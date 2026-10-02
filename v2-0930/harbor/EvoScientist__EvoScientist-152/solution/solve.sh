#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/EvoScientist/EvoScientist.py b/EvoScientist/EvoScientist.py
--- a/EvoScientist/EvoScientist.py
+++ b/EvoScientist/EvoScientist.py
@@ -305,7 +305,7 @@ def _get_default_middleware():
         create_memory_middleware(memory_dir, extraction_model=model),
     ]
 
-    if cfg.enable_ask_user and not cfg.auto_approve:
+    if cfg.enable_ask_user and not cfg.auto_mode:
         from .middleware.ask_user import AskUserMiddleware
 
         mw.insert(0, AskUserMiddleware())
@@ -433,7 +433,7 @@ def create_cli_agent(workspace_dir: str | None = None, checkpointer=None, config
         *create_tool_selector_middleware(),
         create_memory_middleware(_mem_dir, extraction_model=model),
     ]
-    if cfg.enable_ask_user and not cfg.auto_approve:
+    if cfg.enable_ask_user and not cfg.auto_mode:
         from .middleware.ask_user import AskUserMiddleware
 
         mw.insert(0, AskUserMiddleware())
diff --git a/EvoScientist/channels/debug.py b/EvoScientist/channels/debug.py
--- a/EvoScientist/channels/debug.py
+++ b/EvoScientist/channels/debug.py
@@ -68,7 +68,7 @@ def _stringify(value: Any) -> str:
         return value.replace("\n", "\\n")
     if isinstance(value, Mapping):
         return f"<map:{len(value)}>"
-    if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
+    if isinstance(value, Sequence) and not isinstance(value, str | bytes | bytearray):
         return f"<seq:{len(value)}>"
     return str(value).replace("\n", "\\n")
 
diff --git a/EvoScientist/cli/commands.py b/EvoScientist/cli/commands.py
--- a/EvoScientist/cli/commands.py
+++ b/EvoScientist/cli/commands.py
@@ -13,6 +13,7 @@
 from rich.markup import escape
 from rich.table import Table
 
+from ..llm.context_window import DEFAULT_CONTEXT_WINDOW_FALLBACK, resolve_context_window
 from ..paths import ensure_dirs, set_workspace_root
 from ..stream.display import console
 from ._app import app, channel_app, config_app, mcp_app
@@ -100,6 +101,10 @@ def channel_setup():
 # Compact helper
 # =============================================================================
 
