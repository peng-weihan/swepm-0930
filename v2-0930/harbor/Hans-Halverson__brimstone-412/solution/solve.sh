#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/src/js/runtime/abstract_operations.rs b/src/js/runtime/abstract_operations.rs
--- a/src/js/runtime/abstract_operations.rs
+++ b/src/js/runtime/abstract_operations.rs
@@ -4,7 +4,7 @@ use crate::{
     common::numeric::MAX_SAFE_INTEGER_U64,
     must, must_a,
     runtime::{
-        Context, Value,
+        Context, SymbolValue, Value,
         accessor::Accessor,
         alloc_error::AllocResult,
         array_object::create_array_from_list,
@@ -25,7 +25,6 @@ use crate::{
             is_callable, is_constructor_value, require_object_coercible, same_object_value_handles,
             same_value_zero, to_length, to_object, to_property_key,
         },
-        value::SymbolValue,
     },
 };
 
diff --git a/src/js/runtime/arguments_object.rs b/src/js/runtime/arguments_object.rs
--- a/src/js/runtime/arguments_object.rs
+++ b/src/js/runtime/arguments_object.rs
@@ -331,7 +331,10 @@ impl HeapItem for UnmappedArgumentsObject {
         size_of::<UnmappedArgumentsObject>()
     }
 
