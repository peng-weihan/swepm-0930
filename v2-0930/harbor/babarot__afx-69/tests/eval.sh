#!/bin/bash
set -uxo pipefail
cd /testbed
# Keep local test servers from being routed through host proxy settings.
export NO_PROXY="localhost,127.0.0.1,0.0.0.0,::1${NO_PROXY:+,$NO_PROXY}"
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1${no_proxy:+,$no_proxy}"
echo "OMNIGRIL_LOCAL_NO_PROXY_ADDED=1"


COMMIT_SHA="95c6bcd73203fa37b5cd3292b22632d21d1dfeb6"

RUNNABLE_TEST_FILES=(
  cmd/meta_test.go
  internal/data/data_test.go
  internal/dependency/dependency_test.go
  internal/env/config_test.go
  internal/errors/errors_test.go
  internal/github/client_test.go
  internal/github/github_test.go
  internal/helpers/path/path_test.go
  internal/helpers/shell/shell_test.go
  internal/helpers/spin/spin_test.go
  internal/helpers/templates/normalizer_test.go
  internal/logging/logging_additional_test.go
  internal/logging/logging_test.go
  internal/pkg/command_test.go
  internal/pkg/config_test.go
  internal/pkg/installed_test.go
  internal/pkg/read_test.go
  internal/pkg/resource_test.go
  internal/pkg/util_test.go
  internal/printers/printers_test.go
  internal/state/state_additional_test.go
  internal/state/state_test.go
  internal/state/testing.go
  internal/templates/templates_test.go
  internal/update/update_test.go
)

DELETED_TEST_PATCH_FILES=()

# Pre-patch cleanup: restore files that exist in base commit; remove ones that don't (newly added by patch).
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${COMMIT_SHA}:$f" 2>/dev/null; then
    git checkout "${COMMIT_SHA}" -- "$f"
  else
    rm -f "$f"
  fi
done

