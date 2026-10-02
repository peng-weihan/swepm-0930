#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/Cargo.lock b/Cargo.lock
--- a/Cargo.lock
+++ b/Cargo.lock
@@ -491,19 +491,19 @@ dependencies = [
 
 [[package]]
 name = "crabllm-core"
-version = "0.0.10"
+version = "0.0.11"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "a20c104f5a4026fe19151cbf283e0e56b93903c9053f8aa894bfb1d3cc0a856b"
+checksum = "09167c417c2a1033213e80708ed5262d8ef04b0924dbdedb54735a205ab1f13a"
 dependencies = [
  "serde",
  "serde_json",
 ]
 
 [[package]]
 name = "crabllm-provider"
-version = "0.0.10"
+version = "0.0.11"
 source = "registry+https://github.com/rust-lang/crates.io-index"
-checksum = "701145d0421186269876ace8ac586fdb48d4bbdcd2de0f2e36c60a2419bce64a"
+checksum = "7742ea7f39e02119ea6a5335a1bd1ac8190f565d17d0149ccc9a7d7f3a6b11c4"
 dependencies = [
  "bytes",
  "crabllm-core",
diff --git a/Cargo.toml b/Cargo.toml
--- a/Cargo.toml
+++ b/Cargo.toml
@@ -27,8 +27,8 @@ woutlook = { path = "apps/outlook", package = "crabtalk-outlook", version = "0.0
 wsearch = { path = "apps/search", package = "crabtalk-search", version = "0.0.16", default-features = false }
 
 # crabllm
-crabllm-core = "0.0.10"
-crabllm-provider = "0.0.10"
+crabllm-core = "0.0.11"
+crabllm-provider = "0.0.11"
 
 # bench
 criterion = { version = "0.5", features = ["html_reports"] }
diff --git a/crates/cli/src/cmd/attach.rs b/crates/cli/src/cmd/attach.rs
--- a/crates/cli/src/cmd/attach.rs
+++ b/crates/cli/src/cmd/attach.rs
@@ -1,12 +1,12 @@
 //! Attach to an agent via the interactive chat REPL.
 
-use crate::cmd::auth::PRESETS;
 use crate::repl::{ChatRepl, runner::Runner};
 use anyhow::Result;
 use clap::Args;
 use dialoguer::{Input, Password, Select, theme::ColorfulTheme};
 use std::path::Path;
 use toml_edit::{Array, DocumentMut, Item, Table, value};
+use wcore::config::PROVIDER_PRESETS;
 
 /// Attach to an agent and start an interactive chat REPL.
 #[derive(Args, Debug)]
@@ -31,28 +31,17 @@ impl Attach {
 /// Interactive provider setup for first-time daemon start.
 pub(crate) fn setup_provider(config_path: &Path) -> Result<()> {
     let theme = ColorfulTheme::default();
-    let preset_names: Vec<&str> = PRESETS.iter().map(|p| p.name).collect();
+    let preset_names: Vec<&str> = PROVIDER_PRESETS.iter().map(|p| p.name).collect();
 
     println!("\nNo providers configured. Let's set one up.\n");
     let idx = Select::with_theme(&theme)
         .with_prompt("Select a provider")
         .items(&preset_names)
         .default(0)
         .interact()?;
-    let preset = &PRESETS[idx];
+    let preset = &PROVIDER_PRESETS[idx];
 
-    // 1. Provider name — only for custom presets.
-    let provider_name = if preset.allows_custom_name() {
-        let name: String = Input::with_theme(&theme)
-            .with_prompt("Provider name (used as [provider.<name>] in config)")
-            .interact_text()?;
-        if name.is_empty() {
-            anyhow::bail!("provider name is required");
-        }
-        name
-    } else {
-        preset.name.to_string()
-    };
+    let provider_name = preset.name.to_string();
 
     // 2. API key — skipped for ollama.
     let api_key = if preset.name != "ollama" {
@@ -88,10 +77,10 @@ pub(crate) fn setup_provider(config_path: &Path) -> Result<()> {
         url
     };
 
-    let model: String = if let Some(default) = default_model_for(preset.name) {
+    let model: String = if !preset.default_model.is_empty() {
         Input::with_theme(&theme)
             .with_prompt("Model name")
-            .default(default.to_string())
+            .default(preset.default_model.to_string())
             .interact_text()?
     } else {
         let m: String = Input::with_theme(&theme)
@@ -130,7 +119,11 @@ pub(crate) fn setup_provider(config_path: &Path) -> Result<()> {
     if !base_url.is_empty() {
         entry.insert("base_url", value(base_url.as_str()));
     }
-    entry.insert("standard", value(preset.standard));
+    let kind_str = serde_json::to_value(preset.kind)
+        .ok()
+        .and_then(|v| v.as_str().map(String::from))
+        .unwrap_or_else(|| "openai".to_string());
+    entry.insert("kind", value(&kind_str));
     let mut models = Array::new();
     models.push(model.as_str());
     entry.insert("models", value(models));
@@ -140,14 +133,3 @@ pub(crate) fn setup_provider(config_path: &Path) -> Result<()> {
     println!("\nSaved to {}\n", config_path.display());
     Ok(())
 }
-
-fn default_model_for(provider: &str) -> Option<&str> {
-    match provider {
-        "anthropic" => Some("claude-sonnet-4-5-20250514"),
-        "openai" => Some("gpt-4o"),
-        "google" => Some("gemini-2.5-pro"),
-        "ollama" => Some("llama3"),
-        "azure" => Some("gpt-4o"),
-        _ => None,
-    }
-}
diff --git a/crates/cli/src/cmd/auth/mcps.rs b/crates/cli/src/cmd/auth/mcps.rs
--- a/crates/cli/src/cmd/auth/mcps.rs
+++ b/crates/cli/src/cmd/auth/mcps.rs
@@ -224,6 +224,7 @@ fn handle_add_mcp(key: crossterm::event::KeyEvent, state: &mut AuthState) {
                 env: Vec::new(),
                 url: None,
                 auth: false,
+                auto_restart: false,
                 source: McpSource::Local,
             });
             state.mcp_selected = state.mcps.len() - 1;
diff --git a/crates/cli/src/cmd/auth/mod.rs b/crates/cli/src/cmd/auth/mod.rs
--- a/crates/cli/src/cmd/auth/mod.rs
+++ b/crates/cli/src/cmd/auth/mod.rs
@@ -10,7 +10,8 @@ use ratatui::{
     text::{Line, Span},
     widgets::{Block, Borders, Paragraph, Tabs},
 };
-use toml_edit::{Array, DocumentMut, Item, Table, value};
+pub(crate) use wcore::config::{PROVIDER_PRESETS, ProviderPreset};
+use wcore::protocol::message::McpInfo;
 
 use mcps::{handle_mcps_key, render_mcps};
 use providers::{handle_providers_key, render_providers};
@@ -24,86 +25,68 @@ pub struct Auth {}
 
 impl Auth {
     pub async fn run(self) -> Result<()> {
-        tui::run_app(AuthState::load, render, handle_key)?;
-
-        // Reload daemon to pick up config changes (model, providers, MCPs).
-        if let Ok(mut runner) = crate::cmd::connect_default().await {
-            let _ = runner.reload().await;
+        let mut runner = crate::cmd::connect_default()
+            .await
+            .context("daemon must be running for auth — run 'crabtalk' first")?;
+
+        // Load via protocol.
+        let provider_infos = runner.list_providers().await?;
+        let config_json = runner.get_config().await?;
+        let mcp_infos = runner.list_mcps().await?;
+        let initial_names: Vec<String> = provider_infos.iter().map(|p| p.name.clone()).collect();
+
+        let active_model = serde_json::from_str::<serde_json::Value>(&config_json)
+            .ok()
+            .and_then(|v| {
+                v.get("system")?
+                    .get("crab")?
+                    .get("model")?
+                    .as_str()
+                    .map(String::from)
+            })
+            .unwrap_or_default();
+
+        let state = tui::run_app_with_state(
+            || AuthState::from_protocol(provider_infos, active_model, mcp_infos),
+            render,
+            handle_key,
+        )?;
+
+        if !state.needs_save {
+            return Ok(());
         }
-        Ok(())
-    }
-}
 
-// ── Presets ──────────────────────────────────────────────────────────
+        // Save via protocol.
+        runner.set_active_model(state.active_model.clone()).await?;
 
-pub(crate) struct Preset {
-    pub(crate) name: &'static str,
-    pub(crate) base_url: &'static str,
-    pub(crate) standard: &'static str,
-    /// URL hardcoded in crabllm — shown read-only, not saved to config.
-    pub(crate) fixed_base_url: &'static str,
-}
+        // Delete removed providers.
+        let final_names: Vec<String> = state.providers.iter().map(|p| p.name.clone()).collect();
+        for name in &initial_names {
+            if !final_names.contains(name) {
+                let _ = runner.delete_provider(name.clone()).await;
+            }
+        }
 
-impl Preset {
-    /// Whether this preset allows user-defined provider names.
-    pub(crate) fn allows_custom_name(&self) -> bool {
-        self.name == "custom"
-    }
+        // Set all current providers.
+        for p in &state.providers {
+            let def = p.to_provider_def();
+            let json = serde_json::to_string(&def).context("failed to serialize provider")?;
+            runner.set_provider(p.name.clone(), json).await?;
+        }
 
-    /// Whether the base_url field is editable for this preset.
-    pub(crate) fn base_url_editable(&self) -> bool {
-        self.fixed_base_url.is_empty()
-    }
+        // Save local MCPs.
+        let local_mcps: Vec<McpInfo> = state
+            .mcps
+            .iter()
+            .filter(|m| m.source == McpSource::Local)
+            .map(McpData::to_mcp_info)
+            .collect();
+        runner.set_local_mcps(local_mcps).await?;
 
-    /// The display URL — fixed if hardcoded, otherwise whatever the user set.
-    pub(crate) fn display_url(&self) -> &str {
-        if self.fixed_base_url.is_empty() {
-            self.base_url
-        } else {
-            self.fixed_base_url
-        }
+        Ok(())
     }
 }
 
-pub(crate) const PRESETS: &[Preset] = &[
-    Preset {
-        name: "anthropic",
-        base_url: "",
-        standard: "anthropic",
-        fixed_base_url: "https://api.anthropic.com/v1",
-    },
-    Preset {
-        name: "openai",
-        base_url: "https://api.openai.com/v1",
-        standard: "openai_compat",
-        fixed_base_url: "",
-    },
-    Preset {
-        name: "google",
-        base_url: "",
-        standard: "google",
-        fixed_base_url: "https://generativelanguage.googleapis.com/v1beta",
-    },
-    Preset {
-        name: "ollama",
-        base_url: "http://localhost:11434/v1",
-        standard: "ollama",
-        fixed_base_url: "",
-    },
-    Preset {
-        name: "azure",
-        base_url: "",
-        standard: "azure",
-        fixed_base_url: "",
-    },
-    Preset {
-        name: "custom",
-        base_url: "",
-        standard: "openai_compat",
-        fixed_base_url: "",
-    },
-];
-
 // ── Tabs ─────────────────────────────────────────────────────────────
 
 #[derive(Clone, Copy, PartialEq, Eq)]
@@ -131,12 +114,9 @@ pub(crate) struct ProviderData {
 }
 
 impl ProviderData {
-    /// Look up the preset for this provider by matching standard.
-    /// Returns None for providers with no matching preset (custom names).
-    pub(crate) fn preset(&self) -> Option<&'static Preset> {
-        PRESETS
-            .iter()
-            .find(|p| p.name == self.name && p.standard == self.standard)
+    /// Look up the preset for this provider by matching name.
+    pub(crate) fn preset(&self) -> Option<&'static ProviderPreset> {
+        PROVIDER_PRESETS.iter().find(|p| p.name == self.name)
     }
 
     /// Whether the base_url field is editable (not hardcoded by crabllm).
@@ -153,6 +133,28 @@ impl ProviderData {
         }
         &self.base_url
     }
+
+    /// Build a ProviderDef for serialization.
+    pub(crate) fn to_provider_def(&self) -> wcore::ProviderDef {
+        let kind: wcore::ApiStandard =
+            serde_json::from_value(serde_json::Value::String(self.standard.clone()))
+                .unwrap_or_default();
+        wcore::ProviderDef {
+            kind,
+            api_key: if self.api_key.is_empty() {
+                None
+            } else {
+                Some(self.api_key.clone())
+            },
+            base_url: if self.base_url.is_empty() {
+                None
+            } else {
+                Some(self.base_url.clone())
+            },
+            models: self.models.clone(),
+            ..Default::default()
+        }
+    }
 }
 
 pub(crate) const PROVIDER_FIELDS: &[&str] = &["api_key", "base_url", "standard"];
@@ -164,9 +166,25 @@ pub(crate) struct McpData {
     pub(crate) env: Vec<(String, String)>,
     pub(crate) url: Option<String>,
     pub(crate) auth: bool,
+    pub(crate) auto_restart: bool,
     pub(crate) source: McpSource,
 }
 
+impl McpData {
+    pub(crate) fn to_mcp_info(&self) -> McpInfo {
+        McpInfo {
+            name: self.name.clone(),
+            command: self.command.clone(),
+            args: self.args.clone(),
+            env: self.env.iter().cloned().collect(),
+            url: self.url.clone().unwrap_or_default(),
+            auth: self.auth,
+            auto_restart: self.auto_restart,
+            source: String::new(), // always local when saving
+        }
+    }
+}
+
 #[derive(Clone, PartialEq, Eq)]
 pub(crate) enum McpSource {
     Local,
@@ -206,170 +224,52 @@ pub(crate) struct AuthState {
     pub(crate) mcp_add_step: usize, // 0=name, 1=transport, 2=command/url, 3=args
     pub(crate) mcp_add_http: bool,  // true when adding an HTTP MCP
     // Shared.
+    pub(crate) needs_save: bool,
     pub(crate) status: String,
 }
 
 impl AuthState {
-    fn load() -> Result<Self> {
-        let config_path = wcore::paths::CONFIG_DIR.join(wcore::paths::CONFIG_FILE);
+    fn from_protocol(
+        provider_infos: Vec<wcore::protocol::message::ProviderInfo>,
+        active_model: String,
+        mcp_infos: Vec<McpInfo>,
+    ) -> Result<Self> {
         let mut providers = Vec::new();
-        let mut active_model = String::new();
-        let mut mcps = Vec::new();
-
-        if config_path.exists() {
-            let content = std::fs::read_to_string(&config_path)
-                .with_context(|| format!("cannot read {}", config_path.display()))?;
-            let doc: DocumentMut = content
-                .parse()
-                .with_context(|| format!("invalid TOML in {}", config_path.display()))?;
-
-            if let Some(system) = doc.get("system").and_then(|s| s.as_table())
-                && let Some(crab) = system.get("crab").and_then(|w| w.as_table())
-                && let Some(m) = crab.get("model").and_then(|v| v.as_str())
-            {
-                active_model = m.to_string();
-            }
-
-            if let Some(provider_table) = doc.get("provider").and_then(|p| p.as_table()) {
-                for (name, item) in provider_table.iter() {
-                    let Some(tbl) = item.as_table() else {
-                        continue;
-                    };
-                    let api_key = tbl
-                        .get("api_key")
-                        .and_then(|v| v.as_str())
-                        .unwrap_or("")
-                        .to_string();
-                    let base_url = tbl
-                        .get("base_url")
-                        .and_then(|v| v.as_str())
-                        .unwrap_or("")
-                        .to_string();
-                    let standard = tbl
-                        .get("standard")
-                        .and_then(|v| v.as_str())
-                        .unwrap_or("openai")
-                        .to_string();
-                    let mut models = Vec::new();
-                    if let Some(arr) = tbl.get("models").and_then(|v| v.as_array()) {
-                        for m in arr.iter() {
-                            if let Some(s) = m.as_str() {
-                                models.push(s.to_string());
-                            }
-                        }
-                    }
-                    providers.push(ProviderData {
-                        name: name.to_string(),
-                        api_key,
-                        base_url,
-                        standard,
-                        models,
-                    });
-                }
-            }
-        }
-
-        // Load MCPs from local/CrabTalk.toml.
-        let manifest_path = wcore::paths::CONFIG_DIR
-            .join(wcore::paths::LOCAL_DIR)
-            .join("CrabTalk.toml");
-        if manifest_path.exists() {
-            let manifest_content = std::fs::read_to_string(&manifest_path)
-                .with_context(|| format!("cannot read {}", manifest_path.display()))?;
-            let manifest_doc: DocumentMut = manifest_content
-                .parse()
-                .with_context(|| format!("invalid TOML in {}", manifest_path.display()))?;
-
-            if let Some(mcps_table) = manifest_doc.get("mcps").and_then(|m| m.as_table()) {
-                for (name, item) in mcps_table.iter() {
-                    let Some(tbl) = item.as_table() else {
-                        continue;
-                    };
-                    let command = tbl
-                        .get("command")
-                        .and_then(|v| v.as_str())
-                        .unwrap_or("")
-                        .to_string();
-                    let mut args = Vec::new();
-                    if let Some(arr) = tbl.get("args").and_then(|v| v.as_array()) {
-                        for a in arr.iter() {
-                            if let Some(s) = a.as_str() {
-                                args.push(s.to_string());
-                            }
-                        }
-                    }
-                    let mut env = Vec::new();
-                    if let Some(env_tbl) = tbl.get("env").and_then(|e| e.as_table()) {
-                        for (k, v) in env_tbl.iter() {
-                            let val = v.as_str().unwrap_or("").to_string();
-                            env.push((k.to_string(), val));
-                        }
-                    }
-                    let url = tbl.get("url").and_then(|v| v.as_str()).map(String::from);
-                    let auth = tbl.get("auth").and_then(|v| v.as_bool()).unwrap_or(false);
-                    mcps.push(McpData {
-                        name: name.to_string(),
-                        command,
-                        args,
-                        env,
-                        url,
-                        auth,
-                        source: McpSource::Local,
-                    });
-                }
+        for p in provider_infos {
+            if p.config.is_empty() {
+                continue;
             }
+            let def: wcore::ProviderDef = serde_json::from_str(&p.config)
+                .with_context(|| format!("invalid provider config for '{}'", p.name))?;
+            providers.push(ProviderData {
+                name: p.name,
+                api_key: def.api_key.unwrap_or_default(),
+                base_url: def.base_url.unwrap_or_default(),
+                standard: serde_json::to_value(def.kind)
+                    .ok()
+                    .and_then(|v| v.as_str().map(String::from))
+                    .unwrap_or_else(|| "openai".to_string()),
+                models: def.models,
+            });
         }
 
-        // Load hub-installed MCPs (read-only).
-        let packages_dir = wcore::paths::CONFIG_DIR.join(wcore::paths::PACKAGES_DIR);
-        if let Ok(scopes) = std::fs::read_dir(&packages_dir) {
-            for scope_entry in scopes.flatten() {
-                let scope_path = scope_entry.path();
-                let toml_files: Vec<_> = if scope_path.is_dir() {
-                    std::fs::read_dir(&scope_path)
-                        .into_iter()
-                        .flatten()
-                        .flatten()
-                        .map(|e| e.path())
-                        .filter(|p| p.extension().is_some_and(|e| e == "toml"))
-                        .collect()
-                } else if scope_path.extension().is_some_and(|e| e == "toml") {
-                    vec![scope_path.clone()]
+        let mcps = mcp_infos
+            .into_iter()
+            .map(|m| McpData {
+                name: m.name,
+                command: m.command,
+                args: m.args,
+                env: m.env.into_iter().collect(),
+                url: if m.url.is_empty() { None } else { Some(m.url) },
+                auth: m.auth,
+                auto_restart: m.auto_restart,
+                source: if m.source.is_empty() || m.source == "local" {
+                    McpSource::Local
                 } else {
-                    continue;
-                };
-
-                for toml_path in toml_files {
-                    let pkg_id = toml_path
-                        .strip_prefix(&packages_dir)
-                        .unwrap_or(&toml_path)
-                        .with_extension("")
-                        .to_string_lossy()
-                        .into_owned();
-                    if let Ok(Some(manifest)) = wcore::ManifestConfig::load(&toml_path) {
-                        for (name, cfg) in &manifest.mcps {
-                            // Skip if already loaded as local (local wins).
-                            if mcps.iter().any(|m| m.name == *name) {
-                                continue;
-                            }
-                            mcps.push(McpData {
-                                name: name.clone(),
-                                command: cfg.command.clone(),
-                                args: cfg.args.clone(),
-                                env: cfg
-                                    .env
-                                    .iter()
-                                    .map(|(k, v)| (k.clone(), v.clone()))
-                                    .collect(),
-                                url: cfg.url.clone(),
-                                auth: cfg.auth,
-                                source: McpSource::Hub(pkg_id.clone()),
-                            });
-                        }
-                    }
-                }
-            }
-        }
+                    McpSource::Hub(m.source)
+                },
+            })
+            .collect();
 
         Ok(Self {
             tab: Tab::Providers,
@@ -386,134 +286,14 @@ impl AuthState {
             mcp_env_selected: 0,
             mcp_add_step: 0,
             mcp_add_http: false,
+            needs_save: false,
             status: String::from("Ready"),
         })
     }
 
-    fn save(&mut self) -> Result<()> {
-        let config_path = wcore::paths::CONFIG_DIR.join(wcore::paths::CONFIG_FILE);
-        std::fs::create_dir_all(&*wcore::paths::CONFIG_DIR)
-            .with_context(|| format!("cannot create {}", wcore::paths::CONFIG_DIR.display()))?;
-
-        let content = if config_path.exists() {
-            std::fs::read_to_string(&config_path)
-                .with_context(|| format!("cannot read {}", config_path.display()))?
-        } else {
-            String::new()
-        };
-
-        let mut doc: DocumentMut = content
-            .parse()
-            .with_context(|| format!("invalid TOML in {}", config_path.display()))?;
-
-        // [system.crab].model
-        if !self.active_model.is_empty() {
-            if doc.get("system").is_none() {
-                doc.insert("system", Item::Table(Table::new()));
-            }
-            if let Some(system) = doc.get_mut("system").and_then(|s| s.as_table_mut()) {
-                if system.get("crab").is_none() {
-                    system.insert("crab", Item::Table(Table::new()));
-                }
-                if let Some(crab) = system.get_mut("crab").and_then(|w| w.as_table_mut()) {
-                    crab.insert("model", value(&self.active_model));
-                }
-            }
-        }
-
-        // [provider.*]
-        doc.remove("provider");
-        if !self.providers.is_empty() {
-            let mut provider_table = Table::new();
-            for p in &self.providers {
-                let mut tbl = Table::new();
-                if !p.api_key.is_empty() {
-                    tbl.insert("api_key", value(&p.api_key));
-                }
-                if !p.base_url.is_empty() {
-                    tbl.insert("base_url", value(&p.base_url));
-                }
-                tbl.insert("standard", value(&p.standard));
-                if !p.models.is_empty() {
-                    let mut arr = Array::new();
-                    for m in &p.models {
-                        arr.push(m.as_str());
-                    }
-                    tbl.insert("models", Item::Value(arr.into()));
-                }
-                provider_table.insert(&p.name, Item::Table(tbl));
-            }
-            doc.insert("provider", Item::Table(provider_table));
-        }
-
-        // Remove legacy sections from config.toml if present.
-        doc.remove("mcps");
-
-        std::fs::write(&config_path, doc.to_string())
-            .with_context(|| format!("failed to write {}", config_path.display()))?;
-
-        // Save MCPs to local/CrabTalk.toml.
-        let manifest_path = wcore::paths::CONFIG_DIR
-            .join(wcore::paths::LOCAL_DIR)
-            .join("CrabTalk.toml");
-        let local_dir = wcore::paths::CONFIG_DIR.join(wcore::paths::LOCAL_DIR);
-        std::fs::create_dir_all(&local_dir)
-            .with_context(|| format!("cannot create {}", local_dir.display()))?;
-
-        let manifest_content = if manifest_path.exists() {
-            std::fs::read_to_string(&manifest_path)
-                .with_context(|| format!("cannot read {}", manifest_path.display()))?
-        } else {
-            String::new()
-        };
-        let mut manifest_doc: DocumentMut = manifest_content
-            .parse()
-            .with_context(|| format!("invalid TOML in {}", manifest_path.display()))?;
-
-        manifest_doc.remove("mcps");
-        let local_mcps: Vec<_> = self
-            .mcps
-            .iter()
-            .filter(|m| m.source == McpSource::Local)
-            .collect();
-        if !local_mcps.is_empty() {
-            let mut mcps_table = Table::new();
-            for mcp in local_mcps {
-                let mut tbl = Table::new();
-                if let Some(ref url) = mcp.url {
-                    tbl.insert("url", value(url));
-                } else {
-                    if !mcp.command.is_empty() {
-                        tbl.insert("command", value(&mcp.command));
-                    }
-                    if !mcp.args.is_empty() {
-                        let mut arr = Array::new();
-                        for a in &mcp.args {
-                            arr.push(a.as_str());
-                        }
-                        tbl.insert("args", Item::Value(arr.into()));
-                    }
-                }
-                if mcp.auth {
-                    tbl.insert("auth", value(true));
-                }
-                if !mcp.env.is_empty() {
-                    let mut env_tbl = Table::new();
-                    for (k, v) in &mcp.env {
-                        env_tbl.insert(k, value(v));
-                    }
-                    tbl.insert("env", Item::Table(env_tbl));
-                }
-                mcps_table.insert(&mcp.name, Item::Table(tbl));
-            }
-            manifest_doc.insert("mcps", Item::Table(mcps_table));
-        }
-
-        std::fs::write(&manifest_path, manifest_doc.to_string())
-            .with_context(|| format!("failed to write {}", manifest_path.display()))?;
-
+    fn mark_saved(&mut self) {
+        self.needs_save = true;
         self.status = String::from("Saved!");
-        Ok(())
     }
 
     // ── Provider tree helpers ────────────────────────────────────────
@@ -560,12 +340,16 @@ impl AuthState {
         }
     }
 
-    pub(crate) fn add_preset(&mut self, preset: &Preset, name: Option<&str>) {
+    pub(crate) fn add_preset(&mut self, preset: &ProviderPreset, name: Option<&str>) {
+        let kind_str = serde_json::to_value(preset.kind)
+            .ok()
+            .and_then(|v| v.as_str().map(String::from))
+            .unwrap_or_else(|| "openai".to_string());
         self.providers.push(ProviderData {
             name: name.unwrap_or(preset.name).to_string(),
             api_key: String::new(),
             base_url: preset.base_url.to_string(),
-            standard: preset.standard.to_string(),
+            standard: kind_str,
             models: Vec::new(),
         });
         let new_idx = self.tree_len().saturating_sub(1);
@@ -580,9 +364,7 @@ fn handle_key(
     state: &mut AuthState,
 ) -> Result<Option<Result<()>>> {
     if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('s') {
-        if let Err(e) = state.save() {
-            state.status = format!("Error: {e}");
-        }
+        state.mark_saved();
         return Ok(None);
     }
 
diff --git a/crates/cli/src/cmd/auth/providers.rs b/crates/cli/src/cmd/auth/providers.rs
--- a/crates/cli/src/cmd/auth/providers.rs
+++ b/crates/cli/src/cmd/auth/providers.rs
@@ -1,6 +1,6 @@
 use crate::{
     cmd::auth::{
-        AuthState, Focus, PRESETS, PROVIDER_FIELDS, ProviderData, Tab, TreeItem,
+        AuthState, Focus, PROVIDER_FIELDS, PROVIDER_PRESETS, ProviderData, Tab, TreeItem,
         commit_provider_edit,
     },
     tui::{border_dim, border_focused, char_to_byte, handle_text_input, mask_token},
@@ -266,24 +266,29 @@ fn handle_preset(key: crossterm::event::KeyEvent, state: &mut AuthState) {
             state.preset_idx = state.preset_idx.saturating_sub(1);
         }
         KeyCode::Down | KeyCode::Char('j') => {
-            if state.preset_idx < PRESETS.len() - 1 {
+            if state.preset_idx < PROVIDER_PRESETS.len() - 1 {
                 state.preset_idx += 1;
             }
         }
         KeyCode::Enter => {
-            let preset = &PRESETS[state.preset_idx];
-            if preset.allows_custom_name() {
-                state.edit_buf.clear();
-                state.cursor = 0;
+            let preset = &PROVIDER_PRESETS[state.preset_idx];
+            if state.providers.iter().any(|p| p.name == preset.name) {
+                // Name taken — prompt for a custom name.
+                state.edit_buf = preset.name.to_string();
+                state.cursor = state.edit_buf.len();
                 state.focus = Focus::NamingProvider;
-            } else if state.providers.iter().any(|p| p.name == preset.name) {
-                state.status = format!("Provider '{}' already exists", preset.name);
             } else {
                 state.add_preset(preset, None);
                 state.status = format!("Added provider: {}", preset.name);
                 state.focus = Focus::List;
             }
         }
+        // Custom name for any preset.
+        KeyCode::Char('n') => {
+            state.edit_buf.clear();
+            state.cursor = 0;
+            state.focus = Focus::NamingProvider;
+        }
         _ => {}
     }
 }
@@ -303,7 +308,7 @@ fn handle_naming_provider(key: crossterm::event::KeyEvent, state: &mut AuthState
                 state.status = format!("Provider '{}' already exists", name);
                 return;
             }
-            let preset = &PRESETS[state.preset_idx];
+            let preset = &PROVIDER_PRESETS[state.preset_idx];
             state.add_preset(preset, Some(&name));
             state.status = format!("Added provider: {}", name);
             state.focus = Focus::List;
@@ -565,7 +570,7 @@ fn render_presets(frame: &mut Frame, state: &AuthState, area: Rect) {
         .borders(Borders::ALL)
         .border_style(border_focused());
 
-    let lines: Vec<Line> = PRESETS
+    let lines: Vec<Line> = PROVIDER_PRESETS
         .iter()
         .enumerate()
         .map(|(i, preset)| {
@@ -577,7 +582,11 @@ fn render_presets(frame: &mut Frame, state: &AuthState, area: Rect) {
             } else {
                 Style::default().fg(Color::White)
             };
-            let url = preset.display_url();
+            let url = if preset.fixed_base_url.is_empty() {
+                preset.base_url
+            } else {
+                preset.fixed_base_url
+            };
             let detail = if url.is_empty() {
                 String::new()
             } else {
diff --git a/crates/cli/src/cmd/console/mod.rs b/crates/cli/src/cmd/console/mod.rs
--- a/crates/cli/src/cmd/console/mod.rs
+++ b/crates/cli/src/cmd/console/mod.rs
@@ -49,10 +49,11 @@ impl Console {
 
         let mut terminal = tui::setup()?;
 
-        // Fetch initial daemon session data.
+        // Fetch initial data from daemon.
         let daemon_sessions = runner.list_sessions().await.unwrap_or_default();
+        let conversations = runner.list_conversations("", "").await.unwrap_or_default();
         let mut session_view = SessionView::default();
-        session_view.refresh_identities(&daemon_sessions);
+        session_view.refresh_identities(&conversations, &daemon_sessions);
 
         let mut state = ConsoleState {
             status: String::from("Ready"),
@@ -175,17 +176,38 @@ async fn handle_sessions_key(
             if let Some(path) = state.session_view.selected_file() {
                 return Some(path);
             }
-            // In identity view: drill down.
-            let timeout = std::time::Duration::from_millis(500);
-            if let Ok(Ok(sessions)) =
-                tokio::time::timeout(timeout, state.runner.list_sessions()).await
-            {
-                state.daemon_sessions = sessions;
+            // In identity view: drill down — fetch conversations for the selected identity.
+            if let Some((agent, sender)) = state.session_view.selected_identity() {
+                let agent = agent.to_string();
+                let sender = sender.to_string();
+                let timeout = std::time::Duration::from_millis(500);
+                if let Ok(Ok(sessions)) =
+                    tokio::time::timeout(timeout, state.runner.list_sessions()).await
+                {
+                    state.daemon_sessions = sessions;
+                }
+                let conversations =
+                    tokio::time::timeout(timeout, state.runner.list_conversations(&agent, &sender))
+                        .await
+                        .ok()
+                        .and_then(|r| r.ok())
+                        .unwrap_or_default();
+                state
+                    .session_view
+                    .enter(&conversations, &state.daemon_sessions);
             }
-            state.session_view.enter(&state.daemon_sessions);
         }
         KeyCode::Esc => {
-            state.session_view.back(&state.daemon_sessions);
+            let timeout = std::time::Duration::from_millis(500);
+            let conversations =
+                tokio::time::timeout(timeout, state.runner.list_conversations("", ""))
+                    .await
+                    .ok()
+                    .and_then(|r| r.ok())
+                    .unwrap_or_default();
+            state
+                .session_view
+                .back(&conversations, &state.daemon_sessions);
         }
         KeyCode::Char('r') => {
             let timeout = std::time::Duration::from_millis(500);
@@ -194,9 +216,15 @@ async fn handle_sessions_key(
             {
                 state.daemon_sessions = sessions;
             }
+            let conversations =
+                tokio::time::timeout(timeout, state.runner.list_conversations("", ""))
+                    .await
+                    .ok()
+                    .and_then(|r| r.ok())
+                    .unwrap_or_default();
             state
                 .session_view
-                .refresh_identities(&state.daemon_sessions);
+                .refresh_identities(&conversations, &state.daemon_sessions);
             state.status = String::from("Refreshed");
         }
         _ => {}
diff --git a/crates/cli/src/cmd/console/sessions.rs b/crates/cli/src/cmd/console/sessions.rs
--- a/crates/cli/src/cmd/console/sessions.rs
+++ b/crates/cli/src/cmd/console/sessions.rs
@@ -8,7 +8,8 @@ use ratatui::{
     text::{Line, Span},
     widgets::{Block, Borders, Paragraph},
 };
-use std::{collections::BTreeMap, fs, path::Path};
+use std::collections::BTreeMap;
+use wcore::protocol::message::{ConversationInfo, SessionInfo};
 
 /// Which view the Sessions tab is showing.
 #[derive(Clone)]
@@ -49,40 +50,72 @@ pub(super) struct IdentityEntry {
 #[derive(Clone)]
 pub(super) struct ConversationEntry {
     pub date: String,
-    #[allow(dead_code)]
-    pub seq: u32,
     pub title: String,
     /// File path for this conversation (used for resume).
-    #[allow(dead_code)]
-    pub file_path: std::path::PathBuf,
-    /// Message count (from disk line count or daemon).
+    pub file_path: String,
+    /// Message count (from daemon).
     pub message_count: Option<u64>,
-    /// Uptime in seconds (from disk meta or daemon).
+    /// Uptime in seconds (from daemon).
     pub alive_secs: Option<u64>,
     /// Daemon session ID (for correlating with live events).
     pub session_id: Option<u64>,
 }
 
 impl SessionView {
-    /// Refresh identity list from disk, merged with daemon live data.
+    /// Refresh identity list from daemon data.
     pub fn refresh_identities(
         &mut self,
-        daemon_sessions: &[wcore::protocol::message::SessionInfo],
+        conversations: &[ConversationInfo],
+        daemon_sessions: &[SessionInfo],
     ) {
-        let mut entries = scan_identities(&wcore::paths::SESSIONS_DIR);
+        let mut data: BTreeMap<(String, String), (usize, String, u64, u64)> = BTreeMap::new();
 
-        // Merge daemon live data into identity entries.
-        for entry in &mut entries {
-            for ds in daemon_sessions {
-                if ds.agent == entry.agent && ds.created_by == entry.sender {
-                    entry.message_count += ds.message_count;
-                    entry.alive_secs = entry.alive_secs.max(ds.alive_secs);
-                    // Session is loaded in memory — it's active today.
-                    entry.last_active = "Today".to_string();
-                }
+        for c in conversations {
+            let key = (c.agent.clone(), c.sender.clone());
+            let entry = data.entry(key).or_insert((0, String::new(), 0, 0));
+            entry.0 += 1;
+            // Keep the most recent date label.
+            if entry.1.is_empty()
+                || c.date == "Today"
+                || (c.date == "Yesterday" && entry.1 != "Today")
+            {
+                entry.1.clone_from(&c.date);
             }
+            entry.2 += c.alive_secs;
+            entry.3 += c.message_count;
         }
 
+        // Merge live daemon session data.
+        for ds in daemon_sessions {
+            let key = (ds.agent.clone(), ds.created_by.clone());
+            let entry = data.entry(key).or_insert((0, String::new(), 0, 0));
+            entry.1 = "Today".to_string();
+            entry.2 = entry.2.max(ds.alive_secs);
+            entry.3 = entry.3.max(ds.message_count);
+        }
+
+        let mut entries: Vec<_> = data
+            .into_iter()
+            .map(
+                |((agent, sender), (count, last_active, alive_secs, message_count))| {
+                    IdentityEntry {
+                        agent,
+                        sender,
+                        count,
+                        message_count,
+                        last_active,
+                        alive_secs,
+                    }
+                },
+            )
+            .collect();
+        // Sort: active today first, then by name.
+        entries.sort_by(|a, b| {
+            let a_today = a.last_active == "Today";
+            let b_today = b.last_active == "Today";
+            b_today.cmp(&a_today).then(a.agent.cmp(&b.agent))
+        });
+
         let selected = match self {
             Self::Identities { selected, .. } => (*selected).min(entries.len().saturating_sub(1)),
             _ => 0,
@@ -91,23 +124,29 @@ impl SessionView {
     }
 
     /// Enter the selected identity to show its conversations.
-    /// `daemon_sessions` provides live session info from the daemon.
-    pub fn enter(&mut self, daemon_sessions: &[wcore::protocol::message::SessionInfo]) {
+    pub fn enter(&mut self, conversations: &[ConversationInfo], daemon_sessions: &[SessionInfo]) {
         if let Self::Identities { entries, selected } = self
             && let Some(entry) = entries.get(*selected)
         {
-            let mut conversations =
-                scan_conversations(&wcore::paths::SESSIONS_DIR, &entry.agent, &entry.sender);
-
-            // Merge live stats from daemon sessions that match this identity.
+            let mut conv_entries: Vec<ConversationEntry> = conversations
+                .iter()
+                .map(|c| ConversationEntry {
+                    date: c.date.clone(),
+                    title: c.title.clone(),
+                    file_path: c.file_path.clone(),
+                    message_count: Some(c.message_count),
+                    alive_secs: Some(c.alive_secs),
+                    session_id: None,
+                })
+                .collect();
+
+            // Merge live stats from daemon sessions.
             for ds in daemon_sessions {
                 if ds.agent == entry.agent && ds.created_by == entry.sender {
-                    // Match by title: the daemon session's title slug should match
-                    // one of the conversation entries' title.
                     let title_slug = wcore::sender_slug(&ds.title);
-                    if let Some(conv) = conversations.iter_mut().find(|c| {
+                    if let Some(conv) = conv_entries.iter_mut().find(|c| {
                         if ds.title.is_empty() && c.title.is_empty() {
-                            true // both untitled — match the latest
+                            true
                         } else {
                             c.title == title_slug
                         }
@@ -122,25 +161,22 @@ impl SessionView {
             *self = Self::Conversations {
                 agent: entry.agent.clone(),
                 sender: entry.sender.clone(),
-                entries: conversations,
+                entries: conv_entries,
                 selected: 0,
             };
         }
     }
 
     /// Update live stats from daemon data without resetting selection.
-    pub fn merge_daemon_data(&mut self, daemon_sessions: &[wcore::protocol::message::SessionInfo]) {
+    /// Only overlays live session info — does not touch base counts from
+    /// the last `refresh_identities` call.
+    pub fn merge_daemon_data(&mut self, daemon_sessions: &[SessionInfo]) {
         match self {
             Self::Identities { entries, .. } => {
-                // Reset live stats, then re-merge.
-                for e in entries.iter_mut() {
-                    e.message_count = 0;
-                    e.alive_secs = 0;
-                }
                 for e in entries.iter_mut() {
                     for ds in daemon_sessions {
                         if ds.agent == e.agent && ds.created_by == e.sender {
-                            e.message_count += ds.message_count;
+                            e.message_count = e.message_count.max(ds.message_count);
                             e.alive_secs = e.alive_secs.max(ds.alive_secs);
                             e.last_active = "Today".to_string();
                         }
@@ -153,7 +189,6 @@ impl SessionView {
                 entries,
                 ..
             } => {
-                // Reset live stats, then re-merge for this identity.
                 for c in entries.iter_mut() {
                     c.message_count = None;
                     c.alive_secs = None;
@@ -187,16 +222,29 @@ impl SessionView {
             entries, selected, ..
         } = self
         {
-            entries.get(*selected).map(|e| e.file_path.clone())
+            entries
+                .get(*selected)
+                .map(|e| std::path::PathBuf::from(&e.file_path))
+        } else {
+            None
+        }
+    }
+
+    /// Get the (agent, sender) of the currently selected identity.
+    pub fn selected_identity(&self) -> Option<(&str, &str)> {
+        if let Self::Identities { entries, selected } = self {
+            entries
+                .get(*selected)
+                .map(|e| (e.agent.as_str(), e.sender.as_str()))
         } else {
             None
         }
     }
 
     /// Go back to identity list.
-    pub fn back(&mut self, daemon_sessions: &[wcore::protocol::message::SessionInfo]) {
+    pub fn back(&mut self, conversations: &[ConversationInfo], daemon_sessions: &[SessionInfo]) {
         if matches!(self, Self::Conversations { .. }) {
-            self.refresh_identities(daemon_sessions);
+            self.refresh_identities(conversations, daemon_sessions);
         }
     }
 
@@ -372,194 +420,3 @@ fn render_conversations(
 
     frame.render_widget(Paragraph::new(lines).block(block), area);
 }
-
-/// Convert a file mtime to a display label relative to today.
-fn mtime_to_label(mtime: std::time::SystemTime, today: chrono::NaiveDate) -> String {
-    let date = chrono::DateTime::<chrono::Local>::from(mtime).date_naive();
-    if date == today {
-        "Today".to_string()
-    } else if date == today - chrono::Duration::days(1) {
-        "Yesterday".to_string()
-    } else {
-        date.format("%Y-%m-%d").to_string()
-    }
-}
-
-// ── Filesystem scanning ─────────────────────────────────────────────
-
-/// Scan flat sessions directory and return unique identities with stats.
-fn scan_identities(sessions_dir: &Path) -> Vec<IdentityEntry> {
-    // Track: (agent, sender) → (count, latest_mtime, total_uptime, total_msgs)
-    let mut data: BTreeMap<(String, String), (usize, std::time::SystemTime, u64, u64)> =
-        BTreeMap::new();
-
-    let Ok(entries) = fs::read_dir(sessions_dir) else {
-        return Vec::new();
-    };
-
-    for file in entries.flatten() {
-        let path = file.path();
-        if path.is_dir() {
-            continue;
-        }
-        let name = file.file_name();
-        let Some(name) = name.to_str() else { continue };
-        if !name.ends_with(".jsonl") {
-            continue;
-        }
-        if let Some((agent, sender)) = parse_identity_from_filename(name) {
-            let mtime = file
-                .metadata()
-                .and_then(|m| m.modified())
-                .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
-            let (uptime, msgs) = read_file_stats(&path);
-            let entry =
-                data.entry((agent, sender))
-                    .or_insert((0, std::time::SystemTime::UNIX_EPOCH, 0, 0));
-            entry.0 += 1;
-            if mtime > entry.1 {
-                entry.1 = mtime;
-            }
-            entry.2 += uptime;
-            entry.3 += msgs;
-        }
-    }
-
-    let today = chrono::Local::now().date_naive();
-    let mut entries: Vec<_> = data
-        .into_iter()
-        .map(|((agent, sender), (count, mtime, uptime, msgs))| {
-            let last_active = mtime_to_label(mtime, today);
-            (
-                mtime,
-                IdentityEntry {
-                    agent,
-                    sender,
-                    count,
-                    message_count: msgs,
-                    last_active,
-                    alive_secs: uptime,
-                },
-            )
-        })
-        .collect();
-    // Sort by mtime descending (most recently active first).
-    entries.sort_by(|a, b| b.0.cmp(&a.0));
-    entries.into_iter().map(|(_, e)| e).collect()
-}
-
-/// Scan conversations for a specific identity, sorted by mtime (newest first).
-fn scan_conversations(sessions_dir: &Path, agent: &str, sender: &str) -> Vec<ConversationEntry> {
-    let slug = wcore::sender_slug(sender);
-    let prefix = format!("{agent}_{slug}_");
-    let today = chrono::Local::now().date_naive();
-
-    let Ok(files) = fs::read_dir(sessions_dir) else {
-        return Vec::new();
-    };
-
-    let mut raw: Vec<(
-        std::time::SystemTime,
-        u32,
-        String,
-        std::path::PathBuf,
-        u64,
-        u64,
-    )> = Vec::new();
-    for file in files.flatten() {
-        let path = file.path();
-        if path.is_dir() {
-            continue;
-        }
-        let name = file.file_name();
-        let Some(name) = name.to_str() else { continue };
-        if !name.starts_with(&prefix) || !name.ends_with(".jsonl") {
-            continue;
-        }
-        let after_prefix = &name[prefix.len()..name.len() - 6]; // strip .jsonl
-        let (seq, title) = if let Some(underscore) = after_prefix.find('_') {
-            let seq: u32 = after_prefix[..underscore].parse().unwrap_or(0);
-            let title = after_prefix[underscore + 1..].to_string();
-            (seq, title)
-        } else {
-            let seq: u32 = after_prefix.parse().unwrap_or(0);
-            (seq, String::new())
-        };
-        let mtime = file
-            .metadata()
-            .and_then(|m| m.modified())
-            .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
-
-        // Read stats from the file: meta line for uptime, line count for messages.
-        let (uptime, msg_count) = read_file_stats(&path);
-        raw.push((mtime, seq, title, path, uptime, msg_count));
-    }
-
-    // Sort by mtime descending (newest first).
-    raw.sort_by(|a, b| b.0.cmp(&a.0));
-
-    raw.into_iter()
-        .map(
-            |(mtime, seq, title, file_path, uptime, msg_count)| ConversationEntry {
-                date: mtime_to_label(mtime, today),
-                seq,
-                title,
-                file_path,
-                message_count: Some(msg_count),
-                alive_secs: Some(uptime),
-                session_id: None,
-            },
-        )
-        .collect()
-}
-
-/// Read uptime_secs from meta line and count message lines from a session file.
-/// Returns (uptime_secs, message_count).
-fn read_file_stats(path: &Path) -> (u64, u64) {
-    use std::io::{BufRead, BufReader};
-
-    let Ok(file) = fs::File::open(path) else {
-        return (0, 0);
-    };
-    let reader = BufReader::new(file);
-    let mut lines = reader.lines();
-
-    // First line is meta — extract uptime_secs.
-    let uptime = lines
-        .next()
-        .and_then(|l| l.ok())
-        .and_then(|l| {
-            let v: serde_json::Value = serde_json::from_str(&l).ok()?;
-            v.get("uptime_secs")?.as_u64()
-        })
-        .unwrap_or(0);
-
-    // Count remaining non-empty, non-compact lines as messages.
-    let msg_count = lines
-        .map_while(|l| l.ok())
-        .filter(|l| !l.trim().is_empty() && !l.contains("\"compact\""))
-        .count() as u64;
-
-    (uptime, msg_count)
-}
-
-/// Parse agent and sender from a session filename.
-/// Format: `{agent}_{sender}_{seq}[_{title}].jsonl`
-fn parse_identity_from_filename(name: &str) -> Option<(String, String)> {
-    let stem = name.strip_suffix(".jsonl")?;
-    // Split by '_' and find the first part that looks like a seq number.
-    // Everything before the seq is agent_sender.
-    let parts: Vec<&str> = stem.split('_').collect();
-    if parts.len() < 3 {
-        return None;
-    }
-    // Find the first numeric part (that's the seq).
-    for i in 2..parts.len() {
-        if parts[i].chars().all(|c| c.is_ascii_digit()) && !parts[i].is_empty() {
-            let agent = parts[0].to_string();
-            let sender = parts[1..i].join("_");
-            return Some((agent, sender));
-        }
-    }
-    None
-}
diff --git a/crates/cli/src/cmd/hub.rs b/crates/cli/src/cmd/hub.rs
--- a/crates/cli/src/cmd/hub.rs
+++ b/crates/cli/src/cmd/hub.rs
@@ -1,11 +1,12 @@
 //! Hub package management command.
 
-use crate::repl::{self, runner::Runner};
+use crate::repl::runner::Runner;
 use anyhow::{Context, Result};
 use clap::{Args, Subcommand};
 use crabhub::manifest::Manifest;
+use futures_util::StreamExt;
 use std::path::{Path, PathBuf};
-use wcore::Setup;
+use wcore::protocol::message::hub_event;
 
 /// Manage hub packages.
 #[derive(Args, Debug)]
@@ -59,90 +60,48 @@ pub struct HubPackage {
 impl Hub {
     /// Run the hub command.
     pub async fn run(self, runner: &mut Runner) -> Result<()> {
-        if let HubCommand::Test(t) = self.command {
-            return test_manifest(&t.path);
-        }
-
-        let (pkg, force, is_install) = match self.command {
-            HubCommand::Install(p) => (p.package, p.force, true),
-            HubCommand::Uninstall(p) => (p.package, false, false),
-            HubCommand::Test(_) => unreachable!(),
-        };
-
-        let on_step = |msg: &str| println!("  {msg}");
-
-        if is_install {
-            let result = crabhub::package::install(
-                &pkg,
-                self.branch.as_deref(),
-                self.path.as_deref(),
-                force,
-                on_step,
-            )
-            .await?;
-            println!("Done: {pkg}");
-
-            // Reload daemon to pick up new components.
-            let _ = runner.reload().await;
-            println!("Daemon reloaded.");
-
-            // Check for conflicts with existing packages.
-            let config_dir = &*wcore::paths::CONFIG_DIR;
-            let (manifest, mut warnings) = wcore::resolve_manifests(config_dir);
-            warnings.extend(wcore::check_skill_conflicts(&manifest.skill_dirs));
-            for w in &warnings {
-                tracing::warn!("{w}");
-            }
-
-            // Warn about MCPs that require authentication.
-            for (name, mcp) in &manifest.mcps {
-                if mcp.auth
-                    && !wcore::paths::TOKENS_DIR
-                        .join(format!("{name}.json"))
-                        .exists()
-                {
-                    println!("MCP '{name}' requires authentication.");
+        let branch = self.branch.as_deref().unwrap_or("");
+        let path = self
+            .path
+            .as_deref()
+            .map(|p| p.to_string_lossy())
+            .unwrap_or_default();
+
+        match self.command {
+            HubCommand::Test(t) => return test_manifest(&t.path),
+            HubCommand::Install(p) => {
+                let mut stream =
+                    std::pin::pin!(runner.install_package(&p.package, branch, &path, p.force));
+                while let Some(event) = stream.next().await {
+                    match event? {
+                        hub_event::Event::Step(s) => println!("  {}", s.message),
+                        hub_event::Event::Warning(w) => eprintln!("  warning: {}", w.message),
+                        hub_event::Event::SetupOutput(o) => print!("{}", o.content),
+                        hub_event::Event::Done(d) => {
+                            if !d.error.is_empty() {
+                                anyhow::bail!("{}", d.error);
+                            }
+                        }
+                    }
                 }
+                println!("Done: {}", p.package);
             }
-
-            // Run prompt-type setup via inference.
-            if let Some(Setup::Prompt { ref prompt }) = result.setup {
-                let prompt_text = if prompt.ends_with(".md") {
-                    let repo_dir = result
-                        .repo_dir
-                        .as_ref()
-                        .context("prompt setup requires a repository but none was cloned")?;
-                    let raw = std::fs::read_to_string(repo_dir.join(prompt))
-                        .with_context(|| format!("failed to read setup prompt: {}", prompt))?;
-                    // Replace <REPO_DIR> placeholder with the actual cached repo path.
-                    raw.replace("<REPO_DIR>", &repo_dir.display().to_string())
-                } else {
-                    prompt.clone()
-                };
-
-                println!("Running setup…");
-                let conn_info = runner.conn_info().clone();
-                let os_user = std::env::var("USER").unwrap_or_else(|_| "user".into());
-                let stream = runner.stream(
-                    wcore::paths::DEFAULT_AGENT,
-                    &prompt_text,
-                    result.repo_dir.as_deref(),
-                    false,
-                    None,
-                    Some(os_user),
-                );
-                repl::stream_to_terminal(stream, &conn_info).await?;
-                println!();
+            HubCommand::Uninstall(p) => {
+                let mut stream = std::pin::pin!(runner.uninstall_package(&p.package));
+                while let Some(event) = stream.next().await {
+                    match event? {
+                        hub_event::Event::Step(s) => println!("  {}", s.message),
+                        hub_event::Event::Warning(w) => eprintln!("  warning: {}", w.message),
+                        hub_event::Event::SetupOutput(o) => print!("{}", o.content),
+                        hub_event::Event::Done(d) => {
+                            if !d.error.is_empty() {
+                                anyhow::bail!("{}", d.error);
+                            }
+                        }
+                    }
+                }
+                println!("Done: {}", p.package);
             }
-
-            println!("Configure env vars in config.toml [env] section if needed.");
-        } else {
-            crabhub::package::uninstall(&pkg, on_step).await?;
-            println!("Done: {pkg}");
-
-            // Reload daemon to drop removed components.
-            let _ = runner.reload().await;
-            println!("Daemon reloaded.");
         }
 
         Ok(())
diff --git a/crates/cli/src/repl/command.rs b/crates/cli/src/repl/command.rs
--- a/crates/cli/src/repl/command.rs
+++ b/crates/cli/src/repl/command.rs
@@ -5,7 +5,7 @@ use anyhow::Result;
 pub const SLASH_COMMANDS: &[&str] = &["/clear", "/exit", "/help", "/resume"];
 
 /// Collect matching `/command` and `/skill` names for the typed prefix.
-pub fn collect_candidates(line: &str, pos: usize) -> Vec<String> {
+pub fn collect_candidates(line: &str, pos: usize, skill_names: &[String]) -> Vec<String> {
     let prefix = &line[..pos];
     let Some(slash) = prefix.find('/') else {
         return Vec::new();
@@ -19,11 +19,9 @@ pub fn collect_candidates(line: &str, pos: usize) -> Vec<String> {
         .collect();
 
     let skill_prefix = &typed[1..];
-    if let Some(skills) = list_skill_names() {
-        for name in skills {
-            if name.starts_with(skill_prefix) {
-                candidates.push(format!("/{name}"));
-            }
+    for name in skill_names {
+        if name.starts_with(skill_prefix) {
+            candidates.push(format!("/{name}"));
         }
     }
 
@@ -75,18 +73,3 @@ pub async fn handle_slash(line: &str) -> Result<SlashResult> {
     }
     Ok(SlashResult::Handled)
 }
-
-/// List skill names for tab completion.
-fn list_skill_names() -> Option<Vec<String>> {
-    let config_dir = &*wcore::paths::CONFIG_DIR;
-    let (resolved, _) = wcore::resolve_manifests(config_dir);
-    let mut all_names = std::collections::BTreeSet::new();
-    for dir in &resolved.skill_dirs {
-        all_names.extend(wcore::scan_skill_names(dir));
-    }
-    if all_names.is_empty() {
-        None
-    } else {
-        Some(all_names.into_iter().collect())
-    }
-}
diff --git a/crates/cli/src/repl/input.rs b/crates/cli/src/repl/input.rs
--- a/crates/cli/src/repl/input.rs
+++ b/crates/cli/src/repl/input.rs
@@ -274,14 +274,17 @@ pub struct InputState {
     buf: InputBuffer,
     pub history: History,
     dropdown: Option<DropdownState>,
+    /// Cached skill names for tab completion (fetched from daemon at REPL init).
+    pub skill_names: Vec<String>,
 }
 
 impl InputState {
-    pub fn new(history: History) -> Self {
+    pub fn new(history: History, skill_names: Vec<String>) -> Self {
         Self {
             buf: InputBuffer::new(),
             history,
             dropdown: None,
+            skill_names,
         }
     }
 
@@ -296,7 +299,7 @@ impl InputState {
 
     fn open_dropdown(&mut self) {
         let line = self.buf.first_line().to_string();
-        let candidates = collect_candidates(&line, line.len());
+        let candidates = collect_candidates(&line, line.len(), &self.skill_names);
         if !candidates.is_empty() {
             self.dropdown = Some(DropdownState::new(candidates));
         }
@@ -407,7 +410,7 @@ impl InputState {
                 } else {
                     // Re-filter candidates.
                     let line = self.buf.first_line().to_string();
-                    let candidates = collect_candidates(&line, line.len());
+                    let candidates = collect_candidates(&line, line.len(), &self.skill_names);
                     if candidates.is_empty() {
                         self.close_dropdown();
                     } else if let Some(dd) = &mut self.dropdown {
@@ -421,7 +424,7 @@ impl InputState {
                 self.buf.handle_key(event::KeyCode::Char(ch));
                 // Re-filter candidates.
                 let line = self.buf.first_line().to_string();
-                let candidates = collect_candidates(&line, line.len());
+                let candidates = collect_candidates(&line, line.len(), &self.skill_names);
                 if candidates.is_empty() {
                     self.close_dropdown();
                 } else if let Some(dd) = &mut self.dropdown {
diff --git a/crates/cli/src/repl/mod.rs b/crates/cli/src/repl/mod.rs
--- a/crates/cli/src/repl/mod.rs
+++ b/crates/cli/src/repl/mod.rs
@@ -77,10 +77,11 @@ impl ChatRepl {
         let conn_info = self.runner.conn_info().clone();
         let os_user = std::env::var("USER").unwrap_or_else(|_| "user".into());
 
+        let skill_names = self.runner.list_skills().await.unwrap_or_default();
         let history = std::mem::take(&mut self.history);
         let mut app = App {
             renderer: MarkdownRenderer::new(),
-            input: InputState::new(history),
+            input: InputState::new(history, skill_names),
             scroll: 0,
             message_queue: VecDeque::new(),
             agent: self.agent.clone(),
@@ -560,40 +561,3 @@ fn draw_chat(frame: &mut ratatui::Frame, area: ratatui::layout::Rect, app: &App)
     let paragraph = Paragraph::new(lines).scroll((scroll_offset, 0));
     frame.render_widget(paragraph, area);
 }
-
-// ── Legacy helpers kept for other callers (e.g. hub.rs) ──────────
-
-/// Consume a stream of output chunks (legacy — used by hub.rs).
-pub(crate) async fn stream_to_terminal(
-    stream: impl futures_core::Stream<Item = Result<OutputChunk>>,
-    _conn_info: &ConnectionInfo,
-) -> Result<()> {
-    use std::io::Write;
-    let mut stream = pin!(stream);
-    let mut renderer = MarkdownRenderer::new();
-    renderer.start_waiting();
-
-    while let Some(chunk) = stream.next().await {
-        match chunk? {
-            OutputChunk::Text(text) => renderer.push_text(&text),
-            OutputChunk::Thinking(text) => renderer.push_thinking(&text),
-            OutputChunk::ToolStart(calls) => renderer.push_tool_start(&calls),
-            OutputChunk::ToolResult(_id, output) => renderer.push_tool_result(&output),
-            OutputChunk::ToolDone(success) => renderer.push_tool_done(success),
-            OutputChunk::AskUser { .. } => {}
-        }
-    }
-    renderer.finish();
-
-    // Dump buffer to stdout for legacy callers.
-    let lines = renderer.buffer.lines(0);
-    let mut stdout = std::io::stdout().lock();
-    for line in &lines {
-        for span in &line.spans {
-            write!(stdout, "{}", span.content)?;
-        }
-        writeln!(stdout)?;
-    }
-    stdout.flush()?;
-    Ok(())
-}
diff --git a/crates/cli/src/repl/runner.rs b/crates/cli/src/repl/runner.rs
--- a/crates/cli/src/repl/runner.rs
+++ b/crates/cli/src/repl/runner.rs
@@ -13,9 +13,12 @@ use transport::uds::{ClientConfig, Connection, CrabtalkClient};
 use wcore::protocol::{
     api::Client,
     message::{
-        AgentEventMsg, AskQuestion, ClientMessage, ConfigMsg, GetConfig, KillMsg, ReplyToAsk,
-        ServerMessage, SessionInfo, StreamMsg, SubscribeEvents, client_message, server_message,
-        stream_event,
+        AgentEventMsg, AskQuestion, ClientMessage, ConfigMsg, ConversationInfo, ConversationList,
+        DeleteProviderMsg, GetConfig, HubEvent, InstallPackageMsg, KillMsg, ListConversationsMsg,
+        ListMcpsMsg, ListProvidersMsg, ListSkillsMsg, McpInfo, McpList, ProviderInfo, ProviderList,
+        ReplyToAsk, ServerMessage, SessionInfo, SetActiveModelMsg, SetLocalMcpsMsg, SetProviderMsg,
+        SkillList, StreamMsg, SubscribeEvents, UninstallPackageMsg, client_message, hub_event,
+        server_message, stream_event,
     },
 };
 
@@ -301,6 +304,238 @@ impl Runner {
             })
     }
 
+    /// Install a hub package, streaming progress events.
+    pub fn install_package<'a>(
+        &'a mut self,
+        package: &str,
+        branch: &str,
+        path: &str,
+        force: bool,
+    ) -> impl Stream<Item = Result<hub_event::Event>> + Send + 'a {
+        self.transport
+            .request_stream(ClientMessage {
+                msg: Some(client_message::Msg::InstallPackage(InstallPackageMsg {
+                    package: package.to_string(),
+                    branch: branch.to_string(),
+                    path: path.to_string(),
+                    force,
+                })),
+            })
+            .take_while(|r| {
+                std::future::ready(!matches!(
+                    r,
+                    Ok(ServerMessage {
+                        msg: Some(server_message::Msg::HubEvent(HubEvent {
+                            event: Some(hub_event::Event::Done(d))
+                        }))
+                    }) if d.error.is_empty()
+                ))
+            })
+            .filter_map(|r| {
+                std::future::ready(match r {
+                    Ok(ServerMessage {
+                        msg: Some(server_message::Msg::HubEvent(e)),
+                    }) => e.event.map(Ok),
+                    Ok(ServerMessage {
+                        msg: Some(server_message::Msg::Error(e)),
+                    }) => Some(Err(anyhow::anyhow!(
+                        "server error ({}): {}",
+                        e.code,
+                        e.message
+                    ))),
+                    Ok(_) => None,
+                    Err(e) => Some(Err(e)),
+                })
+            })
+    }
+
+    /// Uninstall a hub package, streaming progress events.
+    pub fn uninstall_package<'a>(
+        &'a mut self,
+        package: &str,
+    ) -> impl Stream<Item = Result<hub_event::Event>> + Send + 'a {
+        self.transport
+            .request_stream(ClientMessage {
+                msg: Some(client_message::Msg::UninstallPackage(UninstallPackageMsg {
+                    package: package.to_string(),
+                })),
+            })
+            .take_while(|r| {
+                std::future::ready(!matches!(
+                    r,
+                    Ok(ServerMessage {
+                        msg: Some(server_message::Msg::HubEvent(HubEvent {
+                            event: Some(hub_event::Event::Done(d))
+                        }))
+                    }) if d.error.is_empty()
+                ))
+            })
+            .filter_map(|r| {
+                std::future::ready(match r {
+                    Ok(ServerMessage {
+                        msg: Some(server_message::Msg::HubEvent(e)),
+                    }) => e.event.map(Ok),
+                    Ok(ServerMessage {
+                        msg: Some(server_message::Msg::Error(e)),
+                    }) => Some(Err(anyhow::anyhow!(
+                        "server error ({}): {}",
+                        e.code,
+                        e.message
+                    ))),
+                    Ok(_) => None,
+                    Err(e) => Some(Err(e)),
+                })
+            })
+    }
+
+    /// List historical conversations from the daemon.
+    pub async fn list_conversations(
+        &mut self,
+        agent: &str,
+        sender: &str,
+    ) -> Result<Vec<ConversationInfo>> {
+        let msg = ClientMessage {
+            msg: Some(client_message::Msg::ListConversations(
+                ListConversationsMsg {
+                    agent: agent.to_string(),
+                    sender: sender.to_string(),
+                },
+            )),
+        };
+        match self.transport.request(msg).await? {
+            ServerMessage {
+                msg: Some(server_message::Msg::ConversationList(ConversationList { conversations })),
+            } => Ok(conversations),
+            ServerMessage {
+                msg: Some(server_message::Msg::Error(e)),
+            } => {
+                anyhow::bail!("server error ({}): {}", e.code, e.message)
+            }
+            other => anyhow::bail!("unexpected response: {other:?}"),
+        }
+    }
+
+    /// List all available skill names from the daemon.
+    pub async fn list_skills(&mut self) -> Result<Vec<String>> {
+        let msg = ClientMessage {
+            msg: Some(client_message::Msg::ListSkills(ListSkillsMsg {})),
+        };
+        match self.transport.request(msg).await? {
+            ServerMessage {
+                msg: Some(server_message::Msg::SkillList(SkillList { names })),
+            } => Ok(names),
+            ServerMessage {
+                msg: Some(server_message::Msg::Error(e)),
+            } => {
+                anyhow::bail!("server error ({}): {}", e.code, e.message)
+            }
+            other => anyhow::bail!("unexpected response: {other:?}"),
+        }
+    }
+
+    /// List all registered providers with config.
+    pub async fn list_providers(&mut self) -> Result<Vec<ProviderInfo>> {
+        let msg = ClientMessage {
+            msg: Some(client_message::Msg::ListProviders(ListProvidersMsg {})),
+        };
+        match self.transport.request(msg).await? {
+            ServerMessage {
+                msg: Some(server_message::Msg::ProviderList(ProviderList { providers })),
+            } => Ok(providers),
+            ServerMessage {
+                msg: Some(server_message::Msg::Error(e)),
+            } => anyhow::bail!("server error ({}): {}", e.code, e.message),
+            other => anyhow::bail!("unexpected response: {other:?}"),
+        }
+    }
+
+    /// Create or update a provider.
+    pub async fn set_provider(&mut self, name: String, config: String) -> Result<()> {
+        let msg = ClientMessage {
+            msg: Some(client_message::Msg::SetProvider(SetProviderMsg {
+                name,
+                config,
+            })),
+        };
+        match self.transport.request(msg).await? {
+            ServerMessage {
+                msg: Some(server_message::Msg::ProviderList(_)),
+            } => Ok(()),
+            ServerMessage {
+                msg: Some(server_message::Msg::Error(e)),
+            } => anyhow::bail!("server error ({}): {}", e.code, e.message),
+            other => anyhow::bail!("unexpected response: {other:?}"),
+        }
+    }
+
+    /// Delete a provider by name.
+    pub async fn delete_provider(&mut self, name: String) -> Result<()> {
+        let msg = ClientMessage {
+            msg: Some(client_message::Msg::DeleteProvider(DeleteProviderMsg {
+                name,
+            })),
+        };
+        match self.transport.request(msg).await? {
+            ServerMessage {
+                msg: Some(server_message::Msg::Pong(_)),
+            } => Ok(()),
+            ServerMessage {
+                msg: Some(server_message::Msg::Error(e)),
+            } => anyhow::bail!("server error ({}): {}", e.code, e.message),
+            other => anyhow::bail!("unexpected response: {other:?}"),
+        }
+    }
+
+    /// Set the active model.
+    pub async fn set_active_model(&mut self, model: String) -> Result<()> {
+        let msg = ClientMessage {
+            msg: Some(client_message::Msg::SetActiveModel(SetActiveModelMsg {
+                model,
+            })),
+        };
+        match self.transport.request(msg).await? {
+            ServerMessage {
+                msg: Some(server_message::Msg::Pong(_)),
+            } => Ok(()),
+            ServerMessage {
+                msg: Some(server_message::Msg::Error(e)),
+            } => anyhow::bail!("server error ({}): {}", e.code, e.message),
+            other => anyhow::bail!("unexpected response: {other:?}"),
+        }
+    }
+
+    /// List all MCP server configs.
+    pub async fn list_mcps(&mut self) -> Result<Vec<McpInfo>> {
+        let msg = ClientMessage {
+            msg: Some(client_message::Msg::ListMcps(ListMcpsMsg {})),
+        };
+        match self.transport.request(msg).await? {
+            ServerMessage {
+                msg: Some(server_message::Msg::McpList(McpList { mcps })),
+            } => Ok(mcps),
+            ServerMessage {
+                msg: Some(server_message::Msg::Error(e)),
+            } => anyhow::bail!("server error ({}): {}", e.code, e.message),
+            other => anyhow::bail!("unexpected response: {other:?}"),
+        }
+    }
+
+    /// Replace all local MCPs.
+    pub async fn set_local_mcps(&mut self, mcps: Vec<McpInfo>) -> Result<()> {
+        let msg = ClientMessage {
+            msg: Some(client_message::Msg::SetLocalMcps(SetLocalMcpsMsg { mcps })),
+        };
+        match self.transport.request(msg).await? {
+            ServerMessage {
+                msg: Some(server_message::Msg::Pong(_)),
+            } => Ok(()),
+            ServerMessage {
+                msg: Some(server_message::Msg::Error(e)),
+            } => anyhow::bail!("server error ({}): {}", e.code, e.message),
+            other => anyhow::bail!("unexpected response: {other:?}"),
+        }
+    }
+
     /// Get the daemon config as JSON string.
     pub async fn get_config(&mut self) -> Result<String> {
         let msg = ClientMessage {
diff --git a/crates/core/proto/crabtalk.proto b/crates/core/proto/crabtalk.proto
--- a/crates/core/proto/crabtalk.proto
+++ b/crates/core/proto/crabtalk.proto
@@ -8,33 +8,50 @@ option swift_prefix = "CrabtalkProto_";
 
 message ClientMessage {
   oneof msg {
+    // Execution
     SendMsg send = 1;
     StreamMsg stream = 2;
-    Ping ping = 3;
+    ReplyToAsk reply_to_ask = 3;
+    // Session management
     Sessions sessions = 4;
     KillMsg kill = 5;
-    GetConfig get_config = 6;
-    SetConfigMsg set_config = 7;
-    ReloadMsg reload = 8;
-    SubscribeEvents subscribe_events = 9;
-    ReplyToAsk reply_to_ask = 10;
-    GetStats get_stats = 11;
-    CreateCronMsg create_cron = 12;
-    DeleteCronMsg delete_cron = 13;
-    ListCronsMsg list_crons = 14;
-    CompactMsg compact = 15;
-    ListAgentsMsg list_agents = 16;
-    GetAgentMsg get_agent = 17;
-    CreateAgentMsg create_agent = 18;
-    UpdateAgentMsg update_agent = 19;
-    DeleteAgentMsg delete_agent = 20;
-    ListProvidersMsg list_providers = 21;
-    InstallPackageMsg install_package = 22;
-    UninstallPackageMsg uninstall_package = 23;
-    ListPackagesMsg list_packages = 24;
-    StartServiceMsg start_service = 25;
-    StopServiceMsg stop_service = 26;
-    ServiceLogsMsg service_logs = 27;
+    CompactMsg compact = 6;
+    ListConversationsMsg list_conversations = 7;
+    // Provider management
+    ListProvidersMsg list_providers = 8;
+    SetProviderMsg set_provider = 9;
+    DeleteProviderMsg delete_provider = 10;
+    SetActiveModelMsg set_active_model = 11;
+    ListProviderPresetsMsg list_provider_presets = 12;
+    // MCP management
+    ListMcpsMsg list_mcps = 13;
+    SetLocalMcpsMsg set_local_mcps = 14;
+    // Agent management
+    ListAgentsMsg list_agents = 15;
+    GetAgentMsg get_agent = 16;
+    CreateAgentMsg create_agent = 17;
+    UpdateAgentMsg update_agent = 18;
+    DeleteAgentMsg delete_agent = 19;
+    // Hub / packages
+    InstallPackageMsg install_package = 20;
+    UninstallPackageMsg uninstall_package = 21;
+    ListPackagesMsg list_packages = 22;
+    // Skills
+    ListSkillsMsg list_skills = 23;
+    // Services
+    StartServiceMsg start_service = 24;
+    StopServiceMsg stop_service = 25;
+    ServiceLogsMsg service_logs = 26;
+    // Cron
+    CreateCronMsg create_cron = 27;
+    DeleteCronMsg delete_cron = 28;
+    ListCronsMsg list_crons = 29;
+    // Daemon lifecycle
+    Ping ping = 30;
+    GetConfig get_config = 31;
+    ReloadMsg reload = 32;
+    GetStats get_stats = 33;
+    SubscribeEvents subscribe_events = 34;
   }
 }
 
@@ -68,10 +85,6 @@ message KillMsg {
   uint64 session = 1;
 }
 
-message SetConfigMsg {
-  string config = 1;
-}
-
 message ReloadMsg {}
 
 message CreateCronMsg {
@@ -128,6 +141,34 @@ message UninstallPackageMsg {
 
 message ListPackagesMsg {}
 
+message ListSkillsMsg {}
+
+message ListConversationsMsg {
+  string agent = 1;
+  string sender = 2;
+}
+
+message ListMcpsMsg {}
+
+message SetLocalMcpsMsg {
+  repeated McpInfo mcps = 1;
+}
+
+message SetProviderMsg {
+  string name = 1;
+  string config = 2;
+}
+
+message DeleteProviderMsg {
+  string name = 1;
+}
+
+message SetActiveModelMsg {
+  string model = 1;
+}
+
+message ListProviderPresetsMsg {}
+
 message StartServiceMsg {
   string name = 1;
   bool force = 2;
@@ -146,22 +187,38 @@ message ServiceLogsMsg {
 
 message ServerMessage {
   oneof msg {
-    SendResponse response = 1;
-    StreamEvent stream = 2;
-    ErrorMsg error = 3;
-    Pong pong = 4;
+    // Common
+    ErrorMsg error = 1;
+    Pong pong = 2;
+    // Execution
+    SendResponse response = 3;
+    StreamEvent stream = 4;
+    // Session
     SessionList sessions = 5;
-    ConfigMsg config = 6;
-    AgentEventMsg agent_event = 7;
-    DaemonStats stats = 8;
-    CronInfo cron_info = 9;
-    CronList cron_list = 10;
-    CompactResponse compact = 11;
-    AgentInfo agent_info = 12;
-    AgentList agent_list = 13;
-    ProviderList provider_list = 14;
-    PackageList package_list = 15;
+    CompactResponse compact = 6;
+    ConversationList conversation_list = 7;
+    // Provider
+    ProviderList provider_list = 8;
+    ProviderPresetList provider_preset_list = 9;
+    // MCP
+    McpList mcp_list = 10;
+    // Agent
+    AgentInfo agent_info = 11;
+    AgentList agent_list = 12;
+    // Hub / packages
+    HubEvent hub_event = 13;
+    PackageList package_list = 14;
+    // Skills
+    SkillList skill_list = 15;
+    // Services
     ServiceLogOutput service_log_output = 16;
+    // Cron
+    CronInfo cron_info = 17;
+    CronList cron_list = 18;
+    // Daemon lifecycle
+    ConfigMsg config = 19;
+    DaemonStats stats = 20;
+    AgentEventMsg agent_event = 21;
   }
 }
 
@@ -334,6 +391,7 @@ message AgentList {
 message ProviderInfo {
   string name = 1;
   bool active = 2;
+  string config = 3;
 }
 
 message ProviderList {
@@ -352,3 +410,87 @@ message PackageList {
 message ServiceLogOutput {
   string content = 1;
 }
+
+message SkillList {
+  repeated string names = 1;
+}
+
+message ConversationInfo {
+  string agent = 1;
+  string sender = 2;
+  uint32 seq = 3;
+  string title = 4;
+  string file_path = 5;
+  uint64 message_count = 6;
+  uint64 alive_secs = 7;
+  string date = 8;
+}
+
+message ConversationList {
+  repeated ConversationInfo conversations = 1;
+}
+
+message McpInfo {
+  string name = 1;
+  string command = 2;
+  repeated string args = 3;
+  map<string, string> env = 4;
+  string url = 5;
+  bool auth = 6;
+  string source = 7;
+  bool auto_restart = 8;
+}
+
+message McpList {
+  repeated McpInfo mcps = 1;
+}
+
+enum ProviderKind {
+  PROVIDER_KIND_UNKNOWN = 0;
+  OPENAI = 1;
+  ANTHROPIC = 2;
+  GOOGLE = 3;
+  BEDROCK = 4;
+  OLLAMA = 5;
+  AZURE = 6;
+  LLAMA_CPP = 7;
+}
+
+message ProviderPresetInfo {
+  string name = 1;
+  ProviderKind kind = 2;
+  string base_url = 3;
+  string fixed_base_url = 4;
+  string default_model = 5;
+}
+
+message ProviderPresetList {
+  repeated ProviderPresetInfo presets = 1;
+}
+
+// ── Hub Events ──────────────────────────────────────────────────
+
+message HubEvent {
+  oneof event {
+    HubStep step = 1;
+    HubWarning warning = 2;
+    HubSetupOutput setup_output = 3;
+    HubDone done = 4;
+  }
+}
+
+message HubStep {
+  string message = 1;
+}
+
+message HubWarning {
+  string message = 1;
+}
+
+message HubSetupOutput {
+  string content = 1;
+}
+
+message HubDone {
+  string error = 1;
+}
diff --git a/crates/core/src/agent/mod.rs b/crates/core/src/agent/mod.rs
--- a/crates/core/src/agent/mod.rs
+++ b/crates/core/src/agent/mod.rs
@@ -114,7 +114,7 @@ impl<M: Model> Agent<M> {
                         session_id,
                     )
                     .await;
-                let msg = Message::tool(&result, tc.id.clone());
+                let msg = Message::tool(&result, tc.id.clone(), &tc.function.name);
                 history.push(msg.clone());
                 tool_results.push(msg);
             }
@@ -327,7 +327,7 @@ impl<M: Model> Agent<M> {
                             .dispatch_tool(&tc.function.name, &tc.function.arguments, &sender, session_id)
                             .await;
                         let duration_ms = tool_start.elapsed().as_millis() as u64;
-                        let msg = Message::tool(&result, tc.id.clone());
+                        let msg = Message::tool(&result, tc.id.clone(), &tc.function.name);
                         history.push(msg.clone());
                         tool_results.push(msg);
                         yield AgentEvent::ToolResult {
diff --git a/crates/core/src/config/mod.rs b/crates/core/src/config/mod.rs
--- a/crates/core/src/config/mod.rs
+++ b/crates/core/src/config/mod.rs
@@ -9,4 +9,4 @@ pub use manifest::{
     load_agents_dirs, repo_slug, resolve_manifests, scan_skill_names,
 };
 pub use mcp::McpServerConfig;
-pub use provider::{ApiStandard, ProviderDef};
+pub use provider::{ApiStandard, PROVIDER_PRESETS, ProviderDef, ProviderPreset};
diff --git a/crates/core/src/config/provider.rs b/crates/core/src/config/provider.rs
--- a/crates/core/src/config/provider.rs
+++ b/crates/core/src/config/provider.rs
@@ -1,3 +1,62 @@
 //! Remote provider configuration — re-exported from crabllm-core.
 
 pub use crabllm_core::{ProviderConfig as ProviderDef, ProviderKind as ApiStandard};
+
+/// Provider preset — template for setting up a new provider.
+pub struct ProviderPreset {
+    /// Preset name (e.g. "anthropic", "openai", "custom").
+    pub name: &'static str,
+    /// API standard.
+    pub kind: ApiStandard,
+    /// Default/suggested base URL (editable by user).
+    pub base_url: &'static str,
+    /// Hardcoded base URL (shown read-only, not saved to config). Empty if editable.
+    pub fixed_base_url: &'static str,
+    /// Default model name for this provider.
+    pub default_model: &'static str,
+}
+
+impl ProviderPreset {
+    /// Whether the base_url field is editable for this preset.
+    pub fn base_url_editable(&self) -> bool {
+        self.fixed_base_url.is_empty()
+    }
+}
+
+pub const PROVIDER_PRESETS: &[ProviderPreset] = &[
+    ProviderPreset {
+        name: "anthropic",
+        kind: ApiStandard::Anthropic,
+        base_url: "",
+        fixed_base_url: "https://api.anthropic.com/v1",
+        default_model: "claude-sonnet-4-5-20250514",
+    },
+    ProviderPreset {
+        name: "openai",
+        kind: ApiStandard::Openai,
+        base_url: "https://api.openai.com/v1",
+        fixed_base_url: "",
+        default_model: "gpt-4o",
+    },
+    ProviderPreset {
+        name: "google",
+        kind: ApiStandard::Google,
+        base_url: "",
+        fixed_base_url: "https://generativelanguage.googleapis.com/v1beta",
+        default_model: "gemini-2.5-pro",
+    },
+    ProviderPreset {
+        name: "ollama",
+        kind: ApiStandard::Ollama,
+        base_url: "http://localhost:11434/v1",
+        fixed_base_url: "",
+        default_model: "llama3",
+    },
+    ProviderPreset {
+        name: "azure",
+        kind: ApiStandard::Azure,
+        base_url: "",
+        fixed_base_url: "",
+        default_model: "gpt-4o",
+    },
+];
diff --git a/crates/core/src/model/message.rs b/crates/core/src/model/message.rs
--- a/crates/core/src/model/message.rs
+++ b/crates/core/src/model/message.rs
@@ -19,6 +19,11 @@ pub struct Message {
     #[serde(default, skip_serializing_if = "String::is_empty")]
     pub reasoning_content: String,
 
+    /// The function name (set on tool-result messages for providers that
+    /// require it, e.g. Gemini's `function_response.name`).
+    #[serde(default, skip_serializing_if = "String::is_empty")]
+    pub name: String,
+
     /// The tool call id
     #[serde(default, skip_serializing_if = "String::is_empty")]
     pub tool_call_id: String,
@@ -84,11 +89,16 @@ impl Message {
     }
 
     /// Create a new tool message
-    pub fn tool(content: impl Into<String>, call: impl Into<String>) -> Self {
+    pub fn tool(
+        content: impl Into<String>,
+        call: impl Into<String>,
+        name: impl Into<String>,
+    ) -> Self {
         Self {
             role: Role::Tool,
             content: content.into(),
             tool_call_id: call.into(),
+            name: name.into(),
             ..Default::default()
         }
     }
@@ -186,6 +196,7 @@ impl Default for Message {
             role: Role::User,
             content: String::new(),
             reasoning_content: String::new(),
+            name: String::new(),
             tool_call_id: String::new(),
             tool_calls: Vec::new(),
             sender: String::new(),
diff --git a/crates/core/src/protocol/api/client.rs b/crates/core/src/protocol/api/client.rs
--- a/crates/core/src/protocol/api/client.rs
+++ b/crates/core/src/protocol/api/client.rs
@@ -1,11 +1,14 @@
 //! Client trait — transport primitives plus typed provided methods.
 
 use crate::protocol::message::{
-    AgentInfo, AgentList, ClientMessage, ConfigMsg, CreateAgentMsg, DeleteAgentMsg, ErrorMsg,
-    GetAgentMsg, GetConfig, InstallPackageMsg, ListAgentsMsg, ListPackagesMsg, ListProvidersMsg,
-    PackageInfo, PackageList, Ping, ProviderInfo, ProviderList, SendMsg, SendResponse,
-    ServerMessage, ServiceLogOutput, ServiceLogsMsg, SetConfigMsg, StartServiceMsg, StopServiceMsg,
-    StreamEvent, StreamMsg, UninstallPackageMsg, UpdateAgentMsg, client_message, server_message,
+    AgentInfo, AgentList, ClientMessage, ConfigMsg, ConversationInfo, ConversationList,
+    CreateAgentMsg, DeleteAgentMsg, DeleteProviderMsg, ErrorMsg, GetAgentMsg, GetConfig, HubEvent,
+    InstallPackageMsg, ListAgentsMsg, ListConversationsMsg, ListMcpsMsg, ListPackagesMsg,
+    ListProviderPresetsMsg, ListProvidersMsg, ListSkillsMsg, McpInfo, McpList, PackageInfo,
+    PackageList, Ping, ProviderInfo, ProviderList, ProviderPresetInfo, ProviderPresetList, SendMsg,
+    SendResponse, ServerMessage, ServiceLogOutput, ServiceLogsMsg, SetActiveModelMsg,
+    SetLocalMcpsMsg, SetProviderMsg, SkillList, StartServiceMsg, StopServiceMsg, StreamEvent,
+    StreamMsg, UninstallPackageMsg, UpdateAgentMsg, client_message, hub_event, server_message,
     stream_event,
 };
 use anyhow::Result;
@@ -107,31 +110,6 @@ pub trait Client: Send {
         }
     }
 
-    /// Replace the full daemon config from JSON.
-    fn set_config(
-        &mut self,
-        config: String,
-    ) -> impl std::future::Future<Output = Result<()>> + Send {
-        async move {
-            match self
-                .request(ClientMessage {
-                    msg: Some(client_message::Msg::SetConfig(SetConfigMsg { config })),
-                })
-                .await?
-            {
-                ServerMessage {
-                    msg: Some(server_message::Msg::Pong(_)),
-                } => Ok(()),
-                ServerMessage {
-                    msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
-                } => {
-                    anyhow::bail!("server error ({code}): {message}")
-                }
-                other => anyhow::bail!("unexpected response: {other:?}"),
-            }
-        }
-    }
-
     /// List all registered agents.
     fn list_agents(&mut self) -> impl std::future::Future<Output = Result<Vec<AgentInfo>>> + Send {
         async move {
@@ -286,22 +264,194 @@ pub trait Client: Send {
         }
     }
 
-    /// Install a hub package.
+    /// Install a hub package, streaming progress events.
     fn install_package(
         &mut self,
         package: String,
         branch: String,
         path: String,
         force: bool,
+    ) -> impl Stream<Item = Result<hub_event::Event>> + Send + '_ {
+        self.request_stream(ClientMessage {
+            msg: Some(client_message::Msg::InstallPackage(InstallPackageMsg {
+                package,
+                branch,
+                path,
+                force,
+            })),
+        })
+        .take_while(|r| {
+            std::future::ready(!matches!(
+                r,
+                Ok(ServerMessage {
+                    msg: Some(server_message::Msg::HubEvent(HubEvent {
+                        event: Some(hub_event::Event::Done(d))
+                    }))
+                }) if d.error.is_empty()
+            ))
+        })
+        .map(|r| r.and_then(hub_event::Event::try_from))
+    }
+
+    /// Uninstall a hub package, streaming progress events.
+    fn uninstall_package(
+        &mut self,
+        package: String,
+    ) -> impl Stream<Item = Result<hub_event::Event>> + Send + '_ {
+        self.request_stream(ClientMessage {
+            msg: Some(client_message::Msg::UninstallPackage(UninstallPackageMsg {
+                package,
+            })),
+        })
+        .take_while(|r| {
+            std::future::ready(!matches!(
+                r,
+                Ok(ServerMessage {
+                    msg: Some(server_message::Msg::HubEvent(HubEvent {
+                        event: Some(hub_event::Event::Done(d))
+                    }))
+                }) if d.error.is_empty()
+            ))
+        })
+        .map(|r| r.and_then(hub_event::Event::try_from))
+    }
+
+    /// List installed hub packages.
+    fn list_packages(
+        &mut self,
+    ) -> impl std::future::Future<Output = Result<Vec<PackageInfo>>> + Send {
+        async move {
+            match self
+                .request(ClientMessage {
+                    msg: Some(client_message::Msg::ListPackages(ListPackagesMsg {})),
+                })
+                .await?
+            {
+                ServerMessage {
+                    msg: Some(server_message::Msg::PackageList(PackageList { packages })),
+                } => Ok(packages),
+                ServerMessage {
+                    msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
+                } => {
+                    anyhow::bail!("server error ({code}): {message}")
+                }
+                other => anyhow::bail!("unexpected response: {other:?}"),
+            }
+        }
+    }
+
+    /// List historical conversations from disk.
+    fn list_conversations(
+        &mut self,
+        agent: String,
+        sender: String,
+    ) -> impl std::future::Future<Output = Result<Vec<ConversationInfo>>> + Send {
+        async move {
+            match self
+                .request(ClientMessage {
+                    msg: Some(client_message::Msg::ListConversations(
+                        ListConversationsMsg { agent, sender },
+                    )),
+                })
+                .await?
+            {
+                ServerMessage {
+                    msg:
+                        Some(server_message::Msg::ConversationList(ConversationList { conversations })),
+                } => Ok(conversations),
+                ServerMessage {
+                    msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
+                } => {
+                    anyhow::bail!("server error ({code}): {message}")
+                }
+                other => anyhow::bail!("unexpected response: {other:?}"),
+            }
+        }
+    }
+
+    /// List all MCP server configs.
+    fn list_mcps(&mut self) -> impl std::future::Future<Output = Result<Vec<McpInfo>>> + Send {
+        async move {
+            match self
+                .request(ClientMessage {
+                    msg: Some(client_message::Msg::ListMcps(ListMcpsMsg {})),
+                })
+                .await?
+            {
+                ServerMessage {
+                    msg: Some(server_message::Msg::McpList(McpList { mcps })),
+                } => Ok(mcps),
+                ServerMessage {
+                    msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
+                } => anyhow::bail!("server error ({code}): {message}"),
+                other => anyhow::bail!("unexpected response: {other:?}"),
+            }
+        }
+    }
+
+    /// Replace all local MCPs in CrabTalk.toml.
+    fn set_local_mcps(
+        &mut self,
+        mcps: Vec<McpInfo>,
     ) -> impl std::future::Future<Output = Result<()>> + Send {
         async move {
             match self
                 .request(ClientMessage {
-                    msg: Some(client_message::Msg::InstallPackage(InstallPackageMsg {
-                        package,
-                        branch,
-                        path,
-                        force,
+                    msg: Some(client_message::Msg::SetLocalMcps(SetLocalMcpsMsg { mcps })),
+                })
+                .await?
+            {
+                ServerMessage {
+                    msg: Some(server_message::Msg::Pong(_)),
+                } => Ok(()),
+                ServerMessage {
+                    msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
+                } => anyhow::bail!("server error ({code}): {message}"),
+                other => anyhow::bail!("unexpected response: {other:?}"),
+            }
+        }
+    }
+
+    /// Create or update a provider.
+    fn set_provider(
+        &mut self,
+        name: String,
+        config: String,
+    ) -> impl std::future::Future<Output = Result<ProviderInfo>> + Send {
+        async move {
+            match self
+                .request(ClientMessage {
+                    msg: Some(client_message::Msg::SetProvider(SetProviderMsg {
+                        name,
+                        config,
+                    })),
+                })
+                .await?
+            {
+                ServerMessage {
+                    msg: Some(server_message::Msg::ProviderList(ProviderList { providers })),
+                } => providers
+                    .into_iter()
+                    .next()
+                    .ok_or_else(|| anyhow::anyhow!("empty provider list in response")),
+                ServerMessage {
+                    msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
+                } => anyhow::bail!("server error ({code}): {message}"),
+                other => anyhow::bail!("unexpected response: {other:?}"),
+            }
+        }
+    }
+
+    /// Delete a provider by name.
+    fn delete_provider(
+        &mut self,
+        name: String,
+    ) -> impl std::future::Future<Output = Result<()>> + Send {
+        async move {
+            match self
+                .request(ClientMessage {
+                    msg: Some(client_message::Msg::DeleteProvider(DeleteProviderMsg {
+                        name,
                     })),
                 })
                 .await?
@@ -311,24 +461,22 @@ pub trait Client: Send {
                 } => Ok(()),
                 ServerMessage {
                     msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
-                } => {
-                    anyhow::bail!("server error ({code}): {message}")
-                }
+                } => anyhow::bail!("server error ({code}): {message}"),
                 other => anyhow::bail!("unexpected response: {other:?}"),
             }
         }
     }
 
-    /// Uninstall a hub package.
-    fn uninstall_package(
+    /// Set the active model.
+    fn set_active_model(
         &mut self,
-        package: String,
+        model: String,
     ) -> impl std::future::Future<Output = Result<()>> + Send {
         async move {
             match self
                 .request(ClientMessage {
-                    msg: Some(client_message::Msg::UninstallPackage(UninstallPackageMsg {
-                        package,
+                    msg: Some(client_message::Msg::SetActiveModel(SetActiveModelMsg {
+                        model,
                     })),
                 })
                 .await?
@@ -338,33 +486,32 @@ pub trait Client: Send {
                 } => Ok(()),
                 ServerMessage {
                     msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
-                } => {
-                    anyhow::bail!("server error ({code}): {message}")
-                }
+                } => anyhow::bail!("server error ({code}): {message}"),
                 other => anyhow::bail!("unexpected response: {other:?}"),
             }
         }
     }
 
-    /// List installed hub packages.
-    fn list_packages(
+    /// List provider presets.
+    fn list_provider_presets(
         &mut self,
-    ) -> impl std::future::Future<Output = Result<Vec<PackageInfo>>> + Send {
+    ) -> impl std::future::Future<Output = Result<Vec<ProviderPresetInfo>>> + Send {
         async move {
             match self
                 .request(ClientMessage {
-                    msg: Some(client_message::Msg::ListPackages(ListPackagesMsg {})),
+                    msg: Some(client_message::Msg::ListProviderPresets(
+                        ListProviderPresetsMsg {},
+                    )),
                 })
                 .await?
             {
                 ServerMessage {
-                    msg: Some(server_message::Msg::PackageList(PackageList { packages })),
-                } => Ok(packages),
+                    msg:
+                        Some(server_message::Msg::ProviderPresetList(ProviderPresetList { presets })),
+                } => Ok(presets),
                 ServerMessage {
                     msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
-                } => {
-                    anyhow::bail!("server error ({code}): {message}")
-                }
+                } => anyhow::bail!("server error ({code}): {message}"),
                 other => anyhow::bail!("unexpected response: {other:?}"),
             }
         }
@@ -424,6 +571,28 @@ pub trait Client: Send {
         }
     }
 
+    /// List all available skill names.
+    fn list_skills(&mut self) -> impl std::future::Future<Output = Result<Vec<String>>> + Send {
+        async move {
+            match self
+                .request(ClientMessage {
+                    msg: Some(client_message::Msg::ListSkills(ListSkillsMsg {})),
+                })
+                .await?
+            {
+                ServerMessage {
+                    msg: Some(server_message::Msg::SkillList(SkillList { names })),
+                } => Ok(names),
+                ServerMessage {
+                    msg: Some(server_message::Msg::Error(ErrorMsg { code, message })),
+                } => {
+                    anyhow::bail!("server error ({code}): {message}")
+                }
+                other => anyhow::bail!("unexpected response: {other:?}"),
+            }
+        }
+    }
+
     /// Get recent log lines for a service.
     fn service_logs(
         &mut self,
diff --git a/crates/core/src/protocol/api/server.rs b/crates/core/src/protocol/api/server.rs
--- a/crates/core/src/protocol/api/server.rs
+++ b/crates/core/src/protocol/api/server.rs
@@ -1,11 +1,12 @@
 //! Server trait — one async method per protocol operation.
 
 use crate::protocol::message::{
-    AgentEventMsg, AgentInfo, AgentList, ClientMessage, CompactResponse, ConfigMsg, CreateAgentMsg,
-    CreateCronMsg, CronInfo, CronList, DaemonStats, ErrorMsg, InstallPackageMsg, PackageInfo,
-    PackageList, Pong, ProviderInfo, ProviderList, SendMsg, SendResponse, ServerMessage,
-    ServiceLogOutput, SessionInfo, SessionList, StreamEvent, StreamMsg, UpdateAgentMsg,
-    client_message, server_message,
+    AgentEventMsg, AgentInfo, AgentList, ClientMessage, CompactResponse, ConfigMsg,
+    ConversationInfo, ConversationList, CreateAgentMsg, CreateCronMsg, CronInfo, CronList,
+    DaemonStats, ErrorMsg, HubEvent, InstallPackageMsg, McpInfo, McpList, PackageInfo, PackageList,
+    Pong, ProviderInfo, ProviderList, ProviderPresetInfo, ProviderPresetList, SendMsg,
+    SendResponse, ServerMessage, ServiceLogOutput, SessionInfo, SessionList, SkillList,
+    StreamEvent, StreamMsg, UpdateAgentMsg, client_message, server_message,
 };
 use anyhow::Result;
 use futures_core::Stream;
@@ -64,9 +65,6 @@ pub trait Server: Sync {
     /// Handle `GetConfig` — return the full daemon config as JSON.
     fn get_config(&self) -> impl std::future::Future<Output = Result<String>> + Send;
 
-    /// Handle `SetConfig` — replace the daemon config from JSON.
-    fn set_config(&self, config: String) -> impl std::future::Future<Output = Result<()>> + Send;
-
     /// Handle `Reload` — hot-reload runtime from disk.
     fn reload(&self) -> impl std::future::Future<Output = Result<()>> + Send;
 
@@ -126,20 +124,58 @@ pub trait Server: Sync {
     fn list_providers(&self)
     -> impl std::future::Future<Output = Result<Vec<ProviderInfo>>> + Send;
 
-    /// Handle `InstallPackage` — install a hub package and reload.
+    /// Handle `InstallPackage` — install a hub package, stream progress.
     fn install_package(
         &self,
         req: InstallPackageMsg,
+    ) -> impl Stream<Item = Result<HubEvent>> + Send;
+
+    /// Handle `UninstallPackage` — uninstall a hub package, stream progress.
+    fn uninstall_package(&self, package: String) -> impl Stream<Item = Result<HubEvent>> + Send;
+
+    /// Handle `ListPackages` — return all installed hub packages.
+    fn list_packages(&self) -> impl std::future::Future<Output = Result<Vec<PackageInfo>>> + Send;
+
+    /// Handle `ListSkills` — return all available skill names.
+    fn list_skills(&self) -> impl std::future::Future<Output = Result<Vec<String>>> + Send;
+
+    /// Handle `ListConversations` — return historical conversations from disk.
+    fn list_conversations(
+        &self,
+        agent: String,
+        sender: String,
+    ) -> impl std::future::Future<Output = Result<Vec<ConversationInfo>>> + Send;
+
+    /// Handle `ListMcps` — return all MCP server configs with source info.
+    fn list_mcps(&self) -> impl std::future::Future<Output = Result<Vec<McpInfo>>> + Send;
+
+    /// Handle `SetLocalMcps` — replace local MCPs in CrabTalk.toml.
+    fn set_local_mcps(
+        &self,
+        mcps: Vec<McpInfo>,
     ) -> impl std::future::Future<Output = Result<()>> + Send;
 
-    /// Handle `UninstallPackage` — uninstall a hub package and reload.
-    fn uninstall_package(
+    /// Handle `SetProvider` — create or update a provider in config.toml.
+    fn set_provider(
+        &self,
+        name: String,
+        config: String,
+    ) -> impl std::future::Future<Output = Result<ProviderInfo>> + Send;
+
+    /// Handle `DeleteProvider` — remove a provider from config.toml.
+    fn delete_provider(&self, name: String)
+    -> impl std::future::Future<Output = Result<()>> + Send;
+
+    /// Handle `SetActiveModel` — update the active model in config.toml.
+    fn set_active_model(
         &self,
-        package: String,
+        model: String,
     ) -> impl std::future::Future<Output = Result<()>> + Send;
 
-    /// Handle `ListPackages` — return all installed hub packages.
-    fn list_packages(&self) -> impl std::future::Future<Output = Result<Vec<PackageInfo>>> + Send;
+    /// Handle `ListProviderPresets` — return provider preset templates.
+    fn list_provider_presets(
+        &self,
+    ) -> impl std::future::Future<Output = Result<Vec<ProviderPresetInfo>>> + Send;
 
     /// Handle `StartService` — install and start a command service.
     fn start_service(
@@ -212,12 +248,6 @@ pub trait Server: Sync {
                         Err(e) => server_error(500, e.to_string()),
                     };
                 }
-                client_message::Msg::SetConfig(set_config_msg) => {
-                    yield match self.set_config(set_config_msg.config).await {
-                        Ok(()) => server_pong(),
-                        Err(e) => server_error(500, e.to_string()),
-                    };
-                }
                 client_message::Msg::SubscribeEvents(_) => {
                     let s = self.subscribe_events();
                     tokio::pin!(s);
@@ -329,16 +359,18 @@ pub trait Server: Sync {
                     };
                 }
                 client_message::Msg::InstallPackage(req) => {
-                    yield match self.install_package(req).await {
-                        Ok(()) => server_pong(),
-                        Err(e) => server_error(500, e.to_string()),
-                    };
+                    let s = self.install_package(req);
+                    tokio::pin!(s);
+                    while let Some(result) = s.next().await {
+                        yield result_to_msg(result);
+                    }
                 }
                 client_message::Msg::UninstallPackage(req) => {
-                    yield match self.uninstall_package(req.package).await {
-                        Ok(()) => server_pong(),
-                        Err(e) => server_error(500, e.to_string()),
-                    };
+                    let s = self.uninstall_package(req.package);
+                    tokio::pin!(s);
+                    while let Some(result) = s.next().await {
+                        yield result_to_msg(result);
+                    }
                 }
                 client_message::Msg::ListPackages(_) => {
                     yield match self.list_packages().await {
@@ -372,6 +404,70 @@ pub trait Server: Sync {
                         Err(e) => server_error(500, e.to_string()),
                     };
                 }
+                client_message::Msg::ListSkills(_) => {
+                    yield match self.list_skills().await {
+                        Ok(names) => ServerMessage {
+                            msg: Some(server_message::Msg::SkillList(SkillList { names })),
+                        },
+                        Err(e) => server_error(500, e.to_string()),
+                    };
+                }
+                client_message::Msg::ListConversations(req) => {
+                    yield match self.list_conversations(req.agent, req.sender).await {
+                        Ok(conversations) => ServerMessage {
+                            msg: Some(server_message::Msg::ConversationList(ConversationList {
+                                conversations,
+                            })),
+                        },
+                        Err(e) => server_error(500, e.to_string()),
+                    };
+                }
+                client_message::Msg::ListMcps(_) => {
+                    yield match self.list_mcps().await {
+                        Ok(mcps) => ServerMessage {
+                            msg: Some(server_message::Msg::McpList(McpList { mcps })),
+                        },
+                        Err(e) => server_error(500, e.to_string()),
+                    };
+                }
+                client_message::Msg::SetLocalMcps(req) => {
+                    yield match self.set_local_mcps(req.mcps).await {
+                        Ok(()) => server_pong(),
+                        Err(e) => server_error(500, e.to_string()),
+                    };
+                }
+                client_message::Msg::SetProvider(req) => {
+                    yield match self.set_provider(req.name, req.config).await {
+                        Ok(info) => ServerMessage {
+                            msg: Some(server_message::Msg::ProviderList(ProviderList {
+                                providers: vec![info],
+                            })),
+                        },
+                        Err(e) => server_error(500, e.to_string()),
+                    };
+                }
+                client_message::Msg::DeleteProvider(req) => {
+                    yield match self.delete_provider(req.name.clone()).await {
+                        Ok(()) => server_pong(),
+                        Err(e) => server_error(500, e.to_string()),
+                    };
+                }
+                client_message::Msg::SetActiveModel(req) => {
+                    yield match self.set_active_model(req.model).await {
+                        Ok(()) => server_pong(),
+                        Err(e) => server_error(500, e.to_string()),
+                    };
+                }
+                client_message::Msg::ListProviderPresets(_) => {
+                    yield match self.list_provider_presets().await {
+                        Ok(presets) => ServerMessage {
+                            msg: Some(server_message::Msg::ProviderPresetList(
+                                ProviderPresetList { presets },
+                            )),
+                        },
+                        Err(e) => server_error(500, e.to_string()),
+                    };
+                }
             }
         }
     }
diff --git a/crates/core/src/protocol/message/convert.rs b/crates/core/src/protocol/message/convert.rs
--- a/crates/core/src/protocol/message/convert.rs
+++ b/crates/core/src/protocol/message/convert.rs
@@ -1,8 +1,9 @@
 //! Conversions between protocol message types.
 
+use crate::config::ApiStandard;
 use crate::protocol::proto::{
-    AgentEventMsg, ClientMessage, ReplyToAsk, SendMsg, SendResponse, ServerMessage, StreamEvent,
-    StreamMsg, client_message, server_message, stream_event,
+    AgentEventMsg, ClientMessage, HubEvent, ProviderKind, ReplyToAsk, SendMsg, SendResponse,
+    ServerMessage, StreamEvent, StreamMsg, client_message, hub_event, server_message, stream_event,
 };
 
 // ── ClientMessage constructors ───────────────────────────────────
@@ -57,6 +58,14 @@ impl From<AgentEventMsg> for ServerMessage {
     }
 }
 
+impl From<HubEvent> for ServerMessage {
+    fn from(e: HubEvent) -> Self {
+        Self {
+            msg: Some(server_message::Msg::HubEvent(e)),
+        }
+    }
+}
+
 // ── TryFrom<ServerMessage> ───────────────────────────────────────
 
 fn error_or_unexpected(msg: ServerMessage) -> anyhow::Error {
@@ -89,3 +98,43 @@ impl TryFrom<ServerMessage> for stream_event::Event {
         }
     }
 }
+
+impl From<ApiStandard> for ProviderKind {
+    fn from(kind: ApiStandard) -> Self {
+        match kind {
+            ApiStandard::Openai => Self::Openai,
+            ApiStandard::Anthropic => Self::Anthropic,
+            ApiStandard::Google => Self::Google,
+            ApiStandard::Bedrock => Self::Bedrock,
+            ApiStandard::Ollama => Self::Ollama,
+            ApiStandard::Azure => Self::Azure,
+            ApiStandard::LlamaCpp => Self::LlamaCpp,
+        }
+    }
+}
+
+impl From<ProviderKind> for ApiStandard {
+    fn from(kind: ProviderKind) -> Self {
+        match kind {
+            ProviderKind::Openai | ProviderKind::Unknown => Self::Openai,
+            ProviderKind::Anthropic => Self::Anthropic,
+            ProviderKind::Google => Self::Google,
+            ProviderKind::Bedrock => Self::Bedrock,
+            ProviderKind::Ollama => Self::Ollama,
+            ProviderKind::Azure => Self::Azure,
+            ProviderKind::LlamaCpp => Self::LlamaCpp,
+        }
+    }
+}
+
+impl TryFrom<ServerMessage> for hub_event::Event {
+    type Error = anyhow::Error;
+    fn try_from(msg: ServerMessage) -> anyhow::Result<Self> {
+        match msg.msg {
+            Some(server_message::Msg::HubEvent(e)) => {
+                e.event.ok_or_else(|| anyhow::anyhow!("empty hub event"))
+            }
+            _ => Err(error_or_unexpected(msg)),
+        }
+    }
+}
diff --git a/crates/core/src/protocol/message/mod.rs b/crates/core/src/protocol/message/mod.rs
--- a/crates/core/src/protocol/message/mod.rs
+++ b/crates/core/src/protocol/message/mod.rs
@@ -2,15 +2,22 @@
 
 mod convert;
 
-pub use crate::protocol::proto::{AgentEventKind, client_message, server_message, stream_event};
+pub use crate::protocol::proto::{
+    AgentEventKind, ProviderKind as ProtoProviderKind, client_message, hub_event, server_message,
+    stream_event,
+};
 pub use crate::protocol::proto::{
     AgentEventMsg, AgentInfo, AgentList, AskOption, AskQuestion, AskUserEvent, ClientMessage,
-    CompactMsg, CompactResponse, ConfigMsg, CreateAgentMsg, CreateCronMsg, CronInfo, CronList,
-    DaemonStats, DeleteAgentMsg, DeleteCronMsg, ErrorMsg, GetAgentMsg, GetConfig, GetStats,
-    InstallPackageMsg, KillMsg, ListAgentsMsg, ListCronsMsg, ListPackagesMsg, ListProvidersMsg,
-    PackageInfo, PackageList, Ping, Pong, ProviderInfo, ProviderList, ReplyToAsk, SendMsg,
+    CompactMsg, CompactResponse, ConfigMsg, ConversationInfo, ConversationList, CreateAgentMsg,
+    CreateCronMsg, CronInfo, CronList, DaemonStats, DeleteAgentMsg, DeleteCronMsg,
+    DeleteProviderMsg, ErrorMsg, GetAgentMsg, GetConfig, GetStats, HubDone, HubEvent,
+    HubSetupOutput, HubStep, HubWarning, InstallPackageMsg, KillMsg, ListAgentsMsg,
+    ListConversationsMsg, ListCronsMsg, ListMcpsMsg, ListPackagesMsg, ListProviderPresetsMsg,
+    ListProvidersMsg, ListSkillsMsg, McpInfo, McpList, PackageInfo, PackageList, Ping, Pong,
+    ProviderInfo, ProviderList, ProviderPresetInfo, ProviderPresetList, ReplyToAsk, SendMsg,
     SendResponse, ServerMessage, ServiceLogOutput, ServiceLogsMsg, SessionInfo, SessionList,
-    SetConfigMsg, StartServiceMsg, StopServiceMsg, StreamChunk, StreamEnd, StreamEvent, StreamMsg,
-    StreamStart, StreamThinking, SubscribeEvents, TokenUsage, ToolCallInfo, ToolResultEvent,
-    ToolStartEvent, ToolsCompleteEvent, UninstallPackageMsg, UpdateAgentMsg,
+    SetActiveModelMsg, SetLocalMcpsMsg, SetProviderMsg, SkillList, StartServiceMsg, StopServiceMsg,
+    StreamChunk, StreamEnd, StreamEvent, StreamMsg, StreamStart, StreamThinking, SubscribeEvents,
+    TokenUsage, ToolCallInfo, ToolResultEvent, ToolStartEvent, ToolsCompleteEvent,
+    UninstallPackageMsg, UpdateAgentMsg,
 };
diff --git a/crates/daemon/src/daemon/protocol.rs b/crates/daemon/src/daemon/protocol.rs
--- a/crates/daemon/src/daemon/protocol.rs
+++ b/crates/daemon/src/daemon/protocol.rs
@@ -12,11 +12,13 @@ use std::{
 use wcore::protocol::{
     api::Server,
     message::{
-        AgentEventMsg, AgentInfo, AskOption, AskQuestion, AskUserEvent, CreateAgentMsg,
-        CreateCronMsg, CronInfo, CronList, DaemonStats, InstallPackageMsg, PackageInfo,
-        ProviderInfo, SendMsg, SendResponse, SessionInfo, StreamChunk, StreamEnd, StreamEvent,
-        StreamMsg, StreamStart, StreamThinking, TokenUsage, ToolCallInfo, ToolResultEvent,
-        ToolStartEvent, ToolsCompleteEvent, UpdateAgentMsg, stream_event,
+        AgentEventMsg, AgentInfo, AskOption, AskQuestion, AskUserEvent, ConversationInfo,
+        CreateAgentMsg, CreateCronMsg, CronInfo, CronList, DaemonStats, HubDone, HubEvent,
+        HubSetupOutput, HubStep, HubWarning, InstallPackageMsg, McpInfo, PackageInfo, ProviderInfo,
+        ProviderPresetInfo, SendMsg, SendResponse, SessionInfo, StreamChunk, StreamEnd,
+        StreamEvent, StreamMsg, StreamStart, StreamThinking, TokenUsage, ToolCallInfo,
+        ToolResultEvent, ToolStartEvent, ToolsCompleteEvent, UpdateAgentMsg, hub_event,
+        stream_event,
     },
 };
 use wcore::{AgentEvent, AgentStep};
@@ -240,17 +242,6 @@ impl<H: Host + 'static> Server for Daemon<H> {
         serde_json::to_string(&config).context("failed to serialize config")
     }
 
-    async fn set_config(&self, config: String) -> Result<()> {
-        let parsed: crate::DaemonConfig =
-            serde_json::from_str(&config).context("invalid DaemonConfig JSON")?;
-        let toml_str =
-            toml::to_string_pretty(&parsed).context("failed to serialize config to TOML")?;
-        let config_path = self.config_dir.join(wcore::paths::CONFIG_FILE);
-        std::fs::write(&config_path, toml_str)
-            .with_context(|| format!("failed to write {}", config_path.display()))?;
-        self.reload().await
-    }
-
     async fn reload(&self) -> Result<()> {
         self.reload().await
     }
@@ -383,41 +374,441 @@ impl<H: Host + 'static> Server for Daemon<H> {
     async fn list_providers(&self) -> Result<Vec<ProviderInfo>> {
         let rt = self.runtime.read().await.clone();
         let entries = rt.model.list()?;
+        let config = self.load_config()?;
         Ok(entries
             .into_iter()
-            .map(|e| ProviderInfo {
-                name: e.name,
-                active: e.active,
+            .map(|e| {
+                let cfg_json = config
+                    .provider
+                    .get(&e.name)
+                    .and_then(|def| serde_json::to_string(def).ok())
+                    .unwrap_or_default();
+                ProviderInfo {
+                    name: e.name,
+                    active: e.active,
+                    config: cfg_json,
+                }
             })
             .collect())
     }
 
-    async fn install_package(&self, req: InstallPackageMsg) -> Result<()> {
-        let branch = if req.branch.is_empty() {
-            None
-        } else {
-            Some(req.branch.as_str())
-        };
-        let path = if req.path.is_empty() {
-            None
+    fn install_package(
+        &self,
+        req: InstallPackageMsg,
+    ) -> impl futures_core::Stream<Item = Result<HubEvent>> + Send {
+        let daemon = self.clone();
+        async_stream::try_stream! {
+            let package = req.package;
+            let branch = req.branch;
+            let path = req.path;
+            let force = req.force;
+
+            // Channel bridge: sync on_step callback → async stream.
+            let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();
+            let handle = tokio::spawn({
+                let branch = branch.clone();
+                let path = path.clone();
+                let package = package.clone();
+                async move {
+                    let branch = if branch.is_empty() { None } else { Some(branch.as_str()) };
+                    let path = if path.is_empty() { None } else { Some(std::path::Path::new(&path)) };
+                    crabhub::package::install(&package, branch, path, force, |msg| {
+                        let _ = tx.send(msg.to_string());
+                    })
+                    .await
+                }
+            });
+
+            // Drain progress messages while install runs.
+            tokio::pin!(handle);
+            let task_result;
+            loop {
+                tokio::select! {
+                    msg = rx.recv() => {
+                        match msg {
+                            Some(m) => yield hub_step(&m),
+                            None => {
+                                // Sender dropped — task finished, await it.
+                                task_result = handle.await;
+                                break;
+                            }
+                        }
+                    }
+                    result = &mut handle => {
+                        rx.close();
+                        while let Some(m) = rx.recv().await {
+                            yield hub_step(&m);
+                        }
+                        task_result = result;
+                        break;
+                    }
+                }
+            }
+            let install_result = task_result
+                .context("install task panicked")??;
+
+            // Reload daemon to pick up new components.
+            yield hub_step("reloading daemon…");
+            daemon.reload().await?;
+
+            // Conflict and auth warnings.
+            let (manifest, mut warnings) = wcore::resolve_manifests(&daemon.config_dir);
+            warnings.extend(wcore::check_skill_conflicts(&manifest.skill_dirs));
+            for w in &warnings {
+                yield hub_warning(w);
+            }
+            for (name, mcp) in &manifest.mcps {
+                if mcp.auth
+                    && !wcore::paths::TOKENS_DIR.join(format!("{name}.json")).exists()
+                {
+                    yield hub_warning(&format!("MCP '{name}' requires authentication"));
+                }
+            }
+
+            yield hub_step("configure env vars in config.toml [env] section if needed");
+
+            // Setup::Prompt — run inference through the runtime.
+            if let Some(wcore::Setup::Prompt { ref prompt }) = install_result.setup {
+                let prompt_text = if prompt.ends_with(".md") {
+                    let repo_dir = install_result.repo_dir.as_ref()
+                        .context("prompt setup requires a repository but none was cloned")?;
+                    let raw = tokio::fs::read_to_string(repo_dir.join(prompt))
+                        .await
+                        .with_context(|| format!("failed to read setup prompt: {prompt}"))?;
+                    raw.replace("<REPO_DIR>", &repo_dir.display().to_string())
+                } else {
+                    prompt.clone()
+                };
+
+                yield hub_step("running setup…");
+                let rt = daemon.runtime.read().await.clone();
+                let session_id = rt
+                    .create_session(wcore::paths::DEFAULT_AGENT, "hub-setup")
+                    .await?;
+                let stream = rt.stream_to(session_id, &prompt_text, "hub-setup");
+                futures_util::pin_mut!(stream);
+                while let Some(event) = stream.next().await {
+                    match event {
+                        AgentEvent::TextDelta(text) => {
+                            yield hub_setup_output(&text);
+                        }
+                        AgentEvent::Done(resp) => {
+                            if let wcore::AgentStopReason::Error(ref e) = resp.stop_reason {
+                                yield hub_done(e);
+                                return;
+                            }
+                            break;
+                        }
+                        _ => {}
+                    }
+                }
+            }
+
+            yield hub_done("");
+        }
+    }
+
+    fn uninstall_package(
+        &self,
+        package: String,
+    ) -> impl futures_core::Stream<Item = Result<HubEvent>> + Send {
+        let daemon = self.clone();
+        async_stream::try_stream! {
+            // Channel bridge for on_step callback.
+            let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();
+            let pkg = package.clone();
+            let handle = tokio::spawn(async move {
+                crabhub::package::uninstall(&pkg, |msg| {
+                    let _ = tx.send(msg.to_string());
+                })
+                .await
+            });
+
+            tokio::pin!(handle);
+            let task_result;
+            loop {
+                tokio::select! {
+                    msg = rx.recv() => {
+                        match msg {
+                            Some(m) => yield hub_step(&m),
+                            None => {
+                                task_result = handle.await;
+                                break;
+                            }
+                        }
+                    }
+                    result = &mut handle => {
+                        rx.close();
+                        while let Some(m) = rx.recv().await {
+                            yield hub_step(&m);
+                        }
+                        task_result = result;
+                        break;
+                    }
+                }
+            }
+            task_result.context("uninstall task panicked")??;
+
+            yield hub_step("reloading daemon…");
+            daemon.reload().await?;
+            yield hub_done("");
+        }
+    }
+
+    async fn list_conversations(
+        &self,
+        agent: String,
+        sender: String,
+    ) -> Result<Vec<ConversationInfo>> {
+        let sessions_dir = self.config_dir.join("sessions");
+        tokio::task::spawn_blocking(move || scan_conversations_all(&sessions_dir, &agent, &sender))
+            .await
+            .context("conversation scan task panicked")
+    }
+
+    async fn list_mcps(&self) -> Result<Vec<McpInfo>> {
+        let mut mcps = Vec::new();
+
+        // Local MCPs from CrabTalk.toml.
+        let manifest_path = self
+            .config_dir
+            .join(wcore::paths::LOCAL_DIR)
+            .join("CrabTalk.toml");
+        if let Ok(Some(manifest)) = wcore::ManifestConfig::load(&manifest_path) {
+            for (name, cfg) in &manifest.mcps {
+                mcps.push(mcp_to_info(name, cfg, "local"));
+            }
+        }
+
+        // Hub-installed MCPs from packages.
+        for (pkg_id, manifest) in scan_package_manifests(&self.config_dir) {
+            for (name, mcp_res) in &manifest.mcps {
+                if mcps.iter().any(|m| m.name == *name) {
+                    continue; // local wins
+                }
+                mcps.push(McpInfo {
+                    name: name.clone(),
+                    command: mcp_res.command.clone(),
+                    args: mcp_res.args.clone(),
+                    env: mcp_res
+                        .env
+                        .iter()
+                        .map(|(k, v)| (k.clone(), v.clone()))
+                        .collect(),
+                    url: mcp_res.url.clone().unwrap_or_default(),
+                    auth: mcp_res.auth,
+                    source: pkg_id.clone(),
+                    auto_restart: mcp_res.auto_restart,
+                });
+            }
+        }
+
+        Ok(mcps)
+    }
+
+    async fn set_local_mcps(&self, mcps: Vec<McpInfo>) -> Result<()> {
+        use toml_edit::{Array, DocumentMut, Item, Table, value};
+
+        let manifest_path = self
+            .config_dir
+            .join(wcore::paths::LOCAL_DIR)
+            .join("CrabTalk.toml");
+        let local_dir = self.config_dir.join(wcore::paths::LOCAL_DIR);
+        std::fs::create_dir_all(&local_dir)
+            .with_context(|| format!("cannot create {}", local_dir.display()))?;
+
+        let content = if manifest_path.exists() {
+            std::fs::read_to_string(&manifest_path)
+                .with_context(|| format!("cannot read {}", manifest_path.display()))?
         } else {
-            Some(std::path::Path::new(&req.path))
+            String::new()
         };
-        crabhub::package::install(&req.package, branch, path, req.force, |msg| {
-            tracing::info!("{msg}");
-        })
-        .await?;
+        let mut doc: DocumentMut = content
+            .parse()
+            .with_context(|| format!("invalid TOML in {}", manifest_path.display()))?;
+
+        doc.remove("mcps");
+        if !mcps.is_empty() {
+            let mut mcps_table = Table::new();
+            for mcp in &mcps {
+                let mut tbl = Table::new();
+                if !mcp.url.is_empty() {
+                    tbl.insert("url", value(&mcp.url));
+                } else {
+                    if !mcp.command.is_empty() {
+                        tbl.insert("command", value(&mcp.command));
+                    }
+                    if !mcp.args.is_empty() {
+                        let mut arr = Array::new();
+                        for a in &mcp.args {
+                            arr.push(a.as_str());
+                        }
+                        tbl.insert("args", Item::Value(arr.into()));
+                    }
+                }
+                if mcp.auth {
+                    tbl.insert("auth", value(true));
+                }
+                if mcp.auto_restart {
+                    tbl.insert("auto_restart", value(true));
+                }
+                if !mcp.env.is_empty() {
+                    let mut env_tbl = Table::new();
+                    for (k, v) in &mcp.env {
+                        env_tbl.insert(k, value(v));
+                    }
+                    tbl.insert("env", Item::Table(env_tbl));
+                }
+                mcps_table.insert(&mcp.name, Item::Table(tbl));
+            }
+            doc.insert("mcps", Item::Table(mcps_table));
+        }
+
+        std::fs::write(&manifest_path, doc.to_string())
+            .with_context(|| format!("failed to write {}", manifest_path.display()))?;
         self.reload().await
     }
 
-    async fn uninstall_package(&self, package: String) -> Result<()> {
-        crabhub::package::uninstall(&package, |msg| {
-            tracing::info!("{msg}");
+    async fn set_provider(&self, name: String, config: String) -> Result<ProviderInfo> {
+        use toml_edit::DocumentMut;
+
+        let def: wcore::ProviderDef =
+            serde_json::from_str(&config).context("invalid ProviderDef JSON")?;
+
+        // Validate before writing: merge with existing providers and check.
+        let daemon_config = self.load_config()?;
+        let mut all_providers = daemon_config.provider;
+        all_providers.insert(name.clone(), def.clone());
+        model::validate_providers(&all_providers)?;
+
+        let toml_value = toml::to_string(&def).context("failed to serialize provider to TOML")?;
+        let provider_doc: DocumentMut = toml_value
+            .parse()
+            .context("failed to parse provider TOML")?;
+
+        let config_path = self.config_dir.join(wcore::paths::CONFIG_FILE);
+        let content = std::fs::read_to_string(&config_path)
+            .with_context(|| format!("cannot read {}", config_path.display()))?;
+        let mut doc: DocumentMut = content
+            .parse()
+            .with_context(|| format!("invalid TOML in {}", config_path.display()))?;
+
+        if doc.get("provider").is_none() {
+            doc.insert("provider", toml_edit::Item::Table(toml_edit::Table::new()));
+        }
+        let provider_table = doc["provider"]
+            .as_table_mut()
+            .context("[provider] is not a table")?;
+
+        let mut entry = toml_edit::Table::new();
+        for (key, value) in provider_doc.as_table().iter() {
+            entry.insert(key, value.clone());
+        }
+        provider_table.insert(&name, toml_edit::Item::Table(entry));
+
+        std::fs::write(&config_path, doc.to_string())
+            .with_context(|| format!("failed to write {}", config_path.display()))?;
+        self.reload().await?;
+
+        // Return the config as actually loaded by the daemon, not the input.
+        let loaded_config = self.load_config()?;
+        let loaded_json = loaded_config
+            .provider
+            .get(&name)
+            .and_then(|def| serde_json::to_string(def).ok())
+            .unwrap_or_default();
+        let rt = self.runtime.read().await.clone();
+        let active = rt.model.provider_name_for(&name).is_some_and(|n| n == name);
+        Ok(ProviderInfo {
+            name,
+            active,
+            config: loaded_json,
         })
-        .await?;
+    }
+
+    async fn delete_provider(&self, name: String) -> Result<()> {
+        use toml_edit::DocumentMut;
+
+        let config_path = self.config_dir.join(wcore::paths::CONFIG_FILE);
+        let content = std::fs::read_to_string(&config_path)
+            .with_context(|| format!("cannot read {}", config_path.display()))?;
+        let mut doc: DocumentMut = content
+            .parse()
+            .with_context(|| format!("invalid TOML in {}", config_path.display()))?;
+
+        let removed = doc
+            .get_mut("provider")
+            .and_then(|v| v.as_table_mut())
+            .and_then(|t| t.remove(&name))
+            .is_some();
+        if !removed {
+            anyhow::bail!("provider '{name}' not found");
+        }
+
+        std::fs::write(&config_path, doc.to_string())
+            .with_context(|| format!("failed to write {}", config_path.display()))?;
         self.reload().await
     }
 
+    async fn set_active_model(&self, model: String) -> Result<()> {
+        use toml_edit::{DocumentMut, Item, Table, value};
+
+        // Validate model exists in some provider.
+        let daemon_config = self.load_config()?;
+        let model_exists = daemon_config
+            .provider
+            .values()
+            .any(|def| def.models.iter().any(|m| m == &model));
+        if !model_exists {
+            anyhow::bail!("model '{model}' not found in any provider");
+        }
+
+        let config_path = self.config_dir.join(wcore::paths::CONFIG_FILE);
+        let content = std::fs::read_to_string(&config_path)
+            .with_context(|| format!("cannot read {}", config_path.display()))?;
+        let mut doc: DocumentMut = content
+            .parse()
+            .with_context(|| format!("invalid TOML in {}", config_path.display()))?;
+
+        if doc.get("system").is_none() {
+            doc.insert("system", Item::Table(Table::new()));
+        }
+        if let Some(system) = doc.get_mut("system").and_then(|s| s.as_table_mut()) {
+            if system.get("crab").is_none() {
+                system.insert("crab", Item::Table(Table::new()));
+            }
+            if let Some(crab) = system.get_mut("crab").and_then(|w| w.as_table_mut()) {
+                crab.insert("model", value(&model));
+            }
+        }
+
+        std::fs::write(&config_path, doc.to_string())
+            .with_context(|| format!("failed to write {}", config_path.display()))?;
+        self.reload().await
+    }
+
+    async fn list_provider_presets(&self) -> Result<Vec<ProviderPresetInfo>> {
+        Ok(wcore::config::PROVIDER_PRESETS
+            .iter()
+            .map(|p| ProviderPresetInfo {
+                name: p.name.to_string(),
+                kind: wcore::protocol::message::ProtoProviderKind::from(p.kind).into(),
+                base_url: p.base_url.to_string(),
+                fixed_base_url: p.fixed_base_url.to_string(),
+                default_model: p.default_model.to_string(),
+            })
+            .collect())
+    }
+
+    async fn list_skills(&self) -> Result<Vec<String>> {
+        let (manifest, _) = wcore::resolve_manifests(&self.config_dir);
+        let mut names = std::collections::BTreeSet::new();
+        for dir in &manifest.skill_dirs {
+            names.extend(wcore::scan_skill_names(dir));
+        }
+        Ok(names.into_iter().collect())
+    }
+
     async fn list_packages(&self) -> Result<Vec<PackageInfo>> {
         let mut result: Vec<PackageInfo> = scan_package_manifests(&self.config_dir)
             .into_iter()
@@ -638,6 +1029,194 @@ impl<H: Host + 'static> Daemon<H> {
     }
 }
 
+fn hub_step(message: &str) -> HubEvent {
+    HubEvent {
+        event: Some(hub_event::Event::Step(HubStep {
+            message: message.to_string(),
+        })),
+    }
+}
+
+fn hub_warning(message: &str) -> HubEvent {
+    HubEvent {
+        event: Some(hub_event::Event::Warning(HubWarning {
+            message: message.to_string(),
+        })),
+    }
+}
+
+fn hub_setup_output(content: &str) -> HubEvent {
+    HubEvent {
+        event: Some(hub_event::Event::SetupOutput(HubSetupOutput {
+            content: content.to_string(),
+        })),
+    }
+}
+
+fn hub_done(error: &str) -> HubEvent {
+    HubEvent {
+        event: Some(hub_event::Event::Done(HubDone {
+            error: error.to_string(),
+        })),
+    }
+}
+
+/// Scan session files and return conversation info.
+///
+/// If `agent` and `sender` are both empty, returns all conversations.
+/// Otherwise, filters to the given identity.
+fn scan_conversations_all(
+    sessions_dir: &std::path::Path,
+    agent: &str,
+    sender: &str,
+) -> Vec<ConversationInfo> {
+    let Ok(entries) = std::fs::read_dir(sessions_dir) else {
+        return Vec::new();
+    };
+
+    let filter_prefix = if !agent.is_empty() && !sender.is_empty() {
+        Some(format!("{}_{}_", agent, wcore::sender_slug(sender)))
+    } else {
+        None
+    };
+
+    let today = chrono::Local::now().date_naive();
+    let mut results = Vec::new();
+
+    for file in entries.flatten() {
+        let path = file.path();
+        if path.is_dir() {
+            continue;
+        }
+        let name = file.file_name();
+        let Some(name) = name.to_str() else { continue };
+        if !name.ends_with(".jsonl") {
+            continue;
+        }
+
+        if let Some(ref prefix) = filter_prefix
+            && !name.starts_with(prefix)
+        {
+            continue;
+        }
+
+        let Some((file_agent, file_sender, seq, title)) = parse_session_filename(name) else {
+            continue;
+        };
+
+        if filter_prefix.is_none() && !agent.is_empty() && file_agent != agent {
+            continue;
+        }
+
+        let mtime = file
+            .metadata()
+            .and_then(|m| m.modified())
+            .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
+        let (alive_secs, message_count) = read_session_file_stats(&path);
+        let date = mtime_to_label(mtime, today);
+
+        results.push((
+            mtime,
+            ConversationInfo {
+                agent: file_agent,
+                sender: file_sender,
+                seq,
+                title,
+                file_path: path.to_string_lossy().into_owned(),
+                message_count,
+                alive_secs,
+                date,
+            },
+        ));
+    }
+
+    // Sort by mtime descending (most recently active first).
+    results.sort_by(|a, b| b.0.cmp(&a.0));
+    results.into_iter().map(|(_, info)| info).collect()
+}
+
+/// Parse a session filename into (agent, sender, seq, title).
+///
+/// Format: `{agent}_{sender}_{seq}[_{title}].jsonl`
+fn parse_session_filename(name: &str) -> Option<(String, String, u32, String)> {
+    let stem = name.strip_suffix(".jsonl")?;
+    let parts: Vec<&str> = stem.split('_').collect();
+    if parts.len() < 3 {
+        return None;
+    }
+    // Find the first numeric part after position 1 (that's the seq).
+    for i in 2..parts.len() {
+        if !parts[i].is_empty() && parts[i].chars().all(|c| c.is_ascii_digit()) {
+            let agent = parts[0].to_string();
+            let sender = parts[1..i].join("_");
+            let seq: u32 = parts[i].parse().ok()?;
+            let title = if i + 1 < parts.len() {
+                parts[i + 1..].join("_")
+            } else {
+                String::new()
+            };
+            return Some((agent, sender, seq, title));
+        }
+    }
+    None
+}
+
+/// Read uptime_secs from meta line and count message lines.
+fn read_session_file_stats(path: &std::path::Path) -> (u64, u64) {
+    use std::io::{BufRead, BufReader};
+
+    let Ok(file) = std::fs::File::open(path) else {
+        return (0, 0);
+    };
+    let reader = BufReader::new(file);
+    let mut lines = reader.lines();
+
+    let uptime = lines
+        .next()
+        .and_then(|l| l.ok())
+        .and_then(|l| {
+            let v: serde_json::Value = serde_json::from_str(&l).ok()?;
+            v.get("uptime_secs")?.as_u64()
+        })
+        .unwrap_or(0);
+
+    let msg_count = lines
+        .map_while(|l| l.ok())
+        .filter(|l| !l.trim().is_empty() && !l.contains("\"compact\""))
+        .count() as u64;
+
+    (uptime, msg_count)
+}
+
+/// Convert a file mtime to a human-readable date label.
+fn mtime_to_label(mtime: std::time::SystemTime, today: chrono::NaiveDate) -> String {
+    let date = chrono::DateTime::<chrono::Local>::from(mtime).date_naive();
+    if date == today {
+        "Today".to_string()
+    } else if date == today - chrono::Duration::days(1) {
+        "Yesterday".to_string()
+    } else {
+        date.format("%Y-%m-%d").to_string()
+    }
+}
+
+fn mcp_to_info(name: &str, cfg: &wcore::McpServerConfig, source: &str) -> McpInfo {
+    McpInfo {
+        name: name.to_string(),
+        command: cfg.command.clone(),
+        args: cfg.args.clone(),
+        env: cfg
+            .env
+            .iter()
+            .map(|(k, v)| (k.clone(), v.clone()))
+            .collect(),
+        url: cfg.url.clone().unwrap_or_default(),
+        auth: cfg.auth,
+        source: source.to_string(),
+        auto_restart: cfg.auto_restart,
+    }
+}
+
 fn cron_entry_to_info(e: &CronEntry) -> CronInfo {
     CronInfo {
         id: e.id,
diff --git a/crates/model/src/convert.rs b/crates/model/src/convert.rs
--- a/crates/model/src/convert.rs
+++ b/crates/model/src/convert.rs
@@ -74,12 +74,18 @@ fn to_ct_message(msg: &Message) -> CtMessage {
         Some(msg.reasoning_content.clone())
     };
 
+    let name = if msg.name.is_empty() {
+        None
+    } else {
+        Some(msg.name.clone())
+    };
+
     CtMessage {
         role: msg.role.clone(),
         content,
         tool_calls,
         tool_call_id,
-        name: None,
+        name,
         reasoning_content,
         extra: Default::default(),
     }
diff --git a/crates/model/src/provider.rs b/crates/model/src/provider.rs
--- a/crates/model/src/provider.rs
+++ b/crates/model/src/provider.rs
@@ -49,7 +49,7 @@ pub fn build_provider(def: &ProviderDef, model: &str, client: reqwest::Client) -
     let mut inner = CtProvider::from(&config);
 
     // Apply crabtalk-specific base_url normalization (strip endpoint suffixes).
-    if let CtProvider::OpenAiCompat {
+    if let CtProvider::Openai {
         ref mut base_url, ..
     } = inner
     {
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
