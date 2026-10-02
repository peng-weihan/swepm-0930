#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/EvoScientist/EvoScientist.py b/EvoScientist/EvoScientist.py
--- a/EvoScientist/EvoScientist.py
+++ b/EvoScientist/EvoScientist.py
@@ -42,6 +42,7 @@
     from langgraph.graph.state import CompiledStateGraph
 
     from .middleware.events import MiddlewareEventSink
+    from .runtime import AsyncRuntime
 
 # =============================================================================
 # Constants
@@ -246,7 +247,11 @@ def _load_mcp_config_once() -> tuple[str, dict]:
     return sig, cfg
 
 
-def _load_mcp_tools_cached(on_progress=None) -> dict[str, list]:
+def _load_mcp_tools_cached(
+    on_progress=None,
+    *,
+    runtime: "AsyncRuntime | None" = None,
+) -> dict[str, list]:
     """Load MCP tools with config-aware caching.
 
     Args:
@@ -267,7 +272,11 @@ def _load_mcp_tools_cached(on_progress=None) -> dict[str, list]:
     if _MCP_TOOLS_CACHE_KEY == cfg_key and _MCP_TOOLS_CACHE_VALUE is not None:
         return {k: list(v) for k, v in _MCP_TOOLS_CACHE_VALUE.items()}
 
-    loaded = load_mcp_tools(config=cfg, on_progress=on_progress)
+    loaded = load_mcp_tools(
+        config=cfg,
+        on_progress=on_progress,
+        runtime=runtime,
+    )
     _MCP_TOOLS_CACHE_KEY = cfg_key
     _MCP_TOOLS_CACHE_VALUE = {k: list(v) for k, v in loaded.items()}
     return {k: list(v) for k, v in loaded.items()}
@@ -533,6 +542,7 @@ def load_mcp_and_build_kwargs(
     cfg=None,
     chat_model=None,
     workspace_dir=None,
+    runtime: "AsyncRuntime | None" = None,
 ):
     """Load MCP tools (cached by config) and build agent kwargs.
 
