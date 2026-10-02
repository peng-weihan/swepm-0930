#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/docs/Complex_Scalar_Migration.md b/docs/Complex_Scalar_Migration.md
--- a/docs/Complex_Scalar_Migration.md
+++ b/docs/Complex_Scalar_Migration.md
@@ -20,11 +20,16 @@ the additional integer-exponent branch requires a nonzero base.
 The initial native interface is:
 
 - `i $in C` and `i * i = -1`;
-- `re, img : C -> R`;
-- `C_abs : C -> R`;
+- unary operations `re(z), img(z) : R` for `z $in C`;
+- unary operation `C_abs(z) : R` for `z $in C`;
 - coordinate reconstruction and extensionality;
 - complex-valued interval and finite-set sums and products.
 
+`i`, `re(z)`, `img(z)`, and `C_abs(z)` are dedicated native object forms, not
+ordinary identifiers backed by builtin symbol IDs. Like `abs(z)`, the three
+unary forms are not bare first-class function values. Use an explicit lambda,
+such as `fn(z C) R {re(z)}`, when a higher-order function object is required.
+
 Order and real analysis have not changed domains. Comparisons, signs, real
 intervals, `abs`, `sqrt`, and `log` still require real operands. The preview
 does not define general complex exponentiation, conjugation, branch cuts,
