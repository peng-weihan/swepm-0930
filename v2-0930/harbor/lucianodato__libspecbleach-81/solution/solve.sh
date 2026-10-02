#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/include/specbleach_2d_denoiser.h b/include/specbleach_2d_denoiser.h
--- a/include/specbleach_2d_denoiser.h
+++ b/include/specbleach_2d_denoiser.h
@@ -83,8 +83,9 @@ typedef struct SpectralBleach2DDenoiserParameters {
 
   /**
    * Sets the method used for adaptive noise estimation.
-   * 0: Louizou's method
-   * 1: SPP-MMSE method
+   * 0: SPP-MMSE method
+   * 1: Brandt (Trimmed Mean)
+   * 2: Martin Minimum Statistics
    */
   int noise_estimation_method;
 } SpectralBleach2DDenoiserParameters;
diff --git a/src/processors/denoiser/spectral_denoiser.h b/src/processors/denoiser/spectral_denoiser.h
--- a/src/processors/denoiser/spectral_denoiser.h
+++ b/src/processors/denoiser/spectral_denoiser.h
@@ -37,7 +37,7 @@ typedef struct DenoiserParameters {
   float whitening_factor;
   float post_filter_threshold;
   int adaptive_noise;
-  int noise_estimation_method;
+  int noise_estimation_method; /**< 0=SPP-MMSE, 1=Brandt, 2=Martin MS */
 } DenoiserParameters;
 
 SpectralProcessorHandle spectral_denoiser_initialize(
diff --git a/src/processors/denoiser2d/spectral_2d_denoiser.h b/src/processors/denoiser2d/spectral_2d_denoiser.h
--- a/src/processors/denoiser2d/spectral_2d_denoiser.h
+++ b/src/processors/denoiser2d/spectral_2d_denoiser.h
@@ -38,7 +38,7 @@ typedef struct Denoiser2DParameters {
   float smoothing_factor;   /**< NLM 'h' parameter (smoothing strength) */
   float whitening_factor;   /**< Whitening factor (0.0 to 1.0) */
   int adaptive_noise;       /**< Adaptive noise mode: 0=disabled, 1=enabled */
-  int noise_estimation_method; /**< 0=Louizou, 1=SPP-MMSE */
+  int noise_estimation_method; /**< 0=SPP-MMSE, 1=Brandt, 2=Martin MS */
 } Denoiser2DParameters;
 
 /**
diff --git a/src/shared/configurations.h b/src/shared/configurations.h
--- a/src/shared/configurations.h
+++ b/src/shared/configurations.h
@@ -106,6 +106,17 @@ _Static_assert(sizeof(uint32_t) == 4, "uint32_t must be exactly 32 bits");
 #define BAND_3_LEVEL (5.F)
 
 #define ESTIMATOR_SILENCE_THRESHOLD (1e-10F) // Roughly -100dB in power
+#define ESTIMATOR_BIAS_EPSILON (1e-6F) // Precision for bias correction calc
+#define ESTIMATOR_MIN_HISTORY_FRAMES                                           \
+  5U // Minimum frames for history-based tracking
+#define ESTIMATOR_MIN_DURATION_MS 0.1F // Safety floor for duration calcs
+
+// Martin (2001) Constants
+#define MARTIN_WINDOW_LEN 96  // Total window length (frames)
+#define MARTIN_SUBWIN_COUNT 8 // Number of sub-windows
+#define MARTIN_SUBWIN_LEN 12  // Sub-window length (96/8)
+#define MARTIN_BIAS_CORR 1.5F // Conservative bias correction for min tracking
+#define MARTIN_SMOOTH_ALPHA 0.8F // Baseline smoothing for PSD
 
 // SPP-MMSE Estimator Constants
 #define SPP_PRIOR_H1 (0.5F)      // P(H1) - Speech present prior
@@ -116,6 +127,12 @@ _Static_assert(sizeof(uint32_t) == 4, "uint32_t must be exactly 32 bits");
 #define SPP_CURRENT_SPP (0.1F)   // Current SPP weighting for stagnation control
 #define SPP_STAGNATION_CAP (0.99F) // Maximum SPP value to prevent locking
 
+// Brandt (Trimmer Mean) Constants
+#define BRANDT_DEFAULT_HISTORY_MS 5000.0f
+#define BRANDT_DEFAULT_PERCENTILE 0.5f
+#define BRANDT_MIN_CONFIDENCE                                                  \
+  0.90f // Lowered from 0.98 for better learning speed
+
 /* --------------------------------------------------------------- */
 /* ------------------- Denoiser configurations ------------------- */
 /* --------------------------------------------------------------- */
diff --git a/src/shared/noise_estimation/adaptive_noise_estimator.c b/src/shared/noise_estimation/adaptive_noise_estimator.c
--- a/src/shared/noise_estimation/adaptive_noise_estimator.c
+++ b/src/shared/noise_estimation/adaptive_noise_estimator.c
@@ -19,7 +19,9 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */
 
 #include "adaptive_noise_estimator.h"
-#include "louizou_noise_estimator.h"
+#include "../configurations.h"
+#include "brandt_noise_estimator.h"
+#include "martin_noise_estimator.h"
 #include "spp_mmse_noise_estimator.h"
 #include <stdlib.h>
 
@@ -28,16 +30,16 @@ struct AdaptiveNoiseEstimator {
   void* internal_estimator;
 };
 
-static AdaptiveNoiseEstimator* create_louizou_estimator(
+static AdaptiveNoiseEstimator* create_spp_mmse_estimator(
     uint32_t noise_spectrum_size, uint32_t sample_rate, uint32_t fft_size) {
   AdaptiveNoiseEstimator* self =
       (AdaptiveNoiseEstimator*)calloc(1U, sizeof(AdaptiveNoiseEstimator));
   if (!self) {
     return NULL;
   }
 
-  self->method = LOUIZOU_METHOD;
-  self->internal_estimator = louizou_noise_estimator_initialize(
+  self->method = SPP_MMSE_METHOD;
+  self->internal_estimator = spp_mmse_noise_estimator_initialize(
       noise_spectrum_size, sample_rate, fft_size);
 
   if (!self->internal_estimator) {
@@ -48,16 +50,37 @@ static AdaptiveNoiseEstimator* create_louizou_estimator(
   return self;
 }
 
-static AdaptiveNoiseEstimator* create_spp_mmse_estimator(
+static AdaptiveNoiseEstimator* create_brandt_estimator(
     uint32_t noise_spectrum_size, uint32_t sample_rate, uint32_t fft_size) {
   AdaptiveNoiseEstimator* self =
       (AdaptiveNoiseEstimator*)calloc(1U, sizeof(AdaptiveNoiseEstimator));
   if (!self) {
     return NULL;
   }
 
-  self->method = SPP_MMSE_METHOD;
-  self->internal_estimator = spp_mmse_noise_estimator_initialize(
+  self->method = BRANDT_METHOD;
+  // Default parameters: 5000ms history (extremely robust for music)
+  self->internal_estimator = brandt_noise_estimator_initialize(
+      noise_spectrum_size, BRANDT_DEFAULT_HISTORY_MS, sample_rate, fft_size);
+
+  if (!self->internal_estimator) {
+    free(self);
+    return NULL;
+  }
+
+  return self;
+}
+
+static AdaptiveNoiseEstimator* create_martin_estimator(
+    uint32_t noise_spectrum_size, uint32_t sample_rate, uint32_t fft_size) {
+  AdaptiveNoiseEstimator* self =
+      (AdaptiveNoiseEstimator*)calloc(1U, sizeof(AdaptiveNoiseEstimator));
+  if (!self) {
+    return NULL;
+  }
+
+  self->method = MARTIN_METHOD;
+  self->internal_estimator = martin_noise_estimator_initialize(
       noise_spectrum_size, sample_rate, fft_size);
 
   if (!self->internal_estimator) {
@@ -68,33 +91,40 @@ static AdaptiveNoiseEstimator* create_spp_mmse_estimator(
   return self;
 }
 
-static bool run_louizou(AdaptiveNoiseEstimator* self, const float* spectrum,
-                        float* noise_spectrum) {
-  return louizou_noise_estimator_run(
-      (LouizouNoiseEstimator*)self->internal_estimator, spectrum,
+static bool run_martin(AdaptiveNoiseEstimator* self, const float* spectrum,
+                       float* noise_spectrum) {
+  return martin_noise_estimator_run(
+      (MartinNoiseEstimator*)self->internal_estimator, spectrum,
       noise_spectrum);
 }
 
-static bool run_spp_mmse(AdaptiveNoiseEstimator* self, const float* spectrum,
-                         float* noise_spectrum) {
-  return spp_mmse_noise_estimator_run(
-      (SppMmseNoiseEstimator*)self->internal_estimator, spectrum,
+static bool run_brandt(AdaptiveNoiseEstimator* self, const float* spectrum,
+                       float* noise_spectrum) {
+  return brandt_noise_estimator_run(
+      (BrandtNoiseEstimator*)self->internal_estimator, spectrum,
       noise_spectrum);
 }
 
 AdaptiveNoiseEstimator* adaptive_estimator_initialize(
     uint32_t noise_spectrum_size, uint32_t sample_rate, uint32_t fft_size,
     AdaptiveNoiseEstimationMethod method) {
-  if (method == LOUIZOU_METHOD) {
-    return create_louizou_estimator(noise_spectrum_size, sample_rate, fft_size);
+  if (method == SPP_MMSE_METHOD) {
+    return create_spp_mmse_estimator(noise_spectrum_size, sample_rate,
+                                     fft_size);
+  }
+  if (method == BRANDT_METHOD) {
+    return create_brandt_estimator(noise_spectrum_size, sample_rate, fft_size);
   }
-  return create_spp_mmse_estimator(noise_spectrum_size, sample_rate, fft_size);
+  if (method == MARTIN_METHOD) {
+    return create_martin_estimator(noise_spectrum_size, sample_rate, fft_size);
+  }
+  return create_martin_estimator(noise_spectrum_size, sample_rate, fft_size);
 }
 
 AdaptiveNoiseEstimationMethod adaptive_estimator_get_method(
     const AdaptiveNoiseEstimator* self) {
   if (!self) {
-    return LOUIZOU_METHOD; // Safe default
+    return MARTIN_METHOD; // Safe default
   }
   return self->method;
 }
@@ -104,12 +134,15 @@ void adaptive_estimator_free(AdaptiveNoiseEstimator* self) {
     return;
   }
 
-  if (self->method == LOUIZOU_METHOD) {
-    louizou_noise_estimator_free(
-        (LouizouNoiseEstimator*)self->internal_estimator);
-  } else {
+  if (self->method == SPP_MMSE_METHOD) {
     spp_mmse_noise_estimator_free(
         (SppMmseNoiseEstimator*)self->internal_estimator);
+  } else if (self->method == BRANDT_METHOD) {
+    brandt_noise_estimator_free(
+        (BrandtNoiseEstimator*)self->internal_estimator);
+  } else if (self->method == MARTIN_METHOD) {
+    martin_noise_estimator_free(
+        (MartinNoiseEstimator*)self->internal_estimator);
   }
 
   free(self);
@@ -121,10 +154,16 @@ bool adaptive_estimator_run(AdaptiveNoiseEstimator* self, const float* spectrum,
     return false;
   }
 
-  if (self->method == LOUIZOU_METHOD) {
-    return run_louizou(self, spectrum, noise_spectrum);
+  if (self->method == SPP_MMSE_METHOD) {
+    return spp_mmse_noise_estimator_run(
+        (SppMmseNoiseEstimator*)self->internal_estimator, spectrum,
+        noise_spectrum);
   }
-  return run_spp_mmse(self, spectrum, noise_spectrum);
+  if (self->method == MARTIN_METHOD) {
+    return run_martin(self, spectrum, noise_spectrum);
+  }
+
+  return run_brandt(self, spectrum, noise_spectrum);
 }
 
 void adaptive_estimator_set_state(AdaptiveNoiseEstimator* self,
@@ -135,12 +174,15 @@ void adaptive_estimator_set_state(AdaptiveNoiseEstimator* self,
     return;
   }
 
-  if (self->method == LOUIZOU_METHOD) {
-    louizou_noise_estimator_set_state(
-        (LouizouNoiseEstimator*)self->internal_estimator, initial_profile);
-  } else {
+  if (self->method == SPP_MMSE_METHOD) {
     spp_mmse_noise_estimator_set_state(
         (SppMmseNoiseEstimator*)self->internal_estimator, initial_profile);
+  } else if (self->method == MARTIN_METHOD) {
+    martin_noise_estimator_set_state(
+        (MartinNoiseEstimator*)self->internal_estimator, initial_profile);
+  } else {
+    brandt_noise_estimator_set_state(
+        (BrandtNoiseEstimator*)self->internal_estimator, initial_profile);
   }
 }
 
@@ -150,12 +192,15 @@ void adaptive_estimator_apply_floor(AdaptiveNoiseEstimator* self,
     return;
   }
 
-  if (self->method == LOUIZOU_METHOD) {
-    louizou_noise_estimator_apply_floor(
-        (LouizouNoiseEstimator*)self->internal_estimator, floor_profile);
-  } else {
+  if (self->method == SPP_MMSE_METHOD) {
     spp_mmse_noise_estimator_apply_floor(
         (SppMmseNoiseEstimator*)self->internal_estimator, floor_profile);
+  } else if (self->method == MARTIN_METHOD) {
+    martin_noise_estimator_apply_floor(
+        (MartinNoiseEstimator*)self->internal_estimator, floor_profile);
+  } else {
+    brandt_noise_estimator_apply_floor(
+        (BrandtNoiseEstimator*)self->internal_estimator, floor_profile);
   }
 }
 
@@ -165,11 +210,14 @@ void adaptive_estimator_update_seed(AdaptiveNoiseEstimator* self,
     return;
   }
 
-  if (self->method == LOUIZOU_METHOD) {
-    louizou_noise_estimator_update_seed(
-        (LouizouNoiseEstimator*)self->internal_estimator, seed_profile);
-  } else {
+  if (self->method == SPP_MMSE_METHOD) {
     spp_mmse_noise_estimator_update_seed(
         (SppMmseNoiseEstimator*)self->internal_estimator, seed_profile);
+  } else if (self->method == MARTIN_METHOD) {
+    martin_noise_estimator_update_seed(
+        (MartinNoiseEstimator*)self->internal_estimator, seed_profile);
+  } else {
+    brandt_noise_estimator_update_seed(
+        (BrandtNoiseEstimator*)self->internal_estimator, seed_profile);
   }
 }
diff --git a/src/shared/noise_estimation/adaptive_noise_estimator.h b/src/shared/noise_estimation/adaptive_noise_estimator.h
--- a/src/shared/noise_estimation/adaptive_noise_estimator.h
+++ b/src/shared/noise_estimation/adaptive_noise_estimator.h
@@ -25,8 +25,9 @@ Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 #include <stdint.h>
 
 typedef enum AdaptiveNoiseEstimationMethod {
-  LOUIZOU_METHOD = 0,  // Original minimum statistics method (default)
-  SPP_MMSE_METHOD = 1, // Speech Presence Probability - MMSE method
+  SPP_MMSE_METHOD = 0, // Speech Presence Probability - MMSE method
+  BRANDT_METHOD = 1,   // Trimmed Mean (Automatic PSD Estimation - 2017)
+  MARTIN_METHOD = 2,   // Martin (2001) Minimum Statistics
 } AdaptiveNoiseEstimationMethod;
 
 typedef struct AdaptiveNoiseEstimator AdaptiveNoiseEstimator;
diff --git a/src/shared/noise_estimation/brandt_noise_estimator.c b/src/shared/noise_estimation/brandt_noise_estimator.c
new file mode 100644
--- /dev/null
+++ b/src/shared/noise_estimation/brandt_noise_estimator.c
@@ -0,0 +1,309 @@
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
+#include "brandt_noise_estimator.h"
+#include "../configurations.h"
+#include <math.h>
+#include <stdlib.h>
+#include <string.h>
+
+struct BrandtNoiseEstimator {
+  uint32_t spectrum_size;
+  uint32_t history_size;
+  uint32_t history_index; // Circular buffer write head
+
+  float* history_buffer;      // Size: spectrum_size * history_size
+  float* sort_buffer;         // Scratch space for sorting (Size: history_size)
+  float* last_noise_spectrum; // Persisted noise to keep during rejection
+
+  float percentile;
+  uint32_t trim_count; // Number of items to average (history_size * percentile)
+  float correction_factor;
+  float correction_factors[5]; // Pre-calculated for search
+  bool is_first_frame;
+};
+
+// Helper: Calculate bias correction factor for trimmed mean of exponential dist
+// Formula: Factor = 1 / (1 + ( (1-P)/P * ln(1-P) ))
+static float calculate_correction_factor(float p) {
+  if (p <= 0.0f || p >= 1.0f) {
+    return 1.0f; // Invalid P, no correction
+  }
+  float term = (1.0f - p) / p * logf(1.0f - p);
+  float denominator = 1.0f + term;
+  if (fabsf(denominator) < ESTIMATOR_BIAS_EPSILON) {
+    return 1.0f; // Avoid division by zero
+  }
+  return 1.0f / denominator;
+}
+
+// Helper: Compare floats for qsort
+static int compare_floats(const void* a, const void* b) {
+  float fa = *(const float*)a;
+  float fb = *(const float*)b;
+  return (fa > fb) - (fa < fb);
+}
+
+BrandtNoiseEstimator* brandt_noise_estimator_initialize(
+    uint32_t spectrum_size, float history_duration_ms, uint32_t sample_rate,
+    uint32_t fft_size) {
+  float percentile = BRANDT_DEFAULT_PERCENTILE; // Advised for music restoration
+  BrandtNoiseEstimator* self =
+      (BrandtNoiseEstimator*)calloc(1, sizeof(BrandtNoiseEstimator));
+  if (!self) {
+    return NULL;
+  }
+
+  self->spectrum_size = spectrum_size;
+  self->percentile = percentile;
+
+  // Calculate history size from duration
+  float ms_per_frame = (float)fft_size * 1000.0f / (float)sample_rate;
+  // Overlap consideration: Usually frame step is hop_size.
+  // Assuming hop = fft_size/2 or similar? The caller usually provides
+  // parameters. If exact duration needed, we might need hop_size.
+  // Assuming standard 50% overlap for calculation roughly:
+  float frame_duration = ms_per_frame * 0.5f; // Rough approximation of step
+  if (frame_duration < ESTIMATOR_MIN_DURATION_MS) {
+    frame_duration = ESTIMATOR_MIN_DURATION_MS;
+  }
+
+  self->history_size = (uint32_t)(history_duration_ms / frame_duration);
+  if (self->history_size < ESTIMATOR_MIN_HISTORY_FRAMES) {
+    self->history_size = ESTIMATOR_MIN_HISTORY_FRAMES; // Minimum history
+  }
+
+  self->trim_count = (uint32_t)((float)self->history_size * percentile);
+  if (self->trim_count < 1) {
+    self->trim_count = 1; // At least min
+  }
+  if (self->trim_count > self->history_size) {
+    self->trim_count = self->history_size;
+  }
+
+  self->correction_factor = calculate_correction_factor(percentile);
+
+  static const float p_candidates[] = {0.1f, 0.25f, 0.5f, 0.75f, 1.0f};
+  for (int i = 0; i < 5; i++) {
+    self->correction_factors[i] = calculate_correction_factor(p_candidates[i]);
+  }
+
+  // Allocate buffers
+  self->history_buffer = (float*)calloc(
+      (size_t)self->spectrum_size * self->history_size, sizeof(float));
+  self->sort_buffer = (float*)calloc(self->history_size, sizeof(float));
+  self->last_noise_spectrum =
+      (float*)calloc(self->spectrum_size, sizeof(float));
+
+  if (!self->history_buffer || !self->sort_buffer ||
+      !self->last_noise_spectrum) {
+    brandt_noise_estimator_free(self);
+    return NULL;
+  }
+
+  self->is_first_frame = true;
+  return self;
+}
+
+void brandt_noise_estimator_free(BrandtNoiseEstimator* self) {
+  if (self) {
+    free(self->history_buffer);
+    free(self->sort_buffer);
+    free(self->last_noise_spectrum);
+    free(self);
+  }
+}
+
+static float calculate_ad_norm(const float* sorted, uint32_t q, float mu,
+                               float b) {
+  if (mu < 1e-15f) {
+    return 1.0f;
+  }
+  float mu_inv = 1.0f / mu;
+  float exp_b_mu = expf(-b * mu_inv);
+  float denom = 1.0f - exp_b_mu;
+  if (fabsf(denom) < 1e-12f) {
+    return 1.0f;
+  }
+
+  float abs_diff_sum = 0.0f;
+  float q_inv = 1.0f / (float)q;
+  float denom_inv = 1.0f / denom;
+
+  // Most expensive loop in denoiser: 5 * spectrum_size * q calls per frame
+  // q is roughly history_size / 2.
+  for (uint32_t i = 0; i < q; i++) {
+    float f_te = (1.0f - expf(-sorted[i] * mu_inv)) * denom_inv;
+    float f_empirical = (float)(i + 1) * q_inv;
+    abs_diff_sum += fabsf(f_empirical - f_te);
+  }
+  return abs_diff_sum * (2.0f * q_inv);
+}
+
+bool brandt_noise_estimator_run(BrandtNoiseEstimator* self,
+                                const float* spectrum, float* noise_spectrum) {
+  if (!self || !spectrum || !noise_spectrum || self->history_size == 0) {
+    return false;
+  }
+
+  float frame_energy = 0.F;
+  for (uint32_t k = 0U; k < self->spectrum_size; k++) {
+    frame_energy += spectrum[k];
+  }
+  frame_energy /= (float)self->spectrum_size;
+
+  if (self->is_first_frame) {
+    if (frame_energy > ESTIMATOR_SILENCE_THRESHOLD) {
+      float inv_factor = 1.0f / calculate_correction_factor(0.5f);
+      for (uint32_t k = 0; k < self->spectrum_size; k++) {
+        float val = spectrum[k] * inv_factor;
+        self->last_noise_spectrum[k] = spectrum[k];
+        for (uint32_t t = 0; t < self->history_size; t++) {
+          float jitter =
+              1.0f + (0.01f * (float)(((int32_t)(t + k) % 11) - 5) / 5.0f);
+          self->history_buffer[((size_t)k * self->history_size) + t] =
+              val * jitter;
+        }
+      }
+      self->is_first_frame = false;
+    }
+  }
+
+  if (frame_energy < ESTIMATOR_SILENCE_THRESHOLD) {
+    memcpy(noise_spectrum, self->last_noise_spectrum,
+           self->spectrum_size * sizeof(float));
+    return true;
+  }
+
+  for (uint32_t k = 0; k < self->spectrum_size; k++) {
+    self->history_buffer[((size_t)k * self->history_size) +
+                         self->history_index] = spectrum[k];
+  }
+  self->history_index = (self->history_index + 1) % self->history_size;
+
+  static const float p_candidates[] = {0.1f, 0.25f, 0.5f, 0.75f, 1.0f};
+
+  for (uint32_t k = 0; k < self->spectrum_size; k++) {
+    float* bin_history = &self->history_buffer[(size_t)k * self->history_size];
+    memcpy(self->sort_buffer, bin_history, self->history_size * sizeof(float));
+    qsort(self->sort_buffer, self->history_size, sizeof(float), compare_floats);
+
+    float min_ad_norm = 2.0f;
+    float best_mu = self->last_noise_spectrum[k];
+
+    for (int i = 0; i < 5; i++) {
+      float p = p_candidates[i];
+      uint32_t q = (uint32_t)(p * (float)self->history_size);
+      if (q < 10) {
+        continue;
+      }
+
+      float b = self->sort_buffer[q - 1];
+      float sum = 0.0f;
+      for (uint32_t j = 0; j < q; j++) {
+        sum += self->sort_buffer[j];
+      }
+      float mu_trunc = sum / (float)q;
+
+      if (mu_trunc > ESTIMATOR_SILENCE_THRESHOLD) {
+        float factor = self->correction_factors[i];
+        float mu_full = mu_trunc * factor;
+        float ad_norm = calculate_ad_norm(self->sort_buffer, q, mu_full, b);
+        if (ad_norm < min_ad_norm) {
+          min_ad_norm = ad_norm;
+          best_mu = mu_full;
+        }
+      }
+    }
+
+    if (1.0f - min_ad_norm >= BRANDT_MIN_CONFIDENCE) {
+      self->last_noise_spectrum[k] = best_mu;
+    }
+    noise_spectrum[k] = self->last_noise_spectrum[k];
+  }
+
+  return true;
+}
+
+void brandt_noise_estimator_set_state(BrandtNoiseEstimator* self,
+                                      const float* initial_profile) {
+  if (!self || !initial_profile) {
+    return;
+  }
+
+  // Start with a known state: Fill history with this profile
+  float inverse_factor = 1.0f / self->correction_factor;
+
+  for (uint32_t k = 0; k < self->spectrum_size; k++) {
+    float val = initial_profile[k] * inverse_factor;
+    self->last_noise_spectrum[k] = initial_profile[k];
+    for (uint32_t t = 0; t < self->history_size; t++) {
+      float jitter =
+          1.0f + (0.01f * (float)(((int32_t)(t + k) % 11) - 5) / 5.0f);
+      self->history_buffer[((size_t)k * self->history_size) + t] = val * jitter;
+    }
+  }
+  self->is_first_frame = false;
+}
+
+void brandt_noise_estimator_update_seed(BrandtNoiseEstimator* self,
+                                        const float* seed_profile) {
+  if (!self || !seed_profile) {
+    return;
+  }
+  // Similar to set_state but maybe only updates part of history?
+  // For now, treat same as set_state to ensure quick convergence/reset.
+  brandt_noise_estimator_set_state(self, seed_profile);
+  self->is_first_frame = false;
+}
+
+void brandt_noise_estimator_apply_floor(BrandtNoiseEstimator* self,
+                                        const float* floor_profile) {
+  if (!self || !floor_profile) {
+    return;
+  }
+  float inverse_factor = 1.0f / self->correction_factor;
+  for (uint32_t k = 0; k < self->spectrum_size; k++) {
+    float floor_val = floor_profile[k] * inverse_factor;
+    for (uint32_t t = 0; t < self->history_size; t++) {
+      if (self->history_buffer[((size_t)k * self->history_size) + t] <
+          floor_val) {
+        self->history_buffer[((size_t)k * self->history_size) + t] = floor_val;
+      }
+    }
+  }
+}
+
+void brandt_noise_estimator_set_history_duration(
+    const BrandtNoiseEstimator* self, float history_duration_ms,
+    uint32_t sample_rate, uint32_t fft_size) {
+  if (!self) {
+    return;
+  }
+
+  // To avoid frequent reallocations, we only update if it's a significant
+  // change For now, let's just update the internal logic if we don't want to
+  // realloc. Actually, changing history size at runtime is best done by
+  // pre-allocating a MAX size. Given we are in the middle of a fix, I will only
+  // expose Percentile as "Sensitivity" first.
+  (void)history_duration_ms;
+  (void)sample_rate;
+  (void)fft_size;
+}
diff --git a/src/shared/noise_estimation/brandt_noise_estimator.h b/src/shared/noise_estimation/brandt_noise_estimator.h
new file mode 100644
--- /dev/null
+++ b/src/shared/noise_estimation/brandt_noise_estimator.h
@@ -0,0 +1,88 @@
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
+#ifndef BRANDT_NOISE_ESTIMATOR_H
+#define BRANDT_NOISE_ESTIMATOR_H
+
+#include <stdbool.h>
+#include <stdint.h>
+
+typedef struct BrandtNoiseEstimator BrandtNoiseEstimator;
+
+/**
+ * @brief Creates a new Brandt (Trimmed Mean) noise estimator instance
+ *
+ * Implements the algorithm from:
+ * "Automatic Noise PSD Estimation for Restoration of Archived Audio"
+ * Brandt et al. (2017).
+ *
+ * Uses a trimmed mean of the past N frames (lowest P%) and applies
+ * a bias correction factor assuming exponential distribution.
+ *
+ * @param spectrum_size Number of frequency bins
+ * @param history_duration_ms Duration of the sliding window in milliseconds
+ * @param percentile The percentile to trim at (0.0 - 1.0). e.g., 0.15 for 15%.
+ * @param sample_rate Audio sample rate
+ * @param fft_size FFT size (for time/freq conversion)
+ * @return BrandtNoiseEstimator* or NULL on failure
+ */
+BrandtNoiseEstimator* brandt_noise_estimator_initialize(
+    uint32_t spectrum_size, float history_duration_ms, uint32_t sample_rate,
+    uint32_t fft_size);
+
+/**
+ * @brief Destroys the estimator instance
+ */
+void brandt_noise_estimator_free(BrandtNoiseEstimator* self);
+
+/**
+ * @brief Process a new spectral frame and update the noise estimate
+ *
+ * @param self Estimator instance
+ * @param spectrum Current Input power/magnitude spectrum
+ * @param noise_spectrum Output: Updated noise spectrum
+ * @return true if successful
+ */
+bool brandt_noise_estimator_run(BrandtNoiseEstimator* self,
+                                const float* spectrum, float* noise_spectrum);
+
+/**
+ * @brief Force the internal stated to a specific profile
+ */
+void brandt_noise_estimator_set_state(BrandtNoiseEstimator* self,
+                                      const float* initial_profile);
+
+/**
+ * @brief Update the history seed without full reset
+ */
+void brandt_noise_estimator_update_seed(BrandtNoiseEstimator* self,
+                                        const float* seed_profile);
+
+/**
+ * @brief Apply a minimum floor to the estimate
+ */
+void brandt_noise_estimator_apply_floor(BrandtNoiseEstimator* self,
+                                        const float* floor_profile);
+
+void brandt_noise_estimator_set_history_duration(
+    const BrandtNoiseEstimator* self, float history_duration_ms,
+    uint32_t sample_rate, uint32_t fft_size);
+
+#endif
diff --git a/src/shared/noise_estimation/louizou_noise_estimator.c b/src/shared/noise_estimation/louizou_noise_estimator.c
deleted file mode 100644
--- a/src/shared/noise_estimation/louizou_noise_estimator.c
+++ /dev/null
@@ -1,300 +0,0 @@
-/*
-libspecbleach - A spectral processing library
-
-Copyright 2022 Luciano Dato <lucianodato@gmail.com>
-
-This library is free software; you can redistribute it and/or
-modify it under the terms of the GNU Lesser General Public
-License as published by the Free Software Foundation; either
-version 2.1 of the License, or (at your option) any later version.
-
-This library is distributed in the hope that it will be useful,
-but WITHOUT ANY WARRANTY; without even the implied warranty of
-MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-Lesser General Public License for more details.
-
-You should have received a copy of the GNU Lesser General Public
-License along with this library; if not, write to the Free Software
-Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
-*/
-
-#include "louizou_noise_estimator.h"
-#include "../configurations.h"
-#include "../utils/general_utils.h"
-#include "../utils/spectral_utils.h"
-#include <float.h>
-#include <math.h>
-#include <stdlib.h>
-#include <string.h>
-
-typedef struct FrameSpectrum {
-  float* smoothed_spectrum;
-  float* local_minimum_spectrum;
-  float* speech_present_probability_spectrum;
-} FrameSpectrum;
-
-struct LouizouNoiseEstimator {
-  uint32_t noise_spectrum_size;
-  float noisy_speech_ratio;
-
-  FrameSpectrum* current;
-  FrameSpectrum* previous;
-
-  float* minimum_detection_thresholds;
-  float* previous_noise_spectrum;
-  float* time_frequency_smoothing_constant;
-  uint32_t* speech_presence_detection;
-  bool is_first_frame;
-};
-
-static FrameSpectrum* frame_spectrum_initialize(uint32_t frame_size) {
-  FrameSpectrum* self = (FrameSpectrum*)calloc(1U, sizeof(FrameSpectrum));
-  if (!self) {
-    return NULL;
-  }
-
-  self->smoothed_spectrum = (float*)calloc(frame_size, sizeof(float));
-  self->local_minimum_spectrum = (float*)calloc(frame_size, sizeof(float));
-  self->speech_present_probability_spectrum =
-      (float*)calloc(frame_size, sizeof(float));
-
-  if (!self->smoothed_spectrum || !self->local_minimum_spectrum ||
-      !self->speech_present_probability_spectrum) {
-    if (self->smoothed_spectrum) {
-      free(self->smoothed_spectrum);
-    }
-    if (self->local_minimum_spectrum) {
-      free(self->local_minimum_spectrum);
-    }
-    if (self->speech_present_probability_spectrum) {
-      free(self->speech_present_probability_spectrum);
-    }
-    free(self);
-    return NULL;
-  }
-
-  (void)initialize_spectrum_with_value(self->local_minimum_spectrum, frame_size,
-                                       FLT_MIN);
-
-  return self;
-}
-
-static void frame_spectrum_free(FrameSpectrum* self) {
-  if (!self) {
-    return;
-  }
-  free(self->smoothed_spectrum);
-  free(self->local_minimum_spectrum);
-  free(self->speech_present_probability_spectrum);
-
-  free(self);
-}
-
-static void compute_auto_thresholds(LouizouNoiseEstimator* self,
-                                    uint32_t sample_rate,
-                                    uint32_t noise_spectrum_size,
-                                    uint32_t fft_size) {
-  uint32_t crossover_bin1 =
-      freq_to_fft_bin(CROSSOVER_POINT1, sample_rate, fft_size);
-  uint32_t crossover_bin2 =
-      freq_to_fft_bin(CROSSOVER_POINT2, sample_rate, fft_size);
-  for (uint32_t k = 0U; k < noise_spectrum_size; k++) {
-    if (k <= crossover_bin1) {
-      self->minimum_detection_thresholds[k] = BAND_1_LEVEL;
-    }
-    if (k > crossover_bin1 && k < crossover_bin2) {
-      self->minimum_detection_thresholds[k] = BAND_2_LEVEL;
-    }
-    if (k >= crossover_bin2) {
-      self->minimum_detection_thresholds[k] = BAND_3_LEVEL;
-    }
-  }
-}
-
-static void update_frame_spectums(LouizouNoiseEstimator* self,
-                                  const float* noise_spectrum) {
-  memcpy(self->previous_noise_spectrum, noise_spectrum,
-         sizeof(float) * self->noise_spectrum_size);
-  memcpy(self->previous->local_minimum_spectrum,
-         self->current->local_minimum_spectrum,
-         sizeof(float) * self->noise_spectrum_size);
-  memcpy(self->previous->smoothed_spectrum, self->current->smoothed_spectrum,
-         sizeof(float) * self->noise_spectrum_size);
-  memcpy(self->previous->speech_present_probability_spectrum,
-         self->current->speech_present_probability_spectrum,
-         sizeof(float) * self->noise_spectrum_size);
-}
-
-LouizouNoiseEstimator* louizou_noise_estimator_initialize(
-    uint32_t noise_spectrum_size, uint32_t sample_rate, uint32_t fft_size) {
-  LouizouNoiseEstimator* self =
-      (LouizouNoiseEstimator*)calloc(1U, sizeof(LouizouNoiseEstimator));
-  if (!self) {
-    return NULL;
-  }
-
-  self->noise_spectrum_size = noise_spectrum_size;
-
-  self->minimum_detection_thresholds =
-      (float*)calloc(self->noise_spectrum_size, sizeof(float));
-  self->time_frequency_smoothing_constant =
-      (float*)calloc(self->noise_spectrum_size, sizeof(float));
-  self->speech_presence_detection =
-      (uint32_t*)calloc(self->noise_spectrum_size, sizeof(uint32_t));
-  self->previous_noise_spectrum =
-      (float*)calloc(self->noise_spectrum_size, sizeof(float));
-
-  if (!self->minimum_detection_thresholds ||
-      !self->time_frequency_smoothing_constant ||
-      !self->speech_presence_detection || !self->previous_noise_spectrum) {
-    louizou_noise_estimator_free(self);
-    return NULL;
-  }
-
-  compute_auto_thresholds(self, sample_rate, noise_spectrum_size, fft_size);
-  self->current = frame_spectrum_initialize(noise_spectrum_size);
-  self->previous = frame_spectrum_initialize(noise_spectrum_size);
-
-  if (!self->current || !self->previous) {
-    louizou_noise_estimator_free(self);
-    return NULL;
-  }
-
-  self->noisy_speech_ratio = 0.F;
-  self->is_first_frame = true;
-
-  return self;
-}
-
-void louizou_noise_estimator_free(LouizouNoiseEstimator* self) {
-  if (!self) {
-    return;
-  }
-  free(self->minimum_detection_thresholds);
-  free(self->time_frequency_smoothing_constant);
-  free(self->speech_presence_detection);
-  free(self->previous_noise_spectrum);
-
-  frame_spectrum_free(self->current);
-  frame_spectrum_free(self->previous);
-
-  free(self);
-}
-
-bool louizou_noise_estimator_run(LouizouNoiseEstimator* self,
-                                 const float* spectrum, float* noise_spectrum) {
-  if (!self || !spectrum || !noise_spectrum) {
-    return false;
-  }
-
-  if (self->is_first_frame) {
-    for (uint32_t k = 0U; k < self->noise_spectrum_size; k++) {
-      self->current->smoothed_spectrum[k] = spectrum[k];
-      self->current->local_minimum_spectrum[k] = spectrum[k];
-      noise_spectrum[k] = spectrum[k];
-    }
-    self->is_first_frame = false;
-  } else {
-    for (uint32_t k = 0U; k < self->noise_spectrum_size; k++) {
-      self->current->smoothed_spectrum[k] =
-          (N_SMOOTH * self->previous->smoothed_spectrum[k]) +
-          ((1.F - N_SMOOTH) * spectrum[k]);
-
-      if (self->previous->local_minimum_spectrum[k] <
-          self->current->smoothed_spectrum[k]) {
-        self->current->local_minimum_spectrum[k] =
-            (GAMMA * self->previous->local_minimum_spectrum[k]) +
-            (((1.F - GAMMA) / (1.F - BETA_AT)) *
-             (self->current->smoothed_spectrum[k] -
-              (BETA_AT * self->previous->smoothed_spectrum[k])));
-      } else {
-        self->current->local_minimum_spectrum[k] =
-            self->current->smoothed_spectrum[k];
-      }
-
-      self->noisy_speech_ratio = sanitize_denormal(
-          self->current->smoothed_spectrum[k] /
-          (self->current->local_minimum_spectrum[k] + SPECTRAL_EPSILON));
-
-      if (self->noisy_speech_ratio > self->minimum_detection_thresholds[k]) {
-        self->speech_presence_detection[k] = 1U;
-      } else {
-        self->speech_presence_detection[k] = 0U;
-      }
-
-      self->current->speech_present_probability_spectrum[k] =
-          (ALPHA_P * self->previous->speech_present_probability_spectrum[k]) +
-          ((1.F - ALPHA_P) * (float)self->speech_presence_detection[k]);
-
-      self->time_frequency_smoothing_constant[k] =
-          ALPHA_D + ((1.F - ALPHA_D) *
-                     self->current->speech_present_probability_spectrum[k]);
-
-      noise_spectrum[k] =
-          (self->time_frequency_smoothing_constant[k] *
-           self->previous_noise_spectrum[k]) +
-          ((1.F - self->time_frequency_smoothing_constant[k]) * spectrum[k]);
-    }
-  }
-
-  update_frame_spectums(self, noise_spectrum);
-
-  return true;
-}
-
-void louizou_noise_estimator_set_state(LouizouNoiseEstimator* self,
-                                       const float* initial_profile) {
-  if (!self || !initial_profile) {
-    return;
-  }
-
-  for (uint32_t k = 0U; k < self->noise_spectrum_size; k++) {
-    float val = fmaxf(initial_profile[k], FLT_MIN);
-
-    self->previous_noise_spectrum[k] = val;
-    self->current->smoothed_spectrum[k] = val;
-    self->current->local_minimum_spectrum[k] = val;
-    self->previous->smoothed_spectrum[k] = val;
-    self->previous->local_minimum_spectrum[k] = val;
-  }
-
-  self->is_first_frame = false;
-}
-
-void louizou_noise_estimator_update_seed(LouizouNoiseEstimator* self,
-                                         const float* seed_profile) {
-  if (!self || !seed_profile) {
-    return;
-  }
-
-  for (uint32_t k = 0U; k < self->noise_spectrum_size; k++) {
-    float val = fmaxf(seed_profile[k], FLT_MIN);
-    self->previous_noise_spectrum[k] = val;
-    self->current->smoothed_spectrum[k] = val;
-    self->current->local_minimum_spectrum[k] = val;
-    self->previous->smoothed_spectrum[k] = val;
-    self->previous->local_minimum_spectrum[k] = val;
-  }
-
-  self->is_first_frame = false;
-}
-
-void louizou_noise_estimator_apply_floor(LouizouNoiseEstimator* self,
-                                         const float* floor_profile) {
-  if (!self || !floor_profile) {
-    return;
-  }
-
-  for (uint32_t k = 0U; k < self->noise_spectrum_size; k++) {
-    float floor_val = floor_profile[k];
-    if (self->previous_noise_spectrum[k] < floor_val) {
-      self->previous_noise_spectrum[k] = floor_val;
-    }
-    if (self->current->local_minimum_spectrum[k] < floor_val) {
-      self->current->local_minimum_spectrum[k] = floor_val;
-    }
-    if (self->previous->local_minimum_spectrum[k] < floor_val) {
-      self->previous->local_minimum_spectrum[k] = floor_val;
-    }
-  }
-}
diff --git a/src/shared/noise_estimation/louizou_noise_estimator.h b/src/shared/noise_estimation/louizou_noise_estimator.h
deleted file mode 100644
--- a/src/shared/noise_estimation/louizou_noise_estimator.h
+++ /dev/null
@@ -1,46 +0,0 @@
-/*
-libspecbleach - A spectral processing library
-
-Copyright 2022 Luciano Dato <lucianodato@gmail.com>
-
-This library is free software; you can redistribute it and/or
-modify it under the terms of the GNU Lesser General Public
-License as published by the Free Software Foundation; either
-version 2.1 of the License, or (at your option) any later version.
-
-This library is distributed in the hope that it will be useful,
-but WITHOUT ANY WARRANTY; without even the implied warranty of
-MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-Lesser General Public License for more details.
-
-You should have received a copy of the GNU Lesser General Public
-License along with this library; if not, write to the Free Software
-Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
-*/
-
-#ifndef LOUIZOU_NOISE_ESTIMATOR_H
-#define LOUIZOU_NOISE_ESTIMATOR_H
-
-#include <stdbool.h>
-#include <stdint.h>
-
-typedef struct LouizouNoiseEstimator LouizouNoiseEstimator;
-
-LouizouNoiseEstimator* louizou_noise_estimator_initialize(
-    uint32_t noise_spectrum_size, uint32_t sample_rate, uint32_t fft_size);
-
-void louizou_noise_estimator_free(LouizouNoiseEstimator* self);
-
-bool louizou_noise_estimator_run(LouizouNoiseEstimator* self,
-                                 const float* spectrum, float* noise_spectrum);
-
-void louizou_noise_estimator_set_state(LouizouNoiseEstimator* self,
-                                       const float* initial_profile);
-
-void louizou_noise_estimator_update_seed(LouizouNoiseEstimator* self,
-                                         const float* seed_profile);
-
-void louizou_noise_estimator_apply_floor(LouizouNoiseEstimator* self,
-                                         const float* floor_profile);
-
-#endif
diff --git a/src/shared/noise_estimation/martin_noise_estimator.c b/src/shared/noise_estimation/martin_noise_estimator.c
new file mode 100644
--- /dev/null
+++ b/src/shared/noise_estimation/martin_noise_estimator.c
@@ -0,0 +1,209 @@
+/*
+libspecbleach - A spectral processing library
+
+Copyright 2022 Luciano Dato <lucianodato@gmail.com>
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
+#include "martin_noise_estimator.h"
+#include "../configurations.h"
+#include <float.h>
+#include <math.h>
+#include <stdlib.h>
+#include <string.h>
+
+struct MartinNoiseEstimator {
+  uint32_t noise_spectrum_size;
+
+  float* smoothed_psd;       // Smoothed power spectral density
+  float* current_subwin_min; // Minimum observed in the current sub-window
+  float* subwin_history; // History of minimums from last MARTIN_SUBWIN_COUNT
+                         // sub-windows
+
+  uint32_t frame_count;  // Current frame index within the sub-window
+  uint32_t subwin_index; // Current sub-window index in history
+
+  bool is_first_frame;
+};
+
+MartinNoiseEstimator* martin_noise_estimator_initialize(
+    uint32_t noise_spectrum_size, uint32_t sample_rate, uint32_t fft_size) {
+  (void)sample_rate;
+  (void)fft_size;
+
+  MartinNoiseEstimator* self =
+      (MartinNoiseEstimator*)calloc(1U, sizeof(MartinNoiseEstimator));
+  if (!self) {
+    return NULL;
+  }
+
+  self->noise_spectrum_size = noise_spectrum_size;
+  self->smoothed_psd = (float*)calloc(noise_spectrum_size, sizeof(float));
+  self->current_subwin_min = (float*)calloc(noise_spectrum_size, sizeof(float));
+  self->subwin_history = (float*)calloc(
+      (size_t)noise_spectrum_size * MARTIN_SUBWIN_COUNT, sizeof(float));
+
+  if (!self->smoothed_psd || !self->current_subwin_min ||
+      !self->subwin_history) {
+    martin_noise_estimator_free(self);
+    return NULL;
+  }
+
+  self->is_first_frame = true;
+  self->frame_count = 0;
+  self->subwin_index = 0;
+
+  return self;
+}
+
+void martin_noise_estimator_free(MartinNoiseEstimator* self) {
+  if (!self) {
+    return;
+  }
+  free(self->smoothed_psd);
+  free(self->current_subwin_min);
+  free(self->subwin_history);
+  free(self);
+}
+
+bool martin_noise_estimator_run(MartinNoiseEstimator* self,
+                                const float* spectrum, float* noise_spectrum) {
+  if (!self || !spectrum || !noise_spectrum) {
+    return false;
+  }
+
+  float frame_energy = 0.F;
+  for (uint32_t k = 0U; k < self->noise_spectrum_size; k++) {
+    frame_energy += spectrum[k];
+  }
+  frame_energy /= (float)self->noise_spectrum_size;
+
+  if (self->is_first_frame) {
+    if (frame_energy < ESTIMATOR_SILENCE_THRESHOLD) {
+      memset(noise_spectrum, 0, self->noise_spectrum_size * sizeof(float));
+      return true;
+    }
+    for (uint32_t k = 0; k < self->noise_spectrum_size; k++) {
+      float val = spectrum[k] / MARTIN_BIAS_CORR;
+      self->smoothed_psd[k] = val;
+      self->current_subwin_min[k] = val;
+      // Initialize history with current value
+      for (uint32_t d = 0; d < MARTIN_SUBWIN_COUNT; d++) {
+        self->subwin_history[((size_t)k * MARTIN_SUBWIN_COUNT) + d] = val;
+      }
+      noise_spectrum[k] = spectrum[k];
+    }
+    self->is_first_frame = false;
+    self->frame_count = 1;
+    return true;
+  }
+
+  // Silence check for subsequent frames
+  if (frame_energy < ESTIMATOR_SILENCE_THRESHOLD) {
+    // Return existing estimate without updating internal state
+    goto calculate_output;
+  }
+
+  // 1. Update smoothed PSD
+  for (uint32_t k = 0; k < self->noise_spectrum_size; k++) {
+    self->smoothed_psd[k] = (MARTIN_SMOOTH_ALPHA * self->smoothed_psd[k]) +
+                            ((1.0F - MARTIN_SMOOTH_ALPHA) * spectrum[k]);
+  }
+
+  // 2. Track minimum in current sub-window
+  for (uint32_t k = 0; k < self->noise_spectrum_size; k++) {
+    if (self->smoothed_psd[k] < self->current_subwin_min[k]) {
+      self->current_subwin_min[k] = self->smoothed_psd[k];
+    }
+  }
+
+  // 3. Check if sub-window is complete
+  if (self->frame_count >= MARTIN_SUBWIN_LEN) {
+    // Store sub-window minimum in history
+    for (uint32_t k = 0; k < self->noise_spectrum_size; k++) {
+      self->subwin_history[((size_t)k * MARTIN_SUBWIN_COUNT) +
+                           self->subwin_index] = self->current_subwin_min[k];
+
+      // Reset current sub-window min for next cycle
+      self->current_subwin_min[k] = self->smoothed_psd[k];
+    }
+
+    self->subwin_index = (self->subwin_index + 1) % MARTIN_SUBWIN_COUNT;
+    self->frame_count = 0;
+  }
+
+calculate_output:
+  // 4. Calculate global minimum from history
+  for (uint32_t k = 0; k < self->noise_spectrum_size; k++) {
+    float min_val = self->current_subwin_min[k];
+    for (uint32_t d = 0; d < MARTIN_SUBWIN_COUNT; d++) {
+      float h_val = self->subwin_history[((size_t)k * MARTIN_SUBWIN_COUNT) + d];
+      if (h_val < min_val) {
+        min_val = h_val;
+      }
+    }
+
+    // Apply bias correction to estimate the mean noise power from its minimum
+    noise_spectrum[k] = min_val * MARTIN_BIAS_CORR;
+  }
+
+  self->frame_count++;
+  return true;
+}
+
+void martin_noise_estimator_set_state(MartinNoiseEstimator* self,
+                                      const float* initial_profile) {
+  if (!self || !initial_profile) {
+    return;
+  }
+  for (uint32_t k = 0; k < self->noise_spectrum_size; k++) {
+    float val = fmaxf(initial_profile[k], FLT_MIN) / MARTIN_BIAS_CORR;
+    self->smoothed_psd[k] = val;
+    self->current_subwin_min[k] = val;
+    for (uint32_t d = 0; d < MARTIN_SUBWIN_COUNT; d++) {
+      self->subwin_history[((size_t)k * MARTIN_SUBWIN_COUNT) + d] = val;
+    }
+  }
+  self->is_first_frame = false;
+  self->frame_count = 0;
+}
+
+void martin_noise_estimator_update_seed(MartinNoiseEstimator* self,
+                                        const float* seed_profile) {
+  martin_noise_estimator_set_state(self, seed_profile);
+}
+
+void martin_noise_estimator_apply_floor(MartinNoiseEstimator* self,
+                                        const float* floor_profile) {
+  if (!self || !floor_profile) {
+    return;
+  }
+  for (uint32_t k = 0; k < self->noise_spectrum_size; k++) {
+    float floor_val = floor_profile[k];
+    if (self->smoothed_psd[k] < floor_val) {
+      self->smoothed_psd[k] = floor_val;
+    }
+    if (self->current_subwin_min[k] < floor_val) {
+      self->current_subwin_min[k] = floor_val;
+    }
+    for (uint32_t d = 0; d < MARTIN_SUBWIN_COUNT; d++) {
+      if (self->subwin_history[((size_t)k * MARTIN_SUBWIN_COUNT) + d] <
+          floor_val) {
+        self->subwin_history[((size_t)k * MARTIN_SUBWIN_COUNT) + d] = floor_val;
+      }
+    }
+  }
+}
diff --git a/src/shared/noise_estimation/martin_noise_estimator.h b/src/shared/noise_estimation/martin_noise_estimator.h
new file mode 100644
--- /dev/null
+++ b/src/shared/noise_estimation/martin_noise_estimator.h
@@ -0,0 +1,53 @@
+/*
+libspecbleach - A spectral processing library
+
+Copyright 2022 Luciano Dato <lucianodato@gmail.com>
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
+#ifndef MARTIN_NOISE_ESTIMATOR_H
+#define MARTIN_NOISE_ESTIMATOR_H
+
+#include <stdbool.h>
+#include <stdint.h>
+
+/**
+ * Minimum Statistics noise estimator based on:
+ * Rainer Martin, "Noise Power Spectral Density Estimation Based on Optimal
+ * Smoothing and Minimum Statistics," IEEE Transactions on Speech and Audio
+ * Processing, vol. 9, no. 7, pp. 504-512, July 2001.
+ */
+
+typedef struct MartinNoiseEstimator MartinNoiseEstimator;
+
+MartinNoiseEstimator* martin_noise_estimator_initialize(
+    uint32_t noise_spectrum_size, uint32_t sample_rate, uint32_t fft_size);
+
+void martin_noise_estimator_free(MartinNoiseEstimator* self);
+
+bool martin_noise_estimator_run(MartinNoiseEstimator* self,
+                                const float* spectrum, float* noise_spectrum);
+
+void martin_noise_estimator_set_state(MartinNoiseEstimator* self,
+                                      const float* initial_profile);
+
+void martin_noise_estimator_update_seed(MartinNoiseEstimator* self,
+                                        const float* seed_profile);
+
+void martin_noise_estimator_apply_floor(MartinNoiseEstimator* self,
+                                        const float* floor_profile);
+
+#endif
diff --git a/src/shared/noise_estimation/meson.build b/src/shared/noise_estimation/meson.build
--- a/src/shared/noise_estimation/meson.build
+++ b/src/shared/noise_estimation/meson.build
@@ -1,7 +1,8 @@
 shared_sources += files(
     'adaptive_noise_estimator.c',
-    'louizou_noise_estimator.c',
     'noise_estimator.c',
     'noise_profile.c',
     'spp_mmse_noise_estimator.c',
+    'brandt_noise_estimator.c',
+    'martin_noise_estimator.c',
 )
\ No newline at end of file
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