@@ -551,7 +561,10 @@ def load_mcp_and_build_kwargs(
     from .utils import load_subagents
 
     cfg = cfg if cfg is not None else _ensure_config()
-    mcp_by_agent = _load_mcp_tools_cached(on_progress=on_mcp_progress)
+    mcp_by_agent = _load_mcp_tools_cached(
+        on_progress=on_mcp_progress,
+        runtime=runtime,
+    )
     if not mcp_by_agent:
         return _build_base_kwargs(
             base_backend,
@@ -915,6 +928,7 @@ def create_cli_agent(
     *,
     on_mcp_progress=None,
     events: "MiddlewareEventSink | None" = None,
+    runtime: "AsyncRuntime | None" = None,
 ) -> "CompiledStateGraph":
     """Create agent with checkpointer for CLI multi-turn support.
 
@@ -941,6 +955,8 @@ def create_cli_agent(
         chat_model: Optional pre-built chat model.  Only triggers the pure
             path when ``config`` is also explicit; otherwise it is ignored in
             favor of the ``_ensure_chat_model()`` fallback.
+        runtime: Optional application-scoped runtime for synchronous MCP tool
+            discovery. Direct callers get a scoped runtime when omitted.
     """
     import os as _os
 
@@ -1041,6 +1057,7 @@ def create_cli_agent(
         cfg=cfg,
         chat_model=chat_model,
         workspace_dir=workspace_dir,
+        runtime=runtime,
     )
 
     return create_deep_agent(
diff --git a/EvoScientist/backends.py b/EvoScientist/backends.py
--- a/EvoScientist/backends.py
+++ b/EvoScientist/backends.py
@@ -4,7 +4,11 @@
 import posixpath
 import re
 import shlex
+import signal
+import subprocess
 import sys
+import threading
+import time
 import uuid
 from pathlib import Path
 
@@ -22,6 +26,7 @@
 )
 
 from . import paths
+from .cancellation import current_cancel_event
 
 # Reproduced here to dodge a circular import from .EvoScientist (the canonical
 # SKILLS_DIR constant).
@@ -68,6 +73,87 @@
 ]
 
 
+_active_shell_processes_lock = threading.RLock()
+_active_shell_processes: dict[threading.Event, set[subprocess.Popen[str]]] = {}
+_PROCESS_DRAIN_GRACE_SECONDS = 1.0
+
+
+def _terminate_process_tree(process: subprocess.Popen[str]) -> None:
+    """Force-stop a shell and its descendants without waiting for reaping."""
+    # A completed Popen has already reaped its PID, which the OS may reuse.
+    # Inspect the recorded state rather than calling poll(): an exited but
+    # unreaped shell can still have live descendants in its process group.
+    if process.returncode is not None:
+        return
+
+    try:
+        if os.name == "nt":
+            # CREATE_NEW_PROCESS_GROUP alone does not make terminate() recursive.
+            # taskkill is the native way to stop the complete descendant tree.
+            subprocess.run(
+                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
+                check=False,
+                capture_output=True,
+                timeout=5,
+            )
+        else:
+            os.killpg(process.pid, signal.SIGKILL)
+    except (OSError, subprocess.SubprocessError):
+        try:
+            process.kill()
+        except OSError:
+            pass
+
+
+def _stop_collecting_process_output(process: subprocess.Popen[str]) -> None:
+    """Close inherited pipes and reap *process* without blocking the caller."""
+    for pipe in (process.stdout, process.stderr):
+        if pipe is not None:
+            try:
+                pipe.close()
+            except OSError:
+                pass
+
+    if process.poll() is None:
+        threading.Thread(target=process.wait, daemon=True).start()
+
+
+def cancel_active_shell_processes(event: threading.Event) -> None:
+    """Terminate every active shell command associated with *event*."""
+    with _active_shell_processes_lock:
+        processes = tuple(_active_shell_processes.get(event, ()))
+    for process in processes:
+        _terminate_process_tree(process)
+
+
+def _register_shell_process(
+    event: threading.Event | None,
+    process: subprocess.Popen[str],
+) -> None:
+    if event is None:
+        return
+    with _active_shell_processes_lock:
+        _active_shell_processes.setdefault(event, set()).add(process)
+        cancel_now = event.is_set()
+    if cancel_now:
+        _terminate_process_tree(process)
+
+
+def _unregister_shell_process(
+    event: threading.Event | None,
+    process: subprocess.Popen[str],
+) -> None:
+    if event is None:
+        return
+    with _active_shell_processes_lock:
+        processes = _active_shell_processes.get(event)
+        if processes is None:
+            return
+        processes.discard(process)
+        if not processes:
+            _active_shell_processes.pop(event, None)
+
+
 def _shell_token_spans(command: str) -> list[dict[str, object]]:
     """Tokenize enough shell syntax to find quoted SSH remote commands.
 
@@ -1237,16 +1323,168 @@ def execute(self, command: str, *, timeout: int | None = None) -> ExecuteRespons
         - Access to paths outside workspace
         - Dangerous system commands
 
-        Then delegates to LocalShellBackend.execute() for actual execution.
+        The validated command is handed to the owned process runner so
+        cancelling an agent turn can terminate the complete process tree.
         """
+        # Preserve LocalShellBackend's public validation contract.  This
+        # override cannot delegate execution to the base implementation because
+        # it must retain the Popen handle for cancellation, so validate before
+        # command preparation and process launch instead.
+        if not command or not isinstance(command, str):
+            return ExecuteResponse(
+                output="Error: Command must be a non-empty string.",
+                exit_code=1,
+                truncated=False,
+            )
+
         command, error = prepare_sandbox_command(
             command, self.cwd, virtual_mode=self.virtual_mode, dangerous=self._dangerous
         )
         if error:
             return ExecuteResponse(output=error, exit_code=1, truncated=False)
 
-        # Delegate to parent for subprocess execution
-        response = super().execute(command, timeout=timeout)
+        return self._execute_prepared_command(command, timeout=timeout)
+
+    def _execute_prepared_command(
+        self,
+        command: str,
+        *,
+        timeout: int | None = None,
+    ) -> ExecuteResponse:
+        """Execute an already validated command in an owned process group."""
+
+        effective_timeout = timeout if timeout is not None else self._default_timeout
+        if effective_timeout <= 0:
+            msg = f"timeout must be positive, got {effective_timeout}"
+            raise ValueError(msg)
+
+        cancel_event = current_cancel_event()
+        if cancel_event is not None and cancel_event.is_set():
+            return ExecuteResponse(
+                output="Command cancelled before execution.",
+                exit_code=130,
+                truncated=False,
+            )
+
+        process: subprocess.Popen[str] | None = None
+        termination_reason: str | None = None
+        output_abandoned = False
+        try:
+            process_options: dict[str, object] = {}
+            if os.name == "nt":
+                process_options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
+            else:
+                process_options["start_new_session"] = True
+
+            process = subprocess.Popen(
+                command,
+                shell=True,
+                stdout=subprocess.PIPE,
+                stderr=subprocess.PIPE,
+                stdin=subprocess.DEVNULL,
+                text=True,
+                env=self._env,
+                cwd=str(self.cwd),
+                **process_options,
+            )
+            _register_shell_process(cancel_event, process)
+            deadline = time.monotonic() + effective_timeout
+            drain_deadline: float | None = None
+
+            while True:
+                now = time.monotonic()
+                if (
+                    termination_reason is None
+                    and cancel_event is not None
+                    and cancel_event.is_set()
+                ):
+                    termination_reason = "cancelled"
+                    _terminate_process_tree(process)
+                    drain_deadline = now + _PROCESS_DRAIN_GRACE_SECONDS
+                elif termination_reason is None and now >= deadline:
+                    termination_reason = "timed_out"
+                    _terminate_process_tree(process)
+                    drain_deadline = now + _PROCESS_DRAIN_GRACE_SECONDS
+
+                if drain_deadline is not None and now >= drain_deadline:
+                    _stop_collecting_process_output(process)
+                    stdout = stderr = ""
+                    output_abandoned = True
+                    break
+
+                communicate_deadline = (
+                    drain_deadline if drain_deadline is not None else deadline
+                )
+                try:
+                    stdout, stderr = process.communicate(
+                        timeout=max(
+                            0.01,
+                            min(0.1, communicate_deadline - time.monotonic()),
+                        )
+                    )
+                    break
+                except subprocess.TimeoutExpired:
+                    continue
+
+            if termination_reason == "timed_out":
+                if timeout is not None:
+                    timeout_output = (
+                        "Error: Command timed out after "
+                        f"{effective_timeout} seconds (custom timeout). The command "
+                        "may be stuck or require more time."
+                    )
+                else:
+                    timeout_output = (
+                        f"Error: Command timed out after {effective_timeout} seconds. "
+                        "For long-running commands, re-run using the timeout parameter."
+                    )
+                response = ExecuteResponse(
+                    output=timeout_output,
+                    exit_code=124,
+                    truncated=output_abandoned,
+                )
+            elif termination_reason == "cancelled" or (
+                cancel_event is not None and cancel_event.is_set()
+            ):
+                response = ExecuteResponse(
+                    output="Command cancelled.",
+                    exit_code=130,
+                    truncated=output_abandoned,
+                )
+            else:
+                output_parts = []
+                if stdout:
+                    output_parts.append(stdout)
+                if stderr:
+                    stderr_lines = stderr.strip().split("\n")
+                    output_parts.extend(f"[stderr] {line}" for line in stderr_lines)
+                output = "\n".join(output_parts) if output_parts else "<no output>"
+
+                truncated = False
+                if len(output) > self._max_output_bytes:
+                    output = output[: self._max_output_bytes]
+                    output += (
+                        f"\n\n... Output truncated at {self._max_output_bytes} bytes."
+                    )
+                    truncated = True
+                if process.returncode != 0:
+                    output = f"{output.rstrip()}\n\nExit code: {process.returncode}"
+                response = ExecuteResponse(
+                    output=output,
+                    exit_code=process.returncode,
+                    truncated=truncated,
+                )
+        except Exception as exc:
+            if process is not None:
+                _terminate_process_tree(process)
+            response = ExecuteResponse(
+                output=f"Error executing command ({type(exc).__name__}): {exc}",
+                exit_code=1,
+                truncated=False,
+            )
+        finally:
+            if process is not None:
+                _unregister_shell_process(cancel_event, process)
 
         # Enhance timeout errors with actionable recovery guidance
         if response.exit_code == 124:
diff --git a/EvoScientist/cancellation.py b/EvoScientist/cancellation.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/cancellation.py
@@ -0,0 +1,27 @@
+"""Cancellation context shared by streaming frontends and blocking tools."""
+
+from __future__ import annotations
+
+import contextvars
+import threading
+from collections.abc import Iterator
+from contextlib import contextmanager
+
+_current_cancel_event: contextvars.ContextVar[threading.Event | None] = (
+    contextvars.ContextVar("evoscientist_cancel_event", default=None)
+)
+
+
+@contextmanager
+def bind_cancel_event(event: threading.Event) -> Iterator[None]:
+    """Make a stream's cancellation event visible to nested sync tool calls."""
+    token = _current_cancel_event.set(event)
+    try:
+        yield
+    finally:
+        _current_cancel_event.reset(token)
+
+
+def current_cancel_event() -> threading.Event | None:
+    """Return the cancellation event bound to the current agent run, if any."""
+    return _current_cancel_event.get()
diff --git a/EvoScientist/channels/base.py b/EvoScientist/channels/base.py
--- a/EvoScientist/channels/base.py
+++ b/EvoScientist/channels/base.py
@@ -18,6 +18,7 @@
 from typing import Any
 
 from ..paths import MEDIA_DIR
+from ..runtime import AsyncRuntime
 from .bus.events import InboundMessage, OutboundMessage
 from .capabilities import ChannelCapabilities
 from .debug import TraceMixin, debug_trace_enabled
@@ -927,34 +928,27 @@ async def _build_inbound_async(self, raw: RawIncoming) -> InboundMessage | None:
             return None
         return self._raw_to_inbound(current)
 
-    def _build_inbound(self, raw: RawIncoming) -> InboundMessage | None:
+    def _build_inbound(
+        self,
+        raw: RawIncoming,
+        *,
+        runtime: AsyncRuntime | None = None,
+    ) -> InboundMessage | None:
         """Run *raw* through inbound middlewares and convert to InboundMessage.
 
-        Synchronous wrapper around :meth:`_build_inbound_async`.  When an
-        event loop is already running, the coroutine is scheduled on that
-        loop via :func:`asyncio.run_coroutine_threadsafe` to avoid
-        thread-safety issues with middleware state (DedupCache,
-        GroupHistoryBuffer, etc.).
-        """
-        import asyncio
+        Compatibility wrapper for synchronous integrations. Internal channel
+        implementations should await :meth:`_build_inbound_async` on their
+        transport loop. A caller may provide its application runtime to reuse
+        that owner; otherwise a runtime is scoped to this call.
 
-        try:
-            loop = asyncio.get_running_loop()
-        except RuntimeError:
-            loop = None
-
-        if loop is not None and loop.is_running():
-            future = asyncio.run_coroutine_threadsafe(
-                self._build_inbound_async(raw),
-                loop,
-            )
-            return future.result()
-        else:
-            new_loop = asyncio.new_event_loop()
-            try:
-                return new_loop.run_until_complete(self._build_inbound_async(raw))
-            finally:
-                new_loop.close()
+        This method deliberately rejects callers already running an event
+        loop. Blocking such a loop while scheduling the coroutine back onto it
+        deadlocks; async callers must await :meth:`_build_inbound_async`.
+        """
+        if runtime is None:
+            with AsyncRuntime(thread_name="evosci-channel-adapter-runtime") as owned:
+                return self._build_inbound(raw, runtime=owned)
+        return runtime.run_sync(lambda: self._build_inbound_async(raw))
 
     def _raw_to_inbound(self, raw: RawIncoming) -> InboundMessage | None:
         """Convert a RawIncoming to InboundMessage (pure transformation, no filtering).
diff --git a/EvoScientist/channels/email/probe.py b/EvoScientist/channels/email/probe.py
--- a/EvoScientist/channels/email/probe.py
+++ b/EvoScientist/channels/email/probe.py
@@ -25,7 +25,7 @@ async def validate_email_imap(
 
     import asyncio
 
-    loop = asyncio.get_event_loop()
+    loop = asyncio.get_running_loop()
 
     def _check():
         try:
@@ -62,7 +62,7 @@ async def validate_email_smtp(
 
     import asyncio
 
-    loop = asyncio.get_event_loop()
+    loop = asyncio.get_running_loop()
 
     def _check():
         server = None
diff --git a/EvoScientist/channels/imessage/rpc_client.py b/EvoScientist/channels/imessage/rpc_client.py
--- a/EvoScientist/channels/imessage/rpc_client.py
+++ b/EvoScientist/channels/imessage/rpc_client.py
@@ -150,7 +150,7 @@ async def request(
             "params": params or {},
         }
 
-        future: asyncio.Future = asyncio.get_event_loop().create_future()
+        future: asyncio.Future = asyncio.get_running_loop().create_future()
         self._pending[request_id] = future
 
         line = json.dumps(payload) + "\n"
diff --git a/EvoScientist/channels/signal/probe.py b/EvoScientist/channels/signal/probe.py
--- a/EvoScientist/channels/signal/probe.py
+++ b/EvoScientist/channels/signal/probe.py
@@ -22,7 +22,7 @@ async def validate_signal(
         return False, "phone_number is required"
 
     # Check signal-cli binary
-    loop = asyncio.get_event_loop()
+    loop = asyncio.get_running_loop()
 
     def _check():
         try:
diff --git a/EvoScientist/channels/standalone.py b/EvoScientist/channels/standalone.py
--- a/EvoScientist/channels/standalone.py
+++ b/EvoScientist/channels/standalone.py
@@ -26,6 +26,13 @@
 logger = logging.getLogger(__name__)
 
 
+async def _create_standalone_agent():
+    """Construct the synchronous agent without blocking the channel loop."""
+    from ..EvoScientist import create_cli_agent
+
+    return await asyncio.to_thread(create_cli_agent)
+
+
 def _channel_trace_enabled(channel: Channel) -> bool:
     """Check if debug tracing is enabled on the channel."""
     try:
@@ -107,10 +114,12 @@ async def _async_main(
     consumer: InboundConsumer | None = None
     if use_agent:
         logger.info("Loading EvoScientist agent...")
-        from ..EvoScientist import create_cli_agent
         from ..gateway import create_runtime_gateways
 
-        agent = create_cli_agent()
+        # Agent construction performs synchronous MCP discovery through the
+        # owned-runtime bridge.  Keep it off this already-running channel loop
+        # (and avoid blocking channel health/startup work while it loads).
+        agent = await _create_standalone_agent()
         runtime_gateways = create_runtime_gateways()
         logger.info("Agent loaded")
 
@@ -151,7 +160,7 @@ async def _graceful_shutdown() -> None:
         await channel.stop()
         await manager.stop_health()
 
-    loop = asyncio.get_event_loop()
+    loop = asyncio.get_running_loop()
     for sig in (signal.SIGINT, signal.SIGTERM):
         loop.add_signal_handler(
             sig,
diff --git a/EvoScientist/cli/agent.py b/EvoScientist/cli/agent.py
--- a/EvoScientist/cli/agent.py
+++ b/EvoScientist/cli/agent.py
@@ -10,6 +10,8 @@
 if TYPE_CHECKING:
     from langgraph.graph.state import CompiledStateGraph
 
+    from ..runtime import AsyncRuntime
+
 
 def _shorten_path(path: str) -> str:
     """Shorten absolute path to relative path from current directory."""
@@ -70,6 +72,7 @@ def _load_agent(
     *,
     on_mcp_progress=None,
     events=None,
+    runtime: "AsyncRuntime | None" = None,
 ) -> "CompiledStateGraph":
     """Load the CLI agent with optional persistent checkpointer.
 
@@ -84,6 +87,7 @@ def _load_agent(
             selects the pure (no module-global write) build path.
         on_mcp_progress: Optional per-server MCP progress callback.
             Signature ``(event, server_name, detail) -> None``.
+        runtime: Optional application-scoped runtime used for MCP discovery.
     """
     from ..EvoScientist import create_cli_agent
 
@@ -94,4 +98,5 @@ def _load_agent(
         chat_model=chat_model,
         on_mcp_progress=on_mcp_progress,
         events=events,
+        runtime=runtime,
     )
diff --git a/EvoScientist/cli/channel.py b/EvoScientist/cli/channel.py
--- a/EvoScientist/cli/channel.py
+++ b/EvoScientist/cli/channel.py
@@ -43,6 +43,7 @@
 
 if TYPE_CHECKING:
     from ..gateway import GraphGateway
+    from ..runtime import AsyncRuntime
 
 _channel_logger = logging.getLogger(__name__)
 
@@ -281,6 +282,7 @@ async def dispatch_channel_slash_command(
     await_agent_ready: Callable[[], Awaitable[Any]] | None = None,
     on_cmd_completed: Callable[..., Awaitable[None]] | None = None,
     channel_runtime: ChannelRuntime | None = None,
+    async_runtime: AsyncRuntime | None = None,
 ) -> bool:
     """Dispatch a slash command from a channel message.
 
@@ -347,6 +349,7 @@ async def dispatch_channel_slash_command(
             on_cmd_completed=on_cmd_completed,
             channel_runtime=channel_runtime,
             graph_gateway=graph_gateway,
+            async_runtime=async_runtime,
         )
     except Exception as exc:
         # Last-ditch safety: any uncaught exception from inside the
@@ -383,6 +386,7 @@ async def _dispatch_channel_slash_impl(
     await_agent_ready: Callable[[], Awaitable[Any]] | None,
     on_cmd_completed: Callable[..., Awaitable[None]] | None,
     channel_runtime: ChannelRuntime | None,
+    async_runtime: AsyncRuntime | None,
 ) -> bool:
     """Inner body of ``dispatch_channel_slash_command``.
 
@@ -431,6 +435,7 @@ async def _dispatch_channel_slash_impl(
         checkpointer=checkpointer,
         channel_runtime=channel_runtime,
         graph_gateway=graph_gateway,
+        async_runtime=async_runtime,
     )
 
     try:
diff --git a/EvoScientist/cli/channel_sends.py b/EvoScientist/cli/channel_sends.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/cli/channel_sends.py
@@ -0,0 +1,112 @@
+"""Non-blocking bridge for streaming callbacks sent through a channel loop."""
+
+from __future__ import annotations
+
+import asyncio
+import concurrent.futures
+import logging
+import threading
+from collections.abc import Coroutine
+from typing import Any
+
+
+class PendingChannelSends:
+    """Schedule channel I/O without blocking the caller's event loop.
+
+    Streaming callbacks run on the owned async runtime, while channel clients
+    belong to the channel bus loop.  Submissions therefore only enqueue work;
+    the frontend settles the returned futures after streaming has unwound.
+    """
+
+    def __init__(
+        self,
+        loop: asyncio.AbstractEventLoop | None,
+        logger: logging.Logger,
+    ) -> None:
+        self._loop = loop
+        self._logger = logger
+        self._lock = threading.Lock()
+        self._pending: list[tuple[concurrent.futures.Future[Any], str, int]] = []
+        self._tail: concurrent.futures.Future[Any] | None = None
+
+    @staticmethod
+    def _close(coro: Coroutine[Any, Any, Any]) -> None:
+        coro.close()
+
+    async def _run_after(
+        self,
+        predecessor: concurrent.futures.Future[Any] | None,
+        coro: Coroutine[Any, Any, Any],
+    ) -> Any:
+        if predecessor is not None:
+            try:
+                await asyncio.shield(asyncio.wrap_future(predecessor))
+            except asyncio.CancelledError:
+                task = asyncio.current_task()
+                if task is not None and task.cancelling():
+                    self._close(coro)
+                    raise
+            except Exception:
+                pass
+        return await coro
+
+    def submit(
+        self,
+        coro: Coroutine[Any, Any, Any],
+        label: str,
+        timeout: int = 15,
+    ) -> None:
+        """Schedule one send and return immediately."""
+        if self._loop is None:
+            self._close(coro)
+            return
+        with self._lock:
+            ordered_coro = self._run_after(self._tail, coro)
+            try:
+                future = asyncio.run_coroutine_threadsafe(ordered_coro, self._loop)
+            except Exception as exc:
+                self._close(ordered_coro)
+                self._close(coro)
+                self._logger.debug("%s send failed: %s", label, exc)
+                return
+            self._tail = future
+            self._pending.append((future, label, timeout))
+
+    def _take_pending(
+        self,
+    ) -> list[tuple[concurrent.futures.Future[Any], str, int]]:
+        with self._lock:
+            pending = self._pending
+            self._pending = []
+        return pending
+
+    def settle(self) -> None:
+        """Wait for scheduled sends from a synchronous frontend thread."""
+        for future, label, timeout in self._take_pending():
+            try:
+                future.result(timeout=timeout)
+            except Exception as exc:
+                future.cancel()
+                self._logger.debug("%s send failed: %s", label, exc)
+
+    async def settle_async(self) -> None:
+        """Wait for scheduled sends without blocking the frontend loop."""
+        pending = self._take_pending()
+        try:
+            for future, label, timeout in pending:
+                try:
+                    await asyncio.wait_for(asyncio.wrap_future(future), timeout=timeout)
+                except TimeoutError as exc:
+                    future.cancel()
+                    self._logger.debug("%s send failed: %s", label, exc)
+                except asyncio.CancelledError as exc:
+                    task = asyncio.current_task()
+                    if task is not None and task.cancelling():
+                        raise
+                    self._logger.debug("%s send failed: %s", label, exc)
+                except Exception as exc:
+                    self._logger.debug("%s send failed: %s", label, exc)
+        except asyncio.CancelledError:
+            for future, _label, _timeout in pending:
+                future.cancel()
+            raise
diff --git a/EvoScientist/cli/commands.py b/EvoScientist/cli/commands.py
--- a/EvoScientist/cli/commands.py
+++ b/EvoScientist/cli/commands.py
@@ -1,6 +1,5 @@
 """Typer command registrations — onboard, config, mcp, main callback."""
 
-import asyncio
 import logging
 import os
 import queue
@@ -12,6 +11,7 @@
 from pathlib import Path
 from typing import TYPE_CHECKING, Annotated, Any, cast
 
+import click
 import typer
 from rich.markup import escape
 from rich.table import Table
@@ -26,6 +26,7 @@
 )
 from ..llm.context_window import DEFAULT_CONTEXT_WINDOW_FALLBACK, resolve_context_window
 from ..paths import ensure_dirs, set_active_workspace, set_workspace_root
+from ..runtime import AsyncRuntime
 from ..stream.console import console
 from . import async_notifier
 from ._app import app, channel_app, config_app, configure_app, mcp_app, sessions_app
@@ -53,6 +54,7 @@
     publish_to_channel_origin,
     remember_channel_origin,
 )
+from .channel_sends import PendingChannelSends
 from .mcp_ui import (
     _mcp_add_server_from_kwargs,
     _mcp_edit_server_fields,
@@ -66,13 +68,43 @@
 
     from ..config import EvoScientistConfig
 
+
+_ASYNC_RUNTIME_META_KEY = "evoscientist.async_runtime"
+
+
+def _close_cli_async_runtime(runtime: AsyncRuntime) -> None:
+    """Close the owned runtime or surface a controlled CLI shutdown failure."""
+    try:
+        runtime.close()
+    except TimeoutError as exc:
+        click.echo(
+            f"Error: Async runtime shutdown did not complete: {exc}",
+            err=True,
+        )
+        raise click.exceptions.Exit(1) from None
+
+
+def _get_cli_async_runtime(ctx: typer.Context) -> AsyncRuntime:
+    """Return the application-scoped runtime owned by this CLI invocation."""
+    root = ctx.find_root()
+    runtime = root.meta.get(_ASYNC_RUNTIME_META_KEY)
+    if runtime is None:
+        runtime = AsyncRuntime()
+        root.meta[_ASYNC_RUNTIME_META_KEY] = runtime
+        root.call_on_close(lambda: _close_cli_async_runtime(runtime))
+    if not isinstance(runtime, AsyncRuntime):  # pragma: no cover - defensive
+        raise RuntimeError("CLI async runtime context is invalid")
+    return runtime
+
+
 # =============================================================================
 # Onboard command
 # =============================================================================
 
 
 @app.command()
 def onboard(
+    ctx: typer.Context,
     skip_validation: bool = typer.Option(
         False, "--skip-validation", help="Skip API key validation during setup"
     ),
@@ -201,7 +233,11 @@ def onboard(
             strict=non_interactive,
         )
 
-    _run_onboard_cli(skip_validation=skip_validation, prompter=prompter)
+    _run_onboard_cli(
+        skip_validation=skip_validation,
+        prompter=prompter,
+        runtime=_get_cli_async_runtime(ctx),
+    )
 
 
 # =============================================================================
@@ -243,11 +279,21 @@ def _run_onboard_cli(**kwargs: Any) -> None:
         raise typer.Exit(code=1) from exc
 
 
-def _configure_section(section: str, skip_validation: bool = False) -> None:
+def _configure_section(
+    section: str,
+    skip_validation: bool = False,
+    *,
+    runtime: AsyncRuntime | None = None,
+) -> None:
     """Run a single onboarding section, reusing the wizard's step logic."""
+    kwargs: dict[str, Any] = {
+        "skip_validation": skip_validation,
+        "only_sections": {section},
+    }
+    if runtime is not None:
+        kwargs["runtime"] = runtime
     _run_onboard_cli(
-        skip_validation=skip_validation,
-        only_sections={section},
+        **kwargs,
     )
 
 
@@ -325,9 +371,9 @@ def configure_latex():
 
 
 @configure_app.command("channels")
-def configure_channels():
+def configure_channels(ctx: typer.Context):
     """Re-run channels selection and per-channel configuration."""
-    _configure_section("channels")
+    _configure_section("channels", runtime=_get_cli_async_runtime(ctx))
 
 
 # =============================================================================
@@ -336,24 +382,17 @@ def configure_channels():
 
 
 @channel_app.command("setup")
-def channel_setup():
+def channel_setup(ctx: typer.Context):
     """Interactive channel configuration wizard.
 
     Guides you through selecting and configuring messaging channels
     (Telegram, Discord, or iMessage).
     """
-    import asyncio
-
-    try:
-        asyncio.get_event_loop()
-    except RuntimeError:
-        asyncio.set_event_loop(asyncio.new_event_loop())
-
     from ..config import load_config, save_config
     from ..config.onboard.channels import _step_channels
 
     config = load_config()
-    updates = _step_channels(config)
+    updates = _step_channels(config, runtime=_get_cli_async_runtime(ctx))
     if updates:
         for key, value in updates.items():
             setattr(config, key, value)
@@ -875,6 +914,7 @@ class ServeRuntimeState:
     workspace_dir: str | None
     config: "EvoScientistConfig | None"
     runtime_gateways: RuntimeGateways
+    async_runtime: AsyncRuntime
     resume_warning_thread_id: str | None = None
 
     def set_agent(
@@ -969,6 +1009,7 @@ async def _apply_serve_resume_state(
                 _load_agent,
                 workspace_dir=new_workspace,
                 config=effective_config,
+                runtime=runtime_state.async_runtime,
             )
             await _sync_background_agent_server_workspace(
                 effective_config,
@@ -1119,8 +1160,6 @@ def _serve_process_message(
     via the ``on_cmd_completed`` hook because the command mutates
     ``ctx.thread_id`` / ``ctx.workspace_dir`` directly.
     """
-    import asyncio
-
     from .channel import _bus_loop
     from .tui_runtime import run_streaming
 
@@ -1139,14 +1178,10 @@ def _serve_process_message(
 
     # -- channel callback helpers (same pattern as interactive.py) --
 
+    pending_channel_sends = PendingChannelSends(_bus_loop, _serve_logger)
+
     def _send_to_channel(coro, label: str, timeout: int = 15) -> None:
-        loop = _bus_loop
-        if not loop:
-            return
-        try:
-            asyncio.run_coroutine_threadsafe(coro, loop).result(timeout=timeout)
-        except Exception as e:
-            _serve_logger.debug(f"{label} send failed: {e}")
+        pending_channel_sends.submit(coro, label, timeout)
 
     def _send_thinking(thinking: str) -> None:
         ch = msg.channel_ref
@@ -1196,31 +1231,15 @@ def _ask_user_prompt(ask_user_data: dict) -> dict:
     # commands like ``/evoskills`` actually execute in serve mode instead
     # of being fed to the LLM as a plain prompt.  ``await_agent_ready`` is
     # None because the agent is always loaded before the serve loop polls.
-    # Uses a dedicated event loop (not ``asyncio.run``) so SIGINT handling
-    # installed by ``serve()`` remains authoritative — ``asyncio.run``
-    # swaps ``signal.set_wakeup_fd`` and can leave it dangling on edge
-    # cases, which breaks Ctrl+C between messages.
-    # ``set_event_loop`` is needed because some downstream commands
-    # (e.g. ``/install-mcp``) call ``asyncio.get_event_loop()``, which
-    # raises ``RuntimeError`` on Python 3.12+ when the thread has no
-    # current loop set.  The prior loop (often ``None``) is restored in
-    # the ``finally`` below so subsequent messages start from a clean
-    # slate.  Loop creation lives inside the try so an exception between
-    # creation and ``set_event_loop`` still closes the loop.
+    # Slash commands run on the application-owned runtime. The main thread
+    # remains the signal owner while command coroutines share one stable loop.
     try:
-        _prev_loop: asyncio.AbstractEventLoop | None
-        try:
-            _prev_loop = asyncio.get_event_loop_policy().get_event_loop()
-        except RuntimeError:
-            _prev_loop = None
-        _slash_loop: asyncio.AbstractEventLoop | None = None
         _slash_handled = False
         _slash_error: Exception | None = None
         try:
-            _slash_loop = asyncio.new_event_loop()
-            asyncio.set_event_loop(_slash_loop)
-            _slash_handled = _slash_loop.run_until_complete(
-                dispatch_channel_slash_command(
+            async_runtime = runtime_state.async_runtime
+            _slash_handled = async_runtime.run_sync(
+                lambda: dispatch_channel_slash_command(
                     msg,
                     agent=runtime_state.agent,
                     thread_id=runtime_state.thread_id,
@@ -1245,15 +1264,12 @@ def _ask_user_prompt(ask_user_data: dict) -> dict:
                     ),
                     channel_runtime=channel_runtime,
                     graph_gateway=runtime_gateways.graph_gateway,
+                    async_runtime=async_runtime,
                 )
             )
         except Exception as exc:
             _slash_error = exc
             _serve_logger.exception("Slash dispatch failed for %s", msg.channel_type)
-        finally:
-            if _slash_loop is not None:
-                _slash_loop.close()
-            asyncio.set_event_loop(_prev_loop)
 
         if _slash_error is not None:
             _set_channel_response(msg.msg_id, f"Command error: {_slash_error}")
@@ -1287,11 +1303,13 @@ def _ask_user_prompt(ask_user_data: dict) -> dict:
                 ask_user_prompt_fn=_ask_user_prompt,
                 cancel_scope=_channel_message_cancel_scope(msg),
                 gateway=runtime_gateways.graph_gateway,
+                runtime=runtime_state.async_runtime,
             )
         except Exception as e:
             response = f"Error: {e}"
             console.print(f"[red]Serve error: {e}[/red]")
 
+        pending_channel_sends.settle()
         _set_channel_response(msg.msg_id, response)
         console.print(f"[dim][{msg.channel_type}] Replied to {msg.sender}[/dim]")
     finally:
@@ -1341,6 +1359,7 @@ def _run_notification_message(text: str, notifs: list) -> None:
                 interactive=True,
                 metadata=meta,
                 gateway=runtime_state.runtime_gateways.graph_gateway,
+                runtime=runtime_state.async_runtime,
             )
         except Exception as exc:
             _serve_logger.warning("Notification agent turn failed: %s", exc)
@@ -1378,19 +1397,15 @@ async def _consume() -> None:
             current_thread_id=runtime_state.thread_id,
         )
 
-    _notif_loop: _aio.AbstractEventLoop | None = None
     try:
-        _notif_loop = _aio.new_event_loop()
-        _notif_loop.run_until_complete(_consume())
+        runtime_state.async_runtime.run_sync(_consume)
     except Exception as exc:
         _serve_logger.warning("Notification drain failed: %s", exc)
-    finally:
-        if _notif_loop is not None:
-            _notif_loop.close()
 
 
 @app.command()
 def serve(
+    ctx: typer.Context,
     no_thinking: bool = typer.Option(
         False, "--no-thinking", help="Disable thinking relay to channels"
     ),
@@ -1445,6 +1460,7 @@ def serve(
         cli_overrides["log_level"] = "DEBUG"
         cli_overrides["channel_debug_tracing"] = True
     config = get_effective_config(cli_overrides)
+    async_runtime = _get_cli_async_runtime(ctx)
     if debug:
         os.environ["EVOSCIENTIST_LOG_LEVEL"] = "DEBUG"
         os.environ["EVOSCIENTIST_CHANNEL_DEBUG_TRACING"] = "true"
@@ -1495,11 +1511,13 @@ def serve(
             f"[bold red]{DANGEROUS_BANNER_MESSAGE}[/bold red]"
         )
     console.print("[dim]Loading agent...[/dim]")
-    agent = _load_agent(workspace_dir=ws, config=config)
+    agent = _load_agent(workspace_dir=ws, config=config, runtime=async_runtime)
 
     runtime_gateways = create_runtime_gateways()
-    tid = asyncio.run(
-        runtime_gateways.graph_gateway.create_thread(GraphTarget(workspace_dir=ws))
+    tid = async_runtime.run_sync(
+        lambda: runtime_gateways.graph_gateway.create_thread(
+            GraphTarget(workspace_dir=ws)
+        )
     )
 
     # Mutable runtime shared with _serve_process_message so channel slash
@@ -1511,6 +1529,7 @@ def serve(
         workspace_dir=ws,
         config=config,
         runtime_gateways=runtime_gateways,
+        async_runtime=async_runtime,
     )
 
     channel_runtime = ChannelRuntime(agent=agent, thread_id=tid)
@@ -1551,9 +1570,22 @@ def serve(
     import threading
 
     shutdown_event = threading.Event()
+    no_active_cancel_scope = object()
+    active_cancel_scope: str | object | None = no_active_cancel_scope
 
     def _handle_shutdown(signum: int, _frame: Any) -> None:
         shutdown_event.set()
+        # Cancelling the owned asyncio task is not enough when it is awaiting a
+        # blocking execute call: the executor thread and its isolated process
+        # group keep running until the matching stream event is set.  Request
+        # scope cancellation before KeyboardInterrupt unwinds message cleanup
+        # (which discards that scope).  SIGTERM also needs this to unblock the
+        # synchronous serve call so the poll loop can observe shutdown_event.
+        scope = active_cancel_scope
+        if scope is not no_active_cancel_scope:
+            from ..stream.display import request_stream_cancel
+
+            request_stream_cancel(cast(str | None, scope))
         # Fall back to Python's default SIGINT behavior (raises
         # KeyboardInterrupt) so blocking I/O inside ``run_streaming``
         # is still interrupted.  For SIGTERM there's no default that
@@ -1573,6 +1605,7 @@ def _handle_shutdown(signum: int, _frame: Any) -> None:
             if shutdown_event.is_set():
                 break
             if msg is not None:
+                active_cancel_scope = _channel_message_cancel_scope(msg)
                 try:
                     _serve_process_message(
                         msg,
@@ -1588,15 +1621,22 @@ def _handle_shutdown(signum: int, _frame: Any) -> None:
                 except KeyboardInterrupt:
                     shutdown_event.set()
                     break
+                finally:
+                    active_cancel_scope = no_active_cancel_scope
 
             # Poll notification queue when idle (no channel message was pending).
             if async_notifier.has_pending_notifications(runtime_state.thread_id):
-                _serve_drain_notifications(
-                    runtime_state=runtime_state,
-                    model=config.model,
-                    workspace_dir=ws,
-                    show_thinking=effective_channel_thinking,
-                )
+                # Notification turns use the default stream cancellation scope.
+                active_cancel_scope = None
+                try:
+                    _serve_drain_notifications(
+                        runtime_state=runtime_state,
+                        model=config.model,
+                        workspace_dir=ws,
+                        show_thinking=effective_channel_thinking,
+                    )
+                finally:
+                    active_cancel_scope = no_active_cancel_scope
     except KeyboardInterrupt:
         shutdown_event.set()
     finally:
@@ -1954,20 +1994,16 @@ def sessions_callback(ctx: typer.Context):
     so the bare command is informative rather than silent.
     """
     if ctx.invoked_subcommand is None:
-        sessions_stats()
+        sessions_stats(ctx)
 
 
 @sessions_app.command("stats")
-def sessions_stats():
+def sessions_stats(ctx: typer.Context):
     """Show DB size, thread count, total checkpoints, top heaviest threads."""
-    import asyncio
-
     from ..sessions import db_stats
 
-    try:
-        stats = asyncio.get_event_loop().run_until_complete(db_stats())
-    except RuntimeError:
-        stats = asyncio.new_event_loop().run_until_complete(db_stats())
+    runtime = _get_cli_async_runtime(ctx)
+    stats = runtime.run_sync(db_stats)
 
     table = Table(title="EvoScientist sessions DB", show_header=True)
     table.add_column("Metric", style="cyan")
@@ -2108,6 +2144,8 @@ def _main_callback(
     if ctx.invoked_subcommand is not None:
         return
 
+    async_runtime = _get_cli_async_runtime(ctx)
+
     # Load and apply configuration
     from ..config import apply_config_to_env, get_effective_config
 
@@ -2350,10 +2388,12 @@ async def _single_shot():
                 else:
                     tid = await graph_gateway.create_thread()
                 console.print("[dim]Loading agent...[/dim]")
-                agent = _load_agent(
+                agent = await asyncio.to_thread(
+                    _load_agent,
                     workspace_dir=workspace_dir,
                     checkpointer=checkpointer,
                     config=config,
+                    runtime=async_runtime,
                 )
                 try:
                     if effective_output_format == "stream-json":
@@ -2382,16 +2422,31 @@ async def _single_shot():
                             # matching the text path (cmd_run does this itself).
                             _wait_for_memory_workers_before_exit()
                     else:
-                        cmd_run(
-                            agent,
-                            prompt,
-                            thread_id=tid,
-                            show_thinking=show_thinking,
-                            workspace_dir=workspace_dir,
-                            model=config.model,
-                            ui_backend=config.ui_backend,
-                            runtime_gateways=runtime_gateways,
+                        stream_worker = asyncio.create_task(
+                            asyncio.to_thread(
+                                cmd_run,
+                                agent,
+                                prompt,
+                                thread_id=tid,
+                                show_thinking=show_thinking,
+                                workspace_dir=workspace_dir,
+                                model=config.model,
+                                ui_backend=config.ui_backend,
+                                runtime_gateways=runtime_gateways,
+                                async_runtime=async_runtime,
+                            )
                         )
+                        try:
+                            await asyncio.shield(stream_worker)
+                        except asyncio.CancelledError:
+                            from ..stream.display import request_stream_cancel
+                            from .tui_runtime import settle_cancelled_worker
+
+                            await settle_cancelled_worker(
+                                stream_worker,
+                                on_cancel=request_stream_cancel,
+                            )
+                            raise
                 finally:
                     # Model failures can bypass middleware ``after_agent``
                     # hooks. Close any remaining QuickJS workers while this
@@ -2407,10 +2462,7 @@ async def _single_shot():
                     except Exception:
                         pass
 
-        import nest_asyncio
-
-        nest_asyncio.apply()
-        asyncio.get_event_loop().run_until_complete(_single_shot())
+        async_runtime.run_sync(_single_shot)
     else:
         from .interactive import cmd_interactive
 
@@ -2427,6 +2479,7 @@ async def _single_shot():
             thread_id=thread_id,
             ui_backend=config.ui_backend,
             config=config,
+            async_runtime=async_runtime,
         )
 
 
diff --git a/EvoScientist/cli/interactive.py b/EvoScientist/cli/interactive.py
--- a/EvoScientist/cli/interactive.py
+++ b/EvoScientist/cli/interactive.py
@@ -4,8 +4,10 @@
 import logging
 import queue
 import random
+import signal
 import sys
-from collections.abc import Callable
+import threading
+from collections.abc import Awaitable, Callable
 from dataclasses import dataclass
 from datetime import datetime
 from typing import TYPE_CHECKING, Any
@@ -62,6 +64,7 @@
     _set_channel_response,
     dispatch_channel_slash_command,
 )
+from .channel_sends import PendingChannelSends
 from .file_mentions import complete_file_mention, resolve_file_mentions
 from .rich_command_ui import RichCLICommandUI
 from .status_bar import (
@@ -83,7 +86,12 @@
     make_usage_status_snapshot,
 )
 from .tui_interactive import run_textual_interactive
-from .tui_runtime import resolve_ui_backend, run_streaming
+from .tui_runtime import (
+    StreamCancellationTimeout,
+    resolve_ui_backend,
+    run_streaming,
+    run_streaming_async,
+)
 
 _MEMORY_WORKER_SHUTDOWN_WAIT_SECONDS = 120.0
 _MEMORY_WORKER_SHUTDOWN_POLL_SECONDS = 0.5
@@ -97,6 +105,8 @@
 if TYPE_CHECKING:
     from langgraph.graph.state import CompiledStateGraph
 
+    from ..runtime import AsyncRuntime
+
 
 @dataclass(frozen=True, slots=True)
 class _StartupSession:
@@ -107,6 +117,15 @@ class _StartupSession:
     resumed: bool
 
 
+async def _run_serialized_turn(
+    turn_lock: asyncio.Lock,
+    operation: Callable[[], Awaitable[Any]],
+) -> Any:
+    """Run one session turn without overlapping another frontend source."""
+    async with turn_lock:
+        return await operation()
+
+
 # =============================================================================
 # Banner
 # =============================================================================
@@ -328,6 +347,47 @@ async def _resolve_startup_session(
 # =============================================================================
 
 
+async def _run_rich_cli_streaming_turn(**kwargs: Any) -> str:
+    """Run one Rich CLI turn with a fresh, turn-local SIGINT policy.
+
+    ``asyncio.run`` installs a SIGINT handler whose interrupt count lasts for
+    the lifetime of the runner.  The Rich CLI intentionally recovers after a
+    cancelled turn, so relying on that handler makes Ctrl+C on a later turn
+    look like the runner's second interrupt and raises ``KeyboardInterrupt``.
+
+    While a model turn is active, route the first Ctrl+C to a child task
+    instead.  Restoring the runner's handler after every turn keeps Ctrl+C at
+    the prompt unchanged and resets the force-quit boundary for the next turn.
+    A second Ctrl+C before the current turn settles remains a force quit.
+    """
+    stream_task = asyncio.create_task(
+        run_streaming_async(**kwargs, recover_on_cancel=True)
+    )
+
+    # Interactive CLI execution belongs on the main thread, but retaining the
+    # ordinary await makes this helper safe in embedded/test environments where
+    # Python does not permit installing process signal handlers.
+    if threading.current_thread() is not threading.main_thread():
+        return await stream_task
+
+    previous_sigint = signal.getsignal(signal.SIGINT)
+    interrupted = False
+
+    def _cancel_turn(signum: int, frame: Any) -> None:
+        nonlocal interrupted
+        if interrupted or stream_task.done():
+            signal.default_int_handler(signum, frame)
+            return
+        interrupted = True
+        stream_task.cancel()
+
+    signal.signal(signal.SIGINT, _cancel_turn)
+    try:
+        return await stream_task
+    finally:
+        signal.signal(signal.SIGINT, previous_sigint)
+
+
 def cmd_interactive(
     show_thinking: bool = True,
     channel_send_thinking: bool = True,
@@ -340,6 +400,7 @@ def cmd_interactive(
     thread_id: str | None = None,
     ui_backend: str = "cli",
     config=None,
+    async_runtime: "AsyncRuntime | None" = None,
 ) -> None:
     """Interactive conversation mode with streaming output.
 
@@ -358,15 +419,15 @@ def cmd_interactive(
         thread_id: Optional thread ID to resume a previous session
         ui_backend: UI backend ('cli' or 'tui')
     """
-    import nest_asyncio
-
-    nest_asyncio.apply()
-
     resolved_ui_backend = resolve_ui_backend(ui_backend, warn_fallback=True)
     if resolved_ui_backend == "tui":
         from functools import partial
 
-        load_agent = partial(_load_agent, config=config)
+        load_agent = partial(
+            _load_agent,
+            config=config,
+            runtime=async_runtime,
+        )
         run_textual_interactive(
             show_thinking=show_thinking,
             channel_send_thinking=channel_send_thinking,
@@ -380,6 +441,7 @@ def cmd_interactive(
             load_agent=load_agent,
             create_session_workspace=_create_session_workspace,
             config=config,
+            async_runtime=async_runtime,
         )
         return
 
@@ -497,6 +559,7 @@ def _start_agent_load(checkpointer) -> None:
             checkpointer=checkpointer,
             config=config,
             events=event_sink,
+            runtime=async_runtime,
         )
 
     async def _await_agent_ready() -> "CompiledStateGraph":
@@ -868,6 +931,8 @@ def _stop() -> None:
 
             # ---- Channel queue processing (bus → main thread) ----
 
+            turn_lock = asyncio.Lock()
+
             async def _process_channel_message(msg: ChannelMessage) -> None:
                 """Process a single channel message with real-time streaming.
 
@@ -905,17 +970,12 @@ async def _process_channel_message(msg: ChannelMessage) -> None:
                     console.print(rx)
                     _print_separator()
 
+                    pending_channel_sends = PendingChannelSends(
+                        _ch_mod._bus_loop, _channel_logger
+                    )
+
                     def _send_to_channel(coro, label: str, timeout: int = 15) -> None:
-                        """Schedule an async channel send on the bus loop."""
-                        loop = _ch_mod._bus_loop
-                        if not loop:
-                            return
-                        try:
-                            asyncio.run_coroutine_threadsafe(coro, loop).result(
-                                timeout=timeout
-                            )
-                        except Exception as e:
-                            _channel_logger.debug(f"{label} send failed: {e}")
+                        pending_channel_sends.submit(coro, label, timeout)
 
                     def _send_thinking_to_channel(thinking: str) -> None:
                         ch = msg.channel_ref
@@ -1029,6 +1089,7 @@ async def _on_channel_cmd_completed(
                         on_cmd_completed=_on_channel_cmd_completed,
                         channel_runtime=channel_runtime,
                         graph_gateway=runtime_gateways.graph_gateway,
+                        async_runtime=async_runtime,
                     )
                     if _slash_handled:
                         # A channel-issued /new or /resume rotates the thread
@@ -1047,7 +1108,7 @@ async def _on_channel_cmd_completed(
                         await _refresh_status_snapshot(
                             msg.content, reset_streaming_text=True
                         )
-                        response = run_streaming(
+                        response = await run_streaming_async(
                             ui_backend=state["ui_backend"],
                             agent=ready_agent,
                             message=msg.content,
@@ -1064,11 +1125,13 @@ async def _on_channel_cmd_completed(
                             status_footer_builder=_stream_status_footer,
                             cancel_scope=_ch_mod._channel_message_cancel_scope(msg),
                             gateway=runtime_gateways.graph_gateway,
+                            runtime=async_runtime,
                         )
                     except Exception as e:
                         response = f"Error: {e}"
                         console.print(f"[red]Channel error: {e}[/red]")
 
+                    await pending_channel_sends.settle_async()
                     _set_channel_response(msg.msg_id, response)
                     await _refresh_status_snapshot(reset_streaming_text=True)
 
@@ -1105,7 +1168,7 @@ async def _inject_notification_message(
                 meta = build_metadata(state["workspace_dir"], model)
                 await _refresh_status_snapshot(text, reset_streaming_text=True)
                 ready_agent = await _await_agent_ready()
-                response = run_streaming(
+                response = await run_streaming_async(
                     ui_backend=state["ui_backend"],
                     agent=ready_agent,
                     message=text,
@@ -1121,6 +1184,7 @@ async def _inject_notification_message(
                     on_stream_event=_handle_stream_status_event,
                     status_footer_builder=_stream_status_footer,
                     gateway=runtime_gateways.graph_gateway,
+                    runtime=async_runtime,
                 )
                 _notif_tid = target_thread_id or state["thread_id"]
                 if _ch_mod.publish_to_channel_origin(_notif_tid, response):
@@ -1176,7 +1240,10 @@ async def _check_channel_queue() -> None:
                     except queue.Empty:
                         msg = None
                     if msg is not None:
-                        await _process_channel_message(msg)
+                        await _run_serialized_turn(
+                            turn_lock,
+                            lambda _msg=msg: _process_channel_message(_msg),
+                        )
                         continue  # check queues again immediately
 
                     # Notification path (only when no channel message was pending).
@@ -1193,8 +1260,13 @@ async def _check_channel_queue() -> None:
                         try:
                             await async_notifier.consume_notifications(
                                 run_message=lambda text, notifs, _tid=current_tid: (
-                                    _inject_notification_message(
-                                        text, notifs, target_thread_id=_tid
+                                    _run_serialized_turn(
+                                        turn_lock,
+                                        lambda: _inject_notification_message(
+                                            text,
+                                            notifs,
+                                            target_thread_id=_tid,
+                                        ),
                                     )
                                 ),
                                 read_async_tasks_state=read_async_tasks_state,
@@ -1329,6 +1401,7 @@ def _show_update_hint() -> None:
                                 input_tokens_hint=state.get("status_last_input_tokens"),
                                 channel_runtime=channel_runtime,
                                 graph_gateway=runtime_gateways.graph_gateway,
+                                async_runtime=async_runtime,
                             )
                             await cmd_manager.execute(user_input, ctx)
 
@@ -1411,17 +1484,23 @@ def _show_update_hint() -> None:
                         await _refresh_status_snapshot(
                             message_to_send, reset_streaming_text=True
                         )
-                        run_streaming(
-                            ui_backend=state["ui_backend"],
-                            agent=ready_agent,
-                            message=message_to_send,
-                            thread_id=state["thread_id"],
-                            show_thinking=show_thinking,
-                            interactive=True,
-                            metadata=meta,
-                            on_stream_event=_handle_stream_status_event,
-                            status_footer_builder=_stream_status_footer,
-                            gateway=runtime_gateways.graph_gateway,
+                        await _run_serialized_turn(
+                            turn_lock,
+                            lambda _agent=ready_agent, _message=message_to_send, _thread_id=state["thread_id"], _meta=meta: (
+                                _run_rich_cli_streaming_turn(
+                                    ui_backend=state["ui_backend"],
+                                    agent=_agent,
+                                    message=_message,
+                                    thread_id=_thread_id,
+                                    show_thinking=show_thinking,
+                                    interactive=True,
+                                    metadata=_meta,
+                                    on_stream_event=_handle_stream_status_event,
+                                    status_footer_builder=_stream_status_footer,
+                                    gateway=runtime_gateways.graph_gateway,
+                                    runtime=async_runtime,
+                                )
+                            ),
                         )
                         await _refresh_status_snapshot(reset_streaming_text=True)
                         console.print()
@@ -1436,6 +1515,14 @@ def _show_update_hint() -> None:
                         console.print()
                         state["running"] = False
                         break
+                    except StreamCancellationTimeout as e:
+                        console.print(f"[red]{escape(str(e))}[/red]")
+                        console.print(
+                            "[dim]Exiting because the active turn could not be "
+                            "stopped safely.[/dim]"
+                        )
+                        state["running"] = False
+                        break
                     except Exception as e:
                         error_msg = str(e)
                         if (
@@ -1456,6 +1543,17 @@ def _show_update_hint() -> None:
                     await queue_task
                 except asyncio.CancelledError:
                     pass
+                try:
+                    from ..middleware.code_interpreter import (
+                        aclose_code_interpreters,
+                    )
+
+                    await aclose_code_interpreters()
+                except Exception:
+                    _channel_logger.debug(
+                        "code interpreter cleanup failed",
+                        exc_info=True,
+                    )
                 # Best-effort: guard so a DB lookup failure here can't
                 # shadow the original exception exiting _async_main_loop.
                 current_tid = state.get("thread_id")
@@ -1493,6 +1591,7 @@ def cmd_run(
     ui_backend: str = "cli",
     *,
     runtime_gateways: RuntimeGateways,
+    async_runtime: "AsyncRuntime | None" = None,
 ) -> None:
     """Single-shot execution with streaming display.
 
@@ -1526,6 +1625,7 @@ def cmd_run(
             interactive=False,
             metadata=meta,
             gateway=runtime_gateways.graph_gateway,
+            runtime=async_runtime,
         )
         _wait_for_memory_workers_before_exit()
     except Exception as e:
diff --git a/EvoScientist/cli/tui_backends.py b/EvoScientist/cli/tui_backends.py
--- a/EvoScientist/cli/tui_backends.py
+++ b/EvoScientist/cli/tui_backends.py
@@ -4,11 +4,14 @@
 
 from collections.abc import Callable
 from dataclasses import dataclass
-from typing import Any, Protocol
+from typing import TYPE_CHECKING, Any, Protocol
 
 from ..gateway import GraphGateway
 from ..stream.display import _run_streaming
 
+if TYPE_CHECKING:
+    from ..runtime import AsyncRuntime
+
 
 class StreamingTUIBackend(Protocol):
     """Protocol for TUI backends that can render agent streaming output."""
@@ -33,6 +36,7 @@ def run_streaming(
         ask_user_prompt_fn: Callable[[dict], dict] | None = None,
         cancel_scope: str | None = None,
         gateway: GraphGateway,
+        runtime: AsyncRuntime | None = None,
     ) -> str:
         """Run streaming and return final response text."""
 
@@ -61,6 +65,7 @@ def run_streaming(
         ask_user_prompt_fn: Callable[[dict], dict] | None = None,
         cancel_scope: str | None = None,
         gateway: GraphGateway,
+        runtime: AsyncRuntime | None = None,
     ) -> str:
         return _run_streaming(
             agent=agent,
@@ -78,4 +83,5 @@ def run_streaming(
             ask_user_prompt_fn=ask_user_prompt_fn,
             cancel_scope=cancel_scope,
             gateway=gateway,
+            runtime=runtime,
         )
diff --git a/EvoScientist/cli/tui_interactive.py b/EvoScientist/cli/tui_interactive.py
--- a/EvoScientist/cli/tui_interactive.py
+++ b/EvoScientist/cli/tui_interactive.py
@@ -78,6 +78,9 @@
     make_usage_status_snapshot,
 )
 
+if TYPE_CHECKING:
+    from ..runtime import AsyncRuntime
+
 _channel_logger = logging.getLogger(__name__)
 
 if TYPE_CHECKING:
@@ -483,6 +486,7 @@ def run_textual_interactive(
     load_agent: Callable[..., Any],
     create_session_workspace: Callable[[str | None], str],
     config: Any | None = None,
+    async_runtime: AsyncRuntime | None = None,
 ) -> None:
     """Run full-screen Textual interactive chat loop."""
     if config is None:
@@ -1363,7 +1367,7 @@ async def _wait_for_approval(self, approval_widget) -> Any:
             Returns the ``ApprovalWidget.Decided`` message, or ``None`` on
             timeout / cancellation.
             """
-            self._approval_future = asyncio.get_event_loop().create_future()
+            self._approval_future = asyncio.get_running_loop().create_future()
             try:
                 return await asyncio.wait_for(self._approval_future, timeout=300)
             except (TimeoutError, asyncio.CancelledError):
@@ -1409,7 +1413,7 @@ async def _wait_for_thread_pick(
 
             Returns the selected thread_id, or ``None`` on cancel/timeout.
             """
-            self._picker_future = asyncio.get_event_loop().create_future()
+            self._picker_future = asyncio.get_running_loop().create_future()
             try:
                 return await asyncio.wait_for(self._picker_future, timeout=120)
             except (TimeoutError, asyncio.CancelledError):
@@ -1437,7 +1441,7 @@ async def _wait_for_skill_browse(self, browser_widget) -> list[str] | None:
 
             Returns list of install sources, or None on cancel/timeout.
             """
-            self._browser_future = asyncio.get_event_loop().create_future()
+            self._browser_future = asyncio.get_running_loop().create_future()
             try:
                 return await asyncio.wait_for(self._browser_future, timeout=300)
             except (TimeoutError, asyncio.CancelledError):
@@ -1464,7 +1468,7 @@ def on_skill_browser_widget_cancelled(self, event) -> None:  # type: ignore[over
 
         async def _wait_for_mcp_browse(self, browser_widget) -> list | None:
             """Wait for user to complete MCP server browsing."""
-            self._mcp_browser_future = asyncio.get_event_loop().create_future()
+            self._mcp_browser_future = asyncio.get_running_loop().create_future()
             try:
                 return await asyncio.wait_for(self._mcp_browser_future, timeout=300)
             except (TimeoutError, asyncio.CancelledError):
@@ -1492,7 +1496,7 @@ async def _wait_for_model_pick(self, picker_widget) -> tuple[str, str] | None:
 
             Returns ``(name, provider)`` or ``None`` on cancel/timeout.
             """
-            self._model_picker_future = asyncio.get_event_loop().create_future()
+            self._model_picker_future = asyncio.get_running_loop().create_future()
             try:
                 return await asyncio.wait_for(self._model_picker_future, timeout=120)
             except (TimeoutError, asyncio.CancelledError):
@@ -1554,6 +1558,7 @@ async def _stream_with_widgets(
             """
             from ..stream.display import (
                 is_stream_cancel_requested,
+                iter_with_stream_cancel,
             )
 
             container = self.query_one("#chat", VerticalScroll)
@@ -1780,16 +1785,21 @@ def _get_sa_widget(
                     summarization_w = None
                 try:
                     _anchor_engaged = False
-                    async for event in graph_gateway.stream_events(
-                        RunRequest(
-                            message=_stream_input,
-                            thread_id=thread_id_override or self._conversation_tid,
-                            metadata=metadata,
-                            target=GraphTarget(
-                                local_graph=agent,
-                                workspace_dir=self._workspace_dir,
-                            ),
-                        )
+                    async for event in iter_with_stream_cancel(
+                        graph_gateway.stream_events(
+                            RunRequest(
+                                message=_stream_input,
+                                thread_id=(
+                                    thread_id_override or self._conversation_tid
+                                ),
+                                metadata=metadata,
+                                target=GraphTarget(
+                                    local_graph=agent,
+                                    workspace_dir=self._workspace_dir,
+                                ),
+                            )
+                        ),
+                        cancel_scope,
                     ):
                         if is_stream_cancel_requested(cancel_scope):
                             response = await _mark_cancelled_response()
@@ -2380,6 +2390,11 @@ async def _run_turn(
             cancelled = False
             response = ""
             try:
+                # Foreground turns share the legacy default scope. Reset it at
+                # the turn boundary; scoped channel stop requests remain armed.
+                from ..stream.display import clear_stream_cancel
+
+                clear_stream_cancel()
                 self._busy = True
                 self._turn_started_at = datetime.now()
                 self._status_phase = ResearchPhase.THINKING
@@ -2414,6 +2429,17 @@ async def _run_turn(
                 )
             except asyncio.CancelledError:
                 cancelled = True
+                try:
+                    from ..middleware.code_interpreter import (
+                        aclose_code_interpreters,
+                    )
+
+                    await aclose_code_interpreters()
+                except Exception:
+                    _channel_logger.debug(
+                        "code interpreter cleanup after cancellation failed",
+                        exc_info=True,
+                    )
                 self._append_system("\nInterrupted by user", style="dim italic #ffe082")
             finally:
                 self._busy = False
@@ -2547,6 +2573,7 @@ def _channel_ask_user(ask_user_data: dict) -> dict:
                     on_cmd_completed=self._on_channel_cmd_completed,
                     channel_runtime=self._channel_runtime,
                     graph_gateway=self._runtime_gateways.graph_gateway,
+                    async_runtime=async_runtime,
                 )
                 if _slash_handled:
                     # A channel-issued /new or /resume rotates the thread in
@@ -3091,6 +3118,7 @@ async def _handle_command(self, command: str) -> None:
                     input_tokens_hint=self._status_last_input_tokens,
                     channel_runtime=self._channel_runtime,
                     graph_gateway=self._runtime_gateways.graph_gateway,
+                    async_runtime=async_runtime,
                 )
 
                 if await cmd_manager.execute(command, ctx):
@@ -3237,6 +3265,9 @@ def action_request_quit(self) -> None:
                     self._queued_messages.clear()
                     self._render_queue_indicator()
                 if self._run_task is not None and not self._run_task.done():
+                    from ..stream.display import request_stream_cancel
+
+                    request_stream_cancel()
                     self._run_task.cancel()
                 else:
                     # Edge case: busy but no task — force reset
@@ -3604,6 +3635,18 @@ async def _amain() -> None:
             finally:
                 from .resume_hint import print_resume_hint
 
+                try:
+                    from ..middleware.code_interpreter import (
+                        aclose_code_interpreters,
+                    )
+
+                    await aclose_code_interpreters()
+                except Exception:
+                    _channel_logger.debug(
+                        "code interpreter cleanup failed",
+                        exc_info=True,
+                    )
+
                 # Best-effort resume hint — guarded so failures here (e.g.
                 # DB teardown race during abnormal shutdown) cannot shadow
                 # the original run_async traceback.
@@ -3623,12 +3666,4 @@ async def _amain() -> None:
                 except Exception:
                     _channel_logger.debug("print_resume_hint failed", exc_info=True)
 
-    import nest_asyncio  # type: ignore[import-untyped]
-
-    nest_asyncio.apply()
-    try:
-        loop = asyncio.get_event_loop()
-    except RuntimeError:
-        loop = asyncio.new_event_loop()
-        asyncio.set_event_loop(loop)
-    loop.run_until_complete(_amain())
+    asyncio.run(_amain())
diff --git a/EvoScientist/cli/tui_runtime.py b/EvoScientist/cli/tui_runtime.py
--- a/EvoScientist/cli/tui_runtime.py
+++ b/EvoScientist/cli/tui_runtime.py
@@ -2,14 +2,20 @@
 
 from __future__ import annotations
 
+import asyncio
 from collections.abc import Callable
-from typing import Any
+from typing import TYPE_CHECKING, Any
 
 from ..gateway import GraphGateway
+from ..runtime import AsyncRuntimeError
 from ..stream.console import console
 from .tui_backends import RichStreamingBackend, StreamingTUIBackend
 
+if TYPE_CHECKING:
+    from ..runtime import AsyncRuntime
+
 DEFAULT_UI_BACKEND = "cli"
+STREAM_CANCEL_SETTLE_TIMEOUT = 5.0
 # "webui" launches the browser front-end instead of an in-terminal UI; it is
 # intercepted earlier (cli/commands.py:_main_callback) and never reaches the
 # streaming backends, but is listed here so normalize/resolve preserve it
@@ -18,6 +24,41 @@
 _LEGACY_BACKEND_MAP = {"textual": "tui", "rich": "cli"}
 
 
+class StreamCancellationTimeout(RuntimeError):
+    """A blocking renderer did not settle after its turn was cancelled."""
+
+
+def _consume_late_worker_result(worker: asyncio.Task[Any]) -> None:
+    """Retrieve a detached worker result so eventual failure is not unhandled."""
+    try:
+        worker.exception()
+    except asyncio.CancelledError:
+        pass
+
+
+async def settle_cancelled_worker(
+    worker: asyncio.Task[Any],
+    *,
+    on_cancel: Callable[[], Any],
+) -> Any:
+    """Request cooperative cancellation and wait a bounded time for settlement."""
+    on_cancel()
+    done, _ = await asyncio.wait(
+        {worker},
+        timeout=STREAM_CANCEL_SETTLE_TIMEOUT,
+    )
+    if not done:
+        worker.add_done_callback(_consume_late_worker_result)
+        raise StreamCancellationTimeout(
+            "The active turn did not stop within "
+            f"{STREAM_CANCEL_SETTLE_TIMEOUT:g} seconds after cancellation."
+        )
+    try:
+        return worker.result()
+    except Exception:
+        return ""
+
+
 def normalize_ui_backend(value: str | None) -> str:
     """Normalize user-provided backend name with a safe default."""
     if not value:
@@ -81,6 +122,7 @@ def run_streaming(
     ask_user_prompt_fn: Callable[[dict], dict] | None = None,
     cancel_scope: str | None = None,
     gateway: GraphGateway,
+    runtime: AsyncRuntime | None = None,
 ) -> str:
     """Run streaming with the selected backend."""
     backend = get_backend(ui_backend, warn_fallback=True)
@@ -101,7 +143,10 @@ def run_streaming(
             ask_user_prompt_fn=ask_user_prompt_fn,
             cancel_scope=cancel_scope,
             gateway=gateway,
+            runtime=runtime,
         )
+    except AsyncRuntimeError:
+        raise
     except RuntimeError:
         requested = normalize_ui_backend(ui_backend)
         if requested == "tui":
@@ -124,5 +169,40 @@ def run_streaming(
                 ask_user_prompt_fn=ask_user_prompt_fn,
                 cancel_scope=cancel_scope,
                 gateway=gateway,
+                runtime=runtime,
+            )
+        raise
+
+
+async def run_streaming_async(
+    *,
+    recover_on_cancel: bool = False,
+    **kwargs: Any,
+) -> str:
+    """Run the synchronous Rich renderer without blocking a frontend loop.
+
+    Cancellation requests the matching stream scope and gives the worker a
+    bounded interval to unwind.  Foreground interactive turns may opt into
+    recovering the frontend task after cleanup so Ctrl+C returns to the prompt.
+    """
+    from ..stream.display import request_stream_cancel
+
+    worker = asyncio.create_task(asyncio.to_thread(run_streaming, **kwargs))
+    try:
+        return await asyncio.shield(worker)
+    except asyncio.CancelledError:
+        try:
+            response = await settle_cancelled_worker(
+                worker,
+                on_cancel=lambda: request_stream_cancel(kwargs.get("cancel_scope")),
             )
+        finally:
+            from ..middleware.code_interpreter import aclose_code_interpreters
+
+            await aclose_code_interpreters()
+        if recover_on_cancel:
+            current = asyncio.current_task()
+            if current is not None and current.uncancel() > 0:
+                raise
+            return response
         raise
diff --git a/EvoScientist/commands/base.py b/EvoScientist/commands/base.py
--- a/EvoScientist/commands/base.py
+++ b/EvoScientist/commands/base.py
@@ -6,6 +6,7 @@
 
 if TYPE_CHECKING:
     from ..gateway import GraphGateway
+    from ..runtime import AsyncRuntime
 
 
 @dataclass
@@ -91,6 +92,7 @@ class CommandContext:
     config: Any = None
     channel_runtime: ChannelRuntime | None = None
     graph_gateway: GraphGateway | None = None
+    async_runtime: AsyncRuntime | None = None
     command_error: str | None = None
     # Real LLM input token count from last usage_metadata (includes system
     # prompt + tool schemas).  Used by /compact for accurate display.
diff --git a/EvoScientist/commands/implementation/mcp_install.py b/EvoScientist/commands/implementation/mcp_install.py
--- a/EvoScientist/commands/implementation/mcp_install.py
+++ b/EvoScientist/commands/implementation/mcp_install.py
@@ -37,7 +37,7 @@ async def execute(self, ctx: CommandContext, args: list[str]) -> None:
         try:
             import asyncio
 
-            servers = await asyncio.get_event_loop().run_in_executor(
+            servers = await asyncio.get_running_loop().run_in_executor(
                 None, fetch_marketplace_index
             )
         except Exception as e:
diff --git a/EvoScientist/commands/implementation/model.py b/EvoScientist/commands/implementation/model.py
--- a/EvoScientist/commands/implementation/model.py
+++ b/EvoScientist/commands/implementation/model.py
@@ -130,6 +130,7 @@ async def _apply_model(
         *,
         save: bool = False,
     ) -> None:
+        import asyncio
         import copy
 
         from ...cli.agent import _load_agent
@@ -139,6 +140,7 @@ async def _apply_model(
             set_active_config,
             set_chat_model_instance,
         )
+        from ...runtime import AsyncRuntime
 
         cfg = _ensure_config()
 
@@ -158,12 +160,19 @@ async def _apply_model(
 
         try:
             new_chat_model = _build_chat_model(temp_cfg)
-            new_agent = _load_agent(
-                workspace_dir=ctx.workspace_dir,
-                checkpointer=ctx.checkpointer,
-                config=temp_cfg,
-                chat_model=new_chat_model,
-                events=events,
+            load_kwargs = {
+                "workspace_dir": ctx.workspace_dir,
+                "checkpointer": ctx.checkpointer,
+                "config": temp_cfg,
+                "chat_model": new_chat_model,
+                "events": events,
+            }
+            async_runtime = getattr(ctx, "async_runtime", None)
+            if isinstance(async_runtime, AsyncRuntime):
+                load_kwargs["runtime"] = async_runtime
+            new_agent = await asyncio.to_thread(
+                _load_agent,
+                **load_kwargs,
             )
         except Exception as e:
             ctx.ui.append_system(f"Failed to switch model: {e}", style="red")
diff --git a/EvoScientist/config/onboard/channels.py b/EvoScientist/config/onboard/channels.py
--- a/EvoScientist/config/onboard/channels.py
+++ b/EvoScientist/config/onboard/channels.py
@@ -10,6 +10,7 @@
 import questionary
 from questionary import Choice
 
+from ...runtime import AsyncRuntime
 from ..settings import EvoScientistConfig
 from .helpers import (
     _setup_imessage,
@@ -21,7 +22,11 @@
 )
 
 
-def _step_channels(config: EvoScientistConfig) -> dict[str, object]:
+def _step_channels(
+    config: EvoScientistConfig,
+    *,
+    runtime: AsyncRuntime | None = None,
+) -> dict[str, object]:
     """Step: Select channels to enable on startup.
 
     Presents a multi-select list of supported channels.
@@ -35,6 +40,12 @@ def _step_channels(config: EvoScientistConfig) -> dict[str, object]:
         Dict mapping config field names to their new values.
         Empty dict when the user skips or selects nothing.
     """
+    # Direct/programmatic callers still get a single owned runtime for the
+    # whole step. CLI callers pass their application-scoped runtime instead.
+    if runtime is None:
+        with AsyncRuntime(thread_name="evosci-onboard-runtime") as owned_runtime:
+            return _step_channels(config, runtime=owned_runtime)
+
     # Currently enabled channels
     _currently_enabled = {
         t.strip()
@@ -592,11 +603,9 @@ def _step_channels(config: EvoScientistConfig) -> dict[str, object]:
                         f" to {_accounts_path}.[/dim]"
                     )
                     try:
-                        import asyncio
-
                         from ...channels.wechat.personal import qr_login
 
-                        creds = asyncio.run(qr_login())
+                        creds = runtime.run_sync(qr_login)
                     except Exception as exc:
                         console.print(f"  [red]✗ Scan failed: {exc}[/red]")
                         creds = None
@@ -783,7 +792,7 @@ def _step_channels(config: EvoScientistConfig) -> dict[str, object]:
             updates[senders_field] = senders.strip()
 
         # Probe validation
-        _probe_channel(ch_name, config, updates)
+        _probe_channel(ch_name, config, updates, runtime=runtime)
 
         enabled_channels.append(ch_name)
 
@@ -820,12 +829,13 @@ def _probe_channel(
     ch_name: str,
     config: EvoScientistConfig,
     updates: dict[str, object],
+    *,
+    runtime: AsyncRuntime,
 ) -> None:
     """Run the probe for a channel type and print the result.
 
     Non-fatal: prints a warning on failure but does not prevent enabling.
     """
-    import asyncio
 
     def _val(key: str, fallback: str = "") -> str:
         """Get a value from updates first, then config, then fallback."""
@@ -928,17 +938,7 @@ async def _run() -> tuple[bool, str]:
             return True, "No probe available"
 
     try:
-        try:
-            loop = asyncio.get_event_loop()
-            if loop.is_running():
-                import nest_asyncio  # type: ignore[import-untyped]
-
-                nest_asyncio.apply()
-        except RuntimeError:
-            loop = asyncio.new_event_loop()
-            asyncio.set_event_loop(loop)
-
-        ok, detail = loop.run_until_complete(_run())
+        ok, detail = runtime.run_sync(_run)
         if ok:
             console.print(f"  [green]✓ {detail}[/green]")
         else:
diff --git a/EvoScientist/config/onboard/wizard.py b/EvoScientist/config/onboard/wizard.py
--- a/EvoScientist/config/onboard/wizard.py
+++ b/EvoScientist/config/onboard/wizard.py
@@ -9,6 +9,7 @@
 from rich.panel import Panel
 from rich.text import Text
 
+from ...runtime import AsyncRuntime
 from ..settings import (
     EvoScientistConfig,
     get_config_path,
@@ -475,6 +476,7 @@ def run_onboard(
     skip_validation: bool = False,
     prompter=None,
     only_sections: set[str] | frozenset[str] | None = None,
+    runtime: AsyncRuntime | None = None,
 ) -> bool:
     """Run the interactive onboarding wizard.
 
@@ -487,6 +489,9 @@ def run_onboard(
         only_sections: If given, restrict the wizard to exactly these section
             ids — the Keep/Modify/Reset prompt is skipped. Used by ``EvoSci
             configure <section>`` to re-run a single phase.
+        runtime: Optional application-scoped async runtime used by channel
+            login and credential probes. Direct callers may omit it; the
+            channel step then owns a runtime for the duration of that step.
 
     Returns:
         True if configuration was saved, False if cancelled.
@@ -883,7 +888,7 @@ def _require(pid: str, label: str) -> None:
                 _step_tinytex()
 
             if "channels" in sections_to_run:
-                for key, value in _step_channels(config).items():
+                for key, value in _step_channels(config, runtime=runtime).items():
                     setattr(config, key, value)
                 _autosave(config)
 
diff --git a/EvoScientist/mcp/client.py b/EvoScientist/mcp/client.py
--- a/EvoScientist/mcp/client.py
+++ b/EvoScientist/mcp/client.py
@@ -19,6 +19,8 @@
 
 import yaml
 
+from ..runtime import AsyncRuntime, AsyncRuntimeError
+
 logger = logging.getLogger(__name__)
 
 
@@ -838,6 +840,7 @@ def load_mcp_tools(
     config: dict[str, Any] | None = None,
     *,
     on_progress: ProgressCallback | None = None,
+    runtime: AsyncRuntime | None = None,
 ) -> dict[str, list]:
     """Load MCP tools and return them grouped by target agent.
 
@@ -854,6 +857,10 @@ def load_mcp_tools(
             warnings when the caller has already loaded the config.
         on_progress: Optional callback invoked per server with
             ``(event, server_name, detail)``.  See :data:`ProgressCallback`.
+        runtime: Runtime that owns MCP discovery work. When omitted, this
+            function creates one scoped to this call. The returned adapters
+            open a fresh MCP session for each tool call and do not retain the
+            discovery loop.
 
     Returns:
         Dict mapping agent name -> list of LangChain ``BaseTool`` objects.
@@ -865,19 +872,28 @@ def load_mcp_tools(
     if not config:
         return {}
 
-    try:
-        loop = asyncio.get_running_loop()
-    except RuntimeError:
-        loop = None
+    if runtime is None:
+        with AsyncRuntime(thread_name="evosci-mcp-runtime") as owned_runtime:
+            return load_mcp_tools(
+                config,
+                on_progress=on_progress,
+                runtime=owned_runtime,
+            )
 
     try:
-        if loop and loop.is_running():
-            # Inside an already-running event loop (e.g. Jupyter) —
-            # nest_asyncio patches the loop so asyncio.run() works.
-            import nest_asyncio
-
-            nest_asyncio.apply()
-        server_tools = asyncio.run(_load_tools(config, on_progress=on_progress))
+        server_tools = runtime.run_sync(
+            lambda: _load_tools(config, on_progress=on_progress)
+        )
+    except AsyncRuntimeError as exc:
+        # A bridge lifecycle/call-site error is not an MCP availability
+        # failure.  In particular, hiding a running-loop violation here makes
+        # callers cache an empty tool set for the rest of the process.
+        if "cannot block a running event loop" in str(exc):
+            raise AsyncRuntimeError(
+                "load_mcp_tools() cannot run inside an async context; use "
+                "`await aload_mcp_tools(config, on_progress=...)` instead"
+            ) from exc
+        raise
     except Exception as exc:
         logger.warning("MCP tool loading failed: %s", exc)
         return {}
diff --git a/EvoScientist/middleware/code_interpreter.py b/EvoScientist/middleware/code_interpreter.py
--- a/EvoScientist/middleware/code_interpreter.py
+++ b/EvoScientist/middleware/code_interpreter.py
@@ -29,7 +29,9 @@
 
 from __future__ import annotations
 
+import asyncio
 import contextlib
+import logging
 import weakref
 
 from langchain.agents.middleware.types import ModelRequest
@@ -40,6 +42,9 @@
 # values; tests / ad-hoc callers can omit and get sensible defaults.
 _DEFAULT_TIMEOUT_SECONDS: float = 60.0
 _DEFAULT_MAX_RESULT_CHARS: int = 10000
+_CLOSE_TIMEOUT_SECONDS: float = 10.0
+
+logger = logging.getLogger(__name__)
 
 _MEMORY_FIRST_INTERPRETER_PROMPT = (
     "\n\nWhen memory tools (search_observations, read_memory) are available, use "
@@ -83,10 +88,34 @@ async def aclose(self) -> None:
 _live_interpreters = weakref.WeakSet()
 
 
-async def aclose_code_interpreters() -> None:
-    """Close all live EvoScientist QuickJS middleware instances."""
-    for middleware in tuple(_live_interpreters):
-        await middleware.aclose()
+async def aclose_code_interpreters(
+    *,
+    timeout: float = _CLOSE_TIMEOUT_SECONDS,
+) -> None:
+    """Close live QuickJS middleware without blocking application shutdown."""
+    middlewares = tuple(_live_interpreters)
+    if not middlewares:
+        return
+
+    close_tasks = [middleware.aclose() for middleware in middlewares]
+    try:
+        results = await asyncio.wait_for(
+            asyncio.gather(*close_tasks, return_exceptions=True),
+            timeout=timeout,
+        )
+    except TimeoutError:
+        logger.warning(
+            "code interpreter cleanup did not finish within %g seconds",
+            timeout,
+        )
+        return
+
+    for result in results:
+        if isinstance(result, BaseException):
+            logger.debug(
+                "code interpreter cleanup failed",
+                exc_info=(type(result), result, result.__traceback__),
+            )
 
 
 # Read-only, batchable tools that benefit from being callable inside JS.
diff --git a/EvoScientist/middleware/model_fallback.py b/EvoScientist/middleware/model_fallback.py
--- a/EvoScientist/middleware/model_fallback.py
+++ b/EvoScientist/middleware/model_fallback.py
@@ -287,6 +287,76 @@ async def _try_fallbacks(
     _raise_normalized(last_failing_request, last_exc)
 
 
+def _try_fallbacks_sync(
+    request: ModelRequest,
+    invoke: Callable[[ModelRequest], ModelResponse],
+    primary_exc: Exception,
+    events: MiddlewareEventSink,
+) -> ModelResponse:
+    """Synchronous counterpart to :func:`_try_fallbacks`.
+
+    The synchronous middleware path calls a synchronous model handler. Keeping
+    that traversal synchronous avoids manufacturing an event loop solely to
+    share the async implementation.
+    """
+    from ..llm.models import get_chat_model
+
+    events.emit_fallback_notice(
+        f"Primary model failed: {type(primary_exc).__name__}: {primary_exc}",
+        "yellow",
+    )
+    logger.warning(
+        "Primary model failed: %s: %s", type(primary_exc).__name__, primary_exc
+    )
+
+    last_exc = primary_exc
+    last_failing_request = request
+
+    for model_name, provider in get_fallback_chain():
+        events.emit_fallback_notice(
+            f"  -> Falling back to {model_name} ({provider}) due to: "
+            f"{type(last_exc).__name__}: {last_exc}",
+            "yellow",
+        )
+        try:
+            fallback_model = get_chat_model(model=model_name, provider=provider)
+            fb_request = request.override(model=fallback_model)
+            result = invoke(fb_request)
+            events.emit_fallback_notice(
+                f"  Fallback to {model_name} ({provider}) succeeded",
+                "green",
+            )
+            logger.info("Fallback to %s (%s) succeeded", model_name, provider)
+            return result
+        except Exception as fb_exc:
+            reason = _is_non_fallbackable(fb_exc)
+            if reason is not None:
+                events.emit_fallback_notice(
+                    f"  {model_name} hit non-fallbackable error ({reason}) "
+                    f"-- aborting fallback chain",
+                    "red",
+                )
+                _raise_normalized(fb_request, fb_exc)
+            last_exc = fb_exc
+            last_failing_request = fb_request
+            events.emit_fallback_notice(
+                f"  x {model_name} also failed: {type(fb_exc).__name__}: {fb_exc}",
+                "red",
+            )
+            logger.warning(
+                "Fallback %s (provider=%s) failed: %s: %s",
+                model_name,
+                provider,
+                type(fb_exc).__name__,
+                fb_exc,
+            )
+
+    events.emit_fallback_notice(
+        "  All fallbacks exhausted -- re-raising last error", "red"
+    )
+    _raise_normalized(last_failing_request, last_exc)
+
+
 def _raise_normalized(request: ModelRequest, exc: Exception) -> None:
     """Wrap *exc* in a ``ProviderStreamError`` attributed to
     ``request.model`` and raise, so the outer chain sees the failure
@@ -334,6 +404,23 @@ def _guard_and_fallback(
     return _try_fallbacks(request, invoke, primary_exc, events)
 
 
+def _guard_and_fallback_sync(
+    primary_exc: Exception,
+    request: ModelRequest,
+    invoke: Callable[[ModelRequest], ModelResponse],
+    events: MiddlewareEventSink,
+) -> ModelResponse:
+    """Validate and run the native synchronous fallback traversal."""
+    reason = _is_non_fallbackable(primary_exc)
+    if reason is not None:
+        events.emit_fallback_notice(
+            f"Model error ({reason}) -- not eligible for fallback, re-raising",
+            "red",
+        )
+        _raise_normalized(request, primary_exc)
+    return _try_fallbacks_sync(request, invoke, primary_exc, events)
+
+
 class ModelFallbackMiddleware(AgentMiddleware):
     """LangChain AgentMiddleware that retries failed model calls on fallbacks.
 
@@ -363,15 +450,7 @@ def wrap_model_call(
         try:
             return handler(request)
         except Exception as exc:
-
-            async def _sync_invoke(r: ModelRequest) -> ModelResponse:
-                return handler(r)
-
-            import asyncio
-
-            return asyncio.run(
-                _guard_and_fallback(exc, request, _sync_invoke, self._events)
-            )
+            return _guard_and_fallback_sync(exc, request, handler, self._events)
 
     async def awrap_model_call(
         self,
diff --git a/EvoScientist/middleware/tool_selector.py b/EvoScientist/middleware/tool_selector.py
--- a/EvoScientist/middleware/tool_selector.py
+++ b/EvoScientist/middleware/tool_selector.py
@@ -18,6 +18,7 @@
 from __future__ import annotations
 
 import logging
+import threading
 from collections.abc import Awaitable, Callable, Iterable
 from typing import Any
 
@@ -146,6 +147,8 @@ def __init__(
         # Agent tools are fixed after graph construction, so the filtered
         # always-include set is stable for this middleware instance.
         self._selector: AgentMiddleware | None = None
+        self._fallback_warning_emitted = False
+        self._fallback_warning_lock = threading.Lock()
 
     def _build_selector(self, request: ModelRequest) -> AgentMiddleware:
         if self._selector is None:
@@ -157,6 +160,19 @@ def _build_selector(self, request: ModelRequest) -> AgentMiddleware:
     def _selected_names(request: ModelRequest) -> list[str]:
         return [name for tool in request.tools if (name := _tool_name(tool))]
 
+    def _report_selector_failure(self, exc: Exception) -> None:
+        """Expose selector degradation once without flooding normal logs."""
+        with self._fallback_warning_lock:
+            emit_warning = not self._fallback_warning_emitted
+            self._fallback_warning_emitted = True
+        if emit_warning:
+            logger.warning(
+                "tool_selector.fallback error_type=%s using_all_tools=true; "
+                "details and subsequent failures are logged at DEBUG",
+                type(exc).__name__,
+            )
+        logger.debug("Tool selector failed, using all tools", exc_info=True)
+
     def wrap_model_call(
         self,
         request: ModelRequest,
@@ -197,19 +213,13 @@ def _handler_after_selection(req: ModelRequest) -> ModelResponse:
         except Exception as exc:
             if _handler_called:
                 raise  # Error from downstream model — don't retry
-            from ..llm.errors import ProviderStreamError
-            from .error_normalization import _is_provider_error
-
-            if isinstance(exc, ProviderStreamError) or _is_provider_error(exc):
-                # Auth / quota / connection failures on the selector's
-                # own model. Falling back to "use all tools" would hit
-                # the same provider anyway (same client, likely same
-                # credentials). Surface it instead so the user sees
-                # the real cause.
-                raise
-            # Structured-output shape / config failure — gracefully
-            # degrade to using all tools.
-            logger.debug("Tool selector failed, using all tools", exc_info=True)
+            # The selector is an optimization, so every selector-only failure
+            # degrades to all tools. This includes provider failures: the
+            # downstream model-fallback middleware may replace the request's
+            # primary model, but it cannot replace this selector's fixed
+            # auxiliary model. Re-raising here would make a healthy fallback
+            # retry the same failed selector and never reach the model call.
+            self._report_selector_failure(exc)
             _end_selection()
             return handler(request)
         finally:
@@ -252,14 +262,7 @@ async def _handler_after_selection(req: ModelRequest) -> ModelResponse:
         except Exception as exc:
             if _handler_called:
                 raise
-            from ..llm.errors import ProviderStreamError
-            from .error_normalization import _is_provider_error
-
-            if isinstance(exc, ProviderStreamError) or _is_provider_error(exc):
-                # See sync path — surface provider errors, degrade only
-                # on shape / config failures.
-                raise
-            logger.debug("Tool selector failed, using all tools", exc_info=True)
+            self._report_selector_failure(exc)
             _end_selection()
             return await handler(request)
         finally:
diff --git a/EvoScientist/runtime.py b/EvoScientist/runtime.py
new file mode 100644
--- /dev/null
+++ b/EvoScientist/runtime.py
@@ -0,0 +1,565 @@
+"""Application-scoped ownership for EvoScientist async work.
+
+``AsyncRuntime`` owns one continuously running event loop on a dedicated
+thread. Callers share the runtime, never its raw loop:
+
+* synchronous code uses :meth:`AsyncRuntime.run_sync`;
+* code already on another event loop uses :meth:`AsyncRuntime.run_async`;
+* durable background work uses :meth:`AsyncRuntime.spawn`.
+
+The API accepts factories rather than pre-created coroutines so construction
+happens on the owned loop. There is deliberately no module singleton: an
+application bootstrap owns an instance, passes it to consumers, and closes it.
+"""
+
+from __future__ import annotations
+
+import asyncio
+import concurrent.futures
+import contextvars
+import logging
+import threading
+import time
+from collections.abc import Awaitable, Callable
+from typing import Any, Generic, TypeVar
+
+from EvoScientist._winloop import ensure_proactor_event_loop_policy
+
+logger = logging.getLogger(__name__)
+
+T = TypeVar("T")
+AsyncFactory = Callable[[], Awaitable[T]]
+
+
+class AsyncRuntimeError(RuntimeError):
+    """Base error raised by :class:`AsyncRuntime`."""
+
+
+class AsyncRuntimeClosedError(AsyncRuntimeError):
+    """Raised when work is submitted after shutdown begins."""
+
+
+class RuntimeHandle(concurrent.futures.Future[T], Generic[T]):
+    """Cross-thread result with a separate coroutine-settlement signal.
+
+    Cancelling a concurrent future marks it done immediately, while the
+    asyncio task may still be running ``finally`` blocks. ``wait_settled``
+    distinguishes those two moments for cancellation and shutdown paths.
+    """
+
+    def __init__(self, *, name: str | None = None) -> None:
+        super().__init__()
+        self._name = name
+        self._settled: concurrent.futures.Future[None] = concurrent.futures.Future()
+        self._settle_lock = threading.Lock()
+
+    @property
+    def name(self) -> str | None:
+        return self._name
+
+    @property
+    def settled(self) -> bool:
+        return self._settled.done()
+
+    def wait_settled(self, timeout: float | None = None) -> bool:
+        """Block for task settlement; return ``False`` on timeout."""
+        try:
+            self._settled.result(timeout)
+        except concurrent.futures.TimeoutError:
+            return False
+        return True
+
+    async def wait_settled_async(self) -> None:
+        """Wait for task settlement without blocking the caller's loop."""
+        # ``wrap_future`` propagates cancellation back to the concurrent
+        # future.  Settlement is a shared, one-way runtime signal rather than
+        # work owned by any individual waiter, so a cancelled waiter must not
+        # cancel or falsely complete it for everyone else.
+        await asyncio.shield(asyncio.wrap_future(self._settled))
+
+    def _mark_settled(self) -> None:
+        # The lock makes the check-and-set atomic during forced shutdown.
+        with self._settle_lock:
+            if not self._settled.done():
+                self._settled.set_result(None)
+
+
+class AsyncRuntime:
+    """Own a persistent asyncio loop and its task lifecycle.
+
+    Instances start lazily on first submission or eagerly through
+    :meth:`start`. A closed instance is permanently sealed; create a new
+    instance for a new application lifetime.
+    """
+
+    def __init__(
+        self,
+        *,
+        thread_name: str = "evosci-async-runtime",
+        start_timeout: float = 5.0,
+        cancellation_timeout: float = 2.0,
+    ) -> None:
+        if start_timeout <= 0:
+            raise ValueError("start_timeout must be greater than zero")
+        if cancellation_timeout < 0:
+            raise ValueError("cancellation_timeout must not be negative")
+
+        self._thread_name = thread_name
+        self._start_timeout = start_timeout
+        self._cancellation_timeout = cancellation_timeout
+
+        self._lock = threading.RLock()
+        self._ready = threading.Event()
+        self._stopped = threading.Event()
+        self._closed = False
+        self._failure: BaseException | None = None
+        self._loop: asyncio.AbstractEventLoop | None = None
+        self._thread: threading.Thread | None = None
+
+        # Runtime-loop-only mapping. Strong references prevent pending tasks
+        # and their handles from being garbage-collected.
+        self._loop_tasks: dict[asyncio.Task[Any], RuntimeHandle[Any]] = {}
+
+    def __enter__(self) -> AsyncRuntime:
+        self.start()
+        return self
+
+    def __exit__(self, *exc_info: object) -> None:
+        self.close()
+
+    @property
+    def is_running(self) -> bool:
+        with self._lock:
+            thread = self._thread
+            return (
+                not self._closed
+                and thread is not None
+                and thread.is_alive()
+                and self._ready.is_set()
+                and not self._stopped.is_set()
+            )
+
+    def start(self) -> None:
+        """Start the loop thread idempotently and wait until it serves work."""
+        with self._lock:
+            self._ensure_started_locked()
+
+    def _ensure_started_locked(self) -> asyncio.AbstractEventLoop:
+        if self._closed:
+            raise AsyncRuntimeClosedError(f"{self._thread_name} is closed")
+
+        thread = self._thread
+        if thread is not None:
+            if thread.is_alive() and self._ready.is_set() and self._loop is not None:
+                return self._loop
+            error = AsyncRuntimeError(f"{self._thread_name} stopped unexpectedly")
+            if self._failure is not None:
+                raise error from self._failure
+            raise error
+
+        thread = threading.Thread(
+            target=self._thread_main,
+            name=self._thread_name,
+            daemon=True,
+        )
+        self._thread = thread
+        try:
+            thread.start()
+        except BaseException:
+            self._thread = None
+            raise
+
+        if not self._ready.wait(self._start_timeout):
+            # A late-created loop observes this seal in _thread_main and exits
+            # instead of becoming an orphan after its owner saw startup fail.
+            self._closed = True
+            raise TimeoutError(
+                f"{self._thread_name} did not start within {self._start_timeout:.1f}s"
+            )
+        if self._failure is not None:
+            raise AsyncRuntimeError(f"{self._thread_name} failed to start") from (
+                self._failure
+            )
+        if self._loop is None or not thread.is_alive():
+            raise AsyncRuntimeError(f"{self._thread_name} failed to start")
+        return self._loop
+
+    def _thread_main(self) -> None:
+        loop: asyncio.AbstractEventLoop | None = None
+        try:
+            ensure_proactor_event_loop_policy()
+            loop = asyncio.new_event_loop()
+            self._loop = loop
+            asyncio.set_event_loop(loop)
+
+            # A startup timeout may let close() seal the instance before loop
+            # creation finishes. Do not leave a late-starting daemon behind.
+            if self._closed:
+                self._ready.set()
+                return
+
+            # The callback proves run_forever is serving work before start()
+            # returns; merely allocating a loop is not sufficient.
+            loop.call_soon(self._ready.set)
+            loop.run_forever()
+        except BaseException as exc:
+            self._failure = exc
+            self._ready.set()
+            logger.exception("%s loop failed", self._thread_name)
+        finally:
+            if loop is not None:
+                self._settle_abandoned_tasks()
+                loop.close()
+                asyncio.set_event_loop(None)
+            self._loop = None
+            self._stopped.set()
+
+    def _settle_abandoned_tasks(self) -> None:
+        """Resolve handles when a stopped loop cannot unwind further."""
+        for task, handle in list(self._loop_tasks.items()):
+            if not task.done():
+                task.cancel()
+            if not handle.done():
+                handle.cancel()
+            handle._mark_settled()
+        self._loop_tasks.clear()
+
+    def submit(self, factory: AsyncFactory[T]) -> RuntimeHandle[T]:
+        """Schedule a factory on the owned loop and return its handle.
+
+        Submission is atomic with :meth:`close`: work is either queued before
+        shutdown is sealed or rejected.
+        """
+        return self._submit(factory, name=None)
+
+    def _submit(
+        self,
+        factory: AsyncFactory[T],
+        *,
+        name: str | None,
+    ) -> RuntimeHandle[T]:
+        if not callable(factory):
+            raise TypeError("factory must be callable")
+
+        handle: RuntimeHandle[T] = RuntimeHandle(name=name)
+        context = contextvars.copy_context()
+
+        def create_task() -> None:
+            if handle.cancelled():
+                handle._mark_settled()
+                return
+
+            async def invoke_factory() -> T:
+                return await factory()
+
+            try:
+                task = asyncio.create_task(invoke_factory(), name=name)
+            except BaseException as exc:
+                self._set_handle_exception(handle, exc)
+                handle._mark_settled()
+                return
+
+            self._loop_tasks[task] = handle
+
+            def cancel_task(done: concurrent.futures.Future[T]) -> None:
+                if not done.cancelled() or task.done():
+                    return
+                try:
+                    task.get_loop().call_soon_threadsafe(task.cancel)
+                except RuntimeError:
+                    handle._mark_settled()
+
+            handle.add_done_callback(cancel_task)
+            task.add_done_callback(self._copy_task_result)
+            if handle.cancelled() and not task.done():
+                task.cancel()
+
+        try:
+            with self._lock:
+                loop = self._ensure_started_locked()
+                self._enqueue_locked(loop, create_task, context)
+        except BaseException:
+            handle._mark_settled()
+            raise
+        return handle
+
+    def _enqueue_locked(
+        self,
+        loop: asyncio.AbstractEventLoop,
+        callback: Callable[[], None],
+        context: contextvars.Context,
+    ) -> None:
+        """Enqueue under the lifecycle lock; isolated for race testing."""
+        try:
+            loop.call_soon_threadsafe(callback, context=context)
+        except RuntimeError as exc:
+            raise AsyncRuntimeError(
+                f"{self._thread_name} stopped while submitting work"
+            ) from exc
+
+    def _copy_task_result(self, task: asyncio.Task[Any]) -> None:
+        handle = self._loop_tasks.pop(task)
+        try:
+            result = task.result()
+        except asyncio.CancelledError:
+            handle.cancel()
+        except BaseException as exc:
+            self._set_handle_exception(handle, exc)
+        else:
+            self._set_handle_result(handle, result)
+        finally:
+            handle._mark_settled()
+
+    @staticmethod
+    def _set_handle_result(handle: RuntimeHandle[Any], result: Any) -> None:
+        try:
+            handle.set_result(result)
+        except concurrent.futures.InvalidStateError:
+            pass  # External cancellation won; discard the completed result.
+
+    @staticmethod
+    def _set_handle_exception(handle: RuntimeHandle[Any], exc: BaseException) -> None:
+        try:
+            handle.set_exception(exc)
+        except concurrent.futures.InvalidStateError:
+            pass
+
+    def run_sync(
+        self,
+        factory: AsyncFactory[T],
+        *,
+        timeout: float | None = None,
+        on_submitted: Callable[[RuntimeHandle[T]], None] | None = None,
+    ) -> T:
+        """Run async work from sync code, blocking for its result.
+
+        Any thread already running an event loop must use :meth:`run_async`;
+        blocking it would freeze that frontend even if it is not the owned loop.
+        ``on_submitted`` may retain the handle for cross-thread cancellation;
+        it runs after submission and before this method starts blocking.
+        """
+        try:
+            asyncio.get_running_loop()
+        except RuntimeError:
+            pass
+        else:
+            raise AsyncRuntimeError(
+                "run_sync() cannot block a running event loop; use "
+                "`await runtime.run_async(...)` instead"
+            )
+
+        handle = self.submit(factory)
+        if on_submitted is not None:
+            try:
+                on_submitted(handle)
+            except BaseException:
+                handle.cancel()
+                self._wait_for_cancellation(handle)
+                raise
+        try:
+            return handle.result(timeout)
+        except BaseException:
+            if not handle.done():
+                handle.cancel()
+                self._wait_for_cancellation(handle)
+            elif handle.cancelled():
+                self._wait_for_cancellation(handle)
+            raise
+
+    async def run_async(self, factory: AsyncFactory[T]) -> T:
+        """Await owned work without blocking the caller's event loop.
+
+        Current UI adapters cross through ``to_thread`` and :meth:`run_sync`.
+        This public bridge is retained for embedders and future async surfaces
+        whose event loop must remain responsive while the owned loop does work.
+        """
+        caller_loop = asyncio.get_running_loop()
+        with self._lock:
+            runtime_loop = self._loop
+        if caller_loop is runtime_loop:
+            raise AsyncRuntimeError(
+                "run_async() called from the owned loop; await directly instead"
+            )
+
+        handle = self.submit(factory)
+        try:
+            return await asyncio.wrap_future(handle)
+        except asyncio.CancelledError:
+            handle.cancel()
+            try:
+                await asyncio.wait_for(
+                    asyncio.shield(handle.wait_settled_async()),
+                    timeout=self._cancellation_timeout,
+                )
+            except TimeoutError:
+                logger.warning(
+                    "%s task did not settle within %.1fs after cancellation",
+                    self._thread_name,
+                    self._cancellation_timeout,
+                )
+            raise
+
+    def spawn(
+        self,
+        factory: AsyncFactory[Any],
+        *,
+        name: str,
+    ) -> RuntimeHandle[Any]:
+        """Start durable work, retaining it and logging unhandled failures.
+
+        This public primitive is reserved for runtime-owned background
+        services; scoped request work should continue to use :meth:`submit`.
+        """
+        handle = self._submit(factory, name=name)
+        handle.add_done_callback(self._on_background_done)
+        return handle
+
+    @staticmethod
+    def _on_background_done(handle: concurrent.futures.Future[Any]) -> None:
+        if handle.cancelled():
+            return
+        try:
+            exc = handle.exception()
+        except concurrent.futures.CancelledError:
+            return
+        if exc is not None:
+            name = getattr(handle, "name", None)
+            logger.error(
+                "unhandled exception in runtime task %r",
+                name,
+                exc_info=(type(exc), exc, exc.__traceback__),
+            )
+
+    def _wait_for_cancellation(self, handle: RuntimeHandle[Any]) -> None:
+        if not handle.wait_settled(self._cancellation_timeout):
+            logger.warning(
+                "%s task did not settle within %.1fs after cancellation",
+                self._thread_name,
+                self._cancellation_timeout,
+            )
+
+    @staticmethod
+    async def _drain() -> None:
+        current = asyncio.current_task()
+        pending = [task for task in asyncio.all_tasks() if task is not current]
+        for task in pending:
+            task.cancel()
+        if pending:
+            await asyncio.gather(*pending, return_exceptions=True)
+        loop = asyncio.get_running_loop()
+        await loop.shutdown_asyncgens()
+        # Cancelling a task awaiting ``to_thread`` / ``run_in_executor`` does
+        # not stop its underlying callable.  Do not report a clean runtime
+        # shutdown until the owned loop's default executor is actually idle.
+        await loop.shutdown_default_executor()
+
+    def close(self, *, timeout: float = 5.0) -> None:
+        """Seal intake, settle pending tasks, stop the loop, and join its thread.
+
+        Shutdown is bounded by ``timeout``. Executor work cannot be preempted by
+        asyncio cancellation; if it outlives the deadline this call raises
+        :class:`TimeoutError` and the sealed runtime finishes shutting down in
+        the background. A later ``close()`` waits for that shutdown and only
+        succeeds after the executor is idle and the loop thread has stopped.
+        """
+        if timeout < 0:
+            raise ValueError("timeout must not be negative")
+        deadline = time.monotonic() + timeout
+
+        with self._lock:
+            thread = self._thread
+            if thread is threading.current_thread():
+                raise AsyncRuntimeError(
+                    "close() cannot join the owned loop thread; close the "
+                    "runtime from its application owner"
+                )
+
+            if self._closed:
+                wait_for_existing_close = thread is not None and thread.is_alive()
+                drain = None
+                loop = self._loop
+            else:
+                self._closed = True
+                wait_for_existing_close = False
+                loop = self._loop
+                if thread is None:
+                    self._stopped.set()
+                    return
+                if loop is None:
+                    # start() timed out while the runtime thread was still
+                    # creating its loop. _thread_main observes _closed and
+                    # exits as soon as creation finishes.
+                    drain = None
+                else:
+                    # The lifecycle lock orders this after every accepted
+                    # task-creation callback queued by submit().
+                    try:
+                        drain = asyncio.run_coroutine_threadsafe(self._drain(), loop)
+                    except RuntimeError:
+                        drain = None
+
+        if wait_for_existing_close:
+            if not self._stopped.wait(max(0.0, deadline - time.monotonic())):
+                raise TimeoutError(
+                    f"timed out waiting for {self._thread_name} shutdown"
+                )
+            return
+        if thread is None:
+            return
+
+        if loop is None:
+            thread.join(max(0.0, deadline - time.monotonic()))
+            if thread.is_alive():
+                raise TimeoutError(
+                    f"{self._thread_name} did not stop within {timeout:.1f}s"
+                )
+            return
+
+        drain_timed_out = False
+        drain_error: BaseException | None = None
+        if drain is not None:
+            try:
+                drain.result(max(0.0, deadline - time.monotonic()))
+            except concurrent.futures.TimeoutError:
+                drain_timed_out = True
+
+                def stop_after_drain(
+                    _done: concurrent.futures.Future[None],
+                ) -> None:
+                    try:
+                        loop.call_soon_threadsafe(loop.stop)
+                    except RuntimeError:
+                        pass
+
+                # Keep the loop alive while executor work finishes. This
+                # callback completes the already-sealed shutdown afterward.
+                drain.add_done_callback(stop_after_drain)
+            except BaseException as exc:
+                drain_error = exc
+
+        if drain_timed_out:
+            raise TimeoutError(
+                f"{self._thread_name} tasks did not settle within {timeout:.1f}s"
+            )
+
+        try:
+            loop.call_soon_threadsafe(loop.stop)
+        except RuntimeError:
+            pass
+        thread.join(max(0.0, deadline - time.monotonic()))
+
+        if thread.is_alive():
+            raise TimeoutError(
+                f"{self._thread_name} did not stop within {timeout:.1f}s"
+            )
+        if drain_error is not None:
+            raise drain_error
+
+
+__all__ = [
+    "AsyncFactory",
+    "AsyncRuntime",
+    "AsyncRuntimeClosedError",
+    "AsyncRuntimeError",
+    "RuntimeHandle",
+]
diff --git a/EvoScientist/stream/display.py b/EvoScientist/stream/display.py
--- a/EvoScientist/stream/display.py
+++ b/EvoScientist/stream/display.py
@@ -6,13 +6,15 @@
 """
 
 import asyncio
+import concurrent.futures
 import inspect
 import logging
 import os
 import re
 import threading
-from collections.abc import Callable
-from typing import TYPE_CHECKING, Any
+from collections.abc import AsyncIterator, Callable, Iterator
+from contextlib import contextmanager
+from typing import TYPE_CHECKING, Any, TypeVar
 
 from rich.console import Group  # type: ignore[import-untyped]
 from rich.live import Live  # type: ignore[import-untyped]
@@ -21,8 +23,10 @@
 from rich.spinner import Spinner  # type: ignore[import-untyped]
 from rich.text import Text  # type: ignore[import-untyped]
 
+from ..cancellation import bind_cancel_event
 from ..gateway import GraphGateway, GraphRunInput, GraphTarget, RunRequest
 from ..paths import resolve_virtual_path
+from ..runtime import AsyncRuntime, RuntimeHandle
 from .console import console
 from .diff_format import build_edit_diff
 from .formatter import ToolResultFormatter
@@ -49,6 +53,24 @@
 
 # Media file extensions that should trigger on_file_write callback
 _MEDIA_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".pdf"}
+_T = TypeVar("_T")
+_QuestionRunner = Callable[[Any], Any]
+
+
+class _StreamPromptCancelled(Exception):
+    """Internal control flow for an owned terminal prompt cancellation."""
+
+
+def _update_final_live_frame(
+    live: Any,
+    final_display: Any,
+    stream_handle: RuntimeHandle[Any] | None,
+) -> None:
+    """Render the final frame unless this owned stream was cancelled."""
+    if stream_handle is not None and stream_handle.cancelled():
+        return
+    live.update(final_display)
+    live.refresh()
 
 
 def _graph_target_for_local_agent(
@@ -119,10 +141,18 @@ def _response_markdown_for_display(
 # per-message scope so `/stop` only affects that message's run; scope-less
 # callers retain the legacy process-wide default event.
 _DEFAULT_STREAM_CANCEL_SCOPE = "__default__"
-_stream_cancel_lock = threading.Lock()
+# Serve signal handlers may request cancellation while the main thread is in a
+# scoped cancellation lookup.  Re-entrancy prevents the Python signal callback
+# from deadlocking if it interrupts one of these short registry sections.
+_stream_cancel_lock = threading.RLock()
 _stream_cancel_events: dict[str, threading.Event] = {
     _DEFAULT_STREAM_CANCEL_SCOPE: threading.Event()
 }
+# The flag remains useful for cancellation requested before a stream starts and
+# at synchronous HITL boundaries.  Active Rich streams additionally register
+# their owned-runtime handle so a request can interrupt a blocked ``__anext__``
+# immediately instead of waiting for the model to emit another event.
+_stream_cancel_handles: dict[str, set[RuntimeHandle[Any]]] = {}
 # Backward-compat alias used by older tests and direct imports.
 _stream_cancel_event = _stream_cancel_events[_DEFAULT_STREAM_CANCEL_SCOPE]
 
@@ -146,13 +176,83 @@ def _get_stream_cancel_event(
 
 
 def request_stream_cancel(cancel_scope: str | None = None) -> bool:
-    """Signal a specific in-flight stream to terminate."""
-    event = _get_stream_cancel_event(cancel_scope, create=True)
-    already_requested = event.is_set()
-    event.set()
+    """Signal a stream and directly cancel any active owned coroutine."""
+    scope_key = _stream_cancel_scope_key(cancel_scope)
+    with _stream_cancel_lock:
+        event = _stream_cancel_events.get(scope_key)
+        if event is None:
+            event = threading.Event()
+            _stream_cancel_events[scope_key] = event
+        already_requested = event.is_set()
+        event.set()
+        handles = tuple(_stream_cancel_handles.get(scope_key, ()))
+
+    # Future.cancel() is thread-safe.  Do it outside the registry lock because
+    # cancellation callbacks may settle quickly and unregister the handle.
+    for handle in handles:
+        handle.cancel()
+    # Sync tools may remain active in an executor after their awaiting graph
+    # task is cancelled, so stop their owned subprocesses explicitly.
+    from ..backends import cancel_active_shell_processes
+
+    cancel_active_shell_processes(event)
     return not already_requested
 
 
+def _register_stream_cancel_handle(
+    cancel_scope: str | None,
+    handle: RuntimeHandle[Any],
+) -> None:
+    """Register an active owned task, honoring a pre-start stop request."""
+    scope_key = _stream_cancel_scope_key(cancel_scope)
+    with _stream_cancel_lock:
+        handles = _stream_cancel_handles.setdefault(scope_key, set())
+        handles.add(handle)
+        event = _stream_cancel_events.get(scope_key)
+        cancel_now = event is not None and event.is_set()
+    if cancel_now:
+        handle.cancel()
+
+
+def _unregister_stream_cancel_handle(
+    cancel_scope: str | None,
+    handle: RuntimeHandle[Any],
+) -> None:
+    scope_key = _stream_cancel_scope_key(cancel_scope)
+    with _stream_cancel_lock:
+        handles = _stream_cancel_handles.get(scope_key)
+        if handles is None:
+            return
+        handles.discard(handle)
+        if not handles:
+            _stream_cancel_handles.pop(scope_key, None)
+
+
+def _run_owned_questionary_prompt(
+    question: Any,
+    *,
+    runtime: AsyncRuntime,
+    cancel_scope: str | None,
+) -> Any:
+    """Run a terminal prompt as owned async work so stop can cancel it."""
+    prompt_handle: RuntimeHandle[Any] | None = None
+
+    def _register(handle: RuntimeHandle[Any]) -> None:
+        nonlocal prompt_handle
+        prompt_handle = handle
+        _register_stream_cancel_handle(cancel_scope, handle)
+
+    try:
+        return runtime.run_sync(question.ask_async, on_submitted=_register)
+    except concurrent.futures.CancelledError as exc:
+        if is_stream_cancel_requested(cancel_scope):
+            raise _StreamPromptCancelled from exc
+        raise
+    finally:
+        if prompt_handle is not None:
+            _unregister_stream_cancel_handle(cancel_scope, prompt_handle)
+
+
 def is_stream_cancel_requested(cancel_scope: str | None = None) -> bool:
     event = _get_stream_cancel_event(cancel_scope)
     return event.is_set() if event is not None else False
@@ -165,6 +265,40 @@ def clear_stream_cancel(cancel_scope: str | None = None) -> None:
         event.clear()
 
 
+@contextmanager
+def bind_stream_cancel(cancel_scope: str | None = None) -> Iterator[None]:
+    """Bind a stream's stop event for cancellation-aware blocking tools."""
+    event = _get_stream_cancel_event(cancel_scope, create=True)
+    assert event is not None
+    with bind_cancel_event(event):
+        yield
+
+
+async def iter_with_stream_cancel(
+    events: AsyncIterator[_T],
+    cancel_scope: str | None = None,
+) -> AsyncIterator[_T]:
+    """Iterate graph events with the matching blocking-tool cancel context."""
+    iterator = aiter(events)
+    try:
+        while True:
+            try:
+                # ContextVar tokens cannot safely straddle ``yield``: async
+                # generator finalization may run in a different task/context.
+                # The cancellation binding is only needed while requesting the
+                # next graph event, which includes any nested tool execution.
+                with bind_stream_cancel(cancel_scope):
+                    event = await anext(iterator)
+            except StopAsyncIteration:
+                return
+            yield event
+    finally:
+        aclose = getattr(iterator, "aclose", None)
+        if aclose is not None:
+            with bind_stream_cancel(cancel_scope):
+                await aclose()
+
+
 def discard_stream_cancel(cancel_scope: str | None = None) -> None:
     """Drop a scope's stop signal after the owning request is fully done."""
     scope_key = _stream_cancel_scope_key(cancel_scope)
@@ -1026,6 +1160,8 @@ def _matches_shell_allow_list(command: str, allow_list: list[str]) -> bool:
 def _resolve_hitl_approval(
     interrupt_data: dict,
     prompt_fn: Callable[[list], list[dict] | None] | None = None,
+    *,
+    question_runner: _QuestionRunner | None = None,
 ) -> list[dict] | None:
     """Resolve HITL approval for an interrupt.
 
@@ -1082,10 +1218,17 @@ def _resolve_hitl_approval(
     if prompt_fn is not None:
         return prompt_fn(action_requests)
 
-    return _prompt_hitl_approval(action_requests)
+    return _prompt_hitl_approval(
+        action_requests,
+        question_runner=question_runner,
+    )
 
 
-def _prompt_hitl_approval(action_requests: list) -> list[dict] | None:
+def _prompt_hitl_approval(
+    action_requests: list,
+    *,
+    question_runner: _QuestionRunner | None = None,
+) -> list[dict] | None:
     """Display approval prompt and get user decision.
 
     Returns list of decisions if approved, None if rejected.
@@ -1130,11 +1273,14 @@ def _prompt_hitl_approval(action_requests: list) -> list[dict] | None:
     auto_label = "Approve all (session)"
 
     try:
-        selected = questionary.select(
+        question = questionary.select(
             "Approval required",
             choices=[approve_label, reject_label, auto_label],
             style=_PICKER_STYLE,
-        ).ask()
+        )
+        selected = (
+            question_runner(question) if question_runner is not None else question.ask()
+        )
     except (EOFError, KeyboardInterrupt):
         console.print("[dim]  Rejected.[/dim]")
         return None
@@ -1152,37 +1298,11 @@ def _prompt_hitl_approval(action_requests: list) -> list[dict] | None:
     return None
 
 
-# ---------------------------------------------------------------------------
-# Async-to-sync bridge
-# ---------------------------------------------------------------------------
-
-
-def _create_event_loop() -> asyncio.AbstractEventLoop:
-    """Create and set the event loop for asyncio.
-
-    Returns:
-        The created event loop.
-    """
-    loop = asyncio.new_event_loop()
-    asyncio.set_event_loop(loop)
-    return loop
-
-
-def _get_event_loop() -> asyncio.AbstractEventLoop:
-    """Get the event loop for asyncio.
-
-    If no event loop is set, a new one is created.
-
-    Returns:
-        The current event loop.
-    """
-    loop = asyncio.get_event_loop()
-    if loop.is_closed():
-        loop = _create_event_loop()
-    return loop
-
-
-def _resolve_ask_user_prompt(ask_user_data: dict) -> dict:
+def _resolve_ask_user_prompt(
+    ask_user_data: dict,
+    *,
+    question_runner: _QuestionRunner | None = None,
+) -> dict:
     """Interactive console Q&A for ask_user events.
 
     Presents multiple-choice questions with arrow-key navigation via
@@ -1235,11 +1355,16 @@ def _validate(v: str) -> bool | str:
                 other_label = "Other (type your answer)"
                 choice_labels.append(other_label)
 
-                selected = questionary.select(
+                question = questionary.select(
                     prompt_text,
                     choices=choice_labels,
                     style=_PICKER_STYLE,
-                ).ask()
+                )
+                selected = (
+                    question_runner(question)
+                    if question_runner is not None
+                    else question.ask()
+                )
 
                 if selected is None:  # Ctrl+C
                     raise KeyboardInterrupt
@@ -1250,22 +1375,32 @@ def _validate(v: str) -> bool | str:
                     continue
 
                 if selected == other_label:
-                    selected = questionary.text(
+                    question = questionary.text(
                         "Your answer:",
                         validate=_make_validator(required),
                         style=_PICKER_STYLE,
-                    ).ask()
+                    )
+                    selected = (
+                        question_runner(question)
+                        if question_runner is not None
+                        else question.ask()
+                    )
                     if selected is None:
                         raise KeyboardInterrupt
 
                 answers.append(selected)
 
             else:
-                answer = questionary.text(
+                question = questionary.text(
                     prompt_text,
                     validate=_make_validator(required),
                     style=_PICKER_STYLE,
-                ).ask()
+                )
+                answer = (
+                    question_runner(question)
+                    if question_runner is not None
+                    else question.ask()
+                )
 
                 if answer is None:  # Ctrl+C
                     raise KeyboardInterrupt
@@ -1298,6 +1433,7 @@ def _run_streaming(
     cancel_scope: str | None = None,
     *,
     gateway: GraphGateway,
+    runtime: AsyncRuntime | None = None,
     _state: StreamState | None = None,
     _hitl_depth: int = 0,
     _media_sent: set[str] | None = None,
@@ -1329,6 +1465,31 @@ def _run_streaming(
     Returns:
         The final response text.
     """
+    if runtime is None:
+        with AsyncRuntime(thread_name="evosci-stream-runtime") as owned_runtime:
+            return _run_streaming(
+                agent=agent,
+                message=message,
+                thread_id=thread_id,
+                show_thinking=show_thinking,
+                interactive=interactive,
+                on_thinking=on_thinking,
+                on_todo=on_todo,
+                on_file_write=on_file_write,
+                on_stream_event=on_stream_event,
+                status_footer_builder=status_footer_builder,
+                metadata=metadata,
+                hitl_prompt_fn=hitl_prompt_fn,
+                ask_user_prompt_fn=ask_user_prompt_fn,
+                cancel_scope=cancel_scope,
+                gateway=gateway,
+                runtime=owned_runtime,
+                _state=_state,
+                _hitl_depth=_hitl_depth,
+                _media_sent=_media_sent,
+                _sent_thinking_text=_sent_thinking_text,
+            )
+
     # Scope-less callers keep the legacy single-event semantics. Scoped
     # callers use unique per-request scopes, so pre-start `/stop` must
     # remain armed until this run consumes it.
@@ -1348,108 +1509,114 @@ def _stopped_response() -> str:
 
     async def _consume() -> None:
         nonlocal _sent_thinking_text, _todo_sent
-        async for event in gateway.stream_events(
+        event_stream = gateway.stream_events(
             RunRequest(
                 message=message,
                 thread_id=thread_id,
                 metadata=metadata,
                 target=_graph_target_for_local_agent(agent, metadata),
             )
-        ):
-            if is_stream_cancel_requested(cancel_scope):
-                _stopped_response()
-                return
-            event_type = state.handle_event(event)
-
-            # Relay thinking to channel when transitioning away from
-            # thinking phase.  Uses content comparison so that replayed
-            # thinking after resume is skipped, but genuinely new
-            # thinking is still delivered.
-            if (
-                on_thinking
-                and event_type != "thinking"
-                and state.thinking_text
-                and len(state.thinking_text) >= _MIN_THINKING_LEN
-            ):
-                current = state.thinking_text.rstrip()
-                if current != _sent_thinking_text:
-                    on_thinking(current)
-                    _sent_thinking_text = current
-
-            # Send todo list to channel on first write_todos tool_call
-            if (
-                on_todo
-                and not _todo_sent
-                and event_type == "tool_call"
-                and event.get("name") == "write_todos"
-                and state.todo_items
-            ):
-                on_todo(state.todo_items)
-                _todo_sent = True
-
-            # Send media file to channel when write_file succeeds
-            if (
-                on_file_write
-                and event_type == "tool_result"
-                and event.get("name") == "write_file"
-                and event.get("success")
-            ):
-                wf_path = ""
-                for tc in reversed(state.tool_calls):
-                    if tc.get("name") == "write_file":
-                        p = tc.get("args", {}).get("path", "")
-                        if p and p not in _media_sent:
-                            wf_path = p
-                            break
-                if wf_path:
-                    ext = os.path.splitext(wf_path)[1].lower()
-                    if ext in _MEDIA_EXTENSIONS:
-                        real_path = str(resolve_virtual_path(wf_path))
-                        if os.path.isfile(real_path):
-                            _media_sent.add(wf_path)
-                            on_file_write(real_path)
-
-            # Send media file to channel when read_file returns an image
-            if (
-                on_file_write
-                and event_type == "tool_result"
-                and event.get("name") == "read_file"
-                and event.get("success")
-            ):
-                rf_path = ""
-                for tc in reversed(state.tool_calls):
-                    if tc.get("name") == "read_file":
-                        p = tc.get("args", {}).get("file_path", "") or tc.get(
-                            "args", {}
-                        ).get("path", "")
-                        if p and p not in _media_sent:
-                            rf_path = p
-                            break
-                if rf_path:
-                    ext = os.path.splitext(rf_path)[1].lower()
-                    if ext in _MEDIA_EXTENSIONS:
-                        real_path = rf_path
-                        if not os.path.isfile(real_path):
-                            real_path = str(resolve_virtual_path(rf_path))
-                        if os.path.isfile(real_path):
-                            _media_sent.add(rf_path)
-                            on_file_write(real_path)
-
-            if on_stream_event is not None:
-                callback_result = on_stream_event(event_type, state)
-                if inspect.isawaitable(callback_result):
-                    await callback_result
-
-            live.update(
-                create_streaming_display(
-                    **state.get_display_args(),
-                    show_thinking=show_thinking,
-                    response_markdown=state.get_response_markdown(),
-                    status_footer=(
-                        status_footer_builder() if status_footer_builder else None
-                    ),
+        )
+        try:
+            async for event in event_stream:
+                if is_stream_cancel_requested(cancel_scope):
+                    _stopped_response()
+                    return
+                event_type = state.handle_event(event)
+
+                # Relay thinking to channel when transitioning away from
+                # thinking phase.  Uses content comparison so that replayed
+                # thinking after resume is skipped, but genuinely new
+                # thinking is still delivered.
+                if (
+                    on_thinking
+                    and event_type != "thinking"
+                    and state.thinking_text
+                    and len(state.thinking_text) >= _MIN_THINKING_LEN
+                ):
+                    current = state.thinking_text.rstrip()
+                    if current != _sent_thinking_text:
+                        on_thinking(current)
+                        _sent_thinking_text = current
+
+                # Send todo list to channel on first write_todos tool_call
+                if (
+                    on_todo
+                    and not _todo_sent
+                    and event_type == "tool_call"
+                    and event.get("name") == "write_todos"
+                    and state.todo_items
+                ):
+                    on_todo(state.todo_items)
+                    _todo_sent = True
+
+                # Send media file to channel when write_file succeeds
+                if (
+                    on_file_write
+                    and event_type == "tool_result"
+                    and event.get("name") == "write_file"
+                    and event.get("success")
+                ):
+                    wf_path = ""
+                    for tc in reversed(state.tool_calls):
+                        if tc.get("name") == "write_file":
+                            p = tc.get("args", {}).get("path", "")
+                            if p and p not in _media_sent:
+                                wf_path = p
+                                break
+                    if wf_path:
+                        ext = os.path.splitext(wf_path)[1].lower()
+                        if ext in _MEDIA_EXTENSIONS:
+                            real_path = str(resolve_virtual_path(wf_path))
+                            if os.path.isfile(real_path):
+                                _media_sent.add(wf_path)
+                                on_file_write(real_path)
+
+                # Send media file to channel when read_file returns an image
+                if (
+                    on_file_write
+                    and event_type == "tool_result"
+                    and event.get("name") == "read_file"
+                    and event.get("success")
+                ):
+                    rf_path = ""
+                    for tc in reversed(state.tool_calls):
+                        if tc.get("name") == "read_file":
+                            p = tc.get("args", {}).get("file_path", "") or tc.get(
+                                "args", {}
+                            ).get("path", "")
+                            if p and p not in _media_sent:
+                                rf_path = p
+                                break
+                    if rf_path:
+                        ext = os.path.splitext(rf_path)[1].lower()
+                        if ext in _MEDIA_EXTENSIONS:
+                            real_path = rf_path
+                            if not os.path.isfile(real_path):
+                                real_path = str(resolve_virtual_path(rf_path))
+                            if os.path.isfile(real_path):
+                                _media_sent.add(rf_path)
+                                on_file_write(real_path)
+
+                if on_stream_event is not None:
+                    callback_result = on_stream_event(event_type, state)
+                    if inspect.isawaitable(callback_result):
+                        await callback_result
+
+                live.update(
+                    create_streaming_display(
+                        **state.get_display_args(),
+                        show_thinking=show_thinking,
+                        response_markdown=state.get_response_markdown(),
+                        status_footer=(
+                            status_footer_builder() if status_footer_builder else None
+                        ),
+                    )
                 )
-            )
+        finally:
+            aclose = getattr(event_stream, "aclose", None)
+            if aclose is not None:
+                await aclose()
 
     try:
         if is_stream_cancel_requested(cancel_scope):
@@ -1469,32 +1636,6 @@ async def _consume() -> None:
                     ),
                 )
             )
-            # Determine how to run the async streaming coroutine.
-            # - In TUI mode (Textual), there's already a running event loop;
-            #   nest_asyncio is needed to allow run_until_complete inside it.
-            # - In serve/CLI mode, the main thread has no running loop;
-            #   use a fresh event loop directly (no nest_asyncio needed or wanted,
-            #   since nest_asyncio.apply() patches globally and breaks the bus
-            #   thread's event loop Task-context detection).
-            try:
-                running_loop = asyncio.get_running_loop()
-            except RuntimeError:
-                running_loop = None
-
-            if running_loop is not None:
-                # Already inside a running loop (TUI) — must use nest_asyncio.
-                # NOTE: nest_asyncio.apply() is global and irreversible within
-                # the process; avoid mixing TUI and serve modes in one process.
-                import nest_asyncio  # type: ignore[import-untyped]
-
-                nest_asyncio.apply()
-                loop = running_loop
-            else:
-                # No running loop (serve/CLI) — create a fresh one
-                try:
-                    loop = _get_event_loop()
-                except RuntimeError:
-                    loop = _create_event_loop()
 
             async def _run_with_refresh() -> None:
                 async def _periodic_refresh() -> None:
@@ -1507,7 +1648,8 @@ async def _periodic_refresh() -> None:
 
                 refresh_task = asyncio.ensure_future(_periodic_refresh())
                 try:
-                    await _consume()
+                    with bind_stream_cancel(cancel_scope):
+                        await _consume()
                 finally:
                     refresh_task.cancel()
                     try:
@@ -1552,10 +1694,24 @@ async def _periodic_refresh() -> None:
                                 interactive, status_footer_builder
                             ),
                         )
-                    live.update(final_display)
-                    live.refresh()
+                    _update_final_live_frame(live, final_display, stream_handle)
+
+            stream_handle: RuntimeHandle[None] | None = None
 
-            loop.run_until_complete(_run_with_refresh())
+            def _register(handle: RuntimeHandle[None]) -> None:
+                nonlocal stream_handle
+                stream_handle = handle
+                _register_stream_cancel_handle(cancel_scope, handle)
+
+            try:
+                runtime.run_sync(_run_with_refresh, on_submitted=_register)
+            except concurrent.futures.CancelledError:
+                if not is_stream_cancel_requested(cancel_scope):
+                    raise
+                _stopped_response()
+            finally:
+                if stream_handle is not None:
+                    _unregister_stream_cancel_handle(cancel_scope, stream_handle)
 
         # Flush any remaining thinking that wasn't sent during streaming.
         if on_thinking and state.thinking_text:
@@ -1571,7 +1727,17 @@ async def _periodic_refresh() -> None:
             if ask_user_prompt_fn is not None:
                 result = ask_user_prompt_fn(state.pending_ask_user)
             else:
-                result = _resolve_ask_user_prompt(state.pending_ask_user)
+                try:
+                    result = _resolve_ask_user_prompt(
+                        state.pending_ask_user,
+                        question_runner=lambda question: _run_owned_questionary_prompt(
+                            question,
+                            runtime=runtime,
+                            cancel_scope=cancel_scope,
+                        ),
+                    )
+                except _StreamPromptCancelled:
+                    return _stopped_response()
             from langgraph.types import Command  # type: ignore[import-untyped]
 
             state.pending_ask_user = None
@@ -1594,6 +1760,7 @@ async def _periodic_refresh() -> None:
                 ask_user_prompt_fn=ask_user_prompt_fn,
                 cancel_scope=cancel_scope,
                 gateway=gateway,
+                runtime=runtime,
                 _state=state,
                 _hitl_depth=_hitl_depth + 1,
                 _media_sent=_media_sent,
@@ -1604,10 +1771,22 @@ async def _periodic_refresh() -> None:
         if state.pending_interrupt is not None and _hitl_depth < _MAX_HITL_ITERATIONS:
             if is_stream_cancel_requested(cancel_scope):
                 return _stopped_response()
-            decisions = _resolve_hitl_approval(
-                state.pending_interrupt,
-                prompt_fn=hitl_prompt_fn,
-            )
+            try:
+                decisions = _resolve_hitl_approval(
+                    state.pending_interrupt,
+                    prompt_fn=hitl_prompt_fn,
+                    question_runner=(
+                        None
+                        if hitl_prompt_fn is not None
+                        else lambda question: _run_owned_questionary_prompt(
+                            question,
+                            runtime=runtime,
+                            cancel_scope=cancel_scope,
+                        )
+                    ),
+                )
+            except _StreamPromptCancelled:
+                return _stopped_response()
             if is_stream_cancel_requested(cancel_scope):
                 return _stopped_response()
             if decisions is not None:
@@ -1633,6 +1812,7 @@ async def _periodic_refresh() -> None:
                     ask_user_prompt_fn=ask_user_prompt_fn,
                     cancel_scope=cancel_scope,
                     gateway=gateway,
+                    runtime=runtime,
                     _state=state,
                     _hitl_depth=_hitl_depth + 1,
                     _media_sent=_media_sent,
diff --git a/pyproject.toml b/pyproject.toml
--- a/pyproject.toml
+++ b/pyproject.toml
@@ -42,7 +42,6 @@ dependencies = [
     "filelock>=3.16",
     "lazy-loader>=0.5",
     "markdownify>=1.2",
-    "nest-asyncio>=1.6",
     "tzlocal>=5.0",
     "langchain-mcp-adapters>=0.2",
     # <8.2.7: 8.2.7 Kitty "report-all-keys" breaks CJK input on iTerm2
diff --git a/uv.lock b/uv.lock
--- a/uv.lock
+++ b/uv.lock
@@ -972,7 +972,6 @@ dependencies = [
     { name = "langgraph-sdk" },
     { name = "lazy-loader" },
     { name = "markdownify" },
-    { name = "nest-asyncio" },
     { name = "openrouter" },
     { name = "prompt-toolkit" },
     { name = "psutil" },
@@ -1083,7 +1082,6 @@ requires-dist = [
     { name = "lark-oapi", marker = "extra == 'feishu'", specifier = ">=1.4.0" },
     { name = "lazy-loader", specifier = ">=0.5" },
     { name = "markdownify", specifier = ">=1.2" },
-    { name = "nest-asyncio", specifier = ">=1.6" },
     { name = "openrouter", specifier = ">=0.10.8,<0.11.0" },
     { name = "pre-commit", marker = "extra == 'dev'", specifier = ">=3.5.0" },
     { name = "prompt-toolkit", specifier = ">=3.0" },
@@ -2694,15 +2692,6 @@ wheels = [
     { url = "https://files.pythonhosted.org/packages/81/08/7036c080d7117f28a4af526d794aab6a84463126db031b007717c1a6676e/multidict-6.7.1-py3-none-any.whl", hash = "sha256:55d97cc6dae627efa6a6e548885712d4864b81110ac76fa4e534c03819fa4a56", size = 12319, upload-time = "2026-01-26T02:46:44.004Z" },
 ]
 
-[[package]]
-name = "nest-asyncio"
-version = "1.6.0"
-source = { registry = "https://pypi.org/simple" }
-sdist = { url = "https://files.pythonhosted.org/packages/83/f8/51569ac65d696c8ecbee95938f89d4abf00f47d58d48f6fbabfe8f0baefe/nest_asyncio-1.6.0.tar.gz", hash = "sha256:6f172d5449aca15afd6c646851f4e31e02c598d553a667e38cafa997cfec55fe", size = 7418, upload-time = "2024-01-21T14:25:19.227Z" }
-wheels = [
-    { url = "https://files.pythonhosted.org/packages/a0/c4/c2971a3ba4c6103a3d10c4b0f24f461ddc027f0f09763220cf35ca1401b3/nest_asyncio-1.6.0-py3-none-any.whl", hash = "sha256:87af6efd6b5e897c81050477ef65c62e2b2f35d51703cae01aff2905b1852e1c", size = 5195, upload-time = "2024-01-21T14:25:17.223Z" },
-]
-
 [[package]]
 name = "nodeenv"
 version = "1.10.0"
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
