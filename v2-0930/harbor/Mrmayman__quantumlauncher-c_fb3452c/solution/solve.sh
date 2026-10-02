#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/Cargo.toml b/Cargo.toml
--- a/Cargo.toml
+++ b/Cargo.toml
@@ -16,7 +16,7 @@ default-members = ["quantum_launcher"]
 resolver = "2"
 
 [workspace.dependencies]
-serde = { version = "1", features = ["derive"] }
+serde = { version = "1", features = ["derive", "rc"] }
 serde_json = "1"
 semver = "1"
 dirs = "6"
diff --git a/crates/ql_core/src/jarmod/json.rs b/crates/ql_core/src/jarmod/json.rs
--- a/crates/ql_core/src/jarmod/json.rs
+++ b/crates/ql_core/src/jarmod/json.rs
@@ -1,4 +1,4 @@
-use crate::{InstanceSelection, IntoIoError, JsonFileError};
+use crate::{Instance, IntoIoError, JsonFileError};
 use crate::{IntoJsonError, IoError, err, file_utils};
 use serde::{Deserialize, Serialize};
 
@@ -8,7 +8,7 @@ pub struct JarMods {
 }
 
 impl JarMods {
-    pub async fn read(instance: &InstanceSelection) -> Result<Self, JsonFileError> {
+    pub async fn read(instance: &Instance) -> Result<Self, JsonFileError> {
         let path = instance.get_instance_path().join("jarmods.json");
 
         if path.is_file() {
@@ -23,7 +23,7 @@ impl JarMods {
         }
     }
 
-    pub async fn save(&mut self, instance: &InstanceSelection) -> Result<(), JsonFileError> {
+    pub async fn save(&mut self, instance: &Instance) -> Result<(), JsonFileError> {
         self.trim(instance);
         if let Err(err) = self.expand(instance).await {
             err!("While expanding jarmods.json with new entries: {err}");
@@ -35,12 +35,12 @@ impl JarMods {
         Ok(())
     }
 
-    fn trim(&mut self, instance: &InstanceSelection) {
+    fn trim(&mut self, instance: &Instance) {
         let path = instance.get_instance_path().join("jarmods");
         self.mods.retain(|n| path.join(&n.filename).is_file());
     }
 
-    pub async fn expand(&mut self, instance: &InstanceSelection) -> Result<(), IoError> {
+    pub async fn expand(&mut self, instance: &Instance) -> Result<(), IoError> {
         let path = instance.get_instance_path().join("jarmods");
         if !path.is_dir() {
             tokio::fs::create_dir_all(&path).await.path(path)?;
diff --git a/crates/ql_core/src/jarmod/mod.rs b/crates/ql_core/src/jarmod/mod.rs
--- a/crates/ql_core/src/jarmod/mod.rs
+++ b/crates/ql_core/src/jarmod/mod.rs
@@ -19,7 +19,7 @@
 use std::path::{Path, PathBuf, StripPrefixError};
 
 use crate::{
-    InstanceSelection, IntoIoError, IoError, JsonError, JsonFileError,
+    Instance, IntoIoError, IoError, JsonError, JsonFileError,
     file_utils::{extract_zip_archive, zip_directory_to_bytes},
     get_jar_path,
     json::{InstanceConfigJson, JsonOptifine, VersionDetails},
@@ -31,7 +31,7 @@ mod json;
 
 pub use json::{JarMod, JarMods};
 
-pub async fn remove(instance: &InstanceSelection, filename: &str) -> Result<(), JsonFileError> {
+pub async fn remove(instance: &Instance, filename: &str) -> Result<(), JsonFileError> {
     let mut jarmods = JarMods::read(instance).await?;
 
     if let Some(idx) = jarmods
@@ -52,11 +52,7 @@ pub async fn remove(instance: &InstanceSelection, filename: &str) -> Result<(),
     Ok(())
 }
 
-pub async fn insert(
-    instance: InstanceSelection,
-    bytes: Vec<u8>,
-    name: &str,
-) -> Result<(), JsonFileError> {
+pub async fn insert(instance: Instance, bytes: Vec<u8>, name: &str) -> Result<(), JsonFileError> {
     let filename = format!("{name}.zip");
     let mut jarmods = JarMods::read(&instance).await?;
     if let Some(entry) = jarmods.mods.iter_mut().find(|n| n.filename == filename) {
@@ -85,7 +81,7 @@ pub async fn insert(
     Ok(())
 }
 
-pub async fn build(instance: &InstanceSelection) -> Result<PathBuf, JarModError> {
+pub async fn build(instance: &Instance) -> Result<PathBuf, JarModError> {
     let instance_dir = instance.get_instance_path();
     let jarmods_dir = instance_dir.join("jarmods");
 
@@ -135,7 +131,7 @@ pub async fn build(instance: &InstanceSelection) -> Result<PathBuf, JarModError>
 }
 
 async fn get_original_jar(
-    instance: &InstanceSelection,
+    instance: &Instance,
     instance_dir: &Path,
 ) -> Result<PathBuf, JarModError> {
     let json = VersionDetails::load(instance).await?;
diff --git a/crates/ql_core/src/json/instance_config.rs b/crates/ql_core/src/json/instance_config.rs
--- a/crates/ql_core/src/json/instance_config.rs
+++ b/crates/ql_core/src/json/instance_config.rs
@@ -6,7 +6,7 @@ use std::{
 use serde::{Deserialize, Serialize};
 
 use crate::{
-    DEFAULT_RAM_MB_FOR_INSTANCE, InstanceSelection, IntoIoError, IntoJsonError, JsonFileError,
+    DEFAULT_RAM_MB_FOR_INSTANCE, Instance, InstanceKind, IntoIoError, IntoJsonError, JsonFileError,
     Loader,
 };
 
@@ -103,7 +103,7 @@ pub struct InstanceConfigJson {
 
 impl InstanceConfigJson {
     #[must_use]
-    pub fn new(is_server: bool, is_classic_server: bool, version_info: VersionInfo) -> Self {
+    pub fn new(kind: InstanceKind, is_classic_server: bool, version_info: VersionInfo) -> Self {
         #[allow(deprecated)]
         Self {
             mod_type: Loader::Vanilla,
@@ -114,7 +114,7 @@ impl InstanceConfigJson {
             java_args: None,
             game_args: None,
 
-            is_server: Some(is_server),
+            is_server: Some(kind.is_server()),
             is_classic_server: Some(is_classic_server),
 
             omniarchive: None,
@@ -159,7 +159,7 @@ impl InstanceConfigJson {
     /// # Errors
     /// - `config.json` file couldn't be loaded
     /// - `config.json` couldn't be parsed into valid JSON
-    pub async fn read(instance: &InstanceSelection) -> Result<Self, JsonFileError> {
+    pub async fn read(instance: &Instance) -> Result<Self, JsonFileError> {
         Self::read_from_dir(&instance.get_instance_path()).await
     }
 
@@ -183,7 +183,7 @@ impl InstanceConfigJson {
     /// # Errors
     /// - `config.json` file couldn't be written to
     /// - `self` couldn't be serialized into valid JSON
-    pub async fn save(&self, instance: &InstanceSelection) -> Result<(), JsonFileError> {
+    pub async fn save(&self, instance: &Instance) -> Result<(), JsonFileError> {
         self.save_to_dir(&instance.get_instance_path()).await
     }
 
diff --git a/crates/ql_core/src/json/version.rs b/crates/ql_core/src/json/version.rs
--- a/crates/ql_core/src/json/version.rs
+++ b/crates/ql_core/src/json/version.rs
@@ -5,9 +5,7 @@ use chrono::DateTime;
 use serde::{Deserialize, Serialize};
 use serde_json::Value;
 
-use crate::{
-    InstanceSelection, IntoIoError, IntoJsonError, JsonFileError, OS_NAME, constants::*, err, pt,
-};
+use crate::{Instance, IntoIoError, IntoJsonError, JsonFileError, OS_NAME, constants::*, err, pt};
 
 pub const V_PRECLASSIC_LAST: &str = "2009-05-16T11:48:00+00:00";
 pub const V_OFFICIAL_FABRIC_SUPPORT: &str = "2018-10-24T10:52:16+00:00";
@@ -68,7 +66,7 @@ impl VersionDetails {
     /// # Errors
     /// - `details.json` file couldn't be loaded
     /// - `details.json` couldn't be parsed into valid JSON
-    pub async fn load(instance: &InstanceSelection) -> Result<Self, JsonFileError> {
+    pub async fn load(instance: &Instance) -> Result<Self, JsonFileError> {
         Self::load_from_path(&instance.get_instance_path()).await
     }
 
@@ -90,7 +88,7 @@ impl VersionDetails {
 
     /// Saves the Minecraft instance JSON to disk
     /// to a specific [`InstanceSelection`] (Minecraft installation).
-    pub async fn save(&self, instance: &InstanceSelection) -> Result<(), JsonFileError> {
+    pub async fn save(&self, instance: &Instance) -> Result<(), JsonFileError> {
         self.save_to_dir(&instance.get_instance_path()).await
     }
 
@@ -105,10 +103,7 @@ impl VersionDetails {
         Ok(())
     }
 
-    pub async fn apply_tweaks(
-        &mut self,
-        instance: &InstanceSelection,
-    ) -> Result<(), JsonFileError> {
+    pub async fn apply_tweaks(&mut self, instance: &Instance) -> Result<(), JsonFileError> {
         let patches_path = instance.get_instance_path().join("patches");
         if !patches_path.is_dir() {
             return Ok(());
diff --git a/crates/ql_core/src/lib.rs b/crates/ql_core/src/lib.rs
--- a/crates/ql_core/src/lib.rs
+++ b/crates/ql_core/src/lib.rs
@@ -246,94 +246,94 @@ where
 }
 
 #[derive(Clone, Debug, Hash, PartialEq, Eq)]
-pub enum InstanceSelection {
-    Instance(String),
-    Server(String),
+pub struct Instance {
+    pub name: Arc<str>,
+    pub kind: InstanceKind,
 }
 
-impl InstanceSelection {
+impl Instance {
     #[must_use]
-    pub fn new(name: &str, is_server: bool) -> Self {
-        if is_server {
-            Self::Server(name.to_owned())
-        } else {
-            Self::Instance(name.to_owned())
+    pub fn new(name: &str, kind: InstanceKind) -> Self {
+        Self {
+            name: Arc::from(name),
+            kind,
         }
     }
 
+    #[must_use]
+    pub fn client(name: &str) -> Self {
+        Self::new(name, InstanceKind::Client)
+    }
+
+    #[must_use]
+    pub fn server(name: &str) -> Self {
+        Self::new(name, InstanceKind::Server)
+    }
+
     /// Gets the path where launcher-specific things are stored.
     ///
     /// - Instances: `QuantumLauncher/instances/<NAME>/`
     /// - Servers: `QuantumLauncher/servers/<Name>/` (identical to `dot_minecraft_path`)
     #[must_use]
     pub fn get_instance_path(&self) -> PathBuf {
-        match self {
-            Self::Instance(name) => LAUNCHER_DIR.join("instances").join(name),
-            Self::Server(name) => LAUNCHER_DIR.join("servers").join(name),
-        }
+        let name = &*self.name;
+        self.kind.get_root_directory().join(name)
     }
 
-    /// Gets the path where files used by the game itself are stored,
-    /// also called the `.minecraft` folder.
+    /// Gets the path where files used by the game itself are stored.
+    ///
+    /// For clients this is the `.minecraft` folder. It can vary,
+    /// the only requirement is that it must be equal to, or a subdirectory of,
+    /// the instance path ([`Instance::get_instance_path`]).
     ///
     /// - Instances: `QuantumLauncher/instances/<NAME>/.minecraft/`
     /// - Servers: `QuantumLauncher/servers/<NAME>/` (identical to `instance_path`)
     #[must_use]
     pub fn get_dot_minecraft_path(&self) -> PathBuf {
-        match self {
-            InstanceSelection::Instance(name) => {
-                LAUNCHER_DIR.join("instances").join(name).join(".minecraft")
-            }
-            InstanceSelection::Server(name) => LAUNCHER_DIR.join("servers").join(name),
+        let name = &*self.name;
+        match self.kind {
+            InstanceKind::Client => LAUNCHER_DIR.join("instances").join(name).join(".minecraft"),
+            InstanceKind::Server => LAUNCHER_DIR.join("servers").join(name),
         }
     }
 
     #[must_use]
     pub fn get_name(&self) -> &str {
-        match self {
-            Self::Instance(name) | Self::Server(name) => name,
-        }
+        &*self.name
     }
 
     #[must_use]
     pub const fn is_server(&self) -> bool {
-        matches!(self, Self::Server(_))
-    }
-
-    pub fn set_name(&mut self, name: String) {
-        match self {
-            Self::Instance(n) | Self::Server(n) => *n = name,
-        }
+        self.kind.is_server()
     }
 
     #[must_use]
     pub fn get_pair(&self) -> (&str, bool) {
         (self.get_name(), self.is_server())
     }
-
-    #[must_use]
-    pub fn kind(&self) -> InstanceKind {
-        match self {
-            Self::Instance(_) => InstanceKind::Client,
-            Self::Server(_) => InstanceKind::Server,
-        }
-    }
 }
 
-// TODO: Refactor the entire launcher to use this
-// instead of `is_server: bool`
 #[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq, Hash)]
 #[serde(rename_all = "snake_case")]
 pub enum InstanceKind {
-    Client,
     Server,
+    #[serde(other)]
+    Client,
 }
 
 impl InstanceKind {
     #[must_use]
-    pub fn is_server(self) -> bool {
+    pub const fn is_server(self) -> bool {
         matches!(self, Self::Server)
     }
+
+    pub fn get_root_directory(&self) -> PathBuf {
+        let name = match self {
+            InstanceKind::Client => "instances",
+            InstanceKind::Server => "servers",
+        };
+        LAUNCHER_DIR.join(name)
+    }
 }
 
 /// A struct representing information about a Minecraft version
@@ -548,7 +548,7 @@ pub enum OptifineUniqueVersion {
 
 impl OptifineUniqueVersion {
     #[must_use]
-    pub async fn get(instance: &InstanceSelection) -> Option<Self> {
+    pub async fn get(instance: &Instance) -> Option<Self> {
         VersionDetails::load(instance)
             .await
             .ok()
@@ -643,7 +643,7 @@ pub async fn find_forge_shim_file(dir: &Path) -> Option<PathBuf> {
 #[derive(Debug, Clone)]
 pub struct LaunchedProcess {
     pub child: Arc<tokio::sync::Mutex<Child>>,
-    pub instance: InstanceSelection,
+    pub instance: Instance,
     /// Present because Minecraft classic servers
     /// have some special properties
     ///
@@ -653,7 +653,7 @@ pub struct LaunchedProcess {
     pub is_classic_server: bool,
 }
 
-type ReadLogOut = Result<(ExitStatus, InstanceSelection, Option<Diagnostic>), ReadError>;
+type ReadLogOut = Result<(ExitStatus, Instance, Option<Diagnostic>), ReadError>;
 
 impl LaunchedProcess {
     /// Reads log output from the game process.
diff --git a/crates/ql_core/src/read_log.rs b/crates/ql_core/src/read_log.rs
--- a/crates/ql_core/src/read_log.rs
+++ b/crates/ql_core/src/read_log.rs
@@ -16,7 +16,7 @@ use tokio::{
 };
 
 use crate::{
-    InstanceSelection, IoError, JsonError, JsonFileError, REDACT_SENSITIVE_INFO, err,
+    Instance, InstanceKind, IoError, JsonError, JsonFileError, REDACT_SENSITIVE_INFO, err,
     json::VersionDetails, print::REDACTION_USERNAME,
 };
 
@@ -31,9 +31,9 @@ use crate::{
 pub(crate) async fn read_logs(
     child: Arc<Mutex<Child>>,
     sender: Option<Sender<LogLine>>,
-    instance: InstanceSelection,
+    instance: Instance,
     censors: Vec<String>,
-) -> Result<(ExitStatus, InstanceSelection, Option<Diagnostic>), ReadError> {
+) -> Result<(ExitStatus, Instance, Option<Diagnostic>), ReadError> {
     let r = {
         let mut c = child.lock().await;
         (c.stdout.take(), c.stderr.take())
@@ -42,7 +42,7 @@ pub(crate) async fn read_logs(
         return Ok((ExitStatus::default(), instance, None));
     };
 
-    let uses_xml = !instance.is_server() && is_xml(instance.get_name()).await?;
+    let uses_xml = matches!(instance.kind, InstanceKind::Client) && is_xml(&instance).await?;
 
     let stdout = BufReader::new(stdout);
     let stderr = BufReader::new(stderr);
@@ -214,8 +214,8 @@ fn xml_parse(
     }
 }
 
-async fn is_xml(instance_name: &str) -> Result<bool, ReadError> {
-    let json = VersionDetails::load(&InstanceSelection::Instance(instance_name.to_owned())).await?;
+async fn is_xml(instance: &Instance) -> Result<bool, ReadError> {
+    let json = VersionDetails::load(&instance).await?;
 
     Ok(json.logging.is_some())
 }
diff --git a/crates/ql_instances/src/download/downloader.rs b/crates/ql_instances/src/download/downloader.rs
--- a/crates/ql_instances/src/download/downloader.rs
+++ b/crates/ql_instances/src/download/downloader.rs
@@ -311,8 +311,11 @@ impl GameDownloader {
     }
 
     pub async fn create_config_json(&self) -> Result<(), DownloadError> {
-        let config_json =
-            InstanceConfigJson::new(false, false, VersionInfo::new(&self.version_json.id));
+        let config_json = InstanceConfigJson::new(
+            ql_core::InstanceKind::Client,
+            false,
+            VersionInfo::new(&self.version_json.id),
+        );
         let config_json = serde_json::to_string(&config_json).json_to()?;
 
         let config_json_path = self.instance_dir.join("config.json");
diff --git a/crates/ql_instances/src/download/mod.rs b/crates/ql_instances/src/download/mod.rs
--- a/crates/ql_instances/src/download/mod.rs
+++ b/crates/ql_instances/src/download/mod.rs
@@ -1,7 +1,7 @@
 use std::sync::mpsc::Sender;
 
 use ql_core::{
-    DownloadProgress, InstanceSelection, IntoIoError, IntoStringError, LAUNCHER_DIR,
+    DownloadProgress, Instance, IntoIoError, IntoStringError, LAUNCHER_DIR,
     LAUNCHER_VERSION_NAME, ListEntry, info, json::VersionDetails, sanitize_instance_name,
 };
 
@@ -93,7 +93,7 @@ pub async fn create_instance(
 }
 
 pub async fn repeat_stage(
-    instance: InstanceSelection,
+    instance: Instance,
     stage: DownloadProgress,
     sender: Option<Sender<DownloadProgress>>,
 ) -> Result<(), String> {
diff --git a/crates/ql_instances/src/instance/launch/launcher.rs b/crates/ql_instances/src/instance/launch/launcher.rs
--- a/crates/ql_instances/src/instance/launch/launcher.rs
+++ b/crates/ql_instances/src/instance/launch/launcher.rs
@@ -4,7 +4,7 @@ use crate::{
     jarmod,
 };
 use ql_core::{
-    CLASSPATH_SEPARATOR, GenericProgress, InstanceSelection, IntoIoError, IntoJsonError, IoError,
+    CLASSPATH_SEPARATOR, GenericProgress, Instance, IntoIoError, IntoJsonError, IoError,
     JsonFileError, LAUNCHER_DIR, Loader, err,
     file_utils::{self, exists},
     info,
@@ -20,15 +20,15 @@ use std::{
     io::ErrorKind,
     path::{Path, PathBuf},
     process::Stdio,
-    sync::mpsc::Sender,
+    sync::{Arc, mpsc::Sender},
 };
 use tokio::process::Command;
 
 use super::{error::GameLaunchError, replace_var};
 
 pub struct GameLauncher {
     username: String,
-    instance_name: String,
+    instance_name: Arc<str>,
 
     /// If Java isn't installed, it will be auto-installed by the launcher.
     /// This field allows you to send progress updates
@@ -52,7 +52,7 @@ pub struct GameLauncher {
 
 impl GameLauncher {
     pub async fn new(
-        instance_name: String,
+        instance_name: Arc<str>,
         username: String,
         java_install_progress_sender: Option<Sender<GenericProgress>>,
         global_settings: Option<GlobalSettings>,
@@ -74,7 +74,7 @@ impl GameLauncher {
             c => c?,
         };
 
-        let instance = InstanceSelection::Instance(instance_name.clone());
+        let instance = Instance::client(&instance_name);
         let mut version_json = VersionDetails::load(&instance).await?;
         version_json.apply_tweaks(&instance).await?;
 
@@ -501,7 +501,7 @@ impl GameLauncher {
         // classpath_entries is a HashSet that determines if an overridden
         // version of a library has already been loaded.
 
-        let instance = InstanceSelection::Instance(self.instance_name.clone());
+        let instance = Instance::client(&self.instance_name);
         let jar_path = jarmod::build(&instance).await?;
         debug_assert!(
             jar_path.is_file(),
diff --git a/crates/ql_instances/src/instance/launch/mod.rs b/crates/ql_instances/src/instance/launch/mod.rs
--- a/crates/ql_instances/src/instance/launch/mod.rs
+++ b/crates/ql_instances/src/instance/launch/mod.rs
@@ -1,8 +1,6 @@
 use crate::auth::AccountData;
 use error::GameLaunchError;
-use ql_core::{
-    GenericProgress, InstanceSelection, LaunchedProcess, REDACT_SENSITIVE_INFO, err, info,
-};
+use ql_core::{GenericProgress, Instance, LaunchedProcess, REDACT_SENSITIVE_INFO, err, info};
 use std::sync::{Arc, mpsc::Sender};
 use tokio::sync::Mutex;
 
@@ -25,7 +23,7 @@ use ql_core::json::GlobalSettings;
 ///   like window width/height, etc.
 /// - `extra_java_args`
 pub async fn launch(
-    instance_name: String,
+    instance_name: Arc<str>,
     username: String,
     java_install_progress_sender: Option<Sender<GenericProgress>>,
     auth: Option<AccountData>,
@@ -106,7 +104,7 @@ pub async fn launch(
 
     Ok(LaunchedProcess {
         child: Arc::new(Mutex::new(child)),
-        instance: InstanceSelection::Instance(instance_name),
+        instance: Instance::client(&instance_name),
         is_classic_server: false,
     })
 }
diff --git a/crates/ql_instances/src/instance/mod.rs b/crates/ql_instances/src/instance/mod.rs
--- a/crates/ql_instances/src/instance/mod.rs
+++ b/crates/ql_instances/src/instance/mod.rs
@@ -3,9 +3,9 @@ pub mod list_versions;
 mod migrate;
 
 pub mod notes {
-    use ql_core::{InstanceSelection, IntoIoError, IoError};
+    use ql_core::{Instance, IntoIoError, IoError};
 
-    pub async fn read(instance: InstanceSelection) -> Result<String, IoError> {
+    pub async fn read(instance: Instance) -> Result<String, IoError> {
         let path = instance.get_instance_path().join("notes.md");
         match tokio::fs::read_to_string(&path).await {
             Ok(contents) => Ok(contents),
@@ -14,7 +14,7 @@ pub mod notes {
         }
     }
 
-    pub async fn write(instance: InstanceSelection, notes: String) -> Result<(), IoError> {
+    pub async fn write(instance: Instance, notes: String) -> Result<(), IoError> {
         let path = instance.get_instance_path().join("notes.md");
         tokio::fs::write(&path, &notes).await.path(&path)
     }
diff --git a/crates/ql_mod_manager/src/loaders/fabric/mod.rs b/crates/ql_mod_manager/src/loaders/fabric/mod.rs
--- a/crates/ql_mod_manager/src/loaders/fabric/mod.rs
+++ b/crates/ql_mod_manager/src/loaders/fabric/mod.rs
@@ -4,8 +4,8 @@ use std::{
 };
 
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoIoError, IntoJsonError, LAUNCHER_DIR, Loader, do_jobs,
-    download,
+    GenericProgress, Instance, InstanceKind, IntoIoError, IntoJsonError, LAUNCHER_DIR, Loader,
+    do_jobs, download,
     file_utils::exists,
     info,
     json::{FabricJSON, V_1_12_2, VersionDetails, instance_config::ModTypeInfo},
@@ -35,7 +35,7 @@ const CURSED_LEGACY_JSON: &str =
 
 pub async fn install_server(
     loader_version: String,
-    server_name: String,
+    server_name: &str,
     progress: Option<&Sender<GenericProgress>>,
     backend: BackendType,
 ) -> Result<(), FabricInstallError> {
@@ -154,7 +154,7 @@ async fn download_library(
 
 pub async fn install_client(
     loader_version: String,
-    instance_name: String,
+    instance_name: &str,
     progress: Option<&Sender<GenericProgress>>,
     backend: BackendType,
 ) -> Result<(), FabricInstallError> {
@@ -316,7 +316,7 @@ fn send_progress(
 /// - `backend` - Backend fabric implementation (Fabric/Quilt/Babric/OrnitheMC/...)
 pub async fn install(
     loader_version: Option<String>,
-    instance: InstanceSelection,
+    instance: Instance,
     progress: Option<&Sender<GenericProgress>>,
     mut backend: BackendType,
 ) -> Result<(), FabricInstallError> {
@@ -333,10 +333,9 @@ pub async fn install(
             .version
             .clone()
     };
-    match instance {
-        InstanceSelection::Instance(n) => {
-            install_client(loader_version, n, progress, backend).await
-        }
-        InstanceSelection::Server(n) => install_server(loader_version, n, progress, backend).await,
+    let name = instance.get_name();
+    match instance.kind {
+        InstanceKind::Client => install_client(loader_version, name, progress, backend).await,
+        InstanceKind::Server => install_server(loader_version, name, progress, backend).await,
     }
 }
diff --git a/crates/ql_mod_manager/src/loaders/fabric/uninstall.rs b/crates/ql_mod_manager/src/loaders/fabric/uninstall.rs
--- a/crates/ql_mod_manager/src/loaders/fabric/uninstall.rs
+++ b/crates/ql_mod_manager/src/loaders/fabric/uninstall.rs
@@ -1,7 +1,7 @@
 use std::path::Path;
 
 use ql_core::{
-    InstanceSelection, IntoIoError, IntoJsonError, IoError, LAUNCHER_DIR, Loader, err,
+    Instance, InstanceKind, IntoIoError, IntoJsonError, IoError, LAUNCHER_DIR, Loader, err,
     file_utils::exists, info, json::FabricJSON,
 };
 
@@ -18,7 +18,7 @@ async fn delete(server_dir: &Path, name: &str) -> Result<(), IoError> {
     Ok(())
 }
 
-async fn uninstall_server(server_name: String) -> Result<(), FabricInstallError> {
+async fn uninstall_server(server_name: &str) -> Result<(), FabricInstallError> {
     let server_dir = LAUNCHER_DIR.join("servers").join(&server_name);
 
     info!("Uninstalling fabric from server: {server_name}");
@@ -54,7 +54,7 @@ async fn uninstall_server(server_name: String) -> Result<(), FabricInstallError>
     Ok(())
 }
 
-async fn uninstall_client(instance_name: String) -> Result<(), FabricInstallError> {
+async fn uninstall_client(instance_name: &str) -> Result<(), FabricInstallError> {
     let instance_dir = LAUNCHER_DIR.join("instances").join(&instance_name);
 
     let libraries_dir = instance_dir.join("libraries");
@@ -96,9 +96,10 @@ async fn uninstall_client(instance_name: String) -> Result<(), FabricInstallErro
     Ok(())
 }
 
-pub async fn uninstall(instance: InstanceSelection) -> Result<(), FabricInstallError> {
-    match instance {
-        InstanceSelection::Instance(n) => uninstall_client(n).await,
-        InstanceSelection::Server(n) => uninstall_server(n).await,
+pub async fn uninstall(instance: Instance) -> Result<(), FabricInstallError> {
+    let name = instance.get_name();
+    match instance.kind {
+        InstanceKind::Client => uninstall_client(name).await,
+        InstanceKind::Server => uninstall_server(name).await,
     }
 }
diff --git a/crates/ql_mod_manager/src/loaders/fabric/version_list.rs b/crates/ql_mod_manager/src/loaders/fabric/version_list.rs
--- a/crates/ql_mod_manager/src/loaders/fabric/version_list.rs
+++ b/crates/ql_mod_manager/src/loaders/fabric/version_list.rs
@@ -1,7 +1,7 @@
 use std::fmt::Display;
 
 use ql_core::{
-    InstanceSelection, JsonDownloadError, RequestError, download, info,
+    Instance, InstanceKind, JsonDownloadError, RequestError, download, info,
     json::{V_OFFICIAL_FABRIC_SUPPORT, VersionDetails},
     pt,
 };
@@ -179,17 +179,17 @@ impl FabricVersionList {
 }
 
 pub async fn get_list_of_versions(
-    instance: InstanceSelection,
+    instance: Instance,
     is_quilt: bool,
 ) -> Result<FabricVersionList, FabricInstallError> {
     info!("Loading fabric version list...");
-    let is_server = instance.is_server();
+    let kind = instance.kind;
     let version_json = VersionDetails::load(&instance).await?;
 
-    let mut result = get_list_of_versions_inner(&version_json, is_quilt, is_server).await;
+    let mut result = get_list_of_versions_inner(&version_json, is_quilt, kind).await;
     if result.is_err() {
         for _ in 0..5 {
-            result = get_list_of_versions_inner(&version_json, is_quilt, is_server).await;
+            result = get_list_of_versions_inner(&version_json, is_quilt, kind).await;
             match &result {
                 Ok(_) => break,
                 Err(JsonDownloadError::RequestError(RequestError::DownloadError {
@@ -214,7 +214,7 @@ pub async fn get_list_of_versions(
 pub async fn get_list_of_versions_from_backend(
     version: &str,
     backend: BackendType,
-    is_server: bool,
+    kind: InstanceKind,
 ) -> Result<List, JsonDownloadError> {
     let versions: List = if let BackendType::CursedLegacy = backend {
         vec![FabricVersionListItem {
@@ -231,7 +231,7 @@ pub async fn get_list_of_versions_from_backend(
         let url1 = format!("https://meta.ornithemc.net/v3/versions/{name}-loader/{version}");
         let url2 = format!(
             "https://meta.ornithemc.net/v3/versions/{name}-loader/{version}-{}",
-            if is_server { "server" } else { "client" }
+            if kind.is_server() { "server" } else { "client" }
         );
 
         let list = download(&url1).json::<List>().await?;
@@ -255,26 +255,26 @@ pub async fn get_list_of_versions_from_backend(
 async fn get_list_of_versions_inner(
     version_json: &VersionDetails,
     is_quilt: bool,
-    is_server: bool,
+    kind: InstanceKind,
 ) -> Result<FabricVersionList, JsonDownloadError> {
     let version = version_json.get_id();
     if is_quilt {
-        return get_quilt_list(version_json, is_server, version).await;
+        return get_quilt_list(version_json, kind, version).await;
     }
 
     if version_json.is_after_or_eq(V_OFFICIAL_FABRIC_SUPPORT) {
         let official_versions =
-            get_list_of_versions_from_backend(version, BackendType::Fabric, is_server).await?;
+            get_list_of_versions_from_backend(version, BackendType::Fabric, kind).await?;
         if !official_versions.is_empty() {
             return Ok(FabricVersionList::Fabric(official_versions));
         }
     }
 
     if version == "b1.7.3" {
         let (ornithe_mc, cursed_legacy, babric) = tokio::try_join!(
-            get_list_of_versions_from_backend(version, BackendType::OrnitheMCFabric, is_server),
-            get_list_of_versions_from_backend(version, BackendType::CursedLegacy, is_server),
-            get_list_of_versions_from_backend(version, BackendType::Babric, is_server),
+            get_list_of_versions_from_backend(version, BackendType::OrnitheMCFabric, kind),
+            get_list_of_versions_from_backend(version, BackendType::CursedLegacy, kind),
+            get_list_of_versions_from_backend(version, BackendType::Babric, kind),
         )?;
 
         return Ok(FabricVersionList::Beta173 {
@@ -285,8 +285,8 @@ async fn get_list_of_versions_inner(
     }
 
     let (legacy_fabric, ornithe_mc) = tokio::try_join!(
-        get_list_of_versions_from_backend(version, BackendType::LegacyFabric, is_server),
-        get_list_of_versions_from_backend(version, BackendType::OrnitheMCFabric, is_server)
+        get_list_of_versions_from_backend(version, BackendType::LegacyFabric, kind),
+        get_list_of_versions_from_backend(version, BackendType::OrnitheMCFabric, kind)
     )?;
 
     Ok(match (legacy_fabric.is_empty(), ornithe_mc.is_empty()) {
@@ -302,12 +302,12 @@ async fn get_list_of_versions_inner(
 
 async fn get_quilt_list(
     version_json: &VersionDetails,
-    is_server: bool,
+    kind: InstanceKind,
     version: &str,
 ) -> Result<FabricVersionList, JsonDownloadError> {
     let (versions, should_try_ornithe) =
         if version_json.is_after_or_eq(V_OFFICIAL_FABRIC_SUPPORT) {
-            match get_list_of_versions_from_backend(version, BackendType::Quilt, is_server).await {
+            match get_list_of_versions_from_backend(version, BackendType::Quilt, kind).await {
                 // If the list is empty or an error 404
                 // then try OrnitheMC backend, otherwise
                 // stick to official Quilt backend
@@ -325,8 +325,7 @@ async fn get_quilt_list(
         };
     Ok(if should_try_ornithe {
         let versions =
-            get_list_of_versions_from_backend(version, BackendType::OrnitheMCQuilt, is_server)
-                .await?;
+            get_list_of_versions_from_backend(version, BackendType::OrnitheMCQuilt, kind).await?;
         if versions.is_empty() {
             FabricVersionList::Unsupported
         } else {
diff --git a/crates/ql_mod_manager/src/loaders/forge/mod.rs b/crates/ql_mod_manager/src/loaders/forge/mod.rs
--- a/crates/ql_mod_manager/src/loaders/forge/mod.rs
+++ b/crates/ql_mod_manager/src/loaders/forge/mod.rs
@@ -1,8 +1,8 @@
 use error::Is404NotFound;
 use owo_colors::OwoColorize;
 use ql_core::{
-    CLASSPATH_SEPARATOR, GenericProgress, InstanceSelection, IntoIoError, IntoJsonError, IoError,
-    Loader, Progress, do_jobs, download, err,
+    CLASSPATH_SEPARATOR, GenericProgress, Instance, InstanceKind, IntoIoError, IntoJsonError,
+    IoError, Loader, Progress, do_jobs, download, err,
     file_utils::{self, exists},
     info,
     json::{
@@ -43,7 +43,7 @@ struct ForgeInstaller {
 
     instance_dir: PathBuf,
     forge_dir: PathBuf,
-    is_server: bool,
+    kind: InstanceKind,
     version_json: VersionDetails,
 }
 
@@ -59,7 +59,7 @@ impl ForgeInstaller {
     async fn new(
         forge_version: Option<String>, // example: "11.15.1.2318" for 1.8.9
         f_progress: Option<Sender<ForgeInstallProgress>>,
-        instance: InstanceSelection,
+        instance: Instance,
     ) -> Result<Self, ForgeInstallError> {
         let instance_dir = instance.get_instance_path();
         let forge_dir = if instance.is_server() {
@@ -110,7 +110,7 @@ impl ForgeInstaller {
 
             instance_dir,
             forge_dir,
-            is_server: instance.is_server(),
+            kind: instance.kind,
             version_json,
         })
     }
@@ -212,10 +212,9 @@ impl ForgeInstaller {
         j_progress: Option<&Sender<GenericProgress>>,
         installer_name: &str,
     ) -> Result<(), ForgeInstallError> {
-        let installer = if self.is_server {
-            FORGE_INSTALLER_SERVER
-        } else {
-            FORGE_INSTALLER_CLIENT
+        let installer = match self.kind {
+            InstanceKind::Client => FORGE_INSTALLER_CLIENT,
+            InstanceKind::Server => FORGE_INSTALLER_SERVER,
         };
         let installer_class = self.forge_dir.join("ForgeInstaller.class");
         fs::write(&installer_class, installer)
@@ -262,7 +261,7 @@ impl ForgeInstaller {
     }
 
     async fn run_installer_create_garbage_files(&self) -> Result<(), ForgeInstallError> {
-        if !self.is_server {
+        if matches!(self.kind, InstanceKind::Client) {
             let launcher_profiles_json_path = self.forge_dir.join("launcher_profiles.json");
             fs::write(&launcher_profiles_json_path, "{}")
                 .await
@@ -442,16 +441,16 @@ async fn create_mods_dir(instance_dir: &Path) -> Result<(), ForgeInstallError> {
 
 pub async fn install(
     forge_version: Option<String>, // example: "11.15.1.2318" for 1.8.9
-    instance: InstanceSelection,
+    instance: Instance,
     f_progress: Option<Sender<ForgeInstallProgress>>,
     j_progress: Option<Sender<GenericProgress>>,
 ) -> Result<(), ForgeInstallError> {
-    match instance {
-        InstanceSelection::Instance(name) => {
-            install_client(forge_version, name, f_progress, j_progress).await
+    match instance.kind {
+        InstanceKind::Client => {
+            install_client(forge_version, instance, f_progress, j_progress).await
         }
-        InstanceSelection::Server(name) => {
-            install_server(forge_version, name, j_progress, f_progress).await
+        InstanceKind::Server => {
+            install_server(forge_version, instance, j_progress, f_progress).await
         }
     }
 }
@@ -505,7 +504,7 @@ impl Progress for ForgeInstallProgress {
 
 pub async fn install_client(
     forge_version: Option<String>,
-    instance_name: String,
+    instance: Instance,
     f_progress: Option<Sender<ForgeInstallProgress>>,
     j_progress: Option<Sender<GenericProgress>>,
 ) -> Result<(), ForgeInstallError> {
@@ -514,21 +513,11 @@ pub async fn install_client(
         _ = progress.send(ForgeInstallProgress::P1Start);
     }
 
-    let installer = ForgeInstaller::new(
-        forge_version,
-        f_progress,
-        InstanceSelection::Instance(instance_name.clone()),
-    )
-    .await?;
+    let installer = ForgeInstaller::new(forge_version, f_progress, instance.clone()).await?;
 
     let (installer_file, installer_name, _) = installer.download_forge_installer().await?;
     if installer.version_json.is_legacy_version() && installer.version_json.get_id() != "1.5.2" {
-        ql_core::jarmod::insert(
-            InstanceSelection::Instance(instance_name.clone()),
-            installer_file,
-            "Forge",
-        )
-        .await?;
+        ql_core::jarmod::insert(instance.clone(), installer_file, "Forge").await?;
         return Ok(());
     }
 
diff --git a/crates/ql_mod_manager/src/loaders/forge/server.rs b/crates/ql_mod_manager/src/loaders/forge/server.rs
--- a/crates/ql_mod_manager/src/loaders/forge/server.rs
+++ b/crates/ql_mod_manager/src/loaders/forge/server.rs
@@ -1,25 +1,20 @@
-use ql_core::{InstanceSelection, IntoIoError, Loader, json::instance_config::ModTypeInfo};
+use ql_core::{Instance, IntoIoError, Loader, json::instance_config::ModTypeInfo};
 
 use crate::loaders::{change_instance_type, forge::ForgeInstaller};
 
 use super::{ForgeInstallProgress, error::ForgeInstallError};
 
 pub async fn install_server(
     forge_version: Option<String>, // example: "11.15.1.2318" for 1.8.9
-    instance_name: String,
+    instance: Instance,
     j_progress: Option<std::sync::mpsc::Sender<ql_core::GenericProgress>>,
     f_progress: Option<std::sync::mpsc::Sender<ForgeInstallProgress>>,
 ) -> Result<(), ForgeInstallError> {
     if let Some(progress) = &f_progress {
         _ = progress.send(ForgeInstallProgress::P1Start);
     }
 
-    let installer = ForgeInstaller::new(
-        forge_version,
-        f_progress,
-        InstanceSelection::Server(instance_name),
-    )
-    .await?;
+    let installer = ForgeInstaller::new(forge_version, f_progress, instance).await?;
 
     let (_, installer_name, installer_path) = installer.download_forge_installer().await?;
 
diff --git a/crates/ql_mod_manager/src/loaders/forge/uninstall.rs b/crates/ql_mod_manager/src/loaders/forge/uninstall.rs
--- a/crates/ql_mod_manager/src/loaders/forge/uninstall.rs
+++ b/crates/ql_mod_manager/src/loaders/forge/uninstall.rs
@@ -1,24 +1,23 @@
 use std::path::Path;
 
 use ql_core::{
-    InstanceSelection, IntoIoError, IntoStringError, LAUNCHER_DIR, Loader, err,
-    find_forge_shim_file, json::InstanceConfigJson,
+    Instance, InstanceKind, IntoIoError, IntoStringError, Loader, err, find_forge_shim_file,
+    json::InstanceConfigJson,
 };
 
 use crate::loaders::{self, change_instance_type};
 
 use super::error::ForgeInstallError;
 
-pub async fn uninstall(instance: InstanceSelection) -> Result<(), String> {
-    match instance {
-        InstanceSelection::Instance(instance) => uninstall_client(&instance).await,
-        InstanceSelection::Server(instance) => uninstall_server(&instance).await.strerr(),
+pub async fn uninstall(instance: Instance) -> Result<(), String> {
+    let instance_dir = instance.get_instance_path();
+    match instance.kind {
+        InstanceKind::Client => uninstall_client(&instance_dir, instance).await,
+        InstanceKind::Server => uninstall_server(&instance_dir).await.strerr(),
     }
 }
 
-async fn uninstall_client(instance: &str) -> Result<(), String> {
-    let instance_dir = LAUNCHER_DIR.join("instances").join(instance);
-
+async fn uninstall_client(instance_dir: &Path, instance: Instance) -> Result<(), String> {
     let forge_dir = instance_dir.join("forge");
     if forge_dir.is_dir() {
         if let Err(err) = tokio::fs::remove_dir_all(&forge_dir)
@@ -44,15 +43,9 @@ async fn uninstall_client(instance: &str) -> Result<(), String> {
             .path(&installer_path)
             .strerr()?
         {
-            loaders::optifine::install(
-                instance.to_owned(),
-                installer_path.clone(),
-                None,
-                None,
-                None,
-            )
-            .await
-            .strerr()?;
+            loaders::optifine::install(instance, installer_path.clone(), None, None, None)
+                .await
+                .strerr()?;
             tokio::fs::remove_file(&installer_path)
                 .await
                 .path(&installer_path)
@@ -70,8 +63,7 @@ async fn uninstall_client(instance: &str) -> Result<(), String> {
     Ok(())
 }
 
-async fn uninstall_server(instance: &str) -> Result<(), ForgeInstallError> {
-    let instance_dir = LAUNCHER_DIR.join("servers").join(instance);
+async fn uninstall_server(instance_dir: &Path) -> Result<(), ForgeInstallError> {
     change_instance_type(&instance_dir, Loader::Vanilla, None).await?;
 
     if let Some(forge_shim_file) = find_forge_shim_file(&instance_dir).await {
diff --git a/crates/ql_mod_manager/src/loaders/mod.rs b/crates/ql_mod_manager/src/loaders/mod.rs
--- a/crates/ql_mod_manager/src/loaders/mod.rs
+++ b/crates/ql_mod_manager/src/loaders/mod.rs
@@ -9,7 +9,7 @@ use std::{
 use crate::loaders::paper::PaperVer;
 use forge::ForgeInstallProgress;
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoStringError, JsonFileError, Loader, Progress,
+    GenericProgress, Instance, IntoStringError, JsonFileError, Loader, Progress,
     json::{InstanceConfigJson, instance_config::ModTypeInfo},
 };
 
@@ -44,7 +44,7 @@ pub enum LoaderInstallResult {
 }
 
 pub async fn install_specified_loader(
-    instance: InstanceSelection,
+    instance: Instance,
     loader: Loader,
     progress: Option<Arc<Sender<GenericProgress>>>,
     specified_version: Option<String>,
@@ -136,7 +136,7 @@ fn pipe_progress(rec: Receiver<ForgeInstallProgress>, snd: &Sender<GenericProgre
     }
 }
 
-pub async fn uninstall_loader(instance: InstanceSelection) -> Result<(), String> {
+pub async fn uninstall_loader(instance: Instance) -> Result<(), String> {
     let loader = InstanceConfigJson::read(&instance).await.strerr()?.mod_type;
 
     match loader {
diff --git a/crates/ql_mod_manager/src/loaders/neoforge.rs b/crates/ql_mod_manager/src/loaders/neoforge.rs
--- a/crates/ql_mod_manager/src/loaders/neoforge.rs
+++ b/crates/ql_mod_manager/src/loaders/neoforge.rs
@@ -1,7 +1,7 @@
 use chrono::DateTime;
 use ql_core::{
-    CLASSPATH_SEPARATOR, GenericProgress, InstanceSelection, IntoIoError, IntoJsonError, IoError,
-    Loader, REGEX_SNAPSHOT, download,
+    CLASSPATH_SEPARATOR, GenericProgress, Instance, InstanceKind, IntoIoError, IntoJsonError,
+    IoError, Loader, REGEX_SNAPSHOT, download,
     file_utils::{self, exists},
     info,
     json::{VersionDetails, instance_config::ModTypeInfo},
@@ -28,7 +28,7 @@ struct NeoforgeVersions {
 
 pub async fn install(
     neoforge_version: Option<String>,
-    instance: InstanceSelection,
+    instance: Instance,
     f_progress: Option<Sender<ForgeInstallProgress>>,
     j_progress: Option<Sender<GenericProgress>>,
 ) -> Result<(), ForgeInstallError> {
@@ -57,7 +57,7 @@ pub async fn install(
         &neoforge_dir,
         j_progress.as_ref(),
         f_progress,
-        instance.is_server(),
+        instance.kind,
     )
     .await?;
 
@@ -182,7 +182,7 @@ async fn get_installer(
 
 async fn get_version_and_json(
     neoforge_version: Option<String>,
-    instance: &InstanceSelection,
+    instance: &Instance,
     f_progress: Option<&Sender<ForgeInstallProgress>>,
 ) -> Result<(String, VersionDetails), ForgeInstallError> {
     Ok(if let Some(n) = neoforge_version {
@@ -232,7 +232,7 @@ fn send_progress(f_progress: Option<&Sender<ForgeInstallProgress>>, message: For
 }
 
 pub async fn get_versions(
-    instance_selection: InstanceSelection,
+    instance_selection: Instance,
 ) -> Result<(Vec<String>, VersionDetails), ForgeInstallError> {
     let versions: NeoforgeVersions =
         file_utils::download_file_to_json(NEOFORGE_VERSIONS_URL, false).await?;
@@ -303,15 +303,14 @@ pub async fn run_installer(
     neoforge_dir: &Path,
     j_progress: Option<&Sender<GenericProgress>>,
     f_progress: Option<&Sender<ForgeInstallProgress>>,
-    is_server: bool,
+    kind: InstanceKind,
 ) -> Result<(), ForgeInstallError> {
     pt!("Running Installer");
     send_progress(f_progress, ForgeInstallProgress::P4RunningInstaller);
 
-    let installer = if is_server {
-        FORGE_INSTALLER_SERVER
-    } else {
-        FORGE_INSTALLER_CLIENT
+    let installer = match kind {
+        InstanceKind::Server => FORGE_INSTALLER_SERVER,
+        InstanceKind::Client => FORGE_INSTALLER_CLIENT,
     };
     let installer_class = neoforge_dir.join("NeoForgeInstaller.class");
     fs::write(&installer_class, installer)
@@ -329,12 +328,11 @@ pub async fn run_installer(
             ),
             "NeoForgeInstaller",
         ])
-        .current_dir(if is_server {
-            neoforge_dir
+        .current_dir(match kind {
+            InstanceKind::Client => neoforge_dir.to_owned(),
+            InstanceKind::Server => neoforge_dir
                 .parent()
                 .map_or(neoforge_dir.join(".."), Path::to_owned)
-        } else {
-            neoforge_dir.to_owned()
         });
 
     let output = command.output().await.path(java_path)?;
diff --git a/crates/ql_mod_manager/src/loaders/optifine.rs b/crates/ql_mod_manager/src/loaders/optifine.rs
--- a/crates/ql_mod_manager/src/loaders/optifine.rs
+++ b/crates/ql_mod_manager/src/loaders/optifine.rs
@@ -7,7 +7,7 @@ use std::{
 };
 
 use ql_core::{
-    CLASSPATH_SEPARATOR, GenericProgress, InstanceSelection, IntoIoError, IoError, JsonError,
+    CLASSPATH_SEPARATOR, GenericProgress, Instance, InstanceKind, IntoIoError, IoError, JsonError,
     LAUNCHER_DIR, Loader, OptifineUniqueVersion, Progress, RequestError, download,
     file_utils::{self, exists},
     impl_3_errs_jri, info, jarmod,
@@ -21,10 +21,7 @@ use thiserror::Error;
 
 use super::change_instance_type;
 
-pub async fn install_b173(
-    instance: InstanceSelection,
-    url: &'static str,
-) -> Result<(), OptifineError> {
+pub async fn install_b173(instance: Instance, url: &'static str) -> Result<(), OptifineError> {
     info!("Installing OptiFine for Beta 1.7.3...");
     let bytes = file_utils::download_file_to_bytes(url, true).await?;
     jarmod::insert(instance, bytes, "Optifine").await?;
@@ -86,12 +83,16 @@ impl Progress for OptifineInstallProgress {
 }
 
 pub async fn install(
-    instance_name: String,
+    instance: Instance,
     path_to_installer: PathBuf,
     progress_sender: Option<Sender<OptifineInstallProgress>>,
     java_progress_sender: Option<Sender<GenericProgress>>,
     optifine_unique_version: Option<OptifineUniqueVersion>,
 ) -> Result<(), OptifineError> {
+    if let InstanceKind::Server = instance.kind {
+        return Err(OptifineError::DoesntSupportServer);
+    }
+
     if !tokio::fs::metadata(&path_to_installer)
         .await
         .is_ok_and(|n| n.is_file())
@@ -100,7 +101,7 @@ pub async fn install(
     }
 
     let progress_sender = progress_sender.as_ref();
-    let instance_path = LAUNCHER_DIR.join("instances").join(&instance_name);
+    let instance_path = instance.get_instance_path();
 
     info!("Started installing OptiFine");
     send_progress(progress_sender, OptifineInstallProgress::P1Start);
@@ -130,12 +131,7 @@ pub async fn install(
             let installer = tokio::fs::read(&path_to_installer)
                 .await
                 .path(&path_to_installer)?;
-            jarmod::insert(
-                InstanceSelection::Instance(instance_name),
-                installer,
-                "Optifine",
-            )
-            .await?;
+            jarmod::insert(instance, installer, "Optifine").await?;
             pt!("Finished installing OptiFine (old version)");
             return Ok(());
         }
@@ -170,7 +166,7 @@ pub async fn install(
     send_progress(progress_sender, OptifineInstallProgress::P3RunningHook);
     run_hook(&new_installer_path, &optifine_path).await?;
 
-    download_libraries(&instance_name, &dot_minecraft_path, progress_sender).await?;
+    download_libraries(instance.get_name(), &dot_minecraft_path, progress_sender).await?;
     change_instance_type(&instance_path, Loader::OptiFine, None).await?;
     send_progress(progress_sender, OptifineInstallProgress::P5Done);
     pt!("Finished installing OptiFine");
@@ -372,6 +368,8 @@ pub enum OptifineError {
     Request(#[from] RequestError),
     #[error("{OPTIFINE_ERR_PREFIX}{0}")]
     Json(#[from] JsonError),
+    #[error("OptiFine only supports clients, not servers")]
+    DoesntSupportServer,
 }
 
 impl_3_errs_jri!(OptifineError, Json, Request, Io);
diff --git a/crates/ql_mod_manager/src/presets/mod.rs b/crates/ql_mod_manager/src/presets/mod.rs
--- a/crates/ql_mod_manager/src/presets/mod.rs
+++ b/crates/ql_mod_manager/src/presets/mod.rs
@@ -6,7 +6,7 @@ use std::{
 
 use owo_colors::OwoColorize;
 use ql_core::{
-    InstanceSelection, IntoIoError, IntoJsonError, LAUNCHER_VERSION_NAME, Loader, err, info,
+    Instance, IntoIoError, IntoJsonError, LAUNCHER_VERSION_NAME, Loader, err, info,
     json::{InstanceConfigJson, VersionDetails},
     pt,
 };
@@ -80,7 +80,7 @@ impl Preset {
     /// the bytes of the final `.qmp` file that you can save
     /// anywhere you want.
     pub async fn generate(
-        instance: InstanceSelection,
+        instance: Instance,
         selected_mods: HashSet<SelectedMod>,
         include_config: bool,
     ) -> Result<Vec<u8>, ModError> {
@@ -175,7 +175,7 @@ impl Preset {
     /// ---
     /// - And many other things I probably forgot
     pub async fn load(
-        instance: InstanceSelection,
+        instance: Instance,
         file: Vec<u8>,
         apply: bool,
     ) -> Result<PresetOutput, ModError> {
@@ -278,7 +278,7 @@ impl Preset {
     }
 }
 
-async fn get_instance_type(instance_name: &InstanceSelection) -> Result<Loader, ModError> {
+async fn get_instance_type(instance_name: &Instance) -> Result<Loader, ModError> {
     let config = InstanceConfigJson::read(instance_name).await?;
     Ok(config.mod_type)
 }
@@ -300,7 +300,7 @@ fn add_downloaded_mod_to_entries(
     }
 }
 
-async fn get_minecraft_version(instance_name: &InstanceSelection) -> Result<String, ModError> {
+async fn get_minecraft_version(instance_name: &Instance) -> Result<String, ModError> {
     let version_json = VersionDetails::load(instance_name).await?;
     let minecraft_version = version_json.get_id().to_owned();
     Ok(minecraft_version)
diff --git a/crates/ql_mod_manager/src/store/add_file.rs b/crates/ql_mod_manager/src/store/add_file.rs
--- a/crates/ql_mod_manager/src/store/add_file.rs
+++ b/crates/ql_mod_manager/src/store/add_file.rs
@@ -1,6 +1,6 @@
 use std::{collections::HashSet, ffi::OsStr, path::PathBuf, sync::mpsc::Sender};
 
-use ql_core::{GenericProgress, InstanceSelection, IntoIoError, err, pt};
+use ql_core::{GenericProgress, Instance, IntoIoError, err, pt};
 
 use crate::{presets, store::download_mods_bulk};
 
@@ -10,7 +10,7 @@ use super::{
 };
 
 pub async fn add_files(
-    instance: InstanceSelection,
+    instance: Instance,
     paths: Vec<PathBuf>,
     progress: Option<Sender<GenericProgress>>,
 ) -> Result<HashSet<CurseforgeNotAllowed>, PackError> {
diff --git a/crates/ql_mod_manager/src/store/curseforge/download.rs b/crates/ql_mod_manager/src/store/curseforge/download.rs
--- a/crates/ql_mod_manager/src/store/curseforge/download.rs
+++ b/crates/ql_mod_manager/src/store/curseforge/download.rs
@@ -4,7 +4,7 @@ use std::{
 };
 
 use ql_core::{
-    GenericProgress, InstanceConfigJson, InstanceSelection, download, err, file_utils, info,
+    GenericProgress, InstanceConfigJson, Instance, download, err, file_utils, info,
     json::VersionDetails, pt,
 };
 
@@ -19,7 +19,7 @@ use super::Mod;
 
 pub struct ModDownloader<'a> {
     version: String,
-    instance: InstanceSelection,
+    instance: Instance,
     pub loader: Option<&'static str>,
     pub index: ModIndex,
 
@@ -33,7 +33,7 @@ pub struct ModDownloader<'a> {
 
 impl<'a> ModDownloader<'a> {
     pub async fn new(
-        instance: InstanceSelection,
+        instance: Instance,
         sender: Option<&'a Sender<GenericProgress>>,
     ) -> Result<Self, ModError> {
         let version_json = VersionDetails::load(&instance).await?;
@@ -52,7 +52,7 @@ impl<'a> ModDownloader<'a> {
         })
     }
 
-    pub async fn basic(instance: InstanceSelection) -> Result<Self, ModError> {
+    pub async fn basic(instance: Instance) -> Result<Self, ModError> {
         let version_json = VersionDetails::load(&instance).await?;
         let config = InstanceConfigJson::read(&instance).await?;
 
diff --git a/crates/ql_mod_manager/src/store/curseforge/mod.rs b/crates/ql_mod_manager/src/store/curseforge/mod.rs
--- a/crates/ql_mod_manager/src/store/curseforge/mod.rs
+++ b/crates/ql_mod_manager/src/store/curseforge/mod.rs
@@ -372,7 +372,7 @@ impl Backend for CurseforgeBackend {
 
     async fn download(
         id: &str,
-        instance: &ql_core::InstanceSelection,
+        instance: &ql_core::Instance,
         sender: Option<Sender<GenericProgress>>,
     ) -> Result<HashSet<CurseforgeNotAllowed>, ModError> {
         let _guard = lock().await;
@@ -388,7 +388,7 @@ impl Backend for CurseforgeBackend {
 
     async fn download_bulk(
         ids: &[String],
-        instance: &ql_core::InstanceSelection,
+        instance: &ql_core::Instance,
         ignore_incompatible: bool,
         set_manually_installed: bool,
         sender: Option<&Sender<GenericProgress>>,
@@ -534,7 +534,7 @@ impl Backend for CurseforgeBackend {
     }
 
     async fn get_download_link(
-        instance: &ql_core::InstanceSelection,
+        instance: &ql_core::Instance,
         id: &str,
         query_type: QueryType,
     ) -> Result<String, ModError> {
diff --git a/crates/ql_mod_manager/src/store/delete.rs b/crates/ql_mod_manager/src/store/delete.rs
--- a/crates/ql_mod_manager/src/store/delete.rs
+++ b/crates/ql_mod_manager/src/store/delete.rs
@@ -2,15 +2,15 @@ use crate::{
     rate_limiter::lock,
     store::{ModError, ModId, ModIndex},
 };
-use ql_core::{InstanceSelection, IoError, err, info, pt};
+use ql_core::{Instance, IoError, err, info, pt};
 use std::{
     collections::{HashMap, HashSet},
     path::Path,
 };
 
 pub async fn delete_mods(
     ids: Vec<ModId>,
-    instance: InstanceSelection,
+    instance: Instance,
 ) -> Result<Vec<ModId>, ModError> {
     let _guard = lock().await;
 
diff --git a/crates/ql_mod_manager/src/store/local_json.rs b/crates/ql_mod_manager/src/store/local_json.rs
--- a/crates/ql_mod_manager/src/store/local_json.rs
+++ b/crates/ql_mod_manager/src/store/local_json.rs
@@ -5,7 +5,7 @@ use std::{
 };
 
 use ql_core::{
-    InstanceSelection, IntoIoError, IntoJsonError, IoError, JsonFileError, file_utils::exists, info,
+    Instance, IntoIoError, IntoJsonError, IoError, JsonFileError, file_utils::exists, info,
 };
 use serde::{Deserialize, Serialize};
 use tokio::fs;
@@ -39,15 +39,15 @@ pub struct ModIndex {
 }
 
 impl ModIndex {
-    pub async fn load(selected_instance: &InstanceSelection) -> Result<Self, JsonFileError> {
+    pub async fn load(selected_instance: &Instance) -> Result<Self, JsonFileError> {
         let mut index = load_inner(selected_instance).await?;
         index.fix(selected_instance).await?;
         Ok(index)
     }
 
     pub async fn save(
         &mut self,
-        selected_instance: &InstanceSelection,
+        selected_instance: &Instance,
     ) -> Result<(), JsonFileError> {
         let index_dir = selected_instance
             .get_dot_minecraft_path()
@@ -58,14 +58,14 @@ impl ModIndex {
         Ok(())
     }
 
-    fn new(instance_name: &InstanceSelection) -> Self {
+    fn new(instance_name: &Instance) -> Self {
         Self {
             mods: HashMap::new(),
             is_server: Some(instance_name.is_server()),
         }
     }
 
-    pub async fn fix(&mut self, selected_instance: &InstanceSelection) -> Result<(), IoError> {
+    pub async fn fix(&mut self, selected_instance: &Instance) -> Result<(), IoError> {
         let mods_dir = selected_instance.get_dot_minecraft_path().join("mods");
         if !exists(&mods_dir).await {
             fs::create_dir(&mods_dir).await.path(&mods_dir)?;
@@ -128,7 +128,7 @@ impl ModIndex {
     }
 }
 
-async fn load_inner(selected_instance: &InstanceSelection) -> Result<ModIndex, JsonFileError> {
+async fn load_inner(selected_instance: &Instance) -> Result<ModIndex, JsonFileError> {
     let dot_mc_dir = selected_instance.get_dot_minecraft_path();
 
     let mods_dir = dot_mc_dir.join("mods");
diff --git a/crates/ql_mod_manager/src/store/mod.rs b/crates/ql_mod_manager/src/store/mod.rs
--- a/crates/ql_mod_manager/src/store/mod.rs
+++ b/crates/ql_mod_manager/src/store/mod.rs
@@ -2,7 +2,7 @@ use std::{collections::HashSet, path::PathBuf, sync::mpsc::Sender};
 
 use chrono::DateTime;
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoIoError, Loader, do_jobs, json::VersionDetails, pt,
+    GenericProgress, Instance, IntoIoError, Loader, do_jobs, json::VersionDetails, pt,
 };
 
 mod add_file;
@@ -72,7 +72,7 @@ pub trait Backend {
     /// Optionally takes in a `sender` to use if it's a modpack.
     async fn download(
         id: &str,
-        instance: &InstanceSelection,
+        instance: &Instance,
         sender: Option<Sender<GenericProgress>>,
     ) -> Result<HashSet<CurseforgeNotAllowed>, ModError>;
     /// Downloads multiple mods to the `instance`.
@@ -81,7 +81,7 @@ pub trait Backend {
     /// so more efficient than [`Backend::download`] in a loop.
     async fn download_bulk(
         ids: &[String],
-        instance: &InstanceSelection,
+        instance: &Instance,
         ignore_incompatible: bool,
         _set_manually_installed: bool,
         sender: Option<&Sender<GenericProgress>>,
@@ -135,7 +135,7 @@ pub trait Backend {
     ///
     /// May return [`ModError::NoFilesFound`] if a Curseforge mod doesn't allow direct downloading.
     async fn get_download_link(
-        instance: &InstanceSelection,
+        instance: &Instance,
         id: &str,
         query_type: QueryType,
     ) -> Result<String, ModError>;
@@ -168,7 +168,7 @@ pub async fn search(
 /// Optionally takes in a `sender` to use if it's a modpack.
 pub async fn download_mod(
     id: &ModId,
-    instance: &InstanceSelection,
+    instance: &Instance,
     sender: Option<Sender<GenericProgress>>,
 ) -> Result<HashSet<CurseforgeNotAllowed>, ModError> {
     match id {
@@ -183,7 +183,7 @@ pub async fn download_mod(
 /// so more efficient than [`download_mod`] in a loop.
 pub async fn download_mods_bulk(
     ids: Vec<ModId>,
-    instance: InstanceSelection,
+    instance: Instance,
     sender: Option<Sender<GenericProgress>>,
 ) -> Result<HashSet<CurseforgeNotAllowed>, ModError> {
     let (modrinth, other): (Vec<ModId>, Vec<ModId>) = ids.into_iter().partition(|n| match n {
@@ -288,7 +288,7 @@ pub async fn get_info_bulk(ids: Vec<ModId>) -> Result<Vec<SearchMod>, ModError>
 }
 
 pub async fn get_download_link(
-    instance: &InstanceSelection,
+    instance: &Instance,
     id: &ModId,
     query_type: QueryType,
 ) -> Result<String, ModError> {
@@ -307,7 +307,7 @@ struct DirStructure {
 
 impl DirStructure {
     pub async fn new(
-        instance_name: &InstanceSelection,
+        instance_name: &Instance,
         version_json: &VersionDetails,
     ) -> Result<Self, ModError> {
         // Minecraft 13w23b release date (1.6.1 snapshot)
diff --git a/crates/ql_mod_manager/src/store/modpack/curseforge.rs b/crates/ql_mod_manager/src/store/modpack/curseforge.rs
--- a/crates/ql_mod_manager/src/store/modpack/curseforge.rs
+++ b/crates/ql_mod_manager/src/store/modpack/curseforge.rs
@@ -4,7 +4,7 @@ use std::{
 };
 
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoIoError, Loader, do_jobs, download,
+    GenericProgress, Instance, IntoIoError, Loader, do_jobs, download,
     json::{InstanceConfigJson, VersionDetails},
     pt,
 };
@@ -181,7 +181,7 @@ async fn send_progress(
 }
 
 pub async fn install(
-    instance: &InstanceSelection,
+    instance: &Instance,
     config: &InstanceConfigJson,
     json: &VersionDetails,
     index: &PackIndex,
diff --git a/crates/ql_mod_manager/src/store/modpack/mod.rs b/crates/ql_mod_manager/src/store/modpack/mod.rs
--- a/crates/ql_mod_manager/src/store/modpack/mod.rs
+++ b/crates/ql_mod_manager/src/store/modpack/mod.rs
@@ -5,7 +5,7 @@ use std::{
 };
 
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoIoError, IntoJsonError, err, info,
+    GenericProgress, Instance, IntoIoError, IntoJsonError, err, info,
     json::{InstanceConfigJson, VersionDetails},
     pt,
 };
@@ -44,7 +44,7 @@ use super::CurseforgeNotAllowed;
 /// - `Err` - Any error that occurred.
 pub async fn install_modpack(
     file: Vec<u8>,
-    instance: InstanceSelection,
+    instance: Instance,
     sender: Option<&Sender<GenericProgress>>,
 ) -> Result<Option<HashSet<CurseforgeNotAllowed>>, PackError> {
     let mut zip = zip::ZipArchive::new(Cursor::new(file.as_slice()))?;
diff --git a/crates/ql_mod_manager/src/store/modpack/modrinth.rs b/crates/ql_mod_manager/src/store/modpack/modrinth.rs
--- a/crates/ql_mod_manager/src/store/modpack/modrinth.rs
+++ b/crates/ql_mod_manager/src/store/modpack/modrinth.rs
@@ -1,7 +1,7 @@
 use std::{collections::HashMap, path::Path, sync::mpsc::Sender};
 
 use ql_core::{
-    GenericProgress, InstanceSelection, Loader, do_jobs, download,
+    GenericProgress, Instance, InstanceKind, Loader, do_jobs, download,
     json::{InstanceConfigJson, VersionDetails},
     pt,
 };
@@ -40,7 +40,7 @@ pub struct PackEnv {
 }
 
 pub async fn install(
-    instance: &InstanceSelection,
+    instance: &Instance,
     mc_dir: &Path,
     config: &InstanceConfigJson,
     json: &VersionDetails,
@@ -80,9 +80,9 @@ pub async fn install(
             .iter()
             .filter_map(|file| file.downloads.first().map(|n| (file, n)))
             .map(|(file, url)| async move {
-                let required_field = match instance {
-                    InstanceSelection::Instance(_) => &file.env.client,
-                    InstanceSelection::Server(_) => &file.env.server,
+                let required_field = match instance.kind {
+                    InstanceKind::Client => &file.env.client,
+                    InstanceKind::Server => &file.env.server,
                 };
                 if required_field != "required" {
                     pt!("Skipping {} (optional)", file.path);
diff --git a/crates/ql_mod_manager/src/store/modrinth/download.rs b/crates/ql_mod_manager/src/store/modrinth/download.rs
--- a/crates/ql_mod_manager/src/store/modrinth/download.rs
+++ b/crates/ql_mod_manager/src/store/modrinth/download.rs
@@ -6,7 +6,7 @@ use std::{
 
 use chrono::DateTime;
 use ql_core::{
-    GenericProgress, InstanceConfigJson, InstanceSelection, download, err, file_utils, info,
+    GenericProgress, InstanceConfigJson, Instance, download, err, file_utils, info,
     json::VersionDetails, pt,
 };
 
@@ -19,7 +19,7 @@ use crate::store::{
 use super::info::ProjectInfo;
 
 pub struct ModDownloader {
-    instance: InstanceSelection,
+    instance: Instance,
     version: String,
     loader: Option<&'static str>,
 
@@ -32,7 +32,7 @@ pub struct ModDownloader {
 
 impl ModDownloader {
     pub async fn new(
-        instance: &InstanceSelection,
+        instance: &Instance,
         sender: Option<Sender<GenericProgress>>,
     ) -> Result<ModDownloader, ModError> {
         let version_json = VersionDetails::load(instance).await?;
@@ -56,7 +56,7 @@ impl ModDownloader {
         })
     }
 
-    pub async fn basic(instance: &InstanceSelection) -> Result<ModDownloader, ModError> {
+    pub async fn basic(instance: &Instance) -> Result<ModDownloader, ModError> {
         let version_json = VersionDetails::load(instance).await?;
         let config = InstanceConfigJson::read(instance).await?;
 
diff --git a/crates/ql_mod_manager/src/store/modrinth/mod.rs b/crates/ql_mod_manager/src/store/modrinth/mod.rs
--- a/crates/ql_mod_manager/src/store/modrinth/mod.rs
+++ b/crates/ql_mod_manager/src/store/modrinth/mod.rs
@@ -4,7 +4,7 @@ use chrono::DateTime;
 use download::version_sort;
 use indexmap::IndexMap;
 use info::ProjectInfo;
-use ql_core::{GenericProgress, InstanceSelection, Loader, download, pt};
+use ql_core::{GenericProgress, Instance, Loader, download, pt};
 use serde::Deserialize;
 use versions::ModVersion;
 
@@ -109,7 +109,7 @@ impl Backend for ModrinthBackend {
 
     async fn download(
         id: &str,
-        instance: &InstanceSelection,
+        instance: &Instance,
         sender: Option<Sender<GenericProgress>>,
     ) -> Result<HashSet<CurseforgeNotAllowed>, ModError> {
         let _guard = lock().await;
@@ -126,7 +126,7 @@ impl Backend for ModrinthBackend {
 
     async fn download_bulk(
         ids: &[String],
-        instance: &InstanceSelection,
+        instance: &Instance,
         ignore_incompatible: bool,
         set_manually_installed: bool,
         sender: Option<&Sender<GenericProgress>>,
@@ -273,7 +273,7 @@ impl Backend for ModrinthBackend {
     }
 
     async fn get_download_link(
-        instance: &InstanceSelection,
+        instance: &Instance,
         id: &str,
         query_type: QueryType,
     ) -> Result<String, ModError> {
diff --git a/crates/ql_mod_manager/src/store/recommended.rs b/crates/ql_mod_manager/src/store/recommended.rs
--- a/crates/ql_mod_manager/src/store/recommended.rs
+++ b/crates/ql_mod_manager/src/store/recommended.rs
@@ -2,7 +2,7 @@ use std::sync::{Arc, Mutex, mpsc::Sender};
 
 use futures::StreamExt;
 use owo_colors::colored::OwoColorize;
-use ql_core::{GenericProgress, InstanceSelection, Loader, err, info, json::VersionDetails, pt};
+use ql_core::{GenericProgress, Instance, Loader, err, info, json::VersionDetails, pt};
 
 use crate::store::{ModId, ModIndex, StoreBackendType, get_latest_version_date};
 
@@ -20,7 +20,7 @@ pub struct RecommendedMod {
 impl RecommendedMod {
     pub async fn get_compatible_mods(
         ids: Vec<Self>,
-        instance: InstanceSelection,
+        instance: Instance,
         loader: Loader,
         sender: Sender<GenericProgress>,
     ) -> Result<Vec<Self>, ModError> {
diff --git a/crates/ql_mod_manager/src/store/toggle.rs b/crates/ql_mod_manager/src/store/toggle.rs
--- a/crates/ql_mod_manager/src/store/toggle.rs
+++ b/crates/ql_mod_manager/src/store/toggle.rs
@@ -1,6 +1,6 @@
 use std::path::Path;
 
-use ql_core::{InstanceSelection, IoError, err};
+use ql_core::{Instance, IoError, err};
 
 use crate::store::{ModId, ModIndex};
 
@@ -17,7 +17,7 @@ pub fn flip_filename(name: &str) -> String {
 
 pub async fn toggle_mods_local(
     names: Vec<String>,
-    instance: InstanceSelection,
+    instance: Instance,
 ) -> Result<(), ModError> {
     let mods_dir = instance.get_dot_minecraft_path().join("mods");
 
@@ -28,7 +28,7 @@ pub async fn toggle_mods_local(
     Ok(())
 }
 
-pub async fn toggle_mods(ids: Vec<ModId>, instance: InstanceSelection) -> Result<(), ModError> {
+pub async fn toggle_mods(ids: Vec<ModId>, instance: Instance) -> Result<(), ModError> {
     let mut index = ModIndex::load(&instance).await?;
 
     let mods_dir = instance.get_dot_minecraft_path().join("mods");
diff --git a/crates/ql_mod_manager/src/store/update.rs b/crates/ql_mod_manager/src/store/update.rs
--- a/crates/ql_mod_manager/src/store/update.rs
+++ b/crates/ql_mod_manager/src/store/update.rs
@@ -4,7 +4,7 @@ use std::sync::mpsc::Sender;
 use chrono::DateTime;
 use chrono::Local;
 use ql_core::InstanceConfigJson;
-use ql_core::{GenericProgress, InstanceSelection, do_jobs, err, info, json::VersionDetails};
+use ql_core::{GenericProgress, Instance, do_jobs, err, info, json::VersionDetails};
 
 use crate::store::{get_latest_version_date, toggle_mods};
 
@@ -17,7 +17,7 @@ pub struct ChangelogFile {
 }
 
 pub async fn apply_updates(
-    selected_instance: InstanceSelection,
+    selected_instance: Instance,
     updates: Vec<(ModId, String)>,
     progress: Option<Sender<GenericProgress>>,
     make_changelog: bool,
@@ -56,7 +56,7 @@ pub async fn apply_updates(
 
 async fn write_changelog(
     entries: Vec<String>,
-    selected_instance: InstanceSelection,
+    selected_instance: Instance,
 ) -> Option<ChangelogFile> {
     let titles = entries.join("\n");
     let now = Local::now();
@@ -107,7 +107,7 @@ fn trim(value: &str) -> &str {
 }
 
 pub async fn check_for_updates(
-    instance: InstanceSelection,
+    instance: Instance,
 ) -> Result<Vec<(ModId, String)>, ModError> {
     let index = ModIndex::load(&instance).await?;
     let version_json = VersionDetails::load(&instance).await?;
diff --git a/crates/ql_packager/src/export.rs b/crates/ql_packager/src/export.rs
--- a/crates/ql_packager/src/export.rs
+++ b/crates/ql_packager/src/export.rs
@@ -1,5 +1,5 @@
 use ql_core::{GenericProgress, file_utils};
-use ql_core::{InstanceSelection, IntoIoError, IntoJsonError, info, pt};
+use ql_core::{Instance, IntoIoError, IntoJsonError, info, pt};
 use std::collections::HashSet;
 use std::path::PathBuf;
 use std::sync::mpsc::Sender;
@@ -16,7 +16,7 @@ pub const EXCEPTIONS: &[&str] = &[
 ];
 
 fn create_instance_info(
-    instance: &InstanceSelection,
+    instance: &Instance,
     mut exceptions: HashSet<String>,
 ) -> InstanceInfo {
     exceptions.extend(EXCEPTIONS.iter().map(|n| (*n).to_owned()));
@@ -59,7 +59,7 @@ fn create_instance_info(
 /// - The instance directory doesn't exist.
 /// - File I/O operations (copying, deleting, zipping) fail.
 pub async fn export_instance(
-    instance: InstanceSelection,
+    instance: Instance,
     exceptions: HashSet<String>,
     progress: Option<Sender<GenericProgress>>,
 ) -> Result<Vec<u8>, InstancePackageError> {
diff --git a/crates/ql_packager/src/import.rs b/crates/ql_packager/src/import.rs
--- a/crates/ql_packager/src/import.rs
+++ b/crates/ql_packager/src/import.rs
@@ -1,5 +1,5 @@
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoIoError, IntoJsonError, ListEntry, Progress,
+    GenericProgress, Instance, InstanceKind, IntoIoError, IntoJsonError, ListEntry, Progress,
     file_utils, info,
     json::{InstanceConfigJson, VersionDetails},
     pt,
@@ -47,7 +47,7 @@ pub async fn import_instance(
     zip_path: PathBuf,
     download_assets: bool,
     sender: Option<Sender<GenericProgress>>,
-) -> Result<Option<InstanceSelection>, InstancePackageError> {
+) -> Result<Option<Instance>, InstancePackageError> {
     let temp_dir_obj = tempfile::TempDir::new().map_err(InstancePackageError::TempDir)?;
     let temp_dir = temp_dir_obj.path();
 
@@ -95,7 +95,7 @@ async fn import_quantumlauncher(
     temp_dir: &Path,
     instance_info: String,
     sender: Option<Arc<Sender<GenericProgress>>>,
-) -> Result<InstanceSelection, InstancePackageError> {
+) -> Result<Instance, InstancePackageError> {
     info!("Importing QuantumLauncher instance...");
 
     let instance_info: InstanceInfo = serde_json::from_str(&instance_info).json(instance_info)?;
@@ -106,7 +106,14 @@ async fn import_quantumlauncher(
         serde_json::from_str(&file).json(file)?
     };
 
-    let instance = InstanceSelection::new(&instance_info.instance_name, instance_info.is_server);
+    let instance = Instance::new(
+        &instance_info.instance_name,
+        if instance_info.is_server {
+            InstanceKind::Server
+        } else {
+            InstanceKind::Client
+        },
+    );
 
     pt!("Name: {} ", instance_info.instance_name);
     pt!("Version : {}", version_json.get_id());
diff --git a/crates/ql_packager/src/multimc.rs b/crates/ql_packager/src/multimc.rs
--- a/crates/ql_packager/src/multimc.rs
+++ b/crates/ql_packager/src/multimc.rs
@@ -7,8 +7,8 @@ use std::{
 
 use crate::{InstancePackageError, import::OUT_OF, import::pipe_progress};
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoIoError, IntoJsonError, LAUNCHER_DIR, ListEntry,
-    Loader, do_jobs, download, err,
+    GenericProgress, Instance, IntoIoError, IntoJsonError, LAUNCHER_DIR, ListEntry, Loader,
+    do_jobs, download, err,
     file_utils::{self, exists},
     info,
     jarmod::{JarMod, JarMods},
@@ -74,7 +74,7 @@ pub async fn import(
     temp_dir: &Path,
     mmc_pack: &str,
     sender: Option<Arc<Sender<GenericProgress>>>,
-) -> Result<InstanceSelection, InstancePackageError> {
+) -> Result<Instance, InstancePackageError> {
     info!("Importing MultiMC instance...");
     let mmc_pack: MmcPack = serde_json::from_str(mmc_pack).json(mmc_pack.to_owned())?;
 
@@ -127,7 +127,7 @@ pub async fn import(
     Ok(instance)
 }
 
-async fn setup_details(instance: &InstanceSelection) -> Result<(), InstancePackageError> {
+async fn setup_details(instance: &Instance) -> Result<(), InstancePackageError> {
     if exists(&instance.get_instance_path().join("patches/org.lwjgl.json")).await {
         let mut details = VersionDetails::load(instance).await?;
         details.libraries.retain(|lib| {
@@ -185,7 +185,7 @@ fn general_get<'a>(ini: &'a Ini, key: &str) -> Result<&'a str, InstancePackageEr
         .ok_or_else(|| InstancePackageError::IniFieldMissing("General".to_owned(), key.to_owned()))
 }
 
-async fn get_instance(ini: &Ini) -> Result<InstanceSelection, InstancePackageError> {
+async fn get_instance(ini: &Ini) -> Result<Instance, InstancePackageError> {
     let mut instance_name = general_get(ini, "name")?.to_owned();
 
     // If `MyInstance` exists, try `MyInstance (1)`, `(2)`...
@@ -203,7 +203,7 @@ async fn get_instance(ini: &Ini) -> Result<InstanceSelection, InstancePackageErr
         instance_name = name;
     }
 
-    Ok(InstanceSelection::new(&instance_name, false))
+    Ok(Instance::client(&instance_name))
 }
 
 async fn read_config_ini(temp_dir: &Path) -> Result<Ini, InstancePackageError> {
@@ -266,7 +266,7 @@ async fn get_instance_recipe(mmc_pack: &MmcPack) -> Result<InstanceRecipe, Insta
 
 async fn install_loader(
     sender: Option<&Sender<GenericProgress>>,
-    instance: &InstanceSelection,
+    instance: &Instance,
     instance_recipe: &InstanceRecipe,
 ) -> Result<(), InstancePackageError> {
     if let Some(loader) = instance_recipe.loader {
@@ -299,7 +299,7 @@ async fn install_loader(
 
 async fn install_fabric(
     sender: Option<&Sender<GenericProgress>>,
-    instance_selection: &InstanceSelection,
+    instance_selection: &Instance,
     version: Option<String>,
     is_quilt: bool,
 ) -> Result<(), InstancePackageError> {
@@ -327,7 +327,7 @@ async fn install_fabric(
             version
         } else {
             // Using 1.14.4 just to get the overall list of versions.
-            get_list_of_versions_from_backend("1.14.4", backend, false)
+            get_list_of_versions_from_backend("1.14.4", backend, ql_core::InstanceKind::Client)
                 .await?
                 .first()
                 .map_or_else(
@@ -400,7 +400,7 @@ async fn install_fabric(
 async fn copy_files(
     temp_dir: &Path,
     sender: Option<Arc<Sender<GenericProgress>>>,
-    instance_selection: &InstanceSelection,
+    instance_selection: &Instance,
 ) -> Result<(), InstancePackageError> {
     let src = temp_dir.join("minecraft");
     if src.is_dir() {
@@ -424,7 +424,7 @@ async fn copy_files(
 
 async fn copy_folder_over(
     temp_dir: &Path,
-    instance_selection: &InstanceSelection,
+    instance_selection: &Instance,
     path: &'static str,
 ) -> Result<(), InstancePackageError> {
     let src = temp_dir.join(path);
@@ -460,7 +460,7 @@ async fn create_minecraft_instance(
 
 async fn mmc_forge(
     sender: Option<&Sender<GenericProgress>>,
-    instance_selection: &InstanceSelection,
+    instance_selection: &Instance,
     version: Option<String>,
     is_neoforge: bool,
 ) -> Result<(), InstancePackageError> {
diff --git a/crates/ql_servers/src/create.rs b/crates/ql_servers/src/create.rs
--- a/crates/ql_servers/src/create.rs
+++ b/crates/ql_servers/src/create.rs
@@ -107,8 +107,11 @@ async fn write_config(
     server_dir: &std::path::Path,
     version_json: &VersionDetails,
 ) -> Result<(), ServerError> {
-    let server_config =
-        InstanceConfigJson::new(true, is_classic_server, VersionInfo::new(&version_json.id));
+    let server_config = InstanceConfigJson::new(
+        ql_core::InstanceKind::Server,
+        is_classic_server,
+        VersionInfo::new(&version_json.id),
+    );
     let server_config_path = server_dir.join("config.json");
     tokio::fs::write(
         &server_config_path,
diff --git a/crates/ql_servers/src/run.rs b/crates/ql_servers/src/run.rs
--- a/crates/ql_servers/src/run.rs
+++ b/crates/ql_servers/src/run.rs
@@ -5,7 +5,7 @@ use std::{
 };
 
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoIoError, LAUNCHER_DIR, LaunchedProcess, Loader,
+    GenericProgress, Instance, IntoIoError, LAUNCHER_DIR, LaunchedProcess, Loader,
     find_forge_shim_file, info,
     json::{InstanceConfigJson, VersionDetails},
     no_window, pt,
@@ -35,7 +35,7 @@ use crate::ServerError;
 /// - Forge shim file (`forge-*-shim.jar`) couldn't be found
 /// - Other stuff I'm too dumb to see
 pub async fn run(
-    name: String,
+    name: Arc<str>,
     java_install_progress: Option<Sender<GenericProgress>>,
 ) -> Result<LaunchedProcess, ServerError> {
     let launcher = ServerLauncher::new(&name).await?;
@@ -74,7 +74,7 @@ pub async fn run(
     }
     Ok(LaunchedProcess {
         child: Arc::new(Mutex::new(child)),
-        instance: InstanceSelection::Server(name),
+        instance: Instance::server(&name),
         is_classic_server: launcher.is_classic_server(),
     })
 }
diff --git a/quantum_launcher/src/cli/command.rs b/quantum_launcher/src/cli/command.rs
--- a/quantum_launcher/src/cli/command.rs
+++ b/quantum_launcher/src/cli/command.rs
@@ -1,11 +1,11 @@
 use owo_colors::{OwoColorize, Style};
 use ql_core::{
-    InstanceSelection, IntoStringError, LAUNCHER_DIR, ListEntry, Loader, OptifineUniqueVersion,
-    eeprintln, err, info,
+    Instance, InstanceKind, IntoStringError, ListEntry, Loader, OptifineUniqueVersion, eeprintln,
+    err, info,
     json::{InstanceConfigJson, VersionDetails},
 };
 use ql_mod_manager::loaders::LoaderInstallResult;
-use std::{path::PathBuf, process::exit};
+use std::{path::PathBuf, process::exit, sync::Arc};
 
 use crate::{
     cli::{QLoader, account::refresh_account, helpers::render_row},
@@ -14,7 +14,7 @@ use crate::{
 
 use super::PrintCmd;
 
-pub fn list_available_versions() {
+pub fn list_available_versions(kind: InstanceKind) {
     use std::io::Write;
 
     eeprintln!("Listing downloadable versions...");
@@ -31,13 +31,21 @@ pub fn list_available_versions() {
 
     let mut stdout = std::io::stdout().lock();
     for version in versions {
+        match kind {
+            InstanceKind::Client => {}
+            InstanceKind::Server => {
+                if !version.supports_server {
+                    continue;
+                }
+            }
+        }
         writeln!(stdout, "{version}").unwrap();
     }
 }
 
 pub fn list_instances(
     properties: Option<&[String]>,
-    is_server: bool,
+    kind: InstanceKind,
 ) -> Result<(), Box<dyn std::error::Error>> {
     use std::fmt::Write;
 
@@ -57,15 +65,14 @@ pub fn list_instances(
 
     let runtime = tokio::runtime::Runtime::new()?;
 
-    let dirname = if is_server { "servers" } else { "instances" };
-    let (instances, _) = tokio::runtime::Runtime::new()?.block_on(get_entries(is_server))?;
+    let (instances, _) = tokio::runtime::Runtime::new()?.block_on(get_entries(kind))?;
 
     let mut cmds_name = String::new();
     let mut cmds_version = String::new();
     let mut cmds_loader = String::new();
 
     for instance in instances {
-        let instance_dir = LAUNCHER_DIR.join(dirname).join(&instance);
+        let instance_dir = kind.get_root_directory().join(&instance);
         for cmd in &cmds {
             match cmd {
                 PrintCmd::Name => {
@@ -134,21 +141,26 @@ pub async fn create_instance(
     instance_name: String,
     version: String,
     skip_assets: bool,
-    servers: bool,
+    kind: InstanceKind,
 ) -> Result<(), Box<dyn std::error::Error>> {
     let entry = ListEntry::new(version);
-    if servers {
-        ql_servers::create_server(instance_name, entry, None).await?;
-    } else {
-        ql_instances::create_instance(instance_name, entry, None, !skip_assets).await?;
+
+    match kind {
+        InstanceKind::Client => {
+            ql_instances::create_instance(instance_name, entry, None, !skip_assets).await?;
+        }
+        InstanceKind::Server => {
+            ql_servers::create_server(instance_name, entry, None).await?;
+        }
     }
 
     Ok(())
 }
 
 pub fn delete_instance(
-    instance_name: String,
+    instance_name: &str,
     force: bool,
+    kind: InstanceKind,
 ) -> Result<(), Box<dyn std::error::Error>> {
     if !force {
         println!(
@@ -164,7 +176,7 @@ pub fn delete_instance(
         }
     }
 
-    let instance = InstanceSelection::Instance(instance_name);
+    let instance = Instance::new(instance_name, kind);
     let deleted_instance_dir = instance.get_instance_path();
     std::fs::remove_dir_all(&deleted_instance_dir)?;
     info!("Deleted instance {}", instance.get_name());
@@ -196,32 +208,35 @@ fn confirm_action() -> bool {
 }
 
 pub async fn launch_instance(
-    instance_name: String,
+    instance_name: &str,
     username: String,
     use_account: bool,
-    servers: bool,
+    kind: InstanceKind,
     show_progress: bool,
     account_type: Option<&str>,
 ) -> Result<(), Box<dyn std::error::Error>> {
-    let account = if servers {
-        None
-    } else {
+    let account = if matches!(kind, InstanceKind::Client) {
         refresh_account(&username, use_account, show_progress, account_type).await?
+    } else {
+        None
     };
 
-    let child = if servers {
+    let instance_name = Arc::from(instance_name);
+
+    let child = match kind {
+        InstanceKind::Client => {
+            ql_instances::launch(
+                instance_name,
+                username,
+                None,
+                account.clone(),
+                None, // No global defaults in CLI mode
+                Vec::new(),
+            )
+            .await?
+        }
         // TODO: stdin input
-        ql_servers::run(instance_name.clone(), None).await?
-    } else {
-        ql_instances::launch(
-            instance_name.clone(),
-            username,
-            None,
-            account.clone(),
-            None, // No global defaults in CLI mode
-            Vec::new(),
-        )
-        .await?
+        InstanceKind::Server => ql_servers::run(instance_name, None).await?,
     };
 
     let mut censors = Vec::new();
@@ -243,11 +258,10 @@ pub async fn launch_instance(
     Ok(())
 }
 
-pub async fn loader(cmd: QLoader, servers: bool) -> Result<(), Box<dyn std::error::Error>> {
+pub async fn loader(cmd: QLoader, kind: InstanceKind) -> Result<(), Box<dyn std::error::Error>> {
     match cmd {
         QLoader::Info { instance } => {
-            let json =
-                InstanceConfigJson::read(&InstanceSelection::new(&instance, servers)).await?;
+            let json = InstanceConfigJson::read(&Instance::new(&instance, kind)).await?;
             println!("Kind: {}", json.mod_type);
             if let Some(info) = json.mod_type_info {
                 if let Some(version) = info.version {
@@ -282,7 +296,7 @@ pub async fn loader(cmd: QLoader, servers: bool) -> Result<(), Box<dyn std::erro
                 exit(1)
             };
 
-            let instance = InstanceSelection::new(&instance, servers);
+            let instance = Instance::new(&instance, kind);
             let mt = InstanceConfigJson::read(&instance).await?.mod_type;
 
             if mt == loader {
@@ -319,7 +333,7 @@ pub async fn loader(cmd: QLoader, servers: bool) -> Result<(), Box<dyn std::erro
             }
         }
         QLoader::Uninstall { instance } => {
-            let instance = InstanceSelection::new(&instance, servers);
+            let instance = Instance::new(&instance, kind);
             ql_mod_manager::loaders::uninstall_loader(instance).await?;
         }
     }
@@ -328,7 +342,7 @@ pub async fn loader(cmd: QLoader, servers: bool) -> Result<(), Box<dyn std::erro
 
 async fn install_optifine(
     more: Option<String>,
-    instance: InstanceSelection,
+    instance: Instance,
 ) -> Result<(), Box<dyn std::error::Error + 'static>> {
     let details = VersionDetails::load(&instance).await?;
     if details.get_id() == "b1.7.3" {
@@ -349,7 +363,7 @@ async fn install_optifine(
     };
 
     ql_mod_manager::loaders::optifine::install(
-        instance.get_name().to_owned(),
+        instance,
         PathBuf::from(more),
         None,
         None,
diff --git a/quantum_launcher/src/cli/mod.rs b/quantum_launcher/src/cli/mod.rs
--- a/quantum_launcher/src/cli/mod.rs
+++ b/quantum_launcher/src/cli/mod.rs
@@ -1,11 +1,11 @@
 use std::{
     path::PathBuf,
-    sync::{LazyLock, RwLock},
+    sync::{Arc, LazyLock, RwLock},
 };
 
 use clap::{Parser, Subcommand};
 use owo_colors::{OwoColorize, Style};
-use ql_core::{LAUNCHER_VERSION_NAME, REDACT_SENSITIVE_INFO, WEBSITE, err};
+use ql_core::{InstanceKind, LAUNCHER_VERSION_NAME, REDACT_SENSITIVE_INFO, WEBSITE, err};
 
 use crate::{
     cli::helpers::render_row,
@@ -57,7 +57,7 @@ enum QSubCommand {
     },
     #[command(about = "Launches an instance")]
     Launch {
-        instance_name: String,
+        instance_name: Arc<str>,
         #[arg(help = "Username to play with")]
         username: String,
 
@@ -213,6 +213,12 @@ pub fn start_cli(is_dir_err: bool, launcher_dir: &mut Option<PathBuf>) {
         unsafe { std::env::set_var("QLDIR", p) };
     }
 
+    let kind = if cli.server {
+        InstanceKind::Server
+    } else {
+        InstanceKind::Client
+    };
+
     if let Some(subcommand) = cli.command {
         if is_dir_err && cli.dir.is_none() {
             std::process::exit(1);
@@ -229,7 +235,7 @@ pub fn start_cli(is_dir_err: bool, launcher_dir: &mut Option<PathBuf>) {
                     instance_name,
                     version,
                     skip_assets,
-                    cli.server,
+                    kind,
                 )));
             }
             QSubCommand::Launch {
@@ -240,10 +246,10 @@ pub fn start_cli(is_dir_err: bool, launcher_dir: &mut Option<PathBuf>) {
                 account_type,
             } => {
                 let res = runtime.block_on(command::launch_instance(
-                    instance_name,
+                    &instance_name,
                     username,
                     use_account,
-                    cli.server,
+                    kind,
                     show_progress,
                     account_type.as_deref(),
                 ));
@@ -263,18 +269,18 @@ pub fn start_cli(is_dir_err: bool, launcher_dir: &mut Option<PathBuf>) {
             }
 
             QSubCommand::ListAvailableVersions => {
-                command::list_available_versions();
+                command::list_available_versions(kind);
                 std::process::exit(0);
             }
             QSubCommand::Delete {
                 instance_name,
                 force,
-            } => quit(command::delete_instance(instance_name, force)),
+            } => quit(command::delete_instance(&instance_name, force, kind)),
             QSubCommand::ListInstalled { properties } => {
-                quit(command::list_instances(properties.as_deref(), cli.server));
+                quit(command::list_instances(properties.as_deref(), kind));
             }
             QSubCommand::Loader(cmd) => {
-                quit(runtime.block_on(command::loader(cmd, cli.server)));
+                quit(runtime.block_on(command::loader(cmd, kind)));
             }
         }
     } else {
diff --git a/quantum_launcher/src/config/mod.rs b/quantum_launcher/src/config/mod.rs
--- a/quantum_launcher/src/config/mod.rs
+++ b/quantum_launcher/src/config/mod.rs
@@ -7,6 +7,7 @@ use ql_core::{
 };
 use ql_instances::auth::{AccountData, AccountType};
 use serde::{Deserialize, Serialize};
+use std::sync::Arc;
 use std::{
     collections::{HashMap, HashSet},
     path::Path,
@@ -181,28 +182,24 @@ impl LauncherConfig {
         Ok(())
     }
 
-    pub fn update_sidebar(&mut self, instances: &[String], is_server: bool) {
+    pub fn update_sidebar(&mut self, instances: &[String], kind: InstanceKind) {
         let sidebar = self.sidebar.get_or_insert_with(SidebarConfig::default);
-        let kind = if is_server {
-            InstanceKind::Server
-        } else {
-            InstanceKind::Client
-        };
 
         // Remove nonexistent instances
         sidebar.retain_instances(|node| match &node.kind {
             SidebarNodeKind::Instance(instance_kind) => {
-                (*instance_kind == kind && instances.contains(&node.name))
+                (*instance_kind == kind && instances.iter().any(|n| n == &*node.name))
                     || (*instance_kind != kind)
             }
             SidebarNodeKind::Folder { .. } => true,
         });
         // Add new instances
         for instance in instances {
             if !sidebar.contains_instance(instance, kind) {
-                sidebar
-                    .list
-                    .push(SidebarNode::new_instance(instance.clone(), kind));
+                sidebar.list.push(SidebarNode::new_instance(
+                    Arc::from(instance.as_str()),
+                    kind,
+                ));
             }
         }
     }
@@ -483,9 +480,10 @@ pub enum UiWindowDecorations {
 
 #[derive(Serialize, Deserialize, Debug, Clone)]
 pub struct PersistentSettings {
-    pub selected_instance: Option<String>,
-    pub selected_server: Option<String>,
+    pub selected_instance: Option<Arc<str>>,
     pub selected_remembered: bool,
+    // Since: TBD
+    pub selected_instance_kind: Option<InstanceKind>,
 
     #[serde(default = "default_true")]
     pub write_mod_update_changelog: bool,
@@ -501,7 +499,7 @@ impl Default for PersistentSettings {
     fn default() -> Self {
         Self {
             selected_instance: None,
-            selected_server: None,
+            selected_instance_kind: None,
             selected_remembered: true,
             write_mod_update_changelog: true,
             create_instance_filters: None,
diff --git a/quantum_launcher/src/config/sidebar/mod.rs b/quantum_launcher/src/config/sidebar/mod.rs
--- a/quantum_launcher/src/config/sidebar/mod.rs
+++ b/quantum_launcher/src/config/sidebar/mod.rs
@@ -1,4 +1,7 @@
-use std::collections::{HashMap, HashSet};
+use std::{
+    collections::{HashMap, HashSet},
+    sync::Arc,
+};
 
 use ql_core::InstanceKind;
 use serde::{Deserialize, Serialize};
@@ -52,7 +55,7 @@ impl SidebarConfig {
             }
 
             let index = index?;
-            let folder = SidebarNode::new_folder(name.to_owned());
+            let folder = SidebarNode::new_folder(Arc::from(name));
             let id = folder
                 .get_folder_id()
                 .expect("should be folder, not instance");
@@ -63,7 +66,7 @@ impl SidebarConfig {
         if let Some(selection) = selection {
             for (i, child) in self.list.iter_mut().enumerate() {
                 if *child == selection {
-                    let folder = SidebarNode::new_folder(name.to_owned());
+                    let folder = SidebarNode::new_folder(Arc::from(name));
                     let id = folder
                         .get_folder_id()
                         .expect("should be folder, not instance");
@@ -76,7 +79,7 @@ impl SidebarConfig {
             }
         }
 
-        let folder = SidebarNode::new_folder(name.to_owned());
+        let folder = SidebarNode::new_folder(Arc::from(name));
         let id = folder
             .get_folder_id()
             .expect("should be folder, not instance");
@@ -106,7 +109,7 @@ impl SidebarConfig {
     pub fn rename(&mut self, selection: &SidebarSelection, new_name: &str) {
         fn walk(node: &mut SidebarNode, selection: &SidebarSelection, new_name: &str) -> bool {
             if node == selection {
-                new_name.clone_into(&mut node.name);
+                node.name = Arc::from(new_name);
                 return true;
             }
 
@@ -201,7 +204,7 @@ impl SidebarConfig {
 
 #[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
 pub struct SidebarNode {
-    pub name: String,
+    pub name: Arc<str>,
     // icon: Option<String>
     pub kind: SidebarNodeKind,
     #[serde(flatten)]
@@ -213,7 +216,7 @@ impl SidebarNode {
     fn contains_instance(&self, name: &str, instance_kind: InstanceKind) -> bool {
         match &self.kind {
             SidebarNodeKind::Instance(kind) => {
-                if *kind == instance_kind && self.name == name {
+                if *kind == instance_kind && &*self.name == name {
                     return true;
                 }
             }
@@ -239,7 +242,7 @@ impl SidebarNode {
     }
 
     #[must_use]
-    pub fn new_folder(name: String) -> Self {
+    pub fn new_folder(name: Arc<str>) -> Self {
         SidebarNode {
             name,
             kind: SidebarNodeKind::Folder(SidebarFolder::default()),
@@ -248,7 +251,7 @@ impl SidebarNode {
     }
 
     #[must_use]
-    pub fn new_instance(name: String, kind: InstanceKind) -> Self {
+    pub fn new_instance(name: Arc<str>, kind: InstanceKind) -> Self {
         SidebarNode {
             name,
             kind: SidebarNodeKind::Instance(kind),
diff --git a/quantum_launcher/src/config/sidebar/types.rs b/quantum_launcher/src/config/sidebar/types.rs
--- a/quantum_launcher/src/config/sidebar/types.rs
+++ b/quantum_launcher/src/config/sidebar/types.rs
@@ -1,6 +1,6 @@
-use std::collections::HashMap;
+use std::{collections::HashMap, sync::Arc};
 
-use ql_core::{InstanceKind, InstanceSelection};
+use ql_core::{Instance, InstanceKind};
 use serde::{Deserialize, Serialize};
 
 use crate::config::sidebar::SidebarNode;
@@ -25,22 +25,22 @@ impl PartialEq<SidebarSelection> for SidebarNode {
     }
 }
 
-impl PartialEq<InstanceSelection> for SidebarNode {
-    fn eq(&self, other: &InstanceSelection) -> bool {
+impl PartialEq<Instance> for SidebarNode {
+    fn eq(&self, other: &Instance) -> bool {
         match &self.kind {
             SidebarNodeKind::Instance(kind) => {
-                kind.is_server() == other.is_server() && self.name == other.get_name()
+                kind.is_server() == other.is_server() && &*self.name == other.get_name()
             }
             SidebarNodeKind::Folder(_) => false,
         }
     }
 }
 
-impl PartialEq<InstanceSelection> for SidebarSelection {
-    fn eq(&self, other: &InstanceSelection) -> bool {
+impl PartialEq<Instance> for SidebarSelection {
+    fn eq(&self, other: &Instance) -> bool {
         match self {
             SidebarSelection::Instance(name, instance_kind) => {
-                instance_kind.is_server() == other.is_server() && name == other.get_name()
+                instance_kind.is_server() == other.is_server() && &**name == other.get_name()
             }
             SidebarSelection::Folder(_) => false,
         }
@@ -100,7 +100,7 @@ impl FolderId {
 
 #[derive(Debug, Clone, PartialEq, Eq, Hash)]
 pub enum SidebarSelection {
-    Instance(String, InstanceKind),
+    Instance(Arc<str>, InstanceKind),
     Folder(FolderId),
 }
 
diff --git a/quantum_launcher/src/main.rs b/quantum_launcher/src/main.rs
--- a/quantum_launcher/src/main.rs
+++ b/quantum_launcher/src/main.rs
@@ -30,7 +30,9 @@ use iced::{Settings, Task};
 use owo_colors::OwoColorize;
 use state::{Launcher, Message, get_entries};
 
-use ql_core::{IntoStringError, JsonFileError, constants::OS_NAME, err, file_utils, info, pt};
+use ql_core::{
+    InstanceKind, IntoStringError, JsonFileError, constants::OS_NAME, err, file_utils, info, pt,
+};
 
 use crate::{
     menu_renderer::FONT_DEFAULT,
@@ -116,8 +118,8 @@ impl Launcher {
             launcher,
             Task::batch([
                 check_for_updates_command,
-                Task::perform(get_entries(false), Message::CoreListLoaded),
-                Task::perform(get_entries(true), Message::CoreListLoaded),
+                Task::perform(get_entries(InstanceKind::Client), Message::CoreListLoaded),
+                Task::perform(get_entries(InstanceKind::Server), Message::CoreListLoaded),
                 load_notes_command,
                 Task::perform(ql_core::clean::dir("logs"), |n| {
                     Message::CoreCleanComplete(n.strerr())
diff --git a/quantum_launcher/src/mclog_upload.rs b/quantum_launcher/src/mclog_upload.rs
--- a/quantum_launcher/src/mclog_upload.rs
+++ b/quantum_launcher/src/mclog_upload.rs
@@ -1,5 +1,5 @@
 use ql_core::{
-    CLIENT, InstanceConfigJson, InstanceSelection, IntoJsonError, IntoStringError, Loader,
+    CLIENT, InstanceConfigJson, Instance, IntoJsonError, IntoStringError, Loader,
     json::VersionDetails, request::check_for_success,
 };
 use serde::Deserialize;
@@ -14,7 +14,7 @@ pub struct MclogsResponse {
 }
 
 /// Uploads log content to <https://mclo.gs> and returns the URL if successful
-pub async fn upload_log(content: String, instance: InstanceSelection) -> Result<String, String> {
+pub async fn upload_log(content: String, instance: Instance) -> Result<String, String> {
     #[derive(serde::Serialize)]
     struct Metadata {
         key: &'static str,
diff --git a/quantum_launcher/src/menu_renderer/create.rs b/quantum_launcher/src/menu_renderer/create.rs
--- a/quantum_launcher/src/menu_renderer/create.rs
+++ b/quantum_launcher/src/menu_renderer/create.rs
@@ -4,7 +4,7 @@ use iced::{
     Alignment, Length,
     widget::{self, column, row, tooltip::Position},
 };
-use ql_core::ListEntryKind;
+use ql_core::{InstanceKind, ListEntryKind};
 
 use crate::{
     cli::{EXPERIMENTAL_MMC_IMPORT, EXPERIMENTAL_SERVERS},
@@ -105,7 +105,7 @@ impl MenuCreateInstanceChoosing {
 
         let versions_iter = versions
             .iter()
-            .filter(|n| n.supports_server || !self.is_server)
+            .filter(|n| n.supports_server || !matches!(self.kind, InstanceKind::Server))
             .filter(|n| self.selected_categories.contains(&n.kind))
             .filter(|n| {
                 self.search_box.trim().is_empty()
@@ -202,17 +202,17 @@ impl MenuCreateInstanceChoosing {
             )
             .push_maybe(enabled_servers.then(|| {
                 let radio = |l, v| {
-                    widget::radio(l, v, Some(self.is_server), |t| {
-                        CreateInstanceMessage::ChangeIsServer(t).into()
+                    widget::radio(l, v, Some(self.kind), |t| {
+                        CreateInstanceMessage::ChangeKind(t).into()
                     })
                     .spacing(4)
                     .size(12)
                     .text_size(12)
                 };
                 row![
                     widget::text("Create:").size(12),
-                    radio("Instance", false),
-                    radio("Server", true)
+                    radio("Instance", InstanceKind::Client),
+                    radio("Server", InstanceKind::Server)
                 ]
                 .spacing(4)
                 .align_y(Alignment::Center)
@@ -228,20 +228,23 @@ impl MenuCreateInstanceChoosing {
         });
 
         let main_part = column![
-            widget::text!("Create {}", if self.is_server { "Server" } else { "Instance" })
+            widget::text!("Create {}", match self.kind {
+                InstanceKind::Client => "Instance",
+                InstanceKind::Server => "Server",
+            })
                 .size(24),
             row![
                 widget::text("Name:").size(18),
-                if self.is_server {
-                    widget::text_input(&format!("{} server", self.selected_version.name), &self.instance_name)
-                } else {
-                    widget::text_input(&self.selected_version.name, &self.instance_name)
-                }.on_input(|n| CreateInstanceMessage::NameInput(n).into())
+                match self.kind {
+                    InstanceKind::Server => widget::text_input(&format!("{} server", self.selected_version.name), &self.instance_name),
+                    InstanceKind::Client => widget::text_input(&self.selected_version.name, &self.instance_name),
+                }
+                .on_input(|n| CreateInstanceMessage::NameInput(n).into())
 
             ].spacing(10).align_y(Alignment::Center),
         ]
 
-        .push_maybe((!self.is_server).then(|| tooltip(
+        .push_maybe(matches!(self.kind, InstanceKind::Client).then(|| tooltip(
             row![
                 widget::Space::with_width(5),
                 widget::checkbox("Download assets?", self.download_assets).text_size(14).size(14).on_toggle(|t| Message::CreateInstance(CreateInstanceMessage::ChangeAssetToggle(t)))
diff --git a/quantum_launcher/src/menu_renderer/edit_instance.rs b/quantum_launcher/src/menu_renderer/edit_instance.rs
--- a/quantum_launcher/src/menu_renderer/edit_instance.rs
+++ b/quantum_launcher/src/menu_renderer/edit_instance.rs
@@ -13,7 +13,7 @@ use iced::{
     Alignment, Length,
     widget::{self, column, horizontal_space, row},
 };
-use ql_core::InstanceSelection;
+use ql_core::{Instance, InstanceKind};
 use ql_core::{
     JavaVersion,
     json::{
@@ -27,46 +27,44 @@ use super::Element;
 impl MenuEditInstance {
     pub fn view<'a>(
         &'a self,
-        selected_instance: &InstanceSelection,
+        selected_instance: &Instance,
         jar_choices: Option<&'a CustomJarState>,
     ) -> Element<'a> {
         widget::scrollable(
             checkered_list([
                 self.item_rename(selected_instance),
                 self.item_mem_alloc(),
 
-                if selected_instance.is_server() {
-                    column![widget::button("Edit server.properties")]
-                } else {
-                    resolution_dialog(
+                // Instance type specific settings
+                match selected_instance.kind {
+                    InstanceKind::Client => column![
+                        resolution_dialog(
                             self.config.global_settings.as_ref(),
                             |n| EditInstanceMessage::WindowWidthChanged(n).into(),
                             |n| EditInstanceMessage::WindowHeightChanged(n).into(),
-                    )
+                        ),
+                        column![
+                            widget::Space::with_height(5),
+                            widget::checkbox("DEBUG: Enable log system (recommended)", self.config.enable_logger.unwrap_or(true))
+                                .on_toggle(|t| EditInstanceMessage::LoggingToggle(t).into()),
+                            widget::text("Once disabled, logs will be printed in launcher STDOUT.\nRun the launcher executable from the terminal/command prompt to see it").size(12).style(tsubtitle),
+                            horizontal_space(),
+                        ].spacing(5),
+                    ].spacing(20),
+                    // TODO: Add option to edit server.properties in user-friendly way
+                    InstanceKind::Server => column![widget::button("Edit server.properties")],
                 },
 
-                widget::Column::new()
-                .push(
-                    column![
-                        widget::Space::with_height(5),
-                        widget::checkbox("DEBUG: Enable log system (recommended)", self.config.enable_logger.unwrap_or(true))
-                            .on_toggle(|t| EditInstanceMessage::LoggingToggle(t).into()),
-                        widget::text("Once disabled, logs will be printed in launcher STDOUT.\nRun the launcher executable from the terminal/command prompt to see it").size(12).style(tsubtitle),
-                        horizontal_space(),
-                    ].spacing(5)
-                )
-                .spacing(10),
-
                 self.item_args(),
                 self.item_java_override(),
                 self.item_custom_jar(jar_choices),
 
-                item_footer(selected_instance)
+                item_footer(selected_instance.kind)
             ]),
         ).style(LauncherTheme::style_scrollable_flat_extra_dark).spacing(1).into()
     }
 
-    fn item_rename(&self, selected_instance: &InstanceSelection) -> Column<'_> {
+    fn item_rename(&self, selected_instance: &Instance) -> Column<'_> {
         column![
             row![
                 widget::text(selected_instance.get_name().to_owned())
@@ -402,11 +400,9 @@ Heavy modpacks / High settings: 4-8 GB+"
     }
 }
 
-fn item_footer(
-    selected_instance: &InstanceSelection,
-) -> widget::Column<'static, Message, LauncherTheme> {
-    match selected_instance {
-        InstanceSelection::Instance(_) => column![
+fn item_footer(kind: InstanceKind) -> widget::Column<'static, Message, LauncherTheme> {
+    match kind {
+        InstanceKind::Client => column![
             row![
                 button_with_icon(icons::version_download_s(14), "Reinstall Libraries", 13)
                     .padding([4, 8])
@@ -424,7 +420,7 @@ fn item_footer(
                 .on_press(Message::DeleteInstanceMenu)
         ]
         .spacing(10),
-        InstanceSelection::Server(_) => {
+        InstanceKind::Server => {
             column![
                 button_with_icon(icons::bin(), "Delete Server", 16)
                     .on_press(Message::DeleteInstanceMenu)
diff --git a/quantum_launcher/src/menu_renderer/launch.rs b/quantum_launcher/src/menu_renderer/launch.rs
--- a/quantum_launcher/src/menu_renderer/launch.rs
+++ b/quantum_launcher/src/menu_renderer/launch.rs
@@ -2,7 +2,7 @@ use cfg_if::cfg_if;
 use frostmark::MarkWidget;
 use iced::widget::{column, horizontal_space, row, text_editor, tooltip::Position, vertical_space};
 use iced::{Alignment, Length, Padding, widget};
-use ql_core::{InstanceSelection, LAUNCHER_VERSION_NAME};
+use ql_core::{Instance, InstanceKind, LAUNCHER_VERSION_NAME};
 
 use crate::cli::EXPERIMENTAL_MMC_IMPORT;
 use crate::menu_renderer::onboarding::x86_warning;
@@ -79,7 +79,7 @@ impl Launcher {
         let tab_body = if let Some(selected) = &self.selected_instance {
             match menu.tab {
                 LaunchTab::Buttons => self.get_tab_main(menu, selected),
-                LaunchTab::Log => self.get_tab_logs(menu, selected.is_server()).into(),
+                LaunchTab::Log => self.get_tab_logs(menu, selected.kind).into(),
                 LaunchTab::Edit => {
                     if let Some(menu) = &menu.edit_instance {
                         menu.view(selected, self.custom_jar.as_ref())
@@ -167,11 +167,7 @@ impl Launcher {
         .into()
     }
 
-    fn get_tab_main<'a>(
-        &'a self,
-        menu: &'a MenuLaunch,
-        selected: &'a InstanceSelection,
-    ) -> Element<'a> {
+    fn get_tab_main<'a>(&'a self, menu: &'a MenuLaunch, selected: &'a Instance) -> Element<'a> {
         let is_running = self.is_process_running(selected);
 
         let main_buttons = row![
@@ -268,7 +264,7 @@ impl Launcher {
     pub fn get_tab_logs<'element>(
         &'element self,
         menu: &'element MenuLaunch,
-        is_server: bool,
+        kind: InstanceKind,
     ) -> widget::Column<'element, Message, LauncherTheme> {
         const TEXT_SIZE: f32 = 12.0;
 
@@ -326,13 +322,16 @@ impl Launcher {
             has_crashed.then_some(
                 widget::text!(
                     "The {} has crashed!",
-                    if is_server { "server" } else { "game" }
+                    match kind {
+                        InstanceKind::Client => "game",
+                        InstanceKind::Server => "server",
+                    }
                 )
                 .size(18),
             ),
         )
         .push_maybe(
-            is_server.then_some(
+            matches!(kind, InstanceKind::Server).then_some(
                 widget::text_input("Enter command...", command)
                     .on_input(Message::ServerCommandEdit)
                     .on_submit(Message::ServerCommandSubmit)
@@ -413,9 +412,9 @@ impl Launcher {
     pub(super) fn get_running_icon(
         &self,
         name: &str,
-        is_server: bool,
+        kind: InstanceKind,
     ) -> Option<widget::Row<'static, Message, LauncherTheme>> {
-        if self.is_process_running(&InstanceSelection::new(name, is_server)) {
+        if self.is_process_running(&Instance::new(name, kind)) {
             Some(row![
                 horizontal_space(),
                 icons::play_s(12),
@@ -426,7 +425,7 @@ impl Launcher {
         }
     }
 
-    fn is_process_running(&self, instance: &InstanceSelection) -> bool {
+    fn is_process_running(&self, instance: &Instance) -> bool {
         self.processes.contains_key(instance)
     }
 
@@ -473,7 +472,7 @@ impl Launcher {
 
     fn get_client_play_button(
         &'_ self,
-        selected: &InstanceSelection,
+        selected: &Instance,
     ) -> widget::Tooltip<'_, Message, LauncherTheme> {
         let play_button = button_with_icon(icons::play(), "Play", 16).width(98);
         let is_offline = self.account_selected == OFFLINE_ACCOUNT_NAME;
@@ -506,7 +505,7 @@ impl Launcher {
     }
 
     fn get_files_button(
-        selected_instance: &InstanceSelection,
+        selected_instance: &Instance,
     ) -> widget::Button<'_, Message, LauncherTheme> {
         button_with_icon(icons::folder(), "Files", 16)
             .on_press(Message::CoreOpenPath(
@@ -517,7 +516,7 @@ impl Launcher {
 
     fn get_server_play_button(
         &self,
-        selected: &InstanceSelection,
+        selected: &Instance,
     ) -> widget::Tooltip<'_, Message, LauncherTheme> {
         if self.processes.contains_key(selected) {
             tooltip(
@@ -711,8 +710,8 @@ fn get_sidebar_new_button(decor: bool) -> widget::Button<'static, Message, Launc
             },
         )
     })
-    .on_press(Message::CreateInstance(CreateInstanceMessage::ScreenOpen {
-        is_server: false,
-    }))
+    .on_press(Message::CreateInstance(CreateInstanceMessage::ScreenOpen(
+        InstanceKind::Client,
+    )))
     .width(Length::Fill)
 }
diff --git a/quantum_launcher/src/menu_renderer/mod.rs b/quantum_launcher/src/menu_renderer/mod.rs
--- a/quantum_launcher/src/menu_renderer/mod.rs
+++ b/quantum_launcher/src/menu_renderer/mod.rs
@@ -531,16 +531,12 @@ pub fn view_error(error: &'_ str) -> Element<'_> {
     .into()
 }
 
-pub fn view_log_upload_result(url: &'_ str, is_server: bool) -> Element<'_> {
+pub fn view_log_upload_result(url: &'_ str) -> Element<'_> {
     column![
         back_button().on_press(back_to_launch_screen(None)),
         column![
             widget::vertical_space(),
-            widget::text(format!(
-                "{} log uploaded successfully!",
-                if is_server { "Server" } else { "Game" }
-            ))
-            .size(20),
+            widget::text("Log uploaded successfully!").size(20),
             widget::text("Your log has been uploaded to mclo.gs. You can share the link below:")
                 .size(14),
             widget::container(
diff --git a/quantum_launcher/src/menu_renderer/mods/install_loader.rs b/quantum_launcher/src/menu_renderer/mods/install_loader.rs
--- a/quantum_launcher/src/menu_renderer/mods/install_loader.rs
+++ b/quantum_launcher/src/menu_renderer/mods/install_loader.rs
@@ -1,5 +1,5 @@
 use iced::{Alignment, Length, widget};
-use ql_core::InstanceSelection;
+use ql_core::Instance;
 use ql_mod_manager::loaders::fabric::{self, FabricVersionList, FabricVersionListItem};
 
 use crate::menu_renderer::Column;
@@ -97,7 +97,7 @@ impl MenuInstallOptifine {
 }
 
 impl MenuInstallFabric {
-    pub fn view(&'_ self, selected_instance: &InstanceSelection, tick_timer: usize) -> Element<'_> {
+    pub fn view(&'_ self, selected_instance: &Instance, tick_timer: usize) -> Element<'_> {
         match self {
             MenuInstallFabric::Loading { is_quilt, .. } => {
                 let loader_name = if *is_quilt { "Quilt" } else { "Fabric" };
@@ -151,7 +151,7 @@ impl MenuInstallFabric {
 }
 
 fn install_fabric_main<'a>(
-    selected_instance: &InstanceSelection,
+    selected_instance: &Instance,
     backend: &'a fabric::BackendType,
     fabric_version: &'a str,
     fabric_versions: &'a FabricVersionList,
diff --git a/quantum_launcher/src/menu_renderer/mods/jarmods.rs b/quantum_launcher/src/menu_renderer/mods/jarmods.rs
--- a/quantum_launcher/src/menu_renderer/mods/jarmods.rs
+++ b/quantum_launcher/src/menu_renderer/mods/jarmods.rs
@@ -1,5 +1,5 @@
 use iced::{Length, widget};
-use ql_core::InstanceSelection;
+use ql_core::Instance;
 
 use crate::{
     icons,
@@ -9,7 +9,7 @@ use crate::{
 };
 
 impl MenuEditJarMods {
-    pub fn view(&'_ self, selected_instance: &InstanceSelection) -> Element<'_> {
+    pub fn view(&'_ self, selected_instance: &Instance) -> Element<'_> {
         let menu_main = widget::row!(
             widget::container(
                 widget::scrollable(
diff --git a/quantum_launcher/src/menu_renderer/mods/mods_manage.rs b/quantum_launcher/src/menu_renderer/mods/mods_manage.rs
--- a/quantum_launcher/src/menu_renderer/mods/mods_manage.rs
+++ b/quantum_launcher/src/menu_renderer/mods/mods_manage.rs
@@ -2,7 +2,7 @@ use iced::{
     Alignment, Length,
     widget::{self, column, row, tooltip::Position},
 };
-use ql_core::{InstanceSelection, Loader, json::InstanceConfigJson};
+use ql_core::{Instance, InstanceKind, Loader, json::InstanceConfigJson};
 use ql_mod_manager::store::SelectedMod;
 
 use crate::{
@@ -27,7 +27,7 @@ pub const MODS_SIDEBAR_WIDTH: u16 = 190;
 impl MenuEditMods {
     pub fn view<'a>(
         &'a self,
-        selected_instance: &'a InstanceSelection,
+        selected_instance: &'a Instance,
         tick_timer: usize,
         images: &'a ImageState,
         window_height: f32,
@@ -110,7 +110,7 @@ impl MenuEditMods {
 
     fn get_sidebar<'a>(
         &'a self,
-        selected_instance: &'a InstanceSelection,
+        selected_instance: &'a Instance,
         tick_timer: usize,
     ) -> widget::Scrollable<'a, Message, LauncherTheme> {
         widget::scrollable(
@@ -128,7 +128,7 @@ impl MenuEditMods {
                     )
                 ]
                 .spacing(5),
-                self.get_mod_installer_buttons(selected_instance),
+                self.get_mod_installer_buttons(selected_instance.kind),
                 column![
                     button_with_icon(icons::download_s(15), "Download Content...", 14)
                         .on_press(InstallModsMessage::Open.into()),
@@ -192,10 +192,10 @@ impl MenuEditMods {
         }
     }
 
-    fn get_mod_installer_buttons(&'_ self, selected_instance: &InstanceSelection) -> Element<'_> {
+    fn get_mod_installer_buttons(&'_ self, kind: InstanceKind) -> Element<'_> {
         match self.config.mod_type {
-            Loader::Vanilla => match selected_instance {
-                InstanceSelection::Instance(_) => column![
+            Loader::Vanilla => match kind {
+                InstanceKind::Client => column![
                     "Install:",
                     row![
                         install_ldr("Fabric")
@@ -214,7 +214,7 @@ impl MenuEditMods {
                 ]
                 .spacing(5)
                 .into(),
-                InstanceSelection::Server(_) => column![
+                InstanceKind::Server => column![
                     "Install:",
                     row![
                         install_ldr("Fabric")
@@ -243,7 +243,7 @@ impl MenuEditMods {
 
             Loader::Forge => widget::Column::new()
                 .push_maybe(
-                    (!selected_instance.is_server())
+                    matches!(kind, InstanceKind::Client)
                         .then(|| Self::get_optifine_install_button(&self.config)),
                 )
                 .push(Self::get_uninstall_panel(self.config.mod_type))
diff --git a/quantum_launcher/src/menu_renderer/sidebar/mod.rs b/quantum_launcher/src/menu_renderer/sidebar/mod.rs
--- a/quantum_launcher/src/menu_renderer/sidebar/mod.rs
+++ b/quantum_launcher/src/menu_renderer/sidebar/mod.rs
@@ -1,8 +1,10 @@
+use std::sync::Arc;
+
 use iced::{
     Alignment, Length,
     widget::{self, column, row},
 };
-use ql_core::{InstanceKind, InstanceSelection};
+use ql_core::{Instance, InstanceKind};
 
 use crate::{
     config::sidebar::{FolderId, SidebarFolder, SidebarNode, SidebarNodeKind, SidebarSelection},
@@ -142,13 +144,13 @@ impl Launcher {
             return widget::Column::new().into();
         };
 
-        let text = widget::text(&node.name)
+        let text = widget::text(&*node.name)
             .size(15)
             .style(move |t: &LauncherTheme| t.style_text(Color::SecondLight));
 
         let view = widget::stack!(underline_maybe(
             widget::row![text]
-                .push_maybe(self.get_running_icon(&node.name, kind.is_server()))
+                .push_maybe(self.get_running_icon(&node.name, kind))
                 .padding([5, 14])
                 .width(Length::Fill)
                 .align_y(Alignment::Center),
@@ -160,11 +162,7 @@ impl Launcher {
             NodeMode::InTree(_) => mode
                 .get_button(view.push_maybe(drag_drop_receiver(menu, selection, node)))
                 .on_press_maybe((!is_selected).then(|| {
-                    MainMenuMessage::InstanceSelected(InstanceSelection::new(
-                        &node.name,
-                        kind.is_server(),
-                    ))
-                    .into()
+                    MainMenuMessage::InstanceSelected(Instance::new(&node.name, kind)).into()
                 }))
                 .into(),
             NodeMode::Dragged => drag_tooltip(row![mode.get_space(), view]).into(),
@@ -181,7 +179,7 @@ impl Launcher {
         &self,
         selection: SidebarSelection,
         elem: impl Into<Element<'a>>,
-        name: String,
+        name: Arc<str>,
     ) -> widget::MouseArea<'a, Message, LauncherTheme> {
         widget::mouse_area(elem).on_right_press(
             MainMenuMessage::Modal(Some(LaunchModal::SCtxMenu(
@@ -243,19 +241,16 @@ impl Launcher {
                         move || match inst {
                             SidebarSelection::Instance(name, kind) => {
                                 Message::Multiple(vec![
-                                    MainMenuMessage::InstanceSelected(InstanceSelection::new(
-                                        name,
-                                        kind.is_server(),
-                                    ))
-                                    .into(),
+                                    MainMenuMessage::InstanceSelected(Instance::new(name, *kind))
+                                        .into(),
                                     MainMenuMessage::ChangeTab(LaunchTab::Edit).into(),
                                     EditInstanceMessage::RenameToggle.into(),
                                 ])
                             }
                             SidebarSelection::Folder(folder_id) => {
                                 MainMenuMessage::Modal(Some(LaunchModal::SRenamingFolder(
                                     *folder_id,
-                                    name.clone(),
+                                    name.to_string(),
                                     false,
                                 )))
                                 .into()
@@ -284,7 +279,7 @@ impl Launcher {
         folder: &SidebarFolder,
     ) -> widget::Stack<'a, Message, LauncherTheme> {
         let text = if folder.is_expanded {
-            widget::text(&node.name)
+            widget::text(&*node.name)
         } else {
             widget::text!("{}...", node.name)
         }
diff --git a/quantum_launcher/src/message_handler/iced_event.rs b/quantum_launcher/src/message_handler/iced_event.rs
--- a/quantum_launcher/src/message_handler/iced_event.rs
+++ b/quantum_launcher/src/message_handler/iced_event.rs
@@ -11,7 +11,7 @@ use iced::{
     keyboard::{self, Key, key::Named},
 };
 use ql_core::{
-    InstanceSelection, err,
+    Instance, err,
     jarmod::{JarMod, JarMods},
     pt,
 };
@@ -159,7 +159,7 @@ impl Launcher {
                 // MAIN MENU
                 // ========
                 ("n", true, _, _, State::Launch(_)) => {
-                    CreateInstanceMessage::ScreenOpen { is_server: false }.into()
+                    CreateInstanceMessage::ScreenOpen(ql_core::InstanceKind::Client).into()
                 }
                 ("1", ctrl, alt, _, State::Launch(_)) if ctrl | alt => {
                     MainMenuMessage::ChangeTab(LaunchTab::Buttons).into()
@@ -280,7 +280,7 @@ impl Launcher {
     }
 
     fn load_jarmods_from_path(
-        selected_instance: &InstanceSelection,
+        selected_instance: &Instance,
         path: &Path,
         filename: &str,
         jarmods: &mut JarMods,
diff --git a/quantum_launcher/src/message_handler/mod.rs b/quantum_launcher/src/message_handler/mod.rs
--- a/quantum_launcher/src/message_handler/mod.rs
+++ b/quantum_launcher/src/message_handler/mod.rs
@@ -20,10 +20,10 @@ use ql_core::json::VersionDetails;
 use ql_core::json::instance_config::ModTypeInfo;
 use ql_core::read_log::{Diagnostic, ReadError};
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoIoError, IntoJsonError, IntoStringError, JsonFileError,
-    err, json::instance_config::InstanceConfigJson,
+    GenericProgress, Instance, IntoIoError, IntoJsonError, IntoStringError, JsonFileError, err,
+    json::instance_config::InstanceConfigJson,
 };
-use ql_core::{LaunchedProcess, info, pt};
+use ql_core::{InstanceKind, LaunchedProcess, info, pt};
 use ql_instances::auth::AccountData;
 use ql_mod_manager::{loaders, store::ModIndex};
 use std::{
@@ -41,19 +41,13 @@ pub const SIDEBAR_LIMIT_LEFT: f32 = 135.0;
 mod iced_event;
 
 impl Launcher {
-    pub fn select_instance(&mut self, instance: InstanceSelection) -> Task<Message> {
+    pub fn select_instance(&mut self, instance: Instance) -> Task<Message> {
         self.selected_instance = Some(instance.clone());
         self.load_edit_instance(None);
 
         {
             let persistent = self.config.c_persistent();
-            if persistent.selected_remembered {
-                match instance.clone() {
-                    InstanceSelection::Instance(n) => persistent.selected_instance = Some(n),
-                    InstanceSelection::Server(n) => persistent.selected_server = Some(n),
-                }
-                self.autosave.remove(&AutoSaveKind::LauncherConfig);
-            }
+            persistent.selected_instance = Some(instance.name.clone());
         }
         self.load_logs();
         if let State::Launch(menu) = &mut self.state {
@@ -96,7 +90,7 @@ impl Launcher {
         let global_settings = self.config.global_settings.clone();
         let extra_java_args = self.config.extra_java_args.clone().unwrap_or_default();
 
-        let instance_name = self.instance().get_name().to_owned();
+        let instance_name = self.instance().name.clone();
         Task::perform(
             async move {
                 ql_instances::launch(
@@ -206,14 +200,15 @@ impl Launcher {
 
     pub fn unselect_instance(&mut self) {
         self.selected_instance = None;
-        self.config.c_persistent().selected_instance = None;
-        self.config.c_persistent().selected_server = None;
+        let p = self.config.c_persistent();
+        p.selected_instance = None;
+        p.selected_instance_kind = None;
         self.autosave.remove(&AutoSaveKind::LauncherConfig);
     }
 
     pub fn load_edit_instance_inner(
         edit_instance: &mut Option<MenuEditInstance>,
-        selected_instance: &InstanceSelection,
+        selected_instance: &Instance,
     ) -> Result<(), JsonFileError> {
         let config_path = selected_instance.get_instance_path().join("config.json");
 
@@ -227,14 +222,12 @@ impl Launcher {
         // Use this to check for performance impact
         // std::thread::sleep(std::time::Duration::from_millis(500));
 
-        let instance_name = selected_instance.get_name();
-
         *edit_instance = Some(MenuEditInstance {
             main_class_mode: config_json.get_main_class_mode(),
             config: config_json,
             slider_value,
-            instance_name: instance_name.to_owned(),
-            old_instance_name: instance_name.to_owned(),
+            instance_name: selected_instance.name.to_string(),
+            old_instance_name: selected_instance.name.clone(),
             slider_text: format_memory(memory_mb),
             memory_input: memory_mb.to_string(),
             is_editing_name: false,
@@ -304,7 +297,7 @@ impl Launcher {
     pub fn set_game_exited(
         &mut self,
         status: ExitStatus,
-        instance: &InstanceSelection,
+        instance: &Instance,
         diagnostic: Option<Diagnostic>,
     ) {
         let kind = if instance.is_server() {
@@ -430,19 +423,18 @@ impl Launcher {
         command
     }
 
-    pub fn server_selected(&self) -> bool {
-        self.selected_instance
-            .as_ref()
-            .is_some_and(InstanceSelection::is_server)
-            || if let State::Create(MenuCreateInstance::Choosing(MenuCreateInstanceChoosing {
-                is_server,
+    pub fn selected_kind(&self) -> Option<InstanceKind> {
+        self.selected_instance.as_ref().map(|n| n.kind).or(
+            if let State::Create(MenuCreateInstance::Choosing(MenuCreateInstanceChoosing {
+                kind,
                 ..
             })) = &self.state
             {
-                *is_server
+                Some(*kind)
             } else {
-                false
-            }
+                None
+            },
+        )
     }
 
     pub fn get_selected_dot_minecraft_dir(&self) -> Option<PathBuf> {
@@ -556,14 +548,14 @@ impl Launcher {
         let Some(instance) = &self.selected_instance else {
             return Task::none();
         };
-        match instance {
-            InstanceSelection::Instance(_) => {
+        match instance.kind {
+            InstanceKind::Client => {
                 if let Some(process) = self.processes.remove(instance) {
                     let mut child = block_on(process.child.child.lock());
                     _ = child.start_kill();
                 }
             }
-            InstanceSelection::Server(_) => {
+            InstanceKind::Server => {
                 if let Some(GameProcess {
                     server_input: Some((stdin, has_issued_stop_command)),
                     child,
@@ -610,8 +602,8 @@ impl Launcher {
         }
         self.logs.remove(selected_instance);
 
-        match selected_instance {
-            InstanceSelection::Instance(_) => {
+        match selected_instance.kind {
+            InstanceKind::Client => {
                 if self.account_selected == OFFLINE_ACCOUNT_NAME
                     && (self.config.username.is_empty() || self.config.username.contains(' '))
                 {
@@ -631,11 +623,11 @@ impl Launcher {
                 // directly launch the game
                 self.launch_game(account_data)
             }
-            InstanceSelection::Server(server) => {
+            InstanceKind::Server => {
                 let (sender, receiver) = std::sync::mpsc::channel();
                 self.java_recv = Some(ProgressBar::with_recv(receiver));
 
-                let server = server.clone();
+                let server = selected_instance.name.clone();
                 Task::perform(
                     async move { ql_servers::run(server, Some(sender)).await.strerr() },
                     Message::LaunchEnd,
@@ -691,7 +683,7 @@ pub enum ForgeKind {
     OptiFine,
 }
 
-async fn copy_optifine_over(instance: &InstanceSelection) -> Result<(), String> {
+async fn copy_optifine_over(instance: &Instance) -> Result<(), String> {
     let instance_dir = instance.get_instance_path();
     let installer_path = instance_dir.join("optifine/OptiFine.jar");
     let mods_dir = instance_dir.join(".minecraft/mods");
diff --git a/quantum_launcher/src/message_update/create_instance.rs b/quantum_launcher/src/message_update/create_instance.rs
--- a/quantum_launcher/src/message_update/create_instance.rs
+++ b/quantum_launcher/src/message_update/create_instance.rs
@@ -1,5 +1,7 @@
 use iced::{Task, widget::pane_grid};
-use ql_core::{DownloadProgress, InstanceSelection, IntoStringError, ListEntry, ListEntryKind};
+use ql_core::{
+    DownloadProgress, Instance, InstanceKind, IntoStringError, ListEntry, ListEntryKind,
+};
 
 use crate::{
     message_handler::{SIDEBAR_LIMIT_LEFT, SIDEBAR_LIMIT_RIGHT},
@@ -26,8 +28,8 @@ impl Launcher {
             | CreateInstanceMessage::ImportResult(Err(err)) => {
                 self.set_error(err);
             }
-            CreateInstanceMessage::ScreenOpen { is_server } => {
-                return self.go_to_create_screen(is_server);
+            CreateInstanceMessage::ScreenOpen(kind) => {
+                return self.go_to_create_screen(kind);
             }
             CreateInstanceMessage::VersionsLoaded(res) => {
                 self.create_instance_finish_loading_versions_list(res);
@@ -43,9 +45,9 @@ impl Launcher {
                 *search_box = t;
             }),
             CreateInstanceMessage::SearchSubmit => {
-                iflet!(self, search_box, selected_version, is_server, selected_categories, list; {
+                iflet!(self, search_box, selected_version, kind, selected_categories, list; {
                     let iter = || list.iter().flatten().flatten()
-                        .filter(|n| n.supports_server || !*is_server)
+                        .filter(|n| n.supports_server || !matches!(kind, InstanceKind::Server))
                         .filter(|n| selected_categories.contains(&n.kind))
                         .filter(|n|
                             search_box.trim().is_empty()
@@ -98,8 +100,8 @@ impl Launcher {
             CreateInstanceMessage::NameInput(name) => iflet!(self, instance_name; {
                 *instance_name = name;
             }),
-            CreateInstanceMessage::ChangeIsServer(t) => iflet!(self, is_server; {
-                *is_server = t;
+            CreateInstanceMessage::ChangeKind(t) => iflet!(self, kind; {
+                *kind = t;
             }),
 
             CreateInstanceMessage::Start => return self.create_instance(),
@@ -171,7 +173,7 @@ then go to "Mods->Add File""#,
         });
     }
 
-    pub fn go_to_create_screen(&mut self, is_server: bool) -> Task<Message> {
+    pub fn go_to_create_screen(&mut self, kind: InstanceKind) -> Task<Message> {
         let (task, handle) = Task::perform(ql_instances::list_versions(), |n| {
             CreateInstanceMessage::VersionsLoaded(n.strerr()).into()
         })
@@ -200,7 +202,7 @@ then go to "Mods->Add File""#,
             search_box: String::new(),
             show_category_dropdown: false,
             selected_categories: self.config.c_persistent().get_create_instance_filters(),
-            is_server,
+            kind,
             sidebar_grid_state,
             sidebar_split,
         }));
@@ -209,14 +211,11 @@ then go to "Mods->Add File""#,
     }
 
     fn create_instance(&mut self) -> Task<Message> {
-        iflet!(self, instance_name, download_assets, selected_version, is_server; {
-            let is_server = *is_server;
-
+        iflet!(self, instance_name, download_assets, selected_version, kind; {
             let already_exists = {
-                let existing_instances = if is_server {
-                    self.server_list.as_ref()
-                } else {
-                    self.client_list.as_ref()
+                let existing_instances = match kind {
+                    InstanceKind::Client => self.client_list.as_ref(),
+                    InstanceKind::Server => self.server_list.as_ref(),
                 };
                 existing_instances.is_some_and(|n| {
                     n.contains(instance_name)
@@ -243,33 +242,33 @@ then go to "Mods->Add File""#,
                 instance_name.clone()
             };
             let download_assets = *download_assets;
+            let kind = *kind;
 
             self.state = State::Create(MenuCreateInstance::DownloadingInstance(progress));
 
-            return if is_server {
-                Task::perform(
+            return match kind {
+                InstanceKind::Server => Task::perform(
                     async move {
                         let sender = sender;
                         ql_servers::create_server(instance_name.clone(), version, Some(&sender))
                             .await
                             .strerr()
-                            .map(InstanceSelection::Server)
+                            .map(|n| Instance::server(&n))
                     },
                     |n| CreateInstanceMessage::End(n).into(),
-                )
-            } else {
-                Task::perform(
+                ),
+                InstanceKind::Client => Task::perform(
                     ql_instances::create_instance(
                         instance_name.clone(),
                         version,
                         Some(sender),
                         download_assets,
                     ),
                     |n| CreateInstanceMessage::End(
-                        n.strerr().map(InstanceSelection::Instance),
+                        n.strerr().map(|n| Instance::client(&n)),
                     ).into(),
                 )
-            };
+            }
         });
         Task::none()
     }
diff --git a/quantum_launcher/src/message_update/edit_instance.rs b/quantum_launcher/src/message_update/edit_instance.rs
--- a/quantum_launcher/src/message_update/edit_instance.rs
+++ b/quantum_launcher/src/message_update/edit_instance.rs
@@ -1,3 +1,5 @@
+use std::sync::Arc;
+
 use iced::Task;
 use ql_core::{
     IntoIoError, IntoStringError, LAUNCHER_DIR, err,
@@ -374,7 +376,8 @@ impl Launcher {
             return Ok(Task::none());
         }
 
-        if menu.old_instance_name == sanitized_name || menu.old_instance_name == menu.instance_name
+        if &*menu.old_instance_name == sanitized_name
+            || &*menu.old_instance_name == menu.instance_name
         {
             // Don't waste time talking to OS
             // and "renaming" instance if nothing has changed.
@@ -388,7 +391,7 @@ impl Launcher {
                 "instances"
             });
 
-        let old_path = instances_dir.join(&menu.old_instance_name);
+        let old_path = instances_dir.join(&*menu.old_instance_name);
         let new_path = instances_dir.join(&sanitized_name);
 
         if new_path.parent().is_none_or(|n| n != instances_dir) {
@@ -397,30 +400,27 @@ impl Launcher {
         }
 
         let old_name = menu.old_instance_name.clone();
-        menu.old_instance_name.clone_from(&sanitized_name);
+        menu.old_instance_name = Arc::from(sanitized_name.as_str());
         std::fs::rename(&old_path, &new_path)
             .path(&old_path)
             .strerr()?;
 
         let mut instance = self.selected_instance.clone().unwrap();
-        instance.set_name(sanitized_name.clone());
+        instance.name = Arc::from(sanitized_name.as_str());
 
         if let Some(s) = &mut self.config.sidebar {
             s.rename(
-                &SidebarSelection::Instance(old_name, instance.kind()),
+                &SidebarSelection::Instance(old_name, instance.kind),
                 &sanitized_name,
             );
         }
 
-        Ok(Task::perform(
-            get_entries(self.instance().is_server()),
-            move |n| {
-                Message::Multiple(vec![
-                    Message::CoreListLoaded(n),
-                    MainMenuMessage::InstanceSelected(instance.clone()).into(),
-                ])
-            },
-        ))
+        Ok(Task::perform(get_entries(self.instance().kind), move |n| {
+            Message::Multiple(vec![
+                Message::CoreListLoaded(n),
+                MainMenuMessage::InstanceSelected(instance.clone()).into(),
+            ])
+        }))
     }
 }
 
diff --git a/quantum_launcher/src/message_update/launch.rs b/quantum_launcher/src/message_update/launch.rs
--- a/quantum_launcher/src/message_update/launch.rs
+++ b/quantum_launcher/src/message_update/launch.rs
@@ -1,5 +1,5 @@
 use iced::Task;
-use ql_core::InstanceSelection;
+use ql_core::Instance;
 
 use crate::{
     config::sidebar::SidebarSelection,
@@ -22,8 +22,7 @@ impl Launcher {
                     }) = modal
                     {
                         if self.selected_instance.is_none() {
-                            self.selected_instance =
-                                Some(InstanceSelection::new(name, kind.is_server()));
+                            self.selected_instance = Some(Instance::new(name, *kind));
                         }
                     }
                     *modal = None;
diff --git a/quantum_launcher/src/message_update/manage_mods.rs b/quantum_launcher/src/message_update/manage_mods.rs
--- a/quantum_launcher/src/message_update/manage_mods.rs
+++ b/quantum_launcher/src/message_update/manage_mods.rs
@@ -1,7 +1,7 @@
 use iced::{Task, widget};
 use iced::{futures::executor::block_on, keyboard::Modifiers};
 use ql_core::file_utils::exists;
-use ql_core::{InstanceSelection, IntoIoError, IntoStringError, err, jarmod::JarMods};
+use ql_core::{Instance, IntoIoError, IntoStringError, err, jarmod::JarMods};
 use ql_mod_manager::store::{ModId, ModIndex, SelectedMod};
 use std::{collections::HashSet, path::PathBuf};
 
@@ -399,7 +399,7 @@ impl Launcher {
     }
 
     fn get_delete_mods_command(
-        selected_instance: InstanceSelection,
+        selected_instance: Instance,
         menu: &MenuEditMods,
     ) -> Task<Message> {
         let ids: Vec<ModId> = menu
diff --git a/quantum_launcher/src/message_update/mod.rs b/quantum_launcher/src/message_update/mod.rs
--- a/quantum_launcher/src/message_update/mod.rs
+++ b/quantum_launcher/src/message_update/mod.rs
@@ -199,8 +199,7 @@ impl Launcher {
         let (p_sender, p_recv) = std::sync::mpsc::channel();
         let (j_sender, j_recv) = std::sync::mpsc::channel();
 
-        let instance = self.instance();
-        let instance_name = instance.get_name().to_owned();
+        let instance = self.instance().clone();
         debug_assert!(!instance.is_server());
 
         let optifine_unique_version =
@@ -211,7 +210,7 @@ impl Launcher {
             {
                 *optifine_unique_version
             } else {
-                block_on(OptifineUniqueVersion::get(instance))
+                block_on(OptifineUniqueVersion::get(&instance))
             };
 
         let delete_installer = if let State::InstallOptifine(MenuInstallOptifine::Choosing {
@@ -231,12 +230,11 @@ impl Launcher {
         });
 
         let installer_path = installer_path.to_owned();
-
         Task::perform(
             // OptiFine does not support servers
             // so it's safe to assume we've selected an instance.
             loaders::optifine::install(
-                instance_name,
+                instance,
                 installer_path.clone(),
                 Some(p_sender),
                 Some(j_sender),
@@ -324,7 +322,7 @@ impl Launcher {
                 persistent.selected_remembered = t;
                 if !t {
                     persistent.selected_instance = None;
-                    persistent.selected_server = None;
+                    persistent.selected_instance_kind = None;
                 }
             }
             LauncherSettingsMessage::ToggleModUpdateChangelog(t) => {
diff --git a/quantum_launcher/src/message_update/mod_store.rs b/quantum_launcher/src/message_update/mod_store.rs
--- a/quantum_launcher/src/message_update/mod_store.rs
+++ b/quantum_launcher/src/message_update/mod_store.rs
@@ -2,8 +2,7 @@ use std::{collections::HashMap, time::Instant};
 
 use iced::{Task, futures::executor::block_on, widget::scrollable::AbsoluteOffset};
 use ql_core::{
-    InstanceConfigJson, InstanceSelection, IntoStringError, JsonFileError, err,
-    json::VersionDetails,
+    InstanceConfigJson, InstanceKind, IntoStringError, JsonFileError, err, json::VersionDetails,
 };
 use ql_mod_manager::store::{
     self, ModId, ModIndex, Query, QueryType, StoreBackendType, get_description,
@@ -16,7 +15,10 @@ use crate::state::{
 
 impl Launcher {
     pub fn update_install_mods(&mut self, message: InstallModsMessage) -> Task<Message> {
-        let is_server = matches!(&self.selected_instance, Some(InstanceSelection::Server(_)));
+        let is_server = matches!(
+            self.selected_instance.as_ref().map(|n| n.kind),
+            Some(InstanceKind::Server)
+        );
 
         match message {
             InstallModsMessage::LoadedDescription(Err(err))
@@ -286,15 +288,15 @@ impl Launcher {
     }
 
     async fn open_mods_store(&mut self) -> Result<Task<Message>, JsonFileError> {
-        let selection = self.instance();
+        let instance = self.instance();
 
-        let config = InstanceConfigJson::read(selection).await?;
+        let config = InstanceConfigJson::read(instance).await?;
         let version_json = if let State::EditMods(menu) = &self.state {
             menu.version_json.clone()
         } else {
-            Box::new(VersionDetails::load(selection).await?)
+            Box::new(VersionDetails::load(instance).await?)
         };
-        let mod_index = ModIndex::load(selection).await?;
+        let mod_index = ModIndex::load(instance).await?;
 
         let menu = MenuModsDownload {
             scroll_offset: AbsoluteOffset::default(),
@@ -317,10 +319,7 @@ impl Launcher {
             query_type: QueryType::Mods,
         };
         let command = Task::batch([
-            menu.search_store(
-                matches!(&self.selected_instance, Some(InstanceSelection::Server(_))),
-                0,
-            ),
+            menu.search_store(instance.is_server(), 0),
             menu.load_categories(),
         ]);
         self.state = State::ModsDownload(menu);
diff --git a/quantum_launcher/src/message_update/recommended.rs b/quantum_launcher/src/message_update/recommended.rs
--- a/quantum_launcher/src/message_update/recommended.rs
+++ b/quantum_launcher/src/message_update/recommended.rs
@@ -1,5 +1,5 @@
 use iced::{Task, futures::executor::block_on};
-use ql_core::{InstanceSelection, IntoStringError, JsonFileError, json::InstanceConfigJson};
+use ql_core::{Instance, IntoStringError, JsonFileError, json::InstanceConfigJson};
 use ql_mod_manager::store::{ModId, RECOMMENDED_MODS, RecommendedMod};
 
 use crate::state::{
@@ -132,7 +132,7 @@ impl Launcher {
 impl MenuRecommendedMods {
     pub fn get_config(
         &self,
-        instance: &InstanceSelection,
+        instance: &Instance,
     ) -> Result<InstanceConfigJson, JsonFileError> {
         if let MenuRecommendedMods::Loaded { config, .. }
         | MenuRecommendedMods::Loading { config, .. } = self
diff --git a/quantum_launcher/src/state/menu.rs b/quantum_launcher/src/state/menu.rs
--- a/quantum_launcher/src/state/menu.rs
+++ b/quantum_launcher/src/state/menu.rs
@@ -1,6 +1,7 @@
 use std::{
     collections::{HashMap, HashSet},
     path::PathBuf,
+    sync::Arc,
     time::Instant,
 };
 
@@ -19,7 +20,7 @@ use iced::{
     widget::{self, scrollable::AbsoluteOffset},
 };
 use ql_core::{
-    DownloadProgress, GenericProgress, InstanceSelection, IntoStringError, ListEntry,
+    DownloadProgress, GenericProgress, Instance, InstanceKind, IntoStringError, ListEntry,
     OptifineUniqueVersion,
     file_utils::DirItem,
     jarmod::JarMods,
@@ -64,7 +65,7 @@ pub enum LaunchModal {
     InstanceOptions,
 
     // Sidebar
-    SCtxMenu(Option<(SidebarSelection, String)>, (f32, f32)),
+    SCtxMenu(Option<(SidebarSelection, Arc<str>)>, (f32, f32)),
     SDragging {
         being_dragged: SidebarSelection,
         dragged_to: Option<SDragLocation>,
@@ -155,7 +156,7 @@ impl MenuLaunch {
         }
     }
 
-    pub fn reload_notes(&mut self, instance: InstanceSelection) -> Task<Message> {
+    pub fn reload_notes(&mut self, instance: Instance) -> Task<Message> {
         self.notes = None;
         Task::perform(ql_instances::notes::read(instance), |n| {
             NotesMessage::Loaded(n.strerr()).into()
@@ -181,7 +182,7 @@ pub struct MenuEditInstance {
     // Renaming Instance:
     pub is_editing_name: bool,
     pub instance_name: String,
-    pub old_instance_name: String,
+    pub old_instance_name: Arc<str>,
     // Changing RAM:
     pub slider_value: f32,
     pub slider_text: String,
@@ -316,7 +317,7 @@ pub enum MenuEditModsModal {
 impl MenuEditMods {
     pub fn update_locally_installed_mods(
         idx: &ModIndex,
-        selected_instance: &InstanceSelection,
+        selected_instance: &Instance,
     ) -> Task<Message> {
         let mut blacklist = Vec::new();
         for mod_info in idx.mods.values() {
@@ -405,7 +406,7 @@ pub struct MenuCreateInstanceChoosing {
     pub _loading_list_handle: iced::task::Handle,
     pub list: Result<Option<Vec<ListEntry>>, String>,
     // UI:
-    pub is_server: bool,
+    pub kind: InstanceKind,
     pub search_box: String,
     pub show_category_dropdown: bool,
     pub selected_categories: HashSet<ql_core::ListEntryKind>,
diff --git a/quantum_launcher/src/state/message.rs b/quantum_launcher/src/state/message.rs
--- a/quantum_launcher/src/state/message.rs
+++ b/quantum_launcher/src/state/message.rs
@@ -8,7 +8,7 @@ use crate::{
 };
 use iced::widget::{self, scrollable::AbsoluteOffset};
 use ql_core::{
-    InstanceSelection, LaunchedProcess, ListEntry, Loader,
+    Instance, InstanceKind, LaunchedProcess, ListEntry, Loader,
     file_utils::DirItem,
     jarmod::JarMods,
     json::instance_config::{MainClassMode, PreLaunchPrefixMode},
@@ -49,28 +49,26 @@ pub enum InstallPaperMessage {
 
 #[derive(Debug, Clone)]
 pub enum CreateInstanceMessage {
-    ScreenOpen {
-        is_server: bool,
-    },
+    ScreenOpen(InstanceKind),
     SidebarResize(f32),
 
     VersionsLoaded(Res<(Vec<ListEntry>, String)>),
     VersionSelected(ListEntry),
     NameInput(String),
     ChangeAssetToggle(bool),
-    ChangeIsServer(bool),
+    ChangeKind(InstanceKind),
 
     SearchInput(String),
     SearchSubmit,
     ContextMenuToggle,
     CategoryToggle(ql_core::ListEntryKind),
 
     Start,
-    End(Res<InstanceSelection>),
+    End(Res<Instance>),
 
     #[allow(unused)]
     Import,
-    ImportResult(Res<Option<InstanceSelection>>),
+    ImportResult(Res<Option<Instance>>),
 }
 
 #[derive(Debug, Clone)]
@@ -388,7 +386,7 @@ pub enum SidebarMessage {
 pub enum MainMenuMessage {
     ChangeTab(LaunchTab),
     Modal(Option<LaunchModal>),
-    InstanceSelected(InstanceSelection),
+    InstanceSelected(Instance),
     UsernameSet(String),
     SetInfoMessage(Option<InfoMessage>),
 }
@@ -456,7 +454,7 @@ pub enum Message {
     LaunchStart,
     LaunchEnd(Res<LaunchedProcess>),
     LaunchKill,
-    LaunchGameExited(Res<(ExitStatus, InstanceSelection, Option<Diagnostic>)>),
+    LaunchGameExited(Res<(ExitStatus, Instance, Option<Diagnostic>)>),
 
     DeleteInstanceMenu,
     DeleteInstance,
@@ -482,7 +480,7 @@ pub enum Message {
     CoreOpenPath(PathBuf),
     CoreCopyText(String),
     CoreTick,
-    CoreListLoaded(Res<(Vec<String>, bool)>),
+    CoreListLoaded(Res<(Vec<String>, InstanceKind)>),
     CoreOpenChangeLog,
     CoreOpenIntro,
     CoreEvent(iced::Event, iced::event::Status),
diff --git a/quantum_launcher/src/state/mod.rs b/quantum_launcher/src/state/mod.rs
--- a/quantum_launcher/src/state/mod.rs
+++ b/quantum_launcher/src/state/mod.rs
@@ -8,7 +8,7 @@ use std::{
 use iced::Task;
 use notify::Watcher;
 use ql_core::{
-    GenericProgress, InstanceSelection, IntoIoError, IntoStringError, IoError, JsonFileError,
+    GenericProgress, Instance, InstanceKind, IntoIoError, IntoStringError, IoError, JsonFileError,
     LAUNCHER_DIR, LAUNCHER_VERSION_NAME, LaunchedProcess, Progress, err,
     file_utils::{self, exists},
     read_log::LogLine,
@@ -46,7 +46,7 @@ pub struct InstanceLog {
 
 pub struct Launcher {
     pub state: State,
-    pub selected_instance: Option<InstanceSelection>,
+    pub selected_instance: Option<Instance>,
     pub config: LauncherConfig,
     pub theme: LauncherTheme,
     pub images: ImageState,
@@ -70,8 +70,8 @@ pub struct Launcher {
     pub client_watcher: Option<DirWatcher>,
     pub server_watcher: Option<DirWatcher>,
 
-    pub processes: HashMap<InstanceSelection, GameProcess>,
-    pub logs: HashMap<InstanceSelection, InstanceLog>,
+    pub processes: HashMap<Instance, GameProcess>,
+    pub logs: HashMap<Instance, InstanceLog>,
 
     pub window_state: WindowState,
     pub keys_pressed: HashSet<iced::keyboard::Key>,
@@ -172,13 +172,21 @@ impl Launcher {
         let (accounts, accounts_dropdown, account_selected) = load_accounts(&mut config);
 
         let persistent = config.c_persistent();
+        let selected_instance = persistent
+            .selected_instance
+            .as_ref()
+            .filter(|_| persistent.selected_remembered)
+            .map(|n| {
+                Instance::new(
+                    n,
+                    persistent
+                        .selected_instance_kind
+                        .unwrap_or(ql_core::InstanceKind::Client),
+                )
+            });
 
         Ok(Self {
-            selected_instance: persistent
-                .selected_instance
-                .as_ref()
-                .filter(|_| persistent.selected_remembered)
-                .map(|n| InstanceSelection::new(n, false)),
+            selected_instance,
             state,
             config,
             theme,
@@ -280,7 +288,7 @@ impl Launcher {
         }
     }
 
-    pub fn instance(&self) -> &InstanceSelection {
+    pub fn instance(&self) -> &Instance {
         self.selected_instance.as_ref().unwrap()
     }
 
@@ -390,18 +398,14 @@ fn load_account(
     }
 }
 
-pub async fn get_entries(is_server: bool) -> Res<(Vec<String>, bool)> {
-    let dir_path = file_utils::get_launcher_dir().strerr()?.join(if is_server {
-        "servers"
-    } else {
-        "instances"
-    });
+pub async fn get_entries(kind: InstanceKind) -> Res<(Vec<String>, InstanceKind)> {
+    let dir_path = kind.get_root_directory();
     if !exists(&dir_path).await {
         tokio::fs::create_dir_all(&dir_path)
             .await
             .path(&dir_path)
             .strerr()?;
-        return Ok((Vec::new(), is_server));
+        return Ok((Vec::new(), kind));
     }
 
     Ok((
@@ -412,7 +416,7 @@ pub async fn get_entries(is_server: bool) -> Res<(Vec<String>, bool)> {
             .filter(|n| !n.is_file)
             .map(|n| n.name)
             .collect(),
-        is_server,
+        kind,
     ))
 }
 
diff --git a/quantum_launcher/src/tick.rs b/quantum_launcher/src/tick.rs
--- a/quantum_launcher/src/tick.rs
+++ b/quantum_launcher/src/tick.rs
@@ -6,7 +6,7 @@ use std::{
 
 use iced::{Rectangle, Task, widget::text_editor};
 use ql_core::{
-    InstanceSelection, IntoIoError, IntoJsonError, IntoStringError, JsonFileError,
+    Instance, IntoIoError, IntoJsonError, IntoStringError, JsonFileError,
     constants::OS_NAME, json::InstanceConfigJson,
 };
 use ql_mod_manager::store::{ModConfig, ModId, ModIndex};
@@ -290,10 +290,10 @@ impl Launcher {
 
     pub fn read_game_logs(
         process: &GameProcess,
-        instance: &InstanceSelection,
-        logs: &mut HashMap<InstanceSelection, InstanceLog>,
+        instance: &Instance,
+        logs: &mut HashMap<Instance, InstanceLog>,
         log_state: &mut Option<LogState>,
-        selected_instance: Option<&InstanceSelection>,
+        selected_instance: Option<&Instance>,
     ) {
         let update_ui = selected_instance.is_some_and(|n| n == instance);
 
@@ -332,7 +332,7 @@ impl Launcher {
     }
 
     async fn save_config(
-        instance: InstanceSelection,
+        instance: Instance,
         config: InstanceConfigJson,
     ) -> Result<(), JsonFileError> {
         let mut config = config.clone();
@@ -350,7 +350,7 @@ impl Launcher {
 }
 
 impl MenuModsDownload {
-    pub fn tick(selected_instance: InstanceSelection) -> Task<Message> {
+    pub fn tick(selected_instance: Instance) -> Task<Message> {
         Task::perform(
             async move { ModIndex::load(&selected_instance).await },
             |n| InstallModsMessage::IndexUpdated(n.strerr()).into(),
@@ -409,7 +409,7 @@ pub fn sort_dependencies(
 }
 
 impl MenuEditMods {
-    fn tick(&mut self, instance_selection: &InstanceSelection) -> Task<Message> {
+    fn tick(&mut self, instance_selection: &Instance) -> Task<Message> {
         self.sorted_mods_list = sort_dependencies(&self.mods.mods, &self.locally_installed_mods);
 
         if let Some(progress) = &mut self.mod_update_progress {
diff --git a/quantum_launcher/src/update.rs b/quantum_launcher/src/update.rs
--- a/quantum_launcher/src/update.rs
+++ b/quantum_launcher/src/update.rs
@@ -1,5 +1,5 @@
 use iced::{Task, futures::executor::block_on};
-use ql_core::{IntoIoError, IntoStringError, LAUNCHER_DIR, err, file_utils::DirItem, info};
+use ql_core::{InstanceKind, IntoIoError, IntoStringError, err, file_utils::DirItem, info};
 use std::fmt::Write;
 use tokio::io::AsyncWriteExt;
 
@@ -152,18 +152,13 @@ impl Launcher {
                     tasks.push(CustomJarState::load());
                 }
 
-                for (i, watcher) in [self.client_watcher.as_ref(), self.server_watcher.as_ref()]
-                    .iter()
-                    .enumerate()
-                {
-                    const SERVER: usize = 1;
+                let mut watch_reload = |watcher: Option<&DirWatcher>, kind| {
                     if watcher.is_some_and(DirWatcher::has_changed) {
-                        tasks.push(Task::perform(
-                            get_entries(i == SERVER),
-                            Message::CoreListLoaded,
-                        ));
+                        tasks.push(Task::perform(get_entries(kind), Message::CoreListLoaded));
                     }
-                }
+                };
+                watch_reload(self.client_watcher.as_ref(), InstanceKind::Client);
+                watch_reload(self.server_watcher.as_ref(), InstanceKind::Server);
 
                 return Task::batch(tasks);
             }
@@ -239,8 +234,8 @@ impl Launcher {
                     _ = block_on(future);
                 }
             }
-            Message::CoreListLoaded(Ok((list, is_server))) => {
-                self.core_list_loaded(list, is_server);
+            Message::CoreListLoaded(Ok((list, kind))) => {
+                self.core_list_loaded(list, kind);
             }
             Message::CoreCopyText(txt) => {
                 return iced::clipboard::write(txt);
@@ -410,31 +405,34 @@ impl Launcher {
         Task::none()
     }
 
-    fn core_list_loaded(&mut self, list: Vec<String>, is_server: bool) {
-        self.config.update_sidebar(&list, is_server);
+    fn core_list_loaded(&mut self, list: Vec<String>, kind: InstanceKind) {
+        self.config.update_sidebar(&list, kind);
         self.autosave.remove(&AutoSaveKind::LauncherConfig);
 
         let persistent = self.config.c_persistent();
 
-        let selected = if is_server {
-            persistent.selected_server.as_ref()
-        } else {
-            persistent.selected_instance.as_ref()
-        };
-        if selected.is_some_and(|n| !list.contains(n)) {
+        let p_kind = persistent
+            .selected_instance_kind
+            .unwrap_or(InstanceKind::Client);
+        if p_kind == kind
+            && persistent
+                .selected_instance
+                .as_ref()
+                .is_some_and(|p| !list.iter().any(|n| n == &**p))
+        {
+            // The previously selected instance no longer exists
             self.unselect_instance();
         }
 
-        let (self_list, self_watcher) = if is_server {
-            (&mut self.server_list, &mut self.server_watcher)
-        } else {
-            (&mut self.client_list, &mut self.client_watcher)
+        let (self_list, self_watcher) = match kind {
+            InstanceKind::Client => (&mut self.client_list, &mut self.client_watcher),
+            InstanceKind::Server => (&mut self.server_list, &mut self.server_watcher),
         };
         *self_list = Some(list);
 
         if self_watcher.is_none() {
-            let dir = if is_server { "servers" } else { "instances" };
-            let watcher = match dir_watch(LAUNCHER_DIR.join(dir)) {
+            let dir = kind.get_root_directory();
+            let watcher = match dir_watch(dir) {
                 Ok(n) => n,
                 Err(err) => {
                     err!("Couldn't start dir watcher! {err}");
diff --git a/quantum_launcher/src/view.rs b/quantum_launcher/src/view.rs
--- a/quantum_launcher/src/view.rs
+++ b/quantum_launcher/src/view.rs
@@ -1,4 +1,5 @@
 use iced::{Alignment, Length, widget};
+use ql_core::InstanceKind;
 
 use crate::{
     DEBUG_LOG_BUTTON_HEIGHT,
@@ -105,10 +106,9 @@ impl Launcher {
                 self.window_state.size.1,
             ),
             State::Create(menu) => menu.view(
-                if self.server_selected() {
-                    self.server_list.as_deref()
-                } else {
-                    self.client_list.as_deref()
+                match self.selected_kind() {
+                    Some(InstanceKind::Server) => self.server_list.as_deref(),
+                    Some(InstanceKind::Client) | None => self.client_list.as_deref(),
                 },
                 self.tick_timer,
             ),
@@ -138,9 +138,7 @@ impl Launcher {
                     .spacing(10)
                     .into()
             }
-            State::LogUploadResult { url } => {
-                view_log_upload_result(url, self.instance().is_server())
-            }
+            State::LogUploadResult { url } => view_log_upload_result(url),
             State::CreateShortcut(menu) => menu.view(&self.accounts_dropdown),
             State::LoginAlternate(menu) => menu.view(self.tick_timer),
             State::ExportInstance(menu) => menu.view(self.tick_timer),
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
