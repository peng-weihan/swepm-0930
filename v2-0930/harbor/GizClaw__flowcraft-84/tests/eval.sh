#!/bin/bash
set -uxo pipefail

cd /testbed
# Keep local test servers from being routed through host proxy settings.
export NO_PROXY="localhost,127.0.0.1,0.0.0.0,::1${NO_PROXY:+,$NO_PROXY}"
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1${no_proxy:+,$no_proxy}"
echo "OMNIGRIL_LOCAL_NO_PROXY_ADDED=1"


BASE_COMMIT="5c4e7b408bd2fb4f23d40b41110469bfad2c0256"

RUNNABLE_TEST_FILES=(
  sdk/engine/board_test.go
  sdk/errdefs/http_test.go
  sdk/graph/compile_test.go
  sdk/graph/node/knowledgenode/knowledgenode_test.go
  sdk/graph/node/llmnode/config_test.go
  sdk/graph/node/llmnode/exec_test.go
  sdk/graph/node/llmnode/host_test.go
  sdk/graph/runner/internal/executor/checkpoint_test.go
  sdk/graph/runner/internal/executor/executor_test.go
  sdk/graph/runner/internal/executor/retry_test.go
  sdk/graph/runner/runner_test.go
  sdk/history/archive_test.go
  sdk/history/compact_test.go
  sdk/history/compactor_factory_test.go
  sdk/history/compactor_test.go
  sdk/history/coordinator_test.go
  sdk/history/store_test.go
  sdk/llm/factory_test.go
  sdk/llm/resolver_test.go
  sdk/model/message_test.go
  sdk/retrieval/pipeline/pipeline_test.go
  sdkx/tool/history/tools_test.go
  sdkx/tool/kanban/tools_test.go
)

DELETED_TEST_PATCH_FILES=(
  sdk/graph/adapter/strategy_test.go
  sdk/history/tools_test.go
  sdk/kanban/tools_test.go
  sdk/knowledge/tool_test.go
  sdk/llm/deprecated_test.go
  sdk/retrieval/explain_test.go
  sdk/workflow/board_test.go
  sdk/workflow/run_integration_test.go
  sdk/workflow/run_test.go
  sdk/workflow/strategy_test.go
  sdkx/knowledge/watcher/watcher_test.go
)

# --- Pre-patch cleanup: restore tracked versions of runnable files if they exist in base commit; otherwise remove ---
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${BASE_COMMIT}:$f" 2>/dev/null; then
    git checkout "${BASE_COMMIT}" -- "$f"
  else
    rm -f -- "$f"
  fi
done

# If patch deletes tests, restore them before applying so deletion hunks apply cleanly.
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  if git cat-file -e "${BASE_COMMIT}:$f" 2>/dev/null; then
    git checkout "${BASE_COMMIT}" -- "$f"
  else
    rm -f -- "$f"
  fi
done

# --- Apply test patch from a file (robust) ---
TEST_PATCH_FILE="$(mktemp)"
cat > "$TEST_PATCH_FILE" <<'EOF_114329324912'
diff --git a/sdk/engine/board_test.go b/sdk/engine/board_test.go
--- a/sdk/engine/board_test.go
+++ b/sdk/engine/board_test.go
@@ -292,6 +292,45 @@ func TestBoard_RestoreFrom_EmptyChannelsRehydratesMain(t *testing.T) {
 	}
 }
 
