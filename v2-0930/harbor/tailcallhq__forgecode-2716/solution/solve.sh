#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/Cargo.lock b/Cargo.lock
--- a/Cargo.lock
+++ b/Cargo.lock
@@ -1948,17 +1948,20 @@ dependencies = [
 name = "forge_config"
 version = "0.1.0"
 dependencies = [
+ "anyhow",
  "config",
  "derive_setters",
  "dirs",
  "dotenvy",
  "fake",
+ "is_ci",
  "merge",
  "pretty_assertions",
  "schemars 1.2.1",
  "serde",
  "serde_json",
  "thiserror 2.0.18",
+ "tokio",
  "toml_edit",
  "tracing",
  "url",
diff --git a/crates/forge_api/src/api.rs b/crates/forge_api/src/api.rs
--- a/crates/forge_api/src/api.rs
+++ b/crates/forge_api/src/api.rs
@@ -1,4 +1,4 @@
-use std::path::{Path, PathBuf};
+use std::path::PathBuf;
 
 use anyhow::Result;
 use forge_app::dto::ToolsOverview;
@@ -53,19 +53,6 @@ pub trait API: Sync + Send {
     /// Adds a new conversation to the conversation store
     async fn upsert_conversation(&self, conversation: Conversation) -> Result<()>;
 
-    /// Initializes a workflow configuration from the given path
-    /// The workflow at the specified path is merged with the default
-    /// configuration If no path is provided, it will try to find forge.yaml
-    /// in the current directory or its parent directories
-    async fn read_workflow(&self, path: Option<&Path>) -> Result<Workflow>;
-
-    /// Reads the workflow from the given path and merges it with a default
-    /// workflow. This provides a convenient way to get a complete workflow
-    /// configuration without having to manually handle the merge logic.
-    /// If no path is provided, it will try to find forge.yaml in the current
-    /// directory or its parent directories
-    async fn read_merged(&self, path: Option<&Path>) -> Result<Workflow>;
-
     /// Returns the conversation with the given ID
     async fn conversation(&self, conversation_id: &ConversationId) -> Result<Option<Conversation>>;
 
diff --git a/crates/forge_api/src/forge_api.rs b/crates/forge_api/src/forge_api.rs
--- a/crates/forge_api/src/forge_api.rs
+++ b/crates/forge_api/src/forge_api.rs
@@ -1,4 +1,4 @@
-use std::path::{Path, PathBuf};
+use std::path::PathBuf;
 use std::sync::Arc;
 use std::time::Duration;
 
@@ -146,14 +146,6 @@ impl<A: Services, F: CommandInfra + EnvironmentInfra + SkillRepository + GrpcInf
         self.services.get_environment().clone()
     }
 
-    async fn read_workflow(&self, path: Option<&Path>) -> anyhow::Result<Workflow> {
-        self.app().read_workflow(path).await
-    }
-
-    async fn read_merged(&self, path: Option<&Path>) -> anyhow::Result<Workflow> {
-        self.app().read_workflow_merged(path).await
-    }
-
     async fn conversation(
         &self,
         conversation_id: &ConversationId,
diff --git a/crates/forge_app/src/app.rs b/crates/forge_app/src/app.rs
--- a/crates/forge_app/src/app.rs
+++ b/crates/forge_app/src/app.rs
@@ -1,4 +1,3 @@
-use std::path::{Path, PathBuf};
 use std::sync::Arc;
 
 use anyhow::Result;
@@ -12,17 +11,14 @@ use crate::dto::ToolsOverview;
 use crate::hooks::{CompactionHandler, DoomLoopDetector, TitleGenerationHandler, TracingHandler};
 use crate::init_conversation_metrics::InitConversationMetrics;
 use crate::orch::Orchestrator;
-use crate::services::{
-    AgentRegistry, CustomInstructionsService, ProviderAuthService, TemplateService,
-};
+use crate::services::{AgentRegistry, CustomInstructionsService, ProviderAuthService};
 use crate::set_conversation_id::SetConversationId;
 use crate::system_prompt::SystemPrompt;
 use crate::tool_registry::ToolRegistry;
 use crate::tool_resolver::ToolResolver;
 use crate::user_prompt::UserPromptGenerator;
 use crate::{
     AgentProviderResolver, ConversationService, FileDiscoveryService, ProviderService, Services,
-    WorkflowService,
 };
 
 /// ForgeApp handles the core chat functionality by orchestrating various
@@ -56,21 +52,11 @@ impl<S: Services> ForgeApp<S> {
             .expect("conversation for the request should've been created at this point.");
 
         // Discover files using the discovery service
-        let workflow = self.services.read_merged(None).await.unwrap_or_default();
+        let workflow = services.get_environment();
         let environment = services.get_environment();
 
         let files = services.list_current_directory().await?;
 
-        // Register templates using workflow path or environment fallback
-        let template_path = workflow
-            .templates
-            .as_ref()
-            .map_or(environment.templates(), |templates| {
-                PathBuf::from(templates)
-            });
-
-        services.register_template(template_path).await?;
-
         let custom_instructions = services.get_custom_instructions().await;
 
         // Prepare agents with user configuration
@@ -82,7 +68,7 @@ impl<S: Services> ForgeApp<S> {
             .get_agent(&agent_id)
             .await?
             .ok_or(crate::Error::AgentNotFound(agent_id.clone()))?
-            .apply_workflow_config(&workflow)
+            .apply_env(&workflow)
             .set_compact_model_if_none();
 
         let agent_provider = agent_provider_resolver
@@ -212,7 +198,7 @@ impl<S: Services> ForgeApp<S> {
         let original_messages = context.messages.len();
         let original_token_count = *context.token_count();
 
-        let workflow = self.services.read_merged(None).await.unwrap_or_default();
+        let workflow = self.services.get_environment();
 
         // Get agent and apply workflow config
         let agent = self.services.get_agent(&active_agent_id).await?;
@@ -228,7 +214,7 @@ impl<S: Services> ForgeApp<S> {
 
         // Get compact config from the agent
         let compact = agent
-            .apply_workflow_config(&workflow)
+            .apply_env(&workflow)
             .set_compact_model_if_none()
             .compact;
 
@@ -307,12 +293,4 @@ impl<S: Services> ForgeApp<S> {
 
         Ok(results)
     }
-
-    pub async fn read_workflow(&self, path: Option<&Path>) -> Result<Workflow> {
-        self.services.read_workflow(path).await
-    }
-
-    pub async fn read_workflow_merged(&self, path: Option<&Path>) -> Result<Workflow> {
-        self.services.read_merged(path).await
-    }
 }
diff --git a/crates/forge_app/src/orch_spec/orch_runner.rs b/crates/forge_app/src/orch_spec/orch_runner.rs
--- a/crates/forge_app/src/orch_spec/orch_runner.rs
+++ b/crates/forge_app/src/orch_spec/orch_runner.rs
@@ -91,9 +91,7 @@ impl Runner {
 
         let agent = setup.agent.clone();
         let system_tools = setup.tools.clone();
-        let agent = agent
-            .apply_workflow_config(&setup.workflow)
-            .model(setup.model.clone());
+        let agent = agent.apply_env(&setup.env).model(setup.model.clone());
 
         // Render system prompt into context.
         let conversation = SystemPrompt::new(services.clone(), setup.env.clone(), agent.clone())
diff --git a/crates/forge_app/src/orch_spec/orch_setup.rs b/crates/forge_app/src/orch_spec/orch_setup.rs
--- a/crates/forge_app/src/orch_spec/orch_setup.rs
+++ b/crates/forge_app/src/orch_spec/orch_setup.rs
@@ -6,7 +6,7 @@ use derive_setters::Setters;
 use forge_domain::{
     Agent, AgentId, Attachment, ChatCompletionMessage, ChatResponse, Conversation, Environment,
     Event, File, HttpConfig, MessageEntry, ModelId, ProviderId, RetryConfig, Role, Template,
-    ToolCallFull, ToolDefinition, ToolResult, Workflow,
+    ToolCallFull, ToolDefinition, ToolResult,
 };
 use url::Url;
 
@@ -25,7 +25,6 @@ pub struct TestContext {
     pub mock_tool_call_responses: Vec<(ToolCallFull, ToolResult)>,
     pub mock_assistant_responses: Vec<ChatCompletionMessage>,
     pub mock_shell_outputs: Vec<ShellOutput>,
-    pub workflow: Workflow,
     pub templates: HashMap<String, String>,
     pub files: Vec<File>,
     pub env: Environment,
@@ -49,7 +48,6 @@ impl Default for TestContext {
             mock_assistant_responses: Default::default(),
             mock_tool_call_responses: Default::default(),
             mock_shell_outputs: Default::default(),
-            workflow: Workflow::new().tool_supported(true),
             templates: Default::default(),
             files: Default::default(),
             attachments: Default::default(),
@@ -61,6 +59,7 @@ impl Default for TestContext {
                 shell: "bash".to_string(),
                 base_path: PathBuf::from("/Users/tushar/projects"),
                 service_url: Url::parse("http://localhost:8000").unwrap(),
+                tool_supported: true,
 
                 // No retry policy by default
                 retry_config: RetryConfig {
@@ -99,6 +98,14 @@ impl Default for TestContext {
                 commit: None,
                 suggest: None,
                 is_restricted: false,
+                temperature: None,
+                top_p: None,
+                top_k: None,
+                max_tokens: None,
+                max_tool_failure_per_turn: None,
+                max_requests_per_turn: None,
+                compact: None,
+                updates: None,
             },
             title: Some("test-conversation".into()),
             agent: Agent::new(
diff --git a/crates/forge_app/src/orch_spec/orch_system_spec.rs b/crates/forge_app/src/orch_spec/orch_system_spec.rs
--- a/crates/forge_app/src/orch_spec/orch_system_spec.rs
+++ b/crates/forge_app/src/orch_spec/orch_system_spec.rs
@@ -1,17 +1,14 @@
-use forge_domain::{ChatCompletionMessage, CommandOutput, Content, FinishReason, Workflow};
+use forge_domain::{ChatCompletionMessage, CommandOutput, Content, FinishReason};
 use insta::assert_snapshot;
 
 use crate::ShellOutput;
 use crate::orch_spec::orch_runner::TestContext;
 
 #[tokio::test]
 async fn test_system_prompt() {
-    let mut ctx = TestContext::default()
-        .workflow(Workflow::default().tool_supported(false))
-        .mock_assistant_responses(vec![
-            ChatCompletionMessage::assistant(Content::full("Sure"))
-                .finish_reason(FinishReason::Stop),
-        ]);
+    let mut ctx = TestContext::default().mock_assistant_responses(vec![
+        ChatCompletionMessage::assistant(Content::full("Sure")).finish_reason(FinishReason::Stop),
+    ]);
 
     ctx.run("This is a test").await.unwrap();
     let system_messages = ctx.output.system_messages().unwrap().join("\n\n");
@@ -21,11 +18,6 @@ async fn test_system_prompt() {
 #[tokio::test]
 async fn test_system_prompt_tool_supported() {
     let mut ctx = TestContext::default()
-        .workflow(
-            Workflow::default()
-                .tool_supported(true)
-                .custom_rules("Do it nicely"),
-        )
         .files(vec![
             forge_domain::File { path: "/users/john/foo.txt".to_string(), is_dir: false },
             forge_domain::File { path: "/users/jason/bar.txt".to_string(), is_dir: false },
@@ -55,7 +47,6 @@ async fn test_system_prompt_with_extensions() {
     };
 
     let mut ctx = TestContext::default()
-        .workflow(Workflow::default().tool_supported(true))
         .mock_shell_outputs(vec![shell_output])
         .mock_assistant_responses(vec![
             ChatCompletionMessage::assistant(Content::full("Sure"))
@@ -92,7 +83,6 @@ async fn test_system_prompt_with_extensions_truncated() {
     };
 
     let mut ctx = TestContext::default()
-        .workflow(Workflow::default().tool_supported(true))
         .mock_shell_outputs(vec![shell_output])
         .mock_assistant_responses(vec![
             ChatCompletionMessage::assistant(Content::full("Sure"))
diff --git a/crates/forge_app/src/orch_spec/snapshots/forge_app__orch_spec__orch_system_spec__system_prompt.snap b/crates/forge_app/src/orch_spec/snapshots/forge_app__orch_spec__orch_system_spec__system_prompt.snap
--- a/crates/forge_app/src/orch_spec/snapshots/forge_app__orch_spec__orch_system_spec__system_prompt.snap
+++ b/crates/forge_app/src/orch_spec/snapshots/forge_app__orch_spec__orch_system_spec__system_prompt.snap
@@ -11,44 +11,9 @@ You are Forge
 <home_directory>/Users/tushar</home_directory>
 </system_information>
 
-<available_tools>
-<tool>{"name":"fs_read","description":"","arguments":{}}</tool>
-<tool>{"name":"fs_write","description":"","arguments":{}}</tool>
-</available_tools>
-
-<tool_usage_example>
-1. You can only make one tool call per message.
-2. Each tool call must be wrapped in `<forge_tool_call>` tags.
-3. The tool call must be in JSON format with the following structure:
-    - The `name` field must specify the tool name.
-    - The `arguments` field must contain the required parameters for the tool.
-
-Here's a correct example structure:
-
-Example 1:
-<forge_tool_call>
-{"name": "read", "arguments": {"path": "/a/b/c.txt"}}
-</forge_tool_call>
-
-Example 2:
-<forge_tool_call>
-{"name": "write", "arguments": {"path": "/a/b/c.txt", "content": "Hello World!"}}
-</forge_tool_call>
-
-Important:
-1. ALWAYS use JSON format inside `forge_tool_call` tags.
-2. Specify the name of tool in the `name` field.
-3. Specify the tool arguments in the `arguments` field.
-4. If you need to make multiple tool calls, send them in separate messages.
-
-Before using a tool, ensure all required arguments are available. 
-If any required arguments are missing, do not attempt to use the tool.
-</tool_usage_example>
 
 <tool_usage_instructions>
-- You have access to set of tools as described in the <available_tools> tag.
-- You can use one tool per message, and will receive the result of that tool use in the user's response.
-- You use tools step-by-step to accomplish a given task, with each tool use informed by the result of the previous tool use.
+- For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools (for eg: `patch`, `read`) simultaneously rather than sequentially.
 - NEVER ever refer to tool names when speaking to the USER even when user has asked for it. For example, instead of saying 'I need to use the edit_file tool to edit your file', just say 'I will edit your file'.
 - If you need to read a file, prefer to read larger sections of the file at once over multiple smaller calls.
 </tool_usage_instructions>
diff --git a/crates/forge_app/src/orch_spec/snapshots/forge_app__orch_spec__orch_system_spec__system_prompt_tool_supported.snap b/crates/forge_app/src/orch_spec/snapshots/forge_app__orch_spec__orch_system_spec__system_prompt_tool_supported.snap
--- a/crates/forge_app/src/orch_spec/snapshots/forge_app__orch_spec__orch_system_spec__system_prompt_tool_supported.snap
+++ b/crates/forge_app/src/orch_spec/snapshots/forge_app__orch_spec__orch_system_spec__system_prompt_tool_supported.snap
@@ -22,9 +22,6 @@ You are Forge
 - If you need to read a file, prefer to read larger sections of the file at once over multiple smaller calls.
 </tool_usage_instructions>
 
-<project_guidelines>
-Do it nicely
-</project_guidelines>
 
 <non_negotiable_rules>
 - ALWAYS present the result of your work in a neatly structured format (using markdown syntax in your response) to the user at the end of every task.
@@ -51,5 +48,5 @@ Do it nicely
 
 - User may tag files using the format @[<file name>] and send it as a part of the message. Do not attempt to reread those files.
 - Only use emojis if the user explicitly requests it. Avoid using emojis in all communication unless asked.
-- Always follow all the `project_guidelines` without exception.
+
 </non_negotiable_rules>
diff --git a/crates/forge_app/src/services.rs b/crates/forge_app/src/services.rs
--- a/crates/forge_app/src/services.rs
+++ b/crates/forge_app/src/services.rs
@@ -8,9 +8,8 @@ use forge_domain::{
     ChatCompletionMessage, CommandOutput, Context, Conversation, ConversationId, File, FileInfo,
     FileStatus, Image, McpConfig, McpServers, Model, ModelId, Node, Provider, ProviderId,
     ResultStream, Scope, SearchParams, SyncProgress, SyntaxError, Template, ToolCallFull,
-    ToolOutput, Workflow, WorkspaceAuth, WorkspaceId, WorkspaceInfo,
+    ToolOutput, WorkspaceAuth, WorkspaceId, WorkspaceInfo,
 };
-use merge::Merge;
 use reqwest::Response;
 use reqwest::header::HeaderMap;
 use reqwest_eventsource::EventSource;
@@ -337,28 +336,6 @@ pub trait WorkspaceService: Send + Sync {
     async fn init_workspace(&self, path: PathBuf) -> anyhow::Result<WorkspaceId>;
 }
 
-#[async_trait::async_trait]
-pub trait WorkflowService {
-    /// Find a forge.yaml config file by traversing parent directories.
-    /// Returns the path to the first found config file, or the original path if
-    /// none is found.
-    async fn resolve(&self, path: Option<std::path::PathBuf>) -> std::path::PathBuf;
-
-    /// Reads the workflow from the given path.
-    /// If no path is provided, it will try to find forge.yaml in the current
-    /// directory or its parent directories.
-    async fn read_workflow(&self, path: Option<&Path>) -> anyhow::Result<Workflow>;
-
-    /// Reads the workflow from the given path and merges it with an default
-    /// workflow.
-    async fn read_merged(&self, path: Option<&Path>) -> anyhow::Result<Workflow> {
-        let workflow = self.read_workflow(path).await?;
-        let mut base_workflow = Workflow::default();
-        base_workflow.merge(workflow);
-        Ok(base_workflow)
-    }
-}
-
 #[async_trait::async_trait]
 pub trait FileDiscoveryService: Send + Sync {
     async fn collect_files(&self, config: Walker) -> anyhow::Result<Vec<File>>;
@@ -572,7 +549,6 @@ pub trait Services: Send + Sync + 'static + Clone + EnvironmentInfra {
     type TemplateService: TemplateService;
     type AttachmentService: AttachmentService;
     type CustomInstructionsService: CustomInstructionsService;
-    type WorkflowService: WorkflowService + Sync;
     type FileDiscoveryService: FileDiscoveryService;
     type McpConfigManager: McpConfigManager;
     type FsWriteService: FsWriteService;
@@ -600,7 +576,6 @@ pub trait Services: Send + Sync + 'static + Clone + EnvironmentInfra {
     fn conversation_service(&self) -> &Self::ConversationService;
     fn template_service(&self) -> &Self::TemplateService;
     fn attachment_service(&self) -> &Self::AttachmentService;
-    fn workflow_service(&self) -> &Self::WorkflowService;
     fn file_discovery_service(&self) -> &Self::FileDiscoveryService;
     fn mcp_config_manager(&self) -> &Self::McpConfigManager;
     fn fs_create_service(&self) -> &Self::FsWriteService;
@@ -757,17 +732,6 @@ impl<I: Services> AttachmentService for I {
     }
 }
 
-#[async_trait::async_trait]
-impl<I: Services> WorkflowService for I {
-    async fn resolve(&self, path: Option<std::path::PathBuf>) -> std::path::PathBuf {
-        self.workflow_service().resolve(path).await
-    }
-
-    async fn read_workflow(&self, path: Option<&Path>) -> anyhow::Result<Workflow> {
-        self.workflow_service().read_workflow(path).await
-    }
-}
-
 #[async_trait::async_trait]
 impl<I: Services> FileDiscoveryService for I {
     async fn collect_files(&self, config: Walker) -> anyhow::Result<Vec<File>> {
diff --git a/crates/forge_config/.forge.toml b/crates/forge_config/.forge.toml
--- a/crates/forge_config/.forge.toml
+++ b/crates/forge_config/.forge.toml
@@ -1,59 +1,61 @@
-max_search_lines = 1000
-max_search_result_bytes = 10240
+auto_open_dump = false
+max_conversations = 100
+max_extensions = 15
 max_fetch_chars = 50000
-max_stdout_prefix_lines = 100
-max_stdout_suffix_lines = 100
-max_stdout_line_chars = 500
-max_line_chars = 2000
-max_read_lines = 2000
 max_file_read_batch_size = 50
 max_file_size_bytes = 104857600
 max_image_size_bytes = 262144
-tool_timeout_secs = 300
-auto_open_dump = false
-max_conversations = 100
-max_sem_search_results = 100
-sem_search_top_k = 10
-services_url = "https://api.forgecode.dev/"
-max_extensions = 15
+max_line_chars = 2000
 max_parallel_file_reads = 64
-model_cache_ttl_secs = 604800
+max_read_lines = 2000
 max_requests_per_turn = 100
+max_search_lines = 1000
+max_search_result_bytes = 10240
+max_sem_search_results = 100
+max_stdout_line_chars = 500
+max_stdout_prefix_lines = 100
+max_stdout_suffix_lines = 100
+max_tokens = 20480
 max_tool_failure_per_turn = 3
-top_p = 0.8
+model_cache_ttl_secs = 604800
+restricted = false
+sem_search_top_k = 10
+services_url = "https://api.forgecode.dev/"
+tool_supported = true
+tool_timeout_secs = 300
 top_k = 30
-max_tokens = 20480
+top_p = 0.8
 
 [retry]
-initial_backoff_ms = 200
-min_delay_ms = 1000
 backoff_factor = 2
+initial_backoff_ms = 200
 max_attempts = 8
+min_delay_ms = 1000
 status_codes = [429, 500, 502, 503, 504, 408, 522, 520, 529]
 suppress_errors = false
 
 [http]
+accept_invalid_certs = false
+adaptive_window = true
 connect_timeout_secs = 30
-read_timeout_secs = 900
-pool_idle_timeout_secs = 90
-pool_max_idle_per_host = 5
-max_redirects = 10
 hickory = false
-tls_backend = "default"
-adaptive_window = true
 keep_alive_interval_secs = 60
 keep_alive_timeout_secs = 10
 keep_alive_while_idle = true
-accept_invalid_certs = false
+max_redirects = 10
+pool_idle_timeout_secs = 90
+pool_max_idle_per_host = 5
+read_timeout_secs = 900
+tls_backend = "default"
 
 [compact]
+eviction_window = 0.2
 max_tokens = 2000
-token_threshold = 100000
-retention_window = 6
 message_threshold = 200
-eviction_window = 0.2
 on_turn_end = false
+retention_window = 6
+token_threshold = 100000
 
 [updates]
-frequency = "daily"
 auto_update = true
+frequency = "daily"
diff --git a/crates/forge_config/Cargo.toml b/crates/forge_config/Cargo.toml
--- a/crates/forge_config/Cargo.toml
+++ b/crates/forge_config/Cargo.toml
@@ -20,4 +20,8 @@ merge.workspace = true
 tracing.workspace = true
 
 [dev-dependencies]
+anyhow.workspace = true
+is_ci.workspace = true
 pretty_assertions.workspace = true
+serde_json.workspace = true
+tokio = { workspace = true, features = ["rt-multi-thread", "macros"] }
diff --git a/crates/forge_config/src/auto_dump.rs b/crates/forge_config/src/auto_dump.rs
--- a/crates/forge_config/src/auto_dump.rs
+++ b/crates/forge_config/src/auto_dump.rs
@@ -1,7 +1,8 @@
+use schemars::JsonSchema;
 use serde::{Deserialize, Serialize};
 
 /// The output format used when auto-dumping a conversation on task completion.
-#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, fake::Dummy)]
+#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema, fake::Dummy)]
 #[serde(rename_all = "snake_case")]
 pub enum AutoDumpFormat {
     /// Dump as a JSON file
diff --git a/crates/forge_config/src/compact.rs b/crates/forge_config/src/compact.rs
--- a/crates/forge_config/src/compact.rs
+++ b/crates/forge_config/src/compact.rs
@@ -52,24 +52,6 @@ where
     Ok(value)
 }
 
-/// Optional tag name used when extracting summarized content during compaction
-#[derive(Serialize, Deserialize, Debug, Clone, JsonSchema, PartialEq, fake::Dummy)]
-#[serde(transparent)]
-pub struct SummaryTag(String);
-
-impl Default for SummaryTag {
-    fn default() -> Self {
-        SummaryTag("forge_context_summary".to_string())
-    }
-}
-
-impl SummaryTag {
-    /// Returns the inner string slice
-    pub fn as_str(&self) -> &str {
-        self.0.as_str()
-    }
-}
-
 /// Configuration for automatic context compaction for all agents
 #[derive(Debug, Clone, Serialize, Deserialize, Setters, JsonSchema, PartialEq)]
 #[setters(strip_option, into)]
@@ -111,11 +93,6 @@ pub struct Compact {
     #[serde(skip_serializing_if = "Option::is_none")]
     pub model: Option<String>,
 
-    /// Optional tag name to extract content from when summarizing (e.g.,
-    /// "summary")
-    #[serde(skip_serializing_if = "Option::is_none")]
-    pub summary_tag: Option<SummaryTag>,
-
     /// Whether to trigger compaction when the last message is from a user
     #[serde(default, skip_serializing_if = "Option::is_none")]
     pub on_turn_end: Option<bool>,
@@ -135,7 +112,6 @@ impl Compact {
             token_threshold: None,
             turn_threshold: None,
             message_threshold: None,
-            summary_tag: None,
             model: None,
             eviction_window: 0.2,
             retention_window: 0,
@@ -155,7 +131,6 @@ impl Dummy<fake::Faker> for Compact {
             turn_threshold: fake::Faker.fake_with_rng(rng),
             message_threshold: fake::Faker.fake_with_rng(rng),
             model: fake::Faker.fake_with_rng(rng),
-            summary_tag: fake::Faker.fake_with_rng(rng),
             on_turn_end: fake::Faker.fake_with_rng(rng),
         }
     }
diff --git a/crates/forge_config/src/config.rs b/crates/forge_config/src/config.rs
--- a/crates/forge_config/src/config.rs
+++ b/crates/forge_config/src/config.rs
@@ -2,6 +2,7 @@ use std::path::PathBuf;
 
 use derive_setters::Setters;
 use fake::Dummy;
+use schemars::JsonSchema;
 use serde::{Deserialize, Serialize};
 
 use crate::reader::ConfigReader;
@@ -10,7 +11,7 @@ use crate::{AutoDumpFormat, Compact, HttpConfig, ModelConfig, RetryConfig, Updat
 
 /// Top-level Forge configuration merged from all sources (defaults, file,
 /// environment).
-#[derive(Default, Debug, Setters, Clone, PartialEq, Serialize, Deserialize)]
+#[derive(Default, Debug, Setters, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
 #[serde(rename_all = "snake_case")]
 #[setters(strip_option)]
 pub struct ForgeConfig {
@@ -65,13 +66,13 @@ pub struct ForgeConfig {
     /// TTL in seconds for the model API list cache
     pub model_cache_ttl_secs: u64,
     /// Default model and provider configuration used when not overridden by
-    /// individual agents.
+    /// individual agents.    
     #[serde(default)]
     pub session: Option<ModelConfig>,
-    /// Provider and model to use for commit message generation
+    /// Provider and model to use for commit message generation    
     #[serde(default)]
     pub commit: Option<ModelConfig>,
-    /// Provider and model to use for shell command suggestion generation
+    /// Provider and model to use for shell command suggestion generation    
     #[serde(default)]
     pub suggest: Option<ModelConfig>,
 
@@ -115,9 +116,12 @@ pub struct ForgeConfig {
     pub compact: Option<Compact>,
 
     /// Whether the application is running in restricted mode.
-    /// When true, tool execution requires explicit permission grants.
-    #[serde(default)]
+    /// When true, tool execution requires explicit permission grants.    
     pub restricted: bool,
+
+    /// Whether tool use is supported in the current environment.
+    /// When false, tool calls are disabled regardless of agent configuration.
+    pub tool_supported: bool,
 }
 
 impl ForgeConfig {
@@ -191,6 +195,7 @@ impl Dummy<fake::Faker> for ForgeConfig {
             max_requests_per_turn: fake::Faker.fake_with_rng(rng),
             compact: fake::Faker.fake_with_rng(rng),
             restricted: fake::Faker.fake_with_rng(rng),
+            tool_supported: fake::Faker.fake_with_rng(rng),
         }
     }
 }
diff --git a/crates/forge_config/src/http.rs b/crates/forge_config/src/http.rs
--- a/crates/forge_config/src/http.rs
+++ b/crates/forge_config/src/http.rs
@@ -1,7 +1,8 @@
+use schemars::JsonSchema;
 use serde::{Deserialize, Serialize};
 
 /// TLS version enum for configuring TLS protocol versions.
-#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, fake::Dummy)]
+#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema, fake::Dummy)]
 #[serde(rename_all = "snake_case")]
 pub enum TlsVersion {
     #[serde(rename = "1.0")]
@@ -15,7 +16,7 @@ pub enum TlsVersion {
 }
 
 /// TLS backend option.
-#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, fake::Dummy)]
+#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema, fake::Dummy)]
 #[serde(rename_all = "snake_case")]
 pub enum TlsBackend {
     #[serde(rename = "default")]
@@ -25,7 +26,7 @@ pub enum TlsBackend {
 }
 
 /// HTTP client configuration.
-#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, fake::Dummy)]
+#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema, fake::Dummy)]
 #[serde(rename_all = "snake_case")]
 pub struct HttpConfig {
     pub connect_timeout_secs: u64,
diff --git a/crates/forge_config/src/model.rs b/crates/forge_config/src/model.rs
--- a/crates/forge_config/src/model.rs
+++ b/crates/forge_config/src/model.rs
@@ -1,4 +1,5 @@
 use derive_setters::Setters;
+use schemars::JsonSchema;
 use serde::{Deserialize, Serialize};
 
 /// A type alias for a provider identifier string.
@@ -8,7 +9,9 @@ pub type ProviderId = String;
 pub type ModelId = String;
 
 /// Pairs a provider and model together for a specific operation.
-#[derive(Default, Debug, Setters, Clone, PartialEq, Serialize, Deserialize, fake::Dummy)]
+#[derive(
+    Default, Debug, Setters, Clone, PartialEq, Serialize, Deserialize, JsonSchema, fake::Dummy,
+)]
 #[setters(strip_option, into)]
 pub struct ModelConfig {
     /// The provider to use for this operation.
diff --git a/crates/forge_config/src/retry.rs b/crates/forge_config/src/retry.rs
--- a/crates/forge_config/src/retry.rs
+++ b/crates/forge_config/src/retry.rs
@@ -1,7 +1,8 @@
+use schemars::JsonSchema;
 use serde::{Deserialize, Serialize};
 
 /// Configuration for retry mechanism.
-#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, fake::Dummy)]
+#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema, fake::Dummy)]
 #[serde(rename_all = "snake_case")]
 pub struct RetryConfig {
     /// Initial backoff delay in milliseconds for retry operations
diff --git a/crates/forge_domain/src/agent.rs b/crates/forge_domain/src/agent.rs
--- a/crates/forge_domain/src/agent.rs
+++ b/crates/forge_domain/src/agent.rs
@@ -2,9 +2,9 @@ use derive_setters::Setters;
 use merge::Merge;
 
 use crate::{
-    AgentDefinition, AgentId, Compact, Error, EventContext, MaxTokens, ModelId, ProviderId,
-    ReasoningConfig, Result, SystemContext, Temperature, Template, ToolDefinition, ToolName, TopK,
-    TopP, Workflow,
+    AgentDefinition, AgentId, Compact, Environment, Error, EventContext, MaxTokens, ModelId,
+    ProviderId, ReasoningConfig, Result, SystemContext, Temperature, Template, ToolDefinition,
+    ToolName, TopK, TopP,
 };
 
 /// Runtime agent representation with required model and provider
@@ -114,49 +114,41 @@ impl Agent {
     }
 
     /// Helper to prepare agents with workflow settings
-    pub fn apply_workflow_config(self, workflow: &Workflow) -> Agent {
+    pub fn apply_env(self, env: &Environment) -> Agent {
         let mut agent = self;
-        if let Some(custom_rules) = workflow.custom_rules.clone() {
-            if let Some(existing_rules) = &agent.custom_rules {
-                agent.custom_rules = Some(existing_rules.clone() + "\n\n" + &custom_rules);
-            } else {
-                agent.custom_rules = Some(custom_rules);
-            }
-        }
 
-        if let Some(temperature) = workflow.temperature {
+        if let Some(temperature) = env.temperature {
             agent.temperature = Some(temperature);
         }
 
-        if let Some(top_p) = workflow.top_p {
+        if let Some(top_p) = env.top_p {
             agent.top_p = Some(top_p);
         }
 
-        if let Some(top_k) = workflow.top_k {
+        if let Some(top_k) = env.top_k {
             agent.top_k = Some(top_k);
         }
 
-        if let Some(max_tokens) = workflow.max_tokens {
+        if let Some(max_tokens) = env.max_tokens {
             agent.max_tokens = Some(max_tokens);
         }
 
-        if let Some(tool_supported) = workflow.tool_supported {
-            agent.tool_supported = Some(tool_supported);
-        }
         if agent.max_tool_failure_per_turn.is_none()
-            && let Some(max_tool_failure_per_turn) = workflow.max_tool_failure_per_turn
+            && let Some(max_tool_failure_per_turn) = env.max_tool_failure_per_turn
         {
             agent.max_tool_failure_per_turn = Some(max_tool_failure_per_turn);
         }
 
+        agent.tool_supported = Some(env.tool_supported);
+
         if agent.max_requests_per_turn.is_none()
-            && let Some(max_requests_per_turn) = workflow.max_requests_per_turn
+            && let Some(max_requests_per_turn) = env.max_requests_per_turn
         {
             agent.max_requests_per_turn = Some(max_requests_per_turn);
         }
 
         // Apply workflow compact configuration to agents
-        if let Some(ref workflow_compact) = workflow.compact {
+        if let Some(ref workflow_compact) = env.compact {
             // Merge workflow config into agent config
             // Agent settings take priority over workflow settings
             let mut merged_compact = workflow_compact.clone();
diff --git a/crates/forge_domain/src/command.rs b/crates/forge_domain/src/command.rs
new file mode 100644
--- /dev/null
+++ b/crates/forge_domain/src/command.rs
@@ -0,0 +1,21 @@
+use derive_setters::Setters;
+use serde::Deserialize;
+
+/// A user-defined command loaded from a Markdown file with YAML frontmatter.
+///
+/// Commands are discovered from `.md` files in the forge commands directories
+/// and made available as slash commands in the UI. The `name` and `description`
+/// come from YAML frontmatter; the `prompt` is the Markdown body of the file.
+#[derive(Debug, Clone, Default, Deserialize, Setters, PartialEq)]
+#[setters(into, strip_option)]
+pub struct Command {
+    /// The command name used to invoke it (e.g. `github-pr-description`).
+    #[serde(default)]
+    pub name: String,
+    /// Short description shown in the command list.
+    #[serde(default)]
+    pub description: String,
+    /// The prompt template body (Markdown content after the frontmatter).
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub prompt: Option<String>,
+}
diff --git a/crates/forge_domain/src/compact/compact_config.rs b/crates/forge_domain/src/compact/compact_config.rs
--- a/crates/forge_domain/src/compact/compact_config.rs
+++ b/crates/forge_domain/src/compact/compact_config.rs
@@ -52,12 +52,6 @@ pub struct Compact {
     #[merge(strategy = crate::merge::option)]
     #[serde(skip_serializing_if = "Option::is_none")]
     pub model: Option<ModelId>,
-    /// Optional tag name to extract content from when summarizing (e.g.,
-    /// "summary")
-    #[merge(strategy = crate::merge::std::overwrite)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    pub summary_tag: Option<SummaryTag>,
-
     /// Whether to trigger compaction when the last message is from a user
     #[serde(default, skip_serializing_if = "Option::is_none")]
     #[merge(strategy = crate::merge::option)]
@@ -79,22 +73,6 @@ where
     Ok(value)
 }
 
-#[derive(Serialize, Deserialize, Debug, Clone, JsonSchema, PartialEq)]
-#[serde(transparent)]
-pub struct SummaryTag(String);
-
-impl Default for SummaryTag {
-    fn default() -> Self {
-        SummaryTag("forge_context_summary".to_string())
-    }
-}
-
-impl SummaryTag {
-    pub fn as_str(&self) -> &str {
-        self.0.as_str()
-    }
-}
-
 impl Default for Compact {
     fn default() -> Self {
         Self::new()
@@ -110,7 +88,6 @@ impl Compact {
             token_threshold: None,
             turn_threshold: None,
             message_threshold: None,
-            summary_tag: None,
             model: None,
             eviction_window: 0.2, // Default to 20% compaction
             retention_window: 0,
diff --git a/crates/forge_domain/src/env.rs b/crates/forge_domain/src/env.rs
--- a/crates/forge_domain/src/env.rs
+++ b/crates/forge_domain/src/env.rs
@@ -7,7 +7,10 @@ use derive_setters::Setters;
 use serde::{Deserialize, Serialize};
 use url::Url;
 
-use crate::{CommitConfig, HttpConfig, ModelId, ProviderId, RetryConfig, SuggestConfig};
+use crate::{
+    CommitConfig, Compact, HttpConfig, MaxTokens, ModelId, ProviderId, RetryConfig, SuggestConfig,
+    Temperature, TopK, TopP, Update,
+};
 
 /// Domain-level session configuration pairing a provider with a model.
 ///
@@ -144,6 +147,54 @@ pub struct Environment {
     /// Whether the application is running in restricted mode.
     /// When true, tool execution requires explicit permission grants.
     pub is_restricted: bool,
+
+    /// Whether tool use is supported in the current environment.
+    /// When false, tool calls are disabled regardless of agent configuration.
+    pub tool_supported: bool,
+
+    // --- Workflow configuration fields ---
+    /// Output randomness for all agents; lower values are deterministic, higher
+    /// values are creative (0.0–2.0).
+    #[dummy(default)]
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub temperature: Option<Temperature>,
+
+    /// Nucleus sampling threshold for all agents; limits token selection to the
+    /// top cumulative probability mass (0.0–1.0).
+    #[dummy(default)]
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub top_p: Option<TopP>,
+
+    /// Top-k vocabulary cutoff for all agents; restricts sampling to the k
+    /// highest-probability tokens (1–1000).
+    #[dummy(default)]
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub top_k: Option<TopK>,
+
+    /// Maximum tokens the model may generate per response for all agents
+    /// (1–100,000).
+    #[dummy(default)]
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub max_tokens: Option<MaxTokens>,
+
+    /// Maximum tool failures per turn before the orchestrator forces
+    /// completion.
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub max_tool_failure_per_turn: Option<usize>,
+
+    /// Maximum number of requests that can be made in a single turn.
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub max_requests_per_turn: Option<usize>,
+
+    /// Context compaction settings applied to all agents.
+    #[dummy(default)]
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub compact: Option<Compact>,
+
+    /// Configuration for automatic forge updates.
+    #[dummy(default)]
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub updates: Option<Update>,
 }
 
 /// The output format used when auto-dumping a conversation on task completion.
@@ -225,23 +276,13 @@ impl Environment {
         self.base_path.join(".mcp.json")
     }
 
-    pub fn templates(&self) -> PathBuf {
-        self.base_path.join("templates")
-    }
     pub fn agent_path(&self) -> PathBuf {
         self.base_path.join("agents")
     }
     pub fn agent_cwd_path(&self) -> PathBuf {
         self.cwd.join(".forge/agents")
     }
 
-    pub fn command_path(&self) -> PathBuf {
-        self.base_path.join("commands")
-    }
-
-    pub fn command_cwd_path(&self) -> PathBuf {
-        self.cwd.join(".forge/commands")
-    }
     pub fn permissions_path(&self) -> PathBuf {
         self.base_path.join("permissions.yaml")
     }
@@ -277,6 +318,38 @@ impl Environment {
         self.cwd.join(".forge/skills")
     }
 
+    /// Returns the global commands directory path (base_path/commands)
+    pub fn command_path(&self) -> PathBuf {
+        self.base_path.join("commands")
+    }
+
+    /// Returns the project-local commands directory path (.forge/commands)
+    pub fn command_path_local(&self) -> PathBuf {
+        self.cwd.join(".forge/commands")
+    }
+
+    /// Returns the global AGENTS.md path (base_path/AGENTS.md)
+    pub fn global_agentsmd_path(&self) -> PathBuf {
+        self.base_path.join("AGENTS.md")
+    }
+
+    /// Returns the project-local AGENTS.md path (cwd/AGENTS.md)
+    pub fn local_agentsmd_path(&self) -> PathBuf {
+        self.cwd.join("AGENTS.md")
+    }
+
+    /// Returns the plans directory path relative to the current working
+    /// directory (cwd/plans)
+    pub fn plans_path(&self) -> PathBuf {
+        self.cwd.join("plans")
+    }
+
+    /// Returns the path to the custom provider configuration file
+    /// (base_path/provider.json)
+    pub fn provider_config_path(&self) -> PathBuf {
+        self.base_path.join("provider.json")
+    }
+
     /// Returns the path to the credentials file where provider API keys are
     /// stored
     pub fn credentials_path(&self) -> PathBuf {
@@ -481,151 +554,88 @@ mod tests {
         // Verify they are different paths
         assert_ne!(global_path, local_path);
     }
-}
 
-#[test]
-fn test_command_path() {
-    let fixture = Environment {
-        os: "linux".to_string(),
-        pid: 1234,
-        cwd: PathBuf::from("/current/working/dir"),
-        home: Some(PathBuf::from("/home/user")),
-        shell: "zsh".to_string(),
-        base_path: PathBuf::from("/home/user/.forge"),
-        service_url: "https://api.example.com".parse().unwrap(),
-        retry_config: RetryConfig::default(),
-        max_search_lines: 1000,
-        max_search_result_bytes: 10240,
-        fetch_truncation_limit: 50000,
-        stdout_max_prefix_length: 100,
-        stdout_max_suffix_length: 100,
-        stdout_max_line_length: 500,
-        max_line_length: 2000,
-        max_read_size: 2000,
-        max_file_read_batch_size: 50,
-        http: HttpConfig::default(),
-        max_file_size: 104857600,
-        tool_timeout: 300,
-        auto_open_dump: false,
-        debug_requests: None,
-        custom_history_path: None,
-        max_conversations: 100,
-        sem_search_limit: 100,
-        sem_search_top_k: 10,
-        max_image_size: 262144,
-        max_extensions: 15,
-        auto_dump: None,
-        parallel_file_reads: 64,
-        model_cache_ttl: 604_800,
-        session: None,
-        commit: None,
-        suggest: None,
-        is_restricted: false,
-    };
-
-    let actual = fixture.command_path();
-    let expected = PathBuf::from("/home/user/.forge/commands");
-
-    assert_eq!(actual, expected);
-}
+    #[test]
+    fn test_command_path() {
+        let fixture: Environment = Faker.fake();
+        let fixture = fixture.base_path(PathBuf::from("/home/user/.forge"));
 
-#[test]
-fn test_command_cwd_path() {
-    let fixture = Environment {
-        os: "linux".to_string(),
-        pid: 1234,
-        cwd: PathBuf::from("/current/working/dir"),
-        home: Some(PathBuf::from("/home/user")),
-        shell: "zsh".to_string(),
-        base_path: PathBuf::from("/home/user/.forge"),
-        service_url: "https://api.example.com".parse().unwrap(),
-        retry_config: RetryConfig::default(),
-        max_search_lines: 1000,
-        max_search_result_bytes: 10240,
-        fetch_truncation_limit: 50000,
-        stdout_max_prefix_length: 100,
-        stdout_max_suffix_length: 100,
-        stdout_max_line_length: 500,
-        max_line_length: 2000,
-        max_read_size: 2000,
-        max_file_read_batch_size: 50,
-        http: HttpConfig::default(),
-        max_file_size: 104857600,
-        tool_timeout: 300,
-        auto_open_dump: false,
-        debug_requests: None,
-        custom_history_path: None,
-        max_conversations: 100,
-        sem_search_limit: 100,
-        sem_search_top_k: 10,
-        max_image_size: 262144,
-        max_extensions: 15,
-        auto_dump: None,
-        parallel_file_reads: 64,
-        model_cache_ttl: 604_800,
-        session: None,
-        commit: None,
-        suggest: None,
-        is_restricted: false,
-    };
-
-    let actual = fixture.command_cwd_path();
-    let expected = PathBuf::from("/current/working/dir/.forge/commands");
-
-    assert_eq!(actual, expected);
-}
+        let actual = fixture.command_path();
+        let expected = PathBuf::from("/home/user/.forge/commands");
 
-#[test]
-fn test_command_cwd_path_independent_from_command_path() {
-    let fixture = Environment {
-        os: "linux".to_string(),
-        pid: 1234,
-        cwd: PathBuf::from("/different/current/dir"),
-        home: Some(PathBuf::from("/different/home")),
-        shell: "bash".to_string(),
-        base_path: PathBuf::from("/completely/different/base"),
-        service_url: "https://api.example.com".parse().unwrap(),
-        retry_config: RetryConfig::default(),
-        max_search_lines: 1000,
-        max_search_result_bytes: 10240,
-        fetch_truncation_limit: 50000,
-        stdout_max_prefix_length: 100,
-        stdout_max_suffix_length: 100,
-        stdout_max_line_length: 500,
-        max_line_length: 2000,
-        max_read_size: 2000,
-        max_file_read_batch_size: 50,
-        http: HttpConfig::default(),
-        max_file_size: 104857600,
-        tool_timeout: 300,
-        auto_open_dump: false,
-        debug_requests: None,
-        custom_history_path: None,
-        max_conversations: 100,
-        sem_search_limit: 100,
-        sem_search_top_k: 10,
-        max_image_size: 262144,
-        max_extensions: 15,
-        auto_dump: None,
-        parallel_file_reads: 64,
-        model_cache_ttl: 604_800,
-        session: None,
-        commit: None,
-        suggest: None,
-        is_restricted: false,
-    };
-
-    let command_path = fixture.command_path();
-    let command_cwd_path = fixture.command_cwd_path();
-    let expected_command_path = PathBuf::from("/completely/different/base/commands");
-    let expected_command_cwd_path = PathBuf::from("/different/current/dir/.forge/commands");
-
-    // Verify that command_path uses base_path
-    assert_eq!(command_path, expected_command_path);
-
-    // Verify that command_cwd_path is independent and always relative to CWD
-    assert_eq!(command_cwd_path, expected_command_cwd_path);
-
-    // Verify they are different paths
-    assert_ne!(command_path, command_cwd_path);
+        assert_eq!(actual, expected);
+    }
+
+    #[test]
+    fn test_command_path_local() {
+        let fixture: Environment = Faker.fake();
+        let fixture = fixture.cwd(PathBuf::from("/projects/my-app"));
+
+        let actual = fixture.command_path_local();
+        let expected = PathBuf::from("/projects/my-app/.forge/commands");
+
+        assert_eq!(actual, expected);
+    }
+
+    #[test]
+    fn test_command_paths_independent() {
+        let fixture: Environment = Faker.fake();
+        let fixture = fixture
+            .cwd(PathBuf::from("/projects/my-app"))
+            .base_path(PathBuf::from("/home/user/.forge"));
+
+        let global_path = fixture.command_path();
+        let local_path = fixture.command_path_local();
+
+        let expected_global = PathBuf::from("/home/user/.forge/commands");
+        let expected_local = PathBuf::from("/projects/my-app/.forge/commands");
+
+        assert_eq!(global_path, expected_global);
+        assert_eq!(local_path, expected_local);
+        assert_ne!(global_path, local_path);
+    }
+
+    #[test]
+    fn test_global_agents_md_path() {
+        let fixture: Environment = Faker.fake();
+        let fixture = fixture.base_path(PathBuf::from("/home/user/.forge"));
+
+        let actual = fixture.global_agentsmd_path();
+        let expected = PathBuf::from("/home/user/.forge/AGENTS.md");
+
+        assert_eq!(actual, expected);
+    }
+
+    #[test]
+    fn test_local_agents_md_path() {
+        let fixture: Environment = Faker.fake();
+        let fixture = fixture.cwd(PathBuf::from("/projects/my-app"));
+
+        let actual = fixture.local_agentsmd_path();
+        let expected = PathBuf::from("/projects/my-app/AGENTS.md");
+
+        assert_eq!(actual, expected);
+    }
+
+    #[test]
+    fn test_plans_path() {
+        let fixture: Environment = Faker.fake();
+        let fixture = fixture.cwd(PathBuf::from("/projects/my-app"));
+
+        let actual = fixture.plans_path();
+        let expected = PathBuf::from("/projects/my-app/plans");
+
+        assert_eq!(actual, expected);
+    }
+
+    #[test]
+    fn test_provider_config_path() {
+        let fixture: Environment = Faker.fake();
+        let fixture = fixture.base_path(PathBuf::from("/home/user/.forge"));
+
+        let actual = fixture.provider_config_path();
+        let expected = PathBuf::from("/home/user/.forge/provider.json");
+
+        assert_eq!(actual, expected);
+    }
 }
diff --git a/crates/forge_domain/src/lib.rs b/crates/forge_domain/src/lib.rs
--- a/crates/forge_domain/src/lib.rs
+++ b/crates/forge_domain/src/lib.rs
@@ -4,6 +4,7 @@ mod attachment;
 mod auth;
 mod chat_request;
 mod chat_response;
+mod command;
 mod commit_config;
 mod compact;
 mod console;
@@ -53,7 +54,6 @@ mod top_p;
 mod transformer;
 mod update;
 mod validation;
-mod workflow;
 mod workspace;
 mod xml;
 
@@ -62,6 +62,7 @@ pub use agent_definition::*;
 pub use attachment::*;
 pub use chat_request::*;
 pub use chat_response::*;
+pub use command::*;
 pub use commit_config::*;
 pub use compact::*;
 pub use console::*;
@@ -110,7 +111,6 @@ pub use top_p::*;
 pub use transformer::*;
 pub use update::*;
 pub use validation::*;
-pub use workflow::*;
 pub use workspace::*;
 pub use xml::*;
 pub mod line_numbers;
diff --git a/crates/forge_domain/src/update.rs b/crates/forge_domain/src/update.rs
--- a/crates/forge_domain/src/update.rs
+++ b/crates/forge_domain/src/update.rs
@@ -5,7 +5,7 @@ use merge::Merge;
 use schemars::JsonSchema;
 use serde::{Deserialize, Serialize};
 
-#[derive(Default, Debug, Clone, Serialize, Deserialize, JsonSchema)]
+#[derive(Default, Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq)]
 #[serde(rename_all = "snake_case")]
 pub enum UpdateFrequency {
     Daily,
@@ -24,7 +24,7 @@ impl From<UpdateFrequency> for Duration {
     }
 }
 
-#[derive(Debug, Clone, Serialize, Deserialize, Merge, Default, JsonSchema, Setters)]
+#[derive(Debug, Clone, Serialize, Deserialize, Merge, Default, JsonSchema, Setters, PartialEq)]
 #[merge(strategy = merge::option::overwrite_none)]
 pub struct Update {
     pub frequency: Option<UpdateFrequency>,
diff --git a/crates/forge_domain/src/workflow.rs b/crates/forge_domain/src/workflow.rs
deleted file mode 100644
--- a/crates/forge_domain/src/workflow.rs
+++ /dev/null
@@ -1,278 +0,0 @@
-use std::sync::LazyLock;
-
-use derive_setters::Setters;
-use merge::Merge;
-use schemars::JsonSchema;
-use serde::{Deserialize, Serialize};
-
-use crate::temperature::Temperature;
-use crate::update::Update;
-use crate::{Compact, MaxTokens, TopK, TopP};
-
-/// Configuration for a workflow that contains all settings
-/// required to initialize a workflow.
-#[derive(Debug, Clone, Serialize, Deserialize, Merge, Setters, JsonSchema)]
-#[setters(strip_option, into)]
-pub struct Workflow {
-    /// Path pattern for custom template files (supports glob patterns)
-    #[serde(default)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub templates: Option<String>,
-
-    /// configurations that can be used to update forge
-    #[merge(strategy = crate::merge::option)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    pub updates: Option<Update>,
-
-    /// Commands that can be used to interact with the workflow
-    #[merge(strategy = merge::vec::append)]
-    #[serde(default, skip_serializing_if = "Vec::is_empty")]
-    pub commands: Vec<Command>,
-
-    /// A set of custom rules that all agents should follow
-    /// These rules will be applied in addition to each agent's individual rules
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub custom_rules: Option<String>,
-
-    /// Temperature used for all agents
-    ///
-    /// Temperature controls the randomness in the model's output.
-    /// - Lower values (e.g., 0.1) make responses more focused, deterministic,
-    ///   and coherent
-    /// - Higher values (e.g., 0.8) make responses more creative, diverse, and
-    ///   exploratory
-    /// - Valid range is 0.0 to 2.0
-    /// - If not specified, each agent's individual setting or the model
-    ///   provider's default will be used
-    #[serde(default)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub temperature: Option<Temperature>,
-
-    /// Top-p (nucleus sampling) used for all agents
-    ///
-    /// Controls the diversity of the model's output by considering only the
-    /// most probable tokens up to a cumulative probability threshold.
-    /// - Lower values (e.g., 0.1) make responses more focused
-    /// - Higher values (e.g., 0.9) make responses more diverse
-    /// - Valid range is 0.0 to 1.0
-    /// - If not specified, each agent's individual setting or the model
-    ///   provider's default will be used
-    #[serde(default)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub top_p: Option<TopP>,
-
-    /// Top-k used for all agents
-    ///
-    /// Controls the number of highest probability vocabulary tokens to keep.
-    /// - Lower values (e.g., 10) make responses more focused
-    /// - Higher values (e.g., 100) make responses more diverse
-    /// - Valid range is 1 to 1000
-    /// - If not specified, each agent's individual setting or the model
-    ///   provider's default will be used
-    #[serde(default)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub top_k: Option<TopK>,
-
-    /// Maximum number of tokens the model can generate for all agents
-    ///
-    /// Controls the maximum length of the model's response.
-    /// - Lower values (e.g., 100) limit response length for concise outputs
-    /// - Higher values (e.g., 4000) allow for longer, more detailed responses
-    /// - Valid range is 1 to 100,000
-    /// - If not specified, each agent's individual setting or the model
-    ///   provider's default will be used
-    #[serde(default)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub max_tokens: Option<MaxTokens>,
-
-    /// Flag to enable/disable tool support for all agents in this workflow.
-    /// If not specified, each agent's individual setting will be used.
-    /// Default is false (tools disabled) when not specified.
-    #[serde(default)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub tool_supported: Option<bool>,
-
-    /// Maximum number of times a tool can fail before the orchestrator
-    /// forces the completion.
-    #[serde(default)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub max_tool_failure_per_turn: Option<usize>,
-
-    /// Maximum number of requests that can be made in a single turn
-    #[serde(default)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub max_requests_per_turn: Option<usize>,
-    /// Configuration for automatic context compaction for all agents
-    /// If specified, this will be applied to all agents in the workflow
-    /// If not specified, each agent's individual setting will be used
-    #[serde(default)]
-    #[serde(skip_serializing_if = "Option::is_none")]
-    #[merge(strategy = crate::merge::option)]
-    pub compact: Option<Compact>,
-}
-
-static DEFAULT_WORKFLOW: LazyLock<Workflow> =
-    LazyLock::new(|| serde_yml::from_str(include_str!("../../../forge.default.yaml")).unwrap());
-
-impl Default for Workflow {
-    fn default() -> Self {
-        DEFAULT_WORKFLOW.clone()
-    }
-}
-
-#[derive(Default, Debug, Clone, Serialize, Deserialize, Merge, Setters, JsonSchema)]
-#[setters(strip_option, into)]
-pub struct Command {
-    #[merge(strategy = crate::merge::std::overwrite)]
-    pub name: String,
-
-    #[merge(strategy = crate::merge::std::overwrite)]
-    pub description: String,
-
-    #[merge(strategy = crate::merge::option)]
-    pub prompt: Option<String>,
-}
-
-impl Workflow {
-    /// Creates a new empty workflow with all fields set to their empty state.
-    /// This is useful for testing where you want to build a workflow from
-    /// scratch.
-    pub fn new() -> Self {
-        Self {
-            custom_rules: None,
-            temperature: None,
-            top_p: None,
-            top_k: None,
-            max_tokens: None,
-            tool_supported: None,
-            updates: None,
-            templates: None,
-            max_tool_failure_per_turn: None,
-            max_requests_per_turn: None,
-            compact: None,
-            commands: vec![],
-        }
-    }
-}
-
-#[cfg(test)]
-mod tests {
-    use pretty_assertions::assert_eq;
-
-    use super::*;
-    use crate::ModelId;
-
-    #[test]
-    fn test_workflow_new_creates_empty_workflow() {
-        // Arrange
-
-        // Act
-        let actual = Workflow::new();
-
-        // Assert
-        assert_eq!(actual.custom_rules, None);
-        assert_eq!(actual.temperature, None);
-        assert_eq!(actual.top_p, None);
-        assert_eq!(actual.top_k, None);
-        assert_eq!(actual.max_tokens, None);
-        assert_eq!(actual.tool_supported, None);
-        assert_eq!(actual.compact, None);
-    }
-
-    #[test]
-    fn test_workflow_with_tool_supported() {
-        // Arrange
-        let fixture = r#"
-        {
-            "tool_supported": true,
-            "agents": [
-                {
-                    "id": "test-agent",
-                    "description": "Test agent"
-                }
-            ]
-        }
-        "#;
-
-        // Act
-        let actual: Workflow = serde_json::from_str(fixture).unwrap();
-
-        // Assert
-        assert_eq!(actual.tool_supported, Some(true));
-    }
-
-    #[test]
-    fn test_workflow_merge_tool_supported() {
-        // Fixture
-        let mut base = Workflow::new();
-
-        let other = Workflow::new().tool_supported(true);
-
-        // Act
-        base.merge(other);
-
-        // Assert
-        assert_eq!(base.tool_supported, Some(true));
-    }
-
-    #[test]
-    fn test_workflow_merge_tool_supported_with_existing() {
-        // Fixture
-        let mut base = Workflow::new().tool_supported(false);
-
-        let other = Workflow::new().tool_supported(true);
-
-        // Act
-        base.merge(other);
-
-        // Assert
-        assert_eq!(base.tool_supported, Some(true));
-    }
-    #[test]
-    fn test_workflow_merge_compact() {
-        // Fixture
-        let mut base = Workflow::new();
-
-        let compact = Compact::new()
-            .model(ModelId::new("test-model"))
-            .token_threshold(1000_usize)
-            .turn_threshold(5_usize);
-        let other = Workflow::new().compact(compact.clone());
-
-        // Act
-        base.merge(other);
-
-        // Assert
-        assert_eq!(base.compact, Some(compact));
-    }
-
-    #[test]
-    fn test_workflow_merge_compact_with_existing() {
-        // Fixture
-        let existing_compact = Compact::new()
-            .model(ModelId::new("existing-model"))
-            .token_threshold(500_usize);
-        let mut base = Workflow::new().compact(existing_compact);
-
-        let new_compact = Compact::new()
-            .model(ModelId::new("new-model"))
-            .token_threshold(1000_usize)
-            .turn_threshold(5_usize);
-        let other = Workflow::new().compact(new_compact.clone());
-
-        // Act
-        base.merge(other);
-
-        // Assert
-        assert_eq!(base.compact, Some(new_compact));
-    }
-}
diff --git a/crates/forge_infra/src/env.rs b/crates/forge_infra/src/env.rs
--- a/crates/forge_infra/src/env.rs
+++ b/crates/forge_infra/src/env.rs
@@ -5,8 +5,9 @@ use std::sync::Arc;
 use forge_app::EnvironmentInfra;
 use forge_config::{ConfigReader, ForgeConfig, ModelConfig};
 use forge_domain::{
-    AutoDumpFormat, ConfigOperation, Environment, HttpConfig, RetryConfig, SessionConfig,
-    TlsBackend, TlsVersion,
+    AutoDumpFormat, Compact, ConfigOperation, Environment, HttpConfig, MaxTokens, ModelId,
+    RetryConfig, SessionConfig, Temperature, TlsBackend, TlsVersion, TopK, TopP, Update,
+    UpdateFrequency,
 };
 use reqwest::Url;
 use tracing::{debug, error};
@@ -81,6 +82,38 @@ fn to_auto_dump_format(f: forge_config::AutoDumpFormat) -> AutoDumpFormat {
     }
 }
 
+/// Converts a [`forge_config::UpdateFrequency`] into a
+/// [`forge_domain::UpdateFrequency`].
+fn to_update_frequency(f: forge_config::UpdateFrequency) -> UpdateFrequency {
+    match f {
+        forge_config::UpdateFrequency::Daily => UpdateFrequency::Daily,
+        forge_config::UpdateFrequency::Weekly => UpdateFrequency::Weekly,
+        forge_config::UpdateFrequency::Always => UpdateFrequency::Always,
+    }
+}
+
+/// Converts a [`forge_config::Update`] into a [`forge_domain::Update`].
+fn to_update(u: forge_config::Update) -> Update {
+    Update {
+        frequency: u.frequency.map(to_update_frequency),
+        auto_update: u.auto_update,
+    }
+}
+
+/// Converts a [`forge_config::Compact`] into a [`forge_domain::Compact`].
+fn to_compact(c: forge_config::Compact) -> Compact {
+    Compact {
+        retention_window: c.retention_window,
+        eviction_window: c.eviction_window,
+        max_tokens: c.max_tokens,
+        token_threshold: c.token_threshold,
+        turn_threshold: c.turn_threshold,
+        message_threshold: c.message_threshold,
+        model: c.model.map(ModelId::new),
+        on_turn_end: c.on_turn_end,
+    }
+}
+
 /// Builds a [`forge_domain::Environment`] entirely from a [`ForgeConfig`] and
 /// runtime context (`restricted`, `cwd`), mapping every config field to its
 /// corresponding environment field.
@@ -131,6 +164,15 @@ fn to_environment(fc: ForgeConfig, cwd: PathBuf) -> Environment {
         commit: fc.commit.as_ref().map(to_session_config),
         suggest: fc.suggest.as_ref().map(to_session_config),
         is_restricted: fc.restricted,
+        tool_supported: fc.tool_supported,
+        temperature: fc.temperature.and_then(|v| Temperature::new(v).ok()),
+        top_p: fc.top_p.and_then(|v| TopP::new(v).ok()),
+        top_k: fc.top_k.and_then(|v| TopK::new(v).ok()),
+        max_tokens: fc.max_tokens.and_then(|v| MaxTokens::new(v).ok()),
+        max_tool_failure_per_turn: fc.max_tool_failure_per_turn,
+        max_requests_per_turn: fc.max_requests_per_turn,
+        compact: fc.compact.map(to_compact),
+        updates: fc.updates.map(to_update),
     }
 }
 
@@ -199,6 +241,38 @@ fn from_auto_dump_format(f: &AutoDumpFormat) -> forge_config::AutoDumpFormat {
     }
 }
 
+/// Converts a [`forge_domain::UpdateFrequency`] back into a
+/// [`forge_config::UpdateFrequency`].
+fn from_update_frequency(f: UpdateFrequency) -> forge_config::UpdateFrequency {
+    match f {
+        UpdateFrequency::Daily => forge_config::UpdateFrequency::Daily,
+        UpdateFrequency::Weekly => forge_config::UpdateFrequency::Weekly,
+        UpdateFrequency::Always => forge_config::UpdateFrequency::Always,
+    }
+}
+
+/// Converts a [`forge_domain::Update`] back into a [`forge_config::Update`].
+fn from_update(u: &Update) -> forge_config::Update {
+    forge_config::Update {
+        frequency: u.frequency.clone().map(from_update_frequency),
+        auto_update: u.auto_update,
+    }
+}
+
+/// Converts a [`forge_domain::Compact`] back into a [`forge_config::Compact`].
+fn from_compact(c: &Compact) -> forge_config::Compact {
+    forge_config::Compact {
+        retention_window: c.retention_window,
+        eviction_window: c.eviction_window,
+        max_tokens: c.max_tokens,
+        token_threshold: c.token_threshold,
+        turn_threshold: c.turn_threshold,
+        message_threshold: c.message_threshold,
+        model: c.model.as_ref().map(|m| m.to_string()),
+        on_turn_end: c.on_turn_end,
+    }
+}
+
 /// Converts an [`Environment`] back into a [`ForgeConfig`] suitable for
 /// persisting.
 ///
@@ -247,6 +321,17 @@ fn to_forge_config(env: &Environment) -> ForgeConfig {
     fc.max_parallel_file_reads = env.parallel_file_reads;
     fc.model_cache_ttl_secs = env.model_cache_ttl;
     fc.restricted = env.is_restricted;
+    fc.tool_supported = env.tool_supported;
+
+    // --- Workflow fields ---
+    fc.temperature = env.temperature.map(|t| t.value());
+    fc.top_p = env.top_p.map(|t| t.value());
+    fc.top_k = env.top_k.map(|t| t.value());
+    fc.max_tokens = env.max_tokens.map(|t| t.value());
+    fc.max_tool_failure_per_turn = env.max_tool_failure_per_turn;
+    fc.max_requests_per_turn = env.max_requests_per_turn;
+    fc.compact = env.compact.as_ref().map(from_compact);
+    fc.updates = env.updates.as_ref().map(from_update);
 
     // --- Session configs ---
     fc.session = env.session.as_ref().map(|sc| ModelConfig {
diff --git a/crates/forge_main/src/cli.rs b/crates/forge_main/src/cli.rs
--- a/crates/forge_main/src/cli.rs
+++ b/crates/forge_main/src/cli.rs
@@ -62,10 +62,6 @@ pub struct Cli {
     #[command(subcommand)]
     pub subcommands: Option<TopLevelCommand>,
 
-    /// Path to a file containing the workflow to execute.
-    #[arg(long, short = 'w')]
-    pub workflow: Option<PathBuf>,
-
     /// Event to dispatch to the workflow in JSON format.
     #[arg(long, short = 'e')]
     pub event: Option<String>,
diff --git a/crates/forge_main/src/ui.rs b/crates/forge_main/src/ui.rs
--- a/crates/forge_main/src/ui.rs
+++ b/crates/forge_main/src/ui.rs
@@ -12,7 +12,7 @@ use convert_case::{Case, Casing};
 use forge_api::{
     API, AgentId, AnyProvider, ApiKeyRequest, AuthContextRequest, AuthContextResponse, ChatRequest,
     ChatResponse, CodeRequest, Conversation, ConversationId, DeviceCodeRequest, Event,
-    InterruptionReason, Model, ModelId, Provider, ProviderId, TextMessage, UserPrompt, Workflow,
+    InterruptionReason, Model, ModelId, Provider, ProviderId, TextMessage, UserPrompt,
 };
 use forge_app::utils::{format_display_path, truncate_key};
 use forge_app::{CommitResult, ToolResolver};
@@ -25,7 +25,6 @@ use forge_select::ForgeWidget;
 use forge_spinner::SpinnerManager;
 use forge_tracker::ToolCallPayload;
 use futures::future;
-use merge::Merge;
 use tokio_stream::StreamExt;
 use url::Url;
 
@@ -2861,10 +2860,7 @@ impl<A: API + ConsoleWriter + 'static, F: Fn() -> A + Send + Sync> UI<A, F> {
     }
 
     /// Initialize the state of the UI
-    async fn init_state(&mut self, first: bool) -> Result<Workflow> {
-        // Run the independent initialization tasks in parallel for better performance
-        let workflow = self.api.read_workflow(self.cli.workflow.as_deref()).await?;
-
+    async fn init_state(&mut self, first: bool) -> Result<()> {
         let _ = self.handle_migrate_credentials().await;
 
         // Ensure we have a model selected before proceeding with initialization
@@ -2884,20 +2880,15 @@ impl<A: API + ConsoleWriter + 'static, F: Fn() -> A + Send + Sync> UI<A, F> {
         }
 
         if first {
-            // Create base workflow and trigger updates if this is the first initialization
-            let mut base_workflow = Workflow::default();
-            base_workflow.merge(workflow.clone());
             // For chat, we are trying to get active agent or setting it to default.
             // So for default values, `/info` doesn't show active provider, model, etc.
             // So my default, on new, we should set the active agent.
             self.api
                 .set_active_agent(active_agent.clone().unwrap_or_default())
                 .await?;
             // only call on_update if this is the first initialization
-            on_update(self.api.clone(), base_workflow.updates.as_ref()).await;
-            if !workflow.commands.is_empty() {
-                self.writeln_title(TitleFormat::error("forge.yaml commands are deprecated. Use .md files in forge/ (home) or .forge/ (project) instead"))?;
-            }
+            let env = self.api.environment();
+            on_update(self.api.clone(), env.updates.as_ref()).await;
         }
 
         // Execute independent operations in parallel to improve performance
@@ -2929,7 +2920,7 @@ impl<A: API + ConsoleWriter + 'static, F: Fn() -> A + Send + Sync> UI<A, F> {
         self.state = UIState::new(self.api.environment());
         self.update_model(operating_model);
 
-        Ok(workflow)
+        Ok(())
     }
 
     async fn on_message(&mut self, content: Option<String>) -> Result<()> {
diff --git a/crates/forge_repo/src/provider/provider_repo.rs b/crates/forge_repo/src/provider/provider_repo.rs
--- a/crates/forge_repo/src/provider/provider_repo.rs
+++ b/crates/forge_repo/src/provider/provider_repo.rs
@@ -127,7 +127,7 @@ impl<F: EnvironmentInfra + FileReaderInfra + FileWriterInfra + HttpInfra>
 {
     async fn get_custom_provider_configs(&self) -> anyhow::Result<Vec<ProviderConfig>> {
         let environment = self.infra.get_environment();
-        let provider_json_path = environment.base_path.join("provider.json");
+        let provider_json_path = environment.provider_config_path();
 
         let json_str = self.infra.read_utf8(&provider_json_path).await?;
         let configs = serde_json::from_str(&json_str)?;
diff --git a/crates/forge_services/src/command.rs b/crates/forge_services/src/command.rs
--- a/crates/forge_services/src/command.rs
+++ b/crates/forge_services/src/command.rs
@@ -63,7 +63,7 @@ impl<F: FileReaderInfra + FileWriterInfra + FileInfoInfra + EnvironmentInfra + D
         commands.extend(custom_commands);
 
         // Load custom commands from CWD
-        let dir = self.infra.get_environment().command_cwd_path();
+        let dir = self.infra.get_environment().command_path_local();
         let cwd_commands = self.init_command_dir(&dir).await?;
 
         commands.extend(cwd_commands);
diff --git a/crates/forge_services/src/forge_services.rs b/crates/forge_services/src/forge_services.rs
--- a/crates/forge_services/src/forge_services.rs
+++ b/crates/forge_services/src/forge_services.rs
@@ -28,7 +28,6 @@ use crate::tool_services::{
     ForgeFetch, ForgeFollowup, ForgeFsPatch, ForgeFsRead, ForgeFsRemove, ForgeFsSearch,
     ForgeFsUndo, ForgeFsWrite, ForgeImageRead, ForgePlanCreate, ForgeShell, ForgeSkillFetch,
 };
-use crate::workflow::ForgeWorkflowService;
 
 type McpService<F> = ForgeMcpService<ForgeMcpManager<F>, F, <F as McpServerInfra>::Client>;
 type AuthService<F> = ForgeAuthService<F>;
@@ -62,7 +61,6 @@ pub struct ForgeServices<
     conversation_service: Arc<ForgeConversationService<F>>,
     template_service: Arc<ForgeTemplateService<F>>,
     attachment_service: Arc<ForgeChatRequest<F>>,
-    workflow_service: Arc<ForgeWorkflowService<F>>,
     discovery_service: Arc<ForgeDiscoveryService<F>>,
     mcp_manager: Arc<ForgeMcpManager<F>>,
     file_create_service: Arc<ForgeFsWrite<F>>,
@@ -116,7 +114,6 @@ impl<
         let mcp_service = Arc::new(ForgeMcpService::new(mcp_manager.clone(), infra.clone()));
         let template_service = Arc::new(ForgeTemplateService::new(infra.clone()));
         let attachment_service = Arc::new(ForgeChatRequest::new(infra.clone()));
-        let workflow_service = Arc::new(ForgeWorkflowService::new(infra.clone()));
         let suggestion_service = Arc::new(ForgeDiscoveryService::new(infra.clone()));
         let conversation_service = Arc::new(ForgeConversationService::new(infra.clone()));
         let auth_service = Arc::new(ForgeAuthService::new(infra.clone()));
@@ -150,7 +147,6 @@ impl<
             conversation_service,
             attachment_service,
             template_service,
-            workflow_service,
             discovery_service: suggestion_service,
             mcp_manager,
             file_create_service,
@@ -220,7 +216,6 @@ impl<
     }
     type AttachmentService = ForgeChatRequest<F>;
     type CustomInstructionsService = ForgeCustomInstructionsService<F>;
-    type WorkflowService = ForgeWorkflowService<F>;
     type FileDiscoveryService = ForgeDiscoveryService<F>;
     type McpConfigManager = ForgeMcpManager<F>;
     type FsWriteService = ForgeFsWrite<F>;
@@ -263,10 +258,6 @@ impl<
         &self.custom_instructions_service
     }
 
-    fn workflow_service(&self) -> &Self::WorkflowService {
-        self.workflow_service.as_ref()
-    }
-
     fn file_discovery_service(&self) -> &Self::FileDiscoveryService {
         self.discovery_service.as_ref()
     }
diff --git a/crates/forge_services/src/instructions.rs b/crates/forge_services/src/instructions.rs
--- a/crates/forge_services/src/instructions.rs
+++ b/crates/forge_services/src/instructions.rs
@@ -24,7 +24,7 @@ impl<F: EnvironmentInfra + FileReaderInfra + CommandInfra> ForgeCustomInstructio
         let environment = self.infra.get_environment();
 
         // Base custom instructions
-        let base_agent_md = environment.base_path.join("AGENTS.md");
+        let base_agent_md = environment.global_agentsmd_path();
         if !paths.contains(&base_agent_md) {
             paths.push(base_agent_md);
         }
@@ -38,7 +38,7 @@ impl<F: EnvironmentInfra + FileReaderInfra + CommandInfra> ForgeCustomInstructio
         }
 
         // Working dir custom instructions
-        let cwd_agent_md = environment.cwd.join("AGENTS.md");
+        let cwd_agent_md = environment.local_agentsmd_path();
         if !paths.contains(&cwd_agent_md) {
             paths.push(cwd_agent_md);
         }
diff --git a/crates/forge_services/src/lib.rs b/crates/forge_services/src/lib.rs
--- a/crates/forge_services/src/lib.rs
+++ b/crates/forge_services/src/lib.rs
@@ -22,7 +22,6 @@ mod range;
 mod template;
 mod tool_services;
 mod utils;
-mod workflow;
 
 pub use app_config::*;
 pub use clipper::*;
diff --git a/crates/forge_services/src/tool_services/plan_create.rs b/crates/forge_services/src/tool_services/plan_create.rs
--- a/crates/forge_services/src/tool_services/plan_create.rs
+++ b/crates/forge_services/src/tool_services/plan_create.rs
@@ -42,7 +42,7 @@ impl<
         let filename = format!("{current_date}-{plan_name}-{version}.md");
 
         // Create the plans directory path (assuming current working directory)
-        let plans_dir = self.0.get_environment().cwd.join("plans");
+        let plans_dir = self.0.get_environment().plans_path();
         let file_path = plans_dir.join(&filename);
 
         // Validate the path is reasonable (even though it won't be absolute)
diff --git a/crates/forge_services/src/workflow.rs b/crates/forge_services/src/workflow.rs
deleted file mode 100644
--- a/crates/forge_services/src/workflow.rs
+++ /dev/null
@@ -1,186 +0,0 @@
-use std::path::{Path, PathBuf};
-use std::sync::Arc;
-
-use anyhow::Context;
-use forge_app::domain::Workflow;
-use forge_app::{FileReaderInfra, FileWriterInfra, WorkflowService};
-
-/// A workflow loader to load the workflow from the given path.
-/// It also resolves the internal paths specified in the workflow.
-pub struct ForgeWorkflowService<F> {
-    infra: Arc<F>,
-}
-
-impl<F> ForgeWorkflowService<F> {
-    pub fn new(infra: Arc<F>) -> Self {
-        Self { infra }
-    }
-}
-
-impl<F: FileWriterInfra + FileReaderInfra> ForgeWorkflowService<F> {
-    /// Find a forge.yaml config file by traversing parent directories.
-    /// Returns the path to the first found config file, or the original path if
-    /// none is found.
-    pub async fn resolve_path(&self, path: Option<PathBuf>) -> PathBuf {
-        let path = path.unwrap_or(PathBuf::from("."));
-        // If the path exists or this is an explicitly provided path, return it as is
-        if path.exists() || path.to_string_lossy() != "forge.yaml" {
-            return path.to_path_buf();
-        }
-
-        // Get the current directory as the starting point
-        let mut current_dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
-        let filename = path.file_name().unwrap_or_default();
-
-        // Start searching for the config in the current directory and its parents
-        loop {
-            let config_path = current_dir.join(filename);
-            if config_path.exists() {
-                return config_path;
-            }
-
-            // Try to go up one directory
-            match current_dir.parent() {
-                Some(parent) if parent != current_dir => {
-                    current_dir = parent.to_path_buf();
-                }
-                // Stop if we've reached the root directory or can't go further up
-                _ => break,
-            }
-        }
-
-        // If no config was found, return the original path
-        path.to_path_buf()
-    }
-
-    /// Loads the workflow from the given path.
-    /// If the path is just "forge.yaml", searches for it in parent directories.
-    /// If the file doesn't exist anywhere, returns a default workflow without
-    /// creating any file.
-    async fn read(&self, path: &Path) -> anyhow::Result<Workflow> {
-        // First, try to find the config file in parent directories if needed
-        let path = &self.resolve_path(Some(path.into())).await;
-
-        if !path.exists() {
-            // Return a default workflow without creating a file
-            Ok(Workflow::new())
-        } else {
-            let content = self.infra.read_utf8(path).await?;
-            let workflow: Workflow = serde_yml::from_str(&content)
-                .with_context(|| format!("Failed to parse workflow from {}", path.display()))?;
-            Ok(workflow)
-        }
-    }
-}
-
-#[async_trait::async_trait]
-impl<F: FileWriterInfra + FileReaderInfra> WorkflowService for ForgeWorkflowService<F> {
-    async fn resolve(&self, path: Option<PathBuf>) -> PathBuf {
-        self.resolve_path(path).await
-    }
-
-    async fn read_workflow(&self, path: Option<&Path>) -> anyhow::Result<Workflow> {
-        let path_to_use = path.unwrap_or_else(|| Path::new("forge.yaml"));
-        self.read(path_to_use).await
-    }
-}
-
-#[cfg(test)]
-mod tests {
-    use std::fs;
-
-    use tempfile::TempDir;
-
-    use super::*;
-
-    /// This testing strategy tests the core algorithm directly without
-    /// depending on complex directory structures.
-    #[test]
-    fn test_find_config_file_behavior() {
-        // Test 1: Return exact path if file exists
-        let temp_dir = TempDir::new().unwrap();
-        let config_path = temp_dir.path().join("forge.yaml");
-        fs::write(&config_path, "test content").unwrap();
-
-        let result = find_config_file_logic(Path::new("forge.yaml"), &config_path);
-        assert_eq!(result, config_path);
-
-        // Test 2: Return original path for non-forge.yaml files
-        let custom_path = PathBuf::from("custom-config.yaml");
-        let result =
-            find_config_file_logic(&custom_path, &temp_dir.path().join("file-that-exists.txt"));
-        assert_eq!(result, custom_path);
-
-        // Test 3: Return parent path when found
-        let parent_dir = temp_dir.path().join("parent");
-        let child_dir = parent_dir.join("child");
-        fs::create_dir_all(&child_dir).unwrap();
-
-        let parent_config = parent_dir.join("forge.yaml");
-        fs::write(&parent_config, "parent config").unwrap();
-
-        let result = find_config_file_logic(Path::new("forge.yaml"), &parent_config);
-        assert_eq!(result, parent_config);
-    }
-
-    // Pure function that tests the core logic without filesystem dependencies
-    fn find_config_file_logic(path: &Path, existing_config_path: &Path) -> PathBuf {
-        // If the path exists or this is an explicitly provided path, return it as is
-        if path.exists() || path.to_string_lossy() != "forge.yaml" {
-            return path.to_path_buf();
-        }
-
-        // Simulate checking directories by checking if the existing_config_path
-        // contains the filename we're looking for
-        if existing_config_path.file_name().unwrap_or_default()
-            == path.file_name().unwrap_or_default()
-        {
-            return existing_config_path.to_path_buf();
-        }
-
-        // If no config was found, return the original path
-        path.to_path_buf()
-    }
-
-    #[test]
-    fn test_find_config_not_found() {
-        // Create a temporary directory without a config
-        let temp_dir = TempDir::new().unwrap();
-        let test_dir = temp_dir.path().join("test_dir");
-        fs::create_dir_all(&test_dir).unwrap();
-
-        // Save the original directory and change to the test dir
-        let original_dir = std::env::current_dir().unwrap();
-
-        // Only create the directory structure, but don't create forge.yaml
-        // so the find function should return the original path
-        std::env::set_current_dir(&test_dir).unwrap();
-
-        // Test explicitly only the file existence check logic
-        assert!(!Path::new("forge.yaml").exists());
-
-        // Restore the original directory
-        std::env::set_current_dir(original_dir).unwrap();
-    }
-
-    #[test]
-    fn test_explicit_path_not_searched() {
-        // Create a test directory structure
-        let temp_dir = TempDir::new().unwrap();
-        let parent_dir = temp_dir.path().join("parent");
-        let child_dir = parent_dir.join("child");
-        fs::create_dir_all(&child_dir).unwrap();
-
-        // Create forge.yaml in the parent
-        fs::write(parent_dir.join("forge.yaml"), "# Test").unwrap();
-
-        // Simulate search with a non-forge.yaml path
-        let custom_path = PathBuf::from("custom-config.yaml");
-        let parent_config = parent_dir.join("forge.yaml");
-
-        let result = find_config_file_logic(&custom_path, &parent_config);
-
-        // Should return the custom path unchanged
-        assert_eq!(result, custom_path);
-    }
-}
diff --git a/forge.schema.json b/forge.schema.json
--- a/forge.schema.json
+++ b/forge.schema.json
@@ -1,18 +1,38 @@
 {
   "$schema": "https://json-schema.org/draft/2020-12/schema",
-  "title": "Workflow",
-  "description": "Configuration for a workflow that contains all settings\nrequired to initialize a workflow.",
+  "title": "ForgeConfig",
+  "description": "Top-level Forge configuration merged from all sources (defaults, file,\nenvironment).",
   "type": "object",
   "properties": {
-    "commands": {
-      "description": "Commands that can be used to interact with the workflow",
-      "type": "array",
-      "items": {
-        "$ref": "#/$defs/Command"
-      }
+    "auto_dump": {
+      "description": "Format for automatically creating a dump when a task is completed",
+      "anyOf": [
+        {
+          "$ref": "#/$defs/AutoDumpFormat"
+        },
+        {
+          "type": "null"
+        }
+      ]
+    },
+    "auto_open_dump": {
+      "description": "Whether to automatically open HTML dump files in the browser",
+      "type": "boolean"
+    },
+    "commit": {
+      "description": "Provider and model to use for commit message generation",
+      "anyOf": [
+        {
+          "$ref": "#/$defs/ModelConfig"
+        },
+        {
+          "type": "null"
+        }
+      ],
+      "default": null
     },
     "compact": {
-      "description": "Configuration for automatic context compaction for all agents\nIf specified, this will be applied to all agents in the workflow\nIf not specified, each agent's individual setting will be used",
+      "description": "Context compaction settings applied to all agents; falls back to each\nagent's individual setting when absent.",
       "anyOf": [
         {
           "$ref": "#/$defs/Compact"
@@ -22,91 +42,240 @@
         }
       ]
     },
-    "custom_rules": {
-      "description": "A set of custom rules that all agents should follow\nThese rules will be applied in addition to each agent's individual rules",
+    "custom_history_path": {
+      "description": "Custom history file path",
       "type": [
         "string",
         "null"
       ]
     },
-    "max_requests_per_turn": {
-      "description": "Maximum number of requests that can be made in a single turn",
+    "debug_requests": {
+      "description": "Path where debug request files should be written",
       "type": [
-        "integer",
+        "string",
         "null"
-      ],
-      "format": "uint",
-      "minimum": 0
+      ]
     },
-    "max_tokens": {
-      "description": "Maximum number of tokens the model can generate for all agents\n\nControls the maximum length of the model's response.\n- Lower values (e.g., 100) limit response length for concise outputs\n- Higher values (e.g., 4000) allow for longer, more detailed responses\n- Valid range is 1 to 100,000\n- If not specified, each agent's individual setting or the model\n  provider's default will be used",
+    "http": {
+      "description": "HTTP configuration",
       "anyOf": [
         {
-          "$ref": "#/$defs/MaxTokens"
+          "$ref": "#/$defs/HttpConfig"
         },
         {
           "type": "null"
         }
       ]
     },
+    "max_conversations": {
+      "description": "Maximum number of conversations to show in list",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_extensions": {
+      "description": "Maximum number of file extensions to include in the system prompt",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_fetch_chars": {
+      "description": "Maximum characters for fetch content",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_file_read_batch_size": {
+      "description": "Maximum number of files that can be read in a single batch operation",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_file_size_bytes": {
+      "description": "Maximum file size in bytes for operations",
+      "type": "integer",
+      "format": "uint64",
+      "minimum": 0
+    },
+    "max_image_size_bytes": {
+      "description": "Maximum image file size in bytes for binary read operations",
+      "type": "integer",
+      "format": "uint64",
+      "minimum": 0
+    },
+    "max_line_chars": {
+      "description": "Maximum characters per line for file read operations",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_parallel_file_reads": {
+      "description": "Maximum number of files read concurrently in parallel operations",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_read_lines": {
+      "description": "Maximum number of lines to read from a file",
+      "type": "integer",
+      "format": "uint64",
+      "minimum": 0
+    },
+    "max_requests_per_turn": {
+      "description": "Maximum number of requests that can be made in a single turn.",
+      "type": [
+        "integer",
+        "null"
+      ],
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_search_lines": {
+      "description": "The maximum number of lines returned for FSSearch",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_search_result_bytes": {
+      "description": "Maximum bytes allowed for search results",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_sem_search_results": {
+      "description": "Maximum number of results to return from initial vector search",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_stdout_line_chars": {
+      "description": "Maximum characters per line for shell output",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_stdout_prefix_lines": {
+      "description": "Maximum lines for shell output prefix",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_stdout_suffix_lines": {
+      "description": "Maximum lines for shell output suffix",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
+    },
+    "max_tokens": {
+      "description": "Maximum tokens the model may generate per response for all agents\n(1–100,000).",
+      "type": [
+        "integer",
+        "null"
+      ],
+      "format": "uint32",
+      "minimum": 0
+    },
     "max_tool_failure_per_turn": {
-      "description": "Maximum number of times a tool can fail before the orchestrator\nforces the completion.",
+      "description": "Maximum tool failures per turn before the orchestrator forces\ncompletion.",
       "type": [
         "integer",
         "null"
       ],
       "format": "uint",
       "minimum": 0
     },
-    "temperature": {
-      "description": "Temperature used for all agents\n\nTemperature controls the randomness in the model's output.\n- Lower values (e.g., 0.1) make responses more focused, deterministic,\n  and coherent\n- Higher values (e.g., 0.8) make responses more creative, diverse, and\n  exploratory\n- Valid range is 0.0 to 2.0\n- If not specified, each agent's individual setting or the model\n  provider's default will be used",
+    "model_cache_ttl_secs": {
+      "description": "TTL in seconds for the model API list cache",
+      "type": "integer",
+      "format": "uint64",
+      "minimum": 0
+    },
+    "restricted": {
+      "description": "Whether the application is running in restricted mode.\nWhen true, tool execution requires explicit permission grants.",
+      "type": "boolean"
+    },
+    "retry": {
+      "description": "Configuration for the retry mechanism",
       "anyOf": [
         {
-          "$ref": "#/$defs/Temperature"
+          "$ref": "#/$defs/RetryConfig"
         },
         {
           "type": "null"
         }
       ]
     },
-    "templates": {
-      "description": "Path pattern for custom template files (supports glob patterns)",
-      "type": [
-        "string",
-        "null"
-      ]
+    "sem_search_top_k": {
+      "description": "Top-k parameter for relevance filtering during semantic search",
+      "type": "integer",
+      "format": "uint",
+      "minimum": 0
     },
-    "tool_supported": {
-      "description": "Flag to enable/disable tool support for all agents in this workflow.\nIf not specified, each agent's individual setting will be used.\nDefault is false (tools disabled) when not specified.",
-      "type": [
-        "boolean",
-        "null"
-      ]
+    "services_url": {
+      "description": "URL for the indexing server",
+      "type": "string"
     },
-    "top_k": {
-      "description": "Top-k used for all agents\n\nControls the number of highest probability vocabulary tokens to keep.\n- Lower values (e.g., 10) make responses more focused\n- Higher values (e.g., 100) make responses more diverse\n- Valid range is 1 to 1000\n- If not specified, each agent's individual setting or the model\n  provider's default will be used",
+    "session": {
+      "description": "Default model and provider configuration used when not overridden by\nindividual agents.",
       "anyOf": [
         {
-          "$ref": "#/$defs/TopK"
+          "$ref": "#/$defs/ModelConfig"
         },
         {
           "type": "null"
         }
-      ]
+      ],
+      "default": null
     },
-    "top_p": {
-      "description": "Top-p (nucleus sampling) used for all agents\n\nControls the diversity of the model's output by considering only the\nmost probable tokens up to a cumulative probability threshold.\n- Lower values (e.g., 0.1) make responses more focused\n- Higher values (e.g., 0.9) make responses more diverse\n- Valid range is 0.0 to 1.0\n- If not specified, each agent's individual setting or the model\n  provider's default will be used",
+    "suggest": {
+      "description": "Provider and model to use for shell command suggestion generation",
       "anyOf": [
         {
-          "$ref": "#/$defs/TopP"
+          "$ref": "#/$defs/ModelConfig"
         },
         {
           "type": "null"
         }
-      ]
+      ],
+      "default": null
+    },
+    "temperature": {
+      "description": "Output randomness for all agents; lower values are deterministic, higher\nvalues are creative (0.0–2.0).",
+      "type": [
+        "number",
+        "null"
+      ],
+      "format": "float"
+    },
+    "tool_supported": {
+      "description": "Whether tool use is supported in the current environment.\nWhen false, tool calls are disabled regardless of agent configuration.",
+      "type": "boolean"
+    },
+    "tool_timeout_secs": {
+      "description": "Maximum execution time in seconds for a single tool call",
+      "type": "integer",
+      "format": "uint64",
+      "minimum": 0
+    },
+    "top_k": {
+      "description": "Top-k vocabulary cutoff for all agents; restricts sampling to the k\nhighest-probability tokens (1–1000).",
+      "type": [
+        "integer",
+        "null"
+      ],
+      "format": "uint32",
+      "minimum": 0
+    },
+    "top_p": {
+      "description": "Nucleus sampling threshold for all agents; limits token selection to the\ntop cumulative probability mass (0.0–1.0).",
+      "type": [
+        "number",
+        "null"
+      ],
+      "format": "float"
     },
     "updates": {
-      "description": "configurations that can be used to update forge",
+      "description": "Configuration for automatic forge updates",
       "anyOf": [
         {
           "$ref": "#/$defs/Update"
@@ -117,30 +286,48 @@
       ]
     }
   },
+  "required": [
+    "max_search_lines",
+    "max_search_result_bytes",
+    "max_fetch_chars",
+    "max_stdout_prefix_lines",
+    "max_stdout_suffix_lines",
+    "max_stdout_line_chars",
+    "max_line_chars",
+    "max_read_lines",
+    "max_file_read_batch_size",
+    "max_file_size_bytes",
+    "max_image_size_bytes",
+    "tool_timeout_secs",
+    "auto_open_dump",
+    "max_conversations",
+    "max_sem_search_results",
+    "sem_search_top_k",
+    "services_url",
+    "max_extensions",
+    "max_parallel_file_reads",
+    "model_cache_ttl_secs",
+    "restricted",
+    "tool_supported"
+  ],
   "$defs": {
-    "Command": {
-      "type": "object",
-      "properties": {
-        "description": {
-          "type": "string"
-        },
-        "name": {
-          "type": "string"
+    "AutoDumpFormat": {
+      "description": "The output format used when auto-dumping a conversation on task completion.",
+      "oneOf": [
+        {
+          "description": "Dump as a JSON file",
+          "type": "string",
+          "const": "json"
         },
-        "prompt": {
-          "type": [
-            "string",
-            "null"
-          ]
+        {
+          "description": "Dump as an HTML file",
+          "type": "string",
+          "const": "html"
         }
-      },
-      "required": [
-        "name",
-        "description"
       ]
     },
     "Compact": {
-      "description": "Configuration for automatic context compaction",
+      "description": "Configuration for automatic context compaction for all agents",
       "type": "object",
       "properties": {
         "eviction_window": {
@@ -188,13 +375,6 @@
           "default": 0,
           "minimum": 0
         },
-        "summary_tag": {
-          "description": "Optional tag name to extract content from when summarizing (e.g.,\n\"summary\")",
-          "type": [
-            "string",
-            "null"
-          ]
-        },
         "token_threshold": {
           "description": "Maximum number of tokens before triggering compaction",
           "type": [
@@ -215,38 +395,227 @@
         }
       }
     },
-    "MaxTokens": {
-      "description": "A newtype for max_tokens values with built-in validation\n\nMax tokens controls the maximum number of tokens the model can generate:\n- Lower values (e.g., 100) limit response length for concise outputs\n- Higher values (e.g., 4000) allow for longer, more detailed responses\n- Valid range is 1 to 100,000 (reasonable upper bound for most models)\n- If not specified, the model provider's default will be used",
-      "type": "integer",
-      "format": "uint32",
-      "minimum": 0
+    "HttpConfig": {
+      "description": "HTTP client configuration.",
+      "type": "object",
+      "properties": {
+        "accept_invalid_certs": {
+          "description": "Accept invalid certificates",
+          "type": "boolean"
+        },
+        "adaptive_window": {
+          "description": "Adaptive window sizing for improved flow control",
+          "type": "boolean"
+        },
+        "connect_timeout_secs": {
+          "type": "integer",
+          "format": "uint64",
+          "minimum": 0
+        },
+        "hickory": {
+          "type": "boolean"
+        },
+        "keep_alive_interval_secs": {
+          "description": "Keep-alive interval in seconds",
+          "type": [
+            "integer",
+            "null"
+          ],
+          "format": "uint64",
+          "minimum": 0
+        },
+        "keep_alive_timeout_secs": {
+          "description": "Keep-alive timeout in seconds",
+          "type": "integer",
+          "format": "uint64",
+          "minimum": 0
+        },
+        "keep_alive_while_idle": {
+          "description": "Keep-alive while connection is idle",
+          "type": "boolean"
+        },
+        "max_redirects": {
+          "type": "integer",
+          "format": "uint",
+          "minimum": 0
+        },
+        "max_tls_version": {
+          "description": "Maximum TLS protocol version to use",
+          "anyOf": [
+            {
+              "$ref": "#/$defs/TlsVersion"
+            },
+            {
+              "type": "null"
+            }
+          ]
+        },
+        "min_tls_version": {
+          "description": "Minimum TLS protocol version to use",
+          "anyOf": [
+            {
+              "$ref": "#/$defs/TlsVersion"
+            },
+            {
+              "type": "null"
+            }
+          ]
+        },
+        "pool_idle_timeout_secs": {
+          "type": "integer",
+          "format": "uint64",
+          "minimum": 0
+        },
+        "pool_max_idle_per_host": {
+          "type": "integer",
+          "format": "uint",
+          "minimum": 0
+        },
+        "read_timeout_secs": {
+          "type": "integer",
+          "format": "uint64",
+          "minimum": 0
+        },
+        "root_cert_paths": {
+          "description": "Paths to root certificate files",
+          "type": [
+            "array",
+            "null"
+          ],
+          "items": {
+            "type": "string"
+          }
+        },
+        "tls_backend": {
+          "$ref": "#/$defs/TlsBackend"
+        }
+      },
+      "required": [
+        "connect_timeout_secs",
+        "read_timeout_secs",
+        "pool_idle_timeout_secs",
+        "pool_max_idle_per_host",
+        "max_redirects",
+        "hickory",
+        "tls_backend",
+        "adaptive_window",
+        "keep_alive_timeout_secs",
+        "keep_alive_while_idle",
+        "accept_invalid_certs"
+      ]
     },
-    "Temperature": {
-      "description": "A newtype for temperature values with built-in validation\n\nTemperature controls the randomness in the model's output:\n- Lower values (e.g., 0.1) make responses more focused, deterministic, and\n  coherent\n- Higher values (e.g., 0.8) make responses more creative, diverse, and\n  exploratory\n- Valid range is 0.0 to 2.0",
-      "type": "number",
-      "format": "float"
+    "ModelConfig": {
+      "description": "Pairs a provider and model together for a specific operation.",
+      "type": "object",
+      "properties": {
+        "model_id": {
+          "description": "The model to use for this operation.",
+          "type": [
+            "string",
+            "null"
+          ]
+        },
+        "provider_id": {
+          "description": "The provider to use for this operation.",
+          "type": [
+            "string",
+            "null"
+          ]
+        }
+      }
     },
-    "TopK": {
-      "description": "A newtype for top_k values with built-in validation\n\nTop-k controls the number of highest probability vocabulary tokens to keep:\n- Lower values (e.g., 10) make responses more focused by considering only\n  the top K most likely tokens\n- Higher values (e.g., 100) make responses more diverse by considering more\n  token options\n- Valid range is 1 to 1000 (inclusive)",
-      "type": "integer",
-      "format": "uint32",
-      "minimum": 0
+    "RetryConfig": {
+      "description": "Configuration for retry mechanism.",
+      "type": "object",
+      "properties": {
+        "backoff_factor": {
+          "description": "Backoff multiplication factor for each retry attempt",
+          "type": "integer",
+          "format": "uint64",
+          "minimum": 0
+        },
+        "initial_backoff_ms": {
+          "description": "Initial backoff delay in milliseconds for retry operations",
+          "type": "integer",
+          "format": "uint64",
+          "minimum": 0
+        },
+        "max_attempts": {
+          "description": "Maximum number of retry attempts",
+          "type": "integer",
+          "format": "uint",
+          "minimum": 0
+        },
+        "max_delay_secs": {
+          "description": "Maximum delay between retries in seconds",
+          "type": [
+            "integer",
+            "null"
+          ],
+          "format": "uint64",
+          "minimum": 0
+        },
+        "min_delay_ms": {
+          "description": "Minimum delay in milliseconds between retry attempts",
+          "type": "integer",
+          "format": "uint64",
+          "minimum": 0
+        },
+        "status_codes": {
+          "description": "HTTP status codes that should trigger retries",
+          "type": "array",
+          "items": {
+            "type": "integer",
+            "format": "uint16",
+            "maximum": 65535,
+            "minimum": 0
+          }
+        },
+        "suppress_errors": {
+          "description": "Whether to suppress retry error logging and events",
+          "type": "boolean"
+        }
+      },
+      "required": [
+        "initial_backoff_ms",
+        "min_delay_ms",
+        "backoff_factor",
+        "max_attempts",
+        "status_codes",
+        "suppress_errors"
+      ]
     },
-    "TopP": {
-      "description": "A newtype for top_p values with built-in validation\n\nTop-p (nucleus sampling) controls the diversity of the model's output:\n- Lower values (e.g., 0.1) make responses more focused by considering only\n  the most probable tokens\n- Higher values (e.g., 0.9) make responses more diverse by considering a\n  broader range of tokens\n- Valid range is 0.0 to 1.0",
-      "type": "number",
-      "format": "float"
+    "TlsBackend": {
+      "description": "TLS backend option.",
+      "type": "string",
+      "enum": [
+        "default",
+        "rustls"
+      ]
+    },
+    "TlsVersion": {
+      "description": "TLS version enum for configuring TLS protocol versions.",
+      "type": "string",
+      "enum": [
+        "1.0",
+        "1.1",
+        "1.2",
+        "1.3"
+      ]
     },
     "Update": {
+      "description": "Configuration for automatic forge updates",
       "type": "object",
       "properties": {
         "auto_update": {
+          "description": "Whether to automatically install updates without prompting",
           "type": [
             "boolean",
             "null"
           ]
         },
         "frequency": {
+          "description": "How frequently forge checks for updates",
           "anyOf": [
             {
               "$ref": "#/$defs/UpdateFrequency"
@@ -259,6 +628,7 @@
       }
     },
     "UpdateFrequency": {
+      "description": "Frequency at which forge checks for updates",
       "type": "string",
       "enum": [
         "daily",
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
