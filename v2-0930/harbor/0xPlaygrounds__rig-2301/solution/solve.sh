#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/MIGRATING.md b/MIGRATING.md
--- a/MIGRATING.md
+++ b/MIGRATING.md
@@ -1900,8 +1900,8 @@ Bound the loop with `.max_invalid_tool_call_retries(n)` on either prompt builder
 
 ### 3. The streaming final response carries content, not a string
 
-`MultiTurnStreamItem::final_response` and `final_response_with_history` take
-`OneOrMany<AssistantContent>` where they took `&str`:
+`MultiTurnStreamItem::final_response` takes
+`OneOrMany<AssistantContent>` where it took `&str`:
 
 ```rust
 // before
diff --git a/crates/rig-agent/src/agent/prompt_request/streaming.rs b/crates/rig-agent/src/agent/prompt_request/streaming.rs
--- a/crates/rig-agent/src/agent/prompt_request/streaming.rs
+++ b/crates/rig-agent/src/agent/prompt_request/streaming.rs
@@ -158,19 +158,6 @@ impl MultiTurnStreamItem {
         ))
     }
 
-    pub fn final_response_with_history(
-        content: Vec<AssistantContent>,
-        aggregated_usage: crate::completion::Usage,
-        history: Option<Vec<Message>>,
-    ) -> Self {
-        Self::FinalResponse(final_response_from_content(
-            content,
-            aggregated_usage,
-            Vec::new(),
-            history,
-        ))
-    }
-
     pub(crate) fn final_response_with_completion_calls(
         content: Vec<AssistantContent>,
         aggregated_usage: crate::completion::Usage,
diff --git a/crates/rig-agent/src/agent/run/mod.rs b/crates/rig-agent/src/agent/run/mod.rs
--- a/crates/rig-agent/src/agent/run/mod.rs
+++ b/crates/rig-agent/src/agent/run/mod.rs
@@ -649,16 +649,7 @@ impl AgentRun {
         let RunState::ResolvingToolCalls(resolving) = &self.state else {
             return None;
         };
-        let AssistantContent::ToolCall(tool_call) = resolving.items.get(resolving.next_index)?
-        else {
-            return None;
-        };
-        if resolving
-            .allowed_tool_names
-            .contains(&tool_call.function.name)
-        {
-            return None;
-        }
+        let tool_call = pending_invalid_call(resolving)?;
 
         Some(InvalidToolCallContext {
             tool_name: tool_call.function.name.clone(),
diff --git a/crates/rig-agent/src/agent/run/streamed.rs b/crates/rig-agent/src/agent/run/streamed.rs
--- a/crates/rig-agent/src/agent/run/streamed.rs
+++ b/crates/rig-agent/src/agent/run/streamed.rs
@@ -653,20 +653,17 @@ impl StreamedTurnAssembler {
                 internal_call_id,
             } => {
                 if !self.allowed_tool_names.contains(&tool_call.function.name) {
-                    let invalid = StreamedInvalidToolCall {
-                        tool_call: tool_call.clone(),
-                        internal_call_id: internal_call_id.clone(),
-                        args: Some(json_utils::serialize_json_value(
+                    return Ok(self.surface_invalid_call(
+                        tool_call.clone(),
+                        internal_call_id.clone(),
+                        Some(json_utils::serialize_json_value(
                             &tool_call.function.arguments,
                         )),
-                        executable_tool_names: self.executable_tool_names.clone(),
-                        allowed_tool_names: self.allowed_tool_names.clone(),
-                    };
-                    self.pending_invalid = Some(PendingInvalid::FullCall {
-                        tool_call: Box::new(tool_call.clone()),
-                        internal_call_id: internal_call_id.clone(),
-                    });
-                    return Ok(vec![StreamedTurnEvent::InvalidToolCall(Box::new(invalid))]);
+                        PendingInvalid::FullCall {
+                            tool_call: Box::new(tool_call.clone()),
+                            internal_call_id: internal_call_id.clone(),
+                        },
+                    ));
                 }
 
                 self.pending_tool_calls
@@ -686,18 +683,16 @@ impl StreamedTurnAssembler {
                                 .get(&key)
                                 .map(|state| state.buffered_arguments.join(""))
                                 .unwrap_or_default();
-                            let invalid = StreamedInvalidToolCall {
-                                tool_call: self
-                                    .name_delta_diagnostic_tool_call(name, &buffered_args),
-                                internal_call_id: internal_call_id.clone(),
-                                args: Some(buffered_args),
-                                executable_tool_names: self.executable_tool_names.clone(),
-                                allowed_tool_names: self.allowed_tool_names.clone(),
-                            };
-                            self.pending_invalid = Some(PendingInvalid::NameDelta {
-                                internal_call_id: internal_call_id.clone(),
-                            });
-                            return Ok(vec![StreamedTurnEvent::InvalidToolCall(Box::new(invalid))]);
+                            let tool_call =
+                                self.name_delta_diagnostic_tool_call(name, &buffered_args);
+                            return Ok(self.surface_invalid_call(
+                                tool_call,
+                                internal_call_id.clone(),
+                                Some(buffered_args),
+                                PendingInvalid::NameDelta {
+                                    internal_call_id: internal_call_id.clone(),
+                                },
+                            ));
                         }
 
                         Ok(self.validate_delta_name(&key, name.clone()))
@@ -851,6 +846,26 @@ impl StreamedTurnAssembler {
         }
     }
 
+    /// Park resolution on `pending` and surface the rejected call to the
+    /// caller as an [`StreamedTurnEvent::InvalidToolCall`].
+    fn surface_invalid_call(
+        &mut self,
+        tool_call: ToolCall,
+        internal_call_id: String,
+        args: Option<String>,
+        pending: PendingInvalid,
+    ) -> Vec<StreamedTurnEvent> {
+        let invalid = StreamedInvalidToolCall {
+            tool_call,
+            internal_call_id,
+            args,
+            executable_tool_names: self.executable_tool_names.clone(),
+            allowed_tool_names: self.allowed_tool_names.clone(),
+        };
+        self.pending_invalid = Some(pending);
+        vec![StreamedTurnEvent::InvalidToolCall(Box::new(invalid))]
+    }
+
     fn name_delta_diagnostic_tool_call(&self, name: &str, buffered_args: &str) -> ToolCall {
         let diagnostic_args = if buffered_args.trim().is_empty() {
             serde_json::Value::Null
diff --git a/crates/rig-agent/src/agent/tool.rs b/crates/rig-agent/src/agent/tool.rs
--- a/crates/rig-agent/src/agent/tool.rs
+++ b/crates/rig-agent/src/agent/tool.rs
@@ -45,7 +45,7 @@ impl Agent {
 
         DynamicTool::new(name, description, parameters, move |context, args| {
             let agent = Arc::clone(&agent);
-            let inherited_context = context.inbound_only();
+            let inherited_context = context.for_dispatch();
             Box::pin(async move {
                 let args: AgentToolArgs = serde_json::from_value(args).map_err(|error| {
                     ToolExecutionError::invalid_args(format!(
diff --git a/crates/rig-agent/src/completion.rs b/crates/rig-agent/src/completion.rs
--- a/crates/rig-agent/src/completion.rs
+++ b/crates/rig-agent/src/completion.rs
@@ -58,31 +58,44 @@ pub enum PromptError {
     },
 }
 
-impl PromptError {
-    /// Returns the provider response body exposed by a wrapped completion error.
-    pub fn provider_response_body(&self) -> Option<&str> {
-        match self {
-            Self::CompletionError(error) => error.provider_response_body(),
-            _ => None,
-        }
-    }
+/// Forwards the `provider_response_*` accessor trio through the variant that
+/// wraps an error which itself exposes them.
+macro_rules! forward_provider_response_helpers {
+    ($err:ident, $variant:ident, $inner:literal) => {
+        impl $err {
+            #[doc = concat!("Returns the provider response body exposed by a wrapped ", $inner, ".")]
+            pub fn provider_response_body(&self) -> Option<&str> {
+                match self {
+                    Self::$variant(error) => error.provider_response_body(),
+                    _ => None,
+                }
+            }
+
+            #[doc = concat!("Parses the provider response body of a wrapped ", $inner, " as JSON when present.")]
+            pub fn provider_response_json(
+                &self,
+            ) -> Result<Option<serde_json::Value>, serde_json::Error> {
+                match self {
+                    Self::$variant(error) => error.provider_response_json(),
+                    _ => Ok(None),
+                }
+            }
 
-    /// Parses a wrapped provider response body as JSON when present.
-    pub fn provider_response_json(&self) -> Result<Option<serde_json::Value>, serde_json::Error> {
-        match self {
-            Self::CompletionError(error) => error.provider_response_json(),
-            _ => Ok(None),
+            #[doc = concat!("Returns the HTTP status exposed by a wrapped ", $inner, ".")]
+            pub fn provider_response_status(&self) -> Option<http::StatusCode> {
+                match self {
+                    Self::$variant(error) => error.provider_response_status(),
+                    _ => None,
+                }
+            }
         }
-    }
+    };
+}
 
-    /// Returns the HTTP status exposed by a wrapped completion error.
-    pub fn provider_response_status(&self) -> Option<http::StatusCode> {
-        match self {
-            Self::CompletionError(error) => error.provider_response_status(),
-            _ => None,
-        }
-    }
+forward_provider_response_helpers!(PromptError, CompletionError, "completion error");
+forward_provider_response_helpers!(StructuredOutputError, PromptError, "prompt error");
 
+impl PromptError {
     pub(crate) fn prompt_cancelled(
         chat_history: impl IntoIterator<Item = Message>,
         reason: impl Into<String>,
@@ -109,32 +122,6 @@ pub enum StructuredOutputError {
     EmptyResponse,
 }
 
-impl StructuredOutputError {
-    /// Returns the provider response body exposed through the wrapped prompt error.
-    pub fn provider_response_body(&self) -> Option<&str> {
-        match self {
-            Self::PromptError(error) => error.provider_response_body(),
-            _ => None,
-        }
-    }
-
-    /// Parses the wrapped provider response body as JSON when present.
-    pub fn provider_response_json(&self) -> Result<Option<serde_json::Value>, serde_json::Error> {
-        match self {
-            Self::PromptError(error) => error.provider_response_json(),
-            _ => Ok(None),
-        }
-    }
-
-    /// Returns the provider HTTP status exposed through the wrapped prompt error.
-    pub fn provider_response_status(&self) -> Option<http::StatusCode> {
-        match self {
-            Self::PromptError(error) => error.provider_response_status(),
-            _ => None,
-        }
-    }
-}
-
 /// High-level one-shot prompting for the classic runtime.
 pub trait Prompt: WasmCompatSend + WasmCompatSync {
     /// Send a prompt and return accepted assistant text after runtime orchestration.
diff --git a/crates/rig-agent/src/tool/extensions.rs b/crates/rig-agent/src/tool/extensions.rs
--- a/crates/rig-agent/src/tool/extensions.rs
+++ b/crates/rig-agent/src/tool/extensions.rs
@@ -264,11 +264,6 @@ impl ToolContext {
     pub(crate) fn clear_dispatch_result(&mut self) {
         self.result = TypeMap::EMPTY;
     }
-
-    /// Clone only the inbound values, for nested tool execution.
-    pub(crate) fn inbound_only(&self) -> Self {
-        self.for_dispatch()
-    }
 }
 
 impl std::fmt::Debug for ToolContext {
diff --git a/crates/rig-agent/src/tool/mod.rs b/crates/rig-agent/src/tool/mod.rs
--- a/crates/rig-agent/src/tool/mod.rs
+++ b/crates/rig-agent/src/tool/mod.rs
@@ -570,6 +570,16 @@ pub(crate) struct ToolDispatch {
     pub(crate) context: ToolContext,
 }
 
+impl ToolDispatch {
+    /// Publish the dispatch's result metadata back to the caller's context and
+    /// surface the result. Mutations to the tool's inbound snapshot are
+    /// discarded.
+    pub(crate) fn publish_to(self, context: &mut ToolContext) -> ToolResult {
+        context.accept_dispatch_result(self.context);
+        self.result
+    }
+}
+
 /// Execute a resolved registry entry through the single dispatch boundary.
 ///
 /// Every surface enters here with its caller-owned context. The helper clones
@@ -726,12 +736,8 @@ impl ToolSet {
     ) -> ToolResult {
         context.clear_dispatch_result();
         let tool = self.get(name).cloned();
-        let ToolDispatch {
-            result,
-            context: dispatch_context,
-        } = dispatch_tool(name, args.into(), tool, context).await;
-        context.accept_dispatch_result(dispatch_context);
-        result
+        let dispatch = dispatch_tool(name, args.into(), tool, context).await;
+        dispatch.publish_to(context)
     }
 
     /// Documents describing all registered tools.
diff --git a/crates/rig-agent/src/tool/server.rs b/crates/rig-agent/src/tool/server.rs
--- a/crates/rig-agent/src/tool/server.rs
+++ b/crates/rig-agent/src/tool/server.rs
@@ -427,12 +427,24 @@ impl ToolServerHandle {
         context: &mut ToolContext,
     ) -> ToolResult {
         context.clear_dispatch_result();
-        let ToolDispatch {
-            result,
-            context: dispatch_context,
-        } = self.dispatch(tool_name, args, context).await;
-        context.accept_dispatch_result(dispatch_context);
-        result
+        let dispatch = self.dispatch(tool_name, args, context).await;
+        dispatch.publish_to(context)
+    }
+
+    /// Run `f` against the registry state, first retiring disconnected MCP
+    /// tools (which needs a write lock) when that feature is compiled in.
+    async fn with_registry<R>(&self, f: impl FnOnce(&ToolServerState) -> R) -> R {
+        #[cfg(all(feature = "rmcp", not(target_family = "wasm")))]
+        {
+            let mut state = self.0.write().await;
+            state.retire_disconnected_tools();
+            f(&state)
+        }
+        #[cfg(not(all(feature = "rmcp", not(target_family = "wasm"))))]
+        {
+            let state = self.0.read().await;
+            f(&state)
+        }
     }
 
     /// Run one isolated dispatch and retain its full context for agent hooks.
@@ -442,17 +454,9 @@ impl ToolServerHandle {
         args: &str,
         context: &ToolContext,
     ) -> ToolDispatch {
-        #[cfg(all(feature = "rmcp", not(target_family = "wasm")))]
-        let tool = {
-            let mut state = self.0.write().await;
-            state.retire_disconnected_tools();
-            state.toolset.get(tool_name).cloned()
-        };
-        #[cfg(not(all(feature = "rmcp", not(target_family = "wasm"))))]
-        let tool = {
-            let state = self.0.read().await;
-            state.toolset.get(tool_name).cloned()
-        };
+        let tool = self
+            .with_registry(|state| state.toolset.get(tool_name).cloned())
+            .await;
         dispatch_tool(tool_name, args.to_string(), tool, context).await
     }
 
@@ -518,17 +522,9 @@ impl ToolServerHandle {
             Vec::new()
         };
 
-        #[cfg(all(feature = "rmcp", not(target_family = "wasm")))]
-        let tools = {
-            let mut state = self.0.write().await;
-            state.retire_disconnected_tools();
-            snapshot_registered_tools(&state, dynamic_tool_ids)
-        };
-        #[cfg(not(all(feature = "rmcp", not(target_family = "wasm"))))]
-        let tools = {
-            let state = self.0.read().await;
-            snapshot_registered_tools(&state, dynamic_tool_ids)
-        };
+        let tools = self
+            .with_registry(|state| snapshot_registered_tools(state, dynamic_tool_ids))
+            .await;
 
         Ok(ToolRegistrySnapshot::new(tools))
     }
@@ -539,38 +535,34 @@ fn snapshot_registered_tools(
     dynamic_tool_ids: Vec<String>,
 ) -> IndexMap<String, RegisteredTool> {
     let mut tools = IndexMap::new();
-
-    // Retrieved tools remain first, in index/result order. Duplicate IDs and
-    // dynamic/static overlap retain the first provider declaration.
-    for name in dynamic_tool_ids {
-        if tools.contains_key(&name) {
+    let insert = |tools: &mut IndexMap<String, RegisteredTool>, name: &str, warn_missing| {
+        if tools.contains_key(name) {
             tracing::debug!(
                 tool_name = %name,
                 "dropping duplicate tool definition from the request"
             );
-            continue;
+            return;
         }
-        match state.toolset.get(&name).cloned() {
+        match state.toolset.get(name).cloned() {
             Some(tool) => {
-                tools.insert(name, tool);
+                tools.insert(name.to_string(), tool);
             }
-            None => {
+            // A dynamic ID the model asked for but the toolset lacks is worth
+            // an operator warning; a retired always-exposed tool is not.
+            None if warn_missing => {
                 tracing::warn!("Tool implementation not found in toolset: {name}");
             }
+            None => {}
         }
-    }
+    };
 
+    // Retrieved tools remain first, in index/result order. Duplicate IDs and
+    // dynamic/static overlap retain the first provider declaration.
+    for name in &dynamic_tool_ids {
+        insert(&mut tools, name, true);
+    }
     for name in state.toolset.always_exposed_names() {
-        if tools.contains_key(name) {
-            tracing::debug!(
-                tool_name = %name,
-                "dropping duplicate tool definition from the request"
-            );
-            continue;
-        }
-        if let Some(tool) = state.toolset.get(name).cloned() {
-            tools.insert(name.clone(), tool);
-        }
+        insert(&mut tools, name, false);
     }
     tools
 }
diff --git a/crates/rig-core/src/client/mod.rs b/crates/rig-core/src/client/mod.rs
--- a/crates/rig-core/src/client/mod.rs
+++ b/crates/rig-core/src/client/mod.rs
@@ -615,16 +615,15 @@ impl<Ext, H> Client<Ext, H>
 where
     Ext: Provider,
 {
-    /// Build a provider-customized POST request for a regular HTTP endpoint.
-    pub fn post<S>(&self, path: S) -> http_client::Result<Builder>
-    where
-        S: AsRef<str>,
-    {
-        let uri = self
-            .ext
-            .build_uri(&self.base_url, path.as_ref(), Transport::Http);
+    fn request(
+        &self,
+        method: http::Method,
+        path: &str,
+        transport: Transport,
+    ) -> http_client::Result<Builder> {
+        let uri = self.ext.build_uri(&self.base_url, path, transport);
 
-        let mut req = Request::post(uri);
+        let mut req = Request::builder().method(method).uri(uri);
 
         if let Some(hs) = req.headers_mut() {
             hs.extend(self.headers.iter().map(|(k, v)| (k.clone(), v.clone())));
@@ -633,58 +632,36 @@ where
         self.ext.with_custom(req)
     }
 
+    /// Build a provider-customized POST request for a regular HTTP endpoint.
+    pub fn post<S>(&self, path: S) -> http_client::Result<Builder>
+    where
+        S: AsRef<str>,
+    {
+        self.request(http::Method::POST, path.as_ref(), Transport::Http)
+    }
+
     /// Build a provider-customized POST request for an SSE endpoint.
     pub fn post_sse<S>(&self, path: S) -> http_client::Result<Builder>
     where
         S: AsRef<str>,
     {
-        let uri = self
-            .ext
-            .build_uri(&self.base_url, path.as_ref(), Transport::Sse);
-
-        let mut req = Request::post(uri);
-
-        if let Some(hs) = req.headers_mut() {
-            hs.extend(self.headers.iter().map(|(k, v)| (k.clone(), v.clone())));
-        }
-
-        self.ext.with_custom(req)
+        self.request(http::Method::POST, path.as_ref(), Transport::Sse)
     }
 
     /// Build a provider-customized GET request for an SSE endpoint.
     pub fn get_sse<S>(&self, path: S) -> http_client::Result<Builder>
     where
         S: AsRef<str>,
     {
-        let uri = self
-            .ext
-            .build_uri(&self.base_url, path.as_ref(), Transport::Sse);
-
-        let mut req = Request::get(uri);
-
-        if let Some(hs) = req.headers_mut() {
-            hs.extend(self.headers.iter().map(|(k, v)| (k.clone(), v.clone())));
-        }
-
-        self.ext.with_custom(req)
+        self.request(http::Method::GET, path.as_ref(), Transport::Sse)
     }
 
     /// Build a provider-customized GET request for a regular HTTP endpoint.
     pub fn get<S>(&self, path: S) -> http_client::Result<Builder>
     where
         S: AsRef<str>,
     {
-        let uri = self
-            .ext
-            .build_uri(&self.base_url, path.as_ref(), Transport::Http);
-
-        let mut req = Request::get(uri);
-
-        if let Some(hs) = req.headers_mut() {
-            hs.extend(self.headers.iter().map(|(k, v)| (k.clone(), v.clone())));
-        }
-
-        self.ext.with_custom(req)
+        self.request(http::Method::GET, path.as_ref(), Transport::Http)
     }
 }
 
diff --git a/crates/rig-core/src/completion/message.rs b/crates/rig-core/src/completion/message.rs
--- a/crates/rig-core/src/completion/message.rs
+++ b/crates/rig-core/src/completion/message.rs
@@ -185,12 +185,6 @@ impl Reasoning {
         }
     }
 
-    /// Set or clear the provider reasoning ID.
-    pub fn optional_id(mut self, id: Option<String>) -> Self {
-        self.id = id;
-        self
-    }
-
     /// Set a provider reasoning ID.
     pub fn with_id(mut self, id: String) -> Self {
         self.id = Some(id);
@@ -605,31 +599,30 @@ pub struct ToolCall {
 }
 
 impl ToolCall {
-    /// A call with an explicit correlation handle and no provider-issued id.
-    pub fn new(id: ToolCallId, function: ToolFunction) -> Self {
+    fn assemble(provider: Option<ProviderCallId>, function: ToolFunction) -> Self {
         Self {
-            id,
-            provider: None,
+            id: ToolCallId::for_provider(provider.as_ref()),
+            provider,
             function,
             signature: None,
             additional_params: None,
         }
     }
 
-    /// The single-identifier provider boundary: adopt the wire's id when it
-    /// issued one, mint when it did not (empty or absent ids mint).
-    pub fn from_wire(wire_id: impl Into<String>, function: ToolFunction) -> Self {
-        let provider = ProviderCallId::new(wire_id);
-        let id = ToolCallId::for_provider(provider.as_ref());
+    /// A call with an explicit correlation handle and no provider-issued id.
+    pub fn new(id: ToolCallId, function: ToolFunction) -> Self {
         Self {
             id,
-            provider,
-            function,
-            signature: None,
-            additional_params: None,
+            ..Self::assemble(None, function)
         }
     }
 
+    /// The single-identifier provider boundary: adopt the wire's id when it
+    /// issued one, mint when it did not (empty or absent ids mint).
+    pub fn from_wire(wire_id: impl Into<String>, function: ToolFunction) -> Self {
+        Self::assemble(ProviderCallId::new(wire_id), function)
+    }
+
     /// The dual-identifier provider boundary (OpenAI Responses): `item_id`
     /// is the output-item handle (`fc_…`), `call_id` the correlator
     /// (`call_…`). The correlator drives rig's id; empty ids mint.
@@ -638,18 +631,9 @@ impl ToolCall {
         call_id: impl Into<String>,
         function: ToolFunction,
     ) -> Self {
-        let provider = ProviderCallId::new(call_id).map(|provider| {
-            let item_id = item_id.into();
-            provider.with_item_id(item_id)
-        });
-        let id = ToolCallId::for_provider(provider.as_ref());
-        Self {
-            id,
-            provider,
-            function,
-            signature: None,
-            additional_params: None,
-        }
+        let provider =
+            ProviderCallId::new(call_id).map(|provider| provider.with_item_id(item_id.into()));
+        Self::assemble(provider, function)
     }
 
     /// Attach provider-issued identifiers.
@@ -1075,30 +1059,6 @@ pub struct Image {
     pub additional_params: Option<AdditionalParams>,
 }
 
-impl Image {
-    pub fn try_into_url(self) -> Result<String, MessageError> {
-        match self.data {
-            DocumentSourceKind::Url(url) => Ok(url),
-            DocumentSourceKind::Base64(data) => {
-                let Some(media_type) = self.media_type else {
-                    return Err(MessageError::ConversionError(
-                        "A media type is required to create a valid base64-encoded image URL"
-                            .to_string(),
-                    ));
-                };
-
-                Ok(format!(
-                    "data:image/{ty};base64,{data}",
-                    ty = media_type.to_mime_type()
-                ))
-            }
-            unknown => Err(MessageError::ConversionError(format!(
-                "Tried to convert unknown type to a URL: {unknown:?}"
-            ))),
-        }
-    }
-}
-
 /// The kind of image source (to be used).
 #[derive(Debug, Deserialize, Serialize, Clone, PartialEq, Default)]
 #[serde(tag = "type", content = "value", rename_all = "camelCase")]
@@ -1135,21 +1095,11 @@ impl DocumentSourceKind {
         Self::FileId(file_id.to_string())
     }
 
-    /// Create a raw byte source.
-    pub fn raw(bytes: impl Into<Vec<u8>>) -> Self {
-        Self::Raw(bytes.into())
-    }
-
     /// Create a string-backed source.
     pub fn string(input: &str) -> Self {
         Self::String(input.into())
     }
 
-    /// Create an unknown source placeholder.
-    pub fn unknown() -> Self {
-        Self::Unknown
-    }
-
     /// Return the contained URL, base64 string, or file ID, if this source stores one.
     pub fn try_into_inner(self) -> Option<String> {
         match self {
@@ -1362,14 +1312,6 @@ impl Message {
         }
     }
 
-    /// Helper constructor to make creating assistant messages easier.
-    pub fn assistant_with_id(id: String, text: impl Into<String>) -> Self {
-        Message::Assistant {
-            id: Some(id),
-            content: vec![AssistantContent::text(text)],
-        }
-    }
-
     /// Helper constructor to make creating tool result messages easier.
     /// `call` is the answered call's correlation handle — echo
     /// [`ToolCall::id`]; it is never recorded as a provider-issued
@@ -1510,12 +1452,7 @@ impl UserContent {
     ) -> Self {
         let provider = ProviderCallId::new(wire_id);
         let call = ToolCallId::for_provider(provider.as_ref());
-        UserContent::ToolResult(ToolResult {
-            call,
-            provider,
-            name: name.into(),
-            content,
-        })
+        Self::tool_result_for(call, provider, name, content)
     }
 
     /// Tool result content answering a specific call — the form the agent
@@ -1547,12 +1484,7 @@ impl UserContent {
     ) -> Self {
         let provider = ProviderCallId::new(call_id).map(|provider| provider.with_item_id(item_id));
         let call = ToolCallId::for_provider(provider.as_ref());
-        UserContent::ToolResult(ToolResult {
-            call,
-            provider,
-            name: name.into(),
-            content,
-        })
+        Self::tool_result_for(call, provider, name, content)
     }
 }
 
diff --git a/crates/rig-core/src/completion/request.rs b/crates/rig-core/src/completion/request.rs
--- a/crates/rig-core/src/completion/request.rs
+++ b/crates/rig-core/src/completion/request.rs
@@ -528,17 +528,9 @@ impl Default for Usage {
 impl Add for Usage {
     type Output = Self;
 
-    fn add(self, other: Self) -> Self::Output {
-        Self {
-            input_tokens: self.input_tokens + other.input_tokens,
-            output_tokens: self.output_tokens + other.output_tokens,
-            total_tokens: self.total_tokens + other.total_tokens,
-            cached_input_tokens: self.cached_input_tokens + other.cached_input_tokens,
-            cache_creation_input_tokens: self.cache_creation_input_tokens
-                + other.cache_creation_input_tokens,
-            tool_use_prompt_tokens: self.tool_use_prompt_tokens + other.tool_use_prompt_tokens,
-            reasoning_tokens: self.reasoning_tokens + other.reasoning_tokens,
-        }
+    fn add(mut self, other: Self) -> Self::Output {
+        self += other;
+        self
     }
 }
 
@@ -872,28 +864,21 @@ impl CompletionRequest {
     pub(crate) fn chat_history_with_documents(&self) -> Vec<Message> {
         let mut chat_history = self.chat_history.clone();
         if let Some(documents) = self.normalized_documents() {
-            let insert_at = chat_history
-                .iter()
-                .position(|message| !matches!(message, Message::System { .. }))
-                .unwrap_or(chat_history.len());
-            chat_history.insert(insert_at, documents);
+            insert_after_leading_system(&mut chat_history, documents);
         }
         chat_history
     }
+}
 
-    /// Adds a provider-hosted tool by storing it in `additional_params.tools`.
-    pub fn with_provider_tool(mut self, tool: ProviderToolDefinition) -> Self {
-        self.additional_params =
-            merge_provider_tools_into_additional_params(self.additional_params, vec![tool]);
-        self
-    }
-
-    /// Adds provider-hosted tools by storing them in `additional_params.tools`.
-    pub fn with_provider_tools(mut self, tools: Vec<ProviderToolDefinition>) -> Self {
-        self.additional_params =
-            merge_provider_tools_into_additional_params(self.additional_params, tools);
-        self
-    }
+/// Insert `message` at the first non-system position so document context lands
+/// after any leading system messages; telemetry and the sent request must
+/// agree on this placement.
+fn insert_after_leading_system(chat_history: &mut Vec<Message>, message: Message) {
+    let insert_at = chat_history
+        .iter()
+        .position(|message| !matches!(message, Message::System { .. }))
+        .unwrap_or(chat_history.len());
+    chat_history.insert(insert_at, message);
 }
 
 fn merge_provider_tools_into_additional_params(
@@ -1203,11 +1188,7 @@ impl<M: CompletionModel> CompletionRequestBuilder<M> {
         chat_history.push(self.prompt.clone());
 
         if let Some(documents) = CompletionRequest::normalized_documents_from(&self.documents) {
-            let insert_at = chat_history
-                .iter()
-                .position(|message| !matches!(message, Message::System { .. }))
-                .unwrap_or(chat_history.len());
-            chat_history.insert(insert_at, documents);
+            insert_after_leading_system(&mut chat_history, documents);
         }
 
         chat_history
diff --git a/crates/rig-core/src/embeddings/embedding.rs b/crates/rig-core/src/embeddings/embedding.rs
--- a/crates/rig-core/src/embeddings/embedding.rs
+++ b/crates/rig-core/src/embeddings/embedding.rs
@@ -179,38 +179,6 @@ pub struct EmbeddingResponse {
     pub usage: Usage,
 }
 
-/// Trait for embedding models that can generate embeddings for images.
-pub trait ImageEmbeddingModel: Clone + WasmCompatSend + WasmCompatSync {
-    /// The maximum number of images that can be embedded in a single request.
-    const MAX_DOCUMENTS: usize;
-
-    /// The number of dimensions in the embedding vector.
-    fn ndims(&self) -> usize;
-
-    /// Embed multiple images in a single request from bytes.
-    ///
-    /// Implementations should preserve input order in the returned embeddings.
-    fn embed_images(
-        &self,
-        images: impl IntoIterator<Item = Vec<u8>> + WasmCompatSend,
-    ) -> impl std::future::Future<Output = Result<Vec<Embedding>, EmbeddingError>> + Send;
-
-    /// Embed a single image from bytes.
-    fn embed_image<'a>(
-        &'a self,
-        bytes: &'a [u8],
-    ) -> impl std::future::Future<Output = Result<Embedding, EmbeddingError>> + WasmCompatSend {
-        async move {
-            let mut embeddings = self.embed_images(vec![bytes.to_owned()]).await?;
-            embeddings.pop().ok_or_else(|| {
-                EmbeddingError::ResponseError(
-                    "embedding provider returned an empty response for embed_image".to_string(),
-                )
-            })
-        }
-    }
-}
-
 /// Struct that holds a single document and its embedding.
 #[derive(Clone, Default, Deserialize, Serialize, Debug)]
 pub struct Embedding {
diff --git a/crates/rig-core/src/loaders/pdf.rs b/crates/rig-core/src/loaders/pdf.rs
--- a/crates/rig-core/src/loaders/pdf.rs
+++ b/crates/rig-core/src/loaders/pdf.rs
@@ -160,6 +160,25 @@ impl<'a> PdfFileLoader<'a, Result<PathBuf, PdfLoaderError>> {
     }
 }
 
+/// Extract each page's text, paired with its zero-based page number.
+fn page_texts(doc: &Document) -> Vec<(usize, Result<String, PdfLoaderError>)> {
+    doc.page_iter()
+        .enumerate()
+        .map(|(page_no, _)| {
+            (
+                page_no,
+                doc.extract_text(&[page_no as u32 + 1])
+                    .map_err(PdfLoaderError::PdfError),
+            )
+        })
+        .collect()
+}
+
+/// Concatenate the text of every page, failing on the first unreadable page.
+fn all_text(doc: &Document) -> Result<String, PdfLoaderError> {
+    page_texts(doc).into_iter().map(|(_, text)| text).collect()
+}
+
 impl<'a> PdfFileLoader<'a, Result<PathBuf, PdfLoaderError>> {
     /// Directly reads the contents of the pdfs within the iterator returned by
     ///  [PdfFileLoader::with_glob] or [PdfFileLoader::with_dir].
@@ -182,19 +201,7 @@ impl<'a> PdfFileLoader<'a, Result<PathBuf, PdfLoaderError>> {
     /// ```
     pub fn read(self) -> PdfFileLoader<'a, Result<String, PdfLoaderError>> {
         PdfFileLoader {
-            iterator: Box::new(self.iterator.map(|res| {
-                let doc = res.load()?;
-                Ok(doc
-                    .page_iter()
-                    .enumerate()
-                    .map(|(page_no, _)| {
-                        doc.extract_text(&[page_no as u32 + 1])
-                            .map_err(PdfLoaderError::PdfError)
-                    })
-                    .collect::<Result<Vec<String>, PdfLoaderError>>()?
-                    .into_iter()
-                    .collect::<String>())
-            })),
+            iterator: Box::new(self.iterator.map(|res| all_text(&res.load()?))),
         }
     }
 
