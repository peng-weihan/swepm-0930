# Kit Capability References in Cowork — Implementation Plan

## Context

Today, selecting an installed Kit (e.g. a design or GitHub expert kit) in the Cowork input expands it into its underlying Skill IDs before send. The expanded IDs are stored in `metadata.skillIds` and rendered as multiple Skill badges, so the user sees the Kit's internals rather than the Kit they chose, and follow-up turns can accidentally merge previous Kit selections.

The repo already contains a design spec for exactly this work: `specs/features/kit-capability-references/2026-05-29-kit-capability-reference-design.md`. This plan follows that spec (plus the task's extra requirements: Kit prompt context, per-turn selection scoping, and `safeUrlTransform`/`isInternalHref` exports for `kit://` links).

Goals:
- A selected Kit produces a stable display reference: `kit://<encoded-kit-id>@lobsterai-kits` with `kind: "kit"`, `source: "lobsterai-kits"`.
- Message metadata stores `kitIds`, `kitReferences`, `resolvedKitCapabilities` separately from `skillIds`; `metadata.skillIds` contains only directly-selected Skills.
- Runtime keeps working: runtime skill list = direct skills + kit-expanded skills.
- Kit/Skill selection is scoped to the current turn only.
- Rendering shows Kit badges; `kit://` links render as safe internal links.

## Files overview

New:
- `src/shared/kit/capability.ts` — shared Kit capability model (types + resolver + reference/URI builders), importable by both renderer and main.
- `src/renderer/services/kitCapability.ts` — renderer-side wrapper that adds marketplace metadata (localized names) on top of shared builders.
- `src/renderer/components/cowork/selectedKitContextPrompt.ts` — XML-style Kit capability index prompt for the current turn.
- Co-located `.test.ts` files for each of the above.
- `src/main/libs/kitCapability.ts` — main-side installed-record types + normalization for writing message metadata (thin re-export/adapter of shared module per spec).

Modified:
- `src/renderer/types/kit.ts` — `InstalledKit` becomes `{id, version, installedAt, skills: {skillIds}|null, mcpServers: unknown[], connectors: unknown[]}`.
- `src/renderer/types/cowork.ts` — `CoworkMessageMetadata` gains `kitReferences`, `resolvedKitCapabilities` (already has `kitIds`); `CoworkStartOptions`/`CoworkContinueOptions` gain kit selection fields.
- `src/renderer/types/electron.d.ts` — start/continue option types + `kits.listInstalled` return type updated to new installed record.
- `src/main/ipcHandlers/kits/handlers.ts` — install writes new record shape (with `mcpServers`/`connectors` passed through and normalized to `[]`); uninstall reads `skills.skillIds`; list returns new shape.
- `src/renderer/services/kit.ts` — `installKit` passes `mcpServers`/`connectors`; return type of `getInstalledKits` follows new `InstalledKit`.
- `src/main/main.ts` — `cowork:session:start` / `cowork:session:continue` accept kit selection, write visible metadata (`skillIds` direct-only, `kitIds`, `kitReferences`), pass runtime skill list = direct + kit-expanded to the router.
- `src/main/libs/agentEngine/types.ts` — `CoworkStartOptions`/`CoworkContinueOptions` keep `skillIds` as the runtime (expanded) list; no kit-specific runtime fields needed.
- `src/main/libs/agentEngine/openclawRuntimeAdapter.ts` — `runTurn` user-message metadata gains `kitIds`/`kitReferences` passthrough (continuation path).
- `src/renderer/components/cowork/CoworkPromptInput.tsx` — split direct skills vs kit selection; build runtime skill prompt from union; build Kit context prompt; pass both up via `onSubmit`.
- `src/renderer/components/cowork/CoworkView.tsx` — start/continue handlers compute `kitReferences`, `resolvedKitCapabilities`, runtime skill ids; temp message metadata uses direct-only `skillIds` + kit fields; always clear active kits/skills and drafts after send.
- `src/renderer/components/cowork/UserMessageItem.tsx` — render Kit badges from `metadata.kitReferences` (fallback `kitIds`), keep direct-skill badges only.
- `src/renderer/components/cowork/CoworkSessionDetail.tsx` — re-edit restores both `skillIds` and `kitIds`.
- `src/renderer/components/MarkdownContent.tsx` — allow `kit` protocol in `safeUrlTransform`; export `safeUrlTransform` and new `isInternalHref`; render `kit://` links as internal badge-style pills that don't open externally.
- `src/renderer/services/i18n.ts` — new keys (kit badge tooltip), zh + en.

## Detailed design

### 1. Shared capability model — `src/shared/kit/capability.ts`

Follow the string-literal constants rule: define a `KitReferenceKind`/`KitReferenceSource` const object.

```ts
export const KitReferenceSource = { LobsteraiKits: 'lobsterai-kits' } as const;
export type KitReferenceSource = typeof KitReferenceSource[keyof typeof KitReferenceSource];

export interface KitReference {
  kind: 'kit';            // literal in interface, per convention
  id: string;
  name?: string;
  uri: string;
  source?: KitReferenceSource;
}

export interface ResolvedKitCapabilities {
  skillIds: string[];     // de-duplicated, first-seen order
  mcpServers: unknown[];
  connectors: unknown[];
}

export interface InstalledKitSkillRecord { skillIds: string[] }
export interface InstalledKitRecord {
  id: string;
  version: string;
  installedAt: number;
  skills: InstalledKitSkillRecord | null;
  mcpServers: unknown[];
  connectors: unknown[];
}

export const KIT_URI_SCHEME = 'kit';

export function buildKitUri(kitId: string): string  // kit://<encodeURIComponent(id)>@lobsterai-kits
export function isKitUri(value: string): boolean
export function buildKitReference(kit: { id: string; name?: string }): KitReference
export function resolveSelectedKitCapabilities(
  kitIds: string[],
  installedKits: Record<string, InstalledKitRecord>,
): ResolvedKitCapabilities
```

Resolver rules (per task):
- Reads nested `skills?.skillIds`, `mcpServers`, `connectors`; normalizes null/missing `mcpServers`/`connectors` to `[]`.
- De-duplicates skill IDs preserving first-seen order across all kits.
- Skips missing/uninstalled kit IDs (for runtime capabilities) — silently, no logging per call.
- `buildKitReference` uses marketplace name when provided; URI is always `kit://<encoded>@lobsterai-kits`.

This module must be dependency-free (no Electron, no i18n) so both processes can import it. Renderer's `LocalizedText` resolution happens at the call site (marketplace name resolved to a string before calling `buildKitReference`).

### 2. Renderer service — `src/renderer/services/kitCapability.ts`

```ts
import { resolveLocalizedText } from './skill';

export function buildKitReferences(
  kitIds: string[],
  marketplaceKits: MarketplaceKit[],
): KitReference[]
```
- For each selected kit id, find marketplace metadata; resolve localized `name`; call shared `buildKitReference`.
- Missing marketplace metadata → still build a reference (id only, no name) so display reference survives; runtime capabilities for uninstalled kits are skipped by the resolver.

Also export a renderer convenience `resolveSelectedKitCapabilities(kitIds, installedKits: Record<string, InstalledKit>)` that maps renderer `InstalledKit` (new shape) onto the shared record type.

### 3. Kit context prompt — `src/renderer/components/cowork/selectedKitContextPrompt.ts`

```ts
export function buildSelectedKitContextPrompt(
  kits: Array<{
    id: string;
    name: string;
    skills: Array<{ id: string; name: string }>;
    mcpServers: Array<{ id: string; name: string; description?: string }>;
    connectors: Array<{ id: string; name: string }>;
  }>,
): string | undefined
```

Output shape (matches task exactly):
```
## Selected kits for this turn
<kit id="design">
  <name>Design</name>
  <skill id="design-critique" name="/design-critique" />
  <mcpServer id="figma" name="Figma" description="Inspect design files." />
  <connector id="github" name="GitHub" />
</kit>
```
- Returns `undefined` when no kits selected.
- No `tryAsking` examples, no `SKILL.md` content, no inline skill bodies.
- XML-escape id/name/description (reuse the `escapeXmlText` pattern from `selectedSkillRoutingPrompt.ts`; extract or duplicate locally).
- Skill names come from marketplace `skills.list` (`name` like `/design-critique`); fall back to installed skill ID for both `id` and `name` when marketplace metadata is missing.
- mcpServer/connector entries are best-effort: read `id`/`name`/`description` from unknown records when present, skip otherwise (marketplace schema is still `null`/undefined today).

### 4. Types updates

`src/renderer/types/kit.ts`:
```ts
export interface InstalledKit {
  id: string;
  version: string;
  installedAt: number;
  skills: { skillIds: string[] } | null;
  mcpServers: unknown[];
  connectors: unknown[];
}
```
(`MarketplaceKit` stays as-is; already has `mcpServers?`/`connectors?`.)

`src/renderer/types/cowork.ts` — `CoworkMessageMetadata`:
```ts
skillIds?: string[];            // direct selection only (comment updated)
kitIds?: string[];              // existing
kitReferences?: KitReference[]; // new (import from @shared)
resolvedKitCapabilities?: ResolvedKitCapabilities; // new
```
`CoworkStartOptions`/`CoworkContinueOptions` gain:
```ts
kitIds?: string[];
kitReferences?: KitReference[];
resolvedKitCapabilities?: ResolvedKitCapabilities;
```
`activeSkillIds` in these options keeps meaning "runtime list (direct + kit-expanded)" — the main process builds it; see step 6. Actually, to keep responsibilities clean, renderer keeps sending `activeSkillIds` = runtime expanded list (unchanged semantics for the runtime call) **plus** the new kit fields; main process writes metadata from the kit fields and direct skill list. To let main know which skills are direct, add `directSkillIds?: string[]` to options. Main writes `metadata.skillIds = directSkillIds` and passes `activeSkillIds` (expanded) to the runtime.

`src/main/coworkStore.ts` — `CoworkMessageMetadata` gains the same three optional fields (types imported from shared module).

### 5. Kit install/list IPC — `src/main/ipcHandlers/kits/handlers.ts`

- `InstalledKitRecord` local interface replaced by shared type from `src/shared/kit/capability.ts`.
- `kits:install` params gain `mcpServers?: unknown[]; connectors?: unknown[]` (normalized with `Array.isArray(x) ? x : []`). Persisted record:
  ```ts
  { id, version, installedAt, skills: installedSkillIds.length ? { skillIds } : null, mcpServers, connectors }
  ```
- `kits:uninstall` reads `kitRecord.skills?.skillIds ?? []` for directory deletion.
- `kits:listInstalled` unchanged shape-wise (returns the map as stored).
- Per spec §5.8: no backward-compat migration for old top-level `skillIds` records — old dev data is reset by reinstalling kits.

`src/renderer/services/kit.ts` — `installKit` sends `mcpServers: kit.mcpServers ?? []`, `connectors: kit.connectors ?? []`; drop the unused `skillListIds` param (or keep for logging — prefer drop).

`src/renderer/types/electron.d.ts` — update `kits.listInstalled` return type and `kits.install` params; update `cowork.startSession`/`continueSession` option types with the new fields.

### 6. Send flow — renderer

`CoworkPromptInput.handleSubmit`:
- `directSkillIds = activeSkillIds` (unchanged).
- `kitSkillIds = activeKitIds.flatMap(kitId => installedKits[kitId]?.skills?.skillIds ?? [])`.
- `allSkillIds = [...new Set([...activeSkillIds, ...kitSkillIds])]` → drives `buildSelectedSkillRoutingPrompt` (runtime skill prompt, unchanged behavior).
- NEW: build kit context prompt from marketplace + installed data via `buildSelectedKitContextPrompt` and pass as an additional `kitPrompt` argument to `onSubmit` (extend the `onSubmit` signature: `(prompt, skillPrompt, kitPrompt, imageAttachments, mediaReferences)`), or fold into `skillPrompt` — folding keeps the signature stable but muddles concerns; extending the signature is cleaner and both call sites are local. Choose: **extend signature** with a `kitPrompt?: string` parameter.

`CoworkView.handleStartSession` / `handleContinueSession`:
- Capture `sessionSkillIds = [...activeSkillIds]` (direct), `sessionKitIds = [...activeKitIds]`.
- `resolvedKitCapabilities = resolveSelectedKitCapabilities(sessionKitIds, installedKits)` (skip when no kits).
- `kitReferences = buildKitReferences(sessionKitIds, marketplaceKits)` (skip when no kits).
- Runtime list: `runtimeSkillIds = resolveRoutableSkillIds([...sessionSkillIds, ...(resolvedKitCapabilities?.skillIds ?? [])])`.
- Temp session message metadata (start): `skillIds: sessionSkillIds` (direct only), `kitIds`, `kitReferences` — NOT `expandedSkillIds`.
- `coworkService.startSession({... activeSkillIds: runtimeSkillIds, directSkillIds: sessionSkillIds, kitIds, kitReferences, resolvedKitCapabilities})`; same for continue.
- System prompt: `buildCoworkSystemPrompt(kitPrompt ? [skillPrompt, kitPrompt].join('\n\n') : skillPrompt, config.systemPrompt)` — better: extend `skillSystemPrompt.ts` with a `buildCoworkSystemPrompt(skillPrompt?, kitPrompt?, base)` that joins non-empty parts. For continuation, `buildCoworkContinuationSystemPrompt` gets the same treatment so a turn with only a Kit (no direct skills) still sends kit context; a turn with neither sends `undefined`.
- Clearing: after successful send, always clear active skills/kits and both drafts for the draft key (currently only cleared `if (sent && (sessionSkillIds.length > 0 || sessionKitIds.length > 0))` in continue — change to always clear on success, matching the start handler, so selections never leak to the next turn).

`src/renderer/services/cowork.ts` — `startSession`/`continueSession` pass the new fields through to IPC.

### 7. Main process — `src/main/main.ts`

`cowork:session:start`:
- options type gains `directSkillIds?: string[]; kitIds?: string[]; kitReferences?: KitReference[]; resolvedKitCapabilities?: ResolvedKitCapabilities`.
- `createSession(...)` keeps receiving the runtime expanded list (`options.activeSkillIds`).
- Message metadata:
  ```ts
  if (options.directSkillIds?.length) messageMetadata.skillIds = options.directSkillIds;
  if (options.kitIds?.length) messageMetadata.kitIds = options.kitIds;
  if (options.kitReferences?.length) messageMetadata.kitReferences = options.kitReferences;
  if (options.resolvedKitCapabilities) messageMetadata.resolvedKitCapabilities = options.resolvedKitCapabilities;
  ```
- runtime.startSession continues to get `skillIds: options.activeSkillIds` (expanded runtime list).

`cowork:session:continue`: same metadata handling; the user message for continuation is written by `openclawRuntimeAdapter.runTurn`, so pass `kitIds`/`kitReferences`/`directSkillIds` through `CoworkContinueOptions` (types.ts) into `runTurn` options, and in `runTurn`'s `!skipInitialUserMessage` branch write `metadata.skillIds = directSkillIds`, plus `kitIds`/`kitReferences` when present.

### 8. Display — `UserMessageItem.tsx`

- Read `kitReferences` from metadata; also read `kitIds` as fallback. Build badge items: prefer `kitReferences` entries (name from reference), fallback to `kitIds` mapped to marketplace lookup passed in as a prop (or resolve name from `id`). Simplest per spec §5.6: pass `marketplaceKits` (or a `kits: Array<{id, name}>` prop) down from `CoworkSessionDetail`/`ConversationTurnsView` (both already have access to the kit slice via `useSelector`).
- Render a `UserMessageKitBadges` block (Kit icon = `SidebarKitsIcon`, kit name, tooltip "由专家套件提供"/"Provided by kit" i18n key) above the Skill badges.
- `metadata.skillIds` continues to drive Skill badges — now guaranteed direct-only for new messages. Historical messages with old expanded `skillIds` will show skill badges; acceptable per spec §5.8 (no prod compat needed).
- Kit-expanded skills must not appear as skill badges: guaranteed by construction (metadata no longer contains them).

### 9. Re-edit — `CoworkSessionDetail.tsx` `handleReEdit`

```ts
const skillIds = metadata?.skillIds;   // direct only
if (skillIds?.length) dispatch(setActiveSkillIds(skillIds));
else dispatch(setActiveSkillIds([]));  // avoid stale selection from previous turn
const kitIds = metadata?.kitIds;
if (kitIds?.length) dispatch(setActiveKitIds(kitIds));
else dispatch(setActiveKitIds([]));
```
(Note the current code never clears when metadata lacks skills — fix that too so re-edit doesn't inherit the previous turn's selections.)

### 10. Markdown — `MarkdownContent.tsx`

- Add `'kit'` to `SAFE_URL_PROTOCOLS`.
- Export `safeUrlTransform` (currently module-private) and add + export `isInternalHref(href)`: true for `kit://` (and `#`-anchors stay as-is). Keep `javascript:` etc. stripped (existing behavior, add test).
- In the `a` component: if `isInternalHref(hrefValue)` and it's a `kit://` link, render a pill/badge span (kit icon + link text, e.g. `@design`) with `title` = uri; no click handler that opens external/browser; no `target=_blank`.

### 11. i18n — `src/renderer/services/i18n.ts`

New keys (zh/en):
- `kitBadgeTooltip`: '由专家套件提供' / 'Provided by kit'

### 12. String-literal constants

Per CLAUDE.md rules, kit reference `kind`/`source` values and the `kit` URI scheme go in the shared `capability.ts` const object (`KitReferenceSource.LobsteraiKits`, `KIT_URI_SCHEME`), and consumers use the constants in construction/comparison (tests included). Interface `kind: 'kit'` stays literal.

## Tests (Vitest, co-located `.test.ts`)

1. `src/shared/kit/capability.test.ts`
   - `buildKitUri('design')` → `kit://design@lobsterai-kits`; id encoding for special chars.
   - resolver: nested `skills.skillIds`; multi-kit de-dup preserving first-seen order; missing kit skipped; `mcpServers`/`connectors` null/missing → `[]`.
   - `buildKitReference` shape: `kind: 'kit'`, `source: 'lobsterai-kits'`, uri, localized name passthrough.
2. `src/renderer/components/cowork/selectedKitContextPrompt.test.ts`
   - no kits → `undefined`.
   - kit with skills/mcp/connectors → contains `<id>design</id>`, `<name>Design</name>`, `<skill id="design-critique" name="/design-critique" />`, `<mcpServer id="figma" ... />`, `<connector id="github" name="GitHub" />`.
   - marketplace skill metadata missing → falls back to installed skill IDs for id and name.
   - never contains `tryAsking` content or `SKILL.md` body.
3. `src/renderer/services/kitCapability.test.ts`
   - `buildKitReferences` uses marketplace localized name; missing marketplace kit still yields reference with uri.
4. `src/renderer/components/cowork/UserMessageItem` badge logic — extract pure helper `resolveUserMessageKitBadges(metadata, kits)` into `messageDisplayUtils.ts` (or a new util) and test: kitReferences preferred, kitIds fallback, kit-expanded skills not shown as skill badges.
5. `src/renderer/components/MarkdownContent` — test exported `safeUrlTransform` and `isInternalHref`:
   - `safeUrlTransform('kit://design@lobsterai-kits')` → same string.
   - `isInternalHref('kit://design@lobsterai-kits')` → true.
   - `safeUrlTransform('javascript:alert(1)')` → `''`.
   - `safeUrlTransform('https://x.com')` → unchanged.

## Verification

1. `npm test -- kit` and full `npm test` (vitest).
2. `npm run lint` on changed files.
3. `npx tsc --noEmit -p tsconfig.json` and `-p electron-tsconfig.json` for type checks.
4. Manual (needs `npm run electron:dev`, if environment allows): install a kit, select it, send, verify single Kit badge; verify runtime still gets expanded skills (check main-process logs / response behavior); re-edit restores kit; follow-up turn with no kit sends no kit metadata; `[@design](kit://design@lobsterai-kits)` in a message renders as internal badge.

## Notes / decisions

- Shared module in `src/shared/kit/` so main + renderer share types without renderer→main imports (matches existing `src/shared/cowork/constants.ts` pattern; vitest + vite both alias `@shared`).
- Renderer keeps computing everything (it has marketplace + installed data in Redux); main process just persists what it's given — keeps main thin and matches spec §5.5.
- `directSkillIds` added to IPC options so main can write direct-only `metadata.skillIds` while the runtime keeps receiving the expanded `activeSkillIds` (no runtime behavior change).
- No backward-compat shim for old installed-kit records or old message metadata (spec §5.8 explicitly waives this).
