#!/bin/bash
set -uxo pipefail

cd /testbed
# Keep local test servers from being routed through host proxy settings.
export NO_PROXY="localhost,127.0.0.1,0.0.0.0,::1${NO_PROXY:+,$NO_PROXY}"
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1${no_proxy:+,$no_proxy}"
echo "OMNIGRIL_LOCAL_NO_PROXY_ADDED=1"


COMMIT_SHA="f2284b68690d61e185e251db3b20e251f7da12f2"

RUNNABLE_TEST_FILES=(
  server/authflow/handler_test.go
  server/authflow/request_test.go
  server/authflow/sessionlogin_test.go
  server/device/device_test.go
  server/mfa/handler_test.go
  server/server_api_cache_test.go
  server/server_authorize_test.go
  server/server_grant_password_test.go
  server/server_introspection_test.go
  server/server_login_test.go
  server/server_oauth2_test.go
  server/server_test.go
)

DELETED_TEST_PATCH_FILES=()

# --- Pre-patch cleanup: restore runnable files that exist in base commit; remove those that don't.
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${COMMIT_SHA}:$f" 2>/dev/null; then
    git checkout "${COMMIT_SHA}" -- "$f"
  else
    rm -f -- "$f"
  fi
done

# --- Apply test patch (content injected by harness).
TEST_PATCH_FILE="$(mktemp)"
cat > "$TEST_PATCH_FILE" <<'EOF_114329324912'
diff --git a/server/authflow/handler_test.go b/server/authflow/handler_test.go
--- a/server/authflow/handler_test.go
+++ b/server/authflow/handler_test.go
@@ -19,6 +19,7 @@ import (
 	"github.com/dexidp/dex/server/consent"
 	"github.com/dexidp/dex/server/logout"
 	"github.com/dexidp/dex/server/mfa"
+	"github.com/dexidp/dex/server/oauth2"
 	"github.com/dexidp/dex/server/session"
 	"github.com/dexidp/dex/server/signer"
 	"github.com/dexidp/dex/server/templates"
@@ -107,7 +108,7 @@ func newTestHandler(t *testing.T, updateConfig func(c *testFlowConfig)) (*httpte
 
 	tc := testFlowConfig{
 		Handler: Handler{
-			IssuerURL:              *issuerURL,
+			IssuerURL:              oauth2.IssuerURL{URL: *issuerURL},
 			Connectors:             conns,
 			Storage:                store,
 			Templates:              tmpls,
@@ -126,10 +127,10 @@ func newTestHandler(t *testing.T, updateConfig func(c *testFlowConfig)) (*httpte
 
 	// Assemble the flow the same way the server does: shared infrastructure plus
 	// independent step handlers that hand off by redirect.
-	sessions := &session.Manager{Storage: store, Config: tc.SessionConfig, Now: now, Logger: logger, IssuerURL: *issuerURL}
-	mfaManager := &mfa.Handler{IssuerURL: *issuerURL, Storage: store, Templates: tmpls, Logger: logger, MFAProviders: tc.MFAProviders, DefaultMFAChain: tc.DefaultMFAChain, Now: now, Connectors: conns}
-	consentManager := &consent.Handler{IssuerURL: *issuerURL, Storage: store, Templates: tmpls, Logger: logger, Sessions: sessions, SkipApproval: tc.SkipApproval}
-	logoutManager := &logout.Handler{Storage: store, Templates: tmpls, Logger: logger, Sessions: sessions, Connectors: conns, Issuer: issuer, Signer: sig, IssuerURL: *issuerURL}
+	sessions := &session.Manager{Storage: store, Config: tc.SessionConfig, Now: now, Logger: logger, IssuerURL: oauth2.IssuerURL{URL: *issuerURL}}
+	mfaManager := &mfa.Handler{IssuerURL: oauth2.IssuerURL{URL: *issuerURL}, Storage: store, Templates: tmpls, Logger: logger, MFAProviders: tc.MFAProviders, DefaultMFAChain: tc.DefaultMFAChain, Now: now, Connectors: conns}
+	consentManager := &consent.Handler{IssuerURL: oauth2.IssuerURL{URL: *issuerURL}, Storage: store, Templates: tmpls, Logger: logger, Sessions: sessions, SkipApproval: tc.SkipApproval}
+	logoutManager := &logout.Handler{Storage: store, Templates: tmpls, Logger: logger, Sessions: sessions, Connectors: conns, Issuer: issuer, Signer: sig, IssuerURL: oauth2.IssuerURL{URL: *issuerURL}}
 
 	tc.Sessions = sessions
 	tc.Issuer = issuer
diff --git a/server/authflow/request_test.go b/server/authflow/request_test.go
--- a/server/authflow/request_test.go
+++ b/server/authflow/request_test.go
@@ -774,7 +774,7 @@ func TestValidateIDTokenHint(t *testing.T) {
 
 	s := &Handler{
 		Signer:    sig,
-		IssuerURL: *issuerURL,
+		IssuerURL: oauth2.IssuerURL{URL: *issuerURL},
 		Logger:    slog.Default(),
 	}
 
diff --git a/server/authflow/sessionlogin_test.go b/server/authflow/sessionlogin_test.go
--- a/server/authflow/sessionlogin_test.go
+++ b/server/authflow/sessionlogin_test.go
@@ -46,10 +46,10 @@ func newTestSessionServer(t *testing.T) *sessionTestServer {
 		Storage:   memory.New(nil),
 		Now:       func() time.Time { return now },
 		Logger:    slog.Default(),
-		IssuerURL: *issuerURL,
+		IssuerURL: oauth2.IssuerURL{URL: *issuerURL},
 	}
 	h.Connectors = connectors.NewCache(h.Storage, testResolveConnector)
-	h.Sessions = &session.Manager{Storage: h.Storage, Config: sessionCfg, Now: h.Now, Logger: slog.Default(), IssuerURL: *issuerURL}
+	h.Sessions = &session.Manager{Storage: h.Storage, Config: sessionCfg, Now: h.Now, Logger: slog.Default(), IssuerURL: oauth2.IssuerURL{URL: *issuerURL}}
 	return &sessionTestServer{Handler: h}
 }
 
@@ -2151,5 +2151,5 @@ func TestRememberMeDefault(t *testing.T) {
 // resetSessions rebuilds the Handler's session manager with the given config and
 // issuer, for tests that exercise Manager behavior under a different config.
 func resetSessions(s *sessionTestServer, cfg *session.Config, issuer url.URL) {
-	s.Sessions = &session.Manager{Storage: s.Storage, Config: cfg, Now: s.Now, Logger: slog.Default(), IssuerURL: issuer}
+	s.Sessions = &session.Manager{Storage: s.Storage, Config: cfg, Now: s.Now, Logger: slog.Default(), IssuerURL: oauth2.IssuerURL{URL: issuer}}
 }
diff --git a/server/device/device_test.go b/server/device/device_test.go
--- a/server/device/device_test.go
+++ b/server/device/device_test.go
@@ -5,12 +5,14 @@ import (
 	"testing"
 
 	"github.com/stretchr/testify/require"
+
+	"github.com/dexidp/dex/server/oauth2"
 )
 
 func TestGetDeviceVerificationURI(t *testing.T) {
 	u, err := url.Parse("https://dex.example.com/non-root-path")
 	require.NoError(t, err)
 
-	h := &Handler{IssuerURL: *u}
+	h := &Handler{IssuerURL: oauth2.IssuerURL{URL: *u}}
 	require.Equal(t, "/non-root-path/device/auth/verify_code", h.getDeviceVerificationURI())
 }
diff --git a/server/mfa/handler_test.go b/server/mfa/handler_test.go
--- a/server/mfa/handler_test.go
+++ b/server/mfa/handler_test.go
@@ -16,6 +16,7 @@ import (
 	"github.com/dexidp/dex/connector/mock"
 	"github.com/dexidp/dex/server/connectors"
 	"github.com/dexidp/dex/server/internal"
+	"github.com/dexidp/dex/server/oauth2"
 	"github.com/dexidp/dex/server/templates"
 	"github.com/dexidp/dex/storage"
 	"github.com/dexidp/dex/storage/memory"
@@ -67,7 +68,7 @@ func newTestHandler(t *testing.T, providers map[string]Provider, defaultChain []
 		Storage:         store,
 		Templates:       tmpls,
 		Logger:          logger,
-		IssuerURL:       *issuerURL,
+		IssuerURL:       oauth2.IssuerURL{URL: *issuerURL},
 		MFAProviders:    providers,
 		DefaultMFAChain: defaultChain,
 		Now:             time.Now,
diff --git a/server/server_api_cache_test.go b/server/server_api_cache_test.go
--- a/server/server_api_cache_test.go
+++ b/server/server_api_cache_test.go
@@ -23,9 +23,11 @@ func TestConnectorCacheInvalidation(t *testing.T) {
 		storage: s,
 		logger:  logger,
 	}
-	serv.connectors = connectors.NewCache(s, serv.resolveConnector)
+	serv.connectors = connectors.NewCache(s, connectors.Resolver(s, logger, ConnectorsConfig))
 
-	apiServer := apiserver.NewAPI(s, logger, "test", serv.connectors, serv.ConstructDiscovery)
+	// This test exercises connector-cache invalidation, not discovery, so no
+	// discovery handler is wired (GetDiscovery guards against nil).
+	apiServer := apiserver.NewAPI(s, logger, "test", serv.connectors, nil)
 	ctx := context.Background()
 
 	connID := "mock-conn"
diff --git a/server/server_authorize_test.go b/server/server_authorize_test.go
--- a/server/server_authorize_test.go
+++ b/server/server_authorize_test.go
@@ -364,7 +364,7 @@ func TestBackLinkIncludesPromptSelectAccount(t *testing.T) {
 		Config:          []byte(`{"username": "foo", "password": "bar"}`),
 	}
 	require.NoError(t, s.storage.CreateConnector(ctx, pwConn))
-	_, err := s.OpenConnector(pwConn)
+	_, err := s.connectors.Open(pwConn)
 	require.NoError(t, err)
 
 	client := storage.Client{
diff --git a/server/server_grant_password_test.go b/server/server_grant_password_test.go
--- a/server/server_grant_password_test.go
+++ b/server/server_grant_password_test.go
@@ -14,6 +14,7 @@ import (
 	"github.com/stretchr/testify/require"
 	"golang.org/x/crypto/bcrypt"
 
+	"github.com/dexidp/dex/server/connectors"
 	"github.com/dexidp/dex/storage"
 )
 
@@ -117,12 +118,12 @@ func TestHandlePassword_LocalPasswordDBClaims(t *testing.T) {
 	// Enable local connector.
 	localConn := storage.Connector{
 		ID:              "local",
-		Type:            LocalConnector,
+		Type:            connectors.LocalConnector,
 		Name:            "Email",
 		ResourceVersion: "1",
 	}
 	require.NoError(t, s.storage.CreateConnector(ctx, localConn))
-	_, err := s.OpenConnector(localConn)
+	_, err := s.connectors.Open(localConn)
 	require.NoError(t, err)
 
 	// Create a user in the password DB with groups and preferred_username.
diff --git a/server/server_introspection_test.go b/server/server_introspection_test.go
--- a/server/server_introspection_test.go
+++ b/server/server_introspection_test.go
@@ -194,7 +194,7 @@ func TestHandleIntrospect(t *testing.T) {
 		{
 			testName:           "Access Token: active",
 			token:              activeAccessToken,
-			response:           toJSON(getIntrospectionValue(s.issuerURL, t0, expiry, "access_token")),
+			response:           toJSON(getIntrospectionValue(s.issuerURL.URL, t0, expiry, "access_token")),
 			responseStatusCode: 200,
 		},
 		{
@@ -207,7 +207,7 @@ func TestHandleIntrospect(t *testing.T) {
 		{
 			testName:           "Refresh Token: active",
 			token:              activeRefreshToken,
-			response:           toJSON(getIntrospectionValue(s.issuerURL, t0, t0.Add(s.refreshTokenPolicy.AbsoluteLifetime()), "refresh_token")),
+			response:           toJSON(getIntrospectionValue(s.issuerURL.URL, t0, t0.Add(refreshTokenPolicy.AbsoluteLifetime()), "refresh_token")),
 			responseStatusCode: 200,
 		},
 		{
diff --git a/server/server_login_test.go b/server/server_login_test.go
--- a/server/server_login_test.go
+++ b/server/server_login_test.go
@@ -98,7 +98,7 @@ func TestFinalizeLoginCreatesUserIdentity(t *testing.T) {
 		Config:          []byte(`{"username": "foo", "password": "password"}`),
 	}
 	require.NoError(t, s.storage.CreateConnector(ctx, sc))
-	_, err := s.OpenConnector(sc)
+	_, err := s.connectors.Open(sc)
 	require.NoError(t, err)
 
 	authReq := storage.AuthRequest{
@@ -148,7 +148,7 @@ func TestFinalizeLoginUpdatesUserIdentity(t *testing.T) {
 		Config:          []byte(`{"username": "foo", "password": "password"}`),
 	}
 	require.NoError(t, s.storage.CreateConnector(ctx, sc))
-	_, err := s.OpenConnector(sc)
+	_, err := s.connectors.Open(sc)
 	require.NoError(t, err)
 
 	// Pre-create UserIdentity with old data
@@ -211,7 +211,7 @@ func TestFinalizeLoginSkipsUserIdentityWhenDisabled(t *testing.T) {
 		Config:          []byte(`{"username": "foo", "password": "password"}`),
 	}
 	require.NoError(t, s.storage.CreateConnector(ctx, sc))
-	_, err := s.OpenConnector(sc)
+	_, err := s.connectors.Open(sc)
 	require.NoError(t, err)
 
 	authReq := storage.AuthRequest{
@@ -354,7 +354,7 @@ func TestHandlePasswordLoginWithSkipApproval(t *testing.T) {
 			if err := s.storage.CreateConnector(ctx, sc); err != nil {
 				t.Fatalf("create connector: %v", err)
 			}
-			if _, err := s.OpenConnector(sc); err != nil {
+			if _, err := s.connectors.Open(sc); err != nil {
 				t.Fatalf("open connector: %v", err)
 			}
 			if err := s.storage.CreateAuthRequest(ctx, tc.authReq); err != nil {
@@ -541,7 +541,7 @@ func TestHandlePasswordLogin_SPNEGOShortCircuit(t *testing.T) {
 		Config:          []byte("{\"username\": \"foo\", \"password\": \"password\"}"),
 	}
 	require.NoError(t, s.storage.CreateConnector(ctx, sc))
-	_, err := s.OpenConnector(sc)
+	_, err := s.connectors.Open(sc)
 	require.NoError(t, err)
 
 	// Prepare auth request
@@ -611,7 +611,7 @@ func TestHandlePasswordLogin_SPNEGOError(t *testing.T) {
 		Config:          []byte("{\"username\": \"foo\", \"password\": \"password\"}"),
 	}
 	require.NoError(t, s.storage.CreateConnector(ctx, sc))
-	_, err := s.OpenConnector(sc)
+	_, err := s.connectors.Open(sc)
 	require.NoError(t, err)
 
 	// Prepare auth request
diff --git a/server/server_oauth2_test.go b/server/server_oauth2_test.go
--- a/server/server_oauth2_test.go
+++ b/server/server_oauth2_test.go
@@ -180,19 +180,11 @@ func TestNewIDTokenUsesStoredAlgorithmUntilNextRotation(t *testing.T) {
 	issuerURL, err := url.Parse("https://issuer.example.com")
 	require.NoError(t, err)
 
-	s := &Server{
-		signer:           sig,
-		issuerURL:        *issuerURL,
-		logger:           logger,
-		now:              func() time.Time { return now },
-		idTokensValidFor: time.Hour,
-	}
-
-	s.issuer = tokens.NewIssuer(store, s.signer, s.issuerURL, s.idTokensValidFor, s.now, s.logger)
+	issuer := tokens.NewIssuer(store, sig, *issuerURL, time.Hour, func() time.Time { return now }, logger)
 
 	accessToken := "test-access-token"
 	code := "test-auth-code"
-	idToken, _, err := s.issuer.SignIDToken(ctx, tokens.Authorization{
+	idToken, _, err := issuer.SignIDToken(ctx, tokens.Authorization{
 		Client:      storage.Client{ID: "test-client"},
 		Claims:      storage.Claims{UserID: "1", Username: "jane"},
 		Scopes:      []string{"openid"},
@@ -267,15 +259,7 @@ func TestNewIDTokenContainsJTI(t *testing.T) {
 	issuerURL, err := url.Parse("https://issuer.example.com")
 	require.NoError(t, err)
 
-	s := &Server{
-		signer:           sig,
-		issuerURL:        *issuerURL,
-		logger:           logger,
-		now:              func() time.Time { return now },
-		idTokensValidFor: time.Hour,
-	}
-
-	s.issuer = tokens.NewIssuer(store, s.signer, s.issuerURL, s.idTokensValidFor, s.now, s.logger)
+	issuer := tokens.NewIssuer(store, sig, *issuerURL, time.Hour, func() time.Time { return now }, logger)
 
 	keys, err := sig.ValidationKeys(ctx)
 	require.NoError(t, err)
@@ -297,7 +281,7 @@ func TestNewIDTokenContainsJTI(t *testing.T) {
 
 	mint := func(nonce string) string {
 		t.Helper()
-		token, _, err := s.issuer.SignIDToken(ctx, tokens.Authorization{
+		token, _, err := issuer.SignIDToken(ctx, tokens.Authorization{
 			Client:      storage.Client{ID: "client"},
 			Claims:      storage.Claims{UserID: "1", Username: "alice"},
 			Scopes:      []string{"openid"},
diff --git a/server/server_test.go b/server/server_test.go
--- a/server/server_test.go
+++ b/server/server_test.go
@@ -33,6 +33,7 @@ import (
 	"github.com/dexidp/dex/connector"
 	"github.com/dexidp/dex/connector/mock"
 	"github.com/dexidp/dex/pkg/featureflags"
+	"github.com/dexidp/dex/server/connectors"
 	"github.com/dexidp/dex/server/device"
 	"github.com/dexidp/dex/server/oauth2"
 	"github.com/dexidp/dex/server/session"
@@ -173,6 +174,7 @@ func newTestServerMultipleConnectors(t *testing.T, updateConfig func(c *Config))
 		Logger:             logger,
 		PrometheusRegistry: prometheus.NewRegistry(),
 		Signer:             sig,
+		SkipApprovalScreen: true, // Don't prompt for approval, just immediately redirect with code.
 	}
 	if updateConfig != nil {
 		updateConfig(&config)
@@ -210,7 +212,6 @@ func newTestServerMultipleConnectors(t *testing.T, updateConfig func(c *Config))
 	if server, err = newServer(ctx, config); err != nil {
 		t.Fatal(err)
 	}
-	server.skipApproval = true // Don't prompt for approval, just immediately redirect with code.
 	return s, server
 }
 
@@ -1298,7 +1299,7 @@ func TestPasswordDB(t *testing.T) {
 
 	logger := newLogger(t)
 	s := memory.New(logger)
-	conn := newPasswordDB(s)
+	conn := connectors.NewPasswordDB(s)
 
 	pw := "hi"
 
@@ -1388,7 +1389,7 @@ func TestPasswordDB(t *testing.T) {
 func TestPasswordDBUsernamePrompt(t *testing.T) {
 	logger := newLogger(t)
 	s := memory.New(logger)
-	conn := newPasswordDB(s)
+	conn := connectors.NewPasswordDB(s)
 
 	expected := "Email Address"
 	if actual := conn.Prompt(); actual != expected {
@@ -1652,7 +1653,7 @@ func TestOAuth2DeviceFlow(t *testing.T) {
 				// Add the Clients to the test server
 				client := storage.Client{
 					ID:           clientID,
-					RedirectURIs: []string{s.absPath(oauth2.DeviceCallbackURI)},
+					RedirectURIs: []string{s.issuerURL.AbsPath(oauth2.DeviceCallbackURI)},
 					Public:       true,
 				}
 				if err := s.storage.CreateClient(ctx, client); err != nil {
@@ -1763,7 +1764,7 @@ func TestOAuth2DeviceFlow(t *testing.T) {
 					ClientSecret: client.Secret,
 					Endpoint:     p.Endpoint(),
 					Scopes:       requestedScopes,
-					RedirectURL:  s.absURL(oauth2.DeviceCallbackURI),
+					RedirectURL:  s.issuerURL.AbsURL(oauth2.DeviceCallbackURI),
 				}
 				if len(tc.scopes) != 0 {
 					oauth2Config.Scopes = tc.scopes
@@ -1832,7 +1833,7 @@ func TestServerSupportedGrants(t *testing.T) {
 	for _, tc := range tests {
 		t.Run(tc.name, func(t *testing.T) {
 			_, srv := newTestServer(t, tc.config)
-			require.Equal(t, tc.resGrants, srv.supportedGrantTypes)
+			require.Equal(t, tc.resGrants, srv.discovery.GrantTypes)
 		})
 	}
 }
EOF_114329324912
if [ -s "$TEST_PATCH_FILE" ]; then
  git apply -v "$TEST_PATCH_FILE"
fi
rm -f "$TEST_PATCH_FILE"

# --- Remove any files explicitly deleted by the test patch, and verify absent.
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  rm -f -- "$f"
done
for f in "${DELETED_TEST_PATCH_FILES[@]}"; do
  if [ -e "$f" ]; then
    echo "ERROR: deleted test patch file still exists after applying test patch: $f" >&2
    rc=2
    echo "OMNIGRIL_EXIT_CODE=$rc"
    exit "$rc"
  fi
done

# --- Determine target packages from runnable test files (dedupe).
TARGET_PKGS=()
declare -A seen_pkg=()
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  pkg="./$(dirname "$f")"
  if [[ -z "${seen_pkg[$pkg]+x}" ]]; then
    TARGET_PKGS+=("$pkg")
    seen_pkg["$pkg"]=1
  fi
done

# --- If no runnable targets, run a regression suite instead.
if [ "${#RUNNABLE_TEST_FILES[@]}" -eq 0 ]; then
  set +e
  go test -p 1 ./...
  rc=$?
  set -e
  echo "OMNIGRIL_EXIT_CODE=$rc"
  exit "$rc"
fi

# --- Run tests for target packages sequentially to avoid cross-package resource conflicts.
RESULTS_DIR="$(mktemp -d)"
PKG_STATUS_FILE="$RESULTS_DIR/pkg_status.tsv"
: > "$PKG_STATUS_FILE"

set +e
for pkg in "${TARGET_PKGS[@]}"; do
  out="$RESULTS_DIR/$(echo "$pkg" | sed 's#^./##; s#/#_#g').out"
  go test -p 1 -json "$pkg" >"$out" 2>&1
  pkg_rc=$?
  if [ $pkg_rc -eq 0 ]; then
    printf "%s\tPASS\n" "$pkg" >> "$PKG_STATUS_FILE"
  else
    printf "%s\tFAIL\n" "$pkg" >> "$PKG_STATUS_FILE"
  fi
done

rc=0
if grep -q $'\tFAIL' "$PKG_STATUS_FILE"; then
  rc=1
fi
set -e

# --- Emit concise, structured per-file status (file PASS/FAIL mirrors its package status).
echo "BEGIN_FILE_RESULTS"
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  pkg="./$(dirname "$f")"
  status="$(awk -F'\t' -v p="$pkg" '$1==p{print $2}' "$PKG_STATUS_FILE" | tail -n1)"
  if [ -z "$status" ]; then
    status="UNKNOWN"
  fi
  echo "${f} ${status}"
done
echo "END_FILE_RESULTS"

echo "OMNIGRIL_EXIT_CODE=$rc"

# --- Cleanup: reset runnable files back to base commit state (or remove if not present in base).
for f in "${RUNNABLE_TEST_FILES[@]}"; do
  if git cat-file -e "${COMMIT_SHA}:$f" 2>/dev/null; then
    git checkout "${COMMIT_SHA}" -- "$f"
  else
    rm -f -- "$f"
  fi
done

exit "$rc"