@@ -222,22 +229,7 @@ impl<'a> PdfFileLoader<'a, Result<PathBuf, PdfLoaderError>> {
         PdfFileLoader {
             iterator: Box::new(self.iterator.map(|res| {
                 let (path, doc) = res.load_with_path()?;
-                println!(
-                    "Loaded {:?} PDF: {:?}",
-                    path,
-                    doc.page_iter().collect::<Vec<_>>()
-                );
-                let content = doc
-                    .page_iter()
-                    .enumerate()
-                    .map(|(page_no, _)| {
-                        doc.extract_text(&[page_no as u32 + 1])
-                            .map_err(PdfLoaderError::PdfError)
-                    })
-                    .collect::<Result<Vec<String>, PdfLoaderError>>()?
-                    .into_iter()
-                    .collect::<String>();
-
+                let content = all_text(&doc)?;
                 Ok((path, content))
             })),
         }
@@ -270,12 +262,9 @@ impl<'a> PdfFileLoader<'a, Document> {
     pub fn by_page(self) -> PdfFileLoader<'a, Result<String, PdfLoaderError>> {
         PdfFileLoader {
             iterator: Box::new(self.iterator.flat_map(|doc| {
-                doc.page_iter()
-                    .enumerate()
-                    .map(|(page_no, _)| {
-                        doc.extract_text(&[page_no as u32 + 1])
-                            .map_err(PdfLoaderError::PdfError)
-                    })
+                page_texts(&doc)
+                    .into_iter()
+                    .map(|(_, text)| text)
                     .collect::<Vec<_>>()
             })),
         }
@@ -313,21 +302,7 @@ impl<'a> PdfFileLoader<'a, (PathBuf, Document)> {
     /// ```
     pub fn by_page(self) -> PdfFileLoader<'a, ByPage> {
         PdfFileLoader {
-            iterator: Box::new(self.iterator.map(|(path, doc)| {
-                (
-                    path,
-                    doc.page_iter()
-                        .enumerate()
-                        .map(|(page_no, _)| {
-                            (
-                                page_no,
-                                doc.extract_text(&[page_no as u32 + 1])
-                                    .map_err(PdfLoaderError::PdfError),
-                            )
-                        })
-                        .collect::<Vec<_>>(),
-                )
-            })),
+            iterator: Box::new(self.iterator.map(|(path, doc)| (path, page_texts(&doc)))),
         }
     }
 }
@@ -600,4 +575,30 @@ mod tests {
             ]
         );
     }
