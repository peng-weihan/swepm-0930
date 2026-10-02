#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/configs/harbor.toml b/configs/harbor.toml
--- a/configs/harbor.toml
+++ b/configs/harbor.toml
@@ -1,5 +1,5 @@
 # harbor-v1 — Terminal-Bench 2, each task run in its own declared container image (needs docker).
-# enable_bash turns on the shell tool the agent drives the terminal with.
+# The `bash` harness gives the agent the shell tool it drives the terminal with.
 #
 #   uv run eval @ configs/harbor.toml
 num_tasks = 10
@@ -9,6 +9,5 @@ id = "harbor-v1"
 dataset = "terminal-bench/terminal-bench-2"
 
 [harness]
-id = "default"
+id = "bash"
 runtime = { type = "docker" }
-enable_bash = true
diff --git a/configs/terminal-bench-2.toml b/configs/terminal-bench-2.toml
--- a/configs/terminal-bench-2.toml
+++ b/configs/terminal-bench-2.toml
@@ -1,5 +1,5 @@
 # terminal-bench-2-v1 — the harbor taskset pinned to Terminal-Bench 2. Needs the `harbor`
-# CLI (`uv tool install harbor`) and docker; enable_bash gives the agent the shell tool.
+# CLI (`uv tool install harbor`) and docker; the `bash` harness gives the agent the shell tool.
 #
 #   uv run eval @ configs/terminal-bench-2.toml
 num_tasks = 10
@@ -8,6 +8,5 @@ num_tasks = 10
 id = "terminal-bench-2-v1"
 
 [harness]
-id = "default"
+id = "bash"
 runtime = { type = "docker" }
