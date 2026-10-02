#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/ARCHITECTURE.md b/ARCHITECTURE.md
--- a/ARCHITECTURE.md
+++ b/ARCHITECTURE.md
@@ -77,11 +77,11 @@ new places to add unrelated behavior:
   server tools, provider execution, and Responses adaptation. Future changes
   should keep route handlers thin and move separable use-case logic behind small
   helpers.
-- [providers/openai_compat.py](providers/openai_compat.py) and
-  [providers/anthropic_messages.py](providers/anthropic_messages.py) still own
-  provider-specific stream parsing, request construction, and recovery event
-  construction. Shared protocol rules should continue moving toward
-  [core/](core/) when they are not provider-specific.
+- [providers/transports/](providers/transports/) owns provider transport
+  families. The OpenAI-chat and native Anthropic transport packages split thin
+  transport bases from per-request stream runners, recovery event construction,
+  and transport-specific parsing. Shared protocol rules should continue moving
+  toward [core/](core/) when they are not provider-specific.
 - [messaging/handler.py](messaging/handler.py) owns command dispatch, tree
   queueing, CLI session execution, transcript updates, and persistence
   coordination. New platform-specific behavior should stay in platform or
@@ -273,16 +273,18 @@ providers lazily, caches them, refreshes model lists, and cleans up transports.
 - `BaseProvider`: the provider interface for cleanup, model listing, preflight,
   and `stream_response()`.
 
-There are two transport families:
+There are two transport families under [providers/transports/](providers/transports/):
 
-- [providers/openai_compat.py](providers/openai_compat.py) implements
-  `OpenAIChatTransport` for providers with OpenAI-compatible
-  `/chat/completions` APIs. These providers convert Anthropic messages and tools
-  into OpenAI chat payloads, then rebuild Anthropic SSE events.
-- [providers/anthropic_messages.py](providers/anthropic_messages.py) implements
-  `AnthropicMessagesTransport` for providers with Anthropic-compatible
-  `/messages` APIs. These providers can send more of the Anthropic request shape
-  natively while still enforcing local stream and error contracts.
+- [providers/transports/openai_chat/](providers/transports/openai_chat/)
+  implements `OpenAIChatTransport` for providers with OpenAI-compatible
+  `/chat/completions` APIs. The package owns the thin transport base,
+  per-request stream runner, OpenAI tool-call assembly, and OpenAI-chat recovery
+  event construction.
+- [providers/transports/anthropic_messages/](providers/transports/anthropic_messages/)
+  implements `AnthropicMessagesTransport` for providers with
+  Anthropic-compatible `/messages` APIs. The package owns the thin transport
+  base, native stream runner, HTTP response helpers, and native recovery event
+  construction.
 
 Shared provider responsibilities include upstream rate limiting, model listing,
 safe error mapping, transport cleanup, thinking/tool handling, retry or recovery
@@ -324,7 +326,11 @@ shared layer owns early retry classification, holdback buffering, retry attempt
 counting, and common flush/discard behavior. Provider transports still own
 upstream request construction, stream semantic parsing, transport-specific state
 tracking, and the actual recovery SSE events emitted for OpenAI-chat or native
-Anthropic streams.
+Anthropic streams. Per-request stream runners in
+[providers/transports/openai_chat/](providers/transports/openai_chat/) and
+[providers/transports/anthropic_messages/](providers/transports/anthropic_messages/)
+own mutable stream state so transport base classes stay focused on provider
+hooks, client setup, and model listing.
 
 [core/openai_responses/](core/openai_responses/) owns OpenAI Responses support:
 
diff --git a/core/anthropic/native_sse_block_policy.py b/core/anthropic/native_sse_block_policy.py
--- a/core/anthropic/native_sse_block_policy.py
+++ b/core/anthropic/native_sse_block_policy.py
@@ -1,7 +1,7 @@
 """Shared native Anthropic SSE thinking policy, block remapping, and overlap repair.
 
 Used by :class:`OpenRouterProvider` and line-mode
-:class:`providers.anthropic_messages.AnthropicMessagesTransport` providers.
+:class:`providers.transports.anthropic_messages.AnthropicMessagesTransport` providers.
 """
 
 from __future__ import annotations
diff --git a/providers/anthropic_messages.py b/providers/anthropic_messages.py
deleted file mode 100644
--- a/providers/anthropic_messages.py
+++ /dev/null
@@ -1,718 +0,0 @@
-"""Shared transport for providers with native Anthropic Messages endpoints."""
-
-from __future__ import annotations
-
-import inspect
-from collections.abc import AsyncIterator, Iterator
-from typing import Any, Literal
-
-import httpx
-from loguru import logger
-
-from config.constants import (
-    ANTHROPIC_DEFAULT_MAX_OUTPUT_TOKENS,
-    NATIVE_MESSAGES_ERROR_BODY_LOG_CAP_BYTES,
-    PROVIDER_ERROR_BODY_DISPLAY_CAP_BYTES,
-)
-from core.anthropic import iter_provider_stream_error_sse_events
-from core.anthropic.emitted_sse_tracker import EmittedNativeSseTracker
-from core.anthropic.native_messages_request import (
-    build_base_native_anthropic_request_body,
-)
-from core.anthropic.native_sse_block_policy import (
-    NativeSseBlockPolicyState,
-    transform_native_sse_block_event,
-)
-from core.anthropic.stream_contracts import parse_sse_text
-from core.anthropic.stream_recovery import (
-    MIDSTREAM_RECOVERY_ATTEMPTS,
-    TruncatedProviderStreamError,
-    accept_tool_json_repair,
-    continuation_suffix,
-    is_retryable_stream_error,
-    make_native_text_recovery_body,
-    make_native_tool_repair_body,
-    parse_complete_tool_input,
-    tool_schemas_by_name,
-)
-from core.anthropic.stream_recovery_session import (
-    StreamFailureAction,
-    StreamRecoverySession,
-)
-from core.trace import provider_native_messages_body_snapshot, trace_event
-from providers.base import BaseProvider, ProviderConfig
-from providers.error_mapping import (
-    attach_provider_error_body,
-    extract_provider_error_detail,
-    map_error,
-    user_visible_message_for_mapped_provider_error,
-)
-from providers.exceptions import ModelListResponseError
-from providers.model_listing import (
-    ProviderModelInfo,
-    extract_openai_model_ids,
-    model_infos_from_ids,
-)
-from providers.rate_limit import GlobalRateLimiter
-
-StreamChunkMode = Literal["line", "event"]
-
-
-async def _maybe_await_aclose(response: Any) -> None:
-    """Call ``aclose`` on httpx-like responses; ignore non-async test doubles."""
-    close = getattr(response, "aclose", None)
-    if not callable(close):
-        return
-    result = close()
-    if inspect.isawaitable(result):
-        await result
-
-
-def _model_list_json(response: httpx.Response, *, provider_name: str) -> Any:
-    response.raise_for_status()
-    try:
-        return response.json()
-    except ValueError as exc:
-        raise ModelListResponseError(
-            f"{provider_name} model-list response is malformed: invalid JSON"
-        ) from exc
-
-
-class AnthropicMessagesTransport(BaseProvider):
-    """Base class for providers that stream from an Anthropic-compatible endpoint."""
-
-    stream_chunk_mode: StreamChunkMode = "line"
-
-    def __init__(
-        self,
-        config: ProviderConfig,
-        *,
-        provider_name: str,
-        default_base_url: str,
-    ):
-        super().__init__(config)
-        self._provider_name = provider_name
-        self._api_key = config.api_key
-        self._base_url = (config.base_url or default_base_url).rstrip("/")
-        self._global_rate_limiter = GlobalRateLimiter.get_scoped_instance(
-            provider_name.lower(),
-            rate_limit=config.rate_limit,
-            rate_window=config.rate_window,
-            max_concurrency=config.max_concurrency,
-        )
-        self._client = httpx.AsyncClient(
-            base_url=self._base_url,
-            proxy=config.proxy or None,
-            timeout=httpx.Timeout(
-                config.http_read_timeout,
-                connect=config.http_connect_timeout,
-                read=config.http_read_timeout,
-                write=config.http_write_timeout,
-            ),
-        )
-
-    async def cleanup(self) -> None:
-        """Release HTTP client resources."""
-        await self._client.aclose()
-
-    async def list_model_ids(self) -> frozenset[str]:
-        """Return model ids from an OpenAI-compatible ``/models`` endpoint."""
-        return frozenset(info.model_id for info in await self.list_model_infos())
-
-    async def list_model_infos(self) -> frozenset[ProviderModelInfo]:
-        """Return model ids plus optional metadata from a ``/models`` endpoint."""
-        response = await self._send_model_list_request()
-        try:
-            payload = _model_list_json(response, provider_name=self._provider_name)
-            return self._extract_model_infos_from_model_list_payload(payload)
-        finally:
-            await _maybe_await_aclose(response)
-
-    async def _send_model_list_request(self) -> httpx.Response:
-        """Query the provider endpoint that advertises available model ids."""
-        return await self._client.get(
-            "/models",
-            headers=self._model_list_headers(),
-        )
-
-    def _model_list_headers(self) -> dict[str, str]:
-        """Return headers for model-list requests."""
-        return {}
-
-    def _extract_model_ids_from_model_list_payload(
-        self, payload: Any
-    ) -> frozenset[str]:
-        """Parse the provider model-list response body."""
-        return extract_openai_model_ids(payload, provider_name=self._provider_name)
-
-    def _extract_model_infos_from_model_list_payload(
-        self, payload: Any
-    ) -> frozenset[ProviderModelInfo]:
-        """Parse provider model metadata; default to unknown capabilities."""
-        return model_infos_from_ids(
-            self._extract_model_ids_from_model_list_payload(payload)
-        )
-
-    def _request_headers(self) -> dict[str, str]:
-        """Return headers for the native messages request."""
-        return {"Content-Type": "application/json"}
-
-    def _build_request_body(
-        self, request: Any, thinking_enabled: bool | None = None
-    ) -> dict:
-        """Build a native Anthropic request body."""
-        thinking_enabled = self._is_thinking_enabled(request, thinking_enabled)
-        return build_base_native_anthropic_request_body(
-            request,
-            default_max_tokens=ANTHROPIC_DEFAULT_MAX_OUTPUT_TOKENS,
-            thinking_enabled=thinking_enabled,
-        )
-
-    async def _send_stream_request(self, body: dict) -> httpx.Response:
-        """Create a streaming messages response."""
-        request = self._client.build_request(
-            "POST",
-            "/messages",
-            json=body,
-            headers=self._request_headers(),
-        )
-        return await self._client.send(request, stream=True)
-
-    async def _raise_for_status(
-        self, response: httpx.Response, *, req_tag: str
-    ) -> None:
-        """Raise for non-200 responses after logging safe metadata (or capped body if opted in)."""
-        try:
-            response.raise_for_status()
-        except httpx.HTTPStatusError as error:
-            preview, truncated = await self._read_error_body_preview(
-                response, PROVIDER_ERROR_BODY_DISPLAY_CAP_BYTES
-            )
-            attach_provider_error_body(error, preview, truncated=truncated)
-            if self._config.log_api_error_tracebacks:
-                log_preview = preview[:NATIVE_MESSAGES_ERROR_BODY_LOG_CAP_BYTES]
-                log_truncated = truncated or len(preview) > len(log_preview)
-                if log_preview:
-                    text = log_preview.decode("utf-8", errors="replace")
-                    logger.error(
-                        "{}_ERROR:{} HTTP {} body_preview_bytes={} truncated={}: {}",
-                        self._provider_name,
-                        req_tag,
-                        response.status_code,
-                        len(log_preview),
-                        log_truncated,
-                        text,
-                    )
-                else:
-                    logger.error(
-                        "{}_ERROR:{} HTTP {} (empty error body)",
-                        self._provider_name,
-                        req_tag,
-                        response.status_code,
-                    )
-            else:
-                cl = response.headers.get("content-length", "").strip()
-                extra = f" content_length_declared={cl}" if cl.isdigit() else ""
-                body_extra = (
-                    " empty_error_body"
-                    if not preview
-                    else f" error_body_bytes_read={len(preview)}"
-                )
-                logger.error(
-                    "{}_ERROR:{} HTTP {}{}{}",
-                    self._provider_name,
-                    req_tag,
-                    response.status_code,
-                    extra,
-                    body_extra,
-                )
-            raise error
-
-    async def _read_error_body_preview(
-        self, response: httpx.Response, max_bytes: int
-    ) -> tuple[bytes, bool]:
-        """Read at most ``max_bytes`` from the error body for logging. Returns (preview, truncated)."""
-        if max_bytes <= 0:
-            return b"", False
-        received = 0
-        parts: list[bytes] = []
-        truncated = False
-        async for chunk in response.aiter_bytes(chunk_size=65_536):
-            if received >= max_bytes:
-                truncated = True
-                break
-            remaining = max_bytes - received
-            take = chunk if len(chunk) <= remaining else chunk[:remaining]
-            if take:
-                parts.append(take)
-            received += len(take)
-            if len(chunk) > len(take):
-                truncated = True
-                break
-            if received >= max_bytes:
-                break
-        return (b"".join(parts), truncated)
-
-    async def _iter_sse_lines(self, response: httpx.Response) -> AsyncIterator[str]:
-        """Yield raw SSE line chunks preserving local provider behavior."""
-        async for line in response.aiter_lines():
-            if line:
-                yield f"{line}\n"
-            else:
-                yield "\n"
-
-    async def _iter_sse_events(self, response: httpx.Response) -> AsyncIterator[str]:
-        """Group line-delimited SSE responses into full SSE events."""
-        event_lines: list[str] = []
-        async for line in response.aiter_lines():
-            if line:
-                event_lines.append(line)
-                continue
-            if event_lines:
-                yield "\n".join(event_lines) + "\n\n"
-                event_lines.clear()
-        if event_lines:
-            yield "\n".join(event_lines) + "\n\n"
-
-    def _new_stream_state(self, request: Any, *, thinking_enabled: bool) -> Any:
-        """Return per-stream provider state for event transformation."""
-        if self.stream_chunk_mode == "line":
-            return NativeSseBlockPolicyState()
-        return None
-
-    def _transform_stream_event(
-        self,
-        event: str,
-        state: Any,
-        *,
-        thinking_enabled: bool,
-    ) -> str | None:
-        """Transform or drop a grouped SSE event before yielding it downstream."""
-        if isinstance(state, NativeSseBlockPolicyState):
-            return transform_native_sse_block_event(
-                event, state, thinking_enabled=thinking_enabled
-            )
-        return event
-
-    def _get_error_message(self, error: Exception, request_id: str | None) -> str:
-        """Map an exception into a user-facing provider error message."""
-        mapped_error = map_error(error, rate_limiter=self._global_rate_limiter)
-        base_message = user_visible_message_for_mapped_provider_error(
-            mapped_error,
-            provider_name=self._provider_name,
-            read_timeout_s=self._config.http_read_timeout,
-            detail=extract_provider_error_detail(error),
-            request_id=request_id,
-        )
-        return base_message
-
-    async def _validated_stream_send(
-        self, body: dict, *, req_tag: str
-    ) -> httpx.Response:
-        """Send request and raise mapped HTTP errors before yielding body chunks."""
-        send_response = await self._send_stream_request(body)
-        if send_response.status_code != 200:
-            try:
-                await self._raise_for_status(send_response, req_tag=req_tag)
-            finally:
-                if not send_response.is_closed:
-                    await _maybe_await_aclose(send_response)
-        return send_response
-
-    def _emit_error_events(
-        self,
-        *,
-        request: Any,
-        input_tokens: int,
-        error_message: str,
-        sent_any_event: bool,
-    ) -> Iterator[str]:
-        """Emit the same Anthropic message lifecycle used by OpenAI-compat providers."""
-        yield from iter_provider_stream_error_sse_events(
-            request=request,
-            input_tokens=input_tokens,
-            error_message=error_message,
-            sent_any_event=sent_any_event,
-            log_raw_sse_events=self._config.log_raw_sse_events,
-        )
-
-    async def _iter_stream_chunks(
-        self,
-        response: httpx.Response,
-        *,
-        state: Any,
-        thinking_enabled: bool,
-    ) -> AsyncIterator[str]:
-        """Yield stream chunks according to the provider's observable chunk shape."""
-        if self.stream_chunk_mode == "line" and isinstance(
-            state, NativeSseBlockPolicyState
-        ):
-            async for event in self._iter_sse_events(response):
-                output_event = self._transform_stream_event(
-                    event,
-                    state,
-                    thinking_enabled=thinking_enabled,
-                )
-                if output_event is None:
-                    continue
-                for line in output_event.splitlines(keepends=True):
-                    yield line
-            return
-
-        if self.stream_chunk_mode == "line":
-            async for chunk in self._iter_sse_lines(response):
-                yield chunk
-            return
-
-        async for event in self._iter_sse_events(response):
-            output_event = self._transform_stream_event(
-                event,
-                state,
-                thinking_enabled=thinking_enabled,
-            )
-            if output_event is not None:
-                yield output_event
-
-    async def _collect_native_recovery_text(
-        self,
-        body: dict[str, Any],
-        *,
-        req_tag: str,
-        thinking_enabled: bool,
-    ) -> tuple[str, str]:
-        """Collect text/thinking from an internal native recovery request."""
-        last_error: Exception | None = None
-        for attempt in range(MIDSTREAM_RECOVERY_ATTEMPTS):
-            response: httpx.Response | None = None
-            try:
-                response = await self._global_rate_limiter.execute_with_retry(
-                    self._validated_stream_send, body, req_tag=req_tag
-                )
-                state = self._new_stream_state(None, thinking_enabled=thinking_enabled)
-                chunks = [
-                    chunk
-                    async for chunk in self._iter_stream_chunks(
-                        response,
-                        state=state,
-                        thinking_enabled=thinking_enabled,
-                    )
-                ]
-                text_parts: list[str] = []
-                thinking_parts: list[str] = []
-                for event in parse_sse_text("".join(chunks)):
-                    delta = event.data.get("delta")
-                    if not isinstance(delta, dict):
-                        continue
-                    text = delta.get("text")
-                    if isinstance(text, str):
-                        text_parts.append(text)
-                    thinking = delta.get("thinking")
-                    if isinstance(thinking, str):
-                        thinking_parts.append(thinking)
-                return "".join(text_parts), "".join(thinking_parts)
-            except Exception as error:
-                last_error = error
-                if not is_retryable_stream_error(error):
-                    raise
-                trace_event(
-                    stage="provider",
-                    event="provider.recovery.retry",
-                    source="provider",
-                    provider=self._provider_name,
-                    recovery_kind="native_text",
-                    attempt=attempt + 1,
-                    max_attempts=MIDSTREAM_RECOVERY_ATTEMPTS,
-                    exc_type=type(error).__name__,
-                )
-            finally:
-                if response is not None and not response.is_closed:
-                    await _maybe_await_aclose(response)
-        if last_error is not None:
-            raise last_error
-        return "", ""
-
-    async def _native_recovery_events(
-        self,
-        *,
-        body: dict[str, Any],
-        request: Any,
-        tracker: EmittedNativeSseTracker,
-        error: Exception,
-        request_id: str | None,
-        req_tag: str,
-        thinking_enabled: bool,
-    ) -> list[str] | None:
-        if not is_retryable_stream_error(error):
-            return None
-
-        schemas = tool_schemas_by_name(request)
-        if tracker.has_tool_block():
-            repair_events: list[str] = []
-            for index, block in enumerate(tracker.tool_blocks()):
-                if (
-                    block.tool_id
-                    and block.name
-                    and parse_complete_tool_input(block.content, block.name, schemas)
-                    is not None
-                ):
-                    continue
-                schema = schemas.get(block.name)
-                recovery_body = make_native_tool_repair_body(
-                    body,
-                    tool_name=block.name,
-                    prefix=block.content,
-                    input_schema=schema.input_schema if schema is not None else None,
-                )
-                accepted_suffix: str | None = None
-                for attempt in range(MIDSTREAM_RECOVERY_ATTEMPTS):
-                    text, _ = await self._collect_native_recovery_text(
-                        recovery_body,
-                        req_tag=req_tag,
-                        thinking_enabled=thinking_enabled,
-                    )
-                    repair = accept_tool_json_repair(
-                        block.content,
-                        text,
-                        tool_name=block.name,
-                        schemas=schemas,
-                    )
-                    if repair is not None:
-                        accepted_suffix = repair.suffix
-                        trace_event(
-                            stage="provider",
-                            event="provider.recovery.tool_repaired",
-                            source="provider",
-                            provider=self._provider_name,
-                            tool_name=block.name,
-                            attempt=attempt + 1,
-                        )
-                        break
-                if accepted_suffix is None:
-                    return None
-                repair_events.extend(
-                    tracker.append_tool_repair_suffix(index, accepted_suffix)
-                )
-
-            if not tracker.can_salvage_tool_use(schemas):
-                return None
-            events = list(repair_events)
-            events.extend(tracker.iter_success_tail("tool_use"))
-            trace_event(
-                stage="provider",
-                event="provider.recovery.tool_salvaged",
-                source="provider",
-                provider=self._provider_name,
-                request_id=request_id,
-            )
-            return events
-
-        partial_text = tracker.emitted_text()
-        partial_thinking = tracker.emitted_thinking()
-        if not partial_text and not partial_thinking:
-            return None
-        recovery_body = make_native_text_recovery_body(body, partial_text)
-        text, thinking = await self._collect_native_recovery_text(
-            recovery_body,
-            req_tag=req_tag,
-            thinking_enabled=thinking_enabled,
-        )
-        text_suffix = continuation_suffix(partial_text, text)
-        thinking_suffix = continuation_suffix(partial_thinking, thinking)
-        events: list[str] = []
-        if thinking_suffix:
-            events.extend(tracker.append_thinking_suffix(thinking_suffix))
-        if text_suffix:
-            events.extend(tracker.append_text_suffix(text_suffix))
-        if not events:
-            return None
-        events.extend(tracker.iter_success_tail("end_turn"))
-        trace_event(
-            stage="provider",
-            event="provider.recovery.continued",
-            source="provider",
-            provider=self._provider_name,
-            request_id=request_id,
-        )
-        return events
-
-    async def stream_response(
-        self,
-        request: Any,
-        input_tokens: int = 0,
-        *,
-        request_id: str | None = None,
-        thinking_enabled: bool | None = None,
-    ) -> AsyncIterator[str]:
-        """Stream response via a native Anthropic-compatible messages endpoint."""
-        tag = self._provider_name
-        req_tag = f" request_id={request_id}" if request_id else ""
-        body = self._build_request_body(request, thinking_enabled=thinking_enabled)
-        thinking_enabled = self._is_thinking_enabled(request, thinking_enabled)
-
-        trace_event(
-            stage="provider",
-            event="provider.request.sent",
-            source="provider",
-            provider=self._provider_name,
-            gateway_model=request.model,
-            downstream_model=body.get("model"),
-            message_count=len(body.get("messages", [])),
-            tool_count=len(body.get("tools", [])),
-            body=provider_native_messages_body_snapshot(body),
-        )
-
-        response: httpx.Response | None = None
-        sent_any_event = False
-        state = self._new_stream_state(request, thinking_enabled=thinking_enabled)
-        emitted_tracker = EmittedNativeSseTracker()
-        recovery_session = StreamRecoverySession(
-            provider_name=self._provider_name,
-            request_id=request_id,
-        )
-
-        async with self._global_rate_limiter.concurrency_slot():
-            while True:
-                stream_opened = False
-                try:
-                    response = await self._global_rate_limiter.execute_with_retry(
-                        self._validated_stream_send, body, req_tag=req_tag
-                    )
-                    stream_opened = True
-
-                    chunk_count = 0
-                    chunk_bytes = 0
-
-                    async for chunk in self._iter_stream_chunks(
-                        response,
-                        state=state,
-                        thinking_enabled=thinking_enabled,
-                    ):
-                        chunk_count += 1
-                        chunk_bytes += len(chunk.encode("utf-8", errors="replace"))
-                        emitted_tracker.feed(chunk)
-                        for event in recovery_session.push(chunk):
-                            sent_any_event = True
-                            yield event
-
-                    if not emitted_tracker.has_terminal_message():
-                        raise TruncatedProviderStreamError(
-                            "Provider stream ended without message_stop."
-                        )
-
-                    trace_event(
-                        stage="provider",
-                        event="provider.response.completed",
-                        source="provider",
-                        provider=self._provider_name,
-                        gateway_model=request.model,
-                        sse_chunks_out=chunk_count,
-                        sse_bytes_out=chunk_bytes,
-                    )
-                    for event in recovery_session.flush():
-                        sent_any_event = True
-                        yield event
-                    return
-
-                except Exception as error:
-                    generated_output = emitted_tracker.has_content_block()
-                    complete_tool_salvageable = (
-                        generated_output
-                        and emitted_tracker.can_salvage_tool_use(
-                            tool_schemas_by_name(request)
-                        )
-                    )
-                    decision = recovery_session.advance_failure(
-                        error,
-                        stream_opened=stream_opened,
-                        generated_output=generated_output,
-                        complete_tool_salvageable=complete_tool_salvageable,
-                    )
-                    if decision.action == StreamFailureAction.EARLY_RETRY:
-                        if response is not None and not response.is_closed:
-                            await _maybe_await_aclose(response)
-                        response = None
-                        state = self._new_stream_state(
-                            request, thinking_enabled=thinking_enabled
-                        )
-                        emitted_tracker = EmittedNativeSseTracker()
-                        sent_any_event = False
-                        continue
-
-                    if decision.action == StreamFailureAction.MIDSTREAM_RECOVERY:
-                        try:
-                            recovery_events = await self._native_recovery_events(
-                                body=body,
-                                request=request,
-                                tracker=emitted_tracker,
-                                error=error,
-                                request_id=request_id,
-                                req_tag=req_tag,
-                                thinking_enabled=thinking_enabled,
-                            )
-                        except Exception as recovery_error:
-                            trace_event(
-                                stage="provider",
-                                event="provider.recovery.failed",
-                                source="provider",
-                                provider=self._provider_name,
-                                request_id=request_id,
-                                exc_type=type(recovery_error).__name__,
-                            )
-                            recovery_events = None
-                        if recovery_events is not None:
-                            for event in recovery_session.flush_uncommitted(decision):
-                                sent_any_event = True
-                                yield event
-                            for event in recovery_events:
-                                yield event
-                            return
-
-                    if not isinstance(error, httpx.HTTPStatusError):
-                        self._log_stream_transport_error(
-                            tag, req_tag, error, request_id=request_id
-                        )
-                    error_message = self._get_error_message(error, request_id)
-
-                    if response is not None and not response.is_closed:
-                        await _maybe_await_aclose(response)
-
-                    trace_event(
-                        stage="provider",
-                        event="provider.response.error",
-                        source="provider",
-                        provider=self._provider_name,
-                        error_message=error_message,
-                        exc_type=type(error).__name__,
-                        mid_stream=(
-                            sent_any_event
-                            or decision.committed
-                            or decision.has_buffered
-                        ),
-                    )
-                    if decision.committed or decision.has_buffered:
-                        if not decision.committed:
-                            for event in recovery_session.flush():
-                                sent_any_event = True
-                                yield event
-                        for event in emitted_tracker.iter_close_unclosed_blocks():
-                            yield event
-                        for event in emitted_tracker.iter_midstream_error_tail(
-                            error_message,
-                            request=request,
-                            input_tokens=input_tokens,
-                            log_raw_sse_events=self._config.log_raw_sse_events,
-                        ):
-                            yield event
-                    else:
-                        recovery_session.discard()
-                        for event in self._emit_error_events(
-                            request=request,
-                            input_tokens=input_tokens,
-                            error_message=error_message,
-                            sent_any_event=False,
-                        ):
-                            yield event
-                    return
-                finally:
-                    if response is not None and not response.is_closed:
-                        await _maybe_await_aclose(response)
diff --git a/providers/cerebras/client.py b/providers/cerebras/client.py
--- a/providers/cerebras/client.py
+++ b/providers/cerebras/client.py
@@ -6,7 +6,7 @@
 
 from providers.base import ProviderConfig
 from providers.defaults import CEREBRAS_DEFAULT_BASE
