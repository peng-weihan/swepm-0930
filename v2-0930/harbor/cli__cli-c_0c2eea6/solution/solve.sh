#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.github/codeql/queries/ImmutableSafeURLConstruction.ql b/.github/codeql/queries/ImmutableSafeURLConstruction.ql
new file mode 100644
--- /dev/null
+++ b/.github/codeql/queries/ImmutableSafeURLConstruction.ql
@@ -0,0 +1,58 @@
+/**
+ * @name ImmutableSafeURL built from a hand-assembled string
+ * @description Flags a call to safeurl.NewImmutableSafeURL whose argument is a locally assembled
+ *              string, that is a value tainted by fmt.Sprintf, fmt.Sprint, fmt.Sprintln or a string
+ *              concatenation. NewImmutableSafeURL renders its argument verbatim, skipping the
+ *              percent-encoding and traversal check that JoinPath applies, so it must only receive an
+ *              already formed, trusted URL such as a server returned field or a pagination link. A
+ *              hand-built path reaching it is a way to route around safeurl and must instead be built
+ *              with safeurl.JoinPath. This query is a convention guard, it cannot and does not verify
+ *              the trustedness of URLs read from struct fields or returned by API calls.
+ * @kind problem
+ * @problem.severity warning
+ * @precision high
+ * @id cli-cli/immutable-safeurl-construction
+ * @tags security
+ *       correctness
+ *       maintainability
+ */
+
+import go
+
+/**
+ * Holds when `node` is the URL argument of a call to safeurl.NewImmutableSafeURL, the escape hatch
+ * that renders its argument verbatim without percent-encoding or a traversal check.
+ */
+predicate isImmutableSafeURLArgument(DataFlow::Node node) {
+  exists(Function f, DataFlow::CallNode call |
+    f.hasQualifiedName("github.com/cli/cli/v2/internal/safeurl", "NewImmutableSafeURL") and
+    call = f.getACall() and
+    node = call.getArgument(0)
+  )
+}
+
+/**
+ * Holds when `node` is a locally assembled string: the result of fmt.Sprintf, fmt.Sprint or
+ * fmt.Sprintln, or a string concatenation expression. These are the shapes that build a URL by hand
+ * rather than reading an already formed value, so they must not reach NewImmutableSafeURL.
+ */
+predicate isHandAssembledString(DataFlow::Node node) {
+  exists(Function f |
+    f.hasQualifiedName("fmt", ["Sprintf", "Sprint", "Sprintln"]) and
+    node = f.getACall()
+  )
+  or
+  exists(AddExpr e |
+    e.getType() instanceof StringType and
+    node = DataFlow::exprNode(e)
+  )
+}
+
+from DataFlow::Node source, DataFlow::Node sink
+where
+  isImmutableSafeURLArgument(sink) and
+  isHandAssembledString(source) and
+  TaintTracking::localTaint(source, sink)
+select sink,
+  "This ImmutableSafeURL is built from a hand-assembled string ($@); build the path with safeurl.JoinPath so its components are escaped and traversal-checked.",
+  source, "assembled here"
diff --git a/.github/codeql/queries/SafeURLPathConstruction.ql b/.github/codeql/queries/SafeURLPathConstruction.ql
new file mode 100644
--- /dev/null
+++ b/.github/codeql/queries/SafeURLPathConstruction.ql
@@ -0,0 +1,73 @@
+/**
+ * @name HTTP request URL not built with safeurl.SafeURL
+ * @description Flags any HTTP request, a REST API call being the common case, whose URL argument is
+ *              not literally a call to (safeurl.SafeURL).String. The argument expression itself must
+ *              be a SafeURL.String call; any other form, such as a string literal, string
+ *              concatenation, or fmt.Sprintf, is reported. This keeps every hand built URL routed
+ *              through safeurl so its variable path components are percent-encoded.
+ * @kind problem
+ * @problem.severity warning
+ * @precision high
+ * @id cli-cli/safeurl-path-construction
+ * @tags security
+ *       correctness
+ *       maintainability
+ */
+
+import go
+
+/**
+ * Holds when `node` is the URL argument of an HTTP request, a REST API call being the common case.
+ *
+ * Covered entry points:
+ *   - (github.com/cli/cli/v2/api.Client).REST and .RESTWithNext, where the path is argument 2.
+ *   - net/http.NewRequest, where the URL is argument 1.
+ *   - net/http.NewRequestWithContext, where the URL is argument 2.
+ *   - (net/http.Client).Get, .Head, .Post and .PostForm, where the URL is argument 0.
+ */
+predicate isHttpUrlArgument(DataFlow::Node node) {
+  exists(Method m, DataFlow::CallNode call |
+    m.hasQualifiedName("github.com/cli/cli/v2/api", "Client", ["REST", "RESTWithNext"]) and
+    call = m.getACall() and
+    node = call.getArgument(2)
+  )
+  or
+  exists(Function f, DataFlow::CallNode call |
+    f.hasQualifiedName("net/http", "NewRequest") and
+    call = f.getACall() and
+    node = call.getArgument(1)
+  )
+  or
+  exists(Function f, DataFlow::CallNode call |
+    f.hasQualifiedName("net/http", "NewRequestWithContext") and
+    call = f.getACall() and
+    node = call.getArgument(2)
+  )
+  or
+  exists(Method m, DataFlow::CallNode call |
+    m.hasQualifiedName("net/http", "Client", ["Get", "Head", "Post", "PostForm"]) and
+    call = m.getACall() and
+    node = call.getArgument(0)
+  )
+}
+
+/**
+ * Holds when `node` is a call to the String method of one of the safeurl URL types:
+ * the SafeURL interface or either of its implementations, MutableSafeURL and
+ * ImmutableSafeURL. Matching all three keeps call sites free of explicit conversions:
+ * a value of the concrete type can be passed to the sink directly without first being
+ * assigned to a SafeURL typed variable.
+ */
+predicate isSafeurlStringCall(DataFlow::Node node) {
+  exists(Method m |
+    m.hasQualifiedName("github.com/cli/cli/v2/internal/safeurl",
+      ["SafeURL", "MutableSafeURL", "ImmutableSafeURL"], "String") and
+    node = m.getACall()
+  )
+}
+
+from DataFlow::Node sink
+where
+  isHttpUrlArgument(sink) and
+  not isSafeurlStringCall(sink)
+select sink, "This HTTP request URL is not passed directly as the result of safeurl.SafeURL.String."
diff --git a/api/queries_pr.go b/api/queries_pr.go
--- a/api/queries_pr.go
+++ b/api/queries_pr.go
@@ -3,10 +3,10 @@ package api
 import (
 	"fmt"
 	"net/http"
-	"net/url"
 	"time"
 
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/shurcooL/githubv4"
 )
 
