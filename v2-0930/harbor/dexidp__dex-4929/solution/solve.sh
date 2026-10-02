#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/cmd/dex/config.go b/cmd/dex/config.go
--- a/cmd/dex/config.go
+++ b/cmd/dex/config.go
@@ -16,6 +16,7 @@ import (
 
 	"github.com/dexidp/dex/pkg/featureflags"
 	"github.com/dexidp/dex/server"
+	"github.com/dexidp/dex/server/connectors"
 	"github.com/dexidp/dex/server/signer"
 	"github.com/dexidp/dex/storage"
 	"github.com/dexidp/dex/storage/ent"
@@ -557,8 +558,8 @@ type Connector struct {
 	Name string `json:"name"`
 	ID   string `json:"id"`
 
-	Config     server.ConnectorConfig `json:"config"`
-	GrantTypes []string               `json:"grantTypes"`
+	Config     connectors.ConnectorConfig `json:"config"`
+	GrantTypes []string                   `json:"grantTypes"`
 }
 
 // UnmarshalJSON allows Connector to implement the unmarshaler interface to
diff --git a/cmd/dex/serve.go b/cmd/dex/serve.go
--- a/cmd/dex/serve.go
+++ b/cmd/dex/serve.go
@@ -279,9 +279,9 @@ func runServe(options serveOptions) error {
 
 	if c.EnablePasswordDB {
 		storageConnectors = append(storageConnectors, storage.Connector{
-			ID:   server.LocalConnector,
+			ID:   connectors.LocalConnector,
 			Name: "Email",
-			Type: server.LocalConnector,
+			Type: connectors.LocalConnector,
 		})
 		logger.Info("config connector: local passwords enabled")
 	}
@@ -609,7 +609,7 @@ func runServe(options serveOptions) error {
 		}
 
 		grpcSrv := grpc.NewServer(grpcOptions...)
-		api.RegisterDexServer(grpcSrv, apiserver.NewAPI(serverConfig.Storage, logger, version, serv.Connectors(), serv.ConstructDiscovery))
+		api.RegisterDexServer(grpcSrv, apiserver.NewAPI(serverConfig.Storage, logger, version, serv.Connectors(), serv.Discovery()))
 
 		grpcMetrics.InitializeMetrics(grpcSrv)
 		if c.GRPC.Reflection {
diff --git a/server/apiserver/api.go b/server/apiserver/api.go
--- a/server/apiserver/api.go
+++ b/server/apiserver/api.go
@@ -20,15 +20,16 @@ const apiVersion = 4
 
 // NewAPI returns a server which implements the gRPC API interface. It takes only
 // the narrow dependencies it needs — the connector cache to invalidate on
-// connector CRUD, and a discovery-document builder — rather than the whole Server.
-func NewAPI(s storage.Storage, logger *slog.Logger, version string, conns *connectors.Cache, discovery func(context.Context) discovery.Document) api.DexServer {
+// connector CRUD, and the discovery handler to serve the same document as HTTP —
+// rather than the whole Server.
+func NewAPI(s storage.Storage, logger *slog.Logger, version string, conns *connectors.Cache, disc *discovery.Handler) api.DexServer {
 	apiLogger := logger.With("component", "api")
 	return dexAPI{
 		s:          s,
 		logger:     apiLogger,
 		version:    version,
 		connectors: conns,
-		discovery:  discovery,
+		discovery:  disc,
 		refresh:    tokens.NewRefreshStore(s, time.Now, apiLogger),
 	}
 }
@@ -40,7 +41,7 @@ type dexAPI struct {
 	logger     *slog.Logger
 	version    string
 	connectors *connectors.Cache
-	discovery  func(context.Context) discovery.Document
+	discovery  *discovery.Handler
 	refresh    *tokens.RefreshStore
 }
 
@@ -52,7 +53,10 @@ func (d dexAPI) GetVersion(ctx context.Context, req *api.VersionReq) (*api.Versi
 }
 
 func (d dexAPI) GetDiscovery(ctx context.Context, req *api.DiscoveryReq) (*api.DiscoveryResp, error) {
-	discoveryDoc := d.discovery(ctx)
+	if d.discovery == nil {
+		return nil, fmt.Errorf("discovery is not configured")
+	}
+	discoveryDoc := d.discovery.Construct(ctx)
 	data, err := json.Marshal(discoveryDoc)
 	if err != nil {
 		return nil, fmt.Errorf("failed to marshal discovery data: %v", err)
diff --git a/server/authflow/authorize.go b/server/authflow/authorize.go
--- a/server/authflow/authorize.go
+++ b/server/authflow/authorize.go
@@ -94,7 +94,7 @@ func (h *Handler) handleAuthorization(w http.ResponseWriter, r *http.Request) {
 	if connectorID != "" {
 		for _, c := range connectors {
 			if c.ID == connectorID {
-				connURL.Path = h.absPath("/auth", url.PathEscape(c.ID))
+				connURL.Path = h.IssuerURL.AbsPath("/auth", url.PathEscape(c.ID))
 				http.Redirect(w, r, connURL.String(), http.StatusFound)
 				return
 			}
@@ -104,7 +104,7 @@ func (h *Handler) handleAuthorization(w http.ResponseWriter, r *http.Request) {
 	}
 
 	if len(connectors) == 1 && !h.AlwaysShowLogin {
-		connURL.Path = h.absPath("/auth", url.PathEscape(connectors[0].ID))
+		connURL.Path = h.IssuerURL.AbsPath("/auth", url.PathEscape(connectors[0].ID))
 		http.Redirect(w, r, connURL.String(), http.StatusFound)
 		return
 	}
@@ -140,7 +140,7 @@ func (h *Handler) handleAuthorization(w http.ResponseWriter, r *http.Request) {
 					if c.ID != session.ConnectorID {
 						continue
 					}
-					connURL.Path = h.absPath("/auth", url.PathEscape(session.ConnectorID))
+					connURL.Path = h.IssuerURL.AbsPath("/auth", url.PathEscape(session.ConnectorID))
 					http.Redirect(w, r, connURL.String(), http.StatusFound)
 					return
 				}
@@ -155,7 +155,7 @@ func (h *Handler) handleAuthorization(w http.ResponseWriter, r *http.Request) {
 
 	connectorInfos := make([]templates.ConnectorInfo, 0, len(connectors))
 	for _, conn := range connectors {
-		connURL.Path = h.absPath("/auth", url.PathEscape(conn.ID))
+		connURL.Path = h.IssuerURL.AbsPath("/auth", url.PathEscape(conn.ID))
 		connectorInfos = append(connectorInfos, templates.ConnectorInfo{
 			ID:   conn.ID,
 			Name: conn.Name,
diff --git a/server/authflow/handler.go b/server/authflow/handler.go
--- a/server/authflow/handler.go
+++ b/server/authflow/handler.go
@@ -3,11 +3,11 @@ package authflow
 import (
 	"log/slog"
 	"net/http"
-	"net/url"
 	"strings"
 	"time"
 
 	"github.com/dexidp/dex/server/connectors"
+	"github.com/dexidp/dex/server/oauth2"
 	"github.com/dexidp/dex/server/router"
 	"github.com/dexidp/dex/server/session"
 	"github.com/dexidp/dex/server/signer"
@@ -24,7 +24,7 @@ import (
 // reference to the MFA or consent handlers; each step only redirects back to
 // /auth, never to another step.
 type Handler struct {
-	IssuerURL              url.URL
+	IssuerURL              oauth2.IssuerURL
 	Connectors             *connectors.Cache
 	Storage                storage.Storage
 	Templates              *templates.Templates
diff --git a/server/authflow/login.go b/server/authflow/login.go
--- a/server/authflow/login.go
+++ b/server/authflow/login.go
@@ -149,7 +149,7 @@ func (h *Handler) handleConnectorLogin(w http.ResponseWriter, r *http.Request) {
 			backLinkParams.Set("prompt", "select_account")
 		}
 		backLinkURL := url.URL{
-			Path:     h.absPath("/auth"),
+			Path:     h.IssuerURL.AbsPath("/auth"),
 			RawQuery: backLinkParams.Encode(),
 		}
 		backLink = backLinkURL.String()
@@ -162,7 +162,7 @@ func (h *Handler) handleConnectorLogin(w http.ResponseWriter, r *http.Request) {
 			// Use the auth request ID as the "state" token.
 			//
 			// TODO(ericchiang): Is this appropriate or should we also be using a nonce?
-			callbackURL, connData, err := conn.LoginURL(scopes, h.absURL("/callback"), authReq.ID)
+			callbackURL, connData, err := conn.LoginURL(scopes, h.IssuerURL.AbsURL("/callback"), authReq.ID)
 			if err != nil {
 				h.Logger.ErrorContext(r.Context(), "connector returned error when creating callback", "connector_id", connID, "err", err)
 				h.renderError(r, w, http.StatusInternalServerError, "Login error.")
@@ -183,7 +183,7 @@ func (h *Handler) handleConnectorLogin(w http.ResponseWriter, r *http.Request) {
 			http.Redirect(w, r, callbackURL, http.StatusFound)
 		case connector.PasswordConnector:
 			loginURL := url.URL{
-				Path: h.absPath("/auth", connID, "login"),
+				Path: h.IssuerURL.AbsPath("/auth", connID, "login"),
 			}
 			q := loginURL.Query()
 			q.Set("state", authReq.ID)
diff --git a/server/authflow/render.go b/server/authflow/render.go
--- a/server/authflow/render.go
+++ b/server/authflow/render.go
@@ -2,7 +2,6 @@ package authflow
 
 import (
 	"net/http"
-	"path"
 )
 
 // renderError renders a user-facing HTML error page.
@@ -11,15 +10,3 @@ func (h *Handler) renderError(r *http.Request, w http.ResponseWriter, status int
 		h.Logger.ErrorContext(r.Context(), "server template error", "err", err)
 	}
 }
-
-// absPath returns the issuer path joined with the given path items.
-func (h *Handler) absPath(pathItems ...string) string {
-	return path.Join(append([]string{h.IssuerURL.Path}, pathItems...)...)
-}
-
-// absURL returns the absolute issuer URL for the given path items.
-func (h *Handler) absURL(pathItems ...string) string {
-	u := h.IssuerURL
-	u.Path = h.absPath(pathItems...)
-	return u.String()
-}
diff --git a/server/authflow/request.go b/server/authflow/request.go
--- a/server/authflow/request.go
+++ b/server/authflow/request.go
@@ -215,7 +215,7 @@ func (h *Handler) parseAuthorizationRequest(r *http.Request) (*storage.AuthReque
 		return nil, "", newDisplayedErr(http.StatusBadRequest, "Unregistered redirect_uri.")
 	}
 	if redirectURI == oauth2.DeviceCallbackURI && client.Public {
-		redirectURI = h.absPath(oauth2.DeviceCallbackURI)
+		redirectURI = h.IssuerURL.AbsPath(oauth2.DeviceCallbackURI)
 	}
 
 	// From here on out, we want to redirect back to the client with an error.
diff --git a/server/authflow/urls.go b/server/authflow/urls.go
--- a/server/authflow/urls.go
+++ b/server/authflow/urls.go
@@ -13,7 +13,7 @@ func (h *Handler) buildContinueURL(authReq storage.AuthRequest) string {
 	v := url.Values{}
 	v.Set("req", authReq.ID)
 	v.Set("hmac", internal.ComputeHMAC(authReq.HMACKey, authReq.ID, "continue"))
-	return h.absPath("/auth") + "?" + v.Encode()
+	return h.IssuerURL.AbsPath("/auth") + "?" + v.Encode()
 }
 
 // buildMFAURL builds the HMAC-protected URL of the MFA entry, where the
@@ -24,7 +24,7 @@ func (h *Handler) buildMFAURL(authReq storage.AuthRequest) string {
 	v := url.Values{}
 	v.Set("req", authReq.ID)
 	v.Set("hmac", internal.ComputeHMAC(authReq.HMACKey, authReq.ID, "mfa"))
-	return h.absPath("/mfa") + "?" + v.Encode()
+	return h.IssuerURL.AbsPath("/mfa") + "?" + v.Encode()
 }
 
 // buildApprovalURL builds the HMAC-protected URL of the consent screen, where the
@@ -33,5 +33,5 @@ func (h *Handler) buildApprovalURL(authReq storage.AuthRequest) string {
 	v := url.Values{}
 	v.Set("req", authReq.ID)
 	v.Set("hmac", internal.ComputeHMAC(authReq.HMACKey, authReq.ID, "approval"))
-	return h.absPath("/approval") + "?" + v.Encode()
+	return h.IssuerURL.AbsPath("/approval") + "?" + v.Encode()
 }
diff --git a/server/connector.go b/server/connector.go
new file mode 100644
--- /dev/null
+++ b/server/connector.go
@@ -0,0 +1,46 @@
+package server
+
+import (
+	"github.com/dexidp/dex/connector/atlassiancrowd"
+	"github.com/dexidp/dex/connector/authproxy"
+	"github.com/dexidp/dex/connector/bitbucketcloud"
+	"github.com/dexidp/dex/connector/gitea"
+	"github.com/dexidp/dex/connector/github"
+	"github.com/dexidp/dex/connector/gitlab"
+	"github.com/dexidp/dex/connector/google"
+	"github.com/dexidp/dex/connector/keystone"
+	"github.com/dexidp/dex/connector/ldap"
+	"github.com/dexidp/dex/connector/linkedin"
+	"github.com/dexidp/dex/connector/microsoft"
+	"github.com/dexidp/dex/connector/mock"
+	"github.com/dexidp/dex/connector/oauth"
+	"github.com/dexidp/dex/connector/oidc"
+	"github.com/dexidp/dex/connector/openshift"
+	"github.com/dexidp/dex/connector/saml"
+	"github.com/dexidp/dex/server/connectors"
+)
+
+// ConnectorsConfig maps each built-in connector type to its config factory. It
+// is handed to connectors.Resolver so the connectors package itself imports no
+// connector implementation; a library consumer can pass a different map.
+var ConnectorsConfig = map[string]func() connectors.ConnectorConfig{
+	"keystone":        func() connectors.ConnectorConfig { return new(keystone.Config) },
+	"mockCallback":    func() connectors.ConnectorConfig { return new(mock.CallbackConfig) },
+	"mockPassword":    func() connectors.ConnectorConfig { return new(mock.PasswordConfig) },
+	"ldap":            func() connectors.ConnectorConfig { return new(ldap.Config) },
+	"gitea":           func() connectors.ConnectorConfig { return new(gitea.Config) },
+	"github":          func() connectors.ConnectorConfig { return new(github.Config) },
+	"gitlab":          func() connectors.ConnectorConfig { return new(gitlab.Config) },
+	"google":          func() connectors.ConnectorConfig { return new(google.Config) },
+	"oidc":            func() connectors.ConnectorConfig { return new(oidc.Config) },
+	"oauth":           func() connectors.ConnectorConfig { return new(oauth.Config) },
+	"saml":            func() connectors.ConnectorConfig { return new(saml.Config) },
+	"authproxy":       func() connectors.ConnectorConfig { return new(authproxy.Config) },
+	"linkedin":        func() connectors.ConnectorConfig { return new(linkedin.Config) },
+	"microsoft":       func() connectors.ConnectorConfig { return new(microsoft.Config) },
+	"bitbucket-cloud": func() connectors.ConnectorConfig { return new(bitbucketcloud.Config) },
+	"openshift":       func() connectors.ConnectorConfig { return new(openshift.Config) },
+	"atlassian-crowd": func() connectors.ConnectorConfig { return new(atlassiancrowd.Config) },
+	// Keep around for backwards compatibility.
+	"samlExperimental": func() connectors.ConnectorConfig { return new(saml.Config) },
+}
diff --git a/server/connectors/password.go b/server/connectors/password.go
new file mode 100644
--- /dev/null
+++ b/server/connectors/password.go
@@ -0,0 +1,99 @@
+package connectors
+
+import (
+	"context"
+	"errors"
+	"fmt"
+
+	"golang.org/x/crypto/bcrypt"
+
+	"github.com/dexidp/dex/connector"
+	"github.com/dexidp/dex/server/passwords"
+	"github.com/dexidp/dex/storage"
+)
+
+// NewPasswordDB returns the built-in local password connector backed by the
+// password store. Resolver uses it for LocalConnector; it is exported so a
+// custom ResolveFunc can reuse it.
+func NewPasswordDB(s storage.Storage) interface {
+	connector.Connector
+	connector.PasswordConnector
+} {
+	return passwordDB{s}
+}
+
+type passwordDB struct {
+	s storage.Storage
+}
+
+func resolvePasswordName(p storage.Password) string {
+	if p.Name != "" {
+		return p.Name
+	}
+	return p.Username
+}
+
+func resolvePasswordEmailVerified(p storage.Password) bool {
+	if p.EmailVerified != nil {
+		return *p.EmailVerified
+	}
+	return true
+}
+
+func (db passwordDB) Login(ctx context.Context, s connector.Scopes, email, password string) (connector.Identity, bool, error) {
+	p, err := db.s.GetPassword(ctx, email)
+	if err != nil {
+		if err != storage.ErrNotFound {
+			return connector.Identity{}, false, fmt.Errorf("get password: %v", err)
+		}
+		return connector.Identity{}, false, nil
+	}
+	// This check prevents dex users from logging in using static passwords
+	// configured with hash costs that are too high or low.
+	if err := passwords.CheckCost(p.Hash); err != nil {
+		return connector.Identity{}, false, err
+	}
+	if err := bcrypt.CompareHashAndPassword(p.Hash, []byte(password)); err != nil {
+		return connector.Identity{}, false, nil
+	}
+	return connector.Identity{
+		UserID:            p.UserID,
+		Username:          resolvePasswordName(p),
+		PreferredUsername: p.PreferredUsername,
+		Email:             p.Email,
+		EmailVerified:     resolvePasswordEmailVerified(p),
+		Groups:            p.Groups,
+	}, true, nil
+}
+
+func (db passwordDB) Refresh(ctx context.Context, s connector.Scopes, identity connector.Identity) (connector.Identity, error) {
+	// If the user has been deleted, the refresh token will be rejected.
+	p, err := db.s.GetPassword(ctx, identity.Email)
+	if err != nil {
+		if err == storage.ErrNotFound {
+			return connector.Identity{}, errors.New("user not found")
+		}
+		return connector.Identity{}, fmt.Errorf("get password: %v", err)
+	}
+
+	// User removed but a new user with the same email exists.
+	if p.UserID != identity.UserID {
+		return connector.Identity{}, errors.New("user not found")
+	}
+
+	// If a user has updated their username, that will be reflected in the
+	// refreshed token.
+	//
+	// No other fields are expected to be refreshable as email is effectively used
+	// as an ID.
+	identity.Username = resolvePasswordName(p)
+	identity.PreferredUsername = p.PreferredUsername
+	identity.EmailVerified = resolvePasswordEmailVerified(p)
+	identity.Groups = p.Groups
+
+	return identity, nil
+}
+
+func (db passwordDB) Prompt() string {
+	return "Email Address"
+}
diff --git a/server/connectors/resolve.go b/server/connectors/resolve.go
new file mode 100644
--- /dev/null
+++ b/server/connectors/resolve.go
@@ -0,0 +1,57 @@
+package connectors
+
+import (
+	"encoding/json"
+	"fmt"
+	"log/slog"
+
+	"github.com/dexidp/dex/connector"
+	"github.com/dexidp/dex/storage"
+)
+
+// LocalConnector is the local passwordDB connector: an internal connector,
+// backed by the password store, that is not part of the injected config map.
+const LocalConnector = "local"
+
+// ConnectorConfig is a configuration that can open a connector.
+type ConnectorConfig interface {
+	Open(id string, logger *slog.Logger) (connector.Connector, error)
+}
+
+// Resolver returns a ResolveFunc that builds the underlying implementation for a
+// stored connector: the built-in local password DB (backed by storage), or a
+// connector from the given config map. The map is injected by the caller so this
+// package need not import any connector implementation — a library consumer can
+// pass its own set of connectors.
+func Resolver(store storage.Storage, logger *slog.Logger, configs map[string]func() ConnectorConfig) ResolveFunc {
+	return func(conn storage.Connector) (connector.Connector, error) {
+		if conn.Type == LocalConnector {
+			return NewPasswordDB(store), nil
+		}
+		return openConnector(logger, configs, conn)
+	}
+}
+
+// openConnector parses the stored config and opens the connector named by its type.
+func openConnector(logger *slog.Logger, configs map[string]func() ConnectorConfig, conn storage.Connector) (connector.Connector, error) {
+	var c connector.Connector
+
+	f, ok := configs[conn.Type]
+	if !ok {
+		return c, fmt.Errorf("unknown connector type %q", conn.Type)
+	}
+
+	connConfig := f()
+	if len(conn.Config) != 0 {
+		if err := json.Unmarshal(conn.Config, connConfig); err != nil {
+			return c, fmt.Errorf("parse connector config: %v", err)
+		}
+	}
+
+	c, err := connConfig.Open(conn.ID, logger)
+	if err != nil {
+		return c, fmt.Errorf("failed to create connector %s: %v", conn.ID, err)
+	}
+
+	return c, nil
+}
diff --git a/server/consent/consent.go b/server/consent/consent.go
--- a/server/consent/consent.go
+++ b/server/consent/consent.go
@@ -5,9 +5,9 @@ import (
 	"log/slog"
 	"net/http"
 	"net/url"
-	"path"
 
 	"github.com/dexidp/dex/server/internal"
+	"github.com/dexidp/dex/server/oauth2"
 	"github.com/dexidp/dex/server/router"
 	"github.com/dexidp/dex/server/session"
 	"github.com/dexidp/dex/server/templates"
@@ -23,7 +23,7 @@ type Handler struct {
 	Storage      storage.Storage
 	Templates    *templates.Templates
 	Logger       *slog.Logger
-	IssuerURL    url.URL
+	IssuerURL    oauth2.IssuerURL
 	Sessions     *session.Manager
 	SkipApproval bool
 }
@@ -35,11 +35,6 @@ func (h *Handler) renderError(r *http.Request, w http.ResponseWriter, status int
 	}
 }
 
-// absPath returns the issuer path joined with the given path items.
-func (h *Handler) absPath(pathItems ...string) string {
-	return path.Join(append([]string{h.IssuerURL.Path}, pathItems...)...)
-}
-
 // Mount registers the consent endpoint.
 func (h *Handler) Mount(mux router.Mux) {
 	mux.HandleFunc("/approval", h.handleApproval)
@@ -52,7 +47,7 @@ func (h *Handler) buildApprovedURL(authReq storage.AuthRequest) string {
 	v := url.Values{}
 	v.Set("req", authReq.ID)
 	v.Set("hmac", internal.ComputeHMAC(authReq.HMACKey, authReq.ID, "approved"))
-	return h.absPath("/auth") + "?" + v.Encode()
+	return h.IssuerURL.AbsPath("/auth") + "?" + v.Encode()
 }
 
 // Satisfied reports whether the approval screen can be skipped: the client did
diff --git a/server/device/device.go b/server/device/device.go
--- a/server/device/device.go
+++ b/server/device/device.go
@@ -41,7 +41,7 @@ type DeviceCodeResponse struct {
 
 // Handler serves the browser side of the device authorization grant.
 type Handler struct {
-	IssuerURL        url.URL
+	IssuerURL        oauth2.IssuerURL
 	Storage          storage.Storage
 	Templates        *templates.Templates
 	Now              func() time.Time
@@ -95,7 +95,7 @@ func (h *Handler) renderError(r *http.Request, w http.ResponseWriter, status int
 }
 
 func (h *Handler) getDeviceVerificationURI() string {
-	return path.Join(h.IssuerURL.Path, "/device/auth/verify_code")
+	return h.IssuerURL.AbsPath("/device/auth/verify_code")
 }
 
 // handleDeviceExchange serves the /device user-code entry page.
@@ -290,7 +290,7 @@ func (h *Handler) verifyUserCode(w http.ResponseWriter, r *http.Request) {
 	// stored device request.
 	q.Set("state", deviceRequest.UserCode)
 	q.Set("response_type", "code")
-	q.Set("redirect_uri", path.Join(h.IssuerURL.Path, oauth2.DeviceCallbackURI))
+	q.Set("redirect_uri", h.IssuerURL.AbsPath(oauth2.DeviceCallbackURI))
 	q.Set("scope", strings.Join(deviceRequest.Scopes, " "))
 	u.RawQuery = q.Encode()
 
diff --git a/server/home/home.go b/server/home/home.go
--- a/server/home/home.go
+++ b/server/home/home.go
@@ -6,9 +6,8 @@ import (
 	"fmt"
 	"log/slog"
 	"net/http"
-	"net/url"
-	"path"
 
+	"github.com/dexidp/dex/server/oauth2"
 	"github.com/dexidp/dex/server/router"
 	"github.com/dexidp/dex/server/session"
 	"github.com/dexidp/dex/server/templates"
@@ -19,7 +18,7 @@ import (
 // is available it renders the rich page (with logged-in details); otherwise it
 // falls back to a minimal inline page.
 type Handler struct {
-	IssuerURL url.URL
+	IssuerURL oauth2.IssuerURL
 	Storage   storage.Storage
 	Templates *templates.Templates
 	Logger    *slog.Logger
@@ -47,12 +46,9 @@ func (h *Handler) handle(w http.ResponseWriter, r *http.Request) {
 
 	ctx := r.Context()
 
-	logoutURL := h.IssuerURL
-	logoutURL.Path = path.Join(logoutURL.Path, "/logout")
-
 	data := templates.HomeData{
 		DiscoveryURL: h.IssuerURL.JoinPath(".well-known", "openid-configuration").String(),
-		LogoutURL:    logoutURL.String(),
+		LogoutURL:    h.IssuerURL.AbsURL("/logout"),
 	}
 
 	// ValidSession enforces the nonce AND absolute/idle expiry (clearing an
diff --git a/server/logout/logout.go b/server/logout/logout.go
--- a/server/logout/logout.go
+++ b/server/logout/logout.go
@@ -7,14 +7,14 @@ import (
 	"log/slog"
 	"net/http"
 	"net/url"
-	"path"
 	"slices"
 
 	"github.com/coreos/go-oidc/v3/oidc"
 
 	"github.com/dexidp/dex/connector"
 	"github.com/dexidp/dex/server/connectors"
 	"github.com/dexidp/dex/server/internal"
+	"github.com/dexidp/dex/server/oauth2"
 	"github.com/dexidp/dex/server/router"
 	"github.com/dexidp/dex/server/session"
 	"github.com/dexidp/dex/server/signer"
@@ -34,7 +34,7 @@ type Handler struct {
 	Connectors *connectors.Cache
 	Issuer     *tokens.Issuer
 	Signer     signer.Signer
-	IssuerURL  url.URL
+	IssuerURL  oauth2.IssuerURL
 }
 
 // renderError renders a user-facing HTML error page.
@@ -44,13 +44,6 @@ func (h *Handler) renderError(r *http.Request, w http.ResponseWriter, status int
 	}
 }
 
-// absURL returns the absolute issuer URL for the given path items.
-func (h *Handler) absURL(pathItems ...string) string {
-	u := h.IssuerURL
-	u.Path = path.Join(append([]string{h.IssuerURL.Path}, pathItems...)...)
-	return u.String()
-}
-
 // Mount registers the logout endpoints. Logout requires an active session, so it
 // mounts only when sessions are enabled.
 func (h *Handler) Mount(mux router.Mux) {
@@ -322,7 +315,7 @@ func (h *Handler) tryUpstreamLogout(ctx context.Context, userID, connectorID, po
 		return "", false
 	}
 
-	callbackURI := h.absURL("/logout/callback")
+	callbackURI := h.IssuerURL.AbsURL("/logout/callback")
 	upstreamURL, err := logoutConn.LogoutURL(ctx, callbackURI)
 	if err != nil {
 		h.Logger.ErrorContext(ctx, "logout: upstream connector error", "err", err)
diff --git a/server/mfa/handler.go b/server/mfa/handler.go
--- a/server/mfa/handler.go
+++ b/server/mfa/handler.go
@@ -6,11 +6,11 @@ import (
 	"log/slog"
 	"net/http"
 	"net/url"
-	"path"
 	"time"
 
 	"github.com/dexidp/dex/server/connectors"
 	"github.com/dexidp/dex/server/internal"
+	"github.com/dexidp/dex/server/oauth2"
 	"github.com/dexidp/dex/server/router"
 	"github.com/dexidp/dex/server/templates"
 	"github.com/dexidp/dex/storage"
@@ -39,7 +39,7 @@ type Handler struct {
 	Storage         storage.Storage
 	Templates       *templates.Templates
 	Logger          *slog.Logger
-	IssuerURL       url.URL
+	IssuerURL       oauth2.IssuerURL
 	MFAProviders    map[string]Provider
 	DefaultMFAChain []string
 	Now             func() time.Time
@@ -53,11 +53,6 @@ func (h *Handler) renderError(r *http.Request, w http.ResponseWriter, status int
 	}
 }
 
-// absPath returns the issuer path joined with the given path items.
-func (h *Handler) absPath(pathItems ...string) string {
-	return path.Join(append([]string{h.IssuerURL.Path}, pathItems...)...)
-}
-
 func (h *Handler) validateMFARequest(w http.ResponseWriter, r *http.Request) (*mfaRequestContext, bool) {
 	macEncoded := r.FormValue("hmac")
 	if macEncoded == "" {
@@ -251,7 +246,7 @@ func (h *Handler) buildRedirectURL(authReq storage.AuthRequest, authenticatorID
 	v.Set("req", authReq.ID)
 	v.Set("hmac", internal.ComputeHMAC(authReq.HMACKey, authReq.ID, authenticatorID))
 	v.Set("authenticator", authenticatorID)
-	return h.absPath(h.mfaPagePath(authenticatorID)) + "?" + v.Encode()
+	return h.IssuerURL.AbsPath(h.mfaPagePath(authenticatorID)) + "?" + v.Encode()
 }
 
 // buildContinueURL builds the HMAC-protected URL that returns to the authorize
@@ -260,7 +255,7 @@ func (h *Handler) buildContinueURL(authReq storage.AuthRequest) string {
 	v := url.Values{}
 	v.Set("req", authReq.ID)
 	v.Set("hmac", internal.ComputeHMAC(authReq.HMACKey, authReq.ID, "continue"))
-	return h.absPath("/auth") + "?" + v.Encode()
+	return h.IssuerURL.AbsPath("/auth") + "?" + v.Encode()
 }
 
 // Mount registers the MFA factor endpoints, only when at least one authenticator
diff --git a/server/oauth2/issuer.go b/server/oauth2/issuer.go
new file mode 100644
--- /dev/null
+++ b/server/oauth2/issuer.go
@@ -0,0 +1,29 @@
+package oauth2
+
+import (
+	"net/url"
+	"path"
+)
+
+// IssuerURL is the dex issuer URL together with the helpers for building paths
+// and absolute URLs under its path. Handlers hold this instead of a bare
+// url.URL so the "join onto the issuer path" logic lives in one place rather
+// than being reimplemented per handler. The embedded url.URL keeps String,
+// JoinPath, Query, and the fields available directly.
+type IssuerURL struct {
+	url.URL
+}
+
+// AbsPath joins the given items onto the issuer path, e.g. issuer path "/dex"
+// plus "auth" gives "/dex/auth".
+func (i IssuerURL) AbsPath(items ...string) string {
+	return path.Join(append([]string{i.Path}, items...)...)
+}
+
+// AbsURL returns the absolute issuer URL with the given items joined onto its
+// path.
+func (i IssuerURL) AbsURL(items ...string) string {
+	u := i.URL
+	u.Path = i.AbsPath(items...)
+	return u.String()
+}
diff --git a/server/router/router.go b/server/router/router.go
--- a/server/router/router.go
+++ b/server/router/router.go
@@ -1,9 +1,17 @@
 package router
 
-import "net/http"
+import (
+	"net/http"
+	"path"
 
-// Mux registers HTTP routes. The server provides the implementation (path
-// prefixing, per-route headers, CORS); handlers only name their routes.
+	"github.com/gorilla/handlers"
+	"github.com/gorilla/mux"
+
+	"github.com/dexidp/dex/server/reqctx"
+)
+
+// Mux registers HTTP routes. New returns the implementation used by the server
+// (path prefixing, per-route headers, CORS); handlers only name their routes.
 type Mux interface {
 	// Handle mounts h at pattern.
 	Handle(pattern string, h http.Handler)
@@ -21,3 +29,72 @@ type Mux interface {
 type Handler interface {
 	Mount(Mux)
 }
+
+// Config configures the Mux returned by New.
+type Config struct {
+	// Router is the underlying gorilla router routes are registered on.
+	Router *mux.Router
+	// IssuerPath is prefixed onto every registered route.
+	IssuerPath string
+	// Headers are added to every response.
+	Headers http.Header
+	// RealIPHeader, when set, names the header the real client IP is read from.
+	RealIPHeader string
+	// Instrument wraps a handler with request metrics.
+	Instrument func(name string, h http.Handler) http.HandlerFunc
+	// RealIP extracts the client IP from a request.
+	RealIP func(*http.Request) (string, error)
+	// CORSOrigins / CORSHeaders configure HandleCORS; CORS is skipped when
+	// CORSOrigins is empty.
+	CORSOrigins []string
+	CORSHeaders []string
+}
+
+// New returns a Mux backed by the given config. Handle/HandleFunc/HandleCORS
+// prefix the route with the issuer path and wrap it with the response headers,
+// request-id/real-ip context, and instrumentation. HandlePrefix mounts static
+// asset trees directly (stripped of the prefix) without that wrapping.
+func New(c Config) Mux { return mountMux{c} }
+
+type mountMux struct{ c Config }
+
+// wrap applies the common response headers, request-id/real-ip context, and
+// instrumentation to a handler.
+func (m mountMux) wrap(name string, h http.Handler) http.HandlerFunc {
+	return func(w http.ResponseWriter, r *http.Request) {
+		for k, v := range m.c.Headers {
+			w.Header()[k] = v
+		}
+		// Context values are used for logging purposes with the log/slog logger.
+		rCtx := reqctx.WithRequestID(r.Context())
+		if m.c.RealIPHeader != "" && m.c.RealIP != nil {
+			if realIP, err := m.c.RealIP(r); err == nil {
+				rCtx = reqctx.WithRemoteIP(rCtx, realIP)
+			}
+		}
+		m.c.Instrument(name, h)(w, r.WithContext(rCtx))
+	}
+}
+
+func (m mountMux) Handle(p string, h http.Handler) {
+	m.c.Router.Handle(path.Join(m.c.IssuerPath, p), m.wrap(p, h))
+}
+
+func (m mountMux) HandleFunc(p string, h http.HandlerFunc) { m.Handle(p, h) }
+
+func (m mountMux) HandlePrefix(p string, h http.Handler) {
+	prefix := path.Join(m.c.IssuerPath, p)
+	m.c.Router.PathPrefix(prefix).Handler(http.StripPrefix(prefix, h))
+}
+
+func (m mountMux) HandleCORS(p string, h http.HandlerFunc) {
+	var handler http.Handler = h
+	if len(m.c.CORSOrigins) > 0 {
+		cors := handlers.CORS(
+			handlers.AllowedOrigins(m.c.CORSOrigins),
+			handlers.AllowedHeaders(m.c.CORSHeaders),
+		)
+		handler = cors(handler)
+	}
+	m.Handle(p, handler)
+}
diff --git a/server/server.go b/server/server.go
--- a/server/server.go
+++ b/server/server.go
@@ -2,7 +2,6 @@ package server
 
 import (
 	"context"
-	"encoding/json"
 	"errors"
 	"fmt"
 	"io/fs"
@@ -12,35 +11,15 @@ import (
 	"net/netip"
 	"net/url"
 	"os"
-	"path"
 	"sort"
 	"sync/atomic"
 	"time"
 
 	gosundheit "github.com/AppsFlyer/go-sundheit"
-	"github.com/gorilla/handlers"
 	"github.com/gorilla/mux"
 	"github.com/prometheus/client_golang/prometheus"
 	"github.com/prometheus/client_golang/prometheus/promhttp"
-	"golang.org/x/crypto/bcrypt"
-
-	"github.com/dexidp/dex/connector"
-	"github.com/dexidp/dex/connector/atlassiancrowd"
-	"github.com/dexidp/dex/connector/authproxy"
-	"github.com/dexidp/dex/connector/bitbucketcloud"
-	"github.com/dexidp/dex/connector/gitea"
-	"github.com/dexidp/dex/connector/github"
-	"github.com/dexidp/dex/connector/gitlab"
-	"github.com/dexidp/dex/connector/google"
-	"github.com/dexidp/dex/connector/keystone"
-	"github.com/dexidp/dex/connector/ldap"
-	"github.com/dexidp/dex/connector/linkedin"
-	"github.com/dexidp/dex/connector/microsoft"
-	"github.com/dexidp/dex/connector/mock"
-	"github.com/dexidp/dex/connector/oauth"
-	"github.com/dexidp/dex/connector/oidc"
-	"github.com/dexidp/dex/connector/openshift"
-	"github.com/dexidp/dex/connector/saml"
+
 	"github.com/dexidp/dex/pkg/featureflags"
 	"github.com/dexidp/dex/server/authflow"
 	"github.com/dexidp/dex/server/connectors"
@@ -53,8 +32,6 @@ import (
 	"github.com/dexidp/dex/server/logout"
 	"github.com/dexidp/dex/server/mfa"
 	"github.com/dexidp/dex/server/oauth2"
-	"github.com/dexidp/dex/server/passwords"
-	"github.com/dexidp/dex/server/reqctx"
 	"github.com/dexidp/dex/server/router"
 	"github.com/dexidp/dex/server/session"
 	"github.com/dexidp/dex/server/signer"
@@ -65,10 +42,6 @@ import (
 	"github.com/dexidp/dex/web"
 )
 
-// LocalConnector is the local passwordDB connector which is an internal
-// connector maintained by the server.
-const LocalConnector = "local"
-
 // Config holds the server's configuration options.
 //
 // Multiple servers using the same storage are expected to be configured identically.
@@ -189,7 +162,7 @@ func value(val, defaultValue time.Duration) time.Duration {
 
 // Server is the top level object.
 type Server struct {
-	issuerURL url.URL
+	issuerURL oauth2.IssuerURL
 
 	// In-memory cache of opened connectors.
 	connectors *connectors.Cache
@@ -200,81 +173,26 @@ type Server struct {
 
 	templates *templates.Templates
 
-	// If enabled, don't prompt user for approval after logging in through connector.
-	skipApproval bool
-
-	// If enabled, show the connector selection screen even if there's only one
-	alwaysShowLogin bool
-
-	// Used for password grant
-	passwordConnector string
-
-	supportedResponseTypes map[string]bool
-
-	supportedGrantTypes []string
-
-	pkce authflow.PKCEConfig
-
-	now func() time.Time
-
-	idTokensValidFor       time.Duration
-	authRequestsValidFor   time.Duration
-	deviceRequestsValidFor time.Duration
-
-	refreshTokenPolicy *tokens.RefreshStrategy
-
 	logger *slog.Logger
 
-	signer signer.Signer
-
 	// issuer turns an Authorization into a TokenSet.
 	issuer *tokens.Issuer
 
-	sessionConfig *session.Config
-
-	mfaProviders    map[string]mfa.Provider
-	defaultMFAChain []string
-}
-
-// routeMux adapts the server's route-registration closures to router.Mux so
-// domain handlers can mount their own routes.
-type routeMux struct {
-	handle       func(string, http.Handler)
-	handleFunc   func(string, http.HandlerFunc)
-	handleCORS   func(string, http.HandlerFunc)
-	handlePrefix func(string, http.Handler)
-}
-
-func (m routeMux) Handle(p string, h http.Handler)         { m.handle(p, h) }
-func (m routeMux) HandleFunc(p string, h http.HandlerFunc) { m.handleFunc(p, h) }
-func (m routeMux) HandleCORS(p string, h http.HandlerFunc) { m.handleCORS(p, h) }
-func (m routeMux) HandlePrefix(p string, h http.Handler)   { m.handlePrefix(p, h) }
+	// discovery is built once from config and shared by the mounted HTTP handler
+	// and the gRPC API's Discovery accessor.
+	discovery *discovery.Handler
 
-// newDiscoveryHandler builds a discovery handler from the server's settings. It
-// is shared by the mounted handler and ConstructDiscovery.
-func (s *Server) newDiscoveryHandler() *discovery.Handler {
-	return &discovery.Handler{
-		Issuer:          s.issuerURL.String(),
-		AbsURL:          s.absURL,
-		RenderError:     s.renderError,
-		Signer:          s.signer,
-		Logger:          s.logger,
-		ResponseTypes:   s.supportedResponseTypes,
-		GrantTypes:      s.supportedGrantTypes,
-		PKCEMethods:     s.pkce.CodeChallengeMethodsSupported,
-		SessionsEnabled: s.sessionConfig != nil,
-	}
+	sessionConfig *session.Config
 }
 
 // Connectors is the server's connector cache. The gRPC API needs it to
 // invalidate the cache on connector CRUD.
 func (s *Server) Connectors() *connectors.Cache { return s.connectors }
 
-// ConstructDiscovery builds the OIDC discovery document. The gRPC API's
-// GetDiscovery uses it to return the same document served over HTTP.
-func (s *Server) ConstructDiscovery(ctx context.Context) discovery.Document {
-	return s.newDiscoveryHandler().Construct(ctx)
-}
+// Discovery is the handler that builds the OIDC discovery document. The gRPC
+// API serves the same handler that is mounted for HTTP, so both return an
+// identical document.
+func (s *Server) Discovery() *discovery.Handler { return s.discovery }
 
 // NewServer constructs a server from the provided config.
 func NewServer(ctx context.Context, c Config) (*Server, error) {
@@ -379,29 +297,32 @@ func newServer(ctx context.Context, c Config) (*Server, error) {
 		now = time.Now
 	}
 
+	authRequestsValidFor := value(c.AuthRequestsValidFor, 24*time.Hour)
+	deviceRequestsValidFor := value(c.DeviceRequestsValidFor, 5*time.Minute)
+	idTokensValidFor := value(c.IDTokensValidFor, 24*time.Hour)
+
 	s := &Server{
-		issuerURL:              *issuerURL,
-		storage:                newKeyCacher(c.Storage, now),
-		supportedResponseTypes: supportedRes,
-		supportedGrantTypes:    supportedGrants,
-		pkce:                   c.PKCE,
-		idTokensValidFor:       value(c.IDTokensValidFor, 24*time.Hour),
-		authRequestsValidFor:   value(c.AuthRequestsValidFor, 24*time.Hour),
-		deviceRequestsValidFor: value(c.DeviceRequestsValidFor, 5*time.Minute),
-		refreshTokenPolicy:     c.RefreshTokenPolicy,
-		skipApproval:           c.SkipApprovalScreen,
-		alwaysShowLogin:        c.AlwaysShowLoginScreen,
-		now:                    now,
-		templates:              tmpls,
-		passwordConnector:      c.PasswordConnector,
-		logger:                 c.Logger,
-		signer:                 c.Signer,
-		sessionConfig:          c.SessionConfig,
-		mfaProviders:           c.MFAProviders,
-		defaultMFAChain:        c.DefaultMFAChain,
-	}
-	s.issuer = tokens.NewIssuer(s.storage, s.signer, s.issuerURL, s.idTokensValidFor, s.now, s.logger)
-	s.connectors = connectors.NewCache(s.storage, s.resolveConnector)
+		issuerURL:     oauth2.IssuerURL{URL: *issuerURL},
+		storage:       newKeyCacher(c.Storage, now),
+		templates:     tmpls,
+		logger:        c.Logger,
+		sessionConfig: c.SessionConfig,
+	}
+	s.issuer = tokens.NewIssuer(s.storage, c.Signer, s.issuerURL.URL, idTokensValidFor, now, s.logger)
+	s.connectors = connectors.NewCache(s.storage, connectors.Resolver(s.storage, s.logger, ConnectorsConfig))
+	// Build the discovery handler once from config; both the mounted HTTP route
+	// and the gRPC API (via Discovery) serve this same handler.
+	s.discovery = &discovery.Handler{
+		Issuer:          s.issuerURL.String(),
+		AbsURL:          s.issuerURL.AbsURL,
+		RenderError:     s.renderError,
+		Signer:          c.Signer,
+		Logger:          s.logger,
+		ResponseTypes:   supportedRes,
+		GrantTypes:      supportedGrants,
+		PKCEMethods:     c.PKCE.CodeChallengeMethodsSupported,
+		SessionsEnabled: s.sessionConfig != nil,
+	}
 	// sessions is shared infrastructure (session cookie, SSO, auth-session CRUD)
 	// referenced by the flow steps mounted below. The steps themselves hold no
 	// reference to one another; the /auth dispatcher decides MFA and consent from
@@ -410,7 +331,7 @@ func newServer(ctx context.Context, c Config) (*Server, error) {
 	sessions := &session.Manager{
 		Storage:   s.storage,
 		Config:    s.sessionConfig,
-		Now:       s.now,
+		Now:       now,
 		Logger:    s.logger,
 		IssuerURL: s.issuerURL,
 	}
@@ -428,7 +349,7 @@ func newServer(ctx context.Context, c Config) (*Server, error) {
 
 	var failedCount int
 	for _, conn := range storageConnectors {
-		if _, err := s.OpenConnector(conn); err != nil {
+		if _, err := s.connectors.Open(conn); err != nil {
 			failedCount++
 			if c.ContinueOnConnectorFailure {
 				s.logger.Error("server: Failed to open connector", "id", conn.ID, "err", err)
@@ -507,86 +428,52 @@ func newServer(ctx context.Context, c Config) (*Server, error) {
 		return remoteAddr, nil
 	}
 
-	handlerWithHeaders := func(handlerName string, handler http.Handler) http.HandlerFunc {
-		return func(w http.ResponseWriter, r *http.Request) {
-			for k, v := range c.Headers {
-				w.Header()[k] = v
-			}
-
-			// Context values are used for logging purposes with the log/slog logger.
-			rCtx := r.Context()
-			rCtx = reqctx.WithRequestID(rCtx)
-
-			if c.RealIPHeader != "" {
-				realIP, err := parseRealIP(r)
-				if err == nil {
-					rCtx = reqctx.WithRemoteIP(rCtx, realIP)
-				}
-			}
-
-			r = r.WithContext(rCtx)
-			instrumentHandler(handlerName, handler)(w, r)
-		}
-	}
-
 	r := mux.NewRouter().SkipClean(true).UseEncodedPath()
-	handle := func(p string, h http.Handler) {
-		r.Handle(path.Join(issuerURL.Path, p), handlerWithHeaders(p, h))
-	}
-	handleFunc := func(p string, h http.HandlerFunc) {
-		handle(p, h)
-	}
-	handlePrefix := func(p string, h http.Handler) {
-		prefix := path.Join(issuerURL.Path, p)
-		r.PathPrefix(prefix).Handler(http.StripPrefix(prefix, h))
-	}
-	handleWithCORS := func(p string, h http.HandlerFunc) {
-		var handler http.Handler = h
-		if len(c.AllowedOrigins) > 0 {
-			cors := handlers.CORS(
-				handlers.AllowedOrigins(c.AllowedOrigins),
-				handlers.AllowedHeaders(c.AllowedHeaders),
-			)
-			handler = cors(handler)
-		}
-		r.Handle(path.Join(issuerURL.Path, p), handlerWithHeaders(p, handler))
-	}
 	r.NotFoundHandler = http.NotFoundHandler()
 
 	// Self-contained domains mount their own routes through the router.Mux
-	// abstraction, so this list is the only place they are wired in.
-	mux := routeMux{handle: handle, handleFunc: handleFunc, handleCORS: handleWithCORS, handlePrefix: handlePrefix}
+	// abstraction; this is the only place they are wired in.
+	routes := router.New(router.Config{
+		Router:       r,
+		IssuerPath:   issuerURL.Path,
+		Headers:      c.Headers,
+		RealIPHeader: c.RealIPHeader,
+		Instrument:   instrumentHandler,
+		RealIP:       parseRealIP,
+		CORSOrigins:  c.AllowedOrigins,
+		CORSHeaders:  c.AllowedHeaders,
+	})
 	for _, h := range []router.Handler{
-		s.newDiscoveryHandler(),
+		s.discovery,
 		&grants.Handler{
 			Issuer:              s.issuer,
 			Storage:             s.storage,
 			Connectors:          s.connectors,
-			Now:                 s.now,
+			Now:                 now,
 			Logger:              s.logger,
-			PasswordConnector:   s.passwordConnector,
-			RefreshPolicy:       s.refreshTokenPolicy,
+			PasswordConnector:   c.PasswordConnector,
+			RefreshPolicy:       c.RefreshTokenPolicy,
 			SessionsEnabled:     s.sessionConfig != nil,
-			SupportedGrantTypes: s.supportedGrantTypes,
+			SupportedGrantTypes: supportedGrants,
 		},
 		&userinfo.Handler{
 			Issuer: s.issuerURL.String(),
-			Signer: s.signer,
+			Signer: c.Signer,
 			Logger: s.logger,
 		},
 		&introspection.Handler{
 			Issuer:        s.issuerURL.String(),
-			Signer:        s.signer,
+			Signer:        c.Signer,
 			Storage:       s.storage,
 			Logger:        s.logger,
-			RefreshPolicy: s.refreshTokenPolicy,
+			RefreshPolicy: c.RefreshTokenPolicy,
 		},
 		&device.Handler{
 			IssuerURL:        s.issuerURL,
 			Storage:          s.storage,
 			Templates:        s.templates,
-			Now:              s.now,
-			RequestsValidFor: s.deviceRequestsValidFor,
+			Now:              now,
+			RequestsValidFor: deviceRequestsValidFor,
 			Logger:           s.logger,
 			Issuer:           s.issuer,
 			Connectors:       s.connectors,
@@ -603,27 +490,27 @@ func newServer(ctx context.Context, c Config) (*Server, error) {
 			Connectors:             s.connectors,
 			Storage:                s.storage,
 			Templates:              s.templates,
-			Signer:                 s.signer,
-			Now:                    s.now,
+			Signer:                 c.Signer,
+			Now:                    now,
 			Logger:                 s.logger,
-			AlwaysShowLogin:        s.alwaysShowLogin,
-			SupportedResponseTypes: s.supportedResponseTypes,
-			PKCE:                   s.pkce,
-			AuthRequestsValidFor:   s.authRequestsValidFor,
+			AlwaysShowLogin:        c.AlwaysShowLoginScreen,
+			SupportedResponseTypes: supportedRes,
+			PKCE:                   c.PKCE,
+			AuthRequestsValidFor:   authRequestsValidFor,
 			Sessions:               sessions,
 			Issuer:                 s.issuer,
-			MFAEnabled:             len(s.mfaProviders) > 0,
-			DefaultMFAChain:        s.defaultMFAChain,
-			SkipApproval:           s.skipApproval,
+			MFAEnabled:             len(c.MFAProviders) > 0,
+			DefaultMFAChain:        c.DefaultMFAChain,
+			SkipApproval:           c.SkipApprovalScreen,
 		},
 		&mfa.Handler{
 			Storage:         s.storage,
 			Templates:       s.templates,
 			Logger:          s.logger,
 			IssuerURL:       s.issuerURL,
-			MFAProviders:    s.mfaProviders,
-			DefaultMFAChain: s.defaultMFAChain,
-			Now:             s.now,
+			MFAProviders:    c.MFAProviders,
+			DefaultMFAChain: c.DefaultMFAChain,
+			Now:             now,
 			Connectors:      s.connectors,
 		},
 		&consent.Handler{
@@ -632,7 +519,7 @@ func newServer(ctx context.Context, c Config) (*Server, error) {
 			Logger:       s.logger,
 			IssuerURL:    s.issuerURL,
 			Sessions:     sessions,
-			SkipApproval: s.skipApproval,
+			SkipApproval: c.SkipApprovalScreen,
 		},
 		&logout.Handler{
 			Storage:    s.storage,
@@ -641,29 +528,28 @@ func newServer(ctx context.Context, c Config) (*Server, error) {
 			Sessions:   sessions,
 			Connectors: s.connectors,
 			Issuer:     s.issuer,
-			Signer:     s.signer,
+			Signer:     c.Signer,
 			IssuerURL:  s.issuerURL,
 		},
 	} {
-		h.Mount(mux)
+		h.Mount(routes)
 	}
 
-	// TODO(ericchiang): rate limit certain paths based on IP.
-	handle("/healthz", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
+	routes.Handle("/healthz", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
 		if !c.HealthChecker.IsHealthy() {
 			s.renderError(r, w, http.StatusInternalServerError, "Health check failed.")
 			return
 		}
 		fmt.Fprintf(w, "Health check passed")
 	}))
 
-	handlePrefix("/static", static)
-	handlePrefix("/theme", theme)
-	handleFunc("/robots.txt", robots)
+	routes.HandlePrefix("/static", static)
+	routes.HandlePrefix("/theme", theme)
+	routes.HandleFunc("/robots.txt", robots)
 
 	s.mux = r
 
-	s.signer.Start(ctx)
+	c.Signer.Start(ctx)
 	s.startGarbageCollection(ctx, value(c.GCFrequency, 5*time.Minute), now)
 
 	return s, nil
@@ -673,102 +559,6 @@ func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
 	s.mux.ServeHTTP(w, r)
 }
 
-func (s *Server) absPath(pathItems ...string) string {
-	paths := make([]string, len(pathItems)+1)
-	paths[0] = s.issuerURL.Path
-	copy(paths[1:], pathItems)
-	return path.Join(paths...)
-}
-
-func (s *Server) absURL(pathItems ...string) string {
-	u := s.issuerURL
-	u.Path = s.absPath(pathItems...)
-	return u.String()
-}
-
-func newPasswordDB(s storage.Storage) interface {
-	connector.Connector
-	connector.PasswordConnector
-} {
-	return passwordDB{s}
-}
-
-type passwordDB struct {
-	s storage.Storage
-}
-
-func resolvePasswordName(p storage.Password) string {
-	if p.Name != "" {
-		return p.Name
-	}
-	return p.Username
-}
-
-func resolvePasswordEmailVerified(p storage.Password) bool {
-	if p.EmailVerified != nil {
-		return *p.EmailVerified
-	}
-	return true
-}
-
-func (db passwordDB) Login(ctx context.Context, s connector.Scopes, email, password string) (connector.Identity, bool, error) {
-	p, err := db.s.GetPassword(ctx, email)
-	if err != nil {
-		if err != storage.ErrNotFound {
-			return connector.Identity{}, false, fmt.Errorf("get password: %v", err)
-		}
-		return connector.Identity{}, false, nil
-	}
-	// This check prevents dex users from logging in using static passwords
-	// configured with hash costs that are too high or low.
-	if err := passwords.CheckCost(p.Hash); err != nil {
-		return connector.Identity{}, false, err
-	}
-	if err := bcrypt.CompareHashAndPassword(p.Hash, []byte(password)); err != nil {
-		return connector.Identity{}, false, nil
-	}
-	return connector.Identity{
-		UserID:            p.UserID,
-		Username:          resolvePasswordName(p),
-		PreferredUsername: p.PreferredUsername,
-		Email:             p.Email,
-		EmailVerified:     resolvePasswordEmailVerified(p),
-		Groups:            p.Groups,
-	}, true, nil
-}
-
-func (db passwordDB) Refresh(ctx context.Context, s connector.Scopes, identity connector.Identity) (connector.Identity, error) {
-	// If the user has been deleted, the refresh token will be rejected.
-	p, err := db.s.GetPassword(ctx, identity.Email)
-	if err != nil {
-		if err == storage.ErrNotFound {
-			return connector.Identity{}, errors.New("user not found")
-		}
-		return connector.Identity{}, fmt.Errorf("get password: %v", err)
-	}
-
-	// User removed but a new user with the same email exists.
-	if p.UserID != identity.UserID {
-		return connector.Identity{}, errors.New("user not found")
-	}
-
-	// If a user has updated their username, that will be reflected in the
-	// refreshed token.
-	//
-	// No other fields are expected to be refreshable as email is effectively used
-	// as an ID.
-	identity.Username = resolvePasswordName(p)
-	identity.PreferredUsername = p.PreferredUsername
-	identity.EmailVerified = resolvePasswordEmailVerified(p)
-	identity.Groups = p.Groups
-
-	return identity, nil
-}
-
-func (db passwordDB) Prompt() string {
-	return "Email Address"
-}
-
 // newKeyCacher returns a storage which caches keys so long as the next
 func newKeyCacher(s storage.Storage, now func() time.Time) storage.Storage {
 	if now == nil {
@@ -821,79 +611,6 @@ func (s *Server) startGarbageCollection(ctx context.Context, frequency time.Dura
 	}()
 }
 
-// ConnectorConfig is a configuration that can open a connector.
-type ConnectorConfig interface {
-	Open(id string, logger *slog.Logger) (connector.Connector, error)
-}
-
-// ConnectorsConfig variable provides an easy way to return a config struct
-// depending on the connector type.
-var ConnectorsConfig = map[string]func() ConnectorConfig{
-	"keystone":        func() ConnectorConfig { return new(keystone.Config) },
-	"mockCallback":    func() ConnectorConfig { return new(mock.CallbackConfig) },
-	"mockPassword":    func() ConnectorConfig { return new(mock.PasswordConfig) },
-	"ldap":            func() ConnectorConfig { return new(ldap.Config) },
-	"gitea":           func() ConnectorConfig { return new(gitea.Config) },
-	"github":          func() ConnectorConfig { return new(github.Config) },
-	"gitlab":          func() ConnectorConfig { return new(gitlab.Config) },
-	"google":          func() ConnectorConfig { return new(google.Config) },
-	"oidc":            func() ConnectorConfig { return new(oidc.Config) },
-	"oauth":           func() ConnectorConfig { return new(oauth.Config) },
-	"saml":            func() ConnectorConfig { return new(saml.Config) },
-	"authproxy":       func() ConnectorConfig { return new(authproxy.Config) },
-	"linkedin":        func() ConnectorConfig { return new(linkedin.Config) },
-	"microsoft":       func() ConnectorConfig { return new(microsoft.Config) },
-	"bitbucket-cloud": func() ConnectorConfig { return new(bitbucketcloud.Config) },
-	"openshift":       func() ConnectorConfig { return new(openshift.Config) },
-	"atlassian-crowd": func() ConnectorConfig { return new(atlassiancrowd.Config) },
-	// Keep around for backwards compatibility.
-	"samlExperimental": func() ConnectorConfig { return new(saml.Config) },
-}
-
-// openConnector will parse the connector config and open the connector.
-func openConnector(logger *slog.Logger, conn storage.Connector) (connector.Connector, error) {
-	var c connector.Connector
-
-	f, ok := ConnectorsConfig[conn.Type]
-	if !ok {
-		return c, fmt.Errorf("unknown connector type %q", conn.Type)
-	}
-
-	connConfig := f()
-	if len(conn.Config) != 0 {
-		data := []byte(string(conn.Config))
-		if err := json.Unmarshal(data, connConfig); err != nil {
-			return c, fmt.Errorf("parse connector config: %v", err)
-		}
-	}
-
-	c, err := connConfig.Open(conn.ID, logger)
-	if err != nil {
-		return c, fmt.Errorf("failed to create connector %s: %v", conn.ID, err)
-	}
-
-	return c, nil
-}
-
-// resolveConnector builds the underlying connector implementation for a stored
-// connector: the built-in local password DB, or a configured connector.
-func (s *Server) resolveConnector(conn storage.Connector) (connector.Connector, error) {
-	if conn.Type == LocalConnector {
-		return newPasswordDB(s.storage), nil
-	}
-	return openConnector(s.logger, conn)
-}
-
-// OpenConnector opens the given connector and records it in the in-memory cache.
-func (s *Server) OpenConnector(conn storage.Connector) (connectors.Connector, error) {
-	return s.connectors.Open(conn)
-}
-
-// CloseConnector removes the connector from the in-memory cache.
-func (s *Server) CloseConnector(id string) {
-	s.connectors.Close(id)
-}
-
 // renderError renders a user-facing error page for the non-flow endpoints the
 // server still serves directly (e.g. /healthz).
 func (s *Server) renderError(r *http.Request, w http.ResponseWriter, status int, description string) {
diff --git a/server/session/session.go b/server/session/session.go
--- a/server/session/session.go
+++ b/server/session/session.go
@@ -7,10 +7,10 @@ import (
 	"fmt"
 	"log/slog"
 	"net/http"
-	"net/url"
 	"time"
 
 	"github.com/dexidp/dex/server/internal"
+	"github.com/dexidp/dex/server/oauth2"
 	"github.com/dexidp/dex/server/reqctx"
 	"github.com/dexidp/dex/storage"
 )
@@ -33,7 +33,7 @@ type Manager struct {
 	Config    *Config
 	Now       func() time.Time
 	Logger    *slog.Logger
-	IssuerURL url.URL
+	IssuerURL oauth2.IssuerURL
 }
 
 // Enabled reports whether sessions are configured.
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
