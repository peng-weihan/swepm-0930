feat: Introduce tonal detection and support multiple noise reduction … (#83)

* feat: Introduce tonal detection and support multiple noise reduction modes for 2D denoiser.

* refactor: remove boundary checks when spreading tonal mask influence to neighboring bins.

Additional public API contracts covered by the tests: replace the previous 2D denoiser `noise_reduction_mode` field/API with `aggressiveness` and `tonal_reduction`, support noise profile modes `1` through `4`, rename the noise profile `blocks_averaged` accessors/fields to `block_count`, and apply the corresponding parameter/API changes to the 1D denoiser entry points as well as the 2D denoiser.
