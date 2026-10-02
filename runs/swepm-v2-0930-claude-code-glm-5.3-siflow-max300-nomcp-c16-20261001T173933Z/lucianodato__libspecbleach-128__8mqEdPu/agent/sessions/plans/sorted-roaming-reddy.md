# HPSS Filter with Quality Modes (#128) — Implementation Plan

## Context

libspecbleach (C, `/testbed`) is a spectral denoising library with two public processors (1D denoiser, 2D NLM denoiser). PR #128 adds a Harmonic-Percussive Source Separation (HPSS) filter (Fitzgerald-style median-filter separation) with runtime-selectable quality modes including an OFF bypass. Percussive/transient content currently gets over-suppressed; HPSS masks are used to relax suppression at percussive bins (consolidated onset ducking). Includes an explicit contract: **clamp `noise_profile_offset_db` to the expanded [-12, +12] dB range** (currently ±6 dB).

Key architecture facts (verified):
- 3-layer chain: public header → `sb_*_params_sanitize` (`src/processors/specbleach_processor_core.c`) → `spectral_denoiser_run` / `spectral_2d_denoiser_run` (STFT per-frame callbacks).
- 2D denoiser already delays its output frame by the NLM look-ahead (4 frames) via `SbSpectralCircularBuffer` (`spectral_2d_denoiser.c:386-404`); NLM's internal target frame center is `head - search_range_time_future - 1` (`nlm_filter_internal.h:88-100`, uses the existing `target_frame_offset` field only at init).
- 1D denoiser has **no** delay line today; `specbleach_get_latency` returns STFT latency only.
- New `src/shared/**/*.c` files are auto-globbed into the library (CMakeLists.txt:125-127); only test registration needs a CMake edit.
- AGENTS.md rules: LGPL header on every file, constants (no magic numbers) in `src/shared/configurations.h`, OpenMP loop counters declared *outside* the `for`, FTZ/DAZ around heavy loops (`simd_utils.h`), no malloc/locks in audio path, clang-format before finishing.
- Public headers are standalone (no cross-includes), so a `typedef enum` cannot be defined in both — the mode is an `int` field with documented values (precedent: `noise_estimation_method`).

Design decisions (user declined clarification; using recommended options):
- 2D latency composes as `max(NLM look-ahead, HPSS look-ahead)` via a new minimal NLM target-offset setter (default 4 → OFF is bit-identical to today).
- HPSS effect: relax `alpha` toward `ALPHA_MIN` at percussive/onset bins, complementing (not replacing) `masking_veto_apply`.

## 1. Constants — `src/shared/configurations.h`

```c
// HPSS median-filter windows and look-ahead per quality mode (odd windows)
#define HPSS_HARMONIC_WINDOW_LOW 3U      // time-axis median length
#define HPSS_HARMONIC_WINDOW_MEDIUM 7U
#define HPSS_HARMONIC_WINDOW_HIGH 15U    // matches TONAL_MEDIAN_FILTER_WINDOW precedent
#define HPSS_PERCUSSIVE_WINDOW_LOW 9U    // frequency-axis median length
#define HPSS_PERCUSSIVE_WINDOW_MEDIUM 15U
#define HPSS_PERCUSSIVE_WINDOW_HIGH 21U
#define HPSS_LOOKAHEAD_FRAMES_LOW 1U     // (window-1)/2 future frames
#define HPSS_LOOKAHEAD_FRAMES_MEDIUM 3U
#define HPSS_LOOKAHEAD_FRAMES_HIGH 7U
#define HPSS_TIME_BUFFER_FRAMES 32U      // covers max window; reuse-style of DELAY_BUFFER_FRAMES
#define HPSS_MASK_FLOOR 1.0e-10F         // H^2 + P^2 denominator safety
#define HPSS_ONSET_DUCK_CEILING 1.0F
#define HPSS_MODE_OFF 0
#define HPSS_MODE_LOW 1
#define HPSS_MODE_MEDIUM 2
#define HPSS_MODE_HIGH 3
```

Also change lines 113-114 (the ±12 dB contract):
`NOISE_PROFILE_OFFSET_MIN_DB (-12.0F)` / `NOISE_PROFILE_OFFSET_MAX_DB (12.0F)`

## 2. New module — `src/shared/denoiser_logic/processing/hpss_filter.{h,c}`

Header API (LGPL header; modeled on `nlm_filter.h` / `tonal_reducer.h`):

