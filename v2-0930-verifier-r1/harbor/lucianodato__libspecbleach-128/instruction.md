feat: implement Harmonic-Percussive Source Separation (HPSS) filter with quality modes (#128)

* feat: implement Harmonic-Percussive Source Separation (HPSS) filter with dynamic quality modes and add related utility methods

* feat: add HPSS quality mode selection and allow bypassing the filter via new OFF mode

* fix(hpss): maintain warm spectral buffer and avoid reset on quality mode switch

* style: fix formatting and clang-tidy readability warnings

* test: add test coverage for HPSS modes, circular buffer clear, and STFT getters

* test: expand 1D and 2D parameter tests with active processing

* test: add transient attack and reduction curve test coverage

* test: verify HPSS mode latency in 1D and 2D denoisers

* ci: configure patch coverage target and threshold in .codecov.yml

* refactor: optimize HPSS filtering performance, consolidate onset ducking logic, and improve API robustness and configuration safety

* refactor: add clarifying parentheses to alpha calculation for improved readability

* refactor: mark subband bounds array as const in hpss_filter

Additional configuration-safety contract covered by the tests: `noise_profile_offset_db` should be clamped to the expanded `[-12 dB, +12 dB]` range wherever denoiser parameters are validated or copied, instead of the earlier narrower range.
