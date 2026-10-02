#!/bin/bash
set -uxo pipefail

cd /testbed
# Keep local test servers from being routed through host proxy settings.
export NO_PROXY="localhost,127.0.0.1,0.0.0.0,::1${NO_PROXY:+,$NO_PROXY}"
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1${no_proxy:+,$no_proxy}"
echo "OMNIGRIL_LOCAL_NO_PROXY_ADDED=1"


COMMIT_SHA="2a1409fe88d416cc85fc96fb5bc473f83ed5a054"

RUNNABLE_TEST_FILES=(
  api/queries_pr_test.go
  internal/safeurl/safeurl_test.go
  internal/skills/discovery/discovery_test.go
  pkg/cmd/attestation/api/attestation.go
  pkg/cmd/attestation/api/client.go
  pkg/cmd/attestation/api/client_test.go
  pkg/cmd/codespace/create_test.go
  pkg/cmd/codespace/list_test.go
  pkg/cmd/copilot/copilot_test.go
  pkg/cmd/gist/shared/shared_test.go
  pkg/cmd/pr/close/close_test.go
  pkg/cmd/pr/merge/merge_test.go
  pkg/cmd/release/delete/delete_test.go
  pkg/cmd/release/shared/fetch_test.go
  pkg/cmd/release/shared/upload_test.go
  pkg/cmd/repo/read-file/read_file_test.go
  pkg/cmd/repo/sync/sync_test.go
  pkg/cmd/run/download/download_test.go
  pkg/cmd/run/download/http_test.go
  pkg/cmd/secret/list/list_test.go
  pkg/cmd/skills/install/install_test.go
  pkg/cmd/skills/preview/preview_test.go
  pkg/cmd/skills/update/update_test.go
  pkg/cmd/variable/list/list_test.go
  pkg/cmd/workflow/run/run_test.go
  pkg/cmd/workflow/view/view_test.go
)

DELETED_TEST_PATCH_FILES=()

# --- Pre-patch cleanup: restore files that exist in base commit; remove ones that don't (newly added by patch) ---
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${COMMIT_SHA}:$f" 2>/dev/null; then
    git checkout "${COMMIT_SHA}" -- "$f"
  else
    rm -f "$f"
  fi
done

# --- Apply test patch (content injected by harness) ---
TEST_PATCH_FILE="$(mktemp)"
cat > "$TEST_PATCH_FILE" <<'EOF_114329324912'
diff --git a/api/queries_pr_test.go b/api/queries_pr_test.go
--- a/api/queries_pr_test.go
+++ b/api/queries_pr_test.go
@@ -23,7 +23,7 @@ func TestBranchDeleteRemote(t *testing.T) {
 			branch: "owner/branch#123",
 			httpStubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/owner%2Fbranch%23123"),
+					httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Fowner%2Fbranch%23123"),
 					httpmock.StatusStringResponse(204, ""))
 			},
 			expectError: false,
@@ -33,7 +33,7 @@ func TestBranchDeleteRemote(t *testing.T) {
 			branch: "my-branch",
 			httpStubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/my-branch"),
+					httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Fmy-branch"),
 					httpmock.StatusStringResponse(500, `{"message": "oh no"}`))
 			},
 			expectError: true,
diff --git a/internal/safeurl/safeurl_test.go b/internal/safeurl/safeurl_test.go
new file mode 100644
--- /dev/null
+++ b/internal/safeurl/safeurl_test.go
@@ -0,0 +1,317 @@
+package safeurl_test
+
+import (
+	"testing"
+
+	"github.com/cli/cli/v2/internal/safeurl"
+	"github.com/stretchr/testify/require"
+)
+
+var _ safeurl.SafeURL = (*safeurl.MutableSafeURL)(nil)
+var _ safeurl.SafeURL = (*safeurl.ImmutableSafeURL)(nil)
+
+func TestRepoPartsFromNWO(t *testing.T) {
+
+	tests := []struct {
+		name      string
+		nwo       string
+		wantOwner string
+		wantName  string
+		wantErr   bool
+	}{
+		{
+			name:      "owner and repo",
+			nwo:       "octocat/hello-world",
+			wantOwner: "octocat",
+			wantName:  "hello-world",
+		},
+		{
+			name:    "no separator",
+			nwo:     "octocat",
+			wantErr: true,
+		},
+		{
+			name:    "empty",
+			nwo:     "",
+			wantErr: true,
+		},
+		{
+			name:    "missing name",
+			nwo:     "octocat/",
+			wantErr: true,
+		},
+		{
+			name:    "missing owner",
+			nwo:     "/hello-world",
+			wantErr: true,
+		},
+		{
+			name:      "parts are returned unescaped",
+			nwo:       "my owner/my repo",
+			wantOwner: "my owner",
+			wantName:  "my repo",
+		},
+		{
+			name:    "extra separators are rejected",
+			nwo:     "foo/bar/codespaces",
+			wantErr: true,
+		},
+	}
+	for _, tt := range tests {
+		t.Run(tt.name, func(t *testing.T) {
+
+			owner, name, err := safeurl.RepoPartsFromNWO(tt.nwo)
+			if tt.wantErr {
+				require.Error(t, err)
+			} else {
+				require.NoError(t, err)
+				require.Equal(t, tt.wantOwner, owner)
+				require.Equal(t, tt.wantName, name)
+			}
+		})
+	}
+}
+
+func TestJoinPathRejectsTraversal(t *testing.T) {
+	tests := []struct {
+		name       string
+		components []string
+	}{
+		{
+			name:       "only a .. component",
+			components: []string{".."},
+		},
+		{
+			name:       "a .. component in the middle",
+			components: []string{"repos", "octocat", "..", "hello-world"},
+		},
+	}
+	for _, tt := range tests {
+		t.Run(tt.name, func(t *testing.T) {
+			_, errJoinPath := safeurl.JoinPath(tt.components...)
+			require.Error(t, errJoinPath)
+			_, errJoinPathWithHostPrefix := safeurl.JoinPathWithHostPrefix("https://api.github.com", tt.components...)
+			require.Error(t, errJoinPathWithHostPrefix)
+		})
+	}
+}
+
+func TestMutableSafeURLString(t *testing.T) {
+	tests := []struct {
+		name string
+		url  func(t *testing.T) (*safeurl.MutableSafeURL, error)
+		want string
+	}{
+		{
+			name: "zero value renders empty",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return &safeurl.MutableSafeURL{}, nil
+			},
+			want: "",
+		},
+		{
+			name: "path only",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPath("foo", "bar", "baz")
+			},
+			want: "foo/bar/baz",
+		},
+		{
+			name: "single path component",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPath("foo")
+			},
+			want: "foo",
+		},
+		{
+			name: "empty components produce empty segments",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPath("", "bar", "")
+			},
+			want: "/bar/",
+		},
+		{
+			name: "escapes path components",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPath("foo", "bar baz", "a/b")
+			},
+			want: "foo/bar%20baz/a%2Fb",
+		},
+		{
+			name: "pre-encoded dot-dot cannot bypass the traversal check",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPath("foo", "bar", "%2e%2e", "baz")
+			},
+			want: "foo/bar/%252e%252e/baz",
+		},
+		{
+			name: "single dot component is preserved verbatim",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPath("foo", "bar", ".", "baz")
+			},
+			want: "foo/bar/./baz",
+		},
+		{
+			name: "leading single dot components are preserved verbatim",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPath(".", ".", "foo", "bar")
+			},
+			want: "././foo/bar",
+		},
+		{
+			name: "pre-encoded dot-dot cannot bypass the traversal check with host prefix",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPathWithHostPrefix("https://host", "foo", "bar", "%2e%2e", "baz")
+			},
+			want: "https://host/foo/bar/%252e%252e/baz",
+		},
+		{
+			name: "single dot component is preserved verbatim with host prefix",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPathWithHostPrefix("https://host", "foo", "bar", ".", "baz")
+			},
+			want: "https://host/foo/bar/./baz",
+		},
+		{
+			name: "leading single dot components are preserved verbatim with host prefix",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPathWithHostPrefix("https://host", ".", ".", "foo", "bar")
+			},
+			want: "https://host/././foo/bar",
+		},
+		{
+			name: "host prefix and path",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPathWithHostPrefix("https://host", "foo", "bar", "baz")
+			},
+			want: "https://host/foo/bar/baz",
+		},
+		{
+			name: "host prefix remains intact",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPathWithHostPrefix("https://host/with/slash", "foo", "bar", "baz")
+			},
+			want: "https://host/with/slash/foo/bar/baz",
+		},
+		{
+			name: "host prefix with trailing slash",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPathWithHostPrefix("https://host/", "foo", "bar", "baz")
+			},
+			want: "https://host/foo/bar/baz",
+		},
+		{
+			name: "host prefix without path",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPathWithHostPrefix("https://host")
+			},
+			want: "https://host",
+		},
+		{
+			name: "host prefix with trailing slash and no path",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				return safeurl.JoinPathWithHostPrefix("https://host/")
+			},
+			want: "https://host/",
+		},
+		{
+			name: "query only",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				u := &safeurl.MutableSafeURL{}
+				u.SetQuery("page", "2")
+				return u, nil
+			},
+			want: "?page=2",
+		},
+		{
+			name: "path and query",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				u, err := safeurl.JoinPath("foo", "bar", "baz")
+				require.NoError(t, err)
+				u.SetQuery("value", "x")
+				return u, nil
+			},
+			want: "foo/bar/baz?value=x",
+		},
+		{
+			name: "host prefix, path, and query",
+			url: func(t *testing.T) (*safeurl.MutableSafeURL, error) {
+				u, err := safeurl.JoinPathWithHostPrefix("https://host", "foo", "bar")
+				require.NoError(t, err)
+				u.SetQuery("value", "x y")
+				return u, nil
+			},
+			want: "https://host/foo/bar?value=x+y",
+		},
+	}
+	for _, tt := range tests {
+		t.Run(tt.name, func(t *testing.T) {
+			u, err := tt.url(t)
+			require.NoError(t, err)
+			require.Equal(t, tt.want, u.String())
+		})
+	}
+}
+
+func TestMutableSafeURLSetQuery(t *testing.T) {
+	type query struct {
+		key   string
+		value string
+	}
+
+	tests := []struct {
+		name    string
+		queries []query
+		want    string
+	}{
+		{
+			name:    "replaces existing value rather than appending",
+			queries: []query{{"a", "1"}, {"a", "2"}},
+			want:    "foo/bar?a=2",
+		},
+		{
+			name:    "sorts keys deterministically",
+			queries: []query{{"b", "2"}, {"a", "1"}},
+			want:    "foo/bar?a=1&b=2",
+		},
+		{
+			name:    "escapes keys and values",
+			queries: []query{{"a", "x y&z"}},
+			want:    "foo/bar?a=x+y%26z",
+		},
+	}
+	for _, tt := range tests {
+		t.Run(tt.name, func(t *testing.T) {
+			u, err := safeurl.JoinPath("foo", "bar")
+			require.NoError(t, err)
+			for _, q := range tt.queries {
+				u.SetQuery(q.key, q.value)
+			}
+			require.Equal(t, tt.want, u.String())
+		})
+	}
+}
+
+func TestImmutableSafeURLString(t *testing.T) {
+	tests := []struct {
+		name string
+		url  string
+		want string
+	}{
+		{
+			name: "empty renders empty",
+			url:  "",
+			want: "",
+		},
+		{
+			name: "renders the wrapped url verbatim without encoding",
+			url:  "https://host/foo/bar baz/?value=x y",
+			want: "https://host/foo/bar baz/?value=x y",
+		},
+	}
+	for _, tt := range tests {
+		t.Run(tt.name, func(t *testing.T) {
+			require.Equal(t, tt.want, safeurl.NewImmutableSafeURL(tt.url).String())
+		})
+	}
+}
diff --git a/internal/skills/discovery/discovery_test.go b/internal/skills/discovery/discovery_test.go
--- a/internal/skills/discovery/discovery_test.go
+++ b/internal/skills/discovery/discovery_test.go
@@ -431,7 +431,7 @@ func TestResolveRef(t *testing.T) {
 			version: "main",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/main"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fmain"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "branch-sha"},
 					}))