+func TestBoard_RestoreBoard_MigratesLegacyMainChannelKey(t *testing.T) {
+	// Pre-v0.3.0 checkpoints stored MainChannel under the empty-string
+	// key. RestoreBoard must lift those messages onto the new key so
+	// resume on a v0.3+ binary keeps the transcript.
+	snap := &engine.BoardSnapshot{
+		Channels: map[string][]model.Message{
+			"": {model.NewTextMessage(model.RoleUser, "from-legacy")},
+		},
+	}
+
+	b := engine.RestoreBoard(snap)
+
+	if got := b.Channel(engine.MainChannel); len(got) != 1 || got[0].Content() != "from-legacy" {
+		t.Fatalf("MainChannel = %+v, want one legacy message", got)
+	}
+	if got := b.Channel(""); got != nil {
+		t.Fatalf("legacy empty-string channel should not be reachable, got %+v", got)
+	}
+}
+
+func TestBoard_RestoreBoard_LegacyDoesNotOverwriteNewKey(t *testing.T) {
+	// A snapshot that carries both the legacy "" key and the modern
+	// MainChannel key is treated as already migrated: the modern
+	// content wins and the legacy bucket is dropped.
+	snap := &engine.BoardSnapshot{
+		Channels: map[string][]model.Message{
+			"":                 {model.NewTextMessage(model.RoleUser, "legacy")},
+			engine.MainChannel: {model.NewTextMessage(model.RoleUser, "modern")},
+		},
+	}
+
+	b := engine.RestoreBoard(snap)
+
+	got := b.Channel(engine.MainChannel)
+	if len(got) != 1 || got[0].Content() != "modern" {
+		t.Fatalf("MainChannel = %+v, want modern content", got)
+	}
+}
+
 func TestBoard_RestoreFrom_NilIsNoOp(t *testing.T) {
 	b := engine.NewBoard()
 	b.SetVar("k", "v")
diff --git a/sdk/errdefs/http_test.go b/sdk/errdefs/http_test.go
--- a/sdk/errdefs/http_test.go
+++ b/sdk/errdefs/http_test.go
@@ -19,8 +19,8 @@ func (e *httpErr) HTTPStatusCode() int { return e.code }
 
 // TestClassifyProvider pins the structured-error / keyword / regex
 // dispatcher. Behaviour change here means every dependent (sdk/llm
-// fallback, sdkx/embedding, future sdkx/rerank) silently shifts how it
-// classifies the same upstream error.
+// fallback plus external embedding / rerank adapters) silently shifts
+// how it classifies the same upstream error.
 func TestClassifyProvider(t *testing.T) {
 	cases := []struct {
 		name string
diff --git a/sdk/graph/compile_test.go b/sdk/graph/compile_test.go
--- a/sdk/graph/compile_test.go
+++ b/sdk/graph/compile_test.go
@@ -245,104 +245,3 @@ func TestCompiler_Compile_DetectsCycles(t *testing.T) {
 		t.Fatal("expected HasCycles to be true")
 	}
 }
-
-func TestCompiler_Compile_LLMIsolatedMessagesKeyWarning(t *testing.T) {
-	t.Run("warns when query_fallback missing", func(t *testing.T) {
-		def := &graph.GraphDefinition{
-			Name:  "test",
-			Entry: "llm1",
-			Nodes: []graph.NodeDefinition{
-				{ID: "llm1", Type: "llm", Config: map[string]any{
-					"messages_key": "custom_messages",
-				}},
-			},
-			Edges: []graph.EdgeDefinition{
-				{From: "llm1", To: graph.END},
-			},
-		}
-		result, err := graph.Compile(def)
-		if err != nil {
-			t.Fatalf("compile failed: %v", err)
-		}
-		found := false
-		for _, w := range result.Warnings {
-			if w.Code == "llm_isolated_messages_no_fallback" {
-				found = true
-			}
-		}
-		if !found {
-			t.Fatal("expected llm_isolated_messages_no_fallback warning")
-		}
-	})
-
-	t.Run("no warning when query_fallback is true", func(t *testing.T) {
-		def := &graph.GraphDefinition{
-			Name:  "test",
-			Entry: "llm1",
-			Nodes: []graph.NodeDefinition{
-				{ID: "llm1", Type: "llm", Config: map[string]any{
-					"messages_key":   "custom_messages",
-					"query_fallback": true,
-				}},
-			},
-			Edges: []graph.EdgeDefinition{
-				{From: "llm1", To: graph.END},
-			},
-		}
-		result, err := graph.Compile(def)
-		if err != nil {
-			t.Fatalf("compile failed: %v", err)
-		}
-		for _, w := range result.Warnings {
-			if w.Code == "llm_isolated_messages_no_fallback" {
-				t.Fatalf("unexpected warning: %s", w.Message)
-			}
-		}
-	})
-
-	t.Run("no warning when using default messages key", func(t *testing.T) {
-		def := &graph.GraphDefinition{
-			Name:  "test",
-			Entry: "llm1",
-			Nodes: []graph.NodeDefinition{
-				{ID: "llm1", Type: "llm", Config: map[string]any{
-					"messages_key": "messages",
-				}},
-			},
-			Edges: []graph.EdgeDefinition{
-				{From: "llm1", To: graph.END},
-			},
-		}
-		result, err := graph.Compile(def)
-		if err != nil {
-			t.Fatalf("compile failed: %v", err)
-		}
-		for _, w := range result.Warnings {
-			if w.Code == "llm_isolated_messages_no_fallback" {
-				t.Fatalf("unexpected warning for default messages key")
-			}
-		}
-	})
-
-	t.Run("no warning when messages_key omitted", func(t *testing.T) {
-		def := &graph.GraphDefinition{
-			Name:  "test",
-			Entry: "llm1",
-			Nodes: []graph.NodeDefinition{
-				{ID: "llm1", Type: "llm", Config: map[string]any{}},
-			},
-			Edges: []graph.EdgeDefinition{
-				{From: "llm1", To: graph.END},
-			},
-		}
-		result, err := graph.Compile(def)
-		if err != nil {
-			t.Fatalf("compile failed: %v", err)
-		}
-		for _, w := range result.Warnings {
-			if w.Code == "llm_isolated_messages_no_fallback" {
-				t.Fatalf("unexpected warning when messages_key is omitted")
-			}
-		}
-	})
-}
diff --git a/sdk/graph/node/knowledgenode/knowledgenode_test.go b/sdk/graph/node/knowledgenode/knowledgenode_test.go
--- a/sdk/graph/node/knowledgenode/knowledgenode_test.go
+++ b/sdk/graph/node/knowledgenode/knowledgenode_test.go
@@ -75,7 +75,7 @@ func TestNode_SingleScope_PerDatasetStateKey(t *testing.T) {
 	n := knowledgenode.New("k", svc, knowledgenode.Config{
 		Scope: knowledge.ScopeSingleDataset,
 		Mode:  knowledge.ModeBM25,
-		Datasets: []knowledge.DatasetQuery{
+		Datasets: []knowledgenode.DatasetQuery{
 			{DatasetID: "docs", StateKey: "docsHits", TopK: 5},
 		},
 	})
@@ -162,6 +162,42 @@ func TestConfigFromMap_AllScopeAndDatasets(t *testing.T) {
 	}
 }
 
+func TestNode_CustomQueryKey(t *testing.T) {
+	svc := newLocalService(t)
+	if err := svc.PutDocument(context.Background(), "ds1", "a.md", "alpha banana"); err != nil {
+		t.Fatalf("put: %v", err)
+	}
+
+	n := knowledgenode.New("k", svc, knowledgenode.Config{
+		QueryKey: "search_text",
+		Datasets: []knowledgenode.DatasetQuery{{DatasetID: "ds1", TopK: 3}},
+	})
+
+	ports := n.InputPorts()
+	if len(ports) == 0 || ports[0].Name != "search_text" {
+		t.Fatalf("input port[0] = %+v, want name=search_text", ports[0])
+	}
+
+	ectx, board := newNodeBoardCtx()
+	board.SetVar("search_text", "alpha")
+
+	if err := n.ExecuteBoard(ectx, board); err != nil {
+		t.Fatalf("execute: %v", err)
+	}
+	hits, _ := board.GetVar("hits")
+	h, ok := hits.([]knowledge.Hit)
+	if !ok || len(h) == 0 {
+		t.Fatalf("hits = %v, want non-empty []Hit", hits)
+	}
+}
+
+func TestConfigFromMap_QueryKey(t *testing.T) {
+	cfg := knowledgenode.ConfigFromMap(map[string]any{"query_key": "user_input"})
+	if cfg.QueryKey != "user_input" {
+		t.Fatalf("QueryKey = %q", cfg.QueryKey)
+	}
+}
+
 func TestRegister_BuildsKnowledgeNode(t *testing.T) {
 	f := node.NewFactory()
 	knowledgenode.Register(f, nil) // nil svc is fine — node falls back to empty hits
diff --git a/sdk/graph/node/llmnode/config_test.go b/sdk/graph/node/llmnode/config_test.go
--- a/sdk/graph/node/llmnode/config_test.go
+++ b/sdk/graph/node/llmnode/config_test.go
@@ -22,15 +22,14 @@ func mustConfigFromMap(t *testing.T, m map[string]any) Config {
 
 func TestConfigFromMap_Full(t *testing.T) {
 	m := map[string]any{
-		"system_prompt":  "You are helpful.",
-		"model":          "openai/gpt-4o",
-		"temperature":    0.7,
-		"max_tokens":     float64(1024),
-		"output_key":     "answer",
-		"messages_key":   "msgs",
-		"json_mode":      true,
-		"query_fallback": false,
-		"track_steps":    true,
+		"system_prompt":    "You are helpful.",
+		"model":            "openai/gpt-4o",
+		"temperature":      0.7,
+		"max_tokens":       float64(1024),
+		"output_key":       "answer",
+		"messages_channel": "msgs",
+		"json_mode":        true,
+		"track_steps":      true,
 	}
 	cfg := mustConfigFromMap(t, m)
 
@@ -49,8 +48,8 @@ func TestConfigFromMap_Full(t *testing.T) {
 	if cfg.OutputKey != "answer" {
 		t.Fatalf("OutputKey = %q", cfg.OutputKey)
 	}
-	if cfg.MessagesKey != "msgs" {
-		t.Fatalf("MessagesKey = %q", cfg.MessagesKey)
+	if cfg.MessagesChannel != "msgs" {
+		t.Fatalf("MessagesChannel = %q", cfg.MessagesChannel)
 	}
 	if !cfg.JSONMode {
 		t.Fatal("JSONMode should be true")
@@ -180,7 +179,7 @@ func TestBuildMessages_NoSystemDuplicate(t *testing.T) {
 		model.NewTextMessage(model.RoleUser, "hi"),
 	})
 
-	msgs := n.buildMessages(n.config, board, graph.MainChannel, graph.VarMessages)
+	msgs := n.buildMessages(n.config, board, graph.MainChannel)
 	systemCount := 0
 	for _, m := range msgs {
 		if m.Role == model.RoleSystem {
@@ -192,19 +191,6 @@ func TestBuildMessages_NoSystemDuplicate(t *testing.T) {
 	}
 }
 
-func TestBuildMessages_FallbackToVar(t *testing.T) {
-	n := New("n", nil, nil, Config{})
-	board := newTestBoard()
-	board.SetVar(graph.VarMessages, []model.Message{
-		model.NewTextMessage(model.RoleUser, "from var"),
-	})
-
-	msgs := n.buildMessages(n.config, board, "empty_channel", graph.VarMessages)
-	if len(msgs) != 1 || msgs[0].Content() != "from var" {
-		t.Fatalf("expected message from var, got %v", msgs)
-	}
-}
-
 func TestBuildMessages_SummaryIndexInjection(t *testing.T) {
 	board := newTestBoard()
 	board.SetChannel(graph.MainChannel, []model.Message{
@@ -213,7 +199,7 @@ func TestBuildMessages_SummaryIndexInjection(t *testing.T) {
 	board.SetVar(VarSummaryIndex, "## 摘要\n[s1] seq 0-10")
 
 	n := New("n", nil, nil, Config{SystemPrompt: "You are helpful."})
-	msgs := n.buildMessages(n.config, board, graph.MainChannel, graph.VarMessages)
+	msgs := n.buildMessages(n.config, board, graph.MainChannel)
 
 	if len(msgs) != 2 {
 		t.Fatalf("expected 2 messages, got %d", len(msgs))
diff --git a/sdk/graph/node/llmnode/exec_test.go b/sdk/graph/node/llmnode/exec_test.go
--- a/sdk/graph/node/llmnode/exec_test.go
+++ b/sdk/graph/node/llmnode/exec_test.go
@@ -5,6 +5,7 @@ import (
 	"errors"
 	"testing"
 
+	"github.com/GizClaw/flowcraft/sdk/errdefs"
 	"github.com/GizClaw/flowcraft/sdk/graph"
 	"github.com/GizClaw/flowcraft/sdk/llm"
 	"github.com/GizClaw/flowcraft/sdk/model"
@@ -224,22 +225,6 @@ func TestNode_ExecuteBoard_JSONMode_InvalidJSON(t *testing.T) {
 	}
 }
 
-func TestNode_ExecuteBoard_QueryFallback(t *testing.T) {
-	stream := &mockStream{chunks: []model.StreamChunk{{Content: "resp"}}}
-	resolver := &mockResolver{llmInst: &streamOnlyLLM{stream: stream}}
-	n := New("llm1", resolver, nil, Config{
-		MessagesKey:   "alt_msgs",
-		QueryFallback: true,
-	})
-
-	board := graph.NewBoard()
-	board.SetVar(graph.VarQuery, "what is this?")
-
-	if err := n.ExecuteBoard(execCtx(), board); err != nil {
-		t.Fatalf("unexpected error: %v", err)
-	}
-}
-
 func TestNode_ExecuteBoard_TrackSteps(t *testing.T) {
 	stream := &mockStream{chunks: []model.StreamChunk{{Content: "step1"}}}
 	resolver := &mockResolver{llmInst: &streamOnlyLLM{stream: stream}}
@@ -329,3 +314,38 @@ func TestNode_ExecuteBoard_WithToolCalls(t *testing.T) {
 		t.Fatalf("expected tool_call and tool_result events, got %v", events)
 	}
 }
+
+func TestNode_ExecuteBoard_EmptyMessages_RejectsRequest(t *testing.T) {
+	resolver := &mockResolver{llmInst: &mockLLM{}}
+	n := New("llm1", resolver, nil, Config{
+		MessagesChannel: "isolated",
+	})
+
+	board := graph.NewBoard()
+
+	err := n.ExecuteBoard(execCtx(), board)
+	if err == nil {
+		t.Fatal("expected validation error for empty messages, got nil")
+	}
+	if !errdefs.IsValidation(err) {
+		t.Fatalf("expected validation error, got %v", err)
+	}
+}
+
+func TestNode_ExecuteBoard_SystemPromptOnly_Allowed(t *testing.T) {
+	stream := &mockStream{chunks: []model.StreamChunk{{Content: "hi from system-only"}}}
+	resolver := &mockResolver{llmInst: &streamOnlyLLM{stream: stream}}
+	n := New("llm1", resolver, nil, Config{
+		SystemPrompt:    "You are an autonomous worker. Greet the user.",
+		MessagesChannel: "isolated",
+	})
+
+	board := graph.NewBoard()
+
+	if err := n.ExecuteBoard(execCtx(), board); err != nil {
+		t.Fatalf("system-only request should be allowed, got %v", err)
+	}
+	if resp, _ := board.GetVar(VarResponse); resp != "hi from system-only" {
+		t.Fatalf("response = %q", resp)
+	}
+}
diff --git a/sdk/graph/node/llmnode/host_test.go b/sdk/graph/node/llmnode/host_test.go
--- a/sdk/graph/node/llmnode/host_test.go
+++ b/sdk/graph/node/llmnode/host_test.go
@@ -98,10 +98,14 @@ func TestNode_DoesNotReportZeroUsage(t *testing.T) {
 	}}
 	n := New("llm1", resolver, nil, Config{})
 
+	board := graph.NewBoard()
+	board.SetChannel(graph.MainChannel, []model.Message{
+		model.NewTextMessage(model.RoleUser, "hi"),
+	})
 	err := n.ExecuteBoard(graph.ExecutionContext{
 		Context: context.Background(),
 		Host:    host,
-	}, graph.NewBoard())
+	}, board)
 	if err != nil {
 		t.Fatalf("ExecuteBoard error: %v", err)
 	}
diff --git a/sdk/graph/runner/internal/executor/checkpoint_test.go b/sdk/graph/runner/internal/executor/checkpoint_test.go
--- a/sdk/graph/runner/internal/executor/checkpoint_test.go
+++ b/sdk/graph/runner/internal/executor/checkpoint_test.go
@@ -9,50 +9,6 @@ import (
 	"github.com/GizClaw/flowcraft/sdk/graph"
 )
 
-func TestLocalExecutor_Checkpoint(t *testing.T) {
-	dir := t.TempDir()
-	store, err := NewFileCheckpointStore(FileCheckpointConfig{Dir: dir})
-	if err != nil {
-		t.Fatalf("create checkpoint store: %v", err)
-	}
-
-	g := buildGraph("test", "a",
-		map[string]graph.Node{
-			"a": newTestNode("a", func(_ graph.ExecutionContext, b *graph.Board) error {
-				b.SetVar("a_done", true)
-				return nil
-			}),
-			"b": newTestNode("b", func(_ graph.ExecutionContext, b *graph.Board) error {
-				b.SetVar("b_done", true)
-				return nil
-			}),
-		},
-		[]graph.Edge{
-			{From: "a", To: "b"},
-			{From: "b", To: graph.END},
-		},
-	)
-
-	board := graph.NewBoard()
-	exec := NewLocalExecutor()
-	_, err = exec.Execute(context.Background(), g, board,
-		WithCheckpointStore(store))
-	if err != nil {
-		t.Fatalf("execute failed: %v", err)
-	}
-
-	cp, err := store.Load("test", "")
-	if err != nil {
-		t.Fatalf("load checkpoint: %v", err)
-	}
-	if cp == nil {
-		t.Fatal("expected checkpoint to exist")
-	}
-	if cp.NodeID != "b" {
-		t.Fatalf("expected last checkpoint at node 'b', got %q", cp.NodeID)
-	}
-}
-
 func TestFileCheckpointStore_ListSkipsBackups(t *testing.T) {
 	dir := t.TempDir()
 	store, err := NewFileCheckpointStore(FileCheckpointConfig{Dir: dir})
@@ -269,45 +225,6 @@ func TestCheckpoint_RunID_InStruct(t *testing.T) {
 	}
 }
 
-func TestCheckpoint_WithRunID_IntegrationExecution(t *testing.T) {
-	dir := t.TempDir()
-	store, err := NewFileCheckpointStore(FileCheckpointConfig{Dir: dir})
-	if err != nil {
-		t.Fatal(err)
-	}
-
-	g := buildGraph("test", "a",
-		map[string]graph.Node{
-			"a": newTestNode("a", func(_ graph.ExecutionContext, b *graph.Board) error {
-				b.SetVar("done", true)
-				return nil
-			}),
-		},
-		[]graph.Edge{{From: "a", To: graph.END}},
-	)
-
-	board := graph.NewBoard()
-	exec := NewLocalExecutor()
-	_, err = exec.Execute(context.Background(), g, board,
-		WithRunID("run-abc"),
-		WithCheckpointStore(store),
-	)
-	if err != nil {
-		t.Fatalf("execute failed: %v", err)
-	}
-
-	cp, err := store.Load("test", "run-abc")
-	if err != nil {
-		t.Fatal(err)
-	}
-	if cp == nil {
-		t.Fatal("expected checkpoint with runID")
-	}
-	if cp.RunID != "run-abc" {
-		t.Fatalf("expected RunID=run-abc, got %q", cp.RunID)
-	}
-}
-
 // recordingCheckpointHost embeds engine.NoopHost so it satisfies the
 // full Host interface; only Checkpoint is overridden so executor-side
 // tests can assert on the engine.Checkpoint shape without standing up
@@ -322,20 +239,11 @@ func (h *recordingCheckpointHost) Checkpoint(_ context.Context, cp engine.Checkp
 	return nil
 }
 
-// TestExecutor_HostCheckpoint_PreferredOverStore verifies the contract
-// resolveCheckpointHost documents: when WithHost is supplied, the
-// deprecated WithCheckpointStore is ignored. Checkpointing is state
-// (not observability), so unlike the publisher path we do NOT fan out
-// to both sinks — that would invite conflicting reads.
-func TestExecutor_HostCheckpoint_PreferredOverStore(t *testing.T) {
+// TestExecutor_HostCheckpoint verifies host.Checkpoint is invoked once
+// per node by the executor's main loop.
+func TestExecutor_HostCheckpoint(t *testing.T) {
 	host := &recordingCheckpointHost{}
 
-	dir := t.TempDir()
-	store, err := NewFileCheckpointStore(FileCheckpointConfig{Dir: dir})
-	if err != nil {
-		t.Fatal(err)
-	}
-
 	g := buildGraph("test", "a",
 		map[string]graph.Node{
 			"a": newTestNode("a", func(_ graph.ExecutionContext, b *graph.Board) error {
@@ -346,12 +254,10 @@ func TestExecutor_HostCheckpoint_PreferredOverStore(t *testing.T) {
 		[]graph.Edge{{From: "a", To: graph.END}},
 	)
 
-	board := graph.NewBoard()
 	exec := NewLocalExecutor()
-	_, err = exec.Execute(context.Background(), g, board,
+	_, err := exec.Execute(context.Background(), g, graph.NewBoard(),
 		WithRunID("run-host"),
 		WithHost(host),
-		WithCheckpointStore(store), // intentionally also set; should be ignored
 	)
 	if err != nil {
 		t.Fatalf("execute failed: %v", err)
@@ -371,56 +277,4 @@ func TestExecutor_HostCheckpoint_PreferredOverStore(t *testing.T) {
 		t.Fatalf("Attributes[graph_name] = %q, want %q",
 			got.Attributes["graph_name"], "test")
 	}
-
-	// The legacy file store must remain empty: when the user supplied
-	// a host, the deprecated path is silently shadowed.
-	cp, err := store.Load("test", "run-host")
-	if err != nil {
-		t.Fatal(err)
-	}
-	if cp != nil {
-		t.Fatalf("legacy store should be empty when host is set, got %+v", cp)
-	}
-}
-
-// TestExecutor_StoreOnlyHost_ForwardsToStore confirms that the
-// transitional path (only WithCheckpointStore, no WithHost) keeps
-// working: the store is folded into a storeOnlyHost so the executor's
-// host-driven main loop ends up calling the deprecated Save.
-func TestExecutor_StoreOnlyHost_ForwardsToStore(t *testing.T) {
-	dir := t.TempDir()
-	store, err := NewFileCheckpointStore(FileCheckpointConfig{Dir: dir})
-	if err != nil {
-		t.Fatal(err)
-	}
-
-	g := buildGraph("test", "a",
-		map[string]graph.Node{
-			"a": newTestNode("a", func(_ graph.ExecutionContext, b *graph.Board) error {
-				b.SetVar("done", true)
-				return nil
-			}),
-		},
-		[]graph.Edge{{From: "a", To: graph.END}},
-	)
-
-	exec := NewLocalExecutor()
-	_, err = exec.Execute(context.Background(), g, graph.NewBoard(),
-		WithRunID("run-store"),
-		WithCheckpointStore(store),
-	)
-	if err != nil {
-		t.Fatalf("execute failed: %v", err)
-	}
-
-	cp, err := store.Load("test", "run-store")
-	if err != nil {
-		t.Fatal(err)
-	}
-	if cp == nil {
-		t.Fatal("legacy store should have received the checkpoint")
-	}
-	if cp.RunID != "run-store" || cp.NodeID != "a" || cp.GraphName != "test" {
-		t.Fatalf("checkpoint round-trip wrong: %+v", cp)
-	}
 }
diff --git a/sdk/graph/runner/internal/executor/executor_test.go b/sdk/graph/runner/internal/executor/executor_test.go
--- a/sdk/graph/runner/internal/executor/executor_test.go
+++ b/sdk/graph/runner/internal/executor/executor_test.go
@@ -8,7 +8,6 @@ import (
 
 	"github.com/GizClaw/flowcraft/sdk/engine"
 	"github.com/GizClaw/flowcraft/sdk/errdefs"
-	"github.com/GizClaw/flowcraft/sdk/event"
 	"github.com/GizClaw/flowcraft/sdk/graph"
 	"github.com/GizClaw/flowcraft/sdk/graph/variable"
 )
@@ -142,7 +141,7 @@ func TestLocalExecutor_Interrupt_Resume(t *testing.T) {
 				n := atomic.AddInt32(&callCount, 1)
 				if n == 1 {
 					b.SetVar("approval_status", "pending")
-					return graph.ErrInterrupt
+					return engine.Interrupted(engine.Interrupt{Cause: engine.CauseUnknown})
 				}
 				b.SetVar("approval_status", "approved")
 				return nil
@@ -162,8 +161,8 @@ func TestLocalExecutor_Interrupt_Resume(t *testing.T) {
 	exec := NewLocalExecutor()
 
 	result, err := exec.Execute(context.Background(), g, board)
-	if !errdefs.Is(err, graph.ErrInterrupt) {
-		t.Fatalf("expected ErrInterrupt, got %v", err)
+	if !errdefs.IsInterrupted(err) {
+		t.Fatalf("expected interrupt error, got %v", err)
 	}
 
 	interruptedNode := result.GetVarString(graph.VarInterruptedNode)
@@ -388,66 +387,6 @@ func TestLocalExecutor_AbortBetweenNodes(t *testing.T) {
 	}
 }
 
-func TestLocalExecutor_EventBus_Integration(t *testing.T) {
-	bus := event.NewMemoryBus()
-	defer func() { _ = bus.Close() }()
-
-	ctx := context.Background()
-	const runID = "rint-1"
-	sub, err := bus.Subscribe(ctx, engine.PatternRun(runID))
-	if err != nil {
-		t.Fatalf("subscribe: %v", err)
-	}
-
-	g := buildGraph("test", "start",
-		map[string]graph.Node{
-			"start": graph.NewPassthroughNode("start", "passthrough"),
-		},
-		[]graph.Edge{
-			{From: "start", To: graph.END},
-		},
-	)
-
-	board := graph.NewBoard()
-	exec := NewLocalExecutor()
-	_, err = exec.Execute(ctx, g, board, WithEventBus(bus), WithRunID(runID))
-	if err != nil {
-		t.Fatalf("execute failed: %v", err)
-	}
-
-	wantStart := engine.SubjectRunStart(runID)
-	wantEnd := engine.SubjectRunEnd(runID)
-
-	var envelopes []event.Envelope
-	timeout := time.After(time.Second)
-loop:
-	for {
-		select {
-		case env, ok := <-sub.C():
-			if !ok {
-				break loop
-			}
-			envelopes = append(envelopes, env)
-			if env.Subject == wantEnd {
-				break loop
-			}
-		case <-timeout:
-			break loop
-		}
-	}
-
-	if len(envelopes) < 2 {
-		t.Fatalf("expected at least 2 envelopes (start+end), got %d", len(envelopes))
-	}
-	if envelopes[0].Subject != wantStart {
-		t.Fatalf("first envelope should be %s, got %s", wantStart, envelopes[0].Subject)
-	}
-	// Headers must carry the run id for downstream predicate filters.
-	if envelopes[0].RunID() != runID {
-		t.Fatalf("envelope missing run_id header, got %q", envelopes[0].RunID())
-	}
-}
-
 func TestLocalExecutor_Compiler_Integration(t *testing.T) {
 	def := &graph.GraphDefinition{
 		Name:  "integration_test",
diff --git a/sdk/graph/runner/internal/executor/retry_test.go b/sdk/graph/runner/internal/executor/retry_test.go
--- a/sdk/graph/runner/internal/executor/retry_test.go
+++ b/sdk/graph/runner/internal/executor/retry_test.go
@@ -41,43 +41,27 @@ func TestLocalExecutor_NodeRetry(t *testing.T) {
 	}
 }
 
-func TestLocalExecutor_StreamCallback_ToolCallCapture(t *testing.T) {
+func TestLocalExecutor_StreamPublisher_ToolCallCapture(t *testing.T) {
 	node := newTestNode("llm", func(ctx graph.ExecutionContext, b *graph.Board) error {
-		if ctx.Stream != nil {
-			ctx.Stream(graph.StreamEvent{
-				Type:   "tool_call",
-				NodeID: "llm",
-				Payload: map[string]any{
-					"id":        "tc-1",
-					"name":      "web_search",
-					"arguments": `{"q":"golang"}`,
-				},
+		if ctx.Publisher != nil {
+			ctx.Publisher.Emit("tool_call", map[string]any{
+				"id":        "tc-1",
+				"name":      "web_search",
+				"arguments": `{"q":"golang"}`,
 			})
-			ctx.Stream(graph.StreamEvent{
-				Type:   "tool_call",
-				NodeID: "llm",
-				Payload: map[string]any{
-					"id":        "tc-2",
-					"name":      "code_run",
-					"arguments": `{"code":"fmt.Println()"}`,
-				},
+			ctx.Publisher.Emit("tool_call", map[string]any{
+				"id":        "tc-2",
+				"name":      "code_run",
+				"arguments": `{"code":"fmt.Println()"}`,
 			})
-			ctx.Stream(graph.StreamEvent{
-				Type:   "tool_result",
-				NodeID: "llm",
-				Payload: map[string]any{
-					"tool_call_id": "tc-1",
-					"content":      "search result",
-				},
+			ctx.Publisher.Emit("tool_result", map[string]any{
+				"tool_call_id": "tc-1",
+				"content":      "search result",
 			})
-			ctx.Stream(graph.StreamEvent{
-				Type:   "tool_result",
-				NodeID: "llm",
-				Payload: map[string]any{
-					"tool_call_id": "tc-2",
-					"content":      "error output",
-					"is_error":     true,
-				},
+			ctx.Publisher.Emit("tool_result", map[string]any{
+				"tool_call_id": "tc-2",
+				"content":      "error output",
+				"is_error":     true,
 			})
 		}
 		b.SetVar("answer", "done")
@@ -89,22 +73,13 @@ func TestLocalExecutor_StreamCallback_ToolCallCapture(t *testing.T) {
 		[]graph.Edge{{From: "llm", To: graph.END}},
 	)
 
-	var captured []graph.StreamEvent
-	cb := func(se graph.StreamEvent) {
-		captured = append(captured, se)
-	}
-
 	board := graph.NewBoard()
 	exec := NewLocalExecutor()
-	result, err := exec.Execute(context.Background(), g, board, WithStreamCallback(cb))
+	result, err := exec.Execute(context.Background(), g, board)
 	if err != nil {
 		t.Fatalf("execute failed: %v", err)
 	}
 
-	if len(captured) != 4 {
-		t.Fatalf("expected 4 stream events, got %d", len(captured))
-	}
-
 	tcRaw, ok := result.GetVar(graph.VarToolCalls)
 	if !ok {
 		t.Fatal("expected VarToolCalls on board")
@@ -140,14 +115,10 @@ func TestLocalExecutor_StreamCallback_ToolCallCapture(t *testing.T) {
 	}
 }
 
-func TestLocalExecutor_StreamCallback_NoToolCalls(t *testing.T) {
+func TestLocalExecutor_StreamPublisher_NoToolCalls(t *testing.T) {
 	node := newTestNode("simple", func(ctx graph.ExecutionContext, b *graph.Board) error {
-		if ctx.Stream != nil {
-			ctx.Stream(graph.StreamEvent{
-				Type:    "token",
-				NodeID:  "simple",
-				Payload: map[string]any{"chunk": "hello"},
-			})
+		if ctx.Publisher != nil {
+			ctx.Publisher.Emit("token", map[string]any{"chunk": "hello"})
 		}
 		b.SetVar("answer", "done")
 		return nil
@@ -160,7 +131,7 @@ func TestLocalExecutor_StreamCallback_NoToolCalls(t *testing.T) {
 
 	board := graph.NewBoard()
 	exec := NewLocalExecutor()
-	result, err := exec.Execute(context.Background(), g, board, WithStreamCallback(func(se graph.StreamEvent) {}))
+	result, err := exec.Execute(context.Background(), g, board)
 	if err != nil {
 		t.Fatalf("execute failed: %v", err)
 	}
@@ -169,39 +140,3 @@ func TestLocalExecutor_StreamCallback_NoToolCalls(t *testing.T) {
 		t.Fatal("expected no VarToolCalls for non-tool stream events")
 	}
 }
-
-func TestLocalExecutor_StreamCallback_NilCallback(t *testing.T) {
-	node := newTestNode("llm", func(ctx graph.ExecutionContext, b *graph.Board) error {
-		if ctx.Stream != nil {
-			ctx.Stream(graph.StreamEvent{
-				Type:   "tool_call",
-				NodeID: "llm",
-				Payload: map[string]any{
-					"id": "tc-1", "name": "search", "arguments": "{}",
-				},
-			})
-		}
-		return nil
-	})
-
-	g := buildGraph("test", "llm",
-		map[string]graph.Node{"llm": node},
-		[]graph.Edge{{From: "llm", To: graph.END}},
-	)
-
-	board := graph.NewBoard()
-	exec := NewLocalExecutor()
-	_, err := exec.Execute(context.Background(), g, board)
-	if err != nil {
-		t.Fatalf("execute failed: %v", err)
-	}
-
-	tcRaw, ok := board.GetVar(graph.VarToolCalls)
-	if !ok {
-		t.Fatal("expected VarToolCalls even without external callback")
-	}
-	tc := tcRaw.([]any)
-	if len(tc) != 1 {
-		t.Fatalf("expected 1 tool call, got %d", len(tc))
-	}
-}
diff --git a/sdk/graph/runner/runner_test.go b/sdk/graph/runner/runner_test.go
--- a/sdk/graph/runner/runner_test.go
+++ b/sdk/graph/runner/runner_test.go
@@ -6,11 +6,9 @@ import (
 	"sync"
 	"sync/atomic"
 	"testing"
-	"time"
 
 	"github.com/GizClaw/flowcraft/sdk/engine"
 	"github.com/GizClaw/flowcraft/sdk/engine/enginetest"
-	"github.com/GizClaw/flowcraft/sdk/event"
 	"github.com/GizClaw/flowcraft/sdk/graph"
 	"github.com/GizClaw/flowcraft/sdk/graph/node"
 	"github.com/GizClaw/flowcraft/sdk/graph/runner"
@@ -223,67 +221,6 @@ func TestRunner_ConcurrentSafety(t *testing.T) {
 	}
 }
 
-func TestRunner_WithEventBus(t *testing.T) {
-	bus := event.NewMemoryBus()
-	defer func() { _ = bus.Close() }()
-
-	def := &graph.GraphDefinition{
-		Name:  "bus_test",
-		Entry: "start",
-		Nodes: []graph.NodeDefinition{
-			{ID: "start", Type: "passthrough"},
-		},
-		Edges: []graph.EdgeDefinition{
-			{From: "start", To: graph.END},
-		},
-	}
-
-	r, err := runner.New(def, node.NewFactory(), runner.WithEventBus(bus))
-	if err != nil {
-		t.Fatalf("runner.New: %v", err)
-	}
-
-	if r.Bus() != bus {
-		t.Fatal("Bus() should return the configured bus")
-	}
-
-	const runID = "rb-1"
-	sub, err := bus.Subscribe(context.Background(), engine.PatternRun(runID), event.WithBufferSize(16))
-	if err != nil {
-		t.Fatalf("subscribe: %v", err)
-	}
-
-	_, err = r.Execute(context.Background(),
-		engine.Run{ID: runID}, r.Host(), engine.NewBoard())
-	if err != nil {
-		t.Fatalf("Execute: %v", err)
-	}
-
-	wantPrefix := string(engine.SubjectPrefix) + runID + "."
-	sawStart, sawEnd := false, false
-	timeout := time.After(time.Second)
-	for !(sawStart && sawEnd) {
-		select {
-		case env, ok := <-sub.C():
-			if !ok {
-				t.Fatalf("subscription closed before seeing start+end (sawStart=%v sawEnd=%v)", sawStart, sawEnd)
-			}
-			subj := string(env.Subject)
-			if subj == wantPrefix+"start" {
-				sawStart = true
-			}
-			if subj == wantPrefix+"end" {
-				sawEnd = true
-			}
-			if !strings.HasPrefix(subj, wantPrefix) {
-				t.Fatalf("unexpected subject %q", subj)
-			}
-		case <-timeout:
-			t.Fatalf("timeout waiting for start+end (sawStart=%v sawEnd=%v)", sawStart, sawEnd)
-		}
-	}
-}
-
 // TestRunner_WithHost confirms graph lifecycle envelopes are routed through
 // engine.Host.Publish (the v0.3 path) when the user supplies WithHost. The
 // MockHost lets us assert on every envelope without standing up an event
@@ -339,47 +276,6 @@ func TestRunner_WithHost(t *testing.T) {
 	}
 }
 
-func TestRunner_StreamCallback(t *testing.T) {
-	factory := testFactory(map[string]node.NodeBuilder{
-		"emitter": testNodeBuilder(func(ctx graph.ExecutionContext, b *graph.Board) error {
-			if ctx.Stream != nil {
-				ctx.Stream(graph.StreamEvent{Type: "token", NodeID: "emit", Payload: map[string]any{"content": "hi"}})
-			}
-			b.SetVar("done", true)
-			return nil
-		}),
-	})
-
-	def := &graph.GraphDefinition{
-		Name:  "stream",
-		Entry: "emit",
-		Nodes: []graph.NodeDefinition{
-			{ID: "emit", Type: "emitter"},
-		},
-		Edges: []graph.EdgeDefinition{
-			{From: "emit", To: graph.END},
-		},
-	}
-
-	var captured []graph.StreamEvent
-	r, err := runner.New(def, factory,
-		runner.WithStreamCallback(func(se graph.StreamEvent) {
-			captured = append(captured, se)
-		}),
-	)
-	if err != nil {
-		t.Fatalf("runner.New: %v", err)
-	}
-
-	_, err = r.Run(context.Background(), nil)
-	if err != nil {
-		t.Fatalf("Run: %v", err)
-	}
-	if len(captured) != 1 {
-		t.Fatalf("expected 1 stream event, got %d", len(captured))
-	}
-}
-
 func TestRunner_Graph(t *testing.T) {
 	def := &graph.GraphDefinition{
 		Name:  "inspect",
diff --git a/sdk/history/archive_test.go b/sdk/history/archive_test.go
--- a/sdk/history/archive_test.go
+++ b/sdk/history/archive_test.go
@@ -123,7 +123,7 @@ func TestRecoverArchive_NoIntent(t *testing.T) {
 	ctx := context.Background()
 
 	// No pending intent — should be a no-op.
-	if err := RecoverArchive(ctx, ws, store, "memory", "archive", "no-intent-conv"); err != nil {
+	if err := recoverArchiveImpl(ctx, ws, store, "memory", "archive", "no-intent-conv"); err != nil {
 		t.Fatal(err)
 	}
 }
@@ -172,7 +172,7 @@ func TestRecoverArchive_GzipWrittenPhase(t *testing.T) {
 	_ = writeIntent(ctx, ws, "memory", "archive", convID, intent)
 
 	// Recovery should: update manifest, trim messages.
-	if err := RecoverArchive(ctx, ws, store, "memory", "archive", convID); err != nil {
+	if err := recoverArchiveImpl(ctx, ws, store, "memory", "archive", convID); err != nil {
 		t.Fatal(err)
 	}
 
@@ -221,7 +221,7 @@ func TestRecoverArchive_ManifestUpdatedPhase(t *testing.T) {
 	}
 	_ = writeIntent(ctx, ws, "memory", "archive", convID, intent)
 
-	if err := RecoverArchive(ctx, ws, store, "memory", "archive", convID); err != nil {
+	if err := recoverArchiveImpl(ctx, ws, store, "memory", "archive", convID); err != nil {
 		t.Fatal(err)
 	}
 
@@ -264,9 +264,9 @@ func TestArchive_IntentCleanup(t *testing.T) {
 	}
 }
 
-// TestSaveManifest_RoundTrip exercises the deprecated SaveManifest /
-// LoadManifest pair declared in deprecated.go: write a manifest, read it
-// back, and assert all fields survive the JSON round-trip.
+// TestSaveManifest_RoundTrip exercises the saveManifestImpl /
+// LoadManifest pair: write a manifest, read it back, and assert all
+// fields survive the JSON round-trip.
 func TestSaveManifest_RoundTrip(t *testing.T) {
 	ws, err := workspace.NewLocalWorkspace(t.TempDir())
 	if err != nil {
@@ -282,7 +282,7 @@ func TestSaveManifest_RoundTrip(t *testing.T) {
 			{File: "messages_10_24.jsonl.gz", StartSeq: 10, EndSeq: 24, Count: 15, CreatedAt: time.Now().UTC().Truncate(time.Second)},
 		},
 	}
-	if err := SaveManifest(ctx, ws, "memory", "archive", convID, in); err != nil {
+	if err := saveManifestImpl(ctx, ws, "memory", "archive", convID, in); err != nil {
 		t.Fatalf("SaveManifest: %v", err)
 	}
 
diff --git a/sdk/history/compact_test.go b/sdk/history/compact_test.go
--- a/sdk/history/compact_test.go
+++ b/sdk/history/compact_test.go
@@ -141,48 +141,5 @@ func TestCompactArchive_ManualCompact(t *testing.T) {
 	}
 }
 
-func TestCompactArchive_ArchiveAndExpand(t *testing.T) {
-	ws, err := workspace.NewLocalWorkspace(t.TempDir())
-	if err != nil {
-		t.Fatal(err)
-	}
-	store := NewFileStore(ws, "memory")
-	ctx := context.Background()
-	convID := "archive-expand"
-
-	msgs := make([]model.Message, 30)
-	for i := range msgs {
-		msgs[i] = model.NewTextMessage(model.RoleUser, "content message")
-	}
-	_ = store.SaveMessages(ctx, convID, msgs)
-
-	// Archive first 15.
-	cfg := ArchiveConfig{ArchiveThreshold: 20, ArchiveBatchSize: 15}
-	ar, err := Archive(ctx, ws, store, "memory", convID, cfg)
-	if err != nil {
-		t.Fatal(err)
-	}
-	if ar.MessagesArchived != 15 {
-		t.Fatalf("expected 15 archived, got %d", ar.MessagesArchived)
-	}
-
-	// Expand across boundary (seq 10-20).
-	summaryStore := NewFileSummaryStore(ws, "memory")
-	_ = summaryStore.Save(ctx, &SummaryNode{
-		ID: "cross-node", ConversationID: convID, Depth: 0,
-		Content: "summary", EarliestSeq: 10, LatestSeq: 20,
-	})
-
-	expandTool := newHistoryExpandTool(ToolDeps{
-		SummaryStore: summaryStore, MessageStore: store,
-		Workspace: ws, Prefix: "memory",
-	})
-	expandCtx := WithConversationID(ctx, convID)
-	result, err := expandTool.Execute(expandCtx, `{"summary_id":"cross-node","max_messages":50}`)
-	if err != nil {
-		t.Fatalf("expand: %v", err)
-	}
-	if result == "" {
-		t.Fatal("expand returned empty")
-	}
-}
+// Boundary expand (cold archive + hot tail) is exercised by the
+// history_expand tool's own tests in the adapter package.
diff --git a/sdk/history/compactor_factory_test.go b/sdk/history/compactor_factory_test.go
--- a/sdk/history/compactor_factory_test.go
+++ b/sdk/history/compactor_factory_test.go
@@ -47,8 +47,8 @@ func TestNewCompacted_SmokeBoots(t *testing.T) {
 		t.Fatal("NewCompacted returned nil")
 	}
 	t.Cleanup(func() {
-		if c, ok := mem.(Closer); ok {
-			c.Close()
+		if c, ok := mem.(Coordinator); ok {
+			_ = c.Shutdown(context.Background())
 		}
 	})
 	ctx := context.Background()
diff --git a/sdk/history/compactor_test.go b/sdk/history/compactor_test.go
--- a/sdk/history/compactor_test.go
+++ b/sdk/history/compactor_test.go
@@ -199,7 +199,7 @@ func TestCompacted_CloseWaitsForAsync(t *testing.T) {
 	// Close should block until all async goroutines complete (not panic or deadlock).
 	done := make(chan struct{})
 	go func() {
-		mem.Close()
+		_ = mem.Shutdown(context.Background())
 		close(done)
 	}()
 
@@ -246,7 +246,7 @@ func TestCompacted_NoIngestDrop(t *testing.T) {
 			t.Fatalf("Append %d: %v", i, err)
 		}
 	}
-	mem.Close()
+	_ = mem.Shutdown(context.Background())
 
 	for i := 0; i < conversations; i++ {
 		got, err := store.GetMessages(ctx, fmt.Sprintf("conv-%d", i))
diff --git a/sdk/history/coordinator_test.go b/sdk/history/coordinator_test.go
--- a/sdk/history/coordinator_test.go
+++ b/sdk/history/coordinator_test.go
@@ -228,7 +228,7 @@ func TestCoordinator_LazyArchiveRecovery(t *testing.T) {
 
 	// First archive: completes normally so we have a manifest.
 	cfg := ArchiveConfig{ArchiveThreshold: 20, ArchiveBatchSize: 15}
-	if _, err := archiveImpl(ctx, ws, store, "memory", convID, cfg); err != nil {
+	if _, err := Archive(ctx, ws, store, "memory", convID, cfg); err != nil {
 		t.Fatal(err)
 	}
 
diff --git a/sdk/history/store_test.go b/sdk/history/store_test.go
--- a/sdk/history/store_test.go
+++ b/sdk/history/store_test.go
@@ -381,63 +381,6 @@ func TestFileStore_DeleteAndReuse(t *testing.T) {
 	}
 }
 
-// --- FileStore: deprecated SummaryCacheStore surface ---
-
-func TestFileStore_SaveAndGetSummary(t *testing.T) {
-	ws := workspace.NewMemWorkspace()
-	store := NewFileStore(ws, "memory")
-	ctx := context.Background()
-
-	if err := store.SaveSummary(ctx, "conv-sum", "the summary text", 42); err != nil {
-		t.Fatalf("SaveSummary: %v", err)
-	}
-
-	text, count, err := store.GetSummary(ctx, "conv-sum")
-	if err != nil {
-		t.Fatalf("GetSummary: %v", err)
-	}
-	if text != "the summary text" {
-		t.Fatalf("text mismatch: got %q", text)
-	}
-	if count != 42 {
-		t.Fatalf("count mismatch: got %d", count)
-	}
-}
-
-func TestFileStore_GetSummary_Missing(t *testing.T) {
-	ws := workspace.NewMemWorkspace()
-	store := NewFileStore(ws, "memory")
-	ctx := context.Background()
-
-	text, count, err := store.GetSummary(ctx, "no-such-conv")
-	if err != nil {
-		t.Fatalf("GetSummary on missing should be (\"\",0,nil), got err=%v", err)
-	}
-	if text != "" || count != 0 {
-		t.Fatalf("expected zero values for missing conv, got %q,%d", text, count)
-	}
-}
-
-func TestFileStore_SaveSummary_OverwritesPrevious(t *testing.T) {
-	ws := workspace.NewMemWorkspace()
-	store := NewFileStore(ws, "memory")
-	ctx := context.Background()
-
-	if err := store.SaveSummary(ctx, "c", "first", 1); err != nil {
-		t.Fatal(err)
-	}
-	if err := store.SaveSummary(ctx, "c", "second", 2); err != nil {
-		t.Fatal(err)
-	}
-	text, count, err := store.GetSummary(ctx, "c")
-	if err != nil {
-		t.Fatal(err)
-	}
-	if text != "second" || count != 2 {
-		t.Fatalf("expected overwrite to win, got %q,%d", text, count)
-	}
-}
-
 // --- InMemoryStore: options + lifecycle ---
 
 func TestInMemoryStore_LenReflectsSaves(t *testing.T) {
diff --git a/sdk/llm/factory_test.go b/sdk/llm/factory_test.go
--- a/sdk/llm/factory_test.go
+++ b/sdk/llm/factory_test.go
@@ -88,29 +88,6 @@ func TestProviderRegistry_RegisterModels_DoesNotMutateInput(t *testing.T) {
 	}
 }
 
-func TestLookupModelCaps(t *testing.T) {
-	reg := NewProviderRegistry()
-	reg.RegisterModels("prov", []ModelInfo{
-		{Label: "A", Name: "model-a", Caps: DisabledCaps(CapTemperature)},
-		{Label: "B", Name: "model-b"},
-	})
-
-	caps := reg.LookupModelCaps("prov", "model-a")
-	if caps.Supports(CapTemperature) {
-		t.Fatal("expected CapTemperature disabled for model-a")
-	}
-
-	caps = reg.LookupModelCaps("prov", "model-b")
-	if !caps.IsZero() {
-		t.Fatal("expected zero caps for model-b")
-	}
-
-	caps = reg.LookupModelCaps("prov", "nonexistent")
-	if !caps.IsZero() {
-		t.Fatal("expected zero caps for nonexistent model")
-	}
-}
-
 func TestNewFromConfig_ReturnsRawInstance_NoSpecWrap(t *testing.T) {
 	// Post-redesign contract: NewFromConfig is the bare-provider entry
 	// point; spec wrapping (caps / defaults / limits) is the resolver's
@@ -134,37 +111,3 @@ func TestNewFromConfig_ReturnsRawInstance_NoSpecWrap(t *testing.T) {
 		t.Fatal("NewFromConfig must return the raw provider instance unwrapped")
 	}
 }
-
-func TestRegisterModels_AutoPromotesDeprecatedCapsToSpec(t *testing.T) {
-	// Backward-compat contract: callers using the deprecated ModelInfo.Caps
-	// field (from before the Spec rename) should still see their caps
-	// reflected in LookupModelSpec — the registry auto-promotes the
-	// alias on registration.
-	reg := NewProviderRegistry()
-	reg.RegisterModels("p", []ModelInfo{
-		{Name: "legacy", Caps: DisabledCaps(CapTemperature)}, // old shape
-	})
-	spec := reg.LookupModelSpec("p", "legacy")
-	if spec.Caps.Supports(CapTemperature) {
-		t.Fatal("expected auto-promoted Caps→Spec.Caps to disable temperature")
-	}
-}
-
-func TestRegisterModels_SpecWinsOverDeprecatedCaps(t *testing.T) {
-	// When both fields are non-zero, Spec.Caps is authoritative.
-	reg := NewProviderRegistry()
-	reg.RegisterModels("p", []ModelInfo{
-		{
-			Name: "mixed",
-			Spec: ModelSpec{Caps: DisabledCaps(CapJSONMode)},
-			Caps: DisabledCaps(CapTemperature),
-		},
-	})
-	spec := reg.LookupModelSpec("p", "mixed")
-	if spec.Caps.Supports(CapJSONMode) {
-		t.Fatal("Spec.Caps should disable JSONMode")
-	}
-	if !spec.Caps.Supports(CapTemperature) {
-		t.Fatal("deprecated Caps should NOT have leaked in when Spec.Caps was set")
-	}
-}
diff --git a/sdk/llm/resolver_test.go b/sdk/llm/resolver_test.go
--- a/sdk/llm/resolver_test.go
+++ b/sdk/llm/resolver_test.go
@@ -157,7 +157,8 @@ func (p *probeProviderLLM) GenerateStream(_ context.Context, _ []Message, _ ...G
 
 // captureGenOpts returns a factory that records the GenerateOption set
 // applied by the most recent Generate call into *into. Used by caps
-// tests to assert which user-supplied options survived CapsMiddleware.
+// tests to assert which user-supplied options survived the capsLLM
+// wrapper installed by WithCaps / WithPolicyCaps.
 func captureGenOpts(reg *ProviderRegistry, provider string, into *GenerateOptions) {
 	reg.Register(provider, func(model string, _ map[string]any) (LLM, error) {
 		return &probeProviderLLM{model: model, onGen: func(opts []GenerateOption) {
@@ -391,14 +392,14 @@ func TestResolver_NoModelNoFallback(t *testing.T) {
 	}
 }
 
-func TestResolver_CapsMiddleware_Integration(t *testing.T) {
+func TestResolver_Caps_Integration(t *testing.T) {
 	store := newResolverMockStore()
 	reg := NewProviderRegistry()
 	reg.Register("test-prov", func(model string, config map[string]any) (LLM, error) {
 		return &resolverMockLLM{model: model}, nil
 	})
 	reg.RegisterModels("test-prov", []ModelInfo{
-		{Label: "Test Model", Name: "capped-model", Caps: DisabledCaps(CapTemperature)},
+		{Label: "Test Model", Name: "capped-model", Spec: ModelSpec{Caps: DisabledCaps(CapTemperature)}},
 	})
 	store.configs["test-prov"] = &ProviderConfig{Provider: "test-prov", Config: map[string]any{"api_key": "k"}}
 
@@ -517,7 +518,7 @@ func TestResolver_Caps_LayeredMerge(t *testing.T) {
 
 	// Layer 1: registry catalog disables temperature for "reason-model".
 	reg.RegisterModels("p", []ModelInfo{
-		{Name: "reason-model", Caps: DisabledCaps(CapTemperature)},
+		{Name: "reason-model", Spec: ModelSpec{Caps: DisabledCaps(CapTemperature)}},
 	})
 	// Layer 2: ProviderConfig.SpecOverride disables JSON mode for everything under p.
 	store.providers["p"] = &ProviderConfig{
@@ -554,26 +555,6 @@ func TestResolver_Caps_LayeredMerge(t *testing.T) {
 	}
 }
 
-func TestResolver_Caps_ExtraFromOption(t *testing.T) {
-	store := newLayeredMockStore()
-	reg := NewProviderRegistry()
-
-	var capturedOpts GenerateOptions
-	captureGenOpts(reg, "p", &capturedOpts)
-	store.providers["p"] = &ProviderConfig{Provider: "p", Config: map[string]any{"api_key": "k"}}
-
-	r := newResolverWithRegistry(store, reg, WithExtraCaps(DisabledCaps(CapTemperature)))
-	llm, err := r.Resolve(context.Background(), "p/m")
-	if err != nil {
-		t.Fatal(err)
-	}
-	temp := 0.7
-	_, _, _ = llm.Generate(context.Background(), nil, WithTemperature(temp))
-	if capturedOpts.Temperature != nil {
-		t.Fatalf("WithExtraCaps should disable temperature, got %v", *capturedOpts.Temperature)
-	}
-}
-
 // ---------------------------------------------------------------------------
 // Backward compatibility — animus-style provider-only stores
 // ---------------------------------------------------------------------------
diff --git a/sdk/model/message_test.go b/sdk/model/message_test.go
--- a/sdk/model/message_test.go
+++ b/sdk/model/message_test.go
@@ -175,3 +175,28 @@ func TestMarshalToolArgs_Error(t *testing.T) {
 		t.Fatal("MarshalToolArgs should return error for unsupported type")
 	}
 }
+
+func TestLastByRole(t *testing.T) {
+	msgs := []Message{
+		NewTextMessage(RoleUser, "u1"),
+		NewTextMessage(RoleAssistant, "a1"),
+		NewTextMessage(RoleUser, "u2"),
+		NewTextMessage(RoleAssistant, "a2"),
+	}
+
+	if m, ok := LastByRole(msgs, RoleUser); !ok || m.Content() != "u2" {
+		t.Fatalf("LastByRole(user) = (%q, %v), want (\"u2\", true)", m.Content(), ok)
+	}
+	if m, ok := LastByRole(msgs, RoleAssistant); !ok || m.Content() != "a2" {
+		t.Fatalf("LastByRole(assistant) = (%q, %v), want (\"a2\", true)", m.Content(), ok)
+	}
+	if _, ok := LastByRole(msgs, RoleSystem); ok {
+		t.Fatal("LastByRole(system) should report not-found on a transcript without system turns")
+	}
+	if _, ok := LastByRole(nil, RoleUser); ok {
+		t.Fatal("LastByRole on nil slice should report not-found")
+	}
+	if _, ok := LastByRole([]Message{}, RoleUser); ok {
+		t.Fatal("LastByRole on empty slice should report not-found")
+	}
+}
diff --git a/sdk/retrieval/pipeline/pipeline_test.go b/sdk/retrieval/pipeline/pipeline_test.go
--- a/sdk/retrieval/pipeline/pipeline_test.go
+++ b/sdk/retrieval/pipeline/pipeline_test.go
@@ -59,57 +59,6 @@ func TestPipelineMultiRetrieveAndRRF(t *testing.T) {
 	}
 }
 
-func TestPipelineReturnRawIncludesRetrieverHits(t *testing.T) {
-	ctx := context.Background()
-	idx := memory.New()
-	ns := "ns"
-	_ = idx.Upsert(ctx, ns, []retrieval.Doc{
-		{ID: "1", Content: "coffee tea", Vector: []float32{1, 0, 0}, Timestamp: time.Now()},
-		{ID: "2", Content: "unrelated", Vector: []float32{0, 1, 0}, Timestamp: time.Now()},
-	})
-	pipe := New(
-		MultiRetrieve{
-			"bm25":   {Mode: ModeBM25, TopK: 10},
-			"vector": {Mode: ModeVector, TopK: 10},
-		},
-		RRFFusion{K: 60},
-		Limit{TopK: 5},
-	)
-	resp, err := pipe.Run(ctx, idx, ns, retrieval.SearchRequest{
-		QueryText:   "coffee",
-		QueryVector: []float32{1, 0, 0},
-		TopK:        5,
-		ReturnRaw:   true,
-	})
-	if err != nil {
-		t.Fatal(err)
-	}
-	if len(resp.RawByRetriever) != 2 {
-		t.Fatalf("expected raw hits for 2 retrievers, got %+v", resp.RawByRetriever)
-	}
-	if len(resp.RawByRetriever["bm25"]) == 0 {
-		t.Fatalf("expected bm25 raw hits, got %+v", resp.RawByRetriever)
-	}
-	if len(resp.RawByRetriever["vector"]) == 0 {
-		t.Fatalf("expected vector raw hits, got %+v", resp.RawByRetriever)
-	}
-	if resp.Execution == nil {
-		t.Fatal("expected Execution to be populated when ReturnRaw=true")
-	}
-	if len(resp.Execution.Lanes) != 2 {
-		t.Fatalf("expected 2 lanes in Execution, got %+v", resp.Execution.Lanes)
-	}
-	for _, lane := range resp.Execution.Lanes {
-		raw, ok := resp.RawByRetriever[string(lane.Key)]
-		if !ok {
-			t.Fatalf("lane %q missing in RawByRetriever projection", lane.Key)
-		}
-		if len(raw) != len(lane.Hits) {
-			t.Fatalf("lane %q raw/exec mismatch: raw=%d exec=%d", lane.Key, len(raw), len(lane.Hits))
-		}
-	}
-}
-
 func TestPipelineDebugIncludeStagesRecordsTrace(t *testing.T) {
 	ctx := context.Background()
 	idx := memory.New()
@@ -142,9 +91,6 @@ func TestPipelineDebugIncludeStagesRecordsTrace(t *testing.T) {
 	if len(resp.Execution.Lanes) != 0 {
 		t.Fatalf("expected no lanes when IncludeLanes=false, got %+v", resp.Execution.Lanes)
 	}
-	if resp.RawByRetriever != nil {
-		t.Fatalf("RawByRetriever should remain nil when ReturnRaw=false, got %+v", resp.RawByRetriever)
-	}
 }
 
 func TestPipelineDebugIncludeLanesWithoutLegacyProjection(t *testing.T) {
@@ -170,9 +116,6 @@ func TestPipelineDebugIncludeLanesWithoutLegacyProjection(t *testing.T) {
 	if resp.Execution == nil || len(resp.Execution.Lanes) != 1 {
 		t.Fatalf("expected one lane in Execution, got %+v", resp.Execution)
 	}
-	if resp.RawByRetriever != nil {
-		t.Fatalf("RawByRetriever should only be populated by ReturnRaw, got %+v", resp.RawByRetriever)
-	}
 }
 
 func TestEntityBoost(t *testing.T) {
diff --git a/sdkx/tool/history/tools_test.go b/sdkx/tool/history/tools_test.go
--- a/sdkx/tool/history/tools_test.go
+++ b/sdkx/tool/history/tools_test.go
@@ -3,7 +3,6 @@ package history_test
 import (
 	"testing"
 
-	sdkhistory "github.com/GizClaw/flowcraft/sdk/history"
 	"github.com/GizClaw/flowcraft/sdk/tool"
 	historytool "github.com/GizClaw/flowcraft/sdkx/tool/history"
 )
@@ -18,18 +17,3 @@ func TestRegisterTools_RegistersBothNames(t *testing.T) {
 		}
 	}
 }
-
-// TypeAliasInterop verifies the Go type alias contract: a value of
-// the sdkx ToolDeps must be assignable to sdkhistory.ToolDeps without
-// conversion (and vice-versa). This guards against an accidental
-// future switch from `type Foo = sdkhistory.Foo` to `type Foo
-// sdkhistory.Foo`, which would silently break user code.
-func TestTypeAliasInterop(t *testing.T) {
-	var sdkx historytool.ToolDeps
-	var sdk sdkhistory.ToolDeps = sdkx
-	_ = sdk
-
-	var sdk2 sdkhistory.ToolDeps
-	var sdkx2 historytool.ToolDeps = sdk2
-	_ = sdkx2
-}
diff --git a/sdkx/tool/kanban/tools_test.go b/sdkx/tool/kanban/tools_test.go
--- a/sdkx/tool/kanban/tools_test.go
+++ b/sdkx/tool/kanban/tools_test.go
@@ -62,22 +62,15 @@ func TestSubmitTool_FromContext(t *testing.T) {
 	}
 }
 
-// Round-trip with sdk-side WithKanban: contexts installed via the
-// deprecated sdk helper must be readable by the sdkx KanbanFrom and
-// vice-versa during the v0.2.x → v0.3.0 transition.
-func TestContextInterop(t *testing.T) {
+// Round-trip with the sdkx-side WithKanban: contexts installed via
+// [tool.WithKanban] must be readable by [tool.KanbanFrom] (the
+// canonical helpers post-v0.3.0).
+func TestContextRoundTrip(t *testing.T) {
 	k := newKanban(t)
 
-	// sdk-installed → sdkx readable
-	ctx := sdkkanban.WithKanban(context.Background(), k)
+	ctx := tool.WithKanban(context.Background(), k)
 	if got := tool.KanbanFrom(ctx); got != k {
-		t.Errorf("sdk install / sdkx read: got %v want %v", got, k)
-	}
-
-	// sdkx-installed → sdk readable
-	ctx2 := tool.WithKanban(context.Background(), k)
-	if got := sdkkanban.KanbanFrom(ctx2); got != k {
-		t.Errorf("sdkx install / sdk read: got %v want %v", got, k)
+		t.Errorf("KanbanFrom round-trip: got %v want %v", got, k)
 	}
 }
EOF_114329324912
# Ensure patch file ends with a newline (some harnesses can drop the final newline).
printf '\n' >> "$TEST_PATCH_FILE"

# Fail fast if patch is malformed/unapplicable.
if ! git apply --stat "$TEST_PATCH_FILE"; then
  echo "ERROR: test patch appears malformed (git apply --stat failed); refusing to run tests" >&2
  rm -f "$TEST_PATCH_FILE"
  rc=2
  echo "OMNIGRIL_EXIT_CODE=$rc"
  exit "$rc"
fi
if ! git apply --check "$TEST_PATCH_FILE"; then
  echo "ERROR: test patch failed git apply --check; refusing to run tests" >&2
  rm -f "$TEST_PATCH_FILE"
  rc=2
  echo "OMNIGRIL_EXIT_CODE=$rc"
  exit "$rc"
fi
if ! git apply -v "$TEST_PATCH_FILE"; then
  echo "ERROR: failed to apply test patch; refusing to run tests" >&2
  rm -f "$TEST_PATCH_FILE"
  rc=2
  echo "OMNIGRIL_EXIT_CODE=$rc"
  exit "$rc"
fi
rm -f "$TEST_PATCH_FILE"

# --- Sanity check: ensure patch actually changed working tree (non-empty) ---
if [[ -z "$(git status --porcelain)" ]]; then
  echo "ERROR: test patch produced no working tree changes; refusing to run tests" >&2
  rc=2
  echo "OMNIGRIL_EXIT_CODE=$rc"
  exit "$rc"
fi

# --- Enforce deletions from the test patch and verify absent ---
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  rm -f -- "$f"
done
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  if [[ -e "$f" ]]; then
    echo "ERROR: deleted-by-patch file still exists after patch enforcement: $f" >&2
    rc=2
    echo "OMNIGRIL_EXIT_CODE=$rc"
    exit "$rc"
  fi
done

# --- Determine packages for runnable test files (dedupe) ---
pkgs=()
declare -A seen_pkg=()
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  d="$(dirname "$f")"
  if [[ -d "$d" ]]; then
    if [[ -z "${seen_pkg[$d]+x}" ]]; then
      pkgs+=("./$d")
      seen_pkg["$d"]=1
    fi
  fi
done

# --- Run tests (avoid cross-package resource conflicts with -p 1) ---
set +e
tmpjson="$(mktemp)"
if [[ "${#RUNNABLE_TEST_FILES[@]}" -eq 0 ]]; then
  echo "RUNNING: go test -p 1 ./... -json"
  go test -p 1 ./... -json | tee "$tmpjson"
  rc=${PIPESTATUS[0]}
else
  echo "RUNNING: go test -p 1 ${pkgs[*]} -json"
  go test -p 1 "${pkgs[@]}" -json | tee "$tmpjson"
  rc=${PIPESTATUS[0]}
fi
set -e

# --- Assert tests actually ran / output captured ---
if [[ ! -s "$tmpjson" ]]; then
  echo "ERROR: no go test output captured (tmpjson empty); tests may not have run" >&2
  rc=2
fi
if [[ "$rc" -ne 2 ]]; then
  if ! grep -qE '"Action":"(pass|fail|run|start)"' "$tmpjson" 2>/dev/null; then
    echo "ERROR: go test output captured but contains no JSON Action events; tests may not have run" >&2
    echo "GO_TEST_JSON_HEAD_BEGIN"
    head -n 5 "$tmpjson" || true
    echo "GO_TEST_JSON_HEAD_END"
    echo "GO_TEST_JSON_TAIL_BEGIN"
    tail -n 20 "$tmpjson" || true
    echo "GO_TEST_JSON_TAIL_END"
    rc=2
  fi
fi

# --- Summarize per target test file status (PASS/FAIL) with Go package normalization ---
declare -A import_to_rel=()
for p in "${pkgs[@]}"; do
  while IFS=$'\t' read -r ip dir; do
    if [[ -n "$ip" && -n "$dir" && "$dir" == /testbed/* ]]; then
      rel="${dir#/testbed/}"
      rel="${rel#./}"
      import_to_rel["$ip"]="$rel"
    fi
  done < <(go list -f '{{.ImportPath}}{{"\t"}}{{.Dir}}' "$p" 2>/dev/null || true)
done

normalize_pkg() {
  local p="$1"
  if [[ -n "${import_to_rel[$p]+x}" ]]; then
    echo "${import_to_rel[$p]}"
    return 0
  fi
  local module_path
  module_path="$(go list -m 2>/dev/null || true)"
  if [[ -n "$module_path" && "$p" == "$module_path"* ]]; then
    p="${p#"$module_path"}"
  fi
  p="${p#/}"
  p="${p#./}"
  echo "$p"
}

declare -A pkg_failed=()
declare -A pkg_seen=()
while IFS='|' read -r pkg action; do
  if [[ "$action" == "fail" ]]; then
    npkg="$(normalize_pkg "$pkg")"
    pkg_failed["$npkg"]=1
    pkg_seen["$npkg"]=1
  elif [[ "$action" == "pass" ]]; then
    npkg="$(normalize_pkg "$pkg")"
    pkg_seen["$npkg"]=1
  fi
done < <(
  sed -n     -e 's/.*"Package":"\([^"]*\)".*"Action":"\([^"]*\)".*/\1|\2/p'     -e 's/.*"Action":"\([^"]*\)".*"Package":"\([^"]*\)".*/\2|\1/p'     "$tmpjson"
)

echo "TARGET_TEST_FILE_RESULTS_BEGIN"
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if [[ "${#RUNNABLE_TEST_FILES[@]}" -eq 0 ]]; then
    echo "$f:SKIP(no-runnable-targets)"
    continue
  fi
  d="$(dirname "$f")"
  nd="$(normalize_pkg "$d")"
  if [[ -n "${pkg_failed[$nd]+x}" ]]; then
    echo "$f:FAIL"
  else
    if [[ "$rc" -ne 0 && -z "${pkg_seen[$nd]+x}" ]]; then
      echo "$f:FAIL"
    else
      echo "$f:PASS"
    fi
  fi
done
echo "TARGET_TEST_FILE_RESULTS_END"

echo "OMNIGRIL_EXIT_CODE=$rc"

# --- Cleanup: reset modified runnable/deleted paths back to base commit state ---
set +e
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${BASE_COMMIT}:$f" 2>/dev/null; then
    git checkout "${BASE_COMMIT}" -- "$f"
  else
    rm -f -- "$f"
  fi
done
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  if git cat-file -e "${BASE_COMMIT}:$f" 2>/dev/null; then
    git checkout "${BASE_COMMIT}" -- "$f"
  else
    rm -f -- "$f"
  fi
done
rm -f "$tmpjson"
set -e

exit "$rc"
