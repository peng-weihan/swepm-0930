#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/meson.build b/meson.build
--- a/meson.build
+++ b/meson.build
@@ -437,6 +437,7 @@ _noctalia_sources = files(
   'src/ipc/ipc_client.cpp',
   'src/ipc/ipc_service.cpp',
   'src/launcher/app_provider.cpp',
+  'src/launcher/dmenu_provider.cpp',
   'src/launcher/emoji_provider.cpp',
   'src/launcher/math_provider.cpp',
   'src/launcher/plugin_launcher_provider.cpp',
diff --git a/src/app/application.cpp b/src/app/application.cpp
--- a/src/app/application.cpp
+++ b/src/app/application.cpp
@@ -17,6 +17,7 @@
 #include "i18n/i18n_service.h"
 #include "ipc/ipc_arg_parse.h"
 #include "launcher/app_provider.h"
+#include "launcher/dmenu_provider.h"
 #include "launcher/emoji_provider.h"
 #include "launcher/math_provider.h"
 #include "launcher/plugin_launcher_provider.h"
@@ -1744,6 +1745,7 @@ void Application::initUi() {
     );
   });
   reloadPluginLauncherProviders();
+  reloadDmenuProviders();
   reloadPluginPanels();
   m_overviewLauncherCapture.initialize(m_wayland, &m_renderContext, m_compositorPlatform, m_panelManager);
   m_overviewLauncherCapture.setEnabled(m_configService.config().shell.niriOverviewTypeToLaunchEnabled);
