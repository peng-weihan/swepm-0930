#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.gitignore b/.gitignore
--- a/.gitignore
+++ b/.gitignore
@@ -12,8 +12,7 @@
 !CONTRIBUTING.md
 !CODE_OF_CONDUCT.md
 !docs/
-!docs/migrations/
-!docs/migrations/**
+!docs/**
 
 # ── Go source ──
 !go.mod
diff --git a/docs/_config.yml b/docs/_config.yml
new file mode 100644
--- /dev/null
+++ b/docs/_config.yml
@@ -0,0 +1,17 @@
+title: FlowCraft
+description: Go SDK for building AI agents with long-term memory, knowledge retrieval, and voice
+theme: jekyll-theme-cayman
+markdown: GFM
+
+plugins:
+  - jekyll-relative-links
+
+relative_links:
+  enabled: true
+  collections: true
+
+include:
+  - migrations
+
+exclude:
+  - roadmap.md
diff --git a/docs/index.md b/docs/index.md
new file mode 100644
--- /dev/null
+++ b/docs/index.md
@@ -0,0 +1,48 @@
+---
+layout: default
+title: FlowCraft Documentation
+---
+
+# FlowCraft
+
+Go SDK for building AI agents with long-term memory, knowledge
+retrieval, and voice. Source on
+[github.com/GizClaw/flowcraft](https://github.com/GizClaw/flowcraft).
+
+## Migrations
+
+- [`sdk/v0.3.0`](migrations/v0.3.0.md) — breaking-change cutover
+  closing the v0.2.x deprecation window.
+
+## Layered architecture
+
+The SDK is organised top-down from execution primitives to agent
+orchestration:
+
+| Layer | Package | Responsibility |
+| --- | --- | --- |
+| Primitives | `sdk/engine` | Board / Run / Host / Interrupt / Checkpoint contracts |
+| DAG executor | `sdk/graph` | Declarative graph runtime (`runner.Runner` implements `engine.Engine`) |
+| Orchestration | `sdk/agent` | Agents, observers, deciders, board seeders, handoff DSL |
+| Services | `sdk/{recall,history,knowledge,llm,retrieval,workspace}` | Memory, conversation transcripts, knowledge base, LLM factory, hybrid retrieval, workspace abstraction |
+| Adapters | `sdkx/...` | Concrete provider / protocol bindings layered on the SDK contracts |
+
+## Repository layout
+
+```
+sdk/      Core SDK (interfaces + primitives)
+sdkx/     Extended SDK (concrete adapters with their own go.mod)
+voice/    Voice pipeline: STT → LLM → TTS
+bench/    Benchmarks (GOWORK=off)
+examples/ Reference assemblies
+tests/    Conformance / quality / e2e suites
+```
+
+## Getting started
+
+```bash
+go get github.com/GizClaw/flowcraft/sdk@latest
+```
+
+See the package-level `doc.go` files for runnable usage snippets:
+`sdk/agent/doc.go`, `sdk/engine/doc.go`, `sdk/graph/doc.go`.
diff --git a/docs/migrations/v0.3.0.md b/docs/migrations/v0.3.0.md
--- a/docs/migrations/v0.3.0.md
+++ b/docs/migrations/v0.3.0.md
@@ -1,8 +1,13 @@
 # Migrating to FlowCraft `sdk/v0.3.0`
 
-> Status: planning. This document tracks the breaking changes scheduled
-> for `sdk/v0.3.0` so users can prepare in advance and contributors do
-> not introduce new API in soon-to-move locations.
+> Status: pending — describes the breaking changes that will land in
+> the upcoming `sdk/v0.3.0` cut (latest released tag is
+> `sdk/v0.2.11`). Update this banner to "shipped in sdk/v0.3.0" once
+> the tag is cut. The per-package `deprecated.go` index files that
+> tracked these symbols during the v0.2.x deprecation window are
+> being removed alongside the cut because every symbol they tracked
+> is gone; this document is the single source of truth for the
+> migration.
 
 ## Summary
 
@@ -14,15 +19,14 @@ it:
    concrete adapters. LLM tool implementations move to `sdkx/tool/...`.
 2. **Runtime convergence** — the `agent + engine + graph` runtime fully
    replaces the legacy `workflow` package and the `llm.RunRound` round
-   helper family. `sdk/graph/runner.Executor` retires in favour of
-   `Runner` directly implementing `engine.Engine`.
+   helper family. The unexported
+   `sdk/graph/runner/internal/executor.Executor` interface retires in
+   favour of `Runner` directly implementing `engine.Engine` over a
+   single `LocalExecutor`.
 3. **API tidy-ups** — many service packages (`sdk/knowledge`,
    `sdk/history`, `sdk/retrieval`) carry compatibility shims from their
    v0.1 → v0.2 redesigns. v0.3.0 deletes them.
 
-Authoritative per-package indexes live in each package's `deprecated.go`
-file. This document collates them into a single migration plan.
-
 > **`sdk` defines interfaces and primitives. `sdkx` ships concrete
 > adapters that integrate with external systems or external protocol
 > specs.**
@@ -33,9 +37,28 @@ file. This document collates them into a single migration plan.
 
 ### `sdk/workflow` — full package deletion
 
-Deprecated since `v0.1.x`. The migration map (every concept →
-`agent + engine + graph` equivalent) lives in
-[`sdk/workflow/doc.go`](../../sdk/workflow/doc.go).
+Deprecated since `v0.1.x`. Every workflow concept maps to an
+`agent + engine + graph` equivalent: `workflow.Agent` →
+`agent.Agent` driven by `runner.Runner` (which implements
+`engine.Engine`); `workflow.Board` → `engine.Board`; `workflow`
+strategy / runnable → `agent.BoardSeeder` + `agent.Decider`;
+`workflow.RunOption` → `engine.Run` parameters.
+
+### `sdk/graph/adapter` — workflow ↔ graph bridge package deleted
+
+The whole package goes away with `sdk/workflow`. Removed symbols:
+
+- `adapter.FromDefinition(*graph.GraphDefinition) workflow.Strategy`
+- `adapter.FromCompiled(*graph.CompiledGraph) workflow.Strategy`
+
+These existed only to plug `graph.GraphDefinition` /
+`CompiledGraph` into `workflow.Strategy` so workflow runs could
+delegate execution to graph. The replacement is to drive the
+graph directly: build a `runner.Runner` (which implements
+`engine.Engine`) and either call it through `agent.Run` or let
+`engine.LoadAndResume` resume against it. Boards no longer need
+the `graphBoardFromWorkflow` / `workflowBoardFromGraph` round-trip
+because `engine.Board` is the single board type.
 
 ### `sdk/agent` — Handoff stays put
 
@@ -101,67 +124,165 @@ event happen at separate, low-risk moments for users.
 
 ### `sdk/llm` — round helpers and capability shims removed
 
-Canonical index: [`sdk/llm/deprecated.go`](../../sdk/llm/deprecated.go).
-
 Removed in v0.3.0:
 
 - **Round helper family** (workflow-era streaming + tool-call orchestrator):
   `RunRound`, `RoundStream`, `StreamRound`, `RoundResult`, `RoundConfig`,
   `RoundConfigFromMap`, `CoerceMapForStruct`. The `agent + engine` runtime
   owns per-call streaming and tool execution natively — call
   `LLM.GenerateStream` directly or run the LLM through an `agent.Agent`.
-- **Capability middleware shims**: `CapsMiddleware`, `WithCapsMiddleware`
-  (replaced by `WithCaps` / `WithPolicyCaps`),
+- **Capability middleware shims**: `CapsMiddleware` (replaced by
+  `WithCaps`), `WithExtraCaps` (renamed `WithPolicyCaps` to make the
+  resolver-wide intent explicit),
   `(*ProviderRegistry).LookupModelCaps` (replaced by
   `LookupModelSpec(...).Caps`).
 - **`ModelInfo.Caps` field** — set `ModelInfo.Spec.Caps` directly.
 
-### `sdk/graph` — runner converges on `engine.Engine`
+Additions (v0.2.x → v0.3.0, no removals required):
+
+- **Image / audio output capabilities**: `CapImageOutput`,
+  `CapAudioOutput`; `ImageGenOptions` request shape; the
+  `ImageGenerator` capability surface.
+- **`OneChunkStream`** is now a public helper for adapters that want
+  to expose a non-streaming response through the streaming interface.
 
-Canonical index: [`sdk/graph/deprecated.go`](../../sdk/graph/deprecated.go).
+### `sdk/graph` — runner converges on `engine.Engine`
 
 Removed in v0.3.0:
 
-- **`sdk/graph/runner/internal/executor.Executor`** — the legacy
-  graph executor. `runner.Runner` itself implements `engine.Engine`
-  starting in v0.2; engines are exposed exclusively through that path.
+- **`sdk/graph/runner/internal/executor.Executor` interface** — the
+  legacy execution-engine abstraction. `runner.Runner` itself
+  implements `engine.Engine` starting in v0.2; the internal
+  `LocalExecutor` is now the only concrete graph executor and is
+  used by `Runner` directly without going through an interface.
+- **`graph.ErrInterrupt`** sentinel — return
+  `engine.Interrupted(engine.Interrupt{Cause: …})` instead, which
+  carries a typed Cause and Detail. Both used to satisfy
+  `errdefs.IsInterrupted`; only the latter remains.
 - **Runner option shims** that bypass the host abstraction:
   `WithEventBus`, `WithStreamCallback`, `WithCheckpointStore`,
   `Runner.Bus()`, plus the matching internal fields on `Executor`.
   Pass an `engine.Host` via `WithHost` instead.
 - **Run-ID injection helpers** that pre-date `engine.Run.ID` — the run
-  identity now flows through `engine.Engine.Execute`.
+  identity now flows through `engine.Engine.Execute`. (`runner.WithRunID`
+  itself stays exported as a non-deprecated convenience for callers
+  that drive `Runner.Run` directly outside an engine handler.)
 - **`busOnlyHost`** transitional shim.
-- **Chat-application `graph.Var*` constants**: `VarMessages`, `VarQuery`,
-  `VarAnswer`. These move to `sdk/agent` as the chat conventions belong
-  to the agent layer; new code should pass keys through node config.
+- **`graph.VarMessages` / `graph.VarQuery` / `graph.VarAnswer`** removed.
+  An earlier plan moved them to `sdk/agent`; instead the underlying
+  abstraction was simplified: `llmnode.Config.MessagesKey` (string,
+  pulling double-duty as both var name and channel name with a
+  hard-coded `"messages" → "main"` rewrite) is replaced by
+  `llmnode.Config.MessagesChannel` (json `messages_channel`), which
+  is a pure typed-channel name. Empty value means [graph.MainChannel];
+  any other value names an isolated channel. `llmnode` no longer
+  mirrors the transcript onto a board var — readers must use
+  `board.Channel(...)`.
+- **`llmnode.Config.QueryFallback`** (json `query_fallback`) removed,
+  along with the implicit "read board var `query`, append as final
+  user message when the messages channel is non-Main" branch. The
+  feature coupled "isolated channel" with "single-turn fallback"
+  through a magic var key and had fragile multi-turn semantics.
+  Migration: write the user turn directly to the channel from an
+  upstream node, e.g.
+
+  ```go
+  board.SetChannel("my_chan", []llm.Message{
+      llm.NewTextMessage(llm.RoleUser, query),
+  })
+  ```
+
+  The compile-time warning `llm_isolated_messages_no_fallback` is also
+  removed because its only resolution suggestion (set `query_fallback`)
+  no longer exists; an empty isolated channel will surface as a
+  runtime error from the LLM call instead.
+
+- **`graph.ValidateInputsWithConfig`** behaviour change: the legacy
+  branch `p.Name == VarMessages || p.Type == PortTypeMessages` (always
+  validating against `MainChannel`) is now `p.Type == PortTypeMessages`
+  validating against `Channel(p.Name)`. Custom nodes that declared a
+  message-typed input port with a non-Main name and relied on the
+  validator silently skipping the check by reading `MainChannel` will
+  now correctly require their own channel to be populated.
+- **`engine.MainChannel`** value changed from `""` to `"__main_channel"`.
+  Naming rule introduced: every engine-reserved board key (var or
+  channel) uses the `__` prefix; user-domain code MUST NOT introduce
+  channel or var names beginning with `__`. Existing code that
+  references `engine.MainChannel` / `graph.MainChannel` via the
+  constant tracks the new value automatically — only callers that
+  hard-coded the empty string need to switch to the constant. Stored
+  checkpoints (`BoardSnapshot.Channels` JSON) carrying the legacy
+  `""` key are auto-migrated by `engine.RestoreBoard` /
+  `Board.RestoreFrom`; the migration shim is scheduled for removal
+  in v0.4 once all persisted checkpoints have been re-taken with a
+  v0.3+ writer.
+- **`llmnode` empty-request guard**: `Node.ExecuteBoard` now returns
+  `errdefs.Validation` when the resolved `messages_channel` is empty
+  _and_ `system_prompt` is unset. Previously such a graph would hand
+  an empty request to the LLM, where behaviour depends on the
+  provider (Anthropic rejects, OpenAI / Gemini accept). The
+  system-prompt-only case (channel empty but `system_prompt` non-
+  empty) is still allowed — useful for autonomous / scheduled agents
+  whose first turn is system-driven.
+- **`knowledgenode.Config.QueryKey`** added (json `query_key`). Names
+  the board var the node reads as the search query; empty preserves
+  the historical `"query"` default. Use it to disambiguate when
+  multiple knowledge nodes consume different inputs in the same
+  graph, or to align the var key with whatever the upstream board
+  seeder writes.
+- **`model.LastByRole(msgs, role)`** added. Returns the last message
+  in `msgs` whose `Role` matches, plus an `ok` bool. Replaces the
+  previous ad-hoc reverse-scan loops sprinkled around node code that
+  needed "the latest user turn on `MainChannel`" (or any role-scoped
+  pick) and removes the temptation to recouple board vars and channel
+  contents through magic keys.
 
 ### `sdk/script/bindings` — workflow-coupled bindings removed
 
-Canonical index:
-[`sdk/script/bindings/deprecated.go`](../../sdk/script/bindings/deprecated.go).
-
 Removed in v0.3.0:
 
+- `NewStreamBridge(stream workflow.StreamCallback, nodeID string)` —
+  the bridge that adapted a `workflow.StreamCallback` for script
+  emission. Scripts now publish through the `engine.Host` /
+  `event.Bus` plane that node code already uses; no script-side
+  shim is needed.
 - `NewRunBridge` / `RunBridgeOptions` — hard-wired to `*workflow.Board`.
-  The agent/engine stack carries the same metadata as `agent.RunInfo`.
+  Replaced by `NewRunInfoBridge(info agent.RunInfo)`; the agent/engine
+  stack carries the same metadata as `agent.RunInfo`.
 - `AgentStepBindings` / `AgentStepOptions` — `Board *workflow.Board`
   receiver retires with `workflow`.
 - The `BuildEnv` preset for the workflow-era binding set — callers
   compose `BuildEnv` with the bridges they want directly.
 
 ### `sdk/knowledge` — legacy v0.1 storage and search types
 
-Canonical index:
-[`sdk/knowledge/deprecated.go`](../../sdk/knowledge/deprecated.go).
-
 Removed in v0.3.0:
 
-- **Type renames / consolidations**: `Document` (split into
-  `SourceDocument` + `DerivedLayer`), `Chunk` (replaced by
-  `DerivedChunk`), `SearchResult` (replaced by `Hit`), `SearchOptions`
-  (replaced by `Query`), `DocInput`, `SearchMode = "semantic"` (use
-  `ModeVector`).
+- **Data-model deletions**:
+  - `Document` (split into `SourceDocument` for raw content + Version,
+    and `DerivedLayer` for L0 abstract / L1 overview).
+  - `Chunk` (replaced by `DerivedChunk`).
+  - `SearchResult` (replaced by `Hit`).
+  - `SearchOptions` (replaced by `Query` with `Scope` / `Mode` /
+    `Layer`).
+  - `DocInput` (folded into the `*Service.Put` parameters).
+  - `ModeSemantic` (`SearchMode = "semantic"`) — use `ModeVector`. The
+    v0.2.x `ResolveMode` shim that mapped `"semantic" → "vector"` is
+    gone too; persisted requests carrying the literal must be
+    rewritten before upgrading.
+- **Graph node renames** — the v0.1 node types lived as deprecated
+  shims in v0.2.x and are now removed:
+  - `KnowledgeConfig` → `KnowledgeNodeConfig`
+  - `KnowledgeNode` → `KnowledgeServiceNode`
+  - `NewKnowledgeNode` → `NewKnowledgeServiceNode`
+  - `KnowledgeConfigFromMap` → `KnowledgeNodeConfigFromMap`
+  - `RegisterNode` → `RegisterServiceNode`
+  - `KnowledgeNodeSchema` → `KnowledgeServiceNodeSchema`
+
+  `DatasetQuery` (the dataset descriptor reused by both old and new
+  config) is no longer exported from `sdk/knowledge`; it lives on
+  `knowledgenode.Config.Datasets` directly.
+
 - **Storage layer**: `Store` interface, `FSStore` and its options
   (`WithTokenizer`, `WithChunkConfig`, `WithEmbedder`, ...),
   `RetrievalStore` and its options (`WithRetrievalEmbedder`,
@@ -173,84 +294,153 @@ Removed in v0.3.0:
   `ScoreChunk` (use `textsearch.BM25` directly), `RankResults` /
   `RRFMerge` (use `RRFRanker`).
 - **Reload pipeline**: `ChangeNotifier` / `Reloader` /
-  `NewReloader` (use `EventNotifier` + `EventReloader`).
+  `NewReloader` (use `EventNotifier` + `EventReloader`). The
+  in-tree consumer of the deprecated notifier,
+  `sdkx/knowledge/watcher`, is removed alongside; durable watchers
+  must produce `ChangeEvent` values for `EventReloader` directly.
 - **Tool helpers carried over from the `Store` era**: `NewSearchTool`,
   `NewAddTool` (use `NewSearchServiceTool` / `NewPutServiceTool`,
   themselves moving to `sdkx/tool/knowledge` per the layering section
   above).
 
-### `sdk/history` — closers and manifest internals
+Type-alias changes (kept compiling, but the primary spelling flipped):
+
+- `Layer` is now the canonical type name; the v0.2.x primary name
+  `ContextLayer` survives as `type ContextLayer = Layer` so callers
+  using either spelling keep building. Constants
+  (`LayerAbstract` / `LayerOverview` / `LayerDetail`) declare on
+  `Layer`.
+- `Mode` is the canonical name for `SearchMode`; the older spelling
+  remains as `type Mode = SearchMode`. The constant set
+  (`ModeBM25` / `ModeVector` / `ModeHybrid`) declares on `SearchMode`.
 
-Canonical index:
-[`sdk/history/deprecated.go`](../../sdk/history/deprecated.go).
+### `sdk/history` — closers and manifest internals
 
 Removed in v0.3.0:
 
 - **`Closer.Close` / `compactor.Close`** — use `Coordinator.Shutdown`
   with a context for bounded waits.
-- **`Store` interface** — superseded by `SummaryStore`.
-- **Manual recovery / cold-segment helpers** — `Coordinator`'s startup
-  scan handles recovery automatically; cold-segment loading is the
-  `history_expand` tool's concern.
-- **Manifest read/write helpers** — manifest is an internal artefact of
-  `Coordinator`; query `Coordinator.Archive` instead.
+- **`SummaryCacheStore`** — superseded by `SummaryStore`, which the
+  summary DAG already consumes; the cache wrapper had no remaining
+  readers.
+- **Top-level archive helpers moved off the public surface**:
+  - `RecoverArchive(ctx, ws, store, prefix, archivePrefix, convID)` —
+    folded into the unexported `recoverArchiveImpl`. `Coordinator`
+    auto-recovers in-flight archives at construction; callers that
+    drove recovery manually should construct a `Coordinator` instead.
+  - `SaveManifest(ctx, ws, prefix, archivePrefix, convID, *Manifest)` —
+    folded into the unexported `saveManifestImpl`. There is no
+    public replacement: archive lifecycle is now owned by
+    `Coordinator` end-to-end.
+- **Tool implementations migrated to `sdkx/tool/history`** — `ToolDeps`,
+  `RegisterTools`, `historyExpandTool`, `historyCompactTool`. The
+  archive helpers they read from disk (`Archive`, `LoadManifest`,
+  `LoadArchivedMessages`) remain exported from `sdk/history` so the
+  external tool wrapper can keep using them without re-implementing
+  the on-disk format.
+
+Note: `Store` (the short-term `[]model.Message` persistence interface)
+is **not** removed — it is the active contract `InMemoryStore` and the
+archive subsystem are built around. It is unrelated to the
+`SummaryStore` summary-DAG interface.
 
 ### `sdk/retrieval` — Execution-only debug surface
 
 Removed in v0.3.0:
 
-- `SearchResponse.RawByRetriever` — read `SearchResponse.Execution`
-  instead. Backends keep `RawByRetriever` populated as a projection of
-  `Execution` until removal.
+- `SearchRequest.ReturnRaw` (request-side toggle) — the pipeline no
+  longer branches on this flag; debug projections are produced
+  unconditionally and read through `SearchResponse.Execution`.
+- `SearchResponse.RawByRetriever` (response-side debug map) — read
+  `SearchResponse.Execution` instead.
 - `Explain.Lanes` legacy field — use `Execution.Lanes`.
 
 ---
 
-## Why now
-
-v0.2 introduced the `agent + engine + graph` runtime, the
-`SourceDocument`/`DerivedLayer` knowledge model, and the
-`Coordinator`-driven history archive. Each of those redesigns shipped
-with compatibility shims so existing call sites would keep compiling.
+## Additive surface picked up between v0.2.0 and v0.3.0
+
+The following capabilities landed during the v0.2.x cycle and ship
+unchanged in v0.3.0; they are not breaking, but downstream code that
+skipped intermediate v0.2.x tags often discovers them at the v0.3.0
+upgrade. Listed for completeness:
+
+- **`sdk/engine`**
+  - `StreamRouter` — fan-out helper for routing a single stream-delta
+    source to multiple sinks (file, OTLP, websocket, ...).
+  - Optional `Resumer` interface plus the `LoadAndResume` helper —
+    engines that opt in get fully threaded resume from a
+    `CheckpointStore` via one call.
+  - Public `Subject` / `Pattern` contract for cross-engine event
+    routing.
+  - Engine-host extensibility hooks (event sampling, token-usage
+    reporting wiring).
+- **`sdk/agent`**
+  - `Handoff` DSL — declarative agent-to-agent transfer primitive.
+- **`sdk/workspace`**
+  - `Capabilities` value + `CapabilityReporter` interface so workspace
+    backends advertise the operations they actually support
+    (atomic-write, advisory-lock, ...). Adapters in `sdkx/workspace`
+    and `sdkx/retrieval/workspace` rely on this to gate behaviour.
+- **`sdk/retrieval/scoring`**
+  - Public `CosineSim`, plus `RRFFuse` / `WeightedFuse` helpers
+    extracted so external rankers can call them directly.
+- **`sdk/telemetry`**
+  - `AttrXxx` constant set; `ConversationID` / `DatasetID` /
+    `ErrorMessage` attribute keys; provider-error classification
+    aligned across providers.
+- **`sdk/errdefs`**
+  - Pod-grade boundary error normalization (every external boundary
+    classifies origin errors through `errdefs` rather than ad-hoc
+    string matching).
 
-Two release cycles in, the shims double-document the API: every
-package now ships a `deprecated.go` listing what to call instead.
-v0.3.0 collapses the duplicate surface and lets contributors stop
-threading new code through the legacy paths.
-
-## Backwards-compatibility shim
-
-There is no global shim. `sdk` cannot import `sdkx`, and the runtime
-removals (`workflow`, `executor.Executor`, the round helpers) genuinely
-delete behaviour, not paths.
+---
 
-To soften the impact:
+## Why this release
 
-- All affected symbols are marked `// Deprecated:` from `sdk/v0.2.x`
-  onwards, so `go vet` / `staticcheck (SA1019)` / IDE warnings flag
-  callers ahead of the cut.
-- Each package carries a `deprecated.go` "what replaces what" index.
-- A migration script (`scripts/migrate-tools-v0.3.go`) handles the
-  mechanical import rewrites for the `sdk/{knowledge,kanban,history}`
-  → `sdkx/tool/...` move.
+v0.2 introduced the `agent + engine + graph` runtime, the
+`SourceDocument`/`DerivedLayer` knowledge model, and the
+`Coordinator`-driven history archive. Each redesign shipped with
+compatibility shims (`Deprecated:`-marked symbols + per-package
+`deprecated.go` indexes) so existing call sites kept compiling
+through the v0.2 series.
+
+v0.3.0 deletes those shims in one cut, collapsing the duplicate API
+surface so contributors stop threading new code through the legacy
+paths and `staticcheck (SA1019)` stops being noisy.
+
+## Backwards-compatibility
+
+There is no global shim. The runtime removals (`workflow`,
+`executor.Executor`, the round helpers) genuinely delete behaviour;
+the storage/format renames in `sdk/knowledge` and `sdk/history`
+preserve on-disk artefacts (the `factory.NewLocal` service reads the
+same workspace layout the legacy `FSStore` produced). Stored
+checkpoints carrying the legacy empty-string `MainChannel` key are
+auto-migrated by `engine.RestoreBoard` / `Board.RestoreFrom`; that
+migration shim is itself slated for removal in v0.4.
+
+The recommended upgrade path is the two-step process documented in
+the _Release coordination with `sdkx`_ table above: first swap
+imports during the v0.2.x window (no tag boundary crossed), then
+`go get -u` once v0.3.0 ships.
 
 ## Timeline
 
-- **`sdk/v0.2.x`** (current): Deprecation notices in place across
-  every affected package. No behavioural change. Users SHOULD start
-  migrating in advance.
-- **`sdkx/v0.2.x`** (parallel): New `sdkx/tool/*` packages land
-  alongside the existing `sdk` locations so users can switch on
-  their own schedule.
-- **`sdk/v0.3.0`**: All sections above land as one cut. Release notes
-  will reference this file.
-
-## See also
-
-- Per-package `deprecated.go` files, the source of truth:
-  - [`sdk/llm/deprecated.go`](../../sdk/llm/deprecated.go)
-  - [`sdk/graph/deprecated.go`](../../sdk/graph/deprecated.go)
-  - [`sdk/script/bindings/deprecated.go`](../../sdk/script/bindings/deprecated.go)
-  - [`sdk/knowledge/deprecated.go`](../../sdk/knowledge/deprecated.go)
-  - [`sdk/history/deprecated.go`](../../sdk/history/deprecated.go)
-  - [`sdk/workflow/doc.go`](../../sdk/workflow/doc.go)
+- **`sdk/v0.2.0` – `sdk/v0.2.11`** (released): Deprecation notices
+  in place across every affected package. No behavioural change.
+  Users SHOULD start migrating in advance.
+- **`sdkx/v0.2.0` – `sdkx/v0.2.9`** (released, parallel): New
+  `sdkx/tool/*` packages land alongside the existing `sdk`
+  locations so callers can switch imports at their own schedule,
+  before any source-level breakage.
+- **`sdk/v0.3.0`** (pending): All breaking changes documented
+  above land as one cut. Release notes reference this file.
+- **`sdkx/v0.3.0`** (pending, coordinated): Same-day cut. Tool
+  wrappers under `sdkx/tool/{knowledge,kanban,history}` take
+  ownership of the implementations relocated out of `sdk`. Public
+  signatures remain identical; downstream code that already swapped
+  imports during the v0.2.x window only needs `go get -u`.
+- **`sdk/v0.4.0`** (later): Removal of the `MainChannel`
+  legacy-key migration shim in `engine.RestoreBoard` /
+  `Board.RestoreFrom`. By then all persisted checkpoints should
+  have been re-taken with a v0.3+ writer.
diff --git a/sdk/engine/board.go b/sdk/engine/board.go
--- a/sdk/engine/board.go
+++ b/sdk/engine/board.go
@@ -9,13 +9,26 @@ import (
 	"github.com/GizClaw/flowcraft/sdk/model"
 )
 
-// MainChannel is the default message channel key (empty string).
+// MainChannel is the default message channel key.
 //
 // Channels are an engine-level primitive: they let nodes/steps share
 // ordered message sequences without going through Vars. Convention-level
 // keys for "the chat transcript", "the answer", etc. belong to the
 // agent layer; this package only provides the channel mechanism.
-const MainChannel = ""
+//
+// Naming rule: any board key (var or channel) reserved by the engine
+// itself uses the "__" prefix. User-domain code MUST NOT introduce
+// channel or var names beginning with "__"; doing so risks colliding
+// with a future engine-managed slot. Existing reserved names besides
+// MainChannel include graph-level vars VarInterruptedNode and
+// VarToolCalls (see sdk/graph).
+const MainChannel = "__main_channel"
+
+// legacyMainChannel is the pre-v0.3.0 MainChannel value (the empty
+// string). Snapshot restore paths translate it to the current
+// MainChannel so checkpoint blobs taken with older SDK builds still
+// resume cleanly. Slated for removal in v0.4.
+const legacyMainChannel = ""
 
 // Cloneable may be implemented by values stored in Board vars to
 // provide a type-safe deep copy instead of the reflection fallback used
@@ -239,6 +252,7 @@ func RestoreBoard(snap *BoardSnapshot) *Board {
 		for k, msgs := range snap.Channels {
 			b.channels[k] = model.CloneMessages(msgs)
 		}
+		migrateLegacyMainChannel(b.channels)
 	} else {
 		b.channels[MainChannel] = []model.Message{}
 	}
@@ -261,13 +275,30 @@ func (b *Board) RestoreFrom(snap *BoardSnapshot) {
 		for k, msgs := range snap.Channels {
 			b.channels[k] = model.CloneMessages(msgs)
 		}
+		migrateLegacyMainChannel(b.channels)
 	} else {
 		// Mirror RestoreBoard / NewBoard: every Board must expose
 		// MainChannel even when the snapshot didn't carry channels.
 		b.channels[MainChannel] = []model.Message{}
 	}
 }
 
+// migrateLegacyMainChannel rewrites pre-v0.3.0 checkpoint blobs that
+// used the empty-string MainChannel. If the snapshot already carries
+// the new key, the legacy key is dropped; otherwise its messages move
+// over. Slated for removal in v0.4 once all stored checkpoints have
+// been re-taken with v0.3+ writers.
+func migrateLegacyMainChannel(channels map[string][]model.Message) {
+	legacy, hasLegacy := channels[legacyMainChannel]
+	if !hasLegacy {
+		return
+	}
+	if _, hasNew := channels[MainChannel]; !hasNew {
+		channels[MainChannel] = legacy
+	}
+	delete(channels, legacyMainChannel)
+}
+
 // ---------- internal ----------
 
 func deepCopyVars(src map[string]any) map[string]any {
diff --git a/sdk/engine/doc.go b/sdk/engine/doc.go
--- a/sdk/engine/doc.go
+++ b/sdk/engine/doc.go
@@ -115,8 +115,6 @@
 //   - Strategy / Runnable / Disposition / ResumeToken — those are
 //     agent ↔ engine adapter contracts and live in sdk/agent and
 //     sdk/agent/strategy.
-//   - VarMessages / VarQuery / VarAnswer — chat conventions that
-//     belong to sdk/agent.
 //   - Engine kind enumeration — engine does not reserve a "type"
 //     namespace or list which engines exist; routing on subject is
 //     the only cross-engine identification mechanism.
diff --git a/sdk/graph/adapter/doc.go b/sdk/graph/adapter/doc.go
deleted file mode 100644
--- a/sdk/graph/adapter/doc.go
+++ /dev/null
@@ -1,8 +0,0 @@
-// Package adapter bridges graph.Graph onto the workflow.Strategy interface so
-// graph-defined runs can be hosted by the legacy workflow.Runtime.
-//
-// Deprecated: this package exists solely to wire graph into workflow.Strategy,
-// which is itself scheduled for removal in v0.3.0. New code should consume the
-// graph engine directly via graph/runner.Runner. This package will be removed
-// alongside workflow in v0.3.0.
-package adapter
diff --git a/sdk/graph/adapter/strategy.go b/sdk/graph/adapter/strategy.go
deleted file mode 100644
--- a/sdk/graph/adapter/strategy.go
+++ /dev/null
@@ -1,200 +0,0 @@
-package adapter
-
-import (
-	"context"
-	"fmt"
-	"sync"
-
-	"github.com/GizClaw/flowcraft/sdk/engine"
-	"github.com/GizClaw/flowcraft/sdk/graph"
-	"github.com/GizClaw/flowcraft/sdk/graph/node"
-	"github.com/GizClaw/flowcraft/sdk/graph/runner"
-	"github.com/GizClaw/flowcraft/sdk/workflow"
-)
-
-// ExtExecutorRunOpts is the Request.Extensions key for additional
-// runner-side options. The value MUST be []runner.Option (Runner
-// construction options); per-Run knobs that used to be
-// []executor.RunOption no longer have an equivalent — runner.Runner
-// owns them at construction time now.
-//
-// Deprecated: scheduled for removal in v0.3.0 together with the rest
-// of this adapter. Construct a runner.Runner directly and call
-// agent.Run with it instead.
-const ExtExecutorRunOpts = "adapter.executor_run_opts"
-
-// Dependency keys for SetDep / GetDep.
-const (
-	// DepNodeFactory is the workflow.Dependencies key holding a
-	// *node.Factory the adapter will use to assemble runnables.
-	DepNodeFactory = "node.factory"
-
-	// DepExecutor used to override the underlying executor
-	// implementation. With the v0.2 → v0.3 internalisation of the
-	// executor, the only execution backend is graph/runner.Runner;
-	// the dependency is read for backwards-compatibility but its
-	// value is now ignored.
-	//
-	// Deprecated: scheduled for removal in v0.3.0.
-	DepExecutor = "executor"
-)
-
-// FromDefinition returns a graph Strategy that compiles def (cached) and
-// executes via graph/runner.Runner.
-func FromDefinition(def *graph.GraphDefinition) workflow.Strategy {
-	return &graphStrategy{def: def}
-}
-
-// FromCompiled returns a Strategy that reuses a pre-compiled graph
-// (e.g. from a process-wide cache).
-func FromCompiled(cg *graph.CompiledGraph) workflow.Strategy {
-	return &compiledStrategy{cg: cg}
-}
-
-type graphStrategy struct {
-	def *graph.GraphDefinition
-	mu  sync.Mutex
-	cg  *graph.CompiledGraph
-}
-
-func (s *graphStrategy) Kind() string { return "graph" }
-
-func (s *graphStrategy) Capabilities() workflow.StrategyCapabilities {
-	return workflow.StrategyCapabilities{AnswerKey: workflow.VarAnswer}
-}
-
-func (s *graphStrategy) compiled() (*graph.CompiledGraph, error) {
-	s.mu.Lock()
-	defer s.mu.Unlock()
-	if s.cg != nil {
-		return s.cg, nil
-	}
-	if s.def == nil {
-		return nil, fmt.Errorf("adapter: nil graph definition")
-	}
-	cg, err := graph.Compile(s.def)
-	if err != nil {
-		return nil, err
-	}
-	s.cg = cg
-	return s.cg, nil
-}
-
-func (s *graphStrategy) Build(ctx context.Context, deps *workflow.Dependencies) (workflow.Runnable, error) {
-	cg, err := s.compiled()
-	if err != nil {
-		return nil, err
-	}
-	return newGraphRunnable(cg, deps)
-}
-
-type compiledStrategy struct {
-	cg *graph.CompiledGraph
-}
-
-func (s *compiledStrategy) Kind() string { return "graph" }
-
-func (s *compiledStrategy) Capabilities() workflow.StrategyCapabilities {
-	return workflow.StrategyCapabilities{AnswerKey: workflow.VarAnswer}
-}
-
-func (s *compiledStrategy) Build(ctx context.Context, deps *workflow.Dependencies) (workflow.Runnable, error) {
-	if s.cg == nil {
-		return nil, fmt.Errorf("adapter: nil compiled graph")
-	}
-	return newGraphRunnable(s.cg, deps)
-}
-
-// graphRunnable wraps a graph definition + factory in a workflow.Runnable.
-// It owns no executor of its own; instead it delegates each Execute to a
-// fresh runner.Runner that itself encapsulates the (now internal) execution
-// loop. This keeps the adapter on the same execution path as new agent.Run
-// callers, so behaviour stays identical between the workflow and agent
-// surfaces during the v0.2 → v0.3 transition.
-type graphRunnable struct {
-	def     *graph.GraphDefinition
-	cg      *graph.CompiledGraph
-	factory *node.Factory
-}
-
-func newGraphRunnable(cg *graph.CompiledGraph, deps *workflow.Dependencies) (*graphRunnable, error) {
-	fac, err := workflow.GetDep[*node.Factory](deps, DepNodeFactory)
-	if err != nil {
-		return nil, fmt.Errorf("adapter: %w", err)
-	}
-	return &graphRunnable{cg: cg, factory: fac}, nil
-}
-
-func (r *graphRunnable) Execute(ctx context.Context, board *workflow.Board, req *workflow.Request, opts ...workflow.RunOption) (*workflow.Board, error) {
-	// Recover the original GraphDefinition from the cached CompiledGraph
-	// so we can re-feed it to runner.New. The CompiledGraph carries the
-	// raw definition pieces (NodeDefs, EdgeDefs, Name, Entry) — enough
-	// for runner.New to recompile and produce a fresh executor instance.
-	def := &graph.GraphDefinition{
-		Name:  r.cg.Graph.Name,
-		Entry: r.cg.Graph.Entry,
-		Nodes: r.cg.NodeDefs,
-		Edges: r.cg.EdgeDefs,
-	}
-
-	rOpts := []runner.Option{}
-	if req != nil && req.Extensions != nil {
-		if raw, ok := req.Extensions[ExtExecutorRunOpts]; ok {
-			if sl, ok := raw.([]runner.Option); ok {
-				rOpts = append(rOpts, sl...)
-			}
-		}
-	}
-	rc := workflow.ApplyRunOpts(opts)
-	if rc.StreamCallback != nil {
-		rOpts = append(rOpts, runner.WithStreamCallback(rc.StreamCallback))
-	}
-	if rc.MaxIterations > 0 {
-		rOpts = append(rOpts, runner.WithMaxIterations(rc.MaxIterations))
-	}
-
-	rn, err := runner.New(def, r.factory, rOpts...)
-	if err != nil {
-		return board, err
-	}
-
-	gboard := graphBoardFromWorkflow(board)
-	var run engine.Run
-	if req != nil {
-		run.ID = req.RunID
-	}
-	out, runErr := rn.Execute(ctx, run, nil, gboard)
-	return workflowBoardFromGraph(out), runErr
-}
-
-// graphBoardFromWorkflow projects a *workflow.Board into a *graph.Board via
-// snapshot round-trip. Used by adapter to bridge the two now-independent
-// blackboard types until workflow is removed in v0.3.0.
-func graphBoardFromWorkflow(b *workflow.Board) *graph.Board {
-	if b == nil {
-		return graph.NewBoard()
-	}
-	wsnap := b.Snapshot()
-	if wsnap == nil {
-		return graph.NewBoard()
-	}
-	return graph.RestoreBoard(&graph.BoardSnapshot{
-		Vars:     wsnap.Vars,
-		Channels: wsnap.Channels,
-	})
-}
-
-// workflowBoardFromGraph is the inverse of graphBoardFromWorkflow.
-func workflowBoardFromGraph(b *graph.Board) *workflow.Board {
-	if b == nil {
-		return workflow.NewBoard()
-	}
-	gsnap := b.Snapshot()
-	if gsnap == nil {
-		return workflow.NewBoard()
-	}
-	return workflow.RestoreBoard(&workflow.BoardSnapshot{
-		Vars:     gsnap.Vars,
-		Channels: gsnap.Channels,
-	})
-}
diff --git a/sdk/graph/compile_analyze.go b/sdk/graph/compile_analyze.go
--- a/sdk/graph/compile_analyze.go
+++ b/sdk/graph/compile_analyze.go
@@ -17,7 +17,6 @@ func analyze(g *RawGraph, def *GraphDefinition) []Warning {
 	warnings = append(warnings, checkSkipConditions(def)...)
 	warnings = append(warnings, CheckPortCompatibility(g)...)
 	warnings = append(warnings, checkParallelJoin(g)...)
-	warnings = append(warnings, checkLLMMessagesKey(def)...)
 	return warnings
 }
 
@@ -338,36 +337,6 @@ func bfsReachableForward(succs map[string][]string, start string) map[string]boo
 	return reached
 }
 
-// checkLLMMessagesKey warns when an LLM node uses a non-default messages_key
-// without enabling query_fallback, which causes the isolated message list to
-// start empty and the LLM to receive no user input.
-func checkLLMMessagesKey(def *GraphDefinition) []Warning {
-	var warnings []Warning
-	for _, nd := range def.Nodes {
-		if nd.Type != "llm" {
-			continue
-		}
-		mk, _ := nd.Config["messages_key"].(string)
-		if mk == "" || mk == "messages" {
-			continue
-		}
-		qf, _ := nd.Config["query_fallback"].(bool)
-		if qf {
-			continue
-		}
-		warnings = append(warnings, Warning{
-			Code: "llm_isolated_messages_no_fallback",
-			Message: fmt.Sprintf(
-				"node %q uses messages_key=%q but query_fallback is not enabled; "+
-					"the isolated message list starts empty so the LLM receives no user input — "+
-					"set query_fallback=true or use the default messages_key",
-				nd.ID, mk),
-			NodeIDs: []string{nd.ID},
-		})
-	}
-	return warnings
-}
-
 // CheckPortCompatibility checks if connected nodes have compatible port types.
 func CheckPortCompatibility(g *RawGraph) []Warning {
 	var warnings []Warning
diff --git a/sdk/graph/core.go b/sdk/graph/core.go
--- a/sdk/graph/core.go
+++ b/sdk/graph/core.go
@@ -14,14 +14,12 @@
 //	condition.go   compiled boolean expressions for edge / skip conditions
 //	stream.go      StreamPublisher abstraction handed to nodes
 //	vars.go        well-known board variable keys
-//	deprecated.go  legacy aliases scheduled for removal in v0.3.0
 package graph
 
 import (
 	"context"
 
 	"github.com/GizClaw/flowcraft/sdk/engine"
-	"github.com/GizClaw/flowcraft/sdk/errdefs"
 )
 
 // ---------------------------------------------------------------------------
@@ -31,14 +29,6 @@ import (
 // END is a sentinel node ID that marks the end of execution.
 const END = "__end__"
 
-// ErrInterrupt is the legacy graceful-exit sentinel returned by nodes.
-//
-// Deprecated: prefer engine.Interrupted(engine.Interrupt{Cause: …}) which
-// carries a typed Cause and Detail; the executor classifies both via
-// errdefs.IsInterrupted so they share the resume code path. Scheduled for
-// removal in v0.3.0.
-var ErrInterrupt = errdefs.Interrupted(errdefs.New("execution interrupted"))
-
 // ---------------------------------------------------------------------------
 // Node interface family
 //
@@ -87,19 +77,11 @@ type PortDeclarable interface {
 // Publisher is a thin wrapper around Host.Publish kept for backwards
 // compatibility and ergonomic event emission with (type, payload) pairs;
 // new code MAY call Host.Publish directly with a fully formed envelope.
-//
-// Stream is the legacy callback-based sink scheduled for removal in v0.3.0.
 type ExecutionContext struct {
 	Context   context.Context
 	Host      engine.Host
 	Publisher StreamPublisher
-	// Stream is the legacy callback-based sink for streaming deltas.
-	//
-	// Deprecated: use Publisher.Emit instead. The executor still populates
-	// this field via a shim that forwards to Publisher, so existing nodes
-	// continue to work; scheduled for removal in v0.3.0.
-	Stream StreamCallback
-	RunID  string
+	RunID     string
 }
 
 // ---------------------------------------------------------------------------
diff --git a/sdk/graph/deprecated.go b/sdk/graph/deprecated.go
deleted file mode 100644
--- a/sdk/graph/deprecated.go
+++ /dev/null
@@ -1,30 +0,0 @@
-package graph
-
-// This file collects graph-level types and functions scheduled for removal in
-// v0.3.0. Keeping them isolated lets the rest of the package evolve free of
-// the legacy stream-callback model while existing callers keep compiling.
-//
-// Items here may import workflow because they only exist to bridge the
-// workflow-era APIs; the active graph surface (vars.go, board.go, graph.go,
-// stream.go, validate.go, …) does not depend on workflow.
-
-import (
-	"github.com/GizClaw/flowcraft/sdk/workflow"
-)
-
-// StreamEvent carries a streaming event emitted by a node during execution.
-//
-// Deprecated: prefer event.Envelope payloads delivered via event.Bus and
-// produced through StreamPublisher. Aliased to workflow.StreamEvent so legacy
-// callers passing workflow-typed callbacks keep compiling; scheduled for
-// removal in v0.3.0 along with ExecutionContext.Stream and
-// executor.WithStreamCallback.
-type StreamEvent = workflow.StreamEvent
-
-// StreamCallback receives streaming events during execution.
-//
-// Deprecated: use StreamPublisher (handed to nodes via ExecutionContext.Publisher)
-// or subscribe directly to the configured event.Bus. Aliased to
-// workflow.StreamCallback so legacy code paths interoperate without explicit
-// conversion; scheduled for removal in v0.3.0.
-type StreamCallback = workflow.StreamCallback
diff --git a/sdk/graph/node/knowledgenode/knowledgenode.go b/sdk/graph/node/knowledgenode/knowledgenode.go
--- a/sdk/graph/node/knowledgenode/knowledgenode.go
+++ b/sdk/graph/node/knowledgenode/knowledgenode.go
@@ -13,23 +13,37 @@ import (
 	"go.opentelemetry.io/otel/trace"
 )
 
+type DatasetQuery struct {
+	DatasetID string `json:"dataset_id"`
+	StateKey  string `json:"state_key"`
+	TopK      int    `json:"top_k"`
+}
+
 // Config configures a knowledge graph node.
 //
 // Field semantics:
+//   - QueryKey  names the board var the node reads as the search query;
+//     empty means [DefaultQueryKey] ("query").
 //   - Scope     selects whether to search a specific dataset list (Datasets)
 //     or every known dataset (knowledge.ScopeAllDatasets).
 //   - Datasets  is consulted only when Scope == knowledge.ScopeSingleDataset;
 //     each entry can override TopK and choose a board key for its hits.
 //   - Mode/Layer/TopK/Threshold are forwarded into knowledge.Query.
 type Config struct {
-	Scope     knowledge.Scope          `json:"scope,omitempty"`
-	Datasets  []knowledge.DatasetQuery `json:"datasets,omitempty"`
-	Mode      knowledge.Mode           `json:"mode,omitempty"`
-	Layer     knowledge.Layer          `json:"layer,omitempty"`
-	TopK      int                      `json:"top_k,omitempty"`
-	Threshold float64                  `json:"threshold,omitempty"`
+	QueryKey  string          `json:"query_key,omitempty"`
+	Scope     knowledge.Scope `json:"scope,omitempty"`
+	Datasets  []DatasetQuery  `json:"datasets,omitempty"`
+	Mode      knowledge.Mode  `json:"mode,omitempty"`
+	Layer     knowledge.Layer `json:"layer,omitempty"`
+	TopK      int             `json:"top_k,omitempty"`
+	Threshold float64         `json:"threshold,omitempty"`
 }
 
+// DefaultQueryKey is the board-var key the node reads when Config.QueryKey
+// is empty. Held as a constant rather than a magic string so callers can
+// reference it from BoardSeeders / tests without hard-coding "query".
+const DefaultQueryKey = "query"
+
 // Node is a graph node that retrieves documents from a knowledge.Service.
 // It delegates to Service so contract guarantees (Mode/Layer normalisation,
 // dataset fan-out, RRF fusion) live in one place.
@@ -64,11 +78,19 @@ func (n *Node) SetConfig(c map[string]any) {
 // InputPorts implements graph.Node.
 func (n *Node) InputPorts() []graph.Port {
 	return []graph.Port{
-		{Name: "query", Type: graph.PortTypeString, Required: true},
+		{Name: n.queryKey(), Type: graph.PortTypeString, Required: true},
 		{Name: "dataset_id", Type: graph.PortTypeString},
 	}
 }
 
+// queryKey returns the board-var key the node reads as the search query.
+func (n *Node) queryKey() string {
+	if n.cfg.QueryKey == "" {
+		return DefaultQueryKey
+	}
+	return n.cfg.QueryKey
+}
+
 // OutputPorts implements graph.Node. New callers should consume "hits"
 // (typed []knowledge.Hit) and "by_dataset"; "results" carries the same
 // content projected into []map[string]any for compatibility with older
@@ -86,7 +108,7 @@ func (n *Node) OutputPorts() []graph.Port {
 // every known dataset (ScopeAllDatasets), then publishes the hits onto
 // the board under "hits" / "by_dataset" / "results".
 func (n *Node) ExecuteBoard(ectx graph.ExecutionContext, board *graph.Board) error {
-	queryVal, _ := board.GetVar("query")
+	queryVal, _ := board.GetVar(n.queryKey())
 	query := fmt.Sprint(queryVal)
 
 	if n.svc == nil {
@@ -120,7 +142,7 @@ func (n *Node) ExecuteBoard(ectx graph.ExecutionContext, board *graph.Board) err
 		// Allow boards that pass dataset_id at runtime: fall back to
 		// a single anonymous dataset query when none was configured.
 		if id, ok := board.GetVar("dataset_id"); ok {
-			datasets = []knowledge.DatasetQuery{{DatasetID: fmt.Sprint(id), TopK: topK}}
+			datasets = []DatasetQuery{{DatasetID: fmt.Sprint(id), TopK: topK}}
 		}
 	}
 	for _, dq := range datasets {
@@ -211,6 +233,9 @@ func hitsToCompatSlice(hits []knowledge.Hit) []map[string]any {
 //   - "scope" accepts "single" (default) and "all".
 func ConfigFromMap(m map[string]any) Config {
 	cfg := Config{}
+	if v, ok := m["query_key"].(string); ok {
+		cfg.QueryKey = v
+	}
 	if v, ok := m["scope"].(string); ok && v == "all" {
 		cfg.Scope = knowledge.ScopeAllDatasets
 	}
@@ -244,8 +269,8 @@ func ConfigFromMap(m map[string]any) Config {
 	return cfg
 }
 
-func datasetQueryFromMap(m map[string]any) knowledge.DatasetQuery {
-	dq := knowledge.DatasetQuery{}
+func datasetQueryFromMap(m map[string]any) DatasetQuery {
+	dq := DatasetQuery{}
 	if v, ok := m["dataset_id"].(string); ok {
 		dq.DatasetID = v
 	}
diff --git a/sdk/graph/node/llmnode/llmnode.go b/sdk/graph/node/llmnode/llmnode.go
--- a/sdk/graph/node/llmnode/llmnode.go
+++ b/sdk/graph/node/llmnode/llmnode.go
@@ -19,27 +19,31 @@ import (
 
 // Config configures an LLM graph node. Fields fall into two groups:
 //
-//   - Graph-level board I/O: SystemPrompt, OutputKey, MessagesKey,
-//     QueryFallback, TrackSteps — consumed by Node.ExecuteBoard around
-//     the round boundary.
+//   - Graph-level board I/O: SystemPrompt, OutputKey, MessagesChannel,
+//     TrackSteps — consumed by Node.ExecuteBoard around the round boundary.
 //   - Pure LLM call parameters: Model, Temperature, MaxTokens, JSONMode,
 //     Thinking, ToolNames — forwarded into the in-package round driver
 //     via Config.generateOptions.
 //
 // The split exists to keep the round driver (round.go) ignorant of the
 // graph board, which is essential for testing it in isolation.
+//
+// MessagesChannel selects the typed-message channel the node reads from
+// and writes to. The empty string (zero value) means [graph.MainChannel],
+// shared by every LLM node in the graph. Any other name produces an
+// "isolated" channel; an upstream node (or the caller) is responsible
+// for seeding it with at least one message before the node runs.
 type Config struct {
-	SystemPrompt  string   `json:"system_prompt" yaml:"system_prompt"`
-	Model         string   `json:"model,omitempty" yaml:"model,omitempty"`
-	Temperature   *float64 `json:"temperature,omitempty" yaml:"temperature,omitempty"`
-	MaxTokens     int64    `json:"max_tokens,omitempty" yaml:"max_tokens,omitempty"`
-	OutputKey     string   `json:"output_key,omitempty" yaml:"output_key,omitempty"`
-	MessagesKey   string   `json:"messages_key,omitempty" yaml:"messages_key,omitempty"`
-	JSONMode      bool     `json:"json_mode,omitempty" yaml:"json_mode,omitempty"`
-	Thinking      bool     `json:"thinking,omitempty" yaml:"thinking,omitempty"`
-	QueryFallback bool     `json:"query_fallback,omitempty" yaml:"query_fallback,omitempty"`
-	TrackSteps    bool     `json:"track_steps,omitempty" yaml:"track_steps,omitempty"`
-	ToolNames     []string `json:"tool_names,omitempty" yaml:"tool_names,omitempty"`
+	SystemPrompt    string   `json:"system_prompt" yaml:"system_prompt"`
+	Model           string   `json:"model,omitempty" yaml:"model,omitempty"`
+	Temperature     *float64 `json:"temperature,omitempty" yaml:"temperature,omitempty"`
+	MaxTokens       int64    `json:"max_tokens,omitempty" yaml:"max_tokens,omitempty"`
+	OutputKey       string   `json:"output_key,omitempty" yaml:"output_key,omitempty"`
+	MessagesChannel string   `json:"messages_channel,omitempty" yaml:"messages_channel,omitempty"`
+	JSONMode        bool     `json:"json_mode,omitempty" yaml:"json_mode,omitempty"`
+	Thinking        bool     `json:"thinking,omitempty" yaml:"thinking,omitempty"`
+	TrackSteps      bool     `json:"track_steps,omitempty" yaml:"track_steps,omitempty"`
+	ToolNames       []string `json:"tool_names,omitempty" yaml:"tool_names,omitempty"`
 }
 
 // Node is a Go-native graph node that calls an LLM, dispatches tool calls,
@@ -78,7 +82,7 @@ func (n *Node) SetConfig(c map[string]any) {
 
 func (n *Node) InputPorts() []graph.Port {
 	return []graph.Port{
-		{Name: graph.VarMessages, Type: graph.PortTypeMessages, Required: true},
+		{Name: n.channelName(), Type: graph.PortTypeMessages, Required: true},
 	}
 }
 
@@ -89,28 +93,42 @@ func (n *Node) OutputPorts() []graph.Port {
 	}
 	return []graph.Port{
 		{Name: outputKey, Type: graph.PortTypeString, Required: true},
-		{Name: graph.VarMessages, Type: graph.PortTypeMessages, Required: true},
+		{Name: n.channelName(), Type: graph.PortTypeMessages, Required: true},
 		{Name: VarUsage, Type: graph.PortTypeUsage, Required: true},
 		{Name: VarToolPending, Type: graph.PortTypeBool, Required: true},
 	}
 }
 
+// channelName returns the typed-message channel this node binds to.
+// Empty MessagesChannel maps to [graph.MainChannel] (shared transcript);
+// any other value names an isolated per-node channel.
+func (n *Node) channelName() string {
+	if n.config.MessagesChannel == "" {
+		return graph.MainChannel
+	}
+	return n.config.MessagesChannel
+}
+
 func (n *Node) ExecuteBoard(ctx graph.ExecutionContext, board *graph.Board) error {
 	_, span := telemetry.Tracer().Start(ctx.Context, "node.llm.execute",
 		trace.WithAttributes(attribute.String(telemetry.AttrNodeID, n.id)))
 	defer span.End()
 
 	cfg := n.config
-	messagesKey := cfg.MessagesKey
-	if messagesKey == "" {
-		messagesKey = graph.VarMessages
-	}
-	chName := messagesKey
-	if chName == graph.VarMessages {
-		chName = graph.MainChannel
-	}
+	chName := n.channelName()
 
-	messages := n.buildMessages(cfg, board, chName, messagesKey)
+	messages := n.buildMessages(cfg, board, chName)
+	if len(messages) == 0 {
+		// Empty channel + no system prompt → nothing to send. This is
+		// always a graph wiring mistake (no upstream node populated the
+		// channel and the operator did not configure a system prompt);
+		// fail fast with a clear message rather than emitting a
+		// provider-dependent error (Anthropic 400, OpenAI silent
+		// behaviour, …) that varies across the LLM stack.
+		return errdefs.Validationf(
+			"llm node %q has nothing to send: messages_channel %q is empty and system_prompt is unset",
+			n.id, chName)
+	}
 	if _, ok := board.GetVar(VarPrevMessageCount); !ok {
 		board.SetVar(VarPrevMessageCount, len(messages))
 	}
@@ -129,7 +147,7 @@ func (n *Node) ExecuteBoard(ctx graph.ExecutionContext, board *graph.Board) erro
 	// what materialises the partial assistant message + cancelled
 	// tool_results onto the board so the agent layer / memory writer
 	// can read them after the resume / discard decision.
-	if werr := n.writeResults(ctx, board, cfg, result, messagesKey, chName); werr != nil {
+	if werr := n.writeResults(ctx, board, cfg, result, chName); werr != nil {
 		// writeResults only ever surfaces errors from the host's
 		// budget / quota gate (UsageReporter). Propagate so the
 		// run terminates rather than silently exceeding the budget,
@@ -159,15 +177,10 @@ func (n *Node) ExecuteBoard(ctx graph.ExecutionContext, board *graph.Board) erro
 	return nil
 }
 
-func (n *Node) buildMessages(cfg Config, board *graph.Board, chName, messagesKey string) []llm.Message {
-	var messages []llm.Message
-	if msgs := board.Channel(chName); len(msgs) > 0 {
-		messages = msgs
-	} else if existing, ok := board.GetVar(messagesKey); ok {
-		if msgs, ok := existing.([]llm.Message); ok {
-			messages = append([]llm.Message(nil), msgs...)
-		}
-	}
+func (n *Node) buildMessages(cfg Config, board *graph.Board, chName string) []llm.Message {
+	// Defensive copy: we mutate the slice below (system-prompt prepend,
+	// summary-index injection) and must not write back into board state.
+	messages := append([]llm.Message(nil), board.Channel(chName)...)
 
 	if cfg.SystemPrompt != "" {
 		hasSystem := false
@@ -193,30 +206,12 @@ func (n *Node) buildMessages(cfg Config, board *graph.Board, chName, messagesKey
 		}
 	}
 
-	if cfg.QueryFallback && messagesKey != graph.VarMessages {
-		if query, ok := board.GetVar(graph.VarQuery); ok {
-			if qs, ok := query.(string); ok && qs != "" {
-				needAppend := true
-				for i := len(messages) - 1; i >= 0; i-- {
-					if messages[i].Role == llm.RoleUser {
-						if messages[i].Content() == qs {
-							needAppend = false
-						}
-						break
-					}
-				}
-				if needAppend {
-					messages = append(messages, llm.NewTextMessage(llm.RoleUser, qs))
-				}
-			}
-		}
-	}
 	return messages
 }
 
 func (n *Node) writeResults(
 	ctx graph.ExecutionContext, board *graph.Board, cfg Config,
-	result *roundResult, messagesKey, chName string,
+	result *roundResult, chName string,
 ) error {
 	if cfg.TrackSteps {
 		steps, _ := board.GetVar("agent_steps")
@@ -262,7 +257,6 @@ func (n *Node) writeResults(
 		board.SetVar(outputKey, result.Content)
 	}
 
-	board.SetVar(messagesKey, result.Messages)
 	board.SetChannel(chName, result.Messages)
 	board.SetVar(VarToolPending, result.ToolPending)
 
diff --git a/sdk/graph/node/llmnode/round.go b/sdk/graph/node/llmnode/round.go
--- a/sdk/graph/node/llmnode/round.go
+++ b/sdk/graph/node/llmnode/round.go
@@ -21,9 +21,8 @@ import (
 //     them once via tool.Registry.ExecuteAll and stop. Multi-turn loops
 //     are the graph's job (loopguard + condition edges), not the round's.
 //   - Streaming events flow into graph.StreamPublisher as token / tool_call
-//     / tool_result envelopes; the executor fans them onto the event bus
-//     and the deprecated StreamCallback shim if a legacy caller registered
-//     one.
+//     / tool_result envelopes; the executor forwards them to the run's
+//     engine.Host.Publish.
 //   - Cooperative interrupts (engine.Host.Interrupts()) are observed
 //     between every chunk in the streaming loop. On interrupt, runRound
 //     returns a roundResult with Interrupted set; ExecuteBoard commits
diff --git a/sdk/graph/node/scriptnode/jsnode.go b/sdk/graph/node/scriptnode/jsnode.go
--- a/sdk/graph/node/scriptnode/jsnode.go
+++ b/sdk/graph/node/scriptnode/jsnode.go
@@ -55,10 +55,6 @@ func (n *ScriptNode) ExecuteBoard(ctx graph.ExecutionContext, board *graph.Board
 		bindings.NewBoardBridge(board),
 		bindings.NewExprBridge(),
 		bindings.NewHostBridge(ctx.Host, n.id),
-		// NewStreamBridge is deprecated and scheduled for removal in
-		// v0.3.0; the executor still threads ctx.Stream so legacy
-		// scripts using stream.emit keep working until then.
-		bindings.NewStreamBridge(ctx.Stream, n.id),
 	}
 	allFns = append(allFns, n.extraBindFn...)
 
diff --git a/sdk/graph/port.go b/sdk/graph/port.go
--- a/sdk/graph/port.go
+++ b/sdk/graph/port.go
@@ -57,7 +57,7 @@ func ValidateInputsWithConfig(b *Board, node PortDeclarable, config map[string]a
 		if _, ok := b.GetVar(p.Name); ok {
 			continue
 		}
-		if (p.Name == VarMessages || p.Type == PortTypeMessages) && len(b.Channel(MainChannel)) > 0 {
+		if p.Type == PortTypeMessages && len(b.Channel(p.Name)) > 0 {
 			continue
 		}
 		if config != nil {
diff --git a/sdk/graph/runner/internal/executor/checkpoint.go b/sdk/graph/runner/internal/executor/checkpoint.go
--- a/sdk/graph/runner/internal/executor/checkpoint.go
+++ b/sdk/graph/runner/internal/executor/checkpoint.go
@@ -1,7 +1,6 @@
 package executor
 
 import (
-	"context"
 	"encoding/json"
 	"fmt"
 	"os"
@@ -15,12 +14,6 @@ import (
 )
 
 // Checkpoint represents a snapshot of graph execution state.
-//
-// Deprecated: use engine.Checkpoint. This type predates the
-// engine.Host.Checkpointer abstraction; the executor now persists
-// checkpoints through the host. Scheduled for removal in v0.3.0
-// together with WithCheckpointStore. Existing CheckpointStore
-// implementations keep working via storeOnlyHost.
 type Checkpoint struct {
 	GraphName string               `json:"graph_name"`
 	RunID     string               `json:"run_id,omitempty"`
@@ -49,27 +42,7 @@ func (c Checkpoint) toEngine() engine.Checkpoint {
 	}
 }
 
-// checkpointFromEngine is the inverse of toEngine. Used by storeOnlyHost
-// when the executor (now host-driven) hands a checkpoint back to a
-// legacy CheckpointStore.
-func checkpointFromEngine(cp engine.Checkpoint) Checkpoint {
-	return Checkpoint{
-		GraphName: cp.Attributes["graph_name"],
-		RunID:     cp.ExecID,
-		NodeID:    cp.Step,
-		Iteration: cp.Iteration,
-		Board:     cp.Board,
-		Timestamp: cp.Timestamp,
-	}
-}
-
 // CheckpointStore is the interface for persisting and loading checkpoints.
-//
-// Deprecated: implement engine.CheckpointStore (or expose a Host with a
-// real Checkpointer) and pass it via WithHost. The executor now writes
-// every checkpoint through host.Checkpoint; this interface is kept so
-// code already using WithCheckpointStore keeps compiling and is folded
-// into the host path via storeOnlyHost. Scheduled for removal in v0.3.0.
 type CheckpointStore interface {
 	Save(cp Checkpoint) error
 	// Load retrieves the latest checkpoint. When runID is non-empty, only
@@ -308,61 +281,3 @@ func (s *FileCheckpointStore) cleanOldVersions(cp Checkpoint) {
 		_ = os.Remove(v.path)
 	}
 }
-
-// storeOnlyHost adapts a deprecated executor.CheckpointStore into a
-// full engine.Host so the executor's main path can rely on a single
-// Checkpoint sink (host.Checkpoint) without branching on store vs host.
-//
-// It mirrors busOnlyHost (the runner.WithEventBus shim): every Host
-// method other than Checkpoint is inherited from the embedded base
-// host (typically engine.NoopHost{}). Checkpoint converts the engine
-// canonical form back to the legacy struct and forwards to the store.
-//
-// Deprecated: scheduled for removal in v0.3.0 together with
-// executor.WithCheckpointStore. New code should pass a real
-// engine.Host whose Checkpointer talks to engine.CheckpointStore
-// directly.
-type storeOnlyHost struct {
-	engine.Host
-	store CheckpointStore
-}
-
-// Checkpoint forwards to the wrapped legacy store. Errors are
-// swallowed at the call site (executor) by convention so a failing
-// observer never aborts a run; the host contract here just propagates
-// whatever the store reported so callers that wrap us can still log.
-func (h storeOnlyHost) Checkpoint(_ context.Context, cp engine.Checkpoint) error {
-	if h.store == nil {
-		return nil
-	}
-	return h.store.Save(checkpointFromEngine(cp))
-}
-
-// resolveCheckpointHost folds a legacy CheckpointStore into the
-// modern host so the executor only has one Checkpointer to call.
-//
-// Resolution rules (mirroring resolvePublisher):
-//   - host alone: use it as-is.
-//   - store alone: wrap in storeOnlyHost{NoopHost, store}.
-//   - both: host wins; the legacy store is ignored. Checkpointing is
-//     state, not observability — writing to two backends invites
-//     conflicting reads, so we deliberately do NOT fan out the way
-//     resolvePublisher does for envelopes. The deprecation comment on
-//     WithCheckpointStore tells callers to drop it once they wire a
-//     real host.
-//   - neither: host stays NoopHost{}, Checkpoint becomes a no-op.
-//
-// Returned host is always non-nil so the executor can call
-// host.Checkpoint unconditionally.
-func resolveCheckpointHost(host engine.Host, store CheckpointStore) engine.Host {
-	switch {
-	case host == nil && store == nil:
-		return engine.NoopHost{}
-	case store == nil:
-		return host
-	case host == nil:
-		return storeOnlyHost{Host: engine.NoopHost{}, store: store}
-	default:
-		return host
-	}
-}
diff --git a/sdk/graph/runner/internal/executor/executor.go b/sdk/graph/runner/internal/executor/executor.go
--- a/sdk/graph/runner/internal/executor/executor.go
+++ b/sdk/graph/runner/internal/executor/executor.go
@@ -9,7 +9,6 @@ import (
 
 	"github.com/GizClaw/flowcraft/sdk/engine"
 	"github.com/GizClaw/flowcraft/sdk/errdefs"
-	"github.com/GizClaw/flowcraft/sdk/event"
 	"github.com/GizClaw/flowcraft/sdk/graph"
 	"github.com/GizClaw/flowcraft/sdk/graph/variable"
 	"github.com/GizClaw/flowcraft/sdk/telemetry"
@@ -47,19 +46,6 @@ var (
 
 const defaultMaxIterations = 200
 
-// Executor is the interface for graph execution engines.
-//
-// Deprecated: superseded by [engine.Engine] (satisfied by
-// graph/runner.Runner). The new contract folds run identity / host /
-// initial board into typed parameters, which lets the agent runtime
-// drive any engine uniformly without reaching into a Strategy layer.
-// Scheduled for removal in v0.3.0; until then the LocalExecutor that
-// implements this interface is kept as the in-process default the
-// runner delegates to internally.
-type Executor interface {
-	Execute(ctx context.Context, g *graph.Graph, board *graph.Board, opts ...RunOption) (*graph.Board, error)
-}
-
 // RunOption configures a single graph execution run.
 type RunOption func(*runConfig)
 
@@ -109,35 +95,11 @@ type runConfig struct {
 	// going forward; defaulted to engine.NoopHost{} in Execute when
 	// the caller doesn't supply WithHost.
 	host engine.Host
-	// bus is a write-only slot used by the deprecated WithEventBus
-	// option. Execute reads it once via resolvePublisher to fold it
-	// into publisher; nothing else in the executor consults it.
-	//
-	// Deprecated: scheduled for removal in v0.3.0 together with
-	// WithEventBus. Do NOT add new reads.
-	bus event.Bus
-	// streamCallback is the legacy per-node delta sink set by
-	// WithStreamCallback. newNodePublisher fans every emit to it for
-	// v0.2 backwards compatibility; new code should subscribe to the
-	// host's event stream instead.
-	//
-	// Deprecated: scheduled for removal in v0.3.0 together with
-	// WithStreamCallback. Do NOT add new reads.
-	streamCallback graph.StreamCallback
-	// checkpointStore is a write-only slot used by the deprecated
-	// WithCheckpointStore option. Execute reads it once via
-	// resolveCheckpointHost to fold it into cfg.host before the main
-	// loop runs; nothing else in the executor consults it.
-	//
-	// Deprecated: scheduled for removal in v0.3.0 together with
-	// WithCheckpointStore. Do NOT add new reads.
-	checkpointStore CheckpointStore
-
 	// --- derived (set by Execute) ---
 
 	// publisher is the single event sink consumed by every
 	// publishGraph/publishNode and newNodePublisher call. Built once
-	// in Execute from host + bus; never read before that.
+	// in Execute from host; never read before that.
 	publisher engine.Publisher
 
 	nodeLocks *nodeConfigLocks
@@ -150,32 +112,12 @@ type nodeConfigLocks struct {
 
 // WithRunID sets the run identifier the executor uses in telemetry and
 // event subjects.
-//
-// Deprecated: pass [engine.Run.ID] to [engine.Engine.Execute] (i.e. via
-// agent.Run, which mints and forwards it for you). When invoking
-// [graph/runner.Runner] directly through engine.Engine.Execute, the
-// run.ID parameter is the canonical source. Scheduled for removal in
-// v0.3.0 once executor.Executor is removed.
 func WithRunID(id string) RunOption         { return func(c *runConfig) { c.runID = id } }
 func WithMaxIterations(n int) RunOption     { return func(c *runConfig) { c.maxIterations = n } }
 func WithMaxNodeRetries(n int) RunOption    { return func(c *runConfig) { c.maxNodeRetries = n } }
 func WithTimeout(d time.Duration) RunOption { return func(c *runConfig) { c.timeout = d } }
 func WithStartNode(id string) RunOption     { return func(c *runConfig) { c.startNode = id } }
 
-// WithCheckpointStore installs a graph-format CheckpointStore that
-// persists a checkpoint after every node completes.
-//
-// Deprecated: prefer WithHost with a host whose Checkpointer wraps an
-// engine.CheckpointStore. The executor now writes every checkpoint
-// through host.Checkpoint and the store passed here is folded into
-// the host via storeOnlyHost (see resolveCheckpointHost). When BOTH
-// WithHost and WithCheckpointStore are supplied the host wins and the
-// store is silently ignored — checkpointing is state, so we do not
-// fan out the way we do for events. Scheduled for removal in v0.3.0.
-func WithCheckpointStore(s CheckpointStore) RunOption {
-	return func(c *runConfig) { c.checkpointStore = s }
-}
-
 func WithParallel(cfg ParallelConfig) RunOption {
 	return func(c *runConfig) {
 		if cfg.MaxBranches <= 0 {
@@ -194,39 +136,14 @@ func WithParallel(cfg ParallelConfig) RunOption {
 // WithHost installs the engine.Host the executor will hand to nodes via
 // ExecutionContext.Host. When omitted the executor falls back to
 // engine.NoopHost{} so nodes can call ctx.Host methods unconditionally.
-//
-// WithHost subsumes WithEventBus / WithCheckpointStore: when both are
-// supplied the host wins for publishing and checkpointing while the bus /
-// store remain available for legacy code paths during the transition.
 func WithHost(h engine.Host) RunOption {
 	return func(c *runConfig) { c.host = h }
 }
 
-// WithEventBus installs the event bus used for graph- and node-level
-// envelopes.
-//
-// Deprecated: pass an engine.Host to WithHost instead — the executor now
-// publishes envelopes through host.Publish, which lets the host
-// centralise routing, fan-out and observability. Scheduled for removal in
-// v0.3.0 alongside the other host-overlapping options.
-func WithEventBus(bus event.Bus) RunOption {
-	return func(c *runConfig) { c.bus = bus }
-}
-
 func WithResolver(r VariableResolver) RunOption {
 	return func(c *runConfig) { c.resolver = r }
 }
 
-// WithStreamCallback installs a legacy stream callback receiving every
-// node delta.
-//
-// Deprecated: subscribe to engine.Host's event bus, or read
-// ExecutionContext.Publisher inside a node, instead. Scheduled for
-// removal in v0.3.0.
-func WithStreamCallback(cb graph.StreamCallback) RunOption {
-	return func(c *runConfig) { c.streamCallback = cb }
-}
-
 // LocalExecutor is the default single-process executor.
 type LocalExecutor struct{}
 
@@ -247,23 +164,12 @@ func (e *LocalExecutor) Execute(ctx context.Context, g *graph.Graph, board *grap
 
 	cfg.graphName = g.Name()
 
-	// Resolve the deprecated WithCheckpointStore into a host BEFORE
-	// defaulting cfg.host to NoopHost — the resolver needs to see a
-	// nil host as the signal "user only configured the store, wrap
-	// it". Once this returns cfg.host is the canonical Checkpointer
-	// the rest of the executor will use.
-	cfg.host = resolveCheckpointHost(cfg.host, cfg.checkpointStore)
-
 	// cfg.host backs ExecutionContext.Host so nodes can call Host
 	// methods (Publish / Interrupts / AskUser / ...) unconditionally.
 	if cfg.host == nil {
 		cfg.host = engine.NoopHost{}
 	}
-
-	// resolvePublisher is the single seam where event sinks are
-	// chosen. After this line cfg.bus is invisible to the rest of
-	// the executor — every dispatch site reads cfg.publisher.
-	cfg.publisher = resolvePublisher(cfg.host, cfg.bus)
+	cfg.publisher = cfg.host
 
 	actorKey := actorKeyFrom(ctx)
 
@@ -433,11 +339,9 @@ func (e *LocalExecutor) Execute(ctx context.Context, g *graph.Graph, board *grap
 
 			// Checkpoint through the host. host is always non-nil
 			// (NoopHost when the caller didn't configure one), so
-			// no guard is needed. WithCheckpointStore callers have
-			// already been folded into the host via storeOnlyHost
-			// up in Execute. Errors are intentionally swallowed —
-			// checkpointing is observability-adjacent, never a
-			// reason to abort a run.
+			// no guard is needed. Errors are intentionally
+			// swallowed — checkpointing is observability-adjacent,
+			// never a reason to abort a run.
 			cp := Checkpoint{
 				GraphName: g.Name(),
 				RunID:     cfg.runID,
diff --git a/sdk/graph/runner/internal/executor/publisher.go b/sdk/graph/runner/internal/executor/publisher.go
--- a/sdk/graph/runner/internal/executor/publisher.go
+++ b/sdk/graph/runner/internal/executor/publisher.go
@@ -4,92 +4,22 @@ import (
 	"context"
 
 	"github.com/GizClaw/flowcraft/sdk/engine"
-	"github.com/GizClaw/flowcraft/sdk/event"
 	"github.com/GizClaw/flowcraft/sdk/graph"
 )
 
-// publisherFunc adapts a plain function into engine.Publisher so the
-// executor can compose / fan out without leaking implementation types.
-// It mirrors http.HandlerFunc / graph.StreamPublisherFunc and lives
-// inside the executor package because engine intentionally keeps its
-// public surface minimal.
-type publisherFunc func(ctx context.Context, env event.Envelope) error
-
-// Publish satisfies engine.Publisher.
-func (f publisherFunc) Publish(ctx context.Context, env event.Envelope) error {
-	if f == nil {
-		return nil
-	}
-	return f(ctx, env)
-}
-
-// resolvePublisher collapses the executor's two possible event inputs
-// (cfg.host — modern; cfg.bus — deprecated WithEventBus) into a single
-// engine.Publisher consumed by the rest of the executor. The result is
-// always non-nil so call sites never need to nil-check.
-//
-// Resolution rules:
-//   - host alone: host is the publisher (Host implements Publisher).
-//   - bus  alone: wrap bus so it satisfies Publisher.
-//   - both: fan out to host AND bus, ignoring per-sink errors so a
-//     clogged observer never aborts a run ("events are observability,
-//     not control flow").
-//   - neither: NoopHost{}.
-//
-// This helper is the single seam where the deprecated bus path enters
-// the executor. After Execute calls it, cfg.bus is read by no other
-// code; the rest of the executor only touches cfg.publisher.
-func resolvePublisher(host engine.Host, bus event.Bus) engine.Publisher {
-	hostNonNil := host != nil
-	busNonNil := bus != nil && !isNoopBus(bus)
-	switch {
-	case !hostNonNil && !busNonNil:
-		return engine.NoopHost{}
-	case !busNonNil:
-		return host
-	case !hostNonNil:
-		return publisherFunc(func(ctx context.Context, env event.Envelope) error {
-			_ = bus.Publish(ctx, env)
-			return nil
-		})
-	default:
-		return publisherFunc(func(ctx context.Context, env event.Envelope) error {
-			_ = host.Publish(ctx, env)
-			_ = bus.Publish(ctx, env)
-			return nil
-		})
-	}
-}
-
-// isNoopBus lets resolvePublisher skip the fan-out wrapper when the
-// caller passed event.NoopBus{} explicitly (e.g. defaults set by
-// runner.New). This avoids paying for an extra closure + Publish call
-// per envelope on the common host-only path.
-func isNoopBus(bus event.Bus) bool {
-	_, ok := bus.(event.NoopBus)
-	return ok
-}
-
 // newNodePublisher builds the StreamPublisher handed to a node. The
 // node speaks the simplified (eventType, payload) shape; this wrapper
 // translates each emit into a fully-formed engine event.Envelope and
-// pushes it through the executor's composed publisher (host + optional
-// legacy bus). The deprecated StreamCallback registered via
-// WithStreamCallback is also fanned to here for v0.2 backwards
-// compatibility.
+// pushes it through the executor's host publisher.
 //
 // The wrapper is always non-nil so nodes can call ctx.Publisher.Emit
 // without nil-checks.
 func newNodePublisher(ctx context.Context, cfg runConfig, nodeID string) graph.StreamPublisher {
 	actorKey := actorKeyFrom(ctx)
 	graphName := cfg.graphName
 	pub := cfg.publisher
-	cb := cfg.streamCallback
 
 	return graph.StreamPublisherFunc(func(eventType string, payload any) {
-		if cb != nil {
-			cb(graph.StreamEvent{Type: eventType, NodeID: nodeID, Payload: payload})
-		}
 		if pub == nil {
 			return
 		}
diff --git a/sdk/graph/runner/internal/executor/retry.go b/sdk/graph/runner/internal/executor/retry.go
--- a/sdk/graph/runner/internal/executor/retry.go
+++ b/sdk/graph/runner/internal/executor/retry.go
@@ -18,7 +18,6 @@ func executeWithRetry(ctx context.Context, node graph.Node, board *graph.Board,
 
 	publisher := newNodePublisher(ctx, cfg, nodeID)
 	wrappedPublisher := wrapToolCapture(publisher, board)
-	streamShim := legacyStreamShim(wrappedPublisher)
 
 	for attempt := range maxAttempts {
 		if attempt > 0 {
@@ -35,17 +34,17 @@ func executeWithRetry(ctx context.Context, node graph.Node, board *graph.Board,
 			Context:   ctx,
 			Host:      cfg.host,
 			Publisher: wrappedPublisher,
-			Stream:    streamShim,
 			RunID:     cfg.runID,
 		}
 
 		lastErr = node.ExecuteBoard(execCtx, board)
 		if lastErr == nil {
 			return nil
 		}
-		// Both legacy graph.ErrInterrupt and engine.Interrupted satisfy
-		// errdefs.IsInterrupted, so we never retry an interrupted node
-		// regardless of which sentinel the node chose.
+		// Cooperative interrupts (engine.Interrupted) are never retried:
+		// the node returned with intent, not failure, so re-running would
+		// either burn budget on a duplicate side effect or simply trip
+		// the same interrupt again.
 		if errdefs.IsInterrupted(lastErr) {
 			return lastErr
 		}
@@ -82,19 +81,6 @@ func wrapToolCapture(inner graph.StreamPublisher, board *graph.Board) graph.Stre
 	})
 }
 
-// legacyStreamShim adapts a StreamPublisher into the deprecated StreamCallback
-// shape so nodes that still read ctx.Stream keep working. The shim ignores
-// se.NodeID because the publisher is already bound to the executing node;
-// scheduled for removal in v0.3.0 alongside ExecutionContext.Stream.
-func legacyStreamShim(p graph.StreamPublisher) graph.StreamCallback {
-	if p == nil {
-		return nil
-	}
-	return func(se graph.StreamEvent) {
-		p.Emit(se.Type, se.Payload)
-	}
-}
-
 func updateBoardToolResult(board *graph.Board, m map[string]any) {
 	tcID, _ := m["tool_call_id"].(string)
 	if tcID == "" {
diff --git a/sdk/graph/runner/options.go b/sdk/graph/runner/options.go
--- a/sdk/graph/runner/options.go
+++ b/sdk/graph/runner/options.go
@@ -3,7 +3,6 @@ package runner
 import (
 	"time"
 
-	"github.com/GizClaw/flowcraft/sdk/graph"
 	"github.com/GizClaw/flowcraft/sdk/graph/runner/internal/executor"
 )
 
@@ -69,27 +68,6 @@ func WithResolver(r executor.VariableResolver) Option {
 	return appendRunOpt(executor.WithResolver(r))
 }
 
-// --- deprecated forwarders (kept for v0.2 callers) ---------------------------
-
-// WithStreamCallback installs a legacy node-delta stream callback.
-//
-// Deprecated: subscribe to engine.Host's event bus, or read
-// ExecutionContext.Publisher inside a node, instead. Scheduled for
-// removal in v0.3.0 together with executor.WithStreamCallback.
-func WithStreamCallback(cb graph.StreamCallback) Option {
-	return appendRunOpt(executor.WithStreamCallback(cb))
-}
-
-// WithCheckpointStore installs a graph-format CheckpointStore that
-// persists a checkpoint after every node completes.
-//
-// Deprecated: prefer WithHost with a host whose Checkpointer wraps an
-// engine.CheckpointStore. Scheduled for removal in v0.3.0 together with
-// executor.WithCheckpointStore.
-func WithCheckpointStore(s executor.CheckpointStore) Option { //nolint:staticcheck // forwards to deprecated executor option for transitional callers
-	return appendRunOpt(executor.WithCheckpointStore(s))
-}
-
 // appendRunOpt is the single seam that grows Runner.runOpts so all
 // forwarders share one append site. Keeping this private avoids
 // callers reaching into runOpts directly.
diff --git a/sdk/graph/runner/runner.go b/sdk/graph/runner/runner.go
--- a/sdk/graph/runner/runner.go
+++ b/sdk/graph/runner/runner.go
@@ -4,7 +4,6 @@ import (
 	"context"
 
 	"github.com/GizClaw/flowcraft/sdk/engine"
-	"github.com/GizClaw/flowcraft/sdk/event"
 	"github.com/GizClaw/flowcraft/sdk/graph"
 	"github.com/GizClaw/flowcraft/sdk/graph/node"
 	"github.com/GizClaw/flowcraft/sdk/graph/runner/internal/executor"
@@ -31,31 +30,19 @@ import (
 type Runner struct {
 	compiled *graph.CompiledGraph
 	factory  *node.Factory
-	executor executor.Executor //nolint:staticcheck // the deprecated interface is the executor's own internal contract; runner keeps using it until v0.3.0 inlines the loop
 	host     engine.Host
 
 	// runOpts collects executor.RunOption values produced by
 	// runner.WithMaxIterations / WithTimeout / WithParallel / …
 	// They are appended to the per-execution option list inside
 	// Execute, in declaration order, so behaviour matches calling
 	// the underlying executor.WithXxx directly today.
-	runOpts []executor.RunOption //nolint:staticcheck // executor.RunOption is itself the soon-to-go interface; runner shields callers from that.
+	runOpts []executor.RunOption
 }
 
 // Option configures a Runner.
 type Option func(*Runner)
 
-// WithExecutor overrides the default LocalExecutor.
-//
-// Deprecated: scheduled for removal in v0.3.0 together with
-// [executor.Executor]. The graph engine will be exposed exclusively
-// through [Runner] which itself implements [engine.Engine]; hosting
-// alternative execution backends will be done by writing a fresh
-// [engine.Engine] implementation rather than swapping a sub-interface.
-func WithExecutor(e executor.Executor) Option { //nolint:staticcheck
-	return func(r *Runner) { r.executor = e }
-}
-
 // WithHost installs the engine.Host the Runner forwards to the executor
 // on every Run. The host receives every published envelope and is also
 // handed to nodes via ExecutionContext.Host so they can call Publish,
@@ -74,51 +61,6 @@ func WithHost(h engine.Host) Option {
 	}
 }
 
-// WithEventBus sets the Bus used for graph lifecycle events.
-//
-// Deprecated: pass an engine.Host via WithHost — the Runner now publishes
-// every envelope through host.Publish. WithEventBus is retained as a
-// transitional shim that wraps the bus in a minimal host (other Host
-// methods become no-ops); it will be removed in v0.3.0 alongside
-// executor.WithEventBus.
-func WithEventBus(bus event.Bus) Option {
-	return func(r *Runner) {
-		if bus == nil {
-			bus = event.NoopBus{}
-		}
-		r.host = busOnlyHost{Host: engine.NoopHost{}, bus: bus}
-	}
-}
-
-// busOnlyHost adapts an event.Bus into engine.Host. It exists only to keep
-// the deprecated WithEventBus working without polluting Runner with a
-// second event-sink field. Every Host method other than Publish is
-// inherited from engine.NoopHost via the embedded field, so callers that
-// only care about lifecycle envelopes still get the right behaviour while
-// nodes that try to call Interrupt/AskUser/etc. see a safe default.
-//
-// Deprecated: scheduled for removal in v0.3.0 together with
-// runner.WithEventBus.
-type busOnlyHost struct {
-	engine.Host // embeds engine.NoopHost in practice; Publish is overridden below.
-	bus         event.Bus
-}
-
-// Publish forwards to the wrapped bus, swallowing errors to match the
-// "events are observability, not control flow" rule the executor relies on.
-func (h busOnlyHost) Publish(ctx context.Context, env event.Envelope) error {
-	if h.bus == nil {
-		return nil
-	}
-	_ = h.bus.Publish(ctx, env)
-	return nil
-}
-
-// unwrapBus returns the underlying bus when h originated from
-// runner.WithEventBus. Used by the deprecated Runner.Bus() getter so
-// existing callers keep working until v0.3.0.
-func (h busOnlyHost) unwrapBus() event.Bus { return h.bus }
-
 // New compiles a GraphDefinition and returns a ready-to-use Runner. The
 // factory provides runtime dependencies (LLM resolver, tool registry, etc.)
 // needed to instantiate nodes.
@@ -130,7 +72,6 @@ func New(def *graph.GraphDefinition, factory *node.Factory, opts ...Option) (*Ru
 	r := &Runner{
 		compiled: compiled,
 		factory:  factory,
-		executor: executor.NewLocalExecutor(),
 		host:     engine.NoopHost{},
 	}
 	for _, opt := range opts {
@@ -149,7 +90,7 @@ func New(def *graph.GraphDefinition, factory *node.Factory, opts ...Option) (*Ru
 // New code that runs through agent.Run should call agent.Run with the
 // Runner directly; Run is preserved for tests and one-shot CLI usage
 // where the engine.Engine plumbing would be ceremony.
-func (r *Runner) Run(ctx context.Context, vars map[string]any, opts ...executor.RunOption) (*graph.Board, error) { //nolint:staticcheck
+func (r *Runner) Run(ctx context.Context, vars map[string]any, opts ...executor.RunOption) (*graph.Board, error) {
 	board := graph.NewBoard()
 	for k, v := range vars {
 		board.SetVar(k, v)
@@ -192,7 +133,7 @@ func (r *Runner) executeBound(
 	run engine.Run,
 	host engine.Host,
 	board *graph.Board,
-	extra []executor.RunOption, //nolint:staticcheck
+	extra []executor.RunOption,
 ) (*graph.Board, error) {
 	if host == nil {
 		host = r.host
@@ -220,18 +161,18 @@ func (r *Runner) executeBound(
 		}
 	}
 
-	opts := make([]executor.RunOption, 0, 3+len(r.runOpts)+len(extra)) //nolint:staticcheck
+	opts := make([]executor.RunOption, 0, 3+len(r.runOpts)+len(extra))
 	opts = append(opts, executor.WithHost(host))
 	if run.ID != "" {
-		opts = append(opts, executor.WithRunID(run.ID)) //nolint:staticcheck
+		opts = append(opts, executor.WithRunID(run.ID))
 	}
 	// Default resolver is harmless if the caller already supplied one
 	// via runner.WithResolver — executor.runConfig is last-write-wins.
 	opts = append(opts, executor.WithResolver(variable.NewResolver()))
 	opts = append(opts, r.runOpts...)
 	opts = append(opts, extra...)
 
-	return r.executor.Execute(ctx, g, board, opts...)
+	return executor.NewLocalExecutor().Execute(ctx, g, board, opts...)
 }
 
 // Host returns the configured engine.Host. Always non-nil — callers can
@@ -241,19 +182,6 @@ func (r *Runner) executeBound(
 // that, callers can type-assert on the returned value.
 func (r *Runner) Host() engine.Host { return r.host }
 
-// Bus returns the bus configured via the deprecated WithEventBus option,
-// or nil if WithHost was used (the modern path) or no option was supplied.
-//
-// Deprecated: prefer Runner.Host() and any host-specific getters your host
-// implementation exposes. Scheduled for removal in v0.3.0.
-func (r *Runner) Bus() event.Bus {
-	type busUnwrapper interface{ unwrapBus() event.Bus }
-	if u, ok := r.host.(busUnwrapper); ok {
-		return u.unwrapBus()
-	}
-	return nil
-}
-
 // Graph returns a freshly assembled Graph snapshot for inspection. Intended
 // for testing and debugging, not for execution.
 func (r *Runner) Graph() (*graph.Graph, error) {
diff --git a/sdk/graph/stream.go b/sdk/graph/stream.go
--- a/sdk/graph/stream.go
+++ b/sdk/graph/stream.go
@@ -3,9 +3,8 @@ package graph
 // StreamPublisher emits in-flight node events (token / tool_call / tool_result / ...).
 //
 // Nodes obtain a publisher from ExecutionContext.Publisher and call Emit to
-// push deltas. The executor decides where the events ultimately go
-// (engine.Host.Publisher, legacy StreamCallback, both) so nodes never see
-// those concerns.
+// push deltas. The executor decides where the events ultimately go (typically
+// engine.Host.Publish via the run's host) so nodes never see that concern.
 //
 // Emit is fire-and-forget: implementations must not block the caller and must
 // not return errors. Implementations are expected to be safe for concurrent
diff --git a/sdk/graph/vars.go b/sdk/graph/vars.go
--- a/sdk/graph/vars.go
+++ b/sdk/graph/vars.go
@@ -2,61 +2,19 @@ package graph
 
 // Board variable keys owned by the graph layer.
 //
-// Two groups live here:
-//
-//   - Engine-produced keys (VarInterruptedNode, VarToolCalls) — written by the
-//     executor as a side effect of graph execution. These are part of graph's
-//     own contract and stay here.
-//
-//   - Chat-application conventions (VarMessages, VarQuery, VarAnswer) — these
-//     describe an agent-style chat data model and do NOT belong in the engine
-//     layer. They are kept here only as a transitional landing pad while the
-//     workflow → agent migration is in progress; scheduled to move to
-//     sdk/agent in v0.3.0.
-//
-// Node-type-specific keys (e.g. summarisation index, previous-message count)
-// belong in the owning node sub-package, NOT here.
-
-// --- Engine-produced keys ----------------------------------------------------
-
+// Only engine-produced keys live here — names written by the executor
+// itself as a side effect of running a graph. Node-type-specific keys
+// (e.g. summarisation index, previous-message count, the LLM
+// transcript channel name) belong in the owning node sub-package.
 const (
-	// VarInterruptedNode records the ID of the node that returned
-	// graph.ErrInterrupt, written by the executor before propagating the
-	// interrupt to the caller. Used by resume flows to know where to restart.
+	// VarInterruptedNode records the ID of the node that returned an
+	// engine.Interrupted error, written by the executor before propagating
+	// the interrupt to the caller. Used by resume flows to know where to
+	// restart.
 	VarInterruptedNode = "__interrupted_node"
 
 	// VarToolCalls is the engine-managed slice that mirrors tool_call /
 	// tool_result stream events into board state, so resume / inspection
 	// flows can see the in-flight tool loop without replaying the stream.
 	VarToolCalls = "__tool_calls"
 )
-
-// --- Chat-application conventions (deprecated) -------------------------------
-//
-// These keys describe an agent / chat data model and do not belong in the
-// engine. They survive here as a transitional shim so existing graph users
-// (LLMNode default behaviour, ValidateInputs) keep working while the agent
-// runtime is wired up. New code SHOULD pass the messages/query/answer key
-// names through node config instead of relying on these constants.
-
-// VarMessages is the canonical board-var key holding a []model.Message
-// transcript when graphs do not use the typed message channel.
-//
-// Deprecated: chat-application convention; will move to sdk/agent in v0.3.0.
-// New code should pass messagesKey through node config.
-const VarMessages = "messages"
-
-// VarQuery is the canonical key for the user's current question, used by
-// LLM/template nodes that fall back to a single-turn query when no
-// transcript is available.
-//
-// Deprecated: chat-application convention; will move to sdk/agent in v0.3.0.
-// New code should pass the query key through node config.
-const VarQuery = "query"
-
-// VarAnswer is the canonical key for the final assistant answer string
-// written by the terminal node before the graph stops.
-//
-// Deprecated: chat-application convention; will move to sdk/agent in v0.3.0.
-// New code should pass the answer key through node config.
-const VarAnswer = "answer"
diff --git a/sdk/history/archive.go b/sdk/history/archive.go
--- a/sdk/history/archive.go
+++ b/sdk/history/archive.go
@@ -46,8 +46,8 @@ type ArchiveResult struct {
 	HotStartSeq      int    `json:"hot_start_seq"`
 }
 
-// loadManifestImpl reads the archive manifest for a conversation.
-func loadManifestImpl(ctx context.Context, ws workspace.Workspace, prefix, archivePrefix, convID string) (*ArchiveManifest, error) {
+// LoadManifest reads the archive manifest for a conversation.
+func LoadManifest(ctx context.Context, ws workspace.Workspace, prefix, archivePrefix, convID string) (*ArchiveManifest, error) {
 	path := manifestPath(prefix, archivePrefix, convID)
 	exists, err := ws.Exists(ctx, path)
 	if err != nil {
@@ -168,7 +168,7 @@ func recoverArchiveImpl(ctx context.Context, ws workspace.Workspace, store Store
 		}
 	case "gzip_written":
 		// Gzip done but manifest not updated — update manifest then trim.
-		manifest, err := loadManifestImpl(ctx, ws, prefix, archivePrefix, convID)
+		manifest, err := LoadManifest(ctx, ws, prefix, archivePrefix, convID)
 		if err != nil {
 			return fmt.Errorf("archive: recovery load manifest: %w", err)
 		}
@@ -210,14 +210,18 @@ func recoverArchiveImpl(ctx context.Context, ws workspace.Workspace, store Store
 	return nil
 }
 
-// archiveImpl moves old messages to gzip-compressed archive files. It is
-// the package-private implementation called by the [Coordinator] (via
-// internalArchive) and by the deprecated top-level [Archive] shim.
+// Archive moves old messages to gzip-compressed archive files. The
+// [Coordinator] drives it through its per-conversation worker queue;
+// LLM tools (history_compact in particular) call it directly when the
+// caller has not wired a Coordinator.
 //
-// Crash recovery is handled by recoverArchiveImpl; new callers should
-// drive both through [Coordinator] rather than invoking the package
-// helpers directly.
-func archiveImpl(ctx context.Context, ws workspace.Workspace, store Store, prefix, convID string, cfg ArchiveConfig) (ArchiveResult, error) {
+// Crash recovery is handled by recoverArchiveImpl, which the
+// Coordinator runs lazily on first contact with a conversation.
+// Callers that own a [History] from [NewCompacted] should always
+// reach archive through [Coordinator.Archive] to inherit the
+// per-conversation serialization that protects against racing
+// Append/trim sequences.
+func Archive(ctx context.Context, ws workspace.Workspace, store Store, prefix, convID string, cfg ArchiveConfig) (ArchiveResult, error) {
 	start := time.Now()
 	defer func() {
 		archiveDuration.Record(ctx, time.Since(start).Seconds())
@@ -257,7 +261,7 @@ func archiveImpl(ctx context.Context, ws workspace.Workspace, store Store, prefi
 		archivePrefix = "archive"
 	}
 
-	manifest, err := loadManifestImpl(ctx, ws, prefix, archivePrefix, convID)
+	manifest, err := LoadManifest(ctx, ws, prefix, archivePrefix, convID)
 	if err != nil {
 		return result, err
 	}
@@ -342,12 +346,12 @@ func archiveDir(prefix, archivePrefix, convID string) string {
 	return fmt.Sprintf("%s/%s", convID, archivePrefix)
 }
 
-// loadArchivedMessagesImpl reads messages from gzip archive segments. It
+// LoadArchivedMessages reads messages from gzip archive segments. It
 // powers history_expand's cold-segment path; callers outside the
 // history package should obtain archived turns via the history_expand
-// tool registered through [RegisterTools].
-func loadArchivedMessagesImpl(ctx context.Context, ws workspace.Workspace, prefix, archivePrefix, convID string, startSeq, endSeq int) ([]model.Message, error) {
-	manifest, err := loadManifestImpl(ctx, ws, prefix, archivePrefix, convID)
+// tool wrapper, not by reading archive files directly.
+func LoadArchivedMessages(ctx context.Context, ws workspace.Workspace, prefix, archivePrefix, convID string, startSeq, endSeq int) ([]model.Message, error) {
+	manifest, err := LoadManifest(ctx, ws, prefix, archivePrefix, convID)
 	if err != nil {
 		return nil, err
 	}
diff --git a/sdk/history/compactor.go b/sdk/history/compactor.go
--- a/sdk/history/compactor.go
+++ b/sdk/history/compactor.go
@@ -351,20 +351,8 @@ func (m *compactor) Shutdown(ctx context.Context) error {
 	}
 }
 
-// Close is the legacy v0.2.x entry point preserved for callers still on
-// the [Closer] sub-interface. It blocks until all queues drain.
-//
-// Deprecated: use [Coordinator.Shutdown] (with a context for bounded
-// waits). Will be removed in v0.3.0.
-func (m *compactor) Close() {
-	_ = m.Shutdown(context.Background())
-}
-
-// Compile-time guarantees.
-var (
-	_ Coordinator = (*compactor)(nil)
-	_ Closer      = (*compactor)(nil)
-)
+// Compile-time guarantee.
+var _ Coordinator = (*compactor)(nil)
 
 // enqueueAsync routes a fire-and-forget task (ingest) to the conv queue.
 // Returns ErrClosed if Shutdown has started in the meantime; never
@@ -469,7 +457,7 @@ func (m *compactor) runTask(convID string, task convTask) {
 			return
 		}
 		archiveCtx, cancelArchive := context.WithTimeout(context.Background(), defaultArchiveTimeout)
-		if _, err := internalArchive(archiveCtx, m.ws, m.store, m.prefix, convID, m.config.Archive); err != nil {
+		if _, err := Archive(archiveCtx, m.ws, m.store, m.prefix, convID, m.config.Archive); err != nil {
 			telemetry.Warn(archiveCtx, "history: async archive failed",
 				otellog.String(telemetry.AttrConversationID, convID),
 				otellog.String(telemetry.AttrErrorMessage, err.Error()))
@@ -478,7 +466,7 @@ func (m *compactor) runTask(convID string, task convTask) {
 
 	case taskArchive:
 		ctx, cancel := context.WithTimeout(context.Background(), defaultArchiveTimeout)
-		res, err := internalArchive(ctx, m.ws, m.store, m.prefix, convID, m.config.Archive)
+		res, err := Archive(ctx, m.ws, m.store, m.prefix, convID, m.config.Archive)
 		cancel()
 		task.replyArchive <- archiveReply{res: res, err: err}
 
@@ -591,14 +579,6 @@ func (m *compactor) kickoffStartupRecovery() {
 	}()
 }
 
-// internalArchive is the package-private archive entry point used by the
-// coordinator. The exported [Archive] function in deprecated.go calls
-// through to this implementation; new code should prefer
-// [Coordinator.Archive].
-func internalArchive(ctx context.Context, ws workspace.Workspace, store Store, prefix, convID string, cfg ArchiveConfig) (ArchiveResult, error) {
-	return archiveImpl(ctx, ws, store, prefix, convID, cfg)
-}
-
 // CompactOption customizes a [History] built by [NewCompacted].
 //
 // Compaction knobs (chunk size, recent ratio, leaf pruning, archive
diff --git a/sdk/history/deprecated.go b/sdk/history/deprecated.go
deleted file mode 100644
--- a/sdk/history/deprecated.go
+++ /dev/null
@@ -1,67 +0,0 @@
-// Aggregator for v0.3.0 removals. Every symbol declared in this file is
-// scheduled for removal in v0.3.0; new code should not depend on it.
-//
-// Why this file exists at all: the v0.2.x surface exposed a handful of
-// top-level helpers (Archive, RecoverArchive, LoadArchivedMessages,
-// LoadManifest, SaveManifest, Closer.Close) that each let callers reach
-// into the implementation in incompatible ways and bypass per-
-// conversation serialization. The v0.3 redesign funnels every state-
-// mutating operation through [Coordinator]; the wrappers here exist
-// only so existing callers keep compiling for one release while they
-// migrate.
-
-package history
-
-import (
-	"context"
-
-	"github.com/GizClaw/flowcraft/sdk/model"
-	"github.com/GizClaw/flowcraft/sdk/workspace"
-)
-
-// Archive runs message archiving for one conversation.
-//
-// Deprecated: use [Coordinator.Archive] (obtained by type-asserting the
-// [History] returned by [NewCompacted] to [Coordinator]). Direct calls
-// here bypass the per-conversation worker queue, which means a
-// concurrent [History.Append] can race against the trim step inside
-// archive and silently drop messages. Will be removed in v0.3.0.
-func Archive(ctx context.Context, ws workspace.Workspace, store Store, prefix, convID string, cfg ArchiveConfig) (ArchiveResult, error) {
-	return archiveImpl(ctx, ws, store, prefix, convID, cfg)
-}
-
-// RecoverArchive checks for incomplete archive operations and completes them.
-//
-// Deprecated: [NewCompacted] now performs a startup scan and lazy per-
-// conversation recovery automatically; manual calls are no longer
-// required. Will be removed in v0.3.0.
-func RecoverArchive(ctx context.Context, ws workspace.Workspace, store Store, prefix, archivePrefix, convID string) error {
-	return recoverArchiveImpl(ctx, ws, store, prefix, archivePrefix, convID)
-}
-
-// LoadArchivedMessages reads messages from gzip archive segments.
-//
-// Deprecated: cold-segment loading is an implementation detail of the
-// history_expand tool. Use the tool registered by [RegisterTools]
-// instead of calling this directly. Will be removed in v0.3.0.
-func LoadArchivedMessages(ctx context.Context, ws workspace.Workspace, prefix, archivePrefix, convID string, startSeq, endSeq int) ([]model.Message, error) {
-	return loadArchivedMessagesImpl(ctx, ws, prefix, archivePrefix, convID, startSeq, endSeq)
-}
-
-// LoadManifest reads the archive manifest for a conversation.
-//
-// Deprecated: the manifest is an internal artefact of [Coordinator];
-// callers reasoning about archived state should query
-// [Coordinator.Archive]'s result instead. Will be removed in v0.3.0.
-func LoadManifest(ctx context.Context, ws workspace.Workspace, prefix, archivePrefix, convID string) (*ArchiveManifest, error) {
-	return loadManifestImpl(ctx, ws, prefix, archivePrefix, convID)
-}
-
-// SaveManifest writes the archive manifest atomically.
-//
-// Deprecated: writing the manifest from outside [Coordinator] cannot be
-// serialized against background archive runs and will corrupt accounting
-// under concurrency. Will be removed in v0.3.0.
-func SaveManifest(ctx context.Context, ws workspace.Workspace, prefix, archivePrefix, convID string, m *ArchiveManifest) error {
-	return saveManifestImpl(ctx, ws, prefix, archivePrefix, convID, m)
-}
diff --git a/sdk/history/doc.go b/sdk/history/doc.go
--- a/sdk/history/doc.go
+++ b/sdk/history/doc.go
@@ -41,30 +41,27 @@
 //
 // Two graph tools surface this package to LLMs: history_expand fetches
 // the verbatim messages behind a summary node, history_compact triggers
-// a manual compaction. Wire them through [RegisterTools] with a
-// [ToolDeps] whose Coordinator field is populated, so the tools observe
-// per-conversation serialization rather than mutating raw stores.
+// a manual compaction. The in-tree tool wrappers (taking a Coordinator
+// for per-conversation serialization) live in an adapter package
+// outside sdk; this package exposes only the underlying primitives.
 //
-// # Migration to v0.3.0
+// # v0.3.0 surface
 //
 // The v0.3 surface narrows on the [History] / [Coordinator] interfaces.
-// The following v0.2 entry points are now Deprecated and will be removed
-// in v0.3.0:
+// The following v0.2 entry points were removed in v0.3.0:
 //
-//   - [Closer] / [compactor].Close — replaced by
-//     [Coordinator.Shutdown] (context-aware, refuses late writes).
-//   - Top-level [Archive], [RecoverArchive], [LoadArchivedMessages],
-//     [LoadManifest], [SaveManifest] — replaced by [Coordinator] (which
-//     also auto-recovers in-flight archives at construction).
-//   - [SummaryCacheStore] — superseded by [SummaryStore] which the DAG
-//     already consumes; nothing in the package reads SummaryCacheStore.
-//
-// [ToolDeps] / [RegisterTools] stay supported in v0.3 — they now take
-// an optional Coordinator field that, when set, makes history_compact
-// route through the per-conversation queue.
-//
-// All deprecated symbols live in deprecated.go and continue to compile
-// against the v0.2 ABI for one release.
+//   - Closer / compactor.Close — replaced by [Coordinator.Shutdown]
+//     (context-aware, refuses late writes).
+//   - Top-level RecoverArchive, SaveManifest helpers — folded into the
+//     internal recoverArchiveImpl/saveManifestImpl helpers exercised by
+//     [Coordinator]. The exported [Archive], [LoadManifest] and
+//     [LoadArchivedMessages] survive for adapter packages that need
+//     direct archive access; [Coordinator] auto-recovers in-flight
+//     archives at construction.
+//   - SummaryCacheStore — superseded by [SummaryStore] which the DAG
+//     already consumes.
+//   - In-package ToolDeps / RegisterTools — moved out of sdk into the
+//     adapter layer.
 //
 // # Naming history
 //
diff --git a/sdk/history/history.go b/sdk/history/history.go
--- a/sdk/history/history.go
+++ b/sdk/history/history.go
@@ -65,11 +65,9 @@ var ErrClosed = errors.New("history: coordinator closed")
 //	coord, _ := hist.(history.Coordinator)
 //	defer func() { _ = coord.Shutdown(context.Background()) }()
 //
-// Migration: the previous [Closer] sub-interface is retained for one
-// release behind a Deprecated marker; new code should prefer Coordinator
-// because it offers context-aware shutdown plus first-class maintenance
-// entry points that internally share the per-conversation queue used by
-// background ingest/archive.
+// Coordinator offers context-aware shutdown plus first-class
+// maintenance entry points (Compact / Archive) that internally share
+// the per-conversation queue used by background ingest/archive.
 type Coordinator interface {
 	// Compact runs DAG compact for one conversation. Serialized against
 	// concurrent Append/Archive on the same conversationID.
@@ -92,14 +90,3 @@ type Coordinator interface {
 	// all workers have exited.
 	Shutdown(ctx context.Context) error
 }
-
-// Closer is the legacy lifecycle interface that the [History] returned by
-// [NewCompacted] still satisfies for one release.
-//
-// Deprecated: use [Coordinator] (and its context-aware Shutdown) instead.
-// Closer.Close has no way to bound its wait, no way to refuse late writes,
-// and no way to surface a drain error to the caller. It will be removed
-// in v0.3.0.
-type Closer interface {
-	Close()
-}
diff --git a/sdk/history/store.go b/sdk/history/store.go
--- a/sdk/history/store.go
+++ b/sdk/history/store.go
@@ -41,58 +41,6 @@ type RangeReader interface {
 	GetMessageRange(ctx context.Context, conversationID string, start, end int) ([]model.Message, error)
 }
 
-// SummaryCacheStore is an optional interface that Store implementations
-// can satisfy to persist a single "current summary" string alongside
-// messages.
-//
-// Deprecated: superseded by [SummaryStore], which the [SummaryDAG]
-// already requires. Nothing inside the history package consumes this
-// interface any more — the [InMemoryStore] / [FileStore] implementations
-// remain only so downstream Stores that already satisfied it keep
-// compiling. Will be removed in v0.3.0.
-//
-// # Migration
-//
-// Most callers wired SummaryCacheStore in v0.1 to enable a hand-rolled
-// "buffer + single summary" history strategy. The supported v0.2+
-// equivalent is [NewCompacted], which manages a multi-level summary DAG
-// and assembles "highest-depth summary + recent tail" into the supplied
-// token budget automatically — no SummaryCacheStore plumbing required:
-//
-//	hist := history.NewCompacted(store, summaryLLM, ws,
-//	    history.WithTokenBudget(8000),
-//	)
-//	msgs, _ := hist.Load(ctx, convID, history.Budget{})
-//
-// If the single-summary semantics are still desired (for example
-// because the downstream service has its own summarizer and only needs
-// a place to persist the result), the same shape can be expressed in
-// ~5 lines on top of [SummaryStore]:
-//
-//	// Save (overwrite the single summary):
-//	_ = ss.Rewrite(ctx, convID, []*history.SummaryNode{{
-//	    ID:             history.NewSummaryNodeID(),
-//	    ConversationID: convID,
-//	    Depth:          0,
-//	    Content:        text,
-//	    EarliestSeq:    0,
-//	    LatestSeq:      msgCount - 1,
-//	    CreatedAt:      time.Now(),
-//	}})
-//
-//	// Load:
-//	depth0 := 0
-//	nodes, _ := ss.List(ctx, convID, history.SummaryListOptions{Depth: &depth0})
-//	// nodes[0].Content is the summary; nodes[0].LatestSeq+1 is msgCount.
-//
-// [SummaryStore.Rewrite] is the exact primitive SummaryCacheStore.SaveSummary
-// implied (atomic single-record replacement); the only thing v0.3 drops is
-// the dedicated interface name.
-type SummaryCacheStore interface {
-	GetSummary(ctx context.Context, conversationID string) (summary string, msgCount int, err error)
-	SaveSummary(ctx context.Context, conversationID, summary string, msgCount int) error
-}
-
 const (
 	defaultMaxConversations = 10000
 	defaultConversationTTL  = 24 * time.Hour
@@ -380,54 +328,6 @@ func (s *FileStore) DeleteMessages(ctx context.Context, conversationID string) e
 	return nil
 }
 
-// --- SummaryCacheStore implementation ---
-
-func (s *FileStore) summaryPath(conversationID string) string {
-	return fmt.Sprintf("%s/%s/summary.json", s.prefix, conversationID)
-}
-
-type summaryJSON struct {
-	Text     string `json:"text"`
-	MsgCount int    `json:"msg_count"`
-}
-
-func (s *FileStore) GetSummary(ctx context.Context, conversationID string) (string, int, error) {
-	mu := s.convMu(conversationID)
-	mu.Lock()
-	defer mu.Unlock()
-
-	path := s.summaryPath(conversationID)
-	exists, err := s.ws.Exists(ctx, path)
-	if err != nil || !exists {
-		return "", 0, err
-	}
-	data, err := s.ws.Read(ctx, path)
-	if err != nil {
-		return "", 0, fmt.Errorf("memory: read summary cache: %w", err)
-	}
-	var cache summaryJSON
-	if err := json.Unmarshal(data, &cache); err != nil {
-		return "", 0, fmt.Errorf("memory: unmarshal summary cache: %w", err)
-	}
-	return cache.Text, cache.MsgCount, nil
-}
-
-func (s *FileStore) SaveSummary(ctx context.Context, conversationID, summary string, msgCount int) error {
-	mu := s.convMu(conversationID)
-	mu.Lock()
-	defer mu.Unlock()
-
-	data, err := json.Marshal(summaryJSON{Text: summary, MsgCount: msgCount})
-	if err != nil {
-		return fmt.Errorf("memory: marshal summary cache: %w", err)
-	}
-	path := s.summaryPath(conversationID)
-	if err := s.ws.Write(ctx, path, data); err != nil {
-		return fmt.Errorf("memory: write summary cache: %w", err)
-	}
-	return nil
-}
-
 // GetMessageRange returns messages in the range [start, end).
 func (s *FileStore) GetMessageRange(ctx context.Context, conversationID string, start, end int) ([]model.Message, error) {
 	mu := s.convMu(conversationID)
diff --git a/sdk/history/tools.go b/sdk/history/tools.go
deleted file mode 100644
--- a/sdk/history/tools.go
+++ /dev/null
@@ -1,313 +0,0 @@
-package history
-
-import (
-	"context"
-	"encoding/json"
-	"fmt"
-	"strings"
-
-	"github.com/GizClaw/flowcraft/sdk/errdefs"
-	"github.com/GizClaw/flowcraft/sdk/model"
-	"github.com/GizClaw/flowcraft/sdk/tool"
-	"github.com/GizClaw/flowcraft/sdk/workspace"
-)
-
-// ToolDeps bundles everything the history_expand / history_compact
-// tools need at registration time. Pass it to [RegisterTools].
-//
-// Coordinator is optional but strongly recommended: when set,
-// history_compact routes Compact / Archive through the per-conversation
-// worker queue, matching the serialization guarantees that
-// [Coordinator] offers to first-class callers. When Coordinator is nil
-// the tool falls back to constructing an ad-hoc [SummaryDAG] and
-// calling [archiveImpl] directly, which can race a concurrent
-// [History.Append] on the same conversation. New code that already has
-// a [History] from [NewCompacted] should always wire it via:
-//
-//	coord, _ := hist.(history.Coordinator)
-//	history.RegisterTools(registry, history.ToolDeps{
-//	    Coordinator:  coord,
-//	    SummaryStore: summaryStore,
-//	    MessageStore: msgStore,
-//	    Workspace:    ws,
-//	    Prefix:       prefix,
-//	    Config:       cfg,
-//	})
-//
-// Deprecated: this LLM tool dependency bundle moves to
-// sdkx/tool/history in v0.3.0 alongside [RegisterTools]. The struct
-// shape is preserved across the move; only the import path changes.
-// See docs/migrations/v0.3.0.md.
-type ToolDeps struct {
-	// Coordinator, when non-nil, makes history_compact go through the
-	// per-conversation queue. Leaving it nil preserves the v0.2 "direct
-	// store mutation" behaviour and keeps the struct usable from code
-	// that only has raw stores.
-	Coordinator Coordinator
-
-	SummaryStore SummaryStore
-	MessageStore Store
-	Workspace    workspace.Workspace
-	Prefix       string
-	Config       DAGConfig
-}
-
-// RegisterTools registers history_expand and history_compact against the
-// supplied [tool.Registry]. The summary index is auto-injected into the
-// LLM system prompt via the workflow.VarSummaryIndex board variable, so
-// a separate history_search tool is not needed.
-//
-// See [ToolDeps] for the recommended way to construct deps from an
-// existing [History] / [Coordinator] pair.
-//
-// Deprecated: this LLM tool registration helper moves to
-// sdkx/tool/history in v0.3.0. The function signature is preserved
-// across the move; only the import path changes. See
-// docs/migrations/v0.3.0.md.
-func RegisterTools(registry *tool.Registry, deps ToolDeps) {
-	registry.Register(newHistoryExpandTool(deps))
-	registry.RegisterWithScope(newHistoryCompactTool(deps), tool.ScopePlatform)
-}
-
-// --- history_expand ---
-
-type historyExpandTool struct {
-	deps ToolDeps
-}
-
-func newHistoryExpandTool(deps ToolDeps) tool.Tool {
-	return &historyExpandTool{deps: deps}
-}
-
-func (t *historyExpandTool) Definition() model.ToolDefinition {
-	return tool.DefineSchema("history_expand",
-		"Expand a compressed summary to see the original messages or finer-grained summaries it was derived from.",
-		tool.Property("summary_id", "string", "The ID of the summary to expand"),
-		tool.PropertyWithDefault("max_messages", "integer", "Maximum original messages to return", 20),
-	).Required("summary_id").Build()
-}
-
-func (t *historyExpandTool) Execute(ctx context.Context, arguments string) (string, error) {
-	var args struct {
-		SummaryID   string `json:"summary_id"`
-		MaxMessages int    `json:"max_messages"`
-	}
-	args.MaxMessages = 20
-	if err := json.Unmarshal([]byte(arguments), &args); err != nil {
-		return "", fmt.Errorf("history_expand: parse args: %w", err)
-	}
-
-	convID := ConversationIDFrom(ctx)
-	if convID == "" {
-		return "", errdefs.Validationf("history_expand: no conversation ID in context")
-	}
-
-	if t.deps.SummaryStore == nil {
-		return "", errdefs.NotAvailablef("history_expand: summary store not available")
-	}
-
-	node, err := t.deps.SummaryStore.GetByConvID(ctx, convID, args.SummaryID)
-	if err != nil {
-		return "", fmt.Errorf("history_expand: %w", err)
-	}
-
-	if node.Depth > 0 {
-		var children []*SummaryNode
-		for _, sid := range node.SourceIDs {
-			child, err := t.deps.SummaryStore.GetByConvID(ctx, convID, sid)
-			if err != nil {
-				continue
-			}
-			children = append(children, child)
-		}
-		return formatChildSummaries(children), nil
-	}
-
-	return t.expandLeaf(ctx, convID, node, args.MaxMessages)
-}
-
-func (t *historyExpandTool) expandLeaf(ctx context.Context, convID string, node *SummaryNode, maxMsgs int) (string, error) {
-	startSeq := node.EarliestSeq
-	endSeq := node.LatestSeq + 1
-
-	if t.deps.Workspace != nil {
-		archivePrefix := t.deps.Config.Archive.ArchivePrefix
-		if archivePrefix == "" {
-			archivePrefix = "archive"
-		}
-		manifest, err := loadManifestImpl(ctx, t.deps.Workspace, t.deps.Prefix, archivePrefix, convID)
-		if err == nil && manifest.HotStartSeq > 0 {
-			var allMsgs []model.Message
-
-			if startSeq < manifest.HotStartSeq {
-				coldEnd := endSeq
-				if coldEnd > manifest.HotStartSeq {
-					coldEnd = manifest.HotStartSeq
-				}
-				coldMsgs, err := loadArchivedMessagesImpl(ctx, t.deps.Workspace, t.deps.Prefix, archivePrefix, convID, startSeq, coldEnd-1)
-				if err == nil {
-					allMsgs = append(allMsgs, coldMsgs...)
-				}
-			}
-
-			if endSeq > manifest.HotStartSeq {
-				hotStart := startSeq - manifest.HotStartSeq
-				if hotStart < 0 {
-					hotStart = 0
-				}
-				hotEnd := endSeq - manifest.HotStartSeq
-				if rr, ok := t.deps.MessageStore.(RangeReader); ok {
-					hotMsgs, err := rr.GetMessageRange(ctx, convID, hotStart, hotEnd)
-					if err == nil {
-						allMsgs = append(allMsgs, hotMsgs...)
-					}
-				}
-			}
-
-			if len(allMsgs) > 0 {
-				if len(allMsgs) > maxMsgs {
-					allMsgs = allMsgs[len(allMsgs)-maxMsgs:]
-				}
-				return formatMessages(allMsgs), nil
-			}
-		}
-	}
-
-	if rr, ok := t.deps.MessageStore.(RangeReader); ok {
-		msgs, err := rr.GetMessageRange(ctx, convID, startSeq, endSeq)
-		if err == nil {
-			if len(msgs) > maxMsgs {
-				msgs = msgs[len(msgs)-maxMsgs:]
-			}
-			return formatMessages(msgs), nil
-		}
-	}
-
-	msgs, err := t.deps.MessageStore.GetMessages(ctx, convID)
-	if err != nil {
-		return "", fmt.Errorf("history_expand: get messages: %w", err)
-	}
-	if startSeq < len(msgs) {
-		end := endSeq
-		if end > len(msgs) {
-			end = len(msgs)
-		}
-		msgs = msgs[startSeq:end]
-	}
-	if len(msgs) > maxMsgs {
-		msgs = msgs[len(msgs)-maxMsgs:]
-	}
-	return formatMessages(msgs), nil
-}
-
-func formatMessages(msgs []model.Message) string {
-	var b strings.Builder
-	for _, msg := range msgs {
-		text := msg.Content()
-		if text != "" {
-			fmt.Fprintf(&b, "%s: %s\n\n", msg.Role, text)
-		}
-	}
-	return b.String()
-}
-
-func formatChildSummaries(children []*SummaryNode) string {
-	var b strings.Builder
-	for _, c := range children {
-		fmt.Fprintf(&b, "[d%d seq %d-%d] %s\n", c.Depth, c.EarliestSeq, c.LatestSeq, c.Content)
-		if c.ExpandHint != "" {
-			b.WriteString(c.ExpandHint + "\n")
-		}
-		b.WriteString("\n")
-	}
-	return b.String()
-}
-
-// --- history_compact ---
-
-type historyCompactTool struct {
-	deps ToolDeps
-}
-
-func newHistoryCompactTool(deps ToolDeps) tool.Tool {
-	return &historyCompactTool{deps: deps}
-}
-
-func (t *historyCompactTool) Definition() model.ToolDefinition {
-	return tool.DefineSchema("history_compact",
-		"Manually trigger compact and archive for a conversation's memory DAG.",
-		tool.Property("conversation_id", "string", "The conversation ID to compact/archive"),
-		tool.PropertyWithDefault("compact", "boolean", "Run DAG compact", true),
-		tool.PropertyWithDefault("archive", "boolean", "Run message archiving", true),
-	).Required("conversation_id").Build()
-}
-
-func (t *historyCompactTool) Execute(ctx context.Context, arguments string) (string, error) {
-	var args struct {
-		ConversationID string `json:"conversation_id"`
-		Compact        *bool  `json:"compact"`
-		Archive        *bool  `json:"archive"`
-	}
-	if err := json.Unmarshal([]byte(arguments), &args); err != nil {
-		return "", fmt.Errorf("history_compact: parse args: %w", err)
-	}
-
-	doCompact := args.Compact == nil || *args.Compact
-	doArchive := args.Archive == nil || *args.Archive
-
-	type resultJSON struct {
-		CompactResult *CompactResult `json:"compact_result,omitempty"`
-		ArchiveResult *ArchiveResult `json:"archive_result,omitempty"`
-	}
-	var res resultJSON
-
-	// Preferred path: a Coordinator is wired, every operation observes
-	// per-conversation serialization, and we never reach into the raw
-	// stores from the tool.
-	if t.deps.Coordinator != nil {
-		if doCompact {
-			cr, err := t.deps.Coordinator.Compact(ctx, args.ConversationID)
-			if err != nil {
-				return "", fmt.Errorf("history_compact: compact: %w", err)
-			}
-			res.CompactResult = &cr
-		}
-		if doArchive {
-			ar, err := t.deps.Coordinator.Archive(ctx, args.ConversationID)
-			if err != nil {
-				return "", fmt.Errorf("history_compact: archive: %w", err)
-			}
-			res.ArchiveResult = &ar
-		}
-		data, _ := json.Marshal(res)
-		return string(data), nil
-	}
-
-	// Fallback path (no Coordinator wired): we go straight to the
-	// stores, which means a concurrent Append on the same conversation
-	// can race the trim step inside archive. Callers that own a
-	// [History] from [NewCompacted] should always populate
-	// [ToolDeps.Coordinator] to avoid this branch.
-	cfg := t.deps.Config
-	if doCompact && t.deps.SummaryStore != nil {
-		dag := &SummaryDAG{
-			store:  t.deps.SummaryStore,
-			config: cfg,
-		}
-		cr, err := dag.Compact(ctx, args.ConversationID)
-		if err != nil {
-			return "", fmt.Errorf("history_compact: compact: %w", err)
-		}
-		res.CompactResult = &cr
-	}
-	if doArchive && t.deps.Workspace != nil && t.deps.MessageStore != nil {
-		ar, err := archiveImpl(ctx, t.deps.Workspace, t.deps.MessageStore, t.deps.Prefix, args.ConversationID, cfg.Archive)
-		if err != nil {
-			return "", fmt.Errorf("history_compact: archive: %w", err)
-		}
-		res.ArchiveResult = &ar
-	}
-
-	data, _ := json.Marshal(res)
-	return string(data), nil
-}
diff --git a/sdk/kanban/kanban.go b/sdk/kanban/kanban.go
--- a/sdk/kanban/kanban.go
+++ b/sdk/kanban/kanban.go
@@ -17,10 +17,7 @@ import (
 
 type ctxKey int
 
-const (
-	ctxKeyProducerID ctxKey = iota
-	ctxKeyKanban
-)
+const ctxKeyProducerID ctxKey = iota
 
 // WithProducerID injects the producer ID (e.g. agent ID) into the context.
 func WithProducerID(ctx context.Context, id string) context.Context {
diff --git a/sdk/kanban/tools.go b/sdk/kanban/tools.go
deleted file mode 100644
--- a/sdk/kanban/tools.go
+++ /dev/null
@@ -1,176 +0,0 @@
-package kanban
-
-import (
-	"context"
-	"encoding/json"
-	"fmt"
-
-	"github.com/GizClaw/flowcraft/sdk/errdefs"
-	"github.com/GizClaw/flowcraft/sdk/model"
-	"github.com/GizClaw/flowcraft/sdk/tool"
-)
-
-// SubmitTool allows LLM to submit tasks to the Kanban board.
-// Kanban is injected via struct field (when the instance is known at construction)
-// or resolved from context at execution time via KanbanFrom.
-//
-// Deprecated: this LLM tool implementation will be moved to
-// sdkx/tool/kanban in v0.3.0. The new home matches the existing
-// "sdk = interface, sdkx = concrete adapter" layering rule (cf.
-// sdk/llm → sdkx/llm/{qwen,...}). The struct shape is preserved
-// across the move; only the import path changes. See
-// docs/migrations/v0.3.0.md.
-type SubmitTool struct {
-	Kanban *Kanban
-}
-
-func (t *SubmitTool) Definition() model.ToolDefinition {
-	return tool.DefineSchema("kanban_submit",
-		"Dispatch a task to another agent. Returns a card_id. The agent executes in the background and the system delivers the result via a [Task Callback] message when done. "+
-			"You can optionally schedule the task with a delay or cron expression.",
-		tool.Property("target_agent_id", "string", "Target agent ID to execute the task"),
-		tool.Property("query", "string", "Specific task instruction for the target agent"),
-		tool.Property("user_query", "string",
-			"The user's original request that triggered this task"),
-		tool.Property("dispatch_note", "string",
-			"Brief note about the task purpose and how to summarize the result for the user"),
-		tool.Property("delay", "string",
-			"Execute after a delay instead of immediately. Go duration format, e.g. \"30s\", \"5m\", \"2h\""),
-		tool.Property("cron", "string",
-			"Execute on a recurring cron schedule. 5-field cron expression (minute hour day month weekday). Examples: \"0 9 * * MON-FRI\" = weekdays 9AM, \"*/30 * * * *\" = every 30 minutes"),
-		tool.Property("timezone", "string",
-			"Timezone for cron schedule, IANA format. e.g. \"Asia/Shanghai\", \"America/New_York\". Defaults to UTC"),
-	).Required("target_agent_id", "query").Build()
-}
-
-func (t *SubmitTool) Execute(ctx context.Context, arguments string) (string, error) {
-	k := t.resolve(ctx)
-	if k == nil {
-		return "", errdefs.NotAvailablef("kanban_submit: no kanban instance available")
-	}
-
-	var args struct {
-		TargetAgentID string `json:"target_agent_id"`
-		Query         string `json:"query"`
-		UserQuery     string `json:"user_query"`
-		DispatchNote  string `json:"dispatch_note"`
-		Delay         string `json:"delay"`
-		Cron          string `json:"cron"`
-		Timezone      string `json:"timezone"`
-	}
-	if err := json.Unmarshal([]byte(arguments), &args); err != nil {
-		return "", fmt.Errorf("kanban_submit: invalid arguments: %w", err)
-	}
-
-	cardID, err := k.Submit(ctx, TaskOptions{
-		TargetAgentID: args.TargetAgentID,
-		Query:         args.Query,
-		UserQuery:     args.UserQuery,
-		DispatchNote:  args.DispatchNote,
-		Delay:         args.Delay,
-		Cron:          args.Cron,
-		Timezone:      args.Timezone,
-	})
-	if err != nil {
-		return "", err
-	}
-
-	status := "submitted"
-	message := "Task submitted. The target agent is executing in the background. A [Task Callback] message will be delivered when done."
-	idLabel := "card_id"
-	if args.Cron != "" {
-		status = "scheduled"
-		message = fmt.Sprintf("Recurring task scheduled (cron: %s). The task will be submitted automatically on each trigger.", args.Cron)
-		idLabel = "schedule_id"
-	} else if args.Delay != "" {
-		status = "delayed"
-		message = fmt.Sprintf("Task will be submitted after %s delay.", args.Delay)
-		idLabel = "timer_id"
-	}
-
-	out, _ := json.Marshal(map[string]string{
-		idLabel:           cardID,
-		"status":          status,
-		"target_agent_id": args.TargetAgentID,
-		"message":         message,
-	})
-	return string(out), nil
-}
-
-// TaskContextTool allows the Dispatcher to retrieve the full context of a
-// previously dispatched async task, including the original user request,
-// dispatch note, task instruction, and execution result.
-//
-// Deprecated: this LLM tool implementation will be moved to
-// sdkx/tool/kanban in v0.3.0 alongside [SubmitTool]. The struct
-// shape is preserved across the move; only the import path changes.
-// See docs/migrations/v0.3.0.md.
-type TaskContextTool struct {
-	Kanban *Kanban
-}
-
-func (t *TaskContextTool) Definition() model.ToolDefinition {
-	return tool.DefineSchema("task_context",
-		"Retrieve the full context of a dispatched task, including original user request, "+
-			"your dispatch note, task instruction, and execution result. "+
-			"Use this when you receive a task callback and need to recall the original context.",
-		tool.Property("card_id", "string", "The card ID from the task callback message"),
-	).Required("card_id").Build()
-}
-
-func (t *TaskContextTool) Execute(ctx context.Context, arguments string) (string, error) {
-	k := t.resolve(ctx)
-	if k == nil {
-		return "", errdefs.NotAvailablef("task_context: no kanban instance available")
-	}
-
-	var args struct {
-		CardID string `json:"card_id"`
-	}
-	if err := json.Unmarshal([]byte(arguments), &args); err != nil {
-		return "", fmt.Errorf("task_context: invalid arguments: %w", err)
-	}
-
-	card, err := k.GetCard(ctx, args.CardID)
-	if err != nil {
-		return "", fmt.Errorf("task_context: %w", err)
-	}
-
-	return BuildTaskContext(card), nil
-}
-
-func (t *TaskContextTool) resolve(ctx context.Context) *Kanban {
-	if t.Kanban != nil {
-		return t.Kanban
-	}
-	return KanbanFrom(ctx)
-}
-
-// resolve returns the Kanban instance: struct field first, context fallback.
-func (t *SubmitTool) resolve(ctx context.Context) *Kanban {
-	if t.Kanban != nil {
-		return t.Kanban
-	}
-	return KanbanFrom(ctx)
-}
-
-// WithKanban attaches a [Kanban] instance to ctx so the LLM-facing
-// [SubmitTool] / [TaskContextTool] can resolve it without a struct
-// field. Used by hosts that wire tools into a registry before the
-// Kanban instance is constructed.
-//
-// Deprecated: moves to sdkx/tool/kanban in v0.3.0 alongside the
-// tool types. See docs/migrations/v0.3.0.md.
-func WithKanban(ctx context.Context, k *Kanban) context.Context {
-	return context.WithValue(ctx, ctxKeyKanban, k)
-}
-
-// KanbanFrom retrieves the [Kanban] instance previously installed by
-// [WithKanban], or nil when absent.
-//
-// Deprecated: moves to sdkx/tool/kanban in v0.3.0 alongside the tool
-// types. See docs/migrations/v0.3.0.md.
-func KanbanFrom(ctx context.Context) *Kanban {
-	k, _ := ctx.Value(ctxKeyKanban).(*Kanban)
-	return k
-}
diff --git a/sdk/knowledge/deprecated.go b/sdk/knowledge/deprecated.go
deleted file mode 100644
--- a/sdk/knowledge/deprecated.go
+++ /dev/null
@@ -1,2149 +0,0 @@
-// Package knowledge — v0.2.x compatibility layer (removed in v0.3.0).
-//
-// This file is the single home for every symbol that the v0.3.0
-// architecture supersedes. Each symbol carries a // Deprecated: tag so
-// staticcheck (SA1019) flags new callers; the index below is the
-// canonical "what replaces what" map.
-//
-// === Replacement index ===
-//
-//	Storage / orchestration
-//	  Store                    -> *Service                      (sdk/knowledge)
-//	  FSStore                  -> factory.NewLocal              (sdk/knowledge/factory)
-//	  RetrievalStore           -> factory.NewRetrieval          (sdk/knowledge/factory)
-//	  CachedStore              -> (none — fold caching into the repo)
-//
-//	Data models
-//	  Document                 -> SourceDocument + DerivedLayer
-//	  SearchResult             -> Hit
-//	  SearchOptions            -> Query (with Scope/Mode/Layer)
-//	  Chunk                    -> DerivedChunk
-//	  ContextLayer             -> Layer        (alias kept for transition)
-//	  SearchMode               -> Mode         (alias kept for transition)
-//	  ModeSemantic             -> ModeVector
-//
-//	Graph node
-//	  KnowledgeConfig          -> KnowledgeNodeConfig
-//	  KnowledgeNode            -> KnowledgeServiceNode
-//	  NewKnowledgeNode         -> NewKnowledgeServiceNode
-//	  KnowledgeConfigFromMap   -> KnowledgeNodeConfigFromMap
-//	  RegisterNode             -> RegisterServiceNode
-//	  KnowledgeNodeSchema      -> KnowledgeServiceNodeSchema
-//
-//	LLM tools
-//	  NewSearchTool            -> NewSearchServiceTool
-//	  NewAddTool               -> NewPutServiceTool
-//
-//	Reload pipeline
-//	  ChangeNotifier           -> EventNotifier  (typed ChangeEvent stream)
-//	  Reloader                 -> EventReloader  (scope-aware, serialised)
-//	  NewReloader              -> NewEventReloader
-//
-//	Helpers
-//	  ChunkDocument            -> ChunkText      (returns DerivedChunk)
-//	  RankResults              -> RRFRanker (the SearchEngine.Ranker)
-//	  RRFMerge                 -> RRFRanker
-//	  ScoreChunk               -> textsearch.BM25 directly
-//	  parseFrontmatter         -> Service handles frontmatter internally
-//
-// === Behaviour bridges that survive v0.3.0 ===
-//
-//	ResolveMode("")           -> ModeBM25
-//	ResolveMode("semantic")   -> ModeVector
-//	KnowledgeNodeConfigFromMap reads "max_layer" as "layer" when
-//	  "layer" is absent.
-//
-// === Things that are NOT deprecated ===
-//
-//	GenerateDocumentContext / GenerateDatasetContext — the L0/L1
-//	  derivation helpers remain external to Service so callers control
-//	  scheduling, retry and persistence policy.
-//	DatasetQuery — shared by knowledgenode.Config and the legacy
-//	  KnowledgeConfig (lives in this file because both consumers reach it
-//	  through the knowledge package).
-//	Tokenizer / textsearch.Tokenizer — backend-neutral utility.
-//	CosineSimilarity — used by backend implementations.
-package knowledge
-
-import (
-	"container/list"
-	"context"
-	"encoding/json"
-	"errors"
-	"fmt"
-	"math"
-	"path/filepath"
-	"sort"
-	"strings"
-	"sync"
-	"time"
-
-	"github.com/GizClaw/flowcraft/sdk/embedding"
-	"github.com/GizClaw/flowcraft/sdk/errdefs"
-	"github.com/GizClaw/flowcraft/sdk/retrieval"
-	"github.com/GizClaw/flowcraft/sdk/retrieval/pipeline"
-	"github.com/GizClaw/flowcraft/sdk/telemetry"
-	"github.com/GizClaw/flowcraft/sdk/textsearch"
-	"github.com/GizClaw/flowcraft/sdk/tool"
-	"github.com/GizClaw/flowcraft/sdk/workspace"
-
-	otellog "go.opentelemetry.io/otel/log"
-)
-
-// =============================================================================
-// Shared dataset query descriptor
-// =============================================================================
-
-// DatasetQuery describes a single dataset search within a Knowledge node.
-// Re-used by both the v0.3.0 knowledgenode.Config and the deprecated
-// KnowledgeConfig (kept stable across versions).
-type DatasetQuery struct {
-	DatasetID string `json:"dataset_id"`
-	StateKey  string `json:"state_key"`
-	TopK      int    `json:"top_k"`
-}
-
-// =============================================================================
-// Data models
-// =============================================================================
-
-// Document represents a knowledge base document.
-//
-// Deprecated: use SourceDocument (raw content + Version) and DerivedLayer
-// (L0/L1) separately. Document conflates the two and is removed in v0.3.0.
-type Document struct {
-	Name     string            `json:"name"`
-	Content  string            `json:"content"`
-	Abstract string            `json:"abstract,omitempty"` // L0
-	Overview string            `json:"overview,omitempty"` // L1
-	Metadata map[string]string `json:"metadata,omitempty"`
-}
-
-// SearchResult represents a single search hit with its relevance score.
-//
-// Deprecated: use Hit. SearchResult is removed in v0.3.0.
-type SearchResult struct {
-	Content    string         `json:"content"`
-	Score      float64        `json:"score"`
-	DocName    string         `json:"doc_name,omitempty"`
-	ChunkIndex int            `json:"chunk_index,omitempty"`
-	Layer      ContextLayer   `json:"layer"`
-	Metadata   map[string]any `json:"metadata,omitempty"`
-}
-
-// SearchOptions configures a knowledge search query.
-//
-// Deprecated: use Query. The MaxLayer→Layer rename and ScopeAllDatasets
-// fan-out live on Query. SearchOptions is removed in v0.3.0.
-type SearchOptions struct {
-	TopK      int          `json:"top_k,omitempty"`
-	MaxLayer  ContextLayer `json:"max_layer,omitempty"`
-	Threshold float64      `json:"threshold,omitempty"`
-	Mode      SearchMode   `json:"mode,omitempty"`
-}
-
-// Chunk represents a segment of a document.
-//
-// Deprecated: use DerivedChunk. Chunk is removed in v0.3.0.
-type Chunk struct {
-	DocName string `json:"doc_name"`
-	Index   int    `json:"index"`
-	Content string `json:"content"`
-	Offset  int    `json:"offset"`
-}
-
-// =============================================================================
-// Store interface + DocInput
-// =============================================================================
-
-// DocInput is a name+content pair for batch document ingestion.
-//
-// Deprecated: use Service.PutDocument (one call per document).
-// Removed in v0.3.0.
-type DocInput struct {
-	Name    string
-	Content string
-}
-
-// Store abstracts knowledge base storage. Documents are organized by dataset.
-//
-// Deprecated: use *Service in sdk/knowledge instead. Service unifies
-// document, chunk and layer storage behind a single contract and is the
-// only orchestrator going forward; Store will be removed in v0.3.0.
-//
-// Migration:
-//   - Replace AddDocument / AddDocuments with Service.PutDocument.
-//   - Replace Search                          with Service.Search.
-//   - Replace Abstract / Overview             with Service.Layer.
-//   - Replace DatasetAbstract / Overview      with Service.DatasetLayer.
-type Store interface {
-	AddDocument(ctx context.Context, datasetID, name, content string) error
-	AddDocuments(ctx context.Context, datasetID string, docs []DocInput) error
-	GetDocument(ctx context.Context, datasetID, name string) (*Document, error)
-	DeleteDocument(ctx context.Context, datasetID, name string) error
-	ListDocuments(ctx context.Context, datasetID string) ([]Document, error)
-	Search(ctx context.Context, datasetID, query string, opts SearchOptions) ([]SearchResult, error)
-
-	Abstract(ctx context.Context, datasetID, name string) (string, error)
-	Overview(ctx context.Context, datasetID, name string) (string, error)
-
-	DatasetAbstract(ctx context.Context, datasetID string) (string, error)
-	DatasetOverview(ctx context.Context, datasetID string) (string, error)
-}
-
-// =============================================================================
-// Legacy chunker (returns Chunk; see chunking.go for the v0.3.0 ChunkText)
-// =============================================================================
-
-// ChunkDocument splits content into overlapping chunks, preferring to
-// break at paragraph or sentence boundaries.
-//
-// Deprecated: use ChunkText (returns []DerivedChunk). Removed in v0.3.0.
-func ChunkDocument(docName, content string, cfg ChunkConfig) []Chunk {
-	if cfg.ChunkSize <= 0 {
-		cfg.ChunkSize = 512
-	}
-	if cfg.ChunkOverlap < 0 {
-		cfg.ChunkOverlap = 0
-	}
-	if cfg.ChunkOverlap >= cfg.ChunkSize {
-		cfg.ChunkOverlap = cfg.ChunkSize / 4
-	}
-
-	content = strings.TrimSpace(content)
-	if len(content) == 0 {
-		return nil
-	}
-	if len(content) <= cfg.ChunkSize {
-		return []Chunk{{DocName: docName, Index: 0, Content: content, Offset: 0}}
-	}
-
-	var chunks []Chunk
-	step := cfg.ChunkSize - cfg.ChunkOverlap
-	if step <= 0 {
-		step = 1
-	}
-
-	for offset := 0; offset < len(content); {
-		end := offset + cfg.ChunkSize
-		if end > len(content) {
-			end = len(content)
-		}
-
-		if end < len(content) {
-			if bp := legacyFindBreak(content[offset:end], "\n\n"); bp > 0 {
-				end = offset + bp
-			} else if bp := legacyFindBreak(content[offset:end], ". "); bp > 0 {
-				end = offset + bp + 1
-			} else if bp := legacyFindBreak(content[offset:end], "\n"); bp > 0 {
-				end = offset + bp
-			}
-		}
-
-		chunk := strings.TrimSpace(content[offset:end])
-		if chunk != "" {
-			chunks = append(chunks, Chunk{
-				DocName: docName,
-				Index:   len(chunks),
-				Content: chunk,
-				Offset:  offset,
-			})
-		}
-
-		nextOffset := offset + (end - offset)
-		if nextOffset <= offset {
-			nextOffset = offset + step
-		}
-		nextOffset -= cfg.ChunkOverlap
-		if nextOffset <= offset {
-			nextOffset = offset + 1
-		}
-		if nextOffset >= len(content) {
-			break
-		}
-		offset = nextOffset
-	}
-	return chunks
-}
-
-// legacyFindBreak is the deprecated counterpart of the v0.3.0 chunker's
-// boundary search. Renamed to avoid colliding with chunking.go's findBreak.
-func legacyFindBreak(s, sep string) int {
-	minPos := len(s) * 3 / 4
-	if minPos < len(s)/2 {
-		minPos = len(s) / 2
-	}
-	idx := strings.LastIndex(s[minPos:], sep)
-	if idx < 0 {
-		return -1
-	}
-	return minPos + idx
-}
-
-// =============================================================================
-// Legacy ranking helpers
-// =============================================================================
-
-// ScoreChunk computes the BM25 score for a chunk against query keywords.
-//
-// Deprecated: use textsearch.BM25 directly with DerivedChunk content.
-// Removed in v0.3.0.
-func ScoreChunk(chunk *Chunk, keywords []string, corpus *CorpusStats, tokenizer Tokenizer) float64 {
-	if corpus == nil || corpus.DocCount == 0 || len(keywords) == 0 {
-		return 0
-	}
-	tokens := tokenizer.Tokenize(chunk.Content)
-	return textsearch.BM25(tokens, keywords, corpus)
-}
-
-// RankResults sorts by score descending and limits to topK.
-//
-// Deprecated: use the SearchEngine's Ranker (RRFRanker by default).
-// Removed in v0.3.0.
-func RankResults(results []SearchResult, topK int) []SearchResult {
-	sort.Slice(results, func(i, j int) bool {
-		return results[i].Score > results[j].Score
-	})
-	if topK > 0 && len(results) > topK {
-		results = results[:topK]
-	}
-	return results
-}
-
-// rrfKey is the deduplication key for RRFMerge.
-func rrfKey(r SearchResult) string {
-	return fmt.Sprintf("%s|%d", r.DocName, r.ChunkIndex)
-}
-
-// RRFMerge fuses two ranked SearchResult lists with reciprocal-rank fusion.
-//
-// Deprecated: use RRFRanker. Removed in v0.3.0.
-func RRFMerge(bm25Results, semanticResults []SearchResult, k int) []SearchResult {
-	if k <= 0 {
-		k = 60
-	}
-	type scored struct {
-		result SearchResult
-		rrf    float64
-	}
-	merged := make(map[string]*scored)
-	for rank, r := range bm25Results {
-		key := rrfKey(r)
-		if s, ok := merged[key]; ok {
-			s.rrf += 1.0 / float64(rank+k)
-		} else {
-			merged[key] = &scored{result: r, rrf: 1.0 / float64(rank+k)}
-		}
-	}
-	for rank, r := range semanticResults {
-		key := rrfKey(r)
-		if s, ok := merged[key]; ok {
-			s.rrf += 1.0 / float64(rank+k)
-		} else {
-			merged[key] = &scored{result: r, rrf: 1.0 / float64(rank+k)}
-		}
-	}
-	results := make([]SearchResult, 0, len(merged))
-	for _, s := range merged {
-		s.result.Score = s.rrf
-		results = append(results, s.result)
-	}
-	return results
-}
-
-// parseFrontmatter extracts YAML frontmatter (between "---" delimiters).
-//
-// Deprecated: Service / DocumentRepo handle frontmatter internally; this
-// helper exists only for the legacy FSStore / RetrievalStore code paths.
-// Removed in v0.3.0.
-func parseFrontmatter(raw string) (body string, meta map[string]string) {
-	if !strings.HasPrefix(raw, "---\n") {
-		return raw, nil
-	}
-	end := strings.Index(raw[4:], "\n---")
-	if end < 0 {
-		return raw, nil
-	}
-	fmBlock := raw[4 : 4+end]
-	body = strings.TrimLeft(raw[4+end+4:], "\n")
-	meta = make(map[string]string)
-	for _, line := range strings.Split(fmBlock, "\n") {
-		line = strings.TrimSpace(line)
-		if line == "" {
-			continue
-		}
-		parts := strings.SplitN(line, ":", 2)
-		if len(parts) == 2 {
-			meta[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
-		}
-	}
-	return body, meta
-}
-
-func legacyIsMarkdown(name string) bool {
-	ext := strings.ToLower(filepath.Ext(name))
-	return ext == ".md" || ext == ".markdown" || ext == ".txt"
-}
-
-// =============================================================================
-// FSStore (filesystem-backed Store implementation)
-// =============================================================================
-
-type posting struct {
-	chunk *Chunk
-	tf    int
-	dl    int
-}
-
-type datasetIndex struct {
-	chunks        []*Chunk
-	docs          map[string]*Document
-	stats         *CorpusStats
-	abstractStats *CorpusStats
-	abstract      string
-	overview      string
-	inverted      map[string][]posting
-	vectors       map[*Chunk][]float32
-}
-
-func (di *datasetIndex) addChunkToInverted(chunk *Chunk, tokens []string) {
-	tf := make(map[string]int, len(tokens))
-	for _, t := range tokens {
-		tf[t]++
-	}
-	dl := len(tokens)
-	for term, freq := range tf {
-		di.inverted[term] = append(di.inverted[term], posting{chunk: chunk, tf: freq, dl: dl})
-	}
-}
-
-func (di *datasetIndex) removeFromInverted(docName string) {
-	for term, postings := range di.inverted {
-		var kept []posting
-		for _, p := range postings {
-			if p.chunk.DocName != docName {
-				kept = append(kept, p)
-			}
-		}
-		if len(kept) == 0 {
-			delete(di.inverted, term)
-		} else {
-			di.inverted[term] = kept
-		}
-	}
-}
-
-func (di *datasetIndex) searchL2(keywords []string, threshold float64) []SearchResult {
-	if len(di.inverted) == 0 {
-		return nil
-	}
-	type chunkScore struct {
-		chunk *Chunk
-		score float64
-	}
-	scores := make(map[*Chunk]*chunkScore)
-	k1 := 1.2
-	b := 0.75
-	avgDL := di.stats.AvgLength
-	if avgDL <= 0 {
-		avgDL = 1
-	}
-	for _, kw := range keywords {
-		postings, ok := di.inverted[kw]
-		if !ok {
-			continue
-		}
-		df := di.stats.DocFreq[kw]
-		n := float64(di.stats.DocCount)
-		idf := math.Log((n-float64(df)+0.5)/(float64(df)+0.5) + 1.0)
-		for _, p := range postings {
-			dl := float64(p.dl)
-			tfNorm := float64(p.tf) * (k1 + 1) / (float64(p.tf) + k1*(1-b+b*dl/avgDL))
-			cs, ok := scores[p.chunk]
-			if !ok {
-				cs = &chunkScore{chunk: p.chunk}
-				scores[p.chunk] = cs
-			}
-			cs.score += idf * tfNorm
-		}
-	}
-	var results []SearchResult
-	for _, cs := range scores {
-		if cs.score >= threshold {
-			results = append(results, SearchResult{
-				Content:    cs.chunk.Content,
-				Score:      cs.score,
-				DocName:    cs.chunk.DocName,
-				ChunkIndex: cs.chunk.Index,
-				Layer:      LayerDetail,
-			})
-		}
-	}
-	return results
-}
-
-// FSStoreOption configures an FSStore.
-//
-// Deprecated: see FSStore.
-type FSStoreOption func(*FSStore)
-
-// WithTokenizer sets the tokenizer for search and indexing.
-//
-// Deprecated: pass tokenizer through factory.WithLocalTokenizer.
-func WithTokenizer(t Tokenizer) FSStoreOption {
-	return func(s *FSStore) { s.tokenizer = t }
-}
-
-// WithChunkConfig sets the chunking configuration.
-//
-// Deprecated: configure ChunkConfig on factory.NewLocal's chunker option.
-func WithChunkConfig(cfg ChunkConfig) FSStoreOption {
-	return func(s *FSStore) { s.chunkCfg = cfg }
-}
-
-// WithEmbedder sets the embedder for semantic/hybrid search.
-//
-// Deprecated: pass embedder through factory.WithLocalEmbedder.
-func WithEmbedder(e Embedder) FSStoreOption {
-	return func(s *FSStore) { s.embedder = e }
-}
-
-// FSStore implements Store using a Workspace-backed file tree.
-//
-// Deprecated: use factory.NewLocal(ws, opts...). Removed in v0.3.0.
-type FSStore struct {
-	ws        workspace.Workspace
-	prefix    string
-	mu        sync.RWMutex
-	index     map[string]*datasetIndex
-	tokenizer Tokenizer
-	chunkCfg  ChunkConfig
-	embedder  Embedder
-}
-
-// NewFSStore creates a knowledge store rooted at the given prefix.
-//
-// Deprecated: use factory.NewLocal(ws, opts...). Removed in v0.3.0.
-func NewFSStore(ws workspace.Workspace, opts ...FSStoreOption) *FSStore {
-	s := &FSStore{
-		ws:       ws,
-		prefix:   "knowledge",
-		index:    make(map[string]*datasetIndex),
-		chunkCfg: DefaultChunkConfig(),
-	}
-	for _, opt := range opts {
-		opt(s)
-	}
-	if s.tokenizer == nil {
-		s.tokenizer = &CJKTokenizer{}
-	}
-	return s
-}
-
-// BuildIndex scans all datasets and builds the in-memory search index.
-func (s *FSStore) BuildIndex(ctx context.Context) error {
-	entries, err := s.ws.List(ctx, s.prefix)
-	if err != nil {
-		return fmt.Errorf("knowledge: build index: %w", err)
-	}
-	idx := make(map[string]*datasetIndex)
-	var errs []error
-	for _, entry := range entries {
-		if !entry.IsDir() {
-			continue
-		}
-		dsID := entry.Name()
-		di, err := s.buildDatasetIndex(ctx, dsID)
-		if err != nil {
-			telemetry.Warn(ctx, "knowledge: failed to index dataset",
-				otellog.String("dataset", dsID), otellog.String(telemetry.AttrErrorMessage, err.Error()))
-			errs = append(errs, fmt.Errorf("dataset %q: %w", dsID, err))
-			continue
-		}
-		idx[dsID] = di
-	}
-	s.mu.Lock()
-	s.index = idx
-	s.mu.Unlock()
-	return errors.Join(errs...)
-}
-
-func (s *FSStore) buildDatasetIndex(ctx context.Context, datasetID string) (*datasetIndex, error) {
-	docs, err := s.listDocsFromDisk(ctx, datasetID)
-	if err != nil {
-		return nil, err
-	}
-	di := &datasetIndex{
-		docs:          make(map[string]*Document, len(docs)),
-		stats:         NewCorpusStats(),
-		abstractStats: NewCorpusStats(),
-		inverted:      make(map[string][]posting),
-		vectors:       make(map[*Chunk][]float32),
-	}
-	for i := range docs {
-		doc := &docs[i]
-		di.docs[doc.Name] = doc
-		doc.Abstract, _ = s.readSidecar(ctx, datasetID, doc.Name, ".abstract")
-		doc.Overview, _ = s.readSidecar(ctx, datasetID, doc.Name, ".overview")
-		chunks := ChunkDocument(doc.Name, doc.Content, s.chunkCfg)
-		for j := range chunks {
-			c := &chunks[j]
-			tokens := s.tokenizer.Tokenize(c.Content)
-			di.chunks = append(di.chunks, c)
-			di.stats.AddDocument(tokens)
-			di.addChunkToInverted(c, tokens)
-		}
-	}
-	for _, doc := range di.docs {
-		if doc.Abstract != "" {
-			di.abstractStats.AddDocument(s.tokenizer.Tokenize(doc.Abstract))
-		}
-	}
-	di.abstract, _ = s.readFile(ctx, filepath.Join(s.prefix, datasetID, ".abstract.md"))
-	di.overview, _ = s.readFile(ctx, filepath.Join(s.prefix, datasetID, ".overview.md"))
-	return di, nil
-}
-
-func (s *FSStore) AddDocument(ctx context.Context, datasetID, name, content string) error {
-	if datasetID == "" || name == "" {
-		return errdefs.Validationf("knowledge: dataset_id and name are required")
-	}
-	path := s.docPath(datasetID, name)
-	if err := s.ws.Write(ctx, path, []byte(content)); err != nil {
-		return fmt.Errorf("knowledge: write document: %w", err)
-	}
-	parsedContent, meta := parseFrontmatter(content)
-	doc := &Document{Name: name, Content: parsedContent, Metadata: meta}
-	chunks := ChunkDocument(name, parsedContent, s.chunkCfg)
-	s.mu.Lock()
-	di, ok := s.index[datasetID]
-	if !ok {
-		di = &datasetIndex{docs: make(map[string]*Document), stats: NewCorpusStats(), abstractStats: NewCorpusStats(), inverted: make(map[string][]posting), vectors: make(map[*Chunk][]float32)}
-		s.index[datasetID] = di
-	}
-	if oldDoc, exists := di.docs[name]; exists {
-		s.removeDocChunks(di, oldDoc.Name)
-	}
-	addedChunks := make([]*Chunk, len(chunks))
-	di.docs[name] = doc
-	for i := range chunks {
-		c := &chunks[i]
-		tokens := s.tokenizer.Tokenize(c.Content)
-		di.chunks = append(di.chunks, c)
-		di.stats.AddDocument(tokens)
-		di.addChunkToInverted(c, tokens)
-		addedChunks[i] = c
-	}
-	s.mu.Unlock()
-	if s.embedder != nil {
-		texts := make([]string, len(addedChunks))
-		for i, c := range addedChunks {
-			texts[i] = c.Content
-		}
-		if vecs, err := s.embedder.EmbedBatch(ctx, texts); err == nil && len(vecs) == len(addedChunks) {
-			s.mu.Lock()
-			if currentDI, ok := s.index[datasetID]; ok && currentDI == di {
-				for i, c := range addedChunks {
-					currentDI.vectors[c] = vecs[i]
-				}
-			}
-			s.mu.Unlock()
-		}
-	}
-	return nil
-}
-
-func (s *FSStore) AddDocuments(ctx context.Context, datasetID string, docs []DocInput) error {
-	if datasetID == "" {
-		return errdefs.Validationf("knowledge: dataset_id is required")
-	}
-	if len(docs) == 0 {
-		return nil
-	}
-	type prepared struct {
-		doc    *Document
-		chunks []Chunk
-	}
-	items := make([]prepared, 0, len(docs))
-	for _, d := range docs {
-		if d.Name == "" {
-			continue
-		}
-		path := s.docPath(datasetID, d.Name)
-		if err := s.ws.Write(ctx, path, []byte(d.Content)); err != nil {
-			return fmt.Errorf("knowledge: write document %s: %w", d.Name, err)
-		}
-		parsedContent, meta := parseFrontmatter(d.Content)
-		items = append(items, prepared{
-			doc:    &Document{Name: d.Name, Content: parsedContent, Metadata: meta},
-			chunks: ChunkDocument(d.Name, parsedContent, s.chunkCfg),
-		})
-	}
-	var allChunks []*Chunk
-	s.mu.Lock()
-	di, ok := s.index[datasetID]
-	if !ok {
-		di = &datasetIndex{docs: make(map[string]*Document), stats: NewCorpusStats(), abstractStats: NewCorpusStats(), inverted: make(map[string][]posting), vectors: make(map[*Chunk][]float32)}
-		s.index[datasetID] = di
-	}
-	for _, item := range items {
-		if _, exists := di.docs[item.doc.Name]; exists {
-			s.removeDocChunks(di, item.doc.Name)
-		}
-		di.docs[item.doc.Name] = item.doc
-		for i := range item.chunks {
-			c := &item.chunks[i]
-			tokens := s.tokenizer.Tokenize(c.Content)
-			di.chunks = append(di.chunks, c)
-			di.stats.AddDocument(tokens)
-			di.addChunkToInverted(c, tokens)
-			allChunks = append(allChunks, c)
-		}
-	}
-	s.mu.Unlock()
-	if s.embedder != nil && len(allChunks) > 0 {
-		texts := make([]string, len(allChunks))
-		for i, c := range allChunks {
-			texts[i] = c.Content
-		}
-		if vecs, err := s.embedder.EmbedBatch(ctx, texts); err == nil && len(vecs) == len(allChunks) {
-			s.mu.Lock()
-			if currentDI, ok := s.index[datasetID]; ok && currentDI == di {
-				for i, c := range allChunks {
-					currentDI.vectors[c] = vecs[i]
-				}
-			}
-			s.mu.Unlock()
-		}
-	}
-	return nil
-}
-
-// ReindexVectors regenerates vector embeddings for all indexed chunks.
-func (s *FSStore) ReindexVectors(ctx context.Context) error {
-	if s.embedder == nil {
-		return nil
-	}
-	s.mu.RLock()
-	type work struct {
-		dsID   string
-		chunks []*Chunk
-	}
-	var tasks []work
-	for dsID, di := range s.index {
-		chunks := make([]*Chunk, len(di.chunks))
-		copy(chunks, di.chunks)
-		tasks = append(tasks, work{dsID: dsID, chunks: chunks})
-	}
-	s.mu.RUnlock()
-	for _, t := range tasks {
-		if len(t.chunks) == 0 {
-			continue
-		}
-		texts := make([]string, len(t.chunks))
-		for i, c := range t.chunks {
-			texts[i] = c.Content
-		}
-		vecs, err := s.embedder.EmbedBatch(ctx, texts)
-		if err != nil {
-			return fmt.Errorf("knowledge: reindex vectors for %s: %w", t.dsID, err)
-		}
-		s.mu.Lock()
-		if di, ok := s.index[t.dsID]; ok {
-			for i, c := range t.chunks {
-				if i < len(vecs) {
-					di.vectors[c] = vecs[i]
-				}
-			}
-		}
-		s.mu.Unlock()
-	}
-	return nil
-}
-
-func (s *FSStore) GetDocument(ctx context.Context, datasetID, name string) (*Document, error) {
-	s.mu.RLock()
-	if di, ok := s.index[datasetID]; ok {
-		if doc, ok := di.docs[name]; ok {
-			cp := *doc
-			if doc.Metadata != nil {
-				cp.Metadata = make(map[string]string, len(doc.Metadata))
-				for k, v := range doc.Metadata {
-					cp.Metadata[k] = v
-				}
-			}
-			s.mu.RUnlock()
-			return &cp, nil
-		}
-	}
-	s.mu.RUnlock()
-	path := s.docPath(datasetID, name)
-	data, err := s.ws.Read(ctx, path)
-	if err != nil {
-		return nil, fmt.Errorf("knowledge: get %s/%s: %w", datasetID, name, err)
-	}
-	content, meta := parseFrontmatter(string(data))
-	doc := &Document{Name: name, Content: content, Metadata: meta}
-	doc.Abstract, _ = s.readSidecar(ctx, datasetID, name, ".abstract")
-	doc.Overview, _ = s.readSidecar(ctx, datasetID, name, ".overview")
-	return doc, nil
-}
-
-func (s *FSStore) DeleteDocument(ctx context.Context, datasetID, name string) error {
-	path := s.docPath(datasetID, name)
-	if err := s.ws.Delete(ctx, path); err != nil {
-		return fmt.Errorf("knowledge: delete %s/%s: %w", datasetID, name, err)
-	}
-	_ = s.deleteSidecar(ctx, datasetID, name, ".abstract")
-	_ = s.deleteSidecar(ctx, datasetID, name, ".overview")
-	s.mu.Lock()
-	if di, ok := s.index[datasetID]; ok {
-		s.removeDocChunks(di, name)
-		delete(di.docs, name)
-	}
-	s.mu.Unlock()
-	return nil
-}
-
-func (s *FSStore) ListDocuments(ctx context.Context, datasetID string) ([]Document, error) {
-	s.mu.RLock()
-	if di, ok := s.index[datasetID]; ok && len(di.docs) > 0 {
-		docs := make([]Document, 0, len(di.docs))
-		for _, d := range di.docs {
-			docs = append(docs, *d)
-		}
-		s.mu.RUnlock()
-		return docs, nil
-	}
-	s.mu.RUnlock()
-	return s.listDocsFromDisk(ctx, datasetID)
-}
-
-func (s *FSStore) listDocsFromDisk(ctx context.Context, datasetID string) ([]Document, error) {
-	dir := filepath.Join(s.prefix, datasetID)
-	entries, err := s.ws.List(ctx, dir)
-	if err != nil {
-		return nil, fmt.Errorf("knowledge: list %s: %w", datasetID, err)
-	}
-	var docs []Document
-	for _, e := range entries {
-		if e.IsDir() || !legacyIsMarkdown(e.Name()) {
-			continue
-		}
-		data, err := s.ws.Read(ctx, filepath.Join(dir, e.Name()))
-		if err != nil {
-			continue
-		}
-		content, meta := parseFrontmatter(string(data))
-		docs = append(docs, Document{Name: e.Name(), Content: content, Metadata: meta})
-	}
-	return docs, nil
-}
-
-// Search performs a two-level search over the in-memory index.
-func (s *FSStore) Search(ctx context.Context, datasetID, query string, opts SearchOptions) ([]SearchResult, error) {
-	if opts.TopK <= 0 {
-		opts.TopK = 5
-	}
-	if opts.MaxLayer == "" {
-		opts.MaxLayer = LayerDetail
-	}
-	if opts.Threshold <= 0 {
-		opts.Threshold = DefaultThreshold
-	}
-	switch opts.Mode {
-	case ModeSemantic:
-		return s.searchSemanticOnly(ctx, datasetID, query, opts)
-	case ModeHybrid:
-		return s.searchHybrid(ctx, datasetID, query, opts)
-	default:
-		keywords := ExtractKeywords(query, s.tokenizer)
-		if len(keywords) == 0 {
-			return nil, nil
-		}
-		if datasetID != "" {
-			return s.searchDataset(ctx, datasetID, query, keywords, opts)
-		}
-		return s.searchAcrossDatasets(ctx, query, keywords, opts)
-	}
-}
-
-func (s *FSStore) searchSemanticOnly(ctx context.Context, datasetID, query string, opts SearchOptions) ([]SearchResult, error) {
-	if s.embedder == nil {
-		return s.Search(ctx, datasetID, query, SearchOptions{TopK: opts.TopK, MaxLayer: opts.MaxLayer, Threshold: opts.Threshold})
-	}
-	qvecs, err := s.embedder.EmbedBatch(ctx, []string{query})
-	if err != nil || len(qvecs) == 0 {
-		return s.Search(ctx, datasetID, query, SearchOptions{TopK: opts.TopK, MaxLayer: opts.MaxLayer, Threshold: opts.Threshold})
-	}
-	qvec := qvecs[0]
-	s.mu.RLock()
-	defer s.mu.RUnlock()
-	var results []SearchResult
-	datasets := make(map[string]*datasetIndex)
-	if datasetID != "" {
-		if di, ok := s.index[datasetID]; ok {
-			datasets[datasetID] = di
-		}
-	} else {
-		for id, di := range s.index {
-			datasets[id] = di
-		}
-	}
-	for _, di := range datasets {
-		if ctx.Err() != nil {
-			return nil, ctx.Err()
-		}
-		for chunk, vec := range di.vectors {
-			sim := cosineSimilarity(qvec, vec)
-			if sim >= opts.Threshold {
-				results = append(results, SearchResult{
-					Content:    chunk.Content,
-					Score:      sim,
-					DocName:    chunk.DocName,
-					ChunkIndex: chunk.Index,
-					Layer:      LayerDetail,
-				})
-			}
-		}
-	}
-	return RankResults(results, opts.TopK), nil
-}
-
-func (s *FSStore) searchHybrid(ctx context.Context, datasetID, query string, opts SearchOptions) ([]SearchResult, error) {
-	bm25Opts := SearchOptions{TopK: opts.TopK * 2, MaxLayer: opts.MaxLayer, Threshold: opts.Threshold}
-	keywords := ExtractKeywords(query, s.tokenizer)
-	var bm25Results []SearchResult
-	var firstErr error
-	if len(keywords) > 0 {
-		var err error
-		if datasetID != "" {
-			bm25Results, err = s.searchDataset(ctx, datasetID, query, keywords, bm25Opts)
-		} else {
-			bm25Results, err = s.searchAcrossDatasets(ctx, query, keywords, bm25Opts)
-		}
-		if err != nil {
-			firstErr = err
-		}
-	}
-	semanticResults, err := s.searchSemanticOnly(ctx, datasetID, query, SearchOptions{TopK: opts.TopK * 2, MaxLayer: opts.MaxLayer, Threshold: 0})
-	if err != nil && firstErr == nil {
-		firstErr = err
-	}
-	if len(bm25Results) == 0 && len(semanticResults) == 0 && firstErr != nil {
-		return nil, firstErr
-	}
-	merged := RRFMerge(bm25Results, semanticResults, 60)
-	return RankResults(merged, opts.TopK), nil
-}
-
-func (s *FSStore) searchDataset(ctx context.Context, datasetID, _ string, keywords []string, opts SearchOptions) ([]SearchResult, error) {
-	s.mu.RLock()
-	di, ok := s.index[datasetID]
-	if !ok {
-		s.mu.RUnlock()
-		return nil, nil
-	}
-	var results []SearchResult
-	switch opts.MaxLayer {
-	case LayerAbstract:
-		for _, doc := range di.docs {
-			if ctx.Err() != nil {
-				s.mu.RUnlock()
-				return nil, ctx.Err()
-			}
-			if doc.Abstract == "" {
-				continue
-			}
-			score := ScoreText(doc.Abstract, keywords, di.abstractStats, s.tokenizer)
-			if score >= opts.Threshold {
-				results = append(results, SearchResult{
-					Content: doc.Abstract, Score: score, DocName: doc.Name, Layer: LayerAbstract,
-				})
-			}
-		}
-	case LayerOverview:
-		for _, doc := range di.docs {
-			if ctx.Err() != nil {
-				s.mu.RUnlock()
-				return nil, ctx.Err()
-			}
-			content := doc.Overview
-			if content == "" {
-				content = doc.Abstract
-			}
-			if content == "" {
-				continue
-			}
-			score := ScoreText(content, keywords, di.stats, s.tokenizer)
-			layer := LayerOverview
-			if doc.Overview == "" {
-				layer = LayerAbstract
-			}
-			if score >= opts.Threshold {
-				results = append(results, SearchResult{
-					Content: content, Score: score, DocName: doc.Name, Layer: layer,
-				})
-			}
-		}
-	default:
-		results = di.searchL2(keywords, opts.Threshold)
-	}
-	s.mu.RUnlock()
-	return RankResults(results, opts.TopK), nil
-}
-
-func (s *FSStore) searchAcrossDatasets(ctx context.Context, _ string, keywords []string, opts SearchOptions) ([]SearchResult, error) {
-	s.mu.RLock()
-	defer s.mu.RUnlock()
-	var dsScores []dsScore
-	for dsID, di := range s.index {
-		if di.abstract != "" {
-			score := ScoreText(di.abstract, keywords, di.abstractStats, s.tokenizer)
-			dsScores = append(dsScores, dsScore{dsID, score})
-		} else {
-			dsScores = append(dsScores, dsScore{dsID, 0.1})
-		}
-	}
-	sortDSScores(dsScores)
-	maxDS := 3
-	if len(dsScores) < maxDS {
-		maxDS = len(dsScores)
-	}
-	var results []SearchResult
-	for _, ds := range dsScores[:maxDS] {
-		if ctx.Err() != nil {
-			return nil, ctx.Err()
-		}
-		di := s.index[ds.id]
-		switch opts.MaxLayer {
-		case LayerAbstract:
-			for _, doc := range di.docs {
-				if doc.Abstract != "" {
-					score := ScoreText(doc.Abstract, keywords, di.abstractStats, s.tokenizer)
-					if score >= opts.Threshold {
-						results = append(results, SearchResult{
-							Content: doc.Abstract, Score: score, DocName: doc.Name, Layer: LayerAbstract,
-						})
-					}
-				}
-			}
-		case LayerOverview:
-			for _, doc := range di.docs {
-				content := doc.Overview
-				if content == "" {
-					content = doc.Abstract
-				}
-				if content == "" {
-					continue
-				}
-				score := ScoreText(content, keywords, di.stats, s.tokenizer)
-				if score >= opts.Threshold {
-					results = append(results, SearchResult{
-						Content: content, Score: score, DocName: doc.Name, Layer: LayerOverview,
-					})
-				}
-			}
-		default:
-			results = append(results, di.searchL2(keywords, opts.Threshold)...)
-		}
-	}
-	return RankResults(results, opts.TopK), nil
-}
-
-type dsScore struct {
-	id    string
-	score float64
-}
-
-func sortDSScores(scores []dsScore) {
-	for i := 1; i < len(scores); i++ {
-		for j := i; j > 0 && scores[j].score > scores[j-1].score; j-- {
-			scores[j], scores[j-1] = scores[j-1], scores[j]
-		}
-	}
-}
-
-func (s *FSStore) Abstract(ctx context.Context, datasetID, name string) (string, error) {
-	s.mu.RLock()
-	if di, ok := s.index[datasetID]; ok {
-		if doc, ok := di.docs[name]; ok {
-			s.mu.RUnlock()
-			return doc.Abstract, nil
-		}
-	}
-	s.mu.RUnlock()
-	return s.readSidecar(ctx, datasetID, name, ".abstract")
-}
-
-func (s *FSStore) Overview(ctx context.Context, datasetID, name string) (string, error) {
-	s.mu.RLock()
-	if di, ok := s.index[datasetID]; ok {
-		if doc, ok := di.docs[name]; ok {
-			s.mu.RUnlock()
-			return doc.Overview, nil
-		}
-	}
-	s.mu.RUnlock()
-	return s.readSidecar(ctx, datasetID, name, ".overview")
-}
-
-func (s *FSStore) DatasetAbstract(_ context.Context, datasetID string) (string, error) {
-	s.mu.RLock()
-	defer s.mu.RUnlock()
-	if di, ok := s.index[datasetID]; ok {
-		return di.abstract, nil
-	}
-	return "", nil
-}
-
-func (s *FSStore) DatasetOverview(_ context.Context, datasetID string) (string, error) {
-	s.mu.RLock()
-	defer s.mu.RUnlock()
-	if di, ok := s.index[datasetID]; ok {
-		return di.overview, nil
-	}
-	return "", nil
-}
-
-func (s *FSStore) SetDocAbstract(datasetID, name, abstract string) {
-	s.mu.Lock()
-	defer s.mu.Unlock()
-	if di, ok := s.index[datasetID]; ok {
-		if doc, ok := di.docs[name]; ok {
-			if doc.Abstract != "" {
-				di.abstractStats.RemoveDocument(s.tokenizer.Tokenize(doc.Abstract))
-			}
-			doc.Abstract = abstract
-			if abstract != "" {
-				di.abstractStats.AddDocument(s.tokenizer.Tokenize(abstract))
-			}
-		}
-	}
-}
-
-func (s *FSStore) SetDocOverview(datasetID, name, overview string) {
-	s.mu.Lock()
-	defer s.mu.Unlock()
-	if di, ok := s.index[datasetID]; ok {
-		if doc, ok := di.docs[name]; ok {
-			doc.Overview = overview
-		}
-	}
-}
-
-func (s *FSStore) SetDatasetAbstract(datasetID, abstract string) {
-	s.mu.Lock()
-	defer s.mu.Unlock()
-	if di, ok := s.index[datasetID]; ok {
-		di.abstract = abstract
-	}
-}
-
-func (s *FSStore) SetDatasetOverview(datasetID, overview string) {
-	s.mu.Lock()
-	defer s.mu.Unlock()
-	if di, ok := s.index[datasetID]; ok {
-		di.overview = overview
-	}
-}
-
-func (s *FSStore) removeDocChunks(di *datasetIndex, docName string) {
-	di.removeFromInverted(docName)
-	var kept []*Chunk
-	for _, c := range di.chunks {
-		if c.DocName == docName {
-			di.stats.RemoveDocument(s.tokenizer.Tokenize(c.Content))
-			delete(di.vectors, c)
-		} else {
-			kept = append(kept, c)
-		}
-	}
-	di.chunks = kept
-}
-
-func (s *FSStore) docPath(datasetID, name string) string {
-	if !legacyIsMarkdown(name) {
-		name += ".md"
-	}
-	return filepath.Join(s.prefix, datasetID, name)
-}
-
-func (s *FSStore) readSidecar(ctx context.Context, datasetID, name, ext string) (string, error) {
-	base := strings.TrimSuffix(name, filepath.Ext(name))
-	path := filepath.Join(s.prefix, datasetID, base+ext)
-	return s.readFile(ctx, path)
-}
-
-func (s *FSStore) deleteSidecar(ctx context.Context, datasetID, name, ext string) error {
-	base := strings.TrimSuffix(name, filepath.Ext(name))
-	path := filepath.Join(s.prefix, datasetID, base+ext)
-	return s.ws.Delete(ctx, path)
-}
-
-func (s *FSStore) readFile(ctx context.Context, path string) (string, error) {
-	exists, err := s.ws.Exists(ctx, path)
-	if err != nil || !exists {
-		return "", err
-	}
-	data, err := s.ws.Read(ctx, path)
-	if err != nil {
-		return "", err
-	}
-	return string(data), nil
-}
-
-// WriteSidecar writes a per-document sidecar file (e.g. ".abstract",
-// ".overview") used to persist layered context derived externally.
-func (s *FSStore) WriteSidecar(ctx context.Context, datasetID, name, ext, content string) error {
-	base := strings.TrimSuffix(name, filepath.Ext(name))
-	path := filepath.Join(s.prefix, datasetID, base+ext)
-	return s.ws.Write(ctx, path, []byte(content))
-}
-
-// WriteDatasetFile writes a dataset-level file (e.g. .abstract.md, .overview.md).
-func (s *FSStore) WriteDatasetFile(ctx context.Context, datasetID, filename, content string) error {
-	path := filepath.Join(s.prefix, datasetID, filename)
-	return s.ws.Write(ctx, path, []byte(content))
-}
-
-// WorkspaceRoot exposes the underlying workspace root when available.
-//
-// Returns "" if the workspace does not implement Root().
-func (s *FSStore) WorkspaceRoot() string {
-	if rw, ok := s.ws.(interface{ Root() string }); ok {
-		return rw.Root()
-	}
-	return ""
-}
-
-// Prefix returns the FSStore directory prefix beneath WorkspaceRoot.
-func (s *FSStore) Prefix() string { return s.prefix }
-
-// =============================================================================
-// RetrievalStore (retrieval.Index-backed Store implementation)
-// =============================================================================
-
-// RetrievalStore is a Store implementation backed by a retrieval.Index.
-//
-// Deprecated: use factory.NewRetrieval(docs, idx, opts...) which returns a
-// *Service backed by backend/retrieval. Removed in v0.3.0.
-type RetrievalStore struct {
-	idx       retrieval.Index
-	embedder  embedding.Embedder
-	pipeline  *pipeline.Pipeline
-	chunkCfg  ChunkConfig
-	tokenizer Tokenizer
-	now       func() time.Time
-}
-
-// RetrievalStoreOption configures a RetrievalStore.
-//
-// Deprecated: see RetrievalStore.
-type RetrievalStoreOption func(*RetrievalStore)
-
-// WithRetrievalEmbedder sets the embedder used to vectorize chunks at write time.
-//
-// Deprecated: pass embedder through factory.WithRetrievalEmbedder.
-func WithRetrievalEmbedder(e embedding.Embedder) RetrievalStoreOption {
-	return func(s *RetrievalStore) { s.embedder = e }
-}
-
-// WithRetrievalPipeline overrides the default pipeline.Knowledge(emb, nil).
-//
-// Deprecated: factory.NewRetrieval owns the pipeline now.
-func WithRetrievalPipeline(p *pipeline.Pipeline) RetrievalStoreOption {
-	return func(s *RetrievalStore) { s.pipeline = p }
-}
-
-// WithRetrievalChunkConfig overrides the default chunk config.
-//
-// Deprecated: configure ChunkConfig via factory.WithRetrievalChunker.
-func WithRetrievalChunkConfig(c ChunkConfig) RetrievalStoreOption {
-	return func(s *RetrievalStore) { s.chunkCfg = c }
-}
-
-// WithRetrievalTokenizer overrides the BM25 tokenizer.
-//
-// Deprecated: factory wires the tokenizer through textsearch.
-func WithRetrievalTokenizer(t Tokenizer) RetrievalStoreOption {
-	return func(s *RetrievalStore) { s.tokenizer = t }
-}
-
-// NewRetrievalStore wires a Store to a retrieval.Index.
-//
-// Deprecated: use factory.NewRetrieval(docs, idx, opts...). Removed in v0.3.0.
-func NewRetrievalStore(idx retrieval.Index, opts ...RetrievalStoreOption) *RetrievalStore {
-	s := &RetrievalStore{
-		idx:      idx,
-		chunkCfg: DefaultChunkConfig(),
-		now:      time.Now,
-	}
-	for _, opt := range opts {
-		opt(s)
-	}
-	if s.tokenizer == nil {
-		s.tokenizer = DetectTokenizer("")
-	}
-	if s.pipeline == nil {
-		s.pipeline = pipeline.Knowledge(s.embedder, nil)
-	}
-	return s
-}
-
-// Index exposes the underlying retrieval.Index.
-func (s *RetrievalStore) Index() retrieval.Index { return s.idx }
-
-func chunkNS(dataset string) string   { return "kb_" + saneNS(dataset) + "__chunks" }
-func docMetaNS(dataset string) string { return "kb_" + saneNS(dataset) + "__docmeta" }
-
-const datasetMetaNS = "kb__datasets"
-
-func saneNS(s string) string {
-	if s == "" {
-		return "default"
-	}
-	var b strings.Builder
-	for _, r := range s {
-		switch {
-		case r >= 'a' && r <= 'z',
-			r >= 'A' && r <= 'Z',
-			r >= '0' && r <= '9',
-			r == '_':
-			b.WriteRune(r)
-		default:
-			b.WriteRune('_')
-		}
-	}
-	if b.Len() == 0 {
-		return "default"
-	}
-	return b.String()
-}
-
-func (s *RetrievalStore) AddDocument(ctx context.Context, datasetID, name, content string) error {
-	body, meta := parseFrontmatter(content)
-	if err := s.upsertDocChunks(ctx, datasetID, name, body, meta); err != nil {
-		return err
-	}
-	return s.upsertDocMeta(ctx, datasetID, name, meta)
-}
-
-func (s *RetrievalStore) AddDocuments(ctx context.Context, datasetID string, docs []DocInput) error {
-	for _, d := range docs {
-		if err := s.AddDocument(ctx, datasetID, d.Name, d.Content); err != nil {
-			return fmt.Errorf("add %s: %w", d.Name, err)
-		}
-	}
-	return nil
-}
-
-func (s *RetrievalStore) upsertDocChunks(ctx context.Context, datasetID, name, body string, meta map[string]string) error {
-	chunks := ChunkDocument(name, body, s.chunkCfg)
-	if len(chunks) == 0 {
-		return nil
-	}
-	docs := make([]retrieval.Doc, 0, len(chunks))
-	for _, c := range chunks {
-		md := map[string]any{
-			"dataset":     datasetID,
-			"doc_name":    name,
-			"chunk_index": c.Index,
-			"layer":       string(LayerDetail),
-		}
-		for k, v := range meta {
-			md["fm_"+k] = v
-		}
-		var vec []float32
-		if s.embedder != nil {
-			v, err := s.embedder.Embed(ctx, c.Content)
-			if err != nil {
-				return fmt.Errorf("embed chunk %d: %w", c.Index, err)
-			}
-			vec = v
-		}
-		docs = append(docs, retrieval.Doc{
-			ID:        chunkID(datasetID, name, c.Index),
-			Content:   c.Content,
-			Vector:    vec,
-			Metadata:  md,
-			Timestamp: s.now().UTC(),
-		})
-	}
-	return s.idx.Upsert(ctx, chunkNS(datasetID), docs)
-}
-
-func (s *RetrievalStore) upsertDocMeta(ctx context.Context, datasetID, name string, meta map[string]string) error {
-	md := map[string]any{
-		"dataset":  datasetID,
-		"doc_name": name,
-	}
-	for k, v := range meta {
-		md["fm_"+k] = v
-	}
-	doc := retrieval.Doc{
-		ID:        "doc:" + name,
-		Content:   name,
-		Metadata:  md,
-		Timestamp: s.now().UTC(),
-	}
-	return s.idx.Upsert(ctx, docMetaNS(datasetID), []retrieval.Doc{doc})
-}
-
-func (s *RetrievalStore) SetAbstract(ctx context.Context, datasetID, name, abstract string) error {
-	return s.upsertLayer(ctx, datasetID, name, LayerAbstract, abstract)
-}
-
-func (s *RetrievalStore) SetOverview(ctx context.Context, datasetID, name, overview string) error {
-	return s.upsertLayer(ctx, datasetID, name, LayerOverview, overview)
-}
-
-func (s *RetrievalStore) upsertLayer(ctx context.Context, datasetID, name string, layer ContextLayer, content string) error {
-	md := map[string]any{"dataset": datasetID, "doc_name": name, "layer": string(layer)}
-	var vec []float32
-	if s.embedder != nil {
-		v, err := s.embedder.Embed(ctx, content)
-		if err != nil {
-			return err
-		}
-		vec = v
-	}
-	return s.idx.Upsert(ctx, docMetaNS(datasetID), []retrieval.Doc{{
-		ID: string(layer) + ":" + name, Content: content, Vector: vec,
-		Metadata: md, Timestamp: s.now().UTC(),
-	}})
-}
-
-func (s *RetrievalStore) SetDatasetAbstract(ctx context.Context, datasetID, abstract string) error {
-	return s.idx.Upsert(ctx, datasetMetaNS, []retrieval.Doc{{
-		ID: "abstract:" + saneNS(datasetID), Content: abstract,
-		Metadata:  map[string]any{"dataset": datasetID, "layer": string(LayerAbstract)},
-		Timestamp: s.now().UTC(),
-	}})
-}
-
-func (s *RetrievalStore) SetDatasetOverview(ctx context.Context, datasetID, overview string) error {
-	return s.idx.Upsert(ctx, datasetMetaNS, []retrieval.Doc{{
-		ID: "overview:" + saneNS(datasetID), Content: overview,
-		Metadata:  map[string]any{"dataset": datasetID, "layer": string(LayerOverview)},
-		Timestamp: s.now().UTC(),
-	}})
-}
-
-func (s *RetrievalStore) GetDocument(ctx context.Context, datasetID, name string) (*Document, error) {
-	chunks, err := s.listChunksFor(ctx, datasetID, name)
-	if err != nil {
-		return nil, err
-	}
-	if len(chunks) == 0 {
-		return nil, nil
-	}
-	var body strings.Builder
-	meta := map[string]string{}
-	for i, c := range chunks {
-		if i > 0 {
-			body.WriteString("\n\n")
-		}
-		body.WriteString(c.Content)
-		for k, v := range c.Metadata {
-			if strings.HasPrefix(k, "fm_") {
-				if sv, ok := v.(string); ok {
-					meta[strings.TrimPrefix(k, "fm_")] = sv
-				}
-			}
-		}
-	}
-	abstract, _ := s.Abstract(ctx, datasetID, name)
-	overview, _ := s.Overview(ctx, datasetID, name)
-	return &Document{Name: name, Content: body.String(), Abstract: abstract, Overview: overview, Metadata: meta}, nil
-}
-
-func (s *RetrievalStore) listChunksFor(ctx context.Context, datasetID, name string) ([]retrieval.Doc, error) {
-	tok := ""
-	var out []retrieval.Doc
-	for {
-		page, err := s.idx.List(ctx, chunkNS(datasetID), retrieval.ListRequest{
-			Filter:    retrieval.Filter{Eq: map[string]any{"doc_name": name}},
-			PageSize:  500,
-			PageToken: tok,
-		})
-		if err != nil {
-			return nil, err
-		}
-		out = append(out, page.Items...)
-		if page.NextPageToken == "" {
-			break
-		}
-		tok = page.NextPageToken
-	}
-	sort.SliceStable(out, func(i, j int) bool {
-		return chunkIdx(out[i]) < chunkIdx(out[j])
-	})
-	return out, nil
-}
-
-func chunkIdx(d retrieval.Doc) int {
-	if d.Metadata == nil {
-		return 0
-	}
-	if v, ok := d.Metadata["chunk_index"]; ok {
-		switch t := v.(type) {
-		case int:
-			return t
-		case int64:
-			return int(t)
-		case float64:
-			return int(t)
-		}
-	}
-	return 0
-}
-
-func (s *RetrievalStore) DeleteDocument(ctx context.Context, datasetID, name string) error {
-	chunks, err := s.listChunksFor(ctx, datasetID, name)
-	if err != nil {
-		return err
-	}
-	if len(chunks) > 0 {
-		ids := make([]string, 0, len(chunks))
-		for _, c := range chunks {
-			ids = append(ids, c.ID)
-		}
-		if err := s.idx.Delete(ctx, chunkNS(datasetID), ids); err != nil {
-			return err
-		}
-	}
-	return s.idx.Delete(ctx, docMetaNS(datasetID), []string{
-		"doc:" + name, string(LayerAbstract) + ":" + name, string(LayerOverview) + ":" + name,
-	})
-}
-
-func (s *RetrievalStore) ListDocuments(ctx context.Context, datasetID string) ([]Document, error) {
-	tok := ""
-	seen := map[string]struct{}{}
-	var docs []Document
-	for {
-		page, err := s.idx.List(ctx, docMetaNS(datasetID), retrieval.ListRequest{
-			PageSize:  500,
-			PageToken: tok,
-		})
-		if err != nil {
-			return nil, err
-		}
-		for _, d := range page.Items {
-			if !strings.HasPrefix(d.ID, "doc:") {
-				continue
-			}
-			name := strings.TrimPrefix(d.ID, "doc:")
-			if _, ok := seen[name]; ok {
-				continue
-			}
-			seen[name] = struct{}{}
-			docs = append(docs, Document{Name: name})
-		}
-		if page.NextPageToken == "" {
-			break
-		}
-		tok = page.NextPageToken
-	}
-	sort.Slice(docs, func(i, j int) bool { return docs[i].Name < docs[j].Name })
-	return docs, nil
-}
-
-func (s *RetrievalStore) Search(ctx context.Context, datasetID, query string, opts SearchOptions) ([]SearchResult, error) {
-	topK := opts.TopK
-	if topK <= 0 {
-		topK = 10
-	}
-	threshold := opts.Threshold
-	ns := chunkNS(datasetID)
-	if opts.MaxLayer != "" && opts.MaxLayer != LayerDetail {
-		ns = docMetaNS(datasetID)
-	}
-	resp, err := s.pipeline.Run(ctx, s.idx, ns, retrieval.SearchRequest{
-		QueryText: query,
-		TopK:      topK,
-	})
-	if err != nil {
-		return nil, err
-	}
-	out := make([]SearchResult, 0, len(resp.Hits))
-	for _, h := range resp.Hits {
-		if h.Score < threshold {
-			continue
-		}
-		layer := LayerDetail
-		if v, ok := h.Doc.Metadata["layer"].(string); ok {
-			layer = ContextLayer(v)
-		}
-		docName, _ := h.Doc.Metadata["doc_name"].(string)
-		out = append(out, SearchResult{
-			Content: h.Doc.Content, Score: h.Score, DocName: docName,
-			ChunkIndex: chunkIdx(h.Doc), Layer: layer, Metadata: h.Doc.Metadata,
-		})
-	}
-	return out, nil
-}
-
-func (s *RetrievalStore) getByID(ctx context.Context, ns, id string) (retrieval.Doc, bool, error) {
-	if g, ok := s.idx.(retrieval.DocGetter); ok {
-		return g.Get(ctx, ns, id)
-	}
-	tok := ""
-	for {
-		page, err := s.idx.List(ctx, ns, retrieval.ListRequest{PageSize: 500, PageToken: tok})
-		if err != nil {
-			return retrieval.Doc{}, false, err
-		}
-		for _, d := range page.Items {
-			if d.ID == id {
-				return d, true, nil
-			}
-		}
-		if page.NextPageToken == "" {
-			return retrieval.Doc{}, false, nil
-		}
-		tok = page.NextPageToken
-	}
-}
-
-func (s *RetrievalStore) Abstract(ctx context.Context, datasetID, name string) (string, error) {
-	d, ok, err := s.getByID(ctx, docMetaNS(datasetID), string(LayerAbstract)+":"+name)
-	if err != nil || !ok {
-		return "", err
-	}
-	return d.Content, nil
-}
-
-func (s *RetrievalStore) Overview(ctx context.Context, datasetID, name string) (string, error) {
-	d, ok, err := s.getByID(ctx, docMetaNS(datasetID), string(LayerOverview)+":"+name)
-	if err != nil || !ok {
-		return "", err
-	}
-	return d.Content, nil
-}
-
-func (s *RetrievalStore) DatasetAbstract(ctx context.Context, datasetID string) (string, error) {
-	d, ok, err := s.getByID(ctx, datasetMetaNS, "abstract:"+saneNS(datasetID))
-	if err != nil || !ok {
-		return "", err
-	}
-	return d.Content, nil
-}
-
-func (s *RetrievalStore) DatasetOverview(ctx context.Context, datasetID string) (string, error) {
-	d, ok, err := s.getByID(ctx, datasetMetaNS, "overview:"+saneNS(datasetID))
-	if err != nil || !ok {
-		return "", err
-	}
-	return d.Content, nil
-}
-
-func chunkID(datasetID, name string, idx int) string {
-	return fmt.Sprintf("%s/%s#%d", datasetID, name, idx)
-}
-
-// =============================================================================
-// CachedStore (Store TTL+LRU wrapper)
-// =============================================================================
-
-// CacheOption configures a CachedStore.
-//
-// Deprecated: see CachedStore.
-type CacheOption func(*CachedStore)
-
-// WithTTL sets the cache time-to-live.
-//
-// Deprecated: see CachedStore.
-func WithTTL(d time.Duration) CacheOption {
-	return func(s *CachedStore) { s.ttl = d }
-}
-
-// WithMaxItems sets the maximum number of cached items.
-//
-// Deprecated: see CachedStore.
-func WithMaxItems(n int) CacheOption {
-	return func(s *CachedStore) { s.maxItems = n }
-}
-
-type cacheEntry struct {
-	key     string
-	value   any
-	expiry  time.Time
-	element *list.Element
-}
-
-// CachedStore wraps a Store with TTL + LRU caching for read operations.
-//
-// Deprecated: caching now lives inside Service / repository implementations
-// where appropriate; the indirection no longer earns its keep at the
-// orchestration layer. Removed in v0.3.0.
-type CachedStore struct {
-	inner    Store
-	mu       sync.RWMutex
-	items    map[string]*cacheEntry
-	order    *list.List
-	ttl      time.Duration
-	maxItems int
-}
-
-// NewCachedStore wraps inner with caching.
-//
-// Deprecated: see CachedStore. Removed in v0.3.0.
-func NewCachedStore(inner Store, opts ...CacheOption) *CachedStore {
-	s := &CachedStore{
-		inner:    inner,
-		items:    make(map[string]*cacheEntry),
-		order:    list.New(),
-		ttl:      5 * time.Minute,
-		maxItems: 1000,
-	}
-	for _, opt := range opts {
-		opt(s)
-	}
-	return s
-}
-
-func (s *CachedStore) get(key string) (any, bool) {
-	s.mu.RLock()
-	entry, ok := s.items[key]
-	s.mu.RUnlock()
-	if !ok {
-		return nil, false
-	}
-	if time.Now().After(entry.expiry) {
-		s.mu.Lock()
-		s.removeLocked(key)
-		s.mu.Unlock()
-		return nil, false
-	}
-	s.mu.Lock()
-	s.order.MoveToFront(entry.element)
-	s.mu.Unlock()
-	return entry.value, true
-}
-
-func (s *CachedStore) set(key string, value any) {
-	s.mu.Lock()
-	defer s.mu.Unlock()
-	if entry, ok := s.items[key]; ok {
-		entry.value = value
-		entry.expiry = time.Now().Add(s.ttl)
-		s.order.MoveToFront(entry.element)
-		return
-	}
-	for len(s.items) >= s.maxItems {
-		back := s.order.Back()
-		if back == nil {
-			break
-		}
-		s.removeLocked(back.Value.(string))
-	}
-	el := s.order.PushFront(key)
-	s.items[key] = &cacheEntry{
-		key: key, value: value, expiry: time.Now().Add(s.ttl), element: el,
-	}
-}
-
-func (s *CachedStore) removeLocked(key string) {
-	entry, ok := s.items[key]
-	if !ok {
-		return
-	}
-	s.order.Remove(entry.element)
-	delete(s.items, key)
-}
-
-func (s *CachedStore) evictDataset(datasetID string) {
-	prefix := "doc:" + datasetID + "/"
-	searchPrefix := "search:" + datasetID + "|"
-	absPrefix := "abs:" + datasetID + "/"
-	ovPrefix := "ov:" + datasetID + "/"
-	dsAbs := "dsabs:" + datasetID
-	dsOv := "dsov:" + datasetID
-	s.mu.Lock()
-	defer s.mu.Unlock()
-	for key := range s.items {
-		if hasAnyPrefix(key, prefix, searchPrefix, absPrefix, ovPrefix) || key == dsAbs || key == dsOv {
-			s.removeLocked(key)
-		}
-	}
-}
-
-func hasAnyPrefix(s string, prefixes ...string) bool {
-	for _, p := range prefixes {
-		if len(s) >= len(p) && s[:len(p)] == p {
-			return true
-		}
-	}
-	return false
-}
-
-func (s *CachedStore) AddDocument(ctx context.Context, datasetID, name, content string) error {
-	if err := s.inner.AddDocument(ctx, datasetID, name, content); err != nil {
-		return err
-	}
-	s.evictDataset(datasetID)
-	return nil
-}
-
-func (s *CachedStore) AddDocuments(ctx context.Context, datasetID string, docs []DocInput) error {
-	if err := s.inner.AddDocuments(ctx, datasetID, docs); err != nil {
-		return err
-	}
-	s.evictDataset(datasetID)
-	return nil
-}
-
-func (s *CachedStore) GetDocument(ctx context.Context, datasetID, name string) (*Document, error) {
-	key := fmt.Sprintf("doc:%s/%s", datasetID, name)
-	if v, ok := s.get(key); ok {
-		doc, ok := v.(Document)
-		if !ok {
-			s.mu.Lock()
-			s.removeLocked(key)
-			s.mu.Unlock()
-			return s.inner.GetDocument(ctx, datasetID, name)
-		}
-		return &doc, nil
-	}
-	doc, err := s.inner.GetDocument(ctx, datasetID, name)
-	if err != nil {
-		return nil, err
-	}
-	s.set(key, *doc)
-	return doc, nil
-}
-
-func (s *CachedStore) DeleteDocument(ctx context.Context, datasetID, name string) error {
-	if err := s.inner.DeleteDocument(ctx, datasetID, name); err != nil {
-		return err
-	}
-	s.evictDataset(datasetID)
-	return nil
-}
-
-func (s *CachedStore) ListDocuments(ctx context.Context, datasetID string) ([]Document, error) {
-	return s.inner.ListDocuments(ctx, datasetID)
-}
-
-func (s *CachedStore) Search(ctx context.Context, datasetID, query string, opts SearchOptions) ([]SearchResult, error) {
-	key := fmt.Sprintf("search:%s|%s|%d|%s|%f|%s", datasetID, query, opts.TopK, opts.MaxLayer, opts.Threshold, opts.Mode)
-	if v, ok := s.get(key); ok {
-		results, ok := v.([]SearchResult)
-		if !ok {
-			s.mu.Lock()
-			s.removeLocked(key)
-			s.mu.Unlock()
-			return s.inner.Search(ctx, datasetID, query, opts)
-		}
-		cp := make([]SearchResult, len(results))
-		copy(cp, results)
-		return cp, nil
-	}
-	results, err := s.inner.Search(ctx, datasetID, query, opts)
-	if err != nil {
-		return nil, err
-	}
-	s.set(key, results)
-	return results, nil
-}
-
-func (s *CachedStore) Abstract(ctx context.Context, datasetID, name string) (string, error) {
-	key := fmt.Sprintf("abs:%s/%s", datasetID, name)
-	if v, ok := s.get(key); ok {
-		val, ok := v.(string)
-		if !ok {
-			s.mu.Lock()
-			s.removeLocked(key)
-			s.mu.Unlock()
-			return s.inner.Abstract(ctx, datasetID, name)
-		}
-		return val, nil
-	}
-	val, err := s.inner.Abstract(ctx, datasetID, name)
-	if err != nil {
-		return "", err
-	}
-	s.set(key, val)
-	return val, nil
-}
-
-func (s *CachedStore) Overview(ctx context.Context, datasetID, name string) (string, error) {
-	key := fmt.Sprintf("ov:%s/%s", datasetID, name)
-	if v, ok := s.get(key); ok {
-		val, ok := v.(string)
-		if !ok {
-			s.mu.Lock()
-			s.removeLocked(key)
-			s.mu.Unlock()
-			return s.inner.Overview(ctx, datasetID, name)
-		}
-		return val, nil
-	}
-	val, err := s.inner.Overview(ctx, datasetID, name)
-	if err != nil {
-		return "", err
-	}
-	s.set(key, val)
-	return val, nil
-}
-
-func (s *CachedStore) DatasetAbstract(ctx context.Context, datasetID string) (string, error) {
-	key := "dsabs:" + datasetID
-	if v, ok := s.get(key); ok {
-		val, ok := v.(string)
-		if !ok {
-			s.mu.Lock()
-			s.removeLocked(key)
-			s.mu.Unlock()
-			return s.inner.DatasetAbstract(ctx, datasetID)
-		}
-		return val, nil
-	}
-	val, err := s.inner.DatasetAbstract(ctx, datasetID)
-	if err != nil {
-		return "", err
-	}
-	s.set(key, val)
-	return val, nil
-}
-
-func (s *CachedStore) DatasetOverview(ctx context.Context, datasetID string) (string, error) {
-	key := "dsov:" + datasetID
-	if v, ok := s.get(key); ok {
-		val, ok := v.(string)
-		if !ok {
-			s.mu.Lock()
-			s.removeLocked(key)
-			s.mu.Unlock()
-			return s.inner.DatasetOverview(ctx, datasetID)
-		}
-		return val, nil
-	}
-	val, err := s.inner.DatasetOverview(ctx, datasetID)
-	if err != nil {
-		return "", err
-	}
-	s.set(key, val)
-	return val, nil
-}
-
-// EvictDataset removes all cached entries for a dataset.
-func (s *CachedStore) EvictDataset(datasetID string) {
-	s.evictDataset(datasetID)
-}
-
-// =============================================================================
-// Legacy Reloader / ChangeNotifier
-// =============================================================================
-
-// ChangeNotifier emits an opaque event whenever the underlying source changes.
-//
-// Deprecated: use EventNotifier (typed ChangeEvent stream) with
-// EventReloader. Removed in v0.3.0.
-type ChangeNotifier interface {
-	Events() <-chan struct{}
-	Close() error
-}
-
-// Reloader debounces ChangeNotifier events and triggers Rebuild on a
-// stable trailing edge.
-//
-// Deprecated: use EventReloader (typed events + scope-aware Service.Rebuild
-// + serialised execution). Removed in v0.3.0.
-type Reloader struct {
-	notifier ChangeNotifier
-	rebuild  func(ctx context.Context) error
-	debounce time.Duration
-
-	mu      sync.Mutex
-	pending bool
-	wg      sync.WaitGroup
-	stop    chan struct{}
-}
-
-// NewReloader wires a ChangeNotifier to a rebuild callback.
-//
-// Deprecated: use NewEventReloader(target Rebuilder, notifier EventNotifier, opts).
-// Removed in v0.3.0.
-func NewReloader(store *FSStore, notifier ChangeNotifier, opts ReloaderOptions) *Reloader {
-	d := opts.Debounce
-	if d <= 0 {
-		d = 500 * time.Millisecond
-	}
-	rebuild := opts.Rebuild
-	if rebuild == nil && store != nil {
-		rebuild = store.BuildIndex
-	}
-	return &Reloader{
-		notifier: notifier,
-		rebuild:  rebuild,
-		debounce: d,
-		stop:     make(chan struct{}),
-	}
-}
-
-// Run blocks until Close is called or ctx is cancelled.
-func (r *Reloader) Run(ctx context.Context) error {
-	if r.notifier == nil || r.rebuild == nil {
-		return nil
-	}
-	var timer *time.Timer
-	r.wg.Add(1)
-	defer r.wg.Done()
-	for {
-		select {
-		case <-ctx.Done():
-			if timer != nil {
-				timer.Stop()
-			}
-			return ctx.Err()
-		case <-r.stop:
-			if timer != nil {
-				timer.Stop()
-			}
-			return nil
-		case _, ok := <-r.notifier.Events():
-			if !ok {
-				return nil
-			}
-			r.mu.Lock()
-			if !r.pending {
-				r.pending = true
-				if timer != nil {
-					timer.Stop()
-				}
-				timer = time.AfterFunc(r.debounce, func() {
-					r.mu.Lock()
-					r.pending = false
-					r.mu.Unlock()
-					rebuildCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
-					defer cancel()
-					_ = r.rebuild(rebuildCtx)
-				})
-			}
-			r.mu.Unlock()
-		}
-	}
-}
-
-// Close stops Run and the underlying ChangeNotifier.
-func (r *Reloader) Close() error {
-	close(r.stop)
-	r.wg.Wait()
-	if r.notifier != nil {
-		return r.notifier.Close()
-	}
-	return nil
-}
-
-// =============================================================================
-// Legacy graph node (KnowledgeNode + KnowledgeConfig + KnowledgeNodeSchema)
-// =============================================================================
-//
-// Removed in this branch. All "knowledge" graph node implementations now
-// live in github.com/GizClaw/flowcraft/sdk/graph/node/knowledgenode:
-//
-//	knowledge.KnowledgeServiceNode    -> knowledgenode.Node
-//	knowledge.KnowledgeNodeConfig     -> knowledgenode.Config
-//	knowledge.KnowledgeNodeConfigFromMap -> knowledgenode.ConfigFromMap
-//	knowledge.RegisterServiceNode     -> knowledgenode.Register(*node.Factory, *Service)
-//	knowledge.KnowledgeServiceNodeSchema -> (deleted; UI metadata is no longer SDK-owned)
-//	knowledge.NewKnowledgeNode        -> knowledgenode.New(svc, knowledgenode.Config{...})
-//	knowledge.KnowledgeConfigFromMap  -> knowledgenode.ConfigFromMap
-//	knowledge.RegisterNode            -> knowledgenode.Register
-//	knowledge.KnowledgeNodeSchema     -> (deleted)
-
-// =============================================================================
-// Legacy LLM tools
-// =============================================================================
-
-// NewSearchTool returns the legacy "knowledge_search" LLM tool.
-//
-// Deprecated: use NewSearchServiceTool(*Service). Removed in v0.3.0.
-func NewSearchTool(ks Store) tool.Tool {
-	return tool.FuncTool(
-		tool.DefineSchema("knowledge_search",
-			"Search the knowledge base using keyword matching. "+
-				"Use specific, concrete keywords (e.g. node type names, error messages) "+
-				"rather than abstract queries for best results. "+
-				"Automatically searches across all datasets and returns ranked results.",
-			tool.Property("query", "string", "Search query"),
-			tool.Property("top_k", "integer", "Number of results to return (default 5)"),
-		).Required("query").Build(),
-		func(ctx context.Context, args string) (string, error) {
-			if ks == nil {
-				return "", errdefs.NotAvailablef("knowledge store not available")
-			}
-			var p struct {
-				Query string `json:"query"`
-				TopK  int    `json:"top_k"`
-			}
-			if err := json.Unmarshal([]byte(args), &p); err != nil {
-				return "", err
-			}
-			if p.TopK <= 0 {
-				p.TopK = 5
-			}
-			results, err := ks.Search(ctx, "", p.Query, SearchOptions{TopK: p.TopK})
-			if err != nil {
-				return "", err
-			}
-			data, err := json.Marshal(results)
-			if err != nil {
-				return "", err
-			}
-			return string(data), nil
-		},
-	)
-}
-
-// NewAddTool returns the legacy "knowledge_add" LLM tool.
-//
-// Deprecated: use NewPutServiceTool(*Service). Removed in v0.3.0.
-func NewAddTool(ks Store) tool.Tool {
-	return tool.FuncTool(
-		tool.DefineSchema("knowledge_add",
-			"Add a document to the knowledge base. "+
-				"Use this to persist reusable knowledge such as troubleshooting conclusions, "+
-				"best practices, or design decisions that may benefit future conversations. "+
-				"Do NOT use this for personal preferences or temporary notes.",
-			tool.Property("dataset_id", "string", "Target dataset ID (default: \"default\")"),
-			tool.Property("name", "string", "Document name (include .md suffix)"),
-			tool.Property("content", "string", "Document content in markdown"),
-		).Required("name", "content").Build(),
-		func(ctx context.Context, args string) (string, error) {
-			if ks == nil {
-				return "", errdefs.NotAvailablef("knowledge store not available")
-			}
-			var p struct {
-				DatasetID string `json:"dataset_id"`
-				Name      string `json:"name"`
-				Content   string `json:"content"`
-			}
-			if err := json.Unmarshal([]byte(args), &p); err != nil {
-				return "", err
-			}
-			if p.DatasetID == "" {
-				p.DatasetID = defaultDatasetID
-			}
-			if err := ks.AddDocument(ctx, p.DatasetID, p.Name, p.Content); err != nil {
-				return "", err
-			}
-			resp, _ := json.Marshal(map[string]string{
-				"status":     "ok",
-				"dataset_id": p.DatasetID,
-				"name":       p.Name,
-			})
-			return string(resp), nil
-		},
-	)
-}
-
-// Compile-time assertions that the legacy types still implement Store.
-var (
-	_ Store = (*FSStore)(nil)
-	_ Store = (*RetrievalStore)(nil)
-	_ Store = (*CachedStore)(nil)
-)
diff --git a/sdk/knowledge/model.go b/sdk/knowledge/model.go
--- a/sdk/knowledge/model.go
+++ b/sdk/knowledge/model.go
@@ -2,10 +2,11 @@ package knowledge
 
 import "time"
 
-// Layer is the v0.3.0 name for ContextLayer. It is declared as a type
-// alias so values flow seamlessly between old and new APIs during the
-// deprecation window. The constant set lives in types.go.
-type Layer = ContextLayer
+// ContextLayer is the pre-v0.3.0 name for [Layer]. Retained as a type
+// alias so external code that referenced knowledge.ContextLayer keeps
+// compiling. The constant set (LayerAbstract / LayerOverview /
+// LayerDetail) lives in types.go.
+type ContextLayer = Layer
 
 // IsValidLayer reports whether l is a recognised layer.
 //
diff --git a/sdk/knowledge/query.go b/sdk/knowledge/query.go
--- a/sdk/knowledge/query.go
+++ b/sdk/knowledge/query.go
@@ -10,9 +10,9 @@ const (
 	ScopeAllDatasets
 )
 
-// Mode is the v0.3.0 name for SearchMode. It is declared as a type alias
-// so values flow seamlessly between old and new APIs during the
-// deprecation window. The constant set lives in types.go.
+// Mode is an alias for SearchMode, kept so newer call-sites can read
+// "knowledge.Mode" without the redundant Search prefix while older
+// "knowledge.SearchMode" call sites keep working unchanged.
 type Mode = SearchMode
 
 // IsValidMode reports whether m is a recognised mode.
@@ -21,24 +21,20 @@ type Mode = SearchMode
 // callers used "" to mean BM25); ResolveMode normalises it to ModeBM25.
 func IsValidMode(m Mode) bool {
 	switch m {
-	case ModeBM25, ModeVector, ModeSemantic, ModeHybrid, "":
+	case ModeBM25, ModeVector, ModeHybrid, "":
 		return true
 	}
 	return false
 }
 
-// ResolveMode normalises legacy and zero values to a canonical Mode.
+// ResolveMode normalises zero values to a canonical Mode.
 //
 //   - ""           -> ModeBM25 (legacy default)
-//   - ModeSemantic -> ModeVector (Deprecated alias, removed in v0.3.0)
 //
 // Any other recognised mode is returned unchanged.
 func ResolveMode(m Mode) Mode {
-	switch m {
-	case "":
+	if m == "" {
 		return ModeBM25
-	case ModeSemantic:
-		return ModeVector
 	}
 	return m
 }
diff --git a/sdk/knowledge/rebuilder.go b/sdk/knowledge/rebuilder.go
--- a/sdk/knowledge/rebuilder.go
+++ b/sdk/knowledge/rebuilder.go
@@ -18,12 +18,6 @@ const (
 
 // ChangeEvent carries enough granularity for targeted rebuilds.
 // DocName == "" denotes a dataset-level event.
-//
-// NOTE (v0.2.x): The deprecated ChangeNotifier in deprecated.go still
-// emits opaque struct{} events; sdkx/knowledge/watcher remains its only
-// in-tree producer. The ChangeEvent shape declared here is what
-// EventNotifier implementations will emit once watcher migrates in
-// v0.3.0.
 type ChangeEvent struct {
 	DatasetID string
 	DocName   string
diff --git a/sdk/knowledge/reloader.go b/sdk/knowledge/reloader.go
--- a/sdk/knowledge/reloader.go
+++ b/sdk/knowledge/reloader.go
@@ -8,32 +8,25 @@ import (
 	"github.com/GizClaw/flowcraft/sdk/errdefs"
 )
 
-// EventNotifier is the v0.3.0 producer side of the reload pipeline. It
-// supersedes the deprecated ChangeNotifier (defined in deprecated.go):
-// events carry dataset/doc granularity so the consumer can issue
-// targeted Rebuilds instead of a global one.
+// EventNotifier is the producer side of the reload pipeline. Events
+// carry dataset/doc granularity so the consumer can issue targeted
+// Rebuilds instead of a global one.
 //
-// Implementations live in adapter packages (e.g. sdkx/knowledge/watcher,
-// once it migrates) so the sdk core stays dependency-free.
-// Implementations MUST close the Events channel when Close() is called.
+// Implementations live in adapter packages so the sdk core stays
+// dependency-free. Implementations MUST close the Events channel when
+// Close() is called.
 type EventNotifier interface {
 	Events() <-chan ChangeEvent
 	Close() error
 }
 
-// ReloaderOptions configures EventReloader (and the deprecated Reloader).
+// ReloaderOptions configures EventReloader.
 //
-// Field set is the union of both consumers:
-//   - Debounce       controls the trailing-edge window (both consumers).
-//   - RebuildTimeout caps each rebuild call (EventReloader only; the
-//     legacy Reloader hard-codes 30s).
-//   - Rebuild        is the legacy hook used by the deprecated Reloader to
-//     swap the rebuild callback. EventReloader ignores it and always
-//     calls Rebuilder.Rebuild on the supplied target.
+//   - Debounce       controls the trailing-edge window.
+//   - RebuildTimeout caps each rebuild call.
 type ReloaderOptions struct {
 	Debounce       time.Duration
 	RebuildTimeout time.Duration
-	Rebuild        func(context.Context) error
 }
 
 // EventReloader debounces ChangeEvents and triggers Rebuild on the
@@ -45,11 +38,6 @@ type ReloaderOptions struct {
 // that pair; when it touches multiple datasets or any EventBulk event,
 // a dataset-wide rebuild is issued instead. Mixed datasets in one
 // window collapse to a global RebuildScope{} (every dataset).
-//
-// EventReloader is the v0.3.0 successor to Reloader. The legacy
-// Reloader (with its struct{}-channel ChangeNotifier, both in
-// deprecated.go) remains exported during the deprecation window and
-// will be removed in v0.3.0.
 type EventReloader struct {
 	target   Rebuilder
 	notifier EventNotifier
diff --git a/sdk/knowledge/service.go b/sdk/knowledge/service.go
--- a/sdk/knowledge/service.go
+++ b/sdk/knowledge/service.go
@@ -9,9 +9,9 @@ import (
 )
 
 // Service orchestrates document lifecycle, derived-data persistence and
-// search. All public Knowledge entry points (graph node, tools,
-// deprecated stores) route through Service so contract guarantees
-// (#1..#7 in doc.go) live in one place.
+// search. All public Knowledge entry points (graph node, tool
+// adapters) route through Service so contract guarantees live in one
+// place.
 type Service struct {
 	docs   DocumentRepo
 	chunks ChunkRepo
@@ -234,8 +234,7 @@ func (s *Service) DatasetLayer(ctx context.Context, datasetID string, layer Laye
 //
 // Validation (the only place these checks live, contract #2):
 //   - q.Layer defaults to LayerDetail when zero; rejected otherwise.
-//   - q.Mode  defaults to ModeBM25 when zero; ModeSemantic is normalised
-//     to ModeVector for backwards compatibility.
+//   - q.Mode  defaults to ModeBM25 when zero; rejected otherwise.
 //   - q.Scope=ScopeSingleDataset requires q.DatasetID to be non-empty.
 //
 // For ScopeAllDatasets the dataset list is resolved once via
diff --git a/sdk/knowledge/tool.go b/sdk/knowledge/tool.go
deleted file mode 100644
--- a/sdk/knowledge/tool.go
+++ /dev/null
@@ -1,172 +0,0 @@
-package knowledge
-
-import (
-	"context"
-	"encoding/json"
-
-	"github.com/GizClaw/flowcraft/sdk/errdefs"
-	"github.com/GizClaw/flowcraft/sdk/tool"
-)
-
-// defaultDatasetID is the implicit dataset for tools that omit dataset_id.
-const defaultDatasetID = "default"
-
-// NewSearchServiceTool exposes Service.Search to LLMs (v0.3.0).
-//
-// Tool name:  "knowledge_search"
-// Input JSON:
-//
-//	{
-//	  "query":      string,                       // required
-//	  "scope":      "single"|"all",               // default "all"
-//	  "dataset_id": string,                       // required when scope=single
-//	  "mode":       "bm25"|"vector"|"hybrid",     // default "bm25"
-//	  "layer":      "L0"|"L1"|"L2",               // default "L2"
-//	  "top_k":      integer,                      // default 5
-//	  "threshold":  number                        // default 0
-//	}
-//
-// Output: JSON-encoded []Hit.
-//
-// Backwards compatibility: when callers send only the legacy
-// {query, top_k} fields, the tool defaults to scope=all/mode=bm25/layer=L2
-// — the same behaviour as the deprecated NewSearchTool(Store) helper.
-//
-// Deprecated: this LLM tool implementation will be moved to
-// sdkx/tool/knowledge in v0.3.0. The new home matches the existing
-// "sdk = interface, sdkx = concrete adapter" layering rule that
-// sdk/llm and sdk/embedding already follow. The function signature is
-// unchanged across the move; only the import path differs. New code
-// SHOULD pin sdkx/tool/knowledge directly. See docs/migrations/v0.3.0.md.
-func NewSearchServiceTool(svc *Service) tool.Tool {
-	return tool.FuncTool(
-		tool.DefineSchema("knowledge_search",
-			"Search the knowledge base. Supports BM25 / vector / hybrid modes "+
-				"and three layers (L0 abstract, L1 overview, L2 detail). "+
-				"Use specific keywords for best results.",
-			tool.Property("query", "string", "Search query"),
-			tool.Property("scope", "string", `"single" or "all" (default "all")`),
-			tool.Property("dataset_id", "string", "Required when scope=single"),
-			tool.Property("mode", "string", `"bm25" | "vector" | "hybrid" (default "bm25")`),
-			tool.Property("layer", "string", `"L0" | "L1" | "L2" (default "L2")`),
-			tool.Property("top_k", "integer", "Number of results (default 5)"),
-			tool.Property("threshold", "number", "Minimum fused score (default 0)"),
-		).Required("query").Build(),
-		func(ctx context.Context, args string) (string, error) {
-			if svc == nil {
-				return "", errdefs.NotAvailablef("knowledge service not available")
-			}
-			var p struct {
-				Query     string  `json:"query"`
-				Scope     string  `json:"scope"`
-				DatasetID string  `json:"dataset_id"`
-				Mode      string  `json:"mode"`
-				Layer     string  `json:"layer"`
-				TopK      int     `json:"top_k"`
-				Threshold float64 `json:"threshold"`
-			}
-			if err := json.Unmarshal([]byte(args), &p); err != nil {
-				return "", err
-			}
-			q := Query{
-				Text:      p.Query,
-				DatasetID: p.DatasetID,
-				Mode:      Mode(p.Mode),
-				Layer:     Layer(p.Layer),
-				TopK:      p.TopK,
-				Threshold: p.Threshold,
-			}
-			switch p.Scope {
-			case "single":
-				q.Scope = ScopeSingleDataset
-			case "all", "":
-				q.Scope = ScopeAllDatasets
-			default:
-				return "", errdefs.Validationf("knowledge: invalid scope %q", p.Scope)
-			}
-			res, err := svc.Search(ctx, q)
-			if err != nil {
-				return "", err
-			}
-			hits := []Hit{}
-			if res != nil {
-				hits = res.Hits
-			}
-			data, err := json.Marshal(hits)
-			if err != nil {
-				return "", err
-			}
-			return string(data), nil
-		},
-	)
-}
-
-// NewPutServiceTool exposes Service.PutDocument to LLMs (v0.3.0).
-//
-// Tool name:  "knowledge_put"
-// Input JSON:
-//
-//	{
-//	  "dataset_id": string,   // default "default"
-//	  "name":       string,   // required
-//	  "content":    string    // required
-//	}
-//
-// Output:
-//
-//	{"status": "ok", "dataset_id": ..., "name": ..., "version": uint}
-//
-// The tool returns the new SourceDocument.Version so callers can chain
-// derivation work (layer generation, vector backfill) keyed off the
-// freshness signal.
-//
-// Deprecated: this LLM tool implementation will be moved to
-// sdkx/tool/knowledge in v0.3.0 alongside [NewSearchServiceTool]. The
-// function signature is preserved across the move; only the import
-// path changes. See docs/migrations/v0.3.0.md.
-func NewPutServiceTool(svc *Service) tool.Tool {
-	return tool.FuncTool(
-		tool.DefineSchema("knowledge_put",
-			"Persist a document into the knowledge base. Use this for "+
-				"durable knowledge (troubleshooting conclusions, design notes); "+
-				"avoid temporary scratchpads.",
-			tool.Property("dataset_id", "string", `Target dataset (default "default")`),
-			tool.Property("name", "string", "Document name (include extension, e.g. .md)"),
-			tool.Property("content", "string", "Document body"),
-		).Required("name", "content").Build(),
-		func(ctx context.Context, args string) (string, error) {
-			if svc == nil {
-				return "", errdefs.NotAvailablef("knowledge service not available")
-			}
-			var p struct {
-				DatasetID string `json:"dataset_id"`
-				Name      string `json:"name"`
-				Content   string `json:"content"`
-			}
-			if err := json.Unmarshal([]byte(args), &p); err != nil {
-				return "", err
-			}
-			if p.DatasetID == "" {
-				p.DatasetID = defaultDatasetID
-			}
-			if err := svc.PutDocument(ctx, p.DatasetID, p.Name, p.Content); err != nil {
-				return "", err
-			}
-			doc, err := svc.GetDocument(ctx, p.DatasetID, p.Name)
-			if err != nil {
-				return "", err
-			}
-			version := uint64(0)
-			if doc != nil {
-				version = doc.Version
-			}
-			resp, _ := json.Marshal(map[string]any{
-				"status":     "ok",
-				"dataset_id": p.DatasetID,
-				"name":       p.Name,
-				"version":    version,
-			})
-			return string(resp), nil
-		},
-	)
-}
diff --git a/sdk/knowledge/types.go b/sdk/knowledge/types.go
--- a/sdk/knowledge/types.go
+++ b/sdk/knowledge/types.go
@@ -1,7 +1,6 @@
-// Package knowledge implements the v0.3.0 layered knowledge base:
-// document storage, chunking, tokenization, and BM25 / vector / hybrid
-// retrieval over three context layers (L0 abstract, L1 overview,
-// L2 chunk detail).
+// Package knowledge implements the layered knowledge base: document
+// storage, chunking, tokenization, and BM25 / vector / hybrid retrieval
+// over three context layers (L0 abstract, L1 overview, L2 chunk detail).
 //
 // Architecture
 //
@@ -19,41 +18,28 @@
 // L0/L1 derivation (GenerateDocumentContext / GenerateDatasetContext) is
 // kept external to Service so callers own scheduling, retry and
 // persistence policy.
-//
-// Migration: every v0.2.x symbol survives in deprecated.go (tagged
-// // Deprecated:) until v0.3.0; consult deprecated.go for the full
-// new-name index.
 package knowledge
 
-// ContextLayer indicates the granularity of a search result.
+// Layer indicates the granularity of a search result.
 //
-// v0.3.0 will rename ContextLayer -> Layer; the alias declared in
-// model.go (type Layer = ContextLayer) lets new code adopt the final name
-// today without breaking existing callers.
-type ContextLayer string
+// The pre-v0.3.0 name was ContextLayer; that name remains exported as a
+// type alias in model.go so callers using either spelling keep compiling.
+type Layer string
 
 const (
-	LayerAbstract ContextLayer = "L0" // ~100 token one-sentence summary
-	LayerOverview ContextLayer = "L1" // ~1k token structured overview
-	LayerDetail   ContextLayer = "L2" // full chunk content
+	LayerAbstract Layer = "L0" // ~100 token one-sentence summary
+	LayerOverview Layer = "L1" // ~1k token structured overview
+	LayerDetail   Layer = "L2" // full chunk content
 )
 
-// SearchMode chooses the retrieval algorithm.
-//
-// v0.3.0 final values are explicit strings; legacy callers that pass the
-// empty string are normalised to ModeBM25 by ResolveMode().
-//
-// Deprecated names:
-//   - ModeSemantic remains for backwards compatibility; new code should
-//     use ModeVector. They are recognised as equivalent at the Service
-//     boundary starting in v0.2.x and ModeSemantic is removed in v0.3.0.
+// SearchMode chooses the retrieval algorithm. Legacy callers that pass
+// the empty string are normalised to ModeBM25 by ResolveMode().
 type SearchMode string
 
 const (
-	ModeBM25     SearchMode = "bm25"
-	ModeVector   SearchMode = "vector"
-	ModeSemantic SearchMode = "semantic" // Deprecated: use ModeVector.
-	ModeHybrid   SearchMode = "hybrid"
+	ModeBM25   SearchMode = "bm25"
+	ModeVector SearchMode = "vector"
+	ModeHybrid SearchMode = "hybrid"
 )
 
 // ChunkConfig controls document chunking.
diff --git a/sdk/llm/deprecated.go b/sdk/llm/deprecated.go
deleted file mode 100644
--- a/sdk/llm/deprecated.go
+++ /dev/null
@@ -1,474 +0,0 @@
-package llm
-
-// This file groups symbols that are scheduled for removal in v0.3.0,
-// once the agent + engine runtime supersedes the workflow-based
-// execution path. New code MUST NOT rely on anything declared here.
-// The canonical migration target is documented per symbol; until then
-// the helpers stay buildable so existing callers (graph/node,
-// script/bindings, …) keep compiling.
-
-import (
-	"context"
-	"encoding/json"
-	"fmt"
-	"maps"
-	"reflect"
-	"strconv"
-	"strings"
-
-	"github.com/GizClaw/flowcraft/sdk/model"
-	"github.com/GizClaw/flowcraft/sdk/telemetry"
-	"github.com/GizClaw/flowcraft/sdk/tool"
-	"github.com/GizClaw/flowcraft/sdk/workflow"
-
-	"go.opentelemetry.io/otel/attribute"
-	"go.opentelemetry.io/otel/trace"
-)
-
-// ============================================================================
-// Spec-redesign aliases (added 2026-04-30, scheduled for removal in v0.3.0).
-//
-// These symbols are kept as thin shims so that callers using the old
-// caps-only / extra-caps / model-caps API surface keep compiling
-// during the migration window. Internal sdk/llm code MUST use the
-// new names directly (WithCaps / WithPolicyCaps / LookupModelSpec).
-// See doc/sdk-llm-redesign.md §7 "Deprecation housekeeping" for the
-// placement convention.
-// ============================================================================
-
-// CapsMiddleware wraps an LLM with the caps filter.
-//
-// Deprecated: use [WithCaps] directly. Scheduled for removal in v0.3.0;
-// kept only so existing call sites compile during the migration.
-func CapsMiddleware(inner LLM, caps ModelCaps) LLM {
-	return WithCaps(inner, caps)
-}
-
-// WithExtraCaps merges resolver-wide caps into every produced LLM.
-//
-// Deprecated: renamed to [WithPolicyCaps] to make the resolver-wide
-// policy intent explicit (vs per-model caps). Scheduled for removal
-// in v0.3.0.
-func WithExtraCaps(caps ModelCaps) ResolverOption {
-	return WithPolicyCaps(caps)
-}
-
-// LookupModelCaps returns the catalog ModelCaps for a registered
-// model.
-//
-// Deprecated: use (*ProviderRegistry).LookupModelSpec(provider,
-// model).Caps. Scheduled for removal in v0.3.0.
-func (r *ProviderRegistry) LookupModelCaps(provider, model string) ModelCaps {
-	return r.LookupModelSpec(provider, model).Caps
-}
-
-// ============================================================================
-// Workflow-era round helpers (RunRound / RoundConfig family). Scheduled
-// for removal in v0.3.0 alongside the rest of the workflow package
-// surface, once the agent + engine runtime owns per-call streaming
-// and tool execution end-to-end.
-// ============================================================================
-
-// RoundResult is the structured output of one LLM round.
-//
-// Deprecated: RoundResult is part of the workflow-based round helper
-// surface and is scheduled for removal in v0.3.0, once the
-// agent + engine runtime owns per-call streaming and tool execution.
-// Prefer building rounds on top of [LLM.GenerateStream] directly
-// until the replacement lands.
-type RoundResult struct {
-	Content     string
-	Message     Message
-	Messages    []Message
-	ToolCalls   []model.ToolCall
-	ToolResults []model.ToolResult
-	ToolPending bool
-	Usage       TokenUsage
-}
-
-// RunRound executes one LLM round: resolve model → stream generation → tool
-// follow-up → return result. It is a pure function: callers supply messages
-// explicitly and handle board I/O themselves.
-//
-// stream may be nil; when non-nil, token / tool_call / tool_result events are
-// emitted as they arrive (eventID labels the source in each event).
-//
-// Deprecated: RunRound mixes resolver, streaming, and tool follow-up
-// in one helper and depends on workflow.StreamCallback. It is
-// scheduled for removal in v0.3.0; the agent + engine layering will
-// replace it. New code should drive LLM rounds directly via
-// [LLM.GenerateStream] and surface events through the engine host.
-func RunRound(
-	ctx context.Context,
-	stream workflow.StreamCallback,
-	resolver LLMResolver,
-	reg *tool.Registry,
-	eventID string,
-	messages []Message,
-	cfg RoundConfig,
-) (*RoundResult, error) {
-	ctx, span := telemetry.Tracer().Start(ctx, "llm.round",
-		trace.WithAttributes(attribute.String("event.id", eventID)))
-	defer span.End()
-
-	s, err := StreamRound(ctx, stream, resolver, reg, eventID, messages, cfg)
-	if err != nil {
-		span.RecordError(err)
-		return nil, err
-	}
-	defer s.Close()
-
-	for s.Next() {
-	}
-	result, err := s.Finish()
-	if err != nil {
-		span.RecordError(err)
-		return nil, err
-	}
-
-	span.SetAttributes(
-		attribute.Int64("llm.input_tokens", result.Usage.InputTokens),
-		attribute.Int64("llm.output_tokens", result.Usage.OutputTokens),
-		attribute.Bool("llm.tool_pending", result.ToolPending),
-		attribute.Int("llm.tool_calls", len(result.ToolCalls)),
-	)
-	return result, nil
-}
-
-// RoundStream is a token-by-token iterator over an in-progress LLM round.
-// Callers loop with Next() / Token(), then call Finish() for the complete result.
-//
-// Deprecated: RoundStream is the iterator counterpart of [RunRound]
-// and is scheduled for removal in v0.3.0 alongside it. Use
-// [LLM.GenerateStream] directly.
-type RoundStream struct {
-	ctx     context.Context
-	inner   StreamMessage
-	reg     *tool.Registry
-	stream  workflow.StreamCallback
-	eventID string
-
-	messages []Message
-	current  string
-	acc      strings.Builder
-}
-
-// StreamRound starts an LLM round and returns a RoundStream for
-// token-by-token iteration. Call Finish() after Next() returns false.
-//
-// Deprecated: scheduled for removal in v0.3.0; see [RunRound].
-func StreamRound(
-	ctx context.Context,
-	stream workflow.StreamCallback,
-	resolver LLMResolver,
-	reg *tool.Registry,
-	eventID string,
-	messages []Message,
-	cfg RoundConfig,
-) (*RoundStream, error) {
-	l, err := resolver.Resolve(ctx, cfg.Model)
-	if err != nil {
-		return nil, fmt.Errorf("llm round %q: cannot resolve model %q: %w", eventID, cfg.Model, err)
-	}
-
-	opts := buildRoundGenerateOptions(cfg, reg)
-
-	inner, err := l.GenerateStream(ctx, messages, opts...)
-	if err != nil {
-		return nil, fmt.Errorf("llm round %q: generate failed: %w", eventID, err)
-	}
-
-	msgsCopy := make([]Message, len(messages))
-	copy(msgsCopy, messages)
-
-	return &RoundStream{
-		ctx:      ctx,
-		inner:    inner,
-		reg:      reg,
-		stream:   stream,
-		eventID:  eventID,
-		messages: msgsCopy,
-	}, nil
-}
-
-// Next advances to the next token chunk. Returns false when the stream is done.
-func (s *RoundStream) Next() bool {
-	if !s.inner.Next() {
-		return false
-	}
-	chunk := s.inner.Current()
-	s.current = chunk.Content
-	if s.current != "" {
-		s.acc.WriteString(s.current)
-		if s.stream != nil {
-			s.stream(workflow.StreamEvent{
-				Type:    "token",
-				NodeID:  s.eventID,
-				Payload: map[string]any{"content": s.current},
-			})
-		}
-	}
-	return true
-}
-
-// Token returns the content string of the current chunk.
-func (s *RoundStream) Token() string { return s.current }
-
-// Close releases the underlying stream resources. It is safe to call
-// multiple times. Finish calls Close automatically on success; callers
-// should defer Close when there is any chance of early return.
-func (s *RoundStream) Close() error {
-	inner := s.inner
-	s.inner = nil
-	if inner != nil {
-		return inner.Close()
-	}
-	return nil
-}
-
-// Finish completes the round: checks stream error, executes tool calls (if any),
-// and returns the full RoundResult. It closes the underlying stream on success.
-func (s *RoundStream) Finish() (*RoundResult, error) {
-	defer s.Close()
-
-	if err := s.inner.Err(); err != nil {
-		return nil, fmt.Errorf("llm round %q: stream error: %w", s.eventID, err)
-	}
-
-	rawUsage := s.inner.Usage()
-	usage := TokenUsage{
-		InputTokens:  rawUsage.InputTokens,
-		OutputTokens: rawUsage.OutputTokens,
-		TotalTokens:  rawUsage.InputTokens + rawUsage.OutputTokens,
-	}
-
-	accMsg := s.inner.Message()
-	if s.acc.Len() > 0 && len(accMsg.Parts) == 0 {
-		accMsg = NewTextMessage(RoleAssistant, s.acc.String())
-	}
-
-	messages := s.messages
-	if accMsg.Role != "" || len(accMsg.Parts) > 0 {
-		messages = append(messages, accMsg)
-	}
-
-	toolCalls := accMsg.ToolCalls()
-	toolPending := false
-	var toolResults []model.ToolResult
-
-	if len(toolCalls) > 0 && s.reg != nil {
-		toolPending = true
-
-		if s.stream != nil {
-			for _, tc := range toolCalls {
-				s.stream(workflow.StreamEvent{
-					Type:    "tool_call",
-					NodeID:  s.eventID,
-					Payload: map[string]any{"id": tc.ID, "name": tc.Name, "arguments": tc.Arguments},
-				})
-			}
-		}
-
-		toolResults = s.reg.ExecuteAll(s.ctx, toolCalls)
-
-		if s.stream != nil {
-			tcNames := make(map[string]string, len(toolCalls))
-			for _, tc := range toolCalls {
-				tcNames[tc.ID] = tc.Name
-			}
-			for _, r := range toolResults {
-				s.stream(workflow.StreamEvent{
-					Type:   "tool_result",
-					NodeID: s.eventID,
-					Payload: map[string]any{
-						"tool_call_id": r.ToolCallID,
-						"name":         tcNames[r.ToolCallID],
-						"content":      r.Content,
-						"is_error":     r.IsError,
-					},
-				})
-			}
-		}
-
-		messages = append(messages, NewToolResultMessage(toolResults))
-	}
-
-	return &RoundResult{
-		Content:     s.acc.String(),
-		Message:     accMsg,
-		Messages:    messages,
-		ToolCalls:   toolCalls,
-		ToolResults: toolResults,
-		ToolPending: toolPending,
-		Usage:       usage,
-	}, nil
-}
-
-func buildRoundGenerateOptions(cfg RoundConfig, reg *tool.Registry) []GenerateOption {
-	var opts []GenerateOption
-	if cfg.Temperature != nil {
-		opts = append(opts, WithTemperature(*cfg.Temperature))
-	}
-	if cfg.MaxTokens > 0 {
-		opts = append(opts, WithMaxTokens(cfg.MaxTokens))
-	}
-	if cfg.Thinking {
-		opts = append(opts, WithThinking(true))
-	}
-	if cfg.JSONMode {
-		opts = append(opts, WithJSONMode(true))
-	}
-
-	var toolDefs []ToolDefinition
-	if reg != nil && len(cfg.ToolNames) > 0 {
-		allowed := make(map[string]bool, len(cfg.ToolNames))
-		for _, name := range cfg.ToolNames {
-			allowed[name] = true
-		}
-		for _, def := range reg.Definitions() {
-			if allowed[def.Name] {
-				toolDefs = append(toolDefs, def)
-			}
-		}
-	}
-	if len(toolDefs) > 0 {
-		opts = append(opts, WithTools(toolDefs...))
-	}
-	return opts
-}
-
-// RoundConfig configures the LLM call parameters for one round.
-// Board I/O (system prompt injection, output routing, etc.) is the caller's responsibility.
-//
-// Deprecated: RoundConfig is the input shape consumed by [RunRound]
-// and is scheduled for removal in v0.3.0 alongside it. Configure
-// individual [GenerateOption]s on the agent / engine side once the
-// replacement lands.
-type RoundConfig struct {
-	Model       string   `json:"model,omitempty" yaml:"model,omitempty"`
-	Temperature *float64 `json:"temperature,omitempty" yaml:"temperature,omitempty"`
-	MaxTokens   int64    `json:"max_tokens,omitempty" yaml:"max_tokens,omitempty"`
-	JSONMode    bool     `json:"json_mode,omitempty" yaml:"json_mode,omitempty"`
-	Thinking    bool     `json:"thinking,omitempty" yaml:"thinking,omitempty"`
-	ToolNames   []string `json:"tool_names,omitempty" yaml:"tool_names,omitempty"`
-}
-
-// CoerceMapForStruct uses reflection on T's json tags to coerce string values
-// in m to the numeric/bool types expected by the target struct fields. This
-// allows JSON round-trip (Marshal → Unmarshal) to succeed when map values
-// arrive as strings (e.g. from ${board.temperature} template resolution).
-//
-// isDeferred, when non-nil, reports whether a string value is a deferred
-// reference (e.g. a template variable) that will be resolved later. Such
-// values are removed from non-string fields so that json.Unmarshal sees the
-// zero value instead of an invalid string. The caller should supply the
-// resolver's own ContainsRef function to keep detection in sync.
-//
-// The input map is not modified; a shallow clone is returned.
-//
-// Deprecated: CoerceMapForStruct only exists to support
-// [RoundConfigFromMap]. It is scheduled for removal in v0.3.0
-// alongside [RoundConfig].
-func CoerceMapForStruct[T any](m map[string]any, isDeferred func(string) bool) map[string]any {
-	if m == nil {
-		return nil
-	}
-	var zero T
-	t := reflect.TypeOf(zero)
-	if t.Kind() == reflect.Ptr {
-		t = t.Elem()
-	}
-	if t.Kind() != reflect.Struct {
-		return m
-	}
-
-	result := maps.Clone(m)
-	for i := range t.NumField() {
-		field := t.Field(i)
-		tag := field.Tag.Get("json")
-		if tag == "" || tag == "-" {
-			continue
-		}
-		key, _, _ := strings.Cut(tag, ",")
-		if key == "" {
-			continue
-		}
-		val, ok := result[key]
-		if !ok {
-			continue
-		}
-		str, ok := val.(string)
-		if !ok {
-			continue
-		}
-
-		target := field.Type
-		if target.Kind() == reflect.Ptr {
-			target = target.Elem()
-		}
-		if target.Kind() == reflect.String {
-			continue
-		}
-		if coerced, ok := coerceString(str, target.Kind()); ok {
-			result[key] = coerced
-		} else if isDeferred != nil && isDeferred(str) {
-			delete(result, key)
-		}
-	}
-	return result
-}
-
-func coerceString(s string, kind reflect.Kind) (any, bool) {
-	s = strings.TrimSpace(s)
-	if s == "" {
-		return nil, false
-	}
-	switch kind {
-	case reflect.Float32, reflect.Float64:
-		f, err := strconv.ParseFloat(s, 64)
-		if err != nil {
-			return nil, false
-		}
-		return f, true
-	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
-		i, err := strconv.ParseInt(s, 10, 64)
-		if err != nil {
-			return nil, false
-		}
-		return i, true
-	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
-		u, err := strconv.ParseUint(s, 10, 64)
-		if err != nil {
-			return nil, false
-		}
-		return u, true
-	case reflect.Bool:
-		b, err := strconv.ParseBool(s)
-		if err != nil {
-			return nil, false
-		}
-		return b, true
-	default:
-		return nil, false
-	}
-}
-
-// RoundConfigFromMap parses RoundConfig from a generic map via JSON round-trip.
-// isDeferred is passed through to CoerceMapForStruct; see its documentation.
-//
-// Deprecated: scheduled for removal in v0.3.0; see [RoundConfig].
-func RoundConfigFromMap(m map[string]any, isDeferred func(string) bool) (RoundConfig, error) {
-	var cfg RoundConfig
-	if m == nil {
-		return cfg, nil
-	}
-	m = CoerceMapForStruct[RoundConfig](m, isDeferred)
-	data, err := json.Marshal(m)
-	if err != nil {
-		return cfg, fmt.Errorf("llm: marshal config map: %w", err)
-	}
-	if err := json.Unmarshal(data, &cfg); err != nil {
-		return cfg, fmt.Errorf("llm: unmarshal config: %w", err)
-	}
-	return cfg, nil
-}
diff --git a/sdk/llm/factory.go b/sdk/llm/factory.go
--- a/sdk/llm/factory.go
+++ b/sdk/llm/factory.go
@@ -1,15 +1,11 @@
 package llm
 
 import (
-	"context"
 	"sort"
 	"sync"
 	"time"
 
 	"github.com/GizClaw/flowcraft/sdk/errdefs"
-	"github.com/GizClaw/flowcraft/sdk/telemetry"
-
-	otellog "go.opentelemetry.io/otel/log"
 )
 
 // ProviderFactory creates an LLM instance for the given model.
@@ -24,28 +20,9 @@ type ModelInfo struct {
 	Name     string `json:"name"`
 
 	// Spec carries the model-fixed property set (caps + defaults +
-	// limits). Replaces the old bare Caps field; see RegisterModels
-	// for the auto-promote that keeps Caps-only registrations working
-	// during the deprecation window.
+	// limits).
 	Spec ModelSpec `json:"spec,omitempty" yaml:"spec,omitempty"`
 
-	// Caps is a deprecated alias for Spec.Caps, kept until v0.3.0
-	// for backward compatibility with existing provider registrations.
-	// When both are non-zero, Spec.Caps wins; when only Caps is set,
-	// RegisterModels auto-promotes it into Spec.Caps so the rest of
-	// the system reads a unified Spec.
-	//
-	// JSON / YAML tags are intentionally `"-"` to remove the alias
-	// from serialized output: writers SHOULD use Spec.Caps.
-	// Deserializers reading legacy YAML that names `caps:` at the
-	// top level are expected to migrate the call site (set Spec.Caps
-	// before passing to RegisterModels) — see doc/sdk-llm-redesign.md
-	// §3.3 for the rationale.
-	//
-	// Deprecated: set ModelInfo.Spec.Caps directly. Scheduled for
-	// removal in v0.3.0.
-	Caps ModelCaps `json:"-" yaml:"-"`
-
 	// Deprecation, when non-zero, marks this catalog entry as a
 	// legacy model the provider has scheduled (or already executed)
 	// for retirement. The resolver still serves deprecated models —
@@ -166,54 +143,16 @@ func (r *ProviderRegistry) ListProviders() []string {
 	return names
 }
 
-// RegisterModels associates a list of models with a provider. As part
-// of registration, any ModelInfo that uses the deprecated Caps field
-// without filling Spec.Caps gets auto-promoted (Spec.Caps = Caps) so
-// downstream lookups always see the unified Spec form. When both
-// Spec.Caps and Caps are non-zero, Spec.Caps wins (the new field is
-// authoritative).
-//
-// The first time a provider registers any model that triggers the
-// auto-promote path, a single deprecation warning is emitted via
-// telemetry.Warn. Subsequent re-registrations of the same provider
-// stay silent — see deprecatedCapsWarned for the dedup state.
+// RegisterModels associates a list of models with a provider.
 func (r *ProviderRegistry) RegisterModels(provider string, models []ModelInfo) {
 	r.mu.Lock()
 	defer r.mu.Unlock()
 	cp := make([]ModelInfo, len(models))
 	copy(cp, models)
-	usesLegacy := false
 	for i := range cp {
 		cp[i].Provider = provider
-		// Auto-promote deprecated Caps → Spec.Caps. Skip when Spec.Caps
-		// is already set (the caller migrated; respect their choice).
-		if cp[i].Spec.Caps.IsZero() && !cp[i].Caps.IsZero() {
-			cp[i].Spec.Caps = cp[i].Caps
-			usesLegacy = true
-		}
 	}
 	r.providerModels[provider] = cp
-	if usesLegacy {
-		warnLegacyModelInfoCaps(provider)
-	}
-}
-
-// deprecatedCapsWarned dedupes the legacy ModelInfo.Caps warning so
-// each provider triggers it at most once per process. Using a
-// dedicated sync.Map (instead of mu-guarded set) keeps RegisterModels
-// fast and lock-free for the dedup probe.
-var deprecatedCapsWarned sync.Map // map[string]struct{} keyed by provider
-
-func warnLegacyModelInfoCaps(provider string) {
-	if _, loaded := deprecatedCapsWarned.LoadOrStore(provider, struct{}{}); loaded {
-		return
-	}
-	// Background ctx is intentional — the warning belongs to the
-	// process startup path, not to any per-call ctx that might be
-	// cancelled. telemetry.Warn handles a nil exporter gracefully.
-	telemetry.Warn(context.Background(),
-		"llm: ModelInfo.Caps is deprecated; set ModelInfo.Spec.Caps directly (removal: v0.3.0)",
-		otellog.String("provider", provider))
 }
 
 // ListAllModels returns all registered models across all providers.
diff --git a/sdk/llm/fallback.go b/sdk/llm/fallback.go
--- a/sdk/llm/fallback.go
+++ b/sdk/llm/fallback.go
@@ -72,8 +72,8 @@ func allFailedError(lastErr error) error {
 // next provider in the chain, how long should the breaker stay open
 // after a trip, and what label to attach on per-category metrics.
 // They are package-private helpers because nobody outside this file
-// calls them — peers (sdkx/llm/*, sdkx/embedding/*, future
-// sdkx/rerank, ...) consume the errdefs class directly via
+// calls them — peer adapters (LLM providers, embedders, rerankers in
+// external packages) consume the errdefs class directly via
 // errdefs.IsXxx and don't need the LLM-fallback lens.
 
 // shouldFallback reports whether a given category should try the next
diff --git a/sdk/llm/llm.go b/sdk/llm/llm.go
--- a/sdk/llm/llm.go
+++ b/sdk/llm/llm.go
@@ -104,15 +104,9 @@
 //     on (provider, model, profile), so per-tenant eviction is
 //     possible via [WithProfile].
 //
-// # Compatibility
-//
-// New code should consume [WithCaps] / [WithDefaults] / [WithLimits]
+// New code consumes [WithCaps] / [WithDefaults] / [WithLimits]
 // directly, [ProviderRegistry.LookupModelSpec] for catalog lookups,
-// and [WithPolicyCaps] for resolver-wide policy. The pre-redesign
-// names — [CapsMiddleware], [WithExtraCaps],
-// [ProviderRegistry.LookupModelCaps], [ModelInfo.Caps] — are kept
-// as thin shims in deprecated.go and on the deprecation field, all
-// scheduled for removal in v0.3.0.
+// and [WithPolicyCaps] for resolver-wide policy.
 //
 // See doc/sdk-llm-redesign.md for the full design rationale,
 // per-cap behavior table, and migration guide.
diff --git a/sdk/model/message.go b/sdk/model/message.go
--- a/sdk/model/message.go
+++ b/sdk/model/message.go
@@ -92,6 +92,27 @@ func (m Message) Clone() Message {
 	}
 }
 
+// LastByRole returns the last message in msgs whose Role matches role.
+// The boolean is false when no such message exists. The returned Message
+// is the slice element itself (not a deep copy); callers that intend to
+// mutate it should call [Message.Clone] first.
+//
+// Typical use is for graph nodes that need to read a single role-scoped
+// turn from a board channel — e.g. "the latest user message on
+// MainChannel" — without re-implementing the reverse scan everywhere:
+//
+//	if m, ok := model.LastByRole(b.Channel(engine.MainChannel), model.RoleUser); ok {
+//	    query = m.Content()
+//	}
+func LastByRole(msgs []Message, role Role) (Message, bool) {
+	for i := len(msgs) - 1; i >= 0; i-- {
+		if msgs[i].Role == role {
+			return msgs[i], true
+		}
+	}
+	return Message{}, false
+}
+
 // CloneMessages returns a deep copy of msgs. Nil stays nil so callers can
 // preserve the usual JSON / len semantics.
 func CloneMessages(msgs []Message) []Message {
diff --git a/sdk/recall/doc.go b/sdk/recall/doc.go
--- a/sdk/recall/doc.go
+++ b/sdk/recall/doc.go
@@ -11,8 +11,8 @@
 //   - Entity linking via Doc.Metadata["entities"], consumed by
 //     EntityBoost.
 //   - Sync Save and async SaveAsync backed by a [JobQueue] (default
-//     in-memory; sdkx/recall/jobqueue/sqlite provides a durable
-//     SQLite queue).
+//     in-memory; durable adapters such as a SQLite queue live in
+//     external adapter packages).
 //   - Three-axis [Scope] (RuntimeID + AgentID + UserID) plus a
 //     [Partitions] selector that controls whether a recall visits the
 //     per-user bucket, the runtime-global bucket, or both.
diff --git a/sdk/recall/jobs.go b/sdk/recall/jobs.go
--- a/sdk/recall/jobs.go
+++ b/sdk/recall/jobs.go
@@ -99,8 +99,9 @@ func statusFromRecord(r *JobRecord) JobStatus {
 
 // MemoryJobQueue is the default in-process JobQueue.
 //
-// It does NOT survive a process crash. For crash-recoverable Async Save use
-// sdkx/recall/jobqueue/sqlite.SQLiteJobQueue.
+// It does NOT survive a process crash. For crash-recoverable Async
+// Save, plug a durable JobQueue adapter (e.g. SQLite-backed) supplied
+// by an external package.
 type MemoryJobQueue struct {
 	mu     sync.Mutex
 	jobs   map[JobID]*JobRecord
diff --git a/sdk/recall/memory.go b/sdk/recall/memory.go
--- a/sdk/recall/memory.go
+++ b/sdk/recall/memory.go
@@ -305,7 +305,8 @@ func WithSoftMergeThreshold(cosineMin float64, topK int) Option {
 
 // WithJobQueue plugs in a durable [JobQueue] for SaveAsync. Defaults to
 // an in-memory queue suitable for tests; production deployments should
-// use [sdkx/recall/jobqueue/sqlite] or similar.
+// supply a persistent adapter (e.g. a SQLite-backed queue) from an
+// external package.
 func WithJobQueue(q JobQueue) Option { return func(c *config) { c.jobQueue = q } }
 
 // WithAsyncWorkers sets the number of background workers draining the
diff --git a/sdk/retrieval/explain.go b/sdk/retrieval/explain.go
--- a/sdk/retrieval/explain.go
+++ b/sdk/retrieval/explain.go
@@ -69,27 +69,3 @@ type SearchDebug struct {
 	IncludeLanes  bool
 	IncludeStages bool
 }
-
-// ProjectRawByRetriever copies the lane hits from a SearchExecution into the
-// legacy RawByRetriever map shape used by SearchResponse before v0.3.0.
-//
-// Returns nil when execution is nil or carries no lanes; the caller may use
-// this as the value for the deprecated SearchResponse.RawByRetriever field.
-func ProjectRawByRetriever(execution *SearchExecution) map[string][]Hit {
-	if execution == nil || len(execution.Lanes) == 0 {
-		return nil
-	}
-	out := make(map[string][]Hit, len(execution.Lanes))
-	for _, lane := range execution.Lanes {
-		if lane.Key == "" || len(lane.Hits) == 0 {
-			continue
-		}
-		cp := make([]Hit, len(lane.Hits))
-		copy(cp, lane.Hits)
-		out[string(lane.Key)] = cp
-	}
-	if len(out) == 0 {
-		return nil
-	}
-	return out
-}
diff --git a/sdk/retrieval/pipeline/pipeline.go b/sdk/retrieval/pipeline/pipeline.go
--- a/sdk/retrieval/pipeline/pipeline.go
+++ b/sdk/retrieval/pipeline/pipeline.go
@@ -165,9 +165,6 @@ func (p *Pipeline) Run(ctx context.Context, idx retrieval.Index, namespace strin
 	resp := &retrieval.SearchResponse{Hits: hits, Took: time.Since(overall)}
 
 	debug := req.Debug
-	if req.ReturnRaw {
-		debug.IncludeLanes = true
-	}
 
 	if debug.IncludeLanes || debug.IncludeStages {
 		exec := &retrieval.SearchExecution{}
@@ -220,9 +217,6 @@ func (p *Pipeline) Run(ctx context.Context, idx retrieval.Index, namespace strin
 			exec.Stages = append(exec.Stages, st.HybridExecution.Stages...)
 		}
 		resp.Execution = exec
-		if req.ReturnRaw {
-			resp.RawByRetriever = retrieval.ProjectRawByRetriever(exec)
-		}
 	}
 	return resp, nil
 }
diff --git a/sdk/retrieval/search.go b/sdk/retrieval/search.go
--- a/sdk/retrieval/search.go
+++ b/sdk/retrieval/search.go
@@ -34,14 +34,6 @@ type SearchRequest struct {
 	// stable; hybrid / fused scores live on backend-specific scales and
 	// are NOT subject to MinScore — use pipeline.ScoreThreshold there.
 	MinScore float64
-
-	// ReturnRaw asks the backend to expose per-lane raw hits via the legacy
-	// SearchResponse.RawByRetriever map.
-	//
-	// Deprecated: use Debug.IncludeLanes and read SearchResponse.Execution
-	// instead. This field will be removed in v0.3.0; backends populate
-	// RawByRetriever as a projection of Execution while it is still present.
-	ReturnRaw bool
 }
 
 // SearchResponse holds ranked hits.
@@ -52,13 +44,6 @@ type SearchResponse struct {
 	// Execution is the structured explanation of how this response was
 	// produced. Populated when SearchRequest.Debug requests it; otherwise nil.
 	Execution *SearchExecution
-
-	// RawByRetriever is the per-lane raw hits map produced by older callers.
-	//
-	// Deprecated: use Execution.Lanes instead. Backends keep this populated
-	// (as a projection of Execution) until v0.3.0, when this field will be
-	// removed.
-	RawByRetriever map[string][]Hit
 }
 
 // Hit is one ranked document.
diff --git a/sdk/script/bindings/bridge_board.go b/sdk/script/bindings/bridge_board.go
--- a/sdk/script/bindings/bridge_board.go
+++ b/sdk/script/bindings/bridge_board.go
@@ -3,6 +3,7 @@ package bindings
 import (
 	"context"
 
+	"github.com/GizClaw/flowcraft/sdk/engine"
 	"github.com/GizClaw/flowcraft/sdk/model"
 )
 
@@ -43,12 +44,20 @@ type Board interface {
 //   - setChannel(name, msgs)     → throws on validation errors
 //   - appendChannel(name, msg)   → throws on validation errors
 //
+// Constants:
+//   - MAIN_CHANNEL — the engine's reserved default channel name; scripts
+//     should reference this rather than hard-coding the literal string
+//     so future renames do not break existing scripts.
+//
 // All channel APIs require an explicit name — scripts must opt into
-// MainChannel by passing "" themselves. This avoids accidentally
-// stitching unrelated conversations together via an implicit default.
+// MainChannel by passing board.MAIN_CHANNEL themselves. This avoids
+// accidentally stitching unrelated conversations together via an
+// implicit default.
 func NewBoardBridge(board Board) BindingFunc {
 	return func(_ context.Context) (string, any) {
 		return "board", map[string]any{
+			"MAIN_CHANNEL": engine.MainChannel,
+
 			"getVar":  func(key string) any { v, _ := board.GetVar(key); return v },
 			"setVar":  func(key string, value any) { board.SetVar(key, value) },
 			"getVars": func() map[string]any { return board.Vars() },
diff --git a/sdk/script/bindings/bridge_llm.go b/sdk/script/bindings/bridge_llm.go
--- a/sdk/script/bindings/bridge_llm.go
+++ b/sdk/script/bindings/bridge_llm.go
@@ -94,7 +94,7 @@ type LLMRunOptions struct {
 //	}
 //	var r = s.finish();          // round result map
 //	board.setVar("answer", r.content);
-//	board.setChannel("main", r.messages);
+//	board.setChannel(board.MAIN_CHANNEL, r.messages);
 //
 // Neither mode writes to the board; the script controls what to do
 // with results (typically via the board bridge: board.setVar /
diff --git a/sdk/script/bindings/bridge_run.go b/sdk/script/bindings/bridge_run.go
--- a/sdk/script/bindings/bridge_run.go
+++ b/sdk/script/bindings/bridge_run.go
@@ -20,27 +20,22 @@ import (
 // agent.RunInfo is unset; scripts can do `if (!run.get_task_id()) { … }`
 // to branch on absence without needing a separate "has_*" probe.
 //
-// Naming: the legacy NewRunBridge in deprecated.go is kept under its
-// original name to avoid breaking existing callers; the new constructor
-// names its data source (RunInfo) instead. Once the legacy bridge is
-// removed in v0.3.0, this will be renamed to NewRunBridge.
+// Naming: the constructor advertises its data source (RunInfo) rather
+// than using the bare "Run" prefix. The previous workflow-coupled
+// NewRunBridge was retired in v0.3.0; this is now the only run-metadata
+// bridge in the package.
 //
-// Design choices vs. the deprecated NewRunBridge in deprecated.go:
+// Design choices:
 //
 //   - Pulls metadata from agent.RunInfo directly. No board lookup, no
-//     workflow.VarRunID convention key. The information lives on the call
-//     stack where it was minted, not in a side-channel string map.
+//     VarRunID convention key. The information lives on the call stack
+//     where it was minted, not in a side-channel string map.
 //
-//   - No board reference. The previous bridge accepted a *workflow.Board
-//     so it could fall back to reading "__run_id" — pure tech debt from
-//     when run state was scattered across the blackboard. The agent runtime
-//     hands you the full RunInfo, so the bridge has no reason to know
-//     about a board at all.
+//   - No board reference. Run identity and board state are independent
+//     concerns; the bridge has no reason to know about the board.
 //
-//   - Exposes AgentID and ContextID in addition to RunID/TaskID. These
-//     two fields exist on agent.RunInfo and were not surfaced by the old
-//     bridge; scripts that route on multi-agent or multi-conversation
-//     identity need them.
+//   - Exposes AgentID and ContextID in addition to RunID/TaskID — scripts
+//     that route on multi-agent or multi-conversation identity need them.
 //
 //   - Takes the value (not a pointer). RunInfo is a small immutable
 //     descriptor; copying it into the closure is cheaper and safer than
diff --git a/sdk/script/bindings/deprecated.go b/sdk/script/bindings/deprecated.go
deleted file mode 100644
--- a/sdk/script/bindings/deprecated.go
+++ /dev/null
@@ -1,117 +0,0 @@
-package bindings
-
-// This file collects bridge entry points scheduled for removal in v0.3.0.
-// They are kept here, isolated from the active surface, so the rest of the
-// package can evolve free of workflow-era assumptions while existing callers
-// keep compiling.
-//
-// Removal criteria for each symbol below:
-//   - All in-tree consumers have migrated off the workflow streaming /
-//     control-plane model.
-//   - The replacement (typically engine.Board + agent runtime) is stable.
-//
-// Do not add new code here. Add new bridges as bridge_xxx.go.
-
-import (
-	"context"
-
-	"github.com/GizClaw/flowcraft/sdk/tool"
-	"github.com/GizClaw/flowcraft/sdk/workflow"
-)
-
-// NewStreamBridge exposes streaming as global "stream" (emit).
-//
-// Deprecated: scheduled for removal in v0.3.0. Tied to workflow.StreamCallback
-// and currently only consumed by graph/node/scriptnode (which itself rides on
-// workflow's streaming model). Will be replaced once graph migrates off
-// workflow.StreamCallback.
-func NewStreamBridge(stream workflow.StreamCallback, nodeID string) BindingFunc {
-	return func(_ context.Context) (string, any) {
-		return "stream", map[string]any{
-			"emit": func(eventType string, payload any) {
-				if stream != nil {
-					stream(workflow.StreamEvent{Type: eventType, NodeID: nodeID, Payload: payload})
-				}
-			},
-		}
-	}
-}
-
-// RunBridgeOptions configures NewRunBridge (workflow / agent metadata on the board).
-//
-// Deprecated: scheduled for removal in v0.3.0 together with NewRunBridge.
-// See NewRunBridge for the engine/agent-era replacement plan.
-type RunBridgeOptions struct {
-	Board *workflow.Board
-	// TaskID is optional (e.g. workflow.Request.TaskID).
-	TaskID string
-	// RunID, if non-empty, is returned by get_run_id instead of reading the board.
-	RunID string
-}
-
-// NewRunBridge exposes read-only run metadata to scripts as global "run":
-//   - get_run_id() string
-//   - get_task_id() string
-//
-// Deprecated: scheduled for removal in v0.3.0. Hard-wired to *workflow.Board
-// and the workflow.VarRunID convention. The engine/agent stack carries the
-// same metadata as agent.RunInfo (RunID/TaskID/AgentID/ContextID) — pass it
-// in directly without going through a board key. The replacement bridge will
-// land alongside the rest of the agent-runtime cleanup.
-func NewRunBridge(opts RunBridgeOptions) BindingFunc {
-	return func(_ context.Context) (string, any) {
-		return "run", map[string]any{
-			"get_run_id": func() string {
-				if opts.RunID != "" {
-					return opts.RunID
-				}
-				if opts.Board == nil {
-					return ""
-				}
-				return opts.Board.GetVarString(workflow.VarRunID)
-			},
-			"get_task_id": func() string {
-				return opts.TaskID
-			},
-		}
-	}
-}
-
-// AgentStepOptions selects common bindings for one workflow agent step (Lua/JS),
-// without pulling in LLM streaming (add NewStreamBridge at the call site if needed).
-//
-// Deprecated: scheduled for removal in v0.3.0 together with AgentStepBindings.
-type AgentStepOptions struct {
-	Board *workflow.Board
-	// TaskID / RunID mirror workflow.Request fields; RunID overrides board when non-empty.
-	TaskID string
-	RunID  string
-
-	ToolRegistry *tool.Registry
-	// AllowedTools is passed to WithAllowedToolNames when non-empty (ignored if ToolRegistry is nil).
-	AllowedTools []string
-}
-
-// AgentStepBindings returns a typical binding set: board, run, expr, optional tools.
-// Caller still supplies config + script.Runtime-specific globals (signal, etc.).
-//
-// Deprecated: scheduled for removal in v0.3.0. The agent/engine stack does not
-// need this preset — callers compose BuildEnv with the bridges they want
-// directly (typically four lines), and binding combinations vary too much per
-// agent for one preset to be worth maintaining.
-func AgentStepBindings(o AgentStepOptions) []BindingFunc {
-	var fns []BindingFunc
-	if o.Board != nil {
-		fns = append(fns, NewBoardBridge(o.Board))
-	}
-	fns = append(fns, NewRunBridge(RunBridgeOptions{
-		Board:  o.Board,
-		TaskID: o.TaskID,
-		RunID:  o.RunID,
-	}))
-	fns = append(fns, NewExprBridge())
-	if o.ToolRegistry != nil && len(o.AllowedTools) > 0 {
-		fns = append(fns, NewToolBridge(o.ToolRegistry, WithAllowedToolNames(o.AllowedTools...)))
-	}
-	return fns
-}
diff --git a/sdk/script/bindings/doc.go b/sdk/script/bindings/doc.go
--- a/sdk/script/bindings/doc.go
+++ b/sdk/script/bindings/doc.go
@@ -11,12 +11,10 @@
 //
 // # Dependency constraint
 //
-// bindings depends on llm, model, tool, engine, and (for the bridges in
-// deprecated.go) workflow. It must never depend on graph: graph composes
-// bindings, not the other way around. The Board surface bindings consume is
-// the structural bindings.Board interface, which both *engine.Board and
-// *workflow.Board satisfy — so callers can pass either without conversion
-// while we migrate fully off workflow.
+// bindings depends on llm, model, tool, engine. It must never depend on
+// graph: graph composes bindings, not the other way around. The Board
+// surface bindings consume is the structural bindings.Board interface,
+// which *engine.Board satisfies directly.
 //
 // # Layering model
 //
@@ -49,7 +47,6 @@
 //	llm_marshal.go        model.* ⇄ map[string]any projections (multimodal-aware)
 //	bridge_tools.go   tool.Registry (deny-by-default, explicit allowlist or AllowAll)
 //	bridge_run.go     run metadata exposed from agent.RunInfo (run/task/agent/context ids)
-//	deprecated.go     v0.3.0 removal queue: NewStreamBridge, NewRunBridge, AgentStepBindings
 //	*_test.go         table-driven / jsrt integration tests
 //
 // # Global naming convention
@@ -67,8 +64,6 @@
 //     you need; add NewLLMBridge when LLM access is required, and use
 //     NewRunInfoBridge(runInfo) to surface run/task/agent/context ids.
 //     There is no global preset — the four lines of BuildEnv are the preset.
-//   - Legacy workflow agent step: see deprecated.go (NewRunBridge,
-//     AgentStepBindings — both slated for v0.3.0 removal).
 //
 // # Checklist for adding a new bridge
 //
diff --git a/sdk/script/bindings/llm_marshal.go b/sdk/script/bindings/llm_marshal.go
--- a/sdk/script/bindings/llm_marshal.go
+++ b/sdk/script/bindings/llm_marshal.go
@@ -211,9 +211,9 @@ func usageToMap(u model.TokenUsage) map[string]any {
 // (setChannel / appendChannel). The shape on the script side mirrors
 // what messageToMap / partToMap emit, so a script can round-trip:
 //
-//	var msgs = board.channel("main");
+//	var msgs = board.channel(board.MAIN_CHANNEL);
 //	msgs.push({ role: "user", parts: [{ type: "text", text: "go on" }] });
-//	board.setChannel("main", msgs);
+//	board.setChannel(board.MAIN_CHANNEL, msgs);
 //
 // Reverse marshalers are intentionally strict:
 //   - Unknown keys at any level are rejected with a path-prefixed error
@@ -254,7 +254,7 @@ var (
 // into a []model.Message ready for board.SetChannel.
 //
 // ctx labels the script entry point that triggered the call so that
-// errors point back to setChannel("main", …) rather than just "msgs[1]".
+// errors point back to setChannel(name, …) rather than just "msgs[1]".
 func parseChannelMessages(raw any, ctx string) ([]model.Message, error) {
 	if raw == nil {
 		return nil, nil
diff --git a/sdk/workflow/agent.go b/sdk/workflow/agent.go
deleted file mode 100644
--- a/sdk/workflow/agent.go
+++ /dev/null
@@ -1,73 +0,0 @@
-package workflow
-
-// Agent describes identity and execution strategy for one logical agent.
-type Agent interface {
-	ID() string
-	Card() AgentCard
-	Strategy() Strategy
-	Tools() []string
-}
-
-// AgentCard describes capabilities for discovery (e.g. A2A).
-type AgentCard struct {
-	Name         string
-	Description  string
-	Skills       []Skill
-	InputModes   []string
-	OutputModes  []string
-	Capabilities AgentCapabilities
-}
-
-// Skill is a lightweight skill declaration on an AgentCard.
-type Skill struct {
-	ID          string `json:"id"`
-	Name        string `json:"name"`
-	Description string `json:"description,omitempty"`
-}
-
-// AgentCapabilities declares optional runtime features.
-type AgentCapabilities struct {
-	Streaming        bool `json:"streaming,omitempty"`
-	PushNotification bool `json:"push_notification,omitempty"`
-	StateTransition  bool `json:"state_transition,omitempty"`
-}
-
-type simpleAgent struct {
-	id       string
-	card     AgentCard
-	strategy Strategy
-	tools    []string
-}
-
-func (a *simpleAgent) ID() string         { return a.id }
-func (a *simpleAgent) Card() AgentCard    { return a.card }
-func (a *simpleAgent) Strategy() Strategy { return a.strategy }
-func (a *simpleAgent) Tools() []string    { return a.tools }
-
-// AgentOption configures NewAgent.
-type AgentOption func(*simpleAgent)
-
-// WithAgentDescription sets the card description.
-func WithAgentDescription(desc string) AgentOption {
-	return func(a *simpleAgent) { a.card.Description = desc }
-}
-
-// WithAgentTools sets tool names exposed to the runtime.
-func WithAgentTools(tools []string) AgentOption {
-	return func(a *simpleAgent) { a.tools = tools }
-}
-
-// NewAgent constructs a basic Agent backed by the given Strategy.
-func NewAgent(id string, strategy Strategy, opts ...AgentOption) Agent {
-	a := &simpleAgent{
-		id:       id,
-		strategy: strategy,
-		card: AgentCard{
-			Name: id,
-		},
-	}
-	for _, o := range opts {
-		o(a)
-	}
-	return a
-}
diff --git a/sdk/workflow/board.go b/sdk/workflow/board.go
deleted file mode 100644
--- a/sdk/workflow/board.go
+++ /dev/null
@@ -1,344 +0,0 @@
-// Package workflow defines the execution blackboard and high-level agent runtime types.
-package workflow
-
-import (
-	"fmt"
-	"maps"
-	"reflect"
-	"sync"
-
-	"github.com/GizClaw/flowcraft/sdk/model"
-)
-
-// Cloneable may be implemented by values stored in Board vars
-// to provide a type-safe deep copy instead of the JSON fallback.
-type Cloneable interface {
-	Clone() any
-}
-
-// MainChannel is the default message channel key (empty string).
-const MainChannel = ""
-
-// Board is the graph execution blackboard: typed message channels plus control vars.
-// Card-based kanban coordination lives in kanban.Board, not here.
-//
-// Thread safety: public methods use a mutex (matches historical graph.Board behavior).
-type Board struct {
-	mu       sync.RWMutex
-	channels map[string][]model.Message
-	vars     map[string]any
-}
-
-// BoardSnapshot is a serializable representation of execution state (no kanban cards).
-type BoardSnapshot struct {
-	Vars     map[string]any             `json:"vars"`
-	Channels map[string][]model.Message `json:"channels,omitempty"`
-}
-
-// NewBoard creates an empty Board with an initialized main channel.
-func NewBoard() *Board {
-	return &Board{
-		channels: map[string][]model.Message{MainChannel: {}},
-		vars:     make(map[string]any),
-	}
-}
-
-// ---------- Vars ----------
-
-// SetVar sets a board-level variable.
-func (b *Board) SetVar(key string, value any) {
-	b.mu.Lock()
-	b.vars[key] = value
-	b.mu.Unlock()
-}
-
-// GetVar retrieves a board-level variable.
-func (b *Board) GetVar(key string) (any, bool) {
-	b.mu.RLock()
-	defer b.mu.RUnlock()
-	v, ok := b.vars[key]
-	return v, ok
-}
-
-// GetVarString retrieves a board variable as a string, returning "" if missing or wrong type.
-func (b *Board) GetVarString(key string) string {
-	b.mu.RLock()
-	defer b.mu.RUnlock()
-	if s, ok := b.vars[key].(string); ok {
-		return s
-	}
-	return ""
-}
-
-// GetTyped retrieves a typed value from the Board's vars.
-func GetTyped[T any](b *Board, key string) (T, bool) {
-	raw, ok := b.GetVar(key)
-	if !ok {
-		var zero T
-		return zero, false
-	}
-	v, ok := raw.(T)
-	return v, ok
-}
-
-// Vars returns a shallow copy of all board-level variables.
-func (b *Board) Vars() map[string]any {
-	b.mu.RLock()
-	defer b.mu.RUnlock()
-	cp := make(map[string]any, len(b.vars))
-	maps.Copy(cp, b.vars)
-	return cp
-}
-
-// AppendSliceVar atomically appends a value to a slice stored in a board variable.
-// It returns an error if the existing value is not a []any (instead of silently overwriting).
-func (b *Board) AppendSliceVar(key string, value any) error {
-	b.mu.Lock()
-	defer b.mu.Unlock()
-	existing, ok := b.vars[key]
-	if !ok {
-		b.vars[key] = []any{value}
-		return nil
-	}
-	slice, ok := existing.([]any)
-	if !ok {
-		return fmt.Errorf("board: var %q is %T, not []any", key, existing)
-	}
-	b.vars[key] = append(slice, value)
-	return nil
-}
-
-// UpdateSliceVarItem finds and updates the first matching item in a slice variable.
-func (b *Board) UpdateSliceVarItem(key string, match func(any) bool, update func(any) any) {
-	b.mu.Lock()
-	defer b.mu.Unlock()
-	existing, ok := b.vars[key]
-	if !ok {
-		return
-	}
-	slice, ok := existing.([]any)
-	if !ok {
-		return
-	}
-	for i, item := range slice {
-		if match(item) {
-			slice[i] = update(item)
-			return
-		}
-	}
-}
-
-// ---------- Channels ----------
-
-// Channel returns a copy of messages for the given channel (empty slice if missing).
-func (b *Board) Channel(name string) []model.Message {
-	b.mu.RLock()
-	defer b.mu.RUnlock()
-	msgs := b.channels[name]
-	if len(msgs) == 0 {
-		return nil
-	}
-	out := make([]model.Message, len(msgs))
-	copy(out, msgs)
-	return out
-}
-
-// SetChannel replaces the entire message list for a channel.
-func (b *Board) SetChannel(name string, msgs []model.Message) {
-	b.mu.Lock()
-	if b.channels == nil {
-		b.channels = map[string][]model.Message{}
-	}
-	cp := make([]model.Message, len(msgs))
-	copy(cp, msgs)
-	b.channels[name] = cp
-	b.mu.Unlock()
-}
-
-// AppendChannelMessage appends a message to a channel.
-func (b *Board) AppendChannelMessage(name string, msg model.Message) {
-	b.mu.Lock()
-	if b.channels == nil {
-		b.channels = map[string][]model.Message{}
-	}
-	b.channels[name] = append(b.channels[name], msg)
-	b.mu.Unlock()
-}
-
-// ChannelsCopy returns a deep copy of all channel message lists (for parallel merge).
-func (b *Board) ChannelsCopy() map[string][]model.Message {
-	b.mu.RLock()
-	defer b.mu.RUnlock()
-	out := make(map[string][]model.Message, len(b.channels))
-	for k, msgs := range b.channels {
-		cp := make([]model.Message, len(msgs))
-		copy(cp, msgs)
-		out[k] = cp
-	}
-	return out
-}
-
-// ---------- Snapshot / Restore ----------
-
-// Snapshot returns a serializable snapshot (vars + channels only).
-func (b *Board) Snapshot() *BoardSnapshot {
-	b.mu.RLock()
-	defer b.mu.RUnlock()
-
-	chCopy := make(map[string][]model.Message, len(b.channels))
-	for k, msgs := range b.channels {
-		cp := make([]model.Message, len(msgs))
-		copy(cp, msgs)
-		chCopy[k] = cp
-	}
-	return &BoardSnapshot{
-		Vars:     deepCopyVars(b.vars),
-		Channels: chCopy,
-	}
-}
-
-// RestoreBoard reconstructs a Board from a snapshot.
-func RestoreBoard(snap *BoardSnapshot) *Board {
-	if snap == nil {
-		return NewBoard()
-	}
-	b := &Board{
-		channels: make(map[string][]model.Message),
-		vars:     deepCopyVars(snap.Vars),
-	}
-	if len(snap.Channels) > 0 {
-		for k, msgs := range snap.Channels {
-			cp := make([]model.Message, len(msgs))
-			copy(cp, msgs)
-			b.channels[k] = cp
-		}
-	} else {
-		b.channels[MainChannel] = []model.Message{}
-	}
-	return b
-}
-
-// RestoreFrom overwrites this board from a snapshot (executor retry rollback).
-func (b *Board) RestoreFrom(snap *BoardSnapshot) {
-	if snap == nil {
-		return
-	}
-	b.mu.Lock()
-	defer b.mu.Unlock()
-	b.vars = deepCopyVars(snap.Vars)
-	b.channels = make(map[string][]model.Message)
-	if len(snap.Channels) > 0 {
-		for k, msgs := range snap.Channels {
-			cp := make([]model.Message, len(msgs))
-			copy(cp, msgs)
-			b.channels[k] = cp
-		}
-	} else {
-		// Mirror RestoreBoard / NewBoard: every Board must expose
-		// MainChannel even when the snapshot didn't carry channels.
-		b.channels[MainChannel] = []model.Message{}
-	}
-}
-
-// ---------- internal ----------
-
-func deepCopyVars(src map[string]any) map[string]any {
-	if src == nil {
-		return make(map[string]any)
-	}
-	cp := make(map[string]any, len(src))
-	for k, v := range src {
-		cp[k] = deepCopyValue(v)
-	}
-	return cp
-}
-
-func deepCopyValue(v any) any {
-	if v == nil {
-		return nil
-	}
-	switch val := v.(type) {
-	case string, int, int8, int16, int32, int64,
-		uint, uint8, uint16, uint32, uint64,
-		float32, float64, bool:
-		return v
-	case []model.Message:
-		out := make([]model.Message, len(val))
-		copy(out, val)
-		return out
-	case []any:
-		out := make([]any, len(val))
-		for i, item := range val {
-			out[i] = deepCopyValue(item)
-		}
-		return out
-	case map[string]any:
-		out := make(map[string]any, len(val))
-		for k, item := range val {
-			out[k] = deepCopyValue(item)
-		}
-		return out
-	case Cloneable:
-		return val.Clone()
-	default:
-		return reflectDeepCopy(reflect.ValueOf(v)).Interface()
-	}
-}
-
-// reflectDeepCopy recursively deep-copies a reflect.Value.
-// Unsupported kinds (Chan, Func, UnsafePointer) are returned as-is.
-func reflectDeepCopy(v reflect.Value) reflect.Value {
-	switch v.Kind() {
-	case reflect.Pointer:
-		if v.IsNil() {
-			return reflect.Zero(v.Type())
-		}
-		cp := reflect.New(v.Type().Elem())
-		cp.Elem().Set(reflectDeepCopy(v.Elem()))
-		return cp
-	case reflect.Slice:
-		if v.IsNil() {
-			return reflect.Zero(v.Type())
-		}
-		cp := reflect.MakeSlice(v.Type(), v.Len(), v.Len())
-		for i := range v.Len() {
-			cp.Index(i).Set(reflectDeepCopy(v.Index(i)))
-		}
-		return cp
-	case reflect.Map:
-		if v.IsNil() {
-			return reflect.Zero(v.Type())
-		}
-		cp := reflect.MakeMapWithSize(v.Type(), v.Len())
-		iter := v.MapRange()
-		for iter.Next() {
-			cp.SetMapIndex(reflectDeepCopy(iter.Key()), reflectDeepCopy(iter.Value()))
-		}
-		return cp
-	case reflect.Struct:
-		cp := reflect.New(v.Type()).Elem()
-		for i := range v.NumField() {
-			f := cp.Field(i)
-			if f.CanSet() {
-				f.Set(reflectDeepCopy(v.Field(i)))
-			}
-		}
-		return cp
-	case reflect.Array:
-		cp := reflect.New(v.Type()).Elem()
-		for i := range v.Len() {
-			cp.Index(i).Set(reflectDeepCopy(v.Index(i)))
-		}
-		return cp
-	case reflect.Interface:
-		if v.IsNil() {
-			return reflect.Zero(v.Type())
-		}
-		inner := reflectDeepCopy(v.Elem())
-		cp := reflect.New(v.Type()).Elem()
-		cp.Set(inner)
-		return cp
-	default:
-		return v
-	}
-}
diff --git a/sdk/workflow/doc.go b/sdk/workflow/doc.go
deleted file mode 100644
--- a/sdk/workflow/doc.go
+++ /dev/null
@@ -1,77 +0,0 @@
-// Package workflow defines the execution blackboard (Board: Vars + Channels),
-// the Runtime orchestration API (Run, MemorySession, prepare/finish),
-// Agent/Strategy/Memory abstractions, and Request/Result types.
-//
-// Graph execution Strategy lives in subpackage workflow/flowgraph (imports graph).
-// Callers typically construct a Runtime with WithPrepareBoard for platform-specific
-// board setup and WithDependencies for Factory + Executor when using flowgraph.
-//
-// Deprecated: the workflow package is superseded by the
-// agent + engine + graph runtime introduced in v0.2.x and is scheduled
-// for removal in v0.3.0. The breakdown below documents where each
-// concept moved so callers can migrate incrementally; until v0.3.0
-// every symbol in this package keeps working unchanged.
-//
-// Migration map (workflow → new location):
-//
-//   - workflow.Board / BoardSnapshot / NewBoard / RestoreBoard /
-//     GetTyped / Cloneable / MainChannel
-//     → engine.Board / engine.BoardSnapshot / engine.NewBoard /
-//     engine.RestoreBoard / engine.GetTyped / engine.Cloneable /
-//     engine.MainChannel (re-exported by sdk/graph for graph callers).
-//
-//   - workflow.Runtime / NewRuntime / RuntimeOption /
-//     WithMemoryFactory / WithPrepareBoard / WithDependencies
-//     → sdk/agent: agent.Agent + agent.Run.
-//     The Runtime "prepare board → strategy.Build → run → finish"
-//     pipeline is folded into agent.Run; per-platform board prep
-//     becomes an agent.Seeder.
-//
-//   - workflow.Agent / NewAgent / AgentOption / AgentCard / Skill /
-//     AgentCapabilities
-//     → sdk/agent: agent.Agent (interface), agent.New (constructor),
-//     agent.Card (descriptor). Skills are agent.Decider + agent.Tool
-//     wiring on the agent value.
-//
-//   - workflow.Strategy / Runnable / StrategyCapabilities /
-//     Dependencies / SetDep / GetDep / NewDependencies
-//     → sdk/agent.Decider for the runtime selection logic;
-//     graph/runner.Runner replaces the Build/Runnable split for graph
-//     strategies. Dependency wiring becomes constructor arguments on
-//     the concrete factory (e.g. graph/node/llmnode.Deps).
-//
-//   - workflow.Request / RequestConfig / NewTextRequest / MessageText
-//     → sdk/agent.Request and direct use of model.Message helpers
-//     (model.NewTextMessage, msg.Text()) — there is no longer a
-//     separate "request text" projection.
-//
-//   - workflow.Result / TaskStatus / Artifact
-//     → sdk/agent.Result + sdk/agent.Disposition (typed status).
-//     Artifact slots are now first-class fields on agent.Result.
-//
-//   - workflow.Memory / MemorySession / MemoryFactory / BaseSession /
-//     ContextAssembler / IncrementalSaver
-//     → sdk/agent.Observer (lifecycle hooks) +
-//     sdk/agent.Seeder (initial board state). History persistence is
-//     no longer a runtime concern; persist agent.Result downstream.
-//
-//   - workflow.RunOption / WithHistory / WithStreamCallback /
-//     WithMaxIterations / WithBoard / ApplyRunOpts / RunConfig
-//     → executor.RunOption (graph-level) + agent.RunOption
-//     (agent-level). Streaming moves to engine.Host.Publisher;
-//     subscribers register at the host or via event.Bus directly.
-//
-//   - workflow.StreamEvent / StreamCallback
-//     → event.Envelope + event.Bus. Nodes emit through
-//     graph.StreamPublisher (handed via ExecutionContext); aliases
-//     remain in graph/deprecated.go for one minor release.
-//
-//   - workflow.Task / TaskManager
-//     → sdk/agent.Run (per-invocation handle).
-//     There is no replacement for the global TaskManager; orchestration
-//     of multiple agent runs is the host application's concern.
-//
-// Until v0.3.0 the agent, engine and graph packages are the sanctioned
-// way to build new code; existing workflow callers continue to compile
-// against the legacy API but will see staticcheck SA1019 warnings.
-package workflow
diff --git a/sdk/workflow/helpers.go b/sdk/workflow/helpers.go
deleted file mode 100644
--- a/sdk/workflow/helpers.go
+++ /dev/null
@@ -1,19 +0,0 @@
-package workflow
-
-import "github.com/GizClaw/flowcraft/sdk/model"
-
-// NewTextRequest builds a Request whose Message is a single user text turn.
-func NewTextRequest(text string) *Request {
-	return &Request{
-		Message: model.NewTextMessage(model.RoleUser, text),
-		Inputs:  make(map[string]any),
-	}
-}
-
-// MessageText returns the plain text content of a user message, or "".
-func MessageText(m model.Message) string {
-	if m.Role != model.RoleUser {
-		return ""
-	}
-	return m.Content()
-}
diff --git a/sdk/workflow/keys.go b/sdk/workflow/keys.go
deleted file mode 100644
--- a/sdk/workflow/keys.go
+++ /dev/null
@@ -1,15 +0,0 @@
-package workflow
-
-// Board variable keys for the workflow/runtime layer.
-const (
-	VarQuery            = "query"
-	VarAnswer           = "answer"
-	VarMessages         = "messages"
-	VarRunID            = "__run_id"
-	VarStartTime        = "__start_time"
-	VarInternalUsage    = "__usage"
-	VarInterruptedNode  = "__interrupted_node"
-	VarOutputSchema     = "__output_schema"
-	VarPrevMessageCount = "__prev_message_count"
-	VarSummaryIndex     = "__summary_index"
-)
diff --git a/sdk/workflow/memory.go b/sdk/workflow/memory.go
deleted file mode 100644
--- a/sdk/workflow/memory.go
+++ /dev/null
@@ -1,50 +0,0 @@
-package workflow
-
-import (
-	"context"
-
-	"github.com/GizClaw/flowcraft/sdk/model"
-)
-
-// Memory provides per-agent session memory.
-type Memory interface {
-	Session(ctx context.Context, contextID string) (MemorySession, error)
-}
-
-// MemorySession is one Run's memory lifecycle (Load → Vars → Save → Close).
-// All methods accept a context.Context to support timeout and cancellation
-// for implementations backed by databases or network services.
-type MemorySession interface {
-	Load(ctx context.Context) ([]model.Message, error)
-	Vars(ctx context.Context) (map[string]any, error)
-	Save(ctx context.Context, messages []model.Message) error
-	Close(ctx context.Context, runErr error) error
-}
-
-// ContextAssembler is an optional interface that a MemorySession may implement.
-// When present, Runtime calls Assemble instead of Load to obtain history messages.
-// This allows implementations to perform custom context assembly (e.g. RAG,
-// summarization, sliding window) based on the current request.
-//
-// The returned messages should NOT include req.Message; the runtime appends it.
-type ContextAssembler interface {
-	Assemble(ctx context.Context, req *Request) ([]model.Message, error)
-}
-
-// IncrementalSaver is an optional interface that a MemorySession may implement.
-// When present, Runtime calls Append with only the newly produced messages
-// instead of calling Save with the full message history.
-type IncrementalSaver interface {
-	Append(ctx context.Context, newMessages []model.Message) error
-}
-
-// MemoryFactory creates a Memory for an agent.
-type MemoryFactory func(ctx context.Context, agent Agent) (Memory, error)
-
-// BaseSession is a no-op MemorySession for tests or disabled memory.
-type BaseSession struct{}
-
-func (BaseSession) Load(context.Context) ([]model.Message, error) { return nil, nil }
-func (BaseSession) Vars(context.Context) (map[string]any, error)  { return nil, nil }
-func (BaseSession) Save(context.Context, []model.Message) error   { return nil }
-func (BaseSession) Close(context.Context, error) error            { return nil }
diff --git a/sdk/workflow/option.go b/sdk/workflow/option.go
deleted file mode 100644
--- a/sdk/workflow/option.go
+++ /dev/null
@@ -1,79 +0,0 @@
-package workflow
-
-import (
-	"context"
-
-	"github.com/GizClaw/flowcraft/sdk/model"
-)
-
-// StreamEvent carries a streaming event emitted by a node during execution.
-type StreamEvent struct {
-	Type    string `json:"type"`
-	NodeID  string `json:"node_id"`
-	Payload any    `json:"payload,omitempty"`
-}
-
-// StreamCallback receives streaming events during execution.
-type StreamCallback func(event StreamEvent)
-
-// RuntimeOption configures NewRuntime.
-type RuntimeOption func(*runtime)
-
-// WithMemoryFactory sets the MemoryFactory used by openSession.
-func WithMemoryFactory(f MemoryFactory) RuntimeOption {
-	return func(rt *runtime) { rt.memoryFactory = f }
-}
-
-// WithPrepareBoard sets a custom board preparation (platform graph vars, schema, etc.).
-// When nil, prepareBoard uses the generic Request + session + history path only.
-func WithPrepareBoard(fn func(ctx context.Context, agent Agent, req *Request, session MemorySession, opts []RunOption) (*Board, error)) RuntimeOption {
-	return func(rt *runtime) { rt.prepareBoardFn = fn }
-}
-
-// WithDependencies supplies Strategy.Build with factories and executors (flowgraph uses these).
-func WithDependencies(d *Dependencies) RuntimeOption {
-	return func(rt *runtime) { rt.deps = d }
-}
-
-// RunOption configures a single Run call.
-type RunOption func(*RunConfig)
-
-// RunConfig holds resolved run-level settings. Exported so that Strategy
-// implementations (e.g. flowgraph) can read stream callback, max iterations, etc.
-type RunConfig struct {
-	History        []model.Message
-	Board          *Board
-	StreamCallback StreamCallback
-	MaxIterations  int
-}
-
-// ApplyRunOpts resolves a slice of RunOption into a RunConfig.
-func ApplyRunOpts(opts []RunOption) RunConfig {
-	var c RunConfig
-	for _, o := range opts {
-		o(&c)
-	}
-	return c
-}
-
-// WithHistory injects message history into the main channel when no Memory session is used.
-// Ignored when a non-nil Memory session is opened (MemoryFactory path wins).
-func WithHistory(msgs []model.Message) RunOption {
-	return func(c *RunConfig) { c.History = msgs }
-}
-
-// WithStreamCallback sets a streaming event callback for the execution.
-func WithStreamCallback(cb StreamCallback) RunOption {
-	return func(c *RunConfig) { c.StreamCallback = cb }
-}
-
-// WithMaxIterations caps the number of graph execution steps.
-func WithMaxIterations(n int) RunOption {
-	return func(c *RunConfig) { c.MaxIterations = n }
-}
-
-// WithBoard injects a pre-built Board, skipping the normal prepareBoard phase.
-// Used for resume-from-snapshot flows.
-func WithBoard(b *Board) RunOption {
-	return func(c *RunConfig) { c.Board = b }
-}
diff --git a/sdk/workflow/request.go b/sdk/workflow/request.go
deleted file mode 100644
--- a/sdk/workflow/request.go
+++ /dev/null
@@ -1,20 +0,0 @@
-package workflow
-
-import "github.com/GizClaw/flowcraft/sdk/model"
-
-// RequestConfig holds optional request-level settings (A2A alignment, etc.).
-type RequestConfig struct {
-	AcceptedOutputModes []string `json:"accepted_output_modes,omitempty"`
-}
-
-// Request is one agent turn: user message plus optional inputs and metadata.
-type Request struct {
-	TaskID     string         `json:"task_id,omitempty"`
-	ContextID  string         `json:"context_id,omitempty"`
-	RuntimeID  string         `json:"runtime_id,omitempty"`
-	RunID      string         `json:"run_id,omitempty"`
-	Message    model.Message  `json:"message"`
-	Inputs     map[string]any `json:"inputs,omitempty"`
-	Config     *RequestConfig `json:"config,omitempty"`
-	Extensions map[string]any `json:"extensions,omitempty"`
-}
diff --git a/sdk/workflow/result.go b/sdk/workflow/result.go
deleted file mode 100644
--- a/sdk/workflow/result.go
+++ /dev/null
@@ -1,51 +0,0 @@
-package workflow
-
-import "github.com/GizClaw/flowcraft/sdk/model"
-
-// TaskStatus is the terminal or intermediate status of a run.
-type TaskStatus string
-
-const (
-	StatusCompleted     TaskStatus = "completed"
-	StatusWorking       TaskStatus = "working"
-	StatusFailed        TaskStatus = "failed"
-	StatusInputRequired TaskStatus = "input_required"
-	StatusCanceled      TaskStatus = "canceled"
-	StatusInterrupted   TaskStatus = "interrupted"
-	StatusAborted       TaskStatus = "aborted"
-)
-
-// Artifact is a named bundle of parts produced during a run.
-type Artifact struct {
-	Name  string       `json:"name"`
-	Parts []model.Part `json:"parts,omitempty"`
-}
-
-// Result is returned by Runtime.Run after execution and finish logic.
-type Result struct {
-	TaskID    string           `json:"task_id,omitempty"`
-	Status    TaskStatus       `json:"status"`
-	Messages  []model.Message  `json:"messages,omitempty"`
-	Artifacts []Artifact       `json:"artifacts,omitempty"`
-	Usage     model.TokenUsage `json:"usage"`
-	State     map[string]any   `json:"state,omitempty"`
-	Err       error            `json:"-"`
-	LastBoard *Board           `json:"-"`
-}
-
-// Text returns the last assistant text message in Messages, or "".
-func (r *Result) Text() string {
-	if r == nil {
-		return ""
-	}
-	for i := len(r.Messages) - 1; i >= 0; i-- {
-		if r.Messages[i].Role != model.RoleAssistant {
-			continue
-		}
-		t := r.Messages[i].Content()
-		if t != "" {
-			return t
-		}
-	}
-	return ""
-}
diff --git a/sdk/workflow/run.go b/sdk/workflow/run.go
deleted file mode 100644
--- a/sdk/workflow/run.go
+++ /dev/null
@@ -1,230 +0,0 @@
-package workflow
-
-import (
-	"context"
-	"crypto/rand"
-	"encoding/hex"
-	"fmt"
-	"time"
-
-	"github.com/GizClaw/flowcraft/sdk/errdefs"
-	"github.com/GizClaw/flowcraft/sdk/model"
-)
-
-func (rt *runtime) run(ctx context.Context, agent Agent, req *Request, opts []RunOption) (*Result, error) {
-	if req == nil {
-		return nil, fmt.Errorf("workflow: nil request")
-	}
-	if agent == nil {
-		return nil, fmt.Errorf("workflow: nil agent")
-	}
-
-	session, err := rt.openSession(ctx, agent, req.ContextID)
-	if err != nil {
-		return nil, err
-	}
-	var execErr error
-	if session != nil {
-		defer func() {
-			_ = session.Close(ctx, execErr)
-		}()
-	}
-
-	rc := ApplyRunOpts(opts)
-
-	var board *Board
-	if rc.Board != nil {
-		board = rc.Board
-	} else if rt.prepareBoardFn != nil {
-		board, err = rt.prepareBoardFn(ctx, agent, req, session, opts)
-	} else {
-		board, err = prepareBoard(ctx, req, session, opts)
-	}
-	if err != nil {
-		execErr = err
-		return nil, err
-	}
-
-	deps := rt.deps
-	if deps == nil {
-		deps = NewDependencies()
-	}
-	runnable, err := agent.Strategy().Build(ctx, deps)
-	if err != nil {
-		execErr = err
-		return nil, err
-	}
-
-	board, execErr = runnable.Execute(ctx, board, req, opts...)
-	return finishRun(ctx, agent, req, board, session, execErr)
-}
-
-func (rt *runtime) openSession(ctx context.Context, agent Agent, contextID string) (MemorySession, error) {
-	if rt.memoryFactory == nil || contextID == "" {
-		return nil, nil
-	}
-	mem, err := rt.memoryFactory(ctx, agent)
-	if err != nil {
-		return nil, err
-	}
-	if mem == nil {
-		return nil, nil
-	}
-	return mem.Session(ctx, contextID)
-}
-
-func prepareBoard(ctx context.Context, req *Request, session MemorySession, opts []RunOption) (*Board, error) {
-	board := NewBoard()
-	rc := ApplyRunOpts(opts)
-
-	prev := 0
-	if session != nil {
-		var msgs []model.Message
-		var err error
-		if assembler, ok := session.(ContextAssembler); ok {
-			msgs, err = assembler.Assemble(ctx, req)
-		} else {
-			msgs, err = session.Load(ctx)
-		}
-		if err != nil {
-			return nil, fmt.Errorf("memory load: %w", err)
-		}
-		prev = len(msgs)
-		cp := make([]model.Message, len(msgs))
-		copy(cp, msgs)
-		board.SetChannel(MainChannel, cp)
-		sessionVars, err := session.Vars(ctx)
-		if err != nil {
-			return nil, fmt.Errorf("memory vars: %w", err)
-		}
-		for k, v := range sessionVars {
-			board.SetVar(k, v)
-		}
-	} else if len(rc.History) > 0 {
-		cp := make([]model.Message, len(rc.History))
-		copy(cp, rc.History)
-		board.SetChannel(MainChannel, cp)
-		prev = len(cp)
-	} else {
-		board.SetChannel(MainChannel, []model.Message{})
-	}
-
-	board.AppendChannelMessage(MainChannel, req.Message)
-
-	for k, v := range req.Inputs {
-		board.SetVar(k, v)
-	}
-
-	q := MessageText(req.Message)
-	if q != "" {
-		board.SetVar(VarQuery, q)
-	}
-	if req.RuntimeID != "" {
-		board.SetVar("runtime_id", req.RuntimeID)
-	}
-	runID := req.RunID
-	if runID == "" {
-		runID = genRunID()
-	}
-	board.SetVar(VarRunID, runID)
-
-	board.SetVar(VarPrevMessageCount, prev)
-
-	main := board.Channel(MainChannel)
-	board.SetVar(VarMessages, append([]model.Message(nil), main...))
-
-	return board, nil
-}
-
-func genRunID() string {
-	b := make([]byte, 8)
-	if _, err := rand.Read(b); err != nil {
-		return fmt.Sprintf("run-%d", time.Now().UnixNano())
-	}
-	return "run-" + hex.EncodeToString(b)
-}
-
-// finishRun builds the Result from execution outcome.
-//
-// Error semantics (W-5 fix): Run()'s returned error is reserved for
-// infrastructure failures (e.g. memory save). All business terminal states
-// (interrupted / canceled / aborted / failed) are expressed solely via
-// Result.Status + Result.Err; Run() returns (res, nil) for these.
-func finishRun(ctx context.Context, agent Agent, req *Request, board *Board, session MemorySession, execErr error) (*Result, error) {
-	if board == nil {
-		board = NewBoard()
-	}
-	res := &Result{
-		TaskID:    req.TaskID,
-		State:     make(map[string]any),
-		LastBoard: board,
-	}
-
-	runID, _ := board.GetVar(VarRunID)
-	res.State["run_id"] = runID
-
-	if execErr != nil {
-		res.Err = execErr
-		switch {
-		case errdefs.IsInterrupted(execErr):
-			res.Status = StatusInterrupted
-			res.State["board"] = board.Snapshot()
-			if nodeID, ok := board.GetVar(VarInterruptedNode); ok {
-				res.State["interrupted_node"] = nodeID
-			}
-		case errdefs.Is(execErr, context.Canceled),
-			errdefs.Is(execErr, context.DeadlineExceeded):
-			res.Status = StatusCanceled
-		case errdefs.IsAborted(execErr):
-			res.Status = StatusAborted
-		default:
-			res.Status = StatusFailed
-		}
-		return res, nil
-	}
-
-	prev := 0
-	if pc, ok := board.GetVar(VarPrevMessageCount); ok {
-		switch v := pc.(type) {
-		case int:
-			prev = v
-		case int64:
-			prev = int(v)
-		}
-	}
-
-	main := board.Channel(MainChannel)
-	if session != nil {
-		if inc, ok := session.(IncrementalSaver); ok {
-			newMsgs := main
-			if prev > 0 && prev <= len(main) {
-				newMsgs = main[prev:]
-			}
-			if err := inc.Append(ctx, newMsgs); err != nil {
-				return nil, fmt.Errorf("memory append: %w", err)
-			}
-		} else {
-			if err := session.Save(ctx, main); err != nil {
-				return nil, fmt.Errorf("memory save: %w", err)
-			}
-		}
-	}
-
-	if prev > 0 && prev <= len(main) {
-		res.Messages = append([]model.Message(nil), main[prev:]...)
-	} else {
-		res.Messages = append([]model.Message(nil), main...)
-	}
-
-	ak := agent.Strategy().Capabilities().AnswerVar()
-	if v, ok := board.GetVar(ak); ok {
-		res.State["answer"] = v
-	}
-	if u, ok := board.GetVar(VarInternalUsage); ok {
-		if usage, ok := u.(model.TokenUsage); ok {
-			res.Usage = usage
-		}
-	}
-	res.Status = StatusCompleted
-	return res, nil
-}
diff --git a/sdk/workflow/runtime.go b/sdk/workflow/runtime.go
deleted file mode 100644
--- a/sdk/workflow/runtime.go
+++ /dev/null
@@ -1,28 +0,0 @@
-package workflow
-
-import "context"
-
-// Runtime executes one agent Request using Strategy + optional Memory.
-type Runtime interface {
-	Run(ctx context.Context, agent Agent, req *Request, opts ...RunOption) (*Result, error)
-}
-
-type runtime struct {
-	memoryFactory  MemoryFactory
-	deps           *Dependencies
-	prepareBoardFn func(ctx context.Context, agent Agent, req *Request, session MemorySession, opts []RunOption) (*Board, error)
-}
-
-// NewRuntime constructs a Runtime with optional MemoryFactory and board preparation hook.
-func NewRuntime(opts ...RuntimeOption) Runtime {
-	rt := &runtime{}
-	for _, o := range opts {
-		o(rt)
-	}
-	return rt
-}
-
-// Run implements Runtime.
-func (rt *runtime) Run(ctx context.Context, agent Agent, req *Request, opts ...RunOption) (*Result, error) {
-	return rt.run(ctx, agent, req, opts)
-}
diff --git a/sdk/workflow/strategy.go b/sdk/workflow/strategy.go
deleted file mode 100644
--- a/sdk/workflow/strategy.go
+++ /dev/null
@@ -1,76 +0,0 @@
-package workflow
-
-import (
-	"context"
-	"fmt"
-)
-
-// StrategyCapabilities describes how Runtime reads outputs from the Board.
-type StrategyCapabilities struct {
-	AnswerKey string
-}
-
-// AnswerVar returns the board var key for the final answer, defaulting to "answer".
-func (c StrategyCapabilities) AnswerVar() string {
-	if c.AnswerKey != "" {
-		return c.AnswerKey
-	}
-	return VarAnswer
-}
-
-// Strategy describes how to execute one turn (graph, script, remote, …).
-type Strategy interface {
-	Kind() string
-	Build(ctx context.Context, deps *Dependencies) (Runnable, error)
-	Capabilities() StrategyCapabilities
-}
-
-// Runnable is the compiled execution unit produced by Strategy.Build.
-type Runnable interface {
-	Execute(ctx context.Context, board *Board, req *Request, opts ...RunOption) (*Board, error)
-}
-
-// Dependencies is a type-safe container for resources available to Strategy.Build.
-// Each Strategy defines its own key constants and retrieves values via GetDep.
-type Dependencies struct {
-	store map[string]any
-}
-
-// NewDependencies creates an empty Dependencies container.
-func NewDependencies() *Dependencies {
-	return &Dependencies{store: make(map[string]any)}
-}
-
-// Set stores a dependency value under the given key.
-func (d *Dependencies) Set(key string, val any) {
-	if d.store == nil {
-		d.store = make(map[string]any)
-	}
-	d.store[key] = val
-}
-
-// SetDep stores a typed dependency value. The type parameter is for documentation
-// only at the call site; retrieval is type-checked by GetDep.
-func SetDep[T any](d *Dependencies, key string, val T) {
-	d.Set(key, val)
-}
-
-// GetDep retrieves a typed dependency. It returns an error if the key is missing
-// or the stored value does not match the requested type.
-func GetDep[T any](d *Dependencies, key string) (T, error) {
-	if d == nil || d.store == nil {
-		var zero T
-		return zero, fmt.Errorf("dependency %q not found (nil container)", key)
-	}
-	raw, ok := d.store[key]
-	if !ok {
-		var zero T
-		return zero, fmt.Errorf("dependency %q not found", key)
-	}
-	val, ok := raw.(T)
-	if !ok {
-		var zero T
-		return zero, fmt.Errorf("dependency %q: want %T, got %T", key, zero, raw)
-	}
-	return val, nil
-}
diff --git a/sdk/workflow/task_manager.go b/sdk/workflow/task_manager.go
deleted file mode 100644
--- a/sdk/workflow/task_manager.go
+++ /dev/null
@@ -1,19 +0,0 @@
-package workflow
-
-import "time"
-
-// Task represents a tracked unit of work managed by a TaskManager.
-type Task struct {
-	ID        string     `json:"id"`
-	Status    TaskStatus `json:"status"`
-	CreatedAt time.Time  `json:"created_at"`
-	Result    *Result    `json:"result,omitempty"`
-}
-
-// TaskManager is an optional capability for run/task orchestration (list/cancel).
-// Default Runtime implementations may return a no-op or nil adapter.
-type TaskManager interface {
-	GetTask(id string) (*Task, error)
-	CancelTask(id string) error
-	ListTasks() ([]*Task, error)
-}
diff --git a/sdkx/knowledge/watcher/watcher.go b/sdkx/knowledge/watcher/watcher.go
deleted file mode 100644
--- a/sdkx/knowledge/watcher/watcher.go
+++ /dev/null
@@ -1,158 +0,0 @@
-// Package watcher provides an fsnotify-backed knowledge.ChangeNotifier
-// adapter.
-//
-// Pure-fs notification was deliberately split from the sdk core to keep
-// sdk/knowledge dependency-free; reuse the SDK's Reloader to compose:
-//
-//	notifier, _ := watcher.New(ctx, store)
-//	r := knowledge.NewReloader(store, notifier, knowledge.ReloaderOptions{})
-//	go r.Run(ctx)
-//
-// Deprecated: Removed in sdkx/v0.3.0 (the release that follows sdk/v0.3.0).
-//
-// Every type this package consumes from sdk/knowledge has already been
-// marked Deprecated and is scheduled for removal in sdk/v0.3.0:
-//
-//	*knowledge.FSStore         (use factory.NewLocal)
-//	knowledge.ChangeNotifier   (use EventNotifier — typed ChangeEvent stream)
-//	knowledge.NewReloader      (use NewEventReloader)
-//
-// Once those go away this adapter cannot compile against the new sdk,
-// so the package will be dropped entirely. The v0.3.0 replacement is
-// architecturally different — fsnotify events get *decoded* into typed
-// knowledge.ChangeEvent values (DatasetID / DocName / Kind) instead of
-// emitting opaque struct{} ticks — which means no in-place upgrade is
-// possible. Plan to rewrite call sites against:
-//
-//	svc := factory.NewLocal(ws, ...)            // sdk/knowledge/factory
-//	notifier := <a typed EventNotifier impl>    // sdk/knowledge or your own
-//	r := knowledge.NewEventReloader(svc, notifier, knowledge.ReloaderOptions{})
-//	go r.Run(ctx)
-//
-// A typed fsnotify-backed EventNotifier is on the roadmap for sdkx
-// post-v0.3.0; until it lands, this package keeps working against
-// sdk/v0.2.x consumers and is the recommended bridge for them.
-package watcher
-
-import (
-	"context"
-	"errors"
-	"os"
-	"path/filepath"
-	"sync"
-
-	"github.com/GizClaw/flowcraft/sdk/knowledge"
-	"github.com/GizClaw/flowcraft/sdk/telemetry"
-
-	"github.com/fsnotify/fsnotify"
-	otellog "go.opentelemetry.io/otel/log"
-)
-
-// Notifier wraps fsnotify.Watcher to satisfy knowledge.ChangeNotifier.
-//
-// Deprecated: see package-level deprecation note. Removed in sdkx/v0.3.0.
-type Notifier struct {
-	store     *knowledge.FSStore
-	watcher   *fsnotify.Watcher
-	out       chan struct{}
-	closed    chan struct{}
-	closeOnce sync.Once
-	wg        sync.WaitGroup
-	rootDir   string
-}
-
-// New constructs a Notifier for the given knowledge store. Returns nil
-// without error when the underlying workspace doesn't expose a filesystem
-// root (e.g. in-memory workspace).
-//
-// Deprecated: see package-level deprecation note. Removed in sdkx/v0.3.0.
-func New(ctx context.Context, store *knowledge.FSStore) (*Notifier, error) {
-	if store == nil {
-		return nil, errors.New("knowledge/watcher: store is nil")
-	}
-	root := store.WorkspaceRoot()
-	if root == "" {
-		telemetry.Info(ctx, "knowledge: workspace does not support fsnotify watching")
-		return nil, nil
-	}
-	knowledgeDir := filepath.Join(root, store.Prefix())
-	if _, err := os.Stat(knowledgeDir); os.IsNotExist(err) {
-		if err := os.MkdirAll(knowledgeDir, 0o755); err != nil {
-			return nil, err
-		}
-	}
-	fw, err := fsnotify.NewWatcher()
-	if err != nil {
-		return nil, err
-	}
-	if err := fw.Add(knowledgeDir); err != nil {
-		_ = fw.Close()
-		return nil, err
-	}
-	if entries, err := os.ReadDir(knowledgeDir); err == nil {
-		for _, entry := range entries {
-			if entry.IsDir() {
-				_ = fw.Add(filepath.Join(knowledgeDir, entry.Name()))
-			}
-		}
-	}
-	n := &Notifier{
-		store:   store,
-		watcher: fw,
-		out:     make(chan struct{}, 1),
-		closed:  make(chan struct{}),
-		rootDir: knowledgeDir,
-	}
-	n.wg.Add(1)
-	go n.loop(ctx)
-	telemetry.Info(ctx, "knowledge: watching for changes", otellog.String("dir", knowledgeDir))
-	return n, nil
-}
-
-// Events implements knowledge.ChangeNotifier.
-func (n *Notifier) Events() <-chan struct{} { return n.out }
-
-// Close implements knowledge.ChangeNotifier.
-func (n *Notifier) Close() error {
-	n.closeOnce.Do(func() {
-		close(n.closed)
-		_ = n.watcher.Close()
-	})
-	n.wg.Wait()
-	return nil
-}
-
-func (n *Notifier) loop(ctx context.Context) {
-	defer n.wg.Done()
-	defer close(n.out)
-	for {
-		select {
-		case <-n.closed:
-			return
-		case <-ctx.Done():
-			return
-		case event, ok := <-n.watcher.Events:
-			if !ok {
-				return
-			}
-			if event.Has(fsnotify.Create) || event.Has(fsnotify.Write) ||
-				event.Has(fsnotify.Remove) || event.Has(fsnotify.Rename) {
-				// Watch newly-created subdirectories so future events are seen.
-				if event.Has(fsnotify.Create) {
-					if info, err := os.Stat(event.Name); err == nil && info.IsDir() {
-						_ = n.watcher.Add(event.Name)
-					}
-				}
-				select {
-				case n.out <- struct{}{}:
-				default:
-				}
-			}
-		case err, ok := <-n.watcher.Errors:
-			if !ok {
-				return
-			}
-			telemetry.Warn(ctx, "knowledge: watcher error", otellog.String(telemetry.AttrErrorMessage, err.Error()))
-		}
-	}
-}
diff --git a/sdkx/tool/history/tools.go b/sdkx/tool/history/tools.go
--- a/sdkx/tool/history/tools.go
+++ b/sdkx/tool/history/tools.go
@@ -1,29 +1,301 @@
 package history
 
 import (
+	"context"
+	"encoding/json"
+	"fmt"
+	"strings"
+
+	"github.com/GizClaw/flowcraft/sdk/errdefs"
 	sdkhistory "github.com/GizClaw/flowcraft/sdk/history"
+	"github.com/GizClaw/flowcraft/sdk/model"
 	"github.com/GizClaw/flowcraft/sdk/tool"
+	"github.com/GizClaw/flowcraft/sdk/workspace"
 )
 
 // ToolDeps bundles everything the history_expand / history_compact
 // tools need at registration time. Pass it to [RegisterTools].
 //
-// This is a Go type alias to [sdkhistory.ToolDeps] — instances of
-// either type are interchangeable. At sdk/v0.3.0 this becomes a
-// first-class type definition once the sdk-side helpers are deleted.
+// Coordinator is optional but strongly recommended: when set,
+// history_compact routes Compact / Archive through the per-conversation
+// worker queue, matching the serialization guarantees that
+// [sdkhistory.Coordinator] offers to first-class callers. When
+// Coordinator is nil the tool falls back to ad-hoc helpers, which can
+// race a concurrent [sdkhistory.History.Append] on the same
+// conversation. Callers that already have a [sdkhistory.History] from
+// [sdkhistory.NewCompacted] should always wire it via:
 //
-// See [sdkhistory.ToolDeps] for field semantics.
-type ToolDeps = sdkhistory.ToolDeps
+//	coord, _ := hist.(sdkhistory.Coordinator)
+//	historytool.RegisterTools(registry, historytool.ToolDeps{
+//	    Coordinator:  coord,
+//	    SummaryStore: summaryStore,
+//	    MessageStore: msgStore,
+//	    Workspace:    ws,
+//	    Prefix:       prefix,
+//	    Config:       cfg,
+//	})
+type ToolDeps struct {
+	// Coordinator, when non-nil, makes history_compact go through the
+	// per-conversation queue. Leaving it nil falls back to direct store
+	// mutation and is only safe when no [sdkhistory.History.Append] can
+	// run concurrently on the same conversation.
+	Coordinator sdkhistory.Coordinator
 
-// RegisterTools registers history_expand and history_compact against
-// the supplied [tool.Registry]. The summary index is auto-injected
-// into the LLM system prompt via the workflow.VarSummaryIndex board
-// variable, so a separate history_search tool is not needed.
-//
-// During the v0.2.x → v0.3.0 transition this delegates to
-// [sdkhistory.RegisterTools] because the tool implementation
-// reaches into package-private archive helpers in sdk/history. At
-// sdk/v0.3.0 the implementation relocates into this package.
+	SummaryStore sdkhistory.SummaryStore
+	MessageStore sdkhistory.Store
+	Workspace    workspace.Workspace
+	Prefix       string
+	Config       sdkhistory.DAGConfig
+}
+
+// RegisterTools registers history_expand and history_compact against the
+// supplied [tool.Registry]. The summary index is auto-injected into the
+// LLM system prompt via the agent-level summary-index board variable,
+// so a separate history_search tool is not needed.
 func RegisterTools(registry *tool.Registry, deps ToolDeps) {
-	sdkhistory.RegisterTools(registry, deps)
+	registry.Register(newHistoryExpandTool(deps))
+	registry.RegisterWithScope(newHistoryCompactTool(deps), tool.ScopePlatform)
+}
+
+// --- history_expand ---
+
+type historyExpandTool struct {
+	deps ToolDeps
+}
+
+func newHistoryExpandTool(deps ToolDeps) tool.Tool {
+	return &historyExpandTool{deps: deps}
+}
+
+func (t *historyExpandTool) Definition() model.ToolDefinition {
+	return tool.DefineSchema("history_expand",
+		"Expand a compressed summary to see the original messages or finer-grained summaries it was derived from.",
+		tool.Property("summary_id", "string", "The ID of the summary to expand"),
+		tool.PropertyWithDefault("max_messages", "integer", "Maximum original messages to return", 20),
+	).Required("summary_id").Build()
+}
+
+func (t *historyExpandTool) Execute(ctx context.Context, arguments string) (string, error) {
+	var args struct {
+		SummaryID   string `json:"summary_id"`
+		MaxMessages int    `json:"max_messages"`
+	}
+	args.MaxMessages = 20
+	if err := json.Unmarshal([]byte(arguments), &args); err != nil {
+		return "", fmt.Errorf("history_expand: parse args: %w", err)
+	}
+
+	convID := sdkhistory.ConversationIDFrom(ctx)
+	if convID == "" {
+		return "", errdefs.Validationf("history_expand: no conversation ID in context")
+	}
+
+	if t.deps.SummaryStore == nil {
+		return "", errdefs.NotAvailablef("history_expand: summary store not available")
+	}
+
+	node, err := t.deps.SummaryStore.GetByConvID(ctx, convID, args.SummaryID)
+	if err != nil {
+		return "", fmt.Errorf("history_expand: %w", err)
+	}
+
+	if node.Depth > 0 {
+		var children []*sdkhistory.SummaryNode
+		for _, sid := range node.SourceIDs {
+			child, err := t.deps.SummaryStore.GetByConvID(ctx, convID, sid)
+			if err != nil {
+				continue
+			}
+			children = append(children, child)
+		}
+		return formatChildSummaries(children), nil
+	}
+
+	return t.expandLeaf(ctx, convID, node, args.MaxMessages)
+}
+
+func (t *historyExpandTool) expandLeaf(ctx context.Context, convID string, node *sdkhistory.SummaryNode, maxMsgs int) (string, error) {
+	startSeq := node.EarliestSeq
+	endSeq := node.LatestSeq + 1
+
+	if t.deps.Workspace != nil {
+		archivePrefix := t.deps.Config.Archive.ArchivePrefix
+		if archivePrefix == "" {
+			archivePrefix = "archive"
+		}
+		manifest, err := sdkhistory.LoadManifest(ctx, t.deps.Workspace, t.deps.Prefix, archivePrefix, convID)
+		if err == nil && manifest.HotStartSeq > 0 {
+			var allMsgs []model.Message
+
+			if startSeq < manifest.HotStartSeq {
+				coldEnd := endSeq
+				if coldEnd > manifest.HotStartSeq {
+					coldEnd = manifest.HotStartSeq
+				}
+				coldMsgs, err := sdkhistory.LoadArchivedMessages(ctx, t.deps.Workspace, t.deps.Prefix, archivePrefix, convID, startSeq, coldEnd-1)
+				if err == nil {
+					allMsgs = append(allMsgs, coldMsgs...)
+				}
+			}
+
+			if endSeq > manifest.HotStartSeq {
+				hotStart := startSeq - manifest.HotStartSeq
+				if hotStart < 0 {
+					hotStart = 0
+				}
+				hotEnd := endSeq - manifest.HotStartSeq
+				if rr, ok := t.deps.MessageStore.(sdkhistory.RangeReader); ok {
+					hotMsgs, err := rr.GetMessageRange(ctx, convID, hotStart, hotEnd)
+					if err == nil {
+						allMsgs = append(allMsgs, hotMsgs...)
+					}
+				}
+			}
+
+			if len(allMsgs) > 0 {
+				if len(allMsgs) > maxMsgs {
+					allMsgs = allMsgs[len(allMsgs)-maxMsgs:]
+				}
+				return formatMessages(allMsgs), nil
+			}
+		}
+	}
+
+	if rr, ok := t.deps.MessageStore.(sdkhistory.RangeReader); ok {
+		msgs, err := rr.GetMessageRange(ctx, convID, startSeq, endSeq)
+		if err == nil {
+			if len(msgs) > maxMsgs {
+				msgs = msgs[len(msgs)-maxMsgs:]
+			}
+			return formatMessages(msgs), nil
+		}
+	}
+
+	msgs, err := t.deps.MessageStore.GetMessages(ctx, convID)
+	if err != nil {
+		return "", fmt.Errorf("history_expand: get messages: %w", err)
+	}
+	if startSeq < len(msgs) {
+		end := endSeq
+		if end > len(msgs) {
+			end = len(msgs)
+		}
+		msgs = msgs[startSeq:end]
+	}
+	if len(msgs) > maxMsgs {
+		msgs = msgs[len(msgs)-maxMsgs:]
+	}
+	return formatMessages(msgs), nil
+}
+
+func formatMessages(msgs []model.Message) string {
+	var b strings.Builder
+	for _, msg := range msgs {
+		text := msg.Content()
+		if text != "" {
+			fmt.Fprintf(&b, "%s: %s\n\n", msg.Role, text)
+		}
+	}
+	return b.String()
+}
+
+func formatChildSummaries(children []*sdkhistory.SummaryNode) string {
+	var b strings.Builder
+	for _, c := range children {
+		fmt.Fprintf(&b, "[d%d seq %d-%d] %s\n", c.Depth, c.EarliestSeq, c.LatestSeq, c.Content)
+		if c.ExpandHint != "" {
+			b.WriteString(c.ExpandHint + "\n")
+		}
+		b.WriteString("\n")
+	}
+	return b.String()
+}
+
+// --- history_compact ---
+
+type historyCompactTool struct {
+	deps ToolDeps
+}
+
+func newHistoryCompactTool(deps ToolDeps) tool.Tool {
+	return &historyCompactTool{deps: deps}
+}
+
+func (t *historyCompactTool) Definition() model.ToolDefinition {
+	return tool.DefineSchema("history_compact",
+		"Manually trigger compact and archive for a conversation's memory DAG.",
+		tool.Property("conversation_id", "string", "The conversation ID to compact/archive"),
+		tool.PropertyWithDefault("compact", "boolean", "Run DAG compact", true),
+		tool.PropertyWithDefault("archive", "boolean", "Run message archiving", true),
+	).Required("conversation_id").Build()
+}
+
+func (t *historyCompactTool) Execute(ctx context.Context, arguments string) (string, error) {
+	var args struct {
+		ConversationID string `json:"conversation_id"`
+		Compact        *bool  `json:"compact"`
+		Archive        *bool  `json:"archive"`
+	}
+	if err := json.Unmarshal([]byte(arguments), &args); err != nil {
+		return "", fmt.Errorf("history_compact: parse args: %w", err)
+	}
+
+	doCompact := args.Compact == nil || *args.Compact
+	doArchive := args.Archive == nil || *args.Archive
+
+	type resultJSON struct {
+		CompactResult *sdkhistory.CompactResult `json:"compact_result,omitempty"`
+		ArchiveResult *sdkhistory.ArchiveResult `json:"archive_result,omitempty"`
+	}
+	var res resultJSON
+
+	// Preferred path: a Coordinator is wired, every operation observes
+	// per-conversation serialization, and we never reach into the raw
+	// stores from the tool.
+	if t.deps.Coordinator != nil {
+		if doCompact {
+			cr, err := t.deps.Coordinator.Compact(ctx, args.ConversationID)
+			if err != nil {
+				return "", fmt.Errorf("history_compact: compact: %w", err)
+			}
+			res.CompactResult = &cr
+		}
+		if doArchive {
+			ar, err := t.deps.Coordinator.Archive(ctx, args.ConversationID)
+			if err != nil {
+				return "", fmt.Errorf("history_compact: archive: %w", err)
+			}
+			res.ArchiveResult = &ar
+		}
+		data, _ := json.Marshal(res)
+		return string(data), nil
+	}
+
+	// Fallback path (no Coordinator wired): we go straight to the
+	// stores, which means a concurrent Append on the same conversation
+	// can race the trim step inside archive. Callers that own a
+	// [sdkhistory.History] from [sdkhistory.NewCompacted] should always
+	// populate [ToolDeps.Coordinator] to avoid this branch.
+	cfg := t.deps.Config
+	if doCompact && t.deps.SummaryStore != nil {
+		// LLM/TokenCounter are not needed by Compact's structural pass
+		// (which only re-shapes existing summaries); pass nil and let
+		// NewSummaryDAG default the counter for safety.
+		dag := sdkhistory.NewSummaryDAG(t.deps.SummaryStore, t.deps.MessageStore, nil, cfg, nil)
+		cr, err := dag.Compact(ctx, args.ConversationID)
+		if err != nil {
+			return "", fmt.Errorf("history_compact: compact: %w", err)
+		}
+		res.CompactResult = &cr
+	}
+	if doArchive && t.deps.Workspace != nil && t.deps.MessageStore != nil {
+		ar, err := sdkhistory.Archive(ctx, t.deps.Workspace, t.deps.MessageStore, t.deps.Prefix, args.ConversationID, cfg.Archive)
+		if err != nil {
+			return "", fmt.Errorf("history_compact: archive: %w", err)
+		}
+		res.ArchiveResult = &ar
+	}
+
+	data, _ := json.Marshal(res)
+	return string(data), nil
 }
diff --git a/sdkx/tool/kanban/tools.go b/sdkx/tool/kanban/tools.go
--- a/sdkx/tool/kanban/tools.go
+++ b/sdkx/tool/kanban/tools.go
@@ -157,24 +157,26 @@ func (t *TaskContextTool) resolve(ctx context.Context) *sdkkanban.Kanban {
 	return KanbanFrom(ctx)
 }
 
+// ctxKey is the package-private type backing the Kanban context value;
+// using a private type guarantees no external package can collide with
+// our key by accident.
+type ctxKey int
+
+const ctxKeyKanban ctxKey = iota
+
 // WithKanban attaches a [*sdkkanban.Kanban] instance to ctx so the
 // LLM-facing [SubmitTool] / [TaskContextTool] can resolve it without
 // a struct field. Used by hosts that wire tools into a registry
 // before the Kanban instance is constructed.
-//
-// The implementation re-exports [sdkkanban.WithKanban] so contexts
-// installed by either package interoperate during the v0.2.x →
-// v0.3.0 transition. After sdk/v0.3.0 the sdk-side helper is
-// deleted and this function will hold the canonical implementation.
 func WithKanban(ctx context.Context, k *sdkkanban.Kanban) context.Context {
-	return sdkkanban.WithKanban(ctx, k)
+	return context.WithValue(ctx, ctxKeyKanban, k)
 }
 
 // KanbanFrom retrieves the [*sdkkanban.Kanban] instance previously
-// installed by [WithKanban] (or by [sdkkanban.WithKanban]), or nil
-// when absent.
+// installed by [WithKanban], or nil when absent.
 func KanbanFrom(ctx context.Context) *sdkkanban.Kanban {
-	return sdkkanban.KanbanFrom(ctx)
+	k, _ := ctx.Value(ctxKeyKanban).(*sdkkanban.Kanban)
+	return k
 }
 
 // Compile-time interface check.
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