@@ -845,8 +845,11 @@ func ConvertPullRequestToDraft(client *Client, repo ghrepo.Interface, pr *PullRe
 }
 
 func BranchDeleteRemote(client *Client, repo ghrepo.Interface, branch string) error {
-	path := fmt.Sprintf("repos/%s/%s/git/refs/heads/%s", repo.RepoOwner(), repo.RepoName(), url.PathEscape(branch))
-	return client.REST(repo.RepoHost(), "DELETE", path, nil, nil)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "git", "refs", fmt.Sprintf("heads/%s", branch))
+	if err != nil {
+		return err
+	}
+	return client.REST(repo.RepoHost(), "DELETE", path.String(), nil, nil)
 }
 
 type RefComparison struct {
diff --git a/api/queries_pr_review.go b/api/queries_pr_review.go
--- a/api/queries_pr_review.go
+++ b/api/queries_pr_review.go
@@ -4,11 +4,12 @@ import (
 	"bytes"
 	"encoding/json"
 	"fmt"
-	"net/url"
+	"strconv"
 	"strings"
 	"time"
 
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/shurcooL/githubv4"
 )
 
@@ -284,12 +285,17 @@ func AddPullRequestReviews(client *Client, repo ghrepo.Interface, prNumber int,
 		users = []string{}
 	}
 
-	path := fmt.Sprintf(
-		"repos/%s/%s/pulls/%d/requested_reviewers",
-		url.PathEscape(repo.RepoOwner()),
-		url.PathEscape(repo.RepoName()),
-		prNumber,
+	path, err := safeurl.JoinPath(
+		"repos",
+		repo.RepoOwner(),
+		repo.RepoName(),
+		"pulls",
+		strconv.Itoa(prNumber),
+		"requested_reviewers",
 	)
+	if err != nil {
+		return err
+	}
 	body := struct {
 		Reviewers     []string `json:"reviewers"`
 		TeamReviewers []string `json:"team_reviewers"`
@@ -302,7 +308,7 @@ func AddPullRequestReviews(client *Client, repo ghrepo.Interface, prNumber int,
 		return err
 	}
 	// The endpoint responds with the updated pull request object; we don't need it here.
-	return client.REST(repo.RepoHost(), "POST", path, buf, nil)
+	return client.REST(repo.RepoHost(), "POST", path.String(), buf, nil)
 }
 
 // RemovePullRequestReviews removes requested reviewers from a pull request using the REST API.
@@ -317,12 +323,17 @@ func RemovePullRequestReviews(client *Client, repo ghrepo.Interface, prNumber in
 		users = []string{}
 	}
 
-	path := fmt.Sprintf(
-		"repos/%s/%s/pulls/%d/requested_reviewers",
-		url.PathEscape(repo.RepoOwner()),
-		url.PathEscape(repo.RepoName()),
-		prNumber,
+	path, err := safeurl.JoinPath(
+		"repos",
+		repo.RepoOwner(),
+		repo.RepoName(),
+		"pulls",
+		strconv.Itoa(prNumber),
+		"requested_reviewers",
 	)
+	if err != nil {
+		return err
+	}
 	body := struct {
 		Reviewers     []string `json:"reviewers"`
 		TeamReviewers []string `json:"team_reviewers"`
@@ -335,7 +346,7 @@ func RemovePullRequestReviews(client *Client, repo ghrepo.Interface, prNumber in
 		return err
 	}
 	// The endpoint responds with the updated pull request object; we don't need it here.
-	return client.REST(repo.RepoHost(), "DELETE", path, buf, nil)
+	return client.REST(repo.RepoHost(), "DELETE", path.String(), buf, nil)
 }
 
 // RequestReviewsByLogin sets requested reviewers on a pull request using the GraphQL mutation.
diff --git a/api/queries_repo.go b/api/queries_repo.go
--- a/api/queries_repo.go
+++ b/api/queries_repo.go
@@ -17,6 +17,7 @@ import (
 	"golang.org/x/sync/errgroup"
 
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	ghAPI "github.com/cli/go-gh/v2/pkg/api"
 	"github.com/shurcooL/githubv4"
 )
@@ -589,7 +590,10 @@ type repositoryV3 struct {
 
 // ForkRepo forks the repository on GitHub and returns the new repository
 func ForkRepo(client *Client, repo ghrepo.Interface, org, newName string, defaultBranchOnly bool) (*Repository, error) {
-	path := fmt.Sprintf("repos/%s/forks", ghrepo.FullName(repo))
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "forks")
+	if err != nil {
+		return nil, err
+	}
 
 	params := map[string]interface{}{}
 	if org != "" {
@@ -609,7 +613,7 @@ func ForkRepo(client *Client, repo ghrepo.Interface, org, newName string, defaul
 	}
 
 	result := repositoryV3{}
-	err := client.REST(repo.RepoHost(), "POST", path, body, &result)
+	err = client.REST(repo.RepoHost(), "POST", path.String(), body, &result)
 	if err != nil {
 		return nil, err
 	}
@@ -643,12 +647,13 @@ func RenameRepo(client *Client, repo ghrepo.Interface, newRepoName string) (*Rep
 		return nil, err
 	}
 
-	path := fmt.Sprintf("%srepos/%s",
-		ghinstance.RESTPrefix(repo.RepoHost()),
-		ghrepo.FullName(repo))
+	path, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName())
+	if err != nil {
+		return nil, err
+	}
 
 	result := repositoryV3{}
-	err := client.REST(repo.RepoHost(), "PATCH", path, body, &result)
+	err = client.REST(repo.RepoHost(), "PATCH", path.String(), body, &result)
 	if err != nil {
 		return nil, err
 	}
@@ -1608,9 +1613,9 @@ func v2Projects(client *Client, repo ghrepo.Interface) ([]ProjectV2, error) {
 	return projectsV2, nil
 }
 
-func CreateRepoTransformToV4(apiClient *Client, hostname string, method string, path string, body io.Reader) (*Repository, error) {
+func CreateRepoTransformToV4(apiClient *Client, hostname string, method string, path safeurl.SafeURL, body io.Reader) (*Repository, error) {
 	var responsev3 repositoryV3
-	err := apiClient.REST(hostname, method, path, body, &responsev3)
+	err := apiClient.REST(hostname, method, path.String(), body, &responsev3)
 
 	if err != nil {
 		return nil, err
@@ -1666,9 +1671,12 @@ func GetRepoIDs(client *Client, host string, repositories []ghrepo.Interface) ([
 }
 
 func RepoExists(client *Client, repo ghrepo.Interface) (bool, error) {
-	path := fmt.Sprintf("%srepos/%s/%s", ghinstance.RESTPrefix(repo.RepoHost()), repo.RepoOwner(), repo.RepoName())
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName())
+	if err != nil {
+		return false, err
+	}
 
-	resp, err := client.HTTP().Head(path)
+	resp, err := client.HTTP().Head(u.String())
 	if err != nil {
 		return false, err
 	}
@@ -1690,7 +1698,11 @@ func RepoExists(client *Client, repo ghrepo.Interface) (bool, error) {
 func RepoLicenses(httpClient *http.Client, hostname string) ([]License, error) {
 	var licenses []License
 	client := NewClientFromHTTP(httpClient)
-	err := client.REST(hostname, "GET", "licenses", nil, &licenses)
+	path, err := safeurl.JoinPath("licenses")
+	if err != nil {
+		return nil, err
+	}
+	err = client.REST(hostname, "GET", path.String(), nil, &licenses)
 	if err != nil {
 		return nil, err
 	}
@@ -1702,8 +1714,11 @@ func RepoLicenses(httpClient *http.Client, hostname string) ([]License, error) {
 func RepoLicense(httpClient *http.Client, hostname string, licenseName string) (*License, error) {
 	var license License
 	client := NewClientFromHTTP(httpClient)
-	path := fmt.Sprintf("licenses/%s", licenseName)
-	err := client.REST(hostname, "GET", path, nil, &license)
+	path, err := safeurl.JoinPath("licenses", licenseName)
+	if err != nil {
+		return nil, err
+	}
+	err = client.REST(hostname, "GET", path.String(), nil, &license)
 	if err != nil {
 		return nil, err
 	}
@@ -1715,7 +1730,11 @@ func RepoLicense(httpClient *http.Client, hostname string, licenseName string) (
 func RepoGitIgnoreTemplates(httpClient *http.Client, hostname string) ([]string, error) {
 	var gitIgnoreTemplates []string
 	client := NewClientFromHTTP(httpClient)
-	err := client.REST(hostname, "GET", "gitignore/templates", nil, &gitIgnoreTemplates)
+	path, err := safeurl.JoinPath("gitignore", "templates")
+	if err != nil {
+		return nil, err
+	}
+	err = client.REST(hostname, "GET", path.String(), nil, &gitIgnoreTemplates)
 	if err != nil {
 		return nil, err
 	}
@@ -1727,8 +1746,11 @@ func RepoGitIgnoreTemplates(httpClient *http.Client, hostname string) ([]string,
 func RepoGitIgnoreTemplate(httpClient *http.Client, hostname string, gitIgnoreTemplateName string) (*GitIgnore, error) {
 	var gitIgnoreTemplate GitIgnore
 	client := NewClientFromHTTP(httpClient)
-	path := fmt.Sprintf("gitignore/templates/%s", gitIgnoreTemplateName)
-	err := client.REST(hostname, "GET", path, nil, &gitIgnoreTemplate)
+	path, err := safeurl.JoinPath("gitignore", "templates", gitIgnoreTemplateName)
+	if err != nil {
+		return nil, err
+	}
+	err = client.REST(hostname, "GET", path.String(), nil, &gitIgnoreTemplate)
 	if err != nil {
 		return nil, err
 	}
diff --git a/internal/codespaces/api/api.go b/internal/codespaces/api/api.go
--- a/internal/codespaces/api/api.go
+++ b/internal/codespaces/api/api.go
@@ -42,6 +42,7 @@ import (
 	"github.com/cenkalti/backoff/v4"
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/opentracing/opentracing-go"
 )
@@ -115,7 +116,11 @@ func (a *API) ServerURL() string {
 
 // GetUser returns the user associated with the given token.
 func (a *API) GetUser(ctx context.Context) (*User, error) {
-	req, err := http.NewRequest(http.MethodGet, a.githubAPI+"/user", nil)
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "user")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodGet, u.String(), nil)
 	if err != nil {
 		return nil, fmt.Errorf("error creating request: %w", err)
 	}
@@ -160,7 +165,15 @@ type Repository struct {
 
 // GetRepository returns the repository associated with the given owner and name.
 func (a *API) GetRepository(ctx context.Context, nwo string) (*Repository, error) {
-	req, err := http.NewRequest(http.MethodGet, a.githubAPI+"/repos/"+strings.ToLower(nwo), nil)
+	owner, name, err := safeurl.RepoPartsFromNWO(strings.ToLower(nwo))
+	if err != nil {
+		return nil, err
+	}
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "repos", owner, name)
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodGet, u.String(), nil)
 	if err != nil {
 		return nil, fmt.Errorf("error creating request: %w", err)
 	}
@@ -364,31 +377,55 @@ func (a *API) ListCodespaces(ctx context.Context, opts ListCodespacesOptions) (c
 	}
 
 	var (
-		listURL  string
+		listURL  safeurl.SafeURL
 		spanName string
 	)
 
 	if opts.RepoName != "" {
-		listURL = fmt.Sprintf("%s/repos/%s/codespaces?per_page=%d", a.githubAPI, opts.RepoName, perPage)
+		owner, name, err := safeurl.RepoPartsFromNWO(opts.RepoName)
+		if err != nil {
+			return nil, err
+		}
+		u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "repos", owner, name, "codespaces")
+		if err != nil {
+			return nil, err
+		}
+		u.SetQuery("per_page", strconv.Itoa(perPage))
+		listURL = u
 		spanName = "/repos/*/codespaces"
 	} else if opts.OrgName != "" {
 		// the endpoints below can only be called by the organization admins
 		orgName := opts.OrgName
 		if opts.UserName != "" {
 			userName := opts.UserName
-			listURL = fmt.Sprintf("%s/orgs/%s/members/%s/codespaces?per_page=%d", a.githubAPI, orgName, userName, perPage)
+			u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "orgs", orgName, "members", userName, "codespaces")
+			if err != nil {
+				return nil, err
+			}
+			u.SetQuery("per_page", strconv.Itoa(perPage))
+			listURL = u
 			spanName = "/orgs/*/members/*/codespaces"
 		} else {
-			listURL = fmt.Sprintf("%s/orgs/%s/codespaces?per_page=%d", a.githubAPI, orgName, perPage)
+			u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "orgs", orgName, "codespaces")
+			if err != nil {
+				return nil, err
+			}
+			u.SetQuery("per_page", strconv.Itoa(perPage))
+			listURL = u
 			spanName = "/orgs/*/codespaces"
 		}
 	} else {
-		listURL = fmt.Sprintf("%s/user/codespaces?per_page=%d", a.githubAPI, perPage)
+		u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "user", "codespaces")
+		if err != nil {
+			return nil, err
+		}
+		u.SetQuery("per_page", strconv.Itoa(perPage))
+		listURL = u
 		spanName = "/user/codespaces"
 	}
 
 	for {
-		req, err := http.NewRequest(http.MethodGet, listURL, nil)
+		req, err := http.NewRequest(http.MethodGet, listURL.String(), nil)
 		if err != nil {
 			return nil, fmt.Errorf("error creating request: %w", err)
 		}
@@ -425,9 +462,9 @@ func (a *API) ListCodespaces(ctx context.Context, opts ListCodespacesOptions) (c
 			q := u.Query()
 			q.Set("per_page", strconv.Itoa(newPerPage))
 			u.RawQuery = q.Encode()
-			listURL = u.String()
+			listURL = safeurl.NewImmutableSafeURL(u.String())
 		} else {
-			listURL = nextURL
+			listURL = safeurl.NewImmutableSafeURL(nextURL)
 		}
 	}
 
@@ -447,10 +484,15 @@ func findNextPage(linkValue string) string {
 
 func (a *API) GetOrgMemberCodespace(ctx context.Context, orgName string, userName string, codespaceName string) (*Codespace, error) {
 	perPage := 100
-	listURL := fmt.Sprintf("%s/orgs/%s/members/%s/codespaces?per_page=%d", a.githubAPI, orgName, userName, perPage)
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "orgs", orgName, "members", userName, "codespaces")
+	if err != nil {
+		return nil, err
+	}
+	u.SetQuery("per_page", strconv.Itoa(perPage))
+	var listURL safeurl.SafeURL = u
 
 	for {
-		req, err := http.NewRequest(http.MethodGet, listURL, nil)
+		req, err := http.NewRequest(http.MethodGet, listURL.String(), nil)
 		if err != nil {
 			return nil, fmt.Errorf("error creating request: %w", err)
 		}
@@ -485,7 +527,7 @@ func (a *API) GetOrgMemberCodespace(ctx context.Context, orgName string, userNam
 		if nextURL == "" {
 			break
 		}
-		listURL = nextURL
+		listURL = safeurl.NewImmutableSafeURL(nextURL)
 	}
 
 	return nil, fmt.Errorf("codespace not found for user %s with name %s", userName, codespaceName)
@@ -496,9 +538,13 @@ func (a *API) GetOrgMemberCodespace(ctx context.Context, orgName string, userNam
 // If includeConnection is true, it will return the connection information for the codespace.
 func (a *API) GetCodespace(ctx context.Context, codespaceName string, includeConnection bool) (*Codespace, error) {
 	resp, err := a.withRetry(func() (*http.Response, error) {
+		u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "user", "codespaces", codespaceName)
+		if err != nil {
+			return nil, err
+		}
 		req, err := http.NewRequest(
 			http.MethodGet,
-			a.githubAPI+"/user/codespaces/"+codespaceName,
+			u.String(),
 			nil,
 		)
 		if err != nil {
@@ -539,9 +585,13 @@ func (a *API) GetCodespace(ctx context.Context, codespaceName string, includeCon
 // If the codespace is already running, the returned error from the API is ignored.
 func (a *API) StartCodespace(ctx context.Context, codespaceName string) error {
 	resp, err := a.withRetry(func() (*http.Response, error) {
+		u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "user", "codespaces", codespaceName, "start")
+		if err != nil {
+			return nil, err
+		}
 		req, err := http.NewRequest(
 			http.MethodPost,
-			a.githubAPI+"/user/codespaces/"+codespaceName+"/start",
+			u.String(),
 			nil,
 		)
 		if err != nil {
@@ -567,18 +617,22 @@ func (a *API) StartCodespace(ctx context.Context, codespaceName string) error {
 }
 
 func (a *API) StopCodespace(ctx context.Context, codespaceName string, orgName string, userName string) error {
-	var stopURL string
+	var stopURL *safeurl.MutableSafeURL
 	var spanName string
+	var err error
 
 	if orgName != "" {
-		stopURL = fmt.Sprintf("%s/orgs/%s/members/%s/codespaces/%s/stop", a.githubAPI, orgName, userName, codespaceName)
+		stopURL, err = safeurl.JoinPathWithHostPrefix(a.githubAPI, "orgs", orgName, "members", userName, "codespaces", codespaceName, "stop")
 		spanName = "/orgs/*/members/*/codespaces/*/stop"
 	} else {
-		stopURL = fmt.Sprintf("%s/user/codespaces/%s/stop", a.githubAPI, codespaceName)
+		stopURL, err = safeurl.JoinPathWithHostPrefix(a.githubAPI, "user", "codespaces", codespaceName, "stop")
 		spanName = "/user/codespaces/*/stop"
 	}
+	if err != nil {
+		return err
+	}
 
-	req, err := http.NewRequest(http.MethodPost, stopURL, nil)
+	req, err := http.NewRequest(http.MethodPost, stopURL.String(), nil)
 	if err != nil {
 		return fmt.Errorf("error creating request: %w", err)
 	}
@@ -605,8 +659,11 @@ type Machine struct {
 
 // GetCodespacesMachines returns the codespaces machines for the given repo, branch and location.
 func (a *API) GetCodespacesMachines(ctx context.Context, repoID int64, branch, location string, devcontainerPath string) ([]*Machine, error) {
-	reqURL := fmt.Sprintf("%s/repositories/%d/codespaces/machines", a.githubAPI, repoID)
-	req, err := http.NewRequest(http.MethodGet, reqURL, nil)
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "repositories", strconv.FormatInt(repoID, 10), "codespaces", "machines")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodGet, u.String(), nil)
 	if err != nil {
 		return nil, fmt.Errorf("error creating request: %w", err)
 	}
@@ -645,8 +702,11 @@ func (a *API) GetCodespacesMachines(ctx context.Context, repoID int64, branch, l
 
 // GetCodespacesPermissionsCheck returns a bool indicating whether the user has accepted permissions for the given repo and devcontainer path.
 func (a *API) GetCodespacesPermissionsCheck(ctx context.Context, repoID int64, branch string, devcontainerPath string) (bool, error) {
-	reqURL := fmt.Sprintf("%s/repositories/%d/codespaces/permissions_check", a.githubAPI, repoID)
-	req, err := http.NewRequest(http.MethodGet, reqURL, nil)
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "repositories", strconv.FormatInt(repoID, 10), "codespaces", "permissions_check")
+	if err != nil {
+		return false, err
+	}
+	req, err := http.NewRequest(http.MethodGet, u.String(), nil)
 	if err != nil {
 		return false, fmt.Errorf("error creating request: %w", err)
 	}
@@ -692,8 +752,11 @@ type RepoSearchParameters struct {
 
 // GetCodespaceRepoSuggestions searches for and returns repo names based on the provided search text.
 func (a *API) GetCodespaceRepoSuggestions(ctx context.Context, partialSearch string, parameters RepoSearchParameters) ([]string, error) {
-	reqURL := fmt.Sprintf("%s/search/repositories", a.githubAPI)
-	req, err := http.NewRequest(http.MethodGet, reqURL, nil)
+	reqURL, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "search", "repositories")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodGet, reqURL.String(), nil)
 	if err != nil {
 		return nil, fmt.Errorf("error creating request: %w", err)
 	}
@@ -763,7 +826,15 @@ func (a *API) GetCodespaceRepoSuggestions(ctx context.Context, partialSearch str
 // GetCodespaceBillableOwner returns the billable owner and expected default values for
 // codespaces created by the user for a given repository.
 func (a *API) GetCodespaceBillableOwner(ctx context.Context, nwo string) (*User, error) {
-	req, err := http.NewRequest(http.MethodGet, a.githubAPI+"/repos/"+nwo+"/codespaces/new", nil)
+	owner, name, err := safeurl.RepoPartsFromNWO(nwo)
+	if err != nil {
+		return nil, err
+	}
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "repos", owner, name, "codespaces", "new")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodGet, u.String(), nil)
 	if err != nil {
 		return nil, fmt.Errorf("error creating request: %w", err)
 	}
@@ -908,7 +979,11 @@ func (a *API) startCreate(ctx context.Context, params *CreateCodespaceParams) (*
 		return nil, fmt.Errorf("error marshaling request: %w", err)
 	}
 
-	req, err := http.NewRequest(http.MethodPost, a.githubAPI+"/user/codespaces", bytes.NewBuffer(requestBody))
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "user", "codespaces")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodPost, u.String(), bytes.NewBuffer(requestBody))
 	if err != nil {
 		return nil, fmt.Errorf("error creating request: %w", err)
 	}
@@ -974,18 +1049,22 @@ func (a *API) startCreate(ctx context.Context, params *CreateCodespaceParams) (*
 
 // DeleteCodespace deletes the given codespace.
 func (a *API) DeleteCodespace(ctx context.Context, codespaceName string, orgName string, userName string) error {
-	var deleteURL string
+	var deleteURL *safeurl.MutableSafeURL
 	var spanName string
+	var err error
 
 	if orgName != "" && userName != "" {
-		deleteURL = fmt.Sprintf("%s/orgs/%s/members/%s/codespaces/%s", a.githubAPI, orgName, userName, codespaceName)
+		deleteURL, err = safeurl.JoinPathWithHostPrefix(a.githubAPI, "orgs", orgName, "members", userName, "codespaces", codespaceName)
 		spanName = "/orgs/*/members/*/codespaces/*"
 	} else {
-		deleteURL = a.githubAPI + "/user/codespaces/" + codespaceName
+		deleteURL, err = safeurl.JoinPathWithHostPrefix(a.githubAPI, "user", "codespaces", codespaceName)
 		spanName = "/user/codespaces/*"
 	}
+	if err != nil {
+		return err
+	}
 
-	req, err := http.NewRequest(http.MethodDelete, deleteURL, nil)
+	req, err := http.NewRequest(http.MethodDelete, deleteURL.String(), nil)
 	if err != nil {
 		return fmt.Errorf("error creating request: %w", err)
 	}
@@ -1017,15 +1096,18 @@ func (a *API) ListDevContainers(ctx context.Context, repoID int64, branch string
 		perPage = limit
 	}
 
-	v := url.Values{}
-	v.Set("per_page", strconv.Itoa(perPage))
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "repositories", strconv.FormatInt(repoID, 10), "codespaces", "devcontainers")
+	if err != nil {
+		return nil, err
+	}
+	u.SetQuery("per_page", strconv.Itoa(perPage))
 	if branch != "" {
-		v.Set("ref", branch)
+		u.SetQuery("ref", branch)
 	}
-	listURL := fmt.Sprintf("%s/repositories/%d/codespaces/devcontainers?%s", a.githubAPI, repoID, v.Encode())
+	var listURL safeurl.SafeURL = u
 
 	for {
-		req, err := http.NewRequest(http.MethodGet, listURL, nil)
+		req, err := http.NewRequest(http.MethodGet, listURL.String(), nil)
 		if err != nil {
 			return nil, fmt.Errorf("error creating request: %w", err)
 		}
@@ -1062,9 +1144,9 @@ func (a *API) ListDevContainers(ctx context.Context, repoID int64, branch string
 			q := u.Query()
 			q.Set("per_page", strconv.Itoa(newPerPage))
 			u.RawQuery = q.Encode()
-			listURL = u.String()
+			listURL = safeurl.NewImmutableSafeURL(u.String())
 		} else {
-			listURL = nextURL
+			listURL = safeurl.NewImmutableSafeURL(nextURL)
 		}
 	}
 
@@ -1083,7 +1165,11 @@ func (a *API) EditCodespace(ctx context.Context, codespaceName string, params *E
 		return nil, fmt.Errorf("error marshaling request: %w", err)
 	}
 
-	req, err := http.NewRequest(http.MethodPatch, a.githubAPI+"/user/codespaces/"+codespaceName, bytes.NewBuffer(requestBody))
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "user", "codespaces", codespaceName)
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodPatch, u.String(), bytes.NewBuffer(requestBody))
 	if err != nil {
 		return nil, fmt.Errorf("error creating request: %w", err)
 	}
@@ -1139,7 +1225,15 @@ type getCodespaceRepositoryContentsResponse struct {
 }
 
 func (a *API) GetCodespaceRepositoryContents(ctx context.Context, codespace *Codespace, path string) ([]byte, error) {
-	req, err := http.NewRequest(http.MethodGet, a.githubAPI+"/repos/"+codespace.Repository.FullName+"/contents/"+path, nil)
+	owner, name, err := safeurl.RepoPartsFromNWO(codespace.Repository.FullName)
+	if err != nil {
+		return nil, err
+	}
+	u, err := safeurl.JoinPathWithHostPrefix(a.githubAPI, "repos", owner, name, "contents", path)
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodGet, u.String(), nil)
 	if err != nil {
 		return nil, fmt.Errorf("error creating request: %w", err)
 	}
diff --git a/internal/featuredetection/feature_detection.go b/internal/featuredetection/feature_detection.go
--- a/internal/featuredetection/feature_detection.go
+++ b/internal/featuredetection/feature_detection.go
@@ -5,6 +5,7 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/gh"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/hashicorp/go-version"
 	"golang.org/x/sync/errgroup"
 
@@ -541,7 +542,11 @@ func resolveEnterpriseVersion(httpClient *http.Client, host string) (*version.Ve
 	}
 
 	apiClient := api.NewClientFromHTTP(httpClient)
-	err := apiClient.REST(host, "GET", "meta", nil, &metaResponse)
+	u, err := safeurl.JoinPath("meta")
+	if err != nil {
+		return nil, err
+	}
+	err = apiClient.REST(host, "GET", u.String(), nil, &metaResponse)
 	if err != nil {
 		return nil, err
 	}
diff --git a/internal/safeurl/safeurl.go b/internal/safeurl/safeurl.go
new file mode 100644
--- /dev/null
+++ b/internal/safeurl/safeurl.go
@@ -0,0 +1,164 @@
+// Package safeurl provides helpers for building REST API URL paths (and full
+// URLs, when a host prefix is supplied) from variable components so that user
+// or server controlled values cannot break the path or change which resource
+// is addressed.
+package safeurl
+
+import (
+	"fmt"
+	"net/url"
+	"strings"
+)
+
+// RepoPartsFromNWO parses a raw "owner/repo" string and returns the owner and name
+// unescaped. It returns an error unless nwo contains exactly one slash with a non-empty
+// owner and name, so a value carrying extra slashes cannot smuggle additional path
+// segments through as the owner or name.
+//
+// This intentionally does not reuse ghrepo.FromFullName, which accepts the broader
+// "[HOST/]OWNER/REPO" form. The call sites here only ever handle a bare "OWNER/REPO",
+// so a stricter parse that rejects an unexpected host component is the safer fit.
+func RepoPartsFromNWO(nwo string) (owner, name string, err error) {
+	parts := strings.Split(nwo, "/")
+	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
+		return "", "", fmt.Errorf("expected the \"OWNER/REPO\" format, got %q", nwo)
+	}
+	return parts[0], parts[1], nil
+}
+
+// SafeURL is the sealed interface implemented by the URL types in this package.
+// It exists so that a value known to address a safe REST API URL can be passed
+// around and rendered without exposing how it was built.
+type SafeURL interface {
+	String() string
+
+	// The sealed method keeps the set of implementations closed to this package,
+	// so callers outside it cannot forge a value that claims to be safe.
+	sealed()
+}
+
+// MutableSafeURL is a REST API URL built from a host prefix, path components, and query
+// parameters. The path components and query parameters are URL encoded (aka
+// percent-encoded) when the URL is rendered so that caller supplied values cannot
+// alter the structure of the URL or change which resource it addresses; the host
+// prefix is used as given. The zero value renders as the empty string.
+type MutableSafeURL struct {
+	prefix     string
+	components []string
+	query      url.Values
+}
+
+// JoinPath returns a SafeURL for the path made up of the given components. It
+// returns an error if any component is exactly "..", which would traverse the URL
+// path and change which resource it addresses.
+func JoinPath(components ...string) (*MutableSafeURL, error) {
+	if err := checkTraversal(components); err != nil {
+		return nil, err
+	}
+	return &MutableSafeURL{components: components}, nil
+}
+
+// JoinPathWithHostPrefix returns a SafeURL for the given host prefix and the path
+// made up of the given components. It returns an error if any component is exactly
+// "..", which would traverse the URL path and change which resource it addresses.
+func JoinPathWithHostPrefix(hostPrefix string, components ...string) (*MutableSafeURL, error) {
+	if err := checkTraversal(components); err != nil {
+		return nil, err
+	}
+	return &MutableSafeURL{prefix: hostPrefix, components: components}, nil
+}
+
+// checkTraversal returns an error if any component is exactly "..". Such a component
+// survives percent-encoding as a real path segment and would traverse the URL path.
+// A single "." is left alone because it does not traverse and is a legitimate value
+// in some paths.
+func checkTraversal(components []string) error {
+	for _, c := range components {
+		if c == ".." {
+			return fmt.Errorf("path component %q would traverse the URL path", c)
+		}
+	}
+	return nil
+}
+
+func (u *MutableSafeURL) sealed() {}
+
+// SetQuery sets the query parameter key to value, replacing any existing value.
+func (u *MutableSafeURL) SetQuery(key, value string) {
+	if u.query == nil {
+		u.query = url.Values{}
+	}
+	u.query.Set(key, value)
+}
+
+// String renders the full URL. Path components and query parameters are URL encoded
+// (aka percent-encoded) while the host prefix is included as given. The zero value
+// renders as the empty string.
+func (u *MutableSafeURL) String() string {
+	result := joinPathWithHostPrefix(u.prefix, u.components...)
+	if len(u.query) > 0 {
+		result += "?" + u.query.Encode()
+	}
+	return result
+}
+
+// ImmutableSafeURL is a SafeURL that renders a fixed URL string verbatim. It exists
+// so that a URL which was not built from percent-encoded components, such as a full
+// URL returned by the server (a pagination "next" link, an asset download URL, and
+// the like), can still flow through the SafeURL typed code paths. Because the stored
+// value is rendered as given without any encoding, it is only safe to wrap a URL that
+// was created from trusted components or received from a trusted source.
+type ImmutableSafeURL struct {
+	url string
+}
+
+// NewImmutableSafeURL returns an ImmutableSafeURL that renders url verbatim. Only pass
+// a URL you built yourself from trusted components or received from a trusted source,
+// such as a server response; this bypasses all percent-encoding, so passing a value
+// that embeds unescaped user or third party input reintroduces the injection risk that
+// SafeURL exists to prevent.
+func NewImmutableSafeURL(url string) *ImmutableSafeURL {
+	return &ImmutableSafeURL{url: url}
+}
+
+func (u *ImmutableSafeURL) sealed() {}
+
+// String returns the wrapped URL verbatim.
+func (u *ImmutableSafeURL) String() string {
+	return u.url
+}
+
+// joinPath builds a REST API URL path by percent-encoding each component with
+// url.PathEscape and joining them with single slash separators.
+//
+// With no components, the empty string is returned.
+func joinPath(components ...string) string {
+	// We build the path by hand rather than with url.JoinPath because url.JoinPath runs path.Clean
+	// on the result, which resolves any "." or ".." segments. Percent-encoding does not encode dots,
+	// so a component equal to "." or ".." would survive escaping and then be collapsed by the clean,
+	// silently changing which resource the path addresses.
+	escaped := make([]string, len(components))
+	for i, c := range components {
+		escaped[i] = url.PathEscape(c)
+	}
+	return strings.Join(escaped, "/")
+}
+
+// joinPathWithHostPrefix builds a full REST API URL by prepending hostPrefix to the path produced by
+// JoinPath. A single slash is ensured at the join between hostPrefix and the path so they separate
+// cleanly without doubling up. When hostPrefix is empty, the JoinPath result is returned intact, and
+// when the joined path is empty, hostPrefix is returned intact. hostPrefix is used verbatim while each
+// component is percent-encoded.
+func joinPathWithHostPrefix(hostPrefix string, components ...string) string {
+	path := joinPath(components...)
+	if hostPrefix == "" {
+		return path
+	}
+	if path == "" {
+		return hostPrefix
+	}
+	if !strings.HasSuffix(hostPrefix, "/") {
+		return hostPrefix + "/" + path
+	}
+	return hostPrefix + path
+}
diff --git a/internal/skills/discovery/discovery.go b/internal/skills/discovery/discovery.go
--- a/internal/skills/discovery/discovery.go
+++ b/internal/skills/discovery/discovery.go
@@ -6,7 +6,6 @@ import (
 	"fmt"
 	"io"
 	"net/http"
-	"net/url"
 	"os"
 	"path"
 	"path/filepath"
@@ -17,6 +16,7 @@ import (
 	"sync/atomic"
 
 	"github.com/cli/cli/v2/api"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/skills/frontmatter"
 	"github.com/cli/cli/v2/pkg/iostreams"
 )
@@ -189,11 +189,14 @@ func parseRepoVisibility(s string) (RepoVisibility, error) {
 
 // FetchRepoVisibility returns the repository visibility: "public", "private", or "internal".
 func FetchRepoVisibility(client *api.Client, host, owner, repo string) (RepoVisibility, error) {
-	apiPath := fmt.Sprintf("repos/%s/%s", url.PathEscape(owner), url.PathEscape(repo))
+	apiPath, err := safeurl.JoinPath("repos", owner, repo)
+	if err != nil {
+		return "", err
+	}
 	var resp struct {
 		Visibility string `json:"visibility"`
 	}
-	if err := client.REST(host, "GET", apiPath, nil, &resp); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &resp); err != nil {
 		return "", err
 	}
 	return parseRepoVisibility(resp.Visibility)
@@ -252,11 +255,14 @@ func resolveExplicitRef(client *api.Client, host, owner, repo, ref string) (*Res
 		return nil, err
 	}
 
-	commitPath := fmt.Sprintf("repos/%s/%s/commits/%s", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(ref))
+	commitPath, err := safeurl.JoinPath("repos", owner, repo, "commits", ref)
+	if err != nil {
+		return nil, err
+	}
 	var commitResp struct {
 		SHA string `json:"sha"`
 	}
-	if err := client.REST(host, "GET", commitPath, nil, &commitResp); err == nil {
+	if err := client.REST(host, "GET", commitPath.String(), nil, &commitResp); err == nil {
 		return &ResolvedRef{Ref: commitResp.SHA, SHA: commitResp.SHA}, nil
 	} else if !isNotFound(err) {
 		return nil, err
@@ -268,25 +274,31 @@ func resolveExplicitRef(client *api.Client, host, owner, repo, ref string) (*Res
 // resolveTagRef looks up a tag by short name and returns a fully qualified ref.
 // For annotated tags, the tag object is dereferenced to obtain the commit SHA.
 func resolveTagRef(client *api.Client, host, owner, repo, tag string) (*ResolvedRef, error) {
-	tagPath := fmt.Sprintf("repos/%s/%s/git/ref/tags/%s", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(tag))
+	tagPath, err := safeurl.JoinPath("repos", owner, repo, "git", "ref", fmt.Sprintf("tags/%s", tag))
+	if err != nil {
+		return nil, err
+	}
 	var refResp struct {
 		Object struct {
 			SHA  string `json:"sha"`
 			Type string `json:"type"`
 		} `json:"object"`
 	}
-	if err := client.REST(host, "GET", tagPath, nil, &refResp); err != nil {
+	if err := client.REST(host, "GET", tagPath.String(), nil, &refResp); err != nil {
 		return nil, fmt.Errorf("tag %q not found in %s/%s: %w", tag, owner, repo, err)
 	}
 	sha := refResp.Object.SHA
 	if refResp.Object.Type == "tag" {
-		derefPath := fmt.Sprintf("repos/%s/%s/git/tags/%s", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(sha))
+		derefPath, err := safeurl.JoinPath("repos", owner, repo, "git", "tags", sha)
+		if err != nil {
+			return nil, err
+		}
 		var tagResp struct {
 			Object struct {
 				SHA string `json:"sha"`
 			} `json:"object"`
 		}
-		if err := client.REST(host, "GET", derefPath, nil, &tagResp); err != nil {
+		if err := client.REST(host, "GET", derefPath.String(), nil, &tagResp); err != nil {
 			return nil, fmt.Errorf("could not dereference annotated tag %q: %w", tag, err)
 		}
 		sha = tagResp.Object.SHA
@@ -296,13 +308,16 @@ func resolveTagRef(client *api.Client, host, owner, repo, tag string) (*Resolved
 
 // resolveBranchRef looks up a branch by short name and returns a fully qualified ref.
 func resolveBranchRef(client *api.Client, host, owner, repo, branch string) (*ResolvedRef, error) {
-	refPath := fmt.Sprintf("repos/%s/%s/git/ref/heads/%s", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(branch))
+	refPath, err := safeurl.JoinPath("repos", owner, repo, "git", "ref", fmt.Sprintf("heads/%s", branch))
+	if err != nil {
+		return nil, err
+	}
 	var refResp struct {
 		Object struct {
 			SHA string `json:"sha"`
 		} `json:"object"`
 	}
-	if err := client.REST(host, "GET", refPath, nil, &refResp); err != nil {
+	if err := client.REST(host, "GET", refPath.String(), nil, &refResp); err != nil {
 		return nil, fmt.Errorf("branch %q not found in %s/%s: %w", branch, owner, repo, err)
 	}
 	return &ResolvedRef{Ref: "refs/heads/" + branch, SHA: refResp.Object.SHA}, nil
@@ -324,11 +339,14 @@ type noReleasesError struct {
 func (e *noReleasesError) Error() string { return e.reason }
 
 func resolveLatestRelease(client *api.Client, host, owner, repo string) (*ResolvedRef, error) {
-	apiPath := fmt.Sprintf("repos/%s/%s/releases/latest", url.PathEscape(owner), url.PathEscape(repo))
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "releases", "latest")
+	if err != nil {
+		return nil, err
+	}
 	var resp struct {
 		TagName string `json:"tag_name"`
 	}
-	if err := client.REST(host, "GET", apiPath, nil, &resp); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &resp); err != nil {
 		// A 404 means the repository has no releases. This is the
 		// only case where falling back to the default branch is safe.
 		// Any other HTTP error (403, 500, …) or network failure is
@@ -346,11 +364,14 @@ func resolveLatestRelease(client *api.Client, host, owner, repo string) (*Resolv
 }
 
 func resolveDefaultBranch(client *api.Client, host, owner, repo string) (*ResolvedRef, error) {
-	apiPath := fmt.Sprintf("repos/%s/%s", url.PathEscape(owner), url.PathEscape(repo))
+	apiPath, err := safeurl.JoinPath("repos", owner, repo)
+	if err != nil {
+		return nil, err
+	}
 	var resp struct {
 		DefaultBranch string `json:"default_branch"`
 	}
-	if err := client.REST(host, "GET", apiPath, nil, &resp); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &resp); err != nil {
 		return nil, fmt.Errorf("could not determine default branch: %w", err)
 	}
 	branch := resp.DefaultBranch
@@ -552,9 +573,13 @@ func DiscoverSkills(client *api.Client, host, owner, repo, commitSHA string) ([]
 // DiscoverSkillsWithOptions finds all skills in a repository at the given
 // commit SHA, with configurable discovery behavior.
 func DiscoverSkillsWithOptions(client *api.Client, host, owner, repo, commitSHA string, opts DiscoverOptions) ([]Skill, error) {
-	apiPath := fmt.Sprintf("repos/%s/%s/git/trees/%s?recursive=true", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(commitSHA))
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "git", "trees", commitSHA)
+	if err != nil {
+		return nil, err
+	}
+	apiPath.SetQuery("recursive", "true")
 	var tree treeResponse
-	if err := client.REST(host, "GET", apiPath, nil, &tree); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &tree); err != nil {
 		return nil, fmt.Errorf("could not fetch repository tree: %w", err)
 	}
 
@@ -698,15 +723,19 @@ func DiscoverSkillByPathWithOptions(client *api.Client, host, owner, repo, commi
 	}
 
 	parentPath := path.Dir(skillPath)
-	apiPath := fmt.Sprintf("repos/%s/%s/contents/%s?ref=%s", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(parentPath), commitSHA)
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "contents", parentPath)
+	if err != nil {
+		return nil, err
+	}
+	apiPath.SetQuery("ref", commitSHA)
 
 	var contents []struct {
 		Name string `json:"name"`
 		Path string `json:"path"`
 		SHA  string `json:"sha"`
 		Type string `json:"type"`
 	}
-	if err := client.REST(host, "GET", apiPath, nil, &contents); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &contents); err != nil {
 		return nil, fmt.Errorf("path %q not found in %s/%s: %w", parentPath, owner, repo, err)
 	}
 
@@ -721,9 +750,12 @@ func DiscoverSkillByPathWithOptions(client *api.Client, host, owner, repo, commi
 		return nil, fmt.Errorf("skill directory %q not found in %s/%s", skillPath, owner, repo)
 	}
 
-	skillTreePath := fmt.Sprintf("repos/%s/%s/git/trees/%s", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(treeSHA))
+	skillTreePath, err := safeurl.JoinPath("repos", owner, repo, "git", "trees", treeSHA)
+	if err != nil {
+		return nil, err
+	}
 	var skillTree treeResponse
-	if err := client.REST(host, "GET", skillTreePath, nil, &skillTree); err != nil {
+	if err := client.REST(host, "GET", skillTreePath.String(), nil, &skillTree); err != nil {
 		return nil, fmt.Errorf("could not read skill directory: %w", err)
 	}
 
@@ -779,9 +811,13 @@ func DiscoverSkillByPathWithOptions(client *api.Client, host, owner, repo, commi
 // DiscoverSkillFiles returns all file paths belonging to a skill directory
 // by fetching the skill's subtree directly using its tree SHA.
 func DiscoverSkillFiles(client *api.Client, host, owner, repo, treeSHA, skillPath string) ([]SkillFile, error) {
-	apiPath := fmt.Sprintf("repos/%s/%s/git/trees/%s?recursive=true", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(treeSHA))
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "git", "trees", treeSHA)
+	if err != nil {
+		return nil, err
+	}
+	apiPath.SetQuery("recursive", "true")
 	var tree treeResponse
-	if err := client.REST(host, "GET", apiPath, nil, &tree); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &tree); err != nil {
 		return nil, fmt.Errorf("could not fetch skill tree: %w", err)
 	}
 
@@ -807,9 +843,13 @@ func DiscoverSkillFiles(client *api.Client, host, owner, repo, treeSHA, skillPat
 // ListSkillFiles returns all files in a skill directory as public SkillFile
 // structs with paths relative to the skill root.
 func ListSkillFiles(client *api.Client, host, owner, repo, treeSHA string) ([]SkillFile, error) {
-	apiPath := fmt.Sprintf("repos/%s/%s/git/trees/%s?recursive=true", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(treeSHA))
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "git", "trees", treeSHA)
+	if err != nil {
+		return nil, err
+	}
+	apiPath.SetQuery("recursive", "true")
 	var tree treeResponse
-	if err := client.REST(host, "GET", apiPath, nil, &tree); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &tree); err != nil {
 		return nil, fmt.Errorf("could not fetch skill tree: %w", err)
 	}
 
@@ -842,9 +882,12 @@ func walkTree(client *api.Client, host, owner, repo, sha, prefix string, depth i
 	if depth > maxTreeDepth {
 		return nil, fmt.Errorf("tree depth exceeds %d levels at %s", maxTreeDepth, prefix)
 	}
-	apiPath := fmt.Sprintf("repos/%s/%s/git/trees/%s", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(sha))
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "git", "trees", sha)
+	if err != nil {
+		return nil, err
+	}
 	var tree treeResponse
-	if err := client.REST(host, "GET", apiPath, nil, &tree); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &tree); err != nil {
 		return nil, fmt.Errorf("could not fetch tree %s: %w", prefix, err)
 	}
 
@@ -873,13 +916,16 @@ func walkTree(client *api.Client, host, owner, repo, sha, prefix string, depth i
 // iostreams.Untrusted and callers must choose sanitized display or raw
 // round-tripping.
 func FetchBlob(client *api.Client, host, owner, repo, sha string) (iostreams.Untrusted, error) {
-	apiPath := fmt.Sprintf("repos/%s/%s/git/blobs/%s", url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(sha))
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "git", "blobs", sha)
+	if err != nil {
+		return iostreams.Untrusted{}, err
+	}
 	var resp struct {
 		SHA      string `json:"sha"`
 		Content  string `json:"content"`
 		Encoding string `json:"encoding"`
 	}
-	if err := client.REST(host, "GET", apiPath, nil, &resp); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &resp); err != nil {
 		return iostreams.Untrusted{}, fmt.Errorf("could not fetch blob: %w", err)
 	}
 
diff --git a/internal/update/update.go b/internal/update/update.go
--- a/internal/update/update.go
+++ b/internal/update/update.go
@@ -14,6 +14,7 @@ import (
 	"time"
 
 	"github.com/cli/cli/v2/internal/ci"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/extensions"
 	"github.com/hashicorp/go-version"
 	"github.com/mattn/go-isatty"
@@ -112,7 +113,15 @@ func CheckForUpdate(ctx context.Context, client *http.Client, stateFilePath, rep
 }
 
 func getLatestReleaseInfo(ctx context.Context, client *http.Client, repo string) (*ReleaseInfo, error) {
-	req, err := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", repo), nil)
+	owner, name, err := safeurl.RepoPartsFromNWO(repo)
+	if err != nil {
+		return nil, err
+	}
+	u, err := safeurl.JoinPathWithHostPrefix("https://api.github.com", "repos", owner, name, "releases", "latest")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/agent-task/capi/job.go b/pkg/cmd/agent-task/capi/job.go
--- a/pkg/cmd/agent-task/capi/job.go
+++ b/pkg/cmd/agent-task/capi/job.go
@@ -8,8 +8,9 @@ import (
 	"fmt"
 	"io"
 	"net/http"
-	"net/url"
 	"time"
+
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 const defaultEventType = "gh_cli"
@@ -66,7 +67,10 @@ func (c *CAPIClient) CreateJob(ctx context.Context, owner, repo, problemStatemen
 		return nil, errors.New("problem statement is required")
 	}
 
-	url := fmt.Sprintf("%s/%s/%s", c.jobsBasePathV1(), url.PathEscape(owner), url.PathEscape(repo))
+	u, err := safeurl.JoinPathWithHostPrefix(c.jobsBasePathV1(), owner, repo)
+	if err != nil {
+		return nil, err
+	}
 
 	prOpts := JobPullRequest{}
 	if baseBranch != "" {
@@ -82,7 +86,7 @@ func (c *CAPIClient) CreateJob(ctx context.Context, owner, repo, problemStatemen
 
 	b, _ := json.Marshal(payload)
 
-	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(b))
+	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u.String(), bytes.NewReader(b))
 	if err != nil {
 		return nil, err
 	}
@@ -132,8 +136,11 @@ func (c *CAPIClient) GetJob(ctx context.Context, owner, repo, jobID string) (*Jo
 	if owner == "" || repo == "" || jobID == "" {
 		return nil, errors.New("owner, repo, and jobID are required")
 	}
-	url := fmt.Sprintf("%s/%s/%s/%s", c.jobsBasePathV1(), url.PathEscape(owner), url.PathEscape(repo), url.PathEscape(jobID))
-	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
+	u, err := safeurl.JoinPathWithHostPrefix(c.jobsBasePathV1(), owner, repo, jobID)
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), http.NoBody)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/agent-task/capi/sessions.go b/pkg/cmd/agent-task/capi/sessions.go
--- a/pkg/cmd/agent-task/capi/sessions.go
+++ b/pkg/cmd/agent-task/capi/sessions.go
@@ -10,12 +10,12 @@ import (
 	"io"
 	"math"
 	"net/http"
-	"net/url"
 	"slices"
 	"strconv"
 	"time"
 
 	"github.com/cli/cli/v2/api"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/shurcooL/githubv4"
 	"github.com/vmihailenco/msgpack/v5"
 )
@@ -217,16 +217,16 @@ func (c *CAPIClient) ListLatestSessionsForViewer(ctx context.Context, limit int)
 		return nil, nil
 	}
 
-	sessionsURL, err := url.JoinPath(c.capiBaseURL, "agents", "sessions")
+	sessionsURL, err := safeurl.JoinPathWithHostPrefix(c.capiBaseURL, "agents", "sessions")
 	if err != nil {
-		return nil, fmt.Errorf("failed to build sessions URL: %w", err)
+		return nil, err
 	}
 	pageSize := defaultSessionsPerPage
 
 	seenResources := make(map[int64]struct{})
 	latestSessions := make([]session, 0, limit)
 	for page := 1; ; page++ {
-		req, err := http.NewRequestWithContext(ctx, http.MethodGet, sessionsURL, http.NoBody)
+		req, err := http.NewRequestWithContext(ctx, http.MethodGet, sessionsURL.String(), http.NoBody)
 		if err != nil {
 			return nil, err
 		}
@@ -299,9 +299,12 @@ func (c *CAPIClient) GetSession(ctx context.Context, id string) (*Session, error
 		return nil, fmt.Errorf("missing session ID")
 	}
 
-	url := fmt.Sprintf("%s/agents/sessions/%s", c.capiBaseURL, url.PathEscape(id))
+	u, err := safeurl.JoinPathWithHostPrefix(c.capiBaseURL, "agents", "sessions", id)
+	if err != nil {
+		return nil, err
+	}
 
-	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
+	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), http.NoBody)
 	if err != nil {
 		return nil, err
 	}
@@ -338,9 +341,12 @@ func (c *CAPIClient) GetSessionLogs(ctx context.Context, id string) ([]byte, err
 		return nil, fmt.Errorf("missing session ID")
 	}
 
-	url := fmt.Sprintf("%s/agents/sessions/%s/logs", c.capiBaseURL, url.PathEscape(id))
+	u, err := safeurl.JoinPathWithHostPrefix(c.capiBaseURL, "agents", "sessions", id, "logs")
+	if err != nil {
+		return nil, err
+	}
 
-	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
+	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), http.NoBody)
 	if err != nil {
 		return nil, err
 	}
@@ -371,9 +377,12 @@ func (c *CAPIClient) ListSessionsByResourceID(ctx context.Context, resourceType
 		return nil, nil
 	}
 
-	url := fmt.Sprintf("%s/agents/resource/%s/%d", c.capiBaseURL, url.PathEscape(resourceType), resourceID)
+	u, err := safeurl.JoinPathWithHostPrefix(c.capiBaseURL, "agents", "resource", resourceType, strconv.FormatInt(resourceID, 10))
+	if err != nil {
+		return nil, err
+	}
 
-	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
+	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), http.NoBody)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/api/http.go b/pkg/cmd/api/http.go
--- a/pkg/cmd/api/http.go
+++ b/pkg/cmd/api/http.go
@@ -21,6 +21,8 @@ func httpRequest(client *http.Client, hostname string, method string, p string,
 	} else if isGraphQL {
 		requestURL = ghinstance.GraphQLEndpoint(hostname)
 	} else {
+		// Note that the gh api command takes the path verbatim from the user, so we
+		// intentionally do not route it through safeurl and do not escape it here.
 		requestURL = ghinstance.RESTPrefix(hostname) + strings.TrimPrefix(p, "/")
 	}
 
diff --git a/pkg/cmd/auth/shared/login_flow.go b/pkg/cmd/auth/shared/login_flow.go
--- a/pkg/cmd/auth/shared/login_flow.go
+++ b/pkg/cmd/auth/shared/login_flow.go
@@ -14,6 +14,7 @@ import (
 	"github.com/cli/cli/v2/internal/authflow"
 	"github.com/cli/cli/v2/internal/browser"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/ssh-key/add"
 	"github.com/cli/cli/v2/pkg/iostreams"
 	"github.com/cli/cli/v2/pkg/ssh"
@@ -258,8 +259,11 @@ func GetCurrentLogin(httpClient httpClient, hostname, authToken string) (string,
 	result := struct {
 		Data struct{ Viewer struct{ Login string } }
 	}{}
-	apiEndpoint := ghinstance.GraphQLEndpoint(hostname)
-	req, err := http.NewRequest("POST", apiEndpoint, bytes.NewBuffer(reqBody))
+	apiEndpoint, err := safeurl.JoinPathWithHostPrefix(ghinstance.GraphQLEndpoint(hostname))
+	if err != nil {
+		return "", err
+	}
+	req, err := http.NewRequest("POST", apiEndpoint.String(), bytes.NewBuffer(reqBody))
 	if err != nil {
 		return "", err
 	}
diff --git a/pkg/cmd/auth/shared/oauth_scopes.go b/pkg/cmd/auth/shared/oauth_scopes.go
--- a/pkg/cmd/auth/shared/oauth_scopes.go
+++ b/pkg/cmd/auth/shared/oauth_scopes.go
@@ -8,6 +8,7 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 type MissingScopesError struct {
@@ -33,9 +34,12 @@ type httpClient interface {
 
 // GetScopes performs a GitHub API request and returns the value of the X-Oauth-Scopes header.
 func GetScopes(httpClient httpClient, hostname, authToken string) (string, error) {
-	apiEndpoint := ghinstance.RESTPrefix(hostname)
+	apiEndpoint, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(hostname))
+	if err != nil {
+		return "", err
+	}
 
-	req, err := http.NewRequest("GET", apiEndpoint, nil)
+	req, err := http.NewRequest("GET", apiEndpoint.String(), nil)
 	if err != nil {
 		return "", err
 	}
diff --git a/pkg/cmd/cache/delete/delete.go b/pkg/cmd/cache/delete/delete.go
--- a/pkg/cmd/cache/delete/delete.go
+++ b/pkg/cmd/cache/delete/delete.go
@@ -4,12 +4,12 @@ import (
 	"errors"
 	"fmt"
 	"net/http"
-	"net/url"
 	"strconv"
 
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmd/cache/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -203,8 +203,11 @@ func deleteCaches(opts *DeleteOptions, client *api.Client, repo ghrepo.Interface
 
 func deleteCacheByID(client *api.Client, repo ghrepo.Interface, id int64) error {
 	// returns HTTP 204 (NO CONTENT) on success
-	path := fmt.Sprintf("repos/%s/actions/caches/%d", ghrepo.FullName(repo), id)
-	return client.REST(repo.RepoHost(), "DELETE", path, nil, nil)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "caches", strconv.FormatInt(id, 10))
+	if err != nil {
+		return err
+	}
+	return client.REST(repo.RepoHost(), "DELETE", path.String(), nil, nil)
 }
 
 // deleteCacheByKey deletes cache entries by given key (and optional ref) and
@@ -214,12 +217,16 @@ func deleteCacheByID(client *api.Client, repo ghrepo.Interface, id int64) error
 // entry. There may be more than one entries with the same key/ref combination,
 // but those entries will have different IDs.
 func deleteCacheByKey(client *api.Client, repo ghrepo.Interface, key, ref string) (int, error) {
-	path := fmt.Sprintf("repos/%s/actions/caches?key=%s", ghrepo.FullName(repo), url.QueryEscape(key))
+	u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "caches")
+	if err != nil {
+		return 0, err
+	}
+	u.SetQuery("key", key)
 	if ref != "" {
-		path += fmt.Sprintf("&ref=%s", url.QueryEscape(ref))
+		u.SetQuery("ref", ref)
 	}
 	var payload shared.CachePayload
-	err := client.REST(repo.RepoHost(), "DELETE", path, nil, &payload)
+	err = client.REST(repo.RepoHost(), "DELETE", u.String(), nil, &payload)
 	if err != nil {
 		return 0, err
 	}
diff --git a/pkg/cmd/cache/shared/shared.go b/pkg/cmd/cache/shared/shared.go
--- a/pkg/cmd/cache/shared/shared.go
+++ b/pkg/cmd/cache/shared/shared.go
@@ -1,12 +1,12 @@
 package shared
 
 import (
-	"fmt"
-	"net/url"
+	"strconv"
 	"time"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 )
 
@@ -46,36 +46,40 @@ type GetCachesOptions struct {
 // Return a list of caches for a repository. Pass a negative limit to request
 // all pages from the API until all caches have been fetched.
 func GetCaches(client *api.Client, repo ghrepo.Interface, opts GetCachesOptions) (*CachePayload, error) {
-	path := fmt.Sprintf("repos/%s/actions/caches", ghrepo.FullName(repo))
+	u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "caches")
+	if err != nil {
+		return nil, err
+	}
 
 	perPage := 100
 	if opts.Limit > 0 && opts.Limit < 100 {
 		perPage = opts.Limit
 	}
-	path += fmt.Sprintf("?per_page=%d", perPage)
+	u.SetQuery("per_page", strconv.Itoa(perPage))
 
 	if opts.Sort != "" {
-		path += fmt.Sprintf("&sort=%s", opts.Sort)
+		u.SetQuery("sort", opts.Sort)
 	}
 	if opts.Order != "" {
-		path += fmt.Sprintf("&direction=%s", opts.Order)
+		u.SetQuery("direction", opts.Order)
 	}
 	if opts.Key != "" {
-		path += fmt.Sprintf("&key=%s", url.QueryEscape(opts.Key))
+		u.SetQuery("key", opts.Key)
 	}
 	if opts.Ref != "" {
-		path += fmt.Sprintf("&ref=%s", url.QueryEscape(opts.Ref))
+		u.SetQuery("ref", opts.Ref)
 	}
+	var pageURL safeurl.SafeURL = u
 
 	var result *CachePayload
 pagination:
-	for path != "" {
+	for pageURL.String() != "" {
 		var response CachePayload
-		var err error
-		path, err = client.RESTWithNext(repo.RepoHost(), "GET", path, nil, &response)
+		next, err := client.RESTWithNext(repo.RepoHost(), "GET", pageURL.String(), nil, &response)
 		if err != nil {
 			return nil, err
 		}
+		pageURL = safeurl.NewImmutableSafeURL(next)
 
 		if result == nil {
 			result = &response
diff --git a/pkg/cmd/codespace/common.go b/pkg/cmd/codespace/common.go
--- a/pkg/cmd/codespace/common.go
+++ b/pkg/cmd/codespace/common.go
@@ -18,6 +18,7 @@ import (
 	clicontext "github.com/cli/cli/v2/context"
 	"github.com/cli/cli/v2/internal/browser"
 	"github.com/cli/cli/v2/internal/codespaces/api"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/iostreams"
 	"github.com/spf13/cobra"
 	"golang.org/x/term"
@@ -251,6 +252,12 @@ func addDeprecatedRepoShorthand(cmd *cobra.Command, target *string) error {
 	return nil
 }
 
+// validateNWO returns an error if nwo is not a valid "owner/repo" repository reference.
+func validateNWO(nwo string) error {
+	_, _, err := safeurl.RepoPartsFromNWO(nwo)
+	return err
+}
+
 // filterCodespacesByRepoOwner filters a list of codespaces by the owner of the repository.
 func filterCodespacesByRepoOwner(codespaces []*api.Codespace, repoOwner string) []*api.Codespace {
 	filtered := make([]*api.Codespace, 0, len(codespaces))
diff --git a/pkg/cmd/codespace/create.go b/pkg/cmd/codespace/create.go
--- a/pkg/cmd/codespace/create.go
+++ b/pkg/cmd/codespace/create.go
@@ -88,6 +88,11 @@ func newCreateCmd(app *App) *cobra.Command {
 		Short: "Create a codespace",
 		Args:  noArgsConstraint,
 		PreRunE: func(cmd *cobra.Command, args []string) error {
+			if opts.repo != "" {
+				if err := validateNWO(opts.repo); err != nil {
+					return cmdutil.FlagErrorf("invalid value for --repo: %v", err)
+				}
+			}
 			return cmdutil.MutuallyExclusive(
 				"using --web with --display-name, --idle-timeout, or --retention-period is not supported",
 				opts.useWeb,
diff --git a/pkg/cmd/codespace/list.go b/pkg/cmd/codespace/list.go
--- a/pkg/cmd/codespace/list.go
+++ b/pkg/cmd/codespace/list.go
@@ -35,6 +35,12 @@ func newListCmd(app *App) *cobra.Command {
 		Aliases: []string{"ls"},
 		Args:    noArgsConstraint,
 		PreRunE: func(cmd *cobra.Command, args []string) error {
+			if opts.repo != "" {
+				if err := validateNWO(opts.repo); err != nil {
+					return cmdutil.FlagErrorf("invalid value for --repo: %v", err)
+				}
+			}
+
 			if err := cmdutil.MutuallyExclusive(
 				"using `--org` or `--user` with `--repo` is not allowed",
 				opts.repo != "",
diff --git a/pkg/cmd/copilot/copilot.go b/pkg/cmd/copilot/copilot.go
--- a/pkg/cmd/copilot/copilot.go
+++ b/pkg/cmd/copilot/copilot.go
@@ -23,6 +23,7 @@ import (
 	"github.com/cli/cli/v2/internal/gh/ghtelemetry"
 	"github.com/cli/cli/v2/internal/prompter"
 	"github.com/cli/cli/v2/internal/safepaths"
+	"github.com/cli/cli/v2/internal/safeurl"
 	ghzip "github.com/cli/cli/v2/internal/zip"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -250,32 +251,37 @@ func downloadCopilot(httpClient *http.Client, ios *iostreams.IOStreams, installD
 		return "", fmt.Errorf("unsupported architecture: %s (supported: x64, arm64)", arch)
 	}
 
-	var archiveURL string
 	var archiveName string
 	var isZip bool
 	switch platform {
 	case "win32":
 		archiveName = fmt.Sprintf("copilot-%s-%s.zip", platform, arch)
-		archiveURL = fmt.Sprintf("https://github.com/github/copilot-cli/releases/latest/download/%s", archiveName)
 		isZip = true
 	case "linux", "darwin":
 		archiveName = fmt.Sprintf("copilot-%s-%s.tar.gz", platform, arch)
-		archiveURL = fmt.Sprintf("https://github.com/github/copilot-cli/releases/latest/download/%s", archiveName)
 	default:
 		return "", fmt.Errorf("unsupported platform: %s (supported: linux, darwin, windows)", platform)
 	}
 
-	checksumsURL := "https://github.com/github/copilot-cli/releases/latest/download/SHA256SUMS.txt"
+	archiveURL, err := safeurl.JoinPathWithHostPrefix("https://github.com/", "github", "copilot-cli", "releases", "latest", "download", archiveName)
+	if err != nil {
+		return "", err
+	}
+
+	checksumsURL, err := safeurl.JoinPathWithHostPrefix("https://github.com/", "github", "copilot-cli", "releases", "latest", "download", "SHA256SUMS.txt")
+	if err != nil {
+		return "", err
+	}
 
 	expectedChecksum, err := fetchExpectedChecksum(httpClient, checksumsURL, archiveName)
 	if err != nil {
 		return "", fmt.Errorf("failed to fetch checksums: %w", err)
 	}
 
-	ios.StartProgressIndicatorWithLabel(fmt.Sprintf("Downloading Copilot CLI from %s", archiveURL))
+	ios.StartProgressIndicatorWithLabel(fmt.Sprintf("Downloading Copilot CLI from %s", archiveURL.String()))
 	defer ios.StopProgressIndicator()
 
-	resp, err := httpClient.Get(archiveURL)
+	resp, err := httpClient.Get(archiveURL.String())
 	if err != nil {
 		return "", fmt.Errorf("failed to download: %w", err)
 	}
@@ -333,8 +339,8 @@ func downloadCopilot(httpClient *http.Client, ios *iostreams.IOStreams, installD
 }
 
 // fetchExpectedChecksum downloads the SHA256SUMS.txt file and returns the expected checksum for the given archive name.
-func fetchExpectedChecksum(httpClient *http.Client, checksumsURL, archiveName string) (string, error) {
-	resp, err := httpClient.Get(checksumsURL)
+func fetchExpectedChecksum(httpClient *http.Client, checksumsURL safeurl.SafeURL, archiveName string) (string, error) {
+	resp, err := httpClient.Get(checksumsURL.String())
 	if err != nil {
 		return "", err
 	}
diff --git a/pkg/cmd/extension/http.go b/pkg/cmd/extension/http.go
--- a/pkg/cmd/extension/http.go
+++ b/pkg/cmd/extension/http.go
@@ -3,19 +3,22 @@ package extension
 import (
 	"encoding/json"
 	"errors"
-	"fmt"
 	"io"
 	"net/http"
 	"os"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 func repoExists(httpClient *http.Client, repo ghrepo.Interface) (bool, error) {
-	url := fmt.Sprintf("%srepos/%s/%s", ghinstance.RESTPrefix(repo.RepoHost()), repo.RepoOwner(), repo.RepoName())
-	req, err := http.NewRequest("GET", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName())
+	if err != nil {
+		return false, err
+	}
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return false, err
 	}
@@ -37,10 +40,11 @@ func repoExists(httpClient *http.Client, repo ghrepo.Interface) (bool, error) {
 }
 
 func hasScript(httpClient *http.Client, repo ghrepo.Interface) (bool, error) {
-	path := fmt.Sprintf("repos/%s/%s/contents/%s",
-		repo.RepoOwner(), repo.RepoName(), repo.RepoName())
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest("GET", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "contents", repo.RepoName())
+	if err != nil {
+		return false, err
+	}
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return false, err
 	}
@@ -74,9 +78,9 @@ type release struct {
 }
 
 // downloadAsset downloads a single asset to the given file path.
-func downloadAsset(httpClient *http.Client, asset releaseAsset, destPath string) (downloadErr error) {
+func downloadAsset(httpClient *http.Client, assetURL safeurl.SafeURL, destPath string) (downloadErr error) {
 	var req *http.Request
-	if req, downloadErr = http.NewRequest("GET", asset.APIURL, nil); downloadErr != nil {
+	if req, downloadErr = http.NewRequest("GET", assetURL.String(), nil); downloadErr != nil {
 		return
 	}
 
@@ -113,9 +117,11 @@ var repositoryNotFoundErr = errors.New("repository not found")
 
 // fetchLatestRelease finds the latest published release for a repository.
 func fetchLatestRelease(httpClient *http.Client, baseRepo ghrepo.Interface) (*release, error) {
-	path := fmt.Sprintf("repos/%s/%s/releases/latest", baseRepo.RepoOwner(), baseRepo.RepoName())
-	url := ghinstance.RESTPrefix(baseRepo.RepoHost()) + path
-	req, err := http.NewRequest("GET", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(baseRepo.RepoHost()), "repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "releases", "latest")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -149,10 +155,11 @@ func fetchLatestRelease(httpClient *http.Client, baseRepo ghrepo.Interface) (*re
 
 // fetchReleaseFromTag finds release by tag name for a repository
 func fetchReleaseFromTag(httpClient *http.Client, baseRepo ghrepo.Interface, tagName string) (*release, error) {
-	fullRepoName := fmt.Sprintf("%s/%s", baseRepo.RepoOwner(), baseRepo.RepoName())
-	path := fmt.Sprintf("repos/%s/releases/tags/%s", fullRepoName, tagName)
-	url := ghinstance.RESTPrefix(baseRepo.RepoHost()) + path
-	req, err := http.NewRequest("GET", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(baseRepo.RepoHost()), "repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "releases", "tags", tagName)
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -186,9 +193,11 @@ func fetchReleaseFromTag(httpClient *http.Client, baseRepo ghrepo.Interface, tag
 
 // fetchCommitSHA finds full commit SHA from a target ref in a repo
 func fetchCommitSHA(httpClient *http.Client, baseRepo ghrepo.Interface, targetRef string) (string, error) {
-	path := fmt.Sprintf("repos/%s/%s/commits/%s", baseRepo.RepoOwner(), baseRepo.RepoName(), targetRef)
-	url := ghinstance.RESTPrefix(baseRepo.RepoHost()) + path
-	req, err := http.NewRequest("GET", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(baseRepo.RepoHost()), "repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "commits", targetRef)
+	if err != nil {
+		return "", err
+	}
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return "", err
 	}
diff --git a/pkg/cmd/extension/manager.go b/pkg/cmd/extension/manager.go
--- a/pkg/cmd/extension/manager.go
+++ b/pkg/cmd/extension/manager.go
@@ -20,6 +20,7 @@ import (
 	"github.com/cli/cli/v2/internal/config"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/extensions"
 	"github.com/cli/cli/v2/pkg/findsh"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -346,7 +347,7 @@ func (m *Manager) installBin(repo ghrepo.Interface, target string) error {
 	binPath := filepath.Join(targetDir, name)
 	binPath += ext
 
-	err = downloadAsset(m.client, *asset, binPath)
+	err = downloadAsset(m.client, safeurl.NewImmutableSafeURL(asset.APIURL), binPath)
 	if err != nil {
 		return fmt.Errorf("failed to download asset %s: %w", asset.Name, err)
 	}
diff --git a/pkg/cmd/gist/create/create.go b/pkg/cmd/gist/create/create.go
--- a/pkg/cmd/gist/create/create.go
+++ b/pkg/cmd/gist/create/create.go
@@ -18,6 +18,7 @@ import (
 	"github.com/cli/cli/v2/internal/browser"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmd/gist/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -272,8 +273,11 @@ func createGist(client *http.Client, hostname, description string, public bool,
 		return nil, err
 	}
 
-	u := ghinstance.RESTPrefix(hostname) + "gists"
-	req, err := http.NewRequest(http.MethodPost, u, requestBody)
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(hostname), "gists")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodPost, u.String(), requestBody)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/gist/delete/delete.go b/pkg/cmd/gist/delete/delete.go
--- a/pkg/cmd/gist/delete/delete.go
+++ b/pkg/cmd/gist/delete/delete.go
@@ -10,6 +10,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/gist/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -142,8 +143,11 @@ func deleteRun(opts *DeleteOptions) error {
 }
 
 func deleteGist(apiClient *api.Client, hostname string, gistID string) error {
-	path := "gists/" + gistID
-	err := apiClient.REST(hostname, "DELETE", path, nil, nil)
+	path, err := safeurl.JoinPath("gists", gistID)
+	if err != nil {
+		return err
+	}
+	err = apiClient.REST(hostname, "DELETE", path.String(), nil, nil)
 	if err != nil {
 		var httpErr api.HTTPError
 		if errors.As(err, &httpErr) && httpErr.StatusCode == 404 {
diff --git a/pkg/cmd/gist/edit/edit.go b/pkg/cmd/gist/edit/edit.go
--- a/pkg/cmd/gist/edit/edit.go
+++ b/pkg/cmd/gist/edit/edit.go
@@ -16,6 +16,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/gist/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -287,7 +288,7 @@ func editRun(opts *EditOptions) error {
 		file := gist.Files[filename]
 		if file.Truncated {
 			if _, alreadyEdited := filesToUpdate[filename]; !alreadyEdited {
-				fullContent, err := shared.GetRawGistFile(client, file.RawURL)
+				fullContent, err := shared.GetRawGistFile(client, safeurl.NewImmutableSafeURL(file.RawURL))
 				if err != nil {
 					return err
 				}
@@ -404,8 +405,11 @@ func updateGist(apiClient *api.Client, hostname string, gist gistToUpdate) error
 	requestBody := bytes.NewReader(requestByte)
 	result := shared.Gist{}
 
-	path := "gists/" + gist.id
-	err = apiClient.REST(hostname, "POST", path, requestBody, &result)
+	path, err := safeurl.JoinPath("gists", gist.id)
+	if err != nil {
+		return err
+	}
+	err = apiClient.REST(hostname, "POST", path.String(), requestBody, &result)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/gist/rename/rename.go b/pkg/cmd/gist/rename/rename.go
--- a/pkg/cmd/gist/rename/rename.go
+++ b/pkg/cmd/gist/rename/rename.go
@@ -11,6 +11,7 @@ import (
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/gh"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/gist/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -119,7 +120,10 @@ func updateGist(apiClient *api.Client, hostname string, gist *shared.Gist) error
 		Files:       gist.Files,
 	}
 
-	path := "gists/" + gist.ID
+	path, err := safeurl.JoinPath("gists", gist.ID)
+	if err != nil {
+		return err
+	}
 
 	requestByte, err := json.Marshal(body)
 	if err != nil {
@@ -130,7 +134,7 @@ func updateGist(apiClient *api.Client, hostname string, gist *shared.Gist) error
 
 	result := shared.Gist{}
 
-	err = apiClient.REST(hostname, "POST", path, requestBody, &result)
+	err = apiClient.REST(hostname, "POST", path.String(), requestBody, &result)
 
 	if err != nil {
 		return err
diff --git a/pkg/cmd/gist/shared/shared.go b/pkg/cmd/gist/shared/shared.go
--- a/pkg/cmd/gist/shared/shared.go
+++ b/pkg/cmd/gist/shared/shared.go
@@ -13,6 +13,7 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/iostreams"
 	"github.com/gabriel-vasile/mimetype"
@@ -62,10 +63,13 @@ var NotFoundErr = errors.New("not found")
 
 func GetGist(client *http.Client, hostname, gistID string) (*Gist, error) {
 	gist := Gist{}
-	path := fmt.Sprintf("gists/%s", gistID)
+	path, err := safeurl.JoinPath("gists", gistID)
+	if err != nil {
+		return nil, err
+	}
 
 	apiClient := api.NewClientFromHTTP(client)
-	err := apiClient.REST(hostname, "GET", path, nil, &gist)
+	err = apiClient.REST(hostname, "GET", path.String(), nil, &gist)
 	if err != nil {
 		var httpErr api.HTTPError
 		if errors.As(err, &httpErr) && httpErr.StatusCode == 404 {
@@ -251,8 +255,8 @@ func PromptGists(prompter prompter.Prompter, client *http.Client, host string, c
 // GetRawGistFile fetches the full content of a gist file from its raw URL. The
 // bytes are external content, so they are returned as iostreams.Untrusted to
 // force callers to choose between sanitized display and raw round-tripping.
-func GetRawGistFile(httpClient *http.Client, rawURL string) (iostreams.Untrusted, error) {
-	req, err := http.NewRequest("GET", rawURL, nil)
+func GetRawGistFile(httpClient *http.Client, rawURL safeurl.SafeURL) (iostreams.Untrusted, error) {
+	req, err := http.NewRequest("GET", rawURL.String(), nil)
 	if err != nil {
 		return iostreams.Untrusted{}, err
 	}
diff --git a/pkg/cmd/gist/view/view.go b/pkg/cmd/gist/view/view.go
--- a/pkg/cmd/gist/view/view.go
+++ b/pkg/cmd/gist/view/view.go
@@ -10,6 +10,7 @@ import (
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmd/gist/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -149,7 +150,7 @@ func viewRun(opts *ViewOptions) error {
 		// path fetches the full content from the raw URL.
 		content := iostreams.NewUntrusted(gf.Content)
 		if gf.Truncated {
-			fullContent, err := shared.GetRawGistFile(client, gf.RawURL)
+			fullContent, err := shared.GetRawGistFile(client, safeurl.NewImmutableSafeURL(gf.RawURL))
 			if err != nil {
 				return err
 			}
diff --git a/pkg/cmd/gpg-key/add/http.go b/pkg/cmd/gpg-key/add/http.go
--- a/pkg/cmd/gpg-key/add/http.go
+++ b/pkg/cmd/gpg-key/add/http.go
@@ -9,14 +9,18 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 var errScopesMissing = errors.New("insufficient OAuth scopes")
 var errDuplicateKey = errors.New("key already exists")
 var errWrongFormat = errors.New("key in wrong format")
 
 func gpgKeyUpload(httpClient *http.Client, hostname string, keyFile io.Reader, title string) error {
-	url := ghinstance.RESTPrefix(hostname) + "user/gpg_keys"
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(hostname), "user", "gpg_keys")
+	if err != nil {
+		return err
+	}
 
 	keyBytes, err := io.ReadAll(keyFile)
 	if err != nil {
@@ -35,7 +39,7 @@ func gpgKeyUpload(httpClient *http.Client, hostname string, keyFile io.Reader, t
 		return err
 	}
 
-	req, err := http.NewRequest("POST", url, bytes.NewBuffer(payloadBytes))
+	req, err := http.NewRequest("POST", u.String(), bytes.NewBuffer(payloadBytes))
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/gpg-key/delete/http.go b/pkg/cmd/gpg-key/delete/http.go
--- a/pkg/cmd/gpg-key/delete/http.go
+++ b/pkg/cmd/gpg-key/delete/http.go
@@ -2,12 +2,12 @@ package delete
 
 import (
 	"encoding/json"
-	"fmt"
 	"io"
 	"net/http"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 type gpgKey struct {
@@ -16,8 +16,11 @@ type gpgKey struct {
 }
 
 func deleteGPGKey(httpClient *http.Client, host, id string) error {
-	url := fmt.Sprintf("%suser/gpg_keys/%s", ghinstance.RESTPrefix(host), id)
-	req, err := http.NewRequest("DELETE", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "user", "gpg_keys", id)
+	if err != nil {
+		return err
+	}
+	req, err := http.NewRequest("DELETE", url.String(), nil)
 	if err != nil {
 		return err
 	}
@@ -36,9 +39,12 @@ func deleteGPGKey(httpClient *http.Client, host, id string) error {
 }
 
 func getGPGKeys(httpClient *http.Client, host string) ([]gpgKey, error) {
-	resource := "user/gpg_keys"
-	url := fmt.Sprintf("%s%s?per_page=%d", ghinstance.RESTPrefix(host), resource, 100)
-	req, err := http.NewRequest("GET", url, nil)
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "user", "gpg_keys")
+	if err != nil {
+		return nil, err
+	}
+	u.SetQuery("per_page", "100")
+	req, err := http.NewRequest("GET", u.String(), nil)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/gpg-key/list/http.go b/pkg/cmd/gpg-key/list/http.go
--- a/pkg/cmd/gpg-key/list/http.go
+++ b/pkg/cmd/gpg-key/list/http.go
@@ -3,14 +3,14 @@ package list
 import (
 	"encoding/json"
 	"errors"
-	"fmt"
 	"io"
 	"net/http"
 	"strings"
 	"time"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 var errScopes = errors.New("insufficient OAuth scopes")
@@ -38,12 +38,18 @@ type gpgKey struct {
 }
 
 func userKeys(httpClient *http.Client, host, userHandle string) ([]gpgKey, error) {
-	resource := "user/gpg_keys"
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "user", "gpg_keys")
+	if err != nil {
+		return nil, err
+	}
 	if userHandle != "" {
-		resource = fmt.Sprintf("users/%s/gpg_keys", userHandle)
+		u, err = safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "users", userHandle, "gpg_keys")
+		if err != nil {
+			return nil, err
+		}
 	}
-	url := fmt.Sprintf("%s%s?per_page=%d", ghinstance.RESTPrefix(host), resource, 100)
-	req, err := http.NewRequest("GET", url, nil)
+	u.SetQuery("per_page", "100")
+	req, err := http.NewRequest("GET", u.String(), nil)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/label/create.go b/pkg/cmd/label/create.go
--- a/pkg/cmd/label/create.go
+++ b/pkg/cmd/label/create.go
@@ -13,6 +13,7 @@ import (
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
 	"github.com/spf13/cobra"
@@ -127,7 +128,10 @@ func createRun(opts *createOptions) error {
 
 func createLabel(client *http.Client, repo ghrepo.Interface, opts *createOptions) error {
 	apiClient := api.NewClientFromHTTP(client)
-	path := fmt.Sprintf("repos/%s/%s/labels", repo.RepoOwner(), repo.RepoName())
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "labels")
+	if err != nil {
+		return err
+	}
 	requestByte, err := json.Marshal(map[string]string{
 		"name":        opts.Name,
 		"description": opts.Description,
@@ -137,7 +141,7 @@ func createLabel(client *http.Client, repo ghrepo.Interface, opts *createOptions
 		return err
 	}
 	requestBody := bytes.NewReader(requestByte)
-	err = apiClient.REST(repo.RepoHost(), "POST", path, requestBody, nil)
+	err = apiClient.REST(repo.RepoHost(), "POST", path.String(), requestBody, nil)
 
 	if httpError, ok := err.(api.HTTPError); ok && isLabelAlreadyExistsError(httpError) {
 		err = errLabelAlreadyExists
@@ -156,7 +160,10 @@ func createLabel(client *http.Client, repo ghrepo.Interface, opts *createOptions
 }
 
 func updateLabel(apiClient *api.Client, repo ghrepo.Interface, opts *editOptions) error {
-	path := fmt.Sprintf("repos/%s/%s/labels/%s", repo.RepoOwner(), repo.RepoName(), opts.Name)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "labels", opts.Name)
+	if err != nil {
+		return err
+	}
 	properties := map[string]string{}
 	if opts.Description != "" {
 		properties["description"] = opts.Description
@@ -172,7 +179,7 @@ func updateLabel(apiClient *api.Client, repo ghrepo.Interface, opts *editOptions
 		return err
 	}
 	requestBody := bytes.NewReader(requestByte)
-	err = apiClient.REST(repo.RepoHost(), "PATCH", path, requestBody, nil)
+	err = apiClient.REST(repo.RepoHost(), "PATCH", path.String(), requestBody, nil)
 
 	if httpError, ok := err.(api.HTTPError); ok && isLabelAlreadyExistsError(httpError) {
 		err = errLabelAlreadyExists
diff --git a/pkg/cmd/label/delete.go b/pkg/cmd/label/delete.go
--- a/pkg/cmd/label/delete.go
+++ b/pkg/cmd/label/delete.go
@@ -6,6 +6,7 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
 	"github.com/spf13/cobra"
@@ -94,7 +95,10 @@ func deleteRun(opts *deleteOptions) error {
 
 func deleteLabel(client *http.Client, repo ghrepo.Interface, name string) error {
 	apiClient := api.NewClientFromHTTP(client)
-	path := fmt.Sprintf("repos/%s/%s/labels/%s", repo.RepoOwner(), repo.RepoName(), name)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "labels", name)
+	if err != nil {
+		return err
+	}
 
-	return apiClient.REST(repo.RepoHost(), "DELETE", path, nil, nil)
+	return apiClient.REST(repo.RepoHost(), "DELETE", path.String(), nil, nil)
 }
diff --git a/pkg/cmd/pr/diff/diff.go b/pkg/cmd/pr/diff/diff.go
--- a/pkg/cmd/pr/diff/diff.go
+++ b/pkg/cmd/pr/diff/diff.go
@@ -9,13 +9,15 @@ import (
 	"net/http"
 	"path"
 	"regexp"
+	"strconv"
 	"strings"
 
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/browser"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmd/pr/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -209,18 +211,16 @@ func diffRun(opts *DiffOptions) error {
 }
 
 func fetchDiff(httpClient *http.Client, baseRepo ghrepo.Interface, prNumber int, asPatch bool) (io.ReadCloser, error) {
-	url := fmt.Sprintf(
-		"%srepos/%s/pulls/%d",
-		ghinstance.RESTPrefix(baseRepo.RepoHost()),
-		ghrepo.FullName(baseRepo),
-		prNumber,
-	)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(baseRepo.RepoHost()), "repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "pulls", strconv.Itoa(prNumber))
+	if err != nil {
+		return nil, err
+	}
 	acceptType := "application/vnd.github.v3.diff"
 	if asPatch {
 		acceptType = "application/vnd.github.v3.patch"
 	}
 
-	req, err := http.NewRequest("GET", url, nil)
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/release/create/create.go b/pkg/cmd/release/create/create.go
--- a/pkg/cmd/release/create/create.go
+++ b/pkg/cmd/release/create/create.go
@@ -13,6 +13,7 @@ import (
 	"github.com/cli/cli/v2/git"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmd/release/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -534,7 +535,7 @@ func createRun(opts *CreateOptions) error {
 		if !draftWhileUploading {
 			return err
 		}
-		if cleanupErr := deleteRelease(httpClient, newRelease); cleanupErr != nil {
+		if cleanupErr := deleteRelease(httpClient, safeurl.NewImmutableSafeURL(newRelease.APIURL)); cleanupErr != nil {
 			return fmt.Errorf("%w\ncleaning up draft failed: %v", err, cleanupErr)
 		}
 		return err
@@ -547,14 +548,14 @@ func createRun(opts *CreateOptions) error {
 		}
 
 		opts.IO.StartProgressIndicator()
-		err = shared.ConcurrentUpload(httpClient, uploadURL, opts.Concurrency, opts.Assets)
+		err = shared.ConcurrentUpload(httpClient, safeurl.NewImmutableSafeURL(uploadURL), opts.Concurrency, opts.Assets)
 		opts.IO.StopProgressIndicator()
 		if err != nil {
 			return cleanupDraftRelease(err)
 		}
 
 		if draftWhileUploading {
-			rel, err := publishRelease(httpClient, newRelease.APIURL, opts.DiscussionCategory, opts.IsLatest)
+			rel, err := publishRelease(httpClient, safeurl.NewImmutableSafeURL(newRelease.APIURL), opts.DiscussionCategory, opts.IsLatest)
 			if err != nil {
 				return cleanupDraftRelease(err)
 			}
diff --git a/pkg/cmd/release/create/http.go b/pkg/cmd/release/create/http.go
--- a/pkg/cmd/release/create/http.go
+++ b/pkg/cmd/release/create/http.go
@@ -8,13 +8,14 @@ import (
 	"fmt"
 	"io"
 	"net/http"
-	"net/url"
 	"slices"
+	"strconv"
 	"strings"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/release/shared"
 	"github.com/shurcooL/githubv4"
 
@@ -60,9 +61,12 @@ func remoteTagExists(httpClient *http.Client, repo ghrepo.Interface, tagName str
 }
 
 func getTags(httpClient *http.Client, repo ghrepo.Interface, limit int) ([]tag, error) {
-	path := fmt.Sprintf("repos/%s/%s/tags?per_page=%d", repo.RepoOwner(), repo.RepoName(), limit)
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest("GET", url, nil)
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "tags")
+	if err != nil {
+		return nil, err
+	}
+	u.SetQuery("per_page", strconv.Itoa(limit))
+	req, err := http.NewRequest("GET", u.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -106,9 +110,11 @@ func generateReleaseNotes(httpClient *http.Client, repo ghrepo.Interface, tagNam
 		return nil, err
 	}
 
-	path := fmt.Sprintf("repos/%s/%s/releases/generate-notes", repo.RepoOwner(), repo.RepoName())
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest("POST", url, bytes.NewBuffer(bodyBytes))
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "releases", "generate-notes")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest("POST", url.String(), bytes.NewBuffer(bodyBytes))
 	if err != nil {
 		return nil, err
 	}
@@ -142,9 +148,11 @@ func generateReleaseNotes(httpClient *http.Client, repo ghrepo.Interface, tagNam
 }
 
 func publishedReleaseExists(httpClient *http.Client, repo ghrepo.Interface, tagName string) (bool, error) {
-	path := fmt.Sprintf("repos/%s/%s/releases/tags/%s", repo.RepoOwner(), repo.RepoName(), url.PathEscape(tagName))
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest("HEAD", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "releases", "tags", tagName)
+	if err != nil {
+		return false, err
+	}
+	req, err := http.NewRequest("HEAD", url.String(), nil)
 	if err != nil {
 		return false, err
 	}
@@ -172,9 +180,11 @@ func createRelease(httpClient *http.Client, repo ghrepo.Interface, params map[st
 		return nil, err
 	}
 
-	path := fmt.Sprintf("repos/%s/%s/releases", repo.RepoOwner(), repo.RepoName())
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest("POST", url, bytes.NewBuffer(bodyBytes))
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "releases")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest("POST", url.String(), bytes.NewBuffer(bodyBytes))
 	if err != nil {
 		return nil, err
 	}
@@ -220,7 +230,7 @@ func createRelease(httpClient *http.Client, repo ghrepo.Interface, params map[st
 	return &newRelease, err
 }
 
-func publishRelease(httpClient *http.Client, releaseURL string, discussionCategory string, isLatest *bool) (*shared.Release, error) {
+func publishRelease(httpClient *http.Client, releaseURL safeurl.SafeURL, discussionCategory string, isLatest *bool) (*shared.Release, error) {
 	params := map[string]interface{}{"draft": false}
 	if discussionCategory != "" {
 		params["discussion_category_name"] = discussionCategory
@@ -234,7 +244,7 @@ func publishRelease(httpClient *http.Client, releaseURL string, discussionCatego
 	if err != nil {
 		return nil, err
 	}
-	req, err := http.NewRequest("PATCH", releaseURL, bytes.NewBuffer(bodyBytes))
+	req, err := http.NewRequest("PATCH", releaseURL.String(), bytes.NewBuffer(bodyBytes))
 	if err != nil {
 		return nil, err
 	}
@@ -261,8 +271,8 @@ func publishRelease(httpClient *http.Client, releaseURL string, discussionCatego
 	return &release, err
 }
 
-func deleteRelease(httpClient *http.Client, release *shared.Release) error {
-	req, err := http.NewRequest("DELETE", release.APIURL, nil)
+func deleteRelease(httpClient *http.Client, releaseURL safeurl.SafeURL) error {
+	req, err := http.NewRequest("DELETE", releaseURL.String(), nil)
 	if err != nil {
 		return err
 	}
@@ -314,14 +324,18 @@ func isNewRelease(httpClient *http.Client, repo ghrepo.Interface) (bool, error)
 	}
 
 	tagName := release.TagName
-	path := fmt.Sprintf("repos/%s/%s/compare/%s...HEAD?per_page=1", repo.RepoOwner(), repo.RepoName(), tagName)
+	u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "compare", tagName+"...HEAD")
+	if err != nil {
+		return false, err
+	}
+	u.SetQuery("per_page", "1")
 
 	var comparisonStatus struct {
 		Status string `json:"status"`
 	}
 
 	apiClient := api.NewClientFromHTTP(httpClient)
-	if err := apiClient.REST(repo.RepoHost(), "GET", path, nil, &comparisonStatus); err != nil {
+	if err := apiClient.REST(repo.RepoHost(), "GET", u.String(), nil, &comparisonStatus); err != nil {
 		return false, err
 	}
 
diff --git a/pkg/cmd/release/delete-asset/delete_asset.go b/pkg/cmd/release/delete-asset/delete_asset.go
--- a/pkg/cmd/release/delete-asset/delete_asset.go
+++ b/pkg/cmd/release/delete-asset/delete_asset.go
@@ -7,6 +7,7 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/release/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -96,7 +97,7 @@ func deleteAssetRun(opts *DeleteAssetOptions) error {
 		return fmt.Errorf("asset %s not found in release %s", opts.AssetName, release.TagName)
 	}
 
-	err = deleteAsset(httpClient, assetURL)
+	err = deleteAsset(httpClient, safeurl.NewImmutableSafeURL(assetURL))
 	if err != nil {
 		return err
 	}
@@ -111,8 +112,8 @@ func deleteAssetRun(opts *DeleteAssetOptions) error {
 	return nil
 }
 
-func deleteAsset(httpClient *http.Client, assetURL string) error {
-	req, err := http.NewRequest("DELETE", assetURL, nil)
+func deleteAsset(httpClient *http.Client, assetURL safeurl.SafeURL) error {
+	req, err := http.NewRequest("DELETE", assetURL.String(), nil)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/release/delete/delete.go b/pkg/cmd/release/delete/delete.go
--- a/pkg/cmd/release/delete/delete.go
+++ b/pkg/cmd/release/delete/delete.go
@@ -9,6 +9,7 @@ import (
 	"github.com/cli/cli/v2/git"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/release/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -92,7 +93,7 @@ func deleteRun(opts *DeleteOptions) error {
 		}
 	}
 
-	err = deleteRelease(httpClient, release.APIURL)
+	err = deleteRelease(httpClient, safeurl.NewImmutableSafeURL(release.APIURL))
 	if err != nil {
 		return err
 	}
@@ -121,8 +122,8 @@ func deleteRun(opts *DeleteOptions) error {
 	return nil
 }
 
-func deleteRelease(httpClient *http.Client, releaseURL string) error {
-	req, err := http.NewRequest("DELETE", releaseURL, nil)
+func deleteRelease(httpClient *http.Client, releaseURL safeurl.SafeURL) error {
+	req, err := http.NewRequest("DELETE", releaseURL.String(), nil)
 	if err != nil {
 		return err
 	}
@@ -140,10 +141,11 @@ func deleteRelease(httpClient *http.Client, releaseURL string) error {
 }
 
 func deleteTag(httpClient *http.Client, baseRepo ghrepo.Interface, tagName string) error {
-	path := fmt.Sprintf("repos/%s/%s/git/refs/tags/%s", baseRepo.RepoOwner(), baseRepo.RepoName(), tagName)
-	url := ghinstance.RESTPrefix(baseRepo.RepoHost()) + path
-
-	req, err := http.NewRequest("DELETE", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(baseRepo.RepoHost()), "repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "git", "refs", fmt.Sprintf("tags/%s", tagName))
+	if err != nil {
+		return err
+	}
+	req, err := http.NewRequest("DELETE", url.String(), nil)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/release/download/download.go b/pkg/cmd/release/download/download.go
--- a/pkg/cmd/release/download/download.go
+++ b/pkg/cmd/release/download/download.go
@@ -17,6 +17,7 @@ import (
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/release/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -233,7 +234,15 @@ func downloadRun(opts *DownloadOptions) error {
 		isTTY:        opts.IO.IsStdoutTTY(),
 	}
 
-	return downloadAssets(&dest, httpClient, toDownload, opts.Concurrency, isArchive, opts.IO)
+	targets := make([]downloadTarget, len(toDownload))
+	for i, a := range toDownload {
+		targets[i] = downloadTarget{
+			url:  safeurl.NewImmutableSafeURL(a.APIURL),
+			name: a.Name,
+		}
+	}
+
+	return downloadAssets(&dest, httpClient, targets, opts.Concurrency, isArchive, opts.IO)
 }
 
 func matchAny(patterns []string, name string) bool {
@@ -245,12 +254,17 @@ func matchAny(patterns []string, name string) bool {
 	return false
 }
 
-func downloadAssets(dest *destinationWriter, httpClient *http.Client, toDownload []shared.ReleaseAsset, numWorkers int, isArchive bool, io *iostreams.IOStreams) error {
+type downloadTarget struct {
+	url  safeurl.SafeURL
+	name string
+}
+
+func downloadAssets(dest *destinationWriter, httpClient *http.Client, toDownload []downloadTarget, numWorkers int, isArchive bool, io *iostreams.IOStreams) error {
 	if numWorkers == 0 {
 		return errors.New("the number of concurrent workers needs to be greater than 0")
 	}
 
-	jobs := make(chan shared.ReleaseAsset, len(toDownload))
+	jobs := make(chan downloadTarget, len(toDownload))
 	results := make(chan error, len(toDownload))
 
 	if len(toDownload) < numWorkers {
@@ -260,8 +274,8 @@ func downloadAssets(dest *destinationWriter, httpClient *http.Client, toDownload
 	for w := 1; w <= numWorkers; w++ {
 		go func() {
 			for a := range jobs {
-				io.StartProgressIndicatorWithLabel(fmt.Sprintf("Downloading %s", a.Name))
-				results <- downloadAsset(dest, httpClient, a.APIURL, a.Name, isArchive)
+				io.StartProgressIndicatorWithLabel(fmt.Sprintf("Downloading %s", a.name))
+				results <- downloadAsset(dest, httpClient, a.url, a.name, isArchive)
 			}
 		}()
 	}
@@ -283,12 +297,12 @@ func downloadAssets(dest *destinationWriter, httpClient *http.Client, toDownload
 	return downloadError
 }
 
-func downloadAsset(dest *destinationWriter, httpClient *http.Client, assetURL, fileName string, isArchive bool) error {
+func downloadAsset(dest *destinationWriter, httpClient *http.Client, assetURL safeurl.SafeURL, fileName string, isArchive bool) error {
 	if err := dest.Check(fileName); err != nil {
 		return err
 	}
 
-	req, err := http.NewRequest("GET", assetURL, nil)
+	req, err := http.NewRequest("GET", assetURL.String(), nil)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/release/edit/http.go b/pkg/cmd/release/edit/http.go
--- a/pkg/cmd/release/edit/http.go
+++ b/pkg/cmd/release/edit/http.go
@@ -6,10 +6,12 @@ import (
 	"fmt"
 	"io"
 	"net/http"
+	"strconv"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/release/shared"
 	"github.com/shurcooL/githubv4"
 )
@@ -20,9 +22,11 @@ func editRelease(httpClient *http.Client, repo ghrepo.Interface, releaseID int64
 		return nil, err
 	}
 
-	path := fmt.Sprintf("repos/%s/%s/releases/%d", repo.RepoOwner(), repo.RepoName(), releaseID)
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest("PATCH", url, bytes.NewBuffer(bodyBytes))
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "releases", strconv.FormatInt(releaseID, 10))
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest("PATCH", url.String(), bytes.NewBuffer(bodyBytes))
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/release/shared/fetch.go b/pkg/cmd/release/shared/fetch.go
--- a/pkg/cmd/release/shared/fetch.go
+++ b/pkg/cmd/release/shared/fetch.go
@@ -8,13 +8,15 @@ import (
 	"io"
 	"net/http"
 	"reflect"
+	"strconv"
 	"strings"
 	"testing"
 	"time"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/httpmock"
 	"github.com/shurcooL/githubv4"
 	"github.com/stretchr/testify/assert"
@@ -136,8 +138,11 @@ type fetchResult struct {
 }
 
 func FetchRefSHA(ctx context.Context, httpClient *http.Client, repo ghrepo.Interface, tagName string) (string, error) {
-	path := fmt.Sprintf("repos/%s/%s/git/ref/tags/%s", repo.RepoOwner(), repo.RepoName(), tagName)
-	req, err := http.NewRequestWithContext(ctx, "GET", ghinstance.RESTPrefix(repo.RepoHost())+path, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "git", "ref", fmt.Sprintf("tags/%s", tagName))
+	if err != nil {
+		return "", err
+	}
+	req, err := http.NewRequestWithContext(ctx, "GET", url.String(), nil)
 	if err != nil {
 		return "", err
 	}
@@ -185,13 +190,17 @@ func DigestAlgForRef(digest string) string {
 
 // FetchRelease finds a published repository release by its tagName, or a draft release by its pending tag name.
 func FetchRelease(ctx context.Context, httpClient *http.Client, repo ghrepo.Interface, tagName string) (*Release, error) {
+	publishedURL, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "releases", "tags", tagName)
+	if err != nil {
+		return nil, err
+	}
+
 	cc, cancel := context.WithCancel(ctx)
 	results := make(chan fetchResult, 2)
 
 	// published release lookup
 	go func() {
-		path := fmt.Sprintf("repos/%s/%s/releases/tags/%s", repo.RepoOwner(), repo.RepoName(), tagName)
-		release, err := fetchReleasePath(cc, httpClient, repo.RepoHost(), path)
+		release, err := fetchReleasePath(cc, httpClient, publishedURL)
 		results <- fetchResult{release: release, error: err}
 	}()
 
@@ -226,8 +235,11 @@ func FetchRelease(ctx context.Context, httpClient *http.Client, repo ghrepo.Inte
 
 // FetchLatestRelease finds the latest published release for a repository.
 func FetchLatestRelease(ctx context.Context, httpClient *http.Client, repo ghrepo.Interface) (*Release, error) {
-	path := fmt.Sprintf("repos/%s/%s/releases/latest", repo.RepoOwner(), repo.RepoName())
-	return fetchReleasePath(ctx, httpClient, repo.RepoHost(), path)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "releases", "latest")
+	if err != nil {
+		return nil, err
+	}
+	return fetchReleasePath(ctx, httpClient, url)
 }
 
 // fetchDraftRelease returns the first draft release that has tagName as its pending tag.
@@ -259,12 +271,15 @@ func fetchDraftRelease(ctx context.Context, httpClient *http.Client, repo ghrepo
 
 	// Then, use REST to get information about the draft release. In theory, we could have fetched
 	// all the necessary information via GraphQL, but REST is safer for backwards compatibility.
-	path := fmt.Sprintf("repos/%s/%s/releases/%d", repo.RepoOwner(), repo.RepoName(), query.Repository.Release.DatabaseID)
-	return fetchReleasePath(ctx, httpClient, repo.RepoHost(), path)
+	path, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "releases", strconv.FormatInt(query.Repository.Release.DatabaseID, 10))
+	if err != nil {
+		return nil, err
+	}
+	return fetchReleasePath(ctx, httpClient, path)
 }
 
-func fetchReleasePath(ctx context.Context, httpClient *http.Client, host string, p string) (*Release, error) {
-	req, err := http.NewRequestWithContext(ctx, "GET", ghinstance.RESTPrefix(host)+p, nil)
+func fetchReleasePath(ctx context.Context, httpClient *http.Client, url safeurl.SafeURL) (*Release, error) {
+	req, err := http.NewRequestWithContext(ctx, "GET", url.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -312,7 +327,7 @@ func StubFetchRelease(t *testing.T, reg *httpmock.Registry, owner, repoName, tag
 }
 
 func StubFetchRefSHA(t *testing.T, reg *httpmock.Registry, owner, repoName, tagName, sha string) {
-	path := fmt.Sprintf("repos/%s/%s/git/ref/tags/%s", owner, repoName, tagName)
+	path := fmt.Sprintf("repos/%s/%s/git/ref/tags%%2F%s", owner, repoName, tagName)
 	reg.Register(
 		httpmock.REST("GET", path),
 		httpmock.StringResponse(fmt.Sprintf(`{"object": {"sha": "%s"}}`, sha)),
diff --git a/pkg/cmd/release/shared/upload.go b/pkg/cmd/release/shared/upload.go
--- a/pkg/cmd/release/shared/upload.go
+++ b/pkg/cmd/release/shared/upload.go
@@ -15,6 +15,7 @@ import (
 
 	"github.com/cenkalti/backoff/v4"
 	"github.com/cli/cli/v2/api"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"golang.org/x/sync/errgroup"
 )
@@ -33,7 +34,7 @@ type AssetForUpload struct {
 	MIMEType string
 	Open     func() (io.ReadCloser, error)
 
-	ExistingURL string
+	ExistingURL safeurl.SafeURL
 }
 
 func AssetsFromArgs(args []string) (assets []*AssetForUpload, err error) {
@@ -111,7 +112,7 @@ func fileExt(fn string) string {
 	return path.Ext(fn)
 }
 
-func ConcurrentUpload(httpClient httpDoer, uploadURL string, numWorkers int, assets []*AssetForUpload) error {
+func ConcurrentUpload(httpClient httpDoer, uploadURL safeurl.SafeURL, numWorkers int, assets []*AssetForUpload) error {
 	if numWorkers == 0 {
 		return errors.New("the number of concurrent workers needs to be greater than 0")
 	}
@@ -142,8 +143,8 @@ func shouldRetry(err error) bool {
 // Allow injecting backoff interval in tests.
 var retryInterval = time.Millisecond * 200
 
-func uploadWithDelete(ctx context.Context, httpClient httpDoer, uploadURL string, a AssetForUpload) error {
-	if a.ExistingURL != "" {
+func uploadWithDelete(ctx context.Context, httpClient httpDoer, uploadURL safeurl.SafeURL, a AssetForUpload) error {
+	if a.ExistingURL != nil && a.ExistingURL.String() != "" {
 		if err := deleteAsset(ctx, httpClient, a.ExistingURL); err != nil {
 			return err
 		}
@@ -158,8 +159,8 @@ func uploadWithDelete(ctx context.Context, httpClient httpDoer, uploadURL string
 	}, backoff.WithContext(backoff.WithMaxRetries(bo, 3), ctx))
 }
 
-func uploadAsset(ctx context.Context, httpClient httpDoer, uploadURL string, asset AssetForUpload) (*ReleaseAsset, error) {
-	u, err := url.Parse(uploadURL)
+func uploadAsset(ctx context.Context, httpClient httpDoer, uploadURL safeurl.SafeURL, asset AssetForUpload) (*ReleaseAsset, error) {
+	u, err := url.Parse(uploadURL.String())
 	if err != nil {
 		return nil, err
 	}
@@ -168,13 +169,16 @@ func uploadAsset(ctx context.Context, httpClient httpDoer, uploadURL string, ass
 	params.Set("label", asset.Label)
 	u.RawQuery = params.Encode()
 
+	// Since u is derived from uploadURL, an already-trusted safeurl.SafeURL, the resulting URL is safe to declare as such.
+	safeURL := safeurl.NewImmutableSafeURL(u.String())
+
 	f, err := asset.Open()
 	if err != nil {
 		return nil, err
 	}
 	defer f.Close()
 
-	req, err := http.NewRequestWithContext(ctx, "POST", u.String(), f)
+	req, err := http.NewRequestWithContext(ctx, "POST", safeURL.String(), f)
 	if err != nil {
 		return nil, err
 	}
@@ -202,8 +206,8 @@ func uploadAsset(ctx context.Context, httpClient httpDoer, uploadURL string, ass
 	return &newAsset, nil
 }
 
-func deleteAsset(ctx context.Context, httpClient httpDoer, assetURL string) error {
-	req, err := http.NewRequestWithContext(ctx, "DELETE", assetURL, nil)
+func deleteAsset(ctx context.Context, httpClient httpDoer, assetURL safeurl.SafeURL) error {
+	req, err := http.NewRequestWithContext(ctx, "DELETE", assetURL.String(), nil)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/release/upload/upload.go b/pkg/cmd/release/upload/upload.go
--- a/pkg/cmd/release/upload/upload.go
+++ b/pkg/cmd/release/upload/upload.go
@@ -9,6 +9,7 @@ import (
 
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmd/release/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -90,17 +91,12 @@ func uploadRun(opts *UploadOptions) error {
 		return err
 	}
 
-	uploadURL := release.UploadURL
-	if idx := strings.IndexRune(uploadURL, '{'); idx > 0 {
-		uploadURL = uploadURL[:idx]
-	}
-
 	var existingNames []string
 	for _, a := range opts.Assets {
 		sanitizedFileName := sanitizeFileName(a.Name)
 		for _, ea := range release.Assets {
 			if ea.Name == sanitizedFileName {
-				a.ExistingURL = ea.APIURL
+				a.ExistingURL = safeurl.NewImmutableSafeURL(ea.APIURL)
 				existingNames = append(existingNames, ea.Name)
 				break
 			}
@@ -111,8 +107,13 @@ func uploadRun(opts *UploadOptions) error {
 		return fmt.Errorf("asset under the same name already exists: %v", existingNames)
 	}
 
+	uploadURL := release.UploadURL
+	if idx := strings.IndexRune(uploadURL, '{'); idx > 0 {
+		uploadURL = uploadURL[:idx]
+	}
+
 	opts.IO.StartProgressIndicator()
-	err = shared.ConcurrentUpload(httpClient, uploadURL, opts.Concurrency, opts.Assets)
+	err = shared.ConcurrentUpload(httpClient, safeurl.NewImmutableSafeURL(uploadURL), opts.Concurrency, opts.Assets)
 	opts.IO.StopProgressIndicator()
 	if err != nil {
 		return err
diff --git a/pkg/cmd/repo/autolink/create/http.go b/pkg/cmd/repo/autolink/create/http.go
--- a/pkg/cmd/repo/autolink/create/http.go
+++ b/pkg/cmd/repo/autolink/create/http.go
@@ -4,12 +4,12 @@ import (
 	"bytes"
 	"encoding/json"
 	"errors"
-	"fmt"
 	"net/http"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/repo/autolink/shared"
 )
 
@@ -24,16 +24,18 @@ type AutolinkCreateRequest struct {
 }
 
 func (a *AutolinkCreator) Create(repo ghrepo.Interface, request AutolinkCreateRequest) (*shared.Autolink, error) {
-	path := fmt.Sprintf("repos/%s/%s/autolinks", repo.RepoOwner(), repo.RepoName())
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "autolinks")
+	if err != nil {
+		return nil, err
+	}
 
 	requestByte, err := json.Marshal(request)
 	if err != nil {
 		return nil, err
 	}
 	requestBody := bytes.NewReader(requestByte)
 
-	req, err := http.NewRequest(http.MethodPost, url, requestBody)
+	req, err := http.NewRequest(http.MethodPost, url.String(), requestBody)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/repo/autolink/delete/http.go b/pkg/cmd/repo/autolink/delete/http.go
--- a/pkg/cmd/repo/autolink/delete/http.go
+++ b/pkg/cmd/repo/autolink/delete/http.go
@@ -7,16 +7,19 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 type AutolinkDeleter struct {
 	HTTPClient *http.Client
 }
 
 func (a *AutolinkDeleter) Delete(repo ghrepo.Interface, id string) error {
-	path := fmt.Sprintf("repos/%s/%s/autolinks/%s", repo.RepoOwner(), repo.RepoName(), id)
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest(http.MethodDelete, url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "autolinks", id)
+	if err != nil {
+		return err
+	}
+	req, err := http.NewRequest(http.MethodDelete, url.String(), nil)
 	if err != nil {
 		return err
 	}
@@ -28,7 +31,7 @@ func (a *AutolinkDeleter) Delete(repo ghrepo.Interface, id string) error {
 	defer resp.Body.Close()
 
 	if resp.StatusCode == http.StatusNotFound {
-		return fmt.Errorf("error deleting autolink: HTTP 404: Perhaps you are missing admin rights to the repository? (https://api.github.com/%s)", path)
+		return fmt.Errorf("error deleting autolink: HTTP 404: Perhaps you are missing admin rights to the repository? (%s)", url)
 	} else if resp.StatusCode > 299 {
 		return api.HandleHTTPError(resp)
 	}
diff --git a/pkg/cmd/repo/autolink/list/http.go b/pkg/cmd/repo/autolink/list/http.go
--- a/pkg/cmd/repo/autolink/list/http.go
+++ b/pkg/cmd/repo/autolink/list/http.go
@@ -8,6 +8,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/repo/autolink/shared"
 )
 
@@ -16,9 +17,11 @@ type AutolinkLister struct {
 }
 
 func (a *AutolinkLister) List(repo ghrepo.Interface) ([]shared.Autolink, error) {
-	path := fmt.Sprintf("repos/%s/%s/autolinks", repo.RepoOwner(), repo.RepoName())
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest(http.MethodGet, url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "autolinks")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodGet, url.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -30,7 +33,7 @@ func (a *AutolinkLister) List(repo ghrepo.Interface) ([]shared.Autolink, error)
 	defer resp.Body.Close()
 
 	if resp.StatusCode == http.StatusNotFound {
-		return nil, fmt.Errorf("error getting autolinks: HTTP 404: Perhaps you are missing admin rights to the repository? (https://api.github.com/%s)", path)
+		return nil, fmt.Errorf("error getting autolinks: HTTP 404: Perhaps you are missing admin rights to the repository? (%s)", url)
 	} else if resp.StatusCode > 299 {
 		return nil, api.HandleHTTPError(resp)
 	}
diff --git a/pkg/cmd/repo/autolink/view/http.go b/pkg/cmd/repo/autolink/view/http.go
--- a/pkg/cmd/repo/autolink/view/http.go
+++ b/pkg/cmd/repo/autolink/view/http.go
@@ -8,6 +8,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/repo/autolink/shared"
 )
 
@@ -16,9 +17,11 @@ type AutolinkViewer struct {
 }
 
 func (a *AutolinkViewer) View(repo ghrepo.Interface, id string) (*shared.Autolink, error) {
-	path := fmt.Sprintf("repos/%s/%s/autolinks/%s", repo.RepoOwner(), repo.RepoName(), id)
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest(http.MethodGet, url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "autolinks", id)
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest(http.MethodGet, url.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -30,7 +33,7 @@ func (a *AutolinkViewer) View(repo ghrepo.Interface, id string) (*shared.Autolin
 	defer resp.Body.Close()
 
 	if resp.StatusCode == http.StatusNotFound {
-		return nil, fmt.Errorf("HTTP 404: Perhaps you are missing admin rights to the repository? (https://api.github.com/%s)", path)
+		return nil, fmt.Errorf("HTTP 404: Perhaps you are missing admin rights to the repository? (%s)", url)
 	} else if resp.StatusCode > 299 {
 		return nil, api.HandleHTTPError(resp)
 	}
diff --git a/pkg/cmd/repo/create/http.go b/pkg/cmd/repo/create/http.go
--- a/pkg/cmd/repo/create/http.go
+++ b/pkg/cmd/repo/create/http.go
@@ -8,6 +8,7 @@ import (
 	"strings"
 
 	"github.com/cli/cli/v2/api"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/shurcooL/githubv4"
 )
 
@@ -186,9 +187,15 @@ func repoCreate(client *http.Client, hostname string, input repoCreateInput) (*a
 			InitReadme:        input.InitReadme,
 		}
 
-		path := "user/repos"
+		path, err := safeurl.JoinPath("user", "repos")
+		if err != nil {
+			return nil, err
+		}
 		if isOrg {
-			path = fmt.Sprintf("orgs/%s/repos", input.OwnerLogin)
+			path, err = safeurl.JoinPath("orgs", input.OwnerLogin, "repos")
+			if err != nil {
+				return nil, err
+			}
 			inputv3.Visibility = strings.ToLower(input.Visibility)
 		}
 
@@ -254,7 +261,11 @@ func (r *ownerResponse) IsOrganization() bool {
 
 func resolveOwner(client *api.Client, hostname, orgName string) (*ownerResponse, error) {
 	var response ownerResponse
-	err := client.REST(hostname, "GET", fmt.Sprintf("users/%s", orgName), nil, &response)
+	u, err := safeurl.JoinPath("users", orgName)
+	if err != nil {
+		return nil, err
+	}
+	err = client.REST(hostname, "GET", u.String(), nil, &response)
 	return &response, err
 }
 
@@ -268,7 +279,11 @@ type teamResponse struct {
 
 func resolveOrganizationTeam(client *api.Client, hostname, orgName, teamSlug string) (*teamResponse, error) {
 	var response teamResponse
-	err := client.REST(hostname, "GET", fmt.Sprintf("orgs/%s/teams/%s", orgName, teamSlug), nil, &response)
+	u, err := safeurl.JoinPath("orgs", orgName, "teams", teamSlug)
+	if err != nil {
+		return nil, err
+	}
+	err = client.REST(hostname, "GET", u.String(), nil, &response)
 	return &response, err
 }
 
diff --git a/pkg/cmd/repo/credits/credits.go b/pkg/cmd/repo/credits/credits.go
--- a/pkg/cmd/repo/credits/credits.go
+++ b/pkg/cmd/repo/credits/credits.go
@@ -15,6 +15,7 @@ import (
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
 	"github.com/cli/cli/v2/utils"
@@ -142,9 +143,12 @@ func creditsRun(opts *CreditsOptions) error {
 
 	result := Result{}
 	body := bytes.NewBufferString("")
-	path := fmt.Sprintf("repos/%s/%s/contributors", baseRepo.RepoOwner(), baseRepo.RepoName())
+	path, err := safeurl.JoinPath("repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "contributors")
+	if err != nil {
+		return err
+	}
 
-	err = client.REST(baseRepo.RepoHost(), "GET", path, body, &result)
+	err = client.REST(baseRepo.RepoHost(), "GET", path.String(), body, &result)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/repo/delete/http.go b/pkg/cmd/repo/delete/http.go
--- a/pkg/cmd/repo/delete/http.go
+++ b/pkg/cmd/repo/delete/http.go
@@ -1,12 +1,12 @@
 package delete
 
 import (
-	"fmt"
 	"net/http"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 func deleteRepo(client *http.Client, repo ghrepo.Interface) error {
@@ -16,11 +16,12 @@ func deleteRepo(client *http.Client, repo ghrepo.Interface) error {
 		return http.ErrUseLastResponse
 	}
 
-	url := fmt.Sprintf("%srepos/%s",
-		ghinstance.RESTPrefix(repo.RepoHost()),
-		ghrepo.FullName(repo))
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName())
+	if err != nil {
+		return err
+	}
 
-	request, err := http.NewRequest("DELETE", url, nil)
+	request, err := http.NewRequest("DELETE", url.String(), nil)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/repo/deploy-key/add/http.go b/pkg/cmd/repo/deploy-key/add/http.go
--- a/pkg/cmd/repo/deploy-key/add/http.go
+++ b/pkg/cmd/repo/deploy-key/add/http.go
@@ -3,18 +3,20 @@ package add
 import (
 	"bytes"
 	"encoding/json"
-	"fmt"
 	"io"
 	"net/http"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 func uploadDeployKey(httpClient *http.Client, repo ghrepo.Interface, keyFile io.Reader, title string, isWritable bool) error {
-	path := fmt.Sprintf("repos/%s/%s/keys", repo.RepoOwner(), repo.RepoName())
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "keys")
+	if err != nil {
+		return err
+	}
 
 	keyBytes, err := io.ReadAll(keyFile)
 	if err != nil {
@@ -32,7 +34,7 @@ func uploadDeployKey(httpClient *http.Client, repo ghrepo.Interface, keyFile io.
 		return err
 	}
 
-	req, err := http.NewRequest("POST", url, bytes.NewBuffer(payloadBytes))
+	req, err := http.NewRequest("POST", url.String(), bytes.NewBuffer(payloadBytes))
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/repo/deploy-key/delete/http.go b/pkg/cmd/repo/deploy-key/delete/http.go
--- a/pkg/cmd/repo/deploy-key/delete/http.go
+++ b/pkg/cmd/repo/deploy-key/delete/http.go
@@ -1,20 +1,22 @@
 package delete
 
 import (
-	"fmt"
 	"io"
 	"net/http"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 func deleteDeployKey(httpClient *http.Client, repo ghrepo.Interface, id string) error {
-	path := fmt.Sprintf("repos/%s/%s/keys/%s", repo.RepoOwner(), repo.RepoName(), id)
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "keys", id)
+	if err != nil {
+		return err
+	}
 
-	req, err := http.NewRequest("DELETE", url, nil)
+	req, err := http.NewRequest("DELETE", url.String(), nil)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/repo/deploy-key/list/http.go b/pkg/cmd/repo/deploy-key/list/http.go
--- a/pkg/cmd/repo/deploy-key/list/http.go
+++ b/pkg/cmd/repo/deploy-key/list/http.go
@@ -2,14 +2,14 @@ package list
 
 import (
 	"encoding/json"
-	"fmt"
 	"io"
 	"net/http"
 	"time"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 type deployKey struct {
@@ -21,9 +21,12 @@ type deployKey struct {
 }
 
 func repoKeys(httpClient *http.Client, repo ghrepo.Interface) ([]deployKey, error) {
-	path := fmt.Sprintf("repos/%s/%s/keys?per_page=100", repo.RepoOwner(), repo.RepoName())
-	url := ghinstance.RESTPrefix(repo.RepoHost()) + path
-	req, err := http.NewRequest("GET", url, nil)
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "keys")
+	if err != nil {
+		return nil, err
+	}
+	u.SetQuery("per_page", "100")
+	req, err := http.NewRequest("GET", u.String(), nil)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/repo/edit/edit.go b/pkg/cmd/repo/edit/edit.go
--- a/pkg/cmd/repo/edit/edit.go
+++ b/pkg/cmd/repo/edit/edit.go
@@ -16,6 +16,7 @@ import (
 	fd "github.com/cli/cli/v2/internal/featuredetection"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -298,7 +299,10 @@ func editRun(ctx context.Context, opts *EditOptions) error {
 		}
 	}
 
-	apiPath := fmt.Sprintf("repos/%s/%s", repo.RepoOwner(), repo.RepoName())
+	apiPath, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName())
+	if err != nil {
+		return err
+	}
 
 	body := &bytes.Buffer{}
 	enc := json.NewEncoder(body)
@@ -341,7 +345,7 @@ func editRun(ctx context.Context, opts *EditOptions) error {
 		})
 	}
 
-	err := g.Wait()
+	err = g.Wait()
 	if err != nil {
 		return err
 	}
@@ -563,8 +567,11 @@ func parseTopics(s string) []string {
 }
 
 func getTopics(ctx context.Context, httpClient *http.Client, repo ghrepo.Interface) ([]string, error) {
-	apiPath := fmt.Sprintf("repos/%s/%s/topics", repo.RepoOwner(), repo.RepoName())
-	req, err := http.NewRequestWithContext(ctx, "GET", ghinstance.RESTPrefix(repo.RepoHost())+apiPath, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "topics")
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequestWithContext(ctx, "GET", url.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -601,8 +608,11 @@ func setTopics(ctx context.Context, httpClient *http.Client, repo ghrepo.Interfa
 		return err
 	}
 
-	apiPath := fmt.Sprintf("repos/%s/%s/topics", repo.RepoOwner(), repo.RepoName())
-	req, err := http.NewRequestWithContext(ctx, "PUT", ghinstance.RESTPrefix(repo.RepoHost())+apiPath, body)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "topics")
+	if err != nil {
+		return err
+	}
+	req, err := http.NewRequestWithContext(ctx, "PUT", url.String(), body)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/repo/garden/http.go b/pkg/cmd/repo/garden/http.go
--- a/pkg/cmd/repo/garden/http.go
+++ b/pkg/cmd/repo/garden/http.go
@@ -3,14 +3,15 @@ package garden
 import (
 	"encoding/json"
 	"errors"
-	"fmt"
 	"io"
 	"net/http"
+	"strconv"
 	"strings"
 	"time"
 
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 func getCommits(client *http.Client, repo ghrepo.Interface, maxCommits int) ([]*Commit, error) {
@@ -25,8 +26,14 @@ func getCommits(client *http.Client, repo ghrepo.Interface, maxCommits int) ([]*
 
 	commits := []*Commit{}
 
-	pathF := func(page int) string {
-		return fmt.Sprintf("repos/%s/%s/commits?per_page=100&page=%d", repo.RepoOwner(), repo.RepoName(), page)
+	pathF := func(page int) (*safeurl.MutableSafeURL, error) {
+		u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "commits")
+		if err != nil {
+			return nil, err
+		}
+		u.SetQuery("per_page", "100")
+		u.SetQuery("page", strconv.Itoa(page))
+		return u, nil
 	}
 
 	page := 1
@@ -36,7 +43,11 @@ func getCommits(client *http.Client, repo ghrepo.Interface, maxCommits int) ([]*
 			break
 		}
 		result := Result{}
-		links, err := getResponse(client, repo.RepoHost(), pathF(page), &result)
+		path, err := pathF(page)
+		if err != nil {
+			return nil, err
+		}
+		links, err := getResponse(client, path, &result)
 		if err != nil {
 			return nil, err
 		}
@@ -69,9 +80,8 @@ func getCommits(client *http.Client, repo ghrepo.Interface, maxCommits int) ([]*
 
 // getResponse performs the API call and returns the response's link header values.
 // If the "Link" header is missing, the returned slice will be nil.
-func getResponse(client *http.Client, host, path string, data interface{}) ([]string, error) {
-	url := ghinstance.RESTPrefix(host) + path
-	req, err := http.NewRequest("GET", url, nil)
+func getResponse(client *http.Client, url safeurl.SafeURL, data interface{}) ([]string, error) {
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/repo/read-file/http.go b/pkg/cmd/repo/read-file/http.go
--- a/pkg/cmd/repo/read-file/http.go
+++ b/pkg/cmd/repo/read-file/http.go
@@ -6,12 +6,12 @@ import (
 	"fmt"
 	"io"
 	"net/http"
-	"net/url"
 	"strings"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 // repoFile is the resolved file content and metadata for a single path.
@@ -83,9 +83,12 @@ type contentsResponse struct {
 // It requests the unified object media type so directories, files, symlinks, and
 // submodules all come back as a single JSON object distinguished by the type field.
 func fetchContent(httpClient *http.Client, repo ghrepo.Interface, filePath, ref string) (*contentsResponse, error) {
-	apiPath := contentsAPIPath(repo, filePath, ref)
+	apiPath, err := contentsAPIPath(repo, filePath, ref)
+	if err != nil {
+		return nil, err
+	}
 
-	req, err := http.NewRequest("GET", apiPath, nil)
+	req, err := http.NewRequest("GET", apiPath.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -171,9 +174,12 @@ func fetchFile(httpClient *http.Client, repo ghrepo.Interface, filePath, ref str
 // fetchRawFile retrieves the raw bytes of a file, used for files larger than the
 // 1 MB inline content limit of the Contents API.
 func fetchRawFile(httpClient *http.Client, repo ghrepo.Interface, filePath, ref string) ([]byte, error) {
-	apiPath := contentsAPIPath(repo, filePath, ref)
+	apiPath, err := contentsAPIPath(repo, filePath, ref)
+	if err != nil {
+		return nil, err
+	}
 
-	req, err := http.NewRequest("GET", apiPath, nil)
+	req, err := http.NewRequest("GET", apiPath.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -193,16 +199,15 @@ func fetchRawFile(httpClient *http.Client, repo ghrepo.Interface, filePath, ref
 }
 
 // contentsAPIPath builds the absolute Contents API URL for a path and optional ref.
-func contentsAPIPath(repo ghrepo.Interface, filePath, ref string) string {
+func contentsAPIPath(repo ghrepo.Interface, filePath, ref string) (safeurl.SafeURL, error) {
 	// The Contents API accepts a fully percent-encoded path, including path separators
 	// encoded as %2F, so spaces and other special characters are handled transparently.
-	p := fmt.Sprintf("%srepos/%s/%s/contents/%s",
-		ghinstance.RESTPrefix(repo.RepoHost()),
-		repo.RepoOwner(), repo.RepoName(),
-		url.PathEscape(strings.TrimPrefix(filePath, "/")),
-	)
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "contents", strings.TrimPrefix(filePath, "/"))
+	if err != nil {
+		return nil, err
+	}
 	if ref != "" {
-		p += "?ref=" + url.QueryEscape(ref)
+		u.SetQuery("ref", ref)
 	}
-	return p
+	return u, nil
 }
diff --git a/pkg/cmd/repo/sync/http.go b/pkg/cmd/repo/sync/http.go
--- a/pkg/cmd/repo/sync/http.go
+++ b/pkg/cmd/repo/sync/http.go
@@ -10,6 +10,7 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 type commit struct {
@@ -25,8 +26,11 @@ type commit struct {
 
 func latestCommit(client *api.Client, repo ghrepo.Interface, branch string) (commit, error) {
 	var response commit
-	path := fmt.Sprintf("repos/%s/%s/git/refs/heads/%s", repo.RepoOwner(), repo.RepoName(), branch)
-	err := client.REST(repo.RepoHost(), "GET", path, nil, &response)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "git", "refs", fmt.Sprintf("heads/%s", branch))
+	if err != nil {
+		return response, err
+	}
+	err = client.REST(repo.RepoHost(), "GET", path.String(), nil, &response)
 	return response, err
 }
 
@@ -48,9 +52,12 @@ func triggerUpstreamMerge(client *api.Client, repo ghrepo.Interface, branch stri
 		MergeType  string `json:"merge_type"`
 		BaseBranch string `json:"base_branch"`
 	}
-	path := fmt.Sprintf("repos/%s/%s/merge-upstream", repo.RepoOwner(), repo.RepoName())
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "merge-upstream")
+	if err != nil {
+		return "", err
+	}
 	var httpErr api.HTTPError
-	if err := client.REST(repo.RepoHost(), "POST", path, &payload, &response); err != nil {
+	if err := client.REST(repo.RepoHost(), "POST", path.String(), &payload, &response); err != nil {
 		if errors.As(err, &httpErr) {
 			switch httpErr.StatusCode {
 			case http.StatusUnprocessableEntity, http.StatusConflict:
@@ -66,7 +73,10 @@ func triggerUpstreamMerge(client *api.Client, repo ghrepo.Interface, branch stri
 }
 
 func syncFork(client *api.Client, repo ghrepo.Interface, branch, SHA string, force bool) error {
-	path := fmt.Sprintf("repos/%s/%s/git/refs/heads/%s", repo.RepoOwner(), repo.RepoName(), branch)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "git", "refs", fmt.Sprintf("heads/%s", branch))
+	if err != nil {
+		return err
+	}
 	body := map[string]interface{}{
 		"sha":   SHA,
 		"force": force,
@@ -76,5 +86,5 @@ func syncFork(client *api.Client, repo ghrepo.Interface, branch, SHA string, for
 		return err
 	}
 	requestBody := bytes.NewReader(requestByte)
-	return client.REST(repo.RepoHost(), "PATCH", path, requestBody, nil)
+	return client.REST(repo.RepoHost(), "PATCH", path.String(), requestBody, nil)
 }
diff --git a/pkg/cmd/repo/view/http.go b/pkg/cmd/repo/view/http.go
--- a/pkg/cmd/repo/view/http.go
+++ b/pkg/cmd/repo/view/http.go
@@ -10,6 +10,7 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/go-gh/v2/pkg/asciisanitizer"
 	"golang.org/x/text/transform"
 )
@@ -30,7 +31,12 @@ func RepositoryReadme(client *http.Client, repo ghrepo.Interface, branch string)
 		HTMLURL string `json:"html_url"`
 	}
 
-	err := apiClient.REST(repo.RepoHost(), "GET", getReadmePath(repo, branch), nil, &response)
+	readmePath, err := getReadmePath(repo, branch)
+	if err != nil {
+		return nil, err
+	}
+
+	err = apiClient.REST(repo.RepoHost(), "GET", readmePath.String(), nil, &response)
 	if err != nil {
 		var httpError api.HTTPError
 		if errors.As(err, &httpError) && httpError.StatusCode == 404 {
@@ -56,10 +62,13 @@ func RepositoryReadme(client *http.Client, repo ghrepo.Interface, branch string)
 	}, nil
 }
 
-func getReadmePath(repo ghrepo.Interface, branch string) string {
-	path := fmt.Sprintf("repos/%s/readme", ghrepo.FullName(repo))
+func getReadmePath(repo ghrepo.Interface, branch string) (safeurl.SafeURL, error) {
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "readme")
+	if err != nil {
+		return nil, err
+	}
 	if branch != "" {
-		path = fmt.Sprintf("%s?ref=%s", path, branch)
+		path.SetQuery("ref", branch)
 	}
-	return path
+	return path, nil
 }
diff --git a/pkg/cmd/ruleset/check/check.go b/pkg/cmd/ruleset/check/check.go
--- a/pkg/cmd/ruleset/check/check.go
+++ b/pkg/cmd/ruleset/check/check.go
@@ -12,6 +12,7 @@ import (
 	"github.com/cli/cli/v2/internal/browser"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmd/ruleset/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -144,10 +145,13 @@ func checkRun(opts *CheckOptions) error {
 
 	var rules []shared.RulesetRule
 
-	endpoint := fmt.Sprintf("repos/%s/%s/rules/branches/%s", repoI.RepoOwner(), repoI.RepoName(), url.PathEscape(opts.Branch))
+	endpoint, err := safeurl.JoinPath("repos", repoI.RepoOwner(), repoI.RepoName(), "rules", "branches", opts.Branch)
+	if err != nil {
+		return err
+	}
 
-	if err = client.REST(repoI.RepoHost(), "GET", endpoint, nil, &rules); err != nil {
-		return fmt.Errorf("GET %s failed: %w", endpoint, err)
+	if err = client.REST(repoI.RepoHost(), "GET", endpoint.String(), nil, &rules); err != nil {
+		return fmt.Errorf("GET %s failed: %w", endpoint.String(), err)
 	}
 
 	w := opts.IO.Out
diff --git a/pkg/cmd/ruleset/view/http.go b/pkg/cmd/ruleset/view/http.go
--- a/pkg/cmd/ruleset/view/http.go
+++ b/pkg/cmd/ruleset/view/http.go
@@ -1,29 +1,35 @@
 package view
 
 import (
-	"fmt"
 	"net/http"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/ruleset/shared"
 )
 
 func viewRepoRuleset(httpClient *http.Client, repo ghrepo.Interface, databaseId string) (*shared.RulesetREST, error) {
-	path := fmt.Sprintf("repos/%s/%s/rulesets/%s", repo.RepoOwner(), repo.RepoName(), databaseId)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "rulesets", databaseId)
+	if err != nil {
+		return nil, err
+	}
 	return viewRuleset(httpClient, repo.RepoHost(), path)
 }
 
 func viewOrgRuleset(httpClient *http.Client, orgLogin string, databaseId string, host string) (*shared.RulesetREST, error) {
-	path := fmt.Sprintf("orgs/%s/rulesets/%s", orgLogin, databaseId)
+	path, err := safeurl.JoinPath("orgs", orgLogin, "rulesets", databaseId)
+	if err != nil {
+		return nil, err
+	}
 	return viewRuleset(httpClient, host, path)
 }
 
-func viewRuleset(httpClient *http.Client, hostname string, path string) (*shared.RulesetREST, error) {
+func viewRuleset(httpClient *http.Client, hostname string, path safeurl.SafeURL) (*shared.RulesetREST, error) {
 	apiClient := api.NewClientFromHTTP(httpClient)
 	result := shared.RulesetREST{}
 
-	err := apiClient.REST(hostname, "GET", path, nil, &result)
+	err := apiClient.REST(hostname, "GET", path.String(), nil, &result)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/run/cancel/cancel.go b/pkg/cmd/run/cancel/cancel.go
--- a/pkg/cmd/run/cancel/cancel.go
+++ b/pkg/cmd/run/cancel/cancel.go
@@ -8,6 +8,7 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/run/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -142,14 +143,18 @@ func runCancel(opts *CancelOptions) error {
 }
 
 func cancelWorkflowRun(client *api.Client, repo ghrepo.Interface, runID string, force bool) error {
-	var path string
+	var path *safeurl.MutableSafeURL
+	var err error
 	if force {
-		path = fmt.Sprintf("repos/%s/actions/runs/%s/force-cancel", ghrepo.FullName(repo), runID)
+		path, err = safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", runID, "force-cancel")
 	} else {
-		path = fmt.Sprintf("repos/%s/actions/runs/%s/cancel", ghrepo.FullName(repo), runID)
+		path, err = safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", runID, "cancel")
+	}
+	if err != nil {
+		return err
 	}
 
-	err := client.REST(repo.RepoHost(), "POST", path, nil, nil)
+	err = client.REST(repo.RepoHost(), "POST", path.String(), nil, nil)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/run/delete/delete.go b/pkg/cmd/run/delete/delete.go
--- a/pkg/cmd/run/delete/delete.go
+++ b/pkg/cmd/run/delete/delete.go
@@ -9,6 +9,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/run/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -138,8 +139,11 @@ func runDelete(opts *DeleteOptions) error {
 }
 
 func deleteWorkflowRun(client *api.Client, repo ghrepo.Interface, runID string) error {
-	path := fmt.Sprintf("repos/%s/actions/runs/%s", ghrepo.FullName(repo), runID)
-	err := client.REST(repo.RepoHost(), "DELETE", path, nil, nil)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", runID)
+	if err != nil {
+		return err
+	}
+	err = client.REST(repo.RepoHost(), "DELETE", path.String(), nil, nil)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/run/download/download.go b/pkg/cmd/run/download/download.go
--- a/pkg/cmd/run/download/download.go
+++ b/pkg/cmd/run/download/download.go
@@ -7,6 +7,7 @@ import (
 
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/internal/safepaths"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/run/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -28,7 +29,7 @@ type DownloadOptions struct {
 
 type platform interface {
 	List(runID string) ([]shared.Artifact, error)
-	Download(url string, dir safepaths.Absolute) error
+	Download(url safeurl.SafeURL, dir safepaths.Absolute) error
 }
 
 type iprompter interface {
@@ -187,7 +188,7 @@ func runDownload(opts *DownloadOptions) error {
 			}
 		}
 
-		err := opts.Platform.Download(a.DownloadURL, destDir)
+		err := opts.Platform.Download(safeurl.NewImmutableSafeURL(a.DownloadURL), destDir)
 		if err != nil {
 			return fmt.Errorf("error downloading %s: %w", a.Name, err)
 		}
diff --git a/pkg/cmd/run/download/http.go b/pkg/cmd/run/download/http.go
--- a/pkg/cmd/run/download/http.go
+++ b/pkg/cmd/run/download/http.go
@@ -10,6 +10,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
 	"github.com/cli/cli/v2/internal/safepaths"
+	"github.com/cli/cli/v2/internal/safeurl"
 	ghzip "github.com/cli/cli/v2/internal/zip"
 	"github.com/cli/cli/v2/pkg/cmd/run/shared"
 )
@@ -23,12 +24,12 @@ func (p *apiPlatform) List(runID string) ([]shared.Artifact, error) {
 	return shared.ListArtifacts(p.client, p.repo, runID)
 }
 
-func (p *apiPlatform) Download(url string, dir safepaths.Absolute) error {
+func (p *apiPlatform) Download(url safeurl.SafeURL, dir safepaths.Absolute) error {
 	return downloadArtifact(p.client, url, dir)
 }
 
-func downloadArtifact(httpClient *http.Client, url string, destDir safepaths.Absolute) error {
-	req, err := http.NewRequest("GET", url, nil)
+func downloadArtifact(httpClient *http.Client, url safeurl.SafeURL, destDir safepaths.Absolute) error {
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/run/rerun/rerun.go b/pkg/cmd/run/rerun/rerun.go
--- a/pkg/cmd/run/rerun/rerun.go
+++ b/pkg/cmd/run/rerun/rerun.go
@@ -7,10 +7,12 @@ import (
 	"fmt"
 	"io"
 	"net/http"
+	"strconv"
 
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/run/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -196,9 +198,12 @@ func rerunRun(client *api.Client, repo ghrepo.Interface, run *shared.Run, onlyFa
 		return fmt.Errorf("failed to create rerun body: %w", err)
 	}
 
-	path := fmt.Sprintf("repos/%s/actions/runs/%d/%s", ghrepo.FullName(repo), run.ID, runVerb)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", strconv.FormatInt(run.ID, 10), runVerb)
+	if err != nil {
+		return err
+	}
 
-	err = client.REST(repo.RepoHost(), "POST", path, body, nil)
+	err = client.REST(repo.RepoHost(), "POST", path.String(), body, nil)
 	if err != nil {
 		var httpError api.HTTPError
 		if errors.As(err, &httpError) && httpError.StatusCode == 403 {
@@ -215,9 +220,12 @@ func rerunJob(client *api.Client, repo ghrepo.Interface, job *shared.Job, debug
 		return fmt.Errorf("failed to create rerun body: %w", err)
 	}
 
-	path := fmt.Sprintf("repos/%s/actions/jobs/%d/rerun", ghrepo.FullName(repo), job.ID)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "jobs", strconv.FormatInt(job.ID, 10), "rerun")
+	if err != nil {
+		return err
+	}
 
-	err = client.REST(repo.RepoHost(), "POST", path, body, nil)
+	err = client.REST(repo.RepoHost(), "POST", path.String(), body, nil)
 	if err != nil {
 		var httpError api.HTTPError
 		if errors.As(err, &httpError) && httpError.StatusCode == 403 {
diff --git a/pkg/cmd/run/shared/artifacts.go b/pkg/cmd/run/shared/artifacts.go
--- a/pkg/cmd/run/shared/artifacts.go
+++ b/pkg/cmd/run/shared/artifacts.go
@@ -2,13 +2,14 @@ package shared
 
 import (
 	"encoding/json"
-	"fmt"
 	"net/http"
 	"regexp"
+	"strconv"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 type Artifact struct {
@@ -25,17 +26,24 @@ type artifactsPayload struct {
 func ListArtifacts(httpClient *http.Client, repo ghrepo.Interface, runID string) ([]Artifact, error) {
 	var results []Artifact
 
+	restPrefix := ghinstance.RESTPrefix(repo.RepoHost())
 	perPage := 100
-	path := fmt.Sprintf("repos/%s/%s/actions/artifacts?per_page=%d", repo.RepoOwner(), repo.RepoName(), perPage)
+	u, err := safeurl.JoinPathWithHostPrefix(restPrefix, "repos", repo.RepoOwner(), repo.RepoName(), "actions", "artifacts")
+	if err != nil {
+		return nil, err
+	}
 	if runID != "" {
-		path = fmt.Sprintf("repos/%s/%s/actions/runs/%s/artifacts?per_page=%d", repo.RepoOwner(), repo.RepoName(), runID, perPage)
+		u, err = safeurl.JoinPathWithHostPrefix(restPrefix, "repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", runID, "artifacts")
+		if err != nil {
+			return nil, err
+		}
 	}
-
-	url := fmt.Sprintf("%s%s", ghinstance.RESTPrefix(repo.RepoHost()), path)
+	u.SetQuery("per_page", strconv.Itoa(perPage))
+	var pageURL safeurl.SafeURL = u
 
 	for {
 		var payload artifactsPayload
-		nextURL, err := apiGet(httpClient, url, &payload)
+		nextURL, err := apiGet(httpClient, pageURL, &payload)
 		if err != nil {
 			return nil, err
 		}
@@ -44,14 +52,14 @@ func ListArtifacts(httpClient *http.Client, repo ghrepo.Interface, runID string)
 		if nextURL == "" {
 			break
 		}
-		url = nextURL
+		pageURL = safeurl.NewImmutableSafeURL(nextURL)
 	}
 
 	return results, nil
 }
 
-func apiGet(httpClient *http.Client, url string, data interface{}) (string, error) {
-	req, err := http.NewRequest("GET", url, nil)
+func apiGet(httpClient *http.Client, url safeurl.SafeURL, data interface{}) (string, error) {
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return "", err
 	}
diff --git a/pkg/cmd/run/shared/shared.go b/pkg/cmd/run/shared/shared.go
--- a/pkg/cmd/run/shared/shared.go
+++ b/pkg/cmd/run/shared/shared.go
@@ -6,11 +6,13 @@ import (
 	"net/http"
 	"net/url"
 	"reflect"
+	"strconv"
 	"strings"
 	"time"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	workflowShared "github.com/cli/cli/v2/pkg/cmd/workflow/shared"
 	"github.com/cli/cli/v2/pkg/iostreams"
 )
@@ -106,7 +108,7 @@ type Run struct {
 	HeadSha        string `json:"head_sha"`
 	URL            string `json:"html_url"`
 	HeadRepository Repo   `json:"head_repository"`
-	Jobs           []Job  `json:"-"` // populated by GetJobs
+	Jobs           []Job  `json:"-"` // Populated manually (separate from fetching the run)
 }
 
 func (r *Run) StartedTime() time.Time {
@@ -280,9 +282,12 @@ var ErrMissingAnnotationsPermissions = errors.New("missing annotations permissio
 func GetAnnotations(client *api.Client, repo ghrepo.Interface, job Job) ([]Annotation, error) {
 	var result []*Annotation
 
-	path := fmt.Sprintf("repos/%s/check-runs/%d/annotations", ghrepo.FullName(repo), job.ID)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "check-runs", strconv.FormatInt(job.ID, 10), "annotations")
+	if err != nil {
+		return nil, err
+	}
 
-	err := client.REST(repo.RepoHost(), "GET", path, nil, &result)
+	err = client.REST(repo.RepoHost(), "GET", path.String(), nil, &result)
 	if err != nil {
 		var httpError api.HTTPError
 		if !errors.As(err, &httpError) {
@@ -361,49 +366,56 @@ func GetRunsWithFilter(client *api.Client, repo ghrepo.Interface, opts *FilterOp
 }
 
 func GetRuns(client *api.Client, repo ghrepo.Interface, opts *FilterOptions, limit int) (*RunsPayload, error) {
-	path := fmt.Sprintf("repos/%s/actions/runs", ghrepo.FullName(repo))
+	u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs")
+	if err != nil {
+		return nil, err
+	}
 	if opts != nil && opts.WorkflowID > 0 {
-		path = fmt.Sprintf("repos/%s/actions/workflows/%d/runs", ghrepo.FullName(repo), opts.WorkflowID)
+		u, err = safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "workflows", strconv.FormatInt(opts.WorkflowID, 10), "runs")
+		if err != nil {
+			return nil, err
+		}
 	}
 
 	perPage := limit
 	if limit > 100 {
 		perPage = 100
 	}
-	path += fmt.Sprintf("?per_page=%d", perPage)
-	path += "&exclude_pull_requests=true" // significantly reduces payload size
+	u.SetQuery("per_page", strconv.Itoa(perPage))
+	u.SetQuery("exclude_pull_requests", "true") // significantly reduces payload size
 
 	if opts != nil {
 		if opts.Branch != "" {
-			path += fmt.Sprintf("&branch=%s", url.QueryEscape(opts.Branch))
+			u.SetQuery("branch", opts.Branch)
 		}
 		if opts.Actor != "" {
-			path += fmt.Sprintf("&actor=%s", url.QueryEscape(opts.Actor))
+			u.SetQuery("actor", opts.Actor)
 		}
 		if opts.Status != "" {
-			path += fmt.Sprintf("&status=%s", url.QueryEscape(opts.Status))
+			u.SetQuery("status", opts.Status)
 		}
 		if opts.Event != "" {
-			path += fmt.Sprintf("&event=%s", url.QueryEscape(opts.Event))
+			u.SetQuery("event", opts.Event)
 		}
 		if opts.Created != "" {
-			path += fmt.Sprintf("&created=%s", url.QueryEscape(opts.Created))
+			u.SetQuery("created", opts.Created)
 		}
 		if opts.Commit != "" {
-			path += fmt.Sprintf("&head_sha=%s", url.QueryEscape(opts.Commit))
+			u.SetQuery("head_sha", opts.Commit)
 		}
 	}
+	var pageURL safeurl.SafeURL = u
 
 	var result *RunsPayload
 
 pagination:
-	for path != "" {
+	for pageURL.String() != "" {
 		var response RunsPayload
-		var err error
-		path, err = client.RESTWithNext(repo.RepoHost(), "GET", path, nil, &response)
+		next, err := client.RESTWithNext(repo.RepoHost(), "GET", pageURL.String(), nil, &response)
 		if err != nil {
 			return nil, err
 		}
+		pageURL = safeurl.NewImmutableSafeURL(next)
 
 		if result == nil {
 			result = &response
@@ -475,38 +487,49 @@ type JobsPayload struct {
 	Jobs       []Job
 }
 
-func GetJobs(client *api.Client, repo ghrepo.Interface, run *Run, attempt uint64) ([]Job, error) {
-	if run.Jobs != nil {
-		return run.Jobs, nil
-	}
-
-	query := url.Values{}
-	query.Set("per_page", "100")
-	jobsPath := fmt.Sprintf("%s?%s", run.JobsURL, query.Encode())
-
+func GetJobs(client *api.Client, repo ghrepo.Interface, runID int64, jobsURL safeurl.SafeURL, attempt uint64) ([]Job, error) {
+	var jobsPath safeurl.SafeURL
 	if attempt > 0 {
-		jobsPath = fmt.Sprintf("repos/%s/actions/runs/%d/attempts/%d/jobs?%s", ghrepo.FullName(repo), run.ID, attempt, query.Encode())
+		p, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", strconv.FormatInt(runID, 10), "attempts", strconv.FormatUint(attempt, 10), "jobs")
+		if err != nil {
+			return nil, err
+		}
+		p.SetQuery("per_page", "100")
+		jobsPath = p
+	} else {
+		u, err := url.Parse(jobsURL.String())
+		if err != nil {
+			return nil, err
+		}
+		query := url.Values{}
+		query.Set("per_page", "100")
+		u.RawQuery = query.Encode()
+		// Since u is derived from jobsURL, an already-trusted safeurl.SafeURL, the resulting URL is safe to declare as such.
+		jobsPath = safeurl.NewImmutableSafeURL(u.String())
 	}
 
-	for jobsPath != "" {
+	// A non-nil empty slice is returned so callers can tell that jobs were fetched and there are none (if len is zero).
+	jobs := []Job{}
+	for jobsPath.String() != "" {
 		var resp JobsPayload
-		var err error
-		jobsPath, err = client.RESTWithNext(repo.RepoHost(), http.MethodGet, jobsPath, nil, &resp)
+		next, err := client.RESTWithNext(repo.RepoHost(), http.MethodGet, jobsPath.String(), nil, &resp)
 		if err != nil {
-			run.Jobs = nil
 			return nil, err
 		}
-
-		run.Jobs = append(run.Jobs, resp.Jobs...)
+		jobs = append(jobs, resp.Jobs...)
+		jobsPath = safeurl.NewImmutableSafeURL(next)
 	}
-	return run.Jobs, nil
+	return jobs, nil
 }
 
 func GetJob(client *api.Client, repo ghrepo.Interface, jobID string) (*Job, error) {
-	path := fmt.Sprintf("repos/%s/actions/jobs/%s", ghrepo.FullName(repo), jobID)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "jobs", jobID)
+	if err != nil {
+		return nil, err
+	}
 
 	var result Job
-	err := client.REST(repo.RepoHost(), "GET", path, nil, &result)
+	err = client.REST(repo.RepoHost(), "GET", path.String(), nil, &result)
 	if err != nil {
 		return nil, err
 	}
@@ -539,13 +562,20 @@ func SelectRun(p Prompter, cs *iostreams.ColorScheme, runs []Run) (string, error
 func GetRun(client *api.Client, repo ghrepo.Interface, runID string, attempt uint64) (*Run, error) {
 	var result Run
 
-	path := fmt.Sprintf("repos/%s/actions/runs/%s?exclude_pull_requests=true", ghrepo.FullName(repo), runID)
+	u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", runID)
+	if err != nil {
+		return nil, err
+	}
 
 	if attempt > 0 {
-		path = fmt.Sprintf("repos/%s/actions/runs/%s/attempts/%d?exclude_pull_requests=true", ghrepo.FullName(repo), runID, attempt)
+		u, err = safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", runID, "attempts", strconv.FormatUint(attempt, 10))
+		if err != nil {
+			return nil, err
+		}
 	}
+	u.SetQuery("exclude_pull_requests", "true")
 
-	err := client.REST(repo.RepoHost(), "GET", path, nil, &result)
+	err = client.REST(repo.RepoHost(), "GET", u.String(), nil, &result)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/run/view/logs.go b/pkg/cmd/run/view/logs.go
--- a/pkg/cmd/run/view/logs.go
+++ b/pkg/cmd/run/view/logs.go
@@ -9,12 +9,14 @@ import (
 	"regexp"
 	"slices"
 	"sort"
+	"strconv"
 	"strings"
 	"unicode/utf16"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/run/shared"
 )
 
@@ -38,10 +40,12 @@ type apiLogFetcher struct {
 }
 
 func (f *apiLogFetcher) GetLog() (io.ReadCloser, error) {
-	logURL := fmt.Sprintf("%srepos/%s/actions/jobs/%d/logs",
-		ghinstance.RESTPrefix(f.repo.RepoHost()), ghrepo.FullName(f.repo), f.jobID)
+	logURL, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(f.repo.RepoHost()), "repos", f.repo.RepoOwner(), f.repo.RepoName(), "actions", "jobs", strconv.FormatInt(f.jobID, 10), "logs")
+	if err != nil {
+		return nil, err
+	}
 
-	req, err := http.NewRequest("GET", logURL, nil)
+	req, err := http.NewRequest("GET", logURL.String(), nil)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/run/view/view.go b/pkg/cmd/run/view/view.go
--- a/pkg/cmd/run/view/view.go
+++ b/pkg/cmd/run/view/view.go
@@ -18,6 +18,7 @@ import (
 	"github.com/cli/cli/v2/internal/browser"
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmd/run/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -260,11 +261,12 @@ func runView(opts *ViewOptions) error {
 
 	if shouldFetchJobs(opts) {
 		opts.IO.StartProgressIndicator()
-		jobs, err = shared.GetJobs(client, repo, run, attempt)
+		jobs, err = shared.GetJobs(client, repo, run.ID, safeurl.NewImmutableSafeURL(run.JobsURL), attempt)
 		opts.IO.StopProgressIndicator()
 		if err != nil {
 			return err
 		}
+		run.Jobs = jobs
 	}
 
 	if opts.Prompt && len(jobs) > 1 {
@@ -298,11 +300,12 @@ func runView(opts *ViewOptions) error {
 
 	if selectedJob == nil && len(jobs) == 0 {
 		opts.IO.StartProgressIndicator()
-		jobs, err = shared.GetJobs(client, repo, run, attempt)
+		jobs, err = shared.GetJobs(client, repo, run.ID, safeurl.NewImmutableSafeURL(run.JobsURL), attempt)
 		opts.IO.StopProgressIndicator()
 		if err != nil {
 			return fmt.Errorf("failed to get jobs: %w", err)
 		}
+		run.Jobs = jobs
 	} else if selectedJob != nil {
 		jobs = []shared.Job{*selectedJob}
 	}
@@ -467,8 +470,8 @@ func shouldFetchJobs(opts *ViewOptions) bool {
 	return false
 }
 
-func getLog(httpClient *http.Client, logURL string) (io.ReadCloser, error) {
-	req, err := http.NewRequest("GET", logURL, nil)
+func getLog(httpClient *http.Client, logURL safeurl.SafeURL) (io.ReadCloser, error) {
+	req, err := http.NewRequest("GET", logURL.String(), nil)
 	if err != nil {
 		return nil, err
 	}
@@ -496,12 +499,16 @@ func getRunLog(cache RunLogCache, httpClient *http.Client, repo ghrepo.Interface
 
 	if !isCached {
 		// Run log does not exist in cache so retrieve and store it
-		logURL := fmt.Sprintf("%srepos/%s/actions/runs/%d/logs",
-			ghinstance.RESTPrefix(repo.RepoHost()), ghrepo.FullName(repo), run.ID)
+		logURL, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", strconv.FormatInt(run.ID, 10), "logs")
+		if err != nil {
+			return nil, err
+		}
 
 		if attempt > 0 {
-			logURL = fmt.Sprintf("%srepos/%s/actions/runs/%d/attempts/%d/logs",
-				ghinstance.RESTPrefix(repo.RepoHost()), ghrepo.FullName(repo), run.ID, attempt)
+			logURL, err = safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(repo.RepoHost()), "repos", repo.RepoOwner(), repo.RepoName(), "actions", "runs", strconv.FormatInt(run.ID, 10), "attempts", strconv.FormatUint(attempt, 10), "logs")
+			if err != nil {
+				return nil, err
+			}
 		}
 
 		resp, err := getLog(httpClient, logURL)
diff --git a/pkg/cmd/run/watch/watch.go b/pkg/cmd/run/watch/watch.go
--- a/pkg/cmd/run/watch/watch.go
+++ b/pkg/cmd/run/watch/watch.go
@@ -10,6 +10,7 @@ import (
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/text"
 	"github.com/cli/cli/v2/pkg/cmd/run/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -221,10 +222,11 @@ func renderRun(out io.Writer, opts WatchOptions, client *api.Client, repo ghrepo
 		return nil, fmt.Errorf("failed to get run: %w", err)
 	}
 
-	jobs, err := shared.GetJobs(client, repo, run, 0)
+	jobs, err := shared.GetJobs(client, repo, run.ID, safeurl.NewImmutableSafeURL(run.JobsURL), 0)
 	if err != nil {
 		return nil, fmt.Errorf("failed to get jobs: %w", err)
 	}
+	run.Jobs = jobs
 
 	var annotations []shared.Annotation
 	var missingAnnotationsPermissions bool
diff --git a/pkg/cmd/secret/delete/delete.go b/pkg/cmd/secret/delete/delete.go
--- a/pkg/cmd/secret/delete/delete.go
+++ b/pkg/cmd/secret/delete/delete.go
@@ -9,6 +9,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/secret/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -123,24 +124,27 @@ func removeRun(opts *DeleteOptions) error {
 		return err
 	}
 
-	var path string
+	var path *safeurl.MutableSafeURL
 	var host string
 	switch secretEntity {
 	case shared.Organization:
-		path = fmt.Sprintf("orgs/%s/%s/secrets/%s", orgName, secretApp, opts.SecretName)
+		path, err = safeurl.JoinPath("orgs", orgName, string(secretApp), "secrets", opts.SecretName)
 		host, _ = cfg.Authentication().DefaultHost()
 	case shared.Environment:
-		path = fmt.Sprintf("repos/%s/environments/%s/secrets/%s", ghrepo.FullName(baseRepo), envName, opts.SecretName)
+		path, err = safeurl.JoinPath("repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "environments", envName, "secrets", opts.SecretName)
 		host = baseRepo.RepoHost()
 	case shared.User:
-		path = fmt.Sprintf("user/codespaces/secrets/%s", opts.SecretName)
+		path, err = safeurl.JoinPath("user", "codespaces", "secrets", opts.SecretName)
 		host, _ = cfg.Authentication().DefaultHost()
 	case shared.Repository:
-		path = fmt.Sprintf("repos/%s/%s/secrets/%s", ghrepo.FullName(baseRepo), secretApp, opts.SecretName)
+		path, err = safeurl.JoinPath("repos", baseRepo.RepoOwner(), baseRepo.RepoName(), string(secretApp), "secrets", opts.SecretName)
 		host = baseRepo.RepoHost()
 	}
+	if err != nil {
+		return err
+	}
 
-	err = client.REST(host, "DELETE", path, nil, nil)
+	err = client.REST(host, "DELETE", path.String(), nil, nil)
 	if err != nil {
 		return fmt.Errorf("failed to delete secret %s: %w", opts.SecretName, err)
 	}
diff --git a/pkg/cmd/secret/list/list.go b/pkg/cmd/secret/list/list.go
--- a/pkg/cmd/secret/list/list.go
+++ b/pkg/cmd/secret/list/list.go
@@ -13,6 +13,7 @@ import (
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/tableprinter"
 	"github.com/cli/cli/v2/pkg/cmd/secret/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -248,76 +249,98 @@ func fmtVisibility(s Secret) string {
 }
 
 func getOrgSecrets(client *http.Client, host, orgName string, showSelectedRepoInfo bool, app shared.App) ([]Secret, error) {
-	secrets, err := getSecrets(client, host, fmt.Sprintf("orgs/%s/%s/secrets", orgName, app))
+	u, err := safeurl.JoinPath("orgs", orgName, string(app), "secrets")
+	if err != nil {
+		return nil, err
+	}
+	secrets, err := getSecrets(client, host, u)
 	if err != nil {
 		return nil, err
 	}
 
 	if showSelectedRepoInfo {
-		err = populateSelectedRepositoryInformation(client, host, secrets)
-		if err != nil {
-			return nil, err
+		for i := range secrets {
+			if secrets[i].SelectedReposURL == "" {
+				continue
+			}
+			count, err := selectedRepositoryCount(client, host, safeurl.NewImmutableSafeURL(secrets[i].SelectedReposURL))
+			if err != nil {
+				return nil, fmt.Errorf("failed determining selected repositories for %s: %w", secrets[i].Name, err)
+			}
+			secrets[i].NumSelectedRepos = count
 		}
 	}
 	return secrets, nil
 }
 
 func getUserSecrets(client *http.Client, host string, showSelectedRepoInfo bool) ([]Secret, error) {
-	secrets, err := getSecrets(client, host, "user/codespaces/secrets")
+	u, err := safeurl.JoinPath("user", "codespaces", "secrets")
+	if err != nil {
+		return nil, err
+	}
+	secrets, err := getSecrets(client, host, u)
 	if err != nil {
 		return nil, err
 	}
 
 	if showSelectedRepoInfo {
-		err = populateSelectedRepositoryInformation(client, host, secrets)
-		if err != nil {
-			return nil, err
+		for i := range secrets {
+			if secrets[i].SelectedReposURL == "" {
+				continue
+			}
+			count, err := selectedRepositoryCount(client, host, safeurl.NewImmutableSafeURL(secrets[i].SelectedReposURL))
+			if err != nil {
+				return nil, fmt.Errorf("failed determining selected repositories for %s: %w", secrets[i].Name, err)
+			}
+			secrets[i].NumSelectedRepos = count
 		}
 	}
 
 	return secrets, nil
 }
 
 func getEnvSecrets(client *http.Client, repo ghrepo.Interface, envName string) ([]Secret, error) {
-	path := fmt.Sprintf("repos/%s/environments/%s/secrets", ghrepo.FullName(repo), envName)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "environments", envName, "secrets")
+	if err != nil {
+		return nil, err
+	}
 	return getSecrets(client, repo.RepoHost(), path)
 }
 
 func getRepoSecrets(client *http.Client, repo ghrepo.Interface, app shared.App) ([]Secret, error) {
-	return getSecrets(client, repo.RepoHost(), fmt.Sprintf("repos/%s/%s/secrets", ghrepo.FullName(repo), app))
+	u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), string(app), "secrets")
+	if err != nil {
+		return nil, err
+	}
+	return getSecrets(client, repo.RepoHost(), u)
 }
 
-func getSecrets(client *http.Client, host, path string) ([]Secret, error) {
+func getSecrets(client *http.Client, host string, u *safeurl.MutableSafeURL) ([]Secret, error) {
 	var results []Secret
 	apiClient := api.NewClientFromHTTP(client)
-	path = fmt.Sprintf("%s?per_page=100", path)
-	for path != "" {
+	u.SetQuery("per_page", "100")
+	var pageURL safeurl.SafeURL = u
+	for pageURL.String() != "" {
 		response := struct {
 			Secrets []Secret
 		}{}
-		var err error
-		path, err = apiClient.RESTWithNext(host, "GET", path, nil, &response)
+		next, err := apiClient.RESTWithNext(host, "GET", pageURL.String(), nil, &response)
 		if err != nil {
 			return nil, err
 		}
+		pageURL = safeurl.NewImmutableSafeURL(next)
 		results = append(results, response.Secrets...)
 	}
 	return results, nil
 }
 
-func populateSelectedRepositoryInformation(client *http.Client, host string, secrets []Secret) error {
+func selectedRepositoryCount(client *http.Client, host string, selectedReposURL safeurl.SafeURL) (int, error) {
 	apiClient := api.NewClientFromHTTP(client)
-	for i, secret := range secrets {
-		if secret.SelectedReposURL == "" {
-			continue
-		}
-		response := struct {
-			TotalCount int `json:"total_count"`
-		}{}
-		if err := apiClient.REST(host, "GET", secret.SelectedReposURL, nil, &response); err != nil {
-			return fmt.Errorf("failed determining selected repositories for %s: %w", secret.Name, err)
-		}
-		secrets[i].NumSelectedRepos = response.TotalCount
+	response := struct {
+		TotalCount int `json:"total_count"`
+	}{}
+	if err := apiClient.REST(host, "GET", selectedReposURL.String(), nil, &response); err != nil {
+		return 0, err
 	}
-	return nil
+	return response.TotalCount, nil
 }
diff --git a/pkg/cmd/secret/set/http.go b/pkg/cmd/secret/set/http.go
--- a/pkg/cmd/secret/set/http.go
+++ b/pkg/cmd/secret/set/http.go
@@ -8,6 +8,7 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/secret/shared"
 )
 
@@ -30,45 +31,62 @@ type PubKey struct {
 	Key string
 }
 
-func getPubKey(client *api.Client, host, path string) (*PubKey, error) {
+func getPubKey(client *api.Client, host string, path safeurl.SafeURL) (*PubKey, error) {
 	pk := PubKey{}
-	err := client.REST(host, "GET", path, nil, &pk)
+	err := client.REST(host, "GET", path.String(), nil, &pk)
 	if err != nil {
 		return nil, err
 	}
 	return &pk, nil
 }
 
 func getOrgPublicKey(client *api.Client, host, orgName string, app shared.App) (*PubKey, error) {
-	return getPubKey(client, host, fmt.Sprintf("orgs/%s/%s/secrets/public-key", orgName, app))
+	u, err := safeurl.JoinPath("orgs", orgName, string(app), "secrets", "public-key")
+	if err != nil {
+		return nil, err
+	}
+	return getPubKey(client, host, u)
 }
 
 func getUserPublicKey(client *api.Client, host string) (*PubKey, error) {
-	return getPubKey(client, host, "user/codespaces/secrets/public-key")
+	u, err := safeurl.JoinPath("user", "codespaces", "secrets", "public-key")
+	if err != nil {
+		return nil, err
+	}
+	return getPubKey(client, host, u)
 }
 
 func getRepoPubKey(client *api.Client, repo ghrepo.Interface, app shared.App) (*PubKey, error) {
-	return getPubKey(client, repo.RepoHost(), fmt.Sprintf("repos/%s/%s/secrets/public-key",
-		ghrepo.FullName(repo), app))
+	u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), string(app), "secrets", "public-key")
+	if err != nil {
+		return nil, err
+	}
+	return getPubKey(client, repo.RepoHost(), u)
 }
 
 func getEnvPubKey(client *api.Client, repo ghrepo.Interface, envName string) (*PubKey, error) {
-	return getPubKey(client, repo.RepoHost(), fmt.Sprintf("repos/%s/environments/%s/secrets/public-key",
-		ghrepo.FullName(repo), envName))
+	u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "environments", envName, "secrets", "public-key")
+	if err != nil {
+		return nil, err
+	}
+	return getPubKey(client, repo.RepoHost(), u)
 }
 
-func putSecret(client *api.Client, host, path string, payload interface{}) error {
+func putSecret(client *api.Client, host string, path safeurl.SafeURL, payload interface{}) error {
 	payloadBytes, err := json.Marshal(payload)
 	if err != nil {
 		return fmt.Errorf("failed to serialize: %w", err)
 	}
 	requestBody := bytes.NewReader(payloadBytes)
 
-	return client.REST(host, "PUT", path, requestBody, nil)
+	return client.REST(host, "PUT", path.String(), requestBody, nil)
 }
 
 func putOrgSecret(client *api.Client, host string, pk *PubKey, orgName, visibility, secretName, eValue string, repositoryIDs []int64, app shared.App) error {
-	path := fmt.Sprintf("orgs/%s/%s/secrets/%s", orgName, app, secretName)
+	path, err := safeurl.JoinPath("orgs", orgName, string(app), "secrets", secretName)
+	if err != nil {
+		return err
+	}
 
 	if app == shared.Dependabot {
 		repos := make([]string, len(repositoryIDs))
@@ -102,7 +120,10 @@ func putUserSecret(client *api.Client, host string, pk *PubKey, key, eValue stri
 		KeyID:          pk.ID,
 		Repositories:   repositoryIDs,
 	}
-	path := fmt.Sprintf("user/codespaces/secrets/%s", key)
+	path, err := safeurl.JoinPath("user", "codespaces", "secrets", key)
+	if err != nil {
+		return err
+	}
 	return putSecret(client, host, path, payload)
 }
 
@@ -111,7 +132,10 @@ func putEnvSecret(client *api.Client, pk *PubKey, repo ghrepo.Interface, envName
 		EncryptedValue: eValue,
 		KeyID:          pk.ID,
 	}
-	path := fmt.Sprintf("repos/%s/environments/%s/secrets/%s", ghrepo.FullName(repo), envName, secretName)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "environments", envName, "secrets", secretName)
+	if err != nil {
+		return err
+	}
 	return putSecret(client, repo.RepoHost(), path, payload)
 }
 
@@ -120,6 +144,9 @@ func putRepoSecret(client *api.Client, pk *PubKey, repo ghrepo.Interface, secret
 		EncryptedValue: eValue,
 		KeyID:          pk.ID,
 	}
-	path := fmt.Sprintf("repos/%s/%s/secrets/%s", ghrepo.FullName(repo), app, secretName)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), string(app), "secrets", secretName)
+	if err != nil {
+		return err
+	}
 	return putSecret(client, repo.RepoHost(), path, payload)
 }
diff --git a/pkg/cmd/skills/install/install.go b/pkg/cmd/skills/install/install.go
--- a/pkg/cmd/skills/install/install.go
+++ b/pkg/cmd/skills/install/install.go
@@ -19,6 +19,7 @@ import (
 	"github.com/cli/cli/v2/internal/ghinstance"
 	"github.com/cli/cli/v2/internal/ghrepo"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/skills/discovery"
 	"github.com/cli/cli/v2/internal/skills/frontmatter"
 	"github.com/cli/cli/v2/internal/skills/installer"
@@ -1296,14 +1297,16 @@ func filterHiddenDirSkills(opts *InstallOptions, allSkills []discovery.Skill) ([
 // installs from the re-publisher.
 // Returns (repo to redirect to, whether upstream was detected, error).
 func checkUpstreamProvenance(opts *InstallOptions, client *api.Client, hostname string, skill discovery.Skill, commitSHA string) (ghrepo.Interface, bool, error) {
-	apiPath := fmt.Sprintf("repos/%s/%s/contents/%s?ref=%s",
-		opts.repo.RepoOwner(), opts.repo.RepoName(),
-		skill.Path+"/SKILL.md", commitSHA)
+	u, err := safeurl.JoinPath("repos", opts.repo.RepoOwner(), opts.repo.RepoName(), "contents", skill.Path+"/SKILL.md")
+	if err != nil {
+		return nil, false, err
+	}
+	u.SetQuery("ref", commitSHA)
 	var fileResp struct {
 		Content  string `json:"content"`
 		Encoding string `json:"encoding"`
 	}
-	if err := client.REST(hostname, "GET", apiPath, nil, &fileResp); err != nil {
+	if err := client.REST(hostname, "GET", u.String(), nil, &fileResp); err != nil {
 		return nil, false, nil //nolint:nilerr // best-effort check; failing to fetch is not fatal
 	}
 	if fileResp.Encoding != "base64" {
diff --git a/pkg/cmd/skills/publish/publish.go b/pkg/cmd/skills/publish/publish.go
--- a/pkg/cmd/skills/publish/publish.go
+++ b/pkg/cmd/skills/publish/publish.go
@@ -20,6 +20,7 @@ import (
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/skills/discovery"
 	"github.com/cli/cli/v2/internal/skills/frontmatter"
 	"github.com/cli/cli/v2/internal/skills/registry"
@@ -443,9 +444,12 @@ func repoHasTopic(client *api.Client, host, owner, repo string) bool {
 	if client == nil {
 		return false
 	}
-	apiPath := fmt.Sprintf("repos/%s/%s/topics", owner, repo)
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "topics")
+	if err != nil {
+		return false
+	}
 	var resp repoTopicsResponse
-	if err := client.REST(host, "GET", apiPath, nil, &resp); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &resp); err != nil {
 		return false
 	}
 	for _, t := range resp.Names {
@@ -461,9 +465,13 @@ func fetchTags(client *api.Client, host, owner, repo string) []tagEntry {
 	if client == nil {
 		return nil
 	}
-	apiPath := fmt.Sprintf("repos/%s/%s/tags?per_page=10", owner, repo)
+	u, err := safeurl.JoinPath("repos", owner, repo, "tags")
+	if err != nil {
+		return nil
+	}
+	u.SetQuery("per_page", "10")
 	var tags []tagEntry
-	if err := client.REST(host, "GET", apiPath, nil, &tags); err != nil {
+	if err := client.REST(host, "GET", u.String(), nil, &tags); err != nil {
 		return nil
 	}
 	return tags
@@ -609,11 +617,14 @@ func runPublishRelease(opts *PublishOptions, client *api.Client, host, owner, re
 		return fmt.Errorf("failed to serialize release request: %w", err)
 	}
 
-	releasePath := fmt.Sprintf("repos/%s/%s/releases", owner, repo)
+	releasePath, err := safeurl.JoinPath("repos", owner, repo, "releases")
+	if err != nil {
+		return err
+	}
 	var releaseResp struct {
 		HTMLURL string `json:"html_url"`
 	}
-	if err := client.REST(host, "POST", releasePath, bytes.NewReader(releaseJSON), &releaseResp); err != nil {
+	if err := client.REST(host, "POST", releasePath.String(), bytes.NewReader(releaseJSON), &releaseResp); err != nil {
 		return fmt.Errorf("failed to create release: %w", err)
 	}
 
@@ -683,19 +694,26 @@ func detectDefaultBranch(client *api.Client, host, owner, repo string) string {
 	var result struct {
 		DefaultBranch string `json:"default_branch"`
 	}
-	if err := client.REST(host, "GET", fmt.Sprintf("repos/%s/%s", owner, repo), nil, &result); err != nil {
+	apiPath, err := safeurl.JoinPath("repos", owner, repo)
+	if err != nil {
+		return ""
+	}
+	if err := client.REST(host, "GET", apiPath.String(), nil, &result); err != nil {
 		return ""
 	}
 	return result.DefaultBranch
 }
 
 // addAgentSkillsTopic adds the "agent-skills" topic to the repo, preserving existing topics.
 func addAgentSkillsTopic(client *api.Client, host, owner, repo string) error {
-	apiPath := fmt.Sprintf("repos/%s/%s/topics", owner, repo)
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "topics")
+	if err != nil {
+		return err
+	}
 
 	// Fetch existing topics
 	var resp repoTopicsResponse
-	if err := client.REST(host, "GET", apiPath, nil, &resp); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &resp); err != nil {
 		return fmt.Errorf("could not fetch existing topics: %w", err)
 	}
 
@@ -711,39 +729,48 @@ func addAgentSkillsTopic(client *api.Client, host, owner, repo string) error {
 	if err != nil {
 		return fmt.Errorf("could not serialize topics: %w", err)
 	}
-	return client.REST(host, "PUT", apiPath, bytes.NewReader(topicsJSON), nil)
+	return client.REST(host, "PUT", apiPath.String(), bytes.NewReader(topicsJSON), nil)
 }
 
 // checkImmutableReleases checks if immutable releases are enabled for the repo.
 func checkImmutableReleases(client *api.Client, host, owner, repo string) bool {
 	if client == nil {
 		return false
 	}
-	apiPath := fmt.Sprintf("repos/%s/%s/immutable-releases", owner, repo)
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "immutable-releases")
+	if err != nil {
+		return false
+	}
 	var resp struct {
 		Enabled bool `json:"enabled"`
 	}
-	if err := client.REST(host, "GET", apiPath, nil, &resp); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &resp); err != nil {
 		return false
 	}
 	return resp.Enabled
 }
 
 // enableImmutableReleases enables immutable releases for the repo.
 func enableImmutableReleases(client *api.Client, host, owner, repo string) error {
-	apiPath := fmt.Sprintf("repos/%s/%s/immutable-releases", owner, repo)
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "immutable-releases")
+	if err != nil {
+		return err
+	}
 	body := bytes.NewReader([]byte(`{"enabled":true}`))
-	return client.REST(host, "PATCH", apiPath, body, nil)
+	return client.REST(host, "PATCH", apiPath.String(), body, nil)
 }
 
 // checkTagProtection checks whether tag protection rulesets are enabled.
 func checkTagProtection(client *api.Client, host, owner, repo string) []publishDiagnostic {
 	if client == nil {
 		return nil
 	}
-	apiPath := fmt.Sprintf("repos/%s/%s/rulesets", owner, repo)
+	apiPath, err := safeurl.JoinPath("repos", owner, repo, "rulesets")
+	if err != nil {
+		return nil
+	}
 	var rulesets []rulesetsResponse
-	if err := client.REST(host, "GET", apiPath, nil, &rulesets); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &rulesets); err != nil {
 		return nil
 	}
 
@@ -764,9 +791,12 @@ func checkSecuritySettings(client *api.Client, host, owner, repo string, skillDi
 	if client == nil {
 		return nil
 	}
-	apiPath := fmt.Sprintf("repos/%s/%s", owner, repo)
+	apiPath, err := safeurl.JoinPath("repos", owner, repo)
+	if err != nil {
+		return nil
+	}
 	var resp repoSecurityResponse
-	if err := client.REST(host, "GET", apiPath, nil, &resp); err != nil {
+	if err := client.REST(host, "GET", apiPath.String(), nil, &resp); err != nil {
 		return nil
 	}
 
@@ -794,22 +824,26 @@ func checkSecuritySettings(client *api.Client, host, owner, repo string, skillDi
 	hasCode, hasManifests := detectCodeAndManifests(skillDirs)
 
 	if hasCode {
-		alertsPath := fmt.Sprintf("repos/%s/%s/code-scanning/alerts?per_page=1&state=open", owner, repo)
-		if err := client.REST(host, "GET", alertsPath, nil, new([]interface{})); err != nil {
-			diagnostics = append(diagnostics, publishDiagnostic{
-				severity: "info",
-				message:  "skills include code files but code scanning does not appear to be configured (Settings > Code security > Code scanning)",
-			})
+		if u, err := safeurl.JoinPath("repos", owner, repo, "code-scanning", "alerts"); err == nil {
+			u.SetQuery("per_page", "1")
+			u.SetQuery("state", "open")
+			if err := client.REST(host, "GET", u.String(), nil, new([]interface{})); err != nil {
+				diagnostics = append(diagnostics, publishDiagnostic{
+					severity: "info",
+					message:  "skills include code files but code scanning does not appear to be configured (Settings > Code security > Code scanning)",
+				})
+			}
 		}
 	}
 
 	if hasManifests {
-		dependabotPath := fmt.Sprintf("repos/%s/%s/vulnerability-alerts", owner, repo)
-		if err := client.REST(host, "GET", dependabotPath, nil, nil); err != nil {
-			diagnostics = append(diagnostics, publishDiagnostic{
-				severity: "info",
-				message:  "skills include dependency manifests but Dependabot alerts do not appear to be enabled (Settings > Code security > Dependabot)",
-			})
+		if dependabotPath, err := safeurl.JoinPath("repos", owner, repo, "vulnerability-alerts"); err == nil {
+			if err := client.REST(host, "GET", dependabotPath.String(), nil, nil); err != nil {
+				diagnostics = append(diagnostics, publishDiagnostic{
+					severity: "info",
+					message:  "skills include dependency manifests but Dependabot alerts do not appear to be enabled (Settings > Code security > Dependabot)",
+				})
+			}
 		}
 	}
 
diff --git a/pkg/cmd/skills/search/search.go b/pkg/cmd/skills/search/search.go
--- a/pkg/cmd/skills/search/search.go
+++ b/pkg/cmd/skills/search/search.go
@@ -5,10 +5,10 @@ import (
 	"fmt"
 	"math"
 	"net/http"
-	"net/url"
 	"os"
 	"os/exec"
 	"sort"
+	"strconv"
 	"strings"
 	"sync"
 
@@ -17,6 +17,7 @@ import (
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/gh/ghtelemetry"
 	"github.com/cli/cli/v2/internal/prompter"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/skills/discovery"
 	"github.com/cli/cli/v2/internal/skills/frontmatter"
 	"github.com/cli/cli/v2/internal/skills/registry"
@@ -733,10 +734,15 @@ const rateLimitErrorMessage = "GitHub API rate limit exceeded. Please wait a min
 
 // executeSearch performs a single GitHub Code Search API call.
 func executeSearch(client *api.Client, host, query string, page, pageSize int) (*codeSearchResult, error) {
-	apiPath := fmt.Sprintf("search/code?q=%s&per_page=%d&page=%d",
-		url.QueryEscape(query), pageSize, page)
+	apiPath, err := safeurl.JoinPath("search", "code")
+	if err != nil {
+		return nil, err
+	}
+	apiPath.SetQuery("q", query)
+	apiPath.SetQuery("per_page", strconv.Itoa(pageSize))
+	apiPath.SetQuery("page", strconv.Itoa(page))
 	var result codeSearchResult
-	err := client.REST(host, "GET", apiPath, nil, &result)
+	err = client.REST(host, "GET", apiPath.String(), nil, &result)
 	if err != nil && isRateLimitError(err) {
 		return nil, fmt.Errorf("%s", rateLimitErrorMessage)
 	}
@@ -914,9 +920,12 @@ func fetchRepoStars(client *api.Client, host string, skills []skillResult) map[i
 			sem <- struct{}{}
 			defer func() { <-sem }()
 
-			apiPath := fmt.Sprintf("repos/%s/%s", owner, repo)
+			apiPath, err := safeurl.JoinPath("repos", owner, repo)
+			if err != nil {
+				return
+			}
 			var info repoInfo
-			if err := client.REST(host, "GET", apiPath, nil, &info); err != nil {
+			if err := client.REST(host, "GET", apiPath.String(), nil, &info); err != nil {
 				return
 			}
 			mu.Lock()
diff --git a/pkg/cmd/ssh-key/add/http.go b/pkg/cmd/ssh-key/add/http.go
--- a/pkg/cmd/ssh-key/add/http.go
+++ b/pkg/cmd/ssh-key/add/http.go
@@ -10,12 +10,16 @@ import (
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/ssh-key/shared"
 )
 
 // Uploads the provided SSH key. Returns true if the key was uploaded, false if it was not.
 func SSHKeyUpload(httpClient *http.Client, hostname string, keyFile io.Reader, title string) (bool, error) {
-	url := ghinstance.RESTPrefix(hostname) + "user/keys"
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(hostname), "user", "keys")
+	if err != nil {
+		return false, err
+	}
 
 	keyBytes, err := io.ReadAll(keyFile)
 	if err != nil {
@@ -46,7 +50,7 @@ func SSHKeyUpload(httpClient *http.Client, hostname string, keyFile io.Reader, t
 		"key":   fullUserKey,
 	}
 
-	err = keyUpload(httpClient, url, payload)
+	err = keyUpload(httpClient, u, payload)
 
 	if err != nil {
 		return false, err
@@ -57,7 +61,10 @@ func SSHKeyUpload(httpClient *http.Client, hostname string, keyFile io.Reader, t
 
 // Uploads the provided SSH Signing key. Returns true if the key was uploaded, false if it was not.
 func SSHSigningKeyUpload(httpClient *http.Client, hostname string, keyFile io.Reader, title string) (bool, error) {
-	url := ghinstance.RESTPrefix(hostname) + "user/ssh_signing_keys"
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(hostname), "user", "ssh_signing_keys")
+	if err != nil {
+		return false, err
+	}
 
 	keyBytes, err := io.ReadAll(keyFile)
 	if err != nil {
@@ -88,7 +95,7 @@ func SSHSigningKeyUpload(httpClient *http.Client, hostname string, keyFile io.Re
 		"key":   fullUserKey,
 	}
 
-	err = keyUpload(httpClient, url, payload)
+	err = keyUpload(httpClient, u, payload)
 
 	if err != nil {
 		return false, err
@@ -97,13 +104,13 @@ func SSHSigningKeyUpload(httpClient *http.Client, hostname string, keyFile io.Re
 	return true, nil
 }
 
-func keyUpload(httpClient *http.Client, url string, payload map[string]string) error {
+func keyUpload(httpClient *http.Client, u safeurl.SafeURL, payload map[string]string) error {
 	payloadBytes, err := json.Marshal(payload)
 	if err != nil {
 		return err
 	}
 
-	req, err := http.NewRequest("POST", url, bytes.NewBuffer(payloadBytes))
+	req, err := http.NewRequest("POST", u.String(), bytes.NewBuffer(payloadBytes))
 	if err != nil {
 		return err
 	}
diff --git a/pkg/cmd/ssh-key/delete/http.go b/pkg/cmd/ssh-key/delete/http.go
--- a/pkg/cmd/ssh-key/delete/http.go
+++ b/pkg/cmd/ssh-key/delete/http.go
@@ -2,21 +2,24 @@ package delete
 
 import (
 	"encoding/json"
-	"fmt"
 	"io"
 	"net/http"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 type sshKey struct {
 	Title string
 }
 
 func deleteSSHKey(httpClient *http.Client, host string, keyID string) error {
-	url := fmt.Sprintf("%suser/keys/%s", ghinstance.RESTPrefix(host), keyID)
-	req, err := http.NewRequest("DELETE", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "user", "keys", keyID)
+	if err != nil {
+		return err
+	}
+	req, err := http.NewRequest("DELETE", url.String(), nil)
 	if err != nil {
 		return err
 	}
@@ -35,8 +38,11 @@ func deleteSSHKey(httpClient *http.Client, host string, keyID string) error {
 }
 
 func getSSHKey(httpClient *http.Client, host string, keyID string) (*sshKey, error) {
-	url := fmt.Sprintf("%suser/keys/%s", ghinstance.RESTPrefix(host), keyID)
-	req, err := http.NewRequest("GET", url, nil)
+	url, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "user", "keys", keyID)
+	if err != nil {
+		return nil, err
+	}
+	req, err := http.NewRequest("GET", url.String(), nil)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/ssh-key/shared/user_keys.go b/pkg/cmd/ssh-key/shared/user_keys.go
--- a/pkg/cmd/ssh-key/shared/user_keys.go
+++ b/pkg/cmd/ssh-key/shared/user_keys.go
@@ -2,13 +2,13 @@ package shared
 
 import (
 	"encoding/json"
-	"fmt"
 	"io"
 	"net/http"
 	"time"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 const (
@@ -25,13 +25,19 @@ type sshKey struct {
 }
 
 func UserKeys(httpClient *http.Client, host, userHandle string) ([]sshKey, error) {
-	resource := "user/keys"
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "user", "keys")
+	if err != nil {
+		return nil, err
+	}
 	if userHandle != "" {
-		resource = fmt.Sprintf("users/%s/keys", userHandle)
+		u, err = safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "users", userHandle, "keys")
+		if err != nil {
+			return nil, err
+		}
 	}
-	url := fmt.Sprintf("%s%s?per_page=%d", ghinstance.RESTPrefix(host), resource, 100)
+	u.SetQuery("per_page", "100")
 
-	keys, err := getUserKeys(httpClient, url)
+	keys, err := getUserKeys(httpClient, u)
 
 	if err != nil {
 		return nil, err
@@ -45,13 +51,19 @@ func UserKeys(httpClient *http.Client, host, userHandle string) ([]sshKey, error
 }
 
 func UserSigningKeys(httpClient *http.Client, host, userHandle string) ([]sshKey, error) {
-	resource := "user/ssh_signing_keys"
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "user", "ssh_signing_keys")
+	if err != nil {
+		return nil, err
+	}
 	if userHandle != "" {
-		resource = fmt.Sprintf("users/%s/ssh_signing_keys", userHandle)
+		u, err = safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(host), "users", userHandle, "ssh_signing_keys")
+		if err != nil {
+			return nil, err
+		}
 	}
-	url := fmt.Sprintf("%s%s?per_page=%d", ghinstance.RESTPrefix(host), resource, 100)
+	u.SetQuery("per_page", "100")
 
-	keys, err := getUserKeys(httpClient, url)
+	keys, err := getUserKeys(httpClient, u)
 
 	if err != nil {
 		return nil, err
@@ -64,8 +76,8 @@ func UserSigningKeys(httpClient *http.Client, host, userHandle string) ([]sshKey
 	return keys, nil
 }
 
-func getUserKeys(httpClient *http.Client, url string) ([]sshKey, error) {
-	req, err := http.NewRequest("GET", url, nil)
+func getUserKeys(httpClient *http.Client, u safeurl.SafeURL) ([]sshKey, error) {
+	req, err := http.NewRequest("GET", u.String(), nil)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/cmd/status/status.go b/pkg/cmd/status/status.go
--- a/pkg/cmd/status/status.go
+++ b/pkg/cmd/status/status.go
@@ -6,15 +6,16 @@ import (
 	"errors"
 	"fmt"
 	"net/http"
-	"net/url"
 	"sort"
+	"strconv"
 	"strings"
 	"sync"
 	"time"
 
 	"github.com/MakeNowJust/heredoc"
 	"github.com/charmbracelet/lipgloss"
 	"github.com/cli/cli/v2/api"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/tableprinter"
 	"github.com/cli/cli/v2/pkg/cmd/factory"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -233,7 +234,7 @@ func (s *StatusGetter) CurrentUsername() (string, error) {
 	return currentUsername, nil
 }
 
-func (s *StatusGetter) ActualMention(commentURL string) (string, error) {
+func (s *StatusGetter) ActualMention(commentURL safeurl.SafeURL) (string, error) {
 	currentUsername, err := s.CurrentUsername()
 	if err != nil {
 		return "", err
@@ -246,7 +247,7 @@ func (s *StatusGetter) ActualMention(commentURL string) (string, error) {
 	resp := struct {
 		Body string
 	}{}
-	if err := c.REST(s.hostname(), "GET", commentURL, nil, &resp); err != nil {
+	if err := c.REST(s.hostname(), "GET", commentURL.String(), nil, &resp); err != nil {
 		return "", err
 	}
 
@@ -264,10 +265,6 @@ func (s *StatusGetter) ActualMention(commentURL string) (string, error) {
 func (s *StatusGetter) LoadNotifications() error {
 	perPage := 100
 	c := api.NewClientFromHTTP(s.Client)
-	query := url.Values{}
-	query.Add("per_page", fmt.Sprintf("%d", perPage))
-	query.Add("participating", "true")
-	query.Add("all", "true")
 
 	fetchWorkers := 10
 	ctx, abortFetching := context.WithCancel(context.Background())
@@ -286,7 +283,7 @@ func (s *StatusGetter) LoadNotifications() error {
 					if !ok {
 						return nil
 					}
-					actual, err := s.ActualMention(n.Subject.LatestCommentURL)
+					actual, err := s.ActualMention(safeurl.NewImmutableSafeURL(n.Subject.LatestCommentURL))
 
 					if err != nil {
 						var httpErr api.HTTPError
@@ -336,10 +333,17 @@ func (s *StatusGetter) LoadNotifications() error {
 	// do that. I'd switch to the GraphQL version, but to my knowledge that does
 	// not work with PATs right now.
 	nIndex := 0
-	p := fmt.Sprintf("notifications?%s", query.Encode())
+	u, err := safeurl.JoinPath("notifications")
+	if err != nil {
+		return err
+	}
+	u.SetQuery("per_page", strconv.Itoa(perPage))
+	u.SetQuery("participating", "true")
+	u.SetQuery("all", "true")
+	var p safeurl.SafeURL = u
 	for pages := 0; pages < 3; pages++ {
 		var resp []Notification
-		next, err := c.RESTWithNext(s.hostname(), "GET", p, nil, &resp)
+		next, err := c.RESTWithNext(s.hostname(), "GET", p.String(), nil, &resp)
 		if err != nil {
 			var httpErr api.HTTPError
 			if !errors.As(err, &httpErr) || httpErr.StatusCode != 404 {
@@ -365,11 +369,11 @@ func (s *StatusGetter) LoadNotifications() error {
 		if next == "" || len(resp) < perPage {
 			break
 		}
-		p = next
+		p = safeurl.NewImmutableSafeURL(next)
 	}
 
 	close(toFetch)
-	err := wg.Wait()
+	err = wg.Wait()
 	close(fetched)
 	<-doneCh
 	sort.Slice(s.Mentions, func(i, j int) bool {
@@ -530,8 +534,6 @@ func (s *StatusGetter) LoadSearchResults() error {
 func (s *StatusGetter) LoadEvents() error {
 	perPage := 100
 	c := api.NewClientFromHTTP(s.Client)
-	query := url.Values{}
-	query.Add("per_page", fmt.Sprintf("%d", perPage))
 
 	currentUsername, err := s.CurrentUsername()
 	if err != nil {
@@ -541,9 +543,14 @@ func (s *StatusGetter) LoadEvents() error {
 	var events []Event
 	var resp []Event
 	pages := 0
-	p := fmt.Sprintf("users/%s/received_events?%s", currentUsername, query.Encode())
+	u, err := safeurl.JoinPath("users", currentUsername, "received_events")
+	if err != nil {
+		return err
+	}
+	u.SetQuery("per_page", strconv.Itoa(perPage))
+	var p safeurl.SafeURL = u
 	for pages < 2 {
-		next, err := c.RESTWithNext(s.hostname(), "GET", p, nil, &resp)
+		next, err := c.RESTWithNext(s.hostname(), "GET", p.String(), nil, &resp)
 		if err != nil {
 			var httpErr api.HTTPError
 			if !errors.As(err, &httpErr) || httpErr.StatusCode != 404 {
@@ -556,7 +563,7 @@ func (s *StatusGetter) LoadEvents() error {
 		}
 
 		pages++
-		p = next
+		p = safeurl.NewImmutableSafeURL(next)
 	}
 
 	s.RepoActivity = []StatusItem{}
diff --git a/pkg/cmd/variable/delete/delete.go b/pkg/cmd/variable/delete/delete.go
--- a/pkg/cmd/variable/delete/delete.go
+++ b/pkg/cmd/variable/delete/delete.go
@@ -8,6 +8,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/variable/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -96,21 +97,24 @@ func removeRun(opts *DeleteOptions) error {
 		return err
 	}
 
-	var path string
+	var path *safeurl.MutableSafeURL
 	var host string
 	switch variableEntity {
 	case shared.Organization:
-		path = fmt.Sprintf("orgs/%s/actions/variables/%s", orgName, opts.VariableName)
+		path, err = safeurl.JoinPath("orgs", orgName, "actions", "variables", opts.VariableName)
 		host, _ = cfg.Authentication().DefaultHost()
 	case shared.Environment:
-		path = fmt.Sprintf("repos/%s/environments/%s/variables/%s", ghrepo.FullName(baseRepo), envName, opts.VariableName)
+		path, err = safeurl.JoinPath("repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "environments", envName, "variables", opts.VariableName)
 		host = baseRepo.RepoHost()
 	case shared.Repository:
-		path = fmt.Sprintf("repos/%s/actions/variables/%s", ghrepo.FullName(baseRepo), opts.VariableName)
+		path, err = safeurl.JoinPath("repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "actions", "variables", opts.VariableName)
 		host = baseRepo.RepoHost()
 	}
+	if err != nil {
+		return err
+	}
 
-	err = client.REST(host, "DELETE", path, nil, nil)
+	err = client.REST(host, "DELETE", path.String(), nil, nil)
 	if err != nil {
 		return fmt.Errorf("failed to delete variable %s: %w", opts.VariableName, err)
 	}
diff --git a/pkg/cmd/variable/get/get.go b/pkg/cmd/variable/get/get.go
--- a/pkg/cmd/variable/get/get.go
+++ b/pkg/cmd/variable/get/get.go
@@ -9,6 +9,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/variable/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -97,22 +98,25 @@ func getRun(opts *GetOptions) error {
 		return err
 	}
 
-	var path string
+	var path *safeurl.MutableSafeURL
 	var host string
 	switch variableEntity {
 	case shared.Organization:
-		path = fmt.Sprintf("orgs/%s/actions/variables/%s", orgName, opts.VariableName)
+		path, err = safeurl.JoinPath("orgs", orgName, "actions", "variables", opts.VariableName)
 		host, _ = cfg.Authentication().DefaultHost()
 	case shared.Environment:
-		path = fmt.Sprintf("repos/%s/environments/%s/variables/%s", ghrepo.FullName(baseRepo), envName, opts.VariableName)
+		path, err = safeurl.JoinPath("repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "environments", envName, "variables", opts.VariableName)
 		host = baseRepo.RepoHost()
 	case shared.Repository:
-		path = fmt.Sprintf("repos/%s/actions/variables/%s", ghrepo.FullName(baseRepo), opts.VariableName)
+		path, err = safeurl.JoinPath("repos", baseRepo.RepoOwner(), baseRepo.RepoName(), "actions", "variables", opts.VariableName)
 		host = baseRepo.RepoHost()
 	}
+	if err != nil {
+		return err
+	}
 
 	var variable shared.Variable
-	if err = client.REST(host, "GET", path, nil, &variable); err != nil {
+	if err = client.REST(host, "GET", path.String(), nil, &variable); err != nil {
 		var httpErr api.HTTPError
 		if errors.As(err, &httpErr) && httpErr.StatusCode == http.StatusNotFound {
 			return fmt.Errorf("variable %s was not found", opts.VariableName)
@@ -122,8 +126,12 @@ func getRun(opts *GetOptions) error {
 	}
 
 	if opts.Exporter != nil {
-		if err := shared.PopulateSelectedRepositoryInformation(client, host, &variable); err != nil {
-			return err
+		if variable.SelectedReposURL != "" {
+			count, err := shared.SelectedRepositoryCount(client, host, safeurl.NewImmutableSafeURL(variable.SelectedReposURL))
+			if err != nil {
+				return fmt.Errorf("failed determining selected repositories for %s: %w", variable.Name, err)
+			}
+			variable.NumSelectedRepos = count
 		}
 		return opts.Exporter.Write(opts.IO, &variable)
 	}
diff --git a/pkg/cmd/variable/list/list.go b/pkg/cmd/variable/list/list.go
--- a/pkg/cmd/variable/list/list.go
+++ b/pkg/cmd/variable/list/list.go
@@ -11,6 +11,7 @@ import (
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/gh"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/internal/tableprinter"
 	"github.com/cli/cli/v2/pkg/cmd/variable/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
@@ -193,42 +194,60 @@ func fmtVisibility(s shared.Variable) string {
 }
 
 func getRepoVariables(client *http.Client, repo ghrepo.Interface) ([]shared.Variable, error) {
-	return getVariables(client, repo.RepoHost(), fmt.Sprintf("repos/%s/actions/variables", ghrepo.FullName(repo)))
+	u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "variables")
+	if err != nil {
+		return nil, err
+	}
+	return getVariables(client, repo.RepoHost(), u)
 }
 
 func getEnvVariables(client *http.Client, repo ghrepo.Interface, envName string) ([]shared.Variable, error) {
-	path := fmt.Sprintf("repos/%s/environments/%s/variables", ghrepo.FullName(repo), envName)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "environments", envName, "variables")
+	if err != nil {
+		return nil, err
+	}
 	return getVariables(client, repo.RepoHost(), path)
 }
 
 func getOrgVariables(client *http.Client, host, orgName string, showSelectedRepoInfo bool) ([]shared.Variable, error) {
-	variables, err := getVariables(client, host, fmt.Sprintf("orgs/%s/actions/variables", orgName))
+	u, err := safeurl.JoinPath("orgs", orgName, "actions", "variables")
+	if err != nil {
+		return nil, err
+	}
+	variables, err := getVariables(client, host, u)
 	if err != nil {
 		return nil, err
 	}
 	apiClient := api.NewClientFromHTTP(client)
 	if showSelectedRepoInfo {
-		err = shared.PopulateMultipleSelectedRepositoryInformation(apiClient, host, variables)
-		if err != nil {
-			return nil, err
+		for i := range variables {
+			if variables[i].SelectedReposURL == "" {
+				continue
+			}
+			count, err := shared.SelectedRepositoryCount(apiClient, host, safeurl.NewImmutableSafeURL(variables[i].SelectedReposURL))
+			if err != nil {
+				return nil, fmt.Errorf("failed determining selected repositories for %s: %w", variables[i].Name, err)
+			}
+			variables[i].NumSelectedRepos = count
 		}
 	}
 	return variables, nil
 }
 
-func getVariables(client *http.Client, host, path string) ([]shared.Variable, error) {
+func getVariables(client *http.Client, host string, u *safeurl.MutableSafeURL) ([]shared.Variable, error) {
 	var results []shared.Variable
 	apiClient := api.NewClientFromHTTP(client)
-	path = fmt.Sprintf("%s?per_page=100", path)
-	for path != "" {
+	u.SetQuery("per_page", "100")
+	var pageURL safeurl.SafeURL = u
+	for pageURL.String() != "" {
 		response := struct {
 			Variables []shared.Variable
 		}{}
-		var err error
-		path, err = apiClient.RESTWithNext(host, "GET", path, nil, &response)
+		next, err := apiClient.RESTWithNext(host, "GET", pageURL.String(), nil, &response)
 		if err != nil {
 			return nil, err
 		}
+		pageURL = safeurl.NewImmutableSafeURL(next)
 		results = append(results, response.Variables...)
 	}
 	return results, nil
diff --git a/pkg/cmd/variable/set/http.go b/pkg/cmd/variable/set/http.go
--- a/pkg/cmd/variable/set/http.go
+++ b/pkg/cmd/variable/set/http.go
@@ -5,9 +5,11 @@ import (
 	"encoding/json"
 	"errors"
 	"fmt"
+	"strconv"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/variable/shared"
 )
 
@@ -82,13 +84,13 @@ func setVariable(client *api.Client, host string, opts setOptions) setResult {
 	return result
 }
 
-func postVariable(client *api.Client, host, path string, payload interface{}) error {
+func postVariable(client *api.Client, host string, path safeurl.SafeURL, payload interface{}) error {
 	payloadBytes, err := json.Marshal(payload)
 	if err != nil {
 		return fmt.Errorf("failed to serialize: %w", err)
 	}
 	requestBody := bytes.NewReader(payloadBytes)
-	return client.REST(host, "POST", path, requestBody, nil)
+	return client.REST(host, "POST", path.String(), requestBody, nil)
 }
 
 func postOrgVariable(client *api.Client, host, orgName, visibility, variableName, value string, repositoryIDs []int64) error {
@@ -98,7 +100,10 @@ func postOrgVariable(client *api.Client, host, orgName, visibility, variableName
 		Visibility:   visibility,
 		Repositories: repositoryIDs,
 	}
-	path := fmt.Sprintf(`orgs/%s/actions/variables`, orgName)
+	path, err := safeurl.JoinPath("orgs", orgName, "actions", "variables")
+	if err != nil {
+		return err
+	}
 	return postVariable(client, host, path, payload)
 }
 
@@ -107,7 +112,10 @@ func postEnvVariable(client *api.Client, host string, repoID int64, envName, var
 		Name:  variableName,
 		Value: value,
 	}
-	path := fmt.Sprintf(`repositories/%d/environments/%s/variables`, repoID, envName)
+	path, err := safeurl.JoinPath("repositories", strconv.FormatInt(repoID, 10), "environments", envName, "variables")
+	if err != nil {
+		return err
+	}
 	return postVariable(client, host, path, payload)
 }
 
@@ -116,17 +124,20 @@ func postRepoVariable(client *api.Client, repo ghrepo.Interface, variableName, v
 		Name:  variableName,
 		Value: value,
 	}
-	path := fmt.Sprintf(`repos/%s/actions/variables`, ghrepo.FullName(repo))
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "variables")
+	if err != nil {
+		return err
+	}
 	return postVariable(client, repo.RepoHost(), path, payload)
 }
 
-func patchVariable(client *api.Client, host, path string, payload interface{}) error {
+func patchVariable(client *api.Client, host string, path safeurl.SafeURL, payload interface{}) error {
 	payloadBytes, err := json.Marshal(payload)
 	if err != nil {
 		return fmt.Errorf("failed to serialize: %w", err)
 	}
 	requestBody := bytes.NewReader(payloadBytes)
-	return client.REST(host, "PATCH", path, requestBody, nil)
+	return client.REST(host, "PATCH", path.String(), requestBody, nil)
 }
 
 func patchOrgVariable(client *api.Client, host, orgName, visibility, variableName, value string, repositoryIDs []int64) error {
@@ -135,22 +146,31 @@ func patchOrgVariable(client *api.Client, host, orgName, visibility, variableNam
 		Visibility:   visibility,
 		Repositories: repositoryIDs,
 	}
-	path := fmt.Sprintf(`orgs/%s/actions/variables/%s`, orgName, variableName)
+	path, err := safeurl.JoinPath("orgs", orgName, "actions", "variables", variableName)
+	if err != nil {
+		return err
+	}
 	return patchVariable(client, host, path, payload)
 }
 
 func patchEnvVariable(client *api.Client, host string, repoID int64, envName, variableName, value string) error {
 	payload := setPayload{
 		Value: value,
 	}
-	path := fmt.Sprintf(`repositories/%d/environments/%s/variables/%s`, repoID, envName, variableName)
+	path, err := safeurl.JoinPath("repositories", strconv.FormatInt(repoID, 10), "environments", envName, "variables", variableName)
+	if err != nil {
+		return err
+	}
 	return patchVariable(client, host, path, payload)
 }
 
 func patchRepoVariable(client *api.Client, repo ghrepo.Interface, variableName, value string) error {
 	payload := setPayload{
 		Value: value,
 	}
-	path := fmt.Sprintf(`repos/%s/actions/variables/%s`, ghrepo.FullName(repo), variableName)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "variables", variableName)
+	if err != nil {
+		return err
+	}
 	return patchVariable(client, repo.RepoHost(), path, payload)
 }
diff --git a/pkg/cmd/variable/shared/shared.go b/pkg/cmd/variable/shared/shared.go
--- a/pkg/cmd/variable/shared/shared.go
+++ b/pkg/cmd/variable/shared/shared.go
@@ -2,10 +2,10 @@ package shared
 
 import (
 	"errors"
-	"fmt"
 	"time"
 
 	"github.com/cli/cli/v2/api"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 )
 
@@ -66,27 +66,14 @@ func GetVariableEntity(orgName, envName string) (VariableEntity, error) {
 	return Repository, nil
 }
 
-func PopulateMultipleSelectedRepositoryInformation(apiClient *api.Client, host string, variables []Variable) error {
-	for i, variable := range variables {
-		if err := PopulateSelectedRepositoryInformation(apiClient, host, &variable); err != nil {
-			return err
-		}
-		variables[i] = variable
-	}
-	return nil
-}
-
-func PopulateSelectedRepositoryInformation(apiClient *api.Client, host string, variable *Variable) error {
-	if variable.SelectedReposURL == "" {
-		return nil
-	}
-
+// SelectedRepositoryCount returns how many repositories the variable is visible to, fetched from the
+// given entrusted URL. Callers own reading the URL off the variable and writing the result back.
+func SelectedRepositoryCount(apiClient *api.Client, host string, selectedReposURL safeurl.SafeURL) (int, error) {
 	response := struct {
 		TotalCount int `json:"total_count"`
 	}{}
-	if err := apiClient.REST(host, "GET", variable.SelectedReposURL, nil, &response); err != nil {
-		return fmt.Errorf("failed determining selected repositories for %s: %w", variable.Name, err)
+	if err := apiClient.REST(host, "GET", selectedReposURL.String(), nil, &response); err != nil {
+		return 0, err
 	}
-	variable.NumSelectedRepos = response.TotalCount
-	return nil
+	return response.TotalCount, nil
 }
diff --git a/pkg/cmd/workflow/disable/disable.go b/pkg/cmd/workflow/disable/disable.go
--- a/pkg/cmd/workflow/disable/disable.go
+++ b/pkg/cmd/workflow/disable/disable.go
@@ -4,9 +4,11 @@ import (
 	"errors"
 	"fmt"
 	"net/http"
+	"strconv"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/workflow/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -84,8 +86,11 @@ func runDisable(opts *DisableOptions) error {
 		return err
 	}
 
-	path := fmt.Sprintf("repos/%s/actions/workflows/%d/disable", ghrepo.FullName(repo), workflow.ID)
-	err = client.REST(repo.RepoHost(), "PUT", path, nil, nil)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "workflows", strconv.FormatInt(workflow.ID, 10), "disable")
+	if err != nil {
+		return err
+	}
+	err = client.REST(repo.RepoHost(), "PUT", path.String(), nil, nil)
 	if err != nil {
 		return fmt.Errorf("failed to disable workflow: %w", err)
 	}
diff --git a/pkg/cmd/workflow/enable/enable.go b/pkg/cmd/workflow/enable/enable.go
--- a/pkg/cmd/workflow/enable/enable.go
+++ b/pkg/cmd/workflow/enable/enable.go
@@ -4,9 +4,11 @@ import (
 	"errors"
 	"fmt"
 	"net/http"
+	"strconv"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/workflow/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -84,8 +86,11 @@ func runEnable(opts *EnableOptions) error {
 		return err
 	}
 
-	path := fmt.Sprintf("repos/%s/actions/workflows/%d/enable", ghrepo.FullName(repo), workflow.ID)
-	err = client.REST(repo.RepoHost(), "PUT", path, nil, nil)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "workflows", strconv.FormatInt(workflow.ID, 10), "enable")
+	if err != nil {
+		return err
+	}
+	err = client.REST(repo.RepoHost(), "PUT", path.String(), nil, nil)
 	if err != nil {
 		return fmt.Errorf("failed to enable workflow: %w", err)
 	}
diff --git a/pkg/cmd/workflow/run/run.go b/pkg/cmd/workflow/run/run.go
--- a/pkg/cmd/workflow/run/run.go
+++ b/pkg/cmd/workflow/run/run.go
@@ -7,16 +7,17 @@ import (
 	"fmt"
 	"io"
 	"net/http"
-	"net/url"
 	"reflect"
 	"sort"
+	"strconv"
 	"strings"
 	"time"
 
 	"github.com/MakeNowJust/heredoc"
 	"github.com/cli/cli/v2/api"
 	fd "github.com/cli/cli/v2/internal/featuredetection"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmd/workflow/shared"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
@@ -319,7 +320,10 @@ func runRun(opts *RunOptions) error {
 		return err
 	}
 
-	path := fmt.Sprintf("repos/%s/%s/actions/workflows/%d/dispatches", url.PathEscape(repo.RepoOwner()), url.PathEscape(repo.RepoName()), workflow.ID)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "workflows", strconv.FormatInt(workflow.ID, 10), "dispatches")
+	if err != nil {
+		return err
+	}
 
 	requestBody := map[string]interface{}{
 		"ref":    ref,
@@ -358,7 +362,7 @@ func runRun(opts *RunOptions) error {
 	//
 	// As a related note, the new REST API version (which will come with breaking
 	// changes) will probably default to return 200 + run details.
-	err = client.REST(repo.RepoHost(), "POST", path, body, &response)
+	err = client.REST(repo.RepoHost(), "POST", path.String(), body, &response)
 	if err != nil {
 		return fmt.Errorf("could not create workflow dispatch event: %w", err)
 	}
diff --git a/pkg/cmd/workflow/shared/shared.go b/pkg/cmd/workflow/shared/shared.go
--- a/pkg/cmd/workflow/shared/shared.go
+++ b/pkg/cmd/workflow/shared/shared.go
@@ -6,13 +6,13 @@ import (
 	"errors"
 	"fmt"
 	"io"
-	"net/url"
 	"path"
 	"strconv"
 	"strings"
 
 	"github.com/cli/cli/v2/api"
 	"github.com/cli/cli/v2/internal/ghrepo"
+	"github.com/cli/cli/v2/internal/safeurl"
 	"github.com/cli/cli/v2/pkg/cmdutil"
 	"github.com/cli/cli/v2/pkg/iostreams"
 	"github.com/cli/go-gh/v2/pkg/asciisanitizer"
@@ -69,9 +69,14 @@ func GetWorkflows(client *api.Client, repo ghrepo.Interface, limit int) ([]Workf
 		}
 		var result WorkflowsPayload
 
-		path := fmt.Sprintf("repos/%s/actions/workflows?per_page=%d&page=%d", ghrepo.FullName(repo), perPage, page)
+		u, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "workflows")
+		if err != nil {
+			return nil, err
+		}
+		u.SetQuery("per_page", strconv.Itoa(perPage))
+		u.SetQuery("page", strconv.Itoa(page))
 
-		err := client.REST(repo.RepoHost(), "GET", path, nil, &result)
+		err = client.REST(repo.RepoHost(), "GET", u.String(), nil, &result)
 		if err != nil {
 			return nil, err
 		}
@@ -159,8 +164,11 @@ func isWorkflowFile(f string) bool {
 func getWorkflowByID(client *api.Client, repo ghrepo.Interface, ID string) (*Workflow, error) {
 	var workflow Workflow
 
-	path := fmt.Sprintf("repos/%s/actions/workflows/%s", ghrepo.FullName(repo), url.PathEscape(ID))
-	if err := client.REST(repo.RepoHost(), "GET", path, nil, &workflow); err != nil {
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "actions", "workflows", ID)
+	if err != nil {
+		return nil, err
+	}
+	if err := client.REST(repo.RepoHost(), "GET", path.String(), nil, &workflow); err != nil {
 		return nil, err
 	}
 
@@ -233,18 +241,20 @@ func ResolveWorkflow(p iprompter, io *iostreams.IOStreams, client *api.Client, r
 }
 
 func GetWorkflowContent(client *api.Client, repo ghrepo.Interface, workflow Workflow, ref string) ([]byte, error) {
-	path := fmt.Sprintf("repos/%s/contents/%s", ghrepo.FullName(repo), workflow.Path)
+	path, err := safeurl.JoinPath("repos", repo.RepoOwner(), repo.RepoName(), "contents", workflow.Path)
+	if err != nil {
+		return nil, err
+	}
 	if ref != "" {
-		q := fmt.Sprintf("?ref=%s", url.QueryEscape(ref))
-		path = path + q
+		path.SetQuery("ref", ref)
 	}
 
 	type Result struct {
 		Content string
 	}
 
 	var result Result
-	err := client.REST(repo.RepoHost(), "GET", path, nil, &result)
+	err = client.REST(repo.RepoHost(), "GET", path.String(), nil, &result)
 	if err != nil {
 		return nil, err
 	}
diff --git a/pkg/search/searcher.go b/pkg/search/searcher.go
--- a/pkg/search/searcher.go
+++ b/pkg/search/searcher.go
@@ -12,6 +12,7 @@ import (
 
 	fd "github.com/cli/cli/v2/internal/featuredetection"
 	"github.com/cli/cli/v2/internal/ghinstance"
+	"github.com/cli/cli/v2/internal/safeurl"
 )
 
 const (
@@ -197,10 +198,12 @@ func (s searcher) Issues(query Query) (IssuesResult, error) {
 //
 // For more information, see https://docs.github.com/en/rest/search/search?apiVersion=2022-11-28.
 func (s searcher) search(query Query, result interface{}) (string, error) {
-	path := fmt.Sprintf("%ssearch/%s", ghinstance.RESTPrefix(s.host), query.Kind)
-	qs := url.Values{}
-	qs.Set("page", strconv.Itoa(query.Page))
-	qs.Set("per_page", strconv.Itoa(query.Limit))
+	u, err := safeurl.JoinPathWithHostPrefix(ghinstance.RESTPrefix(s.host), "search", string(query.Kind))
+	if err != nil {
+		return "", err
+	}
+	u.SetQuery("page", strconv.Itoa(query.Page))
+	u.SetQuery("per_page", strconv.Itoa(query.Limit))
 
 	if query.Kind == KindIssues {
 		// TODO advancedIssueSearchCleanup
@@ -213,28 +216,27 @@ func (s searcher) search(query Query, result interface{}) (string, error) {
 		}
 
 		if !features.AdvancedIssueSearchAPI {
-			qs.Set("q", query.StandardSearchString())
+			u.SetQuery("q", query.StandardSearchString())
 		} else {
-			qs.Set("q", query.AdvancedIssueSearchString())
+			u.SetQuery("q", query.AdvancedIssueSearchString())
 
 			// TODO advancedIssueSearchCleanup
 			if features.AdvancedIssueSearchAPIOptIn {
 				// Advanced syntax should be explicitly enabled
-				qs.Set("advanced_search", "true")
+				u.SetQuery("advanced_search", "true")
 			}
 		}
 	} else {
-		qs.Set("q", query.StandardSearchString())
+		u.SetQuery("q", query.StandardSearchString())
 	}
 
 	if query.Order != "" {
-		qs.Set(orderKey, query.Order)
+		u.SetQuery(orderKey, query.Order)
 	}
 	if query.Sort != "" {
-		qs.Set(sortKey, query.Sort)
+		u.SetQuery(sortKey, query.Sort)
 	}
-	url := fmt.Sprintf("%s?%s", path, qs.Encode())
-	req, err := http.NewRequest("GET", url, nil)
+	req, err := http.NewRequest("GET", u.String(), nil)
 	if err != nil {
 		return "", err
 	}
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