+_COMPACT_CONTEXT_WINDOW_FALLBACK = DEFAULT_CONTEXT_WINDOW_FALLBACK
+_MANUAL_COMPACT_MIN_FRACTION = 0.40
+_MANUAL_COMPACT_MIN_PERCENT = int(_MANUAL_COMPACT_MIN_FRACTION * 100)
+
 
 class CompactResult:
     """Structured result from compact_conversation.
@@ -114,14 +119,20 @@ class CompactResult:
         tokens_summarized: Tokens in the summarized portion (before).
         tokens_summary: Tokens in the summary message (after).
         pct_decrease: Percentage decrease.
+        context_window: Model context window used for thresholding.
+        context_percent: Effective context utilization percent.
+        summary_text: Human-readable compact summary content for UI display.
     """
 
     __slots__ = (
+        "context_percent",
+        "context_window",
         "message",
         "messages_compacted",
         "messages_kept",
         "pct_decrease",
         "status",
+        "summary_text",
         "tokens_after",
         "tokens_before",
         "tokens_summarized",
@@ -140,6 +151,9 @@ def __init__(
         tokens_summarized: int = 0,
         tokens_summary: int = 0,
         pct_decrease: int = 0,
+        context_window: int = 0,
+        context_percent: int = 0,
+        summary_text: str = "",
     ):
         self.status = status
         self.message = message
@@ -150,11 +164,40 @@ def __init__(
         self.tokens_summarized = tokens_summarized
         self.tokens_summary = tokens_summary
         self.pct_decrease = pct_decrease
+        self.context_window = context_window
+        self.context_percent = context_percent
+        self.summary_text = summary_text
 
     def __str__(self) -> str:
         return self.message
 
 
+class CompactSummaryRenderable:
+    """Rich renderable payload for the manual compact summary content."""
+
+    __slots__ = ("summary_text",)
+
+    def __init__(self, summary_text: str):
+        self.summary_text = (summary_text or "").strip()
+
+    def __rich_console__(self, console, options):
+        yield render_compact_summary_panel(self.summary_text)
+
+
+def _resolve_context_window(
+    model: Any, fallback: int = _COMPACT_CONTEXT_WINDOW_FALLBACK
+) -> int:
+    """Resolve a model context window with a stable fallback."""
+    return resolve_context_window(model, fallback=fallback)
+
+
+def _percent_used(tokens: int, context_window: int) -> int:
+    """Return a clamped utilization percent."""
+    if context_window <= 0:
+        return 0
+    return max(0, min(100, round((tokens / context_window) * 100)))
+
+
 def render_compact_result(result: CompactResult):  # -> rich.text.Text
     """Render a CompactResult as styled Rich Text.
 
@@ -167,19 +210,23 @@ def render_compact_result(result: CompactResult):  # -> rich.text.Text
 
     if result.status == "noop":
         output.append("○ ", style="dim")
-        output.append("Nothing to compact", style="dim")
+        output.append("Manual compact not needed", style="dim")
         if result.tokens_before > 0:
-            output.append(" — conversation is ~", style="dim")
+            output.append("  [", style="dim")
             output.append(f"{result.tokens_before:,}", style="cyan")
-            output.append(" tokens, within retention budget", style="dim")
-        elif result.message:
-            # Extract reason from message (e.g. "no messages")
-            output.append(
-                f" — {result.message.split('—')[-1].strip()}"
-                if "—" in result.message
-                else "",
-                style="dim",
-            )
+            if result.context_window > 0:
+                output.append(" / ", style="dim")
+                output.append(f"{result.context_window:,}", style="cyan")
+                output.append(" tokens", style="dim")
+                output.append("  │  ", style="dim")
+                output.append(f"{result.context_percent}%", style="cyan")
+                output.append(" of window", style="dim")
+            else:
+                output.append(" tokens", style="dim")
+            output.append("]", style="dim")
+        if result.message:
+            output.append("\n  ", style="")
+            output.append(result.message, style="dim")
         return output
 
     if result.status == "error":
@@ -210,17 +257,57 @@ def render_compact_result(result: CompactResult):  # -> rich.text.Text
     output.append("Kept: ", style="dim")
     output.append(f"{result.messages_kept}", style="cyan")
     output.append(" messages unchanged", style="dim")
+    if result.context_window > 0:
+        output.append("  │  ", style="dim")
+        output.append("Window: ", style="dim")
+        output.append(f"{result.context_percent}%", style="cyan")
+        output.append(" used", style="dim")
 
     return output
 
 
-async def compact_conversation(agent: Any, thread_id: str | None) -> CompactResult:
+def render_compact_summary_panel(summary_text: str):
+    """Render the compacted summary content as a Rich panel."""
+    from rich.panel import Panel
+    from rich.text import Text
+
+    content = (summary_text or "").strip()
+    body = Text(content or "(empty summary)", style="dim italic")
+    return Panel(
+        body,
+        title="Context Compacted",
+        border_style="#f59e0b",
+        padding=(0, 1),
+    )
+
+
+def build_compact_summary_renderable(
+    result: CompactResult,
+) -> CompactSummaryRenderable | None:
+    """Build the UI summary payload for a successful compact operation."""
+    if result.status != "ok" or not result.summary_text.strip():
+        return None
+    return CompactSummaryRenderable(result.summary_text)
+
+
+async def compact_conversation(
+    agent: Any,
+    thread_id: str | None,
+    *,
+    input_tokens_hint: int | None = None,
+) -> CompactResult:
     """Compact the conversation by summarizing old messages.
 
     Reads the agent's checkpointed state, creates a temporary
     ``SummarizationMiddleware``, generates a summary, and writes
     the compacted state back via ``aupdate_state``.
 
+    ``input_tokens_hint`` is the real LLM input token count from the last
+    ``usage_metadata`` (includes system prompt + tool schemas).  When
+    provided it is used for the display values in ``CompactResult`` so the
+    panel stays in sync with the status bar; the internal compact logic
+    (cutoff determination) still uses message-level token counts.
+
     Returns a structured ``CompactResult``.
     """
     if not agent or not thread_id:
@@ -257,6 +344,7 @@ async def compact_conversation(agent: Any, thread_id: str | None) -> CompactResu
         )
 
     backend = _get_default_backend()
+    context_window = _resolve_context_window(model)
 
     defaults = compute_summarization_defaults(model)
     middleware = SummarizationMiddleware(
@@ -269,15 +357,38 @@ async def compact_conversation(agent: Any, thread_id: str | None) -> CompactResu
     # Rebuild effective message list accounting for prior compaction
     event = state_snapshot.values.get("_summarization_event")
     effective = middleware._apply_event_to_messages(messages, event)
+    effective_tokens = count_tokens_approximately(effective)
+
+    # For display and threshold we prefer the real LLM input token count
+    # (includes system prompt + tool schemas) so the panel stays in sync with
+    # the status bar.  The internal compact logic (cutoff, partition, savings)
+    # still uses effective_tokens (message-level) because compact only reduces
+    # messages, not the constant system/tool overhead.
+    display_tokens = (
+        input_tokens_hint
+        if input_tokens_hint is not None and input_tokens_hint > 0
+        else effective_tokens
+    )
+    display_percent = _percent_used(display_tokens, context_window)
+
+    if display_percent < _MANUAL_COMPACT_MIN_PERCENT:
+        return CompactResult(
+            "noop",
+            "Conversation is below the manual compact threshold "
+            f"({display_percent}% < {_MANUAL_COMPACT_MIN_PERCENT}%).",
+            tokens_before=display_tokens,
+            context_window=context_window,
+            context_percent=display_percent,
+        )
 
     cutoff = middleware._determine_cutoff_index(effective)
     if cutoff == 0:
-        conv_tokens = count_tokens_approximately(effective)
         return CompactResult(
             "noop",
-            f"Nothing to compact — conversation (~{conv_tokens:,} tokens) "
-            f"is within the retention budget.",
-            tokens_before=conv_tokens,
+            f"Conversation (~{display_tokens:,} tokens) is within the retention budget.",
+            tokens_before=display_tokens,
+            context_window=context_window,
+            context_percent=display_percent,
         )
 
     to_summarize, to_keep = middleware._partition_messages(effective, cutoff)
@@ -300,7 +411,9 @@ async def compact_conversation(agent: Any, thread_id: str | None) -> CompactResu
             f"Nothing to compact — only {len(to_summarize)} message(s) "
             f"({tokens_summarized:,} tokens) would be summarized, "
             f"not worth the overhead.",
-            tokens_before=tokens_before,
+            tokens_before=display_tokens,
+            context_window=context_window,
+            context_percent=display_percent,
         )
 
     # Generate summary (LLM call)
@@ -325,7 +438,7 @@ async def compact_conversation(agent: Any, thread_id: str | None) -> CompactResu
 
     summary_msg = middleware._build_new_messages_with_path(summary, file_path)[0]
 
-    # Compute token savings
+    # Compute token savings (message-level, used for pct calculation)
     tokens_summary = count_tokens_approximately([summary_msg])
     tokens_after = tokens_summary + tokens_kept
     pct = (
@@ -334,11 +447,18 @@ async def compact_conversation(agent: Any, thread_id: str | None) -> CompactResu
         else 0
     )
 
+    # Adjust display totals: preserve real overhead (system + tools) by
+    # offsetting from input_tokens_hint rather than using bare message counts.
+    msg_reduction = tokens_before - tokens_after  # how many message tokens saved
+    display_before = display_tokens
+    display_after = max(0, display_tokens - msg_reduction)
+    display_after_percent = _percent_used(display_after, context_window)
+
     # Append savings note to summary message for model awareness
     savings_note = (
         f"\n\n{len(to_summarize)} messages were compacted "
         f"({tokens_summarized:,} → {tokens_summary:,} tokens). "
-        f"Total context: {tokens_before:,} → {tokens_after:,} tokens "
+        f"Total context: {display_before:,} → {display_after:,} tokens "
         f"({pct}% decrease), "
         f"{len(to_keep)} messages unchanged."
     )
@@ -357,14 +477,17 @@ async def compact_conversation(agent: Any, thread_id: str | None) -> CompactResu
     return CompactResult(
         "ok",
         f"Compacted {len(to_summarize)} messages "
-        f"({tokens_before:,} → {tokens_after:,} tokens, {pct}% decrease)",
+        f"({display_before:,} → {display_after:,} tokens, {pct}% decrease)",
         messages_compacted=len(to_summarize),
         messages_kept=len(to_keep),
-        tokens_before=tokens_before,
-        tokens_after=tokens_after,
+        tokens_before=display_before,
+        tokens_after=display_after,
         tokens_summarized=tokens_summarized,
         tokens_summary=tokens_summary,
         pct_decrease=pct,
+        context_window=context_window,
+        context_percent=display_after_percent,
+        summary_text=summary,
     )
 
 
@@ -491,7 +614,12 @@ def serve(
     auto_approve: bool = typer.Option(
         False,
         "--auto-approve",
-        help="Auto-approve all tool executions without prompting",
+        help="Skip tool approval prompts for HITL actions",
+    ),
+    auto_mode: bool = typer.Option(
+        False,
+        "--auto-mode",
+        help="Run unattended: skip ask_user and tool approval prompts",
     ),
     ask_user: bool = typer.Option(
         False,
@@ -514,7 +642,11 @@ def serve(
     cli_overrides = {}
     if auto_approve:
         cli_overrides["auto_approve"] = True
-    if ask_user:
+    if auto_mode:
+        cli_overrides["auto_mode"] = True
+        cli_overrides["auto_approve"] = True
+        cli_overrides["enable_ask_user"] = False
+    elif ask_user:
         cli_overrides["enable_ask_user"] = True
     if debug:
         cli_overrides["log_level"] = "DEBUG"
@@ -970,7 +1102,12 @@ def _main_callback(
     auto_approve: bool = typer.Option(
         False,
         "--auto-approve",
-        help="Auto-approve all tool executions without prompting",
+        help="Skip tool approval prompts for HITL actions",
+    ),
+    auto_mode: bool = typer.Option(
+        False,
+        "--auto-mode",
+        help="Run unattended: skip ask_user and tool approval prompts",
     ),
     ask_user: bool = typer.Option(
         False,
@@ -1008,7 +1145,11 @@ def _main_callback(
         cli_overrides["ui_backend"] = ui
     if auto_approve:
         cli_overrides["auto_approve"] = True
-    if ask_user:
+    if auto_mode:
+        cli_overrides["auto_mode"] = True
+        cli_overrides["auto_approve"] = True
+        cli_overrides["enable_ask_user"] = False
+    elif ask_user:
         cli_overrides["enable_ask_user"] = True
     if auth_mode:
         if auth_mode not in ("api_key", "oauth"):
diff --git a/EvoScientist/cli/interactive.py b/EvoScientist/cli/interactive.py
--- a/EvoScientist/cli/interactive.py
+++ b/EvoScientist/cli/interactive.py
@@ -5,6 +5,7 @@
 import queue
 import random
 import sys
+from datetime import datetime
 from typing import Any
 
 import typer  # type: ignore[import-untyped]
@@ -60,6 +61,23 @@
     _cmd_list_skills,
     _cmd_uninstall_skill,
 )
+from .status_bar import (
+    STATUS_BAD,
+    STATUS_BAR_BG,
+    STATUS_CRITICAL,
+    STATUS_DIM,
+    STATUS_GOOD,
+    STATUS_STRONG,
+    STATUS_TEXT,
+    STATUS_WARN,
+    apply_assistant_text_to_snapshot,
+    apply_user_text_to_snapshot,
+    build_session_status_snapshot,
+    build_status_fragments,
+    build_status_text,
+    make_empty_status_snapshot,
+    make_usage_status_snapshot,
+)
 from .tui_interactive import run_textual_interactive
 from .tui_runtime import resolve_ui_backend, run_streaming
 
@@ -156,6 +174,13 @@ def print_banner(
         "completion-menu.meta.completion.current": "bg:default default bold noreverse",
         "scrollbar.background": "bg:default",
         "scrollbar.button": "bg:default",
+        "status-bar": f"bg:{STATUS_BAR_BG} {STATUS_TEXT}",
+        "status-bar-strong": f"bg:{STATUS_BAR_BG} {STATUS_STRONG} bold",
+        "status-bar-dim": f"bg:{STATUS_BAR_BG} {STATUS_DIM}",
+        "status-bar-good": f"bg:{STATUS_BAR_BG} {STATUS_GOOD} bold",
+        "status-bar-warn": f"bg:{STATUS_BAR_BG} {STATUS_WARN} bold",
+        "status-bar-bad": f"bg:{STATUS_BAR_BG} {STATUS_BAD} bold",
+        "status-bar-critical": f"bg:{STATUS_BAR_BG} {STATUS_CRITICAL} bold",
     }
 )
 
@@ -312,8 +337,102 @@ def _print_separator():
         "running": True,
         "resumed": False,
         "ui_backend": resolved_ui_backend,
+        "status_started_at": datetime.now(),
+        "status_base_snapshot": make_empty_status_snapshot(model),
+        "status_snapshot": make_empty_status_snapshot(model),
+        "status_streaming_text": "",
+        "status_last_input_tokens": None,
     }
 
+    def _rebuild_status_snapshot() -> None:
+        """Compose the visible snapshot from thread state + live output."""
+        state["status_snapshot"] = apply_assistant_text_to_snapshot(
+            state["status_base_snapshot"],
+            state["status_streaming_text"],
+        )
+
+    def _set_status_streaming_text(text: str | None) -> None:
+        """Update the in-flight assistant overlay used by the status bar."""
+        new_text = text or ""
+        if new_text == state["status_streaming_text"]:
+            return
+        state["status_streaming_text"] = new_text
+        _rebuild_status_snapshot()
+
+    async def _refresh_status_snapshot(
+        pending_user_text: str | None = None,
+        *,
+        reset_streaming_text: bool = True,
+    ) -> None:
+        """Recompute the persistent status-bar snapshot for the active thread."""
+        pending = (pending_user_text or "").strip()
+        if pending:
+            if state["status_last_input_tokens"] is not None:
+                state["status_base_snapshot"] = apply_user_text_to_snapshot(
+                    make_usage_status_snapshot(
+                        state["status_last_input_tokens"],
+                        model_name=model,
+                    ),
+                    pending,
+                )
+            else:
+                state["status_base_snapshot"] = await build_session_status_snapshot(
+                    state["thread_id"],
+                    model_name=model,
+                    pending_user_text=pending,
+                )
+        elif state["status_last_input_tokens"] is not None:
+            state["status_base_snapshot"] = make_usage_status_snapshot(
+                state["status_last_input_tokens"],
+                model_name=model,
+            )
+        else:
+            state["status_base_snapshot"] = await build_session_status_snapshot(
+                state["thread_id"],
+                model_name=model,
+            )
+        if reset_streaming_text:
+            state["status_streaming_text"] = ""
+        _rebuild_status_snapshot()
+
+    def _bottom_toolbar():
+        """Render the persistent bottom status bar for prompt_toolkit."""
+        try:
+            from prompt_toolkit.application import get_app
+
+            width = get_app().output.get_size().columns
+        except Exception:
+            width = console.size.width
+        return build_status_fragments(
+            state["status_snapshot"],
+            state["status_started_at"],
+            width,
+        )
+
+    def _stream_status_footer():
+        """Render the live Rich footer used during streaming output."""
+        return build_status_text(
+            state["status_snapshot"],
+            state["status_started_at"],
+            console.size.width,
+        )
+
+    async def _handle_stream_status_event(event_type: str, stream_state) -> None:
+        """Keep the CLI status bar aligned with live stream progress."""
+        if event_type == "usage_stats":
+            last_input_tokens = getattr(stream_state, "last_input_tokens", 0)
+            if last_input_tokens > 0:
+                state["status_last_input_tokens"] = last_input_tokens
+                state["status_base_snapshot"] = make_usage_status_snapshot(
+                    last_input_tokens,
+                    model_name=model,
+                )
+                _rebuild_status_snapshot()
+        elif event_type == "text":
+            _set_status_streaming_text(stream_state.response_text)
+        elif event_type in ("done", "error"):
+            _set_status_streaming_text("")
+
     async def _resolve_thread_id(tid: str) -> str | None:
         """Resolve a (possibly partial) thread ID. Returns full ID or None."""
         if await thread_exists(tid):
@@ -517,12 +636,15 @@ async def _cmd_resume(arg: str, checkpointer):
         state["resumed"] = True
         if ws:
             state["workspace_dir"] = ws
+        state["status_started_at"] = datetime.now()
+        state["status_last_input_tokens"] = None
         console.print("[dim]Loading session...[/dim]")
         state["agent"] = _load_agent(
             workspace_dir=state["workspace_dir"],
             checkpointer=checkpointer,
             config=config,
         )
+        await _refresh_status_snapshot(reset_streaming_text=True)
         # Sync shared refs if channel is running
         if _channels_is_running():
             _ch_mod._cli_agent = state["agent"]
@@ -563,6 +685,8 @@ async def _async_main_loop():
                     ws = (meta or {}).get("workspace_dir", "") or state["workspace_dir"]
                     state["thread_id"] = resolved
                     state["resumed"] = True
+                    state["status_started_at"] = datetime.now()
+                    state["status_last_input_tokens"] = None
                     if ws:
                         state["workspace_dir"] = ws
 
@@ -572,6 +696,7 @@ async def _async_main_loop():
                 checkpointer=checkpointer,
                 config=config,
             )
+            await _refresh_status_snapshot(reset_streaming_text=True)
 
             # Print banner
             if state["resumed"]:
@@ -690,6 +815,9 @@ def _channel_ask_user(ask_user_data: dict) -> dict:
 
                 meta = build_metadata(state["workspace_dir"], model)
                 try:
+                    await _refresh_status_snapshot(
+                        msg.content, reset_streaming_text=True
+                    )
                     response = run_streaming(
                         ui_backend=state["ui_backend"],
                         agent=state["agent"],
@@ -703,12 +831,15 @@ def _channel_ask_user(ask_user_data: dict) -> dict:
                         on_file_write=_send_media_to_channel,
                         hitl_prompt_fn=_channel_hitl_prompt,
                         ask_user_prompt_fn=_channel_ask_user,
+                        on_stream_event=_handle_stream_status_event,
+                        status_footer_builder=_stream_status_footer,
                     )
                 except Exception as e:
                     response = f"Error: {e}"
                     console.print(f"[red]Channel error: {e}[/red]")
 
                 _set_channel_response(msg.msg_id, response)
+                await _refresh_status_snapshot(reset_streaming_text=True)
 
                 tx = Text()
                 tx.append(f"[{msg.channel_type}: Replied to ", style="dim")
@@ -793,7 +924,9 @@ def _show_update_hint() -> None:
                 while state["running"]:
                     try:
                         user_input = await session.prompt_async(
-                            HTML("<ansiblue><b>\u276f</b></ansiblue> ")
+                            HTML("<ansiblue><b>\u276f</b></ansiblue> "),
+                            bottom_toolbar=_bottom_toolbar,
+                            refresh_interval=1.0,
                         )
                         user_input = user_input.strip()
 
@@ -839,6 +972,9 @@ def _show_update_hint() -> None:
                             )
                             state["thread_id"] = generate_thread_id()
                             state["resumed"] = False
+                            state["status_started_at"] = datetime.now()
+                            state["status_last_input_tokens"] = None
+                            await _refresh_status_snapshot(reset_streaming_text=True)
                             # Sync channel refs so the queue checker uses the new agent
                             if _channels_is_running():
                                 _ch_mod._cli_agent = state["agent"]
@@ -909,6 +1045,7 @@ def _show_update_hint() -> None:
 
                         if user_input.lower() == "/compact":
                             from .commands import (
+                                build_compact_summary_renderable,
                                 compact_conversation,
                                 render_compact_result,
                             )
@@ -919,8 +1056,27 @@ def _show_update_hint() -> None:
                                 result = await compact_conversation(
                                     agent=state["agent"],
                                     thread_id=state["thread_id"],
+                                    input_tokens_hint=state.get(
+                                        "status_last_input_tokens"
+                                    ),
                                 )
                             console.print(render_compact_result(result))
+                            summary_renderable = build_compact_summary_renderable(
+                                result
+                            )
+                            if summary_renderable is not None:
+                                console.print(summary_renderable)
+                            if result.status == "ok" and result.tokens_after > 0:
+                                state["status_last_input_tokens"] = result.tokens_after
+                                state["status_base_snapshot"] = (
+                                    make_usage_status_snapshot(
+                                        result.tokens_after,
+                                        model_name=model,
+                                    )
+                                )
+                            await _refresh_status_snapshot(
+                                reset_streaming_text=True,
+                            )
                             continue
 
                         # Resolve @file mentions — inject file contents inline
@@ -935,6 +1091,9 @@ def _show_update_hint() -> None:
                             console.print(f"[yellow]⚠ {escape(w)}[/yellow]")
                         console.print()
                         meta = build_metadata(state["workspace_dir"], model)
+                        await _refresh_status_snapshot(
+                            message_to_send, reset_streaming_text=True
+                        )
                         run_streaming(
                             ui_backend=state["ui_backend"],
                             agent=state["agent"],
@@ -943,7 +1102,10 @@ def _show_update_hint() -> None:
                             show_thinking=show_thinking,
                             interactive=True,
                             metadata=meta,
+                            on_stream_event=_handle_stream_status_event,
+                            status_footer_builder=_stream_status_footer,
                         )
+                        await _refresh_status_snapshot(reset_streaming_text=True)
                         console.print()
                         _print_separator()
 
diff --git a/EvoScientist/cli/status_bar.py b/EvoScientist/cli/status_bar.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/cli/status_bar.py
@@ -0,0 +1,372 @@
+"""Shared session status bar helpers for CLI and TUI frontends."""
+
+from __future__ import annotations
+
+from dataclasses import dataclass, replace
+from datetime import datetime
+from typing import Any
+
+from langchain_core.messages import AIMessage, HumanMessage
+from langchain_core.messages.utils import count_tokens_approximately
+
+from ..llm.context_window import (
+    DEFAULT_CONTEXT_WINDOW_FALLBACK,
+    resolve_context_window,
+)
+from ..sessions import get_thread_messages
+
+_FALLBACK_CONTEXT_WINDOW = DEFAULT_CONTEXT_WINDOW_FALLBACK
+STATUS_BAR_BG = "#171a20"
+STATUS_TEXT = "#cbd5e1"
+STATUS_STRONG = "#e5e7eb"
+STATUS_DIM = "#7c8594"
+STATUS_GOOD = "#5fcf8b"
+STATUS_WARN = "#d7b45a"
+STATUS_BAD = "#d08c61"
+STATUS_CRITICAL = "#d86f6f"
+STATUS_HINT_IDLE = "#8b9bb0"
+STATUS_HINT_BUSY = "#f0c36a"
+
+
+@dataclass(slots=True)
+class SessionStatusSnapshot:
+    """Current session metrics shown in the persistent status bar."""
+
+    model_full: str
+    model_short: str
+    context_tokens: int
+    context_window: int
+    context_percent: int
+    context_source: str = "estimated"
+
+
+def _percent_from_context(context_tokens: int, context_window: int) -> int:
+    """Convert token counts into a clamped percent value."""
+    if context_window <= 0:
+        return 0
+    return max(0, min(100, round((context_tokens / context_window) * 100)))
+
+
+def _get_default_chat_model() -> Any:
+    """Resolve the default chat model lazily to avoid import cycles."""
+    from ..EvoScientist import _ensure_chat_model
+
+    return _ensure_chat_model()
+
+
+def _resolve_model_name(model_name: str | None, model_obj: Any | None) -> str:
+    """Best-effort model name resolution for display."""
+    if model_name:
+        return str(model_name)
+    if model_obj is None:
+        model_obj = _get_default_chat_model()
+    for attr in ("model_name", "model", "name"):
+        value = getattr(model_obj, attr, None)
+        if value:
+            return str(value)
+    return "unknown"
+
+
+def _resolve_context_window(model_obj: Any | None) -> int:
+    """Resolve the model context window with a safe fallback."""
+    if model_obj is None:
+        model_obj = _get_default_chat_model()
+    return resolve_context_window(model_obj, fallback=_FALLBACK_CONTEXT_WINDOW)
+
+
+def shorten_model_name(model_name: str, max_len: int = 26) -> str:
+    """Shorten provider-prefixed model names for compact display."""
+    short = (model_name or "unknown").split("/")[-1]
+    if len(short) > max_len:
+        return f"{short[: max_len - 3]}..."
+    return short
+
+
+def format_token_count_compact(value: int) -> str:
+    """Format large token counts into a compact human-readable form."""
+    abs_value = abs(int(value))
+    if abs_value >= 1_000_000:
+        num = value / 1_000_000
+        suffix = "M"
+    elif abs_value >= 1_000:
+        num = value / 1_000
+        suffix = "K"
+    else:
+        return str(value)
+
+    if num.is_integer():
+        return f"{int(num)}{suffix}"
+    return f"{num:.1f}{suffix}"
+
+
+def format_duration_compact(started_at: datetime, now: datetime | None = None) -> str:
+    """Format elapsed wall time into a compact duration string."""
+    current = now or datetime.now()
+    seconds = max(0, int((current - started_at).total_seconds()))
+    if seconds < 60:
+        return f"{seconds}s"
+    minutes = seconds // 60
+    if minutes < 60:
+        return f"{minutes}m"
+    hours = minutes // 60
+    if hours < 24:
+        return f"{hours}h"
+    days = hours // 24
+    return f"{days}d"
+
+
+def status_style_name(percent_used: int) -> str:
+    """Map utilization percent to shared status bar style buckets."""
+    if percent_used >= 95:
+        return "critical"
+    if percent_used > 80:
+        return "bad"
+    if percent_used >= 50:
+        return "warn"
+    return "good"
+
+
+def build_context_bar(percent_used: int, width: int = 10) -> str:
+    """Build a compact visual context progress bar."""
+    safe_percent = max(0, min(100, int(percent_used)))
+    filled = round((safe_percent / 100) * width)
+    body = ("█" * filled) + ("░" * max(0, width - filled))
+    return f"[{body}]"
+
+
+def _display_width(text: str) -> int:
+    try:
+        from prompt_toolkit.utils import get_cwidth
+
+        return get_cwidth(text or "")
+    except Exception:
+        return len(text or "")
+
+
+def trim_status_text(text: str, max_width: int) -> str:
+    """Trim status-bar content to fit a single terminal row."""
+    if max_width <= 0:
+        return ""
+    if _display_width(text) <= max_width:
+        return text
+
+    ellipsis = "..."
+    ellipsis_width = _display_width(ellipsis)
+    if max_width <= ellipsis_width:
+        return ellipsis[:max_width]
+
+    try:
+        from prompt_toolkit.utils import get_cwidth
+    except Exception:
+        get_cwidth = None
+
+    out: list[str] = []
+    width = 0
+    for ch in text:
+        ch_width = get_cwidth(ch) if get_cwidth else len(ch)
+        if width + ch_width + ellipsis_width > max_width:
+            break
+        out.append(ch)
+        width += ch_width
+    return "".join(out).rstrip() + ellipsis
+
+
+def build_status_fragments(
+    snapshot: SessionStatusSnapshot,
+    started_at: datetime,
+    width: int,
+) -> list[tuple[str, str]]:
+    """Build prompt_toolkit formatted-text fragments for the status bar."""
+    duration_label = format_duration_compact(started_at)
+    percent = snapshot.context_percent
+    percent_label = f"{percent}%"
+    if width < 52:
+        frags = [
+            ("class:status-bar-strong", snapshot.model_short),
+            ("class:status-bar-dim", " · "),
+            ("class:status-bar-dim", duration_label),
+            ("class:status-bar", " "),
+        ]
+    elif width < 76:
+        frags = [
+            ("class:status-bar-strong", snapshot.model_short),
+            ("class:status-bar-dim", " · "),
+            (f"class:status-bar-{status_style_name(percent)}", percent_label),
+            ("class:status-bar-dim", " · "),
+            ("class:status-bar-dim", duration_label),
+            ("class:status-bar", " "),
+        ]
+    else:
+        context_label = (
+            f"{format_token_count_compact(snapshot.context_tokens)}/"
+            f"{format_token_count_compact(snapshot.context_window)}"
+        )
+        bucket = status_style_name(percent)
+        frags = [
+            ("class:status-bar-strong", snapshot.model_short),
+            ("class:status-bar-dim", " │ "),
+            ("class:status-bar-dim", context_label),
+            ("class:status-bar-dim", " │ "),
+            (f"class:status-bar-{bucket}", build_context_bar(percent)),
+            ("class:status-bar-dim", " "),
+            (f"class:status-bar-{bucket}", percent_label),
+            ("class:status-bar-dim", " │ "),
+            ("class:status-bar-dim", duration_label),
+            ("class:status-bar", " "),
+        ]
+
+    total_width = sum(_display_width(text) for _, text in frags)
+    if total_width > width:
+        plain_text = "".join(text for _, text in frags)
+        return [("class:status-bar", trim_status_text(plain_text, width))]
+    return frags
+
+
+def build_status_text(
+    snapshot: SessionStatusSnapshot,
+    started_at: datetime,
+    width: int,
+):
+    """Build a Rich Text object for the persistent TUI status bar."""
+    from rich.text import Text
+
+    rich_styles = {
+        "status-bar": f"on {STATUS_BAR_BG} {STATUS_TEXT}",
+        "status-bar-strong": f"on {STATUS_BAR_BG} {STATUS_STRONG} bold",
+        "status-bar-dim": f"on {STATUS_BAR_BG} {STATUS_DIM}",
+        "status-bar-good": f"on {STATUS_BAR_BG} {STATUS_GOOD} bold",
+        "status-bar-warn": f"on {STATUS_BAR_BG} {STATUS_WARN} bold",
+        "status-bar-bad": f"on {STATUS_BAR_BG} {STATUS_BAD} bold",
+        "status-bar-critical": f"on {STATUS_BAR_BG} {STATUS_CRITICAL} bold",
+    }
+    text = Text(no_wrap=True, overflow="crop")
+    for style, content in build_status_fragments(snapshot, started_at, width):
+        rich_style = rich_styles.get(
+            style.removeprefix("class:"),
+            f"on {STATUS_BAR_BG} {STATUS_TEXT}",
+        )
+        text.append(content, style=rich_style)
+    return text
+
+
+def make_empty_status_snapshot(
+    model_name: str | None = None, model_obj: Any | None = None
+) -> SessionStatusSnapshot:
+    """Build a placeholder snapshot before async context counting completes."""
+    resolved_name = _resolve_model_name(model_name, model_obj)
+    window = _resolve_context_window(model_obj)
+    return SessionStatusSnapshot(
+        model_full=resolved_name,
+        model_short=shorten_model_name(resolved_name),
+        context_tokens=0,
+        context_window=window,
+        context_percent=0,
+        context_source="estimated",
+    )
+
+
+def make_usage_status_snapshot(
+    input_tokens: int,
+    *,
+    model_name: str | None = None,
+    model_obj: Any | None = None,
+) -> SessionStatusSnapshot:
+    """Build a snapshot from the last real model input usage."""
+    resolved_name = _resolve_model_name(model_name, model_obj)
+    window = _resolve_context_window(model_obj)
+    context_tokens = max(0, int(input_tokens))
+    return SessionStatusSnapshot(
+        model_full=resolved_name,
+        model_short=shorten_model_name(resolved_name),
+        context_tokens=context_tokens,
+        context_window=window,
+        context_percent=_percent_from_context(context_tokens, window),
+        context_source="usage",
+    )
+
+
+def estimate_message_tokens(
+    text: str,
+    *,
+    message_type: str = "ai",
+) -> int:
+    """Estimate tokens for a single in-flight message fragment."""
+    content = (text or "").strip()
+    if not content:
+        return 0
+
+    try:
+        if message_type == "human":
+            messages = [HumanMessage(content=content)]
+        else:
+            messages = [AIMessage(content=content)]
+        return int(count_tokens_approximately(messages))
+    except Exception:
+        return 0
+
+
+def apply_assistant_text_to_snapshot(
+    snapshot: SessionStatusSnapshot,
+    assistant_text: str | None,
+) -> SessionStatusSnapshot:
+    """Overlay in-flight assistant output on top of a base snapshot."""
+    extra_tokens = estimate_message_tokens(assistant_text or "", message_type="ai")
+    if extra_tokens <= 0:
+        return snapshot
+
+    context_tokens = snapshot.context_tokens + extra_tokens
+    return replace(
+        snapshot,
+        context_tokens=context_tokens,
+        context_percent=_percent_from_context(context_tokens, snapshot.context_window),
+    )
+
+
+def apply_user_text_to_snapshot(
+    snapshot: SessionStatusSnapshot,
+    user_text: str | None,
+) -> SessionStatusSnapshot:
+    """Overlay pending user input on top of an existing snapshot."""
+    extra_tokens = estimate_message_tokens(user_text or "", message_type="human")
+    if extra_tokens <= 0:
+        return snapshot
+
+    context_tokens = snapshot.context_tokens + extra_tokens
+    return replace(
+        snapshot,
+        context_tokens=context_tokens,
+        context_percent=_percent_from_context(context_tokens, snapshot.context_window),
+    )
+
+
+async def build_session_status_snapshot(
+    thread_id: str,
+    *,
+    model_name: str | None = None,
+    model_obj: Any | None = None,
+    pending_user_text: str | None = None,
+) -> SessionStatusSnapshot:
+    """Count current thread context and return a display snapshot."""
+    resolved_name = _resolve_model_name(model_name, model_obj)
+    window = _resolve_context_window(model_obj)
+    messages = list(await get_thread_messages(thread_id))
+
+    pending = (pending_user_text or "").strip()
+    if pending:
+        messages.append(HumanMessage(content=pending))
+
+    try:
+        context_tokens = int(count_tokens_approximately(messages)) if messages else 0
+    except Exception:
+        context_tokens = 0
+
+    percent = _percent_from_context(context_tokens, window)
+
+    return SessionStatusSnapshot(
+        model_full=resolved_name,
+        model_short=shorten_model_name(resolved_name),
+        context_tokens=context_tokens,
+        context_window=window,
+        context_percent=percent,
+        context_source="estimated",
+    )
diff --git a/EvoScientist/cli/tui_backends.py b/EvoScientist/cli/tui_backends.py
--- a/EvoScientist/cli/tui_backends.py
+++ b/EvoScientist/cli/tui_backends.py
@@ -25,6 +25,8 @@ def run_streaming(
         on_thinking: Callable[[str], None] | None = None,
         on_todo: Callable[[list[dict]], None] | None = None,
         on_file_write: Callable[[str], None] | None = None,
+        on_stream_event: Callable[[str, Any], Any] | None = None,
+        status_footer_builder: Callable[[], Any] | None = None,
         metadata: dict | None = None,
         hitl_prompt_fn: Callable[[list], list[dict] | None] | None = None,
         ask_user_prompt_fn: Callable[[dict], dict] | None = None,
@@ -49,6 +51,8 @@ def run_streaming(
         on_thinking: Callable[[str], None] | None = None,
         on_todo: Callable[[list[dict]], None] | None = None,
         on_file_write: Callable[[str], None] | None = None,
+        on_stream_event: Callable[[str, Any], Any] | None = None,
+        status_footer_builder: Callable[[], Any] | None = None,
         metadata: dict | None = None,
         hitl_prompt_fn: Callable[[list], list[dict] | None] | None = None,
         ask_user_prompt_fn: Callable[[dict], dict] | None = None,
@@ -62,6 +66,8 @@ def run_streaming(
             on_thinking=on_thinking,
             on_todo=on_todo,
             on_file_write=on_file_write,
+            on_stream_event=on_stream_event,
+            status_footer_builder=status_footer_builder,
             metadata=metadata,
             hitl_prompt_fn=hitl_prompt_fn,
             ask_user_prompt_fn=ask_user_prompt_fn,
diff --git a/EvoScientist/cli/tui_interactive.py b/EvoScientist/cli/tui_interactive.py
--- a/EvoScientist/cli/tui_interactive.py
+++ b/EvoScientist/cli/tui_interactive.py
@@ -12,6 +12,7 @@
 import random
 import sys
 from collections.abc import Callable
+from datetime import datetime
 from typing import Any, ClassVar
 
 from rich.console import Group
@@ -44,6 +45,18 @@
 )
 from .file_mentions import complete_file_mention, resolve_file_mentions
 from .history_suggester import HistorySuggester
+from .status_bar import (
+    STATUS_BAR_BG,
+    STATUS_DIM,
+    STATUS_HINT_BUSY,
+    STATUS_HINT_IDLE,
+    apply_assistant_text_to_snapshot,
+    apply_user_text_to_snapshot,
+    build_session_status_snapshot,
+    build_status_text,
+    make_empty_status_snapshot,
+    make_usage_status_snapshot,
+)
 
 _channel_logger = logging.getLogger(__name__)
 
@@ -168,6 +181,18 @@ def _is_final_response(state: StreamState) -> bool:
     return not has_pending and not any_active_sa and not state.is_processing
 
 
+_SUMMARY_CONTINUATION_EVENTS = {
+    "summarization_start",
+    "summarization",
+    "usage_stats",
+}
+
+
+def _should_finalize_active_summarization(event_type: str) -> bool:
+    """Return whether an active summary panel should stop for this event."""
+    return bool(event_type) and event_type not in _SUMMARY_CONTINUATION_EVENTS
+
+
 def run_textual_interactive(
     *,
     show_thinking: bool,
@@ -193,6 +218,7 @@ def run_textual_interactive(
         from .clipboard import copy_selection_to_clipboard, get_clipboard_text
         from .widgets import (
             AssistantMessage,
+            CompactingWidget,
             LoadingWidget,
             SubAgentWidget,
             SummarizationWidget,
@@ -233,7 +259,7 @@ def supports_interactive(self) -> bool:
         }
         #input-shell {
             height: auto;
-            padding: 0 2 1 2;
+            padding: 0 2 0 2;
             background: #16161a;
         }
         #input-row {
@@ -278,8 +304,9 @@ def supports_interactive(self) -> bool:
         }
         #status {
             height: 1;
+            min-height: 1;
             background: #171a20;
-            color: #f59e0b;
+            color: #cbd5e1;
             padding: 0 1;
         }
         """
@@ -331,6 +358,12 @@ def __init__(
             self._history_saved_input: str = ""  # saved current input before browsing
             self._background_tasks: set[asyncio.Task] = set()
             self._quit_pending: bool = False
+            self._status_started_at = datetime.now()
+            self._status_base_snapshot = make_empty_status_snapshot(model)
+            self._status_snapshot = self._status_base_snapshot
+            self._status_streaming_text = ""
+            self._status_last_input_tokens: int | None = None
+            self._compacting_widget: CompactingWidget | None = None
 
         # ── CommandUI implementation ─────────────────────────
 
@@ -340,6 +373,12 @@ def append_system(self, text: str, style: str = "dim") -> None:
         def mount_renderable(self, renderable: Any) -> None:
             self._mount_renderable(renderable)
 
+        async def start_compacting_indicator(self) -> None:
+            await self._start_compacting_indicator()
+
+        async def stop_compacting_indicator(self) -> None:
+            await self._stop_compacting_indicator()
+
         async def wait_for_thread_pick(
             self, threads: list[dict], current_thread: str, title: str
         ) -> str | None:
@@ -412,11 +451,19 @@ def start_new_session(self) -> None:
                 workspace_dir=self._workspace_dir,
                 checkpointer=self._checkpointer,
             )
+            self._status_started_at = datetime.now()
+            self._status_base_snapshot = make_empty_status_snapshot(model)
+            self._status_snapshot = self._status_base_snapshot
+            self._status_streaming_text = ""
+            self._status_last_input_tokens = None
             if _channels_is_running():
                 _ch_mod._cli_agent = self._agent
                 _ch_mod._cli_thread_id = self._conversation_tid
             self._render_welcome()
             self._render_status()
+            refresh_task = asyncio.create_task(self._refresh_status_snapshot())
+            self._background_tasks.add(refresh_task)
+            refresh_task.add_done_callback(self._background_tasks.discard)
             self.append_system(f"New session: {self._conversation_tid}", style="green")
 
         async def handle_session_resume(
@@ -430,10 +477,16 @@ async def handle_session_resume(
                 workspace_dir=self._workspace_dir,
                 checkpointer=self._checkpointer,
             )
+            self._status_started_at = datetime.now()
+            self._status_base_snapshot = make_empty_status_snapshot(model)
+            self._status_snapshot = self._status_base_snapshot
+            self._status_streaming_text = ""
+            self._status_last_input_tokens = None
             if _channels_is_running():
                 _ch_mod._cli_agent = self._agent
                 _ch_mod._cli_thread_id = self._conversation_tid
             self._render_welcome()
+            await self._refresh_status_snapshot()
             self._render_status()
             self.append_system(f"Resumed session: {thread_id}", style="green")
             await self._render_history(thread_id)
@@ -465,6 +518,10 @@ def compose(self) -> ComposeResult:
         def on_mount(self) -> None:
             self._render_welcome()
             self._render_status()
+            self.set_interval(1.0, self._render_status)
+            refresh_task = asyncio.create_task(self._refresh_status_snapshot())
+            self._background_tasks.add(refresh_task)
+            refresh_task.add_done_callback(self._background_tasks.discard)
             prompt = self.query_one("#prompt", ChatTextArea)
             prompt.before_submit = self._handle_completion_enter
             prompt.focus()
@@ -561,9 +618,42 @@ def _append_system(self, text: str, style: str = "dim") -> None:
         def _mount_renderable(self, renderable: Any) -> None:
             """Mount a Rich renderable (e.g. Table) as a Static widget."""
             container = self.query_one("#chat", VerticalScroll)
-            container.mount(Static(renderable))
+            try:
+                from .commands import CompactSummaryRenderable
+                from .widgets.compact_summary_widget import CompactSummaryWidget
+            except Exception:
+                CompactSummaryRenderable = None  # type: ignore[assignment]
+
+            if CompactSummaryRenderable is not None and isinstance(
+                renderable, CompactSummaryRenderable
+            ):
+                container.mount(CompactSummaryWidget(renderable.summary_text))
+            else:
+                container.mount(Static(renderable))
+            container.scroll_end(animate=False)
+
+        async def _start_compacting_indicator(self) -> None:
+            """Show a transient timer widget while /compact is running."""
+            await self._stop_compacting_indicator()
+            container = self.query_one("#chat", VerticalScroll)
+            widget = CompactingWidget()
+            self._compacting_widget = widget
+            await container.mount(widget)
             container.scroll_end(animate=False)
 
+        async def _stop_compacting_indicator(self) -> None:
+            """Remove the transient /compact progress widget, if present."""
+            widget = self._compacting_widget
+            self._compacting_widget = None
+            if widget is not None:
+                try:
+                    await widget.cleanup()
+                except Exception:
+                    try:
+                        await widget.remove()
+                    except Exception:
+                        pass
+
         async def _wait_for_approval(self, approval_widget) -> Any:
             """Wait for user to interact with an ApprovalWidget.
 
@@ -796,6 +886,11 @@ async def _remove_w(w: Static | None) -> None:
                     except Exception:
                         pass
 
+            def _finalize_active_summarization() -> None:
+                """Stop the active summary timer once the stream moves on."""
+                if summarization_w is not None and summarization_w._is_active:
+                    summarization_w.finalize()
+
             async def _collapse_completed_tools() -> None:
                 """Hide older completed tool widgets; show summary line."""
                 nonlocal collapse_summary_w
@@ -882,6 +977,12 @@ def _find_or_rename_sa_widget(
                     ):
                         event_type = state.handle_event(event)
 
+                        if event_type == "usage_stats":
+                            self._set_status_usage_baseline(state.last_input_tokens)
+
+                        if _should_finalize_active_summarization(event_type):
+                            _finalize_active_summarization()
+
                         # -- Channel callbacks (thinking, todo, media) --
                         if (
                             on_thinking_cb
@@ -930,6 +1031,7 @@ def _find_or_rename_sa_widget(
                             "thinking",
                             "text",
                             "tool_call",
+                            "summarization_start",
                             "summarization",
                         ):
                             await loading.cleanup()
@@ -942,12 +1044,27 @@ def _find_or_rename_sa_widget(
                                 await container.mount(thinking_w)
                             thinking_w.append_text(event.get("content", ""))
 
+                        elif event_type == "summarization_start":
+                            if (
+                                summarization_w is not None
+                                and not summarization_w._is_active
+                            ):
+                                summarization_w = None
+                            if summarization_w is None:
+                                summarization_w = SummarizationWidget()
+                                await container.mount(summarization_w)
+
                         elif event_type == "summarization":
                             content = event.get("content", "")
+                            if (
+                                summarization_w is not None
+                                and not summarization_w._is_active
+                            ):
+                                summarization_w = None
+                            if summarization_w is None:
+                                summarization_w = SummarizationWidget()
+                                await container.mount(summarization_w)
                             if content:
-                                if summarization_w is None:
-                                    summarization_w = SummarizationWidget()
-                                    await container.mount(summarization_w)
                                 summarization_w.append_text(content)
 
                         elif event_type == "tool_selection":
@@ -961,12 +1078,6 @@ def _find_or_rename_sa_widget(
                                 _schedule_scroll()
 
                         elif event_type == "text":
-                            # Finalize summarization widget when regular text resumes
-                            if (
-                                summarization_w is not None
-                                and summarization_w._is_active
-                            ):
-                                summarization_w.finalize()
                             if thinking_w is not None and thinking_w._is_active:
                                 thinking_w.finalize()
                             # Clear processing indicator
@@ -999,6 +1110,7 @@ def _find_or_rename_sa_widget(
                                     await assistant_w.append_content(
                                         event.get("content", ""),
                                     )
+                                self._set_status_streaming_text(state.response_text)
 
                         elif event_type == "tool_call":
                             tool_name = event.get("name", "unknown")
@@ -1276,12 +1388,6 @@ def _find_or_rename_sa_widget(
                                 )
 
                         elif event_type == "done":
-                            # Finalize summarization if still active
-                            if (
-                                summarization_w is not None
-                                and summarization_w._is_active
-                            ):
-                                summarization_w.finalize()
                             # Clean up transient indicators
                             await _remove_w(narration_w)
                             narration_w = None
@@ -1415,18 +1521,19 @@ def _find_or_rename_sa_widget(
 
         async def _run_turn(self, user_text: str) -> None:
             """Handle a user turn: stream agent response with widgets."""
-            self._busy = True
-            self._render_status()
             cancelled = False
+            try:
+                self._busy = True
+                self._render_status()
 
-            # Resolve @file mentions — inject file contents before sending to agent.
-            # Use self._workspace_dir (current session) not the startup-captured
-            # workspace_dir closure, which becomes stale after /new or /resume.
-            _, message_to_send, file_warnings = await asyncio.to_thread(
-                resolve_file_mentions, user_text, self._workspace_dir
-            )
+                # Resolve @file mentions — inject file contents before sending to agent.
+                # Use self._workspace_dir (current session) not the startup-captured
+                # workspace_dir closure, which becomes stale after /new or /resume.
+                _, message_to_send, file_warnings = await asyncio.to_thread(
+                    resolve_file_mentions, user_text, self._workspace_dir
+                )
+                await self._refresh_status_snapshot(message_to_send)
 
-            try:
                 await self._stream_with_widgets(
                     message_to_send,
                     display_text=user_text,
@@ -1438,6 +1545,7 @@ async def _run_turn(self, user_text: str) -> None:
             finally:
                 self._busy = False
                 self._run_task = None
+                await self._refresh_status_snapshot(reset_streaming_text=True)
                 self._render_status()
                 self.query_one("#prompt", ChatTextArea).focus()
 
@@ -1456,144 +1564,160 @@ async def _process_channel_message(self, msg: ChannelMessage) -> None:
               (streaming response)
               [channel: Replied to sender]
             """
-            self._busy = True
-            self._render_status()
-
-            prompt_widget = self.query_one("#prompt", ChatTextArea)
-            prompt_widget.disabled = True
+            prompt_widget = None
+            try:
+                self._busy = True
+                await self._refresh_status_snapshot(msg.content)
+                self._render_status()
 
-            # Mount user message first, then "Received" label
-            container = self.query_one("#chat", VerticalScroll)
-            await container.mount(UserMessage(msg.content))
-            self._append_system(
-                f"[{msg.channel_type}: Received from {msg.sender}]",
-                style="dim",
-            )
-            container.scroll_end(animate=False)
+                prompt_widget = self.query_one("#prompt", ChatTextArea)
+                prompt_widget.disabled = True
 
-            # Build channel callbacks (fire-and-forget to avoid blocking UI)
-            def _send_to_channel(coro, label: str) -> None:
-                loop = _ch_mod._bus_loop
-                if not loop:
-                    return
-                future = asyncio.run_coroutine_threadsafe(coro, loop)
-                future.add_done_callback(
-                    lambda f: (
-                        _channel_logger.debug(f"{label} send failed: {f.exception()}")
-                        if f.exception()
-                        else None
-                    )
+                # Mount user message first, then "Received" label
+                container = self.query_one("#chat", VerticalScroll)
+                await container.mount(UserMessage(msg.content))
+                self._append_system(
+                    f"[{msg.channel_type}: Received from {msg.sender}]",
+                    style="dim",
                 )
-
-            def _send_thinking(thinking: str) -> None:
-                ch = msg.channel_ref
-                if ch and ch.send_thinking:
-                    _send_to_channel(
-                        ch.send_thinking_message(
-                            sender=msg.chat_id,
-                            thinking=thinking,
-                            metadata=msg.metadata,
-                        ),
-                        "Thinking",
-                    )
-
-            def _send_todo(items: list[dict]) -> None:
-                from ..channels.consumer import _format_todo_list
-
-                if msg.channel_ref:
-                    _send_to_channel(
-                        msg.channel_ref.send_todo_message(
-                            sender=msg.chat_id,
-                            content=_format_todo_list(items),
-                            metadata=msg.metadata,
-                        ),
-                        "Todo",
+                container.scroll_end(animate=False)
+
+                # Build channel callbacks (fire-and-forget to avoid blocking UI)
+                def _send_to_channel(coro, label: str) -> None:
+                    loop = _ch_mod._bus_loop
+                    if not loop:
+                        return
+                    future = asyncio.run_coroutine_threadsafe(coro, loop)
+                    future.add_done_callback(
+                        lambda f: (
+                            _channel_logger.debug(
+                                f"{label} send failed: {f.exception()}"
+                            )
+                            if f.exception()
+                            else None
+                        )
                     )
 
-            def _send_media(file_path: str) -> None:
-                if msg.channel_ref:
-                    _send_to_channel(
-                        msg.channel_ref.send_media(
-                            recipient=msg.chat_id,
-                            file_path=file_path,
-                            metadata=msg.metadata,
-                        ),
-                        "Media",
-                    )
+                def _send_thinking(thinking: str) -> None:
+                    ch = msg.channel_ref
+                    if ch and ch.send_thinking:
+                        _send_to_channel(
+                            ch.send_thinking_message(
+                                sender=msg.chat_id,
+                                thinking=thinking,
+                                metadata=msg.metadata,
+                            ),
+                            "Thinking",
+                        )
 
-            def _channel_hitl_prompt(action_requests: list) -> list[dict] | None:
-                """Send HITL approval prompt to channel user and wait for reply.
+                def _send_todo(items: list[dict]) -> None:
+                    from ..channels.consumer import _format_todo_list
 
-                This runs in a thread (called via asyncio.to_thread) so it can
-                block without freezing the Textual event loop.
-                """
-                return _ch_mod.channel_hitl_prompt(action_requests, msg)
+                    if msg.channel_ref:
+                        _send_to_channel(
+                            msg.channel_ref.send_todo_message(
+                                sender=msg.chat_id,
+                                content=_format_todo_list(items),
+                                metadata=msg.metadata,
+                            ),
+                            "Todo",
+                        )
 
-            def _channel_ask_user(ask_user_data: dict) -> dict:
-                """Send ask_user questions to channel user and wait for reply.
+                def _send_media(file_path: str) -> None:
+                    if msg.channel_ref:
+                        _send_to_channel(
+                            msg.channel_ref.send_media(
+                                recipient=msg.chat_id,
+                                file_path=file_path,
+                                metadata=msg.metadata,
+                            ),
+                            "Media",
+                        )
 
-                This runs in a thread (called via asyncio.to_thread) so it can
-                block without freezing the Textual event loop.
-                """
-                return _ch_mod.channel_ask_user_prompt(ask_user_data, msg)
+                def _channel_hitl_prompt(action_requests: list) -> list[dict] | None:
+                    """Send HITL approval prompt to channel user and wait for reply.
+
+                    This runs in a thread (called via asyncio.to_thread) so it can
+                    block without freezing the Textual event loop.
+                    """
+                    return _ch_mod.channel_hitl_prompt(action_requests, msg)
+
+                def _channel_ask_user(ask_user_data: dict) -> dict:
+                    """Send ask_user questions to channel user and wait for reply.
+
+                    This runs in a thread (called via asyncio.to_thread) so it can
+                    block without freezing the Textual event loop.
+                    """
+                    return _ch_mod.channel_ask_user_prompt(ask_user_data, msg)
+
+                from ..commands.channel_ui import ChannelCommandUI
+
+                # Handle slash commands from channel
+                if msg.content.strip().startswith("/"):
+                    ctx = CommandContext(
+                        agent=self._agent,
+                        thread_id=self._conversation_tid,
+                        ui=ChannelCommandUI(
+                            msg,
+                            append_system_callback=self._append_system,
+                            start_new_session_callback=self.start_new_session,
+                            handle_session_resume_callback=self.handle_session_resume,
+                        ),
+                        workspace_dir=self._workspace_dir,
+                        checkpointer=self._checkpointer,
+                    )
+                    try:
+                        cmd_executed = await cmd_manager.execute(msg.content, ctx)
+                    except Exception as _cmd_exc:
+                        # Command raised — report the error and do NOT fall through
+                        # to _stream_with_widgets (which would treat the slash
+                        # command text as a plain user message to the agent).
+                        _channel_logger.debug(
+                            f"Channel command error: {_cmd_exc}", exc_info=True
+                        )
+                        _set_channel_response(msg.msg_id, f"Command error: {_cmd_exc}")
+                        return  # outer finally handles _busy / widget cleanup
 
-            from ..commands.channel_ui import ChannelCommandUI
+                    if cmd_executed:
+                        self._append_system(
+                            f"[{msg.channel_type}: Executed command from {msg.sender}]",
+                            style="dim",
+                        )
+                        _set_channel_response(
+                            msg.msg_id, f"Command executed: {msg.content}"
+                        )
+                        return  # outer finally handles _busy / widget cleanup
 
-            # Handle slash commands from channel
-            if msg.content.strip().startswith("/"):
-                ctx = CommandContext(
-                    agent=self._agent,
-                    thread_id=self._conversation_tid,
-                    ui=ChannelCommandUI(
-                        msg,
-                        append_system_callback=self._append_system,
-                        start_new_session_callback=self.start_new_session,
-                        handle_session_resume_callback=self.handle_session_resume,
-                    ),
-                    workspace_dir=self._workspace_dir,
-                    checkpointer=self._checkpointer,
-                )
-                if await cmd_manager.execute(msg.content, ctx):
-                    self._append_system(
-                        f"[{msg.channel_type}: Executed command from {msg.sender}]",
-                        style="dim",
-                    )
-                    _set_channel_response(
-                        msg.msg_id, f"Command executed: {msg.content}"
+                response = ""
+                try:
+                    response = await self._stream_with_widgets(
+                        msg.content,
+                        on_thinking_cb=_send_thinking
+                        if self._channel_send_thinking
+                        else None,
+                        on_todo_cb=_send_todo,
+                        on_media_cb=_send_media,
+                        skip_user_message=True,
+                        channel_hitl_fn=_channel_hitl_prompt,
+                        channel_ask_user_fn=_channel_ask_user,
                     )
-                    self._busy = False
-                    self._render_status()
-                    prompt_widget.disabled = False
-                    prompt_widget.focus()
-                    return
+                except Exception as exc:
+                    response = f"Error: {exc}"
+                    self._append_system(f"Error: {exc}", style="red")
 
-            response = ""
-            try:
-                response = await self._stream_with_widgets(
-                    msg.content,
-                    on_thinking_cb=_send_thinking
-                    if self._channel_send_thinking
-                    else None,
-                    on_todo_cb=_send_todo,
-                    on_media_cb=_send_media,
-                    skip_user_message=True,
-                    channel_hitl_fn=_channel_hitl_prompt,
-                    channel_ask_user_fn=_channel_ask_user,
+                _set_channel_response(msg.msg_id, response)
+                self._append_system(
+                    f"[{msg.channel_type}: Replied to {msg.sender}]",
+                    style="dim",
                 )
-            except Exception as exc:
-                response = f"Error: {exc}"
-                self._append_system(f"Error: {exc}", style="red")
+
             finally:
                 self._busy = False
+                await self._refresh_status_snapshot(reset_streaming_text=True)
                 self._render_status()
-                prompt_widget.disabled = False
-                prompt_widget.focus()
-
-            _set_channel_response(msg.msg_id, response)
-            self._append_system(
-                f"[{msg.channel_type}: Replied to {msg.sender}]",
-                style="dim",
-            )
+                if prompt_widget is not None:
+                    prompt_widget.disabled = False
+                    prompt_widget.focus()
 
         # ── Clipboard (copy on mouse select) ─────────────────
 
@@ -1925,18 +2049,40 @@ async def _handle_command(self, command: str) -> None:
             # Echo the command so the user sees what they ran
             self._append_system(command.strip(), style="cyan")
 
+            # Block new user input while the command runs (important for slow
+            # commands like /compact that call an LLM internally).
+            prompt_widget = self.query_one("#prompt", ChatTextArea)
+            self._busy = True
+            prompt_widget.disabled = True
+            self._render_status()
+
             ctx = CommandContext(
                 agent=self._agent,
                 thread_id=self._conversation_tid,
                 ui=self,
                 workspace_dir=self._workspace_dir,
                 checkpointer=self._checkpointer,
+                input_tokens_hint=self._status_last_input_tokens,
             )
 
-            if await cmd_manager.execute(command, ctx):
-                return
+            try:
+                if await cmd_manager.execute(command, ctx):
+                    # Do NOT invalidate the usage baseline after /compact.
+                    # build_session_status_snapshot() only counts raw checkpoint
+                    # messages (~46 tokens) and misses system prompt + tool
+                    # definitions (~50K overhead). The stale pre-compact count
+                    # is far more accurate; the next LLM call will correct it.
+                    await self._refresh_status_snapshot(
+                        reset_streaming_text=True,
+                    )
+                    return
 
-            self._append_system(f"Unknown command: {command}", style="yellow")
+                self._append_system(f"Unknown command: {command}", style="yellow")
+                self._render_status()
+            finally:
+                self._busy = False
+                prompt_widget.disabled = False
+                prompt_widget.focus()
 
         async def _render_history(self, thread_id_value: str) -> None:
             """Render conversation history from a saved thread.
@@ -2074,6 +2220,85 @@ def action_request_quit(self) -> None:
 
         # ── Banner & status ────────────────────────────────────
 
+        async def _refresh_status_snapshot(
+            self,
+            pending_user_text: str | None = None,
+            *,
+            reset_streaming_text: bool = True,
+        ) -> None:
+            """Recompute persistent status metrics for the active thread."""
+            pending = (pending_user_text or "").strip()
+            if pending:
+                if self._status_last_input_tokens is not None:
+                    self._status_base_snapshot = apply_user_text_to_snapshot(
+                        make_usage_status_snapshot(
+                            self._status_last_input_tokens,
+                            model_name=model,
+                        ),
+                        pending,
+                    )
+                else:
+                    self._status_base_snapshot = await build_session_status_snapshot(
+                        self._conversation_tid,
+                        model_name=model,
+                        pending_user_text=pending,
+                    )
+            elif self._status_last_input_tokens is not None:
+                self._status_base_snapshot = make_usage_status_snapshot(
+                    self._status_last_input_tokens,
+                    model_name=model,
+                )
+            else:
+                self._status_base_snapshot = await build_session_status_snapshot(
+                    self._conversation_tid,
+                    model_name=model,
+                )
+            if reset_streaming_text:
+                self._status_streaming_text = ""
+            self._rebuild_status_snapshot()
+
+        def _set_status_usage_baseline(self, input_tokens: int) -> None:
+            """Promote the latest real prompt usage into the status-bar base."""
+            if input_tokens <= 0:
+                return
+            self._status_last_input_tokens = input_tokens
+            self._status_base_snapshot = make_usage_status_snapshot(
+                input_tokens,
+                model_name=model,
+            )
+            self._rebuild_status_snapshot()
+
+        def update_status_after_compact(self, tokens_after: int) -> None:
+            """Update the status bar immediately after a successful /compact.
+
+            Called by CompactCommand so the bar reflects the reduced context
+            without waiting for the next LLM call.
+            """
+            if tokens_after <= 0:
+                return
+            self._status_last_input_tokens = tokens_after
+            self._status_base_snapshot = make_usage_status_snapshot(
+                tokens_after,
+                model_name=model,
+            )
+            self._rebuild_status_snapshot()
+
+        def _set_status_streaming_text(self, text: str | None) -> None:
+            """Update in-flight assistant text shown in the context bar."""
+            new_text = text or ""
+            if new_text == self._status_streaming_text:
+                return
+            self._status_streaming_text = new_text
+            self._rebuild_status_snapshot()
+
+        def _rebuild_status_snapshot(self) -> None:
+            """Compose the displayed snapshot from base state + live overlay."""
+            self._status_snapshot = apply_assistant_text_to_snapshot(
+                self._status_base_snapshot,
+                self._status_streaming_text,
+            )
+            self._render_status()
+
         def _render_welcome(self) -> None:
             channels_info: list[tuple[str, bool, str]] | None = None
             try:
@@ -2112,20 +2337,33 @@ def _render_welcome(self) -> None:
 
         def _render_status(self) -> None:
             status = self.query_one("#status", Static)
+            width = (
+                getattr(status.size, "width", 0)
+                or getattr(status.content_region, "width", 0)
+                or getattr(self.screen.size, "width", 0)
+                or 80
+            )
             if self._busy:
-                left = "vibe researching..."
-                left_style = "bold #f59e0b"
+                hint_label = "vibe researching..."
+                hint_style = f"on {STATUS_BAR_BG} {STATUS_HINT_BUSY} bold"
             else:
-                left = "/help for commands"
-                left_style = "#f59e0b"
-
-            status.update(
-                Text.assemble(
-                    (left, left_style),
-                    ("  ", ""),
-                    ("EvoScientist", "dim"),
-                )
+                hint_label = "/help for commands"
+                hint_style = f"on {STATUS_BAR_BG} {STATUS_HINT_IDLE}"
+
+            hint = Text.assemble(
+                (hint_label, hint_style),
+                (" │ ", f"on {STATUS_BAR_BG} {STATUS_DIM}"),
+            )
+            remaining_width = max(1, width - len(hint.plain))
+            metrics = build_status_text(
+                self._status_snapshot,
+                self._status_started_at,
+                remaining_width,
             )
+            line = Text(no_wrap=True, overflow="crop")
+            line.append_text(hint)
+            line.append_text(metrics)
+            status.update(line)
 
     # ── Media forwarding helper (module-level) ──────────────
 
diff --git a/EvoScientist/cli/tui_runtime.py b/EvoScientist/cli/tui_runtime.py
--- a/EvoScientist/cli/tui_runtime.py
+++ b/EvoScientist/cli/tui_runtime.py
@@ -69,6 +69,8 @@ def run_streaming(
     on_thinking: Callable[[str], None] | None = None,
     on_todo: Callable[[list[dict]], None] | None = None,
     on_file_write: Callable[[str], None] | None = None,
+    on_stream_event: Callable[[str, Any], Any] | None = None,
+    status_footer_builder: Callable[[], Any] | None = None,
     metadata: dict | None = None,
     hitl_prompt_fn: Callable[[list], list[dict] | None] | None = None,
     ask_user_prompt_fn: Callable[[dict], dict] | None = None,
@@ -85,6 +87,8 @@ def run_streaming(
             on_thinking=on_thinking,
             on_todo=on_todo,
             on_file_write=on_file_write,
+            on_stream_event=on_stream_event,
+            status_footer_builder=status_footer_builder,
             metadata=metadata,
             hitl_prompt_fn=hitl_prompt_fn,
             ask_user_prompt_fn=ask_user_prompt_fn,
@@ -104,6 +108,8 @@ def run_streaming(
                 on_thinking=on_thinking,
                 on_todo=on_todo,
                 on_file_write=on_file_write,
+                on_stream_event=on_stream_event,
+                status_footer_builder=status_footer_builder,
                 metadata=metadata,
                 hitl_prompt_fn=hitl_prompt_fn,
                 ask_user_prompt_fn=ask_user_prompt_fn,
diff --git a/EvoScientist/cli/widgets/__init__.py b/EvoScientist/cli/widgets/__init__.py
--- a/EvoScientist/cli/widgets/__init__.py
+++ b/EvoScientist/cli/widgets/__init__.py
@@ -3,6 +3,8 @@
 from .approval_widget import ApprovalWidget
 from .ask_user_widget import AskUserWidget
 from .assistant_message import AssistantMessage
+from .compact_summary_widget import CompactSummaryWidget
+from .compacting_widget import CompactingWidget
 from .loading_widget import LoadingWidget
 from .subagent_widget import SubAgentWidget
 from .summarization_widget import SummarizationWidget
@@ -18,6 +20,8 @@
     "ApprovalWidget",
     "AskUserWidget",
     "AssistantMessage",
+    "CompactSummaryWidget",
+    "CompactingWidget",
     "LoadingWidget",
     "SubAgentWidget",
     "SummarizationWidget",
diff --git a/EvoScientist/cli/widgets/compact_summary_widget.py b/EvoScientist/cli/widgets/compact_summary_widget.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/cli/widgets/compact_summary_widget.py
@@ -0,0 +1,72 @@
+"""Collapsible widget for manual /compact summary results."""
+
+from __future__ import annotations
+
+from rich.panel import Panel
+from rich.text import Text
+from textual.events import Click
+from textual.widgets import Static
+
+_MAX_COLLAPSED_CHARS = 80
+_MAX_EXPANDED_CHARS = 3000
+
+
+class CompactSummaryWidget(Static):
+    """Collapsible panel showing the generated manual compact summary."""
+
+    DEFAULT_CSS = """
+    CompactSummaryWidget {
+        height: auto;
+        margin: 0 0 1 0;
+    }
+    """
+
+    def __init__(self, summary_text: str) -> None:
+        super().__init__("")
+        self._content = (summary_text or "").strip()
+        self._collapsed = True
+        self._refresh_display()
+
+    def _char_count_label(self) -> str:
+        n = len(self._content)
+        if n >= 1000:
+            return f"{n / 1000:.1f}k chars"
+        return f"{n:,} chars"
+
+    def _refresh_display(self) -> None:
+        if not self._content:
+            self.update(
+                Panel(
+                    Text("(empty summary)", style="dim"),
+                    title="Context Compacted",
+                    border_style="#f59e0b",
+                    padding=(0, 1),
+                )
+            )
+            return
+
+        if self._collapsed:
+            title = f"Context Compacted ({self._char_count_label()})"
+            first_line = self._content.strip().split("\n")[0].strip()
+            if len(first_line) > _MAX_COLLAPSED_CHARS:
+                first_line = first_line[: _MAX_COLLAPSED_CHARS - 3] + "..."
+            preview = Text(first_line, style="dim italic")
+            preview.append("  [click to expand]", style="dim italic")
+            body = preview
+        else:
+            title = f"Context Compacted ({self._char_count_label()})"
+            display = self._content.rstrip()
+            if len(display) > _MAX_EXPANDED_CHARS:
+                half = _MAX_EXPANDED_CHARS // 2
+                display = (
+                    display[:half] + "\n\n... (truncated) ...\n\n" + display[-half:]
+                )
+            body = Text(display, style="dim italic")
+
+        self.update(Panel(body, title=title, border_style="#f59e0b", padding=(0, 1)))
+
+    def on_click(self, event: Click) -> None:
+        """Toggle collapsed/expanded state."""
+        if self._content:
+            self._collapsed = not self._collapsed
+            self._refresh_display()
diff --git a/EvoScientist/cli/widgets/compacting_widget.py b/EvoScientist/cli/widgets/compacting_widget.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/cli/widgets/compacting_widget.py
@@ -0,0 +1,30 @@
+"""Transient widget shown while manual /compact is running in the TUI."""
+
+from __future__ import annotations
+
+from .timed_status_widget import TimedStatusWidget
+
+
+class CompactingWidget(TimedStatusWidget):
+    """Timer-backed status line for an in-progress manual compact."""
+
+    DEFAULT_CSS = """
+    CompactingWidget {
+        height: auto;
+        color: #f59e0b;
+        padding: 0 0;
+        margin: 0 0 1 0;
+    }
+    """
+
+    def __init__(self) -> None:
+        super().__init__()
+
+    def _refresh_display(self) -> None:
+        self.update(f"Compacting conversation... ({self.elapsed_seconds}s)")
+
+    async def cleanup(self) -> None:
+        """Stop timer and remove from DOM."""
+        self._stop_timer()
+        if self.is_mounted:
+            await self.remove()
diff --git a/EvoScientist/cli/widgets/loading_widget.py b/EvoScientist/cli/widgets/loading_widget.py
--- a/EvoScientist/cli/widgets/loading_widget.py
+++ b/EvoScientist/cli/widgets/loading_widget.py
@@ -2,12 +2,12 @@
 
 from __future__ import annotations
 
-from textual.widgets import Static
+from .timed_status_widget import TimedStatusWidget
 
 _SPINNER_FRAMES = "\u280b\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2807\u280f"
 
 
-class LoadingWidget(Static):
+class LoadingWidget(TimedStatusWidget):
     """Spinner + 'Thinking...' with elapsed time counter.
 
     Mount when a turn starts; call ``remove()`` when the first
@@ -23,28 +23,18 @@ class LoadingWidget(Static):
     """
 
     def __init__(self) -> None:
-        super().__init__("")
+        super().__init__()
         self._frame = 0
-        self._elapsed = 0.0
-        self._timer_handle = None
-
-    def on_mount(self) -> None:
-        self._timer_handle = self.set_interval(0.1, self._tick)
-        self._refresh_display()
 
     def _tick(self) -> None:
         self._frame = (self._frame + 1) % len(_SPINNER_FRAMES)
-        self._elapsed += 0.1
-        self._refresh_display()
+        super()._tick()
 
     def _refresh_display(self) -> None:
         char = _SPINNER_FRAMES[self._frame]
-        secs = int(self._elapsed)
-        self.update(f"{char} Thinking... ({secs}s)")
+        self.update(f"{char} Thinking... ({self.elapsed_seconds}s)")
 
     async def cleanup(self) -> None:
         """Stop timer and remove from DOM."""
-        if self._timer_handle is not None:
-            self._timer_handle.stop()
-            self._timer_handle = None
+        self._stop_timer()
         await self.remove()
diff --git a/EvoScientist/cli/widgets/summarization_widget.py b/EvoScientist/cli/widgets/summarization_widget.py
--- a/EvoScientist/cli/widgets/summarization_widget.py
+++ b/EvoScientist/cli/widgets/summarization_widget.py
@@ -15,13 +15,14 @@
 from rich.panel import Panel
 from rich.text import Text
 from textual.events import Click
-from textual.widgets import Static
+
+from .timed_status_widget import TimedStatusWidget
 
 _MAX_COLLAPSED_CHARS = 80
 _MAX_EXPANDED_CHARS = 3000
 
 
-class SummarizationWidget(Static):
+class SummarizationWidget(TimedStatusWidget):
     """Collapsible panel showing context summarization.
 
     Streams text via ``append_text()`` (shows live spinner while active).
@@ -44,24 +45,28 @@ class SummarizationWidget(Static):
     """
 
     def __init__(self) -> None:
-        super().__init__("")
+        super().__init__()
         self._content = ""
         self._collapsed = True
         self._is_active = True  # still receiving chunks
 
+    def _should_tick(self) -> bool:
+        return self._is_active
+
     def _char_count_label(self) -> str:
         n = len(self._content)
         if n >= 1000:
             return f"{n / 1000:.1f}k chars"
         return f"{n:,} chars"
 
     def _refresh_display(self) -> None:
+        secs = self.elapsed_seconds
         if not self._content:
             if self._is_active:
                 self.update(
                     Panel(
                         Text("Summarizing...", style="dim italic"),
-                        title="Context Summarizing",
+                        title=f"Context Summarizing... ({secs}s)",
                         border_style="#f59e0b",
                         padding=(0, 1),
                     )
@@ -72,7 +77,7 @@ def _refresh_display(self) -> None:
 
         if self._is_active:
             # While streaming: show latest content tail (like thinking widget)
-            title = "Context Summarizing..."
+            title = f"Context Summarizing... ({secs}s)"
             tail = self._content.rstrip()
             if len(tail) > 200:
                 tail = tail[-200:]
@@ -110,6 +115,7 @@ def finalize(self) -> None:
         """Mark streaming as complete — switch to collapsed preview."""
         self._is_active = False
         self._collapsed = True
+        self._stop_timer()
         self._refresh_display()
 
     def set_content(self, text: str) -> None:
diff --git a/EvoScientist/cli/widgets/timed_status_widget.py b/EvoScientist/cli/widgets/timed_status_widget.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/cli/widgets/timed_status_widget.py
@@ -0,0 +1,49 @@
+"""Shared timer-backed base class for transient TUI status widgets."""
+
+from __future__ import annotations
+
+from textual.widgets import Static
+
+
+class TimedStatusWidget(Static):
+    """Static widget with a simple elapsed-time timer.
+
+    Subclasses implement ``_refresh_display()`` and can override
+    ``_should_tick()`` when the timer should pause after a state transition.
+    """
+
+    TICK_SECONDS = 0.1
+
+    def __init__(self) -> None:
+        super().__init__("")
+        self._elapsed = 0.0
+        self._timer_handle = None
+
+    def on_mount(self) -> None:
+        self._timer_handle = self.set_interval(self.TICK_SECONDS, self._tick)
+        self._refresh_display()
+
+    def on_unmount(self) -> None:
+        self._stop_timer()
+
+    def _tick(self) -> None:
+        if self._should_tick():
+            self._elapsed += self.TICK_SECONDS
+            self._refresh_display()
+
+    def _should_tick(self) -> bool:
+        """Return whether the timer should continue advancing."""
+        return True
+
+    def _stop_timer(self) -> None:
+        if self._timer_handle is not None:
+            self._timer_handle.stop()
+            self._timer_handle = None
+
+    @property
+    def elapsed_seconds(self) -> int:
+        return int(self._elapsed)
+
+    def _refresh_display(self) -> None:
+        """Update the widget's rendered content."""
+        raise NotImplementedError
diff --git a/EvoScientist/cli/widgets/tool_call_widget.py b/EvoScientist/cli/widgets/tool_call_widget.py
--- a/EvoScientist/cli/widgets/tool_call_widget.py
+++ b/EvoScientist/cli/widgets/tool_call_widget.py
@@ -10,7 +10,7 @@
 from textual.widgets import Static
 
 from ...stream.diff_format import build_edit_diff
-from ...stream.utils import format_tool_compact
+from ...stream.utils import format_tool_compact_with_result
 from .timestamp_mixin import show_timestamp_toast
 
 _SPINNER_FRAMES = "\u280b\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2807\u280f"
@@ -100,7 +100,11 @@ def _tick(self) -> None:
             self._render_status()
 
     def _render_header(self) -> None:
-        compact = format_tool_compact(self._tool_name, self._tool_args)
+        compact = format_tool_compact_with_result(
+            self._tool_name,
+            self._tool_args,
+            self._result_content,
+        )
         header = self.query_one(".tool-header", Static)
         line = Text()
         if self._status == "running":
diff --git a/EvoScientist/commands/base.py b/EvoScientist/commands/base.py
--- a/EvoScientist/commands/base.py
+++ b/EvoScientist/commands/base.py
@@ -55,7 +55,9 @@ class CommandContext:
     workspace_dir: str | None = None
     checkpointer: Any = None
     config: Any = None
-    # Add other fields as needed (e.g., current model, provider)
+    # Real LLM input token count from last usage_metadata (includes system
+    # prompt + tool schemas).  Used by /compact for accurate display.
+    input_tokens_hint: int | None = None
 
 
 class Command(ABC):
diff --git a/EvoScientist/commands/implementation/mcp.py b/EvoScientist/commands/implementation/mcp.py
--- a/EvoScientist/commands/implementation/mcp.py
+++ b/EvoScientist/commands/implementation/mcp.py
@@ -13,7 +13,6 @@ class MCPCommand(Command):
     description = "Manage MCP servers"
 
     async def execute(self, ctx: CommandContext, args: list[str]) -> None:
-
         if not args or args[0] == "list":
             await self._mcp_list(ctx)
             return
diff --git a/EvoScientist/commands/implementation/session.py b/EvoScientist/commands/implementation/session.py
--- a/EvoScientist/commands/implementation/session.py
+++ b/EvoScientist/commands/implementation/session.py
@@ -1,5 +1,6 @@
 from __future__ import annotations
 
+import inspect
 from typing import ClassVar
 
 from rich.table import Table
@@ -15,14 +16,53 @@ class CompactCommand(Command):
     description = "Compact conversation to free context"
 
     async def execute(self, ctx: CommandContext, args: list[str]) -> None:
-        from ...cli.commands import compact_conversation, render_compact_result
-
-        ctx.ui.append_system("Compacting conversation...")
-        result = await compact_conversation(
-            agent=ctx.agent,
-            thread_id=ctx.thread_id,
+        from ...cli.commands import (
+            build_compact_summary_renderable,
+            compact_conversation,
+            render_compact_result,
         )
+
+        start_indicator = getattr(ctx.ui, "start_compacting_indicator", None)
+        stop_indicator = getattr(ctx.ui, "stop_compacting_indicator", None)
+        using_indicator = callable(start_indicator) and callable(stop_indicator)
+
+        if using_indicator:
+            maybe = start_indicator()
+            if inspect.isawaitable(maybe):
+                await maybe
+        else:
+            ctx.ui.append_system("Compacting conversation...")
+
+        try:
+            result = await compact_conversation(
+                agent=ctx.agent,
+                thread_id=ctx.thread_id,
+                input_tokens_hint=ctx.input_tokens_hint,
+            )
+        finally:
+            if using_indicator:
+                maybe = stop_indicator()
+                if inspect.isawaitable(maybe):
+                    await maybe
+
         ctx.ui.mount_renderable(render_compact_result(result))
+        summary_renderable = build_compact_summary_renderable(result)
+        if summary_renderable is not None:
+            ctx.ui.mount_renderable(summary_renderable)
+        # Push the reduced token count to the status bar immediately so it
+        # reflects the new context without waiting for the next LLM call.
+        # Only when input_tokens_hint was available: tokens_after is then
+        # LLM-level (includes system + tool overhead), matching the unit that
+        # _status_last_input_tokens expects. Without a hint, tokens_after is
+        # message-level only and would produce a misleadingly low reading.
+        if (
+            result.status == "ok"
+            and result.tokens_after > 0
+            and ctx.input_tokens_hint is not None
+        ):
+            update_fn = getattr(ctx.ui, "update_status_after_compact", None)
+            if callable(update_fn):
+                update_fn(result.tokens_after)
 
 
 class ThreadsCommand(Command):
@@ -89,7 +129,6 @@ class ResumeCommand(Command):
     ]
 
     async def execute(self, ctx: CommandContext, args: list[str]) -> None:
-
         from ...sessions import (
             get_thread_metadata,
             list_threads,
diff --git a/EvoScientist/config/onboard.py b/EvoScientist/config/onboard.py
--- a/EvoScientist/config/onboard.py
+++ b/EvoScientist/config/onboard.py
@@ -2035,7 +2035,7 @@ def _step_mcp_servers() -> list[str]:
     all_installed = all(srv.name in existing_config for srv in servers)
     if all_installed:
         console.print(
-            "  [green]\u2713 All recommended MCP servers are already configured.[/green]"
+            "[green]\u2713 All recommended MCP servers are already configured.[/green]"
         )
         return []
 
diff --git a/EvoScientist/config/settings.py b/EvoScientist/config/settings.py
--- a/EvoScientist/config/settings.py
+++ b/EvoScientist/config/settings.py
@@ -194,6 +194,7 @@ class EvoScientistConfig:
 
     # HITL (Human-in-the-Loop) Settings
     auto_approve: bool = False  # Auto-approve all tool executions without prompting
+    auto_mode: bool = False  # Run unattended: imply auto_approve and disable ask_user
     shell_allow_list: str = ""  # Comma-separated shell command prefixes to auto-approve
 
     # Agent features
diff --git a/EvoScientist/llm/__init__.py b/EvoScientist/llm/__init__.py
--- a/EvoScientist/llm/__init__.py
+++ b/EvoScientist/llm/__init__.py
@@ -4,6 +4,11 @@
 with support for multiple providers.
 """
 
+from .context_window import (
+    DEFAULT_CONTEXT_WINDOW_FALLBACK,
+    get_context_window,
+    resolve_context_window,
+)
 from .models import (
     DEFAULT_MODEL,
     MODELS,
@@ -14,10 +19,13 @@
 )
 
 __all__ = [
+    "DEFAULT_CONTEXT_WINDOW_FALLBACK",
     "DEFAULT_MODEL",
     "MODELS",
     "get_chat_model",
+    "get_context_window",
     "get_model_info",
     "get_models_for_provider",
     "list_models",
+    "resolve_context_window",
 ]
diff --git a/EvoScientist/llm/context_window.py b/EvoScientist/llm/context_window.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/llm/context_window.py
@@ -0,0 +1,81 @@
+"""Helpers for resolving model context windows across LangChain providers."""
+
+from __future__ import annotations
+
+from collections.abc import Mapping
+from typing import Any
+
+DEFAULT_CONTEXT_WINDOW_FALLBACK = 200_000
+
+_DIRECT_WINDOW_ATTRS = (
+    "context_window",
+    "context_length",
+    "num_ctx",
+    "max_input_tokens",
+)
+_CONTAINER_ATTRS = (
+    "profile",
+    "context_management",
+    "model_kwargs",
+    "metadata",
+)
+
+
+def _coerce_positive_int(value: Any) -> int | None:
+    """Best-effort coercion for positive integer-like values."""
+    if isinstance(value, bool) or value is None:
+        return None
+    if isinstance(value, int):
+        return value if value > 0 else None
+    if isinstance(value, float):
+        if value > 0 and value.is_integer():
+            return int(value)
+        return None
+    if isinstance(value, str):
+        normalized = value.strip().replace(",", "").replace("_", "")
+        if normalized.isdigit():
+            parsed = int(normalized)
+            return parsed if parsed > 0 else None
+    return None
+
+
+def _resolve_from_mapping(mapping: Mapping[str, Any]) -> int | None:
+    """Resolve a context window from a metadata mapping."""
+    for key in _DIRECT_WINDOW_ATTRS:
+        if key in mapping:
+            resolved = _coerce_positive_int(mapping.get(key))
+            if resolved is not None:
+                return resolved
+    return None
+
+
+def get_context_window(model_obj: Any | None) -> int | None:
+    """Return the best available context-window value from a model object."""
+    if model_obj is None:
+        return None
+
+    for attr in _DIRECT_WINDOW_ATTRS:
+        resolved = _coerce_positive_int(getattr(model_obj, attr, None))
+        if resolved is not None:
+            return resolved
+
+    for attr in _CONTAINER_ATTRS:
+        candidate = getattr(model_obj, attr, None)
+        if isinstance(candidate, Mapping):
+            resolved = _resolve_from_mapping(candidate)
+            if resolved is not None:
+                return resolved
+
+    return None
+
+
+def resolve_context_window(
+    model_obj: Any | None,
+    *,
+    fallback: int = DEFAULT_CONTEXT_WINDOW_FALLBACK,
+) -> int:
+    """Resolve a usable context window with a stable fallback."""
+    resolved = get_context_window(model_obj)
+    if resolved is not None:
+        return resolved
+    return fallback
diff --git a/EvoScientist/llm/models.py b/EvoScientist/llm/models.py
--- a/EvoScientist/llm/models.py
+++ b/EvoScientist/llm/models.py
@@ -80,16 +80,16 @@
     ("claude-sonnet-4-5", "claude-sonnet-4-5", "anthropic"),
     ("claude-haiku-4-5", "claude-haiku-4-5", "anthropic"),
     # OpenAI
-    ("gpt-5.4", "gpt-5.4-2026-03-05", "openai"),
+    ("gpt-5.4", "gpt-5.4", "openai"),
     ("gpt-5.4-mini", "gpt-5.4-mini", "openai"),
     ("gpt-5.4-nano", "gpt-5.4-nano", "openai"),
     ("gpt-5.3-codex", "gpt-5.3-codex", "openai"),
     ("gpt-5.2-codex", "gpt-5.2-codex", "openai"),
-    ("gpt-5.2", "gpt-5.2-2025-12-11", "openai"),
-    ("gpt-5.1", "gpt-5.1-2025-11-13", "openai"),
-    ("gpt-5", "gpt-5-2025-08-07", "openai"),
-    ("gpt-5-mini", "gpt-5-mini-2025-08-07", "openai"),
-    ("gpt-5-nano", "gpt-5-nano-2025-08-07", "openai"),
+    ("gpt-5.2", "gpt-5.2", "openai"),
+    ("gpt-5.1", "gpt-5.1", "openai"),
+    ("gpt-5", "gpt-5", "openai"),
+    ("gpt-5-mini", "gpt-5-mini", "openai"),
+    ("gpt-5-nano", "gpt-5-nano", "openai"),
     # Google GenAI
     ("gemini-3.1-pro", "gemini-3.1-pro-preview", "google-genai"),
     (
diff --git a/EvoScientist/middleware/context_editing.py b/EvoScientist/middleware/context_editing.py
--- a/EvoScientist/middleware/context_editing.py
+++ b/EvoScientist/middleware/context_editing.py
@@ -15,6 +15,8 @@
 
 from langchain_core.language_models import BaseChatModel
 
+from ..llm.context_window import get_context_window
+
 
 def compute_context_editing_trigger(
     model: BaseChatModel,
@@ -23,18 +25,13 @@ def compute_context_editing_trigger(
 ) -> int:
     """Compute ClearToolUsesEdit trigger based on model context window.
 
-    Uses 50% of ``max_input_tokens`` when a model profile is available,
-    otherwise falls back to a fixed token count.  This fires well before
-    ``SummarizationMiddleware`` (~85% / 170k).
+    Uses 50% of the best available model context window when metadata is
+    available, otherwise falls back to a fixed token count. This fires well
+    before ``SummarizationMiddleware`` (~85% / 170k).
     """
-    profile = getattr(model, "profile", None)
-    if (
-        profile is not None
-        and isinstance(profile, dict)
-        and isinstance(profile.get("max_input_tokens"), int)
-        and profile["max_input_tokens"] > 0
-    ):
-        return int(profile["max_input_tokens"] * fraction)
+    context_window = get_context_window(model)
+    if context_window is not None and context_window > 0:
+        return max(1, int(context_window * fraction))
     return fallback
 
 
diff --git a/EvoScientist/sessions.py b/EvoScientist/sessions.py
--- a/EvoScientist/sessions.py
+++ b/EvoScientist/sessions.py
@@ -112,22 +112,60 @@ async def _load_checkpoint_messages(
 
     Returns a list of LangChain message objects, or an empty list on failure.
     """
+    channel_values = await _load_checkpoint_channel_values(conn, thread_id, serde)
+    messages = channel_values.get("messages", [])
+    if not isinstance(messages, list):
+        return []
+    event = channel_values.get("_summarization_event")
+    return _apply_summarization_event(
+        messages, event if isinstance(event, dict) else None
+    )
+
+
+async def _load_checkpoint_channel_values(
+    conn: aiosqlite.Connection,
+    thread_id: str,
+    serde: JsonPlusSerializer,
+) -> dict:
+    """Load channel_values from the most recent checkpoint for *thread_id*."""
     query = """
         SELECT type, checkpoint
         FROM checkpoints
         WHERE thread_id = ?
+          AND json_extract(metadata, '$.agent_name') = ?
         ORDER BY checkpoint_id DESC
         LIMIT 1
     """
-    async with conn.execute(query, (thread_id,)) as cur:
+    async with conn.execute(query, (thread_id, AGENT_NAME)) as cur:
         row = await cur.fetchone()
         if not row or not row[0] or not row[1]:
-            return []
+            return {}
         try:
             data = serde.loads_typed((row[0], row[1]))
-            return data.get("channel_values", {}).get("messages", [])
+            channel_values = data.get("channel_values", {})
+            return channel_values if isinstance(channel_values, dict) else {}
         except (ValueError, TypeError, KeyError):
-            return []
+            return {}
+
+
+def _apply_summarization_event(messages: list, event: dict | None) -> list:
+    """Return the effective message list after applying a summarization event."""
+    if not event:
+        return list(messages)
+
+    try:
+        summary_message = event["summary_message"]
+        cutoff_index = int(event["cutoff_index"])
+    except (KeyError, TypeError, ValueError):
+        return list(messages)
+
+    if summary_message is None:
+        return list(messages)
+
+    if cutoff_index < 0 or cutoff_index > len(messages):
+        return list(messages)
+
+    return [summary_message, *messages[cutoff_index:]]
 
 
 async def _count_messages(
@@ -375,4 +413,7 @@ async def get_thread_messages(thread_id: str) -> list:
             if not await cur.fetchone():
                 return []
         serde = JsonPlusSerializer()
-        return await _load_checkpoint_messages(conn, thread_id, serde)
+        channel_values = await _load_checkpoint_channel_values(conn, thread_id, serde)
+        messages = channel_values.get("messages", [])
+        event = channel_values.get("_summarization_event")
+        return _apply_summarization_event(messages, event)
diff --git a/EvoScientist/skills/skill-creator/eval-viewer/generate_review.py b/EvoScientist/skills/skill-creator/eval-viewer/generate_review.py
--- a/EvoScientist/skills/skill-creator/eval-viewer/generate_review.py
+++ b/EvoScientist/skills/skill-creator/eval-viewer/generate_review.py
@@ -24,17 +24,40 @@
 import time
 import webbrowser
 from functools import partial
-from http.server import HTTPServer, BaseHTTPRequestHandler
+from http.server import BaseHTTPRequestHandler, HTTPServer
 from pathlib import Path
 
 # Files to exclude from output listings
 METADATA_FILES = {"transcript.md", "user_notes.md", "metrics.json"}
 
 # Extensions we render as inline text
 TEXT_EXTENSIONS = {
-    ".txt", ".md", ".json", ".csv", ".py", ".js", ".ts", ".tsx", ".jsx",
-    ".yaml", ".yml", ".xml", ".html", ".css", ".sh", ".rb", ".go", ".rs",
-    ".java", ".c", ".cpp", ".h", ".hpp", ".sql", ".r", ".toml",
+    ".txt",
+    ".md",
+    ".json",
+    ".csv",
+    ".py",
+    ".js",
+    ".ts",
+    ".tsx",
+    ".jsx",
+    ".yaml",
+    ".yml",
+    ".xml",
+    ".html",
+    ".css",
+    ".sh",
+    ".rb",
+    ".go",
+    ".rs",
+    ".java",
+    ".c",
+    ".cpp",
+    ".h",
+    ".hpp",
+    ".sql",
+    ".r",
+    ".toml",
 }
 
 # Extensions we render as inline images
@@ -88,7 +111,10 @@ def build_run(root: Path, run_dir: Path) -> dict | None:
     eval_id = None
 
     # Try eval_metadata.json
-    for candidate in [run_dir / "eval_metadata.json", run_dir.parent / "eval_metadata.json"]:
+    for candidate in [
+        run_dir / "eval_metadata.json",
+        run_dir.parent / "eval_metadata.json",
+    ]:
         if candidate.exists():
             try:
                 metadata = json.loads(candidate.read_text())
@@ -101,7 +127,10 @@ def build_run(root: Path, run_dir: Path) -> dict | None:
 
     # Fall back to transcript.md
     if not prompt:
-        for candidate in [run_dir / "transcript.md", run_dir / "outputs" / "transcript.md"]:
+        for candidate in [
+            run_dir / "transcript.md",
+            run_dir / "outputs" / "transcript.md",
+        ]:
             if candidate.exists():
                 try:
                     text = candidate.read_text()
@@ -166,7 +195,11 @@ def embed_file(path: Path) -> dict:
             raw = path.read_bytes()
             b64 = base64.b64encode(raw).decode("ascii")
         except OSError:
-            return {"name": path.name, "type": "error", "content": "(Error reading file)"}
+            return {
+                "name": path.name,
+                "type": "error",
+                "content": "(Error reading file)",
+            }
         return {
             "name": path.name,
             "type": "image",
@@ -178,7 +211,11 @@ def embed_file(path: Path) -> dict:
             raw = path.read_bytes()
             b64 = base64.b64encode(raw).decode("ascii")
         except OSError:
-            return {"name": path.name, "type": "error", "content": "(Error reading file)"}
+            return {
+                "name": path.name,
+                "type": "error",
+                "content": "(Error reading file)",
+            }
         return {
             "name": path.name,
             "type": "pdf",
@@ -189,7 +226,11 @@ def embed_file(path: Path) -> dict:
             raw = path.read_bytes()
             b64 = base64.b64encode(raw).decode("ascii")
         except OSError:
-            return {"name": path.name, "type": "error", "content": "(Error reading file)"}
+            return {
+                "name": path.name,
+                "type": "error",
+                "content": "(Error reading file)",
+            }
         return {
             "name": path.name,
             "type": "xlsx",
@@ -201,7 +242,11 @@ def embed_file(path: Path) -> dict:
             raw = path.read_bytes()
             b64 = base64.b64encode(raw).decode("ascii")
         except OSError:
-            return {"name": path.name, "type": "error", "content": "(Error reading file)"}
+            return {
+                "name": path.name,
+                "type": "error",
+                "content": "(Error reading file)",
+            }
         return {
             "name": path.name,
             "type": "binary",
@@ -278,19 +323,24 @@ def generate_html(
 
     data_json = json.dumps(embedded)
 
-    return template.replace("/*__EMBEDDED_DATA__*/", f"const EMBEDDED_DATA = {data_json};")
+    return template.replace(
+        "/*__EMBEDDED_DATA__*/", f"const EMBEDDED_DATA = {data_json};"
+    )
 
 
 # ---------------------------------------------------------------------------
 # HTTP server (stdlib only, zero dependencies)
 # ---------------------------------------------------------------------------
 
+
 def _kill_port(port: int) -> None:
     """Kill any process listening on the given port."""
     try:
         result = subprocess.run(
             ["lsof", "-ti", f":{port}"],
-            capture_output=True, text=True, timeout=5,
+            capture_output=True,
+            text=True,
+            timeout=5,
         )
         for pid_str in result.stdout.strip().split("\n"):
             if pid_str.strip():
@@ -305,6 +355,7 @@ def _kill_port(port: int) -> None:
     except FileNotFoundError:
         print("Note: lsof not found, cannot check if port is in use", file=sys.stderr)
 
+
 class ReviewHandler(BaseHTTPRequestHandler):
     """Serves the review HTML and handles feedback saves.
 
@@ -387,18 +438,29 @@ def log_message(self, format: str, *args: object) -> None:
 def main() -> None:
     parser = argparse.ArgumentParser(description="Generate and serve eval review")
     parser.add_argument("workspace", type=Path, help="Path to workspace directory")
-    parser.add_argument("--port", "-p", type=int, default=3117, help="Server port (default: 3117)")
-    parser.add_argument("--skill-name", "-n", type=str, default=None, help="Skill name for header")
     parser.add_argument(
-        "--previous-workspace", type=Path, default=None,
+        "--port", "-p", type=int, default=3117, help="Server port (default: 3117)"
+    )
+    parser.add_argument(
+        "--skill-name", "-n", type=str, default=None, help="Skill name for header"
+    )
+    parser.add_argument(
+        "--previous-workspace",
+        type=Path,
+        default=None,
         help="Path to previous iteration's workspace (shows old outputs and feedback as context)",
     )
     parser.add_argument(
-        "--benchmark", type=Path, default=None,
+        "--benchmark",
+        type=Path,
+        default=None,
         help="Path to benchmark.json to show in the Benchmark tab",
     )
     parser.add_argument(
-        "--static", "-s", type=Path, default=None,
+        "--static",
+        "-s",
+        type=Path,
+        default=None,
         help="Write standalone HTML to this path instead of starting a server",
     )
     args = parser.parse_args()
@@ -438,7 +500,9 @@ def main() -> None:
     # Kill any existing process on the target port
     port = args.port
     _kill_port(port)
-    handler = partial(ReviewHandler, workspace, skill_name, feedback_path, previous, benchmark_path)
+    handler = partial(
+        ReviewHandler, workspace, skill_name, feedback_path, previous, benchmark_path
+    )
     try:
         server = HTTPServer(("127.0.0.1", port), handler)
     except OSError:
diff --git a/EvoScientist/skills/skill-creator/scripts/aggregate_benchmark.py b/EvoScientist/skills/skill-creator/scripts/aggregate_benchmark.py
--- a/EvoScientist/skills/skill-creator/scripts/aggregate_benchmark.py
+++ b/EvoScientist/skills/skill-creator/scripts/aggregate_benchmark.py
@@ -38,7 +38,7 @@
 import json
 import math
 import sys
-from datetime import datetime, timezone
+from datetime import UTC, datetime
 from pathlib import Path
 
 
@@ -60,7 +60,7 @@ def calculate_stats(values: list[float]) -> dict:
         "mean": round(mean, 4),
         "stddev": round(stddev, 4),
         "min": round(min(values), 4),
-        "max": round(max(values), 4)
+        "max": round(max(values), 4),
     }
 
 
@@ -78,7 +78,9 @@ def load_run_results(benchmark_dir: Path) -> dict:
     elif list(benchmark_dir.glob("eval-*")):
         search_dir = benchmark_dir
     else:
-        print(f"No eval directories found in {benchmark_dir} or {benchmark_dir / 'runs'}")
+        print(
+            f"No eval directories found in {benchmark_dir} or {benchmark_dir / 'runs'}"
+        )
         return {}
 
     results: dict[str, list] = {}
@@ -141,7 +143,9 @@ def load_run_results(benchmark_dir: Path) -> dict:
                     try:
                         with open(timing_file) as tf:
                             timing_data = json.load(tf)
-                        result["time_seconds"] = timing_data.get("total_duration_seconds", 0.0)
+                        result["time_seconds"] = timing_data.get(
+                            "total_duration_seconds", 0.0
+                        )
                         result["tokens"] = timing_data.get("total_tokens", 0)
                     except json.JSONDecodeError:
                         pass
@@ -157,7 +161,9 @@ def load_run_results(benchmark_dir: Path) -> dict:
                 raw_expectations = grading.get("expectations", [])
                 for exp in raw_expectations:
                     if "text" not in exp or "passed" not in exp:
-                        print(f"Warning: expectation in {grading_file} missing required fields (text, passed, evidence): {exp}")
+                        print(
+                            f"Warning: expectation in {grading_file} missing required fields (text, passed, evidence): {exp}"
+                        )
                 result["expectations"] = raw_expectations
 
                 # Extract notes from user_notes_summary
@@ -189,7 +195,7 @@ def aggregate_results(results: dict) -> dict:
             run_summary[config] = {
                 "pass_rate": {"mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0},
                 "time_seconds": {"mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0},
-                "tokens": {"mean": 0, "stddev": 0, "min": 0, "max": 0}
+                "tokens": {"mean": 0, "stddev": 0, "min": 0, "max": 0},
             }
             continue
 
@@ -200,7 +206,7 @@ def aggregate_results(results: dict) -> dict:
         run_summary[config] = {
             "pass_rate": calculate_stats(pass_rates),
             "time_seconds": calculate_stats(times),
-            "tokens": calculate_stats(tokens)
+            "tokens": calculate_stats(tokens),
         }
 
     # Calculate delta between the first two configs (if two exist)
@@ -211,20 +217,28 @@ def aggregate_results(results: dict) -> dict:
         primary = run_summary.get(configs[0], {}) if configs else {}
         baseline = {}
 
-    delta_pass_rate = primary.get("pass_rate", {}).get("mean", 0) - baseline.get("pass_rate", {}).get("mean", 0)
-    delta_time = primary.get("time_seconds", {}).get("mean", 0) - baseline.get("time_seconds", {}).get("mean", 0)
-    delta_tokens = primary.get("tokens", {}).get("mean", 0) - baseline.get("tokens", {}).get("mean", 0)
+    delta_pass_rate = primary.get("pass_rate", {}).get("mean", 0) - baseline.get(
+        "pass_rate", {}
+    ).get("mean", 0)
+    delta_time = primary.get("time_seconds", {}).get("mean", 0) - baseline.get(
+        "time_seconds", {}
+    ).get("mean", 0)
+    delta_tokens = primary.get("tokens", {}).get("mean", 0) - baseline.get(
+        "tokens", {}
+    ).get("mean", 0)
 
     run_summary["delta"] = {
         "pass_rate": f"{delta_pass_rate:+.2f}",
         "time_seconds": f"{delta_time:+.1f}",
-        "tokens": f"{delta_tokens:+.0f}"
+        "tokens": f"{delta_tokens:+.0f}",
     }
 
     return run_summary
 
 
-def generate_benchmark(benchmark_dir: Path, skill_name: str = "", skill_path: str = "") -> dict:
+def generate_benchmark(
+    benchmark_dir: Path, skill_name: str = "", skill_path: str = ""
+) -> dict:
     """
     Generate complete benchmark.json from run results.
     """
@@ -235,46 +249,44 @@ def generate_benchmark(benchmark_dir: Path, skill_name: str = "", skill_path: st
     runs = []
     for config in results:
         for result in results[config]:
-            runs.append({
-                "eval_id": result["eval_id"],
-                "configuration": config,
-                "run_number": result["run_number"],
-                "result": {
-                    "pass_rate": result["pass_rate"],
-                    "passed": result["passed"],
-                    "failed": result["failed"],
-                    "total": result["total"],
-                    "time_seconds": result["time_seconds"],
-                    "tokens": result.get("tokens", 0),
-                    "tool_calls": result.get("tool_calls", 0),
-                    "errors": result.get("errors", 0)
-                },
-                "expectations": result["expectations"],
-                "notes": result["notes"]
-            })
+            runs.append(
+                {
+                    "eval_id": result["eval_id"],
+                    "configuration": config,
+                    "run_number": result["run_number"],
+                    "result": {
+                        "pass_rate": result["pass_rate"],
+                        "passed": result["passed"],
+                        "failed": result["failed"],
+                        "total": result["total"],
+                        "time_seconds": result["time_seconds"],
+                        "tokens": result.get("tokens", 0),
+                        "tool_calls": result.get("tool_calls", 0),
+                        "errors": result.get("errors", 0),
+                    },
+                    "expectations": result["expectations"],
+                    "notes": result["notes"],
+                }
+            )
 
     # Determine eval IDs from results
-    eval_ids = sorted(set(
-        r["eval_id"]
-        for config in results.values()
-        for r in config
-    ))
+    eval_ids = sorted({r["eval_id"] for config in results.values() for r in config})
 
     benchmark = {
         "metadata": {
             "skill_name": skill_name or "<skill-name>",
             "skill_path": skill_path or "<path/to/skill>",
             "executor_model": "<model-name>",
             "analyzer_model": "<model-name>",
-            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
+            "timestamp": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
             "evals_run": eval_ids,
             "runs_per_configuration": {
                 config: len(runs) for config, runs in results.items() if runs
-            }
+            },
         },
         "runs": runs,
         "run_summary": run_summary,
-        "notes": []  # To be filled by analyzer
+        "notes": [],  # To be filled by analyzer
     }
 
     return benchmark
@@ -325,25 +337,27 @@ def generate_markdown(benchmark: dict) -> str:
     # Format pass rate
     a_pr = a_summary.get("pass_rate", {})
     b_pr = b_summary.get("pass_rate", {})
-    lines.append(f"| Pass Rate | {a_pr.get('mean', 0)*100:.0f}% ± {a_pr.get('stddev', 0)*100:.0f}% | {b_pr.get('mean', 0)*100:.0f}% ± {b_pr.get('stddev', 0)*100:.0f}% | {delta.get('pass_rate', '—')} |")
+    lines.append(
+        f"| Pass Rate | {a_pr.get('mean', 0) * 100:.0f}% ± {a_pr.get('stddev', 0) * 100:.0f}% | {b_pr.get('mean', 0) * 100:.0f}% ± {b_pr.get('stddev', 0) * 100:.0f}% | {delta.get('pass_rate', '—')} |"
+    )
 
     # Format time
     a_time = a_summary.get("time_seconds", {})
     b_time = b_summary.get("time_seconds", {})
-    lines.append(f"| Time | {a_time.get('mean', 0):.1f}s ± {a_time.get('stddev', 0):.1f}s | {b_time.get('mean', 0):.1f}s ± {b_time.get('stddev', 0):.1f}s | {delta.get('time_seconds', '—')}s |")
+    lines.append(
+        f"| Time | {a_time.get('mean', 0):.1f}s ± {a_time.get('stddev', 0):.1f}s | {b_time.get('mean', 0):.1f}s ± {b_time.get('stddev', 0):.1f}s | {delta.get('time_seconds', '—')}s |"
+    )
 
     # Format tokens
     a_tokens = a_summary.get("tokens", {})
     b_tokens = b_summary.get("tokens", {})
-    lines.append(f"| Tokens | {a_tokens.get('mean', 0):.0f} ± {a_tokens.get('stddev', 0):.0f} | {b_tokens.get('mean', 0):.0f} ± {b_tokens.get('stddev', 0):.0f} | {delta.get('tokens', '—')} |")
+    lines.append(
+        f"| Tokens | {a_tokens.get('mean', 0):.0f} ± {a_tokens.get('stddev', 0):.0f} | {b_tokens.get('mean', 0):.0f} ± {b_tokens.get('stddev', 0):.0f} | {delta.get('tokens', '—')} |"
+    )
 
     # Notes section
     if benchmark.get("notes"):
-        lines.extend([
-            "",
-            "## Notes",
-            ""
-        ])
+        lines.extend(["", "## Notes", ""])
         for note in benchmark["notes"]:
             lines.append(f"- {note}")
 
@@ -355,24 +369,19 @@ def main():
         description="Aggregate benchmark run results into summary statistics"
     )
     parser.add_argument(
-        "benchmark_dir",
-        type=Path,
-        help="Path to the benchmark directory"
+        "benchmark_dir", type=Path, help="Path to the benchmark directory"
     )
     parser.add_argument(
-        "--skill-name",
-        default="",
-        help="Name of the skill being benchmarked"
+        "--skill-name", default="", help="Name of the skill being benchmarked"
     )
     parser.add_argument(
-        "--skill-path",
-        default="",
-        help="Path to the skill being benchmarked"
+        "--skill-path", default="", help="Path to the skill being benchmarked"
     )
     parser.add_argument(
-        "--output", "-o",
+        "--output",
+        "-o",
         type=Path,
-        help="Output path for benchmark.json (default: <benchmark_dir>/benchmark.json)"
+        help="Output path for benchmark.json (default: <benchmark_dir>/benchmark.json)",
     )
 
     args = parser.parse_args()
@@ -408,7 +417,7 @@ def main():
     for config in configs:
         pr = run_summary[config]["pass_rate"]["mean"]
         label = config.replace("_", " ").title()
-        print(f"  {label}: {pr*100:.1f}% pass rate")
+        print(f"  {label}: {pr * 100:.1f}% pass rate")
     print(f"  Delta:         {delta.get('pass_rate', '—')}")
 
 
diff --git a/EvoScientist/skills/skill-creator/scripts/generate_report.py b/EvoScientist/skills/skill-creator/scripts/generate_report.py
--- a/EvoScientist/skills/skill-creator/scripts/generate_report.py
+++ b/EvoScientist/skills/skill-creator/scripts/generate_report.py
@@ -23,18 +23,32 @@ def generate_html(data: dict, auto_refresh: bool = False, skill_name: str = "")
     test_queries: list[dict] = []
     if history:
         for r in history[0].get("train_results", history[0].get("results", [])):
-            train_queries.append({"query": r["query"], "should_trigger": r.get("should_trigger", True)})
+            train_queries.append(
+                {"query": r["query"], "should_trigger": r.get("should_trigger", True)}
+            )
         if history[0].get("test_results"):
             for r in history[0].get("test_results", []):
-                test_queries.append({"query": r["query"], "should_trigger": r.get("should_trigger", True)})
-
-    refresh_tag = '    <meta http-equiv="refresh" content="5">\n' if auto_refresh else ""
-
-    html_parts = ["""<!DOCTYPE html>
+                test_queries.append(
+                    {
+                        "query": r["query"],
+                        "should_trigger": r.get("should_trigger", True),
+                    }
+                )
+
+    refresh_tag = (
+        '    <meta http-equiv="refresh" content="5">\n' if auto_refresh else ""
+    )
+
+    html_parts = [
+        """<!DOCTYPE html>
 <html>
 <head>
     <meta charset="utf-8">
-""" + refresh_tag + """    <title>""" + title_prefix + """Skill Description Optimization</title>
+"""
+        + refresh_tag
+        + """    <title>"""
+        + title_prefix
+        + """Skill Description Optimization</title>
     <link rel="preconnect" href="https://fonts.googleapis.com">
     <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
     <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@500;600&family=Lora:wght@400;500&display=swap" rel="stylesheet">
@@ -145,20 +159,23 @@ def generate_html(data: dict, auto_refresh: bool = False, skill_name: str = "")
     </style>
 </head>
 <body>
-    <h1>""" + title_prefix + """Skill Description Optimization</h1>
+    <h1>"""
+        + title_prefix
+        + """Skill Description Optimization</h1>
     <div class="explainer">
         <strong>Optimizing your skill's description.</strong> This page updates automatically as Claude tests different versions of your skill's description. Each row is an iteration — a new description attempt. The columns show test queries: green checkmarks mean the skill triggered correctly (or correctly didn't trigger), red crosses mean it got it wrong. The "Train" score shows performance on queries used to improve the description; the "Test" score shows performance on held-out queries the optimizer hasn't seen. When it's done, Claude will apply the best-performing description to your skill.
     </div>
-"""]
+"""
+    ]
 
     # Summary section
-    best_test_score = data.get('best_test_score')
+    best_test_score = data.get("best_test_score")
     html_parts.append(f"""
     <div class="summary">
-        <p><strong>Original:</strong> {html.escape(data.get('original_description', 'N/A'))}</p>
-        <p class="best"><strong>Best:</strong> {html.escape(data.get('best_description', 'N/A'))}</p>
-        <p><strong>Best Score:</strong> {data.get('best_score', 'N/A')} {'(test)' if best_test_score else '(train)'}</p>
-        <p><strong>Iterations:</strong> {data.get('iterations_run', 0)} | <strong>Train:</strong> {data.get('train_size', '?')} | <strong>Test:</strong> {data.get('test_size', '?')}</p>
+        <p><strong>Original:</strong> {html.escape(data.get("original_description", "N/A"))}</p>
+        <p class="best"><strong>Best:</strong> {html.escape(data.get("best_description", "N/A"))}</p>
+        <p><strong>Best Score:</strong> {data.get("best_score", "N/A")} {"(test)" if best_test_score else "(train)"}</p>
+        <p><strong>Iterations:</strong> {data.get("iterations_run", 0)} | <strong>Train:</strong> {data.get("train_size", "?")} | <strong>Test:</strong> {data.get("test_size", "?")}</p>
     </div>
 """)
 
@@ -188,12 +205,16 @@ def generate_html(data: dict, auto_refresh: bool = False, skill_name: str = "")
     # Add column headers for train queries
     for qinfo in train_queries:
         polarity = "positive-col" if qinfo["should_trigger"] else "negative-col"
-        html_parts.append(f'                <th class="{polarity}">{html.escape(qinfo["query"])}</th>\n')
+        html_parts.append(
+            f'                <th class="{polarity}">{html.escape(qinfo["query"])}</th>\n'
+        )
 
     # Add column headers for test queries (different color)
     for qinfo in test_queries:
         polarity = "positive-col" if qinfo["should_trigger"] else "negative-col"
-        html_parts.append(f'                <th class="test-col {polarity}">{html.escape(qinfo["query"])}</th>\n')
+        html_parts.append(
+            f'                <th class="test-col {polarity}">{html.escape(qinfo["query"])}</th>\n'
+        )
 
     html_parts.append("""            </tr>
         </thead>
@@ -202,9 +223,13 @@ def generate_html(data: dict, auto_refresh: bool = False, skill_name: str = "")
 
     # Find best iteration for highlighting
     if test_queries:
-        best_iter = max(history, key=lambda h: h.get("test_passed") or 0).get("iteration")
+        best_iter = max(history, key=lambda h: h.get("test_passed") or 0).get(
+            "iteration"
+        )
     else:
-        best_iter = max(history, key=lambda h: h.get("train_passed", h.get("passed", 0))).get("iteration")
+        best_iter = max(
+            history, key=lambda h: h.get("train_passed", h.get("passed", 0))
+        ).get("iteration")
 
     # Add rows for each iteration
     for h in history:
@@ -266,7 +291,9 @@ def score_class(correct: int, total: int) -> str:
             icon = "✓" if did_pass else "✗"
             css_class = "pass" if did_pass else "fail"
 
-            html_parts.append(f'                <td class="result {css_class}">{icon}<span class="rate">{triggers}/{runs}</span></td>\n')
+            html_parts.append(
+                f'                <td class="result {css_class}">{icon}<span class="rate">{triggers}/{runs}</span></td>\n'
+            )
 
         # Add result for each test query (with different background)
         for qinfo in test_queries:
@@ -278,7 +305,9 @@ def score_class(correct: int, total: int) -> str:
             icon = "✓" if did_pass else "✗"
             css_class = "pass" if did_pass else "fail"
 
-            html_parts.append(f'                <td class="result test-result {css_class}">{icon}<span class="rate">{triggers}/{runs}</span></td>\n')
+            html_parts.append(
+                f'                <td class="result test-result {css_class}">{icon}<span class="rate">{triggers}/{runs}</span></td>\n'
+            )
 
         html_parts.append("            </tr>\n")
 
@@ -296,10 +325,18 @@ def score_class(correct: int, total: int) -> str:
 
 
 def main():
-    parser = argparse.ArgumentParser(description="Generate HTML report from run_loop output")
-    parser.add_argument("input", help="Path to JSON output from run_loop.py (or - for stdin)")
-    parser.add_argument("-o", "--output", default=None, help="Output HTML file (default: stdout)")
-    parser.add_argument("--skill-name", default="", help="Skill name to include in the report title")
+    parser = argparse.ArgumentParser(
+        description="Generate HTML report from run_loop output"
+    )
+    parser.add_argument(
+        "input", help="Path to JSON output from run_loop.py (or - for stdin)"
+    )
+    parser.add_argument(
+        "-o", "--output", default=None, help="Output HTML file (default: stdout)"
+    )
+    parser.add_argument(
+        "--skill-name", default="", help="Skill name to include in the report title"
+    )
     args = parser.parse_args()
 
     if args.input == "-":
diff --git a/EvoScientist/skills/skill-creator/scripts/improve_description.py b/EvoScientist/skills/skill-creator/scripts/improve_description.py
--- a/EvoScientist/skills/skill-creator/scripts/improve_description.py
+++ b/EvoScientist/skills/skill-creator/scripts/improve_description.py
@@ -50,18 +50,20 @@ def improve_description(
 ) -> str:
     """Call an LLM to improve the description based on eval results."""
     failed_triggers = [
-        r for r in eval_results["results"]
-        if r["should_trigger"] and not r["pass"]
+        r for r in eval_results["results"] if r["should_trigger"] and not r["pass"]
     ]
     false_triggers = [
-        r for r in eval_results["results"]
-        if not r["should_trigger"] and not r["pass"]
+        r for r in eval_results["results"] if not r["should_trigger"] and not r["pass"]
     ]
 
     # Build scores summary
-    train_score = f"{eval_results['summary']['passed']}/{eval_results['summary']['total']}"
+    train_score = (
+        f"{eval_results['summary']['passed']}/{eval_results['summary']['total']}"
+    )
     if test_results:
-        test_score = f"{test_results['summary']['passed']}/{test_results['summary']['total']}"
+        test_score = (
+            f"{test_results['summary']['passed']}/{test_results['summary']['total']}"
+        )
         scores_summary = f"Train: {train_score}, Test: {test_score}"
     else:
         scores_summary = f"Train: {train_score}"
@@ -81,30 +83,38 @@ def improve_description(
     if failed_triggers:
         prompt += "FAILED TO TRIGGER (should have triggered but didn't):\n"
         for r in failed_triggers:
-            prompt += f'  - "{r["query"]}" (triggered {r["triggers"]}/{r["runs"]} times)\n'
+            prompt += (
+                f'  - "{r["query"]}" (triggered {r["triggers"]}/{r["runs"]} times)\n'
+            )
         prompt += "\n"
 
     if false_triggers:
         prompt += "FALSE TRIGGERS (triggered but shouldn't have):\n"
         for r in false_triggers:
-            prompt += f'  - "{r["query"]}" (triggered {r["triggers"]}/{r["runs"]} times)\n'
+            prompt += (
+                f'  - "{r["query"]}" (triggered {r["triggers"]}/{r["runs"]} times)\n'
+            )
         prompt += "\n"
 
     if history:
         prompt += "PREVIOUS ATTEMPTS (do NOT repeat these — try something structurally different):\n\n"
         for h in history:
             train_s = f"{h.get('train_passed', h.get('passed', 0))}/{h.get('train_total', h.get('total', 0))}"
-            test_s = f"{h.get('test_passed', '?')}/{h.get('test_total', '?')}" if h.get('test_passed') is not None else None
+            test_s = (
+                f"{h.get('test_passed', '?')}/{h.get('test_total', '?')}"
+                if h.get("test_passed") is not None
+                else None
+            )
             score_str = f"train={train_s}" + (f", test={test_s}" if test_s else "")
-            prompt += f'<attempt {score_str}>\n'
+            prompt += f"<attempt {score_str}>\n"
             prompt += f'Description: "{h["description"]}"\n'
             if "results" in h:
                 prompt += "Train results:\n"
                 for r in h["results"]:
                     status = "PASS" if r["pass"] else "FAIL"
                     prompt += f'  [{status}] "{r["query"][:80]}" (triggered {r["triggers"]}/{r["runs"]})\n'
             if h.get("note"):
-                prompt += f'Note: {h["note"]}\n'
+                prompt += f"Note: {h['note']}\n"
             prompt += "</attempt>\n\n"
 
     prompt += f"""</scores_summary>
@@ -146,7 +156,9 @@ def improve_description(
 
     # Parse out the <new_description> tags
     match = re.search(r"<new_description>(.*?)</new_description>", text, re.DOTALL)
-    description = match.group(1).strip().strip('"') if match else text.strip().strip('"')
+    description = (
+        match.group(1).strip().strip('"') if match else text.strip().strip('"')
+    )
 
     # Log the transcript
     transcript: dict = {
@@ -209,9 +221,7 @@ def main():
         required=True,
         help="Path to eval results JSON (from run_eval.py)",
     )
-    parser.add_argument(
-        "--skill-path", required=True, help="Path to skill directory"
-    )
+    parser.add_argument("--skill-path", required=True, help="Path to skill directory")
     parser.add_argument(
         "--history",
         default=None,
@@ -270,13 +280,16 @@ def main():
     # Output as JSON with both the new description and updated history
     output = {
         "description": new_description,
-        "history": history + [{
-            "description": current_description,
-            "passed": eval_results["summary"]["passed"],
-            "failed": eval_results["summary"]["failed"],
-            "total": eval_results["summary"]["total"],
-            "results": eval_results["results"],
-        }],
+        "history": [
+            *history,
+            {
+                "description": current_description,
+                "passed": eval_results["summary"]["passed"],
+                "failed": eval_results["summary"]["failed"],
+                "total": eval_results["summary"]["total"],
+                "results": eval_results["results"],
+            },
+        ],
     }
     print(json.dumps(output, indent=2))
 
diff --git a/EvoScientist/skills/skill-creator/scripts/init_skill.py b/EvoScientist/skills/skill-creator/scripts/init_skill.py
--- a/EvoScientist/skills/skill-creator/scripts/init_skill.py
+++ b/EvoScientist/skills/skill-creator/scripts/init_skill.py
@@ -14,7 +14,6 @@
 import sys
 from pathlib import Path
 
-
 SKILL_TEMPLATE = """---
 name: {skill_name}
 description: "TODO: replace with a clear explanation of what the skill does and when to use it."
@@ -188,7 +187,7 @@ def main():
 
 def title_case_skill_name(skill_name):
     """Convert hyphenated skill name to Title Case for display."""
-    return ' '.join(word.capitalize() for word in skill_name.split('-'))
+    return " ".join(word.capitalize() for word in skill_name.split("-"))
 
 
 def init_skill(skill_name, path):
@@ -221,11 +220,10 @@ def init_skill(skill_name, path):
     # Create SKILL.md from template
     skill_title = title_case_skill_name(skill_name)
     skill_content = SKILL_TEMPLATE.format(
-        skill_name=skill_name,
-        skill_title=skill_title
+        skill_name=skill_name, skill_title=skill_title
     )
 
-    skill_md_path = skill_dir / 'SKILL.md'
+    skill_md_path = skill_dir / "SKILL.md"
     try:
         skill_md_path.write_text(skill_content)
         print("✅ Created SKILL.md")
@@ -236,24 +234,24 @@ def init_skill(skill_name, path):
     # Create resource directories with example files
     try:
         # Create scripts/ directory with example script
-        scripts_dir = skill_dir / 'scripts'
+        scripts_dir = skill_dir / "scripts"
         scripts_dir.mkdir(exist_ok=True)
-        example_script = scripts_dir / 'example.py'
+        example_script = scripts_dir / "example.py"
         example_script.write_text(EXAMPLE_SCRIPT.format(skill_name=skill_name))
         example_script.chmod(0o755)
         print("✅ Created scripts/example.py")
 
         # Create references/ directory with example reference doc
-        references_dir = skill_dir / 'references'
+        references_dir = skill_dir / "references"
         references_dir.mkdir(exist_ok=True)
-        example_reference = references_dir / 'api_reference.md'
+        example_reference = references_dir / "api_reference.md"
         example_reference.write_text(EXAMPLE_REFERENCE.format(skill_title=skill_title))
         print("✅ Created references/api_reference.md")
 
         # Create assets/ directory with example asset placeholder
-        assets_dir = skill_dir / 'assets'
+        assets_dir = skill_dir / "assets"
         assets_dir.mkdir(exist_ok=True)
-        example_asset = assets_dir / 'example_asset.txt'
+        example_asset = assets_dir / "example_asset.txt"
         example_asset.write_text(EXAMPLE_ASSET)
         print("✅ Created assets/example_asset.txt")
     except Exception as e:
@@ -264,14 +262,16 @@ def init_skill(skill_name, path):
     print(f"\n✅ Skill '{skill_name}' initialized successfully at {skill_dir}")
     print("\nNext steps:")
     print("1. Edit SKILL.md to complete the TODO items and update the description")
-    print("2. Customize or delete the example files in scripts/, references/, and assets/")
+    print(
+        "2. Customize or delete the example files in scripts/, references/, and assets/"
+    )
     print("3. Run the validator when ready to check the skill structure")
 
     return skill_dir
 
 
 def main():
-    if len(sys.argv) < 4 or sys.argv[2] != '--path':
+    if len(sys.argv) < 4 or sys.argv[2] != "--path":
         print("Usage: init_skill.py <skill-name> --path <path>")
         print("\nSkill name requirements:")
         print("  - Hyphen-case identifier (e.g., 'data-analyzer')")
diff --git a/EvoScientist/skills/skill-creator/scripts/package_skill.py b/EvoScientist/skills/skill-creator/scripts/package_skill.py
--- a/EvoScientist/skills/skill-creator/scripts/package_skill.py
+++ b/EvoScientist/skills/skill-creator/scripts/package_skill.py
@@ -92,9 +92,9 @@ def package_skill(skill_path, output_dir=None):
 
     # Create the .skill file (zip format)
     try:
-        with zipfile.ZipFile(skill_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
+        with zipfile.ZipFile(skill_filename, "w", zipfile.ZIP_DEFLATED) as zipf:
             # Walk through the skill directory, excluding build artifacts
-            for file_path in skill_path.rglob('*'):
+            for file_path in skill_path.rglob("*"):
                 if not file_path.is_file():
                     continue
                 arcname = file_path.relative_to(skill_path.parent)
@@ -114,12 +114,17 @@ def package_skill(skill_path, output_dir=None):
 
 def main():
     import argparse
+
     parser = argparse.ArgumentParser(
         description="Package a skill folder into a distributable .skill file"
     )
     parser.add_argument("skill_path", help="Path to the skill folder")
-    parser.add_argument("output_dir", nargs="?", default=None,
-                        help="Output directory for the .skill file (default: current directory)")
+    parser.add_argument(
+        "output_dir",
+        nargs="?",
+        default=None,
+        help="Output directory for the .skill file (default: current directory)",
+    )
     args = parser.parse_args()
 
     print(f"📦 Packaging skill: {args.skill_path}")
diff --git a/EvoScientist/skills/skill-creator/scripts/quick_validate.py b/EvoScientist/skills/skill-creator/scripts/quick_validate.py
--- a/EvoScientist/skills/skill-creator/scripts/quick_validate.py
+++ b/EvoScientist/skills/skill-creator/scripts/quick_validate.py
@@ -3,27 +3,29 @@
 Quick validation script for skills - minimal version
 """
 
-import sys
 import re
-import yaml
+import sys
 from pathlib import Path
 
+import yaml
+
+
 def validate_skill(skill_path, *, strict=False):
     """Basic validation of a skill. With strict=True, also checks for TODO placeholders."""
     skill_path = Path(skill_path)
 
     # Check SKILL.md exists
-    skill_md = skill_path / 'SKILL.md'
+    skill_md = skill_path / "SKILL.md"
     if not skill_md.exists():
         return False, "SKILL.md not found"
 
     # Read and validate frontmatter
     content = skill_md.read_text()
-    if not content.startswith('---'):
+    if not content.startswith("---"):
         return False, "No YAML frontmatter found"
 
     # Extract frontmatter
-    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
+    match = re.match(r"^---\n(.*?)\n---", content, re.DOTALL)
     if not match:
         return False, "Invalid frontmatter format"
 
@@ -38,7 +40,14 @@ def validate_skill(skill_path, *, strict=False):
         return False, f"Invalid YAML in frontmatter: {e}"
 
     # Define allowed properties
-    ALLOWED_PROPERTIES = {'name', 'description', 'license', 'allowed-tools', 'metadata', 'compatibility'}
+    ALLOWED_PROPERTIES = {
+        "name",
+        "description",
+        "license",
+        "allowed-tools",
+        "metadata",
+        "compatibility",
+    }
 
     # Check for unexpected properties (excluding nested keys under metadata)
     unexpected_keys = set(frontmatter.keys()) - ALLOWED_PROPERTIES
@@ -49,71 +58,97 @@ def validate_skill(skill_path, *, strict=False):
         )
 
     # Check required fields
-    if 'name' not in frontmatter:
+    if "name" not in frontmatter:
         return False, "Missing 'name' in frontmatter"
-    if 'description' not in frontmatter:
+    if "description" not in frontmatter:
         return False, "Missing 'description' in frontmatter"
 
     # Extract name for validation
-    name = frontmatter.get('name', '')
+    name = frontmatter.get("name", "")
     if not isinstance(name, str):
         return False, f"Name must be a string, got {type(name).__name__}"
     name = name.strip()
     if name:
         # Check naming convention (kebab-case: lowercase with hyphens)
-        if not re.match(r'^[a-z0-9-]+$', name):
-            return False, f"Name '{name}' should be kebab-case (lowercase letters, digits, and hyphens only)"
-        if name.startswith('-') or name.endswith('-') or '--' in name:
-            return False, f"Name '{name}' cannot start/end with hyphen or contain consecutive hyphens"
+        if not re.match(r"^[a-z0-9-]+$", name):
+            return (
+                False,
+                f"Name '{name}' should be kebab-case (lowercase letters, digits, and hyphens only)",
+            )
+        if name.startswith("-") or name.endswith("-") or "--" in name:
+            return (
+                False,
+                f"Name '{name}' cannot start/end with hyphen or contain consecutive hyphens",
+            )
         # Check name length (max 64 characters per spec)
         if len(name) > 64:
-            return False, f"Name is too long ({len(name)} characters). Maximum is 64 characters."
+            return (
+                False,
+                f"Name is too long ({len(name)} characters). Maximum is 64 characters.",
+            )
 
     # Extract and validate description
-    description = frontmatter.get('description', '')
+    description = frontmatter.get("description", "")
     if not isinstance(description, str):
         return False, f"Description must be a string, got {type(description).__name__}"
     description = description.strip()
     if description:
         # Check for angle brackets
-        if '<' in description or '>' in description:
+        if "<" in description or ">" in description:
             return False, "Description cannot contain angle brackets (< or >)"
         # Check description length (max 1024 characters per spec)
         if len(description) > 1024:
-            return False, f"Description is too long ({len(description)} characters). Maximum is 1024 characters."
+            return (
+                False,
+                f"Description is too long ({len(description)} characters). Maximum is 1024 characters.",
+            )
 
     # Validate compatibility field if present (optional)
-    compatibility = frontmatter.get('compatibility', '')
-    if compatibility:
+    if "compatibility" in frontmatter:
+        compatibility = frontmatter.get("compatibility")
         if not isinstance(compatibility, str):
-            return False, f"Compatibility must be a string, got {type(compatibility).__name__}"
+            return (
+                False,
+                f"Compatibility must be a string, got {type(compatibility).__name__}",
+            )
         if len(compatibility) > 500:
-            return False, f"Compatibility is too long ({len(compatibility)} characters). Maximum is 500 characters."
+            return (
+                False,
+                f"Compatibility is too long ({len(compatibility)} characters). Maximum is 500 characters.",
+            )
 
     # Strict mode: check for incomplete/placeholder content
     if strict:
-        TODO_PATTERN = re.compile(r'\[TODO:|\bTODO\b')
+        TODO_PATTERN = re.compile(r"\[TODO:|\bTODO\b")
 
         # Check description is not a placeholder
         if description and TODO_PATTERN.search(description):
             return False, "Description contains TODO placeholder (strict mode)"
 
         # Check body for TODO markers
-        body = content[match.end():]
+        body = content[match.end() :]
         todo_matches = TODO_PATTERN.findall(body)
         if todo_matches:
-            return False, f"SKILL.md body contains {len(todo_matches)} TODO placeholder(s) (strict mode)"
+            return (
+                False,
+                f"SKILL.md body contains {len(todo_matches)} TODO placeholder(s) (strict mode)",
+            )
 
     return True, "Skill is valid!"
 
+
 if __name__ == "__main__":
     import argparse as _ap
+
     _parser = _ap.ArgumentParser(description="Validate a skill directory")
     _parser.add_argument("skill_directory", help="Path to skill directory")
-    _parser.add_argument("--strict", action="store_true",
-                         help="Also check for TODO placeholders and incomplete content")
+    _parser.add_argument(
+        "--strict",
+        action="store_true",
+        help="Also check for TODO placeholders and incomplete content",
+    )
     _args = _parser.parse_args()
 
     valid, message = validate_skill(_args.skill_directory, strict=_args.strict)
     print(message)
-    sys.exit(0 if valid else 1)
\ No newline at end of file
+    sys.exit(0 if valid else 1)
diff --git a/EvoScientist/skills/skill-creator/scripts/run_eval.py b/EvoScientist/skills/skill-creator/scripts/run_eval.py
--- a/EvoScientist/skills/skill-creator/scripts/run_eval.py
+++ b/EvoScientist/skills/skill-creator/scripts/run_eval.py
@@ -20,7 +20,8 @@
 
 def _init_config():
     """Initialize EvoSci config and apply env vars (once per process)."""
-    from EvoScientist.config import get_effective_config, apply_config_to_env
+    from EvoScientist.config import apply_config_to_env, get_effective_config
+
     config = get_effective_config()
     apply_config_to_env(config)
     return config
@@ -39,10 +40,11 @@ def run_single_query(
     the LLM sees a system prompt with available skills and decides whether to
     call load_skill.
     """
-    from EvoScientist.llm import get_chat_model
     from langchain_core.messages import HumanMessage, SystemMessage
     from langchain_core.tools import tool
 
+    from EvoScientist.llm import get_chat_model
+
     config = _init_config()
 
     effective_model = model or config.model
@@ -76,10 +78,12 @@ def load_skill(name: str) -> str:
             **eval_kwargs,
         )
         model_with_tools = chat_model.bind_tools([load_skill])
-        response = model_with_tools.invoke([
-            SystemMessage(content=system_prompt),
-            HumanMessage(content=query),
-        ])
+        response = model_with_tools.invoke(
+            [
+                SystemMessage(content=system_prompt),
+                HumanMessage(content=query),
+            ]
+        )
 
         # Check if the model called load_skill with the right skill name
         if hasattr(response, "tool_calls") and response.tool_calls:
@@ -109,10 +113,17 @@ def load_skill(name: str) -> str:
 Would you load the "{skill_name}" skill to help with this request?
 Answer with ONLY "YES" or "NO"."""
             response = chat_model.invoke([HumanMessage(content=fallback_prompt)])
-            text = response.content if isinstance(response.content, str) else str(response.content)
+            text = (
+                response.content
+                if isinstance(response.content, str)
+                else str(response.content)
+            )
             return text.strip().upper().startswith("YES")
         except Exception:
-            print(f"Warning: query failed for both tool-calling and fallback: {e}", file=sys.stderr)
+            print(
+                f"Warning: query failed for both tool-calling and fallback: {e}",
+                file=sys.stderr,
+            )
             return False
 
 
@@ -165,14 +176,16 @@ def run_eval(
             did_pass = trigger_rate >= trigger_threshold
         else:
             did_pass = trigger_rate < trigger_threshold
-        results.append({
-            "query": query,
-            "should_trigger": should_trigger,
-            "trigger_rate": trigger_rate,
-            "triggers": sum(triggers),
-            "runs": len(triggers),
-            "pass": did_pass,
-        })
+        results.append(
+            {
+                "query": query,
+                "should_trigger": should_trigger,
+                "trigger_rate": trigger_rate,
+                "triggers": sum(triggers),
+                "runs": len(triggers),
+                "pass": did_pass,
+            }
+        )
 
     passed = sum(1 for r in results if r["pass"])
     total = len(results)
@@ -190,16 +203,34 @@ def run_eval(
 
 
 def main():
-    parser = argparse.ArgumentParser(description="Run trigger evaluation for a skill description")
+    parser = argparse.ArgumentParser(
+        description="Run trigger evaluation for a skill description"
+    )
     parser.add_argument("--eval-set", required=True, help="Path to eval set JSON file")
     parser.add_argument("--skill-path", required=True, help="Path to skill directory")
-    parser.add_argument("--description", default=None, help="Override description to test")
-    parser.add_argument("--num-workers", type=int, default=10, help="Number of parallel workers")
-    parser.add_argument("--runs-per-query", type=int, default=3, help="Number of runs per query")
-    parser.add_argument("--trigger-threshold", type=float, default=0.5, help="Trigger rate threshold")
-    parser.add_argument("--model", default=None, help="Model to use (default: user's configured model)")
-    parser.add_argument("--provider", default=None, help="LLM provider (default: user's configured provider)")
-    parser.add_argument("--verbose", action="store_true", help="Print progress to stderr")
+    parser.add_argument(
+        "--description", default=None, help="Override description to test"
+    )
+    parser.add_argument(
+        "--num-workers", type=int, default=10, help="Number of parallel workers"
+    )
+    parser.add_argument(
+        "--runs-per-query", type=int, default=3, help="Number of runs per query"
+    )
+    parser.add_argument(
+        "--trigger-threshold", type=float, default=0.5, help="Trigger rate threshold"
+    )
+    parser.add_argument(
+        "--model", default=None, help="Model to use (default: user's configured model)"
+    )
+    parser.add_argument(
+        "--provider",
+        default=None,
+        help="LLM provider (default: user's configured provider)",
+    )
+    parser.add_argument(
+        "--verbose", action="store_true", help="Print progress to stderr"
+    )
     args = parser.parse_args()
 
     eval_set = json.loads(Path(args.eval_set).read_text())
@@ -228,11 +259,16 @@ def main():
 
     if args.verbose:
         summary = output["summary"]
-        print(f"Results: {summary['passed']}/{summary['total']} passed", file=sys.stderr)
+        print(
+            f"Results: {summary['passed']}/{summary['total']} passed", file=sys.stderr
+        )
         for r in output["results"]:
             status = "PASS" if r["pass"] else "FAIL"
             rate_str = f"{r['triggers']}/{r['runs']}"
-            print(f"  [{status}] rate={rate_str} expected={r['should_trigger']}: {r['query'][:70]}", file=sys.stderr)
+            print(
+                f"  [{status}] rate={rate_str} expected={r['should_trigger']}: {r['query'][:70]}",
+                file=sys.stderr,
+            )
 
     print(json.dumps(output, indent=2))
 
diff --git a/EvoScientist/skills/skill-creator/scripts/run_loop.py b/EvoScientist/skills/skill-creator/scripts/run_loop.py
--- a/EvoScientist/skills/skill-creator/scripts/run_loop.py
+++ b/EvoScientist/skills/skill-creator/scripts/run_loop.py
@@ -18,15 +18,16 @@
 # Ensure skill-creator root is on sys.path for `from scripts.xxx` imports
 sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
 
-from EvoScientist.config import get_effective_config, apply_config_to_env
-
+from EvoScientist.config import apply_config_to_env, get_effective_config
 from scripts.generate_report import generate_html
 from scripts.improve_description import improve_description
 from scripts.run_eval import run_eval
 from scripts.utils import parse_skill_md
 
 
-def split_eval_set(eval_set: list[dict], holdout: float, seed: int = 42) -> tuple[list[dict], list[dict]]:
+def split_eval_set(
+    eval_set: list[dict], holdout: float, seed: int = 42
+) -> tuple[list[dict], list[dict]]:
     """Split eval set into train and test sets, stratified by should_trigger."""
     random.seed(seed)
 
@@ -75,7 +76,10 @@ def run_loop(
     if holdout > 0:
         train_set, test_set = split_eval_set(eval_set, holdout)
         if verbose:
-            print(f"Split: {len(train_set)} train, {len(test_set)} test (holdout={holdout})", file=sys.stderr)
+            print(
+                f"Split: {len(train_set)} train, {len(test_set)} test (holdout={holdout})",
+                file=sys.stderr,
+            )
     else:
         train_set = eval_set
         test_set = []
@@ -85,10 +89,10 @@ def run_loop(
 
     for iteration in range(1, max_iterations + 1):
         if verbose:
-            print(f"\n{'='*60}", file=sys.stderr)
+            print(f"\n{'=' * 60}", file=sys.stderr)
             print(f"Iteration {iteration}/{max_iterations}", file=sys.stderr)
             print(f"Description: {current_description}", file=sys.stderr)
-            print(f"{'='*60}", file=sys.stderr)
+            print(f"{'=' * 60}", file=sys.stderr)
 
         # Evaluate train + test together in one batch for parallelism
         all_queries = train_set + test_set
@@ -105,42 +109,63 @@ def run_loop(
         )
         eval_elapsed = time.time() - t0
 
-        # Split results back into train/test by matching queries
-        train_queries_set = {q["query"] for q in train_set}
-        train_result_list = [r for r in all_results["results"] if r["query"] in train_queries_set]
-        test_result_list = [r for r in all_results["results"] if r["query"] not in train_queries_set]
+        # Split results back into train/test by query identity.
+        # Use count-based matching to handle duplicate queries correctly.
+        # (run_eval uses as_completed so results are not in submission order)
+        from collections import Counter
+
+        train_query_budget = Counter(q["query"] for q in train_set)
+        train_result_list = []
+        test_result_list = []
+        for r in all_results["results"]:
+            q = r["query"]
+            if train_query_budget[q] > 0:
+                train_result_list.append(r)
+                train_query_budget[q] -= 1
+            else:
+                test_result_list.append(r)
 
         train_passed = sum(1 for r in train_result_list if r["pass"])
         train_total = len(train_result_list)
-        train_summary = {"passed": train_passed, "failed": train_total - train_passed, "total": train_total}
+        train_summary = {
+            "passed": train_passed,
+            "failed": train_total - train_passed,
+            "total": train_total,
+        }
         train_results = {"results": train_result_list, "summary": train_summary}
 
         if test_set:
             test_passed = sum(1 for r in test_result_list if r["pass"])
             test_total = len(test_result_list)
-            test_summary = {"passed": test_passed, "failed": test_total - test_passed, "total": test_total}
+            test_summary = {
+                "passed": test_passed,
+                "failed": test_total - test_passed,
+                "total": test_total,
+            }
             test_results = {"results": test_result_list, "summary": test_summary}
         else:
             test_results = None
             test_summary = None
 
-        history.append({
-            "iteration": iteration,
-            "description": current_description,
-            "train_passed": train_summary["passed"],
-            "train_failed": train_summary["failed"],
-            "train_total": train_summary["total"],
-            "train_results": train_results["results"],
-            "test_passed": test_summary["passed"] if test_summary else None,
-            "test_failed": test_summary["failed"] if test_summary else None,
-            "test_total": test_summary["total"] if test_summary else None,
-            "test_results": test_results["results"] if test_results else None,
-            # For backward compat with report generator
-            "passed": train_summary["passed"],
-            "failed": train_summary["failed"],
-            "total": train_summary["total"],
-            "results": train_results["results"],
-        })
+        history.append(
+            {
+                "iteration": iteration,
+                "description": current_description,
+                "train_passed": train_summary["passed"],
+                "train_failed": train_summary["failed"],
+                "train_total": train_summary["total"],
+                "train_results": train_results["results"],
+                "test_passed": test_summary["passed"] if test_summary else None,
+                "test_failed": test_summary["failed"] if test_summary else None,
+                "test_total": test_summary["total"] if test_summary else None,
+                "test_results": test_results["results"] if test_results else None,
+                # For backward compat with report generator
+                "passed": train_summary["passed"],
+                "failed": train_summary["failed"],
+                "total": train_summary["total"],
+                "results": train_results["results"],
+            }
+        )
 
         # Write live report if path provided
         if live_report_path:
@@ -154,9 +179,12 @@ def run_loop(
                 "test_size": len(test_set),
                 "history": history,
             }
-            live_report_path.write_text(generate_html(partial_output, auto_refresh=True, skill_name=name))
+            live_report_path.write_text(
+                generate_html(partial_output, auto_refresh=True, skill_name=name)
+            )
 
         if verbose:
+
             def print_eval_stats(label, results, elapsed):
                 pos = [r for r in results if r["should_trigger"]]
                 neg = [r for r in results if not r["should_trigger"]]
@@ -170,11 +198,17 @@ def print_eval_stats(label, results, elapsed):
                 precision = tp / (tp + fp) if (tp + fp) > 0 else 1.0
                 recall = tp / (tp + fn) if (tp + fn) > 0 else 1.0
                 accuracy = (tp + tn) / total if total > 0 else 0.0
-                print(f"{label}: {tp+tn}/{total} correct, precision={precision:.0%} recall={recall:.0%} accuracy={accuracy:.0%} ({elapsed:.1f}s)", file=sys.stderr)
+                print(
+                    f"{label}: {tp + tn}/{total} correct, precision={precision:.0%} recall={recall:.0%} accuracy={accuracy:.0%} ({elapsed:.1f}s)",
+                    file=sys.stderr,
+                )
                 for r in results:
                     status = "PASS" if r["pass"] else "FAIL"
                     rate_str = f"{r['triggers']}/{r['runs']}"
-                    print(f"  [{status}] rate={rate_str} expected={r['should_trigger']}: {r['query'][:60]}", file=sys.stderr)
+                    print(
+                        f"  [{status}] rate={rate_str} expected={r['should_trigger']}: {r['query'][:60]}",
+                        file=sys.stderr,
+                    )
 
             print_eval_stats("Train", train_results["results"], eval_elapsed)
             if test_summary:
@@ -183,7 +217,10 @@ def print_eval_stats(label, results, elapsed):
         if train_summary["failed"] == 0:
             exit_reason = f"all_passed (iteration {iteration})"
             if verbose:
-                print(f"\nAll train queries passed on iteration {iteration}!", file=sys.stderr)
+                print(
+                    f"\nAll train queries passed on iteration {iteration}!",
+                    file=sys.stderr,
+                )
             break
 
         if iteration == max_iterations:
@@ -199,8 +236,7 @@ def print_eval_stats(label, results, elapsed):
         t0 = time.time()
         # Strip test scores from history so improvement model can't see them
         blinded_history = [
-            {k: v for k, v in h.items() if not k.startswith("test_")}
-            for h in history
+            {k: v for k, v in h.items() if not k.startswith("test_")} for h in history
         ]
         new_description = improve_description(
             skill_name=name,
@@ -216,7 +252,9 @@ def print_eval_stats(label, results, elapsed):
         improve_elapsed = time.time() - t0
 
         if verbose:
-            print(f"Proposed ({improve_elapsed:.1f}s): {new_description}", file=sys.stderr)
+            print(
+                f"Proposed ({improve_elapsed:.1f}s): {new_description}", file=sys.stderr
+            )
 
         current_description = new_description
 
@@ -230,15 +268,19 @@ def print_eval_stats(label, results, elapsed):
 
     if verbose:
         print(f"\nExit reason: {exit_reason}", file=sys.stderr)
-        print(f"Best score: {best_score} (iteration {best['iteration']})", file=sys.stderr)
+        print(
+            f"Best score: {best_score} (iteration {best['iteration']})", file=sys.stderr
+        )
 
     return {
         "exit_reason": exit_reason,
         "original_description": original_description,
         "best_description": best["description"],
         "best_score": best_score,
         "best_train_score": f"{best['train_passed']}/{best['train_total']}",
-        "best_test_score": f"{best['test_passed']}/{best['test_total']}" if test_set else None,
+        "best_test_score": f"{best['test_passed']}/{best['test_total']}"
+        if test_set
+        else None,
         "final_description": current_description,
         "iterations_run": len(history),
         "holdout": holdout,
@@ -252,17 +294,50 @@ def main():
     parser = argparse.ArgumentParser(description="Run eval + improve loop")
     parser.add_argument("--eval-set", required=True, help="Path to eval set JSON file")
     parser.add_argument("--skill-path", required=True, help="Path to skill directory")
-    parser.add_argument("--description", default=None, help="Override starting description")
-    parser.add_argument("--num-workers", type=int, default=10, help="Number of parallel workers")
-    parser.add_argument("--max-iterations", type=int, default=5, help="Max improvement iterations")
-    parser.add_argument("--runs-per-query", type=int, default=3, help="Number of runs per query")
-    parser.add_argument("--trigger-threshold", type=float, default=0.5, help="Trigger rate threshold")
-    parser.add_argument("--holdout", type=float, default=0.4, help="Fraction of eval set to hold out for testing (0 to disable)")
-    parser.add_argument("--model", default=None, help="Model for improvement (default: user's configured model)")
-    parser.add_argument("--provider", default=None, help="LLM provider (default: user's configured provider)")
-    parser.add_argument("--verbose", action="store_true", help="Print progress to stderr")
-    parser.add_argument("--report", default="auto", help="Generate HTML report at this path (default: 'auto' for temp file, 'none' to disable)")
-    parser.add_argument("--results-dir", default=None, help="Save all outputs (results.json, report.html, log.txt) to a timestamped subdirectory here")
+    parser.add_argument(
+        "--description", default=None, help="Override starting description"
+    )
+    parser.add_argument(
+        "--num-workers", type=int, default=10, help="Number of parallel workers"
+    )
+    parser.add_argument(
+        "--max-iterations", type=int, default=5, help="Max improvement iterations"
+    )
+    parser.add_argument(
+        "--runs-per-query", type=int, default=3, help="Number of runs per query"
+    )
+    parser.add_argument(
+        "--trigger-threshold", type=float, default=0.5, help="Trigger rate threshold"
+    )
+    parser.add_argument(
+        "--holdout",
+        type=float,
+        default=0.4,
+        help="Fraction of eval set to hold out for testing (0 to disable)",
+    )
+    parser.add_argument(
+        "--model",
+        default=None,
+        help="Model for improvement (default: user's configured model)",
+    )
+    parser.add_argument(
+        "--provider",
+        default=None,
+        help="LLM provider (default: user's configured provider)",
+    )
+    parser.add_argument(
+        "--verbose", action="store_true", help="Print progress to stderr"
+    )
+    parser.add_argument(
+        "--report",
+        default="auto",
+        help="Generate HTML report at this path (default: 'auto' for temp file, 'none' to disable)",
+    )
+    parser.add_argument(
+        "--results-dir",
+        default=None,
+        help="Save all outputs (results.json, report.html, log.txt) to a timestamped subdirectory here",
+    )
     args = parser.parse_args()
 
     eval_set = json.loads(Path(args.eval_set).read_text())
@@ -278,11 +353,16 @@ def main():
     if args.report != "none":
         if args.report == "auto":
             timestamp = time.strftime("%Y%m%d_%H%M%S")
-            live_report_path = Path(tempfile.gettempdir()) / f"skill_description_report_{skill_path.name}_{timestamp}.html"
+            live_report_path = (
+                Path(tempfile.gettempdir())
+                / f"skill_description_report_{skill_path.name}_{timestamp}.html"
+            )
         else:
             live_report_path = Path(args.report)
         # Open the report immediately so the user can watch
-        live_report_path.write_text("<html><body><h1>Starting optimization loop...</h1><meta http-equiv='refresh' content='5'></body></html>")
+        live_report_path.write_text(
+            "<html><body><h1>Starting optimization loop...</h1><meta http-equiv='refresh' content='5'></body></html>"
+        )
         webbrowser.open(str(live_report_path))
     else:
         live_report_path = None
@@ -321,11 +401,15 @@ def main():
 
     # Write final HTML report (without auto-refresh)
     if live_report_path:
-        live_report_path.write_text(generate_html(output, auto_refresh=False, skill_name=name))
+        live_report_path.write_text(
+            generate_html(output, auto_refresh=False, skill_name=name)
+        )
         print(f"\nReport: {live_report_path}", file=sys.stderr)
 
     if results_dir and live_report_path:
-        (results_dir / "report.html").write_text(generate_html(output, auto_refresh=False, skill_name=name))
+        (results_dir / "report.html").write_text(
+            generate_html(output, auto_refresh=False, skill_name=name)
+        )
 
     if results_dir:
         print(f"Results saved to: {results_dir}", file=sys.stderr)
diff --git a/EvoScientist/skills/skill-creator/scripts/utils.py b/EvoScientist/skills/skill-creator/scripts/utils.py
--- a/EvoScientist/skills/skill-creator/scripts/utils.py
+++ b/EvoScientist/skills/skill-creator/scripts/utils.py
@@ -3,7 +3,6 @@
 from pathlib import Path
 
 
-
 def parse_skill_md(skill_path: Path) -> tuple[str, str, str]:
     """Parse a SKILL.md file, returning (name, description, full_content)."""
     content = (skill_path / "SKILL.md").read_text()
@@ -28,14 +27,17 @@ def parse_skill_md(skill_path: Path) -> tuple[str, str, str]:
     while i < len(frontmatter_lines):
         line = frontmatter_lines[i]
         if line.startswith("name:"):
-            name = line[len("name:"):].strip().strip('"').strip("'")
+            name = line[len("name:") :].strip().strip('"').strip("'")
         elif line.startswith("description:"):
-            value = line[len("description:"):].strip()
+            value = line[len("description:") :].strip()
             # Handle YAML multiline indicators (>, |, >-, |-)
             if value in (">", "|", ">-", "|-"):
                 continuation_lines: list[str] = []
                 i += 1
-                while i < len(frontmatter_lines) and (frontmatter_lines[i].startswith("  ") or frontmatter_lines[i].startswith("\t")):
+                while i < len(frontmatter_lines) and (
+                    frontmatter_lines[i].startswith("  ")
+                    or frontmatter_lines[i].startswith("\t")
+                ):
                     continuation_lines.append(frontmatter_lines[i].strip())
                     i += 1
                 description = " ".join(continuation_lines)
diff --git a/EvoScientist/stream/display.py b/EvoScientist/stream/display.py
--- a/EvoScientist/stream/display.py
+++ b/EvoScientist/stream/display.py
@@ -6,6 +6,7 @@
 """
 
 import asyncio
+import inspect
 import logging
 import os
 import sys
@@ -30,7 +31,13 @@
     _build_todo_stats,
     _parse_todo_items,
 )
-from .utils import DisplayLimits, ToolStatus, format_tool_compact, is_success
+from .utils import (
+    DisplayLimits,
+    ToolStatus,
+    format_tool_compact,
+    format_tool_compact_with_result,
+    is_success,
+)
 
 # ---------------------------------------------------------------------------
 # Shared globals
@@ -174,21 +181,11 @@ def _render_tool_call_line(tc: dict, tr: dict | None) -> Text:
         style = "bold yellow" if not is_task else "bold cyan"
         indicator = "\u25b6" if is_task else ToolStatus.RUNNING.value
 
-    # Try to get display name from args first
-    tool_compact = format_tool_compact(tc["name"], tc.get("args"))
-
-    # If args were empty and we have a result, try to infer memory operations from result
-    tool_name = tc.get("name", "").lower()
-    if tool_name in ("write_file", "edit_file") and tr is not None:
-        result_content = tr.get("content", "")
-        if "/MEMORY.md" in result_content or "MEMORY.md" in result_content:
-            tool_compact = "Updating memory"
-    elif tool_name == "read_file" and tr is not None:
-        result_content = tr.get("content", "")
-        # read_file result doesn't contain path, check if args is empty and result looks like memory
-        args = tc.get("args") or {}
-        if not args.get("path") and "# EvoScientist Memory" in result_content:
-            tool_compact = "Reading memory"
+    tool_compact = format_tool_compact_with_result(
+        tc["name"],
+        tc.get("args"),
+        tr.get("content", "") if tr is not None else "",
+    )
 
     tool_text = Text()
     tool_text.append(f"{indicator} ", style=style)
@@ -227,9 +224,6 @@ def _render_subagent_section(sa: "SubAgentState", compact: bool = False) -> list
         else:
             pending.append(tc)
 
-    succeeded = sum(1 for _, tr in completed if tr.get("success", True))
-    _ = len(completed) - succeeded  # failed count, unused for now
-
     # Build display name
     display_name = f"Cooking with {sa.name}"
     if sa.description:
@@ -394,7 +388,9 @@ def create_streaming_display(
     total_input_tokens: int = 0,
     total_output_tokens: int = 0,
     summarization_text: str = "",
+    is_summarizing: bool = False,
     selected_tools: list | None = None,
+    status_footer: Any | None = None,
 ) -> Any:
     """Create Rich display layout for streaming output.
 
@@ -409,6 +405,8 @@ def create_streaming_display(
     # Initial waiting state
     if is_waiting and not thinking_text and not response_text and not tool_calls:
         elements.append(Spinner("dots", text=" Thinking...", style="cyan"))
+        if status_footer is not None:
+            elements.append(status_footer)
         return Group(*elements)
 
     # Thinking panel
@@ -454,16 +452,30 @@ def create_streaming_display(
         )
 
     # Summarization panel (context was compressed by LangGraph middleware)
-    if summarization_text:
+    if is_summarizing and not summarization_text:
+        elements.append(
+            Panel(
+                Text("Summarizing...", style="dim italic"),
+                title="Context Summarizing...",
+                border_style="#f59e0b",
+                padding=(0, 1),
+            )
+        )
+    elif summarization_text:
         summary_display = summarization_text.rstrip()
         n = len(summary_display)
         char_label = f"{n / 1000:.1f}k chars" if n >= 1000 else f"{n:,} chars"
         if n > 300:
             summary_display = summary_display[:300] + " ..."
+        title = (
+            f"Context Summarizing... ({char_label})"
+            if is_summarizing
+            else f"Context Summarized ({char_label})"
+        )
         elements.append(
             Panel(
                 Text(summary_display, style="dim italic"),
-                title=f"Context Summarized ({char_label})",
+                title=title,
                 border_style="#f59e0b",
                 padding=(0, 1),
             )
@@ -671,10 +683,27 @@ def create_streaming_display(
             elements.append(response_markdown or Markdown(response_text))
 
     if not elements:
-        return Group(Spinner("dots", text=" Processing...", style="cyan"))
+        elements.append(Spinner("dots", text=" Processing...", style="cyan"))
+    if status_footer is not None:
+        elements.append(status_footer)
     return Group(*elements)
 
 
+def resolve_final_status_footer(
+    interactive: bool,
+    status_footer_builder: Callable[[], Any] | None,
+) -> Any | None:
+    """Resolve the footer to keep in the last Live frame.
+
+    Interactive CLI sessions redraw prompt_toolkit's own bottom toolbar as soon
+    as Rich Live exits, so keeping the Rich footer in that final frame causes a
+    duplicate status bar.
+    """
+    if interactive:
+        return None
+    return status_footer_builder() if status_footer_builder else None
+
+
 # ---------------------------------------------------------------------------
 # Final results display
 # ---------------------------------------------------------------------------
@@ -1037,6 +1066,8 @@ def _run_streaming(
     on_thinking: Callable[[str], None] | None = None,
     on_todo: Callable[[list[dict]], None] | None = None,
     on_file_write: Callable[[str], None] | None = None,
+    on_stream_event: Callable[[str, Any], Any] | None = None,
+    status_footer_builder: Callable[[], Any] | None = None,
     metadata: dict | None = None,
     hitl_prompt_fn: Callable[[list], list[dict] | None] | None = None,
     ask_user_prompt_fn: Callable[[dict], dict] | None = None,
@@ -1161,11 +1192,19 @@ async def _consume() -> None:
                             _media_sent.add(rf_path)
                             on_file_write(real_path)
 
+            if on_stream_event is not None:
+                callback_result = on_stream_event(event_type, state)
+                if inspect.isawaitable(callback_result):
+                    await callback_result
+
             live.update(
                 create_streaming_display(
                     **state.get_display_args(),
                     show_thinking=show_thinking,
                     response_markdown=state.get_response_markdown(),
+                    status_footer=(
+                        status_footer_builder() if status_footer_builder else None
+                    ),
                 )
             )
 
@@ -1175,7 +1214,14 @@ async def _consume() -> None:
         transient=False,
         vertical_overflow="visible",
     ) as live:
-        live.update(create_streaming_display(is_waiting=True))
+        live.update(
+            create_streaming_display(
+                is_waiting=True,
+                status_footer=(
+                    status_footer_builder() if status_footer_builder else None
+                ),
+            )
+        )
         # Determine how to run the async streaming coroutine.
         # - In TUI mode (Textual), there's already a running event loop;
         #   nest_asyncio is needed to allow run_until_complete inside it.
@@ -1232,6 +1278,9 @@ async def _periodic_refresh() -> None:
                         **state.get_display_args(),
                         show_thinking=show_thinking,
                         response_markdown=state.get_response_markdown(),
+                        status_footer=resolve_final_status_footer(
+                            interactive, status_footer_builder
+                        ),
                     )
                 elif interactive:
                     final_display = create_streaming_display(
@@ -1240,6 +1289,9 @@ async def _periodic_refresh() -> None:
                         is_final=True,
                         final_show_thinking=False,
                         response_markdown=state.get_response_markdown(),
+                        status_footer=resolve_final_status_footer(
+                            interactive, status_footer_builder
+                        ),
                     )
                 else:
                     final_display = create_streaming_display(
@@ -1249,6 +1301,9 @@ async def _periodic_refresh() -> None:
                         final_show_thinking=True,
                         final_thinking_max_length=DisplayLimits.THINKING_FINAL,
                         response_markdown=state.get_response_markdown(),
+                        status_footer=resolve_final_status_footer(
+                            interactive, status_footer_builder
+                        ),
                     )
                 live.update(final_display)
                 live.refresh()
@@ -1278,6 +1333,8 @@ async def _periodic_refresh() -> None:
             on_thinking=on_thinking,
             on_todo=on_todo,
             on_file_write=on_file_write,
+            on_stream_event=on_stream_event,
+            status_footer_builder=status_footer_builder,
             metadata=metadata,
             hitl_prompt_fn=hitl_prompt_fn,
             ask_user_prompt_fn=ask_user_prompt_fn,
@@ -1305,6 +1362,8 @@ async def _periodic_refresh() -> None:
                 on_thinking=on_thinking,
                 on_todo=on_todo,
                 on_file_write=on_file_write,
+                on_stream_event=on_stream_event,
+                status_footer_builder=status_footer_builder,
                 metadata=metadata,
                 hitl_prompt_fn=hitl_prompt_fn,
                 ask_user_prompt_fn=ask_user_prompt_fn,
diff --git a/EvoScientist/stream/emitter.py b/EvoScientist/stream/emitter.py
--- a/EvoScientist/stream/emitter.py
+++ b/EvoScientist/stream/emitter.py
@@ -181,6 +181,14 @@ def summarization(content: str) -> StreamEvent:
             "summarization", {"type": "summarization", "content": content}
         )
 
+    @staticmethod
+    def summarization_start() -> StreamEvent:
+        """Context summarization started."""
+        return StreamEvent(
+            "summarization_start",
+            {"type": "summarization_start"},
+        )
+
     @staticmethod
     def error(message: str) -> StreamEvent:
         """Error event."""
diff --git a/EvoScientist/stream/events.py b/EvoScientist/stream/events.py
--- a/EvoScientist/stream/events.py
+++ b/EvoScientist/stream/events.py
@@ -24,6 +24,9 @@
 # Safety net: older ccproxy versions may embed thinking as XML tags in content
 # strings.  Strip them so they never leak to users or channels.
 _THINKING_TAG_RE = re.compile(r"<thinking>.*?</thinking>", re.DOTALL)
+_SUMMARY_TAG_RE = re.compile(
+    r"<summary>\s*(.*?)\s*</summary>", re.DOTALL | re.IGNORECASE
+)
 
 
 def _strip_legacy_thinking_tags(content: str) -> str:
@@ -101,14 +104,86 @@ def _extract_summarization_text(msg: Any) -> str:
     if isinstance(content, list):
         parts: list[str] = []
         for block in content:
-            if isinstance(block, dict) and block.get("type") == "text":
-                parts.append(block.get("text", ""))
+            if isinstance(block, dict):
+                text = block.get("text")
+                if isinstance(text, str):
+                    parts.append(text)
             elif isinstance(block, str):
                 parts.append(block)
         return "".join(parts)
     return ""
 
 
+def _extract_summary_message_text(summary_message: Any) -> str:
+    """Extract user-facing summary text from a stored summarization event.
+
+    DeepAgents persists summary messages as ``HumanMessage`` objects with wrapper
+    text like ``Here is a summary of the conversation to date:`` or an XML-ish
+    ``<summary>...</summary>`` block.  For UI display we only want the summary
+    body itself.
+    """
+    text = _extract_summarization_text(summary_message)
+    if not text:
+        return ""
+
+    match = _SUMMARY_TAG_RE.search(text)
+    if match:
+        return match.group(1).strip()
+
+    prefix = "Here is a summary of the conversation to date:"
+    if text.startswith(prefix):
+        return text[len(prefix) :].strip()
+
+    return text.strip()
+
+
+def _find_summarization_event_payload(data: Any) -> dict[str, Any] | None:
+    """Find a `_summarization_event` dict anywhere inside an updates payload."""
+    seen: set[int] = set()
+    stack: list[Any] = [data]
+
+    while stack:
+        item = stack.pop()
+        item_id = id(item)
+        if item_id in seen:
+            continue
+        seen.add(item_id)
+
+        if isinstance(item, dict):
+            event = item.get("_summarization_event")
+            if isinstance(event, dict):
+                return event
+            stack.extend(item.values())
+            continue
+
+        if isinstance(item, list | tuple):
+            stack.extend(item)
+            continue
+
+        if hasattr(item, "__dict__"):
+            try:
+                stack.append(vars(item))
+            except TypeError:
+                pass
+
+    return None
+
+
+def _summarization_event_signature(
+    event: dict[str, Any] | None,
+) -> tuple[Any, ...] | None:
+    """Build a stable signature for a persisted summarization event."""
+    if not isinstance(event, dict):
+        return None
+    summary_message = event.get("summary_message")
+    summary_text = _extract_summary_message_text(summary_message)
+    return (
+        event.get("cutoff_index"),
+        event.get("file_path"),
+        summary_text,
+    )
+
+
 async def stream_agent_events(
     agent: Any,
     message: Any,
@@ -361,10 +436,23 @@ def _read_file_b64(path: str) -> str:
         astream_input = message
 
     _summarization_in_progress = False
+    _baseline_summarization_signature: tuple[Any, ...] | None = None
     _tool_selection_suppressing = False  # True while buffering selector JSON
     _tool_selection_buffer = ""  # accumulates JSON chunks for parse attempt
     _tool_selection_was_active = False  # True after suppression, triggers Panel
 
+    if hasattr(agent, "aget_state"):
+        try:
+            snapshot = await agent.aget_state(config)
+            values = getattr(snapshot, "values", None)
+            if isinstance(values, dict):
+                baseline_event = _find_summarization_event_payload(values)
+                _baseline_summarization_signature = _summarization_event_signature(
+                    baseline_event
+                )
+        except Exception:
+            pass
+
     try:
         async for chunk in agent.astream(
             astream_input,
@@ -452,6 +540,21 @@ def _read_file_b64(path: str) -> str:
                             yield emitter.interrupt(
                                 interrupt_id, action_reqs, review_cfgs
                             ).data
+                summarization_event = _find_summarization_event_payload(data)
+                if summarization_event and not _summarization_in_progress:
+                    signature = _summarization_event_signature(summarization_event)
+                    if (
+                        signature is not None
+                        and signature == _baseline_summarization_signature
+                    ):
+                        continue
+                    summary_text = _extract_summary_message_text(
+                        summarization_event.get("summary_message")
+                    )
+                    if summary_text:
+                        yield emitter.summarization_start().data
+                        _summarization_in_progress = True
+                        yield emitter.summarization(summary_text).data
                 continue
             if mode_str != "messages":
                 continue
@@ -472,10 +575,11 @@ def _read_file_b64(path: str) -> str:
                 isinstance(metadata, dict)
                 and metadata.get("lc_source") == "summarization"
             ):
-                if not _summarization_in_progress:
-                    _summarization_in_progress = True
                 chunk_text = _extract_summarization_text(msg)
                 if chunk_text:
+                    if not _summarization_in_progress:
+                        yield emitter.summarization_start().data
+                    _summarization_in_progress = True
                     yield emitter.summarization(chunk_text).data
                 continue
 
@@ -485,7 +589,7 @@ def _read_file_b64(path: str) -> str:
             # the _selector_active flag is not visible in the streaming loop.
             # Uses _tool_selection_suppressing to track suppression state
             # and emits a tool_selection event from the tracker ContextVar.
-            if isinstance(msg, (AIMessageChunk, AIMessage)):
+            if isinstance(msg, AIMessageChunk | AIMessage):
                 _raw = msg.content
                 _text = (
                     _raw
@@ -609,7 +713,7 @@ def _read_file_b64(path: str) -> str:
                 )
 
             # Extract token usage from main-agent AIMessages
-            if isinstance(msg, (AIMessageChunk, AIMessage)) and not subagent:
+            if isinstance(msg, AIMessageChunk | AIMessage) and not subagent:
                 usage = getattr(msg, "usage_metadata", None)
                 if usage:
                     inp = (
@@ -626,7 +730,7 @@ def _read_file_b64(path: str) -> str:
                         yield emitter.usage_stats(inp, out).data
 
             # Process AIMessageChunk / AIMessage
-            if isinstance(msg, (AIMessageChunk, AIMessage)):
+            if isinstance(msg, AIMessageChunk | AIMessage):
                 if subagent:
                     # Sub-agent content -- emit sub-agent events
                     for ev in _process_chunk_content(msg, emitter, subagent_tracker):
diff --git a/EvoScientist/stream/state.py b/EvoScientist/stream/state.py
--- a/EvoScientist/stream/state.py
+++ b/EvoScientist/stream/state.py
@@ -80,6 +80,7 @@ class StreamState:
     def __init__(self):
         self.thinking_text = ""
         self.summarization_text = ""
+        self.is_summarizing = False
         self.response_text = ""
         self.tool_calls = []
         self.tool_results = []
@@ -96,6 +97,8 @@ def __init__(self):
         # Token usage tracking
         self.total_input_tokens = 0
         self.total_output_tokens = 0
+        self.last_input_tokens = 0
+        self.last_output_tokens = 0
         # Tool selection tracking (LLMToolSelectorMiddleware)
         self.selected_tools: list[str] = []
         # HITL interrupt tracking
@@ -174,6 +177,7 @@ def handle_event(self, event: dict) -> str:
             self.thinking_text += event.get("content", "")
 
         elif event_type == "text":
+            self.is_summarizing = False
             self.is_thinking = False
             self.is_responding = True
             self.is_processing = False
@@ -275,19 +279,37 @@ def handle_event(self, event: dict) -> str:
         elif event_type == "tool_selection":
             self.selected_tools = event.get("tools", [])
 
+        elif event_type == "summarization_start":
+            self.is_summarizing = True
+
         elif event_type == "summarization":
+            self.is_summarizing = True
             self.summarization_text += event.get("content", "")
 
         elif event_type == "usage_stats":
-            self.total_input_tokens += event.get("input_tokens", 0)
-            self.total_output_tokens += event.get("output_tokens", 0)
+            try:
+                input_tokens = max(0, int(event.get("input_tokens") or 0))
+            except (TypeError, ValueError):
+                input_tokens = 0
+            try:
+                output_tokens = max(0, int(event.get("output_tokens") or 0))
+            except (TypeError, ValueError):
+                output_tokens = 0
+            self.total_input_tokens += input_tokens
+            self.total_output_tokens += output_tokens
+            if input_tokens > 0:
+                self.last_input_tokens = input_tokens
+            if output_tokens > 0:
+                self.last_output_tokens = output_tokens
 
         elif event_type == "done":
+            self.is_summarizing = False
             self.is_processing = False
             if not self.response_text:
                 self.response_text = event.get("response", "")
 
         elif event_type == "error":
+            self.is_summarizing = False
             self.is_processing = False
             self.is_thinking = False
             self.is_responding = False
@@ -301,6 +323,7 @@ def get_display_args(self) -> dict:
         return {
             "thinking_text": self.thinking_text,
             "summarization_text": self.summarization_text,
+            "is_summarizing": self.is_summarizing,
             "response_text": self.response_text,
             "latest_text": self.latest_text,
             "tool_calls": self.tool_calls,
diff --git a/EvoScientist/stream/utils.py b/EvoScientist/stream/utils.py
--- a/EvoScientist/stream/utils.py
+++ b/EvoScientist/stream/utils.py
@@ -106,6 +106,19 @@ def _shorten_path(path: str, max_len: int = 40) -> str:
     return path
 
 
+def _tool_path_arg(args: dict | None) -> str:
+    """Return the best-effort path argument used by file tools."""
+    if not isinstance(args, dict):
+        return ""
+    return str(args.get("path") or args.get("file_path") or "")
+
+
+def _is_memory_path(path: str) -> bool:
+    """Return True when a virtual path targets the shared memory directory."""
+    normalized = (path or "").strip()
+    return normalized == "/memory" or normalized.startswith("/memory/")
+
+
 def format_tool_compact(name: str, args: dict | None) -> str:
     """Format as compact tool call string: ToolName(key_arg).
 
@@ -127,20 +140,20 @@ def format_tool_compact(name: str, args: dict | None) -> str:
 
     # File operations (with special case for memory files)
     if name_lower == "read_file":
-        path = args.get("path", "")
-        if path.endswith("/MEMORY.md") or path == "/MEMORY.md":
+        path = _tool_path_arg(args)
+        if _is_memory_path(path) or path.endswith("/MEMORY.md") or path == "/MEMORY.md":
             return "Reading memory"
         return f"read_file({_shorten_path(path)})"
 
     if name_lower == "write_file":
-        path = args.get("path", "")
-        if path.endswith("/MEMORY.md") or path == "/MEMORY.md":
+        path = _tool_path_arg(args)
+        if _is_memory_path(path) or path.endswith("/MEMORY.md") or path == "/MEMORY.md":
             return "Updating memory"
         return f"write_file({_shorten_path(path)})"
 
     if name_lower == "edit_file":
-        path = args.get("path", "")
-        if path.endswith("/MEMORY.md") or path == "/MEMORY.md":
+        path = _tool_path_arg(args)
+        if _is_memory_path(path) or path.endswith("/MEMORY.md") or path == "/MEMORY.md":
             return "Updating memory"
         return f"edit_file({_shorten_path(path)})"
 
@@ -220,6 +233,36 @@ def format_tool_compact(name: str, args: dict | None) -> str:
     return f"{name}({params_str})"
 
 
+def format_tool_compact_with_result(
+    name: str,
+    args: dict | None,
+    result_content: str = "",
+) -> str:
+    """Format tool labels with a small amount of result-based inference.
+
+    Some providers stream sparse file-tool args, especially for memory reads
+    and edits. Reuse the CLI inference here so all frontends keep the same
+    display names.
+    """
+    compact = format_tool_compact(name, args)
+    name_lower = name.lower()
+    result_content = result_content or ""
+
+    if name_lower in ("write_file", "edit_file"):
+        if (
+            "/memory/" in result_content
+            or "/MEMORY.md" in result_content
+            or "MEMORY.md" in result_content
+        ):
+            return "Updating memory"
+    elif name_lower == "read_file":
+        path = _tool_path_arg(args)
+        if not path and "# EvoScientist Memory" in result_content:
+            return "Reading memory"
+
+    return compact
+
+
 def format_tree_output(lines: list[str], max_lines: int = 5, indent: str = "  ") -> str:
     """Format output as tree structure.
 
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