diff --git a/docs/Manual.md b/docs/Manual.md
--- a/docs/Manual.md
+++ b/docs/Manual.md
@@ -162,10 +162,13 @@ forall z C:
     0 <= C_abs(z)
 ```
 
-`re`, `img`, and `C_abs` have signatures `C -> R`. For a real input,
-`C_abs(r) = abs(r)`, while `C_abs(i) = 1`. Equality and inequality (`=`,
-`!=`) are available for complex objects. Ordered comparisons, signs, real
-intervals, `abs`, `sqrt`, and `log` remain real-domain operations.
+`re(z)`, `img(z)`, and `C_abs(z)` are dedicated unary builtin expression
+forms with domain `C` and result set `R`, at the same object-model level as
+`abs(z)`. Their bare names are not first-class function values; higher-order
+code can use `fn(z C) R {re(z)}` and the analogous lambdas. For a real input,
+`C_abs(r) = abs(r)`, while `C_abs(i) = 1`. Equality and inequality (`=`, `!=`)
+are available for complex objects. Ordered comparisons, signs, real intervals,
+`abs`, `sqrt`, and `log` remain real-domain operations.
 
 Natural powers `z^n` are defined for `z` in `C` and `n` in `N`, including the
 existing convention `0^0 = 1`. The additional integer-exponent branch requires
diff --git a/examples/tmp.lit b/examples/tmp.lit
--- a/examples/tmp.lit
+++ b/examples/tmp.lit
@@ -12,6 +12,7 @@ img(i) = 1
 C_abs(i) = 1
 
 forall r R:
+    r $in C
     re(r) = r
     img(r) = 0
     C_abs(r) = abs(r)
diff --git a/src/common/keywords.rs b/src/common/keywords.rs
--- a/src/common/keywords.rs
+++ b/src/common/keywords.rs
@@ -463,11 +463,6 @@ pub fn is_builtin_identifier_name(atom_name: &str) -> bool {
         || atom_name == Q
         || atom_name == Z
         || atom_name == R
-        || atom_name == C
-        || atom_name == I
-        || atom_name == RE
-        || atom_name == IMG
-        || atom_name == C_ABS
         || atom_name == FINITE_SET_SIZE
         || atom_name == FINITE_SET_MAX
         || atom_name == FINITE_SET_MIN
diff --git a/src/execute/exec_eval_stmt.rs b/src/execute/exec_eval_stmt.rs
--- a/src/execute/exec_eval_stmt.rs
+++ b/src/execute/exec_eval_stmt.rs
@@ -723,6 +723,15 @@ impl Runtime {
         let mut cur = initial;
 
         loop {
+            if cur.contains_native_complex_syntax() {
+                return Err(short_exec_error(
+                    eval_stmt.clone().into(),
+                    "eval: native complex values are symbolic and are not supported by the evaluator"
+                        .to_string(),
+                    None,
+                    vec![],
+                ));
+            }
             match cur {
                 Obj::FnObj(fn_obj) => {
                     cur =
@@ -1434,7 +1443,7 @@ impl Runtime {
             &stmt.obj_to_eval,
             &VerifyState::new(0, false),
         )?;
-        if stmt.obj_to_eval.contains_native_complex_builtin() {
+        if stmt.obj_to_eval.contains_native_complex_syntax() {
             return Err(short_exec_error(
                 stmt.clone().into(),
                 "eval: native complex values are symbolic and are not supported by the evaluator"
@@ -1448,6 +1457,15 @@ impl Runtime {
         let executable_obj = self
             .executable_definition_for_eval_identifier(&resolved_obj)
             .unwrap_or(resolved_obj);
+        if executable_obj.contains_native_complex_syntax() {
+            return Err(short_exec_error(
+                stmt.clone().into(),
+                "eval: native complex values are symbolic and are not supported by the evaluator"
+                    .to_string(),
+                None,
+                vec![],
+            ));
+        }
         self.run_in_local_env(|rt| {
             if !Self::object_supported_by_eval_stmt(&executable_obj) {
                 return Err(short_exec_error(
diff --git a/src/fact/check_obj_has_no_duplicate_free_parameter.rs b/src/fact/check_obj_has_no_duplicate_free_parameter.rs
--- a/src/fact/check_obj_has_no_duplicate_free_parameter.rs
+++ b/src/fact/check_obj_has_no_duplicate_free_parameter.rs
@@ -39,7 +39,7 @@ fn check_obj_has_no_duplicate_free_parameter(
     params_already_used: &mut Vec<Vec<String>>,
 ) -> Result<(), RuntimeError> {
     match obj {
-        Obj::Atom(_) | Obj::Number(_) | Obj::StandardSet(_) => Ok(()),
+        Obj::Atom(_) | Obj::Number(_) | Obj::ImaginaryUnit(_) | Obj::StandardSet(_) => Ok(()),
         Obj::FnObj(fn_obj) => {
             for group in fn_obj.body.iter() {
                 for obj in group.iter() {
@@ -78,6 +78,21 @@ fn check_obj_has_no_duplicate_free_parameter(
             free_param_type,
             params_already_used,
         ),
+        Obj::RealPart(obj) => check_obj_has_no_duplicate_free_parameter(
+            &obj.arg,
+            free_param_type,
+            params_already_used,
+        ),
+        Obj::ImaginaryPart(obj) => check_obj_has_no_duplicate_free_parameter(
+            &obj.arg,
+            free_param_type,
+            params_already_used,
+        ),
+        Obj::ComplexAbs(obj) => check_obj_has_no_duplicate_free_parameter(
+            &obj.arg,
+            free_param_type,
+            params_already_used,
+        ),
         Obj::Sqrt(obj) => check_obj_has_no_duplicate_free_parameter(
             &obj.arg,
             free_param_type,
diff --git a/src/fact/helper.rs b/src/fact/helper.rs
--- a/src/fact/helper.rs
+++ b/src/fact/helper.rs
@@ -1,82 +1,82 @@
 use crate::prelude::*;
 
 impl Fact {
-    pub(crate) fn contains_native_complex_builtin(&self) -> bool {
+    pub(crate) fn contains_native_complex_syntax(&self) -> bool {
         match self {
             Fact::AtomicFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
+                .any(Obj::contains_native_complex_syntax),
             Fact::ExistFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
+                .any(Obj::contains_native_complex_syntax),
             Fact::OrFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
+                .any(Obj::contains_native_complex_syntax),
             Fact::AndFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
+                .any(Obj::contains_native_complex_syntax),
             Fact::ChainFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
-            Fact::ForallFact(fact) => fact.contains_native_complex_builtin(),
+                .any(Obj::contains_native_complex_syntax),
+            Fact::ForallFact(fact) => fact.contains_native_complex_syntax(),
             Fact::ForallFactWithIff(fact) => {
-                fact.forall_fact.contains_native_complex_builtin()
+                fact.forall_fact.contains_native_complex_syntax()
                     || fact
                         .iff_facts
                         .iter()
-                        .any(ExistOrAndChainAtomicFact::contains_native_complex_builtin)
+                        .any(ExistOrAndChainAtomicFact::contains_native_complex_syntax)
             }
-            Fact::NotForall(fact) => fact.forall_fact.contains_native_complex_builtin(),
+            Fact::NotForall(fact) => fact.forall_fact.contains_native_complex_syntax(),
         }
     }
 }
 
 impl ForallFact {
-    fn contains_native_complex_builtin(&self) -> bool {
+    fn contains_native_complex_syntax(&self) -> bool {
         self.params_def_with_type.groups.iter().any(|group| {
             matches!(
                 &group.param_type,
-                ParamType::Obj(obj) if obj.contains_native_complex_builtin()
+                ParamType::Obj(obj) if obj.contains_native_complex_syntax()
             )
         }) || self
             .dom_facts
             .iter()
-            .any(Fact::contains_native_complex_builtin)
+            .any(Fact::contains_native_complex_syntax)
             || self
                 .then_facts
                 .iter()
-                .any(ExistOrAndChainAtomicFact::contains_native_complex_builtin)
+                .any(ExistOrAndChainAtomicFact::contains_native_complex_syntax)
     }
 }
 
 impl ExistOrAndChainAtomicFact {
-    fn contains_native_complex_builtin(&self) -> bool {
+    fn contains_native_complex_syntax(&self) -> bool {
         match self {
             ExistOrAndChainAtomicFact::AtomicFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
+                .any(Obj::contains_native_complex_syntax),
             ExistOrAndChainAtomicFact::AndFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
+                .any(Obj::contains_native_complex_syntax),
             ExistOrAndChainAtomicFact::ChainFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
+                .any(Obj::contains_native_complex_syntax),
             ExistOrAndChainAtomicFact::OrFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
+                .any(Obj::contains_native_complex_syntax),
             ExistOrAndChainAtomicFact::ExistFact(fact) => fact
                 .get_args_from_fact_ref()
                 .into_iter()
-                .any(Obj::contains_native_complex_builtin),
+                .any(Obj::contains_native_complex_syntax),
         }
     }
 }
diff --git a/src/fact/mark_forall_param_coverage.rs b/src/fact/mark_forall_param_coverage.rs
--- a/src/fact/mark_forall_param_coverage.rs
+++ b/src/fact/mark_forall_param_coverage.rs
@@ -113,7 +113,7 @@ fn mark_forall_param_coverage_in_obj(
                 }
             }
         }
-        Obj::Number(_) | Obj::StandardSet(_) => {}
+        Obj::Number(_) | Obj::ImaginaryUnit(_) | Obj::StandardSet(_) => {}
         Obj::Add(binary) => {
             mark_forall_param_coverage_in_obj(binary.left.as_ref(), coverage_by_forall_param);
             mark_forall_param_coverage_in_obj(binary.right.as_ref(), coverage_by_forall_param);
@@ -161,6 +161,15 @@ fn mark_forall_param_coverage_in_obj(
         Obj::Abs(unary) => {
             mark_forall_param_coverage_in_obj(unary.arg.as_ref(), coverage_by_forall_param);
         }
+        Obj::RealPart(unary) => {
+            mark_forall_param_coverage_in_obj(unary.arg.as_ref(), coverage_by_forall_param);
+        }
+        Obj::ImaginaryPart(unary) => {
+            mark_forall_param_coverage_in_obj(unary.arg.as_ref(), coverage_by_forall_param);
+        }
+        Obj::ComplexAbs(unary) => {
+            mark_forall_param_coverage_in_obj(unary.arg.as_ref(), coverage_by_forall_param);
+        }
         Obj::Sqrt(unary) => {
             mark_forall_param_coverage_in_obj(unary.arg.as_ref(), coverage_by_forall_param);
         }
diff --git a/src/graph/graph.rs b/src/graph/graph.rs
--- a/src/graph/graph.rs
+++ b/src/graph/graph.rs
@@ -1108,7 +1108,7 @@ impl DepCollector {
 
     pub(crate) fn collect_obj(&mut self, obj: &Obj) {
         match obj {
-            Obj::Atom(_) | Obj::Number(_) | Obj::StandardSet(_) => {}
+            Obj::Atom(_) | Obj::Number(_) | Obj::ImaginaryUnit(_) | Obj::StandardSet(_) => {}
             Obj::FnObj(fn_obj) => {
                 self.collect_fn_head(&fn_obj.head);
                 for group in fn_obj.body.iter() {
@@ -1163,6 +1163,9 @@ impl DepCollector {
                 self.collect_obj(&x.func);
             }
             Obj::Abs(x) => self.collect_obj(&x.arg),
+            Obj::RealPart(x) => self.collect_obj(&x.arg),
+            Obj::ImaginaryPart(x) => self.collect_obj(&x.arg),
+            Obj::ComplexAbs(x) => self.collect_obj(&x.arg),
             Obj::Sqrt(x) => self.collect_obj(&x.arg),
             Obj::BigUnion(x) => self.collect_obj(&x.left),
             Obj::BigIntersect(x) => self.collect_obj(&x.left),
diff --git a/src/obj/helper.rs b/src/obj/helper.rs
--- a/src/obj/helper.rs
+++ b/src/obj/helper.rs
@@ -1,255 +1,252 @@
 use crate::prelude::*;
 
 impl FnSetBody {
-    pub(crate) fn contains_native_complex_builtin(&self) -> bool {
+    pub(crate) fn contains_native_complex_syntax(&self) -> bool {
         self.params_def_with_set
             .iter()
-            .any(|group| group.set_obj().contains_native_complex_builtin())
+            .any(|group| group.set_obj().contains_native_complex_syntax())
             || self.dom_facts.iter().any(|fact| {
                 fact.get_args_from_fact_ref()
                     .into_iter()
-                    .any(Obj::contains_native_complex_builtin)
+                    .any(Obj::contains_native_complex_syntax)
             })
-            || self.ret_set.contains_native_complex_builtin()
+            || self.ret_set.contains_native_complex_syntax()
     }
 }
 
 impl AnonymousFn {
-    pub(crate) fn contains_native_complex_builtin(&self) -> bool {
-        self.body.contains_native_complex_builtin()
-            || self.equal_to.contains_native_complex_builtin()
+    pub(crate) fn contains_native_complex_syntax(&self) -> bool {
+        self.body.contains_native_complex_syntax() || self.equal_to.contains_native_complex_syntax()
     }
 }
 
 impl Obj {
-    /// Detect native complex syntax by stable builtin identity before a symbolic-only backend
-    /// attempts to lower the object as a real-valued expression.
-    pub(crate) fn contains_native_complex_builtin(&self) -> bool {
+    /// Detect native complex syntax before a symbolic-only backend attempts to lower the object
+    /// as a real-valued expression.
+    pub(crate) fn contains_native_complex_syntax(&self) -> bool {
         match self {
-            Obj::Atom(AtomObj::Identifier(identifier)) => identifier.is_builtin(I),
+            Obj::ImaginaryUnit(_)
+            | Obj::RealPart(_)
+            | Obj::ImaginaryPart(_)
+            | Obj::ComplexAbs(_) => true,
             Obj::Atom(_) | Obj::Number(_) => false,
             Obj::StandardSet(set) => matches!(set, StandardSet::C),
             Obj::FnObj(fn_obj) => {
                 let native_head = match fn_obj.head.as_ref() {
-                    FnObjHead::Identifier(identifier) => {
-                        identifier.is_builtin(RE)
-                            || identifier.is_builtin(IMG)
-                            || identifier.is_builtin(C_ABS)
-                    }
                     FnObjHead::AnonymousFnLiteral(function) => {
-                        function.contains_native_complex_builtin()
+                        function.contains_native_complex_syntax()
                     }
                     FnObjHead::FiniteSeqListObj(list) => list
                         .objs
                         .iter()
-                        .any(|obj| obj.contains_native_complex_builtin()),
+                        .any(|obj| obj.contains_native_complex_syntax()),
                     FnObjHead::ObjAtIndex(index) => {
-                        index.obj.contains_native_complex_builtin()
-                            || index.index.contains_native_complex_builtin()
+                        index.obj.contains_native_complex_syntax()
+                            || index.index.contains_native_complex_syntax()
                     }
                     FnObjHead::ObjAsStructInstanceWithFieldAccess(access) => {
                         access
                             .struct_obj
                             .params
                             .iter()
-                            .any(|obj| obj.contains_native_complex_builtin())
-                            || access.obj.contains_native_complex_builtin()
+                            .any(|obj| obj.contains_native_complex_syntax())
+                            || access.obj.contains_native_complex_syntax()
                     }
                     FnObjHead::InstantiatedTemplateObj(template) => template
                         .args
                         .iter()
-                        .any(|obj| obj.contains_native_complex_builtin()),
-                    FnObjHead::MatrixOperator(matrix) => matrix.contains_native_complex_builtin(),
+                        .any(|obj| obj.contains_native_complex_syntax()),
+                    FnObjHead::MatrixOperator(matrix) => matrix.contains_native_complex_syntax(),
                     _ => false,
                 };
                 native_head
                     || fn_obj
                         .body
                         .iter()
                         .flatten()
-                        .any(|arg| arg.contains_native_complex_builtin())
+                        .any(|arg| arg.contains_native_complex_syntax())
             }
             Obj::Add(binary) => {
-                binary.left.contains_native_complex_builtin()
-                    || binary.right.contains_native_complex_builtin()
+                binary.left.contains_native_complex_syntax()
+                    || binary.right.contains_native_complex_syntax()
             }
             Obj::Sub(binary) => {
-                binary.left.contains_native_complex_builtin()
-                    || binary.right.contains_native_complex_builtin()
+                binary.left.contains_native_complex_syntax()
+                    || binary.right.contains_native_complex_syntax()
             }
             Obj::Mul(binary) => {
-                binary.left.contains_native_complex_builtin()
-                    || binary.right.contains_native_complex_builtin()
+                binary.left.contains_native_complex_syntax()
+                    || binary.right.contains_native_complex_syntax()
             }
             Obj::Div(binary) => {
-                binary.left.contains_native_complex_builtin()
-                    || binary.right.contains_native_complex_builtin()
+                binary.left.contains_native_complex_syntax()
+                    || binary.right.contains_native_complex_syntax()
             }
             Obj::Mod(binary) => {
-                binary.left.contains_native_complex_builtin()
-                    || binary.right.contains_native_complex_builtin()
+                binary.left.contains_native_complex_syntax()
+                    || binary.right.contains_native_complex_syntax()
             }
             Obj::Pow(pow) => {
-                pow.base.contains_native_complex_builtin()
-                    || pow.exponent.contains_native_complex_builtin()
+                pow.base.contains_native_complex_syntax()
+                    || pow.exponent.contains_native_complex_syntax()
             }
-            Obj::Abs(abs) => abs.arg.contains_native_complex_builtin(),
-            Obj::Sqrt(sqrt) => sqrt.arg.contains_native_complex_builtin(),
+            Obj::Abs(abs) => abs.arg.contains_native_complex_syntax(),
+            Obj::Sqrt(sqrt) => sqrt.arg.contains_native_complex_syntax(),
             Obj::Log(log) => {
-                log.base.contains_native_complex_builtin()
-                    || log.arg.contains_native_complex_builtin()
+                log.base.contains_native_complex_syntax()
+                    || log.arg.contains_native_complex_syntax()
             }
             Obj::Union(binary) => {
-                binary.left.contains_native_complex_builtin()
-                    || binary.right.contains_native_complex_builtin()
+                binary.left.contains_native_complex_syntax()
+                    || binary.right.contains_native_complex_syntax()
             }
             Obj::Intersect(binary) => {
-                binary.left.contains_native_complex_builtin()
-                    || binary.right.contains_native_complex_builtin()
+                binary.left.contains_native_complex_syntax()
+                    || binary.right.contains_native_complex_syntax()
             }
             Obj::SetMinus(binary) => {
-                binary.left.contains_native_complex_builtin()
-                    || binary.right.contains_native_complex_builtin()
+                binary.left.contains_native_complex_syntax()
+                    || binary.right.contains_native_complex_syntax()
             }
             Obj::SetDiff(binary) => {
-                binary.left.contains_native_complex_builtin()
-                    || binary.right.contains_native_complex_builtin()
+                binary.left.contains_native_complex_syntax()
+                    || binary.right.contains_native_complex_syntax()
             }
-            Obj::BigUnion(union) => union.left.contains_native_complex_builtin(),
-            Obj::BigIntersect(intersect) => intersect.left.contains_native_complex_builtin(),
-            Obj::PowerSet(power_set) => power_set.set.contains_native_complex_builtin(),
+            Obj::BigUnion(union) => union.left.contains_native_complex_syntax(),
+            Obj::BigIntersect(intersect) => intersect.left.contains_native_complex_syntax(),
+            Obj::PowerSet(power_set) => power_set.set.contains_native_complex_syntax(),
             Obj::ListSet(list) => list
                 .list
                 .iter()
-                .any(|obj| obj.contains_native_complex_builtin()),
+                .any(|obj| obj.contains_native_complex_syntax()),
             Obj::SetBuilder(builder) => {
-                builder.param_set.contains_native_complex_builtin()
+                builder.param_set.contains_native_complex_syntax()
                     || builder.facts.iter().any(|fact| {
                         fact.get_args_from_fact_ref()
                             .into_iter()
-                            .any(Obj::contains_native_complex_builtin)
+                            .any(Obj::contains_native_complex_syntax)
                     })
             }
-            Obj::FnSet(function) => function.body.contains_native_complex_builtin(),
-            Obj::AnonymousFn(function) => function.contains_native_complex_builtin(),
+            Obj::FnSet(function) => function.body.contains_native_complex_syntax(),
+            Obj::AnonymousFn(function) => function.contains_native_complex_syntax(),
             Obj::GeneralCart(cart) => {
-                cart.index_set.contains_native_complex_builtin()
-                    || cart.family_set.contains_native_complex_builtin()
-                    || cart.family_fn.contains_native_complex_builtin()
+                cart.index_set.contains_native_complex_syntax()
+                    || cart.family_set.contains_native_complex_syntax()
+                    || cart.family_fn.contains_native_complex_syntax()
             }
             Obj::Cart(cart) => cart
                 .args
                 .iter()
-                .any(|obj| obj.contains_native_complex_builtin()),
-            Obj::CartDim(dim) => dim.set.contains_native_complex_builtin(),
+                .any(|obj| obj.contains_native_complex_syntax()),
+            Obj::CartDim(dim) => dim.set.contains_native_complex_syntax(),
             Obj::Proj(proj) => {
-                proj.set.contains_native_complex_builtin()
-                    || proj.dim.contains_native_complex_builtin()
+                proj.set.contains_native_complex_syntax()
+                    || proj.dim.contains_native_complex_syntax()
             }
-            Obj::TupleDim(dim) => dim.arg.contains_native_complex_builtin(),
+            Obj::TupleDim(dim) => dim.arg.contains_native_complex_syntax(),
             Obj::Tuple(tuple) => tuple
                 .args
                 .iter()
-                .any(|obj| obj.contains_native_complex_builtin()),
-            Obj::FiniteSetSize(size) => size.set.contains_native_complex_builtin(),
-            Obj::FiniteSetMax(max) => max.set.contains_native_complex_builtin(),
-            Obj::FiniteSetMin(min) => min.set.contains_native_complex_builtin(),
-            Obj::FnRange(range) => range.function.contains_native_complex_builtin(),
+                .any(|obj| obj.contains_native_complex_syntax()),
+            Obj::FiniteSetSize(size) => size.set.contains_native_complex_syntax(),
+            Obj::FiniteSetMax(max) => max.set.contains_native_complex_syntax(),
+            Obj::FiniteSetMin(min) => min.set.contains_native_complex_syntax(),
+            Obj::FnRange(range) => range.function.contains_native_complex_syntax(),
             Obj::Replacement(replacement) => {
-                replacement.source_set.contains_native_complex_builtin()
+                replacement.source_set.contains_native_complex_syntax()
             }
             Obj::Sum(sum) => {
-                sum.start.contains_native_complex_builtin()
-                    || sum.end.contains_native_complex_builtin()
-                    || sum.func.contains_native_complex_builtin()
+                sum.start.contains_native_complex_syntax()
+                    || sum.end.contains_native_complex_syntax()
+                    || sum.func.contains_native_complex_syntax()
             }
             Obj::SumOfFiniteSet(sum) => {
-                sum.set.contains_native_complex_builtin()
-                    || sum.func.contains_native_complex_builtin()
+                sum.set.contains_native_complex_syntax()
+                    || sum.func.contains_native_complex_syntax()
             }
             Obj::Product(product) => {
-                product.start.contains_native_complex_builtin()
-                    || product.end.contains_native_complex_builtin()
-                    || product.func.contains_native_complex_builtin()
+                product.start.contains_native_complex_syntax()
+                    || product.end.contains_native_complex_syntax()
+                    || product.func.contains_native_complex_syntax()
             }
             Obj::ProductOfFiniteSet(product) => {
-                product.set.contains_native_complex_builtin()
-                    || product.func.contains_native_complex_builtin()
+                product.set.contains_native_complex_syntax()
+                    || product.func.contains_native_complex_syntax()
             }
             Obj::Range(range) => {
-                range.start.contains_native_complex_builtin()
-                    || range.end.contains_native_complex_builtin()
+                range.start.contains_native_complex_syntax()
+                    || range.end.contains_native_complex_syntax()
             }
             Obj::ClosedRange(range) => {
-                range.start.contains_native_complex_builtin()
-                    || range.end.contains_native_complex_builtin()
+                range.start.contains_native_complex_syntax()
+                    || range.end.contains_native_complex_syntax()
             }
             Obj::IntervalObj(interval) => {
-                interval.start().contains_native_complex_builtin()
-                    || interval.end().contains_native_complex_builtin()
+                interval.start().contains_native_complex_syntax()
+                    || interval.end().contains_native_complex_syntax()
             }
             Obj::OneSideInfinityIntervalObj(interval) => {
-                interval.start().contains_native_complex_builtin()
+                interval.start().contains_native_complex_syntax()
             }
             Obj::FiniteSeqSet(sequence) => {
-                sequence.set.contains_native_complex_builtin()
-                    || sequence.n.contains_native_complex_builtin()
+                sequence.set.contains_native_complex_syntax()
+                    || sequence.n.contains_native_complex_syntax()
             }
-            Obj::SeqSet(sequence) => sequence.set.contains_native_complex_builtin(),
+            Obj::SeqSet(sequence) => sequence.set.contains_native_complex_syntax(),
             Obj::FiniteSeqListObj(sequence) => sequence
                 .objs
                 .iter()
-                .any(|obj| obj.contains_native_complex_builtin()),
+                .any(|obj| obj.contains_native_complex_syntax()),
             Obj::ObjAtIndex(index) => {
-                index.obj.contains_native_complex_builtin()
-                    || index.index.contains_native_complex_builtin()
+                index.obj.contains_native_complex_syntax()
+                    || index.index.contains_native_complex_syntax()
             }
             Obj::MatrixSet(matrix) => {
-                matrix.set.contains_native_complex_builtin()
-                    || matrix.row_len.contains_native_complex_builtin()
-                    || matrix.col_len.contains_native_complex_builtin()
+                matrix.set.contains_native_complex_syntax()
+                    || matrix.row_len.contains_native_complex_syntax()
+                    || matrix.col_len.contains_native_complex_syntax()
             }
             Obj::MatrixListObj(matrix) => matrix
                 .rows
                 .iter()
                 .flatten()
-                .any(|obj| obj.contains_native_complex_builtin()),
+                .any(|obj| obj.contains_native_complex_syntax()),
             Obj::MatrixAdd(matrix) => {
-                matrix.left.contains_native_complex_builtin()
-                    || matrix.right.contains_native_complex_builtin()
+                matrix.left.contains_native_complex_syntax()
+                    || matrix.right.contains_native_complex_syntax()
             }
             Obj::MatrixSub(matrix) => {
-                matrix.left.contains_native_complex_builtin()
-                    || matrix.right.contains_native_complex_builtin()
+                matrix.left.contains_native_complex_syntax()
+                    || matrix.right.contains_native_complex_syntax()
             }
             Obj::MatrixMul(matrix) => {
-                matrix.left.contains_native_complex_builtin()
-                    || matrix.right.contains_native_complex_builtin()
+                matrix.left.contains_native_complex_syntax()
+                    || matrix.right.contains_native_complex_syntax()
             }
             Obj::MatrixScalarMul(matrix) => {
-                matrix.scalar.contains_native_complex_builtin()
-                    || matrix.matrix.contains_native_complex_builtin()
+                matrix.scalar.contains_native_complex_syntax()
+                    || matrix.matrix.contains_native_complex_syntax()
             }
             Obj::MatrixPow(matrix) => {
-                matrix.base.contains_native_complex_builtin()
-                    || matrix.exponent.contains_native_complex_builtin()
+                matrix.base.contains_native_complex_syntax()
+                    || matrix.exponent.contains_native_complex_syntax()
             }
             Obj::StructObj(object) => object
                 .params
                 .iter()
-                .any(|obj| obj.contains_native_complex_builtin()),
+                .any(|obj| obj.contains_native_complex_syntax()),
             Obj::ObjAsStructInstanceWithFieldAccess(access) => {
                 access
                     .struct_obj
                     .params
                     .iter()
-                    .any(|obj| obj.contains_native_complex_builtin())
-                    || access.obj.contains_native_complex_builtin()
+                    .any(|obj| obj.contains_native_complex_syntax())
+                    || access.obj.contains_native_complex_syntax()
             }
             Obj::InstantiatedTemplateObj(template) => template
                 .args
                 .iter()
-                .any(|obj| obj.contains_native_complex_builtin()),
+                .any(|obj| obj.contains_native_complex_syntax()),
         }
     }
 }
diff --git a/src/obj/mod.rs b/src/obj/mod.rs
--- a/src/obj/mod.rs
+++ b/src/obj/mod.rs
@@ -24,14 +24,15 @@ pub use free_param_obj::{
     ForallFreeParamObj, ParamObjType, SetBuilderFreeParamObj, TupleIndexFreeParamObj,
 };
 pub use obj::{
-    fn_obj_to_string, Abs, Add, BigIntersect, BigUnion, Cart, CartDim, ClosedRange, Div,
-    FiniteSeqListObj, FiniteSeqSet, FiniteSetMax, FiniteSetMin, FiniteSetSize, FnObj, FnRange,
-    GeneralCart, InstantiatedTemplateObj, Intersect, IntervalObj, IntervalObjStruct, ListSet, Log,
-    MatrixAdd, MatrixListObj, MatrixMul, MatrixPow, MatrixScalarMul, MatrixSet, MatrixSub, Mod,
-    Mul, Number, Obj, ObjAsStructInstanceWithFieldAccess, ObjAtIndex, ObjKind,
-    OneSideInfinityIntervalObj, OneSideInfinityIntervalObjStruct, Pow, PowerSet, Product,
-    ProductOfFiniteSet, Proj, Range, Replacement, SeqSet, SetBuilder, SetDiff, SetMinus, Sqrt,
-    StructObj, Sub, Sum, SumOfFiniteSet, Tuple, TupleDim, Union,
+    fn_obj_to_string, Abs, Add, BigIntersect, BigUnion, Cart, CartDim, ClosedRange, ComplexAbs,
+    Div, FiniteSeqListObj, FiniteSeqSet, FiniteSetMax, FiniteSetMin, FiniteSetSize, FnObj, FnRange,
+    GeneralCart, ImaginaryPart, ImaginaryUnit, InstantiatedTemplateObj, Intersect, IntervalObj,
+    IntervalObjStruct, ListSet, Log, MatrixAdd, MatrixListObj, MatrixMul, MatrixPow,
+    MatrixScalarMul, MatrixSet, MatrixSub, Mod, Mul, Number, Obj,
+    ObjAsStructInstanceWithFieldAccess, ObjAtIndex, ObjKind, OneSideInfinityIntervalObj,
+    OneSideInfinityIntervalObjStruct, Pow, PowerSet, Product, ProductOfFiniteSet, Proj, Range,
+    RealPart, Replacement, SeqSet, SetBuilder, SetDiff, SetMinus, Sqrt, StructObj, Sub, Sum,
+    SumOfFiniteSet, Tuple, TupleDim, Union,
 };
 pub use obj_alpha_key::{
     nested_obj_binder_normalized_key, obj_equality_key,
diff --git a/src/obj/obj.rs b/src/obj/obj.rs
--- a/src/obj/obj.rs
+++ b/src/obj/obj.rs
@@ -8,13 +8,17 @@ pub enum Obj {
     Atom(AtomObj),
     FnObj(FnObj),
     Number(Number),
+    ImaginaryUnit(ImaginaryUnit),
     Add(Add),
     Sub(Sub),
     Mul(Mul),
     Div(Div),
     Mod(Mod),
     Pow(Pow),
     Abs(Abs),
+    RealPart(RealPart),
+    ImaginaryPart(ImaginaryPart),
+    ComplexAbs(ComplexAbs),
     Sqrt(Sqrt),
     Log(Log),
     Union(Union),
@@ -136,6 +140,10 @@ pub enum ObjKind {
     TupleIndexFreeParam = 67,
     CartIndexFreeParam = 68,
     GeneralCart = 69,
+    ImaginaryUnit = 70,
+    RealPart = 71,
+    ImaginaryPart = 72,
+    ComplexAbs = 73,
 }
 
 impl ObjKind {
@@ -540,6 +548,9 @@ pub struct Number {
     pub normalized_value: String,
 }
 
+#[derive(Clone)]
+pub struct ImaginaryUnit;
+
 #[derive(Clone)]
 pub struct Add {
     pub left: Box<Obj>,
@@ -581,6 +592,21 @@ pub struct Abs {
     pub arg: Box<Obj>,
 }
 
+#[derive(Clone)]
+pub struct RealPart {
+    pub arg: Box<Obj>,
+}
+
+#[derive(Clone)]
+pub struct ImaginaryPart {
+    pub arg: Box<Obj>,
+}
+
+#[derive(Clone)]
+pub struct ComplexAbs {
+    pub arg: Box<Obj>,
+}
+
 /// Real logarithm `log(base, x)` with `base > 0`, `base != 1`, `x > 0`.
 #[derive(Clone)]
 pub struct Log {
@@ -673,6 +699,12 @@ impl Number {
     }
 }
 
+impl ImaginaryUnit {
+    pub fn new() -> Self {
+        ImaginaryUnit
+    }
+}
+
 impl Add {
     pub fn new(left: Obj, right: Obj) -> Self {
         Add {
@@ -733,6 +765,24 @@ impl Abs {
     }
 }
 
+impl RealPart {
+    pub fn new(arg: Obj) -> Self {
+        RealPart { arg: Box::new(arg) }
+    }
+}
+
+impl ImaginaryPart {
+    pub fn new(arg: Obj) -> Self {
+        ImaginaryPart { arg: Box::new(arg) }
+    }
+}
+
+impl ComplexAbs {
+    pub fn new(arg: Obj) -> Self {
+        ComplexAbs { arg: Box::new(arg) }
+    }
+}
+
 impl Sqrt {
     pub fn new(arg: Obj) -> Self {
         Sqrt { arg: Box::new(arg) }
@@ -1073,6 +1123,9 @@ fn precedence(o: &Obj) -> u8 {
         Obj::Mul(_) | Obj::Div(_) | Obj::Mod(_) | Obj::MatrixScalarMul(_) => 2,
         Obj::Pow(_)
         | Obj::Abs(_)
+        | Obj::RealPart(_)
+        | Obj::ImaginaryPart(_)
+        | Obj::ComplexAbs(_)
         | Obj::Sqrt(_)
         | Obj::Log(_)
         | Obj::MatrixAdd(_)
@@ -1108,13 +1161,17 @@ impl Obj {
             },
             Obj::FnObj(_) => ObjKind::FnObj,
             Obj::Number(_) => ObjKind::Number,
+            Obj::ImaginaryUnit(_) => ObjKind::ImaginaryUnit,
             Obj::Add(_) => ObjKind::Add,
             Obj::Sub(_) => ObjKind::Sub,
             Obj::Mul(_) => ObjKind::Mul,
             Obj::Div(_) => ObjKind::Div,
             Obj::Mod(_) => ObjKind::Mod,
             Obj::Pow(_) => ObjKind::Pow,
             Obj::Abs(_) => ObjKind::Abs,
+            Obj::RealPart(_) => ObjKind::RealPart,
+            Obj::ImaginaryPart(_) => ObjKind::ImaginaryPart,
+            Obj::ComplexAbs(_) => ObjKind::ComplexAbs,
             Obj::Sqrt(_) => ObjKind::Sqrt,
             Obj::Log(_) => ObjKind::Log,
             Obj::Union(_) => ObjKind::Union,
@@ -1185,6 +1242,9 @@ impl Obj {
             Obj::Mod(_) => MOD.to_string(),
             Obj::Pow(_) => POW.to_string(),
             Obj::Abs(_) => ABS.to_string(),
+            Obj::RealPart(_) => RE.to_string(),
+            Obj::ImaginaryPart(_) => IMG.to_string(),
+            Obj::ComplexAbs(_) => C_ABS.to_string(),
             Obj::Sqrt(_) => SQRT.to_string(),
             Obj::Log(_) => LOG.to_string(),
             Obj::Union(_) => UNION.to_string(),
@@ -1298,6 +1358,21 @@ impl Obj {
                 a.arg.fmt_with_precedence(f, 0)?;
                 write!(f, "{}", RIGHT_BRACE)?;
             }
+            Obj::RealPart(real_part) => {
+                write!(f, "{}{}", RE, LEFT_BRACE)?;
+                real_part.arg.fmt_with_precedence(f, 0)?;
+                write!(f, "{}", RIGHT_BRACE)?;
+            }
+            Obj::ImaginaryPart(imaginary_part) => {
+                write!(f, "{}{}", IMG, LEFT_BRACE)?;
+                imaginary_part.arg.fmt_with_precedence(f, 0)?;
+                write!(f, "{}", RIGHT_BRACE)?;
+            }
+            Obj::ComplexAbs(complex_abs) => {
+                write!(f, "{}{}", C_ABS, LEFT_BRACE)?;
+                complex_abs.arg.fmt_with_precedence(f, 0)?;
+                write!(f, "{}", RIGHT_BRACE)?;
+            }
             Obj::Sqrt(s) => {
                 write!(f, "{} {}", SQRT, LEFT_BRACE)?;
                 s.arg.fmt_with_precedence(f, 0)?;
@@ -1319,6 +1394,7 @@ impl Obj {
             Obj::Atom(x) => write!(f, "{}", x)?,
             Obj::FnObj(x) => write!(f, "{}", x)?,
             Obj::Number(x) => write!(f, "{}", x)?,
+            Obj::ImaginaryUnit(_) => write!(f, "{}", I)?,
             Obj::ListSet(x) => write!(f, "{}", x)?,
             Obj::SetBuilder(x) => write!(f, "{}", x)?,
             Obj::FnSet(x) => write!(f, "{}", x)?,
@@ -1381,6 +1457,7 @@ impl Obj {
                 FnObj::new(head, body).into()
             }
             Obj::Number(n) => n.into(),
+            Obj::ImaginaryUnit(i) => i.into(),
             Obj::Add(x) => Add::new(
                 Obj::replace_bound_identifier(*x.left, from, to),
                 Obj::replace_bound_identifier(*x.right, from, to),
@@ -1412,6 +1489,15 @@ impl Obj {
             )
             .into(),
             Obj::Abs(x) => Abs::new(Obj::replace_bound_identifier(*x.arg, from, to)).into(),
+            Obj::RealPart(x) => {
+                RealPart::new(Obj::replace_bound_identifier(*x.arg, from, to)).into()
+            }
+            Obj::ImaginaryPart(x) => {
+                ImaginaryPart::new(Obj::replace_bound_identifier(*x.arg, from, to)).into()
+            }
+            Obj::ComplexAbs(x) => {
+                ComplexAbs::new(Obj::replace_bound_identifier(*x.arg, from, to)).into()
+            }
             Obj::Sqrt(x) => Sqrt::new(Obj::replace_bound_identifier(*x.arg, from, to)).into(),
             Obj::Log(x) => Log::new(
                 Obj::replace_bound_identifier(*x.base, from, to),
@@ -2366,6 +2452,24 @@ impl fmt::Display for Abs {
     }
 }
 
+impl fmt::Display for RealPart {
+    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
+        write!(f, "{}{}{}{}", RE, LEFT_BRACE, self.arg, RIGHT_BRACE)
+    }
+}
+
+impl fmt::Display for ImaginaryPart {
+    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
+        write!(f, "{}{}{}{}", IMG, LEFT_BRACE, self.arg, RIGHT_BRACE)
+    }
+}
+
+impl fmt::Display for ComplexAbs {
+    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
+        write!(f, "{}{}{}{}", C_ABS, LEFT_BRACE, self.arg, RIGHT_BRACE)
+    }
+}
+
 impl fmt::Display for Sqrt {
     fn fmt(&self, f: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
         write!(f, "{} {}{}{}", SQRT, LEFT_BRACE, self.arg, RIGHT_BRACE)
@@ -2523,6 +2627,12 @@ impl From<Number> for Obj {
     }
 }
 
+impl From<ImaginaryUnit> for Obj {
+    fn from(i: ImaginaryUnit) -> Self {
+        Obj::ImaginaryUnit(i)
+    }
+}
+
 impl From<Add> for Obj {
     fn from(a: Add) -> Self {
         Obj::Add(a)
@@ -2601,6 +2711,24 @@ impl From<Abs> for Obj {
     }
 }
 
+impl From<RealPart> for Obj {
+    fn from(real_part: RealPart) -> Self {
+        Obj::RealPart(real_part)
+    }
+}
+
+impl From<ImaginaryPart> for Obj {
+    fn from(imaginary_part: ImaginaryPart) -> Self {
+        Obj::ImaginaryPart(imaginary_part)
+    }
+}
+
+impl From<ComplexAbs> for Obj {
+    fn from(complex_abs: ComplexAbs) -> Self {
+        Obj::ComplexAbs(complex_abs)
+    }
+}
+
 impl From<Sqrt> for Obj {
     fn from(s: Sqrt) -> Self {
         Obj::Sqrt(s)
diff --git a/src/obj/obj_alpha_key.rs b/src/obj/obj_alpha_key.rs
--- a/src/obj/obj_alpha_key.rs
+++ b/src/obj/obj_alpha_key.rs
@@ -34,7 +34,7 @@ fn collect_obj_binder_bindings(
     depth: usize,
 ) {
     match obj {
-        Obj::Atom(_) | Obj::Number(_) | Obj::StandardSet(_) => {}
+        Obj::Atom(_) | Obj::Number(_) | Obj::ImaginaryUnit(_) | Obj::StandardSet(_) => {}
         Obj::FnObj(x) => {
             collect_fn_obj_head_binder_bindings(x.head.as_ref(), bindings, seen, depth);
             for group in &x.body {
@@ -59,6 +59,9 @@ fn collect_obj_binder_bindings(
         Obj::MatrixScalarMul(x) => collect_two(&x.scalar, &x.matrix, bindings, seen, depth),
         Obj::MatrixPow(x) => collect_two(&x.base, &x.exponent, bindings, seen, depth),
         Obj::Abs(x) => collect_obj_binder_bindings(&x.arg, bindings, seen, depth),
+        Obj::RealPart(x) => collect_obj_binder_bindings(&x.arg, bindings, seen, depth),
+        Obj::ImaginaryPart(x) => collect_obj_binder_bindings(&x.arg, bindings, seen, depth),
+        Obj::ComplexAbs(x) => collect_obj_binder_bindings(&x.arg, bindings, seen, depth),
         Obj::Sqrt(x) => collect_obj_binder_bindings(&x.arg, bindings, seen, depth),
         Obj::Log(x) => {
             collect_obj_binder_bindings(&x.base, bindings, seen, depth);
diff --git a/src/obj/obj_contrain_free_params.rs b/src/obj/obj_contrain_free_params.rs
--- a/src/obj/obj_contrain_free_params.rs
+++ b/src/obj/obj_contrain_free_params.rs
@@ -86,7 +86,7 @@ impl Obj {
     fn collect_free_param_names_into(&self, collector: &mut FreeParamNameCollector) {
         match self {
             Obj::Atom(atom) => collector.collect_atom(atom),
-            Obj::Number(_) | Obj::StandardSet(_) => {}
+            Obj::Number(_) | Obj::ImaginaryUnit(_) | Obj::StandardSet(_) => {}
             Obj::FnObj(fn_obj) => {
                 fn_obj.head.collect_free_param_names_into(collector);
                 for args in &fn_obj.body {
@@ -100,6 +100,9 @@ impl Obj {
             Obj::Mod(x) => collect_forall_free_param_names_in_pair(&x.left, &x.right, collector),
             Obj::Pow(x) => collect_forall_free_param_names_in_pair(&x.base, &x.exponent, collector),
             Obj::Abs(x) => x.arg.collect_free_param_names_into(collector),
+            Obj::RealPart(x) => x.arg.collect_free_param_names_into(collector),
+            Obj::ImaginaryPart(x) => x.arg.collect_free_param_names_into(collector),
+            Obj::ComplexAbs(x) => x.arg.collect_free_param_names_into(collector),
             Obj::Sqrt(x) => x.arg.collect_free_param_names_into(collector),
             Obj::Log(x) => collect_forall_free_param_names_in_pair(&x.base, &x.arg, collector),
             Obj::Union(x) => collect_forall_free_param_names_in_pair(&x.left, &x.right, collector),
diff --git a/src/parse/parse_obj.rs b/src/parse/parse_obj.rs
--- a/src/parse/parse_obj.rs
+++ b/src/parse/parse_obj.rs
@@ -592,6 +592,23 @@ impl Runtime {
         if tok == TEMPLATE_INSTANCE_PREFIX {
             return self.parse_instantiated_template_obj(tb);
         }
+        if tok == I {
+            tb.skip()?;
+            return Ok(ImaginaryUnit::new().into());
+        }
+        if tok == RE || tok == IMG || tok == C_ABS {
+            let operator = tok.to_string();
+            tb.skip()?;
+            tb.skip_token(LEFT_BRACE)?;
+            let arg = self.parse_obj(tb)?;
+            tb.skip_token(RIGHT_BRACE)?;
+            return Ok(match operator.as_str() {
+                RE => RealPart::new(arg).into(),
+                IMG => ImaginaryPart::new(arg).into(),
+                C_ABS => ComplexAbs::new(arg).into(),
+                _ => unreachable!(),
+            });
+        }
         if tok == ABS {
             tb.skip()?;
             tb.skip_token(LEFT_BRACE)?;
@@ -2669,6 +2686,22 @@ mod matrix_operator_parse_tests {
         assert_eq!(ObjKind::BigIntersect as u8, 19);
     }
 
+    #[test]
+    fn native_complex_syntax_has_dedicated_ast_nodes() {
+        let cases = [
+            ("i", ObjKind::ImaginaryUnit),
+            ("re(i)", ObjKind::RealPart),
+            ("img(i)", ObjKind::ImaginaryPart),
+            ("C_abs(i)", ObjKind::ComplexAbs),
+        ];
+
+        for (source, expected_kind) in cases {
+            let obj = parse_obj_line(source).expect("native complex syntax should parse");
+            assert_eq!(obj.kind(), expected_kind, "{source}");
+            assert_eq!(obj.to_string(), source, "{source}");
+        }
+    }
+
     #[test]
     fn big_set_family_operators_reject_wrong_arity() {
         let cases = [
diff --git a/src/prelude.rs b/src/prelude.rs
--- a/src/prelude.rs
+++ b/src/prelude.rs
@@ -134,6 +134,7 @@ pub use crate::obj::Cart;
 pub use crate::obj::CartDim;
 pub use crate::obj::CartIndexFreeParamObj;
 pub use crate::obj::ClosedRange;
+pub use crate::obj::ComplexAbs;
 pub use crate::obj::DefAlgoFreeParamObj;
 pub use crate::obj::DefHeaderFreeParamObj;
 pub use crate::obj::DefStructFieldFreeParamObj;
@@ -155,6 +156,8 @@ pub use crate::obj::ForallFreeParamObj;
 pub use crate::obj::GeneralCart;
 pub use crate::obj::Identifier;
 pub use crate::obj::IdentifierWithMod;
+pub use crate::obj::ImaginaryPart;
+pub use crate::obj::ImaginaryUnit;
 pub use crate::obj::InstantiatedTemplateObj;
 pub use crate::obj::Intersect;
 pub use crate::obj::IntervalObj;
@@ -184,6 +187,7 @@ pub use crate::obj::Product;
 pub use crate::obj::ProductOfFiniteSet;
 pub use crate::obj::Proj;
 pub use crate::obj::Range;
+pub use crate::obj::RealPart;
 pub use crate::obj::Replacement;
 pub use crate::obj::SeqSet;
 pub use crate::obj::SetBuilder;
diff --git a/src/runtime/runtime.rs b/src/runtime/runtime.rs
--- a/src/runtime/runtime.rs
+++ b/src/runtime/runtime.rs
@@ -572,6 +572,7 @@ impl Runtime {
             let name = binding.name();
             if self.current_parse_context().active_binding(name).is_some()
                 || self.visible_symbol_definition(name).is_some()
+                || is_keyword(name)
                 || is_builtin_identifier_name(name)
                 || is_builtin_predicate(name)
             {
diff --git a/src/runtime/runtime_instantiate_obj.rs b/src/runtime/runtime_instantiate_obj.rs
--- a/src/runtime/runtime_instantiate_obj.rs
+++ b/src/runtime/runtime_instantiate_obj.rs
@@ -63,6 +63,7 @@ impl Runtime {
             }
             Obj::FnObj(inner) => self.inst_fn_obj(inner, param_to_arg_map, param_obj_type),
             Obj::Number(inner) => self.inst_number(inner, param_to_arg_map, param_obj_type),
+            Obj::ImaginaryUnit(inner) => Ok(inner.clone().into()),
             Obj::Add(inner) => self.inst_add(inner, param_to_arg_map, param_obj_type),
             Obj::Sub(inner) => self.inst_sub(inner, param_to_arg_map, param_obj_type),
             Obj::Mul(inner) => self.inst_mul(inner, param_to_arg_map, param_obj_type),
@@ -77,6 +78,24 @@ impl Runtime {
             }
             Obj::MatrixPow(inner) => self.inst_matrix_pow(inner, param_to_arg_map, param_obj_type),
             Obj::Abs(inner) => self.inst_abs(inner, param_to_arg_map, param_obj_type),
+            Obj::RealPart(inner) => {
+                Ok(
+                    RealPart::new(self.inst_obj(&inner.arg, param_to_arg_map, param_obj_type)?)
+                        .into(),
+                )
+            }
+            Obj::ImaginaryPart(inner) => Ok(ImaginaryPart::new(self.inst_obj(
+                &inner.arg,
+                param_to_arg_map,
+                param_obj_type,
+            )?)
+            .into()),
+            Obj::ComplexAbs(inner) => {
+                Ok(
+                    ComplexAbs::new(self.inst_obj(&inner.arg, param_to_arg_map, param_obj_type)?)
+                        .into(),
+                )
+            }
             Obj::Sqrt(inner) => self.inst_sqrt(inner, param_to_arg_map, param_obj_type),
             Obj::Log(inner) => self.inst_log(inner, param_to_arg_map, param_obj_type),
             Obj::Union(inner) => self.inst_union(inner, param_to_arg_map, param_obj_type),
diff --git a/src/runtime/runtime_known_object_properties.rs b/src/runtime/runtime_known_object_properties.rs
--- a/src/runtime/runtime_known_object_properties.rs
+++ b/src/runtime/runtime_known_object_properties.rs
@@ -64,24 +64,6 @@ impl Runtime {
     }
 
     pub fn get_object_in_fn_set(&self, obj: &Obj) -> Option<FnSetBody> {
-        if let Obj::Atom(AtomObj::Identifier(identifier)) = obj {
-            if identifier.is_builtin(RE)
-                || identifier.is_builtin(IMG)
-                || identifier.is_builtin(C_ABS)
-            {
-                let param = self
-                    .fresh_param_group_with_set(
-                        vec!["complex_arg".to_string()],
-                        StandardSet::C.into(),
-                    )
-                    .ok()?;
-                return Some(FnSetBody::new(
-                    vec![param],
-                    Vec::new(),
-                    StandardSet::R.into(),
-                ));
-            }
-        }
         if let Some(info) = self.get_known_fn_info_for_obj(obj) {
             if let Some((body, _)) = info.fn_set.as_ref() {
                 return Some(body.clone());
@@ -833,6 +815,7 @@ fn collect_module_name_from_atomic_name(name: &AtomicName, module_names: &mut Ve
 fn collect_module_names_from_obj(obj: &Obj, module_names: &mut Vec<String>) {
     match obj {
         Obj::Atom(atom) => collect_module_names_from_atom(atom, module_names),
+        Obj::ImaginaryUnit(_) => {}
         Obj::FnObj(fn_obj) => {
             collect_module_names_from_fn_obj_head(&fn_obj.head, module_names);
             for group in fn_obj.body.iter() {
@@ -847,6 +830,9 @@ fn collect_module_names_from_obj(obj: &Obj, module_names: &mut Vec<String>) {
         Obj::Div(x) => collect_module_names_from_two(&x.left, &x.right, module_names),
         Obj::Mod(x) => collect_module_names_from_two(&x.left, &x.right, module_names),
         Obj::Pow(x) => collect_module_names_from_two(&x.base, &x.exponent, module_names),
+        Obj::RealPart(x) => collect_module_names_from_obj(&x.arg, module_names),
+        Obj::ImaginaryPart(x) => collect_module_names_from_obj(&x.arg, module_names),
+        Obj::ComplexAbs(x) => collect_module_names_from_obj(&x.arg, module_names),
         Obj::Log(x) => collect_module_names_from_two(&x.base, &x.arg, module_names),
         Obj::Union(x) => collect_module_names_from_two(&x.left, &x.right, module_names),
         Obj::Intersect(x) => collect_module_names_from_two(&x.left, &x.right, module_names),
diff --git a/src/runtime/runtime_resolve_obj.rs b/src/runtime/runtime_resolve_obj.rs
--- a/src/runtime/runtime_resolve_obj.rs
+++ b/src/runtime/runtime_resolve_obj.rs
@@ -59,6 +59,7 @@ impl Runtime {
         }
         match obj {
             Obj::Number(number) => number.clone().into(),
+            Obj::ImaginaryUnit(unit) => unit.clone().into(),
             Obj::Atom(AtomObj::IdentifierWithMod(identifier))
                 if self.is_current_parse_module(&identifier.mod_name) =>
             {
@@ -123,6 +124,13 @@ impl Runtime {
                 let result: Obj = Abs::new(resolved_arg).into();
                 self.resolve_obj_try_fold_arithmetic(result)
             }
+            Obj::RealPart(real_part) => RealPart::new(self.resolve_obj(&real_part.arg)).into(),
+            Obj::ImaginaryPart(imaginary_part) => {
+                ImaginaryPart::new(self.resolve_obj(&imaginary_part.arg)).into()
+            }
+            Obj::ComplexAbs(complex_abs) => {
+                ComplexAbs::new(self.resolve_obj(&complex_abs.arg)).into()
+            }
             Obj::Log(l) => {
                 let result: Obj =
                     Log::new(self.resolve_obj(&l.base), self.resolve_obj(&l.arg)).into();
diff --git a/src/runtime/runtime_symbol.rs b/src/runtime/runtime_symbol.rs
--- a/src/runtime/runtime_symbol.rs
+++ b/src/runtime/runtime_symbol.rs
@@ -181,7 +181,7 @@ impl Runtime {
                 existing.role().description(),
             ));
         }
-        if is_builtin_identifier_name(name) || is_builtin_predicate(name) {
+        if is_keyword(name) || is_builtin_identifier_name(name) || is_builtin_predicate(name) {
             return Err(symbol_name_already_used_error(name, "builtin"));
         }
 
@@ -217,7 +217,7 @@ impl Runtime {
                 existing.role().description(),
             ));
         }
-        if is_builtin_identifier_name(name) || is_builtin_predicate(name) {
+        if is_keyword(name) || is_builtin_identifier_name(name) || is_builtin_predicate(name) {
             return Err(symbol_name_already_used_error(name, "builtin"));
         }
         self.top_level_env()
@@ -262,6 +262,7 @@ impl Runtime {
             }
             if self.current_parse_context().active_binding(name).is_some()
                 || self.visible_symbol_definition(name).is_some()
+                || is_keyword(name)
                 || is_builtin_identifier_name(name)
                 || is_builtin_predicate(name)
             {
diff --git a/src/stmt/parameter_def.rs b/src/stmt/parameter_def.rs
--- a/src/stmt/parameter_def.rs
+++ b/src/stmt/parameter_def.rs
@@ -591,7 +591,7 @@ fn collect_cited_param_indices_from_obj(
                 }
             }
         }
-        Obj::Number(_) | Obj::StandardSet(_) => {}
+        Obj::Number(_) | Obj::ImaginaryUnit(_) | Obj::StandardSet(_) => {}
         Obj::Add(x) => collect_cited_param_indices_from_two_objs(
             &x.left,
             &x.right,
@@ -640,6 +640,24 @@ fn collect_cited_param_indices_from_obj(
             shadowed_names,
             out,
         ),
+        Obj::RealPart(x) => collect_cited_param_indices_from_obj(
+            &x.arg,
+            previous_param_indices,
+            shadowed_names,
+            out,
+        ),
+        Obj::ImaginaryPart(x) => collect_cited_param_indices_from_obj(
+            &x.arg,
+            previous_param_indices,
+            shadowed_names,
+            out,
+        ),
+        Obj::ComplexAbs(x) => collect_cited_param_indices_from_obj(
+            &x.arg,
+            previous_param_indices,
+            shadowed_names,
+            out,
+        ),
         Obj::Sqrt(x) => collect_cited_param_indices_from_obj(
             &x.arg,
             previous_param_indices,
diff --git a/src/symbol/symbol.rs b/src/symbol/symbol.rs
--- a/src/symbol/symbol.rs
+++ b/src/symbol/symbol.rs
@@ -165,11 +165,6 @@ pub fn builtin_symbol_ref(name: &str) -> Option<SymbolRef> {
         INJECTIVE => 45,
         SURJECTIVE => 46,
         BIJECTIVE => 47,
-        C => 48,
-        I => 49,
-        RE => 50,
-        IMG => 51,
-        C_ABS => 52,
         _ => return None,
     };
     Some(SymbolRef::new(
diff --git a/src/to_latex/to_latex_string.rs b/src/to_latex/to_latex_string.rs
--- a/src/to_latex/to_latex_string.rs
+++ b/src/to_latex/to_latex_string.rs
@@ -844,27 +844,6 @@ impl FiniteSeqSet {
 
 impl FnObj {
     pub fn to_latex_string(&self) -> String {
-        if let FnObjHead::Identifier(identifier) = self.head.as_ref() {
-            if let [group] = self.body.as_slice() {
-                if let [arg] = group.as_slice() {
-                    if identifier.is_builtin(RE) {
-                        return format!(
-                            r"\operatorname{{re}}\left( {} \right)",
-                            arg.to_latex_string()
-                        );
-                    }
-                    if identifier.is_builtin(IMG) {
-                        return format!(
-                            r"\operatorname{{img}}\left( {} \right)",
-                            arg.to_latex_string()
-                        );
-                    }
-                    if identifier.is_builtin(C_ABS) {
-                        return format!(r"\left| {} \right|", arg.to_latex_string());
-                    }
-                }
-            }
-        }
         let head = match self.head.as_ref() {
             FnObjHead::Identifier(i) => i.to_latex_string(),
             FnObjHead::IdentifierWithMod(i) => i.to_latex_string(),
@@ -1180,11 +1159,7 @@ impl HaveObjByExistFactsStmt {
 
 impl Identifier {
     pub fn to_latex_string(&self) -> String {
-        if self.is_builtin(I) {
-            r"\mathrm{i}".to_string()
-        } else {
-            latex_local_ident(&self.name)
-        }
+        latex_local_ident(&self.name)
     }
 }
 
@@ -1972,6 +1947,36 @@ impl StandardSet {
     }
 }
 
+impl ImaginaryUnit {
+    pub fn to_latex_string(&self) -> String {
+        r"\mathrm{i}".to_string()
+    }
+}
+
+impl RealPart {
+    pub fn to_latex_string(&self) -> String {
+        format!(
+            r"\operatorname{{re}}\left( {} \right)",
+            self.arg.to_latex_string()
+        )
+    }
+}
+
+impl ImaginaryPart {
+    pub fn to_latex_string(&self) -> String {
+        format!(
+            r"\operatorname{{img}}\left( {} \right)",
+            self.arg.to_latex_string()
+        )
+    }
+}
+
+impl ComplexAbs {
+    pub fn to_latex_string(&self) -> String {
+        format!(r"\left| {} \right|", self.arg.to_latex_string())
+    }
+}
+
 impl Fact {
     pub fn to_latex_string(&self) -> String {
         match self {
@@ -2040,13 +2045,17 @@ impl Obj {
             Obj::Atom(AtomObj::IdentifierWithMod(x)) => x.to_latex_string(),
             Obj::FnObj(x) => x.to_latex_string(),
             Obj::Number(x) => x.to_latex_string(),
+            Obj::ImaginaryUnit(x) => x.to_latex_string(),
             Obj::Add(x) => x.to_latex_string(),
             Obj::Sub(x) => x.to_latex_string(),
             Obj::Mul(x) => x.to_latex_string(),
             Obj::Div(x) => x.to_latex_string(),
             Obj::Mod(x) => x.to_latex_string(),
             Obj::Pow(x) => x.to_latex_string(),
             Obj::Abs(x) => x.to_latex_string(),
+            Obj::RealPart(x) => x.to_latex_string(),
+            Obj::ImaginaryPart(x) => x.to_latex_string(),
+            Obj::ComplexAbs(x) => x.to_latex_string(),
             Obj::Sqrt(x) => x.to_latex_string(),
             Obj::Log(x) => x.to_latex_string(),
             Obj::Union(x) => x.to_latex_string(),
diff --git a/src/to_lean/to_lean_pipeline.rs b/src/to_lean/to_lean_pipeline.rs
--- a/src/to_lean/to_lean_pipeline.rs
+++ b/src/to_lean/to_lean_pipeline.rs
@@ -72,7 +72,7 @@ impl LeanEmitter {
         }
 
         if let Stmt::DefObjStmt(DefObjStmt::HaveFnEqualStmt(stmt)) = &verified_stmt.stmt {
-            if stmt.equal_to_anonymous_fn.contains_native_complex_builtin() {
+            if stmt.equal_to_anonymous_fn.contains_native_complex_syntax() {
                 return Err(lean_extract_error(
                     &stmt.line_file,
                     "Lean extractor MVP does not support native complex function signatures or bodies",
@@ -200,7 +200,7 @@ impl LeanEmitter {
     }
 
     fn fact(&self, fact: &Fact) -> Result<String, RuntimeError> {
-        if fact.contains_native_complex_builtin() {
+        if fact.contains_native_complex_syntax() {
             return Err(lean_extract_error(
                 &fact.line_file(),
                 "Lean extractor MVP does not support native complex expressions in facts",
@@ -371,7 +371,7 @@ impl LeanEmitter {
     }
 
     fn real_expr(&self, obj: &Obj) -> Result<String, RuntimeError> {
-        if obj.contains_native_complex_builtin() {
+        if obj.contains_native_complex_syntax() {
             return Err(lean_extract_error(
                 &default_line_file(),
                 "Lean extractor MVP does not support native complex expressions",
diff --git a/src/to_python/to_python_pipeline.rs b/src/to_python/to_python_pipeline.rs
--- a/src/to_python/to_python_pipeline.rs
+++ b/src/to_python/to_python_pipeline.rs
@@ -358,7 +358,7 @@ impl PythonExtractor {
         for ((name, param_type), obj) in names_with_types.iter().zip(stmt.objs_equal_to.iter()) {
             if matches!(
                 param_type,
-                ParamType::Obj(obj) if obj.contains_native_complex_builtin()
+                ParamType::Obj(obj) if obj.contains_native_complex_syntax()
             ) {
                 return Err(python_extract_error(
                     &stmt.line_file,
@@ -378,7 +378,7 @@ impl PythonExtractor {
     }
 
     fn reject_native_complex_function(&self, stmt: &HaveFnEqualStmt) -> Result<(), RuntimeError> {
-        if stmt.equal_to_anonymous_fn.contains_native_complex_builtin() {
+        if stmt.equal_to_anonymous_fn.contains_native_complex_syntax() {
             return Err(python_extract_error(
                 &stmt.line_file,
                 "python extractor v1 does not support native complex function signatures or bodies",
@@ -388,7 +388,7 @@ impl PythonExtractor {
     }
 
     fn reject_native_complex_fact(&self, fact: &Fact) -> Result<(), RuntimeError> {
-        if fact.contains_native_complex_builtin() {
+        if fact.contains_native_complex_syntax() {
             return Err(python_extract_error(
                 &fact.line_file(),
                 "python extractor v1 does not support native complex expressions in facts",
@@ -571,6 +571,16 @@ impl PythonExtractor {
     ) -> Result<String, RuntimeError> {
         match obj {
             Obj::Number(n) => Ok(python_float_literal(&n.normalized_value)),
+            Obj::ImaginaryUnit(_) => Err(python_extract_error(
+                line_file,
+                "python extractor v1 does not support native complex expressions",
+            )),
+            Obj::RealPart(_) | Obj::ImaginaryPart(_) | Obj::ComplexAbs(_) => {
+                Err(python_extract_error(
+                    line_file,
+                    "python extractor v1 does not support native complex coordinate or modulus expressions",
+                ))
+            }
             Obj::Atom(a) => self.python_atom(a, params, line_file),
             Obj::Add(a) => {
                 self.python_binary_expr(a.left.as_ref(), "+", a.right.as_ref(), params, line_file)
@@ -619,12 +629,6 @@ impl PythonExtractor {
         line_file: &LineFile,
     ) -> Result<String, RuntimeError> {
         let name = match atom {
-            AtomObj::Identifier(i) if i.is_builtin(I) => {
-                return Err(python_extract_error(
-                    line_file,
-                    "python extractor v1 does not support native complex expressions",
-                ));
-            }
             AtomObj::Identifier(i) => i.name.as_str(),
             AtomObj::FnSet(p) => p.name.as_str(),
             AtomObj::DefAlgo(p) => p.name.as_str(),
@@ -667,14 +671,6 @@ impl PythonExtractor {
         }
 
         let fn_name = match fn_obj.head.as_ref() {
-            FnObjHead::Identifier(i)
-                if i.is_builtin(RE) || i.is_builtin(IMG) || i.is_builtin(C_ABS) =>
-            {
-                return Err(python_extract_error(
-                    line_file,
-                    "python extractor v1 does not support native complex coordinate or modulus expressions",
-                ));
-            }
             FnObjHead::Identifier(i) => i.name.as_str(),
             _ => {
                 return Err(python_extract_error(
diff --git a/src/verify/verify_atomic_fact_with_known_forall.rs b/src/verify/verify_atomic_fact_with_known_forall.rs
--- a/src/verify/verify_atomic_fact_with_known_forall.rs
+++ b/src/verify/verify_atomic_fact_with_known_forall.rs
@@ -804,6 +804,13 @@ impl Runtime {
             }
             Obj::FnObj(ref f) => self.match_arg_when_left_is_fn_obj(f, given_arg),
             Obj::Number(ref left) => self.match_arg_when_left_is_number(left, given_arg),
+            Obj::ImaginaryUnit(_) => {
+                if matches!(given_arg, Obj::ImaginaryUnit(_)) {
+                    Ok(Some(HashMap::new()))
+                } else {
+                    Ok(None)
+                }
+            }
             Obj::Add(ref a) => self.match_arg_when_left_is_add(&a.left, &a.right, given_arg),
             Obj::MatrixAdd(ref a) => {
                 self.match_arg_when_left_is_matrix_add(&a.left, &a.right, given_arg)
@@ -826,6 +833,24 @@ impl Runtime {
             Obj::Mod(ref a) => self.match_arg_when_left_is_mod(&a.left, &a.right, given_arg),
             Obj::Pow(ref a) => self.match_arg_when_left_is_pow(&a.base, &a.exponent, given_arg),
             Obj::Abs(ref a) => self.match_arg_when_left_is_abs(a.arg.as_ref(), given_arg),
+            Obj::RealPart(ref a) => match given_arg {
+                Obj::RealPart(g) => {
+                    self.match_arg_in_atomic_fact_in_known_forall_with_given_arg(&a.arg, &g.arg)
+                }
+                _ => Ok(None),
+            },
+            Obj::ImaginaryPart(ref a) => match given_arg {
+                Obj::ImaginaryPart(g) => {
+                    self.match_arg_in_atomic_fact_in_known_forall_with_given_arg(&a.arg, &g.arg)
+                }
+                _ => Ok(None),
+            },
+            Obj::ComplexAbs(ref a) => match given_arg {
+                Obj::ComplexAbs(g) => {
+                    self.match_arg_in_atomic_fact_in_known_forall_with_given_arg(&a.arg, &g.arg)
+                }
+                _ => Ok(None),
+            },
             Obj::Sqrt(ref a) => self.match_arg_when_left_is_sqrt(a.arg.as_ref(), given_arg),
             Obj::Log(ref a) => self.match_arg_when_left_is_log(&a.base, &a.arg, given_arg),
             Obj::Union(ref a) => self.match_arg_when_left_is_union(&a.left, &a.right, given_arg),
diff --git a/src/verify/verify_builtin_rules/complex_builtin.rs b/src/verify/verify_builtin_rules/complex_builtin.rs
--- a/src/verify/verify_builtin_rules/complex_builtin.rs
+++ b/src/verify/verify_builtin_rules/complex_builtin.rs
@@ -2,8 +2,8 @@ use crate::prelude::*;
 use crate::verify::verify_equality_by_builtin_rules::verify_equality_by_they_are_the_same;
 
 impl Runtime {
-    /// Native complex equalities use stable builtin symbols and intentionally normalize only
-    /// the imaginary unit and the first coordinate/modulus interfaces.
+    /// Native complex equalities use dedicated AST nodes and intentionally normalize only the
+    /// imaginary unit and the first coordinate/modulus interfaces.
     /// Example: `i^2 = -1`, while an arbitrary `(a + b*i) * (c + d*i)` stays opaque.
     pub(super) fn try_verify_native_complex_equality(
         &mut self,
@@ -76,58 +76,55 @@ impl Runtime {
             None
         };
         if let Some(z) = candidate {
-            if let Some(complex_abs) = native_builtin_call(C_ABS, z.clone()) {
-                let known_zero =
-                    self.verify_objs_are_equal_known_only(&complex_abs, &zero, line_file.clone());
-                if known_zero.is_true() {
-                    let Some(mut steps) =
-                        self.verify_objects_are_known_complex(&[z], &line_file, verify_state)?
-                    else {
-                        return Ok(None);
-                    };
-                    steps.push(known_zero);
-                    return Ok(Some(complex_equality_result_with_steps(
-                        left,
-                        right,
-                        line_file,
-                        "complex modulus zero implies zero argument",
-                        steps,
-                    )));
-                }
-            }
-        }
-
-        if let Some((z, expected)) = native_reconstruction_pair(left) {
-            if verify_equality_by_they_are_the_same(&expected, right) {
-                let Some(steps) =
+            let complex_abs: Obj = ComplexAbs::new(z.clone()).into();
+            let known_zero =
+                self.verify_objs_are_equal_known_only(&complex_abs, &zero, line_file.clone());
+            if known_zero.is_true() {
+                let Some(mut steps) =
                     self.verify_objects_are_known_complex(&[z], &line_file, verify_state)?
                 else {
                     return Ok(None);
                 };
+                steps.push(known_zero);
                 return Ok(Some(complex_equality_result_with_steps(
                     left,
                     right,
                     line_file,
-                    "complex reconstruction from real and imaginary coordinates",
+                    "complex modulus zero implies zero argument",
                     steps,
                 )));
             }
         }
-        if let Some((z, expected)) = native_reconstruction_pair(right) {
-            if verify_equality_by_they_are_the_same(&expected, left) {
-                let Some(steps) =
-                    self.verify_objects_are_known_complex(&[z], &line_file, verify_state)?
-                else {
-                    return Ok(None);
-                };
-                return Ok(Some(complex_equality_result_with_steps(
-                    left,
-                    right,
-                    line_file,
-                    "complex reconstruction from real and imaginary coordinates",
-                    steps,
-                )));
-            }
+
+        let (z, expected) = native_reconstruction_pair(left);
+        if verify_equality_by_they_are_the_same(&expected, right) {
+            let Some(steps) =
+                self.verify_objects_are_known_complex(&[z], &line_file, verify_state)?
+            else {
+                return Ok(None);
+            };
+            return Ok(Some(complex_equality_result_with_steps(
+                left,
+                right,
+                line_file,
+                "complex reconstruction from real and imaginary coordinates",
+                steps,
+            )));
+        }
+        let (z, expected) = native_reconstruction_pair(right);
+        if verify_equality_by_they_are_the_same(&expected, left) {
+            let Some(steps) =
+                self.verify_objects_are_known_complex(&[z], &line_file, verify_state)?
+            else {
+                return Ok(None);
+            };
+            return Ok(Some(complex_equality_result_with_steps(
+                left,
+                right,
+                line_file,
+                "complex reconstruction from real and imaginary coordinates",
+                steps,
+            )));
         }
 
         let Some(mut steps) =
@@ -138,18 +135,10 @@ impl Runtime {
         if self.objects_have_known_standard_membership(&[left, right], StandardSet::R) {
             return Ok(None);
         }
-        let Some(left_re) = native_builtin_call(RE, left.clone()) else {
-            return Ok(None);
-        };
-        let Some(right_re) = native_builtin_call(RE, right.clone()) else {
-            return Ok(None);
-        };
-        let Some(left_img) = native_builtin_call(IMG, left.clone()) else {
-            return Ok(None);
-        };
-        let Some(right_img) = native_builtin_call(IMG, right.clone()) else {
-            return Ok(None);
-        };
+        let left_re: Obj = RealPart::new(left.clone()).into();
+        let right_re: Obj = RealPart::new(right.clone()).into();
+        let left_img: Obj = ImaginaryPart::new(left.clone()).into();
+        let right_img: Obj = ImaginaryPart::new(right.clone()).into();
         let re_result =
             self.verify_objs_are_equal_known_only(&left_re, &right_re, line_file.clone());
         if !re_result.is_true() {
@@ -196,10 +185,10 @@ impl Runtime {
     ) -> Option<StmtResult> {
         let matches = match atomic_fact {
             AtomicFact::LessEqualFact(f) => {
-                obj_is_literal_zero(&f.left) && native_builtin_call_arg(&f.right, C_ABS).is_some()
+                obj_is_literal_zero(&f.left) && matches!(&f.right, Obj::ComplexAbs(_))
             }
             AtomicFact::GreaterEqualFact(f) => {
-                obj_is_literal_zero(&f.right) && native_builtin_call_arg(&f.left, C_ABS).is_some()
+                obj_is_literal_zero(&f.right) && matches!(&f.left, Obj::ComplexAbs(_))
             }
             _ => false,
         };
@@ -220,17 +209,14 @@ impl Runtime {
         line_file: LineFile,
         verify_state: &VerifyState,
     ) -> Result<Option<(String, Vec<StmtResult>)>, RuntimeError> {
-        let (coordinate, arg) = if let Some(arg) = native_builtin_call_arg(application, RE) {
-            (RE, arg)
-        } else if let Some(arg) = native_builtin_call_arg(application, IMG) {
-            (IMG, arg)
-        } else {
-            return Ok(None);
+        let (coordinate, is_real_part, arg) = match application {
+            Obj::RealPart(real_part) => (RE, true, real_part.arg.as_ref()),
+            Obj::ImaginaryPart(imaginary_part) => (IMG, false, imaginary_part.arg.as_ref()),
+            _ => return Ok(None),
         };
 
         if obj_is_native_i(arg) {
-            let target: Obj =
-                Number::new(if coordinate == RE { "0" } else { "1" }.to_string()).into();
+            let target: Obj = Number::new(if is_real_part { "0" } else { "1" }.to_string()).into();
             if verify_equality_by_they_are_the_same(&target, expected) {
                 return Ok(Some((
                     format!("{coordinate}: native imaginary-unit coordinate"),
@@ -240,7 +226,7 @@ impl Runtime {
         }
 
         if let Some((real_part, imaginary_part)) = linear_complex_parts(arg) {
-            let target = if coordinate == RE {
+            let target = if is_real_part {
                 real_part.clone()
             } else {
                 imaginary_part.clone()
@@ -261,15 +247,15 @@ impl Runtime {
             }
         }
 
-        if verify_equality_by_they_are_the_same(arg, expected) && coordinate == RE {
+        if verify_equality_by_they_are_the_same(arg, expected) && is_real_part {
             let Some(steps) =
                 self.verify_objects_are_known_reals(&[arg], &line_file, verify_state)?
             else {
                 return Ok(None);
             };
             return Ok(Some(("re: real embedding".to_string(), steps)));
         }
-        if obj_is_literal_zero(expected) && coordinate == IMG {
+        if obj_is_literal_zero(expected) && !is_real_part {
             let Some(steps) =
                 self.verify_objects_are_known_reals(&[arg], &line_file, verify_state)?
             else {
@@ -313,9 +299,10 @@ impl Runtime {
         line_file: LineFile,
         verify_state: &VerifyState,
     ) -> Result<Option<(String, Vec<StmtResult>)>, RuntimeError> {
-        let Some(arg) = native_builtin_call_arg(application, C_ABS) else {
+        let Obj::ComplexAbs(complex_abs) = application else {
             return Ok(None);
         };
+        let arg = complex_abs.arg.as_ref();
         if obj_is_native_i(arg) && obj_is_literal_one(expected) {
             return Ok(Some(("complex modulus of i".to_string(), Vec::new())));
         }
@@ -333,9 +320,7 @@ impl Runtime {
             )));
         }
 
-        let Some(definition) = native_complex_abs_definition(arg) else {
-            return Ok(None);
-        };
+        let definition = native_complex_abs_definition(arg);
         if verify_equality_by_they_are_the_same(&definition, expected) {
             return Ok(Some((
                 "complex modulus coordinate definition".to_string(),
@@ -438,11 +423,11 @@ fn native_i_normal_form(obj: &Obj) -> Option<(Obj, &'static str)> {
     let exponent = exponent.normalized_value.parse::<i128>().ok()?;
     let normalized = match exponent.rem_euclid(4) {
         0 => Number::new("1".to_string()).into(),
-        1 => native_builtin_identifier_obj(I)?,
+        1 => ImaginaryUnit::new().into(),
         2 => Number::new("-1".to_string()).into(),
         3 => Mul::new(
             Number::new("-1".to_string()).into(),
-            native_builtin_identifier_obj(I)?,
+            ImaginaryUnit::new().into(),
         )
         .into(),
         _ => unreachable!(),
@@ -465,21 +450,21 @@ fn native_normal_form_matches(expected: &Obj, target: &Obj) -> bool {
     }
 }
 
-fn native_reconstruction_pair(obj: &Obj) -> Option<(&Obj, Obj)> {
+fn native_reconstruction_pair(obj: &Obj) -> (&Obj, Obj) {
     let z = obj;
-    let re = native_builtin_call(RE, z.clone())?;
-    let img = native_builtin_call(IMG, z.clone())?;
-    let imaginary_term = Mul::new(img, native_builtin_identifier_obj(I)?).into();
-    Some((z, Add::new(re, imaginary_term).into()))
+    let re: Obj = RealPart::new(z.clone()).into();
+    let img: Obj = ImaginaryPart::new(z.clone()).into();
+    let imaginary_term = Mul::new(img, ImaginaryUnit::new().into()).into();
+    (z, Add::new(re, imaginary_term).into())
 }
 
-fn native_complex_abs_definition(arg: &Obj) -> Option<Obj> {
-    let re = native_builtin_call(RE, arg.clone())?;
-    let img = native_builtin_call(IMG, arg.clone())?;
+fn native_complex_abs_definition(arg: &Obj) -> Obj {
+    let re: Obj = RealPart::new(arg.clone()).into();
+    let img: Obj = ImaginaryPart::new(arg.clone()).into();
     let two: Obj = Number::new("2".to_string()).into();
     let squared_re: Obj = Pow::new(re, two.clone()).into();
     let squared_img: Obj = Pow::new(img, two).into();
-    Some(Sqrt::new(Add::new(squared_re, squared_img).into()).into())
+    Sqrt::new(Add::new(squared_re, squared_img).into()).into()
 }
 
 fn linear_complex_parts(obj: &Obj) -> Option<(&Obj, &Obj)> {
@@ -498,36 +483,8 @@ fn linear_complex_parts(obj: &Obj) -> Option<(&Obj, &Obj)> {
     }
 }
 
-fn native_builtin_call(name: &str, arg: Obj) -> Option<Obj> {
-    let identifier = Identifier::new_bound(name.to_string(), builtin_symbol_ref(name)?);
-    Some(FnObj::new(FnObjHead::Identifier(identifier), vec![vec![Box::new(arg)]]).into())
-}
-
-fn native_builtin_call_arg<'a>(obj: &'a Obj, name: &str) -> Option<&'a Obj> {
-    let Obj::FnObj(fn_obj) = obj else {
-        return None;
-    };
-    let FnObjHead::Identifier(identifier) = fn_obj.head.as_ref() else {
-        return None;
-    };
-    if !identifier.is_builtin(name) {
-        return None;
-    }
-    let [group] = fn_obj.body.as_slice() else {
-        return None;
-    };
-    let [arg] = group.as_slice() else {
-        return None;
-    };
-    Some(arg.as_ref())
-}
-
-fn native_builtin_identifier_obj(name: &str) -> Option<Obj> {
-    Some(Identifier::new_bound(name.to_string(), builtin_symbol_ref(name)?).into())
-}
-
 fn obj_is_native_i(obj: &Obj) -> bool {
-    matches!(obj, Obj::Atom(AtomObj::Identifier(identifier)) if identifier.is_builtin(I))
+    matches!(obj, Obj::ImaginaryUnit(_))
 }
 
 fn obj_is_literal_zero(obj: &Obj) -> bool {
diff --git a/src/verify/verify_builtin_rules/in_fact_builtin/dispatch.rs b/src/verify/verify_builtin_rules/in_fact_builtin/dispatch.rs
--- a/src/verify/verify_builtin_rules/in_fact_builtin/dispatch.rs
+++ b/src/verify/verify_builtin_rules/in_fact_builtin/dispatch.rs
@@ -102,15 +102,38 @@ impl Runtime {
         if let Some(result) = self.maybe_verify_in_fact_builtin_operator_signature(in_fact) {
             return Ok(result);
         }
-        if let (Obj::Atom(AtomObj::Identifier(identifier)), Obj::StandardSet(StandardSet::C)) =
-            (&in_fact.element, &in_fact.set)
-        {
-            if identifier.is_builtin(I) {
-                return Ok(number_in_set_verified_by_builtin_rules_result(
-                    in_fact,
-                    "native imaginary unit is in C",
-                ));
+        if matches!(
+            (&in_fact.element, &in_fact.set),
+            (Obj::ImaginaryUnit(_), Obj::StandardSet(StandardSet::C))
+        ) {
+            return Ok(number_in_set_verified_by_builtin_rules_result(
+                in_fact,
+                "native imaginary unit is in C",
+            ));
+        }
+        // Real and imaginary coordinates and complex modulus map a complex argument into R.
+        // Example: `z $in C` implies `re(z) $in R`.
+        if matches!(
+            &in_fact.element,
+            Obj::RealPart(_) | Obj::ImaginaryPart(_) | Obj::ComplexAbs(_)
+        ) && matches!(
+            &in_fact.set,
+            Obj::StandardSet(StandardSet::R) | Obj::StandardSet(StandardSet::C)
+        ) {
+            if self
+                .verify_obj_well_defined_and_store_cache(&in_fact.element, verify_state)
+                .is_err()
+            {
+                return Ok(StmtUnknown::new().into());
             }
+            let reason = if matches!(&in_fact.set, Obj::StandardSet(StandardSet::R)) {
+                "native complex coordinate or modulus has real result"
+            } else {
+                "native complex coordinate or modulus has real result, hence is in C"
+            };
+            return Ok(number_in_set_verified_by_builtin_rules_result(
+                in_fact, reason,
+            ));
         }
         if let Some(result) =
             self.maybe_verify_in_fact_in_unfolded_user_defined_set(in_fact, verify_state)?
diff --git a/src/verify/verify_by_syntax.rs b/src/verify/verify_by_syntax.rs
--- a/src/verify/verify_by_syntax.rs
+++ b/src/verify/verify_by_syntax.rs
@@ -19,6 +19,7 @@ impl Runtime {
                 Obj::Number(m) => n.to_string() == m.to_string(),
                 _ => false,
             },
+            Obj::ImaginaryUnit(_) => matches!(right, Obj::ImaginaryUnit(_)),
             Obj::Add(a) => match right {
                 Obj::Add(b) => a.to_string() == b.to_string(),
                 _ => false,
@@ -67,6 +68,18 @@ impl Runtime {
                 Obj::Abs(b) => a.to_string() == b.to_string(),
                 _ => false,
             },
+            Obj::RealPart(a) => match right {
+                Obj::RealPart(b) => a.to_string() == b.to_string(),
+                _ => false,
+            },
+            Obj::ImaginaryPart(a) => match right {
+                Obj::ImaginaryPart(b) => a.to_string() == b.to_string(),
+                _ => false,
+            },
+            Obj::ComplexAbs(a) => match right {
+                Obj::ComplexAbs(b) => a.to_string() == b.to_string(),
+                _ => false,
+            },
             Obj::Sqrt(a) => match right {
                 Obj::Sqrt(b) => a.to_string() == b.to_string(),
                 _ => false,
diff --git a/src/verify/verify_equality_by_builtin_rules.rs b/src/verify/verify_equality_by_builtin_rules.rs
--- a/src/verify/verify_equality_by_builtin_rules.rs
+++ b/src/verify/verify_equality_by_builtin_rules.rs
@@ -20,7 +20,7 @@ pub(crate) fn obj_expr_mentions_bare_id_on_two(l: &Obj, r: &Obj, id: &str) -> bo
 pub(crate) fn obj_expr_mentions_bare_id(obj: &Obj, id: &str) -> bool {
     match obj {
         Obj::Atom(AtomObj::Identifier(i)) => i.name == id,
-        Obj::Number(_) | Obj::StandardSet(_) => false,
+        Obj::Number(_) | Obj::ImaginaryUnit(_) | Obj::StandardSet(_) => false,
         Obj::Add(b) => obj_expr_mentions_bare_id_on_two(b.left.as_ref(), b.right.as_ref(), id),
         Obj::Sub(b) => obj_expr_mentions_bare_id_on_two(b.left.as_ref(), b.right.as_ref(), id),
         Obj::Mul(b) => obj_expr_mentions_bare_id_on_two(b.left.as_ref(), b.right.as_ref(), id),
@@ -54,6 +54,9 @@ pub(crate) fn obj_expr_mentions_bare_id(obj: &Obj, id: &str) -> bool {
                 || obj_expr_mentions_bare_id(m.exponent.as_ref(), id)
         }
         Obj::Abs(u) => obj_expr_mentions_bare_id(u.arg.as_ref(), id),
+        Obj::RealPart(u) => obj_expr_mentions_bare_id(u.arg.as_ref(), id),
+        Obj::ImaginaryPart(u) => obj_expr_mentions_bare_id(u.arg.as_ref(), id),
+        Obj::ComplexAbs(u) => obj_expr_mentions_bare_id(u.arg.as_ref(), id),
         Obj::Sqrt(u) => obj_expr_mentions_bare_id(u.arg.as_ref(), id),
         Obj::PowerSet(u) => obj_expr_mentions_bare_id(u.set.as_ref(), id),
         Obj::GeneralCart(g) => {
diff --git a/src/verify/verify_exist_fact_with_known_forall.rs b/src/verify/verify_exist_fact_with_known_forall.rs
--- a/src/verify/verify_exist_fact_with_known_forall.rs
+++ b/src/verify/verify_exist_fact_with_known_forall.rs
@@ -221,7 +221,7 @@ impl Runtime {
     pub(crate) fn obj_depends_on_given_exist_param(obj: &Obj, names: &[String]) -> bool {
         match obj {
             Obj::Atom(AtomObj::Exist(p)) => names.iter().any(|name| name == &p.name),
-            Obj::Atom(_) | Obj::Number(_) | Obj::StandardSet(_) => false,
+            Obj::Atom(_) | Obj::Number(_) | Obj::ImaginaryUnit(_) | Obj::StandardSet(_) => false,
             Obj::Add(x) => Self::obj_pair_depends_on_given_exist_param(
                 x.left.as_ref(),
                 x.right.as_ref(),
@@ -327,6 +327,9 @@ impl Runtime {
                 Self::obj_pair_depends_on_given_exist_param(x.obj.as_ref(), x.index.as_ref(), names)
             }
             Obj::Abs(x) => Self::obj_depends_on_given_exist_param(x.arg.as_ref(), names),
+            Obj::RealPart(x) => Self::obj_depends_on_given_exist_param(x.arg.as_ref(), names),
+            Obj::ImaginaryPart(x) => Self::obj_depends_on_given_exist_param(x.arg.as_ref(), names),
+            Obj::ComplexAbs(x) => Self::obj_depends_on_given_exist_param(x.arg.as_ref(), names),
             Obj::Sqrt(x) => Self::obj_depends_on_given_exist_param(x.arg.as_ref(), names),
             Obj::BigUnion(x) => Self::obj_depends_on_given_exist_param(x.left.as_ref(), names),
             Obj::BigIntersect(x) => Self::obj_depends_on_given_exist_param(x.left.as_ref(), names),
diff --git a/src/verify/verify_obj_well_defined.rs b/src/verify/verify_obj_well_defined.rs
--- a/src/verify/verify_obj_well_defined.rs
+++ b/src/verify/verify_obj_well_defined.rs
@@ -41,13 +41,21 @@ impl Runtime {
             }
             Obj::FnObj(fn_obj) => self.verify_fn_obj_well_defined(fn_obj, verify_state),
             Obj::Number(_) => Ok(()),
+            Obj::ImaginaryUnit(_) => Ok(()),
             Obj::Add(add) => self.verify_add_well_defined(add, verify_state),
             Obj::Sub(sub) => self.verify_sub_well_defined(sub, verify_state),
             Obj::Mul(mul) => self.verify_mul_well_defined(mul, verify_state),
             Obj::Div(div) => self.verify_div_well_defined(div, verify_state),
             Obj::Mod(m) => self.verify_mod_well_defined(m, verify_state),
             Obj::Pow(pow) => self.verify_pow_well_defined(pow, verify_state),
             Obj::Abs(abs) => self.verify_abs_well_defined(abs, verify_state),
+            Obj::RealPart(real_part) => self.verify_real_part_well_defined(real_part, verify_state),
+            Obj::ImaginaryPart(imaginary_part) => {
+                self.verify_imaginary_part_well_defined(imaginary_part, verify_state)
+            }
+            Obj::ComplexAbs(complex_abs) => {
+                self.verify_complex_abs_well_defined(complex_abs, verify_state)
+            }
             Obj::Sqrt(sqrt) => self.verify_sqrt_well_defined(sqrt, verify_state),
             Obj::Log(log) => self.verify_log_well_defined(log, verify_state),
             Obj::Union(x) => self.verify_union_well_defined(x, verify_state),
diff --git a/src/verify/verify_obj_well_defined/core.rs b/src/verify/verify_obj_well_defined/core.rs
--- a/src/verify/verify_obj_well_defined/core.rs
+++ b/src/verify/verify_obj_well_defined/core.rs
@@ -6,13 +6,7 @@ impl Runtime {
         &self,
         identifier: &Identifier,
     ) -> Result<(), RuntimeError> {
-        if identifier.is_builtin(I)
-            || identifier.is_builtin(RE)
-            || identifier.is_builtin(IMG)
-            || identifier.is_builtin(C_ABS)
-        {
-            Ok(())
-        } else if self.is_name_used_for_identifier(&identifier.name) {
+        if self.is_name_used_for_identifier(&identifier.name) {
             Ok(())
         } else if self
             .get_struct_definition_by_name(&identifier.name)
diff --git a/src/verify/verify_obj_well_defined/scalar.rs b/src/verify/verify_obj_well_defined/scalar.rs
--- a/src/verify/verify_obj_well_defined/scalar.rs
+++ b/src/verify/verify_obj_well_defined/scalar.rs
@@ -184,6 +184,36 @@ impl Runtime {
         Ok(())
     }
 
+    pub(in crate::verify) fn verify_real_part_well_defined(
+        &mut self,
+        real_part: &RealPart,
+        verify_state: &VerifyState,
+    ) -> Result<(), RuntimeError> {
+        self.verify_obj_well_defined_and_store_cache(&real_part.arg, verify_state)?;
+        self.require_obj_in_c(&real_part.arg, verify_state)?;
+        Ok(())
+    }
+
+    pub(in crate::verify) fn verify_imaginary_part_well_defined(
+        &mut self,
+        imaginary_part: &ImaginaryPart,
+        verify_state: &VerifyState,
+    ) -> Result<(), RuntimeError> {
+        self.verify_obj_well_defined_and_store_cache(&imaginary_part.arg, verify_state)?;
+        self.require_obj_in_c(&imaginary_part.arg, verify_state)?;
+        Ok(())
+    }
+
+    pub(in crate::verify) fn verify_complex_abs_well_defined(
+        &mut self,
+        complex_abs: &ComplexAbs,
+        verify_state: &VerifyState,
+    ) -> Result<(), RuntimeError> {
+        self.verify_obj_well_defined_and_store_cache(&complex_abs.arg, verify_state)?;
+        self.require_obj_in_c(&complex_abs.arg, verify_state)?;
+        Ok(())
+    }
+
     pub(in crate::verify) fn verify_sqrt_well_defined(
         &mut self,
         sqrt: &Sqrt,
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
