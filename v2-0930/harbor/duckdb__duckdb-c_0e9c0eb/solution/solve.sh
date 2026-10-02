#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.github/patches/extensions/sqlsmith/fix.patch b/.github/patches/extensions/sqlsmith/fix.patch
--- a/.github/patches/extensions/sqlsmith/fix.patch
+++ b/.github/patches/extensions/sqlsmith/fix.patch
@@ -27,19 +27,33 @@ index 72e8f5b..06fc74a 100644
  
  	return delete_statement;
 diff --git a/src/statement_simplifier.cpp b/src/statement_simplifier.cpp
-index 4602928..c3cf639 100644
+index 4602928..d728a1c 100644
 --- a/src/statement_simplifier.cpp
 +++ b/src/statement_simplifier.cpp
-@@ -10,6 +10,8 @@
+@@ -8,8 +8,11 @@
+ #include "duckdb/parser/expression/list.hpp"
+ #include "duckdb/parser/statement/delete_statement.hpp"
  #include "duckdb/parser/statement/insert_statement.hpp"
++#include "duckdb/parser/query_node/insert_query_node.hpp"
  #include "duckdb/parser/statement/prepare_statement.hpp"
  #include "duckdb/parser/statement/update_statement.hpp"
 +#include "duckdb/parser/query_node/update_query_node.hpp"
 +#include "duckdb/parser/query_node/delete_query_node.hpp"
  #include "duckdb/parser/statement/select_statement.hpp"
  #endif
  
