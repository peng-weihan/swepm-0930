#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/src/main/services/extensions/catalog/PluginCatalogService.ts b/src/main/services/extensions/catalog/PluginCatalogService.ts
--- a/src/main/services/extensions/catalog/PluginCatalogService.ts
+++ b/src/main/services/extensions/catalog/PluginCatalogService.ts
@@ -289,6 +289,7 @@ export class PluginCatalogService {
         marketplaceId: qualifiedName,
         qualifiedName,
         name: raw.name,
+        source: 'official',
         description: raw.description ?? '',
         category: raw.category ?? 'other',
         author: raw.author,
diff --git a/src/main/services/team/ChangeExtractorService.ts b/src/main/services/team/ChangeExtractorService.ts
--- a/src/main/services/team/ChangeExtractorService.ts
+++ b/src/main/services/team/ChangeExtractorService.ts
@@ -132,19 +132,25 @@ export class ChangeExtractorService {
     }
   ): Promise<TaskChangeSetV2> {
     const includeDetails = options?.summaryOnly !== true;
-    const cacheKey = `task:${teamName}:${taskId}`;
-    const cached = includeDetails ? this.taskChangeCache.get(cacheKey) : undefined;
-    if (cached && cached.expiresAt > Date.now()) {
-      return cached.data;
-    }
-
     const taskMeta = await this.readTaskMeta(teamName, taskId);
-    const logs = await this.logsFinder.findLogsForTask(teamName, taskId, {
+    const effectiveOptions = {
       owner: options?.owner ?? taskMeta?.owner,
       status: options?.status ?? taskMeta?.status,
       intervals: options?.intervals ?? taskMeta?.intervals,
       since: options?.since,
-    });
+    };
+    const cacheKey = this.buildTaskChangeCacheKey(
+      teamName,
+      taskId,
+      effectiveOptions,
+      includeDetails
+    );
+    const cached = includeDetails ? this.taskChangeCache.get(cacheKey) : undefined;
+    if (cached && cached.expiresAt > Date.now()) {
+      return cached.data;
+    }
+
+    const logs = await this.logsFinder.findLogsForTask(teamName, taskId, effectiveOptions);
     const logRefs = await this.resolveLogFileRefs(teamName, logs);
     if (logRefs.length === 0) {
       const empty = this.emptyTaskChangeSet(teamName, taskId);
@@ -171,7 +177,7 @@ export class ChangeExtractorService {
 
     // Если scope не найден — try deterministic interval scoping, else fallback to whole file
     if (allScopes.length === 0) {
-      const intervals = options?.intervals ?? taskMeta?.intervals;
+      const intervals = effectiveOptions.intervals;
       if (Array.isArray(intervals) && intervals.length > 0) {
         const { files, toolUseIds, startTimestamp, endTimestamp } =
           await this.extractIntervalScopedChanges(logRefs, intervals, projectPath, includeDetails);
@@ -345,7 +351,8 @@ export class ChangeExtractorService {
         status: typeof parsed.status === 'string' ? parsed.status : undefined,
         intervals: derivedIntervals,
       };
-    } catch {
+    } catch (error) {
+      logger.debug(`Failed to read task meta for ${teamName}/${taskId}: ${String(error)}`);
       return null;
     }
   }
@@ -532,7 +539,7 @@ export class ChangeExtractorService {
           const replaceAll = input.replace_all === true;
 
           if (targetPath) {
-            seenFiles.add(targetPath);
+            seenFiles.add(this.normalizeFilePathKey(targetPath));
             snippets.push({
               toolUseId,
               filePath: targetPath,
@@ -551,8 +558,9 @@ export class ChangeExtractorService {
           const writeContent = typeof input.content === 'string' ? input.content : '';
 
           if (targetPath) {
-            const isNew = !seenFiles.has(targetPath);
-            seenFiles.add(targetPath);
+            const normalizedTargetPath = this.normalizeFilePathKey(targetPath);
+            const isNew = !seenFiles.has(normalizedTargetPath);
+            seenFiles.add(normalizedTargetPath);
             snippets.push({
               toolUseId,
               filePath: targetPath,
@@ -571,7 +579,7 @@ export class ChangeExtractorService {
           const edits = Array.isArray(input.edits) ? input.edits : [];
 
           if (targetPath) {
-            seenFiles.add(targetPath);
+            seenFiles.add(this.normalizeFilePathKey(targetPath));
             for (const edit of edits) {
               if (!edit || typeof edit !== 'object') continue;
               const editObj = edit as Record<string, unknown>;
@@ -668,24 +676,30 @@ export class ChangeExtractorService {
     projectPath?: string,
     includeDetails = true
   ): FileChangeSummary[] {
-    const fileMap = new Map<string, { snippets: SnippetDiff[]; isNewFile: boolean }>();
+    const fileMap = new Map<
+      string,
+      { filePath: string; snippets: SnippetDiff[]; isNewFile: boolean }
+    >();
 
     for (const snippet of snippets) {
       // Пропускаем snippets с ошибками при агрегации
       if (snippet.isError) continue;
 
-      const existing = fileMap.get(snippet.filePath);
+      const normalizedFilePath = this.normalizeFilePathKey(snippet.filePath);
+      const existing = fileMap.get(normalizedFilePath);
       if (existing) {
         existing.snippets.push(snippet);
       } else {
-        fileMap.set(snippet.filePath, {
+        fileMap.set(normalizedFilePath, {
+          filePath: snippet.filePath,
           snippets: [snippet],
           isNewFile: snippet.type === 'write-new',
         });
       }
     }
 
-    return [...fileMap.entries()].map(([fp, data]) => {
+    return [...fileMap.values()].map((data) => {
+      const fp = data.filePath;
       let totalAdded = 0;
       let totalRemoved = 0;
       for (const s of data.snippets) {
@@ -854,16 +868,12 @@ export class ChangeExtractorService {
     projectPath?: string,
     includeDetails = true
   ): Promise<TaskChangeSetV2> {
-    const allFiles: FileChangeSummary[] = [];
+    const allSnippets: SnippetDiff[] = [];
     for (const ref of logRefs) {
-      const files = await this.extractAllChanges(
-        ref.filePath,
-        ref.memberName,
-        projectPath,
-        includeDetails
-      );
-      allFiles.push(...files);
+      const snippets = await this.parseJSONLFile(ref.filePath);
+      allSnippets.push(...snippets);
     }
+    const allFiles = this.aggregateByFile(allSnippets, projectPath, includeDetails);
 
     const fallbackScope: TaskChangeScope = {
       taskId,
@@ -916,4 +926,42 @@ export class ChangeExtractorService {
       warnings: ['No log files found for this task.'],
     };
   }
+
+  private buildTaskChangeCacheKey(
+    teamName: string,
+    taskId: string,
+    options: {
+      owner?: string;
+      status?: string;
+      intervals?: { startedAt: string; completedAt?: string }[];
+      since?: string;
+    },
+    includeDetails: boolean
+  ): string {
+    const owner = typeof options.owner === 'string' ? options.owner.trim() : '';
+    const status = typeof options.status === 'string' ? options.status.trim() : '';
+    const since = typeof options.since === 'string' ? options.since : '';
+    const intervals = Array.isArray(options.intervals)
+      ? options.intervals.map((interval) => ({
+          startedAt: interval.startedAt,
+          completedAt: interval.completedAt ?? '',
+        }))
+      : [];
+
+    return JSON.stringify({
+      type: 'task',
+      teamName,
+      taskId,
+      includeDetails,
+      owner,
+      status,
+      since,
+      intervals,
+    });
+  }
+
+  private normalizeFilePathKey(filePath: string): string {
+    const normalized = filePath.replace(/\\/g, '/');
+    return normalized.replace(/^[A-Z]:/, (drive) => drive.toLowerCase());
+  }
 }
diff --git a/src/main/services/team/TaskBoundaryParser.ts b/src/main/services/team/TaskBoundaryParser.ts
--- a/src/main/services/team/TaskBoundaryParser.ts
+++ b/src/main/services/team/TaskBoundaryParser.ts
@@ -35,6 +35,13 @@ const MCP_TASK_BOUNDARY_TOOLS = new Set(['task_start', 'task_complete', 'task_se
 
 type DetectedMechanism = 'TaskUpdate' | 'mcp' | 'none';
 
+function extractTaskId(input: Record<string, unknown>): string {
+  const rawTaskId = input.taskId ?? input.task_id;
+  if (typeof rawTaskId === 'string') return rawTaskId;
+  if (typeof rawTaskId === 'number') return String(rawTaskId);
+  return '';
+}
+
 function pickDetectedMechanism(
   current: DetectedMechanism,
   next: Exclude<DetectedMechanism, 'none'>
@@ -191,13 +198,7 @@ export class TaskBoundaryParser {
       const input = b.input as Record<string, unknown> | undefined;
       if (!input) continue;
 
-      const rawTaskId = input.taskId;
-      const taskId =
-        typeof rawTaskId === 'string'
-          ? rawTaskId
-          : typeof rawTaskId === 'number'
-            ? String(rawTaskId)
-            : '';
+      const taskId = extractTaskId(input);
       if (!taskId) continue;
 
       const status = typeof input.status === 'string' ? input.status : '';
@@ -243,13 +244,7 @@ export class TaskBoundaryParser {
       const input = b.input as Record<string, unknown> | undefined;
       if (!input) continue;
 
-      const rawTaskId = input.taskId;
-      const taskId =
-        typeof rawTaskId === 'string'
-          ? rawTaskId
-          : typeof rawTaskId === 'number'
-            ? String(rawTaskId)
-            : '';
+      const taskId = extractTaskId(input);
       if (!taskId) continue;
 
       let event: TaskBoundaryEvent = null;
diff --git a/src/main/services/team/TeamMcpConfigBuilder.ts b/src/main/services/team/TeamMcpConfigBuilder.ts
--- a/src/main/services/team/TeamMcpConfigBuilder.ts
+++ b/src/main/services/team/TeamMcpConfigBuilder.ts
@@ -4,6 +4,9 @@ import * as fs from 'fs';
 import * as os from 'os';
 import * as path from 'path';
 
+import { getHomeDir } from '@main/utils/pathDecoder';
+import { createLogger } from '@shared/utils/logger';
+
 import { atomicWriteAsync } from './atomicWrite';
 
 interface McpLaunchSpec {
@@ -12,6 +15,14 @@ interface McpLaunchSpec {
 }
 
 const MCP_SERVER_NAME = 'agent-teams';
+const logger = createLogger('Service:TeamMcpConfigBuilder');
+const USER_MCP_CONFIG_NAME = '.claude.json';
+
+type McpServerConfig = Record<string, unknown>;
+
+function isRecord(value: unknown): value is Record<string, unknown> {
+  return !!value && typeof value === 'object' && !Array.isArray(value);
+}
 
 function getWorkspaceRoot(): string {
   return process.cwd();
@@ -94,22 +105,25 @@ async function resolveMcpLaunchSpec(): Promise<McpLaunchSpec> {
 }
 
 export class TeamMcpConfigBuilder {
-  async writeConfigFile(): Promise<string> {
+  async writeConfigFile(_projectPath?: string): Promise<string> {
     const launchSpec = await resolveMcpLaunchSpec();
     const configDir = path.join(os.tmpdir(), 'claude-team-mcp');
     const configPath = path.join(configDir, `agent-teams-mcp-${randomUUID()}.json`);
+    const userServers = await this.readUserMcpServers();
+    const generatedServers: Record<string, McpServerConfig> = {
+      [MCP_SERVER_NAME]: {
+        command: launchSpec.command,
+        args: launchSpec.args,
+      },
+    };
+    const mergedServers = this.mergeServers(userServers, generatedServers);
 
     await fs.promises.mkdir(configDir, { recursive: true });
     await atomicWriteAsync(
       configPath,
       JSON.stringify(
         {
-          mcpServers: {
-            [MCP_SERVER_NAME]: {
-              command: launchSpec.command,
-              args: launchSpec.args,
-            },
-          },
+          mcpServers: mergedServers,
         },
         null,
         2
@@ -118,4 +132,61 @@ export class TeamMcpConfigBuilder {
 
     return configPath;
   }
+
+  private async readUserMcpServers(): Promise<Record<string, McpServerConfig>> {
+    const configPath = path.join(getHomeDir(), USER_MCP_CONFIG_NAME);
+    return this.readMcpServersFromFile(configPath, 'user');
+  }
+
+  private async readMcpServersFromFile(
+    filePath: string,
+    scope: 'user'
+  ): Promise<Record<string, McpServerConfig>> {
+    try {
+      const raw = await fs.promises.readFile(filePath, 'utf8');
+      const parsed = JSON.parse(raw) as Record<string, unknown>;
+      const mcpServers = parsed.mcpServers;
+      if (!isRecord(mcpServers)) {
+        return {};
+      }
+
+      return Object.fromEntries(
+        Object.entries(mcpServers).filter(([, config]) => isRecord(config))
+      ) as Record<string, McpServerConfig>;
+    } catch (error) {
+      const err = error as NodeJS.ErrnoException;
+      if (err.code === 'ENOENT') {
+        return {};
+      }
+
+      logger.warn(
+        `Failed to read ${scope} MCP config from ${filePath}: ${
+          error instanceof Error ? error.message : String(error)
+        }`
+      );
+      return {};
+    }
+  }
+
+  private mergeServers(
+    userServers: Record<string, McpServerConfig>,
+    generatedServers: Record<string, McpServerConfig>
+  ): Record<string, McpServerConfig> {
+    const duplicates = Object.keys(userServers).filter((name) =>
+      Object.hasOwn(generatedServers, name)
+    );
+
+    if (duplicates.length > 0) {
+      logger.info(`Merging MCP configs with overrides for: ${duplicates.join(', ')}`);
+    }
+
+    // We inline only top-level user MCP into --mcp-config.
+    // Project/local scopes are still loaded natively by Claude via
+    // --setting-sources user,project,local, which preserves documented precedence:
+    // local > project > user. Generated agent-teams must always win on name collision.
+    return {
+      ...userServers,
+      ...generatedServers,
+    };
+  }
 }
diff --git a/src/main/services/team/TeamProvisioningService.ts b/src/main/services/team/TeamProvisioningService.ts
--- a/src/main/services/team/TeamProvisioningService.ts
+++ b/src/main/services/team/TeamProvisioningService.ts
@@ -2387,7 +2387,7 @@ export class TeamProvisioningService {
       const { env: shellEnv } = await this.buildProvisioningEnv();
       let mcpConfigPath: string;
       try {
-        mcpConfigPath = await this.mcpConfigBuilder.writeConfigFile();
+        mcpConfigPath = await this.mcpConfigBuilder.writeConfigFile(request.cwd);
       } catch (error) {
         this.runs.delete(runId);
         this.activeByTeam.delete(request.teamName);
@@ -2734,7 +2734,7 @@ export class TeamProvisioningService {
       const { env: shellEnv } = await this.buildProvisioningEnv();
       let mcpConfigPath: string;
       try {
-        mcpConfigPath = await this.mcpConfigBuilder.writeConfigFile();
+        mcpConfigPath = await this.mcpConfigBuilder.writeConfigFile(request.cwd);
       } catch (error) {
         this.runs.delete(runId);
         this.activeByTeam.delete(request.teamName);
diff --git a/src/renderer/components/extensions/mcp/McpServerCard.tsx b/src/renderer/components/extensions/mcp/McpServerCard.tsx
--- a/src/renderer/components/extensions/mcp/McpServerCard.tsx
+++ b/src/renderer/components/extensions/mcp/McpServerCard.tsx
@@ -17,16 +17,11 @@ import { Cloud, Clock, Globe, KeyRound, Lock, Monitor, Star, Tag, Wrench } from
 import { Github as GithubIcon } from 'lucide-react';
 
 import { InstallButton } from '../common/InstallButton';
+import { SourceBadge } from '../common/SourceBadge';
 import { sanitizeMcpServerName } from '@shared/utils/extensionNormalizers';
 
 import type { McpCatalogItem, McpServerDiagnostic } from '@shared/types/extensions';
 
-/** Ribbon colors by source */
-const RIBBON_STYLES: Record<string, string> = {
-  official: 'bg-blue-500/90 text-white',
-  glama: 'bg-zinc-600/90 text-zinc-200',
-};
-
 interface McpServerCardProps {
   server: McpCatalogItem;
   isInstalled: boolean;
@@ -81,17 +76,8 @@ export const McpServerCard = ({
         isInstalled ? 'border-l-2 border-border border-l-emerald-500/30' : 'border-border'
       }`}
     >
-      {/* Source ribbon (top-left corner) */}
-      <div className="pointer-events-none absolute -left-[1px] -top-[1px] size-16 overflow-hidden">
-        <div
-          className={`absolute left-[-18px] top-[8px] w-[80px] rotate-[-45deg] text-center text-[9px] font-semibold leading-[18px] shadow-sm ${RIBBON_STYLES[server.source] ?? RIBBON_STYLES.glama}`}
-        >
-          {server.source === 'official' ? 'Official' : 'Glama'}
-        </div>
-      </div>
-
       {/* Header: icon + name */}
-      <div className={`flex items-start gap-2.5 ${hasIcon ? 'pl-5' : 'pl-7'}`}>
+      <div className="flex items-start gap-2.5">
         {/* Server icon (only when available) */}
         {hasIcon && (
           <div className="flex size-9 shrink-0 items-center justify-center rounded-lg border border-border bg-surface-raised">
@@ -105,7 +91,14 @@ export const McpServerCard = ({
         )}
         <div className="min-w-0 flex-1">
           <div className="flex items-start justify-between gap-2">
-            <h3 className="truncate text-sm font-semibold text-text">{server.name}</h3>
+            <div className="min-w-0">
+              <h3 className="truncate text-sm font-semibold text-text">{server.name}</h3>
+              {server.source !== 'official' && (
+                <div className="mt-1">
+                  <SourceBadge source={server.source} />
+                </div>
+              )}
+            </div>
             <div className="flex shrink-0 items-center gap-1.5">
               {isInstalled && (
                 <Badge
diff --git a/src/renderer/components/extensions/mcp/McpServerDetailDialog.tsx b/src/renderer/components/extensions/mcp/McpServerDetailDialog.tsx
--- a/src/renderer/components/extensions/mcp/McpServerDetailDialog.tsx
+++ b/src/renderer/components/extensions/mcp/McpServerDetailDialog.tsx
@@ -236,7 +236,7 @@ export const McpServerDetailDialog = ({
                       Installed
                     </Badge>
                   )}
-                  <SourceBadge source={server.source} />
+                  {server.source !== 'official' && <SourceBadge source={server.source} />}
                 </div>
               </div>
             </div>
diff --git a/src/renderer/components/extensions/plugins/PluginCard.tsx b/src/renderer/components/extensions/plugins/PluginCard.tsx
--- a/src/renderer/components/extensions/plugins/PluginCard.tsx
+++ b/src/renderer/components/extensions/plugins/PluginCard.tsx
@@ -18,16 +18,20 @@ import type { EnrichedPlugin } from '@shared/types/extensions';
 
 interface PluginCardProps {
   plugin: EnrichedPlugin;
+  index: number;
   onClick: (pluginId: string) => void;
 }
 
-export const PluginCard = ({ plugin, onClick }: PluginCardProps): React.JSX.Element => {
+export const PluginCard = ({ plugin, index, onClick }: PluginCardProps): React.JSX.Element => {
   const capabilities = inferCapabilities(plugin);
   const category = normalizeCategory(plugin.category);
   const installProgress = useStore((s) => s.pluginInstallProgress[plugin.pluginId] ?? 'idle');
   const installPlugin = useStore((s) => s.installPlugin);
   const uninstallPlugin = useStore((s) => s.uninstallPlugin);
   const installError = useStore((s) => s.installErrors[plugin.pluginId]);
+  const baseStriped = index % 2 === 0;
+  const smStriped = Math.floor(index / 2) % 2 === 0;
+  const xlStriped = Math.floor(index / 3) % 2 === 0;
 
   return (
     <div
@@ -40,10 +44,22 @@ export const PluginCard = ({ plugin, onClick }: PluginCardProps): React.JSX.Elem
           onClick(plugin.pluginId);
         }
       }}
-      className={`hover:bg-surface-raised/45 flex w-full cursor-pointer flex-col gap-3 rounded-xl border bg-transparent p-4 text-left transition-all duration-200 hover:border-border-emphasis hover:shadow-[0_0_12px_rgba(255,255,255,0.02)] focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-[var(--color-border-emphasis)] ${
+      className={`hover:bg-surface-raised/45 relative flex w-full cursor-pointer flex-col gap-3 rounded-xl border p-4 text-left transition-all duration-200 hover:border-border-emphasis hover:shadow-[0_0_12px_rgba(255,255,255,0.02)] focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-[var(--color-border-emphasis)] ${
+        baseStriped ? 'bg-surface-raised/10' : 'bg-transparent'
+      } ${smStriped ? 'sm:bg-surface-raised/10' : 'sm:bg-transparent'} ${
+        xlStriped ? 'xl:bg-surface-raised/10' : 'xl:bg-transparent'
+      } ${
         plugin.isInstalled ? 'border-l-2 border-border border-l-emerald-500/35' : 'border-border'
       }`}
     >
+      {plugin.source === 'official' && (
+        <div className="pointer-events-none absolute -left-[1px] -top-[1px] size-16 overflow-hidden">
+          <div className="absolute left-[-24px] top-[4px] w-[80px] rotate-[-45deg] bg-blue-500/90 text-center text-[9px] font-semibold leading-[18px] text-white shadow-sm">
+            Official
+          </div>
+        </div>
+      )}
+
       {/* Header: name + status/meta */}
       <div className="flex items-start justify-between gap-2">
         <div className="min-w-0 space-y-1">
diff --git a/src/renderer/components/extensions/plugins/PluginDetailDialog.tsx b/src/renderer/components/extensions/plugins/PluginDetailDialog.tsx
--- a/src/renderer/components/extensions/plugins/PluginDetailDialog.tsx
+++ b/src/renderer/components/extensions/plugins/PluginDetailDialog.tsx
@@ -32,6 +32,7 @@ import { ExternalLink, Loader2, Mail } from 'lucide-react';
 
 import { InstallButton } from '../common/InstallButton';
 import { InstallCountBadge } from '../common/InstallCountBadge';
+import { SourceBadge } from '../common/SourceBadge';
 
 import { MarkdownViewer } from '@renderer/components/chat/viewers/MarkdownViewer';
 
@@ -87,14 +88,17 @@ export const PluginDetailDialog = ({
               <DialogTitle className="truncate">{plugin.name}</DialogTitle>
               <DialogDescription className="mt-1">{plugin.description}</DialogDescription>
             </div>
-            {plugin.isInstalled && (
-              <Badge
-                className="shrink-0 border-emerald-500/30 bg-emerald-500/10 text-emerald-400"
-                variant="outline"
-              >
-                Installed
-              </Badge>
-            )}
+            <div className="flex shrink-0 items-center gap-1.5">
+              {plugin.isInstalled && (
+                <Badge
+                  className="shrink-0 border-emerald-500/30 bg-emerald-500/10 text-emerald-400"
+                  variant="outline"
+                >
+                  Installed
+                </Badge>
+              )}
+              <SourceBadge source={plugin.source} />
+            </div>
           </div>
         </DialogHeader>
 
@@ -108,6 +112,10 @@ export const PluginDetailDialog = ({
             <span className="text-text-muted">Category</span>
             <p className="capitalize text-text">{category}</p>
           </div>
+          <div>
+            <span className="text-text-muted">Source</span>
+            <p className="capitalize text-text">{plugin.source}</p>
+          </div>
           {plugin.version && (
             <div>
               <span className="text-text-muted">Version</span>
diff --git a/src/renderer/components/extensions/plugins/PluginsPanel.tsx b/src/renderer/components/extensions/plugins/PluginsPanel.tsx
--- a/src/renderer/components/extensions/plugins/PluginsPanel.tsx
+++ b/src/renderer/components/extensions/plugins/PluginsPanel.tsx
@@ -359,8 +359,13 @@ export const PluginsPanel = ({
 
       {!loading && !error && filtered.length > 0 && (
         <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
-          {filtered.map((plugin) => (
-            <PluginCard key={plugin.pluginId} plugin={plugin} onClick={setSelectedPluginId} />
+          {filtered.map((plugin, index) => (
+            <PluginCard
+              key={plugin.pluginId}
+              plugin={plugin}
+              index={index}
+              onClick={setSelectedPluginId}
+            />
           ))}
         </div>
       )}
diff --git a/src/renderer/components/team/TeamDetailView.tsx b/src/renderer/components/team/TeamDetailView.tsx
--- a/src/renderer/components/team/TeamDetailView.tsx
+++ b/src/renderer/components/team/TeamDetailView.tsx
@@ -26,6 +26,10 @@ import { formatProjectPath } from '@renderer/utils/pathDisplay';
 import { buildTaskCountsByOwner, normalizePath } from '@renderer/utils/pathNormalize';
 import { nameColorSet } from '@renderer/utils/projectColor';
 import { resolveProjectIdByPath } from '@renderer/utils/projectLookup';
+import {
+  buildTaskChangeRequestOptions,
+  type TaskChangeRequestOptions,
+} from '@renderer/utils/taskChangeRequest';
 import { stripAgentBlocks } from '@shared/constants/agentBlocks';
 import { deriveTaskDisplayId, formatTaskDisplayLabel } from '@shared/utils/taskIdentity';
 import {
@@ -175,6 +179,7 @@ export const TeamDetailView = ({ teamName }: TeamDetailViewProps): React.JSX.Ele
     memberName?: string;
     taskId?: string;
     initialFilePath?: string;
+    taskChangeRequestOptions?: TaskChangeRequestOptions;
   }>({ open: false, mode: 'task' });
 
   // Active teams for conflict warning in LaunchTeamDialog
@@ -723,6 +728,7 @@ export const TeamDetailView = ({ teamName }: TeamDetailViewProps): React.JSX.Ele
       mode: 'task',
       taskId: pendingReviewRequest.taskId,
       initialFilePath: pendingReviewRequest.filePath,
+      taskChangeRequestOptions: pendingReviewRequest.requestOptions,
     });
     if (pendingReviewRequest.filePath) {
       selectReviewFile(pendingReviewRequest.filePath);
@@ -763,18 +769,34 @@ export const TeamDetailView = ({ teamName }: TeamDetailViewProps): React.JSX.Ele
     [teamName, softDeleteTask]
   );
 
-  const handleViewChanges = useCallback((taskId: string) => {
-    setReviewDialogState({ open: true, mode: 'task', taskId });
-  }, []);
+  const handleViewChanges = useCallback(
+    (taskId: string) => {
+      const task = taskMap.get(taskId);
+      setReviewDialogState({
+        open: true,
+        mode: 'task',
+        taskId,
+        taskChangeRequestOptions: task ? buildTaskChangeRequestOptions(task) : {},
+      });
+    },
+    [taskMap]
+  );
 
   const handleViewChangesForFile = useCallback(
     (taskId: string, filePath?: string) => {
-      setReviewDialogState({ open: true, mode: 'task', taskId });
+      const task = taskMap.get(taskId);
+      setReviewDialogState({
+        open: true,
+        mode: 'task',
+        taskId,
+        initialFilePath: filePath,
+        taskChangeRequestOptions: task ? buildTaskChangeRequestOptions(task) : {},
+      });
       if (filePath) {
         selectReviewFile(filePath);
       }
     },
-    [selectReviewFile]
+    [selectReviewFile, taskMap]
   );
 
   const handleDeleteTeam = useCallback((): void => {
@@ -1873,14 +1895,17 @@ export const TeamDetailView = ({ teamName }: TeamDetailViewProps): React.JSX.Ele
               setReviewDialogState((prev) => ({
                 ...prev,
                 open,
-                ...(open ? {} : { initialFilePath: undefined }),
+                ...(open
+                  ? {}
+                  : { initialFilePath: undefined, taskChangeRequestOptions: undefined }),
               }))
             }
             teamName={teamName}
             mode={reviewDialogState.mode}
             memberName={reviewDialogState.memberName}
             taskId={reviewDialogState.taskId}
             initialFilePath={reviewDialogState.initialFilePath}
+            taskChangeRequestOptions={reviewDialogState.taskChangeRequestOptions}
             projectPath={data.config.projectPath}
             onEditorAction={handleEditorAction}
           />
diff --git a/src/renderer/components/team/dialogs/GlobalTaskDetailDialog.tsx b/src/renderer/components/team/dialogs/GlobalTaskDetailDialog.tsx
--- a/src/renderer/components/team/dialogs/GlobalTaskDetailDialog.tsx
+++ b/src/renderer/components/team/dialogs/GlobalTaskDetailDialog.tsx
@@ -1,6 +1,7 @@
 import { useCallback, useEffect, useMemo } from 'react';
 
 import { useStore } from '@renderer/store';
+import { buildTaskChangeRequestOptions } from '@renderer/utils/taskChangeRequest';
 import { ExternalLink } from 'lucide-react';
 import { useShallow } from 'zustand/react/shallow';
 
@@ -99,11 +100,17 @@ export const GlobalTaskDetailDialog = (): React.JSX.Element | null => {
 
   const handleViewChanges = useCallback(
     (viewTaskId: string, filePath?: string) => {
-      setPendingReviewRequest({ taskId: viewTaskId, filePath });
+      const targetTask = taskMap.get(viewTaskId);
+      if (!targetTask) return;
+      setPendingReviewRequest({
+        taskId: viewTaskId,
+        filePath,
+        requestOptions: buildTaskChangeRequestOptions(targetTask),
+      });
       closeGlobalTaskDetail();
       openTeamTab(teamName);
     },
-    [closeGlobalTaskDetail, openTeamTab, setPendingReviewRequest, teamName]
+    [closeGlobalTaskDetail, openTeamTab, setPendingReviewRequest, taskMap, teamName]
   );
 
   if (!globalTaskDetail) return null;
diff --git a/src/renderer/components/team/dialogs/TaskDetailDialog.tsx b/src/renderer/components/team/dialogs/TaskDetailDialog.tsx
--- a/src/renderer/components/team/dialogs/TaskDetailDialog.tsx
+++ b/src/renderer/components/team/dialogs/TaskDetailDialog.tsx
@@ -34,6 +34,7 @@ import {
   TASK_STATUS_LABELS,
   TASK_STATUS_STYLES,
 } from '@renderer/utils/memberHelpers';
+import { buildTaskChangeRequestOptions, deriveTaskSince } from '@renderer/utils/taskChangeRequest';
 import { getTaskKanbanColumn } from '@shared/utils/reviewState';
 import { deriveTaskDisplayId, formatTaskDisplayLabel } from '@shared/utils/taskIdentity';
 import { formatDistanceToNow } from 'date-fns';
@@ -74,29 +75,6 @@ import type {
   TeamTaskWithKanban,
 } from '@shared/types';
 
-const TASK_SINCE_GRACE_MS = 2 * 60 * 1000;
-
-function deriveTaskSince(task: TeamTaskWithKanban | null): string | undefined {
-  if (!task) return undefined;
-  const sources: string[] = [];
-  if (task.createdAt) sources.push(task.createdAt);
-  if (Array.isArray(task.workIntervals)) {
-    for (const i of task.workIntervals) {
-      if (i.startedAt) sources.push(i.startedAt);
-    }
-  }
-  if (Array.isArray(task.historyEvents)) {
-    for (const e of task.historyEvents) {
-      if (e.timestamp) sources.push(e.timestamp);
-    }
-  }
-  if (sources.length === 0) return undefined;
-  const earliest = sources.reduce((a, b) => (a < b ? a : b));
-  const d = new Date(earliest);
-  d.setTime(d.getTime() - TASK_SINCE_GRACE_MS);
-  return d.toISOString();
-}
-
 interface TaskDetailDialogProps {
   open: boolean;
   loading?: boolean;
@@ -136,6 +114,7 @@ export const TaskDetailDialog = ({
   const colorMap = useMemo(() => buildMemberColorMap(members), [members]);
   const currentTask = task ? (taskMap.get(task.id) ?? task) : null;
   const updateTaskFields = useStore((s) => s.updateTaskFields);
+  const recordTaskHasChanges = useStore((s) => s.recordTaskHasChanges);
 
   const [logsRefreshing, setLogsRefreshing] = useState(false);
   const [executionPreviewOnline, setExecutionPreviewOnline] = useState(false);
@@ -289,19 +268,39 @@ export const TaskDetailDialog = ({
   // Lazy-load task changes when dialog is open and task is completed
   const isTaskCompleted = currentTask?.status === 'completed';
   const taskSince = useMemo(() => deriveTaskSince(currentTask), [currentTask]);
+  const taskChangeRequestOptions = useMemo(
+    () => (currentTask ? buildTaskChangeRequestOptions(currentTask) : null),
+    [currentTask]
+  );
+  const taskChangeSummaryOptions = useMemo(
+    () =>
+      currentTask
+        ? buildTaskChangeRequestOptions(currentTask, {
+            since: taskSince,
+            summaryOnly: true,
+          })
+        : null,
+    [currentTask, taskSince]
+  );
   const setTaskNeedsClarification = useStore((s) => s.setTaskNeedsClarification);
 
   const loadTaskChangeSummary = useCallback(async (): Promise<FileChangeSummary[] | null> => {
-    if (!currentTask || variant !== 'team' || !isTaskCompleted || !onViewChanges) return null;
-    const data = await api.review.getTaskChanges(teamName, currentTask.id, {
-      owner: currentTask.owner,
-      status: currentTask.status,
-      intervals: currentTask.workIntervals,
-      since: taskSince,
-      summaryOnly: true,
-    });
+    if (
+      !currentTask ||
+      !taskChangeSummaryOptions ||
+      variant !== 'team' ||
+      !isTaskCompleted ||
+      !onViewChanges
+    ) {
+      return null;
+    }
+    const data = await api.review.getTaskChanges(
+      teamName,
+      currentTask.id,
+      taskChangeSummaryOptions
+    );
     return data.files;
-  }, [currentTask, isTaskCompleted, onViewChanges, teamName, taskSince, variant]);
+  }, [currentTask, isTaskCompleted, onViewChanges, taskChangeSummaryOptions, teamName, variant]);
 
   useEffect(() => {
     if (variant !== 'team') return;
@@ -312,7 +311,17 @@ export const TaskDetailDialog = ({
     setTaskChangesError(null);
     void loadTaskChangeSummary()
       .then((files) => {
-        if (!cancelled) setTaskChangesFiles(files ?? null);
+        if (!cancelled) {
+          setTaskChangesFiles(files ?? null);
+          if (currentTask && taskChangeRequestOptions) {
+            recordTaskHasChanges(
+              teamName,
+              currentTask.id,
+              taskChangeRequestOptions,
+              !!files?.length
+            );
+          }
+        }
       })
       .catch((error) => {
         if (!cancelled) {
@@ -346,15 +355,29 @@ export const TaskDetailDialog = ({
     setTaskChangesLoading(true);
     setTaskChangesError(null);
     void loadTaskChangeSummary()
-      .then((files) => setTaskChangesFiles(files ?? null))
+      .then((files) => {
+        setTaskChangesFiles(files ?? null);
+        if (currentTask && taskChangeRequestOptions) {
+          recordTaskHasChanges(teamName, currentTask.id, taskChangeRequestOptions, !!files?.length);
+        }
+      })
       .catch((error) => {
         setTaskChangesFiles(null);
         setTaskChangesError(
           error instanceof Error ? error.message : 'Failed to load task changes summary'
         );
       })
       .finally(() => setTaskChangesLoading(false));
-  }, [currentTask, isTaskCompleted, onViewChanges, loadTaskChangeSummary, variant]);
+  }, [
+    currentTask,
+    isTaskCompleted,
+    onViewChanges,
+    loadTaskChangeSummary,
+    recordTaskHasChanges,
+    taskChangeRequestOptions,
+    teamName,
+    variant,
+  ]);
 
   const handleDependencyClick = (taskId: string): void => {
     handleClose();
diff --git a/src/renderer/components/team/kanban/KanbanGridLayout.tsx b/src/renderer/components/team/kanban/KanbanGridLayout.tsx
--- a/src/renderer/components/team/kanban/KanbanGridLayout.tsx
+++ b/src/renderer/components/team/kanban/KanbanGridLayout.tsx
@@ -101,7 +101,7 @@ export const KanbanGridLayout = ({
 }: KanbanGridLayoutProps): React.JSX.Element => {
   const columnMap = useMemo(() => new Map(columns.map((column) => [column.id, column])), [columns]);
   const visibleColumnIds = useMemo(() => columns.map((column) => column.id), [columns]);
-  const { visibleItems, applyVisibleItems } = usePersistedGridLayout({
+  const { visibleItems, applyVisibleItems, isLoaded } = usePersistedGridLayout({
     scopeKey: `${GRID_SCOPE_PREFIX}:${teamName}`,
     allItemIds: allColumnIds,
     visibleItemIds: visibleColumnIds,
@@ -115,8 +115,9 @@ export const KanbanGridLayout = ({
   );
 
   useEffect(() => {
+    if (!isLoaded) return;
     setRenderLayout(visibleItems.map(toReactGridLayoutItem));
-  }, [visibleItems]);
+  }, [isLoaded, visibleItems]);
 
   const applyReactGridLayout = useCallback(
     (layout: Layout, options?: { persist?: boolean }) => {
@@ -128,6 +129,10 @@ export const KanbanGridLayout = ({
     [applyVisibleItems]
   );
 
+  if (!isLoaded) {
+    return <div className="min-h-[640px] p-1.5" />;
+  }
+
   return (
     <div className="p-1.5">
       <WidthAwareGridLayout
diff --git a/src/renderer/components/team/kanban/KanbanTaskCard.tsx b/src/renderer/components/team/kanban/KanbanTaskCard.tsx
--- a/src/renderer/components/team/kanban/KanbanTaskCard.tsx
+++ b/src/renderer/components/team/kanban/KanbanTaskCard.tsx
@@ -8,6 +8,10 @@ import { Tooltip, TooltipContent, TooltipTrigger } from '@renderer/components/ui
 import { useUnreadCommentCount } from '@renderer/hooks/useUnreadCommentCount';
 import { useStore } from '@renderer/store';
 import { REVIEW_STATE_DISPLAY, buildMemberColorMap } from '@renderer/utils/memberHelpers';
+import {
+  buildTaskChangePresenceKey,
+  buildTaskChangeRequestOptions,
+} from '@renderer/utils/taskChangeRequest';
 import { deriveTaskDisplayId, formatTaskDisplayLabel } from '@shared/utils/taskIdentity';
 import {
   ArrowLeftFromLine,
@@ -200,15 +204,27 @@ export const KanbanTaskCard = ({
   // Lazy-check if task has file changes (only for done/review/approved columns)
   const showChangesColumn =
     (columnId === 'done' || columnId === 'review' || columnId === 'approved') && !!onViewChanges;
-  const cacheKey = `${teamName}:${task.id}`;
+  const taskChangeRequestOptions = useMemo(() => buildTaskChangeRequestOptions(task), [task]);
+  const cacheKey = useMemo(
+    () => buildTaskChangePresenceKey(teamName, task.id, taskChangeRequestOptions),
+    [teamName, task.id, taskChangeRequestOptions]
+  );
   const taskHasChanges = useStore((s) => s.taskHasChanges[cacheKey]);
   const checkTaskHasChanges = useStore((s) => s.checkTaskHasChanges);
 
   useEffect(() => {
     if (showChangesColumn && task.status === 'completed' && taskHasChanges !== true) {
-      void checkTaskHasChanges(teamName, task.id);
+      void checkTaskHasChanges(teamName, task.id, taskChangeRequestOptions);
     }
-  }, [showChangesColumn, task.status, task.id, teamName, taskHasChanges, checkTaskHasChanges]);
+  }, [
+    showChangesColumn,
+    task.status,
+    task.id,
+    teamName,
+    taskHasChanges,
+    checkTaskHasChanges,
+    taskChangeRequestOptions,
+  ]);
 
   const isReviewManual = columnId === 'review' && !hasReviewers;
   const multiButton =
diff --git a/src/renderer/components/team/review/ChangeReviewDialog.tsx b/src/renderer/components/team/review/ChangeReviewDialog.tsx
--- a/src/renderer/components/team/review/ChangeReviewDialog.tsx
+++ b/src/renderer/components/team/review/ChangeReviewDialog.tsx
@@ -10,6 +10,7 @@ import { useViewedFiles } from '@renderer/hooks/useViewedFiles';
 import { cn } from '@renderer/lib/utils';
 import { useStore } from '@renderer/store';
 import { getFileHunkCount, REVIEW_INSTANT_APPLY } from '@renderer/store/slices/changeReviewSlice';
+import { type TaskChangeRequestOptions } from '@renderer/utils/taskChangeRequest';
 import { buildSelectionAction } from '@renderer/utils/buildSelectionAction';
 import { buildSelectionInfo, SELECTION_DEBOUNCE_MS } from '@renderer/utils/codemirrorSelectionInfo';
 import { sortItemsAsTree } from '@renderer/utils/fileTreeBuilder';
@@ -47,6 +48,7 @@ interface ChangeReviewDialogProps {
   memberName?: string;
   taskId?: string;
   initialFilePath?: string;
+  taskChangeRequestOptions?: TaskChangeRequestOptions;
   projectPath?: string;
   onEditorAction?: (action: EditorSelectionAction) => void;
 }
@@ -63,6 +65,7 @@ export const ChangeReviewDialog = ({
   memberName,
   taskId,
   initialFilePath,
+  taskChangeRequestOptions,
   projectPath,
   onEditorAction,
 }: ChangeReviewDialogProps): React.ReactElement | null => {
@@ -692,7 +695,7 @@ export const ChangeReviewDialog = ({
     if (mode === 'agent' && memberName) {
       void fetchAgentChanges(teamName, memberName);
     } else if (mode === 'task' && taskId) {
-      void fetchTaskChanges(teamName, taskId);
+      void fetchTaskChanges(teamName, taskId, taskChangeRequestOptions ?? {});
     }
 
     // On close — clear only volatile cache, keep decisions in store
@@ -703,6 +706,7 @@ export const ChangeReviewDialog = ({
     teamName,
     memberName,
     taskId,
+    taskChangeRequestOptions,
     decisionScopeKey,
     fetchAgentChanges,
     fetchTaskChanges,
diff --git a/src/renderer/index.css b/src/renderer/index.css
--- a/src/renderer/index.css
+++ b/src/renderer/index.css
@@ -318,6 +318,7 @@
   width: 36px;
   height: 6px;
   transform: translateX(-50%);
+  cursor: ns-resize;
 }
 
 .kanban-grid-resize-handle-n {
@@ -334,6 +335,7 @@
   width: 6px;
   height: 36px;
   transform: translateY(-50%);
+  cursor: ew-resize;
 }
 
 .kanban-grid-resize-handle-e {
@@ -355,21 +357,25 @@
 .kanban-grid-resize-handle-ne {
   top: -4px;
   right: -4px;
+  cursor: nesw-resize;
 }
 
 .kanban-grid-resize-handle-nw {
   top: -4px;
   left: -4px;
+  cursor: nwse-resize;
 }
 
 .kanban-grid-resize-handle-se {
   right: -4px;
   bottom: -4px;
+  cursor: nwse-resize;
 }
 
 .kanban-grid-resize-handle-sw {
   left: -4px;
   bottom: -4px;
+  cursor: nesw-resize;
 }
 
 /* File icon glow — halo so dark icons stay visible on dark backgrounds */
diff --git a/src/renderer/services/layout-system/BrowserGridLayoutRepository.ts b/src/renderer/services/layout-system/BrowserGridLayoutRepository.ts
--- a/src/renderer/services/layout-system/BrowserGridLayoutRepository.ts
+++ b/src/renderer/services/layout-system/BrowserGridLayoutRepository.ts
@@ -37,26 +37,36 @@ function removeLocalStorage(key: string): void {
   }
 }
 
+function pickNewestState(
+  ...states: Array<PersistedGridLayoutState | null | undefined>
+): PersistedGridLayoutState | null {
+  return states.reduce<PersistedGridLayoutState | null>((latest, current) => {
+    if (!current) return latest;
+    if (!latest) return current;
+    return current.updatedAt >= latest.updatedAt ? current : latest;
+  }, null);
+}
+
 export class BrowserGridLayoutRepository implements GridLayoutRepository<PersistedGridLayoutState> {
   private idbUnavailable = false;
   private readonly fallbackStore = new Map<string, PersistedGridLayoutState>();
 
   async load(scopeKey: string): Promise<PersistedGridLayoutState | null> {
     const key = storageKey(scopeKey);
+    const memoryState = this.fallbackStore.get(key) ?? null;
+    const localState = readLocalStorage(key);
+    let idbState: PersistedGridLayoutState | null = null;
 
     if (!this.idbUnavailable) {
       try {
         const stored = await get<unknown>(key);
-        const sanitized = sanitizePersistedGridLayoutState(stored);
-        if (sanitized) {
-          return sanitized;
-        }
+        idbState = sanitizePersistedGridLayoutState(stored);
       } catch {
         this.idbUnavailable = true;
       }
     }
 
-    return this.fallbackStore.get(key) ?? readLocalStorage(key);
+    return pickNewestState(memoryState, localState, idbState);
   }
 
   async save(scopeKey: string, state: PersistedGridLayoutState): Promise<void> {
diff --git a/src/renderer/services/layout-system/gridLayoutSchema.ts b/src/renderer/services/layout-system/gridLayoutSchema.ts
--- a/src/renderer/services/layout-system/gridLayoutSchema.ts
+++ b/src/renderer/services/layout-system/gridLayoutSchema.ts
@@ -120,41 +120,18 @@ export function projectVisibleGridLayoutItems(
   cols: number
 ): PersistedGridLayoutItem[] {
   const visibleIdSet = new Set(visibleIds);
-  const visibleItems = allItems
+  return allItems
     .filter((item) => visibleIdSet.has(item.id))
+    .map((item) => {
+      const width = Math.min(Math.max(1, item.w), cols);
+      const maxX = Math.max(0, cols - width);
+
+      return {
+        ...item,
+        w: width,
+        x: Math.min(Math.max(0, item.x), maxX),
+        y: Math.max(0, item.y),
+      };
+    })
     .sort((a, b) => (a.y === b.y ? a.x - b.x : a.y - b.y));
-
-  if (visibleItems.length === 0) {
-    return [];
-  }
-
-  const fillWidth =
-    visibleItems.length <= 3 ? Math.max(1, Math.floor(cols / visibleItems.length)) : 0;
-  const projected: PersistedGridLayoutItem[] = [];
-  let currentX = 0;
-  let currentY = 0;
-  let rowHeight = 0;
-
-  for (const item of visibleItems) {
-    const nextWidth =
-      visibleItems.length === 1 ? cols : Math.min(cols, Math.max(item.w, fillWidth || item.w));
-
-    if (currentX + nextWidth > cols) {
-      currentX = 0;
-      currentY += rowHeight;
-      rowHeight = 0;
-    }
-
-    projected.push({
-      ...item,
-      x: currentX,
-      y: currentY,
-      w: nextWidth,
-    });
-
-    currentX += nextWidth;
-    rowHeight = Math.max(rowHeight, item.h);
-  }
-
-  return projected;
 }
diff --git a/src/renderer/store/slices/changeReviewSlice.ts b/src/renderer/store/slices/changeReviewSlice.ts
--- a/src/renderer/store/slices/changeReviewSlice.ts
+++ b/src/renderer/store/slices/changeReviewSlice.ts
@@ -1,4 +1,8 @@
 import { api } from '@renderer/api';
+import {
+  buildTaskChangePresenceKey,
+  type TaskChangeRequestOptions,
+} from '@renderer/utils/taskChangeRequest';
 import { computeDiffContextHash } from '@shared/utils/diffContextHash';
 import { createLogger } from '@shared/utils/logger';
 import { structuredPatch } from 'diff';
@@ -8,6 +12,7 @@ const taskChangesCheckInFlight = new Set<string>();
 /** Negative results cached with timestamp — recheck after 30s */
 const taskChangesNegativeCache = new Map<string, number>();
 const NEGATIVE_CACHE_TTL = 30_000;
+let latestTaskChangesRequestToken = 0;
 
 /** Debounce timer for persisting decisions to disk */
 let persistDebounceTimer: ReturnType<typeof setTimeout> | null = null;
@@ -78,12 +83,22 @@ export interface ChangeReviewSlice {
   // Editable diff state
   editedContents: Record<string, string>;
 
-  /** Cache: "teamName:taskId" → true/false (has file changes) */
+  /** Cache: "teamName:taskId:signature" → true/false (has file changes) */
   taskHasChanges: Record<string, boolean>;
 
   // Phase 1 actions
   fetchAgentChanges: (teamName: string, memberName: string) => Promise<void>;
-  fetchTaskChanges: (teamName: string, taskId: string) => Promise<void>;
+  fetchTaskChanges: (
+    teamName: string,
+    taskId: string,
+    options: TaskChangeRequestOptions
+  ) => Promise<void>;
+  recordTaskHasChanges: (
+    teamName: string,
+    taskId: string,
+    options: TaskChangeRequestOptions,
+    hasChanges: boolean
+  ) => void;
   selectReviewFile: (filePath: string | null) => void;
   clearChangeReview: () => void;
   clearChangeReviewCache: () => void;
@@ -145,7 +160,11 @@ export interface ChangeReviewSlice {
   saveEditedFile: (filePath: string, projectPath?: string) => Promise<void>;
 
   // Task change availability
-  checkTaskHasChanges: (teamName: string, taskId: string) => Promise<void>;
+  checkTaskHasChanges: (
+    teamName: string,
+    taskId: string,
+    options: TaskChangeRequestOptions
+  ) => Promise<void>;
 }
 
 /**
@@ -278,18 +297,43 @@ export const createChangeReviewSlice: StateCreator<AppState, [], [], ChangeRevie
     }
   },
 
-  fetchTaskChanges: async (teamName: string, taskId: string) => {
+  recordTaskHasChanges: (
+    teamName: string,
+    taskId: string,
+    options: TaskChangeRequestOptions,
+    hasChanges: boolean
+  ) => {
+    const cacheKey = buildTaskChangePresenceKey(teamName, taskId, options);
+    set((s) => ({
+      taskHasChanges: { ...s.taskHasChanges, [cacheKey]: hasChanges },
+    }));
+    if (hasChanges) {
+      taskChangesNegativeCache.delete(cacheKey);
+    } else {
+      taskChangesNegativeCache.set(cacheKey, Date.now());
+    }
+  },
+
+  fetchTaskChanges: async (teamName: string, taskId: string, options: TaskChangeRequestOptions) => {
+    const requestToken = ++latestTaskChangesRequestToken;
     set({ changeSetLoading: true, changeSetError: null });
     try {
-      const data = await api.review.getTaskChanges(teamName, taskId);
-      const cacheKey = `${teamName}:${taskId}`;
+      const data = await api.review.getTaskChanges(teamName, taskId, options);
+      if (requestToken !== latestTaskChangesRequestToken) return;
+      const cacheKey = buildTaskChangePresenceKey(teamName, taskId, options);
       set((s) => ({
         activeChangeSet: data,
         changeSetLoading: false,
         selectedReviewFilePath: data.files[0]?.filePath ?? null,
         taskHasChanges: { ...s.taskHasChanges, [cacheKey]: data.files.length > 0 },
       }));
+      if (data.files.length > 0) {
+        taskChangesNegativeCache.delete(cacheKey);
+      } else {
+        taskChangesNegativeCache.set(cacheKey, Date.now());
+      }
     } catch (error) {
+      if (requestToken !== latestTaskChangesRequestToken) return;
       const message = error instanceof Error ? error.message : 'Failed to fetch task changes';
       logger.error('fetchTaskChanges error:', message);
       set({ changeSetError: message, changeSetLoading: false });
@@ -301,6 +345,7 @@ export const createChangeReviewSlice: StateCreator<AppState, [], [], ChangeRevie
   },
 
   clearChangeReview: () => {
+    latestTaskChangesRequestToken++;
     set({
       activeChangeSet: null,
       changeSetLoading: false,
@@ -320,6 +365,7 @@ export const createChangeReviewSlice: StateCreator<AppState, [], [], ChangeRevie
   },
 
   clearChangeReviewCache: () => {
+    latestTaskChangesRequestToken++;
     set({
       activeChangeSet: null,
       changeSetLoading: false,
@@ -337,6 +383,7 @@ export const createChangeReviewSlice: StateCreator<AppState, [], [], ChangeRevie
   },
 
   resetAllReviewState: () => {
+    latestTaskChangesRequestToken++;
     set({
       activeChangeSet: null,
       changeSetLoading: false,
@@ -978,8 +1025,12 @@ export const createChangeReviewSlice: StateCreator<AppState, [], [], ChangeRevie
     }
   },
 
-  checkTaskHasChanges: async (teamName: string, taskId: string) => {
-    const cacheKey = `${teamName}:${taskId}`;
+  checkTaskHasChanges: async (
+    teamName: string,
+    taskId: string,
+    options: TaskChangeRequestOptions
+  ) => {
+    const cacheKey = buildTaskChangePresenceKey(teamName, taskId, options);
     // Positive results are final — no need to recheck
     if (get().taskHasChanges[cacheKey] === true) return;
     // Prevent duplicate in-flight requests
@@ -990,18 +1041,23 @@ export const createChangeReviewSlice: StateCreator<AppState, [], [], ChangeRevie
 
     taskChangesCheckInFlight.add(cacheKey);
     try {
-      const data = await api.review.getTaskChanges(teamName, taskId);
+      const data = await api.review.getTaskChanges(teamName, taskId, {
+        ...options,
+        summaryOnly: true,
+      });
       if (data.files.length > 0) {
         set((s) => ({
           taskHasChanges: { ...s.taskHasChanges, [cacheKey]: true },
         }));
         taskChangesNegativeCache.delete(cacheKey);
       } else {
+        set((s) => ({
+          taskHasChanges: { ...s.taskHasChanges, [cacheKey]: false },
+        }));
         taskChangesNegativeCache.set(cacheKey, Date.now());
       }
     } catch {
-      // Don't cache errors in store — allow retry when session data appears later
-      taskChangesNegativeCache.set(cacheKey, Date.now());
+      // Allow immediate retry after transient failures (race, file lock, late logs).
     } finally {
       taskChangesCheckInFlight.delete(cacheKey);
     }
diff --git a/src/renderer/store/slices/teamSlice.ts b/src/renderer/store/slices/teamSlice.ts
--- a/src/renderer/store/slices/teamSlice.ts
+++ b/src/renderer/store/slices/teamSlice.ts
@@ -1,4 +1,5 @@
 import { api } from '@renderer/api';
+import type { TaskChangeRequestOptions } from '@renderer/utils/taskChangeRequest';
 import { normalizePath } from '@renderer/utils/pathNormalize';
 import { IpcError, unwrapIpc } from '@renderer/utils/unwrapIpc';
 import { createLogger } from '@shared/utils/logger';
@@ -277,8 +278,14 @@ export interface TeamSlice {
   openMemberProfile: (memberName: string) => void;
   closeMemberProfile: () => void;
   /** Set by GlobalTaskDetailDialog to signal TeamDetailView to open ChangeReviewDialog */
-  pendingReviewRequest: { taskId: string; filePath?: string } | null;
-  setPendingReviewRequest: (req: { taskId: string; filePath?: string } | null) => void;
+  pendingReviewRequest: {
+    taskId: string;
+    filePath?: string;
+    requestOptions: TaskChangeRequestOptions;
+  } | null;
+  setPendingReviewRequest: (
+    req: { taskId: string; filePath?: string; requestOptions: TaskChangeRequestOptions } | null
+  ) => void;
   selectedTeamName: string | null;
   selectedTeamData: TeamData | null;
   selectedTeamLoading: boolean;
diff --git a/src/renderer/utils/taskChangeRequest.ts b/src/renderer/utils/taskChangeRequest.ts
new file mode 100644
--- /dev/null
+++ b/src/renderer/utils/taskChangeRequest.ts
@@ -0,0 +1,97 @@
+import type { ReviewAPI } from '@shared/types/api';
+import type { TeamTaskWithKanban } from '@shared/types/team';
+
+const TASK_SINCE_GRACE_MS = 2 * 60 * 1000;
+
+export type TaskChangeRequestOptions = NonNullable<Parameters<ReviewAPI['getTaskChanges']>[2]>;
+
+export interface TaskChangeContext {
+  taskId: string;
+  requestOptions: TaskChangeRequestOptions;
+  initialFilePath?: string;
+}
+
+type TaskChangeTaskLike = Pick<
+  TeamTaskWithKanban,
+  'id' | 'owner' | 'status' | 'createdAt' | 'updatedAt' | 'workIntervals' | 'historyEvents'
+>;
+
+export function deriveTaskSince(task: TaskChangeTaskLike | null): string | undefined {
+  if (!task) return undefined;
+
+  const sources: string[] = [];
+  if (task.createdAt) sources.push(task.createdAt);
+  if (Array.isArray(task.workIntervals)) {
+    for (const interval of task.workIntervals) {
+      if (interval.startedAt) sources.push(interval.startedAt);
+    }
+  }
+  if (Array.isArray(task.historyEvents)) {
+    for (const event of task.historyEvents) {
+      if (event.timestamp) sources.push(event.timestamp);
+    }
+  }
+  if (sources.length === 0) return undefined;
+
+  const earliest = sources.reduce((a, b) => (a < b ? a : b));
+  const date = new Date(earliest);
+  date.setTime(date.getTime() - TASK_SINCE_GRACE_MS);
+  return date.toISOString();
+}
+
+export function buildTaskChangeRequestOptions(
+  task: TaskChangeTaskLike,
+  overrides?: Partial<TaskChangeRequestOptions>
+): TaskChangeRequestOptions {
+  const options: TaskChangeRequestOptions = {
+    owner: task.owner,
+    status: task.status,
+    intervals: task.workIntervals,
+    since: deriveTaskSince(task),
+  };
+
+  return {
+    ...options,
+    ...overrides,
+  };
+}
+
+export function buildTaskChangeContext(
+  task: TaskChangeTaskLike,
+  input?: { initialFilePath?: string; summaryOnly?: boolean }
+): TaskChangeContext {
+  return {
+    taskId: task.id,
+    requestOptions: buildTaskChangeRequestOptions(task, {
+      summaryOnly: input?.summaryOnly,
+    }),
+    initialFilePath: input?.initialFilePath,
+  };
+}
+
+export function buildTaskChangeSignature(options: TaskChangeRequestOptions): string {
+  const owner = typeof options.owner === 'string' ? options.owner.trim() : '';
+  const status = typeof options.status === 'string' ? options.status.trim() : '';
+  const since = typeof options.since === 'string' ? options.since : '';
+  const intervals = Array.isArray(options.intervals)
+    ? options.intervals.map((interval) => ({
+        startedAt: interval.startedAt,
+        completedAt: interval.completedAt ?? '',
+      }))
+    : [];
+
+  return JSON.stringify({
+    owner,
+    status,
+    since,
+    intervals,
+  });
+}
+
+export function buildTaskChangePresenceKey(
+  teamName: string,
+  taskId: string,
+  options: TaskChangeRequestOptions
+): string {
+  return `${teamName}:${taskId}:${buildTaskChangeSignature(options)}`;
+}
diff --git a/src/shared/types/extensions/plugin.ts b/src/shared/types/extensions/plugin.ts
--- a/src/shared/types/extensions/plugin.ts
+++ b/src/shared/types/extensions/plugin.ts
@@ -14,6 +14,7 @@ export interface PluginCatalogItem {
   name: string; // display name only
 
   // Metadata
+  source: 'official';
   description: string;
   category: string; // open-ended string, derived from marketplace.json
   author?: { name: string; email?: string };
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
