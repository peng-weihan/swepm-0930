# Channel gateway owns MessageChannel; runtime_start preserve_skill_sources; attached app-server process-service gating

## Context

Today `MessageChannel` availability for model turns is inferred locally from `ChannelRegistry` adapter state (`getActiveChannelIds()`, `resolveConversationChannelToolScope()` requiring `adapter.isRunning()`) and propagated through `channelToolScope` / the `LETTA_INHERITED_CHANNEL_CONTEXT` env var into subagent child processes. In the real deployment the channel adapters run in the **channel-gateway child process**, so this local inference is both wrong-process and fragile. The ChannelGateway already registers a gateway-built `MessageChannel` external tool per routed runtime via `runtime_start.external_tools` (scope `channel-gateway`); that registration should be the single source of truth.

Four concrete problems to fix:

1. **Process-owned turns lose the gateway tool.** `filterExternalToolsByRuntimeContext` (src/tools/manager.ts:393) drops tools that carry a `connectionId` (the gateway's app-server connection) whenever the turn's `runtimeContext.connectionId` is undefined (process-owned turns queued without a connection).
2. **The gateway's `runtime_start` erases skill sources.** `ensureRuntimeRegistration` (src/channels/gateway-core.ts:406) omits `skill_sources`, and `applyRuntimeStartState` (src/websocket/listener/commands/runtime-start.ts:236) unconditionally clears skill sources when the field is omitted — so an external-tool-only re-registration wipes previously configured skill sources.
3. **The gateway-built tool drops `target` and prunes proactive guidance.** `buildMessageChannelExternalToolDefinition` defaults `allowProactiveTargets: false`, deleting `properties.target`; `gateway-local.ts`'s `buildExternalTool` builds channels from turn sources without `messageActions`, so the compact Slack guidance and action enums are incomplete.
4. **Attached app-server clients race process-service startup.** The gateway's app-server connection (attached runtime) runs the process-services tail (`installProcessEventRouting` + cron) in `startConnectedListenerRuntime`, potentially before the primary listener's startup path (which includes `await startChannelGateway()` in `onConnected`) completes.

Additionally: `composeSubagentChildEnv` serializes inherited channel context into child envs, and forked subagents get `MessageChannel` injected as an extra tool — both must go; the gateway tracks turn sources for the active/routed runtime instead.

Target test contract (from the user): register the gateway-built external tool for `{ agentId: "agent-1", conversationId: "conv-slack" }`, call `prepareToolExecutionContextForModel(..., { clientToolAllowlist: ["MessageChannel"], runtimeContext: { agentId: "agent-1", conversationId: "conv-slack" } })`, and see `MessageChannel` in the prepared tool set; executing it routes back through the registering controller with no `connectionId` in the runtime context.

---

## Step 0 — Worktree

Per CLAUDE.md: create a worktree before this non-trivial change. Do not commit or push until asked.

## Changes

### 1. `runtime_start.preserve_skill_sources` (protocol + handler + gateway)

- **`src/types/protocol_v2.ts`** — add to `RuntimeStartCommand` (next to `skill_sources`, ~line 832):
  ```ts
  /**
   * Keep existing skill sources when skill_sources is omitted. Lets a
   * runtime_start that only updates external tools avoid resetting
   * previously configured skill source overrides.
   */
  preserve_skill_sources?: boolean;
  ```
- **`src/websocket/listener/protocol-inbound.ts`** — in `isRuntimeStartCommand` (~line 540): add `preserve_skill_sources` to the candidate type and
  `(c.preserve_skill_sources === undefined || typeof c.preserve_skill_sources === "boolean")` to the return conjunction (naturally rejects `"yes"`).
- **`src/websocket/listener/commands/runtime-start.ts`** — `applyRuntimeStartState` (~line 236): change the clear branch to
  `if (parsed.skill_sources === undefined && parsed.preserve_skill_sources !== true) { ...clear... }`. When `preserve_skill_sources: true` and `skill_sources` is omitted, both `scopedRuntime.skillSources` and `context.runtime.skillSourcesByConversation` remain untouched.
- **`src/channels/gateway-core.ts`** — `ensureRuntimeRegistration`'s `runtimeStart` call (~line 406): add `preserve_skill_sources: true` so gateway re-registrations (tool signature changes) never erase skill sources.

### 2. Gateway-built MessageChannel tool: `target` + compact guidance + action discovery

- **`src/channels/message-channel-tool-definition.ts`** — `buildMessageChannelExternalToolDefinition` (~line 310): change `allowProactiveTargets: options.allowProactiveTargets ?? false` → `?? true`. This external boundary always has the canonical executor (`executeMessageChannel`) with the proactive `target` path, so the default should advertise it.
- **`src/channels/gateway-local.ts`** — `buildExternalTool` hook (~lines 217–247): replace `buildDynamicMessageChannelToolDefinition` with `buildMessageChannelExternalToolDefinition`. Build `MessageChannelToolChannel[]` from the deduped `{channelId, accountId}` set of `[...routeSources, ...deliverySources]`, enriching each with `displayName: getChannelDisplayName(channelId)` and `messageActions` from `loadChannelPlugin(channelId)` (try/catch, same pattern as `resolveLocalToolChannels` in src/channels/message-tool.ts:39). Call:
  ```ts
  buildMessageChannelExternalToolDefinition({
    scoped: true,
    allowProactiveTargets: true,
    channels,
  })
  ```
  Result: schema keeps `properties.target`; description keeps the compact Slack guidance (`slackWorkAcknowledgement`, `slackThreadGuidance`, `scopedReplyContract`) and action enum reflects plugin `describeMessageTool` discovery. Registration signature change causes one re-`runtime_start` per runtime — fine.

### 3. Process-owned turn discovery + execution routing

- **`src/tools/manager.ts`** — `filterExternalToolsByRuntimeContext` (~line 393): keep a tool for a connection-less turn when the tool is runtime-owned and matches:
  ```ts
  const matchesConnection =
    tool.connectionId === undefined ||
    tool.connectionId === runtimeContext.connectionId;
  const matchesRuntime =
    !tool.runtime ||
    (tool.runtime.agentId === runtimeContext.agentId &&
      tool.runtime.conversationId === runtimeContext.conversationId);
  const processOwnedRuntimeMatch =
    runtimeContext.connectionId === undefined &&
    tool.connectionId !== undefined &&
    tool.runtime !== undefined &&
    tool.runtime.agentId === runtimeContext.agentId &&
    tool.runtime.conversationId === runtimeContext.conversationId;
  return (matchesConnection && matchesRuntime) || processOwnedRuntimeMatch;
  ```
  Notes: `tool.runtime` must be defined for the fallback so connection-scoped runtime-less tools never leak into process-owned snapshots (also keeps `getExternalToolsAsClientTools(registry, {})` behavior unchanged). Turns *with* a `connectionId` keep the existing isolation.
- **Execution routing** — no bridge change needed: `executeToolInner`'s external branch (src/tools/manager.ts:2701) passes the `ExternalToolDefinition` to `executeExternalTool`, and `installExternalToolBridge` (src/websocket/listener/external-tools.ts:99) resolves the controller from `context.tool.registrationKey` → connectionId → `runtime.connections` — it never reads the turn's `connectionId`. Once discovery exposes the tool, routing already works. (The tool's `scopeId: "channel-gateway"` still requires `external_tool_scope_ids: ["channel-gateway"]` on the input turn — the gateway already sends that in `submitDelivery`.)

### 4. Remove `channelToolScope` / local adapter inference / inherited env from the model-turn path

- **`src/tools/manager.ts`**:
  - Remove `channelToolScope` from `capturePreparedToolExecutionContext` options and the `runtimeContext.channelToolScope = ...` assignment (~lines 1118, 1125–1127).
  - Remove `channelToolScope` from the option types of `prepareCurrentToolExecutionContext`, `prepareToolExecutionContextForSpecificTools`, `prepareToolExecutionContextForModel` and stop forwarding it to `buildRegistryForModel` / `buildSpecificToolRegistry` (~lines 1213, 1250–1261, 1289–1290, 1540/1578, 1608/1649, 1666/1714).
  - Delete `maybeAppendChannelTools` (~line 94) and its use in `prepareCurrentToolExecutionContext`; delete the `channelToolScope` parameter of `maybeResolveDynamicChannelTool` and its call sites (unscoped dynamic description resolution for an already-present bundled MessageChannel entry stays).
- **`src/tools/toolset.ts`**:
  - `getToolNamesForToolset` (~line 183): drop the `channelToolScope` param and the `getActiveChannelIds()`-based `MessageChannel` auto-append.
  - Delete `resolveConversationChannelToolScope` (~line 355), `parseInheritedChannelToolScope`, `parseInheritedChannelTurnSources`, `parseInheritedChannelContextEnv` (~lines 401–498).
  - `prepareToolExecutionContextForScope` (~line 500): remove `channelTurnSources` param (no callers pass it), the inherited-env block, and the `channelToolScope` computation/emission; keep passing `channelTurnSources`-free `runtimeContext`. `prepareToolExecutionContextForResolvedTarget` (~line 222): remove `channelToolScope` param and forwarding.
- **`src/runtime-context.ts`**: remove `channelToolScope` from `RuntimeContextSnapshot`/update shapes, `InheritedChannelContextPayload`, and `LETTA_INHERITED_CHANNEL_CONTEXT_ENV`. Keep `channelTurnSources` (still consumed by approval continuation paths: src/agent/approval-execution.ts:269).
  - Check remaining `buildExecutionRuntimeContextSnapshot` copy logic (src/runtime-context.ts:63, 89) for the removed fields.
- Keep untouched: `withDynamicMessageChannelCache`, `refreshDynamicChannelToolsInLoadedRegistry`, `buildDynamicMessageChannelToolDefinition`, and `service-shared.ts` (channels CLI refresh — only affects an already-loaded bundled MessageChannel entry in the CLI process).

### 5. Subagent channel context removal

- **`src/agent/subagents/subagent-launcher.ts`**: remove `InheritedChannelContextPayload` / `LETTA_INHERITED_CHANNEL_CONTEXT_ENV` imports, `inheritedChannelContext` option (~line 158), `buildInheritedChannelContextPayload` (~line 161), and the env emission (~lines 221–225).
- **`src/agent/subagents/manager.ts`**: remove `buildInheritedChannelContextPayload` import + computation (~line 385), the `extraTools: config.fork && inheritedChannelContext ? ["MessageChannel"] : undefined` (~lines 409–412), and the `composeSubagentChildEnv({ inheritedChannelContext })` pass-through (~line 465). Keep `buildSubagentArgs`' `extraTools` param only if other callers remain; otherwise remove.

### 6. Attached app-server clients must not start process services

- **`src/websocket/app-server.ts`**:
  - Add to `StartAppServerOptions`: `/** Start process services (event routing + cron) for accepted clients. Attached/shared runtimes should pass false; the owning listener startup starts them. */ startProcessServices?: boolean;` (default `true`).
  - In `handleWebSocketConnection` (~line 239): pass `startProcessServices: options.startProcessServices !== false` through to `attachOpenListenerSocket` (replacing the bare `startCronScheduler: true`; keep `startHeartbeat: false`, `startupReady: getStartupReady()`).
- **`src/websocket/listener/lifecycle.ts`**:
  - Add `startProcessServices?: boolean` to `attachOpenListenerSocket`'s options (~line 512) and forward to `startConnectedListenerRuntime` options (~line 642) instead of only `startCronScheduler`.
  - `startConnectedListenerRuntime` (~line 378): add `startProcessServices?: boolean` (default `true`); when `false`, skip the entire process-services tail (~lines 455–497: `waitForProcessServicesSlot`, `installProcessEventRouting`, cron, `processServicesStarted`), not just cron.
  - Keep the per-message `await options.startupReady` barrier exactly as-is (attached clients already await `getStartupReady()`; the requirement is that they not *jump ahead* of it via process services).
- **`src/cli/subcommands/listen.tsx`** — `startChannelGateway`'s `startAppServer({ runtime, connectionName, onLog })` (~line 532): add `startProcessServices: false`.
  - Local-channels mode: move gateway startup into the primary startup path by awaiting `startChannelGateway()` inside the `onConnected` callback of `startLocalChannelListener` (~line 625) — `startConnectedListenerRuntime` awaits `opts.onConnected` (lifecycle.ts:408) *before* the process-services tail, so process services then start only after gateway startup completes. The existing `await startChannelGateway()` at line 639 stays (memoized no-op).

### 7. Test updates

- **`src/channels/message-channel-gateway.test.ts`**: first test (~line 52) — `properties.target` now **defined** (assert presence + that `Proactive mode` guidance is in the description); flip the `not.toContain("Proactive mode")` assertion.
- **`src/tools/tool-execution-context.test.ts`**:
  - Rework the `channelToolScope` tests (~lines 1150–1422) to the new contract: build the tool via `buildMessageChannelExternalToolDefinition({ scoped: true, allowProactiveTargets: true, channels: [...] })` (from `@/gateway-core`), `registerExternalTools([{ ...tool, runtime: { agentId, conversationId } }])`, then assert `prepareToolExecutionContextForModel(model, { clientToolAllowlist: ["MessageChannel"], runtimeContext: { agentId, conversationId } })` exposes `MessageChannel` in `clientTools` — including with a synthetic `connectionId` on the registration to cover the process-owned-turn fallback.
  - Remove the `LETTA_INHERITED_CHANNEL_CONTEXT` hydration test (~lines 1330–1385) and `resolveConversationChannelToolScope`-based tests; drop unused imports (`LETTA_INHERITED_CHANNEL_CONTEXT_ENV`, `resolveConversationChannelToolScope`, `refreshDynamicChannelToolsInLoadedRegistry` if unused).
- **`src/websocket/listener/external-tools.test.ts`**: add a test — `registerRuntimeExternalTools(runtime, "conn-1", { agent_id: "agent-1", conversation_id: "conv-slack" }, [{ scope_id: "channel-gateway", tools: [gatewayBuiltTool] }])`, then `prepareToolExecutionContextForModel(..., { clientToolAllowlist: ["MessageChannel"], externalToolScopeIds: ["channel-gateway"], runtimeContext: { agentId: "agent-1", conversationId: "conv-slack" } })` (no connectionId) → MessageChannel present; execute via the mock transport writer and assert the `external_tool_call_request` was sent on the registering controller's connection.
- **`src/websocket/listener/commands/runtime-start-skill-sources.test.ts`**: add cases — `preserve_skill_sources: true` + omitted `skill_sources` keeps `skillSources` and `skillSourcesByConversation` unchanged; omitted without the flag still clears; `preserve_skill_sources: "yes"` rejected by the inbound guard.
- **`src/agent/subagent-env-composition.test.ts`** (~lines 283–325) and **`src/agent/subagent-model-resolution.test.ts`** (~lines 573–597): remove the inherited-channel-env and fork-MessageChannel tests.
- **`src/agent/send-message-stream-channel-envelope.test.ts`**: replace the running-adapter + `channelToolScope` setup with external-tool registration (same pattern as the tool-execution-context rework) so the Slack compact-guidance description assertions still hold.
- **`src/websocket/app-server*.test.ts`**: add a test that an attached (shared-runtime) `startAppServer({ runtime, startProcessServices: false })` client does not set `runtime.processServicesStarted` / install process event routing, while a default client does.
- Protocol guard: extend the existing `isRuntimeStartCommand` tests (wherever runtime_start shape tests live — search `isRuntimeStartCommand` in `src/websocket/listener/*.test.ts`) with `preserve_skill_sources: true/false` accepted, `"yes"` rejected.

## Key files

| File | Change |
|------|--------|
| `src/types/protocol_v2.ts` | `preserve_skill_sources?: boolean` on `RuntimeStartCommand` |
| `src/websocket/listener/protocol-inbound.ts` | boolean guard for the new field |
| `src/websocket/listener/commands/runtime-start.ts` | guarded skill-source clearing |
| `src/channels/gateway-core.ts` | send `preserve_skill_sources: true` |
| `src/channels/message-channel-tool-definition.ts` | `allowProactiveTargets` default `true` |
| `src/channels/gateway-local.ts` | `buildExternalTool` → `buildMessageChannelExternalToolDefinition` with plugin-enriched channels |
| `src/tools/manager.ts` | process-owned runtime match in `filterExternalToolsByRuntimeContext`; remove `channelToolScope` plumbing |
| `src/tools/toolset.ts` | remove local channel-scope resolution + inherited env parsing |
| `src/runtime-context.ts` | remove inherited channel payload/env/scope field |
| `src/agent/subagents/subagent-launcher.ts`, `src/agent/subagents/manager.ts` | drop inherited channel context + fork `MessageChannel` extra tool |
| `src/websocket/app-server.ts`, `src/websocket/listener/lifecycle.ts` | `startProcessServices` option threaded to the process-services tail |
| `src/cli/subcommands/listen.tsx` | `startProcessServices: false` for gateway app server; local-channels gateway-before-process-services ordering |

## Reuse

- `buildMessageChannelExternalToolDefinition` (src/channels/message-channel-tool-definition.ts:302) — already the external-gateway boundary builder; exported from `src/gateway-core.ts`.
- `resolveLocalToolChannels`' plugin-loading pattern (src/channels/message-tool.ts:39) for enriching gateway channels with `messageActions`.
- `registerRuntimeExternalTools` / `installExternalToolBridge` (src/websocket/listener/external-tools.ts) — unchanged routing via `registrationKey`.

## Verification

1. `bun run check` — full suite (biome, tsc, madge cycles, layer boundaries, filename casing, file size, export forms, mock isolation). Fix all failures.
2. Targeted tests first, then the full unit run:
   - `bun test src/channels/message-channel-gateway.test.ts src/channels/gateway-core.test.ts`
   - `bun test src/tools/tool-execution-context.test.ts src/websocket/listener/external-tools.test.ts`
   - `bun test src/websocket/listener/commands/runtime-start-skill-sources.test.ts`
   - `bun test src/agent/subagent-env-composition.test.ts src/agent/subagent-model-resolution.test.ts src/agent/send-message-stream-channel-envelope.test.ts`
   - `bun test src/websocket/app-server-lifecycle.test.ts`
   - Then: `bun test $(find src -name "*.test.ts" | grep -v integration-tests)` — watch for failures that only appear in the full run (mock leakage per CLAUDE.md).
3. Manual golden-path check of the user's contract in a scratch bun script or test: register the gateway-built tool with `runtime: { agentId: "agent-1", conversationId: "conv-slack" }` + a `registrationKey`-style connection mapping, prepare with allowlist + runtimeContext (no connectionId), execute `MessageChannel`, and confirm the request routes over the registering controller's transport.

## Out of scope / notes

- No commit/push until Caren asks (CLAUDE.md workflow).
- `channelTurnSources` stays on `RuntimeContextSnapshot` and `executeTool` options — approval continuation for the bundled tool still uses it; the gateway passes sources explicitly at `executeExternalTool` time.
- The bundled `MessageChannel` internal tool remains in `TOOL_DEFINITIONS` (explicit allowlist/include can still load it); only automatic local-adapter inference is removed. In the listener process the external branch of `executeToolInner` wins on name collision, so gateway-owned execution takes precedence.