-enable_bash = true
diff --git a/environments/aime24_v1/aime24_v1/taskset.py b/environments/aime24_v1/aime24_v1/taskset.py
--- a/environments/aime24_v1/aime24_v1/taskset.py
+++ b/environments/aime24_v1/aime24_v1/taskset.py
@@ -41,7 +41,7 @@ def load_tasks(self) -> list[AIME24Task]:
         return [
             AIME24Task(
                 idx=i,
-                instruction=INSTRUCTION + row["problem"],
+                prompt=INSTRUCTION + row["problem"],
                 answer=str(int(row["answer"])),
             )
             for i, row in enumerate(rows)
diff --git a/environments/alphabet_sort_v1/alphabet_sort_v1/taskset.py b/environments/alphabet_sort_v1/alphabet_sort_v1/taskset.py
--- a/environments/alphabet_sort_v1/alphabet_sort_v1/taskset.py
+++ b/environments/alphabet_sort_v1/alphabet_sort_v1/taskset.py
@@ -7,7 +7,7 @@
 ground truth, power-scaled.
 
 The whole conversation is driven by a `vf.User` simulator (`AlphabetSortUser` in
-`servers/user.py`): the task carries no prompt (`instruction=None`), so the simulator opens the
+`servers/user.py`): the task carries no prompt (`prompt=None`), so the simulator opens the
 conversation with the initial sort prompt — before the model is ever called — and then injects
 each follow-up after the assistant turn. The episode is one rollout the harness only ever sees
 as a single exchange. The simulator runs on the host (not colocated in the agent's runtime), so
@@ -102,7 +102,7 @@ def sort_key(s: str) -> str:
             first = turns[0][:]
             rng.shuffle(first)
             shown = rng.randint(c.min_names_per_turn, c.max_names_per_turn)
-            instruction = (
+            initial_prompt = (
                 f"Sort these names in alphabetical order by {label} name: {', '.join(first)}\n\n"
                 "Use exactly this format:\n<alphabetical_sorted>\n"
                 + "\n".join(f"Name{j}" for j in range(1, shown + 1))
@@ -140,9 +140,9 @@ def sort_key(s: str) -> str:
                     idx=len(tasks),
                     # No prompt on the task: the simulator opens with the sort prompt, then the
                     # follow-ups — one user turn per `user_turns` entry.
-                    instruction=None,
+                    prompt=None,
                     info={
-                        "user_turns": [instruction, *follow_ups],
+                        "user_turns": [initial_prompt, *follow_ups],
                         "ground_truths": ground_truths,
                         "num_turns": len(turns),
                     },
diff --git a/environments/code_golf_v1/code_golf_v1/taskset.py b/environments/code_golf_v1/code_golf_v1/taskset.py
--- a/environments/code_golf_v1/code_golf_v1/taskset.py
+++ b/environments/code_golf_v1/code_golf_v1/taskset.py
@@ -56,7 +56,7 @@ def load_tasks(self) -> list[CodeGolfTask]:
             CodeGolfTask(
                 idx=i,
                 name=name,
-                instruction=f"{SYSTEM}\n\nPrint {description}.",
+                prompt=f"{SYSTEM}\n\nPrint {description}.",
                 expected=expected,
             )
             for i, (name, description, expected) in enumerate(self.SPECS)
diff --git a/environments/color_codeword_v1/color_codeword_v1/taskset.py b/environments/color_codeword_v1/color_codeword_v1/taskset.py
--- a/environments/color_codeword_v1/color_codeword_v1/taskset.py
+++ b/environments/color_codeword_v1/color_codeword_v1/taskset.py
@@ -2,7 +2,7 @@
 
 Each turn shows colored squares that map to letters (Red=A, Green=B, ...); the model accumulates
 the codeword across turns and, on the final turn, outputs the whole thing. Turn 0's squares are
-seeded in the task's `instruction` (a `Messages` prompt carrying images); the later turns are
+seeded in the task's `prompt` (a `Messages` prompt carrying images); the later turns are
 injected by a colocated `vf.User` (`ColorCodewordUser` below) the interception server drives
 after each assistant turn. Reward is an exact match of the final codeword; a partial-match
 metric tracks per-position accuracy. Images carry through the v1 message graph as `mm_kwargs`
@@ -136,7 +136,7 @@ def load_tasks(self) -> list[ColorCodewordTask]:
             tasks.append(
                 ColorCodewordTask(
                     idx=idx,
-                    instruction=[vf.UserMessage(content=parts)],
+                    prompt=[vf.UserMessage(content=parts)],
                     system_prompt=SYSTEM_PROMPT,
                     answer=answer,
                     info={"colors_per_turn": colors_per_turn, "max_turns": MAX_TURNS},
diff --git a/environments/compact/compact/harness.py b/environments/compact/compact/harness.py
--- a/environments/compact/compact/harness.py
+++ b/environments/compact/compact/harness.py
@@ -50,5 +50,5 @@ async def launch(
                 {"mcpServers": {name: {"url": url} for name, url in mcp_urls.items()}}
             )
         return await runtime.run_uv_script(
-            PROGRAM_SOURCE, args=[trace.task.instruction], env=env
+            PROGRAM_SOURCE, args=[trace.task.prompt], env=env
         )
diff --git a/environments/deepwiki_v1/deepwiki_v1/taskset.py b/environments/deepwiki_v1/deepwiki_v1/taskset.py
--- a/environments/deepwiki_v1/deepwiki_v1/taskset.py
+++ b/environments/deepwiki_v1/deepwiki_v1/taskset.py
@@ -36,7 +36,7 @@ def load_tasks(self) -> list[DeepWikiTask]:
             DeepWikiTask(
                 idx=i,
                 name=repo,
-                instruction=(
+                prompt=(
                     f"Use the `deepwiki_ask_question` tool to ask what programming "
                     f'language the "{repo}" GitHub repository is primarily written in. '
                     "Then reply with just the language name."
diff --git a/environments/glossary_v1/glossary_v1/taskset.py b/environments/glossary_v1/glossary_v1/taskset.py
--- a/environments/glossary_v1/glossary_v1/taskset.py
+++ b/environments/glossary_v1/glossary_v1/taskset.py
@@ -27,7 +27,7 @@ def load_tasks(self) -> list[GlossaryTask]:
             GlossaryTask(
                 idx=i,
                 name=entity.title(),
-                instruction=(
+                prompt=(
                     f'Use the `facts_lookup` tool to look up "{entity.title()}", then '
                     "reply with exactly what it returns inside <answer></answer> tags."
                 ),
diff --git a/environments/gsm8k_v1/gsm8k_v1/taskset.py b/environments/gsm8k_v1/gsm8k_v1/taskset.py
--- a/environments/gsm8k_v1/gsm8k_v1/taskset.py
+++ b/environments/gsm8k_v1/gsm8k_v1/taskset.py
@@ -37,7 +37,7 @@ def load_tasks(self) -> list[GSM8KTask]:
         return [
             GSM8KTask(
                 idx=i,
-                instruction=f"{SYSTEM}\n\n{row['question']}",
+                prompt=f"{SYSTEM}\n\n{row['question']}",
                 answer=row["answer"].split("####")[-1].strip(),
             )
             for i, row in enumerate(rows)
diff --git a/environments/math_env_v1/math_env_v1/taskset.py b/environments/math_env_v1/math_env_v1/taskset.py
--- a/environments/math_env_v1/math_env_v1/taskset.py
+++ b/environments/math_env_v1/math_env_v1/taskset.py
@@ -45,7 +45,7 @@ def load_tasks(self) -> list[MathTask]:
         return [
             MathTask(
                 idx=i,
-                instruction=INSTRUCTION + row[self.config.question_key],
+                prompt=INSTRUCTION + row[self.config.question_key],
                 answer=str(row[self.config.answer_key]),
             )
             for i, row in enumerate(rows)
diff --git a/environments/r2e_gym_v1/r2e_gym_v1/taskset.py b/environments/r2e_gym_v1/r2e_gym_v1/taskset.py
--- a/environments/r2e_gym_v1/r2e_gym_v1/taskset.py
+++ b/environments/r2e_gym_v1/r2e_gym_v1/taskset.py
@@ -190,7 +190,7 @@ def load_tasks(self) -> list[R2EGymTask]:
             R2EGymTask(
                 idx=i,
                 name=row.get("commit_hash") or f"r2e-{i}",
-                instruction=row["problem_statement"],
+                prompt=row["problem_statement"],
                 image=(
                     f"{REGISTRY}/{row['docker_image']}"
                     if self.config.use_prime_registry
@@ -199,7 +199,7 @@ def load_tasks(self) -> list[R2EGymTask]:
                 workdir=REPO_PATH,
                 expected_output_json=row["expected_output_json"],
                 parsed_commit_content=row.get("parsed_commit_content") or "",
-                resources=vf.Resources(cpu=4, memory=4, disk=10),
+                resources=vf.TaskResources(cpu=4, memory=4, disk=10),
             )
             for i, row in enumerate(rows)
         ]
diff --git a/environments/reverse_text_v1/reverse_text_v1/taskset.py b/environments/reverse_text_v1/reverse_text_v1/taskset.py
--- a/environments/reverse_text_v1/reverse_text_v1/taskset.py
+++ b/environments/reverse_text_v1/reverse_text_v1/taskset.py
@@ -35,7 +35,7 @@ def load_tasks(self) -> list[ReverseTextTask]:
         return [
             ReverseTextTask(
                 idx=i,
-                instruction=row["prompt"],
+                prompt=row["prompt"],
                 system_prompt=SYSTEM,
                 answer=row["prompt"][::-1],
             )
diff --git a/environments/scaleswe_v1/scaleswe_v1/taskset.py b/environments/scaleswe_v1/scaleswe_v1/taskset.py
--- a/environments/scaleswe_v1/scaleswe_v1/taskset.py
+++ b/environments/scaleswe_v1/scaleswe_v1/taskset.py
@@ -185,14 +185,14 @@ def load_tasks(self) -> list[ScaleSWETask]:
             ScaleSWETask(
                 idx=i,
                 name=row["instance_id"],
-                instruction=row["problem_statement"],
+                prompt=row["problem_statement"],
                 image=(
                     f"{REGISTRY}/{row['image_url']}"
                     if self.config.use_prime_registry
                     else row["image_url"]
                 ),
                 workdir=row["workdir"],
-                resources=vf.Resources(cpu=4, memory=4, disk=10),
+                resources=vf.TaskResources(cpu=4, memory=4, disk=10),
                 base_commit=row.get("parent_commit") or row.get("base_commit") or "",
                 pre_commands=(row.get("pre_commands") or "")
                 .strip()
diff --git a/environments/scratchpad_v1/scratchpad_v1/taskset.py b/environments/scratchpad_v1/scratchpad_v1/taskset.py
--- a/environments/scratchpad_v1/scratchpad_v1/taskset.py
+++ b/environments/scratchpad_v1/scratchpad_v1/taskset.py
@@ -43,7 +43,7 @@ class ScratchpadConfig(vf.TasksetConfig):
 class ScratchpadTaskset(vf.Taskset[ScratchpadTask, ScratchpadConfig, ScratchpadState]):
     def load_tasks(self) -> list[ScratchpadTask]:
         return [
-            ScratchpadTask(idx=i, word=w, instruction=INSTRUCTION.format(word=w))
+            ScratchpadTask(idx=i, word=w, prompt=INSTRUCTION.format(word=w))
             for i, w in enumerate(WORDS)
         ]
 
diff --git a/environments/swelego_v1/swelego_v1/taskset.py b/environments/swelego_v1/swelego_v1/taskset.py
--- a/environments/swelego_v1/swelego_v1/taskset.py
+++ b/environments/swelego_v1/swelego_v1/taskset.py
@@ -180,10 +180,10 @@ def load_tasks(self) -> list[SWELegoTask]:
             SWELegoTask(
                 idx=i,
                 name=row.get("instance_id") or f"swelego-{i}",
-                instruction=row["problem_statement"],
+                prompt=row["problem_statement"],
                 image=row["image_name"],
                 workdir=REPO_PATH,
-                resources=vf.Resources(cpu=4, memory=4, disk=10),
+                resources=vf.TaskResources(cpu=4, memory=4, disk=10),
                 test_cmd=row.get("test_cmd") or "",
                 test_patch=row.get("test_patch") or "",
                 base_commit=row.get("base_commit") or "",
diff --git a/environments/wiki_search_v1/wiki_search_v1/taskset.py b/environments/wiki_search_v1/wiki_search_v1/taskset.py
--- a/environments/wiki_search_v1/wiki_search_v1/taskset.py
+++ b/environments/wiki_search_v1/wiki_search_v1/taskset.py
@@ -74,7 +74,7 @@ def load_tasks(self) -> list[TriviaTask]:
                 idx=i,
                 question=row["question"],
                 answer=str(row["answer"]),
-                instruction=f"{SYSTEM}\n\nQuestion: {row['question']}",
+                prompt=f"{SYSTEM}\n\nQuestion: {row['question']}",
             )
             for i, row in enumerate(rows.select(range(min(NUM_QUESTIONS, len(rows)))))
         ]
diff --git a/environments/wikispeedia_v1/wikispeedia_v1/taskset.py b/environments/wikispeedia_v1/wikispeedia_v1/taskset.py
--- a/environments/wikispeedia_v1/wikispeedia_v1/taskset.py
+++ b/environments/wikispeedia_v1/wikispeedia_v1/taskset.py
@@ -85,7 +85,7 @@ def load_tasks(self) -> list[WikiTask]:
                 source=source,
                 target=target,
                 shortest_path=dist,
-                instruction=(
+                prompt=(
                     f"{SYSTEM}\n\nYour mission: {source} >> {target}\n\n"
                     f"Here is the starting article:\n\n"
                     f"{format_article(wiki, source, self.config.tools.links_only)}"
diff --git a/environments/wordle_v1/wordle_v1/taskset.py b/environments/wordle_v1/wordle_v1/taskset.py
--- a/environments/wordle_v1/wordle_v1/taskset.py
+++ b/environments/wordle_v1/wordle_v1/taskset.py
@@ -8,12 +8,19 @@
 from typing import Literal
 
 import verifiers.v1 as vf
-from tasksets.textarena_v1 import TextArenaConfig, TextArenaTask, TextArenaTaskset
+from tasksets.textarena_v1 import (
+    TextArenaConfig,
+    TextArenaState,
+    TextArenaTask,
+    TextArenaTaskset,
+)
 
 
 class WordleConfig(TextArenaConfig):
     game: Literal["Wordle-v0"] = "Wordle-v0"
 
 
-class WordleTaskset(TextArenaTaskset, vf.Taskset[TextArenaTask, WordleConfig]):
+class WordleTaskset(
+    TextArenaTaskset, vf.Taskset[TextArenaTask, WordleConfig, TextArenaState]
+):
     pass
diff --git a/packages/harnesses/harnesses/__init__.py b/packages/harnesses/harnesses/__init__.py
--- a/packages/harnesses/harnesses/__init__.py
+++ b/packages/harnesses/harnesses/__init__.py
@@ -2,6 +2,7 @@
 
 Re-exports each harness's class + config off the package."""
 
+from harnesses.bash import BashHarness, BashHarnessConfig
 from harnesses.codex import CodexHarness, CodexHarnessConfig
 from harnesses.default import DefaultHarness, DefaultHarnessConfig
 from harnesses.kimi_code import KimiCodeHarness, KimiCodeHarnessConfig
@@ -12,6 +13,8 @@
 from harnesses.rlm import RLMHarness, RLMHarnessConfig
 
 __all__ = [
+    "BashHarness",
+    "BashHarnessConfig",
     "CodexHarness",
     "CodexHarnessConfig",
     "DefaultHarness",
diff --git a/packages/harnesses/harnesses/bash/__init__.py b/packages/harnesses/harnesses/bash/__init__.py
new file mode 100644
--- /dev/null
+++ b/packages/harnesses/harnesses/bash/__init__.py
@@ -0,0 +1,7 @@
+"""bash — v1's built-in agentic harness: the `default` chat loop plus a single local `bash`
+tool. Its `harness.py` (class + config) and the `program.py` script staged into the runtime.
+Resolved by id via `load_harness`."""
+
+from harnesses.bash.harness import BashHarness, BashHarnessConfig
+
+__all__ = ["BashHarness", "BashHarnessConfig"]
diff --git a/packages/harnesses/harnesses/bash/harness.py b/packages/harnesses/harnesses/bash/harness.py
new file mode 100644
--- /dev/null
+++ b/packages/harnesses/harnesses/bash/harness.py
@@ -0,0 +1,70 @@
+"""The built-in bash harness: the default chat loop plus a single local `bash` tool.
+
+The same growing-message-list chat loop as the `default` harness, but its program also offers a
+`bash` tool that runs shell commands in the runtime — for agentic tasks that drive a terminal
+(e.g. harbor / terminal-bench). MCP tools from the taskset are wired in too. A uv script (deps:
+openai, mcp), launched via `runtime.run_uv_script`, so it works on any runtime with `uv`.
+"""
+
+import json
+from pathlib import Path
+
+from verifiers.v1.harness import Harness, HarnessConfig
+from verifiers.v1.clients import RolloutContext
+from verifiers.v1.dialects.chat import message_to_wire
+from verifiers.v1.runtimes import ProgramResult, Runtime
+from verifiers.v1.trace import Trace
+
+PROGRAM_SOURCE = (Path(__file__).resolve().parent / "program.py").read_text()
+
+# Tells the model it can run shell commands (a pure-text chat loop gets no harness-injected prompt).
+BASH_SYSTEM_PROMPT = "You have access to a bash tool; use it to run shell commands."
+
+
+class BashHarnessConfig(HarnessConfig):
+    """The built-in bash harness. A uv script (deps: openai, mcp), so it runs in any runtime that
+    has `uv` (the harness bootstraps it) with no other setup."""
+
+    id: str = "bash"
+
+
+class BashHarness(Harness[BashHarnessConfig]):
+    APPENDS_SYSTEM_PROMPT = True
+    SUPPORTS_USER_SIM = True
+    SUPPORTS_MESSAGE_PROMPT = True
+
+    async def launch(
+        self,
+        ctx: RolloutContext,
+        trace: Trace,
+        runtime: Runtime,
+        endpoint: str,
+        secret: str,
+        mcp_urls: dict[str, str],
+    ) -> ProgramResult:
+        system_prompt, prompt = self.resolve_prompt(trace.task)
+        system_prompt = "\n\n".join(p for p in (BASH_SYSTEM_PROMPT, system_prompt) if p)
+        env = {
+            **self.config.env,
+            "OPENAI_BASE_URL": endpoint,
+            "OPENAI_API_KEY": secret,
+            "OPENAI_MODEL": ctx.model,
+            "APPEND_SYSTEM_PROMPT": system_prompt,
+        }
+        if mcp_urls:
+            # The program connects to the tool servers over HTTP; hand it a standard
+            # `mcpServers` URL config (the `mcp` client itself comes from the uv deps).
+            env["MCP_CONFIG"] = json.dumps(
+                {"mcpServers": {name: {"url": url} for name, url in mcp_urls.items()}}
+            )
+        # A Messages prompt (e.g. an image-bearing prompt) seeds the chat loop directly;
+        # a plain string is the single first user message; None means the task has no prompt and
+        # the framework's user simulator opens the conversation (no opening user message here).
+        if prompt is None:
+            args = [""]
+        elif isinstance(prompt, str):
+            args = [prompt]
+        else:
+            env["INITIAL_MESSAGES"] = json.dumps([message_to_wire(m) for m in prompt])
+            args = [""]
+        return await runtime.run_uv_script(PROGRAM_SOURCE, args=args, env=env)
diff --git a/packages/harnesses/harnesses/bash/program.py b/packages/harnesses/harnesses/bash/program.py
new file mode 100644
--- /dev/null
+++ b/packages/harnesses/harnesses/bash/program.py
@@ -0,0 +1,163 @@
+# /// script
+# requires-python = ">=3.10"
+# dependencies = ["openai", "mcp"]
+# ///
+"""The bash harness's program: a chat loop with a local `bash` tool (+ optional MCP tools).
+
+A growing-message-list chat loop. It always offers a local `bash` tool that runs shell commands
+in the runtime; when the harness sets MCP_CONFIG (a standard `mcpServers` URL map) it also
+connects to those servers over streamable HTTP, exposes their tools to the model as
+`<server>_<tool>`, and routes those calls to the server. The loop runs until the model answers
+without a tool call.
+
+It runs as a uv script (deps: openai, mcp), so the chat + tool plumbing is just the SDKs — the
+harness bootstraps `uv` in the runtime. Model calls go to the interception server
+(OPENAI_BASE_URL/API_KEY); the bash tool runs locally in the runtime.
+"""
+
+import asyncio
+import json
+import os
+import subprocess
+import sys
+from contextlib import AsyncExitStack
+
+from openai import AsyncOpenAI
+
+BASH_TOOL = {
+    "type": "function",
+    "function": {
+        "name": "bash",
+        "description": "Run a bash command and return its combined stdout and stderr.",
+        "parameters": {
+            "type": "object",
+            "properties": {
+                "command": {"type": "string", "description": "The bash command to run."}
+            },
+            "required": ["command"],
+        },
+    },
+}
+
+# base_url + api_key come from OPENAI_BASE_URL / OPENAI_API_KEY. max_retries=0: the framework
+# already retries model calls at the interception relay, so the SDK's own retries would just nest.
+client = AsyncOpenAI(max_retries=0)
+
+
+def run_bash(command: str) -> str:
+    try:
+        result = subprocess.run(
+            ["bash", "-c", command], capture_output=True, text=True, timeout=3600
+        )
+        return result.stdout + result.stderr
+    except Exception as e:
+        return f"error: {e}"
+
+
+async def chat(messages: list[dict], tools: list[dict]):
+    completion = await client.chat.completions.create(
+        model=os.environ["OPENAI_MODEL"], messages=messages, tools=tools or None
+    )
+    return completion.choices[0].message
+
+
+async def connect_mcp(stack: AsyncExitStack, config: dict) -> tuple[list[dict], dict]:
+    """Connect to each configured MCP server (a streamable-HTTP `url`); return
+    (tool schemas, dispatch mapping `<server>_<tool>` -> (session, raw tool name))."""
+    from mcp import ClientSession
+    from mcp.client.streamable_http import (
+        create_mcp_http_client,
+        streamable_http_client,
+    )
+
+    tool_schemas: list[dict] = []
+    dispatch: dict[str, tuple] = {}
+    for name, spec in config.get("mcpServers", {}).items():
+        http_client = await stack.enter_async_context(
+            create_mcp_http_client(headers=spec.get("headers") or None)
+        )
+        read, write, *_ = await stack.enter_async_context(
+            streamable_http_client(spec["url"], http_client=http_client)
+        )
+        session = await stack.enter_async_context(ClientSession(read, write))
+        await session.initialize()
+        for tool in (await session.list_tools()).tools:
+            full = f"{name}_{tool.name}"
+            tool_schemas.append(
+                {
+                    "type": "function",
+                    "function": {
+                        "name": full,
+                        "description": tool.description or "",
+                        "parameters": tool.inputSchema,
+                    },
+                }
+            )
+            dispatch[full] = (session, tool.name)
+    return tool_schemas, dispatch
+
+
+def mcp_content_to_chat_content(blocks) -> str | list[dict]:
+    parts = []
+    for block in blocks:
+        if block.type == "text":
+            parts.append({"type": "text", "text": block.text})
+        elif block.type == "image":
+            url = f"data:{block.mimeType};base64,{block.data}"
+            parts.append({"type": "image_url", "image_url": {"url": url}})
+        else:
+            parts.append({"type": "text", "text": str(block)})
+    if not parts:
+        return str(blocks)
+    if all(part["type"] == "text" for part in parts):
+        return "\n".join(part["text"] for part in parts)
+    return parts
+
+
+async def call_mcp(dispatch: dict, name: str, arguments: dict) -> str | list[dict]:
+    session, raw = dispatch[name]
+    result = await session.call_tool(raw, arguments)
+    return mcp_content_to_chat_content(result.content)
+
+
+async def main() -> None:
+    config = json.loads(os.environ.get("MCP_CONFIG", "{}"))
+    async with AsyncExitStack() as stack:
+        mcp_tools, dispatch = (
+            await connect_mcp(stack, config) if config.get("mcpServers") else ([], {})
+        )
+        tools = [BASH_TOOL] + mcp_tools
+        system_prompt = os.environ.get("APPEND_SYSTEM_PROMPT", "")
+        messages = (
+            [{"role": "system", "content": system_prompt}] if system_prompt else []
+        )
+        # A Messages prompt (e.g. an image-bearing prompt) arrives pre-built as OpenAI
+        # wire dicts; otherwise the single argv string is the first user message. An empty argv
+        # means the task has no prompt — the framework's user simulator seeds the opening turn,
+        # so send no user message and let the interception server inject it.
+        initial = json.loads(os.environ.get("INITIAL_MESSAGES", "[]"))
+        if initial:
+            messages.extend(initial)
+        elif sys.argv[1]:
+            messages.append({"role": "user", "content": sys.argv[1]})
+        while True:
+            message = await chat(messages, tools)
+            messages.append(message.model_dump(exclude_none=True))
+            if not message.tool_calls:
+                break
+            for call in message.tool_calls:
+                name = call.function.name
+                args = json.loads(call.function.arguments or "{}")
+                if name in dispatch:
+                    content = await call_mcp(dispatch, name, args)
+                elif name == "bash":
+                    content = await asyncio.to_thread(run_bash, args.get("command", ""))
+                else:
+                    content = f"error: unknown tool {name!r}"
+                messages.append(
+                    {"role": "tool", "tool_call_id": call.id, "content": content}
+                )
+
+
+if __name__ == "__main__":
+    asyncio.run(main())
diff --git a/packages/harnesses/harnesses/codex/harness.py b/packages/harnesses/harnesses/codex/harness.py
--- a/packages/harnesses/harnesses/codex/harness.py
+++ b/packages/harnesses/harnesses/codex/harness.py
@@ -58,7 +58,7 @@ async def launch(
         secret: str,
         mcp_urls: dict[str, str],
     ) -> ProgramResult:
-        _, instruction = self.resolve_prompt(trace.task)
+        _, prompt = self.resolve_prompt(trace.task)
         # codex authenticates to the interception server with the session secret (its provider
         # api key) and posts Responses calls to `{endpoint}/responses`.
         env = {**self.config.env, KEY_VAR: secret}
@@ -107,6 +107,6 @@ async def launch(
             "-c",
             f"model_providers.{PROVIDER}.requires_openai_auth=false",
             *tool_config,
-            instruction,
+            prompt,
         ]
         return await runtime.run(argv, env)
diff --git a/packages/harnesses/harnesses/default/harness.py b/packages/harnesses/harnesses/default/harness.py
--- a/packages/harnesses/harnesses/default/harness.py
+++ b/packages/harnesses/harnesses/default/harness.py
@@ -1,9 +1,10 @@
 """The built-in default harness: runs a small chat-loop program as a uv script.
 
-A growing-message-list chat loop with an optional bash tool (`enable_bash`), plus MCP tools
-when the rollout has tool servers (host-side, resolved to URLs by the Environment). The program is a uv script
-(deps: openai, mcp), launched via `runtime.run_uv_script` — so it works on any runtime
-with `uv` (the harness bootstraps it), with no runtime-specific setup.
+A growing-message-list chat loop with the taskset's MCP tools (host-side, resolved to URLs by
+the Environment) — and no tools of its own. The program is a uv script (deps: openai, mcp),
+launched via `runtime.run_uv_script` — so it works on any runtime with `uv` (the harness
+bootstraps it), with no runtime-specific setup. For a shell-driving agent, use a dedicated
+agentic harness (e.g. `mini-swe-agent`).
 """
 
 import json
@@ -17,27 +18,18 @@
 
 PROGRAM_SOURCE = (Path(__file__).resolve().parent / "program.py").read_text()
 
-# Added to the system prompt only when the bash tool is enabled, so the model knows it can
-# run shell commands (a pure-text chat loop gets no harness-injected system prompt).
-BASH_SYSTEM_PROMPT = "You have access to a bash tool; use it to run shell commands."
-
 
 class DefaultHarnessConfig(HarnessConfig):
     """The built-in harness. A uv script (deps: openai, mcp), so it runs in any runtime that
     has `uv` (the harness bootstraps it) with no other setup."""
 
     id: str = "default"
-    enable_bash: bool = False
-    """Offer the model a local `bash` tool. Off by default — a pure-text chat loop where
-    the model answers directly (MCP tools from the taskset, if any, are still wired in);
-    enable it (`--harness.enable-bash true`) for agents that run shell commands, e.g.
-    harbor terminal tasks."""
 
 
 class DefaultHarness(Harness[DefaultHarnessConfig]):
     APPENDS_SYSTEM_PROMPT = True
     SUPPORTS_USER_SIM = True
-    SUPPORTS_MESSAGE_INSTRUCTION = True
+    SUPPORTS_MESSAGE_PROMPT = True
 
     async def launch(
         self,
@@ -48,20 +40,12 @@ async def launch(
         secret: str,
         mcp_urls: dict[str, str],
     ) -> ProgramResult:
-        system_prompt, instruction = self.resolve_prompt(trace.task)
-        enable_bash = self.config.enable_bash and "bash" not in (
-            self.config.disabled_tools or []
-        )
-        if enable_bash:
-            system_prompt = "\n\n".join(
-                p for p in (BASH_SYSTEM_PROMPT, system_prompt) if p
-            )
+        system_prompt, prompt = self.resolve_prompt(trace.task)
         env = {
             **self.config.env,
             "OPENAI_BASE_URL": endpoint,
             "OPENAI_API_KEY": secret,
             "OPENAI_MODEL": ctx.model,
-            "ENABLE_BASH": "1" if enable_bash else "0",
             "APPEND_SYSTEM_PROMPT": system_prompt or "",
         }
         if mcp_urls:
@@ -70,16 +54,14 @@ async def launch(
             env["MCP_CONFIG"] = json.dumps(
                 {"mcpServers": {name: {"url": url} for name, url in mcp_urls.items()}}
             )
-        # A Messages instruction (e.g. an image-bearing prompt) seeds the chat loop directly;
+        # A Messages prompt (e.g. an image-bearing prompt) seeds the chat loop directly;
         # a plain string is the single first user message; None means the task has no prompt and
         # the framework's user simulator opens the conversation (no opening user message here).
-        if instruction is None:
+        if prompt is None:
             args = [""]
-        elif isinstance(instruction, str):
-            args = [instruction]
+        elif isinstance(prompt, str):
+            args = [prompt]
         else:
-            env["INITIAL_MESSAGES"] = json.dumps(
-                [message_to_wire(m) for m in instruction]
-            )
+            env["INITIAL_MESSAGES"] = json.dumps([message_to_wire(m) for m in prompt])
             args = [""]
         return await runtime.run_uv_script(PROGRAM_SOURCE, args=args, env=env)
diff --git a/packages/harnesses/harnesses/default/program.py b/packages/harnesses/harnesses/default/program.py
--- a/packages/harnesses/harnesses/default/program.py
+++ b/packages/harnesses/harnesses/default/program.py
@@ -2,55 +2,29 @@
 # requires-python = ">=3.10"
 # dependencies = ["openai", "mcp"]
 # ///
-"""The default harness's program: a chat loop with an optional bash tool (+ optional MCP tools).
+"""The default harness's program: a chat loop with the taskset's MCP tools (and none of its own).
 
-A growing-message-list chat loop. It offers a local `bash` tool when ENABLE_BASH is set
-(the default); when the harness sets MCP_CONFIG (a standard `mcpServers` URL map) it also
-connects to those servers over streamable HTTP, exposes their tools to the model as
-`<server>_<tool>`, and routes those calls to the server. The loop runs until the model
-answers without a tool call (immediately, when no tools are offered).
+A growing-message-list chat loop. When the harness sets MCP_CONFIG (a standard `mcpServers` URL
+map) it connects to those servers over streamable HTTP, exposes their tools to the model as
+`<server>_<tool>`, and routes those calls to the server. The loop runs until the model answers
+without a tool call (immediately, when no tools are offered).
 
 It runs as a uv script (deps: openai, mcp), so the chat + tool plumbing is just the
 SDKs — the harness bootstraps `uv` in the runtime. Model calls go to the interception
-server (OPENAI_BASE_URL/API_KEY); the bash tool runs locally in the runtime.
+server (OPENAI_BASE_URL/API_KEY).
 """
 
 import asyncio
 import json
 import os
-import subprocess
 import sys
 from contextlib import AsyncExitStack
 
 from openai import AsyncOpenAI
 
-BASH_TOOL = {
-    "type": "function",
-    "function": {
-        "name": "bash",
-        "description": "Run a bash command and return its combined stdout and stderr.",
-        "parameters": {
-            "type": "object",
-            "properties": {
-                "command": {"type": "string", "description": "The bash command to run."}
-            },
-            "required": ["command"],
-        },
-    },
-}
-
-# base_url + api_key come from OPENAI_BASE_URL / OPENAI_API_KEY.
-client = AsyncOpenAI()
-
-
-def run_bash(command: str) -> str:
-    try:
-        result = subprocess.run(
-            ["bash", "-c", command], capture_output=True, text=True, timeout=3600
-        )
-        return result.stdout + result.stderr
-    except Exception as e:
-        return f"error: {e}"
+# base_url + api_key come from OPENAI_BASE_URL / OPENAI_API_KEY. max_retries=0: the framework
+# already retries model calls at the interception relay, so the SDK's own retries would just nest.
+client = AsyncOpenAI(max_retries=0)
 
 
 async def chat(messages: list[dict], tools: list[dict]):
@@ -122,16 +96,14 @@ async def call_mcp(dispatch: dict, name: str, arguments: dict) -> str | list[dic
 async def main() -> None:
     config = json.loads(os.environ.get("MCP_CONFIG", "{}"))
     async with AsyncExitStack() as stack:
-        mcp_tools, dispatch = (
+        tools, dispatch = (
             await connect_mcp(stack, config) if config.get("mcpServers") else ([], {})
         )
-        enable_bash = os.environ.get("ENABLE_BASH", "0") == "1"
-        tools = ([BASH_TOOL] if enable_bash else []) + mcp_tools
         system_prompt = os.environ.get("APPEND_SYSTEM_PROMPT", "")
         messages = (
             [{"role": "system", "content": system_prompt}] if system_prompt else []
         )
-        # A Messages instruction (e.g. an image-bearing prompt) arrives pre-built as OpenAI
+        # A Messages prompt (e.g. an image-bearing prompt) arrives pre-built as OpenAI
         # wire dicts; otherwise the single argv string is the first user message. An empty argv
         # means the task has no prompt — the framework's user simulator seeds the opening turn,
         # so send no user message and let the interception server inject it.
@@ -150,8 +122,6 @@ async def main() -> None:
                 args = json.loads(call.function.arguments or "{}")
                 if name in dispatch:
                     content = await call_mcp(dispatch, name, args)
-                elif name == "bash":
-                    content = await asyncio.to_thread(run_bash, args.get("command", ""))
                 else:
                     content = f"error: unknown tool {name!r}"
                 messages.append(
diff --git a/packages/harnesses/harnesses/kimi_code/harness.py b/packages/harnesses/harnesses/kimi_code/harness.py
--- a/packages/harnesses/harnesses/kimi_code/harness.py
+++ b/packages/harnesses/harnesses/kimi_code/harness.py
@@ -58,7 +58,7 @@ async def launch(
         secret: str,
         mcp_urls: dict[str, str],
     ) -> ProgramResult:
-        _, instruction = self.resolve_prompt(trace.task)
+        _, prompt = self.resolve_prompt(trace.task)
         env = {
             **self.config.env,
             "KIMI_CODE_HOME": KIMI_HOME,
@@ -104,4 +104,4 @@ async def launch(
             await runtime.write(f"{KIMI_HOME}/config.toml", permission_rules.encode())
         await runtime.write(f"{KIMI_HOME}/mcp.json", json.dumps(mcp).encode())
         # `--prompt` is Kimi Code's non-interactive print mode.
-        return await runtime.run([BINARY, "--prompt", instruction], env)
+        return await runtime.run([BINARY, "--prompt", prompt], env)
diff --git a/packages/harnesses/harnesses/mini_swe_agent/harness.py b/packages/harnesses/harnesses/mini_swe_agent/harness.py
--- a/packages/harnesses/harnesses/mini_swe_agent/harness.py
+++ b/packages/harnesses/harnesses/mini_swe_agent/harness.py
@@ -33,14 +33,14 @@ async def launch(
     ) -> ProgramResult:
         if self.config.disabled_tools:
             raise ValueError("mini-swe-agent does not support disabling tools")
-        _, instruction = self.resolve_prompt(trace.task)
+        _, prompt = self.resolve_prompt(trace.task)
         args = [
             "--model",
             ctx.model,
             "--model-class",
             "litellm",
             "--task",
-            instruction,
+            prompt,
             "--exit-immediately",
             "--yolo",
             "-c",
diff --git a/packages/harnesses/harnesses/rlm/harness.py b/packages/harnesses/harnesses/rlm/harness.py
--- a/packages/harnesses/harnesses/rlm/harness.py
+++ b/packages/harnesses/harnesses/rlm/harness.py
@@ -51,7 +51,7 @@ async def launch(
         secret: str,
         mcp_urls: dict[str, str],
     ) -> ProgramResult:
-        system_prompt, instruction = self.resolve_prompt(trace.task)
+        system_prompt, prompt = self.resolve_prompt(trace.task)
         # rlm reaches the interception server via OPENAI_BASE_URL/API_KEY (its
         # provider precedence falls back to OPENAI_*), and reads RLM_* for itself.
         env = {
@@ -92,7 +92,7 @@ async def launch(
         result = await runtime.run(["sh", "-c", guarded], env)
         if result.exit_code != 0:
             raise ProgramError(f"rlm install failed: {result.stderr.strip()[-500:]}")
-        return await runtime.run([RLM_BIN, instruction], env)
+        return await runtime.run([RLM_BIN, prompt], env)
 
     @metric
     async def rlm(self, trace: Trace, runtime: Runtime) -> dict[str, float]:
diff --git a/packages/tasksets/tasksets/harbor_v1/taskset.py b/packages/tasksets/tasksets/harbor_v1/taskset.py
--- a/packages/tasksets/tasksets/harbor_v1/taskset.py
+++ b/packages/tasksets/tasksets/harbor_v1/taskset.py
@@ -11,10 +11,11 @@
 taskset (the `solved` reward), so a harbor task runs under ANY harness.
 
 A task's declared [environment].docker_image becomes a first-class `Task.image`
-the Environment injects into the runtime (docker/prime both pull it). Tasks that
-only ship an environment/Dockerfile have no pullable image: with `require_image`
-they're rejected; otherwise they run on the runtime's default image (we don't
-build the Dockerfile — a locally-built image isn't pullable by a remote sandbox).
+the Environment injects into the runtime (docker/prime both pull it). A task whose
+environment is only a `Dockerfile` has no pullable image — we don't build Dockerfiles
+(a locally-built image isn't pullable by a remote sandbox) — so it's rejected unless
+`use_harness_image`, which runs it on the harness runtime's image instead. A task with
+no environment at all also runs on that image, unless `require_image`.
 """
 
 import io
@@ -28,7 +29,7 @@
 from verifiers.v1.decorators import reward
 from verifiers.v1.errors import ProgramError
 from verifiers.v1.runtimes import Runtime
-from verifiers.v1.task import Resources, Task
+from verifiers.v1.task import Task, TaskResources, TaskTimeout
 from verifiers.v1.taskset import Taskset, TasksetConfig
 from verifiers.v1.trace import Trace
 from verifiers.v1.types import StrictBaseModel
@@ -48,9 +49,14 @@ class HarborConfig(TasksetConfig):
     """Scale each task's CPU, memory, and disk requests. GPU requests are unchanged."""
     require_image: bool = False
     """For a task with NO declared environment at all (no docker_image, no Dockerfile),
-    whether to reject it (True) or run it on the runtime's default image (False). Tasks
-    whose environment is a `Dockerfile` are always rejected — building Dockerfiles isn't
-    supported, and running them on the default image scores against the wrong env."""
+    whether to reject it (True) or run it on the runtime's default image (False). A task
+    whose environment is a `Dockerfile` is rejected too (building Dockerfiles isn't
+    supported), unless `use_harness_image`."""
+    use_harness_image: bool = False
+    """Run a task whose environment is only a `Dockerfile` on the harness runtime's image
+    instead of rejecting it. The Dockerfile is NOT built, so the task scores against the
+    harness image rather than its declared environment — only correct when that image already
+    has what the task needs (e.g. you've pointed the runtime at the right image)."""
 
 
 class Author(StrictBaseModel):
@@ -59,7 +65,7 @@ class Author(StrictBaseModel):
 
 
 class HarborTask(Task):
-    """A Harbor task. The base fields carry instruction.md (`instruction`), the
+    """A Harbor task. The base fields carry instruction.md (`prompt`), the
     resolved container `image`, the `harness_timeout`/`scoring_timeout`/`resources`
     (from task.toml's [harness]/[verifier]/[environment]), and [task].name/description;
     the rest mirror [metadata]."""
@@ -90,21 +96,30 @@ def dataset_dir(dataset: str) -> Path:
     return out
 
 
-def resolve_image(task_dir: Path, config: dict, require_image: bool) -> str | None:
+def resolve_image(
+    task_dir: Path,
+    config: dict,
+    require_image: bool,
+    use_harness_image: bool = False,
+) -> str | None:
     """The task's declared registry image (usable by docker or prime). A pullable
     `[environment].docker_image` is used directly. A task whose environment is a
     `Dockerfile` is rejected — we don't build Dockerfiles, and running it on the default
     image would silently score against the wrong environment (e.g. SWE-bench's `/testbed`
-    repo would be missing). A task with no environment at all runs on the runtime's
-    default image, unless `require_image`."""
+    repo would be missing) — unless `use_harness_image`, which returns None to run it on the
+    harness runtime's image. A task with no environment at all runs on that image too, unless
+    `require_image`. None means "use the runtime's own image"."""
     declared = config.get("environment", {}).get("docker_image")
     if declared:
         return declared
     if (task_dir / "environment" / "Dockerfile").exists():
+        if use_harness_image:
+            return None
         raise ValueError(
             f"{task_dir.name}: environment is a Dockerfile, not a pullable "
             "[environment].docker_image — building Dockerfiles isn't supported, so this "
-            "task can't run (it would otherwise score against the wrong default image)."
+            "task can't run (it would otherwise score against the wrong default image). "
+            "Pass --taskset.use-harness-image to run it on the harness runtime's image instead."
         )
     if require_image:
         raise ValueError(
@@ -113,9 +128,9 @@ def resolve_image(task_dir: Path, config: dict, require_image: bool) -> str | No
     return None
 
 
-def parse_resources(env: dict, multiplier: float = 1.0) -> Resources:
-    """Map a task.toml [environment] block to Resources (0 gpus -> unset)."""
-    return Resources(
+def parse_resources(env: dict, multiplier: float = 1.0) -> TaskResources:
+    """Map a task.toml [environment] block to TaskResources (0 gpus -> unset)."""
+    return TaskResources(
         cpu=env["cpus"] * multiplier if env.get("cpus") else None,
         memory=env["memory_mb"] / 1024 * multiplier if env.get("memory_mb") else None,
         gpu=str(env["gpus"]) if env.get("gpus") else None,
@@ -137,14 +152,21 @@ def parse_task(task_dir: Path, idx: int, harbor_config: HarborConfig) -> HarborT
         idx=idx,
         name=task.get("name") or task_dir.name,
         description=task.get("description"),
-        instruction=(task_dir / "instruction.md").read_text().strip(),
-        image=resolve_image(task_dir, config, harbor_config.require_image),
-        harness_timeout=harness_timeout * harbor_config.timeout_multiplier
-        if harness_timeout is not None
-        else None,
-        scoring_timeout=scoring_timeout * harbor_config.timeout_multiplier
-        if scoring_timeout is not None
-        else None,
+        prompt=(task_dir / "instruction.md").read_text().strip(),
+        image=resolve_image(
+            task_dir,
+            config,
+            harbor_config.require_image,
+            harbor_config.use_harness_image,
+        ),
+        timeout=TaskTimeout(
+            harness=harness_timeout * harbor_config.timeout_multiplier
+            if harness_timeout is not None
+            else None,
+            scoring=scoring_timeout * harbor_config.timeout_multiplier
+            if scoring_timeout is not None
+            else None,
+        ),
         resources=parse_resources(
             config.get("environment", {}), harbor_config.resource_multiplier
         ),
diff --git a/packages/tasksets/tasksets/textarena_v1/__init__.py b/packages/tasksets/tasksets/textarena_v1/__init__.py
--- a/packages/tasksets/tasksets/textarena_v1/__init__.py
+++ b/packages/tasksets/tasksets/textarena_v1/__init__.py
@@ -1,8 +1,15 @@
 from tasksets.textarena_v1.taskset import (
     TextArenaConfig,
+    TextArenaState,
     TextArenaTask,
     TextArenaTaskset,
     TextArenaUser,
 )
 
-__all__ = ["TextArenaConfig", "TextArenaTask", "TextArenaTaskset", "TextArenaUser"]
+__all__ = [
+    "TextArenaConfig",
+    "TextArenaState",
+    "TextArenaTask",
+    "TextArenaTaskset",
+    "TextArenaUser",
+]
diff --git a/packages/tasksets/tasksets/textarena_v1/__main__.py b/packages/tasksets/tasksets/textarena_v1/__main__.py
deleted file mode 100644
--- a/packages/tasksets/tasksets/textarena_v1/__main__.py
+++ /dev/null
@@ -1,5 +0,0 @@
-"""`python -m tasksets.textarena_v1` — serve the user simulator (the framework's launch target)."""
-
-from tasksets.textarena_v1 import TextArenaUser
-
-TextArenaUser.run()
diff --git a/packages/tasksets/tasksets/textarena_v1/taskset.py b/packages/tasksets/tasksets/textarena_v1/taskset.py
--- a/packages/tasksets/tasksets/textarena_v1/taskset.py
+++ b/packages/tasksets/tasksets/textarena_v1/taskset.py
@@ -10,7 +10,7 @@
 Scoring is game-authoritative: when the episode ends the user simulator writes the game's
 own outcome (`env.state.rewards`) to `OUTCOME_FILE` in the runtime, and the reward reads it
 back — so the taskset needs no per-game guess parsing. Each task is reproduced from an RNG
-seed (carried in `info`): the taskset seeds the game to build the instruction and the
+seed (carried in `info`): the taskset seeds the game to build the prompt and the
 simulator re-seeds to the same episode, so no per-game word-list or state-key knowledge is
 needed and any single-player TextArena game fits.
 """
@@ -65,7 +65,7 @@ async def setup(self) -> None:
 
     async def setup_task(self, task) -> None:
         # textarena derives a game's whole setup from the global RNG at reset, so seeding it
-        # reproduces the exact episode the taskset built the instruction from — no per-game keys.
+        # reproduces the exact episode the taskset built the prompt from — no per-game keys.
         import random
 
         import textarena
@@ -125,7 +125,7 @@ class TextArenaConfig(vf.TasksetConfig):
 class TextArenaTask(vf.Task):
     info: dict
     """What the user simulator needs to set up the game: the `game` id and the RNG `seed`
-    that reproduces the exact episode this task's instruction was built from."""
+    that reproduces the exact episode this task's prompt was built from."""
 
 
 class TextArenaTaskset(vf.Taskset[TextArenaTask, TextArenaConfig, TextArenaState]):
@@ -136,7 +136,7 @@ async def game_over(self, trace: vf.Trace) -> bool:
     def load_tasks(self) -> list[TextArenaTask]:
         # One task per RNG seed; the simulator re-seeds to reproduce the same episode. Games
         # that embed the per-episode setup in the prompt (WordLadder's start/target,
-        # WordSearch's grid) need the instruction built under each seed; games whose prompt
+        # WordSearch's grid) need the prompt built under each seed; games whose prompt
         # is seed-invariant (Wordle, Hangman) build it once.
         nltk.download("words", quiet=True)
         nltk.download("averaged_perceptron_tagger_eng", quiet=True)
@@ -153,7 +153,7 @@ def observation(seed: int) -> str:
             TextArenaTask(
                 idx=i,
                 name=f"{self.config.game}#{i}",
-                instruction=observation(i) if seed_specific else first,
+                prompt=observation(i) if seed_specific else first,
                 system_prompt=SYSTEM_PROMPT,
                 info={"game": self.config.game, "seed": i},
             )
@@ -174,3 +174,7 @@ async def game_reward(
         except (FileNotFoundError, OSError):
             return 0.0
         return float(json.loads(data)["reward"])
+
+
+if __name__ == "__main__":
+    TextArenaUser.run()
diff --git a/pyproject.toml b/pyproject.toml
--- a/pyproject.toml
+++ b/pyproject.toml
@@ -174,7 +174,7 @@ flash-attn = { FLASH_ATTENTION_SKIP_CUDA_BUILD = "TRUE" }
 
 [project.scripts]
 vf-eval = "verifiers.scripts.eval:main"
-eval = "verifiers.v1.cli.eval:main"
+eval = "verifiers.v1.cli.eval.main:main"
 validate = "verifiers.v1.cli.validate:main"
 serve = "verifiers.v1.cli.serve:main"
 init = "verifiers.v1.cli.init:main"
diff --git a/verifiers/utils/process_utils.py b/verifiers/utils/process_utils.py
--- a/verifiers/utils/process_utils.py
+++ b/verifiers/utils/process_utils.py
@@ -81,3 +81,16 @@ def terminate_processes(
         t.start()
     for t in threads:
         t.join()
+
+
+def use_threading_tqdm_lock() -> None:
+    """Pin tqdm to a threading lock so it never lazily creates an `mp.RLock` a killed worker would
+    leak (a `resource_tracker` semaphore warning). No-op if tqdm isn't installed."""
+    try:
+        import threading
+
+        import tqdm
+
+        tqdm.tqdm.set_lock(threading.RLock())
+    except Exception:
+        pass
diff --git a/verifiers/v1/GUIDE.md b/verifiers/v1/GUIDE.md
--- a/verifiers/v1/GUIDE.md
+++ b/verifiers/v1/GUIDE.md
@@ -14,7 +14,7 @@ config. You'll work with them in very different proportions:
   write.
 - **Harness** — the program that drives the rollout turn to turn, a chat loop or an agent CLI
   (*how* the model is called). **Usually you just pick a built-in** (`default` / `rlm` /
-  `codex`); you only write your own if you need a custom rollout loop. With some exceptions, any 
+  `codex`); you only write your own if you need a custom rollout loop. With some exceptions, any
   taskset runs under any harness.
 - **Runtime** — *where* the harness (and the taskset's tools / user simulator) executes:
   `subprocess` / `docker` / `prime` / `modal`. **You never write one** — runtimes ship with the
@@ -35,21 +35,24 @@ uv run eval -h                   # typed help (lists local tasksets + harnesses)
 ```
 
 Everything below has a CLI flag *and* a TOML equivalent (`uv run eval @ config.toml`); the
-flag names are the dotted config path (`--harness.runtime.type docker`).
+flag names are the dotted config path (`--harness.runtime.type docker`). See the
+[CLI reference](#cli-reference) for the full command surface.
 
-## Authoring a taskset
+---
+
+# Authoring a taskset
 
 A taskset is a package selected by `id`. Scaffold one with `uv run init my-task-v1` (add
 `--add-tool` / `--add-user` / `--add-harness` for more pieces, `--v0` for a legacy environment),
 or copy the closest `environments/<name>_v1` and edit. The scaffold runs out of the box; replace
-`load_tasks` and the `@reward`. Minimal shape:
+`load_tasks` and the `@reward`. The whole minimal shape:
 
 ```python
 import verifiers.v1 as vf
 
 
 class ReverseTask(vf.Task):
-    answer: str                     # your own fields, alongside vf.Task's (instruction, system_prompt, ...)
+    answer: str                     # your own fields, alongside vf.Task's (prompt, system_prompt, ...)
 
 
 class ReverseConfig(vf.TasksetConfig):
@@ -59,7 +62,7 @@ class ReverseConfig(vf.TasksetConfig):
 class ReverseTaskset(vf.Taskset[ReverseTask, ReverseConfig]):
     def load_tasks(self) -> list[ReverseTask]:
         return [
-            ReverseTask(idx=i, instruction=f"Reverse: {w}", answer=w[::-1])
+            ReverseTask(idx=i, prompt=f"Reverse: {w}", answer=w[::-1])
             for i, w in enumerate(WORDS[: self.config.num_tasks])
         ]
 
@@ -71,28 +74,146 @@ class ReverseTaskset(vf.Taskset[ReverseTask, ReverseConfig]):
 __all__ = ["ReverseTaskset"]   # vf resolves the taskset by finding this Taskset subclass
 ```
 
-### Scoring
+`vf.Taskset[TaskT, ConfigT, StateT]` is generic over three types: your `Task` subclass, your
+`TasksetConfig` subclass, and (optionally) your `State` subclass. The third defaults to the base
+`vf.State`, so a stateless taskset writes just `Taskset[MyTask, MyConfig]`. The framework reads
+these off the generic bases to type `self.config`, `trace.task`, and `trace.state`.
+
+The taskset module must export its `Taskset` subclass via `__all__` — the loader walks the
+exported names and finds the single `Taskset` subclass.
 
-Rewards and metrics are decorated `async` methods; the framework injects whichever of `task`
-/ `trace` / `runtime` you name as parameters.
+## The task
+
+`vf.Task` is a frozen pydantic model. Subclass it to add typed, task-specific fields (the
+reference answer, ground truths, per-row metadata) that flow — fully typed — into your rewards as
+`trace.task`. The base fields every task has:
+
+| field | type | meaning |
+| --- | --- | --- |
+| `idx` | `int` *(required)* | stable index within the taskset |
+| `name` | `str \| None` | human-readable label (display / filtering) |
+| `description` | `str \| None` | human-readable description |
+| `prompt` | `str \| Messages \| None` *(required)* | the opening user message. A `str` is the usual case; a `Messages` list seeds a full initial conversation (e.g. a user message carrying images — only harnesses with `SUPPORTS_MESSAGE_PROMPT`); **`None` means the task carries no prompt** and the user simulator opens the conversation (see [User simulators](#user-simulators)) |
+| `system_prompt` | `str \| None` | system prompt; emitted as a real system message by harnesses that set `APPENDS_SYSTEM_PROMPT`, else folded into `prompt` |
+| `image` | `str \| None` | container image the task needs — forces a container runtime (the subprocess runtime is refused) |
+| `workdir` | `str \| None` | working directory the harness and scoring run in |
+| `timeout` | `TaskTimeout` | per-task, per-stage wall-clock overrides |
+| `resources` | `TaskResources` | per-task runtime resource requests |
+
+`prompt` is *required* on purpose — set it to `None` explicitly to opt into a user-sim-opened
+conversation rather than forgetting it.
+
+**Per-task overrides.** `timeout` and `resources` are small frozen submodels that let a single
+row override the eval-wide defaults (precedence is always `cli/toml > task > default`):
 
 ```python
-@vf.reward(weight=1.0)                 # summed into trace.reward
+from verifiers.v1 import TaskTimeout, TaskResources
+
+MyTask(
+    idx=0, prompt=...,
+    timeout=TaskTimeout(setup=300, harness=1200, scoring=120),   # seconds; per stage, None = no limit
+    resources=TaskResources(cpu=4, memory=8, gpu="A100:2", disk=20),  # Modal units; None = runtime default
+)
+```
+
+`TaskTimeout` has `setup` / `harness` / `finalize` / `scoring`; `TaskResources` has `cpu` /
+`memory` (GB) / `gpu` (`"type[:count]"`) / `disk` (GB). A field the runtime doesn't support is
+warned about and ignored. SWE-style tasksets typically set these per row from dataset metadata.
+
+## The config
+
+A `vf.TasksetConfig` subclass is the taskset's typed knobs. Its fields become `--taskset.<field>`
+CLI flags (and TOML keys), and the instance reaches the taskset as `self.config`:
+
+```python
+class GSM8KConfig(vf.TasksetConfig):
+    split: Literal["train", "test"] = "test"   # --taskset.split test
+
+class GSM8KTaskset(vf.Taskset[GSM8KTask, GSM8KConfig]):
+    def load_tasks(self):
+        rows = load_dataset("gsm8k", split=self.config.split)   # read knobs off self.config
+        ...
+```
+
+Nested configs nest the flag path: a `tools: vf.ToolsetConfig` field is set with
+`--taskset.tools.shared true` / `--taskset.tools.runtime.type docker`. Keep **fixed** data
+(prompt templates, lookup tables) in module constants; config is for things a *runner* should be
+able to change. The base `TasksetConfig` carries `id` (the taskset's id, set via `--taskset.id`).
+
+## Loading tasks
+
+`def load_tasks(self) -> list[TaskT]` builds the task list. It runs **once at load** (not per
+rollout), so do dataset loading / filtering / slicing here off `self.config`. Return your typed
+`Task` subclass instances.
+
+## Scoring — rewards, metrics, group rewards
+
+Rewards and metrics are decorated `async` methods. The framework **injects whichever arguments
+you name** — declare any subset of `task` / `trace` / `runtime` and you get exactly those:
+
+```python
+@vf.reward(weight=1.0)                 # summed (weighted) into trace.reward
 async def correct(self, task, trace) -> float: ...
 
-@vf.metric()                           # recorded, not summed (return float or a dict to merge)
-async def num_turns(self, trace) -> int: ...
+@vf.metric()                           # recorded, not summed — return a float or a dict to merge
+async def num_turns(self, trace) -> float: ...
 
 @vf.group_reward(weight=1.0)           # scores a task's N rollouts together
 async def best_of_n(self, traces: list[vf.Trace]) -> list[float]: ...
-
-@vf.stop()                             # extra stop condition, (self, trace) -> bool
-async def saw_answer(self, trace) -> bool: ...
 ```
 
-Higher `priority` runs first; `weight` controls aggregation. To score with a dependency the
-eval process shouldn't have (e.g. `math-verify`), run it as a uv script *in the rollout's
-runtime* — the dep never touches the eval process:
+The decorators and what each can receive:
+
+| decorator | params | optional kwargs | returns |
+| --- | --- | --- | --- |
+| `@vf.reward` | `task`, `trace`, `runtime` | `weight=1.0`, `priority=0` | `float` (× weight → summed into `trace.reward`) |
+| `@vf.metric` | `task`, `trace`, `runtime` | `priority=0` | `float`, **or a `dict[str, float]`** merged into `trace.metrics` |
+| `@vf.group_reward` | `task`, `traces` | `weight=1.0`, `priority=0` | `list[float]`, one per trace |
+| `@vf.stop` | `trace` | `priority=0` | `bool` |
+
+Notes that bite if missed:
+
+- **`@group_reward` gets no `runtime` and no single `trace`** — only `task` and `traces` (it runs
+  after the per-rollout runtimes are gone). To compare a runtime-derived signal across a task's
+  rollouts, record it per-rollout as a `@metric`/`@reward` first, then read it off each trace in
+  the group reward. Group rewards need `-r/--num-rollouts ≥ 2`.
+- **`@metric` returning a dict** lets one method report a whole family of numbers (each key merged
+  into `trace.metrics`). A scalar is recorded under the method name.
+- **`weight`** scales a reward's contribution (`trace.reward = Σ value·weight`); each reward is
+  keyed by its method name, so two rewards (or a reward and a group reward) sharing a name clobber.
+- **`priority`** orders execution within a kind (higher first, then by name). It mostly matters for
+  `@stop` — the highest-priority stop that fires sets the stop reason.
+
+You normally never override `score` / `score_group` — those are the dispatch machinery that finds
+and runs your decorators.
+
+### Reading the trace
+
+A reward reads the finished trajectory off `trace`. The most useful read-only members:
+
+| member | type | what |
+| --- | --- | --- |
+| `trace.task` | `TaskT` | the typed task (your subclass) |
+| `trace.assistant_messages` | `list[AssistantMessage]` | the model's responses in order (excludes prompt-supplied messages) |
+| `trace.messages` | `Messages` | the full conversation (main branch) |
+| `trace.tool_messages` | `list[ToolMessage]` | tool results |
+| `trace.reward` / `trace.rewards` | `float` / `dict` | summed reward / per-function contributions |
+| `trace.metrics` | `dict[str, float]` | recorded metrics |
+| `trace.info` | `dict` | free-form persisted artifact bag (see below) |
+| `trace.state` | `StateT` | transient per-rollout state (see [State](#per-rollout-state)) |
+| `trace.num_turns` | `int` | sampled model turns |
+| `trace.num_branches` / `trace.branches` | `int` / `list` | branch count / the branches (compaction, retokenization) |
+| `trace.is_truncated` | `bool` | hit a turn/token/length cap |
+| `trace.stop_condition` / `trace.is_completed` | `str \| None` / `bool` | why/whether the rollout ended |
+| `trace.has_error` / `trace.error` / `trace.errors` | `bool` / … | error state |
+| `trace.prompt_len` / `completion_len` / `total_tokens` | `int` | token counts |
+| `trace.timing` | `Timing` | per-stage durations |
+
+### In-runtime scoring
+
+To score with a dependency the eval process shouldn't have (e.g. `math-verify`), run it as a uv
+script *in the rollout's runtime* — the dep resolves inside the runtime and never touches the eval
+process:
 
 ```python
 VERIFY = (Path(__file__).parent / "verify.py").read_text()   # PEP 723 header declares its deps
@@ -103,72 +224,88 @@ async def verified(self, task, trace, runtime) -> float:
     return float(r.stdout.strip() == "1.0")
 ```
 
-### Lifecycle hooks
+## Stop conditions
+
+A rollout ends when the harness finishes, a framework budget trips (`--max-turns`, token caps), or
+a taskset `@vf.stop` fires. A stop is an `async (self, trace) -> bool` checked between turns; its
+**method name becomes the stop reason**:
+
+```python
+@vf.stop
+async def saw_answer(self, trace) -> bool:
+    last = trace.assistant_messages[-1].content or ""
+    return "FINAL:" in last
+```
+
+The framework has no built-in "the task is done" signal — multi-turn tasksets end either from the
+trace (above) or from per-rollout state set by a tool / user sim (see [State](#per-rollout-state)).
+
+## Lifecycle hooks
+
+A rollout runs **`setup → harness → finalize → scoring`**, each independently timeout-bounded
+(`--timeout.{setup,rollout,finalize,scoring}`, or per-task `TaskTimeout`). A taskset can hook any
+stage; all are `async`:
 
-A rollout runs `setup → harness → finalize → scoring`, each independently timeout-bounded
-(`--timeout.{setup,rollout,finalize,scoring}`). A taskset can hook any stage (all `async`):
+| hook | signature | when | gets runtime? |
+| --- | --- | --- | --- |
+| `setup` | `(self, task, runtime)` | per-task prep before the harness (clone a repo, start a service) — the trace doesn't exist yet | ✓ |
+| `finalize` | `(self, task, trace, runtime)` | after the harness, before scoring — apply a diff, snapshot, scrape artifacts into `trace.info` | ✓ |
+| `validate` | `(self, task, runtime) -> bool` | model-free gold check (does the reference solution pass?), run only by `uv run validate` | ✓ |
+| `tools` | `(self, task) -> list[vf.Toolset]` | per task, before the harness — the task's tool servers | ✗ |
+| `user` | `(self, task) -> vf.User \| None` | per task, before the harness — the user simulator | ✗ |
 
-- `setup(task, runtime)` — per-task prep before the harness runs (clone a repo, start a service).
-- `finalize(task, trace, runtime)` — after the harness, before scoring (apply a diff, snapshot state, scrape runtime artifacts into `trace.info`).
-- `validate(task, runtime)` — model-free gold check (does the reference solution pass?), run by `uv run validate`.
+`setup`/`finalize`/`validate` errors fail the rollout legibly (captured onto the trace, not a
+crash).
 
-### Runtime access
+## Runtime access
 
 Most hooks run *with the live runtime* and can execute in it, so the whole rollout shares one
-isolated environment. Who gets the `runtime`:
+isolated environment. On a `runtime` you can call:
 
-| hook | signature | runtime |
-| --- | --- | --- |
-| `setup` | `(task, runtime)` | ✓ — prep it before the harness runs (the trace doesn't exist yet) |
-| `finalize` | `(task, trace, runtime)` | ✓ — act on the finished trace + runtime, before scoring |
-| `validate` | `(task, runtime)` | ✓ — model-free gold check |
-| `@reward` / `@metric` / `@stop` | inject any of `task` / `trace` / `runtime` | ✓ |
-| `@group_reward` | `(traces[, task])` | ✗ — runs after the per-rollout runtimes are gone |
+| method | what |
+| --- | --- |
+| `run(argv, env)` | exec a command to completion → `ProgramResult(exit_code, stdout, stderr)` |
+| `run_uv_script(src, args, env)` | run a PEP 723 script (inline deps resolve in-runtime); `args` are shell-`"$@"`-safe |
+| `run_background(argv, env, log)` | start a long-lived process (e.g. a colocated server) |
+| `read(path)` / `write(path, data)` | workspace files (bytes), across the container/sandbox boundary |
+| `expose(port)` | publish a port *inside* the runtime to a host-reachable URL (`None` when local) |
 
-On a `runtime` you can call: `run(argv, env)` (exec to completion → exit code + stdout/stderr),
-`run_uv_script(src, args, env)` (a PEP 723 script with inline deps), `run_background(argv, env,
-log)` (a long-lived server), `read(path)` / `write(path, data)` (workspace files), and
-`expose(port)` (a URL reaching a port inside the runtime).
+A non-zero `exit_code` is a normal result, not an exception — check it and raise `vf.ProgramError`
+yourself if it should fail the stage. The same code works on subprocess / docker / prime / modal.
 
 A SWE taskset is the canonical case: `setup` provisions the repo, the agent edits it during the
 rollout, and a `@reward` runs the tests in the *same* runtime:
 
 ```python
 class SWETaskset(vf.Taskset[SWETask, SWEConfig]):
-    NEEDS_CONTAINER = True   # this taskset needs an isolated container/sandbox runtime
+    NEEDS_CONTAINER = True   # the only Taskset class var: refuse the subprocess runtime
 
-    async def setup(self, task: SWETask, runtime: vf.Runtime) -> None:
-        # prep the runtime before the harness runs: clone + check out the base commit
+    async def setup(self, task, runtime) -> None:
         await runtime.run(["git", "clone", task.repo_url, "/repo"], {})
         await runtime.run(["git", "-C", "/repo", "checkout", task.base_commit], {})
 
-    async def finalize(self, task: SWETask, trace: vf.Trace, runtime: vf.Runtime) -> None:
-        # scrape the agent's diff off the live runtime into trace.info; it persists to results.jsonl
+    async def finalize(self, task, trace, runtime) -> None:
         diff = await runtime.run(["git", "-C", "/repo", "diff"], {})
-        trace.info["diff"] = diff.stdout
+        trace.info["diff"] = diff.stdout   # scrape the agent's diff off the live runtime
 
     @vf.reward()
-    async def tests_pass(self, task: SWETask, trace: vf.Trace, runtime: vf.Runtime) -> float:
-        # the agent edited /repo during the rollout; run the task's tests in that same runtime
+    async def tests_pass(self, task, trace, runtime) -> float:
         result = await runtime.run(["bash", "-lc", task.test_cmd], {})
         return 1.0 if result.exit_code == 0 else 0.0
 ```
 
-`trace.info` is a free-form, JSON-serializable dict for anything that isn't a reward or metric —
-runtime artifacts (the diff above, captured logs, command output) you want persisted with the
-trace for inspection. Like the rewards/metrics it rides along to `results.jsonl`; use `metrics`
-for numbers that aggregate, `trace.info` for everything else.
-
-`trace.state` is the complementary **transient** store: a typed, mutable `vf.State` shared across the
-rollout's tool servers, user simulator, and scoring — the one place per-rollout *runtime* state lives
-(counters, game progress, your own end-of-trajectory flag). Unlike `info` it is **never** persisted to
-disk or sent over the wire. A `@vf.tool` / `respond` reads+writes it as `self.state` (synced over the
-interception server per call, so tools and the user sim see each other's writes); `@reward` /
-`@metric` / `finalize` read+write `trace.state` directly. The base `vf.State` is empty — subclass it
-to declare typed fields and parameterize the taskset (`vf.Taskset[Task, Config, MyState]`) plus any
-stateful server (`vf.Toolset[Config, MyState]` / `vf.User[Config, MyState]`); it defaults to the base.
-To **end a trajectory from state**, set your own flag and declare a `@vf.stop` over it (the framework
-has no built-in end signal):
+`trace.info` is a free-form, **JSON-serializable, persisted** dict for anything that isn't a
+reward or metric — runtime artifacts (the diff above, captured logs, command output) you want in
+`results.jsonl` for inspection. Use `metrics` for numbers that aggregate, `trace.info` for
+everything else (a non-serializable value fails the dump).
+
+## Per-rollout state
+
+`trace.state` is the complementary **transient** store: a typed, mutable `vf.State` shared across
+the rollout's tool servers, user simulator, and scoring — the one place per-rollout *runtime* state
+lives (counters, game progress, your own end-of-trajectory flag). Unlike `info` it is **never**
+persisted to disk or sent over the wire. Subclass `vf.State` to declare typed fields (each needs a
+default) and parameterize the taskset and any stateful server on it:
 
 ```python
 class GameState(vf.State):
@@ -179,83 +316,112 @@ class GameUser(vf.User[vf.UserConfig, GameState]):
         ...
         if finished:
             self.state.game_over = True   # the @vf.stop below ends the rollout
-        return [...]
+        return [{"role": "user", "content": reply}]
 
 class GameTaskset(vf.Taskset[GameTask, GameConfig, GameState]):
     @vf.stop
     async def game_over(self, trace) -> bool:   # stop reason is this method's name
         return trace.state.game_over
 ```
 
+Who touches it how:
+
+- A `@vf.tool` / `respond` reads+writes it as `self.state` — synced over the interception server
+  per call, so tools and the user sim see each other's writes.
+- `@reward` / `@metric` / `finalize` / `@stop` read+write `trace.state` directly.
+
 > **Concurrency — `self.state` is last-write-wins.** Each `@vf.tool` / `respond` call syncs the
-> *whole* state as a read-modify-write: pull `self.state` from the host, run, push it back. Tool calls
-> a harness runs **concurrently** (several `tool_calls` in one assistant turn) therefore race — each
-> reads the same starting state and the last push wins, so concurrent increments/appends are lost.
-> Tools the harness runs **sequentially** compose correctly. Keep shared-state mutations on the
-> sequential path (or accumulate per-key on the host if you need parallel-safe writes). The taskset
-> and its servers must also share **one** `State` subclass — a server that pushes a mismatching shape
-> is rejected (the rollout fails legibly).
-
-Since `@group_reward` has no runtime, fold any runtime-derived signal (here, pass/fail) into a
-per-rollout `@reward`/`@metric` first, then compare those across the task's rollouts.
-
-### Tools and user simulators
-
-Both a tool server and a user simulator are **vf-native classes** (not raw MCP, no FastMCP
-boilerplate) authored from a config — the same shape as a taskset:
-
-- A **tool server** is a `vf.Toolset[ConfigT]` with `@vf.tool` methods (the model sees
-  `<TOOL_PREFIX>_<method>`; the docstring is the description). A taskset exposes a task's tools via
-  `tools(task) -> list[vf.Toolset]`.
-- A **user simulator** is a `vf.User[ConfigT]` with one `async def respond(message) -> Messages` hook
-  (the framework calls it after each assistant turn for the next user message(s); end the trajectory
-  by setting a `self.state` flag a taskset `@vf.stop` checks — see above). A taskset supplies one via
-  `user(task) -> vf.User | None`. If a task carries no prompt (`instruction=None`), the simulator also
-  **opens the conversation**: the framework calls `respond("")` once before the first model turn and
-  seeds its reply as the initial user message.
-
-A taskset may expose **both** at once (tools the model calls *and* a user sim driving the turns) —
-they're served together each rollout; a harness just needs to support both.
-
-**Where they live.** Each server is its own self-launching module under the env package's
-`servers/`, ending with `if __name__ == "__main__": <Server>.run()`; the framework launches it with
-`python -m <env>.servers.<name>` (host: ambient; sandbox: the env package is uploaded + installed
-first). Build state as plain `self.x` attributes in `async def setup(self)` (task-agnostic, runs for
-every server) or `async def setup_task(self, task)` (per-rollout — **skipped for a `shared`
-server**). Those attrs are server-local; for per-rollout state **shared** with the other servers and
-scoring use the typed `self.state` (`trace.state`, above). Fixed data lives in module constants, not
-config.
-
-#### Placement & isolation modes
-
-**Placement** lives on the server's config (a `vf.ToolsetConfig` / `vf.UserConfig` field on the
-taskset), so it's per-server and CLI-tunable (`--taskset.tools.shared true`). It decides **where** the
-server runs and **how many** there are. The default is the cheapest correct thing; the rest trade
-setup cost for isolation.
+> *whole* state as a read-modify-write: pull `self.state` from the host, run, push it back. Tool
+> calls a harness runs **concurrently** (several `tool_calls` in one assistant turn) therefore race
+> — each reads the same starting state and the last push wins, so concurrent increments/appends are
+> lost. Tools the harness runs **sequentially** compose correctly. Keep shared-state mutations on
+> the sequential path. The taskset and its servers must share **one** `State` subclass — a server
+> pushing a mismatching shape is rejected (the rollout fails legibly).
+
+## Tools
+
+A tool server is a **vf-native class** (not raw MCP, no FastMCP boilerplate) authored from a
+config — the same shape as a taskset. Define `@vf.tool` methods on a `vf.Toolset[ConfigT]` (or
+`vf.Toolset[ConfigT, StateT]` for one that shares state); the model sees `<TOOL_PREFIX>_<method>`
+and the docstring is the description:
+
+```python
+class GlossaryToolset(vf.Toolset[GlossaryToolsetConfig]):
+    TOOL_PREFIX = "glossary"            # model sees glossary_lookup (empty → class name snake-cased)
+
+    async def setup(self) -> None:
+        self.facts = _load_facts()       # task-agnostic, runs once per server process
+
+    @vf.tool
+    def lookup(self, name: str) -> str:  # typed params the model fills; docstring → description
+        """Look up a glossary term."""
+        return self.facts.get(name.lower(), "unknown")
+```
+
+Two setup hooks, plus the shared state:
+
+- `async def setup(self)` — task-agnostic, runs for **every** server (shared or per-rollout); build
+  expensive global data as plain `self.x` attributes here.
+- `async def setup_task(self, task)` — per-rollout init off `task`; **skipped for a `shared`
+  server** (warns if defined there).
+- `self.config` is the server's typed knobs; `self.state` is the shared per-rollout `State`.
+
+A taskset exposes a task's tools via `tools(task) -> list[vf.Toolset]`, constructing each from a
+config field so placement is CLI-tunable (below).
+
+## User simulators
+
+A user simulator is a `vf.User[ConfigT]` (or `[ConfigT, StateT]`) with one hook:
+
+```python
+class HagglerUser(vf.User[vf.UserConfig, HagglerState]):
+    async def respond(self, message: str) -> vf.Messages:
+        # the model's last assistant text in → the next user message(s) out ([] to emit nothing)
+        if done:
+            self.state.deal_closed = True       # end via a @vf.stop the taskset declares
+        return [{"role": "user", "content": reply}]
+```
+
+The framework calls `respond` after each assistant turn and injects the reply as the next user
+message; it's consumed by the framework, never shown to the model. A taskset supplies one via
+`user(task) -> vf.User | None`. If a task carries **no prompt** (`prompt=None`), the simulator also
+**opens the conversation**: the framework calls `respond("")` once before the first model turn and
+seeds its reply as the initial user message. End the trajectory by setting a `self.state` flag a
+taskset `@vf.stop` checks (there's no built-in end signal).
+
+A taskset may expose **both** tools and a user sim at once — they're served together each rollout;
+the harness just needs to support both.
+
+## Server placement & isolation
+
+Each tool/user server is its own self-launching module under the env package's `servers/`, ending
+with `if __name__ == "__main__": <Server>.run()`; the framework launches it with
+`python -m <env>.servers.<name>`. **Placement** lives on the server's config (a `vf.ToolsetConfig`
+/ `vf.UserConfig` field on the taskset config), so it's per-server and CLI-tunable
+(`--taskset.tools.shared true`). It decides **where** the server runs and **how many** there are —
+the default is the cheapest correct thing; the rest trade setup cost for isolation:
 
 | mode | config | runs | pros | cons |
 | --- | --- | --- | --- | --- |
-| **own host** *(default)* | *(nothing)* | own `subprocess` runtime on the host, one per rollout | cheapest launch (nothing to fetch); full per-rollout isolation | pays `setup` every rollout |
+| **own host** *(default)* | *(nothing)* | own `subprocess` runtime on the host, one per rollout | cheapest launch; full per-rollout isolation | pays `setup` every rollout |
 | **own sandbox** | `runtime = {type = "docker"\|"prime"}` | own sandbox per rollout, over a tunnel | isolates untrusted tool code / deps / network | sandbox spin-up + env install + `setup`, every rollout |
-| **colocated** | `colocated = true` | inside the harness's runtime, one per rollout (no tunnel) | no extra runtime/tunnel; can touch the harness's filesystem | per-rollout env install in a sandbox; couples to harness; `setup` per rollout |
-| **shared** | `shared = true` | one instance for the whole eval | `setup` once; writable per-rollout if state lives in `self.state` (secret-routed) | state outside `self.state` corrupts across rollouts; `setup_task` skipped |
-| **shared + fork** | `shared = true, fork = true` | warm parent + forked child per rollout (copy-on-write) | `setup` once **and** isolates arbitrary in-process/on-disk state; runs `setup_task` per child | a process per concurrent rollout; CoW erodes for pure-Python heap; one proxy = throughput ceiling; Linux only |
+| **colocated** | `colocated = true` | inside the harness's runtime, one per rollout (no tunnel) | no extra runtime/tunnel; can touch the harness's filesystem | couples to the harness; `setup` per rollout |
+| **shared** | `shared = true` | one instance for the whole eval | `setup` once; writable per-rollout if state lives in `self.state` | state outside `self.state` corrupts across rollouts; `setup_task` skipped |
+| **shared + fork** | `shared = true, fork = true` | warm parent + forked child per rollout (copy-on-write) | `setup` once **and** isolates arbitrary in-process/on-disk state; runs `setup_task` per child | a process per concurrent rollout; Linux only |
 | **remote** *(tools only)* | `url = "https://…"` | connects to an already-running MCP endpoint | zero hosting; use a public/third-party server | no isolation, state, or lifecycle control |
 
-`shared` works on any runtime (local or remote) and `fork` too: the framework makes the rollout's
-`/state` + `/task` channel reachable from the shared server — localhost, or a host tunnel when it's
-remote. Keep big shared data off the Python heap (numpy / mmap / an on-disk index) so fork's
-copy-on-write actually saves memory.
+`shared` (and `fork`) work on any runtime — the framework makes the rollout's `/state` channel
+reachable from the shared server (localhost, or a host tunnel when remote). Keep big shared data
+off the Python heap (numpy / mmap / an on-disk index) so fork's copy-on-write actually saves
+memory.
 
 **Choosing per-rollout state:** read-only resource → `shared`; state that fits a `State` model →
 `shared` + `self.state` (no extra process, the scalable default); state that can't (module globals,
-on-disk scratch, a stateful C library) → `shared + fork` or a per-rollout placement that pays `setup`
-each time; cheap `setup` → just use the default.
-
-**User simulators** support only the per-rollout placements (own runtime or `colocated`); `shared` /
-`fork` / `url` are tools-only.
+on-disk scratch, a stateful C library) → `shared + fork` or a per-rollout placement that pays
+`setup` each time; cheap `setup` → just use the default. **User simulators** support only the
+per-rollout placements (own runtime or `colocated`); `shared` / `fork` / `url` are tools-only.
 
-### Learn from the examples
+## Learn from the examples
 
 The `*_v1` tasksets under `environments/` are the reference library — each shows one pattern:
 
@@ -268,19 +434,23 @@ The `*_v1` tasksets under `environments/` are the reference library — each sho
 | `glossary-v1` | the simplest tool server (own host runtime) |
 | `wikispeedia-v1` | a stateful tool server (global `setup` + per-task `setup_task`) |
 | `wiki-search-v1` | a shared, read-only tool server (built once) + an LLM judge |
-| `scratchpad-v1` | a shared, **writable** tool server — per-rollout state isolated via `self.state` (or `--taskset.tools.fork true` for state outside it) |
+| `scratchpad-v1` | a shared, **writable** tool server — per-rollout state isolated via `self.state` |
 | `deepwiki-v1` | an existing remote tool server, by URL |
 | `color-codeword-v1` | a multimodal (image) task |
 | `scaleswe-v1`, `swelego-v1`, `r2e-gym-v1` | containerized SWE tasks (rlm harness, prime runtime) |
 | `wordle-v1`, `terminal-bench-2-v1` | thin configs over the shipped `textarena-v1` / `harbor-v1` integrations |
 
-## Harnesses
+---
+
+# Authoring a harness
 
-Built-ins, selected with `--harness.id`:
+You rarely need this — a custom harness is for a rollout loop the built-ins can't express
+(context compaction, subagents, a bespoke agent CLI). Built-ins, selected with `--harness.id`:
 
 | id | what it is |
 | --- | --- |
-| `default` | a tiny OpenAI chat loop (bash tool opt-in via `--harness.enable-bash`) |
+| `default` | a tiny OpenAI chat loop (MCP tools only, no tools of its own) |
+| `bash` | the `default` chat loop plus a local `bash` tool, for shell-driving agents |
 | `rlm` | the RLM CLI agent |
 | `codex` | the Codex CLI (Responses dialect + SSE relay) |
 
@@ -289,27 +459,23 @@ uv run eval gsm8k-v1 -n 1                    # default harness
 uv run eval gsm8k-v1 -n 1 --harness.id rlm   # same taskset, different driver
 ```
 
-**Capability flags** gate which tasksets a harness can run, so an incompatible pairing fails
-fast at load instead of mis-running: `SUPPORTS_TASK_TOOLS`, `SUPPORTS_USER_SIM`,
-`SUPPORTS_MESSAGE_INSTRUCTION`, `APPENDS_SYSTEM_PROMPT` (class vars on the harness).
+## Capability flags
 
-### Authoring a harness
+Class vars on the harness gate which tasksets it can run, so an incompatible pairing fails fast at
+load instead of mis-running:
 
-You rarely need this — a custom harness is for a rollout loop the built-ins can't express
-(context compaction, subagents, a bespoke agent CLI). Define a `HarnessConfig` (its `id` plus
-any knobs, which surface as `--harness.*`), subclass `vf.Harness[ConfigT]`, declare the
-capability flags, and implement `launch` — it drives the model however it likes and returns the
-program's result (the base `run` wraps it and errors on a non-zero exit). Export the harness
-class via `__all__`.
-
-A harness never builds the trace itself: it just points *a program* at `endpoint` (authorized
-with `secret`), and the interception server records every call. The program can be any
-executable the runtime can run — an agent CLI, a binary, a script — **as long as it makes its
-model requests in one of the supported dialects** (chat-completions, Responses, ...); that's
-the whole contract. For a self-contained chat loop it's usually a single-file uv script
-(`runtime.run_uv_script`, so the harness needs only `uv` in the runtime); otherwise launch your
-binary with `runtime.run(...)`. `resolve_prompt(trace.task)` gives the `(system, instruction)`
-to seed it, and `mcp_urls` are the task's tool servers.
+| flag | default | gates |
+| --- | --- | --- |
+| `SUPPORTS_TASK_TOOLS` | `True` | exposes the task's MCP tools to the model (set `False` for a harness with no MCP client) |
+| `SUPPORTS_USER_SIM` | `False` | drives a task's user simulator (multi-turn user injection) |
+| `SUPPORTS_MESSAGE_PROMPT` | `False` | accepts a `Messages`-list `task.prompt` (e.g. image-bearing) |
+| `APPENDS_SYSTEM_PROMPT` | `False` | emits `task.system_prompt` as a real system message (else it's folded into the user prompt with a warning) |
+
+## Writing one
+
+Define a `HarnessConfig` (its `id` plus any knobs, which surface as `--harness.*`), subclass
+`vf.Harness[ConfigT]`, declare the capability flags, and implement `launch`. Export the class via
+`__all__`.
 
 ```python
 import verifiers.v1 as vf
@@ -319,98 +485,215 @@ PROGRAM = (Path(__file__).parent / "program.py").read_text()  # a uv script, dep
 
 class MyHarnessConfig(vf.HarnessConfig):
     id: str = "my-harness"
-    enable_bash: bool = False        # a harness-specific knob; surfaces as --harness.enable-bash
+    max_steps: int = 50              # a harness-specific knob; surfaces as --harness.max-steps
 
 
 class MyHarness(vf.Harness[MyHarnessConfig]):
     SUPPORTS_TASK_TOOLS = True
     SUPPORTS_USER_SIM = True
 
     async def launch(self, ctx, trace, runtime, endpoint, secret, mcp_urls) -> vf.ProgramResult:
-        system, instruction = self.resolve_prompt(trace.task)
+        system, prompt = self.resolve_prompt(trace.task)
         env = {"OPENAI_BASE_URL": endpoint, "OPENAI_API_KEY": secret,
                "OPENAI_MODEL": ctx.model, "SYSTEM_PROMPT": system or "",
-               "ENABLE_BASH": "1" if self.config.enable_bash else "0"}
-        return await runtime.run_uv_script(PROGRAM, args=[instruction], env=env)
+               "MAX_STEPS": str(self.config.max_steps)}
+        if mcp_urls:                 # standard mcpServers map the program connects to
+            env["MCP_CONFIG"] = json.dumps({"mcpServers": {n: {"url": u} for n, u in mcp_urls.items()}})
+        return await runtime.run_uv_script(PROGRAM, args=[prompt], env=env)
 
 
-__all__ = ["MyHarness"]   # vf resolves the harness by finding this Harness subclass
+__all__ = ["MyHarness"]
 ```
 
-Copy `environments/compact` (a context-rewrite loop) as a starting point.
+**The contract.** A harness never builds the trace itself: it just points *a program* at
+`endpoint` (authorized with `secret`), and the interception server records every model call —
+**as long as the program makes its requests in one of the supported dialects** (chat-completions,
+Responses, Anthropic Messages). The program can be any executable the runtime can run.
+
+`launch` receives:
+
+- `ctx` — the rollout's collaborators; read `ctx.model` for the model id (`ctx.client` /
+  `ctx.sampling` exist but model calls flow through `endpoint`, not the client object).
+- `trace` — the task is `trace.task`.
+- `runtime` — where to run the program.
+- `endpoint` / `secret` — the interception server URL and its bearer token.
+- `mcp_urls` — the task's tool servers as `{name: url}` to wire in.
+
+It must return a `vf.ProgramResult` (`exit_code`, `stdout`, `stderr`) — usually the return of
+`runtime.run(...)` / `runtime.run_uv_script(...)`. The base `run` wraps `launch`: a clean exit
+becomes `trace.stop("agent_completed")`; a non-zero exit raises `ProgramError` with the tail of
+stderr — **unless** a `@stop` already fired (the program dying because the interception server cut
+a turn is expected, not an error).
+
+**`resolve_prompt(trace.task)`** returns `(system_prompt, prompt)` already reconciled with your
+capability flags: the system prompt is handed back only if `APPENDS_SYSTEM_PROMPT` (else folded
+into `prompt`); `prompt` is a `str`, a `Messages` list (if `SUPPORTS_MESSAGE_PROMPT`), or `None`
+(no prompt → let the user simulator / interception server open the conversation, so send no opening
+user message).
 
-## Runtimes
+**Two program styles.** A self-contained chat loop is usually a single-file uv script
+(`runtime.run_uv_script`, so the harness needs only `uv` in the runtime — its inline deps resolve
+there, never in the eval process; identical scripts share one content-addressed uv env). An agent
+CLI / binary is installed and launched with `runtime.run(...)`. Either way, harness-owned env vars
+(`OPENAI_BASE_URL` / `OPENAI_API_KEY` / `OPENAI_MODEL`, …) are spread *after* `self.config.env`, so
+they take precedence over any collision.
+
+**Harness metrics.** A harness can define its own `@vf.metric` methods (injected `task` / `trace` /
+`runtime`), run over the finished trace alongside the taskset's — handy to surface what the program
+left behind in the runtime (e.g. read a `meta.json` the binary wrote). A harness can't define
+rewards.
+
+Copy `environments/compact` (a context-rewrite loop) as a starting point. A harness is resolved by
+its `id` the same way a taskset is — built-ins live under `packages/harnesses/harnesses/<id>/`; a
+custom one is a local package or a Hub id.
+
+---
+
+# Runtimes
 
 The same `Runtime` contract backs the harness (`--harness.runtime`), a task's tools
-(`--taskset.tools.runtime`), and the user simulator:
+(`--taskset.tools.runtime`), and the user simulator. You choose where code runs; you never write
+one:
 
 ```bash
 uv run eval gsm8k-v1 -n 1 --harness.runtime.type subprocess  # local process (eval default)
 uv run eval gsm8k-v1 -n 1 --harness.runtime.type docker      # local container
-uv run eval gsm8k-v1 -n 1 --harness.runtime.type prime       # remote prime sandbox
-uv run eval gsm8k-v1 -n 1 --harness.runtime.type modal       # remote modal sandbox
+uv run eval gsm8k-v1 -n 1 --harness.runtime.type prime       # remote prime sandbox (requires auth)
+uv run eval gsm8k-v1 -n 1 --harness.runtime.type modal       # remote modal sandbox (requires auth)
 ```
 
-## Evals
+A taskset that sets `NEEDS_CONTAINER` (or a task with an `image`) refuses the subprocess runtime —
+pass `docker` / `prime` / `modal`.
+
+---
+
+# CLI reference
+
+Three commands, all `uv run <cmd>`: **`eval`** (run + score a model), **`validate`** (model-free
+gold check), **`init`** (scaffold). They share a resolution layer:
+
+- **Positional id** — a leading bare token is the taskset id: `eval gsm8k-v1` == `eval --taskset.id
+  gsm8k-v1` (for `init` it's the env name).
+- **`@ file.toml`** — load a saved config; extra flags still override (`eval @ config.toml -n 5`).
+- **`-h` / no args** — print help, *narrowed to the chosen taskset/harness* so it shows their real
+  `--taskset.*` / `--harness.*` fields, not the generic base.
+
+## `eval`
+
+Run a model rollout per task and score it: fan out `-r` rollouts per task with bounded
+concurrency, score each trace, and persist everything.
 
 ```bash
 uv run eval gsm8k-v1 -n 5 -r 3 \
+  -m openai/gpt-5-mini \                                            # model
   --max-turns 8 --max-total-tokens 8192 \                          # per-rollout budgets
-  --retries.model.max-retries 3 --retries.runtime.max-retries 3 \  # retry one failed call
-  --retries.rollout.max-retries 3 --retries.rollout.include ProgramError \  # retry a whole rollout, by error type
-  --timeout.rollout 600 --timeout.scoring 120                      # per-stage wall-clock caps (seconds)
+  --sampling.temperature 0 --sampling.max-tokens 2048 \            # generation knobs
+  --timeout.rollout 600 --timeout.scoring 120 \                    # per-stage wall-clock caps (s)
+  --retries.rollout.max-retries 3 --retries.rollout.include ProgramError  # retry a whole rollout
 ```
 
-Common aliases: `-m`/`--model`, `-n`/`--num-tasks`, `-r`/`--num-rollouts`,
-`-c`/`--max-concurrent`, `-s`/`--shuffle`, `-o`/`--output-dir`, `-v`/`--verbose`,
-`--no-rich` (disable the live dashboard).
-
-- **Sampling** — set provider-neutral generation knobs under `sampling`, for example
-  `--sampling.temperature 0 --sampling.max-tokens 2048 --sampling.reasoning-effort medium`,
-  or:
-
-  ```toml
-  [sampling]
-  temperature = 0
-  max_tokens = 2048
-  reasoning_effort = "medium"
-  ```
-
-  The active dialect maps the string field `reasoning_effort` to the top-level
-  `reasoning_effort` field for chat-completions, `reasoning.effort` for Responses, or
-  `output_config.effort` for Anthropic Messages.
-- **Configs** — a saved run is `uv run eval @ config.toml` (the taskset/harness `id`s live in
-  the file); CLI flags still override. `--dry-run` writes the resolved `config.toml` without
-  running. Logs are teed to `<output_dir>/eval.log`.
-- **Resume** — `uv run eval --resume <output-dir>` re-runs only the missing/errored rollouts
-  of a previous run.
-- **Clients** — eval (default) is a plain chat-completions relay. `--client.type train`
-  tokenizes client-side so each node carries the exact `token_ids` / `mask` / `logprobs`
-  (needs a vLLM engine via `--client.base-url`).
-- **Validate** — `uv run validate gsm8k-v1` runs each taskset's `validate` hook (model-free
-  gold check), no model needed.
-
-## Training
-
-prime-rl consumes the same env over the env-server, so a training env is the eval config in
-TOML form. In a prime-rl config:
+**Common flags** (each has a TOML equivalent at the dotted path):
+
+| group | flags |
+| --- | --- |
+| selection | `<taskset-id>` / `--taskset.id`, `--harness.id` (`default`), `-m`/`--model` |
+| counts | `-n`/`--num-tasks` (all), `-r`/`--num-rollouts` (1; `@group_reward` needs ≥2), `-s`/`--shuffle` |
+| budgets | `--max-turns`, `--max-input-tokens`, `--max-output-tokens`, `--max-total-tokens` (all None) |
+| sampling | `--sampling.temperature`, `--sampling.top-p`, `--sampling.max-tokens`, `--sampling.reasoning-effort` (provider keys pass through) |
+| timeouts | `--timeout.setup`, `--timeout.rollout`, `--timeout.finalize`, `--timeout.scoring` (None = no limit) |
+| retries | `--retries.model.max-retries` (3), `--retries.runtime.max-retries` (3), `--retries.rollout.max-retries` (0), `--retries.rollout.include`/`.exclude` (by exception name) |
+| client | `--client.type` (`eval`\|`train`), `--client.base-url`, `--client.api-key-var` |
+| runtime | `--harness.runtime.type` (`subprocess`), `--harness.env`, `--harness.disabled-tools` |
+| concurrency | `-c`/`--max-concurrent` (128), `--multiplex` (32), `--pool.type` (`elastic`\|`static`) |
+| output | `-o`/`--output-dir`, `--dry-run`, `--no-rich`, `-v`/`--verbose` |
+
+**Sampling.** `reasoning_effort` is a string (not a fixed enum) — the active dialect maps it to the
+provider's shape (`reasoning_effort` for chat-completions, `reasoning.effort` for Responses,
+`output_config.effort` for Anthropic).
+
+**Clients.** `eval` (default) is a plain chat-completions relay. `--client.type train` tokenizes
+client-side so each node carries the exact `token_ids` / `mask` / `logprobs` (the training dialect)
+— point it at a vLLM engine with `--client.base-url`.
+
+**What it writes** (into `--output-dir`, default `outputs/<taskset>--<model>--<harness>/<uuid>`):
+`config.toml` (the resolved config, re-runnable via `@ config.toml`), `results.jsonl` (one full
+trace per line, appended as each rollout finishes — durable mid-run), and `eval.log`.
+
+**`--dry-run`** writes `config.toml` and exits (resolve + validate, no run). **`--resume
+<output-dir>`** re-runs only the missing/errored rollouts of a previous run (it reloads that run's
+`config.toml`, so it takes no other args).
+
+## `validate`
+
+Run each task's `validate` hook — a model-free check that the ground truth holds (the gold patch
+makes the tests pass, the verifier accepts the gold answer) — in a runtime with the taskset's
+`setup` applied. No model, no harness.
+
+```bash
+uv run validate gsm8k-v1 -n 20 --runtime.type subprocess
+```
+
+| flag | default | meaning |
+| --- | --- | --- |
+| `<taskset-id>` / `--taskset.id` | — | taskset to validate |
+| `--runtime.type` | `docker` | runtime for `setup` + `validate` (a gold check often needs the task's container) |
+| `--setup-timeout` / `--validate-timeout` | None | per-hook wall-clock caps |
+| `--retries.runtime.max-retries` | 3 | the only retry that applies (fresh runtime per try) |
+| `-n`/`--num-tasks`, `-s`/`--shuffle`, `-c`/`--max-concurrent` (128) | | task selection + concurrency |
+| `-v`/`--verbose`, `--no-rich` | | logging / disable the dashboard |
+
+Each task is provisioned, set up, validated, and torn down independently; a raised error is
+captured as a result row (one bad task is data, not a crash) with reason `valid` / `invalid` /
+`timeout` / `error`. **Fire-and-forget — nothing is written to disk**; results show live. Note the
+default runtime is **docker** (unlike eval's subprocess), and a subprocess runtime against a
+`NEEDS_CONTAINER` / image-bearing taskset aborts with a clear error.
+
+## `init`
+
+Scaffold a new v1 environment package under `--path` (default `./environments`), following the
+shipped `*_v1` layout: a `pyproject.toml`, a `README.md`, a package whose `__init__.py` re-exports
+the plugin via `__all__`, and a `taskset.py` that runs out of the box (replace `load_tasks` and the
+`@reward`).
+
+```bash
+uv run init my-task-v1                  # minimal taskset package
+uv run init my-task-v1 -T -U -H         # + a tool server, a user sim, a custom harness
+uv run init legacy-env --v0             # a legacy v0 load_environment package instead
+```
+
+| flag | meaning |
+| --- | --- |
+| `<name>` / `--name` | the new env id (`my-task-v1`); package dir, ids, class names are derived from it |
+| `-p`/`--path` | parent directory (default `./environments`) |
+| `-T`/`--add-tool` | also scaffold a `vf.Toolset` (`servers/tool.py`), wired into the taskset |
+| `-U`/`--add-user` | also scaffold a `vf.User` simulator (`servers/user.py`) + a typed `State` + `@vf.stop` |
+| `-H`/`--add-harness` | also scaffold a custom `vf.Harness` (`harness.py`), selectable via `--harness.id <name>` |
+| `--v0` | scaffold a legacy v0 environment instead (can't combine with `--add-*`) |
+| `--force` | overwrite an existing package (default: refuse) |
+
+---
+
+# Training
+
+prime-rl consumes the same env over the env-server, so a training env is the eval config in TOML
+form. In a prime-rl config:
 
 ```toml
 [[orchestrator.train.env]]
 name    = "gsm8k"
 taskset = { id = "math-env-v1", dataset_name = "..." }              # any v1 taskset id
-harness = { id = "default", enable_bash = false, runtime = { type = "subprocess" } }
+harness = { id = "default", runtime = { type = "subprocess" } }
 timeout = { scoring = 10 }                                          # per-stage cap (default: no limit)
 # pool  = { type = "elastic", max_workers = 8, multiplex = 128 }    # env-server pool (default elastic, self-sizing)
 ```
 
-`[orchestrator.renderer]` is required (set `name = "auto"` or a specific renderer) — the
-renderer tokenizes rollouts into training samples. 
+`[orchestrator.renderer]` is required (set `name = "auto"` or a specific renderer) — the renderer
+tokenizes rollouts into training samples.
 
-## Backwards compatibility
+# Backwards compatibility
 
-A classic v0 `verifiers.load_environment` env runs through the v1 CLIs via the legacy bridge —
-its rollouts mapped to v1 `Trace`s. Use `--id` instead of a `taskset`:
+A classic v0 `verifiers.load_environment` env runs through the v1 CLIs via the legacy bridge — its
+rollouts mapped to v1 `Trace`s. Use `--id` instead of a `taskset`:
 
 ```bash
 uv run eval --id reverse-text -n 2                                  # eval a v0 env
diff --git a/verifiers/v1/README.md b/verifiers/v1/README.md
--- a/verifiers/v1/README.md
+++ b/verifiers/v1/README.md
@@ -63,41 +63,13 @@ Common knobs have short aliases:
 | `-o`  | `--output-dir`     | where to write results        | a fresh per-run dir          |
 |       | `--no-rich`        | disable the live dashboard    | dashboard on                 |
 
-### Sampling
-
-Sampling is provider-neutral config. Set reasoning effort with the optional string
-`sampling.reasoning_effort`, alongside the standard sampling knobs:
-
-```bash
-uv run eval gsm8k-v1 \
-  --sampling.temperature 0 \
-  --sampling.max-tokens 2048 \
-  --sampling.reasoning-effort medium
-```
-
-```toml
-[sampling]
-temperature = 0
-max_tokens = 2048
-reasoning_effort = "medium"
-```
-
-The request dialect maps `reasoning_effort` to the provider's wire shape:
-
-- OpenAI chat-completions: `reasoning_effort`
-- OpenAI Responses: `reasoning.effort`
-- Anthropic Messages: `output_config.effort`
-
-The value is a string rather than a fixed enum because providers support different effort
-levels.
-
 ## Tasksets & harnesses
 
 Tasksets (data + scoring) and harnesses (the rollout driver) are Python packages 
 and live in two places:
 
 - **`packages/`** — shipped, installed by default. Commonly-used **harnesses** (`default`,
-  `rlm`, `codex`, ...) and **taskset integrations** that wrap a whole benchmark family (`harbor-v1` — 
+  `bash`, `rlm`, `codex`, ...) and **taskset integrations** that wrap a whole benchmark family (`harbor-v1` — 
   the agentic-benchmark registry; `textarena-v1` — TextArena games).
 - **`environments/`** — small reference implementations to copy when **authoring your own**
   (the `*_v1` tasksets and the `compact` harness), co-located with the standalone v0
@@ -131,20 +103,31 @@ Harness examples (under `environments/`):
 The program that drives the rollout — same taskset, different driver:
 
 ```bash
-uv run eval gsm8k-v1 -n 1                     # default: a tiny OpenAI chat loop (bash tool opt-in)
+uv run eval gsm8k-v1 -n 1                     # default: bare agent (MCP tools only)
 uv run eval gsm8k-v1 -n 1 --harness.id rlm    # the rlm harness
 uv run eval gsm8k-v1 -n 1 --harness.id codex  # the codex harness
 ```
 
+The same drivers on an agentic terminal task — harbor's `hello-world`. The task acts on a
+filesystem, so run it under a containerized runtime: `docker` locally, or a remote `prime` /
+`modal` sandbox (not the default `subprocess`). 
+
+```bash
+uv run eval harbor-v1 -n 1 --taskset.use-harness-image --harness.runtime.type docker --harness.id bash            # bash-only agent
+uv run eval harbor-v1 -n 1 --taskset.use-harness-image --harness.runtime.type docker --harness.id mini-swe-agent  # the mini-swe-agent CLI
+uv run eval harbor-v1 -n 1 --taskset.use-harness-image --harness.runtime.type docker --harness.id rlm             # the rlm CLI agent
+uv run eval harbor-v1 -n 1 --taskset.use-harness-image --harness.runtime.type docker --harness.id codex           # the codex CLI agent
+```
+
 ### Swappable runtime
 
-*Where* code runs, behind one `Runtime` contract — the same contract backs the harness
+Where code runs, behind one `Runtime` contract — the same contract backs the harness
 (`--harness.runtime`), a task's own tool servers (`--taskset.tools.runtime`), and the user
 simulator (`--taskset.user.runtime`) — all structurally MCP servers in a runtime:
 
 ```bash
 uv run eval gsm8k-v1 -n 1 --harness.runtime.type subprocess  # local process (default)
-uv run eval gsm8k-v1 -n 1 --harness.runtime.type docker      # local container
+uv run eval gsm8k-v1 -n 1 --harness.runtime.type docker      # local container (requires local docker)
 uv run eval gsm8k-v1 -n 1 --harness.runtime.type prime       # remote prime sandbox (requires auth)
 uv run eval gsm8k-v1 -n 1 --harness.runtime.type modal       # remote modal sandbox (requires auth)
 ```
@@ -223,7 +206,9 @@ uv run eval gsm8k-v1 -n 1 --client.type train \      # train: client-side tokeni
   --client.base-url http://localhost:8000/v1
 ```
 
-`eval` is the default; `train` is only needed for the prime-rl training integration (it tokenizes client-side so each branch comes back as a ready training sample).
+`eval` is the default; `train` is only needed for the prime-rl training
+integration (it tokenizes client-side so each branch comes back as a ready
+training sample).
 
 ### Budgets
 
diff --git a/verifiers/v1/__init__.py b/verifiers/v1/__init__.py
--- a/verifiers/v1/__init__.py
+++ b/verifiers/v1/__init__.py
@@ -28,7 +28,6 @@
 from verifiers.v1.episode import Episode
 from verifiers.v1.errors import ModelError, ProgramError, RolloutError, ToolError
 from verifiers.v1.harness import Harness, HarnessConfig
-from verifiers.v1.ids import EnvId, ensure_installed, env_name
 from verifiers.v1.loaders import (
     harness_config_type,
     import_harness,
@@ -49,7 +48,7 @@
     SubprocessConfig,
 )
 from verifiers.v1.state import State, StateT
-from verifiers.v1.task import Resources, Task, WireTask
+from verifiers.v1.task import Task, TaskResources, TaskTimeout, WireTask
 from verifiers.v1.taskset import Taskset, TasksetConfig
 from verifiers.v1.mcp import (
     Toolset,
@@ -64,16 +63,19 @@
     TimeSpan,
     Timing,
     Trace,
+    WireTrace,
 )
 from verifiers.v1.types import (
     AssistantMessage,
     ContentPart,
+    EnvId,
     ImageUrlContentPart,
     ImageUrlSource,
     Message,
     MessageContent,
     Messages,
     Response,
+    Sampling,
     SamplingConfig,
     StrictBaseModel,
     SystemMessage,
@@ -89,8 +91,6 @@
 __all__ = [
     # types
     "EnvId",
-    "ensure_installed",
-    "env_name",
     "AssistantMessage",
     "ContentPart",
     "ImageUrlContentPart",
@@ -99,6 +99,7 @@
     "MessageContent",
     "Messages",
     "Response",
+    "Sampling",
     "SamplingConfig",
     "StrictBaseModel",
     "SystemMessage",
@@ -111,8 +112,10 @@
     # task / trace / state
     "Task",
     "WireTask",
-    "Resources",
+    "TaskResources",
+    "TaskTimeout",
     "Trace",
+    "WireTrace",
     "State",
     "StateT",
     "MessageNode",
diff --git a/verifiers/v1/cli/__init__.py b/verifiers/v1/cli/__init__.py
--- a/verifiers/v1/cli/__init__.py
+++ b/verifiers/v1/cli/__init__.py
@@ -1,2 +1,3 @@
-"""CLI commands. Each module exposes a `main()` registered in pyproject's
-`[project.scripts]` (e.g. `eval`) and runnable via `uv run <name> ...`."""
+"""CLI commands. Each exposes a `main()` registered in pyproject's `[project.scripts]` and
+runnable via `uv run <name> ...` — a single module (`validate`, `serve`, `init`), or a
+subpackage whose entry is `<name>.main` (`eval`)."""
diff --git a/verifiers/v1/cli/dashboard/eval.py b/verifiers/v1/cli/dashboard/eval.py
--- a/verifiers/v1/cli/dashboard/eval.py
+++ b/verifiers/v1/cli/dashboard/eval.py
@@ -12,7 +12,7 @@
 import contextlib
 import time
 
-from rich.console import Group
+from rich.console import Console, Group
 from rich.progress_bar import ProgressBar
 from rich.rule import Rule
 from rich.table import Table
@@ -23,7 +23,12 @@
 from verifiers.v1.configs.eval import EvalConfig
 from verifiers.v1.rollout import Phase, Rollout
 from verifiers.v1.trace import Trace
-from verifiers.v1.utils import format_count, format_reward, format_time
+from verifiers.v1.utils.format import format_count, format_reward, format_time
+
+# For sizing pages to the terminal: detects the real terminal height/width each access (the live
+# view writes to the same terminal). Reused so we don't rebuild it every refresh tick.
+_CONSOLE = Console()
+_PAGE_SECONDS = 3.0  # rotate to the next page of rollouts this often when they overflow
 
 _STYLE = {
     "setup": "yellow",
@@ -43,12 +48,68 @@
 }
 
 
-def Overview(config: EvalConfig) -> Table:
-    sampling = (
-        ", ".join(
-            f"{k}={v}" for k, v in config.sampling.model_dump(exclude_none=True).items()
+def _limits(config: EvalConfig) -> list[str]:
+    """Per-rollout caps for the overview (concurrency first, then turns, tokens). An unset cap
+    reads as 'no ...' rather than being hidden."""
+    toks = []
+    if config.max_input_tokens:
+        toks.append(f"in≤{config.max_input_tokens}")
+    if config.max_output_tokens:
+        toks.append(f"out≤{config.max_output_tokens}")
+    if config.max_total_tokens:
+        toks.append(f"total≤{config.max_total_tokens}")
+    return [
+        f"≤{config.max_concurrent} concurrent"
+        if config.max_concurrent
+        else "no concurrency cap",
+        f"{config.max_turns} turns" if config.max_turns else "no turn cap",
+        f"{', '.join(toks)} tokens" if toks else "no token cap",
+    ]
+
+
+def _timeouts(config: EvalConfig) -> list[str]:
+    """Per-stage rollout timeouts for the overview, each stage enumerated (unset → 'no <stage>
+    timeout')."""
+    return [
+        f"{stage} {v:g}s"
+        if (v := getattr(config.timeout, stage))
+        else f"no {stage} timeout"
+        for stage in ("setup", "rollout", "finalize", "scoring")
+    ]
+
+
+def _aligned(rows: list[list[str]]) -> list[str]:
+    """Join each row's `·`-separated segments, padding shared columns to a common width so the
+    separators line up across rows (each row's last segment is left ragged)."""
+    widths: dict[int, int] = {}
+    for row in rows:
+        for i, seg in enumerate(row):
+            widths[i] = max(widths.get(i, 0), len(seg))
+    return [
+        "  ·  ".join(
+            seg.ljust(widths[i]) if i < len(row) - 1 else seg
+            for i, seg in enumerate(row)
+        )
+        for row in rows
+    ]
+
+
+def _warning(config: EvalConfig) -> Text | None:
+    """A local-runtime caution for a code-running harness (none for the tool-less `default`),
+    shown above the overview rather than as a row in it."""
+    if config.harness.id != "default" and config.harness.runtime.type == "subprocess":
+        return Text(
+            "warning  Runs on the local system; local files and settings may affect this "
+            "evaluation. Use subprocess only for debugging, or use docker or prime for an "
+            "isolated run.",
+            style="yellow",
         )
-        or "default"
+    return None
+
+
+def Overview(config: EvalConfig) -> Table:
+    sampling = ", ".join(
+        f"{k}={v}" for k, v in config.sampling.model_dump(exclude_none=True).items()
     )
     grid = Table.grid(padding=(0, 2))
     grid.add_column(style="dim")
@@ -57,36 +118,34 @@ def Overview(config: EvalConfig) -> Table:
         "env",
         f"{config.taskset.name}  ·  {config.harness.name} harness  ·  {config.harness.runtime.type} runtime",
     )
-    if config.harness.id != "default" and config.harness.runtime.type == "subprocess":
-        grid.add_row(
-            "warning",
-            Text(
-                "Runs on the local system; local files and settings may affect this "
-                "evaluation. Use subprocess only for debugging, or use docker or prime "
-                "for an isolated run.",
-                style="yellow",
-            ),
-        )
-    grid.add_row("model", f"{config.model}  ({sampling})")
+    model = f"{config.model}  ({sampling})" if sampling else config.model
+    grid.add_row("model", f"{model}  via {config.client.base_url}")
+    limits, timeouts = _aligned([_limits(config), _timeouts(config)])
+    grid.add_row("limits", limits)
+    grid.add_row("timeouts", timeouts)
     grid.add_row("output", str(output_path(config)))
     return grid
 
 
-def Progress(rollouts: list[Rollout], start: float) -> Table:
+def Progress(
+    rollouts: list[Rollout], start: float, page: tuple[int, int] | None = None
+) -> Table:
     done = [r.trace for r in rollouts if r.phase == Phase.DONE]  # fully scored
     # Headline reward = mean over non-errored; when any errored, `format_reward` appends the
     # global avg (errored count as 0) in parens. `err` is the share that errored.
     reward = format_reward(done)
     err = f"{sum(t.has_error for t in done) / len(done):.2f}" if done else "—"
     stats = (
-        f" {len(done)}/{len(rollouts)} · {format_time(time.time() - start)} · "
+        f"{len(done)}/{len(rollouts)} · {format_time(time.time() - start)} · "
         f"reward {reward} · err {err}"
     )
-    row = Table.grid()
-    row.add_column()
-    row.add_column()
+    if page is not None:  # rollouts overflow the screen — show which page is on screen
+        stats += f"  (page {page[0]}/{page[1]})"
+    row = Table.grid(expand=True, padding=(0, 1))
+    row.add_column(ratio=1)  # bar stretches to fill the width left of the stats
+    row.add_column(justify="right", no_wrap=True)
     row.add_row(
-        ProgressBar(total=len(rollouts) or 1, completed=len(done), width=32),
+        ProgressBar(total=len(rollouts) or 1, completed=len(done)),
         Text(stats),
     )
     return row
@@ -142,9 +201,14 @@ def Rows(groups: list[list[Rollout]], now: float, runtime_type: str) -> Table:
             if rollout.phase == Phase.DONE:  # fully scored — reward is final
                 state = "error" if t.has_error else "success"
                 result = t.error.type if t.has_error else f"reward={t.reward:.2f}"
-                stop = (
-                    "" if t.has_error else (t.stop_condition or "")
-                )  # error shown instead
+                if t.has_error:
+                    stop = ""  # error shown instead
+                else:
+                    stop = t.stop_condition or ""
+                    if (
+                        t.is_truncated
+                    ):  # flag a clipped rollout next to its stop condition
+                        stop = f"{stop} (truncated)".strip()
             else:
                 state, result, stop = rollout.phase, "", ""
             label = f"name={t.task.name[:32]}" if t.task.name else f"idx={t.task.idx}"
@@ -153,6 +217,7 @@ def Rows(groups: list[list[Rollout]], now: float, runtime_type: str) -> Table:
             )
             runtime = f"{runtime_type}({descriptor})" if descriptor else runtime_type
             turns = t.num_turns
+            nbranches = len(t.branches)
             start = t.timing.generation.start
             end = (
                 t.timing.scoring.end
@@ -165,6 +230,7 @@ def Rows(groups: list[list[Rollout]], now: float, runtime_type: str) -> Table:
                 t.id[:8],
                 runtime,
                 f"{turns} turn{'s' * (turns != 1)}",
+                f"{nbranches} branch{'es' * (nbranches != 1)}",
                 _tokens(t),
                 stop,  # stop condition (agent_completed / max_turns / harness_timeout), once done
             ]
@@ -179,10 +245,10 @@ def Rows(groups: list[list[Rollout]], now: float, runtime_type: str) -> Table:
         return grid
     # Pad each left section to its max width across rows (drop all-empty ones) so they align,
     # then join with " · ". Text sections left-justified, numeric right.
-    pad = (str.ljust, str.ljust, str.ljust, str.rjust, str.rjust, str.ljust)
-    widths = [max(len(left[i]) for _, _, left, _, _ in rows) for i in range(6)]
+    pad = (str.ljust, str.ljust, str.ljust, str.rjust, str.rjust, str.rjust, str.ljust)
+    widths = [max(len(left[i]) for _, _, left, _, _ in rows) for i in range(7)]
     for brace, state, left, result, elapsed in rows:
-        sections = [pad[i](left[i], widths[i]) for i in range(6) if widths[i]]
+        sections = [pad[i](left[i], widths[i]) for i in range(7) if widths[i]]
         grid.add_row(
             f"{brace} {_MARK[state]} " + " · ".join(sections),
             f"{result} ·" if result else "",  # trailing dot only when there's a result
@@ -192,12 +258,45 @@ def Rows(groups: list[list[Rollout]], now: float, runtime_type: str) -> Table:
     return grid
 
 
+def _paginate(
+    groups: list[list[Rollout]], rows_per_page: int, now: float
+) -> tuple[list[list[Rollout]], int, int]:
+    """Pack groups (a task's rollouts kept together) into pages of at most `rows_per_page` rows,
+    cycling to the next page every `_PAGE_SECONDS`. Returns (this page's groups, 0-based index,
+    page count) — a single page when everything already fits."""
+    if sum(len(g) for g in groups) <= rows_per_page:
+        return groups, 0, 1
+    pages: list[list[list[Rollout]]] = []
+    current: list[list[Rollout]] = []
+    used = 0
+    for group in groups:
+        if current and used + len(group) > rows_per_page:
+            pages.append(current)
+            current, used = [], 0
+        current.append(group)
+        used += len(group)
+    if current:
+        pages.append(current)
+    index = int(now / _PAGE_SECONDS) % len(pages)
+    return pages[index], index, len(pages)
+
+
 def _render(rollouts: list[Rollout], config: EvalConfig, start: float) -> Group:
+    now = time.time()
+    warning = _warning(config)
+    # `{warning}\n\n{overview}` — the caution sits at the very top, blank line, then the overview.
+    header = Group(warning, Text(""), Overview(config)) if warning else Overview(config)
+    # Measure the fixed top (header + progress + rule) so the rollout rows fill the rest of the
+    # screen; page through them on a timer when they'd overflow (rich would otherwise truncate).
+    top = Group(header, Progress(rollouts, start), Rule(style="dim"))
+    rows_per_page = max(1, _CONSOLE.size.height - len(_CONSOLE.render_lines(top)) - 1)
+    page_groups, index, count = _paginate(_groups(rollouts), rows_per_page, now)
+    progress = Progress(rollouts, start, page=(index + 1, count) if count > 1 else None)
     return Group(
-        Overview(config),
-        Progress(rollouts, start),
+        header,
+        progress,
         Rule(style="dim"),
-        Rows(_groups(rollouts), time.time(), config.harness.runtime.type),
+        Rows(page_groups, now, config.harness.runtime.type),
     )
 
 
diff --git a/verifiers/v1/cli/dashboard/validate.py b/verifiers/v1/cli/dashboard/validate.py
--- a/verifiers/v1/cli/dashboard/validate.py
+++ b/verifiers/v1/cli/dashboard/validate.py
@@ -17,7 +17,7 @@
 
 from verifiers.v1.cli.dashboard.base import live_view
 from verifiers.v1.configs.validate import ValidateConfig
-from verifiers.v1.utils import format_time
+from verifiers.v1.utils.format import format_time
 
 _STYLE = {
     "pending": "dim",
diff --git a/verifiers/v1/cli/eval/__init__.py b/verifiers/v1/cli/eval/__init__.py
new file mode 100644
--- /dev/null
+++ b/verifiers/v1/cli/eval/__init__.py
@@ -0,0 +1 @@
+"""The eval command: `uv run eval` — the entry (`main`), the rollout `runner`, and `resume`."""
diff --git a/verifiers/v1/cli/eval.py b/verifiers/v1/cli/eval/main.py
rename from verifiers/v1/cli/eval.py
rename to verifiers/v1/cli/eval/main.py
--- a/verifiers/v1/cli/eval.py
+++ b/verifiers/v1/cli/eval/main.py
@@ -18,16 +18,16 @@
 from pydantic_config import cli
 
 import verifiers.v1 as vf
-from verifiers.v1.cli.log import setup_logging
+from verifiers.v1.utils.logging import setup_logging
 from verifiers.v1.cli.output import output_path, write_config
 from verifiers.v1.cli.resolve import (
     extract_id,
     narrow_config,
     references_config_file,
     with_positional_taskset,
 )
-from verifiers.v1.cli.resume import load_resume_config, split_resume
-from verifiers.v1.cli.runner import run_eval
+from verifiers.v1.cli.eval.resume import load_resume_config, split_resume
+from verifiers.v1.cli.eval.runner import run_eval
 from verifiers.v1.configs.eval import EvalConfig
 
 logger = logging.getLogger(__name__)
@@ -101,7 +101,7 @@ def main(argv: list[str] | None = None) -> None:
         env = vf.Environment(config)
         traces = asyncio.run(run_eval(env, config))
     else:  # drive rollouts through the env server's worker pool
-        from verifiers.v1.cli.runner import run_eval_server
+        from verifiers.v1.cli.eval.runner import run_eval_server
 
         traces = asyncio.run(run_eval_server(config))
     if not rich:  # --rich is the whole output; otherwise dump each trace as JSON
diff --git a/verifiers/v1/cli/resume.py b/verifiers/v1/cli/eval/resume.py
rename from verifiers/v1/cli/resume.py
rename to verifiers/v1/cli/eval/resume.py
--- a/verifiers/v1/cli/resume.py
+++ b/verifiers/v1/cli/eval/resume.py

diff --git a/verifiers/v1/cli/runner.py b/verifiers/v1/cli/eval/runner.py
rename from verifiers/v1/cli/runner.py
rename to verifiers/v1/cli/eval/runner.py
--- a/verifiers/v1/cli/runner.py
+++ b/verifiers/v1/cli/eval/runner.py
@@ -8,7 +8,7 @@
 
 from verifiers.v1.clients import RolloutContext, resolve_client
 from verifiers.v1.configs.eval import EvalConfig
-from verifiers.v1.cli import resume
+from verifiers.v1.cli.eval import resume
 from verifiers.v1.cli.dashboard import dashboard
 from verifiers.v1.cli.output import append_trace, output_path, save_config
 from verifiers.v1.decorators import discover_decorated
@@ -103,7 +103,7 @@ async def run_eval_server(config: EvalConfig) -> list[Trace]:
     import multiprocessing as mp
     from functools import partial
 
-    from verifiers.v1.cli.log import setup_logging
+    from verifiers.v1.utils.logging import setup_logging
     from verifiers.v1.env import pool_serve_kwargs
     from verifiers.v1.serve import EnvClient, env_config_data, serve_env
 
diff --git a/verifiers/v1/cli/init.py b/verifiers/v1/cli/init.py
--- a/verifiers/v1/cli/init.py
+++ b/verifiers/v1/cli/init.py
@@ -12,37 +12,17 @@
 import sys
 from pathlib import Path
 
-from pydantic import AliasChoices, Field
-from pydantic_config import BaseConfig, cli
+from pydantic_config import cli
+
+from verifiers.v1.configs.init import InitConfig
 
 USAGE = (
-    "usage: uv run init <name> [--path ./environments] [--add-tool] [--add-user] "
-    "[--add-harness] [--v0]\n"
+    "usage: uv run init <name> [--path ./environments] [-T/--add-tool] [-U/--add-user] "
+    "[-H/--add-harness] [--v0]\n"
     "       scaffold a new v1 environment package (use --v0 for a legacy v0 environment)"
 )
 
 
-class InitConfig(BaseConfig):
-    """What to scaffold. The `name` is the new environment id (a leading bare token, e.g.
-    `init my-task-v1`); the package dir, ids, and class names are derived from it. The
-    `--add-*` flags add optional pieces (tool server, user simulator, custom harness)."""
-
-    name: str = ""
-    """The new environment id, e.g. `my-task-v1` (positional: `init my-task-v1`)."""
-    path: str = Field("./environments", validation_alias=AliasChoices("path", "p"))
-    """Parent directory the package is created in (default `./environments`)."""
-    add_tool: bool = False
-    """Also scaffold a `vf.Toolset` tool server (`servers/tool.py`), wired into the taskset."""
-    add_user: bool = False
-    """Also scaffold a `vf.User` simulator (`servers/user.py`), wired into the taskset."""
-    add_harness: bool = False
-    """Also scaffold a custom `vf.Harness` (`harness.py`), selectable via `--harness.id <name>`."""
-    v0: bool = False
-    """Scaffold a legacy v0 environment (a `load_environment` package) instead of a v1 taskset."""
-    force: bool = False
-    """Overwrite files that already exist (default: keep them, scaffold only what's missing)."""
-
-
 def _names(name: str) -> tuple[str, str, str, str]:
     """`(dash, pkg, stem, prefix)` derived from a raw name: the hyphenated id, the importable
     package (underscores), the `_v1`-less stem (for tool prefixes), and the CamelCase class
@@ -103,6 +83,9 @@ def _taskset_py(pkg: str, prefix: str, *, add_tool: bool, add_user: bool) -> str
     local_imports: list[str] = []
     config_extra = ""
     methods: list[str] = []
+    # a user simulator carries per-rollout state and a stop condition, so the taskset is typed with
+    # its `State` subclass; without one it stays on the default `State`.
+    state_param = ""
     if add_tool:
         local_imports.append(f"from {pkg}.servers.tool import {prefix}Toolset")
         config_extra += "\n    tools: vf.ToolsetConfig = vf.ToolsetConfig()"
@@ -111,22 +94,24 @@ def _taskset_py(pkg: str, prefix: str, *, add_tool: bool, add_user: bool) -> str
             f"        return [{prefix}Toolset(self.config.tools)]"
         )
     if add_user:
-        local_imports.append(f"from {pkg}.servers.user import {prefix}User")
+        local_imports.append(
+            f"from {pkg}.servers.user import {prefix}State, {prefix}User"
+        )
         config_extra += "\n    user: vf.UserConfig = vf.UserConfig()"
+        state_param = f", {prefix}State"
         methods.append(
             f"    def user(self, task: {prefix}Task) -> vf.User:\n"
             f"        return {prefix}User(self.config.user)"
         )
+        methods.append(
+            "    @vf.stop\n"
+            "    async def user_done(self, trace: vf.Trace) -> bool:\n"
+            "        return trace.state.done"
+        )
     if local_imports:
         imports += "\n\n" + "\n".join(local_imports)
     methods_block = "".join(f"\n{m}\n" for m in methods)
     return f'''\
-"""{pkg.replace("_", "-")} — <one-line description of the task>.
-
-A starter v1 taskset: implement `load_tasks` (your tasks + prompts) and the `@reward` (how a
-rollout is scored). See `environments/*_v1` for complete examples.
-"""
-
 {imports}
 
 
@@ -139,11 +124,11 @@ class {prefix}Config(vf.TasksetConfig):
     """How many tasks to build."""{config_extra}
 
 
-class {prefix}Taskset(vf.Taskset[{prefix}Task, {prefix}Config]):
+class {prefix}Taskset(vf.Taskset[{prefix}Task, {prefix}Config{state_param}]):
     def load_tasks(self) -> list[{prefix}Task]:
         raise NotImplementedError(
             "Return this taskset's tasks, e.g. "
-            "[{prefix}Task(idx=i, instruction=...) for i in range(self.config.num_tasks)]."
+            "[{prefix}Task(idx=i, prompt=...) for i in range(self.config.num_tasks)]."
         )
 {methods_block}
     @vf.reward(weight=1.0)
@@ -154,12 +139,6 @@ async def reward(self, task: {prefix}Task, trace: vf.Trace) -> float:
 
 def _tool_py(stem: str, prefix: str) -> str:
     return f'''\
-"""A tool server for {stem.replace("_", "-")} — a vf-native `Toolset` (no FastMCP boilerplate).
-
-The framework launches it and surfaces each `@vf.tool` method to the model as `{stem}_<method>`.
-Replace `echo` with your task's tools.
-"""
-
 import verifiers.v1 as vf
 
 
@@ -177,44 +156,30 @@ def echo(self, text: str) -> str:
 '''
 
 
-def _user_py(stem: str, prefix: str) -> str:
-    return f'''\
-"""A user simulator for {stem.replace("_", "-")} — a vf-native `User` driving the conversation.
-
-The framework calls `respond` after each model turn for the next user message(s) + a done flag.
-If a task carries no prompt (`instruction=None`), `respond("")` is called first to open the
-conversation. Replace the logic with your simulated user.
-"""
-
+def _user_py(prefix: str) -> str:
+    return f"""\
 import verifiers.v1 as vf
 
 
-class {prefix}User(vf.User[vf.UserConfig]):
-    async def setup_task(self, task) -> None:
-        self.replied = False
+class {prefix}State(vf.State):
+    done: bool = False
+
 
-    async def respond(self, message: str) -> tuple[vf.Messages, bool]:
-        if self.replied:
-            return [], True
-        self.replied = True
-        return [{{"role": "user", "content": "Thanks - anything else?"}}], False
+class {prefix}User(vf.User[vf.UserConfig, {prefix}State]):
+    async def respond(self, message: str) -> vf.Messages:
+        if self.state.done:
+            return []
+        self.state.done = True
+        return [vf.UserMessage(content="Thanks - anything else?")]
 
 
 if __name__ == "__main__":
     {prefix}User.run()
-'''
+"""
 
 
 def _harness_py(dash: str, prefix: str) -> str:
     return f'''\
-"""A custom harness for {dash} — replace `launch` with how your agent runs.
-
-A harness drives the rollout: it runs a program in `runtime` whose model calls hit the
-interception server at `endpoint` (bearer token `secret`); `mcp_urls` are the task's tool
-servers to wire in. See verifiers' built-in `default` harness for a chat-loop reference. This
-package exports it alongside the taskset, so select it with `--harness.id {dash}`.
-"""
-
 import verifiers.v1 as vf
 
 
@@ -288,6 +253,10 @@ def scaffold(config: InitConfig) -> Path:
     dash, pkg, stem, prefix = _names(config.name)
     env_dir = Path(config.path) / pkg
     pkg_dir = env_dir / pkg
+    if env_dir.exists() and not config.force:
+        raise SystemExit(
+            f"error: {env_dir} already exists - refusing to overwrite (pass --force to overwrite)"
+        )
     print(f"scaffolding v1 environment {dash!r} in {env_dir}")
 
     _write(env_dir / "pyproject.toml", _pyproject(dash, pkg), config.force)
@@ -317,7 +286,7 @@ def scaffold(config: InitConfig) -> Path:
     if config.add_tool:
         _write(pkg_dir / "servers" / "tool.py", _tool_py(stem, prefix), config.force)
     if config.add_user:
-        _write(pkg_dir / "servers" / "user.py", _user_py(stem, prefix), config.force)
+        _write(pkg_dir / "servers" / "user.py", _user_py(prefix), config.force)
 
     print(f"\ndone. next:\n  uv pip install -e {env_dir}\n  uv run eval {dash} -n 3")
     return env_dir
diff --git a/verifiers/v1/cli/serve.py b/verifiers/v1/cli/serve.py
--- a/verifiers/v1/cli/serve.py
+++ b/verifiers/v1/cli/serve.py
@@ -11,7 +11,7 @@
 
 from pydantic_config import cli
 
-from verifiers.v1.cli.log import setup_logging
+from verifiers.v1.utils.logging import setup_logging
 from verifiers.v1.cli.resolve import (
     extract_id,
     narrow_config,
diff --git a/verifiers/v1/cli/validate.py b/verifiers/v1/cli/validate.py
--- a/verifiers/v1/cli/validate.py
+++ b/verifiers/v1/cli/validate.py
@@ -22,7 +22,7 @@
 
 import verifiers.v1 as vf
 from verifiers.v1.cli.dashboard import TaskProgress, validate_dashboard
-from verifiers.v1.cli.log import setup_logging
+from verifiers.v1.utils.logging import setup_logging
 from verifiers.v1.cli.resolve import (
     extract_id,
     references_config_file,
@@ -79,7 +79,7 @@ async def _validate_task(taskset: Taskset, task, config: ValidateConfig) -> dict
     if config.retries.runtime.max_retries > 0:
         runtime = RetryingRuntime(runtime, config.retries.runtime.max_retries)
     setup_timeout = (
-        config.setup_timeout if config.setup_timeout is not None else task.setup_timeout
+        config.setup_timeout if config.setup_timeout is not None else task.timeout.setup
     )
     valid, exc = False, None
     try:
diff --git a/verifiers/v1/clients/client.py b/verifiers/v1/clients/client.py
--- a/verifiers/v1/clients/client.py
+++ b/verifiers/v1/clients/client.py
@@ -20,7 +20,7 @@
 from verifiers.v1.dialects import Dialect
 from verifiers.v1.errors import ModelError, OverlongPromptError
 from verifiers.v1.graph import PendingTurn
-from verifiers.v1.types import Response, SamplingConfig
+from verifiers.v1.types import Response, Sampling, SamplingConfig
 
 logger = logging.getLogger(__name__)
 
@@ -104,11 +104,14 @@ def __init__(self, inner: Client, max_retries: int) -> None:
         )
 
     def _log_retry(self, state: RetryCallState) -> None:
+        # before_sleep fires after a failed attempt, before the imminent retry — so
+        # attempt_number is the retry index (1 on the first retry); count out of max_retries.
+        exc = state.outcome.exception()
         logger.warning(
-            "retrying model call (attempt %d/%d) after error: %s",
+            "retrying model call (retry %d/%d) after error: %s",
             state.attempt_number,
-            self.max_retries + 1,
-            state.outcome.exception(),
+            self.max_retries,
+            f"{type(exc).__name__}: {exc}",  # name too — some errors stringify empty
         )
 
     async def get_response(
@@ -165,6 +168,6 @@ class RolloutContext:
     """The collaborators a single rollout needs (client + model + sampling), bundled
     so harnesses hold no rollout state. Built by the Environment."""
 
-    client: Client
     model: str
-    sampling: SamplingConfig
+    client: Client
+    sampling: Sampling
diff --git a/verifiers/v1/clients/eval.py b/verifiers/v1/clients/eval.py
--- a/verifiers/v1/clients/eval.py
+++ b/verifiers/v1/clients/eval.py
@@ -135,7 +135,11 @@ async def _request(
             try:
                 response.raise_for_status()
             except httpx.HTTPStatusError as e:
-                raise model_error(e.response.text) from e
+                # include the status — an empty/HTML body (e.g. a 404 from a base_url missing
+                # `/v1`) would otherwise make an information-free ModelError
+                raise model_error(
+                    f"upstream {e.response.status_code}: {e.response.text}"
+                ) from e
             return response
         if response.status_code < 400:
             return response
diff --git a/verifiers/v1/configs/__init__.py b/verifiers/v1/configs/__init__.py
--- a/verifiers/v1/configs/__init__.py
+++ b/verifiers/v1/configs/__init__.py
@@ -1,6 +1,8 @@
 """Config schemas for the v1 entrypoints — the objects the CLIs parse."""
 
 from verifiers.v1.configs.eval import EvalConfig
+from verifiers.v1.configs.init import InitConfig
 from verifiers.v1.configs.serve import ServeConfig
+from verifiers.v1.configs.validate import ValidateConfig
 
-__all__ = ["EvalConfig", "ServeConfig"]
+__all__ = ["EvalConfig", "InitConfig", "ServeConfig", "ValidateConfig"]
diff --git a/verifiers/v1/configs/init.py b/verifiers/v1/configs/init.py
new file mode 100644
--- /dev/null
+++ b/verifiers/v1/configs/init.py
@@ -0,0 +1,30 @@
+"""The `InitConfig`: the config the `init` CLI parses.
+
+`init` scaffolds a new environment package (see `verifiers.v1.cli.init`); this config is just
+the "what to scaffold" knobs — the new env name, where to create it, and which optional pieces
+(tool server, user simulator, custom harness) to include.
+"""
+
+from pydantic import AliasChoices, Field
+from pydantic_config import BaseConfig
+
+
+class InitConfig(BaseConfig):
+    """What to scaffold. The `name` is the new environment id (a leading bare token, e.g.
+    `init my-task-v1`); the package dir, ids, and class names are derived from it. The
+    `--add-*` flags add optional pieces (tool server, user simulator, custom harness)."""
+
+    name: str = ""
+    """The new environment id, e.g. `my-task-v1` (positional: `init my-task-v1`)."""
+    path: str = Field("./environments", validation_alias=AliasChoices("path", "p"))
+    """Parent directory the package is created in (default `./environments`)."""
+    add_tool: bool = Field(False, validation_alias=AliasChoices("add_tool", "T"))
+    """Also scaffold a `vf.Toolset` tool server (`servers/tool.py`), wired into the taskset (`-T`)."""
+    add_user: bool = Field(False, validation_alias=AliasChoices("add_user", "U"))
+    """Also scaffold a `vf.User` simulator (`servers/user.py`), wired into the taskset (`-U`)."""
+    add_harness: bool = Field(False, validation_alias=AliasChoices("add_harness", "H"))
+    """Also scaffold a custom `vf.Harness` (`harness.py`), selectable via `--harness.id <name>` (`-H`)."""
+    v0: bool = False
+    """Scaffold a legacy v0 environment (a `load_environment` package) instead of a v1 taskset."""
+    force: bool = False
+    """Overwrite an existing environment package (default: refuse if it already exists)."""
diff --git a/verifiers/v1/dialects/chat.py b/verifiers/v1/dialects/chat.py
--- a/verifiers/v1/dialects/chat.py
+++ b/verifiers/v1/dialects/chat.py
@@ -101,7 +101,7 @@ def parse_tools(raw: list[dict] | None) -> list[Tool] | None:
 
 # --- vf -> chat wire ----------------------------------------------------------
 # `message_to_wire` (chat-only): used by `extend` (user-sim turn injection), the default harness
-# (a Messages instruction), and the train client (its generate request). The proxy never
+# (a Messages prompt), and the train client (its generate request). The proxy never
 # serializes — it relays the provider's raw bytes.
 
 
diff --git a/verifiers/v1/env.py b/verifiers/v1/env.py
--- a/verifiers/v1/env.py
+++ b/verifiers/v1/env.py
@@ -22,7 +22,7 @@
 from verifiers.v1.clients import RolloutContext
 from verifiers.v1.decorators import discover_decorated
 from verifiers.v1.episode import Episode
-from verifiers.v1.ids import EnvId
+from verifiers.v1.types import EnvId
 from verifiers.v1.interception import InterceptionPool, RolloutLimits
 from verifiers.v1.retries import RetryConfig
 from verifiers.v1.rollout import Rollout
@@ -300,22 +300,22 @@ def episode(self, task: Task, ctx: RolloutContext, n: int = 1) -> Episode:
             )
         runtime_config = self.runtime_for(task)
         setup_timeout = (
-            self.setup_timeout if self.setup_timeout is not None else task.setup_timeout
+            self.setup_timeout if self.setup_timeout is not None else task.timeout.setup
         )
         harness_timeout = (
             self.harness_timeout
             if self.harness_timeout is not None
-            else task.harness_timeout
+            else task.timeout.harness
         )
         finalize_timeout = (
             self.finalize_timeout
             if self.finalize_timeout is not None
-            else task.finalize_timeout
+            else task.timeout.finalize
         )
         scoring_timeout = (
             self.scoring_timeout
             if self.scoring_timeout is not None
-            else task.scoring_timeout
+            else task.timeout.scoring
         )
         retries = self.config.retries
         rollouts = [
diff --git a/verifiers/v1/episode.py b/verifiers/v1/episode.py
--- a/verifiers/v1/episode.py
+++ b/verifiers/v1/episode.py
@@ -27,7 +27,7 @@
 from verifiers.v1.rollout import Phase, Rollout
 from verifiers.v1.taskset import Taskset
 from verifiers.v1.trace import Trace
-from verifiers.v1.utils import trim_memory_periodically
+from verifiers.v1.utils.memory import trim_memory_periodically
 
 if TYPE_CHECKING:
     from verifiers.v1.retries import RolloutRetryConfig
diff --git a/verifiers/v1/errors.py b/verifiers/v1/errors.py
--- a/verifiers/v1/errors.py
+++ b/verifiers/v1/errors.py
@@ -49,7 +49,8 @@ def model_error(e: OpenAIError | str) -> ModelError:
     """Map a provider failure to our error type, distinguishing an overlong prompt from any
     other model-call failure (auth, rate limit, a genuine bad request, ...). Accepts either an
     SDK error (the renderer) or the provider's raw error body (the httpx proxy)."""
-    text = str(e).casefold()
-    if any(phrase in text for phrase in _CONTEXT_LENGTH_PHRASES):
-        return OverlongPromptError(str(e))
-    return ModelError(str(e))
+    # Some SDK errors stringify empty; fall back to the type so the message is never blank.
+    text = str(e) or (type(e).__name__ if isinstance(e, BaseException) else "")
+    if any(phrase in text.casefold() for phrase in _CONTEXT_LENGTH_PHRASES):
+        return OverlongPromptError(text)
+    return ModelError(text)
diff --git a/verifiers/v1/harness.py b/verifiers/v1/harness.py
--- a/verifiers/v1/harness.py
+++ b/verifiers/v1/harness.py
@@ -19,7 +19,7 @@
 from verifiers.v1.clients import RolloutContext
 from verifiers.v1.decorators import discover_decorated, invoke
 from verifiers.v1.errors import ProgramError
-from verifiers.v1.ids import EnvId, env_name
+from verifiers.v1.utils.install import env_name
 from verifiers.v1.runtimes import (
     ProgramResult,
     Runtime,
@@ -28,7 +28,7 @@
 )
 from verifiers.v1.task import Task
 from verifiers.v1.trace import Trace
-from verifiers.v1.types import Messages
+from verifiers.v1.types import EnvId, Messages
 
 logger = logging.getLogger(__name__)
 
@@ -72,45 +72,45 @@ class Harness(ABC, Generic[ConfigT]):
     """Expose a task's MCP tool servers to the model; set False for harnesses without an MCP client."""
     SUPPORTS_USER_SIM: ClassVar[bool] = False
     """Drive a task's user simulator (multi-turn user injection); opt in per harness."""
-    SUPPORTS_MESSAGE_INSTRUCTION: ClassVar[bool] = False
-    """Accept a Messages-list task.instruction (e.g. an image-bearing prompt); opt in per harness."""
+    SUPPORTS_MESSAGE_PROMPT: ClassVar[bool] = False
+    """Accept a Messages-list task.prompt (e.g. an image-bearing prompt); opt in per harness."""
 
     def __init__(self, config: ConfigT) -> None:
         self.config = config
 
     def resolve_prompt(self, task: Task) -> tuple[str | None, str | Messages | None]:
-        """Resolve `(system_prompt, user_instruction)` for this harness. If the harness
+        """Resolve `(system_prompt, prompt)` for this harness. If the harness
         appends the system prompt natively, returns it separately; otherwise folds it into
-        the user instruction (warning that it isn't sent as a system message). A `Messages`
-        instruction (e.g. an image-bearing prompt) is only allowed for harnesses that set
-        `SUPPORTS_MESSAGE_INSTRUCTION`. A `None` instruction means the task has no prompt —
+        the user prompt (warning that it isn't sent as a system message). A `Messages`
+        prompt (e.g. an image-bearing prompt) is only allowed for harnesses that set
+        `SUPPORTS_MESSAGE_PROMPT`. A `None` prompt means the task has no prompt —
         the user simulator opens the conversation (see `Taskset.user`); the harness emits no
         opening user message."""
-        instruction = task.instruction
+        prompt = task.prompt
         if (
-            instruction is not None
-            and not isinstance(instruction, str)
-            and not self.SUPPORTS_MESSAGE_INSTRUCTION
+            prompt is not None
+            and not isinstance(prompt, str)
+            and not self.SUPPORTS_MESSAGE_PROMPT
         ):
             raise ValueError(
-                f"Harness {self.config.id!r} does not support a Messages instruction; "
-                "task.instruction must be a string or None."
+                f"Harness {self.config.id!r} does not support a Messages prompt; "
+                "task.prompt must be a string or None."
             )
         system = task.system_prompt
         if system is None or self.APPENDS_SYSTEM_PROMPT:
-            return system if self.APPENDS_SYSTEM_PROMPT else None, instruction
-        if not isinstance(instruction, str):
+            return system if self.APPENDS_SYSTEM_PROMPT else None, prompt
+        if not isinstance(prompt, str):
             raise ValueError(
                 f"Harness {self.config.id!r} cannot fold a system prompt into a "
-                f"{'Messages' if instruction is not None else 'None'} instruction; set "
+                f"{'Messages' if prompt is not None else 'None'} prompt; set "
                 "APPENDS_SYSTEM_PROMPT to emit it as a system message."
             )
         logger.warning(
             "Harness %r does not support a separate system prompt; prepending "
-            "task.system_prompt to the user instruction.",
+            "task.system_prompt to the user prompt.",
             self.config.id,
         )
-        return None, f"{system}\n\n{instruction}"
+        return None, f"{system}\n\n{prompt}"
 
     async def run(
         self,
diff --git a/verifiers/v1/ids.py b/verifiers/v1/ids.py
deleted file mode 100644
--- a/verifiers/v1/ids.py
+++ /dev/null
@@ -1,68 +0,0 @@
-"""The plugin / environment id, and on-demand installation from the Environments Hub.
-
-A taskset, harness, or v0 environment is selected by an id in one of three forms:
-
-  - ``name``              a local package (already importable / pip-installed)
-  - ``org/name``          the env hub, latest version
-  - ``org/name@version``  the env hub, a pinned version
-
-`EnvId` is the type of every id field: a plain ``str`` validated against those forms (an
-`Annotated[str, ...]`, not a subclass), so it flows unchanged through configs and the
-wire. `env_name` derives the package name (org / version stripped) for logging, display,
-and output paths; `ensure_installed` makes a hub id importable on demand, reusing the same
-install path as `prime env install`.
-"""
-
-import logging
-from typing import Annotated
-
-from pydantic import AfterValidator
-
-from verifiers.utils.install_utils import (
-    check_hub_env_installed,
-    install_from_hub,
-    is_hub_env,
-    normalize_package_name,
-    parse_env_id,
-)
-
-logger = logging.getLogger(__name__)
-
-
-def _validate_env_id(env_id: str) -> str:
-    """Validate the id's shape — a hub id must be a well-formed ``org/name[@version]``; a
-    local id is any module name. Returns it unchanged (the value stays a plain ``str``)."""
-    if is_hub_env(env_id):
-        parse_env_id(env_id)  # raises ValueError on a malformed org/name[@version]
-    return env_id
-
-
-EnvId = Annotated[str, AfterValidator(_validate_env_id)]
-"""A taskset / harness / environment id — ``name``, ``org/name``, or ``org/name@version``.
-A plain validated ``str``; parse it with `env_name` / `env_module`."""
-
-
-def env_name(env_id: str) -> str:
-    """The package name — the id with org and version stripped (``org/gsm8k@1.0`` ->
-    ``gsm8k``). Used for logging, display, and output paths."""
-    return parse_env_id(env_id)[1] if is_hub_env(env_id) else env_id
-
-
-def env_module(env_id: str) -> str:
-    """The importable module name — `env_name` normalized (hyphens -> underscores)."""
-    return normalize_package_name(env_name(env_id))
-
-
-def ensure_installed(env_id: str) -> str:
-    """Make `env_id` importable and return its module name.
-
-    For a hub id (``org/name[@version]``) that isn't installed, install it from the
-    Environments Hub — latest, or the pinned version — the same path `prime env install`
-    uses. A local id is assumed already importable."""
-    if is_hub_env(env_id) and not check_hub_env_installed(env_id):
-        logger.info("installing %s from the environments hub", env_id)
-        if not install_from_hub(env_id):
-            raise ModuleNotFoundError(
-                f"could not install {env_id!r} from the environments hub"
-            )
-    return env_module(env_id)
diff --git a/verifiers/v1/interception/server.py b/verifiers/v1/interception/server.py
--- a/verifiers/v1/interception/server.py
+++ b/verifiers/v1/interception/server.py
@@ -14,7 +14,7 @@
 When a rollout sets a user simulator (see `verifiers.v1.mcp.user`), the session also drives it:
 after each model turn it injects the simulator's reply as a user turn and re-prompts the
 model, so a multi-turn exchange plays out within one program request, transparently to the
-harness. When the task carries no prompt (`task.instruction is None`), the simulator also
+harness. When the task carries no prompt (`task.prompt is None`), the simulator also
 opens the conversation: its first turn is seeded before the model is ever called. Tools are
 handled out-of-band (run by the harness).
 """
@@ -216,7 +216,7 @@ async def handle_request(
         # post-turn loop below then drives the remaining turns as usual.
         if (
             session.user is not None
-            and session.trace.task.instruction is None
+            and session.trace.task.prompt is None
             and session.trace.num_turns == 0
         ):
             if session.opening is None:
@@ -269,7 +269,12 @@ async def handle_request(
                     )
                 return web.json_response(completion)
             except Exception as e:  # surface to the program as an API error
-                logger.warning("model call failed: id=%s %s", session.trace.id, e)
+                logger.warning(
+                    "model call failed: id=%s %s: %s",
+                    session.trace.id,
+                    type(e).__name__,
+                    e,
+                )
                 return web.json_response(dialect.error_body(str(e)), status=502)
             # `Response.raw` is the wire response handed to the program 1:1 — the provider's
             # verbatim bytes (proxy) or the client's serialized completion (renderer).
diff --git a/verifiers/v1/legacy.py b/verifiers/v1/legacy.py
--- a/verifiers/v1/legacy.py
+++ b/verifiers/v1/legacy.py
@@ -185,7 +185,7 @@ def rollout_output_to_trace(out: dict, task_idx: int) -> Trace:
     """Map a v0 ``RolloutOutput`` into a v1 ``Trace``, preserving the meta a native v1
     trace carries: per-turn prompt messages, the response message (content / reasoning /
     tool calls), ``finish_reason`` and ``usage``, the token ids/logprobs, and the task's
-    system prompt / instruction / answer. ``is_truncated`` is a computed v1 field derived
+    system prompt / prompt / answer. ``is_truncated`` is a computed v1 field derived
     from the final turn's ``finish_reason`` and the stop condition."""
     model = str(out.get("model") or "")
 
@@ -224,7 +224,7 @@ def rollout_output_to_trace(out: dict, task_idx: int) -> Trace:
 
 def _to_wire_task(task_idx: int, prompt: Any, answer: Any) -> WireTask:
     """Carry the v0 prompt's meta onto the v1 task: the system message becomes
-    ``system_prompt``, the user message(s) become ``instruction``, and the reference
+    ``system_prompt``, the user message(s) become ``prompt``, and the reference
     ``answer`` rides along as a taskset-extra field (``WireTask`` allows extras)."""
     system_prompt: str | None = None
     user_texts: list[str] = []
@@ -239,7 +239,7 @@ def _to_wire_task(task_idx: int, prompt: Any, answer: Any) -> WireTask:
     extra = {"answer": answer} if answer else {}
     return WireTask(
         idx=task_idx,
-        instruction="\n\n".join(user_texts),
+        prompt="\n\n".join(user_texts),
         system_prompt=system_prompt,
         **extra,
     )
@@ -263,7 +263,7 @@ def __init__(
         extra_env_kwargs: dict | None = None,
     ) -> None:
         from verifiers import load_environment
-        from verifiers.v1.ids import ensure_installed, env_name
+        from verifiers.v1.utils.install import ensure_installed, env_name
 
         self.address = address
         # Install from the env hub on demand for an `org/name[@version]` id, then load the
@@ -352,7 +352,7 @@ async def _run_v0(
     async def _run_rollout(self, req: RunRolloutRequest) -> RunRolloutResponse:
         out = await self._run_v0(req.task_idx, req.client, req.model, req.sampling)
         return RunRolloutResponse(
-            trace=rollout_output_to_trace(out, req.task_idx).to_wire()
+            trace=rollout_output_to_trace(out, req.task_idx).model_dump()
         )
 
     async def _run_group(self, req: RunGroupRequest) -> RunGroupResponse:
@@ -365,7 +365,9 @@ async def _run_group(self, req: RunGroupRequest) -> RunGroupResponse:
             sampling_args=req.sampling.model_dump(exclude_none=True),
             state_columns=["trajectory"],
         )
-        traces = [rollout_output_to_trace(out, req.task_idx).to_wire() for out in outs]
+        traces = [
+            rollout_output_to_trace(out, req.task_idx).model_dump() for out in outs
+        ]
         return RunGroupResponse(traces=traces)
 
 
@@ -392,7 +394,7 @@ def _eval_client(client_config: ClientConfig, model: str):
 def _legacy_output_dir(config) -> Path:
     """The legacy run's output dir, mirroring the native `output_path` shape but keyed by
     the v0 env id (`outputs/<id>--<model>--legacy/<uuid>`); honors `--output-dir`."""
-    from verifiers.v1.ids import env_name
+    from verifiers.v1.utils.install import env_name
 
     if config.output_dir is not None:
         return config.output_dir
@@ -416,7 +418,7 @@ async def run_legacy_eval(config) -> list[Trace]:
     from verifiers import load_environment
 
     from verifiers.v1.cli.output import append_trace, save_config
-    from verifiers.v1.ids import ensure_installed
+    from verifiers.v1.utils.install import ensure_installed
 
     # Install from the env hub on demand for an `org/name[@version]` id (a local id is
     # already importable), then load by module name.
diff --git a/verifiers/v1/loaders.py b/verifiers/v1/loaders.py
--- a/verifiers/v1/loaders.py
+++ b/verifiers/v1/loaders.py
@@ -23,7 +23,7 @@
 from pydantic_config import BaseConfig
 
 from verifiers.v1.harness import Harness, HarnessConfig
-from verifiers.v1.ids import ensure_installed
+from verifiers.v1.utils.install import ensure_installed
 from verifiers.v1.task import Task
 from verifiers.v1.taskset import Taskset, TasksetConfig
 
diff --git a/verifiers/v1/mcp/launch.py b/verifiers/v1/mcp/launch.py
--- a/verifiers/v1/mcp/launch.py
+++ b/verifiers/v1/mcp/launch.py
@@ -173,10 +173,15 @@ async def log_tail(runtime: Runtime, log: str, limit: int = 2000) -> str:
 
 async def _read_back_port(runtime: Runtime, path: str) -> int:
     """The port the server bound and wrote to `path` in its runtime. The server writes it the moment
-    it binds (before setup/serving), so this resolves quickly; poll because it's a separate process."""
+    it binds (before setup/serving), so this resolves quickly; poll because it's a separate process.
+
+    Read through the un-retrying inner runtime: a missing file just means the server hasn't bound
+    yet, so a per-call retry wrapper would spam `retrying runtime.read` 3x on every poll — this loop
+    is itself the retry."""
+    reader = getattr(runtime, "inner", runtime)
     for _ in range(180):
         with contextlib.suppress(Exception):
-            data = (await runtime.read(path)).decode().strip()
+            data = (await reader.read(path)).decode().strip()
             if data.isdigit():
                 return int(data)
         await asyncio.sleep(1)
diff --git a/verifiers/v1/mcp/toolset.py b/verifiers/v1/mcp/toolset.py
--- a/verifiers/v1/mcp/toolset.py
+++ b/verifiers/v1/mcp/toolset.py
@@ -37,7 +37,7 @@ class ToolsetConfig(BaseConfig):
     See the placement/isolation section of `verifiers/v1/GUIDE.md` for the trade-offs of each.
     Subclass to add the server's own knobs (the data its `@tool` methods read). The server name is
     the class's `TOOL_PREFIX` ClassVar, not a field here — it's an identity (the model sees
-    `<prefix>_<tool>`, baked into the taskset's instruction), not a tunable knob."""
+    `<prefix>_<tool>`, baked into the taskset's prompt), not a tunable knob."""
 
     colocated: bool = False
     """Run the server inside the harness's runtime (reached in-sandbox, no tunnel). Off by
diff --git a/verifiers/v1/mcp/user.py b/verifiers/v1/mcp/user.py
--- a/verifiers/v1/mcp/user.py
+++ b/verifiers/v1/mcp/user.py
@@ -5,7 +5,7 @@
 to the model: the framework drives it. After each model turn the interception server calls `respond`
 with the model's last message, appends the simulated user message(s), and re-prompts — so a
 multi-turn game plays out as alternating assistant/user turns in the trace, the harness none the
-wiser. When the task carries no prompt (`task.instruction is None`), the simulator also opens the
+wiser. When the task carries no prompt (`task.prompt is None`), the simulator also opens the
 conversation: the interception server calls `respond("")` once before the first model turn and seeds
 its reply as the initial user message. The host side that drives it lives in `launch` (`serve_user` /
 `connect_user`).
@@ -72,7 +72,7 @@ async def deal_closed(self, trace) -> bool:
 
     async def respond(self, message: str) -> Messages:
         """The model's last assistant text in → the next user message(s) out. Called once with an
-        empty `message` to open the conversation when the task has no prompt (`task.instruction is
+        empty `message` to open the conversation when the task has no prompt (`task.prompt is
         None`); end the trajectory by setting a `self.state` flag a taskset `@vf.stop` checks."""
         raise NotImplementedError
 
diff --git a/verifiers/v1/retries.py b/verifiers/v1/retries.py
--- a/verifiers/v1/retries.py
+++ b/verifiers/v1/retries.py
@@ -43,8 +43,10 @@ class RolloutRetryConfig(BaseConfig):
     rollout-level retries). Matching is by the error's exception type name, so
     `include`/`exclude` name exception classes (e.g. ``ModelError``, ``ProgramError``)."""
 
-    max_retries: int = Field(1, ge=0)
-    """Whole-rollout retries beyond the first attempt (0 = no retry, N = up to N retries)."""
+    max_retries: int = Field(0, ge=0)
+    """Whole-rollout retries beyond the first attempt (0 = no retry, the default, N = up to N
+    retries). Off by default — per-call `model`/`runtime` retries already cover transient faults;
+    rerunning a whole trajectory is opt-in (set this, plus `include`/`exclude`)."""
     include: list[str] = []
     """Only retry errors whose type is listed. Empty = retry anything not excluded."""
     exclude: list[str] = []
diff --git a/verifiers/v1/rollout.py b/verifiers/v1/rollout.py
--- a/verifiers/v1/rollout.py
+++ b/verifiers/v1/rollout.py
@@ -195,10 +195,10 @@ async def run(self) -> Trace:
                         state_secret=secret,
                     ) as session.user,
                 ):
-                    if self.task.instruction is None and session.user is None:
+                    if self.task.prompt is None and session.user is None:
                         raise ProgramError(
-                            "task has no instruction and no user simulator to open the "
-                            "conversation; set task.instruction or have Taskset.user return "
+                            "task has no prompt and no user simulator to open the "
+                            "conversation; set task.prompt or have Taskset.user return "
                             "a simulator"
                         )
                     # setup done — the harness is now driving
diff --git a/verifiers/v1/runtimes/base.py b/verifiers/v1/runtimes/base.py
--- a/verifiers/v1/runtimes/base.py
+++ b/verifiers/v1/runtimes/base.py
@@ -118,34 +118,37 @@ def __init__(self, name: str | None = None) -> None:
         the rollout it serves; falls back to a unique `vf-` name (standalone / tool
         runtimes, where there's no single owning rollout)."""
 
+    # --- identity / display ---
+
     @property
     def type(self) -> str:
         """The runtime's config discriminator ("subprocess" / "docker" / "prime" / "modal")."""
         return self.config.type
 
     @property
-    def published_port(self) -> int | None:
-        """A fixed port this runtime exposes to the outside at startup, declared up front to the
-        provider (Modal forwards only ports named at `Sandbox.create`). When set, a server placed
-        here binds it instead of a host-chosen free port, and `expose` returns its public URL.
-        `None` for host-networked runtimes (subprocess/docker), which pick a free port and are
-        reached over the shared host network."""
+    def descriptor(self) -> str | None:
+        """A short resolved id for display (None until provisioned). Overridden per
+        runtime: subprocess workdir, docker image, prime sandbox id."""
         return None
 
+    # --- lifecycle ---
+
     @abstractmethod
     async def start(self) -> None:
         """Provision execution (workspace / container / sandbox). Use `expose` to turn a
         host port into a URL the program can reach."""
 
+    async def stop(self) -> None:
+        """Free the provisioned resource on the normal path, off the event loop. Override
+        only for teardown that must be async (e.g. a remote API call)."""
+        await asyncio.to_thread(self.cleanup)
+
     def cleanup(self) -> None:
         """Synchronously free the provisioned resource — best-effort and idempotent. The
         source of truth for teardown: usable from the atexit backstop where async machinery
         is dead, and run off the event loop by `stop` on the normal path. Default no-op."""
 
-    async def stop(self) -> None:
-        """Free the provisioned resource on the normal path, off the event loop. Override
-        only for teardown that must be async (e.g. a remote API call)."""
-        await asyncio.to_thread(self.cleanup)
+    # --- execution ---
 
     @abstractmethod
     async def run(self, argv: list[str], env: dict[str, str]) -> ProgramResult:
@@ -161,29 +164,6 @@ async def run_background(
             f"{type(self).__name__} does not support run_background"
         )
 
-    @property
-    def descriptor(self) -> str | None:
-        """A short resolved id for display (None until provisioned). Overridden per
-        runtime: subprocess workdir, docker image, prime sandbox id."""
-        return None
-
-    async def expose(self, port: int) -> str | None:
-        """Publish a port running *inside this runtime* to a URL reachable from the host/outside,
-        or None when local (it's on the host network — reach it at localhost). A remote runtime
-        overrides this with the provider's native port exposure (modal `tunnels()`, prime
-        `client.expose`), torn down with the sandbox in `stop()`. The reverse of `host_endpoint`
-        (which reaches a host port from inside a runtime)."""
-        return None
-
-    @abstractmethod
-    async def read(self, path: str) -> bytes:
-        """Read a file from the runtime's workspace. The caller need not know
-        whether that's the host fs or across a container/sandbox boundary."""
-
-    @abstractmethod
-    async def write(self, path: str, data: bytes) -> None:
-        """Write a file into the runtime's workspace, creating parent dirs."""
-
     async def run_uv_script(
         self,
         script: str | bytes,
@@ -215,6 +195,36 @@ async def run_uv_script(
         command = f'{_ENSURE_UV}; exec uv run {shlex.quote(path)} "$@"'
         return await self.run(["sh", "-c", command, path, *(args or [])], env or {})
 
+    # --- filesystem ---
+
+    @abstractmethod
+    async def read(self, path: str) -> bytes:
+        """Read a file from the runtime's workspace. The caller need not know
+        whether that's the host fs or across a container/sandbox boundary."""
+
+    @abstractmethod
+    async def write(self, path: str, data: bytes) -> None:
+        """Write a file into the runtime's workspace, creating parent dirs."""
+
+    # --- networking ---
+
+    @property
+    def published_port(self) -> int | None:
+        """A fixed port this runtime exposes to the outside at startup, declared up front to the
+        provider (Modal forwards only ports named at `Sandbox.create`). When set, a server placed
+        here binds it instead of a host-chosen free port, and `expose` returns its public URL.
+        `None` for host-networked runtimes (subprocess/docker), which pick a free port and are
+        reached over the shared host network."""
+        return None
+
+    async def expose(self, port: int) -> str | None:
+        """Publish a port running *inside this runtime* to a URL reachable from the host/outside,
+        or None when local (it's on the host network — reach it at localhost). A remote runtime
+        overrides this with the provider's native port exposure (modal `tunnels()`, prime
+        `client.expose`), torn down with the sandbox in `stop()`. The reverse of `host_endpoint`
+        (which reaches a host port from inside a runtime)."""
+        return None
+
 
 class RetryingRuntime(Runtime):
     """Wraps a runtime to retry each call on a transient error (tenacity, up to
@@ -240,11 +250,13 @@ def __init__(self, inner: Runtime, max_retries: int) -> None:
         )
 
     def _log_retry(self, state: RetryCallState) -> None:
+        # before_sleep fires after a failed attempt, before the imminent retry — so
+        # attempt_number is the retry index (1 on the first retry); count out of max_retries.
         logger.warning(
-            "retrying runtime.%s (attempt %d/%d) after error: %s",
+            "retrying runtime.%s (retry %d/%d) after error: %s",
             getattr(state.fn, "__name__", "call"),
             state.attempt_number,
-            self.max_retries + 1,
+            self.max_retries,
             state.outcome.exception(),
         )
 
diff --git a/verifiers/v1/runtimes/docker.py b/verifiers/v1/runtimes/docker.py
--- a/verifiers/v1/runtimes/docker.py
+++ b/verifiers/v1/runtimes/docker.py
@@ -24,7 +24,7 @@ class DockerConfig(BaseConfig):
     type: Literal["docker"] = "docker"
     image: str = "python:3.11-slim"
     workdir: str = "/app"
-    # Resources in Modal's units (also settable per-task via Task.resources).
+    # TaskResources in Modal's units (also settable per-task via Task.resources).
     cpu: float | None = None
     """Pin the container to this many CPU cores (docker `--cpus`). None = unlimited."""
     memory: float | None = None
diff --git a/verifiers/v1/runtimes/modal.py b/verifiers/v1/runtimes/modal.py
--- a/verifiers/v1/runtimes/modal.py
+++ b/verifiers/v1/runtimes/modal.py
@@ -40,7 +40,7 @@ class ModalConfig(BaseConfig):
     timeout: int | Literal["auto"] = 21600
     """Max sandbox lifetime in seconds (default 6h; or "auto" = the highest Modal supports,
     24h). A hard backstop: the sandbox self-terminates even if local cleanup is skipped."""
-    # Resources, in Modal's native units (also settable per-task via Task.resources, with
+    # TaskResources, in Modal's native units (also settable per-task via Task.resources, with
     # precedence cli/toml > task > this default).
     cpu: float = 1.0
     """CPU cores."""
diff --git a/verifiers/v1/runtimes/prime.py b/verifiers/v1/runtimes/prime.py
--- a/verifiers/v1/runtimes/prime.py
+++ b/verifiers/v1/runtimes/prime.py
@@ -44,7 +44,7 @@ class PrimeConfig(BaseConfig):
     """Max sandbox lifetime in seconds (default 6h; or "auto" = the highest prime
     supports). A hard backstop: the sandbox self-terminates even if local cleanup is
     skipped."""
-    # Resources, in Modal's units (also settable per-task via Task.resources, with
+    # TaskResources, in Modal's units (also settable per-task via Task.resources, with
     # precedence cli/toml > task > this default). Mapped to prime's API in `start`.
     cpu: float = 1.0
     """CPU cores."""
diff --git a/verifiers/v1/serve/server.py b/verifiers/v1/serve/server.py
--- a/verifiers/v1/serve/server.py
+++ b/verifiers/v1/serve/server.py
@@ -24,6 +24,7 @@
 import zmq
 import zmq.asyncio
 
+from verifiers.utils.process_utils import use_threading_tqdm_lock
 from verifiers.utils.serve_utils import msgpack_encoder
 from verifiers.v1.clients import RolloutContext, resolve_client
 from verifiers.v1.clients.client import Client
@@ -79,6 +80,10 @@ def run_server(cls, address_queue=None, **kwargs) -> None:
         `address_queue` is given, report the concrete bound address on it (so a
         spawner that passed a `:0` address learns the OS-assigned port) before
         serving."""
+        # This worker loads the taskset (and any HF datasets it pulls in) and is killed at
+        # teardown; pin tqdm to a threading lock first so it never leaks a multiprocessing
+        # semaphore (resource_tracker warning at shutdown).
+        use_threading_tqdm_lock()
         server = cls(**kwargs)
         if address_queue is not None:
             address_queue.put(server.address)
@@ -111,13 +116,14 @@ async def _run_rollout(self, req: RunRolloutRequest) -> RunRolloutResponse:
         ctx = self._context(req.client, req.model, req.sampling)
         episode = self.env.episode(self.tasks[req.task_idx], ctx, n=1)
         traces = await episode.run()
-        return RunRolloutResponse(trace=traces[0].to_wire())
+        # dump to a dict so the `Trace[WireTask]` field re-types the concrete task to WireTask
+        return RunRolloutResponse(trace=traces[0].model_dump())
 
     async def _run_group(self, req: RunGroupRequest) -> RunGroupResponse:
         ctx = self._context(req.client, req.model, req.sampling)
         episode = self.env.episode(self.tasks[req.task_idx], ctx, n=req.n)
         traces = await episode.run()
-        return RunGroupResponse(traces=[t.to_wire() for t in traces])
+        return RunGroupResponse(traces=[t.model_dump() for t in traces])
 
     async def _handle(
         self, client_id: bytes, request_id: bytes, method: bytes, payload: bytes
diff --git a/verifiers/v1/serve/types.py b/verifiers/v1/serve/types.py
--- a/verifiers/v1/serve/types.py
+++ b/verifiers/v1/serve/types.py
@@ -58,7 +58,7 @@ class RunRolloutResponse(BaseResponse):
 
     @field_serializer("trace")
     def _ser_trace(self, trace: "Trace[WireTask] | None") -> dict | None:
-        return trace.to_wire() if trace is not None else None
+        return trace.model_dump() if trace is not None else None
 
 
 class RunGroupRequest(BaseRequest):
@@ -76,4 +76,4 @@ class RunGroupResponse(BaseResponse):
 
     @field_serializer("traces")
     def _ser_traces(self, traces: "list[Trace[WireTask]] | None") -> list[dict] | None:
-        return [t.to_wire() for t in traces] if traces is not None else None
+        return [t.model_dump() for t in traces] if traces is not None else None
diff --git a/verifiers/v1/task.py b/verifiers/v1/task.py
--- a/verifiers/v1/task.py
+++ b/verifiers/v1/task.py
@@ -13,7 +13,7 @@
 from verifiers.v1.types import Messages, StrictBaseModel
 
 
-class Resources(StrictBaseModel):
+class TaskResources(StrictBaseModel):
     """Runtime resources a task requests (all optional), in Modal's units. Applied to the
     runtime config where the field exists; a field the runtime doesn't support is warned
     about and ignored. Precedence: cli/toml > task > the runtime default (`None` here =
@@ -31,6 +31,23 @@ class Resources(StrictBaseModel):
     """Disk in GB (enforced by prime; advisory on docker/modal)."""
 
 
+class TaskTimeout(StrictBaseModel):
+    """Per-task wall-clock timeout overrides (seconds, all optional), one per rollout stage. Each
+    merges with the eval's `timeout` (`TimeoutConfig`): cli/toml > this > default (no limit).
+    Frozen, like `TaskResources`."""
+
+    model_config = ConfigDict(frozen=True)
+
+    setup: float | None = None
+    """The taskset's `setup` hook."""
+    harness: float | None = None
+    """The harness run."""
+    finalize: float | None = None
+    """The taskset's `finalize` hook."""
+    scoring: float | None = None
+    """Verify + rewards/metrics."""
+
+
 class Task(StrictBaseModel):
     """A single problem to solve. Subclass to add typed task-specific fields."""
 
@@ -42,16 +59,16 @@ class Task(StrictBaseModel):
     """Optional human-readable task name/label (for display/filtering)."""
     description: str | None = None
     """Optional human-readable task description."""
-    instruction: str | Messages | None
+    prompt: str | Messages | None
     """The user message shown to the model (the task's question/framing). Usually a `str`; a
     `Messages` list seeds a full initial conversation (e.g. a user message carrying images) and
-    is only accepted by harnesses that set `SUPPORTS_MESSAGE_INSTRUCTION`. Required — set it
+    is only accepted by harnesses that set `SUPPORTS_MESSAGE_PROMPT`. Required — set it
     explicitly to `None` to mean the task carries no prompt: the taskset's user simulator
     (`Taskset.user`) then opens the conversation, its first `respond` supplying the initial user
     turn before the model is ever called."""
     system_prompt: str | None = None
     """Optional system prompt. Harnesses that set `APPENDS_SYSTEM_PROMPT` emit it as a real
-    system message (or their own mechanism); others prepend it to `instruction` (with a
+    system message (or their own mechanism); others prepend it to `prompt` (with a
     warning). See `Harness.resolve_prompt`."""
     image: str | None = None
     """Container image this task needs (e.g. its harbor environment). When set, the
@@ -62,19 +79,9 @@ class Task(StrictBaseModel):
     the runtime config's `workdir` (where the runtime supports one). For a containerized
     task whose image puts the working tree at a non-default path (e.g. a SWE row's
     `/workspace/<repo>`)."""
-    setup_timeout: float | None = None
-    """Optional per-task setup timeout (seconds). Merges with the eval's
-    `setup_timeout`: cli/toml > this > default (no limit)."""
-    harness_timeout: float | None = None
-    """Optional per-task harness timeout (seconds). Merges with the eval's
-    `harness_timeout`: cli/toml > this > default (no limit)."""
-    finalize_timeout: float | None = None
-    """Optional per-task finalize timeout (seconds). Merges with the eval's
-    `finalize_timeout`: cli/toml > this > default (no limit)."""
-    scoring_timeout: float | None = None
-    """Optional per-task scoring timeout (seconds). Merges with the eval's
-    `scoring_timeout`: cli/toml > this > default (no limit)."""
-    resources: Resources = Resources()
+    timeout: TaskTimeout = TaskTimeout()
+    """Optional per-task timeout overrides, one per rollout stage (merge with the eval's `timeout`)."""
+    resources: TaskResources = TaskResources()
     """Optional runtime resources this task requests (applied where supported)."""
 
 
diff --git a/verifiers/v1/taskset.py b/verifiers/v1/taskset.py
--- a/verifiers/v1/taskset.py
+++ b/verifiers/v1/taskset.py
@@ -22,7 +22,8 @@
 from pydantic_config import BaseConfig
 
 from verifiers.v1.decorators import discover_decorated, invoke
-from verifiers.v1.ids import EnvId, env_name
+from verifiers.v1.types import EnvId
+from verifiers.v1.utils.install import env_name
 from verifiers.v1.runtimes import Runtime
 from verifiers.v1.mcp import Toolset, User
 from verifiers.v1.state import StateT
diff --git a/verifiers/v1/trace.py b/verifiers/v1/trace.py
--- a/verifiers/v1/trace.py
+++ b/verifiers/v1/trace.py
@@ -16,13 +16,13 @@
 from typing import Any, Generic, TypeVar
 
 import numpy as np
-from pydantic import Field, PrivateAttr, computed_field
+from pydantic import Field, PrivateAttr
 from renderers.base import MultiModalData
 
 from verifiers.v1 import graph
 from verifiers.v1.graph import MessageNode
 from verifiers.v1.state import State, StateT
-from verifiers.v1.task import TaskT
+from verifiers.v1.task import TaskT, WireTask
 from verifiers.v1.types import (
     AssistantMessage,
     Messages,
@@ -34,12 +34,12 @@
 
 
 class TimeSpan(StrictBaseModel):
-    """A start/end wall-clock span with a computed duration in seconds."""
+    """A start/end wall-clock span. `duration` is derived (seconds) — a plain property, not
+    serialized, so it never has to be stripped from a wire/disk dump (it's just `end - start`)."""
 
     start: float = 0.0
     end: float = 0.0
 
-    @computed_field
     @property
     def duration(self) -> float:
         return max(0.0, self.end - self.start) if self.end else 0.0
@@ -62,9 +62,7 @@ class Error(StrictBaseModel):
 
     type: str
     message: str
-    traceback: str | None = (
-        None  # synthetic errors (cancels, empty trajectory) have none
-    )
+    traceback: str | None = None
 
 
 class Branch(StrictBaseModel):
@@ -76,7 +74,6 @@ class Branch(StrictBaseModel):
     index: int
     nodes: list[MessageNode]
 
-    @computed_field
     @property
     def num_turns(self) -> int:
         """Model turns (sampled responses) in this branch — prompt-supplied assistant
@@ -224,12 +221,10 @@ class Trace(StrictBaseModel, Generic[TaskT, StateT]):
     """`(parent, msg_hash) -> node_id` for the graph builder (`graph.prepare_turn` / `commit`);
     rebuilt lazily from `nodes` after deserialization."""
 
-    @computed_field
     @property
     def reward(self) -> float:
         return sum(self.rewards.values())
 
-    @computed_field
     @property
     def error(self) -> Error | None:
         """The most recent captured error (the rest are earlier retry attempts)."""
@@ -295,7 +290,6 @@ def num_turns(self) -> int:
         assistant messages don't count."""
         return sum(1 for n in self.nodes if n.sampled)
 
-    @computed_field
     @property
     def is_truncated(self) -> bool:
         """Whether the rollout was cut off by a budget/limit rather than ending on its
@@ -376,27 +370,11 @@ def capture_error(self, error: Exception) -> None:
         )
         self.stop("error")
 
-    def to_wire(self) -> dict:
-        """Dump for the wire, dropping the derived (computed) fields at every level —
-        the top-level ones (reward, branches, num_branches, num_turns) and the per-span
-        timing durations. A strict `Trace` can't round-trip them as input, and the
-        consumer recomputes them, so we avoid re-running branching + duplicating the
-        trajectory on every reply. The full `model_dump` (with derived fields) is what
-        gets written to disk.
-
-        Dumped in `mode="python"` (not `"json"`) so per-node numpy arrays survive as raw bytes
-        in their `__nd__` dicts — the env-server packs the result with a numpy-aware msgpack
-        encoder so the arrays ride the `bin` wire untouched. `mode="json"` would coerce the
-        bytes to str."""
-        exclude: dict = {field: True for field in type(self).model_computed_fields}
-        # Drop each timing span's computed `duration` — derived per `TimeSpan` field of
-        # `Timing` (setup/generation/scoring, and any future span) so none leaks to the wire.
-        exclude["timing"] = {
-            name: {f: True for f in TimeSpan.model_computed_fields}
-            for name, info in Timing.model_fields.items()
-            if info.annotation is TimeSpan
-        }
-        return self.model_dump(mode="python", exclude=exclude)
-
 
 TraceT = TypeVar("TraceT", bound=Trace)  # type: ignore[type-arg]
+
+WireTrace = Trace[WireTask]
+"""A `Trace` typed for loading a dump without the originating taskset: taskset-specific task fields
+ride in `task.model_extra` (`WireTask` allows extras); `state` is never serialized so it needs no
+permissive type. The dump is plain pydantic (no derived computed fields), so load it directly:
+`WireTrace.model_validate(json.loads(line))`."""
diff --git a/verifiers/v1/types.py b/verifiers/v1/types.py
--- a/verifiers/v1/types.py
+++ b/verifiers/v1/types.py
@@ -8,22 +8,11 @@
 
 from typing import Annotated, Any, Literal
 
-from pydantic import AliasChoices, BaseModel, ConfigDict, Field
+from pydantic import AfterValidator, AliasChoices, BaseModel, ConfigDict, Field
 from renderers.base import MultiModalData
 from typing_extensions import TypedDict
 
 
-class RoutedExperts(TypedDict):
-    """The raw MoE expert-routing data a `generate` response carries for router replay:
-    base64 `data` (uint8 `[tokens, layers, top_k]`), its `shape`, and `start` — the prompt
-    offset where the routing begins (0 = full prompt+completion). Kept opaque (`Any` data)
-    so pydantic never validates the encoded blob."""
-
-    data: Any
-    shape: list[int]
-    start: int
-
-
 class StrictBaseModel(BaseModel):
     """A pydantic base that rejects unknown fields. Use for all closed data types."""
 
@@ -163,6 +152,17 @@ def total_tokens(self) -> int:
         return self.prompt_tokens + self.completion_tokens
 
 
+class RoutedExperts(TypedDict):
+    """The raw MoE expert-routing data a `generate` response carries for router replay:
+    base64 `data` (uint8 `[tokens, layers, top_k]`), its `shape`, and `start` — the prompt
+    offset where the routing begins (0 = full prompt+completion). Kept opaque (`Any` data)
+    so pydantic never validates the encoded blob."""
+
+    data: Any
+    shape: list[int]
+    start: int
+
+
 class TurnTokens(StrictBaseModel):
     """Token ids + sampling logprobs for one response, for training. Populated by the
     renderer client (client-side tokenization) or the chat client (parsed from vLLM's
@@ -218,3 +218,26 @@ class SamplingConfig(BaseModel):
     max_tokens: int | None = Field(
         None, validation_alias=AliasChoices("max_tokens", "max_completion_tokens")
     )
+
+
+Sampling = SamplingConfig
+"""Alias for `SamplingConfig` — the terse name for a `sampling` field/arg."""
+
+
+# --- ids ----------------------------------------------------------------------
+
+
+def _validate_env_id(env_id: str) -> str:
+    """Validate the id's shape — a hub id must be a well-formed ``org/name[@version]``; a
+    local id is any module name. Returns it unchanged (the value stays a plain ``str``)."""
+    from verifiers.utils.install_utils import is_hub_env, parse_env_id
+
+    if is_hub_env(env_id):
+        parse_env_id(env_id)  # raises ValueError on a malformed org/name[@version]
+    return env_id
+
+
+EnvId = Annotated[str, AfterValidator(_validate_env_id)]
+"""A taskset / harness / environment id — ``name``, ``org/name``, or ``org/name@version``. A
+plain validated ``str``; derive its package/module name with `env_name` / `env_module`
+(`verifiers.v1.utils.install`)."""
diff --git a/verifiers/v1/utils/__init__.py b/verifiers/v1/utils/__init__.py
new file mode 100644
--- /dev/null
+++ b/verifiers/v1/utils/__init__.py
@@ -0,0 +1,3 @@
+"""Small shared helpers for v1, by concern: `format` (display), `install` (env-id /
+on-demand hub install), `logging` (route stdlib logs through loguru), `memory` (worker RSS).
+Import from the submodule, e.g. `from verifiers.v1.utils.format import format_reward`."""
diff --git a/verifiers/v1/utils/format.py b/verifiers/v1/utils/format.py
new file mode 100644
--- /dev/null
+++ b/verifiers/v1/utils/format.py
@@ -0,0 +1,49 @@
+"""Compact human-readable formatting for display (durations, counts, headline reward)."""
+
+from __future__ import annotations
+
+from typing import TYPE_CHECKING
+
+if TYPE_CHECKING:
+    from verifiers.v1.trace import Trace
+
+
+def format_time(seconds: float) -> str:
+    """A compact human-readable duration (mirrors prime-rl): s / m s / h m / d h."""
+    if seconds < 1:
+        return f"{seconds:.1f}s"
+    if seconds < 60:
+        return f"{seconds:.0f}s"
+    if seconds < 3600:
+        m, s = divmod(int(seconds), 60)
+        return f"{m}m {s}s"
+    if seconds < 86400:
+        h, rem = divmod(int(seconds), 3600)
+        return f"{h}h {rem // 60}m"
+    d, rem = divmod(int(seconds), 86400)
+    return f"{d}d {rem // 3600}h"
+
+
+def format_count(n: int) -> str:
+    """A compact count (mirrors prime-rl): 936 / 4.8K / 1.5M."""
+    if n < 1_000:
+        return str(n)
+    if n < 1_000_000:
+        return f"{n / 1e3:.1f}K"
+    return f"{n / 1e6:.1f}M"
+
+
+def format_reward(traces: list[Trace], digits: int = 2) -> str:
+    """Headline reward over completed `traces`: the mean over the non-errored ones
+    (error-corrected). When some errored, also append the global mean — over *all*
+    completed, errored counting as 0 — in parens, so both the error-corrected and the
+    raw reward are visible. "—" when nothing has completed (or all errored)."""
+    if not traces:
+        return "—"
+    clean = [t for t in traces if not t.has_error]
+    if not clean:
+        return "—"
+    reward = f"{sum(t.reward for t in clean) / len(clean):.{digits}f}"
+    if len(clean) < len(traces):  # some errored → show the raw global avg alongside
+        reward += f" ({sum(t.reward for t in traces) / len(traces):.{digits}f})"
+    return reward
diff --git a/verifiers/v1/utils/install.py b/verifiers/v1/utils/install.py
new file mode 100644
--- /dev/null
+++ b/verifiers/v1/utils/install.py
@@ -0,0 +1,43 @@
+"""Environment/plugin id helpers + on-demand install from the Environments Hub.
+
+Thin v1 wrappers over `verifiers.utils.install_utils`: derive an id's package/module name,
+and make a hub id (`org/name[@version]`) importable on demand (the same path `prime env
+install` uses)."""
+
+import logging
+
+from verifiers.utils.install_utils import (
+    check_hub_env_installed,
+    install_from_hub,
+    is_hub_env,
+    normalize_package_name,
+    parse_env_id,
+)
+
+logger = logging.getLogger(__name__)
+
+
+def env_name(env_id: str) -> str:
+    """The package name — the id with org and version stripped (``org/gsm8k@1.0`` ->
+    ``gsm8k``). Used for logging, display, and output paths."""
+    return parse_env_id(env_id)[1] if is_hub_env(env_id) else env_id
+
+
+def env_module(env_id: str) -> str:
+    """The importable module name — `env_name` normalized (hyphens -> underscores)."""
+    return normalize_package_name(env_name(env_id))
+
+
+def ensure_installed(env_id: str) -> str:
+    """Make `env_id` importable and return its module name.
+
+    For a hub id (``org/name[@version]``) that isn't installed, install it from the
+    Environments Hub — latest, or the pinned version — the same path `prime env install`
+    uses. A local id is assumed already importable."""
+    if is_hub_env(env_id) and not check_hub_env_installed(env_id):
+        logger.info("installing %s from the environments hub", env_id)
+        if not install_from_hub(env_id):
+            raise ModuleNotFoundError(
+                f"could not install {env_id!r} from the environments hub"
+            )
+    return env_module(env_id)
diff --git a/verifiers/v1/cli/log.py b/verifiers/v1/utils/logging.py
rename from verifiers/v1/cli/log.py
rename to verifiers/v1/utils/logging.py
--- a/verifiers/v1/cli/log.py
+++ b/verifiers/v1/utils/logging.py
@@ -1,7 +1,7 @@
-"""Route the library's stdlib logging through loguru for the eval CLI.
+"""Route the library's stdlib logging through loguru for the CLIs.
 
 The library (`verifiers.v1`) logs via stdlib logging and is silent by default
-(a NullHandler on the package root). The eval CLI opts in: it points loguru at
+(a NullHandler on the package root). A CLI opts in: it points loguru at
 stderr — so logs never mix with the results printed to stdout — and installs an
 `InterceptHandler` on the `verifiers.v1` logger so those records render through
 loguru. Mirrors prime-rl's `intercept_vf_logging`.
diff --git a/verifiers/v1/utils.py b/verifiers/v1/utils/memory.py
rename from verifiers/v1/utils.py
rename to verifiers/v1/utils/memory.py
--- a/verifiers/v1/utils.py
+++ b/verifiers/v1/utils/memory.py
@@ -1,14 +1,7 @@
-"""Small shared helpers."""
-
-from __future__ import annotations
+"""Worker memory management: hand glibc's freed arenas back to the OS."""
 
 import asyncio
 import ctypes
-from typing import TYPE_CHECKING
-
-if TYPE_CHECKING:
-    from verifiers.v1.trace import Trace
-
 
 # Resolved once on first use: glibc's malloc_trim, or False where it isn't available.
 _malloc_trim: object = None
@@ -46,44 +39,3 @@ async def trim_memory_periodically() -> None:
     if _rollouts_since_trim >= _TRIM_EVERY_ROLLOUTS:
         _rollouts_since_trim = 0
         await asyncio.to_thread(trim_memory)
-
-
-def format_time(seconds: float) -> str:
-    """A compact human-readable duration (mirrors prime-rl): s / m s / h m / d h."""
-    if seconds < 1:
-        return f"{seconds:.1f}s"
-    if seconds < 60:
-        return f"{seconds:.0f}s"
-    if seconds < 3600:
-        m, s = divmod(int(seconds), 60)
-        return f"{m}m {s}s"
-    if seconds < 86400:
-        h, rem = divmod(int(seconds), 3600)
-        return f"{h}h {rem // 60}m"
-    d, rem = divmod(int(seconds), 86400)
-    return f"{d}d {rem // 3600}h"
-
-
-def format_count(n: int) -> str:
-    """A compact count (mirrors prime-rl): 936 / 4.8K / 1.5M."""
-    if n < 1_000:
-        return str(n)
-    if n < 1_000_000:
-        return f"{n / 1e3:.1f}K"
-    return f"{n / 1e6:.1f}M"
-
-
-def format_reward(traces: list[Trace], digits: int = 2) -> str:
-    """Headline reward over completed `traces`: the mean over the non-errored ones
-    (error-corrected). When some errored, also append the global mean — over *all*
-    completed, errored counting as 0 — in parens, so both the error-corrected and the
-    raw reward are visible. "—" when nothing has completed (or all errored)."""
-    if not traces:
-        return "—"
-    clean = [t for t in traces if not t.has_error]
-    if not clean:
-        return "—"
-    reward = f"{sum(t.reward for t in clean) / len(clean):.{digits}f}"
-    if len(clean) < len(traces):  # some errored → show the raw global avg alongside
-        reward += f" ({sum(t.reward for t in traces) / len(traces):.{digits}f})"
-    return reward
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
