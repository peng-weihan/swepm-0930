#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/packages/core/src/sheets/sheet-skeleton.ts b/packages/core/src/sheets/sheet-skeleton.ts
--- a/packages/core/src/sheets/sheet-skeleton.ts
+++ b/packages/core/src/sheets/sheet-skeleton.ts
@@ -318,8 +318,8 @@ export class SheetSkeleton extends Skeleton {
 
         return {
             ...config,
-            defaultBackgroundColor: config.defaultBackgroundColor ?? `rgba(${r}, ${g}, ${b}, 0.08)`,
-            defaultStripeColor: config.defaultStripeColor ?? `rgba(${r}, ${g}, ${b}, 0.25)`,
+            defaultBackgroundColor: config.defaultBackgroundColor ?? `rgba(${r}, ${g}, ${b}, 0.025)`,
+            defaultStripeColor: config.defaultStripeColor ?? `rgba(${r}, ${g}, ${b}, 0.08)`,
         };
     }
 
diff --git a/packages/sheets-table-ui/src/commands/operations/open-table-filter-dialog.opration.ts b/packages/sheets-table-ui/src/commands/operations/open-table-filter-dialog.opration.ts
--- a/packages/sheets-table-ui/src/commands/operations/open-table-filter-dialog.opration.ts
+++ b/packages/sheets-table-ui/src/commands/operations/open-table-filter-dialog.opration.ts
@@ -15,9 +15,8 @@
  */
 
 import type { ICommand } from '@univerjs/core';
-import { CommandType, IContextService } from '@univerjs/core';
+import { CommandType } from '@univerjs/core';
 import { TableManager } from '@univerjs/sheets-table';