+
+    #[test]
+    fn test_pdf_loader_bytes_multi() {
+        let dummy = std::fs::read(fixture_path("dummy.pdf")).unwrap();
+        let pages = std::fs::read(fixture_path("pages.pdf")).unwrap();
+
+        let loader = PdfFileLoader::from_bytes_multi(vec![dummy, pages]);
+
+        let actual = loader
+            .load()
+            .ignore_errors()
+            .by_page()
+            .ignore_errors()
+            .into_iter()
+            .collect::<Vec<_>>();
+
+        assert_eq!(
+            actual,
+            vec![
+                "Test\nPDF\nDocument\n".to_string(),
+                "Page\n1\n".to_string(),
+                "Page\n2\n".to_string(),
+                "Page\n3\n".to_string(),
+            ]
+        );
+    }
 }
diff --git a/crates/rig-core/src/model/listing.rs b/crates/rig-core/src/model/listing.rs
--- a/crates/rig-core/src/model/listing.rs
+++ b/crates/rig-core/src/model/listing.rs
@@ -318,27 +318,6 @@ pub enum ModelListingError {
         /// Authentication error details
         message: String,
     },
-
-    /// Rate limit was exceeded
-    #[error("Rate limit error: {message}")]
-    RateLimitError {
-        /// Rate limit error details
-        message: String,
-    },
-
-    /// The provider service is temporarily unavailable
-    #[error("Service unavailable: {message}")]
-    ServiceUnavailable {
-        /// Unavailable error details
-        message: String,
-    },
-
-    /// An unexpected error occurred
-    #[error("Unknown error: {message}")]
-    UnknownError {
-        /// Details of the unknown error
-        message: String,
-    },
 }
 
 const RESPONSE_BODY_PREVIEW_LIMIT: usize = 2048;
@@ -425,34 +404,6 @@ impl ModelListingError {
         let message = format_response_context(provider, path, details, body);
         Self::parse_error(message)
     }
-
-    /// Creates a new AuthError with the given message.
-    pub fn auth_error(message: impl Into<String>) -> Self {
-        Self::AuthError {
-            message: message.into(),
-        }
-    }
-
-    /// Creates a new RateLimitError with the given message.
-    pub fn rate_limit_error(message: impl Into<String>) -> Self {
-        Self::RateLimitError {
-            message: message.into(),
-        }
-    }
-
-    /// Creates a new ServiceUnavailable error with the given message.
-    pub fn service_unavailable(message: impl Into<String>) -> Self {
-        Self::ServiceUnavailable {
-            message: message.into(),
-        }
-    }
-
-    /// Creates a new UnknownError with the given message.
-    pub fn unknown_error(message: impl Into<String>) -> Self {
-        Self::UnknownError {
-            message: message.into(),
-        }
-    }
 }
 
 impl From<crate::http_client::Error> for ModelListingError {
@@ -555,17 +506,10 @@ mod tests {
         let error = ModelListingError::parse_error("Invalid JSON");
         assert_eq!(error.to_string(), "Parse error: Invalid JSON");
 
-        let error = ModelListingError::auth_error("Invalid API key");
+        let error = ModelListingError::AuthError {
+            message: "Invalid API key".to_string(),
+        };
         assert_eq!(error.to_string(), "Authentication error: Invalid API key");
-
-        let error = ModelListingError::rate_limit_error("Too many requests");
-        assert_eq!(error.to_string(), "Rate limit error: Too many requests");
-
-        let error = ModelListingError::service_unavailable("Maintenance mode");
-        assert_eq!(error.to_string(), "Service unavailable: Maintenance mode");
-
-        let error = ModelListingError::unknown_error("Something went wrong");
-        assert_eq!(error.to_string(), "Unknown error: Something went wrong");
     }
 
     #[test]
diff --git a/crates/rig-core/src/providers/azure.rs b/crates/rig-core/src/providers/azure.rs
--- a/crates/rig-core/src/providers/azure.rs
+++ b/crates/rig-core/src/providers/azure.rs
@@ -31,7 +31,6 @@ use crate::{
     embeddings::{self, EmbeddingError},
     providers::openai,
 };
-use serde::Deserialize;
 // ================================================================
 // Main Azure OpenAI Client
 // ================================================================
@@ -320,56 +319,6 @@ fn model_dimensions_from_identifier(identifier: &str) -> Option<usize> {
     }
 }
 