-from providers.openai_compat import OpenAIChatTransport
+from providers.transports.openai_chat import OpenAIChatTransport
 
 from .request import build_request_body
 
diff --git a/providers/codestral/client.py b/providers/codestral/client.py
--- a/providers/codestral/client.py
+++ b/providers/codestral/client.py
@@ -7,7 +7,7 @@
 from providers.base import ProviderConfig
 from providers.defaults import CODESTRAL_DEFAULT_BASE
 from providers.mistral.request import build_request_body
-from providers.openai_compat import OpenAIChatTransport
+from providers.transports.openai_chat import OpenAIChatTransport
 
 
 class CodestralProvider(OpenAIChatTransport):
diff --git a/providers/deepseek/client.py b/providers/deepseek/client.py
--- a/providers/deepseek/client.py
+++ b/providers/deepseek/client.py
@@ -6,9 +6,9 @@
 
 import httpx
 
-from providers.anthropic_messages import AnthropicMessagesTransport
 from providers.base import ProviderConfig
 from providers.defaults import DEEPSEEK_ANTHROPIC_DEFAULT_BASE
+from providers.transports.anthropic_messages import AnthropicMessagesTransport
 
 from .request import build_request_body
 
diff --git a/providers/fireworks/client.py b/providers/fireworks/client.py
--- a/providers/fireworks/client.py
+++ b/providers/fireworks/client.py
@@ -4,8 +4,8 @@
 
 from typing import Any
 
-from providers.anthropic_messages import AnthropicMessagesTransport
 from providers.base import ProviderConfig
+from providers.transports.anthropic_messages import AnthropicMessagesTransport
 
 from .request import build_request_body
 
diff --git a/providers/gemini/client.py b/providers/gemini/client.py
--- a/providers/gemini/client.py
+++ b/providers/gemini/client.py
@@ -7,7 +7,7 @@
 
 from providers.base import ProviderConfig
 from providers.defaults import GEMINI_DEFAULT_BASE
-from providers.openai_compat import OpenAIChatTransport
+from providers.transports.openai_chat import OpenAIChatTransport
 
 from .request import build_request_body
 
diff --git a/providers/groq/client.py b/providers/groq/client.py
--- a/providers/groq/client.py
+++ b/providers/groq/client.py
@@ -6,7 +6,7 @@
 
 from providers.base import ProviderConfig
 from providers.defaults import GROQ_DEFAULT_BASE
-from providers.openai_compat import OpenAIChatTransport
+from providers.transports.openai_chat import OpenAIChatTransport
 
 from .request import build_request_body
 
diff --git a/providers/kimi/client.py b/providers/kimi/client.py
--- a/providers/kimi/client.py
+++ b/providers/kimi/client.py
@@ -6,9 +6,9 @@
 
 import httpx
 
-from providers.anthropic_messages import AnthropicMessagesTransport
 from providers.base import ProviderConfig
 from providers.defaults import KIMI_DEFAULT_BASE
+from providers.transports.anthropic_messages import AnthropicMessagesTransport
 
 from .request import build_request_body
 
diff --git a/providers/llamacpp/client.py b/providers/llamacpp/client.py
--- a/providers/llamacpp/client.py
+++ b/providers/llamacpp/client.py
@@ -1,8 +1,8 @@
 """Llama.cpp provider implementation."""
 
-from providers.anthropic_messages import AnthropicMessagesTransport
 from providers.base import ProviderConfig
 from providers.defaults import LLAMACPP_DEFAULT_BASE
+from providers.transports.anthropic_messages import AnthropicMessagesTransport
 
 
 class LlamaCppProvider(AnthropicMessagesTransport):
diff --git a/providers/lmstudio/client.py b/providers/lmstudio/client.py
--- a/providers/lmstudio/client.py
+++ b/providers/lmstudio/client.py
@@ -1,8 +1,8 @@
 """LM Studio provider implementation."""
 
-from providers.anthropic_messages import AnthropicMessagesTransport
 from providers.base import ProviderConfig
 from providers.defaults import LMSTUDIO_DEFAULT_BASE
+from providers.transports.anthropic_messages import AnthropicMessagesTransport
 
 
 class LMStudioProvider(AnthropicMessagesTransport):
diff --git a/providers/mistral/client.py b/providers/mistral/client.py
--- a/providers/mistral/client.py
+++ b/providers/mistral/client.py
@@ -6,7 +6,7 @@
 
 from providers.base import ProviderConfig
 from providers.defaults import MISTRAL_DEFAULT_BASE
-from providers.openai_compat import OpenAIChatTransport
+from providers.transports.openai_chat import OpenAIChatTransport
 
 from .request import build_request_body
 
diff --git a/providers/nvidia_nim/client.py b/providers/nvidia_nim/client.py
--- a/providers/nvidia_nim/client.py
+++ b/providers/nvidia_nim/client.py
@@ -9,7 +9,7 @@
 from config.nim import NimSettings
 from providers.base import ProviderConfig
 from providers.defaults import NVIDIA_NIM_DEFAULT_BASE
