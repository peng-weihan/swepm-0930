The project’s Plonky3 dependency stack needs to be updated from the 0.5.x series to Plonky3 v0.6.0 while preserving the existing lifted STARK prover/verifier behavior.

After the update, the workspace should compile and the existing STARK tests should continue to pass. In particular, the public AIR trait surface must match the Plonky3 v0.6.0 expectations: methods such as `periodic_columns`, `preprocessed_trace`, `preprocessed_width`, and related base AIR metadata should be available from the appropriate base AIR trait implementation rather than requiring lifted AIR implementations. Constraint evaluation should also continue to expose periodic values to AIR builders, and transition constraints should use the current transition selector API.

The lifted STARK implementation must remain compatible with the updated Plonky3 APIs for DFT/LDE generation, matrix bit-reversal/layout handling, field extension packing/unpacking, polynomial evaluation, quotient commitment, FRI/PCS interactions, and batched linear combination utilities. Code that previously depended on Plonky3 0.5.x-only helper traits, modules, or method signatures should be updated to the v0.6.0 equivalents.

Verifier-side periodic polynomial out-of-domain evaluation must remain correct. Periodic polynomial coefficients are stored in ascending degree order as produced by the inverse DFT, and evaluating them at the appropriate power of the out-of-domain point should produce the same values as before.

The dependency lockfile and changelog should reflect the breaking upgrade to Plonky3 v0.6.0.