```c
typedef struct HpssFilter HpssFilter;

typedef struct HpssFilterConfig {
  uint32_t spectrum_size;      // real_spectrum_size bins
  uint32_t time_buffer_size;   // frames retained (>= max window)
  uint32_t sample_rate;        // for critical bands
  uint32_t fft_size;
  CriticalBandType band_type;  // 1D/2D band layout for onset detection
} HpssFilterConfig;

HpssFilter* hpss_filter_initialize(HpssFilterConfig config);
void hpss_filter_free(HpssFilter* self);
bool hpss_filter_set_mode(HpssFilter* self, int mode);       // HPSS_MODE_*; validates range
int hpss_filter_get_mode(const HpssFilter* self);
void hpss_filter_push_frame(HpssFilter* self, const float* reference_frame);
bool hpss_filter_is_ready(const HpssFilter* self);
bool hpss_filter_process(HpssFilter* self, float* alpha);    // computes masks + ducks alpha in place
uint32_t hpss_filter_get_latency_frames(const HpssFilter* self); // lookahead of current mode; 0 if OFF
void hpss_filter_reset(HpssFilter* self);
const float* hpss_filter_get_harmonic_mask(const HpssFilter* self);   // real_spectrum_size, or NULL
const float* hpss_filter_get_percussive_mask(const HpssFilter* self);
```

Struct:
```c
struct HpssFilter {
  HpssFilterConfig config;
  int mode;
  float** frame_buffer;          // [time_buffer_size][spectrum_size]
  uint32_t buffer_head, frames_filled;
  uint32_t harmonic_window, percussive_window, lookahead_frames; // per-mode
  float* harmonic_mask, * percussive_mask;  // spectrum_size
  float* window_values;          // scratch: max median window
  CriticalBands* critical_bands;
  float* band_energies;          // number_critical_bands
  float* band_onset_weights;     // number_critical_bands
  TransientDetector* transient_detector;  // first production consumer of this module
};
```

Per-frame algorithm (`process`):
1. Gate: `NULL || mode == OFF || !is_ready` → return false (caller treats as bypass). OFF short-circuits before any work.
2. Target frame index = `buffer_head - 1 - lookahead_frames` (mod capacity). `is_ready` = `frames_filled >= harmonic_window`.
3. **Harmonic estimate H[k]**: median over `harmonic_window` frames centered on target (time axis), per bin. Local `hpss_insertion_sort()` (insertion sort beats qsort for W ≤ 21) — copy of the `tonal_detector.c:27-94` clamped sliding-window pattern, not a dependency on its internals.
4. **Percussive estimate P[k]**: median over `percussive_window` bins centered on k, within the target frame (frequency axis), same clamping.
5. Masks (soft, Fitzgerald 2010): `h2=H², p2=P²`; `harmonic_mask = h2/(h2+p2+HPSS_MASK_FLOOR)`; `percussive_mask = p2/(h2+p2+HPSS_MASK_FLOOR)` (masks sum to ~1).
6. **Onset ducking (consolidated)**: `compute_critical_bands_spectrum(target frame)` → `transient_detector_process(band_energies, band_onset_weights)` → expand band weights to bins using **`const`** subband bounds (`get_band_indexes`, loop with `const CriticalBandIndexes band_bounds` / const bounds array — the "const subband bounds" commit).
7. **Alpha ducking** (the "clarifying parentheses" commit — parenthesize `(1.0F - duck_amount)`):
   `duck_amount = fmaxf(percussive_mask[k], band_onset_bin[k]) * HPSS_ONSET_DUCK_CEILING`
   `alpha[k] = ALPHA_MIN + ((1.0F - duck_amount) * (alpha[k] - ALPHA_MIN))` — percussive/onset bins keep less oversubtraction so transients survive the Wiener gain.
8. Performance: wrap loops in `sb_simd_enable_ftz_daz()` / `sb_simd_restore_state()` (pattern: `nlm_filter_internal.h:184/321`); OpenMP `#pragma omp parallel for` over bins with the loop counter declared **outside** the `for`; reciprocal/`+ floor` instead of division.

**Warm-buffer mode switch (`fix(hpss)`)**: `hpss_filter_set_mode` only updates `harmonic_window` / `percussive_window` / `lookahead_frames` from the mode table (validate `HPSS_MODE_OFF..HIGH`, else return false). It **never** touches `frame_buffer`, `buffer_head`, or `frames_filled`. Buffer is allocated at `HPSS_TIME_BUFFER_FRAMES` at init so no mode ever needs reallocation. `push_frame` runs in every mode **including OFF**, so switching OFF→ON resumes on a warm buffer immediately.

