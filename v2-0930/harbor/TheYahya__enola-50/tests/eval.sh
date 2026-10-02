#!/bin/bash
set -uxo pipefail

cd /testbed
# Keep local test servers from being routed through host proxy settings.
export NO_PROXY="localhost,127.0.0.1,0.0.0.0,::1${NO_PROXY:+,$NO_PROXY}"
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1${no_proxy:+,$no_proxy}"
echo "OMNIGRIL_LOCAL_NO_PROXY_ADDED=1"


RUNNABLE_TEST_FILES=(
  enola_test.go
  internal/checker/checker_test.go
  internal/export/export_test.go
  regex_test.go
  website_test.go
)
DELETED_TEST_PATCH_FILES=()

BASE_SHA="d45f591fb51a463d00a61a881ab581dddba6fe85"

# Pre-patch cleanup: restore runnable targets if they exist in base, otherwise remove (new files may be added by patch)
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${BASE_SHA}:$f" 2>/dev/null; then
    git checkout "${BASE_SHA}" -- "$f"
  else
    rm -f "$f"
  fi
done

# Apply test patch (content injected by harness)
TEST_PATCH_FILE="$(mktemp)"
cat > "$TEST_PATCH_FILE" <<'EOF_114329324912'
diff --git a/enola_test.go b/enola_test.go
new file mode 100644
--- /dev/null
+++ b/enola_test.go
@@ -0,0 +1,195 @@
+package enola
+
+import (
+	"context"
+	"errors"
+	"net/http"
+	"net/http/httptest"
+	"testing"
+)
+
+func collectResults(ch <-chan Result) []Result {
+	var out []Result
+	for r := range ch {
+		out = append(out, r)
+	}
+	return out
+}
+
+func TestCheckStatusCodeFound(t *testing.T) {
+	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
+		w.WriteHeader(http.StatusOK)
+	}))
+	defer server.Close()
+
+	data := map[string]Website{
+		"TestSite": {
+			ErrorType: "status_code",
+			URL:       server.URL + "/{}",
+		},
+	}
+
+	e, err := New(WithData(data), WithHTTPClient(server.Client()), WithConcurrency(1))
+	if err != nil {
+		t.Fatalf("New failed: %v", err)
+	}
+
+	ch, err := e.Check(context.Background(), "alice")
+	if err != nil {
+		t.Fatalf("Check failed: %v", err)
+	}
+
+	results := collectResults(ch)
+	if len(results) != 1 {
+		t.Fatalf("got %d results, want 1", len(results))
+	}
+	if !results[0].Found {
+		t.Fatalf("expected found result, got %+v", results[0])
+	}
+}
+
+func TestCheckMessageNotFound(t *testing.T) {
+	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
+		_, _ = w.Write([]byte("user not found"))
+	}))
+	defer server.Close()
+
+	data := map[string]Website{
+		"TestSite": {
+			ErrorType:     "message",
+			ErrorMessages: []string{"not found"},
+			URL:           server.URL + "/{}",
+		},
+	}
+
+	e, err := New(WithData(data), WithHTTPClient(server.Client()), WithConcurrency(1))
+	if err != nil {
+		t.Fatalf("New failed: %v", err)
+	}
+
+	ch, err := e.Check(context.Background(), "alice")
+	if err != nil {
+		t.Fatalf("Check failed: %v", err)
+	}
+
+	results := collectResults(ch)
+	if len(results) != 1 || results[0].Found {
+		t.Fatalf("expected not found result, got %+v", results)
+	}
+}
+
+func TestCheckRegexInvalid(t *testing.T) {
+	data := map[string]Website{
+		"TestSite": {
+			ErrorType:  "status_code",
+			URL:        "https://example.com/{}",
+			RegexCheck: "^[a-z]+$",
+		},
+	}
+
+	e, err := New(WithData(data), WithConcurrency(1))
+	if err != nil {
+		t.Fatalf("New failed: %v", err)
+	}
+
+	ch, err := e.Check(context.Background(), "Alice123")
+	if err != nil {
+		t.Fatalf("Check failed: %v", err)
+	}
+
+	results := collectResults(ch)
+	if len(results) != 1 {
+		t.Fatalf("got %d results, want 1", len(results))
+	}
+	if results[0].Status != StatusInvalid {
+		t.Fatalf("expected invalid status, got %+v", results[0])
+	}
+}
+
+func TestCheckSiteFilterNotFound(t *testing.T) {
+	e, err := New(WithData(map[string]Website{
+		"Twitter": {ErrorType: "status_code", URL: "https://example.com/{}"},
+	}))
+	if err != nil {
+		t.Fatalf("New failed: %v", err)
+	}
+
+	_, err = e.SetSite("does-not-exist").Check(context.Background(), "alice")
+	if !errors.Is(err, ErrSiteNotFound) {
+		t.Fatalf("expected ErrSiteNotFound, got %v", err)
+	}
+}
+
+func TestCheckChannelCloses(t *testing.T) {
+	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
+		w.WriteHeader(http.StatusNotFound)
+	}))
+	defer server.Close()
+
+	data := map[string]Website{
+		"A": {ErrorType: "status_code", URL: server.URL + "/a/{}"},
+		"B": {ErrorType: "status_code", URL: server.URL + "/b/{}"},
+	}
+
+	e, err := New(WithData(data), WithHTTPClient(server.Client()), WithConcurrency(2))
+	if err != nil {
+		t.Fatalf("New failed: %v", err)
+	}
+
+	ch, err := e.Check(context.Background(), "alice")
+	if err != nil {
+		t.Fatalf("Check failed: %v", err)
+	}
+
+	results := collectResults(ch)
+	if len(results) != 2 {
+		t.Fatalf("got %d results, want 2", len(results))
+	}
+}
+
+func TestCheckRequestPayloadAndHeaders(t *testing.T) {
+	var gotMethod, gotContentType string
+	var gotBody []byte
+
+	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
+		gotMethod = r.Method
+		gotContentType = r.Header.Get("Content-Type")
+		body := make([]byte, r.ContentLength)
+		_, _ = r.Body.Read(body)
+		gotBody = body
+		w.WriteHeader(http.StatusOK)
+	}))
+	defer server.Close()
+
+	data := map[string]Website{
+		"TestSite": {
+			ErrorType:      "status_code",
+			URL:            server.URL + "/{}",
+			URLProbe:       server.URL + "/probe",
+			RequestMethod:  http.MethodPost,
+			RequestPayload: map[string]any{"username": "{}"},
+			Headers:        map[string]string{"Content-Type": "application/json"},
+		},
+	}
+
+	e, err := New(WithData(data), WithHTTPClient(server.Client()), WithConcurrency(1))
+	if err != nil {
+		t.Fatalf("New failed: %v", err)
+	}
+
+	ch, err := e.Check(context.Background(), "alice")
+	if err != nil {
+		t.Fatalf("Check failed: %v", err)
+	}
+	_ = collectResults(ch)
+
+	if gotMethod != http.MethodPost {
+		t.Fatalf("method = %q, want POST", gotMethod)
+	}
+	if gotContentType != "application/json" {
+		t.Fatalf("content-type = %q, want application/json", gotContentType)
+	}
+	if string(gotBody) != `{"username":"alice"}` {
+		t.Fatalf("body = %q", gotBody)
+	}
+}
diff --git a/internal/checker/checker_test.go b/internal/checker/checker_test.go
new file mode 100644
--- /dev/null
+++ b/internal/checker/checker_test.go
@@ -0,0 +1,160 @@
+package checker
+
+import (
+	"net/http"
+	"testing"
+)
+
+func TestStatusCodeDetector(t *testing.T) {
+	d := statusCodeDetector{}
+	tests := []struct {
+		name   string
+		resp   Response
+		target Target
+		want   bool
+	}{
+		{
+			name:   "200 ok",
+			resp:   Response{StatusCode: http.StatusOK},
+			target: Target{},
+			want:   true,
+		},
+		{
+			name:   "404 not found",
+			resp:   Response{StatusCode: http.StatusNotFound},
+			target: Target{},
+			want:   false,
+		},
+		{
+			name:   "error code match",
+			resp:   Response{StatusCode: 404},
+			target: Target{ErrorCodes: []int{404}},
+			want:   false,
+		},
+		{
+			name:   "200 with error codes excluding 404",
+			resp:   Response{StatusCode: http.StatusOK},
+			target: Target{ErrorCodes: []int{404}},
+			want:   true,
+		},
+	}
+
+	for _, tt := range tests {
+		t.Run(tt.name, func(t *testing.T) {
+			got, err := d.Detect(tt.resp, tt.target)
+			if err != nil {
+				t.Fatalf("unexpected error: %v", err)
+			}
+			if got != tt.want {
+				t.Fatalf("got %v, want %v", got, tt.want)
+			}
+		})
+	}
+}
+
+func TestMessageDetector(t *testing.T) {
+	d := messageDetector{}
+	tests := []struct {
+		name   string
+		resp   Response
+		target Target
+		want   bool
+	}{
+		{
+			name:   "single message absent",
+			resp:   Response{Body: []byte("welcome profile")},
+			target: Target{ErrorMessages: []string{"not found"}},
+			want:   true,
+		},
+		{
+			name:   "single message present",
+			resp:   Response{Body: []byte("user not found")},
+			target: Target{ErrorMessages: []string{"not found"}},
+			want:   false,
+		},
+		{
+			name:   "array any match",
+			resp:   Response{Body: []byte("<title>404 Not Found</title>")},
+			target: Target{ErrorMessages: []string{"something went wrong", "404 Not Found"}},
+			want:   false,
+		},
+		{
+			name:   "array none match",
+			resp:   Response{Body: []byte("profile page")},
+			target: Target{ErrorMessages: []string{"something went wrong", "404 Not Found"}},
+			want:   true,
+		},
+	}
+
+	for _, tt := range tests {
+		t.Run(tt.name, func(t *testing.T) {
+			got, err := d.Detect(tt.resp, tt.target)
+			if err != nil {
+				t.Fatalf("unexpected error: %v", err)
+			}
+			if got != tt.want {
+				t.Fatalf("got %v, want %v", got, tt.want)
+			}
+		})
+	}
+}
+
+func TestResponseURLDetector(t *testing.T) {
+	d := responseURLDetector{}
+	tests := []struct {
+		name   string
+		resp   Response
+		target Target
+		want   bool
+	}{
+		{
+			name:   "redirected to error url",
+			resp:   Response{FinalURL: "https://example.com/error404.aspx"},
+			target: Target{ErrorURL: "https://example.com/error404.aspx"},
+			want:   false,
+		},
+		{
+			name:   "profile url kept",
+			resp:   Response{FinalURL: "https://example.com/user/alice"},
+			target: Target{ErrorURL: "https://example.com/error404.aspx"},
+			want:   true,
+		},
+		{
+			name:   "empty error url falls back to status",
+			resp:   Response{StatusCode: http.StatusOK, FinalURL: "https://example.com/user/alice"},
+			target: Target{},
+			want:   true,
+		},
+	}
+
+	for _, tt := range tests {
+		t.Run(tt.name, func(t *testing.T) {
+			got, err := d.Detect(tt.resp, tt.target)
+			if err != nil {
+				t.Fatalf("unexpected error: %v", err)
+			}
+			if got != tt.want {
+				t.Fatalf("got %v, want %v", got, tt.want)
+			}
+		})
+	}
+}
+
+func TestRegistryLookup(t *testing.T) {
+	types := []string{"status_code", "message", "response_url"}
+	for _, errorType := range types {
+		t.Run(errorType, func(t *testing.T) {
+			d, ok := Lookup(errorType)
+			if !ok {
+				t.Fatalf("detector not registered for %q", errorType)
+			}
+			if d == nil {
+				t.Fatal("detector is nil")
+			}
+		})
+	}
+
+	if _, ok := Lookup("unknown"); ok {
+		t.Fatal("expected unknown error type to be missing")
+	}
+}
diff --git a/internal/export/export_test.go b/internal/export/export_test.go
new file mode 100644
--- /dev/null
+++ b/internal/export/export_test.go
@@ -0,0 +1,89 @@
+package export
+
+import (
+	"encoding/json"
+	"os"
+	"path/filepath"
+	"strings"
+	"testing"
+)
+
+func TestCheckExportType(t *testing.T) {
+	tests := []struct {
+		path string
+		want ExportType
+	}{
+		{"results.json", JSON},
+		{"results.JSON", JSON},
+		{"results.csv", CSV},
+		{"results.txt", NotSupported},
+	}
+
+	for _, tt := range tests {
+		if got := CheckExportType(tt.path); got != tt.want {
+			t.Fatalf("CheckExportType(%q) = %q, want %q", tt.path, got, tt.want)
+		}
+	}
+}
+
+func TestNewWriterUnsupported(t *testing.T) {
+	_, err := NewWriter("out.txt", nil)
+	if err == nil {
+		t.Fatal("expected error for unsupported format")
+	}
+}
+
+func TestJSONWriterRoundTrip(t *testing.T) {
+	dir := t.TempDir()
+	path := filepath.Join(dir, "out.json")
+	items := []Item{
+		{Title: "Twitter", URL: "https://twitter.com/alice", Found: true},
+	}
+
+	writer, err := NewWriter(path, items)
+	if err != nil {
+		t.Fatalf("NewWriter failed: %v", err)
+	}
+	if err := writer.Write(); err != nil {
+		t.Fatalf("Write failed: %v", err)
+	}
+
+	data, err := os.ReadFile(path)
+	if err != nil {
+		t.Fatalf("ReadFile failed: %v", err)
+	}
+
+	var got []Item
+	if err := json.Unmarshal(data, &got); err != nil {
+		t.Fatalf("json.Unmarshal failed: %v", err)
+	}
+	if len(got) != 1 || got[0].Title != "Twitter" || !got[0].Found {
+		t.Fatalf("unexpected data: %+v", got)
+	}
+}
+
+func TestCSVWriterRoundTrip(t *testing.T) {
+	dir := t.TempDir()
+	path := filepath.Join(dir, "out.csv")
+	items := []Item{
+		{Title: "GitHub", URL: "https://github.com/alice", Found: false},
+	}
+
+	writer, err := NewWriter(path, items)
+	if err != nil {
+		t.Fatalf("NewWriter failed: %v", err)
+	}
+	if err := writer.Write(); err != nil {
+		t.Fatalf("Write failed: %v", err)
+	}
+
+	data, err := os.ReadFile(path)
+	if err != nil {
+		t.Fatalf("ReadFile failed: %v", err)
+	}
+
+	content := string(data)
+	if !strings.Contains(content, "GitHub") || !strings.Contains(content, "false") {
+		t.Fatalf("unexpected csv content: %q", content)
+	}
+}
diff --git a/regex_test.go b/regex_test.go
new file mode 100644
--- /dev/null
+++ b/regex_test.go
@@ -0,0 +1,47 @@
+package enola
+
+import "testing"
+
+func TestMatchUsernameRegex_GitHub(t *testing.T) {
+	pattern := `^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$`
+
+	tests := []struct {
+		username string
+		want     bool
+	}{
+		{"amirrossein", true},
+		{"blue", true},
+		{"-invalid", false},
+		{"invalid-", false},
+	}
+
+	for _, tt := range tests {
+		got, err := matchUsernameRegex(pattern, tt.username)
+		if err != nil {
+			t.Fatalf("matchUsernameRegex(%q) error: %v", tt.username, err)
+		}
+		if got != tt.want {
+			t.Fatalf("matchUsernameRegex(%q) = %v, want %v", tt.username, got, tt.want)
+		}
+	}
+}
+
+func TestMatchUsernameRegex_Stdlib(t *testing.T) {
+	got, err := matchUsernameRegex(`^[a-z]+$`, "alice")
+	if err != nil {
+		t.Fatalf("unexpected error: %v", err)
+	}
+	if !got {
+		t.Fatal("expected match")
+	}
+}
+
+func TestMatchUsernameRegex_Empty(t *testing.T) {
+	got, err := matchUsernameRegex("", "anything")
+	if err != nil {
+		t.Fatalf("unexpected error: %v", err)
+	}
+	if !got {
+		t.Fatal("empty pattern should match anything")
+	}
+}
diff --git a/website_test.go b/website_test.go
new file mode 100644
--- /dev/null
+++ b/website_test.go
@@ -0,0 +1,55 @@
+package enola
+
+import (
+	"encoding/json"
+	"reflect"
+	"testing"
+)
+
+func TestWebsiteUnmarshalErrorMsgString(t *testing.T) {
+	raw := `{"errorType":"message","errorMsg":"Page Not Found","url":"https://example.com/{}"}`
+	var w Website
+	if err := json.Unmarshal([]byte(raw), &w); err != nil {
+		t.Fatalf("unmarshal failed: %v", err)
+	}
+	want := []string{"Page Not Found"}
+	if !reflect.DeepEqual(w.ErrorMessages, want) {
+		t.Fatalf("got %v, want %v", w.ErrorMessages, want)
+	}
+}
+
+func TestWebsiteUnmarshalErrorMsgArray(t *testing.T) {
+	raw := `{"errorType":"message","errorMsg":["a","b"],"url":"https://example.com/{}"}`
+	var w Website
+	if err := json.Unmarshal([]byte(raw), &w); err != nil {
+		t.Fatalf("unmarshal failed: %v", err)
+	}
+	want := []string{"a", "b"}
+	if !reflect.DeepEqual(w.ErrorMessages, want) {
+		t.Fatalf("got %v, want %v", w.ErrorMessages, want)
+	}
+}
+
+func TestWebsiteUnmarshalErrorCodeInt(t *testing.T) {
+	raw := `{"errorType":"status_code","errorCode":404,"url":"https://example.com/{}"}`
+	var w Website
+	if err := json.Unmarshal([]byte(raw), &w); err != nil {
+		t.Fatalf("unmarshal failed: %v", err)
+	}
+	want := []int{404}
+	if !reflect.DeepEqual(w.ErrorCodes, want) {
+		t.Fatalf("got %v, want %v", w.ErrorCodes, want)
+	}
+}
+
+func TestWebsiteUnmarshalErrorCodeArray(t *testing.T) {
+	raw := `{"errorType":"status_code","errorCode":[404,500],"url":"https://example.com/{}"}`
+	var w Website
+	if err := json.Unmarshal([]byte(raw), &w); err != nil {
+		t.Fatalf("unmarshal failed: %v", err)
+	}
+	want := []int{404, 500}
+	if !reflect.DeepEqual(w.ErrorCodes, want) {
+		t.Fatalf("got %v, want %v", w.ErrorCodes, want)
+	}
+}
EOF_114329324912
if [ -s "$TEST_PATCH_FILE" ]; then
  git apply -v "$TEST_PATCH_FILE"