-from providers.openai_compat import OpenAIChatTransport
+from providers.transports.openai_chat import OpenAIChatTransport
 
 from .request import (
     body_without_nim_tool_argument_aliases,
diff --git a/providers/ollama/client.py b/providers/ollama/client.py
--- a/providers/ollama/client.py
+++ b/providers/ollama/client.py
@@ -2,10 +2,10 @@
 
 import httpx
 
-from providers.anthropic_messages import AnthropicMessagesTransport
 from providers.base import ProviderConfig
 from providers.defaults import OLLAMA_DEFAULT_BASE
 from providers.model_listing import extract_ollama_model_ids
+from providers.transports.anthropic_messages import AnthropicMessagesTransport
 
 
 class OllamaProvider(AnthropicMessagesTransport):
diff --git a/providers/open_router/client.py b/providers/open_router/client.py
--- a/providers/open_router/client.py
+++ b/providers/open_router/client.py
@@ -12,14 +12,17 @@
     parse_native_sse_event,
     transform_native_sse_block_event,
 )
-from providers.anthropic_messages import AnthropicMessagesTransport, StreamChunkMode
 from providers.base import ProviderConfig
 from providers.defaults import OPENROUTER_DEFAULT_BASE
 from providers.model_listing import (
     ProviderModelInfo,
     extract_openrouter_tool_model_ids,
     extract_openrouter_tool_model_infos,
 )
+from providers.transports.anthropic_messages import (
+    AnthropicMessagesTransport,
+    StreamChunkMode,
+)
 
 from .request import build_request_body
 
