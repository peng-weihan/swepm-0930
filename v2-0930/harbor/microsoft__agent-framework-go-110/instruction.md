The core agent API should no longer require users or provider implementations to import the separate `github.com/microsoft/agent-framework-go/agentopt` or `github.com/microsoft/agent-framework-go/middleware` packages. Agent options, option helpers, middleware interfaces, and middleware helper types should be exposed from the `github.com/microsoft/agent-framework-go/agent` package itself.

All public agent entry points that accept or forward run options should use `agent.Option`. This includes `agent.ProviderConfig.Run`, `agent.ProviderConfig.CreateSession`, `agent.Config.RunOptions`, `Agent.CreateSession`, `Agent.Run`, `Agent.RunText`, and `Agent.RunMessage`. Code implementing providers or tests should be able to define run functions with signatures such as:

```go
func(ctx context.Context, messages []*message.Message, opts ...agent.Option) iter.Seq2[*message.ResponseUpdate, error]
```

The option constructors and lookup helper should also be available from the `agent` package. Existing option usage should be expressible as `agent.Stream(...)`, `agent.AllowBackgroundResponses(...)`, `agent.WithSession(...)`, `agent.WithServiceID(...)`, `agent.WithContinuationToken(...)`, `agent.WithTool(...)`, `agent.WithToolMode(...)`, and `agent.GetOption(...)`. For example, callers should be able to run:

```go
resp, err := a.RunText(ctx, "hello", agent.WithSession(session), agent.Stream(true)).Collect()
```

Middleware should likewise be defined through the `agent` package. `agent.Config.Middlewares` should accept `[]agent.Middleware`, middleware implementations should implement:

```go
Run(next agent.RunFunc, ctx context.Context, messages []*message.Message, opts ...agent.Option) iter.Seq2[*message.ResponseUpdate, error]
```

and function-style middleware should be constructible through the agent package as well. User code and examples should not need to import the standalone `middleware` package just to configure an `agent.Agent`.

The existing agent behavior must remain unchanged after the API move. Middleware ordering, option propagation, session creation, automatic session handling, background response validation, continuation-token validation, tool options, and streaming behavior should continue to work as before. In particular, attempting to provide messages while resuming with a continuation token must still return the existing error behavior, and enabling background responses without an explicit session must still be rejected with the message `a session must be provided when AllowBackgroundResponses is enabled`.

Hosting packages and examples should be updated to use the new `agent` package API. A2A hosting should expose explicit handler constructors for the supported protocol bindings, including `a2ahosting.NewJSONRPCHandler` for JSON-RPC and `a2ahosting.NewJSONHTTPHandler` for HTTP+JSON. AG-UI hosting should expose `aguihosting.NewJSONHTTPHandler`. Existing example code should compile using `agent.Middleware`, `agent.Option`, and the `agent` option constructors rather than importing `agentopt` or `middleware`.
