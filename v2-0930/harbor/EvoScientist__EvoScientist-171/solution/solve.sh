#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/EvoScientist/EvoScientist.py b/EvoScientist/EvoScientist.py
--- a/EvoScientist/EvoScientist.py
+++ b/EvoScientist/EvoScientist.py
@@ -120,8 +120,14 @@ def _load_mcp_config_once() -> tuple[str, dict]:
     return sig, cfg
 
 
-def _load_mcp_tools_cached() -> dict[str, list]:
-    """Load MCP tools with config-aware caching."""
+def _load_mcp_tools_cached(on_progress=None) -> dict[str, list]:
+    """Load MCP tools with config-aware caching.
+
+    Args:
+        on_progress: Optional per-server progress callback forwarded to
+            :func:`EvoScientist.mcp.load_mcp_tools`.  Only invoked on a
+            cache miss — cached replays don't re-emit progress events.
+    """
     global _MCP_TOOLS_CACHE_KEY, _MCP_TOOLS_CACHE_VALUE
 
     from .mcp import load_mcp_tools
@@ -135,7 +141,7 @@ def _load_mcp_tools_cached() -> dict[str, list]:
     if _MCP_TOOLS_CACHE_KEY == cfg_key and _MCP_TOOLS_CACHE_VALUE is not None:
         return {k: list(v) for k, v in _MCP_TOOLS_CACHE_VALUE.items()}
 
-    loaded = load_mcp_tools(config=cfg)
+    loaded = load_mcp_tools(config=cfg, on_progress=on_progress)
     _MCP_TOOLS_CACHE_KEY = cfg_key
     _MCP_TOOLS_CACHE_VALUE = {k: list(v) for k, v in loaded.items()}
     return {k: list(v) for k, v in loaded.items()}
@@ -208,16 +214,20 @@ def _build_base_kwargs(base_backend, base_middleware):
     }
 
 
-def load_mcp_and_build_kwargs(base_backend, base_middleware):
+def load_mcp_and_build_kwargs(base_backend, base_middleware, *, on_mcp_progress=None):
     """Load MCP tools (cached by config) and build agent kwargs.
 
     Re-connects to MCP servers only when the effective MCP config changes.
     Falls back to base kwargs if no MCP configured.
+
+    Args:
+        on_mcp_progress: Optional per-server progress callback.  Forwarded
+            to the MCP loader so UIs can render live status.
     """
     from .tools import skill_manager, tavily_search, think_tool
     from .utils import load_subagents
 
-    mcp_by_agent = _load_mcp_tools_cached()
+    mcp_by_agent = _load_mcp_tools_cached(on_progress=on_mcp_progress)
     if not mcp_by_agent:
         return _build_base_kwargs(base_backend, base_middleware)
 
@@ -360,7 +370,13 @@ def __getattr__(name: str):
 # =============================================================================
 
 