-import { SHEETS_TABLE_FILTER_PANEL_OPENED_KEY } from '../../const';
 import { SheetsTableComponentController } from '../../controllers/sheet-table-component.controller';
 
 export interface IOpenTableFilterPanelOperationParams {
@@ -37,17 +36,14 @@ export const OpenTableFilterPanelOperation: ICommand<IOpenTableFilterPanelOperat
 
         const { row, col, unitId, subUnitId, tableId } = params;
         const tableManager = accessor.get(TableManager);
-        const contextService = accessor.get(IContextService);
         const sheetsTableComponentController = accessor.get(SheetsTableComponentController);
 
         const table = tableManager.getTable(unitId, tableId);
         if (!table) {
             return false;
         }
-        if (!contextService.getContextValue(SHEETS_TABLE_FILTER_PANEL_OPENED_KEY)) {
-            sheetsTableComponentController.setCurrentTableFilterInfo({ unitId, subUnitId, row, tableId, column: col });
-            contextService.setContextValue(SHEETS_TABLE_FILTER_PANEL_OPENED_KEY, true);
-        }
+
+        sheetsTableComponentController.openOrToggleFilterPanel({ unitId, subUnitId, row, tableId, column: col });
 
         return true;
 
diff --git a/packages/sheets-table-ui/src/const.ts b/packages/sheets-table-ui/src/const.ts
--- a/packages/sheets-table-ui/src/const.ts
+++ b/packages/sheets-table-ui/src/const.ts
@@ -20,6 +20,8 @@ export const UNIVER_SHEET_TABLE_FILTER_PANEL_ID = 'UNIVER_SHEET_Table_FILTER_PAN
 
 export const TABLE_TOOLBAR_BUTTON = 'TABLE_TOOLBAR_BUTTON';
 export const TABLE_SELECTOR_DIALOG = 'TABLE_SELECTOR_DIALOG';
+export const SHEET_TABLE_RENAME_DIALOG = 'SHEET_TABLE_RENAME_DIALOG';
+export const SHEET_TABLE_RENAME_DIALOG_ID = 'SHEET_TABLE_RENAME_DIALOG_ID';
 
 export const SHEET_TABLE_THEME_PANEL_ID = 'SHEET_TABLE_THEME_PANEL_ID';
 export const SHEET_TABLE_THEME_PANEL = 'SHEET_TABLE_THEME_PANEL';
diff --git a/packages/sheets-table-ui/src/controllers/sheet-table-anchor.controller.ts b/packages/sheets-table-ui/src/controllers/sheet-table-anchor.controller.ts
deleted file mode 100644
--- a/packages/sheets-table-ui/src/controllers/sheet-table-anchor.controller.ts
+++ /dev/null
@@ -1,164 +0,0 @@
-/**
- * Copyright 2023-present DreamNum Co., Ltd.
- *
- * Licensed under the Apache License, Version 2.0 (the "License");
- * you may not use this file except in compliance with the License.
- * You may obtain a copy of the License at
- *
- *     http://www.apache.org/licenses/LICENSE-2.0
- *
- * Unless required by applicable law or agreed to in writing, software
- * distributed under the License is distributed on an "AS IS" BASIS,
- * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
- * See the License for the specific language governing permissions and
- * limitations under the License.
- */
-
-import type { Workbook } from '@univerjs/core';
-import type { IRenderContext, IRenderModule } from '@univerjs/engine-render';
-import { Disposable, ICommandService, Inject, Injector, IPermissionService, IUniverInstanceService } from '@univerjs/core';
-import { convertTransformToOffsetX, convertTransformToOffsetY, IRenderManagerService, SHEET_VIEWPORT_KEY } from '@univerjs/engine-render';
-import { WorkbookEditablePermission, WorkbookPermissionService } from '@univerjs/sheets';
-import { TableManager } from '@univerjs/sheets-table';
-import { getSheetObject, SetScrollOperation, SetZoomRatioOperation, SheetScrollManagerService, SheetSkeletonManagerService } from '@univerjs/sheets-ui';
-import { BuiltInUIPart, connectInjector, IUIPartsService } from '@univerjs/ui';
-import { BehaviorSubject, debounceTime, filter, merge } from 'rxjs';
-import { SheetTableAnchor } from '../views/components/SheetTableAnchor';
-
-export interface ITableAnchorPosition {
-    x: number;
-    y: number;
-    tableId: string;
-    tableName: string;
-}
-
-export class SheetTableAnchorController extends Disposable implements IRenderModule {
-    private _anchorVisible$: BehaviorSubject<boolean> = new BehaviorSubject(true);
-    private _timer: NodeJS.Timeout;
-
-    private _anchorPosition$: BehaviorSubject<ITableAnchorPosition[]> = new BehaviorSubject<ITableAnchorPosition[]>([]);
-    public anchorPosition$ = this._anchorPosition$.asObservable();
-
-    constructor(
-        private readonly _context: IRenderContext<Workbook>,
-        @Inject(Injector) private readonly _injector: Injector,
-        @Inject(SheetSkeletonManagerService) private readonly _sheetSkeletonManagerService: SheetSkeletonManagerService,
-        @IRenderManagerService private readonly _renderManagerService: IRenderManagerService,
-        @ICommandService private readonly _commandService: ICommandService,
-        @IUniverInstanceService private readonly _univerInstanceService: IUniverInstanceService,
-        @IUIPartsService protected readonly _uiPartsService: IUIPartsService,
-        @Inject(TableManager) private readonly _tableManager: TableManager,
-        @Inject(SheetScrollManagerService) private readonly _scrollManagerService: SheetScrollManagerService,
-        @Inject(WorkbookPermissionService) private readonly _workbookPermissionService: WorkbookPermissionService,
-        @Inject(IPermissionService) private readonly _permissionService: IPermissionService
-    ) {
-        super();
-        this._initUI();
-        this._initListener();
-        this._initTableAnchor();
-    }
-
-    private _initUI() {
-        this.disposeWithMe(
-            this._uiPartsService.registerComponent(BuiltInUIPart.CONTENT, () => connectInjector(SheetTableAnchor, this._injector))
-        );
-    }
-
-    private _initListener() {
-        this.disposeWithMe(
-            this._commandService.onCommandExecuted((command) => {
-                if (command.id === SetZoomRatioOperation.id || command.id === SetScrollOperation.id) {
-                    this._anchorVisible$.next(false);
-
-                    if (this._timer) {
-                        clearTimeout(this._timer);
-                    }
-
-                    this._timer = setTimeout(() => {
-                        this._anchorVisible$.next(true);
-                    }, 300);
-                }
-            })
-        );
-    }
-
-    private _initTableAnchor() {
-        this.disposeWithMe(
-            merge(
-                this._context.unit.activeSheet$,
-                this._sheetSkeletonManagerService.currentSkeleton$,
-                this._scrollManagerService.validViewportScrollInfo$,
-                this._tableManager.tableAdd$,
-                this._tableManager.tableDelete$,
-                this._tableManager.tableNameChanged$,
-                this._tableManager.tableRangeChanged$,
-                this._tableManager.tableThemeChanged$,
-                this._workbookPermissionService.unitPermissionInitStateChange$.pipe(filter((v) => v)),
-                this._permissionService.permissionPointUpdate$.pipe(debounceTime(300)),
-                this._anchorVisible$
-            ).subscribe(() => {
-                const isVisible = this._anchorVisible$.getValue();
-                if (!isVisible) {
-                    this._anchorPosition$.next([]);
-                    return;
-                }
-                const workbook = this._context.unit;
-                const worksheet = workbook.getActiveSheet();
-                const subUnitId = worksheet?.getSheetId();
-                const tables = this._tableManager.getTableList(this._context.unitId).filter((table) => {
-                    return table.subUnitId === subUnitId;
-                });
-                const renderUnit = this._renderManagerService.getRenderById(this._context.unitId);
-                if (!renderUnit) {
-                    this._anchorPosition$.next([]);
-                    return;
-                }
-
-                const workbookEditPermission = this._permissionService.getPermissionPoint(new WorkbookEditablePermission(workbook.getUnitId()).id)?.value;
-                if (!workbookEditPermission) {
-                    this._anchorPosition$.next([]);
-                    return;
-                }
-
-                const tableInfos = tables.reduce((acc, table) => {
-                    const { startRow, startColumn } = table.range;
-                    const sheetSkeletonManagerService = renderUnit.with(SheetSkeletonManagerService);
-                    const sheetObject = getSheetObject(this._univerInstanceService, this._renderManagerService);
-
-                    if (!sheetObject) return acc;
-
-                    const { scene } = sheetObject;
-                    const viewport = scene.getViewport(SHEET_VIEWPORT_KEY.VIEW_MAIN);
-                    if (!viewport) return acc;
-
-                    const scaleX = scene?.scaleX;
-                    const scaleY = scene?.scaleY;
-                    const scrollXY = scene?.getViewportScrollXY(viewport);
-                    if (!scaleX || !scene || !scaleY || !scrollXY) return acc;
-
-                    const skeleton = sheetSkeletonManagerService.getCurrentSkeleton();
-                    if (!skeleton) return acc;
-
-                    const position = skeleton.getNoMergeCellWithCoordByIndex(startRow, startColumn);
-
-                    const startX = convertTransformToOffsetX(position.startX, scaleX, scrollXY);
-                    // 25 is the height of the anchor, 4 is the offset
-                    const startY = convertTransformToOffsetY(position.startY, scaleY, scrollXY) - 25 - 4;
-
-                    if (startY >= -10 && startX >= 45) {
-                        acc.push({
-                            x: startX,
-                            y: startY,
-                            tableId: table.id,
-                            tableName: table.name,
-                        });
-                    }
-
-                    return acc;
-                }, [] as Array<ITableAnchorPosition>);
-
-                this._anchorPosition$.next(tableInfos);
-            })
-        );
-    }
-}
diff --git a/packages/sheets-table-ui/src/controllers/sheet-table-component.controller.ts b/packages/sheets-table-ui/src/controllers/sheet-table-component.controller.ts
--- a/packages/sheets-table-ui/src/controllers/sheet-table-component.controller.ts
+++ b/packages/sheets-table-ui/src/controllers/sheet-table-component.controller.ts
@@ -19,8 +19,9 @@ import { Disposable, IContextService, Inject } from '@univerjs/core';
 import { SheetCanvasPopManagerService } from '@univerjs/sheets-ui';
 import { ComponentManager, IDialogService } from '@univerjs/ui';
 import { distinctUntilChanged, startWith } from 'rxjs';
-import { SHEETS_TABLE_FILTER_PANEL_OPENED_KEY, UNIVER_SHEET_TABLE_FILTER_PANEL_ID } from '../const';
+import { SHEET_TABLE_RENAME_DIALOG, SHEETS_TABLE_FILTER_PANEL_OPENED_KEY, UNIVER_SHEET_TABLE_FILTER_PANEL_ID } from '../const';
 import { SheetTableFilterPanel } from '../views/components/SheetTableFilterPanel';
+import { SheetTableRenameDialog } from '../views/components/SheetTableRenameDialog';
 
 interface ITableFilterPanelInfo {
     unitId: string;
@@ -49,6 +50,26 @@ export class SheetsTableComponentController extends Disposable {
         this._currentTableFilterInfo = info;
     }
 
+    public openOrToggleFilterPanel(info: ITableFilterPanelInfo): void {
+        const opened = this._contextService.getContextValue(SHEETS_TABLE_FILTER_PANEL_OPENED_KEY);
+
+        if (opened && this._isSameFilterPanelInfo(this._currentTableFilterInfo, info)) {
+            this.closeFilterPanel();
+            return;
+        }
+
+        this.setCurrentTableFilterInfo(info);
+
+        if (opened) {
+            this._popupDisposable?.dispose();
+            this._popupDisposable = null;
+            this._openFilterPopup();
+            return;
+        }
+
+        this._contextService.setContextValue(SHEETS_TABLE_FILTER_PANEL_OPENED_KEY, true);
+    }
+
     public clearCurrentTableFilterInfo(): void {
         this._currentTableFilterInfo = null;
     }
@@ -60,6 +81,7 @@ export class SheetsTableComponentController extends Disposable {
     private _initComponents() {
         ([
             [SHEETS_TABLE_FILTER_PANEL_OPENED_KEY, SheetTableFilterPanel],
+            [SHEET_TABLE_RENAME_DIALOG, SheetTableRenameDialog],
         ] as const).forEach(([key, comp]) => {
             this.disposeWithMe(this._componentManager.register(key, comp));
         });
@@ -106,4 +128,8 @@ export class SheetsTableComponentController extends Disposable {
         this._popupDisposable = null;
         this.clearCurrentTableFilterInfo();
     }
+
+    private _isSameFilterPanelInfo(a: Nullable<ITableFilterPanelInfo>, b: ITableFilterPanelInfo): boolean {
+        return Boolean(a && a.unitId === b.unitId && a.subUnitId === b.subUnitId && a.tableId === b.tableId && a.column === b.column && a.row === b.row);
+    }
 }
diff --git a/packages/sheets-table-ui/src/controllers/sheet-table-controls-render.controller.ts b/packages/sheets-table-ui/src/controllers/sheet-table-controls-render.controller.ts
new file mode 100644
--- /dev/null
+++ b/packages/sheets-table-ui/src/controllers/sheet-table-controls-render.controller.ts
@@ -0,0 +1,480 @@
+/**
+ * Copyright 2023-present DreamNum Co., Ltd.
+ *
+ * Licensed under the Apache License, Version 2.0 (the "License");
+ * you may not use this file except in compliance with the License.
+ * You may obtain a copy of the License at
+ *
+ *     http://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+
+import type { EventState, IRange, Workbook } from '@univerjs/core';
+import type { IMouseEvent, IPointerEvent, IRenderContext, IRenderModule, SpreadsheetSkeleton } from '@univerjs/engine-render';
+import type { ITableControlHitRegion } from '../views/widgets/table-controls-util';
+import { CommandType, Disposable, fromCallback, ICommandService, Inject, Injector, IPermissionService, LocaleService, toDisposable } from '@univerjs/core';
+import { CURSOR_TYPE } from '@univerjs/engine-render';
+import { SheetRangeThemeModel, SheetsSelectionsService, WorkbookEditablePermission, WorkbookPermissionService } from '@univerjs/sheets';
+import { DeleteSheetTableCommand, SetSheetTableCommand, SheetTableInsertColumnAtCommand, SheetTableInsertRowAtCommand, TableManager } from '@univerjs/sheets-table';
+import { getTransformCoord, ISheetSelectionRenderService, SetScrollOperation, SetZoomRatioOperation, SHEET_VIEW_KEY, SheetSkeletonManagerService } from '@univerjs/sheets-ui';
+import { IDialogService, ISidebarService } from '@univerjs/ui';
+import { filter, merge } from 'rxjs';
+import { openRangeSelector } from '../commands/operations/open-table-selector.operation';
+import { SHEET_TABLE_RENAME_DIALOG, SHEET_TABLE_RENAME_DIALOG_ID, SHEET_TABLE_THEME_PANEL, SHEET_TABLE_THEME_PANEL_ID } from '../const';
+import { SheetTableControlsShape } from '../views/widgets/table-controls.shape';
+import { TABLE_CONTROL_INSERT_BUTTON_SIZE, TABLE_CONTROL_TOP_GAP_SIZE } from '../views/widgets/table-controls-util';
+import { SheetTableThemeUIController } from './sheet-table-theme-ui.controller';
+
+const TABLE_CONTROLS_LAYER_INDEX = 5002;
+const TABLE_CONTROL_GAP_ROW = 0;
+
+const TABLE_RENDER_REFRESH_COMMANDS = new Set([
+    SetScrollOperation.id,
+    SetZoomRatioOperation.id,
+]);
+
+type TopGapSnapshot = { size: number; color?: string; stripeColor?: string } | null;
+
+function isSameTopGap(left: TopGapSnapshot, right: TopGapSnapshot): boolean {
+    if (left === null || right === null) {
+        return left === right;
+    }
+
+    return left.size === right.size && left.color === right.color && left.stripeColor === right.stripeColor;
+}
+
+export class SheetTableControlsRenderController extends Disposable implements IRenderModule {
+    private readonly _shape: SheetTableControlsShape;
+    private readonly _topGapBaseBySkeleton = new WeakMap<SpreadsheetSkeleton, TopGapSnapshot>();
+
+    constructor(
+        private readonly _context: IRenderContext<Workbook>,
+        @Inject(Injector) private readonly _injector: Injector,
+        @Inject(SheetSkeletonManagerService) private readonly _sheetSkeletonManagerService: SheetSkeletonManagerService,
+        @ICommandService private readonly _commandService: ICommandService,
+        @Inject(TableManager) private readonly _tableManager: TableManager,
+        @Inject(SheetRangeThemeModel) private readonly _rangeThemeModel: SheetRangeThemeModel,
+        @Inject(WorkbookPermissionService) private readonly _workbookPermissionService: WorkbookPermissionService,
+        @Inject(IPermissionService) private readonly _permissionService: IPermissionService,
+        @Inject(SheetsSelectionsService) private readonly _sheetsSelectionsService: SheetsSelectionsService,
+        @ISheetSelectionRenderService private readonly _selectionRenderService: ISheetSelectionRenderService,
+        @Inject(SheetTableThemeUIController) private readonly _sheetTableThemeUIController: SheetTableThemeUIController,
+        @Inject(LocaleService) private readonly _localeService: LocaleService,
+        @IDialogService private readonly _dialogService: IDialogService,
+        @ISidebarService private readonly _sidebarService: ISidebarService
+    ) {
+        super();
+        this._shape = new SheetTableControlsShape(
+            'SheetTableControlsShape',
+            () => this._sheetSkeletonManagerService.getCurrentSkeleton() || null
+        );
+        this._initShape();
+        this._initRefresh();
+        this._refresh();
+    }
+
+    private _initShape(): void {
+        this._context.scene.addObjects([this._shape], TABLE_CONTROLS_LAYER_INDEX);
+        this.disposeWithMe(toDisposable(() => {
+            this._context.scene.removeObjects([this._shape]);
+        }));
+
+        this.disposeWithMe(this._shape.onPointerMove$.subscribeEvent((evt: IPointerEvent | IMouseEvent, state) => {
+            this._handlePointerMove(evt, state);
+        }));
+        this.disposeWithMe(this._shape.onPointerLeave$.subscribeEvent((_evt: IPointerEvent | IMouseEvent, state) => {
+            this._handlePointerLeave(state);
+        }));
+        this.disposeWithMe(this._shape.onPointerDown$.subscribeEvent((evt: IPointerEvent | IMouseEvent, state) => {
+            this._handlePointerDown(evt, state);
+        }));
+
+        this.disposeWithMe(this._context.components.get(SHEET_VIEW_KEY.MAIN)?.onPointerMove$.subscribeEvent((evt: IPointerEvent | IMouseEvent) => {
+            const point = this._getLocalPoint(evt);
+            const insertRegion = this._getInsertRegionFromPoint(point.x, point.y);
+            this._shape.setHoveredInsertRegion(insertRegion);
+        }) ?? toDisposable(() => {}));
+    }
+
+    private _initRefresh(): void {
+        const commandExecuted$ = fromCallback(this._commandService.onCommandExecuted.bind(this._commandService))
+            .pipe(filter(([command]) => {
+                if (command.type === CommandType.OPERATION && TABLE_RENDER_REFRESH_COMMANDS.has(command.id)) {
+                    this._closeFloatingControls();
+                    return true;
+                }
+
+                return command.type === CommandType.MUTATION || command.type === CommandType.COMMAND;
+            }));
+
+        this.disposeWithMe(merge(
+            this._context.unit.activeSheet$,
+            this._sheetSkeletonManagerService.currentSkeleton$,
+            this._tableManager.tableAdd$,
+            this._tableManager.tableDelete$,
+            this._tableManager.tableNameChanged$,
+            this._tableManager.tableRangeChanged$,
+            this._tableManager.tableThemeChanged$,
+            this._sheetTableThemeUIController.refreshTable$,
+            this._workbookPermissionService.unitPermissionInitStateChange$,
+            this._permissionService.permissionPointUpdate$,
+            this._sheetsSelectionsService.selectionChanged$,
+            commandExecuted$
+        ).subscribe(() => {
+            this._closeFloatingControls();
+            this._refresh();
+        }));
+    }
+
+    private _refresh(): void {
+        const skeleton = this._sheetSkeletonManagerService.getCurrentSkeleton();
+        const worksheet = this._context.unit.getActiveSheet();
+
+        if (!skeleton || !worksheet || !this._canEditWorkbook()) {
+            this._shape.setItems([]);
+            this._shape.refreshBounds();
+            this._context.scene.makeDirty();
+            return;
+        }
+
+        this._syncTopTableGap(skeleton);
+        this._shape.setMenuLabels({
+            rename: this._localeService.t('sheets-table.rename'),
+            'update-range': this._localeService.t('sheets-table.updateRange'),
+            'set-theme': this._localeService.t('sheets-table.setTheme'),
+            delete: this._localeService.t('sheets-table.removeTable'),
+        });
+
+        const unitId = this._context.unit.getUnitId();
+        const subUnitId = worksheet.getSheetId();
+        const items = this._tableManager.getTablesBySubunitId(unitId, subUnitId).map((table) => {
+            const rangeTheme = this._rangeThemeModel.getRangeThemeStyle(unitId, table.getTableStyleId());
+            return {
+                tableId: table.getId(),
+                tableName: table.getDisplayName(),
+                range: table.getRange(),
+                fill: rangeTheme?.getHeaderRowStyle()?.bg?.rgb ?? 'rgb(53,91,183)',
+                text: rangeTheme?.getHeaderRowStyle()?.cl?.rgb ?? 'rgb(255,255,255)',
+            };
+        });
+
+        this._shape.setItems(items);
+        this._shape.refreshBounds();
+        this._shape.makeDirty(true);
+        this._context.scene.makeDirty();
+    }
+
+    private _canEditWorkbook(): boolean {
+        const unitId = this._context.unit.getUnitId();
+        const workbookEditPermission = this._permissionService.getPermissionPoint(new WorkbookEditablePermission(unitId).id)?.value;
+        return workbookEditPermission !== false;
+    }
+
+    private _handlePointerMove(evt: IPointerEvent | IMouseEvent, state: EventState): void {
+        const point = this._getLocalPoint(evt);
+        const hit = this._shape.hitTest(point.x, point.y);
+        const insertRegion = this._isInsertHit(hit) ? hit : hit ? null : this._getInsertRegionFromPoint(point.x, point.y);
+        const activeHit = hit ?? insertRegion;
+
+        this._shape.setHoveredRegion(this._isInsertHit(hit) ? null : hit);
+        this._shape.setHoveredInsertRegion(insertRegion);
+
+        if (activeHit) {
+            state.stopPropagation();
+            this._context.scene.setCursor(CURSOR_TYPE.POINTER);
+        } else {
+            this._context.scene.resetCursor();
+        }
+    }
+
+    private _isInsertHit(hit: ITableControlHitRegion | null): hit is ITableControlHitRegion {
+        return hit?.type === 'insert-row' || hit?.type === 'insert-column';
+    }
+
+    private _handlePointerLeave(state: EventState): void {
+        state.stopPropagation();
+        this._shape.setHoveredRegion(null);
+        this._shape.setHoveredInsertRegion(null);
+        this._context.scene.resetCursor();
+    }
+
+    private _handlePointerDown(evt: IPointerEvent | IMouseEvent, state: EventState): void {
+        if (evt.button === 2) {
+            return;
+        }
+
+        const point = this._getLocalPoint(evt);
+        const hit = this._shape.hitTest(point.x, point.y) ?? this._getInsertRegionFromPoint(point.x, point.y);
+        if (!hit) {
+            this._closeFloatingControls();
+            return;
+        }
+
+        state.stopPropagation();
+        evt.stopPropagation();
+        evt.preventDefault();
+        this._handleHit(hit);
+    }
+
+    private _handleHit(hit: ITableControlHitRegion): void {
+        const worksheet = this._context.unit.getActiveSheet();
+        if (!worksheet) {
+            return;
+        }
+
+        const unitId = this._context.unit.getUnitId();
+        const subUnitId = worksheet.getSheetId();
+
+        if (hit.type === 'anchor-menu-toggle' || hit.type === 'anchor-main') {
+            this._shape.setOpenedMenuTableId(this._shape.getOpenedMenuTableId() === hit.tableId ? null : hit.tableId);
+            return;
+        }
+
+        if (hit.type === 'insert-row') {
+            this._commandService.executeCommand(SheetTableInsertRowAtCommand.id, {
+                unitId,
+                subUnitId,
+                tableId: hit.tableId,
+                index: hit.index,
+                count: 1,
+            });
+            this._closeFloatingControls();
+            return;
+        }
+
+        if (hit.type === 'insert-column') {
+            this._commandService.executeCommand(SheetTableInsertColumnAtCommand.id, {
+                unitId,
+                subUnitId,
+                tableId: hit.tableId,
+                index: hit.index,
+                count: 1,
+            });
+            this._closeFloatingControls();
+            return;
+        }
+
+        if (hit.type !== 'menu-item') {
+            return;
+        }
+
+        switch (hit.action) {
+            case 'rename':
+                this._openRenameDialog(unitId, hit.tableId);
+                break;
+            case 'update-range':
+                this._openRangeSelector(unitId, subUnitId, hit.tableId);
+                break;
+            case 'set-theme':
+                this._openThemePanel(unitId, subUnitId, hit.tableId);
+                break;
+            case 'delete':
+                this._commandService.executeCommand(DeleteSheetTableCommand.id, {
+                    tableId: hit.tableId,
+                    subUnitId,
+                    unitId,
+                });
+                break;
+        }
+
+        this._closeFloatingControls();
+    }
+
+    private _openRenameDialog(unitId: string, tableId: string): void {
+        this._dialogService.open({
+            id: SHEET_TABLE_RENAME_DIALOG_ID,
+            title: { title: this._localeService.t('sheets-table.rename') },
+            draggable: true,
+            destroyOnClose: true,
+            mask: true,
+            children: {
+                label: {
+                    name: SHEET_TABLE_RENAME_DIALOG,
+                    props: {
+                        unitId,
+                        tableId,
+                        onClose: () => this._dialogService.close(SHEET_TABLE_RENAME_DIALOG_ID),
+                    },
+                },
+            },
+            width: 360,
+            onClose: () => this._dialogService.close(SHEET_TABLE_RENAME_DIALOG_ID),
+        });
+    }
+
+    private async _openRangeSelector(unitId: string, subUnitId: string, tableId: string): Promise<void> {
+        const table = this._tableManager.getTableById(unitId, tableId);
+        if (!table) {
+            return;
+        }
+
+        const selection = await openRangeSelector(this._injector, unitId, subUnitId, table.getRange(), tableId);
+        if (!selection) {
+            return;
+        }
+
+        this._commandService.executeCommand(SetSheetTableCommand.id, {
+            tableId,
+            unitId,
+            updateRange: {
+                newRange: selection.range,
+            },
+        });
+    }
+
+    private _openThemePanel(unitId: string, subUnitId: string, tableId: string): void {
+        const table = this._tableManager.getTableById(unitId, tableId);
+        if (!table) {
+            return;
+        }
+
+        this._sidebarService.open({
+            id: SHEET_TABLE_THEME_PANEL_ID,
+            header: { title: this._localeService.t('sheets-table.tableStyle') },
+            children: {
+                label: SHEET_TABLE_THEME_PANEL,
+                oldConfig: table.getTableConfig(),
+                unitId,
+                subUnitId,
+                tableId,
+            } as any,
+            width: 330,
+        });
+    }
+
+    private _getInsertRegionFromPoint(x: number, y: number): ITableControlHitRegion | null {
+        const skeleton = this._sheetSkeletonManagerService.getCurrentSkeleton();
+        const worksheet = this._context.unit.getActiveSheet();
+        if (!skeleton || !worksheet) {
+            return null;
+        }
+
+        const unitId = this._context.unit.getUnitId();
+        const subUnitId = worksheet.getSheetId();
+        const tables = this._tableManager.getTablesBySubunitId(unitId, subUnitId);
+
+        for (const table of tables) {
+            const range = table.getRange();
+            const tableBounds = this._getRangeBounds(skeleton, range);
+            if (x < tableBounds.left || x > tableBounds.right || y < tableBounds.top || y > tableBounds.bottom) {
+                continue;
+            }
+
+            const headerBounds = this._getRangeBounds(skeleton, {
+                ...range,
+                endRow: range.startRow,
+            });
+
+            if (y > headerBounds.bottom) {
+                for (let row = range.startRow + 1; row <= range.endRow; row++) {
+                    const cell = skeleton.getNoMergeCellWithCoordByIndex(row, range.startColumn);
+                    if (y >= cell.startY && y <= cell.endY) {
+                        return {
+                            type: 'insert-row',
+                            tableId: table.getId(),
+                            index: row + 1,
+                            left: tableBounds.left - TABLE_CONTROL_INSERT_BUTTON_SIZE / 2,
+                            top: cell.endY - TABLE_CONTROL_INSERT_BUTTON_SIZE / 2,
+                            width: TABLE_CONTROL_INSERT_BUTTON_SIZE,
+                            height: TABLE_CONTROL_INSERT_BUTTON_SIZE,
+                        };
+                    }
+                }
+            }
+        }
+
+        return null;
+    }
+
+    private _getRangeBounds(skeleton: SpreadsheetSkeleton, range: IRange): { left: number; top: number; right: number; bottom: number } {
+        const startCell = skeleton.getNoMergeCellWithCoordByIndex(range.startRow, range.startColumn);
+        const endCell = skeleton.getNoMergeCellWithCoordByIndex(range.endRow, range.endColumn);
+        return {
+            left: startCell.startX,
+            top: startCell.startY,
+            right: endCell.endX,
+            bottom: endCell.endY,
+        };
+    }
+
+    private _syncTopTableGap(skeleton: SpreadsheetSkeleton): void {
+        const worksheet = this._context.unit.getActiveSheet();
+        if (!worksheet) {
+            return;
+        }
+
+        const unitId = this._context.unit.getUnitId();
+        const subUnitId = worksheet.getSheetId();
+        const hasTopTable = this._tableManager
+            .getTablesBySubunitId(unitId, subUnitId)
+            .some((table) => table.getRange().startRow === 0);
+        const current = skeleton.gapConfig;
+        const rowGaps = { ...current.rowGaps };
+        const previousTopGap = rowGaps[TABLE_CONTROL_GAP_ROW] ? { ...rowGaps[TABLE_CONTROL_GAP_ROW] } : null;
+        let shouldSync = false;
+
+        if (hasTopTable) {
+            if (!this._topGapBaseBySkeleton.has(skeleton)) {
+                this._topGapBaseBySkeleton.set(
+                    skeleton,
+                    rowGaps[TABLE_CONTROL_GAP_ROW] ? { ...rowGaps[TABLE_CONTROL_GAP_ROW] } : null
+                );
+            }
+
+            const baseGap = this._topGapBaseBySkeleton.get(skeleton);
+            rowGaps[TABLE_CONTROL_GAP_ROW] = {
+                ...(baseGap ?? rowGaps[TABLE_CONTROL_GAP_ROW]),
+                size: (baseGap?.size ?? 0) + TABLE_CONTROL_TOP_GAP_SIZE,
+            };
+            shouldSync = true;
+        } else if (this._topGapBaseBySkeleton.has(skeleton)) {
+            const baseGap = this._topGapBaseBySkeleton.get(skeleton);
+            if (baseGap) {
+                rowGaps[TABLE_CONTROL_GAP_ROW] = { ...baseGap };
+            } else {
+                delete rowGaps[TABLE_CONTROL_GAP_ROW];
+            }
+            this._topGapBaseBySkeleton.delete(skeleton);
+            shouldSync = true;
+        }
+
+        if (!shouldSync) {
+            return;
+        }
+
+        const nextTopGap = rowGaps[TABLE_CONTROL_GAP_ROW] ? { ...rowGaps[TABLE_CONTROL_GAP_ROW] } : null;
+        if (isSameTopGap(previousTopGap, nextTopGap)) {
+            return;
+        }
+
+        skeleton.setGapConfig({ ...current, rowGaps });
+        this._refreshSelections();
+    }
+
+    private _refreshSelections(): void {
+        this._selectionRenderService.resetSelectionsByModelData(this._sheetsSelectionsService.getCurrentSelections());
+    }
+
+    private _closeFloatingControls(): void {
+        this._shape.setOpenedMenuTableId(null);
+        this._shape.setHoveredInsertRegion(null);
+        this._shape.setHoveredRegion(null);
+    }
+
+    private _getLocalPoint(evt: IPointerEvent | IMouseEvent): { x: number; y: number } {
+        const skeleton = this._sheetSkeletonManagerService.getCurrentSkeleton();
+        if (skeleton) {
+            return getTransformCoord(evt.offsetX, evt.offsetY, this._context.scene, skeleton);
+        }
+
+        return {
+            x: evt.offsetX,
+            y: evt.offsetY,
+        };
+    }
+}
diff --git a/packages/sheets-table-ui/src/controllers/sheet-table-filter-button-render.controller.ts b/packages/sheets-table-ui/src/controllers/sheet-table-filter-button-render.controller.ts
--- a/packages/sheets-table-ui/src/controllers/sheet-table-filter-button-render.controller.ts
+++ b/packages/sheets-table-ui/src/controllers/sheet-table-filter-button-render.controller.ts
@@ -19,7 +19,7 @@ import type { IRenderContext, IRenderModule, SpreadsheetSkeleton } from '@univer
 import type { ITableRangeWithState } from '@univerjs/sheets-table';
 import type { ISheetsTableFilterButtonShapeProps } from '../views/widgets/table-filter-button.shape';
 import { ICommandService, Inject, Injector, InterceptorEffectEnum, RxDisposable, VerticalAlign } from '@univerjs/core';
-import { INTERCEPTOR_POINT, SetVerticalTextAlignCommand, SheetInterceptorService } from '@univerjs/sheets';
+import { INTERCEPTOR_POINT, SetVerticalTextAlignCommand, SheetInterceptorService, SheetRangeThemeModel } from '@univerjs/sheets';
 import { TableManager } from '@univerjs/sheets-table';
 import { getCoordByCell, SheetSkeletonManagerService } from '@univerjs/sheets-ui';
 import { map, merge, of, startWith, switchMap, takeUntil } from 'rxjs';
@@ -64,6 +64,7 @@ export class SheetsTableFilterButtonRenderController extends RxDisposable implem
         @Inject(SheetSkeletonManagerService) private readonly _sheetSkeletonManagerService: SheetSkeletonManagerService,
         @Inject(SheetInterceptorService) private readonly _sheetInterceptorService: SheetInterceptorService,
         @Inject(TableManager) private _tableManager: TableManager,
+        @Inject(SheetRangeThemeModel) private readonly _rangeThemeModel: SheetRangeThemeModel,
         @ICommandService private readonly _commandService: ICommandService
     ) {
         super();
@@ -155,6 +156,10 @@ export class SheetsTableFilterButtonRenderController extends RxDisposable implem
 
         for (const { range, states, tableId } of tableFilterRanges) {
             const { startRow, startColumn, endColumn } = range;
+            const table = this._tableManager.getTableById(unitId, tableId);
+            const headerStyle = table ? this._rangeThemeModel.getRangeThemeStyle(unitId, table.getTableStyleId())?.getHeaderRowStyle() : null;
+            const iconColor = headerStyle?.cl?.rgb ?? '#fff';
+            const hoverIconColor = headerStyle?.bg?.rgb ?? '#202124';
             this._interceptCellContent(unitId, worksheetId, range);
             for (let col = startColumn; col <= endColumn; col++) {
                 const key = `sheets-table-filter-button-${startRow}-${col}`;
@@ -176,6 +181,9 @@ export class SheetsTableFilterButtonRenderController extends RxDisposable implem
                     height: FILTER_ICON_SIZE,
                     width: FILTER_ICON_SIZE,
                     zIndex: SHEETS_FILTER_BUTTON_Z_INDEX,
+                    iconColor,
+                    hoverBackground: iconColor,
+                    hoverIconColor,
                     cellHeight,
                     cellWidth,
                     filterParams: { unitId, subUnitId: worksheetId, row: startRow, col, buttonState: state, tableId },
diff --git a/packages/sheets-table-ui/src/locale/ca-ES.ts b/packages/sheets-table-ui/src/locale/ca-ES.ts
--- a/packages/sheets-table-ui/src/locale/ca-ES.ts
+++ b/packages/sheets-table-ui/src/locale/ca-ES.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: 'Taula',
         selectRange: 'Selecciona el rang de la taula',
         rename: 'Reanomena la taula',
+        renamePlaceholder: 'Enter table name',
         updateRange: 'Actualitza el rang de la taula',
         tableRangeWithMergeError: 'El rang de la taula no es pot superposar amb cel·les combinades',
         tableRangeWithOtherTableError: 'El rang de la taula no es pot superposar amb altres taules',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: 'Columna',
         tablePrefix: 'Taula',
         tableNameError: 'El nom de la taula no pot contenir espais, no pot començar amb un número i no pot ser idèntic a un nom de taula existent',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: 'Insereix una taula',
diff --git a/packages/sheets-table-ui/src/locale/en-US.ts b/packages/sheets-table-ui/src/locale/en-US.ts
--- a/packages/sheets-table-ui/src/locale/en-US.ts
+++ b/packages/sheets-table-ui/src/locale/en-US.ts
@@ -19,6 +19,7 @@ const locale = {
         title: 'Table',
         selectRange: 'Select Table Range',
         rename: 'Rename Table',
+        renamePlaceholder: 'Enter table name',
         updateRange: 'Update Table Range',
         tableRangeWithMergeError: 'Table range cannot overlap with merged cells',
         tableRangeWithOtherTableError: 'Table range cannot overlap with other tables',
@@ -39,6 +40,11 @@ const locale = {
         columnPrefix: 'Column',
         tablePrefix: 'Table',
         tableNameError: 'Table name cannot contain spaces, cannot start with a number, and cannot be identical to an existing table name',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: 'Insert Table',
diff --git a/packages/sheets-table-ui/src/locale/es-ES.ts b/packages/sheets-table-ui/src/locale/es-ES.ts
--- a/packages/sheets-table-ui/src/locale/es-ES.ts
+++ b/packages/sheets-table-ui/src/locale/es-ES.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: 'Tabla',
         selectRange: 'Seleccionar rango de tabla',
         rename: 'Renombrar tabla',
+        renamePlaceholder: 'Enter table name',
         updateRange: 'Actualizar rango de tabla',
         tableRangeWithMergeError: 'El rango de la tabla no puede superponerse con celdas combinadas',
         tableRangeWithOtherTableError: 'El rango de la tabla no puede superponerse con otras tablas',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: 'Columna',
         tablePrefix: 'Tabla',
         tableNameError: 'El nombre de la tabla no puede contener espacios, no puede comenzar con un número y no puede ser idéntico a un nombre de tabla existente',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: 'Insertar tabla',
diff --git a/packages/sheets-table-ui/src/locale/fa-IR.ts b/packages/sheets-table-ui/src/locale/fa-IR.ts
--- a/packages/sheets-table-ui/src/locale/fa-IR.ts
+++ b/packages/sheets-table-ui/src/locale/fa-IR.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: 'جدول',
         selectRange: 'انتخاب محدوده جدول',
         rename: 'تغییر نام جدول',
+        renamePlaceholder: 'Enter table name',
         updateRange: 'به‌روزرسانی محدوده جدول',
         tableRangeWithMergeError: 'محدوده جدول نمی‌تواند با سلول‌های ادغام‌شده همپوشانی داشته باشد',
         tableRangeWithOtherTableError: 'محدوده جدول نمی‌تواند با جداول دیگر همپوشانی داشته باشد',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: 'ستون',
         tablePrefix: 'جدول',
         tableNameError: 'لا يمكن أن يحتوي اسم الجدول على مسافات، ولا يمكن أن يبدأ برقم، ولا يمكن أن يتكرر مع أسماء الجداول الموجودة',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: 'درج جدول',
diff --git a/packages/sheets-table-ui/src/locale/fr-FR.ts b/packages/sheets-table-ui/src/locale/fr-FR.ts
--- a/packages/sheets-table-ui/src/locale/fr-FR.ts
+++ b/packages/sheets-table-ui/src/locale/fr-FR.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: 'Tableau',
         selectRange: 'Sélectionner la plage du tableau',
         rename: 'Renommer le tableau',
+        renamePlaceholder: 'Enter table name',
         updateRange: 'Mettre à jour la plage du tableau',
         tableRangeWithMergeError: 'La plage du tableau ne peut pas chevaucher des cellules fusionnées',
         tableRangeWithOtherTableError: 'La plage du tableau ne peut pas chevaucher d\'autres tableaux',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: 'Colonne',
         tablePrefix: 'Tableau',
         tableNameError: 'Le nom du tableau ne peut pas contenir d\'espaces, ne peut pas commencer par un chiffre et ne peut pas être identique à un nom de tableau existant',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: 'Insérer un tableau',
diff --git a/packages/sheets-table-ui/src/locale/ja-JP.ts b/packages/sheets-table-ui/src/locale/ja-JP.ts
--- a/packages/sheets-table-ui/src/locale/ja-JP.ts
+++ b/packages/sheets-table-ui/src/locale/ja-JP.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: '表',
         selectRange: '表の範囲を選択',
         rename: '表の名前を変更',
+        renamePlaceholder: 'Enter table name',
         updateRange: '表の範囲を更新',
         tableRangeWithMergeError: '表の範囲は結合セルと重複できません',
         tableRangeWithOtherTableError: '表の範囲は他の表と重複できません',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: '列',
         tablePrefix: '表',
         tableNameError: '表の名前は空白を含めることはできず、数字で始めることはできず、既存の表名と重複できません',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: '表を挿入',
diff --git a/packages/sheets-table-ui/src/locale/ko-KR.ts b/packages/sheets-table-ui/src/locale/ko-KR.ts
--- a/packages/sheets-table-ui/src/locale/ko-KR.ts
+++ b/packages/sheets-table-ui/src/locale/ko-KR.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: '표',
         selectRange: '표 범위 선택',
         rename: '표 이름 바꾸기',
+        renamePlaceholder: 'Enter table name',
         updateRange: '표 범위 업데이트',
         tableRangeWithMergeError: '표 범위는 병합된 셀과 겹칠 수 없습니다',
         tableRangeWithOtherTableError: '표 범위는 다른 표와 겹칠 수 없습니다',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: '열',
         tablePrefix: '표',
         tableNameError: '표 이름은 공백을 포함할 수 없으며 숫자로 시작할 수 없고 기존 표 이름과 중복될 수 없습니다',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: '표 삽입',
diff --git a/packages/sheets-table-ui/src/locale/ru-RU.ts b/packages/sheets-table-ui/src/locale/ru-RU.ts
--- a/packages/sheets-table-ui/src/locale/ru-RU.ts
+++ b/packages/sheets-table-ui/src/locale/ru-RU.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: 'Таблица',
         selectRange: 'Выбрать диапазон таблицы',
         rename: 'Переименовать таблицу',
+        renamePlaceholder: 'Enter table name',
         updateRange: 'Обновить диапазон таблицы',
         tableRangeWithMergeError: 'Диапазон таблицы не может перекрываться с объединенными ячейками',
         tableRangeWithOtherTableError: 'Диапазон таблицы не может перекрываться с другими таблицами',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: 'Столбец',
         tablePrefix: 'Таблица',
         tableNameError: 'Имя таблицы не может содержать пробелы, не может начинаться с цифры и не может совпадать с именем существующей таблицы',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: 'Вставить таблицу',
diff --git a/packages/sheets-table-ui/src/locale/sk-SK.ts b/packages/sheets-table-ui/src/locale/sk-SK.ts
--- a/packages/sheets-table-ui/src/locale/sk-SK.ts
+++ b/packages/sheets-table-ui/src/locale/sk-SK.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: 'Tabuľka',
         selectRange: 'Vyberte rozsah tabuľky',
         rename: 'Premenovať tabuľku',
+        renamePlaceholder: 'Enter table name',
         updateRange: 'Aktualizovať rozsah tabuľky',
         tableRangeWithMergeError: 'Rozsah tabuľky sa nemôže prekrývať so zlúčenými bunkami',
         tableRangeWithOtherTableError: 'Rozsah tabuľky sa nemôže prekrývať s inými tabuľkami',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: 'Stĺpec',
         tablePrefix: 'Tabuľka',
         tableNameError: 'Názov tabuľky nesmie obsahovať medzery, nesmie začínať číslom a nesmie byť zhodný s existujúcim názvom tabuľky',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: 'Vložiť tabuľku',
diff --git a/packages/sheets-table-ui/src/locale/vi-VN.ts b/packages/sheets-table-ui/src/locale/vi-VN.ts
--- a/packages/sheets-table-ui/src/locale/vi-VN.ts
+++ b/packages/sheets-table-ui/src/locale/vi-VN.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: 'Bảng',
         selectRange: 'Chọn phạm vi bảng',
         rename: 'Đổi tên bảng',
+        renamePlaceholder: 'Enter table name',
         updateRange: 'Cập nhật phạm vi bảng',
         tableRangeWithMergeError: 'Phạm vi bảng không thể chồng lấp với các ô đã được hợp nhất',
         tableRangeWithOtherTableError: 'Phạm vi bảng không thể chồng lấp với các bảng khác',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: 'Cột',
         tablePrefix: 'Bảng',
         tableNameError: 'Tên bảng không thể chứa khoảng trắng, không được bắt đầu bằng số và không được trùng với tên bảng đã có',
+        columnMenu: {
+            'insert-left': 'Insert 1 table column left',
+            'insert-right': 'Insert 1 table column right',
+            delete: 'Delete table column',
+        },
 
         insert: {
             main: 'Chèn bảng',
diff --git a/packages/sheets-table-ui/src/locale/zh-CN.ts b/packages/sheets-table-ui/src/locale/zh-CN.ts
--- a/packages/sheets-table-ui/src/locale/zh-CN.ts
+++ b/packages/sheets-table-ui/src/locale/zh-CN.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: '表格',
         selectRange: '选择表格范围',
         rename: '重命名表格',
+        renamePlaceholder: '输入表格名称',
         updateRange: '更新表格范围',
         tableRangeWithMergeError: '表格范围不能与合并单元格重叠',
         tableRangeWithOtherTableError: '表格范围不能与其他表格重叠',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: '列',
         tablePrefix: '表格',
         tableNameError: '表格名称不能包含空格， 不能以数字开头，不能和已有表格名称重复',
+        columnMenu: {
+            'insert-left': '向左插入 1 个表格列',
+            'insert-right': '向右插入 1 个表格列',
+            delete: '删除表格列',
+        },
 
         insert: {
             main: '表格插入',
diff --git a/packages/sheets-table-ui/src/locale/zh-TW.ts b/packages/sheets-table-ui/src/locale/zh-TW.ts
--- a/packages/sheets-table-ui/src/locale/zh-TW.ts
+++ b/packages/sheets-table-ui/src/locale/zh-TW.ts
@@ -21,6 +21,7 @@ const locale: typeof enUS = {
         title: '表格',
         selectRange: '選擇表格範圍',
         rename: '重命名表格',
+        renamePlaceholder: 'Enter table name',
         updateRange: '更新表格範圍',
         tableRangeWithMergeError: '表格範圍不能與合併儲存格重疊',
         tableRangeWithOtherTableError: '表格範圍不能與其他表格重疊',
@@ -41,6 +42,11 @@ const locale: typeof enUS = {
         columnPrefix: '列',
         tablePrefix: '表格',
         tableNameError: '表格名稱不能包含空格， 不能以數字開頭，不能和已有表格名稱重複',
+        columnMenu: {
+            'insert-left': '向左插入 1 個表格欄',
+            'insert-right': '向右插入 1 個表格欄',
+            delete: '刪除表格欄',
+        },
 
         insert: {
             main: '表格插入',
diff --git a/packages/sheets-table-ui/src/plugin.ts b/packages/sheets-table-ui/src/plugin.ts
--- a/packages/sheets-table-ui/src/plugin.ts
+++ b/packages/sheets-table-ui/src/plugin.ts
@@ -24,7 +24,7 @@ import { OpenTableFilterPanelOperation } from './commands/operations/open-table-
 import { OpenTableSelectorOperation } from './commands/operations/open-table-selector.operation';
 import { defaultPluginConfig, SHEETS_TABLE_UI_PLUGIN_CONFIG_KEY } from './config/config';
 import { PLUGIN_NAME } from './const';
-import { SheetTableAnchorController } from './controllers/sheet-table-anchor.controller';
+import { SheetTableControlsRenderController } from './controllers/sheet-table-controls-render.controller';
 import { SheetsTableComponentController } from './controllers/sheet-table-component.controller';
 import { SheetsTableFilterButtonRenderController } from './controllers/sheet-table-filter-button-render.controller';
 import { SheetsTableRenderController } from './controllers/sheet-table-render.controller';
@@ -87,13 +87,14 @@ export class UniverSheetsTableUIPlugin extends Plugin {
     }
 
     private _registerRenderModules(): void {
-        const renderDependencies: Dependency[] = [
-            [SheetsTableFilterButtonRenderController],
-            [SheetsTableRenderController],
-        ];
+        const renderDependencies: Dependency[] = [];
         if (this._config.hideAnchor !== true) {
-            renderDependencies.push([SheetTableAnchorController]);
+            renderDependencies.push([SheetTableControlsRenderController]);
         }
+        renderDependencies.push(
+            [SheetsTableFilterButtonRenderController],
+            [SheetsTableRenderController]
+        );
 
         renderDependencies.forEach((m) => {
             this.disposeWithMe(this._renderManagerService.registerRenderModule(UniverInstanceType.UNIVER_SHEET, m));
diff --git a/packages/sheets-table-ui/src/views/components/SheetTableAnchor.tsx b/packages/sheets-table-ui/src/views/components/SheetTableAnchor.tsx
deleted file mode 100644
--- a/packages/sheets-table-ui/src/views/components/SheetTableAnchor.tsx
+++ /dev/null
@@ -1,277 +0,0 @@
-/**
- * Copyright 2023-present DreamNum Co., Ltd.
- *
- * Licensed under the Apache License, Version 2.0 (the "License");
- * you may not use this file except in compliance with the License.
- * You may obtain a copy of the License at
- *
- *     http://www.apache.org/licenses/LICENSE-2.0
- *
- * Unless required by applicable law or agreed to in writing, software
- * distributed under the License is distributed on an "AS IS" BASIS,
- * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
- * See the License for the specific language governing permissions and
- * limitations under the License.
- */
-
-import type { IUniverSheetsTableUIConfig } from '../../config/config';
-import { cellToRange, ICommandService, IConfigService, Injector, IUniverInstanceService, LocaleService, Rectangle } from '@univerjs/core';
-import { borderClassName, clsx, Dropdown, Input } from '@univerjs/design';
-import { DeleteIcon, GridOutlineIcon, MoreDownIcon, PaintBucketDoubleIcon, RenameIcon } from '@univerjs/icons';
-import { getSheetCommandTarget, SheetRangeThemeModel, SheetsSelectionsService, WorkbookPermissionService } from '@univerjs/sheets';
-import { DeleteSheetTableCommand, SetSheetTableCommand, TableManager } from '@univerjs/sheets-table';
-import { ISidebarService, useDependency, useObservable } from '@univerjs/ui';
-import { useEffect, useState } from 'react';
-import { openRangeSelector } from '../../commands/operations/open-table-selector.operation';
-import { SHEETS_TABLE_UI_PLUGIN_CONFIG_KEY } from '../../config/config';
-import { SHEET_TABLE_THEME_PANEL, SHEET_TABLE_THEME_PANEL_ID } from '../../const';
-import { SheetTableAnchorController } from '../../controllers/sheet-table-anchor.controller';
-import { SheetTableThemeUIController } from '../../controllers/sheet-table-theme-ui.controller';
-
-export const SheetTableAnchor = () => {
-    const [inputFocusId, setInputFocusId] = useState<string>('');
-    const [inputValue, setInputValue] = useState<string>('');
-    const sidebarService = useDependency(ISidebarService);
-    const [openStates, setOpenStates] = useState<Record<string, boolean>>({});
-    const injector = useDependency(Injector);
-    const sheetTableAnchor = useDependency(SheetTableAnchorController);
-    const anchorPosition = useObservable(sheetTableAnchor.anchorPosition$);
-    const commandService = useDependency(ICommandService);
-    const univerInstanceService = useDependency(IUniverInstanceService);
-    const workbookPermissionService = useDependency(WorkbookPermissionService);
-    const workbookPermissionInitState = useObservable(workbookPermissionService.unitPermissionInitStateChange$, false);
-    const tableManager = useDependency(TableManager);
-    const rangeThemeModel = useDependency(SheetRangeThemeModel);
-    const sheetTableThemeUIController = useDependency(SheetTableThemeUIController);
-    const tableRefresh$ = useObservable(sheetTableThemeUIController.refreshTable$);
-    const localeService = useDependency(LocaleService);
-    const sheetsSelectionService = useDependency(SheetsSelectionsService);
-    const selections = useObservable(sheetsSelectionService.selectionChanged$, [{ range: cellToRange(0, 0), primary: null }]);
-
-    const [, setRefresh] = useState(Math.random());
-    const configService = useDependency(IConfigService);
-    const tableConfig = configService.getConfig<IUniverSheetsTableUIConfig>(SHEETS_TABLE_UI_PLUGIN_CONFIG_KEY);
-    const anchorHeight = tableConfig?.anchorHeight ?? 24;
-    const anchorBackgroundColor = tableConfig?.anchorBackgroundColor ?? 'rgb(53,91,183)';
-
-    const updateOpenState = (tableId: string, isOpen: boolean) => {
-        setOpenStates((prev) => ({
-            ...prev,
-            [tableId]: isOpen,
-        }));
-    };
-
-    useEffect(() => {
-        setRefresh(Math.random());
-    }, [tableRefresh$]);
-
-    if (!anchorPosition?.length) {
-        return null;
-    }
-
-    const target = getSheetCommandTarget(univerInstanceService);
-
-    if (!target) return null;
-
-    const { unitId, subUnitId } = target;
-
-    const handleChangeTableName = (tableId: string, name: string) => {
-        const originName = tableManager.getTableById(unitId, tableId)?.getDisplayName();
-        if (originName === name) {
-            setInputFocusId('');
-            setInputValue('');
-            return;
-        }
-        commandService.executeCommand(SetSheetTableCommand.id, {
-            tableId,
-            unitId,
-            name,
-        });
-        setInputValue('');
-        setInputFocusId('');
-    };
-
-    const handleChangeRange = async (tableId: string) => {
-        const table = tableManager.getTableById(unitId, tableId);
-        if (!table) return;
-        const range = table.getRange();
-        const selection = await openRangeSelector(injector, unitId, subUnitId, range, tableId);
-        if (!selection) return;
-        commandService.executeCommand(SetSheetTableCommand.id, {
-            tableId,
-            unitId,
-            updateRange: {
-                newRange: selection.range,
-            },
-        });
-    };
-
-    if (!workbookPermissionInitState) {
-        return null;
-    }
-
-    return (
-        <div className="univer-absolute univer-z-50 univer-size-0">
-            {anchorPosition.map((item) => {
-                const table = tableManager.getTableById(unitId, item.tableId);
-                if (!table) return null;
-                const rangeTheme = rangeThemeModel.getRangeThemeStyle(unitId, table.getTableStyleId());
-                const headerBgColor = rangeTheme?.getHeaderRowStyle()?.bg?.rgb ?? anchorBackgroundColor;
-                const headerCl = rangeTheme?.getHeaderRowStyle()?.cl?.rgb ?? 'rgb(255, 255, 255)';
-                const headerTextColor = headerCl;
-                const tableRange = table.getRange();
-
-                if (!selections?.length) {
-                    return null;
-                }
-
-                const lastSelection = selections[selections.length - 1];
-                const lastRange = lastSelection.range;
-
-                const overlap = Rectangle.intersects(tableRange, lastRange);
-                const shouldHidden = !overlap && item.y <= 20;
-
-                return (
-                    <div
-                        key={item.tableId}
-                        className={clsx(`
-                          univer-shadow-xs univer-absolute univer-box-border univer-cursor-pointer univer-items-center
-                          univer-rounded-xl univer-px-2
-                        `, borderClassName, {
-                            'univer-flex': !shouldHidden,
-                            'univer-hidden': shouldHidden,
-                        })}
-                        style={{
-                            left: item.x,
-                            top: Math.max(item.y, 0),
-                            backgroundColor: headerBgColor,
-                            color: headerTextColor,
-                            borderWidth: '0.5px',
-                            height: anchorHeight ? `${anchorHeight}px` : '24px',
-                        }}
-                    >
-                        <div className="univer-text-nowrap">
-                            {inputFocusId === item.tableId
-                                ? (
-                                    <Input
-                                        className="univer-h-[18px] univer-min-w-16 univer-rounded-none"
-                                        inputClass="univer-h-[18px] univer-w-[80px]"
-                                        value={inputValue}
-                                        onChange={(v) => setInputValue(v)}
-                                        onBlur={() => handleChangeTableName(item.tableId, inputValue)}
-                                        onKeyDown={(e) => {
-                                            if (e.key === 'Enter') {
-                                                handleChangeTableName(item.tableId, inputValue);
-                                            }
-                                        }}
-                                        autoFocus={inputFocusId === item.tableId}
-                                    />
-                                )
-                                : (
-                                    <div className="univer-h-[18px] univer-max-w-24 univer-truncate univer-text-sm">
-                                        {item.tableName}
-                                    </div>
-                                )}
-                        </div>
-                        <Dropdown
-                            key={item.tableId}
-                            align="start"
-                            overlay={(
-                                <div className="univer-py-2">
-                                    <div
-                                        className={`
-                                          univer-flex univer-min-w-32 univer-cursor-pointer univer-items-center
-                                          univer-gap-2 univer-px-2 univer-py-1 univer-text-sm
-                                          hover:univer-bg-gray-200
-                                        `}
-                                        onClick={() => {
-                                            setInputFocusId(item.tableId);
-                                            setInputValue(item.tableName);
-                                        }}
-                                    >
-                                        <RenameIcon />
-                                        {localeService.t('sheets-table.rename')}
-                                    </div>
-                                    <div
-                                        className="univer-my-1 univer-h-px univer-w-full univer-bg-gray-200"
-                                    />
-                                    <div
-                                        onClick={() => handleChangeRange(item.tableId)}
-                                        className={`
-                                          univer-flex univer-min-w-32 univer-cursor-pointer univer-items-center
-                                          univer-gap-2 univer-px-2 univer-py-1 univer-text-sm
-                                          hover:univer-bg-gray-200
-                                        `}
-                                    >
-                                        <GridOutlineIcon />
-                                        {localeService.t('sheets-table.updateRange')}
-                                    </div>
-                                    <div
-                                        className={`
-                                          univer-flex univer-min-w-32 univer-cursor-pointer univer-items-center
-                                          univer-gap-2 univer-px-2 univer-py-1 univer-text-sm
-                                          hover:univer-bg-gray-200
-                                        `}
-                                        onClick={() => {
-                                            updateOpenState(item.tableId, false);
-                                            const table = tableManager.getTableById(unitId, item.tableId);
-                                            if (!table) return;
-                                            const tableConfig = table.getTableConfig();
-                                            const sidebarConfig = {
-                                                id: SHEET_TABLE_THEME_PANEL_ID,
-                                                header: { title: localeService.t('sheets-table.tableStyle') },
-                                                children: {
-                                                    label: SHEET_TABLE_THEME_PANEL,
-                                                    oldConfig: tableConfig,
-                                                    unitId,
-                                                    subUnitId,
-                                                    tableId: item.tableId,
-                                                },
-                                                width: 330,
-                                            };
-                                            sidebarService.open(sidebarConfig);
-                                        }}
-                                    >
-                                        <PaintBucketDoubleIcon
-                                            extend={{ colorChannel1: 'rgb(53,91,183)' }}
-                                        />
-                                        {localeService.t('sheets-table.setTheme')}
-                                    </div>
-                                    <div
-                                        className="univer-my-1 univer-h-px univer-w-full univer-bg-gray-200"
-                                    />
-                                    <div
-                                        className={`
-                                          univer-flex univer-min-w-32 univer-cursor-pointer univer-items-center
-                                          univer-px-2 univer-py-1 univer-text-sm
-                                          hover:univer-bg-gray-200
-                                        `}
-                                        onClick={() => {
-                                            updateOpenState(item.tableId, false);
-                                            commandService.executeCommand(DeleteSheetTableCommand.id, {
-                                                tableId: item.tableId,
-                                                subUnitId,
-                                                unitId,
-                                            });
-                                        }}
-                                    >
-                                        <DeleteIcon className="univer-mr-2" />
-                                        {localeService.t('sheets-table.removeTable')}
-                                    </div>
-                                </div>
-                            )}
-                            open={openStates[item.tableId] ?? false}
-                            onOpenChange={(isOpen) => {
-                                updateOpenState(item.tableId, isOpen);
-                            }}
-                        >
-                            <div>
-                                <MoreDownIcon />
-                            </div>
-                        </Dropdown>
-                    </div>
-                );
-            })}
-        </div>
-    );
-};
diff --git a/packages/sheets-table-ui/src/views/components/SheetTableFilterPanel.tsx b/packages/sheets-table-ui/src/views/components/SheetTableFilterPanel.tsx
--- a/packages/sheets-table-ui/src/views/components/SheetTableFilterPanel.tsx
+++ b/packages/sheets-table-ui/src/views/components/SheetTableFilterPanel.tsx
@@ -19,10 +19,10 @@ import type { ITableConditionFilterItem, ITableManualFilterItem } from '@univerj
 import type { IConditionInfo } from './type';
 import { ICommandService, IPermissionService, LocaleService } from '@univerjs/core';
 import { Button, ButtonGroup, Segmented } from '@univerjs/design';
-import { AscendingIcon, DescendingIcon } from '@univerjs/icons';
+import { AscendingIcon, DeleteColumnDoubleIcon, DescendingIcon, LeftInsertColumnDoubleIcon, RightInsertColumnDoubleIcon } from '@univerjs/icons';
 import { WorkbookEditablePermission } from '@univerjs/sheets';
 import { SortRangeCommand, SortType } from '@univerjs/sheets-sort';
-import { SheetsTableSortStateEnum, TableColumnFilterTypeEnum, TableDateCompareTypeEnum, TableManager } from '@univerjs/sheets-table';
+import { SheetsTableSortStateEnum, SheetTableInsertColumnAtCommand, SheetTableRemoveColumnAtCommand, TableColumnFilterTypeEnum, TableDateCompareTypeEnum, TableManager } from '@univerjs/sheets-table';
 import { useDependency } from '@univerjs/ui';
 import { useMemo, useState } from 'react';
 import { SheetsTableComponentController } from '../../controllers/sheet-table-component.controller';
@@ -61,9 +61,12 @@ export function SheetTableFilterPanel() {
     if (!table) return null;
 
     const tableFilters = table.getTableFilters();
+    const tableRange = table.getRange();
     const sortState = tableFilters.getSortState();
     const isAsc = sortState.columnIndex === columnIndex && sortState.sortState === SheetsTableSortStateEnum.Asc;
     const isDesc = sortState.columnIndex === columnIndex && sortState.sortState === SheetsTableSortStateEnum.Desc;
+    const absoluteColumn = tableFilterPanelInfo.column;
+    const canDeleteColumn = tableRange.endColumn > tableRange.startColumn;
 
     const closeDialog = (): void => {
         sheetsTableComponentController.closeFilterPanel();
@@ -87,6 +90,32 @@ export function SheetTableFilterPanel() {
         closeDialog();
     };
 
+    const insertColumn = (side: 'left' | 'right') => {
+        commandService.executeCommand(SheetTableInsertColumnAtCommand.id, {
+            unitId,
+            subUnitId,
+            tableId,
+            index: side === 'left' ? absoluteColumn : absoluteColumn + 1,
+            count: 1,
+        });
+        closeDialog();
+    };
+
+    const deleteColumn = () => {
+        if (!canDeleteColumn) {
+            return;
+        }
+
+        commandService.executeCommand(SheetTableRemoveColumnAtCommand.id, {
+            unitId,
+            subUnitId,
+            tableId,
+            index: absoluteColumn,
+            count: 1,
+        });
+        closeDialog();
+    };
+
     const onApply = () => {
         if (filterBy === FilterByEnum.Items) {
             // do items
@@ -152,18 +181,76 @@ export function SheetTableFilterPanel() {
             `}
         >
             {editable && (
-                <div className="univer-mb-3 univer-flex">
-                    <ButtonGroup className="univer-mb-3 !univer-flex univer-w-full">
-                        <Button className="univer-w-1/2" onClick={() => applySort(true)}>
-                            <AscendingIcon className="univer-mr-1" />
-                            {localeService.t('sheets-sort.general.sort-asc')}
-                        </Button>
-                        <Button className="univer-w-1/2" onClick={() => applySort(false)}>
-                            <DescendingIcon className="univer-mr-1" />
-                            {localeService.t('sheets-sort.general.sort-desc')}
-                        </Button>
-                    </ButtonGroup>
-                </div>
+                <>
+                    <div
+                        className={`
+                          -univer-mx-4 -univer-mt-2 univer-mb-3 univer-border-0 univer-border-b univer-border-solid
+                          univer-border-gray-200 univer-py-1
+                        `}
+                    >
+                        <button
+                            type="button"
+                            className={`
+                              univer-box-border univer-flex univer-h-10 univer-w-full univer-cursor-pointer
+                              univer-items-center univer-gap-3 univer-border-none univer-bg-transparent univer-px-4
+                              univer-text-left univer-text-sm univer-text-gray-900
+                              hover:univer-bg-gray-100
+                              disabled:univer-cursor-not-allowed disabled:univer-text-gray-400
+                              dark:!univer-text-white
+                              dark:hover:!univer-bg-gray-600
+                            `}
+                            onClick={() => insertColumn('left')}
+                        >
+                            <LeftInsertColumnDoubleIcon className="univer-size-5" extend={{ colorChannel1: 'var(--univer-primary-600)' }} />
+                            <span>{localeService.t('sheets-table.columnMenu.insert-left')}</span>
+                        </button>
+                        <button
+                            type="button"
+                            className={`
+                              univer-box-border univer-flex univer-h-10 univer-w-full univer-cursor-pointer
+                              univer-items-center univer-gap-3 univer-border-none univer-bg-transparent univer-px-4
+                              univer-text-left univer-text-sm univer-text-gray-900
+                              hover:univer-bg-gray-100
+                              disabled:univer-cursor-not-allowed disabled:univer-text-gray-400
+                              dark:!univer-text-white
+                              dark:hover:!univer-bg-gray-600
+                            `}
+                            onClick={() => insertColumn('right')}
+                        >
+                            <RightInsertColumnDoubleIcon className="univer-size-5" extend={{ colorChannel1: 'var(--univer-primary-600)' }} />
+                            <span>{localeService.t('sheets-table.columnMenu.insert-right')}</span>
+                        </button>
+                        <button
+                            type="button"
+                            className={`
+                              univer-box-border univer-flex univer-h-10 univer-w-full univer-cursor-pointer
+                              univer-items-center univer-gap-3 univer-border-none univer-bg-transparent univer-px-4
+                              univer-text-left univer-text-sm univer-text-gray-900
+                              hover:univer-bg-gray-100
+                              disabled:univer-cursor-not-allowed disabled:univer-text-gray-400
+                              dark:!univer-text-white
+                              dark:hover:!univer-bg-gray-600
+                            `}
+                            disabled={!canDeleteColumn}
+                            onClick={deleteColumn}
+                        >
+                            <DeleteColumnDoubleIcon className="univer-size-5" extend={{ colorChannel1: 'var(--univer-primary-600)' }} />
+                            <span>{localeService.t('sheets-table.columnMenu.delete')}</span>
+                        </button>
+                    </div>
+                    <div className="univer-mb-3 univer-flex">
+                        <ButtonGroup className="univer-mb-3 !univer-flex univer-w-full">
+                            <Button className="univer-w-1/2" onClick={() => applySort(true)}>
+                                <AscendingIcon className="univer-mr-1" />
+                                {localeService.t('sheets-sort.general.sort-asc')}
+                            </Button>
+                            <Button className="univer-w-1/2" onClick={() => applySort(false)}>
+                                <DescendingIcon className="univer-mr-1" />
+                                {localeService.t('sheets-sort.general.sort-desc')}
+                            </Button>
+                        </ButtonGroup>
+                    </div>
+                </>
             )}
             <div className="univer-w-full">
                 <Segmented
diff --git a/packages/sheets-table-ui/src/views/components/SheetTableRenameDialog.tsx b/packages/sheets-table-ui/src/views/components/SheetTableRenameDialog.tsx
new file mode 100644
--- /dev/null
+++ b/packages/sheets-table-ui/src/views/components/SheetTableRenameDialog.tsx
@@ -0,0 +1,106 @@
+/**
+ * Copyright 2023-present DreamNum Co., Ltd.
+ *
+ * Licensed under the Apache License, Version 2.0 (the "License");
+ * you may not use this file except in compliance with the License.
+ * You may obtain a copy of the License at
+ *
+ *     http://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+
+import type { IDefinedNamesService } from '@univerjs/engine-formula';
+import { ICommandService, IUniverInstanceService, LocaleService } from '@univerjs/core';
+import { Button, Input } from '@univerjs/design';
+import { IDefinedNamesService as IDefinedNamesServiceIdentifier } from '@univerjs/engine-formula';
+import { getExistingNamesSet, SetSheetTableCommand, TableManager, validateSheetTableName } from '@univerjs/sheets-table';
+import { useDependency } from '@univerjs/ui';
+import { useMemo, useState } from 'react';
+
+export interface ISheetTableRenameDialogProps {
+    unitId: string;
+    tableId: string;
+    onClose: () => void;
+}
+
+export function SheetTableRenameDialog(props: ISheetTableRenameDialogProps) {
+    const { unitId, tableId, onClose } = props;
+    const localeService = useDependency(LocaleService);
+    const commandService = useDependency(ICommandService);
+    const tableManager = useDependency<TableManager>(TableManager);
+    const univerInstanceService = useDependency(IUniverInstanceService);
+    const definedNamesService = useDependency<IDefinedNamesService>(IDefinedNamesServiceIdentifier);
+    const table = tableManager.getTableById(unitId, tableId);
+    const [value, setValue] = useState(table?.getDisplayName() ?? '');
+    const [error, setError] = useState('');
+
+    const existingNames = useMemo(() => {
+        const names = getExistingNamesSet(unitId, {
+            univerInstanceService,
+            tableManager,
+            definedNamesService,
+        });
+        const currentName = table?.getDisplayName().toLowerCase();
+
+        if (currentName) {
+            names.delete(currentName);
+        }
+
+        return names;
+    }, [definedNamesService, table, tableManager, unitId, univerInstanceService]);
+
+    const handleConfirm = () => {
+        const nextName = value.trim();
+        if (!table || nextName === table.getDisplayName()) {
+            onClose();
+            return;
+        }
+
+        const validation = validateSheetTableName(nextName, existingNames);
+        if (!validation.valid) {
+            setError(localeService.t('sheets-table.tableNameError'));
+            return;
+        }
+
+        commandService.executeCommand(SetSheetTableCommand.id, {
+            unitId,
+            tableId,
+            name: nextName,
+        });
+        onClose();
+    };
+
+    return (
+        <div
+            className={`
+              univer-box-border univer-flex univer-w-full univer-flex-col univer-gap-4 univer-pb-3 univer-pt-2
+            `}
+        >
+            <Input
+                size="middle"
+                value={value}
+                placeholder={localeService.t('sheets-table.renamePlaceholder')}
+                onChange={(nextValue) => {
+                    setValue(nextValue);
+                    setError('');
+                }}
+                onKeyDown={(event) => {
+                    if (event.key === 'Enter') {
+                        handleConfirm();
+                    }
+                }}
+                autoFocus
+            />
+            {error ? <div className="-univer-mt-2 univer-text-sm univer-text-red-500">{error}</div> : null}
+            <div className="univer-flex univer-w-full univer-items-center univer-justify-end univer-gap-2">
+                <Button className="univer-min-w-16" onClick={onClose}>{localeService.t('sheets-table.cancel')}</Button>
+                <Button className="univer-min-w-16" variant="primary" onClick={handleConfirm}>{localeService.t('sheets-table.confirm')}</Button>
+            </div>
+        </div>
+    );
+}
diff --git a/packages/sheets-table-ui/src/views/widgets/table-controls-util.ts b/packages/sheets-table-ui/src/views/widgets/table-controls-util.ts
new file mode 100644
--- /dev/null
+++ b/packages/sheets-table-ui/src/views/widgets/table-controls-util.ts
@@ -0,0 +1,70 @@
+/**
+ * Copyright 2023-present DreamNum Co., Ltd.
+ *
+ * Licensed under the Apache License, Version 2.0 (the "License");
+ * you may not use this file except in compliance with the License.
+ * You may obtain a copy of the License at
+ *
+ *     http://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+
+export const TABLE_CONTROL_ANCHOR_HEIGHT = 28;
+export const TABLE_CONTROL_ANCHOR_RADIUS = 14;
+export const TABLE_CONTROL_MENU_WIDTH = 168;
+export const TABLE_CONTROL_MENU_ITEM_HEIGHT = 32;
+export const TABLE_CONTROL_INSERT_BUTTON_SIZE = 22;
+export const TABLE_CONTROL_TOP_GAP_SIZE = 32;
+
+export type TableControlHitType =
+    | 'anchor-main'
+    | 'anchor-menu-toggle'
+    | 'menu-item'
+    | 'insert-row'
+    | 'insert-column';
+
+export type TableControlMenuAction = 'rename' | 'update-range' | 'set-theme' | 'delete';
+
+export interface ITableControlHitRegion {
+    type: TableControlHitType;
+    tableId: string;
+    left: number;
+    top: number;
+    width: number;
+    height: number;
+    action?: TableControlMenuAction;
+    index?: number;
+}
+
+export const TABLE_CONTROL_MENU_ACTIONS: TableControlMenuAction[] = ['rename', 'update-range', 'set-theme', 'delete'];
+
+export function isPointInTableControlRegion(region: ITableControlHitRegion, x: number, y: number): boolean {
+    return x >= region.left && x <= region.left + region.width && y >= region.top && y <= region.top + region.height;
+}
+
+export function hitTestTableControl(regions: ITableControlHitRegion[], x: number, y: number): ITableControlHitRegion | null {
+    for (let i = regions.length - 1; i >= 0; i--) {
+        if (isPointInTableControlRegion(regions[i], x, y)) {
+            return regions[i];
+        }
+    }
+
+    return null;
+}
+
+export function buildTableMenuRegions(tableId: string, left: number, top: number): ITableControlHitRegion[] {
+    return TABLE_CONTROL_MENU_ACTIONS.map((action, index) => ({
+        type: 'menu-item',
+        tableId,
+        action,
+        left,
+        top: top + index * TABLE_CONTROL_MENU_ITEM_HEIGHT,
+        width: TABLE_CONTROL_MENU_WIDTH,
+        height: TABLE_CONTROL_MENU_ITEM_HEIGHT,
+    }));
+}
diff --git a/packages/sheets-table-ui/src/views/widgets/table-controls.shape.ts b/packages/sheets-table-ui/src/views/widgets/table-controls.shape.ts
new file mode 100644
--- /dev/null
+++ b/packages/sheets-table-ui/src/views/widgets/table-controls.shape.ts
@@ -0,0 +1,335 @@
+/**
+ * Copyright 2023-present DreamNum Co., Ltd.
+ *
+ * Licensed under the Apache License, Version 2.0 (the "License");
+ * you may not use this file except in compliance with the License.
+ * You may obtain a copy of the License at
+ *
+ *     http://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+
+import type { IShapeProps, SpreadsheetSkeleton, UniverRenderingContext, Vector2 } from '@univerjs/engine-render';
+import type { ITableControlHitRegion, TableControlMenuAction } from './table-controls-util';
+import { DEFAULT_FONTFACE_PLANE, Rect, Shape } from '@univerjs/engine-render';
+import {
+    buildTableMenuRegions,
+    hitTestTableControl,
+    TABLE_CONTROL_ANCHOR_HEIGHT,
+    TABLE_CONTROL_ANCHOR_RADIUS,
+    TABLE_CONTROL_MENU_ITEM_HEIGHT,
+    TABLE_CONTROL_MENU_WIDTH,
+} from './table-controls-util';
+
+const ANCHOR_MIN_WIDTH = 122;
+const ANCHOR_MAX_WIDTH = 240;
+const ANCHOR_PADDING_X = 12;
+const ANCHOR_TOGGLE_WIDTH = 30;
+const ANCHOR_OFFSET_Y = 0;
+const ANCHOR_BORDER = 'rgba(0, 0, 0, 0.22)';
+const ANCHOR_DIVIDER = 'rgba(0, 0, 0, 0.20)';
+const ANCHOR_TOGGLE_BG_ACTIVE = 'rgba(0, 0, 0, 0.12)';
+const MENU_RADIUS = 8;
+const MENU_BORDER = '#d9dee7';
+const MENU_HOVER_BG = '#f1f3f4';
+const INSERT_BUTTON_VISUAL_SIZE = 18;
+const INSERT_BUTTON_TEXT_OFFSET_Y = -1;
+
+export interface ITableControlRenderItem {
+    tableId: string;
+    tableName: string;
+    range: { startRow: number; endRow: number; startColumn: number; endColumn: number };
+    fill: string;
+    text: string;
+}
+
+export interface ITableControlMenuLabels {
+    rename: string;
+    'update-range': string;
+    'set-theme': string;
+    delete: string;
+}
+
+export class SheetTableControlsShape extends Shape<IShapeProps> {
+    private _items: ITableControlRenderItem[] = [];
+    private _regions: ITableControlHitRegion[] = [];
+    private _openedMenuTableId: string | null = null;
+    private _hoveredRegion: ITableControlHitRegion | null = null;
+    private _hoveredInsertRegion: ITableControlHitRegion | null = null;
+    private _menuLabels: ITableControlMenuLabels = {
+        rename: 'Rename table',
+        'update-range': 'Update range',
+        'set-theme': 'Set theme',
+        delete: 'Remove table',
+    };
+
+    constructor(
+        key: string,
+        private readonly _getSkeleton: () => SpreadsheetSkeleton | null | undefined
+    ) {
+        super(key, {
+            evented: true,
+            fill: 'rgba(0, 0, 0, 0)',
+            zIndex: 5001,
+        });
+    }
+
+    setItems(items: ITableControlRenderItem[]): void {
+        this._items = items;
+        this.makeDirty(true);
+    }
+
+    setMenuLabels(labels: ITableControlMenuLabels): void {
+        this._menuLabels = labels;
+        this.makeDirty(true);
+    }
+
+    setOpenedMenuTableId(tableId: string | null): void {
+        if (this._openedMenuTableId === tableId) {
+            return;
+        }
+
+        this._openedMenuTableId = tableId;
+        this.makeDirty(true);
+    }
+
+    getOpenedMenuTableId(): string | null {
+        return this._openedMenuTableId;
+    }
+
+    setHoveredRegion(region: ITableControlHitRegion | null): void {
+        if (this._hoveredRegion === region) {
+            return;
+        }
+
+        this._hoveredRegion = region;
+        this.makeDirty(true);
+    }
+
+    setHoveredInsertRegion(region: ITableControlHitRegion | null): void {
+        if (this._hoveredInsertRegion === region) {
+            return;
+        }
+
+        this._hoveredInsertRegion = region;
+        this.makeDirty(true);
+    }
+
+    hitTest(x: number, y: number): ITableControlHitRegion | null {
+        return hitTestTableControl(this._regions, x, y);
+    }
+
+    override isHit(coord: Vector2): boolean {
+        return this.hitTest(coord.x, coord.y) != null;
+    }
+
+    refreshBounds(): void {
+        const skeleton = this._getSkeleton();
+        if (!skeleton) {
+            this.hide();
+            return;
+        }
+
+        this.show();
+        this.transformByState({
+            left: 0,
+            top: 0,
+            width: skeleton.rowHeaderWidth + skeleton.columnTotalWidth,
+            height: skeleton.columnHeaderHeight + skeleton.rowTotalHeight,
+        });
+    }
+
+    protected override _draw(ctx: UniverRenderingContext): void {
+        this._regions = [];
+        const skeleton = this._getSkeleton();
+        if (!skeleton) {
+            return;
+        }
+
+        ctx.save();
+        ctx.textBaseline = 'middle';
+
+        for (const item of this._items) {
+            this._drawAnchor(ctx, skeleton, item);
+        }
+
+        if (this._hoveredInsertRegion) {
+            const item = this._items.find((renderItem) => renderItem.tableId === this._hoveredInsertRegion?.tableId);
+            this._drawInsertButton(ctx, this._hoveredInsertRegion, item?.fill ?? '#355bb7');
+            this._regions.push(this._hoveredInsertRegion);
+        }
+
+        ctx.restore();
+    }
+
+    private _drawAnchor(ctx: UniverRenderingContext, skeleton: SpreadsheetSkeleton, item: ITableControlRenderItem): void {
+        const position = skeleton.getNoMergeCellWithCoordByIndex(item.range.startRow, item.range.startColumn);
+        const left = position.startX;
+        const rawTop = position.startY - TABLE_CONTROL_ANCHOR_HEIGHT - ANCHOR_OFFSET_Y;
+        const top = Math.max(0, rawTop);
+        const width = Math.max(ANCHOR_MIN_WIDTH, Math.min(ANCHOR_MAX_WIDTH, item.tableName.length * 8.5 + ANCHOR_PADDING_X * 2 + ANCHOR_TOGGLE_WIDTH));
+        const toggleRegion: ITableControlHitRegion = {
+            type: 'anchor-menu-toggle',
+            tableId: item.tableId,
+            left: left + width - ANCHOR_TOGGLE_WIDTH,
+            top,
+            width: ANCHOR_TOGGLE_WIDTH,
+            height: TABLE_CONTROL_ANCHOR_HEIGHT,
+        };
+
+        ctx.save();
+        ctx.translateWithPrecision(left, top);
+        this._drawTopRoundedRect(ctx, width, TABLE_CONTROL_ANCHOR_HEIGHT, TABLE_CONTROL_ANCHOR_RADIUS, item.fill, ANCHOR_BORDER);
+        this._drawAnchorToggle(ctx, width, item.text, this._openedMenuTableId === item.tableId || this._isSameRegion(this._hoveredRegion, toggleRegion));
+        ctx.font = `600 13px ${DEFAULT_FONTFACE_PLANE}`;
+        ctx.fillStyle = item.text;
+        ctx.textAlign = 'left';
+        ctx.fillText(item.tableName, ANCHOR_PADDING_X, TABLE_CONTROL_ANCHOR_HEIGHT / 2);
+        ctx.restore();
+
+        this._regions.push({
+            type: 'anchor-main',
+            tableId: item.tableId,
+            left,
+            top,
+            width,
+            height: TABLE_CONTROL_ANCHOR_HEIGHT,
+        });
+        this._regions.push(toggleRegion);
+
+        if (this._openedMenuTableId === item.tableId) {
+            this._drawMenu(ctx, item.tableId, left, top + TABLE_CONTROL_ANCHOR_HEIGHT);
+        }
+    }
+
+    private _drawAnchorToggle(ctx: UniverRenderingContext, anchorWidth: number, color: string, active: boolean): void {
+        const toggleLeft = anchorWidth - ANCHOR_TOGGLE_WIDTH;
+        if (active) {
+            this._drawRightTopRoundedRect(ctx, toggleLeft, anchorWidth, TABLE_CONTROL_ANCHOR_HEIGHT, TABLE_CONTROL_ANCHOR_RADIUS, ANCHOR_TOGGLE_BG_ACTIVE);
+        }
+
+        ctx.save();
+        ctx.beginPath();
+        ctx.strokeStyle = ANCHOR_DIVIDER;
+        ctx.lineWidth = 1;
+        ctx.moveTo(toggleLeft + 0.5, 5);
+        ctx.lineTo(toggleLeft + 0.5, TABLE_CONTROL_ANCHOR_HEIGHT - 5);
+        ctx.stroke();
+        ctx.restore();
+
+        const centerX = anchorWidth - ANCHOR_TOGGLE_WIDTH / 2;
+        const centerY = TABLE_CONTROL_ANCHOR_HEIGHT / 2;
+
+        ctx.save();
+        ctx.beginPath();
+        ctx.strokeStyle = color;
+        ctx.lineWidth = 1.6;
+        ctx.lineCap = 'round';
+        ctx.moveTo(centerX - 5, centerY - 4);
+        ctx.lineTo(centerX + 5, centerY - 4);
+        ctx.moveTo(centerX - 5, centerY);
+        ctx.lineTo(centerX + 5, centerY);
+        ctx.moveTo(centerX - 5, centerY + 4);
+        ctx.lineTo(centerX + 5, centerY + 4);
+        ctx.stroke();
+        ctx.restore();
+    }
+
+    private _drawTopRoundedRect(ctx: UniverRenderingContext, width: number, height: number, radius: number, fill: string, stroke?: string): void {
+        const r = Math.min(radius, width / 2, height);
+
+        ctx.beginPath();
+        ctx.moveTo(0, height);
+        ctx.lineTo(0, r);
+        ctx.arcTo(0, 0, r, 0, r);
+        ctx.lineTo(width - r, 0);
+        ctx.arcTo(width, 0, width, r, r);
+        ctx.lineTo(width, height);
+        ctx.closePath();
+        ctx.fillStyle = fill;
+        ctx.fill();
+        if (stroke) {
+            ctx.strokeStyle = stroke;
+            ctx.lineWidth = 1;
+            ctx.stroke();
+        }
+    }
+
+    private _drawRightTopRoundedRect(ctx: UniverRenderingContext, left: number, width: number, height: number, radius: number, fill: string): void {
+        const r = Math.min(radius, width - left, height);
+
+        ctx.save();
+        ctx.beginPath();
+        ctx.moveTo(left, height);
+        ctx.lineTo(left, 0);
+        ctx.lineTo(width - r, 0);
+        ctx.arcTo(width, 0, width, r, r);
+        ctx.lineTo(width, height);
+        ctx.closePath();
+        ctx.fillStyle = fill;
+        ctx.fill();
+        ctx.restore();
+    }
+
+    private _drawMenu(ctx: UniverRenderingContext, tableId: string, left: number, top: number): void {
+        const regions = buildTableMenuRegions(tableId, left, top);
+
+        ctx.save();
+        ctx.translateWithPrecision(left, top);
+        Rect.drawWith(ctx, {
+            width: TABLE_CONTROL_MENU_WIDTH,
+            height: regions.length * TABLE_CONTROL_MENU_ITEM_HEIGHT,
+            radius: MENU_RADIUS,
+            fill: '#fff',
+            stroke: MENU_BORDER,
+        });
+        ctx.restore();
+
+        for (const region of regions) {
+            const hovered = this._isSameRegion(this._hoveredRegion, region);
+            if (hovered) {
+                ctx.save();
+                ctx.fillStyle = MENU_HOVER_BG;
+                ctx.fillRectByPrecision(region.left, region.top, region.width, region.height);
+                ctx.restore();
+            }
+
+            ctx.save();
+            ctx.font = `12px ${DEFAULT_FONTFACE_PLANE}`;
+            ctx.fillStyle = region.action === 'delete' ? '#d92d20' : '#344054';
+            ctx.textAlign = 'left';
+            ctx.fillText(this._menuLabels[region.action as TableControlMenuAction], region.left + 12, region.top + region.height / 2);
+            ctx.restore();
+        }
+
+        this._regions.push(...regions);
+    }
+
+    private _drawInsertButton(ctx: UniverRenderingContext, region: ITableControlHitRegion, fill: string): void {
+        const centerX = region.left + region.width / 2;
+        const centerY = region.top + region.height / 2;
+        const radius = INSERT_BUTTON_VISUAL_SIZE / 2;
+
+        ctx.save();
+        ctx.beginPath();
+        ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
+        ctx.fillStyle = '#fff';
+        ctx.fill();
+        ctx.strokeStyle = fill;
+        ctx.stroke();
+        ctx.font = `12px ${DEFAULT_FONTFACE_PLANE}`;
+        ctx.fillStyle = fill;
+        ctx.textAlign = 'center';
+        ctx.fillText('+', centerX, centerY + INSERT_BUTTON_TEXT_OFFSET_Y);
+        ctx.restore();
+    }
+
+    private _isSameRegion(a: ITableControlHitRegion | null, b: ITableControlHitRegion): boolean {
+        return Boolean(a && a.type === b.type && a.tableId === b.tableId && a.action === b.action && a.index === b.index);
+    }
+}
diff --git a/packages/sheets-table-ui/src/views/widgets/table-filter-button.shape.ts b/packages/sheets-table-ui/src/views/widgets/table-filter-button.shape.ts
--- a/packages/sheets-table-ui/src/views/widgets/table-filter-button.shape.ts
+++ b/packages/sheets-table-ui/src/views/widgets/table-filter-button.shape.ts
@@ -15,21 +15,22 @@
  */
 
 import type { IMouseEvent, IPointerEvent, IShapeProps, UniverRenderingContext2D } from '@univerjs/engine-render';
+import type { SheetsTableButtonStateEnum } from '@univerjs/sheets-table';
 import type { IOpenTableFilterPanelOperationParams } from '../../commands/operations/open-table-filter-dialog.opration';
-import { ICommandService, IContextService, Inject, ThemeService } from '@univerjs/core';
+import { ICommandService } from '@univerjs/core';
 import { Shape } from '@univerjs/engine-render';
-import { SheetsTableButtonStateEnum } from '@univerjs/sheets-table';
 import { OpenTableFilterPanelOperation } from '../../commands/operations/open-table-filter-dialog.opration';
-import { SHEETS_TABLE_FILTER_PANEL_OPENED_KEY } from '../../const';
-import { TableButton } from './drawings';
-import { filteredSortAsc, filteredSortDesc, filterNoneSortAsc, filterNoneSortDesc, filterPartial } from './icons';
 
 export const FILTER_ICON_SIZE = 16;
 export const FILTER_ICON_PADDING = 1;
+const FILTER_TRIGGER_HOVER_RADIUS = 4;
 
 export interface ISheetsTableFilterButtonShapeProps extends IShapeProps {
     cellWidth: number;
     cellHeight: number;
+    iconColor: string;
+    hoverBackground: string;
+    hoverIconColor: string;
     filterParams: { row: number; col: number; unitId: string; subUnitId: string; buttonState: SheetsTableButtonStateEnum; tableId: string };
 }
 
@@ -41,15 +42,16 @@ export class SheetsTableFilterButtonShape extends Shape<ISheetsTableFilterButton
     private _cellHeight: number = 0;
 
     private _filterParams?: { row: number; col: number; unitId: string; subUnitId: string; buttonState: SheetsTableButtonStateEnum; tableId: string };
+    private _iconColor = '#fff';
+    private _hoverBackground = 'rgba(255, 255, 255, 0.92)';
+    private _hoverIconColor = '#202124';
 
     private _hovered = false;
 
     constructor(
         key: string,
         props: ISheetsTableFilterButtonShapeProps,
-        @IContextService private readonly _contextService: IContextService,
-        @ICommandService private readonly _commandService: ICommandService,
-        @Inject(ThemeService) private readonly _themeService: ThemeService
+        @ICommandService private readonly _commandService: ICommandService
     ) {
         super(key, props);
 
@@ -74,6 +76,18 @@ export class SheetsTableFilterButtonShape extends Shape<ISheetsTableFilterButton
             this._filterParams = props.filterParams;
         }
 
+        if (typeof props.iconColor !== 'undefined') {
+            this._iconColor = props.iconColor;
+        }
+
+        if (typeof props.hoverBackground !== 'undefined') {
+            this._hoverBackground = props.hoverBackground;
+        }
+
+        if (typeof props.hoverIconColor !== 'undefined') {
+            this._hoverIconColor = props.hoverIconColor;
+        }
+
         this.transformByState({
             width: props.width!,
             height: props.height!,
@@ -93,41 +107,36 @@ export class SheetsTableFilterButtonShape extends Shape<ISheetsTableFilterButton
         cellRegion.rect(left, top, cellWidth, cellHeight);
         ctx.clip(cellRegion);
 
-        const { buttonState } = this._filterParams!;
-
-        const fgColor = this._themeService.getColorFromTheme('primary.600');
-        const bgColor = this._hovered
-            ? this._themeService.getColorFromTheme('gray.50')
-            : 'rgba(255, 255, 255, 1.0)';
-
-        let icons;
-        switch (buttonState) {
-            case SheetsTableButtonStateEnum.FilteredSortNone:
-                icons = filterPartial;
-                break;
-
-            case SheetsTableButtonStateEnum.FilteredSortAsc:
-                icons = filteredSortAsc;
-                break;
-            case SheetsTableButtonStateEnum.FilteredSortDesc:
-                icons = filteredSortDesc;
-                break;
-            case SheetsTableButtonStateEnum.FilterNoneSortNone:
-
-                break;
-            case SheetsTableButtonStateEnum.FilterNoneSortAsc:
-                icons = filterNoneSortAsc;
-                break;
-            case SheetsTableButtonStateEnum.FilterNoneSortDesc:
-                icons = filterNoneSortDesc;
-                break;
-        }
-        if (icons) {
-            TableButton.drawIconByPath(ctx, icons, fgColor, bgColor);
-        } else if (buttonState !== undefined) {
-            TableButton.drawNoSetting(ctx, FILTER_ICON_SIZE, fgColor, bgColor);
+        if (this._hovered) {
+            ctx.save();
+            ctx.fillStyle = this._hoverBackground;
+            ctx.beginPath();
+            ctx.roundRect?.(0, 0, FILTER_ICON_SIZE, FILTER_ICON_SIZE, FILTER_TRIGGER_HOVER_RADIUS);
+            if (!ctx.roundRect) {
+                ctx.rect(0, 0, FILTER_ICON_SIZE, FILTER_ICON_SIZE);
+            }
+            ctx.fill();
+            ctx.restore();
         }
 
+        this._drawChevron(ctx, this._hovered ? this._hoverIconColor : this._iconColor);
+        ctx.restore();
+    }
+
+    private _drawChevron(ctx: UniverRenderingContext2D, color: string): void {
+        const centerX = FILTER_ICON_SIZE / 2;
+        const centerY = FILTER_ICON_SIZE / 2 + 1;
+
+        ctx.save();
+        ctx.beginPath();
+        ctx.strokeStyle = color;
+        ctx.lineWidth = 1.8;
+        ctx.lineCap = 'round';
+        ctx.lineJoin = 'round';
+        ctx.moveTo(centerX - 4.5, centerY - 2.5);
+        ctx.lineTo(centerX, centerY + 2);
+        ctx.lineTo(centerX + 4.5, centerY - 2.5);
+        ctx.stroke();
         ctx.restore();
     }
 
@@ -138,8 +147,7 @@ export class SheetsTableFilterButtonShape extends Shape<ISheetsTableFilterButton
         }
 
         const { row, col, unitId, subUnitId, tableId } = this._filterParams!;
-        const opened = this._contextService.getContextValue(SHEETS_TABLE_FILTER_PANEL_OPENED_KEY);
-        if (opened || !this._commandService.hasCommand(OpenTableFilterPanelOperation.id)) {
+        if (!this._commandService.hasCommand(OpenTableFilterPanelOperation.id)) {
             return;
         }
 
diff --git a/packages/sheets-table/src/commands/commands/set-sheet-table.command.ts b/packages/sheets-table/src/commands/commands/set-sheet-table.command.ts
--- a/packages/sheets-table/src/commands/commands/set-sheet-table.command.ts
+++ b/packages/sheets-table/src/commands/commands/set-sheet-table.command.ts
@@ -17,11 +17,12 @@
 import type { ICommand } from '@univerjs/core';
 import type { ITableSetConfig } from '../../types/type';
 import type { ISetSheetTableMutationParams } from '../mutations/set-sheet-table.mutation';
-import { CommandType, customNameCharacterCheck, ICommandService, ILogService, IUndoRedoService, IUniverInstanceService, LocaleService } from '@univerjs/core';
+import { CommandType, ICommandService, ILogService, IUndoRedoService, IUniverInstanceService, LocaleService } from '@univerjs/core';
 import { IDefinedNamesService } from '@univerjs/engine-formula';
 import { TableManager } from '../../model/table-manager';
 import { IRangeOperationTypeEnum } from '../../types/type';
 import { getExistingNamesSet } from '../../util';
+import { validateSheetTableName } from '../../util/table-name';
 import { SetSheetTableMutation } from '../mutations/set-sheet-table.mutation';
 
 export interface ISetSheetTableCommandParams extends ITableSetConfig {
@@ -54,8 +55,8 @@ export const SetSheetTableCommand: ICommand<ISetSheetTableCommandParams> = {
         });
 
         if (name) {
-            const isValidName = customNameCharacterCheck(name.toLowerCase(), existingNamesSet);
-            if (!isValidName) {
+            const tableNameValidation = validateSheetTableName(name, existingNamesSet);
+            if (!tableNameValidation.valid) {
                 const logService = accessor.get(ILogService);
                 logService.warn(localeService.t('sheets-table.tableNameError'));
                 return false;
diff --git a/packages/sheets-table/src/commands/commands/sheet-table-row-col.command.ts b/packages/sheets-table/src/commands/commands/sheet-table-row-col.command.ts
--- a/packages/sheets-table/src/commands/commands/sheet-table-row-col.command.ts
+++ b/packages/sheets-table/src/commands/commands/sheet-table-row-col.command.ts
@@ -16,7 +16,7 @@
 
 /* eslint-disable max-lines-per-function */
 
-import type { ICommand, IMutationInfo } from '@univerjs/core';
+import type { IAccessor, ICommand, IMutationInfo } from '@univerjs/core';
 import type { ITableColumnJson } from '../../types/type';
 import { CommandType, ICommandService, IUndoRedoService, IUniverInstanceService, sequenceExecute } from '@univerjs/core';
 import { getMoveRangeUndoRedoMutations, getSheetCommandTarget, InsertColMutation, InsertRowMutation, RemoveColMutation, RemoveRowMutation, SheetsSelectionsService } from '@univerjs/sheets';
@@ -31,6 +31,34 @@ interface ISheetTableRowColOperationCommandParams {
     subUnitId: string;
 }
 
+interface ISheetTableInsertAtCommandParams extends ISheetTableRowColOperationCommandParams {
+    index: number;
+    count?: number;
+}
+
+function executeTableMutationSequence(
+    accessor: IAccessor,
+    unitId: string,
+    redos: IMutationInfo[],
+    undos: IMutationInfo[]
+): boolean {
+    const commandService = accessor.get(ICommandService);
+    const res = sequenceExecute(redos, commandService);
+
+    if (res.result) {
+        const undoRedoService = accessor.get(IUndoRedoService);
+        undoRedoService.pushUndoRedo({
+            unitID: unitId,
+            undoMutations: undos,
+            redoMutations: redos,
+        });
+
+        return true;
+    }
+
+    return false;
+}
+
 export const SheetTableInsertRowCommand: ICommand<ISheetTableRowColOperationCommandParams> = {
     id: 'sheet.command.table-insert-row',
     type: CommandType.COMMAND,
@@ -195,6 +223,99 @@ export const SheetTableInsertRowCommand: ICommand<ISheetTableRowColOperationComm
     },
 };
 
+export const SheetTableInsertRowAtCommand: ICommand<ISheetTableInsertAtCommandParams> = {
+    id: 'sheet.command.table-insert-row-at',
+    type: CommandType.COMMAND,
+    handler: (accessor, params) => {
+        if (!params) {
+            return false;
+        }
+
+        const { unitId, subUnitId, tableId, index, count = 1 } = params;
+        if (count <= 0) {
+            return false;
+        }
+
+        const univerInstanceService = accessor.get(IUniverInstanceService);
+        const target = getSheetCommandTarget(univerInstanceService, { unitId, subUnitId });
+        if (!target) {
+            return false;
+        }
+
+        const table = accessor.get(TableManager).getTableById(unitId, tableId);
+        if (!table || table.getSubunitId() !== subUnitId) {
+            return false;
+        }
+
+        const oldRange = table.getRange();
+        if (index <= oldRange.startRow || index > oldRange.endRow + 1) {
+            return false;
+        }
+
+        const redos: IMutationInfo[] = [{
+            id: SetSheetTableMutation.id,
+            params: {
+                unitId,
+                subUnitId,
+                tableId,
+                config: {
+                    updateRange: {
+                        newRange: {
+                            ...oldRange,
+                            endRow: oldRange.endRow + count,
+                        },
+                    },
+                },
+            },
+        }];
+        const undos: IMutationInfo[] = [{
+            id: SetSheetTableMutation.id,
+            params: {
+                unitId,
+                subUnitId,
+                tableId,
+                config: {
+                    updateRange: {
+                        newRange: { ...oldRange },
+                    },
+                },
+            },
+        }];
+
+        const rowContentIndex = target.worksheet.getCellMatrix().getDataRange().endRow;
+        const moveRangeMutations = getMoveRangeUndoRedoMutations(
+            accessor,
+            {
+                unitId,
+                subUnitId,
+                range: {
+                    startRow: index,
+                    endRow: rowContentIndex,
+                    startColumn: oldRange.startColumn,
+                    endColumn: oldRange.endColumn,
+                },
+            },
+            {
+                unitId,
+                subUnitId,
+                range: {
+                    startRow: index + count,
+                    endRow: rowContentIndex + count,
+                    startColumn: oldRange.startColumn,
+                    endColumn: oldRange.endColumn,
+                },
+            }
+        );
+
+        if (moveRangeMutations) {
+            redos.push(...moveRangeMutations.redos);
+            undos.push(...moveRangeMutations.undos);
+        }
+
+        return executeTableMutationSequence(accessor, unitId, redos, undos);
+    },
+};
+
 export const SheetTableInsertColCommand: ICommand<ISheetTableRowColOperationCommandParams> = {
     id: 'sheet.command.table-insert-col',
     type: CommandType.COMMAND,
@@ -351,6 +472,212 @@ export const SheetTableInsertColCommand: ICommand<ISheetTableRowColOperationComm
     },
 };
 
+export const SheetTableInsertColumnAtCommand: ICommand<ISheetTableInsertAtCommandParams> = {
+    id: 'sheet.command.table-insert-column-at',
+    type: CommandType.COMMAND,
+    handler: (accessor, params) => {
+        if (!params) {
+            return false;
+        }
+
+        const { unitId, subUnitId, tableId, index, count = 1 } = params;
+        if (count <= 0) {
+            return false;
+        }
+
+        const univerInstanceService = accessor.get(IUniverInstanceService);
+        const target = getSheetCommandTarget(univerInstanceService, { unitId, subUnitId });
+        if (!target) {
+            return false;
+        }
+
+        const table = accessor.get(TableManager).getTableById(unitId, tableId);
+        if (!table || table.getSubunitId() !== subUnitId) {
+            return false;
+        }
+
+        const oldRange = table.getRange();
+        if (index < oldRange.startColumn || index > oldRange.endColumn + 1) {
+            return false;
+        }
+
+        const redos: IMutationInfo[] = [{
+            id: SetSheetTableMutation.id,
+            params: {
+                unitId,
+                subUnitId,
+                tableId,
+                config: {
+                    rowColOperation: {
+                        operationType: IRangeOperationTypeEnum.Insert,
+                        rowColType: IRowColTypeEnum.Col,
+                        index,
+                        count,
+                    },
+                },
+            },
+        }];
+        const undos: IMutationInfo[] = [{
+            id: SetSheetTableMutation.id,
+            params: {
+                unitId,
+                subUnitId,
+                tableId,
+                config: {
+                    rowColOperation: {
+                        operationType: IRangeOperationTypeEnum.Delete,
+                        rowColType: IRowColTypeEnum.Col,
+                        index,
+                        count,
+                    },
+                },
+            },
+        }];
+
+        const colContentIndex = target.worksheet.getCellMatrix().getDataRange().endColumn;
+        if (index <= colContentIndex) {
+            const moveRangeMutations = getMoveRangeUndoRedoMutations(
+                accessor,
+                {
+                    unitId,
+                    subUnitId,
+                    range: {
+                        startRow: oldRange.startRow,
+                        endRow: oldRange.endRow,
+                        startColumn: index,
+                        endColumn: colContentIndex,
+                    },
+                },
+                {
+                    unitId,
+                    subUnitId,
+                    range: {
+                        startRow: oldRange.startRow,
+                        endRow: oldRange.endRow,
+                        startColumn: index + count,
+                        endColumn: colContentIndex + count,
+                    },
+                }
+            );
+
+            if (moveRangeMutations) {
+                redos.push(...moveRangeMutations.redos);
+                undos.push(...moveRangeMutations.undos);
+            }
+        }
+
+        return executeTableMutationSequence(accessor, unitId, redos, undos);
+    },
+};
+
+export const SheetTableRemoveColumnAtCommand: ICommand<ISheetTableInsertAtCommandParams> = {
+    id: 'sheet.command.table-remove-column-at',
+    type: CommandType.COMMAND,
+    handler: (accessor, params) => {
+        if (!params) {
+            return false;
+        }
+
+        const { unitId, subUnitId, tableId, index, count = 1 } = params;
+        if (count <= 0) {
+            return false;
+        }
+
+        const univerInstanceService = accessor.get(IUniverInstanceService);
+        const target = getSheetCommandTarget(univerInstanceService, { unitId, subUnitId });
+        if (!target) {
+            return false;
+        }
+
+        const table = accessor.get(TableManager).getTableById(unitId, tableId);
+        if (!table || table.getSubunitId() !== subUnitId) {
+            return false;
+        }
+
+        const oldRange = table.getRange();
+        if (index < oldRange.startColumn || index + count - 1 > oldRange.endColumn || count >= oldRange.endColumn - oldRange.startColumn + 1) {
+            return false;
+        }
+
+        const columns: ITableColumnJson[] = [];
+        const gap = index - oldRange.startColumn;
+        for (let i = 0; i < count; i++) {
+            const column = table.getTableInfo().columns[gap + i];
+            if (column) {
+                columns.push(column);
+            }
+        }
+
+        const redos: IMutationInfo[] = [{
+            id: SetSheetTableMutation.id,
+            params: {
+                unitId,
+                subUnitId,
+                tableId,
+                config: {
+                    rowColOperation: {
+                        operationType: IRangeOperationTypeEnum.Delete,
+                        rowColType: IRowColTypeEnum.Col,
+                        index,
+                        count,
+                    },
+                },
+            },
+        }];
+        const undos: IMutationInfo[] = [{
+            id: SetSheetTableMutation.id,
+            params: {
+                unitId,
+                subUnitId,
+                tableId,
+                config: {
+                    rowColOperation: {
+                        operationType: IRangeOperationTypeEnum.Insert,
+                        rowColType: IRowColTypeEnum.Col,
+                        index,
+                        count,
+                        columnsJson: columns,
+                    },
+                },
+            },
+        }];
+
+        const colContentIndex = target.worksheet.getCellMatrix().getDataRange().endColumn;
+        if (index + count <= colContentIndex) {
+            const moveRangeMutations = getMoveRangeUndoRedoMutations(
+                accessor,
+                {
+                    unitId,
+                    subUnitId,
+                    range: {
+                        startRow: oldRange.startRow,
+                        endRow: oldRange.endRow,
+                        startColumn: index + count,
+                        endColumn: colContentIndex,
+                    },
+                },
+                {
+                    unitId,
+                    subUnitId,
+                    range: {
+                        startRow: oldRange.startRow,
+                        endRow: oldRange.endRow,
+                        startColumn: index,
+                        endColumn: colContentIndex - count,
+                    },
+                }
+            );
+
+            if (moveRangeMutations) {
+                redos.push(...moveRangeMutations.redos);
+                undos.push(...moveRangeMutations.undos);
+            }
+        }
+
+        return executeTableMutationSequence(accessor, unitId, redos, undos);
+    },
+};
+
 export const SheetTableRemoveRowCommand: ICommand<ISheetTableRowColOperationCommandParams> = {
     id: 'sheet.command.table-remove-row',
     type: CommandType.COMMAND,
diff --git a/packages/sheets-table/src/controllers/table-theme.factory.ts b/packages/sheets-table/src/controllers/table-theme.factory.ts
--- a/packages/sheets-table/src/controllers/table-theme.factory.ts
+++ b/packages/sheets-table/src/controllers/table-theme.factory.ts
@@ -83,7 +83,7 @@ export const processStyleWithBorderStyle = (key: keyof Omit<IRangeThemeStyleJSON
 };
 
 const tableDefaultThemeStyleArr = [
-    [['#6280F9', '#FFFFFF', '#BAC6F8', '#D2DAFA'], ['#fff']],
+    [['#6280F9', '#FFFFFF', '#EEF2FF', '#DCE4FF'], ['#fff']],
     [['#16BDCA', '#FFFFFF', '#EDFAFA', '#AFECEF'], ['#000']],
     [['#31C48D', '#FFFFFF', '#F3FAF7', '#BCF0DA'], ['#fff']],
     [['#AC94FA', '#FFFFFF', '#F6F5FF', '#EDEBFE'], ['#fff']],
diff --git a/packages/sheets-table/src/index.ts b/packages/sheets-table/src/index.ts
--- a/packages/sheets-table/src/index.ts
+++ b/packages/sheets-table/src/index.ts
@@ -23,7 +23,7 @@ export { RemoveTableThemeCommand } from './commands/commands/remove-table-theme.
 export { SetSheetTableCommand } from './commands/commands/set-sheet-table.command';
 export type { ISetSheetTableCommandParams } from './commands/commands/set-sheet-table.command';
 export { SetSheetTableFilterCommand } from './commands/commands/set-table-filter.command';
-export { SheetTableInsertColCommand, SheetTableInsertRowCommand, SheetTableRemoveColCommand, SheetTableRemoveRowCommand } from './commands/commands/sheet-table-row-col.command';
+export { SheetTableInsertColCommand, SheetTableInsertColumnAtCommand, SheetTableInsertRowAtCommand, SheetTableInsertRowCommand, SheetTableRemoveColCommand, SheetTableRemoveColumnAtCommand, SheetTableRemoveRowCommand } from './commands/commands/sheet-table-row-col.command';
 export { AddSheetTableMutation } from './commands/mutations/add-sheet-table.mutation';
 export type { IAddSheetTableParams } from './commands/mutations/add-sheet-table.mutation';
 export { DeleteSheetTableMutation } from './commands/mutations/delete-sheet-table.mutation';
@@ -42,4 +42,6 @@ export { SheetTableService } from './services/table-service';
 export { SheetsTableButtonStateEnum, SheetsTableSortStateEnum, TableColumnDataTypeEnum, TableColumnFilterTypeEnum, TableConditionTypeEnum, TableDateCompareTypeEnum, TableNumberCompareTypeEnum, TableStringCompareTypeEnum } from './types/enum';
 export type { ITableColumnJson, ITableConditionFilterItem, ITableData, ITableFilterItem, ITableInfo, ITableInfoWithUnitId, ITableManualFilterItem, ITableOptions, ITableRange, ITableRangeWithState, TableMetaType, TableRelationTupleType } from './types/type';
 export type { ITableJson, ITableSetConfig } from './types/type';
-export { isConditionFilter, isManualTableFilter } from './util';
+export { getExistingNamesSet, isConditionFilter, isManualTableFilter } from './util';
+export { validateSheetTableName } from './util/table-name';
+export type { ISheetTableNameValidationResult, SheetTableNameValidationReason } from './util/table-name';
diff --git a/packages/sheets-table/src/model/table-manager.ts b/packages/sheets-table/src/model/table-manager.ts
--- a/packages/sheets-table/src/model/table-manager.ts
+++ b/packages/sheets-table/src/model/table-manager.ts
@@ -327,8 +327,9 @@ export class TableManager extends Disposable {
             }
         } else if (newRange.endColumn > oldRange.endColumn) {
             const diff = newRange.endColumn - oldRange.endColumn;
+            const columnPrefix = this._localeService.t('sheets-table.columnPrefix');
             for (let i = 0; i < diff; i++) {
-                table.insertColumn(oldRange.endColumn, new TableColumn(generateRandomId(), getColumnName(table.getColumnsCount() + 1, 'Column')));
+                table.insertColumn(oldRange.endColumn, new TableColumn(generateRandomId(), getColumnName(table.getColumnsCount() + 1, columnPrefix)));
             }
         }
 
diff --git a/packages/sheets-table/src/plugin.ts b/packages/sheets-table/src/plugin.ts
--- a/packages/sheets-table/src/plugin.ts
+++ b/packages/sheets-table/src/plugin.ts
@@ -23,7 +23,7 @@ import { DeleteSheetTableCommand } from './commands/commands/delete-sheet-table.
 import { RemoveTableThemeCommand } from './commands/commands/remove-table-theme.command';
 import { SetSheetTableCommand } from './commands/commands/set-sheet-table.command';
 import { SetSheetTableFilterCommand } from './commands/commands/set-table-filter.command';
-import { SheetTableInsertColCommand, SheetTableInsertRowCommand, SheetTableRemoveColCommand, SheetTableRemoveRowCommand } from './commands/commands/sheet-table-row-col.command';
+import { SheetTableInsertColCommand, SheetTableInsertColumnAtCommand, SheetTableInsertRowAtCommand, SheetTableInsertRowCommand, SheetTableRemoveColCommand, SheetTableRemoveColumnAtCommand, SheetTableRemoveRowCommand } from './commands/commands/sheet-table-row-col.command';
 import { AddSheetTableMutation } from './commands/mutations/add-sheet-table.mutation';
 import { DeleteSheetTableMutation } from './commands/mutations/delete-sheet-table.mutation';
 import { SetSheetTableMutation } from './commands/mutations/set-sheet-table.mutation';
@@ -106,8 +106,11 @@ export class UniverSheetsTablePlugin extends Plugin {
             RemoveTableThemeCommand,
             SheetTableInsertRowCommand,
             SheetTableInsertColCommand,
+            SheetTableInsertRowAtCommand,
+            SheetTableInsertColumnAtCommand,
             SheetTableRemoveRowCommand,
             SheetTableRemoveColCommand,
+            SheetTableRemoveColumnAtCommand,
         ].forEach((m) => this._commandService.registerCommand(m));
     }
 }
diff --git a/packages/sheets-table/src/util/table-name.ts b/packages/sheets-table/src/util/table-name.ts
new file mode 100644
--- /dev/null
+++ b/packages/sheets-table/src/util/table-name.ts
@@ -0,0 +1,41 @@
+/**
+ * Copyright 2023-present DreamNum Co., Ltd.
+ *
+ * Licensed under the Apache License, Version 2.0 (the "License");
+ * you may not use this file except in compliance with the License.
+ * You may obtain a copy of the License at
+ *
+ *     http://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+
+import { customNameCharacterCheck } from '@univerjs/core';
+
+export type SheetTableNameValidationReason = 'empty' | 'invalid';
+
+export interface ISheetTableNameValidationResult {
+    valid: boolean;
+    reason?: SheetTableNameValidationReason;
+}
+
+export function validateSheetTableName(name: string, existingNamesSet: Set<string>): ISheetTableNameValidationResult {
+    const trimmedName = name.trim();
+
+    if (!trimmedName) {
+        return { valid: false, reason: 'empty' };
+    }
+
+    const normalizedExistingNames = new Set(Array.from(existingNamesSet, (item) => item.toLowerCase()));
+    const isValidName = customNameCharacterCheck(trimmedName.toLowerCase(), normalizedExistingNames);
+
+    if (!isValidName) {
+        return { valid: false, reason: 'invalid' };
+    }
+
+    return { valid: true };
+}
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