diff --git a/providers/openai_compat.py b/providers/openai_compat.py
deleted file mode 100644
--- a/providers/openai_compat.py
+++ /dev/null
@@ -1,955 +0,0 @@
-"""OpenAI-style chat base for :class:`OpenAIChatTransport` (NIM, etc.).
-
-``AnthropicMessagesTransport``-based providers (OpenRouter, LM Studio, DeepSeek, …) live
-in separate modules; do not list them as subclasses of this class.
-"""
-
-import asyncio
-import json
-import uuid
-from abc import abstractmethod
-from collections.abc import AsyncIterator, Iterator
-from typing import Any
-
-import httpx
-from loguru import logger
-from openai import AsyncOpenAI
-
-from core.anthropic import (
-    ContentType,
-    HeuristicToolParser,
-    SSEBuilder,
-    ThinkTagParser,
-    map_stop_reason,
-)
-from core.anthropic.stream_recovery import (
-    MIDSTREAM_RECOVERY_ATTEMPTS,
-    TruncatedProviderStreamError,
-    accept_tool_json_repair,
-    continuation_suffix,
-    is_retryable_stream_error,
-    make_openai_text_recovery_body,
-    make_openai_tool_repair_body,
-    parse_complete_tool_input,
-    tool_schemas_by_name,
-)
-from core.anthropic.stream_recovery_session import (
-    StreamFailureAction,
-    StreamRecoverySession,
-)
-from core.trace import provider_chat_body_snapshot, trace_event
-from providers.base import BaseProvider, ProviderConfig
-from providers.error_mapping import (
-    extract_provider_error_detail,
-    map_error,
-    user_visible_message_for_mapped_provider_error,
-)
-from providers.model_listing import extract_openai_model_ids
-from providers.rate_limit import GlobalRateLimiter
-
-
-def _iter_heuristic_tool_use_sse(
-    sse: SSEBuilder, tool_use: dict[str, Any]
-) -> Iterator[str]:
-    """Emit SSE for one heuristic tool_use block (closes open text/thinking first)."""
-    if tool_use.get("name") == "Task" and isinstance(tool_use.get("input"), dict):
-        task_input = tool_use["input"]
-        if task_input.get("run_in_background") is not False:
-            task_input["run_in_background"] = False
-    yield from sse.close_content_blocks()
-    block_idx = sse.blocks.allocate_index()
-    yield sse.content_block_start(
-        block_idx,
-        "tool_use",
-        id=tool_use["id"],
-        name=tool_use["name"],
-    )
-    yield sse.content_block_delta(
-        block_idx,
-        "input_json_delta",
-        json.dumps(tool_use["input"]),
-    )
-    yield sse.content_block_stop(block_idx)
-
-
-def _tool_call_extra_content(tool_call: Any) -> dict[str, Any] | None:
-    if isinstance(tool_call, dict):
-        value = tool_call.get("extra_content")
-        return value if isinstance(value, dict) else None
-
-    value = getattr(tool_call, "extra_content", None)
-    if isinstance(value, dict):
-        return value
-
-    model_extra = getattr(tool_call, "model_extra", None)
-    if isinstance(model_extra, dict):
-        value = model_extra.get("extra_content")
-        if isinstance(value, dict):
-            return value
-
-    pydantic_extra = getattr(tool_call, "__pydantic_extra__", None)
-    if isinstance(pydantic_extra, dict):
-        value = pydantic_extra.get("extra_content")
-        if isinstance(value, dict):
-            return value
-
-    return None
-
-
-class OpenAIChatTransport(BaseProvider):
-    """Base for OpenAI-compatible ``/chat/completions`` adapters (NIM, …)."""
-
-    def __init__(
-        self,
-        config: ProviderConfig,
-        *,
-        provider_name: str,
-        base_url: str,
-        api_key: str,
-    ):
-        super().__init__(config)
-        self._provider_name = provider_name
-        self._api_key = api_key
-        self._base_url = base_url.rstrip("/")
-        self._global_rate_limiter = GlobalRateLimiter.get_scoped_instance(
-            provider_name.lower(),
-            rate_limit=config.rate_limit,
-            rate_window=config.rate_window,
-            max_concurrency=config.max_concurrency,
-        )
-        http_client = None
-        if config.proxy:
-            http_client = httpx.AsyncClient(
-                proxy=config.proxy,
-                timeout=httpx.Timeout(
-                    config.http_read_timeout,
-                    connect=config.http_connect_timeout,
-                    read=config.http_read_timeout,
-                    write=config.http_write_timeout,
-                ),
-            )
-        self._client = AsyncOpenAI(
-            api_key=self._api_key,
-            base_url=self._base_url,
-            max_retries=0,
-            timeout=httpx.Timeout(
-                config.http_read_timeout,
-                connect=config.http_connect_timeout,
-                read=config.http_read_timeout,
-                write=config.http_write_timeout,
-            ),
-            http_client=http_client,
-        )
-
-    async def cleanup(self) -> None:
-        """Release HTTP client resources."""
-        client = getattr(self, "_client", None)
-        if client is not None:
-            await client.close()
-
-    async def list_model_ids(self) -> frozenset[str]:
-        """Return model ids from the provider's OpenAI-compatible models endpoint."""
-        payload = await self._client.models.list()
-        return extract_openai_model_ids(payload, provider_name=self._provider_name)
-
-    @abstractmethod
-    def _build_request_body(
-        self, request: Any, thinking_enabled: bool | None = None
-    ) -> dict:
-        """Build request body. Must be implemented by subclasses."""
-
-    def _handle_extra_reasoning(
-        self, delta: Any, sse: SSEBuilder, *, thinking_enabled: bool
-    ) -> Iterator[str]:
-        """Hook for provider-specific reasoning (e.g. OpenRouter reasoning_details)."""
-        return iter(())
-
-    def _get_retry_request_body(self, error: Exception, body: dict) -> dict | None:
-        """Return a modified request body for one retry, or None."""
-        return None
-
-    def _prepare_create_body(self, body: dict[str, Any]) -> dict[str, Any]:
-        """Return the body passed to the upstream OpenAI-compatible client."""
-        return body
-
-    def _record_tool_call_extra_content(
-        self, tool_call_id: str, extra_content: dict[str, Any]
-    ) -> None:
-        """Hook for providers that must replay OpenAI tool-call metadata later."""
-
-    def _tool_argument_aliases(self, body: dict[str, Any]) -> dict[str, dict[str, str]]:
-        """Return provider-specific per-tool argument aliases for this request."""
-        return {}
-
-    async def _create_stream(self, body: dict) -> tuple[Any, dict]:
-        """Create a streaming chat completion, optionally retrying once."""
-        try:
-            create_body = self._prepare_create_body(body)
-            stream = await self._global_rate_limiter.execute_with_retry(
-                self._client.chat.completions.create, **create_body, stream=True
-            )
-            return stream, body
-        except Exception as error:
-            retry_body = self._get_retry_request_body(error, body)
-            if retry_body is None:
-                raise
-
-            create_retry_body = self._prepare_create_body(retry_body)
-            stream = await self._global_rate_limiter.execute_with_retry(
-                self._client.chat.completions.create, **create_retry_body, stream=True
-            )
-            return stream, retry_body
-
-    def _restore_aliased_tool_arguments(
-        self, argument_json: str, aliases: dict[str, str]
-    ) -> str | None:
-        try:
-            parsed = json.loads(argument_json)
-        except json.JSONDecodeError:
-            return None
-        if not isinstance(parsed, dict):
-            return argument_json
-        restored = self._restore_aliased_tool_argument_value(parsed, aliases)
-        return json.dumps(restored)
-
-    def _restore_aliased_tool_argument_value(
-        self, value: Any, aliases: dict[str, str]
-    ) -> Any:
-        if isinstance(value, dict):
-            return {
-                aliases.get(key, key): self._restore_aliased_tool_argument_value(
-                    item, aliases
-                )
-                for key, item in value.items()
-            }
-        if isinstance(value, list):
-            return [
-                self._restore_aliased_tool_argument_value(item, aliases)
-                for item in value
-            ]
-        return value
-
-    def _emit_tool_arg_delta(
-        self,
-        sse: SSEBuilder,
-        tc_index: int,
-        args: str,
-        *,
-        tool_argument_aliases: dict[str, dict[str, str]] | None = None,
-        tool_argument_alias_buffers: dict[int, str] | None = None,
-    ) -> Iterator[str]:
-        """Emit one argument fragment for a started tool block (Task buffer or raw JSON)."""
-        if not args:
-            return
-        state = sse.blocks.tool_states.get(tc_index)
-        if state is None:
-            return
-        if state.name == "Task":
-            parsed = sse.blocks.buffer_task_args(tc_index, args)
-            if parsed is not None:
-                yield sse.emit_tool_delta(tc_index, json.dumps(parsed))
-            return
-        aliases = (
-            tool_argument_aliases.get(state.name, {}) if tool_argument_aliases else {}
-        )
-        if aliases:
-            if tool_argument_alias_buffers is None:
-                restored = self._restore_aliased_tool_arguments(args, aliases)
-                if restored is not None:
-                    yield sse.emit_tool_delta(tc_index, restored)
-                return
-
-            buffered_args = tool_argument_alias_buffers.get(tc_index, "") + args
-            restored = self._restore_aliased_tool_arguments(buffered_args, aliases)
-            if restored is None:
-                tool_argument_alias_buffers[tc_index] = buffered_args
-                return
-            tool_argument_alias_buffers.pop(tc_index, None)
-            yield sse.emit_tool_delta(tc_index, restored)
-            return
-        yield sse.emit_tool_delta(tc_index, args)
-
-    def _process_tool_call(
-        self,
-        tc: dict,
-        sse: SSEBuilder,
-        *,
-        tool_argument_aliases: dict[str, dict[str, str]] | None = None,
-        tool_argument_alias_buffers: dict[int, str] | None = None,
-    ) -> Iterator[str]:
-        """Process a single tool call delta and yield SSE events."""
-        raw_index = tc.get("index", 0)
-        tc_index = raw_index if isinstance(raw_index, int) else 0
-        if tc_index < 0:
-            tc_index = len(sse.blocks.tool_states)
-
-        fn_delta = tc.get("function", {})
-        incoming_name = fn_delta.get("name")
-        arguments = fn_delta.get("arguments", "") or ""
-
-        if tc.get("id") is not None:
-            sse.blocks.set_stream_tool_id(tc_index, tc.get("id"))
-
-        raw_extra_content = tc.get("extra_content")
-        extra_content = (
-            raw_extra_content
-            if isinstance(raw_extra_content, dict) and raw_extra_content
-            else None
-        )
-        if extra_content:
-            sse.blocks.set_tool_extra_content(tc_index, extra_content)
-
-        if incoming_name is not None:
-            sse.blocks.register_tool_name(tc_index, incoming_name)
-
-        state = sse.blocks.tool_states.get(tc_index)
-        resolved_id = (state.tool_id if state and state.tool_id else None) or tc.get(
-            "id"
-        )
-        resolved_name = (state.name if state else "") or ""
-
-        if not state or not state.started:
-            name_ok = bool((resolved_name or "").strip())
-            if name_ok:
-                tool_id = str(resolved_id) if resolved_id else f"tool_{uuid.uuid4()}"
-                display_name = (resolved_name or "").strip() or "tool_call"
-                start_extra_content = state.extra_content if state else extra_content
-                if start_extra_content:
-                    self._record_tool_call_extra_content(tool_id, start_extra_content)
-                yield sse.start_tool_block(
-                    tc_index,
-                    tool_id,
-                    display_name,
-                    extra_content=start_extra_content,
-                )
-                state = sse.blocks.tool_states[tc_index]
-                if state.pre_start_args:
-                    pre = state.pre_start_args
-                    state.pre_start_args = ""
-                    yield from self._emit_tool_arg_delta(
-                        sse,
-                        tc_index,
-                        pre,
-                        tool_argument_aliases=tool_argument_aliases,
-                        tool_argument_alias_buffers=tool_argument_alias_buffers,
-                    )
-
-        state = sse.blocks.tool_states.get(tc_index)
-        if state is not None and state.tool_id and extra_content:
-            self._record_tool_call_extra_content(state.tool_id, extra_content)
-        if not arguments:
-            return
-        if state is None or not state.started:
-            state = sse.blocks.ensure_tool_state(tc_index)
-            if not (resolved_name or "").strip():
-                state.pre_start_args += arguments
-                return
-
-        yield from self._emit_tool_arg_delta(
-            sse,
-            tc_index,
-            arguments,
-            tool_argument_aliases=tool_argument_aliases,
-            tool_argument_alias_buffers=tool_argument_alias_buffers,
-        )
-
-    def _flush_task_arg_buffers(self, sse: SSEBuilder) -> Iterator[str]:
-        """Emit buffered Task args as a single JSON delta (best-effort)."""
-        for tool_index, out in sse.blocks.flush_task_arg_buffers():
-            yield sse.emit_tool_delta(tool_index, out)
-
-    def _flush_tool_argument_alias_buffers(
-        self,
-        sse: SSEBuilder,
-        tool_argument_aliases: dict[str, dict[str, str]],
-        tool_argument_alias_buffers: dict[int, str],
-    ) -> Iterator[str]:
-        """Emit remaining aliased tool args without losing data on malformed JSON."""
-        for tool_index, buffered_args in list(tool_argument_alias_buffers.items()):
-            if not buffered_args:
-                tool_argument_alias_buffers.pop(tool_index, None)
-                continue
-            state = sse.blocks.tool_states.get(tool_index)
-            if state is None or state.name == "Task":
-                continue
-            aliases = tool_argument_aliases.get(state.name, {})
-            if not aliases:
-                continue
-            restored = self._restore_aliased_tool_arguments(buffered_args, aliases)
-            yield sse.emit_tool_delta(
-                tool_index,
-                restored if restored is not None else buffered_args,
-            )
-            tool_argument_alias_buffers.pop(tool_index, None)
-
-    def _has_committed_sse_output(self, sse: SSEBuilder) -> bool:
-        return (
-            sse.blocks.text_index != -1
-            or sse.blocks.thinking_index != -1
-            or sse.blocks.has_emitted_tool_block()
-        )
-
-    def _openai_error_message(self, error: Exception, request_id: str | None) -> str:
-        mapped_error = map_error(error, rate_limiter=self._global_rate_limiter)
-        return user_visible_message_for_mapped_provider_error(
-            mapped_error,
-            provider_name=self._provider_name,
-            read_timeout_s=self._config.http_read_timeout,
-            detail=extract_provider_error_detail(error),
-            request_id=request_id,
-        )
-
-    async def _collect_recovery_text(self, body: dict[str, Any]) -> tuple[str, str]:
-        """Collect text/reasoning from an internal recovery request."""
-        last_error: Exception | None = None
-        for attempt in range(MIDSTREAM_RECOVERY_ATTEMPTS):
-            try:
-                stream, _ = await self._create_stream(body)
-                text_parts: list[str] = []
-                thinking_parts: list[str] = []
-                async for chunk in stream:
-                    if not getattr(chunk, "choices", None):
-                        continue
-                    choice = chunk.choices[0]
-                    delta = choice.delta
-                    if delta is None:
-                        continue
-                    reasoning = getattr(delta, "reasoning_content", None)
-                    if isinstance(reasoning, str) and reasoning:
-                        thinking_parts.append(reasoning)
-                    content = getattr(delta, "content", None)
-                    if isinstance(content, str) and content:
-                        text_parts.append(content)
-                return "".join(text_parts), "".join(thinking_parts)
-            except Exception as error:
-                last_error = error
-                if not is_retryable_stream_error(error):
-                    raise
-                trace_event(
-                    stage="provider",
-                    event="provider.recovery.retry",
-                    source="provider",
-                    provider=self._provider_name,
-                    recovery_kind="openai_text",
-                    attempt=attempt + 1,
-                    max_attempts=MIDSTREAM_RECOVERY_ATTEMPTS,
-                    exc_type=type(error).__name__,
-                )
-        if last_error is not None:
-            raise last_error
-        return "", ""
-
-    def _started_tool_states(self, sse: SSEBuilder) -> list[tuple[int, Any]]:
-        return [
-            (tool_index, state)
-            for tool_index, state in sse.blocks.tool_states.items()
-            if state.started
-        ]
-
-    def _all_started_tools_complete(self, sse: SSEBuilder, request: Any) -> bool:
-        schemas = tool_schemas_by_name(request)
-        started = self._started_tool_states(sse)
-        if not started:
-            return False
-        for _, state in started:
-            raw = "".join(state.contents)
-            if parse_complete_tool_input(raw, state.name, schemas) is None:
-                return False
-        return True
-
-    async def _repair_openai_tool_args(
-        self,
-        *,
-        body: dict[str, Any],
-        sse: SSEBuilder,
-        request: Any,
-        tool_argument_alias_buffers: dict[int, str],
-    ) -> list[str] | None:
-        schemas = tool_schemas_by_name(request)
-        events: list[str] = []
-        for tool_index, state in self._started_tool_states(sse):
-            emitted_prefix = "".join(state.contents)
-            repair_prefix = emitted_prefix
-            if not repair_prefix and state.name == "Task" and state.task_arg_buffer:
-                repair_prefix = state.task_arg_buffer
-            if not repair_prefix and tool_index in tool_argument_alias_buffers:
-                repair_prefix = tool_argument_alias_buffers[tool_index]
-            if (
-                parse_complete_tool_input(repair_prefix, state.name, schemas)
-                is not None
-            ):
-                if not emitted_prefix:
-                    yield_text = repair_prefix
-                    if yield_text:
-                        events.append(sse.emit_tool_delta(tool_index, yield_text))
-                continue
-
-            schema = schemas.get(state.name)
-            recovery_body = make_openai_tool_repair_body(
-                body,
-                tool_name=state.name,
-                prefix=repair_prefix,
-                input_schema=schema.input_schema if schema is not None else None,
-            )
-            accepted_suffix: str | None = None
-            for attempt in range(MIDSTREAM_RECOVERY_ATTEMPTS):
-                text, _ = await self._collect_recovery_text(recovery_body)
-                repair = accept_tool_json_repair(
-                    repair_prefix,
-                    text,
-                    tool_name=state.name,
-                    schemas=schemas,
-                )
-                if repair is not None:
-                    accepted_suffix = repair.suffix
-                    trace_event(
-                        stage="provider",
-                        event="provider.recovery.tool_repaired",
-                        source="provider",
-                        provider=self._provider_name,
-                        tool_name=state.name,
-                        attempt=attempt + 1,
-                    )
-                    break
-            if accepted_suffix is None:
-                return None
-            to_emit = (
-                accepted_suffix if emitted_prefix else repair_prefix + accepted_suffix
-            )
-            if to_emit:
-                events.append(sse.emit_tool_delta(tool_index, to_emit))
-        if not self._all_started_tools_complete(sse, request):
-            return None
-        return events
-
-    async def _openai_recovery_events(
-        self,
-        *,
-        body: dict[str, Any],
-        sse: SSEBuilder,
-        request: Any,
-        request_id: str | None,
-        error: Exception,
-        tool_argument_alias_buffers: dict[int, str],
-    ) -> list[str] | None:
-        if not is_retryable_stream_error(error):
-            return None
-
-        if sse.blocks.has_emitted_tool_block():
-            if not self._all_started_tools_complete(sse, request):
-                repair_events = await self._repair_openai_tool_args(
-                    body=body,
-                    sse=sse,
-                    request=request,
-                    tool_argument_alias_buffers=tool_argument_alias_buffers,
-                )
-                if repair_events is None:
-                    return None
-            else:
-                repair_events = []
-            events = list(repair_events)
-            events.extend(sse.close_all_blocks())
-            events.append(sse.message_delta("tool_use", sse.estimate_output_tokens()))
-            events.append(sse.message_stop())
-            trace_event(
-                stage="provider",
-                event="provider.recovery.tool_salvaged",
-                source="provider",
-                provider=self._provider_name,
-                request_id=request_id,
-            )
-            return events
-
-        partial_text = sse.accumulated_text
-        partial_thinking = sse.accumulated_reasoning
-        if not partial_text and not partial_thinking:
-            return None
-
-        recovery_body = make_openai_text_recovery_body(body, partial_text)
-        text, thinking = await self._collect_recovery_text(recovery_body)
-        text_suffix = continuation_suffix(partial_text, text)
-        thinking_suffix = continuation_suffix(partial_thinking, thinking)
-        events: list[str] = []
-        if thinking_suffix:
-            for event in sse.ensure_thinking_block():
-                events.append(event)
-            events.append(sse.emit_thinking_delta(thinking_suffix))
-        if text_suffix:
-            for event in sse.ensure_text_block():
-                events.append(event)
-            events.append(sse.emit_text_delta(text_suffix))
-        if not events:
-            return None
-        events.extend(sse.close_all_blocks())
-        events.append(sse.message_delta("end_turn", sse.estimate_output_tokens()))
-        events.append(sse.message_stop())
-        trace_event(
-            stage="provider",
-            event="provider.recovery.continued",
-            source="provider",
-            provider=self._provider_name,
-            request_id=request_id,
-        )
-        return events
-
-    def _emit_openai_error_tail(
-        self, sse: SSEBuilder, error_message: str
-    ) -> Iterator[str]:
-        yield from sse.close_all_blocks()
-        if sse.blocks.has_emitted_tool_block():
-            yield sse.emit_top_level_error(error_message)
-        else:
-            yield from sse.emit_error(error_message)
-        yield sse.message_delta("end_turn", 1)
-        yield sse.message_stop()
-
-    async def stream_response(
-        self,
-        request: Any,
-        input_tokens: int = 0,
-        *,
-        request_id: str | None = None,
-        thinking_enabled: bool | None = None,
-    ) -> AsyncIterator[str]:
-        """Stream response in Anthropic SSE format."""
-        with logger.contextualize(request_id=request_id):
-            async for event in self._stream_response_impl(
-                request, input_tokens, request_id, thinking_enabled=thinking_enabled
-            ):
-                yield event
-
-    async def _stream_response_impl(
-        self,
-        request: Any,
-        input_tokens: int,
-        request_id: str | None,
-        *,
-        thinking_enabled: bool | None,
-    ) -> AsyncIterator[str]:
-        """Shared streaming implementation."""
-        tag = self._provider_name
-        message_id = f"msg_{uuid.uuid4()}"
-
-        def new_sse_builder() -> SSEBuilder:
-            return SSEBuilder(
-                message_id,
-                request.model,
-                input_tokens,
-                log_raw_events=self._config.log_raw_sse_events,
-            )
-
-        sse = new_sse_builder()
-        recovery_session = StreamRecoverySession(
-            provider_name=tag,
-            request_id=request_id,
-        )
-
-        def hold_event(event: str) -> Iterator[str]:
-            yield from recovery_session.push(event)
-
-        def hold_events(events: Iterator[str]) -> Iterator[str]:
-            for event in events:
-                yield from hold_event(event)
-
-        body = self._build_request_body(request, thinking_enabled=thinking_enabled)
-        thinking_enabled = self._is_thinking_enabled(request, thinking_enabled)
-        req_tag = f" request_id={request_id}" if request_id else ""
-        trace_event(
-            stage="provider",
-            event="provider.request.sent",
-            source="provider",
-            provider=self._provider_name,
-            gateway_model=request.model,
-            downstream_model=body.get("model"),
-            message_count=len(body.get("messages", [])),
-            tool_count=len(body.get("tools", [])),
-            body=provider_chat_body_snapshot(body),
-        )
-
-        yield sse.message_start()
-
-        think_parser = ThinkTagParser()
-        heuristic_parser = HeuristicToolParser()
-        finish_reason = None
-        usage_info = None
-        tool_argument_aliases: dict[str, dict[str, str]] = {}
-        tool_argument_alias_buffers: dict[int, str] = {}
-
-        async with self._global_rate_limiter.concurrency_slot():
-            while True:
-                stream_opened = False
-                try:
-                    stream, body = await self._create_stream(body)
-                    stream_opened = True
-                    tool_argument_aliases = self._tool_argument_aliases(body)
-                    async for chunk in stream:
-                        if getattr(chunk, "usage", None):
-                            usage_info = chunk.usage
-
-                        if not chunk.choices:
-                            continue
-
-                        choice = chunk.choices[0]
-                        delta = choice.delta
-                        if delta is None:
-                            continue
-
-                        if choice.finish_reason:
-                            finish_reason = choice.finish_reason
-                            logger.debug("{} finish_reason: {}", tag, finish_reason)
-
-                        # Handle reasoning_content (OpenAI extended format)
-                        reasoning = getattr(delta, "reasoning_content", None)
-                        if thinking_enabled and reasoning:
-                            for event in hold_events(sse.ensure_thinking_block()):
-                                yield event
-                            for event in hold_event(sse.emit_thinking_delta(reasoning)):
-                                yield event
-
-                        # Provider-specific extra reasoning (e.g. OpenRouter reasoning_details)
-                        for event in self._handle_extra_reasoning(
-                            delta,
-                            sse,
-                            thinking_enabled=thinking_enabled,
-                        ):
-                            for out_event in hold_event(event):
-                                yield out_event
-
-                        # Handle text content
-                        if delta.content:
-                            for part in think_parser.feed(delta.content):
-                                if part.type == ContentType.THINKING:
-                                    if not thinking_enabled:
-                                        continue
-                                    for event in hold_events(
-                                        sse.ensure_thinking_block()
-                                    ):
-                                        yield event
-                                    for event in hold_event(
-                                        sse.emit_thinking_delta(part.content)
-                                    ):
-                                        yield event
-                                else:
-                                    (
-                                        filtered_text,
-                                        detected_tools,
-                                    ) = heuristic_parser.feed(part.content)
-
-                                    if filtered_text:
-                                        for event in hold_events(
-                                            sse.ensure_text_block()
-                                        ):
-                                            yield event
-                                        for event in hold_event(
-                                            sse.emit_text_delta(filtered_text)
-                                        ):
-                                            yield event
-
-                                    for tool_use in detected_tools:
-                                        for event in _iter_heuristic_tool_use_sse(
-                                            sse, tool_use
-                                        ):
-                                            for out_event in hold_event(event):
-                                                yield out_event
-
-                        # Handle native tool calls
-                        if delta.tool_calls:
-                            for event in hold_events(sse.close_content_blocks()):
-                                yield event
-                            for tc in delta.tool_calls:
-                                extra_content = _tool_call_extra_content(tc)
-                                tc_info = {
-                                    "index": tc.index,
-                                    "id": tc.id,
-                                    "function": {
-                                        "name": tc.function.name,
-                                        "arguments": tc.function.arguments,
-                                    },
-                                }
-                                if extra_content:
-                                    tc_info["extra_content"] = extra_content
-                                for event in self._process_tool_call(
-                                    tc_info,
-                                    sse,
-                                    tool_argument_aliases=tool_argument_aliases,
-                                    tool_argument_alias_buffers=tool_argument_alias_buffers,
-                                ):
-                                    for out_event in hold_event(event):
-                                        yield out_event
-
-                    if finish_reason is None:
-                        raise TruncatedProviderStreamError(
-                            "Provider stream ended without finish_reason."
-                        )
-                    break
-
-                except asyncio.CancelledError, GeneratorExit:
-                    raise
-                except Exception as e:
-                    generated_output = self._has_committed_sse_output(sse)
-                    complete_tool_salvageable = (
-                        generated_output
-                        and sse.blocks.has_emitted_tool_block()
-                        and self._all_started_tools_complete(sse, request)
-                    )
-                    decision = recovery_session.advance_failure(
-                        e,
-                        stream_opened=stream_opened,
-                        generated_output=generated_output,
-                        complete_tool_salvageable=complete_tool_salvageable,
-                    )
-                    if decision.action == StreamFailureAction.EARLY_RETRY:
-                        sse = new_sse_builder()
-                        think_parser = ThinkTagParser()
-                        heuristic_parser = HeuristicToolParser()
-                        finish_reason = None
-                        usage_info = None
-                        tool_argument_aliases = {}
-                        tool_argument_alias_buffers = {}
-                        continue
-
-                    if decision.action == StreamFailureAction.MIDSTREAM_RECOVERY:
-                        try:
-                            recovery_events = await self._openai_recovery_events(
-                                body=body,
-                                sse=sse,
-                                request=request,
-                                request_id=request_id,
-                                error=e,
-                                tool_argument_alias_buffers=tool_argument_alias_buffers,
-                            )
-                        except Exception as recovery_error:
-                            trace_event(
-                                stage="provider",
-                                event="provider.recovery.failed",
-                                source="provider",
-                                provider=tag,
-                                request_id=request_id,
-                                exc_type=type(recovery_error).__name__,
-                            )
-                            recovery_events = None
-                        if recovery_events is not None:
-                            for event in recovery_session.flush_uncommitted(decision):
-                                yield event
-                            for event in recovery_events:
-                                yield event
-                            return
-
-                    self._log_stream_transport_error(
-                        tag, req_tag, e, request_id=request_id
-                    )
-                    error_message = self._openai_error_message(e, request_id)
-                    trace_event(
-                        stage="provider",
-                        event="provider.response.error",
-                        source="provider",
-                        provider=tag,
-                        error_message=error_message,
-                        mapped_error_type=type(
-                            map_error(e, rate_limiter=self._global_rate_limiter)
-                        ).__name__,
-                    )
-                    if not decision.committed and decision.has_buffered:
-                        for event in recovery_session.flush():
-                            yield event
-                    elif not decision.committed:
-                        recovery_session.discard()
-                        sse = new_sse_builder()
-                    for event in self._emit_openai_error_tail(sse, error_message):
-                        yield event
-                    return
-
-        # Flush remaining content
-        remaining = think_parser.flush()
-        if remaining:
-            if remaining.type == ContentType.THINKING:
-                if not thinking_enabled:
-                    remaining = None
-                else:
-                    for event in hold_events(sse.ensure_thinking_block()):
-                        yield event
-                    for event in hold_event(sse.emit_thinking_delta(remaining.content)):
-                        yield event
-            if remaining and remaining.type == ContentType.TEXT:
-                for event in hold_events(sse.ensure_text_block()):
-                    yield event
-                for event in hold_event(sse.emit_text_delta(remaining.content)):
-                    yield event
-
-        for tool_use in heuristic_parser.flush():
-            for event in _iter_heuristic_tool_use_sse(sse, tool_use):
-                for out_event in hold_event(event):
-                    yield out_event
-
-        has_started_tool = any(s.started for s in sse.blocks.tool_states.values())
-        has_content_blocks = (
-            sse.blocks.text_index != -1
-            or sse.blocks.thinking_index != -1
-            or has_started_tool
-        )
-        if not has_content_blocks:
-            for event in hold_events(sse.ensure_text_block()):
-                yield event
-            for event in hold_event(sse.emit_text_delta(" ")):
-                yield event
-        elif (
-            not has_started_tool
-            and not sse.accumulated_text.strip()
-            and sse.accumulated_reasoning.strip()
-        ):
-            # Some OpenAI-compatible models (e.g. NIM reasoning templates) stream only
-            # ``reasoning_content`` with no ``content``; emit a minimal text block so
-            # clients and smoke ``text_content()`` see a completed assistant message.
-            for event in hold_events(sse.ensure_text_block()):
-                yield event
-            for event in hold_event(sse.emit_text_delta(" ")):
-                yield event
-
-        for event in self._flush_tool_argument_alias_buffers(
-            sse, tool_argument_aliases, tool_argument_alias_buffers
-        ):
-            for out_event in hold_event(event):
-                yield out_event
-
-        for event in self._flush_task_arg_buffers(sse):
-            for out_event in hold_event(event):
-                yield out_event
-
-        for event in hold_events(sse.close_all_blocks()):
-            yield event
-
-        completion = (
-            getattr(usage_info, "completion_tokens", None)
-            if usage_info is not None
-            else None
-        )
-        if isinstance(completion, int):
-            output_tokens = completion
-        else:
-            output_tokens = sse.estimate_output_tokens()
-        if usage_info and hasattr(usage_info, "prompt_tokens"):
-            provider_input = usage_info.prompt_tokens
-            if isinstance(provider_input, int):
-                logger.debug(
-                    "TOKEN_ESTIMATE: our={} provider={} diff={:+d}",
-                    input_tokens,
-                    provider_input,
-                    provider_input - input_tokens,
-                )
-        trace_event(
-            stage="provider",
-            event="provider.response.completed",
-            source="provider",
-            provider=self._provider_name,
-            finish_reason=(None if finish_reason is None else str(finish_reason)),
-            output_tokens=output_tokens,
-            prompt_tokens_estimate=input_tokens,
-        )
-        for event in hold_event(
-            sse.message_delta(map_stop_reason(finish_reason), output_tokens)
-        ):
-            yield event
-        for event in hold_event(sse.message_stop()):
-            yield event
-        for event in recovery_session.flush():
-            yield event
diff --git a/providers/opencode/client.py b/providers/opencode/client.py
--- a/providers/opencode/client.py
+++ b/providers/opencode/client.py
@@ -6,7 +6,7 @@
 
 from providers.base import ProviderConfig
 from providers.defaults import OPENCODE_DEFAULT_BASE
