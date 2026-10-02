#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/agent/agent.go b/agent/agent.go
--- a/agent/agent.go
+++ b/agent/agent.go
@@ -11,25 +11,25 @@ import (
 	"slices"
 
 	"github.com/google/uuid"
-	"github.com/microsoft/agent-framework-go/agentopt"
+	"github.com/microsoft/agent-framework-go/agent/internal/middleware/autocall"
+	"github.com/microsoft/agent-framework-go/agent/internal/middleware/contextprovider"
+	"github.com/microsoft/agent-framework-go/agent/internal/middleware/structuredoutput"
 	"github.com/microsoft/agent-framework-go/format"
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
-	"github.com/microsoft/agent-framework-go/middleware/autocall"
-	"github.com/microsoft/agent-framework-go/middleware/contextprovider"
-	"github.com/microsoft/agent-framework-go/middleware/structuredoutput"
 	"github.com/microsoft/agent-framework-go/tool"
 )
 
+type RunFunc = func(ctx context.Context, messages []*message.Message, options ...Option) iter.Seq2[*message.ResponseUpdate, error]
+
 type ProviderConfig struct {
 	ProviderName string
 
 	// Required functions
-	Run func(ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error]
+	Run RunFunc
 
 	// Optional functions
-	CreateSession    func(ctx context.Context, options ...agentopt.Option) (*memory.Session, error)
+	CreateSession    func(ctx context.Context, options ...Option) (*memory.Session, error)
 	MarshalSession   func(ctx context.Context, session *memory.Session) ([]byte, error)
 	UnmarshalSession func(ctx context.Context, data []byte) (*memory.Session, error)
 	FormatOfFn       func(v any) (format.Format, error)
@@ -50,9 +50,9 @@ type Config struct {
 	Logger           *slog.Logger
 	LogSensitiveData bool
 
-	Middlewares []middleware.Middleware
+	Middlewares []Middleware
 	Tools       []tool.Tool
-	RunOptions  []agentopt.Option
+	RunOptions  []Option
 }
 
 func New(prov ProviderConfig, cfg Config) *Agent {
@@ -68,7 +68,7 @@ func New(prov ProviderConfig, cfg Config) *Agent {
 	cfg.Tools = slices.Clone(cfg.Tools)
 	for _, tool := range cfg.Tools {
 		if tool != nil {
-			cfg.RunOptions = append(cfg.RunOptions, agentopt.Tool(tool))
+			cfg.RunOptions = append(cfg.RunOptions, WithTool(tool))
 		}
 	}
 	cfg.Middlewares = slices.Clone(cfg.Middlewares)
@@ -94,7 +94,7 @@ func New(prov ProviderConfig, cfg Config) *Agent {
 			}),
 		)
 	}
-	prefixedMiddlewares := make([]middleware.Middleware, 0, 2)
+	prefixedMiddlewares := make([]Middleware, 0, 2)
 	if len(providers) == 0 {
 		prefixedMiddlewares = append(prefixedMiddlewares, defaultLocalHistoryMiddleware())
 	}
