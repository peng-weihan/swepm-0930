#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/CHANGELOG.md b/CHANGELOG.md
--- a/CHANGELOG.md
+++ b/CHANGELOG.md
@@ -3,6 +3,7 @@
 - [BREAKING] Upgraded the RustCrypto and dalek stack: `der`, `hkdf`, `sha2`, `sha3`, `k256`, `curve25519-dalek`, `ed25519-dalek`, and `x25519-dalek` ([#1045](https://github.com/0xMiden/crypto/pull/1045)).
 - Added `Display` (`0x`-prefixed lowercase hex) for the public key and signature types of all DSA schemes ([#1048](https://github.com/0xMiden/crypto/pull/1048)).
 - Use faster DFT algorithm for `PeriodicPolys` ([#1054](https://github.com/0xMiden/crypto/pull/1054)).
+- [BREAKING] Bumped Plonky3 upstream dependencies to v0.6.0 ([#1053](https://github.com/0xMiden/crypto/pull/1053)).
 
 ## 0.26.0 (06-02-2026)
 
diff --git a/Cargo.lock b/Cargo.lock
--- a/Cargo.lock
+++ b/Cargo.lock
@@ -953,21 +953,15 @@ dependencies = [
 
 [[package]]
 name = "hashbrown"
-version = "0.16.1"
+version = "0.17.1"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "841d1cc9bed7f9236f321df977030373f4a4163ae1a7dbfe1a51a2c1a51d9100"
+checksum = "ed5909b6e89a2db4456e54cd5f673791d7eca6732202bbf2a9cc504fe2f9b84a"
 dependencies = [
  "allocator-api2",
  "equivalent",
  "foldhash 0.2.0",
 ]
 
-[[package]]
-name = "hashbrown"
-version = "0.17.1"
-source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "ed5909b6e89a2db4456e54cd5f673791d7eca6732202bbf2a9cc504fe2f9b84a"
-
 [[package]]
 name = "heck"
 version = "0.5.0"
@@ -1386,7 +1380,6 @@ dependencies = [
  "p3-field",
  "p3-fri",
  "p3-goldilocks",
- "p3-interpolation",
  "p3-keccak",
  "p3-keccak-air",
  "p3-matrix",
@@ -1572,9 +1565,9 @@ checksum = "c08d65885ee38876c4f86fa503fb49d7b507c2b62552df7c70b2fce627e06381"
 
 [[package]]
 name = "p3-air"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "c824e8d7c7ddf208b742eac8d48e0b2d52d22fa013578a7762bf6931dbab1f46"
+checksum = "c67c21e8bf70e8e7238f24e17ab26dbcf4df43054457d9cd31af456572244aed"
 dependencies = [
  "p3-field",
  "p3-matrix",
@@ -1583,11 +1576,11 @@ dependencies = [
 
 [[package]]
 name = "p3-batch-stark"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "9123efa7645acd6d0a3f61b56823e306551dfb8566c070595e4a59cfb7c3cb54"
+checksum = "42faaf32cdf634786e6a392c0e39b2fd21626ab8946b2447b5364f9eafd61326"
 dependencies = [
- "hashbrown 0.16.1",
+ "hashbrown 0.17.1",
  "p3-air",
  "p3-challenger",
  "p3-commit",
@@ -1598,14 +1591,15 @@ dependencies = [
  "p3-uni-stark",
  "p3-util",
  "serde",
+ "thiserror",
  "tracing",
 ]
 
 [[package]]
 name = "p3-blake3"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "2733229a713bd83ccf5eb749e8f8e7380c1052674394a25c0422a772204a20af"
+checksum = "9fbade8790087344c0fb06cd2c99361e32d76c813219301baf4c6192d856870c"
 dependencies = [
  "blake3",
  "p3-symmetric",
@@ -1614,9 +1608,9 @@ dependencies = [
 
 [[package]]
 name = "p3-blake3-air"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "3a035146aa99f465d95ff221e76b7c00837a6686b03b9a758d8d5b004d0e609b"
+checksum = "d8729f8dd68391397285ab1327ff1e97de03408cfda21e13a5efb5bc897e81d9"
 dependencies = [
  "itertools 0.14.0",
  "p3-air",
@@ -1629,9 +1623,9 @@ dependencies = [
 
 [[package]]
 name = "p3-bn254"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "d59da83aac1a65e3197477737a90a9aed1049df93674cae2f7b9fca6e0a4a896"
+checksum = "9e929140ccfffe541dc740d833c2e964b40718ed20f00ec37d6945423f5512eb"
 dependencies = [
  "num-bigint",
  "p3-field",
@@ -1645,9 +1639,9 @@ dependencies = [
 
 [[package]]
 name = "p3-challenger"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "8972ccd1d5dc90e46cdb1f2ab4ee2bae49b3917e5e98aa533f0c2b779c010445"
+checksum = "5974b8830874434511fe248a9ff6af5ff528be29b7d6bd490c92babdbeea6573"
 dependencies = [
  "p3-field",
  "p3-maybe-rayon",
@@ -1659,39 +1653,40 @@ dependencies = [
 
 [[package]]
 name = "p3-commit"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "e5451768a715d8b7a30e64e23f5f78d3d37880ff18aedaa337181acece89b5e4"
+checksum = "6f531e7de6c5f9ee84dbc26569aa03e99d7e6d3bef7eb849e3739ab28c407715"
 dependencies = [
  "itertools 0.14.0",
  "p3-challenger",
  "p3-dft",
  "p3-field",
  "p3-matrix",
+ "p3-multilinear-util",
  "p3-util",
  "serde",
 ]
 
 [[package]]
 name = "p3-dft"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "17771aca44632f9cc11f2718d7ea7ec06794946c4190ef3a985bfc893f14c18a"
+checksum = "d44288108a5bff5097431b1ad303060bd62fc30f2ed7a7221ca780f9be79b6b3"
 dependencies = [
  "itertools 0.14.0",
  "p3-field",
  "p3-matrix",
  "p3-maybe-rayon",
  "p3-util",
- "spin 0.10.0",
+ "spin 0.12.0",
  "tracing",
 ]
 
 [[package]]
 name = "p3-field"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "6f3eb24d0591fd4d282d89cbe4e4efba5571c699375006f80b2cbf53ce83461c"
+checksum = "b97263e43047816338df728790380d18691a2d1118aab4628df704b3d16cbe63"
 dependencies = [
  "itertools 0.14.0",
  "num-bigint",
@@ -1705,31 +1700,30 @@ dependencies = [
 
 [[package]]
 name = "p3-fri"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "cb728959a6e6bd646238d9de49e873c886c66b74d36e7bff6e1edd567b0c15b4"
+checksum = "44ac3cbf36edd2c80bdc458f11630a4126afa1c356ae08a56308289fdc94f829"
 dependencies = [
  "itertools 0.14.0",
  "p3-challenger",
  "p3-commit",
  "p3-dft",
  "p3-field",
- "p3-interpolation",
  "p3-matrix",
  "p3-maybe-rayon",
  "p3-util",
  "rand 0.10.1",
  "serde",
- "spin 0.10.0",
+ "spin 0.12.0",
  "thiserror",
  "tracing",
 ]
 
 [[package]]
 name = "p3-goldilocks"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "5751c6591a0d2397d726620c2c29a7436ec6c5e19d2ed74ca5d078d4fbb18eb5"
+checksum = "6b3230de2e5daac8fb5d521e11019d8e4d155435efdfba1ed3cbcbee1b6af8fc"
 dependencies = [
  "num-bigint",
  "p3-challenger",
@@ -1745,23 +1739,11 @@ dependencies = [
  "serde",
 ]
 
-[[package]]
-name = "p3-interpolation"
-version = "0.5.3"
-source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "506c480fb775bb6399e49053a8e05b5e04ea67d47e430f4d4d3e5257a4f47da5"
-dependencies = [
- "p3-field",
- "p3-matrix",
- "p3-maybe-rayon",
- "p3-util",
-]
-
 [[package]]
 name = "p3-keccak"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "77a7df174ff0c19a8742eb4698eaa1667c5f858d018e2faf09c55f1f24a6f9c3"
+checksum = "213062f2c3d0294f64489403fb8f781c72318bd043422ba5cd89922895c87d3e"
 dependencies = [
  "p3-symmetric",
  "p3-util",
@@ -1770,9 +1752,9 @@ dependencies = [
 
 [[package]]
 name = "p3-keccak-air"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "634c2d5e1221a0c92175a528fe9816e4957f043906a5271ff9dca937ec7877e6"
+checksum = "9262e03c62b4e051f0e2bfbac52e5d8f800f5d29a133dc90e0168a96ea529159"
 dependencies = [
  "p3-air",
  "p3-field",
@@ -1785,25 +1767,27 @@ dependencies = [
 
 [[package]]
 name = "p3-lookup"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "a9698f0b4875ce5e44665088ced76a5c997e5818fab82cf4d973c83cbe5951ad"
+checksum = "1de7f92c3a1cbbe6803e8cc9524533c10639e922db3273bb67a878adf163b734"
 dependencies = [
- "hashbrown 0.16.1",
+ "hashbrown 0.17.1",
+ "num-bigint",
  "p3-air",
  "p3-field",
  "p3-matrix",
  "p3-maybe-rayon",
  "p3-uni-stark",
  "serde",
+ "thiserror",
  "tracing",
 ]
 
 [[package]]
 name = "p3-matrix"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "ea9c94c0714944e7b8a9a62e6340b1e3e1d3f8ecfd3e35c08798360200e73eff"
+checksum = "4ddef2a157f3b2d0c06d79aa43829098612181e77b4d3cf018b96e5339d12ea9"
 dependencies = [
  "itertools 0.14.0",
  "p3-field",
@@ -1816,18 +1800,18 @@ dependencies = [
 
 [[package]]
 name = "p3-maybe-rayon"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "eebc233a34b1ab0273f35b4052fa2eeb3114b22ba4575bd7da00716e878ffb77"
+checksum = "e613f4cac6197191c80b6445dc225e5a06c03c71b974a6223beb44f3ac7e5ffa"
 dependencies = [
  "rayon",
 ]
 
 [[package]]
 name = "p3-mds"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "6b5441fa8116246ec9e6c835f15273cb27777ca572960ec87476b67fef13e01e"
+checksum = "d202b0bbac217b427c88f1a4f37dc097c90f4b7acd2e4b5d7efe653346166c5b"
 dependencies = [
  "p3-dft",
  "p3-field",
@@ -1838,9 +1822,9 @@ dependencies = [
 
 [[package]]
 name = "p3-merkle-tree"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "0946a5207b6092b5e9aac025732d8e824e43edae08b6adff3b8ce1019b70b350"
+checksum = "f10f4d1ee4e5add748fbf9da19f8d7f727eefde917090d9fbf499f0b52eda853"
 dependencies = [
  "itertools 0.14.0",
  "p3-commit",
@@ -1851,15 +1835,16 @@ dependencies = [
  "p3-util",
  "rand 0.10.1",
  "serde",
+ "spin 0.12.0",
  "thiserror",
  "tracing",
 ]
 
 [[package]]
 name = "p3-mersenne-31"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "012351fb727ba404175ea1cc159fb6234fa370ce9399317ba04d38ca43e55bfa"
+checksum = "3c06a5ace7622835da25bb9125c1f93de7e87eedb8d8edf58640a44c14a1e81f"
 dependencies = [
  "itertools 0.14.0",
  "num-bigint",
@@ -1868,6 +1853,7 @@ dependencies = [
  "p3-field",
  "p3-matrix",
  "p3-mds",
+ "p3-poseidon1",
  "p3-poseidon2",
  "p3-symmetric",
  "p3-util",
@@ -1878,9 +1864,9 @@ dependencies = [
 
 [[package]]
 name = "p3-monty-31"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "8724f330ea6d19dd4f2436aa0f88b5fcbf88f0f55ca7fccd3fea8b736dbcddad"
+checksum = "9c96a02490c04c8211a4393a115507296b6a73967c19a586a86301740141420a"
 dependencies = [
  "itertools 0.14.0",
  "num-bigint",
@@ -1896,26 +1882,43 @@ dependencies = [
  "paste",
  "rand 0.10.1",
  "serde",
- "spin 0.10.0",
+ "spin 0.12.0",
+ "tracing",
+]
+
+[[package]]
+name = "p3-multilinear-util"
+version = "0.6.0"
+source = "registry+https://github.com/rust-lang/crates.io-index"
+checksum = "2b91bb1e05117e58c87eb87e57152c5d75585f9e695a4b124144abfaf28388dd"
+dependencies = [
+ "itertools 0.14.0",
+ "p3-field",
+ "p3-matrix",
+ "p3-maybe-rayon",
+ "p3-util",
+ "rand 0.10.1",
+ "serde",
  "tracing",
 ]
 
 [[package]]
 name = "p3-poseidon1"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "04e2a562fea210baae390a32f9ecf0dd8724ae3f4352d1c8e413077b6f00a162"
+checksum = "d8167c4110371fd84bd972c2dce068aae6b983ca6afb00569a23c7ddfd582c43"
 dependencies = [
  "p3-field",
+ "p3-mds",
  "p3-symmetric",
  "rand 0.10.1",
 ]
 
 [[package]]
 name = "p3-poseidon2"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "06394851c161d17e4aa4ad2aad5557d32f14cadd1dc838f965d8e1821a63b8c5"
+checksum = "cac1cceb7d79a5ebb6e23d2129d37dcc037bac01aa078d1e9ba67ae0d470c9bd"
 dependencies = [
  "p3-field",
  "p3-mds",
@@ -1926,9 +1929,9 @@ dependencies = [
 
 [[package]]
 name = "p3-poseidon2-air"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "8ebddb36356d46d5194a937eb4a033bfac2fde09876a8a6ea46c47342c7026cf"
+checksum = "93cdaea081595576413b5340e7c5ba7f97d5c7e0becc3977ca6c9623640cc883"
 dependencies = [
  "p3-air",
  "p3-field",
@@ -1941,9 +1944,9 @@ dependencies = [
 
 [[package]]
 name = "p3-symmetric"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "9ac1a276d421f8ef3361bb7d8c39a02c93c6b3f10eeaa559cc4c50222f9a5b82"
+checksum = "a7535a9e719089873bd1a85571fb8921c685209081eb1d295f2a2af6a42b3f68"
 dependencies = [
  "itertools 0.14.0",
  "p3-field",
@@ -1953,15 +1956,17 @@ dependencies = [
 
 [[package]]
 name = "p3-uni-stark"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "751bb3d740a7795a0da12ae86749df4bc12bd996d0bfd3c6f7ee62652db0e0c3"
+checksum = "f3579c6446a3046f53e8c2cbc0dd59d7cfe761d9f4fb26d47e8a67415987394f"
 dependencies = [
  "itertools 0.14.0",
+ "libm",
  "p3-air",
  "p3-challenger",
  "p3-commit",
  "p3-field",
+ "p3-fri",
  "p3-matrix",
  "p3-maybe-rayon",
  "p3-util",
@@ -1972,9 +1977,9 @@ dependencies = [
 
 [[package]]
 name = "p3-util"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "d08a58162a4c264269ef454f0b28dcda89939490eecacb2b2cf5b00f719b80f6"
+checksum = "607fbd67d3823d91125b7de08c2281f6fd42859821d76d7be1b537f477b38298"
 dependencies = [
  "rayon",
  "serde",
@@ -2529,9 +2534,9 @@ dependencies = [
 
 [[package]]
 name = "spin"
-version = "0.10.0"
+version = "0.12.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "d5fe4ccb98d9c292d56fec89a5e07da7fc4cf0dc11e156b41793132775d3e591"
+checksum = "1527984ca054dfca79333baec451042863f485fbee01b7bf6d911de915cac865"
 dependencies = [
  "lock_api",
 ]
diff --git a/Cargo.toml b/Cargo.toml
--- a/Cargo.toml
+++ b/Cargo.toml
@@ -34,29 +34,28 @@ miden-stark-transcript = { default-features = false, path = "stark/miden-stark-t
 miden-stateful-hasher  = { default-features = false, path = "stark/miden-stateful-hasher", version = "0.27" }
 
 # Plonky3
-p3-air           = { default-features = false, version = "0.5" }
-p3-batch-stark   = { default-features = false, version = "0.5" }
-p3-blake3        = { default-features = false, version = "0.5" }
-p3-blake3-air    = { default-features = false, version = "0.5" }
-p3-bn254         = { default-features = false, version = "0.5" }
-p3-challenger    = { default-features = false, version = "0.5" }
-p3-commit        = { default-features = false, version = "0.5" }
-p3-dft           = { default-features = false, version = "0.5" }
-p3-field         = { default-features = false, version = "0.5" }
-p3-fri           = { default-features = false, version = "0.5" }
-p3-goldilocks    = { default-features = false, version = "0.5" }
-p3-interpolation = { default-features = false, version = "0.5" }
-p3-keccak        = { default-features = false, version = "0.5" }
-p3-keccak-air    = { default-features = false, version = "0.5" }
-p3-lookup        = { default-features = false, version = "0.5" }
-p3-matrix        = { default-features = false, version = "0.5" }
-p3-maybe-rayon   = { default-features = false, version = "0.5" }
-p3-merkle-tree   = { default-features = false, version = "0.5" }
-p3-mersenne-31   = { default-features = false, version = "0.5" }
-p3-poseidon2-air = { default-features = false, version = "0.5" }
-p3-symmetric     = { default-features = false, version = "0.5" }
-p3-uni-stark     = { default-features = false, version = "0.5" }
-p3-util          = { default-features = false, version = "0.5" }
+p3-air           = { default-features = false, version = "0.6" }
+p3-batch-stark   = { default-features = false, version = "0.6" }
+p3-blake3        = { default-features = false, version = "0.6" }
+p3-blake3-air    = { default-features = false, version = "0.6" }
+p3-bn254         = { default-features = false, version = "0.6" }
+p3-challenger    = { default-features = false, version = "0.6" }
+p3-commit        = { default-features = false, version = "0.6" }
+p3-dft           = { default-features = false, version = "0.6" }
+p3-field         = { default-features = false, version = "0.6" }
+p3-fri           = { default-features = false, version = "0.6" }
+p3-goldilocks    = { default-features = false, version = "0.6" }
+p3-keccak        = { default-features = false, version = "0.6" }
+p3-keccak-air    = { default-features = false, version = "0.6" }
+p3-lookup        = { default-features = false, version = "0.6" }
+p3-matrix        = { default-features = false, version = "0.6" }
+p3-maybe-rayon   = { default-features = false, version = "0.6" }
+p3-merkle-tree   = { default-features = false, version = "0.6" }
+p3-mersenne-31   = { default-features = false, version = "0.6" }
+p3-poseidon2-air = { default-features = false, version = "0.6" }
+p3-symmetric     = { default-features = false, version = "0.6" }
+p3-uni-stark     = { default-features = false, version = "0.6" }
+p3-util          = { default-features = false, version = "0.6" }
 
 # Shared third-party dependencies used across workspace crates
 assert_matches   = { default-features = false, version = "1.5" }
diff --git a/miden-bench/src/batch.rs b/miden-bench/src/batch.rs
--- a/miden-bench/src/batch.rs
+++ b/miden-bench/src/batch.rs
@@ -1,23 +1,16 @@
 //! Batch STARK AIR wrappers, lookup implementations, and prove/verify runner.
 
-use miden_lifted_stark::{
-    air::{BaseAir, log2_strict_u8},
-    testing::airs::poseidon2::NUM_POSEIDON2_COLS,
-};
-use p3_air::{Air, AirBuilder, AirLayout, BaseLeaf, SymbolicExpression, WindowAccess};
+use miden_lifted_stark::{air::BaseAir, testing::airs::poseidon2::NUM_POSEIDON2_COLS};
+use p3_air::{Air, AirBuilder, WindowAccess};
 use p3_batch_stark::{ProverData, StarkInstance, prove_batch, verify_batch};
 use p3_blake3_air::{Blake3Air, NUM_BLAKE3_COLS};
 use p3_commit::ExtensionMmcs;
-use p3_field::{Field, PrimeCharacteristicRing};
+use p3_field::PrimeCharacteristicRing;
 use p3_fri::{FriParameters, TwoAdicFriPcs};
 use p3_keccak_air::{KeccakAir, NUM_KECCAK_COLS};
-use p3_lookup::{
-    LookupAir,
-    lookup_traits::{Direction, Kind, Lookup},
-};
-use p3_matrix::{Matrix, dense::RowMajorMatrix};
+use p3_lookup::InteractionBuilder;
+use p3_matrix::dense::RowMajorMatrix;
 use p3_merkle_tree::MerkleTreeMmcs;
-use p3_uni_stark::SymbolicAirBuilder;
 use tracing::info_span;
 
 use crate::{
@@ -33,38 +26,23 @@ use crate::{
 /// extension-field permutation column. Matches the lifted prover's unconditional
 /// 1-column EF aux trace.
 #[derive(Clone)]
-struct KeccakWithLookup {
-    num_lookups: usize,
-}
+struct KeccakWithLookup;
 
 impl<F> BaseAir<F> for KeccakWithLookup {
     fn width(&self) -> usize {
         NUM_KECCAK_COLS
     }
 }
 
-impl<AB: AirBuilder> Air<AB> for KeccakWithLookup {
+impl<AB: AirBuilder + InteractionBuilder> Air<AB> for KeccakWithLookup {
     fn eval(&self, builder: &mut AB) {
         Air::eval(&KeccakAir {}, builder);
-    }
-}
-
-impl<F: Field> LookupAir<F> for KeccakWithLookup {
-    fn add_lookup_columns(&mut self) -> Vec<usize> {
-        let idx = self.num_lookups;
-        self.num_lookups += 1;
-        vec![idx]
-    }
 
-    fn get_lookups(&mut self) -> Vec<Lookup<F>> {
-        self.num_lookups = 0;
-        let col0 = SymbolicExpression::Leaf(BaseLeaf::Constant(F::ONE));
-        let one = SymbolicExpression::Leaf(BaseLeaf::Constant(F::ONE));
-        let lookup_inputs = vec![
-            (vec![col0.clone()], one.clone(), Direction::Send),
-            (vec![col0], one, Direction::Receive),
-        ];
-        vec![LookupAir::register_lookup(self, Kind::Local, &lookup_inputs)]
+        // Single balanced local LogUp lookup, producing one EF permutation column.
+        builder.push_local_interaction(vec![
+            (vec![AB::Expr::ONE], AB::Expr::ONE),
+            (vec![AB::Expr::ONE], -AB::Expr::ONE),
+        ]);
     }
 }
 
@@ -78,7 +56,6 @@ impl<F: Field> LookupAir<F> for KeccakWithLookup {
 struct MidenWithLookups {
     width: usize,
     num_lookups_target: usize,
-    num_lookups: usize,
 }
 
 impl<F> BaseAir<F> for MidenWithLookups {
@@ -87,40 +64,23 @@ impl<F> BaseAir<F> for MidenWithLookups {
     }
 }
 
-impl<AB: AirBuilder> Air<AB> for MidenWithLookups {
+impl<AB: AirBuilder + InteractionBuilder> Air<AB> for MidenWithLookups {
     fn eval(&self, builder: &mut AB) {
         // Same degree-9 constraint as DummyMidenAir.
         let main = builder.main();
         let local = main.current_slice();
         let product = (0..9).fold(AB::Expr::ONE, |acc, j| acc * local[j].into());
         builder.assert_zero(product);
-    }
-}
-
-impl<F: Field> LookupAir<F> for MidenWithLookups {
-    fn add_lookup_columns(&mut self) -> Vec<usize> {
-        let idx = self.num_lookups;
-        self.num_lookups += 1;
-        vec![idx]
-    }
 
-    fn get_lookups(&mut self) -> Vec<Lookup<F>> {
-        self.num_lookups = 0;
-        let symbolic = SymbolicAirBuilder::<F>::new(AirLayout {
-            main_width: self.width,
-            ..AirLayout::default()
-        });
-        let main = symbolic.main();
-        let local = main.current_slice();
-        let col0: SymbolicExpression<F> = local[0].into();
-        let one = SymbolicExpression::Leaf(BaseLeaf::Constant(F::ONE));
-        let lookup_inputs = vec![
-            (vec![col0.clone()], one.clone(), Direction::Send),
-            (vec![col0], one, Direction::Receive),
-        ];
-        (0..self.num_lookups_target)
-            .map(|_| LookupAir::register_lookup(self, Kind::Local, &lookup_inputs))
-            .collect()
+        // `num_lookups_target` balanced local LogUp lookups on column 0, each
+        // producing one EF permutation column.
+        let col0: AB::Expr = local[0].into();
+        for _ in 0..self.num_lookups_target {
+            builder.push_local_interaction(vec![
+                (vec![col0.clone()], AB::Expr::ONE),
+                (vec![col0.clone()], -AB::Expr::ONE),
+            ]);
+        }
     }
 }
 
@@ -147,7 +107,7 @@ impl<F> BaseAir<F> for BatchBenchAir {
     }
 }
 
-impl<AB: AirBuilder<F = Felt>> Air<AB> for BatchBenchAir {
+impl<AB: AirBuilder<F = Felt> + InteractionBuilder> Air<AB> for BatchBenchAir {
     fn eval(&self, builder: &mut AB) {
         match self {
             Self::Keccak(a) => Air::eval(a, builder),
@@ -158,24 +118,6 @@ impl<AB: AirBuilder<F = Felt>> Air<AB> for BatchBenchAir {
     }
 }
 
-impl<F: Field> LookupAir<F> for BatchBenchAir {
-    fn add_lookup_columns(&mut self) -> Vec<usize> {
-        match self {
-            Self::Keccak(a) => <KeccakWithLookup as LookupAir<F>>::add_lookup_columns(a),
-            Self::Miden(a) => <MidenWithLookups as LookupAir<F>>::add_lookup_columns(a),
-            Self::Poseidon2(_) | Self::Blake3 => vec![],
-        }
-    }
-
-    fn get_lookups(&mut self) -> Vec<Lookup<F>> {
-        match self {
-            Self::Keccak(a) => <KeccakWithLookup as LookupAir<F>>::get_lookups(a),
-            Self::Miden(a) => <MidenWithLookups as LookupAir<F>>::get_lookups(a),
-            Self::Poseidon2(_) | Self::Blake3 => vec![],
-        }
-    }
-}
-
 // ═══════════════════════════════════════════════════════════════════════════════
 // Batch config macro
 // ═══════════════════════════════════════════════════════════════════════════════
@@ -226,13 +168,16 @@ pub(crate) fn run_batch<SC>(
 ) -> RunResult
 where
     SC: p3_uni_stark::StarkGenericConfig<Challenge = QuadFelt>,
+    SC::Pcs: Sync,
     <SC::Pcs as p3_commit::Pcs<QuadFelt, SC::Challenger>>::Domain:
-        p3_commit::PolynomialSpace<Val = Felt>,
+        p3_commit::PolynomialSpace<Val = Felt> + Send + Sync,
+    <SC::Pcs as p3_commit::Pcs<QuadFelt, SC::Challenger>>::ProverData: Sync,
+    <SC::Pcs as p3_commit::Pcs<QuadFelt, SC::Challenger>>::Commitment: Sync,
 {
-    let mut airs: Vec<BatchBenchAir> = specs
+    let airs: Vec<BatchBenchAir> = specs
         .iter()
         .map(|spec| match spec.air_type {
-            AirType::Keccak => BatchBenchAir::Keccak(KeccakWithLookup { num_lookups: 0 }),
+            AirType::Keccak => BatchBenchAir::Keccak(KeccakWithLookup),
             AirType::Poseidon2 => {
                 let c = constants.as_ref().expect("poseidon2 constants required");
                 BatchBenchAir::Poseidon2(Box::new(BatchPoseidon2Air::new(c.clone())))
@@ -241,20 +186,17 @@ where
             AirType::Miden => BatchBenchAir::Miden(MidenWithLookups {
                 width: spec.width,
                 num_lookups_target: spec.num_aux_cols,
-                num_lookups: 0,
             }),
         })
         .collect();
 
-    let degree_bits: Vec<usize> =
-        traces.iter().map(|t| log2_strict_u8(t.height()) as usize).collect();
-    let prover_data = ProverData::from_airs_and_degrees(config, &mut airs, &degree_bits);
-    let common = &prover_data.common;
-
     let trace_refs: Vec<&RowMajorMatrix<Felt>> = traces.iter().collect();
     let pvs: Vec<Vec<Felt>> = specs.iter().map(|_| vec![]).collect();
 
-    let instances = StarkInstance::new_multiple(&airs, &trace_refs, &pvs, common);
+    let instances = StarkInstance::new_multiple(&airs, &trace_refs, &pvs);
+
+    let prover_data = ProverData::from_instances(config, &instances);
+    let common = &prover_data.common;
 
     let proof = info_span!("prove").in_scope(|| prove_batch(config, &instances, &prover_data));
 
diff --git a/miden-crypto-fuzz/Cargo.lock b/miden-crypto-fuzz/Cargo.lock
--- a/miden-crypto-fuzz/Cargo.lock
+++ b/miden-crypto-fuzz/Cargo.lock
@@ -56,9 +56,9 @@ checksum = "2af50177e190e07a26ab74f8b1efbfe2ef87da2116221318cb1c2e82baf7de06"
 
 [[package]]
 name = "bitflags"
-version = "2.12.1"
+version = "2.13.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "84d7ced0ae9557296835c32bf1b1e02b44c746701f898460fb000d7eaa84f00a"
+checksum = "b4388bee8683e3d04af747c73422af53102d2bd24d9eadb6cbc100baef4b43f8"
 
 [[package]]
 name = "blake3"
@@ -323,9 +323,9 @@ dependencies = [
 
 [[package]]
 name = "ecdsa"
-version = "0.17.0-rc.18"
+version = "0.17.0-rc.19"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "54fb064faabbee66e1fc8e5c5a9458d4269dc2d8b638fe86a425adb2510d1a96"
+checksum = "0fcddae1289a08e614a83d155a070f54c1803196e92089b8299e2738eb74d3e4"
 dependencies = [
  "der",
  "digest",
@@ -369,9 +369,9 @@ checksum = "91622ff5e7162018101f2fea40d6ebf4a78bbe5a49736a2020649edf9693679e"
 
 [[package]]
 name = "elliptic-curve"
-version = "0.14.0-rc.33"
+version = "0.14.0-rc.34"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "102d3643d30dd8b559613c5cced68317199597fffb278cdc88daa2ef7fafc935"
+checksum = "88a44d097c9f3e494ddc19f77af5aab89f0b3b2652cde370ec8c6064faca5bd2"
 dependencies = [
  "base16ct",
  "crypto-bigint",
@@ -385,6 +385,7 @@ dependencies = [
  "rand_core 0.10.1",
  "sec1",
  "subtle",
+ "wnaf",
  "zeroize",
 ]
 
@@ -582,9 +583,9 @@ dependencies = [
 
 [[package]]
 name = "k256"
-version = "0.14.0-rc.10"
+version = "0.14.0-rc.11"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "1ea8e2b331bd02ab4a6342a78246a0a32096900951ea21aa4c768171ede67b5f"
+checksum = "9eb95d01f9d0270fc40dcb217cb25de1494383597d27b4fe832a42f5d907824a"
 dependencies = [
  "cpubits",
  "ecdsa",
@@ -616,9 +617,9 @@ checksum = "68ab91017fe16c622486840e4c83c9a37afeff978bd239b5293d61ece587de66"
 
 [[package]]
 name = "libfuzzer-sys"
-version = "0.4.12"
+version = "0.4.13"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "f12a681b7dd8ce12bff52488013ba614b869148d54dd79836ab85aafdd53f08d"
+checksum = "a9fd2f41a1cba099f79a0b6b6c35656cf7c03351a7bae8ff0f28f25270f929d2"
 dependencies = [
  "arbitrary",
  "cc",
@@ -641,9 +642,9 @@ dependencies = [
 
 [[package]]
 name = "log"
-version = "0.4.31"
+version = "0.4.32"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "113b30b4cd05f7c06868fdb2854f66a7b9fece9a48425351cd532e810d74024f"
+checksum = "953f07c43838f8e6f9758cab68bf5bed85465e7587ebe0b823f1bcd81978ad3a"
 
 [[package]]
 name = "memchr"
@@ -876,9 +877,9 @@ checksum = "c08d65885ee38876c4f86fa503fb49d7b507c2b62552df7c70b2fce627e06381"
 
 [[package]]
 name = "p3-air"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "c824e8d7c7ddf208b742eac8d48e0b2d52d22fa013578a7762bf6931dbab1f46"
+checksum = "c67c21e8bf70e8e7238f24e17ab26dbcf4df43054457d9cd31af456572244aed"
 dependencies = [
  "p3-field",
  "p3-matrix",
@@ -887,9 +888,9 @@ dependencies = [
 
 [[package]]
 name = "p3-blake3"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "2733229a713bd83ccf5eb749e8f8e7380c1052674394a25c0422a772204a20af"
+checksum = "9fbade8790087344c0fb06cd2c99361e32d76c813219301baf4c6192d856870c"
 dependencies = [
  "blake3",
  "p3-symmetric",
@@ -898,9 +899,9 @@ dependencies = [
 
 [[package]]
 name = "p3-challenger"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "8972ccd1d5dc90e46cdb1f2ab4ee2bae49b3917e5e98aa533f0c2b779c010445"
+checksum = "5974b8830874434511fe248a9ff6af5ff528be29b7d6bd490c92babdbeea6573"
 dependencies = [
  "p3-field",
  "p3-maybe-rayon",
@@ -912,24 +913,24 @@ dependencies = [
 
 [[package]]
 name = "p3-dft"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "17771aca44632f9cc11f2718d7ea7ec06794946c4190ef3a985bfc893f14c18a"
+checksum = "d44288108a5bff5097431b1ad303060bd62fc30f2ed7a7221ca780f9be79b6b3"
 dependencies = [
  "itertools",
  "p3-field",
  "p3-matrix",
  "p3-maybe-rayon",
  "p3-util",
- "spin 0.10.0",
+ "spin 0.12.0",
  "tracing",
 ]
 
 [[package]]
 name = "p3-field"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "6f3eb24d0591fd4d282d89cbe4e4efba5571c699375006f80b2cbf53ce83461c"
+checksum = "b97263e43047816338df728790380d18691a2d1118aab4628df704b3d16cbe63"
 dependencies = [
  "itertools",
  "num-bigint",
@@ -943,9 +944,9 @@ dependencies = [
 
 [[package]]
 name = "p3-goldilocks"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "5751c6591a0d2397d726620c2c29a7436ec6c5e19d2ed74ca5d078d4fbb18eb5"
+checksum = "6b3230de2e5daac8fb5d521e11019d8e4d155435efdfba1ed3cbcbee1b6af8fc"
 dependencies = [
  "num-bigint",
  "p3-challenger",
@@ -963,9 +964,9 @@ dependencies = [
 
 [[package]]
 name = "p3-keccak"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "77a7df174ff0c19a8742eb4698eaa1667c5f858d018e2faf09c55f1f24a6f9c3"
+checksum = "213062f2c3d0294f64489403fb8f781c72318bd043422ba5cd89922895c87d3e"
 dependencies = [
  "p3-symmetric",
  "p3-util",
@@ -974,9 +975,9 @@ dependencies = [
 
 [[package]]
 name = "p3-matrix"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "ea9c94c0714944e7b8a9a62e6340b1e3e1d3f8ecfd3e35c08798360200e73eff"
+checksum = "4ddef2a157f3b2d0c06d79aa43829098612181e77b4d3cf018b96e5339d12ea9"
 dependencies = [
  "itertools",
  "p3-field",
@@ -989,18 +990,18 @@ dependencies = [
 
 [[package]]
 name = "p3-maybe-rayon"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "eebc233a34b1ab0273f35b4052fa2eeb3114b22ba4575bd7da00716e878ffb77"
+checksum = "e613f4cac6197191c80b6445dc225e5a06c03c71b974a6223beb44f3ac7e5ffa"
 dependencies = [
  "rayon",
 ]
 
 [[package]]
 name = "p3-mds"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "6b5441fa8116246ec9e6c835f15273cb27777ca572960ec87476b67fef13e01e"
+checksum = "d202b0bbac217b427c88f1a4f37dc097c90f4b7acd2e4b5d7efe653346166c5b"
 dependencies = [
  "p3-dft",
  "p3-field",
@@ -1011,9 +1012,9 @@ dependencies = [
 
 [[package]]
 name = "p3-monty-31"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "8724f330ea6d19dd4f2436aa0f88b5fcbf88f0f55ca7fccd3fea8b736dbcddad"
+checksum = "9c96a02490c04c8211a4393a115507296b6a73967c19a586a86301740141420a"
 dependencies = [
  "itertools",
  "num-bigint",
@@ -1029,26 +1030,27 @@ dependencies = [
  "paste",
  "rand",
  "serde",
- "spin 0.10.0",
+ "spin 0.12.0",
  "tracing",
 ]
 
 [[package]]
 name = "p3-poseidon1"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "04e2a562fea210baae390a32f9ecf0dd8724ae3f4352d1c8e413077b6f00a162"
+checksum = "d8167c4110371fd84bd972c2dce068aae6b983ca6afb00569a23c7ddfd582c43"
 dependencies = [
  "p3-field",
+ "p3-mds",
  "p3-symmetric",
  "rand",
 ]
 
 [[package]]
 name = "p3-poseidon2"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "06394851c161d17e4aa4ad2aad5557d32f14cadd1dc838f965d8e1821a63b8c5"
+checksum = "cac1cceb7d79a5ebb6e23d2129d37dcc037bac01aa078d1e9ba67ae0d470c9bd"
 dependencies = [
  "p3-field",
  "p3-mds",
@@ -1059,9 +1061,9 @@ dependencies = [
 
 [[package]]
 name = "p3-symmetric"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "9ac1a276d421f8ef3361bb7d8c39a02c93c6b3f10eeaa559cc4c50222f9a5b82"
+checksum = "a7535a9e719089873bd1a85571fb8921c685209081eb1d295f2a2af6a42b3f68"
 dependencies = [
  "itertools",
  "p3-field",
@@ -1071,9 +1073,9 @@ dependencies = [
 
 [[package]]
 name = "p3-util"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "d08a58162a4c264269ef454f0b28dcda89939490eecacb2b2cf5b00f719b80f6"
+checksum = "607fbd67d3823d91125b7de08c2281f6fd42859821d76d7be1b537f477b38298"
 dependencies = [
  "rayon",
  "serde",
@@ -1223,12 +1225,12 @@ dependencies = [
 
 [[package]]
 name = "rfc6979"
-version = "0.5.0"
+version = "0.6.0-pre.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "5236ce872cac07e0fb3969b0cbf468c7d2f37d432f1b627dcb7b8d34563fb0c3"
+checksum = "9935425142ac6e252364413291d96c8bc9898d0876a801824c7af4eae397b689"
 dependencies = [
+ "ctutils",
  "hmac",
- "subtle",
 ]
 
 [[package]]
@@ -1358,9 +1360,9 @@ dependencies = [
 
 [[package]]
 name = "spin"
-version = "0.10.0"
+version = "0.12.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "d5fe4ccb98d9c292d56fec89a5e07da7fc4cf0dc11e156b41793132775d3e591"
+checksum = "1527984ca054dfca79333baec451042863f485fbee01b7bf6d911de915cac865"
 dependencies = [
  "lock_api",
 ]
@@ -1651,6 +1653,16 @@ dependencies = [
  "wasmparser",
 ]
 
+[[package]]
+name = "wnaf"
+version = "0.14.0-pre.0"
+source = "registry+https://github.com/rust-lang/crates.io-index"
+checksum = "81b8f9936fa4378fbe26130d702e51a9d723b22a073105500dfd80d9bb508199"
+dependencies = [
+ "ff",
+ "group",
+]
+
 [[package]]
 name = "x25519-dalek"
 version = "3.0.0-rc.0"
@@ -1663,18 +1675,18 @@ dependencies = [
 
 [[package]]
 name = "zerocopy"
-version = "0.8.50"
+version = "0.8.52"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "3b065d4f0e55f82fae73202e189638116a87c55ab6b8e6c2721e13dd9d854ad1"
+checksum = "ce1022995ff5ff5d841ad7d994facc23098cd40152f2c1d11cd607c6f530653f"
 dependencies = [
  "zerocopy-derive",
 ]
 
 [[package]]
 name = "zerocopy-derive"
-version = "0.8.50"
+version = "0.8.52"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "0b631b19d36a892ab55420c92dbc83ccd79274f25be714855d3074aa71cab639"
+checksum = "1ae7f38b72ec2a254e2b87ef277cf2cd4fb97cbebf944faa6f33354da0867930"
 dependencies = [
  "proc-macro2",
  "quote",
diff --git a/miden-crypto/src/lib.rs b/miden-crypto/src/lib.rs
--- a/miden-crypto/src/lib.rs
+++ b/miden-crypto/src/lib.rs
@@ -23,11 +23,11 @@ pub mod field {
     //! [Felt](super::Felt)).
 
     pub use miden_field::{
-        Algebra, BasedVectorSpace, BinomialExtensionField, BinomiallyExtendable,
-        BinomiallyExtendableAlgebra, BoundedPowers, ExtensionField, Field,
-        HasTwoAdicBinomialExtension, InjectiveMonomial, Packable, PermutationMonomial, Powers,
-        PrimeCharacteristicRing, PrimeField, PrimeField64, QuotientMap, RawDataSerializable,
-        TwoAdicField, batch_multiplicative_inverse,
+        Algebra, BasedVectorSpace, Binomial, BinomialExtensionField, BinomiallyExtendable,
+        BoundedPowers, ExtensionAlgebra, ExtensionField, Field, HasTwoAdicBinomialExtension,
+        InjectiveMonomial, Packable, PermutationMonomial, Powers, PrimeCharacteristicRing,
+        PrimeField, PrimeField64, QuotientMap, RawDataSerializable, TwoAdicField,
+        batch_multiplicative_inverse,
     };
 
     pub use super::batch_inversion::batch_inversion_allow_zeros;
diff --git a/miden-field/src/lib.rs b/miden-field/src/lib.rs
--- a/miden-field/src/lib.rs
+++ b/miden-field/src/lib.rs
@@ -31,7 +31,7 @@ pub use p3_field::{
     PermutationMonomial, Powers, PrimeCharacteristicRing, PrimeField, PrimeField64,
     RawDataSerializable, TwoAdicField, batch_multiplicative_inverse,
     extension::{
-        BinomialExtensionField, BinomiallyExtendable, BinomiallyExtendableAlgebra,
+        Binomial, BinomialExtensionField, BinomiallyExtendable, ExtensionAlgebra,
         HasTwoAdicBinomialExtension,
     },
     integers::QuotientMap,
diff --git a/miden-field/src/native/mod.rs b/miden-field/src/native/mod.rs
--- a/miden-field/src/native/mod.rs
+++ b/miden-field/src/native/mod.rs
@@ -17,7 +17,9 @@ use p3_challenger::UniformSamplingField;
 use p3_field::{
     Field, InjectiveMonomial, Packable, PermutationMonomial, PrimeCharacteristicRing, PrimeField,
     PrimeField64, RawDataSerializable, TwoAdicField,
-    extension::{BinomiallyExtendable, BinomiallyExtendableAlgebra, HasTwoAdicBinomialExtension},
+    extension::{
+        Binomial, BinomiallyExtendable, ExtensionAlgebra, HasTwoAdicBinomialExtension, binomial_mul,
+    },
     impl_raw_serializable_primefield64,
     integers::QuotientMap,
     quotient_map_large_iint, quotient_map_large_uint, quotient_map_small_int,
@@ -353,7 +355,12 @@ impl TwoAdicField for Felt {
 // EXTENSION FIELDS
 // ================================================================================================
 
-impl BinomiallyExtendableAlgebra<Self, 2> for Felt {}
+impl ExtensionAlgebra<Self, 2, Binomial<Self>> for Felt {
+    #[inline]
+    fn ext_mul(a: &[Self; 2], b: &[Self; 2], res: &mut [Self; 2]) {
+        binomial_mul::<Self, Self, Self, 2>(a, b, res, <Self as BinomiallyExtendable<2>>::W);
+    }
+}
 
 impl BinomiallyExtendable<2> for Felt {
     const W: Self = Self(<Goldilocks as BinomiallyExtendable<2>>::W);
@@ -376,7 +383,12 @@ impl HasTwoAdicBinomialExtension<2> for Felt {
     }
 }
 
-impl BinomiallyExtendableAlgebra<Self, 5> for Felt {}
+impl ExtensionAlgebra<Self, 5, Binomial<Self>> for Felt {
+    #[inline]
+    fn ext_mul(a: &[Self; 5], b: &[Self; 5], res: &mut [Self; 5]) {
+        binomial_mul::<Self, Self, Self, 5>(a, b, res, <Self as BinomiallyExtendable<5>>::W);
+    }
+}
 
 impl BinomiallyExtendable<5> for Felt {
     const W: Self = Self(<Goldilocks as BinomiallyExtendable<5>>::W);
diff --git a/miden-serde-utils/fuzz/Cargo.lock b/miden-serde-utils/fuzz/Cargo.lock
--- a/miden-serde-utils/fuzz/Cargo.lock
+++ b/miden-serde-utils/fuzz/Cargo.lock
@@ -10,9 +10,9 @@ checksum = "c3d036a3c4ab069c7b410a2ce876bd74808d2d0888a82667669f8e783a898bf1"
 
 [[package]]
 name = "autocfg"
-version = "1.5.0"
+version = "1.5.1"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "c08606f8c3cbf4ce6ec8e28fb0014a2c086708fe954eaa885384a6165172e7e8"
+checksum = "f2032f911046de80f0a198e0901378627c33f59ea0ac00e363d481118bd70a53"
 
 [[package]]
 name = "cc"
@@ -34,9 +34,9 @@ checksum = "9330f8b2ff13f34540b44e946ef35111825727b38d33286ef986142615121801"
 
 [[package]]
 name = "either"
-version = "1.15.0"
+version = "1.16.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "48c757948c5ede0e46177b7add2e67155f70e33c07fea8284df6576da70b3719"
+checksum = "91622ff5e7162018101f2fea40d6ebf4a78bbe5a49736a2020649edf9693679e"
 
 [[package]]
 name = "find-msvc-tools"
@@ -77,15 +77,15 @@ dependencies = [
 
 [[package]]
 name = "libc"
-version = "0.2.179"
+version = "0.2.186"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "c5a2d376baa530d1238d133232d15e239abad80d05838b4b59354e5268af431f"
+checksum = "68ab91017fe16c622486840e4c83c9a37afeff978bd239b5293d61ece587de66"
 
 [[package]]
 name = "libfuzzer-sys"
-version = "0.4.10"
+version = "0.4.13"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "5037190e1f70cbeef565bd267599242926f724d3b8a9f510fd7e0b540cfa4404"
+checksum = "a9fd2f41a1cba099f79a0b6b6c35656cf7c03351a7bae8ff0f28f25270f929d2"
 dependencies = [
  "arbitrary",
  "cc",
@@ -147,9 +147,9 @@ dependencies = [
 
 [[package]]
 name = "p3-challenger"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "8972ccd1d5dc90e46cdb1f2ab4ee2bae49b3917e5e98aa533f0c2b779c010445"
+checksum = "5974b8830874434511fe248a9ff6af5ff528be29b7d6bd490c92babdbeea6573"
 dependencies = [
  "p3-field",
  "p3-maybe-rayon",
@@ -161,9 +161,9 @@ dependencies = [
 
 [[package]]
 name = "p3-dft"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "17771aca44632f9cc11f2718d7ea7ec06794946c4190ef3a985bfc893f14c18a"
+checksum = "d44288108a5bff5097431b1ad303060bd62fc30f2ed7a7221ca780f9be79b6b3"
 dependencies = [
  "itertools",
  "p3-field",
@@ -176,9 +176,9 @@ dependencies = [
 
 [[package]]
 name = "p3-field"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "6f3eb24d0591fd4d282d89cbe4e4efba5571c699375006f80b2cbf53ce83461c"
+checksum = "b97263e43047816338df728790380d18691a2d1118aab4628df704b3d16cbe63"
 dependencies = [
  "itertools",
  "num-bigint",
@@ -192,9 +192,9 @@ dependencies = [
 
 [[package]]
 name = "p3-goldilocks"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "5751c6591a0d2397d726620c2c29a7436ec6c5e19d2ed74ca5d078d4fbb18eb5"
+checksum = "6b3230de2e5daac8fb5d521e11019d8e4d155435efdfba1ed3cbcbee1b6af8fc"
 dependencies = [
  "num-bigint",
  "p3-challenger",
@@ -212,9 +212,9 @@ dependencies = [
 
 [[package]]
 name = "p3-matrix"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "ea9c94c0714944e7b8a9a62e6340b1e3e1d3f8ecfd3e35c08798360200e73eff"
+checksum = "4ddef2a157f3b2d0c06d79aa43829098612181e77b4d3cf018b96e5339d12ea9"
 dependencies = [
  "itertools",
  "p3-field",
@@ -227,15 +227,15 @@ dependencies = [
 
 [[package]]
 name = "p3-maybe-rayon"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "eebc233a34b1ab0273f35b4052fa2eeb3114b22ba4575bd7da00716e878ffb77"
+checksum = "e613f4cac6197191c80b6445dc225e5a06c03c71b974a6223beb44f3ac7e5ffa"
 
 [[package]]
 name = "p3-mds"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "6b5441fa8116246ec9e6c835f15273cb27777ca572960ec87476b67fef13e01e"
+checksum = "d202b0bbac217b427c88f1a4f37dc097c90f4b7acd2e4b5d7efe653346166c5b"
 dependencies = [
  "p3-dft",
  "p3-field",
@@ -246,9 +246,9 @@ dependencies = [
 
 [[package]]
 name = "p3-monty-31"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "8724f330ea6d19dd4f2436aa0f88b5fcbf88f0f55ca7fccd3fea8b736dbcddad"
+checksum = "9c96a02490c04c8211a4393a115507296b6a73967c19a586a86301740141420a"
 dependencies = [
  "itertools",
  "num-bigint",
@@ -270,20 +270,21 @@ dependencies = [
 
 [[package]]
 name = "p3-poseidon1"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "04e2a562fea210baae390a32f9ecf0dd8724ae3f4352d1c8e413077b6f00a162"
+checksum = "d8167c4110371fd84bd972c2dce068aae6b983ca6afb00569a23c7ddfd582c43"
 dependencies = [
  "p3-field",
+ "p3-mds",
  "p3-symmetric",
  "rand",
 ]
 
 [[package]]
 name = "p3-poseidon2"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "06394851c161d17e4aa4ad2aad5557d32f14cadd1dc838f965d8e1821a63b8c5"
+checksum = "cac1cceb7d79a5ebb6e23d2129d37dcc037bac01aa078d1e9ba67ae0d470c9bd"
 dependencies = [
  "p3-field",
  "p3-mds",
@@ -294,9 +295,9 @@ dependencies = [
 
 [[package]]
 name = "p3-symmetric"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "9ac1a276d421f8ef3361bb7d8c39a02c93c6b3f10eeaa559cc4c50222f9a5b82"
+checksum = "a7535a9e719089873bd1a85571fb8921c685209081eb1d295f2a2af6a42b3f68"
 dependencies = [
  "itertools",
  "p3-field",
@@ -306,9 +307,9 @@ dependencies = [
 
 [[package]]
 name = "p3-util"
-version = "0.5.3"
+version = "0.6.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "d08a58162a4c264269ef454f0b28dcda89939490eecacb2b2cf5b00f719b80f6"
+checksum = "607fbd67d3823d91125b7de08c2281f6fd42859821d76d7be1b537f477b38298"
 dependencies = [
  "serde",
  "transpose",
@@ -322,15 +323,15 @@ checksum = "57c0d7b74b563b49d38dae00a0c37d4d6de9b432382b2892f0574ddcae73fd0a"
 
 [[package]]
 name = "pin-project-lite"
-version = "0.2.16"
+version = "0.2.17"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "3b3cff922bd51709b605d9ead9aa71031d81447142d828eb4a6eba76fe619f9b"
+checksum = "a89322df9ebe1c1578d689c92318e070967d1042b512afbe49518723f4e6d5cd"
 
 [[package]]
 name = "proc-macro2"
-version = "1.0.105"
+version = "1.0.106"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "535d180e0ecab6268a3e718bb9fd44db66bbbc256257165fc699dadf70d16fe7"
+checksum = "8fd00f0bb2e90d81d1044c2b32617f68fcb9fa3bb7640c23e9c748e53fb30934"
 dependencies = [
  "unicode-ident",
 ]
@@ -361,9 +362,9 @@ dependencies = [
 
 [[package]]
 name = "rand_core"
-version = "0.10.0"
+version = "0.10.1"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "0c8d0fd677905edcbeedbf2edb6494d676f0e98d54d5cf9bda0b061cb8fb8aba"
+checksum = "63b8176103e19a2643978565ca18b50549f6101881c443590420e4dc998a3c69"
 
 [[package]]
 name = "scopeguard"
@@ -409,9 +410,9 @@ checksum = "f8fadd59c855ef2080decdef8ff161eb6661b86933c9d82e5ba29dc602a55aba"
 
 [[package]]
 name = "spin"
-version = "0.10.0"
+version = "0.12.0"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "d5fe4ccb98d9c292d56fec89a5e07da7fc4cf0dc11e156b41793132775d3e591"
+checksum = "1527984ca054dfca79333baec451042863f485fbee01b7bf6d911de915cac865"
 dependencies = [
  "lock_api",
 ]
@@ -424,9 +425,9 @@ checksum = "fe895eb47f22e2ddd4dabc02bce419d2e643c8e3b585c78158b349195bc24d82"
 
 [[package]]
 name = "syn"
-version = "2.0.114"
+version = "2.0.117"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "d4d107df263a3013ef9b1879b0df87d706ff80f65a86ea879bd9c31f9b307c2a"
+checksum = "e665b8803e7b1d2a727f4023456bbbbe74da67099c585258af0ad9c5013b9b99"
 dependencies = [
  "proc-macro2",
  "quote",
@@ -473,21 +474,21 @@ dependencies = [
 
 [[package]]
 name = "unicode-ident"
-version = "1.0.22"
+version = "1.0.24"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "9312f7c4f6ff9069b165498234ce8be658059c6728633667c526e27dc2cf1df5"
+checksum = "e6e4313cd5fcd3dad5cafa179702e2b244f760991f45397d14d4ebf38247da75"
 
 [[package]]
 name = "wasip2"
-version = "1.0.1+wasi-0.2.4"
+version = "1.0.3+wasi-0.2.9"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "0562428422c63773dad2c345a1882263bbf4d65cf3f42e90921f787ef5ad58e7"
+checksum = "20064672db26d7cdc89c7798c48a0fdfac8213434a1186e5ef29fd560ae223d6"
 dependencies = [
  "wit-bindgen",
 ]
 
 [[package]]
 name = "wit-bindgen"
-version = "0.46.0"
+version = "0.57.1"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "f17a85883d4e6d00e8a97c586de764dabcc06133f7f1d55dce5cdc070ad7fe59"
+checksum = "1ebf944e87a7c253233ad6766e082e3cd714b5d03812acc24c318f549614536e"
diff --git a/miden-serde-utils/fuzz/Cargo.toml b/miden-serde-utils/fuzz/Cargo.toml
--- a/miden-serde-utils/fuzz/Cargo.toml
+++ b/miden-serde-utils/fuzz/Cargo.toml
@@ -11,7 +11,7 @@ cargo-fuzz = true
 
 [dependencies]
 libfuzzer-sys = "0.4"
-p3-goldilocks = { default-features = false, version = "0.5" }
+p3-goldilocks = { default-features = false, version = "0.6" }
 
 [dependencies.miden-serde-utils]
 path = ".."
diff --git a/stark/miden-lifted-air/src/air.rs b/stark/miden-lifted-air/src/air.rs
--- a/stark/miden-lifted-air/src/air.rs
+++ b/stark/miden-lifted-air/src/air.rs
@@ -11,7 +11,7 @@
 //! [`public_values()`](crate::AirBuilder::public_values),
 //! [`permutation_randomness()`](crate::PermutationAirBuilder::permutation_randomness),
 //! [`permutation_values()`](crate::PermutationAirBuilder::permutation_values), and
-//! [`periodic_values()`](crate::PeriodicAirBuilder::periodic_values) — which return
+//! [`periodic_values()`](crate::AirBuilder::periodic_values) — which return
 //! matrices or slices.
 //!
 //! If the symbolic evaluation in [`LiftedAir::constraint_degree`] succeeds (i.e.
@@ -45,55 +45,10 @@ use crate::{
 /// - `F`: Base field
 /// - `EF`: Extension field (for aux trace challenges and aux values)
 pub trait LiftedAir<F: Field, EF>: Sync + BaseAir<F> {
-    /// Number of base-field columns in the preprocessed trace.
-    ///
-    /// A preprocessed trace is data fixed per AIR — typically a lookup table
-    /// or selector polynomial — committed once and reused across proofs. AIRs
-    /// without preprocessed columns return 0 (the default). The content comes
-    /// from [`BaseAir::preprocessed_trace`]; this is the cheap width the
-    /// verifier reads without materialising the table.
-    fn preprocessed_width(&self) -> usize {
-        0
-    }
-
-    /// Return the periodic table data: a list of columns, each a `Vec<F>` of evaluations.
-    ///
-    /// Each inner `Vec<F>` represents one periodic column. Its length is the period of
-    /// that column, and the entries are the evaluations over a subgroup of that order.
-    ///
-    /// Default: no periodic columns.
-    fn periodic_columns(&self) -> Vec<Vec<F>> {
-        Vec::new()
-    }
-
-    /// Return a matrix with all periodic columns extended to a common height.
-    ///
-    /// Columns with smaller periods are repeated cyclically to fill the extended domain.
-    /// Returns `None` if there are no periodic columns.
-    fn periodic_columns_matrix(&self) -> Option<RowMajorMatrix<F>> {
-        let cols = self.periodic_columns();
-        if cols.is_empty() {
-            return None;
-        }
-
-        let max_period = cols.iter().map(Vec::len).max()?;
-        let num_cols = cols.len();
-
-        let mut values = Vec::with_capacity(max_period * num_cols);
-        for row in 0..max_period {
-            for col in &cols {
-                let period = col.len();
-                values.push(col[row % period]);
-            }
-        }
-
-        Some(RowMajorMatrix::new(values, num_cols))
-    }
-
     /// Maximum periodic-column length, or `0` if there are none. A trace's height
     /// must be at least this, so it is the per-AIR lower bound on trace height.
     ///
-    /// The default derives it from [`periodic_columns`](Self::periodic_columns),
+    /// The default derives it from [`periodic_columns`](BaseAir::periodic_columns),
     /// asserting each column is a non-empty power of two. Override to return it
     /// directly when known statically; the override is cross-checked by
     /// [`crate::debug::assert_multi_air_valid`].
diff --git a/stark/miden-lifted-air/src/builder.rs b/stark/miden-lifted-air/src/builder.rs
--- a/stark/miden-lifted-air/src/builder.rs
+++ b/stark/miden-lifted-air/src/builder.rs
@@ -1,18 +1,12 @@
 //! The `LiftedAirBuilder` super-trait for constraint evaluation builders.
 
-use crate::{AirBuilder, ExtensionBuilder, PeriodicAirBuilder, PermutationAirBuilder};
+use crate::{AirBuilder, ExtensionBuilder, PermutationAirBuilder};
 
 /// Super-trait bundling all builder capabilities needed by the lifted STARK system.
 ///
-/// Every type that already satisfies the four upstream builder traits automatically
+/// Every type that already satisfies the three upstream builder traits automatically
 /// implements this trait via the blanket impl below. No additional methods or
 /// associated types are required .
-pub trait LiftedAirBuilder:
-    AirBuilder + ExtensionBuilder + PermutationAirBuilder + PeriodicAirBuilder
-{
-}
+pub trait LiftedAirBuilder: AirBuilder + ExtensionBuilder + PermutationAirBuilder {}
 
-impl<T> LiftedAirBuilder for T where
-    T: AirBuilder + ExtensionBuilder + PermutationAirBuilder + PeriodicAirBuilder
-{
-}
+impl<T> LiftedAirBuilder for T where T: AirBuilder + ExtensionBuilder + PermutationAirBuilder {}
diff --git a/stark/miden-lifted-air/src/debug.rs b/stark/miden-lifted-air/src/debug.rs
--- a/stark/miden-lifted-air/src/debug.rs
+++ b/stark/miden-lifted-air/src/debug.rs
@@ -29,7 +29,7 @@ use crate::{BaseAir, LiftedAir, LiftedAirBuilder, MultiAir, WindowAccess};
 /// - All AIRs agree on [`BaseAir::num_public_values`].
 /// - [`MultiAir::num_air_inputs`] agrees with the per-AIR public value count.
 /// - Each AIR has positive auxiliary width.
-/// - Each AIR's [`LiftedAir::preprocessed_width`] agrees with [`BaseAir::preprocessed_trace`]
+/// - Each AIR's [`BaseAir::preprocessed_width`] agrees with [`BaseAir::preprocessed_trace`]
 ///   presence and width.
 /// - Each periodic column is non-empty and has power-of-two length.
 /// - [`LiftedAir::max_periodic_length`] agrees with the raw periodic columns.
diff --git a/stark/miden-lifted-air/src/lib.rs b/stark/miden-lifted-air/src/lib.rs
--- a/stark/miden-lifted-air/src/lib.rs
+++ b/stark/miden-lifted-air/src/lib.rs
@@ -25,7 +25,7 @@ pub use builder::LiftedAirBuilder;
 // directly.
 pub use p3_air::{
     Air, AirBuilder, AirBuilderWithContext, BaseAir, ExtensionBuilder, FilteredAirBuilder,
-    PeriodicAirBuilder, PermutationAirBuilder, RowWindow, WindowAccess,
+    PermutationAirBuilder, RowWindow, WindowAccess,
 };
 pub use statement::{InstanceError, ProverStatement, Statement};
 pub use util::{log2_ceil_u8, log2_strict_u8};
diff --git a/stark/miden-lifted-stark/Cargo.toml b/stark/miden-lifted-stark/Cargo.toml
--- a/stark/miden-lifted-stark/Cargo.toml
+++ b/stark/miden-lifted-stark/Cargo.toml
@@ -43,15 +43,14 @@ tracing.workspace   = true
 
 [dev-dependencies]
 # Plonky3
-p3-blake3.workspace        = true
-p3-challenger.workspace    = true
-p3-commit.workspace        = true
-p3-fri.workspace           = true
-p3-goldilocks.workspace    = true
-p3-interpolation.workspace = true
-p3-keccak.workspace        = true
-p3-merkle-tree.workspace   = true
-p3-symmetric.workspace     = true
+p3-blake3.workspace      = true
+p3-challenger.workspace  = true
+p3-commit.workspace      = true
+p3-fri.workspace         = true
+p3-goldilocks.workspace  = true
+p3-keccak.workspace      = true
+p3-merkle-tree.workspace = true
+p3-symmetric.workspace   = true
 
 # Third-party
 criterion.workspace          = true
diff --git a/stark/miden-lifted-stark/benches/per_air_degree_opt.rs b/stark/miden-lifted-stark/benches/per_air_degree_opt.rs
--- a/stark/miden-lifted-stark/benches/per_air_degree_opt.rs
+++ b/stark/miden-lifted-stark/benches/per_air_degree_opt.rs
@@ -166,12 +166,12 @@ impl<A: BaseAir<Felt>> BaseAir<Felt> for OverrideConstraintDegree<A> {
     fn num_public_values(&self) -> usize {
         self.inner.num_public_values()
     }
-}
-
-impl<A: LiftedAir<Felt, QuadFelt>> LiftedAir<Felt, QuadFelt> for OverrideConstraintDegree<A> {
     fn periodic_columns(&self) -> Vec<Vec<Felt>> {
         self.inner.periodic_columns()
     }
+}
+
+impl<A: LiftedAir<Felt, QuadFelt>> LiftedAir<Felt, QuadFelt> for OverrideConstraintDegree<A> {
     fn num_randomness(&self) -> usize {
         self.inner.num_randomness()
     }
diff --git a/stark/miden-lifted-stark/src/config.rs b/stark/miden-lifted-stark/src/config.rs
--- a/stark/miden-lifted-stark/src/config.rs
+++ b/stark/miden-lifted-stark/src/config.rs
@@ -14,6 +14,7 @@ use core::marker::PhantomData;
 use miden_stark_transcript::TranscriptChallenger;
 use p3_dft::TwoAdicSubgroupDft;
 use p3_field::{ExtensionField, TwoAdicField};
+use p3_matrix::{bitrev::BitReversibleMatrix, dense::RowMajorMatrix};
 
 use crate::{lmcs::Lmcs, pcs::params::PcsParams};
 
@@ -26,7 +27,10 @@ pub trait StarkConfig<F: TwoAdicField, EF: ExtensionField<F>>: Clone {
     /// LMCS (Merkle commitment scheme).
     type Lmcs: Lmcs<F = F>;
     /// DFT for LDE computation.
-    type Dft: TwoAdicSubgroupDft<F>;
+    ///
+    /// Its evaluations must bit-reverse to an owned [`RowMajorMatrix`] so committed LDEs are
+    /// stored in a single concrete layout (e.g. `Radix2DitParallel`).
+    type Dft: TwoAdicSubgroupDft<F, Evaluations: BitReversibleMatrix<F, BitRev = RowMajorMatrix<F>>>;
     /// Fiat-Shamir challenger.
     type Challenger: TranscriptChallenger<F, <Self::Lmcs as Lmcs>::Commitment>;
 
@@ -83,7 +87,8 @@ where
     F: TwoAdicField,
     EF: ExtensionField<F>,
     L: Lmcs<F = F>,
-    Dft: TwoAdicSubgroupDft<F> + Clone,
+    Dft: TwoAdicSubgroupDft<F, Evaluations: BitReversibleMatrix<F, BitRev = RowMajorMatrix<F>>>
+        + Clone,
     Ch: TranscriptChallenger<F, L::Commitment>,
 {
     type Lmcs = L;
diff --git a/stark/miden-lifted-stark/src/debug.rs b/stark/miden-lifted-stark/src/debug.rs
--- a/stark/miden-lifted-stark/src/debug.rs
+++ b/stark/miden-lifted-stark/src/debug.rs
@@ -14,8 +14,8 @@ extern crate alloc;
 use alloc::vec::Vec;
 
 use miden_lifted_air::{
-    AirBuilder, ExtensionBuilder, LiftedAir, MultiAir, PeriodicAirBuilder, PermutationAirBuilder,
-    ProverStatement, RowWindow, debug::assert_multi_air_valid,
+    AirBuilder, ExtensionBuilder, LiftedAir, MultiAir, PermutationAirBuilder, ProverStatement,
+    RowWindow, debug::assert_multi_air_valid,
 };
 use p3_challenger::{CanObserve, CanSample};
 use p3_field::{ExtensionField, Field};
@@ -248,6 +248,7 @@ where
     type PreprocessedWindow = RowWindow<'a, F>;
     type MainWindow = RowWindow<'a, F>;
     type PublicVar = F;
+    type PeriodicVar = F;
 
     fn main(&self) -> Self::MainWindow {
         self.main
@@ -265,8 +266,7 @@ where
         self.is_last_row
     }
 
-    fn is_transition_window(&self, size: usize) -> Self::Expr {
-        assert!(size <= 2, "only two-row windows are supported, got {size}");
+    fn is_transition(&self) -> Self::Expr {
         self.is_transition
     }
 
@@ -283,6 +283,10 @@ where
     fn public_values(&self) -> &[Self::PublicVar] {
         self.public_values
     }
+
+    fn periodic_values(&self) -> &[Self::PeriodicVar] {
+        self.periodic_values
+    }
 }
 
 impl<F, EF> ExtensionBuilder for DebugConstraintBuilder<'_, F, EF>
@@ -329,15 +333,3 @@ where
         self.permutation_values
     }
 }
-
-impl<F, EF> PeriodicAirBuilder for DebugConstraintBuilder<'_, F, EF>
-where
-    F: Field,
-    EF: ExtensionField<F>,
-{
-    type PeriodicVar = F;
-
-    fn periodic_values(&self) -> &[Self::PeriodicVar] {
-        self.periodic_values
-    }
-}
diff --git a/stark/miden-lifted-stark/src/lib.rs b/stark/miden-lifted-stark/src/lib.rs
--- a/stark/miden-lifted-stark/src/lib.rs
+++ b/stark/miden-lifted-stark/src/lib.rs
@@ -110,7 +110,6 @@ pub mod air {
         LiftedAir,
         LiftedAirBuilder,
         MultiAir,
-        PeriodicAirBuilder,
         PermutationAirBuilder,
         ProverStatement,
         ReductionError,
diff --git a/stark/miden-lifted-stark/src/lmcs/config.rs b/stark/miden-lifted-stark/src/lmcs/config.rs
--- a/stark/miden-lifted-stark/src/lmcs/config.rs
+++ b/stark/miden-lifted-stark/src/lmcs/config.rs
@@ -6,19 +6,16 @@ use core::marker::PhantomData;
 use miden_stark_transcript::VerifierChannel;
 use miden_stateful_hasher::{Alignable, StatefulHasher};
 use p3_field::PackedValue;
-use p3_matrix::Matrix;
+use p3_matrix::{Matrix, bitrev::BitReversibleMatrix};
 use p3_symmetric::{Hash, PseudoCompressionFunction};
 
-use crate::{
-    lmcs::{
-        Lmcs, LmcsError, OpenedRows,
-        lifted_tree::LiftedMerkleTree,
-        merkle_witness::MerkleWitness,
-        proof::{BatchProof, LeafOpening},
-        row_list::RowList,
-        tree_indices::TreeIndices,
-    },
-    util::bitrev::BitReversibleMatrix,
+use crate::lmcs::{
+    Lmcs, LmcsError, OpenedRows,
+    lifted_tree::LiftedMerkleTree,
+    merkle_witness::MerkleWitness,
+    proof::{BatchProof, LeafOpening},
+    row_list::RowList,
+    tree_indices::TreeIndices,
 };
 
 /// LMCS configuration holding cryptographic primitives (sponge + compression).
diff --git a/stark/miden-lifted-stark/src/lmcs/hiding_config.rs b/stark/miden-lifted-stark/src/lmcs/hiding_config.rs
--- a/stark/miden-lifted-stark/src/lmcs/hiding_config.rs
+++ b/stark/miden-lifted-stark/src/lmcs/hiding_config.rs
@@ -6,19 +6,16 @@ use core::cell::RefCell;
 use miden_stark_transcript::VerifierChannel;
 use miden_stateful_hasher::{Alignable, StatefulHasher};
 use p3_field::PackedValue;
-use p3_matrix::{Matrix, dense::RowMajorMatrix};
+use p3_matrix::{Matrix, bitrev::BitReversibleMatrix, dense::RowMajorMatrix};
 use p3_symmetric::{Hash, PseudoCompressionFunction};
 use rand::{
     Rng,
     distr::{Distribution, StandardUniform},
 };
 
-use crate::{
-    lmcs::{
-        Lmcs, LmcsError, OpenedRows, config::LmcsConfig, lifted_tree::LiftedMerkleTree,
-        proof::BatchProof, tree_indices::TreeIndices,
-    },
-    util::bitrev::BitReversibleMatrix,
+use crate::lmcs::{
+    Lmcs, LmcsError, OpenedRows, config::LmcsConfig, lifted_tree::LiftedMerkleTree,
+    proof::BatchProof, tree_indices::TreeIndices,
 };
 
 /// Configuration for hiding LMCS with random salt.
diff --git a/stark/miden-lifted-stark/src/lmcs/lifted_tree.rs b/stark/miden-lifted-stark/src/lmcs/lifted_tree.rs
--- a/stark/miden-lifted-stark/src/lmcs/lifted_tree.rs
+++ b/stark/miden-lifted-stark/src/lmcs/lifted_tree.rs
@@ -4,16 +4,13 @@ use core::{array, mem};
 use miden_stark_transcript::ProverChannel;
 use miden_stateful_hasher::StatefulHasher;
 use p3_field::PackedValue;
-use p3_matrix::{Matrix, dense::RowMajorMatrix};
+use p3_matrix::{Matrix, bitrev::BitReversibleMatrix, dense::RowMajorMatrix};
 use p3_maybe_rayon::prelude::*;
 use p3_symmetric::{Hash, PseudoCompressionFunction};
 use p3_util::{log2_strict_usize, reverse_bits_len};
 use tracing::info_span;
 
-use crate::{
-    lmcs::{LmcsTree, proof::LeafOpening, row_list::RowList, tree_indices::TreeIndices},
-    util::bitrev::BitReversibleMatrix,
-};
+use crate::lmcs::{LmcsTree, proof::LeafOpening, row_list::RowList, tree_indices::TreeIndices};
 
 /// A uniform binary Merkle tree whose leaves are constructed from matrices with power-of-two
 /// heights.
diff --git a/stark/miden-lifted-stark/src/lmcs/mod.rs b/stark/miden-lifted-stark/src/lmcs/mod.rs
--- a/stark/miden-lifted-stark/src/lmcs/mod.rs
+++ b/stark/miden-lifted-stark/src/lmcs/mod.rs
@@ -84,13 +84,13 @@ mod tests;
 use alloc::{collections::BTreeMap, vec::Vec};
 
 use miden_stark_transcript::{ProverChannel, TranscriptError, VerifierChannel};
-use p3_matrix::Matrix;
+use p3_matrix::{Matrix, bitrev::BitReversibleMatrix};
 use proof::BatchProofView;
 use row_list::RowList;
 use thiserror::Error;
 use tree_indices::TreeIndices;
 
-use crate::util::{align::aligned_len, bitrev::BitReversibleMatrix};
+use crate::util::align::aligned_len;
 
 // ============================================================================
 // Type Aliases
diff --git a/stark/miden-lifted-stark/src/lmcs/row_list.rs b/stark/miden-lifted-stark/src/lmcs/row_list.rs
--- a/stark/miden-lifted-stark/src/lmcs/row_list.rs
+++ b/stark/miden-lifted-stark/src/lmcs/row_list.rs
@@ -65,7 +65,7 @@ impl<T> RowList<T> {
 
     /// Iterate over all elements by value.
     #[inline]
-    pub fn iter_values(&self) -> impl Iterator<Item = T> + '_
+    pub fn iter_values(&self) -> impl DoubleEndedIterator<Item = T> + '_
     where
         T: Copy,
     {
@@ -79,13 +79,8 @@ impl<T> RowList<T> {
     }
 
     /// Iterate over rows as slices.
-    pub fn iter_rows(&self) -> impl Iterator<Item = &[T]> {
-        let mut offset = 0;
-        self.widths.iter().map(move |&w| {
-            let row = &self.elems[offset..offset + w];
-            offset += w;
-            row
-        })
+    pub fn iter_rows(&self) -> impl DoubleEndedIterator<Item = &[T]> {
+        RowIter { elems: &self.elems, widths: &self.widths }
     }
 
     /// Get a single row by index.
@@ -108,7 +103,7 @@ impl<T: Copy + Default> RowList<T> {
     ///
     /// Yields the original row elements followed by implicit zeros, without allocating
     /// a padded copy.
-    pub fn iter_aligned(&self, alignment: usize) -> impl Iterator<Item = T> + '_ {
+    pub fn iter_aligned(&self, alignment: usize) -> impl DoubleEndedIterator<Item = T> + '_ {
         self.iter_rows().flat_map(move |row| {
             let padding = aligned_len(row.len(), alignment) - row.len();
             row.iter().copied().chain(core::iter::repeat_n(T::default(), padding))
@@ -134,3 +129,35 @@ impl<T: Default + Clone> RowList<T> {
         Self { elems, widths }
     }
 }
+
+/// Double-ended iterator over the rows of a [`RowList`].
+struct RowIter<'a, T> {
+    elems: &'a [T],
+    widths: &'a [usize],
+}
+
+impl<'a, T> Iterator for RowIter<'a, T> {
+    type Item = &'a [T];
+
+    fn next(&mut self) -> Option<Self::Item> {
+        let (&width, rest) = self.widths.split_first()?;
+        let (row, elems) = self.elems.split_at(width);
+        self.widths = rest;
+        self.elems = elems;
+        Some(row)
+    }
+
+    fn size_hint(&self) -> (usize, Option<usize>) {
+        (self.widths.len(), Some(self.widths.len()))
+    }
+}
+
+impl<T> DoubleEndedIterator for RowIter<'_, T> {
+    fn next_back(&mut self) -> Option<Self::Item> {
+        let (&width, rest) = self.widths.split_last()?;
+        let (elems, row) = self.elems.split_at(self.elems.len() - width);
+        self.widths = rest;
+        self.elems = elems;
+        Some(row)
+    }
+}
diff --git a/stark/miden-lifted-stark/src/order.rs b/stark/miden-lifted-stark/src/order.rs
--- a/stark/miden-lifted-stark/src/order.rs
+++ b/stark/miden-lifted-stark/src/order.rs
@@ -235,7 +235,7 @@ impl TraceOrder {
     /// AIR instance index backing each committed preprocessed trace.
     ///
     /// The preprocessed commitment contains one committed LDE trace per AIR with
-    /// [`preprocessed_width`](miden_lifted_air::LiftedAir::preprocessed_width)
+    /// [`preprocessed_width`](miden_lifted_air::BaseAir::preprocessed_width)
     /// `> 0`, in proof order (the LMCS height-monotone committed-trace order). The result
     /// length is the number of preprocessed AIRs, which is `<= len()`.
     pub(crate) fn preprocessed_air_for_trace_index<F, EF, A>(&self, airs: &[A]) -> Vec<u8>
diff --git a/stark/miden-lifted-stark/src/pcs/deep/interpolate.rs b/stark/miden-lifted-stark/src/pcs/deep/interpolate.rs
--- a/stark/miden-lifted-stark/src/pcs/deep/interpolate.rs
+++ b/stark/miden-lifted-stark/src/pcs/deep/interpolate.rs
@@ -206,8 +206,11 @@ mod tests {
 
     use p3_dft::{NaiveDft, TwoAdicSubgroupDft};
     use p3_field::PrimeCharacteristicRing;
-    use p3_interpolation::{interpolate_coset, interpolate_coset_with_precomputation};
-    use p3_matrix::{bitrev::BitReversibleMatrix, dense::RowMajorMatrix};
+    use p3_matrix::{
+        bitrev::BitReversibleMatrix,
+        dense::RowMajorMatrix,
+        interpolation::{Interpolate, compute_adjusted_weights},
+    };
     use p3_util::reverse_slice_index_bits;
     use rand::{RngExt, SeedableRng, distr::StandardUniform, prelude::SmallRng};
 
@@ -286,7 +289,7 @@ mod tests {
                 result.as_slice()[1..].iter().map(|arr| arr[0]).collect();
 
             // Standard interpolation on the lifted coset
-            let expected_evals = interpolate_coset(&evals_std, lifted_shift, z_lifted);
+            let expected_evals = evals_std.interpolate_coset(lifted_shift, z_lifted);
 
             assert_eq!(
                 our_evals.len(),
@@ -312,10 +315,8 @@ mod tests {
         let domain = canonical_domain::<Felt>(log_n, 0);
         let shift = domain.lde_shift();
 
-        // Coset points in both orderings
+        // Coset points in bit-reversed order
         let coset_points_br = domain.lde_coset().bit_reversed_points();
-        let mut coset_points_std = coset_points_br.clone();
-        reverse_slice_index_bits(&mut coset_points_std); // Convert to standard order
 
         // Random out-of-domain evaluation point
         let z: QuadFelt = rng.sample(StandardUniform);
@@ -349,14 +350,10 @@ mod tests {
             quotient.point_quotient[..lde_height].iter().map(|arr| arr[0]).collect();
         reverse_slice_index_bits(&mut diff_invs_std);
 
-        // Interpolation with precomputation (both in standard order)
-        let expected_evals = interpolate_coset_with_precomputation(
-            &evals_std,
-            shift,
-            z,
-            &coset_points_std[..lde_height],
-            &diff_invs_std,
-        );
+        // Interpolation with precomputation (standard order)
+        let adjusted_weights = compute_adjusted_weights(z, &diff_invs_std);
+        let expected_evals =
+            evals_std.interpolate_coset_with_precomputation(shift, z, &adjusted_weights);
 
         assert_eq!(our_evals.len(), expected_evals.len(), "length mismatch");
         for (col, (&our, &expected)) in our_evals.iter().zip(expected_evals.iter()).enumerate() {
@@ -504,14 +501,14 @@ mod tests {
             [(0, "z1", z1), (1, "z2", z2)].into_iter().map(|(i, l, z)| (i, (l, z)))
         {
             // Matrix 1 (no lifting): evaluate at z directly
-            let expected1 = interpolate_coset(&evals1_std, lifted_shift_1, z);
+            let expected1 = evals1_std.interpolate_coset(lifted_shift_1, z);
             for (col, (&our, &exp)) in rows[0].iter().zip(expected1.iter()).enumerate() {
                 assert_eq!(our[point_idx], exp, "{label}, mat1, col={col}: mismatch");
             }
 
             // Matrix 2 (lift factor 2): evaluate at z^2
             let z_lifted = z.square();
-            let expected2 = interpolate_coset(&evals2_std, lifted_shift_2, z_lifted);
+            let expected2 = evals2_std.interpolate_coset(lifted_shift_2, z_lifted);
             for (col, (&our, &exp)) in rows[1].iter().zip(expected2.iter()).enumerate() {
                 assert_eq!(our[point_idx], exp, "{label}, mat2, col={col}: mismatch");
             }
diff --git a/stark/miden-lifted-stark/src/pcs/deep/prover.rs b/stark/miden-lifted-stark/src/pcs/deep/prover.rs
--- a/stark/miden-lifted-stark/src/pcs/deep/prover.rs
+++ b/stark/miden-lifted-stark/src/pcs/deep/prover.rs
@@ -3,7 +3,7 @@ use core::iter::zip;
 
 use miden_stark_transcript::ProverChannel;
 use p3_field::{
-    ExtensionField, Field, FieldArray, PackedFieldExtension, PackedValue, TwoAdicField,
+    ExtensionField, Field, FieldArray, HornerIter, PackedFieldExtension, PackedValue, TwoAdicField,
 };
 use p3_matrix::Matrix;
 use p3_maybe_rayon::prelude::*;
@@ -13,7 +13,7 @@ use crate::{
     domain::{Coset, LiftedDomain},
     lmcs::{Lmcs, LmcsTree, row_list::RowList},
     pcs::deep::{DeepParams, interpolate::PointQuotients},
-    util::{align::aligned_widths, horner::horner, packing::PackedFieldExtensionExt},
+    util::align::aligned_widths,
 };
 
 /// The DEEP quotient `Q(X)` evaluated over the LDE domain.
@@ -164,7 +164,7 @@ impl<EF> DeepPoly<EF> {
         // Pre-compute f_reduced(zⱼ) for all N points using Horner.
         // Reduces across all matrices' aligned columns in flat order.
         let f_reduced_at_points: FieldArray<EF, N> =
-            horner(challenge_columns, batched_evals.iter_aligned(alignment));
+            batched_evals.iter_aligned(alignment).rev().horner(challenge_columns);
 
         let w = <L::F as Field>::Packing::WIDTH;
         let point_quotient = &quotient.point_quotient;
@@ -459,7 +459,7 @@ mod tests {
             dot_product(neg_coeffs.iter().flatten().copied(), padded.iter_values());
 
         // Horner using reduce_with_powers (same as used in verifier)
-        let horner: QuadFelt = horner(c, padded.iter_values());
+        let horner: QuadFelt = padded.iter_values().rev().horner(c);
 
         assert_eq!(explicit, QuadFelt::NEG_ONE * horner);
     }
@@ -503,7 +503,7 @@ mod tests {
 
         let explicit: QuadFelt =
             dot_product(coeffs.iter().flatten().copied(), padded.iter_values());
-        let horner: QuadFelt = horner(c, padded.iter_values());
+        let horner: QuadFelt = padded.iter_values().rev().horner(c);
 
         assert_eq!(explicit, QuadFelt::NEG_ONE * horner);
     }
diff --git a/stark/miden-lifted-stark/src/pcs/deep/verifier.rs b/stark/miden-lifted-stark/src/pcs/deep/verifier.rs
--- a/stark/miden-lifted-stark/src/pcs/deep/verifier.rs
+++ b/stark/miden-lifted-stark/src/pcs/deep/verifier.rs
@@ -2,7 +2,7 @@ use alloc::{collections::BTreeMap, vec::Vec};
 use core::{iter::zip, marker::PhantomData};
 
 use miden_stark_transcript::{TranscriptError, VerifierChannel};
-use p3_field::{ExtensionField, TwoAdicField};
+use p3_field::{ExtensionField, HornerIter, TwoAdicField};
 use p3_matrix::Matrix;
 use thiserror::Error;
 
@@ -13,7 +13,6 @@ use crate::{
         deep::{DeepParams, proof::OpenedValues, read_eval_matrices},
         verifier::CommitmentGroup,
     },
-    util::horner::horner_acc,
 };
 
 /// Verifier's view of the DEEP quotient as a point-query oracle.
@@ -97,11 +96,8 @@ impl<F: TwoAdicField, EF: ExtensionField<F>, L: Lmcs<F = F>> DeepOracle<F, EF, L
             .map(|(p, &point)| {
                 let val = evals.iter().flat_map(|g| g.iter()).fold(EF::ZERO, |acc, mat| {
                     // mat has num_eval_points rows (one per z), p < num_eval_points.
-                    horner_acc(
-                        acc,
-                        challenge_columns,
-                        mat.row(p).expect("eval point index in range"),
-                    )
+                    let row = mat.row_slice(p).expect("eval point index in range");
+                    row.iter().copied().rev().horner_acc(acc, challenge_columns)
                 });
                 (point, val)
             })
@@ -166,7 +162,7 @@ impl<F: TwoAdicField, EF: ExtensionField<F>, L: Lmcs<F = F>> DeepOracle<F, EF, L
                 let rows_for_query = opened_rows
                     .get(tree_idx)
                     .ok_or(DeepError::InvalidOpening { tree: group_idx, tree_index: *tree_idx })?;
-                *acc = horner_acc(*acc, self.challenge_columns, rows_for_query.iter_values());
+                *acc = rows_for_query.iter_values().rev().horner_acc(*acc, self.challenge_columns);
             }
         }
 
diff --git a/stark/miden-lifted-stark/src/pcs/fri/fold/mod.rs b/stark/miden-lifted-stark/src/pcs/fri/fold/mod.rs
--- a/stark/miden-lifted-stark/src/pcs/fri/fold/mod.rs
+++ b/stark/miden-lifted-stark/src/pcs/fri/fold/mod.rs
@@ -21,12 +21,10 @@ mod arity8;
 
 use alloc::vec::Vec;
 
-use p3_field::{ExtensionField, PackedValue, TwoAdicField};
+use p3_field::{ExtensionField, PackedFieldExtension, PackedValue, TwoAdicField};
 use p3_matrix::{Matrix, dense::RowMajorMatrixView};
 use p3_maybe_rayon::prelude::*;
 
-use crate::util::packing::PackedFieldExtensionExt;
-
 /// FRI folding strategy.
 ///
 /// This struct encapsulates different folding arities (2, 4, 8).
@@ -167,13 +165,13 @@ impl FriFold {
             .zip(s_invs.par_chunks_exact(width))
             .for_each(|((new_evals_chunk, evals_chunk), s_inv_chunk)| {
                 let evals_packed =
-                    <EF::ExtensionPacking as PackedFieldExtensionExt<F, EF>>::pack_ext_columns::<
-                        ARITY,
-                    >(evals_chunk);
+                    <EF::ExtensionPacking as PackedFieldExtension<F, EF>>::pack_ext_columns::<ARITY>(
+                        evals_chunk,
+                    );
                 let s_invs_packed = F::Packing::from_slice(s_inv_chunk);
                 let new_evals_packed =
                     self.fold_evals_packed::<F, EF>(&evals_packed, *s_invs_packed, beta);
-                <EF::ExtensionPacking as PackedFieldExtensionExt<F, EF>>::to_ext_slice(
+                <EF::ExtensionPacking as PackedFieldExtension<F, EF>>::to_ext_slice(
                     &new_evals_packed,
                     new_evals_chunk,
                 );
@@ -191,7 +189,7 @@ pub mod tests {
     use alloc::vec::Vec;
 
     use p3_dft::{NaiveDft, Radix2DFTSmallBatch, TwoAdicSubgroupDft};
-    use p3_field::{ExtensionField, Field, PrimeCharacteristicRing, TwoAdicField};
+    use p3_field::{ExtensionField, Field, HornerIter, PrimeCharacteristicRing, TwoAdicField};
     use p3_matrix::dense::RowMajorMatrix;
     use p3_util::reverse_slice_index_bits;
     use rand::{
@@ -207,7 +205,6 @@ pub mod tests {
             configs::goldilocks_poseidon2::{Felt, QuadFelt},
             params::{FRI_FOLD_ARITY_2, FRI_FOLD_ARITY_4, FRI_FOLD_ARITY_8},
         },
-        util::horner::horner,
     };
 
     // Type alias for tests using packed fields
@@ -241,7 +238,7 @@ pub mod tests {
         let result = fold.fold_evals(&evals, s_inv, beta);
 
         // Expected: direct Horner evaluation at beta
-        let expected = horner(beta, coeffs.iter().rev().copied());
+        let expected = coeffs.iter().copied().horner(beta);
         assert_eq!(result, expected, "fold_evals mismatch for arity {arity}");
     }
 
@@ -271,10 +268,10 @@ pub mod tests {
 
         // Evaluate polynomial at coset points: [f(s·root) for root in roots]
         let evals: Vec<Ext> =
-            roots.iter().map(|&root| horner(root * s, poly.iter().rev().copied())).collect();
+            roots.iter().map(|&root| poly.iter().copied().horner(root * s)).collect();
 
         // Expected: f(beta)
-        let expected = horner(beta, poly.iter().rev().copied());
+        let expected = poly.iter().copied().horner(beta);
 
         // Test fold_evals
         let result = fold.fold_evals(&evals, s_inv, beta);
diff --git a/stark/miden-lifted-stark/src/pcs/fri/verifier.rs b/stark/miden-lifted-stark/src/pcs/fri/verifier.rs
--- a/stark/miden-lifted-stark/src/pcs/fri/verifier.rs
+++ b/stark/miden-lifted-stark/src/pcs/fri/verifier.rs
@@ -19,15 +19,14 @@
 use alloc::{collections::BTreeMap, vec::Vec};
 
 use miden_stark_transcript::{TranscriptError, VerifierChannel};
-use p3_field::{ExtensionField, TwoAdicField};
+use p3_field::{ExtensionField, HornerIter, TwoAdicField};
 use p3_util::reverse_bits_len;
 use thiserror::Error;
 
 use crate::{
     domain::{Coset, LiftedDomain, TwoAdicSubgroup},
     lmcs::{Lmcs, LmcsError, tree_indices::TreeIndices},
     pcs::fri::FriParams,
-    util::horner::horner,
 };
 
 /// FRI low-degree test oracle.
@@ -206,7 +205,7 @@ where
         for (idx, eval) in evals {
             // Domain index directly gives the exponent (no bit-reversal needed).
             let x = generator.exp_u64(idx as u64);
-            let final_eval: EF = horner(x, self.final_poly.iter().copied());
+            let final_eval: EF = self.final_poly.iter().copied().rev().horner(x);
 
             if final_eval != eval {
                 return Err(FriError::FinalPolyMismatch { tree_index: idx });
diff --git a/stark/miden-lifted-stark/src/preprocessed.rs b/stark/miden-lifted-stark/src/preprocessed.rs
--- a/stark/miden-lifted-stark/src/preprocessed.rs
+++ b/stark/miden-lifted-stark/src/preprocessed.rs
@@ -16,7 +16,7 @@
 
 use alloc::vec::Vec;
 
-use miden_lifted_air::{BaseAir, LiftedAir, MultiAir, ProverStatement, Statement, log2_strict_u8};
+use miden_lifted_air::{BaseAir, MultiAir, ProverStatement, Statement, log2_strict_u8};
 use p3_dft::TwoAdicSubgroupDft;
 use p3_field::{ExtensionField, TwoAdicField};
 use p3_matrix::{Matrix, dense::RowMajorMatrix};
@@ -29,7 +29,6 @@ use crate::{
     lmcs::{Lmcs, LmcsTree},
     order::TraceOrder,
     prover::commit::Committed,
-    util::bitrev::materialize_bitrev,
 };
 
 // ============================================================================
@@ -121,14 +120,7 @@ where
                     .expect("preprocessed LDE order exceeds field two-adicity");
                 let width = trace.width();
                 info_span!("preprocessed LDE", air = air_idx, log_height = log_h, width).in_scope(
-                    || {
-                        let lde = config.dft().coset_lde_batch(
-                            trace.clone(),
-                            log_blowup.into(),
-                            coset_shift,
-                        );
-                        materialize_bitrev(lde)
-                    },
+                    || config.dft().coset_lde_batch(trace.clone(), log_blowup.into(), coset_shift),
                 )
             })
             .collect();
diff --git a/stark/miden-lifted-stark/src/prover/commit.rs b/stark/miden-lifted-stark/src/prover/commit.rs
--- a/stark/miden-lifted-stark/src/prover/commit.rs
+++ b/stark/miden-lifted-stark/src/prover/commit.rs
@@ -20,7 +20,6 @@ use crate::{
     StarkConfig,
     domain::{Coset, EvaluationDomain, LiftedDomain},
     lmcs::{Lmcs, LmcsTree},
-    util::bitrev::materialize_bitrev,
 };
 
 // ============================================================================
@@ -170,10 +169,8 @@ where
             let log_trace_height = domain.log_trace_height();
             let coset_shift = domain.lde_shift();
 
-            info_span!("LDE", trace = idx, log_height = log_trace_height, width).in_scope(|| {
-                let lde = config.dft().coset_lde_batch(trace, log_blowup.into(), coset_shift);
-                materialize_bitrev(lde)
-            })
+            info_span!("LDE", trace = idx, log_height = log_trace_height, width)
+                .in_scope(|| config.dft().coset_lde_batch(trace, log_blowup.into(), coset_shift))
         })
         .collect();
 
diff --git a/stark/miden-lifted-stark/src/prover/constraints/folder.rs b/stark/miden-lifted-stark/src/prover/constraints/folder.rs
--- a/stark/miden-lifted-stark/src/prover/constraints/folder.rs
+++ b/stark/miden-lifted-stark/src/prover/constraints/folder.rs
@@ -7,67 +7,11 @@
 use alloc::vec::Vec;
 use core::marker::PhantomData;
 
-use miden_lifted_air::{
-    AirBuilder, ExtensionBuilder, PeriodicAirBuilder, PermutationAirBuilder, RowWindow,
-};
-use p3_field::{
-    Algebra, BasedVectorSpace, ExtensionField, Field, PackedField, PrimeCharacteristicRing,
-};
+use miden_lifted_air::{AirBuilder, ExtensionBuilder, PermutationAirBuilder, RowWindow};
+use p3_field::{Algebra, BasedVectorSpace, ExtensionField, Field, PackedField};
 
 use crate::selectors::Selectors;
 
-/// Batch size for constraint linear-combination chunks in [`finalize_constraints`].
-const CONSTRAINT_BATCH: usize = 8;
-
-/// Batched linear combination of packed extension field values with EF coefficients.
-///
-/// Extension-field analogue of [`PackedField::packed_linear_combination`]. Processes
-/// `coeffs` and `values` in chunks of [`CONSTRAINT_BATCH`], then handles the remainder.
-#[inline]
-fn batched_ext_linear_combination<PE, EF>(coeffs: &[EF], values: &[PE]) -> PE
-where
-    EF: Field,
-    PE: PrimeCharacteristicRing + Algebra<EF> + Copy,
-{
-    debug_assert_eq!(coeffs.len(), values.len());
-    let len = coeffs.len();
-    let mut acc = PE::ZERO;
-    let mut start = 0;
-    while start + CONSTRAINT_BATCH <= len {
-        let batch: [PE; CONSTRAINT_BATCH] =
-            core::array::from_fn(|i| values[start + i] * coeffs[start + i]);
-        acc += PE::sum_array::<CONSTRAINT_BATCH>(&batch);
-        start += CONSTRAINT_BATCH;
-    }
-    for (&coeff, &val) in coeffs[start..].iter().zip(&values[start..]) {
-        acc += val * coeff;
-    }
-    acc
-}
-
-/// Batched linear combination of packed base field values with F coefficients.
-///
-/// Wraps [`PackedField::packed_linear_combination`] with batched chunking
-/// and remainder handling, mirroring [`batched_ext_linear_combination`].
-#[inline]
-fn batched_base_linear_combination<P: PackedField>(coeffs: &[P::Scalar], values: &[P]) -> P {
-    debug_assert_eq!(coeffs.len(), values.len());
-    let len = coeffs.len();
-    let mut acc = P::ZERO;
-    let mut start = 0;
-    while start + CONSTRAINT_BATCH <= len {
-        acc += P::packed_linear_combination::<CONSTRAINT_BATCH>(
-            &coeffs[start..start + CONSTRAINT_BATCH],
-            &values[start..start + CONSTRAINT_BATCH],
-        );
-        start += CONSTRAINT_BATCH;
-    }
-    for (&coeff, &val) in coeffs[start..].iter().zip(&values[start..]) {
-        acc += val * coeff;
-    }
-    acc
-}
-
 /// Packed constraint folder for SIMD-optimized prover evaluation.
 ///
 /// Uses packed types to evaluate constraints on multiple domain points simultaneously:
@@ -76,7 +20,7 @@ fn batched_base_linear_combination<P: PackedField>(coeffs: &[P::Scalar], values:
 ///
 /// Collects constraints during `air.eval()` into separate base/ext vectors, then
 /// combines them in [`Self::finalize_constraints`] using decomposed alpha powers and
-/// `packed_linear_combination` for efficient SIMD accumulation.
+/// `Algebra::batched_linear_combination` for efficient SIMD accumulation.
 ///
 /// # Type Parameters
 /// - `F`: Base field scalar
@@ -132,10 +76,9 @@ where
 {
     /// Combine all collected constraints with their pre-computed alpha powers.
     ///
-    /// Base constraints use `batched_base_linear_combination` per basis dimension,
+    /// Base constraints use `Algebra::batched_linear_combination` per basis dimension,
     /// decomposing the extension-field multiply into D base-field SIMD dot products.
-    /// Extension constraints use `batched_ext_linear_combination` with scalar EF
-    /// coefficients. Both process in chunks of `CONSTRAINT_BATCH`.
+    /// Extension constraints use the same batched combination with scalar EF coefficients.
     ///
     /// We keep base and extension constraints separate because the base constraints can
     /// stay in the base field and use packed SIMD arithmetic. Decomposing EF powers of
@@ -154,11 +97,11 @@ where
         let base = &self.base_constraints;
         let base_powers = self.base_alpha_powers;
         let acc = PE::from_basis_coefficients_fn(|d| {
-            batched_base_linear_combination(&base_powers[d], base)
+            P::batched_linear_combination(base, &base_powers[d])
         });
 
         // Extension constraints: EF-coefficient dot product
-        acc + batched_ext_linear_combination(self.ext_alpha_powers, &self.ext_constraints)
+        acc + PE::batched_linear_combination(&self.ext_constraints, self.ext_alpha_powers)
     }
 }
 
@@ -175,6 +118,7 @@ where
     type PreprocessedWindow = RowWindow<'a, P>;
     type MainWindow = RowWindow<'a, P>;
     type PublicVar = F;
+    type PeriodicVar = P;
 
     #[inline]
     fn main(&self) -> Self::MainWindow {
@@ -197,12 +141,8 @@ where
     }
 
     #[inline]
-    fn is_transition_window(&self, size: usize) -> Self::Expr {
-        if size == 2 {
-            self.selectors.is_transition
-        } else {
-            panic!("only window size 2 supported")
-        }
+    fn is_transition(&self) -> Self::Expr {
+        self.selectors.is_transition
     }
 
     #[inline]
@@ -222,6 +162,11 @@ where
     fn public_values(&self) -> &[Self::PublicVar] {
         self.public_values
     }
+
+    #[inline]
+    fn periodic_values(&self) -> &[Self::PeriodicVar] {
+        self.periodic_values
+    }
 }
 
 impl<'a, F, EF, P, PE> ExtensionBuilder for ProverConstraintFolder<'a, F, EF, P, PE>
@@ -271,18 +216,3 @@ where
         self.permutation_values
     }
 }
-
-impl<'a, F, EF, P, PE> PeriodicAirBuilder for ProverConstraintFolder<'a, F, EF, P, PE>
-where
-    F: Field,
-    EF: ExtensionField<F>,
-    P: PackedField<Scalar = F>,
-    PE: Algebra<EF> + Algebra<P> + BasedVectorSpace<P> + Copy + Send + Sync,
-{
-    type PeriodicVar = P;
-
-    #[inline]
-    fn periodic_values(&self) -> &[Self::PeriodicVar] {
-        self.periodic_values
-    }
-}
diff --git a/stark/miden-lifted-stark/src/prover/constraints/layout.rs b/stark/miden-lifted-stark/src/prover/constraints/layout.rs
--- a/stark/miden-lifted-stark/src/prover/constraints/layout.rs
+++ b/stark/miden-lifted-stark/src/prover/constraints/layout.rs
@@ -6,8 +6,7 @@
 use alloc::{vec, vec::Vec};
 
 use miden_lifted_air::{
-    AirBuilder, ExtensionBuilder, LiftedAir, PeriodicAirBuilder, PermutationAirBuilder,
-    WindowAccess,
+    AirBuilder, ExtensionBuilder, LiftedAir, PermutationAirBuilder, WindowAccess,
     symbolic::{AirLayout, ConstraintLayout},
 };
 use p3_field::{ExtensionField, Field};
@@ -118,6 +117,7 @@ impl<F: Field> AirBuilder for ConstraintLayoutBuilder<F> {
     type PreprocessedWindow = OwnedRowWindow<F>;
     type MainWindow = RowMajorMatrix<F>;
     type PublicVar = F;
+    type PeriodicVar = F;
 
     fn main(&self) -> Self::MainWindow {
         self.main.clone()
@@ -135,7 +135,7 @@ impl<F: Field> AirBuilder for ConstraintLayoutBuilder<F> {
         F::ZERO
     }
 
-    fn is_transition_window(&self, _size: usize) -> Self::Expr {
+    fn is_transition(&self) -> Self::Expr {
         F::ZERO
     }
 
@@ -147,6 +147,10 @@ impl<F: Field> AirBuilder for ConstraintLayoutBuilder<F> {
     fn public_values(&self) -> &[Self::PublicVar] {
         &self.public_values
     }
+
+    fn periodic_values(&self) -> &[Self::PeriodicVar] {
+        &self.periodic_values
+    }
 }
 
 impl<F: Field> ExtensionBuilder for ConstraintLayoutBuilder<F> {
@@ -180,11 +184,3 @@ impl<F: Field> PermutationAirBuilder for ConstraintLayoutBuilder<F> {
         &self.permutation_values
     }
 }
-
-impl<F: Field> PeriodicAirBuilder for ConstraintLayoutBuilder<F> {
-    type PeriodicVar = F;
-
-    fn periodic_values(&self) -> &[Self::PeriodicVar] {
-        &self.periodic_values
-    }
-}
diff --git a/stark/miden-lifted-stark/src/prover/mod.rs b/stark/miden-lifted-stark/src/prover/mod.rs
--- a/stark/miden-lifted-stark/src/prover/mod.rs
+++ b/stark/miden-lifted-stark/src/prover/mod.rs
@@ -78,7 +78,7 @@ use alloc::vec::Vec;
 use commit::commit_traces;
 use constraints::{evaluate_constraints_into, layout::get_constraint_layout};
 use miden_lifted_air::{
-    InstanceError, LiftedAir, MultiAir, ProverStatement, ReductionError, Statement,
+    BaseAir, InstanceError, LiftedAir, MultiAir, ProverStatement, ReductionError, Statement,
 };
 use miden_stark_transcript::{Channel, ProverChannel, ProverTranscript};
 use p3_challenger::CanObserve;
diff --git a/stark/miden-lifted-stark/src/prover/periodic.rs b/stark/miden-lifted-stark/src/prover/periodic.rs
--- a/stark/miden-lifted-stark/src/prover/periodic.rs
+++ b/stark/miden-lifted-stark/src/prover/periodic.rs
@@ -35,7 +35,7 @@ pub(super) struct PeriodicLde<F: TwoAdicField> {
 impl<F: TwoAdicField> PeriodicLde<F> {
     /// Build periodic LDEs from a periodic column matrix.
     ///
-    /// Takes the output of [`crate::air::LiftedAir::periodic_columns_matrix`], where
+    /// Takes the output of [`miden_lifted_air::BaseAir::periodic_columns_matrix`], where
     /// columns with smaller periods have been repeated cyclically to the maximum period.
     /// Uses NaiveDft since periodic column periods are typically small.
     ///
diff --git a/stark/miden-lifted-stark/src/prover/quotient.rs b/stark/miden-lifted-stark/src/prover/quotient.rs
--- a/stark/miden-lifted-stark/src/prover/quotient.rs
+++ b/stark/miden-lifted-stark/src/prover/quotient.rs
@@ -8,21 +8,21 @@
 
 use alloc::{format, vec, vec::Vec};
 
-use p3_dft::TwoAdicSubgroupDft;
+use p3_dft::{Layout, TwoAdicSubgroupDft};
 use p3_field::{
     BasedVectorSpace, ExtensionField, Field, TwoAdicField, par_add_scaled_slice_in_place,
     par_scale_slice_in_place,
 };
 use p3_matrix::dense::RowMajorMatrix;
 use p3_maybe_rayon::prelude::*;
+use p3_util::{log2_strict_usize, reverse_bits_len};
 use tracing::info_span;
 
 use crate::{
     StarkConfig,
     domain::{Coset, EvaluationDomain},
     lmcs::Lmcs,
     prover::commit::Committed,
-    util::bitrev::materialize_bitrev,
 };
 
 // ============================================================================
@@ -158,89 +158,59 @@ where
     // D ≤ B (i.e. lde_height ≥ N · D) is enforced by `EvaluationDomain::new`.
 
     // ═══════════════════════════════════════════════════════════════════════
-    // Step 0: Reshape to N × D matrix
+    // Step 0: Reshape to N × D and flatten EF → F
     // ═══════════════════════════════════════════════════════════════════════
-    // q_evals[r·D + t] = Q(g·ω_Jᵗ·ω_Hʳ), so column t gives
-    // qₜ evaluated on the coset g·ω_Jᵗ·H.
-    let m = RowMajorMatrix::new(q_evals, d);
-
-    // ═══════════════════════════════════════════════════════════════════════
-    // Step 1: Batched iDFT over H
-    // ═══════════════════════════════════════════════════════════════════════
-    // iDFT treats each column as evaluations on H (not the actual coset
-    // g·ω_Jᵗ·H), producing shifted coefficients:
-    //   c_hat[t, k] = a[t, k]·(g·ω_Jᵗ)ᵏ
-    // where a[t, k] are the true coefficients of qₜ.
-    let mut coeffs = info_span!("quotient iDFT", dims = %format!("{n}x{d}"))
-        .in_scope(|| config.dft().idft_algebra_batch(m));
-
-    // ═══════════════════════════════════════════════════════════════════════
-    // Step 2: Fused coefficient scaling
-    // ═══════════════════════════════════════════════════════════════════════
-    // Multiply c_hat[t, k] by (ω_Jᵗ)⁻ᵏ → a[t, k]·gᵏ.
-    // This removes the per-coset shift ω_Jᵗ while keeping gᵏ baked in.
-    info_span!("quotient scaling", n).in_scope(|| {
-        let omega_j_inv = domain.subgroup().generator_inverse();
-
-        // Precompute ω_J⁻ᵏ for k = 0..N with sequential multiplications
-        let row_bases: Vec<F> = omega_j_inv.powers().take(n).collect();
-
-        // Row k, column t: multiply by (ω_J⁻ᵏ)ᵗ
-        coeffs.par_rows_mut().zip(row_bases.par_iter()).for_each(|(row, &row_base)| {
-            for (val, scale) in row.iter_mut().zip(row_base.powers()) {
-                *val *= scale;
-            }
-        });
-    });
-
-    // ═══════════════════════════════════════════════════════════════════════
-    // Step 3: Flatten EF → F, zero-pad to LDE height (N·B rows)
-    // ═══════════════════════════════════════════════════════════════════════
-    // We flatten before the DFT (rather than using dft_algebra_batch) because
-    // we need base field for commitment anyway — this skips the reconstitute.
-    //
-    // Zero-padding from N to lde_height rows is needed because `dft_batch`
-    // expects the full target-size buffer. The extra rows are zero because each
-    // qₜ has degree < N. We pad here (after iDFT + scaling) so those two steps
-    // work on the smaller N-row buffer.
-    //
-    // PERF: the full N·B-size DFT processes N·(B−1) zero rows through every
-    // butterfly stage, costing O(N·B·log(N·B)) instead of O(N·B·log N). For
-    // B = 4, N = 2^20 that is ≈ 9% overhead on this step (small relative to
-    // total proving time since the quotient matrix has only D·DIM columns).
-    //
-    // The existing `lde_batch`/`coset_lde_batch` APIs cannot help: they take
-    // *evaluations*, not coefficients. Using them would add a redundant DFT(N)
-    // → iDFT(N) round-trip.
-    //
-    // What is conceptually missing from `TwoAdicSubgroupDft` is an
-    // `added_bits` parameter on `dft_batch` / `coset_dft_batch` that evaluates
-    // degree-< N coefficients on a larger domain of size N·2^added_bits. The
-    // default would be zero-pad + the existing same-size DFT, but an optimized
-    // implementation (like `Radix2DftParallel`) could run B separate N-size
-    // DFTs — one per coset of H inside K — matching what its `coset_lde_batch`
-    // already does internally after the iDFT phase.
+    // q_evals[r·D + t] = Q(g·ω_Jᵗ·ω_Hʳ), so column t gives qₜ evaluated on the
+    // coset g·ω_Jᵗ·H. The commitment is base-valued and the iDFT/DFT are
+    // F-linear, so flattening to the base field commutes with both.
     let base_width = d * EF::DIMENSION;
-    let mut base_coeffs = <EF as BasedVectorSpace<F>>::flatten_to_base(coeffs.values);
-    base_coeffs.resize(lde_height * base_width, F::ZERO);
-    let coeffs_padded = RowMajorMatrix::new(base_coeffs, base_width);
+    let coeffs =
+        RowMajorMatrix::new(<EF as BasedVectorSpace<F>>::flatten_to_base(q_evals), base_width);
 
     // ═══════════════════════════════════════════════════════════════════════
-    // Step 4: Plain DFT (not coset DFT) on base field
+    // Steps 1–4: fused iDFT over H → coefficient scaling → coset LDE onto gK
     // ═══════════════════════════════════════════════════════════════════════
-    // Because gᵏ is baked into the coefficients, the plain DFT evaluates
-    // on gK directly: entry (i, t) gives qₜ(g·ω_Kⁱ).
-    let quotient_matrix = info_span!("quotient DFT", dims = %format!("{lde_height}x{base_width}"))
-        .in_scope(|| {
-            let lde = config.dft().dft_batch(coeffs_padded);
-
-            // ═══════════════════════════════════════════════════════════════
-            // Step 5: Wrap for commitment
-            // ═══════════════════════════════════════════════════════════════
-            materialize_bitrev(lde)
+    // `coset_lde_batch_with_transform` runs the iDFT, applies `transform` to the
+    // coefficient buffer, zero-pads by `added_bits`, then evaluates on the
+    // coset. The iDFT treats each column as evaluations on H, producing shifted
+    // coefficients c_hat[k, t] = a[k, t]·(g·ω_Jᵗ)ᵏ. `transform` multiplies by
+    // (ω_Jᵗ)⁻ᵏ, removing the per-coset shift ω_Jᵗ while keeping gᵏ baked in, so a
+    // shift-1 LDE then evaluates directly on the shifted coset gK.
+    let added_bits = log2_strict_usize(lde_height) - log2_strict_usize(n);
+    let omega_j_inv = domain.subgroup().generator_inverse();
+    let row_bases: Vec<F> = omega_j_inv.powers().take(n).collect();
+    let log_n = log2_strict_usize(n);
+
+    let lde =
+        info_span!("quotient LDE", dims = %format!("{lde_height}x{base_width}")).in_scope(|| {
+            config.dft().coset_lde_batch_with_transform(
+                coeffs,
+                added_bits,
+                F::ONE,
+                |buf, layout| {
+                    // Row r holds coefficient index k — bit-reversed when the buffer is in
+                    // bit-reversed layout. Multiply column t (each spanning `EF::DIMENSION`
+                    // flattened base columns) by (ω_J⁻ᵏ)ᵗ.
+                    let width = buf.width;
+                    buf.values.par_chunks_mut(width).enumerate().for_each(|(r, row)| {
+                        let k = match layout {
+                            Layout::Natural => r,
+                            Layout::BitReversed => reverse_bits_len(r, log_n),
+                        };
+                        let row_base = row_bases[k];
+                        let mut scale = F::ONE;
+                        for chunk in row.chunks_exact_mut(EF::DIMENSION) {
+                            for val in chunk {
+                                *val *= scale;
+                            }
+                            scale *= row_base;
+                        }
+                    });
+                },
+            )
         });
 
-    let tree = config.lmcs().build_aligned_tree(vec![quotient_matrix]);
+    let tree = config.lmcs().build_aligned_tree(vec![lde]);
 
     // The quotient is committed on the same LDE coset as the trace commits.
     Committed::new(tree)
diff --git a/stark/miden-lifted-stark/src/util/bitrev.rs b/stark/miden-lifted-stark/src/util/bitrev.rs
deleted file mode 100644
--- a/stark/miden-lifted-stark/src/util/bitrev.rs
+++ /dev/null
@@ -1,103 +0,0 @@
-//! Bit-reversal helpers and a stopgap [`BitReversibleMatrix`] trait.
-//!
-//! # Temporary stopgap
-//!
-//! The upstream `BitReversibleMatrix` trait in `p3-matrix` is only implemented for
-//! [`DenseMatrix`], not for [`FlatMatrixView`]. This module provides an identical
-//! trait with impls for all matrix types used by the LMCS and FRI.
-//!
-//! Once an upstream impl is available, this trait (and `materialize_bitrev`) can
-//! be removed and all uses replaced with `p3_matrix::bitrev::BitReversibleMatrix`.
-
-use p3_field::{ExtensionField, Field};
-use p3_matrix::{
-    Matrix,
-    bitrev::{BitReversalPerm, BitReversedMatrixView},
-    dense::{DenseMatrix, DenseStorage, RowMajorMatrix},
-    extension::FlatMatrixView,
-};
-
-/// A matrix that supports bit-reversed row reordering.
-///
-/// Local copy of `p3_matrix::bitrev::BitReversibleMatrix` extended with impls for
-/// [`FlatMatrixView`].
-pub trait BitReversibleMatrix<T: Send + Sync + Clone>: Matrix<T> {
-    /// The type returned when this matrix is viewed in bit-reversed order.
-    type BitRev: BitReversibleMatrix<T>;
-
-    /// Return a version of the matrix with its row order reversed by bit index.
-    fn bit_reverse_rows(self) -> Self::BitRev;
-}
-
-// ============================================================================
-// DenseMatrix impls (mirrors upstream)
-// ============================================================================
-
-impl<T, S> BitReversibleMatrix<T> for DenseMatrix<T, S>
-where
-    T: Clone + Send + Sync,
-    S: DenseStorage<T>,
-{
-    type BitRev = BitReversedMatrixView<Self>;
-
-    fn bit_reverse_rows(self) -> Self::BitRev {
-        BitReversalPerm::new_view(self)
-    }
-}
-
-impl<T, S> BitReversibleMatrix<T> for BitReversedMatrixView<DenseMatrix<T, S>>
-where
-    T: Clone + Send + Sync,
-    S: DenseStorage<T>,
-{
-    type BitRev = DenseMatrix<T, S>;
-
-    fn bit_reverse_rows(self) -> Self::BitRev {
-        self.inner
-    }
-}
-
-// ============================================================================
-// FlatMatrixView impls (not available upstream)
-// ============================================================================
-
-impl<F, EF, Inner> BitReversibleMatrix<F> for FlatMatrixView<F, EF, Inner>
-where
-    F: Field,
-    EF: ExtensionField<F>,
-    Inner: Matrix<EF>,
-{
-    type BitRev = BitReversedMatrixView<Self>;
-
-    fn bit_reverse_rows(self) -> Self::BitRev {
-        BitReversalPerm::new_view(self)
-    }
-}
-
-impl<F, EF, Inner> BitReversibleMatrix<F> for BitReversedMatrixView<FlatMatrixView<F, EF, Inner>>
-where
-    F: Field,
-    EF: ExtensionField<F>,
-    Inner: Matrix<EF>,
-{
-    type BitRev = FlatMatrixView<F, EF, Inner>;
-
-    fn bit_reverse_rows(self) -> Self::BitRev {
-        self.inner
-    }
-}
-
-/// Materialize a matrix into domain-ordered `BitReversedMatrixView<RowMajorMatrix<T>>`.
-///
-/// Temporary adapter for types that implement the upstream
-/// [`p3_matrix::bitrev::BitReversibleMatrix`] but not this crate's local copy.
-/// The returned type implements both traits and can be passed directly to
-/// [`Lmcs::build_tree`](crate::lmcs::Lmcs::build_tree) /
-/// [`Lmcs::build_aligned_tree`](crate::lmcs::Lmcs::build_aligned_tree).
-///
-/// Remove alongside [`BitReversibleMatrix`] when upstream impls cover all DFT output types.
-pub(crate) fn materialize_bitrev<T: Clone + Send + Sync>(
-    evals: impl p3_matrix::bitrev::BitReversibleMatrix<T>,
-) -> BitReversedMatrixView<RowMajorMatrix<T>> {
-    BitReversalPerm::new_view(evals.bit_reverse_rows().to_row_major_matrix())
-}
diff --git a/stark/miden-lifted-stark/src/util/horner.rs b/stark/miden-lifted-stark/src/util/horner.rs
deleted file mode 100644
--- a/stark/miden-lifted-stark/src/util/horner.rs
+++ /dev/null
@@ -1,34 +0,0 @@
-//! Horner-style polynomial evaluation helpers.
-
-use core::ops::{Add, Mul};
-
-/// Horner fold with an explicit accumulator.
-///
-/// Computes `acc·xⁿ + v₀·xⁿ⁻¹ + v₁·xⁿ⁻² + ... + vₙ₋₁·x⁰` where n = len(vals).
-/// Equivalently: `((acc·x + v₀)·x + v₁)·x + ... + vₙ₋₁`.
-/// The first element gets the highest power of `x`.
-///
-/// For polynomial evaluation `p(x) = Σᵢ cᵢ·xⁱ`, pass coefficients in
-/// descending degree order `[cₙ, ..., c₁, c₀]`.
-#[inline]
-pub(crate) fn horner_acc<Acc, Val, X, I>(acc: Acc, x: X, vals: I) -> Acc
-where
-    I: IntoIterator<Item = Val>,
-    Acc: Mul<X, Output = Acc> + Add<Val, Output = Acc>,
-    X: Clone,
-{
-    vals.into_iter().fold(acc, |acc, val| acc * x.clone() + val)
-}
-
-/// Horner fold starting from zero.
-///
-/// See [`horner_acc`] for the evaluation convention.
-#[inline]
-pub(crate) fn horner<Acc, Val, X, I>(x: X, vals: I) -> Acc
-where
-    I: IntoIterator<Item = Val>,
-    Acc: Default + Mul<X, Output = Acc> + Add<Val, Output = Acc>,
-    X: Clone,
-{
-    horner_acc(Acc::default(), x, vals)
-}
diff --git a/stark/miden-lifted-stark/src/util/mod.rs b/stark/miden-lifted-stark/src/util/mod.rs
--- a/stark/miden-lifted-stark/src/util/mod.rs
+++ b/stark/miden-lifted-stark/src/util/mod.rs
@@ -1,6 +1,4 @@
 //! Crate-wide utility helpers shared across LMCS, PCS, prover, and verifier.
 
 pub(crate) mod align;
-pub(crate) mod bitrev;
-pub(crate) mod horner;
 pub(crate) mod packing;
diff --git a/stark/miden-lifted-stark/src/util/packing.rs b/stark/miden-lifted-stark/src/util/packing.rs
--- a/stark/miden-lifted-stark/src/util/packing.rs
+++ b/stark/miden-lifted-stark/src/util/packing.rs
@@ -2,46 +2,8 @@
 //! and packed extension-field elements.
 
 use alloc::vec::Vec;
-use core::array;
 
-use p3_field::{ExtensionField, Field, PackedFieldExtension, PackedValue};
-
-/// Extension trait for [`PackedFieldExtension`] adding `pack_ext_columns` and
-/// `to_ext_slice` methods for column-wise SIMD operations on extension field elements.
-pub(crate) trait PackedFieldExtensionExt<
-    BaseField: Field,
-    ExtField: ExtensionField<BaseField, ExtensionPacking = Self>,
->: PackedFieldExtension<BaseField, ExtField>
-{
-    /// Pack N columns from WIDTH rows into N packed extension field elements.
-    ///
-    /// Input: `rows[lane][col]` - WIDTH rows, each with N extension field elements.
-    /// Output: `result[col]` - N packed values, where each packs WIDTH lanes.
-    fn pack_ext_columns<const N: usize>(rows: &[[ExtField; N]]) -> [Self; N] {
-        let width = BaseField::Packing::WIDTH;
-        debug_assert_eq!(rows.len(), width);
-        array::from_fn(|col| {
-            let col_elems: Vec<ExtField> = (0..width).map(|lane| rows[lane][col]).collect();
-            Self::from_ext_slice(&col_elems)
-        })
-    }
-
-    /// Extract all lanes to an output slice.
-    fn to_ext_slice(&self, out: &mut [ExtField]) {
-        let width = BaseField::Packing::WIDTH;
-        for (lane, slot) in out.iter_mut().enumerate().take(width) {
-            *slot = self.extract(lane);
-        }
-    }
-}
-
-impl<
-    BaseField: Field,
-    ExtField: ExtensionField<BaseField, ExtensionPacking = P>,
-    P: PackedFieldExtension<BaseField, ExtField>,
-> PackedFieldExtensionExt<BaseField, ExtField> for P
-{
-}
+use p3_field::{ExtensionField, Field};
 
 /// Reconstitute EF elements from opened base field polynomial evaluations.
 ///
@@ -60,13 +22,7 @@ where
     }
     Some(
         row.chunks_exact(EF::DIMENSION)
-            .map(|chunk| {
-                chunk
-                    .iter()
-                    .enumerate()
-                    .map(|(j, &c)| EF::ith_basis_element(j).unwrap() * c)
-                    .sum()
-            })
+            .map(|chunk| EF::from_ext_basis_coefficients(chunk).unwrap())
             .collect(),
     )
 }
diff --git a/stark/miden-lifted-stark/src/verifier/constraints.rs b/stark/miden-lifted-stark/src/verifier/constraints.rs
--- a/stark/miden-lifted-stark/src/verifier/constraints.rs
+++ b/stark/miden-lifted-stark/src/verifier/constraints.rs
@@ -5,9 +5,7 @@
 
 use core::marker::PhantomData;
 
-use miden_lifted_air::{
-    AirBuilder, ExtensionBuilder, PeriodicAirBuilder, PermutationAirBuilder, RowWindow,
-};
+use miden_lifted_air::{AirBuilder, ExtensionBuilder, PermutationAirBuilder, RowWindow};
 use p3_field::{ExtensionField, Field};
 
 use crate::selectors::Selectors;
@@ -59,6 +57,7 @@ where
     type PreprocessedWindow = RowWindow<'a, EF>;
     type MainWindow = RowWindow<'a, EF>;
     type PublicVar = F;
+    type PeriodicVar = EF;
 
     fn main(&self) -> Self::MainWindow {
         self.main
@@ -76,8 +75,7 @@ where
         self.selectors.is_last_row
     }
 
-    fn is_transition_window(&self, size: usize) -> Self::Expr {
-        assert_eq!(size, 2, "AIR uses window size {size}; only 2 supported");
+    fn is_transition(&self) -> Self::Expr {
         self.selectors.is_transition
     }
 
@@ -88,6 +86,10 @@ where
     fn public_values(&self) -> &[Self::PublicVar] {
         self.public_values
     }
+
+    fn periodic_values(&self) -> &[Self::PeriodicVar] {
+        self.periodic_values
+    }
 }
 
 impl<'a, F, EF> ExtensionBuilder for ConstraintFolder<'a, F, EF>
@@ -128,15 +130,3 @@ where
         self.permutation_values
     }
 }
-
-impl<'a, F, EF> PeriodicAirBuilder for ConstraintFolder<'a, F, EF>
-where
-    F: Field,
-    EF: ExtensionField<F>,
-{
-    type PeriodicVar = EF;
-
-    fn periodic_values(&self) -> &[Self::PeriodicVar] {
-        self.periodic_values
-    }
-}
diff --git a/stark/miden-lifted-stark/src/verifier/periodic.rs b/stark/miden-lifted-stark/src/verifier/periodic.rs
--- a/stark/miden-lifted-stark/src/verifier/periodic.rs
+++ b/stark/miden-lifted-stark/src/verifier/periodic.rs
@@ -8,9 +8,7 @@ extern crate alloc;
 use alloc::vec::Vec;
 
 use p3_dft::{Radix2DFTSmallBatch, TwoAdicSubgroupDft};
-use p3_field::{ExtensionField, TwoAdicField};
-
-use crate::util::horner::horner_acc;
+use p3_field::{ExtensionField, HornerIter, TwoAdicField};
 
 /// Verifier-side periodic polynomials for OOD evaluation.
 ///
@@ -74,9 +72,9 @@ impl<F: TwoAdicField> PeriodicPolys<F> {
         for coeffs in &self.polys {
             let period = coeffs.len();
             let y = z.exp_u64((trace_height / period) as u64);
-            // Coefficients are stored in ascending degree (idft output): [c₀, c₁, ..., cₙ₋₁].
-            // Horner needs descending order (highest degree first), hence `.rev()`.
-            result.push(horner_acc(EF::ZERO, y, coeffs.iter().rev().copied()));
+            // Coefficients are stored in ascending degree (idft output): [c₀, c₁, ..., cₙ₋₁],
+            // which is the order `HornerIter` consumes directly.
+            result.push(coeffs.iter().copied().horner(y));
         }
 
         result
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