@@ -444,10 +444,10 @@ func TestResolveRef(t *testing.T) {
 			version: "v1.0",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/v1.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fv1.0"),
 					httpmock.StatusStringResponse(404, "not found"))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v1.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv1.0"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "abc123", "type": "commit"},
 					}))
@@ -460,10 +460,10 @@ func TestResolveRef(t *testing.T) {
 			version: "v2.0",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/v2.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fv2.0"),
 					httpmock.StatusStringResponse(404, "not found"))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v2.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv2.0"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "tag-obj-sha", "type": "tag"},
 					}))
@@ -481,10 +481,10 @@ func TestResolveRef(t *testing.T) {
 			version: "deadbeef",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/deadbeef"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fdeadbeef"),
 					httpmock.StatusStringResponse(404, "not found"))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/deadbeef"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fdeadbeef"),
 					httpmock.StatusStringResponse(404, "not found"))
 				reg.Register(
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/commits/deadbeef"),
@@ -498,10 +498,10 @@ func TestResolveRef(t *testing.T) {
 			version: "nonexistent",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/nonexistent"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fnonexistent"),
 					httpmock.StatusStringResponse(404, "not found"))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/nonexistent"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fnonexistent"),
 					httpmock.StatusStringResponse(404, "not found"))
 				reg.Register(
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/commits/nonexistent"),
@@ -514,7 +514,7 @@ func TestResolveRef(t *testing.T) {
 			version: "release",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/release"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Frelease"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "branch-sha"},
 					}))
@@ -528,7 +528,7 @@ func TestResolveRef(t *testing.T) {
 			version: "refs/tags/v1.0",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v1.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv1.0"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "tag-sha", "type": "commit"},
 					}))
@@ -541,7 +541,7 @@ func TestResolveRef(t *testing.T) {
 			version: "refs/heads/feature",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/feature"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Ffeature"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "feature-sha"},
 					}))
@@ -554,7 +554,7 @@ func TestResolveRef(t *testing.T) {
 			version: "refs/tags/nonexistent",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/nonexistent"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fnonexistent"),
 					httpmock.StatusStringResponse(404, "not found"))
 			},
 			wantErr: `tag "nonexistent" not found in monalisa/octocat-skills`,
@@ -564,7 +564,7 @@ func TestResolveRef(t *testing.T) {
 			version: "refs/heads/nonexistent",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/nonexistent"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fnonexistent"),
 					httpmock.StatusStringResponse(404, "not found"))
 			},
 			wantErr: `branch "nonexistent" not found in monalisa/octocat-skills`,
@@ -576,7 +576,7 @@ func TestResolveRef(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/releases/latest"),
 					httpmock.JSONResponse(map[string]interface{}{"tag_name": "v3.0"}))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v3.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv3.0"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "release-sha", "type": "commit"},
 					}))
@@ -594,7 +594,7 @@ func TestResolveRef(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills"),
 					httpmock.JSONResponse(map[string]interface{}{"default_branch": "main"}))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/main"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fmain"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "branch-sha"},
 					}))
@@ -607,7 +607,7 @@ func TestResolveRef(t *testing.T) {
 			version: "refs/tags/v4.0",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v4.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv4.0"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "tag-obj-sha", "type": "tag"},
 					}))
@@ -645,7 +645,7 @@ func TestResolveRef(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills"),
 					httpmock.JSONResponse(map[string]interface{}{"default_branch": "main"}))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/main"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fmain"),
 					httpmock.JSONResponse(map[string]interface{}{
 						"object": map[string]interface{}{"sha": "fallback-sha"},
 					}))
@@ -670,7 +670,7 @@ func TestResolveRef(t *testing.T) {
 			version: "main",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/main"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fmain"),
 					httpmock.StatusStringResponse(500, "server error"))
 			},
 			wantErr: `branch "main" not found in monalisa/octocat-skills`,
@@ -680,7 +680,7 @@ func TestResolveRef(t *testing.T) {
 			version: "develop",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/develop"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fdevelop"),
 					httpmock.StatusStringResponse(403, "forbidden"))
 			},
 			wantErr: `branch "develop" not found in monalisa/octocat-skills`,
@@ -690,10 +690,10 @@ func TestResolveRef(t *testing.T) {
 			version: "v5.0",
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads/v5.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/heads%2Fv5.0"),
 					httpmock.StatusStringResponse(404, "not found"))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v5.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv5.0"),
 					httpmock.StatusStringResponse(500, "server error"))
 			},
 			wantErr: `tag "v5.0" not found in monalisa/octocat-skills`,