## 3. Supporting changes

### `src/shared/utils/spectral_circular_buffer.{c,h}` — add clear
```c
void spectral_circular_buffer_clear(SbSpectralCircularBuffer* self);
```
Zeroes every layer's storage and resets `write_index = 0`; keeps layers/num_frames (no dealloc). NULL-safe.

### `src/shared/stft/stft_processor.{c,h}` — add getters (struct fields already exist)
```c
uint32_t get_stft_hop(const StftProcessor* self);
uint32_t get_stft_frame_size(const StftProcessor* self);
uint32_t get_stft_overlap_factor(const StftProcessor* self);
```
One-line returns with NULL guards (0). Needed by the 1D wrapper to convert HPSS latency frames → samples.

### `src/shared/denoiser_logic/processing/nlm_filter.{c,h}` + `nlm_filter_internal.h` — target-offset setter
- Add `void nlm_filter_set_target_offset(NlmFilter* filter, uint32_t offset);` — sets `target_frame_offset` clamped to `[search_range_time_future, time_buffer_size - search_range_time_past - 1]`; NULL-safe; no allocation.
- `get_frame()` (`nlm_filter_internal.h:88-100`): compute center as `head - target_frame_offset - 1 + relative_offset` instead of using `search_range_time_future`. Default stays 4 at init → **OFF-mode behavior bit-identical to today** (audio regression references stay valid).
- Do **not** resize the NLM time buffer (keep 21; search window wrapping character is unchanged, and only HIGH mode moves the center, by 3 frames max within the 21-frame ring).

## 4. Public API — `include/specbleach_denoiser.h`, `include/specbleach_2d_denoiser.h`

Add to both parameter structs (after `tonal_reduction`), as `int` with doc comment (enum-in-two-headers would be a redefinition error; `int` matches `noise_estimation_method` precedent):

```c
  /* Harmonic-Percussive Source Separation quality mode.
   * Separates harmonic from percussive content so transients survive the
   * reduction. 0: OFF (bypass, default), 1: LOW, 2: MEDIUM, 3: HIGH.
   * Higher modes use larger median windows and add look-ahead latency
   * (1 / 3 / 7 frames). */
  int hpss_mode;
```

Docs: update `noise_profile_offset_db` comment "Range: [-6.0, +6.0]" → "[-12.0, +12.0]" in both headers; update the 2D header's latency note to mention NLM/HPSS look-ahead.

## 5. Parameter sanitize — `src/processors/specbleach_processor_core.c`

Both `sb_denoiser_params_sanitize` and `sb_denoiser_2d_params_sanitize`:
- Add `.hpss_mode = (parameters.hpss_mode < HPSS_MODE_OFF || parameters.hpss_mode > HPSS_MODE_HIGH) ? HPSS_MODE_OFF : parameters.hpss_mode` (API robustness / configuration safety).
- The ±12 dB clamp needs **no code change** (already uses the macros); verify no hardcoded 6 nearby.

## 6. 1D integration

### `src/processors/denoiser/spectral_denoiser.h`
- `DenoiserParameters`: add `int hpss_mode;`.

