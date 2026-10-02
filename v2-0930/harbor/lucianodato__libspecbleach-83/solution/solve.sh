#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/examples/denoiser_demo.c b/examples/denoiser_demo.c
--- a/examples/denoiser_demo.c
+++ b/examples/denoiser_demo.c
@@ -94,8 +94,8 @@ int main(int argc, char** argv) {
   SpectralBleachDenoiserParameters parameters =
       (SpectralBleachDenoiserParameters){
           .residual_listen = false,
-          .learn_noise = 1,          // Learn all modes
-          .noise_reduction_mode = 3, // Use maximum mode for processing
+          .learn_noise = 1,       // Learn all modes
+          .aggressiveness = 1.0f, // Use maximum mode for processing
           .reduction_amount = 20.F,
           .smoothing_factor = 0.F,
           .whitening_factor = 50.F,
@@ -108,7 +108,7 @@ int main(int argc, char** argv) {
       {"smoothing", required_argument, 0, 's'},
       {"masking-depth", required_argument, 0, 'd'},
       {"masking-elasticity", required_argument, 0, 'e'},
-      {"learn-avg", required_argument, 0, 'l'},
+      {"steering-response", required_argument, 0, 'l'},
       {"adaptive", no_argument, 0, 'a'},
       {"noise-method", required_argument, 0, 'm'},
       {"frame-size", required_argument, 0, 'f'},
@@ -138,7 +138,7 @@ int main(int argc, char** argv) {
         parameters.masking_elasticity = (float)atof(optarg);
         break;
       case 'l':
-        parameters.noise_reduction_mode = atoi(optarg);
+        parameters.aggressiveness = (float)atof(optarg);
         break;
       case 'a':
         parameters.adaptive_noise = 1;
@@ -269,7 +269,7 @@ int main(int argc, char** argv) {
     // If we broke out of the learn stage due to an error, stop.
     // In adaptive mode, we can proceed even without a pre-learned profile.
     if (!parameters.adaptive_noise &&
-        !specbleach_noise_profile_available(lib_instance)) {
+        !specbleach_noise_profile_available_for_mode(lib_instance, 1)) {
       fprintf(stderr, "Error: Noise profile was not successfully learned\n");
       break;
     }
diff --git a/include/specbleach_2d_denoiser.h b/include/specbleach_2d_denoiser.h
--- a/include/specbleach_2d_denoiser.h
+++ b/include/specbleach_2d_denoiser.h
@@ -40,18 +40,6 @@ typedef struct SpectralBleach2DDenoiserParameters {
    * 0 is disabled, 1 will learn all profile types simultaneously.
    */
   int learn_noise;
-
-  /**
-   * Sets the noise reduction mode to use when learning is disabled.
-   * 1 will use the average profile, 2 will use the median profile
-   * and 3 will use the max profile.
-   */
-  int noise_reduction_mode;
-
-  /**
-   * Enables outputting the residue of the reduction processing.
-   * It's either true or false.
-   */
   bool residual_listen;
 
   /**
@@ -101,11 +89,16 @@ typedef struct SpectralBleach2DDenoiserParameters {
    */
   float masking_elasticity;
 
-  /**
-   * Sets the suppression aggressiveness (0-100%).
+  /** Sets the suppression aggressiveness (0-100%).
    * Controls the SNR-dependent oversubtraction factor.
    */
   float suppression_strength;
+
+  /* Intelligent Steering */
+  float aggressiveness; /**< -1.0 (Median/Min) to 1.0 (Max), 0.0 (Mean) */
+
+  /* Tonal Separation */
+  float tonal_reduction; // 0.0 to 1.0: Independent reduction for tones
 } SpectralBleach2DDenoiserParameters;
 
 /**
@@ -150,49 +143,24 @@ uint32_t specbleach_2d_get_latency(SpectralBleachHandle instance);
  */
 uint32_t specbleach_2d_get_noise_profile_size(SpectralBleachHandle instance);
 
-/**
- * Returns the number of blocks used for the noise profile calculation.
- */
-uint32_t specbleach_2d_get_noise_profile_blocks_averaged(
-    SpectralBleachHandle instance);
-
-/**
- * Returns a pointer to the noise profile calculated inside the instance.
- */
-float* specbleach_2d_get_noise_profile(SpectralBleachHandle instance);
-
-/**
- * Allows to load a custom noise profile.
- */
-bool specbleach_2d_load_noise_profile(SpectralBleachHandle instance,
-                                      const float* restored_profile,
-                                      uint32_t profile_size,
-                                      uint32_t profile_blocks);
-
 /**
  * Allows to load a custom noise profile for a specific mode.
  */
 bool specbleach_2d_load_noise_profile_for_mode(SpectralBleachHandle instance,
                                                const float* restored_profile,
                                                uint32_t profile_size,
-                                               uint32_t profile_blocks,
-                                               int mode);
+                                               uint32_t block_count, int mode);
 
 /**
  * Resets the internal noise profile of the library instance.
  */
 bool specbleach_2d_reset_noise_profile(SpectralBleachHandle instance);
 
-/**
- * Returns if the instance has a noise profile calculated internally.
- */
-bool specbleach_2d_noise_profile_available(SpectralBleachHandle instance);
-
 /**
  * Returns the number of blocks used for the noise profile calculation for a
  * specific mode.
  */
-uint32_t specbleach_2d_get_noise_profile_blocks_averaged_for_mode(
+uint32_t specbleach_2d_get_noise_profile_block_count_for_mode(
     SpectralBleachHandle instance, int mode);
 
 /**
diff --git a/include/specbleach_denoiser.h b/include/specbleach_denoiser.h
--- a/include/specbleach_denoiser.h
+++ b/include/specbleach_denoiser.h
@@ -35,11 +35,6 @@ typedef struct SpectralBleachDenoiserParameters {
    * 0 is disabled, 1 will learn all profile types simultaneously. */
   int learn_noise;
 
-  /* Sets the noise reduction mode to use when learning is disabled.
-   * 1 will use the average profile, 2 will use the median profile
-   * and 3 will use the max profile. */
-  int noise_reduction_mode;
-
   /* Enables outputting the residue of the reduction processing. It's either
    * true or false */
   bool residual_listen;
@@ -66,7 +61,9 @@ typedef struct SpectralBleachDenoiserParameters {
   int adaptive_noise;
 
   /* Sets the method used for adaptive noise estimation.
-   * 1: SPP-MMSE method (unbiased estimation) */
+   * 0: SPP-MMSE method (unbiased estimation)
+   * 1: Brandt (Trimmed Mean)
+   * 2: Martin Minimum Statistics */
   int noise_estimation_method;
 
   /** Masking Veto depth (0.0 - 1.0) */
@@ -75,6 +72,11 @@ typedef struct SpectralBleachDenoiserParameters {
 
   /** Suppression aggressiveness (0.0 - 1.0) */
   float suppression_strength; // 0.0 - 1.0: Berouti oversubtraction factor
+
+  /* Intelligent Steering */
+  float aggressiveness; /**< -1.0 (Median/Min) to 1.0 (Max), 0.0 (Mean) */
+  /* Tonal Separation */
+  float tonal_reduction; // 0.0 to 1.0: Independent reduction for tones
 } SpectralBleachDenoiserParameters;
 
 /**
@@ -108,43 +110,23 @@ uint32_t specbleach_get_latency(SpectralBleachHandle instance);
  * Returns the size of the noise profile spectrum
  */
 uint32_t specbleach_get_noise_profile_size(SpectralBleachHandle instance);
-/**
- * Returns a pointer to the noise profile calculated inside the instance
- */
-float* specbleach_get_noise_profile(SpectralBleachHandle instance);
-/**
- * Allows to load a custom noise profile
- */
-bool specbleach_load_noise_profile(SpectralBleachHandle instance,
-                                   const float* restored_profile,
-                                   uint32_t profile_size,
-                                   uint32_t profile_blocks);
 /**
  * Allows to load a custom noise profile for a specific mode
  */
 bool specbleach_load_noise_profile_for_mode(SpectralBleachHandle instance,
                                             const float* restored_profile,
                                             uint32_t profile_size,
-                                            uint32_t profile_blocks, int mode);
+                                            uint32_t block_count, int mode);
 /**
  * Resets the internal noise profile of the library instance
  */
 bool specbleach_reset_noise_profile(SpectralBleachHandle instance);
-/**
- * Returns if the instance has a noise profile calculated internally
- */
-bool specbleach_noise_profile_available(SpectralBleachHandle instance);
-/**
- * Returns the number of blocks used for the noise profile calculation
- */
-uint32_t specbleach_get_noise_profile_blocks_averaged(
-    SpectralBleachHandle instance);
 
 /**
  * Returns the number of blocks used for the noise profile calculation for a
  * specific mode
  */
-uint32_t specbleach_get_noise_profile_blocks_averaged_for_mode(
+uint32_t specbleach_get_noise_profile_block_count_for_mode(
     SpectralBleachHandle instance, int mode);
 
 /**
diff --git a/src/processors/denoiser/spectral_denoiser.c b/src/processors/denoiser/spectral_denoiser.c
--- a/src/processors/denoiser/spectral_denoiser.c
+++ b/src/processors/denoiser/spectral_denoiser.c
@@ -24,6 +24,7 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 #include "shared/gain_estimation/suppression_engine.h"
 #include "shared/noise_estimation/adaptive_noise_estimator.h"
 #include "shared/noise_estimation/noise_estimator.h"
+#include "shared/noise_estimation/tonal_detector.h"
 #include "shared/post_estimation/masking_veto.h"
 #include "shared/post_estimation/noise_floor_manager.h"
 #include "shared/pre_estimation/critical_bands.h"
@@ -32,6 +33,7 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 #include "shared/utils/spectral_features.h"
 #include "shared/utils/spectral_utils.h"
 #include <float.h>
+#include <math.h>
 #include <stdlib.h>
 #include <string.h>
 
@@ -49,6 +51,7 @@ typedef struct SbSpectralDenoiser {
   float* noise_spectrum;
   float* manual_noise_floor;
   float* noisy_reference;
+  float* tonal_mask;
 
   SpectrumType spectrum_type;
   CriticalBandType band_type;
@@ -69,8 +72,9 @@ typedef struct SbSpectralDenoiser {
   bool whitening_enabled;
 
   int last_adaptive_state;
-  int last_noise_reduction_mode;
   int last_noise_estimation_method;
+  float aggressiveness;
+  bool was_learning;
 } SbSpectralDenoiser;
 
 SpectralProcessorHandle spectral_denoiser_initialize(
@@ -134,7 +138,10 @@ SpectralProcessorHandle spectral_denoiser_initialize(
       (float*)calloc(self->real_spectrum_size, sizeof(float));
   self->noisy_reference =
       (float*)calloc(self->real_spectrum_size, sizeof(float));
-  if (!self->manual_noise_floor || !self->noisy_reference) {
+  self->tonal_mask = (float*)calloc(self->real_spectrum_size, sizeof(float));
+
+  if (!self->manual_noise_floor || !self->noisy_reference ||
+      !self->tonal_mask) {
     spectral_denoiser_free(self);
     return NULL;
   }
@@ -169,6 +176,11 @@ SpectralProcessorHandle spectral_denoiser_initialize(
 
   self->noise_floor_manager = noise_floor_manager_initialize(
       self->fft_size, self->sample_rate, self->hop);
+
+  self->was_learning = false;
+  self->aggressiveness = 0.0f;
+  self->denoise_parameters.tonal_reduction = 0.0f;
+
   self->masking_veto = masking_veto_initialize(
       self->fft_size, self->sample_rate, self->spectrum_type);
   self->suppression_engine =
@@ -235,6 +247,9 @@ void spectral_denoiser_free(SpectralProcessorHandle instance) {
   if (self->noisy_reference) {
     free(self->noisy_reference);
   }
+  if (self->tonal_mask) {
+    free(self->tonal_mask);
+  }
 
   free(self);
 }
@@ -266,6 +281,7 @@ bool load_reduction_parameters(SpectralProcessorHandle instance,
   }
 
   self->denoise_parameters = parameters;
+  self->aggressiveness = parameters.aggressiveness;
 
   return true;
 }
@@ -284,70 +300,85 @@ bool spectral_denoiser_run(SpectralProcessorHandle instance,
 
   if (self->denoise_parameters.learn_noise > 0) {
     // Learn all modes simultaneously
-    for (int mode = ROLLING_MEAN; mode <= MAX; mode++) {
+    for (int mode = ROLLING_MEAN; mode <= MINIMUM; mode++) {
       noise_estimation_run(self->noise_estimator, (NoiseEstimatorType)mode,
                            reference_spectrum);
     }
+    self->was_learning = true;
     return true;
   }
 
-  // --- Denoising Path ---
-
-  // Always keep manual floor updated from the current mode
-  float* current_profile = get_noise_profile(
-      self->noise_profile, self->denoise_parameters.noise_reduction_mode);
-  if (current_profile) {
-    memcpy(self->manual_noise_floor, current_profile,
-           self->real_spectrum_size * sizeof(float));
-  } else {
-    memset(self->manual_noise_floor, 0,
-           self->real_spectrum_size * sizeof(float));
+  if (self->was_learning) {
+    // User just stopped learning -> Finalize all captures
+    for (int mode = ROLLING_MEAN; mode <= MINIMUM; mode++) {
+      noise_estimation_finalize(self->noise_estimator,
+                                (NoiseEstimatorType)mode);
+    }
+    self->was_learning = false;
   }
 
+  // --- Denoising Path ---
+
   if (self->denoise_parameters.adaptive_noise && self->adaptive_estimator) {
-    // Check for state transitions (Adaptive OFF->ON or Mode Change)
+    // ... (Adaptive logic remains similar but uses morphed profile as base)
+    // Check for state transitions
     bool state_changed = !self->last_adaptive_state;
-    bool mode_changed = self->last_noise_reduction_mode !=
-                        self->denoise_parameters.noise_reduction_mode;
+    bool mode_changed = fabsf(self->aggressiveness -
+                              self->denoise_parameters.aggressiveness) > 0.01f;
 
     if (state_changed || mode_changed) {
-      // Re-seed the adaptive estimator to the new chosen base profile
+      // Calculate morphed base profile
+      get_morphed_profile(self->manual_noise_floor,
+                          get_noise_profile(self->noise_profile, ROLLING_MEAN),
+                          get_noise_profile(self->noise_profile, MEDIAN),
+                          get_noise_profile(self->noise_profile, MAX),
+                          get_noise_profile(self->noise_profile, MINIMUM),
+                          self->real_spectrum_size,
+                          self->denoise_parameters.aggressiveness);
+
       adaptive_estimator_update_seed(self->adaptive_estimator,
                                      self->manual_noise_floor);
 
       self->last_adaptive_state = 1;
-      self->last_noise_reduction_mode =
-          self->denoise_parameters.noise_reduction_mode;
+      self->aggressiveness = self->denoise_parameters.aggressiveness;
     }
 
     // Run adaptive estimator
     adaptive_estimator_run(self->adaptive_estimator, reference_spectrum,
                            self->noise_spectrum);
 
-    // Apply manual profile as a floor to the internal state and output
+    // Apply morphed profile as a floor
     adaptive_estimator_apply_floor(self->adaptive_estimator,
                                    self->manual_noise_floor);
-
     for (uint32_t k = 0U; k < self->real_spectrum_size; k++) {
       if (self->noise_spectrum[k] < self->manual_noise_floor[k]) {
         self->noise_spectrum[k] = self->manual_noise_floor[k];
       }
     }
+
+    // Smooth the morphed/refined floor every frame to eliminate
+    // residual musical noise in specific steering modes (e.g. Median)
+    smooth_spectrum(self->noise_spectrum, self->real_spectrum_size, 0.5f);
   } else {
     // Manual Denoising Mode
     self->last_adaptive_state = 0;
 
-    if (is_noise_estimation_available(
-            self->noise_profile,
-            self->denoise_parameters.noise_reduction_mode)) {
-      memcpy(self->noise_spectrum, self->manual_noise_floor,
-             self->real_spectrum_size * sizeof(float));
-    } else {
-      // No profile available
-      return true;
-    }
+    // Use morphed profile
+    get_morphed_profile(self->noise_spectrum,
+                        get_noise_profile(self->noise_profile, ROLLING_MEAN),
+                        get_noise_profile(self->noise_profile, MEDIAN),
+                        get_noise_profile(self->noise_profile, MAX),
+                        get_noise_profile(self->noise_profile, MINIMUM),
+                        self->real_spectrum_size,
+                        self->denoise_parameters.aggressiveness);
   }
 
+  // 3. Detect tonal components
+  detect_tonal_components(self->noise_spectrum,
+                          get_noise_profile(self->noise_profile, MAX),
+                          get_noise_profile(self->noise_profile, MEDIAN),
+                          self->real_spectrum_size, self->tonal_mask);
+
   // --- Common Processing Path ---
 
   float whitening_factor = self->whitening_enabled
@@ -383,10 +414,12 @@ bool spectral_denoiser_run(SpectralProcessorHandle instance,
                  self->beta, self->gain_estimation_type);
 
   // Apply noise floor management
-  noise_floor_manager_apply(
-      self->noise_floor_manager, self->real_spectrum_size, self->fft_size,
-      self->gain_spectrum, self->noise_spectrum,
-      self->denoise_parameters.reduction_amount, whitening_factor);
+  noise_floor_manager_apply(self->noise_floor_manager, self->real_spectrum_size,
+                            self->fft_size, self->gain_spectrum,
+                            self->noise_spectrum,
+                            self->denoise_parameters.reduction_amount,
+                            self->denoise_parameters.tonal_reduction,
+                            self->tonal_mask, whitening_factor);
 
   DenoiseMixerParameters mixer_parameters = (DenoiseMixerParameters){
       .noise_level = self->denoise_parameters.reduction_amount,
diff --git a/src/processors/denoiser/spectral_denoiser.h b/src/processors/denoiser/spectral_denoiser.h
--- a/src/processors/denoiser/spectral_denoiser.h
+++ b/src/processors/denoiser/spectral_denoiser.h
@@ -30,14 +30,15 @@ typedef struct DenoiserParameters {
   float reduction_amount;
   bool residual_listen;
   int learn_noise;
-  int noise_reduction_mode;
   float smoothing_factor;
   float whitening_factor;
   int adaptive_noise;
   int noise_estimation_method; /**< 0=SPP-MMSE, 1=Brandt, 2=Martin MS */
   float masking_depth;
   float masking_elasticity;
   float suppression_strength;
+  float aggressiveness;  /**< -1.0 (Median/Min) to 1.0 (Max), 0.0 (Mean) */
+  float tonal_reduction; /**< 0.0 to 1.0 (Phase 3) */
 } DenoiserParameters;
 
 SpectralProcessorHandle spectral_denoiser_initialize(
diff --git a/src/processors/denoiser2d/spectral_2d_denoiser.c b/src/processors/denoiser2d/spectral_2d_denoiser.c
--- a/src/processors/denoiser2d/spectral_2d_denoiser.c
+++ b/src/processors/denoiser2d/spectral_2d_denoiser.c
@@ -24,13 +24,15 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 #include "shared/gain_estimation/suppression_engine.h"
 #include "shared/noise_estimation/adaptive_noise_estimator.h"
 #include "shared/noise_estimation/noise_estimator.h"
+#include "shared/noise_estimation/tonal_detector.h"
 #include "shared/post_estimation/masking_veto.h"
 #include "shared/post_estimation/nlm_filter.h"
 #include "shared/post_estimation/noise_floor_manager.h"
 #include "shared/utils/denoise_mixer.h"
 #include "shared/utils/spectral_features.h"
 #include "shared/utils/spectral_utils.h"
 #include <float.h>
+#include <math.h>
 #include <stdlib.h>
 #include <string.h>
 
@@ -49,6 +51,7 @@ typedef struct Spectral2DDenoiser {
   float* alpha;              // Oversubtraction factors
   float* beta;               // Undersubtraction factors
   float* manual_noise_floor; // Manual profile floor
+  float* tonal_mask;         // Tonal vs Broadband mask
 
   // Delay buffer for audio alignment
   float* spectral_delay_buffer;
@@ -70,8 +73,9 @@ typedef struct Spectral2DDenoiser {
   NoiseFloorManager* noise_floor_manager;
 
   int last_adaptive_state;
-  int last_noise_reduction_mode;
   int last_noise_estimation_method;
+  float aggressiveness;
+  bool was_learning;
 } Spectral2DDenoiser;
 
 SpectralProcessorHandle spectral_2d_denoiser_initialize(
@@ -145,6 +149,12 @@ SpectralProcessorHandle spectral_2d_denoiser_initialize(
     return NULL;
   }
 
+  self->tonal_mask = (float*)calloc(self->real_spectrum_size, sizeof(float));
+  if (!self->tonal_mask) {
+    spectral_2d_denoiser_free(self);
+    return NULL;
+  }
+
   // Allocate spectral delay buffer
   // We need to store full FFT frames (packed complex)
   // Assuming fft_size floats is sufficient for the packed format used by STFT
@@ -171,6 +181,9 @@ SpectralProcessorHandle spectral_2d_denoiser_initialize(
   }
 
   self->delay_buffer_write_index = 0;
+  self->was_learning = false;
+  self->aggressiveness = 0.0f;
+  self->parameters.tonal_reduction = 0.0f;
 
   // Initialize noise estimator for learning mode
   self->noise_estimator = noise_estimation_initialize(fft_size, noise_profile);
@@ -276,6 +289,7 @@ void spectral_2d_denoiser_free(SpectralProcessorHandle instance) {
   free(self->noise_delay_buffer);
   free(self->magnitude_delay_buffer);
   free(self->manual_noise_floor);
+  free(self->tonal_mask);
 
   free(self);
 }
@@ -307,6 +321,7 @@ bool load_2d_reduction_parameters(SpectralProcessorHandle instance,
   }
 
   self->parameters = parameters;
+  self->aggressiveness = parameters.aggressiveness;
 
   // Update NLM h parameter based on smoothing factor
   if (self->nlm_filter && parameters.smoothing_factor > 0.0F) {
@@ -331,26 +346,25 @@ bool spectral_2d_denoiser_run(SpectralProcessorHandle instance,
 
   if (self->parameters.learn_noise > 0) {
     // Learning mode: update noise profile for all modes
-    for (int mode = ROLLING_MEAN; mode <= MAX; mode++) {
+    for (int mode = ROLLING_MEAN; mode <= MINIMUM; mode++) {
       noise_estimation_run(self->noise_estimator, (NoiseEstimatorType)mode,
                            reference_spectrum);
     }
+    self->was_learning = true;
     return true;
   }
 
-  // --- Denoising mode: use NLM for 2D smoothing ---
-
-  // Always keep manual floor updated from the current mode
-  float* current_profile = get_noise_profile(
-      self->noise_profile, self->parameters.noise_reduction_mode);
-  if (current_profile) {
-    memcpy(self->manual_noise_floor, current_profile,
-           self->real_spectrum_size * sizeof(float));
-  } else {
-    memset(self->manual_noise_floor, 0,
-           self->real_spectrum_size * sizeof(float));
+  if (self->was_learning) {
+    // User just stopped learning -> Finalize all captures
+    for (int mode = ROLLING_MEAN; mode <= MINIMUM; mode++) {
+      noise_estimation_finalize(self->noise_estimator,
+                                (NoiseEstimatorType)mode);
+    }
+    self->was_learning = false;
   }
 
+  // --- Denoising mode: use NLM for 2D smoothing ---
+
   // 1. Store current spectral frame in delay buffer
   memcpy(&self->spectral_delay_buffer[(size_t)self->delay_buffer_write_index *
                                       self->fft_size],
@@ -365,16 +379,25 @@ bool spectral_2d_denoiser_run(SpectralProcessorHandle instance,
   if (self->parameters.adaptive_noise && self->adaptive_estimator) {
     // Check for state transitions
     bool state_changed = !self->last_adaptive_state;
-    bool mode_changed = self->last_noise_reduction_mode !=
-                        self->parameters.noise_reduction_mode;
+    bool mode_changed =
+        fabsf(self->aggressiveness - self->parameters.aggressiveness) > 0.01f;
 
     if (state_changed || mode_changed) {
+      // Calculate morphed base profile
+      get_morphed_profile(self->manual_noise_floor,
+                          get_noise_profile(self->noise_profile, ROLLING_MEAN),
+                          get_noise_profile(self->noise_profile, MEDIAN),
+                          get_noise_profile(self->noise_profile, MAX),
+                          get_noise_profile(self->noise_profile, MINIMUM),
+                          self->real_spectrum_size,
+                          self->parameters.aggressiveness);
+
       // Re-seed the adaptive estimator to the new chosen base profile
       adaptive_estimator_update_seed(self->adaptive_estimator,
                                      self->manual_noise_floor);
 
       self->last_adaptive_state = 1;
-      self->last_noise_reduction_mode = self->parameters.noise_reduction_mode;
+      self->aggressiveness = self->parameters.aggressiveness;
     }
 
     // Run adaptive estimator
@@ -391,10 +414,16 @@ bool spectral_2d_denoiser_run(SpectralProcessorHandle instance,
       }
     }
   } else {
-    // Manual mode: use static profile
+    // Manual mode: use morphed profile
     self->last_adaptive_state = 0;
-    memcpy(self->noise_spectrum, self->manual_noise_floor,
-           self->real_spectrum_size * sizeof(float));
+
+    get_morphed_profile(self->noise_spectrum,
+                        get_noise_profile(self->noise_profile, ROLLING_MEAN),
+                        get_noise_profile(self->noise_profile, MEDIAN),
+                        get_noise_profile(self->noise_profile, MAX),
+                        get_noise_profile(self->noise_profile, MINIMUM),
+                        self->real_spectrum_size,
+                        self->parameters.aggressiveness);
   }
 
   // 3. Store the noise spectrum in the delay buffer to match NLM latency
@@ -432,6 +461,12 @@ bool spectral_2d_denoiser_run(SpectralProcessorHandle instance,
     memcpy(self->noise_spectrum, delayed_noise,
            self->real_spectrum_size * sizeof(float));
 
+    // Detect tonal components
+    detect_tonal_components(self->noise_spectrum,
+                            get_noise_profile(self->noise_profile, MAX),
+                            get_noise_profile(self->noise_profile, MEDIAN),
+                            self->real_spectrum_size, self->tonal_mask);
+
     // Moderating the NLM reduction via Masking Veto
     if (nlm_filter_process(self->nlm_filter, self->smoothed_snr)) {
       // 1. Convert smoothed SNR back to spectral domain to get the "cleaner"
@@ -470,7 +505,8 @@ bool spectral_2d_denoiser_run(SpectralProcessorHandle instance,
       noise_floor_manager_apply(
           self->noise_floor_manager, self->real_spectrum_size, self->fft_size,
           self->gain_spectrum, self->noise_spectrum,
-          self->parameters.reduction_amount, self->parameters.whitening_factor);
+          self->parameters.reduction_amount, self->parameters.tonal_reduction,
+          self->tonal_mask, self->parameters.whitening_factor);
 
       // Mix results
       DenoiseMixerParameters mixer_params = {
diff --git a/src/processors/denoiser2d/spectral_2d_denoiser.h b/src/processors/denoiser2d/spectral_2d_denoiser.h
--- a/src/processors/denoiser2d/spectral_2d_denoiser.h
+++ b/src/processors/denoiser2d/spectral_2d_denoiser.h
@@ -31,17 +31,18 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
  * Uses Non-Local Means algorithm for 2D smoothing of SNR map.
  */
 typedef struct Denoiser2DParameters {
-  int learn_noise;          /**< Learning mode: 0=disabled, 1=learn all modes */
-  int noise_reduction_mode; /**< Profile to use: 1=avg, 2=median, 3=max */
-  bool residual_listen;     /**< Output residue instead of denoised signal */
-  float reduction_amount;   /**< Gain floor / reduction amount (linear) */
-  float smoothing_factor;   /**< NLM 'h' parameter (smoothing strength) */
-  float whitening_factor;   /**< Whitening factor (0.0 to 1.0) */
-  int adaptive_noise;       /**< Adaptive noise mode: 0=disabled, 1=enabled */
+  int learn_noise;        /**< Learning mode: 0=disabled, 1=learn all modes */
+  bool residual_listen;   /**< Output residue instead of denoised signal */
+  float reduction_amount; /**< Gain floor / reduction amount (linear) */
+  float smoothing_factor; /**< NLM 'h' parameter (smoothing strength) */
+  float whitening_factor; /**< Whitening factor (0.0 to 1.0) */
+  int adaptive_noise;     /**< Adaptive noise mode: 0=disabled, 1=enabled */
   int noise_estimation_method;  /**< 0=SPP-MMSE, 1=Brandt, 2=Martin MS */
   float nlm_masking_protection; /**< Masking protection depth (0.0 to 1.0) */
   float masking_elasticity;     /**< Masking elasticity (0.0 to 1.0) */
   float suppression_strength;   /**< Suppression aggressiveness (0.0 to 1.0) */
+  float aggressiveness;  /**< -1.0 (Median/Min) to 1.0 (Max), 0.0 (Mean) */
+  float tonal_reduction; /**< 0.0 to 1.0 (Phase 3) */
 } Denoiser2DParameters;
 
 /**
diff --git a/src/processors/specbleach_2d_denoiser.c b/src/processors/specbleach_2d_denoiser.c
--- a/src/processors/specbleach_2d_denoiser.c
+++ b/src/processors/specbleach_2d_denoiser.c
@@ -144,57 +144,15 @@ uint32_t specbleach_2d_get_noise_profile_size(SpectralBleachHandle instance) {
   return get_noise_profile_size(self->noise_profile);
 }
 
-uint32_t specbleach_2d_get_noise_profile_blocks_averaged(
-    SpectralBleachHandle instance) {
-  Sb2DDenoiser* self = (Sb2DDenoiser*)instance;
-
-  if (!self || !self->noise_profile) {
-    return 0;
-  }
-
-  return get_noise_profile_blocks_averaged(self->noise_profile, ROLLING_MEAN);
-}
-
-float* specbleach_2d_get_noise_profile(SpectralBleachHandle instance) {
-  Sb2DDenoiser* self = (Sb2DDenoiser*)instance;
-
-  if (!self || !self->noise_profile) {
-    return NULL;
-  }
-
-  return get_noise_profile(self->noise_profile, ROLLING_MEAN);
-}
-
-bool specbleach_2d_load_noise_profile(SpectralBleachHandle instance,
-                                      const float* restored_profile,
-                                      const uint32_t profile_size,
-                                      const uint32_t averaged_blocks) {
-  Sb2DDenoiser* self = (Sb2DDenoiser*)instance;
-
-  if (!self || !self->noise_profile || !restored_profile) {
-    return false;
-  }
-
-  if (profile_size != get_noise_profile_size(self->noise_profile)) {
-    return false;
-  }
-
-  set_noise_profile(self->noise_profile,
-                    self->denoise_parameters.noise_reduction_mode,
-                    restored_profile, profile_size, averaged_blocks);
-
-  return true;
-}
-
 bool specbleach_2d_load_noise_profile_for_mode(SpectralBleachHandle instance,
                                                const float* restored_profile,
                                                const uint32_t profile_size,
-                                               const uint32_t averaged_blocks,
+                                               const uint32_t block_count,
                                                const int mode) {
   Sb2DDenoiser* self = (Sb2DDenoiser*)instance;
 
   if (!self || !self->noise_profile || !restored_profile || mode < 1 ||
-      mode > 3) {
+      mode > 4) {
     return false;
   }
 
@@ -203,7 +161,7 @@ bool specbleach_2d_load_noise_profile_for_mode(SpectralBleachHandle instance,
   }
 
   set_noise_profile(self->noise_profile, mode, restored_profile, profile_size,
-                    averaged_blocks);
+                    block_count);
 
   return true;
 }
@@ -219,29 +177,19 @@ bool specbleach_2d_reset_noise_profile(SpectralBleachHandle instance) {
   return true;
 }
 
-bool specbleach_2d_noise_profile_available(SpectralBleachHandle instance) {
-  Sb2DDenoiser* self = (Sb2DDenoiser*)instance;
-
-  if (!self || !self->noise_profile) {
-    return false;
-  }
-
-  return is_noise_estimation_available(self->noise_profile, ROLLING_MEAN);
-}
-
-uint32_t specbleach_2d_get_noise_profile_blocks_averaged_for_mode(
+uint32_t specbleach_2d_get_noise_profile_block_count_for_mode(
     SpectralBleachHandle instance, int mode) {
   Sb2DDenoiser* self = (Sb2DDenoiser*)instance;
 
   if (!self || !self->noise_profile) {
     return 0;
   }
 
-  if (mode < 1 || mode > 3) {
+  if (mode < 1 || mode > 4) {
     return 0;
   }
 
-  return get_noise_profile_blocks_averaged(self->noise_profile, mode);
+  return get_noise_profile_block_count(self->noise_profile, mode);
 }
 
 float* specbleach_2d_get_noise_profile_for_mode(SpectralBleachHandle instance,
@@ -252,7 +200,7 @@ float* specbleach_2d_get_noise_profile_for_mode(SpectralBleachHandle instance,
     return NULL;
   }
 
-  if (mode < 1 || mode > 3) {
+  if (mode < 1 || mode > 4) {
     return NULL;
   }
 
@@ -267,7 +215,7 @@ bool specbleach_2d_noise_profile_available_for_mode(
     return false;
   }
 
-  if (mode < 1 || mode > 3) {
+  if (mode < 1 || mode > 4) {
     return false;
   }
 
@@ -287,16 +235,19 @@ bool specbleach_2d_load_parameters(
   // clang-format off
   self->denoise_parameters = (Denoiser2DParameters){
       .learn_noise = parameters.learn_noise,
-      .noise_reduction_mode = parameters.noise_reduction_mode,
       .residual_listen = parameters.residual_listen,
-      .reduction_amount = from_db_to_coefficient(parameters.reduction_amount * -1.F),
+      .reduction_amount =
+          from_db_to_coefficient(parameters.reduction_amount * -1.F),
       .smoothing_factor = parameters.smoothing_factor,
       .whitening_factor = parameters.whitening_factor / 100.F,
       .adaptive_noise = parameters.adaptive_noise,
       .noise_estimation_method = parameters.noise_estimation_method,
       .nlm_masking_protection = parameters.nlm_masking_protection,
       .masking_elasticity = parameters.masking_elasticity,
       .suppression_strength = parameters.suppression_strength / 100.F,
+      .aggressiveness = parameters.aggressiveness,
+      .tonal_reduction =
+          from_db_to_coefficient(parameters.tonal_reduction * -1.F),
   };
   // clang-format on
 
diff --git a/src/processors/specbleach_denoiser.c b/src/processors/specbleach_denoiser.c
--- a/src/processors/specbleach_denoiser.c
+++ b/src/processors/specbleach_denoiser.c
@@ -21,6 +21,7 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 #include "specbleach_denoiser.h"
 #include "denoiser/spectral_denoiser.h"
 #include "shared/configurations.h"
+#include "shared/noise_estimation/noise_estimator.h"
 #include "shared/noise_estimation/noise_profile.h"
 #include "shared/stft/stft_processor.h"
 #include "shared/utils/general_utils.h"
@@ -137,56 +138,12 @@ uint32_t specbleach_get_noise_profile_size(SpectralBleachHandle instance) {
   return get_noise_profile_size(self->noise_profile);
 }
 
-uint32_t specbleach_get_noise_profile_blocks_averaged(
-    SpectralBleachHandle instance) {
-  SbSpectralDenoiser* self = (SbSpectralDenoiser*)instance;
-
-  if (!self || !self->noise_profile) {
-    return 0;
-  }
-
-  return get_noise_profile_blocks_averaged(
-      self->noise_profile, self->denoise_parameters.noise_reduction_mode);
-}
-
-float* specbleach_get_noise_profile(SpectralBleachHandle instance) {
-  SbSpectralDenoiser* self = (SbSpectralDenoiser*)instance;
-
-  if (!self || !self->noise_profile) {
-    return NULL;
-  }
-
-  return get_noise_profile(self->noise_profile,
-                           self->denoise_parameters.noise_reduction_mode);
-}
-
-bool specbleach_load_noise_profile(SpectralBleachHandle instance,
-                                   const float* restored_profile,
-                                   const uint32_t profile_size,
-                                   const uint32_t averaged_blocks) {
-  if (!instance || !restored_profile) {
-    return false;
-  }
-
-  SbSpectralDenoiser* self = (SbSpectralDenoiser*)instance;
-
-  if (profile_size != get_noise_profile_size(self->noise_profile)) {
-    return false;
-  }
-
-  set_noise_profile(self->noise_profile,
-                    self->denoise_parameters.noise_reduction_mode,
-                    restored_profile, profile_size, averaged_blocks);
-
-  return true;
-}
-
 bool specbleach_load_noise_profile_for_mode(SpectralBleachHandle instance,
                                             const float* restored_profile,
                                             const uint32_t profile_size,
-                                            const uint32_t averaged_blocks,
+                                            const uint32_t block_count,
                                             const int mode) {
-  if (!instance || !restored_profile || mode < 1 || mode > 3) {
+  if (!instance || !restored_profile || mode < 1 || mode > 4) {
     return false;
   }
 
@@ -197,7 +154,7 @@ bool specbleach_load_noise_profile_for_mode(SpectralBleachHandle instance,
   }
 
   set_noise_profile(self->noise_profile, mode, restored_profile, profile_size,
-                    averaged_blocks);
+                    block_count);
 
   return true;
 }
@@ -214,29 +171,19 @@ bool specbleach_reset_noise_profile(SpectralBleachHandle instance) {
   return true;
 }
 
-bool specbleach_noise_profile_available(SpectralBleachHandle instance) {
-  SbSpectralDenoiser* self = (SbSpectralDenoiser*)instance;
-  if (!self || !self->noise_profile) {
-    return false;
-  }
-
-  return is_noise_estimation_available(
-      self->noise_profile, self->denoise_parameters.noise_reduction_mode);
-}
-
-uint32_t specbleach_get_noise_profile_blocks_averaged_for_mode(
+uint32_t specbleach_get_noise_profile_block_count_for_mode(
     SpectralBleachHandle instance, int mode) {
   SbSpectralDenoiser* self = (SbSpectralDenoiser*)instance;
-  if (!self || mode < 1 || mode > 3) {
+  if (!self || mode < 1 || mode > 4) {
     return 0;
   }
-  return get_noise_profile_blocks_averaged(self->noise_profile, mode);
+  return get_noise_profile_block_count(self->noise_profile, mode);
 }
 
 float* specbleach_get_noise_profile_for_mode(SpectralBleachHandle instance,
                                              int mode) {
   SbSpectralDenoiser* self = (SbSpectralDenoiser*)instance;
-  if (!self || mode < 1 || mode > 3) {
+  if (!self || mode < 1 || mode > 4) {
     return NULL;
   }
   return get_noise_profile(self->noise_profile, mode);
@@ -245,7 +192,7 @@ float* specbleach_get_noise_profile_for_mode(SpectralBleachHandle instance,
 bool specbleach_noise_profile_available_for_mode(SpectralBleachHandle instance,
                                                  int mode) {
   SbSpectralDenoiser* self = (SbSpectralDenoiser*)instance;
-  if (!self || mode < 1 || mode > 3) {
+  if (!self || mode < 1 || mode > 4) {
     return false;
   }
   return is_noise_estimation_available(self->noise_profile, mode);
@@ -262,17 +209,20 @@ bool specbleach_load_parameters(SpectralBleachHandle instance,
   // clang-format off
   self->denoise_parameters = (DenoiserParameters){
       .learn_noise = parameters.learn_noise,
-      .noise_reduction_mode = parameters.noise_reduction_mode,
       .residual_listen = parameters.residual_listen,
       .reduction_amount =
           from_db_to_coefficient(parameters.reduction_amount * -1.F),
-      .smoothing_factor = remap_percentage_log_like_unity(parameters.smoothing_factor / 100.F),
+      .smoothing_factor =
+          remap_percentage_log_like_unity(parameters.smoothing_factor / 100.F),
       .whitening_factor = parameters.whitening_factor / 100.F,
       .adaptive_noise = parameters.adaptive_noise,
       .noise_estimation_method = parameters.noise_estimation_method,
       .masking_depth = parameters.masking_depth,
       .masking_elasticity = parameters.masking_elasticity,
       .suppression_strength = parameters.suppression_strength / 100.F,
+      .aggressiveness = parameters.aggressiveness,
+      .tonal_reduction =
+          from_db_to_coefficient(parameters.tonal_reduction * -1.F),
   };
   // clang-format on
 
diff --git a/src/shared/configurations.h b/src/shared/configurations.h
--- a/src/shared/configurations.h
+++ b/src/shared/configurations.h
@@ -161,7 +161,9 @@ _Static_assert(sizeof(uint32_t) == 4, "uint32_t must be exactly 32 bits");
 
 // Noise Estimator
 #define MIN_NUMBER_OF_WINDOWS_NOISE_AVERAGED 5
-#define NUMBER_OF_MEDIAN_SPECTRUM 5
+#define NUMBER_OF_MEDIAN_SPECTRUM 25
+#define NOISE_ESTIMATION_INTERPOLATION_THRESHOLD (1e-9F)
+#define NOISE_ESTIMATION_SMOOTHING_FACTOR (0.5F)
 
 // Noise Scaling strategy
 #define NOISE_SCALING_TYPE_GENERAL MASKING_THRESHOLDS
diff --git a/src/shared/noise_estimation/meson.build b/src/shared/noise_estimation/meson.build
--- a/src/shared/noise_estimation/meson.build
+++ b/src/shared/noise_estimation/meson.build
@@ -5,4 +5,5 @@ shared_sources += files(
     'spp_mmse_noise_estimator.c',
     'brandt_noise_estimator.c',
     'martin_noise_estimator.c',
+    'tonal_detector.c',
 )
\ No newline at end of file
diff --git a/src/shared/noise_estimation/noise_estimator.c b/src/shared/noise_estimation/noise_estimator.c
--- a/src/shared/noise_estimation/noise_estimator.c
+++ b/src/shared/noise_estimation/noise_estimator.c
@@ -81,10 +81,10 @@ bool noise_estimation_run(NoiseEstimator* self,
   switch (noise_estimator_type) {
     case ROLLING_MEAN:
       get_rolling_mean_spectrum(noise_profile, signal_spectrum,
-                                get_noise_profile_blocks_averaged(
+                                get_noise_profile_block_count(
                                     self->noise_profile, noise_estimator_type),
                                 self->real_spectrum_size);
-      increment_blocks_averaged(self->noise_profile, noise_estimator_type);
+      increment_block_count(self->noise_profile, noise_estimator_type);
       break;
     case MEDIAN:
       spectral_trailing_buffer_push_back(self->median_buffer, signal_spectrum);
@@ -101,10 +101,34 @@ bool noise_estimation_run(NoiseEstimator* self,
                          self->real_spectrum_size);
       set_noise_profile_available(self->noise_profile, noise_estimator_type);
       break;
+    case MINIMUM:
+      (void)min_spectrum(noise_profile, signal_spectrum,
+                         self->real_spectrum_size);
+      set_noise_profile_available(self->noise_profile, noise_estimator_type);
+      break;
 
     default:
       break;
   }
 
   return true;
 }
+
+void noise_estimation_finalize(NoiseEstimator* self,
+                               NoiseEstimatorType noise_estimator_type) {
+  if (!self) {
+    return;
+  }
+
+  float* noise_profile =
+      get_noise_profile(self->noise_profile, noise_estimator_type);
+
+  if (noise_profile && is_noise_estimation_available(self->noise_profile,
+                                                     noise_estimator_type)) {
+    // Basic refinement
+    interpolate_spectrum_gaps(noise_profile, self->real_spectrum_size,
+                              NOISE_ESTIMATION_INTERPOLATION_THRESHOLD);
+    smooth_spectrum(noise_profile, self->real_spectrum_size,
+                    NOISE_ESTIMATION_SMOOTHING_FACTOR);
+  }
+}
diff --git a/src/shared/noise_estimation/noise_estimator.h b/src/shared/noise_estimation/noise_estimator.h
--- a/src/shared/noise_estimation/noise_estimator.h
+++ b/src/shared/noise_estimation/noise_estimator.h
@@ -32,6 +32,7 @@ typedef enum NoiseEstimatorType {
   ROLLING_MEAN = 1,
   MEDIAN = 2,
   MAX = 3,
+  MINIMUM = 4
 } NoiseEstimatorType;
 
 NoiseEstimator* noise_estimation_initialize(uint32_t fft_size,
@@ -40,5 +41,7 @@ void noise_estimation_free(NoiseEstimator* self);
 bool noise_estimation_run(NoiseEstimator* self,
                           NoiseEstimatorType noise_estimator_type,
                           float* signal_spectrum);
+void noise_estimation_finalize(NoiseEstimator* self,
+                               NoiseEstimatorType noise_estimator_type);
 
 #endif
diff --git a/src/shared/noise_estimation/noise_profile.c b/src/shared/noise_estimation/noise_profile.c
--- a/src/shared/noise_estimation/noise_profile.c
+++ b/src/shared/noise_estimation/noise_profile.c
@@ -26,7 +26,7 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 
 struct NoiseProfile {
   uint32_t noise_profile_size;
-  uint32_t noise_profile_blocks_averaged[NOISE_PROFILE_MODES];
+  uint32_t noise_profile_block_count[NOISE_PROFILE_MODES];
   float* noise_profiles[NOISE_PROFILE_MODES];
   bool noise_spectrum_available[NOISE_PROFILE_MODES];
 };
@@ -39,7 +39,7 @@ NoiseProfile* noise_profile_initialize(const uint32_t size) {
   self->noise_profile_size = size;
 
   for (int i = 0; i < NOISE_PROFILE_MODES; i++) {
-    self->noise_profile_blocks_averaged[i] = 0U;
+    self->noise_profile_block_count[i] = 0U;
     self->noise_spectrum_available[i] = false;
     self->noise_profiles[i] = (float*)calloc(size, sizeof(float));
     if (!self->noise_profiles[i]) {
@@ -63,14 +63,14 @@ void noise_profile_free(NoiseProfile* self) {
 }
 
 bool is_noise_estimation_available(NoiseProfile* self, int mode) {
-  if (mode < 1 || mode > 3) {
+  if (mode < 1 || mode > 4) {
     return false;
   }
   return self->noise_spectrum_available[mode - 1];
 }
 
 float* get_noise_profile(NoiseProfile* self, int mode) {
-  if (mode < 1 || mode > 3) {
+  if (mode < 1 || mode > 4) {
     return NULL;
   }
   return self->noise_profiles[mode - 1];
@@ -80,44 +80,44 @@ uint32_t get_noise_profile_size(NoiseProfile* self) {
   return self->noise_profile_size;
 }
 
-uint32_t get_noise_profile_blocks_averaged(NoiseProfile* self, int mode) {
-  if (mode < 1 || mode > 3) {
+uint32_t get_noise_profile_block_count(NoiseProfile* self, int mode) {
+  if (mode < 1 || mode > 4) {
     return 0;
   }
-  return self->noise_profile_blocks_averaged[mode - 1];
+  return self->noise_profile_block_count[mode - 1];
 }
 void set_noise_profile_available(NoiseProfile* self, int mode) {
-  if (mode >= 1 && mode <= 3) {
+  if (mode >= 1 && mode <= 4) {
     self->noise_spectrum_available[mode - 1] = true;
   }
 }
 
 bool set_noise_profile(NoiseProfile* self, int mode, const float* noise_profile,
                        const uint32_t noise_profile_size,
-                       const uint32_t noise_profile_blocks_averaged) {
-  if (!self || mode < 1 || mode > 3 || !noise_profile ||
+                       const uint32_t block_count) {
+  if (!self || mode < 1 || mode > 4 || !noise_profile ||
       noise_profile_size != self->noise_profile_size) {
     return false;
   }
   int index = mode - 1;
   memcpy(self->noise_profiles[index], noise_profile,
          noise_profile_size * sizeof(float));
 
-  self->noise_profile_blocks_averaged[index] = noise_profile_blocks_averaged;
+  self->noise_profile_block_count[index] = block_count;
   self->noise_spectrum_available[index] = true;
 
   return true;
 }
 
-bool increment_blocks_averaged(NoiseProfile* self, int mode) {
-  if (!self || mode < 1 || mode > 3) {
+bool increment_block_count(NoiseProfile* self, int mode) {
+  if (!self || mode < 1 || mode > 4) {
     return false;
   }
 
   int index = mode - 1;
-  self->noise_profile_blocks_averaged[index]++;
+  self->noise_profile_block_count[index]++;
 
-  if (self->noise_profile_blocks_averaged[index] >
+  if (self->noise_profile_block_count[index] >
           MIN_NUMBER_OF_WINDOWS_NOISE_AVERAGED &&
       !self->noise_spectrum_available[index]) {
     self->noise_spectrum_available[index] = true;
@@ -134,7 +134,7 @@ bool reset_noise_profile(NoiseProfile* self) {
   for (int i = 0; i < NOISE_PROFILE_MODES; i++) {
     (void)initialize_spectrum_with_value(self->noise_profiles[i],
                                          self->noise_profile_size, 0.F);
-    self->noise_profile_blocks_averaged[i] = 0U;
+    self->noise_profile_block_count[i] = 0U;
     self->noise_spectrum_available[i] = false;
   }
 
diff --git a/src/shared/noise_estimation/noise_profile.h b/src/shared/noise_estimation/noise_profile.h
--- a/src/shared/noise_estimation/noise_profile.h
+++ b/src/shared/noise_estimation/noise_profile.h
@@ -27,16 +27,16 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 typedef struct NoiseProfile NoiseProfile;
 
 #define NOISE_PROFILE_MODES                                                    \
-  3 // ROLLING_MEAN, MEDIAN, MAX (no OFF storage needed)
+  4 // ROLLING_MEAN, MEDIAN, MAX, MINIMUM (no OFF storage needed)
 
 NoiseProfile* noise_profile_initialize(uint32_t size);
 void noise_profile_free(NoiseProfile* self);
 float* get_noise_profile(NoiseProfile* self, int mode);
 uint32_t get_noise_profile_size(NoiseProfile* self);
-uint32_t get_noise_profile_blocks_averaged(NoiseProfile* self, int mode);
-bool increment_blocks_averaged(NoiseProfile* self, int mode);
+uint32_t get_noise_profile_block_count(NoiseProfile* self, int mode);
+bool increment_block_count(NoiseProfile* self, int mode);
 bool set_noise_profile(NoiseProfile* self, int mode, const float* noise_profile,
-                       uint32_t noise_profile_size, uint32_t averaged_blocks);
+                       uint32_t noise_profile_size, uint32_t block_count);
 void set_noise_profile_available(NoiseProfile* self, int mode);
 bool reset_noise_profile(NoiseProfile* self);
 bool is_noise_estimation_available(NoiseProfile* self, int mode);
diff --git a/src/shared/noise_estimation/tonal_detector.c b/src/shared/noise_estimation/tonal_detector.c
new file mode 100644
--- /dev/null
+++ b/src/shared/noise_estimation/tonal_detector.c
@@ -0,0 +1,81 @@
+/*
+libspecbleach - A spectral processing library
+*/
+
+#include "tonal_detector.h"
+#include <math.h>
+#include <string.h>
+
+#define PEAK_THRESHOLD 1.58f        // ~4dB above neighbor average
+#define STATIONARITY_THRESHOLD 2.5f // Ratio of Max/Median spread
+
+void detect_tonal_components(const float* profile, const float* max_profile,
+                             const float* median_profile, uint32_t size,
+                             float* tonal_mask) {
+  if (!profile || !tonal_mask || size < 5 || !max_profile || !median_profile) {
+    return;
+  }
+
+  memset(tonal_mask, 0, size * sizeof(float));
+
+  // We use the median profile for detection as it is much more stable than
+  // Mean/Instantaneous
+  const float* detection_profile = median_profile;
+
+  for (uint32_t k = 2; k < size - 2; k++) {
+    // 1. Robust Local Maximum Check (5-bin window to capture broader peaks)
+    if (detection_profile[k] >= detection_profile[k - 1] &&
+        detection_profile[k] >= detection_profile[k + 1] &&
+        detection_profile[k] > detection_profile[k - 2] &&
+        detection_profile[k] > detection_profile[k + 2]) {
+
+      // 2. Broad Neighborhood average (up to 15-bin window) to estimate
+      // background Boundary-aware: clamp the window to [0, size-1] We exclude
+      // the central 5 bins [k-2...k+2] to avoid peak-induced bias
+      float sum_bg = 0.0f;
+      int count_bg = 0;
+      for (int i = -7; i <= 7; i++) {
+        int idx = (int)k + i;
+        if (idx >= 0 && idx < (int)size) {
+          if (i < -2 || i > 2) {
+            sum_bg += detection_profile[idx];
+            count_bg++;
+          }
+        }
+      }
+
+      if (count_bg > 0) {
+        float avg_background = sum_bg / (float)count_bg;
+
+        // 3. Stationarity Index (Spread)
+        float spread = (max_profile[k] + 1e-9f) / (median_profile[k] + 1e-9f);
+
+        // We calculate a 'Stationarity Weight' [0.0 - 1.0]
+        // A slightly more relaxed limit for stationarity
+        float stationarity_weight = fmaxf(
+            0.0f, 1.0f - ((spread - 1.0f) / (STATIONARITY_THRESHOLD - 1.0f)));
+
+        // 4. Adaptive Peak Threshold
+        // Relaxed multiplier (1.5x max) for better sensitivity to subtle tones
+        float threshold =
+            PEAK_THRESHOLD * (1.5f - (stationarity_weight * 0.5f));
+
+        if (detection_profile[k] > avg_background * threshold) {
+          // We found a tonal candidate.
+          tonal_mask[k] = stationarity_weight;
+
+          // Spread the influence to neighboring bins to cover sidebands
+          // (leakage) Center: 1.0, ±1: 0.8, ±2: 0.4
+          tonal_mask[k - 1] =
+              fmaxf(tonal_mask[k - 1], stationarity_weight * 0.8f);
+          tonal_mask[k + 1] =
+              fmaxf(tonal_mask[k + 1], stationarity_weight * 0.8f);
+          tonal_mask[k - 2] =
+              fmaxf(tonal_mask[k - 2], stationarity_weight * 0.4f);
+          tonal_mask[k + 2] =
+              fmaxf(tonal_mask[k + 2], stationarity_weight * 0.4f);
+        }
+      }
+    }
+  }
+}
diff --git a/src/shared/noise_estimation/tonal_detector.h b/src/shared/noise_estimation/tonal_detector.h
new file mode 100644
--- /dev/null
+++ b/src/shared/noise_estimation/tonal_detector.h
@@ -0,0 +1,25 @@
+/*
+libspecbleach - A spectral processing library
+*/
+
+#ifndef TONAL_DETECTOR_H
+#define TONAL_DETECTOR_H
+
+#include <stdbool.h>
+#include <stdint.h>
+
+/**
+ * Identify tonal peaks in a noise profile.
+ * @param profile Noise profile (magnitude or power)
+ * @param max_profile Maximum captured profile (for stationarity check)
+ * @param median_profile Median captured profile (for stationarity check)
+ * @param size Spectrum size
+ * @param sensitivity User sensitivity (0.0 to 1.0)
+ * @param tonal_mask Output mask (1.0 for tonal, 0.0 for broadband, or
+ * intermediate)
+ */
+void detect_tonal_components(const float* profile, const float* max_profile,
+                             const float* median_profile, uint32_t size,
+                             float* tonal_mask);
+
+#endif
diff --git a/src/shared/post_estimation/noise_floor_manager.c b/src/shared/post_estimation/noise_floor_manager.c
--- a/src/shared/post_estimation/noise_floor_manager.c
+++ b/src/shared/post_estimation/noise_floor_manager.c
@@ -73,7 +73,10 @@ void noise_floor_manager_free(NoiseFloorManager* self) {
 void noise_floor_manager_apply(NoiseFloorManager* self,
                                uint32_t real_spectrum_size, uint32_t fft_size,
                                float* gain_spectrum, const float* noise_profile,
-                               float reduction_amount, float whitening_factor) {
+                               float reduction_amount,
+                               float tonal_reduction_amount,
+                               const float* tonal_mask,
+                               float whitening_factor) {
   if (!self || !gain_spectrum || !noise_profile) {
     return;
   }
@@ -84,7 +87,12 @@ void noise_floor_manager_apply(NoiseFloorManager* self,
 
   // 2. Apply biasing + frequency-dependent floor
   for (uint32_t k = 0U; k < real_spectrum_size; k++) {
-    float floor = reduction_amount * self->whitening_weights[k];
+    float mask = (tonal_mask) ? tonal_mask[k] : 0.0f;
+    // Proportional interpolation between regular reduction and tonal reduction
+    float current_reduction =
+        (reduction_amount * (1.0f - mask)) + (tonal_reduction_amount * mask);
+
+    float floor = current_reduction * self->whitening_weights[k];
     if (floor > 1.0f) {
       floor = 1.0f;
     }
diff --git a/src/shared/post_estimation/noise_floor_manager.h b/src/shared/post_estimation/noise_floor_manager.h
--- a/src/shared/post_estimation/noise_floor_manager.h
+++ b/src/shared/post_estimation/noise_floor_manager.h
@@ -35,6 +35,8 @@ void noise_floor_manager_free(NoiseFloorManager* self);
 void noise_floor_manager_apply(NoiseFloorManager* self,
                                uint32_t real_spectrum_size, uint32_t fft_size,
                                float* gain_spectrum, const float* noise_profile,
-                               float reduction_amount, float whitening_factor);
+                               float reduction_amount,
+                               float tonal_reduction_amount,
+                               const float* tonal_mask, float whitening_factor);
 
 #endif
diff --git a/src/shared/pre_estimation/critical_bands.c b/src/shared/pre_estimation/critical_bands.c
--- a/src/shared/pre_estimation/critical_bands.c
+++ b/src/shared/pre_estimation/critical_bands.c
@@ -147,7 +147,7 @@ static void compute_mapping_spectrum(CriticalBands* self) {
     }
     case OCTAVE_SCALE: {
       self->current_critical_bands = (float*)octave_bands;
-      uint32_t number_of_octave_bands = sizeof(opus_bands) / sizeof(float);
+      uint32_t number_of_octave_bands = sizeof(octave_bands) / sizeof(float);
       self->number_bands =
           get_last_valid_band_for_samplerate(self, number_of_octave_bands);
       break;
@@ -168,7 +168,7 @@ static uint32_t get_last_valid_band_for_samplerate(CriticalBands* self,
     }
   }
 
-  return last_valid_band;
+  return last_valid_band + 1;
 }
 bool compute_critical_bands_spectrum(CriticalBands* self, const float* spectrum,
                                      float* critical_bands) {
diff --git a/src/shared/utils/spectral_utils.c b/src/shared/utils/spectral_utils.c
--- a/src/shared/utils/spectral_utils.c
+++ b/src/shared/utils/spectral_utils.c
@@ -268,12 +268,90 @@ bool get_rolling_median_spectrum(float* median_spectrum,
     // Sorting array
     qsort(tmp_buffer, number_of_blocks, sizeof(float), min_max_comparator);
 
-    float median_of_buffer = find_median(tmp_buffer, number_of_blocks);
+    median_spectrum[i] = find_median(tmp_buffer, number_of_blocks);
+  }
+
+  return true;
+}
+
+void smooth_spectrum(float* spectrum, uint32_t size, float smoothing_factor) {
+  if (!spectrum || size < 2 || smoothing_factor <= 0.0F) {
+    return;
+  }
 
-    // Taking the max of the median
-    if (median_of_buffer > median_spectrum[i]) {
-      median_spectrum[i] = median_of_buffer;
+  // Boundary check: Handle edge bins with 2-point moving average
+  // to ensure smoothing reaches the very last bin (Nyquist)
+  float first = spectrum[0];
+  spectrum[0] = ((spectrum[0] + spectrum[1]) / 2.0F * smoothing_factor) +
+                (spectrum[0] * (1.0F - smoothing_factor));
+
+  float prev = first;
+  for (uint32_t i = 1; i < size - 1; i++) {
+    float current = spectrum[i];
+    spectrum[i] =
+        (((prev + current + spectrum[i + 1]) / 3.0F) * smoothing_factor) +
+        (current * (1.0F - smoothing_factor));
+    prev = current;
+  }
+
+  // Handle last bin (Nyquist)
+  spectrum[size - 1] =
+      (((prev + spectrum[size - 1]) / 2.0F) * smoothing_factor) +
+      (spectrum[size - 1] * (1.0F - smoothing_factor));
+}
+
+void interpolate_spectrum_gaps(float* spectrum, uint32_t size,
+                               float gap_threshold) {
+  if (!spectrum || size < 3) {
+    return;
+  }
+
+  for (uint32_t i = 1; i < size - 1; i++) {
+    if (spectrum[i] < gap_threshold) {
+      // Find next non-gap bin
+      uint32_t j = i + 1;
+      while (j < size && spectrum[j] < gap_threshold) {
+        j++;
+      }
+
+      if (j < size) {
+        // Interpolate between i-1 and j
+        float start_val = spectrum[i - 1];
+        float end_val = spectrum[j];
+        float step = (end_val - start_val) / (float)(j - (i - 1));
+
+        for (uint32_t k = i; k < j; k++) {
+          spectrum[k] = start_val + (step * (float)(k - (i - 1)));
+        }
+        i = j;
+      }
+    }
+  }
+}
+
+bool get_morphed_profile(float* output_profile, const float* mean_profile,
+                         const float* median_profile, const float* max_profile,
+                         const float* min_profile, uint32_t size,
+                         float aggressiveness) {
+  if (!output_profile || !mean_profile || !median_profile || !max_profile ||
+      !min_profile || size == 0) {
+    return false;
+  }
+
+  for (uint32_t i = 0; i < size; i++) {
+    if (aggressiveness < 0.0F) {
+      // Morph from Mean (0) to Median (-1)
+      float t = -aggressiveness;
+      output_profile[i] =
+          (mean_profile[i] * (1.0F - t)) + (median_profile[i] * t);
+    } else {
+      // Morph from Mean (0) to Max (1)
+      float t = aggressiveness;
+      output_profile[i] = (mean_profile[i] * (1.0F - t)) + (max_profile[i] * t);
     }
+
+    // Always ensure the profile is at least the Minimum
+    output_profile[i] = fmaxf(output_profile[i], min_profile[i]);
   }
 
   return true;
diff --git a/src/shared/utils/spectral_utils.h b/src/shared/utils/spectral_utils.h
--- a/src/shared/utils/spectral_utils.h
+++ b/src/shared/utils/spectral_utils.h
@@ -74,5 +74,12 @@ bool get_rolling_median_spectrum(float* median_spectrum,
                                  const float* current_spectrum_buffer,
                                  uint32_t number_of_blocks,
                                  uint32_t spectrum_size);
+void smooth_spectrum(float* spectrum, uint32_t size, float smoothing_factor);
+void interpolate_spectrum_gaps(float* spectrum, uint32_t size,
+                               float gap_threshold);
+bool get_morphed_profile(float* output_profile, const float* mean_profile,
+                         const float* median_profile, const float* max_profile,
+                         const float* min_profile, uint32_t size,
+                         float aggressiveness);
 
 #endif
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