-from providers.openai_compat import OpenAIChatTransport
+from providers.transports.openai_chat import OpenAIChatTransport
 
 from .request import build_request_body
 
diff --git a/providers/transports/__init__.py b/providers/transports/__init__.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/__init__.py
@@ -0,0 +1 @@
+"""Provider transport families."""
diff --git a/providers/transports/anthropic_messages/__init__.py b/providers/transports/anthropic_messages/__init__.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/anthropic_messages/__init__.py
@@ -0,0 +1,5 @@
+"""Native Anthropic Messages transport family."""
+
+from .transport import AnthropicMessagesTransport, StreamChunkMode
+
+__all__ = ["AnthropicMessagesTransport", "StreamChunkMode"]
diff --git a/providers/transports/anthropic_messages/http.py b/providers/transports/anthropic_messages/http.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/anthropic_messages/http.py
@@ -0,0 +1,118 @@
+"""HTTP helpers for native Anthropic Messages transports."""
+
+from __future__ import annotations
+
+import inspect
+from typing import Any
+
+import httpx
+from loguru import logger
+
+from config.constants import (
+    NATIVE_MESSAGES_ERROR_BODY_LOG_CAP_BYTES,
+    PROVIDER_ERROR_BODY_DISPLAY_CAP_BYTES,
+)
+from providers.error_mapping import attach_provider_error_body
+from providers.exceptions import ModelListResponseError
+
+
+async def maybe_await_aclose(response: Any) -> None:
+    """Call ``aclose`` on httpx-like responses; ignore sync test doubles."""
+    close = getattr(response, "aclose", None)
+    if not callable(close):
+        return
+    result = close()
+    if inspect.isawaitable(result):
+        await result
+
+
+def model_list_json(response: httpx.Response, *, provider_name: str) -> Any:
+    """Parse model-list JSON with a provider-specific malformed-body error."""
+    response.raise_for_status()
+    try:
+        return response.json()
+    except ValueError as exc:
+        raise ModelListResponseError(
+            f"{provider_name} model-list response is malformed: invalid JSON"
+        ) from exc
+
+
+async def read_error_body_preview(
+    response: httpx.Response, max_bytes: int
+) -> tuple[bytes, bool]:
+    """Read at most ``max_bytes`` from an error response body."""
+    if max_bytes <= 0:
+        return b"", False
+    received = 0
+    parts: list[bytes] = []
+    truncated = False
+    async for chunk in response.aiter_bytes(chunk_size=65_536):
+        if received >= max_bytes:
+            truncated = True
+            break
+        remaining = max_bytes - received
+        take = chunk if len(chunk) <= remaining else chunk[:remaining]
+        if take:
+            parts.append(take)
+        received += len(take)
+        if len(chunk) > len(take):
+            truncated = True
+            break
+        if received >= max_bytes:
+            break
+    return (b"".join(parts), truncated)
+
+
+async def raise_for_status_with_body(
+    response: httpx.Response,
+    *,
+    provider_name: str,
+    req_tag: str,
+    log_api_error_tracebacks: bool,
+) -> None:
+    """Raise for non-200 responses after attaching a safe body preview."""
+    try:
+        response.raise_for_status()
+    except httpx.HTTPStatusError as error:
+        preview, truncated = await read_error_body_preview(
+            response, PROVIDER_ERROR_BODY_DISPLAY_CAP_BYTES
+        )
+        attach_provider_error_body(error, preview, truncated=truncated)
+        if log_api_error_tracebacks:
+            log_preview = preview[:NATIVE_MESSAGES_ERROR_BODY_LOG_CAP_BYTES]
+            log_truncated = truncated or len(preview) > len(log_preview)
+            if log_preview:
+                text = log_preview.decode("utf-8", errors="replace")
+                logger.error(
+                    "{}_ERROR:{} HTTP {} body_preview_bytes={} truncated={}: {}",
+                    provider_name,
+                    req_tag,
+                    response.status_code,
+                    len(log_preview),
+                    log_truncated,
+                    text,
+                )
+            else:
+                logger.error(
+                    "{}_ERROR:{} HTTP {} (empty error body)",
+                    provider_name,
+                    req_tag,
+                    response.status_code,
+                )
+        else:
+            cl = response.headers.get("content-length", "").strip()
+            extra = f" content_length_declared={cl}" if cl.isdigit() else ""
+            body_extra = (
+                " empty_error_body"
+                if not preview
+                else f" error_body_bytes_read={len(preview)}"
+            )
+            logger.error(
+                "{}_ERROR:{} HTTP {}{}{}",
+                provider_name,
+                req_tag,
+                response.status_code,
+                extra,
+                body_extra,
+            )
+        raise error
diff --git a/providers/transports/anthropic_messages/recovery.py b/providers/transports/anthropic_messages/recovery.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/anthropic_messages/recovery.py
@@ -0,0 +1,206 @@
+"""Native Anthropic Messages recovery event construction."""
+
+from __future__ import annotations
+
+from collections.abc import AsyncIterator, Callable
+from typing import Any
+
+import httpx
+
+from core.anthropic.emitted_sse_tracker import EmittedNativeSseTracker
+from core.anthropic.stream_contracts import parse_sse_text
+from core.anthropic.stream_recovery import (
+    MIDSTREAM_RECOVERY_ATTEMPTS,
+    accept_tool_json_repair,
+    continuation_suffix,
+    is_retryable_stream_error,
+    make_native_text_recovery_body,
+    make_native_tool_repair_body,
+    parse_complete_tool_input,
+    tool_schemas_by_name,
+)
+from core.trace import trace_event
+
+from .http import maybe_await_aclose
+
+IterStreamChunks = Callable[..., AsyncIterator[str]]
+
+
+class AnthropicMessagesRecovery:
+    """Construct recovery events for interrupted native Anthropic streams."""
+
+    def __init__(
+        self,
+        transport: Any,
+        *,
+        iter_stream_chunks: IterStreamChunks,
+    ) -> None:
+        self._transport = transport
+        self._iter_stream_chunks = iter_stream_chunks
+
+    async def collect_text(
+        self,
+        body: dict[str, Any],
+        *,
+        req_tag: str,
+        thinking_enabled: bool,
+    ) -> tuple[str, str]:
+        """Collect text/thinking from an internal native recovery request."""
+        last_error: Exception | None = None
+        for attempt in range(MIDSTREAM_RECOVERY_ATTEMPTS):
+            response: httpx.Response | None = None
+            try:
+                response = (
+                    await self._transport._global_rate_limiter.execute_with_retry(
+                        self._transport._validated_stream_send, body, req_tag=req_tag
+                    )
+                )
+                state = self._transport._new_stream_state(
+                    None, thinking_enabled=thinking_enabled
+                )
+                chunks = [
+                    chunk
+                    async for chunk in self._iter_stream_chunks(
+                        response,
+                        state=state,
+                        thinking_enabled=thinking_enabled,
+                    )
+                ]
+                text_parts: list[str] = []
+                thinking_parts: list[str] = []
+                for event in parse_sse_text("".join(chunks)):
+                    delta = event.data.get("delta")
+                    if not isinstance(delta, dict):
+                        continue
+                    text = delta.get("text")
+                    if isinstance(text, str):
+                        text_parts.append(text)
+                    thinking = delta.get("thinking")
+                    if isinstance(thinking, str):
+                        thinking_parts.append(thinking)
+                return "".join(text_parts), "".join(thinking_parts)
+            except Exception as error:
+                last_error = error
+                if not is_retryable_stream_error(error):
+                    raise
+                trace_event(
+                    stage="provider",
+                    event="provider.recovery.retry",
+                    source="provider",
+                    provider=self._transport._provider_name,
+                    recovery_kind="native_text",
+                    attempt=attempt + 1,
+                    max_attempts=MIDSTREAM_RECOVERY_ATTEMPTS,
+                    exc_type=type(error).__name__,
+                )
+            finally:
+                if response is not None and not response.is_closed:
+                    await maybe_await_aclose(response)
+        if last_error is not None:
+            raise last_error
+        return "", ""
+
+    async def events(
+        self,
+        *,
+        body: dict[str, Any],
+        request: Any,
+        tracker: EmittedNativeSseTracker,
+        error: Exception,
+        request_id: str | None,
+        req_tag: str,
+        thinking_enabled: bool,
+    ) -> list[str] | None:
+        """Build recovery events, or return None when recovery is impossible."""
+        if not is_retryable_stream_error(error):
+            return None
+
+        schemas = tool_schemas_by_name(request)
+        if tracker.has_tool_block():
+            repair_events: list[str] = []
+            for index, block in enumerate(tracker.tool_blocks()):
+                if (
+                    block.tool_id
+                    and block.name
+                    and parse_complete_tool_input(block.content, block.name, schemas)
+                    is not None
+                ):
+                    continue
+                schema = schemas.get(block.name)
+                recovery_body = make_native_tool_repair_body(
+                    body,
+                    tool_name=block.name,
+                    prefix=block.content,
+                    input_schema=schema.input_schema if schema is not None else None,
+                )
+                accepted_suffix: str | None = None
+                for attempt in range(MIDSTREAM_RECOVERY_ATTEMPTS):
+                    text, _ = await self.collect_text(
+                        recovery_body,
+                        req_tag=req_tag,
+                        thinking_enabled=thinking_enabled,
+                    )
+                    repair = accept_tool_json_repair(
+                        block.content,
+                        text,
+                        tool_name=block.name,
+                        schemas=schemas,
+                    )
+                    if repair is not None:
+                        accepted_suffix = repair.suffix
+                        trace_event(
+                            stage="provider",
+                            event="provider.recovery.tool_repaired",
+                            source="provider",
+                            provider=self._transport._provider_name,
+                            tool_name=block.name,
+                            attempt=attempt + 1,
+                        )
+                        break
+                if accepted_suffix is None:
+                    return None
+                repair_events.extend(
+                    tracker.append_tool_repair_suffix(index, accepted_suffix)
+                )
+
+            if not tracker.can_salvage_tool_use(schemas):
+                return None
+            events = list(repair_events)
+            events.extend(tracker.iter_success_tail("tool_use"))
+            trace_event(
+                stage="provider",
+                event="provider.recovery.tool_salvaged",
+                source="provider",
+                provider=self._transport._provider_name,
+                request_id=request_id,
+            )
+            return events
+
+        partial_text = tracker.emitted_text()
+        partial_thinking = tracker.emitted_thinking()
+        if not partial_text and not partial_thinking:
+            return None
+        recovery_body = make_native_text_recovery_body(body, partial_text)
+        text, thinking = await self.collect_text(
+            recovery_body,
+            req_tag=req_tag,
+            thinking_enabled=thinking_enabled,
+        )
+        text_suffix = continuation_suffix(partial_text, text)
+        thinking_suffix = continuation_suffix(partial_thinking, thinking)
+        events: list[str] = []
+        if thinking_suffix:
+            events.extend(tracker.append_thinking_suffix(thinking_suffix))
+        if text_suffix:
+            events.extend(tracker.append_text_suffix(text_suffix))
+        if not events:
+            return None
+        events.extend(tracker.iter_success_tail("end_turn"))
+        trace_event(
+            stage="provider",
+            event="provider.recovery.continued",
+            source="provider",
+            provider=self._transport._provider_name,
+            request_id=request_id,
+        )
+        return events
diff --git a/providers/transports/anthropic_messages/stream.py b/providers/transports/anthropic_messages/stream.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/anthropic_messages/stream.py
@@ -0,0 +1,295 @@
+"""Per-request native Anthropic Messages stream runner."""
+
+from __future__ import annotations
+
+from collections.abc import AsyncIterator
+from typing import Any
+
+import httpx
+
+from core.anthropic.emitted_sse_tracker import EmittedNativeSseTracker
+from core.anthropic.native_sse_block_policy import NativeSseBlockPolicyState
+from core.anthropic.stream_recovery import (
+    TruncatedProviderStreamError,
+    tool_schemas_by_name,
+)
+from core.anthropic.stream_recovery_session import (
+    StreamFailureAction,
+    StreamRecoverySession,
+)
+from core.trace import provider_native_messages_body_snapshot, trace_event
+
+from .http import maybe_await_aclose
+from .recovery import AnthropicMessagesRecovery
+
+
+async def iter_sse_lines(response: httpx.Response) -> AsyncIterator[str]:
+    """Yield raw SSE line chunks preserving local provider behavior."""
+    async for line in response.aiter_lines():
+        if line:
+            yield f"{line}\n"
+        else:
+            yield "\n"
+
+
+async def iter_sse_events(response: httpx.Response) -> AsyncIterator[str]:
+    """Group line-delimited SSE responses into full SSE events."""
+    event_lines: list[str] = []
+    async for line in response.aiter_lines():
+        if line:
+            event_lines.append(line)
+            continue
+        if event_lines:
+            yield "\n".join(event_lines) + "\n\n"
+            event_lines.clear()
+    if event_lines:
+        yield "\n".join(event_lines) + "\n\n"
+
+
+class AnthropicMessagesStreamRunner:
+    """Own mutable state for one native Anthropic provider stream."""
+
+    def __init__(
+        self,
+        transport: Any,
+        *,
+        request: Any,
+        input_tokens: int,
+        request_id: str | None,
+        thinking_enabled: bool | None,
+    ) -> None:
+        self._transport = transport
+        self._request = request
+        self._input_tokens = input_tokens
+        self._request_id = request_id
+        self._thinking_enabled = thinking_enabled
+        self._recovery = AnthropicMessagesRecovery(
+            transport,
+            iter_stream_chunks=self.iter_stream_chunks,
+        )
+
+    async def run(self) -> AsyncIterator[str]:
+        """Stream response via a native Anthropic-compatible messages endpoint."""
+        tag = self._transport._provider_name
+        req_tag = f" request_id={self._request_id}" if self._request_id else ""
+        body = self._transport._build_request_body(
+            self._request, thinking_enabled=self._thinking_enabled
+        )
+        thinking_enabled = self._transport._is_thinking_enabled(
+            self._request, self._thinking_enabled
+        )
+
+        trace_event(
+            stage="provider",
+            event="provider.request.sent",
+            source="provider",
+            provider=tag,
+            gateway_model=self._request.model,
+            downstream_model=body.get("model"),
+            message_count=len(body.get("messages", [])),
+            tool_count=len(body.get("tools", [])),
+            body=provider_native_messages_body_snapshot(body),
+        )
+
+        response: httpx.Response | None = None
+        sent_any_event = False
+        state = self._transport._new_stream_state(
+            self._request, thinking_enabled=thinking_enabled
+        )
+        emitted_tracker = EmittedNativeSseTracker()
+        recovery_session = StreamRecoverySession(
+            provider_name=tag,
+            request_id=self._request_id,
+        )
+
+        async with self._transport._global_rate_limiter.concurrency_slot():
+            while True:
+                stream_opened = False
+                try:
+                    response = (
+                        await self._transport._global_rate_limiter.execute_with_retry(
+                            self._transport._validated_stream_send,
+                            body,
+                            req_tag=req_tag,
+                        )
+                    )
+                    stream_opened = True
+
+                    chunk_count = 0
+                    chunk_bytes = 0
+
+                    async for chunk in self.iter_stream_chunks(
+                        response,
+                        state=state,
+                        thinking_enabled=thinking_enabled,
+                    ):
+                        chunk_count += 1
+                        chunk_bytes += len(chunk.encode("utf-8", errors="replace"))
+                        emitted_tracker.feed(chunk)
+                        for event in recovery_session.push(chunk):
+                            sent_any_event = True
+                            yield event
+
+                    if not emitted_tracker.has_terminal_message():
+                        raise TruncatedProviderStreamError(
+                            "Provider stream ended without message_stop."
+                        )
+
+                    trace_event(
+                        stage="provider",
+                        event="provider.response.completed",
+                        source="provider",
+                        provider=tag,
+                        gateway_model=self._request.model,
+                        sse_chunks_out=chunk_count,
+                        sse_bytes_out=chunk_bytes,
+                    )
+                    for event in recovery_session.flush():
+                        sent_any_event = True
+                        yield event
+                    return
+
+                except Exception as error:
+                    generated_output = emitted_tracker.has_content_block()
+                    complete_tool_salvageable = (
+                        generated_output
+                        and emitted_tracker.can_salvage_tool_use(
+                            tool_schemas_by_name(self._request)
+                        )
+                    )
+                    decision = recovery_session.advance_failure(
+                        error,
+                        stream_opened=stream_opened,
+                        generated_output=generated_output,
+                        complete_tool_salvageable=complete_tool_salvageable,
+                    )
+                    if decision.action == StreamFailureAction.EARLY_RETRY:
+                        if response is not None and not response.is_closed:
+                            await maybe_await_aclose(response)
+                        response = None
+                        state = self._transport._new_stream_state(
+                            self._request, thinking_enabled=thinking_enabled
+                        )
+                        emitted_tracker = EmittedNativeSseTracker()
+                        sent_any_event = False
+                        continue
+
+                    if decision.action == StreamFailureAction.MIDSTREAM_RECOVERY:
+                        try:
+                            recovery_events = await self._recovery.events(
+                                body=body,
+                                request=self._request,
+                                tracker=emitted_tracker,
+                                error=error,
+                                request_id=self._request_id,
+                                req_tag=req_tag,
+                                thinking_enabled=thinking_enabled,
+                            )
+                        except Exception as recovery_error:
+                            trace_event(
+                                stage="provider",
+                                event="provider.recovery.failed",
+                                source="provider",
+                                provider=tag,
+                                request_id=self._request_id,
+                                exc_type=type(recovery_error).__name__,
+                            )
+                            recovery_events = None
+                        if recovery_events is not None:
+                            for event in recovery_session.flush_uncommitted(decision):
+                                sent_any_event = True
+                                yield event
+                            for event in recovery_events:
+                                yield event
+                            return
+
+                    if not isinstance(error, httpx.HTTPStatusError):
+                        self._transport._log_stream_transport_error(
+                            tag, req_tag, error, request_id=self._request_id
+                        )
+                    error_message = self._transport._get_error_message(
+                        error, self._request_id
+                    )
+
+                    if response is not None and not response.is_closed:
+                        await maybe_await_aclose(response)
+
+                    trace_event(
+                        stage="provider",
+                        event="provider.response.error",
+                        source="provider",
+                        provider=tag,
+                        error_message=error_message,
+                        exc_type=type(error).__name__,
+                        mid_stream=(
+                            sent_any_event
+                            or decision.committed
+                            or decision.has_buffered
+                        ),
+                    )
+                    if decision.committed or decision.has_buffered:
+                        if not decision.committed:
+                            for event in recovery_session.flush():
+                                sent_any_event = True
+                                yield event
+                        for event in emitted_tracker.iter_close_unclosed_blocks():
+                            yield event
+                        for event in emitted_tracker.iter_midstream_error_tail(
+                            error_message,
+                            request=self._request,
+                            input_tokens=self._input_tokens,
+                            log_raw_sse_events=(
+                                self._transport._config.log_raw_sse_events
+                            ),
+                        ):
+                            yield event
+                    else:
+                        recovery_session.discard()
+                        for event in self._transport._emit_error_events(
+                            request=self._request,
+                            input_tokens=self._input_tokens,
+                            error_message=error_message,
+                            sent_any_event=False,
+                        ):
+                            yield event
+                    return
+                finally:
+                    if response is not None and not response.is_closed:
+                        await maybe_await_aclose(response)
+
+    async def iter_stream_chunks(
+        self,
+        response: httpx.Response,
+        *,
+        state: Any,
+        thinking_enabled: bool,
+    ) -> AsyncIterator[str]:
+        """Yield chunks according to the provider's observable stream shape."""
+        if self._transport.stream_chunk_mode == "line" and isinstance(
+            state, NativeSseBlockPolicyState
+        ):
+            async for event in iter_sse_events(response):
+                output_event = self._transport._transform_stream_event(
+                    event,
+                    state,
+                    thinking_enabled=thinking_enabled,
+                )
+                if output_event is None:
+                    continue
+                for line in output_event.splitlines(keepends=True):
+                    yield line
+            return
+
+        if self._transport.stream_chunk_mode == "line":
+            async for chunk in iter_sse_lines(response):
+                yield chunk
+            return
+
+        async for event in iter_sse_events(response):
+            output_event = self._transport._transform_stream_event(
+                event,
+                state,
+                thinking_enabled=thinking_enabled,
+            )
+            if output_event is not None:
+                yield output_event
diff --git a/providers/transports/anthropic_messages/transport.py b/providers/transports/anthropic_messages/transport.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/anthropic_messages/transport.py
@@ -0,0 +1,227 @@
+"""Shared transport for providers with native Anthropic Messages endpoints."""
+
+from __future__ import annotations
+
+from collections.abc import AsyncIterator, Iterator
+from typing import Any, Literal
+
+import httpx
+
+from config.constants import ANTHROPIC_DEFAULT_MAX_OUTPUT_TOKENS
+from core.anthropic import iter_provider_stream_error_sse_events
+from core.anthropic.native_messages_request import (
+    build_base_native_anthropic_request_body,
+)
+from core.anthropic.native_sse_block_policy import (
+    NativeSseBlockPolicyState,
+    transform_native_sse_block_event,
+)
+from providers.base import BaseProvider, ProviderConfig
+from providers.error_mapping import (
+    extract_provider_error_detail,
+    map_error,
+    user_visible_message_for_mapped_provider_error,
+)
+from providers.model_listing import (
+    ProviderModelInfo,
+    extract_openai_model_ids,
+    model_infos_from_ids,
+)
+from providers.rate_limit import GlobalRateLimiter
+
+from .http import maybe_await_aclose, model_list_json, raise_for_status_with_body
+from .stream import AnthropicMessagesStreamRunner
+
+StreamChunkMode = Literal["line", "event"]
+
+
+class AnthropicMessagesTransport(BaseProvider):
+    """Base class for providers that stream from an Anthropic-compatible endpoint."""
+
+    stream_chunk_mode: StreamChunkMode = "line"
+
+    def __init__(
+        self,
+        config: ProviderConfig,
+        *,
+        provider_name: str,
+        default_base_url: str,
+    ):
+        super().__init__(config)
+        self._provider_name = provider_name
+        self._api_key = config.api_key
+        self._base_url = (config.base_url or default_base_url).rstrip("/")
+        self._global_rate_limiter = GlobalRateLimiter.get_scoped_instance(
+            provider_name.lower(),
+            rate_limit=config.rate_limit,
+            rate_window=config.rate_window,
+            max_concurrency=config.max_concurrency,
+        )
+        self._client = httpx.AsyncClient(
+            base_url=self._base_url,
+            proxy=config.proxy or None,
+            timeout=httpx.Timeout(
+                config.http_read_timeout,
+                connect=config.http_connect_timeout,
+                read=config.http_read_timeout,
+                write=config.http_write_timeout,
+            ),
+        )
+
+    async def cleanup(self) -> None:
+        """Release HTTP client resources."""
+        await self._client.aclose()
+
+    async def list_model_ids(self) -> frozenset[str]:
+        """Return model ids from an OpenAI-compatible ``/models`` endpoint."""
+        return frozenset(info.model_id for info in await self.list_model_infos())
+
+    async def list_model_infos(self) -> frozenset[ProviderModelInfo]:
+        """Return model ids plus optional metadata from a ``/models`` endpoint."""
+        response = await self._send_model_list_request()
+        try:
+            payload = model_list_json(response, provider_name=self._provider_name)
+            return self._extract_model_infos_from_model_list_payload(payload)
+        finally:
+            await maybe_await_aclose(response)
+
+    async def _send_model_list_request(self) -> httpx.Response:
+        """Query the provider endpoint that advertises available model ids."""
+        return await self._client.get(
+            "/models",
+            headers=self._model_list_headers(),
+        )
+
+    def _model_list_headers(self) -> dict[str, str]:
+        """Return headers for model-list requests."""
+        return {}
+
+    def _extract_model_ids_from_model_list_payload(
+        self, payload: Any
+    ) -> frozenset[str]:
+        """Parse the provider model-list response body."""
+        return extract_openai_model_ids(payload, provider_name=self._provider_name)
+
+    def _extract_model_infos_from_model_list_payload(
+        self, payload: Any
+    ) -> frozenset[ProviderModelInfo]:
+        """Parse provider model metadata; default to unknown capabilities."""
+        return model_infos_from_ids(
+            self._extract_model_ids_from_model_list_payload(payload)
+        )
+
+    def _request_headers(self) -> dict[str, str]:
+        """Return headers for the native messages request."""
+        return {"Content-Type": "application/json"}
+
+    def _build_request_body(
+        self, request: Any, thinking_enabled: bool | None = None
+    ) -> dict:
+        """Build a native Anthropic request body."""
+        thinking_enabled = self._is_thinking_enabled(request, thinking_enabled)
+        return build_base_native_anthropic_request_body(
+            request,
+            default_max_tokens=ANTHROPIC_DEFAULT_MAX_OUTPUT_TOKENS,
+            thinking_enabled=thinking_enabled,
+        )
+
+    async def _send_stream_request(self, body: dict) -> httpx.Response:
+        """Create a streaming messages response."""
+        request = self._client.build_request(
+            "POST",
+            "/messages",
+            json=body,
+            headers=self._request_headers(),
+        )
+        return await self._client.send(request, stream=True)
+
+    async def _raise_for_status(
+        self, response: httpx.Response, *, req_tag: str
+    ) -> None:
+        """Raise for non-200 responses after attaching safe error metadata."""
+        await raise_for_status_with_body(
+            response,
+            provider_name=self._provider_name,
+            req_tag=req_tag,
+            log_api_error_tracebacks=self._config.log_api_error_tracebacks,
+        )
+
+    def _new_stream_state(self, request: Any, *, thinking_enabled: bool) -> Any:
+        """Return per-stream provider state for event transformation."""
+        if self.stream_chunk_mode == "line":
+            return NativeSseBlockPolicyState()
+        return None
+
+    def _transform_stream_event(
+        self,
+        event: str,
+        state: Any,
+        *,
+        thinking_enabled: bool,
+    ) -> str | None:
+        """Transform or drop a grouped SSE event before yielding it downstream."""
+        if isinstance(state, NativeSseBlockPolicyState):
+            return transform_native_sse_block_event(
+                event, state, thinking_enabled=thinking_enabled
+            )
+        return event
+
+    def _get_error_message(self, error: Exception, request_id: str | None) -> str:
+        """Map an exception into a user-facing provider error message."""
+        mapped_error = map_error(error, rate_limiter=self._global_rate_limiter)
+        return user_visible_message_for_mapped_provider_error(
+            mapped_error,
+            provider_name=self._provider_name,
+            read_timeout_s=self._config.http_read_timeout,
+            detail=extract_provider_error_detail(error),
+            request_id=request_id,
+        )
+
+    async def _validated_stream_send(
+        self, body: dict, *, req_tag: str
+    ) -> httpx.Response:
+        """Send request and raise mapped HTTP errors before yielding body chunks."""
+        send_response = await self._send_stream_request(body)
+        if send_response.status_code != 200:
+            try:
+                await self._raise_for_status(send_response, req_tag=req_tag)
+            finally:
+                if not send_response.is_closed:
+                    await maybe_await_aclose(send_response)
+        return send_response
+
+    def _emit_error_events(
+        self,
+        *,
+        request: Any,
+        input_tokens: int,
+        error_message: str,
+        sent_any_event: bool,
+    ) -> Iterator[str]:
+        """Emit the same Anthropic message lifecycle used by OpenAI-chat providers."""
+        yield from iter_provider_stream_error_sse_events(
+            request=request,
+            input_tokens=input_tokens,
+            error_message=error_message,
+            sent_any_event=sent_any_event,
+            log_raw_sse_events=self._config.log_raw_sse_events,
+        )
+
+    async def stream_response(
+        self,
+        request: Any,
+        input_tokens: int = 0,
+        *,
+        request_id: str | None = None,
+        thinking_enabled: bool | None = None,
+    ) -> AsyncIterator[str]:
+        """Stream response via a native Anthropic-compatible messages endpoint."""
+        runner = AnthropicMessagesStreamRunner(
+            self,
+            request=request,
+            input_tokens=input_tokens,
+            request_id=request_id,
+            thinking_enabled=thinking_enabled,
+        )
+        async for event in runner.run():
+            yield event
diff --git a/providers/transports/openai_chat/__init__.py b/providers/transports/openai_chat/__init__.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/openai_chat/__init__.py
@@ -0,0 +1,5 @@
+"""OpenAI-compatible chat transport family."""
+
+from .transport import OpenAIChatTransport
+
+__all__ = ["OpenAIChatTransport"]
diff --git a/providers/transports/openai_chat/recovery.py b/providers/transports/openai_chat/recovery.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/openai_chat/recovery.py
@@ -0,0 +1,217 @@
+"""OpenAI-chat stream recovery event construction."""
+
+from __future__ import annotations
+
+from collections.abc import Awaitable, Callable, Iterator
+from typing import Any
+
+from core.anthropic import SSEBuilder
+from core.anthropic.stream_recovery import (
+    MIDSTREAM_RECOVERY_ATTEMPTS,
+    accept_tool_json_repair,
+    continuation_suffix,
+    is_retryable_stream_error,
+    make_openai_text_recovery_body,
+    make_openai_tool_repair_body,
+    parse_complete_tool_input,
+    tool_schemas_by_name,
+)
+from core.trace import trace_event
+
+from .tool_calls import all_started_tools_complete, started_tool_states
+
+CreateStream = Callable[[dict[str, Any]], Awaitable[tuple[Any, dict[str, Any]]]]
+
+
+class OpenAIChatRecovery:
+    """Construct recovery events for interrupted OpenAI-chat streams."""
+
+    def __init__(self, *, provider_name: str, create_stream: CreateStream) -> None:
+        self._provider_name = provider_name
+        self._create_stream = create_stream
+
+    async def collect_text(self, body: dict[str, Any]) -> tuple[str, str]:
+        """Collect text/reasoning from an internal recovery request."""
+        last_error: Exception | None = None
+        for attempt in range(MIDSTREAM_RECOVERY_ATTEMPTS):
+            try:
+                stream, _ = await self._create_stream(body)
+                text_parts: list[str] = []
+                thinking_parts: list[str] = []
+                async for chunk in stream:
+                    if not getattr(chunk, "choices", None):
+                        continue
+                    choice = chunk.choices[0]
+                    delta = choice.delta
+                    if delta is None:
+                        continue
+                    reasoning = getattr(delta, "reasoning_content", None)
+                    if isinstance(reasoning, str) and reasoning:
+                        thinking_parts.append(reasoning)
+                    content = getattr(delta, "content", None)
+                    if isinstance(content, str) and content:
+                        text_parts.append(content)
+                return "".join(text_parts), "".join(thinking_parts)
+            except Exception as error:
+                last_error = error
+                if not is_retryable_stream_error(error):
+                    raise
+                trace_event(
+                    stage="provider",
+                    event="provider.recovery.retry",
+                    source="provider",
+                    provider=self._provider_name,
+                    recovery_kind="openai_text",
+                    attempt=attempt + 1,
+                    max_attempts=MIDSTREAM_RECOVERY_ATTEMPTS,
+                    exc_type=type(error).__name__,
+                )
+        if last_error is not None:
+            raise last_error
+        return "", ""
+
+    async def events(
+        self,
+        *,
+        body: dict[str, Any],
+        sse: SSEBuilder,
+        request: Any,
+        request_id: str | None,
+        error: Exception,
+        tool_argument_alias_buffers: dict[int, str],
+    ) -> list[str] | None:
+        """Build recovery events, or return None when recovery is impossible."""
+        if not is_retryable_stream_error(error):
+            return None
+
+        if sse.blocks.has_emitted_tool_block():
+            if not all_started_tools_complete(sse, request):
+                repair_events = await self._repair_tool_args(
+                    body=body,
+                    sse=sse,
+                    request=request,
+                    tool_argument_alias_buffers=tool_argument_alias_buffers,
+                )
+                if repair_events is None:
+                    return None
+            else:
+                repair_events = []
+            events = list(repair_events)
+            events.extend(sse.close_all_blocks())
+            events.append(sse.message_delta("tool_use", sse.estimate_output_tokens()))
+            events.append(sse.message_stop())
+            trace_event(
+                stage="provider",
+                event="provider.recovery.tool_salvaged",
+                source="provider",
+                provider=self._provider_name,
+                request_id=request_id,
+            )
+            return events
+
+        partial_text = sse.accumulated_text
+        partial_thinking = sse.accumulated_reasoning
+        if not partial_text and not partial_thinking:
+            return None
+
+        recovery_body = make_openai_text_recovery_body(body, partial_text)
+        text, thinking = await self.collect_text(recovery_body)
+        text_suffix = continuation_suffix(partial_text, text)
+        thinking_suffix = continuation_suffix(partial_thinking, thinking)
+        events: list[str] = []
+        if thinking_suffix:
+            for event in sse.ensure_thinking_block():
+                events.append(event)
+            events.append(sse.emit_thinking_delta(thinking_suffix))
+        if text_suffix:
+            for event in sse.ensure_text_block():
+                events.append(event)
+            events.append(sse.emit_text_delta(text_suffix))
+        if not events:
+            return None
+        events.extend(sse.close_all_blocks())
+        events.append(sse.message_delta("end_turn", sse.estimate_output_tokens()))
+        events.append(sse.message_stop())
+        trace_event(
+            stage="provider",
+            event="provider.recovery.continued",
+            source="provider",
+            provider=self._provider_name,
+            request_id=request_id,
+        )
+        return events
+
+    def emit_error_tail(self, sse: SSEBuilder, error_message: str) -> Iterator[str]:
+        """Emit the canonical OpenAI-chat final error tail."""
+        yield from sse.close_all_blocks()
+        if sse.blocks.has_emitted_tool_block():
+            yield sse.emit_top_level_error(error_message)
+        else:
+            yield from sse.emit_error(error_message)
+        yield sse.message_delta("end_turn", 1)
+        yield sse.message_stop()
+
+    async def _repair_tool_args(
+        self,
+        *,
+        body: dict[str, Any],
+        sse: SSEBuilder,
+        request: Any,
+        tool_argument_alias_buffers: dict[int, str],
+    ) -> list[str] | None:
+        schemas = tool_schemas_by_name(request)
+        events: list[str] = []
+        for tool_index, state in started_tool_states(sse):
+            emitted_prefix = "".join(state.contents)
+            repair_prefix = emitted_prefix
+            if not repair_prefix and state.name == "Task" and state.task_arg_buffer:
+                repair_prefix = state.task_arg_buffer
+            if not repair_prefix and tool_index in tool_argument_alias_buffers:
+                repair_prefix = tool_argument_alias_buffers[tool_index]
+            if (
+                parse_complete_tool_input(repair_prefix, state.name, schemas)
+                is not None
+            ):
+                if not emitted_prefix:
+                    yield_text = repair_prefix
+                    if yield_text:
+                        events.append(sse.emit_tool_delta(tool_index, yield_text))
+                continue
+
+            schema = schemas.get(state.name)
+            recovery_body = make_openai_tool_repair_body(
+                body,
+                tool_name=state.name,
+                prefix=repair_prefix,
+                input_schema=schema.input_schema if schema is not None else None,
+            )
+            accepted_suffix: str | None = None
+            for attempt in range(MIDSTREAM_RECOVERY_ATTEMPTS):
+                text, _ = await self.collect_text(recovery_body)
+                repair = accept_tool_json_repair(
+                    repair_prefix,
+                    text,
+                    tool_name=state.name,
+                    schemas=schemas,
+                )
+                if repair is not None:
+                    accepted_suffix = repair.suffix
+                    trace_event(
+                        stage="provider",
+                        event="provider.recovery.tool_repaired",
+                        source="provider",
+                        provider=self._provider_name,
+                        tool_name=state.name,
+                        attempt=attempt + 1,
+                    )
+                    break
+            if accepted_suffix is None:
+                return None
+            to_emit = (
+                accepted_suffix if emitted_prefix else repair_prefix + accepted_suffix
+            )
+            if to_emit:
+                events.append(sse.emit_tool_delta(tool_index, to_emit))
+        if not all_started_tools_complete(sse, request):
+            return None
+        return events
diff --git a/providers/transports/openai_chat/stream.py b/providers/transports/openai_chat/stream.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/openai_chat/stream.py
@@ -0,0 +1,384 @@
+"""Per-request OpenAI-chat stream runner."""
+
+from __future__ import annotations
+
+import asyncio
+import uuid
+from collections.abc import AsyncIterator, Iterator
+from typing import Any
+
+from loguru import logger
+
+from core.anthropic import (
+    ContentType,
+    HeuristicToolParser,
+    SSEBuilder,
+    ThinkTagParser,
+    map_stop_reason,
+)
+from core.anthropic.stream_recovery import TruncatedProviderStreamError
+from core.anthropic.stream_recovery_session import (
+    StreamFailureAction,
+    StreamRecoverySession,
+)
+from core.trace import provider_chat_body_snapshot, trace_event
+from providers.error_mapping import map_error
+
+from .recovery import OpenAIChatRecovery
+from .tool_calls import (
+    OpenAIToolCallAssembler,
+    all_started_tools_complete,
+    has_committed_sse_output,
+    iter_heuristic_tool_use_sse,
+    tool_call_extra_content,
+)
+
+
+class OpenAIChatStreamRunner:
+    """Own mutable state for one OpenAI-chat provider stream."""
+
+    def __init__(
+        self,
+        transport: Any,
+        *,
+        request: Any,
+        input_tokens: int,
+        request_id: str | None,
+        thinking_enabled: bool | None,
+    ) -> None:
+        self._transport = transport
+        self._request = request
+        self._input_tokens = input_tokens
+        self._request_id = request_id
+        self._thinking_enabled = thinking_enabled
+        self._message_id = f"msg_{uuid.uuid4()}"
+        self._tool_calls = OpenAIToolCallAssembler(
+            record_extra_content=transport._record_tool_call_extra_content
+        )
+        self._recovery = OpenAIChatRecovery(
+            provider_name=transport._provider_name,
+            create_stream=transport._create_stream,
+        )
+
+    async def run(self) -> AsyncIterator[str]:
+        """Stream response in Anthropic SSE format."""
+        tag = self._transport._provider_name
+        req_tag = f" request_id={self._request_id}" if self._request_id else ""
+        sse = self._new_sse_builder()
+        recovery_session = StreamRecoverySession(
+            provider_name=tag,
+            request_id=self._request_id,
+        )
+
+        def hold_event(event: str) -> Iterator[str]:
+            yield from recovery_session.push(event)
+
+        def hold_events(events: Iterator[str]) -> Iterator[str]:
+            for event in events:
+                yield from hold_event(event)
+
+        body = self._transport._build_request_body(
+            self._request, thinking_enabled=self._thinking_enabled
+        )
+        thinking_enabled = self._transport._is_thinking_enabled(
+            self._request, self._thinking_enabled
+        )
+        trace_event(
+            stage="provider",
+            event="provider.request.sent",
+            source="provider",
+            provider=tag,
+            gateway_model=self._request.model,
+            downstream_model=body.get("model"),
+            message_count=len(body.get("messages", [])),
+            tool_count=len(body.get("tools", [])),
+            body=provider_chat_body_snapshot(body),
+        )
+
+        yield sse.message_start()
+
+        think_parser = ThinkTagParser()
+        heuristic_parser = HeuristicToolParser()
+        finish_reason = None
+        usage_info = None
+        tool_argument_aliases: dict[str, dict[str, str]] = {}
+        tool_argument_alias_buffers: dict[int, str] = {}
+
+        async with self._transport._global_rate_limiter.concurrency_slot():
+            while True:
+                stream_opened = False
+                try:
+                    stream, body = await self._transport._create_stream(body)
+                    stream_opened = True
+                    tool_argument_aliases = self._transport._tool_argument_aliases(body)
+                    async for chunk in stream:
+                        if getattr(chunk, "usage", None):
+                            usage_info = chunk.usage
+
+                        if not chunk.choices:
+                            continue
+
+                        choice = chunk.choices[0]
+                        delta = choice.delta
+                        if delta is None:
+                            continue
+
+                        if choice.finish_reason:
+                            finish_reason = choice.finish_reason
+                            logger.debug("{} finish_reason: {}", tag, finish_reason)
+
+                        reasoning = getattr(delta, "reasoning_content", None)
+                        if thinking_enabled and reasoning:
+                            for event in hold_events(sse.ensure_thinking_block()):
+                                yield event
+                            for event in hold_event(sse.emit_thinking_delta(reasoning)):
+                                yield event
+
+                        for event in self._transport._handle_extra_reasoning(
+                            delta,
+                            sse,
+                            thinking_enabled=thinking_enabled,
+                        ):
+                            for out_event in hold_event(event):
+                                yield out_event
+
+                        if delta.content:
+                            for part in think_parser.feed(delta.content):
+                                if part.type == ContentType.THINKING:
+                                    if not thinking_enabled:
+                                        continue
+                                    for event in hold_events(
+                                        sse.ensure_thinking_block()
+                                    ):
+                                        yield event
+                                    for event in hold_event(
+                                        sse.emit_thinking_delta(part.content)
+                                    ):
+                                        yield event
+                                else:
+                                    (
+                                        filtered_text,
+                                        detected_tools,
+                                    ) = heuristic_parser.feed(part.content)
+
+                                    if filtered_text:
+                                        for event in hold_events(
+                                            sse.ensure_text_block()
+                                        ):
+                                            yield event
+                                        for event in hold_event(
+                                            sse.emit_text_delta(filtered_text)
+                                        ):
+                                            yield event
+
+                                    for tool_use in detected_tools:
+                                        for event in iter_heuristic_tool_use_sse(
+                                            sse, tool_use
+                                        ):
+                                            for out_event in hold_event(event):
+                                                yield out_event
+
+                        if delta.tool_calls:
+                            for event in hold_events(sse.close_content_blocks()):
+                                yield event
+                            for tc in delta.tool_calls:
+                                extra_content = tool_call_extra_content(tc)
+                                tc_info = {
+                                    "index": tc.index,
+                                    "id": tc.id,
+                                    "function": {
+                                        "name": tc.function.name,
+                                        "arguments": tc.function.arguments,
+                                    },
+                                }
+                                if extra_content:
+                                    tc_info["extra_content"] = extra_content
+                                for event in self._tool_calls.process_tool_call(
+                                    tc_info,
+                                    sse,
+                                    tool_argument_aliases=tool_argument_aliases,
+                                    tool_argument_alias_buffers=tool_argument_alias_buffers,
+                                ):
+                                    for out_event in hold_event(event):
+                                        yield out_event
+
+                    if finish_reason is None:
+                        raise TruncatedProviderStreamError(
+                            "Provider stream ended without finish_reason."
+                        )
+                    break
+
+                except asyncio.CancelledError, GeneratorExit:
+                    raise
+                except Exception as error:
+                    generated_output = has_committed_sse_output(sse)
+                    complete_tool_salvageable = (
+                        generated_output
+                        and sse.blocks.has_emitted_tool_block()
+                        and all_started_tools_complete(sse, self._request)
+                    )
+                    decision = recovery_session.advance_failure(
+                        error,
+                        stream_opened=stream_opened,
+                        generated_output=generated_output,
+                        complete_tool_salvageable=complete_tool_salvageable,
+                    )
+                    if decision.action == StreamFailureAction.EARLY_RETRY:
+                        sse = self._new_sse_builder()
+                        think_parser = ThinkTagParser()
+                        heuristic_parser = HeuristicToolParser()
+                        finish_reason = None
+                        usage_info = None
+                        tool_argument_aliases = {}
+                        tool_argument_alias_buffers = {}
+                        continue
+
+                    if decision.action == StreamFailureAction.MIDSTREAM_RECOVERY:
+                        try:
+                            recovery_events = await self._recovery.events(
+                                body=body,
+                                sse=sse,
+                                request=self._request,
+                                request_id=self._request_id,
+                                error=error,
+                                tool_argument_alias_buffers=tool_argument_alias_buffers,
+                            )
+                        except Exception as recovery_error:
+                            trace_event(
+                                stage="provider",
+                                event="provider.recovery.failed",
+                                source="provider",
+                                provider=tag,
+                                request_id=self._request_id,
+                                exc_type=type(recovery_error).__name__,
+                            )
+                            recovery_events = None
+                        if recovery_events is not None:
+                            for event in recovery_session.flush_uncommitted(decision):
+                                yield event
+                            for event in recovery_events:
+                                yield event
+                            return
+
+                    self._transport._log_stream_transport_error(
+                        tag, req_tag, error, request_id=self._request_id
+                    )
+                    error_message = self._transport._openai_error_message(
+                        error, self._request_id
+                    )
+                    trace_event(
+                        stage="provider",
+                        event="provider.response.error",
+                        source="provider",
+                        provider=tag,
+                        error_message=error_message,
+                        mapped_error_type=type(
+                            map_error(
+                                error,
+                                rate_limiter=self._transport._global_rate_limiter,
+                            )
+                        ).__name__,
+                    )
+                    if not decision.committed and decision.has_buffered:
+                        for event in recovery_session.flush():
+                            yield event
+                    elif not decision.committed:
+                        recovery_session.discard()
+                        sse = self._new_sse_builder()
+                    for event in self._recovery.emit_error_tail(sse, error_message):
+                        yield event
+                    return
+
+        remaining = think_parser.flush()
+        if remaining:
+            if remaining.type == ContentType.THINKING:
+                if not thinking_enabled:
+                    remaining = None
+                else:
+                    for event in hold_events(sse.ensure_thinking_block()):
+                        yield event
+                    for event in hold_event(sse.emit_thinking_delta(remaining.content)):
+                        yield event
+            if remaining and remaining.type == ContentType.TEXT:
+                for event in hold_events(sse.ensure_text_block()):
+                    yield event
+                for event in hold_event(sse.emit_text_delta(remaining.content)):
+                    yield event
+
+        for tool_use in heuristic_parser.flush():
+            for event in iter_heuristic_tool_use_sse(sse, tool_use):
+                for out_event in hold_event(event):
+                    yield out_event
+
+        has_started_tool = any(s.started for s in sse.blocks.tool_states.values())
+        has_content_blocks = (
+            sse.blocks.text_index != -1
+            or sse.blocks.thinking_index != -1
+            or has_started_tool
+        )
+        if not has_content_blocks or (
+            not has_started_tool
+            and not sse.accumulated_text.strip()
+            and sse.accumulated_reasoning.strip()
+        ):
+            for event in hold_events(sse.ensure_text_block()):
+                yield event
+            for event in hold_event(sse.emit_text_delta(" ")):
+                yield event
+
+        for event in self._tool_calls.flush_tool_argument_alias_buffers(
+            sse, tool_argument_aliases, tool_argument_alias_buffers
+        ):
+            for out_event in hold_event(event):
+                yield out_event
+
+        for event in self._tool_calls.flush_task_arg_buffers(sse):
+            for out_event in hold_event(event):
+                yield out_event
+
+        for event in hold_events(sse.close_all_blocks()):
+            yield event
+
+        completion = (
+            getattr(usage_info, "completion_tokens", None)
+            if usage_info is not None
+            else None
+        )
+        if isinstance(completion, int):
+            output_tokens = completion
+        else:
+            output_tokens = sse.estimate_output_tokens()
+        if usage_info and hasattr(usage_info, "prompt_tokens"):
+            provider_input = usage_info.prompt_tokens
+            if isinstance(provider_input, int):
+                logger.debug(
+                    "TOKEN_ESTIMATE: our={} provider={} diff={:+d}",
+                    self._input_tokens,
+                    provider_input,
+                    provider_input - self._input_tokens,
+                )
+        trace_event(
+            stage="provider",
+            event="provider.response.completed",
+            source="provider",
+            provider=tag,
+            finish_reason=(None if finish_reason is None else str(finish_reason)),
+            output_tokens=output_tokens,
+            prompt_tokens_estimate=self._input_tokens,
+        )
+        for event in hold_event(
+            sse.message_delta(map_stop_reason(finish_reason), output_tokens)
+        ):
+            yield event
+        for event in hold_event(sse.message_stop()):
+            yield event
+        for event in recovery_session.flush():
+            yield event
+
+    def _new_sse_builder(self) -> SSEBuilder:
+        return SSEBuilder(
+            self._message_id,
+            self._request.model,
+            self._input_tokens,
+            log_raw_events=self._transport._config.log_raw_sse_events,
+        )
diff --git a/providers/transports/openai_chat/tool_calls.py b/providers/transports/openai_chat/tool_calls.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/openai_chat/tool_calls.py
@@ -0,0 +1,293 @@
+"""OpenAI-chat tool-call assembly helpers."""
+
+from __future__ import annotations
+
+import json
+import uuid
+from collections.abc import Callable, Iterator
+from typing import Any
+
+from core.anthropic import SSEBuilder
+from core.anthropic.stream_recovery import (
+    parse_complete_tool_input,
+    tool_schemas_by_name,
+)
+
+RecordToolExtraContent = Callable[[str, dict[str, Any]], None]
+
+
+def iter_heuristic_tool_use_sse(
+    sse: SSEBuilder, tool_use: dict[str, Any]
+) -> Iterator[str]:
+    """Emit SSE for one heuristic tool_use block."""
+    if tool_use.get("name") == "Task" and isinstance(tool_use.get("input"), dict):
+        task_input = tool_use["input"]
+        if task_input.get("run_in_background") is not False:
+            task_input["run_in_background"] = False
+    yield from sse.close_content_blocks()
+    block_idx = sse.blocks.allocate_index()
+    yield sse.content_block_start(
+        block_idx,
+        "tool_use",
+        id=tool_use["id"],
+        name=tool_use["name"],
+    )
+    yield sse.content_block_delta(
+        block_idx,
+        "input_json_delta",
+        json.dumps(tool_use["input"]),
+    )
+    yield sse.content_block_stop(block_idx)
+
+
+def tool_call_extra_content(tool_call: Any) -> dict[str, Any] | None:
+    """Return provider-specific extra tool-call metadata from OpenAI objects."""
+    if isinstance(tool_call, dict):
+        value = tool_call.get("extra_content")
+        return value if isinstance(value, dict) else None
+
+    value = getattr(tool_call, "extra_content", None)
+    if isinstance(value, dict):
+        return value
+
+    model_extra = getattr(tool_call, "model_extra", None)
+    if isinstance(model_extra, dict):
+        value = model_extra.get("extra_content")
+        if isinstance(value, dict):
+            return value
+
+    pydantic_extra = getattr(tool_call, "__pydantic_extra__", None)
+    if isinstance(pydantic_extra, dict):
+        value = pydantic_extra.get("extra_content")
+        if isinstance(value, dict):
+            return value
+
+    return None
+
+
+def has_committed_sse_output(sse: SSEBuilder) -> bool:
+    """Return whether any assistant content escaped the builder."""
+    return (
+        sse.blocks.text_index != -1
+        or sse.blocks.thinking_index != -1
+        or sse.blocks.has_emitted_tool_block()
+    )
+
+
+def started_tool_states(sse: SSEBuilder) -> list[tuple[int, Any]]:
+    """Return started tool states in stream order."""
+    return [
+        (tool_index, state)
+        for tool_index, state in sse.blocks.tool_states.items()
+        if state.started
+    ]
+
+
+def all_started_tools_complete(sse: SSEBuilder, request: Any) -> bool:
+    """Return whether every emitted tool block has schema-valid input."""
+    schemas = tool_schemas_by_name(request)
+    started = started_tool_states(sse)
+    if not started:
+        return False
+    for _, state in started:
+        raw = "".join(state.contents)
+        if parse_complete_tool_input(raw, state.name, schemas) is None:
+            return False
+    return True
+
+
+class OpenAIToolCallAssembler:
+    """Assemble OpenAI tool-call deltas into Anthropic SSE tool blocks."""
+
+    def __init__(
+        self, *, record_extra_content: RecordToolExtraContent | None = None
+    ) -> None:
+        self._record_extra_content = record_extra_content
+
+    def process_tool_call(
+        self,
+        tc: dict[str, Any],
+        sse: SSEBuilder,
+        *,
+        tool_argument_aliases: dict[str, dict[str, str]] | None = None,
+        tool_argument_alias_buffers: dict[int, str] | None = None,
+    ) -> Iterator[str]:
+        """Process a single tool-call delta and yield Anthropic SSE events."""
+        raw_index = tc.get("index", 0)
+        tc_index = raw_index if isinstance(raw_index, int) else 0
+        if tc_index < 0:
+            tc_index = len(sse.blocks.tool_states)
+
+        fn_delta = tc.get("function", {})
+        incoming_name = fn_delta.get("name")
+        arguments = fn_delta.get("arguments", "") or ""
+
+        if tc.get("id") is not None:
+            sse.blocks.set_stream_tool_id(tc_index, tc.get("id"))
+
+        raw_extra_content = tc.get("extra_content")
+        extra_content = (
+            raw_extra_content
+            if isinstance(raw_extra_content, dict) and raw_extra_content
+            else None
+        )
+        if extra_content:
+            sse.blocks.set_tool_extra_content(tc_index, extra_content)
+
+        if incoming_name is not None:
+            sse.blocks.register_tool_name(tc_index, incoming_name)
+
+        state = sse.blocks.tool_states.get(tc_index)
+        resolved_id = (state.tool_id if state and state.tool_id else None) or tc.get(
+            "id"
+        )
+        resolved_name = (state.name if state else "") or ""
+
+        if not state or not state.started:
+            name_ok = bool((resolved_name or "").strip())
+            if name_ok:
+                tool_id = str(resolved_id) if resolved_id else f"tool_{uuid.uuid4()}"
+                display_name = (resolved_name or "").strip() or "tool_call"
+                start_extra_content = state.extra_content if state else extra_content
+                if start_extra_content:
+                    self._record_tool_call_extra_content(tool_id, start_extra_content)
+                yield sse.start_tool_block(
+                    tc_index,
+                    tool_id,
+                    display_name,
+                    extra_content=start_extra_content,
+                )
+                state = sse.blocks.tool_states[tc_index]
+                if state.pre_start_args:
+                    pre = state.pre_start_args
+                    state.pre_start_args = ""
+                    yield from self._emit_tool_arg_delta(
+                        sse,
+                        tc_index,
+                        pre,
+                        tool_argument_aliases=tool_argument_aliases,
+                        tool_argument_alias_buffers=tool_argument_alias_buffers,
+                    )
+
+        state = sse.blocks.tool_states.get(tc_index)
+        if state is not None and state.tool_id and extra_content:
+            self._record_tool_call_extra_content(state.tool_id, extra_content)
+        if not arguments:
+            return
+        if state is None or not state.started:
+            state = sse.blocks.ensure_tool_state(tc_index)
+            if not (resolved_name or "").strip():
+                state.pre_start_args += arguments
+                return
+
+        yield from self._emit_tool_arg_delta(
+            sse,
+            tc_index,
+            arguments,
+            tool_argument_aliases=tool_argument_aliases,
+            tool_argument_alias_buffers=tool_argument_alias_buffers,
+        )
+
+    def flush_task_arg_buffers(self, sse: SSEBuilder) -> Iterator[str]:
+        """Emit buffered Task args as a single JSON delta."""
+        for tool_index, out in sse.blocks.flush_task_arg_buffers():
+            yield sse.emit_tool_delta(tool_index, out)
+
+    def flush_tool_argument_alias_buffers(
+        self,
+        sse: SSEBuilder,
+        tool_argument_aliases: dict[str, dict[str, str]],
+        tool_argument_alias_buffers: dict[int, str],
+    ) -> Iterator[str]:
+        """Emit remaining aliased args without losing malformed JSON."""
+        for tool_index, buffered_args in list(tool_argument_alias_buffers.items()):
+            if not buffered_args:
+                tool_argument_alias_buffers.pop(tool_index, None)
+                continue
+            state = sse.blocks.tool_states.get(tool_index)
+            if state is None or state.name == "Task":
+                continue
+            aliases = tool_argument_aliases.get(state.name, {})
+            if not aliases:
+                continue
+            restored = self._restore_aliased_tool_arguments(buffered_args, aliases)
+            yield sse.emit_tool_delta(
+                tool_index,
+                restored if restored is not None else buffered_args,
+            )
+            tool_argument_alias_buffers.pop(tool_index, None)
+
+    def _emit_tool_arg_delta(
+        self,
+        sse: SSEBuilder,
+        tc_index: int,
+        args: str,
+        *,
+        tool_argument_aliases: dict[str, dict[str, str]] | None = None,
+        tool_argument_alias_buffers: dict[int, str] | None = None,
+    ) -> Iterator[str]:
+        """Emit one argument fragment for a started tool block."""
+        if not args:
+            return
+        state = sse.blocks.tool_states.get(tc_index)
+        if state is None:
+            return
+        if state.name == "Task":
+            parsed = sse.blocks.buffer_task_args(tc_index, args)
+            if parsed is not None:
+                yield sse.emit_tool_delta(tc_index, json.dumps(parsed))
+            return
+        aliases = (
+            tool_argument_aliases.get(state.name, {}) if tool_argument_aliases else {}
+        )
+        if aliases:
+            if tool_argument_alias_buffers is None:
+                restored = self._restore_aliased_tool_arguments(args, aliases)
+                if restored is not None:
+                    yield sse.emit_tool_delta(tc_index, restored)
+                return
+
+            buffered_args = tool_argument_alias_buffers.get(tc_index, "") + args
+            restored = self._restore_aliased_tool_arguments(buffered_args, aliases)
+            if restored is None:
+                tool_argument_alias_buffers[tc_index] = buffered_args
+                return
+            tool_argument_alias_buffers.pop(tc_index, None)
+            yield sse.emit_tool_delta(tc_index, restored)
+            return
+        yield sse.emit_tool_delta(tc_index, args)
+
+    def _restore_aliased_tool_arguments(
+        self, argument_json: str, aliases: dict[str, str]
+    ) -> str | None:
+        try:
+            parsed = json.loads(argument_json)
+        except json.JSONDecodeError:
+            return None
+        if not isinstance(parsed, dict):
+            return argument_json
+        restored = self._restore_aliased_tool_argument_value(parsed, aliases)
+        return json.dumps(restored)
+
+    def _restore_aliased_tool_argument_value(
+        self, value: Any, aliases: dict[str, str]
+    ) -> Any:
+        if isinstance(value, dict):
+            return {
+                aliases.get(key, key): self._restore_aliased_tool_argument_value(
+                    item, aliases
+                )
+                for key, item in value.items()
+            }
+        if isinstance(value, list):
+            return [
+                self._restore_aliased_tool_argument_value(item, aliases)
+                for item in value
+            ]
+        return value
+
+    def _record_tool_call_extra_content(
+        self, tool_call_id: str, extra_content: dict[str, Any]
+    ) -> None:
+        if self._record_extra_content is not None:
+            self._record_extra_content(tool_call_id, extra_content)
diff --git a/providers/transports/openai_chat/transport.py b/providers/transports/openai_chat/transport.py
new file mode 100644
--- /dev/null
+++ b/providers/transports/openai_chat/transport.py
@@ -0,0 +1,158 @@
+"""OpenAI-compatible chat transport base."""
+
+from __future__ import annotations
+
+from abc import abstractmethod
+from collections.abc import AsyncIterator, Iterator
+from typing import Any
+
+import httpx
+from loguru import logger
+from openai import AsyncOpenAI
+
+from core.anthropic import SSEBuilder
+from providers.base import BaseProvider, ProviderConfig
+from providers.error_mapping import (
+    extract_provider_error_detail,
+    map_error,
+    user_visible_message_for_mapped_provider_error,
+)
+from providers.model_listing import extract_openai_model_ids
+from providers.rate_limit import GlobalRateLimiter
+
+from .stream import OpenAIChatStreamRunner
+
+
+class OpenAIChatTransport(BaseProvider):
+    """Base for OpenAI-compatible ``/chat/completions`` adapters."""
+
+    def __init__(
+        self,
+        config: ProviderConfig,
+        *,
+        provider_name: str,
+        base_url: str,
+        api_key: str,
+    ):
+        super().__init__(config)
+        self._provider_name = provider_name
+        self._api_key = api_key
+        self._base_url = base_url.rstrip("/")
+        self._global_rate_limiter = GlobalRateLimiter.get_scoped_instance(
+            provider_name.lower(),
+            rate_limit=config.rate_limit,
+            rate_window=config.rate_window,
+            max_concurrency=config.max_concurrency,
+        )
+        http_client = None
+        if config.proxy:
+            http_client = httpx.AsyncClient(
+                proxy=config.proxy,
+                timeout=httpx.Timeout(
+                    config.http_read_timeout,
+                    connect=config.http_connect_timeout,
+                    read=config.http_read_timeout,
+                    write=config.http_write_timeout,
+                ),
+            )
+        self._client = AsyncOpenAI(
+            api_key=self._api_key,
+            base_url=self._base_url,
+            max_retries=0,
+            timeout=httpx.Timeout(
+                config.http_read_timeout,
+                connect=config.http_connect_timeout,
+                read=config.http_read_timeout,
+                write=config.http_write_timeout,
+            ),
+            http_client=http_client,
+        )
+
+    async def cleanup(self) -> None:
+        """Release HTTP client resources."""
+        client = getattr(self, "_client", None)
+        if client is not None:
+            await client.close()
+
+    async def list_model_ids(self) -> frozenset[str]:
+        """Return model ids from the provider's OpenAI-compatible models endpoint."""
+        payload = await self._client.models.list()
+        return extract_openai_model_ids(payload, provider_name=self._provider_name)
+
+    @abstractmethod
+    def _build_request_body(
+        self, request: Any, thinking_enabled: bool | None = None
+    ) -> dict:
+        """Build request body. Must be implemented by subclasses."""
+
+    def _handle_extra_reasoning(
+        self, delta: Any, sse: SSEBuilder, *, thinking_enabled: bool
+    ) -> Iterator[str]:
+        """Hook for provider-specific reasoning."""
+        return iter(())
+
+    def _get_retry_request_body(self, error: Exception, body: dict) -> dict | None:
+        """Return a modified request body for one retry, or None."""
+        return None
+
+    def _prepare_create_body(self, body: dict[str, Any]) -> dict[str, Any]:
+        """Return the body passed to the upstream OpenAI-compatible client."""
+        return body
+
+    def _record_tool_call_extra_content(
+        self, tool_call_id: str, extra_content: dict[str, Any]
+    ) -> None:
+        """Hook for providers that must replay OpenAI tool-call metadata later."""
+
+    def _tool_argument_aliases(self, body: dict[str, Any]) -> dict[str, dict[str, str]]:
+        """Return provider-specific per-tool argument aliases for this request."""
+        return {}
+
+    async def _create_stream(self, body: dict) -> tuple[Any, dict]:
+        """Create a streaming chat completion, optionally retrying once."""
+        try:
+            create_body = self._prepare_create_body(body)
+            stream = await self._global_rate_limiter.execute_with_retry(
+                self._client.chat.completions.create, **create_body, stream=True
+            )
+            return stream, body
+        except Exception as error:
+            retry_body = self._get_retry_request_body(error, body)
+            if retry_body is None:
+                raise
+
+            create_retry_body = self._prepare_create_body(retry_body)
+            stream = await self._global_rate_limiter.execute_with_retry(
+                self._client.chat.completions.create, **create_retry_body, stream=True
+            )
+            return stream, retry_body
+
+    def _openai_error_message(self, error: Exception, request_id: str | None) -> str:
+        mapped_error = map_error(error, rate_limiter=self._global_rate_limiter)
+        return user_visible_message_for_mapped_provider_error(
+            mapped_error,
+            provider_name=self._provider_name,
+            read_timeout_s=self._config.http_read_timeout,
+            detail=extract_provider_error_detail(error),
+            request_id=request_id,
+        )
+
+    async def stream_response(
+        self,
+        request: Any,
+        input_tokens: int = 0,
+        *,
+        request_id: str | None = None,
+        thinking_enabled: bool | None = None,
+    ) -> AsyncIterator[str]:
+        """Stream response in Anthropic SSE format."""
+        with logger.contextualize(request_id=request_id):
+            runner = OpenAIChatStreamRunner(
+                self,
+                request=request,
+                input_tokens=input_tokens,
+                request_id=request_id,
+                thinking_enabled=thinking_enabled,
+            )
+            async for event in runner.run():
+                yield event
diff --git a/providers/wafer/client.py b/providers/wafer/client.py
--- a/providers/wafer/client.py
+++ b/providers/wafer/client.py
@@ -2,9 +2,9 @@
 
 from typing import Any
 
