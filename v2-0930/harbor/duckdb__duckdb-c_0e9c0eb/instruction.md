INSERT statements should be represented in the parser as a QueryNode, analogous to the existing DeleteStatement/DeleteQueryNode and UpdateStatement/UpdateQueryNode split.

Currently, INSERT-specific parse state is stored directly on InsertStatement, which prevents INSERT from fully participating in the QueryNode hierarchy and causes missing or incomplete behavior for operations that work on QueryNode objects, such as copying, equality checks, stringification, serialization/deserialization, and use as a CTE body.

Refactor the parser representation so InsertStatement is a thin SQLStatement wrapper around an InsertQueryNode. InsertQueryNode must be a QueryNode with type QueryNodeType::INSERT_QUERY_NODE and must contain the INSERT-specific fields and behavior, including the target catalog/schema/table, optional table reference, select/value source, column list, InsertColumnOrder, DEFAULT VALUES flag, CTE map, RETURNING list, and optional OnConflictInfo.

The following behavior should work through InsertQueryNode:

Parsing `INSERT INTO t VALUES (1, 2, 3)` should produce an InsertStatement whose `node` is non-null, has `type == QueryNodeType::INSERT_QUERY_NODE`, and stores `table == "t"`.

`InsertStatement::ToString()` and `InsertQueryNode::ToString()` should preserve and round-trip supported INSERT forms, including column lists, RETURNING clauses, CTEs, DEFAULT VALUES, `INSERT OR REPLACE`, `INSERT BY NAME`, and `ON CONFLICT DO NOTHING`.

`InsertQueryNode::Copy()` must perform a deep copy, and `InsertQueryNode::Equals()` must compare all relevant INSERT fields so that two equivalent parsed INSERT statements compare equal and statements targeting different tables do not.

Binary serialization and deserialization through `BinarySerializer::Serialize(static_cast<QueryNode &>(node), stream)` and `BinaryDeserializer::Deserialize<QueryNode>(stream)` must support QueryNodeType::INSERT_QUERY_NODE and preserve the full InsertQueryNode contents. This includes INSERT statements with RETURNING and statements with conflict handling such as `INSERT OR REPLACE INTO t VALUES (1, 2)`.

OnConflictInfo must also support copying, equality, string conversion, and binary serialization/deserialization, preserving at least the conflict action, indexed columns, optional update set info, and optional condition. Conflict actions such as REPLACE, NOTHING, UPDATE, and THROW should be handled consistently.

Existing INSERT execution behavior must remain unchanged. The following SQL forms should continue to parse, bind, execute, and stringify correctly:

`INSERT INTO t VALUES (...)`

`INSERT INTO t (a, b, c) VALUES (...)`

`INSERT INTO t VALUES (...) RETURNING a, b, c`

`WITH vals AS (...) INSERT INTO t SELECT * FROM vals RETURNING a`

`INSERT INTO t DEFAULT VALUES`

`INSERT INTO t SELECT ...`

`INSERT INTO schema_name.table_name VALUES (...)`

`INSERT OR REPLACE INTO t VALUES (...)`

`INSERT INTO t BY NAME SELECT ...`

`INSERT INTO t VALUES (...) ON CONFLICT DO NOTHING`

`INSERT INTO t VALUES (...) ON CONFLICT (id) DO UPDATE SET val = excluded.val`

All consumers of parsed INSERT statements, including binding, statement simplification, expression iteration, appender usage, autocomplete parsing, and serialization, should access INSERT-specific state through the InsertQueryNode while preserving existing public behavior of InsertStatement.
