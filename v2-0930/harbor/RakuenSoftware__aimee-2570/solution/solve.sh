#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/dependencies/aimee-repositories.lock.json b/dependencies/aimee-repositories.lock.json
--- a/dependencies/aimee-repositories.lock.json
+++ b/dependencies/aimee-repositories.lock.json
@@ -166,7 +166,7 @@
       "placements": [
         "server"
       ],
-      "source_sha256": "a1193da0edfa1def6f19c0a3dc2fb4bf7702ceeee7cdbeadd66b8d996cad3a33",
+      "source_sha256": "bf114ba6d72348d8a58f4fbd68a5858306032fb7191e3f92e6c2a6ce80b93aeb",
       "runtime": "go",
       "principal_class": 1,
       "principal_ref": 10,
@@ -184,7 +184,8 @@
         6667,
         6668,
         6669,
-        6670
+        6670,
+        6671
       ]
     },
     {
diff --git a/server-go/cmd/aimee-module/main.go b/server-go/cmd/aimee-module/main.go
--- a/server-go/cmd/aimee-module/main.go
+++ b/server-go/cmd/aimee-module/main.go
@@ -118,6 +118,7 @@ func moduleConfig(executable string) (bus.ModuleProcessConfig, bool) {
 			{EventKind: delegates.EventLaunchArgs, StageID: delegates.StageLaunchArgs},
 			{EventKind: delegates.EventImageSpec, StageID: delegates.StageImageSpec},
 			{EventKind: delegates.EventIsolation, StageID: delegates.StageIsolation},
+			{EventKind: delegates.EventMayWrite, StageID: delegates.StageMayWrite},
 		}
 		config.Handler = delegates.Handle
 	case "tools":
diff --git a/server-go/modules/delegates/delegates.go b/server-go/modules/delegates/delegates.go
--- a/server-go/modules/delegates/delegates.go
+++ b/server-go/modules/delegates/delegates.go
@@ -68,6 +68,9 @@ func Handle(invocation bus.ModuleInvocation, request []byte) ([]byte, bus.Module
 	if invocation.StageID == StageIsolation {
 		return handleIsolation(invocation, request)
 	}
+	if invocation.StageID == StageMayWrite {
+		return handleMayWrite(invocation, request)
+	}
 	if invocation.StageID != StageInvoke || len(request) != messageLen ||
 		binary.LittleEndian.Uint32(request[0:4]) != requestMagic || request[4] != wireVersion ||
 		request[5] != 0 || request[7] != 0 || request[6] == 0 || request[6] > roleMax {
diff --git a/server-go/modules/delegates/promptwrites.go b/server-go/modules/delegates/promptwrites.go
new file mode 100644
--- /dev/null
+++ b/server-go/modules/delegates/promptwrites.go
@@ -0,0 +1,91 @@
+package delegates
+
+import "strings"
+
+// Whether a delegate may write, from its role AND what it was asked to do.
+//
+// Two inputs, one answer, decided together. The role's default is not the whole
+// story: a write role told to inspect something must not be handed a writable
+// tree, because the mount is the enforcement and there is nothing above it that
+// would stop the edit. Composing the two here means the answer that reaches the
+// worktree plan and the container spec is the same answer, rather than two
+// halves a caller recombines.
+
+// noWriteWholePrompt are phrases that rule out writing outright. They describe
+// the WHOLE task, so no later keyword rescues them: "read-only: fix the typo"
+// is a contradiction, and the safe reading of a contradiction is the one that
+// does not edit the user's files.
+var noWriteWholePrompt = []string{
+	"do not edit files",
+	"do not modify anything",
+	"do not write files",
+	"do not change files",
+	"do not make changes",
+	"read-only",
+	"read only",
+	"inspect only",
+	"analysis only",
+}
+
+// noWriteScoped are narrower prohibitions -- "do not edit the config" -- which
+// forbid something specific rather than everything. On their own they mean no
+// writing; alongside an explicit ask to create or change something, they are a
+// boundary on a task that IS a write task.
+var noWriteScoped = []string{
+	"do not edit", "do not modify", "do not write", "do not change",
+}
+
+// scopedWriteIntent rescues a scoped prohibition. Deliberately narrower than
+// writeIntent: it takes a clear ask, not any mention of a word like "edit".
+var scopedWriteIntent = []string{
+	"create", "new file", "add ", "add file", "implement ", "update",
+	"fix", "refactor", "delete", "remove",
+}
+
+// writeIntent is what asking for a change looks like.
+var writeIntent = []string{
+	"create", "new file", "add file", "edit", "modify", "update", "fix",
+	"implement", "write", "refactor", "delete", "remove",
+}
+
+func containsAnyFold(haystack string, needles []string) bool {
+	for _, n := range needles {
+		if strings.Contains(haystack, n) {
+			return true
+		}
+	}
+	return false
+}
+
+// PromptAllowsWrites reads a delegate's brief for whether it asks for changes.
+//
+// An EMPTY prompt allows writes: there is nothing to read, so this rule
+// abstains and the role decides alone. It is a narrowing rule, not a granting
+// one -- it can only ever take permission away from a role that had it.
+func PromptAllowsWrites(prompt string) bool {
+	if prompt == "" {
+		return true
+	}
+	lower := strings.ToLower(prompt)
+
+	if containsAnyFold(lower, noWriteWholePrompt) {
+		return false
+	}
+
+	// A scoped prohibition with no write asked for anywhere is a read-only task.
+	if containsAnyFold(lower, noWriteScoped) && !containsAnyFold(lower, scopedWriteIntent) {
+		return false
+	}
+
+	return containsAnyFold(lower, writeIntent)
+}
+
+// DelegateMayWrite is the composed answer: the role permits writing AND the
+// brief asks for it.
+//
+// Both must hold. The role alone would hand a writable tree to a review that
+// happens to run under a write role; the prompt alone would let any brief
+// mentioning "fix" write from a role that has no business doing so.
+func DelegateMayWrite(role, prompt string) bool {
+	return RoleIsWrite(role) && PromptAllowsWrites(prompt)
+}
diff --git a/server-go/modules/delegates/promptwrites_stage.go b/server-go/modules/delegates/promptwrites_stage.go
new file mode 100644
--- /dev/null
+++ b/server-go/modules/delegates/promptwrites_stage.go
@@ -0,0 +1,67 @@
+package delegates
+
+import (
+	"encoding/binary"
+
+	"github.com/JBailes/aimee/server-go/bus"
+)
+
+// Answering "may this delegate write?" in one call.
+//
+// The caller used to compose this from two answers -- the role's default and a
+// prompt rule of its own. Composing it here means the boolean that reaches the
+// worktree plan (stage 11) and the container spec (stage 12) is the same
+// boolean, decided once. Those stages take the composed answer precisely
+// because it is the one fact that must agree across them.
+
+const (
+	StageMayWrite uint32 = 15
+	EventMayWrite uint32 = 6671
+
+	mayWriteRequestMagic  uint32 = 0x51575744 /* "DWWQ" */
+	mayWriteResponseMagic uint32 = 0x53575744 /* "DWWS" */
+	mayWriteReqHeaderLen         = 16
+	mayWriteResponseLen          = 16
+
+	// A brief is carried whole because the rule reads its text; there is
+	// nothing smaller to send that preserves the answer.
+	mayWritePromptMax = 1 << 20
+)
+
+// handleMayWrite returns the composed permission, and its two halves.
+//
+// The halves travel too, not for the decision -- the caller must use MayWrite --
+// but because "the delegate could not edit anything" is otherwise indebuggable:
+// an operator needs to see whether the role or the brief withheld it.
+func handleMayWrite(invocation bus.ModuleInvocation, request []byte) ([]byte, bus.ModuleStatus) {
+	if len(request) < mayWriteReqHeaderLen ||
+		binary.LittleEndian.Uint32(request[0:4]) != mayWriteRequestMagic ||
+		request[4] != wireVersion {
+		return nil, bus.ModuleStatusInvalidRequest
+	}
+	roleLen := int(binary.LittleEndian.Uint32(request[8:12]))
+	promptLen := int(binary.LittleEndian.Uint32(request[12:16]))
+	if roleLen > roleMax || promptLen > mayWritePromptMax {
+		return nil, bus.ModuleStatusInvalidRequest
+	}
+
+	c := &economicsCursor{buf: request, at: mayWriteReqHeaderLen}
+	role := c.str(roleLen)
+	prompt := c.str(promptLen)
+	if c.bad || c.at != len(request) {
+		return nil, bus.ModuleStatusInvalidRequest
+	}
+	if invocation.Cancelled() {
+		return nil, bus.ModuleStatusCancelled
+	}
+
+	roleWrites := RoleIsWrite(role)
+	promptWrites := PromptAllowsWrites(prompt)
+
+	response := make([]byte, mayWriteResponseLen)
+	binary.LittleEndian.PutUint32(response[0:4], mayWriteResponseMagic)
+	putBool(response[4:8], roleWrites && promptWrites)
+	putBool(response[8:12], roleWrites)
+	putBool(response[12:16], promptWrites)
+	return response, bus.ModuleStatusOK
+}
diff --git a/src/modules/delegates/delegate_launch_args.c b/src/modules/delegates/delegate_launch_args.c
--- a/src/modules/delegates/delegate_launch_args.c
+++ b/src/modules/delegates/delegate_launch_args.c
@@ -101,3 +101,35 @@ int delegate_isolation_judge(const char *report, int probe_failed, int require_i
    return g_isolation(report, probe_failed, require_isolation, refuse, warn, is_error, reason,
                       reason_cap);
 }
+
+static delegate_may_write_fn g_may_write;
+
+void delegate_register_may_write_provider(delegate_may_write_fn provider)
+{
+   g_may_write = provider;
+}
+
+int delegate_may_write(const char *role, const char *prompt)
+{
+   if (!g_may_write)
+   {
+      LOG_ERROR("delegates",
+                "no may-write provider registered; treating the delegate as read-only");
+      return 0;
+   }
+   int may = 0, by_role = 0, by_prompt = 0;
+   if (g_may_write(role, prompt, &may, &by_role, &by_prompt) != 0)
+   {
+      LOG_ERROR("delegates",
+                "could not resolve write permission for role '%s'; "
+                "treating the delegate as read-only",
+                role ? role : "");
+      return 0;
+   }
+   if (!may)
+      LOG_INFO("delegates",
+               "delegate role '%s' is read-only for this turn (role permits=%d, "
+               "brief asks=%d)",
+               role ? role : "", by_role, by_prompt);
+   return may;
+}
diff --git a/src/modules/delegates/delegate_prompt.c b/src/modules/delegates/delegate_prompt.c
--- a/src/modules/delegates/delegate_prompt.c
+++ b/src/modules/delegates/delegate_prompt.c
@@ -193,6 +193,21 @@ static int has_create_intent(const char *prompt)
    return 0;
 }
 
+/* RETAINED FOR THE CLI ONLY, and duplicated in the module on purpose.
+ *
+ * The server no longer calls this: it asks the module (stage 15), which
+ * composes this rule with the role's default into one answer. The CLI still
+ * calls it because the CLI cannot reach the bus -- it registers no stage
+ * adapters -- and a fail-closed seam there would not fail closed usefully, it
+ * would just always say "read-only".
+ *
+ * That is not hypothetical. delegate_role_is_write() is already a seam with no
+ * provider in the CLI, so it returns 0 unconditionally there and the branch at
+ * cmd_agent_delegate.c that tests it is dead. Adding a second one would add a
+ * second silent misbehaviour rather than remove a duplicate.
+ *
+ * This copy goes when the CLI can reach the module. Until then it must track
+ * PromptAllowsWrites in server-go/modules/delegates/promptwrites.go. */
 int delegate_prompt_allows_writes(const char *prompt)
 {
    if (!prompt || !prompt[0])
diff --git a/src/modules/delegates/include/aimee/delegates/delegate_launch_args.h b/src/modules/delegates/include/aimee/delegates/delegate_launch_args.h
--- a/src/modules/delegates/include/aimee/delegates/delegate_launch_args.h
+++ b/src/modules/delegates/include/aimee/delegates/delegate_launch_args.h
@@ -68,4 +68,18 @@ int delegate_isolation_judge(const char *report, int probe_failed, int require_i
                              int *refuse, int *warn, int *is_error, char *reason,
                              size_t reason_cap);
 
+/* May this delegate write? The role and the brief, composed by the module.
+ *
+ * FAILS CLOSED: with no provider the answer is NO. A delegate that cannot be
+ * shown to be permitted does not get a writable tree -- the mount is the
+ * enforcement, so guessing yes is the one direction with no recovery. */
+typedef int (*delegate_may_write_fn)(const char *role, const char *prompt, int *may_write,
+                                     int *by_role, int *by_prompt);
+
+void delegate_register_may_write_provider(delegate_may_write_fn provider);
+
+/* Returns 1 when the delegate may write, 0 otherwise (including on any
+ * failure, which is logged). */
+int delegate_may_write(const char *role, const char *prompt);
+
 #endif
diff --git a/src/modules/delegates/include/aimee/delegates/module_api.h b/src/modules/delegates/include/aimee/delegates/module_api.h
--- a/src/modules/delegates/include/aimee/delegates/module_api.h
+++ b/src/modules/delegates/include/aimee/delegates/module_api.h
@@ -770,4 +770,57 @@ static inline int aimee_delegates_isolation_response_decode(const uint8_t *in, s
    return 0;
 }
 
+/* --- May write (stage 15): the role AND the brief, composed ---------------
+ *
+ * One answer, because it is the one fact stages 11 and 12 must agree on. The
+ * halves come back too, so a refusal is debuggable: "the delegate could not
+ * edit anything" is otherwise a mystery. */
+
+#define AIMEE_DELEGATES_EVENT_MAYWRITE          6671u
+#define AIMEE_DELEGATES_STAGE_MAYWRITE          15u
+#define AIMEE_DELEGATES_MAYWRITE_REQUEST_MAGIC  0x51575744u /* "DWWQ" */
+#define AIMEE_DELEGATES_MAYWRITE_RESPONSE_MAGIC 0x53575744u /* "DWWS" */
+#define AIMEE_DELEGATES_MAYWRITE_HEADER_LEN     16u
+#define AIMEE_DELEGATES_MAYWRITE_RESPONSE_LEN   16u
+#define AIMEE_DELEGATES_MAYWRITE_PROMPT_MAX     (1u << 20)
+
+/* Returns the encoded length, or 0 when it does not fit. */
+static inline size_t aimee_delegates_maywrite_request_encode(const char *role, const char *prompt,
+                                                             uint8_t *out, size_t cap)
+{
+   size_t role_len = role ? strlen(role) : 0;
+   size_t prompt_len = prompt ? strlen(prompt) : 0;
+   size_t total = AIMEE_DELEGATES_MAYWRITE_HEADER_LEN + role_len + prompt_len;
+   if (!out || cap < total || role_len > AIMEE_DELEGATES_ROLE_MAX ||
+       prompt_len > AIMEE_DELEGATES_MAYWRITE_PROMPT_MAX)
+      return 0;
+   memset(out, 0, AIMEE_DELEGATES_MAYWRITE_HEADER_LEN);
+   aimee_delegates_put_u32(out, AIMEE_DELEGATES_MAYWRITE_REQUEST_MAGIC);
+   out[4] = (uint8_t)AIMEE_DELEGATES_WIRE_VERSION;
+   aimee_delegates_put_u32(out + 8, (uint32_t)role_len);
+   aimee_delegates_put_u32(out + 12, (uint32_t)prompt_len);
+   if (role_len)
+      memcpy(out + AIMEE_DELEGATES_MAYWRITE_HEADER_LEN, role, role_len);
+   if (prompt_len)
+      memcpy(out + AIMEE_DELEGATES_MAYWRITE_HEADER_LEN + role_len, prompt, prompt_len);
+   return total;
+}
+
+/* `by_role` and `by_prompt` are optional and are for reporting only -- the
+ * decision is `may_write`. */
+static inline int aimee_delegates_maywrite_response_decode(const uint8_t *in, size_t len,
+                                                           int *may_write, int *by_role,
+                                                           int *by_prompt)
+{
+   if (!in || len != AIMEE_DELEGATES_MAYWRITE_RESPONSE_LEN || !may_write ||
+       aimee_delegates_get_u32(in) != AIMEE_DELEGATES_MAYWRITE_RESPONSE_MAGIC)
+      return -1;
+   *may_write = aimee_delegates_get_u32(in + 4) ? 1 : 0;
+   if (by_role)
+      *by_role = aimee_delegates_get_u32(in + 8) ? 1 : 0;
+   if (by_prompt)
+      *by_prompt = aimee_delegates_get_u32(in + 12) ? 1 : 0;
+   return 0;
+}
+
 #endif
diff --git a/src/modules/delegates/module.yaml b/src/modules/delegates/module.yaml
--- a/src/modules/delegates/module.yaml
+++ b/src/modules/delegates/module.yaml
@@ -87,6 +87,8 @@
     "server-go/modules/delegates/sandbox.go",
     "server-go/modules/delegates/isolation.go",
     "server-go/modules/delegates/isolation_stage.go",
+    "server-go/modules/delegates/promptwrites.go",
+    "server-go/modules/delegates/promptwrites_stage.go",
     "server-go/modules/delegates/sandboximage.go",
     "server-go/modules/delegates/sandboximage_stage.go",
     "server-go/modules/delegates/dockerargs.go",
@@ -117,6 +119,8 @@
     "server-go/modules/delegates/sandboxscratch_test.go",
     "server-go/modules/delegates/isolation_test.go",
     "server-go/modules/delegates/isolation_stage_test.go",
+    "server-go/modules/delegates/promptwrites_test.go",
+    "server-go/modules/delegates/promptwrites_stage_test.go",
     "server-go/modules/delegates/sandboximage_test.go",
     "server-go/modules/delegates/sandboximage_stage_test.go",
     "server-go/modules/delegates/dockerargs_test.go",
diff --git a/src/modules/process-contracts.json b/src/modules/process-contracts.json
--- a/src/modules/process-contracts.json
+++ b/src/modules/process-contracts.json
@@ -201,6 +201,11 @@
           "id": 14,
           "name": "delegate-isolation-verdict",
           "event_kind": 6670
+        },
+        {
+          "id": 15,
+          "name": "delegate-may-write",
+          "event_kind": 6671
         }
       ]
     },
