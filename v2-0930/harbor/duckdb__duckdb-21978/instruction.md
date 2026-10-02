Refactor the `FlatVector` data access API so read-only access and mutable access are explicit.

`FlatVector::GetData<T>(Vector &)` should no longer expose a mutable `T *`. It should return a `const T *` suitable for reading vector contents. Code that intends to write into a vector must use a new API, `FlatVector::GetDataMutable<T>(Vector &)`, which returns a mutable `T *`.

This affects all C++ code that writes through a pointer obtained from `FlatVector::GetData`, including core DuckDB code, tests, and extension patches. Typical affected patterns include assigning into result vectors in scalar functions and UDFs, filling `DataChunk` columns, writing list entries, row IDs, validity-related data, enum tags, string values, aggregate state pointers, and storage/update/WAL vectors. After the change, such code should compile only when it calls `FlatVector::GetDataMutable<T>` or another explicitly mutable writer API.

Read-only callers should continue to use `FlatVector::GetData<T>` and should receive a const pointer. Existing read-only usages such as inspecting input vectors in UDFs should remain valid. Mutable usages such as:

`auto result_data = FlatVector::GetData<bool>(result); result_data[i] = ...;`

must instead use:

`auto result_data = FlatVector::GetDataMutable<bool>(result); result_data[i] = ...;`

The public API should make it clear at compile time whether a caller is reading or modifying flat vector storage, while preserving existing behavior for code that explicitly requests mutable access.
