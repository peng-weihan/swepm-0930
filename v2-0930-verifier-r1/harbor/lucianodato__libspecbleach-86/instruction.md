Refactor almost all modules to prepare for future processors (#86)

* Refactor almost all modules to prepare for future processors

* refactor: Introduce a spectral circular buffer and refactor denoiser configurations into 1D and 2D specific settings.

* refactor: Delegate NLM latency, SNR calculation, and magnitude reconstruction to the `nlm_filter` module, and remove unused configuration defines.

* feat: replace `spectral_trailing_buffer` with `spectral_circular_buffer` for median noise estimation.

* refactor: Remove duplicate assignment of `self->noise_profile`.

Additional internal module contracts covered by the tests: provide the `spectral_circular_buffer` API with the expected create/add-layer/push/retrieve/advance/free lifecycle and deterministic delay semantics for delay values 0, 1, and 2. The suppression engine should expose the tested strategies and numeric alpha behavior, and NLM latency, SNR calculation, and magnitude reconstruction should be delegated through the `nlm_filter` module with the tested helper signatures and null/boundary behavior.
