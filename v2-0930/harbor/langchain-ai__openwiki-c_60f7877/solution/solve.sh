#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.changeset/cozy-baboons-turn.md b/.changeset/cozy-baboons-turn.md
deleted file mode 100644
--- a/.changeset/cozy-baboons-turn.md
+++ /dev/null
@@ -1,5 +0,0 @@
----
-"openwiki": patch
----
-
-chore: setup changeset tooling for automated releases
diff --git a/.changeset/gentle-comets-allow.md b/.changeset/gentle-comets-allow.md
deleted file mode 100644
--- a/.changeset/gentle-comets-allow.md
+++ /dev/null
@@ -1,5 +0,0 @@
----
-"openwiki": patch
----
-
-fix: allow comma in model id for gateway/proxy routing identifiers
diff --git a/.changeset/quick-foxes-jump.md b/.changeset/quick-foxes-jump.md
deleted file mode 100644
--- a/.changeset/quick-foxes-jump.md
+++ /dev/null
@@ -1,5 +0,0 @@
----
-"openwiki": patch
----
-
-fix: keep release workflow opt-in on forks
diff --git a/.changeset/salty-onions-wish.md b/.changeset/salty-onions-wish.md
deleted file mode 100644
--- a/.changeset/salty-onions-wish.md
+++ /dev/null
@@ -1,5 +0,0 @@
----
-"openwiki": patch
----
-
-fix: ignore stray oauth callback requests
diff --git a/.changeset/thin-mirrors-add.md b/.changeset/thin-mirrors-add.md
deleted file mode 100644
--- a/.changeset/thin-mirrors-add.md
+++ /dev/null
@@ -1,5 +0,0 @@
----
-"openwiki": patch
----
-
-feat: exclude paths from doc runs via .openwikiignore
diff --git a/.changeset/true-crabs-flash.md b/.changeset/true-crabs-flash.md
deleted file mode 100644
--- a/.changeset/true-crabs-flash.md
+++ /dev/null
@@ -1,5 +0,0 @@
----
-"openwiki": patch
----
-
-fix: route summarization history offload outside the documented repo
diff --git a/CHANGELOG.md b/CHANGELOG.md
new file mode 100644
--- /dev/null
+++ b/CHANGELOG.md
@@ -0,0 +1,23 @@
+# openwiki
+
+## 0.2.5
+
+### Patch Changes
+
+- [#514](https://github.com/langchain-ai/openwiki/pull/514) [`b8c510f`](https://github.com/langchain-ai/openwiki/commit/b8c510fce4afab5cc855390f67f833137183d646) Thanks [@colifran](https://github.com/colifran)! - chore: setup changeset tooling for automated releases
+
+- [#530](https://github.com/langchain-ai/openwiki/pull/530) [`1695c3f`](https://github.com/langchain-ai/openwiki/commit/1695c3f841a90543e5c292a871204faf5de0df9c) Thanks [@Monkey-wusky](https://github.com/Monkey-wusky)! - fix: allow comma in model id for gateway/proxy routing identifiers
+
+- [#533](https://github.com/langchain-ai/openwiki/pull/533) [`fdfdfd8`](https://github.com/langchain-ai/openwiki/commit/fdfdfd8825237abe879d019c9211245f0d17ce40) Thanks [@jyje](https://github.com/jyje)! - fix: keep release workflow opt-in on forks
+
+- [#481](https://github.com/langchain-ai/openwiki/pull/481) [`b3b0b43`](https://github.com/langchain-ai/openwiki/commit/b3b0b4320f184abbd686e05c85afdc0623c8e687) Thanks [@HwangJohn](https://github.com/HwangJohn)! - fix: ignore stray oauth callback requests
+
+- [#455](https://github.com/langchain-ai/openwiki/pull/455) [`161b6a4`](https://github.com/langchain-ai/openwiki/commit/161b6a47d64eda29d0eedf9bfff6fc3966a527c2) Thanks [@colifran](https://github.com/colifran)! - feat: implement native wiki visualizer for openwiki
+
+- [#165](https://github.com/langchain-ai/openwiki/pull/165) [`d6e5fbe`](https://github.com/langchain-ai/openwiki/commit/d6e5fbe2b09081fcaddc0419aa541b52bd3e30c0) Thanks [@n33levo](https://github.com/n33levo)! - feat: exclude paths from doc runs via .openwikiignore
+
+- [#504](https://github.com/langchain-ai/openwiki/pull/504) [`63c848c`](https://github.com/langchain-ai/openwiki/commit/63c848cecf506871411852318c391635d0e038d5) Thanks [@Mohith26](https://github.com/Mohith26)! - fix: route summarization history offload outside the documented repo
+
+- [#534](https://github.com/langchain-ai/openwiki/pull/534) [`aa417e1`](https://github.com/langchain-ai/openwiki/commit/aa417e14ddd4d74bf70b705367c31c7d164f9d3c) Thanks [@colifran](https://github.com/colifran)! - chore(deps): bump @langchain/core to ^1.2.4 to pick up the nested-tracer coalescing fix
+
+- [#500](https://github.com/langchain-ai/openwiki/pull/500) [`b469109`](https://github.com/langchain-ai/openwiki/commit/b469109d12ef005e2d86688b200e78d57c236027) Thanks [@colifran](https://github.com/colifran)! - chore: improve health telemetry to better understand and diagnose init and update failures
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -167,6 +167,28 @@ URL in Slack. If you have a fixed ngrok domain, run
 ignore that HTTPS override and keep using the local loopback callback,
 `http://127.0.0.1:53682/callback`.
 
+Visualize a generated wiki as an interactive graph with a live docs reader:
+
+```sh
+openwiki visualize
+```
+
+This serves the wiki in `./openwiki` on a local loopback address
+(`127.0.0.1`, never exposed on the network) and opens your browser to an
+interactive node graph backed by a live-reloading markdown reader; edits to the
+wiki files are picked up automatically while the server runs. Pass a path to
+visualize a different wiki directory, `--port <port>` to choose the port (it
+increments on conflict; default `4321`), and `--no-open` to leave the browser
+alone:
+
+```sh
+openwiki visualize openwiki --port 4400 --no-open
+```
+
+The page loads its graph, markdown, and diagram libraries from a public CDN, so
+an internet connection is required even though the server itself is local. Press
+Ctrl-C to stop it.
+
 Bare `openwiki` runs in code mode for the current repository. It creates initial repository documentation in `openwiki/` when no wiki exists. Use `openwiki personal` for the local general-purpose wiki in `~/.openwiki/wiki/`. By default, the CLI stays open after each run so you can send follow-up messages. Use `-p` or `--print` for a one-shot non-interactive run that prints the final assistant output.
 
 Bare `openwiki --init` and `openwiki --update` default to code mode and operate on repository documentation. Use the `personal` positional mode or `--mode personal` to initialize or update the local personal brain wiki.
diff --git a/openwiki/.last-update.json b/openwiki/.last-update.json
--- a/openwiki/.last-update.json
+++ b/openwiki/.last-update.json
@@ -1,7 +1,7 @@
 {
-  "updatedAt": "2026-07-30T08:58:20.872Z",
+  "updatedAt": "2026-07-31T09:04:11.703Z",
   "command": "update",
-  "gitHead": "3076d557f8a146e54cf0c6f3238f31a8d99a0537",
+  "gitHead": "63c848cecf506871411852318c391635d0e038d5",
   "model": "z-ai/glm-5.2",
   "status": "complete",
   "language": "en"
diff --git a/openwiki/agent/workflow.md b/openwiki/agent/workflow.md
--- a/openwiki/agent/workflow.md
+++ b/openwiki/agent/workflow.md
@@ -20,7 +20,7 @@ The documentation agent is implemented in `src/agent/`. It takes a command (`cha
 5. Snapshot the current `openwiki/` content hash (before the run).
 6. Build the system prompt and user prompt.
 7. Create the provider-specific model client (`ChatAnthropic`, `ChatOpenRouter`, or `ChatOpenAI`).
-8. Create a DeepAgents `LocalShellBackend` rooted at the repository with a SQLite checkpointer, then attach OKF index middleware (`src/agent/okf-middleware.ts`) and translation middleware (`src/agent/translation-middleware.ts`). The OKF middleware migrates front matter before the agent runs, validates writes, and synchronizes `index.md` files after; the translation middleware translates eligible pages when the output language has changed.
+8. Create a DeepAgents `LocalShellBackend` rooted at the repository with a SQLite checkpointer, wrap it in a `CompositeBackend` via `createAgentBackend()` that mounts `/skills/` and `/conversation_history/` outside the documented repo, then attach OKF index middleware (`src/agent/okf-middleware.ts`) and translation middleware (`src/agent/translation-middleware.ts`). The `/conversation_history/` mount routes the DeepAgents summarization middleware's history offload to `~/.openwiki/conversation_history` so it succeeds even on docs-only runs (without it, the docs-only guard refuses the offload and summarization silently degrades — #496). `AGENT_FILESYSTEM_PERMISSIONS` denies the model's own writes to both `/skills/**` and `/conversation_history/**`. The OKF middleware migrates front matter before the agent runs, validates writes, and synchronizes `index.md` files after; the translation middleware translates eligible pages when the output language has changed.
 9. Stream messages and tool events back to the CLI. `parseStreamEvent()` in `src/agent/index.ts` normalizes the LangGraph protocol stream into `OpenWikiRunEvent` objects. `extractContentBlockText()` filters out non-text content blocks — `tool`, `reasoning`, `file`, and `image` types — so raw base64 payloads from file/image blocks never leak into the terminal output. Text blocks pass through normally.
 10. For `init` and `update`, compare the post-run content snapshot to the pre-run snapshot. Write `openwiki/.last-update.json` **only if the content changed** — or if the previous run was interrupted and this run completed, to clear the stale status. If the run fails mid-stream, the catch block writes metadata with `status: "interrupted"` so the next update retries instead of skipping as a no-op. After the run (success or failure), `recordRunSafe()` in `src/telemetry/` emits a single `openwiki_run` PostHog event with mode, provider, outcome, and latency.
 
@@ -139,6 +139,7 @@ The same agent runtime is the wiki-generation backend invoked by the [DeepSWE ev
 - Credential loading happens before model resolution; changes there affect both onboarding and agent startup.
 - When adding a provider, add a branch in `createModel()` and ensure the API key env key is checked in `ensureProviderKey()`. OAuth-based providers (like `openai-chatgpt`) skip `ensureProviderKey()` and instead require a token refresh step before `createModel()` is called. Providers without an API key (like `gemini-enterprise`) declare their required env keys (e.g. `projectEnvKey`) in `PROVIDER_CONFIGS` and are gated by `getMissingProviderEnvKey()` instead. External-CLI-auth providers (like `copilot`) declare `authMethod: "external-cli"` and an `externalCliAuthAdapter`; `resolveExternalCliCredential()` in `src/external-cli-auth.ts` probes the CLI at startup and injects the token into `process.env` for the current process only. AWS SDK providers (like `bedrock`) declare `authMethod: "aws-sdk"` and delegate credential resolution to the AWS SDK chain, accepting standard AWS env vars, OIDC/web identity, IAM roles, or SSO profiles in addition to legacy Bedrock-specific keys.
 - The DeepAgents backend is configured with `virtualMode: true`, which is important for documentation-only behavior. The custom `OpenWikiLocalShellBackend` in `src/agent/docs-only-backend.ts` adds docs-only write guards that restrict writes to the `openwiki/` directory in docs-only mode.
+- `createAgentBackend()` wraps the wiki backend in a `CompositeBackend` with `/skills/` and `/conversation_history/` mounts. `CONVERSATION_HISTORY_MOUNT` must stay in sync with deepagents' hard-coded `/conversation_history` default (there is no override); a dependency bump that moves that default silently reintroduces #496, so the offload test suite includes a drift probe that drives the installed `createSummarizationMiddleware` against a recording backend. Both mounts are denied to the model's filesystem tools via `AGENT_FILESYSTEM_PERMISSIONS`; do not loosen those deny rules without closing the prompt-injection path they guard.
 
 ## Source map
 
diff --git a/openwiki/architecture/overview.md b/openwiki/architecture/overview.md
--- a/openwiki/architecture/overview.md
+++ b/openwiki/architecture/overview.md
@@ -69,7 +69,16 @@ Credential gating before model creation uses `getMissingProviderEnvKey()` in `sr
 
 ### DeepAgents backend and middleware
 
-The agent uses a DeepAgents `LocalShellBackend` rooted at the repository, configured with `virtualMode: true`, `maxOutputBytes: 100_000`, and a 120 second timeout. A SQLite checkpointer (`~/.openwiki/openwiki.sqlite`) persists conversation threads keyed by a hash of the repository path. The agent runtime attaches two middleware layers:
+The agent uses a DeepAgents `LocalShellBackend` rooted at the repository, configured with `virtualMode: true`, `maxOutputBytes: 100_000`, and a 120 second timeout. A SQLite checkpointer (`~/.openwiki/openwiki.sqlite`) persists conversation threads keyed by a hash of the repository path.
+
+`createAgentBackend()` in `src/agent/index.ts` wraps that wiki backend in a DeepAgents `CompositeBackend` that layers two read-only virtual mounts on top of the documented repository:
+
+- `/skills/` — the bundled and user skills under `~/.openwiki/skills` (populated by `src/agent/skills.ts`).
+- `/conversation_history/` — the DeepAgents summarization middleware's history offload, routed to `~/.openwiki/conversation_history` (created by `ensureOpenWikiHome()` in `src/openwiki-home.ts`). `createDeepAgent` exposes no way to override the `/conversation_history` default prefix, so the mount prefix is kept in sync with it via the exported `CONVERSATION_HISTORY_MOUNT` constant. Routing the offload outside the repository is what lets it succeed on docs-only `--init`/`--update` runs: without the mount, the docs-only write guard refuses the offload write, that refusal is non-fatal, and summarization silently degrades — narrowing coverage on large repositories while the run still exits 0 (#496).
+
+Both mounts are denied to the model's own filesystem tools via `AGENT_FILESYSTEM_PERMISSIONS` (`/skills/**` and `/conversation_history/**`, `mode: "deny"` for writes). The summarization middleware writes directly through the backend, which agent-layer permissions do not affect, so the offload keeps working while prompt-injected `write_file` calls into either mount are refused.
+
+The agent runtime attaches two middleware layers:
 
 - **OKF index middleware** (`src/agent/okf-middleware.ts`): migrates existing pages to valid OKF front matter before the agent runs, validates front matter on every write, and synchronizes directory `index.md` files after the run. It also validates Mermaid fences via `src/mermaid/wiki.ts` after the agent finishes.
 - **Translation middleware** (`src/agent/translation-middleware.ts`): when the output language differs from the wiki's current language, translates all eligible pages before the agent runs. Pages marked `openwiki_translation_pending` from a prior failed run are retranslated individually. The middleware tags its LLM calls with `langsmith:nostream` so translation output does not scroll past in the TUI token stream.
@@ -107,7 +116,7 @@ The current design reflects a documentation product rather than a general-purpos
 - **OKF compliance** (`src/okf/`): `frontmatter.ts` validates and migrates YAML front matter, `index-labels.ts` localizes directory index headings by BCP-47 language, and `index-sync.ts` deterministically generates and synchronizes every `index.md` after a run. The OKF middleware (`src/agent/okf-middleware.ts`) ties these into the agent lifecycle.
 - **Mermaid validation** (`src/mermaid/`): `fences.ts` extracts Mermaid code fences from wiki pages, `validate.ts` parses and validates them, and `wiki.ts` repairs broken fences by converting them to plain text fences with an HTML comment explaining the parse error. The OKF middleware calls `validateWikiMermaid()` after every run.
 - **Telemetry** (`src/telemetry/`): emits a single `openwiki_run` PostHog event per run with mode, provider, outcome, latency, and configured connectors. `gates.ts` checks `OPENWIKI_TELEMETRY_DISABLED` / `DO_NOT_TRACK` for opt-out and uses `ci-info` to tag CI runs with a sentinel distinct ID so ephemeral runners never inflate install counts. `record-run-safe.ts` wraps the send with a 3-second flush timeout so telemetry can never stall the CLI.
-- **Skills** (`src/agent/skills.ts`): bundles the `skills/` directory into the OpenWiki home and exposes it to the agent as a `/skills/` filesystem backend with write access denied. Each bundled skill is staged in a unique scratch directory and swapped into place with an atomic `rename`, so repeated or overlapping `--init` syncs are idempotent — a concurrent install that lands first is accepted as success rather than racing with `EEXIST` or `ENOTEMPTY` errors.
+- **Skills** (`src/agent/skills.ts`): bundles the `skills/` directory into the OpenWiki home and exposes it to the agent as the `/skills/` virtual mount on the `CompositeBackend` built by `createAgentBackend()` (see [DeepAgents backend and middleware](#deepagents-backend-and-middleware)). Write access to `/skills/**` is denied to the model via `AGENT_FILESYSTEM_PERMISSIONS`. Each bundled skill is staged in a unique scratch directory and swapped into place with an atomic `rename`, so repeated or overlapping `--init` syncs are idempotent — a concurrent install that lands first is accepted as success rather than racing with `EEXIST` or `ENOTEMPTY` errors.
 - **Diagnostics and redaction** (`src/diagnostics.ts`): redacts secrets from error messages, headers, and provider responses before they are shown to the user or written to logs. It matches exact secret values from the environment and known token shapes (`sk-…`, `Bearer …`, `ls…`).
 
 ## Things to watch when editing
diff --git a/package.json b/package.json
--- a/package.json
+++ b/package.json
@@ -1,6 +1,6 @@
 {
   "name": "openwiki",
-  "version": "0.2.4",
+  "version": "0.2.5",
   "description": "A CLI that uses a DeepAgents documentation agent to generate and maintain an OpenWiki for a codebase.",
   "license": "MIT",
   "type": "module",
@@ -35,7 +35,7 @@
   ],
   "scripts": {
     "openwiki": "node dist/cli.js",
-    "build": "tsc -p tsconfig.json",
+    "build": "tsc -p tsconfig.json && tsc -p tsconfig.client.json",
     "changeset:version": "changeset version",
     "clean": "node -e \"require('fs').rmSync('dist', { recursive: true, force: true })\"",
     "coverage": "vitest run --coverage",
@@ -49,14 +49,14 @@
     "release": "pnpm run build && changeset publish",
     "start": "node dist/cli.js",
     "test": "vitest run",
-    "typecheck": "tsc --noEmit -p tsconfig.json"
+    "typecheck": "tsc --noEmit -p tsconfig.json && tsc --noEmit -p tsconfig.client.json"
   },
   "dependencies": {
     "@anthropic-ai/vertex-sdk": "^0.19.0",
     "@aws-sdk/client-bedrock-runtime": "^3.1080.0",
     "@langchain/anthropic": "^1.5.1",
     "@langchain/aws": "^1.4.2",
-    "@langchain/core": "^1.2.1",
+    "@langchain/core": "^1.2.4",
     "@langchain/google": "^0.2.1",
     "@langchain/langgraph-checkpoint-sqlite": "^1.0.3",
     "@langchain/openai": "^1.5.5",
diff --git a/pnpm-lock.yaml b/pnpm-lock.yaml
--- a/pnpm-lock.yaml
+++ b/pnpm-lock.yaml
@@ -16,31 +16,31 @@ importers:
         version: 3.1080.0
       '@langchain/anthropic':
         specifier: ^1.5.1
-        version: 1.5.1(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
+        version: 1.5.1(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
       '@langchain/aws':
         specifier: ^1.4.2
-        version: 1.4.2(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
+        version: 1.4.2(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
       '@langchain/core':
-        specifier: ^1.2.1
-        version: 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+        specifier: ^1.2.4
+        version: 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
       '@langchain/google':
         specifier: ^0.2.1
-        version: 0.2.1(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
+        version: 0.2.1(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
       '@langchain/langgraph-checkpoint-sqlite':
         specifier: ^1.0.3
-        version: 1.0.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@langchain/langgraph-checkpoint@1.1.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)))
+        version: 1.0.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@langchain/langgraph-checkpoint@1.1.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)))
       '@langchain/openai':
         specifier: ^1.5.5
-        version: 1.5.5(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)
+        version: 1.5.5(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)
       '@langchain/openrouter':
         specifier: ^0.4.3
-        version: 0.4.3(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3)
+        version: 0.4.3(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3)
       '@langchain/protocol':
         specifier: ^0.0.18
         version: 0.0.18
       '@langchain/tavily':
         specifier: 1.2.0
-        version: 1.2.0(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
+        version: 1.2.0(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
       ci-info:
         specifier: ^4.4.0
         version: 4.4.0
@@ -52,7 +52,7 @@ importers:
         version: 3.24.0
       deepagents:
         specifier: ^1.11.1
-        version: 1.11.1(7f1e56310efb158954ec1f843ef153ef)
+        version: 1.11.1(36530d928ffe7026ae43c7a393ecd4c9)
       google-auth-library:
         specifier: ^10.9.0
         version: 10.9.0
@@ -61,7 +61,7 @@ importers:
         version: 5.2.1(@types/react@18.3.31)(react@18.3.1)
       langchain:
         specifier: ^1.5.3
-        version: 1.5.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(react@18.3.1)(ws@8.21.0)
+        version: 1.5.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(react@18.3.1)(ws@8.21.0)
       langsmith:
         specifier: ^0.8.3
         version: 0.8.3(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
@@ -655,8 +655,8 @@ packages:
     peerDependencies:
       '@langchain/core': ^1.0.0
 
-  '@langchain/core@1.2.1':
-    resolution: {integrity: sha512-NNG/cC5FGuHDOAP56h0ddp8Rfk8p+othWzEK5RV9JIG6RvnF5vGa5r0AEGtKfQieed7s1kC42GuIzVOBvMBL/g==}
+  '@langchain/core@1.2.4':
+    resolution: {integrity: sha512-GIrJktdsFPx8gM0C3VyikkeYGZAV7iRIzUJuS5tFatiKLExybou0LI0MuxH9kksN38quyfWdQDl20lIEAEVkVA==}
     engines: {node: '>=20'}
 
   '@langchain/google@0.2.1':
@@ -3451,21 +3451,21 @@ snapshots:
       '@jridgewell/resolve-uri': 3.1.2
       '@jridgewell/sourcemap-codec': 1.5.5
 
-  '@langchain/anthropic@1.5.1(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
+  '@langchain/anthropic@1.5.1(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
     dependencies:
       '@anthropic-ai/sdk': 0.103.0(zod@4.4.3)
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
       zod: 4.4.3
 
-  '@langchain/aws@1.4.2(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
+  '@langchain/aws@1.4.2(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
     dependencies:
       '@aws-sdk/client-bedrock-agent-runtime': 3.1080.0
       '@aws-sdk/client-bedrock-runtime': 3.1080.0
       '@aws-sdk/client-kendra': 3.1080.0
       '@aws-sdk/credential-provider-node': 3.972.63
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
 
-  '@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)':
+  '@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)':
     dependencies:
       '@cfworker/json-schema': 4.1.1
       '@standard-schema/spec': 1.1.0
@@ -3481,40 +3481,40 @@ snapshots:
       - openai
       - ws
 
-  '@langchain/google@0.2.1(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
+  '@langchain/google@0.2.1(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
       eventsource-parser: 3.1.0
       google-auth-library: 10.9.0
       jose: 6.2.3
     transitivePeerDependencies:
       - supports-color
 
-  '@langchain/langgraph-checkpoint-sqlite@1.0.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@langchain/langgraph-checkpoint@1.1.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)))':
+  '@langchain/langgraph-checkpoint-sqlite@1.0.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@langchain/langgraph-checkpoint@1.1.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)))':
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
-      '@langchain/langgraph-checkpoint': 1.1.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/langgraph-checkpoint': 1.1.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
       better-sqlite3: 12.11.1
 
-  '@langchain/langgraph-checkpoint@1.1.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
+  '@langchain/langgraph-checkpoint@1.1.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
 
-  '@langchain/langgraph-sdk@1.9.25(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)':
+  '@langchain/langgraph-sdk@1.9.25(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)':
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
       '@langchain/protocol': 0.0.18
       '@types/json-schema': 7.0.15
       p-queue: 9.3.0
       p-retry: 7.1.1
     optionalDependencies:
       react: 18.3.1
 
-  '@langchain/langgraph@1.4.7(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)(zod@4.4.3)':
+  '@langchain/langgraph@1.4.7(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)(zod@4.4.3)':
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
-      '@langchain/langgraph-checkpoint': 1.1.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
-      '@langchain/langgraph-sdk': 1.9.25(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/langgraph-checkpoint': 1.1.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
+      '@langchain/langgraph-sdk': 1.9.25(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)
       '@langchain/protocol': 0.0.18
       '@standard-schema/spec': 1.1.0
       zod: 4.4.3
@@ -3524,9 +3524,9 @@ snapshots:
       - svelte
       - vue
 
-  '@langchain/openai@1.5.3(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)':
+  '@langchain/openai@1.5.3(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)':
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
       js-tiktoken: 1.0.21
       openai: 6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3)
       zod: 4.4.3
@@ -3536,9 +3536,9 @@ snapshots:
       - '@smithy/signature-v4'
       - ws
 
-  '@langchain/openai@1.5.5(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)':
+  '@langchain/openai@1.5.5(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)':
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
       js-tiktoken: 1.0.21
       openai: 6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3)
       zod: 4.4.3
@@ -3548,10 +3548,10 @@ snapshots:
       - '@smithy/signature-v4'
       - ws
 
-  '@langchain/openrouter@0.4.3(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3)':
+  '@langchain/openrouter@0.4.3(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3)':
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
-      '@langchain/openai': 1.5.3(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/openai': 1.5.3(@aws-sdk/credential-provider-node@3.972.63)(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(@smithy/signature-v4@5.6.2)(ws@8.21.0)
       eventsource-parser: 3.1.0
       openai: 6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3)
     transitivePeerDependencies:
@@ -3563,9 +3563,9 @@ snapshots:
 
   '@langchain/protocol@0.0.18': {}
 
-  '@langchain/tavily@1.2.0(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
+  '@langchain/tavily@1.2.0(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))':
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
       zod: 4.4.3
 
   '@manypkg/find-root@1.1.0':
@@ -4382,14 +4382,14 @@ snapshots:
 
   deep-is@0.1.4: {}
 
-  deepagents@1.11.1(7f1e56310efb158954ec1f843ef153ef):
+  deepagents@1.11.1(36530d928ffe7026ae43c7a393ecd4c9):
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
-      '@langchain/langgraph': 1.4.7(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)(zod@4.4.3)
-      '@langchain/langgraph-checkpoint': 1.1.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
-      '@langchain/langgraph-sdk': 1.9.25(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/langgraph': 1.4.7(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)(zod@4.4.3)
+      '@langchain/langgraph-checkpoint': 1.1.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
+      '@langchain/langgraph-sdk': 1.9.25(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)
       fast-glob: 3.3.3
-      langchain: 1.5.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(react@18.3.1)(ws@8.21.0)
+      langchain: 1.5.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(react@18.3.1)(ws@8.21.0)
       langsmith: 0.8.3(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
       micromatch: 4.0.8
       yaml: 2.9.0
@@ -4890,11 +4890,11 @@ snapshots:
 
   khroma@2.1.0: {}
 
-  langchain@1.5.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(react@18.3.1)(ws@8.21.0):
+  langchain@1.5.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(react@18.3.1)(ws@8.21.0):
     dependencies:
-      '@langchain/core': 1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
-      '@langchain/langgraph': 1.4.7(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)(zod@4.4.3)
-      '@langchain/langgraph-checkpoint': 1.1.3(@langchain/core@1.2.1(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
+      '@langchain/core': 1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
+      '@langchain/langgraph': 1.4.7(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))(react@18.3.1)(zod@4.4.3)
+      '@langchain/langgraph-checkpoint': 1.1.3(@langchain/core@1.2.4(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0))
       langsmith: 0.8.3(openai@6.45.0(@aws-sdk/credential-provider-node@3.972.63)(@smithy/signature-v4@5.6.2)(ws@8.21.0)(zod@4.4.3))(ws@8.21.0)
       zod: 4.4.3
     transitivePeerDependencies:
diff --git a/pnpm-workspace.yaml b/pnpm-workspace.yaml
--- a/pnpm-workspace.yaml
+++ b/pnpm-workspace.yaml
@@ -2,6 +2,7 @@ allowBuilds:
   better-sqlite3: true
   esbuild: true
 minimumReleaseAgeExclude:
+  - "@langchain/core@1.2.4"
   - "@langchain/openai"
   - "@langchain/openai@1.5.4"
   - "@langchain/openai@1.5.5"
diff --git a/src/agent/index.ts b/src/agent/index.ts
--- a/src/agent/index.ts
+++ b/src/agent/index.ts
@@ -127,13 +127,15 @@ import {
   removeTemporaryPlanFile,
   shouldCheckUpdateNoop,
 } from "./utils.js";
-import { classifyError, recordRunSafe } from "../telemetry/index.js";
+import { inStage, inStageSync, tagErrorStage } from "../telemetry/index.js";
+import type { RunTelemetryContext } from "../telemetry/index.js";
 import { OpenWikiIgnore } from "./openwiki-ignore.js";
 
 export async function runOpenWikiAgent(
   command: OpenWikiCommand,
   cwd = openWikiLocalWikiDir,
   options: OpenWikiRunOptions = {},
+  telemetryContext: RunTelemetryContext = {},
 ): Promise<OpenWikiRunResult> {
   const outputMode = options.outputMode ?? "local-wiki";
   const runtimeCwd = options.outputMode ? cwd : openWikiLocalWikiDir;
@@ -170,10 +172,10 @@ export async function runOpenWikiAgent(
       emitDebug(options, `update.noop gitHead=${noopStatus.gitHead}`);
       options.onEvent?.({ type: "text", text: message });
 
-      await recordRunSafe(command, options, {
-        provider: resolveConfiguredProvider(),
-        outcome: "noop",
-      });
+      // The single telemetry boundary (withRunTelemetry) owns the record; publish
+      // the short-circuit outcome and provider onto the shared context and return.
+      telemetryContext.provider = resolveConfiguredProvider();
+      telemetryContext.outcome = "noop";
 
       return {
         command,
@@ -189,14 +191,55 @@ export async function runOpenWikiAgent(
 
   const debugFetchCapture = installOpenRouterDebugFetch(options);
 
-  // Resolved inside the try so a failure during resolution (missing key,
-  // invalid model, missing base URL) is still recorded. They may be undefined
-  // in the catch if resolution threw before assigning them.
-  let provider: OpenWikiProvider | undefined;
-  let modelId: string | undefined;
+  try {
+    // Published onto the shared context the instant the provider is resolved, so a
+    // failure later in the run still attributes the provider. It stays undefined
+    // only if the very first resolution step throws. The single telemetry boundary
+    // (withRunTelemetry) reads this context to record the run.
+    const config = await resolveRunConfig(options, (resolved) => {
+      telemetryContext.provider = resolved;
+    });
+
+    return await runOpenWikiAgentCore(
+      command,
+      runtimeCwd,
+      options,
+      config.provider,
+      config.modelId,
+      config.providerRetryAttempts,
+      openWikiIgnore,
+    );
+  } catch (error) {
+    // Enrich the error for the CLI's debug/auth UI, then rethrow. The telemetry
+    // record is owned by withRunTelemetry, which reads the stage/class tags this
+    // error already carries.
+    attachOpenRouterDebugInfo(error, debugFetchCapture.getLastFailure());
+
+    throw error;
+  } finally {
+    debugFetchCapture.restore();
+  }
+}
 
+/**
+ * Resolves everything the run needs before the agent is built: provider,
+ * credentials, model id, and retry count. Any throw here is tagged `config` so
+ * the failure telemetry locates it to the resolution stage. `onProviderResolved`
+ * fires the moment the provider is known, letting the caller attribute a failure
+ * that happens later in resolution to the right provider.
+ */
+async function resolveRunConfig(
+  options: OpenWikiRunOptions,
+  onProviderResolved: (provider: OpenWikiProvider) => void,
+): Promise<{
+  provider: OpenWikiProvider;
+  modelId: string;
+  providerRetryAttempts: number;
+}> {
   try {
-    provider = resolveConfiguredProvider();
+    const provider = resolveConfiguredProvider();
+    onProviderResolved(provider);
+
     const providerBaseUrl = resolveProviderBaseUrl(provider);
     emitDebug(options, `provider=${provider}`);
     if (providerBaseUrl) {
@@ -227,39 +270,15 @@ export async function runOpenWikiAgent(
       emitDebug(options, "chatgpt.token=fresh");
     }
 
-    modelId = resolveModelId(options, provider);
+    const modelId = resolveModelId(options, provider);
     emitDebug(options, `model=${modelId}`);
     const providerRetryAttempts = resolveProviderRetryAttempts();
     emitDebug(options, `provider.retryAttempts=${providerRetryAttempts}`);
 
-    const result = await runOpenWikiAgentCore(
-      command,
-      runtimeCwd,
-      options,
-      provider,
-      modelId,
-      providerRetryAttempts,
-      openWikiIgnore,
-    );
-
-    await recordRunSafe(command, options, {
-      provider,
-      outcome: "success",
-    });
-
-    return result;
+    return { provider, modelId, providerRetryAttempts };
   } catch (error) {
-    attachOpenRouterDebugInfo(error, debugFetchCapture.getLastFailure());
-
-    await recordRunSafe(command, options, {
-      provider,
-      outcome: "failure",
-      errorClass: classifyError(error),
-    });
-
+    tagErrorStage(error, "config");
     throw error;
-  } finally {
-    debugFetchCapture.restore();
   }
 }
 
@@ -405,43 +424,65 @@ async function runOpenWikiAgentCore(
   openWikiIgnore: OpenWikiIgnore,
 ): Promise<OpenWikiRunResult> {
   const outputMode = options.outputMode ?? "local-wiki";
-  const context = await createRunContext(
-    command,
-    cwd,
-    outputMode,
-    options.language,
-    openWikiIgnore,
+  const context = await inStage(
+    "build",
+    () =>
+      createRunContext(
+        command,
+        cwd,
+        outputMode,
+        options.language,
+        openWikiIgnore,
+      ),
+    { errorClass: "build_error", errorDetail: "run_context" },
   );
   emitDebug(options, "context=created");
   const openWikiSnapshotBefore =
     command === "chat"
       ? null
-      : await createOpenWikiContentSnapshot(cwd, outputMode);
+      : await inStage(
+          "build",
+          () => createOpenWikiContentSnapshot(cwd, outputMode),
+          { errorClass: "build_error", errorDetail: "snapshot" },
+        );
   emitDebug(options, "openwiki.snapshot=created");
-  const model = createModel(provider, modelId, providerRetryAttempts);
+  const model = inStageSync(
+    "build",
+    () => createModel(provider, modelId, providerRetryAttempts),
+    { errorClass: "build_error", errorDetail: "model" },
+  );
   emitDebug(options, `model.provider=${provider}`);
   emitDebug(options, "model=initialized");
   const threadId = options.threadId ?? createThreadId(cwd, createRunThreadId());
   emitDebug(options, `thread=${threadId}`);
   const checkpointTarget = resolveCheckpointTarget(command);
-  const checkpointer = await createCheckpointer(checkpointTarget);
+  const checkpointer = await inStage(
+    "build",
+    () => createCheckpointer(checkpointTarget),
+    { errorClass: "checkpointer_error", errorDetail: "create" },
+  );
   emitDebug(
     options,
     checkpointTarget.persistent
       ? `checkpointer=${formatUrlDebugValue(checkpointTarget.connString)}`
       : "checkpointer=memory",
   );
-  const agent = createOpenWikiAgentGraph({
-    command,
-    cwd,
-    language: options.language,
-    model,
-    onEvent: options.onEvent,
-    outputMode,
-    checkpointer,
-    context,
-    openWikiIgnore,
-  });
+  const agent = inStageSync(
+    "build",
+    () =>
+      createOpenWikiAgentGraph({
+        command,
+        cwd,
+        language: options.language,
+        model,
+        onEvent: options.onEvent,
+        outputMode,
+        checkpointer,
+        context,
+        openWikiIgnore,
+      }),
+    { errorClass: "build_error", errorDetail: "agent" },
+  );
   emitDebug(options, "agent=created");
 
   const input = {
@@ -454,12 +495,17 @@ async function runOpenWikiAgentCore(
   };
 
   emitDebug(options, "stream=opening protocol=events version=v3");
-  const stream = await agent.streamEvents(input, {
-    configurable: {
-      thread_id: threadId,
-    },
-    version: "v3",
-  });
+  const stream = await inStage(
+    "build",
+    () =>
+      agent.streamEvents(input, {
+        configurable: {
+          thread_id: threadId,
+        },
+        version: "v3",
+      }),
+    { errorClass: "build_error", errorDetail: "stream_open" },
+  );
   emitDebug(options, "stream=started protocol=events version=v3");
 
   let unhandledChunkCount = 0;
@@ -484,6 +530,8 @@ async function runOpenWikiAgentCore(
     }
     emitDebug(options, "stream=completed");
   } catch (error) {
+    tagErrorStage(error, "run");
+
     await cleanupTemporaryPlanFile(command, cwd, outputMode, options).catch(
       () => {
         emitDebug(options, "plan.cleanup=failed");
@@ -524,20 +572,31 @@ async function runOpenWikiAgentCore(
   }
 
   if (checkpointTarget.persistent) {
-    await chmodIfExists(checkpointTarget.connString, 0o600);
+    // Locking down the checkpoint file is a checkpointer concern; a filesystem
+    // failure here owns to us, not the user, so it carries its own class rather
+    // than the stage-only tag the metadata write below relies on.
+    await inStage(
+      "finalize",
+      () => chmodIfExists(checkpointTarget.connString, 0o600),
+      { errorClass: "checkpointer_error", errorDetail: "chmod" },
+    );
   }
 
-  await cleanupTemporaryPlanFile(command, cwd, outputMode, options);
-
-  const metadataWritten = await persistRunMetadataIfChanged(
-    command,
-    cwd,
-    modelId,
-    outputMode,
-    openWikiSnapshotBefore,
-    "complete",
-    context.language,
-  );
+  // Stage-only tag: a write failure here classifies from the raw error (a
+  // filesystem code becomes filesystem_error), and deriveOwner's finalize
+  // exception routes that to openwiki since the run reached our own persistence.
+  const metadataWritten = await inStage("finalize", async () => {
+    await cleanupTemporaryPlanFile(command, cwd, outputMode, options);
+    return persistRunMetadataIfChanged(
+      command,
+      cwd,
+      modelId,
+      outputMode,
+      openWikiSnapshotBefore,
+      "complete",
+      context.language,
+    );
+  });
 
   if (metadataWritten) {
     emitDebug(options, "metadata=written");
diff --git a/src/agent/okf-middleware.ts b/src/agent/okf-middleware.ts
--- a/src/agent/okf-middleware.ts
+++ b/src/agent/okf-middleware.ts
@@ -14,6 +14,7 @@ import {
   type IndexLabels,
 } from "../okf/index-labels.js";
 import { MUTATION_PATH_METADATA_KEY } from "./docs-only-backend.js";
+import { inStage } from "../telemetry/index.js";
 import type { OpenWikiOutputMode } from "./types.js";
 
 const OKF_RESERVED_FILES = new Set(["index.md", "log.md"]);
@@ -33,8 +34,29 @@ export function createOpenWikiIndexMiddleware(
   return createMiddleware({
     name: "OpenWikiIndexMiddleware",
     beforeAgent: async () => {
-      await migrateWikiToOkf(backend, outputMode, conceptType);
+      // Owned OKF pass: a throw here is our conformance code failing, not the
+      // model. Tag class+detail at the origin so it does not fall to the run
+      // stage's raw classifier (which would read agent_error).
+      await inStage(
+        "build",
+        () => migrateWikiToOkf(backend, outputMode, conceptType),
+        { errorClass: "okf_error", errorDetail: "migrate" },
+      );
     },
+    // Telemetry guard: this wrap only *decorates a successful* tool result with a
+    // front-matter warning; it deliberately does not catch tool throws. LangChain's
+    // tool node swallows a thrown tool error into a ToolMessage fed back to the
+    // model so the agent can recover, so tool/connector throws never reach the run
+    // failure path. Consequences to keep in mind before changing this:
+    //   - `connector_error` has no fatal propagating path at all (the connector
+    //     pull in runCodeModeConnectors is fail-open by design), so it is a
+    //     documented telemetry blind spot, not a bucket some run produces.
+    //   - `tool_error` is reachable only when a tool-named error escapes to the
+    //     failure path; classifyError matches it by `error.name`, not here.
+    //   - Tool-input parse errors are swallowed by LangChain upstream and never
+    //     become `tool_error`.
+    // Do not turn this into a catch that rethrows: that would make every recoverable
+    // tool error fatal and record otherwise-successful runs as failures.
     wrapToolCall: async (request, handler) =>
       addFrontmatterWarning(
         await handler(request),
@@ -43,8 +65,16 @@ export function createOpenWikiIndexMiddleware(
         request.toolCall.name,
       ),
     afterAgent: async () => {
-      await validateWikiMermaid(backend, outputMode);
-      await synchronizeWikiIndexes(backend, outputMode, labels, conceptType);
+      await inStage(
+        "finalize",
+        () => validateWikiMermaid(backend, outputMode),
+        { errorClass: "okf_error", errorDetail: "mermaid" },
+      );
+      await inStage(
+        "finalize",
+        () => synchronizeWikiIndexes(backend, outputMode, labels, conceptType),
+        { errorClass: "okf_error", errorDetail: "index_sync" },
+      );
     },
   });
 }
diff --git a/src/cli.tsx b/src/cli.tsx
--- a/src/cli.tsx
+++ b/src/cli.tsx
@@ -1,4 +1,5 @@
 #!/usr/bin/env node
+import path from "node:path";
 import React, { useEffect, useRef, useState } from "react";
 import { Box, render, Text, useApp, useInput } from "ink";
 import { marked, type Token, type Tokens } from "marked";
@@ -8,6 +9,7 @@ import {
   shouldDiscoverToolsAfterAuth,
 } from "./auth/configure.js";
 import { startNgrokTunnel } from "./auth/ngrok.js";
+import { runVisualizeServer } from "./visualize/server.js";
 import { formatAuthProviderList, runOAuthAuth } from "./auth/oauth.js";
 import { ensureCodeModeRepoSetup, runCodeModeConnectors } from "./code-mode.js";
 import {
@@ -84,12 +86,18 @@ import {
   OPENWIKI_VERSION,
   type OpenWikiProvider,
 } from "./constants.js";
-import type { OpenWikiCommand, OpenWikiOutputMode } from "./agent/types.js";
+import type {
+  OpenWikiCommand,
+  OpenWikiOutputMode,
+  OpenWikiRunOptions,
+} from "./agent/types.js";
 import {
   firstRunNoticePending,
   FIRST_RUN_NOTICE_BODY,
   FIRST_RUN_NOTICE_OPT_OUT,
   FIRST_RUN_NOTICE_VERIFY,
+  withRunTelemetry,
+  type RunTelemetryContext,
 } from "./telemetry/index.js";
 
 type RunState =
@@ -579,34 +587,52 @@ function App({ command }: AppProps) {
         });
     }
 
-    const setupPromise =
-      runMode === "code"
-        ? ensureCodeModeRepoSetup(runtimeCwd, {
-            createWorkflow: resolvedCommand === "init",
-          })
-        : Promise.resolve();
+    const handleRunEvent = (event: OpenWikiRunEvent): void => {
+      if (!mountedRef.current || activeRunId.current !== runId) {
+        return;
+      }
 
-    setupPromise
-      .then(async () => {
-        const handleRunEvent = (event: OpenWikiRunEvent): void => {
-          if (!mountedRef.current || activeRunId.current !== runId) {
-            return;
-          }
+      activeRunLog.current = appendRunLogEvent(
+        activeRunLog.current,
+        event,
+        nextLogId,
+      );
+      setRunState((currentState) =>
+        currentState.status === "running"
+          ? {
+              ...currentState,
+              log: activeRunLog.current,
+            }
+          : currentState,
+      );
+    };
 
-          activeRunLog.current = appendRunLogEvent(
-            activeRunLog.current,
-            event,
-            nextLogId,
-          );
-          setRunState((currentState) =>
-            currentState.status === "running"
-              ? {
-                  ...currentState,
-                  log: activeRunLog.current,
-                }
-              : currentState,
-          );
-        };
+    const runOptions: OpenWikiRunOptions = {
+      debug: isDebugMode(),
+      isFollowup: activeMessageIsFollowup,
+      language: command.language,
+      modelId: sessionModelId,
+      outputMode: runtimeOutputMode,
+      threadId: sessionThreadId.current,
+      telemetryFile: command.telemetryFile ?? undefined,
+      onEvent: handleRunEvent,
+    };
+
+    // withRunTelemetry is the single boundary that records this run. It wraps repo
+    // setup and the connector pull too (not just the agent), so a throw in either
+    // pre-agent step is recorded rather than reaching only the UI catch below.
+    const telemetryContext: RunTelemetryContext = {};
+
+    withRunTelemetry(
+      resolvedCommand,
+      runOptions,
+      telemetryContext,
+      async () => {
+        if (runMode === "code") {
+          await ensureCodeModeRepoSetup(runtimeCwd, {
+            createWorkflow: resolvedCommand === "init",
+          });
+        }
 
         // Code-mode connectors pull their evidence and augment the agent message
         // before the run, matching the --print path exactly. They emit progress
@@ -620,18 +646,14 @@ function App({ command }: AppProps) {
               )
             : activeUserMessage;
 
-        return runOpenWikiAgent(resolvedCommand, runtimeCwd, {
-          debug: isDebugMode(),
-          isFollowup: activeMessageIsFollowup,
-          language: command.language,
-          modelId: sessionModelId,
-          outputMode: runtimeOutputMode,
-          threadId: sessionThreadId.current,
-          userMessage,
-          telemetryFile: command.telemetryFile ?? undefined,
-          onEvent: handleRunEvent,
-        });
-      })
+        return runOpenWikiAgent(
+          resolvedCommand,
+          runtimeCwd,
+          { ...runOptions, userMessage },
+          telemetryContext,
+        );
+      },
+    )
       .then((result) => {
         if (!mountedRef.current || activeRunId.current !== runId) {
           return;
@@ -3745,6 +3767,8 @@ if (command.kind === "auth") {
   await runCronCommand(command);
 } else if (command.kind === "ingest") {
   await runIngestCommand(command);
+} else if (command.kind === "visualize") {
+  await runVisualizeCommand(command);
 } else if (shouldPrintStartupError(argv, parsedCommand, command)) {
   process.stderr.write(`${command.message}\n`);
   process.exitCode = command.exitCode;
@@ -3781,6 +3805,26 @@ async function runNgrokCommand(
   }
 }
 
+/**
+ * Start the wiki visualizer server for a resolved wiki directory. Blocks until the
+ * server is stopped with Ctrl-C; surfaces a missing-directory error cleanly.
+ */
+async function runVisualizeCommand(
+  command: Extract<CliCommand, { kind: "visualize" }>,
+): Promise<void> {
+  const wikiRoot = path.resolve(process.cwd(), command.wikiDir);
+  try {
+    await runVisualizeServer({
+      wikiRoot,
+      port: command.port,
+      open: command.open,
+    });
+  } catch (error) {
+    process.stderr.write(`${getErrorMessage(error)}\n`);
+    process.exitCode = 1;
+  }
+}
+
 async function runCronCommand(
   command: Extract<CliCommand, { kind: "cron" }>,
 ): Promise<void> {
@@ -4132,40 +4176,59 @@ async function runPrintCommand(
     const runtimeCwd = getRunModeCwd(command.mode);
     const runtimeOutputMode = getRunModeOutputMode(command.mode);
 
-    if (command.mode === "code") {
-      await ensureCodeModeRepoSetup(runtimeCwd, {
-        createWorkflow: command.command === "init",
-      });
-    }
-
-    // Code-mode connectors (e.g. langsmith) pull their evidence and augment the
-    // agent message before the run, so --print behaves exactly like interactive.
     const handlePrintEvent = (event: OpenWikiRunEvent): void => {
       if (event.type === "text" && event.source !== "subgraph") {
         output.push(event.text);
       }
     };
 
-    const userMessage =
-      command.mode === "code" && command.command !== "chat"
-        ? await runCodeModeConnectors(
-            runtimeCwd,
-            command.userMessage ?? undefined,
-            handlePrintEvent,
-          )
-        : command.userMessage;
-
-    await runOpenWikiAgent(command.command, runtimeCwd, {
+    const runOptions: OpenWikiRunOptions = {
       debug: isDebugMode(),
       isFollowup: command.command === "chat",
       language: command.language,
       modelId: command.modelId,
       outputMode: runtimeOutputMode,
       threadId: createOpenWikiThreadId(runtimeCwd),
-      userMessage,
       telemetryFile: command.telemetryFile ?? undefined,
       onEvent: handlePrintEvent,
-    });
+    };
+
+    // withRunTelemetry is the single boundary that records this run, wrapping repo
+    // setup and the connector pull as well as the agent so a throw in either
+    // pre-agent step is recorded rather than only surfaced on stderr below.
+    const telemetryContext: RunTelemetryContext = {};
+
+    await withRunTelemetry(
+      command.command,
+      runOptions,
+      telemetryContext,
+      async () => {
+        if (command.mode === "code") {
+          await ensureCodeModeRepoSetup(runtimeCwd, {
+            createWorkflow: command.command === "init",
+          });
+        }
+
+        // Code-mode connectors (e.g. langsmith) pull their evidence and augment
+        // the agent message before the run, so --print behaves exactly like
+        // interactive.
+        const userMessage =
+          command.mode === "code" && command.command !== "chat"
+            ? await runCodeModeConnectors(
+                runtimeCwd,
+                command.userMessage ?? undefined,
+                handlePrintEvent,
+              )
+            : command.userMessage;
+
+        await runOpenWikiAgent(
+          command.command,
+          runtimeCwd,
+          { ...runOptions, userMessage },
+          telemetryContext,
+        );
+      },
+    );
 
     const text = output.join("").trim();
 
diff --git a/src/commands.ts b/src/commands.ts
--- a/src/commands.ts
+++ b/src/commands.ts
@@ -39,6 +39,13 @@ export type CliCommand =
       port: number;
       url: string | null;
     }
+  | {
+      kind: "visualize";
+      exitCode: 0;
+      wikiDir: string;
+      port: number;
+      open: boolean;
+    }
   | {
       kind: "ingest";
       exitCode: 0;
@@ -206,6 +213,64 @@ export function parseCommand(argv: string[]): CliCommand {
     };
   }
 
+  if (argv[0] === "visualize") {
+    let wikiDir = "openwiki";
+    let port = 4321;
+    let open = true;
+    let sawPositional = false;
+    const optionArgs = argv.slice(1);
+
+    for (let index = 0; index < optionArgs.length; index += 1) {
+      const arg = optionArgs[index];
+
+      if (arg === "--no-open") {
+        open = false;
+        continue;
+      }
+
+      if (arg === "--port") {
+        const rawPort = optionArgs[index + 1];
+        if (!rawPort || rawPort.startsWith("-")) {
+          return {
+            kind: "error",
+            exitCode: 1,
+            message: "--port requires a value.",
+          };
+        }
+        port = Number(rawPort);
+        index += 1;
+        continue;
+      }
+
+      if (arg.startsWith("--port=")) {
+        port = Number(arg.slice("--port=".length));
+        continue;
+      }
+
+      if (!arg.startsWith("-") && !sawPositional) {
+        wikiDir = arg;
+        sawPositional = true;
+        continue;
+      }
+
+      return {
+        kind: "error",
+        exitCode: 1,
+        message: `Unknown option for visualize: ${arg}`,
+      };
+    }
+
+    if (!Number.isInteger(port) || port < 1024 || port > 65535) {
+      return {
+        kind: "error",
+        exitCode: 1,
+        message: "--port must be between 1024 and 65535.",
+      };
+    }
+
+    return { kind: "visualize", exitCode: 0, wikiDir, port, open };
+  }
+
   if (argv[0] === "ingest") {
     const target = parseIngestionTarget(argv[1] ?? "all");
     if (!target) {
@@ -683,6 +748,7 @@ export const helpContent: HelpContent = {
     "openwiki cron resume all",
     "openwiki cron delete all",
     "openwiki ngrok start [url] [--port <port>]",
+    "openwiki visualize [path] [--port <port>] [--no-open]",
   ],
   commands: [
     {
@@ -743,6 +809,11 @@ export const helpContent: HelpContent = {
       description:
         "Start an ngrok tunnel for Slack OAuth, optionally using a fixed HTTPS URL.",
     },
+    {
+      label: "openwiki visualize [path]",
+      description:
+        "Serve an interactive graph and live docs reader for a generated wiki (defaults to ./openwiki).",
+    },
   ],
   options: [
     {
@@ -788,6 +859,15 @@ export const helpContent: HelpContent = {
       description:
         "Write the exact anonymous telemetry payload to a local JSON file.",
     },
+    {
+      label: "--port <port>",
+      description:
+        "For visualize: port to serve on (default 4321; increments on conflict).",
+    },
+    {
+      label: "--no-open",
+      description: "For visualize: do not open the browser automatically.",
+    },
   ],
   developmentOptions: [
     {
@@ -821,6 +901,8 @@ export const helpContent: HelpContent = {
     "openwiki auth tools notion",
     "openwiki ngrok start",
     "openwiki ngrok start https://openwiki.ngrok.app",
+    "openwiki visualize",
+    "openwiki visualize openwiki --port 4400 --no-open",
   ],
   developmentExamples: ["openwiki --dry-run"],
 };
diff --git a/src/ingestion.ts b/src/ingestion.ts
--- a/src/ingestion.ts
+++ b/src/ingestion.ts
@@ -24,6 +24,10 @@ import type {
   OpenWikiRunOptions,
   OpenWikiRunResult,
 } from "./agent/types.js";
+import {
+  withRunTelemetry,
+  type RunTelemetryContext,
+} from "./telemetry/index.js";
 
 const INGESTION_WINDOW_HOURS = 24;
 
@@ -166,7 +170,7 @@ async function runSourceIngestion({
 
     emitDeterministicPullSummary(emit, deterministicPull);
 
-    const agentResult = await runOpenWikiAgent("update", cwd, {
+    const runOptions: OpenWikiRunOptions = {
       isFollowup: false,
       modelId,
       onEvent: emit,
@@ -179,7 +183,17 @@ async function runSourceIngestion({
         rawFiles,
         sourceConfig,
       }),
-    });
+    };
+
+    // withRunTelemetry is the single boundary that records this per-source update
+    // run, matching the CLI paths so ingestion runs land in telemetry too.
+    const telemetryContext: RunTelemetryContext = {};
+    const agentResult = await withRunTelemetry(
+      "update",
+      runOptions,
+      telemetryContext,
+      () => runOpenWikiAgent("update", cwd, runOptions, telemetryContext),
+    );
 
     return {
       agentResult,
diff --git a/src/telemetry/errors.ts b/src/telemetry/errors.ts
--- a/src/telemetry/errors.ts
+++ b/src/telemetry/errors.ts
@@ -1,55 +1,418 @@
-import type { TelemetryErrorClass } from "./types.js";
+import { deriveOwner, normalizeErrorDetail } from "./taxonomy.js";
+import type {
+  TelemetryErrorClass,
+  TelemetryErrorOwner,
+  TelemetryErrorStage,
+} from "./types.js";
 
 /**
- * Maps an unknown error to a closed TelemetryErrorClass. Importantly, this never
- * leaks the message which could contain sensitive information.
+ * A failure family paired with its detail, the two-level result of classifying a
+ * raw error. `errorDetail` is the specific failure within the family, or undefined
+ * when the family has no detail split or none could be read from the raw error.
  */
-export function classifyError(error: unknown): TelemetryErrorClass {
+export interface ErrorClassification {
+  /**
+   * The closed-set failure family.
+   */
+  errorClass: TelemetryErrorClass;
+
+  /**
+   * The specific failure within the family, or undefined.
+   *
+   * @default undefined - the family has no detail split, or none was resolvable
+   * from the raw error alone.
+   */
+  errorDetail?: string;
+}
+
+/**
+ * Provider-native error codes we recognize, mapped to a class and detail. Read
+ * internally only to disambiguate otherwise-identical statuses (a context-limit 400
+ * vs any other 400); the code string itself is never emitted. Anything not on this
+ * list is ignored, so the envelope stays closed.
+ */
+const PROVIDER_ERROR_CODES: Readonly<Record<string, ErrorClassification>> = {
+  context_length_exceeded: { errorClass: "context_limit_error" },
+  string_above_max_length: { errorClass: "context_limit_error" },
+  rate_limit_exceeded: {
+    errorClass: "provider_error",
+    errorDetail: "rate_limit",
+  },
+  insufficient_quota: {
+    errorClass: "provider_error",
+    errorDetail: "quota_exceeded",
+  },
+  billing_hard_limit_reached: {
+    errorClass: "provider_error",
+    errorDetail: "quota_exceeded",
+  },
+  invalid_api_key: { errorClass: "provider_error", errorDetail: "auth" },
+  authentication_error: { errorClass: "provider_error", errorDetail: "auth" },
+  permission_error: { errorClass: "provider_error", errorDetail: "auth" },
+  overloaded_error: { errorClass: "provider_error", errorDetail: "overloaded" },
+  content_policy_violation: {
+    errorClass: "provider_error",
+    errorDetail: "content_filter",
+  },
+  content_filter: {
+    errorClass: "provider_error",
+    errorDetail: "content_filter",
+  },
+};
+
+/**
+ * Maps an unknown error to a closed {@link ErrorClassification} from the raw error
+ * alone (status, provider code, message, filesystem code). Priority runs
+ * most-specific to least: abort, recognized provider code, HTTP status, tool shape,
+ * message regexes, filesystem code, then the single `agent_error` catch-all.
+ *
+ * This reads only the raw signal; the owned families whose class comes from where
+ * the error was thrown (`build_error`, `connector_error`, `okf_error`,
+ * `checkpointer_error`, plus tagged `config_error`/`tool_error` details) are
+ * resolved from the origin tag by {@link describeErrorForTelemetry}, which prefers
+ * the tag over this. Never leaks the message: it is read to test regexes in-process,
+ * but only an enum member is ever returned.
+ */
+export function classifyError(error: unknown): ErrorClassification {
   if (error instanceof Error && error.name === "AbortError") {
-    return "aborted";
+    return { errorClass: "aborted" };
+  }
+
+  const providerCode = extractProviderErrorCode(error);
+  if (providerCode && providerCode in PROVIDER_ERROR_CODES) {
+    return PROVIDER_ERROR_CODES[providerCode];
   }
 
   const status = extractStatus(error);
   if (status === 401 || status === 403) {
-    return "provider_auth";
+    return { errorClass: "provider_error", errorDetail: "auth" };
   }
   if (status === 429) {
-    return "provider_rate_limit";
+    return { errorClass: "provider_error", errorDetail: "rate_limit" };
+  }
+  if (status === 529 || status === 503) {
+    return { errorClass: "provider_error", errorDetail: "overloaded" };
+  }
+  if (status !== undefined && status >= 500 && status < 600) {
+    return { errorClass: "provider_error", errorDetail: "server_error" };
+  }
+
+  if (error instanceof Error && /tool/iu.test(error.name)) {
+    // The tool name is a raw string; the emitted tool-name detail rides the origin
+    // tag (validated against the tool registry), not this raw-error path.
+    return { errorClass: "tool_error" };
   }
 
   const message = error instanceof Error ? error.message.toLowerCase() : "";
-  if (/is required to run openwiki/.test(message)) {
-    return /base url/.test(message) ? "missing_config" : "missing_credentials";
+  if (/is required to run openwiki/u.test(message)) {
+    return {
+      errorClass: "config_error",
+      errorDetail: /base url/u.test(message)
+        ? "missing_base_url"
+        : "missing_credentials",
+    };
+  }
+  if (/invalid model id/u.test(message)) {
+    return { errorClass: "config_error", errorDetail: "invalid_model" };
+  }
+  if (
+    /context length|maximum context|too many tokens|context window/u.test(
+      message,
+    )
+  ) {
+    return { errorClass: "context_limit_error" };
+  }
+  if (/quota|insufficient_quota|billing/u.test(message)) {
+    return { errorClass: "provider_error", errorDetail: "quota_exceeded" };
+  }
+  if (/timeout|timed out|etimedout/u.test(message)) {
+    return { errorClass: "provider_error", errorDetail: "timeout" };
   }
-  if (/invalid model id/.test(message)) {
-    return "invalid_model";
+  if (/enotfound|eai_again/u.test(message)) {
+    return { errorClass: "network_error", errorDetail: "dns" };
   }
-  if (/timeout|timed out|etimedout/.test(message)) {
-    return "provider_timeout";
+  if (/econnrefused/u.test(message)) {
+    return { errorClass: "network_error", errorDetail: "refused" };
   }
-  if (/econnrefused|enotfound|network|fetch failed/.test(message)) {
-    return "network";
+  if (/econnreset/u.test(message)) {
+    return { errorClass: "network_error", errorDetail: "reset" };
+  }
+  if (/network|fetch failed/u.test(message)) {
+    return { errorClass: "network_error", errorDetail: "unreachable" };
+  }
+  if (/content policy|content filter|content_filter|refus/u.test(message)) {
+    return { errorClass: "provider_error", errorDetail: "content_filter" };
+  }
+  if (/could not parse|invalid json/u.test(message)) {
+    return { errorClass: "output_error", errorDetail: "json_parse" };
+  }
+  if (/schema/u.test(message)) {
+    return { errorClass: "output_error", errorDetail: "schema" };
   }
 
   const code =
     error instanceof Error ? (error as NodeJS.ErrnoException).code : undefined;
-  if (code === "ENOENT" || code === "EACCES" || code === "EPERM") {
-    return "filesystem";
+  if (code === "ENOENT") {
+    return { errorClass: "filesystem_error", errorDetail: "not_found" };
+  }
+  if (code === "EACCES" || code === "EPERM") {
+    return { errorClass: "filesystem_error", errorDetail: "permission" };
+  }
+  if (code === "ENOSPC") {
+    return { errorClass: "filesystem_error", errorDetail: "no_space" };
   }
 
-  return "agent_error";
+  return { errorClass: "agent_error" };
 }
 
 /**
- * Best-effort extraction of an HTTP-ish status from provider SDK errors.
+ * Best-effort extraction of an HTTP-ish status from a provider SDK error. Reads
+ * the common shapes, including the nested `response.status` some clients use.
  */
-function extractStatus(error: unknown): number | undefined {
+export function extractStatus(error: unknown): number | undefined {
   if (typeof error !== "object" || error === null) {
     return undefined;
   }
 
-  const candidate = error as { status?: unknown; statusCode?: unknown };
-  const raw = candidate.status ?? candidate.statusCode;
+  const candidate = error as {
+    status?: unknown;
+    statusCode?: unknown;
+    response?: { status?: unknown } | null;
+  };
+  const raw =
+    candidate.status ?? candidate.statusCode ?? candidate.response?.status;
 
   return typeof raw === "number" ? raw : undefined;
 }
+
+/**
+ * Reads the provider's own error code from the common SDK shapes, lowercased. Used
+ * only to pick a class; the return value is never emitted.
+ */
+function extractProviderErrorCode(error: unknown): string | undefined {
+  if (typeof error !== "object" || error === null) {
+    return undefined;
+  }
+
+  const candidate = error as {
+    code?: unknown;
+    type?: unknown;
+    error?: { code?: unknown; type?: unknown } | null;
+  };
+  const raw =
+    candidate.code ??
+    candidate.type ??
+    candidate.error?.code ??
+    candidate.error?.type;
+
+  return typeof raw === "string" ? raw.trim().toLowerCase() : undefined;
+}
+
+/**
+ * The origin tag stamped onto an error as it unwinds: always the pipeline `stage`,
+ * and for owned families the `errorClass` and `errorDetail` decided at the throw
+ * site (where the class is known from context, not from a message string). Carried
+ * on a non-enumerable symbol so it never serializes into a telemetry payload or a
+ * JSON dump.
+ */
+interface ErrorOriginTag {
+  /**
+   * The pipeline stage the failure occurred in.
+   */
+  stage: TelemetryErrorStage;
+
+  /**
+   * The failure family, when the throw site owns the classification. Absent for a
+   * plain stage bracket, which leaves the class to the raw-error classifier.
+   *
+   * @default undefined - stage-only tag; the class comes from `classifyError`.
+   */
+  errorClass?: TelemetryErrorClass;
+
+  /**
+   * The detail decided at the throw site, paired with `errorClass`.
+   *
+   * @default undefined - no origin-supplied detail.
+   */
+  errorDetail?: string;
+}
+
+/**
+ * The class an owned-family throw site declares about itself, passed to
+ * {@link inStage} / {@link inStageSync} so the tag carries class and detail, not
+ * just stage.
+ */
+export interface ErrorOrigin {
+  /**
+   * The failure family this throw site produces.
+   */
+  errorClass: TelemetryErrorClass;
+
+  /**
+   * The specific detail within the family (e.g. the pass name, or a registry id).
+   *
+   * @default undefined - the family has no detail split.
+   */
+  errorDetail?: string;
+}
+
+/**
+ * Non-enumerable symbol carrying the {@link ErrorOriginTag}. Non-enumerable so it
+ * never serializes into a telemetry payload or a JSON dump.
+ */
+const ERROR_ORIGIN = Symbol.for("openwiki.telemetry.errorOrigin");
+
+/**
+ * Stamps an origin tag onto `error` if it does not already carry one (first tag
+ * wins, so the innermost/earliest origin is preserved as the error unwinds). No-op
+ * for non-objects.
+ *
+ * @param error - The thrown value to tag.
+ * @param tag - The stage, and optionally the owned-family class and detail.
+ */
+function tagErrorOrigin(error: unknown, tag: ErrorOriginTag): void {
+  if (typeof error !== "object" || error === null) {
+    return;
+  }
+
+  const target = error as Record<symbol, unknown>;
+  if (target[ERROR_ORIGIN] !== undefined) {
+    return;
+  }
+
+  Object.defineProperty(error, ERROR_ORIGIN, {
+    value: tag,
+    enumerable: false,
+    configurable: true,
+    writable: false,
+  });
+}
+
+/**
+ * Reads the origin tag off an error, or undefined if it was never tagged.
+ */
+function readErrorOrigin(error: unknown): ErrorOriginTag | undefined {
+  if (typeof error === "object" && error !== null) {
+    const tag = (error as Record<symbol, unknown>)[ERROR_ORIGIN];
+    if (typeof tag === "object" && tag !== null && "stage" in tag) {
+      return tag as ErrorOriginTag;
+    }
+  }
+
+  return undefined;
+}
+
+/**
+ * Stamps just the pipeline `stage` onto `error` (first tag wins). The one call a
+ * plain stage bracket uses; the class is left to the raw-error classifier.
+ */
+export function tagErrorStage(
+  error: unknown,
+  stage: TelemetryErrorStage,
+): void {
+  tagErrorOrigin(error, { stage });
+}
+
+/**
+ * Runs `fn`, tagging any thrown error with `stage` (and, when `origin` is given,
+ * the owned-family class and detail) before it propagates. The one call the run
+ * pipeline uses to bracket a stage. Pass `origin` at an owned-family throw site so
+ * the failure carries its class and detail from where it was thrown, not from a
+ * message string.
+ *
+ * @param stage - The pipeline stage to tag on a throw.
+ * @param fn - The work to run.
+ * @param origin - The owned-family class and detail, when the throw site owns the
+ *   classification.
+ */
+export async function inStage<T>(
+  stage: TelemetryErrorStage,
+  fn: () => Promise<T>,
+  origin?: ErrorOrigin,
+): Promise<T> {
+  try {
+    return await fn();
+  } catch (error) {
+    tagErrorOrigin(error, { stage, ...origin });
+    throw error;
+  }
+}
+
+/**
+ * Synchronous {@link inStage}, for the synchronous build steps (`createModel`,
+ * `createDeepAgent`) that can throw before any promise is created.
+ */
+export function inStageSync<T>(
+  stage: TelemetryErrorStage,
+  fn: () => T,
+  origin?: ErrorOrigin,
+): T {
+  try {
+    return fn();
+  } catch (error) {
+    tagErrorOrigin(error, { stage, ...origin });
+    throw error;
+  }
+}
+
+/**
+ * The full telemetry description of a failure, ready to spread into the run facts.
+ */
+export interface ErrorTelemetry {
+  /**
+   * The closed-set failure family.
+   */
+  errorClass: TelemetryErrorClass;
+
+  /**
+   * The specific failure within the family, normalized against its allowlist, or
+   * undefined.
+   */
+  errorDetail: string | undefined;
+
+  /**
+   * The pipeline stage the failure was tagged at, or undefined when uninstrumented.
+   */
+  errorStage: TelemetryErrorStage | undefined;
+
+  /**
+   * Who owns the fix, derived from (class, detail, stage).
+   */
+  errorOwner: TelemetryErrorOwner;
+
+  /**
+   * The provider's numeric status, or undefined. A bare integer.
+   */
+  httpStatus: number | undefined;
+}
+
+/**
+ * The single call the failure path uses: class, detail, owner, stage, and status in
+ * one object, ready to spread into the run facts. The class and detail come from the
+ * origin tag when the throw site owned the classification (build/connector/okf/
+ * checkpointer, or a tagged config/tool detail), otherwise from {@link classifyError}
+ * reading the raw error. The detail is normalized against its family's allowlist, so
+ * an off-list value is dropped rather than emitted. Never leaks the message.
+ */
+export function describeErrorForTelemetry(error: unknown): ErrorTelemetry {
+  const origin = readErrorOrigin(error);
+  const classified = classifyError(error);
+
+  // An origin tag that names a class owns both class and detail; a stage-only tag
+  // leaves both to the raw-error classifier.
+  const errorClass = origin?.errorClass ?? classified.errorClass;
+  const rawDetail = origin?.errorClass
+    ? origin.errorDetail
+    : classified.errorDetail;
+
+  const errorDetail = normalizeErrorDetail(errorClass, rawDetail);
+  const errorStage = origin?.stage;
+
+  return {
+    errorClass,
+    errorDetail,
+    errorStage,
+    errorOwner: deriveOwner(errorClass, errorDetail, errorStage),
+    httpStatus: extractStatus(error),
+  };
+}
diff --git a/src/telemetry/index.ts b/src/telemetry/index.ts
--- a/src/telemetry/index.ts
+++ b/src/telemetry/index.ts
@@ -1,16 +1,32 @@
 export { buildRunEvent, recordRun } from "./senders.js";
 export type { RunEventContext } from "./senders.js";
 export { recordRunSafe } from "./record-run-safe.js";
+export { withRunTelemetry } from "./with-run-telemetry.js";
+export type { RunTelemetryContext } from "./with-run-telemetry.js";
 export { firstRunNoticePending } from "./install-id.js";
 export {
   FIRST_RUN_NOTICE_BODY,
   FIRST_RUN_NOTICE_OPT_OUT,
   FIRST_RUN_NOTICE_VERIFY,
 } from "./config.js";
-export { classifyError } from "./errors.js";
+export {
+  classifyError,
+  describeErrorForTelemetry,
+  inStage,
+  inStageSync,
+  tagErrorStage,
+} from "./errors.js";
+export type {
+  ErrorClassification,
+  ErrorOrigin,
+  ErrorTelemetry,
+} from "./errors.js";
+export { deriveOwner, normalizeErrorDetail } from "./taxonomy.js";
 export { isCiEnvironment, isTelemetryDisabled } from "./gates.js";
 export type {
   RunTelemetry,
   TelemetryErrorClass,
+  TelemetryErrorOwner,
+  TelemetryErrorStage,
   TelemetryMode,
 } from "./types.js";
diff --git a/src/telemetry/record-run-safe.ts b/src/telemetry/record-run-safe.ts
--- a/src/telemetry/record-run-safe.ts
+++ b/src/telemetry/record-run-safe.ts
@@ -7,7 +7,11 @@ import { getConfiguredConnectorIds } from "../connectors/registry.js";
 import type { OpenWikiProvider } from "../constants.js";
 
 import { recordRun } from "./senders.js";
-import type { TelemetryErrorClass } from "./types.js";
+import type {
+  TelemetryErrorClass,
+  TelemetryErrorOwner,
+  TelemetryErrorStage,
+} from "./types.js";
 
 /**
  * Translates a finished agent run into the single telemetry event and records
@@ -24,9 +28,10 @@ import type { TelemetryErrorClass } from "./types.js";
  *
  * @param command - Which run lifecycle finished. Only init/update are recorded.
  * @param options - The run options; read for `outputMode` and `telemetryFile`.
- * @param facts - What the run produced: its `outcome`, an optional `errorClass`
- *   (present on failure), and the resolved `provider` (which may be undefined
- *   when resolution failed before the provider was known).
+ * @param facts - What the run produced: its `outcome`, the failure diagnostics
+ *   (`errorClass`, plus an optional `errorDetail`, `errorOwner`, `errorStage`, and
+ *   `httpStatus`, all present only on failure), and the resolved `provider` (which
+ *   may be undefined when resolution failed before the provider was known).
  */
 export async function recordRunSafe(
   command: OpenWikiCommand,
@@ -35,6 +40,10 @@ export async function recordRunSafe(
     provider?: OpenWikiProvider;
     outcome: "success" | "failure" | "noop";
     errorClass?: TelemetryErrorClass;
+    errorDetail?: string;
+    errorOwner?: TelemetryErrorOwner;
+    errorStage?: TelemetryErrorStage;
+    httpStatus?: number;
   },
 ): Promise<void> {
   // Chat is deliberately not recorded: it is interactive and would emit one
@@ -49,6 +58,10 @@ export async function recordRunSafe(
     command,
     outcome: facts.outcome,
     errorClass: facts.errorClass,
+    errorDetail: facts.errorDetail,
+    errorOwner: facts.errorOwner,
+    errorStage: facts.errorStage,
+    httpStatus: facts.httpStatus,
     // Setup choices are captured on init only (the configuration moment); on
     // updates these are omitted entirely.
     ...(command === "init"
diff --git a/src/telemetry/senders.ts b/src/telemetry/senders.ts
--- a/src/telemetry/senders.ts
+++ b/src/telemetry/senders.ts
@@ -1,5 +1,7 @@
+import { readFileSync } from "node:fs";
 import { mkdir, writeFile } from "node:fs/promises";
 import path from "node:path";
+import { fileURLToPath } from "node:url";
 
 import { capture } from "./client.js";
 import { DEFAULT_POSTHOG_HOST, TELEMETRY_RUN_EVENT } from "./config.js";
@@ -38,6 +40,17 @@ export interface RunEventContext {
    * sentinel. The builder does not resolve this; the caller decides.
    */
   distinctId: string;
+
+  /**
+   * OpenWiki version from the bundled `package.json` (e.g. "0.2.3"). Stamped on
+   * every event so adoption and per-version breakage are readable, and so the
+   * dashboard can scope metrics to a known version. Resolved by the caller from
+   * disk; the builder stays pure.
+   *
+   * @default undefined - the bundled package.json could not be read or had no
+   * version; the field is omitted rather than sent empty.
+   */
+  appVersion?: string;
 }
 
 /**
@@ -59,12 +72,30 @@ export function buildRunEvent(
       command: details.command,
       outcome: details.outcome,
       ...(details.errorClass ? { error_class: details.errorClass } : {}),
+      // The specific failure within the family and who owns the fix. Detail is an
+      // allowlisted word (dropped upstream if off-list); owner is derived from
+      // (class, detail, stage) so the dashboard can roll up by who must act,
+      // including the cross-owner exceptions PostHog cannot derive. Failure-only.
+      ...(details.errorDetail ? { error_detail: details.errorDetail } : {}),
+      ...(details.errorOwner ? { error_owner: details.errorOwner } : {}),
+      // Where in the pipeline the failure was tagged, and the provider's numeric
+      // status if one was present. Both failure-only and omitted when absent, so
+      // the null bucket reads as "not instrumented / no status" rather than a
+      // named value. No provider strings ride with the status.
+      ...(details.errorStage ? { error_stage: details.errorStage } : {}),
+      ...(details.httpStatus !== undefined
+        ? { http_status: details.httpStatus }
+        : {}),
       ...(details.mode ? { mode: details.mode } : {}),
       ...(details.provider ? { provider: details.provider } : {}),
       ...connectorProperties(details.configuredConnectors ?? []),
       // True for the published build, false for dev/source/seed runs; lets real
       // usage be separated from local testing and pre-launch seed data.
       production: context.production,
+      // Distribution provenance: the OpenWiki version from the bundled
+      // package.json, stamped on every event so adoption and per-version
+      // breakage are readable. Omitted when the caller could not resolve it.
+      ...(context.appVersion ? { app_version: context.appVersion } : {}),
       // Splits any metric human vs CI; also drives identity via the caller.
       ci: context.ci,
       // Never build a PostHog person: every run is anonymous. Unique-install
@@ -101,6 +132,7 @@ export async function recordRun(details: RunTelemetry): Promise<void> {
       ci,
       production: isProductionBuild(),
       distinctId,
+      appVersion: packageProvenance().appVersion,
     });
     const sent = await capture(event);
 
@@ -116,6 +148,79 @@ export async function recordRun(details: RunTelemetry): Promise<void> {
   }
 }
 
+/**
+ * Non-identifying distribution provenance read once from the bundled
+ * `package.json`: the OpenWiki version. Static build metadata, so it is resolved
+ * lazily and cached for the process lifetime.
+ */
+interface PackageProvenance {
+  /**
+   * `version` from the bundled package.json, or undefined when it could not be
+   * read.
+   */
+  appVersion?: string;
+}
+
+/**
+ * Cached result of {@link packageProvenance}. `undefined` means "not resolved
+ * yet"; once resolved it is an object (possibly empty on failure) and never
+ * re-read.
+ */
+let cachedProvenance: PackageProvenance | undefined;
+
+/**
+ * Reads the bundled `package.json` for its `version`, walking up from this
+ * module's own location to the nearest package.json that declares a `name` (the
+ * name gates out unrelated package.json files without itself being emitted). The
+ * version is static, non-identifying build metadata; no user repository content
+ * is ever touched. Fully failure-safe: any error (missing file, bad JSON, no
+ * name) yields an empty object, so provenance is simply omitted from the event
+ * rather than breaking the run. Cached for the process lifetime.
+ */
+function packageProvenance(): PackageProvenance {
+  if (cachedProvenance !== undefined) {
+    return cachedProvenance;
+  }
+
+  cachedProvenance = {};
+  try {
+    let dir = path.dirname(fileURLToPath(import.meta.url));
+    // Walk up a bounded number of levels: dist/ layouts and src/ layouts differ,
+    // so the nearest named package.json may be a few directories up. Bounded so a
+    // stray package.json high in the tree cannot send us walking to the root.
+    for (let depth = 0; depth < 6; depth++) {
+      const candidate = path.join(dir, "package.json");
+      try {
+        const parsed: unknown = JSON.parse(readFileSync(candidate, "utf8"));
+        if (
+          typeof parsed === "object" &&
+          parsed !== null &&
+          typeof (parsed as { name?: unknown }).name === "string"
+        ) {
+          const pkg = parsed as { version?: unknown };
+          cachedProvenance = {
+            appVersion:
+              typeof pkg.version === "string" ? pkg.version : undefined,
+          };
+          break;
+        }
+      } catch {
+        // No readable/valid package.json at this level; keep walking up.
+      }
+
+      const parent = path.dirname(dir);
+      if (parent === dir) {
+        break;
+      }
+      dir = parent;
+    }
+  } catch {
+    // Intentionally ignored: provenance is best-effort, never fatal.
+  }
+
+  return cachedProvenance;
+}
+
 /**
  * Turns configured connector ids into boolean event properties, e.g.
  * `["web-search", "notion"]` -> `{ connector_web_search: true, connector_notion: true }`.
diff --git a/src/telemetry/taxonomy.ts b/src/telemetry/taxonomy.ts
new file mode 100644
--- /dev/null
+++ b/src/telemetry/taxonomy.ts
@@ -0,0 +1,159 @@
+import type {
+  TelemetryErrorClass,
+  TelemetryErrorOwner,
+  TelemetryErrorStage,
+} from "./types.js";
+
+/**
+ * The hardcoded `errorDetail` allowlist for each closed family: the exact set of
+ * detail values that family may emit. This is the anonymity spine for the detail
+ * property. Any observed detail not present for its family is dropped to undefined
+ * (see {@link normalizeErrorDetail}), so only these hand-named words ever leave the
+ * process. Families with no detail split map to an empty list.
+ *
+ * Two families are deliberately absent (`connector_error`, `tool_error`): their
+ * detail is a registry id, not a fixed word, and is validated at its tag site
+ * against the connector/tool registry instead (see {@link OPEN_DETAIL_CLASSES}).
+ */
+const FIXED_ERROR_DETAILS: Readonly<
+  Record<
+    Exclude<TelemetryErrorClass, "connector_error" | "tool_error">,
+    readonly string[]
+  >
+> = {
+  config_error: [
+    "missing_credentials",
+    "missing_base_url",
+    "missing_secret_key",
+    "missing_region",
+    "invalid_model",
+  ],
+  filesystem_error: ["not_found", "permission", "no_space"],
+  provider_error: [
+    "auth",
+    "rate_limit",
+    "overloaded",
+    "server_error",
+    "timeout",
+    "quota_exceeded",
+    "content_filter",
+  ],
+  network_error: ["dns", "refused", "reset", "unreachable"],
+  build_error: ["run_context", "snapshot", "model", "agent", "stream_open"],
+  okf_error: ["migrate", "index_sync", "mermaid"],
+  checkpointer_error: ["create", "persist", "chmod"],
+  output_error: ["json_parse", "schema"],
+  // No detail split: the family is the whole signal.
+  context_limit_error: [],
+  agent_error: [],
+  aborted: [],
+};
+
+/**
+ * Families whose detail is a registry id (the connector id or the tool name) rather
+ * than a fixed word. Their detail is validated at the tag site against the known
+ * connector/tool set, which is the same closed set already emitted as `connector_*`
+ * booleans, so it is trusted here without a static allowlist.
+ */
+const OPEN_DETAIL_CLASSES: ReadonlySet<TelemetryErrorClass> = new Set([
+  "connector_error",
+  "tool_error",
+]);
+
+/**
+ * Provider-error details that are really the user's key or account, not a transient
+ * provider fault, so they route to `environment` instead of `provider`.
+ */
+const PROVIDER_ENVIRONMENT_DETAILS: ReadonlySet<string> = new Set([
+  "auth",
+  "quota_exceeded",
+]);
+
+/**
+ * Network-error details that are the user's machine or network, not the path to the
+ * provider, so they route to `environment` instead of `provider`.
+ */
+const NETWORK_ENVIRONMENT_DETAILS: ReadonlySet<string> = new Set([
+  "dns",
+  "refused",
+]);
+
+/**
+ * Validates an observed `detail` against its family's allowlist, returning it only
+ * when legal and undefined otherwise. This is the runtime guarantee behind the
+ * detail property's anonymity: a fixed-family detail must be on the family's
+ * hardcoded list; an open-family detail (connector/tool id) is trusted as a
+ * non-empty string because its tag site already validated it against the registry;
+ * a no-detail family always yields undefined.
+ *
+ * @param errorClass - The failure family the detail belongs to.
+ * @param detail - The observed detail, or undefined when none was resolved.
+ * @returns The detail if it is legal for the family, otherwise undefined.
+ */
+export function normalizeErrorDetail(
+  errorClass: TelemetryErrorClass,
+  detail: string | undefined,
+): string | undefined {
+  if (detail === undefined || detail === "") {
+    return undefined;
+  }
+
+  if (OPEN_DETAIL_CLASSES.has(errorClass)) {
+    return detail;
+  }
+
+  const allowed =
+    FIXED_ERROR_DETAILS[errorClass as keyof typeof FIXED_ERROR_DETAILS];
+  return allowed.includes(detail) ? detail : undefined;
+}
+
+/**
+ * Derives who owns the fix for a failure from its class, detail, and stage. The
+ * single source of owner truth; no other site should branch on (class, detail) to
+ * decide an owner. Encodes the three cross-owner exceptions where a family sits
+ * under one owner but a couple of its details are really someone else's problem:
+ *
+ * - `provider_error` is the provider's, except `auth`/`quota_exceeded` (the user's
+ *   key or account) which are `environment`.
+ * - `network_error` is the provider path's, except `dns`/`refused` (the user's
+ *   machine or network) which are `environment`.
+ * - `filesystem_error` is the user's, except at `finalize` (our own wiki write
+ *   path) which is `openwiki`.
+ *
+ * @param errorClass - The failure family.
+ * @param detail - The normalized detail, or undefined.
+ * @param stage - The pipeline stage the failure was tagged at, or undefined.
+ * @returns The owner responsible for acting on the failure.
+ */
+export function deriveOwner(
+  errorClass: TelemetryErrorClass,
+  detail: string | undefined,
+  stage: TelemetryErrorStage | undefined,
+): TelemetryErrorOwner {
+  switch (errorClass) {
+    case "config_error":
+      return "environment";
+    case "filesystem_error":
+      return stage === "finalize" ? "openwiki" : "environment";
+    case "provider_error":
+      return detail !== undefined && PROVIDER_ENVIRONMENT_DETAILS.has(detail)
+        ? "environment"
+        : "provider";
+    case "network_error":
+      return detail !== undefined && NETWORK_ENVIRONMENT_DETAILS.has(detail)
+        ? "environment"
+        : "provider";
+    case "context_limit_error":
+    case "build_error":
+    case "connector_error":
+    case "okf_error":
+    case "checkpointer_error":
+    case "tool_error":
+    case "output_error":
+      return "openwiki";
+    case "agent_error":
+      return "unowned";
+    case "aborted":
+      return "control";
+  }
+}
diff --git a/src/telemetry/types.ts b/src/telemetry/types.ts
--- a/src/telemetry/types.ts
+++ b/src/telemetry/types.ts
@@ -1,19 +1,52 @@
 /**
- * Closed set of failure categories. Raw error strings are never sent.
+ * Closed set of failure families, the big bucket a failure falls in. Raw error
+ * strings are never sent; only these enum values leave the process. Each family
+ * pairs with an `errorDetail` (the specific failure inside it) and derives an
+ * `errorOwner` (whose problem it is). `agent_error` is the residual for any
+ * failure that matched no rule (including a thrown non-`Error`); it is the quality
+ * meter and should trend toward zero.
+ *
+ * The full taxonomy (families, per-family detail allowlists, and owner rules) lives
+ * in `taxonomy.ts`.
  */
 export type TelemetryErrorClass =
-  | "missing_credentials"
-  | "missing_config"
-  | "invalid_model"
-  | "provider_auth"
-  | "provider_rate_limit"
-  | "provider_timeout"
-  | "network"
-  | "agent_error"
+  | "config_error"
+  | "filesystem_error"
+  | "provider_error"
+  | "network_error"
+  | "context_limit_error"
+  | "build_error"
+  | "connector_error"
+  | "okf_error"
+  | "checkpointer_error"
   | "tool_error"
-  | "filesystem"
-  | "aborted"
-  | "unknown";
+  | "output_error"
+  | "agent_error"
+  | "aborted";
+
+/**
+ * Who owns the fix for a failure, derived from its class, detail, and stage (see
+ * `deriveOwner` in `taxonomy.ts`). This is emitted so the health dashboard can roll
+ * failures up by who has to act, including the cross-owner exceptions (a
+ * `provider_error` with detail `auth` is really the user's key, so it owns to
+ * `environment`) that PostHog cannot derive on its own.
+ *
+ * - `environment`: the user's setup, credentials, or machine.
+ * - `provider`: the provider API failed transiently; retry/backoff.
+ * - `openwiki`: we own the fix, whether a bug or work like chunking.
+ * - `unowned`: the agent/model core failed in a way we have not named yet.
+ * - `control`: the run was cancelled; excluded from failure-rate math.
+ */
+export type TelemetryErrorOwner =
+  "environment" | "provider" | "openwiki" | "unowned" | "control";
+
+/**
+ * Ordered pipeline stage a failure was tagged at: config -> build -> run ->
+ * finalize. Lets a failure be read as "where in the run did it break", so a class
+ * can be located to a phase. An untagged failure carries no stage (the field is
+ * omitted), which reads as "not instrumented here" rather than a named bucket.
+ */
+export type TelemetryErrorStage = "config" | "build" | "run" | "finalize";
 
 /**
  * Which brain a run targeted.
@@ -43,10 +76,47 @@ export interface RunTelemetry {
   outcome: "success" | "failure" | "noop";
 
   /**
-   * Closed-set failure category. Present only when `outcome` is "failure".
+   * Closed-set failure family. Present only when `outcome` is "failure".
    */
   errorClass?: TelemetryErrorClass;
 
+  /**
+   * The specific failure within `errorClass`, from that family's hardcoded
+   * allowlist (see `taxonomy.ts`), e.g. `auth` inside `provider_error`. One shared
+   * property across all families. Anything off the family's allowlist is dropped to
+   * undefined rather than sent raw, so the anonymity envelope stays closed.
+   *
+   * @default undefined - the family has no detail split, or the observed detail was
+   * not on the family's allowlist; the field is omitted rather than sent raw.
+   */
+  errorDetail?: string;
+
+  /**
+   * Who owns the fix, derived from (class, detail, stage) at record time. Emitted
+   * (not left for PostHog to derive) because the owner rules include cross-owner
+   * exceptions PostHog cannot express. Present only when `outcome` is "failure".
+   *
+   * @default undefined - no failure to attribute (the run did not fail).
+   */
+  errorOwner?: TelemetryErrorOwner;
+
+  /**
+   * Pipeline stage the failure was tagged at. Present only when `outcome` is
+   * "failure", and only when the throwing path was instrumented.
+   *
+   * @default undefined - the error carried no stage tag; the throw site is not
+   * instrumented, so no stage is emitted.
+   */
+  errorStage?: TelemetryErrorStage;
+
+  /**
+   * HTTP-ish status read off the provider error, when one was present. A bare
+   * integer; no provider strings ride with it. Present only on failure.
+   *
+   * @default undefined - the error exposed no numeric status.
+   */
+  httpStatus?: number;
+
   /**
    * Which brain was set up (code = repository, personal = local wiki). Init
    * only; undefined on updates.
diff --git a/src/telemetry/with-run-telemetry.ts b/src/telemetry/with-run-telemetry.ts
new file mode 100644
--- /dev/null
+++ b/src/telemetry/with-run-telemetry.ts
@@ -0,0 +1,85 @@
+import type { OpenWikiCommand, OpenWikiRunOptions } from "../agent/types.js";
+import type { OpenWikiProvider } from "../constants.js";
+
+import { describeErrorForTelemetry } from "./errors.js";
+import { recordRunSafe } from "./record-run-safe.js";
+
+/**
+ * Mutable run facts that resolve as a run proceeds, enriched in place by
+ * `runOpenWikiAgent` and read by {@link withRunTelemetry} once the run settles.
+ *
+ * This is what lets the single telemetry boundary sit *outside* the agent, wrapping
+ * the pre-agent repo setup and connector pulls that today reach no telemetry, while
+ * still attributing the provider and a `noop` short-circuit that are only knowable
+ * *inside* the agent. The caller creates one, hands it to both the wrapper and the
+ * agent, and the agent writes to it as those facts become known.
+ */
+export interface RunTelemetryContext {
+  /**
+   * The resolved LLM provider, published the instant provider resolution succeeds so
+   * that a failure later in the run still attributes the right provider.
+   *
+   * @default undefined - resolution never reached the provider (e.g. a pre-agent
+   * setup or connector throw, or the very first resolution step threw); the run is
+   * recorded with provider "unknown".
+   */
+  provider?: OpenWikiProvider;
+
+  /**
+   * The non-failure outcome the run reached, set by the agent. The wrapper defaults a
+   * clean return to "success" and any throw to "failure", so only a `noop`
+   * short-circuit needs to be published here.
+   *
+   * @default undefined - the run returned without short-circuiting; recorded as
+   * "success".
+   */
+  outcome?: "success" | "noop";
+}
+
+/**
+ * The single telemetry boundary for one run: the sole place an `openwiki_run` event
+ * is recorded.
+ *
+ * It wraps the whole setup -> connectors -> agent sequence a caller performs, so a
+ * failure anywhere in that sequence (repo setup, connector pull, agent prologue, or
+ * the agent itself) is recorded exactly once, closing the pre-agent coverage holes
+ * where a throw previously reached no telemetry. On a clean return it records the
+ * outcome the agent published on `ctx` (defaulting to "success"); on a throw it
+ * records "failure" with the anonymous diagnostics from
+ * {@link describeErrorForTelemetry}, then rethrows so the CLI still owns the failure
+ * UX. It never throws from telemetry: `recordRunSafe` swallows its own errors.
+ *
+ * @param command - Which run lifecycle this is. Only init/update are recorded; chat
+ *   is dropped downstream by `recordRunSafe`.
+ * @param options - The run options; `recordRunSafe` reads `outputMode` and
+ *   `telemetryFile` from them.
+ * @param ctx - The mutable context the wrapped `run` enriches (provider, outcome).
+ * @param run - The run to perform and record: setup, connectors, and the agent.
+ */
+export async function withRunTelemetry<T>(
+  command: OpenWikiCommand,
+  options: OpenWikiRunOptions,
+  ctx: RunTelemetryContext,
+  run: () => Promise<T>,
+): Promise<T> {
+  try {
+    const result = await run();
+
+    await recordRunSafe(command, options, {
+      provider: ctx.provider,
+      outcome: ctx.outcome ?? "success",
+    });
+
+    return result;
+  } catch (error) {
+    await recordRunSafe(command, options, {
+      provider: ctx.provider,
+      outcome: "failure",
+      // Class, detail, owner, stage, and status in one spread. Everything rides
+      // closed-set enums or bare integers; no error text enters the payload.
+      ...describeErrorForTelemetry(error),
+    });
+
+    throw error;
+  }
+}
diff --git a/src/visualize/client-lib.ts b/src/visualize/client-lib.ts
new file mode 100644
--- /dev/null
+++ b/src/visualize/client-lib.ts
@@ -0,0 +1,156 @@
+import type { WikiGraph } from "./graph.js";
+
+/**
+ * The minimal node shape the search/type filter needs. Both the raw wiki nodes
+ * from /api/graph and the force-graph render objects satisfy it structurally.
+ */
+export interface FilterableNode {
+  /**
+   * Stable page id (path relative to the wiki root, without .md).
+   */
+  id: string;
+
+  /**
+   * Display title.
+   */
+  title: string;
+
+  /**
+   * Page kind, matched against the active type filter.
+   */
+  type: string;
+
+  /**
+   * Topic tags, folded into the free-text search haystack.
+   *
+   * @default undefined - treated as no tags.
+   */
+  tags?: readonly string[];
+}
+
+/**
+ * Node sphere colors, keyed by draw order. Saturated enough to hold their hue as
+ * lit 3D spheres (pale pastels blow out to white under the scene lighting); the
+ * legend swatches reuse these same values.
+ */
+export const PALETTE: readonly string[] = [
+  "#4FA8F0",
+  "#B6DE3E",
+  "#D96FA6",
+  "#A97FE0",
+  "#D98A6B",
+  "#3FBFA0",
+  "#E0A63E",
+  "#6E8FF0",
+];
+
+/**
+ * HTML-escape the five characters that could break out of text or an attribute
+ * value, so wiki-sourced strings are safe to assign to innerHTML.
+ */
+const HTML_ESCAPES: Record<string, string> = {
+  "&": "&amp;",
+  "<": "&lt;",
+  ">": "&gt;",
+  '"': "&quot;",
+};
+
+/**
+ * Escape the HTML-significant characters in a string before it is inserted into
+ * the DOM. This is the sole XSS gate for wiki-sourced text.
+ */
+export function escapeHtml(value: string): string {
+  return value.replace(/[&<>"]/g, (char) => HTML_ESCAPES[char] ?? char);
+}
+
+/**
+ * Map each distinct node type to a palette color by its position in the list, so
+ * the graph and legend agree on colors and they stay stable across reloads.
+ */
+export function colorsForTypes(
+  types: readonly string[],
+  palette: readonly string[] = PALETTE,
+): Record<string, string> {
+  const colors: Record<string, string> = {};
+  types.forEach((type, i) => {
+    colors[type] = palette[i % palette.length];
+  });
+  return colors;
+}
+
+/**
+ * Convert a `#RRGGBB` hex color plus an alpha into an `rgba(...)` string, for
+ * canvas glow fills and dimming. A non-6-digit input is returned unchanged.
+ */
+export function hexA(hex: string, alpha: number): string {
+  const c = (hex || "").replace("#", "");
+  if (c.length !== 6) return hex;
+  const channel = (i: number): number => parseInt(c.slice(i, i + 2), 16);
+  return `rgba(${channel(0)}, ${channel(2)}, ${channel(4)}, ${alpha})`;
+}
+
+/**
+ * Node circle radius in graph units, scaled by page length and capped, with a
+ * bonus for the entry (anchor) page so it reads as the starting point.
+ */
+export function nodeRadius(size: number, isAnchor: boolean): number {
+  return 4 + Math.min(7, (size || 0) / 480) + (isAnchor ? 4 : 0);
+}
+
+/**
+ * Whether a node survives the active search text and type filter. An empty query
+ * or empty type matches everything.
+ */
+export function matchesFilter(
+  node: FilterableNode,
+  query: string,
+  type: string,
+): boolean {
+  const haystack = `${node.title} ${node.id} ${(node.tags ?? []).join(" ")}`;
+  const matchesQuery = !query || haystack.toLowerCase().includes(query);
+  const matchesType = !type || node.type === type;
+  return matchesQuery && matchesType;
+}
+
+/**
+ * A stable fingerprint of the graph's topology (its node ids and directed edges).
+ * When it is unchanged across a reload, the scene can be left untouched so the
+ * layout and viewport do not snap.
+ */
+export function signature(graph: Pick<WikiGraph, "nodes" | "edges">): string {
+  const nodes = graph.nodes
+    .map((node) => node.id)
+    .sort()
+    .join("|");
+  const edges = graph.edges
+    .map((edge) => `${edge.source}>${edge.target}`)
+    .sort()
+    .join("|");
+  return `${nodes}::${edges}`;
+}
+
+/**
+ * Strip a leading YAML frontmatter block from a markdown body before it is
+ * rendered in the reader. A body without frontmatter is returned unchanged.
+ */
+export function stripFrontmatter(body: string): string {
+  if (!body.startsWith("---")) return body;
+  const end = body.indexOf("\n---", 3);
+  return end === -1 ? body : body.slice(body.indexOf("\n", end + 1) + 1);
+}
+
+/**
+ * Resolve a relative link (`rel`) against a page's directory (`baseDir`) into a
+ * normalized wiki path, collapsing `.` and `..` segments. Used to turn in-page
+ * markdown links into node ids for in-app navigation.
+ */
+export function normalize(baseDir: string, rel: string): string {
+  const parts = (baseDir ? baseDir.split("/") : []).concat(rel.split("/"));
+  const out: string[] = [];
+  for (const part of parts) {
+    if (part === "" || part === ".") continue;
+    if (part === "..") out.pop();
+    else out.push(part);
+  }
+  return out.join("/");
+}
diff --git a/src/visualize/client.ts b/src/visualize/client.ts
new file mode 100644
--- /dev/null
+++ b/src/visualize/client.ts
@@ -0,0 +1,886 @@
+import type { WikiGraph, WikiNode } from "./graph.js";
+import {
+  colorsForTypes,
+  escapeHtml,
+  hexA,
+  matchesFilter,
+  nodeRadius,
+  normalize,
+  signature,
+  stripFrontmatter,
+} from "./client-lib.js";
+
+// --- Render model -----------------------------------------------------------
+
+/**
+ * A force-graph render node: a persisted object (its identity survives reloads
+ * so positions and camera stay put) carrying the fields the canvas painter reads.
+ */
+interface GraphNode {
+  /**
+   * Stable page id: the path relative to the wiki root, without the .md suffix.
+   */
+  id: string;
+
+  /**
+   * Display title.
+   */
+  title: string;
+
+  /**
+   * Page kind; selects the node's color from the palette.
+   */
+  type: string;
+
+  /**
+   * Body length in characters; scales the rendered radius.
+   */
+  size: number;
+
+  /**
+   * Topic tags.
+   */
+  tags: string[];
+
+  /**
+   * One-line summary, or "" when the page declares none.
+   */
+  description: string;
+
+  /**
+   * Resolved fill color for this node's type.
+   */
+  color: string;
+
+  /**
+   * Whether this is the entry page, drawn larger and always labelled.
+   */
+  anchor: boolean;
+
+  /**
+   * Rendered radius in graph units.
+   */
+  r: number;
+
+  /**
+   * Layout x position, assigned by force-graph once simulated (undefined before).
+   */
+  x?: number;
+
+  /**
+   * Layout y position, assigned by force-graph once simulated (undefined before).
+   */
+  y?: number;
+}
+
+/**
+ * A force-graph link. force-graph resolves the string endpoints from the wire
+ * format into node object references in place once the data is ingested, so by
+ * the time any accessor below runs, source and target are GraphNode objects.
+ */
+interface GraphLink {
+  /**
+   * Origin node (a wire-format id string until force-graph resolves it in place).
+   */
+  source: GraphNode;
+
+  /**
+   * Destination node (a wire-format id string until resolved in place).
+   */
+  target: GraphNode;
+}
+
+/**
+ * The node/link payload force-graph renders.
+ */
+interface GraphData {
+  /**
+   * Every render node in the graph.
+   */
+  nodes: GraphNode[];
+
+  /**
+   * Every link between render nodes.
+   */
+  links: GraphLink[];
+}
+
+// --- Third-party globals (loaded from the CDN <script> tags) ----------------
+
+/**
+ * The subset of the force-graph fluent API this app uses. Every setter returns
+ * the instance so calls chain; graphData is overloaded as getter and setter.
+ */
+interface ForceGraphInstance {
+  /**
+   * Mount the graph into a container element and return the instance.
+   */
+  (element: HTMLElement): ForceGraphInstance;
+
+  /**
+   * Set the canvas background color.
+   */
+  backgroundColor(color: string): ForceGraphInstance;
+
+  /**
+   * Set the base node size the renderer scales from.
+   */
+  nodeRelSize(size: number): ForceGraphInstance;
+
+  /**
+   * Choose how the custom node paint composes with the default ("replace" here).
+   */
+  nodeCanvasObjectMode(mode: () => string): ForceGraphInstance;
+
+  /**
+   * Register the custom per-node canvas painter.
+   */
+  nodeCanvasObject(
+    paint: (
+      node: GraphNode,
+      ctx: CanvasRenderingContext2D,
+      scale: number,
+    ) => void,
+  ): ForceGraphInstance;
+
+  /**
+   * Register the painter for each node's pointer hit area.
+   */
+  nodePointerAreaPaint(
+    paint: (
+      node: GraphNode,
+      color: string,
+      ctx: CanvasRenderingContext2D,
+    ) => void,
+  ): ForceGraphInstance;
+
+  /**
+   * Set the per-link stroke color.
+   */
+  linkColor(accessor: (link: GraphLink) => string): ForceGraphInstance;
+
+  /**
+   * Set the per-link stroke width.
+   */
+  linkWidth(accessor: (link: GraphLink) => number): ForceGraphInstance;
+
+  /**
+   * Set the link curvature (0 = straight).
+   */
+  linkCurvature(curvature: number): ForceGraphInstance;
+
+  /**
+   * Set how many directional particles travel along each link.
+   */
+  linkDirectionalParticles(
+    accessor: (link: GraphLink) => number,
+  ): ForceGraphInstance;
+
+  /**
+   * Set the width of the directional particles.
+   */
+  linkDirectionalParticleWidth(
+    accessor: (link: GraphLink) => number,
+  ): ForceGraphInstance;
+
+  /**
+   * Set the travel speed of the directional particles.
+   */
+  linkDirectionalParticleSpeed(speed: number): ForceGraphInstance;
+
+  /**
+   * Set the color of the directional particles.
+   */
+  linkDirectionalParticleColor(accessor: () => string): ForceGraphInstance;
+
+  /**
+   * Register the node-click handler.
+   */
+  onNodeClick(handler: (node: GraphNode) => void): ForceGraphInstance;
+
+  /**
+   * Register the node-hover handler (null when the pointer leaves all nodes).
+   */
+  onNodeHover(handler: (node: GraphNode | null) => void): ForceGraphInstance;
+
+  /**
+   * Register the background (empty space) click handler.
+   */
+  onBackgroundClick(handler: () => void): ForceGraphInstance;
+
+  /**
+   * Set the canvas width in pixels.
+   */
+  width(width: number): ForceGraphInstance;
+
+  /**
+   * Set the canvas height in pixels.
+   */
+  height(height: number): ForceGraphInstance;
+
+  /**
+   * Set the zoom level (higher is more zoomed in).
+   */
+  zoom(zoom: number): ForceGraphInstance;
+
+  /**
+   * Feed the node/link data to render.
+   */
+  graphData(data: GraphData): ForceGraphInstance;
+
+  /**
+   * Read back the current data, with force-graph's resolved link endpoints.
+   */
+  graphData(): GraphData;
+
+  /**
+   * Access a named d3 force to tune its strength (e.g. "charge").
+   */
+  d3Force(name: string): { strength(value: number): void };
+}
+
+/**
+ * The force-graph factory global (UMD build from the CDN <script> tag).
+ */
+declare const ForceGraph: () => ForceGraphInstance;
+
+/**
+ * The marked global: markdown -> HTML, configured once at bootstrap.
+ */
+declare const marked: {
+  parse(markdown: string): string;
+  setOptions(options: Record<string, unknown>): void;
+};
+
+/**
+ * The mermaid global: renders fenced diagram code blocks in place.
+ */
+declare const mermaid: {
+  initialize(config: Record<string, unknown>): void;
+  run(options: { nodes: NodeListOf<Element> }): void;
+};
+
+/**
+ * The DOMPurify global: strips scripts, inline event handlers, and dangerous URL
+ * schemes from an HTML string before it is assigned to innerHTML. The default
+ * configuration is used, which already removes the injection vectors relevant here.
+ */
+declare const DOMPurify: {
+  sanitize(dirty: string): string;
+};
+
+// --- Module state -----------------------------------------------------------
+
+/**
+ * The full wiki graph as last fetched from /api/graph.
+ */
+let graph: WikiGraph = {
+  root: "",
+  generatedAt: "",
+  types: [],
+  nodes: [],
+  edges: [],
+};
+
+/**
+ * Node fill color per page type, rebuilt on each load.
+ */
+let colorForType: Record<string, string> = {};
+
+/**
+ * The live force-graph instance, or null before the first render.
+ */
+let G: ForceGraphInstance | null = null;
+
+/**
+ * Id of the selected node (drives the highlight), or null when nothing is selected.
+ */
+let current: string | null = null;
+
+/**
+ * Id of the page shown in the reader and marked active in the index, or null.
+ */
+let readerId: string | null = null;
+
+/**
+ * Id of the entry page, drawn larger and always labelled, or null before load.
+ */
+let anchorId: string | null = null;
+
+/**
+ * Topology signature of the last render, used to skip redundant re-layouts.
+ */
+let lastSig = "";
+
+/**
+ * Active search text. Reserved for a future search box; "" means "match all".
+ */
+const filterQ = "";
+
+/**
+ * Active type filter. Reserved for a future filter UI; "" means "match all".
+ */
+const filterType = "";
+
+/**
+ * Persisted render-node objects keyed by id, reused across reloads so layout holds.
+ */
+const nodeById = new Map<string, GraphNode>();
+
+/**
+ * Nodes currently emphasised (the selection/hover neighbourhood).
+ */
+const highlightNodes = new Set<GraphNode>();
+
+/**
+ * Links currently emphasised (edges within the highlighted neighbourhood).
+ */
+const highlightLinks = new Set<GraphLink>();
+
+// --- DOM and theme helpers --------------------------------------------------
+
+/**
+ * Query one element by selector, typed as HTMLElement (every target here exists).
+ */
+const $ = (sel: string): HTMLElement =>
+  document.querySelector(sel) as HTMLElement;
+
+/**
+ * Look up a wiki node by id, or undefined when it is not in the current graph.
+ */
+const byId = (id: string): WikiNode | undefined =>
+  graph.nodes.find((n) => n.id === id);
+
+/**
+ * Read a CSS custom property off the body, so colors follow the active theme.
+ */
+const cssVar = (name: string): string =>
+  getComputedStyle(document.body).getPropertyValue(name).trim();
+
+/**
+ * The current node-label text color.
+ */
+const labelColor = (): string => cssVar("--node-label");
+
+/**
+ * The current edge (link) color.
+ */
+const edgeColor = (): string => cssVar("--edge");
+
+/**
+ * The current graph-canvas background color.
+ */
+const graphBg = (): string => cssVar("--graph-bg");
+
+/**
+ * The reader panel's empty-state markup, captured before any page is rendered.
+ */
+const EMPTY_HTML = $("#detail").innerHTML;
+
+/**
+ * Whether a node is the entry (anchor) page.
+ */
+const isAnchor = (n: { id: string }): boolean => n.id === anchorId;
+
+/**
+ * Whether a node survives the active search text and type filter.
+ */
+const passesFilter = (n: WikiNode | GraphNode): boolean =>
+  matchesFilter(n, filterQ, filterType);
+
+// --- Legend and sidebar (the page index) ------------------------------------
+
+/**
+ * Recompute the per-type node colors for the current graph.
+ */
+function assignColors(): void {
+  colorForType = colorsForTypes(graph.types);
+}
+
+/**
+ * Render the type/color legend.
+ */
+function buildLegend(): void {
+  $("#legend").innerHTML = graph.types
+    .map(
+      (t) =>
+        `<div class="item"><span class="swatch" style="background:${colorForType[t]}"></span>${escapeHtml(t)}</div>`,
+    )
+    .join("");
+}
+
+/**
+ * The whole wiki as a browsable index: pages grouped by type, always visible.
+ * All wiki-sourced text goes through escapeHtml; colors come from our palette.
+ */
+function buildSidebar(): void {
+  const groups = graph.types
+    .map((t) => ({
+      t,
+      items: graph.nodes
+        .filter((n) => n.type === t)
+        .sort((a, b) => a.title.localeCompare(b.title)),
+    }))
+    .filter((g) => g.items.length);
+  const head =
+    `<div class="sb-head"><span class="sb-title">Pages</span>` +
+    `<span class="sb-count">${graph.nodes.length}</span></div>`;
+  const body = groups
+    .map((g) => {
+      const items = g.items
+        .map(
+          (n) =>
+            `<button class="nav-item" data-id="${escapeHtml(n.id)}">` +
+            `<span class="dot" style="background:${colorForType[g.t]}"></span>` +
+            `<span class="nm" title="${escapeHtml(n.title)}">${escapeHtml(n.title)}</span></button>`,
+        )
+        .join("");
+      return (
+        `<div class="sb-group"><div class="sb-group-head">` +
+        `<span class="swatch" style="background:${colorForType[g.t]}"></span>${escapeHtml(g.t)}</div>` +
+        items +
+        `</div>`
+      );
+    })
+    .join("");
+  $("#sidebar").innerHTML = head + body;
+  $("#sidebar")
+    .querySelectorAll<HTMLElement>(".nav-item")
+    .forEach((b) =>
+      b.addEventListener("click", () => {
+        const id = b.dataset.id;
+        if (id) selectNode(id);
+      }),
+    );
+  refreshSidebarActive();
+  refreshSidebarFilter();
+}
+
+/**
+ * Highlight the page open in the reader and scroll it into view in the index.
+ */
+function refreshSidebarActive(): void {
+  $("#sidebar")
+    .querySelectorAll<HTMLElement>(".nav-item")
+    .forEach((b) => {
+      const on = b.dataset.id === readerId;
+      b.classList.toggle("active", on);
+      if (on) b.scrollIntoView({ block: "nearest" });
+    });
+}
+
+/**
+ * Hide index rows (and emptied groups) that the search/type filter excludes.
+ */
+function refreshSidebarFilter(): void {
+  $("#sidebar")
+    .querySelectorAll<HTMLElement>(".nav-item")
+    .forEach((b) => {
+      const n = byId(b.dataset.id ?? "");
+      b.classList.toggle("hidden", !n || !passesFilter(n));
+    });
+  $("#sidebar")
+    .querySelectorAll(".sb-group")
+    .forEach((g) => {
+      const anyVisible = [...g.querySelectorAll(".nav-item")].some(
+        (b) => !b.classList.contains("hidden"),
+      );
+      g.classList.toggle("hidden", !anyVisible);
+    });
+}
+
+// --- Graph canvas -----------------------------------------------------------
+
+/**
+ * Create the force-graph instance and wire its paint, link, and interaction
+ * callbacks, then pin the canvas to its column and loosen the charge force.
+ */
+function initGraph(): void {
+  const container = $("#graph");
+  G = ForceGraph()(container)
+    .backgroundColor(graphBg())
+    .nodeRelSize(4)
+    .nodeCanvasObjectMode(() => "replace")
+    .nodeCanvasObject(paintNode)
+    .nodePointerAreaPaint((n, color, ctx) => {
+      // Hit area matches the drawn circle so clicks/hover line up with the glow.
+      ctx.fillStyle = color;
+      ctx.beginPath();
+      ctx.arc(n.x ?? 0, n.y ?? 0, n.r + 3, 0, 2 * Math.PI);
+      ctx.fill();
+    })
+    .linkColor((l) => {
+      if (isLinkDimmed(l)) return hexA(edgeColor(), 0.05);
+      return highlightLinks.has(l) ? "#7FC8FF" : hexA(edgeColor(), 0.7);
+    })
+    .linkWidth((l) => (highlightLinks.has(l) ? 2 : 0.7))
+    .linkCurvature(0.12)
+    .linkDirectionalParticles((l) =>
+      isLinkDimmed(l) ? 0 : highlightLinks.has(l) ? 4 : 2,
+    )
+    .linkDirectionalParticleWidth((l) => (highlightLinks.has(l) ? 2.6 : 1.7))
+    .linkDirectionalParticleSpeed(0.006)
+    .linkDirectionalParticleColor(() => "#7FC8FF")
+    .onNodeClick((n) => selectNode(n.id))
+    .onNodeHover(hoverHighlight)
+    .onBackgroundClick(clearSelection);
+
+  // Pin the canvas to its column. Without this, force-graph falls back to the
+  // window width and centres the graph behind the reader/index panels.
+  const fitSize = (): void => {
+    if (G) G.width(container.clientWidth).height(container.clientHeight);
+  };
+  fitSize();
+  new ResizeObserver(fitSize).observe(container);
+
+  // A little breathing room so nodes settle apart instead of clumping.
+  G.d3Force("charge").strength(-140);
+}
+
+/**
+ * Obsidian-style node: a soft colored glow, a solid core, and a legible label.
+ */
+function paintNode(
+  n: GraphNode,
+  ctx: CanvasRenderingContext2D,
+  scale: number,
+): void {
+  if (n.x === undefined || n.y === undefined) return;
+  const dim = !passesFilter(n);
+  const sel = n.id === current;
+  const hot = highlightNodes.has(n);
+  const r = n.r;
+  const base = dim ? 0.12 : 1;
+
+  // Glow halo (skipped when dimmed so filtered-out nodes recede).
+  if (!dim) {
+    const gr = r * (sel ? 3.4 : hot ? 2.8 : 2.2);
+    const glow = ctx.createRadialGradient(n.x, n.y, r * 0.5, n.x, n.y, gr);
+    glow.addColorStop(0, hexA(n.color, sel ? 0.5 : hot ? 0.38 : 0.22));
+    glow.addColorStop(1, hexA(n.color, 0));
+    ctx.fillStyle = glow;
+    ctx.beginPath();
+    ctx.arc(n.x, n.y, gr, 0, 2 * Math.PI);
+    ctx.fill();
+  }
+
+  // Solid core.
+  ctx.globalAlpha = base;
+  ctx.beginPath();
+  ctx.arc(n.x, n.y, r, 0, 2 * Math.PI);
+  ctx.fillStyle = sel ? "#FFFFFF" : n.color;
+  ctx.fill();
+  if (sel || hot) {
+    ctx.lineWidth = 1.6 / scale;
+    ctx.strokeStyle = hexA("#FFFFFF", 0.92);
+    ctx.stroke();
+  }
+
+  // Label: always drawn when zoomed in enough (or for notable nodes), with a
+  // dark halo behind the text so it stays readable over links and glows.
+  if (scale > 0.5 || sel || hot || n.anchor) {
+    const fs = Math.max(10 / scale, 3.2);
+    ctx.font = `${sel || n.anchor ? 700 : 600} ${fs}px Inter, sans-serif`;
+    ctx.textAlign = "center";
+    ctx.textBaseline = "top";
+    const y = n.y + r + 2.5 / scale;
+    ctx.globalAlpha = dim ? 0.25 : 1;
+    ctx.lineWidth = 3.5 / scale;
+    ctx.strokeStyle = hexA(graphBg(), 0.9);
+    ctx.strokeText(n.title, n.x, y);
+    ctx.fillStyle = sel ? "#FFFFFF" : labelColor();
+    ctx.fillText(n.title, n.x, y);
+  }
+  ctx.globalAlpha = 1;
+}
+
+/**
+ * Whether a link should recede because the active filter excludes an endpoint.
+ */
+function isLinkDimmed(l: GraphLink): boolean {
+  if (!filterQ && !filterType) return false;
+  return !passesFilter(l.source) || !passesFilter(l.target);
+}
+
+/**
+ * Fill the highlight sets with a node and its immediate neighbourhood.
+ */
+function neighborsOf(node: GraphNode | undefined): void {
+  highlightNodes.clear();
+  highlightLinks.clear();
+  if (!node || !G) return;
+  highlightNodes.add(node);
+  G.graphData().links.forEach((l) => {
+    if (l.source === node || l.target === node) {
+      highlightLinks.add(l);
+      highlightNodes.add(l.source);
+      highlightNodes.add(l.target);
+    }
+  });
+}
+
+/**
+ * Highlight a node's neighbourhood on hover, unless a page is already selected.
+ */
+function hoverHighlight(node: GraphNode | null): void {
+  if (current) return; // a selected page keeps its own highlight
+  neighborsOf(node ?? undefined);
+  $("#graph").style.cursor = node ? "pointer" : "";
+}
+
+// --- Selection and reader ---------------------------------------------------
+
+/**
+ * Select a node: highlight its neighbourhood and open it in the reader.
+ *
+ * Intentionally does NOT move the camera: clicking a node to read it should
+ * never yank the graph out from under you. Pan/zoom stay where you left them.
+ */
+function selectNode(id: string): void {
+  current = id;
+  neighborsOf(nodeById.get(id));
+  renderReader(id);
+}
+
+/**
+ * Clear the selection and restore the reader's empty state.
+ */
+function clearSelection(): void {
+  current = null;
+  readerId = null;
+  highlightNodes.clear();
+  highlightLinks.clear();
+  $("#detail").innerHTML = EMPTY_HTML;
+  refreshSidebarActive();
+}
+
+/**
+ * Render the reader panel for a page. DOM-only: never moves the camera.
+ */
+function renderReader(id: string): void {
+  const n = byId(id);
+  if (!n) return;
+  readerId = id;
+  const tags = n.tags.length
+    ? `<div class="tags">${n.tags.map((t) => `<span class="tag">${escapeHtml(t)}</span>`).join("")}</div>`
+    : "";
+  const desc = n.description
+    ? `<p class="desc">${escapeHtml(n.description)}</p>`
+    : "";
+  const backEls = n.backlinks
+    .map((b) => {
+      const t = byId(b);
+      return t
+        ? `<span class="chip" data-id="${b}">${escapeHtml(t.title)}</span>`
+        : "";
+    })
+    .join("");
+  const back = n.backlinks.length
+    ? `<div class="backlinks"><span class="eyebrow">Referenced by</span>${backEls}</div>`
+    : "";
+  // The page body is rendered as markdown, and marked passes raw HTML through, so
+  // sanitize before innerHTML: DOMPurify strips scripts, event handlers, and unsafe
+  // URL schemes. This is defense in depth on top of the server's CSP.
+  const html = DOMPurify.sanitize(marked.parse(stripFrontmatter(n.body)));
+  $("#detail").innerHTML =
+    `<div class="eyebrow">${escapeHtml(n.type)}</div>` +
+    `<h1 class="doc-title">${escapeHtml(n.title)}</h1>` +
+    desc +
+    tags +
+    `<hr class="rule" />` +
+    `<div class="md">${html}</div>` +
+    back;
+  rewriteLinks(n);
+  renderMermaid();
+  $("#detail").scrollTop = 0;
+  $("#detail")
+    .querySelectorAll<HTMLElement>(".chip")
+    .forEach((c) =>
+      c.addEventListener("click", () => {
+        const id = c.dataset.id;
+        if (id) selectNode(id);
+      }),
+    );
+  refreshSidebarActive();
+}
+
+/**
+ * Turn in-page markdown links that resolve to a node into in-app navigation.
+ */
+function rewriteLinks(node: WikiNode): void {
+  const dir = node.id.includes("/")
+    ? node.id.slice(0, node.id.lastIndexOf("/"))
+    : "";
+  $("#detail")
+    .querySelectorAll<HTMLAnchorElement>(".md a")
+    .forEach((a) => {
+      const href = a.getAttribute("href") ?? "";
+      if (!href.endsWith(".md") && !href.includes(".md#")) return;
+      const clean = href.split("#")[0];
+      const target = normalize(dir, clean).replace(/\.md$/, "");
+      if (byId(target)) {
+        a.classList.add("wikilink");
+        a.addEventListener("click", (e) => {
+          e.preventDefault();
+          selectNode(target);
+        });
+      }
+    });
+}
+
+/**
+ * Upgrade fenced mermaid code blocks in the reader into rendered diagrams.
+ */
+function renderMermaid(): void {
+  const blocks = $("#detail").querySelectorAll("code.language-mermaid");
+  let i = 0;
+  blocks.forEach((code) => {
+    const pre = document.createElement("pre");
+    pre.className = "mermaid";
+    pre.textContent = code.textContent;
+    code.closest("pre")?.replaceWith(pre);
+    i++;
+  });
+  if (i > 0) {
+    try {
+      mermaid.run({ nodes: $("#detail").querySelectorAll(".mermaid") });
+    } catch {
+      // Diagram render failures are non-fatal; leave the source block in place.
+    }
+  }
+}
+
+// --- Theme ------------------------------------------------------------------
+
+/**
+ * Toggle light/dark theme, re-theming mermaid, the canvas, and the open page.
+ */
+function toggleTheme(): void {
+  const root = document.documentElement;
+  const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
+  root.setAttribute("data-theme", next);
+  mermaid.initialize({
+    startOnLoad: false,
+    theme: next === "dark" ? "dark" : "neutral",
+  });
+  if (G) G.backgroundColor(graphBg()); // node/label colors are read live each frame
+  if (current) renderReader(current);
+}
+
+// --- Data load and live reload ----------------------------------------------
+
+/**
+ * Fetch the graph and (re)render everything. Preserves the layout and viewport
+ * when the topology is unchanged, so a live reload does not snap the graph.
+ */
+async function load(firstTime: boolean): Promise<void> {
+  const res = await fetch("/api/graph");
+  graph = (await res.json()) as WikiGraph;
+  $("#wiki-name").textContent = `${graph.root} · ${graph.nodes.length} pages`;
+  const entry =
+    graph.nodes.find((n) => /quickstart/i.test(n.id)) ??
+    graph.nodes.find((n) => /(^|\/)(index|overview|home)$/i.test(n.id)) ??
+    graph.nodes[0];
+  anchorId = entry ? entry.id : null;
+  assignColors();
+  buildLegend();
+  buildSidebar();
+  const sig = signature(graph);
+  if (firstTime) {
+    initGraph();
+    if (G) {
+      G.graphData(buildGraphData());
+      // Start a little more zoomed-in than force-graph's node-count default
+      // (4/∛n). Setting our own zoom also suppresses that default, which only
+      // auto-applies while the zoom is still untouched, so this value sticks.
+      G.zoom((4 / Math.cbrt(graph.nodes.length || 1)) * 1.35);
+    }
+    lastSig = sig;
+  } else if (sig !== lastSig) {
+    // Topology changed: re-feed data, reusing persisted node objects so the
+    // layout and viewport stay put instead of snapping.
+    if (G) G.graphData(buildGraphData());
+    lastSig = sig;
+  }
+  // else: identical topology -> leave the graph and viewport untouched entirely.
+  if (current && byId(current)) renderReader(current);
+  else if (firstTime && anchorId) renderReader(anchorId);
+}
+
+/**
+ * Build the force-graph payload, reusing node objects across reloads so
+ * positions and camera survive a refresh.
+ */
+function buildGraphData(): GraphData {
+  const ids = new Set(graph.nodes.map((n) => n.id));
+  for (const id of [...nodeById.keys()]) if (!ids.has(id)) nodeById.delete(id);
+  const nodes = graph.nodes.map((n) => {
+    let o = nodeById.get(n.id);
+    if (!o) {
+      o = {
+        id: n.id,
+        title: n.title,
+        type: n.type,
+        size: n.size,
+        tags: n.tags,
+        description: n.description,
+        color: "#7FC8FF",
+        anchor: false,
+        r: 4,
+      };
+      nodeById.set(n.id, o);
+    }
+    o.title = n.title;
+    o.type = n.type;
+    o.size = n.size;
+    o.tags = n.tags;
+    o.description = n.description;
+    o.color = colorForType[n.type] || "#7FC8FF";
+    o.anchor = isAnchor(n);
+    o.r = nodeRadius(n.size, isAnchor(n));
+    return o;
+  });
+  // force-graph resolves these string endpoints to node objects in place.
+  const links = graph.edges.map((e) => ({
+    source: e.source,
+    target: e.target,
+  })) as unknown as GraphLink[];
+  return { nodes, links };
+}
+
+/**
+ * Show a transient status toast.
+ */
+function toast(msg: string): void {
+  const t = $("#toast");
+  t.textContent = msg;
+  t.classList.add("show");
+  setTimeout(() => t.classList.remove("show"), 1800);
+}
+
+/**
+ * Subscribe to server-sent reload events and track the live/stale indicator.
+ */
+function connectSSE(): void {
+  const es = new EventSource("/events");
+  es.addEventListener("reload", () => {
+    void load(false).then(() => toast("Wiki updated"));
+  });
+  es.onerror = (): void => {
+    $("#live").classList.add("stale");
+    $("#live-text").textContent = "Reconnecting";
+  };
+  es.onopen = (): void => {
+    $("#live").classList.remove("stale");
+    $("#live-text").textContent = "Live";
+  };
+}
+
+// --- Bootstrap --------------------------------------------------------------
+
+// Wire the theme toggle, configure the markdown/diagram libraries, then do the
+// first load and open the live-reload stream.
+$("#theme").addEventListener("click", toggleTheme);
+mermaid.initialize({ startOnLoad: false, theme: "dark" });
+marked.setOptions({ breaks: false, gfm: true });
+void load(true).then(connectSSE);
diff --git a/src/visualize/graph.ts b/src/visualize/graph.ts
new file mode 100644
--- /dev/null
+++ b/src/visualize/graph.ts
@@ -0,0 +1,338 @@
+import { readFile, readdir } from "node:fs/promises";
+import path from "node:path";
+
+/**
+ * The known-typed subset of frontmatter OpenWiki writes at the top of each page.
+ */
+export interface WikiMeta {
+  /**
+   * The page's declared kind, e.g. "Reference" or "Section".
+   *
+   * @default undefined - a node falls back to "Section" for index pages, else "Reference".
+   */
+  type?: string;
+
+  /**
+   * Explicit page title.
+   *
+   * @default undefined - a node falls back to the section name (index), first H1, then the filename.
+   */
+  title?: string;
+
+  /**
+   * One-line page summary.
+   *
+   * @default undefined - the node's description becomes "".
+   */
+  description?: string;
+
+  /**
+   * Topic tags for the page.
+   *
+   * @default undefined - the node's tags become an empty array.
+   */
+  tags?: string[];
+}
+
+/**
+ * A single wiki page, as one node in the graph.
+ */
+export interface WikiNode {
+  /**
+   * Stable id: the page path relative to the wiki root, without the .md suffix.
+   */
+  id: string;
+
+  /**
+   * Display title, resolved from frontmatter, first heading, or filename.
+   */
+  title: string;
+
+  /**
+   * Page kind, used for node coloring and the legend.
+   */
+  type: string;
+
+  /**
+   * One-line summary, or "" when the page declares none.
+   */
+  description: string;
+
+  /**
+   * Topic tags, or an empty array when the page declares none.
+   */
+  tags: string[];
+
+  /**
+   * Raw markdown body with frontmatter stripped.
+   */
+  body: string;
+
+  /**
+   * Body length in characters, used to scale the node's rendered radius.
+   */
+  size: number;
+
+  /**
+   * Ids of pages this page links to (outgoing edges).
+   */
+  links: string[];
+
+  /**
+   * Ids of pages that link to this page (incoming edges).
+   */
+  backlinks: string[];
+}
+
+/**
+ * A directed link from one page to another.
+ */
+export interface WikiEdge {
+  /**
+   * Id of the page the link starts from.
+   */
+  source: string;
+
+  /**
+   * Id of the page the link points to.
+   */
+  target: string;
+}
+
+/**
+ * The complete in-memory graph, serialized to the browser at /api/graph.
+ */
+export interface WikiGraph {
+  /**
+   * Basename of the wiki root directory, shown in the page header.
+   */
+  root: string;
+
+  /**
+   * ISO-8601 timestamp of when this graph was built.
+   */
+  generatedAt: string;
+
+  /**
+   * All distinct node types present, sorted, for the legend.
+   */
+  types: string[];
+
+  /**
+   * Every page in the wiki.
+   */
+  nodes: WikiNode[];
+
+  /**
+   * Every resolved directed link between pages.
+   */
+  edges: WikiEdge[];
+}
+
+/**
+ * A raw frontmatter map: each key is either a scalar string or a string list.
+ */
+type RawMeta = Record<string, string | string[]>;
+
+/**
+ * Pages that are generation scaffolding, not real wiki content.
+ */
+const EXCLUDED_FILES = new Set(["INSTRUCTIONS.md", "log.md", "_plan.md"]);
+
+/**
+ * Matches a relative markdown link target (`foo.md`, optionally with an `#anchor`).
+ */
+const MARKDOWN_LINK = /\]\(([^)\s]+\.md)(?:#[^)]*)?\)/g;
+
+/**
+ * Strip a single pair of surrounding single or double quotes.
+ */
+function stripQuotes(value: string): string {
+  return value.replace(/^['"]|['"]$/g, "");
+}
+
+/**
+ * Split a markdown file's YAML frontmatter from its body. Only the small subset
+ * OpenWiki emits (scalars, inline `[a, b]` arrays, and dashed lists) is parsed.
+ */
+export function splitFrontmatter(raw: string): { meta: RawMeta; body: string } {
+  if (!raw.startsWith("---")) {
+    return { meta: {}, body: raw };
+  }
+  const end = raw.indexOf("\n---", 3);
+  if (end === -1) {
+    return { meta: {}, body: raw };
+  }
+  const block = raw.slice(3, end).trim();
+  const body = raw.slice(raw.indexOf("\n", end + 1) + 1);
+  const meta: RawMeta = {};
+  let pendingListKey: string | undefined;
+  for (const line of block.split("\n")) {
+    const listItem = line.match(/^\s*-\s+(.*)$/);
+    if (listItem && pendingListKey) {
+      (meta[pendingListKey] as string[]).push(stripQuotes(listItem[1].trim()));
+      continue;
+    }
+    const kv = line.match(/^([A-Za-z0-9_]+):\s*(.*)$/);
+    if (!kv) continue;
+    const [, key, rawValue] = kv;
+    const value = rawValue.trim();
+    if (value === "") {
+      pendingListKey = key;
+      meta[key] = [];
+    } else if (value.startsWith("[") && value.endsWith("]")) {
+      pendingListKey = undefined;
+      meta[key] = value
+        .slice(1, -1)
+        .split(",")
+        .map((item) => stripQuotes(item.trim()))
+        .filter(Boolean);
+    } else {
+      pendingListKey = undefined;
+      meta[key] = stripQuotes(value);
+    }
+  }
+  return { meta, body };
+}
+
+/**
+ * Read the known OpenWiki fields out of a raw frontmatter map, typed.
+ */
+function readMeta(raw: RawMeta): WikiMeta {
+  const scalar = (value: string | string[] | undefined): string | undefined =>
+    typeof value === "string" ? value : undefined;
+  return {
+    type: scalar(raw.type),
+    title: scalar(raw.title),
+    description: scalar(raw.description),
+    tags: Array.isArray(raw.tags) ? raw.tags : undefined,
+  };
+}
+
+/**
+ * First H1 in a markdown body, or undefined when there is none.
+ */
+export function firstHeading(body: string): string | undefined {
+  return body.match(/^#\s+(.+)$/m)?.[1].trim();
+}
+
+/**
+ * Turn an absolute wiki file path into a stable node id (relative, no .md).
+ */
+export function toId(wikiRoot: string, fullPath: string): string {
+  return path
+    .relative(wikiRoot, fullPath)
+    .replace(/\\/g, "/")
+    .replace(/\.md$/, "");
+}
+
+/**
+ * Title for an index page: its section directory name, capitalized ("Home" at the root).
+ */
+function sectionTitle(file: string, wikiRoot: string): string {
+  const dir = path.dirname(file);
+  const name = path.resolve(dir) === wikiRoot ? "Home" : path.basename(dir);
+  return name.charAt(0).toUpperCase() + name.slice(1);
+}
+
+/**
+ * Every relative markdown link target found in a body.
+ */
+function markdownLinks(body: string): string[] {
+  return [...body.matchAll(MARKDOWN_LINK)].map((match) => match[1]);
+}
+
+/**
+ * Recursively collect markdown files under `dir`. Two guards keep the walk inside the
+ * wiki: the resolved path must stay within `wikiRoot`, and only real directories and
+ * files are traversed. A symlink dirent is neither `isDirectory()` nor `isFile()`, so
+ * a symlink pointing outside the wiki is never followed or read.
+ */
+async function collectMarkdown(
+  dir: string,
+  wikiRoot: string,
+  out: string[] = [],
+): Promise<string[]> {
+  for (const entry of await readdir(dir, { withFileTypes: true })) {
+    const full = path.resolve(dir, entry.name);
+    if (full !== wikiRoot && !full.startsWith(wikiRoot + path.sep)) continue;
+    if (entry.isDirectory()) {
+      await collectMarkdown(full, wikiRoot, out);
+    } else if (
+      entry.isFile() &&
+      entry.name.endsWith(".md") &&
+      !EXCLUDED_FILES.has(entry.name)
+    ) {
+      out.push(full);
+    }
+  }
+  return out;
+}
+
+/**
+ * Read one markdown file into a fully-populated but not-yet-linked graph node.
+ */
+async function readNode(file: string, wikiRoot: string): Promise<WikiNode> {
+  const { meta: raw, body } = splitFrontmatter(await readFile(file, "utf8"));
+  const meta = readMeta(raw);
+  const isIndex = path.basename(file) === "index.md";
+  // Index pages carry a generic "# Files" heading, so prefer the section name.
+  const title =
+    meta.title ??
+    (isIndex ? sectionTitle(file, wikiRoot) : firstHeading(body)) ??
+    path.basename(file, ".md");
+  return {
+    id: toId(wikiRoot, file),
+    title,
+    type: meta.type ?? (isIndex ? "Section" : "Reference"),
+    description: meta.description ?? "",
+    tags: meta.tags ?? [],
+    body,
+    size: body.length,
+    links: [],
+    backlinks: [],
+  };
+}
+
+/**
+ * Resolve each node's markdown links into directed edges between existing nodes,
+ * recording them on the nodes' `links`/`backlinks` in place. Self-links, links to
+ * unknown pages, and duplicate edges are dropped.
+ */
+function linkNodes(nodes: WikiNode[], wikiRoot: string): WikiEdge[] {
+  const byId = new Map(nodes.map((node) => [node.id, node]));
+  const edges: WikiEdge[] = [];
+  const seen = new Set<string>();
+  for (const node of nodes) {
+    const fileDir = path.dirname(path.join(wikiRoot, `${node.id}.md`));
+    for (const link of markdownLinks(node.body)) {
+      const target = toId(wikiRoot, path.resolve(fileDir, link));
+      const targetNode = byId.get(target);
+      const key = `${node.id}\n${target}`;
+      if (!targetNode || target === node.id || seen.has(key)) continue;
+      seen.add(key);
+      edges.push({ source: node.id, target });
+      node.links.push(target);
+      targetNode.backlinks.push(node.id);
+    }
+  }
+  return edges;
+}
+
+/**
+ * Build the in-memory node/edge graph from a wiki directory.
+ */
+export async function buildGraph(wikiRoot: string): Promise<WikiGraph> {
+  const files = (await collectMarkdown(wikiRoot, wikiRoot)).sort();
+  const nodes = await Promise.all(
+    files.map((file) => readNode(file, wikiRoot)),
+  );
+  const edges = linkNodes(nodes, wikiRoot);
+  return {
+    root: path.basename(wikiRoot),
+    generatedAt: new Date().toISOString(),
+    types: [...new Set(nodes.map((node) => node.type))].sort(),
+    nodes,
+    edges,
+  };
+}
diff --git a/src/visualize/page.ts b/src/visualize/page.ts
new file mode 100644
--- /dev/null
+++ b/src/visualize/page.ts
@@ -0,0 +1,247 @@
+/**
+ * The branded single-page visualizer app (LangChain design system). Served as-is
+ * at "/". Scalar wiki fields (title, type, tags) are HTML-escaped client-side
+ * before innerHTML; the page body is rendered as markdown, so any HTML embedded in
+ * a body is contained by the server's Content-Security-Policy (no 'unsafe-inline'
+ * scripts, no inline event handlers, no javascript: URLs) rather than by escaping.
+ * The browser libraries load from cdn.jsdelivr.net at pinned exact versions with
+ * SRI hashes, so a tampered CDN response is rejected by the browser.
+ */
+export const PAGE = /* html */ `<!doctype html>
+<html lang="en" data-theme="dark">
+<head>
+<meta charset="utf-8" />
+<meta name="viewport" content="width=device-width, initial-scale=1" />
+<title>OpenWiki visualizer</title>
+<link rel="preconnect" href="https://fonts.googleapis.com" />
+<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
+<script
+  src="https://cdn.jsdelivr.net/npm/force-graph@1.49.5/dist/force-graph.min.js"
+  integrity="sha384-Q7cpDGRIjLb0dIzHOl/cCcP5MM6ixkekYU/M/Y4shUqh7h2IgtwAY7coox/PB0/S"
+  crossorigin="anonymous"
+></script>
+<script
+  src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"
+  integrity="sha384-/TQbtLCAerC3jgaim+N78RZSDYV7ryeoBCVqTuzRrFec2akfBkHS7ACQ3PQhvMVi"
+  crossorigin="anonymous"
+></script>
+<script
+  src="https://cdn.jsdelivr.net/npm/dompurify@3.4.12/dist/purify.min.js"
+  integrity="sha384-piCcpDdJ7qVeK4Tv8Z6Hpcr3ZBIgP16TxQTPVfsLFdZ5uDgwc3Y8Ho7oUnqf12qu"
+  crossorigin="anonymous"
+></script>
+<script
+  src="https://cdn.jsdelivr.net/npm/mermaid@11.16.0/dist/mermaid.min.js"
+  integrity="sha384-T/0lMUdJpd2S1ZHtRiofG3htU3xPCrFVeAQ1UUE2TJwlEJSV5NUwn30kP28n238E"
+  crossorigin="anonymous"
+></script>
+<style>
+:root {
+  --lc-dark:#030710; --lc-card:#0B1120; --lc-surface:#F2FAFF;
+  --lc-border-dark:#1A2740; --lc-border:#B8DFFF; --lc-muted:#6B8299;
+  --lc-body:#C8DDF0; --lc-white:#FFFFFF; --lc-dark-text:#030710;
+  --lc-blue:#7FC8FF; --lc-blue-hover:#99D4FF; --lc-blue-bg:#E5F4FF;
+  --lc-lime:#E3FF8F; --lc-rose:#B27D75; --lc-pink:#C78EAD; --lc-lavender:#D5C3F7;
+  /* semantic (dark default) */
+  --bg:var(--lc-dark); --panel:var(--lc-card); --edge:var(--lc-border-dark);
+  --text:var(--lc-body); --heading:var(--lc-white); --muted:var(--lc-muted);
+  --tag-bg:rgba(127,200,255,0.12); --tag-text:var(--lc-blue);
+  --graph-bg:#050a16; --node-label:#8CA3BD; --code-bg:#0a1424;
+}
+[data-theme="light"] {
+  --bg:var(--lc-surface); --panel:#FFFFFF; --edge:var(--lc-border);
+  --text:#3D5166; --heading:var(--lc-dark-text); --muted:#5B7086;
+  --tag-bg:var(--lc-blue-bg); --tag-text:#1A6FB5;
+  --graph-bg:#EAF5FF; --node-label:#3D5166; --code-bg:#EEF6FF;
+}
+* , *::before, *::after { box-sizing:border-box; }
+html, body { height:100%; margin:0; }
+body {
+  font-family:"Lausanne","Inter",-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
+  background:var(--bg); color:var(--text);
+  display:flex; flex-direction:column; overflow:hidden;
+  transition:background .3s ease, color .3s ease;
+}
+a { color:var(--lc-blue); text-decoration:none; }
+a:hover { color:var(--lc-blue-hover); text-decoration:underline; }
+
+/* Topbar */
+.topbar {
+  display:flex; align-items:center; gap:20px;
+  padding:14px 22px; border-bottom:1px solid var(--edge);
+  background:linear-gradient(180deg, color-mix(in srgb, var(--panel) 85%, transparent), transparent);
+  backdrop-filter:blur(8px); flex:0 0 auto; z-index:10;
+}
+.brand { display:flex; align-items:center; gap:12px; color:var(--heading); }
+.brand .lc-logo-full { height:20px; width:auto; }
+.brand .divider { width:1px; height:22px; background:var(--edge); }
+.brand .title { font-weight:700; font-size:15px; letter-spacing:-0.01em; color:var(--heading); }
+.brand .title small { display:block; font-weight:500; font-size:11px; color:var(--muted); letter-spacing:0.02em; }
+.spacer { flex:1; }
+.control { display:flex; align-items:center; gap:8px; }
+input.search, select.filter {
+  font:inherit; font-size:13px; color:var(--text); background:var(--bg);
+  border:1px solid var(--edge); border-radius:8px; padding:8px 12px; outline:none;
+  transition:border-color .15s ease;
+}
+input.search { width:220px; }
+input.search:focus, select.filter:focus { border-color:var(--lc-blue); }
+input.search::placeholder { color:var(--muted); }
+.icon-btn {
+  display:inline-flex; align-items:center; justify-content:center;
+  width:36px; height:36px; border-radius:8px; cursor:pointer;
+  border:1px solid var(--edge); background:var(--bg); color:var(--text);
+  transition:border-color .15s ease, color .15s ease;
+}
+.icon-btn:hover { border-color:var(--lc-blue); color:var(--lc-blue); }
+.live-pill {
+  display:inline-flex; align-items:center; gap:7px;
+  font-size:11px; font-weight:700; letter-spacing:0.08em; text-transform:uppercase;
+  color:var(--lc-dark-text); background:var(--lc-lime);
+  padding:5px 11px; border-radius:100px;
+}
+.live-pill.stale { background:var(--lc-rose); color:var(--lc-white); }
+.live-dot { width:7px; height:7px; border-radius:50%; background:currentColor; animation:pulse 1.6s ease-in-out infinite; }
+@keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.35} }
+
+/* Main split */
+.main { flex:1; display:flex; min-height:0; }
+/* Left index: the whole wiki as a browsable, always-visible list. */
+.sidebar {
+  width:236px; flex:0 0 auto; border-right:1px solid var(--edge);
+  background:var(--panel); overflow-y:auto; padding:20px 14px;
+}
+.sidebar::-webkit-scrollbar { width:10px; }
+.sidebar::-webkit-scrollbar-thumb { background:var(--edge); border-radius:8px; }
+.sb-head { display:flex; align-items:baseline; justify-content:space-between; padding:2px 8px 6px; }
+.sb-head .sb-title { font-size:11px; font-weight:700; letter-spacing:0.1em; text-transform:uppercase; color:var(--muted); }
+.sb-head .sb-count { font-size:11px; color:var(--muted); }
+.sb-group { margin-top:12px; }
+.sb-group.hidden { display:none; }
+.sb-group-head { display:flex; align-items:center; gap:7px; padding:4px 8px; font-size:10px; font-weight:700; letter-spacing:0.08em; text-transform:uppercase; color:var(--muted); }
+.sb-group-head .swatch { width:9px; height:9px; border-radius:3px; flex:0 0 auto; }
+.nav-item { display:flex; align-items:center; gap:8px; width:100%; text-align:left; font:inherit; font-size:13px; color:var(--text); background:none; border:none; border-radius:7px; padding:6px 9px; cursor:pointer; line-height:1.3; }
+.nav-item:hover { background:color-mix(in srgb, var(--lc-blue) 12%, transparent); }
+.nav-item.active { background:color-mix(in srgb, var(--lc-blue) 20%, transparent); color:var(--heading); font-weight:600; }
+.nav-item.hidden { display:none; }
+.nav-item .dot { width:7px; height:7px; border-radius:50%; flex:0 0 auto; }
+.nav-item .nm { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
+#graph { flex:1; min-width:0; position:relative; overflow:hidden; background:radial-gradient(120% 120% at 30% 10%, color-mix(in srgb, var(--graph-bg) 92%, var(--lc-blue) 8%), var(--graph-bg)); }
+.detail {
+  flex:1 1 0; min-width:0; border-left:1px solid var(--edge);
+  background:var(--panel); overflow-y:auto; padding:40px 48px;
+  position:relative; z-index:2;
+}
+.detail::-webkit-scrollbar { width:10px; }
+.detail::-webkit-scrollbar-thumb { background:var(--edge); border-radius:8px; }
+
+/* Legend */
+.legend {
+  position:absolute; left:20px; bottom:18px; z-index:5;
+  display:flex; flex-wrap:wrap; gap:6px 14px; max-width:60%;
+  padding:12px 14px; border-radius:12px;
+  background:color-mix(in srgb, var(--panel) 88%, transparent);
+  border:1px solid var(--edge); backdrop-filter:blur(6px);
+}
+.legend .item { display:flex; align-items:center; gap:7px; font-size:12px; color:var(--muted); }
+.legend .swatch { width:11px; height:11px; border-radius:3px; }
+
+/* Detail content */
+.eyebrow { font-size:11px; font-weight:700; letter-spacing:0.1em; text-transform:uppercase; color:var(--lc-blue); }
+.detail h1.doc-title { font-size:30px; font-weight:800; line-height:1.15; letter-spacing:-0.03em; color:var(--heading); margin:10px 0 8px; }
+.detail .desc { font-size:15px; color:var(--muted); line-height:1.6; margin:0 0 18px; }
+.tags { display:flex; flex-wrap:wrap; gap:8px; margin-bottom:22px; }
+.tag {
+  font-size:11px; font-weight:700; letter-spacing:0.08em; text-transform:uppercase;
+  color:var(--tag-text); background:var(--tag-bg); padding:4px 11px; border-radius:100px;
+}
+hr.rule { border:none; border-top:1px solid var(--edge); margin:22px 0; }
+
+/* Rendered markdown */
+.md { font-size:16px; line-height:1.75; color:var(--text); }
+.md h1,.md h2,.md h3,.md h4 { color:var(--heading); line-height:1.3; margin:1.6em 0 .5em; letter-spacing:-0.01em; }
+.md h1 { font-size:24px; font-weight:800; } .md h2 { font-size:20px; font-weight:700; }
+.md h3 { font-size:17px; font-weight:700; } .md h4 { font-size:15px; font-weight:600; }
+.md p { margin:.7em 0; } .md ul,.md ol { padding-left:1.3em; margin:.7em 0; } .md li { margin:.3em 0; }
+.md code { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:.87em; background:var(--code-bg); padding:2px 6px; border-radius:5px; color:var(--lc-blue); }
+.md pre { background:var(--code-bg); border:1px solid var(--edge); border-radius:12px; padding:16px 18px; overflow-x:auto; margin:1em 0; }
+.md pre code { background:none; padding:0; color:var(--text); }
+.md blockquote { border-left:3px solid var(--lc-blue); margin:1em 0; padding:.2em 0 .2em 16px; color:var(--muted); }
+.md table { border-collapse:collapse; width:100%; margin:1em 0; font-size:14px; }
+.md th,.md td { border:1px solid var(--edge); padding:8px 12px; text-align:left; }
+.md th { background:var(--tag-bg); color:var(--heading); }
+.md .mermaid { display:flex; justify-content:center; margin:1.2em 0; }
+.md a.wikilink { border-bottom:1px dashed color-mix(in srgb, var(--lc-blue) 55%, transparent); }
+
+/* Backlinks */
+.backlinks { margin-top:28px; }
+.backlinks .eyebrow { display:block; margin-bottom:10px; }
+.chip {
+  display:inline-flex; align-items:center; gap:6px; cursor:pointer;
+  font-size:13px; color:var(--text); background:var(--bg);
+  border:1px solid var(--edge); border-radius:8px; padding:7px 12px; margin:0 8px 8px 0;
+  transition:border-color .15s ease, color .15s ease;
+}
+.chip:hover { border-color:var(--lc-blue); color:var(--lc-blue); }
+.chip::before { content:"↳"; color:var(--lc-blue); }
+
+/* Empty state */
+.empty { color:var(--muted); text-align:center; margin-top:20vh; font-size:15px; }
+.empty .lc-logo-mark { height:44px; opacity:.5; margin-bottom:16px; }
+
+/* Toast */
+.toast {
+  position:fixed; bottom:22px; left:50%; transform:translateX(-50%) translateY(20px);
+  background:var(--lc-blue); color:var(--lc-dark-text); font-weight:600; font-size:13px;
+  padding:9px 18px; border-radius:100px; box-shadow:0 8px 30px rgba(0,0,0,.35);
+  opacity:0; pointer-events:none; transition:opacity .25s ease, transform .25s ease; z-index:50;
+}
+.toast.show { opacity:1; transform:translateX(-50%) translateY(0); }
+
+/* 3D graph node tooltip (rendered by 3d-force-graph on hover) */
+.gtip {
+  font-family:"Inter",sans-serif; font-size:12px; font-weight:600; line-height:1.2;
+  color:var(--lc-dark-text); background:var(--lc-blue);
+  padding:6px 11px; border-radius:8px; box-shadow:0 8px 24px rgba(0,0,0,.45);
+  display:flex; flex-direction:column;
+}
+.gtip span { margin-top:3px; font-size:10px; font-weight:700; letter-spacing:0.08em; text-transform:uppercase; color:rgba(3,7,16,.62); }
+
+/* Controls hint, stacked above the legend */
+.graph-hint {
+  position:absolute; left:20px; bottom:72px; z-index:5; pointer-events:none;
+  font-size:11px; letter-spacing:0.02em; color:var(--muted);
+  padding:6px 12px; border-radius:100px;
+  background:color-mix(in srgb, var(--panel) 82%, transparent);
+  border:1px solid var(--edge); backdrop-filter:blur(6px);
+}
+.graph-hint b { color:var(--lc-blue); font-weight:700; }
+</style>
+</head>
+<body>
+<div class="topbar">
+  <div class="brand">
+    <svg class="lc-logo-full" viewBox="0 0 3000 554" fill="currentColor" xmlns="http://www.w3.org/2000/svg"><path d="M657.602 333.318V88.8672H591.197V379.431H611.489C636.967 379.431 657.602 358.796 657.602 333.318Z"/><path d="M828.858 396.176H591.197V454.876H828.858V396.176Z"/><path d="M1088.87 294.449C1088.87 229.341 1058.13 181.664 975.056 181.664C905.333 181.664 869.022 227.358 861.317 270.878H923.336C930.01 246.276 949.501 230.905 975.628 230.905C1005.84 230.905 1024.3 243.187 1024.3 264.203C1024.3 286.745 1007.9 291.894 973.568 297.005C936.647 302.612 849.531 309.782 849.531 382.595C849.531 427.182 884.393 462.044 942.292 462.044C992.525 462.044 1014.57 435.383 1025.33 414.405H1025.86V427.716C1025.86 436.413 1026.39 446.177 1027.92 454.873H1094.02C1090.4 437.938 1088.91 410.781 1088.91 390.299V294.449H1088.87ZM1025.33 331.904C1025.33 393.427 994.088 413.375 960.257 413.375C930.544 413.375 915.135 399.53 915.135 379.543C915.135 359.557 931.04 348.801 966.398 341.592C1005.34 333.926 1019.19 322.14 1025.33 309.324V331.866V331.904Z"/><path d="M1274.43 182.695C1233.43 182.695 1209.89 204.703 1194.98 235.483V189.866H1130.41V454.875H1196.51V335.949C1196.51 271.375 1220.61 240.099 1255.97 240.099C1293.92 240.099 1304.14 270.345 1304.14 308.792V454.875H1369.75V292.887C1369.75 227.817 1343.08 182.695 1274.39 182.695H1274.43Z"/><path d="M1599.44 227.244H1598.94C1589.71 205.732 1563.05 182.656 1518.96 182.656C1447.21 182.656 1395.95 232.889 1395.95 316.953C1395.95 401.018 1447.71 452.28 1519.45 452.28C1565.07 452.28 1588.64 429.738 1598.9 404.641H1599.4V436.413C1599.4 481.535 1576.32 503.047 1534.82 503.047C1499.96 503.047 1476.92 490.727 1470.78 462.044H1406.21C1413.38 514.337 1461.59 553.28 1535.89 553.28C1606.11 553.28 1668.62 517.884 1668.62 427.183V189.827H1599.47V227.244H1599.44ZM1533.79 400.522C1486.12 400.522 1462.01 361.045 1462.01 317.487C1462.01 273.929 1486.61 234.987 1533.79 234.987C1580.97 234.987 1605.54 279.574 1605.54 317.487C1605.54 355.4 1586.05 400.522 1533.79 400.522Z"/><path d="M1890.27 140.664C1939.97 140.664 1973.8 160.65 1993.29 203.712H2060.95C2038.41 128.878 1982 82.2305 1890.27 82.2305C1779.05 82.2305 1703.68 161.222 1703.68 272.405C1703.68 383.588 1778.51 461.55 1889.73 461.512C1980.47 461.512 2042.49 412.843 2060.95 340.03H1992.79C1977.92 378.973 1946.14 403.079 1890.27 403.079C1819.51 403.079 1772.37 347.735 1772.37 272.405C1772.37 197.075 1819.02 140.702 1890.27 140.702V140.664Z"/><path d="M2242.39 182.62C2201.39 182.62 2177.85 204.665 2162.94 234.912V88.8672H2098.37V454.761H2164.47V335.835C2164.47 271.261 2188.57 239.985 2223.93 239.985C2261.88 239.985 2272.1 270.231 2272.1 308.678V454.761H2337.71V292.773C2337.71 227.703 2311.05 182.581 2242.35 182.581L2242.39 182.62Z"/><path d="M2605.84 294.449C2605.84 229.341 2575.1 181.664 2492.03 181.664C2422.31 181.664 2386 227.358 2378.33 270.878H2440.35C2447.02 246.276 2466.51 230.905 2492.64 230.905C2522.85 230.905 2541.31 243.187 2541.31 264.203C2541.31 286.745 2524.91 291.894 2490.58 297.005C2453.66 302.612 2366.54 309.782 2366.54 382.595C2366.54 427.182 2401.4 462.044 2459.3 462.044C2509.54 462.044 2531.58 435.383 2542.34 414.405H2542.83V427.716C2542.83 436.413 2543.33 446.177 2544.89 454.873H2610.99C2607.41 437.938 2605.88 410.781 2605.88 390.299V294.449H2605.84ZM2542.26 331.904C2542.26 393.427 2511.02 413.375 2477.19 413.375C2447.48 413.375 2432.07 399.53 2432.07 379.543C2432.07 359.557 2447.98 348.801 2483.33 341.592C2522.28 333.926 2536.12 322.14 2542.26 309.324V331.866V331.904Z"/><path d="M2716.03 111.676H2647.88V173.198H2716.03V111.676Z"/><path d="M2648.91 235.751V454.837H2715.01V189.828H2694.79C2669.43 189.828 2648.91 210.387 2648.91 235.751Z"/><path d="M2904.65 182.695C2863.64 182.695 2840.11 204.703 2825.2 235.483V189.866H2760.62V454.875H2826.72V335.949C2826.72 271.375 2850.83 240.099 2886.19 240.099C2924.1 240.099 2934.36 270.345 2934.36 308.792V454.875H2999.96V292.887C2999.96 227.817 2973.3 182.695 2904.61 182.695H2904.65Z"/><path d="M153.197 324.988C181.918 296.266 198.063 257.269 198.063 216.654C198.063 176.039 181.904 137.042 153.197 108.32L44.866 0C16.159 28.7218 0 67.7192 0 108.334C0 148.949 16.159 187.946 44.866 216.668L153.183 324.988H153.197Z"/><path d="M379.871 335.012C351.164 306.304 312.153 290.145 271.554 290.145C230.954 290.145 191.944 306.304 163.223 335.012L271.554 443.346C300.261 472.054 339.271 488.213 379.885 488.213C420.498 488.213 459.495 472.054 488.215 443.346L379.885 335.012H379.871Z"/><path d="M45.13 443.096C73.8509 471.804 112.847 487.963 153.461 487.963V334.762H0.25C0.263942 375.377 16.409 414.374 45.13 443.096Z"/><path d="M421.695 174.84C392.974 146.132 353.978 129.959 313.35 129.973C272.737 129.973 233.74 146.132 205.02 174.854L313.35 283.188L421.695 174.84Z"/></svg>
+    <div class="divider"></div>
+    <div class="title">OpenWiki<small id="wiki-name">wiki visualizer</small></div>
+  </div>
+  <div class="spacer"></div>
+  <div class="live-pill" id="live"><span class="live-dot"></span><span id="live-text">Live</span></div>
+  <div class="icon-btn" id="theme" title="Toggle theme">◐</div>
+</div>
+<div class="main">
+  <nav class="sidebar" id="sidebar"></nav>
+  <div id="graph"></div>
+  <div class="legend" id="legend"></div>
+  <div class="graph-hint" id="hint"><b>Drag</b> to pan · <b>Scroll</b> to zoom · <b>Click</b> a node to read</div>
+  <div class="detail" id="detail">
+    <div class="empty">
+      <svg class="lc-logo-mark" viewBox="0 0 489 489" fill="currentColor" xmlns="http://www.w3.org/2000/svg"><path d="M153.197 324.988C181.918 296.266 198.063 257.269 198.063 216.654C198.063 176.039 181.904 137.042 153.197 108.32L44.866 0C16.159 28.7218 0 67.7192 0 108.334C0 148.949 16.159 187.946 44.866 216.668L153.183 324.988H153.197Z"/><path d="M379.871 335.012C351.164 306.304 312.153 290.145 271.554 290.145C230.954 290.145 191.944 306.304 163.223 335.012L271.554 443.346C300.261 472.054 339.271 488.213 379.885 488.213C420.498 488.213 459.495 472.054 488.215 443.346L379.885 335.012H379.871Z"/><path d="M45.13 443.096C73.8509 471.804 112.847 487.963 153.461 487.963V334.762H0.25C0.263942 375.377 16.409 414.374 45.13 443.096Z"/><path d="M421.695 174.84C392.974 146.132 353.978 129.959 313.35 129.973C272.737 129.973 233.74 146.132 205.02 174.854L313.35 283.188L421.695 174.84Z"/></svg>
+      <div>Select a page to read it, or explore the graph.</div>
+    </div>
+  </div>
+</div>
+<div class="toast" id="toast">Wiki updated</div>
+<script type="module" src="/client.js"></script>
+</body>
+</html>`;
diff --git a/src/visualize/server.ts b/src/visualize/server.ts
new file mode 100644
--- /dev/null
+++ b/src/visualize/server.ts
@@ -0,0 +1,244 @@
+import {
+  createServer,
+  type IncomingMessage,
+  type Server,
+  type ServerResponse,
+} from "node:http";
+import { watch } from "node:fs";
+import { readFile, stat } from "node:fs/promises";
+import { execFile } from "node:child_process";
+import { buildGraph, type WikiGraph } from "./graph.js";
+import { PAGE } from "./page.js";
+
+const HOST = "127.0.0.1"; // loopback only (never expose the wiki on the network)
+const PORT_ATTEMPTS = 20; // ports to try before giving up when the preferred one is busy
+const WATCH_DEBOUNCE_MS = 150; // collapse a burst of file-change events into one rebuild
+
+// The client JS is an external module (/client.js), so scripts need only 'self' plus the
+// jsdelivr CDN origin for the three browser libraries (whose integrity is pinned by the SRI
+// hashes on the <script> tags in page.ts) - no 'unsafe-inline' for scripts. The page still
+// carries one inline <style>, so style-src keeps 'unsafe-inline'.
+const CDN = "https://cdn.jsdelivr.net";
+const CSP = [
+  "default-src 'none'",
+  `script-src 'self' ${CDN}`,
+  "style-src 'self' 'unsafe-inline'",
+  "img-src 'self' data:",
+  "font-src 'self'",
+  "connect-src 'self'",
+  "base-uri 'none'",
+  "form-action 'none'",
+].join("; ");
+
+/**
+ * Inputs for a single visualizer server run. Every field is required: the CLI parser
+ * fills the defaults, so the server itself never has to guess.
+ */
+export interface VisualizeServerOptions {
+  /**
+   * Resolved absolute path to the wiki directory to serve.
+   */
+  wikiRoot: string;
+
+  /**
+   * Preferred TCP port; the server increments from here when it is already in use.
+   */
+  port: number;
+
+  /**
+   * Whether to open the default browser once the server is listening.
+   */
+  open: boolean;
+}
+
+/**
+ * Start the visualizer server. Resolves when the server is stopped (SIGINT);
+ * exits the process on an unrecoverable listen error, matching the prototype.
+ */
+export async function runVisualizeServer(
+  options: VisualizeServerOptions,
+): Promise<void> {
+  const { wikiRoot } = options;
+  await assertWikiDir(wikiRoot);
+
+  let graph: WikiGraph = {
+    root: "",
+    generatedAt: "",
+    types: [],
+    nodes: [],
+    edges: [],
+  };
+  const sseClients = new Set<ServerResponse>();
+
+  // The compiled client modules sit beside this file in dist/visualize/. They are static,
+  // server-owned build artifacts (no user input, never evaluated), read once at startup and
+  // served verbatim at fixed routes.
+  const clientJs = await readFile(
+    new URL("./client.js", import.meta.url),
+    "utf8",
+  );
+  const clientLibJs = await readFile(
+    new URL("./client-lib.js", import.meta.url),
+    "utf8",
+  );
+
+  const broadcastReload = (): void => {
+    for (const res of sseClients) res.write("event: reload\ndata: 1\n\n");
+  };
+  const rebuild = async (reason: string): Promise<void> => {
+    try {
+      graph = await buildGraph(wikiRoot);
+      process.stdout.write(
+        `  ↻ ${reason}: ${graph.nodes.length} pages, ${graph.edges.length} links\n`,
+      );
+      broadcastReload();
+    } catch (error) {
+      process.stderr.write(`  ! rebuild failed: ${(error as Error).message}\n`);
+    }
+  };
+
+  const server = createServer((req: IncomingMessage, res: ServerResponse) => {
+    const url = req.url ?? "/";
+    if (url === "/" || url === "/index.html") {
+      res.writeHead(200, {
+        "content-type": "text/html; charset=utf-8",
+        "content-security-policy": CSP,
+      });
+      res.end(PAGE);
+      return;
+    }
+    if (url === "/client.js") {
+      res.writeHead(200, { "content-type": "text/javascript; charset=utf-8" });
+      res.end(clientJs);
+      return;
+    }
+    if (url === "/client-lib.js") {
+      res.writeHead(200, { "content-type": "text/javascript; charset=utf-8" });
+      res.end(clientLibJs);
+      return;
+    }
+    if (url === "/api/graph") {
+      res.writeHead(200, {
+        "content-type": "application/json; charset=utf-8",
+      });
+      res.end(JSON.stringify(graph));
+      return;
+    }
+    if (url === "/events") {
+      res.writeHead(200, {
+        "content-type": "text/event-stream",
+        "cache-control": "no-cache",
+        connection: "keep-alive",
+      });
+      res.write("retry: 2000\n\n");
+      sseClients.add(res);
+      req.on("close", () => sseClients.delete(res));
+      return;
+    }
+    // Only these fixed routes exist; no filesystem path is ever derived from req.url.
+    res.writeHead(404, { "content-type": "text/plain" });
+    res.end("Not found");
+  });
+
+  return new Promise<void>((resolve) => {
+    process.once("SIGINT", () => {
+      process.stdout.write("\n  stopped.\n");
+      server.close(() => resolve());
+    });
+    listen(server, options.port, PORT_ATTEMPTS, (boundPort) => {
+      const url = `http://${HOST}:${boundPort}`;
+      void rebuild("initial scan").then(() => {
+        startWatch(wikiRoot, rebuild);
+        printBanner(wikiRoot, url);
+        if (options.open) openBrowser(url);
+      });
+    });
+  });
+}
+
+/**
+ * Fail early with a friendly message when the wiki directory is missing.
+ */
+async function assertWikiDir(wikiRoot: string): Promise<void> {
+  try {
+    const info = await stat(wikiRoot);
+    if (!info.isDirectory()) {
+      throw new Error(`Not a directory: ${wikiRoot}`);
+    }
+  } catch {
+    throw new Error(
+      `Wiki directory not found: ${wikiRoot}. Run \`openwiki --init\` first, or pass a path.`,
+    );
+  }
+}
+
+/**
+ * Try the preferred port, incrementing on EADDRINUSE.
+ */
+function listen(
+  server: Server,
+  port: number,
+  attemptsLeft: number,
+  onReady: (port: number) => void,
+): void {
+  const onError = (err: NodeJS.ErrnoException): void => {
+    if (err.code === "EADDRINUSE" && attemptsLeft > 0) {
+      listen(server, port + 1, attemptsLeft - 1, onReady);
+    } else {
+      process.stderr.write(`Failed to start server: ${err.message}\n`);
+      process.exit(1);
+    }
+  };
+  server.once("error", onError);
+  server.listen(port, HOST, () => {
+    server.removeListener("error", onError);
+    onReady(port);
+  });
+}
+
+/**
+ * Debounced recursive watch of the wiki directory.
+ */
+function startWatch(
+  wikiRoot: string,
+  rebuild: (reason: string) => Promise<void>,
+): void {
+  let timer: NodeJS.Timeout | undefined;
+  try {
+    watch(wikiRoot, { recursive: true }, () => {
+      clearTimeout(timer);
+      timer = setTimeout(
+        () => void rebuild("change detected"),
+        WATCH_DEBOUNCE_MS,
+      );
+    });
+  } catch {
+    process.stdout.write("  (live watch unavailable on this platform)\n");
+  }
+}
+
+/**
+ * Open the default browser without a shell (URL is never interpolated).
+ */
+function openBrowser(url: string): void {
+  const opener: [string, string[]] =
+    process.platform === "darwin"
+      ? ["open", [url]]
+      : process.platform === "win32"
+        ? ["cmd", ["/c", "start", "", url]]
+        : ["xdg-open", [url]];
+  execFile(opener[0], opener[1], () => {});
+}
+
+/**
+ * Print the startup banner: where the wiki lives, the URL, and how to stop.
+ */
+function printBanner(wikiRoot: string, url: string): void {
+  process.stdout.write(`\n  OpenWiki visualizer\n`);
+  process.stdout.write(`  wiki:  ${wikiRoot}\n`);
+  process.stdout.write(`  open:  \x1b[36m${url}\x1b[0m\n`);
+  process.stdout.write(
+    `  live:  editing pages under the wiki refreshes the browser\n\n`,
+  );
+  process.stdout.write(`  Ctrl-C to stop.\n\n`);
+}
diff --git a/tsconfig.client.json b/tsconfig.client.json
new file mode 100644
--- /dev/null
+++ b/tsconfig.client.json
@@ -0,0 +1,9 @@
+{
+  "extends": "./tsconfig.json",
+  "compilerOptions": {
+    "declaration": false,
+    "lib": ["ES2022", "DOM", "DOM.Iterable"]
+  },
+  "include": ["src/visualize/client.ts"],
+  "exclude": []
+}
diff --git a/tsconfig.eslint.json b/tsconfig.eslint.json
--- a/tsconfig.eslint.json
+++ b/tsconfig.eslint.json
@@ -1,4 +1,8 @@
 {
   "extends": "./tsconfig.json",
-  "include": ["src/**/*.ts", "src/**/*.tsx", "test/**/*.ts", "test/**/*.tsx"]
+  "compilerOptions": {
+    "lib": ["ES2022", "DOM", "DOM.Iterable"]
+  },
+  "include": ["src/**/*.ts", "src/**/*.tsx", "test/**/*.ts", "test/**/*.tsx"],
+  "exclude": []
 }
diff --git a/tsconfig.json b/tsconfig.json
--- a/tsconfig.json
+++ b/tsconfig.json
@@ -13,5 +13,6 @@
     "strict": true,
     "target": "ES2022"
   },
-  "include": ["src/**/*.ts", "src/**/*.tsx"]
+  "include": ["src/**/*.ts", "src/**/*.tsx"],
+  "exclude": ["src/visualize/client.ts"]
 }
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
