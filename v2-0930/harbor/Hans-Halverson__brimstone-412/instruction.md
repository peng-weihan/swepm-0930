Heap item kind names and debug output should consistently match the concrete heap item type names used by the runtime.

Currently some `HeapItemKind` variants use shortened or mismatched names, such as `String`, `Symbol`, `BigInt`, `WeakVec`, or mapping ordinary objects through `ObjectValue`. This inconsistency is visible in runtime/debug output and bytecode snapshot output. For example, bytecode constant tables currently print BigInt constants as `[BigInt: 1]`, but the heap item type is `BigIntValue`.

Update the runtime heap item naming so every `HeapItemKind` name matches its corresponding heap item type name. In particular, heap items for JavaScript primitive wrapper values should use names like `StringValue`, `SymbolValue`, and `BigIntValue`, weak value vectors should be named consistently with their heap item type, and `OrdinaryObject` should be represented as `OrdinaryObject` rather than `ObjectValue`.

All code that branches on heap item kinds, allocates descriptors, registers heap item descriptors, prints heap items, or serializes/debug-formats bytecode constants must use the updated names consistently. Observable output should reflect the new names; for example, bytecode snapshot constant tables should print BigInt constants as `[BigIntValue: 1]` instead of `[BigInt: 1]`.

The heap item registration API should only require the single canonical heap item kind/type name rather than maintaining separate mismatched names. The runtime should continue to build and pass CI with the renamed heap item kinds, and existing behavior should remain unchanged apart from the corrected, consistent heap item names in debug/snapshot output.
