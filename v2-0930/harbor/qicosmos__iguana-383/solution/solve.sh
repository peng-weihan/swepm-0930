#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.github/workflows/clang-format.yml b/.github/workflows/clang-format.yml
--- a/.github/workflows/clang-format.yml
+++ b/.github/workflows/clang-format.yml
@@ -9,21 +9,14 @@ on:
 jobs:
   build:
   
-    runs-on: ubuntu-22.04
+    runs-on: ubuntu-24.04
     
     steps:
       - name: Checkout
         uses: actions/checkout@v3
         with:
           fetch-depth: 0
       - name: install clang-format
-        run: sudo apt install clang-format
+        run: sudo apt-get update && sudo apt-get install -y clang-format-18
       - name: check-diff
-        run : |
-          diff=`git-clang-format --diff HEAD^`
-          if ! [[ "$diff" = "no modified files to format" || "$diff" = "clang-format did not modify any files" ]]; then
-            echo "The diff you sent is not formatted correctly."
-            echo "the suggested format is"
-            echo "$diff"
-            exit 1
-          fi
+        run: scripts/check-clang-format.sh HEAD^
diff --git a/.github/workflows/linux-gcc-cxx26.yml b/.github/workflows/linux-gcc-cxx26.yml
new file mode 100644
--- /dev/null
+++ b/.github/workflows/linux-gcc-cxx26.yml
@@ -0,0 +1,44 @@
+name: Ubuntu (gcc c++26)
+
+on:
+  push:
+    branches: [ master, struct_pb ]
+  pull_request:
+    branches: [ master, struct_pb ]
+
+jobs:
+  ubuntu_gcc16_cxx26:
+    runs-on: ubuntu-22.04
+    container: gcc:16.1.0-trixie
+
+    steps:
+    - name: check out
+      uses: actions/checkout@v4
+
+    - name: Install dependencies
+      run: |
+        apt-get update
+        apt-get install -y --no-install-recommends \
+          cmake \
+          make \
+          protobuf-compiler \
+          libprotobuf-dev
+
+    - name: Check compiler version
+      run: |
+        gcc --version
+        g++ --version
+        g++ -std=gnu++26 -freflection -x c++ -c -o /tmp/reflection.o - <<'CPP'
+        #include <meta>
+        struct probe { int value; };
+        static_assert(std::meta::identifier_of(^^probe) == "probe");
+        CPP
+
+    - name: configure cmake
+      run: CXX=g++ CC=gcc cmake -S "$GITHUB_WORKSPACE" -B "$GITHUB_WORKSPACE/build_cpp26" -DCMAKE_BUILD_TYPE=Release -DENABLE_CXX26_REFLECTION=ON
+
+    - name: build project
+      run: cmake --build "$GITHUB_WORKSPACE/build_cpp26" --config Release -j 2
+
+    - name: test
+      run: ctest --test-dir "$GITHUB_WORKSPACE/build_cpp26" --output-on-failure -j 2
diff --git a/.gitignore b/.gitignore
--- a/.gitignore
+++ b/.gitignore
@@ -29,10 +29,14 @@
 *.app
 
 build
+build*
+out/
 .vscode
 .idea
 cmake-*
 .cache
 .vs/
 CMakeUserPresets.json
 /CMakeSettings.json
+/NestedMsg.proto
+/test_vector.proto
diff --git a/CMakeLists.txt b/CMakeLists.txt
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -64,6 +64,24 @@ if(CMAKE_COMPILER_IS_GNUCXX)
 link_libraries(stdc++fs)
 endif()
 
+function(iguana_fast_validation_target target)
+    if(MSVC)
+        target_compile_options(${target} PRIVATE "$<$<CONFIG:Release>:/Od;/Ob0>")
+    else()
+        target_compile_options(${target} PRIVATE "$<$<CONFIG:Release>:-O0>")
+    endif()
+endfunction()
+
+option(IGUANA_FAST_BENCHMARK_COMPILE
+       "Compile benchmark targets with low optimization for faster validation builds"
+       OFF)
+
+function(iguana_fast_benchmark_target target)
+    if(IGUANA_FAST_BENCHMARK_COMPILE)
+        iguana_fast_validation_target(${target})
+    endif()
+endfunction()
+
 set(JSON_EXAMPLE
 	example/json_example.cpp
 )
@@ -78,6 +96,7 @@ set(YAML_EXAMPLE
 set(TEST_SOME test/test_some.cpp)
 set(TEST_UT test/unit_test.cpp)
 set(TEST_JSON_FILES test/test_json_files.cpp)
+set(TEST_GITHUB_EVENTS test/test_github_events.cpp)
 set(TEST_XML test/test_xml.cpp)
 set(JSONBENCHMARK benchmark/json_benchmark.cpp)
 set(XMLBENCH  benchmark/xml_benchmark.cpp)
@@ -89,13 +108,15 @@ set(TEST_XMLNOTHROW test/test_xml_nothrow.cpp)
 set(TEST_PB test/test_pb.cpp)
 set(TEST_PROTO test/test_proto3.cpp)
 set(TEST_CPP20 test/test_cpp20.cpp)
+set(TEST_CONFORMANCE test/conformance/iguana_conformance.cpp)
 set(PB_BENCHMARK benchmark/pb_benchmark.cpp)
 
 add_executable(json_example 	${JSON_EXAMPLE})
 add_executable(json_benchmark 	${JSONBENCHMARK})
 add_executable(test_some	${TEST_SOME})
 add_executable(test_ut 	${TEST_UT})
 add_executable(test_json_files 	${TEST_JSON_FILES})
+add_executable(test_github_events ${TEST_GITHUB_EVENTS})
 add_executable(xml_example 		${XML_EXAMPLE})
 add_executable(test_xml ${TEST_XML})
 add_executable(xml_benchmark ${XMLBENCH})
@@ -107,15 +128,29 @@ add_executable(test_nothrow ${TEST_NOTHROW})
 add_executable(test_util ${TEST_UTIL})
 add_executable(test_pb ${TEST_PB})
 add_executable(test_cpp20 ${TEST_CPP20})
+add_executable(iguana_conformance ${TEST_CONFORMANCE})
 set_target_properties(test_cpp20 PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)
 
+foreach(tgt json_benchmark xml_benchmark yaml_benchmark)
+    iguana_fast_benchmark_target(${tgt})
+endforeach()
+
+foreach(tgt json_example xml_example yaml_example
+            test_some test_ut test_json_files test_github_events test_xml test_xml_nothrow
+            test_yaml test_nothrow test_util test_pb test_cpp20
+            iguana_conformance)
+    iguana_fast_validation_target(${tgt})
+endforeach()
+
 if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
     if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER 9)
         message(STATUS "GCC version ${CMAKE_CXX_COMPILER_VERSION}")
         add_executable(test_reflection test/test_reflection.cpp)
+        iguana_fast_validation_target(test_reflection)
     endif()
 else()
     add_executable(test_reflection test/test_reflection.cpp)
+    iguana_fast_validation_target(test_reflection)
 endif()
 
 
@@ -140,8 +175,10 @@ if(Protobuf_FOUND)
     
     add_executable(pb_benchmark ${PB_BENCHMARK} ${PROTO_SRCS})
     target_link_libraries(pb_benchmark ${Protobuf_LIBRARIES})
+    iguana_fast_benchmark_target(pb_benchmark)
     add_executable(test_proto ${PROTO_SRCS} ${TEST_PROTO})
     target_link_libraries(test_proto ${Protobuf_LIBRARIES})
+    iguana_fast_validation_target(test_proto)
     add_test(NAME test_proto COMMAND test_proto)
 endif()
 
@@ -164,10 +201,55 @@ endif()
 add_test(NAME test_some COMMAND test_some)
 add_test(NAME test_ut COMMAND test_ut)
 add_test(NAME test_json_files COMMAND test_json_files)
+add_test(NAME test_github_events COMMAND test_github_events)
 add_test(NAME test_xml COMMAND test_xml)
 add_test(NAME test_yaml COMMAND test_yaml)
 add_test(NAME test_nothrow COMMAND test_nothrow)
 add_test(NAME test_util COMMAND test_util)
 add_test(NAME test_xml_nothrow COMMAND test_xml_nothrow)
 add_test(NAME test_pb COMMAND test_pb)
 add_test(NAME test_cpp20 COMMAND test_cpp20)