### `src/processors/denoiser/spectral_denoiser.c`
- Struct: add `HpssFilter* hpss_filter;`, `SbSpectralCircularBuffer* circular_buffer;`, `uint32_t layer_fft, layer_noise;`, scratch `float* harmonic_mask, * percussive_mask;` (spectrum_size, owned by filter — actually masks live in the filter; the denoiser only needs `alpha`).
- Init: `spectral_circular_buffer_create(HPSS_TIME_BUFFER_FRAMES)` + `layer_fft` (fft_size) + `layer_noise` (real_spectrum_size); `hpss_filter_initialize` with `{real_spectrum_size, HPSS_TIME_BUFFER_FRAMES, sample_rate, fft_size, CRITICAL_BANDS_TYPE_1D}`; free in reverse; NULL-check each with the existing `spectral_denoiser_free(self); return NULL;` pattern.
- `load_reduction_parameters`: if `parameters.hpss_mode != current`, call `hpss_filter_set_mode` (warm switch) and update cached `last_hpss_mode`.
- `spectral_denoiser_run` (after profile update, before stage 3):
  1. `hpss_filter_push_frame(self->hpss_filter, reference_spectrum)` (every frame, all modes).
  2. `delay_frames = hpss_filter_get_latency_frames(...)`.
  3. If `delay_frames > 0`: push `fft_spectrum` → `layer_fft`, `noise_spectrum` → `layer_noise`; retrieve both at `delay_frames`; `memcpy(fft_spectrum, delayed_fft, fft_size * sizeof(float))`; use the delayed noise for the gain chain; recompute `reference_spectrum = get_spectral_feature(..., fft_spectrum, ...)` so the whole downstream chain is aligned to the delayed frame. If OFF (delay 0): path is untouched — bit-identical.
  4. `hpss_filter_process(self->hpss_filter, self->alpha)` **after** `suppression_engine_calculate` and **before** `tonal_reducer_run` (alpha must exist first; tonal reducer only ever boosts alpha upward so ordering is safe).
  5. `spectral_circular_buffer_advance` at end (only when the ring is in use; pushing/advancing only when `delay_frames > 0` keeps OFF identical — but note HPSS's own ring is always pushed in step 1, independent of this).
- Add `uint32_t spectral_denoiser_get_hpss_latency_frames(SpectralProcessorHandle instance);` to the header + impl (NULL-safe, delegates to the filter).

### `src/processors/specbleach_denoiser.c`
- `specbleach_get_latency` (lines 86-94): `stft_latency + (spectral_denoiser_get_hpss_latency_frames(...) * get_stft_hop(self->core->stft_processor))`. OFF → 0 extra (assert-equal to today).

## 7. 2D integration

### `src/processors/denoiser2d/spectral_2d_denoiser.h`
- `Denoiser2DParameters`: add `int hpss_mode;`.

### `src/processors/denoiser2d/spectral_2d_denoiser.c`
- Struct: add `HpssFilter* hpss_filter;`, `int last_hpss_mode;`.
- Init: `hpss_filter_initialize({real_spectrum_size, HPSS_TIME_BUFFER_FRAMES, sample_rate, fft_size, CRITICAL_BANDS_TYPE_2D})`; free alongside the other modules. **Reuse the existing `circular_buffer`/`layer_fft`/`layer_noise` — no second ring.**
- `load_2d_reduction_parameters`: on mode change, `hpss_filter_set_mode` (warm) and cache.
- `spectral_2d_denoiser_run`:
  - Push `reference_spectrum` into HPSS (new, after step 2 noise estimation).
  - Delay composition (replaces line 395):
    `delay_frames = max(nlm_filter_get_latency_frames(nlm), hpss_filter_get_latency_frames(hpss))`;
    call `nlm_filter_set_target_offset(self->nlm_filter, delay_frames)` whenever `delay_frames` differs from the cached value (control-side switch already happened via load_parameters; setter is allocation-free and NULL-safe).
  - Everything else (memcpy delayed frame at line 404, NLM push/process, suppression, tonal, veto, gains, post-process) unchanged, except:
  - Insert `hpss_filter_process(self->hpss_filter, self->alpha)` after `suppression_engine_calculate` (3.3.2) and before `tonal_reducer_run` (3.3.3).
- `spectral_2d_denoiser_get_latency_frames` (lines 486-495): return the composed `max(nlm, hpss)` value (add hpss NULL guard → falls back to NLM only).

### `src/processors/specbleach_2d_denoiser.c`
- `specbleach_2d_get_latency` (lines 91-107): no formula change needed — it already multiplies `spectral_2d_denoiser_get_latency_frames` by hop; the composed value now includes HPSS. OFF → NLM's 4 (today's value).

## 8. `.codecov.yml` — patch status

```yaml
coverage:
  status:
    project:
      default:
        target: auto
        threshold: 1%
        paths:
          - "src/**"
    patch:
      default:
        target: 80%
        threshold: 1%
          paths:
          - "src/**"
```
(keep existing `ignore:` and `comment:` blocks; fix indentation so paths sits under patch.default).

## 9. Tests

### New `tests/test_hpss_filter.c` (+ `add_specbleach_test(test_hpss_filter "test_hpss_filter.c")` in `CMakeLists.txt` after line 247)
Local `TEST_ASSERT`/`TEST_FLOAT_CLOSE` macros (per-file convention). Coverage:
- Lifecycle: init (valid config → non-NULL; `spectrum_size == 0` → NULL), free(NULL), reset(NULL), set_mode(NULL).
- Modes: `set_mode` accepts 0..3, rejects -1/4; `get_latency_frames` == 0/1/3/7 per mode; OFF `process` returns false and leaves alpha untouched.
- Warm-up: `is_ready` false until `frames_filled >= harmonic_window`; true after.
- **Warm-buffer switch (regression for the fix commit)**: run in HIGH until ready → switch MEDIUM → still ready, `process` succeeds immediately; HIGH → OFF → HIGH: still ready; masks still valid.
- Mask math: constant frame → masks sum to ~1 per bin; steady harmonic bin (constant over time, isolated in freq) → `harmonic_mask > 0.5`; broadband single-frame burst → `percussive_mask > 0.5` at burst bins.
- Alpha ducking: feed a percussive burst frame, verify `alpha[k]` pulled toward `ALPHA_MIN` at percussive bins and unchanged elsewhere (parenthesized formula).
- `reset()` → not ready, `frames_filled == 0`; buffer contents zeroed.