-from providers.anthropic_messages import AnthropicMessagesTransport
 from providers.base import ProviderConfig
 from providers.defaults import WAFER_DEFAULT_BASE
+from providers.transports.anthropic_messages import AnthropicMessagesTransport
 
 _ANTHROPIC_VERSION = "2023-06-01"
 
diff --git a/providers/zai/client.py b/providers/zai/client.py
--- a/providers/zai/client.py
+++ b/providers/zai/client.py
@@ -4,9 +4,9 @@
 
 from typing import Any
 
-from providers.anthropic_messages import AnthropicMessagesTransport
 from providers.base import ProviderConfig
 from providers.defaults import ZAI_DEFAULT_BASE
+from providers.transports.anthropic_messages import AnthropicMessagesTransport
 
 from .request import build_request_body
 
diff --git a/pyproject.toml b/pyproject.toml
--- a/pyproject.toml
+++ b/pyproject.toml
@@ -4,7 +4,7 @@ build-backend = "hatchling.build"
 
 [project]
 name = "free-claude-code"
-version = "2.3.1"
+version = "2.3.2"
 description = "Middleware between Claude Code CLI (Anthropic API) and NVIDIA NIM"
 readme = "README.md"
 requires-python = ">=3.14.0"
diff --git a/uv.lock b/uv.lock
--- a/uv.lock
+++ b/uv.lock
@@ -561,7 +561,7 @@ wheels = [
 
 [[package]]
 name = "free-claude-code"
-version = "2.3.1"
+version = "2.3.2"
 source = { editable = "." }
 dependencies = [
     { name = "aiohttp" },
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