+set_tests_properties(test_json_files PROPERTIES
+    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/test")
+set_tests_properties(test_github_events PROPERTIES
+    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/test")
+
+set(PROTOBUF_CONFORMANCE_RUNNER "" CACHE FILEPATH "Path to protobuf conformance_test_runner")
+if(PROTOBUF_CONFORMANCE_RUNNER)
+    add_test(NAME iguana_conformance_runner
+        COMMAND ${PROTOBUF_CONFORMANCE_RUNNER} --enforce_recommended $<TARGET_FILE:iguana_conformance>)
+endif()
+
+# C++26 static reflection tests (requires GCC 16+ with -freflection)
+option(ENABLE_CXX26_REFLECTION "Build tests with C++26 static reflection (requires GCC 16+)" OFF)
+if (ENABLE_CXX26_REFLECTION)
+    message(STATUS "Building with C++26 static reflection")
+    execute_process(
+        COMMAND ${CMAKE_CXX_COMPILER} -print-file-name=libstdc++.so
+        OUTPUT_VARIABLE CXX26_LIBSTDCXX
+        OUTPUT_STRIP_TRAILING_WHITESPACE
+        ERROR_QUIET)
+    if(CXX26_LIBSTDCXX AND EXISTS "${CXX26_LIBSTDCXX}")
+        get_filename_component(CXX26_LIBSTDCXX_DIR "${CXX26_LIBSTDCXX}" DIRECTORY)
+    endif()
+    foreach(tgt test_some test_ut test_json_files test_github_events test_xml
+                test_yaml test_nothrow test_util test_xml_nothrow test_pb
+                test_reflection)
+        if(TARGET ${tgt})
+            set(tgt26 ${tgt}_cpp26)
+            get_target_property(tgt_sources ${tgt} SOURCES)
+            add_executable(${tgt26} ${tgt_sources})
+            target_compile_options(${tgt26} PRIVATE -std=gnu++26 -freflection)
+            iguana_fast_validation_target(${tgt26})
+            if(CXX26_LIBSTDCXX_DIR)
+                set_property(TARGET ${tgt26} APPEND_STRING PROPERTY LINK_FLAGS
+                    " -Wl,-rpath,${CXX26_LIBSTDCXX_DIR}")
+            endif()
+            add_test(NAME ${tgt26} COMMAND ${tgt26})
+            if(tgt STREQUAL test_json_files OR tgt STREQUAL test_github_events)
+                set_tests_properties(${tgt26} PROPERTIES
+                    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/test")
+            endif()
+        endif()
+    endforeach()
+endif()
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -6,6 +6,7 @@
 |------------------------------------------------|----------------------------------------------------------------------------------------------------------|
 | Ubuntu 22.04 (clang 14.0.0)                    | ![win](https://github.com/qicosmos/iguana/actions/workflows/linux-clang.yml/badge.svg?branch=master) |
 | Ubuntu 22.04 (gcc 11.2.0)                      | ![win](https://github.com/qicosmos/iguana/actions/workflows/linux-gcc.yml/badge.svg?branch=master)   |
+| GCC 16.1.0 container (C++26 reflection)         | ![win](https://github.com/qicosmos/iguana/actions/workflows/linux-gcc-cxx26.yml/badge.svg?branch=master) |
 | macOS Monterey latest (AppleClang latest) | ![win](https://github.com/qicosmos/iguana/actions/workflows/mac.yml/badge.svg?branch=master)         |
 | Windows Server 2022 (MSVC 19.33.31630.0)       | ![win](https://github.com/qicosmos/iguana/actions/workflows/windows.yml/badge.svg?branch=master)     |
 
@@ -15,6 +16,8 @@ qq 交流群 701594518
 
 [struct_pb](lang/struct_pb_intro.md)
 
+[C++26 reflection/proto3 change notes](iguana_reflect26_changes.md)
+
 ### Motivation ###
 Serialize an object to any other format data with compile-time reflection, such as json, xml, binary, table and so on.
 This library is designed to unify and simplify serialization in a portable cross-platform manner. This library is also easy to extend, and you can serialize any format of data with the library.
@@ -30,6 +33,47 @@ This library provides a portable cross-platform way of:
 
 [reflection lib introduction](lang/reflection_introduction.md)
 
+With a C++26 static reflection compiler, iguana can read class members directly
+from the language reflection API. The CI job for this path uses the official
+`gcc:16.1.0-trixie` container with `-std=gnu++26 -freflection` and configures
+CMake with `-DENABLE_CXX26_REFLECTION=ON`.
+
+Useful C++26 annotations:
+
+```cpp
+namespace r26 = ylt::reflection::reflect26;
+
+struct [[= r26::struct_name<"user">{}]] user_t {
+  [[= r26::field_name<"id">{}]]
+  int user_id{};
+
+  std::string name;
+
+  [[= r26::skip_field{}]]
+  int local_cache{};
+};
+
+struct base_t {
+  int internal_state{};
+};
+
+struct derived_t : [[= r26::skip_base{}]] base_t {
+  int value{};
+};
+
+struct xml_user_t {
+  [[= r26::field_name<"identifier">{}]]
+  [[= iguana::xml_required{}]]
+  int id{};
+};
+```
+
+`field_name` changes the serialized field name for JSON/XML/YAML and generated
+protobuf schema. `struct_name` changes XML root names. `skip_field` excludes a
+member from reflection, and `skip_base` excludes a base class from recursive
+member collection. `xml_required` is the C++26 annotation form of the XML
+`REQUIRED(type, fields...)` macro.
+
 ### Tutorial ###
 This Tutorial is provided to give you a view of how *iguana* works for serialization. 
 
@@ -332,7 +376,9 @@ iguana::to_json(e1, ss);
 ```
 
 ### Serialization of protobuf
-similar with before:
+
+Basic protobuf serialization uses the same object API:
+
 ```cpp
 struct person {
   int id;
@@ -356,7 +402,160 @@ void test() {
   CHECK(p == p1);
 }
 ```
-[more detail](lang/struct_pb_intro.md)
+
+By default, protobuf field numbers follow member order. For stable schemas or
+interop with existing `.proto` files, specify field numbers explicitly. On the
+legacy/non-C++26 path, `YLT_REFL_PB` remains available:
+
+```cpp
+struct account {
+  std::string name;
+  int32_t age;
+  std::vector<std::string> emails;
+};
+
+YLT_REFL_PB(account, (name, 10), (age, 20), (emails, 9));
+```
+
+With C++26 static reflection, prefer the `[[= iguana::pb_field(N)]]`
+annotation shown below; that path reads protobuf metadata from annotations and
+does not depend on `YLT_REFL_PB`.
+
+For advanced proto3 wire semantics on the non-C++26 path, use the descriptor
+helpers. The helper form keeps normal C++ field types while attaching protobuf
+schema metadata:
+
+```cpp
+struct event_msg {
+  int32_t id{};
+  std::string payload;
+  int32_t delta{};
+  uint32_t checksum{};
+  std::chrono::system_clock::time_point created_at{};
+  std::chrono::nanoseconds timeout{};
+  std::optional<int32_t> retry_count;
+  std::variant<std::monostate, int32_t, std::string> result;
+  std::string unknown;
+};
+
+inline auto get_members_impl(event_msg*) {
+  return iguana::pb_members(
+      iguana::pb_field<&event_msg::id, 1>("id"),
+      iguana::pb_bytes_field<&event_msg::payload, 3>("payload"),
+      iguana::pb_zigzag_field<&event_msg::delta, 5>("delta"),
+      iguana::pb_optional_field<&event_msg::retry_count, 6>("retry_count"),
+      iguana::pb_fixed_field<&event_msg::checksum, 7>("checksum"),
+      iguana::as_timestamp_field<&event_msg::created_at, 8>("created_at"),
+      iguana::as_duration_field<&event_msg::timeout, 9>("timeout"),
+      iguana::pb_oneof_field<&event_msg::result, 10, 12>("result"),
+      iguana::pb_unknown_fields_field<&event_msg::unknown>("unknown"));
+}
+```
+
+Helper APIs:
+
+| Helper | Meaning |
+| --- | --- |
+| `pb_members(...)` | Returns the protobuf descriptor tuple from `get_members_impl(T*)`. |
+| `pb_field<&T::field, N>("name")` | Sets a protobuf field number and schema name. |
+| `pb_bytes_field` | Emits `bytes`; the C++ field is `std::string` or `std::string_view`, including optional/vector forms. |
+| `pb_zigzag_field` | Emits `sint32` or `sint64`; the C++ field remains `int32_t` or `int64_t`, including optional/vector forms. |
+| `pb_fixed_field` | Emits `fixed32`, `fixed64`, `sfixed32`, or `sfixed64` for 32/64-bit integer fields, including optional/vector forms. |
+| `pb_optional_field` | Emits proto3 `optional`; the C++ field must be `std::optional<T>`. |
+| `pb_timestamp_field` / `as_timestamp_field` | Encodes `std::chrono::system_clock::time_point` as `google.protobuf.Timestamp`, including optional/vector forms. |
+| `pb_duration_field` / `as_duration_field` | Encodes `std::chrono::nanoseconds` as `google.protobuf.Duration`, including optional/vector forms. |
+| `pb_oneof_field<&T::field, Ns...>("name")` | Maps `std::variant<std::monostate, ...>` alternatives to oneof field numbers. |
+| `pb_unknown_fields_field<&T::field>()` | Preserves unknown protobuf wire bytes in a single `std::string` field. |
+
+The explicit wrapper types `iguana::pb_timestamp` and `iguana::pb_duration`
+remain available when code wants the wire-shaped representation directly.
+
+`pb_field_ex` can combine options. Supported options are `pb_bytes`,
+`pb_zigzag`, `pb_fixed`, `pb_optional`, `pb_as_timestamp`/`as_timestamp`, and
+`pb_as_duration`/`as_duration`.
+
+```cpp
+iguana::pb_field_ex<&event_msg::retry_count, 6>(
+    "retry_count", iguana::pb_optional, iguana::pb_zigzag);
+```
+
+With a C++26 reflection compiler, the same metadata can be written as
+annotations without `YLT_REFL_PB`. The current C++26 test build uses GCC 16.1 with
+`-std=gnu++26 -freflection`.
+
+```cpp
+struct event_msg26 {
+  [[= iguana::pb_field(1)]] int32_t id{};
+
+  [[= iguana::pb_field(3)]]
+  [[= iguana::pb_bytes]]
+  std::string payload;
+
+  [[= iguana::pb_field(5)]]
+  [[= iguana::pb_zigzag]]
+  int32_t delta{};
+
+  [[= iguana::pb_field(6)]]
+  [[= iguana::pb_optional]]
+  std::optional<int32_t> retry_count;
+
+  [[= iguana::pb_field(7)]]
+  [[= iguana::pb_fixed]]
+  uint32_t checksum{};
+
+  [[= iguana::pb_field(8)]]
+  [[= iguana::as_timestamp]]
+  std::chrono::system_clock::time_point created_at{};
+
+  [[= iguana::pb_field(9)]]
+  [[= iguana::as_duration]]
+  std::chrono::nanoseconds timeout{};
+
+  [[= iguana::pb_oneof<10, 12>]]
+  std::variant<std::monostate, int32_t, std::string> result;
+
+  [[= iguana::pb_unknown_fields]]
+  std::string unknown;
+};
+```
+
+C++26 annotation equivalents:
+
+| Annotation | Meaning |
+| --- | --- |
+| `[[= iguana::pb_field(N)]]` | Sets the protobuf field number. |
+| `[[= iguana::pb_bytes]]` | Same as `pb_bytes_field`. |
+| `[[= iguana::pb_zigzag]]` | Same as `pb_zigzag_field`. |
+| `[[= iguana::pb_fixed]]` | Same as `pb_fixed_field`. |
+| `[[= iguana::pb_optional]]` | Same as `pb_optional_field`. |
+| `[[= iguana::pb_oneof<N...>]]` / `[[= iguana::oneof<N...>]]` | Same as `pb_oneof_field`. |
+| `[[= iguana::as_timestamp]]` / `[[= iguana::pb_as_timestamp]]` | Same as `as_timestamp_field` / `pb_timestamp_field`. |
+| `[[= iguana::as_duration]]` / `[[= iguana::pb_as_duration]]` | Same as `as_duration_field` / `pb_duration_field`. |
+| `[[= iguana::pb_unknown_fields]]` | Same as `pb_unknown_fields_field`. |
+
+Supported proto3 wire metadata includes custom field numbers, `bytes`,
+`sint32/sint64` zigzag encoding, fixed-width integers, explicit optional
+presence, oneof, `google.protobuf.Timestamp`, `google.protobuf.Duration`, and
+unknown field preservation. Repeated primitive fields accept packed, unpacked,
+and mixed input; writers use proto3 default packed output where applicable.
+
+Field numbers must be in `[1, 2^29 - 1]` and cannot be in protobuf's reserved
+`[19000, 19999]` range. A message can have at most one unknown-field storage
+member, and it must be a `std::string`.
+
+Generate a `.proto` view of a struct with:
+
+```cpp
+std::string schema;
+iguana::to_proto<event_msg>(schema, "demo");
+```
+
+The current conformance target covers the proto3 binary/protobuf-output
+wire-only subset. JSON mapping, text format, proto2, extensions, services, and
+custom options are outside this scope.
+
+[more detail](lang/struct_pb_intro.md) and
+[change notes](iguana_reflect26_changes.md)
 
 ### Full sources:
 
@@ -475,4 +674,4 @@ frozen lib
 ### Update
 
 1. Support C++20 and C++17
-2. Refactor json reader, modification based on glaze  [json/read.hpp](https://github.com/stephenberry/glaze/blob/main/include/glaze/json/read.hpp)
\ No newline at end of file
+2. Refactor json reader, modification based on glaze  [json/read.hpp](https://github.com/stephenberry/glaze/blob/main/include/glaze/json/read.hpp)
diff --git a/benchmark/pb_benchmark.cpp b/benchmark/pb_benchmark.cpp
--- a/benchmark/pb_benchmark.cpp
+++ b/benchmark/pb_benchmark.cpp
@@ -1,5 +1,10 @@
 #include <google/protobuf/arena.h>
 #define SEQUENTIAL_PARSE
+#include <cstdlib>
+#include <iomanip>
+#include <iostream>
+#include <limits>
+
 #include "../test/proto/unittest_proto3.h"
 #include "iguana/iguana.hpp"
 
@@ -27,6 +32,26 @@ class ScopedTimer {
   uint64_t *m_ns = nullptr;
 };
 
+void print_compare(const char *name, uint64_t iguana_ns, uint64_t protobuf_ns) {
+  double ratio = protobuf_ns == 0 ? 0.0
+                                  : static_cast<double>(iguana_ns) /
+                                        static_cast<double>(protobuf_ns);
+  std::cout << std::left << std::setw(45) << name << " : iguana/protobuf "
+            << std::right << std::fixed << std::setprecision(3) << ratio << "x";
+  if (protobuf_ns != 0) {
+    if (iguana_ns < protobuf_ns) {
+      std::cout << " (iguana faster)";
+    }
+    else if (iguana_ns > protobuf_ns) {
+      std::cout << " (protobuf faster)";
+    }
+    else {
+      std::cout << " (tie)";
+    }
+  }
+  std::cout << "\n";
+}
+
 void bench(int Count) {
   // init the benchmark data
   stpb::BaseTypeMsg base_type_st{std::numeric_limits<int32_t>::max(),
@@ -146,8 +171,9 @@ void bench(int Count) {
   std::string nest_st_ss;
   std::string map_st_ss;
   std::string base_one_of_st_ss;
+  uint64_t iguana_many_serialize_ns = 0;
   {
-    ScopedTimer timer("struct_pb many serialize");
+    ScopedTimer timer("struct_pb many serialize", iguana_many_serialize_ns);
     for (int i = 0; i < Count; ++i) {
       iguana::to_pb(base_type_st, base_type_st_ss);
       iguana::to_pb(iguana_type_st, iguana_type_st_ss);
@@ -166,9 +192,10 @@ void bench(int Count) {
   std::string nest_msg_ss;
   std::string map_msg_ss;
   std::string base_one_of_msg_ss;
+  uint64_t protobuf_many_serialize_ns = 0;
   // protobuf serialization benchmark
   {
-    ScopedTimer timer("protobuf many serialize");
+    ScopedTimer timer("protobuf many serialize", protobuf_many_serialize_ns);
     for (int i = 0; i < Count; ++i) {
       base_type_msg.SerializeToString(&base_type_msg_ss);
       iguana_type_msg.SerializeToString(&iguana_type_msg_ss);
@@ -179,18 +206,21 @@ void bench(int Count) {
       base_one_of_msg.SerializeToString(&base_one_of_msg_ss);
     }
   }
+  print_compare("many serialize compare", iguana_many_serialize_ns,
+                protobuf_many_serialize_ns);
 
   // ensure serialize correction
   assert(base_type_st_ss == base_type_msg_ss);
   assert(iguana_type_st_ss == iguana_type_msg_ss);
   assert(re_base_type_st_ss == re_base_type_msg_ss);
   assert(re_iguana_type_st_ss == re_iguana_type_msg_ss);
   assert(nest_st_ss == nest_msg_ss);
-  assert(map_st_ss == map_st_ss);
+  assert(map_st_ss.size() == map_msg_ss.size());
   assert(base_one_of_st_ss == base_one_of_msg_ss);
   // iguana deserialization benchmark
+  uint64_t iguana_many_deserialize_ns = 0;
   {
-    ScopedTimer timer("struct_pb many deserialize");
+    ScopedTimer timer("struct_pb many deserialize", iguana_many_deserialize_ns);
     for (int i = 0; i < Count; ++i) {
       stpb::BaseTypeMsg base_type_st_de;
       iguana::from_pb(base_type_st_de, base_type_st_ss);
@@ -216,8 +246,10 @@ void bench(int Count) {
   }
 
   // protobuf deserialization benchmark
+  uint64_t protobuf_many_deserialize_ns = 0;
   {
-    ScopedTimer timer("protobuf many deserialize");
+    ScopedTimer timer("protobuf many deserialize",
+                      protobuf_many_deserialize_ns);
     for (int i = 0; i < Count; ++i) {
       pb::BaseTypeMsg base_type_msg_de;
       base_type_msg_de.ParseFromString(base_type_msg_ss);
@@ -241,6 +273,8 @@ void bench(int Count) {
       base_one_of_msg_de.ParseFromString(base_one_of_msg_ss);
     }
   }
+  print_compare("many deserialize compare", iguana_many_deserialize_ns,
+                protobuf_many_deserialize_ns);
 
   // ensure deserialize correction
   stpb::BaseTypeMsg base_type_st_de{};
@@ -315,32 +349,43 @@ void bench2(int Count) {
   iguana::to_pb(simple, sp_str);
 
   // serialize
+  uint64_t iguana_simple_serialize_ns = 0;
   {
-    ScopedTimer timer("struct_pb simple serialize");
+    ScopedTimer timer("struct_pb simple serialize", iguana_simple_serialize_ns);
     for (int j = 0; j < Count; j++) iguana::to_pb(simple, sp_str);
   }
 
+  uint64_t protobuf_simple_serialize_ns = 0;
   {
-    ScopedTimer timer("protobuf simple serialize ");
+    ScopedTimer timer("protobuf simple serialize ",
+                      protobuf_simple_serialize_ns);
     for (int j = 0; j < Count; j++) pb_simple.SerializeToString(&pb_str);
   }
+  print_compare("simple serialize compare", iguana_simple_serialize_ns,
+                protobuf_simple_serialize_ns);
 
   // deserialize
+  uint64_t iguana_simple_deserialize_ns = 0;
   {
-    ScopedTimer timer("struct_pb simple deserialize");
+    ScopedTimer timer("struct_pb simple deserialize",
+                      iguana_simple_deserialize_ns);
     for (int j = 0; j < Count; j++) {
       stpb::simple_t s;
       iguana::from_pb(s, sp_str);
     }
   }
 
+  uint64_t protobuf_simple_deserialize_ns = 0;
   {
-    ScopedTimer timer("protobuf simple deserialize");
+    ScopedTimer timer("protobuf simple deserialize",
+                      protobuf_simple_deserialize_ns);
     for (int j = 0; j < Count; j++) {
       pb::Simple pb;
       pb.ParseFromString(pb_str);
     }
   }
+  print_compare("simple deserialize compare", iguana_simple_deserialize_ns,
+                protobuf_simple_deserialize_ns);
 
   {
     ScopedTimer timer("struct_pb simple deserialize view");
@@ -362,32 +407,44 @@ void bench3(int Count) {
   iguana::to_pb(sp_monster, sp_str);
 
   // serialize
+  uint64_t iguana_monster_serialize_ns = 0;
   {
-    ScopedTimer timer("struct_pb monster serialize");
+    ScopedTimer timer("struct_pb monster serialize",
+                      iguana_monster_serialize_ns);
     for (int j = 0; j < Count; j++) iguana::to_pb(sp_monster, sp_str);
   }
 
+  uint64_t protobuf_monster_serialize_ns = 0;
   {
-    ScopedTimer timer("protobuf monster serialize ");
+    ScopedTimer timer("protobuf monster serialize ",
+                      protobuf_monster_serialize_ns);
     for (int j = 0; j < Count; j++) pb_monster.SerializeToString(&pb_str);
   }
+  print_compare("monster serialize compare", iguana_monster_serialize_ns,
+                protobuf_monster_serialize_ns);
 
   // deserialize
+  uint64_t iguana_monster_deserialize_ns = 0;
   {
-    ScopedTimer timer("struct_pb monster deserialize");
+    ScopedTimer timer("struct_pb monster deserialize",
+                      iguana_monster_deserialize_ns);
     for (int j = 0; j < Count; j++) {
       stpb::Monster s;
       iguana::from_pb(s, sp_str);
     }
   }
 
+  uint64_t protobuf_monster_deserialize_ns = 0;
   {
-    ScopedTimer timer("protobuf monster deserialize");
+    ScopedTimer timer("protobuf monster deserialize",
+                      protobuf_monster_deserialize_ns);
     for (int j = 0; j < Count; j++) {
       mygame::Monster pb;
       pb.ParseFromString(pb_str);
     }
   }
+  print_compare("monster deserialize compare", iguana_monster_deserialize_ns,
+                protobuf_monster_deserialize_ns);
 }
 
 void bench4(int Count) {
@@ -405,29 +462,43 @@ void bench4(int Count) {
   iguana::to_pb(st_num, st_str);
 
   // deserialize
+  uint64_t iguana_int32_deserialize_ns = 0;
   {
-    ScopedTimer timer("struct_pb int32 deserialize");
+    ScopedTimer timer("struct_pb int32 deserialize",
+                      iguana_int32_deserialize_ns);
     for (int j = 0; j < Count; j++) {
       stpb::bench_int32 s;
       iguana::from_pb(s, st_str);
     }
   }
 
+  uint64_t protobuf_int32_deserialize_ns = 0;
   {
-    ScopedTimer timer("protobuf int32 deserialize");
+    ScopedTimer timer("protobuf int32 deserialize",
+                      protobuf_int32_deserialize_ns);
     for (int j = 0; j < Count; j++) {
       mygame::bench_int32 pb;
       pb.ParseFromString(pb_str);
     }
   }
+  print_compare("int32 deserialize compare", iguana_int32_deserialize_ns,
+                protobuf_int32_deserialize_ns);
 }
 
-int main() {
-  bench(100000);
+int main(int argc, char **argv) {
+  int count = 100000;
+  if (argc > 1) {
+    count = std::atoi(argv[1]);
+    if (count <= 0) {
+      count = 100000;
+    }
+  }
+  std::cout << "protobuf benchmark iterations: " << count << "\n";
+  bench(count);
   std::cout << "----------------------------------------\n";
-  bench2(100000);
+  bench2(count);
   std::cout << "----------------------------------------\n";
-  bench3(100000);
+  bench3(count);
   std::cout << "----------------------------------------\n";
-  bench4(100000);
+  bench4(count);
 }
diff --git a/compile_time_analysis.md b/compile_time_analysis.md
new file mode 100644
--- /dev/null
+++ b/compile_time_analysis.md
@@ -0,0 +1,777 @@
+# Iguana 全量编译时间分析
+
+日期：2026-05-31
+
+本文档记录本地 MSVC 环境下的全量构建基线、热点定位、已验证的优化原型，以及下一步建议。这里的“全量构建”指当前 CMake 默认行为：同时构建 tests、examples 和 benchmarks，而不是只构建一个 header-only 库目标。
+
+## 测试环境
+
+| 项目 | 值 |
+| --- | --- |
+| 仓库目录 | `D:\code\iguana` |
+| CMake 生成器 | Visual Studio 17 2022 |
+| 构建配置 | Release |
+| 并行度 | `--parallel 12` |
+| CMake | 4.0.3 |
+| Visual Studio | VS 2022 Community 17.14.16 |
+| MSVC toolset | 14.44.35207 |
+| 编译器 | MSVC 19.44.35217 |
+| 默认 C++ 标准 | C++17 |
+
+说明：当前实测数据来自 MSVC。本计划后续需要把 GCC 和 Clang 纳入同一套复测矩阵，因为三类编译器在模板实例化、优化器耗时、PCH 和缓存上的行为差异很大。
+
+基线测试命令：
+
+```powershell
+cmake -S . -B out\perf_base_vs -G "Visual Studio 17 2022" -A x64
+cmake --build out\perf_base_vs --config Release --parallel 12 -- /v:minimal
+```
+
+## 当前基线
+
+| 步骤 | 耗时 |
+| --- | ---: |
+| CMake 配置 | 11.20 s |
+| Release 全量构建 | 164.87 s |
+| 配置 + 构建合计 | 176.07 s |
+
+当前全量构建会生成 18 个可执行目标：
+
+```text
+iguana_conformance
+json_benchmark
+json_example
+test_cpp20
+test_json_files
+test_nothrow
+test_pb
+test_reflection
+test_some
+test_ut
+test_util
+test_xml
+test_xml_nothrow
+test_yaml
+xml_benchmark
+xml_example
+yaml_benchmark
+yaml_example
+```
+
+目标：把 `164.87 s` 的 Release 全量构建时间至少降低 50%，也就是降到 `82.44 s` 或更低。
+
+## 热点排序
+
+下面的数据是用 MSVC Release 风格参数逐个编译源文件得到的。绝对时间包含每次启动 VS 开发环境的开销，所以更适合用于判断热点排序，而不是精确归因到最终构建墙钟时间。
+
+| 排名 | 源文件 | 耗时 |
+| ---: | --- | ---: |
+| 1 | `test/test_json_files.cpp` | 42.02 s |
+| 2 | `test/test_pb.cpp` | 38.59 s |
+| 3 | `benchmark/json_benchmark.cpp` | 35.48 s |
+| 4 | `test/test_yaml.cpp` | 29.83 s |
+| 5 | `test/test_xml.cpp` | 28.28 s |
+| 6 | `test/unit_test.cpp` | 24.56 s |
+| 7 | `test/test_some.cpp` | 22.05 s |
+| 8 | `example/yaml_example.cpp` | 12.34 s |
+| 9 | `example/xml_example.cpp` | 12.32 s |
+| 10 | `benchmark/xml_benchmark.cpp` | 8.70 s |
+| 11 | `test/test_xml_nothrow.cpp` | 8.30 s |
+| 12 | `benchmark/yaml_benchmark.cpp` | 8.12 s |
+| 13 | `test/test_yaml_nothrow.cpp` | 7.36 s |
+| 14 | `test/test_yaml_bech.cpp` | 6.28 s |
+| 15 | `example/json_example.cpp` | 6.06 s |
+| 16 | `test/test_reflection.cpp` | 5.07 s |
+| 17 | `test/test_cpp20.cpp` | 4.22 s |
+| 18 | `test/test_util.cpp` | 4.14 s |
+| 19 | `test/conformance/iguana_conformance.cpp` | 3.28 s |
+
+最慢的文件都不是库产物本身，而是测试或 benchmark 源文件。这些文件 include 了大量 header-only 模板代码，并在每个翻译单元里触发实例化。
+
+## 关键验证：优化级别是主要瓶颈
+
+对最慢的几个翻译单元分别用 `/O2` 和 `/Od` 编译，结果如下：
+
+| 源文件 | `/O2` | `/Od` | 降幅 |
+| --- | ---: | ---: | ---: |
+| `test/test_json_files.cpp` | 36.82 s | 11.93 s | 67.6% |
+| `test/test_pb.cpp` | 36.61 s | 12.99 s | 64.5% |
+| `benchmark/json_benchmark.cpp` | 33.40 s | 11.67 s | 65.1% |
+| `test/test_yaml.cpp` | 26.52 s | 6.01 s | 77.3% |
+| `test/test_xml.cpp` | 25.14 s | 5.67 s | 77.4% |
+| `test/unit_test.cpp` | 23.33 s | 9.20 s | 60.6% |
+| `test/test_some.cpp` | 20.99 s | 6.24 s | 70.3% |
+
+这个结果说明：全量 Release 构建慢的主要原因不是单纯的 include 数量，而是 **MSVC 在模板重代码上做 `/O2` 优化非常耗时**。测试程序并不需要优化后的机器码才能验证语义，因此它们是最适合降优化级别的对象。
+
+## 全量 no-opt 原型验证
+
+为了确认这个方向能影响全量墙钟时间，做了一个最小原型：保持当前 18 个目标都构建，只把 Release flags 改成 `/Od /Ob0 /DNDEBUG`。
+
+验证命令：
+
+```powershell
+cmake -S . -B out\perf_od_vs -G "Visual Studio 17 2022" -A x64 `
+  -DCMAKE_CXX_FLAGS_RELEASE="/Od /Ob0 /DNDEBUG"
+cmake --build out\perf_od_vs --config Release --parallel 12 -- /v:minimal
+```
+
+结果：
+
+| 场景 | 配置耗时 | 构建耗时 | 相对基线 |
+| --- | ---: | ---: | ---: |
+| 当前 Release 全量构建 | 11.20 s | 164.87 s | 基线 |
+| 全部目标 `/Od` 原型 | 7.98 s | 32.24 s | 降低 80.4% |
+
+这个原型不是最终方案，因为 benchmarks 如果要用于性能测试，应该继续用优化编译。但它证明了核心判断：**只要避免把测试和示例按 `/O2` 编译，全量构建时间就能大幅下降**。
+
+## 推荐方案实测结果
+
+已验证的推荐方案：
+
+| 目标类别 | Release 编译策略 |
+| --- | --- |
+| tests | `/Od /Ob0` |
+| examples | `/Od /Ob0` |
+| conformance runner | `/Od /Ob0` |
+| benchmarks | 保持 Release 优化 |
+
+复测命令：
+
+```powershell
+cmake -S . -B out\perf_fast_validation_vs -G "Visual Studio 17 2022" -A x64
+cmake --build out\perf_fast_validation_vs --config Release --parallel 12 -- /v:minimal
+ctest --test-dir out\perf_fast_validation_vs -C Release --output-on-failure -j 1
+```
+
+复测结果：
+
+| 场景 | 配置耗时 | 构建耗时 | 相对基线 |
+| --- | ---: | ---: | ---: |
+| 当前 Release 全量构建 | 11.20 s | 164.87 s | 基线 |
+| 推荐方案 | 8.86 s | 68.09 s | 降低 58.7% |
+
+也就是全量构建从 `164.87 s` 降到 `68.09 s`，快了约 `96.78 s`，构建速度约为原来的 `2.42x`。这已经超过“降低至少 50%”的目标。
+
+测试结果：
+
+| 测试 | 结果 |
+| --- | --- |
+| `ctest -C Release` | 10/10 通过 |
+| 测试总耗时 | 5.76 s |
+
+## Debug 构建影响
+
+这个优化主要针对 Release 全量构建。Debug 配置下，MSVC 生成的 benchmark、test 和 example 目标原本就是低优化：
+
+| 目标 | Debug 优化设置 |
+| --- | --- |
+| `json_benchmark` | `Optimization=Disabled` |
+| `test_json_files` | `Optimization=Disabled` |
+| `json_example` | `Optimization=Disabled` |
+
+因此当前改动对 Debug 构建基本没有加速空间。
+
+Debug 全量构建参考数据：
+
+| 场景 | 配置耗时 | 构建耗时 | 说明 |
+| --- | ---: | ---: | --- |
+| Debug 全量构建 | 7.45 s | 31.58 s | 当前改动前后预期基本一致 |
+
+结论：Debug 下提升约为 `0%`。Debug 本身已经接近“全部目标 `/Od` 原型”的 `32.24 s`，慢点主要来自模板解析和代码生成，而不是优化器。
+
+## 其他方向验证
+
+### 关闭警告
+
+对几个慢文件测试了 `/w`。结果波动较大，没有稳定收益。警告输出会让日志变吵，但不是当前主要耗时来源。
+
+### PCH
+
+做了一个临时通用 PCH 探测。PCH 创建耗时约 `8.04 s`。在可成功编译的慢文件上，收益不明显：
+
+| 源文件 | 普通 `/O2` | PCH `/O2` |
+| --- | ---: | ---: |
+| `test/test_json_files.cpp` | 36.82 s | 36.83 s |
+| `test/test_yaml.cpp` | 26.52 s | 27.32 s |
+
+此外，过宽的通用 PCH 会碰到 include 顺序和宏定义风险，例如 doctest 的 `DOCTEST_CONFIG_IMPLEMENT` 这类宏。当前 tests 大多是单源文件目标，CMake 默认的 per-target PCH 还会为每个目标单独生成 PCH，收益更不稳定。因此 PCH 暂不作为优先方案。
+
+### `/MP`
+
+当前 VS 工程没有看到 `/MP`，可以作为补充项加入 MSVC 编译选项。但当前多数目标只有一个 `.cpp`，而外层 `cmake --build --parallel 12` 已经在并行构建多个目标，所以 `/MP` 不是主要杠杆。
+
+## 推荐优化方案
+
+### 方案一：测试和示例 Release 下使用低优化级别
+
+这是当前已验证、收益最大的优化。
+
+保留全量目标，也就是 tests、examples、benchmarks 都仍然可以构建；但把非性能目标在 Release 下改成低优化级别：
+
+| 目标类别 | Release 编译策略 | 原因 |
+| --- | --- | --- |
+| tests | `/Od /Ob0` 或 `-O0` | 测试只需要验证语义，不需要优化代码 |
+| examples | `/Od /Ob0` 或 `-O0` | 示例只需要能编译运行，不承担性能数据 |
+| conformance runner | `/Od /Ob0` 或 `-O0` | 主要用于兼容性验证 |
+| benchmarks | 保持 `/O2` 或 `-O3` | benchmark 结果依赖优化后性能 |
+
+建议在 CMake 里加一个 helper，例如：
+
+```cmake
+function(iguana_fast_validation_target target)
+    if(MSVC)
+        target_compile_options(${target} PRIVATE
+            "$<$<CONFIG:Release>:/Od;/Ob0>")
+    else()
+        target_compile_options(${target} PRIVATE
+            "$<$<CONFIG:Release>:-O0>")
+    endif()
+endfunction()
+```
+
+然后应用到 `test_*`、`iguana_conformance` 和 `*_example` 目标。benchmark 目标先不应用，保证 benchmark 仍然有意义。
+
+实测结果：Release 全量构建从 `164.87 s` 降到 `68.09 s`，降低 `58.7%`。不会达到“全部目标 `/Od` 原型”的 `32.24 s` 那么低，因为 `json_benchmark` 等 benchmark 仍然保留优化编译；但它已经明显低于 `82.44 s` 的目标。
+
+### 方案二：增加快速 benchmark 编译开关
+
+如果目标是“CI 或本地全量只验证能否编译”，而不是运行 benchmark 得到性能数据，可以增加一个显式选项：
+
+```cmake
+option(IGUANA_FAST_BENCHMARK_COMPILE
+       "Compile benchmark targets with low optimization for faster full builds"
+       OFF)
+```
+
+开启后 benchmark 也使用 `/Od` 或 `-O0`。这会接近已验证的 `32.24 s` 原型，但该模式下生成的 benchmark 可执行文件不应用来比较运行性能。
+
+### 方案三：默认目标拆分仍然有用，但不是本次主解
+
+把默认构建改成只构建 header-only interface target，可以改善普通用户的默认构建体验。但它只是减少默认构建目标数量，不能解决“我要构建完整 tests/examples/benchmarks 时仍然慢”的问题。
+
+因此默认目标拆分可以保留为次要优化，但本次全量构建的主优化应优先做“测试和示例低优化编译”。
+
+## 建议复测矩阵
+
+应用 CMake 改动后，建议记录以下场景：
+
+| 场景 | 配置耗时 | 构建耗时 | 说明 |
+| --- | ---: | ---: | --- |
+| 当前 Release 全量构建 | 11.20 s | 164.87 s | 当前基线 |
+| 全部目标 `/Od` 原型 | 7.98 s | 32.24 s | 已验证，用于证明方向 |
+| tests/examples `/Od`，benchmarks 保持优化 | 8.86 s | 68.09 s | 已验证，推荐最终方案 |
+| tests/examples/benchmarks 全部 `/Od` | 8.6 s | 23.56 s | `IGUANA_FAST_BENCHMARK_COMPILE=ON` 快速编译模式，benchmark 不用于性能比较 |
+| 默认只构建 interface target | 待测 | 待测 | 用户体验优化，不代表全量构建 |
+
+推荐复测命令：
+
+```powershell
+cmake -S . -B out\perf_fast_validation_vs -G "Visual Studio 17 2022" -A x64
+cmake --build out\perf_fast_validation_vs --config Release --parallel 12 -- /v:minimal
+ctest --test-dir out\perf_fast_validation_vs -C Release --output-on-failure
+```
+
+验收标准：
+
+1. Release 全量构建时间低于 `82.44 s`。
+2. `ctest` 通过。
+3. benchmark 目标默认仍使用优化编译；如果启用快速 benchmark 编译，需要在文档中明确该模式不能用于性能对比。
+
+## 后续专项优化计划
+
+上面的推荐方案属于“构建策略优化”：它避免 tests/examples/conformance 在 Release 下浪费大量优化器时间，但还没有减少 iguana 模板本身的实例化成本。后续如果要继续做“治本”的编译性能优化，建议按下面顺序推进。
+
+### 阶段 0：保留已验证的快速收益
+
+目标：先保留已经证明有效、风险较低的方案。
+
+计划：
+
+1. 保持 tests、examples、conformance 在 Release 下使用低优化级别。
+2. benchmark 默认保持 Release 优化，确保性能测试结果不被污染。
+3. 可选增加一个显式开关，例如 `IGUANA_FAST_BENCHMARK_COMPILE=ON`，只在需要快速验证“能否编译”时让 benchmark 也低优化。
+
+验收：
+
+| 指标 | 目标 |
+| --- | --- |
+| Release 全量构建 | 低于 `82.44 s` |
+| 当前实测 | `68.09 s` |
+| `ctest -C Release` | 通过 |
+
+### 阶段 1：做精确热点归因
+
+目标：找出真正消耗编译时间的模板路径，而不是只看哪个 `.cpp` 慢。
+
+优先分析对象：
+
+| 文件 | 原因 |
+| --- | --- |
+| `benchmark/json_benchmark.cpp` | benchmark 必须保持优化编译，是 Release 全量里剩下的核心成本 |
+| `test/test_pb.cpp` | PB schema、variant、reflection 路径复杂 |
+| `test/test_json_files.cpp` | JSON DOM、reader/writer、variant 路径复杂 |
+| `test/test_yaml.cpp` | YAML reader/writer 模板实例化较重 |
+| `test/test_xml.cpp` | XML reader/writer 模板实例化较重 |
+
+建议验证方法：
+
+1. MSVC：用 `/d1reportTime` 或 build log 观察前端、后端、模板实例化耗时。
+2. Clang：用 `-ftime-trace` 生成 JSON trace，定位最重的模板和头文件。
+3. GCC/Clang：用 `-ftime-report` 看 parser、template instantiation、optimization 的占比。
+4. 对每个候选改动都用单文件编译和全量构建双重复测，避免局部优化在全量里没有收益。
+
+跨编译器诊断矩阵：
+
+| 编译器 | 主要诊断参数 | 重点观察 |
+| --- | --- | --- |
+| MSVC | `/d1reportTime`、`/Bt+` | 前端解析、后端优化、单文件耗时 |
+| Clang | `-ftime-trace`、`-ftime-report` | 最重模板实例化、头文件解析、优化 pass |
+| GCC | `-ftime-report` | parsing、template instantiation、optimization 占比 |
+
+建议先用 Clang 的 `-ftime-trace` 做模板热点定位，因为它输出的 JSON 更容易反查具体模板和头文件；再用 MSVC/GCC 复测这些热点是否也成立。
+
+输出：
+
+| 输出物 | 说明 |
+| --- | --- |
+| 热点模板列表 | 例如 `from_json_impl`、`from_pb_impl`、`std::variant` visitor、reflection member traversal |
+| 热点头文件列表 | 例如 `common.hpp`、`pb_util.hpp`、`json_reader.hpp`、`value.hpp` |
+| 前端/后端占比 | 判断该优先减少模板实例化还是减少优化器负担 |
+
+### 阶段 2：治理 include 依赖
+
+目标：减少不必要的头文件传播，降低业务项目和测试目标的重复解析成本。
+
+判断：这个方向靠谱，尤其对增量构建和大型业务项目有效。
+
+计划：
+
+1. 梳理 `iguana/iguana.hpp`、`common.hpp`、`pb_util.hpp`、`json_reader.hpp`、`json_writer.hpp` 的 include 图。
+2. 把只在实现细节里需要的重头文件尽量下沉到具体 reader/writer 头中。
+3. 对业务侧使用文档给出建议：模型声明头不 include iguana，序列化逻辑放在单独 `.hpp/.cpp` 或较上层文件里。
+4. 避免推荐“在函数体里 include iguana”这种写法；更推荐分离模型声明和序列化入口。
+
+验收：
+
+| 指标 | 目标 |
+| --- | --- |
+| include 图 | 明确重头文件入口 |
+| 单文件预处理体积 | 重点文件下降 |
+| 增量构建 | 修改普通模型头时受影响 TU 减少 |
+
+### 阶段 3：减少重复模板实例化
+
+目标：降低多个翻译单元重复实例化相同序列化路径的成本。
+
+判断：方向有价值，但不能简单套 `extern template`。
+
+原因：
+
+1. iguana 的核心函数大量使用 `IGUANA_INLINE`，MSVC 下是 `__forceinline`。
+2. `extern template` 不能可靠抑制 inline function 为了内联而发生的实例化。
+3. `to_json/from_json` 的实际模板参数包含引用类别、stream 类型、iterator 类型，签名容易写错。
+4. 当前测试里很多类型只在单个 `.cpp` 内使用，显式实例化收益有限。
+
+更稳妥的实验方向：
+
+1. 先针对少数稳定、高频、跨多个 TU 使用的业务类型设计非 inline wrapper。
+2. wrapper 在 `.cpp` 中显式实例化或显式定义，其他 TU 只调用普通函数。
+3. 对 benchmark 中固定类型，例如 `obj_t`，实验是否能把部分 reader/writer 路径外置。
+
+示意：
+
+```cpp
+// user_json.hpp
+struct User;
+std::string user_to_json(const User& user);
+void user_from_json(User& user, std::string_view json);
+
+// user_json.cpp
+#include <iguana/json_reader.hpp>
+#include <iguana/json_writer.hpp>
+#include "user.hpp"
+
+std::string user_to_json(const User& user) {
+    std::string out;
+    iguana::to_json(user, out);
+    return out;
+}
+
+void user_from_json(User& user, std::string_view json) {
+    iguana::from_json(user, json);
+}
+```
+
+验收：
+
+| 指标 | 目标 |
+| --- | --- |
+| 跨 TU 重复实例化 | 减少 |
+| 增量构建 | 调用方不再因 include iguana 重编重模板 |
+| 运行性能 | wrapper 不引入不可接受开销 |
+
+### 阶段 4：PCH 小范围验证
+
+目标：确认 PCH 是否适合具体业务 target，而不是默认认为它是银弹。
+
+当前最小验证结果：
+
+| 源文件 | 普通 `/O2` | PCH `/O2` |
+| --- | ---: | ---: |
+| `test/test_json_files.cpp` | 36.82 s | 36.83 s |
+| `test/test_yaml.cpp` | 26.52 s | 27.32 s |
+
+结论：对当前仓库的单源文件测试目标，通用 PCH 收益不明显。PCH 更适合一个业务 target 有很多 `.cpp`，并且这些 `.cpp` 都稳定 include 同一批重头文件的场景。
+
+计划：
+
+1. 不在当前仓库默认强制开启 PCH。
+2. 如果未来有多 `.cpp` 的业务 target，再对该 target 单独试 `target_precompile_headers`。
+3. PCH 内容避免包含带宏开关行为的测试框架入口，例如 doctest 的 `DOCTEST_CONFIG_IMPLEMENT`。
+
+跨编译器注意事项：
+
+| 编译器 | PCH 注意点 |
+| --- | --- |
+| MSVC | `.pch` 通常按 target/config 生成；单源文件 target 收益有限 |
+| Clang | PCH/modules 机制更灵活，但宏和编译选项变化会导致失效 |
+| GCC | `.gch` 对头文件路径、宏、编译选项敏感，工程化维护成本较高 |
+
+PCH 不建议作为全局默认优化；更适合在具体业务 target 中按需启用，并分别对 MSVC/GCC/Clang 复测。
+
+验收：
+
+| 指标 | 目标 |
+| --- | --- |
+| PCH 创建时间 | 小于节省时间 |
+| 全量构建 | 有稳定收益 |
+| 增量构建 | 修改普通 `.cpp` 时收益明显 |
+
+### 阶段 5：构建工具链优化
+
+目标：利用构建系统和缓存改善开发迭代体验。
+
+计划：
+
+1. MSVC 下评估 `/MP`。当前很多 target 是单 `.cpp`，且已经使用 `cmake --build --parallel 12`，所以预期收益有限；如果后续拆分大测试文件，`/MP` 的价值会上升。
+2. Windows 可评估 `sccache`，Linux/macOS 可评估 `ccache`。
+3. CI 使用缓存时，重点缓存 compiler launcher 结果，而不是只缓存 build 目录。
+4. `/Zc:preprocessor` 单独小测，不预设一定更快。
+
+跨平台建议：
+
+| 平台/编译器 | 优先工具 | CMake 方式 | 说明 |
+| --- | --- | --- | --- |
+| MSVC | `/MP`、`sccache` | `target_compile_options(... /MP)`、`CMAKE_CXX_COMPILER_LAUNCHER=sccache` | `/MP` 适合单 target 多 `.cpp`；sccache 适合重复构建 |
+| clang-cl | `/MP`、`sccache` | 同 MSVC 风格参数 | 需要单独确认 clang-cl 对现有 flags 的兼容性 |
+| GCC | `ccache`、`-ftime-report` | `CMAKE_CXX_COMPILER_LAUNCHER=ccache` | 首次全量收益小，二次构建收益大 |
+| Clang | `ccache/sccache`、`-ftime-trace` | `CMAKE_CXX_COMPILER_LAUNCHER=ccache` 或 `sccache` | 最适合做模板热点 trace |
+
+注意：ccache/sccache 不是优化“首次干净全量构建”的主要手段。它们主要优化未改动源码的重复构建、CI 缓存和小改动增量构建。
+
+验收：
+
+| 场景 | 预期收益 |
+| --- | --- |
+| 首次干净全量构建 | cache 基本无收益 |
+| 未改源码的重复构建 | cache 应接近秒级 |
+| 只改少量 `.cpp` | cache 应明显减少重编时间 |
+| 修改 iguana 核心头 | cache 命中会显著下降 |
+
+### 阶段 6：编译器版本对比
+
+目标：确认升级编译器是否能自然降低模板编译成本。
+
+计划：
+
+1. MSVC：对比当前 `19.44.35217` 和更新 VS 2022 patch 的 Release 全量构建。
+2. GCC：对比 GCC 11、13、16。
+3. Clang：对比 Clang 14、16、18+。
+4. 对 C++20/C++26 反射路径单独建表，不和默认 C++17 路径混在一起。
+
+建议复测配置：
+
+| 编译器 | C++ 标准 | 构建类型 | 是否启用 C++26 reflection |
+| --- | --- | --- | --- |
+| MSVC 19.44+ | C++17、C++20 | Debug、Release | 否 |
+| GCC 11/13 | C++17、C++20 | Debug、Release | 否 |
+| GCC 16 | C++17、C++20、C++26 | Debug、Release | C++26 单独测 |
+| Clang 16/18+ | C++17、C++20 | Debug、Release | 否 |
+
+C++26 reflection 路径必须单独看，因为它引入新的编译器前端能力和 `<meta>` 支持，不能和当前宏反射/C++17 路径直接比较。
+
+验收：
+
+| 指标 | 目标 |
+| --- | --- |
+| 同一代码同一 CMake 配置 | 只替换编译器版本 |
+| Release 全量构建 | 记录变化 |
+| Debug 全量构建 | 记录变化 |
+| 单文件热点 | 记录变化 |
+
+## 方法优先级总结
+
+| 优先级 | 方法 | 判断 |
+| ---: | --- | --- |
+| 1 | tests/examples/conformance Release 低优化 | 已验证，收益最大，风险低 |
+| 2 | 精确热点归因 | 必须做，否则容易盲改 |
+| 3 | include 依赖治理 | 对增量构建和业务接入价值高 |
+| 4 | 非 inline wrapper / 显式实例化实验 | 有潜力，但只适合稳定高频类型 |
+| 5 | ccache/sccache | 对重复构建和 CI 有价值 |
+| 6 | `/MP` | 当前单 `.cpp` 目标收益有限，拆分后再看 |
+| 7 | PCH | 当前仓库小测收益不明显，只建议按 target 验证 |
+| 8 | 直接套 `extern template` | 不建议优先做，容易复杂且收益不稳 |
+
+## 跨编译器复测计划
+
+为了避免只优化 MSVC，后续每个候选方案都应该至少跑下面三类编译器：
+
+| 编译器族 | 推荐生成器 | 重点问题 |
+| --- | --- | --- |
+| MSVC | Visual Studio 或 Ninja | Release `/O2` 后端优化是否仍是主瓶颈 |
+| GCC | Ninja 或 Unix Makefiles | `-O3` 下 template instantiation 和 optimization 占比 |
+| Clang | Ninja 或 Unix Makefiles | `-ftime-trace` 定位出的热点是否与 MSVC/GCC 一致 |
+
+基础复测命令模板：
+
+```powershell
+# MSVC
+cmake -S . -B out\msvc_release -G "Visual Studio 17 2022" -A x64
+cmake --build out\msvc_release --config Release --parallel 12 -- /v:minimal
+```
+
+```bash
+# GCC
+CXX=g++ CC=gcc cmake -S . -B out/gcc_release -DCMAKE_BUILD_TYPE=Release
+cmake --build out/gcc_release -j"$(nproc)"
+```
+
+```bash
+# Clang
+CXX=clang++ CC=clang cmake -S . -B out/clang_release -DCMAKE_BUILD_TYPE=Release
+cmake --build out/clang_release -j"$(nproc)"
+```
+
+候选优化的记录表：
+
+| 方案 | MSVC Release | GCC Release | Clang Release | Debug 影响 | 结论 |
+| --- | ---: | ---: | ---: | ---: | --- |
+| 当前基线 | `164.87 s` | 待测 | 待测 | `31.58 s` on MSVC | MSVC 已测 |
+| tests/examples 低优化 | `68.09 s` | 待测 | 待测 | 约 `0%` | 需确认 GCC/Clang |
+| PCH | 无稳定收益 | 待测 | 待测 | 待测 | 按 target 验证 |
+| cache launcher | 首次全量收益小 | 待测 | 待测 | 增量更重要 | 看 CI/二次构建 |
+| include 治理 | 待测 | 待测 | 待测 | 增量更重要 | 需要热点驱动 |
+
+只有在 MSVC/GCC/Clang 至少两类编译器上都有稳定收益的改动，才建议作为库级默认优化；只对单个编译器有效的优化，应使用编译器条件或 CMake option 包起来。
+
+## Clang 主导执行计划
+
+后续工作以 Clang 为主要分析工具，MSVC/GCC 作为结果验证工具。原因是 Clang 的 `-ftime-trace` 能直接输出模板实例化、头文件解析和优化 pass 的耗时，适合定位“为什么慢”。
+
+### 执行原则
+
+1. 每一项实验都记录命令、耗时、结果和结论。
+2. 每次只改变一个变量，例如编译器、优化级别、PCH、cache 或 include 结构。
+3. 先测单文件，再测全量构建，避免局部收益无法转化成全量收益。
+4. benchmark 默认保持优化编译；任何降低 benchmark 优化级别的实验都必须标记为“只验证编译，不用于性能对比”。
+5. MSVC/GCC/Clang 至少两类编译器上稳定有效的方案，才考虑作为默认优化。
+
+### 任务清单
+
+| 序号 | 任务 | 状态 | 输出 |
+| ---: | --- | --- | --- |
+| 1 | 确认 Windows 上 clang-cl/clang++ 可用 | 待执行 | 工具版本、路径 |
+| 2 | 建立 clang-cl Release/Debug 全量构建基线 | 待执行 | 配置耗时、构建耗时、测试结果 |
+| 3 | 对慢文件生成 `-ftime-trace` | 待执行 | trace 文件、热点列表 |
+| 4 | 归纳 Clang 热点类型 | 待执行 | 模板实例化、头文件解析、优化器占比 |
+| 5 | 选 1-2 个小优化实验 | 待执行 | 单文件耗时和全量耗时对比 |
+| 6 | 用 MSVC/GCC 复测有效方案 | 待执行 | 跨编译器结果 |
+| 7 | 整理默认启用/可选启用/不建议启用方案 | 待执行 | 最终建议 |
+
+### Clang 基线命令
+
+Windows 上优先使用 `clang-cl`，因为它兼容 MSVC ABI 和 MSVC STL，更接近 Windows 用户的实际使用环境：
+
+```powershell
+cmake -S . -B out\clangcl_release -G "Visual Studio 17 2022" -A x64 -T ClangCL
+cmake --build out\clangcl_release --config Release --parallel 12 -- /v:minimal
+ctest --test-dir out\clangcl_release -C Release --output-on-failure -j 1
+```
+
+```powershell
+cmake -S . -B out\clangcl_debug -G "Visual Studio 17 2022" -A x64 -T ClangCL
+cmake --build out\clangcl_debug --config Debug --parallel 12 -- /v:minimal
+ctest --test-dir out\clangcl_debug -C Debug --output-on-failure -j 1
+```
+
+### Clang Trace 目标文件
+
+优先 trace 以下文件：
+
+| 文件 | 原因 |
+| --- | --- |
+| `benchmark/json_benchmark.cpp` | benchmark 保持优化编译，是 Release 全量剩余大头 |
+| `test/test_pb.cpp` | PB schema、variant、reflection 路径复杂 |
+| `test/test_json_files.cpp` | JSON DOM、reader/writer、variant 路径复杂 |
+| `test/test_yaml.cpp` | YAML reader/writer 模板实例化较重 |
+| `test/test_xml.cpp` | XML reader/writer 模板实例化较重 |
+
+### 执行记录
+
+| 时间 | 项目 | 命令/配置 | 结果 | 结论 |
+| --- | --- | --- | --- | --- |
+| 2026-05-31 | MSVC Release 基线 | VS 2022, Release, parallel 12 | `164.87 s` | Release 慢主要来自优化器处理重模板目标 |
+| 2026-05-31 | MSVC 推荐方案 | tests/examples/conformance `/Od /Ob0`，benchmarks 保持优化 | `68.09 s`，`ctest 10/10` | 构建策略优化有效，降低 `58.7%` |
+| 2026-05-31 | MSVC Debug | VS 2022, Debug, parallel 12 | `31.58 s` | Debug 本来已低优化，当前方案基本无收益 |
+| 2026-05-31 | Clang 工具链检查 | `clang-cl --version`、`clang++ --version` | Clang `18.1.8`，路径 `D:\Program Files\LLVM\bin` | `clang-cl` 和 `clang++` 可用；`ninja` 不在 PATH，优先用 VS 生成器 `-T ClangCL` |
+| 2026-05-31 | Clang 构建执行门禁 | 用户要求正式编译前先确认 | 待用户明确说“开始” | 暂不启动 Release/Debug 全量构建和 `-ftime-trace` 编译 |
+| 2026-05-31 | clang-cl + VS 生成器 | `-G "Visual Studio 17 2022" -T ClangCL` | 配置失败 | VS 未安装 `ClangCL` 平台工具集 |
+| 2026-05-31 | clang-cl + Ninja fallback | VS 自带 Ninja + standalone `clang-cl 18.1.8` | 配置成功，编译失败 | MSVC STL `14.44.35207` 要求 Clang `19.0.0+`，本机 Clang `18.1.8` 触发 `STL1000` |
+| 2026-05-31 | Clang trace override | `clang-cl 18.1.8` + `_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH` + `-ftime-trace` | 5 个慢文件 trace 成功 | 仅用于热点探索，不作为正式 Clang 支持基线 |
+
+### 待确认执行命令
+
+以下命令只作为准备记录，尚未执行。并行度保持 `12`，用于和 MSVC 基线对齐。
+
+```powershell
+cmake -S . -B out\clangcl_release -G "Visual Studio 17 2022" -A x64 -T ClangCL
+cmake --build out\clangcl_release --config Release --parallel 12 -- /v:minimal
+ctest --test-dir out\clangcl_release -C Release --output-on-failure -j 1
+```
+
+```powershell
+cmake -S . -B out\clangcl_debug -G "Visual Studio 17 2022" -A x64 -T ClangCL
+cmake --build out\clangcl_debug --config Debug --parallel 12 -- /v:minimal
+ctest --test-dir out\clangcl_debug -C Debug --output-on-failure -j 1
+```
+
+`-ftime-trace` 单文件分析将在全量基线之后执行，且每个慢文件单独编译，避免并行任务干扰 trace 和耗时记录。
+
+### Clang 阻塞结论
+
+当前 Windows Clang 基线暂时不能作为正式数据继续跑，原因不是 iguana 代码，而是工具链版本不匹配：
+
+| 组件 | 当前版本/状态 |
+| --- | --- |
+| LLVM standalone `clang-cl` | `18.1.8` |
+| MSVC STL | `14.44.35207`，`_MSVC_STL_UPDATE 202503L` |
+| STL 要求 | Clang `19.0.0` 或更新 |
+| VS ClangCL 平台工具集 | 未安装 |
+| VS 自带 Ninja | 可用 |
+
+可选处理方式：
+
+1. 安装 LLVM/Clang `19+`，然后继续用 `Ninja + clang-cl` 跑正式基线。
+2. 安装 Visual Studio 的 `ClangCL` 平台工具集，然后继续用 VS 生成器 `-T ClangCL`。
+3. 仅用于探索性 trace 时，可以定义 `_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH` 绕过 STL 版本检查；该结果不能作为正式支持基线，必须在记录中标注“unsupported toolchain override”。
+
+建议：正式基线不要使用 `_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH`。如果只是为了先看模板热点，可以在用户确认后用该宏做临时 `-ftime-trace` 实验。
+
+### Clang Trace 结果
+
+以下数据使用 standalone `clang-cl 18.1.8`，并定义 `_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH` 绕过当前 MSVC STL 对 Clang 19+ 的版本要求。该结果只用于探索编译热点，不作为正式支持基线。
+
+命令形态：
+
+```powershell
+clang-cl /std:c++17 /I. /D_CRT_SECURE_NO_WARNINGS /DTHROW_UNKNOWN_KEY `
+  /D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH /EHsc /bigobj /Zc:__cplusplus `
+  /utf-8 /O2 /DNDEBUG /clang:-ftime-trace /c <source.cpp>
+```
+
+单文件耗时：
+
+| 文件 | 编译耗时 | Trace 大小 |
+| --- | ---: | ---: |
+| `benchmark/json_benchmark.cpp` | 26.78 s | 35.7 MB |
+| `test/test_pb.cpp` | 27.23 s | 6.4 MB |
+| `test/test_json_files.cpp` | 30.09 s | 32.6 MB |
+| `test/test_yaml.cpp` | 22.85 s | 6.0 MB |
+| `test/test_xml.cpp` | 24.86 s | 6.1 MB |
+
+Trace 汇总：
+
+| 文件 | ExecuteCompiler | Frontend | Backend | Optimizer | InstantiateFunction | InstantiateClass |
+| --- | ---: | ---: | ---: | ---: | ---: | ---: |
+| `json_benchmark.cpp` | 24.42 s | 7.84 s | 16.49 s | 10.41 s | 6.33 s | 3.31 s |
+| `test_pb.cpp` | 25.25 s | 7.30 s | 17.86 s | 11.75 s | 5.47 s | 2.42 s |
+| `test_json_files.cpp` | 27.96 s | 7.76 s | 20.11 s | 12.31 s | 5.98 s | 3.17 s |
+| `test_yaml.cpp` | 20.79 s | 2.86 s | 17.89 s | 10.80 s | 1.50 s | 0.65 s |
+| `test_xml.cpp` | 22.82 s | 2.79 s | 19.99 s | 11.66 s | 1.50 s | 0.56 s |
+
+初步结论：
+
+1. Clang 下这几个慢文件也明显受后端优化器影响。`Backend` 和 `Optimizer` 是总耗时中的最大块。
+2. JSON 相关路径额外有较重的前端模板实例化成本，尤其是 `githubEvents::event_t` 和 `payload_t`。
+3. YAML/XML 的前端模板实例化相对较轻，主要慢在后端优化和代码生成。
+4. PB 的前端和后端都重，热点集中在 `to_proto`、`from_pb`、`build_pb_fields`、`tuple_cat`、`pb_field_t` 等路径。
+
+最重函数模板实例化：
+
+| 文件 | 主要热点 |
+| --- | --- |
+| `json_benchmark.cpp` | `iguana::from_json<std::vector<githubEvents::event_t>>`、`from_json_impl<githubEvents::event_t>`、`from_json_impl<githubEvents::payload_t>` |
+| `test_json_files.cpp` | 同样集中在 `githubEvents::event_t` / `payload_t` 的 JSON 解析 |
+| `test_pb.cpp` | `iguana::to_proto<vector_t>`、`proto_needs_timestamp_import<vector_t>`、`get_pb_members_tuple<vector_t&>`、`build_pb_fields`、`from_pb<test_pb_merge_outer>` |
+| `test_yaml.cpp` | `from_yaml<person_t>`、`from_yaml<store_example_t>`、`from_yaml<test_enum_t>`、`from_yaml<some_type_t>` |
+| `test_xml.cpp` | `from_xml<province>`、`from_xml<some_type_t>`、`xml_parse_item<province>`、`xml_parse_item<some_type_t>` |
+
+最重源码入口：
+
+| 文件 | 主要 Source 热点 |
+| --- | --- |
+| `json_benchmark.cpp` | `benchmark/json_benchmark.h`、`iguana/json_reader.hpp`、`iguana/json_util.hpp`、`iguana/common.hpp` |
+| `test_json_files.cpp` | `test/test_headers.h`、`filesystem`、`doctest.h`、`iguana/json_reader.hpp` |
+| `test_pb.cpp` | `doctest.h`、`iguana/dynamic.hpp`、`iguana/common.hpp`、`iguana/util.hpp`、`windows.h` |
+| `test_yaml.cpp` | `iguana/yaml_reader.hpp`、`doctest.h`、`iguana/yaml_util.hpp`、`iguana/common.hpp` |
+| `test_xml.cpp` | `iguana/xml_reader.hpp`、`doctest.h`、`iguana/xml_util.hpp`、`iguana/common.hpp` |
+
+下一步实验：
+
+1. 用 Clang 对这 5 个文件做 `/O2` vs `/Od` 对比，确认后端优化器成本占比。
+2. 对 `json_benchmark.cpp` 和 `test_json_files.cpp` 单独研究 `githubEvents` 类型，判断是否可以减少大 tuple / variant / reflection traversal 的实例化成本。
+3. 对 `test_pb.cpp` 单独研究 `build_pb_fields` 和 `tuple_cat`，判断是否可以缓存或简化 PB schema 构建路径。
+
+### Clang `/O2` vs `/Od` 对比
+
+同样使用 `_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH`，只作为探索性数据。
+
+| 文件 | `/O2` | `/Od /Ob0` | 降幅 |
+| --- | ---: | ---: | ---: |
+| `benchmark/json_benchmark.cpp` | 34.93 s | 15.37 s | 56.0% |
+| `test/test_pb.cpp` | 38.62 s | 14.68 s | 62.0% |
+| `test/test_json_files.cpp` | 37.06 s | 13.76 s | 62.9% |
+| `test/test_yaml.cpp` | 29.62 s | 7.81 s | 73.6% |
+| `test/test_xml.cpp` | 31.99 s | 8.44 s | 73.6% |
+
+结论：
+
+1. Clang 下也能复现 MSVC 的核心规律：优化器成本是 Release 慢的主要来源。
+2. YAML/XML 的前端模板实例化较轻，低优化收益最大。
+3. JSON/PB 低优化后仍有 13-15 秒，说明除了优化器，前端模板实例化和大型类型 schema 仍然值得专项优化。
+
+### JSON Schema 结构观察
+
+`json_benchmark.cpp` 和 `test_json_files.cpp` 的热点都集中在 `githubEvents` 类型。代码结构上有一个明显问题：`benchmark/json_benchmark.h` 和 `test/test_headers.h` 各自复制了一整套大型 JSON schema 类型。
+
+| 文件 | 行数 | 说明 |
+| --- | ---: | --- |
+| `benchmark/json_benchmark.h` | 688 | benchmark 使用，字段多为 `std::string_view` / `iguana::numeric_str` |
+| `test/test_headers.h` | 672 | test 使用，字段多为 `std::string` / 数值类型 |
+
+两个文件都包含 `githubEvents::event_t`、`payload_t`、`forkee_t` 等大型反射类型。Trace 中最重的 JSON 实例化集中在：
+
+```text
+iguana::from_json<std::vector<githubEvents::event_t>>
+iguana::detail::from_json_impl<githubEvents::event_t>
+iguana::detail::from_json_impl<githubEvents::payload_t>
+iguana::detail::from_json_impl<std::optional<githubEvents::forkee_t>>
+```
+
+后续可以考虑的方向：
+
+1. 把测试和 benchmark 的大型 schema 拆成更小的专用头，避免无关测试 include 全量 schema。
+2. 对 `githubEvents` 单独建立专用 benchmark/test 文件，避免它拖慢普通 JSON 测试。
+3. 分析 `payload_t` 和 `forkee_t` 的字段数、optional、vector、嵌套对象是否触发过多 tuple/variant 组合实例化。
+4. 保持 test 和 benchmark 的类型语义差异，不要盲目合并 `test_headers.h` 和 `json_benchmark.h`；它们一个偏 owning type，一个偏 view/numeric_str benchmark type。
diff --git a/frozen/string.h b/frozen/string.h
--- a/frozen/string.h
+++ b/frozen/string.h
@@ -23,27 +23,28 @@
 #ifndef FROZEN_LETITGO_STRING_H
 #define FROZEN_LETITGO_STRING_H
 
+#include <cstring>
+#include <functional>
+
 #include "frozen/bits/defines.h"
 #include "frozen/bits/elsa.h"
 #include "frozen/bits/hash_string.h"
 #include "frozen/bits/version.h"
 
-#include <cstring>
-#include <functional>
-
 #ifdef FROZEN_LETITGO_HAS_STRING_VIEW
 #include <string_view>
 #endif
 
 namespace frozen {
 
-template <typename _CharT> class basic_string {
+template <typename _CharT>
+class basic_string {
   using chr_t = _CharT;
 
   chr_t const *data_;
   std::size_t size_;
 
-public:
+ public:
   template <std::size_t N>
   constexpr basic_string(chr_t const (&data)[N]) : data_(data), size_(N - 1) {}
   constexpr basic_string(chr_t const *data, std::size_t size)
@@ -89,7 +90,8 @@ template <typename _CharT> class basic_string {
   constexpr const chr_t *end() const { return data() + size(); }
 };
 
-template <typename _CharT> struct elsa<basic_string<_CharT>> {
+template <typename _CharT>
+struct elsa<basic_string<_CharT>> {
   constexpr std::size_t operator()(basic_string<_CharT> value) const {
     return hash_string(value);
   }
@@ -110,38 +112,39 @@ using u8string = basic_string<char8_t>;
 
 namespace string_literals {
 
-constexpr string operator"" _s(const char *data, std::size_t size) {
+constexpr string operator""_s(const char *data, std::size_t size) {
   return {data, size};
 }
 
-constexpr wstring operator"" _s(const wchar_t *data, std::size_t size) {
+constexpr wstring operator""_s(const wchar_t *data, std::size_t size) {
   return {data, size};
 }
 
-constexpr u16string operator"" _s(const char16_t *data, std::size_t size) {
+constexpr u16string operator""_s(const char16_t *data, std::size_t size) {
   return {data, size};
 }
 
-constexpr u32string operator"" _s(const char32_t *data, std::size_t size) {
+constexpr u32string operator""_s(const char32_t *data, std::size_t size) {
   return {data, size};
 }
 
 #ifdef FROZEN_LETITGO_HAS_CHAR8T
-constexpr u8string operator"" _s(const char8_t *data, std::size_t size) {
+constexpr u8string operator""_s(const char8_t *data, std::size_t size) {
   return {data, size};
 }
 #endif
 
-} // namespace string_literals
+}  // namespace string_literals
 
-} // namespace frozen
+}  // namespace frozen
 
 namespace std {
-template <typename _CharT> struct hash<frozen::basic_string<_CharT>> {
+template <typename _CharT>
+struct hash<frozen::basic_string<_CharT>> {
   size_t operator()(frozen::basic_string<_CharT> s) const {
     return frozen::elsa<frozen::basic_string<_CharT>>{}(s);
   }
 };
-} // namespace std
+}  // namespace std
 
 #endif
diff --git a/iguana/common.hpp b/iguana/common.hpp
--- a/iguana/common.hpp
+++ b/iguana/common.hpp
@@ -1,12 +1,115 @@
 #pragma once
 #include <any>
+#include <array>
+#include <chrono>
+#include <cstddef>
+#include <optional>
+#include <string>
+#include <tuple>
+#include <utility>
+#include <variant>
+#include <vector>
 
 #include "util.hpp"
+#ifdef YLT_USE_CXX26_REFLECTION
+#include <meta>
+
+#include "ylt/reflection/reflect26_core.hpp"
+#endif
 
 namespace iguana {
 struct iguana_adl_t {};
 
+#if defined(__GNUC__) && !defined(__clang__)
+#define IGUANA_DYNAMIC_NOINLINE __attribute__((noinline))
+#else
+#define IGUANA_DYNAMIC_NOINLINE
+#endif
+
+struct pb_field_annotation {
+  size_t value;
+};
+
+constexpr pb_field_annotation pb_field(size_t field_no) { return {field_no}; }
+
+struct pb_zigzag_annotation {};
+struct pb_fixed_annotation {};
+struct pb_bytes_annotation {};
+template <size_t... Ns>
+struct pb_oneof_annotation {
+  static constexpr std::array<size_t, sizeof...(Ns)> values{Ns...};
+};
+struct pb_timestamp_annotation {};
+struct pb_duration_annotation {};
+struct pb_optional_annotation {};
+struct pb_unknown_fields_annotation {};
+
+inline constexpr pb_zigzag_annotation pb_zigzag{};
+inline constexpr pb_fixed_annotation pb_fixed{};
+inline constexpr pb_bytes_annotation pb_bytes{};
+template <size_t... Ns>
+inline constexpr pb_oneof_annotation<Ns...> pb_oneof{};
+template <size_t... Ns>
+inline constexpr pb_oneof_annotation<Ns...> oneof{};
+inline constexpr pb_timestamp_annotation pb_as_timestamp{};
+inline constexpr pb_timestamp_annotation as_timestamp{};
+inline constexpr pb_duration_annotation pb_as_duration{};
+inline constexpr pb_duration_annotation as_duration{};
+inline constexpr pb_optional_annotation pb_optional{};
+inline constexpr pb_unknown_fields_annotation pb_unknown_fields{};
+
+struct pb_timestamp {
+  int64_t seconds{};
+  int32_t nanos{};
+
+  pb_timestamp() = default;
+
+  explicit pb_timestamp(std::chrono::system_clock::time_point value) {
+    using namespace std::chrono;
+    auto total = duration_cast<nanoseconds>(value.time_since_epoch());
+    auto sec = duration_cast<std::chrono::seconds>(total);
+    auto rem = total - sec;
+    if (rem.count() < 0) {
+      --sec;
+      rem += std::chrono::seconds{1};
+    }
+    seconds = sec.count();
+    nanos = static_cast<int32_t>(rem.count());
+  }
+
+  operator std::chrono::system_clock::time_point() const {
+    using clock_duration = std::chrono::system_clock::duration;
+    return std::chrono::system_clock::time_point{
+        std::chrono::duration_cast<clock_duration>(
+            std::chrono::seconds{seconds} + std::chrono::nanoseconds{nanos})};
+  }
+};
+
+struct pb_duration {
+  int64_t seconds{};
+  int32_t nanos{};
+
+  pb_duration() = default;
+
+  explicit pb_duration(std::chrono::nanoseconds value) {
+    auto sec = std::chrono::duration_cast<std::chrono::seconds>(value);
+    auto rem = value - sec;
+    seconds = sec.count();
+    nanos = static_cast<int32_t>(rem.count());
+  }
+
+  operator std::chrono::nanoseconds() const {
+    return std::chrono::seconds{seconds} + std::chrono::nanoseconds{nanos};
+  }
+};
+YLT_REFL(pb_timestamp, seconds, nanos);
+YLT_REFL(pb_duration, seconds, nanos);
+
 namespace detail {
+#ifdef YLT_USE_CXX26_REFLECTION
+namespace reflect26 = ylt::reflection::reflect26;
+#endif
+
 template <typename T>
 struct identity {};
 
@@ -35,23 +138,27 @@ struct base {
   T& get_field_value(std::string_view name) {
     auto info = get_field_info(name);
     check_field<T>(name, info);
-    auto ptr = (((char*)this) + info.offset);
+    auto ptr = static_cast<char*>(object_ptr()) + info.offset;
     return *((T*)ptr);
   }
 
   template <typename T, typename FiledType = T>
-  void set_field_value(std::string_view name, T val) {
+  IGUANA_DYNAMIC_NOINLINE void set_field_value(std::string_view name, T val) {
     auto info = get_field_info(name);
     check_field<FiledType>(name, info);
 
-    auto ptr = (((char*)this) + info.offset);
+    auto ptr = static_cast<char*>(object_ptr()) + info.offset;
 
     static_assert(std::is_constructible_v<FiledType, T>, "can not assign");
 
     *((FiledType*)ptr) = std::move(val);
   }
   virtual ~base() {}
 
+ protected:
+  virtual void* object_ptr() { return this; }
+  virtual const void* object_ptr() const { return this; }
+
  private:
   template <typename T>
   void check_field(std::string_view name, const field_info& info) {
@@ -87,7 +194,13 @@ struct field_type_t<std::tuple<Args...>> {
 template <typename T>
 constexpr size_t count_variant_size() {
   if constexpr (is_variant<T>::value) {
-    return std::variant_size_v<T>;
+    using first_type = std::variant_alternative_t<0, T>;
+    if constexpr (std::is_same_v<first_type, std::monostate>) {
+      return std::variant_size_v<T> - 1;
+    }
+    else {
+      return std::variant_size_v<T>;
+    }
   }
   else {
     return 1;
@@ -129,11 +242,17 @@ inline constexpr bool is_custom_reflection_v =
 // owner_type: parant type, value_type: member value type, SubType: subtype from
 // variant
 template <typename Owner, typename Value, size_t FieldNo,
-          typename ElementType = Value>
+          typename ElementType = Value, bool BytesSchema = false,
+          bool TimestampSchema = false, bool DurationSchema = false,
+          bool OptionalSchema = false, bool ZigzagSchema = false,
+          bool FixedSchema = false, typename WireValue = Value,
+          typename WireElement = ElementType>
 struct pb_field_t {
   using owner_type = ylt::reflection::remove_cvref_t<Owner>;
   using value_type = Value;
   using sub_type = ElementType;
+  using wire_value_type = WireValue;
+  using wire_sub_type = WireElement;
 
   // constexpr pb_field_t() = default;
   auto& value(owner_type& value) const {
@@ -149,14 +268,74 @@ struct pb_field_t {
   std::string_view field_name;
 
   inline static constexpr uint32_t field_no = FieldNo;
+  inline static constexpr bool bytes_schema = BytesSchema;
+  inline static constexpr bool timestamp_schema = TimestampSchema;
+  inline static constexpr bool duration_schema = DurationSchema;
+  inline static constexpr bool optional_schema = OptionalSchema;
+  inline static constexpr bool zigzag_schema = ZigzagSchema;
+  inline static constexpr bool fixed_schema = FixedSchema;
+};
+
+template <typename>
+struct pb_field_no;
+
+template <typename Owner, typename Value, size_t FieldNo, typename ElementType,
+          bool BytesSchema, bool TimestampSchema, bool DurationSchema,
+          bool OptionalSchema, bool ZigzagSchema, bool FixedSchema,
+          typename WireValue, typename WireElement>
+struct pb_field_no<
+    pb_field_t<Owner, Value, FieldNo, ElementType, BytesSchema, TimestampSchema,
+               DurationSchema, OptionalSchema, ZigzagSchema, FixedSchema,
+               WireValue, WireElement>> {
+  static constexpr size_t value = FieldNo;
 };
 
+constexpr bool is_valid_pb_field_no(size_t field_no) {
+  constexpr size_t max_field_no = (size_t{1} << 29) - 1;
+  return field_no > 0 && field_no <= max_field_no &&
+         (field_no < 19000 || field_no > 19999);
+}
+
+template <typename Tuple, size_t... I>
+constexpr bool has_invalid_field_nos(std::index_sequence<I...>) {
+  return ((!is_valid_pb_field_no(
+              pb_field_no<std::tuple_element_t<I, Tuple>>::value)) ||
+          ...);
+}
+
+template <typename Tuple, size_t... I>
+constexpr bool has_duplicate_field_nos(std::index_sequence<I...>) {
+  if constexpr (sizeof...(I) == 0) {
+    return false;
+  }
+  else {
+    constexpr size_t nos[] = {
+        pb_field_no<std::tuple_element_t<I, Tuple>>::value...};
+    constexpr size_t N = sizeof...(I);
+    for (size_t i = 0; i < N; ++i)
+      for (size_t j = i + 1; j < N; ++j)
+        if (nos[i] == nos[j])
+          return true;
+    return false;
+  }
+}
+
+template <typename Tuple>
+constexpr void validate_pb_members_tuple() {
+  constexpr size_t N = std::tuple_size_v<Tuple>;
+  static_assert(!has_invalid_field_nos<Tuple>(std::make_index_sequence<N>{}),
+                "protobuf field numbers must be in [1, 2^29 - 1] and not in "
+                "[19000, 19999]");
+  static_assert(!has_duplicate_field_nos<Tuple>(std::make_index_sequence<N>{}),
+                "duplicate proto field numbers detected");
+}
+
 template <size_t I, typename ValueType, typename Array>
 constexpr inline auto get_field_no_impl(Array& arr, size_t& index) {
   arr[I] = index;
   if constexpr (is_variant<ValueType>::value) {
-    constexpr size_t variant_size = std::variant_size_v<ValueType>;
-    index += (variant_size);
+    constexpr size_t variant_size = count_variant_size<ValueType>();
+    index += variant_size;
   }
   else {
     index++;
@@ -175,31 +354,740 @@ inline constexpr auto get_field_no(std::index_sequence<I...>) {
   return arr;
 }
 
-template <typename T, typename value_type, size_t field_no, size_t... I>
+template <typename Variant>
+constexpr size_t pb_variant_first_case_index() {
+  using first_type = std::variant_alternative_t<0, Variant>;
+  if constexpr (std::is_same_v<first_type, std::monostate>) {
+    return 1;
+  }
+  else {
+    return 0;
+  }
+}
+
+template <typename Variant>
+constexpr size_t pb_variant_case_count() {
+  return std::variant_size_v<Variant> - pb_variant_first_case_index<Variant>();
+}
+
+template <typename T, typename value_type, size_t field_no, size_t First,
+          size_t... I>
 constexpr inline auto build_pb_variant_fields(size_t offset,
                                               std::string_view name,
                                               std::index_sequence<I...>) {
   return std::tuple(
       pb_field_t<T, value_type, field_no + I + 1,
-                 std::variant_alternative_t<I, value_type>>{offset, name}...);
+                 std::variant_alternative_t<I + First, value_type>>{offset,
+                                                                    name}...);
+}
+
+template <typename T, typename ValueType, size_t First, size_t... FieldNos,
+          size_t... I>
+constexpr inline auto build_pb_oneof_fields_impl(size_t offset,
+                                                 std::string_view name,
+                                                 std::index_sequence<I...>) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  using value_type = ylt::reflection::remove_cvref_t<ValueType>;
+  return std::tuple(
+      pb_field_t<U, value_type, FieldNos,
+                 std::variant_alternative_t<I + First, value_type>>{offset,
+                                                                    name}...);
+}
+
+template <typename T, typename ValueType, size_t... FieldNos>
+constexpr inline auto build_pb_oneof_fields(size_t offset,
+                                            std::string_view name) {
+  using value_type = ylt::reflection::remove_cvref_t<ValueType>;
+  if constexpr (!is_variant<value_type>::value) {
+    static_assert(is_variant<value_type>::value,
+                  "pb_oneof_field member must be std::variant");
+    return std::tuple<>{};
+  }
+  else if constexpr (!std::is_same_v<std::variant_alternative_t<0, value_type>,
+                                     std::monostate>) {
+    static_assert(std::is_same_v<std::variant_alternative_t<0, value_type>,
+                                 std::monostate>,
+                  "pb_oneof_field member must start with std::monostate");
+    return std::tuple<>{};
+  }
+  else if constexpr (sizeof...(FieldNos) !=
+                     pb_variant_case_count<value_type>()) {
+    static_assert(sizeof...(FieldNos) == pb_variant_case_count<value_type>(),
+                  "pb_oneof_field field number count must match variant "
+                  "alternatives excluding std::monostate");
+    return std::tuple<>{};
+  }
+  else {
+    static_assert(
+        (is_valid_pb_field_no(FieldNos) && ...),
+        "protobuf oneof field numbers must be in [1, 2^29 - 1] and not in "
+        "[19000, 19999]");
+    constexpr size_t first = pb_variant_first_case_index<value_type>();
+    return build_pb_oneof_fields_impl<T, value_type, first, FieldNos...>(
+        offset, name, std::make_index_sequence<sizeof...(FieldNos)>{});
+  }
 }
 
-template <typename T, size_t field_no, typename ValueType>
+template <typename T, size_t field_no, typename ValueType,
+          bool BytesSchema = false, bool TimestampSchema = false,
+          bool DurationSchema = false, bool OptionalSchema = false,
+          bool ZigzagSchema = false, bool FixedSchema = false,
+          typename WireValueType = ValueType>
 constexpr inline auto build_pb_fields_impl(size_t offset,
                                            std::string_view name) {
   using value_type = ylt::reflection::remove_cvref_t<ValueType>;
+  using wire_value_type = ylt::reflection::remove_cvref_t<WireValueType>;
   using U = std::remove_reference_t<T>;
 
   if constexpr (is_variant<value_type>::value) {
-    constexpr uint32_t variant_size = std::variant_size_v<value_type>;
-    return build_pb_variant_fields<U, value_type, field_no>(
+    constexpr size_t first = pb_variant_first_case_index<value_type>();
+    constexpr size_t variant_size = pb_variant_case_count<value_type>();
+    return build_pb_variant_fields<U, value_type, field_no, first>(
         offset, name, std::make_index_sequence<variant_size>{});
   }
   else {
-    return std::tuple(pb_field_t<U, value_type, field_no + 1>{offset, name});
+    return std::tuple(
+        pb_field_t<U, value_type, field_no + 1, value_type, BytesSchema,
+                   TimestampSchema, DurationSchema, OptionalSchema,
+                   ZigzagSchema, FixedSchema, wire_value_type, wire_value_type>{
+            offset, name});
   }
 }
 
+template <bool Zigzag, bool Fixed, typename T>
+struct pb_wire_type_selector {
+  using type = T;
+};
+
+template <>
+struct pb_wire_type_selector<true, false, int32_t> {
+  using type = iguana::sint32_t;
+};
+
+template <>
+struct pb_wire_type_selector<true, false, int64_t> {
+  using type = iguana::sint64_t;
+};
+
+template <>
+struct pb_wire_type_selector<false, true, uint32_t> {
+  using type = iguana::fixed32_t;
+};
+
+template <>
+struct pb_wire_type_selector<false, true, uint64_t> {
+  using type = iguana::fixed64_t;
+};
+
+template <>
+struct pb_wire_type_selector<false, true, int32_t> {
+  using type = iguana::sfixed32_t;
+};
+
+template <>
+struct pb_wire_type_selector<false, true, int64_t> {
+  using type = iguana::sfixed64_t;
+};
+
+template <bool Zigzag, bool Fixed, typename T>
+struct pb_wire_type_selector<Zigzag, Fixed, std::optional<T>> {
+  using type = std::optional<typename pb_wire_type_selector<
+      Zigzag, Fixed, ylt::reflection::remove_cvref_t<T>>::type>;
+};
+
+template <bool Zigzag, bool Fixed, typename T, typename Alloc>
+struct pb_wire_type_selector<Zigzag, Fixed, std::vector<T, Alloc>> {
+  using type = std::vector<typename pb_wire_type_selector<
+      Zigzag, Fixed, ylt::reflection::remove_cvref_t<T>>::type>;
+};
+
+template <typename T>
+struct pb_annotation_leaf_type {
+  using type = ylt::reflection::remove_cvref_t<T>;
+};
+
+template <typename T>
+struct pb_annotation_leaf_type<std::optional<T>> {
+  using type = ylt::reflection::remove_cvref_t<T>;
+};
+
+template <typename T, typename Alloc>
+struct pb_annotation_leaf_type<std::vector<T, Alloc>> {
+  using type = ylt::reflection::remove_cvref_t<T>;
+};
+
+template <typename T>
+using pb_annotation_leaf_type_t =
+    typename pb_annotation_leaf_type<ylt::reflection::remove_cvref_t<T>>::type;
+
+template <typename T>
+struct is_pb_zigzag_option : std::false_type {};
+
+template <>
+struct is_pb_zigzag_option<iguana::pb_zigzag_annotation> : std::true_type {};
+
+template <typename T>
+struct is_pb_fixed_option : std::false_type {};
+
+template <>
+struct is_pb_fixed_option<iguana::pb_fixed_annotation> : std::true_type {};
+
+template <typename T>
+struct is_pb_bytes_option : std::false_type {};
+
+template <>
+struct is_pb_bytes_option<iguana::pb_bytes_annotation> : std::true_type {};
+
+template <typename T>
+struct is_pb_timestamp_option : std::false_type {};
+
+template <>
+struct is_pb_timestamp_option<iguana::pb_timestamp_annotation>
+    : std::true_type {};
+
+template <typename T>
+struct is_pb_duration_option : std::false_type {};
+
+template <>
+struct is_pb_duration_option<iguana::pb_duration_annotation> : std::true_type {
+};
+
+template <typename T>
+struct is_pb_optional_option : std::false_type {};
+
+template <>
+struct is_pb_optional_option<iguana::pb_optional_annotation> : std::true_type {
+};
+
+template <typename... Options>
+struct pb_schema_options {
+  static constexpr bool bytes =
+      (is_pb_bytes_option<std::remove_cvref_t<Options>>::value || ...);
+  static constexpr bool timestamp =
+      (is_pb_timestamp_option<std::remove_cvref_t<Options>>::value || ...);
+  static constexpr bool duration =
+      (is_pb_duration_option<std::remove_cvref_t<Options>>::value || ...);
+  static constexpr bool optional =
+      (is_pb_optional_option<std::remove_cvref_t<Options>>::value || ...);
+  static constexpr bool zigzag =
+      (is_pb_zigzag_option<std::remove_cvref_t<Options>>::value || ...);
+  static constexpr bool fixed =
+      (is_pb_fixed_option<std::remove_cvref_t<Options>>::value || ...);
+};
+
+template <typename Owner, typename Value>
+struct pb_unknown_fields_t {
+  using owner_type = ylt::reflection::remove_cvref_t<Owner>;
+  using value_type = Value;
+
+  auto& value(owner_type& value) const {
+    auto member_ptr = (value_type*)((char*)(&value) + offset);
+    return *member_ptr;
+  }
+  auto const& value(const owner_type& value) const {
+    auto member_ptr = (value_type*)((char*)(&value) + offset);
+    return *member_ptr;
+  }
+
+  size_t offset;
+  std::string_view field_name;
+};
+
+template <typename T>
+struct is_pb_unknown_fields_descriptor : std::false_type {};
+
+template <typename Owner, typename Value>
+struct is_pb_unknown_fields_descriptor<pb_unknown_fields_t<Owner, Value>>
+    : std::true_type {};
+
+template <typename T>
+inline constexpr bool is_pb_unknown_fields_descriptor_v =
+    is_pb_unknown_fields_descriptor<ylt::reflection::remove_cvref_t<T>>::value;
+
+template <typename T>
+IGUANA_INLINE auto pb_member_tuple_item(T&& value) {
+  if constexpr (is_pb_unknown_fields_descriptor_v<T>) {
+    return std::tuple<>{};
+  }
+  else {
+    return std::make_tuple(std::forward<T>(value));
+  }
+}
+
+template <typename Tuple, size_t... I>
+IGUANA_INLINE auto filter_pb_member_tuple_impl(Tuple&& tp,
+                                               std::index_sequence<I...>) {
+  return std::tuple_cat(
+      pb_member_tuple_item(std::get<I>(std::forward<Tuple>(tp)))...);
+}
+
+template <typename Tuple>
+IGUANA_INLINE auto filter_pb_member_tuple(Tuple&& tp) {
+  using tuple_type = ylt::reflection::remove_cvref_t<Tuple>;
+  return filter_pb_member_tuple_impl(
+      std::forward<Tuple>(tp),
+      std::make_index_sequence<std::tuple_size_v<tuple_type>>{});
+}
+
+template <typename Tuple, size_t... I>
+constexpr size_t pb_unknown_fields_count_tuple(std::index_sequence<I...>) {
+  return ((is_pb_unknown_fields_descriptor_v<std::tuple_element_t<I, Tuple>>
+               ? size_t{1}
+               : size_t{0}) +
+          ...);
+}
+
+template <typename Tuple>
+constexpr size_t pb_unknown_fields_count_tuple() {
+  constexpr size_t N = std::tuple_size_v<Tuple>;
+  if constexpr (N == 0) {
+    return 0;
+  }
+  else {
+    return pb_unknown_fields_count_tuple<Tuple>(std::make_index_sequence<N>{});
+  }
+}
+
+template <typename T, typename Field, typename Func>
+IGUANA_INLINE void visit_pb_unknown_field(T&& t, Field&& field, Func&& func) {
+  using field_type = ylt::reflection::remove_cvref_t<Field>;
+  if constexpr (is_pb_unknown_fields_descriptor_v<field_type>) {
+    using value_type = typename field_type::value_type;
+    static_assert(std::is_same_v<value_type, std::string>,
+                  "pb_unknown_fields member must be std::string");
+    func(field.value(t));
+  }
+}
+
+template <typename T, typename Tuple, typename Func, size_t... I>
+IGUANA_INLINE void visit_pb_unknown_fields_tuple(T&& t, Tuple&& tp, Func&& func,
+                                                 std::index_sequence<I...>) {
+  (visit_pb_unknown_field(t, std::get<I>(tp), func), ...);
+}
+
+template <typename T, typename Func>
+IGUANA_INLINE void visit_pb_unknown_fields_custom(T&& t, Func&& func) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  if constexpr (is_custom_reflection_v<U>) {
+    auto tp = get_members_impl((U*)nullptr);
+    using Tuple = ylt::reflection::remove_cvref_t<decltype(tp)>;
+    static_assert(pb_unknown_fields_count_tuple<Tuple>() <= 1,
+                  "only one pb_unknown_fields member is supported");
+    visit_pb_unknown_fields_tuple(
+        t, tp, std::forward<Func>(func),
+        std::make_index_sequence<std::tuple_size_v<Tuple>>{});
+  }
+}
+
+#ifdef YLT_USE_CXX26_REFLECTION
+template <typename T>
+struct is_pb_field_annotation : std::false_type {};
+
+template <>
+struct is_pb_field_annotation<iguana::pb_field_annotation> : std::true_type {};
+
+template <typename T>
+struct is_pb_zigzag_annotation : std::false_type {};
+
+template <>
+struct is_pb_zigzag_annotation<iguana::pb_zigzag_annotation> : std::true_type {
+};
+
+template <typename T>
+struct is_pb_fixed_annotation : std::false_type {};
+
+template <>
+struct is_pb_fixed_annotation<iguana::pb_fixed_annotation> : std::true_type {};
+
+template <typename T>
+struct is_pb_bytes_annotation : std::false_type {};
+
+template <>
+struct is_pb_bytes_annotation<iguana::pb_bytes_annotation> : std::true_type {};
+
+template <typename T>
+struct is_pb_oneof_annotation : std::false_type {};
+
+template <size_t... Ns>
+struct is_pb_oneof_annotation<iguana::pb_oneof_annotation<Ns...>>
+    : std::true_type {};
+
+template <typename T>
+struct is_pb_timestamp_annotation : std::false_type {};
+
+template <>
+struct is_pb_timestamp_annotation<iguana::pb_timestamp_annotation>
+    : std::true_type {};
+
+template <typename T>
+struct is_pb_duration_annotation : std::false_type {};
+
+template <>
+struct is_pb_duration_annotation<iguana::pb_duration_annotation>
+    : std::true_type {};
+
+template <typename T>
+struct is_pb_optional_annotation : std::false_type {};
+
+template <>
+struct is_pb_optional_annotation<iguana::pb_optional_annotation>
+    : std::true_type {};
+
+template <typename T>
+struct is_pb_unknown_fields_annotation : std::false_type {};
+
+template <>
+struct is_pb_unknown_fields_annotation<iguana::pb_unknown_fields_annotation>
+    : std::true_type {};
+
+template <std::meta::info Member>
+consteval bool pb_zigzag_26() {
+  return reflect26::has_annotation_26<Member, is_pb_zigzag_annotation>();
+}
+
+template <std::meta::info Member>
+consteval bool pb_fixed_26() {
+  return reflect26::has_annotation_26<Member, is_pb_fixed_annotation>();
+}
+
+template <std::meta::info Member>
+consteval bool pb_unknown_fields_26() {
+  return reflect26::has_annotation_26<Member,
+                                      is_pb_unknown_fields_annotation>();
+}
+
+template <std::meta::info Member>
+consteval bool pb_bytes_26() {
+  return reflect26::has_annotation_26<Member, is_pb_bytes_annotation>();
+}
+
+template <std::meta::info Member>
+consteval bool pb_oneof_26() {
+  return reflect26::has_annotation_26<Member, is_pb_oneof_annotation>();
+}
+
+template <std::meta::info Member>
+consteval bool pb_as_timestamp_26() {
+  return reflect26::has_annotation_26<Member, is_pb_timestamp_annotation>();
+}
+
+template <std::meta::info Member>
+consteval bool pb_as_duration_26() {
+  return reflect26::has_annotation_26<Member, is_pb_duration_annotation>();
+}
+
+template <std::meta::info Member>
+consteval bool pb_optional_26() {
+  return reflect26::has_annotation_26<Member, is_pb_optional_annotation>();
+}
+
+template <std::meta::info Member>
+consteval size_t pb_oneof_count_26() {
+  static constexpr auto annotations = reflect26::annotations_array<Member>();
+  template for (constexpr auto annotation : annotations) {
+    using annotation_t = reflect26::remove_cvref_meta_type_t<annotation>;
+    if constexpr (is_pb_oneof_annotation<annotation_t>::value) {
+      return annotation_t::values.size();
+    }
+  }
+  return 0;
+}
+
+template <std::meta::info Member, size_t I>
+consteval size_t pb_oneof_field_no_26() {
+  static constexpr auto annotations = reflect26::annotations_array<Member>();
+  template for (constexpr auto annotation : annotations) {
+    using annotation_t = reflect26::remove_cvref_meta_type_t<annotation>;
+    if constexpr (is_pb_oneof_annotation<annotation_t>::value) {
+      constexpr auto field_no = annotation_t::values[I];
+      static_assert(field_no > 0,
+                    "protobuf oneof field number must be positive");
+      static_assert(field_no <= ((size_t{1} << 29) - 1),
+                    "protobuf oneof field number exceeds 2^29 - 1");
+      static_assert(field_no < 19000 || field_no > 19999,
+                    "protobuf oneof field number is in reserved range "
+                    "[19000, 19999]");
+      return field_no;
+    }
+  }
+  return 0;
+}
+
+template <std::meta::info Member, typename ValueType>
+struct pb_wire_type_26 {
+  using value_type = ylt::reflection::remove_cvref_t<ValueType>;
+  static_assert(!(pb_zigzag_26<Member>() && pb_fixed_26<Member>()),
+                "protobuf field can't use both pb_zigzag and pb_fixed");
+  using type =
+      typename pb_wire_type_selector<pb_zigzag_26<Member>(),
+                                     pb_fixed_26<Member>(), value_type>::type;
+};
+
+template <typename T>
+consteval size_t pb_unknown_fields_count_26() {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static constexpr auto members = reflect26::data_members_array<U>();
+  size_t count = 0;
+  template for (constexpr auto member : members) {
+    if constexpr (pb_unknown_fields_26<member>()) {
+      ++count;
+    }
+  }
+  return count;
+}
+
+template <typename T, typename Func>
+IGUANA_INLINE void visit_pb_unknown_fields_26(T&& t, Func&& func) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static_assert(pb_unknown_fields_count_26<U>() <= 1,
+                "only one pb_unknown_fields member is supported");
+  static constexpr auto members = reflect26::data_members_array<U>();
+  template for (constexpr auto member : members) {
+    if constexpr (pb_unknown_fields_26<member>()) {
+      using field_type =
+          ylt::reflection::remove_cvref_t<decltype(t.[:member:])>;
+      static_assert(std::is_same_v<field_type, std::string>,
+                    "pb_unknown_fields member must be std::string");
+      func(t.[:member:]);
+    }
+  }
+}
+
+template <typename T>
+IGUANA_INLINE size_t pb_unknown_fields_size_26(const T& t) {
+  size_t size = 0;
+  visit_pb_unknown_fields_26(t, [&](const std::string& fields) {
+    size += fields.size();
+  });
+  return size;
+}
+
+template <typename T, typename Writer>
+IGUANA_INLINE void write_pb_unknown_fields_26(const T& t, Writer& writer) {
+  visit_pb_unknown_fields_26(t, [&](const std::string& fields) {
+    writer.write(fields.data(), fields.size());
+  });
+}
+
+template <typename T>
+IGUANA_INLINE void append_pb_unknown_field_26(T& t, const char* data,
+                                              size_t size) {
+  visit_pb_unknown_fields_26(t, [&](std::string& fields) {
+    fields.append(data, size);
+  });
+}
+
+template <typename T, size_t I>
+consteval size_t pb_field_width_26() {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static constexpr auto members = reflect26::data_members_array<U>();
+  if constexpr (pb_unknown_fields_26<members[I]>()) {
+    return 0;
+  }
+  else {
+    using value_type = reflect26::remove_cvref_meta_type_t<members[I]>;
+    if constexpr (is_variant<value_type>::value) {
+      if constexpr (pb_oneof_26<members[I]>()) {
+        return pb_oneof_count_26<members[I]>();
+      }
+      else {
+        return pb_variant_case_count<value_type>();
+      }
+    }
+    else {
+      return 1;
+    }
+  }
+}
+
+template <typename T, size_t I>
+consteval size_t pb_default_field_index_26() {
+  if constexpr (I == 0) {
+    return 0;
+  }
+  else {
+    return pb_default_field_index_26<T, I - 1>() +
+           pb_field_width_26<T, I - 1>();
+  }
+}
+
+template <std::meta::info Member>
+consteval size_t pb_field_no_26() {
+  static constexpr auto annotations = reflect26::annotations_array<Member>();
+  template for (constexpr auto annotation : annotations) {
+    using annotation_t = reflect26::remove_cvref_meta_type_t<annotation>;
+    if constexpr (is_pb_field_annotation<annotation_t>::value) {
+      constexpr auto field_no =
+          std::meta::extract<iguana::pb_field_annotation>(annotation).value;
+      static_assert(field_no > 0, "protobuf field number must be positive");
+      static_assert(field_no <= ((size_t{1} << 29) - 1),
+                    "protobuf field number exceeds 2^29 - 1");
+      static_assert(field_no < 19000 || field_no > 19999,
+                    "protobuf field number is in reserved range "
+                    "[19000, 19999]");
+      return field_no;
+    }
+  }
+  return 0;
+}
+
+template <typename T, size_t I, size_t DefaultIndex>
+consteval size_t pb_field_index_26() {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static constexpr auto members = reflect26::data_members_array<U>();
+  if constexpr (I < members.size()) {
+    constexpr auto field_no = pb_field_no_26<members[I]>();
+    if constexpr (field_no > 0) {
+      return field_no - 1;
+    }
+  }
+  return DefaultIndex;
+}
+
+template <typename T, size_t I, typename ValueType>
+struct pb_field_value_type_26 {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static constexpr auto members = reflect26::data_members_array<U>();
+  using type = typename pb_wire_type_26<members[I], ValueType>::type;
+};
+
+template <typename T, typename ValueType, std::meta::info Member, size_t... I>
+constexpr inline auto build_pb_oneof_fields_26(size_t offset,
+                                               std::string_view name,
+                                               std::index_sequence<I...>) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  using value_type = ylt::reflection::remove_cvref_t<ValueType>;
+  constexpr size_t first = pb_variant_first_case_index<value_type>();
+  return std::tuple(
+      pb_field_t<U, value_type, pb_oneof_field_no_26<Member, I>(),
+                 std::variant_alternative_t<I + first, value_type>>{offset,
+                                                                    name}...);
+}
+
+template <typename T, size_t I, typename ValueType, typename Array>
+inline auto build_pb_field_26(const Array& offset_arr, std::string_view name) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static constexpr auto members = reflect26::data_members_array<U>();
+  if constexpr (pb_unknown_fields_26<members[I]>()) {
+    using value_type = ylt::reflection::remove_cvref_t<ValueType>;
+    static_assert(std::is_same_v<value_type, std::string>,
+                  "pb_unknown_fields member must be std::string");
+    return std::tuple<>{};
+  }
+  else {
+    constexpr size_t default_index = pb_default_field_index_26<U, I>();
+    using value_type = ylt::reflection::remove_cvref_t<ValueType>;
+    using annotation_leaf_type = pb_annotation_leaf_type_t<value_type>;
+    if constexpr (pb_oneof_26<members[I]>()) {
+      static_assert(is_variant<value_type>::value,
+                    "pb_oneof member must be std::variant");
+      static_assert(std::is_same_v<std::variant_alternative_t<0, value_type>,
+                                   std::monostate>,
+                    "pb_oneof member must start with std::monostate");
+      static_assert(pb_oneof_count_26<members[I]>() ==
+                        pb_variant_case_count<value_type>(),
+                    "pb_oneof field number count must match variant "
+                    "alternatives excluding std::monostate");
+      return build_pb_oneof_fields_26<T, ValueType, members[I]>(
+          offset_arr[I], name,
+          std::make_index_sequence<pb_oneof_count_26<members[I]>()>{});
+    }
+    else {
+      static_assert(!(pb_as_timestamp_26<members[I]>() &&
+                      pb_as_duration_26<members[I]>()),
+                    "protobuf field can't use both pb_as_timestamp and "
+                    "pb_as_duration");
+      static_assert(!pb_as_timestamp_26<members[I]>() ||
+                        std::is_same_v<annotation_leaf_type,
+                                       std::chrono::system_clock::time_point>,
+                    "pb_as_timestamp member must be "
+                    "std::chrono::system_clock::time_point, or optional/vector "
+                    "of that type");
+      static_assert(
+          !pb_as_duration_26<members[I]>() ||
+              std::is_same_v<annotation_leaf_type, std::chrono::nanoseconds>,
+          "pb_as_duration member must be std::chrono::nanoseconds, "
+          "or optional/vector of that type");
+      static_assert(!pb_bytes_26<members[I]>() ||
+                        std::is_same_v<annotation_leaf_type, std::string> ||
+                        std::is_same_v<annotation_leaf_type, std::string_view>,
+                    "pb_bytes member must be std::string, std::string_view, "
+                    "or optional/vector of that type");
+      static_assert(!pb_optional_26<members[I]>() || optional_v<value_type>,
+                    "pb_optional member must be std::optional<T>");
+      static_assert(!pb_zigzag_26<members[I]>() ||
+                        std::is_same_v<annotation_leaf_type, int32_t> ||
+                        std::is_same_v<annotation_leaf_type, int64_t>,
+                    "pb_zigzag member must be int32_t/int64_t, or "
+                    "optional/vector of that type");
+      static_assert(!pb_fixed_26<members[I]>() ||
+                        std::is_same_v<annotation_leaf_type, uint32_t> ||
+                        std::is_same_v<annotation_leaf_type, uint64_t> ||
+                        std::is_same_v<annotation_leaf_type, int32_t> ||
+                        std::is_same_v<annotation_leaf_type, int64_t>,
+                    "pb_fixed member must be 32/64-bit int, or "
+                    "optional/vector of that type");
+      return build_pb_fields_impl<
+          T, pb_field_index_26<T, I, default_index>(), ValueType,
+          pb_bytes_26<members[I]>(), pb_as_timestamp_26<members[I]>(),
+          pb_as_duration_26<members[I]>(), pb_optional_26<members[I]>(),
+          pb_zigzag_26<members[I]>(), pb_fixed_26<members[I]>(),
+          typename pb_field_value_type_26<T, I, ValueType>::type>(offset_arr[I],
+                                                                  name);
+    }
+  }
+}
+#endif
+
+template <typename T, typename Func>
+IGUANA_INLINE void visit_pb_unknown_fields(T&& t, Func&& func) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  if constexpr (is_custom_reflection_v<U>) {
+    visit_pb_unknown_fields_custom(t, std::forward<Func>(func));
+  }
+#ifdef YLT_USE_CXX26_REFLECTION
+  else if constexpr (ylt_refletable_v<U>) {
+    visit_pb_unknown_fields_26(t, std::forward<Func>(func));
+  }
+#endif
+}
+
+template <typename T>
+IGUANA_INLINE size_t pb_unknown_fields_size(const T& t) {
+  size_t size = 0;
+  visit_pb_unknown_fields(t, [&](const std::string& fields) {
+    size += fields.size();
+  });
+  return size;
+}
+
+template <typename T, typename Writer>
+IGUANA_INLINE void write_pb_unknown_fields(const T& t, Writer& writer) {
+  visit_pb_unknown_fields(t, [&](const std::string& fields) {
+    writer.write(fields.data(), fields.size());
+  });
+}
+
+template <typename T>
+IGUANA_INLINE void append_pb_unknown_field(T& t, const char* data,
+                                           size_t size) {
+  visit_pb_unknown_fields(t, [&](std::string& fields) {
+    fields.append(data, size);
+  });
+}
+
+#ifdef YLT_USE_CXX26_REFLECTION
+template <typename T, typename Array, size_t... I>
+inline auto build_pb_fields(const Array& offset_arr,
+                            std::index_sequence<I...>) {
+  constexpr auto arr = ylt::reflection::get_member_names<T>();
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static constexpr auto members = reflect26::data_members_array<U>();
+  return std::tuple_cat(
+      build_pb_field_26<T, I, reflect26::meta_type_t<members[I]>>(offset_arr,
+                                                                  arr[I])...);
+}
+#else
 template <typename Tuple, typename T, typename Array, size_t... I>
 inline auto build_pb_fields(const Array& offset_arr,
                             std::index_sequence<I...>) {
@@ -210,19 +1098,35 @@ inline auto build_pb_fields(const Array& offset_arr,
       build_pb_fields_impl<T, indexs[I], std::tuple_element_t<I, Tuple>>(
           offset_arr[I], arr[I])...);
 }
+#endif
 
 template <typename T>
 inline auto get_pb_members_tuple(T&& t) {
   using U = ylt::reflection::remove_cvref_t<T>;
   if constexpr (is_custom_reflection_v<U>) {
-    return get_members_impl((U*)nullptr);
+    auto raw = get_members_impl((U*)nullptr);
+    auto res = filter_pb_member_tuple(std::move(raw));
+    using ResultTuple = decltype(res);
+    validate_pb_members_tuple<ResultTuple>();
+    return res;
   }
   else if constexpr (ylt_refletable_v<U>) {
+#ifdef YLT_USE_CXX26_REFLECTION
+    static const auto& offset_arr =
+        ylt::reflection::internal::get_member_offset_arr<U>();
+    constexpr auto count = ylt::reflection::members_count_v<U>;
+    auto res =
+        build_pb_fields<T>(offset_arr, std::make_index_sequence<count>{});
+#else
     static auto& offset_arr = ylt::reflection::internal::get_member_offset_arr(
         ylt::reflection::internal::wrapper<U>::value);
     using Tuple = decltype(ylt::reflection::object_to_tuple(std::declval<U>()));
-    return build_pb_fields<Tuple, T>(
+    auto res = build_pb_fields<Tuple, T>(
         offset_arr, std::make_index_sequence<std::tuple_size_v<Tuple>>{});
+#endif
+    using ResultTuple = decltype(res);
+    validate_pb_members_tuple<ResultTuple>();
+    return res;
   }
   else {
     static_assert(!sizeof(T), "not a reflectable type");
@@ -278,4 +1182,146 @@ IGUANA_INLINE auto build_pb_field(std::string_view name) {
   size_t offset = member_offset((owner*)nullptr, ptr);
   return iguana::detail::pb_field_t<owner, value_type, field_no>{offset, name};
 }
-}  // namespace iguana
\ No newline at end of file
+
+template <auto ptr, size_t field_no, typename... Options>
+IGUANA_INLINE auto pb_field_ex(std::string_view name, Options... options) {
+  ((void)options, ...);
+  using owner =
+      typename ylt::reflection::member_traits<decltype(ptr)>::owner_type;
+  using value_type = ylt::reflection::remove_cvref_t<
+      typename ylt::reflection::member_traits<decltype(ptr)>::value_type>;
+  using leaf_type = detail::pb_annotation_leaf_type_t<value_type>;
+  using opts = detail::pb_schema_options<Options...>;
+  using wire_value_type =
+      typename detail::pb_wire_type_selector<opts::zigzag, opts::fixed,
+                                             value_type>::type;
+
+  static_assert(detail::is_valid_pb_field_no(field_no),
+                "protobuf field number must be in [1, 2^29 - 1] and not in "
+                "[19000, 19999]");
+  static_assert(!(opts::timestamp && opts::duration),
+                "protobuf field can't use both pb_as_timestamp and "
+                "pb_as_duration");
+  static_assert(!(opts::zigzag && opts::fixed),
+                "protobuf field can't use both pb_zigzag and pb_fixed");
+  static_assert(!opts::bytes || std::is_same_v<leaf_type, std::string> ||
+                    std::is_same_v<leaf_type, std::string_view>,
+                "pb_bytes_field member must be std::string, "
+                "std::string_view, or optional/vector of that type");
+  static_assert(
+      !opts::timestamp ||
+          std::is_same_v<leaf_type, std::chrono::system_clock::time_point>,
+      "pb_timestamp_field member must be "
+      "std::chrono::system_clock::time_point, or optional/vector of "
+      "that type");
+  static_assert(
+      !opts::duration || std::is_same_v<leaf_type, std::chrono::nanoseconds>,
+      "pb_duration_field member must be std::chrono::nanoseconds, "
+      "or optional/vector of that type");
+  static_assert(!opts::optional || optional_v<value_type>,
+                "pb_optional_field member must be std::optional<T>");
+  static_assert(!opts::zigzag || std::is_same_v<leaf_type, int32_t> ||
+                    std::is_same_v<leaf_type, int64_t>,
+                "pb_zigzag_field member must be int32_t/int64_t, or "
+                "optional/vector of that type");
+  static_assert(!opts::fixed || std::is_same_v<leaf_type, uint32_t> ||
+                    std::is_same_v<leaf_type, uint64_t> ||
+                    std::is_same_v<leaf_type, int32_t> ||
+                    std::is_same_v<leaf_type, int64_t>,
+                "pb_fixed_field member must be 32/64-bit int, or "
+                "optional/vector of that type");
+
+  size_t offset = member_offset((owner*)nullptr, ptr);
+  return iguana::detail::pb_field_t<
+      owner, value_type, field_no, value_type, opts::bytes, opts::timestamp,
+      opts::duration, opts::optional, opts::zigzag, opts::fixed,
+      wire_value_type, wire_value_type>{offset, name};
+}
+
+template <auto ptr, size_t field_no>
+IGUANA_INLINE auto pb_field(std::string_view name) {
+  return pb_field_ex<ptr, field_no>(name);
+}
+
+template <auto ptr, size_t field_no>
+IGUANA_INLINE auto pb_bytes_field(std::string_view name) {
+  return pb_field_ex<ptr, field_no>(name, pb_bytes);
+}
+
+template <auto ptr, size_t field_no>
+IGUANA_INLINE auto pb_zigzag_field(std::string_view name) {
+  return pb_field_ex<ptr, field_no>(name, pb_zigzag);
+}
+
+template <auto ptr, size_t field_no>
+IGUANA_INLINE auto pb_fixed_field(std::string_view name) {
+  return pb_field_ex<ptr, field_no>(name, pb_fixed);
+}
+
+template <auto ptr, size_t field_no>
+IGUANA_INLINE auto pb_optional_field(std::string_view name) {
+  return pb_field_ex<ptr, field_no>(name, pb_optional);
+}
+
+template <auto ptr, size_t field_no>
+IGUANA_INLINE auto pb_timestamp_field(std::string_view name) {
+  return pb_field_ex<ptr, field_no>(name, pb_as_timestamp);
+}
+
+template <auto ptr, size_t field_no>
+IGUANA_INLINE auto as_timestamp_field(std::string_view name) {
+  return pb_timestamp_field<ptr, field_no>(name);
+}
+
+template <auto ptr, size_t field_no>
+IGUANA_INLINE auto pb_duration_field(std::string_view name) {
+  return pb_field_ex<ptr, field_no>(name, pb_as_duration);
+}
+
+template <auto ptr, size_t field_no>
+IGUANA_INLINE auto as_duration_field(std::string_view name) {
+  return pb_duration_field<ptr, field_no>(name);
+}
+
+template <auto ptr>
+IGUANA_INLINE auto pb_unknown_fields_field(std::string_view name = "") {
+  using owner =
+      typename ylt::reflection::member_traits<decltype(ptr)>::owner_type;
+  using value_type = ylt::reflection::remove_cvref_t<
+      typename ylt::reflection::member_traits<decltype(ptr)>::value_type>;
+  static_assert(std::is_same_v<value_type, std::string>,
+                "pb_unknown_fields_field member must be std::string");
+  size_t offset = member_offset((owner*)nullptr, ptr);
+  return iguana::detail::pb_unknown_fields_t<owner, value_type>{offset, name};
+}
+
+template <auto ptr, size_t... field_nos>
+IGUANA_INLINE auto pb_oneof_field(std::string_view name) {
+  using owner =
+      typename ylt::reflection::member_traits<decltype(ptr)>::owner_type;
+  using value_type =
+      typename ylt::reflection::member_traits<decltype(ptr)>::value_type;
+  size_t offset = member_offset((owner*)nullptr, ptr);
+  return iguana::detail::build_pb_oneof_fields<owner, value_type, field_nos...>(
+      offset, name);
+}
+
+namespace detail {
+template <typename T>
+IGUANA_INLINE auto as_pb_member_tuple(T&& value) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  if constexpr (is_tuple<U>::value) {
+    return std::forward<T>(value);
+  }
+  else {
+    return std::make_tuple(std::forward<T>(value));
+  }
+}
+}  // namespace detail
+
+template <typename... Fields>
+IGUANA_INLINE auto pb_members(Fields&&... fields) {
+  return std::tuple_cat(
+      detail::as_pb_member_tuple(std::forward<Fields>(fields))...);
+}
+}  // namespace iguana
diff --git a/iguana/dynamic.hpp b/iguana/dynamic.hpp
--- a/iguana/dynamic.hpp
+++ b/iguana/dynamic.hpp
@@ -146,7 +146,9 @@ struct base_impl : public base {
             if (val.field_name == name) {
               using value_type =
                   typename std::remove_reference_t<decltype(val)>::value_type;
-              auto ptr = (char*)this + val.offset;
+              auto ptr =
+                  reinterpret_cast<const char*>(static_cast<const T*>(this)) +
+                  val.offset;
               result = *((value_type*)ptr);
             }
           },
@@ -160,6 +162,12 @@ struct base_impl : public base {
 
   mutable size_t cache_size = 0;
 
+ protected:
+  void* object_ptr() override { return static_cast<T*>(this); }
+  const void* object_ptr() const override {
+    return static_cast<const T*>(this);
+  }
+
  private:
   virtual void dummy() {
     // make sure init T before main, and can register_type before main.
@@ -176,4 +184,14 @@ IGUANA_INLINE std::shared_ptr<base> create_instance(std::string_view name) {
   }
   return it->second();
 }
-}  // namespace iguana
\ No newline at end of file
+}  // namespace iguana
+
+#ifdef YLT_USE_CXX26_REFLECTION
+namespace ylt::reflection::reflect26 {
+template <>
+constexpr inline bool skip_base_v<iguana::detail::base> = true;
+
+template <typename T, uint8_t ENABLE_FLAG>
+constexpr inline bool skip_base_v<iguana::base_impl<T, ENABLE_FLAG>> = true;
+}  // namespace ylt::reflection::reflect26
+#endif
diff --git a/iguana/json_reader.hpp b/iguana/json_reader.hpp
--- a/iguana/json_reader.hpp
+++ b/iguana/json_reader.hpp
@@ -2,6 +2,9 @@
 #include "detail/utf.hpp"
 #include "error_code.h"
 #include "json_util.hpp"
+#ifdef YLT_USE_CXX26_REFLECTION
+#include "ylt/reflection/reflect26_dispatch.hpp"
+#endif
 namespace iguana {
 
 template <typename T, typename It,
@@ -230,11 +233,13 @@ IGUANA_INLINE void from_json_impl(U &value, It &&it, It &&end) {
   else {
     while (it != end) {
       switch (*it) {
-        IGUANA_UNLIKELY case '\\' : ++it;
+      IGUANA_UNLIKELY case '\\':
+        ++it;
         parse_escape(value, it, end);
         break;
-        // IGUANA_UNLIKELY case ']' : return;
-        IGUANA_UNLIKELY case '"' : ++it;
+      // IGUANA_UNLIKELY case ']' : return;
+      IGUANA_UNLIKELY case '"':
+        ++it;
         return;
         IGUANA_LIKELY default : value.push_back(*it);
         ++it;
@@ -486,7 +491,7 @@ IGUANA_INLINE void from_json_impl(U &value, It &&it, It &&end) {
   }
   else {
     using value_type = typename T::value_type;
-    value_type t;
+    value_type t{};
     if constexpr (string_v<value_type> || string_view_v<value_type>) {
       if (it < end && *it == '"')
         IGUANA_LIKELY { ++it; }
@@ -554,7 +559,7 @@ template <typename value_type, typename U, typename It>
 IGUANA_INLINE bool from_json_variant_impl(U &value, It it, It end, It &temp_it,
                                           It &temp_end) {
   try {
-    value_type val;
+    value_type val{};
     from_json_impl(val, it, end);
     value = val;
     temp_it = it;
@@ -590,6 +595,48 @@ IGUANA_INLINE void from_json_impl(U &value, It &&it, It &&end) {
 }
 }  // namespace detail
 
+#ifdef YLT_USE_CXX26_REFLECTION
+template <typename T, typename It, std::enable_if_t<ylt_refletable_v<T>, int>>
+IGUANA_INLINE void from_json(T &value, It &&it, It &&end) {
+  skip_ws(it, end);
+  match<'{'>(it, end);
+  skip_ws(it, end);
+  if (*it == '}')
+    IGUANA_UNLIKELY {
+      ++it;
+      return;
+    }
+
+  while (it != end) {
+    std::string_view key = detail::get_key(it, end);
+    skip_ws(it, end);
+    match<':'>(it, end);
+    bool found = ylt::reflection::reflect26::dispatch_by_name(
+        value, key, [&](auto &field) IGUANA__INLINE_LAMBDA {
+          using namespace detail;
+          from_json_impl(field, it, end);
+        });
+    if (!found)
+      IGUANA_UNLIKELY {
+#ifdef THROW_UNKNOWN_KEY
+        throw std::runtime_error("Unknown key: " + std::string(key));
+#else
+        detail::skip_object_value(it, end);
+#endif
+      }
+    skip_ws(it, end);
+    if (*it == '}')
+      IGUANA_UNLIKELY {
+        ++it;
+        return;
+      }
+    else
+      IGUANA_LIKELY { match<','>(it, end); }
+  }
+}
+#endif
+
+#ifndef YLT_USE_CXX26_REFLECTION
 template <typename T, typename It, std::enable_if_t<ylt_refletable_v<T>, int>>
 IGUANA_INLINE void from_json(T &value, It &&it, It &&end) {
   skip_ws(it, end);
@@ -672,6 +719,7 @@ IGUANA_INLINE void from_json(T &value, It &&it, It &&end) {
     }
   }
 }
+#endif  // !YLT_USE_CXX26_REFLECTION
 
 template <typename T, typename It,
           std::enable_if_t<non_ylt_refletable_v<T>, int> = 0>
diff --git a/iguana/json_util.hpp b/iguana/json_util.hpp
--- a/iguana/json_util.hpp
+++ b/iguana/json_util.hpp
@@ -32,6 +32,9 @@ template <typename T>
 constexpr inline bool numeric_str_v =
     std::is_same_v<numeric_str, std::remove_cvref_t<T>>;
 
+template <>
+constexpr inline bool reflect26_excluded_v<numeric_str> = true;
+
 template <typename It>
 IGUANA_INLINE void skip_comment(It &&it, It &&end) {
   ++it;
diff --git a/iguana/pb_reader.hpp b/iguana/pb_reader.hpp
--- a/iguana/pb_reader.hpp
+++ b/iguana/pb_reader.hpp
@@ -11,12 +11,14 @@ template <typename T>
 IGUANA_INLINE void from_pb_impl(T& val, std::string_view& pb_str,
                                 uint32_t field_no = 0);
 
+inline void skip_unknown_field(std::string_view& pb_str, WireType wire_type,
+                               uint32_t field_number = 0);
+
 template <typename T>
 IGUANA_INLINE void decode_pair_value(T& val, std::string_view& pb_str) {
-  size_t pos;
-  uint32_t key = detail::decode_varint(pb_str, pos);
-  pb_str = pb_str.substr(pos);
-  WireType wire_type = static_cast<WireType>(key & 0b0111);
+  auto key = detail::decode_key(pb_str);
+  pb_str = pb_str.substr(key.tag_size);
+  WireType wire_type = key.wire_type;
   if (wire_type != detail::get_wire_type<std::remove_reference_t<T>>()) {
     return;
   }
@@ -28,13 +30,8 @@ IGUANA_INLINE void from_pb_impl(T& val, std::string_view& pb_str,
                                 uint32_t field_no) {
   size_t pos = 0;
   if constexpr (ylt_refletable_v<T>) {
-    size_t pos;
-    uint32_t size = detail::decode_varint(pb_str, pos);
-    pb_str = pb_str.substr(pos);
-    if (pb_str.size() < size)
-      IGUANA_UNLIKELY {
-        throw std::invalid_argument("Invalid fixed int value: too few bytes.");
-      }
+    const size_t size = detail::decode_length_delimited(
+        pb_str, "Invalid message value: too few bytes.");
     if (size == 0) {
       return;
     }
@@ -52,72 +49,90 @@ IGUANA_INLINE void from_pb_impl(T& val, std::string_view& pb_str,
         if (pb_str.empty()) {
           break;
         }
-        uint32_t key = detail::decode_varint(pb_str, pos);
-        uint32_t field_number = key >> 3;
-        if (field_number != field_no) {
+        auto key = detail::decode_key(pb_str);
+        if (key.field_number != field_no ||
+            key.wire_type != detail::get_wire_type<item_type>()) {
           break;
         }
         else {
-          pb_str = pb_str.substr(pos);
+          pb_str = pb_str.substr(key.tag_size);
         }
       }
     }
     else {
       // item_type packed
-      size_t pos;
-      uint32_t size = detail::decode_varint(pb_str, pos);
-      pb_str = pb_str.substr(pos);
-      if (pb_str.size() < size)
-        IGUANA_UNLIKELY {
-          throw std::invalid_argument(
-              "Invalid fixed int value: too few bytes.");
-        }
+      const size_t size = detail::decode_length_delimited(
+          pb_str, "Invalid packed repeated value: too few bytes.");
+      std::string_view packed = pb_str.substr(0, size);
+      pb_str = pb_str.substr(size);
       if constexpr (is_fixed_v<item_type>) {
-        int num = size / sizeof(item_type);
-        int old_size = val.size();
+        if (size % sizeof(item_type) != 0)
+          IGUANA_UNLIKELY {
+            throw std::invalid_argument(
+                "Invalid packed fixed repeated value: bad length.");
+          }
+        size_t num = size / sizeof(item_type);
+        size_t old_size = val.size();
         detail::resize(val, old_size + num);
-        std::memcpy(val.data() + old_size, pb_str.data(), size);
-        pb_str = pb_str.substr(size);
+        std::memcpy(val.data() + old_size, packed.data(), size);
       }
       else {
-        size_t start = pb_str.size();
-
-        while (!pb_str.empty()) {
+        while (!packed.empty()) {
           item_type item;
-          from_pb_impl(item, pb_str);
+          from_pb_impl(item, packed);
           val.push_back(std::move(item));
-          if (start - pb_str.size() == size) {
-            break;
-          }
         }
       }
     }
   }
   else if constexpr (is_map_container<T>::value) {
-    using item_type = std::pair<typename T::key_type, typename T::mapped_type>;
+    using key_type = typename T::key_type;
+    using mapped_type = typename T::mapped_type;
     while (!pb_str.empty()) {
-      size_t pos;
-      uint32_t size = detail::decode_varint(pb_str, pos);
-      pb_str = pb_str.substr(pos);
-      if (pb_str.size() < size)
-        IGUANA_UNLIKELY {
-          throw std::invalid_argument(
-              "Invalid fixed int value: too few bytes.");
+      const size_t size = detail::decode_length_delimited(
+          pb_str, "Invalid map entry value: too few bytes.");
+      std::string_view entry = pb_str.substr(0, size);
+      pb_str = pb_str.substr(size);
+
+      key_type map_key{};
+      mapped_type mapped{};
+      while (!entry.empty()) {
+        auto entry_key = detail::decode_key(entry);
+        WireType entry_wire_type = entry_key.wire_type;
+        uint32_t entry_field_number = entry_key.field_number;
+        entry = entry.substr(entry_key.tag_size);
+
+        if (entry_field_number == 1) {
+          if (entry_wire_type == detail::get_wire_type<key_type>()) {
+            from_pb_impl(map_key, entry, 1);
+          }
+          else {
+            skip_unknown_field(entry, entry_wire_type, entry_field_number);
+          }
+        }
+        else if (entry_field_number == 2) {
+          if (entry_wire_type == detail::get_wire_type<mapped_type>()) {
+            from_pb_impl(mapped, entry, 2);
+          }
+          else {
+            skip_unknown_field(entry, entry_wire_type, entry_field_number);
+          }
+        }
+        else {
+          skip_unknown_field(entry, entry_wire_type, entry_field_number);
         }
-      item_type item = {};
-      decode_pair_value(item.first, pb_str);
-      decode_pair_value(item.second, pb_str);
-      val.emplace(std::move(item));
+      }
+      val.insert_or_assign(std::move(map_key), std::move(mapped));
 
       if (pb_str.empty()) {
         break;
       }
-      uint32_t key = detail::decode_varint(pb_str, pos);
-      uint32_t field_number = key >> 3;
-      if (field_number != field_no) {
+      auto key = detail::decode_key(pb_str);
+      if (key.field_number != field_no ||
+          key.wire_type != WireType::LengthDelimeted) {
         break;
       }
-      pb_str = pb_str.substr(pos);
+      pb_str = pb_str.substr(key.tag_size);
     }
   }
   else if constexpr (std::is_integral_v<T>) {
@@ -155,19 +170,16 @@ IGUANA_INLINE void from_pb_impl(T& val, std::string_view& pb_str,
   }
   else if constexpr (std::is_same_v<T, std::string> ||
                      std::is_same_v<T, std::string_view>) {
-    size_t size = detail::decode_varint(pb_str, pos);
-    if (pb_str.size() < pos + size)
-      IGUANA_UNLIKELY {
-        throw std::invalid_argument("Invalid string value: too few bytes.");
-      }
+    const size_t size = detail::decode_length_delimited(
+        pb_str, "Invalid string value: too few bytes.");
     if constexpr (std::is_same_v<T, std::string_view>) {
-      val = std::string_view(pb_str.data() + pos, size);
+      val = std::string_view(pb_str.data(), size);
     }
     else {
       detail::resize(val, size);
-      memcpy(val.data(), pb_str.data() + pos, size);
+      memcpy(val.data(), pb_str.data(), size);
     }
-    pb_str = pb_str.substr(size + pos);
+    pb_str = pb_str.substr(size);
   }
   else if constexpr (std::is_enum_v<T>) {
     using U = std::underlying_type_t<T>;
@@ -176,7 +188,10 @@ IGUANA_INLINE void from_pb_impl(T& val, std::string_view& pb_str,
     val = static_cast<T>(value);
   }
   else if constexpr (optional_v<T>) {
-    from_pb_impl(val.emplace(), pb_str);
+    if (!val.has_value()) {
+      val.emplace();
+    }
+    from_pb_impl(*val, pb_str, field_no);
   }
   else {
     static_assert(!sizeof(T), "err");
@@ -189,11 +204,127 @@ IGUANA_INLINE void parse_oneof(T& t, const Field& f, std::string_view& pb_str) {
   from_pb_impl(t.template emplace<item_type>(), pb_str, f.field_no);
 }
 
+template <typename T>
+constexpr bool is_unpacked_repeated_type() {
+  using value_type = std::remove_const_t<std::remove_reference_t<T>>;
+  if constexpr (is_sequence_container<value_type>::value) {
+    using item_type = typename value_type::value_type;
+    return !is_lenprefix_v<item_type>;
+  }
+  else {
+    return false;
+  }
+}
+
+template <typename T>
+constexpr bool is_unpacked_repeated_wire_type(WireType wire_type) {
+  using value_type = std::remove_const_t<std::remove_reference_t<T>>;
+  if constexpr (is_unpacked_repeated_type<value_type>()) {
+    using item_type = typename value_type::value_type;
+    return wire_type == detail::get_wire_type<item_type>();
+  }
+  else {
+    return false;
+  }
+}
+
+template <typename T>
+IGUANA_INLINE void from_pb_unpacked_repeated_item(T& val,
+                                                  std::string_view& pb_str) {
+  using value_type = std::remove_const_t<std::remove_reference_t<T>>;
+  using item_type = typename value_type::value_type;
+  item_type item{};
+  from_pb_impl(item, pb_str);
+  val.push_back(std::move(item));
+}
+
+template <bool TimestampSchema, typename T>
+IGUANA_INLINE auto from_pb_well_known_value(const T* current,
+                                            std::string_view& pb_str,
+                                            uint32_t field_no) {
+  using value_type = std::remove_const_t<std::remove_reference_t<T>>;
+  if constexpr (TimestampSchema) {
+    iguana::pb_timestamp wire_value{};
+    if (current != nullptr) {
+      wire_value = iguana::pb_timestamp{*current};
+    }
+    from_pb_impl(wire_value, pb_str, field_no);
+    return static_cast<value_type>(wire_value);
+  }
+  else {
+    iguana::pb_duration wire_value{};
+    if (current != nullptr) {
+      wire_value = iguana::pb_duration{*current};
+    }
+    from_pb_impl(wire_value, pb_str, field_no);
+    return static_cast<value_type>(wire_value);
+  }
+}
+
+template <bool TimestampSchema, typename T>
+IGUANA_INLINE void from_pb_well_known_impl(T& val, std::string_view& pb_str,
+                                           uint32_t field_no) {
+  using value_type = std::remove_const_t<std::remove_reference_t<T>>;
+  if constexpr (optional_v<value_type>) {
+    using item_type = typename value_type::value_type;
+    const item_type* current = val.has_value() ? &*val : nullptr;
+    val = from_pb_well_known_value<TimestampSchema, item_type>(current, pb_str,
+                                                               field_no);
+  }
+  else if constexpr (is_sequence_container<value_type>::value) {
+    using item_type = typename value_type::value_type;
+    val.push_back(from_pb_well_known_value<TimestampSchema, item_type>(
+        nullptr, pb_str, field_no));
+  }
+  else {
+    val = from_pb_well_known_value<TimestampSchema, value_type>(&val, pb_str,
+                                                                field_no);
+  }
+}
+
+template <typename Wire, typename T>
+IGUANA_INLINE void from_pb_schema_impl(T& val, std::string_view& pb_str,
+                                       uint32_t field_no) {
+  using value_type = ylt::reflection::remove_cvref_t<T>;
+  using wire_type = ylt::reflection::remove_cvref_t<Wire>;
+  if constexpr (std::is_same_v<value_type, wire_type>) {
+    from_pb_impl(val, pb_str, field_no);
+  }
+  else if constexpr (is_sequence_container<value_type>::value) {
+    using wire_item_type = typename wire_type::value_type;
+    if constexpr (is_lenprefix_v<wire_item_type>) {
+      wire_type wire_value{};
+      from_pb_impl(wire_value, pb_str, field_no);
+      assign_pb_wire_value(val, std::move(wire_value));
+    }
+    else {
+      const size_t size = decode_length_delimited(
+          pb_str, "Invalid packed repeated value: too few bytes.");
+      std::string_view packed = pb_str.substr(0, size);
+      pb_str = pb_str.substr(size);
+      while (!packed.empty()) {
+        wire_item_type wire_item{};
+        from_pb_impl(wire_item, packed);
+        typename value_type::value_type item{};
+        assign_pb_wire_value(item, std::move(wire_item));
+        val.push_back(std::move(item));
+      }
+    }
+  }
+  else {
+    wire_type wire_value{};
+    from_pb_impl(wire_value, pb_str, field_no);
+    assign_pb_wire_value(val, std::move(wire_value));
+  }
+}
+
 // pb_str must already point past the field tag varint.
-IGUANA_INLINE void skip_unknown_field(std::string_view& pb_str,
-                                      WireType wire_type) {
+inline void skip_unknown_field(std::string_view& pb_str, WireType wire_type,
+                               uint32_t field_number) {
   switch (wire_type) {
     case WireType::Varint: {
+      if (pb_str.empty())
+        throw std::invalid_argument("unknown Varint field: too few bytes");
       size_t skip_pos = 0;
       decode_varint(pb_str, skip_pos);
       pb_str = pb_str.substr(skip_pos);
@@ -205,19 +336,37 @@ IGUANA_INLINE void skip_unknown_field(std::string_view& pb_str,
       pb_str = pb_str.substr(8);
       break;
     case WireType::LengthDelimeted: {
-      size_t skip_pos = 0;
-      uint64_t len = decode_varint(pb_str, skip_pos);
-      if (pb_str.size() < skip_pos + len)
-        throw std::invalid_argument(
-            "unknown LengthDelimited field: too few bytes");
-      pb_str = pb_str.substr(skip_pos + len);
+      const size_t len = decode_length_delimited(
+          pb_str, "unknown LengthDelimited field: too few bytes");
+      pb_str = pb_str.substr(len);
       break;
     }
     case WireType::Fixed32:
       if (pb_str.size() < 4)
         throw std::invalid_argument("unknown Fixed32 field: too few bytes");
       pb_str = pb_str.substr(4);
       break;
+    case WireType::StartGroup: {
+      pb_recursion_guard recursion_guard;
+      while (true) {
+        if (pb_str.empty())
+          throw std::invalid_argument("unknown group field: missing end tag");
+        auto key = detail::decode_key(pb_str, true);
+        pb_str = pb_str.substr(key.tag_size);
+        WireType child_wire_type = key.wire_type;
+        uint32_t child_field_number = key.field_number;
+        if (child_wire_type == WireType::EndGroup) {
+          if (child_field_number != field_number) {
+            throw std::invalid_argument(
+                "unknown group field: mismatched end tag");
+          }
+          return;
+        }
+        skip_unknown_field(pb_str, child_wire_type, child_field_number);
+      }
+    }
+    case WireType::EndGroup:
+      throw std::runtime_error("unexpected end group in unknown field");
     default:
       throw std::runtime_error("unknown wire type in unknown field");
   }
@@ -228,10 +377,11 @@ template <typename T>
 IGUANA_INLINE void from_pb(T& t, std::string_view pb_str) {
   if (pb_str.empty())
     IGUANA_UNLIKELY { return; }
-  size_t pos = 0;
-  uint32_t key = detail::decode_varint(pb_str, pos);
-  WireType wire_type = static_cast<WireType>(key & 0b0111);
-  uint32_t field_number = key >> 3;
+  detail::pb_recursion_guard recursion_guard;
+  auto key = detail::decode_key(pb_str);
+  size_t pos = key.tag_size;
+  WireType wire_type = key.wire_type;
+  uint32_t field_number = key.field_number;
 #ifdef SEQUENTIAL_PARSE
   static auto tp = detail::get_pb_members_tuple(t);
   constexpr size_t SIZE = std::tuple_size_v<std::decay_t<decltype(tp)>>;
@@ -242,66 +392,155 @@ IGUANA_INLINE void from_pb(T& t, std::string_view pb_str) {
         auto val = std::get<decltype(i)::value>(tp);
         using sub_type = typename std::decay_t<decltype(val)>::sub_type;
         using value_type = typename std::decay_t<decltype(val)>::value_type;
+        using wire_value_type =
+            typename std::decay_t<decltype(val)>::wire_value_type;
+        using wire_sub_type =
+            typename std::decay_t<decltype(val)>::wire_sub_type;
         constexpr bool is_variant_v = variant_v<value_type>;
         // sub_type is the element type when value_type is the variant type;
         // otherwise, they are the same.
         if (parse_done || field_number != val.field_no) {
           return;
         }
         pb_str = pb_str.substr(pos);
-        if (wire_type != detail::get_wire_type<sub_type>())
+        if constexpr (std::decay_t<decltype(val)>::timestamp_schema ||
+                      std::decay_t<decltype(val)>::duration_schema) {
+          if (wire_type != WireType::LengthDelimeted) {
+            throw std::runtime_error("unmatched wire_type");
+          }
+        }
+        else if constexpr (std::is_same_v<sub_type, std::monostate>) {
+          throw std::runtime_error("oneof monostate has no wire type");
+        }
+        else if constexpr (detail::is_unpacked_repeated_type<
+                               wire_value_type>()) {
+          if (wire_type != WireType::LengthDelimeted &&
+              !detail::is_unpacked_repeated_wire_type<wire_value_type>(
+                  wire_type)) {
+            throw std::runtime_error("unmatched wire_type");
+          }
+        }
+        else if (wire_type != detail::get_wire_type<wire_sub_type>())
           IGUANA_UNLIKELY { throw std::runtime_error("unmatched wire_type"); }
 
         auto member_ptr = (value_type*)((char*)(ptr) + val.offset);
-        if constexpr (is_variant_v) {
+        if constexpr (std::decay_t<decltype(val)>::timestamp_schema ||
+                      std::decay_t<decltype(val)>::duration_schema) {
+          detail::from_pb_well_known_impl<
+              std::decay_t<decltype(val)>::timestamp_schema>(
+              *member_ptr, pb_str, val.field_no);
+        }
+        else if constexpr (detail::is_unpacked_repeated_type<
+                               wire_value_type>()) {
+          if (wire_type == WireType::LengthDelimeted) {
+            detail::from_pb_schema_impl<wire_value_type>(*member_ptr, pb_str,
+                                                         val.field_no);
+          }
+          else {
+            typename wire_value_type::value_type wire_item{};
+            detail::from_pb_impl(wire_item, pb_str);
+            typename value_type::value_type item{};
+            detail::assign_pb_wire_value(item, std::move(wire_item));
+            member_ptr->push_back(std::move(item));
+          }
+        }
+        else if constexpr (is_variant_v) {
           detail::parse_oneof(*member_ptr, val, pb_str);
         }
         else {
-          detail::from_pb_impl(*member_ptr, pb_str, val.field_no);
+          detail::from_pb_schema_impl<wire_value_type>(*member_ptr, pb_str,
+                                                       val.field_no);
         }
         if (pb_str.empty()) {
           parse_done = true;
           return;
         }
-        key = detail::decode_varint(pb_str, pos);
-        wire_type = static_cast<WireType>(key & 0b0111);
-        field_number = key >> 3;
+        key = detail::decode_key(pb_str);
+        pos = key.tag_size;
+        wire_type = key.wire_type;
+        field_number = key.field_number;
       },
       std::make_index_sequence<SIZE>{});
   if (parse_done)
     IGUANA_LIKELY { return; }
 #endif
   static auto map = detail::get_members(t);
   while (true) {
+    const char* field_start = pb_str.data();
     pb_str = pb_str.substr(pos);
     auto it = map.find(field_number);
     if (it == map.end()) {
       // Unknown field: skip according to wire type (proto3 forward compat)
-      detail::skip_unknown_field(pb_str, wire_type);
+      detail::skip_unknown_field(pb_str, wire_type, field_number);
+      detail::append_pb_unknown_field(
+          t, field_start, static_cast<size_t>(pb_str.data() - field_start));
     }
     else {
       auto& member = it->second;
       std::visit(
           [&t, &pb_str, wire_type](auto& val) {
             using sub_type = typename std::decay_t<decltype(val)>::sub_type;
             using value_type = typename std::decay_t<decltype(val)>::value_type;
-            if (wire_type != detail::get_wire_type<sub_type>()) {
+            using wire_value_type =
+                typename std::decay_t<decltype(val)>::wire_value_type;
+            using wire_sub_type =
+                typename std::decay_t<decltype(val)>::wire_sub_type;
+            if constexpr (std::decay_t<decltype(val)>::timestamp_schema ||
+                          std::decay_t<decltype(val)>::duration_schema) {
+              if (wire_type != WireType::LengthDelimeted) {
+                throw std::runtime_error("unmatched wire_type");
+              }
+            }
+            else if constexpr (std::is_same_v<sub_type, std::monostate>) {
+              throw std::runtime_error("oneof monostate has no wire type");
+            }
+            else if constexpr (detail::is_unpacked_repeated_type<
+                                   wire_value_type>()) {
+              if (wire_type != WireType::LengthDelimeted &&
+                  !detail::is_unpacked_repeated_wire_type<wire_value_type>(
+                      wire_type)) {
+                throw std::runtime_error("unmatched wire_type");
+              }
+            }
+            else if (wire_type != detail::get_wire_type<wire_sub_type>()) {
               throw std::runtime_error("unmatched wire_type");
             }
-            if constexpr (variant_v<value_type>) {
+            if constexpr (std::decay_t<decltype(val)>::timestamp_schema ||
+                          std::decay_t<decltype(val)>::duration_schema) {
+              detail::from_pb_well_known_impl<
+                  std::decay_t<decltype(val)>::timestamp_schema>(
+                  val.value(t), pb_str, val.field_no);
+            }
+            else if constexpr (detail::is_unpacked_repeated_type<
+                                   wire_value_type>()) {
+              if (wire_type == WireType::LengthDelimeted) {
+                detail::from_pb_schema_impl<wire_value_type>(
+                    val.value(t), pb_str, val.field_no);
+              }
+              else {
+                typename wire_value_type::value_type wire_item{};
+                detail::from_pb_impl(wire_item, pb_str);
+                typename value_type::value_type item{};
+                detail::assign_pb_wire_value(item, std::move(wire_item));
+                val.value(t).push_back(std::move(item));
+              }
+            }
+            else if constexpr (variant_v<value_type>) {
               detail::parse_oneof(val.value(t), val, pb_str);
             }
             else {
-              detail::from_pb_impl(val.value(t), pb_str, val.field_no);
+              detail::from_pb_schema_impl<wire_value_type>(val.value(t), pb_str,
+                                                           val.field_no);
             }
           },
           member);
     }
     if (!pb_str.empty())
       IGUANA_LIKELY {
-        key = detail::decode_varint(pb_str, pos);
-        wire_type = static_cast<WireType>(key & 0b0111);
-        field_number = key >> 3;
+        key = detail::decode_key(pb_str);
+        pos = key.tag_size;
+        wire_type = key.wire_type;
+        field_number = key.field_number;
       }
     else {
       return;
diff --git a/iguana/pb_util.hpp b/iguana/pb_util.hpp
--- a/iguana/pb_util.hpp
+++ b/iguana/pb_util.hpp
@@ -2,6 +2,7 @@
 #include <cassert>
 #include <cstddef>
 #include <cstring>
+#include <limits>
 #include <map>
 #include <stdexcept>
 #include <string>
@@ -76,6 +77,23 @@ template <typename T>
 constexpr bool is_lenprefix_v = (get_wire_type<T>() ==
                                  WireType::LengthDelimeted);
 
+template <typename T>
+inline constexpr bool pb_well_known_chrono_v =
+    std::is_same_v<std::remove_const_t<std::remove_reference_t<T>>,
+                   std::chrono::system_clock::time_point> ||
+    std::is_same_v<std::remove_const_t<std::remove_reference_t<T>>,
+                   std::chrono::nanoseconds>;
+
+template <bool TimestampSchema, typename T>
+IGUANA_INLINE auto make_pb_well_known_value(const T& value) {
+  if constexpr (TimestampSchema) {
+    return iguana::pb_timestamp{value};
+  }
+  else {
+    return iguana::pb_duration{value};
+  }
+}
+
 [[nodiscard]] IGUANA_INLINE uint32_t encode_zigzag(int32_t v) {
   return (static_cast<uint32_t>(v) << 1U) ^
          static_cast<uint32_t>(
@@ -98,90 +116,97 @@ constexpr bool is_lenprefix_v = (get_wire_type<T>() ==
 
 template <class T>
 IGUANA_INLINE uint64_t decode_varint(T& data, size_t& pos) {
-  const int8_t* begin = reinterpret_cast<const int8_t*>(data.data());
-  const int8_t* end = begin + data.size();
-  const int8_t* p = begin;
-  uint64_t val = 0;
+  if (data.empty())
+    IGUANA_UNLIKELY {
+      throw std::invalid_argument("Invalid varint value: too few bytes.");
+    }
 
-  if ((static_cast<uint64_t>(*p) & 0x80) == 0) {
-    pos = 1;
-    return static_cast<uint64_t>(*p);
-  }
-
-  // end is always greater than or equal to begin, so this subtraction is safe
-  if (size_t(end - begin) >= 10)
-    IGUANA_LIKELY {  // fast path
-      int64_t b;
-      do {
-        b = *p++;
-        val = (b & 0x7f);
-        if (b >= 0) {
-          break;
-        }
-        b = *p++;
-        val |= (b & 0x7f) << 7;
-        if (b >= 0) {
-          break;
-        }
-        b = *p++;
-        val |= (b & 0x7f) << 14;
-        if (b >= 0) {
-          break;
-        }
-        b = *p++;
-        val |= (b & 0x7f) << 21;
-        if (b >= 0) {
-          break;
-        }
-        b = *p++;
-        val |= (b & 0x7f) << 28;
-        if (b >= 0) {
-          break;
-        }
-        b = *p++;
-        val |= (b & 0x7f) << 35;
-        if (b >= 0) {
-          break;
-        }
-        b = *p++;
-        val |= (b & 0x7f) << 42;
-        if (b >= 0) {
-          break;
-        }
-        b = *p++;
-        val |= (b & 0x7f) << 49;
-        if (b >= 0) {
-          break;
-        }
-        b = *p++;
-        val |= (b & 0x7f) << 56;
-        if (b >= 0) {
-          break;
-        }
-        b = *p++;
-        val |= (b & 0x01) << 63;
-        if (b >= 0) {
-          break;
-        }
+  const auto* begin = reinterpret_cast<const unsigned char*>(data.data());
+  uint64_t val = 0;
+  const size_t size = data.size();
+  const size_t limit = size < 10 ? size : 10;
+  for (size_t i = 0; i < limit; ++i) {
+    const uint64_t byte = begin[i];
+    if (i == 9 && (byte & 0xfeU) != 0)
+      IGUANA_UNLIKELY {
         throw std::invalid_argument("Invalid varint value: too many bytes.");
-      } while (false);
+      }
+    val |= (byte & 0x7fU) << (7 * i);
+    if ((byte & 0x80U) == 0) {
+      pos = i + 1;
+      return val;
     }
-  else {
-    int shift = 0;
-    while (p != end && *p < 0) {
-      val |= static_cast<uint64_t>(*p++ & 0x7f) << shift;
-      shift += 7;
+  }
+
+  if (size >= 10)
+    IGUANA_UNLIKELY {
+      throw std::invalid_argument("Invalid varint value: too many bytes.");
+    }
+  throw std::invalid_argument("Invalid varint value: too few bytes.");
+}
+
+struct pb_key {
+  uint32_t field_number;
+  WireType wire_type;
+  size_t tag_size;
+};
+
+IGUANA_INLINE pb_key decode_key(std::string_view data,
+                                bool allow_end_group = false) {
+  size_t pos = 0;
+  const uint64_t raw_key = decode_varint(data, pos);
+  if (raw_key > std::numeric_limits<uint32_t>::max())
+    IGUANA_UNLIKELY {
+      throw std::invalid_argument("Invalid protobuf tag: too large.");
+    }
+  const uint32_t key = static_cast<uint32_t>(raw_key);
+  const uint32_t wire = key & 0b0111U;
+  const uint32_t field_number = key >> 3U;
+  if (field_number == 0)
+    IGUANA_UNLIKELY {
+      throw std::invalid_argument(
+          "Invalid protobuf tag: field number must be positive.");
     }
-    if (p == end)
+  if (wire > static_cast<uint32_t>(WireType::Fixed32))
+    IGUANA_UNLIKELY {
+      throw std::invalid_argument("Invalid protobuf tag: unknown wire type.");
+    }
+  auto wire_type = static_cast<WireType>(wire);
+  if (wire_type == WireType::EndGroup && !allow_end_group)
+    IGUANA_UNLIKELY {
+      throw std::invalid_argument("unexpected end group in protobuf stream");
+    }
+  return {field_number, wire_type, pos};
+}
+
+IGUANA_INLINE size_t decode_length_delimited(std::string_view& pb_str,
+                                             const char* error) {
+  size_t pos = 0;
+  const uint64_t size = decode_varint(pb_str, pos);
+  pb_str = pb_str.substr(pos);
+  if (size > pb_str.size())
+    IGUANA_UNLIKELY { throw std::invalid_argument(error); }
+  if (size > std::numeric_limits<size_t>::max())
+    IGUANA_UNLIKELY {
+      throw std::invalid_argument("Invalid length-delimited value: too large.");
+    }
+  return static_cast<size_t>(size);
+}
+
+inline constexpr size_t max_pb_recursion_depth = 100;
+inline thread_local size_t pb_recursion_depth = 0;
+
+struct pb_recursion_guard {
+  pb_recursion_guard() {
+    if (pb_recursion_depth >= max_pb_recursion_depth)
       IGUANA_UNLIKELY {
-        throw std::invalid_argument("Invalid varint value: too few bytes.");
+        throw std::runtime_error("protobuf message recursion limit exceeded");
       }
-    val |= static_cast<uint64_t>(*p++) << shift;
+    ++pb_recursion_depth;
   }
 
-  pos = (p - begin);
-  return val;
-}
+  ~pb_recursion_guard() { --pb_recursion_depth; }
+};
 
 // value == 0 ? 1 : floor(log2(value)) / 7 + 1
 constexpr size_t variant_uint32_size_constexpr(uint32_t value) {
@@ -401,6 +426,83 @@ template <size_t key_size, bool omit_default_val = true, typename Type,
           typename Arr>
 IGUANA_INLINE size_t pb_key_value_size(Type&& t, Arr& size_arr);
 
+template <bool TimestampSchema, size_t key_size, bool omit_default_val = true,
+          typename Type, typename Arr>
+IGUANA_INLINE size_t pb_well_known_key_value_size(Type&& t, Arr& size_arr) {
+  using T = std::remove_const_t<std::remove_reference_t<Type>>;
+  if constexpr (optional_v<T>) {
+    if (!t.has_value()) {
+      return 0;
+    }
+    return pb_well_known_key_value_size<TimestampSchema, key_size,
+                                        omit_default_val>(*t, size_arr);
+  }
+  else if constexpr (is_sequence_container<T>::value) {
+    size_t len = 0;
+    for (auto& item : t) {
+      len += pb_well_known_key_value_size<TimestampSchema, key_size, false>(
+          item, size_arr);
+    }
+    return len;
+  }
+  else {
+    auto wire_value = make_pb_well_known_value<TimestampSchema>(t);
+    return pb_key_value_size<key_size, omit_default_val>(wire_value, size_arr);
+  }
+}
+
+template <typename Wire, typename T>
+IGUANA_INLINE auto make_pb_wire_scalar(const T& value) {
+  using W = ylt::reflection::remove_cvref_t<Wire>;
+  using U = ylt::reflection::remove_cvref_t<T>;
+  if constexpr (std::is_same_v<W, U>) {
+    return value;
+  }
+  else if constexpr (is_pb_type_v<W>) {
+    return W{static_cast<typename W::value_type>(value)};
+  }
+  else {
+    return W{value};
+  }
+}
+
+template <typename T, typename Wire>
+IGUANA_INLINE void assign_pb_wire_value(T& value, Wire&& wire) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  using W = ylt::reflection::remove_cvref_t<Wire>;
+  if constexpr (std::is_same_v<U, W>) {
+    value = std::forward<Wire>(wire);
+  }
+  else if constexpr (optional_v<U>) {
+    if (wire.has_value()) {
+      typename U::value_type item{};
+      assign_pb_wire_value(item, *wire);
+      value = std::move(item);
+    }
+    else {
+      value.reset();
+    }
+  }
+  else if constexpr (is_sequence_container<U>::value) {
+    value.clear();
+    for (auto& item : wire) {
+      typename U::value_type converted{};
+      assign_pb_wire_value(converted, item);
+      value.push_back(std::move(converted));
+    }
+  }
+  else if constexpr (is_pb_type_v<W>) {
+    value = wire.val;
+  }
+  else {
+    value = static_cast<U>(wire);
+  }
+}
+
+template <typename Wire, size_t key_size, bool omit_default_val = true,
+          typename Type, typename Arr>
+IGUANA_INLINE size_t pb_schema_key_value_size(Type&& t, Arr& size_arr);
+
 template <typename Variant, typename T, size_t I>
 constexpr inline size_t get_variant_index() {
   if constexpr (I == 0) {
@@ -459,24 +561,52 @@ IGUANA_INLINE size_t pb_key_value_size(Type&& t, Arr& size_arr) {
                                    std::decay_t<decltype(tuple)>>;
           auto value = std::get<decltype(i)::value>(tuple);
           using U = typename field_type::value_type;
+          using wire_type = typename field_type::wire_value_type;
           using sub_type = typename field_type::sub_type;
           auto& val = value.value(t);
-          if constexpr (variant_v<U>) {
+          if constexpr (field_type::timestamp_schema ||
+                        field_type::duration_schema) {
+            constexpr uint32_t sub_key =
+                (value.field_no << 3) |
+                static_cast<uint32_t>(WireType::LengthDelimeted);
+            constexpr auto sub_keysize = variant_uint32_size_constexpr(sub_key);
+            len += pb_well_known_key_value_size<field_type::timestamp_schema,
+                                                sub_keysize>(val, size_arr);
+          }
+          else if constexpr (field_type::optional_schema) {
+            constexpr uint32_t sub_key =
+                (value.field_no << 3) |
+                static_cast<uint32_t>(get_wire_type<wire_type>());
+            constexpr auto sub_keysize = variant_uint32_size_constexpr(sub_key);
+            len += pb_schema_key_value_size<wire_type, sub_keysize, false>(
+                val, size_arr);
+          }
+          else if constexpr (variant_v<U>) {
             constexpr auto offset =
                 get_variant_index<U, sub_type, std::variant_size_v<U> - 1>();
-            if constexpr (offset == 0) {
-              len += pb_oneof_size<value.field_no>(val, size_arr);
+            if (val.index() == offset) {
+              if constexpr (!std::is_same_v<sub_type, std::monostate>) {
+                constexpr uint32_t sub_key =
+                    (value.field_no << 3) |
+                    static_cast<uint32_t>(get_wire_type<sub_type>());
+                constexpr auto sub_keysize =
+                    variant_uint32_size_constexpr(sub_key);
+                len += pb_key_value_size<sub_keysize, false>(
+                    std::get<offset>(val), size_arr);
+              }
             }
           }
           else {
             constexpr uint32_t sub_key =
                 (value.field_no << 3) |
-                static_cast<uint32_t>(get_wire_type<U>());
+                static_cast<uint32_t>(get_wire_type<wire_type>());
             constexpr auto sub_keysize = variant_uint32_size_constexpr(sub_key);
-            len += pb_key_value_size<sub_keysize>(val, size_arr);
+            len +=
+                pb_schema_key_value_size<wire_type, sub_keysize>(val, size_arr);
           }
         },
         std::make_index_sequence<SIZE>{});
+    len += pb_unknown_fields_size(t);
     if constexpr (inherits_from_base_v<T>) {
       t.cache_size = len;
     }
@@ -541,6 +671,49 @@ IGUANA_INLINE size_t pb_key_value_size(Type&& t, Arr& size_arr) {
   }
 }
 
+template <typename Wire, size_t key_size, bool omit_default_val, typename Type,
+          typename Arr>
+IGUANA_INLINE size_t pb_schema_key_value_size(Type&& t, Arr& size_arr) {
+  using T = ylt::reflection::remove_cvref_t<Type>;
+  using W = ylt::reflection::remove_cvref_t<Wire>;
+  if constexpr (std::is_same_v<T, W>) {
+    return pb_key_value_size<key_size, omit_default_val>(std::forward<Type>(t),
+                                                         size_arr);
+  }
+  else if constexpr (optional_v<T>) {
+    if (!t.has_value()) {
+      return 0;
+    }
+    return pb_schema_key_value_size<typename W::value_type, key_size,
+                                    omit_default_val>(*t, size_arr);
+  }
+  else if constexpr (is_sequence_container<T>::value) {
+    using wire_item_type = typename W::value_type;
+    size_t len = 0;
+    if constexpr (is_lenprefix_v<wire_item_type>) {
+      for (auto& item : t) {
+        len += pb_schema_key_value_size<wire_item_type, key_size, false>(
+            item, size_arr);
+      }
+      return len;
+    }
+    else {
+      for (auto& item : t) {
+        auto wire_item = make_pb_wire_scalar<wire_item_type>(item);
+        len += str_numeric_size<0, false>(wire_item);
+      }
+      if (len == 0) {
+        return 0;
+      }
+      return key_size + variant_uint32_size(static_cast<uint32_t>(len)) + len;
+    }
+  }
+  else {
+    auto wire_value = make_pb_wire_scalar<W>(t);
+    return pb_key_value_size<key_size, omit_default_val>(wire_value, size_arr);
+  }
+}
+
 // return the payload size
 template <bool skip_next = true, typename Type>
 IGUANA_INLINE size_t pb_value_size(Type&& t, uint32_t*& sz_ptr) {
@@ -586,53 +759,44 @@ IGUANA_INLINE size_t pb_value_size(Type&& t, uint32_t*& sz_ptr) {
   }
 }
 
-// YLT_REFL_PB implementation
-template <typename>
-struct pb_field_no;
-
-template <typename Owner, typename Value, size_t FieldNo, typename ElementType>
-struct pb_field_no<pb_field_t<Owner, Value, FieldNo, ElementType>> {
-  static constexpr size_t value = FieldNo;
-};
-
 template <typename T, size_t... I>
 inline auto build_pb_members_impl(
     const std::array<size_t, sizeof...(I)>& offset_arr,
     std::index_sequence<I...>) {
-  using Tuple = decltype(ylt::reflection::object_to_tuple(std::declval<T>()));
   constexpr auto names = ylt::reflection::get_member_names<T>();
   constexpr auto numbers = get_pb_field_numbers((T*)nullptr);
+#ifdef YLT_USE_CXX26_REFLECTION
+  static constexpr auto members =
+      ylt::reflection::reflect26::data_members_array<T>();
+  return std::tuple_cat(
+      build_pb_fields_impl<T, numbers[I] - 1,
+                           ylt::reflection::reflect26::meta_type_t<members[I]>>(
+          offset_arr[I], names[I])...);
+#else
+  using Tuple = decltype(ylt::reflection::object_to_tuple(std::declval<T>()));
   return std::tuple_cat(
       build_pb_fields_impl<T, numbers[I] - 1, std::tuple_element_t<I, Tuple>>(
           offset_arr[I], names[I])...);
-}
-
-template <typename Tuple, size_t... I>
-constexpr bool has_duplicate_field_nos(std::index_sequence<I...>) {
-  constexpr size_t nos[] = {
-      pb_field_no<std::tuple_element_t<I, Tuple>>::value...};
-  constexpr size_t N = sizeof...(I);
-  for (size_t i = 0; i < N; ++i)
-    for (size_t j = i + 1; j < N; ++j)
-      if (nos[i] == nos[j])
-        return true;
-  return false;
+#endif
 }
 
 template <typename T>
 inline auto build_pb_members() {
+#ifdef YLT_USE_CXX26_REFLECTION
+  constexpr size_t N = ylt::reflection::members_count_v<T>;
+  static const auto& offset_arr =
+      ylt::reflection::internal::get_member_offset_arr<T>();
+#else
   using Tuple = decltype(ylt::reflection::object_to_tuple(std::declval<T>()));
   constexpr size_t N = std::tuple_size_v<Tuple>;
   static auto& offset_arr = ylt::reflection::internal::get_member_offset_arr(
       ylt::reflection::internal::wrapper<T>::value);
+#endif
 
   auto res =
       build_pb_members_impl<T>(offset_arr, std::make_index_sequence<N>{});
   using ResultTuple = decltype(res);
-  constexpr size_t M = std::tuple_size_v<ResultTuple>;
-  static_assert(
-      !has_duplicate_field_nos<ResultTuple>(std::make_index_sequence<M>{}),
-      "YLT_REFL_PB: duplicate proto field numbers detected");
+  validate_pb_members_tuple<ResultTuple>();
   return res;
 }
 
@@ -659,4 +823,4 @@ inline auto build_pb_members() {
 #define IGUANA_PB_YLT_REFL_FWD(STRUCT, ...) YLT_REFL(STRUCT, __VA_ARGS__)
 
 }  // namespace detail
-}  // namespace iguana
\ No newline at end of file
+}  // namespace iguana
diff --git a/iguana/pb_writer.hpp b/iguana/pb_writer.hpp
--- a/iguana/pb_writer.hpp
+++ b/iguana/pb_writer.hpp
@@ -28,6 +28,77 @@ template <uint32_t key, bool omit_default_val = true, typename Type,
           typename Writer>
 IGUANA_INLINE void to_pb_impl(Type&& t, uint32_t*& sz_ptr, Writer& writer);
 
+template <uint32_t key, bool omit_default_val, typename T, typename Writer>
+IGUANA_INLINE void encode_numeric_field(T t, Writer& writer);
+
+template <bool TimestampSchema, uint32_t key, bool omit_default_val = true,
+          typename Type, typename Writer>
+IGUANA_INLINE void to_pb_well_known_impl(Type&& t, uint32_t*& sz_ptr,
+                                         Writer& writer) {
+  using T = std::remove_const_t<std::remove_reference_t<Type>>;
+  if constexpr (optional_v<T>) {
+    if (!t.has_value()) {
+      return;
+    }
+    to_pb_well_known_impl<TimestampSchema, key, omit_default_val>(*t, sz_ptr,
+                                                                  writer);
+  }
+  else if constexpr (is_sequence_container<T>::value) {
+    for (auto& item : t) {
+      to_pb_well_known_impl<TimestampSchema, key, false>(item, sz_ptr, writer);
+    }
+  }
+  else {
+    auto wire_value = make_pb_well_known_value<TimestampSchema>(t);
+    to_pb_impl<key, omit_default_val>(wire_value, sz_ptr, writer);
+  }
+}
+
+template <typename Wire, uint32_t key, bool omit_default_val = true,
+          typename Type, typename Writer>
+IGUANA_INLINE void to_pb_schema_impl(Type&& t, uint32_t*& sz_ptr,
+                                     Writer& writer) {
+  using T = ylt::reflection::remove_cvref_t<Type>;
+  using W = ylt::reflection::remove_cvref_t<Wire>;
+  if constexpr (std::is_same_v<T, W>) {
+    to_pb_impl<key, omit_default_val>(std::forward<Type>(t), sz_ptr, writer);
+  }
+  else if constexpr (optional_v<T>) {
+    if (!t.has_value()) {
+      return;
+    }
+    to_pb_schema_impl<typename W::value_type, key, omit_default_val>(*t, sz_ptr,
+                                                                     writer);
+  }
+  else if constexpr (is_sequence_container<T>::value) {
+    using wire_item_type = typename W::value_type;
+    if constexpr (is_lenprefix_v<wire_item_type>) {
+      for (auto& item : t) {
+        to_pb_schema_impl<wire_item_type, key, false>(item, sz_ptr, writer);
+      }
+    }
+    else {
+      if (t.empty())
+        IGUANA_UNLIKELY { return; }
+      serialize_varint_u32<key>(writer);
+      size_t len = 0;
+      for (auto& item : t) {
+        auto wire_item = make_pb_wire_scalar<wire_item_type>(item);
+        len += str_numeric_size<0, false>(wire_item);
+      }
+      serialize_varint(len, writer);
+      for (auto& item : t) {
+        auto wire_item = make_pb_wire_scalar<wire_item_type>(item);
+        encode_numeric_field<0, false>(wire_item, writer);
+      }
+    }
+  }
+  else {
+    auto wire_value = make_pb_wire_scalar<W>(t);
+    to_pb_impl<key, omit_default_val>(wire_value, sz_ptr, writer);
+  }
+}
+
 template <uint32_t key, typename V, typename Writer>
 IGUANA_INLINE void encode_pair_value(V&& val, size_t size, uint32_t*& sz_ptr,
                                      Writer& writer) {
@@ -120,22 +191,44 @@ IGUANA_INLINE void to_pb_impl(Type&& t, uint32_t*& sz_ptr, Writer& writer) {
           auto& val = value.value(t);
 
           using U = typename field_type::value_type;
+          using wire_type = typename field_type::wire_value_type;
           using sub_type = typename field_type::sub_type;
-          if constexpr (variant_v<U>) {
+          if constexpr (field_type::timestamp_schema ||
+                        field_type::duration_schema) {
+            constexpr uint32_t sub_key =
+                (value.field_no << 3) |
+                static_cast<uint32_t>(WireType::LengthDelimeted);
+            to_pb_well_known_impl<field_type::timestamp_schema, sub_key>(
+                val, sz_ptr, writer);
+          }
+          else if constexpr (field_type::optional_schema) {
+            constexpr uint32_t sub_key =
+                (value.field_no << 3) |
+                static_cast<uint32_t>(get_wire_type<wire_type>());
+            to_pb_schema_impl<wire_type, sub_key, false>(val, sz_ptr, writer);
+          }
+          else if constexpr (variant_v<U>) {
             constexpr auto offset =
                 get_variant_index<U, sub_type, std::variant_size_v<U> - 1>();
-            if constexpr (offset == 0) {
-              to_pb_oneof<value.field_no>(val, sz_ptr, writer);
+            if (val.index() == offset) {
+              if constexpr (!std::is_same_v<sub_type, std::monostate>) {
+                constexpr uint32_t sub_key =
+                    (value.field_no << 3) |
+                    static_cast<uint32_t>(get_wire_type<sub_type>());
+                to_pb_impl<sub_key, false>(std::get<offset>(val), sz_ptr,
+                                           writer);
+              }
             }
           }
           else {
             constexpr uint32_t sub_key =
                 (value.field_no << 3) |
-                static_cast<uint32_t>(get_wire_type<U>());
-            to_pb_impl<sub_key>(val, sz_ptr, writer);
+                static_cast<uint32_t>(get_wire_type<wire_type>());
+            to_pb_schema_impl<wire_type, sub_key>(val, sz_ptr, writer);
           }
         },
         std::make_index_sequence<SIZE>{});
+    write_pb_unknown_fields(t, writer);
   }
   else if constexpr (is_sequence_container<T>::value) {
     // TODO support std::array
@@ -329,8 +422,66 @@ IGUANA_INLINE void to_proto_impl(
           auto value = std::get<decltype(i)::value>(tuple);
 
           using U = typename field_type::value_type;
+          using WireU = typename field_type::wire_value_type;
           using sub_type = typename field_type::sub_type;
-          if constexpr (ylt_refletable_v<U>) {
+          if constexpr (field_type::bytes_schema) {
+            if constexpr (is_sequence_container<U>::value) {
+              build_proto_field(
+                  out, "repeated bytes",
+                  {value.field_name.data(), value.field_name.size()},
+                  value.field_no);
+            }
+            else if constexpr (optional_v<U>) {
+              out.append("  optional");
+              build_proto_field(
+                  out, "bytes",
+                  {value.field_name.data(), value.field_name.size()},
+                  value.field_no);
+            }
+            else {
+              build_proto_field(
+                  out, "bytes ",
+                  {value.field_name.data(), value.field_name.size()},
+                  value.field_no);
+            }
+          }
+          else if constexpr (field_type::timestamp_schema) {
+            if constexpr (is_sequence_container<U>::value) {
+              build_proto_field(
+                  out, "repeated google.protobuf.Timestamp",
+                  {value.field_name.data(), value.field_name.size()},
+                  value.field_no);
+            }
+            else {
+              build_proto_field(
+                  out, "google.protobuf.Timestamp",
+                  {value.field_name.data(), value.field_name.size()},
+                  value.field_no);
+            }
+          }
+          else if constexpr (field_type::duration_schema) {
+            if constexpr (is_sequence_container<U>::value) {
+              build_proto_field(
+                  out, "repeated google.protobuf.Duration",
+                  {value.field_name.data(), value.field_name.size()},
+                  value.field_no);
+            }
+            else {
+              build_proto_field(
+                  out, "google.protobuf.Duration",
+                  {value.field_name.data(), value.field_name.size()},
+                  value.field_no);
+            }
+          }
+          else if constexpr (field_type::optional_schema) {
+            static_assert(optional_v<U>,
+                          "pb_optional member must be std::optional<T>");
+            out.append("  optional");
+            to_proto_impl<typename WireU::value_type>(
+                out, map, {value.field_name.data(), value.field_name.size()},
+                value.field_no);
+          }
+          else if constexpr (ylt_refletable_v<U>) {
             constexpr auto str_type = get_type_string<U>();
             build_proto_field(
                 out, str_type,
@@ -341,35 +492,38 @@ IGUANA_INLINE void to_proto_impl(
           }
           else if constexpr (variant_v<U>) {
             constexpr size_t var_size = std::variant_size_v<U>;
+            constexpr size_t first_case = pb_variant_first_case_index<U>();
 
             constexpr auto offset =
                 get_variant_index<U, sub_type, var_size - 1>();
 
-            if (offset == 0) {
+            if (offset == first_case) {
               out.append("  oneof ");
               out.append(value.field_name.data(), value.field_name.size())
                   .append(" {\n");
             }
 
-            constexpr auto str_type = get_type_string<sub_type>();
-            std::string field_name = " one_of_";
-            field_name.append(str_type);
+            if constexpr (!std::is_same_v<sub_type, std::monostate>) {
+              constexpr auto str_type = get_type_string<sub_type>();
+              std::string field_name = " one_of_";
+              field_name.append(str_type);
 
-            out.append("  ");
-            build_proto_field(out, str_type, field_name, value.field_no);
+              out.append("  ");
+              build_proto_field(out, str_type, field_name, value.field_no);
 
-            if constexpr (ylt_refletable_v<sub_type>) {
-              build_sub_proto<sub_type>(map, str_type, sub_str);
+              if constexpr (ylt_refletable_v<sub_type>) {
+                build_sub_proto<sub_type>(map, str_type, sub_str);
+              }
             }
 
             if (offset == var_size - 1) {
               out.append("  }\n");
             }
           }
           else {
-            to_proto_impl<U>(out, map,
-                             {value.field_name.data(), value.field_name.size()},
-                             value.field_no);
+            to_proto_impl<WireU>(
+                out, map, {value.field_name.data(), value.field_name.size()},
+                value.field_no);
           }
         },
         std::make_index_sequence<SIZE>{});
@@ -464,6 +618,130 @@ IGUANA_INLINE void build_sub_proto(Map& map, std::string_view str_type,
     map.emplace(str_type, std::move(sub_str));
   }
 }
+
+template <typename T>
+constexpr bool proto_needs_timestamp_import();
+
+template <typename T>
+constexpr bool proto_needs_duration_import();
+
+template <typename T>
+constexpr bool proto_value_needs_timestamp_import();
+
+template <typename T>
+constexpr bool proto_value_needs_duration_import();
+
+template <typename Variant, size_t... I>
+constexpr bool proto_variant_needs_timestamp_import(std::index_sequence<I...>) {
+  return (proto_value_needs_timestamp_import<
+              std::variant_alternative_t<I, Variant>>() ||
+          ...);
+}
+
+template <typename Variant, size_t... I>
+constexpr bool proto_variant_needs_duration_import(std::index_sequence<I...>) {
+  return (proto_value_needs_duration_import<
+              std::variant_alternative_t<I, Variant>>() ||
+          ...);
+}
+
+template <typename T>
+constexpr bool proto_value_needs_timestamp_import() {
+  using U = std::remove_cvref_t<T>;
+  if constexpr (std::is_same_v<U, std::monostate> ||
+                pb_well_known_chrono_v<U>) {
+    return false;
+  }
+  else if constexpr (optional_v<U>) {
+    return proto_value_needs_timestamp_import<typename U::value_type>();
+  }
+  else if constexpr (is_sequence_container<U>::value) {
+    return proto_value_needs_timestamp_import<typename U::value_type>();
+  }
+  else if constexpr (is_map_container<U>::value) {
+    return proto_value_needs_timestamp_import<typename U::mapped_type>();
+  }
+  else if constexpr (variant_v<U>) {
+    return proto_variant_needs_timestamp_import<U>(
+        std::make_index_sequence<std::variant_size_v<U>>{});
+  }
+  else if constexpr (ylt_refletable_v<U> || is_custom_reflection_v<U>) {
+    return proto_needs_timestamp_import<U>();
+  }
+  else {
+    return false;
+  }
+}
+
+template <typename T>
+constexpr bool proto_value_needs_duration_import() {
+  using U = std::remove_cvref_t<T>;
+  if constexpr (std::is_same_v<U, std::monostate> ||
+                pb_well_known_chrono_v<U>) {
+    return false;
+  }
+  else if constexpr (optional_v<U>) {
+    return proto_value_needs_duration_import<typename U::value_type>();
+  }
+  else if constexpr (is_sequence_container<U>::value) {
+    return proto_value_needs_duration_import<typename U::value_type>();
+  }
+  else if constexpr (is_map_container<U>::value) {
+    return proto_value_needs_duration_import<typename U::mapped_type>();
+  }
+  else if constexpr (variant_v<U>) {
+    return proto_variant_needs_duration_import<U>(
+        std::make_index_sequence<std::variant_size_v<U>>{});
+  }
+  else if constexpr (ylt_refletable_v<U> || is_custom_reflection_v<U>) {
+    return proto_needs_duration_import<U>();
+  }
+  else {
+    return false;
+  }
+}
+
+template <typename Tuple, size_t... I>
+constexpr bool proto_tuple_needs_timestamp_import(std::index_sequence<I...>) {
+  return ((std::tuple_element_t<I, Tuple>::timestamp_schema ||
+           proto_value_needs_timestamp_import<
+               typename std::tuple_element_t<I, Tuple>::value_type>()) ||
+          ...);
+}
+
+template <typename Tuple, size_t... I>
+constexpr bool proto_tuple_needs_duration_import(std::index_sequence<I...>) {
+  return ((std::tuple_element_t<I, Tuple>::duration_schema ||
+           proto_value_needs_duration_import<
+               typename std::tuple_element_t<I, Tuple>::value_type>()) ||
+          ...);
+}
+
+template <typename T>
+constexpr bool proto_needs_timestamp_import() {
+  if constexpr (ylt_refletable_v<T> || is_custom_reflection_v<T>) {
+    using Tuple =
+        std::decay_t<decltype(get_pb_members_tuple(std::declval<T&>()))>;
+    return proto_tuple_needs_timestamp_import<Tuple>(
+        std::make_index_sequence<std::tuple_size_v<Tuple>>{});
+  }
+  else {
+    return false;
+  }
+}
+
+template <typename T>
+constexpr bool proto_needs_duration_import() {
+  if constexpr (ylt_refletable_v<T> || is_custom_reflection_v<T>) {
+    using Tuple =
+        std::decay_t<decltype(get_pb_members_tuple(std::declval<T&>()))>;
+    return proto_tuple_needs_duration_import<Tuple>(
+        std::make_index_sequence<std::tuple_size_v<Tuple>>{});
+  }
+  else {
+    return false;
+  }
+}
 #endif
 }  // namespace detail
 
@@ -496,6 +774,12 @@ IGUANA_INLINE void to_proto(Stream& out, std::string_view ns = "") {
   if (gen_header) {
     constexpr std::string_view crlf = "\r\n\r\n";
     out.append(R"(syntax = "proto3";)").append(crlf);
+    if constexpr (detail::proto_needs_timestamp_import<T>()) {
+      out.append(R"(import "google/protobuf/timestamp.proto";)").append(crlf);
+    }
+    if constexpr (detail::proto_needs_duration_import<T>()) {
+      out.append(R"(import "google/protobuf/duration.proto";)").append(crlf);
+    }
     if (!ns.empty()) {
       out.append("package ").append(ns).append(";").append(crlf);
     }
diff --git a/iguana/util.hpp b/iguana/util.hpp
--- a/iguana/util.hpp
+++ b/iguana/util.hpp
@@ -164,12 +164,24 @@ inline constexpr auto for_each_tuple(F&& f, T&& tup) {
       std::forward<T>(tup));
 }
 
+template <class T>
+constexpr inline bool reflect26_excluded_v = false;
+
 template <class T>
 constexpr inline bool ylt_refletable_v =
-    (ylt::reflection::is_ylt_refl_v<T> ||
-     std::is_aggregate_v<
-         ylt::reflection::remove_cvref_t<T>>)&&!fixed_array_v<T> &&
+#ifdef YLT_USE_CXX26_REFLECTION
+    (std::is_class_v<ylt::reflection::remove_cvref_t<T>> ||
+     std::is_aggregate_v<ylt::reflection::remove_cvref_t<T>>) &&
+    !string_container_v<T> && !container_v<T> && !fixed_array_v<T> &&
+    !tuple_v<T> && !optional_v<T> && !variant_v<T> && !smart_ptr_v<T> &&
+    !reflect26_excluded_v<ylt::reflection::remove_cvref_t<T>> &&
     !ylt::reflection::is_custom_refl_v<T> && !is_pb_type_v<T>;
+#else
+    (ylt::reflection::is_ylt_refl_v<T> ||
+     std::is_aggregate_v<ylt::reflection::remove_cvref_t<T>>) &&
+    !fixed_array_v<T> && !ylt::reflection::is_custom_refl_v<T> &&
+    !is_pb_type_v<T>;
+#endif
 
 template <class T>
 constexpr inline bool non_ylt_refletable_v = !ylt_refletable_v<T>;
diff --git a/iguana/xml_reader.hpp b/iguana/xml_reader.hpp
--- a/iguana/xml_reader.hpp
+++ b/iguana/xml_reader.hpp
@@ -1,9 +1,13 @@
 #pragma once
 #include <charconv>
+#include <vector>
 
 #include "detail/charconv.h"
 #include "detail/utf.hpp"
 #include "xml_util.hpp"
+#ifdef YLT_USE_CXX26_REFLECTION
+#include "ylt/reflection/reflect26_dispatch.hpp"
+#endif
 
 namespace iguana {
 namespace detail {
@@ -378,19 +382,42 @@ IGUANA_INLINE void skip_till_first_key(It &&it, It &&end) {
   }
 }
 
+IGUANA_INLINE bool contains_xml_key(const std::vector<std::string_view> &keys,
+                                    std::string_view key) {
+  for (auto item : keys) {
+    if (item == key) {
+      return true;
+    }
+  }
+  return false;
+}
+
 template <typename T>
-IGUANA_INLINE void check_required(std::string_view key_set) {
+IGUANA_INLINE void check_required(
+    const std::vector<std::string_view> &parsed_keys) {
   if constexpr (iguana::has_iguana_required_arr_v<T>) {
     constexpr auto required_arr =
         iguana::iguana_required_struct<T>::requied_arr();
     for (auto &item : required_arr) {
-      if (key_set.find(item) == std::string_view::npos) {
+      if (!contains_xml_key(parsed_keys, item)) {
+        std::string err = "required filed ";
+        err.append(item).append(" not found!");
+        throw std::invalid_argument(err);
+      }
+    }
+  }
+#ifdef YLT_USE_CXX26_REFLECTION
+  if constexpr (iguana::detail::xml_required_count_26<T>() > 0) {
+    constexpr auto required_arr = iguana::detail::xml_required_names_26<T>();
+    for (auto &item : required_arr) {
+      if (!contains_xml_key(parsed_keys, item)) {
         std::string err = "required filed ";
         err.append(item).append(" not found!");
         throw std::invalid_argument(err);
       }
     }
   }
+#endif
 }
 
 template <typename T, typename It, std::enable_if_t<ylt_refletable_v<T>, int>>
@@ -409,12 +436,11 @@ IGUANA_INLINE void xml_parse_item(T &value, It &&it, It &&end,
   std::string_view key =
       std::string_view{&*start, static_cast<size_t>(std::distance(start, it))};
 
-  [[maybe_unused]] std::string key_set;
+  [[maybe_unused]] std::vector<std::string_view> parsed_keys;
   bool parse_done = false;
   // sequential parse
   ylt::reflection::for_each(value, [&](auto &field, auto st_key, auto index) {
 #if defined(_MSC_VER) && _MSVC_LANG < 202002L
-    // seems MVSC can't pass a constexpr value to lambda
     constexpr auto cdata_idx = get_type_index<is_cdata_t, U>();
 #endif
     using item_type = std::remove_reference_t<decltype(field)>;
@@ -425,8 +451,8 @@ IGUANA_INLINE void xml_parse_item(T &value, It &&it, It &&end,
       IGUANA_UNLIKELY { return; }
     if constexpr (!cdata_v<item_type>) {
       xml_parse_item(field, it, end, key);
-      if constexpr (iguana::has_iguana_required_arr_v<U>) {
-        key_set.append(key).append(", ");
+      if constexpr (iguana::has_xml_required_fields_v<U>) {
+        parsed_keys.push_back(key);
       }
     }
     if (skip_till_close_tag<cdata_idx>(value, it, end))
@@ -442,11 +468,30 @@ IGUANA_INLINE void xml_parse_item(T &value, It &&it, It &&end,
   });
   if (parse_done)
     IGUANA_UNLIKELY {
-      check_required<U>(key_set);
+      check_required<U>(parsed_keys);
       return;
     }
   // map parse
   while (true) {
+#ifdef YLT_USE_CXX26_REFLECTION
+    bool found = ylt::reflection::reflect26::dispatch_by_name(
+        value, key, [&](auto &field) IGUANA__INLINE_LAMBDA {
+          if constexpr (!cdata_v<std::remove_reference_t<decltype(field)>>) {
+            xml_parse_item(field, it, end, key);
+            if constexpr (iguana::has_xml_required_fields_v<U>) {
+              parsed_keys.push_back(key);
+            }
+          }
+        });
+    if (!found)
+      IGUANA_UNLIKELY {
+#ifdef THROW_UNKNOWN_KEY
+        throw std::runtime_error("Unknown key: " + std::string(key));
+#else
+        skip_object_value(it, end, key);
+#endif
+      }
+#else
     static auto frozen_map = ylt::reflection::get_variant_map<U>();
     const auto &member_it = frozen_map.find(key);
     if (member_it != frozen_map.end())
@@ -458,8 +503,8 @@ IGUANA_INLINE void xml_parse_item(T &value, It &&it, It &&end,
                 auto member_ptr =
                     (value_type *)((char *)(&value) + offset.value);
                 xml_parse_item(*member_ptr, it, end, key);
-                if constexpr (iguana::has_iguana_required_arr_v<U>) {
-                  key_set.append(key).append(", ");
+                if constexpr (iguana::has_xml_required_fields_v<U>) {
+                  parsed_keys.push_back(key);
                 }
               }
             },
@@ -473,9 +518,10 @@ IGUANA_INLINE void xml_parse_item(T &value, It &&it, It &&end,
         skip_object_value(it, end, key);
 #endif
       }
+#endif
     if (skip_till_close_tag<cdata_idx>(value, it, end)) {
       match_close_tag(it, end, name);
-      check_required<U>(key_set);
+      check_required<U>(parsed_keys);
       return;
     }
     start = it;
@@ -528,4 +574,4 @@ IGUANA_INLINE void from_xml_adl(iguana_adl_t *p, T &t,
   iguana::from_xml(t, pb_str);
 }
 
-}  // namespace iguana
\ No newline at end of file
+}  // namespace iguana
diff --git a/iguana/xml_util.hpp b/iguana/xml_util.hpp
--- a/iguana/xml_util.hpp
+++ b/iguana/xml_util.hpp
@@ -2,8 +2,15 @@
 #include "common.hpp"
 #include "detail/pb_type.hpp"
 #include "util.hpp"
+#ifdef YLT_USE_CXX26_REFLECTION
+#include <meta>
+
+#include "ylt/reflection/reflect26_core.hpp"
+#endif
 
 namespace iguana {
+struct xml_required {};
+
 template <typename T>
 struct iguana_required_struct;
 #define REQUIRED_IMPL(STRUCT_NAME, N, ...)             \
@@ -30,6 +37,62 @@ struct has_iguana_required_arr<
 template <class T>
 constexpr bool has_iguana_required_arr_v = has_iguana_required_arr<T>::value;
 
+#ifdef YLT_USE_CXX26_REFLECTION
+namespace detail {
+template <typename T>
+struct is_xml_required_annotation : std::false_type {};
+
+template <>
+struct is_xml_required_annotation<iguana::xml_required> : std::true_type {};
+
+template <std::meta::info Member>
+consteval bool xml_required_26() {
+  return ylt::reflection::reflect26::has_annotation_26<
+      Member, is_xml_required_annotation>();
+}
+
+template <typename T>
+consteval size_t xml_required_count_26() {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static constexpr auto members =
+      ylt::reflection::reflect26::data_members_array<U>();
+  size_t count = 0;
+  template for (constexpr auto member : members) {
+    if constexpr (xml_required_26<member>()) {
+      ++count;
+    }
+  }
+  return count;
+}
+
+template <typename T>
+consteval auto xml_required_names_26() {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static constexpr auto members =
+      ylt::reflection::reflect26::data_members_array<U>();
+  constexpr auto member_names = ylt::reflection::get_member_names<U>();
+  std::array<std::string_view, xml_required_count_26<U>()> names{};
+  size_t index = 0;
+  size_t member_index = 0;
+  template for (constexpr auto member : members) {
+    if constexpr (xml_required_26<member>()) {
+      names[index++] = member_names[member_index];
+    }
+    ++member_index;
+  }
+  return names;
+}
+}  // namespace detail
+#endif
+
+template <class T>
+constexpr bool has_xml_required_fields_v =
+    has_iguana_required_arr_v<T>
+#ifdef YLT_USE_CXX26_REFLECTION
+    || detail::xml_required_count_26<T>() > 0
+#endif
+    ;
+
 template <typename T,
           typename map_type = std::unordered_map<std::string, std::string>>
 class xml_attr_t {
@@ -76,6 +139,12 @@ struct is_cdata_t : std::false_type {};
 template <typename T>
 struct is_cdata_t<xml_cdata_t<T>> : std::true_type {};
 
+template <typename T, typename map_type>
+constexpr inline bool reflect26_excluded_v<xml_attr_t<T, map_type>> = true;
+
+template <typename T>
+constexpr inline bool reflect26_excluded_v<xml_cdata_t<T>> = true;
+
 template <std::size_t index, template <typename...> typename Condition,
           typename Tuple>
 constexpr int element_index_helper() {
@@ -94,8 +163,13 @@ constexpr int element_index_helper() {
 
 template <template <typename...> typename Condition, typename T>
 constexpr int tuple_element_index() {
+#ifdef YLT_USE_CXX26_REFLECTION
+  return static_cast<int>(
+      ylt::reflection::reflect26::member_index_if<Condition, T>());
+#else
   using Tuple = decltype(ylt::reflection::object_to_tuple(std::declval<T>()));
   return element_index_helper<0, Condition, Tuple>();
+#endif
 }
 
 template <template <typename...> typename Condition, typename T>
diff --git a/iguana/yaml_reader.hpp b/iguana/yaml_reader.hpp
--- a/iguana/yaml_reader.hpp
+++ b/iguana/yaml_reader.hpp
@@ -5,6 +5,9 @@
 #include "detail/charconv.h"
 #include "detail/utf.hpp"
 #include "yaml_util.hpp"
+#ifdef YLT_USE_CXX26_REFLECTION
+#include "ylt/reflection/reflect26_dispatch.hpp"
+#endif
 
 namespace iguana {
 
@@ -559,6 +562,37 @@ IGUANA_INLINE void skip_object_value(It &&it, It &&end, size_t min_spaces) {
 
 }  // namespace detail
 
+#ifdef YLT_USE_CXX26_REFLECTION
+template <typename T, typename It, std::enable_if_t<ylt_refletable_v<T>, int>>
+IGUANA_INLINE void from_yaml(T &value, It &&it, It &&end, size_t min_spaces) {
+  auto spaces = skip_space_and_lines(it, end, min_spaces);
+  while (it != end) {
+    auto start = it;
+    auto keyend = yaml_skip_till<':'>(it, end);
+    std::string_view key = std::string_view{
+        &*start, static_cast<size_t>(std::distance(start, keyend))};
+
+    bool found = ylt::reflection::reflect26::dispatch_by_name(
+        value, key, [&](auto &field) IGUANA__INLINE_LAMBDA {
+          detail::yaml_parse_item(field, it, end, spaces + 1);
+        });
+    if (!found)
+      IGUANA_UNLIKELY {
+#ifdef THROW_UNKNOWN_KEY
+        throw std::runtime_error("Unknown key: " + std::string(key));
+#else
+        detail::skip_object_value(it, end, spaces + 1);
+#endif
+      }
+    auto subspaces = skip_space_and_lines<false>(it, end, min_spaces);
+    if (subspaces < min_spaces)
+      IGUANA_UNLIKELY {
+        it -= subspaces + 1;
+        return;
+      }
+  }
+}
+#else
 template <typename T, typename It, std::enable_if_t<ylt_refletable_v<T>, int>>
 IGUANA_INLINE void from_yaml(T &value, It &&it, It &&end, size_t min_spaces) {
   auto spaces = skip_space_and_lines(it, end, min_spaces);
@@ -599,6 +633,7 @@ IGUANA_INLINE void from_yaml(T &value, It &&it, It &&end, size_t min_spaces) {
       }
   }
 }
+#endif  // !YLT_USE_CXX26_REFLECTION
 
 template <typename T, typename It,
           std::enable_if_t<non_ylt_refletable_v<T>, int> = 0>
diff --git a/iguana/ylt/reflection/member_count.hpp b/iguana/ylt/reflection/member_count.hpp
--- a/iguana/ylt/reflection/member_count.hpp
+++ b/iguana/ylt/reflection/member_count.hpp
@@ -11,7 +11,11 @@
 #include "iguana/ylt/util/expected.hpp"
 #endif
 
+#include "reflect26_compat.hpp"
 #include "user_reflect_macro.hpp"
+#ifdef YLT_USE_CXX26_REFLECTION
+#include "reflect26_core.hpp"
+#endif
 namespace struct_pack {
 template <typename T, uint64_t version>
 struct compatible;
@@ -169,6 +173,14 @@ inline constexpr std::size_t members_count_impl() {
 template <typename T>
 inline constexpr std::size_t members_count() {
   using type = remove_cvref_t<T>;
+#ifdef YLT_USE_CXX26_REFLECTION
+  if constexpr (internal::tuple_size<type>) {
+    return std::tuple_size<type>::value;
+  }
+  else {
+    return reflect26::members_count_26<type>();
+  }
+#else
   if constexpr (is_out_ylt_refl_v<type>) {
     return refl_member_count(ylt::reflection::identity<type>{});
   }
@@ -184,8 +196,9 @@ inline constexpr std::size_t members_count() {
   else {
     static_assert(!sizeof(T), "not supported type!");
   }
+#endif
 }
 
 template <typename T>
 constexpr std::size_t members_count_v = members_count<T>();
-}  // namespace ylt::reflection
\ No newline at end of file
+}  // namespace ylt::reflection
diff --git a/iguana/ylt/reflection/member_names.hpp b/iguana/ylt/reflection/member_names.hpp
--- a/iguana/ylt/reflection/member_names.hpp
+++ b/iguana/ylt/reflection/member_names.hpp
@@ -1,9 +1,15 @@
 #pragma once
+#include <array>
+#include <stdexcept>
 #include <string_view>
 #include <variant>
 
 #include "member_ptr.hpp"
+#include "reflect26_compat.hpp"
 #include "template_string.hpp"
+#ifdef YLT_USE_CXX26_REFLECTION
+#include "reflect26_core.hpp"
+#endif
 
 namespace ylt::reflection {
 
@@ -116,47 +122,75 @@ inline constexpr void init_arr_with_tuple(U& arr, std::index_sequence<Is...>) {
 template <typename T>
 inline constexpr std::array<std::string_view, members_count_v<T>>
 get_member_names() {
-  constexpr size_t Count = members_count_v<T>;
   using type = remove_cvref_t<T>;
+#ifdef YLT_USE_CXX26_REFLECTION
+  return reflect26::member_names_array<type>();
+#else
   if constexpr (is_out_ylt_refl_v<type>) {
     return refl_member_names(ylt::reflection::identity<type>{});
   }
   else if constexpr (is_inner_ylt_refl_v<type>) {
     return type::refl_member_names(ylt::reflection::identity<type>{});
   }
   else {
+    constexpr size_t Count = members_count_v<T>;
     std::array<std::string_view, Count> arr;
 #if __cplusplus >= 202002L
     constexpr auto tp = struct_to_tuple<T>();
     [&]<size_t... Is>(std::index_sequence<Is...>) mutable {
       ((arr[Is] =
             internal::get_member_name<internal::wrap(std::get<Is>(tp))>()),
        ...);
-    }
-    (std::make_index_sequence<Count>{});
+    }(std::make_index_sequence<Count>{});
 #else
     init_arr_with_tuple<T>(arr, std::make_index_sequence<Count>{});
 #endif
     return arr;
   }
+#endif
 }
 
+#ifdef YLT_USE_CXX26_REFLECTION
+template <std::size_t N>
+struct member_names_linear_map {
+  std::array<std::string_view, N> names;
+
+  constexpr std::size_t size() const noexcept { return N; }
+  constexpr auto begin() const noexcept { return names.begin(); }
+  constexpr auto end() const noexcept { return names.end(); }
+
+  static constexpr std::string_view normalized_name(std::string_view name) {
+    return reflect26::normalized_member_name(name);
+  }
+
+  constexpr std::size_t at(std::string_view name) const {
+    for (std::size_t i = 0; i < N; ++i) {
+      if (names[i] == name || normalized_name(names[i]) == name) {
+        return i;
+      }
+    }
+    throw std::out_of_range("unknown member name");
+  }
+};
+#else
 template <typename T, size_t... Is>
 inline constexpr auto get_member_names_map_impl(T& name_arr,
                                                 std::index_sequence<Is...>) {
   return frozen::unordered_map<frozen::string, size_t, sizeof...(Is)>{
       {name_arr[Is], Is}...};
 }
+#endif
 
 template <typename T>
 inline constexpr auto get_member_names_map() {
   constexpr auto name_arr = get_member_names<T>();
-#if __cplusplus >= 202002L
+#ifdef YLT_USE_CXX26_REFLECTION
+  return member_names_linear_map<name_arr.size()>{name_arr};
+#elif __cplusplus >= 202002L
   return [&]<size_t... Is>(std::index_sequence<Is...>) mutable {
     return frozen::unordered_map<frozen::string, size_t, name_arr.size()>{
         {name_arr[Is], Is}...};
-  }
-  (std::make_index_sequence<name_arr.size()>{});
+  }(std::make_index_sequence<name_arr.size()>{});
 #else
   return get_member_names_map_impl(name_arr,
                                    std::make_index_sequence<name_arr.size()>{});
@@ -173,29 +207,40 @@ inline auto get_member_offset_arr_impl(T& t, Tuple& tp,
 
 template <typename T>
 inline const auto& get_member_offset_arr(T&& t) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  [[maybe_unused]] static constexpr auto arr =
+      reflect26::member_offsets_26<remove_cvref_t<T>>();
+  return arr;
+#else
   constexpr size_t Count = members_count_v<T>;
   auto tp = ylt::reflection::object_to_tuple(std::forward<T>(t));
 
 #if __cplusplus >= 202002L
-  [[maybe_unused]] static std::array<size_t, Count> arr = {[&]<size_t... Is>(
-      std::index_sequence<Is...>) mutable {std::array<size_t, Count> arr;
-  ((arr[Is] = size_t((const char*)&std::get<Is>(tp) - (char*)(&t))), ...);
-  return arr;
-}
-(std::make_index_sequence<Count>{})
-};  // namespace internal
+  [[maybe_unused]] static std::array<size_t, Count> arr = {
+      [&]<size_t... Is>(std::index_sequence<Is...>) mutable {
+        std::array<size_t, Count> arr;
+        ((arr[Is] = size_t((const char*)&std::get<Is>(tp) - (char*)(&t))), ...);
+        return arr;
+      }(std::make_index_sequence<Count>{})};  // namespace internal
 
-return arr;
+  return arr;
 #else
   [[maybe_unused]] static std::array<size_t, Count> arr =
       get_member_offset_arr_impl(t, tp, std::make_index_sequence<Count>{});
   return arr;
 #endif
+#endif
 }  // namespace ylt::reflection
 
 template <typename T>
 inline const auto& get_member_offset_arr() {
+#ifdef YLT_USE_CXX26_REFLECTION
+  [[maybe_unused]] static constexpr auto arr =
+      reflect26::member_offsets_26<remove_cvref_t<T>>();
+  return arr;
+#else
   return get_member_offset_arr(internal::wrapper<T>::value);
+#endif
 }  // namespace ylt::reflection
 }  // namespace internal
 
@@ -204,9 +249,29 @@ inline constexpr auto tuple_to_variant(std::tuple<Args...>) {
   return std::variant<std::add_pointer_t<Args>...>{};
 }
 
+#ifdef YLT_USE_CXX26_REFLECTION
+namespace internal {
+template <typename T, typename Member>
+using copy_const_t =
+    std::conditional_t<std::is_const_v<std::remove_reference_t<T>>,
+                       std::add_const_t<Member>, Member>;
+
+template <typename T, std::size_t... Is>
+inline constexpr auto struct_variant_26(std::index_sequence<Is...>) {
+  static constexpr auto members = reflect26::data_members_array<T>();
+  return std::variant<std::add_pointer_t<
+      copy_const_t<T, reflect26::meta_type_t<members[Is]>>>...>{};
+}
+}  // namespace internal
+
+template <typename T>
+using struct_variant_t = decltype(internal::struct_variant_26<T>(
+    std::make_index_sequence<members_count_v<remove_cvref_t<T>>>{}));
+#else
 template <typename T>
 using struct_variant_t = decltype(tuple_to_variant(
     std::declval<decltype(struct_to_tuple<remove_cvref_t<T>>())>));
+#endif
 
 template <typename T>
 constexpr auto member_names_map = internal::get_member_names_map<T>();
@@ -248,15 +313,26 @@ inline constexpr auto get_alias_field_names() {
 
 template <typename T>
 constexpr std::string_view get_struct_name() {
-  if constexpr (internal::has_alias_struct_name_v<T>) {
-    return get_alias_struct_name((T*)nullptr);
-  }
-  else if constexpr (internal::has_inner_alias_struct_name_v<T>) {
-    return T::get_alias_struct_name((T*)nullptr);
+  using U = ylt::reflection::remove_cvref_t<T>;
+#ifdef YLT_USE_CXX26_REFLECTION
+  constexpr auto annotation_name = reflect26::type_name_26<U>();
+  if constexpr (!annotation_name.empty()) {
+    return annotation_name;
   }
   else {
-    return type_string<T>();
+#endif
+    if constexpr (internal::has_alias_struct_name_v<U>) {
+      return get_alias_struct_name((U*)nullptr);
+    }
+    else if constexpr (internal::has_inner_alias_struct_name_v<U>) {
+      return U::get_alias_struct_name((U*)nullptr);
+    }
+    else {
+      return type_string<U>();
+    }
+#ifdef YLT_USE_CXX26_REFLECTION
   }
+#endif
 }
 
 template <typename T>
@@ -342,8 +418,25 @@ inline constexpr void for_each_impl(Visit&& func, U& arr,
 
 template <typename T, typename Visit>
 inline constexpr void for_each(Visit&& func) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  static constexpr auto arr = get_member_names<T>();
+  [[maybe_unused]] size_t index = 0;
+  template for (constexpr auto name : arr) {
+    if constexpr (std::is_invocable_v<Visit, std::string_view, size_t>) {
+      func(name, index++);
+    }
+    else if constexpr (std::is_invocable_v<Visit, std::string_view>) {
+      func(name);
+    }
+    else {
+      static_assert(sizeof(Visit) < 0,
+                    "invalid arguments, full arguments: [std::string_view, "
+                    "size_t], at least has std::string_view and make sure keep "
+                    "the order of arguments");
+    }
+  }
+#elif __cplusplus >= 202002L
   constexpr auto arr = get_member_names<T>();
-#if __cplusplus >= 202002L
   [&]<size_t... Is>(std::index_sequence<Is...>) mutable {
     if constexpr (std::is_invocable_v<Visit, std::string_view, size_t>) {
       (func(arr[Is], Is), ...);
@@ -357,9 +450,9 @@ inline constexpr void for_each(Visit&& func) {
                     "size_t], at least has std::string_view and make sure keep "
                     "the order of arguments");
     }
-  }
-  (std::make_index_sequence<arr.size()>{});
+  }(std::make_index_sequence<arr.size()>{});
 #else
+  constexpr auto arr = get_member_names<T>();
   for_each_impl(std::forward<Visit>(func), arr,
                 std::make_index_sequence<arr.size()>{});
 #endif
diff --git a/iguana/ylt/reflection/member_ptr.hpp b/iguana/ylt/reflection/member_ptr.hpp
--- a/iguana/ylt/reflection/member_ptr.hpp
+++ b/iguana/ylt/reflection/member_ptr.hpp
@@ -1,5 +1,9 @@
 #pragma once
 #include "member_count.hpp"
+#include "reflect26_compat.hpp"
+#ifdef YLT_USE_CXX26_REFLECTION
+#include "reflect26_core.hpp"
+#endif
 
 // modified based on:
 // https://github.com/getml/reflect-cpp/blob/main/include/rfl/internal/bind_fake_object_to_tuple.hpp
@@ -84,7 +88,9 @@ inline constexpr remove_cvref_t<T>& get_fake_object() noexcept {
   }
 
 // such file is generate macro file
+#ifndef YLT_USE_CXX26_REFLECTION
 #include "internal/generate/member_macro.hpp"
+#endif
 
 template <class T>
 inline constexpr auto tuple_view(T&& t) {
@@ -101,12 +107,19 @@ inline constexpr decltype(auto) tuple_view(T&& t, Visitor&& visitor) {
 
 template <class T>
 inline constexpr auto struct_to_tuple() {
+#ifdef YLT_USE_CXX26_REFLECTION
+  return reflect26::data_members_26<remove_cvref_t<T>>();
+#else
   return internal::object_tuple_view_helper<T,
                                             members_count_v<T>>::tuple_view();
+#endif
 }
 
 template <class T>
 inline constexpr auto object_to_tuple(T&& t) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  return reflect26::data_members_26<remove_cvref_t<T>>();
+#else
   using type = remove_cvref_t<T>;
   if constexpr (is_out_ylt_refl_v<type>) {
     return refl_object_to_tuple(std::forward<T>(t));
@@ -117,10 +130,15 @@ inline constexpr auto object_to_tuple(T&& t) {
   else {
     return internal::tuple_view(std::forward<T>(t));
   }
+#endif
 }
 
 template <class T, typename Visitor, size_t Count = members_count_v<T>>
 inline constexpr decltype(auto) visit_members(T&& t, Visitor&& visitor) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  return reflect26::for_each_data_member(std::forward<T>(t),
+                                         std::forward<Visitor>(visitor));
+#else
   using type = remove_cvref_t<T>;
   if constexpr (is_out_ylt_refl_v<type>) {
     return refl_visit_members(std::forward<T>(t),
@@ -134,5 +152,6 @@ inline constexpr decltype(auto) visit_members(T&& t, Visitor&& visitor) {
     return internal::tuple_view<Count>(std::forward<T>(t),
                                        std::forward<Visitor>(visitor));
   }
+#endif
 }
 }  // namespace ylt::reflection
diff --git a/iguana/ylt/reflection/member_value.hpp b/iguana/ylt/reflection/member_value.hpp
--- a/iguana/ylt/reflection/member_value.hpp
+++ b/iguana/ylt/reflection/member_value.hpp
@@ -2,10 +2,14 @@
 #include <algorithm>
 #include <cstddef>
 #include <iterator>
+#include <memory>
+#include <stdexcept>
 #include <variant>
 
 #include "member_names.hpp"
-#include "template_string.hpp"
+#ifdef YLT_USE_CXX26_REFLECTION
+#include "reflect26_dispatch.hpp"
+#endif
 #include "template_switch.hpp"
 
 namespace ylt::reflection {
@@ -49,6 +53,7 @@ struct switch_helper {
   }
 };
 
+#ifndef YLT_USE_CXX26_REFLECTION
 inline constexpr frozen::string filter_str(const frozen::string& str) {
   if (str.size() > 3 && str[0] == '_' && str[1] == '_' && str[2] == '_') {
     auto ptr = str.data() + 3;
@@ -82,17 +87,68 @@ inline constexpr auto get_variant_map_impl(std::index_sequence<Is...>) {
                  offset_t<ylt::reflection::remove_cvref_t<
                      std::tuple_element_t<Is, Tuple>>>{offset_arr[Is]}}}...};
 }
+#endif
+
+#ifdef YLT_USE_CXX26_REFLECTION
+template <typename T, size_t... Is>
+inline auto get_variant_by_index_26(T& t, size_t index,
+                                    std::index_sequence<Is...>) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  using variant = struct_variant_t<T>;
+  static constexpr auto members = reflect26::data_members_array<U>();
+  variant member_ptr;
+  bool found = false;
+  (
+      [&] {
+        if (!found && index == Is) {
+          member_ptr.template emplace<Is>(std::addressof(t.[:members[Is]:]));
+          found = true;
+        }
+      }(),
+      ...);
+  if (!found) {
+    std::string str = "index out of range, ";
+    str.append("index: ")
+        .append(std::to_string(index))
+        .append(" is greater equal than member count ")
+        .append(std::to_string(members_count_v<U>));
+    throw std::out_of_range(str);
+  }
+  return member_ptr;
+}
+#endif
 
 }  // namespace internal
 
 template <typename T>
 inline constexpr auto get_variant_map() {
+#ifdef YLT_USE_CXX26_REFLECTION
+  static_assert(sizeof(T) < 0,
+                "get_variant_map is not available with C++26 reflection; use "
+                "reflect26::dispatch_by_name instead");
+#else
   return internal::get_variant_map_impl<T>(
       std::make_index_sequence<members_count_v<T>>{});
+#endif
 }
 
 template <typename Member, typename T>
 inline Member& get(T& t, size_t index) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  Member* member_ptr = nullptr;
+  bool found = reflect26::dispatch_by_index(t, index, [&](auto& field) {
+    internal::set_member_ptr(member_ptr, std::addressof(field));
+  });
+  if (!found) {
+    std::string str = "index out of range, ";
+    str.append("index: ")
+        .append(std::to_string(index))
+        .append(" is greater equal than member count ")
+        .append(std::to_string(members_count_v<remove_cvref_t<T>>));
+    throw std::out_of_range(str);
+  }
+  return *member_ptr;
+#else
   auto ref_tp = object_to_tuple(t);
   constexpr size_t tuple_size = std::tuple_size_v<decltype(ref_tp)>;
 
@@ -107,21 +163,43 @@ inline Member& get(T& t, size_t index) {
   Member* member_ptr = nullptr;
   template_switch<internal::switch_helper>(index, member_ptr, ref_tp);
   return *member_ptr;
+#endif
 }
 
 template <typename Member, typename T>
 inline Member& get(T& t, std::string_view name) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  Member* member_ptr = nullptr;
+  bool found = reflect26::dispatch_by_name(t, name, [&](auto& field) {
+    internal::set_member_ptr(member_ptr, std::addressof(field));
+  });
+  if (!found) {
+    throw std::out_of_range("unknown member name");
+  }
+  return *member_ptr;
+#else
   static constexpr auto map = member_names_map<T>;
   size_t index = map.at(name);  // may throw out_of_range: unknown key.
   auto ref_tp = object_to_tuple(t);
 
   Member* member_ptr = nullptr;
   template_switch<internal::switch_helper>(index, member_ptr, ref_tp);
   return *member_ptr;
+#endif
 }
 
 template <typename T>
 inline auto get(T& t, size_t index) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  using U = remove_cvref_t<T>;
+  if constexpr (members_count_v<U> == 0) {
+    throw std::out_of_range("index out of range, empty object");
+  }
+  else {
+    return internal::get_variant_by_index_26(
+        t, index, std::make_index_sequence<members_count_v<U>>{});
+  }
+#else
   auto ref_tp = object_to_tuple(t);
   constexpr size_t tuple_size = std::tuple_size_v<decltype(ref_tp)>;
   if (index >= tuple_size) {
@@ -137,23 +215,40 @@ inline auto get(T& t, size_t index) {
   variant member_ptr;
   template_switch<internal::switch_helper>(index, member_ptr, ref_tp);
   return member_ptr;
+#endif
 }
 
 template <typename T>
 inline constexpr auto get(T& t, std::string_view name) {
+#ifdef YLT_USE_CXX26_REFLECTION
   constexpr auto& map = member_names_map<T>;
   size_t index = map.at(name);  // may throw out_of_range: unknown key.
   return get(t, index);
+#else
+  constexpr auto& map = member_names_map<T>;
+  size_t index = map.at(name);  // may throw out_of_range: unknown key.
+  return get(t, index);
+#endif
 }
 
 template <size_t index, typename T>
 inline constexpr auto& get(T& t) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  using U = remove_cvref_t<T>;
+  static_assert(index < members_count_v<U>, "index out of range");
+  decltype(auto) result = [&]() -> decltype(auto) {
+    static constexpr auto members = reflect26::data_members_array<U>();
+    return (t.[:members[index]:]);
+  }();
+  return result;
+#else
   auto ref_tp = object_to_tuple(t);
 
   static_assert(index < std::tuple_size_v<decltype(ref_tp)>,
                 "index out of range");
 
   return std::get<index>(ref_tp);
+#endif
 }
 
 #if __cplusplus >= 202002L
@@ -166,6 +261,22 @@ inline constexpr auto& get(T& t) {
 
 template <typename T, typename Field>
 inline size_t index_of(T& t, Field& value) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  using U = remove_cvref_t<T>;
+  size_t index = 0;
+  size_t result = members_count_v<U>;
+  const auto value_addr =
+      static_cast<const volatile void*>(std::addressof(value));
+  reflect26::for_each_data_member(t, [&](auto& field, std::string_view, auto) {
+    const auto field_addr =
+        static_cast<const volatile void*>(std::addressof(field));
+    if (result == members_count_v<U> && field_addr == value_addr) {
+      result = index;
+    }
+    ++index;
+  });
+  return result;
+#else
   const auto& offset_arr = member_offsets<T>;
   size_t cur_offset = (const char*)(&value) - (const char*)(&t);
   auto it = std::lower_bound(offset_arr.begin(), offset_arr.end(), cur_offset);
@@ -174,6 +285,7 @@ inline size_t index_of(T& t, Field& value) {
   }
 
   return std::distance(offset_arr.begin(), it);
+#endif
 }
 
 template <typename Member>
@@ -210,54 +322,99 @@ inline constexpr void visit_members_impl(Visit&& func,
   (func(args, arr[Is], Is), ...);
 }
 
+namespace internal {
+template <typename Visit, typename Field>
+inline constexpr void invoke_for_each_field(Visit& func, Field& field,
+                                            std::string_view name,
+                                            std::size_t index) {
+  if constexpr (std::is_invocable_v<Visit&, Field&>) {
+    func(field);
+  }
+  else if constexpr (std::is_invocable_v<Visit&, Field&, std::string_view>) {
+    func(field, name);
+  }
+  else if constexpr (std::is_invocable_v<Visit&, Field&, std::string_view,
+                                         std::size_t>) {
+    func(field, name, index);
+  }
+  else {
+    static_assert(sizeof(Visit) < 0,
+                  "invalid arguments, full arguments: [field_value&, "
+                  "std::string_view, size_t], at least has field_value and "
+                  "make sure keep the order of arguments");
+  }
+}
+}  // namespace internal
+
 template <typename T, typename Visit>
 inline constexpr void for_each(T&& t, Visit&& func) {
+#ifdef YLT_USE_CXX26_REFLECTION
+  using U = remove_cvref_t<T>;
+  constexpr auto Count = members_count_v<U>;
+  if constexpr (Count == 0) {
+    return;
+  }
+  else {
+    constexpr auto names = get_member_names<U>();
+    reflect26::for_each_data_member(
+        std::forward<T>(t),
+        [&](auto& field, std::string_view name, auto index) {
+          (void)name;
+          internal::invoke_for_each_field(func, field, names[index], index);
+        });
+  }
+#else
   using Tuple = decltype(object_to_tuple(t));
-  using first_t = std::tuple_element_t<0, Tuple>;
-  if constexpr (std::is_invocable_v<Visit, first_t>) {
-    visit_members(t, [&func](auto&... args) {
-      (func(args), ...);
-    });
+  constexpr auto Count = std::tuple_size_v<Tuple>;
+  if constexpr (Count == 0) {
+    return;
   }
   else {
-    if constexpr (std::is_invocable_v<Visit, first_t, std::string_view>) {
-      visit_members(t, [&](auto&... args) {
+    using first_t = std::tuple_element_t<0, Tuple>;
+    if constexpr (std::is_invocable_v<Visit, first_t>) {
+      visit_members(t, [&func](auto&... args) {
+        (func(args), ...);
+      });
+    }
+    else {
+      if constexpr (std::is_invocable_v<Visit, first_t, std::string_view>) {
+        visit_members(t, [&](auto&... args) {
 #if __cplusplus >= 202002L
-        [&]<size_t... Is>(std::index_sequence<Is...>) mutable {
-          constexpr auto arr = get_member_names<T>();
-          (func(args, arr[Is]), ...);
-        }
-        (std::make_index_sequence<sizeof...(args)>{});
+          [&]<size_t... Is>(std::index_sequence<Is...>) mutable {
+            constexpr auto arr = get_member_names<T>();
+            (func(args, arr[Is]), ...);
+          }(std::make_index_sequence<sizeof...(args)>{});
 #else
             visit_members_impl0<T>(std::forward<Visit>(func),
                                    std::make_index_sequence<sizeof...(args)>{},
                                    args...);
 #endif
-      });
-    }
-    else if constexpr (std::is_invocable_v<Visit, first_t, std::string_view,
-                                           size_t>) {
-      visit_members(t, [&](auto&... args) {
+        });
+      }
+      else if constexpr (std::is_invocable_v<Visit, first_t, std::string_view,
+                                             size_t>) {
+        visit_members(t, [&](auto&... args) {
 #if __cplusplus >= 202002L
-        [&]<size_t... Is>(std::index_sequence<Is...>) mutable {
-          constexpr auto arr = get_member_names<T>();
-          (func(args, arr[Is], Is), ...);
-        }
-        (std::make_index_sequence<sizeof...(args)>{});
+          [&]<size_t... Is>(std::index_sequence<Is...>) mutable {
+            constexpr auto arr = get_member_names<T>();
+            (func(args, arr[Is], Is), ...);
+          }(std::make_index_sequence<sizeof...(args)>{});
 #else
             visit_members_impl<T>(std::forward<Visit>(func),
                                   std::make_index_sequence<sizeof...(args)>{},
                                   args...);
 #endif
-      });
-    }
-    else {
-      static_assert(sizeof(Visit) < 0,
-                    "invalid arguments, full arguments: [field_value&, "
-                    "std::string_view, size_t], at least has field_value and "
-                    "make sure keep the order of arguments");
+        });
+      }
+      else {
+        static_assert(sizeof(Visit) < 0,
+                      "invalid arguments, full arguments: [field_value&, "
+                      "std::string_view, size_t], at least has field_value and "
+                      "make sure keep the order of arguments");
+      }
     }
   }
+#endif
 }
 
 }  // namespace ylt::reflection
diff --git a/iguana/ylt/reflection/reflect26_compat.hpp b/iguana/ylt/reflection/reflect26_compat.hpp
new file mode 100644
--- /dev/null
+++ b/iguana/ylt/reflection/reflect26_compat.hpp
@@ -0,0 +1,6 @@
+#pragma once
+// GCC 16 uses __cpp_impl_reflection; future compilers may use __cpp_reflection
+#if (defined(__cpp_impl_reflection) && __cpp_impl_reflection >= 202406L) || \
+    (defined(__cpp_reflection) && __cpp_reflection >= 202406L)
+#define YLT_USE_CXX26_REFLECTION 1
+#endif
diff --git a/iguana/ylt/reflection/reflect26_core.hpp b/iguana/ylt/reflection/reflect26_core.hpp
new file mode 100644
--- /dev/null
+++ b/iguana/ylt/reflection/reflect26_core.hpp
@@ -0,0 +1,233 @@
+#pragma once
+#ifdef YLT_USE_CXX26_REFLECTION
+#include <array>
+#include <cstddef>
+#include <meta>
+#include <string_view>
+#include <tuple>
+#include <type_traits>
+#include <utility>
+#include <vector>
+
+namespace ylt::reflection::reflect26 {
+
+template <std::size_t N>
+struct fixed_string {
+  char data[N];
+
+  consteval fixed_string(const char (&str)[N]) {
+    for (std::size_t i = 0; i < N; ++i) {
+      data[i] = str[i];
+    }
+  }
+
+  consteval operator std::string_view() const { return {data, N - 1}; }
+};
+
+template <fixed_string Name>
+struct field_name {
+  static constexpr auto value = Name;
+};
+
+template <fixed_string Name>
+struct struct_name {
+  static constexpr auto value = Name;
+};
+
+struct skip_base {};
+
+struct skip_field {};
+
+inline constexpr std::string_view normalized_member_name(
+    std::string_view name) {
+  if (name.size() > 3 && name[0] == '_' && name[1] == '_' && name[2] == '_') {
+    name.remove_prefix(3);
+  }
+  return name;
+}
+
+template <std::meta::info Info>
+using meta_type_t = typename[:std::meta::type_of(Info):];
+
+template <std::meta::info Info>
+using remove_cvref_meta_type_t = std::remove_cvref_t<meta_type_t<Info>>;
+
+template <std::meta::info Info>
+consteval auto annotations_array() {
+  return std::define_static_array(std::meta::annotations_of(Info));
+}
+
+template <typename T>
+struct is_field_name_annotation : std::false_type {};
+
+template <fixed_string Name>
+struct is_field_name_annotation<field_name<Name>> : std::true_type {};
+
+template <typename T>
+struct is_struct_name_annotation : std::false_type {};
+
+template <fixed_string Name>
+struct is_struct_name_annotation<struct_name<Name>> : std::true_type {};
+
+template <typename T>
+struct is_skip_base_annotation : std::false_type {};
+
+template <>
+struct is_skip_base_annotation<skip_base> : std::true_type {};
+
+template <typename T>
+struct is_skip_field_annotation : std::false_type {};
+
+template <>
+struct is_skip_field_annotation<skip_field> : std::true_type {};
+
+template <typename T>
+constexpr inline bool skip_base_v = false;
+
+template <std::meta::info Info, template <typename> typename Predicate>
+consteval bool has_annotation_26() {
+  static constexpr auto annotations = annotations_array<Info>();
+  template for (constexpr auto annotation : annotations) {
+    using annotation_t = remove_cvref_meta_type_t<annotation>;
+    if constexpr (Predicate<annotation_t>::value) {
+      return true;
+    }
+  }
+  return false;
+}
+
+template <std::meta::info Member>
+consteval std::string_view member_name_26() {
+  static constexpr auto annotations = annotations_array<Member>();
+  template for (constexpr auto annotation : annotations) {
+    using annotation_t = remove_cvref_meta_type_t<annotation>;
+    if constexpr (is_field_name_annotation<annotation_t>::value) {
+      return annotation_t::value;
+    }
+  }
+  return std::meta::identifier_of(Member);
+}
+
+template <typename T>
+consteval std::string_view type_name_26() {
+  static constexpr auto annotations = annotations_array<^^T>();
+  template for (constexpr auto annotation : annotations) {
+    using annotation_t = remove_cvref_meta_type_t<annotation>;
+    if constexpr (is_struct_name_annotation<annotation_t>::value) {
+      return annotation_t::value;
+    }
+  }
+  return {};
+}
+
+template <std::meta::info Info>
+consteval bool has_skip_base_annotation_26() {
+  return has_annotation_26<Info, is_skip_base_annotation>();
+}
+
+template <std::meta::info Base>
+consteval bool skip_base_26() {
+  using base_type = meta_type_t<Base>;
+  if constexpr (skip_base_v<std::remove_cvref_t<base_type>>) {
+    return true;
+  }
+  else if constexpr (has_skip_base_annotation_26<Base>()) {
+    return true;
+  }
+  else {
+    return has_skip_base_annotation_26<std::meta::type_of(Base)>();
+  }
+}
+
+template <std::meta::info Member>
+consteval bool skip_field_26() {
+  return has_annotation_26<Member, is_skip_field_annotation>();
+}
+
+template <std::meta::info Type>
+consteval void append_data_members_26(std::vector<std::meta::info>& members) {
+  constexpr auto ctx = std::meta::access_context::unchecked();
+  static constexpr auto bases =
+      std::define_static_array(std::meta::bases_of(Type, ctx));
+  template for (constexpr auto base : bases) {
+    if constexpr (!skip_base_26<base>()) {
+      append_data_members_26<std::meta::type_of(base)>(members);
+    }
+  }
+  static constexpr auto direct_members =
+      std::define_static_array(std::meta::nonstatic_data_members_of(Type, ctx));
+  template for (constexpr auto member : direct_members) {
+    if constexpr (!skip_field_26<member>()) {
+      members.push_back(member);
+    }
+  }
+}
+
+template <typename T>
+consteval auto data_members_26() {
+  std::vector<std::meta::info> members;
+  append_data_members_26<^^T>(members);
+  return members;
+}
+
+template <typename T>
+consteval auto data_members_array() {
+  return std::define_static_array(data_members_26<std::remove_cvref_t<T>>());
+}
+
+template <typename T>
+consteval std::size_t members_count_26() {
+  return data_members_26<T>().size();
+}
+
+template <typename T>
+consteval auto member_names_array() {
+  static constexpr auto members = data_members_array<T>();
+  std::array<std::string_view, members.size()> names{};
+  [[maybe_unused]] std::size_t index = 0;
+  template for (constexpr auto member : members) {
+    names[index++] = member_name_26<member>();
+  }
+  return names;
+}
+
+template <template <typename...> typename Predicate, typename T>
+consteval std::size_t member_index_if() {
+  static constexpr auto members = data_members_array<T>();
+  std::size_t result = members.size();
+  std::size_t index = 0;
+  template for (constexpr auto member : members) {
+    using member_t = remove_cvref_meta_type_t<member>;
+    if constexpr (Predicate<member_t>::value) {
+      if (result == members.size()) {
+        result = index;
+      }
+    }
+    ++index;
+  }
+  return result;
+}
+
+template <typename T, typename Visitor>
+constexpr void for_each_data_member(T&& t, Visitor&& visitor) {
+  static constexpr auto members = data_members_array<T>();
+  [[maybe_unused]] std::size_t index = 0;
+  template for (constexpr auto member : members) {
+    visitor(t.[:member:], member_name_26<member>(), index++);
+  }
+}
+
+template <typename T>
+consteval auto member_offsets_26() {
+  static constexpr auto members = data_members_array<T>();
+  std::array<std::size_t, members.size()> offsets{};
+  [[maybe_unused]] std::size_t index = 0;
+  template for (constexpr auto member : members) {
+    auto offset = std::meta::offset_of(member);
+    offsets[index++] = static_cast<std::size_t>(offset.bytes);
+  }
+  return offsets;
+}
+
+}  // namespace ylt::reflection::reflect26
+#endif  // YLT_USE_CXX26_REFLECTION
diff --git a/iguana/ylt/reflection/reflect26_dispatch.hpp b/iguana/ylt/reflection/reflect26_dispatch.hpp
new file mode 100644
--- /dev/null
+++ b/iguana/ylt/reflection/reflect26_dispatch.hpp
@@ -0,0 +1,83 @@
+#pragma once
+#ifdef YLT_USE_CXX26_REFLECTION
+#include <meta>
+#include <string_view>
+#include <type_traits>
+#include <utility>
+
+#include "member_names.hpp"
+
+namespace ylt::reflection::reflect26 {
+
+template <typename Func, typename Field>
+void invoke_dispatch(Func& func, Field& field, std::string_view name,
+                     std::size_t index) {
+  if constexpr (std::is_invocable_v<Func&, Field&, std::string_view,
+                                    std::size_t>) {
+    func(field, name, index);
+  }
+  else if constexpr (std::is_invocable_v<Func&, Field&, std::string_view>) {
+    func(field, name);
+  }
+  else if constexpr (std::is_invocable_v<Func&, Field&>) {
+    func(field);
+  }
+  else {
+    static_assert(sizeof(Func) < 0,
+                  "invalid arguments, full arguments: [field_value&, "
+                  "std::string_view, size_t], at least has field_value and "
+                  "make sure keep the order of arguments");
+  }
+}
+
+template <typename T, typename Func>
+bool dispatch_by_name(T& obj, std::string_view key, Func&& func) {
+  using U = ylt::reflection::remove_cvref_t<T>;
+  static constexpr auto members = data_members_array<U>();
+  if constexpr (members.size() == 0) {
+    return false;
+  }
+  else {
+    static constexpr auto names = ylt::reflection::get_member_names<U>();
+    bool found = false;
+    [[maybe_unused]] std::size_t index = 0;
+    template for (constexpr auto member : members) {
+      if (!found && key == normalized_member_name(names[index])) {
+        invoke_dispatch(func, obj.[:member:], names[index], index);
+        found = true;
+      }
+      ++index;
+    }
+    return found;
+  }
+}
+
+template <std::size_t Index, typename T, typename Func>
+void dispatch_by_index(T& obj, Func&& func) {
+  static constexpr auto members = data_members_array<T>();
+  static_assert(Index < members.size(), "index out of range");
+  func(obj.[:members[Index]:]);
+}
+
+template <typename T, typename Func>
+bool dispatch_by_index(T& obj, std::size_t target, Func&& func) {
+  static constexpr auto members = data_members_array<T>();
+  if constexpr (members.size() == 0) {
+    return false;
+  }
+  else {
+    bool found = false;
+    [[maybe_unused]] std::size_t index = 0;
+    template for (constexpr auto member : members) {
+      if (!found && index == target) {
+        invoke_dispatch(func, obj.[:member:], member_name_26<member>(), index);
+        found = true;
+      }
+      ++index;
+    }
+    return found;
+  }
+}
+
+}  // namespace ylt::reflection::reflect26
+#endif  // YLT_USE_CXX26_REFLECTION
diff --git a/iguana/ylt/reflection/user_reflect_macro.hpp b/iguana/ylt/reflection/user_reflect_macro.hpp
--- a/iguana/ylt/reflection/user_reflect_macro.hpp
+++ b/iguana/ylt/reflection/user_reflect_macro.hpp
@@ -4,6 +4,7 @@
 #include <type_traits>
 
 #include "internal/arg_list_macro.hpp"
+#include "reflect26_compat.hpp"
 
 namespace ylt::reflection {
 template <typename T>
@@ -164,4 +165,13 @@ struct is_custom_reflect<
 template <typename T>
 inline constexpr bool is_custom_refl_v =
     is_custom_reflect<remove_cvref_t<T>>::value;
+#ifdef YLT_USE_CXX26_REFLECTION
+#undef YLT_REFL
+#undef YLT_REFL_PRIVATE
+#undef YLT_REFL_PRIVATE_
+#define YLT_REFL(STRUCT, ...)
+#define YLT_REFL_PRIVATE(STRUCT, ...)
+#define YLT_REFL_PRIVATE_(STRUCT, ...)
+#endif
+
 }  // namespace ylt::reflection
diff --git a/iguana_reflect26_changes.md b/iguana_reflect26_changes.md
new file mode 100644
--- /dev/null
+++ b/iguana_reflect26_changes.md
@@ -0,0 +1,516 @@
+# iguana C++26 反射与 proto3 变更追溯
+
+本文档记录本轮 C++26 静态反射、proto3 wire-only 补全和非 C++26 protobuf helper 的实际落地内容，供后续追溯和 review 使用。早期方案文档是设计草案；本文只描述当前代码里的实现、修改原因、验证结果和待 review 风险。
+
+参考文章：
+
+- https://purecpp.cn/article.html?slug=VutnwLDX
+- 采用的核心思路是：结构体本身作为 schema，字段遍历使用 `std::meta::nonstatic_data_members_of` 和 `template for`，额外语义通过 `[[= ...]]` 注解挂到字段或类型上。
+
+## 总体目标
+
+这次改造把 C++26 分支从“继续复用 C++17/C++20 的宏注册、结构化绑定、偏移表分发”改成真正使用静态反射：
+
+- 字段数量、字段名、字段访问都来自 `std::meta`。
+- JSON/XML/YAML 反序列化不再通过 offset 转回字段指针，而是 splice 到真实成员。
+- protobuf 自定义字段号支持 C++26 值注解；C++26 注解路径不再依赖 `YLT_REFL_PB`，但保留该宏作为旧代码和 custom reflection 入口。
+- 非 C++26 路径补齐 `pb_members` helper，能表达 C++26 注解路径已经具备的 proto3 wire-only schema metadata。
+- 公开入口尽量保留，但 C++26 下 `object_to_tuple`、`struct_to_tuple`、`visit_members` 的行为已经转为反射 metadata 和逐字段访问，不再保证旧的 tuple/参数包调用契约。
+
+## 变更追溯总表
+
+后续 review 先看这张表定位改动范围，再进入对应章节和代码。表里的“为什么改”只记录本轮必须改的原因，避免把早期设计草案和最终落地混在一起。
+
+| 范围 | 改了什么 | 为什么改 | Review 重点 |
+| --- | --- | --- | --- |
+| `iguana/ylt/reflection/reflect26_compat.hpp` | 新增 C++26 反射特性开关，兼容 `__cpp_impl_reflection` 和后续 `__cpp_reflection`。 | 让 C++26 分支可以独立接入，同时旧编译器不受影响。 | 宏检测是否只在支持 `std::meta` 的编译器上打开。 |
+| `iguana/ylt/reflection/reflect26_core.hpp` | 新增字段收集、字段名、注解扫描、逐字段访问、offset 兼容工具。 | 替代宏注册和结构化绑定字段枚举，统一支撑 JSON/XML/YAML/protobuf。 | 基类递归、`skip_base`/`skip_field`、`access_context::unchecked` 的可见性边界。 |
+| `iguana/ylt/reflection/reflect26_dispatch.hpp` | 新增运行时 key 到 C++26 成员访问的分发表。 | JSON/XML/YAML 输入字段名是运行时字符串，不能只靠纯编译期遍历。 | alias 名称、查找失败、性能和旧 offset 分发行为是否一致。 |
+| `member_count.hpp`、`member_names.hpp`、`member_ptr.hpp`、`member_value.hpp`、`user_reflect_macro.hpp` | C++26 下接入 `std::meta` 字段来源，`YLT_REFL`/`YLT_REFL_PRIVATE` 保留为兼容入口；tuple/参数包式 helper 在 C++26 下改为 metadata/逐字段访问。 | 让旧宏代码在 C++26 下可编译，同时让 C++26 路径不再依赖宏生成字段和结构化绑定。 | 旧路径是否完全保留；C++26 下 `visit_members`/`object_to_tuple` 行为变化是否可接受；no-op 宏是否改变私有反射预期。 |
+| `iguana/util.hpp`、`iguana/dynamic.hpp`、`iguana/json_util.hpp`、`iguana/xml_util.hpp` | 调整 C++26 可反射类型过滤，给动态基类和 XML/JSON wrapper 增加排除标记；新增 `xml_required` 注解。 | 防止把容器、字符串、wrapper、框架基类内部状态当成业务 message 字段递归反射。 | 排除列表是否覆盖所有 wrapper。 |
+| `iguana/json_reader.hpp`、`iguana/xml_reader.hpp`、`iguana/yaml_reader.hpp` | C++26 读取分支改用 `dispatch_by_name` 后直接解析真实成员。 | 删除 C++26 路径上的 offset 指针算术，避免假对象地址和私有布局依赖。 | 未知字段处理、alias、required 字段和旧路径语义是否一致。 |
+| `iguana/common.hpp` | 新增 protobuf 注解、老路径 helper、字段号校验、oneof 展开、wire type selector、Timestamp/Duration/unknown fields 公共描述。 | C++26 注解路径和非 C++26 helper 路径需要共享同一套 proto3 schema metadata。 | 字段号合法性是否影响旧 `YLT_REFL_PB` 用户；helper 和注解是否语义对齐。 |
+| `iguana/pb_util.hpp` | 统一 varint/tag 解码、字段号校验、递归深度 guard、wire schema 辅助。 | proto3 wire-only 需要对非法 field number、非法 wire type、截断 varint 做一致边界检查。 | 递归深度限制是否和 protobuf 兼容。 |
+| `iguana/pb_reader.hpp` | 补 packed/unpacked repeated、map entry 任意顺序、重复字段 merge/last-wins、unknown fields 保留、well-known type 转换和非法 wire 检查。 | 使 public protobuf reader 达到 proto3 wire-only 互通语义，而不是只处理 iguana 自己写出的 bytes。 | 截断 payload、map 重复 key、oneof message merge、unknown group 深度。 |
+| `iguana/pb_writer.hpp` | 写入端接入 schema-aware wire 类型、proto3 optional presence、oneof monostate 跳过、unknown fields 原样写回。 | 让用户字段类型可以和 protobuf wire 类型分离，并保持未知字段 roundtrip。 | 默认值省略、optional present default、oneof 输出和 unknown bytes 拼接顺序。 |
+| `CMakeLists.txt` | 新增 `ENABLE_CXX26_REFLECTION`、`*_cpp26` 测试目标、`iguana_conformance` target 和可选 runner CTest。 | 同一构建目录内同时验证旧路径和 C++26 路径，并能接官方 conformance runner。 | CTest 是否覆盖必要目标；conformance target 的范围是否标注清楚。 |
+| `.github/workflows/linux-gcc-cxx26.yml` | 新增 GCC 16.1.0 C++26 反射 CI。 | 提交后在 GitHub Actions 中真实编译 `-std=gnu++26 -freflection` 路径并运行 `_cpp26` 测试。 | 官方 gcc 容器 tag 和 GCC 反射实现仍可能随上游演进，需要定期确认。 |
+| `benchmark/pb_benchmark.cpp` | 支持命令行迭代次数，输出 iguana/protobuf 耗时比，修正 map benchmark 自比较断言。 | 便于复现性能结果，并避免 benchmark 断言掩盖 map 场景问题。 | benchmark 是否只做性能观察，不作为语义正确性证明。 |
+| `test/test_pb.cpp`、`test/test_proto3.cpp`、`test/conformance/iguana_conformance.cpp`、`test/proto/*.proto` | 扩展 proto3 wire-only 单测、protoc runtime 对照、官方 conformance testee 和 fixture proto。 | 覆盖新增 schema helper、C++26 注解、旧路径 helper、wire 互操作和官方 conformance 子集。 | `iguana_conformance` 是 wire canonicalizer，不等同于 public API conformance。 |
+| `iguana_reflect26_changes.md`、`README.md`、`lang/struct_pb_intro.md` | 记录实际变更、验证命令、能力边界和用户用法。 | 后续排查可以从文档追到代码、测试和验收结果，避免多个草稿文档分散事实来源。 | 文档是否准确区分已完成能力、conformance 子集和待修复问题。 |
+
+## 计划完成情况
+
+| 计划项 | 状态 | 落地结果 |
+| --- | --- | --- |
+| 引入 C++26 反射开关和基础层 | 已完成 | 新增 `reflect26_compat.hpp`、`reflect26_core.hpp`、`reflect26_dispatch.hpp`，旧编译器继续走原路径。 |
+| 字段数量、字段名、字段遍历改用 `std::meta` | 已完成 | `members_count_26`、`member_names_array`、`for_each_data_member` 已接入反射层；逐字段访问用 `template for` 和 `obj.[:member:]`。 |
+| JSON/XML/YAML 读取去掉 C++26 offset 分发 | 已完成 | C++26 分支通过 `dispatch_by_name` 做运行时 key 查找，再 splice 到真实成员解析。 |
+| 保留公开入口并记录 C++26 行为变化 | 已完成 | `visit_members`、`object_to_tuple`、`struct_to_tuple` 入口仍存在；C++26 下 `object_to_tuple`/`struct_to_tuple` 返回 `std::meta::info` 字段列表，`visit_members` 改为逐字段 visitor，不再等价于旧路径的 tuple/参数包 API。 |
+| 注解替代宏注册语义 | 已完成 | 已支持 `field_name`、`struct_name`、`skip_base`、`skip_field`、`xml_required`、`pb_field` 等注解。 |
+| protobuf 参考文章式注解能力 | 已完成 | 已支持 `pb_zigzag`、`pb_fixed`、`pb_bytes`、`pb_oneof`、`pb_optional`、`as_timestamp`、`as_duration`、`pb_unknown_fields`。 |
+| protobuf optional/vector wire 注解 | 已完成 | `pb_zigzag/pb_fixed` 支持 scalar、`std::optional<T>`、`std::vector<T>`，用户字段类型和 wire schema 分离。 |
+| `template for` 替代旧式逐字段展开 | 已完成 | C++26 逐字段执行场景已改为 `template for`；非 C++26 tuple/frozen map 和 protobuf variant/oneof 展开等场景仍保留 pack expansion。 |
+| 提取注解扫描公共能力 | 已完成 | `reflect26_core.hpp` 新增 `has_annotation_26`，protobuf、XML、skip 注解共用同一套 `annotations_of + template for` 判定。 |
+| 测试和验证 | 已完成 | C++26 目标、全量 build、CTest、`git diff --check` 均作为最终验收项。 |
+| 仍不纳入本轮 | 已记录 | XML attr/cdata 注解化、proto2 required/extension/custom option 属于后续独立语义改造。 |
+
+## 新增反射核心
+
+新增文件：
+
+- `iguana/ylt/reflection/reflect26_compat.hpp`
+- `iguana/ylt/reflection/reflect26_core.hpp`
+- `iguana/ylt/reflection/reflect26_dispatch.hpp`
+
+`reflect26_compat.hpp` 只做特性开关。它检测 `__cpp_impl_reflection` 或未来的 `__cpp_reflection`，定义 `YLT_USE_CXX26_REFLECTION`。
+
+`reflect26_core.hpp` 是纯 C++26 反射基础层：
+
+- `data_members_26<T>()` 递归收集基类和本类非静态数据成员。
+- `skip_field` 注解可以把本地状态字段从反射字段列表中排除。
+- `has_annotation_26<Member, Predicate>()` 统一封装 `annotations_of + template for` 注解判定。
+- `members_count_26<T>()` 替代结构化绑定计数字段。
+- `member_names_array<T>()` 使用 `std::meta::identifier_of` 或字段注解拿字段名。
+- `for_each_data_member(t, visitor)` 使用 `template for` 和 `t.[:member:]` 直接访问字段，并把字段名和 index 一起传给 visitor。
+- `member_offsets_26<T>()` 只保留给仍需要 offset 数组的兼容路径。
+
+`reflect26_dispatch.hpp` 是运行时 key 到静态字段访问的桥：
+
+- 使用 `template for` 线性遍历 C++26 字段列表，并用字段名或规范化字段名匹配运行时 key。
+- 命中后直接 splice 到 `obj.[:member:]` 调用用户回调，回调可接收 `(field)`、`(field, name)` 或 `(field, name, index)`。
+- 这样避免了旧实现的 offset 指针算术；当前没有使用 `frozen::unordered_map` 做 C++26 路径的运行时 key 查找，性能重点是线性比较的字段数成本。
+
+这个文件仍然需要。C++26 反射解决的是“编译期知道有哪些成员”，但 JSON/XML/YAML 输入 key 是运行时字符串，需要一层运行时查找和类型化调用桥接。
+
+## 注解能力
+
+当前实现了九类注解能力。
+
+字段别名：
+
+```cpp
+struct T {
+  [[= ylt::reflection::reflect26::field_name<"id">{}]] int user_id;
+};
+```
+
+类型名别名：
+
+```cpp
+struct [[= ylt::reflection::reflect26::struct_name<"user">{}]] user_t {
+  int id;
+};
+```
+
+protobuf 字段号：
+
+```cpp
+struct Person {
+  [[= iguana::pb_field(10)]] std::string name;
+  [[= iguana::pb_field(20)]] int32_t age;
+};
+```
+
+base 跳过：
+
+```cpp
+struct D : [[= ylt::reflection::reflect26::skip_base{}]] Base {
+  int x;
+};
+```
+
+字段跳过：
+
+```cpp
+struct T {
+  int id;
+  [[= ylt::reflection::reflect26::skip_field{}]] int local_cache;
+};
+```
+
+XML required 字段：
+
+```cpp
+struct T {
+  [[= iguana::xml_required{}]] int id;
+};
+```
+
+protobuf wire 语义：
+
+```cpp
+struct T {
+  [[= iguana::pb_zigzag]] int32_t delta;
+  [[= iguana::pb_fixed]] uint32_t checksum;
+  [[= iguana::pb_bytes]] std::string payload;
+  [[= iguana::pb_oneof<5, 8>]]
+  std::variant<std::monostate, int32_t, std::string> result;
+  [[= iguana::as_timestamp]]
+  std::chrono::system_clock::time_point created_at;
+  [[= iguana::as_duration]]
+  std::chrono::nanoseconds timeout;
+};
+```
+
+protobuf 未知字段保留：
+
+```cpp
+struct OldMessage {
+  [[= iguana::pb_field(2)]] int32_t id;
+  [[= iguana::pb_unknown_fields]] std::string unknown;
+};
+```
+
+protobuf 字段号使用值注解 `[[= iguana::pb_field(N)]]`，不是 `pb_field<N>{}`。这是参考文章里 `[[= proto3::field(5)]]` 的写法，字段号作为 constexpr 值提取，API 更短，语义也更接近 protobuf schema。
+
+## 反射层改动
+
+`member_count.hpp`：
+
+- C++26 分支直接调用 `reflect26::members_count_26<T>()`。
+- 不再依赖聚合结构化绑定探测，也没有 256 字段限制。
+
+`member_names.hpp`：
+
+- C++26 分支直接返回 `reflect26::member_names_array<T>()`。
+- `get_struct_name<T>()` 优先读取 `struct_name` 注解，再回退到旧 alias API 和 `type_string<T>()`。
+- 字段名遍历改为 `template for`。
+- C++26 offset 数组改用 `std::meta::offset_of` 生成，避免假对象地址计算。
+
+`member_ptr.hpp`：
+
+- C++26 分支不再包含宏生成文件 `internal/generate/member_macro.hpp`。
+- `object_to_tuple(t)` 和 `struct_to_tuple<T>()` 当前返回 `reflect26::data_members_26<T>()`，即字段 `std::meta::info` 列表，而不是旧路径的引用 tuple 或字段指针 tuple。
+- `visit_members(t, visitor)` 在 C++26 分支委托给 `for_each_data_member`，按字段逐次调用 visitor，传入 `(field, name, index)`。
+- 因此 C++26 下不再兼容依赖 `visitor(field0, field1, ...)` 一次性参数包的旧用法；需要参数包契约的用户应继续走非 C++26 路径或单独补兼容层。
+
+这里没有强行把所有 `index_sequence` 改成 `template for`。原因是非 C++26 旧路径的 tuple 构造、旧路径 frozen map 初始化，以及 protobuf variant/oneof 字段展开仍需要参数包展开；`template for` 更适合 C++26 的逐字段执行逻辑。
+
+`member_value.hpp`：
+
+- `for_each(t, visitor)` 在 C++26 分支用 `for_each_data_member` 直接访问字段。
+- `for_each` 的字段名仍通过 `get_member_names<T>()` 取得，以同时保留旧 `get_alias_field_names` API 和新 `field_name` 注解。
+- `index_of(t, field)` 在 C++26 分支用地址比较确定字段 index，不再排序 offset 数组再二分。
+- 保留旧分支，非 C++26 编译器行为不变。
+
+`user_reflect_macro.hpp`：
+
+- C++26 分支下 `YLT_REFL`/`YLT_REFL_PRIVATE` 变成 no-op。
+- 目的是让旧测试和旧用户代码在 C++26 下可以继续编译，但成员枚举实际来自语言反射。
+
+## JSON/XML/YAML 读取路径
+
+`json_reader.hpp`、`xml_reader.hpp`、`yaml_reader.hpp` 都增加了 C++26 分支：
+
+- 运行时 key 使用 `reflect26::dispatch_by_name` 找到字段。
+- 找到字段后直接调用原有的 `from_json_impl`、`xml_parse_item`、`yaml_parse_item`。
+- 未知字段处理逻辑保持原样，继续受 `THROW_UNKNOWN_KEY` 控制。
+
+旧路径还保留 `get_variant_map` + offset 的实现，用于 C++17/C++20。
+
+## protobuf 改动
+
+`common.hpp` 新增：
+
+- `iguana::pb_field_annotation`
+- `iguana::pb_field(size_t)`
+- `iguana::pb_zigzag`
+- `iguana::pb_fixed`
+- `iguana::pb_bytes`
+- `iguana::pb_optional`
+- `iguana::pb_unknown_fields`
+- C++26 注解提取函数 `pb_field_no_26<Member>()`
+- 字段号合法性检查和重复字段号检查
+
+字段号规则现在统一检查：
+
+- 必须大于 0。
+- 必须小于等于 `2^29 - 1`。
+- 不能落入 protobuf 保留区间 `[19000, 19999]`。
+- 同一个 message 内不能重复。
+
+`pb_util.hpp` 删除了重复的 `pb_field_no` 和重复字段号检查实现，改为复用 `common.hpp` 里的统一校验。
+
+这让两条路径都能受益：
+
+- 旧的 `YLT_REFL_PB(Struct, (field, no), ...)`
+- 新的 `[[= iguana::pb_field(no)]]`
+- 新的 `[[= iguana::pb_zigzag]]` 和 `[[= iguana::pb_fixed]]`
+- 新的 `[[= iguana::pb_bytes]]`
+- 新的 `[[= iguana::pb_oneof<N...>]]`
+- 新的 `[[= iguana::pb_optional]]`
+- 新的 `[[= iguana::as_timestamp]]` 和 `[[= iguana::as_duration]]`
+- 新的 `[[= iguana::pb_unknown_fields]]`
+
+`pb_zigzag` 把 `int32_t/int64_t` 映射到 `sint32/sint64` wire 语义；`pb_fixed` 把 `uint32_t/uint64_t/int32_t/int64_t` 映射到 `fixed32/fixed64/sfixed32/sfixed64`。二者同时支持标在 `std::optional<T>` 和 `std::vector<T>` 上，用户结构体仍保存原始整数类型，wire schema 单独保存 wrapper 类型。
+
+`pb_bytes` 标记 `std::string` 或 `std::string_view` 字段在 `to_proto` schema 中生成为 `bytes`。它不改变 protobuf 二进制 wire 类型，因为 `string` 和 `bytes` 都是 LengthDelimited。
+
+`pb_oneof<N...>` 标记 `std::variant<std::monostate, ...>` 字段为 protobuf oneof，并用注解里的字段号逐一对应非 `monostate` 备选项。`monostate` 只表示未选择状态，不写入 wire，也不会出现在 schema 里。
+
+`pb_optional` 标记 `std::optional<T>` 字段为 proto3 explicit presence 字段。字段有值时即使是默认值 `0/false/""` 也会写入 wire，`to_proto` 会生成 `optional` label；未设置时不写入。
+
+`as_timestamp` 标记 `std::chrono::system_clock::time_point` 字段按 `google.protobuf.Timestamp` message 编码；`as_duration` 标记 `std::chrono::nanoseconds` 字段按 `google.protobuf.Duration` message 编码。二者也支持对应的 `std::optional<T>` 和 `std::vector<T>`，用户结构体里仍保持 chrono 类型。
+
+`pb_unknown_fields` 标记一个 `std::string` 字段作为未知 protobuf 字段的原始字节缓存。C++26 读取路径遇到未知 field 时会把 tag 和 payload 一起追加进去，写回时再原样输出；该字段不会参与普通 protobuf 字段号分配，也不会出现在 `to_proto` 生成的 schema 里。当前限制是每个 message 最多一个该字段。未知字段跳过覆盖 Varint、Fixed32、Fixed64、LengthDelimited，以及已废弃但仍合法的 group wire type。
+
+protobuf 读取端现在同时接受 packed 和 unpacked 的 repeated primitive 编码。写入端仍使用 proto3 默认 packed 编码，但解析时允许同一 repeated 字段混合出现 packed chunk 和 unpacked value。
+
+protobuf map entry 读取端现在按 entry 内部 field number 解析，不再依赖 key/value 顺序；entry 内 unknown field 会按 wire type 跳过，重复 key 按 protobuf map 语义采用 last-wins。
+
+wire-only proto3 解析继续补齐了重复字段语义和非法输入边界：
+
+- repeated primitive 的多个 packed chunk 会追加合并，不会覆盖前一个 chunk。
+- singular message 重复出现时按 protobuf 语义 merge；`std::optional<message>` 也会在已有值上 merge。
+- oneof 重复出现时保持 last-wins，同一 message 备选项重复出现也不做跨 oneof case merge。
+- tag 解码统一校验 field number 不能为 0、wire type 不能为 6/7、顶层不能出现 EndGroup。
+- length-delimited payload 会限制在自身 slice 内解析，截断 string/message/packed payload、过长 varint 和 fixed packed 坏长度都会抛异常。
+
+字段注解的实现方式是把“用户字段类型”和“protobuf wire 类型”分开：
+
+- `pb_field_t` 保留 `value_type` 作为结构体真实字段类型。
+- `wire_value_type`/`wire_sub_type` 只用于 size 计算、写入、读取和 `to_proto` schema。
+- 写入时通过 `make_pb_wire_scalar` 临时构造 `sint32_t/fixed32_t/...` wrapper，不改用户对象。
+- 读取时通过 `assign_pb_wire_value` 转回原始字段；对 packed repeated wrapper 直接按 payload 解每个 item，避免把 `std::vector<fixed32_t>` 之类 wrapper vector 当成普通 `vector<char>` resize。
+
+这样 `[[= iguana::pb_zigzag]] std::vector<int64_t>` 可以生成 `repeated sint64`，二进制和显式 wrapper 结构一致，但业务代码不需要暴露 wrapper 类型。
+
+## XML required 注解
+
+`xml_util.hpp` 新增 `iguana::xml_required`。C++26 分支会通过 `std::meta::annotations_of` 收集带该注解的字段名，`xml_reader.hpp` 的 required 检查同时支持旧 `REQUIRED(type, fields...)` 宏和新字段注解。
+
+字段名仍然走统一的 `member_name_26`，因此 `xml_required` 可以和 `field_name` 注解组合使用：
+
+```cpp
+struct T {
+  [[= ylt::reflection::reflect26::field_name<"identifier">{}]]
+  [[= iguana::xml_required{}]] int id;
+};
+```
+
+required 检查现在记录已解析字段名列表并做精确匹配，不再用拼接字符串做 substring 查找。这样 `id` 和 `identifier` 这类重叠字段名不会误判 required 字段已出现。
+
+## 可反射类型过滤
+
+`util.hpp` 的 `ylt_refletable_v` 在 C++26 分支下更严格：
+
+- 排除 string/container/fixed array/tuple/optional/variant/smart pointer/pb wrapper。
+- 排除显式标记的反射包装类型。
+- 避免把 `std::string`、`std::vector`、`std::optional` 或 XML wrapper 当成 message 继续反射内部实现。
+
+`json_util.hpp` 和 `xml_util.hpp` 标记了需要排除的 wrapper：
+
+- `numeric_str`
+- `xml_attr_t`
+- `xml_cdata_t`
+
+`dynamic.hpp` 给 iguana 动态基类注册了 `skip_base_v`：
+
+- `iguana::detail::base`
+- `iguana::base_impl<T, ENABLE_FLAG>`
+
+这避免 C++26 递归收集继承成员时把框架基类的虚函数状态或内部字段混入业务字段。
+
+## 测试覆盖
+
+新增和调整的测试点：
+
+- `test/test_some.cpp`
+  - 无宏 alias 仍可工作。
+  - C++26 `field_name` 注解可驱动 JSON 写入和读取。
+  - C++26 `skip_field` 注解可排除本地字段。
+
+- `test/test_xml.cpp`
+  - C++26 `struct_name` 和 `field_name` 注解可驱动 XML 根节点和字段名。
+  - C++26 `xml_required` 注解可替代 `REQUIRED` 宏，并支持和 `field_name` 组合。
+  - required 字段检查覆盖 `id` / `identifier` 这类字段名重叠场景，确认使用精确匹配。
+
+- `test/test_pb.cpp`
+  - `[[= iguana::pb_field(N)]]` 能生成正确 proto schema。
+  - `[[= iguana::pb_zigzag]]` 和 `[[= iguana::pb_fixed]]` 能生成正确 wire 类型，并与 wrapper 类型二进制一致。
+  - `[[= iguana::pb_zigzag]]` 和 `[[= iguana::pb_fixed]]` 覆盖 scalar、`std::optional<T>` 和 `std::vector<T>`。
+  - `[[= iguana::pb_bytes]]` 能把字符串字段生成为 proto `bytes`，同时保持二进制编码与普通字符串一致。
+  - `[[= iguana::pb_oneof<N...>]]` 能给 oneof 备选项指定非连续字段号，并跳过 `std::monostate`。
+  - `[[= iguana::pb_optional]]` 能保持 proto3 optional presence，present default value 会写入并 roundtrip。
+  - `[[= iguana::as_timestamp]]` 和 `[[= iguana::as_duration]]` 能按 protobuf well-known message 编码、解码和生成 schema import。
+  - `[[= iguana::pb_unknown_fields]]` 能保留未知字段的原始 protobuf bytes，并在再序列化后恢复给新版本结构体，覆盖 group unknown field。
+  - repeated primitive 读取兼容 packed、unpacked 和混合编码。
+  - repeated primitive 读取兼容多个 packed chunk 追加合并。
+  - map entry 读取兼容 key/value 任意顺序、entry 内 unknown field 和重复 key last-wins。
+  - singular message/optional message 重复字段按 merge 解析，oneof 重复字段按 last-wins 解析。
+  - malformed wire 覆盖 field number 0、非法 wire type、截断 length-delimited、截断 packed varint、过长 varint 和 fixed packed 坏长度。
+  - unknown group 跳过受 protobuf 递归深度限制约束，深层 group 会抛出递归限制异常。
+  - 注解字段号的二进制结果与 `YLT_REFL_PB` 旧宏一致。
+
+- `test/test_proto3.cpp`
+  - 启用本机 `protoc 3.21.12` 生成的 C++ runtime 对照。
+  - 继续覆盖正常路径的 iguana/protoc serialized bytes 一致性。
+  - 新增手写 wire 输入互操作：多 packed chunk + unpacked mixed repeated、singular message merge、oneof last-wins、map entry key/value 任意顺序、entry 内 unknown field、重复 map key last-wins。
+
+- `test/conformance/iguana_conformance.cpp`
+  - 新增官方 protobuf conformance runner 的 iguana testee。
+  - 实现 runner pipe 协议，解析 `ConformanceRequest` 并返回 `ConformanceResponse`。
+  - 当前只处理 `protobuf_test_messages.proto3.TestAllTypesProto3` 的 binary protobuf payload 和 protobuf output；JSON/text/JSPB/proto2/非 protobuf 输出明确 skipped。
+  - 对 proto3 binary 输入做 wire 结构校验、递归深度限制、length/fixed/varint 截断检测、packed fixed 长度检测和 proto3 string UTF-8 校验；合法 payload 会按 `TestAllTypesProto3` schema 做 canonical binary re-encode 后返回。
+  - canonical re-encode 覆盖 singular 默认值省略、repeated numeric packed/unpacked 输出规范、singular message merge、oneof last-wins 和 oneof message merge；该 testee 当前用于 wire-only protobuf-output conformance，不扩展到 JSON/text/proto2。
+
+- `test/test_reflection.cpp`
+  - C++26 下跳过依赖旧宏私有反射的断言。
+  - C++26 下覆盖 `visit_members` 的逐字段 visitor 行为；旧路径继续覆盖参数包 visitor 行为。
+
+`CMakeLists.txt` 新增 `ENABLE_CXX26_REFLECTION`：
+
+- 打开后为现有测试生成 `_cpp26` 目标。
+- 编译参数为 `-std=gnu++26 -freflection`。
+- `_cpp26` 目标会从当前 C++ 编译器查询 `libstdc++.so` 位置并设置 build rpath，避免 GCC 16 构建产物在系统默认 libstdc++ 较旧时运行失败。
+- CTest 同时覆盖普通目标和 C++26 目标。
+- 新增 `iguana_conformance` target；如设置 `PROTOBUF_CONFORMANCE_RUNNER` cache 变量，可把官方 runner 作为 CTest 项接入。
+
+`benchmark/pb_benchmark.cpp` 调整：
+
+- 支持通过命令行传入迭代次数。
+- 输出 iguana/protobuf 耗时比值，便于直接判断哪边更快。
+- 修正 map serialize benchmark 的自比较断言。
+
+## visit_members 当前行为
+
+`visit_members` 入口仍然保留，但 C++26 和旧路径的调用契约不同。
+
+旧路径仍支持一次性参数包 visitor：
+
+```cpp
+visit_members(obj, [](auto&... fields) {
+  // 用户拿到字段参数包
+});
+```
+
+C++26 路径当前直接复用 `for_each_data_member`，逐字段调用 visitor：
+
+```cpp
+visit_members(obj, [](auto& field, std::string_view name, std::size_t index) {
+  // 每次处理一个字段
+});
+```
+
+这和旧路径的 `visitor(field0, field1, ...)` 不等价。可变参数 lambda 在 C++26 下可能仍能编译，但它接收到的是单个字段调用的参数组，而不是全部字段组成的参数包。
+
+## template for 和 index_sequence
+
+逐字段访问已经优先使用 `template for`，例如字段名、注解扫描、JSON/XML/YAML 读取分发、protobuf C++26 字段收集都直接遍历 `std::meta::info` 数组。之前这种形式：
+
+```cpp
+[&]<std::size_t... Is>(std::index_sequence<Is...>) {
+  (visitor(t.[:members[Is]:], std::string_view{},
+           std::integral_constant<std::size_t, Is>{}),
+   ...);
+}(std::make_index_sequence<members.size()>{});
+```
+
+在逐字段执行场景下已经改成：
+
+```cpp
+template for (constexpr auto member : members) {
+  visitor(t.[:member:], member_name_26<member>(), index++);
+}
+```
+
+仍保留 `index_sequence` 或 pack expansion 的主要场景：
+
+- 非 C++26 路径的 tuple 构造：`std::tie(field...)`、字段类型 tuple、`std::tuple_cat`。
+- 非 C++26 路径的 frozen map 初始化：需要 `{name, index}...` 这种参数包。
+- variant/pb 字段展开：protobuf oneof/variant 会把一个 C++ 字段展开为多个 wire field。
+- enum/string 转换表：这些和 C++26 class reflection 无关。
+
+这些位置使用 pack expansion 更直接，也更符合现有类型接口。把它们改成 `template for` 反而会引入中间容器或更复杂的状态代码。
+
+## 后续注解方向
+
+可以继续用注解简化的方向：
+
+- XML attr/cdata：当前 wrapper 还承载实际存储结构，不能只靠注解等价替换；后续可以为普通字段提供注解式语法糖。
+- protobuf proto2 required、extension、自定义 option 等更大 schema 语义。
+
+当前没有把所有 wrapper 都改成注解，是因为 XML attr/cdata 还承载存储结构，proto2/extension 会改变兼容性和 schema 语义，需要单独测试矩阵。
+
+## Review 重点
+
+当前建议把 review 分成两类：一类是已知需要产品/范围确认的问题，另一类是大范围改动的重点阅读区域。
+
+已知需要确认的问题：
+
+- `test/conformance/iguana_conformance.cpp` 当前是面向官方 runner 的 proto3 binary canonicalizer，没有调用 public `iguana::from_pb` / `iguana::to_pb`。因此 conformance 通过只能证明 wire-only protobuf-output 子集 testee 通过，不能单独证明所有 public API 路径都通过官方 conformance 语义。
+- C++26 路径使用 `access_context::unchecked`，可以反射 private data member。需要产品层明确这是预期能力，还是应该默认只反射公开成员/显式注册成员。
+
+重点阅读区域：
+
+- `reflect26_core.hpp` 的基类递归和 `skip_base` 判断是否符合业务继承模型。
+- `reflect26_dispatch.hpp` 的线性 key 查找 + 类型化分发是否满足性能预期。
+- `common.hpp` 中 protobuf 字段号校验是否会影响旧 `YLT_REFL_PB` 用户。
+- `util.hpp` 的 C++26 `ylt_refletable_v` 排除条件是否覆盖所有 wrapper 类型。
+- JSON/XML/YAML C++26 分支和旧分支在未知字段处理上的行为是否一致。
+
+已清理的问题：
+
+- `pb_reader.hpp` unknown group 跳过路径已加 `pb_recursion_guard`，并新增深层 unknown group 回归测试。
+- `xml_reader.hpp` required 字段检查已改为精确字段名匹配，并新增 `id` / `identifier` 重叠字段名回归测试。
+- `NestedMsg.proto`、`test_vector.proto` 这类测试生成文件不再写到仓库根目录，根目录历史临时文件已删除并加入 `.gitignore` 兜底。
+- C++26 GitHub Actions 容器内构建路径改用运行时 `$GITHUB_WORKSPACE`，避免 `${{ github.workspace }}` 展开到宿主 `/home/runner/work/...` 后让 `test_json_files_cpp26` 找不到 `data/`；同时为 JSON 文件测试固定 CTest 工作目录。
+
+## 验证命令
+
+本轮使用的核心验证命令：
+
+```bash
+cmake --build build_cpp26 --target test_some_cpp26 test_ut_cpp26 test_json_files_cpp26 test_xml_cpp26 test_yaml_cpp26 test_pb_cpp26 test_reflection_cpp26 -j2
+cmake --build build_cpp26 -j2
+cmake --build build_cpp26 --target test_proto -j2
+ctest --test-dir build_cpp26 --output-on-failure
+LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_proto
+LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_pb
+LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_xml
+LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_pb_cpp26
+LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_xml_cpp26
+LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ctest --test-dir build_cpp26 --output-on-failure
+cmake --build build_cpp26 --target iguana_conformance pb_benchmark -j2
+LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/pb_benchmark 100000
+git diff --check
+```
+
+官方 protobuf conformance reference 验证使用 `v3.21.12` 源码临时构建：
+
+```bash
+cmake -S .cache/protobuf-v3.21.12 -B .cache/protobuf-v3.21.12-build -Dprotobuf_BUILD_CONFORMANCE=ON -Dprotobuf_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release
+cmake --build .cache/protobuf-v3.21.12-build --target conformance_test_runner conformance_cpp -j2
+.cache/protobuf-v3.21.12-build/conformance_test_runner --text_format_failure_list .cache/protobuf-v3.21.12/conformance/text_format_failure_list_cpp.txt .cache/protobuf-v3.21.12-build/conformance_cpp
+.cache/protobuf-v3.21.12-build/conformance_test_runner build_cpp26/iguana_conformance
+.cache/protobuf-v3.21.12-build/conformance_test_runner --enforce_recommended build_cpp26/iguana_conformance
+```
+
+最终验证结果：
+
+- `cmake --build build_cpp26 -j2`：通过，普通目标和 `_cpp26` 目标均完成构建。
+- `cmake --build build_cpp26 --target test_proto -j2`：通过，使用 `protoc 3.21.12` 生成的 C++ fixture。
+- `ctest --test-dir build_cpp26 --output-on-failure`：重新配置后通过，`_cpp26` 目标通过 build rpath 找到 GCC 16 libstdc++，`test_json_files_cpp26` 通过固定 CTest 工作目录读取源码树 `data/`。
+- `LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_pb`：11/11 test cases、268/268 assertions 通过。
+- `LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_xml`：20/20 test cases、227/227 assertions 通过。
+- `LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_proto`：11/11 test cases、54/54 assertions 通过。
+- `LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_pb_cpp26`：12/12 test cases、369/369 assertions 通过。
+- `LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/test_xml_cpp26`：22/22 test cases、236/236 assertions 通过。
+- `LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ctest --test-dir build_cpp26 --output-on-failure`：21/21 通过。
+- 官方 `conformance_test_runner + conformance_cpp` reference：带 `text_format_failure_list_cpp.txt` 后通过。Binary/JSON suite 为 1989 successes、0 unexpected failures；Text-format suite 为 100 successes、20 expected failures、0 unexpected failures。临时 `.cache/protobuf-v3.21.12*` 源码和构建目录位于 `.cache/`，已被 `.gitignore` 忽略。
+- 官方 `conformance_test_runner + build_cpp26/iguana_conformance --enforce_recommended`：通过。Binary/JSON suite 为 651 successes、1366 skipped、0 expected failures、0 unexpected failures；Text-format suite 为 0 successes、120 skipped、0 expected failures、0 unexpected failures。
+- `LD_LIBRARY_PATH=/opt/gcc-16.1.0/lib64 ./build_cpp26/pb_benchmark 100000`：当前机器结果如下：
+  - many serialize：iguana/protobuf `0.568x`
+  - many deserialize：`0.810x`
+  - simple serialize：`0.343x`
+  - simple deserialize：`0.395x`
+  - monster serialize：`0.535x`
+  - monster deserialize：`0.368x`
+  - int32 deserialize：`0.522x`
+  - 比值小于 1 表示 iguana 更快；本次样本中 iguana 全部快于官方 C++ protobuf runtime。
+- `git diff --check`：通过，无 whitespace/error 输出。
+
+注意：`iguana_conformance` 目前是 wire-only protobuf-output 验收 testee。它跳过 JSON/text/proto2 以及非 protobuf output，不等同于完整 protobuf conformance；binary/protobuf-output 子集已在 `--enforce_recommended` 下通过。
+
+构建过程中仍能看到既有 warning，主要来自 `frozen/string.h` 的 C++23 literal suffix 提示、JSON optional/variant 路径的 `maybe-uninitialized` 提示，以及 dynamic 测试里的 `stringop-overflow` 提示。本轮没有扩大范围去修这些历史 warning。
diff --git a/lang/struct_pb_intro.md b/lang/struct_pb_intro.md
--- a/lang/struct_pb_intro.md
+++ b/lang/struct_pb_intro.md
@@ -53,6 +53,142 @@ message nest {
 }
 ```
 
+### 自定义字段号
+
+默认情况下，字段号按 C++ 成员声明顺序从 1 开始分配。需要和已有 `.proto` 互通时，应显式指定字段号。旧路径/非 C++26 路径可以继续使用 `YLT_REFL_PB`：
+
+```cpp
+struct account {
+  std::string name;
+  int32_t age;
+  std::vector<std::string> emails;
+};
+
+YLT_REFL_PB(account, (name, 10), (age, 20), (emails, 9));
+```
+
+启用 C++26 静态反射后，优先使用后文的 `[[= iguana::pb_field(N)]]` 注解；该路径从字段注解读取 protobuf metadata，不依赖 `YLT_REFL_PB`。
+
+也可以使用 helper 形式描述 proto3 wire schema。helper 形式适合需要 `bytes`、zigzag、fixed、optional、oneof、well-known type 或 unknown fields 的场景：
+
+```cpp
+struct event_msg {
+  int32_t id{};
+  std::string payload;
+  int32_t delta{};
+  uint32_t checksum{};
+  std::chrono::system_clock::time_point created_at{};
+  std::chrono::nanoseconds timeout{};
+  std::optional<int32_t> retry_count;
+  std::variant<std::monostate, int32_t, std::string> result;
+  std::string unknown;
+};
+
+inline auto get_members_impl(event_msg*) {
+  return iguana::pb_members(
+      iguana::pb_field<&event_msg::id, 1>("id"),
+      iguana::pb_bytes_field<&event_msg::payload, 3>("payload"),
+      iguana::pb_zigzag_field<&event_msg::delta, 5>("delta"),
+      iguana::pb_optional_field<&event_msg::retry_count, 6>("retry_count"),
+      iguana::pb_fixed_field<&event_msg::checksum, 7>("checksum"),
+      iguana::as_timestamp_field<&event_msg::created_at, 8>("created_at"),
+      iguana::as_duration_field<&event_msg::timeout, 9>("timeout"),
+      iguana::pb_oneof_field<&event_msg::result, 10, 12>("result"),
+      iguana::pb_unknown_fields_field<&event_msg::unknown>("unknown"));
+}
+```
+
+helper 接口说明：
+
+| helper | 用途 |
+| --- | --- |
+| `pb_members(...)` | 在 `get_members_impl(T*)` 中返回 protobuf descriptor tuple。 |
+| `pb_field<&T::field, N>("name")` | 指定 protobuf 字段号和 schema 名称。 |
+| `pb_bytes_field` | 生成 `bytes`；C++ 字段是 `std::string` 或 `std::string_view`，也支持 optional/vector 外层。 |
+| `pb_zigzag_field` | 生成 `sint32` 或 `sint64`；C++ 字段仍是 `int32_t` 或 `int64_t`，也支持 optional/vector 外层。 |
+| `pb_fixed_field` | 为 32/64-bit 整数字段生成 `fixed32`、`fixed64`、`sfixed32` 或 `sfixed64`，也支持 optional/vector 外层。 |
+| `pb_optional_field` | 生成 proto3 `optional`；C++ 字段必须是 `std::optional<T>`。 |
+| `pb_timestamp_field` / `as_timestamp_field` | 把 `std::chrono::system_clock::time_point` 按 `google.protobuf.Timestamp` 编码，也支持 optional/vector 外层。 |
+| `pb_duration_field` / `as_duration_field` | 把 `std::chrono::nanoseconds` 按 `google.protobuf.Duration` 编码，也支持 optional/vector 外层。 |
+| `pb_oneof_field<&T::field, Ns...>("name")` | 把 `std::variant<std::monostate, ...>` 的非 `monostate` 备选项映射到 oneof 字段号。 |
+| `pb_unknown_fields_field<&T::field>()` | 用单个 `std::string` 字段保留未知 protobuf wire bytes，并在再次序列化时原样写回。 |
+
+显式 wrapper 类型 `iguana::pb_timestamp` 和 `iguana::pb_duration` 仍可用于直接保存 wire-shaped well-known type；业务代码通常优先使用 chrono 字段加 `pb_timestamp_field/as_timestamp_field` 或 `pb_duration_field/as_duration_field`。
+
+需要组合多个 protobuf option 时使用 `pb_field_ex`：
+
+```cpp
+iguana::pb_field_ex<&event_msg::retry_count, 6>(
+    "retry_count", iguana::pb_optional, iguana::pb_zigzag);
+```
+
+`pb_field_ex` 支持组合的 option 包括 `pb_bytes`、`pb_zigzag`、`pb_fixed`、`pb_optional`、`pb_as_timestamp/as_timestamp` 和 `pb_as_duration/as_duration`。`pb_zigzag` 不能和 `pb_fixed` 同时使用，`pb_as_timestamp` 不能和 `pb_as_duration` 同时使用。
+
+### C++26 注解写法
+
+启用 C++26 静态反射后，可以直接把 protobuf metadata 写成字段注解，不需要 `YLT_REFL_PB`。本轮 C++26 测试构建使用 GCC 16.1 和 `-std=gnu++26 -freflection`。
+
+```cpp
+struct event_msg26 {
+  [[= iguana::pb_field(1)]] int32_t id{};
+
+  [[= iguana::pb_field(3)]]
+  [[= iguana::pb_bytes]]
+  std::string payload;
+
+  [[= iguana::pb_field(5)]]
+  [[= iguana::pb_zigzag]]
+  int32_t delta{};
+
+  [[= iguana::pb_field(6)]]
+  [[= iguana::pb_optional]]
+  std::optional<int32_t> retry_count;
+
+  [[= iguana::pb_field(7)]]
+  [[= iguana::pb_fixed]]
+  uint32_t checksum{};
+
+  [[= iguana::pb_field(8)]]
+  [[= iguana::as_timestamp]]
+  std::chrono::system_clock::time_point created_at{};
+
+  [[= iguana::pb_field(9)]]
+  [[= iguana::as_duration]]
+  std::chrono::nanoseconds timeout{};
+
+  [[= iguana::pb_oneof<10, 12>]]
+  std::variant<std::monostate, int32_t, std::string> result;
+
+  [[= iguana::pb_unknown_fields]]
+  std::string unknown;
+};
+```
+
+当前支持的 proto3 wire metadata 包括：自定义字段号、`bytes`、`sint32/sint64` zigzag、fixed/sfixed、explicit optional presence、oneof、`google.protobuf.Timestamp`、`google.protobuf.Duration`、unknown fields 保留。repeated primitive 读取端同时接受 packed、unpacked、多 packed chunk 和混合编码；写入端按 proto3 默认规则输出 packed。
+
+C++26 注解和 helper 的含义一一对应：
+
+| C++26 注解 | 对应 helper / 说明 |
+| --- | --- |
+| `[[= iguana::pb_field(N)]]` | 对应 `pb_field<&T::field, N>`，指定字段号；字段号必须在 `[1, 2^29 - 1]`，且不能落入 `[19000, 19999]`。 |
+| `[[= iguana::pb_bytes]]` | 对应 `pb_bytes_field`，字段类型限制同 helper。 |
+| `[[= iguana::pb_zigzag]]` | 对应 `pb_zigzag_field`，支持 `int32_t/int64_t` 及 optional/vector 外层。 |
+| `[[= iguana::pb_fixed]]` | 对应 `pb_fixed_field`，支持 32/64-bit 整数及 optional/vector 外层。 |
+| `[[= iguana::pb_optional]]` | 对应 `pb_optional_field`，字段必须是 `std::optional<T>`。 |
+| `[[= iguana::pb_oneof<N...>]]` / `[[= iguana::oneof<N...>]]` | 对应 `pb_oneof_field`，字段必须是 `std::variant<std::monostate, ...>`。 |
+| `[[= iguana::as_timestamp]]` / `[[= iguana::pb_as_timestamp]]` | 对应 `as_timestamp_field/pb_timestamp_field`。 |
+| `[[= iguana::as_duration]]` / `[[= iguana::pb_as_duration]]` | 对应 `as_duration_field/pb_duration_field`。 |
+| `[[= iguana::pb_unknown_fields]]` | 对应 `pb_unknown_fields_field`；每个 message 最多一个，字段必须是 `std::string`。 |
+
+### 生成 proto schema
+
+```cpp
+std::string schema;
+iguana::to_proto<event_msg>(schema, "demo");
+```
+
+`to_proto` 用于生成结构体对应的 proto3 schema 视图，便于 review 字段号和 wire 类型；它不是完整的 `.proto` 编译器。
+
 ## 动态反射
 特性：
 - 根据对象名称创建实例；
@@ -155,13 +291,12 @@ oneof -> `std::variant <...>`
 | oneof       | std::variant<...> |                    |                                    |
 
 ## 约束
-- 目前还只支持proto3，不支持proto2；
-- 目前还没支持反射；
-- 还没支持unkonwn字段；
-- struct_pb 结构体必须派生于base_impl
+- 当前 protobuf 能力定位为 proto3 binary wire-only，不支持 proto2 required、extension、自定义 option、service，也不覆盖 proto3 JSON mapping 或 text format；
+- 普通 `to_pb` / `from_pb` 不要求结构体派生 `base_impl`；只有“根据对象名称创建实例”的动态反射功能需要派生 `iguana::base_impl`；
+- unknown fields 需要显式声明 `pb_unknown_fields_field` 或 C++26 `[[= iguana::pb_unknown_fields]]` 字段后才会保留；
+- official conformance 当前接入的是 proto3 binary/protobuf-output 子集，JSON/text/proto2 和非 protobuf output 会跳过。
 
 ## roadmap
 - 支持proto2；
-- 支持反射；
-- 支持unkonwn字段；
-- 去除struct_pb 结构体必须派生于base_impl的约束；
+- 扩展 proto3 JSON mapping 和 text format；
+- 扩展 descriptor/custom option/service 等更完整 `.proto` 语义；
diff --git a/scripts/check-clang-format.sh b/scripts/check-clang-format.sh
new file mode 100644
--- /dev/null
+++ b/scripts/check-clang-format.sh
@@ -0,0 +1,33 @@
+#!/usr/bin/env bash
+set -euo pipefail
+
+base_ref="${1:-HEAD}"
+clang_format="${CLANG_FORMAT:-clang-format-18}"
+git_clang_format="${GIT_CLANG_FORMAT:-git-clang-format-18}"
+
+if ! command -v "$clang_format" >/dev/null 2>&1; then
+  echo "error: $clang_format not found; install clang-format-18 or set CLANG_FORMAT." >&2
+  exit 127
+fi
+
+if ! command -v "$git_clang_format" >/dev/null 2>&1; then
+  echo "error: $git_clang_format not found; install clang-format-18 or set GIT_CLANG_FORMAT." >&2
+  exit 127
+fi
+
+set +e
+diff="$("$git_clang_format" --binary "$clang_format" --diff "$base_ref")"
+status=$?
+set -e
+
+if [[ $status -ne 0 && -z "$diff" ]]; then
+  exit "$status"
+fi
+
+if ! [[ "$diff" = "no modified files to format" ||
+  "$diff" = "clang-format did not modify any files" ]]; then
+  echo "The diff you sent is not formatted correctly."
+  echo "the suggested format is"
+  echo "$diff"
+  exit 1
+fi
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
