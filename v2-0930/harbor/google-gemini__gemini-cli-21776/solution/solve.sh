#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.gemini/commands/strict-development-rules.md b/.gemini/commands/strict-development-rules.md
--- a/.gemini/commands/strict-development-rules.md
+++ b/.gemini/commands/strict-development-rules.md
@@ -107,7 +107,7 @@ Gemini CLI project.
   set.
 - **Logging**: Use `debugLogger` for rethrown errors to avoid duplicate logging.
 - **Keyboard Shortcuts**: Define all new keyboard shortcuts in
-  `packages/cli/src/config/keyBindings.ts` and document them in
+  `packages/cli/src/ui/key/keyBindings.ts` and document them in
   `docs/cli/keyboard-shortcuts.md`. Be careful of keybindings that require the
   `Meta` key, as only certain meta key shortcuts are supported on Mac. Avoid
   function keys and shortcuts commonly bound in VSCode.
diff --git a/docs/reference/keyboard-shortcuts.md b/docs/reference/keyboard-shortcuts.md
--- a/docs/reference/keyboard-shortcuts.md
+++ b/docs/reference/keyboard-shortcuts.md
@@ -55,14 +55,13 @@ available combinations.
 
 #### History & Search
 
-| Action                                       | Keys         |
-| -------------------------------------------- | ------------ |
-| Show the previous entry in history.          | `Ctrl+P`     |
-| Show the next entry in history.              | `Ctrl+N`     |
-| Start reverse search through history.        | `Ctrl+R`     |
-| Submit the selected reverse-search match.    | `Enter`      |
-| Accept a suggestion while reverse searching. | `Tab`        |
-| Browse and rewind previous interactions.     | `Double Esc` |
+| Action                                       | Keys     |
+| -------------------------------------------- | -------- |
+| Show the previous entry in history.          | `Ctrl+P` |
+| Show the next entry in history.              | `Ctrl+N` |
+| Start reverse search through history.        | `Ctrl+R` |
+| Submit the selected reverse-search match.    | `Enter`  |
+| Accept a suggestion while reverse searching. | `Tab`    |
 
 #### Navigation
 
diff --git a/packages/cli/src/ui/AppContainer.tsx b/packages/cli/src/ui/AppContainer.tsx
--- a/packages/cli/src/ui/AppContainer.tsx
+++ b/packages/cli/src/ui/AppContainer.tsx
@@ -119,7 +119,7 @@ import { type InitializationResult } from '../core/initializer.js';
 import { useFocus } from './hooks/useFocus.js';
 import { useKeypress, type Key } from './hooks/useKeypress.js';
 import { KeypressPriority } from './contexts/KeypressContext.js';
-import { Command } from './keyMatchers.js';
+import { Command } from './key/keyMatchers.js';
 import { useLoadingIndicator } from './hooks/useLoadingIndicator.js';
 import { useShellInactivityStatus } from './hooks/useShellInactivityStatus.js';
 import { useFolderTrust } from './hooks/useFolderTrust.js';
