#!/bin/bash
set -uxo pipefail

cd /testbed
# Keep local test servers from being routed through host proxy settings.
export NO_PROXY="localhost,127.0.0.1,0.0.0.0,::1${NO_PROXY:+,$NO_PROXY}"
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1${no_proxy:+,$no_proxy}"
echo "OMNIGRIL_LOCAL_NO_PROXY_ADDED=1"


# Go toolchain is already available in the Docker image; no extra activation needed.

RUNNABLE_TEST_FILES=(
  internal/cli/horizon_reload_test.go
)

DELETED_TEST_PATCH_FILES=(
  internal/ui/web/src/stores/horizonReload.test.ts
)

BASE_COMMIT="5741e56605430a2b3be05f23c4a504952e1101f7"

# Pre-patch cleanup: reset runnable targets to base commit state if they existed, else remove.
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${BASE_COMMIT}:$f" 2>/dev/null; then
    git checkout "${BASE_COMMIT}" -- "$f"
  else
    rm -f -- "$f"
  fi
done

# Apply test patch (content injected by harness).
TEST_PATCH_FILE="$(mktemp)"
cat > "$TEST_PATCH_FILE" <<'EOF_114329324912'
diff --git a/internal/cli/horizon_reload_test.go b/internal/cli/horizon_reload_test.go
--- a/internal/cli/horizon_reload_test.go
+++ b/internal/cli/horizon_reload_test.go
@@ -3,35 +3,38 @@ package cli
 import (
 	"os"
 	"path/filepath"
+	"runtime"
 	"testing"
 
 	"github.com/geodro/lerd/internal/config"
 )
 
-// isolateGlobalConfig points the global config (and XDG roots) at a temp dir so
-// SaveGlobal/LoadGlobal never touch the developer's real machine.
-func isolateGlobalConfig(t *testing.T, horizonReload bool) {
-	t.Helper()
-	dir := t.TempDir()
-	t.Setenv("HOME", dir)
-	t.Setenv("XDG_DATA_HOME", filepath.Join(dir, "data"))
-	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, "config"))
-
-	cfg, err := config.LoadGlobal()
-	if err != nil {
-		t.Fatalf("LoadGlobal: %v", err)
-	}
-	cfg.SetHorizonReload(horizonReload)
-	if err := config.SaveGlobal(cfg); err != nil {
-		t.Fatalf("SaveGlobal: %v", err)
-	}
+// horizonWorker mirrors the framework's horizon definition: the standard
+// command plus the reload variant core selects when a project opts in.
+var horizonWorker = config.FrameworkWorker{
+	Command:       "php artisan horizon",
+	ReloadCommand: "php artisan horizon:listen",
 }
 
-// siteWithChokidar returns a temp site dir; when withChokidar is true it seeds
-// node_modules/chokidar so the watcher prerequisite is satisfied.
-func siteWithChokidar(t *testing.T, withChokidar bool) string {
+// siteWithReload returns a temp site dir seeded with a .lerd.yaml. When
+// reloadOn is true the horizon worker is opted into auto-reload; when
+// withChokidar is true node_modules/chokidar is created so the watcher
+// prerequisite is satisfied. HOME and the XDG roots are pointed at a temp dir
+// so nothing reads or writes the developer's real machine.
+func siteWithReload(t *testing.T, reloadOn, withChokidar bool) string {
 	t.Helper()
+	home := t.TempDir()
+	t.Setenv("HOME", home)
+	t.Setenv("XDG_DATA_HOME", filepath.Join(home, "data"))
+	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, "config"))
 	site := t.TempDir()