fi
rm -f "$TEST_PATCH_FILE"

# If patch deletes files, ensure they are absent (none in this task)
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  rm -f "$f"
  if [ -e "$f" ]; then
    echo "ERROR: deleted-by-patch file still exists: $f" >&2
    exit 2
  fi
done

# Determine target packages from target test files (directory of each file)
mapfile -t TARGET_PKGS < <(
  for f in "${RUNNABLE_TEST_FILES[@]}"; do
    d="$(dirname "$f")"
    if [ "$d" = "." ]; then
      echo "."
    else
      echo "./$d"
    fi
  done | awk '!seen[$0]++'
)

# If no runnable targets, run regression suite (not expected here)
if [ "${#RUNNABLE_TEST_FILES[@]}" -eq 0 ]; then
  set +e
  go test -p 1 ./...
  rc=$?
  set -e
  echo "OMNIGRIL_EXIT_CODE=$rc"
  exit $rc
fi

# Run tests for target packages (serialize packages to avoid cross-package conflicts)
JSON_OUT="$(mktemp)"
set +e
go test -p 1 -json "${TARGET_PKGS[@]}" | tee "$JSON_OUT"
rc=${PIPESTATUS[0]}
set -e

# Summarize PASS/FAIL per runnable target test file.
# Normalize package names: strip module path prefix if present.
MODULE_PATH="$(go list -m -f '{{.Path}}' 2>/dev/null || true)"