-@@ -401,11 +403,11 @@ void StatementSimplifier::Simplify(InsertStatement &stmt) {
+@@ -395,17 +398,19 @@ void StatementSimplifier::Simplify(SelectStatement &stmt) {
+ }
+ 
+ void StatementSimplifier::Simplify(InsertStatement &stmt) {
+-	Simplify(stmt.cte_map);
+-	Simplify(*stmt.select_statement);
+-	SimplifyList(stmt.returning_list);
++	Simplify(stmt.node->cte_map);
++	if (stmt.node->select_statement) {
++		Simplify(*stmt.node->select_statement);
++	}
++	SimplifyList(stmt.node->returning_list);
  }
  
  void StatementSimplifier::Simplify(DeleteStatement &stmt) {
@@ -56,7 +70,7 @@ index 4602928..c3cf639 100644
  }
  
  void StatementSimplifier::Simplify(UpdateSetInfo &info) {
-@@ -432,11 +434,11 @@ void StatementSimplifier::Simplify(PrepareStatement &stmt) {
+@@ -432,11 +437,11 @@ void StatementSimplifier::Simplify(PrepareStatement &stmt) {
  }
  
  void StatementSimplifier::Simplify(UpdateStatement &stmt) {
diff --git a/extension/autocomplete/transformer/transform_insert.cpp b/extension/autocomplete/transformer/transform_insert.cpp
--- a/extension/autocomplete/transformer/transform_insert.cpp
+++ b/extension/autocomplete/transformer/transform_insert.cpp
@@ -2,35 +2,37 @@
 #include "ast/on_conflict_expression_target.hpp"
 #include "transformer/peg_transformer.hpp"
 #include "duckdb/parser/statement/insert_statement.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 
 namespace duckdb {
 
 unique_ptr<SQLStatement> PEGTransformerFactory::TransformInsertStatement(PEGTransformer &transformer,
                                                                          optional_ptr<ParseResult> parse_result) {
 	auto &list_pr = parse_result->Cast<ListParseResult>();
 	auto result = make_uniq<InsertStatement>();
+	auto &node = *result->node;
 	auto with_opt = list_pr.Child<OptionalParseResult>(0);
 	if (with_opt.HasResult()) {
-		result->cte_map = transformer.Transform<CommonTableExpressionMap>(with_opt.optional_result);
+		node.cte_map = transformer.Transform<CommonTableExpressionMap>(with_opt.optional_result);
 	}
 	auto or_action_opt = list_pr.Child<OptionalParseResult>(2);
 	auto insert_target = transformer.Transform<unique_ptr<BaseTableRef>>(list_pr.Child<ListParseResult>(4));
 	// TODO(Dtenwolde) What about the insert alias?
-	result->catalog = insert_target->catalog_name;
-	result->schema = insert_target->schema_name;
-	result->table = insert_target->table_name;
-	transformer.TransformOptional<InsertColumnOrder>(list_pr, 5, result->column_order);
-	transformer.TransformOptional<vector<string>>(list_pr, 6, result->columns);
+	node.catalog = insert_target->catalog_name;
+	node.schema = insert_target->schema_name;
+	node.table = insert_target->table_name;
+	transformer.TransformOptional<InsertColumnOrder>(list_pr, 5, node.column_order);
+	transformer.TransformOptional<vector<string>>(list_pr, 6, node.columns);
 	auto insert_values = transformer.Transform<InsertValues>(list_pr.Child<ListParseResult>(7));
-	if (!result->columns.empty() && insert_values.default_values) {
+	if (!node.columns.empty() && insert_values.default_values) {
 		throw ParserException(
 		    "You can not provide both a column list and DEFAULT VALUES, please remove one of the two");
 	}
 	if (insert_values.default_values) {
-		result->default_values = true;
+		node.default_values = true;
 	}
 	if (insert_values.select_statement) {
-		result->select_statement = std::move(insert_values.select_statement);
+		node.select_statement = std::move(insert_values.select_statement);
 	}
 	auto on_conflict_info = make_uniq<OnConflictInfo>();
 	auto on_conflict_clause = list_pr.Child<OptionalParseResult>(8);
@@ -41,14 +43,14 @@ unique_ptr<SQLStatement> PEGTransformerFactory::TransformInsertStatement(PEGTran
 			                      "the first if you want to have more granual control");
 		}
 		on_conflict_info = transformer.Transform<unique_ptr<OnConflictInfo>>(on_conflict_clause.optional_result);
-		result->on_conflict_info = std::move(on_conflict_info);
-		result->table_ref = std::move(insert_target);
+		node.on_conflict_info = std::move(on_conflict_info);
+		node.table_ref = std::move(insert_target);
 	} else if (or_action_opt.HasResult()) {
 		on_conflict_info->action_type = transformer.Transform<OnConflictAction>(or_action_opt.optional_result);
-		result->on_conflict_info = std::move(on_conflict_info);
-		result->table_ref = std::move(insert_target);
+		node.on_conflict_info = std::move(on_conflict_info);
+		node.table_ref = std::move(insert_target);
 	}
-	transformer.TransformOptional<vector<unique_ptr<ParsedExpression>>>(list_pr, 9, result->returning_list);
+	transformer.TransformOptional<vector<unique_ptr<ParsedExpression>>>(list_pr, 9, node.returning_list);
 	return std::move(result);
 }
 
diff --git a/src/common/enum_util.cpp b/src/common/enum_util.cpp
--- a/src/common/enum_util.cpp
+++ b/src/common/enum_util.cpp
@@ -4097,19 +4097,20 @@ const StringUtil::EnumStringLiteral *GetQueryNodeTypeValues() {
 		{ static_cast<uint32_t>(QueryNodeType::CTE_NODE), "CTE_NODE" },
 		{ static_cast<uint32_t>(QueryNodeType::STATEMENT_NODE), "STATEMENT_NODE" },
 		{ static_cast<uint32_t>(QueryNodeType::UPDATE_QUERY_NODE), "UPDATE_QUERY_NODE" },
-		{ static_cast<uint32_t>(QueryNodeType::DELETE_QUERY_NODE), "DELETE_QUERY_NODE" }
+		{ static_cast<uint32_t>(QueryNodeType::DELETE_QUERY_NODE), "DELETE_QUERY_NODE" },
+		{ static_cast<uint32_t>(QueryNodeType::INSERT_QUERY_NODE), "INSERT_QUERY_NODE" }
 	};
 	return values;
 }
 
 template<>
 const char* EnumUtil::ToChars<QueryNodeType>(QueryNodeType value) {
-	return StringUtil::EnumToString(GetQueryNodeTypeValues(), 8, "QueryNodeType", static_cast<uint32_t>(value));
+	return StringUtil::EnumToString(GetQueryNodeTypeValues(), 9, "QueryNodeType", static_cast<uint32_t>(value));
 }
 
 template<>
 QueryNodeType EnumUtil::FromString<QueryNodeType>(const char *value) {
-	return static_cast<QueryNodeType>(StringUtil::StringToEnum(GetQueryNodeTypeValues(), 8, "QueryNodeType", value));
+	return static_cast<QueryNodeType>(StringUtil::StringToEnum(GetQueryNodeTypeValues(), 9, "QueryNodeType", value));
 }
 
 const StringUtil::EnumStringLiteral *GetQueryResultMemoryTypeValues() {
diff --git a/src/common/symbols.cpp b/src/common/symbols.cpp
--- a/src/common/symbols.cpp
+++ b/src/common/symbols.cpp
@@ -29,6 +29,7 @@
 #include "duckdb/parser/query_node/set_operation_node.hpp"
 #include "duckdb/parser/query_node/update_query_node.hpp"
 #include "duckdb/parser/query_node/delete_query_node.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 #include "duckdb/parser/statement/list.hpp"
 #include "duckdb/parser/tableref/list.hpp"
 #include "duckdb/planner/expression/list.hpp"
@@ -64,6 +65,7 @@ template class unique_ptr<SelectNode>;
 template class unique_ptr<SetOperationNode>;
 template class unique_ptr<UpdateQueryNode>;
 template class unique_ptr<DeleteQueryNode>;
+template class unique_ptr<InsertQueryNode>;
 template class unique_ptr<ParsedExpression>;
 template class unique_ptr<CaseExpression>;
 template class unique_ptr<CastExpression>;
diff --git a/src/include/duckdb/parser/query_node.hpp b/src/include/duckdb/parser/query_node.hpp
--- a/src/include/duckdb/parser/query_node.hpp
+++ b/src/include/duckdb/parser/query_node.hpp
@@ -27,7 +27,8 @@ enum class QueryNodeType : uint8_t {
 	CTE_NODE = 5,
 	STATEMENT_NODE = 6,
 	UPDATE_QUERY_NODE = 7,
-	DELETE_QUERY_NODE = 8
+	DELETE_QUERY_NODE = 8,
+	INSERT_QUERY_NODE = 9
 };
 
 struct CommonTableExpressionInfo;
diff --git a/src/include/duckdb/parser/query_node/insert_query_node.hpp b/src/include/duckdb/parser/query_node/insert_query_node.hpp
new file mode 100644
--- /dev/null
+++ b/src/include/duckdb/parser/query_node/insert_query_node.hpp
@@ -0,0 +1,70 @@
+//===----------------------------------------------------------------------===//
+//                         DuckDB
+//
+// duckdb/parser/query_node/insert_query_node.hpp
+//
+//
+//===----------------------------------------------------------------------===//
+
+#pragma once
+
+#include "duckdb/parser/query_node.hpp"
+#include "duckdb/parser/tableref.hpp"
+#include "duckdb/parser/parsed_expression.hpp"
+
+namespace duckdb {
+class Serializer;
+class Deserializer;
+class OnConflictInfo;
+class ExpressionListRef;
+class SelectStatement;
+
+enum class InsertColumnOrder : uint8_t;
+
+//! InsertQueryNode represents an INSERT DML statement as a QueryNode,
+//! enabling serialization and use as a CTE body.
+class InsertQueryNode : public QueryNode {
+public:
+	static constexpr const QueryNodeType TYPE = QueryNodeType::INSERT_QUERY_NODE;
+
+public:
+	InsertQueryNode();
+
+	//! The select statement to insert from
+	unique_ptr<SelectStatement> select_statement;
+	//! Column names to insert into
+	vector<string> columns;
+
+	//! Table name to insert to
+	string table;
+	//! Schema name to insert to
+	string schema;
+	//! The catalog name to insert to
+	string catalog;
+
+	//! keep track of optional returningList if statement contains a RETURNING keyword
+	vector<unique_ptr<ParsedExpression>> returning_list;
+
+	unique_ptr<OnConflictInfo> on_conflict_info;
+	unique_ptr<TableRef> table_ref;
+
+	//! Whether or not this a DEFAULT VALUES
+	bool default_values = false;
+
+	//! INSERT BY POSITION or INSERT BY NAME
+	InsertColumnOrder column_order;
+
+public:
+	string ToString() const override;
+	bool Equals(const QueryNode *other) const override;
+	unique_ptr<QueryNode> Copy() const override;
+
+	void Serialize(Serializer &serializer) const override;
+	static unique_ptr<QueryNode> Deserialize(Deserializer &deserializer);
+
+	//! If the INSERT statement is inserted DIRECTLY from a values list (i.e. INSERT INTO tbl VALUES (...)) this returns
+	//! the expression list Otherwise, this returns NULL
+	optional_ptr<ExpressionListRef> GetValuesList() const;
+};
+
+} // namespace duckdb
diff --git a/src/include/duckdb/parser/query_node/list.hpp b/src/include/duckdb/parser/query_node/list.hpp
--- a/src/include/duckdb/parser/query_node/list.hpp
+++ b/src/include/duckdb/parser/query_node/list.hpp
@@ -5,3 +5,4 @@
 #include "duckdb/parser/query_node/statement_node.hpp"
 #include "duckdb/parser/query_node/update_query_node.hpp"
 #include "duckdb/parser/query_node/delete_query_node.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
diff --git a/src/include/duckdb/parser/statement/insert_statement.hpp b/src/include/duckdb/parser/statement/insert_statement.hpp
--- a/src/include/duckdb/parser/statement/insert_statement.hpp
+++ b/src/include/duckdb/parser/statement/insert_statement.hpp
@@ -16,6 +16,10 @@
 namespace duckdb {
 class ExpressionListRef;
 class UpdateSetInfo;
+class Serializer;
+class Deserializer;
+class InsertQueryNode;
+
 
 enum class OnConflictAction : uint8_t {
 	THROW,
@@ -32,6 +36,12 @@ class OnConflictInfo {
 
 public:
 	unique_ptr<OnConflictInfo> Copy() const;
+	static bool Equals(const unique_ptr<OnConflictInfo> &left, const unique_ptr<OnConflictInfo> &right);
+
+	void Serialize(Serializer &serializer) const;
+	static unique_ptr<OnConflictInfo> Deserialize(Deserializer &deserializer);
+
+	static string ActionToString(OnConflictAction action);
 
 public:
 	OnConflictAction action_type;
@@ -53,39 +63,12 @@ class InsertStatement : public SQLStatement {
 public:
 	InsertStatement();
 
-	//! The select statement to insert from
-	unique_ptr<SelectStatement> select_statement;
-	//! Column names to insert into
-	vector<string> columns;
-
-	//! Table name to insert to
-	string table;
-	//! Schema name to insert to
-	string schema;
-	//! The catalog name to insert to
-	string catalog;
-
-	//! keep track of optional returningList if statement contains a RETURNING keyword
-	vector<unique_ptr<ParsedExpression>> returning_list;
-
-	unique_ptr<OnConflictInfo> on_conflict_info;
-	unique_ptr<TableRef> table_ref;
-
-	//! CTEs
-	CommonTableExpressionMap cte_map;
-
-	//! Whether or not this a DEFAULT VALUES
-	bool default_values = false;
-
-	//! INSERT BY POSITION or INSERT BY NAME
-	InsertColumnOrder column_order = InsertColumnOrder::INSERT_BY_POSITION;
+	unique_ptr<InsertQueryNode> node;
 
 protected:
 	InsertStatement(const InsertStatement &other);
 
 public:
-	static string OnConflictActionToString(OnConflictAction action);
-
 	string ToString() const override;
 	unique_ptr<SQLStatement> Copy() const override;
 
diff --git a/src/include/duckdb/parser/tokens.hpp b/src/include/duckdb/parser/tokens.hpp
--- a/src/include/duckdb/parser/tokens.hpp
+++ b/src/include/duckdb/parser/tokens.hpp
@@ -56,6 +56,7 @@ class CTENode;
 class StatementNode;
 class UpdateQueryNode;
 class DeleteQueryNode;
+class InsertQueryNode;
 
 //===--------------------------------------------------------------------===//
 // Expressions
diff --git a/src/include/duckdb/planner/binder.hpp b/src/include/duckdb/planner/binder.hpp
--- a/src/include/duckdb/planner/binder.hpp
+++ b/src/include/duckdb/planner/binder.hpp
@@ -440,6 +440,7 @@ class Binder : public enable_shared_from_this<Binder> {
 	BoundStatement BindNode(RecursiveCTENode &node);
 	BoundStatement BindNode(QueryNode &node);
 	BoundStatement BindNode(StatementNode &node);
+	BoundStatement BindNode(InsertQueryNode &node);
 	BoundStatement BindNode(UpdateQueryNode &node);
 	BoundStatement BindNode(DeleteQueryNode &node);
 
@@ -552,7 +553,7 @@ class Binder : public enable_shared_from_this<Binder> {
 	                          vector<LogicalIndex> &named_column_map, vector<LogicalType> &expected_types,
 	                          IndexVector<idx_t, PhysicalIndex> &column_index_map);
 	void TryReplaceDefaultExpression(unique_ptr<ParsedExpression> &expr, const ColumnDefinition &column);
-	void ExpandDefaultInValuesList(InsertStatement &stmt, TableCatalogEntry &table,
+	void ExpandDefaultInValuesList(InsertQueryNode &node, TableCatalogEntry &table,
 	                               optional_ptr<ExpressionListRef> values_list,
 	                               const vector<LogicalIndex> &named_column_map);
 	unique_ptr<BoundMergeIntoAction> BindMergeAction(LogicalMergeInto &merge_into, TableCatalogEntry &table,
@@ -562,7 +563,7 @@ class Binder : public enable_shared_from_this<Binder> {
 	                                                 const vector<BindingAlias> &source_aliases,
 	                                                 const vector<string> &source_names);
 
-	unique_ptr<MergeIntoStatement> GenerateMergeInto(InsertStatement &stmt, TableCatalogEntry &table);
+	unique_ptr<MergeIntoStatement> GenerateMergeInto(InsertQueryNode &node, TableCatalogEntry &table);
 
 	static void CheckInsertColumnCountMismatch(idx_t expected_columns, idx_t result_columns, bool columns_provided,
 	                                           const string &tname);
diff --git a/src/include/duckdb/storage/serialization/query_node.json b/src/include/duckdb/storage/serialization/query_node.json
--- a/src/include/duckdb/storage/serialization/query_node.json
+++ b/src/include/duckdb/storage/serialization/query_node.json
@@ -257,5 +257,69 @@
         "type": "vector<ParsedExpression*>"
       }
     ]
+  },
+  {
+    "class": "InsertQueryNode",
+    "base": "QueryNode",
+    "enum": "INSERT_QUERY_NODE",
+    "includes": [
+      "duckdb/parser/query_node/insert_query_node.hpp",
+      "duckdb/parser/statement/insert_statement.hpp",
+      "duckdb/parser/statement/select_statement.hpp"
+    ],
+    "members": [
+      {
+        "id": 200,
+        "name": "select_statement",
+        "type": "SelectStatement*"
+      },
+      {
+        "id": 201,
+        "name": "columns",
+        "type": "vector<string>"
+      },
+      {
+        "id": 202,
+        "name": "table",
+        "type": "string"
+      },
+      {
+        "id": 203,
+        "name": "schema",
+        "type": "string"
+      },
+      {
+        "id": 204,
+        "name": "catalog",
+        "type": "string"
+      },
+      {
+        "id": 205,
+        "name": "returning_list",
+        "type": "vector<ParsedExpression*>"
+      },
+      {
+        "id": 206,
+        "name": "on_conflict_info",
+        "type": "OnConflictInfo*"
+      },
+      {
+        "id": 207,
+        "name": "table_ref",
+        "type": "TableRef*"
+      },
+      {
+        "id": 208,
+        "name": "default_values",
+        "type": "bool",
+        "default": "false"
+      },
+      {
+        "id": 209,
+        "name": "column_order",
+        "type": "InsertColumnOrder",
+        "default": "InsertColumnOrder::INSERT_BY_POSITION"
+      }
+    ]
   }
 ]
diff --git a/src/include/duckdb/storage/serialization/statement.json b/src/include/duckdb/storage/serialization/statement.json
--- a/src/include/duckdb/storage/serialization/statement.json
+++ b/src/include/duckdb/storage/serialization/statement.json
@@ -39,5 +39,33 @@
         "type": "vector<ParsedExpression*>"
       }
     ]
+  },
+  {
+    "class": "OnConflictInfo",
+    "includes": [
+      "duckdb/parser/statement/insert_statement.hpp"
+    ],
+    "members": [
+      {
+        "id": 100,
+        "name": "action_type",
+        "type": "OnConflictAction"
+      },
+      {
+        "id": 101,
+        "name": "indexed_columns",
+        "type": "vector<string>"
+      },
+      {
+        "id": 102,
+        "name": "set_info",
+        "type": "UpdateSetInfo*"
+      },
+      {
+        "id": 103,
+        "name": "condition",
+        "type": "ParsedExpression*"
+      }
+    ]
   }
 ]
diff --git a/src/main/appender.cpp b/src/main/appender.cpp
--- a/src/main/appender.cpp
+++ b/src/main/appender.cpp
@@ -18,6 +18,7 @@
 #include "duckdb/parser/tableref/column_data_ref.hpp"
 #include "duckdb/parser/parser.hpp"
 #include "duckdb/parser/statement/insert_statement.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 #include "duckdb/parser/statement/delete_statement.hpp"
 #include "duckdb/parser/query_node/delete_query_node.hpp"
 #include "duckdb/parser/statement/update_statement.hpp"
@@ -447,7 +448,7 @@ unique_ptr<TableRef> BaseAppender::GetColumnDataTableRef(ColumnDataCollection &c
 CommonTableExpressionMap &GetCTEMap(SQLStatement &statement) {
 	switch (statement.type) {
 	case StatementType::INSERT_STATEMENT:
-		return statement.Cast<InsertStatement>().cte_map;
+		return statement.Cast<InsertStatement>().node->cte_map;
 	case StatementType::DELETE_STATEMENT:
 		return statement.Cast<DeleteStatement>().node->cte_map;
 	case StatementType::UPDATE_STATEMENT:
diff --git a/src/main/relation/insert_relation.cpp b/src/main/relation/insert_relation.cpp
--- a/src/main/relation/insert_relation.cpp
+++ b/src/main/relation/insert_relation.cpp
@@ -1,5 +1,6 @@
 #include "duckdb/main/relation/insert_relation.hpp"
 #include "duckdb/parser/statement/insert_statement.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 #include "duckdb/parser/statement/select_statement.hpp"
 #include "duckdb/parser/parsed_data/create_table_info.hpp"
 #include "duckdb/planner/binder.hpp"
@@ -21,13 +22,14 @@ InsertRelation::InsertRelation(shared_ptr<Relation> child_p, string catalog_name
 
 BoundStatement InsertRelation::Bind(Binder &binder) {
 	InsertStatement stmt;
+	auto &node = *stmt.node;
 	auto select = make_uniq<SelectStatement>();
 	select->node = child->GetQueryNode();
 
-	stmt.catalog = catalog_name;
-	stmt.schema = schema_name;
-	stmt.table = table_name;
-	stmt.select_statement = std::move(select);
+	node.catalog = catalog_name;
+	node.schema = schema_name;
+	node.table = table_name;
+	node.select_statement = std::move(select);
 	return binder.Bind(stmt.Cast<SQLStatement>());
 }
 
diff --git a/src/parser/parsed_expression_iterator.cpp b/src/parser/parsed_expression_iterator.cpp
--- a/src/parser/parsed_expression_iterator.cpp
+++ b/src/parser/parsed_expression_iterator.cpp
@@ -8,6 +8,8 @@
 #include "duckdb/parser/query_node/set_operation_node.hpp"
 #include "duckdb/parser/query_node/update_query_node.hpp"
 #include "duckdb/parser/query_node/delete_query_node.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
+#include "duckdb/parser/statement/insert_statement.hpp"
 #include "duckdb/parser/tableref/list.hpp"
 
 namespace duckdb {
@@ -344,6 +346,30 @@ void ParsedExpressionIterator::EnumerateQueryNodeChildren(
 		}
 		break;
 	}
+	case QueryNodeType::INSERT_QUERY_NODE: {
+		auto &ins_node = node.Cast<InsertQueryNode>();
+		if (ins_node.select_statement) {
+			EnumerateQueryNodeChildren(*ins_node.select_statement->node, expr_callback, ref_callback);
+		}
+		if (ins_node.table_ref) {
+			EnumerateTableRefChildren(*ins_node.table_ref, expr_callback, ref_callback);
+		}
+		for (auto &expr : ins_node.returning_list) {
+			expr_callback(expr);
+		}
+		if (ins_node.on_conflict_info && ins_node.on_conflict_info->set_info) {
+			for (auto &expr : ins_node.on_conflict_info->set_info->expressions) {
+				expr_callback(expr);
+			}
+			if (ins_node.on_conflict_info->set_info->condition) {
+				expr_callback(ins_node.on_conflict_info->set_info->condition);
+			}
+		}
+		if (ins_node.on_conflict_info && ins_node.on_conflict_info->condition) {
+			expr_callback(ins_node.on_conflict_info->condition);
+		}
+		break;
+	}
 	default:
 		throw NotImplementedException("QueryNode type not implemented for traversal");
 	}
diff --git a/src/parser/query_node/CMakeLists.txt b/src/parser/query_node/CMakeLists.txt
--- a/src/parser/query_node/CMakeLists.txt
+++ b/src/parser/query_node/CMakeLists.txt
@@ -7,7 +7,8 @@ add_library_unity(
   set_operation_node.cpp
   statement_node.cpp
   update_query_node.cpp
-  delete_query_node.cpp)
+  delete_query_node.cpp
+  insert_query_node.cpp)
 set(ALL_OBJECT_FILES
     ${ALL_OBJECT_FILES} $<TARGET_OBJECTS:duckdb_query_node>
     PARENT_SCOPE)
diff --git a/src/parser/query_node/insert_query_node.cpp b/src/parser/query_node/insert_query_node.cpp
new file mode 100644
--- /dev/null
+++ b/src/parser/query_node/insert_query_node.cpp
@@ -0,0 +1,227 @@
+#include "duckdb/parser/query_node/insert_query_node.hpp"
+#include "duckdb/parser/statement/insert_statement.hpp"
+#include "duckdb/parser/keyword_helper.hpp"
+#include "duckdb/common/string_util.hpp"
+#include "duckdb/parser/query_node/select_node.hpp"
+#include "duckdb/parser/tableref/expressionlistref.hpp"
+
+namespace duckdb {
+
+InsertQueryNode::InsertQueryNode()
+    : QueryNode(QueryNodeType::INSERT_QUERY_NODE), schema(DEFAULT_SCHEMA), catalog(INVALID_CATALOG),
+      column_order(InsertColumnOrder::INSERT_BY_POSITION) {
+}
+
+string InsertQueryNode::ToString() const {
+	bool or_replace_shorthand_set = false;
+	string result;
+
+	result = cte_map.ToString();
+	result += "INSERT";
+	if (on_conflict_info && on_conflict_info->action_type == OnConflictAction::REPLACE) {
+		or_replace_shorthand_set = true;
+		result += " OR REPLACE";
+	}
+	result += " INTO ";
+	if (!catalog.empty()) {
+		result += KeywordHelper::WriteOptionallyQuoted(catalog) + ".";
+	}
+	if (!schema.empty()) {
+		result += KeywordHelper::WriteOptionallyQuoted(schema) + ".";
+	}
+	result += KeywordHelper::WriteOptionallyQuoted(table);
+	// Write the (optional) alias of the insert target
+	if (table_ref && !table_ref->alias.empty()) {
+		result += StringUtil::Format(" AS %s", KeywordHelper::WriteOptionallyQuoted(table_ref->alias));
+	}
+	if (column_order == InsertColumnOrder::INSERT_BY_NAME) {
+		result += " BY NAME";
+	}
+	if (!columns.empty()) {
+		result += " (";
+		for (idx_t i = 0; i < columns.size(); i++) {
+			if (i > 0) {
+				result += ", ";
+			}
+			result += KeywordHelper::WriteOptionallyQuoted(columns[i]);
+		}
+		result += " )";
+	}
+	result += " ";
+	auto values_list = GetValuesList();
+	if (values_list) {
+		D_ASSERT(!default_values);
+		auto saved_alias = values_list->alias;
+		values_list->alias = string();
+		result += values_list->ToString();
+		values_list->alias = saved_alias;
+	} else if (select_statement) {
+		D_ASSERT(!default_values);
+		result += select_statement->ToString();
+	} else {
+		D_ASSERT(default_values);
+		result += "DEFAULT VALUES";
+	}
+	if (!or_replace_shorthand_set && on_conflict_info) {
+		auto &conflict_info = *on_conflict_info;
+		result += " ON CONFLICT ";
+		// (optional) conflict target
+		if (!conflict_info.indexed_columns.empty()) {
+			result += "(";
+			auto &cols = conflict_info.indexed_columns;
+			for (auto it = cols.begin(); it != cols.end();) {
+				result += StringUtil::Lower(*it);
+				if (++it != cols.end()) {
+					result += ", ";
+				}
+			}
+			result += " )";
+		}
+
+		// (optional) where clause
+		if (conflict_info.condition) {
+			result += " WHERE " + conflict_info.condition->ToString();
+		}
+		result += " " + OnConflictInfo::ActionToString(conflict_info.action_type);
+		if (conflict_info.set_info) {
+			D_ASSERT(conflict_info.action_type == OnConflictAction::UPDATE);
+			result += " SET ";
+			auto &set_info = *conflict_info.set_info;
+			D_ASSERT(set_info.columns.size() == set_info.expressions.size());
+			// SET <column_name> = <expression>
+			for (idx_t i = 0; i < set_info.columns.size(); i++) {
+				auto &column = set_info.columns[i];
+				auto &expr = set_info.expressions[i];
+				if (i) {
+					result += ", ";
+				}
+				result += StringUtil::Lower(column) + " = " + expr->ToString();
+			}
+			// (optional) where clause
+			if (set_info.condition) {
+				result += " WHERE " + set_info.condition->ToString();
+			}
+		}
+	}
+	if (!returning_list.empty()) {
+		result += " RETURNING ";
+		for (idx_t i = 0; i < returning_list.size(); i++) {
+			if (i > 0) {
+				result += ", ";
+			}
+			auto col = returning_list[i]->ToString();
+			if (!returning_list[i]->GetAlias().empty()) {
+				col +=
+				    StringUtil::Format(" AS %s", KeywordHelper::WriteOptionallyQuoted(returning_list[i]->GetAlias()));
+			}
+			result += col;
+		}
+	}
+	return result;
+}
+
+bool InsertQueryNode::Equals(const QueryNode *other_p) const {
+	if (this == other_p) {
+		return true;
+	}
+	if (!QueryNode::Equals(other_p)) {
+		return false;
+	}
+	auto &other = other_p->Cast<InsertQueryNode>();
+	if (table != other.table) {
+		return false;
+	}
+	if (schema != other.schema) {
+		return false;
+	}
+	if (catalog != other.catalog) {
+		return false;
+	}
+	if (columns != other.columns) {
+		return false;
+	}
+	if (default_values != other.default_values) {
+		return false;
+	}
+	if (column_order != other.column_order) {
+		return false;
+	}
+	if (!TableRef::Equals(table_ref, other.table_ref)) {
+		return false;
+	}
+	// compare select_statement
+	if (select_statement && other.select_statement) {
+		if (!select_statement->Equals(*other.select_statement)) {
+			return false;
+		}
+	} else if (select_statement || other.select_statement) {
+		return false;
+	}
+	if (!OnConflictInfo::Equals(on_conflict_info, other.on_conflict_info)) {
+		return false;
+	}
+	if (returning_list.size() != other.returning_list.size()) {
+		return false;
+	}
+	for (idx_t i = 0; i < returning_list.size(); i++) {
+		if (!ParsedExpression::Equals(returning_list[i], other.returning_list[i])) {
+			return false;
+		}
+	}
+	return true;
+}
+
+unique_ptr<QueryNode> InsertQueryNode::Copy() const {
+	auto result = make_uniq<InsertQueryNode>();
+	result->table = table;
+	result->schema = schema;
+	result->catalog = catalog;
+	result->columns = columns;
+	result->default_values = default_values;
+	result->column_order = column_order;
+	if (select_statement) {
+		result->select_statement = unique_ptr_cast<SQLStatement, SelectStatement>(select_statement->Copy());
+	}
+	for (auto &expr : returning_list) {
+		result->returning_list.push_back(expr->Copy());
+	}
+	if (table_ref) {
+		result->table_ref = table_ref->Copy();
+	}
+	if (on_conflict_info) {
+		result->on_conflict_info = on_conflict_info->Copy();
+	}
+	CopyProperties(*result);
+	return std::move(result);
+}
+
+optional_ptr<ExpressionListRef> InsertQueryNode::GetValuesList() const {
+	if (!select_statement) {
+		return nullptr;
+	}
+	if (select_statement->node->type != QueryNodeType::SELECT_NODE) {
+		return nullptr;
+	}
+	auto &node = select_statement->node->Cast<SelectNode>();
+	if (node.where_clause || node.qualify || node.having) {
+		return nullptr;
+	}
+	if (!node.cte_map.map.empty()) {
+		return nullptr;
+	}
+	if (!node.groups.grouping_sets.empty()) {
+		return nullptr;
+	}
+	if (node.aggregate_handling != AggregateHandling::STANDARD_HANDLING) {
+		return nullptr;
+	}
+	if (node.select_list.size() != 1 || node.select_list[0]->GetExpressionType() != ExpressionType::STAR) {
+		return nullptr;
+	}
+	if (!node.from_table || node.from_table->type != TableReferenceType::EXPRESSION_LIST) {
+		return nullptr;
+	}
+	return &node.from_table->Cast<ExpressionListRef>();
+}
+
+} // namespace duckdb
diff --git a/src/parser/statement/insert_statement.cpp b/src/parser/statement/insert_statement.cpp
--- a/src/parser/statement/insert_statement.cpp
+++ b/src/parser/statement/insert_statement.cpp
@@ -1,7 +1,5 @@
 #include "duckdb/parser/statement/insert_statement.hpp"
-#include "duckdb/parser/query_node/select_node.hpp"
-#include "duckdb/parser/tableref/expressionlistref.hpp"
-#include "duckdb/parser/statement/update_statement.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 
 namespace duckdb {
 
@@ -22,28 +20,36 @@ unique_ptr<OnConflictInfo> OnConflictInfo::Copy() const {
 	return unique_ptr<OnConflictInfo>(new OnConflictInfo(*this));
 }
 
-InsertStatement::InsertStatement()
-    : SQLStatement(StatementType::INSERT_STATEMENT), schema(DEFAULT_SCHEMA), catalog(INVALID_CATALOG) {
-}
-
-InsertStatement::InsertStatement(const InsertStatement &other)
-    : SQLStatement(other), select_statement(unique_ptr_cast<SQLStatement, SelectStatement>(
-                               other.select_statement ? other.select_statement->Copy() : nullptr)),
-      columns(other.columns), table(other.table), schema(other.schema), catalog(other.catalog),
-      default_values(other.default_values), column_order(other.column_order) {
-	cte_map = other.cte_map.Copy();
-	for (auto &expr : other.returning_list) {
-		returning_list.emplace_back(expr->Copy());
+bool OnConflictInfo::Equals(const unique_ptr<OnConflictInfo> &left, const unique_ptr<OnConflictInfo> &right) {
+	if (!left && !right) {
+		return true;
+	}
+	if (!left || !right) {
+		return false;
 	}
-	if (other.table_ref) {
-		table_ref = other.table_ref->Copy();
+	if (left->action_type != right->action_type) {
+		return false;
 	}
-	if (other.on_conflict_info) {
-		on_conflict_info = other.on_conflict_info->Copy();
+	if (left->indexed_columns != right->indexed_columns) {
+		return false;
 	}
+	if (!UpdateSetInfo::Equals(left->set_info, right->set_info)) {
+		return false;
+	}
+	if (!ParsedExpression::Equals(left->condition, right->condition)) {
+		return false;
+	}
+	return true;
+}
+
+InsertStatement::InsertStatement() : SQLStatement(StatementType::INSERT_STATEMENT), node(make_uniq<InsertQueryNode>()) {
 }
 
-string InsertStatement::OnConflictActionToString(OnConflictAction action) {
+InsertStatement::InsertStatement(const InsertStatement &other)
+    : SQLStatement(other), node(unique_ptr_cast<QueryNode, InsertQueryNode>(other.node->Copy())) {
+}
+
+string OnConflictInfo::ActionToString(OnConflictAction action) {
 	switch (action) {
 	case OnConflictAction::NOTHING:
 		return "DO NOTHING";
@@ -60,144 +66,15 @@ string InsertStatement::OnConflictActionToString(OnConflictAction action) {
 }
 
 string InsertStatement::ToString() const {
-	bool or_replace_shorthand_set = false;
-	string result;
-
-	result = cte_map.ToString();
-	result += "INSERT";
-	if (on_conflict_info && on_conflict_info->action_type == OnConflictAction::REPLACE) {
-		or_replace_shorthand_set = true;
-		result += " OR REPLACE";
-	}
-	result += " INTO ";
-	if (!catalog.empty()) {
-		result += KeywordHelper::WriteOptionallyQuoted(catalog) + ".";
-	}
-	if (!schema.empty()) {
-		result += KeywordHelper::WriteOptionallyQuoted(schema) + ".";
-	}
-	result += KeywordHelper::WriteOptionallyQuoted(table);
-	// Write the (optional) alias of the insert target
-	if (table_ref && !table_ref->alias.empty()) {
-		result += StringUtil::Format(" AS %s", KeywordHelper::WriteOptionallyQuoted(table_ref->alias));
-	}
-	if (column_order == InsertColumnOrder::INSERT_BY_NAME) {
-		result += " BY NAME";
-	}
-	if (!columns.empty()) {
-		result += " (";
-		for (idx_t i = 0; i < columns.size(); i++) {
-			if (i > 0) {
-				result += ", ";
-			}
-			result += KeywordHelper::WriteOptionallyQuoted(columns[i]);
-		}
-		result += " )";
-	}
-	result += " ";
-	auto values_list = GetValuesList();
-	if (values_list) {
-		D_ASSERT(!default_values);
-		auto saved_alias = values_list->alias;
-		values_list->alias = string();
-		result += values_list->ToString();
-		values_list->alias = saved_alias;
-	} else if (select_statement) {
-		D_ASSERT(!default_values);
-		result += select_statement->ToString();
-	} else {
-		D_ASSERT(default_values);
-		result += "DEFAULT VALUES";
-	}
-	if (!or_replace_shorthand_set && on_conflict_info) {
-		auto &conflict_info = *on_conflict_info;
-		result += " ON CONFLICT ";
-		// (optional) conflict target
-		if (!conflict_info.indexed_columns.empty()) {
-			result += "(";
-			auto &columns = conflict_info.indexed_columns;
-			for (auto it = columns.begin(); it != columns.end();) {
-				result += StringUtil::Lower(*it);
-				if (++it != columns.end()) {
-					result += ", ";
-				}
-			}
-			result += " )";
-		}
-
-		// (optional) where clause
-		if (conflict_info.condition) {
-			result += " WHERE " + conflict_info.condition->ToString();
-		}
-		result += " " + OnConflictActionToString(conflict_info.action_type);
-		if (conflict_info.set_info) {
-			D_ASSERT(conflict_info.action_type == OnConflictAction::UPDATE);
-			result += " SET ";
-			auto &set_info = *conflict_info.set_info;
-			D_ASSERT(set_info.columns.size() == set_info.expressions.size());
-			// SET <column_name> = <expression>
-			for (idx_t i = 0; i < set_info.columns.size(); i++) {
-				auto &column = set_info.columns[i];
-				auto &expr = set_info.expressions[i];
-				if (i) {
-					result += ", ";
-				}
-				result += StringUtil::Lower(column) + " = " + expr->ToString();
-			}
-			// (optional) where clause
-			if (set_info.condition) {
-				result += " WHERE " + set_info.condition->ToString();
-			}
-		}
-	}
-	if (!returning_list.empty()) {
-		result += " RETURNING ";
-		for (idx_t i = 0; i < returning_list.size(); i++) {
-			if (i > 0) {
-				result += ", ";
-			}
-			auto column = returning_list[i]->ToString();
-			if (!returning_list[i]->GetAlias().empty()) {
-				column +=
-				    StringUtil::Format(" AS %s", KeywordHelper::WriteOptionallyQuoted(returning_list[i]->GetAlias()));
-			}
-			result += column;
-		}
-	}
-	return result;
+	return node->ToString();
 }
 
 unique_ptr<SQLStatement> InsertStatement::Copy() const {
 	return unique_ptr<InsertStatement>(new InsertStatement(*this));
 }
 
 optional_ptr<ExpressionListRef> InsertStatement::GetValuesList() const {
-	if (!select_statement) {
-		return nullptr;
-	}
-	if (select_statement->node->type != QueryNodeType::SELECT_NODE) {
-		return nullptr;
-	}
-	auto &node = select_statement->node->Cast<SelectNode>();
-	if (node.where_clause || node.qualify || node.having) {
-		return nullptr;
-	}
-	if (!node.cte_map.map.empty()) {
-		return nullptr;
-	}
-	if (!node.groups.grouping_sets.empty()) {
-		return nullptr;
-	}
-	if (node.aggregate_handling != AggregateHandling::STANDARD_HANDLING) {
-		return nullptr;
-	}
-	if (node.select_list.size() != 1 || node.select_list[0]->GetExpressionType() != ExpressionType::STAR) {
-		return nullptr;
-	}
-	if (!node.from_table || node.from_table->type != TableReferenceType::EXPRESSION_LIST) {
-		return nullptr;
-	}
-	return &node.from_table->Cast<ExpressionListRef>();
+	return node->GetValuesList();
 }
 
 } // namespace duckdb
diff --git a/src/parser/transform/statement/transform_insert.cpp b/src/parser/transform/statement/transform_insert.cpp
--- a/src/parser/transform/statement/transform_insert.cpp
+++ b/src/parser/transform/statement/transform_insert.cpp
@@ -1,4 +1,5 @@
 #include "duckdb/parser/statement/insert_statement.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 #include "duckdb/parser/tableref/expressionlistref.hpp"
 #include "duckdb/parser/transformer.hpp"
 
@@ -44,45 +45,46 @@ InsertColumnOrder Transformer::TransformColumnOrder(duckdb_libpgquery::PGInsertC
 
 unique_ptr<InsertStatement> Transformer::TransformInsert(duckdb_libpgquery::PGInsertStmt &stmt) {
 	auto result = make_uniq<InsertStatement>();
+	auto &node = *result->node;
 	if (stmt.withClause) {
-		TransformCTE(*PGPointerCast<duckdb_libpgquery::PGWithClause>(stmt.withClause), result->cte_map);
+		TransformCTE(*PGPointerCast<duckdb_libpgquery::PGWithClause>(stmt.withClause), node.cte_map);
 	}
 
 	// first check if there are any columns specified
 	if (stmt.cols) {
-		result->columns = TransformInsertColumns(*stmt.cols);
+		node.columns = TransformInsertColumns(*stmt.cols);
 	}
 
 	// Grab and transform the returning columns from the parser.
 	if (stmt.returningList) {
-		TransformExpressionList(*stmt.returningList, result->returning_list);
+		TransformExpressionList(*stmt.returningList, node.returning_list);
 	}
 	if (stmt.selectStmt) {
-		result->select_statement = TransformSelectStmt(*stmt.selectStmt, false);
+		node.select_statement = TransformSelectStmt(*stmt.selectStmt, false);
 	} else {
-		result->default_values = true;
+		node.default_values = true;
 	}
 
 	auto qname = TransformQualifiedName(*stmt.relation);
-	result->table = qname.name;
-	result->schema = qname.schema;
+	node.table = qname.name;
+	node.schema = qname.schema;
 
 	if (stmt.onConflictClause) {
 		if (stmt.onConflictAlias != duckdb_libpgquery::PG_ONCONFLICT_ALIAS_NONE) {
 			// OR REPLACE | OR IGNORE are shorthands for the ON CONFLICT clause
 			throw ParserException("You can not provide both OR REPLACE|IGNORE and an ON CONFLICT clause, please remove "
 			                      "the first if you want to have more granual control");
 		}
-		result->on_conflict_info = TransformOnConflictClause(stmt.onConflictClause, result->schema);
-		result->table_ref = TransformRangeVar(*stmt.relation);
+		node.on_conflict_info = TransformOnConflictClause(stmt.onConflictClause, node.schema);
+		node.table_ref = TransformRangeVar(*stmt.relation);
 	}
 	if (stmt.onConflictAlias != duckdb_libpgquery::PG_ONCONFLICT_ALIAS_NONE) {
 		D_ASSERT(!stmt.onConflictClause);
-		result->on_conflict_info = DummyOnConflictClause(stmt.onConflictAlias, result->schema);
-		result->table_ref = TransformRangeVar(*stmt.relation);
+		node.on_conflict_info = DummyOnConflictClause(stmt.onConflictAlias, node.schema);
+		node.table_ref = TransformRangeVar(*stmt.relation);
 	}
-	result->column_order = TransformColumnOrder(stmt.insert_column_order);
-	result->catalog = qname.catalog;
+	node.column_order = TransformColumnOrder(stmt.insert_column_order);
+	node.catalog = qname.catalog;
 	return result;
 }
 
diff --git a/src/planner/binder.cpp b/src/planner/binder.cpp
--- a/src/planner/binder.cpp
+++ b/src/planner/binder.cpp
@@ -83,10 +83,10 @@ BoundStatement Binder::Bind(SQLStatement &statement) {
 	switch (statement.type) {
 	case StatementType::SELECT_STATEMENT:
 		return Bind(statement.Cast<SelectStatement>());
-	case StatementType::INSERT_STATEMENT:
-		return BindWithCTE(statement.Cast<InsertStatement>());
 	case StatementType::COPY_STATEMENT:
 		return Bind(statement.Cast<CopyStatement>(), CopyToType::COPY_TO_FILE);
+	case StatementType::INSERT_STATEMENT:
+		return Bind(statement.Cast<InsertStatement>());
 	case StatementType::DELETE_STATEMENT:
 		return Bind(statement.Cast<DeleteStatement>());
 	case StatementType::UPDATE_STATEMENT:
diff --git a/src/planner/binder/query_node/bind_cte_node.cpp b/src/planner/binder/query_node/bind_cte_node.cpp
--- a/src/planner/binder/query_node/bind_cte_node.cpp
+++ b/src/planner/binder/query_node/bind_cte_node.cpp
@@ -1,6 +1,7 @@
 #include "duckdb/parser/query_node/cte_node.hpp"
 #include "duckdb/parser/query_node/update_query_node.hpp"
 #include "duckdb/parser/query_node/delete_query_node.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 #include "duckdb/planner/binder.hpp"
 #include "duckdb/planner/operator/logical_materialized_cte.hpp"
 #include "duckdb/parser/query_node/list.hpp"
@@ -45,6 +46,9 @@ BoundStatement Binder::BindNode(QueryNode &node) {
 	case QueryNodeType::DELETE_QUERY_NODE:
 		result = current_binder.get().BindNode(node.Cast<DeleteQueryNode>());
 		break;
+	case QueryNodeType::INSERT_QUERY_NODE:
+		result = current_binder.get().BindNode(node.Cast<InsertQueryNode>());
+		break;
 	default:
 		throw InternalException("Unsupported query node type");
 	}
diff --git a/src/planner/binder/statement/bind_copy.cpp b/src/planner/binder/statement/bind_copy.cpp
--- a/src/planner/binder/statement/bind_copy.cpp
+++ b/src/planner/binder/statement/bind_copy.cpp
@@ -14,6 +14,7 @@
 #include "duckdb/parser/query_node/select_node.hpp"
 #include "duckdb/parser/statement/copy_statement.hpp"
 #include "duckdb/parser/statement/insert_statement.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 #include "duckdb/parser/tableref/basetableref.hpp"
 #include "duckdb/planner/binder.hpp"
 #include "duckdb/planner/operator/logical_copy_to_file.hpp"
@@ -403,10 +404,11 @@ BoundStatement Binder::BindCopyFrom(CopyStatement &stmt, const CopyFunction &fun
 	// COPY FROM a file
 	// generate an insert statement for the to-be-inserted table
 	InsertStatement insert;
-	insert.table = stmt.info->table;
-	insert.schema = stmt.info->schema;
-	insert.catalog = stmt.info->catalog;
-	insert.columns = stmt.info->select_list;
+	auto &insert_node = *insert.node;
+	insert_node.table = stmt.info->table;
+	insert_node.schema = stmt.info->schema;
+	insert_node.catalog = stmt.info->catalog;
+	insert_node.columns = stmt.info->select_list;
 
 	// bind the insert statement to the base table
 	auto insert_statement = Bind(insert);
diff --git a/src/planner/binder/statement/bind_copy_database.cpp b/src/planner/binder/statement/bind_copy_database.cpp
--- a/src/planner/binder/statement/bind_copy_database.cpp
+++ b/src/planner/binder/statement/bind_copy_database.cpp
@@ -11,6 +11,7 @@
 #include "duckdb/parser/expression/star_expression.hpp"
 #include "duckdb/parser/query_node/select_node.hpp"
 #include "duckdb/parser/statement/insert_statement.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 #include "duckdb/parser/tableref/basetableref.hpp"
 #include "duckdb/planner/expression/bound_constant_expression.hpp"
 #include "duckdb/planner/operator/logical_dummy_scan.hpp"
@@ -57,9 +58,10 @@ unique_ptr<LogicalOperator> Binder::BindCopyDatabaseData(Catalog &source_catalog
 		auto &table = table_ref.get().Cast<TableCatalogEntry>();
 		// generate the insert statement
 		InsertStatement insert_stmt;
-		insert_stmt.catalog = target_database_name;
-		insert_stmt.schema = table.ParentSchema().name;
-		insert_stmt.table = table.name;
+		auto &insert_node = *insert_stmt.node;
+		insert_node.catalog = target_database_name;
+		insert_node.schema = table.ParentSchema().name;
+		insert_node.table = table.name;
 
 		auto from_tbl = make_uniq<BaseTableRef>();
 		from_tbl->catalog_name = source_catalog.GetName();
@@ -77,7 +79,7 @@ unique_ptr<LogicalOperator> Binder::BindCopyDatabaseData(Catalog &source_catalog
 		auto select_stmt = make_uniq<SelectStatement>();
 		select_stmt->node = std::move(select_node);
 
-		insert_stmt.select_statement = std::move(select_stmt);
+		insert_node.select_statement = std::move(select_stmt);
 		auto bound_insert = Bind(insert_stmt);
 		auto insert_plan = std::move(bound_insert.plan);
 		insert_nodes.push_back(std::move(insert_plan));
diff --git a/src/planner/binder/statement/bind_insert.cpp b/src/planner/binder/statement/bind_insert.cpp
--- a/src/planner/binder/statement/bind_insert.cpp
+++ b/src/planner/binder/statement/bind_insert.cpp
@@ -4,6 +4,7 @@
 #include "duckdb/parser/expression/constant_expression.hpp"
 #include "duckdb/parser/expression/function_expression.hpp"
 #include "duckdb/parser/statement/insert_statement.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
 #include "duckdb/parser/statement/merge_into_statement.hpp"
 #include "duckdb/parser/query_node/select_node.hpp"
 #include "duckdb/parser/tableref/expressionlistref.hpp"
@@ -56,13 +57,13 @@ void Binder::TryReplaceDefaultExpression(unique_ptr<ParsedExpression> &expr, con
 	expr = ExpandDefaultExpression(column);
 }
 
-void Binder::ExpandDefaultInValuesList(InsertStatement &stmt, TableCatalogEntry &table,
+void Binder::ExpandDefaultInValuesList(InsertQueryNode &node, TableCatalogEntry &table,
                                        optional_ptr<ExpressionListRef> values_list,
                                        const vector<LogicalIndex> &named_column_map) {
 	if (!values_list) {
 		return;
 	}
-	idx_t expected_columns = stmt.columns.empty() ? table.GetColumns().PhysicalColumnCount() : stmt.columns.size();
+	idx_t expected_columns = node.columns.empty() ? table.GetColumns().PhysicalColumnCount() : node.columns.size();
 
 	// special case: check if we are inserting from a VALUES statement
 	if (values_list) {
@@ -71,7 +72,7 @@ void Binder::ExpandDefaultInValuesList(InsertStatement &stmt, TableCatalogEntry
 		expr_list.expected_names.resize(expected_columns);
 
 		D_ASSERT(!expr_list.values.empty());
-		CheckInsertColumnCountMismatch(expected_columns, expr_list.values[0].size(), !stmt.columns.empty(), table.name);
+		CheckInsertColumnCountMismatch(expected_columns, expr_list.values[0].size(), !node.columns.empty(), table.name);
 
 		// VALUES list!
 		for (idx_t col_idx = 0; col_idx < expected_columns; col_idx++) {
@@ -173,7 +174,7 @@ void DoUpdateSetQualify(unique_ptr<ParsedExpression> &expr, const string &table_
 	    *expr, [&](unique_ptr<ParsedExpression> &child) { DoUpdateSetQualify(child, table_name, lambda_params); });
 }
 
-unique_ptr<UpdateSetInfo> CreateSetInfoForReplace(TableCatalogEntry &table, InsertStatement &insert,
+unique_ptr<UpdateSetInfo> CreateSetInfoForReplace(TableCatalogEntry &table, InsertQueryNode &insert,
                                                   const TableStorageInfo &storage_info) {
 	auto set_info = make_uniq<UpdateSetInfo>();
 
@@ -262,14 +263,14 @@ void Binder::BindInsertColumnList(TableCatalogEntry &table, vector<string> &colu
 	}
 }
 
-unique_ptr<MergeIntoStatement> Binder::GenerateMergeInto(InsertStatement &stmt, TableCatalogEntry &table) {
-	D_ASSERT(stmt.on_conflict_info);
+unique_ptr<MergeIntoStatement> Binder::GenerateMergeInto(InsertQueryNode &node, TableCatalogEntry &table) {
+	D_ASSERT(node.on_conflict_info);
 
-	auto &on_conflict_info = *stmt.on_conflict_info;
+	auto &on_conflict_info = *node.on_conflict_info;
 	auto merge_into = make_uniq<MergeIntoStatement>();
 	// set up the target table
-	string table_name = !stmt.table_ref->alias.empty() ? stmt.table_ref->alias : stmt.table;
-	merge_into->target = std::move(stmt.table_ref);
+	string table_name = !node.table_ref->alias.empty() ? node.table_ref->alias : node.table;
+	merge_into->target = std::move(node.table_ref);
 
 	auto storage_info = table.GetStorageInfo(context);
 	auto &columns = table.GetColumns();
@@ -381,40 +382,40 @@ unique_ptr<MergeIntoStatement> Binder::GenerateMergeInto(InsertStatement &stmt,
 	}
 
 	// expand any default values
-	auto values_list = stmt.GetValuesList();
+	auto values_list = node.GetValuesList();
 	if (values_list) {
 		vector<LogicalIndex> named_column_map;
-		if (stmt.columns.empty()) {
+		if (node.columns.empty()) {
 			for (auto &col : table.GetColumns().Physical()) {
 				named_column_map.push_back(col.Logical());
 			}
 		} else {
 			// Ensure that the columns are valid.
-			for (auto &col_name : stmt.columns) {
+			for (auto &col_name : node.columns) {
 				auto col_idx = table.GetColumnIndex(col_name);
 				named_column_map.push_back(col_idx);
 			}
 		}
-		ExpandDefaultInValuesList(stmt, table, values_list, named_column_map);
+		ExpandDefaultInValuesList(node, table, values_list, named_column_map);
 	}
 	// set up the data source
 	unique_ptr<TableRef> source;
-	if (stmt.select_statement) {
-		source = make_uniq<SubqueryRef>(std::move(stmt.select_statement), "excluded");
+	if (node.select_statement) {
+		source = make_uniq<SubqueryRef>(std::move(node.select_statement), "excluded");
 	} else {
 		source = make_uniq<EmptyTableRef>();
 	}
-	if (stmt.column_order == InsertColumnOrder::INSERT_BY_POSITION) {
+	if (node.column_order == InsertColumnOrder::INSERT_BY_POSITION) {
 		// if we are inserting by position add the columns of the target table as an alias to the source
-		if (!stmt.columns.empty() || stmt.default_values) {
+		if (!node.columns.empty() || node.default_values) {
 			// we are not emitting all columns - set the column set as the set of aliases
-			source->column_name_alias = stmt.columns;
+			source->column_name_alias = node.columns;
 
 			// now push another subquery that adds the default columns
 			auto select_stmt = make_uniq<SelectStatement>();
 			auto select_node = make_uniq<SelectNode>();
 			unordered_set<string> set_columns;
-			for (auto &set_col : stmt.columns) {
+			for (auto &set_col : node.columns) {
 				set_columns.insert(set_col);
 			}
 
@@ -465,16 +466,16 @@ unique_ptr<MergeIntoStatement> Binder::GenerateMergeInto(InsertStatement &stmt,
 		D_ASSERT(!on_conflict_info.set_info);
 		// For BY POSITION, create explicit SET information
 		// For BY NAME, leave it empty and let bind_merge_into handle it automatically
-		if (stmt.column_order != InsertColumnOrder::INSERT_BY_NAME) {
-			on_conflict_info.set_info = CreateSetInfoForReplace(table, stmt, storage_info);
+		if (node.column_order != InsertColumnOrder::INSERT_BY_NAME) {
+			on_conflict_info.set_info = CreateSetInfoForReplace(table, node, storage_info);
 		}
 		on_conflict_info.action_type = OnConflictAction::UPDATE;
 	}
 	// now set up the merge actions
 	// first set up the base (insert) action when not matched
 	auto insert_action = make_uniq<MergeIntoAction>();
 	insert_action->action_type = MergeActionType::MERGE_INSERT;
-	insert_action->column_order = stmt.column_order;
+	insert_action->column_order = node.column_order;
 
 	merge_into->actions[MergeActionCondition::WHEN_NOT_MATCHED_BY_TARGET].push_back(std::move(insert_action));
 
@@ -486,7 +487,7 @@ unique_ptr<MergeIntoStatement> Binder::GenerateMergeInto(InsertStatement &stmt,
 		// when doing UPDATE set up the when matched action
 		auto update_action = make_uniq<MergeIntoAction>();
 		update_action->action_type = MergeActionType::MERGE_UPDATE;
-		update_action->column_order = stmt.column_order;
+		update_action->column_order = node.column_order;
 		if (on_conflict_info.set_info) {
 			for (auto &col : on_conflict_info.set_info->expressions) {
 				vector<unordered_set<string>> lambda_params;
@@ -504,21 +505,25 @@ unique_ptr<MergeIntoStatement> Binder::GenerateMergeInto(InsertStatement &stmt,
 	}
 
 	// move over extra properties
-	merge_into->cte_map = std::move(stmt.cte_map);
-	merge_into->returning_list = std::move(stmt.returning_list);
+	merge_into->cte_map = std::move(node.cte_map);
+	merge_into->returning_list = std::move(node.returning_list);
 	return merge_into;
 }
 
 BoundStatement Binder::Bind(InsertStatement &stmt) {
+	return Bind(*stmt.node);
+}
+
+BoundStatement Binder::BindNode(InsertQueryNode &node) {
 	BoundStatement result;
 	result.names = {"Count"};
 	result.types = {LogicalType::BIGINT};
 
-	BindSchemaOrCatalog(stmt.catalog, stmt.schema);
-	auto &table = Catalog::GetEntry<TableCatalogEntry>(context, stmt.catalog, stmt.schema, stmt.table);
-	if (stmt.on_conflict_info) {
+	BindSchemaOrCatalog(node.catalog, node.schema);
+	auto &table = Catalog::GetEntry<TableCatalogEntry>(context, node.catalog, node.schema, node.table);
+	if (node.on_conflict_info) {
 		// generate a MERGE INTO statement and bind it instead
-		auto merge_into = GenerateMergeInto(stmt, table);
+		auto merge_into = GenerateMergeInto(node, table);
 		return Bind(*merge_into);
 	}
 	if (!table.temporary) {
@@ -530,70 +535,70 @@ BoundStatement Binder::Bind(InsertStatement &stmt) {
 
 	auto insert = make_uniq<LogicalInsert>(table, GenerateTableIndex());
 
-	auto values_list = stmt.GetValuesList();
+	auto values_list = node.GetValuesList();
 
 	// bind the root select node (if any)
 	BoundStatement root_select;
-	if (stmt.column_order == InsertColumnOrder::INSERT_BY_NAME) {
+	if (node.column_order == InsertColumnOrder::INSERT_BY_NAME) {
 		if (values_list) {
 			throw BinderException("INSERT BY NAME can only be used when inserting from a SELECT statement");
 		}
-		if (stmt.default_values) {
+		if (node.default_values) {
 			throw BinderException("INSERT BY NAME cannot be combined with with DEFAULT VALUES");
 		}
-		if (!stmt.columns.empty()) {
+		if (!node.columns.empty()) {
 			throw BinderException("INSERT BY NAME cannot be combined with an explicit column list");
 		}
-		D_ASSERT(stmt.select_statement);
+		D_ASSERT(node.select_statement);
 		// INSERT BY NAME - generate the columns from the names of the SELECT statement
 		auto select_binder = Binder::CreateBinder(context, this);
-		root_select = select_binder->Bind(*stmt.select_statement);
+		root_select = select_binder->Bind(*node.select_statement);
 		MoveCorrelatedExpressions(*select_binder);
 
-		stmt.columns = root_select.names;
+		node.columns = root_select.names;
 	}
 
 	vector<LogicalIndex> named_column_map;
-	BindInsertColumnList(table, stmt.columns, stmt.default_values, named_column_map, insert->expected_types,
+	BindInsertColumnList(table, node.columns, node.default_values, named_column_map, insert->expected_types,
 	                     insert->column_index_map);
 
 	// bind the default values
 	auto &catalog_name = table.ParentCatalog().GetName();
 	auto &schema_name = table.ParentSchema().name;
 	BindDefaultValues(table.GetColumns(), insert->bound_defaults, catalog_name, schema_name);
 	insert->bound_constraints = BindConstraints(table);
-	if (!stmt.select_statement && !stmt.default_values) {
+	if (!node.select_statement && !node.default_values) {
 		result.plan = std::move(insert);
 		return result;
 	}
 	// Exclude the generated columns from this amount
-	idx_t expected_columns = stmt.columns.empty() ? table.GetColumns().PhysicalColumnCount() : stmt.columns.size();
-	ExpandDefaultInValuesList(stmt, table, values_list, named_column_map);
+	idx_t expected_columns = node.columns.empty() ? table.GetColumns().PhysicalColumnCount() : node.columns.size();
+	ExpandDefaultInValuesList(node, table, values_list, named_column_map);
 
 	// parse select statement and add to logical plan
 	unique_ptr<LogicalOperator> root;
-	if (stmt.select_statement) {
-		if (stmt.column_order == InsertColumnOrder::INSERT_BY_POSITION) {
+	if (node.select_statement) {
+		if (node.column_order == InsertColumnOrder::INSERT_BY_POSITION) {
 			auto select_binder = Binder::CreateBinder(context, this);
-			root_select = select_binder->Bind(*stmt.select_statement);
+			root_select = select_binder->Bind(*node.select_statement);
 			MoveCorrelatedExpressions(*select_binder);
 		}
 		// inserting from a select - check if the column count matches
-		CheckInsertColumnCountMismatch(expected_columns, root_select.types.size(), !stmt.columns.empty(), table.name);
+		CheckInsertColumnCountMismatch(expected_columns, root_select.types.size(), !node.columns.empty(), table.name);
 
 		root = CastLogicalOperatorToTypes(root_select.types, insert->expected_types, std::move(root_select.plan));
 	} else {
 		root = make_uniq<LogicalDummyScan>(GenerateTableIndex());
 	}
 
 	insert->AddChild(std::move(root));
-	if (!stmt.returning_list.empty()) {
+	if (!node.returning_list.empty()) {
 		insert->return_chunk = true;
 		auto insert_table_index = GenerateTableIndex();
 		insert->table_index = insert_table_index;
 		unique_ptr<LogicalOperator> index_as_logicaloperator = std::move(insert);
 
-		return BindReturning(std::move(stmt.returning_list), table, stmt.table_ref ? stmt.table_ref->alias : string(),
+		return BindReturning(std::move(node.returning_list), table, node.table_ref ? node.table_ref->alias : string(),
 		                     insert_table_index, std::move(index_as_logicaloperator));
 	}
 
diff --git a/src/storage/serialization/serialize_query_node.cpp b/src/storage/serialization/serialize_query_node.cpp
--- a/src/storage/serialization/serialize_query_node.cpp
+++ b/src/storage/serialization/serialize_query_node.cpp
@@ -8,6 +8,9 @@
 #include "duckdb/parser/query_node/list.hpp"
 #include "duckdb/parser/query_node/update_query_node.hpp"
 #include "duckdb/parser/query_node/delete_query_node.hpp"
+#include "duckdb/parser/query_node/insert_query_node.hpp"
+#include "duckdb/parser/statement/insert_statement.hpp"
+#include "duckdb/parser/statement/select_statement.hpp"
 
 namespace duckdb {
 
@@ -29,6 +32,9 @@ unique_ptr<QueryNode> QueryNode::Deserialize(Deserializer &deserializer) {
 	case QueryNodeType::DELETE_QUERY_NODE:
 		result = DeleteQueryNode::Deserialize(deserializer);
 		break;
+	case QueryNodeType::INSERT_QUERY_NODE:
+		result = InsertQueryNode::Deserialize(deserializer);
+		break;
 	case QueryNodeType::RECURSIVE_CTE_NODE:
 		result = RecursiveCTENode::Deserialize(deserializer);
 		break;
@@ -88,6 +94,35 @@ unique_ptr<QueryNode> DeleteQueryNode::Deserialize(Deserializer &deserializer) {
 	return std::move(result);
 }
 
+void InsertQueryNode::Serialize(Serializer &serializer) const {
+	QueryNode::Serialize(serializer);
+	serializer.WritePropertyWithDefault<unique_ptr<SelectStatement>>(200, "select_statement", select_statement);
+	serializer.WritePropertyWithDefault<vector<string>>(201, "columns", columns);
+	serializer.WritePropertyWithDefault<string>(202, "table", table);
+	serializer.WritePropertyWithDefault<string>(203, "schema", schema);
+	serializer.WritePropertyWithDefault<string>(204, "catalog", catalog);
+	serializer.WritePropertyWithDefault<vector<unique_ptr<ParsedExpression>>>(205, "returning_list", returning_list);
+	serializer.WritePropertyWithDefault<unique_ptr<OnConflictInfo>>(206, "on_conflict_info", on_conflict_info);
+	serializer.WritePropertyWithDefault<unique_ptr<TableRef>>(207, "table_ref", table_ref);
+	serializer.WritePropertyWithDefault<bool>(208, "default_values", default_values, false);
+	serializer.WritePropertyWithDefault<InsertColumnOrder>(209, "column_order", column_order, InsertColumnOrder::INSERT_BY_POSITION);
+}
+
+unique_ptr<QueryNode> InsertQueryNode::Deserialize(Deserializer &deserializer) {
+	auto result = duckdb::unique_ptr<InsertQueryNode>(new InsertQueryNode());
+	deserializer.ReadPropertyWithDefault<unique_ptr<SelectStatement>>(200, "select_statement", result->select_statement);
+	deserializer.ReadPropertyWithDefault<vector<string>>(201, "columns", result->columns);
+	deserializer.ReadPropertyWithDefault<string>(202, "table", result->table);
+	deserializer.ReadPropertyWithDefault<string>(203, "schema", result->schema);
+	deserializer.ReadPropertyWithDefault<string>(204, "catalog", result->catalog);
+	deserializer.ReadPropertyWithDefault<vector<unique_ptr<ParsedExpression>>>(205, "returning_list", result->returning_list);
+	deserializer.ReadPropertyWithDefault<unique_ptr<OnConflictInfo>>(206, "on_conflict_info", result->on_conflict_info);
+	deserializer.ReadPropertyWithDefault<unique_ptr<TableRef>>(207, "table_ref", result->table_ref);
+	deserializer.ReadPropertyWithExplicitDefault<bool>(208, "default_values", result->default_values, false);
+	deserializer.ReadPropertyWithExplicitDefault<InsertColumnOrder>(209, "column_order", result->column_order, InsertColumnOrder::INSERT_BY_POSITION);
+	return std::move(result);
+}
+
 void RecursiveCTENode::Serialize(Serializer &serializer) const {
 	QueryNode::Serialize(serializer);
 	serializer.WritePropertyWithDefault<string>(200, "cte_name", ctename);
diff --git a/src/storage/serialization/serialize_statement.cpp b/src/storage/serialization/serialize_statement.cpp
--- a/src/storage/serialization/serialize_statement.cpp
+++ b/src/storage/serialization/serialize_statement.cpp
@@ -7,9 +7,26 @@
 #include "duckdb/common/serializer/deserializer.hpp"
 #include "duckdb/parser/statement/select_statement.hpp"
 #include "duckdb/parser/statement/update_statement.hpp"
+#include "duckdb/parser/statement/insert_statement.hpp"
 
 namespace duckdb {
 
+void OnConflictInfo::Serialize(Serializer &serializer) const {
+	serializer.WriteProperty<OnConflictAction>(100, "action_type", action_type);
+	serializer.WritePropertyWithDefault<vector<string>>(101, "indexed_columns", indexed_columns);
+	serializer.WritePropertyWithDefault<unique_ptr<UpdateSetInfo>>(102, "set_info", set_info);
+	serializer.WritePropertyWithDefault<unique_ptr<ParsedExpression>>(103, "condition", condition);
+}
+
+unique_ptr<OnConflictInfo> OnConflictInfo::Deserialize(Deserializer &deserializer) {
+	auto result = duckdb::unique_ptr<OnConflictInfo>(new OnConflictInfo());
+	deserializer.ReadProperty<OnConflictAction>(100, "action_type", result->action_type);
+	deserializer.ReadPropertyWithDefault<vector<string>>(101, "indexed_columns", result->indexed_columns);
+	deserializer.ReadPropertyWithDefault<unique_ptr<UpdateSetInfo>>(102, "set_info", result->set_info);
+	deserializer.ReadPropertyWithDefault<unique_ptr<ParsedExpression>>(103, "condition", result->condition);
+	return result;
+}
+
 void SelectStatement::Serialize(Serializer &serializer) const {
 	serializer.WritePropertyWithDefault<unique_ptr<QueryNode>>(100, "node", node);
 	serializer.WritePropertyWithDefault<case_insensitive_map_t<idx_t>>(101, "named_param_map", named_param_map);
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