### `tests/test_spectral_circular_buffer.c` — new `test_circular_buffer_clear`
push non-zero → `clear` → all frames zero via retrieve at several delays, write_index reset (push after clear lands at frame 0), layers/ids preserved; `clear(NULL)` no-op.

### `tests/test_stft_latency.c` — getter coverage
Assert `get_stft_hop == frame_size/overlap`, `get_stft_frame_size == expected_frame`, `get_stft_overlap_factor` round-trip, and NULL-handle → 0 for all three.

### `tests/test_specbleach_processor_core.c`
- Update clamp expectations (±12 dB): `10^(-12/20) = 0.2512f`, `10^(+12/20) = 3.9811f` (lines 216-235; +2 dB `1.2589f` at line 188 unchanged).
- Add `hpss_mode` sanitize checks: passthrough for 0..3, out-of-range (-1, 7) → `HPSS_MODE_OFF`, for both 1D and 2D sanitize functions.

### `tests/test_specbleach_denoiser.c` — expanded 1D parameter tests + latency
- New `test_hpss_modes_and_latency()`: for each mode load params (with `learn_noise=false`, `reduction_amount = 20.f`) and process ≥ 8 blocks of 1024 samples (impulse-ish input, e.g. `input[i] = ((i % 256) == 0) ? 1.f : 0.05f`); assert `specbleach_get_latency` == STFT latency for OFF and `STFT + (1/3/7) * hop` for LOW/MEDIUM/HIGH (hop = frame_size/4 = 220 @ 44.1 kHz/20 ms). Assert processing with HIGH ≠ OFF output (diff_sum pattern from `test_2d_smoothing_factor_responsiveness`). NULL-safety: `specbleach_get_latency(NULL) == 0` (already covered).
- Out-of-range `hpss_mode` (e.g. 9) loads fine and behaves as OFF.

### `tests/test_specbleach_2d_denoiser.c` — expanded 2D parameter tests + latency
- New `test_2d_hpss_modes_and_latency()`: same structure; latency: OFF/MEDIUM/LOW == `stft + 4*hop` (NLM floor), HIGH == `stft + 7*hop`; processing per mode succeeds and HIGH output differs from OFF. Mode switch mid-stream (HIGH → LOW) keeps `specbleach_2d_process` returning true.

### `tests/test_transient_detector.c` — transient attack coverage
Add a test with a decaying impulse train: first burst frame → `weight > 0.8` at attacked band, subsequent decay frames → weight returns toward 0; assert global `transient_detected` true only on attack frames (verify exponential release behavior of `TRANSIENT_SMOOTH_ALPHA`).

### `tests/test_noise_floor_manager.c` — reduction curve coverage
Extend `test_noise_floor_manager_reduction_curve` (line 185): negative-bias curve (less reduction), strongly positive curve (more reduction), and a mixed curve asserting per-bin ordering of gains.

## 10. CHANGELOG.md
Add an entry under the pending-release section summarizing: HPSS filter with quality modes (OFF/LOW/MEDIUM/HIGH), latency changes, warm-buffer mode switching, `noise_profile_offset_db` range widened to ±12 dB, circular buffer clear + STFT getters utilities.

## Verification

1. `cmake -B build -DCMAKE_BUILD_TYPE=Release -DENABLE_TESTS=ON` (do NOT delete `build/` per AGENTS.md; reconfigure to pick up the new globbed source).
2. `cmake --build build -j4`.
3. `cd build && ctest --output-on-failure` — all existing tests (esp. `test_audio_file_regression`, `test_audio_regression`, `test_integration`) must stay green: OFF mode is the default (`hpss_mode` zero-initialized) and the NLM default target offset is unchanged, so reference files must match.
4. Lint: `clang-format -i` on every touched/new `.c`/`.h`, verify with `clang-format --dry-run --Werror` (as `.github/workflows/lint.yml` does); run `clang-tidy` over `src/`.
5. Confirm new HPSS lines are exercised (target ≥ 80% for the codecov patch gate) via the new/expanded tests.
