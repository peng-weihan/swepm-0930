#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/docs/reference/integrations.md b/docs/reference/integrations.md
--- a/docs/reference/integrations.md
+++ b/docs/reference/integrations.md
@@ -43,6 +43,8 @@ specify integration list
 ```
 
 Shows all available integrations, which one is currently installed, and whether each requires a CLI tool or is IDE-based.
+When multiple integrations are installed, the list marks the default integration separately from the other installed integrations.
+The list also shows whether each built-in integration is declared multi-install safe.
 
 ## Install an Integration
 
@@ -53,9 +55,12 @@ specify integration install <key>
 | Option                   | Description                                                              |
 | ------------------------ | ------------------------------------------------------------------------ |
 | `--script sh\|ps`        | Script type: `sh` (bash/zsh) or `ps` (PowerShell)                        |
+| `--force`                | Opt in to installing alongside integrations that are not declared multi-install safe |
 | `--integration-options`  | Integration-specific options (e.g. `--integration-options="--commands-dir .myagent/cmds"`) |
 
-Installs the specified integration into the current project. Fails if another integration is already installed — use `switch` instead. If the installation fails partway through, it automatically rolls back to a clean state.
+Installs the specified integration into the current project. If another integration is already installed, the command only proceeds automatically when all involved integrations are declared multi-install safe. Otherwise, use `switch` to replace the default integration or pass `--force` to explicitly opt in to multi-install. If the installation fails partway through, it automatically rolls back to a clean state.
+
+Installing an additional integration does not change the default integration. Use `specify integration use <key>` to change the default.
 
 > **Note:** All integration management commands require a project already initialized with `specify init`. To start a new project with a specific agent, use `specify init <project> --integration <key>` instead.
 
@@ -84,10 +89,22 @@ specify integration switch <key>
 | Option                   | Description                                                              |
 | ------------------------ | ------------------------------------------------------------------------ |
 | `--script sh\|ps`        | Script type: `sh` (bash/zsh) or `ps` (PowerShell)                        |
-| `--force`                | Force removal of modified files during uninstall                         |
-| `--integration-options`  | Options for the target integration                                       |
+| `--force`                | Force removal of modified files during uninstall; when the target is already installed, overwrite managed shared templates while changing the default |
+| `--integration-options`  | Options for the target integration when it is not already installed      |
+
+If the target integration is not already installed, equivalent to running `uninstall` followed by `install` in a single step. In this mode, `--force` controls whether modified files from the removed integration are deleted. If the target integration is already installed, `switch` only changes the default integration, like `use`; in this mode, `--force` controls whether managed shared templates are overwritten while the default changes. `--integration-options` is rejected for already-installed targets because changing integration options requires reinstalling managed files; run `upgrade <key> --integration-options ...` first, then `use <key>`.
+
+## Use an Installed Integration
+
+```bash
+specify integration use <key>
+```
 
-Equivalent to running `uninstall` followed by `install` in a single step.
+| Option    | Description                                         |
+| --------- | --------------------------------------------------- |
+| `--force` | Overwrite managed shared templates while changing the default |
+
+Sets the default integration without uninstalling any other installed integrations. This also refreshes managed shared templates so command references match the new default integration's invocation style. Modified or untracked shared templates are preserved unless `--force` is used.
 
 ## Upgrade an Integration
 
@@ -101,7 +118,7 @@ specify integration upgrade [<key>]
 | `--script sh\|ps`        | Script type: `sh` (bash/zsh) or `ps` (PowerShell)                        |
 | `--integration-options`  | Options for the integration                                              |
 
-Reinstalls the current integration with updated templates and commands (e.g., after upgrading Spec Kit). Defaults to the currently installed integration; if a key is provided, it must match the installed one — otherwise the command fails and suggests using `switch` instead. Detects locally modified files and blocks the upgrade unless `--force` is used. Stale files from the previous install that are no longer needed are removed automatically.
+Reinstalls an installed integration with updated templates and commands (e.g., after upgrading Spec Kit). Defaults to the default integration; if a key is provided, it must be one of the installed integrations. Detects locally modified files and blocks the upgrade unless `--force` is used. Stale files from the previous install that are no longer needed are removed automatically. Shared templates stay aligned with the default integration even when upgrading a non-default integration.
 
 ## Integration-Specific Options
 
@@ -120,9 +137,39 @@ specify integration install generic --integration-options="--commands-dir .myage
 
 ## FAQ
 
-### Can I use multiple integrations at the same time?
+### Can I install multiple integrations in the same project?
+
+Yes, but it is intended for team portability rather than the default workflow. Multiple integrations are allowed automatically only when the installed integration and the new integration are declared multi-install safe by Spec Kit. For other combinations, pass `--force` to acknowledge that multiple agents may see unrelated agent-specific instructions or commands.
+
+Spec Kit tracks one default integration in `.specify/integration.json` with `default_integration`, all installed integrations with `installed_integrations`, per-integration runtime settings with `integration_settings`, and a dedicated `integration_state_schema` for future state migrations. The legacy `integration` field remains as an alias for the default integration.
+
+### Which integrations are multi-install safe?
+
+An integration is multi-install safe when it uses isolated agent directories, a dedicated context file that does not collide with another safe integration, stable command invocation settings, and a separate install manifest. Shared Spec Kit templates remain aligned to the single default integration.
+
+The currently declared multi-install safe integrations are:
+
+| Key | Isolation |
+| --- | --------- |
+| `auggie` | `.augment/commands`, `.augment/rules/specify-rules.md` |
+| `claude` | `.claude/skills`, `CLAUDE.md` |
+| `codebuddy` | `.codebuddy/commands`, `CODEBUDDY.md` |
+| `codex` | `.agents/skills`, `AGENTS.md` |
+| `cursor-agent` | `.cursor/skills`, `.cursor/rules/specify-rules.mdc` |
+| `gemini` | `.gemini/commands`, `GEMINI.md` |
+| `iflow` | `.iflow/commands`, `IFLOW.md` |
+| `junie` | `.junie/commands`, `.junie/AGENTS.md` |
+| `kilocode` | `.kilocode/workflows`, `.kilocode/rules/specify-rules.md` |
+| `kimi` | `.kimi/skills`, `KIMI.md` |
+| `qodercli` | `.qoder/commands`, `QODER.md` |
+| `qwen` | `.qwen/commands`, `QWEN.md` |
+| `roo` | `.roo/commands`, `.roo/rules/specify-rules.md` |
+| `shai` | `.shai/commands`, `SHAI.md` |
+| `tabnine` | `.tabnine/agent/commands`, `TABNINE.md` |
+| `trae` | `.trae/skills`, `.trae/rules/project_rules.md` |
+| `windsurf` | `.windsurf/workflows`, `.windsurf/rules/specify-rules.md` |
 
-No. Only one AI coding agent integration can be installed per project. Use `specify integration switch <key>` to change to a different AI coding agent.
+Integrations that share a context file or command directory with another integration, require dynamic install paths such as `--commands-dir`, or merge shared tool settings are not declared safe by default. They can still be installed alongside another integration with `--force`.
 
 ### What happens to my changes when I uninstall or switch?
 
@@ -138,4 +185,4 @@ CLI-based integrations (like Claude Code, Gemini CLI) require the tool to be ins
 
 ### When should I use `upgrade` vs `switch`?
 
-Use `upgrade` when you've upgraded Spec Kit and want to refresh the same integration's templates. Use `switch` when you want to change to a different AI coding agent.
+Use `upgrade` when you've upgraded Spec Kit and want to refresh an installed integration's managed files. Use `switch` when you want to replace the current default with another integration; if the target is already installed, `switch` behaves like `use`.
diff --git a/src/specify_cli/__init__.py b/src/specify_cli/__init__.py
--- a/src/specify_cli/__init__.py
+++ b/src/specify_cli/__init__.py
@@ -54,6 +54,27 @@
 from rich.tree import Tree
 from typer.core import TyperGroup
 
+from .integration_runtime import (
+    invoke_separator_for_integration as _invoke_separator_for_integration,
+    resolve_integration_options as _resolve_integration_options_impl,
+    with_integration_setting as _with_integration_setting,
+)
+from .integration_state import (
+    INTEGRATION_JSON,
+    INTEGRATION_STATE_SCHEMA,
+    dedupe_integration_keys as _dedupe_integration_keys,
+    default_integration_key as _default_integration_key,
+    installed_integration_keys as _installed_integration_keys,
+    integration_setting as _integration_setting,
+    integration_settings as _integration_settings,
+    normalize_integration_state as _normalize_integration_state,
+    write_integration_json as _write_integration_json_file,
+)
+from .shared_infra import (
+    install_shared_infra as _install_shared_infra_impl,
+    refresh_shared_templates as _refresh_shared_templates_impl,
+)
+
 # For cross-platform keyboard input
 import readchar
 
@@ -643,6 +664,11 @@ def _locate_core_pack() -> Path | None:
     return None
 
 
+def _repo_root() -> Path:
+    """Return the source checkout root used for editable installs."""
+    return Path(__file__).parent.parent.parent
+
+
 def _locate_bundled_extension(extension_id: str) -> Path | None:
     """Return the path to a bundled extension, or None.
 
@@ -660,8 +686,7 @@ def _locate_bundled_extension(extension_id: str) -> Path | None:
             return candidate
 
     # Source-checkout / editable install: look relative to repo root
-    repo_root = Path(__file__).parent.parent.parent
-    candidate = repo_root / "extensions" / extension_id
+    candidate = _repo_root() / "extensions" / extension_id
     if (candidate / "extension.yml").is_file():
         return candidate
 
@@ -685,8 +710,7 @@ def _locate_bundled_workflow(workflow_id: str) -> Path | None:
             return candidate
 
     # Source-checkout / editable install: look relative to repo root
-    repo_root = Path(__file__).parent.parent.parent
-    candidate = repo_root / "workflows" / workflow_id
+    candidate = _repo_root() / "workflows" / workflow_id
     if (candidate / "workflow.yml").is_file():
         return candidate
 
@@ -710,14 +734,31 @@ def _locate_bundled_preset(preset_id: str) -> Path | None:
             return candidate
 
     # Source-checkout / editable install: look relative to repo root
-    repo_root = Path(__file__).parent.parent.parent
-    candidate = repo_root / "presets" / preset_id
+    candidate = _repo_root() / "presets" / preset_id
     if (candidate / "preset.yml").is_file():
         return candidate
 
     return None
 
 
+def _refresh_shared_templates(
+    project_path: Path,
+    *,
+    invoke_separator: str,
+    force: bool = False,
+) -> None:
+    """Refresh default-sensitive shared templates without touching scripts."""
+    _refresh_shared_templates_impl(
+        project_path,
+        version=get_speckit_version(),
+        core_pack=_locate_core_pack(),
+        repo_root=_repo_root(),
+        console=console,
+        invoke_separator=invoke_separator,
+        force=force,
+    )
+
+
 def _install_shared_infra(
     project_path: Path,
     script_type: str,
@@ -741,79 +782,36 @@ def _install_shared_infra(
 
     Returns ``True`` on success.
     """
-    from .integrations.base import IntegrationBase
-    from .integrations.manifest import IntegrationManifest
-
-    core = _locate_core_pack()
-    manifest = IntegrationManifest("speckit", project_path, version=get_speckit_version())
+    return _install_shared_infra_impl(
+        project_path,
+        script_type,
+        version=get_speckit_version(),
+        core_pack=_locate_core_pack(),
+        repo_root=_repo_root(),
+        console=console,
+        force=force,
+        invoke_separator=invoke_separator,
+    )
 
-    # Scripts
-    if core and (core / "scripts").is_dir():
-        scripts_src = core / "scripts"
-    else:
-        repo_root = Path(__file__).parent.parent.parent
-        scripts_src = repo_root / "scripts"
-
-    skipped_files: list[str] = []
-
-    if scripts_src.is_dir():
-        dest_scripts = project_path / ".specify" / "scripts"
-        dest_scripts.mkdir(parents=True, exist_ok=True)
-        variant_dir = "bash" if script_type == "sh" else "powershell"
-        variant_src = scripts_src / variant_dir
-        if variant_src.is_dir():
-            dest_variant = dest_scripts / variant_dir
-            dest_variant.mkdir(parents=True, exist_ok=True)
-            for src_path in variant_src.rglob("*"):
-                if src_path.is_file():
-                    rel_path = src_path.relative_to(variant_src)
-                    dst_path = dest_variant / rel_path
-                    if dst_path.exists() and not force:
-                        skipped_files.append(str(dst_path.relative_to(project_path)))
-                    else:
-                        dst_path.parent.mkdir(parents=True, exist_ok=True)
-                        shutil.copy2(src_path, dst_path)
-                        rel = dst_path.relative_to(project_path).as_posix()
-                        manifest.record_existing(rel)
-
-    # Page templates (not command templates, not vscode-settings.json)
-    if core and (core / "templates").is_dir():
-        templates_src = core / "templates"
-    else:
-        repo_root = Path(__file__).parent.parent.parent
-        templates_src = repo_root / "templates"
-
-    if templates_src.is_dir():
-        dest_templates = project_path / ".specify" / "templates"
-        dest_templates.mkdir(parents=True, exist_ok=True)
-        for f in templates_src.iterdir():
-            if f.is_file() and f.name != "vscode-settings.json" and not f.name.startswith("."):
-                dst = dest_templates / f.name
-                if dst.exists() and not force:
-                    skipped_files.append(str(dst.relative_to(project_path)))
-                else:
-                    content = f.read_text(encoding="utf-8")
-                    content = IntegrationBase.resolve_command_refs(
-                        content, invoke_separator
-                    )
-                    dst.write_text(content, encoding="utf-8")
-                    rel = dst.relative_to(project_path).as_posix()
-                    manifest.record_existing(rel)
 
-    if skipped_files:
-        console.print(
-            f"[yellow]⚠[/yellow]  {len(skipped_files)} shared infrastructure file(s) already exist and were not updated:"
-        )
-        for f in skipped_files:
-            console.print(f"    {f}")
-        console.print(
-            "To refresh shared infrastructure, run "
-            "[cyan]specify init --here --force[/cyan] or "
-            "[cyan]specify integration upgrade --force[/cyan]."
+def _install_shared_infra_or_exit(
+    project_path: Path,
+    script_type: str,
+    tracker: StepTracker | None = None,
+    force: bool = False,
+    invoke_separator: str = ".",
+) -> bool:
+    try:
+        return _install_shared_infra(
+            project_path,
+            script_type,
+            tracker=tracker,
+            force=force,
+            invoke_separator=invoke_separator,
         )
-
-    manifest.save()
-    return True
+    except (ValueError, OSError) as exc:
+        console.print(f"[red]Error:[/red] Failed to install shared infrastructure: {exc}")
+        raise typer.Exit(1)
 
 
 def ensure_executable_scripts(project_path: Path, tracker: StepTracker | None = None) -> None:
@@ -855,7 +853,7 @@ def ensure_executable_scripts(project_path: Path, tracker: StepTracker | None =
                 os.chmod(script, new_mode)
                 updated += 1
             except Exception as e:
-                failures.append(f"{script.relative_to(project_path)}: {e}")
+                failures.append(f"{_display_project_path(project_path, script)}: {e}")
     if tracker:
         detail = f"{updated} updated" + (f", {len(failures)} failed" if failures else "")
         tracker.add("chmod", "Set script permissions recursively")
@@ -1299,19 +1297,32 @@ def init(
             )
             manifest.save()
 
-            # Write .specify/integration.json
-            integration_json = project_path / ".specify" / "integration.json"
-            integration_json.parent.mkdir(parents=True, exist_ok=True)
-            integration_json.write_text(json.dumps({
-                "integration": resolved_integration.key,
-                "version": get_speckit_version(),
-            }, indent=2) + "\n", encoding="utf-8")
+            integration_settings = _with_integration_setting(
+                {},
+                resolved_integration.key,
+                resolved_integration,
+                script_type=selected_script,
+                raw_options=integration_options,
+                parsed_options=integration_parsed_options or None,
+            )
+            _write_integration_json(
+                project_path,
+                resolved_integration.key,
+                [resolved_integration.key],
+                integration_settings,
+            )
 
             tracker.complete("integration", resolved_integration.config.get("name", resolved_integration.key))
 
             # Install shared infrastructure (scripts, templates)
             tracker.start("shared-infra")
-            _install_shared_infra(project_path, selected_script, tracker=tracker, force=force, invoke_separator=resolved_integration.effective_invoke_separator(integration_parsed_options))
+            _install_shared_infra_or_exit(
+                project_path,
+                selected_script,
+                tracker=tracker,
+                force=force,
+                invoke_separator=resolved_integration.effective_invoke_separator(integration_parsed_options),
+            )
             tracker.complete("shared-infra", f"scripts ({selected_script}) + templates")
 
             ensure_constitution_from_template(project_path, tracker=tracker)
@@ -1869,7 +1880,7 @@ def get_speckit_version() -> str:
         # Fallback: try reading from pyproject.toml
         try:
             import tomllib
-            pyproject_path = Path(__file__).parent.parent.parent / "pyproject.toml"
+            pyproject_path = _repo_root() / "pyproject.toml"
             if pyproject_path.exists():
                 with open(pyproject_path, "rb") as f:
                     data = tomllib.load(f)
@@ -1898,11 +1909,8 @@ def get_speckit_version() -> str:
 integration_app.add_typer(integration_catalog_app, name="catalog")
 
 
-INTEGRATION_JSON = ".specify/integration.json"
-
-
 def _read_integration_json(project_root: Path) -> dict[str, Any]:
-    """Load ``.specify/integration.json``.  Returns ``{}`` when missing."""
+    """Load ``.specify/integration.json``. Returns normalized state when present."""
     path = project_root / INTEGRATION_JSON
     if not path.exists():
         return {}
@@ -1922,20 +1930,42 @@ def _read_integration_json(project_root: Path) -> dict[str, Any]:
         console.print(f"[red]Error:[/red] {path} must contain a JSON object, got {type(data).__name__}.")
         console.print(f"Please fix or delete {INTEGRATION_JSON} and retry.")
         raise typer.Exit(1)
-    return data
+    schema = data.get("integration_state_schema")
+    if isinstance(schema, int) and not isinstance(schema, bool) and schema > INTEGRATION_STATE_SCHEMA:
+        console.print(
+            f"[red]Error:[/red] {path} uses integration state schema {schema}, "
+            f"but this CLI only supports schema {INTEGRATION_STATE_SCHEMA}."
+        )
+        console.print("Please upgrade Spec Kit before modifying integrations.")
+        raise typer.Exit(1)
+    return _normalize_integration_state(data)
 
 
 def _write_integration_json(
     project_root: Path,
-    integration_key: str,
+    integration_key: str | None,
+    installed_integrations: list[str] | None = None,
+    integration_settings: dict[str, dict[str, Any]] | None = None,
 ) -> None:
-    """Write ``.specify/integration.json`` for *integration_key*."""
-    dest = project_root / INTEGRATION_JSON
-    dest.parent.mkdir(parents=True, exist_ok=True)
-    dest.write_text(json.dumps({
-        "integration": integration_key,
-        "version": get_speckit_version(),
-    }, indent=2) + "\n", encoding="utf-8")
+    """Write ``.specify/integration.json`` with legacy-compatible state."""
+    _write_integration_json_file(
+        project_root,
+        version=get_speckit_version(),
+        integration_key=integration_key,
+        installed_integrations=installed_integrations,
+        settings=integration_settings,
+    )
+
+
+def _clear_init_options_for_integration(project_root: Path, integration_key: str) -> None:
+    """Clear active integration keys from init-options.json when they match."""
+    opts = load_init_options(project_root)
+    if opts.get("integration") == integration_key or opts.get("ai") == integration_key:
+        opts.pop("integration", None)
+        opts.pop("ai", None)
+        opts.pop("ai_skills", None)
+        opts.pop("context_file", None)
+        save_init_options(project_root, opts)
 
 
 def _remove_integration_json(project_root: Path) -> None:
@@ -1945,6 +1975,13 @@ def _remove_integration_json(project_root: Path) -> None:
         path.unlink()
 
 
+_MANIFEST_READ_ERRORS = (ValueError, FileNotFoundError, OSError, UnicodeDecodeError)
+
+
+class _SharedTemplateRefreshError(RuntimeError):
+    """Raised when default integration metadata should not be persisted."""
+
+
 def _normalize_script_type(script_type: str, source: str) -> str:
     """Normalize and validate a script type from CLI/config sources."""
     normalized = script_type.strip().lower()
@@ -1968,6 +2005,102 @@ def _resolve_script_type(project_root: Path, script_type: str | None) -> str:
     return "ps" if os.name == "nt" else "sh"
 
 
+def _resolve_integration_script_type(
+    project_root: Path,
+    state: dict[str, Any],
+    key: str,
+    script_type: str | None = None,
+) -> str:
+    """Resolve script type for an integration, preferring stored settings."""
+    if script_type:
+        return _normalize_script_type(script_type, "--script")
+
+    stored = _integration_setting(state, key).get("script")
+    if isinstance(stored, str) and stored.strip():
+        return _normalize_script_type(stored, f"{INTEGRATION_JSON} integration_settings.{key}.script")
+
+    return _resolve_script_type(project_root, None)
+
+
+def _resolve_integration_options(
+    integration: Any,
+    state: dict[str, Any],
+    key: str,
+    raw_options: str | None,
+) -> tuple[str | None, dict[str, Any] | None]:
+    """Resolve raw and parsed options for an integration operation."""
+    return _resolve_integration_options_impl(
+        integration,
+        state,
+        key,
+        raw_options,
+        parse_options=_parse_integration_options,
+    )
+
+
+def _set_default_integration(
+    project_root: Path,
+    state: dict[str, Any],
+    key: str,
+    integration: Any,
+    installed_keys: list[str],
+    *,
+    script_type: str | None = None,
+    raw_options: str | None = None,
+    parsed_options: dict[str, Any] | None = None,
+    refresh_templates: bool = True,
+    refresh_templates_force: bool = False,
+) -> None:
+    """Persist *key* as default and align active runtime metadata."""
+    resolved_script = _resolve_integration_script_type(project_root, state, key, script_type)
+    settings = _with_integration_setting(
+        state,
+        key,
+        integration,
+        script_type=resolved_script,
+        raw_options=raw_options,
+        parsed_options=parsed_options,
+    )
+
+    if refresh_templates:
+        try:
+            _refresh_shared_templates(
+                project_root,
+                invoke_separator=_invoke_separator_for_integration(
+                    integration, {"integration_settings": settings}, key, parsed_options
+                ),
+                force=refresh_templates_force,
+            )
+        except (ValueError, OSError) as exc:
+            raise _SharedTemplateRefreshError(
+                f"Failed to refresh shared templates for '{key}': {exc}"
+            ) from exc
+
+    _write_integration_json(project_root, key, installed_keys, settings)
+    _update_init_options_for_integration(project_root, integration, script_type=resolved_script)
+
+
+def _set_default_integration_or_exit(*args: Any, **kwargs: Any) -> None:
+    try:
+        _set_default_integration(*args, **kwargs)
+    except _SharedTemplateRefreshError as exc:
+        console.print(f"[red]Error:[/red] {exc}")
+        raise typer.Exit(1)
+
+
+def _display_project_path(project_root: Path, path: str | Path) -> str:
+    """Return a stable POSIX-style display path for paths under a project."""
+    path_obj = Path(path)
+    try:
+        rel_path = path_obj.relative_to(project_root) if path_obj.is_absolute() else path_obj
+    except ValueError:
+        try:
+            rel_path = path_obj.resolve().relative_to(project_root.resolve())
+        except (OSError, ValueError):
+            return path_obj.as_posix()
+    return rel_path.as_posix()
+
+
 def _require_specify_project() -> Path:
     """Return the current project root if it is a spec-kit project, else exit."""
     project_root = Path.cwd()
@@ -1987,7 +2120,8 @@ def integration_list(
 
     project_root = _require_specify_project()
     current = _read_integration_json(project_root)
-    installed_key = current.get("integration")
+    default_key = _default_integration_key(current)
+    installed_keys = set(_installed_integration_keys(current))
 
     if catalog:
         from .integrations.catalog import IntegrationCatalog, IntegrationCatalogError
@@ -2009,25 +2143,32 @@ def integration_list(
         table.add_column("Version")
         table.add_column("Source")
         table.add_column("Status")
+        table.add_column("Multi-install Safe")
 
         for entry in sorted(entries, key=lambda e: e["id"]):
             eid = entry["id"]
             cat_name = entry.get("_catalog_name", "")
             install_allowed = entry.get("_install_allowed", True)
-            if eid == installed_key:
+            if eid == default_key:
+                status = "[green]installed (default)[/green]"
+            elif eid in installed_keys:
                 status = "[green]installed[/green]"
             elif eid in INTEGRATION_REGISTRY:
                 status = "built-in"
             elif install_allowed is False:
                 status = "discovery-only"
             else:
                 status = ""
+            safe = ""
+            if eid in INTEGRATION_REGISTRY:
+                safe = "yes" if getattr(INTEGRATION_REGISTRY[eid], "multi_install_safe", False) else "no"
             table.add_row(
                 eid,
                 entry.get("name", eid),
                 entry.get("version", ""),
                 cat_name,
                 status,
+                safe,
             )
 
         console.print(table)
@@ -2038,25 +2179,30 @@ def integration_list(
     table.add_column("Name")
     table.add_column("Status")
     table.add_column("CLI Required")
+    table.add_column("Multi-install Safe")
 
     for key in sorted(INTEGRATION_REGISTRY.keys()):
         integration = INTEGRATION_REGISTRY[key]
         cfg = integration.config or {}
         name = cfg.get("name", key)
         requires_cli = cfg.get("requires_cli", False)
 
-        if key == installed_key:
+        if key == default_key:
+            status = "[green]installed (default)[/green]"
+        elif key in installed_keys:
             status = "[green]installed[/green]"
         else:
             status = ""
 
         cli_req = "yes" if requires_cli else "no (IDE)"
-        table.add_row(key, name, status, cli_req)
+        safe = "yes" if getattr(integration, "multi_install_safe", False) else "no"
+        table.add_row(key, name, status, cli_req, safe)
 
     console.print(table)
 
-    if installed_key:
-        console.print(f"\n[dim]Current integration:[/dim] [cyan]{installed_key}[/cyan]")
+    if installed_keys:
+        console.print(f"\n[dim]Default integration:[/dim] [cyan]{default_key or 'none'}[/cyan]")
+        console.print(f"[dim]Installed integrations:[/dim] [cyan]{', '.join(sorted(installed_keys))}[/cyan]")
     else:
         console.print("\n[yellow]No integration currently installed.[/yellow]")
         console.print("Install one with: [cyan]specify integration install <key>[/cyan]")
@@ -2066,6 +2212,7 @@ def integration_list(
 def integration_install(
     key: str = typer.Argument(help="Integration key to install (e.g. claude, copilot)"),
     script: str | None = typer.Option(None, "--script", help="Script type: sh or ps (default: from init-options.json or platform default)"),
+    force: bool = typer.Option(False, "--force", help="Allow multi-install when integrations are not declared safe"),
     integration_options: str | None = typer.Option(None, "--integration-options", help='Options for the integration (e.g. --integration-options="--commands-dir .myagent/cmds")'),
 ):
     """Install an integration into an existing project."""
@@ -2081,30 +2228,68 @@ def integration_install(
         raise typer.Exit(1)
 
     current = _read_integration_json(project_root)
-    installed_key = current.get("integration")
+    default_key = _default_integration_key(current)
+    installed_keys = _installed_integration_keys(current)
 
-    if installed_key and installed_key == key:
+    if key in installed_keys:
         console.print(f"[yellow]Integration '{key}' is already installed.[/yellow]")
-        console.print("Run [cyan]specify integration uninstall[/cyan] first, then reinstall.")
+        console.print(
+            f"Run [cyan]specify integration upgrade {key}[/cyan] to reinstall managed files, "
+            f"or [cyan]specify integration uninstall {key}[/cyan] first."
+        )
         raise typer.Exit(0)
 
-    if installed_key:
-        console.print(f"[red]Error:[/red] Integration '{installed_key}' is already installed.")
-        console.print(f"Run [cyan]specify integration uninstall[/cyan] first, or use [cyan]specify integration switch {key}[/cyan].")
-        raise typer.Exit(1)
+    if installed_keys and not force:
+        unsafe_keys = []
+        for installed_key in installed_keys:
+            installed_integration = get_integration(installed_key)
+            if not installed_integration or not getattr(installed_integration, "multi_install_safe", False):
+                unsafe_keys.append(installed_key)
+        if unsafe_keys or not getattr(integration, "multi_install_safe", False):
+            console.print(
+                f"[red]Error:[/red] Installed integrations: {', '.join(installed_keys)}."
+            )
+            if default_key:
+                console.print(f"Default integration: [cyan]{default_key}[/cyan].")
+            console.print(
+                "Installing multiple integrations is only automatic when all involved "
+                "integrations are declared multi-install safe."
+            )
+            console.print(
+                f"Run [cyan]specify integration switch {key}[/cyan] to replace the default "
+                f"integration, or retry with [cyan]--force[/cyan] to opt in."
+            )
+            raise typer.Exit(1)
 
     selected_script = _resolve_script_type(project_root, script)
 
     # Build parsed options from --integration-options so the integration
     # can determine its effective invoke separator before shared infra
     # is installed.
-    parsed_options: dict[str, Any] | None = None
-    if integration_options:
-        parsed_options = _parse_integration_options(integration, integration_options)
+    raw_options, parsed_options = _resolve_integration_options(
+        integration, current, key, integration_options
+    )
 
     # Ensure shared infrastructure is present (safe to run unconditionally;
     # _install_shared_infra merges missing files without overwriting).
-    _install_shared_infra(project_root, selected_script, invoke_separator=integration.effective_invoke_separator(parsed_options))
+    infra_integration = integration
+    infra_key = key
+    infra_parsed = parsed_options
+    if default_key:
+        default_integration = get_integration(default_key)
+        if default_integration is not None:
+            infra_integration = default_integration
+            infra_key = default_key
+            _, infra_parsed = _resolve_integration_options(
+                default_integration, current, default_key, None
+            )
+    _install_shared_infra_or_exit(
+        project_root,
+        selected_script,
+        invoke_separator=_invoke_separator_for_integration(
+            infra_integration, current, infra_key, infra_parsed
+        ),
+    )
     if os.name != "nt":
         ensure_executable_scripts(project_root)
 
@@ -2117,11 +2302,22 @@ def integration_install(
             project_root, manifest,
             parsed_options=parsed_options,
             script_type=selected_script,
-            raw_options=integration_options,
+            raw_options=raw_options,
         )
         manifest.save()
-        _write_integration_json(project_root, integration.key)
-        _update_init_options_for_integration(project_root, integration, script_type=selected_script)
+        new_installed = _dedupe_integration_keys([*installed_keys, integration.key])
+        new_default = default_key or integration.key
+        settings = _with_integration_setting(
+            current,
+            integration.key,
+            integration,
+            script_type=selected_script,
+            raw_options=raw_options,
+            parsed_options=parsed_options,
+        )
+        _write_integration_json(project_root, new_default, new_installed, settings)
+        if new_default == integration.key:
+            _update_init_options_for_integration(project_root, integration, script_type=selected_script)
 
     except Exception as e:
         # Attempt rollback of any files written by setup
@@ -2130,12 +2326,19 @@ def integration_install(
         except Exception as rollback_err:
             # Suppress so the original setup error remains the primary failure
             console.print(f"[yellow]Warning:[/yellow] Failed to roll back integration changes: {rollback_err}")
-        _remove_integration_json(project_root)
+        if installed_keys:
+            _write_integration_json(
+                project_root, default_key, installed_keys, _integration_settings(current)
+            )
+        else:
+            _remove_integration_json(project_root)
         console.print(f"[red]Error:[/red] Failed to install integration: {e}")
         raise typer.Exit(1)
 
     name = (integration.config or {}).get("name", key)
     console.print(f"\n[green]✓[/green] Integration '{name}' installed successfully")
+    if default_key:
+        console.print(f"[dim]Default integration remains:[/dim] [cyan]{default_key}[/cyan]")
 
 
 def _parse_integration_options(integration: Any, raw_options: str) -> dict[str, Any] | None:
@@ -2207,6 +2410,44 @@ def _update_init_options_for_integration(
     save_init_options(project_root, opts)
 
 
+@integration_app.command("use")
+def integration_use(
+    key: str = typer.Argument(help="Installed integration key to make the default"),
+    force: bool = typer.Option(False, "--force", help="Overwrite managed shared templates while changing the default"),
+):
+    """Set the default integration without uninstalling other integrations."""
+    from .integrations import get_integration
+
+    project_root = _require_specify_project()
+    current = _read_integration_json(project_root)
+    installed_keys = _installed_integration_keys(current)
+    if key not in installed_keys:
+        console.print(f"[red]Error:[/red] Integration '{key}' is not installed.")
+        if installed_keys:
+            console.print(f"[yellow]Installed integrations:[/yellow] {', '.join(installed_keys)}")
+        else:
+            console.print("Install one with: [cyan]specify integration install <key>[/cyan]")
+        raise typer.Exit(1)
+
+    integration = get_integration(key)
+    if integration is None:
+        console.print(f"[red]Error:[/red] Unknown integration '{key}'")
+        raise typer.Exit(1)
+
+    raw_options, parsed_options = _resolve_integration_options(integration, current, key, None)
+    _set_default_integration_or_exit(
+        project_root,
+        current,
+        key,
+        integration,
+        installed_keys,
+        raw_options=raw_options,
+        parsed_options=parsed_options,
+        refresh_templates_force=force,
+    )
+    console.print(f"[green]✓[/green] Default integration set to [bold]{key}[/bold].")
+
+
 @integration_app.command("uninstall")
 def integration_uninstall(
     key: str = typer.Argument(None, help="Integration key to uninstall (default: current integration)"),
@@ -2218,37 +2459,53 @@ def integration_uninstall(
 
     project_root = _require_specify_project()
     current = _read_integration_json(project_root)
-    installed_key = current.get("integration")
+    default_key = _default_integration_key(current)
+    installed_keys = _installed_integration_keys(current)
 
     if key is None:
-        if not installed_key:
+        if not default_key:
             console.print("[yellow]No integration is currently installed.[/yellow]")
             raise typer.Exit(0)
-        key = installed_key
+        key = default_key
 
-    if installed_key and installed_key != key:
-        console.print(f"[red]Error:[/red] Integration '{key}' is not the currently installed integration ('{installed_key}').")
+    if key not in installed_keys:
+        console.print(f"[red]Error:[/red] Integration '{key}' is not installed.")
         raise typer.Exit(1)
 
     integration = get_integration(key)
 
     manifest_path = project_root / ".specify" / "integrations" / f"{key}.manifest.json"
     if not manifest_path.exists():
         console.print(f"[yellow]No manifest found for integration '{key}'. Nothing to uninstall.[/yellow]")
-        _remove_integration_json(project_root)
-        # Clear integration-related keys from init-options.json
-        opts = load_init_options(project_root)
-        if opts.get("integration") == key or opts.get("ai") == key:
-            opts.pop("integration", None)
-            opts.pop("ai", None)
-            opts.pop("ai_skills", None)
-            opts.pop("context_file", None)
-            save_init_options(project_root, opts)
+        remaining = [installed for installed in installed_keys if installed != key]
+        new_default = default_key if default_key != key else (remaining[0] if remaining else None)
+        if remaining:
+            if default_key == key and new_default and (new_integration := get_integration(new_default)):
+                raw_options, parsed_options = _resolve_integration_options(
+                    new_integration, current, new_default, None
+                )
+                _set_default_integration_or_exit(
+                    project_root,
+                    current,
+                    new_default,
+                    new_integration,
+                    remaining,
+                    raw_options=raw_options,
+                    parsed_options=parsed_options,
+                )
+            else:
+                _write_integration_json(
+                    project_root, new_default, remaining, _integration_settings(current)
+                )
+        else:
+            _remove_integration_json(project_root)
+        if default_key == key:
+            _clear_init_options_for_integration(project_root, key)
         raise typer.Exit(0)
 
     try:
         manifest = IntegrationManifest.load(key, project_root)
-    except (ValueError, FileNotFoundError) as exc:
+    except _MANIFEST_READ_ERRORS as exc:
         console.print(f"[red]Error:[/red] Integration manifest for '{key}' is unreadable.")
         console.print(f"Manifest: {manifest_path}")
         console.print(
@@ -2265,16 +2522,31 @@ def integration_uninstall(
     if integration:
         integration.remove_context_section(project_root)
 
-    _remove_integration_json(project_root)
+    remaining = [installed for installed in installed_keys if installed != key]
+    new_default = default_key if default_key != key else (remaining[0] if remaining else None)
+    if remaining:
+        if default_key == key and new_default and (new_integration := get_integration(new_default)):
+            raw_options, parsed_options = _resolve_integration_options(
+                new_integration, current, new_default, None
+            )
+            _set_default_integration_or_exit(
+                project_root,
+                current,
+                new_default,
+                new_integration,
+                remaining,
+                raw_options=raw_options,
+                parsed_options=parsed_options,
+            )
+        else:
+            _write_integration_json(
+                project_root, new_default, remaining, _integration_settings(current)
+            )
+    else:
+        _remove_integration_json(project_root)
 
-    # Update init-options.json to clear the integration
-    opts = load_init_options(project_root)
-    if opts.get("integration") == key or opts.get("ai") == key:
-        opts.pop("integration", None)
-        opts.pop("ai", None)
-        opts.pop("ai_skills", None)
-        opts.pop("context_file", None)
-        save_init_options(project_root, opts)
+    if default_key == key:
+        _clear_init_options_for_integration(project_root, key)
 
     name = (integration.config or {}).get("name", key) if integration else key
     console.print(f"\n[green]✓[/green] Integration '{name}' uninstalled")
@@ -2283,7 +2555,7 @@ def integration_uninstall(
     if skipped:
         console.print(f"\n[yellow]⚠[/yellow]  {len(skipped)} modified file(s) were preserved:")
         for path in skipped:
-            rel = path.relative_to(project_root) if path.is_absolute() else path
+            rel = _display_project_path(project_root, path)
             console.print(f"    {rel}")
 
 
@@ -2307,10 +2579,67 @@ def integration_switch(
         raise typer.Exit(1)
 
     current = _read_integration_json(project_root)
-    installed_key = current.get("integration")
+    installed_keys = _installed_integration_keys(current)
+    installed_key = _default_integration_key(current)
 
     if installed_key == target:
-        console.print(f"[yellow]Integration '{target}' is already installed. Nothing to switch.[/yellow]")
+        if integration_options is not None:
+            console.print(
+                "[red]Error:[/red] --integration-options cannot be used when switching "
+                "to an already installed integration."
+            )
+            console.print(
+                f"Run [cyan]specify integration upgrade {target} --integration-options ...[/cyan] "
+                "to update managed files/options."
+            )
+            raise typer.Exit(1)
+        if force:
+            raw_options, parsed_options = _resolve_integration_options(
+                target_integration, current, target, None
+            )
+            _set_default_integration_or_exit(
+                project_root,
+                current,
+                target,
+                target_integration,
+                installed_keys,
+                raw_options=raw_options,
+                parsed_options=parsed_options,
+                refresh_templates_force=True,
+            )
+            console.print(
+                f"\n[green]✓[/green] Default integration remains [bold]{target}[/bold]; "
+                "managed shared templates refreshed."
+            )
+            raise typer.Exit(0)
+        console.print(f"[yellow]Integration '{target}' is already the default integration. Nothing to switch.[/yellow]")
+        raise typer.Exit(0)
+
+    if target in installed_keys:
+        if integration_options is not None:
+            console.print(
+                "[red]Error:[/red] --integration-options cannot be used when switching "
+                "to an already installed integration."
+            )
+            console.print(
+                f"Run [cyan]specify integration upgrade {target} --integration-options ...[/cyan] "
+                f"to update managed files/options, then [cyan]specify integration use {target}[/cyan]."
+            )
+            raise typer.Exit(1)
+        raw_options, parsed_options = _resolve_integration_options(
+            target_integration, current, target, None
+        )
+        _set_default_integration_or_exit(
+            project_root,
+            current,
+            target,
+            target_integration,
+            installed_keys,
+            raw_options=raw_options,
+            parsed_options=parsed_options,
+            refresh_templates_force=force,
+        )
+        console.print(f"\n[green]✓[/green] Default integration set to [bold]{target}[/bold].")
         raise typer.Exit(0)
 
     selected_script = _resolve_script_type(project_root, script)
@@ -2324,7 +2653,7 @@ def integration_switch(
             console.print(f"Uninstalling current integration: [cyan]{installed_key}[/cyan]")
             try:
                 old_manifest = IntegrationManifest.load(installed_key, project_root)
-            except (ValueError, FileNotFoundError) as exc:
+            except _MANIFEST_READ_ERRORS as exc:
                 console.print(f"[red]Error:[/red] Could not read integration manifest for '{installed_key}': {manifest_path}")
                 console.print(f"[dim]{exc}[/dim]")
                 console.print(
@@ -2348,7 +2677,7 @@ def integration_switch(
                     console.print(f"  Removed {len(removed)} file(s)")
                 if skipped:
                     console.print(f"  [yellow]⚠[/yellow]  {len(skipped)} modified file(s) preserved")
-            except (ValueError, FileNotFoundError) as exc:
+            except _MANIFEST_READ_ERRORS as exc:
                 console.print(f"[yellow]Warning:[/yellow] Could not read manifest for '{installed_key}': {exc}")
         else:
             console.print(f"[red]Error:[/red] Integration '{installed_key}' is installed but has no manifest.")
@@ -2372,24 +2701,48 @@ def integration_switch(
             )
 
         # Clear metadata so a failed Phase 2 doesn't leave stale references
-        _remove_integration_json(project_root)
-        opts = load_init_options(project_root)
-        opts.pop("integration", None)
-        opts.pop("ai", None)
-        opts.pop("ai_skills", None)
-        opts.pop("context_file", None)
-        save_init_options(project_root, opts)
+        installed_keys = [installed for installed in installed_keys if installed != installed_key]
+        _clear_init_options_for_integration(project_root, installed_key)
+        if installed_keys:
+            fallback_key = installed_keys[0]
+            fallback_integration = get_integration(fallback_key)
+            if fallback_integration is not None:
+                raw_options, parsed_options = _resolve_integration_options(
+                    fallback_integration, current, fallback_key, None
+                )
+                _set_default_integration_or_exit(
+                    project_root,
+                    current,
+                    fallback_key,
+                    fallback_integration,
+                    installed_keys,
+                    raw_options=raw_options,
+                    parsed_options=parsed_options,
+                )
+            else:
+                _write_integration_json(
+                    project_root, fallback_key, installed_keys, _integration_settings(current)
+                )
+        else:
+            _remove_integration_json(project_root)
+        current = _read_integration_json(project_root)
 
     # Build parsed options from --integration-options so the integration
     # can determine its effective invoke separator before shared infra
     # is installed.
-    parsed_options: dict[str, Any] | None = None
-    if integration_options:
-        parsed_options = _parse_integration_options(target_integration, integration_options)
+    raw_options, parsed_options = _resolve_integration_options(
+        target_integration, current, target, integration_options
+    )
 
     # Ensure shared infrastructure is present (safe to run unconditionally;
     # _install_shared_infra merges missing files without overwriting).
-    _install_shared_infra(project_root, selected_script, invoke_separator=target_integration.effective_invoke_separator(parsed_options))
+    _install_shared_infra_or_exit(
+        project_root,
+        selected_script,
+        invoke_separator=_invoke_separator_for_integration(
+            target_integration, current, target, parsed_options
+        ),
+    )
     if os.name != "nt":
         ensure_executable_scripts(project_root)
 
@@ -2404,11 +2757,19 @@ def integration_switch(
             project_root, manifest,
             parsed_options=parsed_options,
             script_type=selected_script,
-            raw_options=integration_options,
+            raw_options=raw_options,
         )
         manifest.save()
-        _write_integration_json(project_root, target_integration.key)
-        _update_init_options_for_integration(project_root, target_integration, script_type=selected_script)
+        _set_default_integration(
+            project_root,
+            current,
+            target_integration.key,
+            target_integration,
+            _dedupe_integration_keys([*installed_keys, target_integration.key]),
+            script_type=selected_script,
+            raw_options=raw_options,
+            parsed_options=parsed_options,
+        )
 
         # Re-register extension commands for the new agent so that
         # previously-installed extensions are available in the new integration.
@@ -2430,7 +2791,34 @@ def integration_switch(
         except Exception as rollback_err:
             # Suppress so the original setup error remains the primary failure
             console.print(f"[yellow]Warning:[/yellow] Failed to roll back integration '{target}': {rollback_err}")
-        _remove_integration_json(project_root)
+        if installed_keys:
+            fallback_key = installed_keys[0]
+            fallback_integration = get_integration(fallback_key)
+            if fallback_integration is not None:
+                raw_options, parsed_options = _resolve_integration_options(
+                    fallback_integration, current, fallback_key, None
+                )
+                try:
+                    _set_default_integration(
+                        project_root,
+                        current,
+                        fallback_key,
+                        fallback_integration,
+                        installed_keys,
+                        raw_options=raw_options,
+                        parsed_options=parsed_options,
+                    )
+                except _SharedTemplateRefreshError as restore_err:
+                    console.print(
+                        f"[yellow]Warning:[/yellow] Failed to restore default "
+                        f"integration '{fallback_key}': {restore_err}"
+                    )
+            else:
+                _write_integration_json(
+                    project_root, fallback_key, installed_keys, _integration_settings(current)
+                )
+        else:
+            _remove_integration_json(project_root)
         console.print(f"[red]Error:[/red] Failed to install integration '{target}': {e}")
         raise typer.Exit(1)
 
@@ -2455,19 +2843,17 @@ def integration_upgrade(
 
     project_root = _require_specify_project()
     current = _read_integration_json(project_root)
-    installed_key = current.get("integration")
+    installed_key = _default_integration_key(current)
+    installed_keys = _installed_integration_keys(current)
 
     if key is None:
         if not installed_key:
             console.print("[yellow]No integration is currently installed.[/yellow]")
             raise typer.Exit(0)
         key = installed_key
 
-    if installed_key and installed_key != key:
-        console.print(
-            f"[red]Error:[/red] Integration '{key}' is not the currently installed integration ('{installed_key}')."
-        )
-        console.print(f"Use [cyan]specify integration switch {key}[/cyan] instead.")
+    if key not in installed_keys:
+        console.print(f"[red]Error:[/red] Integration '{key}' is not installed.")
         raise typer.Exit(1)
 
     integration = get_integration(key)
@@ -2483,7 +2869,7 @@ def integration_upgrade(
 
     try:
         old_manifest = IntegrationManifest.load(key, project_root)
-    except (ValueError, FileNotFoundError) as exc:
+    except _MANIFEST_READ_ERRORS as exc:
         console.print(f"[red]Error:[/red] Integration manifest for '{key}' is unreadable: {exc}")
         raise typer.Exit(1)
 
@@ -2496,17 +2882,35 @@ def integration_upgrade(
         console.print("\nUse [cyan]--force[/cyan] to overwrite modified files, or resolve manually.")
         raise typer.Exit(1)
 
-    selected_script = _resolve_script_type(project_root, script)
+    selected_script = _resolve_integration_script_type(project_root, current, key, script)
 
     # Build parsed options from --integration-options so the integration
     # can determine its effective invoke separator before shared infra
     # is installed.
-    parsed_options: dict[str, Any] | None = None
-    if integration_options:
-        parsed_options = _parse_integration_options(integration, integration_options)
+    raw_options, parsed_options = _resolve_integration_options(
+        integration, current, key, integration_options
+    )
 
     # Ensure shared infrastructure is up to date; --force overwrites existing files.
-    _install_shared_infra(project_root, selected_script, force=force, invoke_separator=integration.effective_invoke_separator(parsed_options))
+    infra_integration = integration
+    infra_key = key
+    infra_parsed = parsed_options
+    if installed_key and installed_key != key:
+        default_integration = get_integration(installed_key)
+        if default_integration is not None:
+            infra_integration = default_integration
+            infra_key = installed_key
+            _, infra_parsed = _resolve_integration_options(
+                default_integration, current, installed_key, None
+            )
+    _install_shared_infra_or_exit(
+        project_root,
+        selected_script,
+        force=force,
+        invoke_separator=_invoke_separator_for_integration(
+            infra_integration, current, infra_key, infra_parsed
+        ),
+    )
     if os.name != "nt":
         ensure_executable_scripts(project_root)
 
@@ -2520,11 +2924,33 @@ def integration_upgrade(
             new_manifest,
             parsed_options=parsed_options,
             script_type=selected_script,
-            raw_options=integration_options,
+            raw_options=raw_options,
+        )
+        settings = _with_integration_setting(
+            current,
+            key,
+            integration,
+            script_type=selected_script,
+            raw_options=raw_options,
+            parsed_options=parsed_options,
         )
+        if installed_key == key:
+            try:
+                _refresh_shared_templates(
+                    project_root,
+                    invoke_separator=_invoke_separator_for_integration(
+                        integration, {"integration_settings": settings}, key, parsed_options
+                    ),
+                    force=force,
+                )
+            except (ValueError, OSError) as exc:
+                raise _SharedTemplateRefreshError(
+                    f"Failed to refresh shared templates for '{key}': {exc}"
+                ) from exc
         new_manifest.save()
-        _write_integration_json(project_root, key)
-        _update_init_options_for_integration(project_root, integration, script_type=selected_script)
+        _write_integration_json(project_root, installed_key, installed_keys, settings)
+        if installed_key == key:
+            _update_init_options_for_integration(project_root, integration, script_type=selected_script)
     except Exception as exc:
         # Don't teardown — setup overwrites in-place, so teardown would
         # delete files that were working before the upgrade.  Just report.
@@ -2853,14 +3279,7 @@ def preset_list():
     """List installed presets."""
     from .presets import PresetManager
 
-    project_root = Path.cwd()
-
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     manager = PresetManager(project_root)
     installed = manager.list_installed()
 
@@ -2899,14 +3318,7 @@ def preset_add(
         PresetCompatibilityError,
     )
 
-    project_root = Path.cwd()
-
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     # Validate priority
     if priority < 1:
         console.print("[red]Error:[/red] Priority must be a positive integer (1 or higher)")
@@ -3020,14 +3432,7 @@ def preset_remove(
     """Remove an installed preset."""
     from .presets import PresetManager
 
-    project_root = Path.cwd()
-
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     manager = PresetManager(project_root)
 
     if not manager.registry.is_installed(preset_id):
@@ -3050,14 +3455,7 @@ def preset_search(
     """Search for presets in the catalog."""
     from .presets import PresetCatalog, PresetError
 
-    project_root = Path.cwd()
-
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     catalog = PresetCatalog(project_root)
 
     try:
@@ -3087,14 +3485,7 @@ def preset_resolve(
     """Show which template will be resolved for a given name."""
     from .presets import PresetResolver
 
-    project_root = Path.cwd()
-
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     resolver = PresetResolver(project_root)
     layers = resolver.collect_all_layers(template_name)
 
@@ -3158,14 +3549,7 @@ def preset_info(
     from .extensions import normalize_priority
     from .presets import PresetCatalog, PresetManager, PresetError
 
-    project_root = Path.cwd()
-
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     # Check if installed locally first
     manager = PresetManager(project_root)
     local_pack = manager.get_pack(preset_id)
@@ -3232,15 +3616,7 @@ def preset_set_priority(
     """Set the resolution priority of an installed preset."""
     from .presets import PresetManager
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     # Validate priority
     if priority < 1:
         console.print("[red]Error:[/red] Priority must be a positive integer (1 or higher)")
@@ -3283,15 +3659,7 @@ def preset_enable(
     """Enable a disabled preset."""
     from .presets import PresetManager
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     manager = PresetManager(project_root)
 
     # Check if preset is installed
@@ -3324,15 +3692,7 @@ def preset_disable(
     """Disable a preset without removing it."""
     from .presets import PresetManager
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     manager = PresetManager(project_root)
 
     # Check if preset is installed
@@ -3367,14 +3727,7 @@ def preset_catalog_list():
     """List all active preset catalogs."""
     from .presets import PresetCatalog, PresetValidationError
 
-    project_root = Path.cwd()
-
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     catalog = PresetCatalog(project_root)
 
     try:
@@ -3407,7 +3760,7 @@ def preset_catalog_list():
         except PresetValidationError:
             proj_loaded = False
         if proj_loaded:
-            console.print(f"[dim]Config: {config_path.relative_to(project_root)}[/dim]")
+            console.print(f"[dim]Config: {_display_project_path(project_root, config_path)}[/dim]")
         else:
             try:
                 user_loaded = user_config_path.exists() and catalog._load_catalog_config(user_config_path) is not None
@@ -3436,13 +3789,8 @@ def preset_catalog_add(
     """Add a catalog to .specify/preset-catalogs.yml."""
     from .presets import PresetCatalog, PresetValidationError
 
-    project_root = Path.cwd()
-
+    project_root = _require_specify_project()
     specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
 
     # Validate URL
     tmp_catalog = PresetCatalog(project_root)
@@ -3459,7 +3807,8 @@ def preset_catalog_add(
         try:
             config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
         except Exception as e:
-            console.print(f"[red]Error:[/red] Failed to read {config_path}: {e}")
+            config_label = _display_project_path(project_root, config_path)
+            console.print(f"[red]Error:[/red] Failed to read {config_label}: {e}")
             raise typer.Exit(1)
     else:
         config = {}
@@ -3491,21 +3840,16 @@ def preset_catalog_add(
     console.print(f"\n[green]✓[/green] Added catalog '[bold]{name}[/bold]' ({install_label})")
     console.print(f"  URL: {url}")
     console.print(f"  Priority: {priority}")
-    console.print(f"\nConfig saved to {config_path.relative_to(project_root)}")
+    console.print(f"\nConfig saved to {_display_project_path(project_root, config_path)}")
 
 
 @preset_catalog_app.command("remove")
 def preset_catalog_remove(
     name: str = typer.Argument(help="Catalog name to remove"),
 ):
     """Remove a catalog from .specify/preset-catalogs.yml."""
-    project_root = Path.cwd()
-
+    project_root = _require_specify_project()
     specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
 
     config_path = specify_dir / "preset-catalogs.yml"
     if not config_path.exists():
@@ -3668,15 +4012,7 @@ def extension_list(
     """List installed extensions."""
     from .extensions import ExtensionManager
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     manager = ExtensionManager(project_root)
     installed = manager.list_installed()
 
@@ -3709,14 +4045,7 @@ def catalog_list():
     """List all active extension catalogs."""
     from .extensions import ExtensionCatalog, ValidationError
 
-    project_root = Path.cwd()
-
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     catalog = ExtensionCatalog(project_root)
 
     try:
@@ -3749,7 +4078,7 @@ def catalog_list():
         except ValidationError:
             proj_loaded = False
         if proj_loaded:
-            console.print(f"[dim]Config: {config_path.relative_to(project_root)}[/dim]")
+            console.print(f"[dim]Config: {_display_project_path(project_root, config_path)}[/dim]")
         else:
             try:
                 user_loaded = user_config_path.exists() and catalog._load_catalog_config(user_config_path) is not None
@@ -3778,13 +4107,8 @@ def catalog_add(
     """Add a catalog to .specify/extension-catalogs.yml."""
     from .extensions import ExtensionCatalog, ValidationError
 
-    project_root = Path.cwd()
-
+    project_root = _require_specify_project()
     specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
 
     # Validate URL
     tmp_catalog = ExtensionCatalog(project_root)
@@ -3801,7 +4125,8 @@ def catalog_add(
         try:
             config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
         except Exception as e:
-            console.print(f"[red]Error:[/red] Failed to read {config_path}: {e}")
+            config_label = _display_project_path(project_root, config_path)
+            console.print(f"[red]Error:[/red] Failed to read {config_label}: {e}")
             raise typer.Exit(1)
     else:
         config = {}
@@ -3833,21 +4158,16 @@ def catalog_add(
     console.print(f"\n[green]✓[/green] Added catalog '[bold]{name}[/bold]' ({install_label})")
     console.print(f"  URL: {url}")
     console.print(f"  Priority: {priority}")
-    console.print(f"\nConfig saved to {config_path.relative_to(project_root)}")
+    console.print(f"\nConfig saved to {_display_project_path(project_root, config_path)}")
 
 
 @catalog_app.command("remove")
 def catalog_remove(
     name: str = typer.Argument(help="Catalog name to remove"),
 ):
     """Remove a catalog from .specify/extension-catalogs.yml."""
-    project_root = Path.cwd()
-
+    project_root = _require_specify_project()
     specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
 
     config_path = specify_dir / "extension-catalogs.yml"
     if not config_path.exists():
@@ -3889,15 +4209,7 @@ def extension_add(
     """Install an extension."""
     from .extensions import ExtensionManager, ExtensionCatalog, ExtensionError, ValidationError, CompatibilityError, REINSTALL_COMMAND
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     # Validate priority
     if priority < 1:
         console.print("[red]Error:[/red] Priority must be a positive integer (1 or higher)")
@@ -4071,15 +4383,7 @@ def extension_remove(
     """Uninstall an extension."""
     from .extensions import ExtensionManager
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     manager = ExtensionManager(project_root)
 
     # Resolve extension ID from argument (handles ambiguous names)
@@ -4147,15 +4451,7 @@ def extension_search(
     """Search for available extensions in catalog."""
     from .extensions import ExtensionCatalog, ExtensionError
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     catalog = ExtensionCatalog(project_root)
 
     try:
@@ -4231,15 +4527,7 @@ def extension_info(
     """Show detailed information about an extension."""
     from .extensions import ExtensionCatalog, ExtensionManager, normalize_priority
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     catalog = ExtensionCatalog(project_root)
     manager = ExtensionManager(project_root)
     installed = manager.list_installed()
@@ -4433,15 +4721,7 @@ def extension_update(
     from packaging import version as pkg_version
     import shutil
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     manager = ExtensionManager(project_root)
     catalog = ExtensionCatalog(project_root)
     speckit_version = get_speckit_version()
@@ -4829,15 +5109,7 @@ def extension_enable(
     """Enable a disabled extension."""
     from .extensions import ExtensionManager, HookExecutor
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     manager = ExtensionManager(project_root)
     hook_executor = HookExecutor(project_root)
 
@@ -4876,15 +5148,7 @@ def extension_disable(
     """Disable an extension without removing it."""
     from .extensions import ExtensionManager, HookExecutor
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     manager = ExtensionManager(project_root)
     hook_executor = HookExecutor(project_root)
 
@@ -4926,15 +5190,7 @@ def extension_set_priority(
     """Set the resolution priority of an installed extension."""
     from .extensions import ExtensionManager
 
-    project_root = Path.cwd()
-
-    # Check if we're in a spec-kit project
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        console.print("Run this command from a spec-kit project root")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     # Validate priority
     if priority < 1:
         console.print("[red]Error:[/red] Priority must be a positive integer (1 or higher)")
@@ -4996,10 +5252,7 @@ def workflow_run(
     """Run a workflow from an installed ID or local YAML path."""
     from .workflows.engine import WorkflowEngine
 
-    project_root = Path.cwd()
-    if not (project_root / ".specify").exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
+    project_root = _require_specify_project()
     engine = WorkflowEngine(project_root)
     engine.on_step_start = lambda sid, label: console.print(f"  \u25b8 [{sid}] {label} \u2026")
 
@@ -5063,10 +5316,7 @@ def workflow_resume(
     """Resume a paused or failed workflow run."""
     from .workflows.engine import WorkflowEngine
 
-    project_root = Path.cwd()
-    if not (project_root / ".specify").exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
+    project_root = _require_specify_project()
     engine = WorkflowEngine(project_root)
     engine.on_step_start = lambda sid, label: console.print(f"  \u25b8 [{sid}] {label} \u2026")
 
@@ -5099,10 +5349,7 @@ def workflow_status(
     """Show workflow run status."""
     from .workflows.engine import WorkflowEngine
 
-    project_root = Path.cwd()
-    if not (project_root / ".specify").exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
+    project_root = _require_specify_project()
     engine = WorkflowEngine(project_root)
 
     if run_id:
@@ -5161,12 +5408,7 @@ def workflow_list():
     """List installed workflows."""
     from .workflows.catalog import WorkflowRegistry
 
-    project_root = Path.cwd()
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     registry = WorkflowRegistry(project_root)
     installed = registry.list()
 
@@ -5193,12 +5435,7 @@ def workflow_add(
     from .workflows.catalog import WorkflowCatalog, WorkflowRegistry, WorkflowCatalogError
     from .workflows.engine import WorkflowDefinition
 
-    project_root = Path.cwd()
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     registry = WorkflowRegistry(project_root)
     workflows_dir = project_root / ".specify" / "workflows"
 
@@ -5429,12 +5666,7 @@ def workflow_remove(
     """Uninstall a workflow."""
     from .workflows.catalog import WorkflowRegistry
 
-    project_root = Path.cwd()
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     registry = WorkflowRegistry(project_root)
 
     if not registry.is_installed(workflow_id):
@@ -5459,10 +5691,7 @@ def workflow_search(
     """Search workflow catalogs."""
     from .workflows.catalog import WorkflowCatalog, WorkflowCatalogError
 
-    project_root = Path.cwd()
-    if not (project_root / ".specify").exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
+    project_root = _require_specify_project()
     catalog = WorkflowCatalog(project_root)
 
     try:
@@ -5495,10 +5724,7 @@ def workflow_info(
     from .workflows.catalog import WorkflowCatalog, WorkflowRegistry, WorkflowCatalogError
     from .workflows.engine import WorkflowEngine
 
-    project_root = Path.cwd()
-    if not (project_root / ".specify").exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
+    project_root = _require_specify_project()
 
     # Check installed first
     registry = WorkflowRegistry(project_root)
@@ -5592,12 +5818,7 @@ def workflow_catalog_add(
     """Add a workflow catalog source."""
     from .workflows.catalog import WorkflowCatalog, WorkflowValidationError
 
-    project_root = Path.cwd()
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     catalog = WorkflowCatalog(project_root)
     try:
         catalog.add_catalog(url, name)
@@ -5615,12 +5836,7 @@ def workflow_catalog_remove(
     """Remove a workflow catalog source by index."""
     from .workflows.catalog import WorkflowCatalog, WorkflowValidationError
 
-    project_root = Path.cwd()
-    specify_dir = project_root / ".specify"
-    if not specify_dir.exists():
-        console.print("[red]Error:[/red] Not a spec-kit project (no .specify/ directory)")
-        raise typer.Exit(1)
-
+    project_root = _require_specify_project()
     catalog = WorkflowCatalog(project_root)
     try:
         removed_name = catalog.remove_catalog(index)
diff --git a/src/specify_cli/integration_runtime.py b/src/specify_cli/integration_runtime.py
new file mode 100644
--- /dev/null
+++ b/src/specify_cli/integration_runtime.py
@@ -0,0 +1,90 @@
+"""Runtime helpers for integration commands."""
+
+from __future__ import annotations
+
+from collections.abc import Callable
+from typing import Any
+
+from .integration_state import integration_setting, integration_settings
+
+
+ParseOptions = Callable[[Any, str], dict[str, Any] | None]
+
+
+def resolve_integration_options(
+    integration: Any,
+    state: dict[str, Any],
+    key: str,
+    raw_options: str | None,
+    *,
+    parse_options: ParseOptions,
+) -> tuple[str | None, dict[str, Any] | None]:
+    """Resolve raw and parsed options for an integration operation."""
+    if raw_options is not None:
+        return raw_options, parse_options(integration, raw_options)
+
+    setting = integration_setting(state, key)
+    stored_raw = setting.get("raw_options")
+    if not isinstance(stored_raw, str):
+        stored_raw = None
+
+    stored_parsed = setting.get("parsed_options")
+    if isinstance(stored_parsed, dict):
+        return stored_raw, stored_parsed or None
+
+    if stored_raw:
+        return stored_raw, parse_options(integration, stored_raw)
+
+    return None, None
+
+
+def with_integration_setting(
+    state: dict[str, Any],
+    key: str,
+    integration: Any,
+    *,
+    script_type: str | None = None,
+    raw_options: str | None = None,
+    parsed_options: dict[str, Any] | None = None,
+) -> dict[str, dict[str, Any]]:
+    """Return integration settings with *key* updated."""
+    settings = integration_settings(state)
+    current = dict(settings.get(key, {}))
+
+    if script_type:
+        current["script"] = script_type
+    if raw_options is not None:
+        current["raw_options"] = raw_options
+    elif "raw_options" in current and not current.get("raw_options"):
+        current.pop("raw_options", None)
+
+    if parsed_options is not None:
+        current["parsed_options"] = parsed_options
+    elif raw_options is not None:
+        current.pop("parsed_options", None)
+
+    current["invoke_separator"] = integration.effective_invoke_separator(parsed_options)
+    settings[key] = current
+    return settings
+
+
+def invoke_separator_for_integration(
+    integration: Any,
+    state: dict[str, Any],
+    key: str,
+    parsed_options: dict[str, Any] | None = None,
+) -> str:
+    """Resolve the invocation separator for stored/default integration state."""
+    if parsed_options is not None:
+        return integration.effective_invoke_separator(parsed_options)
+
+    setting = integration_setting(state, key)
+    stored_separator = setting.get("invoke_separator")
+    if isinstance(stored_separator, str) and stored_separator:
+        return stored_separator
+
+    stored_parsed = setting.get("parsed_options")
+    if isinstance(stored_parsed, dict):
+        return integration.effective_invoke_separator(stored_parsed)
+
+    return integration.effective_invoke_separator(None)
diff --git a/src/specify_cli/integration_state.py b/src/specify_cli/integration_state.py
new file mode 100644
--- /dev/null
+++ b/src/specify_cli/integration_state.py
@@ -0,0 +1,161 @@
+"""State helpers for installed AI agent integrations."""
+
+from __future__ import annotations
+
+import json
+from pathlib import Path
+from typing import Any
+
+
+INTEGRATION_JSON = ".specify/integration.json"
+INTEGRATION_STATE_SCHEMA = 1
+
+
+def clean_integration_key(key: Any) -> str | None:
+    """Return a stripped integration key, or None for empty/non-string values."""
+    if not isinstance(key, str) or not key.strip():
+        return None
+    return key.strip()
+
+
+def dedupe_integration_keys(keys: list[Any]) -> list[str]:
+    """Return a de-duplicated list of non-empty integration keys."""
+    seen: set[str] = set()
+    deduped: list[str] = []
+    for key in keys:
+        clean = clean_integration_key(key)
+        if clean is None:
+            continue
+        if clean in seen:
+            continue
+        seen.add(clean)
+        deduped.append(clean)
+    return deduped
+
+
+def normalize_integration_settings(settings: Any) -> dict[str, dict[str, Any]]:
+    """Return JSON-safe per-integration runtime settings."""
+    if not isinstance(settings, dict):
+        return {}
+
+    normalized: dict[str, dict[str, Any]] = {}
+    for key, value in settings.items():
+        if not isinstance(key, str) or not key.strip() or not isinstance(value, dict):
+            continue
+
+        clean: dict[str, Any] = {}
+        script = value.get("script")
+        if isinstance(script, str) and script.strip():
+            clean["script"] = script.strip()
+
+        raw_options = value.get("raw_options")
+        if isinstance(raw_options, str):
+            clean["raw_options"] = raw_options
+
+        parsed_options = value.get("parsed_options")
+        if isinstance(parsed_options, dict):
+            clean["parsed_options"] = parsed_options
+
+        invoke_separator = value.get("invoke_separator")
+        if isinstance(invoke_separator, str) and invoke_separator.strip():
+            clean["invoke_separator"] = invoke_separator.strip()
+
+        if clean:
+            normalized[key.strip()] = clean
+
+    return normalized
+
+
+def _normalized_integration_state_schema(value: Any) -> int:
+    if isinstance(value, int) and not isinstance(value, bool) and value > INTEGRATION_STATE_SCHEMA:
+        return value
+    return INTEGRATION_STATE_SCHEMA
+
+
+def normalize_integration_state(data: dict[str, Any]) -> dict[str, Any]:
+    """Normalize legacy and multi-install integration metadata."""
+    legacy_key = clean_integration_key(data.get("integration"))
+    default_key = clean_integration_key(data.get("default_integration")) or legacy_key
+
+    installed = data.get("installed_integrations")
+    installed_keys = dedupe_integration_keys(installed if isinstance(installed, list) else [])
+    if not default_key and installed_keys:
+        default_key = installed_keys[0]
+    if default_key and default_key not in installed_keys:
+        installed_keys.insert(0, default_key)
+
+    settings = normalize_integration_settings(data.get("integration_settings"))
+
+    normalized = dict(data)
+    normalized["integration_state_schema"] = _normalized_integration_state_schema(
+        data.get("integration_state_schema")
+    )
+    if default_key:
+        normalized["integration"] = default_key
+        normalized["default_integration"] = default_key
+    else:
+        normalized.pop("integration", None)
+        normalized.pop("default_integration", None)
+    normalized["installed_integrations"] = installed_keys
+    normalized["integration_settings"] = {
+        key: settings[key] for key in installed_keys if key in settings
+    }
+    return normalized
+
+
+def default_integration_key(state: dict[str, Any]) -> str | None:
+    """Return the default integration key from normalized state."""
+    key = state.get("default_integration") or state.get("integration")
+    return clean_integration_key(key)
+
+
+def installed_integration_keys(state: dict[str, Any]) -> list[str]:
+    """Return installed integration keys from normalized state."""
+    return dedupe_integration_keys(state.get("installed_integrations", []))
+
+
+def integration_settings(state: dict[str, Any]) -> dict[str, dict[str, Any]]:
+    """Return normalized per-integration settings from state."""
+    return normalize_integration_settings(state.get("integration_settings"))
+
+
+def integration_setting(state: dict[str, Any], key: str) -> dict[str, Any]:
+    """Return stored runtime settings for *key*."""
+    return dict(integration_settings(state).get(key, {}))
+
+
+def write_integration_json(
+    project_root: Path,
+    *,
+    version: str,
+    integration_key: str | None,
+    installed_integrations: list[str] | None = None,
+    settings: dict[str, dict[str, Any]] | None = None,
+) -> None:
+    """Write ``.specify/integration.json`` with legacy-compatible state."""
+    dest = project_root / INTEGRATION_JSON
+    dest.parent.mkdir(parents=True, exist_ok=True)
+
+    integration_key = clean_integration_key(integration_key)
+    installed = dedupe_integration_keys(installed_integrations or [])
+    if integration_key and integration_key not in installed:
+        installed.insert(0, integration_key)
+    if not integration_key and installed:
+        integration_key = installed[0]
+
+    normalized_settings = normalize_integration_settings(settings or {})
+    normalized_settings = {
+        key: normalized_settings[key] for key in installed if key in normalized_settings
+    }
+
+    data: dict[str, Any] = {
+        "version": version,
+        "integration_state_schema": INTEGRATION_STATE_SCHEMA,
+        "installed_integrations": installed,
+        "integration_settings": normalized_settings,
+    }
+    if integration_key:
+        data["integration"] = integration_key
+        data["default_integration"] = integration_key
+
+    dest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
diff --git a/src/specify_cli/integrations/auggie/__init__.py b/src/specify_cli/integrations/auggie/__init__.py
--- a/src/specify_cli/integrations/auggie/__init__.py
+++ b/src/specify_cli/integrations/auggie/__init__.py
@@ -19,3 +19,4 @@ class AuggieIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = ".augment/rules/specify-rules.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/base.py b/src/specify_cli/integrations/base.py
--- a/src/specify_cli/integrations/base.py
+++ b/src/specify_cli/integrations/base.py
@@ -87,6 +87,14 @@ class IntegrationBase(ABC):
     invoke_separator: str = "."
     """Separator used in slash-command invocations (``"."`` → ``/speckit.plan``)."""
 
+    multi_install_safe: bool = False
+    """Whether this integration is declared safe to install alongside others.
+
+    Safe integrations must use a static, unique agent root, command directory,
+    and context file. Registry tests enforce those invariants for every
+    integration that sets this flag.
+    """
+
     # -- Markers for managed context section ------------------------------
 
     CONTEXT_MARKER_START = "<!-- SPECKIT START -->"
diff --git a/src/specify_cli/integrations/claude/__init__.py b/src/specify_cli/integrations/claude/__init__.py
--- a/src/specify_cli/integrations/claude/__init__.py
+++ b/src/specify_cli/integrations/claude/__init__.py
@@ -53,6 +53,7 @@ class ClaudeIntegration(SkillsIntegration):
         "extension": "/SKILL.md",
     }
     context_file = "CLAUDE.md"
+    multi_install_safe = True
 
     @staticmethod
     def inject_argument_hint(content: str, hint: str) -> str:
diff --git a/src/specify_cli/integrations/codebuddy/__init__.py b/src/specify_cli/integrations/codebuddy/__init__.py
--- a/src/specify_cli/integrations/codebuddy/__init__.py
+++ b/src/specify_cli/integrations/codebuddy/__init__.py
@@ -19,3 +19,4 @@ class CodebuddyIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = "CODEBUDDY.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/codex/__init__.py b/src/specify_cli/integrations/codex/__init__.py
--- a/src/specify_cli/integrations/codex/__init__.py
+++ b/src/specify_cli/integrations/codex/__init__.py
@@ -27,6 +27,7 @@ class CodexIntegration(SkillsIntegration):
         "extension": "/SKILL.md",
     }
     context_file = "AGENTS.md"
+    multi_install_safe = True
 
     def build_exec_args(
         self,
diff --git a/src/specify_cli/integrations/cursor_agent/__init__.py b/src/specify_cli/integrations/cursor_agent/__init__.py
--- a/src/specify_cli/integrations/cursor_agent/__init__.py
+++ b/src/specify_cli/integrations/cursor_agent/__init__.py
@@ -26,6 +26,7 @@ class CursorAgentIntegration(SkillsIntegration):
     }
 
     context_file = ".cursor/rules/specify-rules.mdc"
+    multi_install_safe = True
 
     @classmethod
     def options(cls) -> list[IntegrationOption]:
diff --git a/src/specify_cli/integrations/gemini/__init__.py b/src/specify_cli/integrations/gemini/__init__.py
--- a/src/specify_cli/integrations/gemini/__init__.py
+++ b/src/specify_cli/integrations/gemini/__init__.py
@@ -19,3 +19,4 @@ class GeminiIntegration(TomlIntegration):
         "extension": ".toml",
     }
     context_file = "GEMINI.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/iflow/__init__.py b/src/specify_cli/integrations/iflow/__init__.py
--- a/src/specify_cli/integrations/iflow/__init__.py
+++ b/src/specify_cli/integrations/iflow/__init__.py
@@ -19,3 +19,4 @@ class IflowIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = "IFLOW.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/junie/__init__.py b/src/specify_cli/integrations/junie/__init__.py
--- a/src/specify_cli/integrations/junie/__init__.py
+++ b/src/specify_cli/integrations/junie/__init__.py
@@ -19,3 +19,4 @@ class JunieIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = ".junie/AGENTS.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/kilocode/__init__.py b/src/specify_cli/integrations/kilocode/__init__.py
--- a/src/specify_cli/integrations/kilocode/__init__.py
+++ b/src/specify_cli/integrations/kilocode/__init__.py
@@ -19,3 +19,4 @@ class KilocodeIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = ".kilocode/rules/specify-rules.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/kimi/__init__.py b/src/specify_cli/integrations/kimi/__init__.py
--- a/src/specify_cli/integrations/kimi/__init__.py
+++ b/src/specify_cli/integrations/kimi/__init__.py
@@ -36,6 +36,7 @@ class KimiIntegration(SkillsIntegration):
         "extension": "/SKILL.md",
     }
     context_file = "KIMI.md"
+    multi_install_safe = True
 
     @classmethod
     def options(cls) -> list[IntegrationOption]:
diff --git a/src/specify_cli/integrations/manifest.py b/src/specify_cli/integrations/manifest.py
--- a/src/specify_cli/integrations/manifest.py
+++ b/src/specify_cli/integrations/manifest.py
@@ -11,6 +11,7 @@
 import hashlib
 import json
 import os
+import tempfile
 from datetime import datetime, timezone
 from pathlib import Path
 from typing import Any
@@ -47,6 +48,59 @@ def _validate_rel_path(rel: Path, root: Path) -> Path:
     return resolved
 
 
+def _manifest_path_label(root: Path, path: Path) -> str:
+    try:
+        return path.relative_to(root).as_posix()
+    except ValueError:
+        return path.as_posix()
+
+
+def _ensure_safe_manifest_directory(root: Path, directory: Path) -> None:
+    """Create a manifest directory without following symlinked parents."""
+    root_resolved = root.resolve()
+    try:
+        rel = directory.relative_to(root)
+    except ValueError:
+        label = _manifest_path_label(root, directory)
+        raise ValueError(f"Integration manifest directory escapes project root: {label}") from None
+
+    current = root
+    for part in rel.parts:
+        current = current / part
+        label = _manifest_path_label(root, current)
+        if current.is_symlink():
+            raise ValueError(f"Refusing to use symlinked integration manifest directory: {label}")
+        if current.exists():
+            if not current.is_dir():
+                raise ValueError(f"Integration manifest directory path is not a directory: {label}")
+            try:
+                current.resolve().relative_to(root_resolved)
+            except (OSError, ValueError):
+                raise ValueError(f"Integration manifest directory escapes project root: {label}") from None
+            continue
+        current.mkdir()
+        try:
+            current.resolve().relative_to(root_resolved)
+        except (OSError, ValueError):
+            raise ValueError(f"Integration manifest directory escapes project root: {label}") from None
+
+
+def _ensure_safe_manifest_destination(root: Path, path: Path) -> None:
+    """Refuse manifest writes that would escape the project or follow symlinks."""
+    root_resolved = root.resolve()
+    _ensure_safe_manifest_directory(root, path.parent)
+    label = _manifest_path_label(root, path)
+    if path.is_symlink():
+        raise ValueError(f"Refusing to overwrite symlinked integration manifest path: {label}")
+    if path.exists():
+        if not path.is_file():
+            raise ValueError(f"Integration manifest path is not a file: {label}")
+        try:
+            path.resolve().relative_to(root_resolved)
+        except (OSError, ValueError):
+            raise ValueError(f"Integration manifest path escapes project root: {label}") from None
+
+
 class IntegrationManifest:
     """Tracks files installed by a single integration.
 
@@ -217,8 +271,19 @@ def save(self) -> Path:
             "files": self._files,
         }
         path = self.manifest_path
-        path.parent.mkdir(parents=True, exist_ok=True)
-        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
+        content = json.dumps(data, indent=2) + "\n"
+        _ensure_safe_manifest_destination(self.project_root, path)
+        fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
+        temp_path = Path(temp_name)
+        try:
+            with os.fdopen(fd, "w", encoding="utf-8") as fh:
+                fh.write(content)
+            temp_path.chmod(0o644)
+            _ensure_safe_manifest_destination(self.project_root, path)
+            os.replace(temp_path, path)
+        finally:
+            if temp_path.exists():
+                temp_path.unlink()
         return path
 
     @classmethod
diff --git a/src/specify_cli/integrations/qodercli/__init__.py b/src/specify_cli/integrations/qodercli/__init__.py
--- a/src/specify_cli/integrations/qodercli/__init__.py
+++ b/src/specify_cli/integrations/qodercli/__init__.py
@@ -19,3 +19,4 @@ class QodercliIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = "QODER.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/qwen/__init__.py b/src/specify_cli/integrations/qwen/__init__.py
--- a/src/specify_cli/integrations/qwen/__init__.py
+++ b/src/specify_cli/integrations/qwen/__init__.py
@@ -19,3 +19,4 @@ class QwenIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = "QWEN.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/roo/__init__.py b/src/specify_cli/integrations/roo/__init__.py
--- a/src/specify_cli/integrations/roo/__init__.py
+++ b/src/specify_cli/integrations/roo/__init__.py
@@ -19,3 +19,4 @@ class RooIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = ".roo/rules/specify-rules.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/shai/__init__.py b/src/specify_cli/integrations/shai/__init__.py
--- a/src/specify_cli/integrations/shai/__init__.py
+++ b/src/specify_cli/integrations/shai/__init__.py
@@ -19,3 +19,4 @@ class ShaiIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = "SHAI.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/tabnine/__init__.py b/src/specify_cli/integrations/tabnine/__init__.py
--- a/src/specify_cli/integrations/tabnine/__init__.py
+++ b/src/specify_cli/integrations/tabnine/__init__.py
@@ -19,3 +19,4 @@ class TabnineIntegration(TomlIntegration):
         "extension": ".toml",
     }
     context_file = "TABNINE.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/integrations/trae/__init__.py b/src/specify_cli/integrations/trae/__init__.py
--- a/src/specify_cli/integrations/trae/__init__.py
+++ b/src/specify_cli/integrations/trae/__init__.py
@@ -27,6 +27,7 @@ class TraeIntegration(SkillsIntegration):
         "extension": "/SKILL.md",
     }
     context_file = ".trae/rules/project_rules.md"
+    multi_install_safe = True
 
     @classmethod
     def options(cls) -> list[IntegrationOption]:
diff --git a/src/specify_cli/integrations/windsurf/__init__.py b/src/specify_cli/integrations/windsurf/__init__.py
--- a/src/specify_cli/integrations/windsurf/__init__.py
+++ b/src/specify_cli/integrations/windsurf/__init__.py
@@ -19,3 +19,4 @@ class WindsurfIntegration(MarkdownIntegration):
         "extension": ".md",
     }
     context_file = ".windsurf/rules/specify-rules.md"
+    multi_install_safe = True
diff --git a/src/specify_cli/shared_infra.py b/src/specify_cli/shared_infra.py
new file mode 100644
--- /dev/null
+++ b/src/specify_cli/shared_infra.py
@@ -0,0 +1,317 @@
+"""Shared Spec Kit infrastructure installation helpers."""
+
+from __future__ import annotations
+
+import os
+import tempfile
+from pathlib import Path
+from typing import Any
+
+from .integrations.base import IntegrationBase
+from .integrations.manifest import IntegrationManifest
+
+
+def load_speckit_manifest(
+    project_path: Path,
+    *,
+    version: str,
+    console: Any | None = None,
+) -> IntegrationManifest:
+    """Load the shared infrastructure manifest, preserving existing entries."""
+    manifest_path = project_path / ".specify" / "integrations" / "speckit.manifest.json"
+    if manifest_path.exists():
+        try:
+            manifest = IntegrationManifest.load("speckit", project_path)
+            manifest.version = version
+            return manifest
+        except (ValueError, FileNotFoundError, OSError, UnicodeDecodeError) as exc:
+            if console is not None:
+                console.print(
+                    f"[yellow]Warning:[/yellow] Could not read shared infrastructure "
+                    f"manifest at {manifest_path}: {exc}"
+                )
+                console.print(
+                    "A new shared manifest will be created; previously tracked "
+                    "shared files may be treated as untracked."
+                )
+    return IntegrationManifest("speckit", project_path, version=version)
+
+
+def shared_templates_source(
+    *,
+    core_pack: Path | None,
+    repo_root: Path,
+) -> Path:
+    """Return the bundled/source shared templates directory."""
+    if core_pack and (core_pack / "templates").is_dir():
+        return core_pack / "templates"
+    return repo_root / "templates"
+
+
+def shared_scripts_source(
+    *,
+    core_pack: Path | None,
+    repo_root: Path,
+) -> Path:
+    """Return the bundled/source shared scripts directory."""
+    if core_pack and (core_pack / "scripts").is_dir():
+        return core_pack / "scripts"
+    return repo_root / "scripts"
+
+
+def _shared_destination_label(project_path: Path, dest: Path) -> str:
+    try:
+        return dest.relative_to(project_path).as_posix()
+    except ValueError:
+        return str(dest)
+
+
+def _shared_relative_path(project_path: Path, dest: Path) -> Path:
+    try:
+        rel = dest.relative_to(project_path)
+    except ValueError:
+        label = _shared_destination_label(project_path, dest)
+        raise ValueError(f"Shared infrastructure path escapes project root: {label}") from None
+
+    if rel.is_absolute() or ".." in rel.parts:
+        label = _shared_destination_label(project_path, dest)
+        raise ValueError(f"Shared infrastructure path escapes project root: {label}")
+    return rel
+
+
+def _ensure_safe_shared_directory(project_path: Path, directory: Path, *, create: bool = True) -> None:
+    """Create a shared infra directory without following symlinked parents."""
+    root = project_path.resolve()
+    rel = _shared_relative_path(project_path, directory)
+    current = project_path
+
+    for part in rel.parts:
+        current = current / part
+        label = _shared_destination_label(project_path, current)
+        if current.is_symlink():
+            raise ValueError(f"Refusing to use symlinked shared infrastructure directory: {label}")
+        if current.exists():
+            if not current.is_dir():
+                raise ValueError(f"Shared infrastructure directory path is not a directory: {label}")
+            try:
+                current.resolve().relative_to(root)
+            except (OSError, ValueError):
+                raise ValueError(f"Shared infrastructure directory escapes project root: {label}") from None
+            continue
+        if not create:
+            raise ValueError(f"Shared infrastructure directory does not exist: {label}")
+        current.mkdir()
+        if current.is_symlink():
+            raise ValueError(f"Refusing to use symlinked shared infrastructure directory: {label}")
+        try:
+            current.resolve().relative_to(root)
+        except (OSError, ValueError):
+            raise ValueError(f"Shared infrastructure directory escapes project root: {label}") from None
+
+
+def _validate_safe_shared_directory(project_path: Path, directory: Path) -> None:
+    """Validate existing directory parents while allowing missing directories."""
+    root = project_path.resolve()
+    rel = _shared_relative_path(project_path, directory)
+    current = project_path
+
+    for part in rel.parts:
+        current = current / part
+        label = _shared_destination_label(project_path, current)
+        if current.is_symlink():
+            raise ValueError(f"Refusing to use symlinked shared infrastructure directory: {label}")
+        if not current.exists():
+            continue
+        if not current.is_dir():
+            raise ValueError(f"Shared infrastructure directory path is not a directory: {label}")
+        try:
+            current.resolve().relative_to(root)
+        except (OSError, ValueError):
+            raise ValueError(f"Shared infrastructure directory escapes project root: {label}") from None
+
+
+def _ensure_safe_shared_destination(
+    project_path: Path,
+    dest: Path,
+    *,
+    parent_must_exist: bool = True,
+) -> None:
+    """Refuse shared infra writes that would escape or follow symlinks."""
+    root = project_path.resolve()
+    _shared_relative_path(project_path, dest)
+    if parent_must_exist:
+        _ensure_safe_shared_directory(project_path, dest.parent, create=False)
+    else:
+        _validate_safe_shared_directory(project_path, dest.parent)
+    label = _shared_destination_label(project_path, dest)
+    if dest.is_symlink():
+        raise ValueError(f"Refusing to overwrite symlinked shared infrastructure path: {label}")
+
+    if dest.exists():
+        try:
+            dest.resolve().relative_to(root)
+        except (OSError, ValueError):
+            raise ValueError(f"Shared infrastructure destination escapes project root: {label}") from None
+
+
+def _write_shared_text(project_path: Path, dest: Path, content: str) -> None:
+    _write_shared_bytes(project_path, dest, content.encode("utf-8"))
+
+
+def _write_shared_bytes(
+    project_path: Path,
+    dest: Path,
+    content: bytes,
+    *,
+    mode: int = 0o644,
+) -> None:
+    _ensure_safe_shared_destination(project_path, dest)
+    fd, temp_name = tempfile.mkstemp(prefix=f".{dest.name}.", dir=dest.parent)
+    temp_path = Path(temp_name)
+    try:
+        with os.fdopen(fd, "wb") as fh:
+            fh.write(content)
+        temp_path.chmod(mode)
+        _ensure_safe_shared_destination(project_path, dest)
+        os.replace(temp_path, dest)
+    finally:
+        if temp_path.exists():
+            temp_path.unlink()
+
+
+def refresh_shared_templates(
+    project_path: Path,
+    *,
+    version: str,
+    core_pack: Path | None,
+    repo_root: Path,
+    console: Any,
+    invoke_separator: str,
+    force: bool = False,
+) -> None:
+    """Refresh default-sensitive shared templates without touching scripts."""
+    templates_src = shared_templates_source(core_pack=core_pack, repo_root=repo_root)
+    if not templates_src.is_dir():
+        return
+
+    manifest = load_speckit_manifest(project_path, version=version, console=console)
+    tracked_files = manifest.files
+    modified = set(manifest.check_modified())
+    skipped_files: list[str] = []
+    planned_updates: list[tuple[Path, str, str]] = []
+
+    dest_templates = project_path / ".specify" / "templates"
+    _ensure_safe_shared_directory(project_path, dest_templates)
+    for src in templates_src.iterdir():
+        if not src.is_file() or src.name == "vscode-settings.json" or src.name.startswith("."):
+            continue
+
+        dst = dest_templates / src.name
+        _ensure_safe_shared_destination(project_path, dst)
+        rel = dst.relative_to(project_path).as_posix()
+        if dst.exists() and not force:
+            if rel not in tracked_files or rel in modified:
+                skipped_files.append(rel)
+                continue
+
+        content = src.read_text(encoding="utf-8")
+        content = IntegrationBase.resolve_command_refs(content, invoke_separator)
+        planned_updates.append((dst, rel, content))
+
+    for dst, rel, content in planned_updates:
+        _write_shared_text(project_path, dst, content)
+        manifest.record_existing(rel)
+
+    manifest.save()
+
+    if skipped_files:
+        console.print(
+            f"[yellow]⚠[/yellow]  {len(skipped_files)} modified or untracked shared template file(s) were not updated:"
+        )
+        for rel in skipped_files:
+            console.print(f"    {rel}")
+
+
+def install_shared_infra(
+    project_path: Path,
+    script_type: str,
+    *,
+    version: str,
+    core_pack: Path | None,
+    repo_root: Path,
+    console: Any,
+    force: bool = False,
+    invoke_separator: str = ".",
+) -> bool:
+    """Install shared scripts and templates into *project_path*."""
+    manifest = load_speckit_manifest(project_path, version=version, console=console)
+    skipped_files: list[str] = []
+    planned_copies: list[tuple[Path, str, bytes, int]] = []
+    planned_templates: list[tuple[Path, str, str]] = []
+
+    scripts_src = shared_scripts_source(core_pack=core_pack, repo_root=repo_root)
+    if scripts_src.is_dir():
+        dest_scripts = project_path / ".specify" / "scripts"
+        _ensure_safe_shared_directory(project_path, dest_scripts)
+        variant_dir = "bash" if script_type == "sh" else "powershell"
+        variant_src = scripts_src / variant_dir
+        if variant_src.is_dir():
+            dest_variant = dest_scripts / variant_dir
+            _ensure_safe_shared_directory(project_path, dest_variant)
+            for src_path in variant_src.rglob("*"):
+                if not src_path.is_file():
+                    continue
+
+                rel_path = src_path.relative_to(variant_src)
+                dst_path = dest_variant / rel_path
+                _ensure_safe_shared_destination(project_path, dst_path, parent_must_exist=False)
+                if dst_path.exists() and not force:
+                    skipped_files.append(dst_path.relative_to(project_path).as_posix())
+                    continue
+
+                _ensure_safe_shared_directory(project_path, dst_path.parent)
+                rel = dst_path.relative_to(project_path).as_posix()
+                planned_copies.append((dst_path, rel, src_path.read_bytes(), src_path.stat().st_mode & 0o777))
+
+    templates_src = shared_templates_source(core_pack=core_pack, repo_root=repo_root)
+    if templates_src.is_dir():
+        dest_templates = project_path / ".specify" / "templates"
+        _ensure_safe_shared_directory(project_path, dest_templates)
+        for src in templates_src.iterdir():
+            if not src.is_file() or src.name == "vscode-settings.json" or src.name.startswith("."):
+                continue
+
+            dst = dest_templates / src.name
+            _ensure_safe_shared_destination(project_path, dst)
+            if dst.exists() and not force:
+                skipped_files.append(dst.relative_to(project_path).as_posix())
+                continue
+
+            content = src.read_text(encoding="utf-8")
+            content = IntegrationBase.resolve_command_refs(content, invoke_separator)
+            rel = dst.relative_to(project_path).as_posix()
+            planned_templates.append((dst, rel, content))
+
+    for dst_path, rel, content, mode in planned_copies:
+        _ensure_safe_shared_directory(project_path, dst_path.parent)
+        _write_shared_bytes(project_path, dst_path, content, mode=mode)
+        manifest.record_existing(rel)
+
+    for dst, rel, content in planned_templates:
+        _write_shared_text(project_path, dst, content)
+        manifest.record_existing(rel)
+
+    if skipped_files:
+        console.print(
+            f"[yellow]⚠[/yellow]  {len(skipped_files)} shared infrastructure file(s) already exist and were not updated:"
+        )
+        for path in skipped_files:
+            console.print(f"    {path}")
+        console.print(
+            "To refresh shared infrastructure, run "
+            "[cyan]specify init --here --force[/cyan] or "
+            "[cyan]specify integration upgrade --force[/cyan]."
+        )
+
+    manifest.save()
+    return True
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