+	cfg := &config.ProjectConfig{}
+	if reloadOn {
+		cfg.ReloadWorkers = []string{"horizon"}
+	}
+	if err := config.SaveProjectConfig(site, cfg); err != nil {
+		t.Fatalf("write .lerd.yaml: %v", err)
+	}
 	if withChokidar {
 		if err := os.MkdirAll(filepath.Join(site, "node_modules", "chokidar"), 0o755); err != nil {
 			t.Fatalf("seed chokidar: %v", err)
@@ -40,50 +43,43 @@ func siteWithChokidar(t *testing.T, withChokidar bool) string {
 	return site
 }
 
-func TestResolveHorizonCommand(t *testing.T) {
-	const base = "php artisan horizon"
+// withPoll appends the polling flag the way resolveWorkerCommand does on macOS,
+// where the container cannot observe host filesystem events.
+func withPoll(cmd string) string {
+	if runtime.GOOS == "darwin" {
+		return cmd + " --poll"
+	}
+	return cmd
+}
 
+func TestResolveWorkerCommand(t *testing.T) {
 	t.Run("reload off keeps the standard command", func(t *testing.T) {
-		isolateGlobalConfig(t, false)
-		site := siteWithChokidar(t, true)
-		if got := resolveHorizonCommand("horizon", site, base); got != base {
-			t.Errorf("got %q, want %q", got, base)
+		site := siteWithReload(t, false, true)
+		if got := resolveWorkerCommand(site, "horizon", horizonWorker); got != horizonWorker.Command {
+			t.Errorf("got %q, want %q", got, horizonWorker.Command)
 		}
 	})
 
-	t.Run("reload on with chokidar swaps to horizon:listen --poll", func(t *testing.T) {
-		isolateGlobalConfig(t, true)
-		site := siteWithChokidar(t, true)
-		want := "php artisan horizon:listen --poll"
-		if got := resolveHorizonCommand("horizon", site, base); got != want {
+	t.Run("reload on with chokidar selects the reload command", func(t *testing.T) {
+		site := siteWithReload(t, true, true)
+		want := withPoll("php artisan horizon:listen")
+		if got := resolveWorkerCommand(site, "horizon", horizonWorker); got != want {
 			t.Errorf("got %q, want %q", got, want)
 		}
 	})
 
 	t.Run("reload on without chokidar falls back to the standard command", func(t *testing.T) {
-		isolateGlobalConfig(t, true)
-		site := siteWithChokidar(t, false)
-		if got := resolveHorizonCommand("horizon", site, base); got != base {
-			t.Errorf("got %q, want %q (should fall back when chokidar missing)", got, base)
-		}
-	})
-
-	t.Run("non-horizon workers are never rewritten", func(t *testing.T) {
-		isolateGlobalConfig(t, true)
-		site := siteWithChokidar(t, true)
-		const queue = "php artisan queue:work --queue=default --tries=3 --timeout=60"
-		if got := resolveHorizonCommand("queue", site, queue); got != queue {
-			t.Errorf("got %q, want %q", got, queue)
+		site := siteWithReload(t, true, false)
+		if got := resolveWorkerCommand(site, "horizon", horizonWorker); got != horizonWorker.Command {
+			t.Errorf("got %q, want %q (should fall back when chokidar missing)", got, horizonWorker.Command)
 		}
 	})
 
-	t.Run("derives from the base so extra flags are preserved", func(t *testing.T) {
-		isolateGlobalConfig(t, true)
-		site := siteWithChokidar(t, true)
-		got := resolveHorizonCommand("horizon", site, "php artisan horizon --environment=local")
-		want := "php artisan horizon:listen --environment=local --poll"
-		if got != want {
-			t.Errorf("got %q, want %q", got, want)
+	t.Run("workers without a reload command are never rewritten", func(t *testing.T) {
+		site := siteWithReload(t, true, true)
+		queue := config.FrameworkWorker{Command: "php artisan queue:work --queue=default"}
+		if got := resolveWorkerCommand(site, "queue", queue); got != queue.Command {
+			t.Errorf("got %q, want %q", got, queue.Command)
 		}
 	})
 }
EOF_114329324912
if [ -s "$TEST_PATCH_FILE" ]; then
  git apply -v "$TEST_PATCH_FILE"
fi
rm -f "$TEST_PATCH_FILE"

# Ensure deleted-by-patch files are absent (do not restore them).
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  rm -f -- "$f"
done
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  if [ -e "$f" ]; then
    echo "ERROR: deleted test patch file still exists after applying test patch: $f"
    rc=2
    echo "OMNIGRIL_EXIT_CODE=$rc"
    exit "$rc"
  fi
done

# Determine target packages from runnable test files (Go).
TARGET_PKGS=()
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  d="$(dirname "$f")"
  pkg="./$d"
  # de-dup
  seen=0
  for p in "${TARGET_PKGS[@]}"; do
    if [ "$p" = "$pkg" ]; then
      seen=1
      break
    fi
  done
  if [ "$seen" -eq 0 ]; then
    TARGET_PKGS+=("$pkg")
  fi
done

# Run only the target packages (serialize to avoid cross-package resource conflicts).
set +e
JSON_OUT="$(mktemp)"
if [ "${#TARGET_PKGS[@]}" -eq 0 ]; then
  go test -p 1 ./... -json | tee "$JSON_OUT"
  rc=${PIPESTATUS[0]}
else
  go test -p 1 "${TARGET_PKGS[@]}" -json | tee "$JSON_OUT"
  rc=${PIPESTATUS[0]}
fi
set -e

# Summarize per runnable target file: PASS/FAIL/SKIP based on package result.
MODULE_PATH="$(go list -m -f '{{.Path}}' 2>/dev/null || true)"

normalize_pkg() {
  local pkg="$1"
  pkg="${pkg#./}"
  if [ -n "$MODULE_PATH" ]; then
    pkg="${pkg#${MODULE_PATH}/}"
    pkg="${pkg#${MODULE_PATH}}"
  fi
  pkg="${pkg#./}"
  echo "$pkg"
}

declare -A PKG_STATUS=()
while IFS='|' read -r pkg act; do
  if [ -n "$pkg" ] && [ -n "$act" ]; then
    npkg="$(normalize_pkg "$pkg")"
    case "$act" in
      pass) PKG_STATUS["$npkg"]="PASS" ;;
      fail) PKG_STATUS["$npkg"]="FAIL" ;;
      skip) PKG_STATUS["$npkg"]="SKIP" ;;
    esac
  fi
done < <(
  sed -n     -e 's/.*"Package":"\([^"]*\)".*"Action":"\([^"]*\)".*/\1|\2/p'     -e 's/.*"Action":"\([^"]*\)".*"Package":"\([^"]*\)".*/\2|\1/p'     "$JSON_OUT"
)
rm -f "$JSON_OUT"

echo "=== TARGET TEST FILE RESULTS ==="
if [ "${#RUNNABLE_TEST_FILES[@]}" -eq 0 ]; then
  echo "(no runnable target test files)"
else
  for f in "${RUNNABLE_TEST_FILES[@]}"; do
    d="$(dirname "$f")"
    nd="$(normalize_pkg "$d")"
    st="${PKG_STATUS[$nd]:-UNKNOWN}"
    echo "$f: $st"
  done
fi

echo "OMNIGRIL_EXIT_CODE=$rc"

# Cleanup: reset runnable targets back to base commit state (if they existed), else remove.
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${BASE_COMMIT}:$f" 2>/dev/null; then
    git checkout "${BASE_COMMIT}" -- "$f"
  else
    rm -f -- "$f"
  fi
done

exit "$rc"
