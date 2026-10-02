#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.github/workflows/pr-title.yml b/.github/workflows/pr-title.yml
--- a/.github/workflows/pr-title.yml
+++ b/.github/workflows/pr-title.yml
@@ -67,7 +67,7 @@ jobs:
           console.error(`Allowed types: ${allowedTypes.join(", ")}`);
           console.error("");
           console.error("Examples:");
-          console.error("  feat(extensions): add provider registry");
+          console.error("  feat(mods): add provider registry");
           console.error("  fix(conversations): regenerate descriptions after compaction");
           console.error("  ci: enforce conventional PR titles");
           console.error("");
diff --git a/src/agent/approval-execution.ts b/src/agent/approval-execution.ts
--- a/src/agent/approval-execution.ts
+++ b/src/agent/approval-execution.ts
@@ -13,7 +13,7 @@ import { INTERRUPTED_BY_USER } from "@/constants";
 import { getCurrentWorkingDirectory } from "@/runtime-context";
 import {
   executeTool,
-  isExtensionToolParallelSafeForContext,
+  isModToolParallelSafeForContext,
   prepareCurrentToolExecutionContext,
   type ToolExecutionResult,
   type ToolReturnContent,
@@ -88,7 +88,7 @@ const PARALLEL_SAFE_TOOLS = new Set([
 function isParallelSafe(toolName: string, toolContextId?: string): boolean {
   return (
     PARALLEL_SAFE_TOOLS.has(toolName) ||
-    isExtensionToolParallelSafeForContext(toolName, toolContextId)
+    isModToolParallelSafeForContext(toolName, toolContextId)
   );
 }
 
diff --git a/src/backend/dev/pi-model-factory.ts b/src/backend/dev/pi-model-factory.ts
--- a/src/backend/dev/pi-model-factory.ts
+++ b/src/backend/dev/pi-model-factory.ts
@@ -21,7 +21,7 @@ import {
   type PiProviderRegistration,
   resolveRegisteredPiProviderFromModelHandle,
   stripRegisteredProviderHandlePrefix,
-} from "./pi-provider-extension-registry";
+} from "./pi-provider-mod-registry";
 import {
   expectedPiProviderList,
   getPiProviderSpec,
@@ -183,7 +183,7 @@ export function resolvePiProviderFromAgent(
     const slashIndex = model.indexOf("/");
     if (slashIndex > 0) {
       throw new Error(
-        `Model provider "${model.slice(0, slashIndex)}" is not registered. Load or repair the provider extension, or choose another model with /model.`,
+        `Model provider "${model.slice(0, slashIndex)}" is not registered. Load or repair the provider mod, or choose another model with /model.`,
       );
     }
   }
diff --git a/src/backend/dev/pi-provider-extension-registry.ts b/src/backend/dev/pi-provider-mod-registry.ts
rename from src/backend/dev/pi-provider-extension-registry.ts
rename to src/backend/dev/pi-provider-mod-registry.ts
--- a/src/backend/dev/pi-provider-extension-registry.ts
+++ b/src/backend/dev/pi-provider-mod-registry.ts
@@ -6,12 +6,12 @@ import type {
   PiProviderOAuthLoginCallbacks,
   PiProviderRegistration,
   RegisteredPiProvider,
-} from "./pi-provider-extension-types";
+} from "./pi-provider-mod-types";
 import {
   clonePiProviderRegistration,
   resolvePiProviderRegistrationHeaders,
   validatePiProviderRegistration,
-} from "./pi-provider-extension-validation";
+} from "./pi-provider-mod-validation";
 
 export type {
   PiProviderConnectConfig,
@@ -24,7 +24,7 @@ export type {
   PiProviderOAuthLoginCallbacks,
   PiProviderRegistration,
   RegisteredPiProvider,
-} from "./pi-provider-extension-types";
+} from "./pi-provider-mod-types";
 
 type PiProviderRegistryListener = () => void;
 
@@ -37,7 +37,7 @@ function notifyRegistryListeners(): void {
       listener();
     } catch {
       // Registry listeners are observers; a UI refresh failure should not make
-      // extension provider registration fail.
+      // mod provider registration fail.
     }
   }
 }
diff --git a/src/backend/dev/pi-provider-extension-types.ts b/src/backend/dev/pi-provider-mod-types.ts
rename from src/backend/dev/pi-provider-extension-types.ts
rename to src/backend/dev/pi-provider-mod-types.ts
--- a/src/backend/dev/pi-provider-extension-types.ts
+++ b/src/backend/dev/pi-provider-mod-types.ts

diff --git a/src/backend/dev/pi-provider-extension-validation.ts b/src/backend/dev/pi-provider-mod-validation.ts
rename from src/backend/dev/pi-provider-extension-validation.ts
rename to src/backend/dev/pi-provider-mod-validation.ts
--- a/src/backend/dev/pi-provider-extension-validation.ts
+++ b/src/backend/dev/pi-provider-mod-validation.ts
@@ -1,7 +1,7 @@
 import type {
   PiProviderModelRegistration,
   PiProviderRegistration,
-} from "./pi-provider-extension-types";
+} from "./pi-provider-mod-types";
 
 function cloneHeaders(
   headers: Record<string, string> | undefined,
diff --git a/src/backend/dev/registered-pi-provider-runtime.ts b/src/backend/dev/registered-pi-provider-runtime.ts
--- a/src/backend/dev/registered-pi-provider-runtime.ts
+++ b/src/backend/dev/registered-pi-provider-runtime.ts
@@ -11,12 +11,12 @@ import {
 import {
   resolveRegisteredPiProviderApiKey,
   resolveRegisteredPiProviderHeaders,
-} from "./pi-provider-extension-registry";
+} from "./pi-provider-mod-registry";
 import type {
   PiProviderConnection,
   PiProviderModelRegistration,
   RegisteredPiProvider,
-} from "./pi-provider-extension-types";
+} from "./pi-provider-mod-types";
 import { getPiProviderSpec, isPiProvider } from "./pi-provider-registry";
 
 export interface RegisteredPiProviderRuntimeConnection {
diff --git a/src/backend/local/local-model-config.ts b/src/backend/local/local-model-config.ts
--- a/src/backend/local/local-model-config.ts
+++ b/src/backend/local/local-model-config.ts
@@ -10,7 +10,7 @@ import {
   listRegisteredPiProviders,
   resolveRegisteredPiProviderFromModelHandle,
   stripRegisteredProviderHandlePrefix,
-} from "@/backend/dev/pi-provider-extension-registry";
+} from "@/backend/dev/pi-provider-mod-registry";
 import {
   getPiProviderSpec,
   isPiProvider,
diff --git a/src/backend/local/local-provider-auth-store.ts b/src/backend/local/local-provider-auth-store.ts
--- a/src/backend/local/local-provider-auth-store.ts
+++ b/src/backend/local/local-provider-auth-store.ts
@@ -11,7 +11,7 @@ import {
   type OAuthCredentials,
 } from "@earendil-works/pi-ai/oauth";
 import type { ProviderResponse } from "@/backend/api/providers";
-import { getRegisteredPiProvider } from "@/backend/dev/pi-provider-extension-registry";
+import { getRegisteredPiProvider } from "@/backend/dev/pi-provider-mod-registry";
 import {
   LOCAL_CHATGPT_PROVIDER_NAME,
   SUPPORTED_LOCAL_PROVIDER_TYPES,
diff --git a/src/cli/app/AppCoordinator.tsx b/src/cli/app/AppCoordinator.tsx
--- a/src/cli/app/AppCoordinator.tsx
+++ b/src/cli/app/AppCoordinator.tsx
@@ -43,7 +43,7 @@ import {
 import { getBackend, isLocalBackendEnabled } from "@/backend";
 import { getClient } from "@/backend/api/client";
 import { getBillingTier } from "@/backend/api/metadata";
-import { subscribePiProviderRegistry } from "@/backend/dev/pi-provider-extension-registry";
+import { subscribePiProviderRegistry } from "@/backend/dev/pi-provider-mod-registry";
 import {
   cancelActiveConnectOperation,
   isActiveConnectOperationCancellable,
@@ -58,11 +58,6 @@ import type { BtwState } from "@/cli/components/BtwPane";
 import type { ModelSelectorSelection } from "@/cli/components/ModelSelector";
 import { TerminalTitleWriter } from "@/cli/components/TerminalTitleWriter";
 import { buildStatuslineRenderContext } from "@/cli/display/statusline/context";
-import type { ExtensionConversationCloseReason } from "@/cli/extensions/types";
-import {
-  type LocalExtensionAdapter,
-  useLocalExtensionAdapter,
-} from "@/cli/extensions/use-local-extension-adapter";
 import {
   appendStreamingOutput,
   type Buffers,
@@ -120,6 +115,11 @@ import {
   useTerminalWidth,
 } from "@/cli/hooks/use-terminal-width";
 import { useSuspend } from "@/cli/hooks/useSuspend/use-suspend.ts";
+import type { ModConversationCloseReason } from "@/cli/mods/types";
+import {
+  type LocalModAdapter,
+  useLocalModAdapter,
+} from "@/cli/mods/use-local-mod-adapter";
 import {
   getTask,
   handleMissedOneShot,
@@ -341,7 +341,7 @@ export function App({
   releaseNotes = null,
   updateNotification = null,
   systemInfoReminderEnabled = true,
-  extensionsDisabled = false,
+  modsDisabled = false,
 }: AppProps) {
   // Warm the model-access cache in the background so /model is fast on first open.
   useEffect(() => {
@@ -1026,8 +1026,8 @@ export function App({
   const sessionStatsRef = useRef(new SessionStats());
   const sessionStartTimeRef = useRef(Date.now());
   const sessionHooksRanRef = useRef(false);
-  const sessionExtensionStartAttemptedRef = useRef(false);
-  const extensionAdapterRef = useRef<LocalExtensionAdapter | null>(null);
+  const sessionModStartAttemptedRef = useRef(false);
+  const modAdapterRef = useRef<LocalModAdapter | null>(null);
 
   // Initialize chunk log for this agent + session (clears buffer, GCs old files).
   // Re-runs when agentId changes (e.g. agent switch via /agents).
@@ -1129,7 +1129,7 @@ export function App({
 
   // Run SessionEnd hooks helper
   const runEndHooks = useCallback(
-    async (reason: ExtensionConversationCloseReason = "quit") => {
+    async (reason: ModConversationCloseReason = "quit") => {
       const durationMs = Date.now() - sessionStartTimeRef.current;
       try {
         await runSessionEndHooks(
@@ -1143,10 +1143,10 @@ export function App({
         // Silently ignore hook errors
       }
 
-      const extensionAdapter = extensionAdapterRef.current;
-      if (extensionAdapter) {
+      const modAdapter = modAdapterRef.current;
+      if (modAdapter) {
         try {
-          await extensionAdapter.events.emit("conversation_close", {
+          await modAdapter.events.emit("conversation_close", {
             agentId: agentIdRef.current ?? null,
             conversationId: conversationIdRef.current ?? null,
             durationMs,
@@ -1155,7 +1155,7 @@ export function App({
             toolCallCount: telemetry.getToolCallCount(),
           });
         } catch {
-          // Extension lifecycle events are best-effort on shutdown.
+          // Mod lifecycle events are best-effort on shutdown.
         }
       }
     },
@@ -1629,15 +1629,15 @@ export function App({
           conversationId: conversationIdRef.current,
           overrideModel: desiredModel,
           workingDirectory,
-          extensionEvents: extensionAdapterRef.current?.events,
+          modEvents: modAdapterRef.current?.events,
         });
       }
 
       if (desiredModel) {
         return prepareToolExecutionContextForResolvedTarget({
           modelIdentifier: desiredModel,
           conversationId: conversationIdRef.current,
-          extensionEvents: extensionAdapterRef.current?.events,
+          modEvents: modAdapterRef.current?.events,
           toolsetPreference: currentToolsetPreference,
           workingDirectory,
         });
@@ -1646,7 +1646,7 @@ export function App({
       return prepareToolExecutionContextForResolvedTarget({
         modelIdentifier: null,
         conversationId: conversationIdRef.current,
-        extensionEvents: extensionAdapterRef.current?.events,
+        modEvents: modAdapterRef.current?.events,
         toolsetPreference: currentToolsetPreference,
         workingDirectory,
       });
@@ -2322,7 +2322,7 @@ export function App({
       duration_ms: Date.now() - a.startTime,
     })),
   });
-  const extensionContext = useMemo(
+  const modContext = useMemo(
     () =>
       buildStatuslineRenderContext({
         payload: statusLinePayload,
@@ -2351,28 +2351,28 @@ export function App({
       statusLinePayload,
     ],
   );
-  const extensionAdapter = useLocalExtensionAdapter(extensionContext, {
-    disabled: extensionsDisabled,
+  const modAdapter = useLocalModAdapter(modContext, {
+    disabled: modsDisabled,
   });
 
   useEffect(() => {
-    extensionAdapterRef.current = extensionAdapter;
-  }, [extensionAdapter]);
+    modAdapterRef.current = modAdapter;
+  }, [modAdapter]);
 
   useEffect(() => {
     if (!agentId || agentId === "loading") return;
-    if (sessionExtensionStartAttemptedRef.current) return;
-    if (extensionAdapter.isLoading) return;
-    if (!extensionAdapter.hasExtensionSources) return;
+    if (sessionModStartAttemptedRef.current) return;
+    if (modAdapter.isLoading) return;
+    if (!modAdapter.hasModSources) return;
 
-    sessionExtensionStartAttemptedRef.current = true;
-    void extensionAdapter.events.emit("conversation_open", {
+    sessionModStartAttemptedRef.current = true;
+    void modAdapter.events.emit("conversation_open", {
       agentId,
       agentName: agentName ?? null,
       conversationId: conversationIdRef.current ?? null,
       reason: "startup",
     });
-  }, [agentId, agentName, extensionAdapter]);
+  }, [agentId, agentName, modAdapter]);
 
   // Keep buffers in sync with agentId for server-side tool hooks
   useEffect(() => {
@@ -2593,24 +2593,24 @@ export function App({
     }
 
     const durationMs = Date.now() - sessionStartTimeRef.current;
-    void extensionAdapter.events.emit("conversation_close", {
+    void modAdapter.events.emit("conversation_close", {
       agentId,
       conversationId: conversationIdRef.current ?? null,
       durationMs,
       messageCount: telemetry.getMessageCount(),
       reason: "reload",
       toolCallCount: telemetry.getToolCallCount(),
     });
-    await extensionAdapter.reload();
-    void extensionAdapter.events.emit("conversation_open", {
+    await modAdapter.reload();
+    void modAdapter.events.emit("conversation_open", {
       agentId,
       agentName: agentName ?? null,
       conversationId: conversationIdRef.current ?? null,
       reason: "reload",
     });
     setTerminalTitleConfigRefreshEpoch((epoch) => epoch + 1);
     refreshDerived();
-  }, [agentId, agentName, extensionAdapter, refreshDerived]);
+  }, [agentId, agentName, modAdapter, refreshDerived]);
 
   const recordCommandReminder = useCallback((event: CommandFinishedEvent) => {
     let input = event.input.trim();
@@ -3141,7 +3141,7 @@ export function App({
     return undefined;
   }, [loadingState, agentId, initialAgentState]);
 
-  // Extension provider metadata can arrive after the first local AgentState
+  // Mod provider metadata can arrive after the first local AgentState
   // projection on cold boot. Re-project the active local agent when the provider
   // registry changes so statusline context windows reflect registered models.
   useEffect(() => {
@@ -3214,7 +3214,7 @@ export function App({
       });
     };
 
-    if (!extensionAdapter.isLoading) {
+    if (!modAdapter.isLoading) {
       refreshAgentFromRegisteredProviderMetadata();
     }
 
@@ -3227,7 +3227,7 @@ export function App({
     };
   }, [
     agentId,
-    extensionAdapter.isLoading,
+    modAdapter.isLoading,
     hasConversationModelOverrideRef,
     isLocalBackend,
     loadingState,
@@ -3704,7 +3704,7 @@ export function App({
     emptyResponseRetriesRef,
     executingToolCallIdsRef,
     generateConversationDescription,
-    extensionAdapter,
+    modAdapter,
     generateConversationTitle,
     hasConversationModelOverrideRef,
     interruptQueuedRef,
@@ -4023,7 +4023,7 @@ export function App({
     currentModelHandle,
     currentModelId,
     emittedIdsRef,
-    extensionAdapter,
+    modAdapter,
     hasBackfilledRef,
     isAgentBusy,
     maybeCarryOverActiveConversationModel,
@@ -4112,7 +4112,7 @@ export function App({
     currentModelProvider,
     effectiveContextWindowSize,
     emittedIdsRef,
-    extensionAdapter,
+    modAdapter,
     firstUserQueryRef,
     flushPendingReasoningEffort: () => flushPendingReasoningEffort(),
     generateConversationDescription,
@@ -5050,7 +5050,7 @@ export function App({
         terminalTitleData={terminalTitleData}
         onTitlePreview={setTerminalTitlePreviewOverride}
         onTitlePreviewEnd={clearTerminalTitlePreviewOverride}
-        extensionAdapter={extensionAdapter}
+        modAdapter={modAdapter}
         streaming={streaming}
         stubDescriptions={stubDescriptions}
         thinkingMessage={thinkingMessage}
diff --git a/src/cli/app/AppView.tsx b/src/cli/app/AppView.tsx
--- a/src/cli/app/AppView.tsx
+++ b/src/cli/app/AppView.tsx
@@ -57,7 +57,6 @@ import { WelcomeScreen } from "@/cli/components/WelcomeScreen";
 import { WindowTitlePicker } from "@/cli/components/WindowTitlePicker";
 import { WorktreeDiffSelector } from "@/cli/components/WorktreeDiffSelector";
 import { AnimationProvider } from "@/cli/contexts/AnimationContext";
-import type { LocalExtensionAdapter } from "@/cli/extensions/use-local-extension-adapter";
 import { type Buffers, type Line, toLines } from "@/cli/helpers/accumulator";
 import { backfillBuffers } from "@/cli/helpers/backfill";
 import {
@@ -82,6 +81,7 @@ import {
 } from "@/cli/helpers/tool-name-mapping";
 import { isTaskTool } from "@/cli/helpers/tool-name-mapping.js";
 import type { WindowTitleData } from "@/cli/helpers/window-title-config";
+import type { LocalModAdapter } from "@/cli/mods/use-local-mod-adapter";
 import { experimentManager } from "@/experiments/manager";
 import type { ExperimentId } from "@/experiments/types";
 import type { ApprovalContext } from "@/permissions/analyzer";
@@ -324,7 +324,7 @@ type AppViewProps = {
   terminalTitleData: WindowTitleData;
   onTitlePreview: (title: string | null) => void;
   onTitlePreviewEnd: () => void;
-  extensionAdapter: LocalExtensionAdapter;
+  modAdapter: LocalModAdapter;
   fileAutocompleteFdPath?: string | null;
   streaming: boolean;
   stubDescriptions: Map<string, string>;
@@ -472,7 +472,7 @@ export function AppView(props: AppViewProps) {
     terminalTitleData,
     onTitlePreview,
     onTitlePreviewEnd,
-    extensionAdapter,
+    modAdapter,
     streaming,
     stubDescriptions,
     thinkingMessage,
@@ -762,7 +762,7 @@ export function AppView(props: AppViewProps) {
                 terminalWidth={chromeColumns}
                 shouldAnimate={shouldAnimate}
                 statusLinePayload={statusLinePayload}
-                extensionAdapter={extensionAdapter}
+                modAdapter={modAdapter}
                 statusLinePrompt={statusLinePrompt}
                 footerNotification={footerUpdateText}
                 showInspirationalPromptHints={showInspirationalPromptHints}
diff --git a/src/cli/app/command-routing.ts b/src/cli/app/command-routing.ts
--- a/src/cli/app/command-routing.ts
+++ b/src/cli/app/command-routing.ts
@@ -74,10 +74,10 @@ export function shouldSlashCommandBypassQueue(
   msg: string,
   options: {
     hasCustomCommand?: boolean;
-    extensionCommand?: { runWhenBusy: boolean };
+    modCommand?: { runWhenBusy: boolean };
   } = {},
 ): boolean {
   if (options.hasCustomCommand) return false;
-  if (options.extensionCommand) return options.extensionCommand.runWhenBusy;
+  if (options.modCommand) return options.modCommand.runWhenBusy;
   return isInteractiveCommand(msg) || isNonStateCommand(msg);
 }
diff --git a/src/cli/app/types.ts b/src/cli/app/types.ts
--- a/src/cli/app/types.ts
+++ b/src/cli/app/types.ts
@@ -49,7 +49,7 @@ export type AppProps = {
   releaseNotes?: string | null; // Markdown release notes to display above header
   updateNotification?: string | null; // Latest version when a significant auto-update was applied
   systemInfoReminderEnabled?: boolean;
-  extensionsDisabled?: boolean;
+  modsDisabled?: boolean;
 };
 
 export type ActiveOverlay =
diff --git a/src/cli/app/use-conversation-loop.ts b/src/cli/app/use-conversation-loop.ts
--- a/src/cli/app/use-conversation-loop.ts
+++ b/src/cli/app/use-conversation-loop.ts
@@ -40,7 +40,6 @@ import {
   hasActiveSubagents,
 } from "@/agent/subagent-state";
 import { type ConversationMessageStreamBody, getBackend } from "@/backend";
-import type { LocalExtensionAdapter } from "@/cli/extensions/use-local-extension-adapter";
 import {
   type Buffers,
   type Line,
@@ -94,6 +93,7 @@ import {
   isPatchTool,
 } from "@/cli/helpers/tool-name-mapping";
 import { alwaysRequiresUserInput } from "@/cli/helpers/tool-name-mapping.js";
+import type { LocalModAdapter } from "@/cli/mods/use-local-mod-adapter";
 import { SYSTEM_ALERT_OPEN, SYSTEM_REMINDER_OPEN } from "@/constants";
 import { goalLoopMode } from "@/goal-loop-mode";
 import { runStopHooks } from "@/hooks";
@@ -201,7 +201,7 @@ type ConversationLoopContext = {
   generateConversationDescription: (options?: {
     force?: boolean;
   }) => Promise<void>;
-  extensionAdapter: LocalExtensionAdapter;
+  modAdapter: LocalModAdapter;
   generateConversationTitle: () => Promise<string | null>;
   hasConversationModelOverrideRef: MutableRefObject<boolean>;
   interruptQueuedRef: MutableRefObject<boolean>;
@@ -299,7 +299,7 @@ export function useConversationLoop(ctx: ConversationLoopContext) {
     emptyResponseRetriesRef,
     executingToolCallIdsRef,
     generateConversationDescription,
-    extensionAdapter,
+    modAdapter,
     generateConversationTitle,
     hasConversationModelOverrideRef,
     interruptQueuedRef,
@@ -639,12 +639,12 @@ export function useConversationLoop(ctx: ConversationLoopContext) {
             conversationId: conversationIdRef.current ?? null,
             input: currentInput,
           };
-          await extensionAdapter.events.emit("turn_start", turnStartEvent);
+          await modAdapter.events.emit("turn_start", turnStartEvent);
           currentInput = isTurnInputArray(turnStartEvent.input)
             ? turnStartEvent.input
             : originalInput;
         } catch {
-          // Extension turn_start handlers should not block sending the turn.
+          // Mod turn_start handlers should not block sending the turn.
           currentInput = originalInput;
         }
       }
@@ -2994,7 +2994,7 @@ export function useConversationLoop(ctx: ConversationLoopContext) {
       setUiPermissionMode,
       prepareScopedToolExecutionContext,
       maybeStreamSyntheticNoModelResponse,
-      extensionAdapter,
+      modAdapter,
     ],
   );
 
diff --git a/src/cli/app/use-conversation-switching.ts b/src/cli/app/use-conversation-switching.ts
--- a/src/cli/app/use-conversation-switching.ts
+++ b/src/cli/app/use-conversation-switching.ts
@@ -32,8 +32,6 @@ import {
 } from "@/backend";
 import { getServerUrl } from "@/backend/api/client";
 import type { BtwState } from "@/cli/components/BtwPane";
-import type { ExtensionConversationCloseReason } from "@/cli/extensions/types";
-import type { LocalExtensionAdapter } from "@/cli/extensions/use-local-extension-adapter";
 import {
   type Buffers,
   extractTextPart,
@@ -50,6 +48,8 @@ import type { ConversationSwitchContext } from "@/cli/helpers/conversation-switc
 import { formatErrorDetails } from "@/cli/helpers/error-formatter";
 import { CLI_GLYPHS } from "@/cli/helpers/glyphs";
 import type { ApprovalRequest } from "@/cli/helpers/stream";
+import type { ModConversationCloseReason } from "@/cli/mods/types";
+import type { LocalModAdapter } from "@/cli/mods/use-local-mod-adapter";
 import { runSessionStartHooks } from "@/hooks";
 import { updateProjectSettings } from "@/settings";
 import { settingsManager } from "@/settings-manager";
@@ -82,7 +82,7 @@ type ConversationSwitchingContext = {
   currentModelHandle: string | null;
   currentModelId: string | null;
   emittedIdsRef: MutableRefObject<Set<string>>;
-  extensionAdapter: LocalExtensionAdapter;
+  modAdapter: LocalModAdapter;
   hasBackfilledRef: MutableRefObject<boolean>;
   isAgentBusy: () => boolean;
   maybeCarryOverActiveConversationModel: (
@@ -100,7 +100,7 @@ type ConversationSwitchingContext = {
   resetDeferredToolCallCommits: () => void;
   resetPendingReasoningCycle: () => void;
   resetTrajectoryBases: () => void;
-  runEndHooks: (reason?: ExtensionConversationCloseReason) => Promise<void>;
+  runEndHooks: (reason?: ModConversationCloseReason) => Promise<void>;
   sessionHooksRanRef: MutableRefObject<boolean>;
   sessionStartFeedbackRef: MutableRefObject<string[]>;
   setActiveOverlay: Dispatch<SetStateAction<ActiveOverlay>>;
@@ -141,7 +141,7 @@ export function useConversationSwitching(ctx: ConversationSwitchingContext) {
     currentModelHandle,
     currentModelId,
     emittedIdsRef,
-    extensionAdapter,
+    modAdapter,
     hasBackfilledRef,
     isAgentBusy,
     maybeCarryOverActiveConversationModel,
@@ -434,7 +434,7 @@ export function useConversationSwitching(ctx: ConversationSwitchingContext) {
           })
           .catch(() => {});
         sessionHooksRanRef.current = true;
-        void extensionAdapter.events.emit("conversation_open", {
+        void modAdapter.events.emit("conversation_open", {
           agentId,
           agentName: agentName ?? null,
           conversationId,
@@ -468,7 +468,7 @@ export function useConversationSwitching(ctx: ConversationSwitchingContext) {
       setCommandRunning,
       setStreaming,
       recoverRestoredPendingApprovals,
-      extensionAdapter,
+      modAdapter,
       resetDeferredToolCallCommits,
       resetTrajectoryBases,
       abortControllerRef,
diff --git a/src/cli/app/use-submit-handler.ts b/src/cli/app/use-submit-handler.ts
--- a/src/cli/app/use-submit-handler.ts
+++ b/src/cli/app/use-submit-handler.ts
@@ -44,17 +44,6 @@ import { getClient } from "@/backend/api/client";
 import type { CustomCommand } from "@/cli/commands/custom";
 import type { CommandHandle } from "@/cli/commands/runner";
 import { validateAgentName } from "@/cli/components/PinDialog";
-import {
-  buildExtensionCommandPrompt,
-  parseExtensionCommandArgv,
-  parseExtensionSlashCommand,
-  runExtensionCommandWithTimeout,
-} from "@/cli/extensions/command-runtime";
-import type {
-  ExtensionCommandContext,
-  ExtensionConversationCloseReason,
-} from "@/cli/extensions/types";
-import type { LocalExtensionAdapter } from "@/cli/extensions/use-local-extension-adapter";
 import { type Buffers, type Line, toLines } from "@/cli/helpers/accumulator";
 import { buildChatUrl, isLocalAgentId } from "@/cli/helpers/app-urls";
 import {
@@ -97,19 +86,30 @@ import {
   setSystemPromptDoctorState,
 } from "@/cli/helpers/system-prompt-warning.ts";
 import { getRandomThinkingVerb } from "@/cli/helpers/thinking-messages";
+import {
+  buildModCommandPrompt,
+  parseModCommandArgv,
+  parseModSlashCommand,
+  runModCommandWithTimeout,
+} from "@/cli/mods/command-runtime";
+import type {
+  ModCommandContext,
+  ModConversationCloseReason,
+} from "@/cli/mods/types";
+import type { LocalModAdapter } from "@/cli/mods/use-local-mod-adapter";
 import {
   DEFAULT_SUMMARIZATION_MODEL,
   SYSTEM_REMINDER_CLOSE,
   SYSTEM_REMINDER_OPEN,
 } from "@/constants";
 import { experimentManager } from "@/experiments/manager";
-import { createExtensionConversationHandle } from "@/extensions/conversation-handle";
 import { goalLoopMode } from "@/goal-loop-mode";
 import {
   runPreCompactHooks,
   runSessionStartHooks,
   runUserPromptSubmitHooks,
 } from "@/hooks";
+import { createModConversationHandle } from "@/mods/conversation-handle";
 import type { PermissionMode } from "@/permissions/mode";
 import { permissionMode } from "@/permissions/mode";
 import type { QueueRuntime } from "@/queue/queue-runtime";
@@ -209,7 +209,7 @@ type SubmitHandlerContext = {
   currentModelProvider: string | null;
   effectiveContextWindowSize: number | undefined;
   emittedIdsRef: MutableRefObject<Set<string>>;
-  extensionAdapter: LocalExtensionAdapter;
+  modAdapter: LocalModAdapter;
   firstUserQueryRef: MutableRefObject<string | null>;
   flushPendingReasoningEffort: () => Promise<void>;
   generateConversationDescription: (options?: {
@@ -255,7 +255,7 @@ type SubmitHandlerContext = {
   resetDeferredToolCallCommits: () => void;
   resetPendingReasoningCycle: () => void;
   resetTrajectoryBases: () => void;
-  runEndHooks: (reason?: ExtensionConversationCloseReason) => Promise<void>;
+  runEndHooks: (reason?: ModConversationCloseReason) => Promise<void>;
   sessionHooksRanRef: MutableRefObject<boolean>;
   sessionStartFeedbackRef: MutableRefObject<string[]>;
   sessionStatsRef: MutableRefObject<SessionStats>;
@@ -354,7 +354,7 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
     currentModelProvider,
     effectiveContextWindowSize,
     emittedIdsRef,
-    extensionAdapter,
+    modAdapter,
     firstUserQueryRef,
     flushPendingReasoningEffort,
     generateConversationDescription,
@@ -580,25 +580,23 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
       }
 
       const isSlashCommand = userTextForInput.startsWith("/");
-      const parsedExtensionCommand = isSlashCommand
-        ? parseExtensionSlashCommand(userTextForInput.trim())
+      const parsedModCommand = isSlashCommand
+        ? parseModSlashCommand(userTextForInput.trim())
         : null;
-      const parsedSlashCommandName = parsedExtensionCommand?.command ?? null;
+      const parsedSlashCommandName = parsedModCommand?.command ?? null;
       const matchedCustomCommand = parsedSlashCommandName
         ? await findCustomCommandByName(parsedSlashCommandName)
         : undefined;
-      const matchedExtensionCommand = parsedSlashCommandName
-        ? extensionAdapter.registry?.commands[parsedSlashCommandName]
+      const matchedModCommand = parsedSlashCommandName
+        ? modAdapter.registry?.commands[parsedSlashCommandName]
         : undefined;
       // Interactive/non-state slash commands bypass queueing so menus stay responsive
       // while the agent is busy. Overlay writes are still deferred via queuedOverlayAction.
       const shouldBypassQueue =
         isSlashCommand &&
         shouldSlashCommandBypassQueue(userTextForInput, {
           hasCustomCommand: Boolean(matchedCustomCommand),
-          ...(matchedExtensionCommand
-            ? { extensionCommand: matchedExtensionCommand }
-            : {}),
+          ...(matchedModCommand ? { modCommand: matchedModCommand } : {}),
         });
 
       if (isAgentBusy() && isSlashCommand && !shouldBypassQueue) {
@@ -632,7 +630,7 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
       if (aliasedMsg.startsWith("/")) {
         const trimmed = aliasedMsg.trim();
 
-        // Custom commands and extension commands override built-ins.
+        // Custom commands and mod commands override built-ins.
         if (matchedCustomCommand) {
           const { substituteArguments, expandBashCommands } = await import(
             "@/cli/commands/custom.js"
@@ -692,69 +690,66 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
           return { submitted: true };
         }
 
-        if (parsedExtensionCommand && matchedExtensionCommand) {
-          const showInTranscript = matchedExtensionCommand.showInTranscript;
-          const shouldLockCommand = !matchedExtensionCommand.runWhenBusy;
+        if (parsedModCommand && matchedModCommand) {
+          const showInTranscript = matchedModCommand.showInTranscript;
+          const shouldLockCommand = !matchedModCommand.runWhenBusy;
           const cmd = showInTranscript
             ? commandRunner.start(
                 trimmed,
-                `Running /${matchedExtensionCommand.id}...`,
+                `Running /${matchedModCommand.id}...`,
               )
             : null;
           const getFeedbackCommand = () =>
             cmd ??
-            commandRunner.start(
-              trimmed,
-              `Running /${matchedExtensionCommand.id}...`,
-            );
+            commandRunner.start(trimmed, `Running /${matchedModCommand.id}...`);
           if (shouldLockCommand) {
             setCommandRunning(true);
           }
 
           try {
-            const extensionContext = extensionAdapter.getContext();
+            const modContext = modAdapter.getContext();
             const cwd = getCurrentWorkingDirectory();
-            const conversation = createExtensionConversationHandle({
+            const conversation = createModConversationHandle({
               agentId,
-              backend: extensionAdapter.getBackend(),
+              backend: modAdapter.getBackend(),
               conversationId: conversationIdRef.current,
               sendMessageStream: sendMessageStreamWithBackend,
               workingDirectory: cwd,
             });
-            const commandContext: ExtensionCommandContext = {
+            const commandContext: ModCommandContext = {
               agent: { id: agentId, name: agentName },
-              args: parsedExtensionCommand.args,
-              argv: parseExtensionCommandArgv(parsedExtensionCommand.args),
-              command: parsedExtensionCommand.command,
+              args: parsedModCommand.args,
+              argv: parseModCommandArgv(parsedModCommand.args),
+              command: parsedModCommand.command,
               conversation: { ...conversation, id: conversationIdRef.current },
               cwd,
-              getContext: extensionAdapter.getContext,
+              getContext: modAdapter.getContext,
               model: {
                 id:
                   currentModelId ??
                   llmConfigRef.current?.model ??
-                  extensionContext.model.id,
-                displayName: extensionContext.model.displayName,
+                  modContext.model.id,
+                displayName: modContext.model.displayName,
               },
-              permissionMode: extensionContext.permissionMode,
+              permissionMode: modContext.permissionMode,
               rawInput: trimmed,
             };
-            const result = await runExtensionCommandWithTimeout(
-              matchedExtensionCommand,
+            const result = await runModCommandWithTimeout(
+              matchedModCommand,
               commandContext,
             );
 
             if (result.type === "prompt") {
               if (!showInTranscript) {
                 getFeedbackCommand().fail(
-                  `/${matchedExtensionCommand.id} returned a prompt with showInTranscript: false. Hidden extension commands must return output or handled and own their UI.`,
+                  `/${matchedModCommand.id} returned a prompt with showInTranscript: false. Hidden mod commands must return output or handled and own their UI.`,
                 );
                 return { submitted: true };
               }
 
-              if (matchedExtensionCommand.runWhenBusy && isAgentBusy()) {
+              if (matchedModCommand.runWhenBusy && isAgentBusy()) {
                 getFeedbackCommand().fail(
-                  `/${matchedExtensionCommand.id} returned a prompt while the agent is running. Busy-safe extension commands must handle their own SDK calls or return output.`,
+                  `/${matchedModCommand.id} returned a prompt while the agent is running. Busy-safe mod commands must handle their own SDK calls or return output.`,
                 );
                 return { submitted: true };
               }
@@ -763,17 +758,17 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
                 await checkPendingApprovalsForSlashCommand();
               if (approvalCheck.blocked) {
                 getFeedbackCommand().fail(
-                  `Pending approval(s). Resolve approvals before running /${matchedExtensionCommand.id}.`,
+                  `Pending approval(s). Resolve approvals before running /${matchedModCommand.id}.`,
                 );
                 return { submitted: false };
               }
 
-              cmd?.finish(`Running /${matchedExtensionCommand.id}...`, true);
+              cmd?.finish(`Running /${matchedModCommand.id}...`, true);
               await processConversationWithQueuedApprovals([
                 {
                   type: "message",
                   role: "user",
-                  content: buildTextParts(buildExtensionCommandPrompt(result)),
+                  content: buildTextParts(buildModCommandPrompt(result)),
                   otid: randomUUID(),
                 },
               ]);
@@ -788,7 +783,7 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
           } catch (error) {
             const errorDetails = formatErrorDetails(error, agentId);
             getFeedbackCommand().fail(
-              `Failed to run /${matchedExtensionCommand.id}: ${errorDetails}`,
+              `Failed to run /${matchedModCommand.id}: ${errorDetails}`,
             );
           } finally {
             if (shouldLockCommand) {
@@ -980,15 +975,15 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
           if (onReload) {
             const cmd = commandRunner.start(
               "/reload",
-              "Reloading settings and local extensions...",
+              "Reloading settings and local mods...",
             );
             setCommandRunning(true);
             // Defer the reload to let the command UI render first
             setTimeout(() => {
               void (async () => {
                 try {
                   await onReload();
-                  cmd.finish("Reloaded settings and local extensions", true);
+                  cmd.finish("Reloaded settings and local mods", true);
                 } catch (error) {
                   const errorDetails = formatErrorDetails(error, agentId);
                   cmd.fail(`Failed: ${errorDetails}`);
@@ -1257,7 +1252,7 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
               },
             );
             const request = args
-              ? `The user ran \`/statusline ${args}\`. Use the loaded skill to help them create, edit, or migrate their Letta Code statusline extension.`
+              ? `The user ran \`/statusline ${args}\`. Use the loaded skill to help them create, edit, or migrate their Letta Code statusline mod.`
               : "The user ran `/statusline` without arguments. Use the loaded skill's bare `/statusline` behavior.";
 
             cmd.finish("Running statusline setup...", true);
@@ -1632,7 +1627,7 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
               })
               .catch(() => {});
             sessionHooksRanRef.current = true;
-            void extensionAdapter.events.emit("conversation_open", {
+            void modAdapter.events.emit("conversation_open", {
               agentId,
               agentName: agentName ?? null,
               conversationId: conversation.id,
@@ -1730,7 +1725,7 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
               })
               .catch(() => {});
             sessionHooksRanRef.current = true;
-            void extensionAdapter.events.emit("conversation_open", {
+            void modAdapter.events.emit("conversation_open", {
               agentId,
               agentName: agentName ?? null,
               conversationId: forked.id,
@@ -1846,7 +1841,7 @@ export function useSubmitHandler(ctx: SubmitHandlerContext) {
               })
               .catch(() => {});
             sessionHooksRanRef.current = true;
-            void extensionAdapter.events.emit("conversation_open", {
+            void modAdapter.events.emit("conversation_open", {
               agentId,
               agentName: agentName ?? null,
               conversationId: conversation.id,
@@ -3538,7 +3533,7 @@ ${SYSTEM_REMINDER_CLOSE}
       conversationId,
       currentModelHandle,
       currentModelId,
-      extensionAdapter,
+      modAdapter,
       effectiveContextWindowSize,
       commandRunner,
       handleExit,
diff --git a/src/cli/args.ts b/src/cli/args.ts
--- a/src/cli/args.ts
+++ b/src/cli/args.ts
@@ -266,12 +266,12 @@ export const CLI_FLAG_CATALOG = {
         "Disable first-turn environment reminder (device/git/cwd context)",
     },
   },
-  "no-extensions": {
+  "no-mods": {
     parser: { type: "boolean" },
     mode: "both",
     help: {
-      description: "Disable local extensions for this session",
-      continuationLines: ["Recovery alias: LETTA_DISABLE_EXTENSIONS=1 letta"],
+      description: "Disable local mods for this session",
+      continuationLines: ["Recovery alias: LETTA_DISABLE_MODS=1 letta"],
     },
   },
   "reflection-trigger": {
@@ -381,7 +381,11 @@ export function renderCliOptionsHelp(): string {
 }
 
 export function preprocessCliArgs(args: string[]): string[] {
-  return args.map((arg) => (arg === "--conv" ? "--conversation" : arg));
+  return args.map((arg) => {
+    if (arg === "--conv") return "--conversation";
+    if (arg === "--no-extensions") return "--no-mods";
+    return arg;
+  });
 }
 
 export function parseCliArgs(args: string[], strict: boolean) {
diff --git a/src/cli/commands/registry.ts b/src/cli/commands/registry.ts
--- a/src/cli/commands/registry.ts
+++ b/src/cli/commands/registry.ts
@@ -289,7 +289,7 @@ export const commands: Record<string, Command> = {
     },
   },
   "/reload": {
-    desc: "Reload settings and local extensions",
+    desc: "Reload settings and local mods",
     order: 27.2,
     noArgs: true,
     handler: () => {
diff --git a/src/cli/components/InputAssist.tsx b/src/cli/components/InputAssist.tsx
--- a/src/cli/components/InputAssist.tsx
+++ b/src/cli/components/InputAssist.tsx
@@ -4,7 +4,7 @@ import type { ModelReasoningEffort } from "@/agent/model";
 import { AgentInfoBar } from "./AgentInfoBar";
 import { FileAutocomplete } from "./FileAutocomplete";
 import { SlashCommandAutocomplete } from "./SlashCommandAutocomplete";
-import type { ExtensionCommandAutocompleteItem } from "./types/autocomplete";
+import type { ModCommandAutocompleteItem } from "./types/autocomplete";
 
 interface InputAssistProps {
   currentInput: string;
@@ -21,7 +21,7 @@ interface InputAssistProps {
   serverUrl?: string;
   workingDirectory?: string;
   conversationId?: string;
-  extensionCommands?: Record<string, ExtensionCommandAutocompleteItem>;
+  modCommands?: Record<string, ModCommandAutocompleteItem>;
 }
 
 /**
@@ -45,7 +45,7 @@ export function InputAssist({
   serverUrl,
   workingDirectory,
   conversationId,
-  extensionCommands,
+  modCommands,
 }: InputAssistProps) {
   const showFileAutocomplete = currentInput.includes("@");
   const showCommandAutocomplete =
@@ -87,7 +87,7 @@ export function InputAssist({
           onActiveChange={onAutocompleteActiveChange}
           agentId={agentId}
           workingDirectory={workingDirectory}
-          extensionCommands={extensionCommands}
+          modCommands={modCommands}
         />
         <AgentInfoBar
           agentId={agentId}
diff --git a/src/cli/components/InputRich.tsx b/src/cli/components/InputRich.tsx
--- a/src/cli/components/InputRich.tsx
+++ b/src/cli/components/InputRich.tsx
@@ -23,8 +23,6 @@ import {
   getBuiltinStatuslineRenderer,
 } from "@/cli/display/statusline/registry";
 import { buildDefaultStatuslineParts } from "@/cli/display/statusline/renderers/Default";
-import { evaluateLocalExtensionStatuses } from "@/cli/extensions/local-extension-loader";
-import type { LocalExtensionAdapter } from "@/cli/extensions/use-local-extension-adapter";
 import { bytesToTokens, formatCompact } from "@/cli/helpers/format";
 import { CLI_GLYPHS } from "@/cli/helpers/glyphs";
 import { formatGoalStatusIndicator } from "@/cli/helpers/goal-command";
@@ -36,6 +34,8 @@ import type { StatusLinePayload } from "@/cli/helpers/status-line-payload";
 import { getRandomThinkingTip } from "@/cli/helpers/thinking-messages";
 import { useShimmerAnimation } from "@/cli/hooks/use-shimmer-animation";
 import { useTokenSmoothing } from "@/cli/hooks/use-token-smoothing";
+import { evaluateLocalModStatuses } from "@/cli/mods/local-mod-loader";
+import type { LocalModAdapter } from "@/cli/mods/use-local-mod-adapter";
 import {
   ELAPSED_DISPLAY_THRESHOLD_MS,
   TOKEN_DISPLAY_THRESHOLD,
@@ -47,8 +47,8 @@ import { settingsManager } from "@/settings-manager";
 import { debugLog } from "@/utils/debug";
 import type { QueuedMessage } from "@/utils/message-queue-bridge";
 import { colors } from "./colors";
-import { ExtensionPanelRow } from "./ExtensionPanelRow";
 import { InputAssist } from "./InputAssist";
+import { ModPanelRow } from "./ModPanelRow";
 import { PasteAwareTextInput } from "./PasteAwareTextInput";
 import { ProductStatusRow } from "./ProductStatusRow";
 import { QueuedMessages } from "./QueuedMessages";
@@ -440,7 +440,7 @@ function BlankStatuslineRow({
 
 /**
  * Bottom statusline slot. Safety states and transient host hints may preempt the
- * row; otherwise custom extensions own the idle row before the built-in default.
+ * row; otherwise custom mods own the idle row before the built-in default.
  */
 const StatuslineSlot = memo(function StatuslineSlot({
   ctrlCPressed,
@@ -458,7 +458,7 @@ const StatuslineSlot = memo(function StatuslineSlot({
   hideFooter,
   rightColumnWidth,
   statusLinePayload,
-  extensionAdapter,
+  modAdapter,
   transientHint,
 }: {
   ctrlCPressed: boolean;
@@ -476,7 +476,7 @@ const StatuslineSlot = memo(function StatuslineSlot({
   hideFooter: boolean;
   rightColumnWidth: number;
   statusLinePayload: StatusLinePayload;
-  extensionAdapter: LocalExtensionAdapter;
+  modAdapter: LocalModAdapter;
   transientHint?: StatuslineTransientHint | null;
 }) {
   const hideFooterContent = hideFooter;
@@ -500,24 +500,23 @@ const StatuslineSlot = memo(function StatuslineSlot({
   });
   const statuslineContext = {
     ...baseStatuslineContext,
-    statuses: evaluateLocalExtensionStatuses(
-      extensionAdapter.registry,
+    statuses: evaluateLocalModStatuses(
+      modAdapter.registry,
       baseStatuslineContext,
     ),
   };
-  extensionAdapter.updateContext(statuslineContext);
+  modAdapter.updateContext(statuslineContext);
 
   const builtInStatuslineRenderer = getBuiltinStatuslineRenderer(
     DEFAULT_STATUSLINE_RENDERER_ID,
   );
   const localStatuslineRenderer =
-    extensionAdapter.registry?.ui.statuslineRenderer ?? null;
-  const extensionStatuslineLoading =
-    extensionAdapter.isLoading &&
-    (extensionAdapter.hasExtensionSources ||
-      extensionAdapter.hadStatuslineRenderer);
+    modAdapter.registry?.ui.statuslineRenderer ?? null;
+  const modStatuslineLoading =
+    modAdapter.isLoading &&
+    (modAdapter.hasModSources || modAdapter.hadStatuslineRenderer);
   const customStatuslineActive = Boolean(
-    localStatuslineRenderer || extensionStatuslineLoading,
+    localStatuslineRenderer || modStatuslineLoading,
   );
   const idleSlotAvailable = !hideFooterContent && !preemption && !transientHint;
 
@@ -526,15 +525,15 @@ const StatuslineSlot = memo(function StatuslineSlot({
       return localStatuslineRenderer.render(statuslineContext);
     } catch (error) {
       debugLog(
-        "extensions",
+        "mods",
         "statusline renderer %s failed: %s",
         localStatuslineRenderer.id,
         error instanceof Error ? error.message : String(error),
       );
     }
   }
 
-  if (idleSlotAvailable && extensionStatuslineLoading) {
+  if (idleSlotAvailable && modStatuslineLoading) {
     return <BlankStatuslineRow rightColumnWidth={rightColumnWidth} />;
   }
 
@@ -929,7 +928,7 @@ export function Input({
   terminalWidth,
   shouldAnimate = true,
   statusLinePayload,
-  extensionAdapter,
+  modAdapter,
   statusLinePrompt,
   onCycleReasoningEffort,
   footerNotification,
@@ -982,7 +981,7 @@ export function Input({
   terminalWidth: number;
   shouldAnimate?: boolean;
   statusLinePayload: StatusLinePayload;
-  extensionAdapter: LocalExtensionAdapter;
+  modAdapter: LocalModAdapter;
   statusLinePrompt?: string;
   onCycleReasoningEffort?: () => void;
   footerNotification?: string | null;
@@ -1928,8 +1927,8 @@ export function Input({
         {interactionEnabled ? (
           <Box flexDirection="column">
             {!suppressDividers && (
-              <ExtensionPanelRow
-                panels={extensionAdapter.registry?.ui.panels}
+              <ModPanelRow
+                panels={modAdapter.registry?.ui.panels}
                 terminalWidth={terminalWidth}
               />
             )}
@@ -2012,7 +2011,7 @@ export function Input({
                 serverUrl={serverUrl}
                 workingDirectory={process.cwd()}
                 conversationId={conversationId}
-                extensionCommands={extensionAdapter.registry?.commands}
+                modCommands={modAdapter.registry?.commands}
               />
             )}
 
@@ -2038,7 +2037,7 @@ export function Input({
                 hideFooter={hideFooter}
                 rightColumnWidth={footerRightColumnWidth}
                 statusLinePayload={statusLinePayload}
-                extensionAdapter={extensionAdapter}
+                modAdapter={modAdapter}
                 transientHint={statuslineTransientHint}
               />
             )}
@@ -2087,7 +2086,7 @@ export function Input({
     reserveInputSpace,
     inputChromeHeight,
     statusLinePayload,
-    extensionAdapter,
+    modAdapter,
 
     goalStatusText,
     promptChar,
diff --git a/src/cli/components/ExtensionPanelRow.tsx b/src/cli/components/ModPanelRow.tsx
rename from src/cli/components/ExtensionPanelRow.tsx
rename to src/cli/components/ModPanelRow.tsx
--- a/src/cli/components/ExtensionPanelRow.tsx
+++ b/src/cli/components/ModPanelRow.tsx
@@ -1,31 +1,29 @@
 import { Box } from "ink";
-import type { ExtensionPanel } from "@/cli/extensions/types";
 import { truncateText } from "@/cli/helpers/truncate-text";
+import type { ModPanel } from "@/cli/mods/types";
 import { Text } from "./Text";
 
-const MAX_EXTENSION_PANEL_LINES = 8;
+const MAX_MOD_PANEL_LINES = 8;
 
-function visiblePanels(
-  panels: Record<string, ExtensionPanel>,
-): ExtensionPanel[] {
+function visiblePanels(panels: Record<string, ModPanel>): ModPanel[] {
   return Object.values(panels).sort(
     (a, b) => a.order - b.order || b.updatedAt - a.updatedAt,
   );
 }
 
-export function ExtensionPanelRow({
+export function ModPanelRow({
   panels,
   terminalWidth,
 }: {
-  panels?: Record<string, ExtensionPanel>;
+  panels?: Record<string, ModPanel>;
   terminalWidth: number;
 }) {
   const rowWidth = Math.max(0, terminalWidth - 1);
   if (rowWidth === 0) return null;
 
   const lines = visiblePanels(panels ?? {})
     .flatMap((panel) => panel.content)
-    .slice(0, MAX_EXTENSION_PANEL_LINES);
+    .slice(0, MAX_MOD_PANEL_LINES);
   if (lines.length === 0) return null;
 
   return (
diff --git a/src/cli/components/SlashCommandAutocomplete.tsx b/src/cli/components/SlashCommandAutocomplete.tsx
--- a/src/cli/components/SlashCommandAutocomplete.tsx
+++ b/src/cli/components/SlashCommandAutocomplete.tsx
@@ -68,7 +68,7 @@ export function SlashCommandAutocomplete({
   onActiveChange,
   agentId,
   workingDirectory = process.cwd(),
-  extensionCommands = {},
+  modCommands = {},
 }: AutocompleteProps) {
   const columns = useTerminalWidth();
   const terminalRows = useTerminalRows();
@@ -163,29 +163,27 @@ export function SlashCommandAutocomplete({
       }
     }
 
-    const extensionCommandMatches: CommandMatch[] = Object.values(
-      extensionCommands,
-    ).map((command) => ({
-      cmd: `/${command.id}`,
-      desc: `${command.description}${command.args ? ` ${command.args}` : ""} (extension)`,
-      order: command.order,
-    }));
+    const modCommandMatches: CommandMatch[] = Object.values(modCommands).map(
+      (command) => ({
+        cmd: `/${command.id}`,
+        desc: `${command.description}${command.args ? ` ${command.args}` : ""} (mod)`,
+        order: command.order,
+      }),
+    );
 
     const customCommandNames = new Set(customCommands.map((cmd) => cmd.cmd));
-    const extensionCommandNames = new Set(
-      extensionCommandMatches.map((cmd) => cmd.cmd),
-    );
+    const modCommandNames = new Set(modCommandMatches.map((cmd) => cmd.cmd));
     const visibleBuiltins = builtins.filter(
       (cmd) =>
-        !customCommandNames.has(cmd.cmd) && !extensionCommandNames.has(cmd.cmd),
+        !customCommandNames.has(cmd.cmd) && !modCommandNames.has(cmd.cmd),
     );
-    const visibleExtensionCommands = extensionCommandMatches.filter(
+    const visibleModCommands = modCommandMatches.filter(
       (cmd) => !customCommandNames.has(cmd.cmd),
     );
 
     const reservedCommands = new Set([
       ...visibleBuiltins.map((cmd) => cmd.cmd),
-      ...visibleExtensionCommands.map((cmd) => cmd.cmd),
+      ...visibleModCommands.map((cmd) => cmd.cmd),
       ...customCommands.map((cmd) => cmd.cmd),
     ]);
     const visibleSkillCommands = skillCommands.filter(
@@ -195,17 +193,11 @@ export function SlashCommandAutocomplete({
     // Merge command sources and sort by order.
     return [
       ...visibleBuiltins,
-      ...visibleExtensionCommands,
+      ...visibleModCommands,
       ...customCommands,
       ...visibleSkillCommands,
     ].sort((a, b) => (a.order ?? 100) - (b.order ?? 100));
-  }, [
-    agentId,
-    workingDirectory,
-    extensionCommands,
-    customCommands,
-    skillCommands,
-  ]);
+  }, [agentId, workingDirectory, modCommands, customCommands, skillCommands]);
 
   const queryInfo = useMemo(
     () => extractSearchQuery(currentInput, cursorPosition),
diff --git a/src/cli/components/types/autocomplete.ts b/src/cli/components/types/autocomplete.ts
--- a/src/cli/components/types/autocomplete.ts
+++ b/src/cli/components/types/autocomplete.ts
@@ -2,7 +2,7 @@
  * Shared types for autocomplete components
  */
 
-export interface ExtensionCommandAutocompleteItem {
+export interface ModCommandAutocompleteItem {
   id: string;
   description: string;
   args?: string;
@@ -27,8 +27,8 @@ export interface AutocompleteProps {
   agentId?: string;
   /** Working directory for local pin status checking */
   workingDirectory?: string;
-  /** Slash commands registered by trusted local extensions */
-  extensionCommands?: Record<string, ExtensionCommandAutocompleteItem>;
+  /** Slash commands registered by trusted local mods */
+  modCommands?: Record<string, ModCommandAutocompleteItem>;
 }
 
 /**
diff --git a/src/cli/display/statusline/types.ts b/src/cli/display/statusline/types.ts
--- a/src/cli/display/statusline/types.ts
+++ b/src/cli/display/statusline/types.ts
@@ -1,7 +1,7 @@
 import type { ReactNode } from "react";
 import type * as DisplayComponents from "@/cli/display/DisplayComponents";
 import type { StatusLinePayload } from "@/cli/helpers/status-line-payload";
-import type { ExtensionContext } from "@/extensions/types";
+import type { ModContext } from "@/mods/types";
 
 export interface StatuslineUiContext {
   currentModelProvider: string | null;
@@ -13,7 +13,7 @@ export interface StatuslineUiContext {
   rightColumnWidth: number;
 }
 
-export interface StatuslineRenderContext extends ExtensionContext {
+export interface StatuslineRenderContext extends ModContext {
   rawPayload: StatusLinePayload;
   components: typeof DisplayComponents;
   statuses: Record<string, string>;
diff --git a/src/cli/extensions/local-extension-loader.ts b/src/cli/extensions/local-extension-loader.ts
deleted file mode 100644
--- a/src/cli/extensions/local-extension-loader.ts
+++ /dev/null
@@ -1,102 +0,0 @@
-import { commands as builtinCommands } from "@/cli/commands/registry";
-import type { CreateExtensionAdapterOptions } from "@/extensions/extension-adapter";
-import { createExtensionAdapter as createExtensionAdapterBase } from "@/extensions/extension-adapter";
-import type {
-  CreateExtensionEngineOptions,
-  LoadLocalExtensionsOptions,
-} from "@/extensions/extension-engine";
-import {
-  createExtensionEngine as createExtensionEngineBase,
-  disposeLocalExtensions,
-  EXTENSION_CACHE_DIRECTORY,
-  emitLocalExtensionEvent,
-  evaluateLocalExtensionStatuses,
-  GLOBAL_EXTENSIONS_DIRECTORY,
-  loadLocalExtensions as loadLocalExtensionsBase,
-  resolveLocalExtensionSources,
-} from "@/extensions/extension-engine";
-import type { ExtensionCapabilities } from "@/extensions/types";
-import { getAllLettaToolNames, getServerToolName } from "@/tools/manager";
-import { TUI_EXTENSION_CAPABILITIES } from "./capabilities";
-
-function stripSlash(command: string): string {
-  return command.startsWith("/") ? command.slice(1) : command;
-}
-
-function getDefaultBuiltinCommandIds(): Set<string> {
-  return new Set(Object.keys(builtinCommands).map(stripSlash));
-}
-
-function getDefaultReservedToolNames(): Set<string> {
-  const reserved = new Set<string>();
-  for (const toolName of getAllLettaToolNames()) {
-    reserved.add(toolName);
-    reserved.add(getServerToolName(toolName));
-  }
-  return reserved;
-}
-
-function withDefaultReservations<
-  T extends {
-    builtinCommandIds?: Iterable<string>;
-    capabilities?: ExtensionCapabilities;
-    reservedToolNames?: Iterable<string>;
-  },
->(options: T): T {
-  return {
-    ...options,
-    builtinCommandIds: [
-      ...getDefaultBuiltinCommandIds(),
-      ...(options.builtinCommandIds ?? []),
-    ],
-    capabilities: options.capabilities ?? TUI_EXTENSION_CAPABILITIES,
-    reservedToolNames: [
-      ...getDefaultReservedToolNames(),
-      ...(options.reservedToolNames ?? []),
-    ],
-  };
-}
-
-export function createExtensionEngine(options: CreateExtensionEngineOptions) {
-  return createExtensionEngineBase(withDefaultReservations(options));
-}
-
-export function createExtensionAdapter(options: CreateExtensionAdapterOptions) {
-  return createExtensionAdapterBase(withDefaultReservations(options));
-}
-
-export function loadLocalExtensions(options: LoadLocalExtensionsOptions) {
-  return loadLocalExtensionsBase(withDefaultReservations(options));
-}
-
-export {
-  EXTENSION_CACHE_DIRECTORY,
-  GLOBAL_EXTENSIONS_DIRECTORY,
-  disposeLocalExtensions,
-  emitLocalExtensionEvent,
-  evaluateLocalExtensionStatuses,
-  resolveLocalExtensionSources,
-};
-
-export type {
-  CreateExtensionAdapterOptions,
-  ExtensionAdapter,
-  ExtensionAdapterLoadState,
-  ExtensionAdapterSnapshot,
-} from "@/extensions/extension-adapter";
-export type {
-  CreateExtensionEngineOptions,
-  ExtensionEngine,
-  ExtensionStatusValue,
-  LettaExtensionApi,
-  LettaExtensionDisposer,
-  LettaExtensionFactory,
-  LoadLocalExtensionsOptions,
-  LocalExtensionDisposer,
-  LocalExtensionRegistry,
-  LocalExtensionSource,
-  LocalExtensionUiRegistry,
-  ResolveLocalExtensionSourcesOptions,
-  StatuslineRenderFunction,
-} from "@/extensions/extension-engine";
-export { TUI_EXTENSION_CAPABILITIES } from "./capabilities";
diff --git a/src/cli/extensions/types.ts b/src/cli/extensions/types.ts
deleted file mode 100644
--- a/src/cli/extensions/types.ts
+++ /dev/null
@@ -1,58 +0,0 @@
-export type {
-  ExtensionAgentContext,
-  ExtensionBackgroundAgentContext,
-  ExtensionCapabilities,
-  ExtensionCapabilityKind,
-  ExtensionCapabilityRecord,
-  ExtensionCommand,
-  ExtensionCommandContext,
-  ExtensionCommandRegistration,
-  ExtensionCommandResult,
-  ExtensionContext,
-  ExtensionContextWindowContext,
-  ExtensionConversationCloseEvent,
-  ExtensionConversationCloseReason,
-  ExtensionConversationForkOptions,
-  ExtensionConversationHandle,
-  ExtensionConversationHistoryOptions,
-  ExtensionConversationMessage,
-  ExtensionConversationOpenEvent,
-  ExtensionConversationOpenReason,
-  ExtensionConversationSendMessageOptions,
-  ExtensionConversationSendMessageRequestOptions,
-  ExtensionCostContext,
-  ExtensionDiagnostic,
-  ExtensionDiagnosticPhase,
-  ExtensionEventCapabilities,
-  ExtensionEventContext,
-  ExtensionEventEmissionResult,
-  ExtensionEventHandler,
-  ExtensionEventMap,
-  ExtensionEventName,
-  ExtensionEventRegistration,
-  ExtensionEventResultMap,
-  ExtensionMemfsContext,
-  ExtensionModelContext,
-  ExtensionOwner,
-  ExtensionPanel,
-  ExtensionPanelContent,
-  ExtensionPanelHandle,
-  ExtensionPanelOptions,
-  ExtensionPanelUpdate,
-  ExtensionReflectionContext,
-  ExtensionSourceScope,
-  ExtensionTokenUsageContext,
-  ExtensionTool,
-  ExtensionToolContent,
-  ExtensionToolContentImage,
-  ExtensionToolContentText,
-  ExtensionToolRegistration,
-  ExtensionToolRunContext,
-  ExtensionToolRunResult,
-  ExtensionToolStartEvent,
-  ExtensionToolStartResult,
-  ExtensionTurnStartEvent,
-  ExtensionTurnStartResult,
-  ExtensionUiCapabilities,
-  ExtensionWorkspaceContext,
-} from "@/extensions/types";
diff --git a/src/cli/helpers/status-line-payload.ts b/src/cli/helpers/status-line-payload.ts
--- a/src/cli/helpers/status-line-payload.ts
+++ b/src/cli/helpers/status-line-payload.ts
@@ -35,7 +35,7 @@ export interface StatusLinePayloadBuildInput {
 }
 
 /**
- * Shared payload for built-in and extension statusline renderers.
+ * Shared payload for built-in and mod statusline renderers.
  *
  * Unsupported fields are set to null to keep the renderer context stable.
  */
diff --git a/src/cli/extensions/capabilities.ts b/src/cli/mods/capabilities.ts
rename from src/cli/extensions/capabilities.ts
rename to src/cli/mods/capabilities.ts
--- a/src/cli/extensions/capabilities.ts
+++ b/src/cli/mods/capabilities.ts
@@ -1,6 +1,6 @@
-import type { ExtensionCapabilities } from "@/extensions/types";
+import type { ModCapabilities } from "@/mods/types";
 
-export const TUI_EXTENSION_CAPABILITIES: ExtensionCapabilities = {
+export const TUI_MOD_CAPABILITIES: ModCapabilities = {
   tools: true,
   commands: true,
   events: {
diff --git a/src/cli/extensions/command-runtime.ts b/src/cli/mods/command-runtime.ts
rename from src/cli/extensions/command-runtime.ts
rename to src/cli/mods/command-runtime.ts
--- a/src/cli/extensions/command-runtime.ts
+++ b/src/cli/mods/command-runtime.ts
@@ -1,13 +1,9 @@
 import { SYSTEM_REMINDER_CLOSE, SYSTEM_REMINDER_OPEN } from "@/constants";
-import type {
-  ExtensionCommand,
-  ExtensionCommandContext,
-  ExtensionCommandResult,
-} from "./types";
+import type { ModCommand, ModCommandContext, ModCommandResult } from "./types";
 
-const EXTENSION_COMMAND_TIMEOUT_MS = 30_000;
+const MOD_COMMAND_TIMEOUT_MS = 30_000;
 
-export function parseExtensionSlashCommand(trimmed: string): {
+export function parseModSlashCommand(trimmed: string): {
   command: string;
   args: string;
 } | null {
@@ -22,7 +18,7 @@ export function parseExtensionSlashCommand(trimmed: string): {
   };
 }
 
-export function parseExtensionCommandArgv(args: string): string[] {
+export function parseModCommandArgv(args: string): string[] {
   const argv: string[] = [];
   let current = "";
   let quote: '"' | "'" | null = null;
@@ -74,12 +70,10 @@ export function parseExtensionCommandArgv(args: string): string[] {
   return argv;
 }
 
-export function normalizeExtensionCommandResult(
-  result: unknown,
-): ExtensionCommandResult {
+export function normalizeModCommandResult(result: unknown): ModCommandResult {
   if (!result || typeof result !== "object" || !("type" in result)) {
     throw new Error(
-      "Extension command must return { type: 'prompt' | 'output' | 'handled' }",
+      "Mod command must return { type: 'prompt' | 'output' | 'handled' }",
     );
   }
 
@@ -92,7 +86,7 @@ export function normalizeExtensionCommandResult(
   };
   if (typed.type === "prompt") {
     if (typeof typed.content !== "string") {
-      throw new Error("Extension command prompt result requires content");
+      throw new Error("Mod command prompt result requires content");
     }
     return {
       type: "prompt",
@@ -104,7 +98,7 @@ export function normalizeExtensionCommandResult(
   }
   if (typed.type === "output") {
     if (typeof typed.output !== "string") {
-      throw new Error("Extension command output result requires output");
+      throw new Error("Mod command output result requires output");
     }
     return {
       type: "output",
@@ -116,12 +110,10 @@ export function normalizeExtensionCommandResult(
     return { type: "handled" };
   }
 
-  throw new Error(
-    `Unknown extension command result type: ${String(typed.type)}`,
-  );
+  throw new Error(`Unknown mod command result type: ${String(typed.type)}`);
 }
 
-export function buildExtensionCommandPrompt(result: {
+export function buildModCommandPrompt(result: {
   content: string;
   systemReminder?: boolean;
 }): string {
@@ -131,24 +123,24 @@ export function buildExtensionCommandPrompt(result: {
   return `${SYSTEM_REMINDER_OPEN}\n${result.content}\n${SYSTEM_REMINDER_CLOSE}`;
 }
 
-export async function runExtensionCommandWithTimeout(
-  command: ExtensionCommand,
-  context: ExtensionCommandContext,
-): Promise<ExtensionCommandResult> {
+export async function runModCommandWithTimeout(
+  command: ModCommand,
+  context: ModCommandContext,
+): Promise<ModCommandResult> {
   let timeout: ReturnType<typeof setTimeout> | null = null;
   try {
-    return normalizeExtensionCommandResult(
+    return normalizeModCommandResult(
       await Promise.race([
         Promise.resolve(command.run(context)),
         new Promise<never>((_, reject) => {
           timeout = setTimeout(
             () =>
               reject(
                 new Error(
-                  `Extension command timed out after ${EXTENSION_COMMAND_TIMEOUT_MS}ms`,
+                  `Mod command timed out after ${MOD_COMMAND_TIMEOUT_MS}ms`,
                 ),
               ),
-            EXTENSION_COMMAND_TIMEOUT_MS,
+            MOD_COMMAND_TIMEOUT_MS,
           );
         }),
       ]),
diff --git a/src/cli/mods/local-mod-loader.ts b/src/cli/mods/local-mod-loader.ts
new file mode 100644
--- /dev/null
+++ b/src/cli/mods/local-mod-loader.ts
@@ -0,0 +1,102 @@
+import { commands as builtinCommands } from "@/cli/commands/registry";
+import type { CreateModAdapterOptions } from "@/mods/mod-adapter";
+import { createModAdapter as createModAdapterBase } from "@/mods/mod-adapter";
+import type {
+  CreateModEngineOptions,
+  LoadLocalModsOptions,
+} from "@/mods/mod-engine";
+import {
+  createModEngine as createModEngineBase,
+  disposeLocalMods,
+  emitLocalModEvent,
+  evaluateLocalModStatuses,
+  GLOBAL_MODS_DIRECTORY,
+  loadLocalMods as loadLocalModsBase,
+  MOD_CACHE_DIRECTORY,
+  resolveLocalModSources,
+} from "@/mods/mod-engine";
+import type { ModCapabilities } from "@/mods/types";
+import { getAllLettaToolNames, getServerToolName } from "@/tools/manager";
+import { TUI_MOD_CAPABILITIES } from "./capabilities";
+
+function stripSlash(command: string): string {
+  return command.startsWith("/") ? command.slice(1) : command;
+}
+
+function getDefaultBuiltinCommandIds(): Set<string> {
+  return new Set(Object.keys(builtinCommands).map(stripSlash));
+}
+
+function getDefaultReservedToolNames(): Set<string> {
+  const reserved = new Set<string>();
+  for (const toolName of getAllLettaToolNames()) {
+    reserved.add(toolName);
+    reserved.add(getServerToolName(toolName));
+  }
+  return reserved;
+}
+
+function withDefaultReservations<
+  T extends {
+    builtinCommandIds?: Iterable<string>;
+    capabilities?: ModCapabilities;
+    reservedToolNames?: Iterable<string>;
+  },
+>(options: T): T {
+  return {
+    ...options,
+    builtinCommandIds: [
+      ...getDefaultBuiltinCommandIds(),
+      ...(options.builtinCommandIds ?? []),
+    ],
+    capabilities: options.capabilities ?? TUI_MOD_CAPABILITIES,
+    reservedToolNames: [
+      ...getDefaultReservedToolNames(),
+      ...(options.reservedToolNames ?? []),
+    ],
+  };
+}
+
+export function createModEngine(options: CreateModEngineOptions) {
+  return createModEngineBase(withDefaultReservations(options));
+}
+
+export function createModAdapter(options: CreateModAdapterOptions) {
+  return createModAdapterBase(withDefaultReservations(options));
+}
+
+export function loadLocalMods(options: LoadLocalModsOptions) {
+  return loadLocalModsBase(withDefaultReservations(options));
+}
+
+export {
+  MOD_CACHE_DIRECTORY,
+  GLOBAL_MODS_DIRECTORY,
+  disposeLocalMods,
+  emitLocalModEvent,
+  evaluateLocalModStatuses,
+  resolveLocalModSources,
+};
+
+export type {
+  CreateModAdapterOptions,
+  ModAdapter,
+  ModAdapterLoadState,
+  ModAdapterSnapshot,
+} from "@/mods/mod-adapter";
+export type {
+  CreateModEngineOptions,
+  LettaModApi,
+  LettaModDisposer,
+  LettaModFactory,
+  LoadLocalModsOptions,
+  LocalModDisposer,
+  LocalModRegistry,
+  LocalModSource,
+  LocalModUiRegistry,
+  ModEngine,
+  ModStatusValue,
+  ResolveLocalModSourcesOptions,
+  StatuslineRenderFunction,
+} from "@/mods/mod-engine";
+export { TUI_MOD_CAPABILITIES } from "./capabilities";
diff --git a/src/cli/mods/types.ts b/src/cli/mods/types.ts
new file mode 100644
--- /dev/null
+++ b/src/cli/mods/types.ts
@@ -0,0 +1,58 @@
+export type {
+  ModAgentContext,
+  ModBackgroundAgentContext,
+  ModCapabilities,
+  ModCapabilityKind,
+  ModCapabilityRecord,
+  ModCommand,
+  ModCommandContext,
+  ModCommandRegistration,
+  ModCommandResult,
+  ModContext,
+  ModContextWindowContext,
+  ModConversationCloseEvent,
+  ModConversationCloseReason,
+  ModConversationForkOptions,
+  ModConversationHandle,
+  ModConversationHistoryOptions,
+  ModConversationMessage,
+  ModConversationOpenEvent,
+  ModConversationOpenReason,
+  ModConversationSendMessageOptions,
+  ModConversationSendMessageRequestOptions,
+  ModCostContext,
+  ModDiagnostic,
+  ModDiagnosticPhase,
+  ModEventCapabilities,
+  ModEventContext,
+  ModEventEmissionResult,
+  ModEventHandler,
+  ModEventMap,
+  ModEventName,
+  ModEventRegistration,
+  ModEventResultMap,
+  ModMemfsContext,
+  ModModelContext,
+  ModOwner,
+  ModPanel,
+  ModPanelContent,
+  ModPanelHandle,
+  ModPanelOptions,
+  ModPanelUpdate,
+  ModReflectionContext,
+  ModSourceScope,
+  ModTokenUsageContext,
+  ModTool,
+  ModToolContent,
+  ModToolContentImage,
+  ModToolContentText,
+  ModToolRegistration,
+  ModToolRunContext,
+  ModToolRunResult,
+  ModToolStartEvent,
+  ModToolStartResult,
+  ModTurnStartEvent,
+  ModTurnStartResult,
+  ModUiCapabilities,
+  ModWorkspaceContext,
+} from "@/mods/types";
diff --git a/src/cli/extensions/use-local-extension-adapter.ts b/src/cli/mods/use-local-mod-adapter.ts
rename from src/cli/extensions/use-local-extension-adapter.ts
rename to src/cli/mods/use-local-mod-adapter.ts
--- a/src/cli/extensions/use-local-extension-adapter.ts
+++ b/src/cli/mods/use-local-mod-adapter.ts
@@ -2,33 +2,33 @@ import { useEffect, useMemo, useSyncExternalStore } from "react";
 import { getBackend } from "@/backend";
 import { getClient } from "@/backend/api/client";
 import {
-  createExtensionAdapter,
-  type ExtensionAdapter,
-  type ExtensionAdapterSnapshot,
-} from "./local-extension-loader";
-import type { ExtensionContext } from "./types";
+  createModAdapter,
+  type ModAdapter,
+  type ModAdapterSnapshot,
+} from "./local-mod-loader";
+import type { ModContext } from "./types";
 
-export interface LocalExtensionAdapter {
-  events: ExtensionAdapter["events"];
-  getBackend: ExtensionAdapter["getBackend"];
-  getContext: () => ExtensionContext;
+export interface LocalModAdapter {
+  events: ModAdapter["events"];
+  getBackend: ModAdapter["getBackend"];
+  getContext: () => ModContext;
   hadStatuslineRenderer: boolean; // Used to prevent flicker on reload
-  hasExtensionSources: boolean;
-  engine: ExtensionAdapter["engine"];
+  hasModSources: boolean;
+  engine: ModAdapter["engine"];
   isLoading: boolean;
-  registry: ExtensionAdapterSnapshot["registry"];
+  registry: ModAdapterSnapshot["registry"];
   reload: () => Promise<void>;
-  updateContext: (context: ExtensionContext) => void;
+  updateContext: (context: ModContext) => void;
 }
 
-export function useLocalExtensionAdapter(
-  initialContext: ExtensionContext,
+export function useLocalModAdapter(
+  initialContext: ModContext,
   options: { disabled?: boolean } = {},
-): LocalExtensionAdapter {
+): LocalModAdapter {
   // biome-ignore lint/correctness/useExhaustiveDependencies: the adapter is process-local; context updates are pushed through updateContext below.
   const adapter = useMemo(
     () =>
-      createExtensionAdapter({
+      createModAdapter({
         disabled: options.disabled,
         getBackend,
         getClient,
@@ -61,7 +61,7 @@ export function useLocalExtensionAdapter(
       getBackend: adapter.getBackend,
       getContext: adapter.getContext,
       hadStatuslineRenderer: snapshot.hadStatuslineRenderer,
-      hasExtensionSources: snapshot.hasExtensionSources,
+      hasModSources: snapshot.hasModSources,
       engine: adapter.engine,
       isLoading: snapshot.isLoading,
       registry: snapshot.registry,
diff --git a/src/extensions/disable.ts b/src/extensions/disable.ts
deleted file mode 100644
--- a/src/extensions/disable.ts
+++ /dev/null
@@ -1,26 +0,0 @@
-export const LETTA_DISABLE_EXTENSIONS_ENV = "LETTA_DISABLE_EXTENSIONS";
-
-function isTruthyEnvFlag(value: string | undefined): boolean {
-  if (!value) return false;
-  const normalized = value.trim().toLowerCase();
-  return ["1", "true", "yes", "on"].includes(normalized);
-}
-
-export function areExtensionsDisabled(
-  env: NodeJS.ProcessEnv = process.env,
-): boolean {
-  return isTruthyEnvFlag(env[LETTA_DISABLE_EXTENSIONS_ENV]);
-}
-
-export function shouldDisableExtensions(options?: {
-  cliFlag?: boolean;
-  env?: NodeJS.ProcessEnv;
-}): boolean {
-  return Boolean(
-    options?.cliFlag || areExtensionsDisabled(options?.env ?? process.env),
-  );
-}
-
-export function disableExtensionsForProcess(): void {
-  process.env[LETTA_DISABLE_EXTENSIONS_ENV] = "1";
-}
diff --git a/src/extensions/event-emitter.ts b/src/extensions/event-emitter.ts
deleted file mode 100644
--- a/src/extensions/event-emitter.ts
+++ /dev/null
@@ -1,33 +0,0 @@
-import type {
-  ExtensionEventEmissionResult,
-  ExtensionEventMap,
-  ExtensionEventName,
-} from "@/extensions/types";
-
-// Narrow event capability exposed by the extension adapter. Adapter-owned
-// implementations are guarded, so lower layers can emit events without
-// depending on adapter lifecycle or registry APIs.
-export type ExtensionEvents = {
-  emit: <TName extends ExtensionEventName>(
-    name: TName,
-    event: ExtensionEventMap[TName],
-  ) => Promise<ExtensionEventEmissionResult<TName>>;
-};
-
-export function emptyEventEmissionResult<TName extends ExtensionEventName>(
-  name: TName,
-): ExtensionEventEmissionResult<TName> {
-  return { diagnostics: [], handlerCount: 0, name, results: [] };
-}
-
-export async function emitExtensionEvent<TName extends ExtensionEventName>(
-  events: ExtensionEvents | undefined,
-  name: TName,
-  event: ExtensionEventMap[TName],
-): Promise<ExtensionEventEmissionResult<TName>> {
-  if (!events) {
-    return emptyEventEmissionResult(name);
-  }
-
-  return events.emit(name, event);
-}
diff --git a/src/extensions/extension-diagnostics-file.ts b/src/extensions/extension-diagnostics-file.ts
deleted file mode 100644
--- a/src/extensions/extension-diagnostics-file.ts
+++ /dev/null
@@ -1,46 +0,0 @@
-import { mkdirSync, writeFileSync } from "node:fs";
-import { homedir } from "node:os";
-import path from "node:path";
-import {
-  createExtensionDiagnosticsReport,
-  type ExtensionDiagnosticsReport,
-} from "@/extensions/extension-diagnostics";
-import type { ExtensionDiagnostic } from "@/extensions/types";
-
-export interface ExtensionDiagnosticsFile {
-  generatedAt: number;
-  report: ExtensionDiagnosticsReport;
-}
-
-export function getDefaultExtensionDiagnosticsRoot(
-  homeDirectory = homedir(),
-): string {
-  return path.join(homeDirectory, ".letta", "extensions", "diagnostics");
-}
-
-export function getExtensionDiagnosticsLatestFilePath(
-  rootDirectory = getDefaultExtensionDiagnosticsRoot(),
-): string {
-  return path.join(rootDirectory, "latest.json");
-}
-
-function createExtensionDiagnosticsFile(
-  diagnostics: readonly ExtensionDiagnostic[],
-  generatedAt = Date.now(),
-): ExtensionDiagnosticsFile {
-  return {
-    generatedAt,
-    report: createExtensionDiagnosticsReport(diagnostics),
-  };
-}
-
-export function writeExtensionDiagnosticsLatestFile(
-  diagnostics: readonly ExtensionDiagnostic[],
-  options: { generatedAt?: number; rootDirectory?: string } = {},
-): ExtensionDiagnosticsFile {
-  const file = createExtensionDiagnosticsFile(diagnostics, options.generatedAt);
-  const filePath = getExtensionDiagnosticsLatestFilePath(options.rootDirectory);
-  mkdirSync(path.dirname(filePath), { recursive: true });
-  writeFileSync(filePath, `${JSON.stringify(file, null, 2)}\n`, "utf-8");
-  return file;
-}
diff --git a/src/extensions/extension-diagnostics.ts b/src/extensions/extension-diagnostics.ts
deleted file mode 100644
--- a/src/extensions/extension-diagnostics.ts
+++ /dev/null
@@ -1,152 +0,0 @@
-import type {
-  ExtensionDiagnostic,
-  ExtensionDiagnosticPhase,
-  ExtensionDiagnosticSeverity,
-  ExtensionOwner,
-} from "@/extensions/types";
-
-export type { ExtensionDiagnosticSeverity } from "@/extensions/types";
-
-export const EXTENSION_DIAGNOSTICS_MAX_COUNT = 200;
-export const EXTENSION_DIAGNOSTICS_RESET_COUNT = 50;
-
-export interface ExtensionDiagnosticCollector {
-  diagnostics: ExtensionDiagnostic[];
-}
-
-export interface ExtensionDiagnosticReportEntry {
-  capability?: ExtensionDiagnostic["capability"];
-  errorName: string;
-  extension: ExtensionOwner;
-  message: string;
-  phase: ExtensionDiagnosticPhase;
-  severity: ExtensionDiagnosticSeverity;
-  stack?: string;
-  timestamp: number;
-}
-
-export interface ExtensionDiagnosticsReport {
-  diagnostics: ExtensionDiagnosticReportEntry[];
-  errorCount: number;
-  warningCount: number;
-}
-
-export function getExtensionDiagnosticSeverity(
-  phase: ExtensionDiagnosticPhase,
-  severity?: ExtensionDiagnosticSeverity,
-): ExtensionDiagnosticSeverity {
-  switch (phase) {
-    case "command_override":
-      return "warning";
-    case "report":
-      return severity ?? "error";
-    default:
-      return "error";
-  }
-}
-
-export function isExtensionDiagnosticErrorPhase(
-  phase: ExtensionDiagnosticPhase,
-): boolean {
-  return getExtensionDiagnosticSeverity(phase) === "error";
-}
-
-export function isExtensionDiagnosticError(
-  diagnostic: Pick<ExtensionDiagnostic, "phase" | "severity">,
-): boolean {
-  return (
-    getExtensionDiagnosticSeverity(diagnostic.phase, diagnostic.severity) ===
-    "error"
-  );
-}
-
-export function getExtensionErrorDiagnostics(
-  diagnostics: readonly ExtensionDiagnostic[],
-): ExtensionDiagnostic[] {
-  return diagnostics.filter(isExtensionDiagnosticError);
-}
-
-export function createExtensionDiagnosticsReport(
-  diagnostics: readonly ExtensionDiagnostic[],
-): ExtensionDiagnosticsReport {
-  let errorCount = 0;
-  let warningCount = 0;
-
-  const entries = diagnostics.map((diagnostic) => {
-    const severity = getExtensionDiagnosticSeverity(
-      diagnostic.phase,
-      diagnostic.severity,
-    );
-    if (severity === "error") {
-      errorCount += 1;
-    } else {
-      warningCount += 1;
-    }
-
-    return {
-      ...(diagnostic.capability
-        ? { capability: { ...diagnostic.capability } }
-        : {}),
-      errorName: diagnostic.error.name,
-      extension: { ...diagnostic.owner },
-      message: diagnostic.error.message,
-      phase: diagnostic.phase,
-      severity,
-      ...(diagnostic.error.stack ? { stack: diagnostic.error.stack } : {}),
-      timestamp: diagnostic.timestamp,
-    } satisfies ExtensionDiagnosticReportEntry;
-  });
-
-  return {
-    diagnostics: entries,
-    errorCount,
-    warningCount,
-  };
-}
-
-export function appendExtensionDiagnostic(
-  collector: ExtensionDiagnosticCollector,
-  diagnostic: ExtensionDiagnostic,
-): void {
-  collector.diagnostics.push(diagnostic);
-  if (collector.diagnostics.length > EXTENSION_DIAGNOSTICS_MAX_COUNT) {
-    collector.diagnostics.splice(
-      0,
-      collector.diagnostics.length - EXTENSION_DIAGNOSTICS_RESET_COUNT,
-    );
-  }
-}
-
-export function recordExtensionDiagnostic(
-  collector: ExtensionDiagnosticCollector,
-  diagnostic: Omit<ExtensionDiagnostic, "timestamp">,
-  onDiagnostic?: (diagnostic: ExtensionDiagnostic) => void,
-): ExtensionDiagnostic {
-  const completeDiagnostic: ExtensionDiagnostic = {
-    ...diagnostic,
-    timestamp: Date.now(),
-  };
-  appendExtensionDiagnostic(collector, completeDiagnostic);
-  onDiagnostic?.(completeDiagnostic);
-  return completeDiagnostic;
-}
-
-export function recordStaleHandleUse(
-  collector: ExtensionDiagnosticCollector,
-  owner: ExtensionOwner,
-  capability: ExtensionDiagnostic["capability"],
-  onDiagnostic?: (diagnostic: ExtensionDiagnostic) => void,
-): ExtensionDiagnostic {
-  return recordExtensionDiagnostic(
-    collector,
-    {
-      capability,
-      error: new Error(
-        `Ignored stale extension handle for ${capability?.kind ?? "capability"}${capability?.id ? ` '${capability.id}'` : ""}`,
-      ),
-      owner,
-      phase: "stale_handle",
-    },
-    onDiagnostic,
-  );
-}
diff --git a/src/extensions/permission-registry.ts b/src/extensions/permission-registry.ts
deleted file mode 100644
--- a/src/extensions/permission-registry.ts
+++ /dev/null
@@ -1,165 +0,0 @@
-import type {
-  ExtensionContext,
-  ExtensionOwner,
-  ExtensionPermission,
-  ExtensionPermissionCheckEvent,
-  ExtensionPermissionCheckResult,
-} from "@/extensions/types";
-import { areExtensionsDisabled } from "./disable";
-
-const EXTENSION_PERMISSIONS_KEY = Symbol.for("@letta/extensionPermissions");
-
-type GlobalWithExtensionPermissions = typeof globalThis & {
-  [EXTENSION_PERMISSIONS_KEY]?: Map<string, ExtensionPermissionDefinition>;
-};
-
-export interface ExtensionPermissionDefinition extends ExtensionPermission {
-  activationSignal: AbortSignal;
-  getContext: () => ExtensionContext;
-  isAvailable: () => boolean;
-}
-
-export interface ExtensionPermissionDecisionResult {
-  decision: "allow" | "ask" | "deny";
-  matchedRule: string;
-  reason?: string;
-}
-
-function getMutableExtensionPermissionsRegistry(): Map<
-  string,
-  ExtensionPermissionDefinition
-> {
-  const global = globalThis as GlobalWithExtensionPermissions;
-  if (!global[EXTENSION_PERMISSIONS_KEY]) {
-    global[EXTENSION_PERMISSIONS_KEY] = new Map();
-  }
-  return global[EXTENSION_PERMISSIONS_KEY];
-}
-
-export function getAvailableExtensionPermissionsRegistry(): Map<
-  string,
-  ExtensionPermissionDefinition
-> {
-  if (areExtensionsDisabled()) return new Map();
-
-  return new Map(
-    Array.from(getMutableExtensionPermissionsRegistry().entries()).filter(
-      ([, permission]) => {
-        if (permission.activationSignal.aborted) return false;
-        try {
-          return permission.isAvailable();
-        } catch {
-          return false;
-        }
-      },
-    ),
-  );
-}
-
-export function registerExtensionPermission(
-  permission: ExtensionPermissionDefinition,
-): void {
-  if (areExtensionsDisabled()) return;
-  getMutableExtensionPermissionsRegistry().set(permission.id, permission);
-}
-
-export function unregisterExtensionPermission(
-  id: string,
-  owner: ExtensionOwner,
-): void {
-  const registry = getMutableExtensionPermissionsRegistry();
-  const existing = registry.get(id);
-  if (existing?.owner?.id === owner.id) {
-    registry.delete(id);
-  }
-}
-
-export function unregisterExtensionPermissionsForOwner(
-  owner: ExtensionOwner,
-): void {
-  const registry = getMutableExtensionPermissionsRegistry();
-  for (const [id, permission] of registry.entries()) {
-    if (permission.owner?.id === owner.id) {
-      registry.delete(id);
-    }
-  }
-}
-
-export function clearExtensionPermissions(): void {
-  getMutableExtensionPermissionsRegistry().clear();
-}
-
-export function getExtensionPermissionDefinition(
-  id: string,
-  registry: Map<
-    string,
-    ExtensionPermissionDefinition
-  > = getMutableExtensionPermissionsRegistry(),
-): ExtensionPermissionDefinition | undefined {
-  if (areExtensionsDisabled()) return undefined;
-  return registry.get(id);
-}
-
-function normalizePermissionResult(
-  result: ExtensionPermissionCheckResult,
-): ExtensionPermissionCheckResult {
-  if (result === undefined) return undefined;
-  if (
-    result.decision === "allow" ||
-    result.decision === "ask" ||
-    result.decision === "deny"
-  ) {
-    return result;
-  }
-  return undefined;
-}
-
-function composePermissionDecision(
-  decisions: ExtensionPermissionDecisionResult[],
-): ExtensionPermissionDecisionResult | undefined {
-  return (
-    decisions.find((result) => result.decision === "deny") ??
-    decisions.find((result) => result.decision === "ask") ??
-    decisions.find((result) => result.decision === "allow")
-  );
-}
-
-export async function checkExtensionPermissions(
-  event: ExtensionPermissionCheckEvent,
-  registry: Map<
-    string,
-    ExtensionPermissionDefinition
-  > = getAvailableExtensionPermissionsRegistry(),
-): Promise<ExtensionPermissionDecisionResult | undefined> {
-  if (areExtensionsDisabled()) return undefined;
-
-  const decisions: ExtensionPermissionDecisionResult[] = [];
-  for (const permission of registry.values()) {
-    if (permission.activationSignal.aborted) continue;
-
-    let rawResult: ExtensionPermissionCheckResult;
-    try {
-      if (!permission.isAvailable()) continue;
-      rawResult = await permission.check(event, {
-        getContext: permission.getContext,
-        signal: permission.activationSignal,
-      });
-    } catch (error) {
-      return {
-        decision: "deny",
-        matchedRule: `extension permission:${permission.id}`,
-        reason: `Extension permission '${permission.id}' failed: ${error instanceof Error ? error.message : String(error)}`,
-      };
-    }
-
-    const result = normalizePermissionResult(rawResult);
-    if (!result) continue;
-    decisions.push({
-      decision: result.decision,
-      matchedRule: `extension permission:${permission.id}`,
-      reason: result.reason,
-    });
-  }
-
-  return composePermissionDecision(decisions);
-}
diff --git a/src/extensions/tool-registry.ts b/src/extensions/tool-registry.ts
deleted file mode 100644
--- a/src/extensions/tool-registry.ts
+++ /dev/null
@@ -1,122 +0,0 @@
-import type {
-  ExtensionOwner,
-  ExtensionTool,
-  ExtensionToolRunContext,
-  ExtensionToolRunResult,
-} from "@/extensions/types";
-import { areExtensionsDisabled } from "./disable";
-
-const EXTENSION_TOOLS_KEY = Symbol.for("@letta/extensionTools");
-
-type GlobalWithExtensionTools = typeof globalThis & {
-  [EXTENSION_TOOLS_KEY]?: Map<string, ExtensionToolDefinition>;
-};
-
-export interface ExtensionToolDefinition extends ExtensionTool {
-  activationSignal: AbortSignal;
-  getContext: ExtensionToolRunContext["getContext"];
-  isAvailable: () => boolean;
-}
-
-function getMutableExtensionToolsRegistry(): Map<
-  string,
-  ExtensionToolDefinition
-> {
-  const global = globalThis as GlobalWithExtensionTools;
-  if (!global[EXTENSION_TOOLS_KEY]) {
-    global[EXTENSION_TOOLS_KEY] = new Map();
-  }
-  return global[EXTENSION_TOOLS_KEY];
-}
-
-export function getAvailableExtensionToolsRegistry(): Map<
-  string,
-  ExtensionToolDefinition
-> {
-  if (areExtensionsDisabled()) return new Map();
-
-  return new Map(
-    Array.from(getMutableExtensionToolsRegistry().entries()).filter(
-      ([, tool]) => {
-        if (tool.activationSignal.aborted) return false;
-        try {
-          return tool.isAvailable();
-        } catch {
-          return false;
-        }
-      },
-    ),
-  );
-}
-
-export function registerExtensionTool(tool: ExtensionToolDefinition): void {
-  if (areExtensionsDisabled()) return;
-  getMutableExtensionToolsRegistry().set(tool.name, tool);
-}
-
-export function unregisterExtensionTool(
-  name: string,
-  owner: ExtensionOwner,
-): void {
-  const registry = getMutableExtensionToolsRegistry();
-  const existing = registry.get(name);
-  if (existing?.owner?.id === owner.id) {
-    registry.delete(name);
-  }
-}
-
-export function unregisterExtensionToolsForOwner(owner: ExtensionOwner): void {
-  const registry = getMutableExtensionToolsRegistry();
-  for (const [name, tool] of registry.entries()) {
-    if (tool.owner?.id === owner.id) {
-      registry.delete(name);
-    }
-  }
-}
-
-export function clearExtensionTools(): void {
-  getMutableExtensionToolsRegistry().clear();
-}
-
-export function getExtensionToolDefinition(
-  name: string,
-  registry: Map<
-    string,
-    ExtensionToolDefinition
-  > = getMutableExtensionToolsRegistry(),
-): ExtensionToolDefinition | undefined {
-  if (areExtensionsDisabled()) return undefined;
-  return registry.get(name);
-}
-
-export function extensionToolRequiresApproval(
-  name: string,
-  registry: Map<
-    string,
-    ExtensionToolDefinition
-  > = getMutableExtensionToolsRegistry(),
-): boolean | undefined {
-  if (areExtensionsDisabled()) return undefined;
-  return registry.get(name)?.requiresApproval;
-}
-
-export function isExtensionToolParallelSafe(
-  name: string,
-  registry: Map<
-    string,
-    ExtensionToolDefinition
-  > = getMutableExtensionToolsRegistry(),
-): boolean {
-  if (areExtensionsDisabled()) return false;
-  return registry.get(name)?.parallelSafe === true;
-}
-
-export async function runExtensionTool(
-  tool: ExtensionToolDefinition,
-  context: ExtensionToolRunContext,
-): Promise<ExtensionToolRunResult> {
-  if (tool.activationSignal.aborted) {
-    throw new Error(`Extension tool '${tool.name}' is no longer available`);
-  }
-  return tool.run(context);
-}
diff --git a/src/extensions/types.ts b/src/extensions/types.ts
deleted file mode 100644
--- a/src/extensions/types.ts
+++ /dev/null
@@ -1,505 +0,0 @@
-import type { MessageCreate } from "@letta-ai/letta-client/resources/agents/agents";
-import type {
-  ApprovalCreate,
-  LettaStreamingResponse,
-  Message,
-} from "@letta-ai/letta-client/resources/agents/messages";
-
-export interface ExtensionWorkspaceContext {
-  cwd: string;
-  currentDir: string;
-  projectDir: string;
-}
-
-export interface ExtensionModelContext {
-  id: string | null;
-  displayName: string | null;
-  provider: string | null;
-  reasoningEffort: string | null;
-}
-
-export interface ExtensionTokenUsageContext {
-  inputTokens: number | null;
-  outputTokens: number | null;
-  cacheCreationInputTokens: number | null;
-  cacheReadInputTokens: number | null;
-}
-
-export interface ExtensionContextWindowContext {
-  size: number;
-  totalInputTokens: number;
-  totalOutputTokens: number;
-  usedPercentage: number | null;
-  remainingPercentage: number | null;
-  currentUsage: ExtensionTokenUsageContext | null;
-}
-
-export interface ExtensionCostContext {
-  totalDurationMs: number;
-  totalApiDurationMs: number;
-  totalCostUsd: number | null;
-  totalLinesAdded: number | null;
-  totalLinesRemoved: number | null;
-}
-
-export interface ExtensionAgentContext {
-  id: string | null;
-  name: string | null;
-}
-
-export interface ExtensionReflectionContext {
-  mode: "off" | "step-count" | "compaction-event" | null;
-  stepCount: number;
-}
-
-export interface ExtensionMemfsContext {
-  enabled: boolean;
-  memoryDir: string | null;
-}
-
-export interface ExtensionBackgroundAgentContext {
-  type: string;
-  status: string;
-  durationMs: number;
-}
-
-export interface ExtensionUiCapabilities {
-  panels: boolean;
-  statusValues: boolean;
-  customStatuslineRenderer: boolean;
-}
-
-export interface ExtensionEventCapabilities {
-  lifecycle: boolean;
-  tools: boolean;
-  turns: boolean;
-}
-
-export interface ExtensionCapabilities {
-  tools: boolean;
-  commands: boolean;
-  events: ExtensionEventCapabilities;
-  permissions: boolean;
-  providers: boolean;
-  ui: ExtensionUiCapabilities;
-}
-
-export interface ExtensionConversationForkOptions {
-  hidden?: boolean;
-}
-
-export type ExtensionConversationMessage = MessageCreate | ApprovalCreate;
-
-export interface ExtensionConversationSendMessageOptions {
-  background?: boolean;
-  overrideModel?: string;
-  skipImageNormalization?: boolean;
-  streamTokens?: boolean;
-  workingDirectory?: string;
-}
-
-export interface ExtensionConversationSendMessageRequestOptions {
-  headers?: Record<string, string>;
-  maxRetries?: number;
-  signal?: AbortSignal;
-}
-
-export interface ExtensionConversationHistoryOptions {
-  /** Maximum number of recent messages to return. Defaults to 100. */
-  limit?: number;
-  /** Return chronological (asc, default) or newest-first (desc) messages. */
-  order?: "asc" | "desc";
-  /** Include error messages and error statuses. Defaults to true. */
-  includeErrors?: boolean;
-}
-
-export interface ExtensionConversationHandle {
-  id: string | null;
-  fork: (
-    options?: ExtensionConversationForkOptions,
-  ) => Promise<ExtensionConversationHandle>;
-  getHistory: (
-    options?: ExtensionConversationHistoryOptions,
-  ) => Promise<Message[]>;
-  sendMessageStream: (
-    messages: ExtensionConversationMessage[],
-    options?: ExtensionConversationSendMessageOptions,
-    requestOptions?: ExtensionConversationSendMessageRequestOptions,
-  ) => Promise<AsyncIterable<LettaStreamingResponse>>;
-}
-
-export type ExtensionSourceScope = "global" | "project" | "bundled";
-
-export interface ExtensionOwner {
-  id: string;
-  path: string;
-  scope: ExtensionSourceScope;
-  generation: number;
-}
-
-export type ExtensionEventName =
-  | "conversation_open"
-  | "conversation_close"
-  | "tool_start"
-  | "turn_start";
-
-export type ExtensionConversationOpenReason =
-  | "startup"
-  | "new"
-  | "resume"
-  | "fork"
-  | "reload";
-
-export type ExtensionConversationCloseReason =
-  | "quit"
-  | "new"
-  | "resume"
-  | "fork"
-  | "reload";
-
-export interface ExtensionConversationOpenEvent {
-  agentId: string | null;
-  agentName: string | null;
-  conversationId: string | null;
-  previousConversationId?: string | null;
-  reason: ExtensionConversationOpenReason;
-}
-
-export interface ExtensionConversationCloseEvent {
-  agentId: string | null;
-  conversationId: string | null;
-  durationMs: number | null;
-  messageCount: number | null;
-  reason: ExtensionConversationCloseReason;
-  toolCallCount: number | null;
-}
-
-export interface ExtensionTurnStartEvent {
-  agentId: string | null;
-  conversationId: string | null;
-  input: Array<MessageCreate | ApprovalCreate>;
-}
-
-export interface ExtensionTurnStartResult {
-  input?: Array<MessageCreate | ApprovalCreate>;
-}
-
-export interface ExtensionToolStartEvent {
-  agentId: string | null;
-  conversationId: string | null;
-  toolCallId: string | null;
-  toolName: string;
-  args: Record<string, unknown>;
-}
-
-export interface ExtensionToolStartResult {
-  args?: Record<string, unknown>;
-}
-
-export interface ExtensionEventMap {
-  conversation_open: ExtensionConversationOpenEvent;
-  conversation_close: ExtensionConversationCloseEvent;
-  tool_start: ExtensionToolStartEvent;
-  turn_start: ExtensionTurnStartEvent;
-}
-
-export interface ExtensionEventResultMap {
-  conversation_open: undefined;
-  conversation_close: undefined;
-  tool_start: ExtensionToolStartResult | undefined;
-  turn_start: ExtensionTurnStartResult | undefined;
-}
-
-export interface ExtensionEventContext {
-  conversation: ExtensionConversationHandle;
-  context: ExtensionContext;
-  getContext: () => ExtensionContext;
-  signal: AbortSignal;
-}
-
-export type ExtensionEventHandler<
-  TName extends ExtensionEventName = ExtensionEventName,
-> = (
-  event: ExtensionEventMap[TName],
-  context: ExtensionEventContext,
-) => ExtensionEventResultMap[TName] | Promise<ExtensionEventResultMap[TName]>;
-
-export interface ExtensionEventRegistration<
-  TName extends ExtensionEventName = ExtensionEventName,
-> {
-  handler: ExtensionEventHandler<TName>;
-  name: TName;
-  owner: ExtensionOwner;
-}
-
-export interface ExtensionEventEmissionResult<
-  TName extends ExtensionEventName = ExtensionEventName,
-> {
-  diagnostics: ExtensionDiagnostic[];
-  handlerCount: number;
-  name: TName;
-  results: Array<NonNullable<ExtensionEventResultMap[TName]>>;
-}
-
-export type ExtensionCapabilityKind =
-  | "command"
-  | "event"
-  | "permission"
-  | "provider"
-  | "tool"
-  | "panel"
-  | "status"
-  | "statusline";
-
-export interface ExtensionCapabilityRecord<T> {
-  id: string;
-  kind: ExtensionCapabilityKind;
-  owner: ExtensionOwner;
-  value: T;
-  createdAt: number;
-}
-
-export type ExtensionDiagnosticPhase =
-  | "transpile"
-  | "import"
-  | "activate"
-  | "command_override"
-  | "dispose"
-  | "event"
-  | "report"
-  | "stale_handle";
-
-export type ExtensionDiagnosticSeverity = "error" | "warning";
-
-export interface ExtensionDiagnosticReportOptions {
-  message: string;
-  severity?: ExtensionDiagnosticSeverity;
-}
-
-export interface ExtensionDiagnostic {
-  capability?: {
-    id: string;
-    kind: ExtensionCapabilityKind;
-  };
-  error: Error;
-  owner: ExtensionOwner;
-  phase: ExtensionDiagnosticPhase;
-  severity?: ExtensionDiagnosticSeverity;
-  timestamp: number;
-}
-
-export interface ExtensionContext {
-  app: {
-    version: string;
-  };
-  workspace: ExtensionWorkspaceContext;
-  cwd: string;
-  sessionId: string | null;
-  lastRunId: string | null;
-  agent: ExtensionAgentContext;
-  model: ExtensionModelContext;
-  toolset: string | null;
-  systemPromptId: string | null;
-  permissionMode: string | null;
-  networkPhase: "upload" | "download" | "error" | null;
-  terminalWidth: number | null;
-  contextWindow: ExtensionContextWindowContext;
-  cost: ExtensionCostContext;
-  reflection: ExtensionReflectionContext;
-  memfs: ExtensionMemfsContext;
-  backgroundAgents: ExtensionBackgroundAgentContext[];
-}
-
-export interface ExtensionCommandContext {
-  rawInput: string;
-  command: string;
-  args: string;
-  argv: string[];
-  cwd: string;
-  agent: {
-    id: string;
-    name: string | null;
-  };
-  conversation: ExtensionConversationHandle & { id: string };
-  model: {
-    id: string | null;
-    displayName: string | null;
-  };
-  permissionMode: string | null;
-  getContext: () => ExtensionContext;
-}
-
-export type ExtensionCommandResult =
-  | { type: "prompt"; content: string; systemReminder?: boolean }
-  | { type: "output"; output: string; success?: boolean }
-  | { type: "handled" };
-
-export type ExtensionPanelContent = string | string[];
-
-export interface ExtensionPanelOptions {
-  content?: ExtensionPanelContent;
-  id: string;
-  order?: number;
-}
-
-export interface ExtensionPanelUpdate {
-  content?: ExtensionPanelContent;
-  order?: number;
-}
-
-export interface ExtensionPanel {
-  content: string[];
-  id: string;
-  owner?: ExtensionOwner;
-  order: number;
-  path: string;
-  updatedAt: number;
-}
-
-export interface ExtensionPanelHandle {
-  close: () => void;
-  update: (update: ExtensionPanelUpdate) => void;
-}
-
-export interface ExtensionCommandRegistration {
-  id: string;
-  description: string;
-  args?: string;
-  order?: number;
-  override?: boolean;
-  runWhenBusy?: boolean;
-  showInTranscript?: boolean;
-  run: (
-    context: ExtensionCommandContext,
-  ) => ExtensionCommandResult | Promise<ExtensionCommandResult>;
-}
-
-export interface ExtensionCommand {
-  id: string;
-  description: string;
-  args?: string;
-  owner?: ExtensionOwner;
-  order: number;
-  path: string;
-  runWhenBusy: boolean;
-  showInTranscript: boolean;
-  run: ExtensionCommandRegistration["run"];
-}
-
-export interface ExtensionToolContentText {
-  type: "text";
-  text: string;
-}
-
-export interface ExtensionToolContentImage {
-  type: "image";
-  source: {
-    type: "base64";
-    media_type: string;
-    data: string;
-  };
-}
-
-export type ExtensionToolContent =
-  | ExtensionToolContentText
-  | ExtensionToolContentImage;
-
-export type ExtensionToolRunResult =
-  | string
-  | ExtensionToolContent[]
-  | {
-      content?: string | ExtensionToolContent[];
-      output?: string;
-      stdout?: string[];
-      stderr?: string[];
-      status?: "success" | "error";
-      isError?: boolean;
-      success?: boolean;
-    };
-
-export interface ExtensionToolRunContext {
-  args: Record<string, unknown>;
-  cwd: string;
-  workingDirectory: string;
-  toolCallId: string | null;
-  signal: AbortSignal;
-  onOutput?: (chunk: string, stream: "stdout" | "stderr") => void;
-  permissionMode: string | null;
-  agent: {
-    id: string | null;
-  };
-  conversation: ExtensionConversationHandle;
-  getContext: () => ExtensionContext;
-}
-
-export interface ExtensionToolRegistration {
-  name: string;
-  description: string;
-  parameters?: Record<string, unknown>;
-  override?: boolean;
-  requiresApproval?: boolean;
-  parallelSafe?: boolean;
-  isEnabled?: (context: ExtensionContext) => boolean;
-  run: (
-    context: ExtensionToolRunContext,
-  ) => ExtensionToolRunResult | Promise<ExtensionToolRunResult>;
-}
-
-export interface ExtensionTool {
-  name: string;
-  description: string;
-  parameters: Record<string, unknown>;
-  owner?: ExtensionOwner;
-  path: string;
-  requiresApproval: boolean;
-  parallelSafe: boolean;
-  isEnabled?: ExtensionToolRegistration["isEnabled"];
-  run: ExtensionToolRegistration["run"];
-}
-
-export type ExtensionPermissionDecision = "allow" | "ask" | "deny";
-
-export type ExtensionPermissionCheckPhase = "approval" | "execution";
-
-export interface ExtensionPermissionCheckEvent {
-  agentId: string | null;
-  conversationId: string | null;
-  toolCallId: string | null;
-  toolName: string;
-  args: Record<string, unknown>;
-  cwd: string;
-  workingDirectory: string;
-  permissionMode: string | null;
-  phase: ExtensionPermissionCheckPhase;
-}
-
-export type ExtensionPermissionCheckResult =
-  | {
-      decision: ExtensionPermissionDecision;
-      reason?: string;
-    }
-  | undefined;
-
-export interface ExtensionPermissionCheckContext {
-  getContext: () => ExtensionContext;
-  signal: AbortSignal;
-}
-
-export interface ExtensionPermissionRegistration {
-  id: string;
-  description?: string;
-  isEnabled?: (context: ExtensionContext) => boolean;
-  check: (
-    event: ExtensionPermissionCheckEvent,
-    context: ExtensionPermissionCheckContext,
-  ) => ExtensionPermissionCheckResult | Promise<ExtensionPermissionCheckResult>;
-}
-
-export interface ExtensionPermission {
-  id: string;
-  description?: string;
-  owner?: ExtensionOwner;
-  path: string;
-  isEnabled?: ExtensionPermissionRegistration["isEnabled"];
-  check: ExtensionPermissionRegistration["check"];
-}
diff --git a/src/headless-extension-adapter.ts b/src/headless-mod-adapter.ts
rename from src/headless-extension-adapter.ts
rename to src/headless-mod-adapter.ts
--- a/src/headless-extension-adapter.ts
+++ b/src/headless-mod-adapter.ts
@@ -5,21 +5,18 @@ import type { SessionStats } from "@/agent/stats";
 import type { Backend } from "@/backend";
 import { getClient } from "@/backend/api/client";
 import type { ReflectionSettings } from "@/cli/helpers/memory-reminder";
-import {
-  createExtensionAdapter,
-  type ExtensionAdapter,
-} from "@/extensions/extension-adapter";
+import { createModAdapter, type ModAdapter } from "@/mods/mod-adapter";
 import type {
-  ExtensionCapabilities,
-  ExtensionContext,
-  ExtensionConversationOpenReason,
-} from "@/extensions/types";
+  ModCapabilities,
+  ModContext,
+  ModConversationOpenReason,
+} from "@/mods/types";
 import { getCurrentWorkingDirectory } from "@/runtime-context";
 import { settingsManager } from "@/settings-manager";
 import { telemetry } from "@/telemetry";
 import { getVersion } from "@/version";
 
-export const HEADLESS_EXTENSION_CAPABILITIES: ExtensionCapabilities = {
+export const HEADLESS_MOD_CAPABILITIES: ModCapabilities = {
   tools: true,
   commands: false,
   events: {
@@ -44,14 +41,14 @@ function isHeadlessMemfsEnabled(agentId: string): boolean {
   }
 }
 
-export function createHeadlessExtensionContext(options: {
+export function createHeadlessModContext(options: {
   agent: AgentState;
   conversationId: string;
   lastRunId?: string | null;
   permissionMode?: string | null;
   reflectionSettings?: ReflectionSettings;
   sessionStats?: SessionStats | null;
-}): ExtensionContext {
+}): ModContext {
   const cwd = getCurrentWorkingDirectory();
   const modelId = options.agent.llm_config?.model ?? null;
   const modelInfo = modelId ? getModelInfo(modelId) : null;
@@ -128,37 +125,37 @@ export function createHeadlessExtensionContext(options: {
   };
 }
 
-export function createHeadlessExtensionAdapter(options: {
+export function createHeadlessModAdapter(options: {
   agent: AgentState;
   backend: Backend;
   cacheDirectory?: string;
   conversationId: string;
   disabled?: boolean;
-  globalExtensionsDirectory?: string;
+  globalModsDirectory?: string;
   permissionMode?: string | null;
   reflectionSettings?: ReflectionSettings;
   sessionStats?: SessionStats | null;
-}): ExtensionAdapter {
-  return createExtensionAdapter({
+}): ModAdapter {
+  return createModAdapter({
     ...(options.cacheDirectory
       ? { cacheDirectory: options.cacheDirectory }
       : {}),
-    capabilities: HEADLESS_EXTENSION_CAPABILITIES,
+    capabilities: HEADLESS_MOD_CAPABILITIES,
     disabled: options.disabled,
     getBackend: () => options.backend,
     getClient,
-    ...(options.globalExtensionsDirectory
-      ? { globalExtensionsDirectory: options.globalExtensionsDirectory }
+    ...(options.globalModsDirectory
+      ? { globalModsDirectory: options.globalModsDirectory }
       : {}),
-    initialContext: createHeadlessExtensionContext(options),
+    initialContext: createHeadlessModContext(options),
   });
 }
 
 export async function emitHeadlessConversationOpen(options: {
   agent: AgentState;
   conversationId: string;
-  reason: ExtensionConversationOpenReason;
-  adapter: ExtensionAdapter;
+  reason: ModConversationOpenReason;
+  adapter: ModAdapter;
 }): Promise<void> {
   await options.adapter.events.emit("conversation_open", {
     agentId: options.agent.id,
@@ -172,7 +169,7 @@ export async function emitHeadlessConversationClose(options: {
   agent: AgentState;
   conversationId: string;
   durationMs: number | null;
-  adapter: ExtensionAdapter;
+  adapter: ModAdapter;
 }): Promise<void> {
   await options.adapter.events.emit("conversation_close", {
     agentId: options.agent.id,
diff --git a/src/headless.ts b/src/headless.ts
--- a/src/headless.ts
+++ b/src/headless.ts
@@ -101,18 +101,15 @@ import {
 } from "./cli/startup-flag-validation";
 import { SYSTEM_REMINDER_CLOSE, SYSTEM_REMINDER_OPEN } from "./constants";
 import {
-  disableExtensionsForProcess,
-  shouldDisableExtensions,
-} from "./extensions/disable";
-import type { ExtensionAdapter } from "./extensions/extension-adapter";
-import type { ExtensionConversationOpenReason } from "./extensions/types";
-import {
-  createHeadlessExtensionAdapter,
-  createHeadlessExtensionContext,
+  createHeadlessModAdapter,
+  createHeadlessModContext,
   emitHeadlessConversationClose,
   emitHeadlessConversationOpen,
-} from "./headless-extension-adapter";
+} from "./headless-mod-adapter";
 import { computeDiffPreviews } from "./helpers/diff-preview";
+import { disableModsForProcess, shouldDisableMods } from "./mods/disable";
+import type { ModAdapter } from "./mods/mod-adapter";
+import type { ModConversationOpenReason } from "./mods/types";
 import { formatPermissionDenial } from "./permissions/format-denial";
 import { applyStartupPermissionMode } from "./permissions/startup";
 import { QueueRuntime } from "./queue/queue-runtime";
@@ -429,7 +426,7 @@ async function prepareHeadlessToolExecutionContext(params: {
   conversationId: string;
   overrideModel?: string | null;
   cachedAgent?: AgentState | null;
-  extensionEvents?: ExtensionAdapter["events"];
+  modEvents?: ModAdapter["events"];
 }): Promise<{
   preparedToolContext: Awaited<
     ReturnType<typeof prepareToolExecutionContextForScope>
@@ -443,7 +440,7 @@ async function prepareHeadlessToolExecutionContext(params: {
     workingDirectory: getCurrentWorkingDirectory(),
     exclude: ["AskUserQuestion"],
     cachedAgent: params.cachedAgent,
-    extensionEvents: params.extensionEvents,
+    modEvents: params.modEvents,
   });
 
   return {
@@ -467,7 +464,7 @@ async function emitHeadlessTurnStart(options: {
   agent: AgentState;
   conversationId: string;
   input: Array<MessageCreate | ApprovalCreate>;
-  adapter: ExtensionAdapter;
+  adapter: ModAdapter;
 }): Promise<Array<MessageCreate | ApprovalCreate>> {
   try {
     const event = {
@@ -478,7 +475,7 @@ async function emitHeadlessTurnStart(options: {
     await options.adapter.events.emit("turn_start", event);
     return isTurnInputArray(event.input) ? event.input : options.input;
   } catch {
-    // Extension turn_start handlers should not block sending the turn.
+    // Mod turn_start handlers should not block sending the turn.
     return options.input;
   }
 }
@@ -487,12 +484,12 @@ async function sendScopedApprovalMessages(params: {
   agentId: string;
   conversationId: string;
   approvalMessages: Array<MessageCreate | ApprovalCreate>;
-  extensionEvents?: ExtensionAdapter["events"];
+  modEvents?: ModAdapter["events"];
 }): Promise<Awaited<ReturnType<typeof sendMessageStream>>> {
   const approvalToolContext = await prepareHeadlessToolExecutionContext({
     agentId: params.agentId,
     conversationId: params.conversationId,
-    extensionEvents: params.extensionEvents,
+    modEvents: params.modEvents,
   });
 
   return await sendMessageStream(
@@ -546,11 +543,11 @@ export async function handleHeadlessCommand(
 ) {
   const { values, positionals } = parsedArgs;
   telemetry.setSurface(getTerminalTelemetrySurface(true));
-  const extensionsDisabled = shouldDisableExtensions({
-    cliFlag: values["no-extensions"],
+  const modsDisabled = shouldDisableMods({
+    cliFlag: values["no-mods"],
   });
-  if (extensionsDisabled) {
-    disableExtensionsForProcess();
+  if (modsDisabled) {
+    disableModsForProcess();
   }
 
   // Set tool filter if provided (controls which tools are loaded)
@@ -1349,7 +1346,7 @@ export async function handleHeadlessCommand(
 
   // Determine which conversation to use
   let conversationId: string;
-  let conversationOpenReason: ExtensionConversationOpenReason = "startup";
+  let conversationOpenReason: ModConversationOpenReason = "startup";
   let effectiveReflectionSettings: ReflectionSettings;
 
   const isSubagent = process.env.LETTA_CODE_AGENT_ROLE === "subagent";
@@ -1661,25 +1658,25 @@ export async function handleHeadlessCommand(
 
   const sessionStats = new SessionStats();
   const headlessPermissionMode = startupPermissionMode.mode;
-  const headlessExtensionAdapter = createHeadlessExtensionAdapter({
+  const headlessModAdapter = createHeadlessModAdapter({
     agent,
     backend,
     conversationId,
     permissionMode: headlessPermissionMode,
     reflectionSettings: effectiveReflectionSettings,
     sessionStats,
-    disabled: extensionsDisabled,
+    disabled: modsDisabled,
   });
-  await headlessExtensionAdapter.reload();
+  await headlessModAdapter.reload();
   try {
     await emitHeadlessConversationOpen({
       agent,
       conversationId,
       reason: conversationOpenReason,
-      adapter: headlessExtensionAdapter,
+      adapter: headlessModAdapter,
     });
   } catch {
-    // Extension lifecycle events should not block headless startup.
+    // Mod lifecycle events should not block headless startup.
   }
 
   let availableTools =
@@ -1697,7 +1694,7 @@ export async function handleHeadlessCommand(
       agentId: agent.id,
       conversationId,
       cachedAgent: agent as AgentState,
-      extensionEvents: headlessExtensionAdapter.events,
+      modEvents: headlessModAdapter.events,
     });
     availableTools = initialToolContext.availableTools;
     cachedAgent = initialToolContext.preparedToolContext.agent;
@@ -1716,7 +1713,7 @@ export async function handleHeadlessCommand(
       resolvedSkillSources,
       systemInfoReminderEnabled,
       effectiveReflectionSettings,
-      headlessExtensionAdapter,
+      headlessModAdapter,
     );
     return;
   }
@@ -1737,8 +1734,8 @@ export async function handleHeadlessCommand(
     try {
       if (!headlessConversationClosed) {
         headlessConversationClosed = true;
-        headlessExtensionAdapter.updateContext(
-          createHeadlessExtensionContext({
+        headlessModAdapter.updateContext(
+          createHeadlessModContext({
             agent,
             conversationId,
             lastRunId: lastKnownRunId,
@@ -1752,16 +1749,16 @@ export async function handleHeadlessCommand(
             agent,
             conversationId,
             durationMs: sessionStats.getSnapshot().totalWallMs,
-            adapter: headlessExtensionAdapter,
+            adapter: headlessModAdapter,
           });
         } catch {
-          // Extension lifecycle events should not block headless shutdown.
+          // Mod lifecycle events should not block headless shutdown.
         }
       }
       telemetry.trackSessionEnd(sessionStats.getSnapshot(), exitReason);
       await telemetry.flush();
     } finally {
-      headlessExtensionAdapter.dispose();
+      headlessModAdapter.dispose();
       telemetry.setSessionStatsGetter(undefined);
     }
     return await flushAndExit(code);
@@ -1869,7 +1866,7 @@ export async function handleHeadlessCommand(
         agentId: agent.id,
         conversationId,
         approvalMessages,
-        extensionEvents: headlessExtensionAdapter.events,
+        modEvents: headlessModAdapter.events,
       });
       const drainResult = await drainStreamWithResume(
         approvalStream,
@@ -2029,8 +2026,8 @@ ${SYSTEM_REMINDER_CLOSE}
     ];
     queuedRecoveredApprovalResults = null;
   }
-  headlessExtensionAdapter.updateContext(
-    createHeadlessExtensionContext({
+  headlessModAdapter.updateContext(
+    createHeadlessModContext({
       agent,
       conversationId,
       permissionMode: headlessPermissionMode,
@@ -2042,7 +2039,7 @@ ${SYSTEM_REMINDER_CLOSE}
     agent,
     conversationId,
     input: currentInput,
-    adapter: headlessExtensionAdapter,
+    adapter: headlessModAdapter,
   });
 
   // Track lastRunId outside the while loop so it's available in catch block
@@ -2119,7 +2116,7 @@ ${SYSTEM_REMINDER_CLOSE}
           conversationId,
           overrideModel: overrideModelHandle ?? preparedEffectiveModel,
           cachedAgent,
-          extensionEvents: headlessExtensionAdapter.events,
+          modEvents: headlessModAdapter.events,
         });
         availableTools = turnToolContext.availableTools;
         stream = await sendMessageStream(conversationId, currentInput, {
@@ -3114,7 +3111,7 @@ async function runBidirectionalMode(
   skillSources: SkillSource[],
   systemInfoReminderEnabled: boolean,
   reflectionSettings: ReflectionSettings,
-  headlessExtensionAdapter: ExtensionAdapter,
+  headlessModAdapter: ModAdapter,
 ): Promise<void> {
   const sessionId = agent.id;
   const backend = getBackend();
@@ -3135,16 +3132,16 @@ async function runBidirectionalMode(
             agent,
             conversationId,
             durationMs: null,
-            adapter: headlessExtensionAdapter,
+            adapter: headlessModAdapter,
           });
         } catch {
-          // Extension lifecycle events should not block headless shutdown.
+          // Mod lifecycle events should not block headless shutdown.
         }
       }
       telemetry.trackSessionEnd(undefined, exitReason);
       await telemetry.flush();
     } finally {
-      headlessExtensionAdapter.dispose();
+      headlessModAdapter.dispose();
     }
     return await flushAndExit(code);
   };
@@ -3256,7 +3253,7 @@ async function runBidirectionalMode(
         agentId: agent.id,
         conversationId,
         approvalMessages,
-        extensionEvents: headlessExtensionAdapter.events,
+        modEvents: headlessModAdapter.events,
       });
       const drainResult = await drainStreamWithResume(
         approvalStream,
@@ -3636,7 +3633,7 @@ async function runBidirectionalMode(
         agentId: agent.id,
         conversationId: targetConversationId,
         approvalMessages: [approvalInput],
-        extensionEvents: headlessExtensionAdapter.events,
+        modEvents: headlessModAdapter.events,
       });
 
       const drainResult = await drainStreamWithResume(
@@ -4032,8 +4029,8 @@ async function runBidirectionalMode(
           skillSources,
           maybeLaunchReflectionSubagent,
         });
-        headlessExtensionAdapter.updateContext(
-          createHeadlessExtensionContext({
+        headlessModAdapter.updateContext(
+          createHeadlessModContext({
             agent,
             conversationId,
             reflectionSettings,
@@ -4051,7 +4048,7 @@ async function runBidirectionalMode(
           agent,
           conversationId,
           input: currentInput,
-          adapter: headlessExtensionAdapter,
+          adapter: headlessModAdapter,
         });
 
         // Approval handling loop - continue until end_turn or error
@@ -4091,7 +4088,7 @@ async function runBidirectionalMode(
             const turnToolContext = await prepareHeadlessToolExecutionContext({
               agentId: agent.id,
               conversationId,
-              extensionEvents: headlessExtensionAdapter.events,
+              modEvents: headlessModAdapter.events,
             });
             availableTools = turnToolContext.availableTools;
             stream = await sendMessageStream(conversationId, currentInput, {
diff --git a/src/index.ts b/src/index.ts
--- a/src/index.ts
+++ b/src/index.ts
@@ -78,10 +78,7 @@ import {
   runSubcommand,
   subcommandNeedsEarlyBackendMode,
 } from "./cli/subcommands/router";
-import {
-  disableExtensionsForProcess,
-  shouldDisableExtensions,
-} from "./extensions/disable";
+import { disableModsForProcess, shouldDisableMods } from "./mods/disable";
 import { applyStartupPermissionMode } from "./permissions/startup";
 import {
   type Settings,
@@ -749,7 +746,7 @@ async function main(): Promise<void> {
   const autoUpdatePromise = startStartupAutoUpdateCheck(checkAndAutoUpdate);
 
   // Parse command-line arguments from a shared schema used by both TUI and headless flows.
-  // Preprocess args to support --conv as an alias for --conversation.
+  // Preprocess args to support legacy aliases before strict parsing.
   const processedArgs = preprocessCliArgs([
     process.argv[0] ?? "node",
     process.argv[1] ?? "letta",
@@ -890,11 +887,11 @@ async function main(): Promise<void> {
   const noBundledSkillsFlag = values["no-bundled-skills"];
   const skillSourcesRaw = values["skill-sources"];
   const noSystemInfoReminderFlag = values["no-system-info-reminder"];
-  const extensionsDisabled = shouldDisableExtensions({
-    cliFlag: values["no-extensions"],
+  const modsDisabled = shouldDisableMods({
+    cliFlag: values["no-mods"],
   });
-  if (extensionsDisabled) {
-    disableExtensionsForProcess();
+  if (modsDisabled) {
+    disableModsForProcess();
   }
   const resolvedSkillSources = (() => {
     try {
@@ -2902,7 +2899,7 @@ async function main(): Promise<void> {
         startupHasAvailableLocalModels,
         releaseNotes,
         systemInfoReminderEnabled: !noSystemInfoReminderFlag,
-        extensionsDisabled,
+        modsDisabled,
         fileAutocompleteFdPath,
       });
     }
@@ -2927,7 +2924,7 @@ async function main(): Promise<void> {
       releaseNotes,
       updateNotification,
       systemInfoReminderEnabled: !noSystemInfoReminderFlag,
-      extensionsDisabled,
+      modsDisabled,
       fileAutocompleteFdPath,
     });
   }
diff --git a/src/extensions/capabilities.ts b/src/mods/capabilities.ts
rename from src/extensions/capabilities.ts
rename to src/mods/capabilities.ts
--- a/src/extensions/capabilities.ts
+++ b/src/mods/capabilities.ts
@@ -1,6 +1,6 @@
-import type { ExtensionCapabilities } from "@/extensions/types";
+import type { ModCapabilities } from "@/mods/types";
 
-export const DEFAULT_EXTENSION_CAPABILITIES: ExtensionCapabilities = {
+export const DEFAULT_MOD_CAPABILITIES: ModCapabilities = {
   tools: true,
   commands: true,
   events: {
@@ -17,7 +17,7 @@ export const DEFAULT_EXTENSION_CAPABILITIES: ExtensionCapabilities = {
   },
 };
 
-export const DISABLED_EXTENSION_CAPABILITIES: ExtensionCapabilities = {
+export const DISABLED_MOD_CAPABILITIES: ModCapabilities = {
   tools: false,
   commands: false,
   events: {
@@ -34,9 +34,9 @@ export const DISABLED_EXTENSION_CAPABILITIES: ExtensionCapabilities = {
   },
 };
 
-export function cloneExtensionCapabilities(
-  capabilities: ExtensionCapabilities,
-): ExtensionCapabilities {
+export function cloneModCapabilities(
+  capabilities: ModCapabilities,
+): ModCapabilities {
   return {
     tools: capabilities.tools,
     commands: capabilities.commands,
@@ -55,10 +55,8 @@ export function cloneExtensionCapabilities(
   };
 }
 
-export function resolveExtensionCapabilities(
-  capabilities?: ExtensionCapabilities,
-): ExtensionCapabilities {
-  return cloneExtensionCapabilities(
-    capabilities ?? DEFAULT_EXTENSION_CAPABILITIES,
-  );
+export function resolveModCapabilities(
+  capabilities?: ModCapabilities,
+): ModCapabilities {
+  return cloneModCapabilities(capabilities ?? DEFAULT_MOD_CAPABILITIES);
 }
diff --git a/src/extensions/conversation-handle.ts b/src/mods/conversation-handle.ts
rename from src/extensions/conversation-handle.ts
rename to src/mods/conversation-handle.ts
--- a/src/extensions/conversation-handle.ts
+++ b/src/mods/conversation-handle.ts
@@ -1,31 +1,31 @@
 import type { Backend } from "@/backend";
-import { loadExtensionConversationHistoryFromBackend } from "@/extensions/conversation-history";
+import { loadModConversationHistoryFromBackend } from "@/mods/conversation-history";
 import type {
-  ExtensionConversationHandle,
-  ExtensionConversationMessage,
-  ExtensionConversationSendMessageOptions,
-  ExtensionConversationSendMessageRequestOptions,
-} from "@/extensions/types";
+  ModConversationHandle,
+  ModConversationMessage,
+  ModConversationSendMessageOptions,
+  ModConversationSendMessageRequestOptions,
+} from "@/mods/types";
 
-type SendExtensionConversationMessageStream = (
+type SendModConversationMessageStream = (
   backend: Backend,
   conversationId: string,
-  messages: ExtensionConversationMessage[],
-  options?: ExtensionConversationSendMessageOptions & { agentId?: string },
-  requestOptions?: ExtensionConversationSendMessageRequestOptions,
-) => ReturnType<ExtensionConversationHandle["sendMessageStream"]>;
+  messages: ModConversationMessage[],
+  options?: ModConversationSendMessageOptions & { agentId?: string },
+  requestOptions?: ModConversationSendMessageRequestOptions,
+) => ReturnType<ModConversationHandle["sendMessageStream"]>;
 
-export function createExtensionConversationHandle(options: {
+export function createModConversationHandle(options: {
   agentId?: string | null;
   backend?: Backend;
   conversationId?: string | null;
-  sendMessageStream: SendExtensionConversationMessageStream;
+  sendMessageStream: SendModConversationMessageStream;
   workingDirectory?: string | null;
-}): ExtensionConversationHandle {
+}): ModConversationHandle {
   const conversationId = options.conversationId ?? "default";
   const requireBackend = () => {
     if (!options.backend) {
-      throw new Error("Extension conversation backend is not available");
+      throw new Error("Mod conversation backend is not available");
     }
     return options.backend;
   };
@@ -37,13 +37,13 @@ export function createExtensionConversationHandle(options: {
         ...(options.agentId ? { agentId: options.agentId } : {}),
         ...forkOptions,
       });
-      return createExtensionConversationHandle({
+      return createModConversationHandle({
         ...options,
         conversationId: forked.id,
       });
     },
     getHistory(historyOptions) {
-      return loadExtensionConversationHistoryFromBackend(
+      return loadModConversationHistoryFromBackend(
         requireBackend(),
         {
           agentId: options.agentId,
diff --git a/src/extensions/conversation-history.ts b/src/mods/conversation-history.ts
rename from src/extensions/conversation-history.ts
rename to src/mods/conversation-history.ts
--- a/src/extensions/conversation-history.ts
+++ b/src/mods/conversation-history.ts
@@ -1,28 +1,28 @@
 import type { Message } from "@letta-ai/letta-client/resources/agents/messages";
 import type { Backend, ConversationMessageListBody } from "@/backend";
-import type { ExtensionConversationHistoryOptions } from "@/extensions/types";
+import type { ModConversationHistoryOptions } from "@/mods/types";
 
-const DEFAULT_EXTENSION_CONVERSATION_HISTORY_LIMIT = 100;
-const MAX_EXTENSION_CONVERSATION_HISTORY_LIMIT = 500;
+const DEFAULT_MOD_CONVERSATION_HISTORY_LIMIT = 100;
+const MAX_MOD_CONVERSATION_HISTORY_LIMIT = 500;
 
-function normalizeExtensionConversationHistoryLimit(limit?: number): number {
-  if (limit === undefined) return DEFAULT_EXTENSION_CONVERSATION_HISTORY_LIMIT;
+function normalizeModConversationHistoryLimit(limit?: number): number {
+  if (limit === undefined) return DEFAULT_MOD_CONVERSATION_HISTORY_LIMIT;
   if (!Number.isFinite(limit)) {
-    return DEFAULT_EXTENSION_CONVERSATION_HISTORY_LIMIT;
+    return DEFAULT_MOD_CONVERSATION_HISTORY_LIMIT;
   }
   return Math.min(
     Math.max(1, Math.trunc(limit)),
-    MAX_EXTENSION_CONVERSATION_HISTORY_LIMIT,
+    MAX_MOD_CONVERSATION_HISTORY_LIMIT,
   );
 }
 
-export async function loadExtensionConversationHistoryFromBackend(
+export async function loadModConversationHistoryFromBackend(
   backend: Pick<Backend, "listConversationMessages">,
   scope: {
     agentId?: string | null;
     conversationId?: string | null;
   },
-  options?: ExtensionConversationHistoryOptions,
+  options?: ModConversationHistoryOptions,
 ): Promise<Message[]> {
   const conversationId = scope.conversationId ?? "default";
   const agentId = scope.agentId ?? null;
@@ -31,7 +31,7 @@ export async function loadExtensionConversationHistoryFromBackend(
   }
 
   const page = await backend.listConversationMessages(conversationId, {
-    limit: normalizeExtensionConversationHistoryLimit(options?.limit),
+    limit: normalizeModConversationHistoryLimit(options?.limit),
     order: "desc",
     include_err: options?.includeErrors ?? true,
     ...(conversationId === "default" && agentId ? { agent_id: agentId } : {}),
diff --git a/src/mods/disable.ts b/src/mods/disable.ts
new file mode 100644
--- /dev/null
+++ b/src/mods/disable.ts
@@ -0,0 +1,28 @@
+export const LETTA_DISABLE_MODS_ENV = "LETTA_DISABLE_MODS";
+export const LEGACY_LETTA_DISABLE_EXTENSIONS_ENV = "LETTA_DISABLE_EXTENSIONS";
+
+function isTruthyEnvFlag(value: string | undefined): boolean {
+  if (!value) return false;
+  const normalized = value.trim().toLowerCase();
+  return ["1", "true", "yes", "on"].includes(normalized);
+}
+
+export function areModsDisabled(env: NodeJS.ProcessEnv = process.env): boolean {
+  return (
+    isTruthyEnvFlag(env[LETTA_DISABLE_MODS_ENV]) ||
+    isTruthyEnvFlag(env[LEGACY_LETTA_DISABLE_EXTENSIONS_ENV])
+  );
+}
+
+export function shouldDisableMods(options?: {
+  cliFlag?: boolean;
+  env?: NodeJS.ProcessEnv;
+}): boolean {
+  return Boolean(
+    options?.cliFlag || areModsDisabled(options?.env ?? process.env),
+  );
+}
+
+export function disableModsForProcess(): void {
+  process.env[LETTA_DISABLE_MODS_ENV] = "1";
+}
diff --git a/src/extensions/disabled-extension-adapter.ts b/src/mods/disabled-mod-adapter.ts
rename from src/extensions/disabled-extension-adapter.ts
rename to src/mods/disabled-mod-adapter.ts
--- a/src/extensions/disabled-extension-adapter.ts
+++ b/src/mods/disabled-mod-adapter.ts
@@ -1,27 +1,21 @@
-import { clearRegisteredPiProviders } from "@/backend/dev/pi-provider-extension-registry";
+import { clearRegisteredPiProviders } from "@/backend/dev/pi-provider-mod-registry";
 import {
-  cloneExtensionCapabilities,
-  DISABLED_EXTENSION_CAPABILITIES,
-} from "@/extensions/capabilities";
-import {
-  type ExtensionEvents,
-  emptyEventEmissionResult,
-} from "@/extensions/event-emitter";
-import type {
-  ExtensionEngine,
-  LocalExtensionRegistry,
-} from "@/extensions/extension-engine";
-import { clearExtensionPermissions } from "@/extensions/permission-registry";
-import { clearExtensionTools } from "@/extensions/tool-registry";
-import type { ExtensionContext } from "@/extensions/types";
+  cloneModCapabilities,
+  DISABLED_MOD_CAPABILITIES,
+} from "@/mods/capabilities";
+import { emptyEventEmissionResult, type ModEvents } from "@/mods/event-emitter";
+import type { LocalModRegistry, ModEngine } from "@/mods/mod-engine";
+import { clearModPermissions } from "@/mods/permission-registry";
+import { clearModTools } from "@/mods/tool-registry";
+import type { ModContext } from "@/mods/types";
 
-interface CreateDisabledExtensionAdapterOptions {
-  initialContext: ExtensionContext;
+interface CreateDisabledModAdapterOptions {
+  initialContext: ModContext;
 }
 
-function createDisabledExtensionRegistry(): LocalExtensionRegistry {
+function createDisabledModRegistry(): LocalModRegistry {
   return {
-    capabilities: cloneExtensionCapabilities(DISABLED_EXTENSION_CAPABILITIES),
+    capabilities: cloneModCapabilities(DISABLED_MOD_CAPABILITIES),
     commands: {},
     diagnostics: [],
     disposers: [],
@@ -42,9 +36,7 @@ function createDisabledExtensionRegistry(): LocalExtensionRegistry {
   };
 }
 
-function createDisabledExtensionEngine(
-  registry: LocalExtensionRegistry,
-): ExtensionEngine {
+function createDisabledModEngine(registry: LocalModRegistry): ModEngine {
   return {
     dispose() {},
     emitEvent(name) {
@@ -62,23 +54,23 @@ function createDisabledExtensionEngine(
   };
 }
 
-export function createDisabledExtensionAdapter(
-  options: CreateDisabledExtensionAdapterOptions,
+export function createDisabledModAdapter(
+  options: CreateDisabledModAdapterOptions,
 ) {
-  clearExtensionPermissions();
-  clearExtensionTools();
+  clearModPermissions();
+  clearModTools();
   clearRegisteredPiProviders();
 
   let context = options.initialContext;
-  const registry = createDisabledExtensionRegistry();
-  const engine = createDisabledExtensionEngine(registry);
+  const registry = createDisabledModRegistry();
+  const engine = createDisabledModEngine(registry);
   const snapshot = {
     hadStatuslineRenderer: false,
-    hasExtensionSources: false,
+    hasModSources: false,
     isLoading: false,
     registry,
   };
-  const events: ExtensionEvents = {
+  const events: ModEvents = {
     emit(name) {
       return Promise.resolve(emptyEventEmissionResult(name));
     },
@@ -103,7 +95,7 @@ export function createDisabledExtensionAdapter(
     subscribe(_listener: () => void) {
       return () => undefined;
     },
-    updateContext(nextContext: ExtensionContext) {
+    updateContext(nextContext: ModContext) {
       context = nextContext;
     },
   };
diff --git a/src/mods/event-emitter.ts b/src/mods/event-emitter.ts
new file mode 100644
--- /dev/null
+++ b/src/mods/event-emitter.ts
@@ -0,0 +1,33 @@
+import type {
+  ModEventEmissionResult,
+  ModEventMap,
+  ModEventName,
+} from "@/mods/types";
+
+// Narrow event capability exposed by the mod adapter. Adapter-owned
+// implementations are guarded, so lower layers can emit events without
+// depending on adapter lifecycle or registry APIs.
+export type ModEvents = {
+  emit: <TName extends ModEventName>(
+    name: TName,
+    event: ModEventMap[TName],
+  ) => Promise<ModEventEmissionResult<TName>>;
+};
+
+export function emptyEventEmissionResult<TName extends ModEventName>(
+  name: TName,
+): ModEventEmissionResult<TName> {
+  return { diagnostics: [], handlerCount: 0, name, results: [] };
+}
+
+export async function emitModEvent<TName extends ModEventName>(
+  events: ModEvents | undefined,
+  name: TName,
+  event: ModEventMap[TName],
+): Promise<ModEventEmissionResult<TName>> {
+  if (!events) {
+    return emptyEventEmissionResult(name);
+  }
+
+  return events.emit(name, event);
+}
diff --git a/src/extensions/extension-adapter.ts b/src/mods/mod-adapter.ts
rename from src/extensions/extension-adapter.ts
rename to src/mods/mod-adapter.ts
--- a/src/extensions/extension-adapter.ts
+++ b/src/mods/mod-adapter.ts
@@ -1,68 +1,58 @@
 import type { Backend } from "@/backend";
+import { areModsDisabled, disableModsForProcess } from "@/mods/disable";
+import { createDisabledModAdapter } from "@/mods/disabled-mod-adapter";
+import { emptyEventEmissionResult, type ModEvents } from "@/mods/event-emitter";
+import { getModErrorDiagnostics } from "@/mods/mod-diagnostics";
+import { writeModDiagnosticsLatestFile } from "@/mods/mod-diagnostics-file";
 import {
-  areExtensionsDisabled,
-  disableExtensionsForProcess,
-} from "@/extensions/disable";
-import { createDisabledExtensionAdapter } from "@/extensions/disabled-extension-adapter";
-import {
-  type ExtensionEvents,
-  emptyEventEmissionResult,
-} from "@/extensions/event-emitter";
-import { getExtensionErrorDiagnostics } from "@/extensions/extension-diagnostics";
-import { writeExtensionDiagnosticsLatestFile } from "@/extensions/extension-diagnostics-file";
-import {
-  type CreateExtensionEngineOptions,
-  createExtensionEngine,
-  type ExtensionEngine,
-  type ResolveLocalExtensionSourcesOptions,
-  resolveLocalExtensionSources,
-} from "@/extensions/extension-engine";
-import type { ExtensionContext } from "@/extensions/types";
+  type CreateModEngineOptions,
+  createModEngine,
+  type ModEngine,
+  type ResolveLocalModSourcesOptions,
+  resolveLocalModSources,
+} from "@/mods/mod-engine";
+import type { ModContext } from "@/mods/types";
 import { debugLog } from "@/utils/debug";
 
 const RUNTIME_DIAGNOSTICS_WRITE_DELAY_MS = 30_000;
 
-export interface ExtensionAdapterLoadState {
+export interface ModAdapterLoadState {
   hadStatuslineRenderer: boolean;
-  hasExtensionSources: boolean;
+  hasModSources: boolean;
   isLoading: boolean;
 }
 
-export interface ExtensionAdapterSnapshot extends ExtensionAdapterLoadState {
-  registry: ReturnType<ExtensionEngine["getSnapshot"]>;
+export interface ModAdapterSnapshot extends ModAdapterLoadState {
+  registry: ReturnType<ModEngine["getSnapshot"]>;
 }
 
-export interface CreateExtensionAdapterOptions
-  extends Omit<CreateExtensionEngineOptions, "getContext"> {
+export interface CreateModAdapterOptions
+  extends Omit<CreateModEngineOptions, "getContext"> {
   diagnosticsRootDirectory?: string;
   diagnosticsWriteDelayMs?: number;
   disabled?: boolean;
-  initialContext: ExtensionContext;
+  initialContext: ModContext;
 }
 
-export interface ExtensionAdapter {
+export interface ModAdapter {
   dispose: () => void;
-  events: ExtensionEvents;
+  events: ModEvents;
   getBackend: () => Backend | undefined;
-  getContext: () => ExtensionContext;
-  getSnapshot: () => ExtensionAdapterSnapshot;
-  engine: ExtensionEngine;
+  getContext: () => ModContext;
+  getSnapshot: () => ModAdapterSnapshot;
+  engine: ModEngine;
   reload: () => Promise<void>;
   subscribe: (listener: () => void) => () => void;
-  updateContext: (context: ExtensionContext) => void;
+  updateContext: (context: ModContext) => void;
 }
 
-function hasExtensionSources(
-  options: ResolveLocalExtensionSourcesOptions,
-): boolean {
-  return resolveLocalExtensionSources(options).some(
+function hasModSources(options: ResolveLocalModSourcesOptions): boolean {
+  return resolveLocalModSources(options).some(
     (source) => source.files.length > 0,
   );
 }
 
-export function createExtensionAdapter(
-  options: CreateExtensionAdapterOptions,
-): ExtensionAdapter {
+export function createModAdapter(options: CreateModAdapterOptions): ModAdapter {
   const {
     diagnosticsRootDirectory,
     diagnosticsWriteDelayMs = RUNTIME_DIAGNOSTICS_WRITE_DELAY_MS,
@@ -72,29 +62,29 @@ export function createExtensionAdapter(
     ...engineOptions
   } = options;
 
-  const alreadyDisabled = areExtensionsDisabled();
+  const alreadyDisabled = areModsDisabled();
   if (disabled || alreadyDisabled) {
     if (!alreadyDisabled) {
-      disableExtensionsForProcess();
+      disableModsForProcess();
     }
-    return createDisabledExtensionAdapter({ initialContext });
+    return createDisabledModAdapter({ initialContext });
   }
 
   let context = initialContext;
   let disposed = false;
-  const initialHasExtensionSources = hasExtensionSources(engineOptions);
-  let loadState: ExtensionAdapterLoadState = {
+  const initialHasModSources = hasModSources(engineOptions);
+  let loadState: ModAdapterLoadState = {
     hadStatuslineRenderer: false,
-    hasExtensionSources: initialHasExtensionSources,
-    isLoading: initialHasExtensionSources,
+    hasModSources: initialHasModSources,
+    isLoading: initialHasModSources,
   };
   const listeners = new Set<() => void>();
   let diagnosticsWriteTimer: ReturnType<typeof setTimeout> | null = null;
 
   const getBackend = () => resolveBackend?.();
   const getContext = () => context;
 
-  const engine = createExtensionEngine({
+  const engine = createModEngine({
     ...engineOptions,
     getBackend,
     getContext,
@@ -112,13 +102,13 @@ export function createExtensionAdapter(
     if (!registry.sources.some((source) => source.files.length > 0)) return;
 
     try {
-      writeExtensionDiagnosticsLatestFile(registry.diagnostics, {
+      writeModDiagnosticsLatestFile(registry.diagnostics, {
         rootDirectory: diagnosticsRootDirectory,
       });
     } catch (error) {
       debugLog(
-        "extensions",
-        "failed to write extension diagnostics: %s",
+        "mods",
+        "failed to write mod diagnostics: %s",
         error instanceof Error ? error.message : String(error),
       );
     }
@@ -131,8 +121,7 @@ export function createExtensionAdapter(
   }
 
   function scheduleDiagnosticsWrite(): void {
-    if (disposed || loadState.isLoading || !loadState.hasExtensionSources)
-      return;
+    if (disposed || loadState.isLoading || !loadState.hasModSources) return;
     if (diagnosticsWriteTimer) return;
 
     diagnosticsWriteTimer = setTimeout(() => {
@@ -145,10 +134,10 @@ export function createExtensionAdapter(
     timerWithUnref.unref?.();
   }
 
-  const events: ExtensionEvents = {
+  const events: ModEvents = {
     async emit(name, event) {
-      if (loadState.isLoading || !loadState.hasExtensionSources) {
-        // Events are best-effort hooks; do not deliver them while the extension
+      if (loadState.isLoading || !loadState.hasModSources) {
+        // Events are best-effort hooks; do not deliver them while the mod
         // registry is unavailable or in flux.
         return emptyEventEmissionResult(name);
       }
@@ -157,7 +146,7 @@ export function createExtensionAdapter(
     },
   };
 
-  const buildSnapshot = (): ExtensionAdapterSnapshot => ({
+  const buildSnapshot = (): ModAdapterSnapshot => ({
     registry: engine.getSnapshot(),
     ...loadState,
   });
@@ -183,7 +172,7 @@ export function createExtensionAdapter(
       loadState.hadStatuslineRenderer;
     loadState = {
       hadStatuslineRenderer: previousHadStatuslineRenderer,
-      hasExtensionSources: hasExtensionSources(engineOptions),
+      hasModSources: hasModSources(engineOptions),
       isLoading: true,
     };
     publish();
@@ -195,18 +184,16 @@ export function createExtensionAdapter(
     writeLatestDiagnostics();
 
     debugLog(
-      "extensions",
-      "loaded %s extension(s) from %s source(s); renderer=%s",
+      "mods",
+      "loaded %s mod(s) from %s source(s); renderer=%s",
       nextRegistry.loadedPaths.length,
       nextRegistry.sources.length,
       nextRegistry.ui.statuslineRenderer?.id ?? "(none)",
     );
 
-    for (const diagnostic of getExtensionErrorDiagnostics(
-      nextRegistry.diagnostics,
-    )) {
+    for (const diagnostic of getModErrorDiagnostics(nextRegistry.diagnostics)) {
       debugLog(
-        "extensions",
+        "mods",
         "failed to load %s: %s",
         diagnostic.owner.path,
         diagnostic.error.message,
@@ -215,13 +202,13 @@ export function createExtensionAdapter(
 
     for (const diagnostic of nextRegistry.diagnostics) {
       if (diagnostic.phase === "command_override") {
-        debugLog("extensions", "%s", diagnostic.error.message);
+        debugLog("mods", "%s", diagnostic.error.message);
       }
     }
 
     loadState = {
       hadStatuslineRenderer: Boolean(nextRegistry.ui.statuslineRenderer),
-      hasExtensionSources: nextRegistry.sources.some(
+      hasModSources: nextRegistry.sources.some(
         (source) => source.files.length > 0,
       ),
       isLoading: false,
diff --git a/src/mods/mod-diagnostics-file.ts b/src/mods/mod-diagnostics-file.ts
new file mode 100644
--- /dev/null
+++ b/src/mods/mod-diagnostics-file.ts
@@ -0,0 +1,50 @@
+import { mkdirSync, writeFileSync } from "node:fs";
+import { homedir } from "node:os";
+import path from "node:path";
+import {
+  createModDiagnosticsReport,
+  type ModDiagnosticsReport,
+} from "@/mods/mod-diagnostics";
+import { resolveDefaultGlobalModsDirectory } from "@/mods/paths";
+import type { ModDiagnostic } from "@/mods/types";
+
+export interface ModDiagnosticsFile {
+  generatedAt: number;
+  report: ModDiagnosticsReport;
+}
+
+export function getDefaultModDiagnosticsRoot(
+  homeDirectory = homedir(),
+): string {
+  return path.join(
+    resolveDefaultGlobalModsDirectory(homeDirectory),
+    "diagnostics",
+  );
+}
+
+export function getModDiagnosticsLatestFilePath(
+  rootDirectory = getDefaultModDiagnosticsRoot(),
+): string {
+  return path.join(rootDirectory, "latest.json");
+}
+
+function createModDiagnosticsFile(
+  diagnostics: readonly ModDiagnostic[],
+  generatedAt = Date.now(),
+): ModDiagnosticsFile {
+  return {
+    generatedAt,
+    report: createModDiagnosticsReport(diagnostics),
+  };
+}
+
+export function writeModDiagnosticsLatestFile(
+  diagnostics: readonly ModDiagnostic[],
+  options: { generatedAt?: number; rootDirectory?: string } = {},
+): ModDiagnosticsFile {
+  const file = createModDiagnosticsFile(diagnostics, options.generatedAt);
+  const filePath = getModDiagnosticsLatestFilePath(options.rootDirectory);
+  mkdirSync(path.dirname(filePath), { recursive: true });
+  writeFileSync(filePath, `${JSON.stringify(file, null, 2)}\n`, "utf-8");
+  return file;
+}
diff --git a/src/mods/mod-diagnostics.ts b/src/mods/mod-diagnostics.ts
new file mode 100644
--- /dev/null
+++ b/src/mods/mod-diagnostics.ts
@@ -0,0 +1,149 @@
+import type {
+  ModDiagnostic,
+  ModDiagnosticPhase,
+  ModDiagnosticSeverity,
+  ModOwner,
+} from "@/mods/types";
+
+export type { ModDiagnosticSeverity } from "@/mods/types";
+
+export const MOD_DIAGNOSTICS_MAX_COUNT = 200;
+export const MOD_DIAGNOSTICS_RESET_COUNT = 50;
+
+export interface ModDiagnosticCollector {
+  diagnostics: ModDiagnostic[];
+}
+
+export interface ModDiagnosticReportEntry {
+  capability?: ModDiagnostic["capability"];
+  errorName: string;
+  mod: ModOwner;
+  message: string;
+  phase: ModDiagnosticPhase;
+  severity: ModDiagnosticSeverity;
+  stack?: string;
+  timestamp: number;
+}
+
+export interface ModDiagnosticsReport {
+  diagnostics: ModDiagnosticReportEntry[];
+  errorCount: number;
+  warningCount: number;
+}
+
+export function getModDiagnosticSeverity(
+  phase: ModDiagnosticPhase,
+  severity?: ModDiagnosticSeverity,
+): ModDiagnosticSeverity {
+  switch (phase) {
+    case "command_override":
+      return "warning";
+    case "report":
+      return severity ?? "error";
+    default:
+      return "error";
+  }
+}
+
+export function isModDiagnosticErrorPhase(phase: ModDiagnosticPhase): boolean {
+  return getModDiagnosticSeverity(phase) === "error";
+}
+
+export function isModDiagnosticError(
+  diagnostic: Pick<ModDiagnostic, "phase" | "severity">,
+): boolean {
+  return (
+    getModDiagnosticSeverity(diagnostic.phase, diagnostic.severity) === "error"
+  );
+}
+
+export function getModErrorDiagnostics(
+  diagnostics: readonly ModDiagnostic[],
+): ModDiagnostic[] {
+  return diagnostics.filter(isModDiagnosticError);
+}
+
+export function createModDiagnosticsReport(
+  diagnostics: readonly ModDiagnostic[],
+): ModDiagnosticsReport {
+  let errorCount = 0;
+  let warningCount = 0;
+
+  const entries = diagnostics.map((diagnostic) => {
+    const severity = getModDiagnosticSeverity(
+      diagnostic.phase,
+      diagnostic.severity,
+    );
+    if (severity === "error") {
+      errorCount += 1;
+    } else {
+      warningCount += 1;
+    }
+
+    return {
+      ...(diagnostic.capability
+        ? { capability: { ...diagnostic.capability } }
+        : {}),
+      errorName: diagnostic.error.name,
+      mod: { ...diagnostic.owner },
+      message: diagnostic.error.message,
+      phase: diagnostic.phase,
+      severity,
+      ...(diagnostic.error.stack ? { stack: diagnostic.error.stack } : {}),
+      timestamp: diagnostic.timestamp,
+    } satisfies ModDiagnosticReportEntry;
+  });
+
+  return {
+    diagnostics: entries,
+    errorCount,
+    warningCount,
+  };
+}
+
+export function appendModDiagnostic(
+  collector: ModDiagnosticCollector,
+  diagnostic: ModDiagnostic,
+): void {
+  collector.diagnostics.push(diagnostic);
+  if (collector.diagnostics.length > MOD_DIAGNOSTICS_MAX_COUNT) {
+    collector.diagnostics.splice(
+      0,
+      collector.diagnostics.length - MOD_DIAGNOSTICS_RESET_COUNT,
+    );
+  }
+}
+
+export function recordModDiagnostic(
+  collector: ModDiagnosticCollector,
+  diagnostic: Omit<ModDiagnostic, "timestamp">,
+  onDiagnostic?: (diagnostic: ModDiagnostic) => void,
+): ModDiagnostic {
+  const completeDiagnostic: ModDiagnostic = {
+    ...diagnostic,
+    timestamp: Date.now(),
+  };
+  appendModDiagnostic(collector, completeDiagnostic);
+  onDiagnostic?.(completeDiagnostic);
+  return completeDiagnostic;
+}
+
+export function recordStaleHandleUse(
+  collector: ModDiagnosticCollector,
+  owner: ModOwner,
+  capability: ModDiagnostic["capability"],
+  onDiagnostic?: (diagnostic: ModDiagnostic) => void,
+): ModDiagnostic {
+  return recordModDiagnostic(
+    collector,
+    {
+      capability,
+      error: new Error(
+        `Ignored stale mod handle for ${capability?.kind ?? "capability"}${capability?.id ? ` '${capability.id}'` : ""}`,
+      ),
+      owner,
+      phase: "stale_handle",
+    },
+    onDiagnostic,
+  );
+}
diff --git a/src/extensions/extension-engine.ts b/src/mods/mod-engine.ts
rename from src/extensions/extension-engine.ts
rename to src/mods/mod-engine.ts
--- a/src/extensions/extension-engine.ts
+++ b/src/mods/mod-engine.ts
@@ -10,286 +10,278 @@ import {
   writeFileSync,
 } from "node:fs";
 import { createRequire } from "node:module";
-import { homedir } from "node:os";
 import path from "node:path";
 import { pathToFileURL } from "node:url";
 import type Letta from "@letta-ai/letta-client";
 import * as ts from "typescript";
 import { clearAvailableModelsCache } from "@/agent/available-models";
 import { sendMessageStreamWithBackend } from "@/agent/message";
 import type { Backend } from "@/backend";
-import type { PiProviderRegistration } from "@/backend/dev/pi-provider-extension-registry";
+import type { PiProviderRegistration } from "@/backend/dev/pi-provider-mod-registry";
 import {
   registerPiProvider,
   unregisterPiProvider,
   unregisterPiProvidersForOwner,
-} from "@/backend/dev/pi-provider-extension-registry";
+} from "@/backend/dev/pi-provider-mod-registry";
 import type {
   StatuslineRenderContext,
   StatuslineRenderer,
   StatuslineRendererOutput,
 } from "@/cli/display/statusline/types";
 import {
-  cloneExtensionCapabilities,
-  resolveExtensionCapabilities,
-} from "@/extensions/capabilities";
-import { createExtensionConversationHandle } from "@/extensions/conversation-handle";
+  cloneModCapabilities,
+  resolveModCapabilities,
+} from "@/mods/capabilities";
+import { createModConversationHandle } from "@/mods/conversation-handle";
 import {
-  appendExtensionDiagnostic,
-  recordExtensionDiagnostic,
+  appendModDiagnostic,
+  recordModDiagnostic,
   recordStaleHandleUse,
-} from "@/extensions/extension-diagnostics";
+} from "@/mods/mod-diagnostics";
 import {
-  getExtensionPermissionDefinition,
-  registerExtensionPermission,
-  unregisterExtensionPermission,
-  unregisterExtensionPermissionsForOwner,
-} from "@/extensions/permission-registry";
+  getGlobalModsDirectory,
+  getLegacyGlobalExtensionsDirectory,
+  getModCacheDirectory,
+  resolveDefaultGlobalModsDirectory,
+} from "@/mods/paths";
 import {
-  getExtensionToolDefinition,
-  registerExtensionTool,
-  unregisterExtensionTool,
-  unregisterExtensionToolsForOwner,
-} from "@/extensions/tool-registry";
+  getModPermissionDefinition,
+  registerModPermission,
+  unregisterModPermission,
+  unregisterModPermissionsForOwner,
+} from "@/mods/permission-registry";
+import {
+  getModToolDefinition,
+  registerModTool,
+  unregisterModTool,
+  unregisterModToolsForOwner,
+} from "@/mods/tool-registry";
 import type {
-  ExtensionCapabilities,
-  ExtensionCommand,
-  ExtensionCommandRegistration,
-  ExtensionContext,
-  ExtensionDiagnostic,
-  ExtensionDiagnosticReportOptions,
-  ExtensionDiagnosticSeverity,
-  ExtensionEventContext,
-  ExtensionEventEmissionResult,
-  ExtensionEventHandler,
-  ExtensionEventMap,
-  ExtensionEventName,
-  ExtensionEventRegistration,
-  ExtensionEventResultMap,
-  ExtensionOwner,
-  ExtensionPanel,
-  ExtensionPanelContent,
-  ExtensionPanelHandle,
-  ExtensionPanelOptions,
-  ExtensionPanelUpdate,
-  ExtensionPermission,
-  ExtensionPermissionRegistration,
-  ExtensionTool,
-  ExtensionToolRegistration,
-  ExtensionToolStartEvent,
-  ExtensionTurnStartEvent,
-} from "@/extensions/types";
-
-export const GLOBAL_EXTENSIONS_DIRECTORY = path.join(
-  homedir(),
-  ".letta",
-  "extensions",
-);
-export const EXTENSION_CACHE_DIRECTORY = path.join(
-  homedir(),
-  ".letta",
-  "extension-cache",
-);
-
-const EXTENSION_FILE_EXTENSIONS = new Set([".js", ".mjs", ".ts", ".tsx"]);
-const TYPESCRIPT_EXTENSION_FILE_EXTENSIONS = new Set([".ts", ".tsx"]);
+  ModCapabilities,
+  ModCommand,
+  ModCommandRegistration,
+  ModContext,
+  ModDiagnostic,
+  ModDiagnosticReportOptions,
+  ModDiagnosticSeverity,
+  ModEventContext,
+  ModEventEmissionResult,
+  ModEventHandler,
+  ModEventMap,
+  ModEventName,
+  ModEventRegistration,
+  ModEventResultMap,
+  ModOwner,
+  ModPanel,
+  ModPanelContent,
+  ModPanelHandle,
+  ModPanelOptions,
+  ModPanelUpdate,
+  ModPermission,
+  ModPermissionRegistration,
+  ModTool,
+  ModToolRegistration,
+  ModToolStartEvent,
+  ModTurnStartEvent,
+} from "@/mods/types";
+
+export const GLOBAL_MODS_DIRECTORY = getGlobalModsDirectory();
+export const LEGACY_GLOBAL_EXTENSIONS_DIRECTORY =
+  getLegacyGlobalExtensionsDirectory();
+export const MOD_CACHE_DIRECTORY = getModCacheDirectory();
+
+const MOD_FILE_EXTENSIONS = new Set([".js", ".mjs", ".ts", ".tsx"]);
+const TYPESCRIPT_MOD_FILE_EXTENSIONS = new Set([".ts", ".tsx"]);
 const requireFromRuntime = createRequire(import.meta.url);
 
 export type StatuslineRenderFunction = (
   context: StatuslineRenderContext,
 ) => StatuslineRendererOutput;
 
-export type ExtensionStatusValue =
+export type ModStatusValue =
   | string
   | null
-  | ((context: ExtensionContext) => string | null);
+  | ((context: ModContext) => string | null);
 
-export type LettaExtensionDisposer = () => void;
+export type LettaModDisposer = () => void;
 
-export type LettaExtensionFactory = (
-  letta: LettaExtensionApi,
-) =>
-  | undefined
-  | LettaExtensionDisposer
-  | Promise<undefined | LettaExtensionDisposer>;
+export type LettaModFactory = (
+  letta: LettaModApi,
+) => undefined | LettaModDisposer | Promise<undefined | LettaModDisposer>;
 
-export interface LettaExtensionApi {
-  capabilities: ExtensionCapabilities;
+export interface LettaModApi {
+  capabilities: ModCapabilities;
   client: Letta;
   getClient: () => Promise<Letta>;
-  getContext: () => ExtensionContext;
+  getContext: () => ModContext;
   signal: AbortSignal;
   registerProvider: (
     name: string,
     config: PiProviderRegistration,
-  ) => LettaExtensionDisposer;
+  ) => LettaModDisposer;
   unregisterProvider: (name: string) => void;
   commands: {
-    register: (command: ExtensionCommandRegistration) => LettaExtensionDisposer;
+    register: (command: ModCommandRegistration) => LettaModDisposer;
     unregister: (id: string) => void;
   };
   tools: {
-    register: (tool: ExtensionToolRegistration) => LettaExtensionDisposer;
+    register: (tool: ModToolRegistration) => LettaModDisposer;
     unregister: (name: string) => void;
   };
   providers: {
     register: (
       name: string,
       config: PiProviderRegistration,
-    ) => LettaExtensionDisposer;
+    ) => LettaModDisposer;
     unregister: (name: string) => void;
   };
   events: {
-    off: <TName extends ExtensionEventName>(
+    off: <TName extends ModEventName>(
       name: TName,
-      handler: ExtensionEventHandler<TName>,
+      handler: ModEventHandler<TName>,
     ) => void;
-    on: <TName extends ExtensionEventName>(
+    on: <TName extends ModEventName>(
       name: TName,
-      handler: ExtensionEventHandler<TName>,
-    ) => LettaExtensionDisposer;
+      handler: ModEventHandler<TName>,
+    ) => LettaModDisposer;
   };
   permissions: {
-    register: (
-      permission: ExtensionPermissionRegistration,
-    ) => LettaExtensionDisposer;
+    register: (permission: ModPermissionRegistration) => LettaModDisposer;
     unregister: (id: string) => void;
   };
   diagnostics: {
-    report: (diagnostic: ExtensionDiagnosticReportOptions) => void;
+    report: (diagnostic: ModDiagnosticReportOptions) => void;
   };
   ui: {
     clearPanel: (id: string) => void;
     clearStatus: (key: string) => void;
-    openPanel: (panel: ExtensionPanelOptions) => ExtensionPanelHandle;
-    setStatus: (key: string, value: ExtensionStatusValue | undefined) => void;
+    openPanel: (panel: ModPanelOptions) => ModPanelHandle;
+    setStatus: (key: string, value: ModStatusValue | undefined) => void;
     setStatuslineRenderer: (
       renderer: StatuslineRenderer | StatuslineRenderFunction,
     ) => void;
   };
 }
 
-export interface LocalExtensionDisposer {
+export interface LocalModDisposer {
   abortController?: AbortController;
-  dispose: LettaExtensionDisposer;
-  owner: ExtensionOwner;
+  dispose: LettaModDisposer;
+  owner: ModOwner;
 }
 
-export interface LocalExtensionUiRegistry {
-  panels: Record<string, ExtensionPanel>;
+export interface LocalModUiRegistry {
+  panels: Record<string, ModPanel>;
   statuslineRenderer: StatuslineRenderer | null;
-  statuslineRendererOwner?: ExtensionOwner;
-  statusOwners: Record<string, ExtensionOwner>;
-  statusValues: Record<string, ExtensionStatusValue>;
+  statuslineRendererOwner?: ModOwner;
+  statusOwners: Record<string, ModOwner>;
+  statusValues: Record<string, ModStatusValue>;
 }
 
-type LocalExtensionEventsRegistry = Partial<
-  Record<ExtensionEventName, ExtensionEventRegistration[]>
+type LocalModEventsRegistry = Partial<
+  Record<ModEventName, ModEventRegistration[]>
 >;
 
-export interface LocalExtensionRegistry {
-  capabilities: ExtensionCapabilities;
-  commands: Record<string, ExtensionCommand>;
-  diagnostics: ExtensionDiagnostic[];
-  disposers: LocalExtensionDisposer[];
-  events: LocalExtensionEventsRegistry;
+export interface LocalModRegistry {
+  capabilities: ModCapabilities;
+  commands: Record<string, ModCommand>;
+  diagnostics: ModDiagnostic[];
+  disposers: LocalModDisposer[];
+  events: LocalModEventsRegistry;
   generation: number;
   loadedPaths: string[];
   ownerAbortControllers: Record<string, AbortController>;
-  owners: Record<string, ExtensionOwner>;
-  permissions: Record<string, ExtensionPermission>;
-  sources: LocalExtensionSource[];
-  tools: Record<string, ExtensionTool>;
-  ui: LocalExtensionUiRegistry;
+  owners: Record<string, ModOwner>;
+  permissions: Record<string, ModPermission>;
+  sources: LocalModSource[];
+  tools: Record<string, ModTool>;
+  ui: LocalModUiRegistry;
 }
 
-export interface LocalExtensionSource {
+export interface LocalModSource {
   files: string[];
   root: string;
   scope: "global" | "project" | "bundled";
   trusted: boolean;
 }
 
-interface LocalExtensionModule {
+interface LocalModModule {
   activate?: unknown;
   default?: unknown;
 }
 
-export interface ResolveLocalExtensionSourcesOptions {
+export interface ResolveLocalModSourcesOptions {
   cacheDirectory?: string;
-  globalExtensionsDirectory?: string;
+  globalModsDirectory?: string;
 }
 
-export interface LoadLocalExtensionsOptions
-  extends ResolveLocalExtensionSourcesOptions {
-  getContext?: () => ExtensionContext;
+export interface LoadLocalModsOptions extends ResolveLocalModSourcesOptions {
+  getContext?: () => ModContext;
   getClient: () => Promise<Letta>;
-  capabilities?: ExtensionCapabilities;
+  capabilities?: ModCapabilities;
   builtinCommandIds?: Iterable<string>;
   generation?: number;
   onChange?: () => void;
-  onDiagnostic?: (diagnostic: ExtensionDiagnostic) => void;
+  onDiagnostic?: (diagnostic: ModDiagnostic) => void;
   reservedToolNames?: Iterable<string>;
 }
 
-export interface ExtensionEngine {
+export interface ModEngine {
   dispose: () => void;
-  emitEvent: <TName extends ExtensionEventName>(
+  emitEvent: <TName extends ModEventName>(
     name: TName,
-    event: ExtensionEventMap[TName],
-  ) => Promise<ExtensionEventEmissionResult<TName>>;
-  getSnapshot: () => LocalExtensionRegistry;
+    event: ModEventMap[TName],
+  ) => Promise<ModEventEmissionResult<TName>>;
+  getSnapshot: () => LocalModRegistry;
   reload: () => Promise<void>;
   subscribe: (listener: () => void) => () => void;
 }
 
-export interface CreateExtensionEngineOptions
-  extends ResolveLocalExtensionSourcesOptions {
-  getContext?: () => ExtensionContext;
+export interface CreateModEngineOptions extends ResolveLocalModSourcesOptions {
+  getContext?: () => ModContext;
   getClient: () => Promise<Letta>;
   getBackend?: () => Backend | undefined;
   builtinCommandIds?: Iterable<string>;
-  capabilities?: ExtensionCapabilities;
-  onDiagnostic?: (diagnostic: ExtensionDiagnostic) => void;
+  capabilities?: ModCapabilities;
+  onDiagnostic?: (diagnostic: ModDiagnostic) => void;
   reservedToolNames?: Iterable<string>;
 }
 
-function listExtensionFiles(directory: string): string[] {
+function listModFiles(directory: string): string[] {
   if (!existsSync(directory)) return [];
 
   return readdirSync(directory, { withFileTypes: true })
     .filter((entry) => {
       if (!entry.isFile()) return false;
       if (entry.name.startsWith(".")) return false;
-      return EXTENSION_FILE_EXTENSIONS.has(path.extname(entry.name));
+      return MOD_FILE_EXTENSIONS.has(path.extname(entry.name));
     })
     .map((entry) => path.join(directory, entry.name))
     .sort((a, b) => a.localeCompare(b));
 }
 
-export function resolveLocalExtensionSources(
-  options: ResolveLocalExtensionSourcesOptions = {},
-): LocalExtensionSource[] {
-  const globalExtensionsDirectory =
-    options.globalExtensionsDirectory ?? GLOBAL_EXTENSIONS_DIRECTORY;
+export function resolveLocalModSources(
+  options: ResolveLocalModSourcesOptions = {},
+): LocalModSource[] {
+  const globalModsDirectory =
+    options.globalModsDirectory ?? resolveDefaultGlobalModsDirectory();
 
   return [
     {
-      files: listExtensionFiles(globalExtensionsDirectory),
-      root: globalExtensionsDirectory,
+      files: listModFiles(globalModsDirectory),
+      root: globalModsDirectory,
       scope: "global",
       trusted: true,
     },
   ];
 }
 
-function createEmptyExtensionRegistry(
-  sources: LocalExtensionSource[],
+function createEmptyModRegistry(
+  sources: LocalModSource[],
   generation: number,
-  capabilities: ExtensionCapabilities,
-): LocalExtensionRegistry {
+  capabilities: ModCapabilities,
+): LocalModRegistry {
   return {
-    capabilities: cloneExtensionCapabilities(capabilities),
+    capabilities: cloneModCapabilities(capabilities),
     commands: {},
     diagnostics: [],
     disposers: [],
@@ -310,41 +302,38 @@ function createEmptyExtensionRegistry(
   };
 }
 
-function createExtensionOwner(
-  extensionPath: string,
-  source: LocalExtensionSource,
+function createModOwner(
+  modPath: string,
+  source: LocalModSource,
   generation: number,
-): ExtensionOwner {
+): ModOwner {
   return {
-    id: `${source.scope}:${extensionPath}`,
-    path: extensionPath,
+    id: `${source.scope}:${modPath}`,
+    path: modPath,
     scope: source.scope,
     generation,
   };
 }
 
-function isOwnerLive(
-  registry: LocalExtensionRegistry,
-  owner: ExtensionOwner,
-): boolean {
+function isOwnerLive(registry: LocalModRegistry, owner: ModOwner): boolean {
   return registry.owners[owner.id]?.generation === owner.generation;
 }
 
 function snapshotRegistryForReaders(
-  registry: LocalExtensionRegistry,
-): LocalExtensionRegistry {
+  registry: LocalModRegistry,
+): LocalModRegistry {
   return {
     ...registry,
     commands: { ...registry.commands },
-    capabilities: cloneExtensionCapabilities(registry.capabilities),
+    capabilities: cloneModCapabilities(registry.capabilities),
     diagnostics: [...registry.diagnostics],
     disposers: [...registry.disposers],
     events: Object.fromEntries(
       Object.entries(registry.events).map(([name, handlers]) => [
         name,
         handlers ? [...handlers] : [],
       ]),
-    ) as LocalExtensionEventsRegistry,
+    ) as LocalModEventsRegistry,
     loadedPaths: [...registry.loadedPaths],
     ownerAbortControllers: { ...registry.ownerAbortControllers },
     owners: { ...registry.owners },
@@ -364,8 +353,8 @@ function snapshotRegistryForReaders(
 }
 
 function removeOwnerCapabilities(
-  registry: LocalExtensionRegistry,
-  owner: ExtensionOwner,
+  registry: LocalModRegistry,
+  owner: ModOwner,
 ): void {
   unregisterPiProvidersForOwner(owner.id);
   clearAvailableModelsCache();
@@ -381,9 +370,9 @@ function removeOwnerCapabilities(
       (registration) => registration.owner?.id !== owner.id,
     );
     if (nextRegistrations && nextRegistrations.length > 0) {
-      registry.events[name as ExtensionEventName] = nextRegistrations;
+      registry.events[name as ModEventName] = nextRegistrations;
     } else {
-      delete registry.events[name as ExtensionEventName];
+      delete registry.events[name as ModEventName];
     }
   }
 
@@ -399,7 +388,7 @@ function removeOwnerCapabilities(
     }
   }
 
-  unregisterExtensionToolsForOwner(owner);
+  unregisterModToolsForOwner(owner);
 
   for (const [key, statusOwner] of Object.entries(registry.ui.statusOwners)) {
     if (statusOwner.id === owner.id) {
@@ -438,7 +427,7 @@ function ensureRuntimeDependencySymlink(
   );
 }
 
-function ensureExtensionCache(cacheDirectory: string): void {
+function ensureModCache(cacheDirectory: string): void {
   mkdirSync(cacheDirectory, { recursive: true });
   ensureRuntimeDependencySymlink(cacheDirectory, "react");
 }
@@ -455,17 +444,14 @@ function formatTranspileDiagnostic(diagnostic: ts.Diagnostic): string {
   return `${diagnostic.file.fileName}:${position.line + 1}:${position.character + 1} ${message}`;
 }
 
-function transpileTypeScriptExtension(
-  extensionPath: string,
-  source: string,
-): string {
+function transpileTypeScriptMod(modPath: string, source: string): string {
   const result = ts.transpileModule(source, {
     compilerOptions: {
       jsx: ts.JsxEmit.ReactJSX,
       module: ts.ModuleKind.ES2022,
       target: ts.ScriptTarget.ES2022,
     },
-    fileName: extensionPath,
+    fileName: modPath,
     reportDiagnostics: true,
   });
 
@@ -479,34 +465,31 @@ function transpileTypeScriptExtension(
   return result.outputText;
 }
 
-function prepareExtensionForImport(
-  extensionPath: string,
-  source: string,
-): string {
-  const extension = path.extname(extensionPath);
-  if (TYPESCRIPT_EXTENSION_FILE_EXTENSIONS.has(extension)) {
-    return transpileTypeScriptExtension(extensionPath, source);
+function prepareModForImport(modPath: string, source: string): string {
+  const fileExtension = path.extname(modPath);
+  if (TYPESCRIPT_MOD_FILE_EXTENSIONS.has(fileExtension)) {
+    return transpileTypeScriptMod(modPath, source);
   }
 
   return source;
 }
 
-function createImportableExtensionPath(
-  extensionPath: string,
+function createImportableModPath(
+  modPath: string,
   cacheDirectory: string,
 ): string {
-  ensureExtensionCache(cacheDirectory);
+  ensureModCache(cacheDirectory);
 
-  const source = readFileSync(extensionPath, "utf8");
+  const source = readFileSync(modPath, "utf8");
   const hash = createHash("sha256").update(source).digest("hex").slice(0, 16);
-  const extension = path.extname(extensionPath);
-  const importableSource = prepareExtensionForImport(extensionPath, source);
+  const fileExtension = path.extname(modPath);
+  const importableSource = prepareModForImport(modPath, source);
   const baseName = path
-    .basename(extensionPath, extension)
+    .basename(modPath, fileExtension)
     .replace(/[^a-zA-Z0-9_-]/g, "-");
   const importPath = path.join(
     cacheDirectory,
-    `.letta-extension-${baseName}-${hash}.mjs`,
+    `.letta-mod-${baseName}-${hash}.mjs`,
   );
 
   if (!existsSync(importPath)) {
@@ -516,7 +499,7 @@ function createImportableExtensionPath(
   try {
     for (const entry of readdirSync(cacheDirectory)) {
       if (
-        entry.startsWith(`.letta-extension-${baseName}-`) &&
+        entry.startsWith(`.letta-mod-${baseName}-`) &&
         entry !== path.basename(importPath)
       ) {
         unlinkSync(path.join(cacheDirectory, entry));
@@ -531,13 +514,13 @@ function createImportableExtensionPath(
 
 function toStatuslineRenderer(
   renderer: StatuslineRenderer | StatuslineRenderFunction,
-  extensionPath: string,
+  modPath: string,
 ): StatuslineRenderer {
   if (typeof renderer === "function") {
     return {
-      id: `local:${extensionPath}`,
-      label: path.basename(extensionPath),
-      description: extensionPath,
+      id: `local:${modPath}`,
+      label: path.basename(modPath),
+      description: modPath,
       render: renderer,
     };
   }
@@ -575,24 +558,22 @@ function createLazyClient(getClient: () => Promise<Letta>): Letta {
   return createProxy() as Letta;
 }
 
-const SUPPORTED_EXTENSION_EVENT_NAMES = new Set<ExtensionEventName>([
+const SUPPORTED_MOD_EVENT_NAMES = new Set<ModEventName>([
   "conversation_open",
   "conversation_close",
   "tool_start",
   "turn_start",
 ]);
 
-function validateExtensionEventName(
-  name: string,
-): asserts name is ExtensionEventName {
-  if (!SUPPORTED_EXTENSION_EVENT_NAMES.has(name as ExtensionEventName)) {
-    throw new Error(`Unsupported extension event '${name}'`);
+function validateModEventName(name: string): asserts name is ModEventName {
+  if (!SUPPORTED_MOD_EVENT_NAMES.has(name as ModEventName)) {
+    throw new Error(`Unsupported mod event '${name}'`);
   }
 }
 
-function isExtensionEventCapabilityEnabled(
-  capabilities: ExtensionCapabilities,
-  name: ExtensionEventName,
+function isModEventCapabilityEnabled(
+  capabilities: ModCapabilities,
+  name: ModEventName,
 ): boolean {
   switch (name) {
     case "conversation_open":
@@ -606,9 +587,9 @@ function isExtensionEventCapabilityEnabled(
 }
 
 function isTurnStartResultWithInput(
-  name: ExtensionEventName,
+  name: ModEventName,
   result: unknown,
-): result is { input: ExtensionTurnStartEvent["input"] } {
+): result is { input: ModTurnStartEvent["input"] } {
   return (
     name === "turn_start" &&
     typeof result === "object" &&
@@ -617,25 +598,23 @@ function isTurnStartResultWithInput(
   );
 }
 
-function isTurnStartInput(
-  value: unknown,
-): value is ExtensionTurnStartEvent["input"] {
+function isTurnStartInput(value: unknown): value is ModTurnStartEvent["input"] {
   return (
     Array.isArray(value) &&
     value.every((item) => typeof item === "object" && item !== null)
   );
 }
 
 function cloneTurnStartInput(
-  input: ExtensionTurnStartEvent["input"],
-): ExtensionTurnStartEvent["input"] {
+  input: ModTurnStartEvent["input"],
+): ModTurnStartEvent["input"] {
   return input.map((item) => structuredClone(item));
 }
 
 function isToolStartResultWithArgs(
-  name: ExtensionEventName,
+  name: ModEventName,
   result: unknown,
-): result is { args: ExtensionToolStartEvent["args"] } {
+): result is { args: ModToolStartEvent["args"] } {
   return (
     name === "tool_start" &&
     typeof result === "object" &&
@@ -644,45 +623,41 @@ function isToolStartResultWithArgs(
   );
 }
 
-function isToolStartArgs(
-  value: unknown,
-): value is ExtensionToolStartEvent["args"] {
+function isToolStartArgs(value: unknown): value is ModToolStartEvent["args"] {
   return typeof value === "object" && value !== null && !Array.isArray(value);
 }
 
 function cloneToolStartArgs(
-  args: ExtensionToolStartEvent["args"],
-): ExtensionToolStartEvent["args"] {
+  args: ModToolStartEvent["args"],
+): ModToolStartEvent["args"] {
   try {
     return structuredClone(args);
   } catch {
     return { ...args };
   }
 }
 
-function validateExtensionCommandId(id: string): void {
+function validateModCommandId(id: string): void {
   if (id.startsWith("/")) {
-    throw new Error("Extension command id must not start with '/'");
+    throw new Error("Mod command id must not start with '/'");
   }
   if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) {
     throw new Error(
-      "Extension command id must be a lowercase slug using letters, numbers, and hyphens",
+      "Mod command id must be a lowercase slug using letters, numbers, and hyphens",
     );
   }
 }
 
-function normalizeExtensionCommand(
-  command: ExtensionCommandRegistration,
-  owner: ExtensionOwner,
-): ExtensionCommand {
-  validateExtensionCommandId(command.id);
+function normalizeModCommand(
+  command: ModCommandRegistration,
+  owner: ModOwner,
+): ModCommand {
+  validateModCommandId(command.id);
   if (!command.description.trim()) {
-    throw new Error(
-      `Extension command '${command.id}' must include a description`,
-    );
+    throw new Error(`Mod command '${command.id}' must include a description`);
   }
   if (typeof command.run !== "function") {
-    throw new Error(`Extension command '${command.id}' must include run()`);
+    throw new Error(`Mod command '${command.id}' must include run()`);
   }
 
   return {
@@ -698,23 +673,21 @@ function normalizeExtensionCommand(
   };
 }
 
-function validateExtensionPermissionId(id: string): void {
+function validateModPermissionId(id: string): void {
   if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) {
     throw new Error(
-      "Extension permission id must be a lowercase slug using letters, numbers, and hyphens",
+      "Mod permission id must be a lowercase slug using letters, numbers, and hyphens",
     );
   }
 }
 
-function normalizeExtensionPermission(
-  permission: ExtensionPermissionRegistration,
-  owner: ExtensionOwner,
-): ExtensionPermission {
-  validateExtensionPermissionId(permission.id);
+function normalizeModPermission(
+  permission: ModPermissionRegistration,
+  owner: ModOwner,
+): ModPermission {
+  validateModPermissionId(permission.id);
   if (typeof permission.check !== "function") {
-    throw new Error(
-      `Extension permission '${permission.id}' must include check()`,
-    );
+    throw new Error(`Mod permission '${permission.id}' must include check()`);
   }
 
   return {
@@ -727,15 +700,15 @@ function normalizeExtensionPermission(
   };
 }
 
-function validateExtensionToolName(name: string): void {
+function validateModToolName(name: string): void {
   if (!/^[a-zA-Z0-9_-]{1,64}$/.test(name)) {
     throw new Error(
-      "Extension tool name must be 1-64 characters using letters, numbers, underscores, or hyphens",
+      "Mod tool name must be 1-64 characters using letters, numbers, underscores, or hyphens",
     );
   }
 }
 
-function normalizeExtensionToolParameters(
+function normalizeModToolParameters(
   parameters: Record<string, unknown> | undefined,
 ): Record<string, unknown> {
   if (!parameters) {
@@ -750,32 +723,27 @@ function normalizeExtensionToolParameters(
     parameters === null ||
     Array.isArray(parameters)
   ) {
-    throw new Error("Extension tool parameters must be a JSON Schema object");
+    throw new Error("Mod tool parameters must be a JSON Schema object");
   }
   if (parameters.type !== undefined && parameters.type !== "object") {
-    throw new Error(
-      "Extension tool parameters schema must be an object schema",
-    );
+    throw new Error("Mod tool parameters schema must be an object schema");
   }
   return parameters;
 }
 
-function normalizeExtensionTool(
-  tool: ExtensionToolRegistration,
-  owner: ExtensionOwner,
-): ExtensionTool {
-  validateExtensionToolName(tool.name);
+function normalizeModTool(tool: ModToolRegistration, owner: ModOwner): ModTool {
+  validateModToolName(tool.name);
   if (!tool.description.trim()) {
-    throw new Error(`Extension tool '${tool.name}' must include a description`);
+    throw new Error(`Mod tool '${tool.name}' must include a description`);
   }
   if (typeof tool.run !== "function") {
-    throw new Error(`Extension tool '${tool.name}' must include run()`);
+    throw new Error(`Mod tool '${tool.name}' must include run()`);
   }
 
   return {
     name: tool.name,
     description: tool.description,
-    parameters: normalizeExtensionToolParameters(tool.parameters),
+    parameters: normalizeModToolParameters(tool.parameters),
     owner,
     path: owner.path,
     requiresApproval: tool.requiresApproval !== false,
@@ -785,33 +753,31 @@ function normalizeExtensionTool(
   };
 }
 
-function validateExtensionPanelId(id: string): void {
+function validateModPanelId(id: string): void {
   if (!id.trim()) {
-    throw new Error("Extension panel id must not be empty");
+    throw new Error("Mod panel id must not be empty");
   }
 }
 
-function getExtensionPanelKey(extensionPath: string, id: string): string {
-  return JSON.stringify([extensionPath, id]);
+function getModPanelKey(modPath: string, id: string): string {
+  return JSON.stringify([modPath, id]);
 }
 
-function normalizePanelContent(
-  content: ExtensionPanelContent | undefined,
-): string[] {
+function normalizePanelContent(content: ModPanelContent | undefined): string[] {
   if (content == null) return [];
   return Array.isArray(content)
     ? content.map(String)
     : String(content).split("\n");
 }
 
-function upsertExtensionPanel(
-  registry: LocalExtensionRegistry,
-  owner: ExtensionOwner,
+function upsertModPanel(
+  registry: LocalModRegistry,
+  owner: ModOwner,
   id: string,
-  update: ExtensionPanelUpdate,
+  update: ModPanelUpdate,
 ): void {
-  validateExtensionPanelId(id);
-  const panelKey = getExtensionPanelKey(owner.id, id);
+  validateModPanelId(id);
+  const panelKey = getModPanelKey(owner.id, id);
   const existing = registry.ui.panels[panelKey];
   registry.ui.panels[panelKey] = {
     content:
@@ -826,40 +792,38 @@ function upsertExtensionPanel(
   };
 }
 
-function createLettaExtensionApi(
-  registry: LocalExtensionRegistry,
-  owner: ExtensionOwner,
-  capabilities: ExtensionCapabilities,
+function createLettaModApi(
+  registry: LocalModRegistry,
+  owner: ModOwner,
+  capabilities: ModCapabilities,
   getClient: () => Promise<Letta>,
-  getContext: () => ExtensionContext,
+  getContext: () => ModContext,
   onChange: () => void,
-  onDiagnostic: ((diagnostic: ExtensionDiagnostic) => void) | undefined,
+  onDiagnostic: ((diagnostic: ModDiagnostic) => void) | undefined,
   builtinCommandIds: Set<string>,
   reservedToolNames: Set<string>,
   signal: AbortSignal,
-): LettaExtensionApi {
+): LettaModApi {
   const isLive = () => isOwnerLive(registry, owner);
-  const guardLive = (
-    capability: ExtensionDiagnostic["capability"],
-  ): boolean => {
+  const guardLive = (capability: ModDiagnostic["capability"]): boolean => {
     if (isLive()) return true;
     recordStaleHandleUse(registry, owner, capability, onDiagnostic);
     return false;
   };
 
-  const unregisterEvent = <TName extends ExtensionEventName>(
+  const unregisterEvent = <TName extends ModEventName>(
     name: TName,
-    handler: ExtensionEventHandler<TName>,
+    handler: ModEventHandler<TName>,
   ) => {
-    validateExtensionEventName(name);
-    if (!isExtensionEventCapabilityEnabled(capabilities, name)) return;
+    validateModEventName(name);
+    if (!isModEventCapabilityEnabled(capabilities, name)) return;
     if (!guardLive({ id: name, kind: "event" })) return;
     const registrations = registry.events[name];
     if (!registrations) return;
     const nextRegistrations = registrations.filter(
       (registration) =>
         registration.owner?.id !== owner.id ||
-        registration.handler !== (handler as unknown as ExtensionEventHandler),
+        registration.handler !== (handler as unknown as ModEventHandler),
     );
     if (nextRegistrations.length > 0) {
       registry.events[name] = nextRegistrations;
@@ -871,7 +835,7 @@ function createLettaExtensionApi(
 
   const unregisterCommand = (id: string) => {
     if (!capabilities.commands) return;
-    validateExtensionCommandId(id);
+    validateModCommandId(id);
     if (!guardLive({ id, kind: "command" })) return;
     const existing = registry.commands[id];
     if (existing?.owner?.id === owner.id) {
@@ -882,21 +846,21 @@ function createLettaExtensionApi(
 
   const unregisterPermission = (id: string) => {
     if (!capabilities.permissions) return;
-    validateExtensionPermissionId(id);
+    validateModPermissionId(id);
     if (!guardLive({ id, kind: "permission" })) return;
     const existing = registry.permissions[id];
     if (existing?.owner?.id === owner.id) {
       delete registry.permissions[id];
-      unregisterExtensionPermission(id, owner);
+      unregisterModPermission(id, owner);
       onChange();
     }
   };
 
   const clearPanel = (id: string) => {
     if (!capabilities.ui.panels) return;
-    validateExtensionPanelId(id);
+    validateModPanelId(id);
     if (!guardLive({ id, kind: "panel" })) return;
-    const panelKey = getExtensionPanelKey(owner.id, id);
+    const panelKey = getModPanelKey(owner.id, id);
     const existing = registry.ui.panels[panelKey];
     if (existing?.owner?.id === owner.id) {
       delete registry.ui.panels[panelKey];
@@ -906,12 +870,12 @@ function createLettaExtensionApi(
 
   const unregisterTool = (name: string) => {
     if (!capabilities.tools) return;
-    validateExtensionToolName(name);
+    validateModToolName(name);
     if (!guardLive({ id: name, kind: "tool" })) return;
     const existing = registry.tools[name];
     if (existing?.owner?.id === owner.id) {
       delete registry.tools[name];
-      unregisterExtensionTool(name, owner);
+      unregisterModTool(name, owner);
       onChange();
     }
   };
@@ -927,7 +891,7 @@ function createLettaExtensionApi(
   const registerProviderForOwner = (
     name: string,
     config: PiProviderRegistration,
-  ): LettaExtensionDisposer => {
+  ): LettaModDisposer => {
     if (!capabilities.providers) {
       return () => undefined;
     }
@@ -944,37 +908,35 @@ function createLettaExtensionApi(
   };
 
   const normalizeReportedDiagnostic = (
-    diagnostic: ExtensionDiagnosticReportOptions,
-  ): { message: string; severity: ExtensionDiagnosticSeverity } => {
+    diagnostic: ModDiagnosticReportOptions,
+  ): { message: string; severity: ModDiagnosticSeverity } => {
     if (!diagnostic || typeof diagnostic !== "object") {
-      throw new Error("Extension diagnostic report must be an object");
+      throw new Error("Mod diagnostic report must be an object");
     }
     if (typeof diagnostic.message !== "string") {
-      throw new Error("Extension diagnostic report must include a message");
+      throw new Error("Mod diagnostic report must include a message");
     }
     const message = diagnostic.message.trim();
     if (message.length === 0) {
-      throw new Error("Extension diagnostic report message cannot be empty");
+      throw new Error("Mod diagnostic report message cannot be empty");
     }
     if (
       diagnostic.severity !== undefined &&
       diagnostic.severity !== "error" &&
       diagnostic.severity !== "warning"
     ) {
-      throw new Error(
-        "Extension diagnostic severity must be 'error' or 'warning'",
-      );
+      throw new Error("Mod diagnostic severity must be 'error' or 'warning'");
     }
     return { message, severity: diagnostic.severity ?? "error" };
   };
 
-  const reportDiagnostic = (diagnostic: ExtensionDiagnosticReportOptions) => {
+  const reportDiagnostic = (diagnostic: ModDiagnosticReportOptions) => {
     if (!guardLive(undefined)) return;
     const normalized = normalizeReportedDiagnostic(diagnostic);
     const error = new Error(normalized.message);
-    error.name = "ExtensionDiagnosticReport";
+    error.name = "ModDiagnosticReport";
     error.stack = undefined;
-    recordExtensionDiagnostic(
+    recordModDiagnostic(
       registry,
       {
         error,
@@ -986,16 +948,16 @@ function createLettaExtensionApi(
     );
   };
 
-  const onEvent = <TName extends ExtensionEventName>(
+  const onEvent = <TName extends ModEventName>(
     name: TName,
-    handler: ExtensionEventHandler<TName>,
-  ): LettaExtensionDisposer => {
-    validateExtensionEventName(name);
-    if (!isExtensionEventCapabilityEnabled(capabilities, name)) {
+    handler: ModEventHandler<TName>,
+  ): LettaModDisposer => {
+    validateModEventName(name);
+    if (!isModEventCapabilityEnabled(capabilities, name)) {
       return () => undefined;
     }
     if (typeof handler !== "function") {
-      throw new Error("Extension event registration must include a handler");
+      throw new Error("Mod event registration must include a handler");
     }
     if (!guardLive({ id: name, kind: "event" })) {
       return () => undefined;
@@ -1004,7 +966,7 @@ function createLettaExtensionApi(
     registry.events[name] = [
       ...(registry.events[name] ?? []),
       {
-        handler: handler as unknown as ExtensionEventHandler,
+        handler: handler as unknown as ModEventHandler,
         name,
         owner,
       },
@@ -1015,7 +977,7 @@ function createLettaExtensionApi(
   };
 
   return {
-    capabilities: cloneExtensionCapabilities(capabilities),
+    capabilities: cloneModCapabilities(capabilities),
     client: createLazyClient(getClient),
     getClient,
     getContext,
@@ -1031,14 +993,14 @@ function createLettaExtensionApi(
           return () => undefined;
         }
 
-        const normalized = normalizeExtensionCommand(command, owner);
+        const normalized = normalizeModCommand(command, owner);
         if (builtinCommandIds.has(normalized.id)) {
-          recordExtensionDiagnostic(
+          recordModDiagnostic(
             registry,
             {
               capability: { id: normalized.id, kind: "command" },
               error: new Error(
-                `Extension command '${normalized.id}' overrides a built-in command`,
+                `Mod command '${normalized.id}' overrides a built-in command`,
               ),
               owner,
               phase: "command_override",
@@ -1050,7 +1012,7 @@ function createLettaExtensionApi(
         const existing = registry.commands[normalized.id];
         if (existing && !command.override) {
           throw new Error(
-            `Extension command '${normalized.id}' is already registered by ${existing.path}`,
+            `Mod command '${normalized.id}' is already registered by ${existing.path}`,
           );
         }
 
@@ -1070,23 +1032,23 @@ function createLettaExtensionApi(
           return () => undefined;
         }
 
-        const normalized = normalizeExtensionTool(tool, owner);
+        const normalized = normalizeModTool(tool, owner);
         if (reservedToolNames.has(normalized.name)) {
           throw new Error(
-            `Extension tool '${normalized.name}' conflicts with a built-in tool`,
+            `Mod tool '${normalized.name}' conflicts with a built-in tool`,
           );
         }
 
         const existing = registry.tools[normalized.name];
-        const existingGlobal = getExtensionToolDefinition(normalized.name);
+        const existingGlobal = getModToolDefinition(normalized.name);
         if ((existing || existingGlobal) && !tool.override) {
           throw new Error(
-            `Extension tool '${normalized.name}' is already registered by ${existing?.path ?? existingGlobal?.path}`,
+            `Mod tool '${normalized.name}' is already registered by ${existing?.path ?? existingGlobal?.path}`,
           );
         }
 
         registry.tools[normalized.name] = normalized;
-        registerExtensionTool({
+        registerModTool({
           ...normalized,
           activationSignal: signal,
           getContext,
@@ -1120,17 +1082,17 @@ function createLettaExtensionApi(
           return () => undefined;
         }
 
-        const normalized = normalizeExtensionPermission(permission, owner);
+        const normalized = normalizeModPermission(permission, owner);
         const existing = registry.permissions[normalized.id];
-        const existingGlobal = getExtensionPermissionDefinition(normalized.id);
+        const existingGlobal = getModPermissionDefinition(normalized.id);
         if (existing || existingGlobal) {
           throw new Error(
-            `Extension permission '${normalized.id}' is already registered by ${existing?.path ?? existingGlobal?.path}`,
+            `Mod permission '${normalized.id}' is already registered by ${existing?.path ?? existingGlobal?.path}`,
           );
         }
 
         registry.permissions[normalized.id] = normalized;
-        registerExtensionPermission({
+        registerModPermission({
           ...normalized,
           activationSignal: signal,
           getContext,
@@ -1171,15 +1133,15 @@ function createLettaExtensionApi(
           };
         }
 
-        upsertExtensionPanel(registry, owner, panel.id, panel);
+        upsertModPanel(registry, owner, panel.id, panel);
         onChange();
         return {
           close() {
             clearPanel(panel.id);
           },
           update(update) {
             if (!guardLive({ id: panel.id, kind: "panel" })) return;
-            upsertExtensionPanel(registry, owner, panel.id, update);
+            upsertModPanel(registry, owner, panel.id, update);
             onChange();
           },
         };
@@ -1211,16 +1173,16 @@ function createLettaExtensionApi(
   };
 }
 
-function getExtensionFactory(module: LocalExtensionModule): unknown {
+function getModFactory(module: LocalModModule): unknown {
   return typeof module.default === "function"
     ? module.default
     : module.activate;
 }
 
-export async function loadLocalExtensions(
-  options: LoadLocalExtensionsOptions,
-): Promise<LocalExtensionRegistry> {
-  const cacheDirectory = options.cacheDirectory ?? EXTENSION_CACHE_DIRECTORY;
+export async function loadLocalMods(
+  options: LoadLocalModsOptions,
+): Promise<LocalModRegistry> {
+  const cacheDirectory = options.cacheDirectory ?? MOD_CACHE_DIRECTORY;
   let clientPromise: Promise<Letta> | null = null;
   const getConfiguredClient = () => {
     clientPromise ??= options.getClient();
@@ -1229,54 +1191,45 @@ export async function loadLocalExtensions(
   const getContext =
     options.getContext ??
     (() => {
-      throw new Error("Extension context is not available yet");
+      throw new Error("Mod context is not available yet");
     });
   const onChange = options.onChange ?? (() => {});
-  const sources = resolveLocalExtensionSources(options);
-  const capabilities = resolveExtensionCapabilities(options.capabilities);
+  const sources = resolveLocalModSources(options);
+  const capabilities = resolveModCapabilities(options.capabilities);
   const generation = options.generation ?? 1;
   const builtinCommandIds = new Set([...(options.builtinCommandIds ?? [])]);
   const reservedToolNames = new Set([...(options.reservedToolNames ?? [])]);
-  const registry = createEmptyExtensionRegistry(
-    sources,
-    generation,
-    capabilities,
-  );
+  const registry = createEmptyModRegistry(sources, generation, capabilities);
 
   for (const source of sources) {
-    for (const extensionPath of source.files) {
-      const owner = createExtensionOwner(extensionPath, source, generation);
+    for (const modPath of source.files) {
+      const owner = createModOwner(modPath, source, generation);
       const abortController = new AbortController();
-      let failurePhase: ExtensionDiagnostic["phase"] = "import";
+      let failurePhase: ModDiagnostic["phase"] = "import";
       registry.ownerAbortControllers[owner.id] = abortController;
       registry.owners[owner.id] = owner;
 
       try {
-        const mtimeMs = statSync(extensionPath).mtimeMs;
-        failurePhase = TYPESCRIPT_EXTENSION_FILE_EXTENSIONS.has(
-          path.extname(extensionPath),
-        )
+        const mtimeMs = statSync(modPath).mtimeMs;
+        failurePhase = TYPESCRIPT_MOD_FILE_EXTENSIONS.has(path.extname(modPath))
           ? "transpile"
           : "import";
-        const importPath = createImportableExtensionPath(
-          extensionPath,
-          cacheDirectory,
-        );
+        const importPath = createImportableModPath(modPath, cacheDirectory);
         failurePhase = "import";
         const module = (await import(
-          `${pathToFileURL(importPath).href}?extension=${mtimeMs}`
-        )) as LocalExtensionModule;
-        const factory = getExtensionFactory(module);
+          `${pathToFileURL(importPath).href}?mod=${mtimeMs}`
+        )) as LocalModModule;
+        const factory = getModFactory(module);
         failurePhase = "activate";
 
         if (typeof factory !== "function") {
           throw new Error(
-            "Extension must export a default function or activate() function",
+            "Mod must export a default function or activate() function",
           );
         }
 
-        const dispose = await (factory as LettaExtensionFactory)(
-          createLettaExtensionApi(
+        const dispose = await (factory as LettaModFactory)(
+          createLettaModApi(
             registry,
             owner,
             capabilities,
@@ -1296,12 +1249,12 @@ export async function loadLocalExtensions(
             owner,
           });
         }
-        registry.loadedPaths.push(extensionPath);
+        registry.loadedPaths.push(modPath);
       } catch (error) {
         removeOwnerCapabilities(registry, owner);
-        abortController.abort("extension activation failed");
+        abortController.abort("mod activation failed");
         delete registry.ownerAbortControllers[owner.id];
-        recordExtensionDiagnostic(
+        recordModDiagnostic(
           registry,
           {
             error: error instanceof Error ? error : new Error(String(error)),
@@ -1317,9 +1270,9 @@ export async function loadLocalExtensions(
   return registry;
 }
 
-export function evaluateLocalExtensionStatuses(
-  registry: LocalExtensionRegistry | null,
-  context: ExtensionContext,
+export function evaluateLocalModStatuses(
+  registry: LocalModRegistry | null,
+  context: ModContext,
 ): Record<string, string> {
   if (!registry) return {};
 
@@ -1332,52 +1285,52 @@ export function evaluateLocalExtensionStatuses(
       }
     } catch {
       // Status providers run during render; failed providers are skipped so the
-      // extension cannot crash the TUI.
+      // mod cannot crash the TUI.
     }
   }
 
   return statuses;
 }
 
-export async function emitLocalExtensionEvent<TName extends ExtensionEventName>(
-  registry: LocalExtensionRegistry | null,
+export async function emitLocalModEvent<TName extends ModEventName>(
+  registry: LocalModRegistry | null,
   name: TName,
-  event: ExtensionEventMap[TName],
-  getContext: () => ExtensionContext,
+  event: ModEventMap[TName],
+  getContext: () => ModContext,
   backend?: Backend,
-  onDiagnostic?: (diagnostic: ExtensionDiagnostic) => void,
-): Promise<ExtensionEventEmissionResult<TName>> {
+  onDiagnostic?: (diagnostic: ModDiagnostic) => void,
+): Promise<ModEventEmissionResult<TName>> {
   if (!registry) {
     return { diagnostics: [], handlerCount: 0, name, results: [] };
   }
 
-  validateExtensionEventName(name);
+  validateModEventName(name);
   const registrations = [...(registry.events[name] ?? [])];
-  const diagnostics: ExtensionDiagnostic[] = [];
-  const results: Array<NonNullable<ExtensionEventResultMap[TName]>> = [];
+  const diagnostics: ModDiagnostic[] = [];
+  const results: Array<NonNullable<ModEventResultMap[TName]>> = [];
 
   for (const registration of registrations) {
     const signal = registration.owner
       ? registry.ownerAbortControllers[registration.owner.id]?.signal
       : undefined;
     if (signal?.aborted) continue;
     const turnStartEvent =
-      name === "turn_start" ? (event as ExtensionTurnStartEvent) : null;
+      name === "turn_start" ? (event as ModTurnStartEvent) : null;
     const turnStartInputBeforeHandler =
       turnStartEvent && isTurnStartInput(turnStartEvent.input)
         ? cloneTurnStartInput(turnStartEvent.input)
         : null;
     const toolStartEvent =
-      name === "tool_start" ? (event as ExtensionToolStartEvent) : null;
+      name === "tool_start" ? (event as ModToolStartEvent) : null;
     const toolStartArgsBeforeHandler =
       toolStartEvent && isToolStartArgs(toolStartEvent.args)
         ? cloneToolStartArgs(toolStartEvent.args)
         : null;
 
     try {
       const context = getContext();
-      const eventContext: ExtensionEventContext = {
-        conversation: createExtensionConversationHandle({
+      const eventContext: ModEventContext = {
+        conversation: createModConversationHandle({
           agentId:
             typeof event.agentId === "string"
               ? event.agentId
@@ -1396,13 +1349,13 @@ export async function emitLocalExtensionEvent<TName extends ExtensionEventName>(
       };
       const result = await registration.handler(event, eventContext);
       if (isTurnStartResultWithInput(name, result)) {
-        (event as ExtensionTurnStartEvent).input = result.input;
+        (event as ModTurnStartEvent).input = result.input;
       }
       if (isToolStartResultWithArgs(name, result)) {
-        (event as ExtensionToolStartEvent).args = result.args;
+        (event as ModToolStartEvent).args = result.args;
       }
       if (result != null) {
-        results.push(result as NonNullable<ExtensionEventResultMap[TName]>);
+        results.push(result as NonNullable<ModEventResultMap[TName]>);
       }
       if (
         turnStartEvent &&
@@ -1425,7 +1378,7 @@ export async function emitLocalExtensionEvent<TName extends ExtensionEventName>(
       if (toolStartEvent && toolStartArgsBeforeHandler) {
         toolStartEvent.args = toolStartArgsBeforeHandler;
       }
-      const diagnostic = recordExtensionDiagnostic(
+      const diagnostic = recordModDiagnostic(
         registry,
         {
           capability: { id: name, kind: "event" },
@@ -1442,9 +1395,9 @@ export async function emitLocalExtensionEvent<TName extends ExtensionEventName>(
   return { diagnostics, handlerCount: registrations.length, name, results };
 }
 
-export function disposeLocalExtensions(registry: LocalExtensionRegistry): void {
+export function disposeLocalMods(registry: LocalModRegistry): void {
   for (const abortController of Object.values(registry.ownerAbortControllers)) {
-    abortController.abort("extension disposed");
+    abortController.abort("mod disposed");
   }
 
   const disposers = [...registry.disposers].reverse();
@@ -1454,7 +1407,7 @@ export function disposeLocalExtensions(registry: LocalExtensionRegistry): void {
     try {
       dispose();
     } catch (error) {
-      recordExtensionDiagnostic(registry, {
+      recordModDiagnostic(registry, {
         error: error instanceof Error ? error : new Error(String(error)),
         owner,
         phase: "dispose",
@@ -1464,8 +1417,8 @@ export function disposeLocalExtensions(registry: LocalExtensionRegistry): void {
 
   for (const owner of Object.values(registry.owners)) {
     unregisterPiProvidersForOwner(owner.id);
-    unregisterExtensionPermissionsForOwner(owner);
-    unregisterExtensionToolsForOwner(owner);
+    unregisterModPermissionsForOwner(owner);
+    unregisterModToolsForOwner(owner);
   }
   clearAvailableModelsCache();
 
@@ -1482,22 +1435,18 @@ export function disposeLocalExtensions(registry: LocalExtensionRegistry): void {
   delete registry.ui.statuslineRendererOwner;
 }
 
-export function createExtensionEngine(
-  options: CreateExtensionEngineOptions,
-): ExtensionEngine {
-  const { getBackend, onDiagnostic, ...extensionOptions } = options;
+export function createModEngine(options: CreateModEngineOptions): ModEngine {
+  const { getBackend, onDiagnostic, ...modOptions } = options;
   let generation = 0;
   let disposed = false;
-  const capabilities = resolveExtensionCapabilities(
-    extensionOptions.capabilities,
-  );
+  const capabilities = resolveModCapabilities(modOptions.capabilities);
   const getContext =
-    extensionOptions.getContext ??
+    modOptions.getContext ??
     (() => {
-      throw new Error("Extension context is not available yet");
+      throw new Error("Mod context is not available yet");
     });
-  let activeRegistry = createEmptyExtensionRegistry(
-    resolveLocalExtensionSources(extensionOptions),
+  let activeRegistry = createEmptyModRegistry(
+    resolveLocalModSources(modOptions),
     generation,
     capabilities,
   );
@@ -1514,19 +1463,19 @@ export function createExtensionEngine(
   const reload = async () => {
     if (disposed) return;
 
-    disposeLocalExtensions(activeRegistry);
+    disposeLocalMods(activeRegistry);
     generation += 1;
     const loadGeneration = generation;
-    activeRegistry = createEmptyExtensionRegistry(
-      resolveLocalExtensionSources(extensionOptions),
+    activeRegistry = createEmptyModRegistry(
+      resolveLocalModSources(modOptions),
       loadGeneration,
       capabilities,
     );
     publish();
 
-    let loadingRegistry: LocalExtensionRegistry | null = null;
-    const nextRegistry = await loadLocalExtensions({
-      ...extensionOptions,
+    let loadingRegistry: LocalModRegistry | null = null;
+    const nextRegistry = await loadLocalMods({
+      ...modOptions,
       generation: loadGeneration,
       onChange: () => {
         if (!disposed && loadingRegistry && loadGeneration === generation) {
@@ -1546,14 +1495,14 @@ export function createExtensionEngine(
         // Stale handles from a prior generation report through their old
         // activation callback. Preserve the diagnostic on the current engine
         // snapshot without reviving the old registry.
-        appendExtensionDiagnostic(activeRegistry, diagnostic);
+        appendModDiagnostic(activeRegistry, diagnostic);
         publish();
         onDiagnostic?.(diagnostic);
       },
     });
     loadingRegistry = nextRegistry;
     if (disposed || loadGeneration !== generation) {
-      disposeLocalExtensions(nextRegistry);
+      disposeLocalMods(nextRegistry);
       return;
     }
 
@@ -1566,9 +1515,9 @@ export function createExtensionEngine(
       if (disposed) return;
       disposed = true;
       generation += 1;
-      disposeLocalExtensions(activeRegistry);
-      activeRegistry = createEmptyExtensionRegistry(
-        resolveLocalExtensionSources(extensionOptions),
+      disposeLocalMods(activeRegistry);
+      activeRegistry = createEmptyModRegistry(
+        resolveLocalModSources(modOptions),
         generation,
         capabilities,
       );
@@ -1580,7 +1529,7 @@ export function createExtensionEngine(
         return { diagnostics: [], handlerCount: 0, name, results: [] };
       }
       const invocationBackend = getBackend?.();
-      const result = await emitLocalExtensionEvent(
+      const result = await emitLocalModEvent(
         activeRegistry,
         name,
         payload,
diff --git a/src/mods/paths.ts b/src/mods/paths.ts
new file mode 100644
--- /dev/null
+++ b/src/mods/paths.ts
@@ -0,0 +1,29 @@
+import { existsSync } from "node:fs";
+import { homedir } from "node:os";
+import path from "node:path";
+
+export function getGlobalModsDirectory(homeDirectory = homedir()): string {
+  return path.join(homeDirectory, ".letta", "mods");
+}
+
+export function getLegacyGlobalExtensionsDirectory(
+  homeDirectory = homedir(),
+): string {
+  return path.join(homeDirectory, ".letta", "extensions");
+}
+
+export function resolveDefaultGlobalModsDirectory(
+  homeDirectory = homedir(),
+): string {
+  const modsDirectory = getGlobalModsDirectory(homeDirectory);
+  if (existsSync(modsDirectory)) return modsDirectory;
+
+  const legacyDirectory = getLegacyGlobalExtensionsDirectory(homeDirectory);
+  if (existsSync(legacyDirectory)) return legacyDirectory;
+
+  return modsDirectory;
+}
+
+export function getModCacheDirectory(homeDirectory = homedir()): string {
+  return path.join(homeDirectory, ".letta", "mod-cache");
+}
diff --git a/src/mods/permission-registry.ts b/src/mods/permission-registry.ts
new file mode 100644
--- /dev/null
+++ b/src/mods/permission-registry.ts
@@ -0,0 +1,160 @@
+import type {
+  ModContext,
+  ModOwner,
+  ModPermission,
+  ModPermissionCheckEvent,
+  ModPermissionCheckResult,
+} from "@/mods/types";
+import { areModsDisabled } from "./disable";
+
+const MOD_PERMISSIONS_KEY = Symbol.for("@letta/modPermissions");
+
+type GlobalWithModPermissions = typeof globalThis & {
+  [MOD_PERMISSIONS_KEY]?: Map<string, ModPermissionDefinition>;
+};
+
+export interface ModPermissionDefinition extends ModPermission {
+  activationSignal: AbortSignal;
+  getContext: () => ModContext;
+  isAvailable: () => boolean;
+}
+
+export interface ModPermissionDecisionResult {
+  decision: "allow" | "ask" | "deny";
+  matchedRule: string;
+  reason?: string;
+}
+
+function getMutableModPermissionsRegistry(): Map<
+  string,
+  ModPermissionDefinition
+> {
+  const global = globalThis as GlobalWithModPermissions;
+  if (!global[MOD_PERMISSIONS_KEY]) {
+    global[MOD_PERMISSIONS_KEY] = new Map();
+  }
+  return global[MOD_PERMISSIONS_KEY];
+}
+
+export function getAvailableModPermissionsRegistry(): Map<
+  string,
+  ModPermissionDefinition
+> {
+  if (areModsDisabled()) return new Map();
+
+  return new Map(
+    Array.from(getMutableModPermissionsRegistry().entries()).filter(
+      ([, permission]) => {
+        if (permission.activationSignal.aborted) return false;
+        try {
+          return permission.isAvailable();
+        } catch {
+          return false;
+        }
+      },
+    ),
+  );
+}
+
+export function registerModPermission(
+  permission: ModPermissionDefinition,
+): void {
+  if (areModsDisabled()) return;
+  getMutableModPermissionsRegistry().set(permission.id, permission);
+}
+
+export function unregisterModPermission(id: string, owner: ModOwner): void {
+  const registry = getMutableModPermissionsRegistry();
+  const existing = registry.get(id);
+  if (existing?.owner?.id === owner.id) {
+    registry.delete(id);
+  }
+}
+
+export function unregisterModPermissionsForOwner(owner: ModOwner): void {
+  const registry = getMutableModPermissionsRegistry();
+  for (const [id, permission] of registry.entries()) {
+    if (permission.owner?.id === owner.id) {
+      registry.delete(id);
+    }
+  }
+}
+
+export function clearModPermissions(): void {
+  getMutableModPermissionsRegistry().clear();
+}
+
+export function getModPermissionDefinition(
+  id: string,
+  registry: Map<
+    string,
+    ModPermissionDefinition
+  > = getMutableModPermissionsRegistry(),
+): ModPermissionDefinition | undefined {
+  if (areModsDisabled()) return undefined;
+  return registry.get(id);
+}
+
+function normalizePermissionResult(
+  result: ModPermissionCheckResult,
+): ModPermissionCheckResult {
+  if (result === undefined) return undefined;
+  if (
+    result.decision === "allow" ||
+    result.decision === "ask" ||
+    result.decision === "deny"
+  ) {
+    return result;
+  }
+  return undefined;
+}
+
+function composePermissionDecision(
+  decisions: ModPermissionDecisionResult[],
+): ModPermissionDecisionResult | undefined {
+  return (
+    decisions.find((result) => result.decision === "deny") ??
+    decisions.find((result) => result.decision === "ask") ??
+    decisions.find((result) => result.decision === "allow")
+  );
+}
+
+export async function checkModPermissions(
+  event: ModPermissionCheckEvent,
+  registry: Map<
+    string,
+    ModPermissionDefinition
+  > = getAvailableModPermissionsRegistry(),
+): Promise<ModPermissionDecisionResult | undefined> {
+  if (areModsDisabled()) return undefined;
+
+  const decisions: ModPermissionDecisionResult[] = [];
+  for (const permission of registry.values()) {
+    if (permission.activationSignal.aborted) continue;
+
+    let rawResult: ModPermissionCheckResult;
+    try {
+      if (!permission.isAvailable()) continue;
+      rawResult = await permission.check(event, {
+        getContext: permission.getContext,
+        signal: permission.activationSignal,
+      });
+    } catch (error) {
+      return {
+        decision: "deny",
+        matchedRule: `mod permission:${permission.id}`,
+        reason: `Mod permission '${permission.id}' failed: ${error instanceof Error ? error.message : String(error)}`,
+      };
+    }
+
+    const result = normalizePermissionResult(rawResult);
+    if (!result) continue;
+    decisions.push({
+      decision: result.decision,
+      matchedRule: `mod permission:${permission.id}`,
+      reason: result.reason,
+    });
+  }
+
+  return composePermissionDecision(decisions);
+}
diff --git a/src/mods/tool-registry.ts b/src/mods/tool-registry.ts
new file mode 100644
--- /dev/null
+++ b/src/mods/tool-registry.ts
@@ -0,0 +1,102 @@
+import type {
+  ModOwner,
+  ModTool,
+  ModToolRunContext,
+  ModToolRunResult,
+} from "@/mods/types";
+import { areModsDisabled } from "./disable";
+
+const MOD_TOOLS_KEY = Symbol.for("@letta/modTools");
+
+type GlobalWithModTools = typeof globalThis & {
+  [MOD_TOOLS_KEY]?: Map<string, ModToolDefinition>;
+};
+
+export interface ModToolDefinition extends ModTool {
+  activationSignal: AbortSignal;
+  getContext: ModToolRunContext["getContext"];
+  isAvailable: () => boolean;
+}
+
+function getMutableModToolsRegistry(): Map<string, ModToolDefinition> {
+  const global = globalThis as GlobalWithModTools;
+  if (!global[MOD_TOOLS_KEY]) {
+    global[MOD_TOOLS_KEY] = new Map();
+  }
+  return global[MOD_TOOLS_KEY];
+}
+
+export function getAvailableModToolsRegistry(): Map<string, ModToolDefinition> {
+  if (areModsDisabled()) return new Map();
+
+  return new Map(
+    Array.from(getMutableModToolsRegistry().entries()).filter(([, tool]) => {
+      if (tool.activationSignal.aborted) return false;
+      try {
+        return tool.isAvailable();
+      } catch {
+        return false;
+      }
+    }),
+  );
+}
+
+export function registerModTool(tool: ModToolDefinition): void {
+  if (areModsDisabled()) return;
+  getMutableModToolsRegistry().set(tool.name, tool);
+}
+
+export function unregisterModTool(name: string, owner: ModOwner): void {
+  const registry = getMutableModToolsRegistry();
+  const existing = registry.get(name);
+  if (existing?.owner?.id === owner.id) {
+    registry.delete(name);
+  }
+}
+
+export function unregisterModToolsForOwner(owner: ModOwner): void {
+  const registry = getMutableModToolsRegistry();
+  for (const [name, tool] of registry.entries()) {
+    if (tool.owner?.id === owner.id) {
+      registry.delete(name);
+    }
+  }
+}
+
+export function clearModTools(): void {
+  getMutableModToolsRegistry().clear();
+}
+
+export function getModToolDefinition(
+  name: string,
+  registry: Map<string, ModToolDefinition> = getMutableModToolsRegistry(),
+): ModToolDefinition | undefined {
+  if (areModsDisabled()) return undefined;
+  return registry.get(name);
+}
+
+export function modToolRequiresApproval(
+  name: string,
+  registry: Map<string, ModToolDefinition> = getMutableModToolsRegistry(),
+): boolean | undefined {
+  if (areModsDisabled()) return undefined;
+  return registry.get(name)?.requiresApproval;
+}
+
+export function isModToolParallelSafe(
+  name: string,
+  registry: Map<string, ModToolDefinition> = getMutableModToolsRegistry(),
+): boolean {
+  if (areModsDisabled()) return false;
+  return registry.get(name)?.parallelSafe === true;
+}
+
+export async function runModTool(
+  tool: ModToolDefinition,
+  context: ModToolRunContext,
+): Promise<ModToolRunResult> {
+  if (tool.activationSignal.aborted) {
+    throw new Error(`Mod tool '${tool.name}' is no longer available`);
+  }
+  return tool.run(context);
+}
diff --git a/src/mods/types.ts b/src/mods/types.ts
new file mode 100644
--- /dev/null
+++ b/src/mods/types.ts
@@ -0,0 +1,499 @@
+import type { MessageCreate } from "@letta-ai/letta-client/resources/agents/agents";
+import type {
+  ApprovalCreate,
+  LettaStreamingResponse,
+  Message,
+} from "@letta-ai/letta-client/resources/agents/messages";
+
+export interface ModWorkspaceContext {
+  cwd: string;
+  currentDir: string;
+  projectDir: string;
+}
+
+export interface ModModelContext {
+  id: string | null;
+  displayName: string | null;
+  provider: string | null;
+  reasoningEffort: string | null;
+}
+
+export interface ModTokenUsageContext {
+  inputTokens: number | null;
+  outputTokens: number | null;
+  cacheCreationInputTokens: number | null;
+  cacheReadInputTokens: number | null;
+}
+
+export interface ModContextWindowContext {
+  size: number;
+  totalInputTokens: number;
+  totalOutputTokens: number;
+  usedPercentage: number | null;
+  remainingPercentage: number | null;
+  currentUsage: ModTokenUsageContext | null;
+}
+
+export interface ModCostContext {
+  totalDurationMs: number;
+  totalApiDurationMs: number;
+  totalCostUsd: number | null;
+  totalLinesAdded: number | null;
+  totalLinesRemoved: number | null;
+}
+
+export interface ModAgentContext {
+  id: string | null;
+  name: string | null;
+}
+
+export interface ModReflectionContext {
+  mode: "off" | "step-count" | "compaction-event" | null;
+  stepCount: number;
+}
+
+export interface ModMemfsContext {
+  enabled: boolean;
+  memoryDir: string | null;
+}
+
+export interface ModBackgroundAgentContext {
+  type: string;
+  status: string;
+  durationMs: number;
+}
+
+export interface ModUiCapabilities {
+  panels: boolean;
+  statusValues: boolean;
+  customStatuslineRenderer: boolean;
+}
+
+export interface ModEventCapabilities {
+  lifecycle: boolean;
+  tools: boolean;
+  turns: boolean;
+}
+
+export interface ModCapabilities {
+  tools: boolean;
+  commands: boolean;
+  events: ModEventCapabilities;
+  permissions: boolean;
+  providers: boolean;
+  ui: ModUiCapabilities;
+}
+
+export interface ModConversationForkOptions {
+  hidden?: boolean;
+}
+
+export type ModConversationMessage = MessageCreate | ApprovalCreate;
+
+export interface ModConversationSendMessageOptions {
+  background?: boolean;
+  overrideModel?: string;
+  skipImageNormalization?: boolean;
+  streamTokens?: boolean;
+  workingDirectory?: string;
+}
+
+export interface ModConversationSendMessageRequestOptions {
+  headers?: Record<string, string>;
+  maxRetries?: number;
+  signal?: AbortSignal;
+}
+
+export interface ModConversationHistoryOptions {
+  /** Maximum number of recent messages to return. Defaults to 100. */
+  limit?: number;
+  /** Return chronological (asc, default) or newest-first (desc) messages. */
+  order?: "asc" | "desc";
+  /** Include error messages and error statuses. Defaults to true. */
+  includeErrors?: boolean;
+}
+
+export interface ModConversationHandle {
+  id: string | null;
+  fork: (
+    options?: ModConversationForkOptions,
+  ) => Promise<ModConversationHandle>;
+  getHistory: (options?: ModConversationHistoryOptions) => Promise<Message[]>;
+  sendMessageStream: (
+    messages: ModConversationMessage[],
+    options?: ModConversationSendMessageOptions,
+    requestOptions?: ModConversationSendMessageRequestOptions,
+  ) => Promise<AsyncIterable<LettaStreamingResponse>>;
+}
+
+export type ModSourceScope = "global" | "project" | "bundled";
+
+export interface ModOwner {
+  id: string;
+  path: string;
+  scope: ModSourceScope;
+  generation: number;
+}
+
+export type ModEventName =
+  | "conversation_open"
+  | "conversation_close"
+  | "tool_start"
+  | "turn_start";
+
+export type ModConversationOpenReason =
+  | "startup"
+  | "new"
+  | "resume"
+  | "fork"
+  | "reload";
+
+export type ModConversationCloseReason =
+  | "quit"
+  | "new"
+  | "resume"
+  | "fork"
+  | "reload";
+
+export interface ModConversationOpenEvent {
+  agentId: string | null;
+  agentName: string | null;
+  conversationId: string | null;
+  previousConversationId?: string | null;
+  reason: ModConversationOpenReason;
+}
+
+export interface ModConversationCloseEvent {
+  agentId: string | null;
+  conversationId: string | null;
+  durationMs: number | null;
+  messageCount: number | null;
+  reason: ModConversationCloseReason;
+  toolCallCount: number | null;
+}
+
+export interface ModTurnStartEvent {
+  agentId: string | null;
+  conversationId: string | null;
+  input: Array<MessageCreate | ApprovalCreate>;
+}
+
+export interface ModTurnStartResult {
+  input?: Array<MessageCreate | ApprovalCreate>;
+}
+
+export interface ModToolStartEvent {
+  agentId: string | null;
+  conversationId: string | null;
+  toolCallId: string | null;
+  toolName: string;
+  args: Record<string, unknown>;
+}
+
+export interface ModToolStartResult {
+  args?: Record<string, unknown>;
+}
+
+export interface ModEventMap {
+  conversation_open: ModConversationOpenEvent;
+  conversation_close: ModConversationCloseEvent;
+  tool_start: ModToolStartEvent;
+  turn_start: ModTurnStartEvent;
+}
+
+export interface ModEventResultMap {
+  conversation_open: undefined;
+  conversation_close: undefined;
+  tool_start: ModToolStartResult | undefined;
+  turn_start: ModTurnStartResult | undefined;
+}
+
+export interface ModEventContext {
+  conversation: ModConversationHandle;
+  context: ModContext;
+  getContext: () => ModContext;
+  signal: AbortSignal;
+}
+
+export type ModEventHandler<TName extends ModEventName = ModEventName> = (
+  event: ModEventMap[TName],
+  context: ModEventContext,
+) => ModEventResultMap[TName] | Promise<ModEventResultMap[TName]>;
+
+export interface ModEventRegistration<
+  TName extends ModEventName = ModEventName,
+> {
+  handler: ModEventHandler<TName>;
+  name: TName;
+  owner: ModOwner;
+}
+
+export interface ModEventEmissionResult<
+  TName extends ModEventName = ModEventName,
+> {
+  diagnostics: ModDiagnostic[];
+  handlerCount: number;
+  name: TName;
+  results: Array<NonNullable<ModEventResultMap[TName]>>;
+}
+
+export type ModCapabilityKind =
+  | "command"
+  | "event"
+  | "permission"
+  | "provider"
+  | "tool"
+  | "panel"
+  | "status"
+  | "statusline";
+
+export interface ModCapabilityRecord<T> {
+  id: string;
+  kind: ModCapabilityKind;
+  owner: ModOwner;
+  value: T;
+  createdAt: number;
+}
+
+export type ModDiagnosticPhase =
+  | "transpile"
+  | "import"
+  | "activate"
+  | "command_override"
+  | "dispose"
+  | "event"
+  | "report"
+  | "stale_handle";
+
+export type ModDiagnosticSeverity = "error" | "warning";
+
+export interface ModDiagnosticReportOptions {
+  message: string;
+  severity?: ModDiagnosticSeverity;
+}
+
+export interface ModDiagnostic {
+  capability?: {
+    id: string;
+    kind: ModCapabilityKind;
+  };
+  error: Error;
+  owner: ModOwner;
+  phase: ModDiagnosticPhase;
+  severity?: ModDiagnosticSeverity;
+  timestamp: number;
+}
+
+export interface ModContext {
+  app: {
+    version: string;
+  };
+  workspace: ModWorkspaceContext;
+  cwd: string;
+  sessionId: string | null;
+  lastRunId: string | null;
+  agent: ModAgentContext;
+  model: ModModelContext;
+  toolset: string | null;
+  systemPromptId: string | null;
+  permissionMode: string | null;
+  networkPhase: "upload" | "download" | "error" | null;
+  terminalWidth: number | null;
+  contextWindow: ModContextWindowContext;
+  cost: ModCostContext;
+  reflection: ModReflectionContext;
+  memfs: ModMemfsContext;
+  backgroundAgents: ModBackgroundAgentContext[];
+}
+
+export interface ModCommandContext {
+  rawInput: string;
+  command: string;
+  args: string;
+  argv: string[];
+  cwd: string;
+  agent: {
+    id: string;
+    name: string | null;
+  };
+  conversation: ModConversationHandle & { id: string };
+  model: {
+    id: string | null;
+    displayName: string | null;
+  };
+  permissionMode: string | null;
+  getContext: () => ModContext;
+}
+
+export type ModCommandResult =
+  | { type: "prompt"; content: string; systemReminder?: boolean }
+  | { type: "output"; output: string; success?: boolean }
+  | { type: "handled" };
+
+export type ModPanelContent = string | string[];
+
+export interface ModPanelOptions {
+  content?: ModPanelContent;
+  id: string;
+  order?: number;
+}
+
+export interface ModPanelUpdate {
+  content?: ModPanelContent;
+  order?: number;
+}
+
+export interface ModPanel {
+  content: string[];
+  id: string;
+  owner?: ModOwner;
+  order: number;
+  path: string;
+  updatedAt: number;
+}
+
+export interface ModPanelHandle {
+  close: () => void;
+  update: (update: ModPanelUpdate) => void;
+}
+
+export interface ModCommandRegistration {
+  id: string;
+  description: string;
+  args?: string;
+  order?: number;
+  override?: boolean;
+  runWhenBusy?: boolean;
+  showInTranscript?: boolean;
+  run: (
+    context: ModCommandContext,
+  ) => ModCommandResult | Promise<ModCommandResult>;
+}
+
+export interface ModCommand {
+  id: string;
+  description: string;
+  args?: string;
+  owner?: ModOwner;
+  order: number;
+  path: string;
+  runWhenBusy: boolean;
+  showInTranscript: boolean;
+  run: ModCommandRegistration["run"];
+}
+
+export interface ModToolContentText {
+  type: "text";
+  text: string;
+}
+
+export interface ModToolContentImage {
+  type: "image";
+  source: {
+    type: "base64";
+    media_type: string;
+    data: string;
+  };
+}
+
+export type ModToolContent = ModToolContentText | ModToolContentImage;
+
+export type ModToolRunResult =
+  | string
+  | ModToolContent[]
+  | {
+      content?: string | ModToolContent[];
+      output?: string;
+      stdout?: string[];
+      stderr?: string[];
+      status?: "success" | "error";
+      isError?: boolean;
+      success?: boolean;
+    };
+
+export interface ModToolRunContext {
+  args: Record<string, unknown>;
+  cwd: string;
+  workingDirectory: string;
+  toolCallId: string | null;
+  signal: AbortSignal;
+  onOutput?: (chunk: string, stream: "stdout" | "stderr") => void;
+  permissionMode: string | null;
+  agent: {
+    id: string | null;
+  };
+  conversation: ModConversationHandle;
+  getContext: () => ModContext;
+}
+
+export interface ModToolRegistration {
+  name: string;
+  description: string;
+  parameters?: Record<string, unknown>;
+  override?: boolean;
+  requiresApproval?: boolean;
+  parallelSafe?: boolean;
+  isEnabled?: (context: ModContext) => boolean;
+  run: (
+    context: ModToolRunContext,
+  ) => ModToolRunResult | Promise<ModToolRunResult>;
+}
+
+export interface ModTool {
+  name: string;
+  description: string;
+  parameters: Record<string, unknown>;
+  owner?: ModOwner;
+  path: string;
+  requiresApproval: boolean;
+  parallelSafe: boolean;
+  isEnabled?: ModToolRegistration["isEnabled"];
+  run: ModToolRegistration["run"];
+}
+
+export type ModPermissionDecision = "allow" | "ask" | "deny";
+
+export type ModPermissionCheckPhase = "approval" | "execution";
+
+export interface ModPermissionCheckEvent {
+  agentId: string | null;
+  conversationId: string | null;
+  toolCallId: string | null;
+  toolName: string;
+  args: Record<string, unknown>;
+  cwd: string;
+  workingDirectory: string;
+  permissionMode: string | null;
+  phase: ModPermissionCheckPhase;
+}
+
+export type ModPermissionCheckResult =
+  | {
+      decision: ModPermissionDecision;
+      reason?: string;
+    }
+  | undefined;
+
+export interface ModPermissionCheckContext {
+  getContext: () => ModContext;
+  signal: AbortSignal;
+}
+
+export interface ModPermissionRegistration {
+  id: string;
+  description?: string;
+  isEnabled?: (context: ModContext) => boolean;
+  check: (
+    event: ModPermissionCheckEvent,
+    context: ModPermissionCheckContext,
+  ) => ModPermissionCheckResult | Promise<ModPermissionCheckResult>;
+}
+
+export interface ModPermission {
+  id: string;
+  description?: string;
+  owner?: ModOwner;
+  path: string;
+  isEnabled?: ModPermissionRegistration["isEnabled"];
+  check: ModPermissionRegistration["check"];
+}
diff --git a/src/permissions/checker.ts b/src/permissions/checker.ts
--- a/src/permissions/checker.ts
+++ b/src/permissions/checker.ts
@@ -3,13 +3,13 @@
 
 import { resolve } from "node:path";
 import { getCurrentAgentId } from "@/agent/context";
-import {
-  checkExtensionPermissions,
-  type ExtensionPermissionDefinition,
-  getAvailableExtensionPermissionsRegistry,
-} from "@/extensions/permission-registry";
-import { extensionToolRequiresApproval } from "@/extensions/tool-registry";
 import { runPermissionRequestHooks } from "@/hooks";
+import {
+  checkModPermissions,
+  getAvailableModPermissionsRegistry,
+  type ModPermissionDefinition,
+} from "@/mods/permission-registry";
+import { modToolRequiresApproval } from "@/mods/tool-registry";
 import type { PermissionModeState } from "@/tools/manager";
 import { canonicalToolName, isShellToolName } from "./canonical";
 import { cliPermissions } from "./cli-permissions-instance";
@@ -97,7 +97,7 @@ const FILE_TOOLS_V1 = [
 
 type ToolArgs = Record<string, unknown>;
 
-interface ExtensionPermissionCheckOptions {
+interface ModPermissionCheckOptions {
   conversationId?: string | null;
   phase?: "approval" | "execution";
   toolCallId?: string | null;
@@ -744,9 +744,9 @@ function getDefaultDecision(
   toolName: string,
   toolArgs?: ToolArgs,
 ): PermissionDecision {
-  const extensionRequiresApproval = extensionToolRequiresApproval(toolName);
-  if (extensionRequiresApproval !== undefined) {
-    return extensionRequiresApproval ? "ask" : "allow";
+  const modRequiresApproval = modToolRequiresApproval(toolName);
+  if (modRequiresApproval !== undefined) {
+    return modRequiresApproval ? "ask" : "allow";
   }
 
   // Check TOOL_PERMISSIONS to determine if tool requires approval
@@ -829,11 +829,11 @@ export async function checkPermissionWithHooks(
   workingDirectory: string = process.cwd(),
   modeState?: PermissionModeState,
   agentId?: string,
-  extensionPermissions: Map<
+  modPermissions: Map<
     string,
-    ExtensionPermissionDefinition
-  > = getAvailableExtensionPermissionsRegistry(),
-  extensionPermissionOptions: ExtensionPermissionCheckOptions = {},
+    ModPermissionDefinition
+  > = getAvailableModPermissionsRegistry(),
+  modPermissionOptions: ModPermissionCheckOptions = {},
 ): Promise<PermissionCheckResult> {
   // First, check permission using normal rules
   let result = checkPermission(
@@ -846,27 +846,25 @@ export async function checkPermissionWithHooks(
   );
 
   if (result.decision !== "deny") {
-    const extensionDecision = await checkExtensionPermissions(
+    const modDecision = await checkModPermissions(
       {
         agentId: agentId ?? null,
-        conversationId: extensionPermissionOptions.conversationId ?? null,
-        toolCallId: extensionPermissionOptions.toolCallId ?? null,
+        conversationId: modPermissionOptions.conversationId ?? null,
+        toolCallId: modPermissionOptions.toolCallId ?? null,
         toolName,
         args: toolArgs,
         cwd: workingDirectory,
         workingDirectory,
         permissionMode: modeState?.mode ?? permissionMode.getMode(),
-        phase: extensionPermissionOptions.phase ?? "approval",
+        phase: modPermissionOptions.phase ?? "approval",
       },
-      extensionPermissions,
+      modPermissions,
     );
-    if (extensionDecision) {
+    if (modDecision) {
       result = {
-        decision: extensionDecision.decision,
-        matchedRule: extensionDecision.matchedRule,
-        reason:
-          extensionDecision.reason ??
-          `Matched ${extensionDecision.matchedRule}`,
+        decision: modDecision.decision,
+        matchedRule: modDecision.matchedRule,
+        reason: modDecision.reason ?? `Matched ${modDecision.matchedRule}`,
       };
     }
   }
diff --git a/src/providers/byok-providers.ts b/src/providers/byok-providers.ts
--- a/src/providers/byok-providers.ts
+++ b/src/providers/byok-providers.ts
@@ -17,7 +17,7 @@ import {
   updateProvider as updateProviderRequest,
 } from "@/backend/api/providers";
 import { getBackend } from "@/backend/backend";
-import { listRegisteredPiProviders } from "@/backend/dev/pi-provider-extension-registry";
+import { listRegisteredPiProviders } from "@/backend/dev/pi-provider-mod-registry";
 import {
   getPiProviderSpec,
   LMSTUDIO_OPENAI_PROVIDER_TYPE,
@@ -363,16 +363,14 @@ function localApiKeyProviderIds(): string[] {
   );
 }
 
-function defaultExtensionProviderFields(providerName: string): ProviderField[] {
+function defaultModProviderFields(providerName: string): ProviderField[] {
   return [
     { key: "apiKey", label: `${providerName} API Key`, secret: true },
     { key: "baseUrl", label: "Base URL" },
   ];
 }
 
-function extensionProviderEnvApiKey(
-  apiKey: string | undefined,
-): string | undefined {
+function modProviderEnvApiKey(apiKey: string | undefined): string | undefined {
   if (!apiKey) return undefined;
   const value = process.env[apiKey];
   return value && value.length > 0 ? value : undefined;
@@ -386,7 +384,7 @@ function byokProviderFromRegisteredProvider(
     provider.config.connect && typeof provider.config.connect === "object"
       ? provider.config.connect
       : undefined;
-  const defaultApiKey = extensionProviderEnvApiKey(provider.config.apiKey);
+  const defaultApiKey = modProviderEnvApiKey(provider.config.apiKey);
   const displayName =
     provider.config.name ?? displayNameForLocalProvider(provider.providerName);
   const baseConfig: ByokProvider = {
@@ -409,7 +407,7 @@ function byokProviderFromRegisteredProvider(
     ...baseConfig,
     requiresApiKey: defaultApiKey === undefined,
     ...(defaultApiKey ? { defaultApiKey } : {}),
-    fields: connect?.fields ?? defaultExtensionProviderFields(displayName),
+    fields: connect?.fields ?? defaultModProviderFields(displayName),
   };
 }
 
diff --git a/src/skills/builtin/creating-extensions/SKILL.md b/src/skills/builtin/creating-mods/SKILL.md
rename from src/skills/builtin/creating-extensions/SKILL.md
rename to src/skills/builtin/creating-mods/SKILL.md
--- a/src/skills/builtin/creating-extensions/SKILL.md
+++ b/src/skills/builtin/creating-mods/SKILL.md
@@ -1,56 +1,56 @@
 ---
-name: creating-extensions
-description: Creates and edits trusted local Letta Code extensions, including tools, slash commands, local-only model providers, lifecycle/turn events, scoped conversation helpers, panels, status values, and capability-gated behavior. Use when asked to make an extension, add an agent-callable tool, add a slash command, add a local provider/model adapter, transform turns, react to app events, or add lightweight extension UI outside the dedicated /statusline flow.
+name: creating-mods
+description: Creates and edits trusted local Letta Code mods, including tools, slash commands, local-only model providers, lifecycle/turn events, scoped conversation helpers, panels, status values, and capability-gated behavior. Use when asked to make a mod, add an agent-callable tool, add a slash command, add a local provider/model adapter, transform turns, react to app events, or add lightweight mod UI outside the dedicated /statusline flow.
 ---
 
-# Creating Extensions
+# Creating Mods
 
-Use this skill to create or update trusted global Letta Code extensions in:
+Use this skill to create or update trusted global Letta Code mods in:
 
 ```text
-~/.letta/extensions/
+~/.letta/mods/
 ```
 
-Extensions are trusted local apps for Letta Code. They add small composable capabilities through extension APIs, not by importing app internals. Prefer scoped handles (`ctx.conversation`, `ctx.cwd`, `ctx.agent`, `letta.getContext()`) and guard optional UI with `letta.capabilities`.
+Mods are trusted local code for Letta Code. They add small composable capabilities through mod APIs, not by importing app internals. Prefer scoped handles (`ctx.conversation`, `ctx.cwd`, `ctx.agent`, `letta.getContext()`) and guard optional UI with `letta.capabilities`.
 
-Capabilities vary by surface. TUI/headless may load tools, commands, events, UI, and providers; the desktop listener loads provider-only extensions for local provider discovery. Always guard optional capabilities.
+Capabilities vary by surface. TUI/headless may load tools, commands, events, UI, and providers; the desktop listener loads provider-only mods for local provider discovery. Always guard optional capabilities.
 
 ## Choose the right capability
 
 | User wants | Build |
 | --- | --- |
-| Agent/model should autonomously call a local capability | Extension tool |
-| User wants `/foo` to send a prompt or run local UI logic | Extension command |
-| Slash command represents a reusable agent workflow | Skill + thin extension command |
+| Agent/model should autonomously call a local capability | Mod tool |
+| User wants `/foo` to send a prompt or run local UI logic | Mod command |
+| Slash command represents a reusable agent workflow | Skill + thin mod command |
 | Command should work while the main agent is busy | Command with `runWhenBusy: true`, `handled`, panel/status, and usually `ctx.conversation.fork()` |
 | Show transient output above input | Panel, usually from a command |
 | Show small persistent state | Status value |
 | React to app/session lifecycle or transform outbound turns | Event |
 | Enforce dynamic allow/ask/deny policy for tool calls | Permission overlay |
-| Add a custom model/API provider for local agents | Provider extension (local agents only) |
+| Add a custom model/API provider for local agents | Provider mod (local agents only) |
 | Change the bottom statusline appearance | Use `customizing-statusline`, not this skill |
 
 Default to a **tool** when the model should decide when to use the capability. Default to a **command** when the human explicitly invokes it. Compose capabilities when the UX needs it, e.g. command + panel + scoped conversation fork.
 
 ## Workflow
 
-1. Inspect `~/.letta/extensions/` for related files.
-2. Preserve unrelated extension code. Prefer a focused new file if merging would be messy.
-3. Choose the extension shape and load only the needed recipe:
+1. Inspect `~/.letta/mods/` for related files.
+2. Preserve unrelated mod code. Prefer a focused new file if merging would be messy.
+3. Choose the mod shape and load only the needed recipe:
    - tools: `references/tools.md`
    - commands: `references/commands.md`
    - local custom providers: `references/providers.md`
    - events: `references/events.md`
    - permissions: `references/permissions.md`
    - panels/status/capabilities: `references/ui.md`
    - complex plan-mode composition: `references/plan-mode.md`
-4. For multi-capability or stateful extensions, also read `references/architecture.md`.
-5. Write a single-file extension unless the user asks for something larger.
+4. For multi-capability or stateful mods, also read `references/architecture.md`.
+5. Write a single-file mod unless the user asks for something larger.
 6. Return disposers for registered providers/commands/tools/events, timers, subscriptions, and panels that should close on reload.
 7. Do a basic review: valid names, descriptions present, schemas are object schemas, optional capabilities guarded, scoped APIs used, cleanup returned.
-8. Tell the user the absolute file path changed and to run `/reload`. If an extension breaks startup or command handling, recover with `letta --no-extensions` or `LETTA_DISABLE_EXTENSIONS=1 letta`.
+8. Tell the user the absolute file path changed and to run `/reload`. If a mod breaks startup or command handling, recover with `letta --no-mods` or `LETTA_DISABLE_MODS=1 letta`.
 
-## Core extension shape
+## Core mod shape
 
 ```ts
 export default function activate(letta) {
@@ -93,42 +93,42 @@ letta.capabilities.ui.customStatuslineRenderer
   - `forked.sendMessageStream([...])` to stream from a fork
 - In tools, use `ctx.conversation.getHistory()` when the tool needs recent context.
 - Use `letta.client` only for server-specific Letta API calls; do not use it as a substitute for scoped conversation helpers.
-- Do not import `@/backend`, `@/cli`, or other Letta Code internals from extension files.
+- Do not import `@/backend`, `@/cli`, or other Letta Code internals from mod files.
 
 ## Diagnostics
 
-Use `letta.diagnostics.report({ message, severity })` sparingly as a debug utility for extension setup/runtime problems an agent should inspect, such as missing required environment variables or failed local configuration. Default severity is `"error"`; use `severity: "warning"` only for optional/degraded behavior. Keep messages short and actionable, and do not dump routine logs or large state.
+Use `letta.diagnostics.report({ message, severity })` sparingly as a debug utility for mod setup/runtime problems an agent should inspect, such as missing required environment variables or failed local configuration. Default severity is `"error"`; use `severity: "warning"` only for optional/degraded behavior. Keep messages short and actionable, and do not dump routine logs or large state.
 
-Agents can inspect local extension diagnostics at:
+Agents can inspect local mod diagnostics at:
 
 ```text
-~/.letta/extensions/diagnostics/latest.json
+~/.letta/mods/diagnostics/latest.json
 ```
 
 ## Rules
 
-- Global trusted code only for now. Do not create project extensions.
-- Custom provider extensions are local-backend/local-agent only. They do not add providers for Constellation/cloud agents.
-- Provider extensions may run in a provider-only listener context; keep provider registration independent from commands/tools/UI and guard everything else.
+- Global trusted code only for now. Do not create project mods.
+- Custom provider mods are local-backend/local-agent only. They do not add providers for Constellation/cloud agents.
+- Provider mods may run in a provider-only listener context; keep provider registration independent from commands/tools/UI and guard everything else.
 - Do not assume extra npm packages are available.
-- Do not do surprising side effects on startup; extensions activate on app start and `/reload`.
+- Do not do surprising side effects on startup; mods activate on app start and `/reload`.
 - Keep user-facing output short and intentional.
 - Prefer Node/Bun standard APIs (`node:child_process`, `node:fs`, etc.) for local work.
 - For shell execution, prefer `execFile`/`spawn` over shell strings.
 - Do not use emojis for loading states; use text or spinner-like characters if the user asks for loading UI.
 - For `runWhenBusy: true`, do not return `prompt`; return `handled` and own the UI/background work.
 - Treat `turn_start` as powerful trusted code: keep transforms narrow and unsurprising.
 
-## Pre-flight checklist for complex extensions
+## Pre-flight checklist for complex mods
 
 Before finishing, verify:
 
-- The extension has one clear owner/file and does not mix unrelated features.
+- The mod has one clear owner/file and does not mix unrelated features.
 - Command/tool IDs are valid; command overrides of built-ins are intentional, and tool IDs do not collide with built-ins.
 - Tool descriptions explain when the model should call them.
 - JSON schemas are object schemas with useful descriptions.
 - Optional UI/event/statusline APIs are capability-guarded.
-- Provider extensions are capability-guarded and clearly documented as local-agent only.
+- Provider mods are capability-guarded and clearly documented as local-agent only.
 - Timers, intervals, event registrations, and panels are cleaned up in a disposer.
 - Busy commands return `{ type: "handled" }` quickly and avoid main-conversation sends.
 - Conversation work uses `ctx.conversation` or forked handles, not app internals.
diff --git a/src/skills/builtin/creating-extensions/references/architecture.md b/src/skills/builtin/creating-mods/references/architecture.md
rename from src/skills/builtin/creating-extensions/references/architecture.md
rename to src/skills/builtin/creating-mods/references/architecture.md
--- a/src/skills/builtin/creating-extensions/references/architecture.md
+++ b/src/skills/builtin/creating-mods/references/architecture.md
@@ -1,6 +1,6 @@
-# Extension architecture patterns
+# Mod architecture patterns
 
-Use this reference for non-trivial extensions: multiple capabilities, local state, timers, background model work, or UI.
+Use this reference for non-trivial mods: multiple capabilities, local state, timers, background model work, or UI.
 
 ## Contents
 
@@ -14,14 +14,14 @@ Use this reference for non-trivial extensions: multiple capabilities, local stat
 
 ## Mental model
 
-An extension is trusted local code that registers capabilities during activation and cleans them up on reload/shutdown. Keep the public surface small:
+A mod is trusted local code that registers capabilities during activation and cleans them up on reload/shutdown. Keep the public surface small:
 
 - activation registers commands/tools/events/UI
 - command/tool/event handlers receive scoped context
 - state is local and explicit
 - cleanup is returned from activation
 
-Do not import Letta Code internals. If the extension API does not expose a capability yet, avoid reaching around it.
+Do not import Letta Code internals. If the mod API does not expose a capability yet, avoid reaching around it.
 
 Capabilities vary by host surface. Keep each registration behind the matching `letta.capabilities` guard so one file can run in TUI, headless, and provider-only listener contexts.
 
@@ -92,14 +92,14 @@ if (letta.capabilities.events.lifecycle && letta.capabilities.ui.statusValues) {
 
 ### `turn_start` transform
 
-Use `turn_start` only when the extension needs to inspect or transform the outbound user-message turn. Keep transforms local and predictable. Prefer appending/prepending focused context or replacing explicit shortcuts over broad rewrites.
+Use `turn_start` only when the mod needs to inspect or transform the outbound user-message turn. Keep transforms local and predictable. Prefer appending/prepending focused context or replacing explicit shortcuts over broad rewrites.
 
 ## Local state
 
-For small persistent state, use a clearly named file under `~/.letta/extensions/`, for example:
+For small persistent state, use a clearly named file under `~/.letta/mods/`, for example:
 
 ```text
-~/.letta/extensions/my-extension.state.json
+~/.letta/mods/my-mod.state.json
 ```
 
 Use atomic-ish writes when practical: write the full JSON file from an in-memory object after each change. Validate parsed state and fall back gracefully if the file is missing or malformed.
@@ -108,7 +108,7 @@ Keep state separate from source code. Do not store secrets in plain JSON; use ex
 
 ## Timers and subscriptions
 
-Timers are okay for active-session behavior, but they only run while the extension engine is alive. Always clear them:
+Timers are okay for active-session behavior, but they only run while the mod engine is alive. Always clear them:
 
 ```ts
 const timer = setInterval(update, 30_000);
@@ -147,4 +147,4 @@ Tools currently receive `ctx.conversation.getHistory()` but not fork/send helper
 - `runWhenBusy: true` commands return `handled`, not `prompt`.
 - Background model work uses a forked conversation.
 - Local filesystem and shell work uses scoped paths and `execFile`/`spawn`.
-- Extension output is concise and actionable.
+- Mod output is concise and actionable.
diff --git a/src/skills/builtin/creating-extensions/references/commands.md b/src/skills/builtin/creating-mods/references/commands.md
rename from src/skills/builtin/creating-extensions/references/commands.md
rename to src/skills/builtin/creating-mods/references/commands.md
--- a/src/skills/builtin/creating-extensions/references/commands.md
+++ b/src/skills/builtin/creating-mods/references/commands.md
@@ -1,8 +1,8 @@
-# Extension command recipes
+# Mod command recipes
 
 Use commands when the human explicitly invokes `/foo`.
 
-For complex command-driven extensions with panels, timers, local state, or background model work, also read `architecture.md`.
+For complex command-driven mods with panels, timers, local state, or background model work, also read `architecture.md`.
 
 ## Contents
 
@@ -17,10 +17,10 @@ For complex command-driven extensions with panels, timers, local state, or backg
 
 | Need | Use |
 | --- | --- |
-| `/foo` expands to a prompt | Extension command |
-| `/foo` starts a complex reusable workflow | Skill + thin extension command |
-| Model should call the capability by itself | Extension tool |
-| Command needs transient UI while doing local work | Extension command + panel |
+| `/foo` expands to a prompt | Mod command |
+| `/foo` starts a complex reusable workflow | Skill + thin mod command |
+| Model should call the capability by itself | Mod tool |
+| Command needs transient UI while doing local work | Mod command + panel |
 | Command needs model output while the main agent is busy | `runWhenBusy: true` command + forked `ctx.conversation` |
 
 If the command represents a durable agent workflow (for example `/goal`), put the workflow instructions in a skill and keep the command as a small launcher/prompt.
@@ -29,8 +29,8 @@ If the command represents a durable agent workflow (for example `/goal`), put th
 
 - Do not include the leading slash. Use `id: "review"`, not `id: "/review"`.
 - Use a lowercase slug with letters, numbers, and hyphens only.
-- Built-in commands like `/reload`, `/model`, `/statusline`, etc. can be overridden by trusted local extensions. Do this intentionally and keep recovery in mind: start with `--no-extensions` or `LETTA_DISABLE_EXTENSIONS=1` if an override breaks command handling.
-- Duplicate extension command IDs fail unless `override: true` is intentional.
+- Built-in commands like `/reload`, `/model`, `/statusline`, etc. can be overridden by trusted local mods. Do this intentionally and keep recovery in mind: start with `--no-mods` or `LETTA_DISABLE_MODS=1` if an override breaks command handling.
+- Duplicate mod command IDs fail unless `override: true` is intentional.
 
 ## Prompt command
 
@@ -68,7 +68,7 @@ export default function activate(letta) {
 
   return letta.commands.register({
     id: "whereami",
-    description: "Show the active extension command context",
+    description: "Show the active mod command context",
     run(ctx) {
       return {
         type: "output",
@@ -125,4 +125,4 @@ const stream = await forked.sendMessageStream([
 
 Do not send directly to the active conversation from a busy command; fork first unless the user explicitly asked to affect the main conversation later.
 
-For a worked multi-capability extension that combines commands, tools, events, permissions, and local state, see `plan-mode.md`.
+For a worked multi-capability mod that combines commands, tools, events, permissions, and local state, see `plan-mode.md`.
diff --git a/src/skills/builtin/creating-extensions/references/events.md b/src/skills/builtin/creating-mods/references/events.md
rename from src/skills/builtin/creating-extensions/references/events.md
rename to src/skills/builtin/creating-mods/references/events.md
--- a/src/skills/builtin/creating-extensions/references/events.md
+++ b/src/skills/builtin/creating-mods/references/events.md
@@ -1,6 +1,6 @@
-# Extension event recipes
+# Mod event recipes
 
-Use events when trusted local code should react to app/session changes or transform outbound turns without the human explicitly invoking a command. For event-driven extensions with state, timers, panels, or background model work, also read `architecture.md`.
+Use events when trusted local code should react to app/session changes or transform outbound turns without the human explicitly invoking a command. For event-driven mods with state, timers, panels, or background model work, also read `architecture.md`.
 
 ## Contents
 
@@ -12,7 +12,7 @@ Use events when trusted local code should react to app/session changes or transf
 - Conversation status example
 - Rules
 
-This is the first slice of the hooks-v2 direction. The long-term goal is for typed extension events to replace settings-based hooks. Existing hooks still own blocking decisions and model feedback injection until each event has a typed return contract.
+This is the first slice of the hooks-v2 direction. The long-term goal is for typed mod events to replace settings-based hooks. Existing hooks still own blocking decisions and model feedback injection until each event has a typed return contract.
 
 ## Capabilities
 
@@ -22,7 +22,7 @@ letta.capabilities.events.tools
 letta.capabilities.events.turns
 ```
 
-Guard events when writing portable extensions:
+Guard events when writing portable mods:
 
 ```ts
 export default function activate(letta) {
@@ -115,7 +115,7 @@ Lifecycle handlers are notification-only and should not return values. `turn_sta
 }
 ```
 
-`tool_start` fires immediately before a client-side tool executes. This includes built-in tools, extension tools, and external tools executed through the local tool manager. It runs after permission/approval classification and before `PreToolUse` hooks, so trusted local extensions can change the actual executed arguments after the approval UI has already classified the original request. Extension permission overlays are rechecked after `tool_start` on the final args.
+`tool_start` fires immediately before a client-side tool executes. This includes built-in tools, mod tools, and external tools executed through the local tool manager. It runs after permission/approval classification and before `PreToolUse` hooks, so trusted local mods can change the actual executed arguments after the approval UI has already classified the original request. Mod permission overlays are rechecked after `tool_start` on the final args.
 
 Handlers can inspect `event.args`, mutate it directly, or return replacement args:
 
@@ -134,9 +134,9 @@ letta.events.on("tool_start", (event) => {
 });
 ```
 
-Handlers run in registration order. Later handlers see the current args after earlier mutations/returns. If a handler throws, its partial `event.args` mutation is rolled back and the error is recorded as an extension diagnostic.
+Handlers run in registration order. Later handlers see the current args after earlier mutations/returns. If a handler throws, its partial `event.args` mutation is rolled back and the error is recorded as a mod diagnostic.
 
-`tool_start` is intentionally a trusted local extension point: it can rewrite commands, file paths, and other tool inputs before execution. Keep transforms focused and unsurprising.
+`tool_start` is intentionally a trusted local mod point: it can rewrite commands, file paths, and other tool inputs before execution. Keep transforms focused and unsurprising.
 
 `turn_start` fires before outbound turns that include a user message. In the TUI this includes normal submits and prompt-style command turns. In headless it includes one-shot prompts and bidirectional user turns.
 
@@ -166,9 +166,9 @@ letta.events.on("turn_start", (event) => {
 });
 ```
 
-Handlers run in registration order. Later handlers see the current input after earlier mutations/returns. If a handler throws, its partial `event.input` mutation is rolled back and the error is recorded as an extension diagnostic.
+Handlers run in registration order. Later handlers see the current input after earlier mutations/returns. If a handler throws, its partial `event.input` mutation is rolled back and the error is recorded as a mod diagnostic.
 
-`turn_start` is intentionally a trusted local extension point: it can rewrite user messages, approval results, and ordering. Keep transforms focused and unsurprising.
+`turn_start` is intentionally a trusted local mod point: it can rewrite user messages, approval results, and ordering. Keep transforms focused and unsurprising.
 
 Handlers also receive:
 
@@ -221,5 +221,5 @@ export default function activate(letta) {
 
 - Do not block user flow unless the event's typed contract explicitly supports blocking.
 - Do not use lifecycle events for safety decisions yet. Existing hooks still own blocking behavior.
-- Catch expected local errors if the user-facing outcome matters. Uncaught errors are isolated and recorded as extension diagnostics.
+- Catch expected local errors if the user-facing outcome matters. Uncaught errors are isolated and recorded as mod diagnostics.
 - Return disposers from activation for event registrations, timers, subscriptions, and status values.
diff --git a/src/skills/builtin/creating-extensions/references/permissions.md b/src/skills/builtin/creating-mods/references/permissions.md
rename from src/skills/builtin/creating-extensions/references/permissions.md
rename to src/skills/builtin/creating-mods/references/permissions.md
--- a/src/skills/builtin/creating-extensions/references/permissions.md
+++ b/src/skills/builtin/creating-mods/references/permissions.md
@@ -1,4 +1,4 @@
-# Extension permission recipes
+# Mod permission recipes
 
 Use permission overlays when trusted local code should participate in tool approval decisions. Prefer permissions over `tool_start` denial for policy: permissions run before approval UI and again before execution on final tool arguments.
 
@@ -8,7 +8,7 @@ Use permission overlays when trusted local code should participate in tool appro
 letta.capabilities.permissions
 ```
 
-Guard registrations when writing portable extensions:
+Guard registrations when writing portable mods:
 
 ```ts
 export default function activate(letta) {
@@ -71,7 +71,7 @@ Composition rules across overlays:
 - then `allow`
 - `undefined` means no opinion
 
-User/configured hard denials still win before extension overlays. Extension overlays can override normal auto-allow/default approval behavior, including unrestricted/yolo mode.
+User/configured hard denials still win before mod overlays. Mod overlays can override normal auto-allow/default approval behavior, including unrestricted/yolo mode.
 
 ## Two phases
 
diff --git a/src/skills/builtin/creating-extensions/references/plan-mode.md b/src/skills/builtin/creating-mods/references/plan-mode.md
rename from src/skills/builtin/creating-extensions/references/plan-mode.md
rename to src/skills/builtin/creating-mods/references/plan-mode.md
--- a/src/skills/builtin/creating-extensions/references/plan-mode.md
+++ b/src/skills/builtin/creating-mods/references/plan-mode.md
@@ -1,8 +1,8 @@
-# Plan mode extension example
+# Plan mode mod example
 
-Use this as the canonical multi-capability extension example. It composes a slash command, model-callable tools, turn reminders, permission overlays, and local state to recreate the old built-in plan-mode flow with extension APIs.
+Use this as the canonical multi-capability mod example. It composes a slash command, model-callable tools, turn reminders, permission overlays, and local state to recreate the old built-in plan-mode flow with mod APIs.
 
-This is a pattern reference, not a full product implementation. Keep local extensions self-contained and avoid importing Letta Code internals.
+This is a pattern reference, not a full product implementation. Keep local mods self-contained and avoid importing Letta Code internals.
 
 ## Contents
 
@@ -46,15 +46,15 @@ Do not use panels for persistent mode state. Panels are transient UI and can be
 
 ## State
 
-Use small local state under `~/.letta/extensions/`, keyed by conversation ID:
+Use small local state under `~/.letta/mods/`, keyed by conversation ID:
 
 ```ts
 import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
 import { homedir } from "node:os";
 import { join, relative } from "node:path";
 
 const PLANS_DIR = join(homedir(), ".letta", "plans");
-const STATE_PATH = join(homedir(), ".letta", "extensions", "plan-mode.state.json");
+const STATE_PATH = join(homedir(), ".letta", "mods", "plan-mode.state.json");
 const GLOBAL_CONVERSATION_ID = "__global__";
 
 type PlanSession = {
@@ -81,7 +81,7 @@ function readState(): PlanState {
 }
 
 function writeState(state: PlanState): void {
-  mkdirSync(join(homedir(), ".letta", "extensions"), { recursive: true });
+  mkdirSync(join(homedir(), ".letta", "mods"), { recursive: true });
   writeFileSync(STATE_PATH, JSON.stringify(state, null, 2));
 }
 ```
@@ -279,7 +279,7 @@ Shell allowlists are easy to get wrong. Start conservative: allow clearly read-o
 
 ## Exit tool
 
-In the extension version, `exit_plan_mode` is not the approval UI. The agent should read the plan file, present the full current plan text with `AskUserQuestion`, then call `exit_plan_mode` only after the user approves.
+In the mod version, `exit_plan_mode` is not the approval UI. The agent should read the plan file, present the full current plan text with `AskUserQuestion`, then call `exit_plan_mode` only after the user approves.
 
 ```ts
 if (letta.capabilities.tools) {
diff --git a/src/skills/builtin/creating-extensions/references/providers.md b/src/skills/builtin/creating-mods/references/providers.md
rename from src/skills/builtin/creating-extensions/references/providers.md
rename to src/skills/builtin/creating-mods/references/providers.md
--- a/src/skills/builtin/creating-extensions/references/providers.md
+++ b/src/skills/builtin/creating-mods/references/providers.md
@@ -1,15 +1,15 @@
-# Extension provider recipes
+# Mod provider recipes
 
-Use provider extensions when the user wants a **local agent** to use a model provider that is not built into `/connect` and `/model`.
+Use provider mods when the user wants a **local agent** to use a model provider that is not built into `/connect` and `/model`.
 
-Important: provider extensions are local-backend/local-agent only. They register local provider metadata for the TUI, headless local runtime, and desktop listener. They do not add providers for Constellation/cloud agents.
+Important: provider mods are local-backend/local-agent only. They register local provider metadata for the TUI, headless local runtime, and desktop listener. They do not add providers for Constellation/cloud agents.
 
-For multi-capability extensions that combine a provider with commands, tools, UI, or state, also read `architecture.md`.
+For multi-capability mods that combine a provider with commands, tools, UI, or state, also read `architecture.md`.
 
 ## Quick pattern
 
 ```ts
-// ~/.letta/extensions/kilo.ts
+// ~/.letta/mods/kilo.ts
 export default function activate(letta) {
   if (!letta.capabilities.providers) return;
 
@@ -48,10 +48,10 @@ After `/reload`, the provider appears in local `/connect` and desktop Connect mo
 
 - Always guard with `letta.capabilities.providers`.
 - Prefer `letta.providers.register(...)` over legacy `letta.registerProvider(...)`.
-- Keep provider registration independent from commands/tools/UI/events and `letta.client`; the desktop listener loads provider-only extensions.
+- Keep provider registration independent from commands/tools/UI/events and `letta.client`; the desktop listener loads provider-only mods.
 - Do not hardcode real secrets. `apiKey: "ENV_VAR"` resolves `process.env.ENV_VAR` when present, or lets `/connect` save a local key.
 - Use stable lowercase provider ids. Model ids must be unprefixed and must not contain `/`.
-- Set `api` at provider or model level. Common values include `"openai-completions"`, `"openai-responses"`, `"anthropic-messages"`, and `"bedrock-converse-stream"`; check `src/backend/dev/pi-provider-extension-types.ts` and pi-ai model types before using uncommon values.
+- Set `api` at provider or model level. Common values include `"openai-completions"`, `"openai-responses"`, `"anthropic-messages"`, and `"bedrock-converse-stream"`; check `src/backend/dev/pi-provider-mod-types.ts` and pi-ai model types before using uncommon values.
 
 ## Model metadata
 
diff --git a/src/skills/builtin/creating-extensions/references/tools.md b/src/skills/builtin/creating-mods/references/tools.md
rename from src/skills/builtin/creating-extensions/references/tools.md
rename to src/skills/builtin/creating-mods/references/tools.md
--- a/src/skills/builtin/creating-extensions/references/tools.md
+++ b/src/skills/builtin/creating-mods/references/tools.md
@@ -1,8 +1,8 @@
-# Extension tool recipes
+# Mod tool recipes
 
 Use tools when the agent/model should call a local capability autonomously.
 
-For tools that are part of a larger extension with commands, UI, local state, or events, also read `architecture.md`.
+For tools that are part of a larger mod with commands, UI, local state, or events, also read `architecture.md`.
 
 ## Contents
 
diff --git a/src/skills/builtin/creating-extensions/references/ui.md b/src/skills/builtin/creating-mods/references/ui.md
rename from src/skills/builtin/creating-extensions/references/ui.md
rename to src/skills/builtin/creating-mods/references/ui.md
--- a/src/skills/builtin/creating-extensions/references/ui.md
+++ b/src/skills/builtin/creating-mods/references/ui.md
@@ -1,8 +1,8 @@
-# Extension UI recipes
+# Mod UI recipes
 
-UI capabilities are optional. Always guard UI work with `letta.capabilities.ui.*` when writing portable extensions.
+UI capabilities are optional. Always guard UI work with `letta.capabilities.ui.*` when writing portable mods.
 
-For UI that belongs to a larger command/event extension, also read `architecture.md` for cleanup and composition patterns.
+For UI that belongs to a larger command/event mod, also read `architecture.md` for cleanup and composition patterns.
 
 ## Capabilities
 
@@ -21,7 +21,7 @@ letta.capabilities.ui.customStatuslineRenderer
 ```ts
 if (letta.capabilities.ui.panels) {
   const panel = letta.ui.openPanel({
-    id: "my-extension",
+    id: "my-mod",
     content: ["Working…"],
     order: 100,
   });
diff --git a/src/skills/builtin/customizing-commands/SKILL.md b/src/skills/builtin/customizing-commands/SKILL.md
--- a/src/skills/builtin/customizing-commands/SKILL.md
+++ b/src/skills/builtin/customizing-commands/SKILL.md
@@ -1,36 +1,36 @@
 ---
 name: customizing-commands
-description: Creates, edits, and enables Letta Code extension-provided slash commands. Use when the user asks to add a custom /command, slash command, command shortcut, scoped conversation-backed command, or command-driven panel behavior.
+description: Creates, edits, and enables Letta Code mod-provided slash commands. Use when the user asks to add a custom /command, slash command, command shortcut, scoped conversation-backed command, or command-driven panel behavior.
 ---
 
 # Customizing Commands
 
-Use this as the command-specific entrypoint for local extension slash commands. For broader extension work, recipes live in `../creating-extensions/references/commands.md`, `../creating-extensions/references/architecture.md`, `../creating-extensions/references/ui.md`, and `../creating-extensions/references/plan-mode.md`.
+Use this as the command-specific entrypoint for local mod slash commands. For broader mod work, recipes live in `../creating-mods/references/commands.md`, `../creating-mods/references/architecture.md`, `../creating-mods/references/ui.md`, and `../creating-mods/references/plan-mode.md`.
 
-Extension files live in:
+Mod files live in:
 
 ```text
-~/.letta/extensions/
+~/.letta/mods/
 ```
 
-Use a focused file name, e.g. `~/.letta/extensions/review.ts` or `~/.letta/extensions/commands.ts`.
+Use a focused file name, e.g. `~/.letta/mods/review.ts` or `~/.letta/mods/commands.ts`.
 
 ## First decide whether a command is right
 
 | User wants | Build |
 | --- | --- |
-| `/foo` sends a prompt or shows local output | Extension command |
-| `/foo` starts a reusable agent workflow | Skill + thin extension command |
-| Agent/model should autonomously call the capability | Extension tool, not a command |
-| Command shows transient progress/results | Extension command + panel |
+| `/foo` sends a prompt or shows local output | Mod command |
+| `/foo` starts a reusable agent workflow | Skill + thin mod command |
+| Agent/model should autonomously call the capability | Mod tool, not a command |
+| Command shows transient progress/results | Mod command + panel |
 | Command needs model output while the main agent is busy | `runWhenBusy: true` command + forked `ctx.conversation` |
 
-If the command is a durable workflow like `/goal`, put the workflow instructions in a skill and keep the extension command as a small launcher/prompt.
+If the command is a durable workflow like `/goal`, put the workflow instructions in a skill and keep the mod command as a small launcher/prompt.
 
 ## Workflow
 
-1. Inspect `~/.letta/extensions/` for related command files.
-2. Preserve unrelated extension code; create a focused new file if merging is messy.
+1. Inspect `~/.letta/mods/` for related command files.
+2. Preserve unrelated mod code; create a focused new file if merging is messy.
 3. Register with `letta.commands.register()` and guard with `letta.capabilities.commands`.
 4. Return the unregister function, or a disposer that calls it plus any timer/panel cleanup.
 5. Tell the user the exact file path changed and to run `/reload`.
@@ -62,7 +62,7 @@ export default function activate(letta) {
 ## Command result types
 
 ```ts
-type ExtensionCommandResult =
+type ModCommandResult =
   | { type: "prompt"; content: string; systemReminder?: boolean }
   | { type: "output"; output: string; success?: boolean }
   | { type: "handled" };
@@ -80,11 +80,11 @@ type ExtensionCommandResult =
 - `runWhenBusy: true` commands must not return `prompt` while the main agent is busy; use scoped conversation helpers/panels and return `handled`.
 - `showInTranscript: false` commands should usually return `handled`, not `prompt`.
 - Do not import Letta Code app internals.
-- Do not do surprising side effects on startup; extensions activate on app start and `/reload`.
+- Do not do surprising side effects on startup; mods activate on app start and `/reload`.
 
 ## More recipes
 
-- Simple output command, panel command, busy-safe conversation command: `../creating-extensions/references/commands.md`
-- Complex command architecture, state, cleanup: `../creating-extensions/references/architecture.md`
-- Panel/status UI patterns: `../creating-extensions/references/ui.md`
-- Worked plan-mode command/tool composition: `../creating-extensions/references/plan-mode.md`
+- Simple output command, panel command, busy-safe conversation command: `../creating-mods/references/commands.md`
+- Complex command architecture, state, cleanup: `../creating-mods/references/architecture.md`
+- Panel/status UI patterns: `../creating-mods/references/ui.md`
+- Worked plan-mode command/tool composition: `../creating-mods/references/plan-mode.md`
diff --git a/src/skills/builtin/customizing-statusline/SKILL.md b/src/skills/builtin/customizing-statusline/SKILL.md
--- a/src/skills/builtin/customizing-statusline/SKILL.md
+++ b/src/skills/builtin/customizing-statusline/SKILL.md
@@ -1,14 +1,14 @@
 ---
 name: customizing-statusline
-description: Creates, edits, and migrates Letta Code statusline extensions. Use when handling the /statusline command or continuing work started by /statusline.
+description: Creates, edits, and migrates Letta Code statusline mods. Use when handling the /statusline command or continuing work started by /statusline.
 ---
 
 # Customizing Statusline
 
-Use this skill to create or update the global Letta Code statusline extension:
+Use this skill to create or update the global Letta Code statusline mod:
 
 ```text
-~/.letta/extensions/statusline.tsx
+~/.letta/mods/statusline.tsx
 ```
 
 The statusline is a full-row idle renderer. Host UI can still temporarily preempt it for safety confirmations and transient hints.
@@ -18,22 +18,22 @@ The statusline is a full-row idle renderer. Host UI can still temporarily preemp
 ```text
 safety preemption
 else transient host hint
-else custom statusline extension
+else custom statusline mod
 else built-in default statusline
 ```
 
 A custom statusline owns the whole idle row. Do not preserve legacy left/right split semantics in the new API.
 
 ## Workflow
 
-1. Check whether `~/.letta/extensions/statusline.tsx` exists.
+1. Check whether `~/.letta/mods/statusline.tsx` exists.
 2. If it exists, read it before editing and preserve unrelated code.
 3. If it does not exist, start from the built-in default template or synthesize a focused starter for the user's request.
 4. If the user asks to migrate, import a `.sh` file, or match a shell prompt, read `references/migration.md`.
 5. If API details or concrete patterns are needed, read `references/api.md` and `references/examples.md`.
-6. If the request combines statusline work with commands, tools, events, panels, or stateful extension behavior, also use `creating-extensions` and its `references/architecture.md`.
+6. If the request combines statusline work with commands, tools, events, panels, or stateful mod behavior, also use `creating-mods` and its `references/architecture.md`.
 7. Guard statusline-specific behavior with `letta.capabilities.ui.customStatuslineRenderer` when writing new files.
-8. Edit `~/.letta/extensions/statusline.tsx`.
+8. Edit `~/.letta/mods/statusline.tsx`.
 9. Summarize the absolute file path changed and tell the user to run `/reload` unless the command can reload automatically.
 
 ## Bare `/statusline` behavior
@@ -52,20 +52,20 @@ Keep this conversational. Do not build a menu UI unless the product command expl
 
 ## Rules
 
-- Global-only for now. Do not create project extensions.
-- Keep the extension single-file for MVP.
+- Global-only for now. Do not create project mods.
+- Keep the mod single-file for MVP.
 - Do not assume extra npm packages are available.
 - Do not use relative multi-file imports yet.
 - Keep renderers synchronous. Do not shell, fetch, or await inside render.
 - Do async work in setup code, intervals, subscriptions, or status providers.
 - Use `letta.ui.setStatus` for data and `setStatuslineRenderer` for drawing that data.
 - Guard optional APIs with `letta.capabilities.ui.statusValues` and `letta.capabilities.ui.customStatuslineRenderer` in new files.
 - Return a disposer that clears timers/subscriptions.
-- Preserve existing extension code unless the user asks to reset.
+- Preserve existing mod code unless the user asks to reset.
 - Do not delete legacy command statusline files or settings unless the user explicitly asks.
 
 ## Useful references
 
-- `references/api.md` - extension API, render context, lifecycle rules
+- `references/api.md` - mod API, render context, lifecycle rules
 - `references/examples.md` - common statusline patterns
 - `references/migration.md` - legacy command `.sh` and PS1 migration
diff --git a/src/skills/builtin/customizing-statusline/references/api.md b/src/skills/builtin/customizing-statusline/references/api.md
--- a/src/skills/builtin/customizing-statusline/references/api.md
+++ b/src/skills/builtin/customizing-statusline/references/api.md
@@ -1,14 +1,14 @@
-# Statusline Extension API
+# Statusline Mod API
 
-Use this reference when creating or editing `~/.letta/extensions/statusline.tsx`.
+Use this reference when creating or editing `~/.letta/mods/statusline.tsx`.
 
 ## Location
 
 ```text
-~/.letta/extensions/statusline.tsx
+~/.letta/mods/statusline.tsx
 ```
 
-This is a trusted, user-owned global extension file. Project extensions are intentionally unsupported for now.
+This is a trusted, user-owned global mod file. Project mods are intentionally unsupported for now.
 
 ## Activation
 
@@ -59,7 +59,7 @@ letta.ui.setStatuslineRenderer((context) => {
 
 ## Async state pattern
 
-Use Node/Bun APIs directly from the trusted extension file. Do not assume helper methods like `letta.shell` exist.
+Use Node/Bun APIs directly from the trusted mod file. Do not assume helper methods like `letta.shell` exist.
 
 ```tsx
 import { execFile } from "node:child_process";
@@ -117,7 +117,7 @@ Common fields:
 
 ```ts
 context.components      // Display components such as Text, Box, Spacer
-context.statuses        // evaluated extension status strings
+context.statuses        // evaluated mod status strings
 context.app.version
 context.workspace.cwd
 context.workspace.currentDir
@@ -159,10 +159,10 @@ return (
 
 ## Reload behavior
 
-After editing `~/.letta/extensions/statusline.tsx`, tell the user to run:
+After editing `~/.letta/mods/statusline.tsx`, tell the user to run:
 
 ```text
 /reload
 ```
 
-The runtime tracks extension loading separately from “no custom statusline,” so a custom statusline should not flash back to the built-in default during reload.
+The runtime tracks mod loading separately from “no custom statusline,” so a custom statusline should not flash back to the built-in default during reload.
diff --git a/src/skills/builtin/customizing-statusline/references/examples.md b/src/skills/builtin/customizing-statusline/references/examples.md
--- a/src/skills/builtin/customizing-statusline/references/examples.md
+++ b/src/skills/builtin/customizing-statusline/references/examples.md
@@ -1,6 +1,6 @@
 # Statusline Examples
 
-Use these as patterns, not mandatory templates. Keep the final extension focused on the user's request.
+Use these as patterns, not mandatory templates. Keep the final mod focused on the user's request.
 
 ## Agent and model
 
diff --git a/src/skills/builtin/customizing-statusline/references/migration.md b/src/skills/builtin/customizing-statusline/references/migration.md
--- a/src/skills/builtin/customizing-statusline/references/migration.md
+++ b/src/skills/builtin/customizing-statusline/references/migration.md
@@ -39,7 +39,7 @@ Look for either shape:
 When migrating:
 
 - Preserve old config and referenced files unless the user explicitly asks to delete them.
-- If `command` references a `.sh` file, read it before writing the new extension.
+- If `command` references a `.sh` file, read it before writing the new mod.
 - Translate polling (`refreshIntervalMs`) to `setInterval`.
 - Translate direct command output into cached status plus synchronous rendering.
 - If the command output used `\x1e` to split left/right output, convert it to internal full-row layout with `Box`; do not create a new left/right API.
diff --git a/src/tools/manager.ts b/src/tools/manager.ts
--- a/src/tools/manager.ts
+++ b/src/tools/manager.ts
@@ -19,31 +19,28 @@ import {
 import { getActiveChannelIds } from "@/channels/registry";
 import type { ChannelTurnSource } from "@/channels/types";
 import { INTERRUPTED_BY_USER } from "@/constants";
-import { createExtensionConversationHandle } from "@/extensions/conversation-handle";
-import {
-  type ExtensionEvents,
-  emitExtensionEvent,
-} from "@/extensions/event-emitter";
-import {
-  checkExtensionPermissions,
-  type ExtensionPermissionDecisionResult,
-  type ExtensionPermissionDefinition,
-  getAvailableExtensionPermissionsRegistry,
-} from "@/extensions/permission-registry";
-import {
-  type ExtensionToolDefinition,
-  extensionToolRequiresApproval,
-  getAvailableExtensionToolsRegistry,
-  getExtensionToolDefinition,
-  isExtensionToolParallelSafe,
-  runExtensionTool,
-} from "@/extensions/tool-registry";
-import type { ExtensionToolRunContext } from "@/extensions/types";
 import {
   runPostToolUseFailureHooks,
   runPostToolUseHooks,
   runPreToolUseHooks,
 } from "@/hooks";
+import { createModConversationHandle } from "@/mods/conversation-handle";
+import { emitModEvent, type ModEvents } from "@/mods/event-emitter";
+import {
+  checkModPermissions,
+  getAvailableModPermissionsRegistry,
+  type ModPermissionDecisionResult,
+  type ModPermissionDefinition,
+} from "@/mods/permission-registry";
+import {
+  getAvailableModToolsRegistry,
+  getModToolDefinition,
+  isModToolParallelSafe,
+  type ModToolDefinition,
+  modToolRequiresApproval,
+  runModTool,
+} from "@/mods/tool-registry";
+import type { ModToolRunContext } from "@/mods/types";
 import {
   permissionMode as globalPermissionMode,
   type PermissionMode,
@@ -339,17 +336,17 @@ function filterExternalToolsByClientAllowlist(
   );
 }
 
-function filterExtensionToolsByClientAllowlist(
-  extensionTools: Map<string, ExtensionToolDefinition>,
+function filterModToolsByClientAllowlist(
+  modTools: Map<string, ModToolDefinition>,
   clientToolAllowlist?: string[],
-): Map<string, ExtensionToolDefinition> {
+): Map<string, ModToolDefinition> {
   if (clientToolAllowlist === undefined) {
-    return new Map(extensionTools);
+    return new Map(modTools);
   }
 
   const allowSet = new Set(clientToolAllowlist);
   return new Map(
-    Array.from(extensionTools.entries()).filter(([name, tool]) =>
+    Array.from(modTools.entries()).filter(([name, tool]) =>
       matchesClientToolAllowlistEntry(allowSet, tool.name, name),
     ),
   );
@@ -594,9 +591,9 @@ type ToolExecutionContextSnapshot = {
   toolRegistry: ToolRegistry;
   externalTools: Map<string, ExternalToolDefinition>;
   externalExecutor?: ExternalToolExecutor;
-  extensionEvents?: ExtensionEvents;
-  extensionPermissions: Map<string, ExtensionPermissionDefinition>;
-  extensionTools: Map<string, ExtensionToolDefinition>;
+  modEvents?: ModEvents;
+  modPermissions: Map<string, ModPermissionDefinition>;
+  modTools: Map<string, ModToolDefinition>;
   workingDirectory: string;
   runtimeContext: RuntimeContextSnapshot;
   permissionModeState: PermissionModeState;
@@ -951,49 +948,47 @@ export async function executeExternalTool(
 /**
  * Get all loaded tools in the format expected by the Letta API's client_tools field.
  * Maps internal tool names to server-facing names for proper tool invocation.
- * Includes built-in, external, and extension tools.
+ * Includes built-in, external, and mod tools.
  */
 export function getClientToolsFromRegistry(): ClientTool[] {
   return buildClientToolsFromSnapshot(
     withDynamicMessageChannelCache(toolRegistry),
     getExternalToolsRegistry(),
-    getAvailableExtensionToolsRegistry(),
+    getAvailableModToolsRegistry(),
   );
 }
 
 function buildClientToolsFromSnapshot(
   registry: ToolRegistry,
   externalTools: Map<string, ExternalToolDefinition>,
-  extensionTools: Map<string, ExtensionToolDefinition>,
+  modTools: Map<string, ModToolDefinition>,
 ): ClientTool[] {
   const builtInTools = Array.from(registry.entries()).map(([name, tool]) =>
     serializeFunctionOnlyToolPayload(getServerToolName(name), tool.modelForm),
   );
   for (const name of externalTools.keys()) {
-    if (extensionTools.has(name)) {
+    if (modTools.has(name)) {
       debugLog(
         "tools",
-        "extension tool %s shadows external tool with same name",
+        "mod tool %s shadows external tool with same name",
         name,
       );
     }
   }
   const externalClientTools = Array.from(externalTools.values())
-    .filter((tool) => !extensionTools.has(tool.name))
+    .filter((tool) => !modTools.has(tool.name))
     .map((tool) => ({
       name: tool.name,
       description: tool.description,
       parameters: tool.parameters,
     }));
-  const extensionClientTools = Array.from(extensionTools.values()).map(
-    (tool) => ({
-      name: tool.name,
-      description: tool.description,
-      parameters: tool.parameters,
-    }),
-  );
+  const modClientTools = Array.from(modTools.values()).map((tool) => ({
+    name: tool.name,
+    description: tool.description,
+    parameters: tool.parameters,
+  }));
 
-  return [...builtInTools, ...externalClientTools, ...extensionClientTools];
+  return [...builtInTools, ...externalClientTools, ...modClientTools];
 }
 
 function getEffectivePermissionModeState(
@@ -1018,15 +1013,15 @@ function capturePreparedToolExecutionContext(
     toolRegistry: ToolRegistry;
     externalTools: Map<string, ExternalToolDefinition>;
     externalExecutor?: ExternalToolExecutor;
-    extensionEvents?: ExtensionEvents;
-    extensionPermissions: Map<string, ExtensionPermissionDefinition>;
-    extensionTools: Map<string, ExtensionToolDefinition>;
+    modEvents?: ModEvents;
+    modPermissions: Map<string, ModPermissionDefinition>;
+    modTools: Map<string, ModToolDefinition>;
   },
   options?: {
     clientToolAllowlist?: string[];
     workingDirectory?: string;
     permissionModeState?: PermissionModeState;
-    extensionEvents?: ExtensionEvents;
+    modEvents?: ModEvents;
     runtimeContext?: Partial<RuntimeContextSnapshot>;
     channelToolScope?: MessageChannelToolDiscoveryScope | null;
     channelTurnSources?: ChannelTurnSource[];
@@ -1046,10 +1041,10 @@ function capturePreparedToolExecutionContext(
       options?.clientToolAllowlist,
     ),
     externalExecutor: snapshot.externalExecutor,
-    extensionEvents: options?.extensionEvents ?? snapshot.extensionEvents,
-    extensionPermissions: snapshot.extensionPermissions,
-    extensionTools: filterExtensionToolsByClientAllowlist(
-      snapshot.extensionTools,
+    modEvents: options?.modEvents ?? snapshot.modEvents,
+    modPermissions: snapshot.modPermissions,
+    modTools: filterModToolsByClientAllowlist(
+      snapshot.modTools,
       options?.clientToolAllowlist,
     ),
     workingDirectory:
@@ -1067,7 +1062,7 @@ function capturePreparedToolExecutionContext(
     clientTools: buildClientToolsFromSnapshot(
       executionSnapshot.toolRegistry,
       executionSnapshot.externalTools,
-      executionSnapshot.extensionTools,
+      executionSnapshot.modTools,
     ),
     loadedToolNames: Array.from(executionSnapshot.toolRegistry.keys()),
   };
@@ -1087,8 +1082,8 @@ export function captureToolExecutionContext(
       toolRegistry: new Map(toolRegistry),
       externalTools: new Map(getExternalToolsRegistry()),
       externalExecutor: getExternalToolExecutor(),
-      extensionPermissions: getAvailableExtensionPermissionsRegistry(),
-      extensionTools: getAvailableExtensionToolsRegistry(),
+      modPermissions: getAvailableModPermissionsRegistry(),
+      modTools: getAvailableModToolsRegistry(),
     },
     {
       workingDirectory,
@@ -1103,7 +1098,7 @@ export async function prepareCurrentToolExecutionContext(options?: {
   runtimeContext?: Partial<RuntimeContextSnapshot>;
   channelToolScope?: MessageChannelToolDiscoveryScope | null;
   channelTurnSources?: ChannelTurnSource[];
-  extensionEvents?: ExtensionEvents;
+  modEvents?: ModEvents;
 }): Promise<PreparedToolExecutionContext> {
   await waitForToolsetReady();
   const currentToolNames = maybeAppendChannelTools(
@@ -1116,9 +1111,9 @@ export async function prepareCurrentToolExecutionContext(options?: {
       toolRegistry: toolRegistrySnapshot,
       externalTools: new Map(getExternalToolsRegistry()),
       externalExecutor: getExternalToolExecutor(),
-      extensionEvents: options?.extensionEvents,
-      extensionPermissions: getAvailableExtensionPermissionsRegistry(),
-      extensionTools: getAvailableExtensionToolsRegistry(),
+      modEvents: options?.modEvents,
+      modPermissions: getAvailableModPermissionsRegistry(),
+      modTools: getAvailableModToolsRegistry(),
     },
     options,
   );
@@ -1132,7 +1127,7 @@ export async function prepareToolExecutionContextForSpecificTools(
     permissionModeState?: PermissionModeState;
     channelToolScope?: MessageChannelToolDiscoveryScope | null;
     channelTurnSources?: ChannelTurnSource[];
-    extensionEvents?: ExtensionEvents;
+    modEvents?: ModEvents;
     runtimeContext?: Partial<RuntimeContextSnapshot>;
   },
 ): Promise<PreparedToolExecutionContext> {
@@ -1145,9 +1140,9 @@ export async function prepareToolExecutionContextForSpecificTools(
       toolRegistry: toolRegistrySnapshot,
       externalTools: new Map(getExternalToolsRegistry()),
       externalExecutor: getExternalToolExecutor(),
-      extensionEvents: options?.extensionEvents,
-      extensionPermissions: getAvailableExtensionPermissionsRegistry(),
-      extensionTools: getAvailableExtensionToolsRegistry(),
+      modEvents: options?.modEvents,
+      modPermissions: getAvailableModPermissionsRegistry(),
+      modTools: getAvailableModToolsRegistry(),
     },
     options,
   );
@@ -1163,7 +1158,7 @@ export async function prepareToolExecutionContextForModel(
     permissionModeState?: PermissionModeState;
     channelToolScope?: MessageChannelToolDiscoveryScope | null;
     channelTurnSources?: ChannelTurnSource[];
-    extensionEvents?: ExtensionEvents;
+    modEvents?: ModEvents;
     runtimeContext?: Partial<RuntimeContextSnapshot>;
   },
 ): Promise<PreparedToolExecutionContext> {
@@ -1176,9 +1171,9 @@ export async function prepareToolExecutionContextForModel(
       toolRegistry: toolRegistrySnapshot,
       externalTools: new Map(getExternalToolsRegistry()),
       externalExecutor: getExternalToolExecutor(),
-      extensionEvents: options?.extensionEvents,
-      extensionPermissions: getAvailableExtensionPermissionsRegistry(),
-      extensionTools: getAvailableExtensionToolsRegistry(),
+      modEvents: options?.modEvents,
+      modPermissions: getAvailableModPermissionsRegistry(),
+      modTools: getAvailableModToolsRegistry(),
     },
     options,
   );
@@ -1190,35 +1185,35 @@ export async function prepareToolExecutionContextForModel(
  * @returns Tool permissions object with requiresApproval flag
  */
 export function getToolPermissions(toolName: string) {
-  const extensionRequiresApproval = extensionToolRequiresApproval(toolName);
-  if (extensionRequiresApproval !== undefined) {
-    return { requiresApproval: extensionRequiresApproval };
+  const modRequiresApproval = modToolRequiresApproval(toolName);
+  if (modRequiresApproval !== undefined) {
+    return { requiresApproval: modRequiresApproval };
   }
   return TOOL_PERMISSIONS[toolName as ToolName] || { requiresApproval: false };
 }
 
-export function isExtensionToolParallelSafeForContext(
+export function isModToolParallelSafeForContext(
   toolName: string,
   contextId?: string,
 ): boolean {
   const context = contextId ? getExecutionContextById(contextId) : undefined;
-  return isExtensionToolParallelSafe(
+  return isModToolParallelSafe(
     toolName,
-    context?.extensionTools ?? getAvailableExtensionToolsRegistry(),
+    context?.modTools ?? getAvailableModToolsRegistry(),
   );
 }
 
-async function checkExtensionPermissionForContext(options: {
+async function checkModPermissionForContext(options: {
   args: ToolArgs;
   context?: ToolExecutionContextSnapshot;
   phase: "approval" | "execution";
   toolCallId?: string | null;
   toolName: string;
   workingDirectory: string;
-}): Promise<ExtensionPermissionDecisionResult | undefined> {
+}): Promise<ModPermissionDecisionResult | undefined> {
   const runtimeContext = options.context?.runtimeContext;
   const permissionModeState = options.context?.permissionModeState;
-  return checkExtensionPermissions(
+  return checkModPermissions(
     {
       agentId: runtimeContext?.agentId ?? null,
       conversationId: runtimeContext?.conversationId ?? null,
@@ -1231,8 +1226,7 @@ async function checkExtensionPermissionForContext(options: {
         permissionModeState?.mode ?? runtimeContext?.permissionMode ?? null,
       phase: options.phase,
     },
-    options.context?.extensionPermissions ??
-      getAvailableExtensionPermissionsRegistry(),
+    options.context?.modPermissions ?? getAvailableModPermissionsRegistry(),
   );
 }
 
@@ -1284,8 +1278,7 @@ export async function checkToolPermission(
         effectiveWorkingDirectory,
         effectivePermissionModeState,
         effectiveAgentId,
-        context?.extensionPermissions ??
-          getAvailableExtensionPermissionsRegistry(),
+        context?.modPermissions ?? getAvailableModPermissionsRegistry(),
         {
           conversationId: context?.runtimeContext.conversationId ?? null,
           phase: "approval",
@@ -1884,7 +1877,7 @@ function createLinkedAbortSignal(signals: Array<AbortSignal | undefined>): {
   };
 }
 
-function getExtensionToolStatus(result: unknown): "success" | "error" {
+function getModToolStatus(result: unknown): "success" | "error" {
   if (!isRecord(result)) return "success";
   if (result.status === "error" || result.isError === true) return "error";
   if (result.success === false) return "error";
@@ -1970,16 +1963,16 @@ function appendHookFeedbackToToolReturn(
   return [...toolReturn, { type: "text" as const, text: feedbackMessage }];
 }
 
-function cloneToolArgsForExtensionEvent(args: ToolArgs): ToolArgs {
+function cloneToolArgsForModEvent(args: ToolArgs): ToolArgs {
   try {
     return structuredClone(args);
   } catch {
     return { ...args };
   }
 }
 
-function createExtensionPermissionToolResult(
-  decision: ExtensionPermissionDecisionResult,
+function createModPermissionToolResult(
+  decision: ModPermissionDecisionResult,
 ): ToolExecutionResult {
   const isApprovalRequest = decision.decision === "ask";
   const action = isApprovalRequest ? "blocked" : "denied";
@@ -1998,7 +1991,7 @@ function isToolStartArgs(value: unknown): value is ToolArgs {
 
 async function emitToolStartEvent(options: {
   args: ToolArgs;
-  events?: ExtensionEvents;
+  events?: ModEvents;
   executionScope: RuntimeContextSnapshot;
   toolCallId?: string;
   toolName: string;
@@ -2008,22 +2001,22 @@ async function emitToolStartEvent(options: {
     conversationId: options.executionScope.conversationId ?? null,
     toolCallId: options.toolCallId ?? null,
     toolName: options.toolName,
-    args: cloneToolArgsForExtensionEvent(options.args),
+    args: cloneToolArgsForModEvent(options.args),
   };
 
   try {
-    await emitExtensionEvent(options.events, "tool_start", event);
+    await emitModEvent(options.events, "tool_start", event);
   } catch (error) {
-    debugLog("extensions", "tool_start event failed", error);
+    debugLog("mods", "tool_start event failed", error);
     return { args: options.args };
   }
 
   return { args: isToolStartArgs(event.args) ? event.args : options.args };
 }
 
-async function executeExtensionTool(
+async function executeModTool(
   toolName: string,
-  tool: ExtensionToolDefinition,
+  tool: ModToolDefinition,
   args: ToolArgs,
   executionScope: RuntimeContextSnapshot,
   options: {
@@ -2059,7 +2052,7 @@ async function executeExtensionTool(
 
     try {
       const backend = getBackend();
-      const context: ExtensionToolRunContext = {
+      const context: ModToolRunContext = {
         args: args as Record<string, unknown>,
         cwd: options.workingDirectory,
         workingDirectory: options.workingDirectory,
@@ -2079,7 +2072,7 @@ async function executeExtensionTool(
           : {}),
         permissionMode: executionScope.permissionMode ?? null,
         agent: { id: executionScope.agentId ?? null },
-        conversation: createExtensionConversationHandle({
+        conversation: createModConversationHandle({
           agentId: executionScope.agentId,
           backend,
           conversationId: executionScope.conversationId,
@@ -2093,7 +2086,7 @@ async function executeExtensionTool(
         }),
         getContext: tool.getContext,
       };
-      const result = await runExtensionTool(tool, context);
+      const result = await runModTool(tool, context);
       const duration = Date.now() - startTime;
       const recordResult = isRecord(result) ? result : undefined;
       const stdout = isStringArray(recordResult?.stdout)
@@ -2102,7 +2095,7 @@ async function executeExtensionTool(
       const stderr = isStringArray(recordResult?.stderr)
         ? recordResult.stderr
         : undefined;
-      const toolStatus = getExtensionToolStatus(result);
+      const toolStatus = getModToolStatus(result);
       const flattenedResponse = flattenToolResponse(result);
       const responseSize =
         typeof flattenedResponse === "string"
@@ -2121,7 +2114,7 @@ async function executeExtensionTool(
       const hookFeedback = await collectPostToolHookFeedback(
         {
           args: args as Record<string, unknown>,
-          debugLabel: "extension tool result path",
+          debugLabel: "mod tool result path",
           scopedAgentId: options.scopedAgentId,
           toolCallId: options.toolCallId,
           toolName,
@@ -2179,7 +2172,7 @@ async function executeExtensionTool(
       const hookFeedback = await collectPostToolHookFeedback(
         {
           args: args as Record<string, unknown>,
-          debugLabel: "extension tool exception path",
+          debugLabel: "mod tool exception path",
           scopedAgentId: options.scopedAgentId,
           toolCallId: options.toolCallId,
           toolName,
@@ -2248,9 +2241,8 @@ export async function executeTool(
     context?.externalTools ?? getExternalToolsRegistry();
   const activeExternalExecutor =
     context?.externalExecutor ?? getExternalToolExecutor();
-  const activeExtensionTools =
-    context?.extensionTools ?? getAvailableExtensionToolsRegistry();
-  const extensionEvents = context?.extensionEvents;
+  const activeModTools = context?.modTools ?? getAvailableModToolsRegistry();
+  const modEvents = context?.modEvents;
   const executionScope = context?.runtimeContext
     ? buildExecutionRuntimeContextSnapshot({
         workingDirectory: context.runtimeContext.workingDirectory ?? undefined,
@@ -2265,22 +2257,22 @@ export async function executeTool(
     executionScope.workingDirectory ?? getCurrentWorkingDirectory();
   const scopedAgentId = executionScope.agentId ?? undefined;
 
-  if (activeExtensionTools.has(name)) {
-    const extensionTool = activeExtensionTools.get(name);
-    if (!extensionTool) {
+  if (activeModTools.has(name)) {
+    const modTool = activeModTools.get(name);
+    if (!modTool) {
       return {
-        toolReturn: `Extension tool not found: ${name}`,
+        toolReturn: `Mod tool not found: ${name}`,
         status: "error",
       };
     }
     const { args: eventArgs } = await emitToolStartEvent({
       args,
-      events: extensionEvents,
+      events: modEvents,
       executionScope,
       toolCallId: options?.toolCallId,
       toolName: name,
     });
-    const permissionDecision = await checkExtensionPermissionForContext({
+    const permissionDecision = await checkModPermissionForContext({
       args: eventArgs,
       context,
       phase: "execution",
@@ -2290,34 +2282,28 @@ export async function executeTool(
     });
     if (permissionDecision?.decision !== undefined) {
       if (permissionDecision.decision !== "allow") {
-        return createExtensionPermissionToolResult(permissionDecision);
+        return createModPermissionToolResult(permissionDecision);
       }
     }
-    return executeExtensionTool(
-      name,
-      extensionTool,
-      eventArgs,
-      executionScope,
-      {
-        signal: options?.signal,
-        toolCallId: options?.toolCallId,
-        onOutput: options?.onOutput,
-        workingDirectory,
-        scopedAgentId,
-      },
-    );
+    return executeModTool(name, modTool, eventArgs, executionScope, {
+      signal: options?.signal,
+      toolCallId: options?.toolCallId,
+      onOutput: options?.onOutput,
+      workingDirectory,
+      scopedAgentId,
+    });
   }
 
   // Check if this is an external tool (SDK-executed)
   if (activeExternalTools.has(name)) {
     const { args: eventArgs } = await emitToolStartEvent({
       args,
-      events: extensionEvents,
+      events: modEvents,
       executionScope,
       toolCallId: options?.toolCallId,
       toolName: name,
     });
-    const permissionDecision = await checkExtensionPermissionForContext({
+    const permissionDecision = await checkModPermissionForContext({
       args: eventArgs,
       context,
       phase: "execution",
@@ -2327,7 +2313,7 @@ export async function executeTool(
     });
     if (permissionDecision?.decision !== undefined) {
       if (permissionDecision.decision !== "allow") {
-        return createExtensionPermissionToolResult(permissionDecision);
+        return createModPermissionToolResult(permissionDecision);
       }
     }
     return executeExternalTool(
@@ -2343,7 +2329,7 @@ export async function executeTool(
     const availableTools = [
       ...Array.from(activeRegistry.keys()),
       ...Array.from(activeExternalTools.keys()),
-      ...Array.from(activeExtensionTools.keys()),
+      ...Array.from(activeModTools.keys()),
     ];
     return {
       toolReturn: `Tool not found: ${name}. Available tools: ${availableTools.join(", ")}`,
@@ -2356,7 +2342,7 @@ export async function executeTool(
     const availableTools = [
       ...Array.from(activeRegistry.keys()),
       ...Array.from(activeExternalTools.keys()),
-      ...Array.from(activeExtensionTools.keys()),
+      ...Array.from(activeModTools.keys()),
     ];
     return {
       toolReturn: `Tool not found: ${name}. Available tools: ${availableTools.join(", ")}`,
@@ -2366,13 +2352,13 @@ export async function executeTool(
 
   const { args: eventArgs } = await emitToolStartEvent({
     args,
-    events: extensionEvents,
+    events: modEvents,
     executionScope,
     toolCallId: options?.toolCallId,
     toolName: internalName,
   });
   args = eventArgs;
-  const permissionDecision = await checkExtensionPermissionForContext({
+  const permissionDecision = await checkModPermissionForContext({
     args,
     context,
     phase: "execution",
@@ -2382,7 +2368,7 @@ export async function executeTool(
   });
   if (permissionDecision?.decision !== undefined) {
     if (permissionDecision.decision !== "allow") {
-      return createExtensionPermissionToolResult(permissionDecision);
+      return createModPermissionToolResult(permissionDecision);
     }
   }
   const startTime = Date.now();
@@ -2695,14 +2681,14 @@ export function getToolSchemas(): ToolSchema[] {
   const builtInSchemas = Array.from(
     withDynamicMessageChannelCache(toolRegistry).values(),
   ).map((tool) => tool.schema);
-  const extensionSchemas = Array.from(
-    getAvailableExtensionToolsRegistry().values(),
-  ).map((tool) => ({
-    name: tool.name,
-    description: tool.description,
-    input_schema: tool.parameters as JsonSchema,
-  }));
-  return [...builtInSchemas, ...extensionSchemas];
+  const modSchemas = Array.from(getAvailableModToolsRegistry().values()).map(
+    (tool) => ({
+      name: tool.name,
+      description: tool.description,
+      input_schema: tool.parameters as JsonSchema,
+    }),
+  );
+  return [...builtInSchemas, ...modSchemas];
 }
 
 /**
@@ -2717,12 +2703,12 @@ export function getToolSchema(name: string): ToolSchema | undefined {
     return withDynamicMessageChannelCache(toolRegistry).get(internalName)
       ?.schema;
   }
-  const extensionTool = getExtensionToolDefinition(name);
-  if (extensionTool) {
+  const modTool = getModToolDefinition(name);
+  if (modTool) {
     return {
-      name: extensionTool.name,
-      description: extensionTool.description,
-      input_schema: extensionTool.parameters as JsonSchema,
+      name: modTool.name,
+      description: modTool.description,
+      input_schema: modTool.parameters as JsonSchema,
     };
   }
   const externalTool = getExternalToolDefinition(name);
diff --git a/src/tools/toolset.ts b/src/tools/toolset.ts
--- a/src/tools/toolset.ts
+++ b/src/tools/toolset.ts
@@ -7,7 +7,7 @@ import { getSupportedChannelIds } from "@/channels/plugin-registry";
 import { getChannelRegistry } from "@/channels/registry";
 import { getRoutesForChannel, loadRoutes } from "@/channels/routing";
 import type { ChannelTurnSource, SupportedChannelId } from "@/channels/types";
-import type { ExtensionEvents } from "@/extensions/event-emitter";
+import type { ModEvents } from "@/mods/event-emitter";
 import {
   type InheritedChannelContextPayload,
   LETTA_INHERITED_CHANNEL_CONTEXT_ENV,
@@ -196,7 +196,7 @@ export async function prepareToolExecutionContextForResolvedTarget(params: {
   workingDirectory?: string;
   permissionModeState?: PermissionModeState;
   channelToolScope?: MessageChannelToolDiscoveryScope | null;
-  extensionEvents?: ExtensionEvents;
+  modEvents?: ModEvents;
   runtimeContext?: Partial<RuntimeContextSnapshot>;
 }): Promise<PreparedScopeToolContext> {
   const {
@@ -208,7 +208,7 @@ export async function prepareToolExecutionContextForResolvedTarget(params: {
     workingDirectory,
     permissionModeState,
     channelToolScope,
-    extensionEvents,
+    modEvents,
     runtimeContext,
   } = params;
   const effectiveModel =
@@ -234,7 +234,7 @@ export async function prepareToolExecutionContextForResolvedTarget(params: {
         workingDirectory,
         permissionModeState,
         channelToolScope,
-        extensionEvents,
+        modEvents,
         runtimeContext,
       },
     );
@@ -265,7 +265,7 @@ export async function prepareToolExecutionContextForResolvedTarget(params: {
       workingDirectory,
       permissionModeState,
       channelToolScope,
-      extensionEvents,
+      modEvents,
       runtimeContext,
     },
   );
@@ -434,7 +434,7 @@ export async function prepareToolExecutionContextForScope(params: {
   permissionModeState?: PermissionModeState;
   cachedAgent?: AgentState | null;
   channelTurnSources?: import("@/channels/types").ChannelTurnSource[];
-  extensionEvents?: ExtensionEvents;
+  modEvents?: ModEvents;
 }): Promise<PreparedScopeToolContext> {
   const {
     agentId,
@@ -447,7 +447,7 @@ export async function prepareToolExecutionContextForScope(params: {
     permissionModeState,
     cachedAgent,
     channelTurnSources: explicitChannelTurnSources,
-    extensionEvents,
+    modEvents,
   } = params;
 
   const backend = getBackend();
@@ -507,7 +507,7 @@ export async function prepareToolExecutionContextForScope(params: {
     clientToolAllowlist,
     workingDirectory,
     permissionModeState,
-    extensionEvents,
+    modEvents,
     runtimeContext: {
       agentId,
       conversationId: scopedConversationId,
diff --git a/src/websocket/listener/commands.ts b/src/websocket/listener/commands.ts
--- a/src/websocket/listener/commands.ts
+++ b/src/websocket/listener/commands.ts
@@ -43,7 +43,7 @@ import type {
 } from "@/types/protocol_v2";
 import { debugLog } from "@/utils/debug";
 import { markSecretsReminderRefreshPending } from "./commands/secrets";
-import { reloadListenerExtensionAdapter } from "./extension-adapter";
+import { reloadListenerModAdapter } from "./mod-adapter";
 import {
   getOrCreateConversationPermissionModeStateRef,
   persistPermissionModeMapForRuntime,
@@ -221,15 +221,15 @@ async function handleReloadCommand(
     );
   }
 
-  await reloadListenerExtensionAdapter(listener);
+  await reloadListenerModAdapter(listener);
 
   if (conversationRuntime.agentId) {
     invalidateSecretsCacheForAgent(listener, conversationRuntime.agentId);
     markSecretsReminderRefreshPending(listener, conversationRuntime.agentId);
     await ensureSecretsHydratedForAgent(listener, conversationRuntime.agentId);
   }
 
-  return "Reloaded settings, local extensions, and agent secrets";
+  return "Reloaded settings, local mods, and agent secrets";
 }
 
 async function handleUpgradeLettaCodeCommand(opts: {
diff --git a/src/websocket/listener/lifecycle.ts b/src/websocket/listener/lifecycle.ts
--- a/src/websocket/listener/lifecycle.ts
+++ b/src/websocket/listener/lifecycle.ts
@@ -55,12 +55,12 @@ import {
   getOrCreateScopedRuntime,
 } from "./conversation-runtime";
 import { loadPersistedCwdMap } from "./cwd";
-import {
-  disposeListenerExtensionAdapter,
-  reloadListenerExtensionAdapter,
-} from "./extension-adapter";
 import { createFileCommandSession } from "./file-commands";
 import { createListenerMessageHandler } from "./message-router";
+import {
+  disposeListenerModAdapter,
+  reloadListenerModAdapter,
+} from "./mod-adapter";
 import {
   getOrCreateConversationPermissionModeStateRef,
   loadPersistedPermissionModeMap,
@@ -795,7 +795,7 @@ export function stopRuntime(
   runtime: ListenerRuntime,
   suppressCallbacks: boolean,
 ): void {
-  disposeListenerExtensionAdapter(runtime);
+  disposeListenerModAdapter(runtime);
   setMessageQueueAdder(null); // Clear bridge for ALL stop paths
   runtime.intentionallyClosed = true;
   clearRuntimeTimers(runtime);
@@ -1055,7 +1055,7 @@ export async function startListenerClient(
   telemetry.setSurface(getListenerTelemetrySurface());
   telemetry.init();
 
-  await reloadListenerExtensionAdapter(runtime);
+  await reloadListenerModAdapter(runtime);
   await connectWithRetry(runtime, opts);
 }
 
@@ -1090,7 +1090,7 @@ export async function startLocalChannelListener(
   telemetry.init();
 
   try {
-    await reloadListenerExtensionAdapter(runtime);
+    await reloadListenerModAdapter(runtime);
     await loadTools();
     const transport = new LocalListenerTransport();
     const processQueuedTurn: ProcessQueuedTurn = async (
diff --git a/src/websocket/listener/extension-adapter.ts b/src/websocket/listener/mod-adapter.ts
rename from src/websocket/listener/extension-adapter.ts
rename to src/websocket/listener/mod-adapter.ts
--- a/src/websocket/listener/extension-adapter.ts
+++ b/src/websocket/listener/mod-adapter.ts
@@ -1,18 +1,12 @@
 import type Letta from "@letta-ai/letta-client";
 import { getBackend } from "@/backend";
-import {
-  createExtensionAdapter,
-  type ExtensionAdapter,
-} from "@/extensions/extension-adapter";
-import type {
-  ExtensionCapabilities,
-  ExtensionContext,
-} from "@/extensions/types";
+import { createModAdapter, type ModAdapter } from "@/mods/mod-adapter";
+import type { ModCapabilities, ModContext } from "@/mods/types";
 import { getCurrentWorkingDirectory } from "@/runtime-context";
 import { getVersion } from "@/version";
 import type { ListenerRuntime } from "./types";
 
-export const LISTENER_EXTENSION_CAPABILITIES: ExtensionCapabilities = {
+export const LISTENER_MOD_CAPABILITIES: ModCapabilities = {
   tools: false,
   commands: false,
   events: {
@@ -29,27 +23,25 @@ export const LISTENER_EXTENSION_CAPABILITIES: ExtensionCapabilities = {
   },
 };
 
-export interface CreateListenerExtensionAdapterOptions {
+export interface CreateListenerModAdapterOptions {
   cacheDirectory?: string;
   diagnosticsRootDirectory?: string;
   disabled?: boolean;
-  globalExtensionsDirectory?: string;
+  globalModsDirectory?: string;
   sessionId?: string | null;
   workingDirectory?: string | null;
 }
 
 async function getUnavailableListenerClient(): Promise<Letta> {
-  throw new Error(
-    "letta.client is not available in listener provider extensions",
-  );
+  throw new Error("letta.client is not available in listener provider mods");
 }
 
-export function createListenerExtensionContext(
+export function createListenerModContext(
   options: Pick<
-    CreateListenerExtensionAdapterOptions,
+    CreateListenerModAdapterOptions,
     "sessionId" | "workingDirectory"
   > = {},
-): ExtensionContext {
+): ModContext {
   const cwd = options.workingDirectory ?? getCurrentWorkingDirectory();
   return {
     app: { version: getVersion() },
@@ -103,53 +95,49 @@ export function createListenerExtensionContext(
   };
 }
 
-export function createListenerExtensionAdapter(
-  options: CreateListenerExtensionAdapterOptions = {},
-): ExtensionAdapter {
-  return createExtensionAdapter({
+export function createListenerModAdapter(
+  options: CreateListenerModAdapterOptions = {},
+): ModAdapter {
+  return createModAdapter({
     ...(options.cacheDirectory
       ? { cacheDirectory: options.cacheDirectory }
       : {}),
-    capabilities: LISTENER_EXTENSION_CAPABILITIES,
+    capabilities: LISTENER_MOD_CAPABILITIES,
     ...(options.diagnosticsRootDirectory
       ? { diagnosticsRootDirectory: options.diagnosticsRootDirectory }
       : {}),
     disabled: options.disabled,
     getBackend,
     getClient: getUnavailableListenerClient,
-    ...(options.globalExtensionsDirectory
-      ? { globalExtensionsDirectory: options.globalExtensionsDirectory }
+    ...(options.globalModsDirectory
+      ? { globalModsDirectory: options.globalModsDirectory }
       : {}),
-    initialContext: createListenerExtensionContext(options),
+    initialContext: createListenerModContext(options),
   });
 }
 
-export function ensureListenerExtensionAdapter(
-  runtime: ListenerRuntime,
-): ExtensionAdapter {
-  runtime.extensionAdapter ??= createListenerExtensionAdapter({
+export function ensureListenerModAdapter(runtime: ListenerRuntime): ModAdapter {
+  runtime.modAdapter ??= createListenerModAdapter({
     sessionId: runtime.sessionId,
     workingDirectory: runtime.bootWorkingDirectory,
   });
-  return runtime.extensionAdapter;
+  return runtime.modAdapter;
 }
 
-export async function reloadListenerExtensionAdapter(
+export async function reloadListenerModAdapter(
   runtime: ListenerRuntime,
 ): Promise<void> {
-  const adapter = ensureListenerExtensionAdapter(runtime);
+  const adapter = ensureListenerModAdapter(runtime);
   adapter.updateContext(
-    createListenerExtensionContext({
+    createListenerModContext({
       sessionId: runtime.sessionId,
       workingDirectory: runtime.bootWorkingDirectory,
     }),
   );
   await adapter.reload();
 }
 
-export function disposeListenerExtensionAdapter(
-  runtime: ListenerRuntime,
-): void {
-  runtime.extensionAdapter?.dispose();
-  runtime.extensionAdapter = undefined;
+export function disposeListenerModAdapter(runtime: ListenerRuntime): void {
+  runtime.modAdapter?.dispose();
+  runtime.modAdapter = undefined;
 }
diff --git a/src/websocket/listener/types.ts b/src/websocket/listener/types.ts
--- a/src/websocket/listener/types.ts
+++ b/src/websocket/listener/types.ts
@@ -8,7 +8,7 @@ import type {
 import type { ChannelTurnSource } from "@/channels/types";
 import type { ContextTracker } from "@/cli/helpers/context-tracker";
 import type { ApprovalRequest } from "@/cli/helpers/stream";
-import type { ExtensionAdapter } from "@/extensions/extension-adapter";
+import type { ModAdapter } from "@/mods/mod-adapter";
 import type { ApprovalContext } from "@/permissions/analyzer";
 import type {
   DequeuedBatch,
@@ -182,8 +182,8 @@ export type ListenerRuntime = {
   hasSuccessfulConnection: boolean;
   /** True once the WS has connected at least once. Never reset to false. */
   everConnected: boolean;
-  /** Provider-only local extension adapter for desktop/listener surfaces. */
-  extensionAdapter?: ExtensionAdapter | undefined;
+  /** Provider-only local mod adapter for desktop/listener surfaces. */
+  modAdapter?: ModAdapter | undefined;
   sessionId: string;
   eventSeqCounter: number;
   lastStopReason: string | null;
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