@@ -142,13 +142,13 @@ type Agent struct {
 
 	instructions string
 
-	middlewares []middleware.Middleware
-	runOptions  []agentopt.Option
+	middlewares []Middleware
+	runOptions  []Option
 
-	createSession    func(ctx context.Context, options ...agentopt.Option) (*memory.Session, error)
+	createSession    func(ctx context.Context, options ...Option) (*memory.Session, error)
 	marshalSession   func(ctx context.Context, session *memory.Session) ([]byte, error)
 	unmarshalSession func(ctx context.Context, data []byte) (*memory.Session, error)
-	run              func(ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error]
+	run              func(ctx context.Context, messages []*message.Message, options ...Option) iter.Seq2[*message.ResponseUpdate, error]
 }
 
 func (a *Agent) ID() string {
@@ -179,10 +179,10 @@ func (a *Agent) ProviderName() string {
 	return a.providerName
 }
 
-func (a *Agent) CreateSession(ctx context.Context, options ...agentopt.Option) (*memory.Session, error) {
+func (a *Agent) CreateSession(ctx context.Context, options ...Option) (*memory.Session, error) {
 	if a.createSession == nil {
 		session := memory.NewSession("")
-		session.ServiceID, _ = agentopt.Get(options, agentopt.ServiceID)
+		session.ServiceID, _ = GetOption(options, WithServiceID)
 		return session, nil
 	}
 	return a.createSession(ctx, options...)
@@ -209,32 +209,32 @@ func (a *Agent) UnmarshalSession(ctx context.Context, data []byte) (*memory.Sess
 	return a.unmarshalSession(ctx, data)
 }
 
-func (a *Agent) RunText(ctx context.Context, msg string, options ...agentopt.Option) ResponseStream {
+func (a *Agent) RunText(ctx context.Context, msg string, options ...Option) ResponseStream {
 	return a.Run(ctx, []*message.Message{message.NewText(msg)}, options...)
 }
 
-func (a *Agent) RunMessage(ctx context.Context, msg *message.Message, options ...agentopt.Option) ResponseStream {
+func (a *Agent) RunMessage(ctx context.Context, msg *message.Message, options ...Option) ResponseStream {
 	return a.Run(ctx, []*message.Message{msg}, options...)
 }
 
-func (a *Agent) Run(ctx context.Context, messages []*message.Message, options ...agentopt.Option) ResponseStream {
+func (a *Agent) Run(ctx context.Context, messages []*message.Message, options ...Option) ResponseStream {
 	ctx, preparedMessages, options, err := a.prepareRun(ctx, messages, options)
 	if err != nil {
 		return func(yield func(*message.ResponseUpdate, error) bool) {
 			yield(nil, err)
 		}
 	}
-	return ResponseStream(middleware.RunChain(ctx, a.run, a.middlewares, preparedMessages, options...))
+	return ResponseStream(runChain(ctx, a.run, a.middlewares, preparedMessages, options...))
 }
 
-func (a *Agent) prepareRun(ctx context.Context, messages []*message.Message, options []agentopt.Option) (context.Context, []*message.Message, []agentopt.Option, error) {
+func (a *Agent) prepareRun(ctx context.Context, messages []*message.Message, options []Option) (context.Context, []*message.Message, []Option, error) {
 	// Prepend options from agent configuration.
 	if len(a.runOptions) != 0 {
 		options = append(a.runOptions, options...)
 	}
 
-	if _, ok := agentopt.Get(options, agentopt.Session); !ok {
-		if allowBackgroundResponses, ok := agentopt.Get(options, agentopt.AllowBackgroundResponses); ok && allowBackgroundResponses {
+	if _, ok := GetOption(options, WithSession); !ok {
+		if allowBackgroundResponses, ok := GetOption(options, AllowBackgroundResponses); ok && allowBackgroundResponses {
 			// Background responses require an explicit session to avoid inconsistent
 			// caller experience between initial and follow-up runs.
 			return nil, nil, nil, errors.New("a session must be provided when AllowBackgroundResponses is enabled")
@@ -244,10 +244,10 @@ func (a *Agent) prepareRun(ctx context.Context, messages []*message.Message, opt
 		if err != nil {
 			return nil, nil, nil, err
 		}
-		options = append(options, agentopt.Session(session), noSessionProvided(true))
+		options = append(options, WithSession(session), noSessionProvided(true))
 	}
 
-	continuationToken, _ := agentopt.Get(options, agentopt.ContinuationToken)
+	continuationToken, _ := GetOption(options, WithContinuationToken)
 	if continuationToken != "" && len(messages) > 0 {
 		return nil, nil, nil, errors.New("messages are not allowed when continuing a background response using a continuation token")
 	}
@@ -276,22 +276,22 @@ func (a *Agent) prepareRun(ctx context.Context, messages []*message.Message, opt
 // configuration. New prepends it only when Config.ContextProviders is empty.
 // It is bypassed for auto-created sessions on the first run, service-managed
 // sessions, and continuation-token resumes.
-func defaultLocalHistoryMiddleware() middleware.Middleware {
+func defaultLocalHistoryMiddleware() Middleware {
 	history := contextprovider.New(memory.NewInMemoryHistoryProvider("in-memory"))
 
-	return middleware.Func(func(next middleware.RunFunc, ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
-		session, _ := agentopt.Get(options, agentopt.Session)
-		noSession, _ := agentopt.Get(options, noSessionProvided)
-		contToken, _ := agentopt.Get(options, agentopt.ContinuationToken)
+	return MiddlewareFunc(func(next RunFunc, ctx context.Context, messages []*message.Message, options ...Option) iter.Seq2[*message.ResponseUpdate, error] {
+		session, _ := GetOption(options, WithSession)
+		noSession, _ := GetOption(options, noSessionProvided)
+		contToken, _ := GetOption(options, WithContinuationToken)
 		if noSession || contToken != "" || session.ServiceID != "" {
 			return next(ctx, messages, options...)
 		}
 		return history.Run(next, ctx, messages, options...)
 	})
 }
 
-func authorMiddleware(id, name string) middleware.Middleware {
-	return middleware.Func(func(next middleware.RunFunc, ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func authorMiddleware(id, name string) Middleware {
+	return MiddlewareFunc(func(next RunFunc, ctx context.Context, messages []*message.Message, options ...Option) iter.Seq2[*message.ResponseUpdate, error] {
 		return func(yield func(*message.ResponseUpdate, error) bool) {
 			for update, err := range next(ctx, messages, options...) {
 				if update != nil {
@@ -316,7 +316,7 @@ type noSessionOpt bool
 
 func (o noSessionOpt) Value() any { return bool(o) }
 
-func noSessionProvided(v bool) agentopt.Option {
+func noSessionProvided(v bool) Option {
 	return noSessionOpt(v)
 }
 
diff --git a/agent/hosting/a2ahosting/a2a.go b/agent/hosting/a2ahosting/a2a.go
--- a/agent/hosting/a2ahosting/a2a.go
+++ b/agent/hosting/a2ahosting/a2a.go
@@ -8,13 +8,20 @@ import (
 	"github.com/a2aproject/a2a-go/v2/a2asrv"
 )
 
+// NewRequestHandler creates a new request handler.
 func NewRequestHandler(cfg ExecutorConfig, options ...a2asrv.RequestHandlerOption) a2asrv.RequestHandler {
 	if cfg.Agent == nil {
 		panic("agent is required")
 	}
 	return a2asrv.NewHandler(NewExecutor(cfg), options...)
 }
 
-func NewHTTPHandler(cfg ExecutorConfig, options ...a2asrv.RequestHandlerOption) http.Handler {
+// NewJSONRPCHandler creates an [http.Handler] which implements JSONRPC A2A protocol binding.
+func NewJSONRPCHandler(cfg ExecutorConfig, options ...a2asrv.RequestHandlerOption) http.Handler {
 	return a2asrv.NewJSONRPCHandler(NewRequestHandler(cfg, options...))
 }
+
+// NewRESTHandler creates an [http.Handler] which implements the HTTP+JSON A2A protocol binding.
+func NewJSONHTTPHandler(cfg ExecutorConfig, options ...a2asrv.RequestHandlerOption) http.Handler {
+	return a2asrv.NewRESTHandler(NewRequestHandler(cfg, options...))
+}
diff --git a/agent/hosting/a2ahosting/executor.go b/agent/hosting/a2ahosting/executor.go
--- a/agent/hosting/a2ahosting/executor.go
+++ b/agent/hosting/a2ahosting/executor.go
@@ -10,7 +10,6 @@ import (
 	"github.com/a2aproject/a2a-go/v2/a2a"
 	"github.com/a2aproject/a2a-go/v2/a2asrv"
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/message"
 )
 
@@ -55,15 +54,15 @@ func (e *executor) Execute(ctx context.Context, execCtx *a2asrv.ExecutorContext)
 			return
 		}
 
-		session, err := e.cfg.Agent.CreateSession(ctx, agentopt.ServiceID(execCtx.ContextID))
+		session, err := e.cfg.Agent.CreateSession(ctx, agent.WithServiceID(execCtx.ContextID))
 		if err != nil {
 			yield(nil, err)
 			return
 		}
 
-		runOptions := []agentopt.Option{
-			agentopt.Session(session),
-			agentopt.AllowBackgroundResponses(allowBackground),
+		runOptions := []agent.Option{
+			agent.WithSession(session),
+			agent.AllowBackgroundResponses(allowBackground),
 		}
 
 		resp, runErr := e.cfg.Agent.Run(ctx, messagesIn, runOptions...).Collect()
diff --git a/agent/hosting/aguihosting/agui.go b/agent/hosting/aguihosting/agui.go
--- a/agent/hosting/aguihosting/agui.go
+++ b/agent/hosting/aguihosting/agui.go
@@ -14,7 +14,6 @@ import (
 	aguiTypes "github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/core/types"
 	aguiSSE "github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/encoding/sse"
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/message"
 )
 
@@ -24,7 +23,7 @@ type HandlerConfig struct {
 	Logger *slog.Logger
 }
 
-func NewHTTPHandler(cfg HandlerConfig) http.Handler {
+func NewJSONHTTPHandler(cfg HandlerConfig) http.Handler {
 	if cfg.Agent == nil {
 		panic("agent is required")
 	}
@@ -64,9 +63,9 @@ func NewHTTPHandler(cfg HandlerConfig) http.Handler {
 		w.Header().Set("Cache-Control", "no-cache,no-store")
 		w.Header().Set("Pragma", "no-cache")
 
-		var runOptions []agentopt.Option
+		var runOptions []agent.Option
 		for _, t := range toDeclarationTools(input.Tools) {
-			runOptions = append(runOptions, agentopt.Tool(t))
+			runOptions = append(runOptions, agent.WithTool(t))
 		}
 		updates := cfg.Agent.Run(r.Context(), messagesIn, runOptions...)
 		updatesSeq := iter.Seq2[*message.ResponseUpdate, error](updates)
diff --git a/agent/internal/agentopt/README.go b/agent/internal/agentopt/README.go
new file mode 100644
--- /dev/null
+++ b/agent/internal/agentopt/README.go
@@ -0,0 +1,4 @@
+// Package agentopt contains internal option plumbing.
+//
+// See README.md for rationale and package design notes.
+package agentopt
diff --git a/agent/internal/agentopt/README.md b/agent/internal/agentopt/README.md
new file mode 100644
--- /dev/null
+++ b/agent/internal/agentopt/README.md
@@ -0,0 +1,19 @@
+This package exists to hold agent options implementations that are used by the
+`agent` package itself.
+
+Why this is internal:
+- Public option APIs are exposed from the `agent` package (for example setters
+	like `WithSession`, `WithTool`, and `Stream`).
+- The `agent` package also imports internal middleware implementations to wire
+	default behavior in `agent.New(...)`.
+- Those middleware implementations need to read and append run options.
+
+If middleware implementations imported the public `agent` option API directly,
+Go would create an import cycle:
+
+`agent -> internal middleware implementation -> agent`
+
+To avoid that cycle, shared option plumbing lives here in an internal package.
+The public `agent` option functions are thin wrappers over these internal
+types, and adapter packages expose middleware functionality through the public
+`agent` surface without creating circular dependencies.
diff --git a/agent/internal/agentopt/agentopt.go b/agent/internal/agentopt/agentopt.go
new file mode 100644
--- /dev/null
+++ b/agent/internal/agentopt/agentopt.go
@@ -0,0 +1,108 @@
+// Copyright (c) Microsoft. All rights reserved.
+
+package agentopt
+
+import (
+	"iter"
+	"reflect"
+	"slices"
+
+	"github.com/microsoft/agent-framework-go/format"
+	"github.com/microsoft/agent-framework-go/memory"
+	"github.com/microsoft/agent-framework-go/tool"
+)
+
+type Option interface {
+	Value() any
+}
+
+type (
+	responseFormatOpt    struct{ format.Format }
+	sessionOpt           struct{ *memory.Session }
+	continuationTokenOpt string
+	serviceIDOpt         string
+
+	toolOpt struct{ tool.Tool }
+
+	toolModeOpt                 tool.ToolMode
+	streamOpt                   bool
+	allowBackgroundResponsesOpt bool
+
+	structuredOutputOpt struct{ any }
+)
+
+func (o responseFormatOpt) Value() any           { return o.Format }
+func (o sessionOpt) Value() any                  { return o.Session }
+func (o streamOpt) Value() any                   { return bool(o) }
+func (o continuationTokenOpt) Value() any        { return string(o) }
+func (o allowBackgroundResponsesOpt) Value() any { return bool(o) }
+func (o toolModeOpt) Value() any                 { return tool.ToolMode(o) }
+func (o toolOpt) Value() any                     { return o.Tool }
+func (o structuredOutputOpt) Value() any         { return o.any }
+func (o serviceIDOpt) Value() any                { return string(o) }
+
+func WithServiceID(id string) Option {
+	return serviceIDOpt(id)
+}
+
+func WithStructuredOutput(v any) Option {
+	return structuredOutputOpt{v}
+}
+
+func WithTool(tool tool.Tool) Option {
+	return toolOpt{tool}
+}
+
+func WithToolMode(mode tool.ToolMode) Option {
+	return toolModeOpt(mode)
+}
+
+func Stream(stream bool) Option {
+	return streamOpt(stream)
+}
+
+func WithResponseFormat(format format.Format) Option {
+	return responseFormatOpt{format}
+}
+
+func WithSession(session *memory.Session) Option {
+	return sessionOpt{session}
+}
+
+func WithContinuationToken(token string) Option {
+	return continuationTokenOpt(token)
+}
+
+func AllowBackgroundResponses(allow bool) Option {
+	return allowBackgroundResponsesOpt(allow)
+}
+
+func GetOption[T any](opts []Option, setter func(T) Option) (T, bool) {
+	var zero T
+	var setterType = reflect.TypeOf(setter(zero))
+	for _, opt := range slices.Backward(opts) {
+		if reflect.TypeOf(opt) == setterType {
+			v, ok := opt.Value().(T)
+			return v, ok
+		}
+	}
+	return zero, false
+}
+
+func AllOptions[T any](opts []Option, setter func(T) Option) iter.Seq[T] {
+	return func(yield func(T) bool) {
+		var zero T
+		var setterType = reflect.TypeOf(setter(zero))
+		for _, opt := range opts {
+			if reflect.TypeOf(opt) == setterType {
+				v, ok := opt.Value().(T)
+				if !ok {
+					panic("option type mismatch")
+				}
+				if !yield(v) {
+					return
+				}
+			}
+		}
+	}
+}
diff --git a/agent/internal/middleware/README.md b/agent/internal/middleware/README.md
new file mode 100644
--- /dev/null
+++ b/agent/internal/middleware/README.md
@@ -0,0 +1,16 @@
+This package exists to hold middleware implementations that are used by the
+`agent` package itself.
+
+Why this is internal:
+- Public middleware APIs are defined in `agent` (for example `agent.Middleware`,
+	`agent.RunFunc`, and `agent.Option`).
+- Some middleware implementations need to be wired in by `agent.New(...)` as
+	defaults and therefore are imported by the `agent` package.
+- If those middleware implementations were in a package that imported `agent`
+	directly, Go would create an import cycle:
+	`agent` -> `middleware implementation` -> `agent`.
+
+To avoid that cycle, implementations in this folder depend on internal option
+types (`internal/agentopt`) and internal middleware interfaces, and the public
+`agent/middleware/...` packages provide thin adapters that expose the same
+behavior through the public `agent` API.
diff --git a/middleware/autocall/autocall.go b/agent/internal/middleware/autocall/autocall.go
rename from middleware/autocall/autocall.go
rename to agent/internal/middleware/autocall/autocall.go
--- a/middleware/autocall/autocall.go
+++ b/agent/internal/middleware/autocall/autocall.go
@@ -15,10 +15,10 @@ import (
 	"time"
 
 	"github.com/google/uuid"
-	"github.com/microsoft/agent-framework-go/agentopt"
+	"github.com/microsoft/agent-framework-go/agent/internal/agentopt"
+	"github.com/microsoft/agent-framework-go/agent/internal/middleware"
 	"github.com/microsoft/agent-framework-go/internal/slogx"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/microsoft/agent-framework-go/tool"
 )
 
@@ -70,7 +70,7 @@ func New(cfg Config) middleware.Middleware {
 
 func (f *autocall) Run(next middleware.RunFunc, ctx context.Context, messages []*message.Message, opts ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	return func(yield func(*message.ResponseUpdate, error) bool) {
-		tools, requiresApproval := f.createToolsMap(agentopt.All(opts, agentopt.Tool))
+		tools, requiresApproval := f.createToolsMap(agentopt.AllOptions(opts, agentopt.WithTool))
 
 		// This is a synthetic ID since we're generating the tool messages instead of getting them from
 		// the underlying provider. When emitting the streamed chunks, it's perfectly valid for us to
@@ -155,7 +155,7 @@ func (f *autocall) Run(next middleware.RunFunc, ctx context.Context, messages []
 				// or the first time we get an FCC that requires approval. At that point, we can yield all of the updates buffered thus far
 				// and anything further, replacing FCCs with approval if any required it, or yielding them as is.
 				if requiresApproval && approvalRequiredFunctions == nil && len(functionCallContents) > 0 {
-					for tl := range agentopt.All(opts, agentopt.Tool) {
+					for tl := range agentopt.AllOptions(opts, agentopt.WithTool) {
 						if tl, ok := tl.(tool.ApprovalRequiredTool); ok {
 							approvalRequiredFunctions = append(approvalRequiredFunctions, tl)
 						}
@@ -298,16 +298,16 @@ func convertToolResultMsgToUpdate(msg *message.Message, msgID string) *message.R
 }
 
 func updateOptionsForNextIteration(opts []agentopt.Option) []agentopt.Option {
-	if v, ok := agentopt.Get(opts, agentopt.ToolMode); ok && v == tool.ToolModeRequired {
+	if v, ok := agentopt.GetOption(opts, agentopt.WithToolMode); ok && v == tool.ToolModeRequired {
 		// We have to reset the tool mode to be non-required after the first iteration,
 		// as otherwise we'll be in an infinite loop.
-		opts = append(opts, agentopt.ToolMode(tool.ToolModeAuto))
+		opts = append(opts, agentopt.WithToolMode(tool.ToolModeAuto))
 	}
 	// Reset the continuation token of a background response operation
 	// to signal the inner client to handle function call result rather
 	// than getting the result of the operation.
-	if _, ok := agentopt.Get(opts, agentopt.ContinuationToken); ok {
-		opts = append(opts, agentopt.ContinuationToken(""))
+	if _, ok := agentopt.GetOption(opts, agentopt.WithContinuationToken); ok {
+		opts = append(opts, agentopt.WithContinuationToken(""))
 	}
 	return opts
 }
diff --git a/middleware/contextprovider/contextprovider.go b/agent/internal/middleware/contextprovider/contextprovider.go
rename from middleware/contextprovider/contextprovider.go
rename to agent/internal/middleware/contextprovider/contextprovider.go
--- a/middleware/contextprovider/contextprovider.go
+++ b/agent/internal/middleware/contextprovider/contextprovider.go
@@ -7,10 +7,10 @@ import (
 	"iter"
 	"slices"
 
-	"github.com/microsoft/agent-framework-go/agentopt"
+	"github.com/microsoft/agent-framework-go/agent/internal/agentopt"
+	"github.com/microsoft/agent-framework-go/agent/internal/middleware"
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 )
 
 // New returns a middleware that invokes the provided context providers in order
@@ -33,12 +33,12 @@ type runner struct {
 }
 
 func (r *runner) Run(next middleware.RunFunc, ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
-	session, _ := agentopt.Get(options, agentopt.Session)
+	session, _ := agentopt.GetOption(options, agentopt.WithSession)
 
 	return func(yield func(*message.ResponseUpdate, error) bool) {
 		currentMessages := messages
 		providerMessages := make([]*message.Message, 0)
-		currentTools := slices.Collect(agentopt.All(options, agentopt.Tool))
+		currentTools := slices.Collect(agentopt.AllOptions(options, agentopt.WithTool))
 		runOptions := options
 		for _, provider := range r.providers {
 			providerContext, err := provider.BeforeRun(memory.BeforeRunContext{
@@ -61,7 +61,7 @@ func (r *runner) Run(next middleware.RunFunc, ctx context.Context, messages []*m
 			if len(providerContext.Tools) > 0 {
 				currentTools = append(currentTools, providerContext.Tools...)
 				for _, tool := range providerContext.Tools {
-					runOptions = append(runOptions, agentopt.Tool(tool))
+					runOptions = append(runOptions, agentopt.WithTool(tool))
 				}
 			}
 		}
diff --git a/middleware/middleware.go b/agent/internal/middleware/middleware.go
rename from middleware/middleware.go
rename to agent/internal/middleware/middleware.go
--- a/middleware/middleware.go
+++ b/agent/internal/middleware/middleware.go
@@ -6,7 +6,7 @@ import (
 	"context"
 	"iter"
 
-	"github.com/microsoft/agent-framework-go/agentopt"
+	"github.com/microsoft/agent-framework-go/agent/internal/agentopt"
 	"github.com/microsoft/agent-framework-go/message"
 )
 
@@ -16,12 +16,6 @@ type Middleware interface {
 	Run(next RunFunc, ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error]
 }
 
-type Func func(next RunFunc, ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error]
-
-func (mf Func) Run(next RunFunc, ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
-	return mf(next, ctx, messages, options...)
-}
-
 // RunChain applies the given middlewares around the given RunFunc.
 func RunChain(ctx context.Context, fn RunFunc, middlewares []Middleware, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	// Chain the middlewares together.
diff --git a/middleware/structuredoutput/structuredoutput.go b/agent/internal/middleware/structuredoutput/structuredoutput.go
rename from middleware/structuredoutput/structuredoutput.go
rename to agent/internal/middleware/structuredoutput/structuredoutput.go
--- a/middleware/structuredoutput/structuredoutput.go
+++ b/agent/internal/middleware/structuredoutput/structuredoutput.go
@@ -7,10 +7,10 @@ import (
 	"errors"
 	"iter"
 
-	"github.com/microsoft/agent-framework-go/agentopt"
+	"github.com/microsoft/agent-framework-go/agent/internal/agentopt"
+	"github.com/microsoft/agent-framework-go/agent/internal/middleware"
 	"github.com/microsoft/agent-framework-go/format"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 )
 
 type Config struct {
@@ -34,7 +34,7 @@ type so struct {
 
 func (a *so) Run(next middleware.RunFunc, ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	return func(yield func(*message.ResponseUpdate, error) bool) {
-		v, ok := agentopt.Get(options, agentopt.StructuredOutput)
+		v, ok := agentopt.GetOption(options, agentopt.WithStructuredOutput)
 		if !ok || v == nil {
 			// No structured output requested or nil value, just pass through.
 			for update, err := range next(ctx, messages, options...) {
@@ -53,7 +53,7 @@ func (a *so) Run(next middleware.RunFunc, ctx context.Context, messages []*messa
 			yield(nil, err)
 			return
 		}
-		options = append(options, agentopt.ResponseFormat(format))
+		options = append(options, agentopt.WithResponseFormat(format))
 		var data []byte
 		for update, err := range next(ctx, messages, options...) {
 			if err != nil {
diff --git a/agent/middleware.go b/agent/middleware.go
new file mode 100644
--- /dev/null
+++ b/agent/middleware.go
@@ -0,0 +1,42 @@
+// Copyright (c) Microsoft. All rights reserved.
+
+package agent
+
+import (
+	"context"
+	"iter"
+
+	"github.com/microsoft/agent-framework-go/message"
+)
+
+type Middleware interface {
+	Run(next RunFunc, ctx context.Context, messages []*message.Message, options ...Option) iter.Seq2[*message.ResponseUpdate, error]
+}
+
+type MiddlewareFunc func(next RunFunc, ctx context.Context, messages []*message.Message, options ...Option) iter.Seq2[*message.ResponseUpdate, error]
+
+func (mf MiddlewareFunc) Run(next RunFunc, ctx context.Context, messages []*message.Message, options ...Option) iter.Seq2[*message.ResponseUpdate, error] {
+	return mf(next, ctx, messages, options...)
+}
+
+// runChain applies the given middlewares around the given RunFunc.
+func runChain(ctx context.Context, fn RunFunc, middlewares []Middleware, messages []*message.Message, options ...Option) iter.Seq2[*message.ResponseUpdate, error] {
+	// Chain the middlewares together.
+	for i := len(middlewares) - 1; i >= 0; i-- {
+		mw := middlewares[i]
+		fn = middlewareRunner{
+			Middleware: mw,
+			next:       fn,
+		}.Run
+	}
+	return fn(ctx, messages, options...)
+}
+
+type middlewareRunner struct {
+	Middleware
+	next RunFunc
+}
+
+func (mr middlewareRunner) Run(ctx context.Context, messages []*message.Message, opts ...Option) iter.Seq2[*message.ResponseUpdate, error] {
+	return mr.Middleware.Run(mr.next, ctx, messages, opts...)
+}
diff --git a/agent/middleware/autocall/autocall.go b/agent/middleware/autocall/autocall.go
new file mode 100644
--- /dev/null
+++ b/agent/middleware/autocall/autocall.go
@@ -0,0 +1,28 @@
+// Copyright (c) Microsoft. All rights reserved.
+
+package autocall
+
+import (
+	"log/slog"
+
+	"github.com/microsoft/agent-framework-go/agent"
+	"github.com/microsoft/agent-framework-go/agent/internal/middleware/autocall"
+	"github.com/microsoft/agent-framework-go/tool"
+)
+
+type Config struct {
+	Logger                             *slog.Logger
+	LogSensitiveData                   bool
+	AdditionalTools                    []tool.Tool
+	IncludeDetailedErrors              bool
+	TerminateOnUnknownCalls            bool
+	AllowConcurrentInvocations         bool
+	MaximumConsecutiveErrorsPerRequest int
+	MaximumIterationsPerRequest        int // Default: 40
+	NewID                              func() string
+}
+
+// New creates a new function-invoking chat client that wraps the provided client.
+func New(cfg Config) agent.Middleware {
+	return autocall.New(autocall.Config(cfg))
+}
diff --git a/agent/middleware/contextprovider/contextprovider.go b/agent/middleware/contextprovider/contextprovider.go
new file mode 100644
--- /dev/null
+++ b/agent/middleware/contextprovider/contextprovider.go
@@ -0,0 +1,15 @@
+// Copyright (c) Microsoft. All rights reserved.
+
+package contextprovider
+
+import (
+	"github.com/microsoft/agent-framework-go/agent"
+	"github.com/microsoft/agent-framework-go/agent/internal/middleware/contextprovider"
+	"github.com/microsoft/agent-framework-go/memory"
+)
+
+// New returns a middleware that invokes the provided context providers in order
+// before the wrapped run and persists them in reverse order after the run.
+func New(providers ...*memory.ContextProvider) agent.Middleware {
+	return contextprovider.New(providers...)
+}
diff --git a/middleware/logger/logger.go b/agent/middleware/logger/logger.go
rename from middleware/logger/logger.go
rename to agent/middleware/logger/logger.go
--- a/middleware/logger/logger.go
+++ b/agent/middleware/logger/logger.go
@@ -10,18 +10,16 @@ import (
 	"time"
 
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/internal/slogx"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 )
 
 type Config struct {
 	Logger        *slog.Logger
 	SensitiveData bool
 }
 
-func New(cfg Config) middleware.Middleware {
+func New(cfg Config) agent.Middleware {
 	return &logger{l: slogx.Logger{
 		Logger:        cfg.Logger,
 		SensitiveData: cfg.SensitiveData,
@@ -34,7 +32,7 @@ type logger struct {
 	l slogx.Logger
 }
 
-func (l *logger) Run(next middleware.RunFunc, ctx context.Context, messages []*message.Message, opts ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (l *logger) Run(next agent.RunFunc, ctx context.Context, messages []*message.Message, opts ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	return func(yield func(*message.ResponseUpdate, error) bool) {
 		start := time.Now()
 		l.log(ctx, slog.LevelDebug, "run invoked", slogx.SensitiveData("messages", messages), slogx.SensitiveData("opts", opts))
diff --git a/middleware/otel/otel.go b/agent/middleware/otel/otel.go
rename from middleware/otel/otel.go
rename to agent/middleware/otel/otel.go
--- a/middleware/otel/otel.go
+++ b/agent/middleware/otel/otel.go
@@ -9,9 +9,7 @@ import (
 	"time"
 
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 
 	"go.opentelemetry.io/otel"
 	"go.opentelemetry.io/otel/attribute"
@@ -25,7 +23,7 @@ type Config struct {
 }
 
 // New creates a new middleware that adds OpenTelemetry tracing to agent runs.
-func New(cfg Config) middleware.Middleware {
+func New(cfg Config) agent.Middleware {
 	tracer := otel.Tracer(cmp.Or(cfg.SourceName, "github.com/microsoft/agent-framework-go"))
 	return &mw{
 		tracer: tracer,
@@ -46,7 +44,7 @@ type mw struct {
 	tracer trace.Tracer
 }
 
-func (m *mw) Run(next middleware.RunFunc, ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (m *mw) Run(next agent.RunFunc, ctx context.Context, messages []*message.Message, options ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	return func(yield func(*message.ResponseUpdate, error) bool) {
 		a, _ := agent.AgentFromContext(ctx)
 		ctx, span := m.tracer.Start(ctx, a.Name(), trace.WithAttributes(
diff --git a/agent/middleware/structuredoutput/structuredoutput.go b/agent/middleware/structuredoutput/structuredoutput.go
new file mode 100644
--- /dev/null
+++ b/agent/middleware/structuredoutput/structuredoutput.go
@@ -0,0 +1,18 @@
+// Copyright (c) Microsoft. All rights reserved.
+
+package structuredoutput
+
+import (
+	"github.com/microsoft/agent-framework-go/agent"
+	"github.com/microsoft/agent-framework-go/agent/internal/middleware/structuredoutput"
+	"github.com/microsoft/agent-framework-go/format"
+)
+
+type Config struct {
+	Format    func(v any) (format.Format, error)
+	Unmarshal func(format format.Format, data []byte, v any) error
+}
+
+func New(cfg Config) agent.Middleware {
+	return structuredoutput.New(structuredoutput.Config(cfg))
+}
diff --git a/agent/options.go b/agent/options.go
new file mode 100644
--- /dev/null
+++ b/agent/options.go
@@ -0,0 +1,108 @@
+// Copyright (c) Microsoft. All rights reserved.
+
+package agent
+
+import (
+	"iter"
+
+	"github.com/microsoft/agent-framework-go/agent/internal/agentopt"
+	"github.com/microsoft/agent-framework-go/format"
+	"github.com/microsoft/agent-framework-go/memory"
+	"github.com/microsoft/agent-framework-go/tool"
+)
+
+// An Option is a configuration option for an Agent.
+//
+// Each option must be implemented as its own distinct type.
+// [GetOption] and [AllOptions] use the option's type
+// to uniquely identify each option.
+type Option = agentopt.Option
+
+// GetOption returns the value stored in opts with the provided setter,
+// reporting whether the value is present.
+//
+// Example usage:
+//
+//	v, ok := agent.GetOption(opts, agent.WithSession)
+func GetOption[T any](opts []Option, setter func(T) Option) (T, bool) {
+	return agentopt.GetOption(opts, setter)
+}
+
+// AllOptions returns a sequence of all values of type T stored in opts with the provided setter.
+//
+// Example usage:
+//
+//	for v := range agent.AllOptions(opts, agent.WithSession) {
+//	   // do something with v of type T
+//	}
+func AllOptions[T any](opts []Option, setter func(T) Option) iter.Seq[T] {
+	return agentopt.AllOptions(opts, setter)
+}
+
+// WithServiceID sets the service ID for a session.
+func WithServiceID(id string) Option {
+	return agentopt.WithServiceID(id)
+}
+
+// WithStructuredOutput sets the variable pointed to by v to the structured output produced by the agent.
+func WithStructuredOutput(v any) Option {
+	return agentopt.WithStructuredOutput(v)
+}
+
+// WithTool adds a tool to the agent run.
+func WithTool(tool tool.Tool) Option {
+	return agentopt.WithTool(tool)
+}
+
+// WithToolMode sets the tool mode for the agent run.
+func WithToolMode(mode tool.ToolMode) Option {
+	return agentopt.WithToolMode(mode)
+}
+
+// Stream sets whether to use streaming responses during the agent run.
+func Stream(stream bool) Option {
+	return agentopt.Stream(stream)
+}
+
+// WithResponseFormat sets the desired response format for the agent run.
+func WithResponseFormat(format format.Format) Option {
+	return agentopt.WithResponseFormat(format)
+}
+
+// WithSession sets the session to use during the agent run.
+func WithSession(session *memory.Session) Option {
+	return agentopt.WithSession(session)
+}
+
+// WithContinuationToken sets the continuation token for resuming and getting the result
+// of the agent response identified by this token.
+//
+// This token is used for background responses that can be activated via [AllowBackgroundResponses]
+// if the agent supports them. Streamed background responses, such as those returned by default by [RunStream],
+// can be resumed if interrupted. This means that a continuation token obtained from the [RunResponseUpdate] continuation token
+// of an update just before the interruption occurred can be passed to this function to resume the stream from
+// the point of interruption. Non-streamed background responses, such as those returned by [Run], can be polled for
+// completion by obtaining the token from the [RunResponse] continuation token.
+func WithContinuationToken(token string) Option {
+	return agentopt.WithContinuationToken(token)
+}
+
+// AllowBackgroundResponses sets whether to allow background responses during the agent run.
+//
+// Background responses allow running long-running operations or tasks asynchronously in the background that can be resumed
+// by streaming APIs and polled for completion by non-streaming APIs.
+//
+// When this property is set to true, non-streaming APIs may start a background operation and return an initial
+// response with a continuation token. Subsequent calls to the same API should be made in a polling manner with
+// the continuation token to get the final result of the operation.
+//
+// When this property is set to true, streaming APIs may also start a background operation and begin streaming
+// response updates until the operation is completed. If the streaming connection is interrupted, the
+// continuation token obtained from the last update that has one should be supplied to a subsequent call to the same streaming API
+// to resume the stream from the point of interruption and continue receiving updates until the operation is completed.
+//
+// This property only takes effect if the implementation it's used with supports background responses.
+// If the implementation does not support background responses, this property will be ignored.
+func AllowBackgroundResponses(allow bool) Option {
+	return agentopt.AllowBackgroundResponses(allow)
+}
diff --git a/agent/provider/a2aagent/a2a.go b/agent/provider/a2aagent/a2a.go
--- a/agent/provider/a2aagent/a2a.go
+++ b/agent/provider/a2aagent/a2a.go
@@ -17,7 +17,6 @@ import (
 	"github.com/a2aproject/a2a-go/v2/a2a"
 	"github.com/a2aproject/a2a-go/v2/a2aclient"
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/message"
 )
@@ -30,7 +29,7 @@ type taskIDOpt struct{ string }
 
 func (o taskIDOpt) Value() any { return o.string }
 
-func TaskID(taskID string) agentopt.Option {
+func TaskID(taskID string) agent.Option {
 	return taskIDOpt{taskID}
 }
 
@@ -55,19 +54,19 @@ func New(aclient *a2aclient.Client, config Config) *agent.Agent {
 	}, config.Config)
 }
 
-func (a *a2aagent) createSession(ctx context.Context, options ...agentopt.Option) (*memory.Session, error) {
-	serviceID, _ := agentopt.Get(options, agentopt.ServiceID)
+func (a *a2aagent) createSession(ctx context.Context, options ...agent.Option) (*memory.Session, error) {
+	serviceID, _ := agent.GetOption(options, agent.WithServiceID)
 	session := memory.NewSession("")
 	setContextID(session, serviceID)
-	setTaskIDs(session, slices.Collect(agentopt.All(options, TaskID)))
+	setTaskIDs(session, slices.Collect(agent.AllOptions(options, TaskID)))
 	return session, nil
 }
 
-func (a *a2aagent) run(ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (a *a2aagent) run(ctx context.Context, messages []*message.Message, options ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	return func(yield func(*message.ResponseUpdate, error) bool) {
-		session, _ := agentopt.Get(options, agentopt.Session)
-		stream, _ := agentopt.Get(options, agentopt.Stream)
-		if token, ok := agentopt.Get(options, agentopt.ContinuationToken); ok && token != "" {
+		session, _ := agent.GetOption(options, agent.WithSession)
+		stream, _ := agent.GetOption(options, agent.Stream)
+		if token, ok := agent.GetOption(options, agent.WithContinuationToken); ok && token != "" {
 			if stream {
 				// TODO: support resuming stream responses using continuation tokens.
 				yield(nil, errors.New("reconnecting to task streams using continuation tokens is not supported yet"))
diff --git a/agent/provider/aguiagent/agui.go b/agent/provider/aguiagent/agui.go
--- a/agent/provider/aguiagent/agui.go
+++ b/agent/provider/aguiagent/agui.go
@@ -16,7 +16,6 @@ import (
 	aguiEvents "github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/core/events"
 	aguiTypes "github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/core/types"
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/message"
 	"github.com/microsoft/agent-framework-go/tool"
@@ -50,9 +49,9 @@ func New(aclient *aguiSSEClient.Client, config Config) *agent.Agent {
 	}, config.Config)
 }
 
-func (p *provider) run(ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (p *provider) run(ctx context.Context, messages []*message.Message, options ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	return func(yield func(*message.ResponseUpdate, error) bool) {
-		session, _ := agentopt.Get(options, agentopt.Session)
+		session, _ := agent.GetOption(options, agent.WithSession)
 		threadID := getOrCreateThreadID(session)
 		runID := aguiEvents.GenerateRunID()
 
@@ -67,7 +66,7 @@ func (p *provider) run(ctx context.Context, messages []*message.Message, options
 			RunID:          runID,
 			State:          state,
 			Messages:       convertedMessages,
-			Tools:          toAGUITools(agentopt.All(options, agentopt.Tool)),
+			Tools:          toAGUITools(agent.AllOptions(options, agent.WithTool)),
 			Context:        []aguiTypes.Context{},
 			ForwardedProps: map[string]any{},
 		}
diff --git a/agent/provider/anthropicagent/agent.go b/agent/provider/anthropicagent/agent.go
--- a/agent/provider/anthropicagent/agent.go
+++ b/agent/provider/anthropicagent/agent.go
@@ -15,7 +15,6 @@ import (
 
 	"github.com/anthropics/anthropic-sdk-go"
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/format"
 	"github.com/microsoft/agent-framework-go/format/jsonformat"
 	"github.com/microsoft/agent-framework-go/message"
@@ -27,7 +26,7 @@ type messageNewParamsOpt anthropic.MessageNewParams
 func (o messageNewParamsOpt) Value() any { return anthropic.MessageNewParams(o) }
 
 // MessageNewParams allows passing custom parameters to the underlying anthropic API calls.
-func MessageNewParams(params anthropic.MessageNewParams) agentopt.Option {
+func MessageNewParams(params anthropic.MessageNewParams) agent.Option {
 	return messageNewParamsOpt(params)
 }
 
@@ -64,14 +63,14 @@ func (a *client) unmarshal(f format.Format, data []byte, v any) error {
 	return jsonformat.Unmarshal(f.(*jsonformat.Format), data, v)
 }
 
-func (a *client) run(ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (a *client) run(ctx context.Context, messages []*message.Message, options ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	params, err := a.buildMessageParams(messages, options)
 	if err != nil {
 		return func(yield func(*message.ResponseUpdate, error) bool) {
 			yield(nil, err)
 		}
 	}
-	if stream, _ := agentopt.Get(options, agentopt.Stream); !stream {
+	if stream, _ := agent.GetOption(options, agent.Stream); !stream {
 		resp, err := a.client.Messages.New(ctx, params)
 		if err != nil {
 			return func(yield func(*message.ResponseUpdate, error) bool) {
@@ -252,16 +251,16 @@ func (a *client) buildDelta(index int, v any, contents []message.Content, functi
 	return contents
 }
 
-func (a *client) buildMessageParams(messages []*message.Message, opts []agentopt.Option) (anthropic.MessageNewParams, error) {
+func (a *client) buildMessageParams(messages []*message.Message, opts []agent.Option) (anthropic.MessageNewParams, error) {
 	var params anthropic.MessageNewParams
-	if p, ok := agentopt.Get(opts, MessageNewParams); ok {
+	if p, ok := agent.GetOption(opts, MessageNewParams); ok {
 		params = p
 	}
 	params.Model = cmp.Or(params.Model, anthropic.Model(a.config.Model))
 	params.MaxTokens = cmp.Or(params.MaxTokens, 4096)
 
 	var tools []anthropic.ToolUnionParam
-	for tl := range agentopt.All(opts, agentopt.Tool) {
+	for tl := range agent.AllOptions(opts, agent.WithTool) {
 		if ft, ok := tl.(tool.FuncTool); ok {
 			name, description := ft.Name(), ft.Description()
 			var properties any
@@ -317,7 +316,7 @@ func (a *client) buildMessageParams(messages []*message.Message, opts []agentopt
 		params.Tools = tools
 	}
 
-	if mode, ok := agentopt.Get(opts, agentopt.ToolMode); ok {
+	if mode, ok := agent.GetOption(opts, agent.WithToolMode); ok {
 		switch mode.Mode() {
 		case tool.ToolModeAuto, "":
 			params.ToolChoice = anthropic.ToolChoiceUnionParam{
@@ -340,7 +339,7 @@ func (a *client) buildMessageParams(messages []*message.Message, opts []agentopt
 		}
 	}
 
-	if frmt, ok := agentopt.Get(opts, agentopt.ResponseFormat); ok && frmt != nil {
+	if frmt, ok := agent.GetOption(opts, agent.WithResponseFormat); ok && frmt != nil {
 		if frmt.Kind() == "json" {
 			if schemaFmt, ok := frmt.(format.SchemaFormat); ok {
 				var schemaMap map[string]any
diff --git a/agent/provider/geminiagent/agent.go b/agent/provider/geminiagent/agent.go
--- a/agent/provider/geminiagent/agent.go
+++ b/agent/provider/geminiagent/agent.go
@@ -12,7 +12,6 @@ import (
 	"time"
 
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/format"
 	"github.com/microsoft/agent-framework-go/format/jsonformat"
 	"github.com/microsoft/agent-framework-go/message"
@@ -25,7 +24,7 @@ type generateContentConfigOpt genai.GenerateContentConfig
 func (o generateContentConfigOpt) Value() any { return genai.GenerateContentConfig(o) }
 
 // GenerateContentConfig allows passing custom parameters to the underlying genai API calls.
-func GenerateContentConfig(config genai.GenerateContentConfig) agentopt.Option {
+func GenerateContentConfig(config genai.GenerateContentConfig) agent.Option {
 	return generateContentConfigOpt(config)
 }
 
@@ -63,15 +62,15 @@ func (a *client) unmarshal(f format.Format, data []byte, v any) error {
 	return jsonformat.Unmarshal(f.(*jsonformat.Format), data, v)
 }
 
-func (a *client) run(ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (a *client) run(ctx context.Context, messages []*message.Message, options ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	contents, cfg, err := a.buildParams(messages, options)
 	if err != nil {
 		return func(yield func(*message.ResponseUpdate, error) bool) {
 			yield(nil, err)
 		}
 	}
 
-	if stream, _ := agentopt.Get(options, agentopt.Stream); !stream {
+	if stream, _ := agent.GetOption(options, agent.Stream); !stream {
 		resp, err := a.client.Models.GenerateContent(ctx, a.config.Model, contents, cfg)
 		if err != nil {
 			return func(yield func(*message.ResponseUpdate, error) bool) {
@@ -144,9 +143,9 @@ func (a *client) run(ctx context.Context, messages []*message.Message, options .
 }
 
 // buildParams converts framework messages and options into genai API parameters.
-func (a *client) buildParams(messages []*message.Message, opts []agentopt.Option) ([]*genai.Content, *genai.GenerateContentConfig, error) {
+func (a *client) buildParams(messages []*message.Message, opts []agent.Option) ([]*genai.Content, *genai.GenerateContentConfig, error) {
 	cfg := &genai.GenerateContentConfig{}
-	if p, ok := agentopt.Get(opts, GenerateContentConfig); ok {
+	if p, ok := agent.GetOption(opts, GenerateContentConfig); ok {
 		*cfg = p
 		// Clone mutable slice fields so that appending to cfg.Tools or
 		// cfg.SystemInstruction.Parts below never aliases the caller's
@@ -161,7 +160,7 @@ func (a *client) buildParams(messages []*message.Message, opts []agentopt.Option
 
 	// Collect tools from options.
 	var funcDecls []*genai.FunctionDeclaration
-	for tl := range agentopt.All(opts, agentopt.Tool) {
+	for tl := range agent.AllOptions(opts, agent.WithTool) {
 		if ft, ok := tl.(tool.FuncTool); ok {
 			decl := &genai.FunctionDeclaration{
 				Name:        ft.Name(),
@@ -181,7 +180,7 @@ func (a *client) buildParams(messages []*message.Message, opts []agentopt.Option
 	}
 
 	// Apply structured output format.
-	if frmt, ok := agentopt.Get(opts, agentopt.ResponseFormat); ok && frmt != nil {
+	if frmt, ok := agent.GetOption(opts, agent.WithResponseFormat); ok && frmt != nil {
 		if frmt.Kind() == "json" {
 			cfg.ResponseMIMEType = "application/json"
 			if schemaFmt, ok := frmt.(format.SchemaFormat); ok {
@@ -193,7 +192,7 @@ func (a *client) buildParams(messages []*message.Message, opts []agentopt.Option
 	}
 
 	// Apply tool mode.
-	if mode, ok := agentopt.Get(opts, agentopt.ToolMode); ok && len(funcDecls) > 0 {
+	if mode, ok := agent.GetOption(opts, agent.WithToolMode); ok && len(funcDecls) > 0 {
 		fc := &genai.FunctionCallingConfig{}
 		switch mode.Mode() {
 		case tool.ToolModeAuto, "":
diff --git a/agent/provider/openaichatagent/chat.go b/agent/provider/openaichatagent/chat.go
--- a/agent/provider/openaichatagent/chat.go
+++ b/agent/provider/openaichatagent/chat.go
@@ -12,7 +12,6 @@ import (
 	"time"
 
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/format"
 	"github.com/microsoft/agent-framework-go/format/jsonformat"
 	"github.com/microsoft/agent-framework-go/message"
@@ -34,7 +33,7 @@ func (o chatCompletionNewParamsOpt) Value() any {
 }
 
 // ChatCompletionNewParams allows passing custom parameters to the underlying OpenAI Chat Completions API calls.
-func ChatCompletionNewParams(params openai.ChatCompletionNewParams) agentopt.Option {
+func ChatCompletionNewParams(params openai.ChatCompletionNewParams) agent.Option {
 	return chatCompletionNewParamsOpt(params)
 }
 
@@ -66,14 +65,14 @@ func (a *client) unmarshal(format format.Format, data []byte, v any) error {
 	return jsonformat.Unmarshal(format.(*jsonformat.Format), data, v)
 }
 
-func (a *client) run(ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (a *client) run(ctx context.Context, messages []*message.Message, options ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	body, err := buildCompletionParams(a.config.Model, messages, options)
 	if err != nil {
 		return func(yield func(*message.ResponseUpdate, error) bool) {
 			yield(nil, err)
 		}
 	}
-	if stream, _ := agentopt.Get(options, agentopt.Stream); !stream {
+	if stream, _ := agent.GetOption(options, agent.Stream); !stream {
 		resp, err := a.client.Chat.Completions.New(ctx, body)
 		if err != nil {
 			return func(yield func(*message.ResponseUpdate, error) bool) {
@@ -172,13 +171,13 @@ func mapRole(r string) message.Role {
 }
 
 // buildCompletionParams constructs the parameters for the OpenAI chat completion API.
-func buildCompletionParams(model string, messages []*message.Message, opts []agentopt.Option) (openai.ChatCompletionNewParams, error) {
+func buildCompletionParams(model string, messages []*message.Message, opts []agent.Option) (openai.ChatCompletionNewParams, error) {
 	var params openai.ChatCompletionNewParams
-	if p, ok := agentopt.Get(opts, ChatCompletionNewParams); ok {
+	if p, ok := agent.GetOption(opts, ChatCompletionNewParams); ok {
 		params = p
 	}
 	params.Model = cmp.Or(params.Model, model)
-	if frmt, ok := agentopt.Get(opts, agentopt.ResponseFormat); ok && frmt != nil {
+	if frmt, ok := agent.GetOption(opts, agent.WithResponseFormat); ok && frmt != nil {
 		switch frmt.Kind() {
 		case "json":
 			if schema, ok := frmt.(format.SchemaFormat); ok {
@@ -202,10 +201,10 @@ func buildCompletionParams(model string, messages []*message.Message, opts []age
 		}
 	}
 	first := true
-	for tl := range agentopt.All(opts, agentopt.Tool) {
+	for tl := range agent.AllOptions(opts, agent.WithTool) {
 		if first {
 			first = false
-			if mode, ok := agentopt.Get(opts, agentopt.ToolMode); ok {
+			if mode, ok := agent.GetOption(opts, agent.WithToolMode); ok {
 				switch mode.Mode() {
 				case tool.ToolModeAuto, "":
 					params.ToolChoice = openai.ChatCompletionToolChoiceOptionUnionParam{
diff --git a/agent/provider/openairesponsesagent/responses.go b/agent/provider/openairesponsesagent/responses.go
--- a/agent/provider/openairesponsesagent/responses.go
+++ b/agent/provider/openairesponsesagent/responses.go
@@ -17,7 +17,6 @@ import (
 	"time"
 
 	"github.com/microsoft/agent-framework-go/agent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/format"
 	"github.com/microsoft/agent-framework-go/format/jsonformat"
 	"github.com/microsoft/agent-framework-go/memory"
@@ -63,7 +62,7 @@ func (o responsesNewParamsOpt) Value() any {
 }
 
 // ResponsesNewParams allows passing custom parameters to the underlying OpenAI Responses API calls.
-func ResponsesNewParams(params responses.ResponseNewParams) agentopt.Option {
+func ResponsesNewParams(params responses.ResponseNewParams) agent.Option {
 	return responsesNewParamsOpt(params)
 }
 
@@ -75,14 +74,14 @@ func (a *responsesClient) unmarshal(format format.Format, data []byte, v any) er
 	return jsonformat.Unmarshal(format.(*jsonformat.Format), data, v)
 }
 
-func (a *responsesClient) run(ctx context.Context, messages []*message.Message, options ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (a *responsesClient) run(ctx context.Context, messages []*message.Message, options ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	return func(yield func(*message.ResponseUpdate, error) bool) {
-		stream, _ := agentopt.Get(options, agentopt.Stream)
+		stream, _ := agent.GetOption(options, agent.Stream)
 
 		// Get session for conversation ID management
 		var session *memory.Session
 		var keepConversationID bool // true if we should keep the conversation ID unchanged (it's a "conv_" ID)
-		if t, ok := agentopt.Get(options, agentopt.Session); ok && t != nil {
+		if t, ok := agent.GetOption(options, agent.WithSession); ok && t != nil {
 			session = t
 			keepConversationID = session.ServiceID != "" && strings.HasPrefix(session.ServiceID, "conv_")
 		}
@@ -95,7 +94,7 @@ func (a *responsesClient) run(ctx context.Context, messages []*message.Message,
 		}
 
 		// Handle continuation token for resuming background responses
-		if token, ok := agentopt.Get(options, agentopt.ContinuationToken); ok && token != "" {
+		if token, ok := agent.GetOption(options, agent.WithContinuationToken); ok && token != "" {
 			if len(messages) > 0 {
 				yield(nil, errors.New("messages are not allowed when continuing a background response using a continuation token"))
 				return
@@ -154,7 +153,7 @@ func (a *responsesClient) run(ctx context.Context, messages []*message.Message,
 			streamResp := a.client.Responses.NewStreaming(ctx, body)
 			responseID := ""
 			createdAt := time.Time{}
-			isBackground, _ := agentopt.Get(options, agentopt.AllowBackgroundResponses)
+			isBackground, _ := agent.GetOption(options, agent.AllowBackgroundResponses)
 			for streamResp.Next() {
 				update, err := responsesProcessStreamingUpdate(streamResp.Current(), responseID, isBackground)
 				if err != nil {
@@ -201,16 +200,16 @@ func (a *responsesClient) run(ctx context.Context, messages []*message.Message,
 }
 
 // buildCompletionParams constructs the parameters for the OpenAI chat completion API.
-func responsesBuildCompletionParams(model string, messages []*message.Message, opts []agentopt.Option) (responses.ResponseNewParams, error) {
+func responsesBuildCompletionParams(model string, messages []*message.Message, opts []agent.Option) (responses.ResponseNewParams, error) {
 	var params responses.ResponseNewParams
-	if p, ok := agentopt.Get(opts, ResponsesNewParams); ok {
+	if p, ok := agent.GetOption(opts, ResponsesNewParams); ok {
 		params = p
 	}
 	params.Model = cmp.Or(params.Model, model)
-	if v, ok := agentopt.Get(opts, agentopt.AllowBackgroundResponses); ok {
+	if v, ok := agent.GetOption(opts, agent.AllowBackgroundResponses); ok {
 		params.Background = openai.Bool(v)
 	}
-	if session, ok := agentopt.Get(opts, agentopt.Session); ok && session != nil {
+	if session, ok := agent.GetOption(opts, agent.WithSession); ok && session != nil {
 		if session.ServiceID != "" {
 			// Technically, OpenAI's IDs are opaque. However, by convention conversation IDs start with "conv_" and
 			// we can use that to disambiguate whether we're looking at a conversation ID or a response ID.
@@ -224,7 +223,7 @@ func responsesBuildCompletionParams(model string, messages []*message.Message, o
 		}
 	}
 
-	if frmt, ok := agentopt.Get(opts, agentopt.ResponseFormat); ok && frmt != nil {
+	if frmt, ok := agent.GetOption(opts, agent.WithResponseFormat); ok && frmt != nil {
 		switch frmt.Kind() {
 		case "json":
 			if schema, ok := frmt.(format.SchemaFormat); ok {
@@ -246,10 +245,10 @@ func responsesBuildCompletionParams(model string, messages []*message.Message, o
 		}
 	}
 	first := true
-	for tl := range agentopt.All(opts, agentopt.Tool) {
+	for tl := range agent.AllOptions(opts, agent.WithTool) {
 		if first {
 			first = false
-			if mode, ok := agentopt.Get(opts, agentopt.ToolMode); ok {
+			if mode, ok := agent.GetOption(opts, agent.WithToolMode); ok {
 				switch mode.Mode() {
 				case tool.ToolModeAuto, "":
 					params.ToolChoice = responses.ResponseNewParamsToolChoiceUnion{
diff --git a/agent/tool.go b/agent/tool.go
--- a/agent/tool.go
+++ b/agent/tool.go
@@ -4,13 +4,11 @@ package agent
 
 import (
 	"encoding/json"
-
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/tool"
 )
 
 // AsFuncTool creates a function tool that invokes the given agent.
-func (a *Agent) AsFuncTool(options ...agentopt.Option) tool.FuncTool {
+func (a *Agent) AsFuncTool(options ...Option) tool.FuncTool {
 	return functool{
 		name:        a.Name(),
 		description: a.Description(),
@@ -22,7 +20,7 @@ func (a *Agent) AsFuncTool(options ...agentopt.Option) tool.FuncTool {
 type functool struct {
 	name        string
 	description string
-	opts        []agentopt.Option
+	opts        []Option
 	agent       *Agent
 }
 
diff --git a/agent/workflow.go b/agent/workflow.go
--- a/agent/workflow.go
+++ b/agent/workflow.go
@@ -4,13 +4,11 @@ package agent
 
 import (
 	"context"
-	"reflect"
-
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/message"
 	"github.com/microsoft/agent-framework-go/message/messageworkflow"
 	"github.com/microsoft/agent-framework-go/workflow"
+	"reflect"
 )
 
 func newExecutor(a *Agent, emitEvents bool) *workflow.Executor {
@@ -60,14 +58,14 @@ func newExecutor(a *Agent, emitEvents bool) *workflow.Executor {
 		StateKey: "agent_messages",
 		TakeTurnHandler: func(ctx *workflow.Context, token workflow.TurnToken, messages []*message.Message) error {
 			emitEvents := token.EmitEventsOr(emitEvents)
-			options := make([]agentopt.Option, 0, 1+len(messages))
+			options := make([]Option, 0, 1+len(messages))
 			session, err := ensureSession(ctx)
 			if err != nil {
 				return err
 			}
-			options = append(options, agentopt.Session(session))
+			options = append(options, WithSession(session))
 			// Run the agent in streaming mode only when agent run update events are to be emitted.
-			options = append(options, agentopt.Stream(emitEvents))
+			options = append(options, Stream(emitEvents))
 			var updates []*message.ResponseUpdate
 			for update, err := range a.Run(ctx, messages, options...) {
 				if err != nil {
diff --git a/agentopt/agentopt.go b/agentopt/agentopt.go
deleted file mode 100644
--- a/agentopt/agentopt.go
+++ /dev/null
@@ -1,167 +0,0 @@
-// Copyright (c) Microsoft. All rights reserved.
-
-package agentopt
-
-import (
-	"iter"
-	"reflect"
-	"slices"
-
-	"github.com/microsoft/agent-framework-go/format"
-	"github.com/microsoft/agent-framework-go/memory"
-	"github.com/microsoft/agent-framework-go/tool"
-)
-
-// An Option is a configuration option for an Agent.
-//
-// Each option must be implemented as its own distinct type.
-// [Get] and [All] use the option's type
-// to uniquely identify each option.
-type Option interface {
-	Value() any
-}
-
-type serviceIDOpt struct{ string }
-
-func (o serviceIDOpt) Value() any { return o.string }
-
-func ServiceID(id string) Option {
-	return serviceIDOpt{id}
-}
-
-type (
-	responseFormatOpt    struct{ format.Format }
-	sessionOpt           struct{ *memory.Session }
-	continuationTokenOpt string
-
-	toolOpt struct{ tool.Tool }
-
-	toolModeOpt                 tool.ToolMode
-	streamOpt                   bool
-	allowBackgroundResponsesOpt bool
-
-	structuredOutputOpt struct{ any }
-)
-
-func (o responseFormatOpt) Value() any           { return o.Format }
-func (o sessionOpt) Value() any                  { return o.Session }
-func (o streamOpt) Value() any                   { return bool(o) }
-func (o continuationTokenOpt) Value() any        { return string(o) }
-func (o allowBackgroundResponsesOpt) Value() any { return bool(o) }
-func (o toolModeOpt) Value() any                 { return tool.ToolMode(o) }
-func (o toolOpt) Value() any                     { return o.Tool }
-func (o structuredOutputOpt) Value() any         { return o.any }
-
-func StructuredOutput(v any) Option {
-	return structuredOutputOpt{v}
-}
-
-// Tool adds a tool to the agent run.
-func Tool(tool tool.Tool) Option {
-	return toolOpt{tool}
-}
-
-// ToolMode sets the tool mode for the agent run.
-func ToolMode(mode tool.ToolMode) Option {
-	return toolModeOpt(mode)
-}
-
-// Stream sets whether to use streaming responses during the agent run.
-func Stream(stream bool) Option {
-	return streamOpt(stream)
-}
-
-// ResponseFormat sets the desired response format for the agent run.
-func ResponseFormat(format format.Format) Option {
-	return responseFormatOpt{format}
-}
-
-// Session sets the session to use during the agent run.
-func Session(session *memory.Session) Option {
-	return sessionOpt{session}
-}
-
-// ContinuationToken sets the continuation token for resuming and getting the result
-// of the agent response identified by this token.
-//
-// This token is used for background responses that can be activated via [AllowBackgroundResponses]
-// if the agent supports them. Streamed background responses, such as those returned by default by [RunStream],
-// can be resumed if interrupted. This means that a continuation token obtained from the [RunResponseUpdate] continuation token
-// of an update just before the interruption occurred can be passed to this function to resume the stream from
-// the point of interruption. Non-streamed background responses, such as those returned by [Run], can be polled for
-// completion by obtaining the token from the [RunResponse] continuation token.
-func ContinuationToken(token string) Option {
-	return continuationTokenOpt(token)
-}
-
-// AllowBackgroundResponses sets whether to allow background responses during the agent run.
-//
-// Background responses allow running long-running operations or tasks asynchronously in the background that can be resumed
-// by streaming APIs and polled for completion by non-streaming APIs.
-//
-// When this property is set to true, non-streaming APIs may start a background operation and return an initial
-// response with a continuation token. Subsequent calls to the same API should be made in a polling manner with
-// the continuation token to get the final result of the operation.
-//
-// When this property is set to true, streaming APIs may also start a background operation and begin streaming
-// response updates until the operation is completed. If the streaming connection is interrupted, the
-// continuation token obtained from the last update that has one should be supplied to a subsequent call to the same streaming API
-// to resume the stream from the point of interruption and continue receiving updates until the operation is completed.
-//
-// This property only takes effect if the implementation it's used with supports background responses.
-// If the implementation does not support background responses, this property will be ignored.
-func AllowBackgroundResponses(allow bool) Option {
-	return allowBackgroundResponsesOpt(allow)
-}
-
-// Get returns the value stored in opts with the provided setter,
-// reporting whether the value is present.
-func Get[T any](opts []Option, setter func(T) Option) (T, bool) {
-	var zero T
-	var setterType = reflect.TypeOf(setter(zero))
-	for _, opt := range slices.Backward(opts) {
-		if reflect.TypeOf(opt) == setterType {
-			v, ok := opt.Value().(T)
-			return v, ok
-		}
-	}
-	return zero, false
-}
-
-// All returns a sequence of all values stored in opts with the provided setter.
-func All[T any](opts []Option, setter func(T) Option) iter.Seq[T] {
-	return func(yield func(T) bool) {
-		var zero T
-		var setterType = reflect.TypeOf(setter(zero))
-		for _, opt := range opts {
-			if reflect.TypeOf(opt) == setterType {
-				v, ok := opt.Value().(T)
-				if !ok {
-					panic("option type mismatch")
-				}
-				if !yield(v) {
-					return
-				}
-			}
-		}
-	}
-}
-
-func AllBackward[T any](opts []Option, setter func(T) Option) iter.Seq[T] {
-	return func(yield func(T) bool) {
-		var zero T
-		var setterType = reflect.TypeOf(setter(zero))
-		for i := len(opts) - 1; i >= 0; i-- {
-			opt := opts[i]
-			if reflect.TypeOf(opt) == setterType {
-				v, ok := opt.Value().(T)
-				if !ok {
-					panic("option type mismatch")
-				}
-				if !yield(v) {
-					return
-				}
-			}
-		}
-	}
-}
diff --git a/examples/01-get-started/01_hello_agent/main.go b/examples/01-get-started/01_hello_agent/main.go
--- a/examples/01-get-started/01_hello_agent/main.go
+++ b/examples/01-get-started/01_hello_agent/main.go
@@ -10,9 +10,7 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 
 	openai "github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
@@ -46,7 +44,7 @@ func main() {
 			Model: deployment,
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.", Name: "Joker",
-				Middlewares: []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares: []agent.Middleware{logger}, // for logging agent interactions
 			},
 		})
 
@@ -57,7 +55,7 @@ func main() {
 	demo.Response(resp, err)
 
 	// Invoke the agent with streaming support.
-	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agent.Stream(true)) {
 		demo.Response(update, err)
 	}
 }
diff --git a/examples/01-get-started/02_add_tools/main.go b/examples/01-get-started/02_add_tools/main.go
--- a/examples/01-get-started/02_add_tools/main.go
+++ b/examples/01-get-started/02_add_tools/main.go
@@ -11,9 +11,7 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/microsoft/agent-framework-go/tool"
 	"github.com/microsoft/agent-framework-go/tool/functool"
 
@@ -55,7 +53,7 @@ func main() {
 			Model: deployment,
 			Config: agent.Config{
 				Instructions: "You are a helpful assistant",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 				Tools:        []tool.Tool{weatherTool},
 			},
 		},
@@ -68,7 +66,7 @@ func main() {
 	demo.Response(resp, err)
 
 	// Invoke the agent with streaming support.
-	for update, err := range a.RunText(ctx, "What is the weather like in Amsterdam?", agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "What is the weather like in Amsterdam?", agent.Stream(true)) {
 		demo.Response(update, err)
 	}
 }
diff --git a/examples/01-get-started/03_multi_turn/main.go b/examples/01-get-started/03_multi_turn/main.go
--- a/examples/01-get-started/03_multi_turn/main.go
+++ b/examples/01-get-started/03_multi_turn/main.go
@@ -10,9 +10,7 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -44,7 +42,7 @@ func main() {
 			Model: deployment,
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.", Name: "Joker",
-				Middlewares: []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares: []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
@@ -56,20 +54,20 @@ func main() {
 	if err != nil {
 		demo.Panic(err)
 	}
-	resp, err := a.RunText(ctx, "Tell me a joke about a pirate.", agentopt.Session(session)).Collect()
+	resp, err := a.RunText(ctx, "Tell me a joke about a pirate.", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
-	resp, err = a.RunText(ctx, "Now add some emojis to the joke and tell it in the voice of a pirate's parrot.", agentopt.Session(session)).Collect()
+	resp, err = a.RunText(ctx, "Now add some emojis to the joke and tell it in the voice of a pirate's parrot.", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
 
 	// Invoke the agent with a multi-turn conversation and streaming, where the context is preserved in the session object.
 	session, err = a.CreateSession(ctx)
 	if err != nil {
 		demo.Panic(err)
 	}
-	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agentopt.Session(session), agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agent.WithSession(session), agent.Stream(true)) {
 		demo.Response(update, err)
 	}
-	for update, err := range a.RunText(ctx, "Now add some emojis to the joke and tell it in the voice of a pirate's parrot.", agentopt.Session(session), agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "Now add some emojis to the joke and tell it in the voice of a pirate's parrot.", agent.WithSession(session), agent.Stream(true)) {
 		demo.Response(update, err)
 	}
 }
diff --git a/examples/01-get-started/04_memory/main.go b/examples/01-get-started/04_memory/main.go
--- a/examples/01-get-started/04_memory/main.go
+++ b/examples/01-get-started/04_memory/main.go
@@ -12,11 +12,9 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -48,7 +46,7 @@ func main() {
 			Config: agent.Config{
 				Instructions:     "You are a friendly assistant.",
 				Name:             "MemoryAgent",
-				Middlewares:      []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:      []agent.Middleware{logger}, // for logging agent interactions
 				ContextProviders: []*memory.ContextProvider{newUserMemoryProvider()},
 			},
 		},
@@ -61,15 +59,15 @@ func main() {
 	}
 
 	// The provider doesn't know the user yet — it will ask for a name
-	resp, err := a.RunText(ctx, "Hello, what is the square root of 9?", agentopt.Session(session)).Collect()
+	resp, err := a.RunText(ctx, "Hello, what is the square root of 9?", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
 
 	// Teach the provider the user's name.
-	resp, err = a.RunText(ctx, "My name is Alice", agentopt.Session(session)).Collect()
+	resp, err = a.RunText(ctx, "My name is Alice", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
 
 	// Subsequent calls are personalized using session state.
-	resp, err = a.RunText(ctx, "What is 2 + 2?", agentopt.Session(session)).Collect()
+	resp, err = a.RunText(ctx, "What is 2 + 2?", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
 
 	// Inspect session state to see what the provider stored.
diff --git a/examples/02-agents/agents/step01_running/main.go b/examples/02-agents/agents/step01_running/main.go
--- a/examples/02-agents/agents/step01_running/main.go
+++ b/examples/02-agents/agents/step01_running/main.go
@@ -10,9 +10,7 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	openai "github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -46,7 +44,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.",
 				Name:         "Joker",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
@@ -58,7 +56,7 @@ func main() {
 	demo.Response(resp, err)
 
 	// Invoke the agent with streaming support.
-	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agent.Stream(true)) {
 		demo.Response(update, err)
 	}
 }
diff --git a/examples/02-agents/agents/step02_multiturn_conversation/main.go b/examples/02-agents/agents/step02_multiturn_conversation/main.go
--- a/examples/02-agents/agents/step02_multiturn_conversation/main.go
+++ b/examples/02-agents/agents/step02_multiturn_conversation/main.go
@@ -10,9 +10,7 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -45,7 +43,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.",
 				Name:         "Joker",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
@@ -57,20 +55,20 @@ func main() {
 	if err != nil {
 		demo.Panic(err)
 	}
-	resp, err := a.RunText(ctx, "Tell me a joke about a pirate.", agentopt.Session(session)).Collect()
+	resp, err := a.RunText(ctx, "Tell me a joke about a pirate.", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
-	resp, err = a.RunText(ctx, "Now add some emojis to the joke and tell it in the voice of a pirate's parrot.", agentopt.Session(session)).Collect()
+	resp, err = a.RunText(ctx, "Now add some emojis to the joke and tell it in the voice of a pirate's parrot.", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
 
 	// Invoke the agent with a multi-turn conversation and streaming, where the context is preserved in the session object.
 	session2, err := a.CreateSession(ctx)
 	if err != nil {
 		demo.Panic(err)
 	}
-	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agentopt.Session(session2), agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agent.WithSession(session2), agent.Stream(true)) {
 		demo.Response(update, err)
 	}
-	for update, err := range a.RunText(ctx, "Now add some emojis to the joke and tell it in the voice of a pirate's parrot.", agentopt.Session(session2), agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "Now add some emojis to the joke and tell it in the voice of a pirate's parrot.", agent.WithSession(session2), agent.Stream(true)) {
 		demo.Response(update, err)
 	}
 }
diff --git a/examples/02-agents/agents/step03_using_function_tools/main.go b/examples/02-agents/agents/step03_using_function_tools/main.go
--- a/examples/02-agents/agents/step03_using_function_tools/main.go
+++ b/examples/02-agents/agents/step03_using_function_tools/main.go
@@ -11,9 +11,7 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/microsoft/agent-framework-go/tool"
 	"github.com/microsoft/agent-framework-go/tool/functool"
 	"github.com/openai/openai-go/v3"
@@ -54,7 +52,7 @@ func main() {
 			Model: deployment,
 			Config: agent.Config{
 				Instructions: "You are a helpful assistant",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 				Tools:        []tool.Tool{weatherTool},
 			},
 		},
@@ -67,7 +65,7 @@ func main() {
 	demo.Response(resp, err)
 
 	// Invoke the agent with streaming support.
-	for update, err := range a.RunText(ctx, "What is the weather like in Amsterdam?", agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "What is the weather like in Amsterdam?", agent.Stream(true)) {
 		demo.Response(update, err)
 	}
 }
diff --git a/examples/02-agents/agents/step04_using_function_tools_with_approvals/main.go b/examples/02-agents/agents/step04_using_function_tools_with_approvals/main.go
--- a/examples/02-agents/agents/step04_using_function_tools_with_approvals/main.go
+++ b/examples/02-agents/agents/step04_using_function_tools_with_approvals/main.go
@@ -11,10 +11,8 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/microsoft/agent-framework-go/tool"
 	"github.com/microsoft/agent-framework-go/tool/functool"
 	"github.com/openai/openai-go/v3"
@@ -56,7 +54,7 @@ func main() {
 			Model: deployment,
 			Config: agent.Config{
 				Instructions: "You are a helpful assistant",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 				Tools:        []tool.Tool{tool.ApprovalRequiredFunc(weatherTool)},
 			},
 		},
@@ -69,7 +67,7 @@ func main() {
 	if err != nil {
 		demo.Panic(err)
 	}
-	resp, err := a.RunText(ctx, "What is the weather like in Amsterdam?", agentopt.Session(session)).Collect()
+	resp, err := a.RunText(ctx, "What is the weather like in Amsterdam?", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
 
 	var userResponses []message.Content
@@ -91,6 +89,6 @@ func main() {
 		return
 	}
 	// Pass the user input responses back to the agent for further processing.
-	resp, err = a.RunMessage(ctx, message.New(userResponses...), agentopt.Session(session)).Collect()
+	resp, err = a.RunMessage(ctx, message.New(userResponses...), agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
 }
diff --git a/examples/02-agents/agents/step05_structured_output/main.go b/examples/02-agents/agents/step05_structured_output/main.go
--- a/examples/02-agents/agents/step05_structured_output/main.go
+++ b/examples/02-agents/agents/step05_structured_output/main.go
@@ -12,10 +12,8 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
 	"github.com/microsoft/agent-framework-go/format/jsonformat"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -37,9 +35,9 @@ type PersonInfo struct {
 }
 
 // runFor executes the agent with the given messages and returns the result of type T.
-func runFor[T any](ctx context.Context, a *agent.Agent, message string, opts ...agentopt.Option) (T, error) {
+func runFor[T any](ctx context.Context, a *agent.Agent, message string, opts ...agent.Option) (T, error) {
 	var v T
-	opts = append(opts, agentopt.StructuredOutput(&v), agentopt.Stream(false))
+	opts = append(opts, agent.WithStructuredOutput(&v), agent.Stream(false))
 	for _, err := range a.RunText(ctx, message, opts...) {
 		if err != nil {
 			return v, err
@@ -66,7 +64,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are a helpful assistant.",
 				Name:         "HelpfulAssistant",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
@@ -96,17 +94,17 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are a helpful assistant.",
 				Name:         "HelpfulAssistant",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
-				RunOptions: []agentopt.Option{
-					agentopt.ResponseFormat(jsonformat.MustFor[PersonInfo]()),
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
+				RunOptions: []agent.Option{
+					agent.WithResponseFormat(jsonformat.MustFor[PersonInfo]()),
 				},
 			},
 		},
 	)
 
 	// Invoke the agent with some unstructured input while streaming, to extract the structured information from.
 	var personRaw []byte
-	for update, err := range a.RunText(ctx, "Please provide information about John Smith, who is a 35-year-old software engineer.", agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "Please provide information about John Smith, who is a 35-year-old software engineer.", agent.Stream(true)) {
 		demo.Response(update, err)
 		personRaw = append(personRaw, update.String()...)
 	}
diff --git a/examples/02-agents/agents/step06_persisted_conversation/main.go b/examples/02-agents/agents/step06_persisted_conversation/main.go
--- a/examples/02-agents/agents/step06_persisted_conversation/main.go
+++ b/examples/02-agents/agents/step06_persisted_conversation/main.go
@@ -11,9 +11,7 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -46,7 +44,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.",
 				Name:         "Joker",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
@@ -60,7 +58,7 @@ func main() {
 	}
 
 	// Run the agent with a new session.
-	resp, err := a.RunText(ctx, "Tell me a joke about a pirate.", agentopt.Session(session)).Collect()
+	resp, err := a.RunText(ctx, "Tell me a joke about a pirate.", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
 
 	// Serialize the session state so it can be stored for later use.
@@ -92,6 +90,6 @@ func main() {
 	}
 
 	// Run the agent again with the resumed session.
-	resp, err = a.RunText(ctx, "Now tell the same joke in the voice of a pirate, and add some emojis to the joke.", agentopt.Session(resumedSession)).Collect()
+	resp, err = a.RunText(ctx, "Now tell the same joke in the voice of a pirate, and add some emojis to the joke.", agent.WithSession(resumedSession)).Collect()
 	demo.Response(resp, err)
 }
diff --git a/examples/02-agents/agents/step07_3rdparty_session_storage/main.go b/examples/02-agents/agents/step07_3rdparty_session_storage/main.go
--- a/examples/02-agents/agents/step07_3rdparty_session_storage/main.go
+++ b/examples/02-agents/agents/step07_3rdparty_session_storage/main.go
@@ -15,11 +15,9 @@ import (
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -59,7 +57,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.",
 				Name:         "Joker",
-				Middlewares: []middleware.Middleware{
+				Middlewares: []agent.Middleware{
 					logger,                       // for logging agent interactions
 					&fsMessageStore{Dir: tmpDir}, // for persistent message history
 				},
@@ -76,7 +74,7 @@ func main() {
 	}
 
 	// Run the agent with the session that stores conversation history in the disk store.
-	resp, err := a.RunText(ctx, "Tell me a joke about a pirate.", agentopt.Session(session)).Collect()
+	resp, err := a.RunText(ctx, "Tell me a joke about a pirate.", agent.WithSession(session)).Collect()
 	demo.Response(resp, err)
 
 	// Serialize the session state, so it can be stored for later use.
@@ -99,7 +97,7 @@ func main() {
 	}
 
 	// Run the agent with the session that stores conversation history in the disk store a second time.
-	resp, err = a.RunText(ctx, "Now tell the same joke in the voice of a pirate, and add some emojis to the joke.", agentopt.Session(resumedSession)).Collect()
+	resp, err = a.RunText(ctx, "Now tell the same joke in the voice of a pirate, and add some emojis to the joke.", agent.WithSession(resumedSession)).Collect()
 	demo.Response(resp, err)
 }
 
@@ -171,9 +169,9 @@ func (d *fsMessageStore) persistMessages(session *memory.Session, requestMessage
 	return nil
 }
 
-func (d *fsMessageStore) Run(next middleware.RunFunc, ctx context.Context, msgs []*message.Message, opts ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (d *fsMessageStore) Run(next agent.RunFunc, ctx context.Context, msgs []*message.Message, opts ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	var session *memory.Session
-	if v, ok := agentopt.Get(opts, agentopt.Session); ok {
+	if v, ok := agent.GetOption(opts, agent.WithSession); ok {
 		session = v
 	} else {
 		// If no session is provided, we cannot persist messages, so just pass through to next middleware.
diff --git a/examples/02-agents/agents/step08_observability/main.go b/examples/02-agents/agents/step08_observability/main.go
--- a/examples/02-agents/agents/step08_observability/main.go
+++ b/examples/02-agents/agents/step08_observability/main.go
@@ -12,11 +12,9 @@ import (
 
 	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
 	"github.com/microsoft/agent-framework-go/agent"
+	"github.com/microsoft/agent-framework-go/agent/middleware/otel"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
-	"github.com/microsoft/agent-framework-go/middleware/otel"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 
@@ -71,7 +69,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.",
 				Name:         "Joker",
-				Middlewares: []middleware.Middleware{
+				Middlewares: []agent.Middleware{
 					otel.New(otel.Config{}), // for OpenTelemetry observability
 					logger,                  // for logging agent interactions
 				},
@@ -86,7 +84,7 @@ func main() {
 	demo.Response(resp, err)
 
 	// Invoke the agent with streaming support.
-	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agentopt.Stream(true)) {
+	for update, err := range a.RunText(ctx, "Tell me a joke about a pirate.", agent.Stream(true)) {
 		demo.Response(update, err)
 	}
 }
diff --git a/examples/02-agents/agents/step11_using_images/main.go b/examples/02-agents/agents/step11_using_images/main.go
--- a/examples/02-agents/agents/step11_using_images/main.go
+++ b/examples/02-agents/agents/step11_using_images/main.go
@@ -12,7 +12,6 @@ import (
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -45,7 +44,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are a helpful agent that can analyze images.",
 				Name:         "VisionAgent",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
diff --git a/examples/02-agents/agents/step12_as_function_tool/main.go b/examples/02-agents/agents/step12_as_function_tool/main.go
--- a/examples/02-agents/agents/step12_as_function_tool/main.go
+++ b/examples/02-agents/agents/step12_as_function_tool/main.go
@@ -14,7 +14,6 @@ import (
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/microsoft/agent-framework-go/tool"
 	"github.com/microsoft/agent-framework-go/tool/functool"
 	"github.com/openai/openai-go/v3"
@@ -57,7 +56,7 @@ func main() {
 				Instructions: "You answer questions about the weather.",
 				Name:         "WeatherAgent",
 				Description:  "An agent that answers questions about the weather.",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 				Tools:        []tool.Tool{weatherTool},
 			},
 		},
diff --git a/examples/02-agents/agui/step01_getting_started/client/main.go b/examples/02-agents/agui/step01_getting_started/client/main.go
--- a/examples/02-agents/agui/step01_getting_started/client/main.go
+++ b/examples/02-agents/agui/step01_getting_started/client/main.go
@@ -12,8 +12,8 @@ import (
 	"strings"
 
 	aguiSSEClient "github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/client/sse"
+	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/aguiagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/message"
 )
 
@@ -46,7 +46,7 @@ func main() {
 			return
 		}
 
-		for update, err := range a.RunText(context.Background(), input, agentopt.Session(session), agentopt.Stream(true)) {
+		for update, err := range a.RunText(context.Background(), input, agent.WithSession(session), agent.Stream(true)) {
 			if err != nil {
 				log.Fatal(err)
 			}
diff --git a/examples/02-agents/agui/step01_getting_started/server/main.go b/examples/02-agents/agui/step01_getting_started/server/main.go
--- a/examples/02-agents/agui/step01_getting_started/server/main.go
+++ b/examples/02-agents/agui/step01_getting_started/server/main.go
@@ -42,7 +42,7 @@ func main() {
 		},
 	)
 	mux := http.NewServeMux()
-	mux.Handle("/", aguihosting.NewHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
+	mux.Handle("/", aguihosting.NewJSONHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
 
 	log.Printf("AG-UI server listening on %s", ":8888")
 	if err := http.ListenAndServe(":8888", mux); err != nil {
diff --git a/examples/02-agents/agui/step02_backend_tools/client/main.go b/examples/02-agents/agui/step02_backend_tools/client/main.go
--- a/examples/02-agents/agui/step02_backend_tools/client/main.go
+++ b/examples/02-agents/agui/step02_backend_tools/client/main.go
@@ -12,8 +12,8 @@ import (
 	"strings"
 
 	aguiSSEClient "github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/client/sse"
+	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/aguiagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/message"
 )
 
@@ -46,7 +46,7 @@ func main() {
 			return
 		}
 
-		for update, err := range a.RunText(context.Background(), input, agentopt.Session(session), agentopt.Stream(true)) {
+		for update, err := range a.RunText(context.Background(), input, agent.WithSession(session), agent.Stream(true)) {
 			if err != nil {
 				log.Fatal(err)
 			}
diff --git a/examples/02-agents/agui/step02_backend_tools/server/main.go b/examples/02-agents/agui/step02_backend_tools/server/main.go
--- a/examples/02-agents/agui/step02_backend_tools/server/main.go
+++ b/examples/02-agents/agui/step02_backend_tools/server/main.go
@@ -82,7 +82,7 @@ func main() {
 		},
 	)
 	mux := http.NewServeMux()
-	mux.Handle("/", aguihosting.NewHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
+	mux.Handle("/", aguihosting.NewJSONHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
 
 	log.Printf("AG-UI server listening on %s", ":8888")
 	if err := http.ListenAndServe(":8888", mux); err != nil {
diff --git a/examples/02-agents/agui/step03_frontend_tools/client/main.go b/examples/02-agents/agui/step03_frontend_tools/client/main.go
--- a/examples/02-agents/agui/step03_frontend_tools/client/main.go
+++ b/examples/02-agents/agui/step03_frontend_tools/client/main.go
@@ -14,7 +14,6 @@ import (
 	aguiSSEClient "github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/client/sse"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/aguiagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/message"
 	"github.com/microsoft/agent-framework-go/tool"
 	"github.com/microsoft/agent-framework-go/tool/functool"
@@ -61,7 +60,7 @@ func main() {
 			return
 		}
 
-		for update, err := range a.RunText(context.Background(), input, agentopt.Session(session), agentopt.Stream(true)) {
+		for update, err := range a.RunText(context.Background(), input, agent.WithSession(session), agent.Stream(true)) {
 			if err != nil {
 				log.Fatal(err)
 			}
diff --git a/examples/02-agents/agui/step03_frontend_tools/server/main.go b/examples/02-agents/agui/step03_frontend_tools/server/main.go
--- a/examples/02-agents/agui/step03_frontend_tools/server/main.go
+++ b/examples/02-agents/agui/step03_frontend_tools/server/main.go
@@ -43,7 +43,7 @@ func main() {
 		},
 	)
 	mux := http.NewServeMux()
-	mux.Handle("/", aguihosting.NewHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
+	mux.Handle("/", aguihosting.NewJSONHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
 
 	log.Printf("AG-UI server listening on %s", ":8888")
 	if err := http.ListenAndServe(":8888", mux); err != nil {
diff --git a/examples/02-agents/agui/step04_human_in_loop/client/main.go b/examples/02-agents/agui/step04_human_in_loop/client/main.go
--- a/examples/02-agents/agui/step04_human_in_loop/client/main.go
+++ b/examples/02-agents/agui/step04_human_in_loop/client/main.go
@@ -15,7 +15,6 @@ import (
 	aguiSSEClient "github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/client/sse"
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/aguiagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/message"
 )
@@ -59,7 +58,7 @@ func main() {
 func runWithApprovals(ctx context.Context, a *agent.Agent, session *memory.Session, input *message.Message) error {
 	current := input
 	for {
-		resp, err := a.RunMessage(ctx, current, agentopt.Session(session)).Collect()
+		resp, err := a.RunMessage(ctx, current, agent.WithSession(session)).Collect()
 		if err != nil {
 			return err
 		}
diff --git a/examples/02-agents/agui/step04_human_in_loop/server/main.go b/examples/02-agents/agui/step04_human_in_loop/server/main.go
--- a/examples/02-agents/agui/step04_human_in_loop/server/main.go
+++ b/examples/02-agents/agui/step04_human_in_loop/server/main.go
@@ -53,7 +53,7 @@ func main() {
 		},
 	)
 	mux := http.NewServeMux()
-	mux.Handle("/", aguihosting.NewHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
+	mux.Handle("/", aguihosting.NewJSONHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
 
 	log.Printf("AG-UI server listening on %s", ":8888")
 	if err := http.ListenAndServe(":8888", mux); err != nil {
diff --git a/examples/02-agents/agui/step05_state_management/client/main.go b/examples/02-agents/agui/step05_state_management/client/main.go
--- a/examples/02-agents/agui/step05_state_management/client/main.go
+++ b/examples/02-agents/agui/step05_state_management/client/main.go
@@ -14,8 +14,8 @@ import (
 	"strings"
 
 	aguiSSEClient "github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/client/sse"
+	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/aguiagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/message"
 )
 
@@ -54,7 +54,7 @@ func main() {
 		}
 
 		msg := message.New(&message.TextContent{Text: input}, toStateContent(state))
-		resp, err := a.RunMessage(context.Background(), msg, agentopt.Session(session)).Collect()
+		resp, err := a.RunMessage(context.Background(), msg, agent.WithSession(session)).Collect()
 		if err != nil {
 			log.Fatal(err)
 		}
diff --git a/examples/02-agents/agui/step05_state_management/server/main.go b/examples/02-agents/agui/step05_state_management/server/main.go
--- a/examples/02-agents/agui/step05_state_management/server/main.go
+++ b/examples/02-agents/agui/step05_state_management/server/main.go
@@ -17,16 +17,14 @@ import (
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/hosting/aguihosting"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 	openai "github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
 
 func main() {
-	stateSnapshotMiddleware := middleware.Func(func(next middleware.RunFunc, ctx context.Context, messages []*message.Message, opts ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+	stateSnapshotMiddleware := agent.MiddlewareFunc(func(next agent.RunFunc, ctx context.Context, messages []*message.Message, opts ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 		return func(yield func(*message.ResponseUpdate, error) bool) {
 			for update, err := range next(ctx, messages, opts...) {
 				if err != nil {
@@ -91,12 +89,12 @@ func main() {
   }
 }
 Then also provide a concise summary in one sentence.`,
-				Middlewares: []middleware.Middleware{stateSnapshotMiddleware},
+				Middlewares: []agent.Middleware{stateSnapshotMiddleware},
 			},
 		},
 	)
 	mux := http.NewServeMux()
-	mux.Handle("/", aguihosting.NewHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
+	mux.Handle("/", aguihosting.NewJSONHTTPHandler(aguihosting.HandlerConfig{Agent: a}))
 
 	log.Printf("AG-UI server listening on %s", ":8888")
 	if err := http.ListenAndServe(":8888", mux); err != nil {
diff --git a/examples/02-agents/mcp/agent_mcp_server/main.go b/examples/02-agents/mcp/agent_mcp_server/main.go
--- a/examples/02-agents/mcp/agent_mcp_server/main.go
+++ b/examples/02-agents/mcp/agent_mcp_server/main.go
@@ -8,7 +8,6 @@ import (
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/microsoft/agent-framework-go/tool/mcptool"
 	"github.com/modelcontextprotocol/go-sdk/mcp"
 	"github.com/openai/openai-go/v3"
@@ -46,7 +45,7 @@ func main() {
 			Config: agent.Config{
 				Name:         "DocsAgent",
 				Instructions: "You are a helpful assistant that can help with microsoft documentation questions.",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 				Tools:        tools,
 			},
 		},
diff --git a/examples/02-agents/providers/a2a/main.go b/examples/02-agents/providers/a2a/main.go
--- a/examples/02-agents/providers/a2a/main.go
+++ b/examples/02-agents/providers/a2a/main.go
@@ -13,7 +13,6 @@ import (
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/a2aagent"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"google.golang.org/grpc"
 	"google.golang.org/grpc/credentials/insecure"
 )
@@ -49,7 +48,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.",
 				Name:         "Joker",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
diff --git a/examples/02-agents/providers/anthrophic/main.go b/examples/02-agents/providers/anthrophic/main.go
--- a/examples/02-agents/providers/anthrophic/main.go
+++ b/examples/02-agents/providers/anthrophic/main.go
@@ -9,7 +9,6 @@ import (
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/anthropicagent"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 )
 
 var logger = demo.NewLogger(
@@ -27,7 +26,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.",
 				Name:         "Joker",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
diff --git a/examples/02-agents/providers/azure/main.go b/examples/02-agents/providers/azure/main.go
--- a/examples/02-agents/providers/azure/main.go
+++ b/examples/02-agents/providers/azure/main.go
@@ -11,7 +11,6 @@ import (
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 
 	openai "github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
@@ -45,7 +44,7 @@ func main() {
 			Model: deployment,
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.", Name: "Joker",
-				Middlewares: []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares: []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
diff --git a/examples/02-agents/providers/gemini/main.go b/examples/02-agents/providers/gemini/main.go
--- a/examples/02-agents/providers/gemini/main.go
+++ b/examples/02-agents/providers/gemini/main.go
@@ -10,7 +10,6 @@ import (
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/geminiagent"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"google.golang.org/genai"
 )
 
@@ -41,7 +40,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.",
 				Name:         "Joker",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
diff --git a/examples/02-agents/providers/openai/main.go b/examples/02-agents/providers/openai/main.go
--- a/examples/02-agents/providers/openai/main.go
+++ b/examples/02-agents/providers/openai/main.go
@@ -8,7 +8,6 @@ import (
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 )
 
@@ -26,7 +25,7 @@ func main() {
 			Config: agent.Config{
 				Instructions: "You are good at telling jokes.",
 				Name:         "Joker",
-				Middlewares:  []middleware.Middleware{logger}, // for logging agent interactions
+				Middlewares:  []agent.Middleware{logger}, // for logging agent interactions
 			},
 		},
 	)
diff --git a/examples/02-agents/skills/step01_file_based_skills/main.go b/examples/02-agents/skills/step01_file_based_skills/main.go
--- a/examples/02-agents/skills/step01_file_based_skills/main.go
+++ b/examples/02-agents/skills/step01_file_based_skills/main.go
@@ -19,7 +19,6 @@ import (
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/memory/skills"
 	"github.com/microsoft/agent-framework-go/memory/skills/fsskills"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -62,7 +61,7 @@ func main() {
 			Config: agent.Config{
 				Name:             "UnitConverterAgent",
 				Instructions:     "You are a helpful assistant that can convert units.",
-				Middlewares:      []middleware.Middleware{logger},
+				Middlewares:      []agent.Middleware{logger},
 				ContextProviders: []*memory.ContextProvider{skillsProvider},
 			},
 		},
diff --git a/examples/02-agents/skills/step02_code_defined_skills/main.go b/examples/02-agents/skills/step02_code_defined_skills/main.go
--- a/examples/02-agents/skills/step02_code_defined_skills/main.go
+++ b/examples/02-agents/skills/step02_code_defined_skills/main.go
@@ -19,7 +19,6 @@ import (
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/memory/skills"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -114,7 +113,7 @@ func main() {
 			Config: agent.Config{
 				Name:             "UnitConverterAgent",
 				Instructions:     "You are a helpful assistant that can convert units.",
-				Middlewares:      []middleware.Middleware{logger},
+				Middlewares:      []agent.Middleware{logger},
 				ContextProviders: []*memory.ContextProvider{skillsProvider},
 			},
 		},
diff --git a/examples/02-agents/skills/step03_mixed_skills/main.go b/examples/02-agents/skills/step03_mixed_skills/main.go
--- a/examples/02-agents/skills/step03_mixed_skills/main.go
+++ b/examples/02-agents/skills/step03_mixed_skills/main.go
@@ -20,7 +20,6 @@ import (
 	"github.com/microsoft/agent-framework-go/memory"
 	"github.com/microsoft/agent-framework-go/memory/skills"
 	"github.com/microsoft/agent-framework-go/memory/skills/fsskills"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
 )
@@ -187,7 +186,7 @@ func main() {
 			Config: agent.Config{
 				Name:             "MultiConverterAgent",
 				Instructions:     "You are a helpful assistant that can convert units, volumes, and temperatures.",
-				Middlewares:      []middleware.Middleware{logger},
+				Middlewares:      []agent.Middleware{logger},
 				ContextProviders: []*memory.ContextProvider{skillsProvider},
 			},
 		},
diff --git a/examples/05-end-to-end/a2a_client_server/a2a_client/main.go b/examples/05-end-to-end/a2a_client_server/a2a_client/main.go
--- a/examples/05-end-to-end/a2a_client_server/a2a_client/main.go
+++ b/examples/05-end-to-end/a2a_client_server/a2a_client/main.go
@@ -15,9 +15,7 @@ import (
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/a2aagent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
-	"github.com/microsoft/agent-framework-go/middleware"
 	"github.com/microsoft/agent-framework-go/tool"
 	"github.com/openai/openai-go/v3"
 	"github.com/openai/openai-go/v3/azure"
@@ -79,7 +77,7 @@ func main() {
 			Config: agent.Config{
 				Name:         "HostClient",
 				Instructions: "You specialize in handling user queries and using your tools to provide answers.",
-				Middlewares:  []middleware.Middleware{logger},
+				Middlewares:  []agent.Middleware{logger},
 				Tools:        tools,
 			},
 		},
@@ -106,7 +104,7 @@ func main() {
 			break
 		}
 
-		resp, runErr := host.RunText(ctx, message, agentopt.Session(session)).Collect()
+		resp, runErr := host.RunText(ctx, message, agent.WithSession(session)).Collect()
 		demo.Response(resp, runErr)
 	}
 }
diff --git a/examples/05-end-to-end/a2a_client_server/a2a_server/main.go b/examples/05-end-to-end/a2a_client_server/a2a_server/main.go
--- a/examples/05-end-to-end/a2a_client_server/a2a_server/main.go
+++ b/examples/05-end-to-end/a2a_client_server/a2a_server/main.go
@@ -128,7 +128,7 @@ func main() {
 		a2a.NewAgentInterface(url, a2a.TransportProtocolJSONRPC),
 	}
 	mux := http.NewServeMux()
-	mux.Handle("/", a2ahosting.NewHTTPHandler(a2ahosting.ExecutorConfig{
+	mux.Handle("/", a2ahosting.NewJSONRPCHandler(a2ahosting.ExecutorConfig{
 		Agent: hostAgent,
 	}, a2asrv.WithExtendedAgentCard(card)))
 	mux.Handle(a2asrv.WellKnownAgentCardPath, a2asrv.NewStaticAgentCardHandler(card))
diff --git a/examples/demos/chat_cli/main.go b/examples/demos/chat_cli/main.go
--- a/examples/demos/chat_cli/main.go
+++ b/examples/demos/chat_cli/main.go
@@ -9,7 +9,6 @@ import (
 
 	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/agent/provider/openaichatagent"
-	"github.com/microsoft/agent-framework-go/agentopt"
 	"github.com/microsoft/agent-framework-go/examples/internal/demo"
 	"github.com/microsoft/agent-framework-go/tool"
 	"github.com/microsoft/agent-framework-go/tool/functool"
@@ -88,7 +87,7 @@ func runChatLoop(ctx context.Context, a *agent.Agent) {
 		fmt.Print("Assistant: ")
 
 		hasError := false
-		for update, err := range a.RunText(ctx, userInput, agentopt.Session(session), agentopt.Stream(true)) {
+		for update, err := range a.RunText(ctx, userInput, agent.WithSession(session), agent.Stream(true)) {
 			if err != nil {
 				fmt.Printf("\n❌ Error: %v\n", err)
 				hasError = true
diff --git a/examples/internal/demo/demo.go b/examples/internal/demo/demo.go
--- a/examples/internal/demo/demo.go
+++ b/examples/internal/demo/demo.go
@@ -9,9 +9,8 @@ import (
 	"os"
 	"strings"
 
-	"github.com/microsoft/agent-framework-go/agentopt"
+	"github.com/microsoft/agent-framework-go/agent"
 	"github.com/microsoft/agent-framework-go/message"
-	"github.com/microsoft/agent-framework-go/middleware"
 )
 
 // ANSI color codes
@@ -41,7 +40,7 @@ type logger struct {
 	n int
 }
 
-func NewLogger(name, description string, metadata ...string) middleware.Middleware {
+func NewLogger(name, description string, metadata ...string) agent.Middleware {
 	var kvs []kv
 	for i := 0; i < len(metadata)-1; i += 2 {
 		kvs = append(kvs, kv{key: metadata[i], value: metadata[i+1]})
@@ -50,7 +49,7 @@ func NewLogger(name, description string, metadata ...string) middleware.Middlewa
 	return &logger{}
 }
 
-func (mw *logger) Run(next middleware.RunFunc, ctx context.Context, messages []*message.Message, opts ...agentopt.Option) iter.Seq2[*message.ResponseUpdate, error] {
+func (mw *logger) Run(next agent.RunFunc, ctx context.Context, messages []*message.Message, opts ...agent.Option) iter.Seq2[*message.ResponseUpdate, error] {
 	return func(yield func(*message.ResponseUpdate, error) bool) {
 		mw.n++
 		fmt.Printf("%s%s===== Run %d =====%s\n\n", colorYellow, colorBold, mw.n, colorReset)
@@ -71,7 +70,7 @@ func (mw *logger) Run(next middleware.RunFunc, ctx context.Context, messages []*
 				break
 			}
 		}
-		if v, _ := agentopt.Get(opts, agentopt.Stream); v {
+		if v, _ := agent.GetOption(opts, agent.Stream); v {
 			fmt.Printf("\n\n")
 		}
 	}
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