diff --git a/pkg/cmd/attestation/api/attestation.go b/pkg/cmd/attestation/api/attestation.go
--- a/pkg/cmd/attestation/api/attestation.go
+++ b/pkg/cmd/attestation/api/attestation.go
@@ -8,11 +8,6 @@ import (
 	"github.com/sigstore/sigstore-go/pkg/bundle"
 )
 
-const (
-	GetAttestationByRepoAndSubjectDigestPath  = "repos/%s/attestations/%s"
-	GetAttestationByOwnerAndSubjectDigestPath = "orgs/%s/attestations/%s"
-)
-
 var ErrNoAttestationsFound = errors.New("no attestations found")
 
 type Attestation struct {
diff --git a/pkg/cmd/attestation/api/client.go b/pkg/cmd/attestation/api/client.go
--- a/pkg/cmd/attestation/api/client.go
+++ b/pkg/cmd/attestation/api/client.go
@@ -5,12 +5,13 @@ import (
 	"fmt"
 	"io"
 	"net/http"
-	neturl "net/url"
+	"strconv"
 	"strings"
 	"time"
 
 	"github.com/cenkalti/backoff/v4"
 	"github.com/cli/cli/v2/api"
+	"github.com/cli/cli/v2/internal/safeurl"
 	ioconfig "github.com/cli/cli/v2/pkg/cmd/attestation/io"
 	"github.com/klauspost/compress/snappy"
 	v1 "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
@@ -100,18 +101,29 @@ func (c *LiveClient) GetByDigest(params FetchParams) ([]*Attestation, error) {
 	return bundles, nil
 }
 
-func (c *LiveClient) buildRequestURL(params FetchParams) (string, error) {
+func (c *LiveClient) buildRequestURL(params FetchParams) (safeurl.SafeURL, error) {
 	if err := params.Validate(); err != nil {
-		return "", err
+		return nil, err
 	}
 
-	var url string
+	var u *safeurl.MutableSafeURL
 	if params.Repo != "" {
 		// check if Repo is set first because if Repo has been set, Owner will be set using the value of Repo.
 		// If Repo is not set, the field will remain empty. It will not be populated using the value of Owner.
-		url = fmt.Sprintf(GetAttestationByRepoAndSubjectDigestPath, params.Repo, params.Digest)
+		owner, name, err := safeurl.RepoPartsFromNWO(params.Repo)
+		if err != nil {
+			return nil, err
+		}
+		u, err = safeurl.JoinPath("repos", owner, name, "attestations", params.Digest)
+		if err != nil {
+			return nil, err
+		}
 	} else {
-		url = fmt.Sprintf(GetAttestationByOwnerAndSubjectDigestPath, params.Owner, params.Digest)
+		var err error
+		u, err = safeurl.JoinPath("orgs", params.Owner, "attestations", params.Digest)
+		if err != nil {
+			return nil, err
+		}
 	}
 
 	perPage := params.Limit
@@ -120,15 +132,15 @@ func (c *LiveClient) buildRequestURL(params FetchParams) (string, error) {
 	}
 
 	// ref: https://github.com/cli/go-gh/blob/d32c104a9a25c9de3d7c7b07a43ae0091441c858/example_gh_test.go#L96
-	url = fmt.Sprintf("%s?per_page=%d", url, perPage)
+	u.SetQuery("per_page", strconv.Itoa(perPage))
 	if params.PredicateType != "" {
-		url = fmt.Sprintf("%s&predicate_type=%s", url, neturl.QueryEscape(params.PredicateType))
+		u.SetQuery("predicate_type", params.PredicateType)
 	}
-	return url, nil
+	return u, nil
 }
 
 func (c *LiveClient) getAttestations(params FetchParams) ([]*Attestation, error) {
-	url, err := c.buildRequestURL(params)
+	u, err := c.buildRequestURL(params)
 	if err != nil {
 		return nil, err
 	}
@@ -137,18 +149,20 @@ func (c *LiveClient) getAttestations(params FetchParams) ([]*Attestation, error)
 	var resp AttestationsResponse
 	bo := backoff.NewConstantBackOff(getAttestationRetryInterval)
 
+	var pageURL safeurl.SafeURL = u
+
 	// if no attestation or less than limit, then keep fetching
-	for url != "" && len(attestations) < params.Limit {
+	for pageURL.String() != "" && len(attestations) < params.Limit {
 		err := backoff.Retry(func() error {
-			newURL, restErr := c.githubAPI.RESTWithNext(c.host, http.MethodGet, url, nil, &resp)
+			newURL, restErr := c.githubAPI.RESTWithNext(c.host, http.MethodGet, pageURL.String(), nil, &resp)
 			if restErr != nil {
 				if shouldRetry(restErr) {
 					return restErr
 				}
 				return backoff.Permanent(restErr)
 			}
 
-			url = newURL
+			pageURL = safeurl.NewImmutableSafeURL(newURL)
 
 			// filter by the initiator type
 			if params.Initiator != "" {
@@ -201,7 +215,7 @@ func (c *LiveClient) fetchBundleFromAttestations(attestations []*Attestation) ([
 			}
 
 			// otherwise fetch the bundle with the provided URL
-			b, err := c.getBundle(a.BundleURL)
+			b, err := c.getBundle(safeurl.NewImmutableSafeURL(a.BundleURL))
 			if err != nil {
 				return fmt.Errorf("failed to fetch bundle with URL: %w", err)
 			}
@@ -220,19 +234,19 @@ func (c *LiveClient) fetchBundleFromAttestations(attestations []*Attestation) ([
 	return fetched, nil
 }
 
-func (c *LiveClient) getBundle(url string) (*bundle.Bundle, error) {
+func (c *LiveClient) getBundle(url safeurl.SafeURL) (*bundle.Bundle, error) {
 	c.logger.VerbosePrintf("Fetching attestation bundle with bundle URL\n\n")
 
 	var sgBundle *bundle.Bundle
 	bo := backoff.NewConstantBackOff(getAttestationRetryInterval)
 	err := backoff.Retry(func() error {
-		resp, err := c.externalHttpClient.Get(url)
+		resp, err := c.externalHttpClient.Get(url.String())
 		if err != nil {
 			return fmt.Errorf("request to fetch bundle from URL failed: %w", err)
 		}
 
 		if resp.StatusCode >= 500 && resp.StatusCode <= 599 {
-			return fmt.Errorf("attestation bundle with URL %s returned status code %d", url, resp.StatusCode)
+			return fmt.Errorf("attestation bundle with URL %s returned status code %d", url.String(), resp.StatusCode)
 		}
 
 		defer resp.Body.Close()
@@ -279,15 +293,19 @@ func shouldRetry(err error) bool {
 // GetTrustDomain returns the current trust domain. If the default is used
 // the empty string is returned
 func (c *LiveClient) GetTrustDomain() (string, error) {
-	return c.getTrustDomain(MetaPath)
+	u, err := safeurl.JoinPath(MetaPath)
+	if err != nil {
+		return "", err
+	}
+	return c.getTrustDomain(u)
 }
 
-func (c *LiveClient) getTrustDomain(url string) (string, error) {
+func (c *LiveClient) getTrustDomain(u safeurl.SafeURL) (string, error) {
 	var resp MetaResponse
 
 	bo := backoff.NewConstantBackOff(getAttestationRetryInterval)
 	err := backoff.Retry(func() error {
-		restErr := c.githubAPI.REST(c.host, http.MethodGet, url, nil, &resp)
+		restErr := c.githubAPI.REST(c.host, http.MethodGet, u.String(), nil, &resp)
 		if restErr != nil {
 			if shouldRetry(restErr) {
 				return restErr
diff --git a/pkg/cmd/attestation/api/client_test.go b/pkg/cmd/attestation/api/client_test.go
--- a/pkg/cmd/attestation/api/client_test.go
+++ b/pkg/cmd/attestation/api/client_test.go
@@ -3,6 +3,7 @@ package api
 import (
 	"testing"
 
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/attestation/io"
 	"github.com/cli/cli/v2/pkg/cmd/attestation/test/data"
 	"github.com/stretchr/testify/require"
@@ -261,7 +262,7 @@ func TestGetBundle(t *testing.T) {
 		logger:             io.NewTestHandler(),
 	}
 
-	b, err := c.getBundle("https://mybundleurl.com")
+	b, err := c.getBundle(safeurl.NewImmutableSafeURL("https://mybundleurl.com"))
 	require.NoError(t, err)
 	require.Equal(t, "application/vnd.dev.sigstore.bundle.v0.3+json", b.GetMediaType())
 	mockHTTPClient.AssertNumberOfCalls(t, "OnGetSuccess", 1)
@@ -280,7 +281,7 @@ func TestGetBundle_SuccessfulRetry(t *testing.T) {
 		logger:             io.NewTestHandler(),
 	}
 
-	b, err := c.getBundle("mybundleurl")
+	b, err := c.getBundle(safeurl.NewImmutableSafeURL("mybundleurl"))
 	require.NoError(t, err)
 	require.Equal(t, "application/vnd.dev.sigstore.bundle.v0.3+json", b.GetMediaType())
 	mockHTTPClient.AssertNumberOfCalls(t, "OnGetFailAfterNCalls", 2)
@@ -294,7 +295,7 @@ func TestGetBundle_PermanentBackoffFail(t *testing.T) {
 		logger:             io.NewTestHandler(),
 	}
 
-	b, err := c.getBundle("mybundleurl")
+	b, err := c.getBundle(safeurl.NewImmutableSafeURL("mybundleurl"))
 	// var permanent *backoff.PermanentError
 	//require.IsType(t, &backoff.PermanentError{}, err)
 	require.Error(t, err)
@@ -311,7 +312,7 @@ func TestGetBundle_RequestFail(t *testing.T) {
 		logger:             io.NewTestHandler(),
 	}
 
-	b, err := c.getBundle("mybundleurl")
+	b, err := c.getBundle(safeurl.NewImmutableSafeURL("mybundleurl"))
 	require.Error(t, err)
 	require.Nil(t, b)
 	mockHTTPClient.AssertNumberOfCalls(t, "OnGetReqFail", 4)
diff --git a/pkg/cmd/codespace/create_test.go b/pkg/cmd/codespace/create_test.go
--- a/pkg/cmd/codespace/create_test.go
+++ b/pkg/cmd/codespace/create_test.go
@@ -32,6 +32,11 @@ func TestCreateCmdFlagError(t *testing.T) {
 			args:     "--web --idle-timeout 30m",
 			wantsErr: fmt.Errorf("using --web with --display-name, --idle-timeout, or --retention-period is not supported"),
 		},
+		{
+			name:     "return error when --repo is not in owner/repo format",
+			args:     "--repo foo",
+			wantsErr: fmt.Errorf(`invalid value for --repo: expected the "OWNER/REPO" format, got "foo"`),
+		},
 	}
 
 	for _, tt := range tests {
diff --git a/pkg/cmd/codespace/list_test.go b/pkg/cmd/codespace/list_test.go
--- a/pkg/cmd/codespace/list_test.go
+++ b/pkg/cmd/codespace/list_test.go
@@ -35,6 +35,11 @@ func TestListCmdFlagError(t *testing.T) {
 			args:     "--limit -1",
 			wantsErr: fmt.Errorf("invalid limit: -1"),
 		},
+		{
+			name:     "list codespaces, --repo not in owner/repo format",
+			args:     "--repo foo",
+			wantsErr: fmt.Errorf(`invalid value for --repo: expected the "OWNER/REPO" format, got "foo"`),
+		},
 	}
 
 	for _, tt := range tests {
diff --git a/pkg/cmd/copilot/copilot_test.go b/pkg/cmd/copilot/copilot_test.go
--- a/pkg/cmd/copilot/copilot_test.go
+++ b/pkg/cmd/copilot/copilot_test.go
@@ -16,6 +16,7 @@ import (
 	"testing"
 
 	"github.com/cli/cli/v2/internal/gh/ghtelemetry"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/telemetry"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/httpmock"
@@ -341,7 +342,7 @@ func TestFetchExpectedChecksum(t *testing.T) {
 		)
 
 		client := &http.Client{Transport: reg}
-		checksum, err := fetchExpectedChecksum(client, "https://example.com/checksums", "copilot-linux-x64.tar.gz")
+		checksum, err := fetchExpectedChecksum(client, safeurl.NewImmutableSafeURL("https://example.com/checksums"), "copilot-linux-x64.tar.gz")
 		require.NoError(t, err, "unexpected error")
 		require.Equal(t, "abc123def456", checksum, "checksum mismatch")
 	})
@@ -355,7 +356,7 @@ func TestFetchExpectedChecksum(t *testing.T) {
 		)
 
 		client := &http.Client{Transport: reg}
-		_, err := fetchExpectedChecksum(client, "https://example.com/checksums", "copilot-win32-x64.zip")
+		_, err := fetchExpectedChecksum(client, safeurl.NewImmutableSafeURL("https://example.com/checksums"), "copilot-win32-x64.zip")
 		require.Error(t, err, "expected error for missing archive")
 		require.Equal(t, "checksum not found for copilot-win32-x64.zip", err.Error(), "unexpected error")
 	})
@@ -369,7 +370,7 @@ func TestFetchExpectedChecksum(t *testing.T) {
 		)
 
 		client := &http.Client{Transport: reg}
-		checksum, err := fetchExpectedChecksum(client, "https://example.com/checksums", "copilot-darwin-x64.tar.gz")
+		checksum, err := fetchExpectedChecksum(client, safeurl.NewImmutableSafeURL("https://example.com/checksums"), "copilot-darwin-x64.tar.gz")
 		require.NoError(t, err, "unexpected error")
 		require.Equal(t, "abc123", checksum, "checksum mismatch")
 	})
@@ -382,7 +383,7 @@ func TestFetchExpectedChecksum(t *testing.T) {
 		)
 
 		client := &http.Client{Transport: reg}
-		_, err := fetchExpectedChecksum(client, "https://example.com/checksums", "copilot-linux-x64.tar.gz")
+		_, err := fetchExpectedChecksum(client, safeurl.NewImmutableSafeURL("https://example.com/checksums"), "copilot-linux-x64.tar.gz")
 		require.Error(t, err, "expected error for HTTP 404")
 	})
 }
diff --git a/pkg/cmd/gist/shared/shared_test.go b/pkg/cmd/gist/shared/shared_test.go
--- a/pkg/cmd/gist/shared/shared_test.go
+++ b/pkg/cmd/gist/shared/shared_test.go
@@ -7,6 +7,7 @@ import (
 	"time"
 
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/httpmock"
 	"github.com/cli/cli/v2/pkg/iostreams"
 	"github.com/stretchr/testify/assert"
@@ -298,7 +299,7 @@ func TestGetRawGistFile(t *testing.T) {
 			)
 
 			client := &http.Client{Transport: reg}
-			result, err := GetRawGistFile(client, "https://gist.githubusercontent.com/raw-url")
+			result, err := GetRawGistFile(client, safeurl.NewImmutableSafeURL("https://gist.githubusercontent.com/raw-url"))
 
 			if tt.wantErr {
 				assert.Error(t, err)
diff --git a/pkg/cmd/pr/close/close_test.go b/pkg/cmd/pr/close/close_test.go
--- a/pkg/cmd/pr/close/close_test.go
+++ b/pkg/cmd/pr/close/close_test.go
@@ -157,7 +157,7 @@ func TestPrClose_deleteBranch_sameRepo(t *testing.T) {
 			}),
 	)
 	http.Register(
-		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/blueberries"),
+		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Fblueberries"),
 		httpmock.StringResponse(`{}`))
 
 	cs, cmdTeardown := run.Stub()
@@ -223,7 +223,7 @@ func TestPrClose_deleteBranch_sameBranch(t *testing.T) {
 			}),
 	)
 	http.Register(
-		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/trunk"),
+		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Ftrunk"),
 		httpmock.StringResponse(`{}`))
 
 	cs, cmdTeardown := run.Stub()
@@ -258,7 +258,7 @@ func TestPrClose_deleteBranch_notInGitRepo(t *testing.T) {
 			}),
 	)
 	http.Register(
-		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/trunk"),
+		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Ftrunk"),
 		httpmock.StringResponse(`{}`))
 
 	cs, cmdTeardown := run.Stub()
diff --git a/pkg/cmd/pr/merge/merge_test.go b/pkg/cmd/pr/merge/merge_test.go
--- a/pkg/cmd/pr/merge/merge_test.go
+++ b/pkg/cmd/pr/merge/merge_test.go
@@ -635,7 +635,7 @@ func TestPrMerge_deleteBranch(t *testing.T) {
 			assert.NotContains(t, input, "commitHeadline")
 		}))
 	http.Register(
-		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/blueberries"),
+		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Fblueberries"),
 		httpmock.StringResponse(`{}`))
 
 	cs, cmdTeardown := run.Stub()
@@ -701,7 +701,7 @@ func TestPrMerge_deleteBranch_apiError(t *testing.T) {
 				✓ Merged pull request OWNER/REPO#10 (Blueberries are a good fruit)
 				✓ Deleted local branch blueberries and switched to branch main
 			`),
-			wantErr: "failed to delete remote branch blueberries: HTTP 500: blah blah (https://api.github.com/repos/OWNER/REPO/git/refs/heads/blueberries)",
+			wantErr: "failed to delete remote branch blueberries: HTTP 500: blah blah (https://api.github.com/repos/OWNER/REPO/git/refs/heads%2Fblueberries)",
 		},
 	}
 
@@ -732,7 +732,7 @@ func TestPrMerge_deleteBranch_apiError(t *testing.T) {
 					assert.NotContains(t, input, "commitHeadline")
 				}))
 			http.Register(
-				httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/blueberries"),
+				httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Fblueberries"),
 				httpmock.JSONErrorResponse(tt.apiError.StatusCode, tt.apiError))
 
 			cs, cmdTeardown := run.Stub()
@@ -806,7 +806,7 @@ func TestPrMerge_deleteBranch_nonDefault(t *testing.T) {
 			assert.NotContains(t, input, "commitHeadline")
 		}))
 	http.Register(
-		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/blueberries"),
+		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Fblueberries"),
 		httpmock.StringResponse(`{}`))
 
 	cs, cmdTeardown := run.Stub()
@@ -905,7 +905,7 @@ func TestPrMerge_deleteBranch_checkoutNewBranch(t *testing.T) {
 			assert.NotContains(t, input, "commitHeadline")
 		}))
 	http.Register(
-		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/blueberries"),
+		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Fblueberries"),
 		httpmock.StringResponse(`{}`))
 
 	cs, cmdTeardown := run.Stub()
@@ -955,7 +955,7 @@ func TestPrMerge_deleteNonCurrentBranch(t *testing.T) {
 			assert.NotContains(t, input, "commitHeadline")
 		}))
 	http.Register(
-		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/blueberries"),
+		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Fblueberries"),
 		httpmock.StringResponse(`{}`))
 
 	cs, cmdTeardown := run.Stub()
@@ -1435,7 +1435,7 @@ func TestPRMergeTTY_withDeleteBranch(t *testing.T) {
 			assert.NotContains(t, input, "commitHeadline")
 		}))
 	http.Register(
-		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads/blueberries"),
+		httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/heads%2Fblueberries"),
 		httpmock.StringResponse(`{}`))
 
 	cs, cmdTeardown := run.Stub()
diff --git a/pkg/cmd/release/delete/delete_test.go b/pkg/cmd/release/delete/delete_test.go
--- a/pkg/cmd/release/delete/delete_test.go
+++ b/pkg/cmd/release/delete/delete_test.go
@@ -210,7 +210,7 @@ func Test_deleteRun(t *testing.T) {
 			}`)
 
 			fakeHTTP.Register(httpmock.REST("DELETE", "repos/OWNER/REPO/releases/23456"), httpmock.StatusStringResponse(204, ""))
-			fakeHTTP.Register(httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/tags/v1.2.3"), httpmock.StatusStringResponse(204, ""))
+			fakeHTTP.Register(httpmock.REST("DELETE", "repos/OWNER/REPO/git/refs/tags%2Fv1.2.3"), httpmock.StatusStringResponse(204, ""))
 
 			rs, teardown := run.Stub()
 			defer teardown(t)
diff --git a/pkg/cmd/release/shared/fetch_test.go b/pkg/cmd/release/shared/fetch_test.go
--- a/pkg/cmd/release/shared/fetch_test.go
+++ b/pkg/cmd/release/shared/fetch_test.go
@@ -42,7 +42,7 @@ func TestFetchRefSHA(t *testing.T) {
 			tagName:         "v1.2.3",
 			responseStatus:  500,
 			responseMessage: `arbitrary error"`,
-			errorMessage:    "HTTP 500: arbitrary error\" (https://api.github.com/repos/owner/repo/git/ref/tags/v1.2.3)",
+			errorMessage:    "HTTP 500: arbitrary error\" (https://api.github.com/repos/owner/repo/git/ref/tags%2Fv1.2.3)",
 		},
 		{
 			name:           "malformed JSON with 200",
@@ -61,7 +61,7 @@ func TestFetchRefSHA(t *testing.T) {
 			repo, err := ghrepo.FromFullName("owner/repo")
 			require.NoError(t, err)
 
-			path := "repos/owner/repo/git/ref/tags/" + tt.tagName
+			path := "repos/owner/repo/git/ref/tags%2F" + tt.tagName
 			if tt.responseStatus == 404 || tt.responseStatus == 500 {
 				fakeHTTP.Register(
 					httpmock.REST("GET", path),
diff --git a/pkg/cmd/release/shared/upload_test.go b/pkg/cmd/release/shared/upload_test.go
--- a/pkg/cmd/release/shared/upload_test.go
+++ b/pkg/cmd/release/shared/upload_test.go
@@ -7,6 +7,8 @@ import (
 	"io"
 	"net/http"
 	"testing"
+
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 func Test_typeForFilename(t *testing.T) {
@@ -97,7 +99,7 @@ func Test_uploadWithDelete_retry(t *testing.T) {
 			Body:       io.NopCloser(bytes.NewBufferString(`{}`)),
 		}, nil
 	})
-	err := uploadWithDelete(ctx, client, "http://example.com/upload", AssetForUpload{
+	err := uploadWithDelete(ctx, client, safeurl.NewImmutableSafeURL("http://example.com/upload"), AssetForUpload{
 		Name:  "asset",
 		Label: "",
 		Size:  8,
diff --git a/pkg/cmd/repo/read-file/read_file_test.go b/pkg/cmd/repo/read-file/read_file_test.go
--- a/pkg/cmd/repo/read-file/read_file_test.go
+++ b/pkg/cmd/repo/read-file/read_file_test.go
@@ -751,8 +751,9 @@ func Test_contentsAPIPath(t *testing.T) {
 
 	for _, tt := range tests {
 		t.Run(tt.name, func(t *testing.T) {
-			got := contentsAPIPath(repo, tt.filePath, tt.ref)
-			assert.Equal(t, tt.want, got)
+			got, err := contentsAPIPath(repo, tt.filePath, tt.ref)
+			require.NoError(t, err)
+			assert.Equal(t, tt.want, got.String())
 		})
 	}
 }
diff --git a/pkg/cmd/repo/sync/sync_test.go b/pkg/cmd/repo/sync/sync_test.go
--- a/pkg/cmd/repo/sync/sync_test.go
+++ b/pkg/cmd/repo/sync/sync_test.go
@@ -306,10 +306,10 @@ func Test_SyncRun(t *testing.T) {
 					httpmock.REST("POST", "repos/FORKOWNER/REPO-FORK/merge-upstream"),
 					httpmock.StatusStringResponse(422, `{}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/git/refs/heads/trunk"),
+					httpmock.REST("GET", "repos/OWNER/REPO/git/refs/heads%2Ftrunk"),
 					httpmock.StringResponse(`{"object":{"sha":"0xDEADBEEF"}}`))
 				reg.Register(
-					httpmock.REST("PATCH", "repos/FORKOWNER/REPO-FORK/git/refs/heads/trunk"),
+					httpmock.REST("PATCH", "repos/FORKOWNER/REPO-FORK/git/refs/heads%2Ftrunk"),
 					httpmock.StringResponse(`{}`))
 			},
 			wantStdout: "✓ Synced the \"FORKOWNER:trunk\" branch from \"OWNER:trunk\"\n",
@@ -395,10 +395,10 @@ func Test_SyncRun(t *testing.T) {
 					httpmock.REST("POST", "repos/OWNER/REPO-FORK/merge-upstream"),
 					httpmock.StatusStringResponse(409, `{"message": "Merge conflict"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/git/refs/heads/trunk"),
+					httpmock.REST("GET", "repos/OWNER/REPO/git/refs/heads%2Ftrunk"),
 					httpmock.StringResponse(`{"object":{"sha":"0xDEADBEEF"}}`))
 				reg.Register(
-					httpmock.REST("PATCH", "repos/OWNER/REPO-FORK/git/refs/heads/trunk"),
+					httpmock.REST("PATCH", "repos/OWNER/REPO-FORK/git/refs/heads%2Ftrunk"),
 					httpmock.StringResponse(`{}`))
 			},
 			wantStdout: "✓ Synced the \"OWNER:trunk\" branch from \"OWNER:trunk\"\n",
@@ -420,10 +420,10 @@ func Test_SyncRun(t *testing.T) {
 					httpmock.REST("POST", "repos/OWNER/REPO-FORK/merge-upstream"),
 					httpmock.StatusStringResponse(409, `{"message": "Merge conflict"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/git/refs/heads/trunk"),
+					httpmock.REST("GET", "repos/OWNER/REPO/git/refs/heads%2Ftrunk"),
 					httpmock.StringResponse(`{"object":{"sha":"0xDEADBEEF"}}`))
 				reg.Register(
-					httpmock.REST("PATCH", "repos/OWNER/REPO-FORK/git/refs/heads/trunk"),
+					httpmock.REST("PATCH", "repos/OWNER/REPO-FORK/git/refs/heads%2Ftrunk"),
 					func(req *http.Request) (*http.Response, error) {
 						return &http.Response{
 							StatusCode: 422,
@@ -453,10 +453,10 @@ func Test_SyncRun(t *testing.T) {
 					httpmock.REST("POST", "repos/OWNER/REPO-FORK/merge-upstream"),
 					httpmock.StatusStringResponse(409, `{"message": "Merge conflict"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/git/refs/heads/trunk"),
+					httpmock.REST("GET", "repos/OWNER/REPO/git/refs/heads%2Ftrunk"),
 					httpmock.StringResponse(`{"object":{"sha":"0xDEADBEEF"}}`))
 				reg.Register(
-					httpmock.REST("PATCH", "repos/OWNER/REPO-FORK/git/refs/heads/trunk"),
+					httpmock.REST("PATCH", "repos/OWNER/REPO-FORK/git/refs/heads%2Ftrunk"),
 					func(req *http.Request) (*http.Response, error) {
 						return &http.Response{
 							StatusCode: 422,
diff --git a/pkg/cmd/run/download/download_test.go b/pkg/cmd/run/download/download_test.go
--- a/pkg/cmd/run/download/download_test.go
+++ b/pkg/cmd/run/download/download_test.go
@@ -13,6 +13,7 @@ import (
 	"github.com/cli/cli/v2/internal/ghrepo"
 	"github.com/cli/cli/v2/internal/prompter"
 	"github.com/cli/cli/v2/internal/safepaths"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/run/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -186,7 +187,7 @@ func (f *fakePlatform) List(runID string) ([]shared.Artifact, error) {
 	return artifacts, nil
 }
 
-func (f *fakePlatform) Download(url string, dir safepaths.Absolute) error {
+func (f *fakePlatform) Download(url safeurl.SafeURL, dir safepaths.Absolute) error {
 	if err := os.MkdirAll(dir.String(), 0755); err != nil {
 		return err
 	}
@@ -197,7 +198,7 @@ func (f *fakePlatform) Download(url string, dir safepaths.Absolute) error {
 	// Think fakePlatform { artifacts: ... } rather than fakePlatform.makeArtifactAvailable()
 	for _, run := range f.runs {
 		for _, testArtifact := range run.testArtifacts {
-			if testArtifact.artifact.DownloadURL == url {
+			if testArtifact.artifact.DownloadURL == url.String() {
 				for _, file := range testArtifact.files {
 					path := filepath.Join(dir.String(), file)
 					return os.WriteFile(path, []byte{}, 0600)
diff --git a/pkg/cmd/run/download/http_test.go b/pkg/cmd/run/download/http_test.go
--- a/pkg/cmd/run/download/http_test.go
+++ b/pkg/cmd/run/download/http_test.go
@@ -10,6 +10,7 @@ import (
 
 	"github.com/cli/cli/v2/internal/ghrepo"
 	"github.com/cli/cli/v2/internal/safepaths"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/httpmock"
 	"github.com/stretchr/testify/assert"
 	"github.com/stretchr/testify/require"
@@ -72,7 +73,7 @@ func Test_Download(t *testing.T) {
 	api := &apiPlatform{
 		client: &http.Client{Transport: reg},
 	}
-	require.NoError(t, api.Download("https://api.github.com/repos/OWNER/REPO/actions/artifacts/12345/zip", destDir))
+	require.NoError(t, api.Download(safeurl.NewImmutableSafeURL("https://api.github.com/repos/OWNER/REPO/actions/artifacts/12345/zip"), destDir))
 
 	var paths []string
 	parentPrefix := tmpDir + string(filepath.Separator)
diff --git a/pkg/cmd/secret/list/list_test.go b/pkg/cmd/secret/list/list_test.go
--- a/pkg/cmd/secret/list/list_test.go
+++ b/pkg/cmd/secret/list/list_test.go
@@ -16,6 +16,7 @@ import (
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/secret/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/httpmock"
@@ -857,7 +858,9 @@ func Test_getSecrets_pagination(t *testing.T) {
 		httpmock.StringResponse(`{"secrets":[{},{}]}`),
 	)
 	client := &http.Client{Transport: reg}
-	secrets, err := getSecrets(client, "github.com", "path/to")
+	u, err := safeurl.JoinPath("path", "to")
+	require.NoError(t, err)
+	secrets, err := getSecrets(client, "github.com", u)
 	assert.NoError(t, err)
 	assert.Equal(t, 4, len(secrets))
 }
diff --git a/pkg/cmd/skills/install/install_test.go b/pkg/cmd/skills/install/install_test.go
--- a/pkg/cmd/skills/install/install_test.go
+++ b/pkg/cmd/skills/install/install_test.go
@@ -221,7 +221,7 @@ func stubResolveVersion(reg *httpmock.Registry, owner, repo, tag, sha string) {
 		httpmock.StringResponse(fmt.Sprintf(`{"tag_name": %q}`, tag)),
 	)
 	reg.Register(
-		httpmock.REST("GET", fmt.Sprintf("repos/%s/%s/git/ref/tags/%s", owner, repo, tag)),
+		httpmock.REST("GET", fmt.Sprintf("repos/%s/%s/git/ref/tags%%2F%s", owner, repo, tag)),
 		httpmock.StringResponse(fmt.Sprintf(`{"object": {"sha": %q, "type": "commit"}}`, sha)),
 	)
 }
@@ -656,10 +656,10 @@ func TestInstallRun(t *testing.T) {
 			isTTY: true,
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/heads/v2.0.0"),
+					httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/heads%2Fv2.0.0"),
 					httpmock.StatusStringResponse(404, "not found"))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/tags/v2.0.0"),
+					httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/tags%2Fv2.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "def456", "type": "commit"}}`),
 				)
 				stubDiscoverTree(reg, "monalisa", "skills-repo", "def456",
@@ -766,10 +766,10 @@ func TestInstallRun(t *testing.T) {
 			isTTY: true,
 			stubs: func(reg *httpmock.Registry) {
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/heads/v1.2.0"),
+					httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/heads%2Fv1.2.0"),
 					httpmock.StatusStringResponse(404, "not found"))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/tags/v1.2.0"),
+					httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/tags%2Fv1.2.0"),
 					httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 				)
 				stubDiscoverTree(reg, "monalisa", "skills-repo", "abc123",
@@ -2716,7 +2716,7 @@ var republishedContent = heredoc.Doc(`
 func stubContentsAPI(reg *httpmock.Registry, owner, repo, path, content string) {
 	encoded := base64.StdEncoding.EncodeToString([]byte(content))
 	reg.Register(
-		httpmock.REST("GET", fmt.Sprintf("repos/%s/%s/contents/%s", owner, repo, path)),
+		httpmock.REST("GET", fmt.Sprintf("repos/%s/%s/contents/%s", owner, repo, url.PathEscape(path))),
 		httpmock.StringResponse(fmt.Sprintf(`{"content": %q, "encoding": "base64"}`, encoded)),
 	)
 }
diff --git a/pkg/cmd/skills/preview/preview_test.go b/pkg/cmd/skills/preview/preview_test.go
--- a/pkg/cmd/skills/preview/preview_test.go
+++ b/pkg/cmd/skills/preview/preview_test.go
@@ -142,7 +142,7 @@ func TestPreviewRun(t *testing.T) {
 					httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/github/awesome-copilot/git/ref/tags/v1.0.0"),
+					httpmock.REST("GET", "repos/github/awesome-copilot/git/ref/tags%2Fv1.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 				)
 				reg.Register(
@@ -185,7 +185,7 @@ func TestPreviewRun(t *testing.T) {
 					httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+					httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 				)
 				reg.Register(
@@ -229,7 +229,7 @@ func TestPreviewRun(t *testing.T) {
 					httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+					httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 				)
 				reg.Register(
@@ -274,7 +274,7 @@ func TestPreviewRun(t *testing.T) {
 					httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+					httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 				)
 				reg.Register(
@@ -311,7 +311,7 @@ func TestPreviewRun(t *testing.T) {
 					httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+					httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 				)
 				reg.Register(
@@ -340,7 +340,7 @@ func TestPreviewRun(t *testing.T) {
 					httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+					httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 				)
 				reg.Register(
@@ -368,11 +368,11 @@ func TestPreviewRun(t *testing.T) {
 			httpStubs: func(reg *httpmock.Registry) {
 				// ResolveRef with explicit version tries branch first, then tag, then commit
 				reg.Register(
-					httpmock.REST("GET", "repos/github/awesome-copilot/git/ref/heads/abc123def456"),
+					httpmock.REST("GET", "repos/github/awesome-copilot/git/ref/heads%2Fabc123def456"),
 					httpmock.StatusStringResponse(404, "not found"),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/github/awesome-copilot/git/ref/tags/abc123def456"),
+					httpmock.REST("GET", "repos/github/awesome-copilot/git/ref/tags%2Fabc123def456"),
 					httpmock.StatusStringResponse(404, "not found"),
 				)
 				reg.Register(
@@ -464,7 +464,7 @@ func TestPreviewRun_Interactive(t *testing.T) {
 		httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 	)
 	reg.Register(
-		httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+		httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 		httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 	)
 	reg.Register(
@@ -539,7 +539,7 @@ func TestPreviewRun_ShowsFileTree(t *testing.T) {
 			httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 		)
 		reg.Register(
-			httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+			httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 			httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 		)
 		reg.Register(
@@ -628,7 +628,7 @@ func TestPreviewRun_ShowsFileTree(t *testing.T) {
 			httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 		)
 		reg.Register(
-			httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+			httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 			httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 		)
 		reg.Register(
@@ -777,7 +777,7 @@ func TestPreviewRun_RenderLimits(t *testing.T) {
 			httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 		)
 		reg.Register(
-			httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/tags/v1.0.0"),
+			httpmock.REST("GET", "repos/monalisa/skills-repo/git/ref/tags%2Fv1.0.0"),
 			httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 		)
 		reg.Register(
@@ -916,7 +916,7 @@ func TestPreviewRun_InteractiveTelemetryCapturesSelectedSkillName(t *testing.T)
 		httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 	)
 	reg.Register(
-		httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+		httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 		httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 	)
 	reg.Register(
@@ -1028,7 +1028,7 @@ func TestPreviewRun_TelemetryVisibility(t *testing.T) {
 				httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 			)
 			reg.Register(
-				httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+				httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 				httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 			)
 			reg.Register(
@@ -1223,7 +1223,7 @@ func TestPreviewRun_HiddenDirSkillsExcluded(t *testing.T) {
 			httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 		)
 		reg.Register(
-			httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+			httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 			httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 		)
 		reg.Register(
@@ -1271,7 +1271,7 @@ func TestPreviewRun_HiddenDirSkillsExcluded(t *testing.T) {
 			httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 		)
 		reg.Register(
-			httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+			httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 			httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 		)
 		reg.Register(
@@ -1329,7 +1329,7 @@ func TestPreviewRun_HiddenDirSkillsExcluded(t *testing.T) {
 			httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 		)
 		reg.Register(
-			httpmock.REST("GET", "repos/owner/repo/git/ref/tags/v1.0.0"),
+			httpmock.REST("GET", "repos/owner/repo/git/ref/tags%2Fv1.0.0"),
 			httpmock.StringResponse(`{"object": {"sha": "abc123", "type": "commit"}}`),
 		)
 		reg.Register(
diff --git a/pkg/cmd/skills/update/update_test.go b/pkg/cmd/skills/update/update_test.go
--- a/pkg/cmd/skills/update/update_test.go
+++ b/pkg/cmd/skills/update/update_test.go
@@ -345,7 +345,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/releases/latest"),
 					httpmock.StringResponse(`{"tag_name": "v1.0.0"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v1.0.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv1.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "commit1", "type": "commit"}}`))
 				reg.Register(
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/trees/commit1"),
@@ -532,7 +532,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.StringResponse(`{"tag_name": "v1.0.0"}`),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v1.0.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv1.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "commitsha123", "type": "commit"}}`),
 				)
 				reg.Register(
@@ -576,7 +576,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.StringResponse(`{"tag_name": "v2.0.0"}`),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/hubot/octocat-skills/git/ref/tags/v2.0.0"),
+					httpmock.REST("GET", "repos/hubot/octocat-skills/git/ref/tags%2Fv2.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "newcommit456", "type": "commit"}}`),
 				)
 				reg.Register(
@@ -624,7 +624,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.StringResponse(`{"tag_name": "v2.0.0"}`),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/hubot/octocat-skills/git/ref/tags/v2.0.0"),
+					httpmock.REST("GET", "repos/hubot/octocat-skills/git/ref/tags%2Fv2.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "newcommit456", "type": "commit"}}`),
 				)
 				reg.Register(
@@ -672,7 +672,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/releases/latest"),
 					httpmock.StringResponse(`{"tag_name": "v3.0.0"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v3.0.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv3.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "newcommit789", "type": "commit"}}`))
 				reg.Register(
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/trees/newcommit789"),
@@ -735,7 +735,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/releases/latest"),
 					httpmock.StringResponse(`{"tag_name": "v3.0.0"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v3.0.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv3.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "newcommit789", "type": "commit"}}`))
 				reg.Register(
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/trees/newcommit789"),
@@ -806,7 +806,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/releases/latest"),
 					httpmock.StringResponse(`{"tag_name": "v3.0.0"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v3.0.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv3.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "newcommit789", "type": "commit"}}`))
 				reg.Register(
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/trees/newcommit789"),
@@ -865,7 +865,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/releases/latest"),
 					httpmock.StringResponse(`{"tag_name": "v3.0.0"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v3.0.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv3.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "newcommit789", "type": "commit"}}`))
 				reg.Register(
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/trees/newcommit789"),
@@ -927,7 +927,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/releases/latest"),
 					httpmock.StringResponse(`{"tag_name": "v3.0.0"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v3.0.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv3.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "newcommit789", "type": "commit"}}`))
 				reg.Register(
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/trees/newcommit789"),
@@ -1011,7 +1011,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/releases/latest"),
 					httpmock.StringResponse(`{"tag_name": "v1.0.0"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags/v1.0.0"),
+					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/ref/tags%2Fv1.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "commit123", "type": "commit"}}`))
 				reg.Register(
 					httpmock.REST("GET", "repos/monalisa/octocat-skills/git/trees/commit123"),
@@ -1081,7 +1081,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.REST("GET", "repos/octocat/hubot-skills/releases/latest"),
 					httpmock.StringResponse(`{"tag_name": "v2.0.0"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/octocat/hubot-skills/git/ref/tags/v2.0.0"),
+					httpmock.REST("GET", "repos/octocat/hubot-skills/git/ref/tags%2Fv2.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "newcommit789", "type": "commit"}}`))
 				reg.Register(
 					httpmock.REST("GET", "repos/octocat/hubot-skills/git/trees/newcommit789"),
@@ -1174,7 +1174,7 @@ func TestUpdateRun(t *testing.T) {
 					httpmock.REST("GET", "repos/octocat/hubot-skills/releases/latest"),
 					httpmock.StringResponse(`{"tag_name": "v2.0.0"}`))
 				reg.Register(
-					httpmock.REST("GET", "repos/octocat/hubot-skills/git/ref/tags/v2.0.0"),
+					httpmock.REST("GET", "repos/octocat/hubot-skills/git/ref/tags%2Fv2.0.0"),
 					httpmock.StringResponse(`{"object": {"sha": "newcommit789", "type": "commit"}}`))
 				reg.Register(
 					httpmock.REST("GET", "repos/octocat/hubot-skills/git/trees/newcommit789"),
diff --git a/pkg/cmd/variable/list/list_test.go b/pkg/cmd/variable/list/list_test.go
--- a/pkg/cmd/variable/list/list_test.go
+++ b/pkg/cmd/variable/list/list_test.go
@@ -12,6 +12,7 @@ import (
 	"github.com/cli/cli/v2/internal/config"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/variable/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/httpmock"
@@ -436,7 +437,9 @@ func Test_getVariables_pagination(t *testing.T) {
 		httpmock.StringResponse(`{"variables":[{},{}]}`),
 	)
 	client := &http.Client{Transport: reg}
-	variables, err := getVariables(client, "github.com", "path/to")
+	u, err := safeurl.JoinPath("path", "to")
+	require.NoError(t, err)
+	variables, err := getVariables(client, "github.com", u)
 	assert.NoError(t, err)
 	assert.Equal(t, 4, len(variables))
 }
diff --git a/pkg/cmd/workflow/run/run_test.go b/pkg/cmd/workflow/run/run_test.go
--- a/pkg/cmd/workflow/run/run_test.go
+++ b/pkg/cmd/workflow/run/run_test.go
@@ -764,7 +764,7 @@ jobs:
 						},
 					}))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/minimal.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fminimal.yml"),
 					httpmock.JSONResponse(struct{ Content string }{
 						Content: encodedNoInputsYAMLContent,
 					}))
@@ -808,7 +808,7 @@ jobs:
 						},
 					}))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/minimal.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fminimal.yml"),
 					httpmock.JSONResponse(struct{ Content string }{
 						Content: encodedNoInputsYAMLContent,
 					}))
@@ -861,7 +861,7 @@ jobs:
 						},
 					}))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/workflow.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fworkflow.yml"),
 					httpmock.JSONResponse(struct{ Content string }{
 						Content: encodedYAMLContent,
 					}))
@@ -914,7 +914,7 @@ jobs:
 						},
 					}))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/workflow.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fworkflow.yml"),
 					httpmock.JSONResponse(struct{ Content string }{
 						Content: encodedYAMLContent,
 					}))
@@ -976,7 +976,7 @@ jobs:
 						},
 					}))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/workflow.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fworkflow.yml"),
 					httpmock.JSONResponse(struct{ Content string }{
 						Content: encodedYAMLContentChoiceIp,
 					}))
@@ -1030,7 +1030,7 @@ jobs:
 						},
 					}))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/workflow.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fworkflow.yml"),
 					httpmock.JSONResponse(struct{ Content string }{
 						Content: encodedYAMLContentChoiceIp,
 					}))
@@ -1091,7 +1091,7 @@ jobs:
 						},
 					}))
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/workflow.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fworkflow.yml"),
 					httpmock.JSONResponse(struct{ Content string }{
 						Content: encodedYAMLContentMissingChoiceIp,
 					}))
diff --git a/pkg/cmd/workflow/view/view_test.go b/pkg/cmd/workflow/view/view_test.go
--- a/pkg/cmd/workflow/view/view_test.go
+++ b/pkg/cmd/workflow/view/view_test.go
@@ -289,7 +289,7 @@ func TestViewRun(t *testing.T) {
 					httpmock.JSONResponse(aWorkflow),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/flow.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fflow.yml"),
 					httpmock.StringResponse(aWorkflowContent),
 				)
 			},
@@ -308,7 +308,7 @@ func TestViewRun(t *testing.T) {
 					httpmock.JSONResponse(aWorkflow),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/flow.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fflow.yml"),
 					httpmock.StringResponse(aWorkflowContent),
 				)
 			},
@@ -327,7 +327,7 @@ func TestViewRun(t *testing.T) {
 					httpmock.JSONResponse(aWorkflow),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/flow.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fflow.yml"),
 					httpmock.StatusStringResponse(404, "not Found"),
 				)
 			},
@@ -348,7 +348,7 @@ func TestViewRun(t *testing.T) {
 					httpmock.JSONResponse(aWorkflow),
 				)
 				reg.Register(
-					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github/workflows/flow.yml"),
+					httpmock.REST("GET", "repos/OWNER/REPO/contents/.github%2Fworkflows%2Fflow.yml"),
 					httpmock.StringResponse(aWorkflowContent),
 				)
 			},
EOF_114329324912
if [ -s "$TEST_PATCH_FILE" ]; then
  git apply -v "$TEST_PATCH_FILE"
fi
rm -f "$TEST_PATCH_FILE"

# --- Handle deleted files from patch (none in this task, but keep logic) ---
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  rm -f "$f"
  if [ -e "$f" ]; then
    echo "ERROR: expected deleted path to be absent: $f" >&2
    exit 2
  fi
done

# --- Build list of target packages from runnable files (Go tests run by package) ---
TARGET_PKGS=()
declare -A SEEN_PKG=()
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  d="$(dirname "$f")"
  # Only run packages that actually exist after patch application
  if [ -d "$d" ]; then
    if [ -z "${SEEN_PKG[$d]+x}" ]; then
      TARGET_PKGS+=("./$d")
      SEEN_PKG["$d"]=1
    fi
  fi
done

# --- Run tests (avoid cross-package conflicts: -p 1). Capture JSON for per-package status. ---
rc=0
JSON_OUT="$(mktemp)"
set +e
if [ "${#TARGET_PKGS[@]}" -eq 0 ]; then
  # Fallback (shouldn't happen here): run a small regression command
  go test -p 1 ./... -json | tee "$JSON_OUT"
  rc=${PIPESTATUS[0]}
else
  go test -p 1 "${TARGET_PKGS[@]}" -json | tee "$JSON_OUT"
  rc=${PIPESTATUS[0]}
fi
set -e

# --- Summarize PASS/FAIL per runnable target file (normalize import paths to relative dirs) ---
MODULE_PATH="$(go list -m -f '{{.Path}}' 2>/dev/null || true)"

normalize_pkg() {
  local p="$1"
  p="${p#./}"
  if [ -n "$MODULE_PATH" ]; then
    p="${p#${MODULE_PATH}/}"
    p="${p#${MODULE_PATH}}"
  fi
  p="${p#/}"
  echo "$p"
}

declare -A PKG_STATUS=()
# Parse go test -json with one stream parser (no jq dependency required)
while IFS='|' read -r pkg action; do
  [ -n "$action" ] || continue
  [ -n "$pkg" ] || continue

  npkg="$(normalize_pkg "$pkg")"
  case "$action" in
    pass) PKG_STATUS["$npkg"]="PASS" ;;
    fail) PKG_STATUS["$npkg"]="FAIL" ;;
    skip) if [ -z "${PKG_STATUS[$npkg]+x}" ]; then PKG_STATUS["$npkg"]="SKIP"; fi ;;
  esac
done < <(
  sed -n     -e 's/.*"Package":"\([^"]*\)".*"Action":"\([^"]*\)".*/\1|\2/p'     -e 's/.*"Action":"\([^"]*\)".*"Package":"\([^"]*\)".*/\2|\1/p'     "$JSON_OUT"
)
rm -f "$JSON_OUT"

# Print per-file status keyed by file path
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  d="$(dirname "$f")"
  nd="$(normalize_pkg "$d")"
  st="${PKG_STATUS[$nd]:-UNKNOWN}"
  echo "TESTFILE $f $st"
done

echo "OMNIGRIL_EXIT_CODE=$rc"
set +e

# --- Cleanup: reset runnable files back to base commit state (or remove if not in base) ---
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${COMMIT_SHA}:$f" 2>/dev/null; then
    git checkout "${COMMIT_SHA}" -- "$f"
  else
    rm -f "$f"
  fi
done
exit $rc