@@ -1961,6 +1963,11 @@ void Application::initUi() {
   // When config reloads, refresh any open panel: bar-driven attached decoration restyle and
   // shell-driven compositor blur.
   m_configService.addReloadCallback([this]() { m_panelManager.onConfigReloaded(); });
+  m_configService.addReloadCallback([this]() {
+    if (m_configService.lastChange().shell) {
+      reloadDmenuProviders();
+    }
+  });
   m_configService.addReloadCallback([this]() { m_screenCorners.onConfigReload(); });
 
   m_layerPopupHosts.registerHost(
@@ -2183,6 +2190,23 @@ void Application::reloadPluginLauncherProviders() {
   }
 }
 
+void Application::reloadDmenuProviders() {
+  if (m_launcherPanel == nullptr) {
+    return;
+  }
+  m_launcherPanel->clearProvidersWithIdPrefix("dmenu.");
+  for (const auto& entry : m_configService.config().shell.launcher.dmenu.entries) {
+    if (entry.command.empty()) {
+      logWarn("dmenu[{}]: missing command, skipping", entry.id);
+      continue;
+    }
+    if (entry.prefix.value_or("").empty() && !entry.global) {
+      logWarn("dmenu[{}]: no prefix and global=false; unreachable until configured", entry.id);
+    }
+    m_launcherPanel->addProvider(std::make_unique<DmenuProvider>(entry, &m_clipboardService));
+  }
+}
+
 void Application::reloadPluginPanels() {
   // Retire the previously registered plugin panels (closing any that are open),
   // then register the current enabled set under their canonical full ids.
diff --git a/src/app/application.h b/src/app/application.h
--- a/src/app/application.h
+++ b/src/app/application.h
@@ -148,6 +148,8 @@ class Application {
   void initIpc();
   // (Re)register plugin-backed launcher providers from the enabled plugin set.
   void reloadPluginLauncherProviders();
+  // (Re)register config-driven dmenu launcher providers ([shell.launcher.dmenu.entry.*]).
+  void reloadDmenuProviders();
   // (Re)register plugin-backed panels from the enabled plugin set.
   void reloadPluginPanels();
   void startTrayService();
diff --git a/src/config/config_types.h b/src/config/config_types.h
--- a/src/config/config_types.h
+++ b/src/config/config_types.h
@@ -799,6 +799,29 @@ constexpr EnumOption<WallpaperTransition> kWallpaperTransitions[] = {
     {WallpaperTransition::Zoom, "zoom", "settings.options.wallpaper.transition.zoom"},
 };
 
+// One config-driven dmenu-style launcher entry. The provider runs `command`, splits
+// its stdout into newline-separated candidates, and on activation either runs `exec`
+// (with {selection} substituted) or copies the selection to the clipboard.
+struct DmenuEntryConfig {
+  // Canonical flat identifier; the [shell.launcher.dmenu.entry.<id>] table key. Used as
+  // the provider id suffix (dmenu.<id>) and the usage-tracking key.
+  std::string id;
+  // Shell string run via /bin/sh -lc; stdout lines become candidates. A tab in a line
+  // splits it into title \t description (the raw line is still the selection value).
+  std::string command;
+  // When set, the activated line is substituted into {selection} and run detached.
+  // When unset, the selection is copied to the clipboard.
+  std::optional<std::string> exec;
+  // Launcher prefix routing (e.g. "/ssh"). Empty leaves the entry reachable only via
+  // global = true, otherwise it is unreachable (surfaced as a config warning).
+  std::optional<std::string> prefix;
+  std::optional<std::string> label; // Provider overview title; defaults to the id.
+  std::optional<std::string> glyph; // Tabler glyph name; defaults to "terminal".
+  bool global = false;              // Include results in non-prefixed search.
+
+  bool operator==(const DmenuEntryConfig&) const = default;
+};
+
 struct ShellConfig {
   struct AnimationConfig {
     bool enabled = true;
@@ -836,16 +859,30 @@ struct ShellConfig {
     bool openNearClickClipboard = false;
     bool openNearClickWallpaper = false;
     bool openNearClickSession = false;
-    bool launcherCategories = true;
-    bool launcherShowIcons = true;
-    bool launcherCompact = false;
-    bool launcherAppGrid = false;
-    bool launcherSessionSearch = false;
-    bool launcherSortByUsage = true;
 
     bool operator==(const PanelConfig&) const = default;
   };
 
+  // Launcher behavior/appearance. Panel placement for the launcher surface stays
+  // under [shell.panel] (launcher_placement/position/open_near_click_launcher),
+  // parallel to every other surface.
+  struct LauncherConfig {
+    bool categories = true;
+    bool showIcons = true;
+    bool compact = false;
+    bool appGrid = false;
+    bool sessionSearch = false;
+    bool sortByUsage = true;
+
+    struct DmenuConfig {
+      std::vector<DmenuEntryConfig> entries;
+
+      bool operator==(const DmenuConfig&) const = default;
+    } dmenu;
+
+    bool operator==(const LauncherConfig&) const = default;
+  };
+
   struct ScreenCornersConfig {
     bool enabled = false;
     std::int32_t size = 32;
@@ -913,6 +950,7 @@ struct ShellConfig {
   std::string clipboardImageActionCommand;
   ShadowConfig shadow;
   PanelConfig panel;
+  LauncherConfig launcher;
   ScreenCornersConfig screenCorners;
   MprisConfig mpris;
   ScreenshotConfig screenshot;
diff --git a/src/config/schema/config_schema.cpp b/src/config/schema/config_schema.cpp
--- a/src/config/schema/config_schema.cpp
+++ b/src/config/schema/config_schema.cpp
@@ -1123,6 +1123,46 @@ namespace noctalia::config::schema {
       return s;
     }
 
+    // Optional strings stored trimmed-or-nullopt, always emitted (value_or("")).
+    Field<DmenuEntryConfig>
+    dmenuOptionalString(std::optional<std::string> DmenuEntryConfig::* member, std::string_view key) {
+      return custom<DmenuEntryConfig>(
+          key,
+          [member, key](const toml::table& tbl, DmenuEntryConfig& out, std::string_view, Diagnostics&) {
+            if (auto v = tbl[key].value<std::string>()) {
+              const std::string trimmed = StringUtils::trim(*v);
+              out.*member = trimmed.empty() ? std::optional<std::string>{} : std::optional<std::string>{trimmed};
+            }
+          },
+          [member, key](toml::table& tbl, const DmenuEntryConfig& in) {
+            tbl.insert_or_assign(key, (in.*member).value_or(""));
+          }
+      );
+    }
+
+    const Schema<DmenuEntryConfig>& dmenuEntrySchema() {
+      static const Schema<DmenuEntryConfig> s = {
+          field(&DmenuEntryConfig::command, "command"),
+          dmenuOptionalString(&DmenuEntryConfig::exec, "exec"),
+          dmenuOptionalString(&DmenuEntryConfig::prefix, "prefix"),
+          dmenuOptionalString(&DmenuEntryConfig::label, "label"),
+          dmenuOptionalString(&DmenuEntryConfig::glyph, "glyph"),
+          field(&DmenuEntryConfig::global, "global"),
+      };
+      return s;
+    }
+
+    const Schema<ShellConfig::LauncherConfig::DmenuConfig>& shellLauncherDmenuSchema() {
+      static const Schema<ShellConfig::LauncherConfig::DmenuConfig> s = {
+          namedMap<ShellConfig::LauncherConfig::DmenuConfig, DmenuEntryConfig>(
+              &ShellConfig::LauncherConfig::DmenuConfig::entries, "entry", dmenuEntrySchema(),
+              [](DmenuEntryConfig& e, std::string_view name) { e.id = std::string(name); },
+              [](const DmenuEntryConfig& e) { return e.id; }
+          ),
+      };
+      return s;
+    }
+
     const Schema<ShellConfig::PanelConfig>& shellPanelSchema() {
       static const Schema<ShellConfig::PanelConfig> s = {
           enumField(&ShellConfig::PanelConfig::transparencyMode, "transparency_mode", kPanelTransparencyModes),
@@ -1144,12 +1184,19 @@ namespace noctalia::config::schema {
           field(&ShellConfig::PanelConfig::openNearClickClipboard, "open_near_click_clipboard"),
           field(&ShellConfig::PanelConfig::openNearClickWallpaper, "open_near_click_wallpaper"),
           field(&ShellConfig::PanelConfig::openNearClickSession, "open_near_click_session"),
-          field(&ShellConfig::PanelConfig::launcherCategories, "launcher_categories"),
-          field(&ShellConfig::PanelConfig::launcherShowIcons, "launcher_show_icons"),
-          field(&ShellConfig::PanelConfig::launcherCompact, "launcher_compact"),
-          field(&ShellConfig::PanelConfig::launcherAppGrid, "launcher_app_grid"),
-          field(&ShellConfig::PanelConfig::launcherSessionSearch, "launcher_session_search"),
-          field(&ShellConfig::PanelConfig::launcherSortByUsage, "launcher_sort_by_usage"),
+      };
+      return s;
+    }
+
+    const Schema<ShellConfig::LauncherConfig>& shellLauncherSchema() {
+      static const Schema<ShellConfig::LauncherConfig> s = {
+          field(&ShellConfig::LauncherConfig::categories, "categories"),
+          field(&ShellConfig::LauncherConfig::showIcons, "show_icons"),
+          field(&ShellConfig::LauncherConfig::compact, "compact"),
+          field(&ShellConfig::LauncherConfig::appGrid, "app_grid"),
+          field(&ShellConfig::LauncherConfig::sessionSearch, "session_search"),
+          field(&ShellConfig::LauncherConfig::sortByUsage, "sort_by_usage"),
+          subTable(&ShellConfig::LauncherConfig::dmenu, "dmenu", shellLauncherDmenuSchema()),
       };
       return s;
     }
@@ -1326,6 +1373,7 @@ namespace noctalia::config::schema {
         subTable(&ShellConfig::animation, "animation", shellAnimationSchema()),
         subTable(&ShellConfig::shadow, "shadow", shellShadowSchema()),
         subTable(&ShellConfig::panel, "panel", shellPanelSchema()),
+        subTable(&ShellConfig::launcher, "launcher", shellLauncherSchema()),
         subTable(&ShellConfig::screenCorners, "screen_corners", shellScreenCornersSchema()),
         subTable(&ShellConfig::mpris, "mpris", shellMprisSchema()),
         subTable(&ShellConfig::screenshot, "screenshot", shellScreenshotSchema()),
diff --git a/src/launcher/dmenu_provider.cpp b/src/launcher/dmenu_provider.cpp
new file mode 100644
--- /dev/null
+++ b/src/launcher/dmenu_provider.cpp
@@ -0,0 +1,161 @@
+#include "launcher/dmenu_provider.h"
+
+#include "core/log.h"
+#include "core/process.h"
+#include "util/fuzzy_match.h"
+#include "util/string_utils.h"
+#include "wayland/clipboard_service.h"
+
+#include <algorithm>
+#include <chrono>
+#include <cstddef>
+#include <string>
+#include <string_view>
+
+namespace {
+
+  constexpr std::chrono::milliseconds kCommandTimeout{2000};
+  constexpr std::size_t kMaxOutputBytes = 256 * 1024;
+  constexpr std::size_t kMaxResults = 200;
+
+  // Replace every {selection} occurrence in `tmpl` with `selection`. Plain substitution;
+  // the exec template is user-trusted config (like dmenu/rofi run commands).
+  std::string substituteSelection(std::string tmpl, std::string_view selection) {
+    constexpr std::string_view kToken = "{selection}";
+    for (std::size_t pos = tmpl.find(kToken); pos != std::string::npos;
+         pos = tmpl.find(kToken, pos + selection.size())) {
+      tmpl.replace(pos, kToken.size(), selection);
+    }
+    return tmpl;
+  }
+
+} // namespace
+
+DmenuProvider::Line DmenuProvider::parseLine(std::string&& raw) {
+  Line line;
+  if (const auto tab = raw.find('\t'); tab != std::string::npos) {
+    line.title = raw.substr(0, tab);
+    line.subtitle = raw.substr(tab + 1);
+  } else {
+    line.title = raw;
+  }
+  line.searchable = StringUtils::toLower(line.title + " " + line.subtitle);
+  line.raw = std::move(raw);
+  return line;
+}
+
+DmenuProvider::DmenuProvider(DmenuEntryConfig entry, ClipboardService* clipboard)
+    : m_entry(std::move(entry)), m_clipboard(clipboard) {
+  m_id = "dmenu.";
+  m_id += m_entry.id;
+  m_prefix = m_entry.prefix.value_or("");
+  m_glyph = m_entry.glyph.value_or("terminal");
+}
+
+std::string DmenuProvider::displayName() const { return m_entry.label.value_or(m_entry.id); }
+
+void DmenuProvider::ensureLoaded() const {
+  if (m_loaded) {
+    return;
+  }
+  m_loaded = true; // set before run so a failure doesn't retry every keystroke
+  m_lines.clear();
+
+  if (m_entry.command.empty()) {
+    return;
+  }
+  const auto result =
+      process::runSyncWithTimeoutAndOutputLimit({"/bin/sh", "-lc", m_entry.command}, kCommandTimeout, kMaxOutputBytes);
+  if (!result) {
+    logWarn("dmenu[{}]: command failed (exit {})", m_entry.id, result.exitCode);
+    return;
+  }
+
+  std::size_t begin = 0;
+  for (std::size_t i = 0; i <= result.out.size(); ++i) {
+    if (i < result.out.size() && result.out[i] != '\n') {
+      continue;
+    }
+    std::size_t end = i;
+    if (end > begin && result.out[end - 1] == '\r') {
+      --end;
+    }
+    if (end > begin) {
+      m_lines.push_back(parseLine(result.out.substr(begin, end - begin)));
+    }
+    begin = i + 1;
+  }
+}
+
+void DmenuProvider::reset() {
+  m_lines.clear();
+  m_loaded = false;
+}
+
+std::vector<LauncherResult> DmenuProvider::query(std::string_view text) const {
+  ensureLoaded();
+  if (m_lines.empty()) {
+    return {};
+  }
+
+  auto makeResult = [this](const Line& line, double score) {
+    LauncherResult r;
+    r.id = line.raw;
+    r.title = line.title;
+    r.subtitle = line.subtitle;
+    r.glyphName = m_glyph;
+    r.score = score;
+    return r;
+  };
+
+  const std::string query = StringUtils::toLower(StringUtils::trim(text));
+  if (query.empty()) {
+    const auto limit = std::min(m_lines.size(), kMaxResults);
+    std::vector<LauncherResult> results;
+    results.reserve(limit);
+    for (std::size_t i = 0; i < limit; ++i) {
+      results.push_back(makeResult(m_lines[i], 0.0));
+    }
+    return results;
+  }
+
+  std::vector<std::pair<double, const Line*>> scored;
+  scored.reserve(m_lines.size());
+  for (const auto& line : m_lines) {
+    const double s = FuzzyMatch::score(query, line.searchable);
+    if (FuzzyMatch::isMatch(s)) {
+      scored.emplace_back(s, &line);
+    }
+  }
+
+  const auto limit = std::min(scored.size(), kMaxResults);
+  std::partial_sort(
+      scored.begin(), scored.begin() + static_cast<std::ptrdiff_t>(limit), scored.end(),
+      [](const auto& a, const auto& b) { return a.first > b.first; }
+  );
+
+  std::vector<LauncherResult> results;
+  results.reserve(limit);
+  for (std::size_t i = 0; i < limit; ++i) {
+    results.push_back(makeResult(*scored[i].second, scored[i].first));
+  }
+  return results;
+}
+
+bool DmenuProvider::activate(const LauncherResult& result) {
+  if (!result.providerId.empty() && result.providerId != m_id) {
+    return false;
+  }
+  // Only activate lines this provider actually produced.
+  for (const auto& line : m_lines) {
+    if (line.raw != result.id) {
+      continue;
+    }
+    if (m_entry.exec.has_value() && !m_entry.exec->empty()) {
+      const std::string command = substituteSelection(*m_entry.exec, line.raw);
+      return process::runAsync(command);
+    }
+    return m_clipboard != nullptr && m_clipboard->copyText(line.raw);
+  }
+  return false;
+}
diff --git a/src/launcher/dmenu_provider.h b/src/launcher/dmenu_provider.h
new file mode 100644
--- /dev/null
+++ b/src/launcher/dmenu_provider.h
@@ -0,0 +1,47 @@
+#pragma once
+
+#include "config/config_types.h"
+#include "launcher/launcher_provider.h"
+
+class ClipboardService;
+
+// One config-driven dmenu-style launcher entry. Runs `entry.command` once per open
+// session, splits stdout into newline-separated candidates, and fuzzy-filters them.
+// On activate: runs `entry.exec` (with {selection} substituted) or, when no exec is
+// set, copies the selection to the clipboard.
+class DmenuProvider : public LauncherProvider {
+public:
+  DmenuProvider(DmenuEntryConfig entry, ClipboardService* clipboard);
+
+  [[nodiscard]] std::string_view prefix() const override { return m_prefix; }
+  [[nodiscard]] std::string_view id() const override { return m_id; }
+  [[nodiscard]] std::string displayName() const override;
+  [[nodiscard]] std::string_view defaultGlyphName() const override { return m_glyph; }
+  [[nodiscard]] bool trackUsage() const override { return true; }
+  [[nodiscard]] bool includeInGlobalSearch() const override { return m_entry.global; }
+
+  [[nodiscard]] std::vector<LauncherResult> query(std::string_view text) const override;
+
+  bool activate(const LauncherResult& result) override;
+
+  void reset() override;
+
+private:
+  struct Line {
+    std::string raw;        // exact line; the selection value and result id
+    std::string title;      // text before the first tab
+    std::string subtitle;   // text after the first tab (empty if none)
+    std::string searchable; // lowercased title + " " + subtitle
+  };
+
+  void ensureLoaded() const;
+  static Line parseLine(std::string&& raw);
+
+  DmenuEntryConfig m_entry;
+  std::string m_id;     // "dmenu." + entry.id
+  std::string m_prefix; // entry.prefix value or empty
+  std::string m_glyph;  // entry.glyph or "terminal"
+  ClipboardService* m_clipboard = nullptr;
+  mutable std::vector<Line> m_lines;
+  mutable bool m_loaded = false;
+};
diff --git a/src/launcher/session_provider.cpp b/src/launcher/session_provider.cpp
--- a/src/launcher/session_provider.cpp
+++ b/src/launcher/session_provider.cpp
@@ -132,7 +132,7 @@ SessionProvider::SessionProvider(ConfigService* config, SessionActionRunner* act
 std::string SessionProvider::displayName() const { return i18n::tr("launcher.providers.session.title"); }
 
 bool SessionProvider::includeInGlobalSearch() const {
-  return m_config != nullptr && m_config->config().shell.panel.launcherSessionSearch;
+  return m_config != nullptr && m_config->config().shell.launcher.sessionSearch;
 }
 
 std::vector<LauncherResult> SessionProvider::query(std::string_view text) const {
diff --git a/src/shell/launcher/launcher_panel.cpp b/src/shell/launcher/launcher_panel.cpp
--- a/src/shell/launcher/launcher_panel.cpp
+++ b/src/shell/launcher/launcher_panel.cpp
@@ -153,9 +153,9 @@ namespace {
   [[nodiscard]] LauncherListStyle launcherListStyleFrom(const ConfigService* config, float scale) {
     LauncherListStyle style{.scale = scale, .appIconColorizeTint = std::nullopt};
     if (config != nullptr) {
-      const auto& panel = config->config().shell.panel;
-      style.showIcons = panel.launcherShowIcons;
-      style.compact = panel.launcherCompact;
+      const auto& launcher = config->config().shell.launcher;
+      style.showIcons = launcher.showIcons;
+      style.compact = launcher.compact;
       style.appIconColorizeTint = effectiveShellAppIconColorizationTint(config->config().shell);
     }
     return style;
@@ -676,6 +676,12 @@ void LauncherPanel::clearDynamicProviders() {
   std::erase_if(m_providers, [](const std::unique_ptr<LauncherProvider>& provider) { return provider->isDynamic(); });
 }
 
+void LauncherPanel::clearProvidersWithIdPrefix(std::string_view prefix) {
+  std::erase_if(m_providers, [&](const std::unique_ptr<LauncherProvider>& provider) {
+    return provider->id().starts_with(prefix);
+  });
+}
+
 void LauncherPanel::create() {
   m_launcherRowHeight = 0.0f;
   const float scale = contentScale();
@@ -787,7 +793,7 @@ void LauncherPanel::refreshLauncherAppIconColorization() {
 }
 
 bool LauncherPanel::shouldUseAppGrid() const {
-  if (m_config == nullptr || !m_config->config().shell.panel.launcherAppGrid || !m_launcherShowIcons) {
+  if (m_config == nullptr || !m_config->config().shell.launcher.appGrid || !m_launcherShowIcons) {
     return false;
   }
   if (m_results.empty()) {
@@ -847,9 +853,9 @@ void LauncherPanel::syncLauncherViewLayout(Renderer* renderer) {
 }
 
 void LauncherPanel::syncLauncherListStyle() {
-  const bool showIcons = m_config == nullptr || m_config->config().shell.panel.launcherShowIcons;
-  const bool compact = m_config != nullptr && m_config->config().shell.panel.launcherCompact;
-  const bool appGrid = m_config != nullptr && m_config->config().shell.panel.launcherAppGrid;
+  const bool showIcons = m_config == nullptr || m_config->config().shell.launcher.showIcons;
+  const bool compact = m_config != nullptr && m_config->config().shell.launcher.compact;
+  const bool appGrid = m_config != nullptr && m_config->config().shell.launcher.appGrid;
   if (showIcons == m_launcherShowIcons
       && compact == m_launcherCompact
       && appGrid == m_launcherAppGrid
@@ -919,7 +925,7 @@ void LauncherPanel::onOpen(std::string_view context) {
   // inotify cannot observe). Cheap stat-only check; only rescans on real change.
   refreshDesktopEntriesIfSourcesChanged();
 
-  m_categoryFilterVisible = m_config != nullptr && m_config->config().shell.panel.launcherCategories;
+  m_categoryFilterVisible = m_config != nullptr && m_config->config().shell.launcher.categories;
   m_activeCategoryType = All;
   m_activeCategory.clear();
   m_currentCategories.clear();
@@ -1068,7 +1074,7 @@ void LauncherPanel::onInputChanged(const std::string& text) {
   }
 
   const bool typedQuery = !queryText.empty();
-  const bool sortByUsage = m_config != nullptr && m_config->config().shell.panel.launcherSortByUsage;
+  const bool sortByUsage = m_config != nullptr && m_config->config().shell.launcher.sortByUsage;
 
   auto applyUsageBoost = [&](std::vector<LauncherResult>& results, const LauncherProvider& provider) {
     if (!sortByUsage) {
diff --git a/src/shell/launcher/launcher_panel.h b/src/shell/launcher/launcher_panel.h
--- a/src/shell/launcher/launcher_panel.h
+++ b/src/shell/launcher/launcher_panel.h
@@ -36,6 +36,8 @@ class LauncherPanel : public Panel {
   // Drop every dynamically-registered (plugin-backed) provider, so the enabled
   // plugin set can be re-applied without disturbing the built-in providers.
   void clearDynamicProviders();
+  // Drop providers whose stable id starts with `prefix` (e.g. config-driven "dmenu.").
+  void clearProvidersWithIdPrefix(std::string_view prefix);
 
   void create() override;
   void onOpen(std::string_view context) override;
diff --git a/src/shell/settings/settings_registry.cpp b/src/shell/settings/settings_registry.cpp
--- a/src/shell/settings/settings_registry.cpp
+++ b/src/shell/settings/settings_registry.cpp
@@ -1049,33 +1049,33 @@ namespace settings {
     }
     entries.push_back(makeEntry(
         SettingsSection::Panels, "launcher", tr("settings.schema.panels.launcher-categories.label"),
-        tr("settings.schema.panels.launcher-categories.description"), {"shell", "panel", "launcher_categories"},
-        ToggleSetting{cfg.shell.panel.launcherCategories}, "launcher categories filter"
+        tr("settings.schema.panels.launcher-categories.description"), {"shell", "launcher", "categories"},
+        ToggleSetting{cfg.shell.launcher.categories}, "launcher categories filter"
     ));
     entries.push_back(makeEntry(
         SettingsSection::Panels, "launcher", tr("settings.schema.panels.launcher-show-icons.label"),
-        tr("settings.schema.panels.launcher-show-icons.description"), {"shell", "panel", "launcher_show_icons"},
-        ToggleSetting{cfg.shell.panel.launcherShowIcons}, "launcher app icons hide"
+        tr("settings.schema.panels.launcher-show-icons.description"), {"shell", "launcher", "show_icons"},
+        ToggleSetting{cfg.shell.launcher.showIcons}, "launcher app icons hide"
     ));
     entries.push_back(makeEntry(
         SettingsSection::Panels, "launcher", tr("settings.schema.panels.launcher-app-grid.label"),
-        tr("settings.schema.panels.launcher-app-grid.description"), {"shell", "panel", "launcher_app_grid"},
-        ToggleSetting{cfg.shell.panel.launcherAppGrid}, "launcher app grid icons view"
+        tr("settings.schema.panels.launcher-app-grid.description"), {"shell", "launcher", "app_grid"},
+        ToggleSetting{cfg.shell.launcher.appGrid}, "launcher app grid icons view"
     ));
     entries.push_back(makeEntry(
         SettingsSection::Panels, "launcher", tr("settings.schema.panels.launcher-compact.label"),
-        tr("settings.schema.panels.launcher-compact.description"), {"shell", "panel", "launcher_compact"},
-        ToggleSetting{cfg.shell.panel.launcherCompact}, "launcher compact rows dense"
+        tr("settings.schema.panels.launcher-compact.description"), {"shell", "launcher", "compact"},
+        ToggleSetting{cfg.shell.launcher.compact}, "launcher compact rows dense"
     ));
     entries.push_back(makeEntry(
         SettingsSection::Panels, "launcher", tr("settings.schema.panels.launcher-sort-by-usage.label"),
-        tr("settings.schema.panels.launcher-sort-by-usage.description"), {"shell", "panel", "launcher_sort_by_usage"},
-        ToggleSetting{cfg.shell.panel.launcherSortByUsage}, "launcher sort usage recently used frequency"
+        tr("settings.schema.panels.launcher-sort-by-usage.description"), {"shell", "launcher", "sort_by_usage"},
+        ToggleSetting{cfg.shell.launcher.sortByUsage}, "launcher sort usage recently used frequency"
     ));
     entries.push_back(makeEntry(
         SettingsSection::Panels, "launcher", tr("settings.schema.panels.launcher-session-search.label"),
-        tr("settings.schema.panels.launcher-session-search.description"), {"shell", "panel", "launcher_session_search"},
-        ToggleSetting{cfg.shell.panel.launcherSessionSearch},
+        tr("settings.schema.panels.launcher-session-search.description"), {"shell", "launcher", "session_search"},
+        ToggleSetting{cfg.shell.launcher.sessionSearch},
         "launcher session search power menu lock suspend reboot shutdown logout"
     ));
     entries.push_back(makeEntry(
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