diff --git a/src/server/module_stage_adapters.c b/src/server/module_stage_adapters.c
--- a/src/server/module_stage_adapters.c
+++ b/src/server/module_stage_adapters.c
@@ -891,6 +891,33 @@ static int delegate_isolation(const char *report, int probe_failed, int require_
                                                     reason, reason_cap);
 }
 
+/* The role and the brief, composed by the module into one permission. */
+static int delegate_may_write_adapter(const char *role, const char *prompt, int *may_write,
+                                      int *by_role, int *by_prompt)
+{
+   size_t prompt_len = prompt ? strlen(prompt) : 0;
+   size_t cap = AIMEE_DELEGATES_MAYWRITE_HEADER_LEN + AIMEE_DELEGATES_ROLE_MAX + prompt_len + 8;
+   uint8_t *request = malloc(cap);
+   if (!request)
+      return -1;
+   size_t request_len = aimee_delegates_maywrite_request_encode(role, prompt, request, cap);
+   if (request_len == 0)
+   {
+      free(request);
+      return -1;
+   }
+
+   uint8_t response[AIMEE_DELEGATES_MAYWRITE_RESPONSE_LEN];
+   uint32_t response_len = 0;
+   int rc = call_module(AIMEE_DELEGATES_EVENT_MAYWRITE, AIMEE_DELEGATES_STAGE_MAYWRITE, request,
+                        (uint32_t)request_len, response, sizeof(response), &response_len);
+   free(request);
+   if (rc != 0)
+      return -1;
+   return aimee_delegates_maywrite_response_decode(response, response_len, may_write, by_role,
+                                                   by_prompt);
+}
+
 static int tool_classify(const char *name, int *classification)
 {
    uint8_t request[AIMEE_TOOLS_REQUEST_LEN], response[AIMEE_TOOLS_RESPONSE_LEN];
@@ -1110,6 +1137,7 @@ void server_module_stage_adapters_configure(void)
    delegate_register_launch_args_provider(delegate_launch_args);
    delegate_register_image_spec_provider(delegate_image_spec);
    delegate_register_isolation_provider(delegate_isolation);
+   delegate_register_may_write_provider(delegate_may_write_adapter);
    agent_tools_register_classifier(tool_classify);
    ws_scope_register_ref_validator(workspace_validate);
    /* Same decision, same owner: webuser's runtime dir names a single path
diff --git a/src/server/server_compute.c b/src/server/server_compute.c
--- a/src/server/server_compute.c
+++ b/src/server/server_compute.c
@@ -34,6 +34,7 @@
 #include "kb_client.h"
 #include "kb_bandit.h"
 #include "db1/interaction_events.h"
+#include <aimee/delegates/delegate_launch_args.h>
 #include <aimee/delegates/delegate_role.h>
 #include "delegate_ensemble.h"
 #include "evidence_replay.h"
@@ -1230,8 +1231,11 @@ void delegate_worker(void *arg)
       if (resolved_prompt)
          prompt = resolved_prompt;
    }
-   int role_allows_writes = delegate_role_is_write(role);
-   int delegate_allows_writes = role_allows_writes && delegate_prompt_allows_writes(prompt);
+   /* ONE answer, composed by the module from the role AND the brief. This is the
+    * boolean the worktree plan and the container spec both consume, and it is
+    * the one fact they must agree on -- composing it in two places is how a
+    * delegate ends up planned read-only and mounted writable, or the reverse. */
+   int delegate_allows_writes = delegate_may_write(role, prompt);
    if (branch && !delegate_allows_writes)
    {
       delegation_compute_error(cctx, "read-only delegates must use the parent worktree; branch "
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