normalize_pkg() {
  local p="$1"
  # strip module prefix if present
  if [ -n "$MODULE_PATH" ] && [[ "$p" == "$MODULE_PATH"* ]]; then
    p="${p#"$MODULE_PATH"}"
    p="${p#/}"
  fi
  # ensure relative form like ./dir or .
  if [ -z "$p" ] || [ "$p" = "." ]; then
    echo "."
    return
  fi
  if [[ "$p" == ./* ]]; then
    echo "$p"
    return
  fi
  echo "./$p"
}

# Build package result map from go test -json: last Package-level "pass"/"fail" wins.
declare -A PKG_STATUS=()
while IFS= read -r line; do
  # Extract Package and Action with minimal parsing (no jq dependency)
  pkg="$(printf '%s' "$line" | sed -n 's/.*"Package":"\([^"]*\)".*/\1/p')"
  act="$(printf '%s' "$line" | sed -n 's/.*"Action":"\([^"]*\)".*/\1/p')"
  if [ -n "$pkg" ] && { [ "$act" = "pass" ] || [ "$act" = "fail" ]; }; then
    npkg="$(normalize_pkg "$pkg")"
    PKG_STATUS["$npkg"]="$act"
  fi
done < "$JSON_OUT"
rm -f "$JSON_OUT"

# Print per-file status
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  d="$(dirname "$f")"
  if [ "$d" = "." ]; then
    pkg="."
  else
    pkg="./$d"
  fi
  st="${PKG_STATUS[$pkg]:-unknown}"
  case "$st" in
    pass) echo "$f PASS" ;;
    fail) echo "$f FAIL" ;;
    *)    echo "$f UNKNOWN" ;;
  esac
done

echo "OMNIGRIL_EXIT_CODE=$rc"

# Cleanup: restore runnable targets to base state (or remove if they didn't exist in base)
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${BASE_SHA}:$f" 2>/dev/null; then
    git checkout "${BASE_SHA}" -- "$f"
  else
    rm -f "$f"
  fi
done

exit $rc