-    fn visit_pointers(unmapped_arguments_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(
+        mut unmapped_arguments_object: HeapPtr<Self>,
+        visitor: &mut impl HeapVisitor,
+    ) {
         unmapped_arguments_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/array_object.rs b/src/js/runtime/array_object.rs
--- a/src/js/runtime/array_object.rs
+++ b/src/js/runtime/array_object.rs
@@ -265,7 +265,7 @@ impl HeapItem for ArrayObject {
         size_of::<ArrayObject>()
     }
 
-    fn visit_pointers(array_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut array_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         array_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/bigint_value.rs b/src/js/runtime/bigint_value.rs
new file mode 100644
--- /dev/null
+++ b/src/js/runtime/bigint_value.rs
@@ -0,0 +1,78 @@
+use num_bigint::{BigInt, Sign};
+
+use crate::{
+    field_offset,
+    runtime::{
+        Context, Handle, HeapItemKind, HeapPtr,
+        alloc_error::AllocResult,
+        debug_print::{DebugPrint, DebugPrinter},
+        gc::{HeapItem, HeapVisitor},
+        heap_item_descriptor::HeapItemDescriptor,
+    },
+    set_uninit,
+};
+
+#[repr(C)]
+pub struct BigIntValue {
+    descriptor: HeapPtr<HeapItemDescriptor>,
+    // Number of u32 digits in the BigInt
+    len: usize,
+    // Sign of the BigInt
+    sign: Sign,
+    // Start of the BigInt's array of digits. Variable sized but array has a single item for
+    // alignment.
+    digits: [u32; 1],
+}
+
+impl BigIntValue {
+    const DIGITS_OFFSET: usize = field_offset!(BigIntValue, digits);
+
+    pub fn new(cx: Context, value: BigInt) -> AllocResult<Handle<BigIntValue>> {
+        Ok(Self::new_ptr(cx, value)?.to_handle())
+    }
+
+    pub fn new_ptr(cx: Context, value: BigInt) -> AllocResult<HeapPtr<BigIntValue>> {
+        // Extract sign and digits from BigInt
+        let (sign, digits) = value.to_u32_digits();
+        let len = digits.len();
+
+        let size = Self::calculate_size_in_bytes(len);
+        let mut bigint = cx.alloc_uninit_with_size::<BigIntValue>(size)?;
+
+        // Copy raw parts of BigInt into BigIntValue
+        set_uninit!(bigint.descriptor, cx.descriptors.get(HeapItemKind::BigIntValue));
+        set_uninit!(bigint.len, digits.len());
+        set_uninit!(bigint.sign, sign);
+
+        unsafe { std::ptr::copy_nonoverlapping(digits.as_ptr(), bigint.digits.as_mut_ptr(), len) };
+
+        Ok(bigint)
+    }
+
+    pub fn calculate_size_in_bytes(num_u32_digits: usize) -> usize {
+        // Calculate size of BigIntValue with inlined digits
+        Self::DIGITS_OFFSET + num_u32_digits * size_of::<u32>()
+    }
+
+    pub fn bigint(&self) -> BigInt {
+        // Recreate BigInt from stored raw parts
+        let slice = unsafe { std::slice::from_raw_parts(self.digits.as_ptr(), self.len) };
+        BigInt::from_slice(self.sign, slice)
+    }
+}
+
+impl DebugPrint for HeapPtr<BigIntValue> {
+    fn debug_format(&self, printer: &mut DebugPrinter) {
+        printer.write_heap_item_with_context(self.cast(), &self.bigint().to_string())
+    }
+}
+
+impl HeapItem for BigIntValue {
+    fn byte_size(big_int_value: HeapPtr<Self>) -> usize {
+        BigIntValue::calculate_size_in_bytes(big_int_value.len)
+    }
+
+    fn visit_pointers(mut big_int_value: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+        visitor.visit_pointer(&mut big_int_value.descriptor);
+    }
+}
diff --git a/src/js/runtime/builtin_names.rs b/src/js/runtime/builtin_names.rs
--- a/src/js/runtime/builtin_names.rs
+++ b/src/js/runtime/builtin_names.rs
@@ -1,8 +1,8 @@
 use crate::{
     handle_scope_guard,
     runtime::{
-        Handle, alloc_error::AllocResult, context::Context, gc::HeapVisitor,
-        property_key::PropertyKey, value::SymbolValue,
+        Handle, SymbolValue, alloc_error::AllocResult, context::Context, gc::HeapVisitor,
+        property_key::PropertyKey,
     },
 };
 
diff --git a/src/js/runtime/bytecode/generator.rs b/src/js/runtime/bytecode/generator.rs
--- a/src/js/runtime/bytecode/generator.rs
+++ b/src/js/runtime/bytecode/generator.rs
@@ -29,7 +29,7 @@ use crate::{
         source::Source,
     },
     runtime::{
-        Context, Handle, HeapPtr, Realm, Value,
+        BigIntValue, Context, Handle, HeapPtr, Realm, Value,
         alloc_error::{AllocError, AllocResult},
         boxed_value::BoxedValue,
         bytecode::{
@@ -65,7 +65,6 @@ use crate::{
         scope_names::{ScopeFlags, ScopeNameFlags, ScopeNames},
         source_file::SourceFile,
         string_value::{FlatString, StringValue},
-        value::BigIntValue,
     },
 };
 
diff --git a/src/js/runtime/bytecode/vm.rs b/src/js/runtime/bytecode/vm.rs
--- a/src/js/runtime/bytecode/vm.rs
+++ b/src/js/runtime/bytecode/vm.rs
@@ -9,8 +9,8 @@ use crate::{
     common::numeric::Numeric,
     eval_err, handle_scope, handle_scope_guard, must,
     runtime::{
-        Arguments, Context, EvalResult, Handle, HeapItemKind, HeapPtr, PropertyDescriptor,
-        PropertyKey, Realm, Value,
+        Arguments, BigIntValue, Context, EvalResult, Handle, HeapItemKind, HeapPtr,
+        PropertyDescriptor, PropertyKey, Realm, SymbolValue, Value,
         abstract_operations::{
             call, call_object, copy_data_properties, create_data_property_or_throw,
             define_property_or_throw, get_method, get_v, has_property, private_get, private_set,
@@ -137,7 +137,6 @@ use crate::{
             is_callable, is_callable_object, is_loosely_equal, is_strictly_equal,
             same_object_value, to_boolean, to_number, to_numeric, to_object, to_property_key,
         },
-        value::{BigIntValue, SymbolValue},
     },
 };
 
diff --git a/src/js/runtime/collections/mod.rs b/src/js/runtime/collections/mod.rs
--- a/src/js/runtime/collections/mod.rs
+++ b/src/js/runtime/collections/mod.rs
@@ -14,4 +14,4 @@ pub use index_map::{BsIndexMap, BsIndexMapField, IndexMapInstance};
 pub use index_set::{BsIndexSet, BsIndexSetField, IndexSetInstance};
 pub use inline_array::InlineArray;
 pub use vec::{BsVec, BsVecField, VecInstance};
-pub use weak_vec::BsWeakVec;
+pub use weak_vec::WeakValueVec;
diff --git a/src/js/runtime/collections/weak_vec.rs b/src/js/runtime/collections/weak_vec.rs
--- a/src/js/runtime/collections/weak_vec.rs
+++ b/src/js/runtime/collections/weak_vec.rs
@@ -17,33 +17,33 @@ use crate::{
 /// The intrusive `next_weak_vec` list used by the collector lives on the holder of the vec, not on
 /// the vec itself.
 #[repr(C)]
-pub struct BsWeakVec {
+pub struct WeakValueVec {
     descriptor: HeapPtr<HeapItemDescriptor>,
     /// The number of elements stored in the array.
     length: usize,
     // Holds the address of the next weak list that has been visited during garbage collection.
     // Unused outside of garbage collection.
-    next_weak_vec: Option<HeapPtr<BsWeakVec>>,
+    next_weak_vec: Option<HeapPtr<WeakValueVec>>,
     /// The array along with its capacity, which is always a power of 2.
     array: InlineArray<Value>,
 }
 
-impl BsWeakVec {
-    /// Create a new BsWeakVec with the given capacity.
+impl WeakValueVec {
+    /// Create a new WeakValueVec with the given capacity.
     #[allow(unused)]
     pub fn new(cx: Context, capacity: usize) -> AllocResult<HeapPtr<Self>> {
         let size = Self::calculate_size_in_bytes(capacity);
-        let mut vec = cx.alloc_uninit_with_size::<BsWeakVec>(size)?;
+        let mut vec = cx.alloc_uninit_with_size::<WeakValueVec>(size)?;
 
-        set_uninit!(vec.descriptor, cx.descriptors.get(HeapItemKind::WeakVec));
+        set_uninit!(vec.descriptor, cx.descriptors.get(HeapItemKind::WeakValueVec));
         set_uninit!(vec.length, 0);
         set_uninit!(vec.next_weak_vec, None);
         vec.array.init_with_uninit(capacity);
 
         Ok(vec)
     }
 
-    const ARRAY_FIELD_OFFSET: usize = field_offset!(BsWeakVec, array);
+    const ARRAY_FIELD_OFFSET: usize = field_offset!(WeakValueVec, array);
 
     #[inline]
     fn calculate_size_in_bytes(capacity: usize) -> usize {
@@ -65,11 +65,11 @@ impl BsWeakVec {
         self.array.len()
     }
 
-    pub fn next_weak_vec(&self) -> Option<HeapPtr<BsWeakVec>> {
+    pub fn next_weak_vec(&self) -> Option<HeapPtr<WeakValueVec>> {
         self.next_weak_vec
     }
 
-    pub fn set_next_weak_vec(&mut self, next_weak_vec: Option<HeapPtr<BsWeakVec>>) {
+    pub fn set_next_weak_vec(&mut self, next_weak_vec: Option<HeapPtr<WeakValueVec>>) {
         self.next_weak_vec = next_weak_vec;
     }
 
@@ -84,7 +84,7 @@ impl BsWeakVec {
         &mut self.array.as_mut_slice()[..len]
     }
 
-    /// Append an item to the BsWeakVec. Should only be called if there is room to append an item.
+    /// Append an item to the WeakValueVec. Should only be called if there is room to append an item.
     #[allow(unused)]
     pub fn push_without_growing(&mut self, item: Value) {
         let len = self.len();
@@ -93,31 +93,31 @@ impl BsWeakVec {
     }
 }
 
-impl HeapItem for BsWeakVec {
+impl HeapItem for WeakValueVec {
     fn byte_size(bs_weak_vec: HeapPtr<Self>) -> usize {
-        BsWeakVec::calculate_size_in_bytes(bs_weak_vec.capacity())
+        WeakValueVec::calculate_size_in_bytes(bs_weak_vec.capacity())
     }
 
-    /// Visit pointers intrinsic to all BsWeakVec. Do not visit elements as they could be of any type.
+    /// Visit pointers intrinsic to all WeakValueVec. Do not visit elements as they could be of any type.
     fn visit_pointers(mut bs_weak_vec: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         visitor.visit_pointer(&mut bs_weak_vec.descriptor);
     }
 }
 
-/// A BsWeakVec stored as the field of a heap item. Can create new BsWeakVec objects and set the
-/// field to a new BsWeakVec.
+/// A WeakValueVec stored as the field of a heap item. Can create new WeakValueVec objects and set the
+/// field to a new WeakValueVec.
 #[allow(unused)]
-pub trait BsWeakVecField {
-    fn new_vec(cx: Context, capacity: usize) -> AllocResult<HeapPtr<BsWeakVec>>;
+pub trait WeakValueVecField {
+    fn new_vec(cx: Context, capacity: usize) -> AllocResult<HeapPtr<WeakValueVec>>;
 
-    fn get(&self) -> HeapPtr<BsWeakVec>;
+    fn get(&self) -> HeapPtr<WeakValueVec>;
 
-    fn set(&mut self, vec: HeapPtr<BsWeakVec>);
+    fn set(&mut self, vec: HeapPtr<WeakValueVec>);
 
     /// Prepare vec for appending a single item. This will grow the vec and update container to
     /// point to new vec if there is no room to append another item to the vec.
     #[inline]
-    fn maybe_grow_for_push(&mut self, cx: Context) -> AllocResult<HeapPtr<BsWeakVec>> {
+    fn maybe_grow_for_push(&mut self, cx: Context) -> AllocResult<HeapPtr<WeakValueVec>> {
         let old_vec = self.get();
 
         // Check if we have room for another item in the vec
diff --git a/src/js/runtime/console_object.rs b/src/js/runtime/console_object.rs
--- a/src/js/runtime/console_object.rs
+++ b/src/js/runtime/console_object.rs
@@ -100,12 +100,12 @@ pub fn to_console_string(
 ) -> AllocResult<String> {
     let result = if value.is_pointer() {
         match value.as_pointer().descriptor().kind() {
-            HeapItemKind::String => value.as_string().format()?,
-            HeapItemKind::Symbol => match value.as_symbol().description_ptr() {
+            HeapItemKind::StringValue => value.as_string().format()?,
+            HeapItemKind::SymbolValue => match value.as_symbol().description_ptr() {
                 None => String::from("Symbol()"),
                 Some(description) => format!("Symbol({description})"),
             },
-            HeapItemKind::BigInt => format!("{}n", value.as_bigint().bigint()),
+            HeapItemKind::BigIntValue => format!("{}n", value.as_bigint().bigint()),
             // Otherwise must be an object
             _ => {
                 let object = value.as_object();
diff --git a/src/js/runtime/context.rs b/src/js/runtime/context.rs
--- a/src/js/runtime/context.rs
+++ b/src/js/runtime/context.rs
@@ -24,7 +24,7 @@ use crate::{
         ParseContext, analyze::analyze, parse_module, parse_script, print_program, source::Source,
     },
     runtime::{
-        EvalResult, Handle, HeapPtr, Value,
+        EvalResult, Handle, HeapPtr, SymbolValue, Value,
         alloc_error::AllocResult,
         annex_b::init_annex_b_methods,
         array_properties::{ArrayProperties, DenseArrayProperties},
@@ -49,7 +49,6 @@ use crate::{
         realm::Realm,
         string_value::{FlatString, StringValue},
         tasks::TaskQueue,
-        value::SymbolValue,
     },
 };
 
diff --git a/src/js/runtime/debug_print.rs b/src/js/runtime/debug_print.rs
--- a/src/js/runtime/debug_print.rs
+++ b/src/js/runtime/debug_print.rs
@@ -1,13 +1,12 @@
 use crate::runtime::{
-    HeapItemKind, HeapPtr,
+    BigIntValue, HeapItemKind, HeapPtr, SymbolValue,
     bytecode::{
         constant_table::ConstantTable, exception_handlers::ExceptionHandlers,
         function::BytecodeFunction,
     },
     gc::AnyHeapItem,
     regexp::compiled_regexp::CompiledRegExp,
     string_value::StringValue,
-    value::{BigIntValue, SymbolValue},
 };
 
 #[derive(Clone, Copy, PartialEq)]
@@ -114,9 +113,9 @@ impl DebugPrinter {
 impl DebugPrint for HeapPtr<AnyHeapItem> {
     fn debug_format(&self, printer: &mut DebugPrinter) {
         match self.descriptor().kind() {
-            HeapItemKind::String => self.cast::<StringValue>().debug_format(printer),
-            HeapItemKind::Symbol => self.cast::<SymbolValue>().debug_format(printer),
-            HeapItemKind::BigInt => self.cast::<BigIntValue>().debug_format(printer),
+            HeapItemKind::StringValue => self.cast::<StringValue>().debug_format(printer),
+            HeapItemKind::SymbolValue => self.cast::<SymbolValue>().debug_format(printer),
+            HeapItemKind::BigIntValue => self.cast::<BigIntValue>().debug_format(printer),
             HeapItemKind::BytecodeFunction => self.cast::<BytecodeFunction>().debug_format(printer),
             HeapItemKind::ConstantTable => self.cast::<ConstantTable>().debug_format(printer),
             HeapItemKind::ExceptionHandlers => {
diff --git a/src/js/runtime/descriptor_registry.rs b/src/js/runtime/descriptor_registry.rs
--- a/src/js/runtime/descriptor_registry.rs
+++ b/src/js/runtime/descriptor_registry.rs
@@ -41,7 +41,7 @@ impl DescriptorRegistry {
 
         // First set up the descriptor descriptor since it is needed for all others
         let descriptor = HeapItemDescriptor::new_descriptor_descriptor(cx)?.to_handle();
-        descriptors[HeapItemKind::Descriptor as usize] = *descriptor;
+        descriptors[HeapItemKind::HeapItemDescriptor as usize] = *descriptor;
 
         macro_rules! register_descriptor {
             ($object_kind:expr, $object_ty:ty, $flags:expr) => {
@@ -171,9 +171,9 @@ impl DescriptorRegistry {
 
         ordinary_object_descriptor!(HeapItemKind::ObjectPrototypeObject);
 
-        other_heap_item_descriptor!(HeapItemKind::String);
-        other_heap_item_descriptor!(HeapItemKind::Symbol);
-        other_heap_item_descriptor!(HeapItemKind::BigInt);
+        other_heap_item_descriptor!(HeapItemKind::StringValue);
+        other_heap_item_descriptor!(HeapItemKind::SymbolValue);
+        other_heap_item_descriptor!(HeapItemKind::BigIntValue);
         other_heap_item_descriptor!(HeapItemKind::Accessor);
 
         ordinary_object_descriptor!(HeapItemKind::PromiseObject);
@@ -236,7 +236,7 @@ impl DescriptorRegistry {
 
         other_heap_item_descriptor!(HeapItemKind::FunctionVec);
         other_heap_item_descriptor!(HeapItemKind::SourceTextModuleVec);
-        other_heap_item_descriptor!(HeapItemKind::WeakVec);
+        other_heap_item_descriptor!(HeapItemKind::WeakValueVec);
 
         Ok(base_descriptors)
     }
diff --git a/src/js/runtime/eval/expression.rs b/src/js/runtime/eval/expression.rs
--- a/src/js/runtime/eval/expression.rs
+++ b/src/js/runtime/eval/expression.rs
@@ -6,7 +6,7 @@ use crate::{
     must, must_a,
     parser::ast,
     runtime::{
-        Context, Handle, HeapItemKind, Realm,
+        BigIntValue, Context, Handle, HeapItemKind, Realm,
         abstract_operations::{
             IntegrityLevel, call_object, define_property_or_throw, get_method, has_property,
             ordinary_has_instance, set_integrity_level,
@@ -25,7 +25,7 @@ use crate::{
             ToPrimitivePreferredType, is_less_than, to_boolean, to_int32, to_numeric, to_object,
             to_primitive, to_property_key, to_string, to_uint32,
         },
-        value::{BOOL_TAG, BigIntValue, NULL_TAG, UNDEFINED_TAG, Value},
+        value::{BOOL_TAG, NULL_TAG, UNDEFINED_TAG, Value},
     },
 };
 
@@ -89,9 +89,9 @@ pub fn eval_typeof(mut cx: Context, value: Handle<Value>) -> AllocResult<Handle<
     let type_string = if value.is_pointer() {
         let kind = value.as_pointer().descriptor().kind();
         match kind {
-            HeapItemKind::String => "string",
-            HeapItemKind::Symbol => "symbol",
-            HeapItemKind::BigInt => "bigint",
+            HeapItemKind::StringValue => "string",
+            HeapItemKind::SymbolValue => "symbol",
+            HeapItemKind::BigIntValue => "bigint",
             // All other pointer values must be an object
             _ => {
                 if value.as_object().is_callable() {
diff --git a/src/js/runtime/gc/garbage_collector.rs b/src/js/runtime/gc/garbage_collector.rs
--- a/src/js/runtime/gc/garbage_collector.rs
+++ b/src/js/runtime/gc/garbage_collector.rs
@@ -2,7 +2,7 @@ use std::{ops::Range, ptr::NonNull};
 
 use crate::runtime::{
     Context, HeapItemKind, Value,
-    collections::BsWeakVec,
+    collections::WeakValueVec,
     gc::{AnyHeapItem, Heap, HeapItem, HeapPtr, HeapVisitor},
     heap_item_descriptor::HeapItemDescriptor,
     interned_strings::InternedStrings,
@@ -47,8 +47,8 @@ pub struct GarbageCollector {
     // Intrusive list of all FinalizationRegistries that have been visited during this gc cycle
     finalization_registry_list: Option<HeapPtr<FinalizationRegistryObject>>,
 
-    // Intrusive list of all WeakVecs that have been visited during this gc cycle
-    weak_vec_list: Option<HeapPtr<BsWeakVec>>,
+    // Intrusive list of all WeakValueVec that have been visited during this gc cycle
+    weak_vec_list: Option<HeapPtr<WeakValueVec>>,
 }
 
 #[derive(Clone, Debug)]
@@ -282,7 +282,9 @@ impl GarbageCollector {
             HeapItemKind::WeakMapObject => {
                 self.add_visited_weak_map(new_heap_item.cast::<WeakMapObject>())
             }
-            HeapItemKind::WeakVec => self.add_visited_weak_vec(new_heap_item.cast::<BsWeakVec>()),
+            HeapItemKind::WeakValueVec => {
+                self.add_visited_weak_vec(new_heap_item.cast::<WeakValueVec>())
+            }
             HeapItemKind::FinalizationRegistryObject => self.add_visited_finalization_registry(
                 new_heap_item.cast::<FinalizationRegistryObject>(),
             ),
@@ -366,7 +368,7 @@ impl GarbageCollector {
     }
 
     // Add a weak vec to the linked list of weak vecs that are live during this garbage collection.
-    fn add_visited_weak_vec(&mut self, mut weak_vec: HeapPtr<BsWeakVec>) {
+    fn add_visited_weak_vec(&mut self, mut weak_vec: HeapPtr<WeakValueVec>) {
         weak_vec.set_next_weak_vec(self.weak_vec_list);
         self.weak_vec_list = Some(weak_vec);
     }
@@ -626,11 +628,11 @@ impl GarbageCollector {
         }
     }
 
-    /// Compress a `BsWeakVec` by removing elements that have been garbage collected.
+    /// Compress a `WeakValueVec` by removing elements that have been garbage collected.
     ///
     /// Vector is compressed in place by moving live elements down to fill the slots of dead
     /// elements. Note that backing array is never shrunk.
-    fn compress_weak_vec(&self, mut weak_vec: HeapPtr<BsWeakVec>) {
+    fn compress_weak_vec(&self, mut weak_vec: HeapPtr<WeakValueVec>) {
         let len = weak_vec.len();
         let mut next_kept_index = 0;
 
diff --git a/src/js/runtime/gc/handle.rs b/src/js/runtime/gc/handle.rs
--- a/src/js/runtime/gc/handle.rs
+++ b/src/js/runtime/gc/handle.rs
@@ -6,11 +6,10 @@ use std::{
 };
 
 use crate::runtime::{
-    Context, Value,
+    BigIntValue, Context, SymbolValue, Value,
     gc::{Heap, HeapInfo, HeapPtr, HeapVisitor, IsHeapItem},
     object_value::ObjectValue,
     string_value::StringValue,
-    value::{BigIntValue, SymbolValue},
 };
 
 /// Handles store a pointer-sized unit of data. This may be either a value or a heap pointer.
diff --git a/src/js/runtime/gc/heap_item.rs b/src/js/runtime/gc/heap_item.rs
--- a/src/js/runtime/gc/heap_item.rs
+++ b/src/js/runtime/gc/heap_item.rs
@@ -1,6 +1,6 @@
 use crate::{
     runtime::{
-        Realm,
+        BigIntValue, Realm, SymbolValue,
         accessor::Accessor,
         arguments_object::{MappedArgumentsObject, UnmappedArgumentsObject},
         array_object::ArrayObject,
@@ -16,7 +16,7 @@ use crate::{
         },
         class_names::ClassNames,
         collections::{
-            BsWeakVec,
+            WeakValueVec,
             array::{ByteArray, U32Array, ValueArray},
         },
         context::{GlobalSymbolRegistryMap, ModuleCacheMap},
@@ -74,7 +74,8 @@ use crate::{
             },
             synthetic_module::SyntheticModule,
         },
-        object_value::{NamedPropertiesMap, ObjectValue},
+        object_value::NamedPropertiesMap,
+        ordinary_object::OrdinaryObject,
         promise_object::{PromiseCapability, PromiseObject, PromiseReaction},
         proxy_object::ProxyObject,
         realm::{GlobalScopes, LexicalNamesMap},
@@ -85,7 +86,6 @@ use crate::{
         stack_trace::StackFrameInfoArray,
         string_object::StringObject,
         string_value::StringValue,
-        value::{BigIntValue, SymbolValue},
     },
     unit,
 };
@@ -110,7 +110,7 @@ pub trait WithHeapItemKind {
     const KIND: HeapItemKind;
 }
 
-impl<T: WithHeapItemKind> HeapPtr<T> {
+impl<T> HeapPtr<T> {
     /// Whether this is a heap item of a particular type.
     #[inline]
     pub fn is<U: WithHeapItemKind>(&self) -> bool {
@@ -134,10 +134,10 @@ impl<T: WithHeapItemKind> HeapPtr<T> {
 }
 
 macro_rules! register_heap_items {
-    ($(($kind:ident, $item_name:ident),)*) => {
+    ($(($name:ident),)*) => {
         $(
-            impl WithHeapItemKind for $item_name {
-                const KIND: HeapItemKind = HeapItemKind::$kind;
+            impl WithHeapItemKind for $name {
+                const KIND: HeapItemKind = HeapItemKind::$name;
             }
         )*
 
@@ -146,22 +146,22 @@ macro_rules! register_heap_items {
         #[derive(Clone, Copy, Debug, PartialEq)]
         #[repr(u8)]
         pub enum HeapItemKind {
-            $($kind,)*
+            $($name,)*
         }
 
         impl HeapItemKind {
-            pub const COUNT: usize = <[()]>::len(&[$(unit!($kind)),*]);
+            pub const COUNT: usize = <[()]>::len(&[$(unit!($name)),*]);
         }
 
         pub fn byte_size_for_kind(item: HeapPtr<AnyHeapItem>, kind: HeapItemKind) -> usize {
             match kind {
-                $(HeapItemKind::$kind => $item_name::byte_size(item.cast()),)*
+                $(HeapItemKind::$name => $name::byte_size(item.cast()),)*
             }
         }
 
         pub fn visit_pointers_for_kind(item: HeapPtr<AnyHeapItem>, visitor: &mut impl HeapVisitor, kind: HeapItemKind) {
             match kind {
-                $(HeapItemKind::$kind => $item_name::visit_pointers(item.cast(), visitor),)*
+                $(HeapItemKind::$name => $name::visit_pointers(item.cast(), visitor),)*
             }
         }
 
@@ -180,109 +180,109 @@ macro_rules! register_heap_items {
 }
 
 register_heap_items!(
-    (Descriptor, HeapItemDescriptor),
-    (OrdinaryObject, ObjectValue),
-    (ProxyObject, ProxyObject),
-    (BooleanObject, BooleanObject),
-    (NumberObject, NumberObject),
-    (StringObject, StringObject),
-    (SymbolObject, SymbolObject),
-    (BigIntObject, BigIntObject),
-    (ArrayObject, ArrayObject),
-    (RegExpObject, RegExpObject),
-    (ErrorObject, ErrorObject),
-    (DateObject, DateObject),
-    (SetObject, SetObject),
-    (MapObject, MapObject),
-    (WeakRefObject, WeakRefObject),
-    (WeakSetObject, WeakSetObject),
-    (WeakMapObject, WeakMapObject),
-    (FinalizationRegistryObject, FinalizationRegistryObject),
-    (RawJSONObject, RawJSONObject),
-    (MappedArgumentsObject, MappedArgumentsObject),
-    (UnmappedArgumentsObject, UnmappedArgumentsObject),
-    (Int8ArrayObject, Int8ArrayObject),
-    (UInt8ArrayObject, UInt8ArrayObject),
-    (UInt8ClampedArrayObject, UInt8ClampedArrayObject),
-    (Int16ArrayObject, Int16ArrayObject),
-    (UInt16ArrayObject, UInt16ArrayObject),
-    (Int32ArrayObject, Int32ArrayObject),
-    (UInt32ArrayObject, UInt32ArrayObject),
-    (BigInt64ArrayObject, BigInt64ArrayObject),
-    (BigUInt64ArrayObject, BigUInt64ArrayObject),
-    (Float16ArrayObject, Float16ArrayObject),
-    (Float32ArrayObject, Float32ArrayObject),
-    (Float64ArrayObject, Float64ArrayObject),
-    (ArrayBufferObject, ArrayBufferObject),
-    (DataViewObject, DataViewObject),
-    (DurationObject, DurationObject),
-    (InstantObject, InstantObject),
-    (PlainDateObject, PlainDateObject),
-    (PlainDateTimeObject, PlainDateTimeObject),
-    (PlainMonthDayObject, PlainMonthDayObject),
-    (PlainTimeObject, PlainTimeObject),
-    (PlainYearMonthObject, PlainYearMonthObject),
-    (ZonedDateTimeObject, ZonedDateTimeObject),
-    (ArrayIteratorObject, ArrayIteratorObject),
-    (StringIteratorObject, StringIteratorObject),
-    (SetIteratorObject, SetIteratorObject),
-    (MapIteratorObject, MapIteratorObject),
-    (RegExpStringIteratorObject, RegExpStringIteratorObject),
-    (ForInIterator, ForInIterator),
-    (AsyncFromSyncIteratorObject, AsyncFromSyncIteratorObject),
-    (WrappedValidIteratorObject, WrappedValidIteratorObject),
-    (IteratorHelperObject, IteratorHelperObject),
-    (ObjectPrototypeObject, ObjectPrototypeObject),
-    (String, StringValue),
-    (Symbol, SymbolValue),
-    (BigInt, BigIntValue),
-    (Accessor, Accessor),
-    (PromiseObject, PromiseObject),
-    (PromiseReaction, PromiseReaction),
-    (PromiseCapability, PromiseCapability),
-    (Realm, Realm),
-    (ClosureObject, ClosureObject),
-    (BytecodeFunction, BytecodeFunction),
-    (ConstantTable, ConstantTable),
-    (ExceptionHandlers, ExceptionHandlers),
-    (SourceFile, SourceFile),
-    (Scope, Scope),
-    (ScopeNames, ScopeNames),
-    (GlobalNames, GlobalNames),
-    (ClassNames, ClassNames),
-    (SourceTextModule, SourceTextModule),
-    (SyntheticModule, SyntheticModule),
-    (ModuleNamespaceObject, ModuleNamespaceObject),
-    (ImportAttributes, ImportAttributes),
-    (GeneratorObject, GeneratorObject),
-    (AsyncGeneratorObject, AsyncGeneratorObject),
-    (AsyncGeneratorRequest, AsyncGeneratorRequest),
-    (BuiltinGenerator, BuiltinGenerator),
-    (DenseArrayProperties, DenseArrayProperties),
-    (SparseArrayPropertiesMap, SparseArrayPropertiesMap),
-    (CompiledRegExp, CompiledRegExp),
-    (BoxedValue, BoxedValue),
-    (NamedPropertiesMap, NamedPropertiesMap),
-    (ValueIndexMap, ValueIndexMap),
-    (ValueIndexSet, ValueIndexSet),
-    (ExportMap, ExportMap),
-    (WeakValueMap, WeakValueMap),
-    (WeakValueSet, WeakValueSet),
-    (GlobalSymbolRegistryMap, GlobalSymbolRegistryMap),
-    (InternedStringsSet, InternedStringsSet),
-    (LexicalNamesMap, LexicalNamesMap),
-    (ModuleCacheMap, ModuleCacheMap),
-    (ValueArray, ValueArray),
-    (ByteArray, ByteArray),
-    (U32Array, U32Array),
-    (ModuleRequestArray, ModuleRequestArray),
-    (ModuleOptionArray, ModuleOptionArray),
-    (StackFrameInfoArray, StackFrameInfoArray),
-    (FinalizationRegistryCells, FinalizationRegistryCells),
-    (GlobalScopes, GlobalScopes),
-    (FunctionVec, FunctionVec),
-    (SourceTextModuleVec, SourceTextModuleVec),
-    (WeakVec, BsWeakVec),
+    (HeapItemDescriptor),
+    (OrdinaryObject),
+    (ProxyObject),
+    (BooleanObject),
+    (NumberObject),
+    (StringObject),
+    (SymbolObject),
+    (BigIntObject),
+    (ArrayObject),
+    (RegExpObject),
+    (ErrorObject),
+    (DateObject),
+    (SetObject),
+    (MapObject),
+    (WeakRefObject),
+    (WeakSetObject),
+    (WeakMapObject),
+    (FinalizationRegistryObject),
+    (RawJSONObject),
+    (MappedArgumentsObject),
+    (UnmappedArgumentsObject),
+    (Int8ArrayObject),
+    (UInt8ArrayObject),
+    (UInt8ClampedArrayObject),
+    (Int16ArrayObject),
+    (UInt16ArrayObject),
+    (Int32ArrayObject),
+    (UInt32ArrayObject),
+    (BigInt64ArrayObject),
+    (BigUInt64ArrayObject),
+    (Float16ArrayObject),
+    (Float32ArrayObject),
+    (Float64ArrayObject),
+    (ArrayBufferObject),
+    (DataViewObject),
+    (DurationObject),
+    (InstantObject),
+    (PlainDateObject),
+    (PlainDateTimeObject),
+    (PlainMonthDayObject),
+    (PlainTimeObject),
+    (PlainYearMonthObject),
+    (ZonedDateTimeObject),
+    (ArrayIteratorObject),
+    (StringIteratorObject),
+    (SetIteratorObject),
+    (MapIteratorObject),
+    (RegExpStringIteratorObject),
+    (ForInIterator),
+    (AsyncFromSyncIteratorObject),
+    (WrappedValidIteratorObject),
+    (IteratorHelperObject),
+    (ObjectPrototypeObject),
+    (StringValue),
+    (SymbolValue),
+    (BigIntValue),
+    (Accessor),
+    (PromiseObject),
+    (PromiseReaction),
+    (PromiseCapability),
+    (Realm),
+    (ClosureObject),
+    (BytecodeFunction),
+    (ConstantTable),
+    (ExceptionHandlers),
+    (SourceFile),
+    (Scope),
+    (ScopeNames),
+    (GlobalNames),
+    (ClassNames),
+    (SourceTextModule),
+    (SyntheticModule),
+    (ModuleNamespaceObject),
+    (ImportAttributes),
+    (GeneratorObject),
+    (AsyncGeneratorObject),
+    (AsyncGeneratorRequest),
+    (BuiltinGenerator),
+    (DenseArrayProperties),
+    (SparseArrayPropertiesMap),
+    (CompiledRegExp),
+    (BoxedValue),
+    (NamedPropertiesMap),
+    (ValueIndexMap),
+    (ValueIndexSet),
+    (ExportMap),
+    (WeakValueMap),
+    (WeakValueSet),
+    (GlobalSymbolRegistryMap),
+    (InternedStringsSet),
+    (LexicalNamesMap),
+    (ModuleCacheMap),
+    (ValueArray),
+    (ByteArray),
+    (U32Array),
+    (ModuleRequestArray),
+    (ModuleOptionArray),
+    (StackFrameInfoArray),
+    (FinalizationRegistryCells),
+    (GlobalScopes),
+    (FunctionVec),
+    (SourceTextModuleVec),
+    (WeakValueVec),
 );
 
 /// An arbitrary heap item. Only common field between heap items is their descriptor, which can be
@@ -301,21 +301,3 @@ impl AnyHeapItem {
         self.descriptor = descriptor;
     }
 }
-
-impl HeapPtr<AnyHeapItem> {
-    /// Whether this is a heap item of a particular type.
-    #[inline]
-    pub fn is<U: WithHeapItemKind>(&self) -> bool {
-        self.descriptor().kind() == U::KIND
-    }
-
-    /// Return this value as a heap item of a particular type, or None if it is not of that type.
-    #[inline]
-    pub fn as_opt<U: WithHeapItemKind>(&self) -> Option<HeapPtr<U>> {
-        if self.is::<U>() {
-            Some(self.cast())
-        } else {
-            None
-        }
-    }
-}
diff --git a/src/js/runtime/generator_object.rs b/src/js/runtime/generator_object.rs
--- a/src/js/runtime/generator_object.rs
+++ b/src/js/runtime/generator_object.rs
@@ -298,7 +298,7 @@ impl HeapItem for GeneratorObject {
         GeneratorObject::calculate_size_in_bytes(generator_object.stack_frame.len())
     }
 
-    fn visit_pointers(generator_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut generator_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         generator_object.visit_object_pointers(visitor);
 
         if generator_object.state.is_suspended() {
diff --git a/src/js/runtime/heap_item_descriptor.rs b/src/js/runtime/heap_item_descriptor.rs
--- a/src/js/runtime/heap_item_descriptor.rs
+++ b/src/js/runtime/heap_item_descriptor.rs
@@ -66,7 +66,7 @@ impl HeapItemDescriptor {
         let mut descriptor = HeapItemDescriptor::new::<OrdinaryObject>(
             cx,
             fake_descriptor_handle,
-            HeapItemKind::Descriptor,
+            HeapItemKind::HeapItemDescriptor,
             DescFlags::empty(),
         )?;
 
diff --git a/src/js/runtime/intrinsics/bigint_constructor.rs b/src/js/runtime/intrinsics/bigint_constructor.rs
--- a/src/js/runtime/intrinsics/bigint_constructor.rs
+++ b/src/js/runtime/intrinsics/bigint_constructor.rs
@@ -4,7 +4,7 @@ use num_traits::FromPrimitive;
 use crate::{
     intrinsic_methods,
     runtime::{
-        Context, Handle, Value,
+        BigIntValue, Context, Handle, Value,
         alloc_error::AllocResult,
         error::{range_error, type_error},
         eval_result::EvalResult,
@@ -15,7 +15,6 @@ use crate::{
         type_utilities::{
             ToPrimitivePreferredType, is_integral_number, to_bigint, to_index, to_primitive,
         },
-        value::BigIntValue,
     },
     runtime_fn,
 };
diff --git a/src/js/runtime/intrinsics/bigint_object.rs b/src/js/runtime/intrinsics/bigint_object.rs
--- a/src/js/runtime/intrinsics/bigint_object.rs
+++ b/src/js/runtime/intrinsics/bigint_object.rs
@@ -3,12 +3,11 @@ use std::mem::size_of;
 use crate::{
     extend_object,
     runtime::{
-        Context, HeapItemKind, HeapPtr,
+        BigIntValue, Context, HeapItemKind, HeapPtr,
         alloc_error::AllocResult,
         gc::{Handle, HeapItem, HeapVisitor},
         intrinsics::intrinsics::Intrinsic,
         ordinary_object::object_create,
-        value::BigIntValue,
     },
     set_uninit,
 };
diff --git a/src/js/runtime/intrinsics/bigint_prototype.rs b/src/js/runtime/intrinsics/bigint_prototype.rs
--- a/src/js/runtime/intrinsics/bigint_prototype.rs
+++ b/src/js/runtime/intrinsics/bigint_prototype.rs
@@ -1,7 +1,7 @@
 use crate::{
     intrinsic_methods,
     runtime::{
-        Context, Handle, Value,
+        BigIntValue, Context, Handle, Value,
         alloc_error::AllocResult,
         error::{range_error, type_error},
         eval_result::EvalResult,
@@ -10,7 +10,6 @@ use crate::{
         object_value::ObjectValue,
         realm::Realm,
         type_utilities::to_integer_or_infinity,
-        value::BigIntValue,
     },
     runtime_fn,
 };
diff --git a/src/js/runtime/intrinsics/boolean_object.rs b/src/js/runtime/intrinsics/boolean_object.rs
--- a/src/js/runtime/intrinsics/boolean_object.rs
+++ b/src/js/runtime/intrinsics/boolean_object.rs
@@ -81,7 +81,7 @@ impl HeapItem for BooleanObject {
         size_of::<BooleanObject>()
     }
 
-    fn visit_pointers(boolean_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut boolean_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         boolean_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/date_object.rs b/src/js/runtime/intrinsics/date_object.rs
--- a/src/js/runtime/intrinsics/date_object.rs
+++ b/src/js/runtime/intrinsics/date_object.rs
@@ -382,7 +382,7 @@ impl HeapItem for DateObject {
         size_of::<DateObject>()
     }
 
-    fn visit_pointers(date_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut date_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         date_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/number_object.rs b/src/js/runtime/intrinsics/number_object.rs
--- a/src/js/runtime/intrinsics/number_object.rs
+++ b/src/js/runtime/intrinsics/number_object.rs
@@ -81,7 +81,7 @@ impl HeapItem for NumberObject {
         size_of::<NumberObject>()
     }
 
-    fn visit_pointers(number_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut number_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         number_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/object_prototype_object.rs b/src/js/runtime/intrinsics/object_prototype_object.rs
--- a/src/js/runtime/intrinsics/object_prototype_object.rs
+++ b/src/js/runtime/intrinsics/object_prototype_object.rs
@@ -330,7 +330,7 @@ impl HeapItem for ObjectPrototypeObject {
         size_of::<ObjectPrototypeObject>()
     }
 
-    fn visit_pointers(object_prototype: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut object_prototype: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         object_prototype.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/raw_json_object.rs b/src/js/runtime/intrinsics/raw_json_object.rs
--- a/src/js/runtime/intrinsics/raw_json_object.rs
+++ b/src/js/runtime/intrinsics/raw_json_object.rs
@@ -43,7 +43,7 @@ impl HeapItem for RawJSONObject {
         size_of::<RawJSONObject>()
     }
 
-    fn visit_pointers(raw_json_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut raw_json_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         raw_json_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/symbol_constructor.rs b/src/js/runtime/intrinsics/symbol_constructor.rs
--- a/src/js/runtime/intrinsics/symbol_constructor.rs
+++ b/src/js/runtime/intrinsics/symbol_constructor.rs
@@ -1,7 +1,7 @@
 use crate::{
     intrinsic_methods,
     runtime::{
-        Context, Handle,
+        Context, Handle, SymbolValue,
         alloc_error::AllocResult,
         collections::hash_map::BsHashMapField,
         error::type_error,
@@ -10,7 +10,6 @@ use crate::{
         object_value::ObjectValue,
         realm::Realm,
         type_utilities::to_string,
-        value::SymbolValue,
     },
     runtime_fn,
 };
diff --git a/src/js/runtime/intrinsics/symbol_object.rs b/src/js/runtime/intrinsics/symbol_object.rs
--- a/src/js/runtime/intrinsics/symbol_object.rs
+++ b/src/js/runtime/intrinsics/symbol_object.rs
@@ -3,12 +3,11 @@ use std::mem::size_of;
 use crate::{
     extend_object,
     runtime::{
-        Context, HeapItemKind, HeapPtr,
+        Context, HeapItemKind, HeapPtr, SymbolValue,
         alloc_error::AllocResult,
         gc::{Handle, HeapItem, HeapVisitor},
         intrinsics::intrinsics::Intrinsic,
         ordinary_object::object_create,
-        value::SymbolValue,
     },
     set_uninit,
 };
diff --git a/src/js/runtime/intrinsics/symbol_prototype.rs b/src/js/runtime/intrinsics/symbol_prototype.rs
--- a/src/js/runtime/intrinsics/symbol_prototype.rs
+++ b/src/js/runtime/intrinsics/symbol_prototype.rs
@@ -2,7 +2,7 @@ use crate::runtime::intrinsics::symbol_object::SymbolObject;
 use crate::{
     intrinsic_methods,
     runtime::{
-        Context, Handle, Value,
+        Context, Handle, SymbolValue, Value,
         alloc_error::AllocResult,
         error::type_error,
         eval_result::EvalResult,
@@ -12,7 +12,6 @@ use crate::{
         property::Property,
         realm::Realm,
         string_value::StringValue,
-        value::SymbolValue,
     },
     runtime_fn,
 };
diff --git a/src/js/runtime/intrinsics/temporal/duration_object.rs b/src/js/runtime/intrinsics/temporal/duration_object.rs
--- a/src/js/runtime/intrinsics/temporal/duration_object.rs
+++ b/src/js/runtime/intrinsics/temporal/duration_object.rs
@@ -53,7 +53,7 @@ impl HeapItem for DurationObject {
         size_of::<DurationObject>()
     }
 
-    fn visit_pointers(duration_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut duration_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         duration_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/temporal/instant_object.rs b/src/js/runtime/intrinsics/temporal/instant_object.rs
--- a/src/js/runtime/intrinsics/temporal/instant_object.rs
+++ b/src/js/runtime/intrinsics/temporal/instant_object.rs
@@ -53,7 +53,7 @@ impl HeapItem for InstantObject {
         size_of::<InstantObject>()
     }
 
-    fn visit_pointers(instant_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut instant_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         instant_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/temporal/instant_prototype.rs b/src/js/runtime/intrinsics/temporal/instant_prototype.rs
--- a/src/js/runtime/intrinsics/temporal/instant_prototype.rs
+++ b/src/js/runtime/intrinsics/temporal/instant_prototype.rs
@@ -4,7 +4,7 @@ use temporal_rs::options::{RoundingMode, RoundingOptions, ToStringRoundingOption
 use crate::{
     intrinsic_getter_methods, intrinsic_methods,
     runtime::{
-        Arguments, Context, EvalResult, Handle, Realm, Value,
+        Arguments, BigIntValue, Context, EvalResult, Handle, Realm, Value,
         alloc_error::AllocResult,
         error::type_error,
         intrinsic_builder::IntrinsicBuilder,
@@ -25,7 +25,6 @@ use crate::{
             },
         },
         object_value::ObjectValue,
-        value::BigIntValue,
     },
     runtime_fn,
 };
diff --git a/src/js/runtime/intrinsics/temporal/plain_date_object.rs b/src/js/runtime/intrinsics/temporal/plain_date_object.rs
--- a/src/js/runtime/intrinsics/temporal/plain_date_object.rs
+++ b/src/js/runtime/intrinsics/temporal/plain_date_object.rs
@@ -53,7 +53,7 @@ impl HeapItem for PlainDateObject {
         size_of::<PlainDateObject>()
     }
 
-    fn visit_pointers(plain_date_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut plain_date_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         plain_date_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/temporal/plain_date_time_object.rs b/src/js/runtime/intrinsics/temporal/plain_date_time_object.rs
--- a/src/js/runtime/intrinsics/temporal/plain_date_time_object.rs
+++ b/src/js/runtime/intrinsics/temporal/plain_date_time_object.rs
@@ -53,7 +53,7 @@ impl HeapItem for PlainDateTimeObject {
         size_of::<PlainDateTimeObject>()
     }
 
-    fn visit_pointers(plain_date_time_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut plain_date_time_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         plain_date_time_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/temporal/plain_month_day_object.rs b/src/js/runtime/intrinsics/temporal/plain_month_day_object.rs
--- a/src/js/runtime/intrinsics/temporal/plain_month_day_object.rs
+++ b/src/js/runtime/intrinsics/temporal/plain_month_day_object.rs
@@ -53,7 +53,7 @@ impl HeapItem for PlainMonthDayObject {
         size_of::<PlainMonthDayObject>()
     }
 
-    fn visit_pointers(plain_month_day_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut plain_month_day_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         plain_month_day_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/temporal/plain_time_object.rs b/src/js/runtime/intrinsics/temporal/plain_time_object.rs
--- a/src/js/runtime/intrinsics/temporal/plain_time_object.rs
+++ b/src/js/runtime/intrinsics/temporal/plain_time_object.rs
@@ -53,7 +53,7 @@ impl HeapItem for PlainTimeObject {
         size_of::<PlainTimeObject>()
     }
 
-    fn visit_pointers(plain_time_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut plain_time_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         plain_time_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/temporal/plain_year_month_object.rs b/src/js/runtime/intrinsics/temporal/plain_year_month_object.rs
--- a/src/js/runtime/intrinsics/temporal/plain_year_month_object.rs
+++ b/src/js/runtime/intrinsics/temporal/plain_year_month_object.rs
@@ -56,7 +56,7 @@ impl HeapItem for PlainYearMonthObject {
         size_of::<PlainYearMonthObject>()
     }
 
-    fn visit_pointers(plain_year_month_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut plain_year_month_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         plain_year_month_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/temporal/zoned_date_time_object.rs b/src/js/runtime/intrinsics/temporal/zoned_date_time_object.rs
--- a/src/js/runtime/intrinsics/temporal/zoned_date_time_object.rs
+++ b/src/js/runtime/intrinsics/temporal/zoned_date_time_object.rs
@@ -56,7 +56,7 @@ impl HeapItem for ZonedDateTimeObject {
         size_of::<ZonedDateTimeObject>()
     }
 
-    fn visit_pointers(zoned_date_time_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+    fn visit_pointers(mut zoned_date_time_object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
         zoned_date_time_object.visit_object_pointers(visitor);
     }
 }
diff --git a/src/js/runtime/intrinsics/temporal/zoned_date_time_prototype.rs b/src/js/runtime/intrinsics/temporal/zoned_date_time_prototype.rs
--- a/src/js/runtime/intrinsics/temporal/zoned_date_time_prototype.rs
+++ b/src/js/runtime/intrinsics/temporal/zoned_date_time_prototype.rs
@@ -7,7 +7,7 @@ use temporal_rs::options::{
 use crate::{
     intrinsic_getter_methods, intrinsic_methods, must,
     runtime::{
-        Arguments, Context, EvalResult, Handle, Realm, Value,
+        Arguments, BigIntValue, Context, EvalResult, Handle, Realm, Value,
         abstract_operations::create_data_property_or_throw,
         alloc_error::AllocResult,
         error::type_error,
@@ -40,7 +40,6 @@ use crate::{
         },
         object_value::ObjectValue,
         ordinary_object::ordinary_object_create_without_proto,
-        value::BigIntValue,
     },
     runtime_fn,
 };
diff --git a/src/js/runtime/intrinsics/typed_array.rs b/src/js/runtime/intrinsics/typed_array.rs
--- a/src/js/runtime/intrinsics/typed_array.rs
+++ b/src/js/runtime/intrinsics/typed_array.rs
@@ -9,7 +9,7 @@ use crate::{
     create_typed_array_constructor, create_typed_array_object, create_typed_array_prototype,
     extend_object, heap_trait_object,
     runtime::{
-        Context, Handle, HeapItemKind, HeapPtr,
+        BigIntValue, Context, Handle, HeapItemKind, HeapPtr,
         abstract_operations::{get, get_method, length_of_array_like, set},
         alloc_error::AllocResult,
         error::{range_error, type_error},
@@ -43,7 +43,7 @@ use crate::{
             to_big_int64, to_big_uint64, to_index, to_int8, to_int16, to_int32, to_number,
             to_uint8, to_uint8_clamp, to_uint16, to_uint32,
         },
-        value::{BigIntValue, Value},
+        value::Value,
     },
     set_uninit,
 };
diff --git a/src/js/runtime/mod.rs b/src/js/runtime/mod.rs
--- a/src/js/runtime/mod.rs
+++ b/src/js/runtime/mod.rs
@@ -6,6 +6,7 @@ mod arguments_object;
 mod array_object;
 mod array_properties;
 mod async_generator_object;
+mod bigint_value;
 mod bound_function_object;
 mod boxed_value;
 pub mod builtin_function;
@@ -51,13 +52,15 @@ pub mod stack_trace;
 mod string_object;
 mod string_parsing;
 pub mod string_value;
+mod symbol_value;
 mod tasks;
 pub mod test_262_object;
 mod test_shell;
 mod type_utilities;
 mod value;
 
 pub use abstract_operations::get;
+pub use bigint_value::BigIntValue;
 pub use console_object::to_console_string;
 pub use context::{Context, ContextBuilder};
 pub use error::BsResult;
@@ -67,5 +70,6 @@ pub use intrinsics::rust_runtime::Arguments;
 pub use property_descriptor::PropertyDescriptor;
 pub use property_key::PropertyKey;
 pub use realm::Realm;
+pub use symbol_value::SymbolValue;
 pub use type_utilities::to_string;
 pub use value::Value;
diff --git a/src/js/runtime/object_value.rs b/src/js/runtime/object_value.rs
--- a/src/js/runtime/object_value.rs
+++ b/src/js/runtime/object_value.rs
@@ -1,27 +1,24 @@
-use std::{
-    mem::{size_of, transmute_copy},
-    num::NonZeroU32,
-};
+use std::{mem::transmute_copy, num::NonZeroU32};
 
 use rand::Rng;
 
 use crate::{
     impl_index_map_instance,
     runtime::{
-        Context, HeapItemKind, Realm,
+        Context, HeapItemKind, Realm, SymbolValue,
         alloc_error::AllocResult,
         array_properties::ArrayProperties,
         collections::{BsIndexMapField, index_map::IndexMapInstance},
         error::type_error,
         eval_result::EvalResult,
-        gc::{Handle, HeapInfo, HeapItem, HeapPtr, HeapVisitor, WithHeapItemKind},
+        gc::{Handle, HeapInfo, HeapItem, HeapPtr, HeapVisitor, IsHeapItem, WithHeapItemKind},
         intrinsics::typed_array::DynTypedArray,
         property::{HeapProperty, Property},
         property_descriptor::PropertyDescriptor,
         property_key::PropertyKey,
         proxy_object::ProxyObject,
         type_utilities::is_callable_object,
-        value::{SymbolValue, Value},
+        value::Value,
     },
     set_uninit,
 };
@@ -140,8 +137,11 @@ macro_rules! extend_object {
 
         impl $(<$($generics),*>)? $crate::runtime::HeapPtr<$name $(<$($generics),*>)?> {
             #[inline]
-            pub fn visit_object_pointers(&self, visitor: &mut impl $crate::runtime::gc::HeapVisitor) {
-                $crate::runtime::object_value::ObjectValue::visit_pointers(self.as_object(), visitor);
+            pub fn visit_object_pointers(&mut self, visitor: &mut impl $crate::runtime::gc::HeapVisitor) {
+                visitor.visit_pointer(&mut self.descriptor);
+                visitor.visit_pointer_opt(&mut self.prototype);
+                visitor.visit_pointer(&mut self.named_properties);
+                visitor.visit_pointer(&mut self.array_properties);
             }
         }
     }
@@ -683,15 +683,5 @@ struct ObjectTraitObject {
     vtable: *const (),
 }
 
-impl HeapItem for ObjectValue {
-    fn byte_size(_: HeapPtr<Self>) -> usize {
-        size_of::<ObjectValue>()
-    }
-
-    fn visit_pointers(mut object_value: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
-        visitor.visit_pointer(&mut object_value.descriptor);
-        visitor.visit_pointer_opt(&mut object_value.prototype);
-        visitor.visit_pointer(&mut object_value.named_properties);
-        visitor.visit_pointer(&mut object_value.array_properties);
-    }
-}
+// Only necessary so we get deref for HeapPtrs.
+impl IsHeapItem for ObjectValue {}
diff --git a/src/js/runtime/ordinary_object.rs b/src/js/runtime/ordinary_object.rs
--- a/src/js/runtime/ordinary_object.rs
+++ b/src/js/runtime/ordinary_object.rs
@@ -1,20 +1,19 @@
-use crate::runtime::intrinsics::object_prototype_object::ObjectPrototypeObject;
-use crate::runtime::proxy_object::ProxyObject;
 use crate::{
-    extend_object_without_conversions, must, must_a,
+    extend_object, must, must_a,
     runtime::{
         Context, HeapItemKind,
         abstract_operations::{call_object, create_data_property, get, get_function_realm},
         accessor::Accessor,
         alloc_error::AllocResult,
         eval_result::EvalResult,
-        gc::{Handle, HeapPtr},
+        gc::{Handle, HeapItem, HeapPtr, HeapVisitor},
         heap_item_descriptor::HeapItemDescriptor,
-        intrinsics::intrinsics::Intrinsic,
+        intrinsics::{intrinsics::Intrinsic, object_prototype_object::ObjectPrototypeObject},
         object_value::{ObjectValue, VirtualObject},
         property::Property,
         property_descriptor::PropertyDescriptor,
         property_key::PropertyKey,
+        proxy_object::ProxyObject,
         rust_vtables::extract_virtual_object_vtable,
         type_utilities::{same_object_value_handles, same_opt_object_value, same_value},
         value::Value,
@@ -23,18 +22,10 @@ use crate::{
 
 // An ordinary object is used to create the vtable for a generic object. Must be a separate type
 // from ObjectValue so that the same methods can appear on ObjectValue but perform dynamic dispatch.
-//
-// Should never be created. Only used to reference its vtable.
-extend_object_without_conversions! {
+extend_object! {
     pub struct OrdinaryObject {}
 }
 
-impl From<OrdinaryObject> for ObjectValue {
-    fn from(value: OrdinaryObject) -> Self {
-        unsafe { std::mem::transmute::<OrdinaryObject, ObjectValue>(value) }
-    }
-}
-
 impl ObjectValue {
     /// OrdinaryGetPrototypeOf (https://tc39.es/ecma262/#sec-ordinarygetprototypeof)
     pub fn ordinary_get_prototype_of(&self) -> EvalResult<Option<Handle<ObjectValue>>> {
@@ -714,3 +705,13 @@ pub fn get_prototype_from_constructor(
         Ok(realm.get_intrinsic(intrinsic_default_proto))
     }
 }
+
+impl HeapItem for OrdinaryObject {
+    fn byte_size(_: HeapPtr<Self>) -> usize {
+        size_of::<OrdinaryObject>()
+    }
+
+    fn visit_pointers(mut object: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+        object.visit_object_pointers(visitor);
+    }
+}
diff --git a/src/js/runtime/property_key.rs b/src/js/runtime/property_key.rs
--- a/src/js/runtime/property_key.rs
+++ b/src/js/runtime/property_key.rs
@@ -4,15 +4,14 @@ use crate::{
     common::numeric::Numeric,
     must_a,
     runtime::{
-        Context, EvalResult, HeapPtr, Value,
+        Context, EvalResult, HeapPtr, SymbolValue, Value,
         alloc_error::AllocResult,
         gc::{Handle, HandleContents, ToHandleContents},
         interned_strings::InternedStrings,
         string_parsing::{StringLexer, parse_string_to_u32},
         string_value::StringValue,
         to_string,
         type_utilities::is_integral_number,
-        value::SymbolValue,
     },
 };
 
diff --git a/src/js/runtime/string_value.rs b/src/js/runtime/string_value.rs
--- a/src/js/runtime/string_value.rs
+++ b/src/js/runtime/string_value.rs
@@ -762,7 +762,7 @@ impl FlatString {
         let size = Self::calculate_size_in_bytes(len, StringWidth::OneByte);
         let mut string = cx.alloc_uninit_with_size::<FlatString>(size)?;
 
-        set_uninit!(string.descriptor, cx.descriptors.get(HeapItemKind::String));
+        set_uninit!(string.descriptor, cx.descriptors.get(HeapItemKind::StringValue));
         set_uninit!(string.len, len);
         set_uninit!(string.kind, StringKind::OneByte);
         set_uninit!(string.is_interned, false);
@@ -785,7 +785,7 @@ impl FlatString {
         let size = Self::calculate_size_in_bytes(len, StringWidth::TwoByte);
         let mut string = cx.alloc_uninit_with_size::<FlatString>(size)?;
 
-        set_uninit!(string.descriptor, cx.descriptors.get(HeapItemKind::String));
+        set_uninit!(string.descriptor, cx.descriptors.get(HeapItemKind::StringValue));
         set_uninit!(string.len, len);
         set_uninit!(string.kind, StringKind::TwoByte);
         set_uninit!(string.is_interned, false);
@@ -1333,7 +1333,7 @@ impl ConcatString {
     ) -> EvalResult<Handle<StringValue>> {
         let mut string = cx.alloc_uninit::<ConcatString>()?;
 
-        set_uninit!(string.descriptor, cx.descriptors.get(HeapItemKind::String));
+        set_uninit!(string.descriptor, cx.descriptors.get(HeapItemKind::StringValue));
         set_uninit!(string.len, len);
         set_uninit!(string.kind, StringKind::Concat);
         set_uninit!(string.width, width);
diff --git a/src/js/runtime/symbol_value.rs b/src/js/runtime/symbol_value.rs
new file mode 100644
--- /dev/null
+++ b/src/js/runtime/symbol_value.rs
@@ -0,0 +1,115 @@
+use std::hash;
+
+use rand::Rng;
+
+use crate::{
+    runtime::{
+        Context, Handle, HeapItemKind, HeapPtr,
+        alloc_error::AllocResult,
+        debug_print::{DebugPrint, DebugPrinter},
+        gc::{HeapItem, HeapVisitor},
+        heap_item_descriptor::HeapItemDescriptor,
+        string_value::{FlatString, StringValue},
+    },
+    set_uninit,
+};
+
+#[repr(C)]
+pub struct SymbolValue {
+    descriptor: HeapPtr<HeapItemDescriptor>,
+    description: Option<HeapPtr<FlatString>>,
+    /// Stable hash code for this symbol, since symbol can be moved by GC
+    hash_code: u32,
+    /// Whether this symbol is for a private name
+    is_private: bool,
+}
+
+impl SymbolValue {
+    pub fn new(
+        mut cx: Context,
+        description: Option<Handle<StringValue>>,
+        is_private: bool,
+    ) -> AllocResult<Handle<SymbolValue>> {
+        let description = description.map(|d| d.flatten()).transpose()?;
+        let mut symbol = cx.alloc_uninit::<SymbolValue>()?;
+
+        set_uninit!(symbol.descriptor, cx.descriptors.get(HeapItemKind::SymbolValue));
+        set_uninit!(symbol.description, description.map(|desc| *desc));
+        set_uninit!(symbol.hash_code, cx.rand.r#gen::<u32>());
+        set_uninit!(symbol.is_private, is_private);
+
+        Ok(symbol.to_handle())
+    }
+
+    pub fn description_ptr(&self) -> Option<HeapPtr<FlatString>> {
+        self.description
+    }
+
+    pub fn description(&self) -> Option<Handle<FlatString>> {
+        self.description.map(|d| d.to_handle())
+    }
+
+    pub fn is_private(&self) -> bool {
+        self.is_private
+    }
+}
+
+impl DebugPrint for HeapPtr<SymbolValue> {
+    fn debug_format(&self, printer: &mut DebugPrinter) {
+        if let Some(description) = self.description_ptr() {
+            printer.write_heap_item_with_context(self.cast(), &description.to_string())
+        } else {
+            printer.write_heap_item_default(self.cast())
+        }
+    }
+}
+
+impl hash::Hash for SymbolValue {
+    #[inline]
+    fn hash<H: hash::Hasher>(&self, state: &mut H) {
+        self.hash_code.hash(state)
+    }
+}
+
+impl hash::Hash for HeapPtr<SymbolValue> {
+    #[inline]
+    fn hash<H: hash::Hasher>(&self, state: &mut H) {
+        self.hash_code.hash(state)
+    }
+}
+
+impl PartialEq for HeapPtr<SymbolValue> {
+    #[inline]
+    fn eq(&self, other: &Self) -> bool {
+        self.ptr_eq(other)
+    }
+}
+
+impl Eq for HeapPtr<SymbolValue> {}
+
+impl hash::Hash for Handle<SymbolValue> {
+    #[inline]
+    fn hash<H: hash::Hasher>(&self, state: &mut H) {
+        (**self).hash(state)
+    }
+}
+
+impl PartialEq for Handle<SymbolValue> {
+    #[inline]
+    fn eq(&self, other: &Self) -> bool {
+        (**self).eq(&**other)
+    }
+}
+
+impl Eq for Handle<SymbolValue> {}
+
+impl HeapItem for SymbolValue {
+    fn byte_size(_: HeapPtr<Self>) -> usize {
+        size_of::<SymbolValue>()
+    }
+
+    fn visit_pointers(mut symbol_value: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
+        visitor.visit_pointer(&mut symbol_value.descriptor);
+        visitor.visit_pointer_opt(&mut symbol_value.description);
+    }
+}
diff --git a/src/js/runtime/type_utilities.rs b/src/js/runtime/type_utilities.rs
--- a/src/js/runtime/type_utilities.rs
+++ b/src/js/runtime/type_utilities.rs
@@ -2,8 +2,6 @@ use std::cmp::Ordering;
 
 use num_bigint::{BigInt, ToBigInt};
 
-use crate::runtime::array_object::ArrayObject;
-use crate::runtime::intrinsics::regexp_object::RegExpObject;
 use crate::{
     common::{
         math::modulo,
@@ -14,24 +12,25 @@ use crate::{
     },
     must_a,
     runtime::{
-        Context, HeapItemKind,
+        BigIntValue, Context, HeapItemKind,
         abstract_operations::{call_object, get, get_method},
         alloc_error::AllocResult,
+        array_object::ArrayObject,
         bytecode::function::ClosureObject,
         error::{range_error, syntax_error, type_error},
         eval_result::EvalResult,
         gc::{Handle, HeapPtr},
         intrinsics::{
             bigint_object::BigIntObject, boolean_object::BooleanObject,
-            number_object::NumberObject, symbol_object::SymbolObject,
+            number_object::NumberObject, regexp_object::RegExpObject, symbol_object::SymbolObject,
         },
         object_value::ObjectValue,
         property_key::PropertyKey,
         proxy_object::ProxyObject,
         string_object::StringObject,
         string_parsing::{StringLexer, parse_string_to_bigint, parse_string_to_number},
         string_value::StringValue,
-        value::{BOOL_TAG, BigIntValue, NULL_TAG, POINTER_TAG, SMI_TAG, UNDEFINED_TAG, Value},
+        value::{BOOL_TAG, NULL_TAG, POINTER_TAG, SMI_TAG, UNDEFINED_TAG, Value},
     },
 };
 
@@ -122,8 +121,8 @@ pub fn to_boolean(value: Value) -> bool {
 
     if value.is_pointer() {
         match value.as_pointer().descriptor().kind() {
-            HeapItemKind::String => !value.as_string().is_empty(),
-            HeapItemKind::BigInt => value.as_bigint().bigint().ne(&BigInt::default()),
+            HeapItemKind::StringValue => !value.as_string().is_empty(),
+            HeapItemKind::BigIntValue => value.as_bigint().bigint().ne(&BigInt::default()),
             // Objects and symbols
             _ => true,
         }
@@ -165,11 +164,11 @@ pub fn to_number(cx: Context, value_handle: Handle<Value>) -> EvalResult<Handle<
         } else {
             match value.as_pointer().descriptor().kind() {
                 // May allocate
-                HeapItemKind::String => {
+                HeapItemKind::StringValue => {
                     Ok(string_to_number(value_handle.as_string())?.to_handle(cx))
                 }
-                HeapItemKind::Symbol => type_error(cx, "symbol cannot be converted to number"),
-                HeapItemKind::BigInt => type_error(cx, "BigInt cannot be converted to number"),
+                HeapItemKind::SymbolValue => type_error(cx, "symbol cannot be converted to number"),
+                HeapItemKind::BigIntValue => type_error(cx, "BigInt cannot be converted to number"),
                 _ => unreachable!(),
             }
         }
@@ -461,8 +460,8 @@ pub fn to_bigint(cx: Context, value: Handle<Value>) -> EvalResult<Handle<BigIntV
 
     if primitive.is_pointer() {
         match primitive.as_pointer().descriptor().kind() {
-            HeapItemKind::BigInt => return Ok(primitive_handle.as_bigint()),
-            HeapItemKind::String => {
+            HeapItemKind::BigIntValue => return Ok(primitive_handle.as_bigint()),
+            HeapItemKind::StringValue => {
                 // May allocate
                 return if let Some(bigint) = string_to_bigint(primitive_handle.as_string())? {
                     Ok(BigIntValue::new(cx, bigint)?)
@@ -526,11 +525,11 @@ pub fn to_string(mut cx: Context, value_handle: Handle<Value>) -> EvalResult<Han
             to_string(cx, primitive_value)
         } else {
             match value.as_pointer().descriptor().kind() {
-                HeapItemKind::BigInt => {
+                HeapItemKind::BigIntValue => {
                     let bigint_string = value.as_bigint().bigint().to_string();
                     Ok(cx.alloc_string(&bigint_string)?)
                 }
-                HeapItemKind::Symbol => type_error(cx, "symbol cannot be converted to string"),
+                HeapItemKind::SymbolValue => type_error(cx, "symbol cannot be converted to string"),
                 _ => unreachable!(),
             }
         }
@@ -566,13 +565,13 @@ pub fn to_object(cx: Context, value_handle: Handle<Value>) -> EvalResult<Handle<
             Ok(value_handle.as_object())
         } else {
             match value.as_pointer().descriptor().kind() {
-                HeapItemKind::String => {
+                HeapItemKind::StringValue => {
                     Ok(StringObject::new_from_value(cx, value_handle.as_string())?.as_object())
                 }
-                HeapItemKind::Symbol => {
+                HeapItemKind::SymbolValue => {
                     Ok(SymbolObject::new_from_value(cx, value_handle.as_symbol())?.as_object())
                 }
-                HeapItemKind::BigInt => {
+                HeapItemKind::BigIntValue => {
                     Ok(BigIntObject::new_from_value(cx, value_handle.as_bigint())?.as_object())
                 }
                 _ => unreachable!(),
@@ -867,11 +866,11 @@ fn same_value_non_numeric(v1_handle: Handle<Value>, v2_handle: Handle<Value>) ->
         let kind1 = v1.as_pointer().descriptor().kind();
         if kind1 == v2.as_pointer().descriptor().kind() {
             match kind1 {
-                HeapItemKind::String => {
+                HeapItemKind::StringValue => {
                     // May allocate
                     return v1_handle.as_string().equals(&v2_handle.as_string());
                 }
-                HeapItemKind::BigInt => {
+                HeapItemKind::BigIntValue => {
                     return Ok(v1.as_bigint().bigint().eq(&v2.as_bigint().bigint()));
                 }
                 _ => {}
@@ -897,7 +896,7 @@ pub fn same_value_non_numeric_non_allocating(v1: Value, v2: Value) -> bool {
         let kind1 = v1.as_pointer().descriptor().kind();
         if kind1 == v2.as_pointer().descriptor().kind() {
             match kind1 {
-                HeapItemKind::String => {
+                HeapItemKind::StringValue => {
                     // Must be flat strings to be non allocating
                     let v1_string = v1.as_string();
                     let v2_string = v2.as_string();
@@ -908,7 +907,7 @@ pub fn same_value_non_numeric_non_allocating(v1: Value, v2: Value) -> bool {
                     // Cannot allocate
                     return v1_string.as_flat() == v2_string.as_flat();
                 }
-                HeapItemKind::BigInt => {
+                HeapItemKind::BigIntValue => {
                     return v1.as_bigint().bigint().eq(&v2.as_bigint().bigint());
                 }
                 _ => {}
@@ -967,15 +966,15 @@ pub fn is_less_than(
         let x_kind = x.as_pointer().descriptor().kind();
         let y_kind = y.as_pointer().descriptor().kind();
 
-        if x_kind == HeapItemKind::String {
-            if y_kind == HeapItemKind::String {
+        if x_kind == HeapItemKind::StringValue {
+            if y_kind == HeapItemKind::StringValue {
                 // May allocate
                 return Ok(x_handle
                     .as_string()
                     .compare(&y_handle.as_string())?
                     .is_lt()
                     .into());
-            } else if y_kind == HeapItemKind::BigInt {
+            } else if y_kind == HeapItemKind::BigIntValue {
                 // May allocate
                 let x_bigint = string_to_bigint(x_handle.as_string())?;
 
@@ -987,7 +986,7 @@ pub fn is_less_than(
             }
         }
 
-        if x_kind == HeapItemKind::BigInt && y_kind == HeapItemKind::String {
+        if x_kind == HeapItemKind::BigIntValue && y_kind == HeapItemKind::StringValue {
             // May allocate
             let y_bigint = string_to_bigint(y_handle.as_string())?;
 
@@ -1109,12 +1108,12 @@ pub fn is_loosely_equal(
 
         return if v2.is_pointer() {
             match v2.as_pointer().descriptor().kind() {
-                HeapItemKind::String => {
+                HeapItemKind::StringValue => {
                     // May allocate
                     let number_v2 = string_to_number(v2_handle.as_string())?;
                     Ok(v1_handle.as_number() == number_v2.as_number())
                 }
-                HeapItemKind::BigInt => {
+                HeapItemKind::BigIntValue => {
                     if v1.is_nan() || v1.is_infinity() {
                         return Ok(false);
                     }
@@ -1132,7 +1131,7 @@ pub fn is_loosely_equal(
 
                     Ok(v1_bigint == v2_bigint)
                 }
-                HeapItemKind::Symbol => Ok(false),
+                HeapItemKind::SymbolValue => Ok(false),
                 // Otherwise must be an object
                 _ => {
                     let primitive_v2 = to_primitive(cx, v2_handle, ToPrimitivePreferredType::None)?;
@@ -1163,11 +1162,11 @@ pub fn is_loosely_equal(
             if kind1 == kind2 {
                 return match kind1 {
                     // Only strings and BigInts may have the same value but different bit patterns
-                    HeapItemKind::String => {
+                    HeapItemKind::StringValue => {
                         // May allocate
                         Ok(v1_handle.as_string().equals(&v2_handle.as_string())?)
                     }
-                    HeapItemKind::BigInt => {
+                    HeapItemKind::BigIntValue => {
                         Ok(v1.as_bigint().bigint().eq(&v2.as_bigint().bigint()))
                     }
                     _ => Ok(false),
@@ -1204,12 +1203,12 @@ pub fn is_loosely_equal(
         return if tag1 == POINTER_TAG {
             let kind = v1.as_pointer().descriptor().kind();
             match kind {
-                HeapItemKind::String => {
+                HeapItemKind::StringValue => {
                     // May allocate
                     let v1_number = string_to_number(v1_handle.as_string())?;
                     Ok(v1_number.as_number() == v2_handle.as_number())
                 }
-                HeapItemKind::BigInt => {
+                HeapItemKind::BigIntValue => {
                     if v2.is_nan() || v2.is_infinity() {
                         return Ok(false);
                     }
@@ -1227,7 +1226,7 @@ pub fn is_loosely_equal(
 
                     Ok(v1_bigint == v2_bigint)
                 }
-                HeapItemKind::Symbol => Ok(false),
+                HeapItemKind::SymbolValue => Ok(false),
                 // Otherwise must be an object
                 _ => {
                     let v1_primitive = to_primitive(cx, v1_handle, ToPrimitivePreferredType::None)?;
@@ -1245,7 +1244,7 @@ pub fn is_loosely_equal(
 
         // Strings are implicitly converted to BigInts
         match (kind1, kind2) {
-            (HeapItemKind::String, HeapItemKind::BigInt) => {
+            (HeapItemKind::StringValue, HeapItemKind::BigIntValue) => {
                 // May allocate
                 let v1_bigint = string_to_bigint(v1_handle.as_string())?;
                 return if let Some(v1_bigint) = v1_bigint {
@@ -1254,7 +1253,7 @@ pub fn is_loosely_equal(
                     Ok(false)
                 };
             }
-            (HeapItemKind::BigInt, HeapItemKind::String) => {
+            (HeapItemKind::BigIntValue, HeapItemKind::StringValue) => {
                 // May allocate
                 let v2_bigint = string_to_bigint(v2_handle.as_string())?;
                 return if let Some(v2_bigint) = v2_bigint {
diff --git a/src/js/runtime/value.rs b/src/js/runtime/value.rs
--- a/src/js/runtime/value.rs
+++ b/src/js/runtime/value.rs
@@ -2,30 +2,23 @@ use std::{
     hash,
     mem::{MaybeUninit, size_of},
     num::NonZeroU64,
-    ptr::copy_nonoverlapping,
 };
 
-use num_bigint::{BigInt, Sign};
-use rand::Rng;
-
 use crate::{
     common::numeric::Numeric,
-    const_assert, field_offset,
+    const_assert,
     runtime::{
-        HeapItemKind,
+        BigIntValue, HeapItemKind, SymbolValue,
         alloc_error::AllocResult,
-        context::Context,
         debug_print::{DebugPrint, DebugPrinter},
         gc::{
-            AnyHeapItem, Handle, HandleContents, HeapItem, HeapPtr, HeapVisitor, ToHandleContents,
+            AnyHeapItem, Handle, HandleContents, HeapPtr, HeapVisitor, ToHandleContents,
             WithHeapItemKind,
         },
-        heap_item_descriptor::HeapItemDescriptor,
         object_value::ObjectValue,
-        string_value::{FlatString, StringValue},
+        string_value::StringValue,
         type_utilities::same_value_zero_non_allocating,
     },
-    set_uninit,
 };
 
 /// Values implemented with NaN boxing on 64-bit IEEE-754 floating point numbers. Inspired by NaN
@@ -556,183 +549,6 @@ impl From<HeapPtr<BigIntValue>> for Value {
     }
 }
 
-#[repr(C)]
-pub struct SymbolValue {
-    descriptor: HeapPtr<HeapItemDescriptor>,
-    description: Option<HeapPtr<FlatString>>,
-    /// Stable hash code for this symbol, since symbol can be moved by GC
-    hash_code: u32,
-    /// Whether this symbol is for a private name
-    is_private: bool,
-}
-
-impl SymbolValue {
-    pub fn new(
-        mut cx: Context,
-        description: Option<Handle<StringValue>>,
-        is_private: bool,
-    ) -> AllocResult<Handle<SymbolValue>> {
-        let description = description.map(|d| d.flatten()).transpose()?;
-        let mut symbol = cx.alloc_uninit::<SymbolValue>()?;
-
-        set_uninit!(symbol.descriptor, cx.descriptors.get(HeapItemKind::Symbol));
-        set_uninit!(symbol.description, description.map(|desc| *desc));
-        set_uninit!(symbol.hash_code, cx.rand.r#gen::<u32>());
-        set_uninit!(symbol.is_private, is_private);
-
-        Ok(symbol.to_handle())
-    }
-
-    pub fn description_ptr(&self) -> Option<HeapPtr<FlatString>> {
-        self.description
-    }
-
-    pub fn description(&self) -> Option<Handle<FlatString>> {
-        self.description.map(|d| d.to_handle())
-    }
-
-    pub fn is_private(&self) -> bool {
-        self.is_private
-    }
-}
-
-impl DebugPrint for HeapPtr<SymbolValue> {
-    fn debug_format(&self, printer: &mut DebugPrinter) {
-        if let Some(description) = self.description_ptr() {
-            printer.write_heap_item_with_context(self.cast(), &description.to_string())
-        } else {
-            printer.write_heap_item_default(self.cast())
-        }
-    }
-}
-
-impl hash::Hash for SymbolValue {
-    #[inline]
-    fn hash<H: hash::Hasher>(&self, state: &mut H) {
-        self.hash_code.hash(state)
-    }
-}
-
-impl hash::Hash for HeapPtr<SymbolValue> {
-    #[inline]
-    fn hash<H: hash::Hasher>(&self, state: &mut H) {
-        self.hash_code.hash(state)
-    }
-}
-
-impl PartialEq for HeapPtr<SymbolValue> {
-    #[inline]
-    fn eq(&self, other: &Self) -> bool {
-        self.ptr_eq(other)
-    }
-}
-
-impl Eq for HeapPtr<SymbolValue> {}
-
-impl hash::Hash for Handle<SymbolValue> {
-    #[inline]
-    fn hash<H: hash::Hasher>(&self, state: &mut H) {
-        (**self).hash(state)
-    }
-}
-
-impl PartialEq for Handle<SymbolValue> {
-    #[inline]
-    fn eq(&self, other: &Self) -> bool {
-        (**self).eq(&**other)
-    }
-}
-
-impl Eq for Handle<SymbolValue> {}
-
-impl From<Handle<SymbolValue>> for Handle<ObjectValue> {
-    fn from(value: Handle<SymbolValue>) -> Self {
-        value.cast()
-    }
-}
-
-impl HeapItem for SymbolValue {
-    fn byte_size(_: HeapPtr<Self>) -> usize {
-        size_of::<SymbolValue>()
-    }
-
-    fn visit_pointers(mut symbol_value: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
-        visitor.visit_pointer(&mut symbol_value.descriptor);
-        visitor.visit_pointer_opt(&mut symbol_value.description);
-    }
-}
-
-#[repr(C)]
-pub struct BigIntValue {
-    descriptor: HeapPtr<HeapItemDescriptor>,
-    // Number of u32 digits in the BigInt
-    len: usize,
-    // Sign of the BigInt
-    sign: Sign,
-    // Start of the BigInt's array of digits. Variable sized but array has a single item for
-    // alignment.
-    digits: [u32; 1],
-}
-
-impl BigIntValue {
-    const DIGITS_OFFSET: usize = field_offset!(BigIntValue, digits);
-
-    pub fn new(cx: Context, value: BigInt) -> AllocResult<Handle<BigIntValue>> {
-        Ok(Self::new_ptr(cx, value)?.to_handle())
-    }
-
-    pub fn new_ptr(cx: Context, value: BigInt) -> AllocResult<HeapPtr<BigIntValue>> {
-        // Extract sign and digits from BigInt
-        let (sign, digits) = value.to_u32_digits();
-        let len = digits.len();
-
-        let size = Self::calculate_size_in_bytes(len);
-        let mut bigint = cx.alloc_uninit_with_size::<BigIntValue>(size)?;
-
-        // Copy raw parts of BigInt into BigIntValue
-        set_uninit!(bigint.descriptor, cx.descriptors.get(HeapItemKind::BigInt));
-        set_uninit!(bigint.len, digits.len());
-        set_uninit!(bigint.sign, sign);
-
-        unsafe { copy_nonoverlapping(digits.as_ptr(), bigint.digits.as_mut_ptr(), len) };
-
-        Ok(bigint)
-    }
-
-    pub fn calculate_size_in_bytes(num_u32_digits: usize) -> usize {
-        // Calculate size of BigIntValue with inlined digits
-        Self::DIGITS_OFFSET + num_u32_digits * size_of::<u32>()
-    }
-
-    pub fn bigint(&self) -> BigInt {
-        // Recreate BigInt from stored raw parts
-        let slice = unsafe { std::slice::from_raw_parts(self.digits.as_ptr(), self.len) };
-        BigInt::from_slice(self.sign, slice)
-    }
-}
-
-impl DebugPrint for HeapPtr<BigIntValue> {
-    fn debug_format(&self, printer: &mut DebugPrinter) {
-        printer.write_heap_item_with_context(self.cast(), &self.bigint().to_string())
-    }
-}
-
-impl From<Handle<BigIntValue>> for Handle<ObjectValue> {
-    fn from(value: Handle<BigIntValue>) -> Self {
-        value.cast()
-    }
-}
-
-impl HeapItem for BigIntValue {
-    fn byte_size(big_int_value: HeapPtr<Self>) -> usize {
-        BigIntValue::calculate_size_in_bytes(big_int_value.len)
-    }
-
-    fn visit_pointers(mut big_int_value: HeapPtr<Self>, visitor: &mut impl HeapVisitor) {
-        visitor.visit_pointer(&mut big_int_value.descriptor);
-    }
-}
-
 /// Encoding scheme for packing a sequence of raw bytes into a sequence of Values. Each Value is
 /// encoded as the EMPTY_TAG in the top 16-bits and the payload in the low 48-bits.
 pub struct RawBytesEncoding;
@@ -865,19 +681,19 @@ impl hash::Hash for ValueCollectionKey {
 
         if self.0.is_pointer() {
             return match self.0.as_pointer().descriptor().kind() {
-                HeapItemKind::String => {
+                HeapItemKind::StringValue => {
                     // Strings must always be flat before they can be placed into hash tables to
                     // avoid allocating in the hash function.
                     let string = self.0.as_string();
                     debug_assert!(string.is_flat());
 
                     string.as_flat().hash(state)
                 }
-                HeapItemKind::BigInt => self.0.as_bigint().bigint().hash(state),
+                HeapItemKind::BigIntValue => self.0.as_bigint().bigint().hash(state),
                 // Otherwise is an object or symbol. Hash code must represent object/symbol
                 // identity, but objects/symbols can be moved by the GC. So use the stable hash code
                 // stored in the object/symbol.
-                HeapItemKind::Symbol => self.0.as_symbol().hash(state),
+                HeapItemKind::SymbolValue => self.0.as_symbol().hash(state),
                 _ => self.0.as_object().hash_code().hash(state),
             };
         }
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
