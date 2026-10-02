#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.codecov.yml b/.codecov.yml
--- a/.codecov.yml
+++ b/.codecov.yml
@@ -6,6 +6,12 @@ coverage:
         threshold: 1%
         paths:
           - "src/**"
+    patch:
+      default:
+        target: auto
+        threshold: 20%
+        paths:
+          - "src/**"
 
 ignore:
   - "tests/**"
diff --git a/CMakeLists.txt b/CMakeLists.txt
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -244,6 +244,7 @@ if(ENABLE_TESTS)
     add_specbleach_test(test_spp_mmse "test_spp_mmse_noise_estimator.c")
     add_specbleach_test(test_tonal_detector "test_tonal_detector.c")
     add_specbleach_test(test_tonal_reducer "test_tonal_reducer.c")
+    add_specbleach_test(test_hpss_filter "test_hpss_filter.c")
     add_specbleach_test(test_denoiser_post_process "test_denoiser_post_process.c")
 
     if(TARGET PkgConfig::SNDFILE)
diff --git a/include/specbleach_2d_denoiser.h b/include/specbleach_2d_denoiser.h
--- a/include/specbleach_2d_denoiser.h
+++ b/include/specbleach_2d_denoiser.h
@@ -95,6 +95,10 @@ typedef struct SpectralBleach2DDenoiserParameters {
   /* Tonal Separation */
   float tonal_reduction; // 0.0 to 1.0: Independent reduction for tones
 
+  /* HPSS quality mode (0 = Off, 1 = Low, 2 = Mid, 3 = High). Default: 0 (Off)
+   */
+  int hpss_quality_mode;
+
   /* Noise Profile Offset — shifts the noise threshold up/down in dB.
    * Positive values make detection more aggressive (more noise removed).
    * Default: 2.0, Range: [-6.0, +6.0] */
diff --git a/include/specbleach_denoiser.h b/include/specbleach_denoiser.h
--- a/include/specbleach_denoiser.h
+++ b/include/specbleach_denoiser.h
@@ -77,6 +77,10 @@ typedef struct SpectralBleachDenoiserParameters {
   /* Tonal Separation */
   float tonal_reduction; // 0.0 to 1.0: Independent reduction for tones
 
+  /* HPSS quality mode (0 = Off, 1 = Low, 2 = Mid, 3 = High). Default: 0 (Off)
+   */
+  int hpss_quality_mode;
+
   /* Noise Profile Offset — shifts the noise threshold up/down in dB.
    * Positive values make detection more aggressive (more noise removed).
    * Default: 2.0, Range: [-6.0, +6.0] */
diff --git a/src/processors/denoiser/spectral_denoiser.c b/src/processors/denoiser/spectral_denoiser.c
--- a/src/processors/denoiser/spectral_denoiser.c
+++ b/src/processors/denoiser/spectral_denoiser.c
@@ -7,11 +7,13 @@
 #include "shared/denoiser_logic/estimators/adaptive_noise_estimator.h"
 #include "shared/denoiser_logic/estimators/noise_estimator.h"
 #include "shared/denoiser_logic/processing/gain_calculator.h"
+#include "shared/denoiser_logic/processing/hpss_filter.h"
 #include "shared/denoiser_logic/processing/masking_veto.h"
 #include "shared/denoiser_logic/processing/suppression_engine.h"
 #include "shared/denoiser_logic/processing/tonal_reducer.h"
 #include "shared/stft/stft_processor.h"
 #include "shared/utils/critical_bands.h"
+#include "shared/utils/spectral_circular_buffer.h"
 #include "shared/utils/spectral_features.h"
 #include "shared/utils/spectral_smoother.h"
 #include "shared/utils/spectral_utils.h"
@@ -48,6 +50,17 @@ typedef struct SbSpectralDenoiser {
   NoiseFloorManager* noise_floor_manager;
   MaskingVeto* masking_veto;
   SuppressionEngine* suppression_engine;
+  HpssFilter* hpss_filter;
+
+  SbSpectralCircularBuffer* circular_buffer;
+  uint32_t layer_fft;
+  uint32_t layer_noise;
+
+  float* delayed_magnitude;
+  float* mask_harmonic;
+  float* mask_percussive;
+  float* g_h;
+  float* g_p;
 
   int last_adaptive_state;
   int last_noise_estimation_method;
@@ -158,8 +171,40 @@ SpectralProcessorHandle spectral_denoiser_initialize(
       self->real_spectrum_size, self->sample_rate, self->band_type,
       self->spectrum_type, true, USE_TEMPORAL_MASKING_1D_DEFAULT);
 
+  self->circular_buffer = spectral_circular_buffer_create(DELAY_BUFFER_FRAMES);
+  if (!self->circular_buffer) {
+    spectral_denoiser_free(self);
+    return NULL;
+  }
+
+  self->layer_fft =
+      spectral_circular_buffer_add_layer(self->circular_buffer, self->fft_size);
+  self->layer_noise = spectral_circular_buffer_add_layer(
+      self->circular_buffer, self->real_spectrum_size);
+
+  if (self->layer_fft == 0xFFFFFFFFU || self->layer_noise == 0xFFFFFFFFU) {
+    spectral_denoiser_free(self);
+    return NULL;
+  }
+
+  HpssConfig hpss_cfg = {
+      .real_spectrum_size = self->real_spectrum_size,
+      .time_window_size = HPSS_TIME_WINDOW_1D_DEFAULT,
+      .freq_window_size = HPSS_FREQ_WINDOW_1D_DEFAULT,
+  };
+  self->hpss_filter = hpss_filter_initialize(hpss_cfg);
+  self->delayed_magnitude =
+      (float*)calloc(self->real_spectrum_size, sizeof(float));
+  self->mask_harmonic = (float*)calloc(self->real_spectrum_size, sizeof(float));
+  self->mask_percussive =
+      (float*)calloc(self->real_spectrum_size, sizeof(float));
+  self->g_h = (float*)calloc(self->fft_size, sizeof(float));
+  self->g_p = (float*)calloc(self->fft_size, sizeof(float));
+
   if (!self->noise_floor_manager || !self->masking_veto ||
-      !self->suppression_engine) {
+      !self->suppression_engine || !self->hpss_filter ||
+      !self->delayed_magnitude || !self->mask_harmonic ||
+      !self->mask_percussive || !self->g_h || !self->g_p) {
     spectral_denoiser_free(self);
     return NULL;
   }
@@ -176,6 +221,9 @@ void spectral_denoiser_free(SpectralProcessorHandle instance) {
 
   // Don't free noise profile used as reference here
 
+  if (self->circular_buffer) {
+    spectral_circular_buffer_free(self->circular_buffer);
+  }
   if (self->noise_estimator) {
     noise_estimation_free(self->noise_estimator);
   }
@@ -218,6 +266,25 @@ void spectral_denoiser_free(SpectralProcessorHandle instance) {
     tonal_reducer_free(self->tonal_reducer);
   }
 
+  if (self->hpss_filter) {
+    hpss_filter_free(self->hpss_filter);
+  }
+  if (self->delayed_magnitude) {
+    free(self->delayed_magnitude);
+  }
+  if (self->mask_harmonic) {
+    free(self->mask_harmonic);
+  }
+  if (self->mask_percussive) {
+    free(self->mask_percussive);
+  }
+  if (self->g_h) {
+    free(self->g_h);
+  }
+  if (self->g_p) {
+    free(self->g_p);
+  }
+
   free(self);
 }
 
@@ -250,6 +317,11 @@ bool load_reduction_parameters(SpectralProcessorHandle instance,
   self->denoise_parameters = parameters;
   self->aggressiveness = parameters.aggressiveness;
 
+  if (self->hpss_filter) {
+    hpss_filter_set_quality_mode(self->hpss_filter,
+                                 (HpssQualityMode)parameters.hpss_quality_mode);
+  }
+
   return true;
 }
 
@@ -289,40 +361,101 @@ bool spectral_denoiser_run(SpectralProcessorHandle instance,
   };
   denoiser_profile_core_update(profile_params, reference_spectrum);
 
-  // 3. Denoising Stage: Calculate gains and apply psychoacoustic constraints
+  // 2.1 Align internal state and output to the delayed frame (temporal
+  // plumbing)
+  spectral_circular_buffer_push(self->circular_buffer, self->layer_fft,
+                                fft_spectrum);
+  spectral_circular_buffer_push(self->circular_buffer, self->layer_noise,
+                                self->noise_spectrum);
+
+  const uint32_t delay_frames =
+      hpss_filter_get_latency_frames(self->hpss_filter);
+
+  float* delayed_spectrum = spectral_circular_buffer_retrieve(
+      self->circular_buffer, self->layer_fft, delay_frames);
+  float* delayed_noise = spectral_circular_buffer_retrieve(
+      self->circular_buffer, self->layer_noise, delay_frames);
+
+  if (!delayed_spectrum) {
+    delayed_spectrum = fft_spectrum;
+  }
+  if (!delayed_noise) {
+    delayed_noise = self->noise_spectrum;
+  }
+
+  // Align output to delayed frame for post-processing
+  if (delayed_spectrum != fft_spectrum) {
+    memcpy(fft_spectrum, delayed_spectrum, self->fft_size * sizeof(float));
+  }
+
+  // 3. Denoising Stage: HPSS dual-path gain calculation and psychoacoustic
+  // constraints
+  if (!hpss_filter_process(self->hpss_filter, reference_spectrum,
+                           self->delayed_magnitude, self->mask_harmonic,
+                           self->mask_percussive)) {
+    memcpy(self->delayed_magnitude, reference_spectrum,
+           self->real_spectrum_size * sizeof(float));
+    for (uint32_t k = 0U; k < self->real_spectrum_size; ++k) {
+      self->mask_harmonic[k] = 1.0f;
+      self->mask_percussive[k] = 0.0f;
+    }
+  }
+
+  float* input_magnitude = self->delayed_magnitude;
 
   // 3.1. Calculate SNR-dependent oversubtraction factors (Alpha/Beta)
   SuppressionParameters suppression_params = {
       .type = SUPPRESSION_BEROUTI_PER_BIN,
       .strength = self->denoise_parameters.suppression_strength,
       .undersubtraction = 0.0F};
-  suppression_engine_calculate(self->suppression_engine, reference_spectrum,
-                               self->noise_spectrum, suppression_params,
-                               self->alpha, self->beta);
+  suppression_engine_calculate(self->suppression_engine, input_magnitude,
+                               delayed_noise, suppression_params, self->alpha,
+                               self->beta);
+
+  float onset_ratio = hpss_filter_get_onset_ratio(self->hpss_filter);
+  apply_onset_alpha_ducking(self->alpha, self->real_spectrum_size, onset_ratio);
 
   // 3.2. Detect tonal components and boost alpha at tonal bins
-  tonal_reducer_run(self->tonal_reducer, self->noise_spectrum,
+  tonal_reducer_run(self->tonal_reducer, delayed_noise,
                     get_noise_profile(self->noise_profile, MAX),
                     get_noise_profile(self->noise_profile, MEDIAN), self->alpha,
                     self->denoise_parameters.tonal_reduction);
 
   // 3.3. Apply Structural Veto to rescue transients and moderate artifacts
-  masking_veto_apply(self->masking_veto, reference_spectrum,
-                     self->noise_spectrum, NULL, self->alpha,
-                     self->denoise_parameters.masking_depth);
+  masking_veto_apply(self->masking_veto, input_magnitude, delayed_noise, NULL,
+                     self->alpha, self->denoise_parameters.masking_depth);
 
-  // 3.4. Final Gain Calculation
-  calculate_gains(self->real_spectrum_size, self->fft_size, reference_spectrum,
-                  self->noise_spectrum, self->gain_spectrum, self->alpha,
-                  self->beta, self->gain_calculation_type);
+  // 3.4. Dual-Path Gain Engine
+  // 3.4a. Calculate Raw Harmonic Gain G_H and apply temporal & spatial gain
+  // smoothing
+  calculate_gains(self->real_spectrum_size, self->fft_size, input_magnitude,
+                  delayed_noise, self->g_h, self->alpha, self->beta,
+                  self->gain_calculation_type);
 
-  // 3.5. Apply temporal smoothing to calculated suppression gains
   TimeSmoothingParameters spectral_smoothing_parameters =
       (TimeSmoothingParameters){
           .smoothing = self->denoise_parameters.smoothing_factor,
       };
   spectral_smoothing_run(self->spectrum_smoothing,
-                         spectral_smoothing_parameters, self->gain_spectrum);
+                         spectral_smoothing_parameters, self->g_h);
+  if (self->denoise_parameters.smoothing_factor > 0.0f) {
+    int passes = 1 + (int)(self->denoise_parameters.smoothing_factor * 2.0f);
+    for (int p = 0; p < passes; ++p) {
+      spectral_smoothing_apply_spatial(self->g_h, self->real_spectrum_size);
+    }
+  }
+
+  // 3.4b. Calculate Raw Percussive Gain G_P (Bypass temporal smoothing
+  // completely)
+  calculate_gains(self->real_spectrum_size, self->fft_size, input_magnitude,
+                  delayed_noise, self->g_p, self->alpha, self->beta,
+                  self->gain_calculation_type);
+
+  // 3.4c. Recombine gains: G_final = W_H * G_H + W_P * G_P
+  for (uint32_t k = 0U; k < self->real_spectrum_size; ++k) {
+    self->gain_spectrum[k] = self->mask_harmonic[k] * self->g_h[k] +
+                             self->mask_percussive[k] * self->g_p[k];
+  }
 
   // 4. Post-Processing: Final gain management and mixing
   DenoiserPostProcessParams post_params = {
@@ -335,12 +468,15 @@ bool spectral_denoiser_run(SpectralProcessorHandle instance,
       .noise_floor_manager = self->noise_floor_manager,
       .tonal_reducer = self->tonal_reducer,
       .gain_spectrum = self->gain_spectrum,
-      .noise_spectrum = self->noise_spectrum,
+      .noise_spectrum = delayed_noise,
       .fft_spectrum = fft_spectrum,
       .reduction_curve_bias = self->denoise_parameters.reduction_curve_bias,
   };
   denoiser_post_process_apply(post_params);
 
+  // Advance circular buffer write index
+  spectral_circular_buffer_advance(self->circular_buffer);
+
   return true;
 }
 
@@ -365,3 +501,12 @@ const float* spectral_denoiser_get_active_noise_profile(
   SbSpectralDenoiser* self = (SbSpectralDenoiser*)instance;
   return self ? self->noise_spectrum : NULL;
 }
+
+uint32_t spectral_denoiser_get_latency_frames(
+    SpectralProcessorHandle instance) {
+  if (!instance) {
+    return 0;
+  }
+  SbSpectralDenoiser* self = (SbSpectralDenoiser*)instance;
+  return hpss_filter_get_latency_frames(self->hpss_filter);
+}
diff --git a/src/processors/denoiser/spectral_denoiser.h b/src/processors/denoiser/spectral_denoiser.h
--- a/src/processors/denoiser/spectral_denoiser.h
+++ b/src/processors/denoiser/spectral_denoiser.h
@@ -38,6 +38,7 @@ typedef struct DenoiserParameters {
   float suppression_strength;
   float aggressiveness;  /**< -1.0 (Median/Min) to 1.0 (Max), 0.0 (Mean) */
   float tonal_reduction; /**< 0.0 to 1.0 (Phase 3) */
+  int hpss_quality_mode; /**< 0=Off, 1=Low, 2=Medium, 3=High */
   float noise_profile_offset_linear; /**< Linear scalar for noise profile */
   const float* reduction_curve_bias; /**< Per-bin dB bias, NULL = disabled */
   bool reduction_curve_enabled;
@@ -56,5 +57,6 @@ uint32_t spectral_denoiser_get_peaks(SpectralProcessorHandle instance,
                                      float* peak_freqs_hz, uint32_t max_peaks);
 const float* spectral_denoiser_get_active_noise_profile(
     SpectralProcessorHandle instance);
+uint32_t spectral_denoiser_get_latency_frames(SpectralProcessorHandle instance);
 
 #endif
diff --git a/src/processors/denoiser2d/spectral_2d_denoiser.c b/src/processors/denoiser2d/spectral_2d_denoiser.c
--- a/src/processors/denoiser2d/spectral_2d_denoiser.c
+++ b/src/processors/denoiser2d/spectral_2d_denoiser.c
@@ -27,6 +27,7 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 #include "shared/denoiser_logic/estimators/adaptive_noise_estimator.h"
 #include "shared/denoiser_logic/estimators/noise_estimator.h"
 #include "shared/denoiser_logic/processing/gain_calculator.h"
+#include "shared/denoiser_logic/processing/hpss_filter.h"
 #include "shared/denoiser_logic/processing/masking_veto.h"
 #include "shared/denoiser_logic/processing/nlm_filter.h"
 #include "shared/denoiser_logic/processing/suppression_engine.h"
@@ -62,6 +63,7 @@ typedef struct Spectral2DDenoiser {
   SbSpectralCircularBuffer* circular_buffer;
   uint32_t layer_fft;
   uint32_t layer_noise;
+  uint32_t layer_nlm_smoothed;
 
   SpectrumType spectrum_type;
   GainCalculationType gain_calculation_type;
@@ -74,6 +76,13 @@ typedef struct Spectral2DDenoiser {
   MaskingVeto* masking_veto;
   SuppressionEngine* suppression_engine;
   NoiseFloorManager* noise_floor_manager;
+  HpssFilter* hpss_filter;
+
+  float* delayed_magnitude;
+  float* mask_harmonic;
+  float* mask_percussive;
+  float* g_h;
+  float* g_p;
 
   int last_adaptive_state;
   int last_noise_estimation_method;
@@ -182,8 +191,11 @@ SpectralProcessorHandle spectral_2d_denoiser_initialize(
       spectral_circular_buffer_add_layer(self->circular_buffer, self->fft_size);
   self->layer_noise = spectral_circular_buffer_add_layer(
       self->circular_buffer, self->real_spectrum_size);
+  self->layer_nlm_smoothed = spectral_circular_buffer_add_layer(
+      self->circular_buffer, self->real_spectrum_size);
 
-  if (self->layer_fft == 0xFFFFFFFF || self->layer_noise == 0xFFFFFFFF) {
+  if (self->layer_fft == 0xFFFFFFFFU || self->layer_noise == 0xFFFFFFFFU ||
+      self->layer_nlm_smoothed == 0xFFFFFFFFU) {
     spectral_2d_denoiser_free(self);
     return NULL;
   }
@@ -240,7 +252,23 @@ SpectralProcessorHandle spectral_2d_denoiser_initialize(
 
   self->noise_floor_manager = noise_floor_manager_initialize(fft_size);
 
-  if (!self->noise_floor_manager) {
+  HpssConfig hpss_cfg = {
+      .real_spectrum_size = self->real_spectrum_size,
+      .time_window_size = HPSS_TIME_WINDOW_2D_DEFAULT,
+      .freq_window_size = HPSS_FREQ_WINDOW_2D_DEFAULT,
+  };
+  self->hpss_filter = hpss_filter_initialize(hpss_cfg);
+  self->delayed_magnitude =
+      (float*)calloc(self->real_spectrum_size, sizeof(float));
+  self->mask_harmonic = (float*)calloc(self->real_spectrum_size, sizeof(float));
+  self->mask_percussive =
+      (float*)calloc(self->real_spectrum_size, sizeof(float));
+  self->g_h = (float*)calloc(self->fft_size, sizeof(float));
+  self->g_p = (float*)calloc(self->fft_size, sizeof(float));
+
+  if (!self->noise_floor_manager || !self->hpss_filter ||
+      !self->delayed_magnitude || !self->mask_harmonic ||
+      !self->mask_percussive || !self->g_h || !self->g_p) {
     spectral_2d_denoiser_free(self);
     return NULL;
   }
@@ -301,6 +329,25 @@ void spectral_2d_denoiser_free(SpectralProcessorHandle instance) {
     tonal_reducer_free(self->tonal_reducer);
   }
 
+  if (self->hpss_filter) {
+    hpss_filter_free(self->hpss_filter);
+  }
+  if (self->delayed_magnitude) {
+    free(self->delayed_magnitude);
+  }
+  if (self->mask_harmonic) {
+    free(self->mask_harmonic);
+  }
+  if (self->mask_percussive) {
+    free(self->mask_percussive);
+  }
+  if (self->g_h) {
+    free(self->g_h);
+  }
+  if (self->g_p) {
+    free(self->g_p);
+  }
+
   free(self);
 }
 
@@ -333,6 +380,11 @@ bool load_2d_reduction_parameters(SpectralProcessorHandle instance,
   self->parameters = parameters;
   self->aggressiveness = parameters.aggressiveness;
 
+  if (self->hpss_filter) {
+    hpss_filter_set_quality_mode(self->hpss_filter,
+                                 (HpssQualityMode)parameters.hpss_quality_mode);
+  }
+
   // Update NLM h parameter based on smoothing factor (scales h up to 5.0F for
   // strong NLM patch smoothing)
   if (self->nlm_filter) {
@@ -383,90 +435,138 @@ bool spectral_2d_denoiser_run(SpectralProcessorHandle instance,
 
   // 2.1 Align internal state and output to the delayed frame (temporal
   // plumbing)
-  float* delayed_noise = NULL;
-
   // 2.1.1 Push current spectra to circular buffer
   spectral_circular_buffer_push(self->circular_buffer, self->layer_fft,
                                 fft_spectrum);
   spectral_circular_buffer_push(self->circular_buffer, self->layer_noise,
                                 self->noise_spectrum);
 
-  // 2.1.2 Retrieve aligned (delayed) frames
-  const uint32_t delay_frames = nlm_filter_get_latency_frames(self->nlm_filter);
-
-  float* delayed_spectrum = spectral_circular_buffer_retrieve(
-      self->circular_buffer, self->layer_fft, delay_frames);
-
-  delayed_noise = spectral_circular_buffer_retrieve(
-      self->circular_buffer, self->layer_noise, delay_frames);
-
-  // 2.1.3 Align output to the delayed frame by default (Passthrough)
-  memcpy(fft_spectrum, delayed_spectrum, self->fft_size * sizeof(float));
-
-  // 3. Denoising Stage: Calculate gains and apply psychoacoustic constraints
+  // 2.1.2 HPSS Process (operates on current reference_spectrum, outputs
+  // delayed_magnitude and masks at delay L_hpss)
+  if (!hpss_filter_process(self->hpss_filter, reference_spectrum,
+                           self->delayed_magnitude, self->mask_harmonic,
+                           self->mask_percussive)) {
+    memcpy(self->delayed_magnitude, reference_spectrum,
+           self->real_spectrum_size * sizeof(float));
+    for (uint32_t k = 0U; k < self->real_spectrum_size; ++k) {
+      self->mask_harmonic[k] = 1.0f;
+      self->mask_percussive[k] = 0.0f;
+    }
+  }
 
-  // 3.1 Compute SNR for NLM using the CURRENT noise
+  // 2.1.3 Compute SNR for NLM using CURRENT noise and push frame
   nlm_filter_calculate_snr(self->nlm_filter, reference_spectrum,
                            self->noise_spectrum, self->snr_frame);
-
-  // 3.2 Push frame to NLM filter
   nlm_filter_push_frame(self->nlm_filter, self->snr_frame);
 
-  // 3.3. Process NLM filter (internally handles buffering readiness)
+  const uint32_t nlm_delay = nlm_filter_get_latency_frames(self->nlm_filter);
+  const uint32_t hpss_delay = hpss_filter_get_latency_frames(self->hpss_filter);
+  const uint32_t total_delay =
+      (hpss_delay > nlm_delay) ? hpss_delay : nlm_delay;
+
+  float* nlm_intermediate_noise = spectral_circular_buffer_retrieve(
+      self->circular_buffer, self->layer_noise, nlm_delay);
+  if (!nlm_intermediate_noise) {
+    nlm_intermediate_noise = self->noise_spectrum;
+  }
+
+  // Process NLM filter (outputs smoothed SNR at nlm_delay)
   if (nlm_filter_process(self->nlm_filter, self->smoothed_snr)) {
-    // 3.3.1 Convert smoothed SNR back to spectral domain
-    // We reuse self->snr_frame as a temp buffer for smoothed_magnitude
-    float* smoothed_magnitude = self->snr_frame;
     nlm_filter_reconstruct_magnitude(self->nlm_filter, self->smoothed_snr,
-                                     delayed_noise, smoothed_magnitude);
-
-    // 3.3.2 Calculate SNR-dependent oversubtraction factors (Alpha/Beta)
-    SuppressionParameters suppression_params = {
-        .type = SUPPRESSION_BEROUTI_PER_BIN,
-        .strength = self->parameters.suppression_strength,
-        .undersubtraction = 0.0F};
-    suppression_engine_calculate(self->suppression_engine, smoothed_magnitude,
-                                 delayed_noise, suppression_params, self->alpha,
-                                 self->beta);
-
-    // 3.3.3 Detect tonal components and boost alpha at tonal bins
-    tonal_reducer_run(self->tonal_reducer, delayed_noise,
-                      get_noise_profile(self->noise_profile, MAX),
-                      get_noise_profile(self->noise_profile, MEDIAN),
-                      self->alpha, self->parameters.tonal_reduction);
-
-    // 3.3.4 Apply psychoacoustic veto to preserve transients and moderate
-    // artifacts
-    // We pass the CURRENT spectrum (fft_spectrum) as the lookahead for the
-    // DELAYED frame being processed.
-    masking_veto_apply(self->masking_veto, smoothed_magnitude, delayed_noise,
-                       fft_spectrum, self->alpha,
-                       self->parameters.nlm_masking_protection);
-
-    // 3.3.5 Final Gain Calculation
-    calculate_gains(self->real_spectrum_size, self->fft_size,
-                    smoothed_magnitude, delayed_noise, self->gain_spectrum,
-                    self->alpha, self->beta, self->gain_calculation_type);
-
-    // 4. Post-Processing: Final gain management and mixing
-    DenoiserPostProcessParams post_params = {
-        .fft_size = self->fft_size,
-        .real_spectrum_size = self->real_spectrum_size,
-        .reduction_amount = self->parameters.reduction_amount,
-        .tonal_reduction = self->parameters.tonal_reduction,
-        .whitening_factor = self->parameters.whitening_factor,
-        .residual_listen = self->parameters.residual_listen,
-        .noise_floor_manager = self->noise_floor_manager,
-        .tonal_reducer = self->tonal_reducer,
-        .gain_spectrum = self->gain_spectrum,
-        .noise_spectrum = delayed_noise,
-        .fft_spectrum = fft_spectrum,
-        .reduction_curve_bias = self->parameters.reduction_curve_bias,
-    };
-
-    denoiser_post_process_apply(post_params);
+                                     nlm_intermediate_noise, self->snr_frame);
+    spectral_circular_buffer_push(self->circular_buffer,
+                                  self->layer_nlm_smoothed, self->snr_frame);
+  } else {
+    // If NLM not ready yet, push current reference_spectrum
+    spectral_circular_buffer_push(self->circular_buffer,
+                                  self->layer_nlm_smoothed, reference_spectrum);
+  }
+
+  // 2.1.4 Retrieve unified aligned frames at total_delay
+  float* delayed_spectrum = spectral_circular_buffer_retrieve(
+      self->circular_buffer, self->layer_fft, total_delay);
+  float* delayed_noise = spectral_circular_buffer_retrieve(
+      self->circular_buffer, self->layer_noise, total_delay);
+  float* smoothed_magnitude = spectral_circular_buffer_retrieve(
+      self->circular_buffer, self->layer_nlm_smoothed, total_delay - nlm_delay);
+
+  if (!delayed_spectrum) {
+    delayed_spectrum = fft_spectrum;
+  }
+  if (!delayed_noise) {
+    delayed_noise = self->noise_spectrum;
+  }
+  if (!smoothed_magnitude) {
+    smoothed_magnitude = self->delayed_magnitude;
+  }
+
+  // Align output to delayed frame for post-processing
+  if (delayed_spectrum != fft_spectrum) {
+    memcpy(fft_spectrum, delayed_spectrum, self->fft_size * sizeof(float));
   }
 
+  // 3. Denoising Stage: Calculate gains and apply psychoacoustic constraints
+  // 3.1 Calculate SNR-dependent oversubtraction factors (Alpha/Beta)
+  SuppressionParameters suppression_params = {
+      .type = SUPPRESSION_BEROUTI_PER_BIN,
+      .strength = self->parameters.suppression_strength,
+      .undersubtraction = 0.0F};
+  suppression_engine_calculate(self->suppression_engine, smoothed_magnitude,
+                               delayed_noise, suppression_params, self->alpha,
+                               self->beta);
+
+  float onset_ratio = hpss_filter_get_onset_ratio(self->hpss_filter);
+  apply_onset_alpha_ducking(self->alpha, self->real_spectrum_size, onset_ratio);
+  ;
+
+  // 3.2 Detect tonal components and boost alpha at tonal bins
+  tonal_reducer_run(self->tonal_reducer, delayed_noise,
+                    get_noise_profile(self->noise_profile, MAX),
+                    get_noise_profile(self->noise_profile, MEDIAN), self->alpha,
+                    self->parameters.tonal_reduction);
+
+  // 3.3 Apply psychoacoustic veto to preserve transients and moderate artifacts
+  masking_veto_apply(self->masking_veto, smoothed_magnitude, delayed_noise,
+                     fft_spectrum, self->alpha,
+                     self->parameters.nlm_masking_protection);
+
+  // 3.4 Dual-Path Gain Engine
+  // Calculate Harmonic Gain G_H from smoothed harmonic path (NLM smoothed
+  // magnitude)
+  calculate_gains(self->real_spectrum_size, self->fft_size, smoothed_magnitude,
+                  delayed_noise, self->g_h, self->alpha, self->beta,
+                  self->gain_calculation_type);
+
+  // Calculate Percussive Gain G_P from raw delayed magnitude (bypassing NLM
+  // smoothing)
+  calculate_gains(self->real_spectrum_size, self->fft_size,
+                  self->delayed_magnitude, delayed_noise, self->g_p,
+                  self->alpha, self->beta, self->gain_calculation_type);
+
+  // Recombine gains: G_final = W_H * G_H + W_P * G_P
+  for (uint32_t k = 0U; k < self->real_spectrum_size; ++k) {
+    self->gain_spectrum[k] = self->mask_harmonic[k] * self->g_h[k] +
+                             self->mask_percussive[k] * self->g_p[k];
+  }
+
+  // 4. Post-Processing: Final gain management and mixing
+  DenoiserPostProcessParams post_params = {
+      .fft_size = self->fft_size,
+      .real_spectrum_size = self->real_spectrum_size,
+      .reduction_amount = self->parameters.reduction_amount,
+      .tonal_reduction = self->parameters.tonal_reduction,
+      .whitening_factor = self->parameters.whitening_factor,
+      .residual_listen = self->parameters.residual_listen,
+      .noise_floor_manager = self->noise_floor_manager,
+      .tonal_reducer = self->tonal_reducer,
+      .gain_spectrum = self->gain_spectrum,
+      .noise_spectrum = delayed_noise,
+      .fft_spectrum = fft_spectrum,
+      .reduction_curve_bias = self->parameters.reduction_curve_bias,
+  };
+
+  denoiser_post_process_apply(post_params);
+
   // Finalize: Advance circular buffer write index
   spectral_circular_buffer_advance(self->circular_buffer);
 
@@ -487,11 +587,13 @@ uint32_t spectral_2d_denoiser_get_latency_frames(
     SpectralProcessorHandle instance) {
   Spectral2DDenoiser* self = (Spectral2DDenoiser*)instance;
 
-  if (!self || !self->nlm_filter) {
+  if (!self) {
     return 0;
   }
 
-  return nlm_filter_get_latency_frames(self->nlm_filter);
+  uint32_t nlm_latency = nlm_filter_get_latency_frames(self->nlm_filter);
+  uint32_t hpss_latency = hpss_filter_get_latency_frames(self->hpss_filter);
+  return (hpss_latency > nlm_latency) ? hpss_latency : nlm_latency;
 }
 
 const float* spectral_2d_denoiser_get_tonal_mask(
diff --git a/src/processors/denoiser2d/spectral_2d_denoiser.h b/src/processors/denoiser2d/spectral_2d_denoiser.h
--- a/src/processors/denoiser2d/spectral_2d_denoiser.h
+++ b/src/processors/denoiser2d/spectral_2d_denoiser.h
@@ -42,6 +42,7 @@ typedef struct Denoiser2DParameters {
   float suppression_strength;   /**< Suppression aggressiveness (0.0 to 1.0) */
   float aggressiveness;  /**< -1.0 (Median/Min) to 1.0 (Max), 0.0 (Mean) */
   float tonal_reduction; /**< 0.0 to 1.0 (Phase 3) */
+  int hpss_quality_mode; /**< 0=Off, 1=Low, 2=Medium, 3=High */
   float noise_profile_offset_linear; /**< Linear scalar for noise profile */
   const float* reduction_curve_bias; /**< Per-bin dB bias, NULL = disabled */
   bool reduction_curve_enabled;
diff --git a/src/processors/specbleach_2d_denoiser.c b/src/processors/specbleach_2d_denoiser.c
--- a/src/processors/specbleach_2d_denoiser.c
+++ b/src/processors/specbleach_2d_denoiser.c
@@ -58,7 +58,7 @@ SpectralBleachHandle specbleach_2d_initialize(const uint32_t sample_rate,
   }
 
   const uint32_t fft_size = get_stft_fft_size(self->core->stft_processor);
-  self->hop = fft_size / OVERLAP_FACTOR_2D;
+  self->hop = get_stft_hop_size(self->core->stft_processor);
 
   self->spectral_2d_denoiser = spectral_2d_denoiser_initialize(
       sample_rate, fft_size, OVERLAP_FACTOR_2D, self->core->noise_profile);
diff --git a/src/processors/specbleach_denoiser.c b/src/processors/specbleach_denoiser.c
--- a/src/processors/specbleach_denoiser.c
+++ b/src/processors/specbleach_denoiser.c
@@ -31,6 +31,7 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 #include <string.h>
 
 typedef struct SbSpectralDenoiser {
+  uint32_t hop;
   SbProcessorCore* core;
   SpectralProcessorHandle spectral_denoiser;
 } SbSpectralDenoiser;
@@ -53,6 +54,7 @@ SpectralBleachHandle specbleach_initialize(const uint32_t sample_rate,
   }
 
   const uint32_t fft_size = get_stft_fft_size(self->core->stft_processor);
+  self->hop = get_stft_hop_size(self->core->stft_processor);
 
   self->spectral_denoiser = spectral_denoiser_initialize(
       self->core->sample_rate, fft_size, OVERLAP_FACTOR_1D,
@@ -90,7 +92,12 @@ uint32_t specbleach_get_latency(SpectralBleachHandle instance) {
     return 0;
   }
 
-  return get_stft_latency(self->core->stft_processor);
+  uint32_t stft_latency = get_stft_latency(self->core->stft_processor);
+  uint32_t denoiser_latency_frames =
+      spectral_denoiser_get_latency_frames(self->spectral_denoiser);
+  uint32_t denoiser_latency_samples = denoiser_latency_frames * self->hop;
+
+  return stft_latency + denoiser_latency_samples;
 }
 
 bool specbleach_process(SpectralBleachHandle instance,
diff --git a/src/processors/specbleach_processor_core.c b/src/processors/specbleach_processor_core.c
--- a/src/processors/specbleach_processor_core.c
+++ b/src/processors/specbleach_processor_core.c
@@ -40,6 +40,7 @@ DenoiserParameters sb_denoiser_params_sanitize(
       .aggressiveness = parameters.aggressiveness,
       .tonal_reduction =
           from_db_to_coefficient(parameters.tonal_reduction * -1.F),
+      .hpss_quality_mode = parameters.hpss_quality_mode,
       .noise_profile_offset_linear =
           powf(10.0f, fmaxf(NOISE_PROFILE_OFFSET_MIN_DB,
                             fminf(NOISE_PROFILE_OFFSET_MAX_DB,
@@ -68,6 +69,7 @@ Denoiser2DParameters sb_denoiser_2d_params_sanitize(
       .aggressiveness = parameters.aggressiveness,
       .tonal_reduction =
           from_db_to_coefficient(parameters.tonal_reduction * -1.F),
+      .hpss_quality_mode = parameters.hpss_quality_mode,
       .noise_profile_offset_linear =
           powf(10.0f, fmaxf(NOISE_PROFILE_OFFSET_MIN_DB,
                             fminf(NOISE_PROFILE_OFFSET_MAX_DB,
diff --git a/src/shared/configurations.h b/src/shared/configurations.h
--- a/src/shared/configurations.h
+++ b/src/shared/configurations.h
@@ -110,8 +110,8 @@ _Static_assert(sizeof(uint32_t) == 4, "uint32_t must be exactly 32 bits");
 
 // Noise Profile Offset
 #define NOISE_PROFILE_OFFSET_DEFAULT_DB 0.0f
-#define NOISE_PROFILE_OFFSET_MIN_DB (-6.0F)
-#define NOISE_PROFILE_OFFSET_MAX_DB (6.0F)
+#define NOISE_PROFILE_OFFSET_MIN_DB (-12.0F)
+#define NOISE_PROFILE_OFFSET_MAX_DB (12.0F)
 #define ALPHA_MAX_TONAL (10.F)
 #define ALPHA_MIN (1.F)
 #define DEFAULT_OVERSUBTRACTION (ALPHA_MIN)
@@ -206,14 +206,30 @@ _Static_assert(sizeof(uint32_t) == 4, "uint32_t must be exactly 32 bits");
 #define NLM_DISTANCE_THRESHOLD_MULTIPLIER 4.0F
 
 // Must be >= search_time_past + search_time_future + patch_size for NLM caching
-// Using power-of-two (32U) for efficient modulo wrap-around and future headroom
-#define DELAY_BUFFER_FRAMES 32U
+// Using power-of-two (64U) for efficient modulo wrap-around and future headroom
+#define DELAY_BUFFER_FRAMES 64U
+
+#define HPSS_TIME_WINDOW_LOW 9U
+#define HPSS_TIME_WINDOW_MEDIUM 17U
+#define HPSS_TIME_WINDOW_HIGH 33U
+#define HPSS_TIME_WINDOW_MAX HPSS_TIME_WINDOW_HIGH
+
+#define HPSS_FREQ_WINDOW_LOW 9U
+#define HPSS_FREQ_WINDOW_MEDIUM 17U
+#define HPSS_FREQ_WINDOW_HIGH 33U
+
+#define HPSS_BASS_CUTOFF_BINS 24.0F
 
 /* --------------------------------------------------------------- */
 /* ------------------- 1D Denoiser configurations ---------------- */
 #define GAIN_SMOOTHING_MIN_RELEASE_SEC (0.010F)
 #define GAIN_SMOOTHING_MAX_RELEASE_SEC (0.150F)
 
+// HPSS configurations (Defaults to 0 = HPSS_QUALITY_OFF / zero latency)
+#define HPSS_QUALITY_MODE_1D_DEFAULT 0
+#define HPSS_TIME_WINDOW_1D_DEFAULT HPSS_TIME_WINDOW_LOW
+#define HPSS_FREQ_WINDOW_1D_DEFAULT HPSS_FREQ_WINDOW_LOW
+
 // STFT configurations
 #define OVERLAP_FACTOR_1D 4
 #define INPUT_WINDOW_TYPE_1D HANN_WINDOW
@@ -237,6 +253,11 @@ _Static_assert(sizeof(uint32_t) == 4, "uint32_t must be exactly 32 bits");
 /* ------------------- 2D Denoiser configurations ------------------- */
 /* ------------------------------------------------------------------ */
 
+// HPSS configurations (Defaults to 0 = HPSS_QUALITY_OFF / zero latency)
+#define HPSS_QUALITY_MODE_2D_DEFAULT 0
+#define HPSS_TIME_WINDOW_2D_DEFAULT HPSS_TIME_WINDOW_HIGH
+#define HPSS_FREQ_WINDOW_2D_DEFAULT HPSS_FREQ_WINDOW_HIGH
+
 // STFT configurations
 #define OVERLAP_FACTOR_2D 4
 #define INPUT_WINDOW_TYPE_2D HANN_WINDOW
diff --git a/src/shared/denoiser_logic/processing/hpss_filter.c b/src/shared/denoiser_logic/processing/hpss_filter.c
new file mode 100644
--- /dev/null
+++ b/src/shared/denoiser_logic/processing/hpss_filter.c
@@ -0,0 +1,410 @@
+/*
+libspecbleach - A spectral processing library
+
+Copyright 2026 Luciano Dato <lucianodato@gmail.com>
+
+This library is free software; you can redistribute it and/or
+modify it under the terms of the GNU Lesser General Public
+License as published by the Free Software Foundation; either
+version 2.1 of the License, or (at your option) any later version.
+
+This library is distributed in the hope that it will be useful,
+but WITHOUT ANY WARRANTY; without even the implied warranty of
+MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
+Lesser General Public License for more details.
+
+You should have received a copy of the GNU Lesser General Public
+License along with this library; if not, write to the Free Software
+Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
+*/
+
+#include "hpss_filter.h"
+#include "shared/configurations.h"
+#include "shared/utils/spectral_circular_buffer.h"
+#include <math.h>
+#include <stdlib.h>
+#include <string.h>
+
+struct HpssFilter {
+  HpssConfig config;
+  uint32_t latency_frames;
+  SbSpectralCircularBuffer* circular_buffer;
+  uint32_t mag_layer_id;
+
+  float* prev_mag;
+  float* m_h;
+  float* m_p;
+  float* time_sort_buffer;
+  float* onset_boost_buffer;
+  float* onset_ratio_buffer;
+
+  uint32_t write_pos;
+  float delayed_onset_ratio;
+  bool is_initialized_flux;
+};
+
+static float fast_median(float* arr, uint32_t n) {
+  for (uint32_t i = 1U; i < n; ++i) {
+    float key = arr[i];
+    int32_t j = (int32_t)i - 1;
+    while (j >= 0 && arr[j] > key) {
+      arr[j + 1] = arr[j];
+      j--;
+    }
+    arr[j + 1] = key;
+  }
+  if (n % 2U == 1U) {
+    return arr[n / 2U];
+  }
+  return 0.5f * (arr[(n / 2U) - 1U] + arr[n / 2U]);
+}
+
+static void compute_adaptive_freq_median(const float* src, float* dst,
+                                         int num_bins, int max_win_size) {
+  int max_half = max_win_size / 2;
+  if (max_half > 31) {
+    max_half = 31;
+  }
+  float scratch[64];
+
+  for (int k = 0; k < num_bins; k++) {
+    // Scale half-window size: 1 bin at bass, scaling up to max_half at high
+    // frequencies
+    int half_win = k / ((int)HPSS_BASS_CUTOFF_BINS / 2);
+    if (half_win < 1) {
+      half_win = 1; // 3-bin window for bass (k-1, k, k+1)
+    }
+    if (half_win > max_half) {
+      half_win = max_half; // Cap at max_half (e.g. 8 for 17-bin)
+    }
+
+    int start_idx = k - half_win;
+    if (start_idx < 0) {
+      start_idx = 0;
+    }
+
+    int end_idx = k + half_win;
+    if (end_idx >= num_bins) {
+      end_idx = num_bins - 1;
+    }
+
+    int count = end_idx - start_idx + 1;
+
+    for (int i = 0; i < count; i++) {
+      scratch[i] = src[start_idx + i];
+    }
+
+    // Fast insertion sort for small array
+    for (int i = 1; i < count; i++) {
+      float key = scratch[i];
+      int j = i - 1;
+      while (j >= 0 && scratch[j] > key) {
+        scratch[j + 1] = scratch[j];
+        j--;
+      }
+      scratch[j + 1] = key;
+    }
+
+    dst[k] = scratch[count / 2];
+  }
+}
+
+HpssFilter* hpss_filter_initialize(HpssConfig config) {
+  if (config.real_spectrum_size == 0U || config.time_window_size == 0U ||
+      config.freq_window_size == 0U) {
+    return NULL;
+  }
+
+  // Enforce odd window sizes
+  if (config.time_window_size % 2U == 0U) {
+    config.time_window_size += 1U;
+  }
+  if (config.time_window_size > HPSS_TIME_WINDOW_MAX) {
+    config.time_window_size = HPSS_TIME_WINDOW_MAX;
+  }
+  if (config.freq_window_size % 2U == 0U) {
+    config.freq_window_size += 1U;
+  }
+
+  HpssFilter* self = (HpssFilter*)calloc(1U, sizeof(HpssFilter));
+  if (!self) {
+    return NULL;
+  }
+
+  self->config = config;
+  self->latency_frames = (config.time_window_size - 1U) / 2U;
+  self->write_pos = 0U;
+  self->delayed_onset_ratio = 0.0f;
+  self->is_initialized_flux = false;
+
+  // Pre-allocate circular buffer to maximum window size
+  self->circular_buffer = spectral_circular_buffer_create(HPSS_TIME_WINDOW_MAX);
+  if (!self->circular_buffer) {
+    hpss_filter_free(self);
+    return NULL;
+  }
+
+  self->mag_layer_id = spectral_circular_buffer_add_layer(
+      self->circular_buffer, config.real_spectrum_size);
+
+  if (self->mag_layer_id == 0xFFFFFFFFU) {
+    hpss_filter_free(self);
+    return NULL;
+  }
+
+  self->prev_mag = (float*)calloc(config.real_spectrum_size, sizeof(float));
+  self->m_h = (float*)calloc(config.real_spectrum_size, sizeof(float));
+  self->m_p = (float*)calloc(config.real_spectrum_size, sizeof(float));
+  self->time_sort_buffer = (float*)calloc(HPSS_TIME_WINDOW_MAX, sizeof(float));
+  self->onset_boost_buffer =
+      (float*)calloc(HPSS_TIME_WINDOW_MAX, sizeof(float));
+  self->onset_ratio_buffer =
+      (float*)calloc(HPSS_TIME_WINDOW_MAX, sizeof(float));
+
+  if (!self->prev_mag || !self->m_h || !self->m_p || !self->time_sort_buffer ||
+      !self->onset_boost_buffer || !self->onset_ratio_buffer) {
+    hpss_filter_free(self);
+    return NULL;
+  }
+
+  for (uint32_t i = 0U; i < HPSS_TIME_WINDOW_MAX; ++i) {
+    self->onset_boost_buffer[i] = 0.0f;
+    self->onset_ratio_buffer[i] = 0.0f;
+  }
+
+  return self;
+}
+
+void hpss_filter_free(HpssFilter* self) {
+  if (!self) {
+    return;
+  }
+
+  if (self->circular_buffer) {
+    spectral_circular_buffer_free(self->circular_buffer);
+  }
+  if (self->prev_mag) {
+    free(self->prev_mag);
+  }
+  if (self->m_h) {
+    free(self->m_h);
+  }
+  if (self->m_p) {
+    free(self->m_p);
+  }
+  if (self->time_sort_buffer) {
+    free(self->time_sort_buffer);
+  }
+  if (self->onset_boost_buffer) {
+    free(self->onset_boost_buffer);
+  }
+  if (self->onset_ratio_buffer) {
+    free(self->onset_ratio_buffer);
+  }
+  free(self);
+}
+
+void hpss_filter_set_quality_mode(HpssFilter* self, HpssQualityMode mode) {
+  if (!self) {
+    return;
+  }
+
+  uint32_t new_time_win = HPSS_TIME_WINDOW_MEDIUM;
+  uint32_t new_freq_win = HPSS_FREQ_WINDOW_MEDIUM;
+  switch (mode) {
+    case HPSS_QUALITY_OFF:
+      new_time_win = 0U;
+      new_freq_win = 0U;
+      break;
+    case HPSS_QUALITY_LOW:
+      new_time_win = HPSS_TIME_WINDOW_LOW;
+      new_freq_win = HPSS_FREQ_WINDOW_LOW;
+      break;
+    case HPSS_QUALITY_MEDIUM:
+      new_time_win = HPSS_TIME_WINDOW_MEDIUM;
+      new_freq_win = HPSS_FREQ_WINDOW_MEDIUM;
+      break;
+    case HPSS_QUALITY_HIGH:
+      new_time_win = HPSS_TIME_WINDOW_HIGH;
+      new_freq_win = HPSS_FREQ_WINDOW_HIGH;
+      break;
+    default:
+      new_time_win = HPSS_TIME_WINDOW_MEDIUM;
+      new_freq_win = HPSS_FREQ_WINDOW_MEDIUM;
+      break;
+  }
+
+  if (self->config.time_window_size == new_time_win &&
+      self->config.freq_window_size == new_freq_win) {
+    return;
+  }
+
+  if (new_time_win > self->config.time_window_size) {
+    spectral_circular_buffer_clear(self->circular_buffer);
+    self->is_initialized_flux = false;
+  }
+
+  self->config.time_window_size = new_time_win;
+  self->config.freq_window_size = new_freq_win;
+  self->latency_frames = (new_time_win > 0U) ? ((new_time_win - 1U) / 2U) : 0U;
+}
+
+uint32_t hpss_filter_get_latency_frames(const HpssFilter* self) {
+  return self ? self->latency_frames : 0U;
+}
+
+float hpss_filter_get_onset_ratio(const HpssFilter* self) {
+  return self ? self->delayed_onset_ratio : 0.0f;
+}
+
+bool hpss_filter_process(HpssFilter* self, const float* current_magnitude,
+                         float* delayed_magnitude_out, float* mask_harmonic_out,
+                         float* mask_percussive_out) {
+  if (!self || !current_magnitude) {
+    return false;
+  }
+
+  const uint32_t spectrum_size = self->config.real_spectrum_size;
+
+  const uint32_t time_win = self->config.time_window_size;
+  const uint32_t freq_win = self->config.freq_window_size;
+
+  // 1. Multi-band Onset / Spectral Flux Detection (Preserves high-frequency
+  // plucks & attacks)
+  float onset_ratio = 0.0f;
+  float boost_add = 0.0f;
+  if (self->is_initialized_flux) {
+    // Subband flux across 4 frequency regions (Low, Mid-Low, Mid-High, High)
+    const uint32_t bounds[5] = {0U, spectrum_size / 8U, spectrum_size / 4U,
+                                spectrum_size / 2U, spectrum_size};
+    float max_subband_ratio = 0.0f;
+
+    for (int b = 0; b < 4; ++b) {
+      uint32_t start_k = bounds[b];
+      uint32_t end_k = bounds[b + 1];
+      float sub_flux = 0.0f;
+      float sub_prev_sum = 0.0f;
+
+      for (uint32_t k = start_k; k < end_k; ++k) {
+        float diff = current_magnitude[k] - self->prev_mag[k];
+        if (diff > 0.0f) {
+          sub_flux += diff;
+        }
+        sub_prev_sum += self->prev_mag[k];
+      }
+      float sub_ratio = sub_flux / (sub_prev_sum + 1e-6f);
+      if (sub_ratio > max_subband_ratio) {
+        max_subband_ratio = sub_ratio;
+      }
+    }
+
+    onset_ratio = max_subband_ratio;
+    boost_add = 3.0f * onset_ratio;
+    if (boost_add > 3.0f) {
+      boost_add = 3.0f;
+    } else if (boost_add < 0.0f) {
+      boost_add = 0.0f;
+    }
+  } else {
+    self->is_initialized_flux = true;
+  }
+  memcpy(self->prev_mag, current_magnitude, spectrum_size * sizeof(float));
+  self->onset_boost_buffer[self->write_pos] = boost_add;
+  self->onset_ratio_buffer[self->write_pos] = onset_ratio;
+
+  // 2. Push magnitude frames into circular buffer
+  spectral_circular_buffer_push(self->circular_buffer, self->mag_layer_id,
+                                current_magnitude);
+
+  if (self->config.time_window_size == 0U || self->latency_frames == 0U) {
+    if (delayed_magnitude_out) {
+      memcpy(delayed_magnitude_out, current_magnitude,
+             spectrum_size * sizeof(float));
+    }
+    if (mask_harmonic_out) {
+      for (uint32_t k = 0U; k < spectrum_size; ++k) {
+        mask_harmonic_out[k] = 1.0f;
+      }
+    }
+    if (mask_percussive_out) {
+      memset(mask_percussive_out, 0, spectrum_size * sizeof(float));
+    }
+    self->delayed_onset_ratio = 0.0f;
+    self->write_pos = (self->write_pos + 1U) % HPSS_TIME_WINDOW_MAX;
+    spectral_circular_buffer_advance(self->circular_buffer);
+    return true;
+  }
+
+  // 3. Retrieve delayed frame
+  const float* delayed_mag = spectral_circular_buffer_retrieve(
+      self->circular_buffer, self->mag_layer_id, self->latency_frames);
+
+  if (!delayed_mag) {
+    return false;
+  }
+
+  if (delayed_magnitude_out) {
+    memcpy(delayed_magnitude_out, delayed_mag, spectrum_size * sizeof(float));
+  }
+
+  uint32_t delayed_idx =
+      (self->write_pos + HPSS_TIME_WINDOW_MAX - self->latency_frames) %
+      HPSS_TIME_WINDOW_MAX;
+  float frame_onset_boost = self->onset_boost_buffer[delayed_idx];
+  self->delayed_onset_ratio = self->onset_ratio_buffer[delayed_idx];
+
+  // 4. Median Filtering
+  // 4a. Harmonic median (M_H) along time axis for each frequency bin
+  const float* frames[HPSS_TIME_WINDOW_MAX];
+  for (uint32_t t = 0U; t < time_win; ++t) {
+    frames[t] = spectral_circular_buffer_retrieve(self->circular_buffer,
+                                                  self->mag_layer_id, t);
+  }
+
+  for (uint32_t k = 0U; k < spectrum_size; ++k) {
+    for (uint32_t t = 0U; t < time_win; ++t) {
+      self->time_sort_buffer[t] = frames[t] ? frames[t][k] : 0.0f;
+    }
+    self->m_h[k] = fast_median(self->time_sort_buffer, time_win);
+  }
+
+  // 4b. Percussive median (M_P) along frequency axis for delayed frame
+  compute_adaptive_freq_median(delayed_mag, self->m_p, (int)spectrum_size,
+                               (int)freq_win);
+
+  // 5. Onset-Boosted Soft Masking with Transient Excess Margin
+  // In stationary noise (M_P ~= M_H), excess is zero -> 100% smoothed harmonic
+  // path G_H to eliminate musical noise
+  for (uint32_t k = 0U; k < spectrum_size; ++k) {
+    float m_h = self->m_h[k];
+    float m_p_boosted = self->m_p[k] * (1.0f + frame_onset_boost);
+
+    float p_diff = m_p_boosted - m_h;
+    float p_excess = (p_diff > 0.0f) ? p_diff : 0.0f;
+
+    float m_h_sq = m_h * m_h;
+    float p_excess_sq = p_excess * p_excess;
+    float sum_sq = m_h_sq + p_excess_sq;
+
+    float w_p = 0.0f;
+    float w_h = 1.0f;
+    if (sum_sq > SPECTRAL_EPSILON) {
+      float inv_sum_sq = 1.0f / sum_sq;
+      w_p = p_excess_sq * inv_sum_sq;
+      w_h = 1.0f - w_p;
+    }
+
+    if (mask_harmonic_out) {
+      mask_harmonic_out[k] = w_h;
+    }
+    if (mask_percussive_out) {
+      mask_percussive_out[k] = w_p;
+    }
+  }
+
+  // 6. Advance circular buffer and write position
+  self->write_pos = (self->write_pos + 1U) % HPSS_TIME_WINDOW_MAX;
+  spectral_circular_buffer_advance(self->circular_buffer);
+
+  return true;
+}
diff --git a/src/shared/denoiser_logic/processing/hpss_filter.h b/src/shared/denoiser_logic/processing/hpss_filter.h
new file mode 100644
--- /dev/null
+++ b/src/shared/denoiser_logic/processing/hpss_filter.h
@@ -0,0 +1,61 @@
+/*
+libspecbleach - A spectral processing library
+
+Copyright 2026 Luciano Dato <lucianodato@gmail.com>
+
+This library is free software; you can redistribute it and/or
+modify it under the terms of the GNU Lesser General Public
+License as published by the Free Software Foundation; either
+version 2.1 of the License, or (at your option) any later version.
+
+This library is distributed in the hope that it will be useful,
+but WITHOUT ANY WARRANTY; without even the implied warranty of
+MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
+Lesser General Public License for more details.
+
+You should have received a copy of the GNU Lesser General Public
+License along with this library; if not, write to the Free Software
+Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
+*/
+
+#ifndef SHARED_DENOISER_LOGIC_HPSS_FILTER_H
+#define SHARED_DENOISER_LOGIC_HPSS_FILTER_H
+
+#include "shared/configurations.h"
+#include <stdbool.h>
+#include <stdint.h>
+
+#ifndef HPSS_QUALITY_MODE_DEFINED
+#define HPSS_QUALITY_MODE_DEFINED
+typedef enum HpssQualityMode {
+  HPSS_QUALITY_OFF = 0,    // Bypassed (Lookahead: 0)
+  HPSS_QUALITY_LOW = 1,    // L_time = 9 frames (Lookahead: 4)
+  HPSS_QUALITY_MEDIUM = 2, // L_time = 17 frames (Lookahead: 8)
+  HPSS_QUALITY_HIGH = 3    // L_time = 33 frames (Lookahead: 16)
+} HpssQualityMode;
+#endif
+
+typedef struct HpssFilter HpssFilter;
+
+typedef struct HpssConfig {
+  uint32_t real_spectrum_size;
+  uint32_t time_window_size; // Default: 17 frames
+  uint32_t freq_window_size; // Default: 17 bins
+} HpssConfig;
+
+// Pre-allocates ring buffers to HPSS_TIME_WINDOW_MAX
+HpssFilter* hpss_filter_initialize(HpssConfig config);
+void hpss_filter_free(HpssFilter* self);
+
+// Dynamic parameter update (allocator-free)
+void hpss_filter_set_quality_mode(HpssFilter* self, HpssQualityMode mode);
+
+// Returns current lookahead delay in frames: (current_time_window - 1) / 2
+uint32_t hpss_filter_get_latency_frames(const HpssFilter* self);
+float hpss_filter_get_onset_ratio(const HpssFilter* self);
+
+bool hpss_filter_process(HpssFilter* self, const float* current_magnitude,
+                         float* delayed_magnitude_out, float* mask_harmonic_out,
+                         float* mask_percussive_out);
+
+#endif // SHARED_DENOISER_LOGIC_HPSS_FILTER_H
diff --git a/src/shared/stft/stft_processor.c b/src/shared/stft/stft_processor.c
--- a/src/shared/stft/stft_processor.c
+++ b/src/shared/stft/stft_processor.c
@@ -161,21 +161,28 @@ bool stft_processor_run(StftProcessor* self, const uint32_t number_of_samples,
   return true;
 }
 
-uint32_t get_stft_latency(StftProcessor* self) {
+uint32_t get_stft_latency(const StftProcessor* self) {
   if (!self) {
     return 0;
   }
   return self->input_latency;
 }
 
-uint32_t get_stft_fft_size(StftProcessor* self) {
+uint32_t get_stft_hop_size(const StftProcessor* self) {
+  if (!self) {
+    return 0;
+  }
+  return self->hop;
+}
+
+uint32_t get_stft_fft_size(const StftProcessor* self) {
   if (!self) {
     return 0;
   }
   return self->fft_size;
 }
 
-uint32_t get_stft_real_spectrum_size(StftProcessor* self) {
+uint32_t get_stft_real_spectrum_size(const StftProcessor* self) {
   if (!self) {
     return 0;
   }
diff --git a/src/shared/stft/stft_processor.h b/src/shared/stft/stft_processor.h
--- a/src/shared/stft/stft_processor.h
+++ b/src/shared/stft/stft_processor.h
@@ -34,9 +34,10 @@ StftProcessor* stft_processor_initialize(
     ZeroPaddingType padding_type, uint32_t zeropadding_amount,
     WindowTypes input_window, WindowTypes output_window);
 void stft_processor_free(StftProcessor* self);
-uint32_t get_stft_latency(StftProcessor* self);
-uint32_t get_stft_fft_size(StftProcessor* self);
-uint32_t get_stft_real_spectrum_size(StftProcessor* self);
+uint32_t get_stft_latency(const StftProcessor* self);
+uint32_t get_stft_hop_size(const StftProcessor* self);
+uint32_t get_stft_fft_size(const StftProcessor* self);
+uint32_t get_stft_real_spectrum_size(const StftProcessor* self);
 
 // Receives an input and output buffer with a a number_of_samples and does the
 // STFT transform applying any spectral_processing. It works similar to qsort,
diff --git a/src/shared/utils/spectral_circular_buffer.c b/src/shared/utils/spectral_circular_buffer.c
--- a/src/shared/utils/spectral_circular_buffer.c
+++ b/src/shared/utils/spectral_circular_buffer.c
@@ -105,6 +105,20 @@ void spectral_circular_buffer_advance(SbSpectralCircularBuffer* self) {
   self->write_index = (self->write_index + 1) % self->num_frames;
 }
 
+void spectral_circular_buffer_clear(SbSpectralCircularBuffer* self) {
+  if (!self) {
+    return;
+  }
+
+  for (uint32_t i = 0; i < self->num_layers; i++) {
+    if (self->layers[i].buffer) {
+      memset(self->layers[i].buffer, 0,
+             (size_t)self->num_frames * self->layers[i].size * sizeof(float));
+    }
+  }
+  self->write_index = 0;
+}
+
 void spectral_circular_buffer_free(SbSpectralCircularBuffer* self) {
   if (!self) {
     return;
diff --git a/src/shared/utils/spectral_circular_buffer.h b/src/shared/utils/spectral_circular_buffer.h
--- a/src/shared/utils/spectral_circular_buffer.h
+++ b/src/shared/utils/spectral_circular_buffer.h
@@ -84,6 +84,13 @@ float* spectral_circular_buffer_retrieve(SbSpectralCircularBuffer* self,
  */
 void spectral_circular_buffer_advance(SbSpectralCircularBuffer* self);
 
+/**
+ * @brief Clear all layers and reset write index in the circular buffer.
+ *
+ * @param self The circular buffer instance.
+ */
+void spectral_circular_buffer_clear(SbSpectralCircularBuffer* self);
+
 /**
  * @brief Destroy the circular buffer and free all associated memory.
  *
diff --git a/src/shared/utils/spectral_smoother.c b/src/shared/utils/spectral_smoother.c
--- a/src/shared/utils/spectral_smoother.c
+++ b/src/shared/utils/spectral_smoother.c
@@ -107,12 +107,20 @@ bool spectral_smoothing_run(SpectralSmoother* self,
       (p * (GAIN_SMOOTHING_MAX_RELEASE_SEC - GAIN_SMOOTHING_MIN_RELEASE_SEC));
   float dt = ((float)self->fft_size / (float)self->overlap_factor) /
              (float)self->sample_rate;
-  float alpha = expf(-dt / tau_sec);
+  float alpha_release = expf(-dt / tau_sec);
 
   uint32_t k = 0U;
   for (k = 0U; k < self->real_spectrum_size; k++) {
-    gains[k] = (alpha * self->smoothed_spectrum_previous[k]) +
-               ((1.0F - alpha) * gains[k]);
+    float target = gains[k];
+    float prev = self->smoothed_spectrum_previous[k];
+    if (target >= prev) {
+      // Instant attack: gain opens immediately so onsets and attacks are never
+      // eaten
+      gains[k] = target;
+    } else {
+      // Smooth release: gain decays slowly to eliminate musical noise
+      gains[k] = (alpha_release * prev) + ((1.0F - alpha_release) * target);
+    }
     self->smoothed_spectrum_previous[k] = gains[k];
   }
 
@@ -128,8 +136,8 @@ void spectral_smoothing_apply_spatial(float* data, uint32_t size) {
   uint32_t i = 0U;
   for (i = 1U; i < size; i++) {
     float curr = data[i];
-    data[i] = 0.25F * prev + 0.5F * curr +
-              0.25F * (i + 1 < size ? data[i + 1] : curr);
+    data[i] = (0.25F * prev) + (0.5F * curr) +
+              (0.25F * (i + 1 < size ? data[i + 1] : curr));
     prev = curr;
   }
 }
@@ -142,7 +150,7 @@ void spectral_smoothing_apply_simple_temporal(float* current, float* memory,
 
   uint32_t i = 0U;
   for (i = 0U; i < size; i++) {
-    current[i] = smoothing * memory[i] + (1.0F - smoothing) * current[i];
+    current[i] = (smoothing * memory[i]) + ((1.0F - smoothing) * current[i]);
     memory[i] = current[i];
   }
 }
diff --git a/src/shared/utils/spectral_utils.c b/src/shared/utils/spectral_utils.c
--- a/src/shared/utils/spectral_utils.c
+++ b/src/shared/utils/spectral_utils.c
@@ -292,3 +292,21 @@ bool get_morphed_profile(float* output_profile, const float* mean_profile,
 
   return true;
 }
+
+void apply_onset_alpha_ducking(float* alpha, uint32_t num_bins,
+                               float onset_ratio) {
+  if (!alpha || onset_ratio <= 0.01f || num_bins == 0U) {
+    return;
+  }
+
+  float reduction = onset_ratio * 2.0f;
+  if (reduction > 1.0f) {
+    reduction = 1.0f;
+  }
+
+  for (uint32_t k = 0U; k < num_bins; k++) {
+    // Duck alpha down toward 1.0 (no over-subtraction) on attack frame across
+    // full spectrum
+    alpha[k] = 1.0f + ((alpha[k] - 1.0f) * (1.0f - reduction));
+  }
+}
diff --git a/src/shared/utils/spectral_utils.h b/src/shared/utils/spectral_utils.h
--- a/src/shared/utils/spectral_utils.h
+++ b/src/shared/utils/spectral_utils.h
@@ -71,6 +71,8 @@ bool get_morphed_profile(float* output_profile, const float* mean_profile,
                          const float* median_profile, const float* max_profile,
                          const float* min_profile, uint32_t size,
                          float aggressiveness);
+void apply_onset_alpha_ducking(float* alpha, uint32_t num_bins,
+                               float onset_ratio);
 
 #include "shared/utils/general_utils.h"
 
diff --git a/src/shared/utils/transient_detector.c b/src/shared/utils/transient_detector.c
--- a/src/shared/utils/transient_detector.c
+++ b/src/shared/utils/transient_detector.c
@@ -101,7 +101,7 @@ bool transient_detector_process(TransientDetector* self,
 
     // Update background energy tracking (exponential filter)
     self->smoothed_items[j] =
-        self->alpha * smoothed + (1.0F - self->alpha) * current;
+        (self->alpha * smoothed) + ((1.0F - self->alpha) * current);
   }
 
   return transient_detected;
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