# Apply test patch (content injected by harness)
TEST_PATCH_FILE="$(mktemp)"
cat > "$TEST_PATCH_FILE" <<'EOF_114329324912'
diff --git a/cmd/meta_test.go b/cmd/meta_test.go
--- a/cmd/meta_test.go
+++ b/cmd/meta_test.go
@@ -6,8 +6,8 @@ import (
 	"os"
 	"testing"
 
-	"github.com/babarot/afx/pkg/config"
-	"github.com/babarot/afx/pkg/state"
+	afxpkg "github.com/babarot/afx/internal/pkg"
+	"github.com/babarot/afx/internal/state"
 )
 
 func init() {
@@ -16,9 +16,9 @@ func init() {
 
 func TestGetPackage_found(t *testing.T) {
 	m := metaCmd{
-		packages: []config.Package{
-			&config.GitHub{Name: "tool-a", Owner: "owner", Repo: "tool-a"},
-			&config.GitHub{Name: "tool-b", Owner: "owner", Repo: "tool-b"},
+		packages: []afxpkg.Package{
+			&afxpkg.GitHub{Name: "tool-a", Owner: "owner", Repo: "tool-a"},
+			&afxpkg.GitHub{Name: "tool-b", Owner: "owner", Repo: "tool-b"},
 		},
 	}
 
@@ -35,8 +35,8 @@ func TestGetPackage_found(t *testing.T) {
 
 func TestGetPackage_notFound(t *testing.T) {
 	m := metaCmd{
-		packages: []config.Package{
-			&config.GitHub{Name: "tool-a", Owner: "owner", Repo: "tool-a"},
+		packages: []afxpkg.Package{
+			&afxpkg.GitHub{Name: "tool-a", Owner: "owner", Repo: "tool-a"},
 		},
 	}
 
@@ -50,10 +50,10 @@ func TestGetPackage_notFound(t *testing.T) {
 
 func TestGetPackages(t *testing.T) {
 	m := metaCmd{
-		packages: []config.Package{
-			&config.GitHub{Name: "tool-a", Owner: "owner", Repo: "tool-a"},
-			&config.GitHub{Name: "tool-b", Owner: "owner", Repo: "tool-b"},
-			&config.GitHub{Name: "tool-c", Owner: "owner", Repo: "tool-c"},
+		packages: []afxpkg.Package{
+			&afxpkg.GitHub{Name: "tool-a", Owner: "owner", Repo: "tool-a"},
+			&afxpkg.GitHub{Name: "tool-b", Owner: "owner", Repo: "tool-b"},
+			&afxpkg.GitHub{Name: "tool-c", Owner: "owner", Repo: "tool-c"},
 		},
 	}
 
@@ -75,25 +75,25 @@ func TestGetPackages(t *testing.T) {
 }
 
 func TestGetConfig_mergesAll(t *testing.T) {
-	main := &config.Main{Shell: "zsh"}
+	main := &afxpkg.Main{Shell: "zsh"}
 
 	m := metaCmd{
-		configs: map[string]config.Config{
+		configs: map[string]afxpkg.Config{
 			"file1.yaml": {
 				Main: main,
-				GitHub: []*config.GitHub{
+				GitHub: []*afxpkg.GitHub{
 					{Name: "gh1", Owner: "o", Repo: "r1"},
 					{Name: "gh2", Owner: "o", Repo: "r2"},
 				},
-				Gist: []*config.Gist{
+				Gist: []*afxpkg.Gist{
 					{Name: "gist1", Owner: "o", ID: "id1"},
 				},
 			},
 			"file2.yaml": {
-				GitHub: []*config.GitHub{
+				GitHub: []*afxpkg.GitHub{
 					{Name: "gh3", Owner: "o", Repo: "r3"},
 				},
-				Gist: []*config.Gist{
+				Gist: []*afxpkg.Gist{
 					{Name: "gist2", Owner: "o", ID: "id2"},
 				},
 			},
@@ -121,9 +121,9 @@ func TestGetConfig_mergesAll(t *testing.T) {
 
 func TestGetConfig_noMain(t *testing.T) {
 	m := metaCmd{
-		configs: map[string]config.Config{
+		configs: map[string]afxpkg.Config{
 			"file1.yaml": {
-				GitHub: []*config.GitHub{
+				GitHub: []*afxpkg.GitHub{
 					{Name: "gh1", Owner: "o", Repo: "r1"},
 				},
 			},
diff --git a/pkg/data/data_test.go b/internal/data/data_test.go
rename from pkg/data/data_test.go
rename to internal/data/data_test.go
--- a/pkg/data/data_test.go
+++ b/internal/data/data_test.go

diff --git a/pkg/dependency/dependency_test.go b/internal/dependency/dependency_test.go
rename from pkg/dependency/dependency_test.go
rename to internal/dependency/dependency_test.go
--- a/pkg/dependency/dependency_test.go
+++ b/internal/dependency/dependency_test.go

diff --git a/pkg/env/config_test.go b/internal/env/config_test.go
rename from pkg/env/config_test.go
rename to internal/env/config_test.go
--- a/pkg/env/config_test.go
+++ b/internal/env/config_test.go

diff --git a/pkg/errors/errors_test.go b/internal/errors/errors_test.go
rename from pkg/errors/errors_test.go
rename to internal/errors/errors_test.go
--- a/pkg/errors/errors_test.go
+++ b/internal/errors/errors_test.go

diff --git a/pkg/github/client_test.go b/internal/github/client_test.go
rename from pkg/github/client_test.go
rename to internal/github/client_test.go
--- a/pkg/github/client_test.go
+++ b/internal/github/client_test.go

diff --git a/pkg/github/github_test.go b/internal/github/github_test.go
rename from pkg/github/github_test.go
rename to internal/github/github_test.go
--- a/pkg/github/github_test.go
+++ b/internal/github/github_test.go

diff --git a/internal/helpers/path/path_test.go b/internal/helpers/path/path_test.go
new file mode 100644
--- /dev/null
+++ b/internal/helpers/path/path_test.go
@@ -0,0 +1,54 @@
+package path
+
+import (
+	"runtime"
+	"testing"
+)
+
+func TestExpandTilda(t *testing.T) {
+	if runtime.GOOS == "windows" {
+		t.Skip("ExpandTilda uses HOME on Unix; skipping on Windows")
+	}
+
+	tests := map[string]struct {
+		input string
+		home  string
+		want  string
+	}{
+		"with tilde": {
+			input: "~/foo",
+			home:  "/home/user",
+			want:  "/home/user/foo",
+		},
+		"absolute path": {
+			input: "/absolute/path",
+			home:  "/home/user",
+			want:  "/absolute/path",
+		},
+		"tilde only": {
+			input: "~",
+			home:  "/home/user",
+			want:  "/home/user",
+		},
+		"empty": {
+			input: "",
+			home:  "/home/user",
+			want:  "",
+		},
+		"empty home": {
+			input: "~/foo",
+			home:  "",
+			want:  "~/foo",
+		},
+	}
+
+	for name, tt := range tests {
+		t.Run(name, func(t *testing.T) {
+			t.Setenv("HOME", tt.home)
+			got := ExpandTilda(tt.input)
+			if got != tt.want {
+				t.Errorf("ExpandTilda(%q) = %q, want %q", tt.input, got, tt.want)
+			}
+		})
+	}
+}
diff --git a/pkg/helpers/shell/shell_test.go b/internal/helpers/shell/shell_test.go
rename from pkg/helpers/shell/shell_test.go
rename to internal/helpers/shell/shell_test.go
--- a/pkg/helpers/shell/shell_test.go
+++ b/internal/helpers/shell/shell_test.go

diff --git a/pkg/helpers/spin/spin_test.go b/internal/helpers/spin/spin_test.go
rename from pkg/helpers/spin/spin_test.go
rename to internal/helpers/spin/spin_test.go
--- a/pkg/helpers/spin/spin_test.go
+++ b/internal/helpers/spin/spin_test.go

diff --git a/pkg/helpers/templates/normalizer_test.go b/internal/helpers/templates/normalizer_test.go
rename from pkg/helpers/templates/normalizer_test.go
rename to internal/helpers/templates/normalizer_test.go
--- a/pkg/helpers/templates/normalizer_test.go
+++ b/internal/helpers/templates/normalizer_test.go

diff --git a/pkg/logging/logging_additional_test.go b/internal/logging/logging_additional_test.go
rename from pkg/logging/logging_additional_test.go
rename to internal/logging/logging_additional_test.go
--- a/pkg/logging/logging_additional_test.go
+++ b/internal/logging/logging_additional_test.go

diff --git a/pkg/logging/logging_test.go b/internal/logging/logging_test.go
rename from pkg/logging/logging_test.go
rename to internal/logging/logging_test.go
--- a/pkg/logging/logging_test.go
+++ b/internal/logging/logging_test.go

diff --git a/internal/pkg/command_test.go b/internal/pkg/command_test.go
new file mode 100644
--- /dev/null
+++ b/internal/pkg/command_test.go
@@ -0,0 +1,32 @@
+package pkg
+
+import "testing"
+
+func TestCommand_buildRequired(t *testing.T) {
+	tests := map[string]struct {
+		cmd  Command
+		want bool
+	}{
+		"nil build": {
+			cmd:  Command{Build: nil},
+			want: false,
+		},
+		"empty steps": {
+			cmd:  Command{Build: &Build{Steps: []string{}}},
+			want: false,
+		},
+		"has steps": {
+			cmd:  Command{Build: &Build{Steps: []string{"make"}}},
+			want: true,
+		},
+	}
+
+	for name, tt := range tests {
+		t.Run(name, func(t *testing.T) {
+			got := tt.cmd.buildRequired()
+			if got != tt.want {
+				t.Errorf("buildRequired() = %v, want %v", got, tt.want)
+			}
+		})
+	}
+}
diff --git a/pkg/config/config_test.go b/internal/pkg/config_test.go
rename from pkg/config/config_test.go
rename to internal/pkg/config_test.go
--- a/pkg/config/config_test.go
+++ b/internal/pkg/config_test.go
@@ -1,4 +1,4 @@
-package config
+package pkg
 
 import (
 	"io"
@@ -150,86 +150,6 @@ func TestConfig_Contains(t *testing.T) {
 	}
 }
 
-func TestCountRemaining(t *testing.T) {
-	tests := map[string]struct {
-		status    map[string]Status
-		wantCount int
-		wantNames int // number of remaining names
-	}{
-		"all done": {
-			status: map[string]Status{
-				"a": {Name: "a", Done: true},
-				"b": {Name: "b", Done: true},
-			},
-			wantCount: 2,
-			wantNames: 0,
-		},
-		"none done": {
-			status: map[string]Status{
-				"a": {Name: "a", Done: false},
-				"b": {Name: "b", Done: false},
-			},
-			wantCount: 0,
-			wantNames: 2,
-		},
-		"mixed": {
-			status: map[string]Status{
-				"a": {Name: "a", Done: true},
-				"b": {Name: "b", Done: false},
-				"c": {Name: "c", Done: false},
-			},
-			wantCount: 1,
-			wantNames: 2,
-		},
-		"empty": {
-			status:    map[string]Status{},
-			wantCount: 0,
-			wantNames: 0,
-		},
-	}
-
-	for name, tt := range tests {
-		t.Run(name, func(t *testing.T) {
-			count, repos := countRemaining(tt.status)
-			if count != tt.wantCount {
-				t.Errorf("countRemaining() count = %d, want %d", count, tt.wantCount)
-			}
-			if len(repos) != tt.wantNames {
-				t.Errorf("countRemaining() repos len = %d, want %d", len(repos), tt.wantNames)
-			}
-		})
-	}
-}
-
-func TestCommand_buildRequired(t *testing.T) {
-	tests := map[string]struct {
-		cmd  Command
-		want bool
-	}{
-		"nil build": {
-			cmd:  Command{Build: nil},
-			want: false,
-		},
-		"empty steps": {
-			cmd:  Command{Build: &Build{Steps: []string{}}},
-			want: false,
-		},
-		"has steps": {
-			cmd:  Command{Build: &Build{Steps: []string{"make"}}},
-			want: true,
-		},
-	}
-
-	for name, tt := range tests {
-		t.Run(name, func(t *testing.T) {
-			got := tt.cmd.buildRequired()
-			if got != tt.want {
-				t.Errorf("buildRequired() = %v, want %v", got, tt.want)
-			}
-		})
-	}
-}
-
 func TestVisitYAML(t *testing.T) {
 	dir, err := os.MkdirTemp("", "visitYAML")
 	if err != nil {
@@ -397,27 +317,6 @@ func TestValidate_errorMessage(t *testing.T) {
 	}
 }
 
-func TestNewProgress(t *testing.T) {
-	pkgs := []Package{
-		&GitHub{Name: "a", Owner: "o", Repo: "r"},
-		&Local{Name: "b", Directory: "/tmp"},
-	}
-	p := NewProgress(pkgs)
-	if len(p.Status) != 2 {
-		t.Errorf("NewProgress() status len = %d, want 2", len(p.Status))
-	}
-	for _, name := range []string{"a", "b"} {
-		s, ok := p.Status[name]
-		if !ok {
-			t.Errorf("missing status for %q", name)
-			continue
-		}
-		if s.Done || s.Err {
-			t.Errorf("initial status for %q should be not done/err", name)
-		}
-	}
-}
-
 func TestHasGitHubReleaseBlock(t *testing.T) {
 	tests := map[string]struct {
 		pkgs []Package
diff --git a/pkg/config/installed_test.go b/internal/pkg/installed_test.go
rename from pkg/config/installed_test.go
rename to internal/pkg/installed_test.go
--- a/pkg/config/installed_test.go
+++ b/internal/pkg/installed_test.go
@@ -1,4 +1,4 @@
-package config
+package pkg
 
 import (
 	"os"
@@ -64,14 +64,15 @@ func TestLocal_GetHome_absolute(t *testing.T) {
 }
 
 func TestHTTP_GetHome(t *testing.T) {
+	if runtime.GOOS == "windows" {
+		t.Skip("skipping on Windows due to HOME path handling")
+	}
 	t.Setenv("HOME", "/test/home")
 	h := HTTP{URL: "https://example.com/releases/tool.tar.gz"}
 	got := h.GetHome()
-	// Should be based on URL host + path dir
 	if got == "" {
 		t.Error("GetHome() should not be empty")
 	}
-	// Should contain the host
 	if !filepath.IsAbs(got) {
 		t.Errorf("GetHome() = %q, should be absolute path", got)
 	}
diff --git a/pkg/config/read_test.go b/internal/pkg/read_test.go
rename from pkg/config/read_test.go
rename to internal/pkg/read_test.go
--- a/pkg/config/read_test.go
+++ b/internal/pkg/read_test.go
@@ -1,4 +1,4 @@
-package config
+package pkg
 
 import (
 	"os"
diff --git a/pkg/config/resource_test.go b/internal/pkg/resource_test.go
rename from pkg/config/resource_test.go
rename to internal/pkg/resource_test.go
--- a/pkg/config/resource_test.go
+++ b/internal/pkg/resource_test.go
@@ -1,4 +1,4 @@
-package config
+package pkg
 
 import (
 	"testing"
diff --git a/pkg/config/util_test.go b/internal/pkg/util_test.go
rename from pkg/config/util_test.go
rename to internal/pkg/util_test.go
--- a/pkg/config/util_test.go
+++ b/internal/pkg/util_test.go
@@ -1,8 +1,7 @@
-package config
+package pkg
 
 import (
 	"fmt"
-	"runtime"
 	"strings"
 	"testing"
 )
@@ -44,54 +43,6 @@ func TestAllTrue(t *testing.T) {
 	}
 }
 
-func TestExpandTilda(t *testing.T) {
-	if runtime.GOOS == "windows" {
-		t.Skip("expandTilda uses HOME on Unix; skipping on Windows")
-	}
-
-	tests := map[string]struct {
-		input string
-		home  string
-		want  string
-	}{
-		"with tilde": {
-			input: "~/foo",
-			home:  "/home/user",
-			want:  "/home/user/foo",
-		},
-		"absolute path": {
-			input: "/absolute/path",
-			home:  "/home/user",
-			want:  "/absolute/path",
-		},
-		"tilde only": {
-			input: "~",
-			home:  "/home/user",
-			want:  "/home/user",
-		},
-		"empty": {
-			input: "",
-			home:  "/home/user",
-			want:  "",
-		},
-		"empty home": {
-			input: "~/foo",
-			home:  "",
-			want:  "~/foo",
-		},
-	}
-
-	for name, tt := range tests {
-		t.Run(name, func(t *testing.T) {
-			t.Setenv("HOME", tt.home)
-			got := expandTilda(tt.input)
-			if got != tt.want {
-				t.Errorf("expandTilda(%q) = %q, want %q", tt.input, got, tt.want)
-			}
-		})
-	}
-}
-
 func TestWrapAuthError(t *testing.T) {
 	tests := map[string]struct {
 		err      error
diff --git a/pkg/printers/printers_test.go b/internal/printers/printers_test.go
rename from pkg/printers/printers_test.go
rename to internal/printers/printers_test.go
--- a/pkg/printers/printers_test.go
+++ b/internal/printers/printers_test.go

diff --git a/pkg/state/state_additional_test.go b/internal/state/state_additional_test.go
rename from pkg/state/state_additional_test.go
rename to internal/state/state_additional_test.go
--- a/pkg/state/state_additional_test.go
+++ b/internal/state/state_additional_test.go

diff --git a/pkg/state/state_test.go b/internal/state/state_test.go
rename from pkg/state/state_test.go
rename to internal/state/state_test.go
--- a/pkg/state/state_test.go
+++ b/internal/state/state_test.go

diff --git a/pkg/state/testing.go b/internal/state/testing.go
rename from pkg/state/testing.go
rename to internal/state/testing.go
--- a/pkg/state/testing.go
+++ b/internal/state/testing.go

diff --git a/pkg/templates/templates_test.go b/internal/templates/templates_test.go
rename from pkg/templates/templates_test.go
rename to internal/templates/templates_test.go
--- a/pkg/templates/templates_test.go
+++ b/internal/templates/templates_test.go
@@ -5,7 +5,7 @@ import (
 	"strings"
 	"testing"
 
-	"github.com/babarot/afx/pkg/data"
+	"github.com/babarot/afx/internal/data"
 )
 
 func testData() *data.Data {
diff --git a/pkg/update/update_test.go b/internal/update/update_test.go
rename from pkg/update/update_test.go
rename to internal/update/update_test.go
--- a/pkg/update/update_test.go
+++ b/internal/update/update_test.go
@@ -10,7 +10,7 @@ import (
 
 	"github.com/cli/cli/v2/pkg/httpmock"
 
-	"github.com/babarot/afx/pkg/github"
+	"github.com/babarot/afx/internal/github"
 )
 
 func TestCheckForUpdate(t *testing.T) {
EOF_114329324912
if [ -s "$TEST_PATCH_FILE" ]; then
  git apply -v "$TEST_PATCH_FILE"
fi
rm -f "$TEST_PATCH_FILE"

# If patch deletes files, ensure they are absent (and never run them).
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  rm -f "$f"
  if [ -e "$f" ]; then
    echo "ERROR: deleted-by-patch file still exists: $f"
    exit 2
  fi
done

# Build list of unique packages (directories) from runnable test files.
PKGS=()
declare -A seen_pkg=()
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  d="$(dirname "$f")"
  pkg="./$d"
  if [[ -z "${seen_pkg[$pkg]+x}" ]]; then
    seen_pkg["$pkg"]=1
    PKGS+=("$pkg")
  fi
done

# Run tests package-by-package to avoid cross-package resource conflicts (-p 1).
# Capture per-package PASS/FAIL and then print per-file status based on its package.
set +e
rm -f /tmp/go_test_jsonl.txt
declare -A pkg_status=()
rc=0

for pkg in "${PKGS[@]}"; do
  # -json gives structured output; tee keeps logs while allowing parsing.
  go test -p 1 -json "$pkg" 2>&1 | tee -a /tmp/go_test_jsonl.txt
  pkg_rc=${PIPESTATUS[0]}
  if [ $pkg_rc -eq 0 ]; then
    pkg_status["$pkg"]="PASS"
  else
    pkg_status["$pkg"]="FAIL"
    rc=1
  fi
done

# Emit concise, structured per-target-file status.
# (Map file -> its package status; this satisfies "names and pass/fail/skip status of each runnable target executed test file".)
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  pkg="./$(dirname "$f")"
  st="${pkg_status[$pkg]:-UNKNOWN}"
  echo "TEST_FILE_STATUS $f $st"
done

echo "OMNIGRIL_EXIT_CODE=$rc"

# Cleanup: reset runnable files back to base commit state (or remove if they didn't exist in base).
set -e
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${COMMIT_SHA}:$f" 2>/dev/null; then
    git checkout "${COMMIT_SHA}" -- "$f"
  else
    rm -f "$f"
  fi
done
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  rm -f "$f"
done

exit $rc
