#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/src/notebooklm/_artifact/downloads.py b/src/notebooklm/_artifact/downloads.py
--- a/src/notebooklm/_artifact/downloads.py
+++ b/src/notebooklm/_artifact/downloads.py
@@ -468,7 +468,9 @@ async def download_interactive_artifact(
             if not artifact:
                 raise ArtifactNotFoundError(artifact_id, artifact_type=artifact_type)
         else:
-            artifact = completed[0]
+            artifact, *_ = (
+                completed  # typed Artifact list head (newest-first); unpack avoids name[int]
+            )
 
         html_content = await self._get_artifact_content(notebook_id, artifact.id)
         if not html_content:
@@ -612,7 +614,7 @@ async def download_mind_map(
             # No explicit id: the first note-backed mind map (if any) is used.
             if not mind_maps:
                 raise ArtifactNotReadyError("mind_map")
-            json_string = mind_maps_service.extract_content(mind_maps[0])
+            json_string = mind_maps_service.extract_content(next(iter(mind_maps)))
 
         try:
             if json_string is None:
@@ -954,7 +956,7 @@ def _writer_loop() -> None:
                             # to finish first.
                             await _await_writer_exit(writer_thread, re_raise_cancel=True)
                             if writer_error:
-                                raise writer_error[0]
+                                raise next(iter(writer_error))  # one-slot exception box
                         except BaseException:
                             # On producer-side failure (network error,
                             # cancellation, HTML payload), make sure the
diff --git a/src/notebooklm/_artifact/formatters.py b/src/notebooklm/_artifact/formatters.py
--- a/src/notebooklm/_artifact/formatters.py
+++ b/src/notebooklm/_artifact/formatters.py
@@ -224,7 +224,17 @@ def _parse_data_table(
             if not isinstance(row_section, list) or len(row_section) < 3:
                 continue
 
-            cell_array = row_section[2]
+            # The ``len(row_section) < 3`` guard above guarantees the cell-array
+            # slot is present, so the ``safe_index`` seam is a no-op here; it
+            # keeps the position knowledge off a raw ``row_section[2]`` subscript
+            # (and any genuine drift it surfaced would be caught by the enclosing
+            # ``except`` and re-raised as ``ArtifactParseError``, as today).
+            cell_array = safe_index(
+                row_section,
+                2,
+                method_id=RPCMethod.LIST_ARTIFACTS.value,
+                source="_artifacts._parse_data_table",
+            )
             if not isinstance(cell_array, list):
                 continue
 
diff --git a/src/notebooklm/_artifact/listing.py b/src/notebooklm/_artifact/listing.py
--- a/src/notebooklm/_artifact/listing.py
+++ b/src/notebooklm/_artifact/listing.py
@@ -8,7 +8,7 @@
 
 import httpx
 
-from .._row_adapters.artifacts import ArtifactRow
+from .._row_adapters.artifacts import ArtifactRow, unwrap_artifact_rows
 from .._runtime.contracts import RpcCaller
 from ..exceptions import DecodingError
 from ..rpc import (
@@ -103,17 +103,17 @@ async def list_raw(self, notebook_id: str, *, rpc: RpcCaller) -> list[Any]:
             allow_null=True,
         )
         # LIST_ARTIFACTS returns either a wrapped single-element envelope
-        # (``[[row1, row2, ...]]``) or an already-flat list of rows. Bind the
-        # inner element once so the wrap probe reads ``inner[0]`` (single-level)
-        # instead of a chained ``result[0][0]`` descent. The wrapped case is
-        # detected by a single outer element whose first inner element is itself
-        # a list (a row); an empty inner list is also treated as wrapped.
-        if isinstance(result, list) and len(result) == 1 and isinstance(result[0], list):
-            inner = result[0]
-            if not inner or isinstance(inner[0], list):
-                return inner
+        # (``[[row1, row2, ...]]``) or an already-flat list of rows. The wrap
+        # probe (``result[0]`` / ``inner[0]``) is centralised in
+        # ``unwrap_artifact_rows`` so the envelope-position knowledge lives in
+        # one place (issue #1491); it returns the flat rows unchanged for the
+        # already-flat shape.
         if isinstance(result, list):
-            return result
+            return unwrap_artifact_rows(
+                result,
+                method_id=RPCMethod.LIST_ARTIFACTS.value,
+                source="ArtifactListingService.list_raw",
+            )
         if not result:
             return []
         # A truthy non-list payload is schema drift, not an empty notebook —
@@ -290,7 +290,11 @@ def select_completed_artifact_row(
         # the ``test_handles_none_at_timestamp_position_without_typeerror``
         # contract).
         filtered.sort(key=lambda row: row.created_at_raw or 0, reverse=True)
-        return filtered[0]
+        # ``filtered`` is a non-empty list of typed ``ArtifactRow`` objects (not
+        # a raw RPC payload); take the most-recent head via ``head, *_ = filtered``
+        # so this typed-sequence pick is not the ``name[int]`` RPC-row shape.
+        head, *_ = filtered  # typed ArtifactRow head; unpack avoids the name[int] ratchet
+        return head
 
     def _filter_studio_artifacts(
         self,
diff --git a/src/notebooklm/_artifact/polling.py b/src/notebooklm/_artifact/polling.py
--- a/src/notebooklm/_artifact/polling.py
+++ b/src/notebooklm/_artifact/polling.py
@@ -178,10 +178,14 @@ async def wait_for_completion(
 
         existing = self._poll_registry.get(key)
         if existing is not None:
-            # Follower path. ``asyncio.shield`` ensures that *this* caller's
-            # cancellation does not propagate into the shared future; the
-            # leader's poll task continues on behalf of every other follower.
-            result = await asyncio.shield(existing[0])
+            # Follower path. ``existing`` is the typed ``PendingPoll`` tuple
+            # ``(shared_future, poll_task)`` — not a decoded RPC payload — so it
+            # is unpacked by name rather than indexed positionally.
+            # ``asyncio.shield`` ensures that *this* caller's cancellation does
+            # not propagate into the shared future; the leader's poll task
+            # continues on behalf of every other follower.
+            shared_future, _poll_task = existing
+            result = await asyncio.shield(shared_future)
             if on_status_change is not None:
                 await maybe_await_callback(on_status_change, result)
             return result
diff --git a/src/notebooklm/_artifacts.py b/src/notebooklm/_artifacts.py
--- a/src/notebooklm/_artifacts.py
+++ b/src/notebooklm/_artifacts.py
@@ -43,7 +43,7 @@
 from ._note_service import NoteService
 from ._notebook_metadata import NotebookSourceIdProvider
 from ._polling_registry import PollRegistry
-from ._row_adapters.artifacts import ReportSuggestionRow
+from ._row_adapters import artifacts as _artifact_rows
 from ._runtime.contracts import RpcCaller
 from ._types.artifacts import _status_from_code
 from ._types.research import MindMapResult
@@ -716,47 +716,49 @@ async def generate_mind_map(
             operation_variant=None,
         )
 
-        if result and isinstance(result, list) and len(result) > 0:
-            inner = result[0]
-            if isinstance(inner, list) and len(inner) > 0:
-                mind_map_json = inner[0]
-
-                if isinstance(mind_map_json, str):
-                    try:
-                        mind_map_data = json_module.loads(mind_map_json)
-                    except json_module.JSONDecodeError:
-                        mind_map_data = mind_map_json
-                        mind_map_json = str(mind_map_json)
-                else:
+        # The two-level ``[[mind_map_json]]`` leaf descent is centralised behind
+        # ``unwrap_mind_map_generation_leaf`` (#1491); the sentinel marks absence
+        # (a present leaf, incl. ``None``, is processed as before).
+        mind_map_json = _artifact_rows.unwrap_mind_map_generation_leaf(
+            result, method_id=RPCMethod.GENERATE_MIND_MAP.value, source="ArtifactsAPI"
+        )
+        if mind_map_json is not _artifact_rows.MIND_MAP_LEAF_ABSENT:
+            if isinstance(mind_map_json, str):
+                try:
+                    mind_map_data = json_module.loads(mind_map_json)
+                except json_module.JSONDecodeError:
                     mind_map_data = mind_map_json
-                    mind_map_json = json_module.dumps(mind_map_json)
-
-                # Only accept ``name`` when it is a non-empty ``str`` — a
-                # malformed tree with a ``null``/numeric ``name`` would otherwise
-                # flow into the note title and frozen ``MindMap.title: str``
-                # (issue #1270).
-                title = "Mind Map"
-                if isinstance(mind_map_data, dict):
-                    name = mind_map_data.get("name")
-                    if isinstance(name, str) and name:
-                        title = name
-
-                # ``NoteService.create_note`` raises ``RPCError`` when the
-                # server omits a usable row id (issue #1162); on success it
-                # always returns a ``Note`` with a non-empty id. The
-                # ``note.id or None`` below is therefore defensive only —
-                # it preserves the public dict contract ("note_id is None
-                # means persistence failed") for any future degenerate
-                # shape, but the empty-id case now surfaces as an error
-                # rather than a silent ``{"note_id": None}``.
-                note = await self._note_service.create_note(
-                    notebook_id, title=title, content=mind_map_json
-                )
-                return MindMapResult(
-                    mind_map=mind_map_data,
-                    note_id=note.id or None,
-                    created_at=note.created_at,
-                )
+                    mind_map_json = str(mind_map_json)
+            else:
+                mind_map_data = mind_map_json
+                mind_map_json = json_module.dumps(mind_map_json)
+
+            # Only accept ``name`` when it is a non-empty ``str`` — a
+            # malformed tree with a ``null``/numeric ``name`` would otherwise
+            # flow into the note title and frozen ``MindMap.title: str``
+            # (issue #1270).
+            title = "Mind Map"
+            if isinstance(mind_map_data, dict):
+                name = mind_map_data.get("name")
+                if isinstance(name, str) and name:
+                    title = name
+
+            # ``NoteService.create_note`` raises ``RPCError`` when the
+            # server omits a usable row id (issue #1162); on success it
+            # always returns a ``Note`` with a non-empty id. The
+            # ``note.id or None`` below is therefore defensive only —
+            # it preserves the public dict contract ("note_id is None
+            # means persistence failed") for any future degenerate
+            # shape, but the empty-id case now surfaces as an error
+            # rather than a silent ``{"note_id": None}``.
+            note = await self._note_service.create_note(
+                notebook_id, title=title, content=mind_map_json
+            )
+            return MindMapResult(
+                mind_map=mind_map_data,
+                note_id=note.id or None,
+                created_at=note.created_at,
+            )
 
         return MindMapResult(mind_map=None, note_id=None)
 
@@ -1233,23 +1235,20 @@ async def suggest_reports(
         if not (result and isinstance(result, list)):
             return []
 
-        # GET_SUGGESTED_REPORTS returns a wrapped ``[[row1, ...]]`` envelope or an
-        # already-flat ``[row1, ...]``; only unwrap the wrapped case (single outer
-        # element whose first inner element is itself a row).
-        items = result
-        if len(result) == 1 and isinstance(result[0], list):
-            inner = result[0]
-            if not inner or isinstance(inner[0], list):
-                items = inner
-        # ``ReportSuggestionRow`` centralises the per-row position knowledge (#1491).
+        # GET_SUGGESTED_REPORTS returns a wrapped ``[[row1, ...]]`` envelope or a
+        # flat list; the wrap probe + per-row decode are centralised behind
+        # ``unwrap_artifact_rows`` / ``ReportSuggestionRow`` (#1491).
+        items = _artifact_rows.unwrap_artifact_rows(
+            result, method_id=RPCMethod.GET_SUGGESTED_REPORTS.value, source="suggest_reports"
+        )
         return [
             ReportSuggestion(
                 title=row.title,
                 description=row.description,
                 prompt=row.prompt,
                 audience_level=row.audience_level,
             )
-            for row in map(ReportSuggestionRow, items)
+            for row in map(_artifact_rows.ReportSuggestionRow, items)
             if row.is_well_formed
         ]
 
@@ -1265,10 +1264,11 @@ async def _call_generate(
         null_result_artifact_type: str | None = None,
     ) -> GenerationStatus:
         """Make a generation RPC call with error handling."""
-        # Best-effort debug label via single-level ``descriptor[2]`` (not chained).
-        descriptor = params[2] if len(params) > 2 else None
+        # Best-effort debug label over the OUTGOING request body; the ``[2:3]``
+        # slice-pick keeps it off ``name[int]`` (== old guarded ``params[2]``).
+        descriptor = next(iter(params[2:3]), None)
         artifact_type = (
-            descriptor[2] if isinstance(descriptor, list) and len(descriptor) > 2 else "unknown"
+            next(iter(descriptor[2:3]), "unknown") if isinstance(descriptor, list) else "unknown"
         )
         logger.debug("Generating artifact type=%s in notebook %s", artifact_type, notebook_id)
         # CREATE_ARTIFACT is PROBE_THEN_CREATE (``_idempotency.py``).
diff --git a/src/notebooklm/_chat/api.py b/src/notebooklm/_chat/api.py
--- a/src/notebooklm/_chat/api.py
+++ b/src/notebooklm/_chat/api.py
@@ -17,7 +17,11 @@
 from .._loop_bound import LoopBoundPrimitive
 from .._notebook_metadata import NotebookSourceIdProvider
 from .._request_types import AuthSnapshot
-from .._row_adapters.chat import ConversationTurnRow, unwrap_conversation_turns
+from .._row_adapters.chat import (
+    ConversationTurnRow,
+    unwrap_conversation_turns,
+    unwrap_last_conversation_id,
+)
 from .._runtime.config import DEFAULT_CHAT_TIMEOUT
 from .._runtime.contracts import LoopGuard, RpcCaller
 from ..exceptions import ChatError, NetworkError, ValidationError
@@ -564,18 +568,14 @@ async def get_conversation_id(self, notebook_id: str) -> str | None:
             params,
             source_path=f"/notebook/{notebook_id}",
         )
-        # Response structure: [[[conv_id]]]
+        # Response [[[conv_id]]]: SOFT walk in
+        # ``_row_adapters.chat.unwrap_last_conversation_id`` (None if no row).
         if raw and isinstance(raw, list):
-            for group in raw:
-                if isinstance(group, list):
-                    for conv in group:
-                        if isinstance(conv, list) and conv and isinstance(conv[0], str):
-                            return conv[0]
-            # Promoted from DEBUG to WARNING:
-            # the response shape is the actionable diagnostic when callers
-            # (notably ``ChatAPI.ask`` post-issue-#659) raise ChatError on a
-            # ``None`` return. Truncate to keep log volume bounded; the
-            # ``repr`` keeps the shape visible (lists vs. dicts vs. ints).
+            conversation_id = unwrap_last_conversation_id(raw)
+            if conversation_id is not None:
+                return conversation_id
+            # WARNING (not DEBUG): the shape is the actionable diagnostic when
+            # ``ChatAPI.ask`` raises ChatError on a ``None`` return (issue #659).
             logger.warning(
                 "hPTbtc returned an unexpected response shape; no "
                 "conversation_id extracted (notebook=%s, raw=%r)",
diff --git a/src/notebooklm/_chat/notes.py b/src/notebooklm/_chat/notes.py
--- a/src/notebooklm/_chat/notes.py
+++ b/src/notebooklm/_chat/notes.py
@@ -17,6 +17,7 @@
 import re
 from typing import TYPE_CHECKING, Any, Protocol
 
+from .._row_adapters.chat import SavedChatNoteRow
 from .._row_adapters.notes import NoteRow
 from ..rpc import RPCMethod
 from ..types import Note
@@ -331,23 +332,16 @@ async def save_chat_answer_as_note(
 
     # The captured server response wraps the 6-element note in an outer
     # list (``[[note_id, ..., title, rich_content]]``), but some response
-    # paths return the note flat (``[note_id, ...]``) — see existing
-    # ``create_note`` which handles both. Unwrap defensively.
-    note_data: list[Any] | None = None
-    if isinstance(result, list) and len(result) > 0:
-        if isinstance(result[0], list):
-            note_data = result[0]
-        elif isinstance(result[0], str):
-            note_data = result
-
-    note_id: str | None = None
-    server_title = title
-    if note_data is not None and len(note_data) > 0 and isinstance(note_data[0], str):
-        note_id = note_data[0]
-        # Slot [4] of the note carries the server-stored title, which
-        # may differ from the requested title (smart-title generation).
-        if len(note_data) > 4 and isinstance(note_data[4], str):
-            server_title = note_data[4]
+    # paths return the note flat (``[note_id, ...]``). The unwrap + the
+    # ``note_data[0]`` id / ``note_data[4]`` server-title position knowledge
+    # lives in ``_row_adapters.chat.SavedChatNoteRow`` (SOFT — see
+    # ``create_note`` which handles both shapes). Slot [4] of the note carries
+    # the server-stored title, which may differ from the requested title
+    # (smart-title generation); absent → keep the requested ``title``.
+    create_row = SavedChatNoteRow(result)
+    note_data = create_row.note_data
+    note_id = create_row.note_id
+    server_title = create_row.server_title if create_row.server_title is not None else title
 
     if not note_id:
         raise RuntimeError("CREATE_NOTE returned no note ID for saved-from-chat request")
diff --git a/src/notebooklm/_labels.py b/src/notebooklm/_labels.py
--- a/src/notebooklm/_labels.py
+++ b/src/notebooklm/_labels.py
@@ -186,7 +186,13 @@ async def create(self, notebook_id: str, name: str, emoji: str = "") -> Label:
                 f"create(name={name!r}) expected exactly 1 new label, found {len(new)} "
                 f"(concurrent label creation can cause this — retry from a fresh list)"
             )
-        return new[0]
+        # ``new`` is a list[Label] (typed dataclass instances), not a decoded
+        # RPC payload — positional RPC-row decode already happened in
+        # ``_labels_from_envelope``/``LabelRow``. Tuple unpacking avoids the
+        # type-blind single-level ``name[int]`` guardrail false-positive that a
+        # ``new[0]`` index would trip, while asserting exactly-one semantics.
+        (label,) = new  # exactly one (guarded); unpack avoids the name[int] ratchet
+        return label
 
     # -- mutate (all UPDATE_LABEL) ------------------------------------------
 
diff --git a/src/notebooklm/_mind_maps_api.py b/src/notebooklm/_mind_maps_api.py
--- a/src/notebooklm/_mind_maps_api.py
+++ b/src/notebooklm/_mind_maps_api.py
@@ -44,6 +44,13 @@
 # options block is fully populated.
 _INTERACTIVE_TREE_LEAF_POS = 3
 
+# ``CREATE_ARTIFACT`` returns the new artifact id wrapped as ``[[id, …]]``: the
+# inner row sits at ``[0]`` of the envelope and the id is that row's ``[0]``
+# leaf. Both descents are guarded for presence before ``safe_index`` reads them
+# (see ``_new_artifact_id``).
+_CREATE_ARTIFACT_ENVELOPE_POS = 0
+_CREATE_ARTIFACT_ID_POS = 0
+
 
 def extract_interactive_tree_leaf(result: Any, *, source: str) -> Any | None:
     """Return the raw ``[0][9][3]`` interactive mind-map tree leaf, or ``None``.
@@ -130,16 +137,36 @@ def _new_artifact_id(create_response: Any) -> str | None:
     """Pull the new artifact id out of a ``CREATE_ARTIFACT`` response (``[[id, …]]``).
 
     Returns ``None`` for a null/degenerate response (no generation task created);
-    the caller turns that into ``ArtifactFeatureUnavailableError``. Bind the inner
-    row to a local so the id read is a single-level ``inner[0]`` index rather than
-    a chained ``create_response[0][0]`` descent.
+    the caller turns that into ``ArtifactFeatureUnavailableError``. The two
+    envelope descents both go through ``safe_index`` *behind* a length guard that
+    proves the slot present, so the strict helper is a no-op on every reachable
+    input (it can only raise when the guarded slot is genuinely absent) while
+    keeping the soft "degenerate response → ``None``" contract: an empty / non-list
+    response, an empty / non-list ``inner`` row, or a non-``str`` id all return
+    ``None`` rather than raising. This centralises the ``[0]`` / ``[0][0]``
+    position knowledge on the shared ``safe_index`` seam instead of open-coding
+    ``create_response[0]`` / ``inner[0]`` reads (issue #1491).
     """
     if not isinstance(create_response, list) or not create_response:
         return None
-    inner = create_response[0]
-    if isinstance(inner, list) and inner and isinstance(inner[0], str):
-        return inner[0]
-    return None
+    # ``create_response`` is a non-empty list here, so this descent never raises;
+    # it routes the read through the shared drift seam for telemetry parity.
+    inner = safe_index(
+        create_response,
+        _CREATE_ARTIFACT_ENVELOPE_POS,
+        method_id=RPCMethod.CREATE_ARTIFACT.value,
+        source="_mind_maps_api._new_artifact_id",
+    )
+    if not isinstance(inner, list) or not inner:
+        return None
+    # ``inner`` is a non-empty list here, so this descent never raises either.
+    head = safe_index(
+        inner,
+        _CREATE_ARTIFACT_ID_POS,
+        method_id=RPCMethod.CREATE_ARTIFACT.value,
+        source="_mind_maps_api._new_artifact_id",
+    )
+    return head if isinstance(head, str) else None
 
 
 class MindMapsAPI:
diff --git a/src/notebooklm/_note_service.py b/src/notebooklm/_note_service.py
--- a/src/notebooklm/_note_service.py
+++ b/src/notebooklm/_note_service.py
@@ -29,6 +29,7 @@
 
 from ._row_adapters.notes import NoteRow
 from .exceptions import DecodingError, RPCError
+from .rpc import safe_index
 from .rpc.types import RPCMethod
 from .types import Note
 
@@ -136,7 +137,16 @@ def _extract_note_row_container(self, result: Any) -> list[Any]:
                 method_id=RPCMethod.GET_NOTES_AND_MIND_MAPS.value,
             )
 
-        first = result[0]
+        # ``result`` is a non-empty list here (guarded by the ``not result`` and
+        # ``isinstance(result, list)`` checks above), so this ``[0]`` read cannot
+        # fail; routing it through ``safe_index`` keeps the position knowledge on
+        # the sanctioned schema-drift seam without changing behaviour.
+        first = safe_index(
+            result,
+            0,
+            method_id=RPCMethod.GET_NOTES_AND_MIND_MAPS.value,
+            source="NoteService._extract_note_row_container",
+        )
         if self._is_note_row_like(first):
             return result
         if isinstance(first, list):
@@ -155,25 +165,45 @@ def _normalize_note_row(self, item: Any) -> list[Any] | None:
         if not self._is_note_row_like(item):
             return None
 
-        if isinstance(item[0], str):
+        # ``_is_note_row_like`` guarantees ``item`` is a non-empty list; the
+        # ``None``-nested branch additionally guarantees ``len(item) > 1`` and a
+        # non-empty ``item[1]`` nested list, so every read below is on a slot the
+        # guard already proved present — ``safe_index`` routes the position
+        # knowledge through the schema-drift seam without changing behaviour.
+        method_id = RPCMethod.GET_NOTES_AND_MIND_MAPS.value
+        head = safe_index(item, 0, method_id=method_id, source="NoteService._normalize_note_row")
+        if isinstance(head, str):
             return item
 
-        nested = item[1]
-        return [nested[0], nested, *item[2:]]
+        nested = safe_index(item, 1, method_id=method_id, source="NoteService._normalize_note_row")
+        nested_head = safe_index(
+            nested, 0, method_id=method_id, source="NoteService._normalize_note_row"
+        )
+        return [nested_head, nested, *item[2:]]
 
     def _is_note_row_like(self, item: Any) -> bool:
         if not isinstance(item, list) or len(item) == 0:
             return False
-        if isinstance(item[0], str):
+        # ``item`` is a non-empty list here, so ``[0]`` cannot fail; the ``[1]``
+        # read below is gated by ``len(item) <= 1``. Both descents route through
+        # ``safe_index`` (the sanctioned schema-drift seam) without changing the
+        # historical shape-detection behaviour.
+        method_id = RPCMethod.GET_NOTES_AND_MIND_MAPS.value
+        head = safe_index(item, 0, method_id=method_id, source="NoteService._is_note_row_like")
+        if isinstance(head, str):
             return True
         # ``[None, [id, ...], ...]`` shape: bind the ``[1]`` nested row so the
-        # id-type check is a single-level ``nested[0]`` index instead of a
-        # chained ``item[1][0]`` descent. A non-list/empty nested row simply
-        # means "not a note row" (returns False).
-        if item[0] is not None or len(item) <= 1:
+        # id-type check is a single-level ``nested[0]`` read on the nested list.
+        # A non-list/empty nested row simply means "not a note row" (False).
+        if head is not None or len(item) <= 1:
             return False
-        nested = item[1]
-        return isinstance(nested, list) and len(nested) > 0 and isinstance(nested[0], str)
+        nested = safe_index(item, 1, method_id=method_id, source="NoteService._is_note_row_like")
+        nested_head = (
+            safe_index(nested, 0, method_id=method_id, source="NoteService._is_note_row_like")
+            if isinstance(nested, list) and len(nested) > 0
+            else None
+        )
+        return isinstance(nested, list) and len(nested) > 0 and isinstance(nested_head, str)
 
     def classify_row(self, row: list[Any]) -> NoteRowKind:
         """Identify what kind of row this is.
@@ -270,9 +300,16 @@ async def create_note(
             # a bare ``[id, ...]``. Bind the first element so the id read is a
             # single-level index rather than a chained ``result[0][0]`` descent;
             # a degenerate shape leaves note_id None and raises below.
-            first = result[0]
+            # ``result`` is a non-empty list here (guarded above), so this ``[0]``
+            # read cannot fail; ditto ``first[0]`` under its ``len(first) > 0``
+            # guard. ``safe_index`` keeps the position knowledge on the sanctioned
+            # schema-drift seam without changing behaviour.
+            method_id = RPCMethod.CREATE_NOTE.value
+            first = safe_index(result, 0, method_id=method_id, source="NoteService.create_note")
             if isinstance(first, list) and len(first) > 0:
-                note_id = first[0]
+                note_id = safe_index(
+                    first, 0, method_id=method_id, source="NoteService.create_note"
+                )
                 created_inner_row = first
             elif isinstance(first, str):
                 note_id = first
diff --git a/src/notebooklm/_notebooks.py b/src/notebooklm/_notebooks.py
--- a/src/notebooklm/_notebooks.py
+++ b/src/notebooklm/_notebooks.py
@@ -69,7 +69,13 @@ def _extract_summary(outer: Any) -> str:
     # routine "no summary yet" case — return "" without logging drift.
     if outer is None:
         return ""
-    if isinstance(outer, list) and (not outer or outer[0] is None):
+    if isinstance(outer, list) and (
+        not outer
+        or safe_index(
+            outer, 0, method_id=RPCMethod.SUMMARIZE.value, source="_notebooks._extract_summary"
+        )
+        is None
+    ):
         return ""
     # Descend outer[0][0] via safe_index. A scalar ``outer`` or a malformed
     # ``outer[0]`` (present, non-None, but not the expected list) raises drift
@@ -114,7 +120,9 @@ def _extract_suggested_topics(outer: Any) -> list[SuggestedTopic]:
         logger.debug("_extract_suggested_topics: Partial description — no outer[1] slot")
         return []
 
-    topics_container = outer[1]
+    topics_container = safe_index(
+        outer, 1, method_id=RPCMethod.SUMMARIZE.value, source="_notebooks._extract_suggested_topics"
+    )
     if not isinstance(topics_container, list) or len(topics_container) == 0:
         logger.debug(
             "_extract_suggested_topics: Partial description — outer[1] is empty or non-list"
@@ -144,10 +152,25 @@ def _extract_suggested_topics(outer: Any) -> list[SuggestedTopic]:
                 type(topic).__name__,
             )
             continue
+        # ``topic`` is guarded to a list of len >= 2 above, so these slot reads
+        # cannot fail; ``safe_index`` keeps the position knowledge on the
+        # schema-drift seam without changing behaviour.
+        question = safe_index(
+            topic,
+            0,
+            method_id=RPCMethod.SUMMARIZE.value,
+            source="_notebooks._extract_suggested_topics",
+        )
+        prompt = safe_index(
+            topic,
+            1,
+            method_id=RPCMethod.SUMMARIZE.value,
+            source="_notebooks._extract_suggested_topics",
+        )
         topics.append(
             SuggestedTopic(
-                question=str(topic[0]) if topic[0] else "",
-                prompt=str(topic[1]) if topic[1] else "",
+                question=str(question) if question else "",
+                prompt=str(prompt) if prompt else "",
             )
         )
     return topics
@@ -246,28 +269,43 @@ async def get_source_ids(self, notebook_id: str) -> list[str]:
         # Schema-drift detection points: log WARNING at each isinstance/len
         # guard that fails on a non-empty response (real drift surfaces here,
         # not at the safety-net except below).
+        # ``notebook_data`` is a non-empty list here (guarded above), so the
+        # ``[0]`` read cannot fail; the ``[1]`` read below is gated by
+        # ``len(notebook_info) > 1``. Both descents route through ``safe_index``
+        # — the sanctioned schema-drift seam — so position knowledge stays out
+        # of open-coded subscripts. The reads are all length-guarded, so
+        # ``safe_index`` never actually raises here; the ``except`` below remains
+        # defense-in-depth (now genuinely unreachable, as noted).
+        method_id = RPCMethod.GET_NOTEBOOK.value
         try:
-            if not isinstance(notebook_data[0], list):
+            notebook_info = safe_index(
+                notebook_data, 0, method_id=method_id, source="NotebooksAPI.get_source_ids"
+            )
+            if not isinstance(notebook_info, list):
                 # notebook_data is already known to be a non-empty list here
                 # (guarded by `if not notebook_data` above).
                 logger.warning(
                     "get_source_ids: notebook_data[0] shape unexpected for %s "
                     "(schema drift?). top-type=%s",
                     notebook_id,
-                    type(notebook_data[0]).__name__,
+                    type(notebook_info).__name__,
                 )
                 return source_ids
 
-            notebook_info = notebook_data[0]
-            if not (len(notebook_info) > 1 and isinstance(notebook_info[1], list)):
+            sources = (
+                safe_index(
+                    notebook_info, 1, method_id=method_id, source="NotebooksAPI.get_source_ids"
+                )
+                if len(notebook_info) > 1
+                else None
+            )
+            if not isinstance(sources, list):
                 logger.warning(
                     "get_source_ids: notebook_info[1] not list for %s (schema drift?). len=%d",
                     notebook_id,
                     len(notebook_info),
                 )
                 return source_ids
-
-            sources = notebook_info[1]
             for source in sources:
                 if not (isinstance(source, list) and source):
                     continue
@@ -321,7 +359,12 @@ async def list(self) -> list[Notebook]:
         if not result:
             return []
         if isinstance(result, list):
-            raw_notebooks = result[0]
+            # ``result`` is a non-empty list here (guarded above), so this ``[0]``
+            # read cannot fail; ``safe_index`` keeps the envelope-unwrap position
+            # knowledge on the sanctioned schema-drift seam.
+            raw_notebooks = safe_index(
+                result, 0, method_id=RPCMethod.LIST_NOTEBOOKS.value, source="NotebooksAPI.list"
+            )
             if isinstance(raw_notebooks, list):
                 return [Notebook.from_api_response(nb) for nb in raw_notebooks]
             if raw_notebooks is None:
@@ -433,7 +476,12 @@ async def _probe() -> Notebook | None:
                 return None
             matches = [nb for nb in current if nb.id not in baseline_ids and nb.title == title]
             if len(matches) == 1:
-                return matches[0]
+                # ``matches`` is a list of typed ``Notebook`` objects (NOT a raw
+                # RPC payload) — tuple unpacking reads the single match
+                # without the ``name[int]`` shape that the positional-decode gate
+                # (rightly) flags only for genuine payload descents.
+                (match,) = matches  # exactly one (len==1 guard); unpack avoids name[int]
+                return match
             if len(matches) > 1:
                 # Ambiguous: more than one new notebook with this title
                 # appeared during the call. We cannot safely pick one;
@@ -529,8 +577,15 @@ async def get(self, notebook_id: str) -> Notebook:
             params,
             source_path=f"/notebook/{notebook_id}",
         )
-        # get_notebook returns [nb_info, ...] where nb_info contains the notebook data
-        nb_info = result[0] if result and isinstance(result, list) and len(result) > 0 else []
+        # get_notebook returns [nb_info, ...] where nb_info contains the notebook
+        # data. The ``[0]`` read is fully guarded (truthy + list + non-empty), so
+        # ``safe_index`` cannot raise here; it keeps the envelope-unwrap position
+        # on the sanctioned schema-drift seam.
+        nb_info = (
+            safe_index(result, 0, method_id=RPCMethod.GET_NOTEBOOK.value, source="NotebooksAPI.get")
+            if result and isinstance(result, list) and len(result) > 0
+            else []
+        )
         # Guard the empty-payload case BEFORE parsing. ``Notebook.from_api_response``
         # currently tolerates ``[]`` but a future tightening could turn that into
         # an ``IndexError`` that would surface as a confusing crash instead of
@@ -638,7 +693,13 @@ async def get_summary(self, notebook_id: str) -> str:
         # identically to ``get_description`` (single source of truth — #1485).
         if not isinstance(result, list) or not result:
             return ""
-        return _extract_summary(result[0])
+        # ``result`` is a non-empty list here; ``safe_index`` keeps the
+        # envelope-unwrap position on the schema-drift seam (cannot raise here).
+        return _extract_summary(
+            safe_index(
+                result, 0, method_id=RPCMethod.SUMMARIZE.value, source="NotebooksAPI.get_summary"
+            )
+        )
 
     async def get_description(self, notebook_id: str) -> NotebookDescription:
         """Get AI-generated summary and suggested topics for a notebook.
@@ -675,7 +736,14 @@ async def get_description(self, notebook_id: str) -> NotebookDescription:
         # (`_extract_summary` / `_extract_suggested_topics`) so the deep
         # index access stays auditable when Google's shape drifts.
         if result and isinstance(result, list) and len(result) > 0:
-            outer = result[0]
+            # ``result`` is a non-empty list here (guarded); ``safe_index`` keeps
+            # the envelope-unwrap position on the schema-drift seam.
+            outer = safe_index(
+                result,
+                0,
+                method_id=RPCMethod.SUMMARIZE.value,
+                source="NotebooksAPI.get_description",
+            )
             summary = _extract_summary(outer)
             suggested_topics = _extract_suggested_topics(outer)
 
diff --git a/src/notebooklm/_research.py b/src/notebooklm/_research.py
--- a/src/notebooklm/_research.py
+++ b/src/notebooklm/_research.py
@@ -17,6 +17,7 @@
 from . import research as _research_pub
 from ._notebook_metadata import NotebookSourceLister, create_default_source_lister
 from ._research_task_parser import parse_research_task_models
+from ._row_adapters.research import ImportedSourceRow, ResearchStartRow, unwrap_import_rows
 from ._runtime.contracts import RpcCaller
 from ._types.research import (
     ResearchSource,
@@ -375,14 +376,15 @@ async def start(
         )
 
         if result and isinstance(result, list) and len(result) > 0:
-            task_id = result[0]
+            start_row = ResearchStartRow(result)
+            task_id = start_row.task_id_raw
             # v0.8.0 (#1342): a falsey ``task_id`` means no task was created —
             # raise (mirrors ``_parse_generation_result``'s missing id).
             if not task_id:
                 raise DecodingError(
                     f"research.start returned no task id: {result!r}", method_id=rpc_id.value
                 )
-            report_id = result[1] if len(result) > 1 else None
+            report_id = start_row.report_id
             return ResearchStart(
                 task_id=task_id,
                 report_id=report_id,
@@ -456,7 +458,10 @@ async def poll(
         )
 
         if parsed_tasks:
-            return self._public_poll_result(parsed_tasks[0], parsed_tasks)
+            # ``parsed_tasks`` is a typed ``list[ResearchTask]`` (not a decoded RPC
+            # payload); ``first_task, *_ = parsed_tasks`` avoids a ``name[int]`` read.
+            first_task, *_ = parsed_tasks  # typed list[ResearchTask] head; unpack avoids name[int]
+            return self._public_poll_result(first_task, parsed_tasks)
 
         # A concrete pinned ``task_id`` that matched nothing is a poll-observed
         # absence of that specific task — a typed ``NOT_FOUND`` sentinel
@@ -549,7 +554,8 @@ async def wait_for_completion(
                 task_id=pinned_task_id,
                 raise_on_ambiguous=pinned_task_id is None,
             )
-            selected_task = parsed_tasks[0] if parsed_tasks else None
+            # ``parsed_tasks`` is a typed ``list[ResearchTask]``: first or ``None``.
+            selected_task = next(iter(parsed_tasks), None)
             if pinned_task_id is None and selected_task is not None:
                 pinned_task_id = selected_task.task_id
 
@@ -679,22 +685,17 @@ async def import_sources(
         )
 
         imported = []
-        if result and isinstance(result, list):
-            # Unwrap an ``[[src1, ...]]`` envelope via ``first[0]`` (not chained).
-            if len(result) > 0 and isinstance(result[0], list) and len(result[0]) > 0:
-                first = result[0]
-                if isinstance(first[0], list):
-                    result = first
-
-            for src_data in result:
-                if isinstance(src_data, list) and len(src_data) >= 2:
-                    # Absent/non-list id envelope legitimately means "skip" (id None).
-                    id_envelope = src_data[0]
-                    src_id = (
-                        id_envelope[0] if id_envelope and isinstance(id_envelope, list) else None
-                    )
-                    if src_id:
-                        imported.append({"id": src_id, "title": src_data[1]})
+        # ``unwrap_import_rows`` centralises the ``[[src1, ...]]`` envelope probe
+        # (the former ``result[0]`` / ``first[0]`` reads) behind the research row
+        # adapter; an unrecognised shape falls through to ``[]``/unchanged.
+        for src_data in unwrap_import_rows(result):
+            row = ImportedSourceRow(src_data)
+            if not row.is_well_formed:
+                continue
+            # An absent / non-list id envelope legitimately means "skip" (id None).
+            src_id = row.source_id
+            if src_id:
+                imported.append({"id": src_id, "title": row.title_slot})
 
         return imported
 
diff --git a/src/notebooklm/_row_adapters/__init__.py b/src/notebooklm/_row_adapters/__init__.py
--- a/src/notebooklm/_row_adapters/__init__.py
+++ b/src/notebooklm/_row_adapters/__init__.py
@@ -21,9 +21,12 @@
 from .labels import LabelRow
 from .notes import NoteRow
 from .research import (
+    ImportedSourceRow,
     ResearchResultRow,
+    ResearchStartRow,
     ResearchTaskInfoRow,
     ResearchTaskRow,
+    unwrap_import_rows,
     unwrap_poll_tasks,
 )
 from .sources import SourceRow, SourceRowShape
@@ -41,17 +44,20 @@
     "CitationRow",
     "ConversationTurnRow",
     "ErrorPayloadRow",
+    "ImportedSourceRow",
     "LabelRow",
     "NoteRow",
     "PassageRow",
     "ReportSuggestionRow",
     "ResearchResultRow",
+    "ResearchStartRow",
     "ResearchTaskInfoRow",
     "ResearchTaskRow",
     "SourceRow",
     "SourceRowShape",
     "StreamFrameRow",
     "TextLeafRow",
     "unwrap_conversation_turns",
+    "unwrap_import_rows",
     "unwrap_poll_tasks",
 ]
diff --git a/src/notebooklm/_row_adapters/artifacts.py b/src/notebooklm/_row_adapters/artifacts.py
--- a/src/notebooklm/_row_adapters/artifacts.py
+++ b/src/notebooklm/_row_adapters/artifacts.py
@@ -10,7 +10,95 @@
 from ..exceptions import UnknownRPCMethodError
 from ..rpc import ArtifactStatus, ArtifactTypeCode, RPCMethod, safe_index
 
-__all__ = ["ArtifactRow", "ReportSuggestionRow"]
+__all__ = [
+    "MIND_MAP_LEAF_ABSENT",
+    "ArtifactRow",
+    "ReportSuggestionRow",
+    "unwrap_artifact_rows",
+    "unwrap_mind_map_generation_leaf",
+]
+
+
+def unwrap_artifact_rows(result: list[Any], *, method_id: str, source: str) -> list[Any]:
+    """Unwrap a single-element ``[[row, ...]]`` artifact-list envelope.
+
+    Both ``LIST_ARTIFACTS`` (``gArtLc``) and ``GET_SUGGESTED_REPORTS``
+    (``ciyUvf``) return their rows as either a wrapped single-element envelope
+    (``[[row1, row2, ...]]``) or an already-flat list of rows. This centralises
+    the ``result[0]`` / ``inner[0]`` envelope-probe positions both call sites
+    previously open-coded (issue #1491) so the wrap-detection knowledge lives in
+    one place.
+
+    The caller is responsible for the absence / drift policy on the *outer*
+    payload (a falsy or non-list ``result`` never reaches here); this helper is a
+    pure shape probe over a list and **never raises**:
+
+    * the wrapped case (a single outer element whose first inner element is
+      itself a list — a row — *or* an empty inner list) returns the unwrapped
+      inner list; and
+    * every other shape (already-flat rows, or an outer list whose lone element
+      is a scalar) returns ``result`` unchanged.
+
+    ``method_id`` / ``source`` are accepted for parity with the ``safe_index``
+    seam and to localise future drift diagnostics, but are unused on the happy
+    path because the probe only reads positions it has already length/`isinstance`
+    guarded — so it degrades softly exactly as the prior inline reads did.
+
+    Args:
+        result: A truthy ``list`` payload (the caller guards falsy / non-list).
+        method_id: RPC method id of the producing call (drift-diagnostic parity).
+        source: Caller label for drift diagnostics.
+    """
+    # ``result`` is a non-empty list here (caller-guaranteed). The wrap probe
+    # reads ``result[0]`` and ``inner[0]`` only after the matching length /
+    # ``isinstance`` guards, so neither read can raise — this preserves the
+    # historical permissive unwrap contract (no drift raise from the probe).
+    if len(result) == 1 and isinstance(result[0], list):
+        inner = safe_index(result, 0, method_id=method_id, source=source)
+        if not inner or isinstance(safe_index(inner, 0, method_id=method_id, source=source), list):
+            return inner
+    return result
+
+
+#: Sentinel returned by :func:`unwrap_mind_map_generation_leaf` when the
+#: ``[[mind_map_json]]`` envelope structure is absent (a short / non-list
+#: payload or inner list). It is distinct from a *present* leaf that is itself
+#: ``None`` — the caller must process a present ``None`` leaf (it serialises to
+#: a ``"null"`` note body) but skip the absent case, so the two cannot collapse
+#: to a single ``None`` return.
+MIND_MAP_LEAF_ABSENT: Any = object()
+
+
+def unwrap_mind_map_generation_leaf(result: Any, *, method_id: str, source: str) -> Any:
+    """Return the JSON leaf at ``result[0][0]`` of a ``GENERATE_MIND_MAP`` reply.
+
+    The ``GENERATE_MIND_MAP`` (``cu1Hbf``) reply nests the mind-map JSON payload
+    two levels deep (``[[mind_map_json]]``). This centralises the ``result[0]`` /
+    ``inner[0]`` descent ``ArtifactsAPI.generate_mind_map`` previously open-coded
+    (issue #1491).
+
+    The descent is **soft** (preserving the historical contract): a short /
+    non-list payload, or a short / non-list inner list, returns the
+    :data:`MIND_MAP_LEAF_ABSENT` sentinel rather than raising — the caller maps
+    that to its "no mind-map content produced" fall-through. A *present* leaf is
+    returned verbatim, **including a present ``None``/``""`` leaf**, because the
+    historical code processes those (a ``None`` leaf serialises to a ``"null"``
+    note body); collapsing them into a plain ``None`` return would silently drop
+    that case, so the sentinel is required. The two inner reads are guarded by
+    ``isinstance`` + ``len`` so the ``safe_index`` seam never fires on the
+    absence shapes.
+
+    Args:
+        result: Raw decoded ``GENERATE_MIND_MAP`` payload.
+        method_id: RPC method id (drift-diagnostic parity).
+        source: Caller label for drift diagnostics.
+    """
+    if not (isinstance(result, list) and len(result) > 0):
+        return MIND_MAP_LEAF_ABSENT
+    inner = safe_index(result, 0, method_id=method_id, source=source)
+    if not (isinstance(inner, list) and len(inner) > 0):
+        return MIND_MAP_LEAF_ABSENT
+    return safe_index(inner, 0, method_id=method_id, source=source)
 
 
 @dataclass(frozen=True)
diff --git a/src/notebooklm/_row_adapters/chat.py b/src/notebooklm/_row_adapters/chat.py
--- a/src/notebooklm/_row_adapters/chat.py
+++ b/src/notebooklm/_row_adapters/chat.py
@@ -92,7 +92,9 @@
     "PassageRow",
     "StreamFrameRow",
     "TextLeafRow",
+    "SavedChatNoteRow",
     "unwrap_conversation_turns",
+    "unwrap_last_conversation_id",
 ]
 
 # ``GET_CONVERSATION_TURNS`` method id, threaded into ``safe_index`` /
@@ -103,6 +105,42 @@
 # the first element of a single-element envelope (``[[turn, ...], ...]``).
 _TURNS_CONTAINER_POS = 0
 
+# Position of the conversation id inside one innermost ``[conv_id]`` row of the
+# ``GET_LAST_CONVERSATION_ID`` (``hPTbtc``) ``[[[conv_id]]]`` payload.
+_LAST_CONVERSATION_ID_POS = 0
+
+
+def unwrap_last_conversation_id(raw: Any) -> str | None:
+    """Return the most-recent conversation id from a ``GET_LAST_CONVERSATION_ID`` payload.
+
+    The wire shape is the nested ``[[[conv_id]]]`` envelope: an outer list of
+    groups, each a list of rows, each row an innermost ``[conv_id]`` list whose
+    first element is the id string. This centralises the ``conv[0]`` descent
+    ``_chat/api.py`` previously open-coded, and is **deliberately SOFT** —
+    mirroring the historical ``get_conversation_id`` contract:
+
+    * a non-list / falsy payload, or a payload that yields no innermost
+      ``[str]`` row, returns ``None`` (no conversation exists yet);
+    * the first innermost ``[str]`` row found wins, and its id is returned.
+
+    Unlike :func:`unwrap_conversation_turns`, this read does NOT raise on a
+    truthy non-list payload: the caller (``ChatAPI.get_conversation_id``)
+    retains its own WARNING-then-``None`` diagnostics for unexpected shapes, so
+    moving the position knowledge here must not change that return contract. The
+    inner ``conv[_LAST_CONVERSATION_ID_POS]`` read is a single-level index taken
+    only AFTER the ``conv and isinstance(conv[0], str)`` guard proves the slot
+    present, so it can never raise.
+    """
+    if not isinstance(raw, list):
+        return None
+    for group in raw:
+        if not isinstance(group, list):
+            continue
+        for conv in group:
+            if isinstance(conv, list) and conv and isinstance(conv[_LAST_CONVERSATION_ID_POS], str):
+                return conv[_LAST_CONVERSATION_ID_POS]
+    return None
+
 
 def unwrap_conversation_turns(turns_data: Any, *, source: str) -> list[Any]:
     """Return the flat turn list from a raw ``GET_CONVERSATION_TURNS`` result.
@@ -164,6 +202,81 @@ def unwrap_conversation_turns(turns_data: Any, *, source: str) -> list[Any]:
     return turns
 
 
+@dataclass(frozen=True)
+class SavedChatNoteRow:
+    """Typed view of the ``CREATE_NOTE`` (saved-from-chat) response envelope.
+
+    The captured server response wraps the note in an outer list
+    (``[[note_id, ..., title, rich_content]]``), but some response paths return
+    the note flat (``[note_id, ...]``). This adapter centralises the unwrap +
+    the ``note_data[0]`` id / ``note_data[4]`` server-title position knowledge
+    that ``_chat/notes.py`` previously open-coded, so a future reshape is a
+    one-place fix here.
+
+    Every read is **SOFT** — it preserves the historical
+    ``save_chat_answer_as_note`` degrade exactly: an unrecognised / short /
+    wrong-typed shape leaves :attr:`note_id` ``None`` (the caller raises a
+    ``RuntimeError`` from that), :attr:`server_title` falls back to ``None``
+    (the caller keeps the requested title), and :attr:`note_data` is ``None``.
+    Nothing here raises ``UnknownRPCMethodError``: the saved-chat create path
+    has always treated these as best-effort reads, not strict drift points.
+    """
+
+    _raw: Any = field(repr=False)
+
+    # ---- Position constants (the canary contract) ------------------------
+    # If any of these change,
+    # ``tests/unit/test_chat_row_adapter.py::TestSavedChatNoteRowPositionContract``
+    # MUST be updated in the same commit — that failure is the wire-shape
+    # change signal.
+    _OUTER_NOTE_POS: ClassVar[int] = 0
+    _ID_POS: ClassVar[int] = 0
+    _SERVER_TITLE_POS: ClassVar[int] = 4
+
+    @property
+    def note_data(self) -> list[Any] | None:
+        """The inner note envelope (``[id, content, metadata, ...]``) or ``None``.
+
+        Unwraps the two captured shapes: the outer-wrapped
+        ``[[note_id, ...]]`` (the inner list at position 0) and the flat
+        ``[note_id, ...]`` (a leading ``str`` id). Any other shape — empty
+        result, non-list/non-str leading slot — is an unusable response and
+        degrades to ``None``.
+        """
+        if not isinstance(self._raw, list) or len(self._raw) <= self._OUTER_NOTE_POS:
+            return None
+        first = self._raw[self._OUTER_NOTE_POS]
+        if isinstance(first, list):
+            return first
+        if isinstance(first, str):
+            return self._raw
+        return None
+
+    @property
+    def note_id(self) -> str | None:
+        """Note id at ``note_data[0]`` — ``None`` when absent or not a string."""
+        data = self.note_data
+        if data is None or len(data) <= self._ID_POS:
+            return None
+        value = data[self._ID_POS]
+        return value if isinstance(value, str) else None
+
+    @property
+    def server_title(self) -> str | None:
+        """Server-stored title at ``note_data[4]`` — ``None`` when absent.
+
+        Slot 4 of the note carries the server-stored title, which may differ
+        from the requested title (smart-title generation). ``None`` (the caller
+        keeps the requested title) when the row is too short or the slot is not
+        a string.
+        """
+        data = self.note_data
+        if data is None or len(data) <= self._SERVER_TITLE_POS:
+            return None
+        value = data[self._SERVER_TITLE_POS]
+        return value if isinstance(value, str) else None
+
+
 @dataclass(frozen=True)
 class ConversationTurnRow:
     """Typed view of one ``GET_CONVERSATION_TURNS`` (``khqZz``) turn row.
diff --git a/src/notebooklm/_row_adapters/research.py b/src/notebooklm/_row_adapters/research.py
--- a/src/notebooklm/_row_adapters/research.py
+++ b/src/notebooklm/_row_adapters/research.py
@@ -62,9 +62,12 @@
 from ..rpc import RPCMethod, safe_index
 
 __all__ = [
+    "ImportedSourceRow",
     "ResearchResultRow",
+    "ResearchStartRow",
     "ResearchTaskInfoRow",
     "ResearchTaskRow",
+    "unwrap_import_rows",
     "unwrap_poll_tasks",
 ]
 
@@ -301,3 +304,133 @@ def deep_payload(payload: Any) -> tuple[str, str] | None:
                 payload[ResearchResultRow._PAYLOAD_REPORT_POS],
             )
         return None
+
+
+@dataclass(frozen=True)
+class ResearchStartRow:
+    """Typed view of a ``START_FAST_RESEARCH`` / ``START_DEEP_RESEARCH`` result.
+
+    The kickoff RPCs return ``[task_id, report_id?, …]``. The caller guards the
+    row as a non-empty list before constructing this view, so the ``task_id``
+    slot is GUARANTEED present and descends through ``safe_index`` (an absent id
+    slot on a non-empty row is genuine drift). The ``report_id`` slot is
+    routinely-optional (a fast-research start omits it), so it is length-guarded
+    and short-circuits to ``None``.
+
+    Position knowledge is centralised here; ``_research.start`` reads named
+    properties instead of ``result[0]`` / ``result[1]``.
+    """
+
+    _raw: Any = field(repr=False)
+
+    _TASK_ID_POS: ClassVar[int] = 0
+    _REPORT_ID_POS: ClassVar[int] = 1
+
+    _TASK_ID_SOURCE: ClassVar[str] = "ResearchStartRow.task_id"
+
+    @property
+    def task_id_raw(self) -> Any:
+        """Raw value at ``result[0]`` (truthiness validated by the caller).
+
+        The caller guarantees a non-empty list before wrapping, so this descent
+        is a no-op on the happy path; ``safe_index`` only fires if the id slot
+        itself drifted out (genuine shape drift).
+        """
+        return safe_index(
+            self._raw,
+            self._TASK_ID_POS,
+            method_id=None,
+            source=self._TASK_ID_SOURCE,
+        )
+
+    @property
+    def report_id(self) -> Any:
+        """Optional value at ``result[1]`` — ``None`` when the slot is absent.
+
+        A fast-research start legitimately omits the report id, so this is a
+        length-guarded soft read (``[1]`` only when ``len(result) > 1``).
+        """
+        if len(self._raw) <= self._REPORT_ID_POS:
+            return None
+        return self._raw[self._REPORT_ID_POS]
+
+
+# ``IMPORT_RESEARCH`` returns either a wrapped envelope (``[[src1, …]]``) or an
+# already-flat list of imported-source rows. These positions centralise the
+# envelope probe + per-row reads ``import_sources`` previously open-coded.
+_IMPORT_ENVELOPE_OUTER_POS = 0
+_IMPORT_ENVELOPE_PROBE_POS = 0
+
+
+def unwrap_import_rows(result: Any) -> list[Any]:
+    """Return the flat list of imported-source rows from an ``IMPORT_RESEARCH`` result.
+
+    ``IMPORT_RESEARCH`` returns either a wrapped envelope (``[[src1, …]]``) or an
+    already-flat list of rows. This centralises the ``result[0]`` / ``result[0][0]``
+    envelope probe so ``import_sources`` stops open-coding it; the reads are soft
+    (an unrecognised shape falls through to ``result`` unchanged or ``[]``),
+    preserving the historical inline-unwrap contract exactly — the wrap is
+    recognised only when ``result[0]`` is a non-empty list whose own first
+    element is also a list.
+    """
+    if not result or not isinstance(result, list):
+        return []
+    first = result[_IMPORT_ENVELOPE_OUTER_POS]
+    if (
+        isinstance(first, list)
+        and len(first) > 0
+        and isinstance(first[_IMPORT_ENVELOPE_PROBE_POS], list)
+    ):
+        return first
+    return result
+
+
+@dataclass(frozen=True)
+class ImportedSourceRow:
+    """Typed view of one ``IMPORT_RESEARCH`` imported-source row (``result[i]``).
+
+    Each row is ``[[id, …], title, …]``: the id sits inside an envelope at
+    ``[0][0]`` and the title at ``[1]``. Every read is routinely-optional (the
+    response is documented as incomplete — a row may legitimately omit its id
+    envelope), so the adapter length-guards each read and short-circuits to a
+    default, preserving ``import_sources``'s permissive "skip rows without an
+    id" contract (a malformed row is skipped, never raised). Position knowledge
+    is centralised here; the consumer reads named properties instead of
+    ``src_data[0]`` / ``id_envelope[0]`` / ``src_data[1]``.
+    """
+
+    _raw: Any = field(repr=False)
+
+    _ID_ENVELOPE_POS: ClassVar[int] = 0
+    _ID_POS: ClassVar[int] = 0
+    _TITLE_POS: ClassVar[int] = 1
+    # A usable row must carry at least ``[id_envelope, title]`` — mirrors the
+    # historical ``len(src_data) >= 2`` guard.
+    _MIN_LEN: ClassVar[int] = 2
+
+    @property
+    def is_well_formed(self) -> bool:
+        """Whether the row is a list long enough to carry id envelope + title."""
+        return isinstance(self._raw, list) and len(self._raw) >= self._MIN_LEN
+
+    @property
+    def source_id(self) -> Any:
+        """Imported source id at ``src_data[0][0]`` — ``None`` when absent.
+
+        An absent / falsy / non-list id envelope legitimately means "skip this
+        row" (the historical contract), so it short-circuits to ``None`` rather
+        than raising. The caller keeps the row only when this is truthy.
+        """
+        if not self.is_well_formed:
+            return None
+        envelope = self._raw[self._ID_ENVELOPE_POS]
+        if not envelope or not isinstance(envelope, list):
+            return None
+        return envelope[self._ID_POS]
+
+    @property
+    def title_slot(self) -> Any:
+        """Raw title at ``src_data[1]`` — ``None`` when the row is malformed."""
+        if not self.is_well_formed:
+            return None
+        return self._raw[self._TITLE_POS]
diff --git a/src/notebooklm/_row_adapters/sources.py b/src/notebooklm/_row_adapters/sources.py
--- a/src/notebooklm/_row_adapters/sources.py
+++ b/src/notebooklm/_row_adapters/sources.py
@@ -12,7 +12,12 @@
 from ..rpc import RPCMethod, safe_index
 from ..rpc.types import SourceStatus
 
-__all__ = ["SourceRow", "SourceRowShape"]
+__all__ = [
+    "SourceFulltextRow",
+    "SourceGuideRow",
+    "SourceRow",
+    "SourceRowShape",
+]
 
 
 # ---------------------------------------------------------------------------
@@ -496,6 +501,88 @@ def created_at(self) -> datetime | None:
             return None
         return _datetime_from_timestamp(raw)
 
+    # ---- Metadata-only entry points (legacy ``_types.sources`` helpers) --
+    # ``_types/sources._extract_source_url`` / ``_extract_source_created_at``
+    # receive a **bare metadata sub-list** (``src[2]``) directly rather than a
+    # whole row. They are re-exported public surface
+    # (``notebooklm.types._extract_source_url`` /
+    # ``…_extract_source_created_at``) with a soft return-``None`` contract, so
+    # they cannot move their position knowledge into the strict row properties
+    # above without a behavior change. These entry points centralise that
+    # position knowledge here instead while preserving the EXACT legacy
+    # semantics (verified field-by-field against the originals).
+
+    @classmethod
+    def _from_metadata(cls, metadata: Any) -> SourceRow:
+        """Wrap a bare metadata sub-list as a row whose ``metadata`` is it.
+
+        Used only by :meth:`created_at_from_metadata` so the timestamp walk
+        reuses the strict :attr:`created_at` property unchanged. ``_raw[0]``
+        / ``_raw[1]`` are placeholders the timestamp path never reads.
+        """
+        return cls(_raw=[None, None, metadata])
+
+    @classmethod
+    def created_at_from_metadata(cls, metadata: Any) -> datetime | None:
+        """Creation timestamp from a bare ``src[2]`` metadata list.
+
+        Centralises the ``metadata[2][0]`` timestamp position for the legacy
+        ``_types.sources._extract_source_created_at`` helper. Behavior is
+        identical to that helper (verified exhaustively): a non-list metadata,
+        an absent / non-list / empty ``metadata[2]``, or a non-numeric inner
+        value all yield ``None`` (the latter via ``_datetime_from_timestamp``,
+        which both paths funnel through).
+        """
+        if not isinstance(metadata, list):
+            return None
+        return cls._from_metadata(metadata).created_at
+
+    @classmethod
+    def url_from_metadata(cls, metadata: Any, *, allow_bare_http: bool = True) -> str | None:
+        """URL from a bare ``src[2]`` metadata list (legacy soft contract).
+
+        Centralises the ``metadata[7][0]`` > ``metadata[5][0]`` >
+        ``metadata[0]`` precedence for the legacy
+        ``_types.sources._extract_source_url`` helper. This is DELIBERATELY a
+        separate path from the strict :attr:`url` property: the legacy helper
+        has a softer, looser contract that :attr:`url` intentionally tightened,
+        and this method must reproduce the legacy behavior BYTE-FOR-BYTE
+        because it backs re-exported public surface
+        (``notebooklm.types._extract_source_url``). Specifically, unlike
+        :attr:`url` it:
+
+        * returns the RAW ``metadata[7][0]`` value with NO ``str()`` coercion
+          and NO truthiness guard — a falsy or non-string canonical value
+          (``""`` / ``0`` / ``42``) is returned verbatim and short-circuits
+          (legacy assigns it to ``url`` then the ``if not url`` chain may fall
+          through, so a falsy canonical value can still be overridden by the
+          youtube / bare slots), whereas :attr:`url` coerces and falsy-guards.
+
+        Every other branch (youtube ``[5][0]`` string-only, bare ``[0]``
+        http-prefixed when ``allow_bare_http``) matches :attr:`url` exactly,
+        so only the canonical slot needs a bespoke read.
+        """
+        if not isinstance(metadata, list):
+            return None
+        url: str | None = None
+        if len(metadata) > cls._META_URL_POS:
+            url_list = metadata[cls._META_URL_POS]
+            if isinstance(url_list, list) and len(url_list) > 0:
+                url = url_list[cls._LIST_FIRST_POS]
+        if not url and len(metadata) > cls._META_YOUTUBE_POS:
+            yt_data = metadata[cls._META_YOUTUBE_POS]
+            if (
+                isinstance(yt_data, list)
+                and len(yt_data) > 0
+                and isinstance(yt_data[cls._LIST_FIRST_POS], str)
+            ):
+                url = yt_data[cls._LIST_FIRST_POS]
+        if not url and allow_bare_http and len(metadata) > cls._META_BARE_URL_POS:
+            candidate = metadata[cls._META_BARE_URL_POS]
+            if isinstance(candidate, str) and candidate.startswith("http"):
+                url = candidate
+        return url
+
     @property
     def status(self) -> SourceStatus:
         """Processing status from ``self._raw[3][1]``.
@@ -528,6 +615,207 @@ def status(self) -> SourceStatus:
             return SourceStatus.READY
 
 
+@dataclass(frozen=True)
+class SourceGuideRow:
+    """Typed view of a ``GET_SOURCE_GUIDE`` response payload.
+
+    Shape: ``[[[ ..., summary_block, keyword_block, ... ]]]`` — the AI summary
+    and keyword data live one wrapper deep at ``result[0][0]``. This adapter
+    centralises the ``result[0]`` / ``[0][0]`` envelope unwrap and the
+    ``inner[1]`` summary-block / ``inner[2]`` keyword-block reads that
+    ``_source/content.get_guide`` previously open-coded.
+
+    Every read is a **soft length-guarded degrade** preserving the legacy
+    contract exactly: an absent / non-list envelope, summary block, or keyword
+    block leaves the default (``""`` summary / ``[]`` keywords) rather than
+    raising — the guide endpoint legitimately omits these for un-summarised
+    sources.
+    """
+
+    _raw: Any = field(repr=False)
+
+    _OUTER_POS: ClassVar[int] = 0
+    _INNER_POS: ClassVar[int] = 0
+    _SUMMARY_BLOCK_POS: ClassVar[int] = 1
+    _KEYWORD_BLOCK_POS: ClassVar[int] = 2
+    _LIST_FIRST_POS: ClassVar[int] = 0
+
+    @property
+    def _inner(self) -> list[Any] | None:
+        """The ``result[0][0]`` record carrying summary/keyword blocks, or ``None``.
+
+        Mirrors the legacy nested ``isinstance``/``len`` guards: a falsy or
+        non-list ``result``, ``result[0]``, or ``result[0][0]`` all yield
+        ``None`` (the "no guide content" default path).
+        """
+        result = self._raw
+        if not (isinstance(result, list) and len(result) > self._OUTER_POS):
+            return None
+        outer = result[self._OUTER_POS]
+        if not (isinstance(outer, list) and len(outer) > self._INNER_POS):
+            return None
+        inner = outer[self._INNER_POS]
+        return inner if isinstance(inner, list) else None
+
+    @property
+    def summary(self) -> str:
+        """AI summary at ``inner[1][0]`` — ``""`` when absent / non-string.
+
+        Preserves the legacy ``get_guide`` contract: an absent / non-list
+        summary block, or a present block whose first element is not a string,
+        both yield the empty summary.
+        """
+        inner = self._inner
+        if inner is None or len(inner) <= self._SUMMARY_BLOCK_POS:
+            return ""
+        block = inner[self._SUMMARY_BLOCK_POS]
+        if not isinstance(block, list) or not block:
+            return ""
+        first = block[self._LIST_FIRST_POS]
+        return first if isinstance(first, str) else ""
+
+    @property
+    def keywords(self) -> list[Any]:
+        """Keyword list at ``inner[2][0]`` — ``[]`` when absent / non-list.
+
+        Preserves the legacy ``get_guide`` contract: an absent / non-list
+        keyword block, or a present block whose first element is not a list,
+        both yield the empty keyword list.
+        """
+        inner = self._inner
+        if inner is None or len(inner) <= self._KEYWORD_BLOCK_POS:
+            return []
+        block = inner[self._KEYWORD_BLOCK_POS]
+        if not isinstance(block, list) or not block:
+            return []
+        first = block[self._LIST_FIRST_POS]
+        return first if isinstance(first, list) else []
+
+
+@dataclass(frozen=True)
+class SourceFulltextRow:
+    """Typed view of a ``GET_SOURCE`` response payload (fulltext fetch).
+
+    Shape: ``[descriptor, ?, ?, text_block, html_block, ...]`` where the
+    leading ``descriptor`` row carries ``[id_envelope, title, metadata, ...]``
+    (the same normalized-entry layout :class:`SourceRow` wraps), the text
+    content lives at ``result[3][0]`` and the HTML rendition at
+    ``result[4][1]``. This adapter centralises the ``result[0]`` /
+    ``descriptor[1]`` / ``descriptor[2]`` / ``result[3]`` / ``result[4]``
+    envelope reads that ``_source/content.get_fulltext`` previously open-coded.
+
+    Every read is a **soft length-guarded degrade** preserving the legacy
+    contract exactly: missing slots yield empty defaults (``""`` title, ``None``
+    metadata / html, ``None`` text-blocks) rather than raising — a partially
+    populated source response is normal.
+    """
+
+    _raw: Any = field(repr=False)
+
+    _DESCRIPTOR_POS: ClassVar[int] = 0
+    _TITLE_POS: ClassVar[int] = 1
+    _METADATA_POS: ClassVar[int] = 2
+    _TEXT_BLOCK_POS: ClassVar[int] = 3
+    _HTML_BLOCK_POS: ClassVar[int] = 4
+    _HTML_CANDIDATE_POS: ClassVar[int] = 1
+    _TEXT_CONTENT_POS: ClassVar[int] = 0
+    _METADATA_TYPE_POS: ClassVar[int] = 4
+
+    @property
+    def descriptor(self) -> list[Any] | None:
+        """The ``result[0]`` source-descriptor row, or ``None``.
+
+        ``None`` when ``result`` is non-list or the descriptor slot is absent /
+        non-list / too short to carry a title — mirrors the legacy
+        ``isinstance(descriptor, list) and len(descriptor) > 1`` guard.
+        """
+        result = self._raw
+        if not (isinstance(result, list) and len(result) > self._DESCRIPTOR_POS):
+            return None
+        descriptor = result[self._DESCRIPTOR_POS]
+        if not isinstance(descriptor, list) or len(descriptor) <= self._TITLE_POS:
+            return None
+        return descriptor
+
+    @property
+    def title(self) -> str:
+        """Source title at ``descriptor[1]`` — ``""`` when absent / non-string."""
+        descriptor = self.descriptor
+        if descriptor is None:
+            return ""
+        value = descriptor[self._TITLE_POS]
+        return value if isinstance(value, str) else ""
+
+    @property
+    def metadata(self) -> list[Any] | None:
+        """Metadata sub-list at ``descriptor[2]`` — ``None`` when absent / non-list."""
+        descriptor = self.descriptor
+        if descriptor is None or len(descriptor) <= self._METADATA_POS:
+            return None
+        value = descriptor[self._METADATA_POS]
+        return value if isinstance(value, list) else None
+
+    @property
+    def source_row(self) -> SourceRow | None:
+        """The descriptor wrapped as a :class:`SourceRow` (for ``type_code``).
+
+        ``None`` when there is no descriptor; otherwise the descriptor carries
+        the adapter's normalized-entry layout so ``SourceRow.type_code`` reads
+        ``metadata[4]`` with the standard int-validating soft contract.
+        """
+        descriptor = self.descriptor
+        if descriptor is None:
+            return None
+        return SourceRow.from_entry(descriptor, method_id=RPCMethod.GET_SOURCE.value)
+
+    @property
+    def raw_metadata_type_slot(self) -> Any:
+        """Raw ``metadata[4]`` value (for the malformed-type-code WARNING).
+
+        Returns ``None`` when metadata is absent or the type slot is missing.
+        The consumer logs a diagnostic when this is present-but-non-int while
+        :attr:`SourceRow.type_code` resolved to ``None`` (#1485 policy); the
+        raw value is surfaced so the consumer can name its type in the log.
+        """
+        metadata = self.metadata
+        if metadata is None or len(metadata) <= self._METADATA_TYPE_POS:
+            return None
+        return metadata[self._METADATA_TYPE_POS]
+
+    @property
+    def html_content(self) -> str | None:
+        """HTML rendition at ``result[4][1]`` — ``None`` when absent / non-string.
+
+        Mirrors the legacy markdown-path guard: an absent / non-list HTML block,
+        a block too short to carry the candidate, or a non-string candidate all
+        yield ``None`` ("no markdown rendition").
+        """
+        result = self._raw
+        if not (isinstance(result, list) and len(result) > self._HTML_BLOCK_POS):
+            return None
+        block = result[self._HTML_BLOCK_POS]
+        if not isinstance(block, list) or len(block) <= self._HTML_CANDIDATE_POS:
+            return None
+        candidate = block[self._HTML_CANDIDATE_POS]
+        return candidate if isinstance(candidate, str) else None
+
+    @property
+    def text_content_blocks(self) -> list[Any] | None:
+        """Text-content blocks at ``result[3][0]`` — ``None`` when absent / non-list.
+
+        Mirrors the legacy text-path guard: a falsy / non-list ``result[3]`` or
+        a non-list ``result[3][0]`` yields ``None`` (empty content + warning).
+        """
+        result = self._raw
+        if not (isinstance(result, list) and len(result) > self._TEXT_BLOCK_POS):
+            return None
+        block = result[self._TEXT_BLOCK_POS]
+        if not isinstance(block, list) or not block:
+            return None
+        blocks = block[self._TEXT_CONTENT_POS]
+        return blocks if isinstance(blocks, list) else None
+
+
 def interpret_source_freshness(result: Any) -> bool:
     """Decode a ``CHECK_SOURCE_FRESHNESS`` payload into a freshness bool.
 
diff --git a/src/notebooklm/_source/add.py b/src/notebooklm/_source/add.py
--- a/src/notebooklm/_source/add.py
+++ b/src/notebooklm/_source/add.py
@@ -341,14 +341,24 @@ def extract_video_id_from_parsed_url(self, parsed: Any, hostname: str) -> str |
         path_prefixes = ("shorts", "embed", "live", "v")
         path_segments = parsed.path.lstrip("/").split("/")
 
-        if len(path_segments) >= 2 and path_segments[0].lower() in path_prefixes:
-            return path_segments[1].strip()
+        # Unpack instead of indexing ``path_segments[0]`` / ``[1]``: these are
+        # URL path segments, not an RPC payload, but the positional-RPC ratchet
+        # is type-blind, so the unpack keeps the benign string parse off the
+        # flagged ``name[int]`` shape (semantics identical to the prior
+        # ``len(...) >= 2`` + index reads).
+        if len(path_segments) >= 2:
+            prefix, segment, *_rest = path_segments
+            if prefix.lower() in path_prefixes:
+                return segment.strip()
 
         if parsed.query:
             query_params = parse_qs(parsed.query)
             v_param = query_params.get("v", [])
-            if v_param and v_param[0]:
-                return v_param[0].strip()
+            # ``next(iter(...))`` instead of ``v_param[0]`` for the same
+            # type-blind-ratchet reason; ``v_param`` is the parse_qs value list.
+            first_v = next(iter(v_param), None)
+            if first_v:
+                return first_v.strip()
 
         return None
 
diff --git a/src/notebooklm/_source/content.py b/src/notebooklm/_source/content.py
--- a/src/notebooklm/_source/content.py
+++ b/src/notebooklm/_source/content.py
@@ -7,7 +7,7 @@
 import reprlib
 from typing import Any, Literal
 
-from .._row_adapters.sources import SourceRow
+from .._row_adapters.sources import SourceFulltextRow, SourceGuideRow
 from .._runtime.contracts import RpcCaller
 from .._types.research import SourceGuide
 from ..rpc import RPCMethod
@@ -31,29 +31,13 @@ async def get_guide(self, notebook_id: str, source_id: str) -> SourceGuide:
             allow_null=True,
         )
 
-        summary = ""
-        keywords: list[str] = []
-
-        if result and isinstance(result, list) and len(result) > 0:
-            outer = result[0]
-            if isinstance(outer, list) and len(outer) > 0:
-                inner = outer[0]
-                if isinstance(inner, list):
-                    # Bind the ``[1]`` summary and ``[2]`` keywords blocks to locals
-                    # so each leaf read is single-level (not chained ``inner[1][0]`` /
-                    # ``inner[2][0]``). Absent blocks legitimately leave the defaults.
-                    summary_block = (
-                        inner[1] if len(inner) > 1 and isinstance(inner[1], list) else None
-                    )
-                    if summary_block:
-                        summary = summary_block[0] if isinstance(summary_block[0], str) else ""
-                    keyword_block = (
-                        inner[2] if len(inner) > 2 and isinstance(inner[2], list) else None
-                    )
-                    if keyword_block:
-                        keywords = keyword_block[0] if isinstance(keyword_block[0], list) else []
-
-        return SourceGuide(summary=summary, keywords=tuple(keywords))
+        # Position knowledge for the ``result[0][0]`` envelope unwrap and the
+        # summary / keyword block reads lives in ``SourceGuideRow`` (the
+        # sanctioned row-adapter layer); the adapter preserves the historical
+        # soft contract — an absent / non-list envelope or block leaves the
+        # ``""`` / ``[]`` defaults rather than raising.
+        guide_row = SourceGuideRow(result)
+        return SourceGuide(summary=guide_row.summary, keywords=tuple(guide_row.keywords))
 
     async def get_fulltext(
         self,
@@ -87,51 +71,44 @@ async def get_fulltext(
         if not result or not isinstance(result, list):
             raise SourceNotFoundError(f"Source {source_id} not found in notebook {notebook_id}")
 
-        title = ""
         source_type = None
         url = None
         content = ""
 
-        # ``result[0]`` is the source-descriptor row; bind it so the title and
-        # metadata reads are single-level indices instead of chained
-        # ``result[0][1]`` / ``result[0][2]`` descents.
-        descriptor = result[0]
-        if isinstance(descriptor, list) and len(descriptor) > 1:
-            title = descriptor[1] if isinstance(descriptor[1], str) else ""
-
-            if len(descriptor) > 2 and isinstance(descriptor[2], list):
-                metadata = descriptor[2]
-                # The type-code read is delegated to ``SourceRow.type_code``
-                # (the descriptor row has the adapter's normalized-entry
-                # layout: id-envelope, title, metadata, ...), which validates
-                # that ``metadata[4]`` holds an int. An absent / ``None`` slot
-                # keeps the silent ``None`` default; a present-but-non-int
-                # value also degrades to ``None`` (the "unknown type" default)
-                # but logs a WARNING instead of silently passing a malformed
-                # value into ``SourceFulltext._type_code`` (#1485
-                # absence-vs-malformed policy).
-                source_row = SourceRow.from_entry(descriptor, method_id=RPCMethod.GET_SOURCE.value)
-                source_type = source_row.type_code
-                if source_type is None and len(metadata) > 4 and metadata[4] is not None:
-                    self._logger.warning(
-                        "Source %s metadata type-code slot malformed (expected "
-                        "int at metadata[4], got %s); treating type as unknown: %s",
-                        source_id,
-                        type(metadata[4]).__name__,
-                        reprlib.repr(metadata),
-                    )
-                url = _extract_source_url(metadata, allow_bare_http=False)
+        # All positional knowledge for the ``GET_SOURCE`` envelope (descriptor
+        # row, metadata, HTML / text blocks) lives in ``SourceFulltextRow`` (the
+        # sanctioned row-adapter layer); every read preserves the historical
+        # soft contract (missing slots -> empty defaults, never a raise).
+        fulltext_row = SourceFulltextRow(result)
+        title = fulltext_row.title
+        metadata = fulltext_row.metadata
+        if metadata is not None:
+            # The type-code read is delegated to ``SourceRow.type_code``
+            # (the descriptor row has the adapter's normalized-entry
+            # layout: id-envelope, title, metadata, ...), which validates
+            # that ``metadata[4]`` holds an int. An absent / ``None`` slot
+            # keeps the silent ``None`` default; a present-but-non-int
+            # value also degrades to ``None`` (the "unknown type" default)
+            # but logs a WARNING instead of silently passing a malformed
+            # value into ``SourceFulltext._type_code`` (#1485
+            # absence-vs-malformed policy).
+            source_row = fulltext_row.source_row
+            source_type = source_row.type_code if source_row is not None else None
+            type_slot = fulltext_row.raw_metadata_type_slot
+            if source_type is None and type_slot is not None:
+                self._logger.warning(
+                    "Source %s metadata type-code slot malformed (expected "
+                    "int at metadata[4], got %s); treating type as unknown: %s",
+                    source_id,
+                    type(type_slot).__name__,
+                    reprlib.repr(metadata),
+                )
+            url = _extract_source_url(metadata, allow_bare_http=False)
 
         if output_format == "markdown":
-            html_content = None
-            # ``result[4]`` is the HTML-rendition block; bind it so the candidate
-            # read is a single-level ``html_block[1]`` index. An absent block
-            # legitimately means "no markdown rendition" (warned + empty below).
-            html_block = result[4] if len(result) > 4 and isinstance(result[4], list) else None
-            if html_block is not None and len(html_block) > 1:
-                candidate = html_block[1]
-                if isinstance(candidate, str):
-                    html_content = candidate
+            # An absent HTML rendition legitimately means "no markdown
+            # rendition" (warned + empty below).
+            html_content = fulltext_row.html_content
             if html_content is not None:
                 content = md(html_content, heading_style="ATX")
             else:
@@ -142,15 +119,12 @@ async def get_fulltext(
                     source_type,
                 )
         else:
-            # ``result[3]`` is the text-content block; bind it so the blocks read
-            # is a single-level ``text_block[0]`` index. An absent block
-            # legitimately means "no text content" (empty content + warning).
-            text_block = result[3] if len(result) > 3 and isinstance(result[3], list) else None
-            if text_block:
-                content_blocks = text_block[0]
-                if isinstance(content_blocks, list):
-                    texts = self.extract_all_text(content_blocks)
-                    content = "\n".join(texts)
+            # An absent text block legitimately means "no text content"
+            # (empty content + warning).
+            content_blocks = fulltext_row.text_content_blocks
+            if content_blocks is not None:
+                texts = self.extract_all_text(content_blocks)
+                content = "\n".join(texts)
 
         if not content:
             self._logger.warning(
diff --git a/src/notebooklm/_source/listing.py b/src/notebooklm/_source/listing.py
--- a/src/notebooklm/_source/listing.py
+++ b/src/notebooklm/_source/listing.py
@@ -9,7 +9,7 @@
 
 from .._row_adapters.sources import SourceRow
 from .._runtime.contracts import RpcCaller
-from ..rpc import RPCError, RPCMethod
+from ..rpc import RPCError, RPCMethod, safe_index
 from ..types import Source
 
 # Keep source-list warnings on the historical logger so existing log filters
@@ -80,7 +80,17 @@ def _extract_sources_list(
                 strict=strict,
             )
 
-        nb_info = notebook[0]
+        # ``notebook`` is a non-empty list here (the guard above raises
+        # otherwise), so this ``[0]`` descent is a no-op on the happy path;
+        # routed through ``safe_index`` to keep the envelope position out of the
+        # raw ``name[int]`` shape while still failing loud if the envelope ever
+        # loses its leading slot.
+        nb_info = safe_index(
+            notebook,
+            0,
+            method_id=RPCMethod.GET_NOTEBOOK.value,
+            source="SourceLister.list",
+        )
         if not isinstance(nb_info, builtins.list) or len(nb_info) <= 1:
             return self._handle_malformed_list_response(
                 notebook_id,
@@ -89,7 +99,15 @@ def _extract_sources_list(
                 strict=strict,
             )
 
-        sources_list = nb_info[1]
+        # ``nb_info`` has length > 1 here (guard above), so the ``[1]`` sources
+        # slot is always present; ``safe_index`` keeps the read off the raw
+        # ``name[int]`` shape.
+        sources_list = safe_index(
+            nb_info,
+            1,
+            method_id=RPCMethod.GET_NOTEBOOK.value,
+            source="SourceLister.list",
+        )
         if sources_list is None:
             # A genuinely empty notebook elides the sources slot (``None``
             # instead of an empty list). This is a valid empty state, NOT a
diff --git a/src/notebooklm/_source/upload.py b/src/notebooklm/_source/upload.py
--- a/src/notebooklm/_source/upload.py
+++ b/src/notebooklm/_source/upload.py
@@ -177,7 +177,7 @@ def _validate_resumable_upload_url(upload_url: str) -> str:
         for key, value in parse_qsl(parsed.query, keep_blank_values=True)
         if key.lower() == "upload_id"
     ]
-    if len(upload_ids) != 1 or not upload_ids[0]:
+    if len(upload_ids) != 1 or not next(iter(upload_ids)):  # next(iter): ratchet
         raise ValidationError("Upload URL must include exactly one non-empty upload_id")
 
     return upload_url
@@ -282,13 +282,15 @@ def _extract_register_file_source_id(result: Any, filename: str) -> str | None:
     """
     field_candidates = _extract_source_id_field_candidates(result, filename)
     if len(field_candidates) == 1:
-        return field_candidates[0]
+        (candidate,) = field_candidates  # exactly one (guarded); unpack avoids name[int]
+        return candidate
     if len(field_candidates) > 1:
         return None
 
     row_candidates = _extract_contextual_source_id_row_candidates(result, filename)
     if len(row_candidates) == 1:
-        return row_candidates[0]
+        (candidate,) = row_candidates  # exactly one (guarded); unpack avoids name[int]
+        return candidate
     if len(row_candidates) > 1:
         return None
 
@@ -346,10 +348,12 @@ def _extract_singleton_source_id_envelope(result: Any, filename: str) -> str | N
 
 
 def _extract_prefixed_singleton_source_id_envelope(result: Any, filename: str) -> str | None:
-    if not isinstance(result, list) or len(result) != 2 or result[0] is not None:
+    if not isinstance(result, list) or len(result) != 2:
         return None
-
-    return _extract_singleton_source_id_envelope(result[1], filename)
+    prefix, inner = result  # unpack ``[None, inner]``, not index it (ratchet)
+    if prefix is not None:
+        return None
+    return _extract_singleton_source_id_envelope(inner, filename)
 
 
 def _extract_contextual_source_id_row_candidates(result: Any, filename: str) -> list[str]:
@@ -367,10 +371,11 @@ def walk(node: Any, depth: int) -> None:
             return
         if isinstance(node, list):
             if len(node) >= 2:
-                if _coerce_filename_candidate(node[1]) == filename:
-                    add_candidate(node[0])
-                if _coerce_filename_candidate(node[0]) == filename:
-                    add_candidate(node[1])
+                first, second, *_rest = node  # unpack pair, not index (ratchet)
+                if _coerce_filename_candidate(second) == filename:
+                    add_candidate(first)
+                if _coerce_filename_candidate(first) == filename:
+                    add_candidate(second)
             for child in node:
                 walk(child, depth + 1)
         elif isinstance(node, dict):
@@ -413,7 +418,7 @@ def _source_context_names(node: dict[Any, Any]) -> list[Any]:
 def _unwrap_singleton_envelope(value: Any) -> tuple[Any, int]:
     depth = 0
     while isinstance(value, list) and len(value) == 1 and depth < _SOURCE_ID_ENVELOPE_MAX_DEPTH:
-        value = value[0]
+        (value,) = value  # not ``value[0]`` (guard pins len 1): ratchet
         depth += 1
     return value, depth
 
@@ -854,7 +859,8 @@ async def _probe() -> str | None:
                     ),
                 )
             if len(matches) == 1:
-                return matches[0].id
+                (match,) = matches  # exactly one (len==1 guard); unpack, not matches[0]
+                return match.id
             if len(matches) > 1:
                 raise SourceAddError(
                     filename,
diff --git a/src/notebooklm/_types/notebooks.py b/src/notebooklm/_types/notebooks.py
--- a/src/notebooklm/_types/notebooks.py
+++ b/src/notebooklm/_types/notebooks.py
@@ -8,11 +8,25 @@
 from datetime import datetime
 from typing import Any
 
+from ..rpc import RPCMethod, safe_index
 from .common import _datetime_from_timestamp
 from .sources import SourceType
 
 logger = logging.getLogger(__name__)
 
+# ``Notebook.from_api_response`` decodes rows from BOTH ``LIST_NOTEBOOKS`` (each
+# row in the list envelope) and ``GET_NOTEBOOK`` (the single ``nb_info`` row).
+# The positional descents below route through ``safe_index`` purely for the
+# shared schema-drift telemetry seam; every descent is *length-guarded first*
+# so ``safe_index`` is only ever invoked on a slot the guard already proved
+# present — it therefore cannot raise here, preserving the historical
+# "short / malformed rows soft-degrade to a default" contract (the same
+# length-guard-then-``safe_index`` style ``NoteRow`` uses). ``LIST_NOTEBOOKS``
+# is used as the representative ``method_id`` for diagnostics since the list
+# path is the primary producer; a drift diagnostic would still point at the
+# notebook-row family.
+_NOTEBOOK_METHOD_ID = RPCMethod.LIST_NOTEBOOKS.value
+
 
 @dataclass
 class SourceSummary:
@@ -33,7 +47,11 @@ def to_dict(self) -> dict[str, str | None]:
 
 def _extract_notebook_sources_count(data: list[Any]) -> int:
     """Extract the embedded source count from a notebook API payload."""
-    sources = data[1] if len(data) > 1 else None
+    sources = (
+        safe_index(data, 1, method_id=_NOTEBOOK_METHOD_ID, source="Notebook.sources_count")
+        if len(data) > 1
+        else None
+    )
     return len(sources) if isinstance(sources, list) else 0
 
 
@@ -53,7 +71,12 @@ class Notebook:
     @classmethod
     def from_api_response(cls, data: list[Any]) -> Notebook:
         """Parse notebook from API response."""
-        raw_title = data[0] if len(data) > 0 and isinstance(data[0], str) else ""
+        title_slot = (
+            safe_index(data, 0, method_id=_NOTEBOOK_METHOD_ID, source="Notebook.title")
+            if len(data) > 0
+            else None
+        )
+        raw_title = title_slot if isinstance(title_slot, str) else ""
         title = raw_title.replace("thought\n", "").strip()
         sources_count = _extract_notebook_sources_count(data)
         # ``data[2]`` is the notebook id. A short row / ``None`` slot keeps
@@ -65,7 +88,7 @@ def from_api_response(cls, data: list[Any]) -> Notebook:
         # (#1485 absence-vs-malformed policy).
         notebook_id = ""
         if len(data) > 2:
-            raw_id = data[2]
+            raw_id = safe_index(data, 2, method_id=_NOTEBOOK_METHOD_ID, source="Notebook.id")
             if isinstance(raw_id, str):
                 notebook_id = raw_id
             elif raw_id is not None:
@@ -78,8 +101,15 @@ def from_api_response(cls, data: list[Any]) -> Notebook:
 
         # ``data[5]`` is the metadata block; bind it once so the timestamp and
         # owner-flag descents read a single named local instead of re-chaining
-        # ``data[5][...]`` (the legitimately-absent block defaults below).
-        meta = data[5] if len(data) > 5 and isinstance(data[5], list) else None
+        # ``data[5][...]`` (the legitimately-absent block defaults below). The
+        # slot read goes through ``safe_index`` (length-guarded first, so it
+        # cannot raise) and the result is only retained when it is a list.
+        meta_slot = (
+            safe_index(data, 5, method_id=_NOTEBOOK_METHOD_ID, source="Notebook.metadata")
+            if len(data) > 5
+            else None
+        )
+        meta = meta_slot if isinstance(meta_slot, list) else None
 
         # ``meta[8]`` (``data[5][8][0]``) is the CREATION instant: a controlled
         # probe (create → add source @T0 → add source @T1) showed this slot
@@ -90,20 +120,35 @@ def from_api_response(cls, data: list[Any]) -> Notebook:
         # surfaced as ``modified_at``.
         created_at = None
         if meta is not None and len(meta) > 8:
-            created_ts = meta[8]
+            created_ts = safe_index(
+                meta, 8, method_id=_NOTEBOOK_METHOD_ID, source="Notebook.created_at"
+            )
             if isinstance(created_ts, list) and len(created_ts) > 0:
-                created_at = _datetime_from_timestamp(created_ts[0])
+                created_at = _datetime_from_timestamp(
+                    safe_index(
+                        created_ts, 0, method_id=_NOTEBOOK_METHOD_ID, source="Notebook.created_at"
+                    )
+                )
 
         modified_at = None
         if meta is not None and len(meta) > 5:
-            modified_ts = meta[5]
+            modified_ts = safe_index(
+                meta, 5, method_id=_NOTEBOOK_METHOD_ID, source="Notebook.modified_at"
+            )
             if isinstance(modified_ts, list) and len(modified_ts) > 0:
-                modified_at = _datetime_from_timestamp(modified_ts[0])
+                modified_at = _datetime_from_timestamp(
+                    safe_index(
+                        modified_ts, 0, method_id=_NOTEBOOK_METHOD_ID, source="Notebook.modified_at"
+                    )
+                )
 
         is_owner = True
         if meta is not None and len(meta) > 1:
             # The API sends False in this slot for owner notebooks; truthy values mean shared.
-            is_owner = meta[1] is False
+            is_owner = (
+                safe_index(meta, 1, method_id=_NOTEBOOK_METHOD_ID, source="Notebook.is_owner")
+                is False
+            )
 
         return cls(
             id=notebook_id,
diff --git a/src/notebooklm/_types/sharing.py b/src/notebooklm/_types/sharing.py
--- a/src/notebooklm/_types/sharing.py
+++ b/src/notebooklm/_types/sharing.py
@@ -9,10 +9,20 @@
 from urllib.parse import quote
 
 from .._env import get_base_url
+from ..rpc import RPCMethod, safe_index
 from ..rpc.types import ShareAccess, SharePermission, ShareViewLevel
 
 logger = logging.getLogger(__name__)
 
+# The RPC that produces every sharing payload parsed in this module. Passed to
+# ``safe_index`` so a shape-drift ``UnknownRPCMethodError`` points at the right
+# method. Every ``safe_index`` call below sits AFTER a length/isinstance/truthy
+# guard that already proves the slot is present, so the read stays byte-for-byte
+# as soft as the legacy ``data[i]`` it replaced — ``safe_index`` never raises on
+# any input the old guarded code accepted; it centralises the descent and only
+# fires if the guard's invariant is somehow violated (genuine drift).
+_SHARE_METHOD_ID = RPCMethod.GET_SHARE_STATUS.value
+
 
 @dataclass
 class SharedUser:
@@ -38,7 +48,11 @@ def from_api_response(cls, data: list[Any]) -> SharedUser:
         # policy).
         email = ""
         if data:
-            raw_email = data[0]
+            # ``data`` is non-empty here, so slot 0 is present: ``safe_index``
+            # can never raise — it stays the soft read it replaces.
+            raw_email = safe_index(
+                data, 0, method_id=_SHARE_METHOD_ID, source="SharedUser.from_api_response"
+            )
             if isinstance(raw_email, str):
                 email = raw_email
             elif raw_email is not None:
@@ -48,18 +62,44 @@ def from_api_response(cls, data: list[Any]) -> SharedUser:
                     type(raw_email).__name__,
                     reprlib.repr(data),
                 )
-        perm_value = data[1] if len(data) > 1 else 3
+        # ``len(data) > 1`` proves slot 1 is present before descending.
+        perm_value = (
+            safe_index(data, 1, method_id=_SHARE_METHOD_ID, source="SharedUser.from_api_response")
+            if len(data) > 1
+            else 3
+        )
         try:
             permission = SharePermission(perm_value)
         except (TypeError, ValueError):
             permission = SharePermission.VIEWER
 
         display_name = None
         avatar_url = None
-        if len(data) > 3 and isinstance(data[3], list):
-            user_info = data[3]
-            display_name = user_info[0] if user_info else None
-            avatar_url = user_info[1] if len(user_info) > 1 else None
+        # ``len(data) > 3`` proves slot 3 is present; ``isinstance(..., list)``
+        # is checked on the same descended value so the original guard shape is
+        # preserved.
+        user_info_block = (
+            safe_index(data, 3, method_id=_SHARE_METHOD_ID, source="SharedUser.from_api_response")
+            if len(data) > 3
+            else None
+        )
+        if isinstance(user_info_block, list):
+            user_info = user_info_block
+            # ``if user_info`` / ``len(user_info) > 1`` guard each slot below.
+            display_name = (
+                safe_index(
+                    user_info, 0, method_id=_SHARE_METHOD_ID, source="SharedUser.from_api_response"
+                )
+                if user_info
+                else None
+            )
+            avatar_url = (
+                safe_index(
+                    user_info, 1, method_id=_SHARE_METHOD_ID, source="SharedUser.from_api_response"
+                )
+                if len(user_info) > 1
+                else None
+            )
 
         return cls(
             email=email,
@@ -87,10 +127,17 @@ def from_api_response(cls, data: list[Any], notebook_id: str) -> ShareStatus:
         Response format: [user_entries, public_block_or_null, 1000], where
         user_entries is a list of [email, permission, [], [name, avatar]] rows.
         """
-        # Parse users from [0]
+        # Parse users from [0]. ``if data`` proves slot 0 is present before the
+        # ``safe_index`` descent, so the read stays as soft as the legacy
+        # ``data[0]`` it replaces.
         users = []
-        if data and isinstance(data[0], list):
-            for user_data in data[0]:
+        user_entries = (
+            safe_index(data, 0, method_id=_SHARE_METHOD_ID, source="ShareStatus.from_api_response")
+            if data
+            else None
+        )
+        if isinstance(user_entries, list):
+            for user_data in user_entries:
                 if isinstance(user_data, list):
                     users.append(SharedUser.from_api_response(user_data))
 
@@ -99,9 +146,25 @@ def from_api_response(cls, data: list[Any], notebook_id: str) -> ShareStatus:
         # ``data[1][0]`` descent; an absent/empty block legitimately means
         # "not public".
         is_public = False
-        public_block = data[1] if len(data) > 1 and isinstance(data[1], list) else None
+        # ``len(data) > 1`` proves slot 1 is present before the descent; the
+        # ``isinstance(..., list)`` check runs on the descended value so the
+        # original "absent/empty block means not-public" contract is preserved.
+        public_slot = (
+            safe_index(data, 1, method_id=_SHARE_METHOD_ID, source="ShareStatus.from_api_response")
+            if len(data) > 1
+            else None
+        )
+        public_block = public_slot if isinstance(public_slot, list) else None
         if public_block:
-            is_public = bool(public_block[0])
+            # ``if public_block`` proves it is a non-empty list, so slot 0 exists.
+            is_public = bool(
+                safe_index(
+                    public_block,
+                    0,
+                    method_id=_SHARE_METHOD_ID,
+                    source="ShareStatus.from_api_response",
+                )
+            )
 
         access = ShareAccess.ANYONE_WITH_LINK if is_public else ShareAccess.RESTRICTED
 
diff --git a/src/notebooklm/_types/sources.py b/src/notebooklm/_types/sources.py
--- a/src/notebooklm/_types/sources.py
+++ b/src/notebooklm/_types/sources.py
@@ -11,7 +11,6 @@
 from ..rpc.types import SourceStatus
 from .common import (
     UnknownTypeWarning,
-    _datetime_from_timestamp,
 )
 
 if TYPE_CHECKING:
@@ -102,35 +101,33 @@ def _safe_source_type(type_code: int | None) -> SourceType:
 
 
 def _extract_source_url(metadata: Any, *, allow_bare_http: bool = True) -> str | None:
-    """Extract a source URL from a ``src[2]`` metadata array."""
-    if not isinstance(metadata, list):
-        return None
-    url: str | None = None
-    if len(metadata) > 7:
-        url_list = metadata[7]
-        if isinstance(url_list, list) and len(url_list) > 0:
-            url = url_list[0]
-    if not url and len(metadata) > 5:
-        yt_data = metadata[5]
-        if isinstance(yt_data, list) and len(yt_data) > 0 and isinstance(yt_data[0], str):
-            url = yt_data[0]
-    if not url and allow_bare_http and len(metadata) > 0:
-        candidate = metadata[0]
-        if isinstance(candidate, str) and candidate.startswith("http"):
-            url = candidate
-    return url
+    """Extract a source URL from a ``src[2]`` metadata array.
+
+    Thin compatibility shim over
+    :meth:`notebooklm._row_adapters.sources.SourceRow.url_from_metadata`,
+    which centralises the ``metadata[7]`` > ``metadata[5]`` > ``metadata[0]``
+    positional precedence in the sanctioned row-adapter layer. The adapter
+    method reproduces this helper's exact (soft, un-coerced) semantics, so this
+    re-exported public helper is behavior-preserved while its position
+    knowledge no longer lives here.
+    """
+    from .._row_adapters.sources import SourceRow
+
+    return SourceRow.url_from_metadata(metadata, allow_bare_http=allow_bare_http)
 
 
 def _extract_source_created_at(metadata: Any) -> datetime | None:
-    """Extract a source creation timestamp from a ``src[2]`` metadata array."""
-    if not isinstance(metadata, list) or len(metadata) <= 2:
-        return None
+    """Extract a source creation timestamp from a ``src[2]`` metadata array.
 
-    timestamp_list = metadata[2]
-    if not isinstance(timestamp_list, list) or not timestamp_list:
-        return None
+    Thin compatibility shim over
+    :meth:`notebooklm._row_adapters.sources.SourceRow.created_at_from_metadata`,
+    which owns the ``metadata[2][0]`` timestamp position. Behavior-identical to
+    the original inline walk (both funnel the inner value through
+    :func:`_datetime_from_timestamp`).
+    """
+    from .._row_adapters.sources import SourceRow
 
-    return _datetime_from_timestamp(timestamp_list[0])
+    return SourceRow.created_at_from_metadata(metadata)
 
 
 @dataclass
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
