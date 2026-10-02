NLM Optimization: SIMD abstraction, AVX/AVX2 support and FTZ/DAZ (#90)

* perf: Enable SSE flush-to-zero and denormals-are-zero modes for NLM filter processing.

* feat: Introduce AVX/AVX2 optimizations for NLM filter, simplify NoiseFloorManager initialization, and refine floating-point comparisons.

* chore: Remove `--masking-elasticity` from reference generation script and reformat `NoiseFloorManager` initialization.

* feat: Add cross-platform SIMD utility functions for 4-wide and 8-wide float vectors, and update nlm_filter to utilize them.

* refactor: introduce and apply `SB_SIMD_INLINE` macro to SIMD utility functions.

* style: fix indentation of `sb_acc8_add_ssd` function parameter.

* refactor: Extract SIMD denormal handling into utility functions and apply them in the NLM filter.

* docs: add CodeRabbit Pull Request Reviews badge to README.

* Fix `__ARM_NEON` macro and `sb_store4` memcpy, and improve NLM filter boundary safety and NEON division implementation.

* fix: Ensure NoiseFloorManager uses its internal FFT size for processing and refine ARM NEON SIMD state handling.

* Refactor SIMD denormal handling to use named constants and correct ARM64 state management, and add a test assertion for NoiseFloorManager initialization.

* fix: Normalize `sb_sel8` mask input to ensure consistent behavior across SIMD backends.

* feat: Optimize SIMD division for AArch64 NEON and refine mask normalization in selection functions.

* Implement dynamic AVX dispatch for NLM filter

* Fix unused function warnings in nlm_filter_internal.h

* perf: skip NLM filter processing for silent blocks to avoid unnecessary computation

* Fix CI issues: fix cppcheck shadowed variable, fix clang-format length limit, and add silent block test for codecov

* Add tests to increase coverage: test_simd_utils, mismatch in NFM, and explicit generic/avx NLM testing for 100% patch coverage

* Fix formatting violations in tests and utilities

* Fix remaining clang-format violations: pack arguments and remove trailing space

* Fix final formatting issues: remove trailing spaces and fix column limit

---------

Co-authored-by: Luciano Dato <luciano.dato@jll.com>

Additional NLM dispatch contracts covered by the tests: keep the internal NLM dispatch interface available through `nlm_filter_internal.h`. `NlmFilter` should expose the tested `process_fn` dispatch field, and both `nlm_filter_process_generic` and, on supported x86 builds, `nlm_filter_process_avx` should be callable directly and produce results consistent with `nlm_filter_process`.