-#[derive(Debug, Deserialize)]
-pub struct EmbeddingResponse {
-    pub object: String,
-    pub data: Vec<EmbeddingData>,
-    pub model: String,
-    pub usage: Usage,
-}
-
-#[derive(Debug, Deserialize)]
-pub struct EmbeddingData {
-    pub object: String,
-    pub embedding: Vec<f64>,
-    pub index: usize,
-}
-
-#[derive(Clone, Debug, Deserialize)]
-pub struct Usage {
-    pub prompt_tokens: usize,
-    pub total_tokens: usize,
-}
-
-impl From<&Usage> for crate::completion::Usage {
-    fn from(usage: &Usage) -> Self {
-        crate::providers::internal::completion_usage(
-            usage.prompt_tokens as u64,
-            // Azure's embeddings usage reports only prompt and total counts;
-            // the completion count is the remainder.
-            usage.total_tokens.saturating_sub(usage.prompt_tokens) as u64,
-            usage.total_tokens as u64,
-            0,
-        )
-    }
-}
-
-impl From<Usage> for crate::completion::Usage {
-    fn from(usage: Usage) -> Self {
-        Self::from(&usage)
-    }
-}
-
-impl std::fmt::Display for Usage {
-    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
-        write!(
-            f,
-            "Prompt tokens: {} Total tokens: {}",
-            self.prompt_tokens, self.total_tokens
-        )
-    }
-}
-
 #[derive(Clone)]
 pub struct EmbeddingModel<T = reqwest::Client> {
     /// The shared OpenAI-compatible embeddings driver, built once at
diff --git a/crates/rig-core/src/providers/chatgpt/mod.rs b/crates/rig-core/src/providers/chatgpt/mod.rs
--- a/crates/rig-core/src/providers/chatgpt/mod.rs
+++ b/crates/rig-core/src/providers/chatgpt/mod.rs
@@ -681,19 +681,7 @@ fn default_auth_file() -> Option<PathBuf> {
     config_dir().map(|dir| dir.join("chatgpt").join("auth.json"))
 }
 
-fn config_dir() -> Option<PathBuf> {
-    #[cfg(target_os = "windows")]
-    {
-        std::env::var_os("APPDATA").map(PathBuf::from)
-    }
-
-    #[cfg(not(target_os = "windows"))]
-    {
-        std::env::var_os("XDG_CONFIG_HOME")
-            .map(PathBuf::from)
-            .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
-    }
-}
+use crate::providers::internal::auth::config_dir;
 
 fn merge_instructions(default_instructions: &str, existing_instructions: Option<&str>) -> String {
     match existing_instructions
diff --git a/crates/rig-core/src/providers/copilot/mod.rs b/crates/rig-core/src/providers/copilot/mod.rs
--- a/crates/rig-core/src/providers/copilot/mod.rs
+++ b/crates/rig-core/src/providers/copilot/mod.rs
@@ -1357,26 +1357,13 @@ where
             )
         })?;
 