-def create_cli_agent(workspace_dir: str | None = None, checkpointer=None, config=None):
+def create_cli_agent(
+    workspace_dir: str | None = None,
+    checkpointer=None,
+    config=None,
+    *,
+    on_mcp_progress=None,
+):
     """Create agent with checkpointer for CLI multi-turn support.
 
     A fresh backend is constructed on every call using the current
@@ -453,7 +469,7 @@ def create_cli_agent(workspace_dir: str | None = None, checkpointer=None, config
         mw.insert(0, AskUserMiddleware())
 
     # Re-load MCP tools from current config (picks up /mcp add changes)
-    kwargs = load_mcp_and_build_kwargs(be, mw)
+    kwargs = load_mcp_and_build_kwargs(be, mw, on_mcp_progress=on_mcp_progress)
 
     # HITL: gate shell execution for user approval
     _interrupt_on: dict[str, bool] | None = None
diff --git a/EvoScientist/cli/__init__.py b/EvoScientist/cli/__init__.py
--- a/EvoScientist/cli/__init__.py
+++ b/EvoScientist/cli/__init__.py
@@ -1,27 +1,66 @@
-"""EvoScientist CLI package."""
-
-# Backward-compat re-exports (tests import these from EvoScientist.cli)
-from ..stream.state import (  # noqa: F401
-    StreamState,
-    SubAgentState,
-    _build_todo_stats,
-    _parse_todo_items,
-)
+"""EvoScientist CLI package.
+
+Most re-exports are served lazily through ``__getattr__`` so that a bare
+``import EvoScientist.cli`` only costs what ``main()`` actually needs.  That
+keeps ``evosci --help`` fast — the heavy chat-model/TUI/langgraph imports
+only pay their cost when someone actually touches those names.
+"""
+
+from __future__ import annotations
+
 from . import commands  # noqa: F401 — registers @app.command decorators
 from ._app import app
-from ._constants import WELCOME_SLOGANS  # noqa: F401
-from .agent import _deduplicate_run_name  # noqa: F401
-from .channel import _channels_is_running, _channels_stop  # noqa: F401
-
-# UI runtime re-exports (merged from former tui/ package)
-from .tui_runtime import (  # noqa: F401
-    DEFAULT_UI_BACKEND,
-    SUPPORTED_UI_BACKENDS,
-    get_backend,
-    normalize_ui_backend,
-    resolve_ui_backend,
-    run_streaming,
-)
+
+__all__ = [
+    "DEFAULT_UI_BACKEND",
+    "SUPPORTED_UI_BACKENDS",
+    "WELCOME_SLOGANS",
+    "StreamState",
+    "SubAgentState",
+    "_build_todo_stats",
+    "_channels_is_running",
+    "_channels_stop",
+    "_deduplicate_run_name",
+    "_parse_todo_items",
+    "app",
+    "get_backend",
+    "main",
+    "normalize_ui_backend",
+    "resolve_ui_backend",
+    "run_streaming",
+]
+
+# Map attribute name -> (relative-module, attribute-in-module).
+# Paths starting with ".." reach out of this package.
+_LAZY_EXPORTS: dict[str, tuple[str, str]] = {
+    "StreamState": ("..stream.state", "StreamState"),
+    "SubAgentState": ("..stream.state", "SubAgentState"),
+    "_build_todo_stats": ("..stream.state", "_build_todo_stats"),
+    "_parse_todo_items": ("..stream.state", "_parse_todo_items"),
+    "WELCOME_SLOGANS": ("._constants", "WELCOME_SLOGANS"),
+    "_deduplicate_run_name": (".agent", "_deduplicate_run_name"),
+    "_channels_is_running": (".channel", "_channels_is_running"),
+    "_channels_stop": (".channel", "_channels_stop"),
+    "DEFAULT_UI_BACKEND": (".tui_runtime", "DEFAULT_UI_BACKEND"),
+    "SUPPORTED_UI_BACKENDS": (".tui_runtime", "SUPPORTED_UI_BACKENDS"),
+    "get_backend": (".tui_runtime", "get_backend"),
+    "normalize_ui_backend": (".tui_runtime", "normalize_ui_backend"),
+    "resolve_ui_backend": (".tui_runtime", "resolve_ui_backend"),
+    "run_streaming": (".tui_runtime", "run_streaming"),
+}
+
+
+def __getattr__(name: str):
+    target = _LAZY_EXPORTS.get(name)
+    if target is None:
+        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
+    from importlib import import_module
+
+    module_path, attr = target
+    module = import_module(module_path, package=__name__)
+    value = getattr(module, attr)
+    globals()[name] = value
+    return value
 
 
 def main():
diff --git a/EvoScientist/cli/_agent_loader.py b/EvoScientist/cli/_agent_loader.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/cli/_agent_loader.py
@@ -0,0 +1,197 @@
+"""Background MCP/agent load lifecycle shared by CLI and TUI surfaces.
+
+Holds no references to Rich, prompt_toolkit, or Textual — UI-specific
+rendering and thread-hopping plug in via callbacks.
+"""
+
+from __future__ import annotations
+
+import asyncio
+import logging
+from collections.abc import Callable
+from typing import Any
+
+_logger = logging.getLogger(__name__)
+
+ProgressEvent = str  # "start" | "success" | "error"
+ProgressState = str  # "pending" | "ok" | "error"
+
+ProgressCallback = Callable[[ProgressEvent, str, str], None]
+SuccessCallback = Callable[[Any], None]
+FailureCallback = Callable[[BaseException], None]
+
+
+class MCPProgressTracker:
+    """Per-server MCP load progress state.
+
+    Reads and writes are GIL-atomic but iteration must go through
+    :meth:`snapshot` — events can fire from a worker thread while the
+    main thread renders.
+    """
+
+    __slots__ = ("progress",)
+
+    def __init__(self) -> None:
+        self.progress: dict[str, tuple[ProgressState, str]] = {}
+
+    def prime(self) -> None:
+        """Seed a ``pending`` entry for every configured server.
+
+        Keeps the UI's "N / M" denominator stable from the first render.
+        """
+        try:
+            from ..mcp import load_mcp_config
+
+            cfg = load_mcp_config() or {}
+            self.progress = dict.fromkeys(cfg, ("pending", ""))
+        except Exception:
+            self.progress = {}
+
+    def record(
+        self, event: ProgressEvent, server: str, detail: str
+    ) -> ProgressState | None:
+        """Apply an event and return the new state, or ``None`` if unknown."""
+        if event == "start":
+            self.progress.setdefault(server, ("pending", ""))
+            return "pending"
+        if event == "success":
+            self.progress[server] = ("ok", detail)
+            return "ok"
+        if event == "error":
+            self.progress[server] = ("error", detail)
+            return "error"
+        return None
+
+    def snapshot(self) -> list[tuple[ProgressState, str]]:
+        return list(self.progress.values())
+
+    def totals(self) -> tuple[int, int]:
+        """``(done, total)`` — done excludes ``pending``."""
+        snap = self.snapshot()
+        total = len(snap)
+        done = sum(1 for state, _ in snap if state != "pending")
+        return done, total
+
+
+class BackgroundAgentLoader:
+    """Owns the background ``_load_agent`` task and its generation token.
+
+    Each :meth:`start` bumps an internal id; callbacks from a superseded
+    load (the old worker thread keeps running after cancel, since
+    ``asyncio.to_thread`` can't preempt arbitrary Python code) compare
+    against it and drop silently.
+
+    ``on_progress`` fires on the **worker thread**; UI callers hop
+    threads inside it if needed.  ``on_success`` / ``on_failure`` fire
+    on the event loop when the task completes.
+    """
+
+    def __init__(
+        self,
+        loader_fn: Callable[..., Any],
+        *,
+        on_progress: ProgressCallback | None = None,
+        on_success: SuccessCallback | None = None,
+        on_failure: FailureCallback | None = None,
+    ) -> None:
+        self._loader_fn = loader_fn
+        self._on_progress = on_progress
+        self._on_success = on_success
+        self._on_failure = on_failure
+        self.agent: Any = None
+        self._task: asyncio.Task | None = None
+        self._load_id: int = 0
+
+    @property
+    def task(self) -> asyncio.Task | None:
+        return self._task
+
+    @property
+    def is_pending(self) -> bool:
+        return self.agent is None and self._task is not None and not self._task.done()
+
+    @property
+    def needs_restart(self) -> bool:
+        """True when no load is in flight and no agent is ready.
+
+        Callers that want auto-retry behavior (e.g. TUI on the next
+        user send after a failure) check this before :meth:`start`.
+        """
+        return self.agent is None and (self._task is None or self._task.done())
+
+    def start(self, **loader_kwargs: Any) -> None:
+        prev = self._task
+        if prev is not None and not prev.done():
+            prev.cancel()
+        self._load_id += 1
+        load_id = self._load_id
+        self.agent = None
+
+        def _gated_progress(event: str, server: str, detail: str) -> None:
+            if load_id != self._load_id:
+                return
+            if self._on_progress is None:
+                return
+            try:
+                self._on_progress(event, server, detail)
+            except Exception:
+                _logger.debug("MCP progress callback raised", exc_info=True)
+
+        self._task = asyncio.create_task(
+            asyncio.to_thread(
+                self._loader_fn,
+                on_mcp_progress=_gated_progress,
+                **loader_kwargs,
+            )
+        )
+        self._task.add_done_callback(lambda task, lid=load_id: self._on_done(task, lid))
+
+    def adopt(self, agent: Any) -> None:
+        """Install an externally-built agent and supersede any in-flight load.
+
+        Used by ``/model`` (and any other caller that constructs a
+        replacement agent directly): bumps the generation token so a
+        late-arriving background load can't clobber ``self.agent`` via
+        the done-callback, cancels the in-flight wrapper, and seats the
+        new agent immediately.
+        """
+        prev = self._task
+        if prev is not None and not prev.done():
+            prev.cancel()
+        self._load_id += 1
+        self._task = None
+        self.agent = agent
+
+    async def await_ready(self) -> Any:
+        """Return the loaded agent; re-raises on load failure.
+
+        Idempotent.  State transitions (setting ``self.agent``, calling
+        ``on_success`` / ``on_failure``) are handled exclusively by
+        :meth:`_on_done`, which fires before this ``await`` resumes
+        (asyncio guarantees done-callbacks run in registration order).
+        """
+        if self.agent is not None:
+            return self.agent
+        if self._task is None:
+            raise RuntimeError(
+                "BackgroundAgentLoader.await_ready called before start()"
+            )
+        await self._task
+        return self.agent
+
+    def _on_done(self, task: asyncio.Task, load_id: int) -> None:
+        if load_id != self._load_id:
+            return
+        if task.cancelled():
+            return
+        try:
+            self.agent = task.result()
+        except Exception as exc:
+            # Keep ``_task`` set so a later ``await_ready`` re-raises the
+            # real exception instead of the "before start()" sentinel.
+            self.agent = None
+            if self._on_failure is not None:
+                self._on_failure(exc)
+            return
+        if self._on_success is not None:
+            self._on_success(self.agent)
diff --git a/EvoScientist/cli/_constants.py b/EvoScientist/cli/_constants.py
--- a/EvoScientist/cli/_constants.py
+++ b/EvoScientist/cli/_constants.py
@@ -2,7 +2,14 @@
 
 from datetime import UTC, datetime
 
-from ..sessions import AGENT_NAME
+
+def _agent_name() -> str:
+    # Deferred import: ``sessions`` pulls in langgraph/aiosqlite (~300 ms)
+    # and is only needed when ``build_metadata`` is actually called.
+    from ..sessions import AGENT_NAME
+
+    return AGENT_NAME
+
 
 WELCOME_SLOGANS = [
     "Ready for vibe research? What do you want cooking?",
@@ -34,7 +41,7 @@
 def build_metadata(workspace_dir: str | None, model: str | None) -> dict:
     """Build metadata dict for LangGraph checkpoint persistence."""
     return {
-        "agent_name": AGENT_NAME,
+        "agent_name": _agent_name(),
         "updated_at": datetime.now(UTC).isoformat(),
         "workspace_dir": workspace_dir or "",
         "model": model or "",
diff --git a/EvoScientist/cli/agent.py b/EvoScientist/cli/agent.py
--- a/EvoScientist/cli/agent.py
+++ b/EvoScientist/cli/agent.py
@@ -58,7 +58,13 @@ def _create_session_workspace(name: str | None = None) -> str:
     return workspace_dir
 
 
-def _load_agent(workspace_dir: str | None = None, checkpointer=None, config=None):
+def _load_agent(
+    workspace_dir: str | None = None,
+    checkpointer=None,
+    config=None,
+    *,
+    on_mcp_progress=None,
+):
     """Load the CLI agent with optional persistent checkpointer.
 
     Args:
@@ -67,9 +73,14 @@ def _load_agent(workspace_dir: str | None = None, checkpointer=None, config=None
             Falls back to ``InMemorySaver`` when ``None``.
         config: Optional pre-loaded ``EvoScientistConfig``.  Forwarded to
             ``create_cli_agent`` to avoid double config loading.
+        on_mcp_progress: Optional per-server MCP progress callback.
+            Signature ``(event, server_name, detail) -> None``.
     """
     from ..EvoScientist import create_cli_agent
 
     return create_cli_agent(
-        workspace_dir=workspace_dir, checkpointer=checkpointer, config=config
+        workspace_dir=workspace_dir,
+        checkpointer=checkpointer,
+        config=config,
+        on_mcp_progress=on_mcp_progress,
     )
diff --git a/EvoScientist/cli/channel.py b/EvoScientist/cli/channel.py
--- a/EvoScientist/cli/channel.py
+++ b/EvoScientist/cli/channel.py
@@ -22,7 +22,7 @@
 from rich.table import Table
 from rich.text import Text
 
-from ..stream.display import console
+from ..stream.console import console
 
 _channel_logger = logging.getLogger(__name__)
 
diff --git a/EvoScientist/cli/commands.py b/EvoScientist/cli/commands.py
--- a/EvoScientist/cli/commands.py
+++ b/EvoScientist/cli/commands.py
@@ -15,7 +15,7 @@
 
 from ..llm.context_window import DEFAULT_CONTEXT_WINDOW_FALLBACK, resolve_context_window
 from ..paths import ensure_dirs, set_workspace_root
-from ..stream.display import console
+from ..stream.console import console
 from ._app import app, channel_app, config_app, mcp_app
 from ._constants import build_metadata
 from .agent import (
@@ -33,15 +33,13 @@
     channel_ask_user_prompt,
     channel_hitl_prompt,
 )
-from .interactive import cmd_interactive, cmd_run
 from .mcp_ui import (
     _mcp_add_server_from_kwargs,
     _mcp_edit_server_fields,
     _mcp_list_servers,
     _mcp_remove_server,
     _show_mcp_config,
 )
-from .tui_runtime import run_streaming
 
 # =============================================================================
 # Onboard command
@@ -515,6 +513,7 @@ def _serve_process_message(
     import asyncio
 
     from .channel import _bus_loop
+    from .tui_runtime import run_streaming
 
     console.print(
         f"[dim][{msg.channel_type}] {msg.sender}: {escape(msg.content[:80])}[/dim]"
@@ -1286,6 +1285,7 @@ def _main_callback(
             get_checkpointer,
             resolve_thread_id_prefix,
         )
+        from .interactive import cmd_run
 
         async def _single_shot():
             async with get_checkpointer() as checkpointer:
@@ -1330,6 +1330,8 @@ async def _single_shot():
         nest_asyncio.apply()
         asyncio.get_event_loop().run_until_complete(_single_shot())
     else:
+        from .interactive import cmd_interactive
+
         # Interactive mode (default) — checkpointer managed inside cmd_interactive
         cmd_interactive(
             show_thinking=show_thinking,
diff --git a/EvoScientist/cli/interactive.py b/EvoScientist/cli/interactive.py
--- a/EvoScientist/cli/interactive.py
+++ b/EvoScientist/cli/interactive.py
@@ -20,6 +20,7 @@
 from prompt_toolkit.formatted_text import HTML  # type: ignore[import-untyped]
 from prompt_toolkit.history import FileHistory  # type: ignore[import-untyped]
 from prompt_toolkit.key_binding import KeyBindings  # type: ignore[import-untyped]
+from prompt_toolkit.patch_stdout import patch_stdout  # type: ignore[import-untyped]
 from prompt_toolkit.shortcuts import CompleteStyle  # type: ignore[import-untyped]
 from prompt_toolkit.styles import Style as PtStyle  # type: ignore[import-untyped]
 from rich.markdown import Markdown
@@ -41,7 +42,8 @@
     resolve_thread_id_prefix,
     thread_exists,
 )
-from ..stream.display import console
+from ..stream.console import console
+from ._agent_loader import BackgroundAgentLoader, MCPProgressTracker
 from ._constants import LOGO_GRADIENT, LOGO_LINES, WELCOME_SLOGANS, build_metadata
 from .agent import _create_session_workspace, _load_agent, _shorten_path
 from .channel import (
@@ -62,6 +64,7 @@
     _cmd_uninstall_skill,
 )
 from .status_bar import (
+    SPINNER_FRAMES,
     STATUS_BAD,
     STATUS_BAR_BG,
     STATUS_CRITICAL,
@@ -83,6 +86,9 @@
 
 _channel_logger = logging.getLogger(__name__)
 
+# Keeps references to fire-and-forget coroutines so they aren't GC'd mid-flight.
+_background_tasks: set[asyncio.Task] = set()
+
 
 # =============================================================================
 # Banner
@@ -329,7 +335,6 @@ def _print_separator():
 
     # Mutable state for async loop
     state: dict[str, Any] = {
-        "agent": None,
         "thread_id": thread_id or generate_thread_id(),
         "workspace_dir": workspace_dir,
         "running": True,
@@ -342,6 +347,60 @@ def _print_separator():
         "status_last_input_tokens": None,
     }
 
+    progress_tracker = MCPProgressTracker()
+
+    def _on_mcp_progress(event: str, server: str, detail: str) -> None:
+        """Record progress + print the inline ✓/✗ line.
+
+        Runs on the MCP worker thread; ``console.print`` while the main
+        loop is inside ``patch_stdout`` lands above the prompt safely.
+        """
+        new_state = progress_tracker.record(event, server, detail)
+        if new_state == "ok":
+            console.print(
+                f"[green]\u2713[/green] [dim]MCP[/dim] [bold]{server}[/bold] "
+                f"[dim]({detail} tools)[/dim]"
+            )
+        elif new_state == "error":
+            console.print(
+                f"[red]\u2717[/red] [dim]MCP[/dim] [bold]{server}[/bold] "
+                f"[red]failed:[/red] {escape(detail)}"
+            )
+
+    agent_loader = BackgroundAgentLoader(
+        _load_agent,
+        on_progress=_on_mcp_progress,
+    )
+
+    def _start_agent_load(checkpointer) -> None:
+        progress_tracker.prime()
+        agent_loader.start(
+            workspace_dir=state["workspace_dir"],
+            checkpointer=checkpointer,
+            config=config,
+        )
+
+    async def _await_agent_ready() -> Any:
+        """Await the agent load and apply CLI-side post-load side effects.
+
+        Raises when called before ``_start_agent_load``: reloading here
+        would drop the SQLite checkpointer and silently lose persistence.
+        """
+        try:
+            agent = await agent_loader.await_ready()
+        except RuntimeError as exc:
+            if "before start()" in str(exc):
+                raise RuntimeError(
+                    "_await_agent_ready called before _start_agent_load — "
+                    "the checkpointer reference is not available here."
+                ) from exc
+            raise
+        await _refresh_status_snapshot(reset_streaming_text=True)
+        if _channels_is_running():
+            _ch_mod._cli_agent = agent
+            _ch_mod._cli_thread_id = state["thread_id"]
+        return agent
+
     def _rebuild_status_snapshot() -> None:
         """Compose the visible snapshot from thread state + live output."""
         state["status_snapshot"] = apply_assistant_text_to_snapshot(
@@ -401,11 +460,29 @@ def _bottom_toolbar():
             width = get_app().output.get_size().columns
         except Exception:
             width = console.size.width
-        return build_status_fragments(
+        fragments = build_status_fragments(
             state["status_snapshot"],
             state["status_started_at"],
             width,
         )
+        if agent_loader.is_pending:
+            # Per-server ✓/✗ lines are printed above the prompt by
+            # `_on_mcp_progress`; this just shows the animated summary.
+            done, total = progress_tracker.totals()
+            frame = SPINNER_FRAMES[
+                int(datetime.now().timestamp() * 10) % len(SPINNER_FRAMES)
+            ]
+            label = (
+                f"{frame} Loading MCP tools {done}/{total} "
+                if total and width >= 60
+                else f"{frame} Loading MCP tools "
+            )
+            fragments = [
+                ("class:status-bar-warn", label),
+                ("class:status-bar-dim", "│ "),
+                *fragments,
+            ]
+        return fragments
 
     def _stream_status_footer():
         """Render the live Rich footer used during streaming output."""
@@ -634,17 +711,10 @@ async def _cmd_resume(arg: str, checkpointer):
             state["workspace_dir"] = ws
         state["status_started_at"] = datetime.now()
         state["status_last_input_tokens"] = None
-        console.print("[dim]Loading session...[/dim]")
-        state["agent"] = _load_agent(
-            workspace_dir=state["workspace_dir"],
-            checkpointer=checkpointer,
-            config=config,
-        )
+        # Rebuild the agent in the background so the resumed transcript
+        # and prompt render immediately; the next message awaits the load.
+        _start_agent_load(checkpointer)
         await _refresh_status_snapshot(reset_streaming_text=True)
-        # Sync shared refs if channel is running
-        if _channels_is_running():
-            _ch_mod._cli_agent = state["agent"]
-            _ch_mod._cli_thread_id = state["thread_id"]
         console.print(f"[green]Resumed session:[/green] [yellow]{resolved}[/yellow]")
         if state["workspace_dir"]:
             console.print(
@@ -693,12 +763,11 @@ async def _async_main_loop():
                     # checkpointed under the bad prefix.
                     state["thread_id"] = generate_thread_id()
 
-            console.print("[dim]Loading agent...[/dim]")
-            state["agent"] = _load_agent(
-                workspace_dir=state["workspace_dir"],
-                checkpointer=checkpointer,
-                config=config,
-            )
+            # Kick off agent construction (MCP tool enumeration is the
+            # slow part) in the background so the banner and prompt can
+            # appear immediately.  The status bar shows a spinner while
+            # this is in flight; submitting a message awaits the result.
+            _start_agent_load(checkpointer)
             await _refresh_status_snapshot(reset_streaming_text=True)
 
             # Print banner
@@ -817,14 +886,15 @@ def _channel_ask_user(ask_user_data: dict) -> dict:
                     """Send ask_user questions to channel user and wait for reply."""
                     return _ch_mod.channel_ask_user_prompt(ask_user_data, msg)
 
-                meta = build_metadata(state["workspace_dir"], model)
                 try:
+                    ready_agent = await _await_agent_ready()
+                    meta = build_metadata(state["workspace_dir"], model)
                     await _refresh_status_snapshot(
                         msg.content, reset_streaming_text=True
                     )
                     response = run_streaming(
                         ui_backend=state["ui_backend"],
-                        agent=state["agent"],
+                        agent=ready_agent,
                         message=msg.content,
                         thread_id=state["thread_id"],
                         show_thinking=show_thinking,
@@ -877,7 +947,9 @@ async def _check_channel_queue() -> None:
                 )
             )
 
-            # Auto-start channel if enabled in config
+            # Auto-start channel if enabled in config.  Needs the agent
+            # bound before the bus starts polling, so schedule it as a
+            # background coroutine that waits for the loader first.
             from ..config import load_config
 
             _channel_cfg = load_config()
@@ -886,12 +958,29 @@ async def _check_channel_queue() -> None:
                 and _channel_cfg.channel_enabled
                 and not _channels_is_running()
             ):
-                _auto_start_channel(
-                    state["agent"],
-                    state["thread_id"],
-                    _channel_cfg,
-                    send_thinking=channel_send_thinking,
+
+                async def _deferred_auto_start_channel(cfg):
+                    try:
+                        agent = await _await_agent_ready()
+                    except Exception as e:
+                        console.print(
+                            f"[red]Channel auto-start skipped: agent load failed:[/red] "
+                            f"{escape(str(e))}"
+                        )
+                        return
+                    if not _channels_is_running():
+                        _auto_start_channel(
+                            agent,
+                            state["thread_id"],
+                            cfg,
+                            send_thinking=channel_send_thinking,
+                        )
+
+                _auto_start_task = asyncio.create_task(
+                    _deferred_auto_start_channel(_channel_cfg)
                 )
+                _background_tasks.add(_auto_start_task)
+                _auto_start_task.add_done_callback(_background_tasks.discard)
 
             # Update check — non-blocking, runs in background thread
             import concurrent.futures
@@ -927,11 +1016,16 @@ def _show_update_hint() -> None:
                 _print_separator()
                 while state["running"]:
                     try:
-                        user_input = await session.prompt_async(
-                            HTML("<ansiblue><b>\u276f</b></ansiblue> "),
-                            bottom_toolbar=_bottom_toolbar,
-                            refresh_interval=1.0,
-                        )
+                        # ``patch_stdout`` routes stray ``print`` /
+                        # ``console.print`` calls — including the MCP
+                        # progress callback firing from a worker thread —
+                        # above the live prompt instead of over it.
+                        with patch_stdout(raw=True):
+                            user_input = await session.prompt_async(
+                                HTML("<ansiblue><b>\u276f</b></ansiblue> "),
+                                bottom_toolbar=_bottom_toolbar,
+                                refresh_interval=1.0,
+                            )
                         user_input = user_input.strip()
 
                         if not user_input:
@@ -967,21 +1061,13 @@ def _show_update_hint() -> None:
                                 state["workspace_dir"] = _create_session_workspace(
                                     run_name
                                 )
-                            console.print("[dim]Loading new session...[/dim]")
-                            state["agent"] = _load_agent(
-                                workspace_dir=state["workspace_dir"],
-                                checkpointer=checkpointer,
-                                config=config,
-                            )
                             state["thread_id"] = generate_thread_id()
                             state["resumed"] = False
                             state["status_started_at"] = datetime.now()
                             state["status_last_input_tokens"] = None
+                            # Background agent reload — next message awaits it.
+                            _start_agent_load(checkpointer)
                             await _refresh_status_snapshot(reset_streaming_text=True)
-                            # Sync channel refs so the queue checker uses the new agent
-                            if _channels_is_running():
-                                _ch_mod._cli_agent = state["agent"]
-                                _ch_mod._cli_thread_id = state["thread_id"]
                             console.print(
                                 f"[green]New session:[/green] [yellow]{state['thread_id']}[/yellow]"
                             )
@@ -1035,9 +1121,10 @@ def _show_update_hint() -> None:
                                 stop_arg = args[len("stop") :].strip()
                                 _cmd_channel_stop(stop_arg or None)
                             else:
+                                await _await_agent_ready()
                                 _cmd_channel(
                                     args,
-                                    state["agent"],
+                                    agent_loader.agent,
                                     state["thread_id"],
                                     send_thinking=channel_send_thinking,
                                 )
@@ -1050,11 +1137,12 @@ def _show_update_hint() -> None:
                                 render_compact_result,
                             )
 
+                            await _await_agent_ready()
                             with console.status(
                                 "[cyan]Compacting conversation...[/cyan]"
                             ):
                                 result = await compact_conversation(
-                                    agent=state["agent"],
+                                    agent=agent_loader.agent,
                                     thread_id=state["thread_id"],
                                     input_tokens_hint=state.get(
                                         "status_last_input_tokens"
@@ -1085,18 +1173,20 @@ def _show_update_hint() -> None:
                             from ..EvoScientist import _ensure_config
                             from .rich_command_ui import RichCLICommandUI
 
+                            # /model is ``needs_agent=False`` — it builds its
+                            # own agent — so we don't wait for the current
+                            # load; /model is the way to fix a broken one.
                             ctx = CommandContext(
-                                agent=state["agent"],
+                                agent=None,
                                 thread_id=state["thread_id"],
                                 ui=RichCLICommandUI(console),
                                 workspace_dir=state["workspace_dir"],
                                 checkpointer=checkpointer,
                             )
                             await cmd_manager.execute(user_input, ctx)
 
-                            # Sync agent back if command replaced it (e.g. /model)
-                            if ctx.agent is not state["agent"]:
-                                state["agent"] = ctx.agent
+                            if ctx.agent is not None:
+                                agent_loader.adopt(ctx.agent)
                                 cfg = _ensure_config()
                                 model = cfg.model
                                 state["status_base_snapshot"] = (
@@ -1106,7 +1196,7 @@ def _show_update_hint() -> None:
                                     reset_streaming_text=True,
                                 )
                                 if _channels_is_running():
-                                    _ch_mod._cli_agent = state["agent"]
+                                    _ch_mod._cli_agent = ctx.agent
                                     _ch_mod._cli_thread_id = state["thread_id"]
                             continue
 
@@ -1121,13 +1211,14 @@ def _show_update_hint() -> None:
                         for w in file_warnings:
                             console.print(f"[yellow]⚠ {escape(w)}[/yellow]")
                         console.print()
+                        ready_agent = await _await_agent_ready()
                         meta = build_metadata(state["workspace_dir"], model)
                         await _refresh_status_snapshot(
                             message_to_send, reset_streaming_text=True
                         )
                         run_streaming(
                             ui_backend=state["ui_backend"],
-                            agent=state["agent"],
+                            agent=ready_agent,
                             message=message_to_send,
                             thread_id=state["thread_id"],
                             show_thinking=show_thinking,
diff --git a/EvoScientist/cli/mcp_install_cmd.py b/EvoScientist/cli/mcp_install_cmd.py
--- a/EvoScientist/cli/mcp_install_cmd.py
+++ b/EvoScientist/cli/mcp_install_cmd.py
@@ -20,7 +20,7 @@
     install_mcp_server,
     install_mcp_servers,
 )
-from ..stream.display import console
+from ..stream.console import console
 from .interactive import _PICKER_STYLE
 
 _INSTALLED_INDICATOR = ("fg:#4caf50", "\u2713 ")
diff --git a/EvoScientist/cli/mcp_ui.py b/EvoScientist/cli/mcp_ui.py
--- a/EvoScientist/cli/mcp_ui.py
+++ b/EvoScientist/cli/mcp_ui.py
@@ -4,7 +4,7 @@
 
 from rich.table import Table
 
-from ..stream.display import console
+from ..stream.console import console
 
 
 def _mcp_list_servers() -> None:
diff --git a/EvoScientist/cli/skills_cmd.py b/EvoScientist/cli/skills_cmd.py
--- a/EvoScientist/cli/skills_cmd.py
+++ b/EvoScientist/cli/skills_cmd.py
@@ -2,7 +2,7 @@
 
 from pathlib import Path
 
-from ..stream.display import console
+from ..stream.console import console
 from .agent import _shorten_path
 
 
diff --git a/EvoScientist/cli/status_bar.py b/EvoScientist/cli/status_bar.py
--- a/EvoScientist/cli/status_bar.py
+++ b/EvoScientist/cli/status_bar.py
@@ -27,6 +27,10 @@
 STATUS_HINT_IDLE = "#8b9bb0"
 STATUS_HINT_BUSY = "#f0c36a"
 
+# Braille spinner frames used by the CLI bottom toolbar and TUI status bar
+# to animate the "Loading MCP tools" indicator.
+SPINNER_FRAMES = "\u280b\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2807\u280f"
+
 
 @dataclass(slots=True)
 class SessionStatusSnapshot:
diff --git a/EvoScientist/cli/tui_interactive.py b/EvoScientist/cli/tui_interactive.py
--- a/EvoScientist/cli/tui_interactive.py
+++ b/EvoScientist/cli/tui_interactive.py
@@ -34,6 +34,7 @@
 )
 from ..stream.events import stream_agent_events
 from ..stream.state import _INTERNAL_TOOLS, StreamState
+from ._agent_loader import BackgroundAgentLoader, MCPProgressTracker
 from ._constants import LOGO_GRADIENT, LOGO_LINES, WELCOME_SLOGANS, build_metadata
 from .channel import (
     ChannelMessage,
@@ -221,6 +222,7 @@ def run_textual_interactive(
             AssistantMessage,
             CompactingWidget,
             LoadingWidget,
+            MCPLoaderWidget,
             SubAgentWidget,
             SummarizationWidget,
             SystemMessage,
@@ -323,7 +325,6 @@ def supports_interactive(self) -> bool:
         def __init__(
             self,
             *,
-            agent: Any,
             thread_id_value: str,
             workspace: str | None,
             checkpointer: Any,
@@ -332,7 +333,14 @@ def __init__(
             resume_warning: str = "",
         ) -> None:
             super().__init__()
-            self._agent = agent
+            self._progress_tracker = MCPProgressTracker()
+            self._agent_loader = BackgroundAgentLoader(
+                load_agent,
+                on_progress=self._on_mcp_progress,
+                on_success=self._on_agent_load_success,
+                on_failure=self._on_agent_load_failure,
+            )
+            self._mcp_loader_widget: Any = None
             self._conversation_tid = thread_id_value
             self._workspace_dir = workspace
             self._checkpointer = checkpointer
@@ -369,6 +377,88 @@ def __init__(
             self._status_last_input_tokens: int | None = None
             self._compacting_widget: CompactingWidget | None = None
 
+        # ── Background agent / MCP loading ───────────────────
+
+        def _on_mcp_progress(self, event: str, server: str, detail: str) -> None:
+            """Bridge worker-thread progress events to the Textual loop."""
+            if event not in {"start", "success", "error"}:
+                return
+            try:
+                self.call_from_thread(self._apply_mcp_progress, event, server, detail)
+            except Exception:
+                pass
+
+        def _apply_mcp_progress(self, event: str, server: str, detail: str) -> None:
+            """Update tracker + widget on the Textual thread."""
+            state = self._progress_tracker.record(event, server, detail)
+            if state is None:
+                return
+            widget = self._mcp_loader_widget
+            if widget is None or widget.dismissed:
+                self._mcp_loader_widget = None
+                return
+            widget.update_server(server, state, detail)
+
+        def _on_agent_load_success(self, agent: Any) -> None:
+            if _channels_is_running():
+                _ch_mod._cli_agent = agent
+                _ch_mod._cli_thread_id = self._conversation_tid
+            self._finish_loader_widget()
+            self._render_status()
+
+        def _on_agent_load_failure(self, exc: BaseException) -> None:
+            self._append_system(f"Agent failed to load: {exc}", style="red")
+            self._finish_loader_widget()
+
+        def _start_background_agent_load(self, workspace: str | None) -> None:
+            self._progress_tracker.prime()
+            self._mount_mcp_loader_widget()
+            self._agent_loader.start(
+                workspace_dir=workspace,
+                checkpointer=self._checkpointer,
+            )
+
+        def _mount_mcp_loader_widget(self) -> None:
+            if not self._progress_tracker.progress:
+                return
+            if self._mcp_loader_widget is not None:
+                try:
+                    self._mcp_loader_widget.remove()
+                except Exception:
+                    pass
+                self._mcp_loader_widget = None
+            widget = MCPLoaderWidget(list(self._progress_tracker.progress.keys()))
+            try:
+                shell = self.query_one("#input-shell", Container)
+                children = list(shell.children)
+                if children:
+                    shell.mount(widget, before=children[0])
+                else:
+                    shell.mount(widget)
+            except Exception:
+                # Compose hasn't happened yet — the mount will be retried
+                # from ``on_mount`` once the DOM is ready.
+                return
+            self._mcp_loader_widget = widget
+
+        def _finish_loader_widget(self) -> None:
+            """Call ``mark_finished`` and clear the ref if self-dismissed."""
+            widget = self._mcp_loader_widget
+            if widget is None:
+                return
+            try:
+                widget.mark_finished()
+            except Exception:
+                pass
+            if widget.dismissed:
+                self._mcp_loader_widget = None
+
+        async def _await_agent_ready(self) -> Any:
+            """Await the agent load, auto-retrying on cold-start or failure."""
+            if self._agent_loader.needs_restart:
+                self._start_background_agent_load(self._workspace_dir)
+            return await self._agent_loader.await_ready()
+
         # ── CommandUI implementation ─────────────────────────
 
         def append_system(self, text: str, style: str = "dim") -> None:
@@ -471,18 +561,13 @@ def start_new_session(self) -> None:
             if not workspace_fixed:
                 self._workspace_dir = create_session_workspace(run_name)
             self._conversation_tid = generate_thread_id()
-            self._agent = load_agent(
-                workspace_dir=self._workspace_dir,
-                checkpointer=self._checkpointer,
-            )
+            # Background reload: next user message awaits it.
+            self._start_background_agent_load(self._workspace_dir)
             self._status_started_at = datetime.now()
             self._status_base_snapshot = make_empty_status_snapshot(self._current_model)
             self._status_snapshot = self._status_base_snapshot
             self._status_streaming_text = ""
             self._status_last_input_tokens = None
-            if _channels_is_running():
-                _ch_mod._cli_agent = self._agent
-                _ch_mod._cli_thread_id = self._conversation_tid
             self._render_welcome()
             self._render_status()
             refresh_task = asyncio.create_task(self._refresh_status_snapshot())
@@ -497,18 +582,13 @@ async def handle_session_resume(
                 self._workspace_dir = workspace_dir
 
             self._conversation_tid = thread_id
-            self._agent = load_agent(
-                workspace_dir=self._workspace_dir,
-                checkpointer=self._checkpointer,
-            )
+            # Background reload: history renders immediately; next turn awaits.
+            self._start_background_agent_load(self._workspace_dir)
             self._status_started_at = datetime.now()
             self._status_base_snapshot = make_empty_status_snapshot(self._current_model)
             self._status_snapshot = self._status_base_snapshot
             self._status_streaming_text = ""
             self._status_last_input_tokens = None
-            if _channels_is_running():
-                _ch_mod._cli_agent = self._agent
-                _ch_mod._cli_thread_id = self._conversation_tid
             self._render_welcome()
             await self._refresh_status_snapshot()
             self._render_status()
@@ -543,6 +623,10 @@ def on_mount(self) -> None:
             self._render_welcome()
             self._render_status()
             self.set_interval(1.0, self._render_status)
+            # Kick off agent construction in the background so the TUI
+            # appears instantly; MCP progress shows up in the status bar.
+            if self._agent_loader.agent is None and self._agent_loader.task is None:
+                self._start_background_agent_load(self._workspace_dir)
             refresh_task = asyncio.create_task(self._refresh_status_snapshot())
             self._background_tasks.add(refresh_task)
             refresh_task.add_done_callback(self._background_tasks.discard)
@@ -572,8 +656,22 @@ def on_mount(self) -> None:
             self.run_worker(
                 self._check_for_updates, exclusive=True, group="update-check"
             )
-            # Auto-start channels
-            self._start_channels()
+
+            # Auto-start channels — needs the agent, so defer to after load
+            async def _deferred_start_channels():
+                try:
+                    await self._await_agent_ready()
+                except Exception:
+                    _channel_logger.debug(
+                        "Skipping channel auto-start because agent load failed",
+                        exc_info=True,
+                    )
+                    return
+                self._start_channels()
+
+            ch_task = asyncio.create_task(_deferred_start_channels())
+            self._background_tasks.add(ch_task)
+            ch_task.add_done_callback(self._background_tasks.discard)
 
         # ── Update check ──────────────────────────────────────
 
@@ -604,7 +702,7 @@ def _start_channels(self) -> None:
                 cfg = load_config()
                 if cfg and cfg.channel_enabled and not _channels_is_running():
                     _auto_start_channel(
-                        self._agent,
+                        self._agent_loader.agent,
                         self._conversation_tid,
                         cfg,
                         send_thinking=self._channel_send_thinking,
@@ -1050,7 +1148,7 @@ def _find_or_rename_sa_widget(
                     summarization_w = None
                 try:
                     async for event in stream_agent_events(
-                        self._agent,
+                        self._agent_loader.agent,
                         _stream_input,
                         self._conversation_tid,
                         metadata=metadata,
@@ -1597,6 +1695,14 @@ async def _run_turn(self, user_text: str) -> None:
                 )
                 await self._refresh_status_snapshot(message_to_send)
 
+                # Block the turn on MCP tools finishing, if still in flight.
+                # ``_on_agent_load_failure`` is the sole reporter for load
+                # errors; callers just return so the send is dropped.
+                try:
+                    await self._await_agent_ready()
+                except Exception:
+                    return
+
                 await self._stream_with_widgets(
                     message_to_send,
                     display_text=user_text,
@@ -1717,8 +1823,19 @@ def _channel_ask_user(ask_user_data: dict) -> dict:
 
                 # Handle slash commands from channel
                 if msg.content.strip().startswith("/"):
+                    # Only wait for the agent if the command actually
+                    # needs it — otherwise ``/mcp add`` & friends would
+                    # hang behind a failing MCP load they're meant to fix.
+                    cmd, cmd_args = cmd_manager.resolve(msg.content) or (None, [])
+                    agent = None
+                    if cmd is not None and cmd.needs_agent(cmd_args):
+                        try:
+                            agent = await self._await_agent_ready()
+                        except Exception as exc:
+                            _set_channel_response(msg.msg_id, f"Error: {exc}")
+                            return
                     ctx = CommandContext(
-                        agent=self._agent,
+                        agent=agent,
                         thread_id=self._conversation_tid,
                         ui=ChannelCommandUI(
                             msg,
@@ -1751,6 +1868,14 @@ def _channel_ask_user(ask_user_data: dict) -> dict:
                         )
                         return  # outer finally handles _busy / widget cleanup
 
+                # Non-slash message — streams through the agent, so wait
+                # for readiness now.
+                try:
+                    await self._await_agent_ready()
+                except Exception as exc:
+                    _set_channel_response(msg.msg_id, f"Error: {exc}")
+                    return
+
                 response = ""
                 try:
                     response = await self._stream_with_widgets(
@@ -2136,22 +2261,41 @@ async def _handle_command(self, command: str) -> None:
             prompt_widget.disabled = True
             self._render_status()
 
-            ctx = CommandContext(
-                agent=self._agent,
-                thread_id=self._conversation_tid,
-                ui=self,
-                workspace_dir=self._workspace_dir,
-                checkpointer=self._checkpointer,
-                input_tokens_hint=self._status_last_input_tokens,
-            )
-
             try:
+                # Only gate on agent readiness for commands that need it —
+                # recovery commands like ``/mcp add`` must run even when
+                # ``_await_agent_ready`` would hang on a broken MCP load.
+                cmd, cmd_args = cmd_manager.resolve(command) or (None, [])
+                agent = None
+                if cmd is not None and cmd.needs_agent(cmd_args):
+                    try:
+                        agent = await self._await_agent_ready()
+                    except Exception:
+                        # ``_on_agent_load_failure`` already surfaced the error.
+                        return
+                ctx = CommandContext(
+                    agent=agent,
+                    thread_id=self._conversation_tid,
+                    ui=self,
+                    workspace_dir=self._workspace_dir,
+                    checkpointer=self._checkpointer,
+                    input_tokens_hint=self._status_last_input_tokens,
+                )
+
                 if await cmd_manager.execute(command, ctx):
-                    # Sync agent back if command replaced it (e.g. /model)
-                    if ctx.agent is not self._agent:
-                        self._agent = ctx.agent
+                    # Sync agent back if command replaced it (e.g. /model).
+                    # ``is not None`` guard: non-agent commands (ctx.agent
+                    # starts None) must not clobber a valid loaded agent.
+                    if (
+                        ctx.agent is not None
+                        and ctx.agent is not self._agent_loader.agent
+                    ):
+                        # ``adopt`` also cancels/supersedes any in-flight
+                        # load so a late completion can't overwrite the
+                        # replacement agent (/model on a broken provider).
+                        self._agent_loader.adopt(ctx.agent)
                         if _channels_is_running():
-                            _ch_mod._cli_agent = self._agent
+                            _ch_mod._cli_agent = ctx.agent
                             _ch_mod._cli_thread_id = self._conversation_tid
                     # Do NOT invalidate the usage baseline after /compact.
                     # build_session_status_snapshot() only counts raw checkpoint
@@ -2445,6 +2589,8 @@ def _render_status(self) -> None:
                 or getattr(self.screen.size, "width", 0)
                 or 80
             )
+            # MCP load progress lives in the dedicated MCPLoaderWidget
+            # above the input bar — no need to duplicate it here.
             if self._busy:
                 hint_label = "vibe researching..."
                 hint_style = f"on {STATUS_BAR_BG} {STATUS_HINT_BUSY} bold"
@@ -2540,12 +2686,10 @@ async def _amain() -> None:
             if not effective_thread_id:
                 effective_thread_id = generate_thread_id()
 
-            initial_agent = load_agent(
-                workspace_dir=effective_workspace,
-                checkpointer=checkpointer,
-            )
+            # The TUI opens instantly and starts MCP loading in the
+            # background; ``on_mount`` in the app kicks off the real
+            # ``load_agent`` call and awaits it before the first turn.
             app = EvoTextualInteractiveApp(
-                agent=initial_agent,
                 thread_id_value=effective_thread_id,
                 workspace=effective_workspace,
                 checkpointer=checkpointer,
diff --git a/EvoScientist/cli/tui_runtime.py b/EvoScientist/cli/tui_runtime.py
--- a/EvoScientist/cli/tui_runtime.py
+++ b/EvoScientist/cli/tui_runtime.py
@@ -5,7 +5,7 @@
 from collections.abc import Callable
 from typing import Any
 
-from ..stream.display import console
+from ..stream.console import console
 from .tui_backends import RichStreamingBackend, StreamingTUIBackend
 
 DEFAULT_UI_BACKEND = "cli"
diff --git a/EvoScientist/cli/widgets/__init__.py b/EvoScientist/cli/widgets/__init__.py
--- a/EvoScientist/cli/widgets/__init__.py
+++ b/EvoScientist/cli/widgets/__init__.py
@@ -6,6 +6,7 @@
 from .compact_summary_widget import CompactSummaryWidget
 from .compacting_widget import CompactingWidget
 from .loading_widget import LoadingWidget
+from .mcp_loader_widget import MCPLoaderWidget
 from .subagent_widget import SubAgentWidget
 from .summarization_widget import SummarizationWidget
 from .system_message import SystemMessage
@@ -23,6 +24,7 @@
     "CompactSummaryWidget",
     "CompactingWidget",
     "LoadingWidget",
+    "MCPLoaderWidget",
     "SubAgentWidget",
     "SummarizationWidget",
     "SystemMessage",
diff --git a/EvoScientist/cli/widgets/mcp_loader_widget.py b/EvoScientist/cli/widgets/mcp_loader_widget.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/cli/widgets/mcp_loader_widget.py
@@ -0,0 +1,191 @@
+"""Live-updating widget that shows per-server MCP load progress.
+
+Mounted above the chat input while MCP tools are being fetched in the
+background.  Re-renders on a 100 ms tick so the spinner animates and the
+per-server states transition smoothly from pending → ok/error.
+
+When the load finishes:
+- All-success runs auto-dismiss after a short grace period so the chat
+  area isn't permanently crowded.
+- Failures stick around longer so the user has time to read the error
+  detail, then auto-dismiss — otherwise the widget pins itself above
+  the input forever.
+"""
+
+from __future__ import annotations
+
+import time
+
+from rich.text import Text
+from textual.widgets import Static
+
+from ..status_bar import SPINNER_FRAMES
+
+_DIM = "#7c8594"
+_STRONG = "#e5e7eb"
+_GOOD = "#5fcf8b"
+_WARN = "#d7b45a"
+_BAD = "#d86f6f"
+
+# How long to wait after an all-success load before auto-dismissing.
+_AUTO_DISMISS_SECONDS = 2.5
+# Longer grace on failure so the user has time to read error detail.
+_AUTO_DISMISS_ON_ERROR_SECONDS = 12.0
+
+
+class MCPLoaderWidget(Static):
+    """Shows a header line + one line per MCP server with its live status."""
+
+    DEFAULT_CSS = """
+    MCPLoaderWidget {
+        height: auto;
+        padding: 0 1;
+        margin: 0 0 1 0;
+    }
+    """
+
+    TICK_SECONDS = 0.1
+
+    def __init__(self, servers: list[str]) -> None:
+        # server_name -> (state, detail); state ∈ {"pending","ok","error"}.
+        self._progress: dict[str, tuple[str, str]] = dict.fromkeys(
+            servers, ("pending", "")
+        )
+        self._frame = 0
+        self._tick_handle = None
+        self._finished = False
+        self._dismissed = False
+        self._auto_dismiss_at: float | None = None
+        # Seed with real content so Textual can measure us before the
+        # first tick; ``self.update()`` during ``__init__`` is unsafe
+        # (widget isn't attached yet), but we can pass the renderable
+        # straight into ``Static.__init__``.
+        super().__init__(self._build_renderable())
+
+    def on_mount(self) -> None:
+        self._tick_handle = self.set_interval(self.TICK_SECONDS, self._tick)
+
+    def on_unmount(self) -> None:
+        if self._tick_handle is not None:
+            self._tick_handle.stop()
+            self._tick_handle = None
+
+    # ── Public API ───────────────────────────────────────────────────
+
+    @property
+    def dismissed(self) -> bool:
+        """Whether the widget has already removed itself from the DOM."""
+        return self._dismissed
+
+    def update_server(self, name: str, state: str, detail: str = "") -> None:
+        """Record a progress event for one server and re-render."""
+        if self._dismissed or state not in ("pending", "ok", "error"):
+            return
+        # First-time-seen servers (e.g., ones missing from the initial
+        # prime set because the config file changed mid-load) just get
+        # appended — order stays stable for already-known entries.
+        self._progress[name] = (state, detail)
+        self._refresh_content()
+
+    def mark_finished(self) -> None:
+        """Call once the background load task resolves (success or error).
+
+        If nothing ever progressed past ``pending``, the load was served
+        from cache (no events emitted) — drop the widget immediately
+        instead of flashing a misleading "0/N loaded" header.
+
+        Otherwise schedule an auto-dismiss: short on full success so the
+        chat area isn't cluttered, longer on failure so the user has
+        time to read the error detail before it goes away.
+        """
+        if self._finished:
+            return
+        self._finished = True
+        progressed = any(state != "pending" for state, _ in self._progress.values())
+        if not progressed:
+            self._dismiss()
+            return
+        has_errors = any(state == "error" for state, _ in self._progress.values())
+        delay = _AUTO_DISMISS_ON_ERROR_SECONDS if has_errors else _AUTO_DISMISS_SECONDS
+        self._auto_dismiss_at = time.monotonic() + delay
+        self._refresh_content()
+
+    # ── Internal ─────────────────────────────────────────────────────
+
+    def _tick(self) -> None:
+        self._frame = (self._frame + 1) % len(SPINNER_FRAMES)
+        if (
+            self._auto_dismiss_at is not None
+            and time.monotonic() >= self._auto_dismiss_at
+        ):
+            self._auto_dismiss_at = None
+            self._dismiss()
+            return
+        if not self._finished:
+            self._refresh_content()
+
+    def _dismiss(self) -> None:
+        """Stop the tick timer and detach from the DOM.
+
+        Sets :attr:`dismissed` so the app can clear its widget reference
+        and late progress events become no-ops.
+        """
+        if self._dismissed:
+            return
+        self._dismissed = True
+        if self._tick_handle is not None:
+            self._tick_handle.stop()
+            self._tick_handle = None
+        # Fire-and-forget remove — nothing awaits us.
+        self.remove()
+
+    def _build_renderable(self) -> Text:
+        spinner = SPINNER_FRAMES[self._frame]
+        pending = sum(1 for state, _ in self._progress.values() if state == "pending")
+        total = len(self._progress)
+        done = total - pending
+
+        header = Text()
+        if self._finished:
+            errors = sum(1 for state, _ in self._progress.values() if state == "error")
+            if errors:
+                header.append("✗ MCP ", style=f"{_BAD} bold")
+                header.append(
+                    f"{done - errors}/{total} loaded, {errors} failed",
+                    style=_STRONG,
+                )
+            else:
+                header.append("✓ MCP ", style=f"{_GOOD} bold")
+                header.append(f"{done}/{total} servers loaded", style=_STRONG)
+        else:
+            header.append(f"{spinner} ", style=f"{_WARN} bold")
+            header.append("Loading MCP tools ", style=_STRONG)
+            header.append(f"{done}/{total}", style=_DIM)
+
+        lines: list[Text] = [header]
+        for name, (state, detail) in self._progress.items():
+            line = Text("  ")
+            if state == "pending":
+                line.append(f"{spinner} ", style=_WARN)
+                line.append(name, style=_DIM)
+            elif state == "ok":
+                line.append("✓ ", style=_GOOD)
+                line.append(name, style=_STRONG)
+                if detail:
+                    line.append(f"  {detail} tools", style=_DIM)
+            else:  # error
+                line.append("✗ ", style=_BAD)
+                line.append(name, style=_STRONG)
+                if detail:
+                    summary = detail if len(detail) <= 80 else detail[:77] + "…"
+                    line.append(f"  {summary}", style=_BAD)
+            lines.append(line)
+
+        return Text("\n").join(lines)
+
+    def _refresh_content(self) -> None:
+        # NB: don't name this ``_render`` — that shadows Textual's internal
+        # ``Widget._render`` which must return a ``Visual``.  Silently
+        # breaking that contract triggers ``'NoneType' object has no
+        # attribute 'get_height'`` during layout.
+        self.update(self._build_renderable())
diff --git a/EvoScientist/commands/base.py b/EvoScientist/commands/base.py
--- a/EvoScientist/commands/base.py
+++ b/EvoScientist/commands/base.py
@@ -73,6 +73,20 @@ class Command(ABC):
     alias: ClassVar[list[str]] = []
     description: str
     arguments: ClassVar[list[Argument]] = []
+    # When False, callers may dispatch this command without waiting for
+    # the background agent load to finish — important so recovery
+    # commands like ``/mcp add`` can run even when the MCP load is
+    # failing and ``_await_agent_ready`` would hang.
+    requires_agent: ClassVar[bool] = False
+
+    def needs_agent(self, args: list[str]) -> bool:
+        """Whether this specific invocation needs the agent.
+
+        Default returns :attr:`requires_agent`.  Override when a command
+        has a mix of agent-using and agent-free subcommands (e.g.
+        ``/channel start`` vs ``/channel status``).
+        """
+        return self.requires_agent
 
     @abstractmethod
     async def execute(self, ctx: CommandContext, args: list[str]) -> None:
diff --git a/EvoScientist/commands/implementation/channel.py b/EvoScientist/commands/implementation/channel.py
--- a/EvoScientist/commands/implementation/channel.py
+++ b/EvoScientist/commands/implementation/channel.py
@@ -14,6 +14,14 @@ class ChannelCommand(Command):
     name = "/channel"
     description = "Configure messaging channels"
 
+    def needs_agent(self, args: list[str]) -> bool:
+        # ``status`` and ``stop`` are introspection / teardown; they
+        # must work even when the agent load is still in flight or has
+        # failed.  Only start/add flows feed ``ctx.agent`` into
+        # ``_start_channels_bus_mode``.
+        subcmd = args[0].lower() if args else ""
+        return subcmd not in {"status", "stop"}
+
     async def execute(self, ctx: CommandContext, args: list[str]) -> None:
         import EvoScientist.cli.channel as _ch_mod
 
diff --git a/EvoScientist/commands/implementation/session.py b/EvoScientist/commands/implementation/session.py
--- a/EvoScientist/commands/implementation/session.py
+++ b/EvoScientist/commands/implementation/session.py
@@ -14,6 +14,7 @@ class CompactCommand(Command):
 
     name = "/compact"
     description = "Compact conversation to free context"
+    requires_agent = True
 
     async def execute(self, ctx: CommandContext, args: list[str]) -> None:
         from ...cli.commands import (
diff --git a/EvoScientist/commands/manager.py b/EvoScientist/commands/manager.py
--- a/EvoScientist/commands/manager.py
+++ b/EvoScientist/commands/manager.py
@@ -27,6 +27,27 @@ def get_command(self, name: str) -> Command | None:
         """Lookup a command by name."""
         return self._commands.get(name.lower())
 
+    def resolve(self, command_str: str) -> tuple[Command, list[str]] | None:
+        """Return ``(command, args)`` for the dispatch of ``command_str``.
+
+        Uses the same parsing as :meth:`execute` so callers can inspect
+        metadata (e.g. call :meth:`Command.needs_agent`) without
+        re-implementing ``shlex`` quirks.
+        """
+        command_str = command_str.strip()
+        if not command_str:
+            return None
+        try:
+            parts = shlex.split(command_str)
+        except ValueError:
+            parts = command_str.split()
+        if not parts:
+            return None
+        cmd = self.get_command(parts[0])
+        if cmd is None:
+            return None
+        return cmd, parts[1:]
+
     def list_commands(self) -> list[tuple[str, str]]:
         """List all registered command names and descriptions."""
         seen = set()
diff --git a/EvoScientist/llm/__init__.py b/EvoScientist/llm/__init__.py
--- a/EvoScientist/llm/__init__.py
+++ b/EvoScientist/llm/__init__.py
@@ -2,30 +2,32 @@
 
 Provides a unified interface for creating chat model instances
 with support for multiple providers.
+
+``models`` is attached lazily via :mod:`lazy_loader` (SPEC-1 / PEP 562) so
+that importing ``EvoScientist.llm`` (or any of its submodules, like
+``context_window``) does not eagerly drag in ``langchain.chat_models`` and
+its transitive ``langchain_anthropic``/``langchain_openai`` stack — that's
+roughly 1 s of wall time on every CLI invocation.
 """
 
-from .context_window import (
-    DEFAULT_CONTEXT_WINDOW_FALLBACK,
-    get_context_window,
-    resolve_context_window,
-)
-from .models import (
-    DEFAULT_MODEL,
-    MODELS,
-    get_chat_model,
-    get_model_info,
-    get_models_for_provider,
-    list_models,
-)
+import lazy_loader as _lazy
 
-__all__ = [
-    "DEFAULT_CONTEXT_WINDOW_FALLBACK",
-    "DEFAULT_MODEL",
-    "MODELS",
-    "get_chat_model",
-    "get_context_window",
-    "get_model_info",
-    "get_models_for_provider",
-    "list_models",
-    "resolve_context_window",
-]
+__getattr__, __dir__, __all__ = _lazy.attach(
+    __name__,
+    submodules=["context_window", "models", "patches"],
+    submod_attrs={
+        "context_window": [
+            "DEFAULT_CONTEXT_WINDOW_FALLBACK",
+            "get_context_window",
+            "resolve_context_window",
+        ],
+        "models": [
+            "DEFAULT_MODEL",
+            "MODELS",
+            "get_chat_model",
+            "get_model_info",
+            "get_models_for_provider",
+            "list_models",
+        ],
+    },
+)
diff --git a/EvoScientist/mcp/client.py b/EvoScientist/mcp/client.py
--- a/EvoScientist/mcp/client.py
+++ b/EvoScientist/mcp/client.py
@@ -13,6 +13,7 @@
 import re
 import shutil
 import sys
+from collections.abc import Callable
 from pathlib import Path
 from typing import Any
 
@@ -33,6 +34,11 @@
 # URL-based transports (share the same connection shape)
 _URL_TRANSPORTS = {"http", "streamable_http", "sse", "websocket"}
 
+# Upper bound on simultaneous ``get_tools`` attempts in :func:`_load_tools`.
+# Keeps stdio-server fleets from spawning 20+ subprocesses at once while
+# still parallelizing the common 3–7 server case to completion.
+_MAX_CONCURRENT_CONNECTIONS = 8
+
 # Env vars forwarded to stdio MCP subprocesses on top of the MCP SDK's
 # minimal default set (HOME/PATH/USER/…). Without this, servers behind
 # a proxy or with a custom CA bundle silently fail with long timeouts.
@@ -649,7 +655,20 @@ def _route_tools(
     return by_agent
 
 
-async def _load_tools(config: dict[str, Any]) -> dict[str, list]:
+ProgressCallback = Callable[[str, str, str], None]
+"""Per-server progress callback: ``(event, server_name, detail)``.
+
+- ``event="start"``   — connection attempt has begun.  ``detail`` is empty.
+- ``event="success"`` — tools fetched.  ``detail`` is the count as a string.
+- ``event="error"``   — failed.  ``detail`` is the exception message.
+"""
+
+
+async def _load_tools(
+    config: dict[str, Any],
+    *,
+    on_progress: ProgressCallback | None = None,
+) -> dict[str, list]:
     """Connect to MCP servers and retrieve tools.
 
     Returns a dict of server name -> list of LangChain tools.
@@ -669,43 +688,81 @@ async def _load_tools(config: dict[str, Any]) -> dict[str, list]:
     if not connections:
         return {}
 
-    server_tools: dict[str, list] = {}
     client = MultiServerMCPClient(connections)  # type: ignore[invalid-argument-type]
 
-    for server_name in connections:
+    def _report(event: str, name: str, detail: str = "") -> None:
+        if on_progress is None:
+            return
         try:
-            tools = await client.get_tools(server_name=server_name)
-            server_tools[server_name] = tools
-            logger.info("MCP server %r: loaded %d tool(s)", server_name, len(tools))
-        except Exception as exc:
-            logger.warning("MCP server %r: failed to load tools: %s", server_name, exc)
-            server_tools[server_name] = []
-
-    return server_tools
-
-
-async def aload_mcp_tools(config: dict[str, Any] | None = None) -> dict[str, list]:
+            on_progress(event, name, detail)
+        except Exception:
+            # Progress callbacks are UI glue — never let their bugs break
+            # the actual MCP load.
+            logger.debug("MCP progress callback raised", exc_info=True)
+
+    # Cap in-flight connections so a user with many servers doesn't
+    # spawn all their stdio subprocesses at once (fd/ulimit pressure,
+    # load spikes).  The cap still parallelizes ~an order of magnitude
+    # better than the old serial loop.
+    sem = asyncio.Semaphore(_MAX_CONCURRENT_CONNECTIONS)
+
+    async def _fetch(name: str) -> tuple[str, list]:
+        async with sem:
+            _report("start", name)
+            try:
+                tools = await client.get_tools(server_name=name)
+                logger.info("MCP server %r: loaded %d tool(s)", name, len(tools))
+                _report("success", name, str(len(tools)))
+                return name, tools
+            except Exception as exc:
+                # When the caller wired up ``on_progress`` they own the
+                # user-facing display; downgrade the logger so we don't
+                # double-print.
+                if on_progress is None:
+                    logger.warning("MCP server %r: failed to load tools: %s", name, exc)
+                else:
+                    logger.debug("MCP server %r: failed to load tools: %s", name, exc)
+                _report("error", name, str(exc))
+                return name, []
+
+    # ``return_exceptions=False`` is fine because ``_fetch`` already
+    # swallows errors per server.
+    results = await asyncio.gather(*(_fetch(name) for name in connections))
+    return dict(results)
+
+
+async def aload_mcp_tools(
+    config: dict[str, Any] | None = None,
+    *,
+    on_progress: ProgressCallback | None = None,
+) -> dict[str, list]:
     """Async version of :func:`load_mcp_tools`.
 
     Prefer this when already inside an async context (e.g. Jupyter, async CLI).
 
     Args:
         config: Optional pre-loaded MCP config dict.  When ``None``,
             loads from ``~/.config/evoscientist/mcp.yaml``.
+        on_progress: Optional callback invoked per server with
+            ``(event, server_name, detail)``.  See :data:`ProgressCallback`.
     """
     if config is None:
         config = load_mcp_config()
     if not config:
         return {}
     try:
-        server_tools = await _load_tools(config)
+        server_tools = await _load_tools(config, on_progress=on_progress)
     except Exception as exc:
         logger.warning("MCP tool loading failed: %s", exc)
         return {}
     return _route_tools(config, server_tools)
 
 
-def load_mcp_tools(config: dict[str, Any] | None = None) -> dict[str, list]:
+def load_mcp_tools(
+    config: dict[str, Any] | None = None,
+    *,
+    on_progress: ProgressCallback | None = None,
+) -> dict[str, list]:
     """Load MCP tools and return them grouped by target agent.
 
     This is the main synchronous entry point. It:
@@ -719,6 +776,8 @@ def load_mcp_tools(config: dict[str, Any] | None = None) -> dict[str, list]:
             loads from ``~/.config/evoscientist/mcp.yaml``.  Passing a
             pre-loaded config avoids duplicate env-var interpolation
             warnings when the caller has already loaded the config.
+        on_progress: Optional callback invoked per server with
+            ``(event, server_name, detail)``.  See :data:`ProgressCallback`.
 
     Returns:
         Dict mapping agent name -> list of LangChain ``BaseTool`` objects.
@@ -742,7 +801,7 @@ def load_mcp_tools(config: dict[str, Any] | None = None) -> dict[str, list]:
             import nest_asyncio
 
             nest_asyncio.apply()
-        server_tools = asyncio.run(_load_tools(config))
+        server_tools = asyncio.run(_load_tools(config, on_progress=on_progress))
     except Exception as exc:
         logger.warning("MCP tool loading failed: %s", exc)
         return {}
diff --git a/EvoScientist/mcp/registry.py b/EvoScientist/mcp/registry.py
--- a/EvoScientist/mcp/registry.py
+++ b/EvoScientist/mcp/registry.py
@@ -507,7 +507,7 @@ def install_mcp_server(
     if print_fn is None:
 
         def print_fn(text: str, style: str = "") -> None:
-            from ..stream.display import console
+            from ..stream.console import console
 
             console.print(f"[{style}]{text}[/{style}]" if style else text)
 
diff --git a/EvoScientist/stream/__init__.py b/EvoScientist/stream/__init__.py
--- a/EvoScientist/stream/__init__.py
+++ b/EvoScientist/stream/__init__.py
@@ -9,76 +9,61 @@
 - SubAgentState / StreamState: Stream state tracking
 - stream_agent_events: Async event generator
 - Display functions: Rich rendering for streaming and final output
+
+Re-exports are attached lazily via :mod:`lazy_loader` (SPEC-1 / PEP 562) so
+that ``import EvoScientist.stream`` (or ``from .stream.state import ...``)
+does not drag in ``stream.display``/``stream.events`` — that load cascades
+into ``langchain_core.messages`` and is deferred until an actually-used
+symbol forces it.
 """
 
-from .diff_format import build_edit_diff, format_diff_rich
-from .display import (
-    _astream_to_console,
-    console,
-    create_streaming_display,
-    display_final_results,
-    format_tool_result_compact,
-    formatter,
-)
-from .emitter import StreamEvent, StreamEventEmitter
-from .events import stream_agent_events
-from .formatter import ContentType, FormattedResult, ToolResultFormatter
-from .state import StreamState, SubAgentState, _build_todo_stats, _parse_todo_items
-from .tracker import ToolCallInfo, ToolCallTracker
-from .utils import (
-    FAILURE_PREFIX,
-    SUCCESS_PREFIX,
-    DisplayLimits,
-    ToolStatus,
-    count_lines,
-    format_tool_compact,
-    format_tree_output,
-    get_status_symbol,
-    has_args,
-    is_success,
-    truncate,
-    truncate_with_line_hint,
-)
+import lazy_loader as _lazy
 
-__all__ = [
-    "FAILURE_PREFIX",
-    # Utils
-    "SUCCESS_PREFIX",
-    "ContentType",
-    "DisplayLimits",
-    "FormattedResult",
-    "StreamEvent",
-    # Emitter
-    "StreamEventEmitter",
-    "StreamState",
-    # State
-    "SubAgentState",
-    "ToolCallInfo",
-    # Tracker
-    "ToolCallTracker",
-    # Formatter
-    "ToolResultFormatter",
-    "ToolStatus",
-    "_astream_to_console",
-    "_build_todo_stats",
-    "_parse_todo_items",
-    # Diff formatting
-    "build_edit_diff",
-    # Display
-    "console",
-    "count_lines",
-    "create_streaming_display",
-    "display_final_results",
-    "format_diff_rich",
-    "format_tool_compact",
-    "format_tool_result_compact",
-    "format_tree_output",
-    "formatter",
-    "get_status_symbol",
-    "has_args",
-    "is_success",
-    # Events
-    "stream_agent_events",
-    "truncate",
-    "truncate_with_line_hint",
-]
+__getattr__, __dir__, __all__ = _lazy.attach(
+    __name__,
+    submodules=[
+        "diff_format",
+        "display",
+        "emitter",
+        "events",
+        "formatter",
+        "state",
+        "tracker",
+        "utils",
+    ],
+    submod_attrs={
+        "console": ["console"],
+        "diff_format": ["build_edit_diff", "format_diff_rich"],
+        "display": [
+            "_astream_to_console",
+            "create_streaming_display",
+            "display_final_results",
+            "format_tool_result_compact",
+            "formatter",
+        ],
+        "emitter": ["StreamEvent", "StreamEventEmitter"],
+        "events": ["stream_agent_events"],
+        "formatter": ["ContentType", "FormattedResult", "ToolResultFormatter"],
+        "state": [
+            "StreamState",
+            "SubAgentState",
+            "_build_todo_stats",
+            "_parse_todo_items",
+        ],
+        "tracker": ["ToolCallInfo", "ToolCallTracker"],
+        "utils": [
+            "FAILURE_PREFIX",
+            "SUCCESS_PREFIX",
+            "DisplayLimits",
+            "ToolStatus",
+            "count_lines",
+            "format_tool_compact",
+            "format_tree_output",
+            "get_status_symbol",
+            "has_args",
+            "is_success",
+            "truncate",
+            "truncate_with_line_hint",
+        ],
+    },
+)
diff --git a/EvoScientist/stream/console.py b/EvoScientist/stream/console.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/stream/console.py
@@ -0,0 +1,18 @@
+"""Shared Rich ``console`` singleton.
+
+Lives in its own lightweight module so that importing just the ``console``
+from ``EvoScientist.stream`` does not pull in the heavy rendering/event
+machinery (``stream.events`` → ``langchain_core.messages``).
+"""
+
+from __future__ import annotations
+
+import os
+import sys
+
+from rich.console import Console  # type: ignore[import-untyped]
+
+console = Console(
+    legacy_windows=(sys.platform == "win32"),
+    no_color=os.getenv("NO_COLOR") is not None,
+)
diff --git a/EvoScientist/stream/display.py b/EvoScientist/stream/display.py
--- a/EvoScientist/stream/display.py
+++ b/EvoScientist/stream/display.py
@@ -9,18 +9,18 @@
 import inspect
 import logging
 import os
-import sys
 from collections.abc import Callable
 from typing import Any
 
-from rich.console import Console, Group  # type: ignore[import-untyped]
+from rich.console import Group  # type: ignore[import-untyped]
 from rich.live import Live  # type: ignore[import-untyped]
 from rich.markdown import Markdown  # type: ignore[import-untyped]
 from rich.panel import Panel  # type: ignore[import-untyped]
 from rich.spinner import Spinner  # type: ignore[import-untyped]
 from rich.text import Text  # type: ignore[import-untyped]
 
 from ..paths import resolve_virtual_path
+from .console import console
 from .diff_format import build_edit_diff
 from .events import stream_agent_events
 from .formatter import ToolResultFormatter
@@ -46,11 +46,6 @@
 # Media file extensions that should trigger on_file_write callback
 _MEDIA_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".pdf"}
 
-console = Console(
-    legacy_windows=(sys.platform == "win32"),
-    no_color=os.getenv("NO_COLOR") is not None,
-)
-
 formatter = ToolResultFormatter()
 
 
diff --git a/pyproject.toml b/pyproject.toml
--- a/pyproject.toml
+++ b/pyproject.toml
@@ -34,6 +34,7 @@ dependencies = [
     "langgraph-cli[inmem]>=0.4",
     "langgraph-checkpoint-sqlite>=3.0.0",
     "httpx>=0.27",
+    "lazy-loader>=0.5",
     "markdownify>=0.14",
     "nest-asyncio>=1.6",
     "langchain-mcp-adapters>=0.1",
diff --git a/uv.lock b/uv.lock
--- a/uv.lock
+++ b/uv.lock

__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