diff --git a/packages/cli/src/ui/auth/ApiAuthDialog.tsx b/packages/cli/src/ui/auth/ApiAuthDialog.tsx
--- a/packages/cli/src/ui/auth/ApiAuthDialog.tsx
+++ b/packages/cli/src/ui/auth/ApiAuthDialog.tsx
@@ -13,7 +13,7 @@ import { useTextBuffer } from '../components/shared/text-buffer.js';
 import { useUIState } from '../contexts/UIStateContext.js';
 import { clearApiKey, debugLogger } from '@google/gemini-cli-core';
 import { useKeypress } from '../hooks/useKeypress.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
 
 interface ApiAuthDialogProps {
diff --git a/packages/cli/src/ui/components/AdminSettingsChangedDialog.tsx b/packages/cli/src/ui/components/AdminSettingsChangedDialog.tsx
--- a/packages/cli/src/ui/components/AdminSettingsChangedDialog.tsx
+++ b/packages/cli/src/ui/components/AdminSettingsChangedDialog.tsx
@@ -8,7 +8,7 @@ import { Box, Text } from 'ink';
 import { theme } from '../semantic-colors.js';
 import { useKeypress } from '../hooks/useKeypress.js';
 import { useUIActions } from '../contexts/UIActionsContext.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
 
 export const AdminSettingsChangedDialog = () => {
diff --git a/packages/cli/src/ui/components/ApprovalModeIndicator.tsx b/packages/cli/src/ui/components/ApprovalModeIndicator.tsx
--- a/packages/cli/src/ui/components/ApprovalModeIndicator.tsx
+++ b/packages/cli/src/ui/components/ApprovalModeIndicator.tsx
@@ -8,8 +8,8 @@ import type React from 'react';
 import { Box, Text } from 'ink';
 import { theme } from '../semantic-colors.js';
 import { ApprovalMode } from '@google/gemini-cli-core';
-import { formatCommand } from '../utils/keybindingUtils.js';
-import { Command } from '../../config/keyBindings.js';
+import { formatCommand } from '../key/keybindingUtils.js';
+import { Command } from '../key/keyBindings.js';
 
 interface ApprovalModeIndicatorProps {
   approvalMode: ApprovalMode;
diff --git a/packages/cli/src/ui/components/AskUserDialog.tsx b/packages/cli/src/ui/components/AskUserDialog.tsx
--- a/packages/cli/src/ui/components/AskUserDialog.tsx
+++ b/packages/cli/src/ui/components/AskUserDialog.tsx
@@ -20,10 +20,10 @@ import { BaseSelectionList } from './shared/BaseSelectionList.js';
 import type { SelectionListItem } from '../hooks/useSelectionList.js';
 import { TabHeader, type Tab } from './shared/TabHeader.js';
 import { useKeypress, type Key } from '../hooks/useKeypress.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { checkExhaustive } from '@google/gemini-cli-core';
 import { TextInput } from './shared/TextInput.js';
-import { formatCommand } from '../utils/keybindingUtils.js';
+import { formatCommand } from '../key/keybindingUtils.js';
 import {
   useTextBuffer,
   expandPastePlaceholders,
diff --git a/packages/cli/src/ui/components/BackgroundShellDisplay.tsx b/packages/cli/src/ui/components/BackgroundShellDisplay.tsx
--- a/packages/cli/src/ui/components/BackgroundShellDisplay.tsx
+++ b/packages/cli/src/ui/components/BackgroundShellDisplay.tsx
@@ -16,9 +16,9 @@ import {
 } from '@google/gemini-cli-core';
 import { cpLen, cpSlice, getCachedStringWidth } from '../utils/textUtils.js';
 import { type BackgroundShell } from '../hooks/shellCommandProcessor.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeypress } from '../hooks/useKeypress.js';
-import { formatCommand } from '../utils/keybindingUtils.js';
+import { formatCommand } from '../key/keybindingUtils.js';
 import {
   ScrollableList,
   type ScrollableListRef,
diff --git a/packages/cli/src/ui/components/ExitPlanModeDialog.tsx b/packages/cli/src/ui/components/ExitPlanModeDialog.tsx
--- a/packages/cli/src/ui/components/ExitPlanModeDialog.tsx
+++ b/packages/cli/src/ui/components/ExitPlanModeDialog.tsx
@@ -22,8 +22,8 @@ import { useConfig } from '../contexts/ConfigContext.js';
 import { AskUserDialog } from './AskUserDialog.js';
 import { openFileInEditor } from '../utils/editorUtils.js';
 import { useKeypress } from '../hooks/useKeypress.js';
-import { Command } from '../keyMatchers.js';
-import { formatCommand } from '../utils/keybindingUtils.js';
+import { Command } from '../key/keyMatchers.js';
+import { formatCommand } from '../key/keybindingUtils.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
 
 export interface ExitPlanModeDialogProps {
diff --git a/packages/cli/src/ui/components/FooterConfigDialog.tsx b/packages/cli/src/ui/components/FooterConfigDialog.tsx
--- a/packages/cli/src/ui/components/FooterConfigDialog.tsx
+++ b/packages/cli/src/ui/components/FooterConfigDialog.tsx
@@ -11,7 +11,7 @@ import { theme } from '../semantic-colors.js';
 import { useSettingsStore } from '../contexts/SettingsContext.js';
 import { useUIState } from '../contexts/UIStateContext.js';
 import { useKeypress, type Key } from '../hooks/useKeypress.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { FooterRow, type FooterRowItem } from './Footer.js';
 import { ALL_ITEMS, resolveFooterState } from '../../config/footerItems.js';
 import { SettingScope } from '../../config/settings.js';
diff --git a/packages/cli/src/ui/components/Help.tsx b/packages/cli/src/ui/components/Help.tsx
--- a/packages/cli/src/ui/components/Help.tsx
+++ b/packages/cli/src/ui/components/Help.tsx
@@ -10,8 +10,8 @@ import { theme } from '../semantic-colors.js';
 import { type SlashCommand, CommandKind } from '../commands/types.js';
 import { KEYBOARD_SHORTCUTS_URL } from '../constants.js';
 import { sanitizeForDisplay } from '../utils/textUtils.js';
-import { formatCommand } from '../utils/keybindingUtils.js';
-import { Command } from '../../config/keyBindings.js';
+import { formatCommand } from '../key/keybindingUtils.js';
+import { Command } from '../key/keyBindings.js';
 
 interface Help {
   commands: readonly SlashCommand[];
diff --git a/packages/cli/src/ui/components/HooksDialog.tsx b/packages/cli/src/ui/components/HooksDialog.tsx
--- a/packages/cli/src/ui/components/HooksDialog.tsx
+++ b/packages/cli/src/ui/components/HooksDialog.tsx
@@ -9,7 +9,7 @@ import { useState, useMemo } from 'react';
 import { Box, Text } from 'ink';
 import { theme } from '../semantic-colors.js';
 import { useKeypress } from '../hooks/useKeypress.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
 
 /**
diff --git a/packages/cli/src/ui/components/InputPrompt.tsx b/packages/cli/src/ui/components/InputPrompt.tsx
--- a/packages/cli/src/ui/components/InputPrompt.tsx
+++ b/packages/cli/src/ui/components/InputPrompt.tsx
@@ -36,8 +36,8 @@ import {
 } from '../hooks/useCommandCompletion.js';
 import type { Key } from '../hooks/useKeypress.js';
 import { useKeypress } from '../hooks/useKeypress.js';
-import { Command } from '../keyMatchers.js';
-import { formatCommand } from '../utils/keybindingUtils.js';
+import { Command } from '../key/keyMatchers.js';
+import { formatCommand } from '../key/keybindingUtils.js';
 import type { CommandContext, SlashCommand } from '../commands/types.js';
 import type { Config } from '@google/gemini-cli-core';
 import { ApprovalMode, coreEvents, debugLogger } from '@google/gemini-cli-core';
diff --git a/packages/cli/src/ui/components/PolicyUpdateDialog.tsx b/packages/cli/src/ui/components/PolicyUpdateDialog.tsx
--- a/packages/cli/src/ui/components/PolicyUpdateDialog.tsx
+++ b/packages/cli/src/ui/components/PolicyUpdateDialog.tsx
@@ -16,7 +16,7 @@ import { theme } from '../semantic-colors.js';
 import type { RadioSelectItem } from './shared/RadioButtonSelect.js';
 import { RadioButtonSelect } from './shared/RadioButtonSelect.js';
 import { useKeypress } from '../hooks/useKeypress.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
 
 export enum PolicyUpdateChoice {
diff --git a/packages/cli/src/ui/components/RawMarkdownIndicator.tsx b/packages/cli/src/ui/components/RawMarkdownIndicator.tsx
--- a/packages/cli/src/ui/components/RawMarkdownIndicator.tsx
+++ b/packages/cli/src/ui/components/RawMarkdownIndicator.tsx
@@ -7,8 +7,8 @@
 import type React from 'react';
 import { Box, Text } from 'ink';
 import { theme } from '../semantic-colors.js';
-import { formatCommand } from '../utils/keybindingUtils.js';
-import { Command } from '../../config/keyBindings.js';
+import { formatCommand } from '../key/keybindingUtils.js';
+import { Command } from '../key/keyBindings.js';
 
 export const RawMarkdownIndicator: React.FC = () => {
   const modKey = formatCommand(Command.TOGGLE_MARKDOWN);
diff --git a/packages/cli/src/ui/components/RewindConfirmation.tsx b/packages/cli/src/ui/components/RewindConfirmation.tsx
--- a/packages/cli/src/ui/components/RewindConfirmation.tsx
+++ b/packages/cli/src/ui/components/RewindConfirmation.tsx
@@ -13,7 +13,7 @@ import type { RadioSelectItem } from './shared/RadioButtonSelect.js';
 import type { FileChangeStats } from '../utils/rewindFileOps.js';
 import { useKeypress } from '../hooks/useKeypress.js';
 import { formatTimeAgo } from '../utils/formatters.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
 
 export enum RewindOutcome {
diff --git a/packages/cli/src/ui/components/RewindViewer.tsx b/packages/cli/src/ui/components/RewindViewer.tsx
--- a/packages/cli/src/ui/components/RewindViewer.tsx
+++ b/packages/cli/src/ui/components/RewindViewer.tsx
@@ -19,7 +19,7 @@ import { useKeypress } from '../hooks/useKeypress.js';
 import { useRewind } from '../hooks/useRewind.js';
 import { RewindConfirmation, RewindOutcome } from './RewindConfirmation.js';
 import { stripReferenceContent } from '../utils/formatters.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { CliSpinner } from './CliSpinner.js';
 import { ExpandableText } from './shared/ExpandableText.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
diff --git a/packages/cli/src/ui/components/ShellInputPrompt.tsx b/packages/cli/src/ui/components/ShellInputPrompt.tsx
--- a/packages/cli/src/ui/components/ShellInputPrompt.tsx
+++ b/packages/cli/src/ui/components/ShellInputPrompt.tsx
@@ -8,9 +8,9 @@ import { useCallback } from 'react';
 import type React from 'react';
 import { useKeypress } from '../hooks/useKeypress.js';
 import { ShellExecutionService } from '@google/gemini-cli-core';
-import { keyToAnsi, type Key } from '../hooks/keyToAnsi.js';
+import { keyToAnsi, type Key } from '../key/keyToAnsi.js';
 import { ACTIVE_SHELL_MAX_LINES } from '../constants.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
 
 export interface ShellInputPromptProps {
diff --git a/packages/cli/src/ui/components/ShortcutsHelp.tsx b/packages/cli/src/ui/components/ShortcutsHelp.tsx
--- a/packages/cli/src/ui/components/ShortcutsHelp.tsx
+++ b/packages/cli/src/ui/components/ShortcutsHelp.tsx
@@ -10,8 +10,8 @@ import { theme } from '../semantic-colors.js';
 import { isNarrowWidth } from '../utils/isNarrowWidth.js';
 import { SectionHeader } from './shared/SectionHeader.js';
 import { useUIState } from '../contexts/UIStateContext.js';
-import { Command } from '../../config/keyBindings.js';
-import { formatCommand } from '../utils/keybindingUtils.js';
+import { Command } from '../key/keyBindings.js';
+import { formatCommand } from '../key/keybindingUtils.js';
 
 type ShortcutItem = {
   key: string;
@@ -21,7 +21,7 @@ type ShortcutItem = {
 const buildShortcutItems = (): ShortcutItem[] => [
   { key: '!', description: 'shell mode' },
   { key: '@', description: 'select file or folder' },
-  { key: formatCommand(Command.REWIND), description: 'clear & rewind' },
+  { key: 'Double Esc', description: 'clear & rewind' },
   { key: formatCommand(Command.FOCUS_SHELL_INPUT), description: 'focus UI' },
   { key: formatCommand(Command.TOGGLE_YOLO), description: 'YOLO mode' },
   {
diff --git a/packages/cli/src/ui/components/ValidationDialog.tsx b/packages/cli/src/ui/components/ValidationDialog.tsx
--- a/packages/cli/src/ui/components/ValidationDialog.tsx
+++ b/packages/cli/src/ui/components/ValidationDialog.tsx
@@ -16,7 +16,7 @@ import {
   type ValidationIntent,
 } from '@google/gemini-cli-core';
 import { useKeypress } from '../hooks/useKeypress.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
 
 interface ValidationDialogProps {
diff --git a/packages/cli/src/ui/components/messages/Todo.tsx b/packages/cli/src/ui/components/messages/Todo.tsx
--- a/packages/cli/src/ui/components/messages/Todo.tsx
+++ b/packages/cli/src/ui/components/messages/Todo.tsx
@@ -11,8 +11,8 @@ import { useMemo } from 'react';
 import type { HistoryItemToolGroup } from '../../types.js';
 import { Checklist } from '../Checklist.js';
 import type { ChecklistItemData } from '../ChecklistItem.js';
-import { formatCommand } from '../../utils/keybindingUtils.js';
-import { Command } from '../../../config/keyBindings.js';
+import { formatCommand } from '../../key/keybindingUtils.js';
+import { Command } from '../../key/keyBindings.js';
 
 export const TodoTray: React.FC = () => {
   const uiState = useUIState();
diff --git a/packages/cli/src/ui/components/messages/ToolConfirmationMessage.tsx b/packages/cli/src/ui/components/messages/ToolConfirmationMessage.tsx
--- a/packages/cli/src/ui/components/messages/ToolConfirmationMessage.tsx
+++ b/packages/cli/src/ui/components/messages/ToolConfirmationMessage.tsx
@@ -29,8 +29,8 @@ import {
 import { useKeypress } from '../../hooks/useKeypress.js';
 import { theme } from '../../semantic-colors.js';
 import { useSettings } from '../../contexts/SettingsContext.js';
-import { Command } from '../../keyMatchers.js';
-import { formatCommand } from '../../utils/keybindingUtils.js';
+import { Command } from '../../key/keyMatchers.js';
+import { formatCommand } from '../../key/keybindingUtils.js';
 import { AskUserDialog } from '../AskUserDialog.js';
 import { ExitPlanModeDialog } from '../ExitPlanModeDialog.js';
 import { WarningMessage } from './WarningMessage.js';
diff --git a/packages/cli/src/ui/components/messages/ToolShared.tsx b/packages/cli/src/ui/components/messages/ToolShared.tsx
--- a/packages/cli/src/ui/components/messages/ToolShared.tsx
+++ b/packages/cli/src/ui/components/messages/ToolShared.tsx
@@ -23,8 +23,8 @@ import {
   CoreToolCallStatus,
 } from '@google/gemini-cli-core';
 import { useInactivityTimer } from '../../hooks/useInactivityTimer.js';
-import { formatCommand } from '../../utils/keybindingUtils.js';
-import { Command } from '../../../config/keyBindings.js';
+import { formatCommand } from '../../key/keybindingUtils.js';
+import { Command } from '../../key/keyBindings.js';
 
 export const STATUS_INDICATOR_WIDTH = 3;
 
diff --git a/packages/cli/src/ui/components/shared/BaseSettingsDialog.tsx b/packages/cli/src/ui/components/shared/BaseSettingsDialog.tsx
--- a/packages/cli/src/ui/components/shared/BaseSettingsDialog.tsx
+++ b/packages/cli/src/ui/components/shared/BaseSettingsDialog.tsx
@@ -19,10 +19,10 @@ import { TextInput } from './TextInput.js';
 import type { TextBuffer } from './text-buffer.js';
 import { cpSlice, cpLen, cpIndexToOffset } from '../../utils/textUtils.js';
 import { useKeypress, type Key } from '../../hooks/useKeypress.js';
-import { Command } from '../../keyMatchers.js';
+import { Command } from '../../key/keyMatchers.js';
 import { useSettingsNavigation } from '../../hooks/useSettingsNavigation.js';
 import { useInlineEditBuffer } from '../../hooks/useInlineEditBuffer.js';
-import { formatCommand } from '../../utils/keybindingUtils.js';
+import { formatCommand } from '../../key/keybindingUtils.js';
 import { useKeyMatchers } from '../../hooks/useKeyMatchers.js';
 
 /**
diff --git a/packages/cli/src/ui/components/shared/MaxSizedBox.tsx b/packages/cli/src/ui/components/shared/MaxSizedBox.tsx
--- a/packages/cli/src/ui/components/shared/MaxSizedBox.tsx
+++ b/packages/cli/src/ui/components/shared/MaxSizedBox.tsx
@@ -10,8 +10,8 @@ import { Box, Text, ResizeObserver, type DOMElement } from 'ink';
 import { theme } from '../../semantic-colors.js';
 import { useOverflowActions } from '../../contexts/OverflowContext.js';
 import { isNarrowWidth } from '../../utils/isNarrowWidth.js';
-import { Command } from '../../../config/keyBindings.js';
-import { formatCommand } from '../../utils/keybindingUtils.js';
+import { Command } from '../../key/keyBindings.js';
+import { formatCommand } from '../../key/keybindingUtils.js';
 
 /**
  * Minimum height for the MaxSizedBox component.
diff --git a/packages/cli/src/ui/components/shared/Scrollable.tsx b/packages/cli/src/ui/components/shared/Scrollable.tsx
--- a/packages/cli/src/ui/components/shared/Scrollable.tsx
+++ b/packages/cli/src/ui/components/shared/Scrollable.tsx
@@ -19,7 +19,7 @@ import { useKeypress, type Key } from '../../hooks/useKeypress.js';
 import { useScrollable } from '../../contexts/ScrollProvider.js';
 import { useAnimatedScrollbar } from '../../hooks/useAnimatedScrollbar.js';
 import { useBatchedScroll } from '../../hooks/useBatchedScroll.js';
-import { Command } from '../../keyMatchers.js';
+import { Command } from '../../key/keyMatchers.js';
 import { useOverflowActions } from '../../contexts/OverflowContext.js';
 import { useKeyMatchers } from '../../hooks/useKeyMatchers.js';
 
diff --git a/packages/cli/src/ui/components/shared/ScrollableList.tsx b/packages/cli/src/ui/components/shared/ScrollableList.tsx
--- a/packages/cli/src/ui/components/shared/ScrollableList.tsx
+++ b/packages/cli/src/ui/components/shared/ScrollableList.tsx
@@ -22,7 +22,7 @@ import { useScrollable } from '../../contexts/ScrollProvider.js';
 import { Box, type DOMElement } from 'ink';
 import { useAnimatedScrollbar } from '../../hooks/useAnimatedScrollbar.js';
 import { useKeypress, type Key } from '../../hooks/useKeypress.js';
-import { Command } from '../../keyMatchers.js';
+import { Command } from '../../key/keyMatchers.js';
 import { useKeyMatchers } from '../../hooks/useKeyMatchers.js';
 
 const ANIMATION_FRAME_DURATION_MS = 33;
diff --git a/packages/cli/src/ui/components/shared/SearchableList.tsx b/packages/cli/src/ui/components/shared/SearchableList.tsx
--- a/packages/cli/src/ui/components/shared/SearchableList.tsx
+++ b/packages/cli/src/ui/components/shared/SearchableList.tsx
@@ -11,7 +11,7 @@ import { useSelectionList } from '../../hooks/useSelectionList.js';
 import { TextInput } from './TextInput.js';
 import type { TextBuffer } from './text-buffer.js';
 import { useKeypress } from '../../hooks/useKeypress.js';
-import { Command } from '../../keyMatchers.js';
+import { Command } from '../../key/keyMatchers.js';
 import { useKeyMatchers } from '../../hooks/useKeyMatchers.js';
 
 /**
diff --git a/packages/cli/src/ui/components/shared/TextInput.tsx b/packages/cli/src/ui/components/shared/TextInput.tsx
--- a/packages/cli/src/ui/components/shared/TextInput.tsx
+++ b/packages/cli/src/ui/components/shared/TextInput.tsx
@@ -14,7 +14,7 @@ import { theme } from '../../semantic-colors.js';
 import type { TextBuffer } from './text-buffer.js';
 import { expandPastePlaceholders } from './text-buffer.js';
 import { cpSlice, cpIndexToOffset } from '../../utils/textUtils.js';
-import { Command } from '../../keyMatchers.js';
+import { Command } from '../../key/keyMatchers.js';
 import { useKeyMatchers } from '../../hooks/useKeyMatchers.js';
 
 export interface TextInputProps {
diff --git a/packages/cli/src/ui/components/shared/text-buffer.ts b/packages/cli/src/ui/components/shared/text-buffer.ts
--- a/packages/cli/src/ui/components/shared/text-buffer.ts
+++ b/packages/cli/src/ui/components/shared/text-buffer.ts
@@ -25,7 +25,7 @@ import {
 } from '../../utils/textUtils.js';
 import { parsePastedPaths } from '../../utils/clipboardUtils.js';
 import type { Key } from '../../contexts/KeypressContext.js';
-import { Command } from '../../keyMatchers.js';
+import { Command } from '../../key/keyMatchers.js';
 import type { VimAction } from './vim-buffer-actions.js';
 import { handleVimAction } from './vim-buffer-actions.js';
 import { LRU_BUFFER_PERF_CACHE_LIMIT } from '../../constants.js';
diff --git a/packages/cli/src/ui/components/triage/TriageDuplicates.tsx b/packages/cli/src/ui/components/triage/TriageDuplicates.tsx
--- a/packages/cli/src/ui/components/triage/TriageDuplicates.tsx
+++ b/packages/cli/src/ui/components/triage/TriageDuplicates.tsx
@@ -10,7 +10,7 @@ import Spinner from 'ink-spinner';
 import type { Config } from '@google/gemini-cli-core';
 import { debugLogger, spawnAsync, LlmRole } from '@google/gemini-cli-core';
 import { useKeypress } from '../../hooks/useKeypress.js';
-import { Command } from '../../keyMatchers.js';
+import { Command } from '../../key/keyMatchers.js';
 import { useKeyMatchers } from '../../hooks/useKeyMatchers.js';
 
 interface Issue {
diff --git a/packages/cli/src/ui/components/triage/TriageIssues.tsx b/packages/cli/src/ui/components/triage/TriageIssues.tsx
--- a/packages/cli/src/ui/components/triage/TriageIssues.tsx
+++ b/packages/cli/src/ui/components/triage/TriageIssues.tsx
@@ -10,7 +10,7 @@ import Spinner from 'ink-spinner';
 import type { Config } from '@google/gemini-cli-core';
 import { debugLogger, spawnAsync, LlmRole } from '@google/gemini-cli-core';
 import { useKeypress } from '../../hooks/useKeypress.js';
-import { Command } from '../../keyMatchers.js';
+import { Command } from '../../key/keyMatchers.js';
 import { TextInput } from '../shared/TextInput.js';
 import { useTextBuffer } from '../shared/text-buffer.js';
 import { useKeyMatchers } from '../../hooks/useKeyMatchers.js';
diff --git a/packages/cli/src/ui/hooks/keyToAnsi.ts b/packages/cli/src/ui/hooks/keyToAnsi.ts
deleted file mode 100644
--- a/packages/cli/src/ui/hooks/keyToAnsi.ts
+++ /dev/null
@@ -1,77 +0,0 @@
-/**
- * @license
- * Copyright 2025 Google LLC
- * SPDX-License-Identifier: Apache-2.0
- */
-
-import type { Key } from '../contexts/KeypressContext.js';
-
-export type { Key };
-
-/**
- * Translates a Key object into its corresponding ANSI escape sequence.
- * This is useful for sending control characters to a pseudo-terminal.
- *
- * @param key The Key object to translate.
- * @returns The ANSI escape sequence as a string, or null if no mapping exists.
- */
-export function keyToAnsi(key: Key): string | null {
-  if (key.ctrl) {
-    // Ctrl + letter
-    if (key.name >= 'a' && key.name <= 'z') {
-      return String.fromCharCode(
-        key.name.charCodeAt(0) - 'a'.charCodeAt(0) + 1,
-      );
-    }
-    // Other Ctrl combinations might need specific handling
-    switch (key.name) {
-      case 'c':
-        return '\x03'; // ETX (End of Text), commonly used for interrupt
-      // Add other special ctrl cases if needed
-      default:
-        break;
-    }
-  }
-
-  // Arrow keys and other special keys
-  switch (key.name) {
-    case 'up':
-      return '\x1b[A';
-    case 'down':
-      return '\x1b[B';
-    case 'right':
-      return '\x1b[C';
-    case 'left':
-      return '\x1b[D';
-    case 'escape':
-      return '\x1b';
-    case 'tab':
-      return '\t';
-    case 'backspace':
-      return '\x7f';
-    case 'delete':
-      return '\x1b[3~';
-    case 'home':
-      return '\x1b[H';
-    case 'end':
-      return '\x1b[F';
-    case 'pageup':
-      return '\x1b[5~';
-    case 'pagedown':
-      return '\x1b[6~';
-    default:
-      break;
-  }
-
-  // Enter/Return
-  if (key.name === 'return') {
-    return '\r';
-  }
-
-  // If it's a simple character, return it.
-  if (!key.ctrl && !key.cmd && key.sequence) {
-    return key.sequence;
-  }
-
-  return null;
-}
diff --git a/packages/cli/src/ui/hooks/useApprovalModeIndicator.ts b/packages/cli/src/ui/hooks/useApprovalModeIndicator.ts
--- a/packages/cli/src/ui/hooks/useApprovalModeIndicator.ts
+++ b/packages/cli/src/ui/hooks/useApprovalModeIndicator.ts
@@ -11,7 +11,7 @@ import {
   getAdminErrorMessage,
 } from '@google/gemini-cli-core';
 import { useKeypress } from './useKeypress.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from './useKeyMatchers.js';
 import type { HistoryItemWithoutId } from '../types.js';
 import { MessageType } from '../types.js';
diff --git a/packages/cli/src/ui/hooks/useKeyMatchers.ts b/packages/cli/src/ui/hooks/useKeyMatchers.ts
--- a/packages/cli/src/ui/hooks/useKeyMatchers.ts
+++ b/packages/cli/src/ui/hooks/useKeyMatchers.ts
@@ -5,8 +5,8 @@
  */
 
 import { useMemo } from 'react';
-import type { KeyMatchers } from '../keyMatchers.js';
-import { defaultKeyMatchers } from '../keyMatchers.js';
+import type { KeyMatchers } from '../key/keyMatchers.js';
+import { defaultKeyMatchers } from '../key/keyMatchers.js';
 
 /**
  * Hook to retrieve the currently active key matchers.
diff --git a/packages/cli/src/ui/hooks/useSelectionList.ts b/packages/cli/src/ui/hooks/useSelectionList.ts
--- a/packages/cli/src/ui/hooks/useSelectionList.ts
+++ b/packages/cli/src/ui/hooks/useSelectionList.ts
@@ -6,7 +6,7 @@
 
 import { useReducer, useRef, useEffect, useCallback } from 'react';
 import { useKeypress, type Key } from './useKeypress.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { debugLogger } from '@google/gemini-cli-core';
 import { useKeyMatchers } from './useKeyMatchers.js';
 
diff --git a/packages/cli/src/ui/hooks/useSuspend.ts b/packages/cli/src/ui/hooks/useSuspend.ts
--- a/packages/cli/src/ui/hooks/useSuspend.ts
+++ b/packages/cli/src/ui/hooks/useSuspend.ts
@@ -20,8 +20,8 @@ import {
   terminalCapabilityManager,
 } from '../utils/terminalCapabilityManager.js';
 import { WARNING_PROMPT_DURATION_MS } from '../constants.js';
-import { formatCommand } from '../utils/keybindingUtils.js';
-import { Command } from '../../config/keyBindings.js';
+import { formatCommand } from '../key/keybindingUtils.js';
+import { Command } from '../key/keyBindings.js';
 
 interface UseSuspendProps {
   handleWarning: (message: string) => void;
diff --git a/packages/cli/src/ui/hooks/useTabbedNavigation.ts b/packages/cli/src/ui/hooks/useTabbedNavigation.ts
--- a/packages/cli/src/ui/hooks/useTabbedNavigation.ts
+++ b/packages/cli/src/ui/hooks/useTabbedNavigation.ts
@@ -6,7 +6,7 @@
 
 import { useReducer, useCallback, useEffect, useRef } from 'react';
 import { useKeypress, type Key } from './useKeypress.js';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from './useKeyMatchers.js';
 
 /**
diff --git a/packages/cli/src/ui/hooks/vim.ts b/packages/cli/src/ui/hooks/vim.ts
--- a/packages/cli/src/ui/hooks/vim.ts
+++ b/packages/cli/src/ui/hooks/vim.ts
@@ -9,7 +9,7 @@ import type { Key } from './useKeypress.js';
 import type { TextBuffer } from '../components/shared/text-buffer.js';
 import { useVimMode } from '../contexts/VimModeContext.js';
 import { debugLogger } from '@google/gemini-cli-core';
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import { useKeyMatchers } from './useKeyMatchers.js';
 
 export type VimMode = 'NORMAL' | 'INSERT';
diff --git a/packages/cli/src/config/keyBindings.ts b/packages/cli/src/ui/key/keyBindings.ts
rename from packages/cli/src/config/keyBindings.ts
rename to packages/cli/src/ui/key/keyBindings.ts
--- a/packages/cli/src/config/keyBindings.ts
+++ b/packages/cli/src/ui/key/keyBindings.ts
@@ -7,6 +7,8 @@
 /**
  * Command enum for all available keyboard shortcuts
  */
+import type { Key } from '../hooks/useKeypress.js';
+
 export enum Command {
   // Basic Controls
   RETURN = 'basic.confirm',
@@ -49,7 +51,6 @@ export enum Command {
   REVERSE_SEARCH = 'history.search.start',
   SUBMIT_REVERSE_SEARCH = 'history.search.submit',
   ACCEPT_SUGGESTION_REVERSE_SEARCH = 'history.search.accept',
-  REWIND = 'history.rewind',
 
   // Navigation
   NAVIGATION_UP = 'nav.up',
@@ -102,17 +103,126 @@ export enum Command {
 /**
  * Data-driven key binding structure for user configuration
  */
-export interface KeyBinding {
+export class KeyBinding {
+  private static readonly VALID_KEYS = new Set([
+    // Letters & Numbers
+    ...'abcdefghijklmnopqrstuvwxyz0123456789',
+    // Punctuation
+    '`',
+    '-',
+    '=',
+    '[',
+    ']',
+    '\\',
+    ';',
+    "'",
+    ',',
+    '.',
+    '/',
+    // Navigation & Actions
+    'left',
+    'up',
+    'right',
+    'down',
+    'pageup',
+    'pagedown',
+    'end',
+    'home',
+    'tab',
+    'enter',
+    'escape',
+    'space',
+    'backspace',
+    'delete',
+    'pausebreak',
+    'capslock',
+    'insert',
+    'numlock',
+    'scrolllock',
+    // Function Keys
+    ...Array.from({ length: 19 }, (_, i) => `f${i + 1}`),
+    // Numpad
+    ...Array.from({ length: 10 }, (_, i) => `numpad${i}`),
+    'numpad_multiply',
+    'numpad_add',
+    'numpad_separator',
+    'numpad_subtract',
+    'numpad_decimal',
+    'numpad_divide',
+    // Gemini CLI legacy/internal support
+    'return',
+  ]);
+
   /** The key name (e.g., 'a', 'return', 'tab', 'escape') */
-  key: string;
-  /** Shift key requirement: true=must be pressed, false=must not be pressed, undefined=ignore */
-  shift?: boolean;
-  /** Alt/Option key requirement: true=must be pressed, false=must not be pressed, undefined=ignore */
-  alt?: boolean;
-  /** Control key requirement: true=must be pressed, false=must not be pressed, undefined=ignore */
-  ctrl?: boolean;
-  /** Command/Windows/Super key requirement: true=must be pressed, false=must not be pressed, undefined=ignore */
-  cmd?: boolean;
+  readonly key: string;
+  readonly shift: boolean;
+  readonly alt: boolean;
+  readonly ctrl: boolean;
+  readonly cmd: boolean;
+
+  constructor(pattern: string) {
+    let remains = pattern.toLowerCase().trim();
+    let shift = false;
+    let alt = false;
+    let ctrl = false;
+    let cmd = false;
+
+    let matched: boolean;
+    do {
+      matched = false;
+      if (remains.startsWith('ctrl+')) {
+        ctrl = true;
+        remains = remains.slice(5);
+        matched = true;
+      } else if (remains.startsWith('shift+')) {
+        shift = true;
+        remains = remains.slice(6);
+        matched = true;
+      } else if (remains.startsWith('alt+')) {
+        alt = true;
+        remains = remains.slice(4);
+        matched = true;
+      } else if (remains.startsWith('option+')) {
+        alt = true;
+        remains = remains.slice(7);
+        matched = true;
+      } else if (remains.startsWith('opt+')) {
+        alt = true;
+        remains = remains.slice(4);
+        matched = true;
+      } else if (remains.startsWith('cmd+')) {
+        cmd = true;
+        remains = remains.slice(4);
+        matched = true;
+      } else if (remains.startsWith('meta+')) {
+        cmd = true;
+        remains = remains.slice(5);
+        matched = true;
+      }
+    } while (matched);
+
+    const key = remains;
+
+    if (!KeyBinding.VALID_KEYS.has(key)) {
+      throw new Error(`Invalid keybinding key: "${key}" in "${pattern}"`);
+    }
+
+    this.key = key;
+    this.shift = shift;
+    this.alt = alt;
+    this.ctrl = ctrl;
+    this.cmd = cmd;
+  }
+
+  matches(key: Key): boolean {
+    return (
+      this.key === key.name &&
+      !!key.shift === !!this.shift &&
+      !!key.alt === !!this.alt &&
+      !!key.ctrl === !!this.ctrl &&
+      !!key.cmd === !!this.cmd
+    );
+  }
 }
 
 /**
@@ -128,135 +238,143 @@ export type KeyBindingConfig = {
  */
 export const defaultKeyBindings: KeyBindingConfig = {
   // Basic Controls
-  [Command.RETURN]: [{ key: 'return' }],
-  [Command.ESCAPE]: [{ key: 'escape' }, { key: '[', ctrl: true }],
-  [Command.QUIT]: [{ key: 'c', ctrl: true }],
-  [Command.EXIT]: [{ key: 'd', ctrl: true }],
+  [Command.RETURN]: [new KeyBinding('return')],
+  [Command.ESCAPE]: [new KeyBinding('escape'), new KeyBinding('ctrl+[')],
+  [Command.QUIT]: [new KeyBinding('ctrl+c')],
+  [Command.EXIT]: [new KeyBinding('ctrl+d')],
 
   // Cursor Movement
-  [Command.HOME]: [{ key: 'a', ctrl: true }, { key: 'home' }],
-  [Command.END]: [{ key: 'e', ctrl: true }, { key: 'end' }],
-  [Command.MOVE_UP]: [{ key: 'up' }],
-  [Command.MOVE_DOWN]: [{ key: 'down' }],
-  [Command.MOVE_LEFT]: [{ key: 'left' }],
-  [Command.MOVE_RIGHT]: [{ key: 'right' }, { key: 'f', ctrl: true }],
+  [Command.HOME]: [new KeyBinding('ctrl+a'), new KeyBinding('home')],
+  [Command.END]: [new KeyBinding('ctrl+e'), new KeyBinding('end')],
+  [Command.MOVE_UP]: [new KeyBinding('up')],
+  [Command.MOVE_DOWN]: [new KeyBinding('down')],
+  [Command.MOVE_LEFT]: [new KeyBinding('left')],
+  [Command.MOVE_RIGHT]: [new KeyBinding('right'), new KeyBinding('ctrl+f')],
   [Command.MOVE_WORD_LEFT]: [
-    { key: 'left', ctrl: true },
-    { key: 'left', alt: true },
-    { key: 'b', alt: true },
+    new KeyBinding('ctrl+left'),
+    new KeyBinding('alt+left'),
+    new KeyBinding('alt+b'),
   ],
   [Command.MOVE_WORD_RIGHT]: [
-    { key: 'right', ctrl: true },
-    { key: 'right', alt: true },
-    { key: 'f', alt: true },
+    new KeyBinding('ctrl+right'),
+    new KeyBinding('alt+right'),
+    new KeyBinding('alt+f'),
   ],
 
   // Editing
-  [Command.KILL_LINE_RIGHT]: [{ key: 'k', ctrl: true }],
-  [Command.KILL_LINE_LEFT]: [{ key: 'u', ctrl: true }],
-  [Command.CLEAR_INPUT]: [{ key: 'c', ctrl: true }],
+  [Command.KILL_LINE_RIGHT]: [new KeyBinding('ctrl+k')],
+  [Command.KILL_LINE_LEFT]: [new KeyBinding('ctrl+u')],
+  [Command.CLEAR_INPUT]: [new KeyBinding('ctrl+c')],
   [Command.DELETE_WORD_BACKWARD]: [
-    { key: 'backspace', ctrl: true },
-    { key: 'backspace', alt: true },
-    { key: 'w', ctrl: true },
+    new KeyBinding('ctrl+backspace'),
+    new KeyBinding('alt+backspace'),
+    new KeyBinding('ctrl+w'),
   ],
   [Command.DELETE_WORD_FORWARD]: [
-    { key: 'delete', ctrl: true },
-    { key: 'delete', alt: true },
-    { key: 'd', alt: true },
+    new KeyBinding('ctrl+delete'),
+    new KeyBinding('alt+delete'),
+    new KeyBinding('alt+d'),
+  ],
+  [Command.DELETE_CHAR_LEFT]: [
+    new KeyBinding('backspace'),
+    new KeyBinding('ctrl+h'),
   ],
-  [Command.DELETE_CHAR_LEFT]: [{ key: 'backspace' }, { key: 'h', ctrl: true }],
-  [Command.DELETE_CHAR_RIGHT]: [{ key: 'delete' }, { key: 'd', ctrl: true }],
-  [Command.UNDO]: [
-    { key: 'z', cmd: true },
-    { key: 'z', alt: true },
+  [Command.DELETE_CHAR_RIGHT]: [
+    new KeyBinding('delete'),
+    new KeyBinding('ctrl+d'),
   ],
+  [Command.UNDO]: [new KeyBinding('cmd+z'), new KeyBinding('alt+z')],
   [Command.REDO]: [
-    { key: 'z', ctrl: true, shift: true },
-    { key: 'z', cmd: true, shift: true },
-    { key: 'z', alt: true, shift: true },
+    new KeyBinding('ctrl+shift+z'),
+    new KeyBinding('cmd+shift+z'),
+    new KeyBinding('alt+shift+z'),
   ],
 
   // Scrolling
-  [Command.SCROLL_UP]: [{ key: 'up', shift: true }],
-  [Command.SCROLL_DOWN]: [{ key: 'down', shift: true }],
+  [Command.SCROLL_UP]: [new KeyBinding('shift+up')],
+  [Command.SCROLL_DOWN]: [new KeyBinding('shift+down')],
   [Command.SCROLL_HOME]: [
-    { key: 'home', ctrl: true },
-    { key: 'home', shift: true },
+    new KeyBinding('ctrl+home'),
+    new KeyBinding('shift+home'),
   ],
   [Command.SCROLL_END]: [
-    { key: 'end', ctrl: true },
-    { key: 'end', shift: true },
+    new KeyBinding('ctrl+end'),
+    new KeyBinding('shift+end'),
   ],
-  [Command.PAGE_UP]: [{ key: 'pageup' }],
-  [Command.PAGE_DOWN]: [{ key: 'pagedown' }],
+  [Command.PAGE_UP]: [new KeyBinding('pageup')],
+  [Command.PAGE_DOWN]: [new KeyBinding('pagedown')],
 
   // History & Search
-  [Command.HISTORY_UP]: [{ key: 'p', ctrl: true }],
-  [Command.HISTORY_DOWN]: [{ key: 'n', ctrl: true }],
-  [Command.REVERSE_SEARCH]: [{ key: 'r', ctrl: true }],
-  [Command.REWIND]: [{ key: 'double escape' }], // for documentation only
-  [Command.SUBMIT_REVERSE_SEARCH]: [{ key: 'return' }],
-  [Command.ACCEPT_SUGGESTION_REVERSE_SEARCH]: [{ key: 'tab' }],
+  [Command.HISTORY_UP]: [new KeyBinding('ctrl+p')],
+  [Command.HISTORY_DOWN]: [new KeyBinding('ctrl+n')],
+  [Command.REVERSE_SEARCH]: [new KeyBinding('ctrl+r')],
+  [Command.SUBMIT_REVERSE_SEARCH]: [new KeyBinding('return')],
+  [Command.ACCEPT_SUGGESTION_REVERSE_SEARCH]: [new KeyBinding('tab')],
 
   // Navigation
-  [Command.NAVIGATION_UP]: [{ key: 'up' }],
-  [Command.NAVIGATION_DOWN]: [{ key: 'down' }],
+  [Command.NAVIGATION_UP]: [new KeyBinding('up')],
+  [Command.NAVIGATION_DOWN]: [new KeyBinding('down')],
   // Navigation shortcuts appropriate for dialogs where we do not need to accept
   // text input.
-  [Command.DIALOG_NAVIGATION_UP]: [{ key: 'up' }, { key: 'k' }],
-  [Command.DIALOG_NAVIGATION_DOWN]: [{ key: 'down' }, { key: 'j' }],
-  [Command.DIALOG_NEXT]: [{ key: 'tab' }],
-  [Command.DIALOG_PREV]: [{ key: 'tab', shift: true }],
+  [Command.DIALOG_NAVIGATION_UP]: [new KeyBinding('up'), new KeyBinding('k')],
+  [Command.DIALOG_NAVIGATION_DOWN]: [
+    new KeyBinding('down'),
+    new KeyBinding('j'),
+  ],
+  [Command.DIALOG_NEXT]: [new KeyBinding('tab')],
+  [Command.DIALOG_PREV]: [new KeyBinding('shift+tab')],
 
   // Suggestions & Completions
-  [Command.ACCEPT_SUGGESTION]: [{ key: 'tab' }, { key: 'return' }],
-  [Command.COMPLETION_UP]: [{ key: 'up' }, { key: 'p', ctrl: true }],
-  [Command.COMPLETION_DOWN]: [{ key: 'down' }, { key: 'n', ctrl: true }],
-  [Command.EXPAND_SUGGESTION]: [{ key: 'right' }],
-  [Command.COLLAPSE_SUGGESTION]: [{ key: 'left' }],
+  [Command.ACCEPT_SUGGESTION]: [
+    new KeyBinding('tab'),
+    new KeyBinding('return'),
+  ],
+  [Command.COMPLETION_UP]: [new KeyBinding('up'), new KeyBinding('ctrl+p')],
+  [Command.COMPLETION_DOWN]: [new KeyBinding('down'), new KeyBinding('ctrl+n')],
+  [Command.EXPAND_SUGGESTION]: [new KeyBinding('right')],
+  [Command.COLLAPSE_SUGGESTION]: [new KeyBinding('left')],
 
   // Text Input
   // Must also exclude shift to allow shift+enter for newline
-  [Command.SUBMIT]: [{ key: 'return' }],
+  [Command.SUBMIT]: [new KeyBinding('return')],
   [Command.NEWLINE]: [
-    { key: 'return', ctrl: true },
-    { key: 'return', cmd: true },
-    { key: 'return', alt: true },
-    { key: 'return', shift: true },
-    { key: 'j', ctrl: true },
+    new KeyBinding('ctrl+return'),
+    new KeyBinding('cmd+return'),
+    new KeyBinding('alt+return'),
+    new KeyBinding('shift+return'),
+    new KeyBinding('ctrl+j'),
   ],
-  [Command.OPEN_EXTERNAL_EDITOR]: [{ key: 'x', ctrl: true }],
+  [Command.OPEN_EXTERNAL_EDITOR]: [new KeyBinding('ctrl+x')],
   [Command.PASTE_CLIPBOARD]: [
-    { key: 'v', ctrl: true },
-    { key: 'v', cmd: true },
-    { key: 'v', alt: true },
+    new KeyBinding('ctrl+v'),
+    new KeyBinding('cmd+v'),
+    new KeyBinding('alt+v'),
   ],
 
   // App Controls
-  [Command.SHOW_ERROR_DETAILS]: [{ key: 'f12' }],
-  [Command.SHOW_FULL_TODOS]: [{ key: 't', ctrl: true }],
-  [Command.SHOW_IDE_CONTEXT_DETAIL]: [{ key: 'g', ctrl: true }],
-  [Command.TOGGLE_MARKDOWN]: [{ key: 'm', alt: true }],
-  [Command.TOGGLE_COPY_MODE]: [{ key: 's', ctrl: true }],
-  [Command.TOGGLE_YOLO]: [{ key: 'y', ctrl: true }],
-  [Command.CYCLE_APPROVAL_MODE]: [{ key: 'tab', shift: true }],
-  [Command.TOGGLE_BACKGROUND_SHELL]: [{ key: 'b', ctrl: true }],
-  [Command.TOGGLE_BACKGROUND_SHELL_LIST]: [{ key: 'l', ctrl: true }],
-  [Command.KILL_BACKGROUND_SHELL]: [{ key: 'k', ctrl: true }],
-  [Command.UNFOCUS_BACKGROUND_SHELL]: [{ key: 'tab', shift: true }],
-  [Command.UNFOCUS_BACKGROUND_SHELL_LIST]: [{ key: 'tab' }],
-  [Command.SHOW_BACKGROUND_SHELL_UNFOCUS_WARNING]: [{ key: 'tab' }],
-  [Command.SHOW_SHELL_INPUT_UNFOCUS_WARNING]: [{ key: 'tab' }],
-  [Command.BACKGROUND_SHELL_SELECT]: [{ key: 'return' }],
-  [Command.BACKGROUND_SHELL_ESCAPE]: [{ key: 'escape' }],
-  [Command.SHOW_MORE_LINES]: [{ key: 'o', ctrl: true }],
-  [Command.EXPAND_PASTE]: [{ key: 'o', ctrl: true }],
-  [Command.FOCUS_SHELL_INPUT]: [{ key: 'tab' }],
-  [Command.UNFOCUS_SHELL_INPUT]: [{ key: 'tab', shift: true }],
-  [Command.CLEAR_SCREEN]: [{ key: 'l', ctrl: true }],
-  [Command.RESTART_APP]: [{ key: 'r' }, { key: 'r', shift: true }],
-  [Command.SUSPEND_APP]: [{ key: 'z', ctrl: true }],
+  [Command.SHOW_ERROR_DETAILS]: [new KeyBinding('f12')],
+  [Command.SHOW_FULL_TODOS]: [new KeyBinding('ctrl+t')],
+  [Command.SHOW_IDE_CONTEXT_DETAIL]: [new KeyBinding('ctrl+g')],
+  [Command.TOGGLE_MARKDOWN]: [new KeyBinding('alt+m')],
+  [Command.TOGGLE_COPY_MODE]: [new KeyBinding('ctrl+s')],
+  [Command.TOGGLE_YOLO]: [new KeyBinding('ctrl+y')],
+  [Command.CYCLE_APPROVAL_MODE]: [new KeyBinding('shift+tab')],
+  [Command.TOGGLE_BACKGROUND_SHELL]: [new KeyBinding('ctrl+b')],
+  [Command.TOGGLE_BACKGROUND_SHELL_LIST]: [new KeyBinding('ctrl+l')],
+  [Command.KILL_BACKGROUND_SHELL]: [new KeyBinding('ctrl+k')],
+  [Command.UNFOCUS_BACKGROUND_SHELL]: [new KeyBinding('shift+tab')],
+  [Command.UNFOCUS_BACKGROUND_SHELL_LIST]: [new KeyBinding('tab')],
+  [Command.SHOW_BACKGROUND_SHELL_UNFOCUS_WARNING]: [new KeyBinding('tab')],
+  [Command.SHOW_SHELL_INPUT_UNFOCUS_WARNING]: [new KeyBinding('tab')],
+  [Command.BACKGROUND_SHELL_SELECT]: [new KeyBinding('return')],
+  [Command.BACKGROUND_SHELL_ESCAPE]: [new KeyBinding('escape')],
+  [Command.SHOW_MORE_LINES]: [new KeyBinding('ctrl+o')],
+  [Command.EXPAND_PASTE]: [new KeyBinding('ctrl+o')],
+  [Command.FOCUS_SHELL_INPUT]: [new KeyBinding('tab')],
+  [Command.UNFOCUS_SHELL_INPUT]: [new KeyBinding('shift+tab')],
+  [Command.CLEAR_SCREEN]: [new KeyBinding('ctrl+l')],
+  [Command.RESTART_APP]: [new KeyBinding('r'), new KeyBinding('shift+r')],
+  [Command.SUSPEND_APP]: [new KeyBinding('ctrl+z')],
 };
 
 interface CommandCategory {
@@ -318,7 +436,6 @@ export const commandCategories: readonly CommandCategory[] = [
       Command.REVERSE_SEARCH,
       Command.SUBMIT_REVERSE_SEARCH,
       Command.ACCEPT_SUGGESTION_REVERSE_SEARCH,
-      Command.REWIND,
     ],
   },
   {
@@ -428,7 +545,6 @@ export const commandDescriptions: Readonly<Record<Command, string>> = {
   [Command.SUBMIT_REVERSE_SEARCH]: 'Submit the selected reverse-search match.',
   [Command.ACCEPT_SUGGESTION_REVERSE_SEARCH]:
     'Accept a suggestion while reverse searching.',
-  [Command.REWIND]: 'Browse and rewind previous interactions.',
 
   // Navigation
   [Command.NAVIGATION_UP]: 'Move selection up in lists.',
diff --git a/packages/cli/src/ui/keyMatchers.ts b/packages/cli/src/ui/key/keyMatchers.ts
rename from packages/cli/src/ui/keyMatchers.ts
rename to packages/cli/src/ui/key/keyMatchers.ts
--- a/packages/cli/src/ui/keyMatchers.ts
+++ b/packages/cli/src/ui/key/keyMatchers.ts
@@ -4,26 +4,9 @@
  * SPDX-License-Identifier: Apache-2.0
  */
 
-import type { Key } from './hooks/useKeypress.js';
-import type { KeyBinding, KeyBindingConfig } from '../config/keyBindings.js';
-import { Command, defaultKeyBindings } from '../config/keyBindings.js';
-
-/**
- * Matches a KeyBinding against an actual Key press
- * Pure data-driven matching logic
- */
-function matchKeyBinding(keyBinding: KeyBinding, key: Key): boolean {
-  // Check modifiers:
-  // true = modifier must be pressed
-  // false or undefined = modifier must NOT be pressed
-  return (
-    keyBinding.key === key.name &&
-    !!key.shift === !!keyBinding.shift &&
-    !!key.alt === !!keyBinding.alt &&
-    !!key.ctrl === !!keyBinding.ctrl &&
-    !!key.cmd === !!keyBinding.cmd
-  );
-}
+import type { Key } from '../hooks/useKeypress.js';
+import type { KeyBindingConfig } from './keyBindings.js';
+import { Command, defaultKeyBindings } from './keyBindings.js';
 
 /**
  * Checks if a key matches any of the bindings for a command
@@ -33,8 +16,7 @@ function matchCommand(
   key: Key,
   config: KeyBindingConfig = defaultKeyBindings,
 ): boolean {
-  const bindings = config[command];
-  return bindings.some((binding) => matchKeyBinding(binding, key));
+  return config[command].some((binding) => binding.matches(key));
 }
 
 /**
diff --git a/packages/cli/src/ui/key/keyToAnsi.ts b/packages/cli/src/ui/key/keyToAnsi.ts
new file mode 100644
--- /dev/null
+++ b/packages/cli/src/ui/key/keyToAnsi.ts
@@ -0,0 +1,55 @@
+/**
+ * @license
+ * Copyright 2025 Google LLC
+ * SPDX-License-Identifier: Apache-2.0
+ */
+
+import type { Key } from '../contexts/KeypressContext.js';
+
+export type { Key };
+
+const SPECIAL_KEYS: Record<string, string> = {
+  up: '\x1b[A',
+  down: '\x1b[B',
+  right: '\x1b[C',
+  left: '\x1b[D',
+  escape: '\x1b',
+  tab: '\t',
+  backspace: '\x7f',
+  delete: '\x1b[3~',
+  home: '\x1b[H',
+  end: '\x1b[F',
+  pageup: '\x1b[5~',
+  pagedown: '\x1b[6~',
+  return: '\r',
+};
+
+/**
+ * Translates a Key object into its corresponding ANSI escape sequence.
+ * This is useful for sending control characters to a pseudo-terminal.
+ *
+ * @param key The Key object to translate.
+ * @returns The ANSI escape sequence as a string, or null if no mapping exists.
+ */
+export function keyToAnsi(key: Key): string | null {
+  if (key.ctrl) {
+    // Ctrl + letter (A-Z maps to 1-26, e.g., Ctrl+C is \x03)
+    if (key.name >= 'a' && key.name <= 'z') {
+      return String.fromCharCode(
+        key.name.charCodeAt(0) - 'a'.charCodeAt(0) + 1,
+      );
+    }
+  }
+
+  // Arrow keys and other special keys
+  if (key.name in SPECIAL_KEYS) {
+    return SPECIAL_KEYS[key.name];
+  }
+
+  // If it's a simple character, return it.
+  if (!key.ctrl && !key.cmd && key.sequence) {
+    return key.sequence;
+  }
+
+  return null;
+}
diff --git a/packages/cli/src/ui/utils/keybindingUtils.ts b/packages/cli/src/ui/key/keybindingUtils.ts
rename from packages/cli/src/ui/utils/keybindingUtils.ts
rename to packages/cli/src/ui/key/keybindingUtils.ts
--- a/packages/cli/src/ui/utils/keybindingUtils.ts
+++ b/packages/cli/src/ui/key/keybindingUtils.ts
@@ -10,7 +10,7 @@ import {
   type KeyBinding,
   type KeyBindingConfig,
   defaultKeyBindings,
-} from '../../config/keyBindings.js';
+} from './keyBindings.js';
 
 /**
  * Maps internal key names to user-friendly display names.
@@ -30,7 +30,6 @@ const KEY_NAME_MAP: Record<string, string> = {
   end: 'End',
   tab: 'Tab',
   space: 'Space',
-  'double escape': 'Double Esc',
 };
 
 interface ModifierMap {
diff --git a/packages/cli/src/ui/utils/shortcutsHelp.ts b/packages/cli/src/ui/utils/shortcutsHelp.ts
--- a/packages/cli/src/ui/utils/shortcutsHelp.ts
+++ b/packages/cli/src/ui/utils/shortcutsHelp.ts
@@ -4,7 +4,7 @@
  * SPDX-License-Identifier: Apache-2.0
  */
 
-import { Command } from '../keyMatchers.js';
+import { Command } from '../key/keyMatchers.js';
 import type { Key } from '../hooks/useKeypress.js';
 import { useKeyMatchers } from '../hooks/useKeyMatchers.js';
 
diff --git a/scripts/generate-keybindings-doc.ts b/scripts/generate-keybindings-doc.ts
--- a/scripts/generate-keybindings-doc.ts
+++ b/scripts/generate-keybindings-doc.ts
@@ -8,12 +8,12 @@ import path from 'node:path';
 import { fileURLToPath, pathToFileURL } from 'node:url';
 import { readFile, writeFile } from 'node:fs/promises';
 
-import type { KeyBinding } from '../packages/cli/src/config/keyBindings.js';
+import type { KeyBinding } from '../packages/cli/src/ui/key/keyBindings.js';
 import {
   commandCategories,
   commandDescriptions,
   defaultKeyBindings,
-} from '../packages/cli/src/config/keyBindings.js';
+} from '../packages/cli/src/ui/key/keyBindings.js';
 import {
   formatWithPrettier,
   injectBetweenMarkers,
@@ -24,7 +24,7 @@ const START_MARKER = '<!-- KEYBINDINGS-AUTOGEN:START -->';
 const END_MARKER = '<!-- KEYBINDINGS-AUTOGEN:END -->';
 const OUTPUT_RELATIVE_PATH = ['docs', 'reference', 'keyboard-shortcuts.md'];
 
-import { formatKeyBinding } from '../packages/cli/src/ui/utils/keybindingUtils.js';
+import { formatKeyBinding } from '../packages/cli/src/ui/key/keybindingUtils.js';
 
 export interface KeybindingDocCommand {
   description: string;
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