-        if !response.status().is_success() {
-            let status_code = response.status().as_u16();
-            let body = response.into_body().await?;
-            return Err(ModelListingError::api_error_with_context(
+        let api_resp: ListModelsResponse =
+            crate::providers::internal::model_listing::decode_json_response(
+                response,
                 MODEL_LISTING_PROVIDER,
                 MODEL_LISTING_PATH,
-                status_code,
-                &body,
-            ));
-        }
-
-        let body = response.into_body().await?;
-        let api_resp: ListModelsResponse = serde_json::from_slice(&body).map_err(|error| {
-            ModelListingError::parse_error_with_context(
-                MODEL_LISTING_PROVIDER,
-                MODEL_LISTING_PATH,
-                &error,
-                &body,
             )
-        })?;
+            .await?;
         let models = api_resp.data.into_iter().map(Model::from).collect();
 
         Ok(ModelList::new(models))
@@ -1411,19 +1398,7 @@ fn default_token_dir() -> Option<PathBuf> {
     config_dir().map(|dir| dir.join("github_copilot"))
 }
 
-fn config_dir() -> Option<PathBuf> {
-    #[cfg(target_os = "windows")]
-    {
-        std::env::var_os("APPDATA").map(PathBuf::from)
-    }
-
-    #[cfg(not(target_os = "windows"))]
-    {
-        std::env::var_os("XDG_CONFIG_HOME")
-            .map(PathBuf::from)
-            .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
-    }
-}
+use crate::providers::internal::auth::config_dir;
 
 #[cfg(test)]
 mod tests {
diff --git a/crates/rig-core/src/providers/deepseek.rs b/crates/rig-core/src/providers/deepseek.rs
--- a/crates/rig-core/src/providers/deepseek.rs
+++ b/crates/rig-core/src/providers/deepseek.rs
@@ -235,7 +235,9 @@ impl From<&Usage> for crate::completion::Usage {
                 .as_ref()
                 .and_then(|details| details.cached_tokens)
                 .map(u64::from)
-                .unwrap_or(0),
+                // DeepSeek's native usage reports cache hits outside the
+                // OpenAI-style details object.
+                .unwrap_or(u64::from(usage.prompt_cache_hit_tokens)),
         );
         normalized.reasoning_tokens = usage
             .completion_tokens_details
@@ -277,16 +279,6 @@ pub struct Choice {
 #[derive(Debug, Serialize, Deserialize, PartialEq, Clone)]
 #[serde(tag = "role", rename_all = "lowercase")]
 pub enum Message {
-    System {
-        content: String,
-        #[serde(skip_serializing_if = "Option::is_none")]
-        name: Option<String>,
-    },
-    User {
-        content: String,
-        #[serde(skip_serializing_if = "Option::is_none")]
-        name: Option<String>,
-    },
     Assistant {
         content: String,
         #[serde(skip_serializing_if = "Option::is_none")]
@@ -301,11 +293,6 @@ pub enum Message {
         #[serde(skip_serializing_if = "Option::is_none")]
         reasoning_content: Option<String>,
     },
-    #[serde(rename = "tool")]
-    ToolResult {
-        tool_call_id: String,
-        content: String,
-    },
 }
 
 #[derive(Debug, Serialize, Deserialize, PartialEq, Clone)]
@@ -349,32 +336,30 @@ impl crate::completion::NormalizeCompletionResponse for CompletionResponse {
             self.model.as_deref(),
             usage,
             |choice| choice.finish_reason.as_str(),
-            |choice| match &choice.message {
-                Message::Assistant {
+            |choice| {
+                let Message::Assistant {
                     content,
                     tool_calls,
                     reasoning_content,
                     ..
-                } => {
-                    let mut content = compat::text_then_tool_calls(
-                        content,
-                        content.trim().is_empty(),
-                        tool_calls.iter().map(|call| {
-                            (
-                                call.id.as_str(),
-                                call.function.name.as_str(),
-                                call.function.arguments.clone(),
-                            )
-                        }),
-                    );
-
-                    if let Some(reasoning_content) = reasoning_content {
-                        content.push(completion::AssistantContent::reasoning(reasoning_content));
-                    }
-
-                    Some(content)
+                } = &choice.message;
+                let mut content = compat::text_then_tool_calls(
+                    content,
+                    content.trim().is_empty(),
+                    tool_calls.iter().map(|call| {
+                        (
+                            call.id.as_str(),
+                            call.function.name.as_str(),
+                            call.function.arguments.clone(),
+                        )
+                    }),
+                );
+
+                if let Some(reasoning_content) = reasoning_content {
+                    content.push(completion::AssistantContent::reasoning(reasoning_content));
                 }
-                _ => None,
+
+                Some(content)
             },
         )
     }
@@ -477,7 +462,6 @@ mod tests {
         assert_eq!(choices.len(), 1);
         match &choices.first().unwrap().message {
             Message::Assistant { content, .. } => assert_eq!(content, "Hello, world!"),
-            _ => panic!("Expected assistant message"),
         }
     }
 
@@ -504,7 +488,6 @@ mod tests {
         match result {
             Ok(response) => match &response.choices.first().unwrap().message {
                 Message::Assistant { content, .. } => assert_eq!(content, "Hello, world!"),
-                _ => panic!("Expected assistant message"),
             },
             Err(err) => {
                 panic!("Deserialization error at {}: {}", err.path(), err);
@@ -798,7 +781,6 @@ mod tests {
                     content,
                     "Why don’t skeletons fight each other?  \nBecause they don’t have the guts! 😄"
                 ),
-                _ => panic!("Expected assistant message"),
             },
             Err(err) => {
                 panic!("Deserialization error at {}: {}", err.path(), err);
@@ -840,7 +822,6 @@ mod tests {
                 assert_eq!(call.function.name, "subtract");
                 assert_eq!(call.index, 0);
             }
-            _ => panic!("Expected assistant message"),
         }
 
         let serialized = serde_json::to_value(&choice).expect("choice should serialize");
diff --git a/crates/rig-core/src/providers/doubleword/client.rs b/crates/rig-core/src/providers/doubleword/client.rs
--- a/crates/rig-core/src/providers/doubleword/client.rs
+++ b/crates/rig-core/src/providers/doubleword/client.rs
@@ -51,37 +51,6 @@ client::impl_provider_client!(
     base_url_env_first = "DOUBLEWORD_BASE_URL",
 );
 
-pub mod doubleword_api_types {
-    use serde::Deserialize;
-
-    impl ApiErrorResponse {
-        pub fn message(&self) -> String {
-            self.error.message.clone()
-        }
-    }
-
-    #[derive(Debug, Deserialize)]
-    pub struct ApiErrorResponse {
-        pub error: ApiError,
-    }
-
-    #[derive(Debug, Deserialize)]
-    pub struct ApiError {
-        pub message: String,
-        #[serde(default)]
-        pub r#type: Option<String>,
-        #[serde(default)]
-        pub code: Option<String>,
-    }
-
-    #[derive(Debug, Deserialize)]
-    #[serde(untagged)]
-    pub enum ApiResponse<T> {
-        Ok(T),
-        Error(ApiErrorResponse),
-    }
-}
-
 #[cfg(test)]
 mod tests {
     #[test]
diff --git a/crates/rig-core/src/providers/gemini/interactions_api/mod.rs b/crates/rig-core/src/providers/gemini/interactions_api/mod.rs
--- a/crates/rig-core/src/providers/gemini/interactions_api/mod.rs
+++ b/crates/rig-core/src/providers/gemini/interactions_api/mod.rs
@@ -821,17 +821,141 @@ pub mod interactions_api_types {
         }
     }
 
-    /// Groups Google Search tool calls and results for a single interaction.
-    #[derive(Clone, Debug, Default)]
-    pub struct GoogleSearchExchange {
+    /// Groups tool calls and results of one built-in tool family for a single
+    /// interaction.
+    #[derive(Clone, Debug)]
+    pub struct Exchange<C, R> {
         /// Call identifier used to match calls to results.
         pub call_id: Option<String>,
-        /// One or more Google Search tool calls.
-        pub calls: Vec<GoogleSearchCallContent>,
-        /// One or more Google Search tool results.
-        pub results: Vec<GoogleSearchResultContent>,
+        /// One or more tool calls.
+        pub calls: Vec<C>,
+        /// One or more tool results.
+        pub results: Vec<R>,
+    }
+
+    impl<C, R> Default for Exchange<C, R> {
+        fn default() -> Self {
+            Self {
+                call_id: None,
+                calls: Vec::new(),
+                results: Vec::new(),
+            }
+        }
+    }
+
+    /// A tool call content type that carries an optional call identifier.
+    trait ExchangeCall {
+        fn id(&self) -> Option<&str>;
+    }
+
+    /// A tool result content type that carries an optional call identifier.
+    trait ExchangeResult {
+        fn call_id(&self) -> Option<&str>;
+    }
+
+    macro_rules! impl_exchange_ids {
+        ($call:ty, $result:ty) => {
+            impl ExchangeCall for $call {
+                fn id(&self) -> Option<&str> {
+                    self.id.as_deref()
+                }
+            }
+            impl ExchangeResult for $result {
+                fn call_id(&self) -> Option<&str> {
+                    self.call_id.as_deref()
+                }
+            }
+        };
+    }
+
+    impl_exchange_ids!(GoogleSearchCallContent, GoogleSearchResultContent);
+    impl_exchange_ids!(UrlContextCallContent, UrlContextResultContent);
+    impl_exchange_ids!(CodeExecutionCallContent, CodeExecutionResultContent);
+
+    /// Pairs tool calls with their results by call_id.
+    ///
+    /// When a call_id is missing, results are grouped with the most recent
+    /// call (identified or not) as a best-effort fallback.
+    fn pair_exchanges<C, R>(
+        contents: &[Content],
+        as_call: impl Fn(&Content) -> Option<&C>,
+        as_result: impl Fn(&Content) -> Option<&R>,
+    ) -> Vec<Exchange<C, R>>
+    where
+        C: Clone + ExchangeCall,
+        R: Clone + ExchangeResult,
+    {
+        let mut exchanges: Vec<Exchange<C, R>> = Vec::new();
+        let mut last_call_index: Option<usize> = None;
+        let position_of = |exchanges: &[Exchange<C, R>], call_id: &str| {
+            exchanges
+                .iter()
+                .position(|exchange| exchange.call_id.as_deref() == Some(call_id))
+        };
+
+        for content in contents {
+            if let Some(call) = as_call(content) {
+                let index = match call.id() {
+                    Some(call_id) => match position_of(&exchanges, call_id) {
+                        Some(index) => {
+                            if let Some(exchange) = exchanges.get_mut(index) {
+                                exchange.calls.push(call.clone());
+                            }
+                            index
+                        }
+                        None => {
+                            exchanges.push(Exchange {
+                                call_id: Some(call_id.to_string()),
+                                calls: vec![call.clone()],
+                                results: Vec::new(),
+                            });
+                            exchanges.len() - 1
+                        }
+                    },
+                    None => {
+                        exchanges.push(Exchange {
+                            call_id: None,
+                            calls: vec![call.clone()],
+                            results: Vec::new(),
+                        });
+                        exchanges.len() - 1
+                    }
+                };
+                last_call_index = Some(index);
+            } else if let Some(result) = as_result(content) {
+                if let Some(call_id) = result.call_id() {
+                    if let Some(index) = position_of(&exchanges, call_id) {
+                        if let Some(exchange) = exchanges.get_mut(index) {
+                            exchange.results.push(result.clone());
+                        }
+                    } else {
+                        exchanges.push(Exchange {
+                            call_id: Some(call_id.to_string()),
+                            calls: Vec::new(),
+                            results: vec![result.clone()],
+                        });
+                    }
+                } else if let Some(index) = last_call_index {
+                    if let Some(exchange) = exchanges.get_mut(index) {
+                        exchange.results.push(result.clone());
+                    }
+                } else {
+                    exchanges.push(Exchange {
+                        call_id: None,
+                        calls: Vec::new(),
+                        results: vec![result.clone()],
+                    });
+                    last_call_index = Some(exchanges.len() - 1);
+                }
+            }
+        }
+
+        exchanges
     }
 
+    /// Groups Google Search tool calls and results for a single interaction.
+    pub type GoogleSearchExchange = Exchange<GoogleSearchCallContent, GoogleSearchResultContent>;
+
     impl GoogleSearchExchange {
         /// Collects all queries from the stored Google Search tool calls.
         pub fn queries(&self) -> Vec<String> {
@@ -859,15 +983,7 @@ pub mod interactions_api_types {
     }
 
     /// Groups URL context tool calls and results for a single interaction.
-    #[derive(Clone, Debug, Default)]
-    pub struct UrlContextExchange {
-        /// Call identifier used to match calls to results.
-        pub call_id: Option<String>,
-        /// One or more URL context tool calls.
-        pub calls: Vec<UrlContextCallContent>,
-        /// One or more URL context tool results.
-        pub results: Vec<UrlContextResultContent>,
-    }
+    pub type UrlContextExchange = Exchange<UrlContextCallContent, UrlContextResultContent>;
 
     impl UrlContextExchange {
         /// Collects all URLs from the stored URL context tool calls.
@@ -896,15 +1012,7 @@ pub mod interactions_api_types {
     }
 
     /// Groups code execution tool calls and results for a single interaction.
-    #[derive(Clone, Debug, Default)]
-    pub struct CodeExecutionExchange {
-        /// Call identifier used to match calls to results.
-        pub call_id: Option<String>,
-        /// One or more code execution tool calls.
-        pub calls: Vec<CodeExecutionCallContent>,
-        /// One or more code execution tool results.
-        pub results: Vec<CodeExecutionResultContent>,
-    }
+    pub type CodeExecutionExchange = Exchange<CodeExecutionCallContent, CodeExecutionResultContent>;
 
     impl CodeExecutionExchange {
         /// Collects all code snippets from the stored code execution tool calls.
@@ -942,74 +1050,17 @@ pub mod interactions_api_types {
         /// When a call_id is missing, results are grouped with the most recent
         /// call (identified or not) as a best-effort fallback.
         pub fn google_search_exchanges(&self) -> Vec<GoogleSearchExchange> {
-            let mut exchanges: Vec<GoogleSearchExchange> = Vec::new();
-            let mut last_call_index: Option<usize> = None;
-            let output_contents = self.output_contents();
-
-            for content in &output_contents {
-                match content {
-                    Content::GoogleSearchCall(call) => {
-                        let index = if let Some(call_id) = call.id.as_ref() {
-                            if let Some(index) = exchanges
-                                .iter()
-                                .position(|exchange| exchange.call_id.as_deref() == Some(call_id))
-                            {
-                                if let Some(exchange) = exchanges.get_mut(index) {
-                                    exchange.calls.push(call.clone());
-                                }
-                                index
-                            } else {
-                                exchanges.push(GoogleSearchExchange {
-                                    call_id: Some(call_id.clone()),
-                                    calls: vec![call.clone()],
-                                    results: Vec::new(),
-                                });
-                                exchanges.len() - 1
-                            }
-                        } else {
-                            exchanges.push(GoogleSearchExchange {
-                                call_id: None,
-                                calls: vec![call.clone()],
-                                results: Vec::new(),
-                            });
-                            exchanges.len() - 1
-                        };
-                        last_call_index = Some(index);
-                    }
-                    Content::GoogleSearchResult(result) => {
-                        if let Some(call_id) = result.call_id.as_ref() {
-                            if let Some(index) = exchanges
-                                .iter()
-                                .position(|exchange| exchange.call_id.as_deref() == Some(call_id))
-                            {
-                                if let Some(exchange) = exchanges.get_mut(index) {
-                                    exchange.results.push(result.clone());
-                                }
-                            } else {
-                                exchanges.push(GoogleSearchExchange {
-                                    call_id: Some(call_id.clone()),
-                                    calls: Vec::new(),
-                                    results: vec![result.clone()],
-                                });
-                            }
-                        } else if let Some(index) = last_call_index {
-                            if let Some(exchange) = exchanges.get_mut(index) {
-                                exchange.results.push(result.clone());
-                            }
-                        } else {
-                            exchanges.push(GoogleSearchExchange {
-                                call_id: None,
-                                calls: Vec::new(),
-                                results: vec![result.clone()],
-                            });
-                            last_call_index = Some(exchanges.len() - 1);
-                        }
-                    }
-                    _ => {}
-                }
-            }
-
-            exchanges
+            pair_exchanges(
+                &self.output_contents(),
+                |content| match content {
+                    Content::GoogleSearchCall(call) => Some(call),
+                    _ => None,
+                },
+                |content| match content {
+                    Content::GoogleSearchResult(result) => Some(result),
+                    _ => None,
+                },
+            )
         }
 
         /// Collects Google Search tool call contents from the interaction outputs.
@@ -1049,74 +1100,17 @@ pub mod interactions_api_types {
         /// When a call_id is missing, results are grouped with the most recent
         /// call (identified or not) as a best-effort fallback.
         pub fn url_context_exchanges(&self) -> Vec<UrlContextExchange> {
-            let mut exchanges: Vec<UrlContextExchange> = Vec::new();
-            let mut last_call_index: Option<usize> = None;
-            let output_contents = self.output_contents();
-
-            for content in &output_contents {
-                match content {
-                    Content::UrlContextCall(call) => {
-                        let index = if let Some(call_id) = call.id.as_ref() {
-                            if let Some(index) = exchanges
-                                .iter()
-                                .position(|exchange| exchange.call_id.as_deref() == Some(call_id))
-                            {
-                                if let Some(exchange) = exchanges.get_mut(index) {
-                                    exchange.calls.push(call.clone());
-                                }
-                                index
-                            } else {
-                                exchanges.push(UrlContextExchange {
-                                    call_id: Some(call_id.clone()),
-                                    calls: vec![call.clone()],
-                                    results: Vec::new(),
-                                });
-                                exchanges.len() - 1
-                            }
-                        } else {
-                            exchanges.push(UrlContextExchange {
-                                call_id: None,
-                                calls: vec![call.clone()],
-                                results: Vec::new(),
-                            });
-                            exchanges.len() - 1
-                        };
-                        last_call_index = Some(index);
-                    }
-                    Content::UrlContextResult(result) => {
-                        if let Some(call_id) = result.call_id.as_ref() {
-                            if let Some(index) = exchanges
-                                .iter()
-                                .position(|exchange| exchange.call_id.as_deref() == Some(call_id))
-                            {
-                                if let Some(exchange) = exchanges.get_mut(index) {
-                                    exchange.results.push(result.clone());
-                                }
-                            } else {
-                                exchanges.push(UrlContextExchange {
-                                    call_id: Some(call_id.clone()),
-                                    calls: Vec::new(),
-                                    results: vec![result.clone()],
-                                });
-                            }
-                        } else if let Some(index) = last_call_index {
-                            if let Some(exchange) = exchanges.get_mut(index) {
-                                exchange.results.push(result.clone());
-                            }
-                        } else {
-                            exchanges.push(UrlContextExchange {
-                                call_id: None,
-                                calls: Vec::new(),
-                                results: vec![result.clone()],
-                            });
-                            last_call_index = Some(exchanges.len() - 1);
-                        }
-                    }
-                    _ => {}
-                }
-            }
-
-            exchanges
+            pair_exchanges(
+                &self.output_contents(),
+                |content| match content {
+                    Content::UrlContextCall(call) => Some(call),
+                    _ => None,
+                },
+                |content| match content {
+                    Content::UrlContextResult(result) => Some(result),
+                    _ => None,
+                },
+            )
         }
 
         /// Collects URL context tool call contents from the interaction outputs.
@@ -1156,74 +1150,17 @@ pub mod interactions_api_types {
         /// When a call_id is missing, results are grouped with the most recent
         /// call (identified or not) as a best-effort fallback.
         pub fn code_execution_exchanges(&self) -> Vec<CodeExecutionExchange> {
-            let mut exchanges: Vec<CodeExecutionExchange> = Vec::new();
-            let mut last_call_index: Option<usize> = None;
-            let output_contents = self.output_contents();
-
-            for content in &output_contents {
-                match content {
-                    Content::CodeExecutionCall(call) => {
-                        let index = if let Some(call_id) = call.id.as_ref() {
-                            if let Some(index) = exchanges
-                                .iter()
-                                .position(|exchange| exchange.call_id.as_deref() == Some(call_id))
-                            {
-                                if let Some(exchange) = exchanges.get_mut(index) {
-                                    exchange.calls.push(call.clone());
-                                }
-                                index
-                            } else {
-                                exchanges.push(CodeExecutionExchange {
-                                    call_id: Some(call_id.clone()),
-                                    calls: vec![call.clone()],
-                                    results: Vec::new(),
-                                });
-                                exchanges.len() - 1
-                            }
-                        } else {
-                            exchanges.push(CodeExecutionExchange {
-                                call_id: None,
-                                calls: vec![call.clone()],
-                                results: Vec::new(),
-                            });
-                            exchanges.len() - 1
-                        };
-                        last_call_index = Some(index);
-                    }
-                    Content::CodeExecutionResult(result) => {
-                        if let Some(call_id) = result.call_id.as_ref() {
-                            if let Some(index) = exchanges
-                                .iter()
-                                .position(|exchange| exchange.call_id.as_deref() == Some(call_id))
-                            {
-                                if let Some(exchange) = exchanges.get_mut(index) {
-                                    exchange.results.push(result.clone());
-                                }
-                            } else {
-                                exchanges.push(CodeExecutionExchange {
-                                    call_id: Some(call_id.clone()),
-                                    calls: Vec::new(),
-                                    results: vec![result.clone()],
-                                });
-                            }
-                        } else if let Some(index) = last_call_index {
-                            if let Some(exchange) = exchanges.get_mut(index) {
-                                exchange.results.push(result.clone());
-                            }
-                        } else {
-                            exchanges.push(CodeExecutionExchange {
-                                call_id: None,
-                                calls: Vec::new(),
-                                results: vec![result.clone()],
-                            });
-                            last_call_index = Some(exchanges.len() - 1);
-                        }
-                    }
-                    _ => {}
-                }
-            }
-
-            exchanges
+            pair_exchanges(
+                &self.output_contents(),
+                |content| match content {
+                    Content::CodeExecutionCall(call) => Some(call),
+                    _ => None,
+                },
+                |content| match content {
+                    Content::CodeExecutionResult(result) => Some(result),
+                    _ => None,
+                },
+            )
         }
 
         /// Collects code execution tool call contents from the interaction outputs.
diff --git a/crates/rig-core/src/providers/internal/auth.rs b/crates/rig-core/src/providers/internal/auth.rs
--- a/crates/rig-core/src/providers/internal/auth.rs
+++ b/crates/rig-core/src/providers/internal/auth.rs
@@ -12,3 +12,22 @@ pub enum AuthError {
     #[error(transparent)]
     Http(#[from] reqwest::Error),
 }
+
+/// Platform config directory used for on-disk OAuth/token caches
+/// (`APPDATA` on Windows; `XDG_CONFIG_HOME` falling back to `~/.config`
+/// elsewhere).
+pub(crate) fn config_dir() -> Option<std::path::PathBuf> {
+    use std::path::PathBuf;
+
+    #[cfg(target_os = "windows")]
+    {
+        std::env::var_os("APPDATA").map(PathBuf::from)
+    }
+
+    #[cfg(not(target_os = "windows"))]
+    {
+        std::env::var_os("XDG_CONFIG_HOME")
+            .map(PathBuf::from)
+            .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
+    }
+}
diff --git a/crates/rig-core/src/providers/internal/model_listing.rs b/crates/rig-core/src/providers/internal/model_listing.rs
--- a/crates/rig-core/src/providers/internal/model_listing.rs
+++ b/crates/rig-core/src/providers/internal/model_listing.rs
@@ -92,6 +92,21 @@ where
         .await
         .map_err(|error| map_transport_error(provider_name, path, error))?;
 
+    decode_json_response(response, provider_name, path).await
+}
+
+/// Triage a listing response's status and decode its JSON body, keeping the
+/// provider label, path, status, and body preview in every error. Shared with
+/// listings that build their own request (copilot's auth-derived base URL
+/// cannot go through [`get_json`]).
+pub(crate) async fn decode_json_response<T>(
+    response: http::Response<http_client::LazyBody<Vec<u8>>>,
+    provider_name: &str,
+    path: &str,
+) -> Result<T, ModelListingError>
+where
+    T: serde::de::DeserializeOwned,
+{
     if !response.status().is_success() {
         let status_code = response.status().as_u16();
         let body = response.into_body().await?;
diff --git a/crates/rig-core/src/providers/mira.rs b/crates/rig-core/src/providers/mira.rs
--- a/crates/rig-core/src/providers/mira.rs
+++ b/crates/rig-core/src/providers/mira.rs
@@ -8,12 +8,8 @@
 //!
 //! ```
 use crate::client::{self, BearerAuth, DebugExt, Provider};
+use crate::completion::{self, CompletionError};
 use crate::http_client::{self, HttpClientExt};
-use crate::providers::internal::openai_chat_completions_compatible::map_openai_finish_reason;
-use crate::{
-    completion::{self, CompletionError},
-    message::{self, AssistantContent, Message, UserContent},
-};
 use serde::{Deserialize, Serialize};
 use std::string::FromUtf8Error;
 use thiserror::Error;
@@ -126,29 +122,6 @@ pub struct RawMessage {
 
 const MIRA_API_BASE_URL: &str = "https://api.mira.network";
 
-impl TryFrom<RawMessage> for message::Message {
-    type Error = CompletionError;
-
-    fn try_from(raw: RawMessage) -> Result<Self, Self::Error> {
-        match raw.role.as_str() {
-            "system" => Ok(message::Message::System {
-                content: raw.content,
-            }),
-            "user" => Ok(message::Message::User {
-                content: vec![UserContent::Text(message::Text::new(raw.content))],
-            }),
-            "assistant" => Ok(message::Message::Assistant {
-                id: None,
-                content: vec![AssistantContent::Text(message::Text::new(raw.content))],
-            }),
-            _ => Err(CompletionError::ResponseError(format!(
-                "Unsupported message role: {}",
-                raw.role
-            ))),
-        }
-    }
-}
-
 #[derive(Debug, Deserialize, Serialize)]
 #[serde(untagged)]
 pub enum CompletionResponse {
@@ -298,104 +271,77 @@ impl From<Usage> for completion::Usage {
 /// descriptor that actually produced it.
 impl crate::completion::NormalizeCompletionResponse for CompletionResponse {
     fn normalize(self, provider: &str) -> Result<completion::CompletionResponse, CompletionError> {
-        let response = self;
-        let (content, usage, message_id, model, finish_reason) = match &response {
+        use crate::providers::internal::openai_chat_completions_compatible as compat;
+
+        let (id, model, choices, usage) = match self {
             CompletionResponse::Structured {
                 id,
                 model,
                 choices,
                 usage,
                 ..
-            } => {
-                let choice = choices.first().ok_or_else(|| {
-                    CompletionError::ResponseError("Response contained no choices".to_owned())
-                })?;
-
-                let usage = usage
-                    .as_ref()
-                    .map(completion::Usage::from)
-                    .unwrap_or_default();
-
-                let finish_reason = choice
-                    .finish_reason
-                    .as_deref()
-                    .filter(|reason| !reason.is_empty())
-                    .map(map_openai_finish_reason);
-
-                let message_id = Some(id.clone()).filter(|id| !id.is_empty());
-                let model = Some(model.clone()).filter(|model| !model.is_empty());
-
-                // Convert RawMessage to message::Message
-                let message = message::Message::try_from(choice.message.clone())?;
-
-                let content = match message {
-                    Message::Assistant { content, .. } => {
-                        // Unreachable today, and not for the reason it looks
-                        // like: `TryFrom<RawMessage>` builds the assistant arm
-                        // as `vec![one]` unconditionally, so this is never
-                        // empty even when the wire sent an empty string. It
-                        // was equally unreachable before message content became
-                        // a `Vec` — the container's `is_empty` returned a
-                        // hardcoded `false` — so the type change did not
-                        // revive it. Kept as a guard against a future
-                        // conversion that can produce nothing.
-                        if content.is_empty() {
-                            return Err(CompletionError::ResponseError(
-                                "Response contained empty content".to_owned(),
-                            ));
-                        }
-
-                        // Log warning for unsupported content types
-                        for c in content.iter() {
-                            if !matches!(c, AssistantContent::Text(_)) {
-                                tracing::warn!(target: "rig",
-                                    "Unsupported content type encountered: {:?}. The Mira provider currently only supports text content", c
-                                );
-                            }
-                        }
-
-                        content.iter().map(|c| {
-                            match c {
-                                AssistantContent::Text(text) => Ok(completion::AssistantContent::text(&text.text)),
-                                other => Err(CompletionError::ResponseError(
-                                    format!("Unsupported content type: {other:?}. The Mira provider currently only supports text content")
-                                ))
-                            }
-                        }).collect::<Result<Vec<_>, _>>()?
-                    }
-                    Message::User { .. } => {
-                        tracing::warn!(target: "rig", "Received user message in response where assistant message was expected");
-                        return Err(CompletionError::ResponseError(
-                            "Received user message in response where assistant message was expected".to_owned()
-                        ));
-                    }
-                    Message::System { .. } => {
-                        tracing::warn!(target: "rig", "Received system message in response where assistant message was expected");
-                        return Err(CompletionError::ResponseError(
-                            "Received system message in response where assistant message was expected".to_owned(),
-                        ));
-                    }
-                };
-
-                (content, usage, message_id, model, finish_reason)
-            }
+            } => (id, model, choices, usage),
             // The bare-string variant carries no metadata at all — not even a
             // terminal reason, so the normalized reason stays `None`.
-            CompletionResponse::Simple(text) => (
-                vec![completion::AssistantContent::text(text)],
-                completion::Usage::new(),
-                None,
-                None,
-                None,
-            ),
+            CompletionResponse::Simple(text) => {
+                let choice = crate::message::require_non_empty_response(vec![
+                    completion::AssistantContent::text(&text),
+                ])?;
+                return Ok(completion::CompletionResponse::new(
+                    choice,
+                    completion::Usage::new(),
+                    provider,
+                ));
+            }
         };
 
-        let choice = crate::message::require_non_empty_response(content)?;
+        // Preserve Mira's role-specific error messages: the shared helper
+        // folds every non-assistant message into one generic error. Mira's
+        // wire messages are plain `{role, content}` strings, so an assistant
+        // message can never carry unsupported content types.
+        if let Some(choice) = choices.first() {
+            match choice.message.role.as_str() {
+                "assistant" => {}
+                "user" => {
+                    tracing::warn!(target: "rig", "Received user message in response where assistant message was expected");
+                    return Err(CompletionError::ResponseError(
+                        "Received user message in response where assistant message was expected"
+                            .to_owned(),
+                    ));
+                }
+                "system" => {
+                    tracing::warn!(target: "rig", "Received system message in response where assistant message was expected");
+                    return Err(CompletionError::ResponseError(
+                        "Received system message in response where assistant message was expected"
+                            .to_owned(),
+                    ));
+                }
+                other => {
+                    return Err(CompletionError::ResponseError(format!(
+                        "Unsupported message role: {other}"
+                    )));
+                }
+            }
+        }
 
-        Ok(completion::CompletionResponse::new(choice, usage, provider)
-            .with_optional_response_id(message_id)
-            .with_optional_model(model)
-            .with_optional_finish_reason(finish_reason))
+        let usage = usage
+            .as_ref()
+            .map(completion::Usage::from)
+            .unwrap_or_default();
+
+        compat::normalize_openai_response(
+            provider,
+            &choices,
+            Some(id.as_str()).filter(|id| !id.is_empty()),
+            Some(model.as_str()).filter(|model| !model.is_empty()),
+            usage,
+            |choice| choice.finish_reason.as_deref().unwrap_or(""),
+            |choice| {
+                Some(vec![completion::AssistantContent::text(
+                    &choice.message.content,
+                )])
+            },
+        )
     }
 }
 
diff --git a/crates/rig-core/src/providers/ollama.rs b/crates/rig-core/src/providers/ollama.rs
--- a/crates/rig-core/src/providers/ollama.rs
+++ b/crates/rig-core/src/providers/ollama.rs
@@ -50,7 +50,7 @@ use crate::{
     completion::{self, CompletionError, CompletionRequest},
     embeddings::{self, EmbeddingError},
     json_utils, message,
-    message::{ImageDetail, Text},
+    message::Text,
     streaming,
     wasm_compat::{WasmCompatSend, WasmCompatSync},
 };
@@ -59,7 +59,7 @@ use bytes::Bytes;
 use futures::StreamExt;
 use serde::{Deserialize, Serialize};
 use serde_json::{Value, json};
-use std::{convert::TryFrom, str::FromStr};
+use std::convert::TryFrom;
 use tracing_futures::Instrument;
 // ---------- Main Client ----------
 
@@ -643,12 +643,12 @@ impl From<&StreamingCompletionResponse> for Usage {
     fn from(response: &StreamingCompletionResponse) -> Usage {
         let input_tokens = response.prompt_eval_count.unwrap_or_default();
         let output_tokens = response.eval_count.unwrap_or_default();
-
-        let mut usage = Usage::new();
-        usage.input_tokens = input_tokens;
-        usage.output_tokens = output_tokens;
-        usage.total_tokens = input_tokens + output_tokens;
-        usage
+        crate::providers::internal::completion_usage(
+            input_tokens,
+            output_tokens,
+            input_tokens + output_tokens,
+            0,
+        )
     }
 }
 
@@ -1044,25 +1044,12 @@ where
     }
 
     async fn list_all(&self) -> Result<ModelList, ModelListingError> {
-        let path = "/api/tags";
-        let req = self.client.get(path)?.body(http_client::NoBody)?;
-        let response = self.client.send::<_, Vec<u8>>(req).await?;
-
-        if !response.status().is_success() {
-            let status_code = response.status().as_u16();
-            let body = response.into_body().await?;
-            return Err(ModelListingError::api_error_with_context(
-                "Ollama",
-                path,
-                status_code,
-                &body,
-            ));
-        }
-
-        let body = response.into_body().await?;
-        let api_resp: ListModelsResponse = serde_json::from_slice(&body).map_err(|error| {
-            ModelListingError::parse_error_with_context("Ollama", path, &error, &body)
-        })?;
+        let api_resp: ListModelsResponse = crate::providers::internal::model_listing::get_json(
+            &self.client,
+            "Ollama",
+            "/api/tags",
+        )
+        .await?;
         let models = api_resp.models.into_iter().map(Model::from).collect();
 
         Ok(ModelList::new(models))
@@ -1427,43 +1414,6 @@ impl From<crate::message::ToolCall> for ToolCall {
     }
 }
 
-// Byte-for-byte the same wire shape as OpenAI's system content part; reuse it.
-pub use crate::providers::openai::completion::{SystemContent, SystemContentType};
-
-#[derive(Debug, Serialize, Deserialize, PartialEq, Clone)]
-pub struct AssistantContent {
-    pub text: String,
-}
-
-impl FromStr for AssistantContent {
-    type Err = std::convert::Infallible;
-    fn from_str(s: &str) -> Result<Self, Self::Err> {
-        Ok(AssistantContent { text: s.to_owned() })
-    }
-}
-
-#[derive(Debug, Serialize, Deserialize, PartialEq, Clone)]
-#[serde(tag = "type", rename_all = "lowercase")]
-pub enum UserContent {
-    Text { text: String },
-    Image { image_url: ImageUrl },
-    // Audio variant removed as Ollama API does not support audio input.
-}
-
-impl FromStr for UserContent {
-    type Err = std::convert::Infallible;
-    fn from_str(s: &str) -> Result<Self, Self::Err> {
-        Ok(UserContent::Text { text: s.to_owned() })
-    }
-}
-
-#[derive(Debug, Serialize, Deserialize, PartialEq, Clone)]
-pub struct ImageUrl {
-    pub url: String,
-    #[serde(default)]
-    pub detail: ImageDetail,
-}
-
 // =================================================================
 // Tests
 // =================================================================
diff --git a/crates/rig-core/src/providers/openai/responses_api/mod.rs b/crates/rig-core/src/providers/openai/responses_api/mod.rs
--- a/crates/rig-core/src/providers/openai/responses_api/mod.rs
+++ b/crates/rig-core/src/providers/openai/responses_api/mod.rs
@@ -21,8 +21,7 @@ use crate::http_client::HttpClientExt;
 use crate::json_utils;
 use crate::json_utils::string_or_vec;
 use crate::message::{
-    AudioMediaType, Document, DocumentMediaType, DocumentSourceKind, ImageDetail, MessageError,
-    MimeType, Text,
+    Document, DocumentMediaType, DocumentSourceKind, ImageDetail, MessageError, MimeType, Text,
 };
 use crate::telemetry::{CompletionOperation, CompletionSpanBuilder, SpanCombinator};
 
@@ -2241,13 +2240,6 @@ impl From<Output> for Vec<completion::AssistantContent> {
     }
 }
 
-#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
-pub struct OutputReasoning {
-    id: String,
-    summary: Vec<ReasoningSummary>,
-    status: ToolStatus,
-}
-
 /// An OpenAI Responses API tool call. A call ID will be returned that must be used when creating a tool result to send back to OpenAI as a message input, otherwise an error will be received.
 #[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
 pub struct OutputFunctionCall {
@@ -2908,233 +2900,6 @@ pub enum UserContent {
     },
 }
 
-fn flush_responses_user_content(messages: &mut Vec<Message>, pending: &mut Vec<UserContent>) {
-    // An empty flush is a legal no-op — it fires between consecutive
-    // tool-result groups — not a conversion error. This early return is
-    // the only emptiness decision here; the pushed content is non-empty
-    // because of it.
-    if pending.is_empty() {
-        return;
-    }
-
-    messages.push(Message::User {
-        content: std::mem::take(pending),
-        name: None,
-    });
-}
-
-fn responses_user_content(content: message::UserContent) -> Result<UserContent, MessageError> {
-    match content {
-        message::UserContent::Text(message::Text { text, .. }) => {
-            Ok(UserContent::InputText { text })
-        }
-        message::UserContent::Image(message::Image {
-            data,
-            detail,
-            media_type,
-            ..
-        }) => {
-            let url = match data {
-                DocumentSourceKind::Base64(data) => {
-                    let media_type = media_type
-                        .map(|media_type| media_type.to_mime_type().to_string())
-                        .unwrap_or_default();
-                    format!("data:{media_type};base64,{data}")
-                }
-                DocumentSourceKind::Url(url) => url,
-                DocumentSourceKind::Raw(_) => {
-                    return Err(MessageError::ConversionError(
-                        "Raw files not supported, encode as base64 first".into(),
-                    ));
-                }
-                doc => {
-                    return Err(MessageError::ConversionError(format!(
-                        "Unsupported document type: {doc}"
-                    )));
-                }
-            };
-
-            Ok(UserContent::InputImage {
-                image_url: url,
-                detail: detail.unwrap_or_default(),
-            })
-        }
-        message::UserContent::Document(message::Document {
-            data: DocumentSourceKind::FileId(file_id),
-            ..
-        }) => Ok(UserContent::InputFile {
-            file_id: Some(file_id),
-            file_url: None,
-            file_data: None,
-            filename: None,
-        }),
-        message::UserContent::Document(message::Document {
-            media_type: Some(DocumentMediaType::PDF),
-            data,
-            ..
-        }) => {
-            let (file_data, file_url, filename) = match data {
-                DocumentSourceKind::Base64(data) => (
-                    Some(format!("data:application/pdf;base64,{data}")),
-                    None,
-                    Some("document.pdf".to_string()),
-                ),
-                DocumentSourceKind::Url(url) => (None, Some(url), None),
-                DocumentSourceKind::Raw(_) => {
-                    return Err(MessageError::ConversionError(
-                        "Raw files not supported, encode as base64 first".into(),
-                    ));
-                }
-                doc => {
-                    return Err(MessageError::ConversionError(format!(
-                        "Unsupported document type: {doc}"
-                    )));
-                }
-            };
-
-            Ok(UserContent::InputFile {
-                file_id: None,
-                file_url,
-                file_data,
-                filename,
-            })
-        }
-        message::UserContent::Document(message::Document {
-            data: DocumentSourceKind::Base64(text),
-            ..
-        }) => Ok(UserContent::InputText { text }),
-        message::UserContent::Audio(message::Audio {
-            data: DocumentSourceKind::Base64(data),
-            media_type,
-            ..
-        }) => Ok(UserContent::Audio {
-            input_audio: InputAudio {
-                data,
-                format: media_type.unwrap_or(AudioMediaType::MP3),
-            },
-        }),
-        message::UserContent::Audio(_) => Err(MessageError::ConversionError(
-            "Audio must be base64 encoded data".into(),
-        )),
-        _ => Err(MessageError::ConversionError(
-            "Unsupported user content for OpenAI Responses API".into(),
-        )),
-    }
-}
-
-fn responses_tool_result(tool_result: message::ToolResult) -> Result<Message, MessageError> {
-    let tool_call_id = tool_result.wire_call_id().to_owned();
-    let output = responses_tool_result_output(tool_result.content)?;
-
-    Ok(Message::ToolResult {
-        tool_call_id,
-        output,
-    })
-}
-
-impl TryFrom<message::Message> for Vec<Message> {
-    type Error = message::MessageError;
-
-    fn try_from(message: message::Message) -> Result<Self, Self::Error> {
-        match message {
-            message::Message::System { content } => Ok(vec![Message::System {
-                content: vec![content.into()],
-                name: None,
-            }]),
-            message::Message::User { content } => {
-                let mut messages = Vec::new();
-                let mut pending = Vec::new();
-
-                for content in content {
-                    match content {
-                        message::UserContent::ToolResult(tool_result) => {
-                            flush_responses_user_content(&mut messages, &mut pending);
-                            messages.push(responses_tool_result(tool_result)?);
-                        }
-                        content => pending.push(responses_user_content(content)?),
-                    }
-                }
-
-                flush_responses_user_content(&mut messages, &mut pending);
-                Ok(messages)
-            }
-            message::Message::Assistant {
-                content,
-                id: assistant_message_id,
-            } => {
-                let mut messages = Vec::new();
-
-                for assistant_content in content {
-                    match assistant_content {
-                        crate::message::AssistantContent::Text(Text {
-                            text,
-                            additional_params,
-                        }) => {
-                            // The whole replay rule lives in
-                            // `assistant_text_replay_message`; `None` means
-                            // the block produces no wire item.
-                            if let Some(message) = assistant_text_replay_message(
-                                assistant_message_id.clone(),
-                                text,
-                                additional_params,
-                            ) {
-                                messages.push(message);
-                            }
-                        }
-                        crate::message::AssistantContent::ToolCall(crate::message::ToolCall {
-                            id,
-                            provider,
-                            function,
-                            ..
-                        }) => {
-                            let (call_id, item_id) = match provider {
-                                Some(provider) => {
-                                    let item_id = provider.item_id.clone().unwrap_or_default();
-                                    (provider.call_id, item_id)
-                                }
-                                None => (id.into_string(), String::new()),
-                            };
-                            messages.push(Message::Assistant {
-                                content: vec![AssistantContentType::ToolCall(OutputFunctionCall {
-                                    call_id,
-                                    arguments: function.arguments.into(),
-                                    id: item_id,
-                                    name: function.name,
-                                    status: ToolStatus::Completed,
-                                })],
-                                id: assistant_message_id.clone().unwrap_or_default(),
-                                name: None,
-                                status: ToolStatus::Completed,
-                            });
-                        }
-                        crate::message::AssistantContent::Reasoning(reasoning) => {
-                            if let Some(openai_reasoning) = openai_reasoning_from_core(&reasoning)?
-                            {
-                                messages.push(Message::Assistant {
-                                    content: vec![AssistantContentType::Reasoning(
-                                        openai_reasoning,
-                                    )],
-                                    id: assistant_message_id.clone().unwrap_or_default(),
-                                    name: None,
-                                    status: ToolStatus::Completed,
-                                });
-                            }
-                        }
-                        crate::message::AssistantContent::Image(_) => {
-                            return Err(MessageError::ConversionError(
-                                "Assistant image content is not supported in OpenAI Responses API"
-                                    .into(),
-                            ));
-                        }
-                    }
-                }
-
-                Ok(messages)
-            }
-        }
-    }
-}
-
 impl FromStr for UserContent {
     type Err = Infallible;
 
@@ -3324,16 +3089,25 @@ mod tests {
             ],
         };
 
-        let messages = Vec::<Message>::try_from(input).expect("message conversion");
+        let items = Vec::<InputItem>::try_from(input).expect("input item conversion");
 
         assert!(matches!(
-            messages.as_slice(),
+            items.as_slice(),
             [
-                Message::User { content: before, .. },
-                Message::ToolResult { tool_call_id, .. },
-                Message::User { content: after, .. },
+                InputItem {
+                    input: InputContent::Message(Message::User { content: before, .. }),
+                    ..
+                },
+                InputItem {
+                    input: InputContent::FunctionCallOutput(ToolResult { call_id, .. }),
+                    ..
+                },
+                InputItem {
+                    input: InputContent::Message(Message::User { content: after, .. }),
+                    ..
+                },
             ] if matches!(before.first(), Some(UserContent::InputText { text }) if text == "before")
-                && tool_call_id == "call-id"
+                && call_id == "call-id"
                 && matches!(after.first(), Some(UserContent::InputText { text }) if text == "after")
         ));
     }
@@ -3482,15 +3256,6 @@ mod tests {
         for (content, expected) in cases {
             let input = rig_tool_result(content);
 
-            let messages: Vec<Message> = input.clone().try_into().expect("message conversion");
-            assert!(matches!(
-                messages.as_slice(),
-                [Message::ToolResult {
-                    output: ToolResultOutput::Text(output),
-                    ..
-                }] if output == &expected
-            ));
-
             let items: Vec<InputItem> = input.try_into().expect("input item conversion");
             assert!(matches!(
                 items.as_slice(),
@@ -3531,15 +3296,6 @@ mod tests {
             },
         ]);
 
-        let messages: Vec<Message> = input.clone().try_into().expect("message conversion");
-
-        match messages.as_slice() {
-            [Message::ToolResult { output, .. }] => {
-                assert_eq!(output, &expected);
-            }
-            other => panic!("expected one tool result, got {other:?}"),
-        }
-
         let items: Vec<InputItem> = input.try_into().expect("input item conversion");
 
         match items.as_slice() {
@@ -3640,12 +3396,6 @@ mod tests {
             ));
         };
 
-        let messages: Vec<Message> = input.clone().try_into().expect("message conversion");
-        match messages.as_slice() {
-            [Message::ToolResult { output, .. }] => assert_output(output),
-            other => panic!("expected one rich tool result, got {other:?}"),
-        }
-
         let items: Vec<InputItem> = input.try_into().expect("input item conversion");
         match items.as_slice() {
             [
@@ -5044,21 +4794,6 @@ mod tests {
         assert_eq!(reasoning_count, 1);
     }
 
-    #[test]
-    fn idless_reasoning_is_skipped_when_converting_responses_history() {
-        let assistant = message::Message::Assistant {
-            id: Some("msg_123".to_string()),
-            content: vec![message::AssistantContent::Reasoning(
-                message::Reasoning::new("provider reasoning"),
-            )],
-        };
-
-        let converted = Vec::<Message>::try_from(assistant)
-            .expect("idless reasoning should degrade gracefully");
-
-        assert!(converted.is_empty());
-    }
-
     #[test]
     fn idless_reasoning_only_is_skipped_without_empty_input_item() {
         let assistant = completion::Message::Assistant {
@@ -5074,29 +4809,6 @@ mod tests {
         assert!(converted.is_empty());
     }
 
-    #[test]
-    fn idless_reasoning_plus_text_preserves_text_for_responses_history() {
-        let assistant = message::Message::Assistant {
-            id: Some("msg_123".to_string()),
-            content: vec![
-                message::AssistantContent::Reasoning(message::Reasoning::new("provider reasoning")),
-                message::AssistantContent::Text(Text::new("final answer")),
-            ],
-        };
-
-        let converted =
-            Vec::<Message>::try_from(assistant).expect("assistant history should convert");
-
-        assert_eq!(converted.len(), 1);
-        let Message::Assistant { content, .. } = &converted[0] else {
-            panic!("expected assistant message");
-        };
-        assert!(matches!(
-            content.first(),
-            Some(AssistantContentType::Text(AssistantContent::OutputText(OutputText { text, .. }))) if text == "final answer"
-        ));
-    }
-
     #[test]
     fn completion_history_idless_reasoning_plus_text_preserves_text_input_item() {
         let assistant = completion::Message::Assistant {
@@ -5168,55 +4880,6 @@ mod tests {
         assert!(serialized.get("status").is_none());
     }
 
-    #[test]
-    fn idless_message_assistant_text_replays_as_easy_input_message() {
-        let assistant = message::Message::Assistant {
-            id: None,
-            content: vec![message::AssistantContent::Text(Text::new("final answer"))],
-        };
-
-        let converted =
-            Vec::<Message>::try_from(assistant).expect("assistant history should convert");
-
-        assert_eq!(converted.len(), 1);
-        let Message::AssistantInput { content, .. } = &converted[0] else {
-            panic!("expected assistant input message");
-        };
-        assert_eq!(content, "final answer");
-
-        let serialized = serde_json::to_value(&converted[0])
-            .expect("assistant message should serialize to JSON");
-        assert_eq!(serialized["role"], json!("assistant"));
-        assert_eq!(serialized["content"], json!("final answer"));
-        assert!(serialized.get("id").is_none());
-        assert!(serialized.get("status").is_none());
-    }
-
-    #[test]
-    fn structured_reasoning_with_id_still_converts_for_responses_history() {
-        let assistant = message::Message::Assistant {
-            id: Some("msg_123".to_string()),
-            content: vec![message::AssistantContent::Reasoning(message::Reasoning {
-                id: Some("rs_123".to_string()),
-                content: vec![message::ReasoningContent::Summary(
-                    "structured summary".to_string(),
-                )],
-            })],
-        };
-
-        let converted =
-            Vec::<Message>::try_from(assistant).expect("structured reasoning should still convert");
-
-        assert_eq!(converted.len(), 1);
-        let Message::Assistant { content, .. } = &converted[0] else {
-            panic!("expected assistant message");
-        };
-        assert!(matches!(
-            content.first(),
-            Some(AssistantContentType::Reasoning(OpenAIReasoning { id, .. })) if id == "rs_123"
-        ));
-    }
-
     #[test]
     fn structured_reasoning_with_id_still_converts_to_input_item() {
         let assistant = completion::Message::Assistant {
@@ -5397,30 +5060,6 @@ mod tests {
         assert_eq!(token_usage.total_tokens, 38);
     }
 
-    #[test]
-    fn file_id_document_serializes_as_input_file_content() {
-        let message = message::Message::User {
-            content: vec![message::UserContent::Document(message::Document {
-                data: DocumentSourceKind::FileId("file_abc".to_string()),
-                media_type: None,
-                additional_params: None,
-            })],
-        };
-
-        let converted: Vec<Message> = message.try_into().expect("conversion should succeed");
-        let Message::User { content, .. } = &converted[0] else {
-            panic!("expected user message");
-        };
-
-        let json = serde_json::to_value(content.first().expect("first content"))
-            .expect("serialize content");
-
-        assert_eq!(json["type"], "input_file");
-        assert_eq!(json["file_id"], "file_abc");
-        assert!(json.get("file_data").is_none());
-        assert!(json.get("file_url").is_none());
-    }
-
     #[test]
     fn file_id_document_serializes_as_input_item_content() {
         let message = completion::Message::User {
@@ -5750,11 +5389,9 @@ mod tests {
 
     // Regression tests for issue #1429: `file_url` and `filename` are mutually
     // exclusive on OpenAI's Responses API (400 `mutually_exclusive_parameters`),
-    // so URL-backed PDFs must not carry the hardcoded `filename`. PR #1432
-    // fixed the `TryFrom<message::Message> for Vec<Message>` conversion; these
-    // tests also cover the `TryFrom<crate::completion::Message> for
-    // Vec<InputItem>` path that `CompletionModel::completion()` requests
-    // actually go through.
+    // so URL-backed PDFs must not carry the hardcoded `filename`. These tests
+    // cover the `TryFrom<crate::completion::Message> for Vec<InputItem>` path
+    // that `CompletionModel::completion()` requests actually go through.
     //
     // See <https://platform.openai.com/docs/guides/pdf-files> for the
     // `input_file` content part and its `file_url` / `file_data` / `file_id`
@@ -5846,14 +5483,6 @@ mod tests {
         assert_url_only_input_file(&sole_input_file(&json));
     }
 
-    #[test]
-    fn url_pdf_via_vec_message_path_omits_filename() {
-        let messages = Vec::<Message>::try_from(url_pdf_message())
-            .expect("URL PDF should convert to messages");
-        let json = serde_json::to_value(&messages).expect("messages should serialize");
-        assert_url_only_input_file(&sole_input_file(&json));
-    }
-
     #[test]
     fn base64_pdf_via_input_item_path_keeps_filename() {
         let input = message::Message::User {
diff --git a/crates/rig-core/src/providers/xiaomimimo.rs b/crates/rig-core/src/providers/xiaomimimo.rs
--- a/crates/rig-core/src/providers/xiaomimimo.rs
+++ b/crates/rig-core/src/providers/xiaomimimo.rs
@@ -23,11 +23,12 @@
 
 use crate::client::{self, BearerAuth, DebugExt, ModelLister, Provider};
 use crate::http_client::HttpClientExt;
-use crate::model::{Model, ModelList, ModelListingError};
+use crate::model::{ModelList, ModelListingError};
 use crate::providers::anthropic::client::{
     AnthropicBuilder as AnthropicCompatBuilder, AnthropicKey, impl_anthropic_compatible_builder,
 };
 use crate::providers::internal::anthropic_compatible::AnthropicBaseUrl;
+use crate::providers::internal::model_listing::ListModelEntry;
 use crate::wasm_compat::{WasmCompatSend, WasmCompatSync};
 
 /// OpenAI-compatible base URL.
@@ -143,20 +144,6 @@ const ANTHROPIC_BASE_URLS: AnthropicBaseUrl = AnthropicBaseUrl::new(
     "/anthropic/v1",
 );
 
-#[derive(Debug, serde::Deserialize)]
-struct ListModelEntry {
-    id: String,
-    owned_by: String,
-}
-
-impl From<ListModelEntry> for Model {
-    fn from(value: ListModelEntry) -> Self {
-        let mut model = Model::from_id(value.id);
-        model.owned_by = Some(value.owned_by);
-        model
-    }
-}
-
 /// [`ModelLister`] implementation for the Xiaomi MiMo API (`GET /models`).
 #[derive(Clone)]
 pub struct XiaomiMimoModelLister<H = reqwest::Client> {
diff --git a/crates/rig-core/src/streaming/mod.rs b/crates/rig-core/src/streaming/mod.rs
--- a/crates/rig-core/src/streaming/mod.rs
+++ b/crates/rig-core/src/streaming/mod.rs
@@ -738,12 +738,6 @@ impl RawStreamingToolCall {
         }
     }
 
-    /// Override the generated internal call ID.
-    pub fn with_internal_call_id(mut self, internal_call_id: String) -> Self {
-        self.internal_call_id = internal_call_id;
-        self
-    }
-
     /// Attach a provider-specific call ID.
     pub fn with_call_id(mut self, call_id: String) -> Self {
         self.call_id = Some(call_id);
diff --git a/crates/rig-core/src/streaming/parts.rs b/crates/rig-core/src/streaming/parts.rs
--- a/crates/rig-core/src/streaming/parts.rs
+++ b/crates/rig-core/src/streaming/parts.rs
@@ -348,15 +348,7 @@ impl PartsAccumulator {
                             ))
                     );
                     if part_already_signed {
-                        let index = self.push_reasoning_part(Reasoning {
-                            id: None,
-                            content: vec![ReasoningContent::Text {
-                                text: String::new(),
-                                signature: Some(signature),
-                            }],
-                        });
-                        self.finished_reasoning.insert(id.clone(), index);
-                        return self.reasoning_at(index);
+                        return self.finish_signature_only(id, signature);
                     }
                     attach_signature(self.parts.get_mut(index), signature);
                     return self.reasoning_at(index);
@@ -366,44 +358,51 @@ impl PartsAccumulator {
                 (None, None) => return None,
                 // A whole block under a finished key is a NEW sibling part
                 // reusing the key.
-                (Some(mut restatement), signature) => {
-                    if let Some(signature) = signature {
-                        attach_reasoning_signature(&mut restatement, signature);
-                    }
-                    let index = self.push_reasoning_part(restatement);
-                    self.finished_reasoning.insert(id.clone(), index);
-                    return self.reasoning_at(index);
+                (Some(restatement), signature) => {
+                    return self.finish_restated(id, restatement, signature);
                 }
             }
         }
 
         // Never-seen key: create the part whole from the end payload.
         match (restatement, signature) {
-            (Some(mut restatement), signature) => {
-                if let Some(signature) = signature {
-                    attach_reasoning_signature(&mut restatement, signature);
-                }
-                let index = self.push_reasoning_part(restatement);
-                self.finished_reasoning.insert(id.clone(), index);
-                self.reasoning_at(index)
-            }
-            (None, Some(signature)) => {
-                // Signature-only stream: replay-required provider state with
-                // nothing streamed to sign. Record it alone.
-                let index = self.push_reasoning_part(Reasoning {
-                    id: None,
-                    content: vec![ReasoningContent::Text {
-                        text: String::new(),
-                        signature: Some(signature),
-                    }],
-                });
-                self.finished_reasoning.insert(id.clone(), index);
-                self.reasoning_at(index)
-            }
+            (Some(restatement), signature) => self.finish_restated(id, restatement, signature),
+            // Signature-only stream: replay-required provider state with
+            // nothing streamed to sign. Record it alone.
+            (None, Some(signature)) => self.finish_signature_only(id, signature),
             (None, None) => None,
         }
     }
 
+    /// Record a whole reasoning block as a finished part under `id`.
+    fn finish_restated(
+        &mut self,
+        id: &StreamPartId,
+        mut restatement: Reasoning,
+        signature: Option<String>,
+    ) -> Option<Reasoning> {
+        if let Some(signature) = signature {
+            attach_reasoning_signature(&mut restatement, signature);
+        }
+        let index = self.push_reasoning_part(restatement);
+        self.finished_reasoning.insert(id.clone(), index);
+        self.reasoning_at(index)
+    }
+
+    /// Record a signature with no chain-of-thought as its own finished part
+    /// under `id`.
+    fn finish_signature_only(&mut self, id: &StreamPartId, signature: String) -> Option<Reasoning> {
+        let index = self.push_reasoning_part(Reasoning {
+            id: None,
+            content: vec![ReasoningContent::Text {
+                text: String::new(),
+                signature: Some(signature),
+            }],
+        });
+        self.finished_reasoning.insert(id.clone(), index);
+        self.reasoning_at(index)
+    }
+
     fn open_fresh_reasoning(
         &mut self,
         id: &StreamPartId,
diff --git a/crates/rig-core/src/tool/result.rs b/crates/rig-core/src/tool/result.rs
--- a/crates/rig-core/src/tool/result.rs
+++ b/crates/rig-core/src/tool/result.rs
@@ -66,6 +66,45 @@ kind_defaults! {
     Other => ("other", None, "the tool failed"),
 }
 
+// One `ToolExecutionError` constructor per kind, from a single table so a new
+// kind cannot miss its shorthand. `refused` stays hand-written because it also
+// sets the refusal disposition.
+macro_rules! kind_ctors {
+    ($($(#[$doc:meta])* $ctor:ident => $variant:ident),+ $(,)?) => {
+        impl ToolExecutionError {
+            $($(#[$doc])*
+            pub fn $ctor(message: impl Into<String>) -> Self {
+                Self::new(ToolErrorKind::$variant, message)
+            })+
+        }
+    };
+}
+
+kind_ctors! {
+    /// Invalid arguments.
+    invalid_args => InvalidArgs,
+    /// Timeout.
+    timeout => Timeout,
+    /// Cancellation.
+    cancelled => Cancelled,
+    /// Missing tool or resource.
+    not_found => NotFound,
+    /// An authorization or permission failure.
+    ///
+    /// This is an ordinary execution error. Use [`Self::refused`] when the tool
+    /// intentionally declines the operation so hooks and telemetry can preserve
+    /// the refusal as a distinct disposition.
+    permission_denied => PermissionDenied,
+    /// Rate limit.
+    rate_limited => RateLimited,
+    /// Upstream provider failure.
+    provider => Provider,
+    /// Network failure.
+    network => Network,
+    /// Catch-all failure.
+    other => Other,
+}
+
 impl std::fmt::Display for ToolErrorKind {
     fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
         f.write_str(self.as_str())
@@ -112,35 +151,6 @@ impl ToolExecutionError {
         }
     }
 
-    /// Invalid arguments.
-    pub fn invalid_args(message: impl Into<String>) -> Self {
-        Self::new(ToolErrorKind::InvalidArgs, message)
-    }
-
-    /// Timeout.
-    pub fn timeout(message: impl Into<String>) -> Self {
-        Self::new(ToolErrorKind::Timeout, message)
-    }
-
-    /// Cancellation.
-    pub fn cancelled(message: impl Into<String>) -> Self {
-        Self::new(ToolErrorKind::Cancelled, message)
-    }
-
-    /// Missing tool or resource.
-    pub fn not_found(message: impl Into<String>) -> Self {
-        Self::new(ToolErrorKind::NotFound, message)
-    }
-
-    /// An authorization or permission failure.
-    ///
-    /// This is an ordinary execution error. Use [`Self::refused`] when the tool
-    /// intentionally declines the operation so hooks and telemetry can preserve
-    /// the refusal as a distinct disposition.
-    pub fn permission_denied(message: impl Into<String>) -> Self {
-        Self::new(ToolErrorKind::PermissionDenied, message)
-    }
-
     /// An intentional, tool-authored refusal.
     ///
     /// Refusals use the normalized [`ToolErrorKind::PermissionDenied`] kind but
@@ -151,26 +161,6 @@ impl ToolExecutionError {
         error
     }
 
-    /// Rate limit.
-    pub fn rate_limited(message: impl Into<String>) -> Self {
-        Self::new(ToolErrorKind::RateLimited, message)
-    }
-
-    /// Upstream provider failure.
-    pub fn provider(message: impl Into<String>) -> Self {
-        Self::new(ToolErrorKind::Provider, message)
-    }
-
-    /// Network failure.
-    pub fn network(message: impl Into<String>) -> Self {
-        Self::new(ToolErrorKind::Network, message)
-    }
-
-    /// Catch-all failure.
-    pub fn other(message: impl Into<String>) -> Self {
-        Self::new(ToolErrorKind::Other, message)
-    }
-
     /// Build a safely presented `Other` error from a concrete source.
     ///
     /// The source's display string remains available as the operator-facing
diff --git a/crates/rig-core/src/vector_store/in_memory_store.rs b/crates/rig-core/src/vector_store/in_memory_store.rs
--- a/crates/rig-core/src/vector_store/in_memory_store.rs
+++ b/crates/rig-core/src/vector_store/in_memory_store.rs
@@ -368,18 +368,6 @@ impl<D: Serialize + Eq> InMemoryVectorStore<D> {
             self.insert_document(f(&doc), doc, embeddings);
         }
     }
-
-    /// Get the document by its id and deserialize it into the given type.
-    pub fn get_document<T: for<'a> Deserialize<'a>>(
-        &self,
-        id: &str,
-    ) -> Result<Option<T>, VectorStoreError> {
-        Ok(self
-            .embeddings
-            .get(id)
-            .map(|(doc, _)| serde_json::from_str(&serde_json::to_string(doc)?))
-            .transpose()?)
-    }
 }
 
 /// RankingItem(distance, document_id, serializable document, embeddings document)
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
