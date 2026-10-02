#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.gitignore b/.gitignore
--- a/.gitignore
+++ b/.gitignore
@@ -270,6 +270,9 @@ lut-npyԤ��/Custom/*.npy
 LD_ColorLayering-main/
 ChromaStack-main/
 
+# 3MF metadata analysis files (local testing only)
+元数据分析/
+
 # Frontend
 node_modules/
 frontend/node_modules/
diff --git a/api/routers/converter.py b/api/routers/converter.py
--- a/api/routers/converter.py
+++ b/api/routers/converter.py
@@ -665,6 +665,23 @@ async def convert_generate(
         "matched_rgb_path": matched_rgb_path,
     }
 
+    # Read printer_model and slicer_software from user_settings.json for 3MF template selection
+    # 从 user_settings.json 读取 printer_model 和 slicer_software 用于 3MF 模板选择
+    printer_id: str = "bambu-h2d"
+    slicer_software: str = "BambuStudio"
+    try:
+        import json as _json
+        from pathlib import Path as _Path
+        _settings_file = _Path("user_settings.json")
+        if _settings_file.exists():
+            _settings_data = _json.loads(_settings_file.read_text(encoding="utf-8"))
+            printer_id = _settings_data.get("printer_model", "bambu-h2d")
+            slicer_software = _settings_data.get("slicer_software", "BambuStudio")
+    except Exception:
+        pass  # Use default on any read error
+    params["printer_id"] = printer_id
+    params["slicer"] = slicer_software
+
     # 3. CPU computation offloaded to process pool (only paths and scalars)
     try:
         result = await pool.submit(
diff --git a/api/routers/system.py b/api/routers/system.py
--- a/api/routers/system.py
+++ b/api/routers/system.py
@@ -20,7 +20,11 @@
     CacheCleanupDetails,
     ClearCacheResponse,
     ClearCacheResult,
+    PrinterInfo,
+    PrinterListResponse,
     SaveSettingsResponse,
+    SlicerInfo,
+    SlicerListResponse,
     StatsResponse,
     UserSettings,
     UserSettingsResponse,
@@ -122,6 +126,71 @@ def clear_cache(
     )
 
 
+# ---------------------------------------------------------------------------
+# Printers endpoint
+# ---------------------------------------------------------------------------
+
+
+@router.get("/printers")
+def get_printers() -> PrinterListResponse:
+    """Return all supported printer models.
+    返回所有支持的打印机型号列表。
+
+    Returns:
+        PrinterListResponse: List of printer metadata. (打印机元数据列表)
+    """
+    profiles = config.list_printer_profiles()
+    printers = []
+    for p in profiles:
+        # Build supported slicer list: default template → BambuStudio, plus slicer_templates keys
+        slicers = []
+        # If template_file starts with "bambu_", default slicer is BambuStudio
+        if p.template_file.startswith("bambu_"):
+            slicers.append("BambuStudio")
+        slicers.extend(p.slicer_templates.keys())
+        # Deduplicate while preserving order
+        seen: set[str] = set()
+        unique_slicers = []
+        for s in slicers:
+            if s not in seen:
+                seen.add(s)
+                unique_slicers.append(s)
+        printers.append(
+            PrinterInfo(
+                id=p.id,
+                display_name=p.display_name,
+                brand=p.brand,
+                bed_width=p.bed_width,
+                bed_depth=p.bed_depth,
+                bed_height=p.bed_height,
+                nozzle_count=p.nozzle_count,
+                is_dual_head=p.is_dual_head,
+                supported_slicers=unique_slicers,
+            )
+        )
+    return PrinterListResponse(status="success", printers=printers)
+
+
+# ---------------------------------------------------------------------------
+# Slicers endpoint
+# ---------------------------------------------------------------------------
+
+
+@router.get("/slicers")
+def get_slicers() -> SlicerListResponse:
+    """Return all supported slicer software options.
+    返回所有支持的切片器软件列表。
+
+    Returns:
+        SlicerListResponse: List of slicer metadata. (切片器元数据列表)
+    """
+    slicers = [
+        SlicerInfo(id=s["id"], display_name=s["display_name"])
+        for s in config.SUPPORTED_SLICERS
+    ]
+    return SlicerListResponse(status="success", slicers=slicers)
+
+
 # ---------------------------------------------------------------------------
 # Settings & Stats endpoints
 # ---------------------------------------------------------------------------
diff --git a/api/schemas/system.py b/api/schemas/system.py
--- a/api/schemas/system.py
+++ b/api/schemas/system.py
@@ -10,6 +10,31 @@
 from pydantic import BaseModel
 
 
+class PrinterInfo(BaseModel):
+    """Printer hardware metadata exposed to the frontend.
+    暴露给前端的打印机硬件元数据。
+    """
+
+    id: str
+    display_name: str
+    brand: str
+    bed_width: int
+    bed_depth: int
+    bed_height: int
+    nozzle_count: int
+    is_dual_head: bool
+    supported_slicers: list[str] = []
+
+
+class PrinterListResponse(BaseModel):
+    """Response for GET /api/system/printers.
+    GET /api/system/printers 响应。
+    """
+
+    status: str
+    printers: list[PrinterInfo]
+
+
 class CacheCleanupDetails(BaseModel):
     """缓存清理详情。"""
 
@@ -47,6 +72,8 @@ class UserSettings(BaseModel):
     last_slicer: str = ""
     palette_mode: str = "swatch"
     enable_crop_modal: bool = True
+    printer_model: str = "bambu-h2d"
+    slicer_software: str = "BambuStudio"
 
 
 class UserSettingsResponse(BaseModel):
@@ -69,3 +96,17 @@ class StatsResponse(BaseModel):
     calibrations: int = 0
     extractions: int = 0
     conversions: int = 0
+
+
+class SlicerInfo(BaseModel):
+    """切片器软件信息。"""
+
+    id: str
+    display_name: str
+
+
+class SlicerListResponse(BaseModel):
+    """GET /api/system/slicers 响应。"""
+
+    status: str
+    slicers: list[SlicerInfo]
diff --git a/bambu_config_template.json b/bambu_config_template.json
--- a/bambu_config_template.json
+++ b/bambu_config_template.json
@@ -1609,7 +1609,7 @@
     ],
     "print_flow_ratio": "1",
     "print_sequence": "by layer",
-    "print_settings_id": "版画",
+    "print_settings_id": "Bambu_Lumina",
     "printable_area": [
         "0x0",
         "350x0",
diff --git a/config.py b/config.py
--- a/config.py
+++ b/config.py
@@ -430,12 +430,189 @@ def get_tray_runtime_policy():
     return False, f"Disabled on unsupported platform: {sys.platform}"
 
 
-# ========== LUT Palette & Metadata ==========
+# ========== Printer Profile Registry ==========
 
 from dataclasses import dataclass, field
 from typing import Optional
 
 
+@dataclass
+class PrinterProfile:
+    """Printer hardware profile for 3MF export template selection.
+    打印机硬件配置，用于 3MF 导出模板选择。
+
+    Attributes:
+        id (str): Unique printer identifier, e.g. "bambu-h2d". (唯一打印机标识)
+        display_name (str): Human-readable name, e.g. "Bambu Lab H2D". (显示名称)
+        brand (str): Manufacturer brand, e.g. "Bambu Lab". (品牌)
+        bed_width (int): Print bed width in mm. (打印床宽度，毫米)
+        bed_depth (int): Print bed depth in mm. (打印床深度，毫米)
+        bed_height (int): Max print height in mm. (最大打印高度，毫米)
+        nozzle_count (int): Number of nozzles, 1=single, 2=dual. (喷头数量)
+        is_dual_head (bool): Whether the printer has dual print heads. (是否双头)
+        template_file (str): Default (BambuStudio) config template filename. (默认模板文件名)
+        slicer_templates (dict[str, str]): Slicer-specific template filenames. (切片器专属模板)
+        thumbnail (str): Thumbnail image filename, reserved for future use. (缩略图文件名，预留)
+    """
+    id: str
+    display_name: str
+    brand: str
+    bed_width: int
+    bed_depth: int
+    bed_height: int
+    nozzle_count: int
+    is_dual_head: bool
+    template_file: str
+    slicer_templates: dict = field(default_factory=dict)
+    thumbnail: str = ""
+
+    def get_template_file(self, slicer: str = "BambuStudio") -> str:
+        """Return template filename for the given slicer.
+        返回指定切片器的模板文件名。
+
+        Args:
+            slicer (str): Slicer identifier, e.g. "BambuStudio" or "OrcaSlicer". (切片器标识)
+
+        Returns:
+            str: Template filename. Falls back to default template_file. (模板文件名，回退到默认)
+        """
+        return self.slicer_templates.get(slicer, self.template_file)
+
+
+# Supported slicer software list
+SUPPORTED_SLICERS: list[dict[str, str]] = [
+    {"id": "BambuStudio", "display_name": "BambuStudio"},
+    {"id": "OrcaSlicer", "display_name": "OrcaSlicer"},
+    {"id": "SnapmakerOrca", "display_name": "Snapmaker Orca"},
+    {"id": "ElegooSlicer", "display_name": "ElegooSlicer"},
+]
+
+DEFAULT_SLICER_ID: str = "BambuStudio"
+
+
+PRINTER_PROFILES: dict[str, PrinterProfile] = {
+    "bambu-a1-mini": PrinterProfile(
+        id="bambu-a1-mini", display_name="Bambu Lab A1 mini", brand="Bambu Lab",
+        bed_width=180, bed_depth=180, bed_height=180,
+        nozzle_count=1, is_dual_head=False,
+        template_file="bambu_a1_mini.json",
+        slicer_templates={"OrcaSlicer": "orca_a1_mini.json"},
+    ),
+    "bambu-a1": PrinterProfile(
+        id="bambu-a1", display_name="Bambu Lab A1", brand="Bambu Lab",
+        bed_width=256, bed_depth=256, bed_height=256,
+        nozzle_count=1, is_dual_head=False,
+        template_file="bambu_a1.json",
+        slicer_templates={"OrcaSlicer": "orca_a1.json"},
+    ),
+    "bambu-p1p": PrinterProfile(
+        id="bambu-p1p", display_name="Bambu Lab P1P", brand="Bambu Lab",
+        bed_width=256, bed_depth=256, bed_height=256,
+        nozzle_count=1, is_dual_head=False,
+        template_file="bambu_p1p.json",
+        slicer_templates={"OrcaSlicer": "orca_p1p.json"},
+    ),
+    "bambu-p1s": PrinterProfile(
+        id="bambu-p1s", display_name="Bambu Lab P1S", brand="Bambu Lab",
+        bed_width=256, bed_depth=256, bed_height=250,
+        nozzle_count=1, is_dual_head=False,
+        template_file="bambu_p1s.json",
+        slicer_templates={"OrcaSlicer": "orca_p1s.json"},
+    ),
+    "bambu-x1c": PrinterProfile(
+        id="bambu-x1c", display_name="Bambu Lab X1 Carbon", brand="Bambu Lab",
+        bed_width=256, bed_depth=256, bed_height=256,
+        nozzle_count=1, is_dual_head=False,
+        template_file="bambu_x1c.json",
+        slicer_templates={"OrcaSlicer": "orca_x1c.json"},
+    ),
+    "bambu-x1e": PrinterProfile(
+        id="bambu-x1e", display_name="Bambu Lab X1E", brand="Bambu Lab",
+        bed_width=256, bed_depth=256, bed_height=256,
+        nozzle_count=1, is_dual_head=False,
+        template_file="bambu_x1e.json",
+        slicer_templates={"OrcaSlicer": "orca_x1e.json"},
+    ),
+    "bambu-h2d": PrinterProfile(
+        id="bambu-h2d", display_name="Bambu Lab H2D", brand="Bambu Lab",
+        bed_width=350, bed_depth=320, bed_height=325,
+        nozzle_count=2, is_dual_head=True,
+        template_file="bambu_h2d.json",
+        slicer_templates={"OrcaSlicer": "orca_h2d.json"},
+    ),
+    "bambu-h2d-pro": PrinterProfile(
+        id="bambu-h2d-pro", display_name="Bambu Lab H2D Pro", brand="Bambu Lab",
+        bed_width=350, bed_depth=320, bed_height=325,
+        nozzle_count=2, is_dual_head=True,
+        template_file="bambu_h2d_pro.json",
+        slicer_templates={"OrcaSlicer": "orca_h2d_pro.json"},
+    ),
+    "bambu-h2s": PrinterProfile(
+        id="bambu-h2s", display_name="Bambu Lab H2S", brand="Bambu Lab",
+        bed_width=350, bed_depth=320, bed_height=325,
+        nozzle_count=2, is_dual_head=True,
+        template_file="bambu_h2s.json",
+        slicer_templates={"OrcaSlicer": "orca_h2s.json"},
+    ),
+    "bambu-p2s": PrinterProfile(
+        id="bambu-p2s", display_name="Bambu Lab P2S", brand="Bambu Lab",
+        bed_width=256, bed_depth=256, bed_height=250,
+        nozzle_count=1, is_dual_head=False,
+        template_file="bambu_p2s.json",
+        slicer_templates={"OrcaSlicer": "orca_p2s.json"},
+    ),
+    "bambu-h2c": PrinterProfile(
+        id="bambu-h2c", display_name="Bambu Lab H2C", brand="Bambu Lab",
+        bed_width=350, bed_depth=320, bed_height=325,
+        nozzle_count=2, is_dual_head=True,
+        template_file="bambu_h2c.json",
+        slicer_templates={"OrcaSlicer": "orca_h2c.json"},
+    ),
+    "snapmaker-u1": PrinterProfile(
+        id="snapmaker-u1", display_name="Snapmaker U1", brand="Snapmaker",
+        bed_width=270, bed_depth=270, bed_height=270,
+        nozzle_count=4, is_dual_head=False,
+        template_file="snapmaker_u1.json",
+        slicer_templates={"SnapmakerOrca": "snapmaker_u1.json"},
+    ),
+    "elegoo-cc2": PrinterProfile(
+        id="elegoo-cc2", display_name="Elegoo Centauri Carbon 2", brand="Elegoo",
+        bed_width=256, bed_depth=256, bed_height=256,
+        nozzle_count=1, is_dual_head=False,
+        template_file="elegoo_cc2.json",
+        slicer_templates={"ElegooSlicer": "elegoo_cc2.json"},
+    ),
+}
+
+DEFAULT_PRINTER_ID: str = "bambu-h2d"
+
+
+def get_printer_profile(printer_id: str) -> PrinterProfile:
+    """Get printer profile by ID, falling back to default (H2D) for unknown IDs.
+    根据 ID 获取打印机配置，未知 ID 回退到默认机型 H2D。
+
+    Args:
+        printer_id (str): Printer identifier, e.g. "bambu-h2d". (打印机标识)
+
+    Returns:
+        PrinterProfile: Matching profile or default H2D profile. (匹配的配置或默认 H2D 配置)
+    """
+    return PRINTER_PROFILES.get(printer_id, PRINTER_PROFILES[DEFAULT_PRINTER_ID])
+
+
+def list_printer_profiles() -> list[PrinterProfile]:
+    """Return all supported printer profiles as a list.
+    返回所有支持的打印机配置列表。
+
+    Returns:
+        list[PrinterProfile]: All registered printer profiles. (所有已注册的打印机配置)
+    """
+    return list(PRINTER_PROFILES.values())
+
+
+# ========== LUT Palette & Metadata ==========
+
+
 @dataclass
 class PaletteEntry:
     """Palette entry: describes a single base color channel.
diff --git a/core/converter.py b/core/converter.py
--- a/core/converter.py
+++ b/core/converter.py
@@ -132,6 +132,8 @@ def convert_image_to_3d(image_path, lut_path, target_width_mm, spacer_thick,
                          loop_offset_x: float = 0.0,
                          loop_offset_y: float = 0.0,
                          loop_position_preset: Optional[str] = "top-center",
+                         printer_id: str = 'bambu-h2d',
+                         slicer: str = 'BambuStudio',
                          progress=None):
     """Main conversion function: Convert image to 3D model.
     主转换函数：将图像转换为 3D 模型。薄包装层，委托给 coordinator。
@@ -279,6 +281,8 @@ def generate_final_model(image_path, lut_path, target_width_mm, spacer_thick,
                         loop_offset_x: float = 0.0,
                         loop_offset_y: float = 0.0,
                         loop_position_preset: Optional[str] = "top-center",
+                        printer_id: str = 'bambu-h2d',
+                        slicer: str = 'BambuStudio',
                         progress=None):
     """Wrapper function for generating final model.
     生成最终模型的包装函数。
@@ -338,6 +342,8 @@ def generate_final_model(image_path, lut_path, target_width_mm, spacer_thick,
         loop_offset_x=loop_offset_x,
         loop_offset_y=loop_offset_y,
         loop_position_preset=loop_position_preset,
+        printer_id=printer_id,
+        slicer=slicer,
         progress=progress,
     )
 
diff --git a/core/pipeline/coordinator.py b/core/pipeline/coordinator.py
--- a/core/pipeline/coordinator.py
+++ b/core/pipeline/coordinator.py
@@ -312,6 +312,8 @@ def _run_vector_branch(ctx: dict) -> dict:
             preview_colors=vec_preview_colors,
             settings=vec_print_settings,
             color_mode=vec_color_mode,
+            printer_id=ctx.get('printer_id', 'bambu-h2d'),
+            slicer=ctx.get('slicer', 'BambuStudio'),
         )
         print(f"[COORDINATOR] Vector 3MF exported with Bambu metadata: {out_path}")
         vector_timing["export_3mf_s"] = time.perf_counter() - export_t0
diff --git a/core/pipeline/s09_export_3mf.py b/core/pipeline/s09_export_3mf.py
--- a/core/pipeline/s09_export_3mf.py
+++ b/core/pipeline/s09_export_3mf.py
@@ -135,7 +135,9 @@ def run(ctx: dict) -> dict:
             slot_names=valid_slot_names,
             preview_colors=preview_colors,
             settings=print_settings,
-            color_mode=color_mode
+            color_mode=color_mode,
+            printer_id=ctx.get('printer_id', 'bambu-h2d'),
+            slicer=ctx.get('slicer', 'BambuStudio'),
         )
         if _bench_enabled and _export_t0 is not None:
             _hifi_timings['export_3mf_s'] = time.perf_counter() - _export_t0
diff --git a/frontend/src/api/system.ts b/frontend/src/api/system.ts
--- a/frontend/src/api/system.ts
+++ b/frontend/src/api/system.ts
@@ -5,6 +5,10 @@ import type {
   UserSettingsResponse,
   SaveSettingsResponse,
   StatsResponse,
+  PrinterInfo,
+  PrinterListResponse,
+  SlicerOption,
+  SlicerListResponse,
 } from "./types";
 
 /** 调用后端清除系统缓存，返回清理统计信息 */
@@ -35,3 +39,15 @@ export async function getStats(): Promise<StatsResponse> {
   const response = await apiClient.get<StatsResponse>("/system/stats");
   return response.data;
 }
+
+/** 获取所有支持的打印机型号列表 */
+export async function getPrinters(): Promise<PrinterInfo[]> {
+  const response = await apiClient.get<PrinterListResponse>("/system/printers");
+  return response.data.printers;
+}
+
+/** 获取所有支持的切片器软件列表 */
+export async function getSlicers(): Promise<SlicerOption[]> {
+  const response = await apiClient.get<SlicerListResponse>("/system/slicers");
+  return response.data.slicers;
+}
diff --git a/frontend/src/api/types.ts b/frontend/src/api/types.ts
--- a/frontend/src/api/types.ts
+++ b/frontend/src/api/types.ts
@@ -402,6 +402,25 @@ export interface RegionReplaceResponse {
   message: string;
 }
 
+// ========== Printer Models ==========
+
+export interface PrinterInfo {
+  id: string;
+  display_name: string;
+  brand: string;
+  bed_width: number;
+  bed_depth: number;
+  bed_height: number;
+  nozzle_count: number;
+  is_dual_head: boolean;
+  supported_slicers: string[];
+}
+
+export interface PrinterListResponse {
+  status: string;
+  printers: PrinterInfo[];
+}
+
 // ========== Settings Models ==========
 
 export interface UserSettings {
@@ -411,6 +430,8 @@ export interface UserSettings {
   last_slicer: string;
   palette_mode: string;
   enable_crop_modal: boolean;
+  printer_model: string;
+  slicer_software: string;
 }
 
 export interface UserSettingsResponse {
@@ -428,3 +449,15 @@ export interface StatsResponse {
   extractions: number;
   conversions: number;
 }
+
+// ========== Slicer Template Models ==========
+
+export interface SlicerOption {
+  id: string;
+  display_name: string;
+}
+
+export interface SlicerListResponse {
+  status: string;
+  slicers: SlicerOption[];
+}
diff --git a/frontend/src/components/SettingsPanel.tsx b/frontend/src/components/SettingsPanel.tsx
--- a/frontend/src/components/SettingsPanel.tsx
+++ b/frontend/src/components/SettingsPanel.tsx
@@ -1,12 +1,14 @@
 /**
  * SettingsPanel - System settings page.
- * 系统设置页面，包含缓存清理功能。
+ * 系统设置页面，包含切片软件设置和缓存清理功能。
  */
 
 import { motion } from "framer-motion";
-import { useState } from "react";
+import { useState, useEffect } from "react";
 import { useI18n } from "../i18n/context";
-import { clearCache } from "../api/system";
+import { clearCache, getPrinters, getSlicers } from "../api/system";
+import { useSettingsStore } from "../stores/settingsStore";
+import type { PrinterInfo, SlicerOption } from "../api/types";
 import Button from "./ui/Button";
 import { PanelIntro, StatusBanner, centeredPanelClass, sectionCardClass } from "./ui/panelPrimitives";
 
@@ -16,6 +18,88 @@ export default function SettingsPanel() {
   const [clearing, setClearing] = useState(false);
   const [cacheResult, setCacheResult] = useState<string | null>(null);
 
+  // Printer list state (task 5.2)
+  const [printers, setPrinters] = useState<PrinterInfo[]>([]);
+  const [printersLoading, setPrintersLoading] = useState(true);
+
+  // Slicer list state
+  const [slicers, setSlicers] = useState<SlicerOption[]>([]);
+  const [slicersLoading, setSlicersLoading] = useState(true);
+
+  // Store state (task 5.3)
+  const printerModel = useSettingsStore((s) => s.printerModel);
+  const setPrinterModel = useSettingsStore((s) => s.setPrinterModel);
+  const slicerSoftware = useSettingsStore((s) => s.slicerSoftware);
+  const setSlicerSoftware = useSettingsStore((s) => s.setSlicerSoftware);
+  const setLastBedLabel = useSettingsStore((s) => s.setLastBedLabel);
+  const syncToBackend = useSettingsStore((s) => s.syncToBackend);
+
+  // Load printers and slicers on mount
+  useEffect(() => {
+    let cancelled = false;
+    setPrintersLoading(true);
+    setSlicersLoading(true);
+    getPrinters()
+      .then((list) => {
+        if (!cancelled) setPrinters(list);
+      })
+      .catch(() => {})
+      .finally(() => {
+        if (!cancelled) setPrintersLoading(false);
+      });
+    getSlicers()
+      .then((list) => {
+        if (!cancelled) setSlicers(list);
+      })
+      .catch(() => {})
+      .finally(() => {
+        if (!cancelled) setSlicersLoading(false);
+      });
+    return () => { cancelled = true; };
+  }, []);
+
+  // Filter printers by selected slicer
+  const filteredPrinters = printers.filter(
+    (p) =>
+      !p.supported_slicers ||
+      p.supported_slicers.length === 0 ||
+      p.supported_slicers.includes(slicerSoftware)
+  );
+
+  // Handle printer selection change (task 5.3 + 6.1)
+  const handlePrinterChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
+    const id = e.target.value;
+    setPrinterModel(id);
+    const selected = printers.find((p) => p.id === id);
+    if (selected) {
+      setLastBedLabel(`${selected.bed_width}×${selected.bed_depth} mm`);
+    }
+    syncToBackend();
+  };
+
+  // Handle slicer selection change — auto-select first compatible printer
+  const handleSlicerChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
+    const id = e.target.value;
+    setSlicerSoftware(id);
+    // If current printer doesn't support the new slicer, switch to first compatible
+    const compatible = printers.filter(
+      (p) =>
+        !p.supported_slicers ||
+        p.supported_slicers.length === 0 ||
+        p.supported_slicers.includes(id)
+    );
+    const currentStillValid = compatible.some((p) => p.id === printerModel);
+    if (!currentStillValid && compatible.length > 0) {
+      setPrinterModel(compatible[0].id);
+      setLastBedLabel(
+        `${compatible[0].bed_width}×${compatible[0].bed_depth} mm`
+      );
+    }
+    syncToBackend();
+  };
+
+  const selectedPrinter = printers.find((p) => p.id === printerModel);
+
   const handleClearCache = async () => {
     setClearing(true);
     setCacheResult(null);
@@ -50,6 +134,72 @@ export default function SettingsPanel() {
         description={t("settings.desc")}
       />
 
+      <section className={`${sectionCardClass} flex flex-col gap-4`}>
+        <div>
+          <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
+            {t("settings.slicer_settings")}
+          </p>
+          <h4 className="mt-1 text-base font-semibold text-slate-900 dark:text-slate-50">
+            {t("settings.printer_model")}
+          </h4>
+        </div>
+        <div className="grid gap-4 md:grid-cols-2">
+          <label className="flex flex-col gap-1.5">
+            <span className="text-sm text-slate-500 dark:text-slate-400">
+              {t("settings.slicer_software")}
+            </span>
+            <select
+              id="slicer-software-select"
+              value={slicerSoftware}
+              onChange={handleSlicerChange}
+              disabled={slicersLoading}
+              className="w-full rounded-xl border border-slate-200 bg-white/90 px-3 py-2.5 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 disabled:cursor-wait disabled:opacity-50 dark:border-slate-700 dark:bg-slate-950/70 dark:text-slate-100 dark:focus:border-slate-500 dark:focus:ring-slate-800"
+            >
+              {slicers.map((s) => (
+                <option key={s.id} value={s.id}>
+                  {s.display_name}
+                </option>
+              ))}
+            </select>
+          </label>
+          <label className="flex flex-col gap-1.5">
+            <span className="text-sm text-slate-500 dark:text-slate-400">
+              {t("settings.printer_model")}
+            </span>
+            <select
+              id="printer-model-select"
+              value={printerModel}
+              onChange={handlePrinterChange}
+              disabled={printersLoading}
+              className="w-full rounded-xl border border-slate-200 bg-white/90 px-3 py-2.5 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 disabled:cursor-wait disabled:opacity-50 dark:border-slate-700 dark:bg-slate-950/70 dark:text-slate-100 dark:focus:border-slate-500 dark:focus:ring-slate-800"
+            >
+              {filteredPrinters.map((p) => (
+                <option key={p.id} value={p.id}>
+                  {p.display_name}
+                </option>
+              ))}
+            </select>
+          </label>
+        </div>
+        {selectedPrinter && (
+          <div className="flex flex-wrap items-center gap-3 text-xs text-slate-500 dark:text-slate-400">
+            <span>
+              {t("settings.bed_size")}: {selectedPrinter.bed_width}&times;{selectedPrinter.bed_depth} mm
+            </span>
+            <span className="text-slate-300 dark:text-slate-600">|</span>
+            <span>
+              {t("settings.nozzle_count")}: {selectedPrinter.nozzle_count}
+            </span>
+            <span className="text-slate-300 dark:text-slate-600">|</span>
+            <span>
+              {selectedPrinter.is_dual_head
+                ? t("settings.dual_head")
+                : t("settings.single_head")}
+            </span>
+          </div>
+        )}
+      </section>
+
       <section className={`${sectionCardClass} flex flex-col gap-4`}>
         <div>
           <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
diff --git a/frontend/src/components/sections/SlicerSelector.tsx b/frontend/src/components/sections/SlicerSelector.tsx
--- a/frontend/src/components/sections/SlicerSelector.tsx
+++ b/frontend/src/components/sections/SlicerSelector.tsx
@@ -1,4 +1,5 @@
-import { useEffect, useRef, useState } from "react";
+import { useCallback, useEffect, useRef, useState } from "react";
+import { createPortal } from "react-dom";
 import { useSlicerStore } from "../../stores/slicerStore";
 import { useConverterStore } from "../../stores/converterStore";
 import { useI18n } from "../../i18n/context";
@@ -91,9 +92,21 @@ export default function SlicerSelector({
 
   const [isDropdownOpen, setIsDropdownOpen] = useState(false);
   const [isAutoGenerating, setIsAutoGenerating] = useState(false);
+  const triggerRef = useRef<HTMLDivElement>(null);
   const dropdownRef = useRef<HTMLDivElement>(null);
+  const [dropdownPos, setDropdownPos] = useState<{ top: number; left: number; width: number } | null>(null);
   const { t } = useI18n();
 
+  /**
+   * Compute dropdown position above the trigger button via getBoundingClientRect.
+   * 通过 getBoundingClientRect 计算下拉菜单在触发按钮上方的位置。
+   */
+  const updateDropdownPos = useCallback(() => {
+    if (!triggerRef.current) return;
+    const rect = triggerRef.current.getBoundingClientRect();
+    setDropdownPos({ top: rect.top, left: rect.left, width: rect.width });
+  }, []);
+
   // Auto-detect slicers on mount
   useEffect(() => {
     void detectSlicers();
@@ -106,17 +119,33 @@ export default function SlicerSelector({
     return () => clearTimeout(timer);
   }, [launchMessage, error, clearMessage]);
 
-  // Close dropdown when clicking outside
+  // Close dropdown when clicking outside (check both trigger and portal)
   useEffect(() => {
     const handleClickOutside = (e: MouseEvent) => {
-      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
+      const target = e.target as Node;
+      if (
+        triggerRef.current && !triggerRef.current.contains(target) &&
+        dropdownRef.current && !dropdownRef.current.contains(target)
+      ) {
         setIsDropdownOpen(false);
       }
     };
     document.addEventListener("mousedown", handleClickOutside);
     return () => document.removeEventListener("mousedown", handleClickOutside);
   }, []);
 
+  // Recalculate position on scroll/resize while open
+  useEffect(() => {
+    if (!isDropdownOpen) return;
+    updateDropdownPos();
+    window.addEventListener("scroll", updateDropdownPos, true);
+    window.addEventListener("resize", updateDropdownPos);
+    return () => {
+      window.removeEventListener("scroll", updateDropdownPos, true);
+      window.removeEventListener("resize", updateDropdownPos);
+    };
+  }, [isDropdownOpen, updateDropdownPos]);
+
   const hasSlicers = slicers.length > 0;
   const selectedSlicer = slicers.find((s) => s.id === selectedSlicerId);
   const brandStyle = selectedSlicerId
@@ -208,7 +237,7 @@ export default function SlicerSelector({
   return (
     <div className="flex flex-col gap-2">
       {hasSlicers ? (
-        <div className="relative" ref={dropdownRef}>
+        <div className="relative" ref={triggerRef}>
           {/* Split Button */}
           <div className="flex">
             {/* Main button with brand color */}
@@ -243,9 +272,19 @@ export default function SlicerSelector({
             </button>
           </div>
 
-          {/* Dropdown menu */}
-          {isDropdownOpen && (
-            <div className="absolute bottom-[calc(100%+4px)] right-0 z-50 w-full min-w-[200px] rounded-md border border-gray-200 bg-white dark:border-gray-600 dark:bg-gray-800 py-1 shadow-lg" role="listbox">
+          {/* Dropdown menu — rendered via Portal to escape overflow clipping */}
+          {isDropdownOpen && dropdownPos && createPortal(
+            <div
+              ref={dropdownRef}
+              style={{
+                position: "fixed",
+                bottom: `${window.innerHeight - dropdownPos.top + 4}px`,
+                left: `${dropdownPos.left}px`,
+                width: `${Math.max(dropdownPos.width, 200)}px`,
+              }}
+              className="z-[9999] rounded-md border border-gray-200 bg-white dark:border-gray-600 dark:bg-gray-800 py-1 shadow-lg"
+              role="listbox"
+            >
               {slicers.map((slicer) => {
                 const style = getSlicerBrandStyle(slicer.id);
                 const isSelected = slicer.id === selectedSlicerId;
@@ -279,7 +318,8 @@ export default function SlicerSelector({
                 </svg>
                 {t("slicer_download_3mf")}
               </button>
-            </div>
+            </div>,
+            document.body,
           )}
         </div>
       ) : (
diff --git a/frontend/src/i18n/translations.ts b/frontend/src/i18n/translations.ts
--- a/frontend/src/i18n/translations.ts
+++ b/frontend/src/i18n/translations.ts
@@ -1241,6 +1241,37 @@ export const translations: Record<string, Record<"zh" | "en", string>> = {
     zh: "清除缓存失败，请稍后重试",
     en: "Failed to clear cache. Please try again.",
   },
+
+
+  // ==================== Settings Panel (Slicer Settings) ====================
+  "settings.slicer_settings": {
+    zh: "切片软件设置",
+    en: "Slicer Settings",
+  },
+  "settings.slicer_software": {
+    zh: "切片软件",
+    en: "Slicer Software",
+  },
+  "settings.printer_model": {
+    zh: "打印机型号",
+    en: "Printer Model",
+  },
+  "settings.bed_size": {
+    zh: "打印床尺寸",
+    en: "Bed Size",
+  },
+  "settings.nozzle_count": {
+    zh: "喷头数量",
+    en: "Nozzle Count",
+  },
+  "settings.dual_head": {
+    zh: "双头",
+    en: "Dual Head",
+  },
+  "settings.single_head": {
+    zh: "单头",
+    en: "Single Head",
+  },
   "loading.generating": {
     zh: "模型生成中...",
     en: "Generating model...",
diff --git a/frontend/src/stores/settingsStore.ts b/frontend/src/stores/settingsStore.ts
--- a/frontend/src/stores/settingsStore.ts
+++ b/frontend/src/stores/settingsStore.ts
@@ -16,6 +16,8 @@ export interface SettingsState {
   enableBlur: boolean;
   enableFancyLoading: boolean;
   paletteMode: "swatch" | "card";
+  printerModel: string;
+  slicerSoftware: string;
 }
 
 // ========== Actions Interface ==========
@@ -32,6 +34,8 @@ export interface SettingsActions {
   setEnableBlur: (enabled: boolean) => void;
   setEnableFancyLoading: (enabled: boolean) => void;
   setPaletteMode: (mode: "swatch" | "card") => void;
+  setPrinterModel: (id: string) => void;
+  setSlicerSoftware: (id: string) => void;
   syncToBackend: () => Promise<void>;
 }
 
@@ -49,6 +53,8 @@ export const DEFAULT_SETTINGS: SettingsState = {
   enableBlur: true,
   enableFancyLoading: true,
   paletteMode: "swatch",
+  printerModel: "bambu-h2d",
+  slicerSoftware: "BambuStudio",
 };
 
 // ========== Store ==========
@@ -80,6 +86,10 @@ export const useSettingsStore = create<SettingsState & SettingsActions>()(
 
       setPaletteMode: (mode: "swatch" | "card") => set({ paletteMode: mode }),
 
+      setPrinterModel: (id: string) => set({ printerModel: id }),
+
+      setSlicerSoftware: (id: string) => set({ slicerSoftware: id }),
+
       syncToBackend: async () => {
         const state = get();
         try {
@@ -90,6 +100,8 @@ export const useSettingsStore = create<SettingsState & SettingsActions>()(
             last_slicer: state.lastSlicerId,
             palette_mode: state.paletteMode,
             enable_crop_modal: state.cropEnabled,
+            printer_model: state.printerModel,
+            slicer_software: state.slicerSoftware,
           });
         } catch {
           // best-effort sync — settings are already persisted in localStorage
diff --git a/printer_profiles/bambu_a1.json b/printer_profiles/bambu_a1.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_a1.json
@@ -0,0 +1,2176 @@
+{
+    "accel_to_decel_enable": "0",
+    "accel_to_decel_factor": "50%",
+    "activate_air_filtration": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "additional_cooling_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "apply_scarf_seam_on_circles": "1",
+    "apply_top_surface_compensation": "0",
+    "auxiliary_fan": "0",
+    "avoid_crossing_wall_includes_support": "0",
+    "bed_custom_model": "",
+    "bed_custom_texture": "",
+    "bed_exclude_area": [],
+    "bed_temperature_formula": "by_first_filament",
+    "before_layer_change_gcode": "",
+    "best_object_pos": "0.5,0.5",
+    "bottom_color_penetration_layers": "3",
+    "bottom_shell_layers": "0",
+    "bottom_shell_thickness": "0",
+    "bottom_surface_density": "100%",
+    "bottom_surface_pattern": "monotonic",
+    "bridge_angle": "0",
+    "bridge_flow": "1",
+    "bridge_no_support": "0",
+    "bridge_speed": [
+        "50"
+    ],
+    "brim_object_gap": "0.1",
+    "brim_type": "auto_brim",
+    "brim_width": "5",
+    "chamber_temperatures": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "change_filament_gcode": ";===== A1mini 20251031 =====\nG392 S0\nM1007 S0\nM620 S[next_extruder]A\nM204 S9000\nG1 Z{max_layer_z + 3.0} F1200\n\nM400\nM106 P1 S0\nM106 P2 S0\n{if old_filament_temp > 142 && next_extruder < 255}\nM104 S[old_filament_temp]\n{endif}\n\nG1 X180 F18000\n\n{if long_retractions_when_cut[previous_extruder]}\nM620.11 S1 I[previous_extruder] E-{retraction_distances_when_cut[previous_extruder]} F1200\n{else}\nM620.11 S0\n{endif}\nM400\n\nM620.1 E F{flush_volumetric_speeds[previous_extruder]/2.4053*60} T{flush_temperatures[previous_extruder]}\nM620.10 A0 F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nT[next_extruder]\nM620.1 E F{flush_volumetric_speeds[next_extruder]/2.4053*60} T{flush_temperatures[next_extruder]}\nM620.10 A1 F{flush_volumetric_speeds[next_extruder]/2.4053*60} L[flush_length] H[nozzle_diameter] T{flush_temperatures[next_extruder]}\n\nG1 Y90 F9000\n\n{if next_extruder < 255}\n\n{if long_retractions_when_cut[previous_extruder]}\nM620.11 S1 I[previous_extruder] E{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nM628 S1\nG92 E0\nG1 E{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nM400\nM629 S1\n{else}\nM620.11 S0\n{endif}\n\nM400\nG92 E0\nM628 S0\n\n{if flush_length_1 > 1}\n; FLUSH_START\n; always use highest temperature to flush\nM400\nM1002 set_filament_type:UNKNOWN\nM109 S[flush_temperatures[next_extruder]]\nM106 P1 S60\n{if flush_length_1 > 23.7}\nG1 E23.7 F{flush_volumetric_speeds[previous_extruder]/2.4053*60} ; do not need pulsatile flushing for start part\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\n{else}\nG1 E{flush_length_1} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\n{endif}\n; FLUSH_END\nG1 E-[old_retract_length_toolchange] F1800\nG1 E[old_retract_length_toolchange] F300\nM400\nM1002 set_filament_type:{filament_type[next_extruder]}\n{endif}\n\n{if flush_length_1 > 45 && flush_length_2 > 1}\n; WIPE\nM400\nM106 P1 S178\nM400 S3\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nM400\nM106 P1 S0\n{endif}\n\n{if flush_length_2 > 1}\nM106 P1 S60\n; FLUSH_START\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\n; FLUSH_END\nG1 E-[new_retract_length_toolchange] F1800\nG1 E[new_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_2 > 45 && flush_length_3 > 1}\n; WIPE\nM400\nM106 P1 S178\nM400 S3\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nM400\nM106 P1 S0\n{endif}\n\n{if flush_length_3 > 1}\nM106 P1 S60\n; FLUSH_START\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\n; FLUSH_END\nG1 E-[new_retract_length_toolchange] F1800\nG1 E[new_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_3 > 45 && flush_length_4 > 1}\n; WIPE\nM400\nM106 P1 S178\nM400 S3\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nM400\nM106 P1 S0\n{endif}\n\n{if flush_length_4 > 1}\nM106 P1 S60\n; FLUSH_START\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\n; FLUSH_END\n{endif}\n\nM629\n\nM400\nM106 P1 S60\nM109 S[new_filament_temp]\nG1 E5 F{flush_volumetric_speeds[next_extruder]/2.4053*60} ;Compensate for filament spillage during waiting temperature\nM400\nG92 E0\nG1 E-[new_retract_length_toolchange] F1800\nM400\nM106 P1 S178\nM400 S3\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nM400\nG1 Z{max_layer_z + 3.0} F3000\nM106 P1 S0\n{if layer_z <= (initial_layer_print_height + 0.001)}\nM204 S[initial_layer_acceleration]\n{else}\nM204 S[default_acceleration]\n{endif}\n{else}\nG1 X[x_after_toolchange] Y[y_after_toolchange] Z[z_after_toolchange] F12000\n{endif}\n\nM622.1 S0\nM9833 F{outer_wall_volumetric_speed/2.4} A0.3 ; cali dynamic extrusion compensation\nM1002 judge_flag filament_need_cali_flag\nM622 J1\n  G92 E0\n  G1 E-[new_retract_length_toolchange] F1800\n  M400\n  \n  M106 P1 S178\n  M400 S7\n  G1 X0 F18000\n  G1 X-13.5 F3000\n  G1 X0 F18000 ;wipe and shake\n  G1 X-13.5 F3000\n  G1 X0 F12000 ;wipe and shake\n  G1 X-13.5 F3000\n  G1 X0 F12000 ;wipe and shake\n  M400\n  M106 P1 S0 \nM623\n\nM621 S[next_extruder]A\nG392 S0\n\nM1007 S1\n",
+    "circle_compensation_manual_offset": "0",
+    "circle_compensation_speed": [
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200"
+    ],
+    "close_fan_the_first_x_layers": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "complete_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "cool_plate_temp": [
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cool_plate_temp_initial_layer": [
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cooling_filter_enabled": "0",
+    "cooling_perimeter_transition_distance": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "cooling_slowdown_logic": [
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling"
+    ],
+    "counter_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "counter_coef_2": [
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008"
+    ],
+    "counter_coef_3": [
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041"
+    ],
+    "counter_limit_max": [
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033"
+    ],
+    "counter_limit_min": [
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035"
+    ],
+    "curr_bed_type": "Textured PEI Plate",
+    "default_acceleration": [
+        "6000"
+    ],
+    "default_filament_colour": [
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "default_filament_profile": [
+        "Bambu PLA Basic @BBL A1"
+    ],
+    "default_jerk": "0",
+    "default_nozzle_volume_type": [
+        "Standard"
+    ],
+    "default_print_profile": "0.20mm Standard @BBL A1",
+    "deretraction_speed": [
+        "30"
+    ],
+    "detect_floating_vertical_shell": "1",
+    "detect_narrow_internal_solid_infill": "0",
+    "detect_overhang_wall": "1",
+    "detect_thin_wall": "0",
+    "diameter_limit": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "different_settings_to_system": [
+        "bottom_shell_layers;detect_narrow_internal_solid_infill;initial_layer_flow_ratio;initial_layer_line_width;initial_layer_print_height;layer_height;only_one_wall_first_layer;prime_tower_rib_wall;prime_tower_width;skeleton_infill_density;skin_infill_density;sparse_infill_density;sparse_infill_pattern;top_shell_layers;wall_loops",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "draft_shield": "disabled",
+    "during_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "elefant_foot_compensation": "0",
+    "embedding_wall_into_infill": "0",
+    "enable_arc_fitting": "1",
+    "enable_circle_compensation": "0",
+    "enable_height_slowdown": [
+        "0"
+    ],
+    "enable_long_retraction_when_cut": "2",
+    "enable_overhang_bridge_fan": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_overhang_speed": [
+        "1"
+    ],
+    "enable_pre_heating": "0",
+    "enable_pressure_advance": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_prime_tower": "1",
+    "enable_support": "0",
+    "enable_support_ironing": "0",
+    "enable_tower_interface_features": "0",
+    "enable_wrapping_detection": "0",
+    "enforce_support_layers": "0",
+    "eng_plate_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "eng_plate_temp_initial_layer": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "ensure_vertical_shell_thickness": "enabled",
+    "exclude_object": "1",
+    "extruder_ams_count": [
+        "1#0|4#0",
+        "1#0|4#0"
+    ],
+    "extruder_clearance_dist_to_rod": "56.5",
+    "extruder_clearance_height_to_lid": "180",
+    "extruder_clearance_height_to_rod": "25",
+    "extruder_clearance_max_radius": "73",
+    "extruder_colour": [
+        "#018001"
+    ],
+    "extruder_max_nozzle_count": [
+        "1"
+    ],
+    "extruder_nozzle_stats": [
+        "Standard#1"
+    ],
+    "extruder_offset": [
+        "0x0"
+    ],
+    "extruder_printable_area": [
+        "0x0,256x0,256x256,0x256"
+    ],
+    "extruder_printable_height": [
+        "256"
+    ],
+    "extruder_type": [
+        "Direct Drive"
+    ],
+    "extruder_variant_list": [
+        "Direct Drive Standard"
+    ],
+    "fan_cooling_layer_time": [
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "fan_direction": "undefine",
+    "fan_max_speed": [
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "fan_min_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_adaptive_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_adhesiveness_category": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_bridge_speed": [
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25"
+    ],
+    "filament_change_length": [
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5"
+    ],
+    "filament_change_length_nc": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_colour": [
+        "#FFFFFF",
+        "#0080FF",
+        "#FF00FF",
+        "#FFFF00",
+        "#000000",
+        "#FF0000",
+        "#0000FF",
+        "#00FF00"
+    ],
+    "filament_colour_type": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_cooling_before_tower": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_cost": [
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99"
+    ],
+    "filament_density": [
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26"
+    ],
+    "filament_deretraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_dev_ams_drying_ams_limitations": [
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0"
+    ],
+    "filament_dev_ams_drying_heat_distortion_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_chamber_drying_bed_temperature": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "filament_dev_chamber_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_drying_cooling_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_drying_softening_temperature": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_diameter": [
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75"
+    ],
+    "filament_enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_end_gcode": [
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n"
+    ],
+    "filament_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard"
+    ],
+    "filament_flow_ratio": [
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98"
+    ],
+    "filament_flush_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_flush_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ids": [
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00"
+    ],
+    "filament_is_support": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_long_retractions_when_cut": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map_mode": "Auto For Flush",
+    "filament_max_volumetric_speed": [
+        "21",
+        "21",
+        "21",
+        "21",
+        "21",
+        "21",
+        "21",
+        "21"
+    ],
+    "filament_minimal_purge_on_wipe_tower": [
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15"
+    ],
+    "filament_multi_colour": [
+        "#FFFFFF",
+        "#0080FF",
+        "#FF00FF",
+        "#FFFF00",
+        "#000000",
+        "#FF0000",
+        "#0000FF",
+        "#00FF00"
+    ],
+    "filament_notes": "",
+    "filament_nozzle_map": [
+        "1",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_1_4_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_2_4_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_overhang_3_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_pre_cooling_temperature": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_pre_cooling_temperature_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_prime_volume": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_prime_volume_nc": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_printable": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "filament_ramming_travel_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_travel_time_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_volumetric_speed": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_ramming_volumetric_speed_nc": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_retract_before_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_length_nc": [
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14"
+    ],
+    "filament_retract_restart_extra": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_when_changing_layer": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_distances_when_cut": [
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18"
+    ],
+    "filament_retraction_length": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_minimum_travel": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_scarf_gap": [
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "filament_scarf_height": [
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%"
+    ],
+    "filament_scarf_length": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_scarf_seam_type": [
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none"
+    ],
+    "filament_self_index": [
+        "1",
+        "2",
+        "3",
+        "4",
+        "5",
+        "6",
+        "7",
+        "8"
+    ],
+    "filament_settings_id": [
+        "Bambu PLA Basic @BBL A1",
+        "Bambu PLA Basic @BBL A1",
+        "Bambu PLA Basic @BBL A1",
+        "Bambu PLA Basic @BBL A1",
+        "Bambu PLA Basic @BBL A1",
+        "Bambu PLA Basic @BBL A1",
+        "Bambu PLA Basic @BBL A1",
+        "Bambu PLA Basic @BBL A1"
+    ],
+    "filament_shrink": [
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "filament_soluble": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_start_gcode": [
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}"
+    ],
+    "filament_tower_interface_pre_extrusion_dist": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_tower_interface_pre_extrusion_length": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_tower_interface_print_temp": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_tower_interface_purge_volume": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "filament_tower_ironing_area": [
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_type": [
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA"
+    ],
+    "filament_velocity_adaptation_factor": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_vendor": [
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab"
+    ],
+    "filament_volume_map": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_wipe_distance": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop_types": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filename_format": "{input_filename_base}_{filament_type[0]}_{print_time}.gcode",
+    "fill_multiline": "1",
+    "filter_out_gap_fill": "0",
+    "first_layer_print_sequence": [
+        "0"
+    ],
+    "first_x_layer_fan_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "flush_into_infill": "0",
+    "flush_into_objects": "0",
+    "flush_into_support": "1",
+    "flush_multiplier": [
+        "1"
+    ],
+    "flush_volumes_matrix": [
+        "0",
+        "305",
+        "304",
+        "282",
+        "128",
+        "310",
+        "320",
+        "296",
+        "589",
+        "0",
+        "329",
+        "579",
+        "144",
+        "282",
+        "180",
+        "438",
+        "588",
+        "278",
+        "0",
+        "577",
+        "144",
+        "282",
+        "290",
+        "436",
+        "355",
+        "299",
+        "299",
+        "0",
+        "168",
+        "304",
+        "314",
+        "290",
+        "608",
+        "506",
+        "508",
+        "498",
+        "0",
+        "456",
+        "355",
+        "588",
+        "634",
+        "397",
+        "355",
+        "588",
+        "138",
+        "0",
+        "285",
+        "491",
+        "709",
+        "364",
+        "456",
+        "701",
+        "128",
+        "441",
+        "0",
+        "577",
+        "508",
+        "285",
+        "285",
+        "456",
+        "155",
+        "290",
+        "299",
+        "0"
+    ],
+    "flush_volumes_vector": [
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140"
+    ],
+    "from": "project",
+    "full_fan_speed_layer": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "fuzzy_skin": "none",
+    "fuzzy_skin_point_distance": "0.8",
+    "fuzzy_skin_thickness": "0.3",
+    "gap_infill_speed": [
+        "250"
+    ],
+    "gcode_add_line_number": "0",
+    "gcode_flavor": "marlin",
+    "grab_length": [
+        "17.4"
+    ],
+    "group_algo_with_time": "0",
+    "has_scarf_joint_seam": "0",
+    "head_wrap_detect_zone": [
+        "156x152",
+        "180x152",
+        "180x180",
+        "156x180"
+    ],
+    "hole_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "hole_coef_2": [
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008"
+    ],
+    "hole_coef_3": [
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415"
+    ],
+    "hole_limit_max": [
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22"
+    ],
+    "hole_limit_min": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "host_type": "octoprint",
+    "hot_plate_temp": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "hot_plate_temp_initial_layer": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "hotend_cooling_rate": [
+        "2"
+    ],
+    "hotend_heating_rate": [
+        "2"
+    ],
+    "impact_strength_z": [
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8"
+    ],
+    "independent_support_layer_height": "1",
+    "infill_combination": "0",
+    "infill_direction": "45",
+    "infill_instead_top_bottom_surfaces": "0",
+    "infill_jerk": "9",
+    "infill_lock_depth": "1",
+    "infill_rotate_step": "0",
+    "infill_shift_step": "0.4",
+    "infill_wall_overlap": "15%",
+    "initial_layer_acceleration": [
+        "500"
+    ],
+    "initial_layer_flow_ratio": "1.05",
+    "initial_layer_infill_speed": [
+        "105"
+    ],
+    "initial_layer_jerk": "9",
+    "initial_layer_line_width": "0.42",
+    "initial_layer_print_height": "0.08",
+    "initial_layer_speed": [
+        "50"
+    ],
+    "initial_layer_travel_acceleration": [
+        "6000"
+    ],
+    "inner_wall_acceleration": [
+        "0"
+    ],
+    "inner_wall_jerk": "9",
+    "inner_wall_line_width": "0.45",
+    "inner_wall_speed": [
+        "300"
+    ],
+    "interface_shells": "0",
+    "interlocking_beam": "0",
+    "interlocking_beam_layer_count": "2",
+    "interlocking_beam_width": "0.8",
+    "interlocking_boundary_avoidance": "2",
+    "interlocking_depth": "2",
+    "interlocking_orientation": "22.5",
+    "internal_bridge_support_thickness": "0.8",
+    "internal_solid_infill_line_width": "0.42",
+    "internal_solid_infill_pattern": "zig-zag",
+    "internal_solid_infill_speed": [
+        "250"
+    ],
+    "ironing_direction": "45",
+    "ironing_flow": "10%",
+    "ironing_inset": "0.21",
+    "ironing_pattern": "zig-zag",
+    "ironing_spacing": "0.15",
+    "ironing_speed": "30",
+    "ironing_type": "no ironing",
+    "is_infill_first": "0",
+    "layer_change_gcode": "; layer num/total_layer_count: {layer_num+1}/[total_layer_count]\n; update layer progress\nM73 L{layer_num+1}\nM991 S0 P{layer_num} ;notify layer change",
+    "layer_height": "0.08",
+    "line_width": "0.42",
+    "locked_skeleton_infill_pattern": "zigzag",
+    "locked_skin_infill_pattern": "crosszag",
+    "long_retractions_when_cut": [
+        "0"
+    ],
+    "long_retractions_when_ec": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "machine_end_gcode": ";===== date: 20231229 =====================\n;turn off nozzle clog detect\nG392 S0\n\nM400 ; wait for buffer to clear\nG92 E0 ; zero the extruder\nG1 E-0.8 F1800 ; retract\nG1 Z{max_layer_z + 0.5} F900 ; lower z a little\nG1 X0 Y{first_layer_center_no_wipe_tower[1]} F18000 ; move to safe pos\nG1 X-13.0 F3000 ; move to safe pos\n{if !spiral_mode && print_sequence != \"by object\"}\nM1002 judge_flag timelapse_record_flag\nM622 J1\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM991 S0 P-1 ;end timelapse at safe pos\nM623\n{endif}\n\nM140 S0 ; turn off bed\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off remote part cooling fan\nM106 P3 S0 ; turn off chamber cooling fan\n\n;G1 X27 F15000 ; wipe\n\n; pull back filament to AMS\nM620 S255\nG1 X181 F12000\nT255\nG1 X0 F18000\nG1 X-13.0 F3000\nG1 X0 F18000 ; wipe\nM621 S255\n\nM104 S0 ; turn off hotend\n\nM400 ; wait all motion done\nM17 S\nM17 Z0.4 ; lower z motor current to reduce impact if there is something in the bottom\n{if (max_layer_z + 100.0) < 180}\n    G1 Z{max_layer_z + 100.0} F600\n    G1 Z{max_layer_z +98.0}\n{else}\n    G1 Z180 F600\n    G1 Z180\n{endif}\nM400 P100\nM17 R ; restore z current\n\nG90\nG1 X-13 Y180 F3600\n\nG91\nG1 Z-1 F600\nG90\nM83\n\nM220 S100  ; Reset feedrate magnitude\nM201.2 K1.0 ; Reset acc magnitude\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 0\n\n;=====printer finish  sound=========\nM17\nM400 S1\nM1006 S1\nM1006 A0 B20 L100 C37 D20 M100 E42 F20 N100\nM1006 A0 B10 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B10 L100 C46 D10 M100 E46 F10 N100\nM1006 A44 B20 L100 C39 D20 M100 E48 F20 N100\nM1006 A0 B10 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B10 L100 C39 D10 M100 E39 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B10 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B10 L100 C39 D10 M100 E39 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A44 B10 L100 C0 D10 M100 E48 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A44 B20 L100 C41 D20 M100 E49 F20 N100\nM1006 A0 B20 L100 C0 D20 M100 E0 F20 N100\nM1006 A0 B20 L100 C37 D20 M100 E37 F20 N100\nM1006 W\n;=====printer finish  sound=========\nM400 S1\nM18 X Y Z\n",
+    "machine_hotend_change_time": "0",
+    "machine_load_filament_time": "28",
+    "machine_max_acceleration_e": [
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_extruding": [
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_retracting": [
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_travel": [
+        "9000",
+        "9000"
+    ],
+    "machine_max_acceleration_x": [
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_y": [
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_z": [
+        "1500",
+        "1500"
+    ],
+    "machine_max_jerk_e": [
+        "3",
+        "3"
+    ],
+    "machine_max_jerk_x": [
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_y": [
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_z": [
+        "5",
+        "5"
+    ],
+    "machine_max_speed_e": [
+        "30",
+        "30"
+    ],
+    "machine_max_speed_x": [
+        "500",
+        "200"
+    ],
+    "machine_max_speed_y": [
+        "500",
+        "200"
+    ],
+    "machine_max_speed_z": [
+        "30",
+        "30"
+    ],
+    "machine_min_extruding_rate": [
+        "0",
+        "0"
+    ],
+    "machine_min_travel_rate": [
+        "0",
+        "0"
+    ],
+    "machine_pause_gcode": "M400 U1",
+    "machine_prepare_compensation_time": "260",
+    "machine_start_gcode": ";===== machine: A1 mini =========================\n;===== date: 20251031 ==================\n\n;===== start to heat heatbead&hotend==========\nM1002 gcode_claim_action : 2\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM104 S170\nM140 S[bed_temperature_initial_layer_single]\nG392 S0 ;turn off clog detect\nM9833.2\n;=====start printer sound ===================\nM17\nM400 S1\nM1006 S1\nM1006 A0 B0 L100 C37 D10 M100 E37 F10 N100\nM1006 A0 B0 L100 C41 D10 M100 E41 F10 N100\nM1006 A0 B0 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A43 B10 L100 C39 D10 M100 E46 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B0 L100 C39 D10 M100 E43 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B0 L100 C41 D10 M100 E41 F10 N100\nM1006 A0 B0 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B0 L100 C49 D10 M100 E49 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A44 B10 L100 C39 D10 M100 E48 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B0 L100 C39 D10 M100 E44 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A43 B10 L100 C39 D10 M100 E46 F10 N100\nM1006 W\nM18\n;=====avoid end stop =================\nG91\nG380 S2 Z30 F1200\nG380 S3 Z-20 F1200\nG1 Z5 F1200\nG90\n\n;===== reset machine status =================\nM204 S6000\n\nM630 S0 P0\nG91\nM17 Z0.3 ; lower the z-motor current\n\nG90\nM17 X0.7 Y0.9 Z0.5 ; reset motor current to default\nM960 S5 P1 ; turn on logo lamp\nG90\nM83\nM220 S100 ;Reset Feedrate\nM221 S100 ;Reset Flowrate\nM73.2   R1.0 ;Reset left time magnitude\n;====== cog noise reduction=================\nM982.2 S1 ; turn on cog noise reduction\n\n;===== prepare print temperature and material ==========\nM400\nM18\nM109 S100 H170\nM104 S170\nM400\nM17\nM400\nG28 X\n\nM211 X0 Y0 Z0 ;turn off soft endstop ; turn off soft endstop to prevent protential logic problem\n\nM975 S1 ; turn on\n\nG1 X0.0 F30000\nG1 X-13.5 F3000\n\nM620 M ;enable remap\nM620 S[initial_no_support_extruder]A   ; switch material if AMS exist\n    G392 S0 ;turn on clog detect\n    M1002 gcode_claim_action : 4\n    M400\n    M1002 set_filament_type:UNKNOWN\n    M109 S[nozzle_temperature_initial_layer]\n    M104 S250\n    M400\n    T[initial_no_support_extruder]\n    G1 X-13.5 F3000\n    M400\n    M620.1 E F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60} T{flush_temperatures[initial_no_support_extruder]}\n    M109 S250 ;set nozzle to common flush temp\n    M106 P1 S0\n    G92 E0\n    G1 E50 F200\n    M400\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M104 S{flush_temperatures[initial_no_support_extruder]}\n    G92 E0\n    G1 E50 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n    M400\n    M106 P1 S178\n    G92 E0\n    G1 E5 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n    M109 S{nozzle_temperature_initial_layer[initial_no_support_extruder]-20} ; drop nozzle temp, make filament shink a bit\n    M104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]-40}\n    G92 E0\n    G1 E-0.5 F300\n\n    G1 X0 F30000\n    G1 X-13.5 F3000\n    G1 X0 F30000 ;wipe and shake\n    G1 X-13.5 F3000\n    G1 X0 F12000 ;wipe and shake\n    G1 X0 F30000\n    G1 X-13.5 F3000\n    M109 S{nozzle_temperature_initial_layer[initial_no_support_extruder]-40}\n    G392 S0 ;turn off clog detect\nM621 S[initial_no_support_extruder]A\n\nM400\nM106 P1 S0\n;===== prepare print temperature and material end =====\n\n\n;===== mech mode fast check============================\nM1002 gcode_claim_action : 3\nG0 X25 Y175 F20000 ; find a soft place to home\n;M104 S0\nG28 Z P0 T300; home z with low precision,permit 300deg temperature\nG29.2 S0 ; turn off ABL\nM104 S170\n\n; build plate detect\nM1002 judge_flag build_plate_detect_flag\nM622 S1\n  G39.4\n  M400\nM623\n\nG1 Z5 F3000\nG1 X90 Y-1 F30000\nM400 P200\nM970.3 Q1 A7 K0 O2\nM974 Q1 S2 P0\n\nG1 X90 Y0 Z5 F30000\nM400 P200\nM970 Q0 A10 B50 C90 H15 K0 M20 O3\nM974 Q0 S2 P0\n\nM975 S1\nG1 F30000\nG1 X-1 Y10\nG28 X ; re-home XY\n\n;===== wipe nozzle ===============================\nM1002 gcode_claim_action : 14\nM975 S1\n\nM104 S170 ; set temp down to heatbed acceptable\nM106 S255 ; turn on fan (G28 has turn off fan)\nM211 S; push soft endstop status\nM211 X0 Y0 Z0 ;turn off Z axis endstop\n\nM83\nG1 E-1 F500\nG90\nM83\n\nM109 S170\nM104 S140\nG0 X90 Y-4 F30000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X91 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X92 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X93 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X94 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X95 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X96 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X97 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X98 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\n\nG1 Z5 F30000\n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\nG1 X25 Y175 F30000.1 ;Brush material\nG1 Z0.2 F30000.1\nG1 Y185\nG91\nG1 X-30 F30000\nG1 Y-2\nG1 X27\nG1 Y1.5\nG1 X-28\nG1 Y-2\nG1 X30\nG1 Y1.5\nG1 X-30\nG90\nM83\n\nG1 Z5 F3000\nG0 X50 Y175 F20000 ; find a soft place to home\nG28 Z P0 T300; home z with low precision, permit 300deg temperature\nG29.2 S0 ; turn off ABL\n\nG0 X85 Y185 F10000 ;move to exposed steel surface and stop the nozzle\nG0 Z-1.01 F10000\nG91\n\nG2 I1 J0 X2 Y0 F2000.1\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\n\nG90\nG1 Z5 F30000\nG1 X25 Y175 F30000.1 ;Brush material\nG1 Z0.2 F30000.1\nG1 Y185\nG91\nG1 X-30 F30000\nG1 Y-2\nG1 X27\nG1 Y1.5\nG1 X-28\nG1 Y-2\nG1 X30\nG1 Y1.5\nG1 X-30\nG90\nM83\n\nG1 Z5\nG0 X55 Y175 F20000 ; find a soft place to home\nG28 Z P0 T300; home z with low precision, permit 300deg temperature\nG29.2 S0 ; turn off ABL\n\nG1 Z10\nG1 X85 Y185\nG1 Z-1.01\nG1 X95\nG1 X90\n\nM211 R; pop softend status\n\nM106 S0 ; turn off fan , too noisy\n;===== wipe nozzle end ================================\n\n\n;===== wait heatbed  ====================\nM1002 gcode_claim_action:54\nM104 S0\nM190 S[bed_temperature_initial_layer_single];set bed temp\nM109 S140\n\nG1 Z5 F3000\nG29.2 S1\nG1 X10 Y10 F20000\n\n;===== bed leveling ==================================\n;M1002 set_flag g29_before_print_flag=1\nM1002 judge_flag g29_before_print_flag\nM622 J1\n    M1002 gcode_claim_action : 1\n    G29 A1 X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]}\n    M400\n    M500 ; save cali data\nM623\n;===== bed leveling end ================================\n\n;===== home after wipe mouth============================\nM1002 judge_flag g29_before_print_flag\nM622 J0\n\n    M1002 gcode_claim_action : 13\n    G28 T145\n\nM623\n\n;===== home after wipe mouth end =======================\n\nM975 S1 ; turn on vibration supression\n;===== nozzle load line ===============================\nM975 S1\nG90\nM83\nT1000\n\nG1 X-13.5 Y0 Z10 F10000\nG1 E1.2 F500\nM400\nM1002 set_filament_type:UNKNOWN\nM109 S{nozzle_temperature[initial_extruder]}\nM400\n\nM412 S1 ;    ===turn on  filament runout detection===\nM400 P10\n\nG392 S0 ;turn on clog detect\n\nM620.3 W1; === turn on filament tangle detection===\nM400 S2\n\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n;M1002 set_flag extrude_cali_flag=1\nM1002 judge_flag extrude_cali_flag\nM622 J1\n    M1002 gcode_claim_action : 8\n    \n    M400\n    M900 K0.0 L1000.0 M1.0\n    G90\n    M83\n    G0 X68 Y-4 F30000\n    G0 Z0.3 F18000 ;Move to start position\n    M400\n    G0 X88 E10  F{outer_wall_volumetric_speed/(24/20)    * 60}\n    G0 X93 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\n    G0 X98 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\n    G0 X103 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\n    G0 X108 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\n    G0 X113 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\n    G0 Y0 Z0 F20000\n    M400\n    \n    G1 X-13.5 Y0 Z10 F10000\n    M400\n    \n    G1 E10 F{outer_wall_volumetric_speed/2.4*60}\n    M983 F{outer_wall_volumetric_speed/2.4} A0.3 H[nozzle_diameter]; cali dynamic extrusion compensation\n    M106 P1 S178\n    M400 S7\n    G1 X0 F18000\n    G1 X-13.5 F3000\n    G1 X0 F18000 ;wipe and shake\n    G1 X-13.5 F3000\n    G1 X0 F12000 ;wipe and shake\n    G1 X-13.5 F3000\n    M400\n    M106 P1 S0\n\n    M1002 judge_last_extrude_cali_success\n    M622 J0\n        M983 F{outer_wall_volumetric_speed/2.4} A0.3 H[nozzle_diameter]; cali dynamic extrusion compensation\n        M106 P1 S178\n        M400 S7\n        G1 X0 F18000\n        G1 X-13.5 F3000\n        G1 X0 F18000 ;wipe and shake\n        G1 X-13.5 F3000\n        G1 X0 F12000 ;wipe and shake\n        M400\n        M106 P1 S0\n    M623\n    \n    G1 X-13.5 F3000\n    M400\n    M984 A0.1 E1 S1 F{outer_wall_volumetric_speed/2.4} H[nozzle_diameter]\n    M106 P1 S178\n    M400 S7\n    G1 X0 F18000\n    G1 X-13.5 F3000\n    G1 X0 F18000 ;wipe and shake\n    G1 X-13.5 F3000\n    G1 X0 F12000 ;wipe and shake\n    G1 X-13.5 F3000\n    M400\n    M106 P1 S0\n\nM623 ; end of \"draw extrinsic para cali paint\"\n\n;===== extrude cali test ===============================\nM104 S{nozzle_temperature_initial_layer[initial_extruder]}\nG90\nM83\nG0 X68 Y-2.5 F30000\nG0 Z0.3 F18000 ;Move to start position\nG0 X88 E10  F{outer_wall_volumetric_speed/(24/20)    * 60}\nG0 X93 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\nG0 X98 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\nG0 X103 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\nG0 X108 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\nG0 X113 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\nG0 X115 Z0 F20000\nG0 Z5\nM400\n\n;========turn off light and wait extrude temperature =============\nM1002 gcode_claim_action : 0\n\nM400 ; wait all motion done before implement the emprical L parameters\n\n;===== for Textured PEI Plate , lower the nozzle as the nozzle was touching topmost of the texture when homing ==\n;curr_bed_type={curr_bed_type}\n{if curr_bed_type==\"Textured PEI Plate\"}\nG29.1 Z{-0.02} ; for Textured PEI Plate\n{endif}\n\nM960 S1 P0 ; turn off laser\nM960 S2 P0 ; turn off laser\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off big fan\nM106 P3 S0 ; turn off chamber fan\n\nM975 S1 ; turn on mech mode supression\nG90\nM83\nT1000\n\nM211 X0 Y0 Z0 ;turn off soft endstop\nM1007 S1\n\n\n\n",
+    "machine_switch_extruder_time": "0",
+    "machine_unload_filament_time": "34",
+    "master_extruder_id": "1",
+    "max_bridge_length": "0",
+    "max_layer_height": [
+        "0.28"
+    ],
+    "max_travel_detour_distance": "0",
+    "min_bead_width": "85%",
+    "min_feature_size": "25%",
+    "min_layer_height": [
+        "0.08"
+    ],
+    "minimum_sparse_infill_area": "15",
+    "mmu_segmented_region_interlocking_depth": "0",
+    "mmu_segmented_region_max_width": "0",
+    "name": "project_settings",
+    "no_slow_down_for_cooling_on_outwalls": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "nozzle_diameter": [
+        "0.4"
+    ],
+    "nozzle_flush_dataset": [
+        "0"
+    ],
+    "nozzle_height": "4.76",
+    "nozzle_temperature": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_initial_layer": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_range_high": [
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240"
+    ],
+    "nozzle_temperature_range_low": [
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190"
+    ],
+    "nozzle_type": [
+        "stainless_steel"
+    ],
+    "nozzle_volume": [
+        "92"
+    ],
+    "nozzle_volume_type": [
+        "Standard"
+    ],
+    "only_one_wall_first_layer": "1",
+    "ooze_prevention": "0",
+    "other_layers_print_sequence": [
+        "0"
+    ],
+    "other_layers_print_sequence_nums": "0",
+    "outer_wall_acceleration": [
+        "5000"
+    ],
+    "outer_wall_jerk": "9",
+    "outer_wall_line_width": "0.42",
+    "outer_wall_speed": [
+        "200"
+    ],
+    "overhang_1_4_speed": [
+        "0"
+    ],
+    "overhang_2_4_speed": [
+        "50"
+    ],
+    "overhang_3_4_speed": [
+        "30"
+    ],
+    "overhang_4_4_speed": [
+        "10"
+    ],
+    "overhang_fan_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "overhang_fan_threshold": [
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "overhang_threshold_participating_cooling": [
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%"
+    ],
+    "overhang_totally_speed": [
+        "10"
+    ],
+    "override_filament_scarf_seam_setting": "0",
+    "override_process_overhang_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "physical_extruder_map": [
+        "0"
+    ],
+    "post_process": [],
+    "pre_start_fan_time": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "precise_outer_wall": "0",
+    "precise_z_height": "0",
+    "pressure_advance": [
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02"
+    ],
+    "prime_tower_brim_width": "3",
+    "prime_tower_enable_framework": "0",
+    "prime_tower_extra_rib_length": "0",
+    "prime_tower_fillet_wall": "1",
+    "prime_tower_flat_ironing": "0",
+    "prime_tower_infill_gap": "150%",
+    "prime_tower_lift_height": "-1",
+    "prime_tower_lift_speed": "90",
+    "prime_tower_max_speed": "90",
+    "prime_tower_rib_wall": "0",
+    "prime_tower_rib_width": "8",
+    "prime_tower_skip_points": "1",
+    "prime_tower_width": "170",
+    "prime_volume_mode": "Default",
+    "print_compatible_printers": [
+        "Bambu Lab A1 0.4 nozzle"
+    ],
+    "print_extruder_id": [
+        "1"
+    ],
+    "print_extruder_variant": [
+        "Direct Drive Standard"
+    ],
+    "print_flow_ratio": "1",
+    "print_sequence": "by layer",
+    "print_settings_id": "Bambu_Lumina",
+    "printable_area": [
+        "0x0",
+        "256x0",
+        "256x256",
+        "0x256"
+    ],
+    "printable_height": "256",
+    "printer_extruder_id": [
+        "1"
+    ],
+    "printer_extruder_variant": [
+        "Direct Drive Standard"
+    ],
+    "printer_model": "Bambu Lab A1",
+    "printer_notes": "",
+    "printer_settings_id": "Bambu Lab A1 0.4 nozzle",
+    "printer_structure": "i3",
+    "printer_technology": "FFF",
+    "printer_variant": "0.4",
+    "printhost_authorization_type": "key",
+    "printhost_ssl_ignore_revoke": "0",
+    "printing_by_object_gcode": "",
+    "process_notes": "",
+    "raft_contact_distance": "0.1",
+    "raft_expansion": "1.5",
+    "raft_first_layer_density": "90%",
+    "raft_first_layer_expansion": "-1",
+    "raft_layers": "0",
+    "reduce_crossing_wall": "0",
+    "reduce_fan_stop_start_freq": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "reduce_infill_retraction": "1",
+    "required_nozzle_HRC": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "resolution": "0.012",
+    "retract_before_wipe": [
+        "0%"
+    ],
+    "retract_length_toolchange": [
+        "2"
+    ],
+    "retract_lift_above": [
+        "0"
+    ],
+    "retract_lift_below": [
+        "255"
+    ],
+    "retract_restart_extra": [
+        "0"
+    ],
+    "retract_restart_extra_toolchange": [
+        "0"
+    ],
+    "retract_when_changing_layer": [
+        "1"
+    ],
+    "retraction_distances_when_cut": [
+        "18"
+    ],
+    "retraction_distances_when_ec": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retraction_length": [
+        "0.8"
+    ],
+    "retraction_minimum_travel": [
+        "1"
+    ],
+    "retraction_speed": [
+        "30"
+    ],
+    "role_base_wipe_speed": "1",
+    "scan_first_layer": "0",
+    "scarf_angle_threshold": "155",
+    "seam_gap": "15%",
+    "seam_placement_away_from_overhangs": "0",
+    "seam_position": "aligned",
+    "seam_slope_conditional": "1",
+    "seam_slope_entire_loop": "0",
+    "seam_slope_gap": "0",
+    "seam_slope_inner_walls": "1",
+    "seam_slope_min_length": "10",
+    "seam_slope_start_height": "10%",
+    "seam_slope_steps": "10",
+    "seam_slope_type": "none",
+    "silent_mode": "0",
+    "single_extruder_multi_material": "1",
+    "skeleton_infill_density": "100%",
+    "skeleton_infill_line_width": "0.45",
+    "skin_infill_density": "100%",
+    "skin_infill_depth": "2",
+    "skin_infill_line_width": "0.45",
+    "skirt_distance": "2",
+    "skirt_height": "1",
+    "skirt_loops": "0",
+    "slice_closing_radius": "0.049",
+    "slicing_mode": "regular",
+    "slow_down_for_layer_cooling": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "slow_down_layer_time": [
+        "6",
+        "6",
+        "6",
+        "6",
+        "6",
+        "6",
+        "6",
+        "6"
+    ],
+    "slow_down_min_speed": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "slowdown_end_acc": [
+        "100000"
+    ],
+    "slowdown_end_height": [
+        "400"
+    ],
+    "slowdown_end_speed": [
+        "1000"
+    ],
+    "slowdown_start_acc": [
+        "100000"
+    ],
+    "slowdown_start_height": [
+        "0"
+    ],
+    "slowdown_start_speed": [
+        "1000"
+    ],
+    "small_perimeter_speed": [
+        "50%"
+    ],
+    "small_perimeter_threshold": [
+        "0"
+    ],
+    "smooth_coefficient": "80",
+    "smooth_speed_discontinuity_area": "1",
+    "solid_infill_filament": "0",
+    "sparse_infill_acceleration": [
+        "100%"
+    ],
+    "sparse_infill_anchor": "400%",
+    "sparse_infill_anchor_max": "20",
+    "sparse_infill_density": "100%",
+    "sparse_infill_filament": "0",
+    "sparse_infill_lattice_angle_1": "-45",
+    "sparse_infill_lattice_angle_2": "45",
+    "sparse_infill_line_width": "0.45",
+    "sparse_infill_pattern": "alignedrectilinear",
+    "sparse_infill_speed": [
+        "270"
+    ],
+    "spiral_mode": "0",
+    "spiral_mode_max_xy_smoothing": "200%",
+    "spiral_mode_smooth": "0",
+    "standby_temperature_delta": "-5",
+    "start_end_points": [
+        "30x-3",
+        "54x245"
+    ],
+    "supertack_plate_temp": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "supertack_plate_temp_initial_layer": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "support_air_filtration": "0",
+    "support_angle": "0",
+    "support_base_pattern": "default",
+    "support_base_pattern_spacing": "2.5",
+    "support_bottom_interface_spacing": "0.5",
+    "support_bottom_z_distance": "0.2",
+    "support_chamber_temp_control": "0",
+    "support_cooling_filter": "0",
+    "support_critical_regions_only": "0",
+    "support_expansion": "0",
+    "support_filament": "0",
+    "support_interface_bottom_layers": "2",
+    "support_interface_filament": "0",
+    "support_interface_loop_pattern": "0",
+    "support_interface_not_for_body": "1",
+    "support_interface_pattern": "auto",
+    "support_interface_spacing": "0.5",
+    "support_interface_speed": [
+        "80"
+    ],
+    "support_interface_top_layers": "2",
+    "support_ironing_direction": "0",
+    "support_ironing_flow": "10%",
+    "support_ironing_inset": "0",
+    "support_ironing_pattern": "zig-zag",
+    "support_ironing_spacing": "0.15",
+    "support_ironing_speed": "30",
+    "support_line_width": "0.42",
+    "support_object_first_layer_gap": "0.2",
+    "support_object_skip_flush": "0",
+    "support_object_xy_distance": "0.35",
+    "support_on_build_plate_only": "0",
+    "support_remove_small_overhang": "1",
+    "support_speed": [
+        "150"
+    ],
+    "support_style": "default",
+    "support_threshold_angle": "30",
+    "support_top_z_distance": "0.2",
+    "support_type": "tree(auto)",
+    "symmetric_infill_y_axis": "0",
+    "temperature_vitrification": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "template_custom_gcode": "",
+    "textured_plate_temp": [
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65"
+    ],
+    "textured_plate_temp_initial_layer": [
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65"
+    ],
+    "thick_bridges": "0",
+    "thumbnail_size": [
+        "50x50"
+    ],
+    "time_lapse_gcode": ";===================== date: 20250206 =====================\n{if !spiral_mode && print_sequence != \"by object\"}\n; don't support timelapse gcode in spiral_mode and by object sequence for I3 structure printer\n; SKIPPABLE_START\n; SKIPTYPE: timelapse\nM622.1 S1 ; for prev firmware, default turned on\nM1002 judge_flag timelapse_record_flag\nM622 J1\nG92 E0\nG1 Z{max_layer_z + 0.4}\nG1 X0 Y{first_layer_center_no_wipe_tower[1]} F18000 ; move to safe pos\nG1 X-13.0 F3000 ; move to safe pos\nM400\nM1004 S5 P1  ; external shutter\nM400 P300\nM971 S11 C11 O0\nG92 E0\nG1 X0 F18000\nM623\n\n; SKIPTYPE: head_wrap_detect\nM622.1 S1\nM1002 judge_flag g39_3rd_layer_detect_flag\nM622 J1\n    ; enable nozzle clog detect at 3rd layer\n    {if layer_num == 2}\n      M400\n      G90\n      M83\n      M204 S5000\n      G0 Z2 F4000\n      G0 X187 Y178 F20000\n      G39 S1 X187 Y178\n      G0 Z2 F4000\n    {endif}\n\n\n    M622.1 S1\n    M1002 judge_flag g39_detection_flag\n    M622 J1\n      {if !in_head_wrap_detect_zone}\n        M622.1 S0\n        M1002 judge_flag g39_mass_exceed_flag\n        M622 J1\n        {if layer_num > 2}\n            G392 S0\n            M400\n            G90\n            M83\n            M204 S5000\n            G0 Z{max_layer_z + 0.4} F4000\n            G39.3 S1\n            G0 Z{max_layer_z + 0.4} F4000\n            G392 S0\n          {endif}\n        M623\n    {endif}\n    M623\nM623\n; SKIPPABLE_END\n{endif}\n\n\n",
+    "timelapse_type": "0",
+    "top_area_threshold": "200%",
+    "top_color_penetration_layers": "5",
+    "top_one_wall_type": "all top",
+    "top_shell_layers": "0",
+    "top_shell_thickness": "1",
+    "top_solid_infill_flow_ratio": [
+        "1"
+    ],
+    "top_surface_acceleration": [
+        "2000"
+    ],
+    "top_surface_density": "100%",
+    "top_surface_jerk": "9",
+    "top_surface_line_width": "0.42",
+    "top_surface_pattern": "monotonicline",
+    "top_surface_speed": [
+        "200"
+    ],
+    "top_z_overrides_xy_distance": "0",
+    "travel_acceleration": [
+        "10000"
+    ],
+    "travel_jerk": "9",
+    "travel_short_distance_acceleration": [
+        "250"
+    ],
+    "travel_speed": [
+        "700"
+    ],
+    "travel_speed_z": [
+        "0"
+    ],
+    "tree_support_branch_angle": "45",
+    "tree_support_branch_diameter": "2",
+    "tree_support_branch_diameter_angle": "5",
+    "tree_support_branch_distance": "5",
+    "tree_support_wall_count": "-1",
+    "upward_compatible_machine": [
+        "Bambu Lab P1S 0.4 nozzle",
+        "Bambu Lab P1P 0.4 nozzle",
+        "Bambu Lab X1 0.4 nozzle",
+        "Bambu Lab X1 Carbon 0.4 nozzle",
+        "Bambu Lab X1E 0.4 nozzle",
+        "Bambu Lab A1 0.4 nozzle",
+        "Bambu Lab H2D 0.4 nozzle",
+        "Bambu Lab H2D Pro 0.4 nozzle",
+        "Bambu Lab H2S 0.4 nozzle",
+        "Bambu Lab P2S 0.4 nozzle",
+        "Bambu Lab H2C 0.4 nozzle"
+    ],
+    "use_firmware_retraction": "0",
+    "use_relative_e_distances": "1",
+    "version": "02.05.00.66",
+    "vertical_shell_speed": [
+        "80%"
+    ],
+    "volumetric_speed_coefficients": [
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0"
+    ],
+    "wall_distribution_count": "1",
+    "wall_filament": "0",
+    "wall_generator": "classic",
+    "wall_loops": "1",
+    "wall_sequence": "inner wall/outer wall",
+    "wall_transition_angle": "10",
+    "wall_transition_filter_deviation": "25%",
+    "wall_transition_length": "100%",
+    "wipe": [
+        "1"
+    ],
+    "wipe_distance": [
+        "2"
+    ],
+    "wipe_speed": "80%",
+    "wipe_tower_no_sparse_layers": "0",
+    "wipe_tower_rotation_angle": "0",
+    "wipe_tower_x": [
+        "5.70098"
+    ],
+    "wipe_tower_y": [
+        "149.411"
+    ],
+    "wrapping_detection_gcode": "",
+    "wrapping_detection_layers": "20",
+    "wrapping_exclude_area": [],
+    "xy_contour_compensation": "0",
+    "xy_hole_compensation": "0",
+    "z_direction_outwall_speed_continuous": "0",
+    "z_hop": [
+        "0.4"
+    ],
+    "z_hop_types": [
+        "Auto Lift"
+    ]
+}
\ No newline at end of file
diff --git a/printer_profiles/bambu_a1_mini.json b/printer_profiles/bambu_a1_mini.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_a1_mini.json
@@ -0,0 +1,2172 @@
+{
+    "accel_to_decel_enable": "0",
+    "accel_to_decel_factor": "50%",
+    "activate_air_filtration": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "additional_cooling_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "apply_scarf_seam_on_circles": "1",
+    "apply_top_surface_compensation": "0",
+    "auxiliary_fan": "0",
+    "avoid_crossing_wall_includes_support": "0",
+    "bed_custom_model": "",
+    "bed_custom_texture": "",
+    "bed_exclude_area": [],
+    "bed_temperature_formula": "by_first_filament",
+    "before_layer_change_gcode": "",
+    "best_object_pos": "0.7,0.5",
+    "bottom_color_penetration_layers": "3",
+    "bottom_shell_layers": "0",
+    "bottom_shell_thickness": "0",
+    "bottom_surface_density": "100%",
+    "bottom_surface_pattern": "monotonic",
+    "bridge_angle": "0",
+    "bridge_flow": "1",
+    "bridge_no_support": "0",
+    "bridge_speed": [
+        "50"
+    ],
+    "brim_object_gap": "0.1",
+    "brim_type": "auto_brim",
+    "brim_width": "5",
+    "chamber_temperatures": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "change_filament_gcode": ";===== A1mini 20251031 =====\nG392 S0\nM1007 S0\nM620 S[next_extruder]A\nM204 S9000\nG1 Z{max_layer_z + 3.0} F1200\n\nM400\nM106 P1 S0\nM106 P2 S0\n{if old_filament_temp > 142 && next_extruder < 255}\nM104 S[old_filament_temp]\n{endif}\n\nG1 X180 F18000\n\n{if long_retractions_when_cut[previous_extruder]}\nM620.11 S1 I[previous_extruder] E-{retraction_distances_when_cut[previous_extruder]} F1200\n{else}\nM620.11 S0\n{endif}\nM400\n\nM620.1 E F{flush_volumetric_speeds[previous_extruder]/2.4053*60} T{flush_temperatures[previous_extruder]}\nM620.10 A0 F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nT[next_extruder]\nM620.1 E F{flush_volumetric_speeds[next_extruder]/2.4053*60} T{flush_temperatures[next_extruder]}\nM620.10 A1 F{flush_volumetric_speeds[next_extruder]/2.4053*60} L[flush_length] H[nozzle_diameter] T{flush_temperatures[next_extruder]}\n\nG1 Y90 F9000\n\n{if next_extruder < 255}\n\n{if long_retractions_when_cut[previous_extruder]}\nM620.11 S1 I[previous_extruder] E{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nM628 S1\nG92 E0\nG1 E{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nM400\nM629 S1\n{else}\nM620.11 S0\n{endif}\n\nM400\nG92 E0\nM628 S0\n\n{if flush_length_1 > 1}\n; FLUSH_START\n; always use highest temperature to flush\nM400\nM1002 set_filament_type:UNKNOWN\nM109 S[flush_temperatures[next_extruder]]\nM106 P1 S60\n{if flush_length_1 > 23.7}\nG1 E23.7 F{flush_volumetric_speeds[previous_extruder]/2.4053*60} ; do not need pulsatile flushing for start part\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\n{else}\nG1 E{flush_length_1} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\n{endif}\n; FLUSH_END\nG1 E-[old_retract_length_toolchange] F1800\nG1 E[old_retract_length_toolchange] F300\nM400\nM1002 set_filament_type:{filament_type[next_extruder]}\n{endif}\n\n{if flush_length_1 > 45 && flush_length_2 > 1}\n; WIPE\nM400\nM106 P1 S178\nM400 S3\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nM400\nM106 P1 S0\n{endif}\n\n{if flush_length_2 > 1}\nM106 P1 S60\n; FLUSH_START\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\n; FLUSH_END\nG1 E-[new_retract_length_toolchange] F1800\nG1 E[new_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_2 > 45 && flush_length_3 > 1}\n; WIPE\nM400\nM106 P1 S178\nM400 S3\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nM400\nM106 P1 S0\n{endif}\n\n{if flush_length_3 > 1}\nM106 P1 S60\n; FLUSH_START\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\n; FLUSH_END\nG1 E-[new_retract_length_toolchange] F1800\nG1 E[new_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_3 > 45 && flush_length_4 > 1}\n; WIPE\nM400\nM106 P1 S178\nM400 S3\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nM400\nM106 P1 S0\n{endif}\n\n{if flush_length_4 > 1}\nM106 P1 S60\n; FLUSH_START\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\n; FLUSH_END\n{endif}\n\nM629\n\nM400\nM106 P1 S60\nM109 S[new_filament_temp]\nG1 E5 F{flush_volumetric_speeds[next_extruder]/2.4053*60} ;Compensate for filament spillage during waiting temperature\nM400\nG92 E0\nG1 E-[new_retract_length_toolchange] F1800\nM400\nM106 P1 S178\nM400 S3\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nG1 X-3.5 F18000\nG1 X-13.5 F3000\nM400\nG1 Z{max_layer_z + 3.0} F3000\nM106 P1 S0\n{if layer_z <= (initial_layer_print_height + 0.001)}\nM204 S[initial_layer_acceleration]\n{else}\nM204 S[default_acceleration]\n{endif}\n{else}\nG1 X[x_after_toolchange] Y[y_after_toolchange] Z[z_after_toolchange] F12000\n{endif}\n\nM622.1 S0\nM9833 F{outer_wall_volumetric_speed/2.4} A0.3 ; cali dynamic extrusion compensation\nM1002 judge_flag filament_need_cali_flag\nM622 J1\n  G92 E0\n  G1 E-[new_retract_length_toolchange] F1800\n  M400\n  \n  M106 P1 S178\n  M400 S7\n  G1 X0 F18000\n  G1 X-13.5 F3000\n  G1 X0 F18000 ;wipe and shake\n  G1 X-13.5 F3000\n  G1 X0 F12000 ;wipe and shake\n  G1 X-13.5 F3000\n  G1 X0 F12000 ;wipe and shake\n  M400\n  M106 P1 S0 \nM623\n\nM621 S[next_extruder]A\nG392 S0\n\nM1007 S1\n",
+    "circle_compensation_manual_offset": "0",
+    "circle_compensation_speed": [
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200"
+    ],
+    "close_fan_the_first_x_layers": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "complete_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "cool_plate_temp": [
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cool_plate_temp_initial_layer": [
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cooling_filter_enabled": "0",
+    "cooling_perimeter_transition_distance": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "cooling_slowdown_logic": [
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling"
+    ],
+    "counter_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "counter_coef_2": [
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008"
+    ],
+    "counter_coef_3": [
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041"
+    ],
+    "counter_limit_max": [
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033"
+    ],
+    "counter_limit_min": [
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035"
+    ],
+    "curr_bed_type": "Textured PEI Plate",
+    "default_acceleration": [
+        "6000"
+    ],
+    "default_filament_colour": [
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "default_filament_profile": [
+        "Bambu PLA Basic @BBL A1M"
+    ],
+    "default_jerk": "0",
+    "default_nozzle_volume_type": [
+        "Standard"
+    ],
+    "default_print_profile": "0.20mm Standard @BBL A1M",
+    "deretraction_speed": [
+        "30"
+    ],
+    "detect_floating_vertical_shell": "1",
+    "detect_narrow_internal_solid_infill": "0",
+    "detect_overhang_wall": "1",
+    "detect_thin_wall": "0",
+    "diameter_limit": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "different_settings_to_system": [
+        "bottom_shell_layers;detect_narrow_internal_solid_infill;initial_layer_flow_ratio;initial_layer_line_width;initial_layer_print_height;layer_height;only_one_wall_first_layer;prime_tower_rib_wall;prime_tower_width;skeleton_infill_density;skin_infill_density;sparse_infill_density;sparse_infill_pattern;top_shell_layers;wall_loops",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "draft_shield": "disabled",
+    "during_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "elefant_foot_compensation": "0",
+    "embedding_wall_into_infill": "0",
+    "enable_arc_fitting": "1",
+    "enable_circle_compensation": "0",
+    "enable_height_slowdown": [
+        "0"
+    ],
+    "enable_long_retraction_when_cut": "2",
+    "enable_overhang_bridge_fan": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_overhang_speed": [
+        "1"
+    ],
+    "enable_pre_heating": "0",
+    "enable_pressure_advance": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_prime_tower": "1",
+    "enable_support": "0",
+    "enable_support_ironing": "0",
+    "enable_tower_interface_features": "0",
+    "enable_wrapping_detection": "0",
+    "enforce_support_layers": "0",
+    "eng_plate_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "eng_plate_temp_initial_layer": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "ensure_vertical_shell_thickness": "enabled",
+    "exclude_object": "1",
+    "extruder_ams_count": [
+        "1#0|4#0",
+        "1#0|4#0"
+    ],
+    "extruder_clearance_dist_to_rod": "56.5",
+    "extruder_clearance_height_to_lid": "180",
+    "extruder_clearance_height_to_rod": "25",
+    "extruder_clearance_max_radius": "73",
+    "extruder_colour": [
+        "#018001"
+    ],
+    "extruder_max_nozzle_count": [
+        "1"
+    ],
+    "extruder_nozzle_stats": [
+        "Standard#1"
+    ],
+    "extruder_offset": [
+        "0x0"
+    ],
+    "extruder_printable_area": [],
+    "extruder_printable_height": [],
+    "extruder_type": [
+        "Direct Drive"
+    ],
+    "extruder_variant_list": [
+        "Direct Drive Standard"
+    ],
+    "fan_cooling_layer_time": [
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "fan_direction": "undefine",
+    "fan_max_speed": [
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "fan_min_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_adaptive_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_adhesiveness_category": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_bridge_speed": [
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25"
+    ],
+    "filament_change_length": [
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5"
+    ],
+    "filament_change_length_nc": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_colour": [
+        "#FFFFFF",
+        "#0080FF",
+        "#FF00FF",
+        "#FFFF00",
+        "#000000",
+        "#FF0000",
+        "#0000FF",
+        "#00FF00"
+    ],
+    "filament_colour_type": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_cooling_before_tower": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_cost": [
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99"
+    ],
+    "filament_density": [
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26"
+    ],
+    "filament_deretraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_dev_ams_drying_ams_limitations": [
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0"
+    ],
+    "filament_dev_ams_drying_heat_distortion_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_chamber_drying_bed_temperature": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "filament_dev_chamber_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_drying_cooling_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_drying_softening_temperature": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_diameter": [
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75"
+    ],
+    "filament_enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_end_gcode": [
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n"
+    ],
+    "filament_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard",
+        "Direct Drive Standard"
+    ],
+    "filament_flow_ratio": [
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98"
+    ],
+    "filament_flush_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_flush_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ids": [
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00"
+    ],
+    "filament_is_support": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_long_retractions_when_cut": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map_mode": "Auto For Flush",
+    "filament_max_volumetric_speed": [
+        "21",
+        "21",
+        "21",
+        "21",
+        "21",
+        "21",
+        "21",
+        "21"
+    ],
+    "filament_minimal_purge_on_wipe_tower": [
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15"
+    ],
+    "filament_multi_colour": [
+        "#FFFFFF",
+        "#0080FF",
+        "#FF00FF",
+        "#FFFF00",
+        "#000000",
+        "#FF0000",
+        "#0000FF",
+        "#00FF00"
+    ],
+    "filament_notes": "",
+    "filament_nozzle_map": [
+        "1",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_1_4_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_2_4_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_overhang_3_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_pre_cooling_temperature": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_pre_cooling_temperature_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_prime_volume": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_prime_volume_nc": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_printable": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "filament_ramming_travel_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_travel_time_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_volumetric_speed": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_ramming_volumetric_speed_nc": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_retract_before_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_length_nc": [
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14"
+    ],
+    "filament_retract_restart_extra": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_when_changing_layer": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_distances_when_cut": [
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18"
+    ],
+    "filament_retraction_length": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_minimum_travel": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_scarf_gap": [
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "filament_scarf_height": [
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%"
+    ],
+    "filament_scarf_length": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_scarf_seam_type": [
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none"
+    ],
+    "filament_self_index": [
+        "1",
+        "2",
+        "3",
+        "4",
+        "5",
+        "6",
+        "7",
+        "8"
+    ],
+    "filament_settings_id": [
+        "Bambu PLA Basic @BBL A1M",
+        "Bambu PLA Basic @BBL A1M",
+        "Bambu PLA Basic @BBL A1M",
+        "Bambu PLA Basic @BBL A1M",
+        "Bambu PLA Basic @BBL A1M",
+        "Bambu PLA Basic @BBL A1M",
+        "Bambu PLA Basic @BBL A1M",
+        "Bambu PLA Basic @BBL A1M"
+    ],
+    "filament_shrink": [
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "filament_soluble": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_start_gcode": [
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\n\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}"
+    ],
+    "filament_tower_interface_pre_extrusion_dist": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_tower_interface_pre_extrusion_length": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_tower_interface_print_temp": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_tower_interface_purge_volume": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "filament_tower_ironing_area": [
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_type": [
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA"
+    ],
+    "filament_velocity_adaptation_factor": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_vendor": [
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab"
+    ],
+    "filament_volume_map": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_wipe_distance": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop_types": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filename_format": "{input_filename_base}_{filament_type[0]}_{print_time}.gcode",
+    "fill_multiline": "1",
+    "filter_out_gap_fill": "0",
+    "first_layer_print_sequence": [
+        "0"
+    ],
+    "first_x_layer_fan_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "flush_into_infill": "0",
+    "flush_into_objects": "0",
+    "flush_into_support": "1",
+    "flush_multiplier": [
+        "1"
+    ],
+    "flush_volumes_matrix": [
+        "0",
+        "305",
+        "304",
+        "282",
+        "128",
+        "310",
+        "320",
+        "296",
+        "589",
+        "0",
+        "329",
+        "579",
+        "144",
+        "282",
+        "180",
+        "438",
+        "588",
+        "278",
+        "0",
+        "577",
+        "144",
+        "282",
+        "290",
+        "436",
+        "355",
+        "299",
+        "299",
+        "0",
+        "168",
+        "304",
+        "314",
+        "290",
+        "608",
+        "506",
+        "508",
+        "498",
+        "0",
+        "456",
+        "355",
+        "588",
+        "634",
+        "397",
+        "355",
+        "588",
+        "138",
+        "0",
+        "285",
+        "491",
+        "709",
+        "364",
+        "456",
+        "701",
+        "128",
+        "441",
+        "0",
+        "577",
+        "508",
+        "285",
+        "285",
+        "456",
+        "155",
+        "290",
+        "299",
+        "0"
+    ],
+    "flush_volumes_vector": [
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140"
+    ],
+    "from": "project",
+    "full_fan_speed_layer": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "fuzzy_skin": "none",
+    "fuzzy_skin_point_distance": "0.8",
+    "fuzzy_skin_thickness": "0.3",
+    "gap_infill_speed": [
+        "250"
+    ],
+    "gcode_add_line_number": "0",
+    "gcode_flavor": "marlin",
+    "grab_length": [
+        "17.4"
+    ],
+    "group_algo_with_time": "0",
+    "has_scarf_joint_seam": "0",
+    "head_wrap_detect_zone": [
+        "156x152",
+        "180x152",
+        "180x180",
+        "156x180"
+    ],
+    "hole_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "hole_coef_2": [
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008"
+    ],
+    "hole_coef_3": [
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415"
+    ],
+    "hole_limit_max": [
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22"
+    ],
+    "hole_limit_min": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "host_type": "octoprint",
+    "hot_plate_temp": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "hot_plate_temp_initial_layer": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "hotend_cooling_rate": [
+        "2"
+    ],
+    "hotend_heating_rate": [
+        "2"
+    ],
+    "impact_strength_z": [
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8"
+    ],
+    "independent_support_layer_height": "1",
+    "infill_combination": "0",
+    "infill_direction": "45",
+    "infill_instead_top_bottom_surfaces": "0",
+    "infill_jerk": "9",
+    "infill_lock_depth": "1",
+    "infill_rotate_step": "0",
+    "infill_shift_step": "0.4",
+    "infill_wall_overlap": "15%",
+    "initial_layer_acceleration": [
+        "500"
+    ],
+    "initial_layer_flow_ratio": "1.05",
+    "initial_layer_infill_speed": [
+        "105"
+    ],
+    "initial_layer_jerk": "9",
+    "initial_layer_line_width": "0.42",
+    "initial_layer_print_height": "0.08",
+    "initial_layer_speed": [
+        "50"
+    ],
+    "initial_layer_travel_acceleration": [
+        "6000"
+    ],
+    "inner_wall_acceleration": [
+        "0"
+    ],
+    "inner_wall_jerk": "9",
+    "inner_wall_line_width": "0.45",
+    "inner_wall_speed": [
+        "300"
+    ],
+    "interface_shells": "0",
+    "interlocking_beam": "0",
+    "interlocking_beam_layer_count": "2",
+    "interlocking_beam_width": "0.8",
+    "interlocking_boundary_avoidance": "2",
+    "interlocking_depth": "2",
+    "interlocking_orientation": "22.5",
+    "internal_bridge_support_thickness": "0.8",
+    "internal_solid_infill_line_width": "0.42",
+    "internal_solid_infill_pattern": "zig-zag",
+    "internal_solid_infill_speed": [
+        "250"
+    ],
+    "ironing_direction": "45",
+    "ironing_flow": "10%",
+    "ironing_inset": "0.21",
+    "ironing_pattern": "zig-zag",
+    "ironing_spacing": "0.15",
+    "ironing_speed": "30",
+    "ironing_type": "no ironing",
+    "is_infill_first": "0",
+    "layer_change_gcode": "; layer num/total_layer_count: {layer_num+1}/[total_layer_count]\n; update layer progress\nM73 L{layer_num+1}\nM991 S0 P{layer_num} ;notify layer change",
+    "layer_height": "0.08",
+    "line_width": "0.42",
+    "locked_skeleton_infill_pattern": "zigzag",
+    "locked_skin_infill_pattern": "crosszag",
+    "long_retractions_when_cut": [
+        "0"
+    ],
+    "long_retractions_when_ec": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "machine_end_gcode": ";===== date: 20231229 =====================\n;turn off nozzle clog detect\nG392 S0\n\nM400 ; wait for buffer to clear\nG92 E0 ; zero the extruder\nG1 E-0.8 F1800 ; retract\nG1 Z{max_layer_z + 0.5} F900 ; lower z a little\nG1 X0 Y{first_layer_center_no_wipe_tower[1]} F18000 ; move to safe pos\nG1 X-13.0 F3000 ; move to safe pos\n{if !spiral_mode && print_sequence != \"by object\"}\nM1002 judge_flag timelapse_record_flag\nM622 J1\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM400 P100\nM971 S11 C11 O0\nM991 S0 P-1 ;end timelapse at safe pos\nM623\n{endif}\n\nM140 S0 ; turn off bed\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off remote part cooling fan\nM106 P3 S0 ; turn off chamber cooling fan\n\n;G1 X27 F15000 ; wipe\n\n; pull back filament to AMS\nM620 S255\nG1 X181 F12000\nT255\nG1 X0 F18000\nG1 X-13.0 F3000\nG1 X0 F18000 ; wipe\nM621 S255\n\nM104 S0 ; turn off hotend\n\nM400 ; wait all motion done\nM17 S\nM17 Z0.4 ; lower z motor current to reduce impact if there is something in the bottom\n{if (max_layer_z + 100.0) < 180}\n    G1 Z{max_layer_z + 100.0} F600\n    G1 Z{max_layer_z +98.0}\n{else}\n    G1 Z180 F600\n    G1 Z180\n{endif}\nM400 P100\nM17 R ; restore z current\n\nG90\nG1 X-13 Y180 F3600\n\nG91\nG1 Z-1 F600\nG90\nM83\n\nM220 S100  ; Reset feedrate magnitude\nM201.2 K1.0 ; Reset acc magnitude\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 0\n\n;=====printer finish  sound=========\nM17\nM400 S1\nM1006 S1\nM1006 A0 B20 L100 C37 D20 M100 E42 F20 N100\nM1006 A0 B10 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B10 L100 C46 D10 M100 E46 F10 N100\nM1006 A44 B20 L100 C39 D20 M100 E48 F20 N100\nM1006 A0 B10 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B10 L100 C39 D10 M100 E39 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B10 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B10 L100 C39 D10 M100 E39 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A44 B10 L100 C0 D10 M100 E48 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A44 B20 L100 C41 D20 M100 E49 F20 N100\nM1006 A0 B20 L100 C0 D20 M100 E0 F20 N100\nM1006 A0 B20 L100 C37 D20 M100 E37 F20 N100\nM1006 W\n;=====printer finish  sound=========\nM400 S1\nM18 X Y Z\n",
+    "machine_hotend_change_time": "0",
+    "machine_load_filament_time": "28",
+    "machine_max_acceleration_e": [
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_extruding": [
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_retracting": [
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_travel": [
+        "9000",
+        "9000"
+    ],
+    "machine_max_acceleration_x": [
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_y": [
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_z": [
+        "1500",
+        "1500"
+    ],
+    "machine_max_jerk_e": [
+        "3",
+        "3"
+    ],
+    "machine_max_jerk_x": [
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_y": [
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_z": [
+        "5",
+        "5"
+    ],
+    "machine_max_speed_e": [
+        "30",
+        "30"
+    ],
+    "machine_max_speed_x": [
+        "500",
+        "200"
+    ],
+    "machine_max_speed_y": [
+        "500",
+        "200"
+    ],
+    "machine_max_speed_z": [
+        "30",
+        "30"
+    ],
+    "machine_min_extruding_rate": [
+        "0",
+        "0"
+    ],
+    "machine_min_travel_rate": [
+        "0",
+        "0"
+    ],
+    "machine_pause_gcode": "M400 U1",
+    "machine_prepare_compensation_time": "260",
+    "machine_start_gcode": ";===== machine: A1 mini =========================\n;===== date: 20251031 ==================\n\n;===== start to heat heatbead&hotend==========\nM1002 gcode_claim_action : 2\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM104 S170\nM140 S[bed_temperature_initial_layer_single]\nG392 S0 ;turn off clog detect\nM9833.2\n;=====start printer sound ===================\nM17\nM400 S1\nM1006 S1\nM1006 A0 B0 L100 C37 D10 M100 E37 F10 N100\nM1006 A0 B0 L100 C41 D10 M100 E41 F10 N100\nM1006 A0 B0 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B10 L100 C0 D10 M100 E0 F10 N100\nM1006 A43 B10 L100 C39 D10 M100 E46 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B0 L100 C39 D10 M100 E43 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B0 L100 C41 D10 M100 E41 F10 N100\nM1006 A0 B0 L100 C44 D10 M100 E44 F10 N100\nM1006 A0 B0 L100 C49 D10 M100 E49 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A44 B10 L100 C39 D10 M100 E48 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A0 B0 L100 C39 D10 M100 E44 F10 N100\nM1006 A0 B0 L100 C0 D10 M100 E0 F10 N100\nM1006 A43 B10 L100 C39 D10 M100 E46 F10 N100\nM1006 W\nM18\n;=====avoid end stop =================\nG91\nG380 S2 Z30 F1200\nG380 S3 Z-20 F1200\nG1 Z5 F1200\nG90\n\n;===== reset machine status =================\nM204 S6000\n\nM630 S0 P0\nG91\nM17 Z0.3 ; lower the z-motor current\n\nG90\nM17 X0.7 Y0.9 Z0.5 ; reset motor current to default\nM960 S5 P1 ; turn on logo lamp\nG90\nM83\nM220 S100 ;Reset Feedrate\nM221 S100 ;Reset Flowrate\nM73.2   R1.0 ;Reset left time magnitude\n;====== cog noise reduction=================\nM982.2 S1 ; turn on cog noise reduction\n\n;===== prepare print temperature and material ==========\nM400\nM18\nM109 S100 H170\nM104 S170\nM400\nM17\nM400\nG28 X\n\nM211 X0 Y0 Z0 ;turn off soft endstop ; turn off soft endstop to prevent protential logic problem\n\nM975 S1 ; turn on\n\nG1 X0.0 F30000\nG1 X-13.5 F3000\n\nM620 M ;enable remap\nM620 S[initial_no_support_extruder]A   ; switch material if AMS exist\n    G392 S0 ;turn on clog detect\n    M1002 gcode_claim_action : 4\n    M400\n    M1002 set_filament_type:UNKNOWN\n    M109 S[nozzle_temperature_initial_layer]\n    M104 S250\n    M400\n    T[initial_no_support_extruder]\n    G1 X-13.5 F3000\n    M400\n    M620.1 E F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60} T{flush_temperatures[initial_no_support_extruder]}\n    M109 S250 ;set nozzle to common flush temp\n    M106 P1 S0\n    G92 E0\n    G1 E50 F200\n    M400\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M104 S{flush_temperatures[initial_no_support_extruder]}\n    G92 E0\n    G1 E50 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n    M400\n    M106 P1 S178\n    G92 E0\n    G1 E5 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n    M109 S{nozzle_temperature_initial_layer[initial_no_support_extruder]-20} ; drop nozzle temp, make filament shink a bit\n    M104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]-40}\n    G92 E0\n    G1 E-0.5 F300\n\n    G1 X0 F30000\n    G1 X-13.5 F3000\n    G1 X0 F30000 ;wipe and shake\n    G1 X-13.5 F3000\n    G1 X0 F12000 ;wipe and shake\n    G1 X0 F30000\n    G1 X-13.5 F3000\n    M109 S{nozzle_temperature_initial_layer[initial_no_support_extruder]-40}\n    G392 S0 ;turn off clog detect\nM621 S[initial_no_support_extruder]A\n\nM400\nM106 P1 S0\n;===== prepare print temperature and material end =====\n\n\n;===== mech mode fast check============================\nM1002 gcode_claim_action : 3\nG0 X25 Y175 F20000 ; find a soft place to home\n;M104 S0\nG28 Z P0 T300; home z with low precision,permit 300deg temperature\nG29.2 S0 ; turn off ABL\nM104 S170\n\n; build plate detect\nM1002 judge_flag build_plate_detect_flag\nM622 S1\n  G39.4\n  M400\nM623\n\nG1 Z5 F3000\nG1 X90 Y-1 F30000\nM400 P200\nM970.3 Q1 A7 K0 O2\nM974 Q1 S2 P0\n\nG1 X90 Y0 Z5 F30000\nM400 P200\nM970 Q0 A10 B50 C90 H15 K0 M20 O3\nM974 Q0 S2 P0\n\nM975 S1\nG1 F30000\nG1 X-1 Y10\nG28 X ; re-home XY\n\n;===== wipe nozzle ===============================\nM1002 gcode_claim_action : 14\nM975 S1\n\nM104 S170 ; set temp down to heatbed acceptable\nM106 S255 ; turn on fan (G28 has turn off fan)\nM211 S; push soft endstop status\nM211 X0 Y0 Z0 ;turn off Z axis endstop\n\nM83\nG1 E-1 F500\nG90\nM83\n\nM109 S170\nM104 S140\nG0 X90 Y-4 F30000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X91 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X92 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X93 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X94 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X95 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X96 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X97 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X98 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\nG1 Z2 F1200\nG1 X99 F10000\nG380 S3 Z-5 F1200\n\nG1 Z5 F30000\n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\nG1 X25 Y175 F30000.1 ;Brush material\nG1 Z0.2 F30000.1\nG1 Y185\nG91\nG1 X-30 F30000\nG1 Y-2\nG1 X27\nG1 Y1.5\nG1 X-28\nG1 Y-2\nG1 X30\nG1 Y1.5\nG1 X-30\nG90\nM83\n\nG1 Z5 F3000\nG0 X50 Y175 F20000 ; find a soft place to home\nG28 Z P0 T300; home z with low precision, permit 300deg temperature\nG29.2 S0 ; turn off ABL\n\nG0 X85 Y185 F10000 ;move to exposed steel surface and stop the nozzle\nG0 Z-1.01 F10000\nG91\n\nG2 I1 J0 X2 Y0 F2000.1\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\nG2 I1 J0 X2\nG2 I-0.75 J0 X-1.5\n\nG90\nG1 Z5 F30000\nG1 X25 Y175 F30000.1 ;Brush material\nG1 Z0.2 F30000.1\nG1 Y185\nG91\nG1 X-30 F30000\nG1 Y-2\nG1 X27\nG1 Y1.5\nG1 X-28\nG1 Y-2\nG1 X30\nG1 Y1.5\nG1 X-30\nG90\nM83\n\nG1 Z5\nG0 X55 Y175 F20000 ; find a soft place to home\nG28 Z P0 T300; home z with low precision, permit 300deg temperature\nG29.2 S0 ; turn off ABL\n\nG1 Z10\nG1 X85 Y185\nG1 Z-1.01\nG1 X95\nG1 X90\n\nM211 R; pop softend status\n\nM106 S0 ; turn off fan , too noisy\n;===== wipe nozzle end ================================\n\n\n;===== wait heatbed  ====================\nM1002 gcode_claim_action:54\nM104 S0\nM190 S[bed_temperature_initial_layer_single];set bed temp\nM109 S140\n\nG1 Z5 F3000\nG29.2 S1\nG1 X10 Y10 F20000\n\n;===== bed leveling ==================================\n;M1002 set_flag g29_before_print_flag=1\nM1002 judge_flag g29_before_print_flag\nM622 J1\n    M1002 gcode_claim_action : 1\n    G29 A1 X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]}\n    M400\n    M500 ; save cali data\nM623\n;===== bed leveling end ================================\n\n;===== home after wipe mouth============================\nM1002 judge_flag g29_before_print_flag\nM622 J0\n\n    M1002 gcode_claim_action : 13\n    G28 T145\n\nM623\n\n;===== home after wipe mouth end =======================\n\nM975 S1 ; turn on vibration supression\n;===== nozzle load line ===============================\nM975 S1\nG90\nM83\nT1000\n\nG1 X-13.5 Y0 Z10 F10000\nG1 E1.2 F500\nM400\nM1002 set_filament_type:UNKNOWN\nM109 S{nozzle_temperature[initial_extruder]}\nM400\n\nM412 S1 ;    ===turn on  filament runout detection===\nM400 P10\n\nG392 S0 ;turn on clog detect\n\nM620.3 W1; === turn on filament tangle detection===\nM400 S2\n\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n;M1002 set_flag extrude_cali_flag=1\nM1002 judge_flag extrude_cali_flag\nM622 J1\n    M1002 gcode_claim_action : 8\n    \n    M400\n    M900 K0.0 L1000.0 M1.0\n    G90\n    M83\n    G0 X68 Y-4 F30000\n    G0 Z0.3 F18000 ;Move to start position\n    M400\n    G0 X88 E10  F{outer_wall_volumetric_speed/(24/20)    * 60}\n    G0 X93 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\n    G0 X98 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\n    G0 X103 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\n    G0 X108 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\n    G0 X113 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\n    G0 Y0 Z0 F20000\n    M400\n    \n    G1 X-13.5 Y0 Z10 F10000\n    M400\n    \n    G1 E10 F{outer_wall_volumetric_speed/2.4*60}\n    M983 F{outer_wall_volumetric_speed/2.4} A0.3 H[nozzle_diameter]; cali dynamic extrusion compensation\n    M106 P1 S178\n    M400 S7\n    G1 X0 F18000\n    G1 X-13.5 F3000\n    G1 X0 F18000 ;wipe and shake\n    G1 X-13.5 F3000\n    G1 X0 F12000 ;wipe and shake\n    G1 X-13.5 F3000\n    M400\n    M106 P1 S0\n\n    M1002 judge_last_extrude_cali_success\n    M622 J0\n        M983 F{outer_wall_volumetric_speed/2.4} A0.3 H[nozzle_diameter]; cali dynamic extrusion compensation\n        M106 P1 S178\n        M400 S7\n        G1 X0 F18000\n        G1 X-13.5 F3000\n        G1 X0 F18000 ;wipe and shake\n        G1 X-13.5 F3000\n        G1 X0 F12000 ;wipe and shake\n        M400\n        M106 P1 S0\n    M623\n    \n    G1 X-13.5 F3000\n    M400\n    M984 A0.1 E1 S1 F{outer_wall_volumetric_speed/2.4} H[nozzle_diameter]\n    M106 P1 S178\n    M400 S7\n    G1 X0 F18000\n    G1 X-13.5 F3000\n    G1 X0 F18000 ;wipe and shake\n    G1 X-13.5 F3000\n    G1 X0 F12000 ;wipe and shake\n    G1 X-13.5 F3000\n    M400\n    M106 P1 S0\n\nM623 ; end of \"draw extrinsic para cali paint\"\n\n;===== extrude cali test ===============================\nM104 S{nozzle_temperature_initial_layer[initial_extruder]}\nG90\nM83\nG0 X68 Y-2.5 F30000\nG0 Z0.3 F18000 ;Move to start position\nG0 X88 E10  F{outer_wall_volumetric_speed/(24/20)    * 60}\nG0 X93 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\nG0 X98 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\nG0 X103 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\nG0 X108 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\nG0 X113 E.3742  F{outer_wall_volumetric_speed/(0.3*0.5)/4     * 60}\nG0 X115 Z0 F20000\nG0 Z5\nM400\n\n;========turn off light and wait extrude temperature =============\nM1002 gcode_claim_action : 0\n\nM400 ; wait all motion done before implement the emprical L parameters\n\n;===== for Textured PEI Plate , lower the nozzle as the nozzle was touching topmost of the texture when homing ==\n;curr_bed_type={curr_bed_type}\n{if curr_bed_type==\"Textured PEI Plate\"}\nG29.1 Z{-0.02} ; for Textured PEI Plate\n{endif}\n\nM960 S1 P0 ; turn off laser\nM960 S2 P0 ; turn off laser\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off big fan\nM106 P3 S0 ; turn off chamber fan\n\nM975 S1 ; turn on mech mode supression\nG90\nM83\nT1000\n\nM211 X0 Y0 Z0 ;turn off soft endstop\nM1007 S1\n\n\n\n",
+    "machine_switch_extruder_time": "0",
+    "machine_unload_filament_time": "34",
+    "master_extruder_id": "1",
+    "max_bridge_length": "0",
+    "max_layer_height": [
+        "0.28"
+    ],
+    "max_travel_detour_distance": "0",
+    "min_bead_width": "85%",
+    "min_feature_size": "25%",
+    "min_layer_height": [
+        "0.08"
+    ],
+    "minimum_sparse_infill_area": "15",
+    "mmu_segmented_region_interlocking_depth": "0",
+    "mmu_segmented_region_max_width": "0",
+    "name": "project_settings",
+    "no_slow_down_for_cooling_on_outwalls": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "nozzle_diameter": [
+        "0.4"
+    ],
+    "nozzle_flush_dataset": [
+        "0"
+    ],
+    "nozzle_height": "4.76",
+    "nozzle_temperature": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_initial_layer": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_range_high": [
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240"
+    ],
+    "nozzle_temperature_range_low": [
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190"
+    ],
+    "nozzle_type": [
+        "stainless_steel"
+    ],
+    "nozzle_volume": [
+        "92"
+    ],
+    "nozzle_volume_type": [
+        "Standard"
+    ],
+    "only_one_wall_first_layer": "1",
+    "ooze_prevention": "0",
+    "other_layers_print_sequence": [
+        "0"
+    ],
+    "other_layers_print_sequence_nums": "0",
+    "outer_wall_acceleration": [
+        "5000"
+    ],
+    "outer_wall_jerk": "9",
+    "outer_wall_line_width": "0.42",
+    "outer_wall_speed": [
+        "200"
+    ],
+    "overhang_1_4_speed": [
+        "0"
+    ],
+    "overhang_2_4_speed": [
+        "50"
+    ],
+    "overhang_3_4_speed": [
+        "30"
+    ],
+    "overhang_4_4_speed": [
+        "10"
+    ],
+    "overhang_fan_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "overhang_fan_threshold": [
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "overhang_threshold_participating_cooling": [
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%"
+    ],
+    "overhang_totally_speed": [
+        "10"
+    ],
+    "override_filament_scarf_seam_setting": "0",
+    "override_process_overhang_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "physical_extruder_map": [
+        "0"
+    ],
+    "post_process": [],
+    "pre_start_fan_time": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "precise_outer_wall": "0",
+    "precise_z_height": "0",
+    "pressure_advance": [
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02"
+    ],
+    "prime_tower_brim_width": "3",
+    "prime_tower_enable_framework": "0",
+    "prime_tower_extra_rib_length": "0",
+    "prime_tower_fillet_wall": "1",
+    "prime_tower_flat_ironing": "0",
+    "prime_tower_infill_gap": "150%",
+    "prime_tower_lift_height": "-1",
+    "prime_tower_lift_speed": "90",
+    "prime_tower_max_speed": "90",
+    "prime_tower_rib_wall": "0",
+    "prime_tower_rib_width": "8",
+    "prime_tower_skip_points": "1",
+    "prime_tower_width": "170",
+    "prime_volume_mode": "Default",
+    "print_compatible_printers": [
+        "Bambu Lab A1 mini 0.4 nozzle"
+    ],
+    "print_extruder_id": [
+        "1"
+    ],
+    "print_extruder_variant": [
+        "Direct Drive Standard"
+    ],
+    "print_flow_ratio": "1",
+    "print_sequence": "by layer",
+    "print_settings_id": "Bambu_Lumina",
+    "printable_area": [
+        "0x0",
+        "180x0",
+        "180x180",
+        "0x180"
+    ],
+    "printable_height": "180",
+    "printer_extruder_id": [
+        "1"
+    ],
+    "printer_extruder_variant": [
+        "Direct Drive Standard"
+    ],
+    "printer_model": "Bambu Lab A1 mini",
+    "printer_notes": "",
+    "printer_settings_id": "Bambu Lab A1 mini 0.4 nozzle",
+    "printer_structure": "i3",
+    "printer_technology": "FFF",
+    "printer_variant": "0.4",
+    "printhost_authorization_type": "key",
+    "printhost_ssl_ignore_revoke": "0",
+    "printing_by_object_gcode": "",
+    "process_notes": "",
+    "raft_contact_distance": "0.1",
+    "raft_expansion": "1.5",
+    "raft_first_layer_density": "90%",
+    "raft_first_layer_expansion": "-1",
+    "raft_layers": "0",
+    "reduce_crossing_wall": "0",
+    "reduce_fan_stop_start_freq": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "reduce_infill_retraction": "1",
+    "required_nozzle_HRC": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "resolution": "0.012",
+    "retract_before_wipe": [
+        "0%"
+    ],
+    "retract_length_toolchange": [
+        "2"
+    ],
+    "retract_lift_above": [
+        "0"
+    ],
+    "retract_lift_below": [
+        "179"
+    ],
+    "retract_restart_extra": [
+        "0"
+    ],
+    "retract_restart_extra_toolchange": [
+        "0"
+    ],
+    "retract_when_changing_layer": [
+        "1"
+    ],
+    "retraction_distances_when_cut": [
+        "18"
+    ],
+    "retraction_distances_when_ec": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retraction_length": [
+        "0.8"
+    ],
+    "retraction_minimum_travel": [
+        "1"
+    ],
+    "retraction_speed": [
+        "30"
+    ],
+    "role_base_wipe_speed": "1",
+    "scan_first_layer": "0",
+    "scarf_angle_threshold": "155",
+    "seam_gap": "15%",
+    "seam_placement_away_from_overhangs": "0",
+    "seam_position": "aligned",
+    "seam_slope_conditional": "1",
+    "seam_slope_entire_loop": "0",
+    "seam_slope_gap": "0",
+    "seam_slope_inner_walls": "1",
+    "seam_slope_min_length": "10",
+    "seam_slope_start_height": "10%",
+    "seam_slope_steps": "10",
+    "seam_slope_type": "none",
+    "silent_mode": "0",
+    "single_extruder_multi_material": "1",
+    "skeleton_infill_density": "100%",
+    "skeleton_infill_line_width": "0.45",
+    "skin_infill_density": "100%",
+    "skin_infill_depth": "2",
+    "skin_infill_line_width": "0.45",
+    "skirt_distance": "2",
+    "skirt_height": "1",
+    "skirt_loops": "0",
+    "slice_closing_radius": "0.049",
+    "slicing_mode": "regular",
+    "slow_down_for_layer_cooling": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "slow_down_layer_time": [
+        "6",
+        "6",
+        "6",
+        "6",
+        "6",
+        "6",
+        "6",
+        "6"
+    ],
+    "slow_down_min_speed": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "slowdown_end_acc": [
+        "100000"
+    ],
+    "slowdown_end_height": [
+        "400"
+    ],
+    "slowdown_end_speed": [
+        "1000"
+    ],
+    "slowdown_start_acc": [
+        "100000"
+    ],
+    "slowdown_start_height": [
+        "0"
+    ],
+    "slowdown_start_speed": [
+        "1000"
+    ],
+    "small_perimeter_speed": [
+        "50%"
+    ],
+    "small_perimeter_threshold": [
+        "0"
+    ],
+    "smooth_coefficient": "80",
+    "smooth_speed_discontinuity_area": "1",
+    "solid_infill_filament": "0",
+    "sparse_infill_acceleration": [
+        "100%"
+    ],
+    "sparse_infill_anchor": "400%",
+    "sparse_infill_anchor_max": "20",
+    "sparse_infill_density": "100%",
+    "sparse_infill_filament": "0",
+    "sparse_infill_lattice_angle_1": "-45",
+    "sparse_infill_lattice_angle_2": "45",
+    "sparse_infill_line_width": "0.45",
+    "sparse_infill_pattern": "alignedrectilinear",
+    "sparse_infill_speed": [
+        "270"
+    ],
+    "spiral_mode": "0",
+    "spiral_mode_max_xy_smoothing": "200%",
+    "spiral_mode_smooth": "0",
+    "standby_temperature_delta": "-5",
+    "start_end_points": [
+        "30x-3",
+        "54x245"
+    ],
+    "supertack_plate_temp": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "supertack_plate_temp_initial_layer": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "support_air_filtration": "0",
+    "support_angle": "0",
+    "support_base_pattern": "default",
+    "support_base_pattern_spacing": "2.5",
+    "support_bottom_interface_spacing": "0.5",
+    "support_bottom_z_distance": "0.2",
+    "support_chamber_temp_control": "0",
+    "support_cooling_filter": "0",
+    "support_critical_regions_only": "0",
+    "support_expansion": "0",
+    "support_filament": "0",
+    "support_interface_bottom_layers": "2",
+    "support_interface_filament": "0",
+    "support_interface_loop_pattern": "0",
+    "support_interface_not_for_body": "1",
+    "support_interface_pattern": "auto",
+    "support_interface_spacing": "0.5",
+    "support_interface_speed": [
+        "80"
+    ],
+    "support_interface_top_layers": "2",
+    "support_ironing_direction": "0",
+    "support_ironing_flow": "10%",
+    "support_ironing_inset": "0",
+    "support_ironing_pattern": "zig-zag",
+    "support_ironing_spacing": "0.15",
+    "support_ironing_speed": "30",
+    "support_line_width": "0.42",
+    "support_object_first_layer_gap": "0.2",
+    "support_object_skip_flush": "0",
+    "support_object_xy_distance": "0.35",
+    "support_on_build_plate_only": "0",
+    "support_remove_small_overhang": "1",
+    "support_speed": [
+        "150"
+    ],
+    "support_style": "default",
+    "support_threshold_angle": "30",
+    "support_top_z_distance": "0.2",
+    "support_type": "tree(auto)",
+    "symmetric_infill_y_axis": "0",
+    "temperature_vitrification": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "template_custom_gcode": "",
+    "textured_plate_temp": [
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65"
+    ],
+    "textured_plate_temp_initial_layer": [
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65",
+        "65"
+    ],
+    "thick_bridges": "0",
+    "thumbnail_size": [
+        "50x50"
+    ],
+    "time_lapse_gcode": ";===================== date: 20250206 =====================\n{if !spiral_mode && print_sequence != \"by object\"}\n; don't support timelapse gcode in spiral_mode and by object sequence for I3 structure printer\n; SKIPPABLE_START\n; SKIPTYPE: timelapse\nM622.1 S1 ; for prev firmware, default turned on\nM1002 judge_flag timelapse_record_flag\nM622 J1\nG92 E0\nG1 Z{max_layer_z + 0.4}\nG1 X0 Y{first_layer_center_no_wipe_tower[1]} F18000 ; move to safe pos\nG1 X-13.0 F3000 ; move to safe pos\nM400\nM1004 S5 P1  ; external shutter\nM400 P300\nM971 S11 C11 O0\nG92 E0\nG1 X0 F18000\nM623\n\n; SKIPTYPE: head_wrap_detect\nM622.1 S1\nM1002 judge_flag g39_3rd_layer_detect_flag\nM622 J1\n    ; enable nozzle clog detect at 3rd layer\n    {if layer_num == 2}\n      M400\n      G90\n      M83\n      M204 S5000\n      G0 Z2 F4000\n      G0 X187 Y178 F20000\n      G39 S1 X187 Y178\n      G0 Z2 F4000\n    {endif}\n\n\n    M622.1 S1\n    M1002 judge_flag g39_detection_flag\n    M622 J1\n      {if !in_head_wrap_detect_zone}\n        M622.1 S0\n        M1002 judge_flag g39_mass_exceed_flag\n        M622 J1\n        {if layer_num > 2}\n            G392 S0\n            M400\n            G90\n            M83\n            M204 S5000\n            G0 Z{max_layer_z + 0.4} F4000\n            G39.3 S1\n            G0 Z{max_layer_z + 0.4} F4000\n            G392 S0\n          {endif}\n        M623\n    {endif}\n    M623\nM623\n; SKIPPABLE_END\n{endif}\n\n\n",
+    "timelapse_type": "0",
+    "top_area_threshold": "200%",
+    "top_color_penetration_layers": "5",
+    "top_one_wall_type": "all top",
+    "top_shell_layers": "0",
+    "top_shell_thickness": "1",
+    "top_solid_infill_flow_ratio": [
+        "1"
+    ],
+    "top_surface_acceleration": [
+        "2000"
+    ],
+    "top_surface_density": "100%",
+    "top_surface_jerk": "9",
+    "top_surface_line_width": "0.42",
+    "top_surface_pattern": "monotonicline",
+    "top_surface_speed": [
+        "200"
+    ],
+    "top_z_overrides_xy_distance": "0",
+    "travel_acceleration": [
+        "10000"
+    ],
+    "travel_jerk": "9",
+    "travel_short_distance_acceleration": [
+        "250"
+    ],
+    "travel_speed": [
+        "700"
+    ],
+    "travel_speed_z": [
+        "0"
+    ],
+    "tree_support_branch_angle": "45",
+    "tree_support_branch_diameter": "2",
+    "tree_support_branch_diameter_angle": "5",
+    "tree_support_branch_distance": "5",
+    "tree_support_wall_count": "-1",
+    "upward_compatible_machine": [
+        "Bambu Lab P1S 0.4 nozzle",
+        "Bambu Lab P1P 0.4 nozzle",
+        "Bambu Lab X1 0.4 nozzle",
+        "Bambu Lab X1 Carbon 0.4 nozzle",
+        "Bambu Lab X1E 0.4 nozzle",
+        "Bambu Lab A1 0.4 nozzle",
+        "Bambu Lab H2D 0.4 nozzle",
+        "Bambu Lab H2D Pro 0.4 nozzle",
+        "Bambu Lab H2S 0.4 nozzle",
+        "Bambu Lab P2S 0.4 nozzle",
+        "Bambu Lab H2C 0.4 nozzle"
+    ],
+    "use_firmware_retraction": "0",
+    "use_relative_e_distances": "1",
+    "version": "02.05.00.66",
+    "vertical_shell_speed": [
+        "80%"
+    ],
+    "volumetric_speed_coefficients": [
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0"
+    ],
+    "wall_distribution_count": "1",
+    "wall_filament": "0",
+    "wall_generator": "classic",
+    "wall_loops": "1",
+    "wall_sequence": "inner wall/outer wall",
+    "wall_transition_angle": "10",
+    "wall_transition_filter_deviation": "25%",
+    "wall_transition_length": "100%",
+    "wipe": [
+        "1"
+    ],
+    "wipe_distance": [
+        "2"
+    ],
+    "wipe_speed": "80%",
+    "wipe_tower_no_sparse_layers": "0",
+    "wipe_tower_rotation_angle": "0",
+    "wipe_tower_x": [
+        "5.70098"
+    ],
+    "wipe_tower_y": [
+        "149.411"
+    ],
+    "wrapping_detection_gcode": "",
+    "wrapping_detection_layers": "20",
+    "wrapping_exclude_area": [],
+    "xy_contour_compensation": "0",
+    "xy_hole_compensation": "0",
+    "z_direction_outwall_speed_continuous": "0",
+    "z_hop": [
+        "0.4"
+    ],
+    "z_hop_types": [
+        "Auto Lift"
+    ]
+}
\ No newline at end of file
diff --git a/printer_profiles/bambu_h2c.json b/printer_profiles/bambu_h2c.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_h2c.json
@@ -0,0 +1,2118 @@
+{
+    "accel_to_decel_enable": "0",
+    "accel_to_decel_factor": "50%",
+    "activate_air_filtration": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "additional_cooling_fan_speed": [
+        "75",
+        "75",
+        "75",
+        "75"
+    ],
+    "apply_scarf_seam_on_circles": "1",
+    "apply_top_surface_compensation": "0",
+    "auxiliary_fan": "1",
+    "avoid_crossing_wall_includes_support": "0",
+    "bed_custom_model": "",
+    "bed_custom_texture": "",
+    "bed_exclude_area": [],
+    "bed_temperature_formula": "by_highest_temp",
+    "before_layer_change_gcode": "",
+    "best_object_pos": "0.3,0.5",
+    "bottom_color_penetration_layers": "7",
+    "bottom_shell_layers": "0",
+    "bottom_shell_thickness": "0",
+    "bottom_surface_density": "100%",
+    "bottom_surface_pattern": "zig-zag",
+    "bridge_angle": "0",
+    "bridge_flow": "1",
+    "bridge_no_support": "0",
+    "bridge_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "brim_object_gap": "0.1",
+    "brim_type": "auto_brim",
+    "brim_width": "5",
+    "chamber_temperatures": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "change_filament_gcode": ";======== H2D ========\n;===== 20260116 =====\nM993 A2 B2 C2 ; nozzle cam detection allow status save.\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\n{if (filament_type[next_extruder] == \"PLA\") ||  (filament_type[next_extruder] == \"PETG\")\n ||  (filament_type[next_extruder] == \"PLA-CF\")  ||  (filament_type[next_extruder] == \"PETG-CF\")}\nM1015.4 S1 K0 ;disable E air printing detect\n{else}\nM1015.4 S0 ; disable E air printing detect\n{endif}\n\nM620 S[next_extruder]A\nM1002 gcode_claim_action : 4\nM204 S9000\n\nG1 Z{max_layer_z + 3.0} F1200\n\nM400\nM106 P1 S0\nM106 P2 S0\n\n{if toolchange_count == 2}\n; get travel path for change filament\n;M620.1 X[travel_point_1_x] Y[travel_point_1_y] F21000 P0\n;M620.1 X[travel_point_2_x] Y[travel_point_2_y] F21000 P1\n;M620.1 X[travel_point_3_x] Y[travel_point_3_y] F21000 P2\n{endif}\n\n{if ((filament_type[current_extruder] == \"PLA\") || (filament_type[current_extruder] == \"PLA-CF\") || (filament_type[current_extruder] == \"PETG\")) && (nozzle_diameter[current_extruder] == 0.2)}\nM620.10 A0 F74.8347 L[flush_length] H{nozzle_diameter[current_extruder]} T{flush_temperatures[current_extruder]} P[old_filament_temp] S1\n{else}\nM620.10 A0 F{flush_volumetric_speeds[current_extruder]/2.4053*60*0.8} L[flush_length] H{nozzle_diameter[current_extruder]} T{flush_temperatures[current_extruder]} P[old_filament_temp] S1\n{endif}\n\n{if ((filament_type[next_extruder] == \"PLA\") || (filament_type[next_extruder] == \"PLA-CF\") || (filament_type[next_extruder] == \"PETG\")) && (nozzle_diameter[next_extruder] == 0.2)}\nM620.10 A1 F74.8347 L[flush_length] H{nozzle_diameter[next_extruder]} T{flush_temperatures[next_extruder]} P[new_filament_temp] S1\n{else}\nM620.10 A1 F{flush_volumetric_speeds[next_extruder]/2.4053*60*0.8} L[flush_length] H{nozzle_diameter[next_extruder]} T{flush_temperatures[next_extruder]} P[new_filament_temp] S1\n{endif}\n\n{if long_retraction_when_cut}\nM620.11 P1 I[current_extruder] E-{retraction_distance_when_cut} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 P0 I[current_extruder] E0\n{endif}\n\n{if long_retraction_when_ec}\nM620.11 K1 I[current_extruder] R{retraction_distance_when_ec} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 K0 I[current_extruder] R0\n{endif}\n\nM620.15 C{new_filament_temp - filament_cooling_before_tower[next_extruder]}\n\nM628 S1\n{if filament_type[current_extruder] == \"TPU\"}\nM620.11 S0 L0 I[current_extruder] E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\n{if (filament_type[current_extruder] == \"PA\") || (filament_type[current_extruder] == \"PA-GF\")}\nM620.11 S1 L0 I[current_extruder] R4 D2 E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 S1 L0 I[current_extruder] R10 D8 E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{endif}\n{endif}\nM629\n\n{if (filament_type[current_extruder] == \"TPU\" || filament_type[next_extruder] == \"TPU\") && (old_extruder_variant != \"Direct Drive TPU High Flow\")}\nM620.11 H2 C331\n{else}\nM620.11 H0\n{endif}\n\n{if  (old_extruder_variant == \"Direct Drive TPU High Flow\") && (filament_map[current_extruder] == 2) && (filament_map[next_extruder] == 1)}\n;debug log pe:{previous_extruder} ce:{current_extruder} ne:{next_extruder} oev: {old_extruder_variant} nev:{new_extruder_variant}\n;debug fm-curr:{filament_map[current_extruder]} fm-next:{filament_map[next_extruder]}\n;sw from R2L&TPU kit, travel run a distance for sketch TPU\nG1 X30 Y30 F5000\nM400\nG1 X300 Y30 F5000\nM400\n{endif}\n\nT[next_extruder]\n\n;deretract\n{if filament_type[next_extruder] == \"TPU\"}\n{else}\n{if (filament_type[next_extruder] == \"PA\") || (filament_type[next_extruder] == \"PA-GF\")}\n;VG1 E1 F{max(new_filament_e_feedrate, 200)}\n;VG1 E1 F{max(new_filament_e_feedrate/2, 100)}\n{else}\n;VG1 E4 F{max(new_filament_e_feedrate, 200)}\n;VG1 E4 F{max(new_filament_e_feedrate/2, 100)}\n{endif}\n{endif}\n\n; VFLUSH_START\n\n{if flush_length>41.5}\n;VG1 E41.5 F{min(old_filament_e_feedrate,new_filament_e_feedrate)}\n;VG1 E{flush_length-41.5} F{new_filament_e_feedrate}\n{else}\n;VG1 E{flush_length} F{min(old_filament_e_feedrate,new_filament_e_feedrate)}\n{endif}\n\nSYNC T{ceil(flush_length / 125) * 5}\n\n; VFLUSH_END\n\nM1002 set_filament_type:{filament_type[next_extruder]}\n\nM400\nM83\n{if next_extruder < 255}\n\nM620.10 R{new_extruder_retracted_length}\nM628 S0\n;VM109 S[new_filament_temp]\nM629\nM400\n\n;prime_tower_interface\n{if is_prime_tower_interface && filament_tower_interface_purge_volume !=0}\nG150.1\nM620.13 W0 L{filament_tower_interface_purge_volume} T{filament_tower_interface_print_temp} R0.0\n{endif}\n;prime_tower_interface\n\nM983.3 F{filament_max_volumetric_speed[next_extruder]/2.4} A0.4 R{new_extruder_retracted_length}\n\nM400\n{if wipe_avoid_perimeter}\nG1 Y320 F30000\nG1 X{wipe_avoid_pos_x} F30000\n{endif}\nG1 Y295 F30000\nG1 Y265 F18000\nG1 Z{max_layer_z + 3.0} F3000\n{if layer_z <= (initial_layer_print_height + 0.001)}\nM204 S[initial_layer_acceleration]\n{else}\nM204 S[default_acceleration]\n{endif}\n{else}\nG1 X[x_after_toolchange] Y[y_after_toolchange] Z[z_after_toolchange] F12000\n{endif}\nM621 S[next_extruder]A\n\nM993 A3 B3 C3 ; nozzle cam detection allow status restore.\n\n{if (filament_type[next_extruder]  == \"TPU\")}\nM1015.3 S1;enable tpu clog detect\n{else}\nM1015.3 S0;disable tpu clog detect\n{endif}\n\n{if (filament_type[next_extruder] == \"PLA\") ||  (filament_type[next_extruder] == \"PETG\")\n ||  (filament_type[next_extruder] == \"PLA-CF\")  ||  (filament_type[next_extruder] == \"PETG-CF\")}\nM1015.4 S1 K1 H[nozzle_diameter] ;enable E air printing detect\n{else}\nM1015.4 S0 ; disable E air printing detect\n{endif}\n\nM620.6 I[next_extruder] W1 ;enable ams air printing detect\nM1002 gcode_claim_action : 0",
+    "circle_compensation_manual_offset": "0",
+    "circle_compensation_speed": [
+        "200",
+        "200",
+        "200",
+        "200"
+    ],
+    "close_fan_the_first_x_layers": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "complete_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "cool_plate_temp": [
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cool_plate_temp_initial_layer": [
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cooling_filter_enabled": "0",
+    "cooling_perimeter_transition_distance": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "cooling_slowdown_logic": [
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling"
+    ],
+    "counter_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "counter_coef_2": [
+        "0.003",
+        "0.003",
+        "0.003",
+        "0.003"
+    ],
+    "counter_coef_3": [
+        "0.01",
+        "0.01",
+        "0.01",
+        "0.01"
+    ],
+    "counter_limit_max": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "counter_limit_min": [
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035"
+    ],
+    "curr_bed_type": "Textured PEI Plate",
+    "default_acceleration": [
+        "4000",
+        "4000",
+        "4000",
+        "4000",
+        "4000"
+    ],
+    "default_filament_colour": [
+        "",
+        "",
+        "",
+        ""
+    ],
+    "default_filament_profile": [
+        "Bambu PLA Basic @BBL H2C"
+    ],
+    "default_jerk": "0",
+    "default_nozzle_volume_type": [
+        "Standard",
+        "Standard"
+    ],
+    "default_print_profile": "0.20mm Standard @BBL H2C",
+    "deretraction_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "detect_floating_vertical_shell": "1",
+    "detect_narrow_internal_solid_infill": "0",
+    "detect_overhang_wall": "1",
+    "detect_thin_wall": "0",
+    "diameter_limit": [
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "different_settings_to_system": [
+        "bottom_shell_layers;bottom_surface_pattern;detect_narrow_internal_solid_infill;infill_direction;initial_layer_line_width;initial_layer_print_height;inner_wall_line_width;only_one_wall_first_layer;prime_tower_rib_wall;prime_tower_width;skeleton_infill_density;skeleton_infill_line_width;skin_infill_density;skin_infill_line_width;sparse_infill_density;sparse_infill_line_width;sparse_infill_pattern;top_shell_layers;top_surface_pattern;wall_generator;wall_loops",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "draft_shield": "disabled",
+    "during_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "elefant_foot_compensation": "0.15",
+    "embedding_wall_into_infill": "0",
+    "enable_arc_fitting": "1",
+    "enable_circle_compensation": "0",
+    "enable_height_slowdown": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_long_retraction_when_cut": "2",
+    "enable_overhang_bridge_fan": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_pre_heating": "1",
+    "enable_pressure_advance": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_prime_tower": "1",
+    "enable_support": "0",
+    "enable_support_ironing": "0",
+    "enable_tower_interface_features": "1",
+    "enable_wrapping_detection": "0",
+    "enforce_support_layers": "0",
+    "eng_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "eng_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "ensure_vertical_shell_thickness": "enabled",
+    "exclude_object": "1",
+    "extruder_ams_count": [
+        "1#0|4#0",
+        "1#0|4#0"
+    ],
+    "extruder_clearance_dist_to_rod": "50",
+    "extruder_clearance_height_to_lid": "201",
+    "extruder_clearance_height_to_rod": "47.4",
+    "extruder_clearance_max_radius": "96",
+    "extruder_colour": [
+        "#018001",
+        "#018001"
+    ],
+    "extruder_max_nozzle_count": [
+        "1",
+        "1"
+    ],
+    "extruder_nozzle_stats": [
+        "Standard#1",
+        "Standard#1"
+    ],
+    "extruder_offset": [
+        "0x0",
+        "0x0"
+    ],
+    "extruder_printable_area": [
+        "0x0,325x0,325x320,0x320",
+        "25x0,350x0,350x320,25x320"
+    ],
+    "extruder_printable_height": [
+        "320",
+        "325"
+    ],
+    "extruder_type": [
+        "Direct Drive",
+        "Direct Drive"
+    ],
+    "extruder_variant_list": [
+        "Direct Drive Standard,Direct Drive High Flow",
+        "Direct Drive Standard,Direct Drive High Flow,Direct Drive TPU High Flow"
+    ],
+    "fan_cooling_layer_time": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "fan_direction": "left",
+    "fan_max_speed": [
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "fan_min_speed": [
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_adaptive_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_adhesiveness_category": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_bridge_speed": [
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25"
+    ],
+    "filament_change_length": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_change_length_nc": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_colour": [
+        "#FFFFFF",
+        "#C12E1F",
+        "#F4EE2A",
+        "#0000FF"
+    ],
+    "filament_colour_type": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_cooling_before_tower": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_cost": [
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99"
+    ],
+    "filament_density": [
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26"
+    ],
+    "filament_deretraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_dev_ams_drying_ams_limitations": [
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0"
+    ],
+    "filament_dev_ams_drying_heat_distortion_temperature": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_chamber_drying_bed_temperature": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "filament_dev_chamber_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_drying_cooling_temperature": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_drying_softening_temperature": [
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_diameter": [
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75"
+    ],
+    "filament_enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_end_gcode": [
+        "; filament end gcode \n",
+        "; filament end gcode \n",
+        "; filament end gcode \n",
+        "; filament end gcode \n"
+    ],
+    "filament_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "filament_flow_ratio": [
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98"
+    ],
+    "filament_flush_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_flush_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ids": [
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00"
+    ],
+    "filament_is_support": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_long_retractions_when_cut": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_map": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map_mode": "Auto For Flush",
+    "filament_max_volumetric_speed": [
+        "25",
+        "40",
+        "25",
+        "40",
+        "25",
+        "40",
+        "25",
+        "40"
+    ],
+    "filament_minimal_purge_on_wipe_tower": [
+        "15",
+        "15",
+        "15",
+        "15"
+    ],
+    "filament_multi_colour": [
+        "#FFFFFF",
+        "#C12E1F",
+        "#F4EE2A",
+        "#0000FF"
+    ],
+    "filament_notes": "",
+    "filament_nozzle_map": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_1_4_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_2_4_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_overhang_3_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_pre_cooling_temperature": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_pre_cooling_temperature_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_prime_volume": [
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_prime_volume_nc": [
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_printable": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "filament_ramming_travel_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_travel_time_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_volumetric_speed": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_ramming_volumetric_speed_nc": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_retract_before_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_length_nc": [
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14"
+    ],
+    "filament_retract_restart_extra": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_when_changing_layer": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_distances_when_cut": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_length": [
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4"
+    ],
+    "filament_retraction_minimum_travel": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_scarf_gap": [
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "filament_scarf_height": [
+        "10%",
+        "10%",
+        "10%",
+        "10%"
+    ],
+    "filament_scarf_length": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_scarf_seam_type": [
+        "none",
+        "none",
+        "none",
+        "none"
+    ],
+    "filament_self_index": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "3",
+        "3",
+        "4",
+        "4"
+    ],
+    "filament_settings_id": [
+        "Bambu PLA Basic @BBL H2C",
+        "Bambu PLA Basic @BBL H2C",
+        "Bambu PLA Basic @BBL H2C",
+        "Bambu PLA Basic @BBL H2C"
+    ],
+    "filament_shrink": [
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "filament_soluble": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_start_gcode": [
+        "; filament start gcode\n",
+        "; filament start gcode\n",
+        "; filament start gcode\n",
+        "; filament start gcode\n"
+    ],
+    "filament_tower_interface_pre_extrusion_dist": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_tower_interface_pre_extrusion_length": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_tower_interface_print_temp": [
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_tower_interface_purge_volume": [
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "filament_tower_ironing_area": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_type": [
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA"
+    ],
+    "filament_velocity_adaptation_factor": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_vendor": [
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab"
+    ],
+    "filament_volume_map": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_wipe": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_wipe_distance": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_z_hop": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop_types": [
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift"
+    ],
+    "filename_format": "{input_filename_base}_{filament_type[0]}_{print_time}.gcode",
+    "fill_multiline": "1",
+    "filter_out_gap_fill": "0",
+    "first_layer_print_sequence": [
+        "0"
+    ],
+    "first_x_layer_fan_speed": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "flush_into_infill": "0",
+    "flush_into_objects": "0",
+    "flush_into_support": "1",
+    "flush_multiplier": [
+        "1",
+        "1"
+    ],
+    "flush_volumes_matrix": [
+        "0",
+        "90",
+        "90",
+        "402",
+        "900",
+        "0",
+        "450",
+        "351",
+        "900",
+        "180",
+        "0",
+        "391",
+        "791",
+        "547",
+        "770",
+        "0",
+        "0",
+        "90",
+        "90",
+        "417",
+        "900",
+        "0",
+        "450",
+        "366",
+        "900",
+        "180",
+        "0",
+        "406",
+        "806",
+        "562",
+        "785",
+        "0"
+    ],
+    "flush_volumes_vector": [
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140"
+    ],
+    "from": "project",
+    "full_fan_speed_layer": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "fuzzy_skin": "none",
+    "fuzzy_skin_point_distance": "0.8",
+    "fuzzy_skin_thickness": "0.3",
+    "gap_infill_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "gcode_add_line_number": "0",
+    "gcode_flavor": "marlin",
+    "grab_length": [
+        "0",
+        "0"
+    ],
+    "group_algo_with_time": "0",
+    "has_scarf_joint_seam": "0",
+    "head_wrap_detect_zone": [],
+    "hole_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "hole_coef_2": [
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008"
+    ],
+    "hole_coef_3": [
+        "0.18",
+        "0.18",
+        "0.18",
+        "0.18"
+    ],
+    "hole_limit_max": [
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22"
+    ],
+    "hole_limit_min": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "host_type": "octoprint",
+    "hot_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hot_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hotend_cooling_rate": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "hotend_heating_rate": [
+        "3.6",
+        "3.6",
+        "3.6",
+        "3.6",
+        "3.6"
+    ],
+    "impact_strength_z": [
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8"
+    ],
+    "independent_support_layer_height": "1",
+    "infill_combination": "0",
+    "infill_direction": "0",
+    "infill_instead_top_bottom_surfaces": "0",
+    "infill_jerk": "9",
+    "infill_lock_depth": "1",
+    "infill_rotate_step": "0",
+    "infill_shift_step": "0.4",
+    "infill_wall_overlap": "15%",
+    "inherits_group": [
+        "0.08mm Extra Fine @BBL H2C",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "initial_layer_acceleration": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "initial_layer_flow_ratio": "1",
+    "initial_layer_infill_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "initial_layer_jerk": "9",
+    "initial_layer_line_width": "0.42",
+    "initial_layer_print_height": "0.08",
+    "initial_layer_speed": [
+        "40",
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "initial_layer_travel_acceleration": [
+        "6000",
+        "6000",
+        "6000",
+        "6000",
+        "6000"
+    ],
+    "inner_wall_acceleration": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "inner_wall_jerk": "9",
+    "inner_wall_line_width": "0.42",
+    "inner_wall_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "interface_shells": "0",
+    "interlocking_beam": "0",
+    "interlocking_beam_layer_count": "2",
+    "interlocking_beam_width": "0.8",
+    "interlocking_boundary_avoidance": "2",
+    "interlocking_depth": "2",
+    "interlocking_orientation": "22.5",
+    "internal_bridge_support_thickness": "0.8",
+    "internal_solid_infill_line_width": "0.42",
+    "internal_solid_infill_pattern": "zig-zag",
+    "internal_solid_infill_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "ironing_direction": "45",
+    "ironing_flow": "8%",
+    "ironing_inset": "0.21",
+    "ironing_pattern": "zig-zag",
+    "ironing_spacing": "0.15",
+    "ironing_speed": "30",
+    "ironing_type": "no ironing",
+    "is_infill_first": "0",
+    "layer_change_gcode": ";======== H2D 20250710 layer_change ========\n; layer num/total_layer_count: {layer_num+1}/[total_layer_count]\n; update layer progress\nM73 L{layer_num+1}\nM991 S0 P{layer_num} ;notify layer change\n",
+    "layer_height": "0.08",
+    "line_width": "0.42",
+    "locked_skeleton_infill_pattern": "zigzag",
+    "locked_skin_infill_pattern": "crosszag",
+    "long_retractions_when_cut": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "long_retractions_when_ec": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "machine_end_gcode": ";========== H2D end ==========\n;===== date: 2025/12/26 =====\n\nG392 S0 ;turn off nozzle clog detect\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\nM400 ; wait for buffer to clear\nG92 E0 ; zero the extruder\nG1 E-0.8 F1800 ; retract\nM400\nM211 Z1\nG1 Z{max_layer_z + 0.4} F900 ; lower z a little\n\nM1002 judge_flag timelapse_record_flag\nM622 J1\n    G150.3\n    M400 ; wait all motion done\n    M991 S0 P-1 ;end smooth timelapse at safe pos\n    M400 S5 ;wait for last picture to be taken\nM623  ;end of \"timelapse_record_flag\"\n\nG90\nG1 Z{max_layer_z + 10} F900 ; lower z a little\n\nG90\nM141 S0 ; turn off chamber heating\nM140 S0 ; turn off bed\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off remote part cooling fan\nM106 P3 S0 ; turn off chamber cooling fan\nM106 P9 S0 ; turn off ext toodhead cooling fan\n; pull back filament to AMS\nM620 S65535\nT65535\nG150.2\nM621 S65535\n\nM620 S65279\nT65279\nG150.2\nM621 S65279\n\nG150.3\n\nM104 S0 T0; turn off hotend\nM104 S0 T1; turn off hotend\n\nM400 ; wait all motion done\nM17 S\nM17 Z0.4 ; lower z motor current to reduce impact if there is something in the bottom\n{if (100.0 - max_layer_z/2) > 0}\n    {if (max_layer_z + 100.0 - max_layer_z/2) < 320}\n        G1 Z{max_layer_z + 100.0 - max_layer_z/2} F600\n        G1 Z{max_layer_z + 98.0 - max_layer_z/2}\n    {else}\n        G1 Z320 F600\n        G1 Z320\n    {endif}\n{else}\n    {if (max_layer_z + 4.0) < 320}\n        G1 Z{max_layer_z + 4.0} F600\n        G1 Z{max_layer_z + 2.0}\n    {else}\n        G1 Z320 F600\n        G1 Z320\n    {endif}\n{endif}\nM400 P100\nM17 R ; restore z current\n\nM220 S100  ; Reset feedrate magnitude\nM201.2 K1.0 ; Reset acc magnitude\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 0\n\nM1015.4 S0 K0 ;disable air printing detect\n\n;=====printer finish air purification=========\nM622.1 S0\nM1002 judge_flag print_finish_air_filt_flag\n\nM622 J1\nM1002 gcode_claim_action : 66\nM145 P1\nM106 P6 S255\nM400 S180\nM106 P6 S0\nM623\n\nM622 J2\nM1002 gcode_claim_action : 66\nM145 P0\nM106 P3 S127\nM400 S180\nM106 P3 S0\nM623\n;=====printer finish air purification=========\n\n\n;=====printer finish  sound=========\nM17\nM400 S1\nM1006 S1\nM1006 A53 B10 L99 C53 D10 M99 E53 F10 N99 \nM1006 A57 B10 L99 C57 D10 M99 E57 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A53 B10 L99 C53 D10 M99 E53 F10 N99 \nM1006 A57 B10 L99 C57 D10 M99 E57 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A48 B10 L99 C48 D10 M99 E48 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A60 B10 L99 C60 D10 M99 E60 F10 N99 \nM1006 W\n;=====printer finish  sound=========\nM400\nM18\n\n",
+    "machine_hotend_change_time": "0",
+    "machine_load_filament_time": "30",
+    "machine_max_acceleration_e": [
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_extruding": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_retracting": [
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_travel": [
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000"
+    ],
+    "machine_max_acceleration_x": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_y": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_z": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_jerk_e": [
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5"
+    ],
+    "machine_max_jerk_x": [
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_y": [
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_z": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "machine_max_speed_e": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "machine_max_speed_x": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "machine_max_speed_y": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "machine_max_speed_z": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "machine_min_extruding_rate": [
+        "0",
+        "0"
+    ],
+    "machine_min_travel_rate": [
+        "0",
+        "0"
+    ],
+    "machine_pause_gcode": "M400 U1",
+    "machine_prepare_compensation_time": "260",
+    "machine_start_gcode": ";===== machine: H2D =========================\n;===== date: 20260116 =====================\n\n;M1002 set_flag extrude_cali_flag=1\n;M1002 set_flag g29_before_print_flag=1\n;M1002 set_flag auto_cali_toolhead_offset_flag=1\n;M1002 set_flag build_plate_detect_flag=1\n\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\nM400\n;M73 P99\n\nM960 S10 P1 ; ext fan led\n\n;=====printer start sound ===================\nM17\nM400 S1\nM1006 S1\nM1006 A53 B9 L99 C53 D9 M99 E53 F9 N99 \nM1006 A56 B9 L99 C56 D9 M99 E56 F9 N99 \nM1006 A61 B9 L99 C61 D9 M99 E61 F9 N99 \nM1006 A53 B9 L99 C53 D9 M99 E53 F9 N99 \nM1006 A56 B9 L99 C56 D9 M99 E56 F9 N99 \nM1006 A61 B18 L99 C61 D18 M99 E61 F18 N99 \nM1006 W\n;=====printer start sound ===================\n\n;===== reset machine status =================\nM204 S10000\nM630 S0 P0\n\nG90\nM17 D ; reset motor current to default\nM960 S5 P1 ; turn on logo lamp\nG90\nM1002 set_gcode_claim_speed_level 5 ;Reset speed level\nM220 S100 ;Reset Feedrate\nM221 S100 ;Reset Flowrate\nM73.2   R1.0 ;Reset left time magnitude\nG29.1 Z{+0.0} ; clear z-trim value first\nM983.1 M1 \nM901 D4\nM481 S0 ; turn off cutter pos comp\nG28.140 D0; reset pre-extrude z pos\n;===== reset machine status =================\n\nM620 M ;enable remap\n\n;===== avoid end stop =================\nG91\nG380 S2 Z42 F1200\nG380 S2 Z-12 F1200\nG90\n;===== avoid end stop =================\n\n;==== set airduct mode ==== \n\n{if (overall_chamber_temperature >= 40)}\n\n    M145 P1 ; set airduct mode to heating mode for heating\n    M106 P2 S0 ; turn off auxiliary fan\n    M106 P3 S0 ; turn off chamber fan\n\n{else}\n    M145 P0 ; set airduct mode to cooling mode for cooling\n    M106 P2 S178 ; turn on auxiliary fan for cooling\n    M106 P3 S127 ; turn on chamber fan for cooling\n    M140 S0 ; stop heatbed from heating\n\n    M1002 gcode_claim_action : 29\n    M191 S0 ; wait for chamber temp\n    M106 P2 S0 ; turn off auxiliary fan\n    {if (min_vitrification_temperature <= 50)}\n        {if (nozzle_diameter == 0.2)}\n            M142 P1 R30 S35 T40 U0.3 V0.5 W0.8 O40 ; set PLA/TPU ND0.2 chamber autocooling\n        {else}\n            M142 P1 R30 S40 T45 U0.3 V0.5 W0.8 O45; set PLA/TPU ND0.4 chamber autocooling\n        {endif}\n    {else}\n        {if (!is_all_bbl_filament)}\n            M142 P1 R35 S40 T45 U0.3 V0.5 W0.8 O45 L1 ; set third-party PETG chamber autocooling\n        {else}\n            {if (nozzle_diameter == 0.2)}\n                M142 P1 R35 S45 T50 U0.3 V0.5 W0.8 O50 L1 ; set PETG ND0.2 chamber autocooling\n            {else}\n                M142 P1 R35 S50 T55 U0.3 V0.5 W0.8 O55 L1 ; set PETG ND0.4 chamber autocooling\n            {endif}\n        {endif}\n    {endif}\n    {if(cooling_filter_enabled)}\n        M145.2 P0 F0\n    {else}\n        M145.2 P0 F1\n    {endif}\n{endif}\n;==== set airduct mode ==== \n\n;===== start to heat heatbed & hotend==========\n\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n\n    M104 S140 A\n    M140 S[bed_temperature_initial_layer_single]\n\n    ;===== set chamber temperature ==========\n    {if (overall_chamber_temperature >= 40)}\n        M145 P1 ; set airduct mode to heating mode\n        M141 S[overall_chamber_temperature] ; Let Chamber begin to heat\n    {endif}\n    ;===== set chamber temperature ==========\n\n;===== start to heat heatbead & hotend==========\n\n;====== cog noise reduction=================\nM982.2 S1 ; turn on cog noise reduction\n\n;===== first homing start =====\nM1002 gcode_claim_action : 13\n\nG28 X T300\n\nG150.1 F18000 ; wipe mouth to avoid filament stick to heatbed\nG150.3 F18000\nM400 P200\nM972 S24 P0 T2000\n\nM1002 gcode_claim_action : 74 ; Heatbed surface foreign object detection\n{if curr_bed_type==\"Textured PEI Plate\"}\nM972 S26 P0 C0\n{else}\nM972 S36 P0 C0 X1\n{endif}\nM972 S35 P0 C0\n\nM972 S41 P0 T5000 ; trash can anti-collision\n\nM1009 Q1 L1\nG91\nG380 S2 Z30 F1200 ; lower heatbed to move toolhead\nG90\nG1 X175 Y160 F30000\nG28 Z P0 T250\nM1009 Q1 L0\n\n;===== first homing end =====\n\nM400\n;M73 P99\n\n;===== detection start =====\n    \nM1002 judge_flag build_plate_detect_flag\nM622 S1\n    ;M1002 gcode_claim_action : 11 ; Indentifying build plate type\n    M972 S19 P0 C0    ; heatbed presence detection\n    M972 S31 P0 T5000 ; toolhead camera dirty detection\n    ;M1002 gcode_claim_action : 73 ; Build plate alignment detection\n    M972 S34 P0 T5000 ; heatbed plate offset detection\nM623\n\nM1002 gcode_claim_action : 72 ; Hotend Type Detection\nT1001\nM972 S14 P0 T5000 ; nozzle type detection\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} T{filament_map[initial_no_support_extruder] % 2} ; rise temp in advance\n\nG151 P{filament_map[initial_no_support_extruder] % 2} M ; plug the heat nozzle\n\n{if max_print_z >= 145}\nM1002 gcode_claim_action : 75 ; Heatbed underside foreign object detection\nG3811 Z{max_print_z}  ; Detect obstacles at the bottom of the heated bed\n{endif}\n\n;===== detection end =====\n\nM400\n;M73 P99\n\n;===== prepare print temperature and material ==========\nM400\nM211 X0 Y0 Z0 ;turn off soft endstop\nM975 S1 ; turn on input shaping\n\nG29.2 S0 ; avoid invalid abl data\n\n{if ((filament_type[initial_no_support_extruder] == \"PLA\") || (filament_type[initial_no_support_extruder] == \"PLA-CF\") || (filament_type[initial_no_support_extruder] == \"PETG\")) && (nozzle_diameter[initial_no_support_extruder] == 0.2)}\nM620.10 A0 F74.8347 H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\nM620.10 A1 F74.8347 H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\n{else}\nM620.10 A0 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60*0.8} H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\nM620.10 A1 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60*0.8} H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\n{endif}\n\nM620.11 P0 I[initial_no_support_extruder] E0\n\n{if long_retraction_when_ec }\nM620.11 K1 I[initial_no_support_extruder] R{retraction_distance_when_ec} F{max((flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60), 200)}\n{else}\nM620.11 K0 I[initial_no_support_extruder] R0\n{endif}\n\nM628 S1\n{if filament_type[initial_no_support_extruder] == \"TPU\"}\n    M620.11 S0 L0 I[initial_no_support_extruder] E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{else}\n{if (filament_type[initial_no_support_extruder] == \"PA\") ||  (filament_type[initial_no_support_extruder] == \"PA-GF\")}\n    M620.11 S1 L0 I[initial_no_support_extruder] R4 D2 E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{else}\n    M620.11 S1 L0 I[initial_no_support_extruder] R10 D8 E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{endif}\n{endif}\nM629\n\nM620 S[initial_no_support_extruder]A   ; switch material if AMS exist\nM1002 gcode_claim_action : 4\nM1002 set_filament_type:UNKNOWN\nM400\nT[initial_no_support_extruder]\nM400\nM628 S0\nM629\nM400\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM621 S[initial_no_support_extruder]A\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]}\nM400\nM106 P1 S0\n\nG29.2 S1\n;===== prepare print temperature and material ==========\n\nM400\n;M73 P99\n\n;===== auto extrude cali start =========================\nM975 S1\nM1002 judge_flag extrude_cali_flag\n\nM622 J0\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\nM623\n\nM622 J1\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M1002 gcode_claim_action : 8\n\n    M109 S{nozzle_temperature[initial_no_support_extruder]}\n\n    G90\n    M83\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\n\n    M400\n    M106 P1 S255\n    M400 S5\n    M106 P1 S0\n    G150.3\nM623\n\nM622 J2\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M1002 gcode_claim_action : 8\n\n    M109 S{nozzle_temperature[initial_no_support_extruder]}\n\n    G90\n    M83\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\n\n    M400\n    M106 P1 S255\n    M400 S5\n    M106 P1 S0\n    G150.3\nM623\n\n;===== auto extrude cali end =========================\n\n{if filament_type[initial_no_support_extruder] == \"TPU\"}\n    G150.2\n    G150.1\n    G150.2\n    G150.1\n    G150.2\n    G150.1\n{else}\n    M106 P1 S0\n    M400 S2\n    M109 S{nozzle_temperature[initial_no_support_extruder]} ; wait tmpr to extrude\n    M83\n    {if(nozzle_diameter == 0.8)}\n        G1 E60 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    {else}\n        G1 E45 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    {endif}\n    G1 E-3 F1800\n    M400 P500\n    G150.2\n    G150.1\n{endif}\n\nG91\nG1 Y-16 F12000 ; move away from the trash bin\nG90\n\nM400\n;M73 P99\n\n;===== wipe right nozzle start =====\n\nM1002 gcode_claim_action : 14\n    G150 T{nozzle_temperature_initial_layer[initial_no_support_extruder]}\n    {if (overall_chamber_temperature >= 40)}\n        G150 T{nozzle_temperature_initial_layer[initial_no_support_extruder] - 80}\n    {endif}\nM106 S255 ; turn on fan to cool the nozzle\n\n;===== wipe left nozzle end =====\n\nM400\n;M73 P99\n\n{if (overall_chamber_temperature >= 40)}\n    M1002 gcode_claim_action : 49\n    M191 S[overall_chamber_temperature] ; wait for chamber temp\n{endif}\n\nM400\n;M73 P99\n\n;===== bed leveling ==================================\n\nM1002 judge_flag g29_before_print_flag\n\nM190 S[bed_temperature_initial_layer_single]; ensure bed temp\nM109 S140 A\nM106 S0 ; turn off fan , too noisy\n\nG91\nG1 Z5 F1200\nG90\nG1 X175 Y160 F30000\n\nM622 J1\n    M1002 gcode_claim_action : 1\n    G29.20 A3\n    G29 A1 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R \n    M400\n    M500 ; save cali data\nM623\n    \nM622 J2\n    M1002 gcode_claim_action : 1\n    {if has_tpu_in_first_layer}\n        G29.20 A3\n        G29 A1 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R\n    {else}\n        G29.20 A4\n        G29 A2 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R\n    {endif}\n    M400\n    M500 ; save cali data\nM623\n\nM622 J0\n    G28 R\nM623\n\n;===== bed leveling end ================================\n\n;===== z ofst cali start =====\n\n    M190 S[bed_temperature_initial_layer_single]; ensure bed temp\n\n    G383 O0 M2 T140\n    M500\n\n;===== z ofst cali end =====\n\nG39.1 ; cali nozzle wrapped detection pos\nM500\n\nG90\nG1 Z5 F1200\nG1 X270 Y-0.5 F60000\nG28.140 S0 ; cali pre-extrude z pos\n\nM141 S[overall_chamber_temperature]\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} A\n\n;===== mech mode sweep start =====\n    M1002 gcode_claim_action : 3\n\n    G90\n    G1 Z5 F1200\n    G1 X187 Y160 F20000\n    T1000\n    M400 P200\n\n    M970.3 Q1 A5 K0 O1\n    M974 Q1 S2 P0\n\n    M970.3 Q0 A5 K0 O1\n    M974 Q0 S2 P0\n\n    M970.2 Q2 K0 W38 Z0.01\n    M974 Q2 S2 P0\n    M500\n\n    M975 S1\n;===== mech mode sweep end =====\n\nM400\n;M73 P99\n\nG150.3 ; move to garbage can to wait for temp\nM1026\nG29.9\n\n;===== xy ofst cali start =====\n\nM1002 judge_flag auto_cali_toolhead_offset_flag\n\nM622 J0\n    M1012.5 N1 R1\n    M500\nM623\n\nM622 J1\n    M1002 gcode_claim_action : 39\n    M141 S0\n    M620.17 T0 S{nozzle_temperature_initial_layer[(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])]} L{(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])}\n    M620.17 T1 S{nozzle_temperature_initial_layer[(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])]} L{(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])}\n    G383 O1 T{nozzle_temperature_initial_layer[initial_no_support_extruder]} L{initial_no_support_extruder}\n    M500\n    M141 S[overall_chamber_temperature]\nM623\n\nM622 J2\n    M1002 gcode_claim_action : 39\n    M141 S0\n    M620.17 T0 S{nozzle_temperature_initial_layer[(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])]} L{(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])}\n    M620.17 T1 S{nozzle_temperature_initial_layer[(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])]} L{(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])}\n    G383.3 T{nozzle_temperature_initial_layer[initial_no_support_extruder]} L{initial_no_support_extruder}\n    M500\n    M141 S[overall_chamber_temperature]\nM623\n;===== xy ofst cali end =====\n\nM400\n;M73 P99\n\nM1002 gcode_claim_action : 0\nM400\n\n;============switch again==================\n\nM211 X0 Y0 Z0 ;turn off soft endstop\nG91\nG1 Z6 F1200\nG90\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM620 S[initial_no_support_extruder]A\nM400\nT[initial_no_support_extruder]\nM400\nM628 S0\nM629\nM400\nM621 S[initial_no_support_extruder]A\n\n;============switch again==================\n\nM400\n;M73 P99\n\n;===== wait temperature reaching the reference value =======\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} ; rise to print tmpr\n\nM140 S[bed_temperature_initial_layer_single] \nM190 S[bed_temperature_initial_layer_single] \n\n    ;========turn off light and fans =============\n    M960 S1 P0 ; turn off laser\n    M960 S2 P0 ; turn off laser\n    M106 S0 ; turn off fan\n    M106 P2 S0 ; turn off big fan\n    ;==== set ext toodhead cooling fan ==== \n    {if (min_vitrification_temperature <= 50)}\n    M106 P9 S255\n    {endif}\n    ;============set motor current==================\n    M400 S1\n\n;===== wait temperature reaching the reference value =======\n\nM400\n;M73 P99\n\n;===== for Textured PEI Plate , lower the nozzle as the nozzle was touching topmost of the texture when homing ==\n    {if curr_bed_type==\"Textured PEI Plate\"}\n        {if nozzle_diameter[initial_no_support_extruder] == 0.2}\n            G29.1 Z{-0.01} ; for Textured PEI Plate\n        {else}\n            G29.1 Z{-0.02} ; for Textured PEI Plate\n        {endif}\n    {else}\n        {if nozzle_diameter[initial_no_support_extruder] == 0.2}\n            G29.1 Z{0.01} ; for Textured PEI Plate\n        {endif}\n    {endif}\n    \nG150.1\n\nM975 S1 ; turn on mech mode supression\nM983.4 S1 ; turn on deformation compensation \nG29.2 S1 ; turn on pos comp\nG29.7 S1\n\nG90\nG1 Z5 F1200\nG1 Y295 F30000\nG1 Y265 F18000\n\n;===== nozzle load line ===============================\n    G29.2 S1 ; ensure z comp turn on\n    G90\n    M83\n    G1 Z5 F1200\n    G1 X270 Y-0.5 F60000\n    G28.14 R0\n    G29.2 S0\n    G91\n    G1 Z0.8 F1200\n    G90\n    G1 X250 F60000\n    M109 S{nozzle_temperature_initial_layer[initial_no_support_extruder]}\n    M83\n{if (filament_type[initial_no_support_extruder] == \"TPU\")}\n    G1 E5 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n{endif}\n    G1 E5 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    G1 X290 E10 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    G91\n    G3 Z0.4 I1.217 J0 P1 F60000\n    G90\n    M83\n    G29.2 S1 ; ensure z comp turn on\n;===== noozle load line end ===========================\n\nM400\n;M73 P99\n\nM993 A1 B1 C1 ; nozzle cam detection allowed.\n\n{if (filament_type[initial_no_support_extruder] == \"TPU\")}\nM1015.3 S1;enable tpu clog detect\n{else}\nM1015.3 S0;disable tpu clog detect\n{endif}\n\n{if (filament_type[initial_no_support_extruder] == \"PLA\") ||  (filament_type[initial_no_support_extruder] == \"PETG\")\n ||  (filament_type[initial_no_support_extruder] == \"PLA-CF\")  ||  (filament_type[initial_no_support_extruder] == \"PETG-CF\")}\nM1015.4 S1 K1 H[nozzle_diameter] ;enable E air printing detect\n{else}\nM1015.4 S0 K0 H[nozzle_diameter] ;disable E air printing detect\n{endif}\n\nM620.6 I[initial_no_support_extruder] W1 ;enable ams air printing detect\n\nM211 Z1\nG29.99\n\n\n",
+    "machine_switch_extruder_time": "5.6",
+    "machine_unload_filament_time": "30",
+    "master_extruder_id": "2",
+    "max_bridge_length": "0",
+    "max_layer_height": [
+        "0.28",
+        "0.28"
+    ],
+    "max_travel_detour_distance": "0",
+    "min_bead_width": "85%",
+    "min_feature_size": "25%",
+    "min_layer_height": [
+        "0.08",
+        "0.08"
+    ],
+    "minimum_sparse_infill_area": "15",
+    "mmu_segmented_region_interlocking_depth": "0",
+    "mmu_segmented_region_max_width": "0",
+    "name": "project_settings",
+    "no_slow_down_for_cooling_on_outwalls": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "nozzle_diameter": [
+        "0.4",
+        "0.4"
+    ],
+    "nozzle_flush_dataset": [
+        "1",
+        "2",
+        "1",
+        "2",
+        "2"
+    ],
+    "nozzle_height": "4",
+    "nozzle_temperature": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_initial_layer": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_range_high": [
+        "240",
+        "240",
+        "240",
+        "240"
+    ],
+    "nozzle_temperature_range_low": [
+        "190",
+        "190",
+        "190",
+        "190"
+    ],
+    "nozzle_type": [
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel"
+    ],
+    "nozzle_volume": [
+        "130",
+        "133",
+        "145",
+        "148",
+        "148"
+    ],
+    "nozzle_volume_type": [
+        "Standard",
+        "Standard"
+    ],
+    "only_one_wall_first_layer": "1",
+    "ooze_prevention": "0",
+    "other_layers_print_sequence": [
+        "0"
+    ],
+    "other_layers_print_sequence_nums": "0",
+    "outer_wall_acceleration": [
+        "2000",
+        "2000",
+        "2000",
+        "2000",
+        "2000"
+    ],
+    "outer_wall_jerk": "9",
+    "outer_wall_line_width": "0.42",
+    "outer_wall_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "overhang_1_4_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "overhang_2_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "overhang_3_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "overhang_fan_speed": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "overhang_fan_threshold": [
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "overhang_threshold_participating_cooling": [
+        "95%",
+        "95%",
+        "95%",
+        "95%"
+    ],
+    "overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "override_filament_scarf_seam_setting": "0",
+    "override_process_overhang_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "physical_extruder_map": [
+        "1",
+        "0"
+    ],
+    "post_process": [],
+    "pre_start_fan_time": [
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "precise_outer_wall": "0",
+    "precise_z_height": "0",
+    "pressure_advance": [
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02"
+    ],
+    "prime_tower_brim_width": "-1",
+    "prime_tower_enable_framework": "0",
+    "prime_tower_extra_rib_length": "0",
+    "prime_tower_fillet_wall": "1",
+    "prime_tower_flat_ironing": "1",
+    "prime_tower_infill_gap": "150%",
+    "prime_tower_lift_height": "-1",
+    "prime_tower_lift_speed": "90",
+    "prime_tower_max_speed": "90",
+    "prime_tower_rib_wall": "0",
+    "prime_tower_rib_width": "8",
+    "prime_tower_skip_points": "1",
+    "prime_tower_width": "230",
+    "prime_volume_mode": "Default",
+    "print_compatible_printers": [
+        "Bambu Lab H2C 0.4 nozzle"
+    ],
+    "print_extruder_id": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "2"
+    ],
+    "print_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive TPU High Flow"
+    ],
+    "print_flow_ratio": "1",
+    "print_sequence": "by layer",
+    "print_settings_id": "Bambu_Lumina",
+    "printable_area": [
+        "0x0",
+        "350x0",
+        "350x320",
+        "0x320"
+    ],
+    "printable_height": "325",
+    "printer_extruder_id": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "2"
+    ],
+    "printer_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive TPU High Flow"
+    ],
+    "printer_model": "Bambu Lab H2C",
+    "printer_notes": "",
+    "printer_settings_id": "Bambu Lab H2C 0.4 nozzle",
+    "printer_structure": "corexy",
+    "printer_technology": "FFF",
+    "printer_variant": "0.4",
+    "printhost_authorization_type": "key",
+    "printhost_ssl_ignore_revoke": "0",
+    "printing_by_object_gcode": "",
+    "process_notes": "",
+    "raft_contact_distance": "0.1",
+    "raft_expansion": "1.5",
+    "raft_first_layer_density": "90%",
+    "raft_first_layer_expansion": "-1",
+    "raft_layers": "0",
+    "reduce_crossing_wall": "0",
+    "reduce_fan_stop_start_freq": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "reduce_infill_retraction": "1",
+    "required_nozzle_HRC": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "resolution": "0.012",
+    "retract_before_wipe": [
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "retract_length_toolchange": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "retract_lift_above": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_lift_below": [
+        "319",
+        "319",
+        "319",
+        "319",
+        "319"
+    ],
+    "retract_restart_extra": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_restart_extra_toolchange": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_when_changing_layer": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "retraction_distances_when_cut": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "retraction_distances_when_ec": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "retraction_length": [
+        "0.8",
+        "0.8",
+        "0.8",
+        "0.8",
+        "0.8"
+    ],
+    "retraction_minimum_travel": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "retraction_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "role_base_wipe_speed": "1",
+    "scan_first_layer": "0",
+    "scarf_angle_threshold": "155",
+    "seam_gap": "15%",
+    "seam_placement_away_from_overhangs": "0",
+    "seam_position": "aligned",
+    "seam_slope_conditional": "1",
+    "seam_slope_entire_loop": "0",
+    "seam_slope_gap": "0",
+    "seam_slope_inner_walls": "1",
+    "seam_slope_min_length": "10",
+    "seam_slope_start_height": "10%",
+    "seam_slope_steps": "10",
+    "seam_slope_type": "none",
+    "silent_mode": "0",
+    "single_extruder_multi_material": "1",
+    "skeleton_infill_density": "100%",
+    "skeleton_infill_line_width": "0.42",
+    "skin_infill_density": "100%",
+    "skin_infill_depth": "2",
+    "skin_infill_line_width": "0.42",
+    "skirt_distance": "2",
+    "skirt_height": "1",
+    "skirt_loops": "0",
+    "slice_closing_radius": "0.049",
+    "slicing_mode": "regular",
+    "slow_down_for_layer_cooling": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "slow_down_layer_time": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "slow_down_min_speed": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "slowdown_end_acc": [
+        "100000",
+        "100000",
+        "100000",
+        "100000",
+        "100000"
+    ],
+    "slowdown_end_height": [
+        "400",
+        "400",
+        "400",
+        "400",
+        "400"
+    ],
+    "slowdown_end_speed": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "slowdown_start_acc": [
+        "100000",
+        "100000",
+        "100000",
+        "100000",
+        "100000"
+    ],
+    "slowdown_start_height": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "slowdown_start_speed": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "small_perimeter_speed": [
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "small_perimeter_threshold": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "smooth_coefficient": "4",
+    "smooth_speed_discontinuity_area": "1",
+    "solid_infill_filament": "0",
+    "sparse_infill_acceleration": [
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "sparse_infill_anchor": "400%",
+    "sparse_infill_anchor_max": "20",
+    "sparse_infill_density": "100%",
+    "sparse_infill_filament": "0",
+    "sparse_infill_lattice_angle_1": "-45",
+    "sparse_infill_lattice_angle_2": "45",
+    "sparse_infill_line_width": "0.42",
+    "sparse_infill_pattern": "zig-zag",
+    "sparse_infill_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "spiral_mode": "0",
+    "spiral_mode_max_xy_smoothing": "200%",
+    "spiral_mode_smooth": "0",
+    "standby_temperature_delta": "-5",
+    "start_end_points": [
+        "30x-3",
+        "54x245"
+    ],
+    "supertack_plate_temp": [
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "supertack_plate_temp_initial_layer": [
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "support_air_filtration": "0",
+    "support_angle": "0",
+    "support_base_pattern": "default",
+    "support_base_pattern_spacing": "2.5",
+    "support_bottom_interface_spacing": "0.5",
+    "support_bottom_z_distance": "0.08",
+    "support_chamber_temp_control": "1",
+    "support_cooling_filter": "1",
+    "support_critical_regions_only": "0",
+    "support_expansion": "0",
+    "support_filament": "0",
+    "support_interface_bottom_layers": "2",
+    "support_interface_filament": "0",
+    "support_interface_loop_pattern": "0",
+    "support_interface_not_for_body": "1",
+    "support_interface_pattern": "auto",
+    "support_interface_spacing": "0.5",
+    "support_interface_speed": [
+        "80",
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "support_interface_top_layers": "2",
+    "support_ironing_direction": "0",
+    "support_ironing_flow": "10%",
+    "support_ironing_inset": "0",
+    "support_ironing_pattern": "zig-zag",
+    "support_ironing_spacing": "0.15",
+    "support_ironing_speed": "30",
+    "support_line_width": "0.42",
+    "support_object_first_layer_gap": "0.2",
+    "support_object_skip_flush": "0",
+    "support_object_xy_distance": "0.35",
+    "support_on_build_plate_only": "0",
+    "support_remove_small_overhang": "1",
+    "support_speed": [
+        "150",
+        "150",
+        "150",
+        "150",
+        "150"
+    ],
+    "support_style": "default",
+    "support_threshold_angle": "15",
+    "support_top_z_distance": "0.08",
+    "support_type": "tree(auto)",
+    "symmetric_infill_y_axis": "0",
+    "temperature_vitrification": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "template_custom_gcode": "",
+    "textured_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "textured_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "thick_bridges": "0",
+    "thumbnail_size": [
+        "50x50"
+    ],
+    "time_lapse_gcode": ";======== H2D 20251104========\n; SKIPPABLE_START\n; SKIPTYPE: timelapse\nM622.1 S1 ; for prev firmware, default turned on\n\nM1002 judge_flag timelapse_record_flag\n\n    M622 J1\n    M993 A2 B2 C2\n    M993 A0 B0 C0\n    \n    M622.1 S0 ; for prev firmware, default turn off\n    M1002 set_flag smooth_safe_pos_suppoprt_flag=1\n    M1002 judge_flag smooth_safe_pos_suppoprt_flag\n    \n    M622 J0\n        {if !spiral_mode && !(has_timelapse_safe_pos && timelapse_type == 0) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                M83\n                G1 Z{max_layer_z + 0.4} F1200\n                M400\n            {endif}\n        {endif}\n\n        {if has_timelapse_safe_pos && timelapse_type == 0 && !spiral_mode}\n            M9711 M{timelapse_type} E{most_used_physical_extruder_id} X{timelapse_pos_x} Y{timelapse_pos_y} Z{layer_z + 0.4} S11 C10 O0 T3000\n        {else}\n            {if spiral_mode}\n                M971 S11 C10 O0\n                M1004 S5 P1  ; external shutter\n            {else}\n                M9711 M{timelapse_type} E{most_used_physical_extruder_id} Z{layer_z + 0.4} S11 C10 O0 T3000\n            {endif}\n        {endif}\n\n        {if !spiral_mode && !(has_timelapse_safe_pos && timelapse_type == 0) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                G90\n                G1 Z{max_layer_z + 3.0} F1200\n                G1 Y295 F30000\n                G1 Y265 F18000\n                M83\n            {endif}\n        {endif}\n    M623\n\n    M622 J1\n        {if !spiral_mode && !(has_timelapse_safe_pos) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                M83\n                G1 Z{max_layer_z + 0.4} F1200\n                M400\n            {endif}\n        {endif}\n\n        {if has_timelapse_safe_pos && !spiral_mode}\n            M9711 M{timelapse_type} E{most_used_physical_extruder_id} U{timelapse_pos_x} V{timelapse_pos_y} Z{layer_z + 0.4} S11 C10 O0 T3000\n        {else}\n            {if spiral_mode}\n                M971 S11 C10 O0\n                M1004 S5 P1  ; external shutter\n            {else}\n                M9711 M{timelapse_type} E{most_used_physical_extruder_id} Z{layer_z + 0.4} S11 C10 O0 T3000\n            {endif}\n        {endif}\n\n        {if !spiral_mode && !(has_timelapse_safe_pos) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                G90\n                G1 Z{max_layer_z + 3.0} F1200\n                G1 Y295 F30000\n                G1 Y265 F18000\n                M83\n            {endif}\n        {endif}\n    M623\n\n    M993 A3 B3 C3\n\nM623\n; SKIPPABLE_END\n",
+    "timelapse_type": "0",
+    "top_area_threshold": "200%",
+    "top_color_penetration_layers": "9",
+    "top_one_wall_type": "all top",
+    "top_shell_layers": "0",
+    "top_shell_thickness": "1",
+    "top_solid_infill_flow_ratio": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "top_surface_acceleration": [
+        "2000",
+        "2000",
+        "2000",
+        "2000",
+        "2000"
+    ],
+    "top_surface_density": "100%",
+    "top_surface_jerk": "9",
+    "top_surface_line_width": "0.42",
+    "top_surface_pattern": "zig-zag",
+    "top_surface_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "top_z_overrides_xy_distance": "0",
+    "travel_acceleration": [
+        "10000",
+        "10000",
+        "10000",
+        "10000",
+        "10000"
+    ],
+    "travel_jerk": "9",
+    "travel_short_distance_acceleration": [
+        "250",
+        "250",
+        "250",
+        "250",
+        "250"
+    ],
+    "travel_speed": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "travel_speed_z": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "tree_support_branch_angle": "45",
+    "tree_support_branch_diameter": "2",
+    "tree_support_branch_diameter_angle": "5",
+    "tree_support_branch_distance": "5",
+    "tree_support_wall_count": "-1",
+    "upward_compatible_machine": [
+        "Bambu Lab H2D Pro 0.4 nozzle"
+    ],
+    "use_firmware_retraction": "0",
+    "use_relative_e_distances": "1",
+    "version": "02.05.00.66",
+    "vertical_shell_speed": [
+        "80%",
+        "80%",
+        "80%",
+        "80%",
+        "80%"
+    ],
+    "volumetric_speed_coefficients": [
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0"
+    ],
+    "wall_distribution_count": "1",
+    "wall_filament": "0",
+    "wall_generator": "arachne",
+    "wall_loops": "1",
+    "wall_sequence": "inner wall/outer wall",
+    "wall_transition_angle": "10",
+    "wall_transition_filter_deviation": "25%",
+    "wall_transition_length": "100%",
+    "wipe": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "wipe_distance": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "wipe_speed": "80%",
+    "wipe_tower_no_sparse_layers": "0",
+    "wipe_tower_rotation_angle": "0",
+    "wipe_tower_x": [
+        "80"
+    ],
+    "wipe_tower_y": [
+        "250"
+    ],
+    "wrapping_detection_gcode": ";======== H2D 20250729 clumping ========\n{if !spiral_mode}\n    M622.1 S0 ; for previous firmware, default turn off\n    M1002 set_flag g39_forced_detection_flag=1\n    M1002 judge_flag g39_forced_detection_flag\n    M622 J1\n        {if layer_num == 3 || layer_num == 10 || layer_num == 19}\n            M993 A2 B2 C2 ; nozzle cam detection allow status save.\n            M993 A0 B0 C0 ; nozzle cam detection not allowed.\n\n            M400 P100\n\n            G39\n\n            G90\n            G1 Y295 F30000\n            G1 Y265 F18000\n            \n            M993 A3 B3 C3 ; nozzle cam detection allow status restore.\n        {endif}\n    M623\n{endif}\n",
+    "wrapping_detection_layers": "20",
+    "wrapping_exclude_area": [
+        "145x310",
+        "256x310",
+        "256x326",
+        "145x326"
+    ],
+    "xy_contour_compensation": "0",
+    "xy_hole_compensation": "0",
+    "z_direction_outwall_speed_continuous": "1",
+    "z_hop": [
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4"
+    ],
+    "z_hop_types": [
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift"
+    ]
+}
\ No newline at end of file
diff --git a/printer_profiles/bambu_h2d.json b/printer_profiles/bambu_h2d.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_h2d.json
@@ -0,0 +1,2118 @@
+{
+    "accel_to_decel_enable": "0",
+    "accel_to_decel_factor": "50%",
+    "activate_air_filtration": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "additional_cooling_fan_speed": [
+        "75",
+        "75",
+        "75",
+        "75"
+    ],
+    "apply_scarf_seam_on_circles": "1",
+    "apply_top_surface_compensation": "0",
+    "auxiliary_fan": "1",
+    "avoid_crossing_wall_includes_support": "0",
+    "bed_custom_model": "",
+    "bed_custom_texture": "",
+    "bed_exclude_area": [],
+    "bed_temperature_formula": "by_highest_temp",
+    "before_layer_change_gcode": "",
+    "best_object_pos": "0.3,0.5",
+    "bottom_color_penetration_layers": "7",
+    "bottom_shell_layers": "0",
+    "bottom_shell_thickness": "0",
+    "bottom_surface_density": "100%",
+    "bottom_surface_pattern": "zig-zag",
+    "bridge_angle": "0",
+    "bridge_flow": "1",
+    "bridge_no_support": "0",
+    "bridge_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "brim_object_gap": "0.1",
+    "brim_type": "auto_brim",
+    "brim_width": "5",
+    "chamber_temperatures": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "change_filament_gcode": ";======== H2D ========\n;===== 20260116 =====\nM993 A2 B2 C2 ; nozzle cam detection allow status save.\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\n{if (filament_type[next_extruder] == \"PLA\") ||  (filament_type[next_extruder] == \"PETG\")\n ||  (filament_type[next_extruder] == \"PLA-CF\")  ||  (filament_type[next_extruder] == \"PETG-CF\")}\nM1015.4 S1 K0 ;disable E air printing detect\n{else}\nM1015.4 S0 ; disable E air printing detect\n{endif}\n\nM620 S[next_extruder]A\nM1002 gcode_claim_action : 4\nM204 S9000\n\nG1 Z{max_layer_z + 3.0} F1200\n\nM400\nM106 P1 S0\nM106 P2 S0\n\n{if toolchange_count == 2}\n; get travel path for change filament\n;M620.1 X[travel_point_1_x] Y[travel_point_1_y] F21000 P0\n;M620.1 X[travel_point_2_x] Y[travel_point_2_y] F21000 P1\n;M620.1 X[travel_point_3_x] Y[travel_point_3_y] F21000 P2\n{endif}\n\n{if ((filament_type[current_extruder] == \"PLA\") || (filament_type[current_extruder] == \"PLA-CF\") || (filament_type[current_extruder] == \"PETG\")) && (nozzle_diameter[current_extruder] == 0.2)}\nM620.10 A0 F74.8347 L[flush_length] H{nozzle_diameter[current_extruder]} T{flush_temperatures[current_extruder]} P[old_filament_temp] S1\n{else}\nM620.10 A0 F{flush_volumetric_speeds[current_extruder]/2.4053*60*0.8} L[flush_length] H{nozzle_diameter[current_extruder]} T{flush_temperatures[current_extruder]} P[old_filament_temp] S1\n{endif}\n\n{if ((filament_type[next_extruder] == \"PLA\") || (filament_type[next_extruder] == \"PLA-CF\") || (filament_type[next_extruder] == \"PETG\")) && (nozzle_diameter[next_extruder] == 0.2)}\nM620.10 A1 F74.8347 L[flush_length] H{nozzle_diameter[next_extruder]} T{flush_temperatures[next_extruder]} P[new_filament_temp] S1\n{else}\nM620.10 A1 F{flush_volumetric_speeds[next_extruder]/2.4053*60*0.8} L[flush_length] H{nozzle_diameter[next_extruder]} T{flush_temperatures[next_extruder]} P[new_filament_temp] S1\n{endif}\n\n{if long_retraction_when_cut}\nM620.11 P1 I[current_extruder] E-{retraction_distance_when_cut} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 P0 I[current_extruder] E0\n{endif}\n\n{if long_retraction_when_ec}\nM620.11 K1 I[current_extruder] R{retraction_distance_when_ec} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 K0 I[current_extruder] R0\n{endif}\n\nM620.15 C{new_filament_temp - filament_cooling_before_tower[next_extruder]}\n\nM628 S1\n{if filament_type[current_extruder] == \"TPU\"}\nM620.11 S0 L0 I[current_extruder] E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\n{if (filament_type[current_extruder] == \"PA\") || (filament_type[current_extruder] == \"PA-GF\")}\nM620.11 S1 L0 I[current_extruder] R4 D2 E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 S1 L0 I[current_extruder] R10 D8 E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{endif}\n{endif}\nM629\n\n{if (filament_type[current_extruder] == \"TPU\" || filament_type[next_extruder] == \"TPU\") && (old_extruder_variant != \"Direct Drive TPU High Flow\")}\nM620.11 H2 C331\n{else}\nM620.11 H0\n{endif}\n\n{if  (old_extruder_variant == \"Direct Drive TPU High Flow\") && (filament_map[current_extruder] == 2) && (filament_map[next_extruder] == 1)}\n;debug log pe:{previous_extruder} ce:{current_extruder} ne:{next_extruder} oev: {old_extruder_variant} nev:{new_extruder_variant}\n;debug fm-curr:{filament_map[current_extruder]} fm-next:{filament_map[next_extruder]}\n;sw from R2L&TPU kit, travel run a distance for sketch TPU\nG1 X30 Y30 F5000\nM400\nG1 X300 Y30 F5000\nM400\n{endif}\n\nT[next_extruder]\n\n;deretract\n{if filament_type[next_extruder] == \"TPU\"}\n{else}\n{if (filament_type[next_extruder] == \"PA\") || (filament_type[next_extruder] == \"PA-GF\")}\n;VG1 E1 F{max(new_filament_e_feedrate, 200)}\n;VG1 E1 F{max(new_filament_e_feedrate/2, 100)}\n{else}\n;VG1 E4 F{max(new_filament_e_feedrate, 200)}\n;VG1 E4 F{max(new_filament_e_feedrate/2, 100)}\n{endif}\n{endif}\n\n; VFLUSH_START\n\n{if flush_length>41.5}\n;VG1 E41.5 F{min(old_filament_e_feedrate,new_filament_e_feedrate)}\n;VG1 E{flush_length-41.5} F{new_filament_e_feedrate}\n{else}\n;VG1 E{flush_length} F{min(old_filament_e_feedrate,new_filament_e_feedrate)}\n{endif}\n\nSYNC T{ceil(flush_length / 125) * 5}\n\n; VFLUSH_END\n\nM1002 set_filament_type:{filament_type[next_extruder]}\n\nM400\nM83\n{if next_extruder < 255}\n\nM620.10 R{new_extruder_retracted_length}\nM628 S0\n;VM109 S[new_filament_temp]\nM629\nM400\n\n;prime_tower_interface\n{if is_prime_tower_interface && filament_tower_interface_purge_volume !=0}\nG150.1\nM620.13 W0 L{filament_tower_interface_purge_volume} T{filament_tower_interface_print_temp} R0.0\n{endif}\n;prime_tower_interface\n\nM983.3 F{filament_max_volumetric_speed[next_extruder]/2.4} A0.4 R{new_extruder_retracted_length}\n\nM400\n{if wipe_avoid_perimeter}\nG1 Y320 F30000\nG1 X{wipe_avoid_pos_x} F30000\n{endif}\nG1 Y295 F30000\nG1 Y265 F18000\nG1 Z{max_layer_z + 3.0} F3000\n{if layer_z <= (initial_layer_print_height + 0.001)}\nM204 S[initial_layer_acceleration]\n{else}\nM204 S[default_acceleration]\n{endif}\n{else}\nG1 X[x_after_toolchange] Y[y_after_toolchange] Z[z_after_toolchange] F12000\n{endif}\nM621 S[next_extruder]A\n\nM993 A3 B3 C3 ; nozzle cam detection allow status restore.\n\n{if (filament_type[next_extruder]  == \"TPU\")}\nM1015.3 S1;enable tpu clog detect\n{else}\nM1015.3 S0;disable tpu clog detect\n{endif}\n\n{if (filament_type[next_extruder] == \"PLA\") ||  (filament_type[next_extruder] == \"PETG\")\n ||  (filament_type[next_extruder] == \"PLA-CF\")  ||  (filament_type[next_extruder] == \"PETG-CF\")}\nM1015.4 S1 K1 H[nozzle_diameter] ;enable E air printing detect\n{else}\nM1015.4 S0 ; disable E air printing detect\n{endif}\n\nM620.6 I[next_extruder] W1 ;enable ams air printing detect\nM1002 gcode_claim_action : 0",
+    "circle_compensation_manual_offset": "0",
+    "circle_compensation_speed": [
+        "200",
+        "200",
+        "200",
+        "200"
+    ],
+    "close_fan_the_first_x_layers": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "complete_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "cool_plate_temp": [
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cool_plate_temp_initial_layer": [
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cooling_filter_enabled": "0",
+    "cooling_perimeter_transition_distance": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "cooling_slowdown_logic": [
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling"
+    ],
+    "counter_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "counter_coef_2": [
+        "0.003",
+        "0.003",
+        "0.003",
+        "0.003"
+    ],
+    "counter_coef_3": [
+        "0.01",
+        "0.01",
+        "0.01",
+        "0.01"
+    ],
+    "counter_limit_max": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "counter_limit_min": [
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035"
+    ],
+    "curr_bed_type": "Textured PEI Plate",
+    "default_acceleration": [
+        "4000",
+        "4000",
+        "4000",
+        "4000",
+        "4000"
+    ],
+    "default_filament_colour": [
+        "",
+        "",
+        "",
+        ""
+    ],
+    "default_filament_profile": [
+        "Bambu PLA Basic @BBL H2D"
+    ],
+    "default_jerk": "0",
+    "default_nozzle_volume_type": [
+        "Standard",
+        "Standard"
+    ],
+    "default_print_profile": "0.20mm Standard @BBL H2D",
+    "deretraction_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "detect_floating_vertical_shell": "1",
+    "detect_narrow_internal_solid_infill": "0",
+    "detect_overhang_wall": "1",
+    "detect_thin_wall": "0",
+    "diameter_limit": [
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "different_settings_to_system": [
+        "bottom_shell_layers;bottom_surface_pattern;detect_narrow_internal_solid_infill;infill_direction;initial_layer_line_width;initial_layer_print_height;inner_wall_line_width;only_one_wall_first_layer;prime_tower_rib_wall;prime_tower_width;skeleton_infill_density;skeleton_infill_line_width;skin_infill_density;skin_infill_line_width;sparse_infill_density;sparse_infill_line_width;sparse_infill_pattern;top_shell_layers;top_surface_pattern;wall_generator;wall_loops",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "draft_shield": "disabled",
+    "during_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "elefant_foot_compensation": "0.15",
+    "embedding_wall_into_infill": "0",
+    "enable_arc_fitting": "1",
+    "enable_circle_compensation": "0",
+    "enable_height_slowdown": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_long_retraction_when_cut": "2",
+    "enable_overhang_bridge_fan": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_pre_heating": "1",
+    "enable_pressure_advance": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_prime_tower": "1",
+    "enable_support": "0",
+    "enable_support_ironing": "0",
+    "enable_tower_interface_features": "1",
+    "enable_wrapping_detection": "0",
+    "enforce_support_layers": "0",
+    "eng_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "eng_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "ensure_vertical_shell_thickness": "enabled",
+    "exclude_object": "1",
+    "extruder_ams_count": [
+        "1#0|4#0",
+        "1#0|4#0"
+    ],
+    "extruder_clearance_dist_to_rod": "50",
+    "extruder_clearance_height_to_lid": "201",
+    "extruder_clearance_height_to_rod": "47.4",
+    "extruder_clearance_max_radius": "96",
+    "extruder_colour": [
+        "#018001",
+        "#018001"
+    ],
+    "extruder_max_nozzle_count": [
+        "1",
+        "1"
+    ],
+    "extruder_nozzle_stats": [
+        "Standard#1",
+        "Standard#1"
+    ],
+    "extruder_offset": [
+        "0x0",
+        "0x0"
+    ],
+    "extruder_printable_area": [
+        "0x0,325x0,325x320,0x320",
+        "25x0,350x0,350x320,25x320"
+    ],
+    "extruder_printable_height": [
+        "320",
+        "325"
+    ],
+    "extruder_type": [
+        "Direct Drive",
+        "Direct Drive"
+    ],
+    "extruder_variant_list": [
+        "Direct Drive Standard,Direct Drive High Flow",
+        "Direct Drive Standard,Direct Drive High Flow,Direct Drive TPU High Flow"
+    ],
+    "fan_cooling_layer_time": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "fan_direction": "left",
+    "fan_max_speed": [
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "fan_min_speed": [
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_adaptive_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_adhesiveness_category": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_bridge_speed": [
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25"
+    ],
+    "filament_change_length": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_change_length_nc": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_colour": [
+        "#FFFFFF",
+        "#C12E1F",
+        "#F4EE2A",
+        "#0000FF"
+    ],
+    "filament_colour_type": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_cooling_before_tower": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_cost": [
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99"
+    ],
+    "filament_density": [
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26"
+    ],
+    "filament_deretraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_dev_ams_drying_ams_limitations": [
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0"
+    ],
+    "filament_dev_ams_drying_heat_distortion_temperature": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_chamber_drying_bed_temperature": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "filament_dev_chamber_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_drying_cooling_temperature": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_drying_softening_temperature": [
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_diameter": [
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75"
+    ],
+    "filament_enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_end_gcode": [
+        "; filament end gcode \n",
+        "; filament end gcode \n",
+        "; filament end gcode \n",
+        "; filament end gcode \n"
+    ],
+    "filament_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "filament_flow_ratio": [
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98"
+    ],
+    "filament_flush_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_flush_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ids": [
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00"
+    ],
+    "filament_is_support": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_long_retractions_when_cut": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_map": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map_mode": "Auto For Flush",
+    "filament_max_volumetric_speed": [
+        "25",
+        "40",
+        "25",
+        "40",
+        "25",
+        "40",
+        "25",
+        "40"
+    ],
+    "filament_minimal_purge_on_wipe_tower": [
+        "15",
+        "15",
+        "15",
+        "15"
+    ],
+    "filament_multi_colour": [
+        "#FFFFFF",
+        "#C12E1F",
+        "#F4EE2A",
+        "#0000FF"
+    ],
+    "filament_notes": "",
+    "filament_nozzle_map": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_1_4_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_2_4_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_overhang_3_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_pre_cooling_temperature": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_pre_cooling_temperature_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_prime_volume": [
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_prime_volume_nc": [
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_printable": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "filament_ramming_travel_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_travel_time_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_volumetric_speed": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_ramming_volumetric_speed_nc": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_retract_before_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_length_nc": [
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14"
+    ],
+    "filament_retract_restart_extra": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_when_changing_layer": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_distances_when_cut": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_length": [
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4"
+    ],
+    "filament_retraction_minimum_travel": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_scarf_gap": [
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "filament_scarf_height": [
+        "10%",
+        "10%",
+        "10%",
+        "10%"
+    ],
+    "filament_scarf_length": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_scarf_seam_type": [
+        "none",
+        "none",
+        "none",
+        "none"
+    ],
+    "filament_self_index": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "3",
+        "3",
+        "4",
+        "4"
+    ],
+    "filament_settings_id": [
+        "Bambu PLA Basic @BBL H2D",
+        "Bambu PLA Basic @BBL H2D",
+        "Bambu PLA Basic @BBL H2D",
+        "Bambu PLA Basic @BBL H2D"
+    ],
+    "filament_shrink": [
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "filament_soluble": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_start_gcode": [
+        "; filament start gcode\n",
+        "; filament start gcode\n",
+        "; filament start gcode\n",
+        "; filament start gcode\n"
+    ],
+    "filament_tower_interface_pre_extrusion_dist": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_tower_interface_pre_extrusion_length": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_tower_interface_print_temp": [
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_tower_interface_purge_volume": [
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "filament_tower_ironing_area": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_type": [
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA"
+    ],
+    "filament_velocity_adaptation_factor": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_vendor": [
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab"
+    ],
+    "filament_volume_map": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_wipe": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_wipe_distance": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_z_hop": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop_types": [
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift"
+    ],
+    "filename_format": "{input_filename_base}_{filament_type[0]}_{print_time}.gcode",
+    "fill_multiline": "1",
+    "filter_out_gap_fill": "0",
+    "first_layer_print_sequence": [
+        "0"
+    ],
+    "first_x_layer_fan_speed": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "flush_into_infill": "0",
+    "flush_into_objects": "0",
+    "flush_into_support": "1",
+    "flush_multiplier": [
+        "1",
+        "1"
+    ],
+    "flush_volumes_matrix": [
+        "0",
+        "90",
+        "90",
+        "402",
+        "900",
+        "0",
+        "450",
+        "351",
+        "900",
+        "180",
+        "0",
+        "391",
+        "791",
+        "547",
+        "770",
+        "0",
+        "0",
+        "90",
+        "90",
+        "417",
+        "900",
+        "0",
+        "450",
+        "366",
+        "900",
+        "180",
+        "0",
+        "406",
+        "806",
+        "562",
+        "785",
+        "0"
+    ],
+    "flush_volumes_vector": [
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140"
+    ],
+    "from": "project",
+    "full_fan_speed_layer": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "fuzzy_skin": "none",
+    "fuzzy_skin_point_distance": "0.8",
+    "fuzzy_skin_thickness": "0.3",
+    "gap_infill_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "gcode_add_line_number": "0",
+    "gcode_flavor": "marlin",
+    "grab_length": [
+        "0",
+        "0"
+    ],
+    "group_algo_with_time": "0",
+    "has_scarf_joint_seam": "0",
+    "head_wrap_detect_zone": [],
+    "hole_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "hole_coef_2": [
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008"
+    ],
+    "hole_coef_3": [
+        "0.18",
+        "0.18",
+        "0.18",
+        "0.18"
+    ],
+    "hole_limit_max": [
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22"
+    ],
+    "hole_limit_min": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "host_type": "octoprint",
+    "hot_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hot_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hotend_cooling_rate": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "hotend_heating_rate": [
+        "3.6",
+        "3.6",
+        "3.6",
+        "3.6",
+        "3.6"
+    ],
+    "impact_strength_z": [
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8"
+    ],
+    "independent_support_layer_height": "1",
+    "infill_combination": "0",
+    "infill_direction": "0",
+    "infill_instead_top_bottom_surfaces": "0",
+    "infill_jerk": "9",
+    "infill_lock_depth": "1",
+    "infill_rotate_step": "0",
+    "infill_shift_step": "0.4",
+    "infill_wall_overlap": "15%",
+    "inherits_group": [
+        "0.08mm Extra Fine @BBL H2D",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "initial_layer_acceleration": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "initial_layer_flow_ratio": "1",
+    "initial_layer_infill_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "initial_layer_jerk": "9",
+    "initial_layer_line_width": "0.42",
+    "initial_layer_print_height": "0.08",
+    "initial_layer_speed": [
+        "40",
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "initial_layer_travel_acceleration": [
+        "6000",
+        "6000",
+        "6000",
+        "6000",
+        "6000"
+    ],
+    "inner_wall_acceleration": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "inner_wall_jerk": "9",
+    "inner_wall_line_width": "0.42",
+    "inner_wall_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "interface_shells": "0",
+    "interlocking_beam": "0",
+    "interlocking_beam_layer_count": "2",
+    "interlocking_beam_width": "0.8",
+    "interlocking_boundary_avoidance": "2",
+    "interlocking_depth": "2",
+    "interlocking_orientation": "22.5",
+    "internal_bridge_support_thickness": "0.8",
+    "internal_solid_infill_line_width": "0.42",
+    "internal_solid_infill_pattern": "zig-zag",
+    "internal_solid_infill_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "ironing_direction": "45",
+    "ironing_flow": "8%",
+    "ironing_inset": "0.21",
+    "ironing_pattern": "zig-zag",
+    "ironing_spacing": "0.15",
+    "ironing_speed": "30",
+    "ironing_type": "no ironing",
+    "is_infill_first": "0",
+    "layer_change_gcode": ";======== H2D 20250710 layer_change ========\n; layer num/total_layer_count: {layer_num+1}/[total_layer_count]\n; update layer progress\nM73 L{layer_num+1}\nM991 S0 P{layer_num} ;notify layer change\n",
+    "layer_height": "0.08",
+    "line_width": "0.42",
+    "locked_skeleton_infill_pattern": "zigzag",
+    "locked_skin_infill_pattern": "crosszag",
+    "long_retractions_when_cut": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "long_retractions_when_ec": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "machine_end_gcode": ";========== H2D end ==========\n;===== date: 2025/12/26 =====\n\nG392 S0 ;turn off nozzle clog detect\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\nM400 ; wait for buffer to clear\nG92 E0 ; zero the extruder\nG1 E-0.8 F1800 ; retract\nM400\nM211 Z1\nG1 Z{max_layer_z + 0.4} F900 ; lower z a little\n\nM1002 judge_flag timelapse_record_flag\nM622 J1\n    G150.3\n    M400 ; wait all motion done\n    M991 S0 P-1 ;end smooth timelapse at safe pos\n    M400 S5 ;wait for last picture to be taken\nM623  ;end of \"timelapse_record_flag\"\n\nG90\nG1 Z{max_layer_z + 10} F900 ; lower z a little\n\nG90\nM141 S0 ; turn off chamber heating\nM140 S0 ; turn off bed\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off remote part cooling fan\nM106 P3 S0 ; turn off chamber cooling fan\nM106 P9 S0 ; turn off ext toodhead cooling fan\n; pull back filament to AMS\nM620 S65535\nT65535\nG150.2\nM621 S65535\n\nM620 S65279\nT65279\nG150.2\nM621 S65279\n\nG150.3\n\nM104 S0 T0; turn off hotend\nM104 S0 T1; turn off hotend\n\nM400 ; wait all motion done\nM17 S\nM17 Z0.4 ; lower z motor current to reduce impact if there is something in the bottom\n{if (100.0 - max_layer_z/2) > 0}\n    {if (max_layer_z + 100.0 - max_layer_z/2) < 320}\n        G1 Z{max_layer_z + 100.0 - max_layer_z/2} F600\n        G1 Z{max_layer_z + 98.0 - max_layer_z/2}\n    {else}\n        G1 Z320 F600\n        G1 Z320\n    {endif}\n{else}\n    {if (max_layer_z + 4.0) < 320}\n        G1 Z{max_layer_z + 4.0} F600\n        G1 Z{max_layer_z + 2.0}\n    {else}\n        G1 Z320 F600\n        G1 Z320\n    {endif}\n{endif}\nM400 P100\nM17 R ; restore z current\n\nM220 S100  ; Reset feedrate magnitude\nM201.2 K1.0 ; Reset acc magnitude\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 0\n\nM1015.4 S0 K0 ;disable air printing detect\n\n;=====printer finish air purification=========\nM622.1 S0\nM1002 judge_flag print_finish_air_filt_flag\n\nM622 J1\nM1002 gcode_claim_action : 66\nM145 P1\nM106 P6 S255\nM400 S180\nM106 P6 S0\nM623\n\nM622 J2\nM1002 gcode_claim_action : 66\nM145 P0\nM106 P3 S127\nM400 S180\nM106 P3 S0\nM623\n;=====printer finish air purification=========\n\n\n;=====printer finish  sound=========\nM17\nM400 S1\nM1006 S1\nM1006 A53 B10 L99 C53 D10 M99 E53 F10 N99 \nM1006 A57 B10 L99 C57 D10 M99 E57 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A53 B10 L99 C53 D10 M99 E53 F10 N99 \nM1006 A57 B10 L99 C57 D10 M99 E57 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A48 B10 L99 C48 D10 M99 E48 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A60 B10 L99 C60 D10 M99 E60 F10 N99 \nM1006 W\n;=====printer finish  sound=========\nM400\nM18\n\n",
+    "machine_hotend_change_time": "0",
+    "machine_load_filament_time": "30",
+    "machine_max_acceleration_e": [
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_extruding": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_retracting": [
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_travel": [
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000"
+    ],
+    "machine_max_acceleration_x": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_y": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_z": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_jerk_e": [
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5"
+    ],
+    "machine_max_jerk_x": [
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_y": [
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_z": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "machine_max_speed_e": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "machine_max_speed_x": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "machine_max_speed_y": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "machine_max_speed_z": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "machine_min_extruding_rate": [
+        "0",
+        "0"
+    ],
+    "machine_min_travel_rate": [
+        "0",
+        "0"
+    ],
+    "machine_pause_gcode": "M400 U1",
+    "machine_prepare_compensation_time": "260",
+    "machine_start_gcode": ";===== machine: H2D =========================\n;===== date: 20260116 =====================\n\n;M1002 set_flag extrude_cali_flag=1\n;M1002 set_flag g29_before_print_flag=1\n;M1002 set_flag auto_cali_toolhead_offset_flag=1\n;M1002 set_flag build_plate_detect_flag=1\n\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\nM400\n;M73 P99\n\nM960 S10 P1 ; ext fan led\n\n;=====printer start sound ===================\nM17\nM400 S1\nM1006 S1\nM1006 A53 B9 L99 C53 D9 M99 E53 F9 N99 \nM1006 A56 B9 L99 C56 D9 M99 E56 F9 N99 \nM1006 A61 B9 L99 C61 D9 M99 E61 F9 N99 \nM1006 A53 B9 L99 C53 D9 M99 E53 F9 N99 \nM1006 A56 B9 L99 C56 D9 M99 E56 F9 N99 \nM1006 A61 B18 L99 C61 D18 M99 E61 F18 N99 \nM1006 W\n;=====printer start sound ===================\n\n;===== reset machine status =================\nM204 S10000\nM630 S0 P0\n\nG90\nM17 D ; reset motor current to default\nM960 S5 P1 ; turn on logo lamp\nG90\nM1002 set_gcode_claim_speed_level 5 ;Reset speed level\nM220 S100 ;Reset Feedrate\nM221 S100 ;Reset Flowrate\nM73.2   R1.0 ;Reset left time magnitude\nG29.1 Z{+0.0} ; clear z-trim value first\nM983.1 M1 \nM901 D4\nM481 S0 ; turn off cutter pos comp\nG28.140 D0; reset pre-extrude z pos\n;===== reset machine status =================\n\nM620 M ;enable remap\n\n;===== avoid end stop =================\nG91\nG380 S2 Z42 F1200\nG380 S2 Z-12 F1200\nG90\n;===== avoid end stop =================\n\n;==== set airduct mode ==== \n\n{if (overall_chamber_temperature >= 40)}\n\n    M145 P1 ; set airduct mode to heating mode for heating\n    M106 P2 S0 ; turn off auxiliary fan\n    M106 P3 S0 ; turn off chamber fan\n\n{else}\n    M145 P0 ; set airduct mode to cooling mode for cooling\n    M106 P2 S178 ; turn on auxiliary fan for cooling\n    M106 P3 S127 ; turn on chamber fan for cooling\n    M140 S0 ; stop heatbed from heating\n\n    M1002 gcode_claim_action : 29\n    M191 S0 ; wait for chamber temp\n    M106 P2 S0 ; turn off auxiliary fan\n    {if (min_vitrification_temperature <= 50)}\n        {if (nozzle_diameter == 0.2)}\n            M142 P1 R30 S35 T40 U0.3 V0.5 W0.8 O40 ; set PLA/TPU ND0.2 chamber autocooling\n        {else}\n            M142 P1 R30 S40 T45 U0.3 V0.5 W0.8 O45; set PLA/TPU ND0.4 chamber autocooling\n        {endif}\n    {else}\n        {if (!is_all_bbl_filament)}\n            M142 P1 R35 S40 T45 U0.3 V0.5 W0.8 O45 L1 ; set third-party PETG chamber autocooling\n        {else}\n            {if (nozzle_diameter == 0.2)}\n                M142 P1 R35 S45 T50 U0.3 V0.5 W0.8 O50 L1 ; set PETG ND0.2 chamber autocooling\n            {else}\n                M142 P1 R35 S50 T55 U0.3 V0.5 W0.8 O55 L1 ; set PETG ND0.4 chamber autocooling\n            {endif}\n        {endif}\n    {endif}\n    {if(cooling_filter_enabled)}\n        M145.2 P0 F0\n    {else}\n        M145.2 P0 F1\n    {endif}\n{endif}\n;==== set airduct mode ==== \n\n;===== start to heat heatbed & hotend==========\n\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n\n    M104 S140 A\n    M140 S[bed_temperature_initial_layer_single]\n\n    ;===== set chamber temperature ==========\n    {if (overall_chamber_temperature >= 40)}\n        M145 P1 ; set airduct mode to heating mode\n        M141 S[overall_chamber_temperature] ; Let Chamber begin to heat\n    {endif}\n    ;===== set chamber temperature ==========\n\n;===== start to heat heatbead & hotend==========\n\n;====== cog noise reduction=================\nM982.2 S1 ; turn on cog noise reduction\n\n;===== first homing start =====\nM1002 gcode_claim_action : 13\n\nG28 X T300\n\nG150.1 F18000 ; wipe mouth to avoid filament stick to heatbed\nG150.3 F18000\nM400 P200\nM972 S24 P0 T2000\n\nM1002 gcode_claim_action : 74 ; Heatbed surface foreign object detection\n{if curr_bed_type==\"Textured PEI Plate\"}\nM972 S26 P0 C0\n{else}\nM972 S36 P0 C0 X1\n{endif}\nM972 S35 P0 C0\n\nM972 S41 P0 T5000 ; trash can anti-collision\n\nM1009 Q1 L1\nG91\nG380 S2 Z30 F1200 ; lower heatbed to move toolhead\nG90\nG1 X175 Y160 F30000\nG28 Z P0 T250\nM1009 Q1 L0\n\n;===== first homing end =====\n\nM400\n;M73 P99\n\n;===== detection start =====\n    \nM1002 judge_flag build_plate_detect_flag\nM622 S1\n    ;M1002 gcode_claim_action : 11 ; Indentifying build plate type\n    M972 S19 P0 C0    ; heatbed presence detection\n    M972 S31 P0 T5000 ; toolhead camera dirty detection\n    ;M1002 gcode_claim_action : 73 ; Build plate alignment detection\n    M972 S34 P0 T5000 ; heatbed plate offset detection\nM623\n\nM1002 gcode_claim_action : 72 ; Hotend Type Detection\nT1001\nM972 S14 P0 T5000 ; nozzle type detection\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} T{filament_map[initial_no_support_extruder] % 2} ; rise temp in advance\n\nG151 P{filament_map[initial_no_support_extruder] % 2} M ; plug the heat nozzle\n\n{if max_print_z >= 145}\nM1002 gcode_claim_action : 75 ; Heatbed underside foreign object detection\nG3811 Z{max_print_z}  ; Detect obstacles at the bottom of the heated bed\n{endif}\n\n;===== detection end =====\n\nM400\n;M73 P99\n\n;===== prepare print temperature and material ==========\nM400\nM211 X0 Y0 Z0 ;turn off soft endstop\nM975 S1 ; turn on input shaping\n\nG29.2 S0 ; avoid invalid abl data\n\n{if ((filament_type[initial_no_support_extruder] == \"PLA\") || (filament_type[initial_no_support_extruder] == \"PLA-CF\") || (filament_type[initial_no_support_extruder] == \"PETG\")) && (nozzle_diameter[initial_no_support_extruder] == 0.2)}\nM620.10 A0 F74.8347 H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\nM620.10 A1 F74.8347 H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\n{else}\nM620.10 A0 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60*0.8} H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\nM620.10 A1 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60*0.8} H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\n{endif}\n\nM620.11 P0 I[initial_no_support_extruder] E0\n\n{if long_retraction_when_ec }\nM620.11 K1 I[initial_no_support_extruder] R{retraction_distance_when_ec} F{max((flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60), 200)}\n{else}\nM620.11 K0 I[initial_no_support_extruder] R0\n{endif}\n\nM628 S1\n{if filament_type[initial_no_support_extruder] == \"TPU\"}\n    M620.11 S0 L0 I[initial_no_support_extruder] E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{else}\n{if (filament_type[initial_no_support_extruder] == \"PA\") ||  (filament_type[initial_no_support_extruder] == \"PA-GF\")}\n    M620.11 S1 L0 I[initial_no_support_extruder] R4 D2 E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{else}\n    M620.11 S1 L0 I[initial_no_support_extruder] R10 D8 E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{endif}\n{endif}\nM629\n\nM620 S[initial_no_support_extruder]A   ; switch material if AMS exist\nM1002 gcode_claim_action : 4\nM1002 set_filament_type:UNKNOWN\nM400\nT[initial_no_support_extruder]\nM400\nM628 S0\nM629\nM400\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM621 S[initial_no_support_extruder]A\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]}\nM400\nM106 P1 S0\n\nG29.2 S1\n;===== prepare print temperature and material ==========\n\nM400\n;M73 P99\n\n;===== auto extrude cali start =========================\nM975 S1\nM1002 judge_flag extrude_cali_flag\n\nM622 J0\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\nM623\n\nM622 J1\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M1002 gcode_claim_action : 8\n\n    M109 S{nozzle_temperature[initial_no_support_extruder]}\n\n    G90\n    M83\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\n\n    M400\n    M106 P1 S255\n    M400 S5\n    M106 P1 S0\n    G150.3\nM623\n\nM622 J2\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M1002 gcode_claim_action : 8\n\n    M109 S{nozzle_temperature[initial_no_support_extruder]}\n\n    G90\n    M83\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\n\n    M400\n    M106 P1 S255\n    M400 S5\n    M106 P1 S0\n    G150.3\nM623\n\n;===== auto extrude cali end =========================\n\n{if filament_type[initial_no_support_extruder] == \"TPU\"}\n    G150.2\n    G150.1\n    G150.2\n    G150.1\n    G150.2\n    G150.1\n{else}\n    M106 P1 S0\n    M400 S2\n    M109 S{nozzle_temperature[initial_no_support_extruder]} ; wait tmpr to extrude\n    M83\n    {if(nozzle_diameter == 0.8)}\n        G1 E60 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    {else}\n        G1 E45 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    {endif}\n    G1 E-3 F1800\n    M400 P500\n    G150.2\n    G150.1\n{endif}\n\nG91\nG1 Y-16 F12000 ; move away from the trash bin\nG90\n\nM400\n;M73 P99\n\n;===== wipe right nozzle start =====\n\nM1002 gcode_claim_action : 14\n    G150 T{nozzle_temperature_initial_layer[initial_no_support_extruder]}\n    {if (overall_chamber_temperature >= 40)}\n        G150 T{nozzle_temperature_initial_layer[initial_no_support_extruder] - 80}\n    {endif}\nM106 S255 ; turn on fan to cool the nozzle\n\n;===== wipe left nozzle end =====\n\nM400\n;M73 P99\n\n{if (overall_chamber_temperature >= 40)}\n    M1002 gcode_claim_action : 49\n    M191 S[overall_chamber_temperature] ; wait for chamber temp\n{endif}\n\nM400\n;M73 P99\n\n;===== bed leveling ==================================\n\nM1002 judge_flag g29_before_print_flag\n\nM190 S[bed_temperature_initial_layer_single]; ensure bed temp\nM109 S140 A\nM106 S0 ; turn off fan , too noisy\n\nG91\nG1 Z5 F1200\nG90\nG1 X175 Y160 F30000\n\nM622 J1\n    M1002 gcode_claim_action : 1\n    G29.20 A3\n    G29 A1 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R \n    M400\n    M500 ; save cali data\nM623\n    \nM622 J2\n    M1002 gcode_claim_action : 1\n    {if has_tpu_in_first_layer}\n        G29.20 A3\n        G29 A1 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R\n    {else}\n        G29.20 A4\n        G29 A2 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R\n    {endif}\n    M400\n    M500 ; save cali data\nM623\n\nM622 J0\n    G28 R\nM623\n\n;===== bed leveling end ================================\n\n;===== z ofst cali start =====\n\n    M190 S[bed_temperature_initial_layer_single]; ensure bed temp\n\n    G383 O0 M2 T140\n    M500\n\n;===== z ofst cali end =====\n\nG39.1 ; cali nozzle wrapped detection pos\nM500\n\nG90\nG1 Z5 F1200\nG1 X270 Y-0.5 F60000\nG28.140 S0 ; cali pre-extrude z pos\n\nM141 S[overall_chamber_temperature]\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} A\n\n;===== mech mode sweep start =====\n    M1002 gcode_claim_action : 3\n\n    G90\n    G1 Z5 F1200\n    G1 X187 Y160 F20000\n    T1000\n    M400 P200\n\n    M970.3 Q1 A5 K0 O1\n    M974 Q1 S2 P0\n\n    M970.3 Q0 A5 K0 O1\n    M974 Q0 S2 P0\n\n    M970.2 Q2 K0 W38 Z0.01\n    M974 Q2 S2 P0\n    M500\n\n    M975 S1\n;===== mech mode sweep end =====\n\nM400\n;M73 P99\n\nG150.3 ; move to garbage can to wait for temp\nM1026\nG29.9\n\n;===== xy ofst cali start =====\n\nM1002 judge_flag auto_cali_toolhead_offset_flag\n\nM622 J0\n    M1012.5 N1 R1\n    M500\nM623\n\nM622 J1\n    M1002 gcode_claim_action : 39\n    M141 S0\n    M620.17 T0 S{nozzle_temperature_initial_layer[(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])]} L{(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])}\n    M620.17 T1 S{nozzle_temperature_initial_layer[(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])]} L{(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])}\n    G383 O1 T{nozzle_temperature_initial_layer[initial_no_support_extruder]} L{initial_no_support_extruder}\n    M500\n    M141 S[overall_chamber_temperature]\nM623\n\nM622 J2\n    M1002 gcode_claim_action : 39\n    M141 S0\n    M620.17 T0 S{nozzle_temperature_initial_layer[(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])]} L{(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])}\n    M620.17 T1 S{nozzle_temperature_initial_layer[(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])]} L{(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])}\n    G383.3 T{nozzle_temperature_initial_layer[initial_no_support_extruder]} L{initial_no_support_extruder}\n    M500\n    M141 S[overall_chamber_temperature]\nM623\n;===== xy ofst cali end =====\n\nM400\n;M73 P99\n\nM1002 gcode_claim_action : 0\nM400\n\n;============switch again==================\n\nM211 X0 Y0 Z0 ;turn off soft endstop\nG91\nG1 Z6 F1200\nG90\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM620 S[initial_no_support_extruder]A\nM400\nT[initial_no_support_extruder]\nM400\nM628 S0\nM629\nM400\nM621 S[initial_no_support_extruder]A\n\n;============switch again==================\n\nM400\n;M73 P99\n\n;===== wait temperature reaching the reference value =======\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} ; rise to print tmpr\n\nM140 S[bed_temperature_initial_layer_single] \nM190 S[bed_temperature_initial_layer_single] \n\n    ;========turn off light and fans =============\n    M960 S1 P0 ; turn off laser\n    M960 S2 P0 ; turn off laser\n    M106 S0 ; turn off fan\n    M106 P2 S0 ; turn off big fan\n    ;==== set ext toodhead cooling fan ==== \n    {if (min_vitrification_temperature <= 50)}\n    M106 P9 S255\n    {endif}\n    ;============set motor current==================\n    M400 S1\n\n;===== wait temperature reaching the reference value =======\n\nM400\n;M73 P99\n\n;===== for Textured PEI Plate , lower the nozzle as the nozzle was touching topmost of the texture when homing ==\n    {if curr_bed_type==\"Textured PEI Plate\"}\n        {if nozzle_diameter[initial_no_support_extruder] == 0.2}\n            G29.1 Z{-0.01} ; for Textured PEI Plate\n        {else}\n            G29.1 Z{-0.02} ; for Textured PEI Plate\n        {endif}\n    {else}\n        {if nozzle_diameter[initial_no_support_extruder] == 0.2}\n            G29.1 Z{0.01} ; for Textured PEI Plate\n        {endif}\n    {endif}\n    \nG150.1\n\nM975 S1 ; turn on mech mode supression\nM983.4 S1 ; turn on deformation compensation \nG29.2 S1 ; turn on pos comp\nG29.7 S1\n\nG90\nG1 Z5 F1200\nG1 Y295 F30000\nG1 Y265 F18000\n\n;===== nozzle load line ===============================\n    G29.2 S1 ; ensure z comp turn on\n    G90\n    M83\n    G1 Z5 F1200\n    G1 X270 Y-0.5 F60000\n    G28.14 R0\n    G29.2 S0\n    G91\n    G1 Z0.8 F1200\n    G90\n    G1 X250 F60000\n    M109 S{nozzle_temperature_initial_layer[initial_no_support_extruder]}\n    M83\n{if (filament_type[initial_no_support_extruder] == \"TPU\")}\n    G1 E5 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n{endif}\n    G1 E5 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    G1 X290 E10 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    G91\n    G3 Z0.4 I1.217 J0 P1 F60000\n    G90\n    M83\n    G29.2 S1 ; ensure z comp turn on\n;===== noozle load line end ===========================\n\nM400\n;M73 P99\n\nM993 A1 B1 C1 ; nozzle cam detection allowed.\n\n{if (filament_type[initial_no_support_extruder] == \"TPU\")}\nM1015.3 S1;enable tpu clog detect\n{else}\nM1015.3 S0;disable tpu clog detect\n{endif}\n\n{if (filament_type[initial_no_support_extruder] == \"PLA\") ||  (filament_type[initial_no_support_extruder] == \"PETG\")\n ||  (filament_type[initial_no_support_extruder] == \"PLA-CF\")  ||  (filament_type[initial_no_support_extruder] == \"PETG-CF\")}\nM1015.4 S1 K1 H[nozzle_diameter] ;enable E air printing detect\n{else}\nM1015.4 S0 K0 H[nozzle_diameter] ;disable E air printing detect\n{endif}\n\nM620.6 I[initial_no_support_extruder] W1 ;enable ams air printing detect\n\nM211 Z1\nG29.99\n\n\n",
+    "machine_switch_extruder_time": "5.6",
+    "machine_unload_filament_time": "30",
+    "master_extruder_id": "2",
+    "max_bridge_length": "0",
+    "max_layer_height": [
+        "0.28",
+        "0.28"
+    ],
+    "max_travel_detour_distance": "0",
+    "min_bead_width": "85%",
+    "min_feature_size": "25%",
+    "min_layer_height": [
+        "0.08",
+        "0.08"
+    ],
+    "minimum_sparse_infill_area": "15",
+    "mmu_segmented_region_interlocking_depth": "0",
+    "mmu_segmented_region_max_width": "0",
+    "name": "project_settings",
+    "no_slow_down_for_cooling_on_outwalls": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "nozzle_diameter": [
+        "0.4",
+        "0.4"
+    ],
+    "nozzle_flush_dataset": [
+        "1",
+        "2",
+        "1",
+        "2",
+        "2"
+    ],
+    "nozzle_height": "4",
+    "nozzle_temperature": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_initial_layer": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_range_high": [
+        "240",
+        "240",
+        "240",
+        "240"
+    ],
+    "nozzle_temperature_range_low": [
+        "190",
+        "190",
+        "190",
+        "190"
+    ],
+    "nozzle_type": [
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel"
+    ],
+    "nozzle_volume": [
+        "130",
+        "133",
+        "145",
+        "148",
+        "148"
+    ],
+    "nozzle_volume_type": [
+        "Standard",
+        "Standard"
+    ],
+    "only_one_wall_first_layer": "1",
+    "ooze_prevention": "0",
+    "other_layers_print_sequence": [
+        "0"
+    ],
+    "other_layers_print_sequence_nums": "0",
+    "outer_wall_acceleration": [
+        "2000",
+        "2000",
+        "2000",
+        "2000",
+        "2000"
+    ],
+    "outer_wall_jerk": "9",
+    "outer_wall_line_width": "0.42",
+    "outer_wall_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "overhang_1_4_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "overhang_2_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "overhang_3_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "overhang_fan_speed": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "overhang_fan_threshold": [
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "overhang_threshold_participating_cooling": [
+        "95%",
+        "95%",
+        "95%",
+        "95%"
+    ],
+    "overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "override_filament_scarf_seam_setting": "0",
+    "override_process_overhang_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "physical_extruder_map": [
+        "1",
+        "0"
+    ],
+    "post_process": [],
+    "pre_start_fan_time": [
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "precise_outer_wall": "0",
+    "precise_z_height": "0",
+    "pressure_advance": [
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02"
+    ],
+    "prime_tower_brim_width": "-1",
+    "prime_tower_enable_framework": "0",
+    "prime_tower_extra_rib_length": "0",
+    "prime_tower_fillet_wall": "1",
+    "prime_tower_flat_ironing": "1",
+    "prime_tower_infill_gap": "150%",
+    "prime_tower_lift_height": "-1",
+    "prime_tower_lift_speed": "90",
+    "prime_tower_max_speed": "90",
+    "prime_tower_rib_wall": "0",
+    "prime_tower_rib_width": "8",
+    "prime_tower_skip_points": "1",
+    "prime_tower_width": "230",
+    "prime_volume_mode": "Default",
+    "print_compatible_printers": [
+        "Bambu Lab H2D 0.4 nozzle"
+    ],
+    "print_extruder_id": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "2"
+    ],
+    "print_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive TPU High Flow"
+    ],
+    "print_flow_ratio": "1",
+    "print_sequence": "by layer",
+    "print_settings_id": "Bambu_Lumina",
+    "printable_area": [
+        "0x0",
+        "350x0",
+        "350x320",
+        "0x320"
+    ],
+    "printable_height": "325",
+    "printer_extruder_id": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "2"
+    ],
+    "printer_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive TPU High Flow"
+    ],
+    "printer_model": "Bambu Lab H2D",
+    "printer_notes": "",
+    "printer_settings_id": "Bambu Lab H2D 0.4 nozzle",
+    "printer_structure": "corexy",
+    "printer_technology": "FFF",
+    "printer_variant": "0.4",
+    "printhost_authorization_type": "key",
+    "printhost_ssl_ignore_revoke": "0",
+    "printing_by_object_gcode": "",
+    "process_notes": "",
+    "raft_contact_distance": "0.1",
+    "raft_expansion": "1.5",
+    "raft_first_layer_density": "90%",
+    "raft_first_layer_expansion": "-1",
+    "raft_layers": "0",
+    "reduce_crossing_wall": "0",
+    "reduce_fan_stop_start_freq": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "reduce_infill_retraction": "1",
+    "required_nozzle_HRC": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "resolution": "0.012",
+    "retract_before_wipe": [
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "retract_length_toolchange": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "retract_lift_above": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_lift_below": [
+        "319",
+        "319",
+        "319",
+        "319",
+        "319"
+    ],
+    "retract_restart_extra": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_restart_extra_toolchange": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_when_changing_layer": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "retraction_distances_when_cut": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "retraction_distances_when_ec": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "retraction_length": [
+        "0.8",
+        "0.8",
+        "0.8",
+        "0.8",
+        "0.8"
+    ],
+    "retraction_minimum_travel": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "retraction_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "role_base_wipe_speed": "1",
+    "scan_first_layer": "0",
+    "scarf_angle_threshold": "155",
+    "seam_gap": "15%",
+    "seam_placement_away_from_overhangs": "0",
+    "seam_position": "aligned",
+    "seam_slope_conditional": "1",
+    "seam_slope_entire_loop": "0",
+    "seam_slope_gap": "0",
+    "seam_slope_inner_walls": "1",
+    "seam_slope_min_length": "10",
+    "seam_slope_start_height": "10%",
+    "seam_slope_steps": "10",
+    "seam_slope_type": "none",
+    "silent_mode": "0",
+    "single_extruder_multi_material": "1",
+    "skeleton_infill_density": "100%",
+    "skeleton_infill_line_width": "0.42",
+    "skin_infill_density": "100%",
+    "skin_infill_depth": "2",
+    "skin_infill_line_width": "0.42",
+    "skirt_distance": "2",
+    "skirt_height": "1",
+    "skirt_loops": "0",
+    "slice_closing_radius": "0.049",
+    "slicing_mode": "regular",
+    "slow_down_for_layer_cooling": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "slow_down_layer_time": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "slow_down_min_speed": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "slowdown_end_acc": [
+        "100000",
+        "100000",
+        "100000",
+        "100000",
+        "100000"
+    ],
+    "slowdown_end_height": [
+        "400",
+        "400",
+        "400",
+        "400",
+        "400"
+    ],
+    "slowdown_end_speed": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "slowdown_start_acc": [
+        "100000",
+        "100000",
+        "100000",
+        "100000",
+        "100000"
+    ],
+    "slowdown_start_height": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "slowdown_start_speed": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "small_perimeter_speed": [
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "small_perimeter_threshold": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "smooth_coefficient": "4",
+    "smooth_speed_discontinuity_area": "1",
+    "solid_infill_filament": "0",
+    "sparse_infill_acceleration": [
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "sparse_infill_anchor": "400%",
+    "sparse_infill_anchor_max": "20",
+    "sparse_infill_density": "100%",
+    "sparse_infill_filament": "0",
+    "sparse_infill_lattice_angle_1": "-45",
+    "sparse_infill_lattice_angle_2": "45",
+    "sparse_infill_line_width": "0.42",
+    "sparse_infill_pattern": "zig-zag",
+    "sparse_infill_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "spiral_mode": "0",
+    "spiral_mode_max_xy_smoothing": "200%",
+    "spiral_mode_smooth": "0",
+    "standby_temperature_delta": "-5",
+    "start_end_points": [
+        "30x-3",
+        "54x245"
+    ],
+    "supertack_plate_temp": [
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "supertack_plate_temp_initial_layer": [
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "support_air_filtration": "0",
+    "support_angle": "0",
+    "support_base_pattern": "default",
+    "support_base_pattern_spacing": "2.5",
+    "support_bottom_interface_spacing": "0.5",
+    "support_bottom_z_distance": "0.08",
+    "support_chamber_temp_control": "1",
+    "support_cooling_filter": "1",
+    "support_critical_regions_only": "0",
+    "support_expansion": "0",
+    "support_filament": "0",
+    "support_interface_bottom_layers": "2",
+    "support_interface_filament": "0",
+    "support_interface_loop_pattern": "0",
+    "support_interface_not_for_body": "1",
+    "support_interface_pattern": "auto",
+    "support_interface_spacing": "0.5",
+    "support_interface_speed": [
+        "80",
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "support_interface_top_layers": "2",
+    "support_ironing_direction": "0",
+    "support_ironing_flow": "10%",
+    "support_ironing_inset": "0",
+    "support_ironing_pattern": "zig-zag",
+    "support_ironing_spacing": "0.15",
+    "support_ironing_speed": "30",
+    "support_line_width": "0.42",
+    "support_object_first_layer_gap": "0.2",
+    "support_object_skip_flush": "0",
+    "support_object_xy_distance": "0.35",
+    "support_on_build_plate_only": "0",
+    "support_remove_small_overhang": "1",
+    "support_speed": [
+        "150",
+        "150",
+        "150",
+        "150",
+        "150"
+    ],
+    "support_style": "default",
+    "support_threshold_angle": "15",
+    "support_top_z_distance": "0.08",
+    "support_type": "tree(auto)",
+    "symmetric_infill_y_axis": "0",
+    "temperature_vitrification": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "template_custom_gcode": "",
+    "textured_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "textured_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "thick_bridges": "0",
+    "thumbnail_size": [
+        "50x50"
+    ],
+    "time_lapse_gcode": ";======== H2D 20251104========\n; SKIPPABLE_START\n; SKIPTYPE: timelapse\nM622.1 S1 ; for prev firmware, default turned on\n\nM1002 judge_flag timelapse_record_flag\n\n    M622 J1\n    M993 A2 B2 C2\n    M993 A0 B0 C0\n    \n    M622.1 S0 ; for prev firmware, default turn off\n    M1002 set_flag smooth_safe_pos_suppoprt_flag=1\n    M1002 judge_flag smooth_safe_pos_suppoprt_flag\n    \n    M622 J0\n        {if !spiral_mode && !(has_timelapse_safe_pos && timelapse_type == 0) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                M83\n                G1 Z{max_layer_z + 0.4} F1200\n                M400\n            {endif}\n        {endif}\n\n        {if has_timelapse_safe_pos && timelapse_type == 0 && !spiral_mode}\n            M9711 M{timelapse_type} E{most_used_physical_extruder_id} X{timelapse_pos_x} Y{timelapse_pos_y} Z{layer_z + 0.4} S11 C10 O0 T3000\n        {else}\n            {if spiral_mode}\n                M971 S11 C10 O0\n                M1004 S5 P1  ; external shutter\n            {else}\n                M9711 M{timelapse_type} E{most_used_physical_extruder_id} Z{layer_z + 0.4} S11 C10 O0 T3000\n            {endif}\n        {endif}\n\n        {if !spiral_mode && !(has_timelapse_safe_pos && timelapse_type == 0) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                G90\n                G1 Z{max_layer_z + 3.0} F1200\n                G1 Y295 F30000\n                G1 Y265 F18000\n                M83\n            {endif}\n        {endif}\n    M623\n\n    M622 J1\n        {if !spiral_mode && !(has_timelapse_safe_pos) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                M83\n                G1 Z{max_layer_z + 0.4} F1200\n                M400\n            {endif}\n        {endif}\n\n        {if has_timelapse_safe_pos && !spiral_mode}\n            M9711 M{timelapse_type} E{most_used_physical_extruder_id} U{timelapse_pos_x} V{timelapse_pos_y} Z{layer_z + 0.4} S11 C10 O0 T3000\n        {else}\n            {if spiral_mode}\n                M971 S11 C10 O0\n                M1004 S5 P1  ; external shutter\n            {else}\n                M9711 M{timelapse_type} E{most_used_physical_extruder_id} Z{layer_z + 0.4} S11 C10 O0 T3000\n            {endif}\n        {endif}\n\n        {if !spiral_mode && !(has_timelapse_safe_pos) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                G90\n                G1 Z{max_layer_z + 3.0} F1200\n                G1 Y295 F30000\n                G1 Y265 F18000\n                M83\n            {endif}\n        {endif}\n    M623\n\n    M993 A3 B3 C3\n\nM623\n; SKIPPABLE_END\n",
+    "timelapse_type": "0",
+    "top_area_threshold": "200%",
+    "top_color_penetration_layers": "9",
+    "top_one_wall_type": "all top",
+    "top_shell_layers": "0",
+    "top_shell_thickness": "1",
+    "top_solid_infill_flow_ratio": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "top_surface_acceleration": [
+        "2000",
+        "2000",
+        "2000",
+        "2000",
+        "2000"
+    ],
+    "top_surface_density": "100%",
+    "top_surface_jerk": "9",
+    "top_surface_line_width": "0.42",
+    "top_surface_pattern": "zig-zag",
+    "top_surface_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "top_z_overrides_xy_distance": "0",
+    "travel_acceleration": [
+        "10000",
+        "10000",
+        "10000",
+        "10000",
+        "10000"
+    ],
+    "travel_jerk": "9",
+    "travel_short_distance_acceleration": [
+        "250",
+        "250",
+        "250",
+        "250",
+        "250"
+    ],
+    "travel_speed": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "travel_speed_z": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "tree_support_branch_angle": "45",
+    "tree_support_branch_diameter": "2",
+    "tree_support_branch_diameter_angle": "5",
+    "tree_support_branch_distance": "5",
+    "tree_support_wall_count": "-1",
+    "upward_compatible_machine": [
+        "Bambu Lab H2D Pro 0.4 nozzle"
+    ],
+    "use_firmware_retraction": "0",
+    "use_relative_e_distances": "1",
+    "version": "02.05.00.66",
+    "vertical_shell_speed": [
+        "80%",
+        "80%",
+        "80%",
+        "80%",
+        "80%"
+    ],
+    "volumetric_speed_coefficients": [
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0"
+    ],
+    "wall_distribution_count": "1",
+    "wall_filament": "0",
+    "wall_generator": "arachne",
+    "wall_loops": "1",
+    "wall_sequence": "inner wall/outer wall",
+    "wall_transition_angle": "10",
+    "wall_transition_filter_deviation": "25%",
+    "wall_transition_length": "100%",
+    "wipe": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "wipe_distance": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "wipe_speed": "80%",
+    "wipe_tower_no_sparse_layers": "0",
+    "wipe_tower_rotation_angle": "0",
+    "wipe_tower_x": [
+        "80"
+    ],
+    "wipe_tower_y": [
+        "250"
+    ],
+    "wrapping_detection_gcode": ";======== H2D 20250729 clumping ========\n{if !spiral_mode}\n    M622.1 S0 ; for previous firmware, default turn off\n    M1002 set_flag g39_forced_detection_flag=1\n    M1002 judge_flag g39_forced_detection_flag\n    M622 J1\n        {if layer_num == 3 || layer_num == 10 || layer_num == 19}\n            M993 A2 B2 C2 ; nozzle cam detection allow status save.\n            M993 A0 B0 C0 ; nozzle cam detection not allowed.\n\n            M400 P100\n\n            G39\n\n            G90\n            G1 Y295 F30000\n            G1 Y265 F18000\n            \n            M993 A3 B3 C3 ; nozzle cam detection allow status restore.\n        {endif}\n    M623\n{endif}\n",
+    "wrapping_detection_layers": "20",
+    "wrapping_exclude_area": [
+        "145x310",
+        "256x310",
+        "256x326",
+        "145x326"
+    ],
+    "xy_contour_compensation": "0",
+    "xy_hole_compensation": "0",
+    "z_direction_outwall_speed_continuous": "1",
+    "z_hop": [
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4"
+    ],
+    "z_hop_types": [
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift"
+    ]
+}
\ No newline at end of file
diff --git a/printer_profiles/bambu_h2d_pro.json b/printer_profiles/bambu_h2d_pro.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_h2d_pro.json
@@ -0,0 +1,2118 @@
+{
+    "accel_to_decel_enable": "0",
+    "accel_to_decel_factor": "50%",
+    "activate_air_filtration": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "additional_cooling_fan_speed": [
+        "75",
+        "75",
+        "75",
+        "75"
+    ],
+    "apply_scarf_seam_on_circles": "1",
+    "apply_top_surface_compensation": "0",
+    "auxiliary_fan": "1",
+    "avoid_crossing_wall_includes_support": "0",
+    "bed_custom_model": "",
+    "bed_custom_texture": "",
+    "bed_exclude_area": [],
+    "bed_temperature_formula": "by_highest_temp",
+    "before_layer_change_gcode": "",
+    "best_object_pos": "0.3,0.5",
+    "bottom_color_penetration_layers": "7",
+    "bottom_shell_layers": "0",
+    "bottom_shell_thickness": "0",
+    "bottom_surface_density": "100%",
+    "bottom_surface_pattern": "zig-zag",
+    "bridge_angle": "0",
+    "bridge_flow": "1",
+    "bridge_no_support": "0",
+    "bridge_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "brim_object_gap": "0.1",
+    "brim_type": "auto_brim",
+    "brim_width": "5",
+    "chamber_temperatures": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "change_filament_gcode": ";======== H2D ========\n;===== 20260116 =====\nM993 A2 B2 C2 ; nozzle cam detection allow status save.\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\n{if (filament_type[next_extruder] == \"PLA\") ||  (filament_type[next_extruder] == \"PETG\")\n ||  (filament_type[next_extruder] == \"PLA-CF\")  ||  (filament_type[next_extruder] == \"PETG-CF\")}\nM1015.4 S1 K0 ;disable E air printing detect\n{else}\nM1015.4 S0 ; disable E air printing detect\n{endif}\n\nM620 S[next_extruder]A\nM1002 gcode_claim_action : 4\nM204 S9000\n\nG1 Z{max_layer_z + 3.0} F1200\n\nM400\nM106 P1 S0\nM106 P2 S0\n\n{if toolchange_count == 2}\n; get travel path for change filament\n;M620.1 X[travel_point_1_x] Y[travel_point_1_y] F21000 P0\n;M620.1 X[travel_point_2_x] Y[travel_point_2_y] F21000 P1\n;M620.1 X[travel_point_3_x] Y[travel_point_3_y] F21000 P2\n{endif}\n\n{if ((filament_type[current_extruder] == \"PLA\") || (filament_type[current_extruder] == \"PLA-CF\") || (filament_type[current_extruder] == \"PETG\")) && (nozzle_diameter[current_extruder] == 0.2)}\nM620.10 A0 F74.8347 L[flush_length] H{nozzle_diameter[current_extruder]} T{flush_temperatures[current_extruder]} P[old_filament_temp] S1\n{else}\nM620.10 A0 F{flush_volumetric_speeds[current_extruder]/2.4053*60*0.8} L[flush_length] H{nozzle_diameter[current_extruder]} T{flush_temperatures[current_extruder]} P[old_filament_temp] S1\n{endif}\n\n{if ((filament_type[next_extruder] == \"PLA\") || (filament_type[next_extruder] == \"PLA-CF\") || (filament_type[next_extruder] == \"PETG\")) && (nozzle_diameter[next_extruder] == 0.2)}\nM620.10 A1 F74.8347 L[flush_length] H{nozzle_diameter[next_extruder]} T{flush_temperatures[next_extruder]} P[new_filament_temp] S1\n{else}\nM620.10 A1 F{flush_volumetric_speeds[next_extruder]/2.4053*60*0.8} L[flush_length] H{nozzle_diameter[next_extruder]} T{flush_temperatures[next_extruder]} P[new_filament_temp] S1\n{endif}\n\n{if long_retraction_when_cut}\nM620.11 P1 I[current_extruder] E-{retraction_distance_when_cut} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 P0 I[current_extruder] E0\n{endif}\n\n{if long_retraction_when_ec}\nM620.11 K1 I[current_extruder] R{retraction_distance_when_ec} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 K0 I[current_extruder] R0\n{endif}\n\nM620.15 C{new_filament_temp - filament_cooling_before_tower[next_extruder]}\n\nM628 S1\n{if filament_type[current_extruder] == \"TPU\"}\nM620.11 S0 L0 I[current_extruder] E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\n{if (filament_type[current_extruder] == \"PA\") || (filament_type[current_extruder] == \"PA-GF\")}\nM620.11 S1 L0 I[current_extruder] R4 D2 E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 S1 L0 I[current_extruder] R10 D8 E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{endif}\n{endif}\nM629\n\n{if (filament_type[current_extruder] == \"TPU\" || filament_type[next_extruder] == \"TPU\") && (old_extruder_variant != \"Direct Drive TPU High Flow\")}\nM620.11 H2 C331\n{else}\nM620.11 H0\n{endif}\n\n{if  (old_extruder_variant == \"Direct Drive TPU High Flow\") && (filament_map[current_extruder] == 2) && (filament_map[next_extruder] == 1)}\n;debug log pe:{previous_extruder} ce:{current_extruder} ne:{next_extruder} oev: {old_extruder_variant} nev:{new_extruder_variant}\n;debug fm-curr:{filament_map[current_extruder]} fm-next:{filament_map[next_extruder]}\n;sw from R2L&TPU kit, travel run a distance for sketch TPU\nG1 X30 Y30 F5000\nM400\nG1 X300 Y30 F5000\nM400\n{endif}\n\nT[next_extruder]\n\n;deretract\n{if filament_type[next_extruder] == \"TPU\"}\n{else}\n{if (filament_type[next_extruder] == \"PA\") || (filament_type[next_extruder] == \"PA-GF\")}\n;VG1 E1 F{max(new_filament_e_feedrate, 200)}\n;VG1 E1 F{max(new_filament_e_feedrate/2, 100)}\n{else}\n;VG1 E4 F{max(new_filament_e_feedrate, 200)}\n;VG1 E4 F{max(new_filament_e_feedrate/2, 100)}\n{endif}\n{endif}\n\n; VFLUSH_START\n\n{if flush_length>41.5}\n;VG1 E41.5 F{min(old_filament_e_feedrate,new_filament_e_feedrate)}\n;VG1 E{flush_length-41.5} F{new_filament_e_feedrate}\n{else}\n;VG1 E{flush_length} F{min(old_filament_e_feedrate,new_filament_e_feedrate)}\n{endif}\n\nSYNC T{ceil(flush_length / 125) * 5}\n\n; VFLUSH_END\n\nM1002 set_filament_type:{filament_type[next_extruder]}\n\nM400\nM83\n{if next_extruder < 255}\n\nM620.10 R{new_extruder_retracted_length}\nM628 S0\n;VM109 S[new_filament_temp]\nM629\nM400\n\n;prime_tower_interface\n{if is_prime_tower_interface && filament_tower_interface_purge_volume !=0}\nG150.1\nM620.13 W0 L{filament_tower_interface_purge_volume} T{filament_tower_interface_print_temp} R0.0\n{endif}\n;prime_tower_interface\n\nM983.3 F{filament_max_volumetric_speed[next_extruder]/2.4} A0.4 R{new_extruder_retracted_length}\n\nM400\n{if wipe_avoid_perimeter}\nG1 Y320 F30000\nG1 X{wipe_avoid_pos_x} F30000\n{endif}\nG1 Y295 F30000\nG1 Y265 F18000\nG1 Z{max_layer_z + 3.0} F3000\n{if layer_z <= (initial_layer_print_height + 0.001)}\nM204 S[initial_layer_acceleration]\n{else}\nM204 S[default_acceleration]\n{endif}\n{else}\nG1 X[x_after_toolchange] Y[y_after_toolchange] Z[z_after_toolchange] F12000\n{endif}\nM621 S[next_extruder]A\n\nM993 A3 B3 C3 ; nozzle cam detection allow status restore.\n\n{if (filament_type[next_extruder]  == \"TPU\")}\nM1015.3 S1;enable tpu clog detect\n{else}\nM1015.3 S0;disable tpu clog detect\n{endif}\n\n{if (filament_type[next_extruder] == \"PLA\") ||  (filament_type[next_extruder] == \"PETG\")\n ||  (filament_type[next_extruder] == \"PLA-CF\")  ||  (filament_type[next_extruder] == \"PETG-CF\")}\nM1015.4 S1 K1 H[nozzle_diameter] ;enable E air printing detect\n{else}\nM1015.4 S0 ; disable E air printing detect\n{endif}\n\nM620.6 I[next_extruder] W1 ;enable ams air printing detect\nM1002 gcode_claim_action : 0",
+    "circle_compensation_manual_offset": "0",
+    "circle_compensation_speed": [
+        "200",
+        "200",
+        "200",
+        "200"
+    ],
+    "close_fan_the_first_x_layers": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "complete_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "cool_plate_temp": [
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cool_plate_temp_initial_layer": [
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cooling_filter_enabled": "0",
+    "cooling_perimeter_transition_distance": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "cooling_slowdown_logic": [
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling"
+    ],
+    "counter_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "counter_coef_2": [
+        "0.003",
+        "0.003",
+        "0.003",
+        "0.003"
+    ],
+    "counter_coef_3": [
+        "0.01",
+        "0.01",
+        "0.01",
+        "0.01"
+    ],
+    "counter_limit_max": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "counter_limit_min": [
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035"
+    ],
+    "curr_bed_type": "Textured PEI Plate",
+    "default_acceleration": [
+        "4000",
+        "4000",
+        "4000",
+        "4000",
+        "4000"
+    ],
+    "default_filament_colour": [
+        "",
+        "",
+        "",
+        ""
+    ],
+    "default_filament_profile": [
+        "Bambu PLA Basic @BBL H2D Pro"
+    ],
+    "default_jerk": "0",
+    "default_nozzle_volume_type": [
+        "Standard",
+        "Standard"
+    ],
+    "default_print_profile": "0.20mm Standard @BBL H2D Pro",
+    "deretraction_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "detect_floating_vertical_shell": "1",
+    "detect_narrow_internal_solid_infill": "0",
+    "detect_overhang_wall": "1",
+    "detect_thin_wall": "0",
+    "diameter_limit": [
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "different_settings_to_system": [
+        "bottom_shell_layers;bottom_surface_pattern;detect_narrow_internal_solid_infill;infill_direction;initial_layer_line_width;initial_layer_print_height;inner_wall_line_width;only_one_wall_first_layer;prime_tower_rib_wall;prime_tower_width;skeleton_infill_density;skeleton_infill_line_width;skin_infill_density;skin_infill_line_width;sparse_infill_density;sparse_infill_line_width;sparse_infill_pattern;top_shell_layers;top_surface_pattern;wall_generator;wall_loops",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "draft_shield": "disabled",
+    "during_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "elefant_foot_compensation": "0.15",
+    "embedding_wall_into_infill": "0",
+    "enable_arc_fitting": "1",
+    "enable_circle_compensation": "0",
+    "enable_height_slowdown": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_long_retraction_when_cut": "2",
+    "enable_overhang_bridge_fan": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_pre_heating": "1",
+    "enable_pressure_advance": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_prime_tower": "1",
+    "enable_support": "0",
+    "enable_support_ironing": "0",
+    "enable_tower_interface_features": "1",
+    "enable_wrapping_detection": "0",
+    "enforce_support_layers": "0",
+    "eng_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "eng_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "ensure_vertical_shell_thickness": "enabled",
+    "exclude_object": "1",
+    "extruder_ams_count": [
+        "1#0|4#0",
+        "1#0|4#0"
+    ],
+    "extruder_clearance_dist_to_rod": "50",
+    "extruder_clearance_height_to_lid": "201",
+    "extruder_clearance_height_to_rod": "47.4",
+    "extruder_clearance_max_radius": "96",
+    "extruder_colour": [
+        "#018001",
+        "#018001"
+    ],
+    "extruder_max_nozzle_count": [
+        "1",
+        "1"
+    ],
+    "extruder_nozzle_stats": [
+        "Standard#1",
+        "Standard#1"
+    ],
+    "extruder_offset": [
+        "0x0",
+        "0x0"
+    ],
+    "extruder_printable_area": [
+        "0x0,325x0,325x320,0x320",
+        "25x0,350x0,350x320,25x320"
+    ],
+    "extruder_printable_height": [
+        "320",
+        "325"
+    ],
+    "extruder_type": [
+        "Direct Drive",
+        "Direct Drive"
+    ],
+    "extruder_variant_list": [
+        "Direct Drive Standard,Direct Drive High Flow",
+        "Direct Drive Standard,Direct Drive High Flow,Direct Drive TPU High Flow"
+    ],
+    "fan_cooling_layer_time": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "fan_direction": "left",
+    "fan_max_speed": [
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "fan_min_speed": [
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_adaptive_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_adhesiveness_category": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_bridge_speed": [
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25"
+    ],
+    "filament_change_length": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_change_length_nc": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_colour": [
+        "#FFFFFF",
+        "#C12E1F",
+        "#F4EE2A",
+        "#0000FF"
+    ],
+    "filament_colour_type": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_cooling_before_tower": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_cost": [
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99"
+    ],
+    "filament_density": [
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26"
+    ],
+    "filament_deretraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_dev_ams_drying_ams_limitations": [
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0"
+    ],
+    "filament_dev_ams_drying_heat_distortion_temperature": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_chamber_drying_bed_temperature": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "filament_dev_chamber_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_drying_cooling_temperature": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_drying_softening_temperature": [
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_diameter": [
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75"
+    ],
+    "filament_enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_end_gcode": [
+        "; filament end gcode \n",
+        "; filament end gcode \n",
+        "; filament end gcode \n",
+        "; filament end gcode \n"
+    ],
+    "filament_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "filament_flow_ratio": [
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98"
+    ],
+    "filament_flush_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_flush_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ids": [
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00"
+    ],
+    "filament_is_support": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_long_retractions_when_cut": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_map": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map_mode": "Auto For Flush",
+    "filament_max_volumetric_speed": [
+        "25",
+        "40",
+        "25",
+        "40",
+        "25",
+        "40",
+        "25",
+        "40"
+    ],
+    "filament_minimal_purge_on_wipe_tower": [
+        "15",
+        "15",
+        "15",
+        "15"
+    ],
+    "filament_multi_colour": [
+        "#FFFFFF",
+        "#C12E1F",
+        "#F4EE2A",
+        "#0000FF"
+    ],
+    "filament_notes": "",
+    "filament_nozzle_map": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_1_4_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_2_4_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_overhang_3_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_pre_cooling_temperature": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_pre_cooling_temperature_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_prime_volume": [
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_prime_volume_nc": [
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_printable": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "filament_ramming_travel_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_travel_time_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_volumetric_speed": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_ramming_volumetric_speed_nc": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_retract_before_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_length_nc": [
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14"
+    ],
+    "filament_retract_restart_extra": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_when_changing_layer": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_distances_when_cut": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_length": [
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4"
+    ],
+    "filament_retraction_minimum_travel": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_scarf_gap": [
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "filament_scarf_height": [
+        "10%",
+        "10%",
+        "10%",
+        "10%"
+    ],
+    "filament_scarf_length": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_scarf_seam_type": [
+        "none",
+        "none",
+        "none",
+        "none"
+    ],
+    "filament_self_index": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "3",
+        "3",
+        "4",
+        "4"
+    ],
+    "filament_settings_id": [
+        "Bambu PLA Basic @BBL H2D Pro",
+        "Bambu PLA Basic @BBL H2D Pro",
+        "Bambu PLA Basic @BBL H2D Pro",
+        "Bambu PLA Basic @BBL H2D Pro"
+    ],
+    "filament_shrink": [
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "filament_soluble": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_start_gcode": [
+        "; filament start gcode\n",
+        "; filament start gcode\n",
+        "; filament start gcode\n",
+        "; filament start gcode\n"
+    ],
+    "filament_tower_interface_pre_extrusion_dist": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_tower_interface_pre_extrusion_length": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_tower_interface_print_temp": [
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_tower_interface_purge_volume": [
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "filament_tower_ironing_area": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_type": [
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA"
+    ],
+    "filament_velocity_adaptation_factor": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_vendor": [
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab"
+    ],
+    "filament_volume_map": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_wipe": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_wipe_distance": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_z_hop": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop_types": [
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift"
+    ],
+    "filename_format": "{input_filename_base}_{filament_type[0]}_{print_time}.gcode",
+    "fill_multiline": "1",
+    "filter_out_gap_fill": "0",
+    "first_layer_print_sequence": [
+        "0"
+    ],
+    "first_x_layer_fan_speed": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "flush_into_infill": "0",
+    "flush_into_objects": "0",
+    "flush_into_support": "1",
+    "flush_multiplier": [
+        "1",
+        "1"
+    ],
+    "flush_volumes_matrix": [
+        "0",
+        "90",
+        "90",
+        "402",
+        "900",
+        "0",
+        "450",
+        "351",
+        "900",
+        "180",
+        "0",
+        "391",
+        "791",
+        "547",
+        "770",
+        "0",
+        "0",
+        "90",
+        "90",
+        "417",
+        "900",
+        "0",
+        "450",
+        "366",
+        "900",
+        "180",
+        "0",
+        "406",
+        "806",
+        "562",
+        "785",
+        "0"
+    ],
+    "flush_volumes_vector": [
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140"
+    ],
+    "from": "project",
+    "full_fan_speed_layer": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "fuzzy_skin": "none",
+    "fuzzy_skin_point_distance": "0.8",
+    "fuzzy_skin_thickness": "0.3",
+    "gap_infill_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "gcode_add_line_number": "0",
+    "gcode_flavor": "marlin",
+    "grab_length": [
+        "0",
+        "0"
+    ],
+    "group_algo_with_time": "0",
+    "has_scarf_joint_seam": "0",
+    "head_wrap_detect_zone": [],
+    "hole_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "hole_coef_2": [
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008"
+    ],
+    "hole_coef_3": [
+        "0.18",
+        "0.18",
+        "0.18",
+        "0.18"
+    ],
+    "hole_limit_max": [
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22"
+    ],
+    "hole_limit_min": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "host_type": "octoprint",
+    "hot_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hot_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hotend_cooling_rate": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "hotend_heating_rate": [
+        "3.6",
+        "3.6",
+        "3.6",
+        "3.6",
+        "3.6"
+    ],
+    "impact_strength_z": [
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8"
+    ],
+    "independent_support_layer_height": "1",
+    "infill_combination": "0",
+    "infill_direction": "0",
+    "infill_instead_top_bottom_surfaces": "0",
+    "infill_jerk": "9",
+    "infill_lock_depth": "1",
+    "infill_rotate_step": "0",
+    "infill_shift_step": "0.4",
+    "infill_wall_overlap": "15%",
+    "inherits_group": [
+        "0.08mm Extra Fine @BBL H2D Pro",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "initial_layer_acceleration": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "initial_layer_flow_ratio": "1",
+    "initial_layer_infill_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "initial_layer_jerk": "9",
+    "initial_layer_line_width": "0.42",
+    "initial_layer_print_height": "0.08",
+    "initial_layer_speed": [
+        "40",
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "initial_layer_travel_acceleration": [
+        "6000",
+        "6000",
+        "6000",
+        "6000",
+        "6000"
+    ],
+    "inner_wall_acceleration": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "inner_wall_jerk": "9",
+    "inner_wall_line_width": "0.42",
+    "inner_wall_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "interface_shells": "0",
+    "interlocking_beam": "0",
+    "interlocking_beam_layer_count": "2",
+    "interlocking_beam_width": "0.8",
+    "interlocking_boundary_avoidance": "2",
+    "interlocking_depth": "2",
+    "interlocking_orientation": "22.5",
+    "internal_bridge_support_thickness": "0.8",
+    "internal_solid_infill_line_width": "0.42",
+    "internal_solid_infill_pattern": "zig-zag",
+    "internal_solid_infill_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "ironing_direction": "45",
+    "ironing_flow": "8%",
+    "ironing_inset": "0.21",
+    "ironing_pattern": "zig-zag",
+    "ironing_spacing": "0.15",
+    "ironing_speed": "30",
+    "ironing_type": "no ironing",
+    "is_infill_first": "0",
+    "layer_change_gcode": ";======== H2D 20250710 layer_change ========\n; layer num/total_layer_count: {layer_num+1}/[total_layer_count]\n; update layer progress\nM73 L{layer_num+1}\nM991 S0 P{layer_num} ;notify layer change\n",
+    "layer_height": "0.08",
+    "line_width": "0.42",
+    "locked_skeleton_infill_pattern": "zigzag",
+    "locked_skin_infill_pattern": "crosszag",
+    "long_retractions_when_cut": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "long_retractions_when_ec": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "machine_end_gcode": ";========== H2D end ==========\n;===== date: 2025/12/26 =====\n\nG392 S0 ;turn off nozzle clog detect\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\nM400 ; wait for buffer to clear\nG92 E0 ; zero the extruder\nG1 E-0.8 F1800 ; retract\nM400\nM211 Z1\nG1 Z{max_layer_z + 0.4} F900 ; lower z a little\n\nM1002 judge_flag timelapse_record_flag\nM622 J1\n    G150.3\n    M400 ; wait all motion done\n    M991 S0 P-1 ;end smooth timelapse at safe pos\n    M400 S5 ;wait for last picture to be taken\nM623  ;end of \"timelapse_record_flag\"\n\nG90\nG1 Z{max_layer_z + 10} F900 ; lower z a little\n\nG90\nM141 S0 ; turn off chamber heating\nM140 S0 ; turn off bed\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off remote part cooling fan\nM106 P3 S0 ; turn off chamber cooling fan\nM106 P9 S0 ; turn off ext toodhead cooling fan\n; pull back filament to AMS\nM620 S65535\nT65535\nG150.2\nM621 S65535\n\nM620 S65279\nT65279\nG150.2\nM621 S65279\n\nG150.3\n\nM104 S0 T0; turn off hotend\nM104 S0 T1; turn off hotend\n\nM400 ; wait all motion done\nM17 S\nM17 Z0.4 ; lower z motor current to reduce impact if there is something in the bottom\n{if (100.0 - max_layer_z/2) > 0}\n    {if (max_layer_z + 100.0 - max_layer_z/2) < 320}\n        G1 Z{max_layer_z + 100.0 - max_layer_z/2} F600\n        G1 Z{max_layer_z + 98.0 - max_layer_z/2}\n    {else}\n        G1 Z320 F600\n        G1 Z320\n    {endif}\n{else}\n    {if (max_layer_z + 4.0) < 320}\n        G1 Z{max_layer_z + 4.0} F600\n        G1 Z{max_layer_z + 2.0}\n    {else}\n        G1 Z320 F600\n        G1 Z320\n    {endif}\n{endif}\nM400 P100\nM17 R ; restore z current\n\nM220 S100  ; Reset feedrate magnitude\nM201.2 K1.0 ; Reset acc magnitude\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 0\n\nM1015.4 S0 K0 ;disable air printing detect\n\n;=====printer finish air purification=========\nM622.1 S0\nM1002 judge_flag print_finish_air_filt_flag\n\nM622 J1\nM1002 gcode_claim_action : 66\nM145 P1\nM106 P6 S255\nM400 S180\nM106 P6 S0\nM623\n\nM622 J2\nM1002 gcode_claim_action : 66\nM145 P0\nM106 P3 S127\nM400 S180\nM106 P3 S0\nM623\n;=====printer finish air purification=========\n\n\n;=====printer finish  sound=========\nM17\nM400 S1\nM1006 S1\nM1006 A53 B10 L99 C53 D10 M99 E53 F10 N99 \nM1006 A57 B10 L99 C57 D10 M99 E57 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A53 B10 L99 C53 D10 M99 E53 F10 N99 \nM1006 A57 B10 L99 C57 D10 M99 E57 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A48 B10 L99 C48 D10 M99 E48 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A60 B10 L99 C60 D10 M99 E60 F10 N99 \nM1006 W\n;=====printer finish  sound=========\nM400\nM18\n\n",
+    "machine_hotend_change_time": "0",
+    "machine_load_filament_time": "30",
+    "machine_max_acceleration_e": [
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_extruding": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_retracting": [
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_travel": [
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000"
+    ],
+    "machine_max_acceleration_x": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_y": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_z": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_jerk_e": [
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5"
+    ],
+    "machine_max_jerk_x": [
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_y": [
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_z": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "machine_max_speed_e": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "machine_max_speed_x": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "machine_max_speed_y": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "machine_max_speed_z": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "machine_min_extruding_rate": [
+        "0",
+        "0"
+    ],
+    "machine_min_travel_rate": [
+        "0",
+        "0"
+    ],
+    "machine_pause_gcode": "M400 U1",
+    "machine_prepare_compensation_time": "260",
+    "machine_start_gcode": ";===== machine: H2D =========================\n;===== date: 20260116 =====================\n\n;M1002 set_flag extrude_cali_flag=1\n;M1002 set_flag g29_before_print_flag=1\n;M1002 set_flag auto_cali_toolhead_offset_flag=1\n;M1002 set_flag build_plate_detect_flag=1\n\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\nM400\n;M73 P99\n\nM960 S10 P1 ; ext fan led\n\n;=====printer start sound ===================\nM17\nM400 S1\nM1006 S1\nM1006 A53 B9 L99 C53 D9 M99 E53 F9 N99 \nM1006 A56 B9 L99 C56 D9 M99 E56 F9 N99 \nM1006 A61 B9 L99 C61 D9 M99 E61 F9 N99 \nM1006 A53 B9 L99 C53 D9 M99 E53 F9 N99 \nM1006 A56 B9 L99 C56 D9 M99 E56 F9 N99 \nM1006 A61 B18 L99 C61 D18 M99 E61 F18 N99 \nM1006 W\n;=====printer start sound ===================\n\n;===== reset machine status =================\nM204 S10000\nM630 S0 P0\n\nG90\nM17 D ; reset motor current to default\nM960 S5 P1 ; turn on logo lamp\nG90\nM1002 set_gcode_claim_speed_level 5 ;Reset speed level\nM220 S100 ;Reset Feedrate\nM221 S100 ;Reset Flowrate\nM73.2   R1.0 ;Reset left time magnitude\nG29.1 Z{+0.0} ; clear z-trim value first\nM983.1 M1 \nM901 D4\nM481 S0 ; turn off cutter pos comp\nG28.140 D0; reset pre-extrude z pos\n;===== reset machine status =================\n\nM620 M ;enable remap\n\n;===== avoid end stop =================\nG91\nG380 S2 Z42 F1200\nG380 S2 Z-12 F1200\nG90\n;===== avoid end stop =================\n\n;==== set airduct mode ==== \n\n{if (overall_chamber_temperature >= 40)}\n\n    M145 P1 ; set airduct mode to heating mode for heating\n    M106 P2 S0 ; turn off auxiliary fan\n    M106 P3 S0 ; turn off chamber fan\n\n{else}\n    M145 P0 ; set airduct mode to cooling mode for cooling\n    M106 P2 S178 ; turn on auxiliary fan for cooling\n    M106 P3 S127 ; turn on chamber fan for cooling\n    M140 S0 ; stop heatbed from heating\n\n    M1002 gcode_claim_action : 29\n    M191 S0 ; wait for chamber temp\n    M106 P2 S0 ; turn off auxiliary fan\n    {if (min_vitrification_temperature <= 50)}\n        {if (nozzle_diameter == 0.2)}\n            M142 P1 R30 S35 T40 U0.3 V0.5 W0.8 O40 ; set PLA/TPU ND0.2 chamber autocooling\n        {else}\n            M142 P1 R30 S40 T45 U0.3 V0.5 W0.8 O45; set PLA/TPU ND0.4 chamber autocooling\n        {endif}\n    {else}\n        {if (!is_all_bbl_filament)}\n            M142 P1 R35 S40 T45 U0.3 V0.5 W0.8 O45 L1 ; set third-party PETG chamber autocooling\n        {else}\n            {if (nozzle_diameter == 0.2)}\n                M142 P1 R35 S45 T50 U0.3 V0.5 W0.8 O50 L1 ; set PETG ND0.2 chamber autocooling\n            {else}\n                M142 P1 R35 S50 T55 U0.3 V0.5 W0.8 O55 L1 ; set PETG ND0.4 chamber autocooling\n            {endif}\n        {endif}\n    {endif}\n    {if(cooling_filter_enabled)}\n        M145.2 P0 F0\n    {else}\n        M145.2 P0 F1\n    {endif}\n{endif}\n;==== set airduct mode ==== \n\n;===== start to heat heatbed & hotend==========\n\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n\n    M104 S140 A\n    M140 S[bed_temperature_initial_layer_single]\n\n    ;===== set chamber temperature ==========\n    {if (overall_chamber_temperature >= 40)}\n        M145 P1 ; set airduct mode to heating mode\n        M141 S[overall_chamber_temperature] ; Let Chamber begin to heat\n    {endif}\n    ;===== set chamber temperature ==========\n\n;===== start to heat heatbead & hotend==========\n\n;====== cog noise reduction=================\nM982.2 S1 ; turn on cog noise reduction\n\n;===== first homing start =====\nM1002 gcode_claim_action : 13\n\nG28 X T300\n\nG150.1 F18000 ; wipe mouth to avoid filament stick to heatbed\nG150.3 F18000\nM400 P200\nM972 S24 P0 T2000\n\nM1002 gcode_claim_action : 74 ; Heatbed surface foreign object detection\n{if curr_bed_type==\"Textured PEI Plate\"}\nM972 S26 P0 C0\n{else}\nM972 S36 P0 C0 X1\n{endif}\nM972 S35 P0 C0\n\nM972 S41 P0 T5000 ; trash can anti-collision\n\nM1009 Q1 L1\nG91\nG380 S2 Z30 F1200 ; lower heatbed to move toolhead\nG90\nG1 X175 Y160 F30000\nG28 Z P0 T250\nM1009 Q1 L0\n\n;===== first homing end =====\n\nM400\n;M73 P99\n\n;===== detection start =====\n    \nM1002 judge_flag build_plate_detect_flag\nM622 S1\n    ;M1002 gcode_claim_action : 11 ; Indentifying build plate type\n    M972 S19 P0 C0    ; heatbed presence detection\n    M972 S31 P0 T5000 ; toolhead camera dirty detection\n    ;M1002 gcode_claim_action : 73 ; Build plate alignment detection\n    M972 S34 P0 T5000 ; heatbed plate offset detection\nM623\n\nM1002 gcode_claim_action : 72 ; Hotend Type Detection\nT1001\nM972 S14 P0 T5000 ; nozzle type detection\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} T{filament_map[initial_no_support_extruder] % 2} ; rise temp in advance\n\nG151 P{filament_map[initial_no_support_extruder] % 2} M ; plug the heat nozzle\n\n{if max_print_z >= 145}\nM1002 gcode_claim_action : 75 ; Heatbed underside foreign object detection\nG3811 Z{max_print_z}  ; Detect obstacles at the bottom of the heated bed\n{endif}\n\n;===== detection end =====\n\nM400\n;M73 P99\n\n;===== prepare print temperature and material ==========\nM400\nM211 X0 Y0 Z0 ;turn off soft endstop\nM975 S1 ; turn on input shaping\n\nG29.2 S0 ; avoid invalid abl data\n\n{if ((filament_type[initial_no_support_extruder] == \"PLA\") || (filament_type[initial_no_support_extruder] == \"PLA-CF\") || (filament_type[initial_no_support_extruder] == \"PETG\")) && (nozzle_diameter[initial_no_support_extruder] == 0.2)}\nM620.10 A0 F74.8347 H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\nM620.10 A1 F74.8347 H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\n{else}\nM620.10 A0 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60*0.8} H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\nM620.10 A1 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60*0.8} H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\n{endif}\n\nM620.11 P0 I[initial_no_support_extruder] E0\n\n{if long_retraction_when_ec }\nM620.11 K1 I[initial_no_support_extruder] R{retraction_distance_when_ec} F{max((flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60), 200)}\n{else}\nM620.11 K0 I[initial_no_support_extruder] R0\n{endif}\n\nM628 S1\n{if filament_type[initial_no_support_extruder] == \"TPU\"}\n    M620.11 S0 L0 I[initial_no_support_extruder] E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{else}\n{if (filament_type[initial_no_support_extruder] == \"PA\") ||  (filament_type[initial_no_support_extruder] == \"PA-GF\")}\n    M620.11 S1 L0 I[initial_no_support_extruder] R4 D2 E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{else}\n    M620.11 S1 L0 I[initial_no_support_extruder] R10 D8 E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{endif}\n{endif}\nM629\n\nM620 S[initial_no_support_extruder]A   ; switch material if AMS exist\nM1002 gcode_claim_action : 4\nM1002 set_filament_type:UNKNOWN\nM400\nT[initial_no_support_extruder]\nM400\nM628 S0\nM629\nM400\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM621 S[initial_no_support_extruder]A\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]}\nM400\nM106 P1 S0\n\nG29.2 S1\n;===== prepare print temperature and material ==========\n\nM400\n;M73 P99\n\n;===== auto extrude cali start =========================\nM975 S1\nM1002 judge_flag extrude_cali_flag\n\nM622 J0\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\nM623\n\nM622 J1\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M1002 gcode_claim_action : 8\n\n    M109 S{nozzle_temperature[initial_no_support_extruder]}\n\n    G90\n    M83\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\n\n    M400\n    M106 P1 S255\n    M400 S5\n    M106 P1 S0\n    G150.3\nM623\n\nM622 J2\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M1002 gcode_claim_action : 8\n\n    M109 S{nozzle_temperature[initial_no_support_extruder]}\n\n    G90\n    M83\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\n\n    M400\n    M106 P1 S255\n    M400 S5\n    M106 P1 S0\n    G150.3\nM623\n\n;===== auto extrude cali end =========================\n\n{if filament_type[initial_no_support_extruder] == \"TPU\"}\n    G150.2\n    G150.1\n    G150.2\n    G150.1\n    G150.2\n    G150.1\n{else}\n    M106 P1 S0\n    M400 S2\n    M109 S{nozzle_temperature[initial_no_support_extruder]} ; wait tmpr to extrude\n    M83\n    {if(nozzle_diameter == 0.8)}\n        G1 E60 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    {else}\n        G1 E45 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    {endif}\n    G1 E-3 F1800\n    M400 P500\n    G150.2\n    G150.1\n{endif}\n\nG91\nG1 Y-16 F12000 ; move away from the trash bin\nG90\n\nM400\n;M73 P99\n\n;===== wipe right nozzle start =====\n\nM1002 gcode_claim_action : 14\n    G150 T{nozzle_temperature_initial_layer[initial_no_support_extruder]}\n    {if (overall_chamber_temperature >= 40)}\n        G150 T{nozzle_temperature_initial_layer[initial_no_support_extruder] - 80}\n    {endif}\nM106 S255 ; turn on fan to cool the nozzle\n\n;===== wipe left nozzle end =====\n\nM400\n;M73 P99\n\n{if (overall_chamber_temperature >= 40)}\n    M1002 gcode_claim_action : 49\n    M191 S[overall_chamber_temperature] ; wait for chamber temp\n{endif}\n\nM400\n;M73 P99\n\n;===== bed leveling ==================================\n\nM1002 judge_flag g29_before_print_flag\n\nM190 S[bed_temperature_initial_layer_single]; ensure bed temp\nM109 S140 A\nM106 S0 ; turn off fan , too noisy\n\nG91\nG1 Z5 F1200\nG90\nG1 X175 Y160 F30000\n\nM622 J1\n    M1002 gcode_claim_action : 1\n    G29.20 A3\n    G29 A1 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R \n    M400\n    M500 ; save cali data\nM623\n    \nM622 J2\n    M1002 gcode_claim_action : 1\n    {if has_tpu_in_first_layer}\n        G29.20 A3\n        G29 A1 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R\n    {else}\n        G29.20 A4\n        G29 A2 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R\n    {endif}\n    M400\n    M500 ; save cali data\nM623\n\nM622 J0\n    G28 R\nM623\n\n;===== bed leveling end ================================\n\n;===== z ofst cali start =====\n\n    M190 S[bed_temperature_initial_layer_single]; ensure bed temp\n\n    G383 O0 M2 T140\n    M500\n\n;===== z ofst cali end =====\n\nG39.1 ; cali nozzle wrapped detection pos\nM500\n\nG90\nG1 Z5 F1200\nG1 X270 Y-0.5 F60000\nG28.140 S0 ; cali pre-extrude z pos\n\nM141 S[overall_chamber_temperature]\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} A\n\n;===== mech mode sweep start =====\n    M1002 gcode_claim_action : 3\n\n    G90\n    G1 Z5 F1200\n    G1 X187 Y160 F20000\n    T1000\n    M400 P200\n\n    M970.3 Q1 A5 K0 O1\n    M974 Q1 S2 P0\n\n    M970.3 Q0 A5 K0 O1\n    M974 Q0 S2 P0\n\n    M970.2 Q2 K0 W38 Z0.01\n    M974 Q2 S2 P0\n    M500\n\n    M975 S1\n;===== mech mode sweep end =====\n\nM400\n;M73 P99\n\nG150.3 ; move to garbage can to wait for temp\nM1026\nG29.9\n\n;===== xy ofst cali start =====\n\nM1002 judge_flag auto_cali_toolhead_offset_flag\n\nM622 J0\n    M1012.5 N1 R1\n    M500\nM623\n\nM622 J1\n    M1002 gcode_claim_action : 39\n    M141 S0\n    M620.17 T0 S{nozzle_temperature_initial_layer[(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])]} L{(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])}\n    M620.17 T1 S{nozzle_temperature_initial_layer[(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])]} L{(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])}\n    G383 O1 T{nozzle_temperature_initial_layer[initial_no_support_extruder]} L{initial_no_support_extruder}\n    M500\n    M141 S[overall_chamber_temperature]\nM623\n\nM622 J2\n    M1002 gcode_claim_action : 39\n    M141 S0\n    M620.17 T0 S{nozzle_temperature_initial_layer[(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])]} L{(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])}\n    M620.17 T1 S{nozzle_temperature_initial_layer[(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])]} L{(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])}\n    G383.3 T{nozzle_temperature_initial_layer[initial_no_support_extruder]} L{initial_no_support_extruder}\n    M500\n    M141 S[overall_chamber_temperature]\nM623\n;===== xy ofst cali end =====\n\nM400\n;M73 P99\n\nM1002 gcode_claim_action : 0\nM400\n\n;============switch again==================\n\nM211 X0 Y0 Z0 ;turn off soft endstop\nG91\nG1 Z6 F1200\nG90\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM620 S[initial_no_support_extruder]A\nM400\nT[initial_no_support_extruder]\nM400\nM628 S0\nM629\nM400\nM621 S[initial_no_support_extruder]A\n\n;============switch again==================\n\nM400\n;M73 P99\n\n;===== wait temperature reaching the reference value =======\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} ; rise to print tmpr\n\nM140 S[bed_temperature_initial_layer_single] \nM190 S[bed_temperature_initial_layer_single] \n\n    ;========turn off light and fans =============\n    M960 S1 P0 ; turn off laser\n    M960 S2 P0 ; turn off laser\n    M106 S0 ; turn off fan\n    M106 P2 S0 ; turn off big fan\n    ;==== set ext toodhead cooling fan ==== \n    {if (min_vitrification_temperature <= 50)}\n    M106 P9 S255\n    {endif}\n    ;============set motor current==================\n    M400 S1\n\n;===== wait temperature reaching the reference value =======\n\nM400\n;M73 P99\n\n;===== for Textured PEI Plate , lower the nozzle as the nozzle was touching topmost of the texture when homing ==\n    {if curr_bed_type==\"Textured PEI Plate\"}\n        {if nozzle_diameter[initial_no_support_extruder] == 0.2}\n            G29.1 Z{-0.01} ; for Textured PEI Plate\n        {else}\n            G29.1 Z{-0.02} ; for Textured PEI Plate\n        {endif}\n    {else}\n        {if nozzle_diameter[initial_no_support_extruder] == 0.2}\n            G29.1 Z{0.01} ; for Textured PEI Plate\n        {endif}\n    {endif}\n    \nG150.1\n\nM975 S1 ; turn on mech mode supression\nM983.4 S1 ; turn on deformation compensation \nG29.2 S1 ; turn on pos comp\nG29.7 S1\n\nG90\nG1 Z5 F1200\nG1 Y295 F30000\nG1 Y265 F18000\n\n;===== nozzle load line ===============================\n    G29.2 S1 ; ensure z comp turn on\n    G90\n    M83\n    G1 Z5 F1200\n    G1 X270 Y-0.5 F60000\n    G28.14 R0\n    G29.2 S0\n    G91\n    G1 Z0.8 F1200\n    G90\n    G1 X250 F60000\n    M109 S{nozzle_temperature_initial_layer[initial_no_support_extruder]}\n    M83\n{if (filament_type[initial_no_support_extruder] == \"TPU\")}\n    G1 E5 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n{endif}\n    G1 E5 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    G1 X290 E10 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    G91\n    G3 Z0.4 I1.217 J0 P1 F60000\n    G90\n    M83\n    G29.2 S1 ; ensure z comp turn on\n;===== noozle load line end ===========================\n\nM400\n;M73 P99\n\nM993 A1 B1 C1 ; nozzle cam detection allowed.\n\n{if (filament_type[initial_no_support_extruder] == \"TPU\")}\nM1015.3 S1;enable tpu clog detect\n{else}\nM1015.3 S0;disable tpu clog detect\n{endif}\n\n{if (filament_type[initial_no_support_extruder] == \"PLA\") ||  (filament_type[initial_no_support_extruder] == \"PETG\")\n ||  (filament_type[initial_no_support_extruder] == \"PLA-CF\")  ||  (filament_type[initial_no_support_extruder] == \"PETG-CF\")}\nM1015.4 S1 K1 H[nozzle_diameter] ;enable E air printing detect\n{else}\nM1015.4 S0 K0 H[nozzle_diameter] ;disable E air printing detect\n{endif}\n\nM620.6 I[initial_no_support_extruder] W1 ;enable ams air printing detect\n\nM211 Z1\nG29.99\n\n\n",
+    "machine_switch_extruder_time": "5.6",
+    "machine_unload_filament_time": "30",
+    "master_extruder_id": "2",
+    "max_bridge_length": "0",
+    "max_layer_height": [
+        "0.28",
+        "0.28"
+    ],
+    "max_travel_detour_distance": "0",
+    "min_bead_width": "85%",
+    "min_feature_size": "25%",
+    "min_layer_height": [
+        "0.08",
+        "0.08"
+    ],
+    "minimum_sparse_infill_area": "15",
+    "mmu_segmented_region_interlocking_depth": "0",
+    "mmu_segmented_region_max_width": "0",
+    "name": "project_settings",
+    "no_slow_down_for_cooling_on_outwalls": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "nozzle_diameter": [
+        "0.4",
+        "0.4"
+    ],
+    "nozzle_flush_dataset": [
+        "1",
+        "2",
+        "1",
+        "2",
+        "2"
+    ],
+    "nozzle_height": "4",
+    "nozzle_temperature": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_initial_layer": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_range_high": [
+        "240",
+        "240",
+        "240",
+        "240"
+    ],
+    "nozzle_temperature_range_low": [
+        "190",
+        "190",
+        "190",
+        "190"
+    ],
+    "nozzle_type": [
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel"
+    ],
+    "nozzle_volume": [
+        "130",
+        "133",
+        "145",
+        "148",
+        "148"
+    ],
+    "nozzle_volume_type": [
+        "Standard",
+        "Standard"
+    ],
+    "only_one_wall_first_layer": "1",
+    "ooze_prevention": "0",
+    "other_layers_print_sequence": [
+        "0"
+    ],
+    "other_layers_print_sequence_nums": "0",
+    "outer_wall_acceleration": [
+        "2000",
+        "2000",
+        "2000",
+        "2000",
+        "2000"
+    ],
+    "outer_wall_jerk": "9",
+    "outer_wall_line_width": "0.42",
+    "outer_wall_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "overhang_1_4_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "overhang_2_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "overhang_3_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "overhang_fan_speed": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "overhang_fan_threshold": [
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "overhang_threshold_participating_cooling": [
+        "95%",
+        "95%",
+        "95%",
+        "95%"
+    ],
+    "overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "override_filament_scarf_seam_setting": "0",
+    "override_process_overhang_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "physical_extruder_map": [
+        "1",
+        "0"
+    ],
+    "post_process": [],
+    "pre_start_fan_time": [
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "precise_outer_wall": "0",
+    "precise_z_height": "0",
+    "pressure_advance": [
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02"
+    ],
+    "prime_tower_brim_width": "-1",
+    "prime_tower_enable_framework": "0",
+    "prime_tower_extra_rib_length": "0",
+    "prime_tower_fillet_wall": "1",
+    "prime_tower_flat_ironing": "1",
+    "prime_tower_infill_gap": "150%",
+    "prime_tower_lift_height": "-1",
+    "prime_tower_lift_speed": "90",
+    "prime_tower_max_speed": "90",
+    "prime_tower_rib_wall": "0",
+    "prime_tower_rib_width": "8",
+    "prime_tower_skip_points": "1",
+    "prime_tower_width": "230",
+    "prime_volume_mode": "Default",
+    "print_compatible_printers": [
+        "Bambu Lab H2D Pro 0.4 nozzle"
+    ],
+    "print_extruder_id": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "2"
+    ],
+    "print_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive TPU High Flow"
+    ],
+    "print_flow_ratio": "1",
+    "print_sequence": "by layer",
+    "print_settings_id": "Bambu_Lumina",
+    "printable_area": [
+        "0x0",
+        "350x0",
+        "350x320",
+        "0x320"
+    ],
+    "printable_height": "325",
+    "printer_extruder_id": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "2"
+    ],
+    "printer_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive TPU High Flow"
+    ],
+    "printer_model": "Bambu Lab H2D Pro",
+    "printer_notes": "",
+    "printer_settings_id": "Bambu Lab H2D Pro 0.4 nozzle",
+    "printer_structure": "corexy",
+    "printer_technology": "FFF",
+    "printer_variant": "0.4",
+    "printhost_authorization_type": "key",
+    "printhost_ssl_ignore_revoke": "0",
+    "printing_by_object_gcode": "",
+    "process_notes": "",
+    "raft_contact_distance": "0.1",
+    "raft_expansion": "1.5",
+    "raft_first_layer_density": "90%",
+    "raft_first_layer_expansion": "-1",
+    "raft_layers": "0",
+    "reduce_crossing_wall": "0",
+    "reduce_fan_stop_start_freq": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "reduce_infill_retraction": "1",
+    "required_nozzle_HRC": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "resolution": "0.012",
+    "retract_before_wipe": [
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "retract_length_toolchange": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "retract_lift_above": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_lift_below": [
+        "319",
+        "319",
+        "319",
+        "319",
+        "319"
+    ],
+    "retract_restart_extra": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_restart_extra_toolchange": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_when_changing_layer": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "retraction_distances_when_cut": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "retraction_distances_when_ec": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "retraction_length": [
+        "0.8",
+        "0.8",
+        "0.8",
+        "0.8",
+        "0.8"
+    ],
+    "retraction_minimum_travel": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "retraction_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "role_base_wipe_speed": "1",
+    "scan_first_layer": "0",
+    "scarf_angle_threshold": "155",
+    "seam_gap": "15%",
+    "seam_placement_away_from_overhangs": "0",
+    "seam_position": "aligned",
+    "seam_slope_conditional": "1",
+    "seam_slope_entire_loop": "0",
+    "seam_slope_gap": "0",
+    "seam_slope_inner_walls": "1",
+    "seam_slope_min_length": "10",
+    "seam_slope_start_height": "10%",
+    "seam_slope_steps": "10",
+    "seam_slope_type": "none",
+    "silent_mode": "0",
+    "single_extruder_multi_material": "1",
+    "skeleton_infill_density": "100%",
+    "skeleton_infill_line_width": "0.42",
+    "skin_infill_density": "100%",
+    "skin_infill_depth": "2",
+    "skin_infill_line_width": "0.42",
+    "skirt_distance": "2",
+    "skirt_height": "1",
+    "skirt_loops": "0",
+    "slice_closing_radius": "0.049",
+    "slicing_mode": "regular",
+    "slow_down_for_layer_cooling": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "slow_down_layer_time": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "slow_down_min_speed": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "slowdown_end_acc": [
+        "100000",
+        "100000",
+        "100000",
+        "100000",
+        "100000"
+    ],
+    "slowdown_end_height": [
+        "400",
+        "400",
+        "400",
+        "400",
+        "400"
+    ],
+    "slowdown_end_speed": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "slowdown_start_acc": [
+        "100000",
+        "100000",
+        "100000",
+        "100000",
+        "100000"
+    ],
+    "slowdown_start_height": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "slowdown_start_speed": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "small_perimeter_speed": [
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "small_perimeter_threshold": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "smooth_coefficient": "4",
+    "smooth_speed_discontinuity_area": "1",
+    "solid_infill_filament": "0",
+    "sparse_infill_acceleration": [
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "sparse_infill_anchor": "400%",
+    "sparse_infill_anchor_max": "20",
+    "sparse_infill_density": "100%",
+    "sparse_infill_filament": "0",
+    "sparse_infill_lattice_angle_1": "-45",
+    "sparse_infill_lattice_angle_2": "45",
+    "sparse_infill_line_width": "0.42",
+    "sparse_infill_pattern": "zig-zag",
+    "sparse_infill_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "spiral_mode": "0",
+    "spiral_mode_max_xy_smoothing": "200%",
+    "spiral_mode_smooth": "0",
+    "standby_temperature_delta": "-5",
+    "start_end_points": [
+        "30x-3",
+        "54x245"
+    ],
+    "supertack_plate_temp": [
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "supertack_plate_temp_initial_layer": [
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "support_air_filtration": "0",
+    "support_angle": "0",
+    "support_base_pattern": "default",
+    "support_base_pattern_spacing": "2.5",
+    "support_bottom_interface_spacing": "0.5",
+    "support_bottom_z_distance": "0.08",
+    "support_chamber_temp_control": "1",
+    "support_cooling_filter": "1",
+    "support_critical_regions_only": "0",
+    "support_expansion": "0",
+    "support_filament": "0",
+    "support_interface_bottom_layers": "2",
+    "support_interface_filament": "0",
+    "support_interface_loop_pattern": "0",
+    "support_interface_not_for_body": "1",
+    "support_interface_pattern": "auto",
+    "support_interface_spacing": "0.5",
+    "support_interface_speed": [
+        "80",
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "support_interface_top_layers": "2",
+    "support_ironing_direction": "0",
+    "support_ironing_flow": "10%",
+    "support_ironing_inset": "0",
+    "support_ironing_pattern": "zig-zag",
+    "support_ironing_spacing": "0.15",
+    "support_ironing_speed": "30",
+    "support_line_width": "0.42",
+    "support_object_first_layer_gap": "0.2",
+    "support_object_skip_flush": "0",
+    "support_object_xy_distance": "0.35",
+    "support_on_build_plate_only": "0",
+    "support_remove_small_overhang": "1",
+    "support_speed": [
+        "150",
+        "150",
+        "150",
+        "150",
+        "150"
+    ],
+    "support_style": "default",
+    "support_threshold_angle": "15",
+    "support_top_z_distance": "0.08",
+    "support_type": "tree(auto)",
+    "symmetric_infill_y_axis": "0",
+    "temperature_vitrification": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "template_custom_gcode": "",
+    "textured_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "textured_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "thick_bridges": "0",
+    "thumbnail_size": [
+        "50x50"
+    ],
+    "time_lapse_gcode": ";======== H2D 20251104========\n; SKIPPABLE_START\n; SKIPTYPE: timelapse\nM622.1 S1 ; for prev firmware, default turned on\n\nM1002 judge_flag timelapse_record_flag\n\n    M622 J1\n    M993 A2 B2 C2\n    M993 A0 B0 C0\n    \n    M622.1 S0 ; for prev firmware, default turn off\n    M1002 set_flag smooth_safe_pos_suppoprt_flag=1\n    M1002 judge_flag smooth_safe_pos_suppoprt_flag\n    \n    M622 J0\n        {if !spiral_mode && !(has_timelapse_safe_pos && timelapse_type == 0) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                M83\n                G1 Z{max_layer_z + 0.4} F1200\n                M400\n            {endif}\n        {endif}\n\n        {if has_timelapse_safe_pos && timelapse_type == 0 && !spiral_mode}\n            M9711 M{timelapse_type} E{most_used_physical_extruder_id} X{timelapse_pos_x} Y{timelapse_pos_y} Z{layer_z + 0.4} S11 C10 O0 T3000\n        {else}\n            {if spiral_mode}\n                M971 S11 C10 O0\n                M1004 S5 P1  ; external shutter\n            {else}\n                M9711 M{timelapse_type} E{most_used_physical_extruder_id} Z{layer_z + 0.4} S11 C10 O0 T3000\n            {endif}\n        {endif}\n\n        {if !spiral_mode && !(has_timelapse_safe_pos && timelapse_type == 0) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                G90\n                G1 Z{max_layer_z + 3.0} F1200\n                G1 Y295 F30000\n                G1 Y265 F18000\n                M83\n            {endif}\n        {endif}\n    M623\n\n    M622 J1\n        {if !spiral_mode && !(has_timelapse_safe_pos) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                M83\n                G1 Z{max_layer_z + 0.4} F1200\n                M400\n            {endif}\n        {endif}\n\n        {if has_timelapse_safe_pos && !spiral_mode}\n            M9711 M{timelapse_type} E{most_used_physical_extruder_id} U{timelapse_pos_x} V{timelapse_pos_y} Z{layer_z + 0.4} S11 C10 O0 T3000\n        {else}\n            {if spiral_mode}\n                M971 S11 C10 O0\n                M1004 S5 P1  ; external shutter\n            {else}\n                M9711 M{timelapse_type} E{most_used_physical_extruder_id} Z{layer_z + 0.4} S11 C10 O0 T3000\n            {endif}\n        {endif}\n\n        {if !spiral_mode && !(has_timelapse_safe_pos) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                G90\n                G1 Z{max_layer_z + 3.0} F1200\n                G1 Y295 F30000\n                G1 Y265 F18000\n                M83\n            {endif}\n        {endif}\n    M623\n\n    M993 A3 B3 C3\n\nM623\n; SKIPPABLE_END\n",
+    "timelapse_type": "0",
+    "top_area_threshold": "200%",
+    "top_color_penetration_layers": "9",
+    "top_one_wall_type": "all top",
+    "top_shell_layers": "0",
+    "top_shell_thickness": "1",
+    "top_solid_infill_flow_ratio": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "top_surface_acceleration": [
+        "2000",
+        "2000",
+        "2000",
+        "2000",
+        "2000"
+    ],
+    "top_surface_density": "100%",
+    "top_surface_jerk": "9",
+    "top_surface_line_width": "0.42",
+    "top_surface_pattern": "zig-zag",
+    "top_surface_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "top_z_overrides_xy_distance": "0",
+    "travel_acceleration": [
+        "10000",
+        "10000",
+        "10000",
+        "10000",
+        "10000"
+    ],
+    "travel_jerk": "9",
+    "travel_short_distance_acceleration": [
+        "250",
+        "250",
+        "250",
+        "250",
+        "250"
+    ],
+    "travel_speed": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "travel_speed_z": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "tree_support_branch_angle": "45",
+    "tree_support_branch_diameter": "2",
+    "tree_support_branch_diameter_angle": "5",
+    "tree_support_branch_distance": "5",
+    "tree_support_wall_count": "-1",
+    "upward_compatible_machine": [
+        "Bambu Lab H2D Pro 0.4 nozzle"
+    ],
+    "use_firmware_retraction": "0",
+    "use_relative_e_distances": "1",
+    "version": "02.05.00.66",
+    "vertical_shell_speed": [
+        "80%",
+        "80%",
+        "80%",
+        "80%",
+        "80%"
+    ],
+    "volumetric_speed_coefficients": [
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0"
+    ],
+    "wall_distribution_count": "1",
+    "wall_filament": "0",
+    "wall_generator": "arachne",
+    "wall_loops": "1",
+    "wall_sequence": "inner wall/outer wall",
+    "wall_transition_angle": "10",
+    "wall_transition_filter_deviation": "25%",
+    "wall_transition_length": "100%",
+    "wipe": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "wipe_distance": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "wipe_speed": "80%",
+    "wipe_tower_no_sparse_layers": "0",
+    "wipe_tower_rotation_angle": "0",
+    "wipe_tower_x": [
+        "80"
+    ],
+    "wipe_tower_y": [
+        "250"
+    ],
+    "wrapping_detection_gcode": ";======== H2D 20250729 clumping ========\n{if !spiral_mode}\n    M622.1 S0 ; for previous firmware, default turn off\n    M1002 set_flag g39_forced_detection_flag=1\n    M1002 judge_flag g39_forced_detection_flag\n    M622 J1\n        {if layer_num == 3 || layer_num == 10 || layer_num == 19}\n            M993 A2 B2 C2 ; nozzle cam detection allow status save.\n            M993 A0 B0 C0 ; nozzle cam detection not allowed.\n\n            M400 P100\n\n            G39\n\n            G90\n            G1 Y295 F30000\n            G1 Y265 F18000\n            \n            M993 A3 B3 C3 ; nozzle cam detection allow status restore.\n        {endif}\n    M623\n{endif}\n",
+    "wrapping_detection_layers": "20",
+    "wrapping_exclude_area": [
+        "145x310",
+        "256x310",
+        "256x326",
+        "145x326"
+    ],
+    "xy_contour_compensation": "0",
+    "xy_hole_compensation": "0",
+    "z_direction_outwall_speed_continuous": "1",
+    "z_hop": [
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4"
+    ],
+    "z_hop_types": [
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift"
+    ]
+}
\ No newline at end of file
diff --git a/printer_profiles/bambu_h2s.json b/printer_profiles/bambu_h2s.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_h2s.json
@@ -0,0 +1,2118 @@
+{
+    "accel_to_decel_enable": "0",
+    "accel_to_decel_factor": "50%",
+    "activate_air_filtration": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "additional_cooling_fan_speed": [
+        "75",
+        "75",
+        "75",
+        "75"
+    ],
+    "apply_scarf_seam_on_circles": "1",
+    "apply_top_surface_compensation": "0",
+    "auxiliary_fan": "1",
+    "avoid_crossing_wall_includes_support": "0",
+    "bed_custom_model": "",
+    "bed_custom_texture": "",
+    "bed_exclude_area": [],
+    "bed_temperature_formula": "by_highest_temp",
+    "before_layer_change_gcode": "",
+    "best_object_pos": "0.3,0.5",
+    "bottom_color_penetration_layers": "7",
+    "bottom_shell_layers": "0",
+    "bottom_shell_thickness": "0",
+    "bottom_surface_density": "100%",
+    "bottom_surface_pattern": "zig-zag",
+    "bridge_angle": "0",
+    "bridge_flow": "1",
+    "bridge_no_support": "0",
+    "bridge_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "brim_object_gap": "0.1",
+    "brim_type": "auto_brim",
+    "brim_width": "5",
+    "chamber_temperatures": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "change_filament_gcode": ";======== H2D ========\n;===== 20260116 =====\nM993 A2 B2 C2 ; nozzle cam detection allow status save.\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\n{if (filament_type[next_extruder] == \"PLA\") ||  (filament_type[next_extruder] == \"PETG\")\n ||  (filament_type[next_extruder] == \"PLA-CF\")  ||  (filament_type[next_extruder] == \"PETG-CF\")}\nM1015.4 S1 K0 ;disable E air printing detect\n{else}\nM1015.4 S0 ; disable E air printing detect\n{endif}\n\nM620 S[next_extruder]A\nM1002 gcode_claim_action : 4\nM204 S9000\n\nG1 Z{max_layer_z + 3.0} F1200\n\nM400\nM106 P1 S0\nM106 P2 S0\n\n{if toolchange_count == 2}\n; get travel path for change filament\n;M620.1 X[travel_point_1_x] Y[travel_point_1_y] F21000 P0\n;M620.1 X[travel_point_2_x] Y[travel_point_2_y] F21000 P1\n;M620.1 X[travel_point_3_x] Y[travel_point_3_y] F21000 P2\n{endif}\n\n{if ((filament_type[current_extruder] == \"PLA\") || (filament_type[current_extruder] == \"PLA-CF\") || (filament_type[current_extruder] == \"PETG\")) && (nozzle_diameter[current_extruder] == 0.2)}\nM620.10 A0 F74.8347 L[flush_length] H{nozzle_diameter[current_extruder]} T{flush_temperatures[current_extruder]} P[old_filament_temp] S1\n{else}\nM620.10 A0 F{flush_volumetric_speeds[current_extruder]/2.4053*60*0.8} L[flush_length] H{nozzle_diameter[current_extruder]} T{flush_temperatures[current_extruder]} P[old_filament_temp] S1\n{endif}\n\n{if ((filament_type[next_extruder] == \"PLA\") || (filament_type[next_extruder] == \"PLA-CF\") || (filament_type[next_extruder] == \"PETG\")) && (nozzle_diameter[next_extruder] == 0.2)}\nM620.10 A1 F74.8347 L[flush_length] H{nozzle_diameter[next_extruder]} T{flush_temperatures[next_extruder]} P[new_filament_temp] S1\n{else}\nM620.10 A1 F{flush_volumetric_speeds[next_extruder]/2.4053*60*0.8} L[flush_length] H{nozzle_diameter[next_extruder]} T{flush_temperatures[next_extruder]} P[new_filament_temp] S1\n{endif}\n\n{if long_retraction_when_cut}\nM620.11 P1 I[current_extruder] E-{retraction_distance_when_cut} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 P0 I[current_extruder] E0\n{endif}\n\n{if long_retraction_when_ec}\nM620.11 K1 I[current_extruder] R{retraction_distance_when_ec} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 K0 I[current_extruder] R0\n{endif}\n\nM620.15 C{new_filament_temp - filament_cooling_before_tower[next_extruder]}\n\nM628 S1\n{if filament_type[current_extruder] == \"TPU\"}\nM620.11 S0 L0 I[current_extruder] E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\n{if (filament_type[current_extruder] == \"PA\") || (filament_type[current_extruder] == \"PA-GF\")}\nM620.11 S1 L0 I[current_extruder] R4 D2 E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{else}\nM620.11 S1 L0 I[current_extruder] R10 D8 E-{retraction_distances_when_cut[current_extruder]} F{max((flush_volumetric_speeds[current_extruder]/2.4053*60), 200)}\n{endif}\n{endif}\nM629\n\n{if (filament_type[current_extruder] == \"TPU\" || filament_type[next_extruder] == \"TPU\") && (old_extruder_variant != \"Direct Drive TPU High Flow\")}\nM620.11 H2 C331\n{else}\nM620.11 H0\n{endif}\n\n{if  (old_extruder_variant == \"Direct Drive TPU High Flow\") && (filament_map[current_extruder] == 2) && (filament_map[next_extruder] == 1)}\n;debug log pe:{previous_extruder} ce:{current_extruder} ne:{next_extruder} oev: {old_extruder_variant} nev:{new_extruder_variant}\n;debug fm-curr:{filament_map[current_extruder]} fm-next:{filament_map[next_extruder]}\n;sw from R2L&TPU kit, travel run a distance for sketch TPU\nG1 X30 Y30 F5000\nM400\nG1 X300 Y30 F5000\nM400\n{endif}\n\nT[next_extruder]\n\n;deretract\n{if filament_type[next_extruder] == \"TPU\"}\n{else}\n{if (filament_type[next_extruder] == \"PA\") || (filament_type[next_extruder] == \"PA-GF\")}\n;VG1 E1 F{max(new_filament_e_feedrate, 200)}\n;VG1 E1 F{max(new_filament_e_feedrate/2, 100)}\n{else}\n;VG1 E4 F{max(new_filament_e_feedrate, 200)}\n;VG1 E4 F{max(new_filament_e_feedrate/2, 100)}\n{endif}\n{endif}\n\n; VFLUSH_START\n\n{if flush_length>41.5}\n;VG1 E41.5 F{min(old_filament_e_feedrate,new_filament_e_feedrate)}\n;VG1 E{flush_length-41.5} F{new_filament_e_feedrate}\n{else}\n;VG1 E{flush_length} F{min(old_filament_e_feedrate,new_filament_e_feedrate)}\n{endif}\n\nSYNC T{ceil(flush_length / 125) * 5}\n\n; VFLUSH_END\n\nM1002 set_filament_type:{filament_type[next_extruder]}\n\nM400\nM83\n{if next_extruder < 255}\n\nM620.10 R{new_extruder_retracted_length}\nM628 S0\n;VM109 S[new_filament_temp]\nM629\nM400\n\n;prime_tower_interface\n{if is_prime_tower_interface && filament_tower_interface_purge_volume !=0}\nG150.1\nM620.13 W0 L{filament_tower_interface_purge_volume} T{filament_tower_interface_print_temp} R0.0\n{endif}\n;prime_tower_interface\n\nM983.3 F{filament_max_volumetric_speed[next_extruder]/2.4} A0.4 R{new_extruder_retracted_length}\n\nM400\n{if wipe_avoid_perimeter}\nG1 Y320 F30000\nG1 X{wipe_avoid_pos_x} F30000\n{endif}\nG1 Y295 F30000\nG1 Y265 F18000\nG1 Z{max_layer_z + 3.0} F3000\n{if layer_z <= (initial_layer_print_height + 0.001)}\nM204 S[initial_layer_acceleration]\n{else}\nM204 S[default_acceleration]\n{endif}\n{else}\nG1 X[x_after_toolchange] Y[y_after_toolchange] Z[z_after_toolchange] F12000\n{endif}\nM621 S[next_extruder]A\n\nM993 A3 B3 C3 ; nozzle cam detection allow status restore.\n\n{if (filament_type[next_extruder]  == \"TPU\")}\nM1015.3 S1;enable tpu clog detect\n{else}\nM1015.3 S0;disable tpu clog detect\n{endif}\n\n{if (filament_type[next_extruder] == \"PLA\") ||  (filament_type[next_extruder] == \"PETG\")\n ||  (filament_type[next_extruder] == \"PLA-CF\")  ||  (filament_type[next_extruder] == \"PETG-CF\")}\nM1015.4 S1 K1 H[nozzle_diameter] ;enable E air printing detect\n{else}\nM1015.4 S0 ; disable E air printing detect\n{endif}\n\nM620.6 I[next_extruder] W1 ;enable ams air printing detect\nM1002 gcode_claim_action : 0",
+    "circle_compensation_manual_offset": "0",
+    "circle_compensation_speed": [
+        "200",
+        "200",
+        "200",
+        "200"
+    ],
+    "close_fan_the_first_x_layers": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "complete_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "cool_plate_temp": [
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cool_plate_temp_initial_layer": [
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cooling_filter_enabled": "0",
+    "cooling_perimeter_transition_distance": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "cooling_slowdown_logic": [
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling"
+    ],
+    "counter_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "counter_coef_2": [
+        "0.003",
+        "0.003",
+        "0.003",
+        "0.003"
+    ],
+    "counter_coef_3": [
+        "0.01",
+        "0.01",
+        "0.01",
+        "0.01"
+    ],
+    "counter_limit_max": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "counter_limit_min": [
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035"
+    ],
+    "curr_bed_type": "Textured PEI Plate",
+    "default_acceleration": [
+        "4000",
+        "4000",
+        "4000",
+        "4000",
+        "4000"
+    ],
+    "default_filament_colour": [
+        "",
+        "",
+        "",
+        ""
+    ],
+    "default_filament_profile": [
+        "Bambu PLA Basic @BBL H2S"
+    ],
+    "default_jerk": "0",
+    "default_nozzle_volume_type": [
+        "Standard",
+        "Standard"
+    ],
+    "default_print_profile": "0.20mm Standard @BBL H2S",
+    "deretraction_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "detect_floating_vertical_shell": "1",
+    "detect_narrow_internal_solid_infill": "0",
+    "detect_overhang_wall": "1",
+    "detect_thin_wall": "0",
+    "diameter_limit": [
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "different_settings_to_system": [
+        "bottom_shell_layers;bottom_surface_pattern;detect_narrow_internal_solid_infill;infill_direction;initial_layer_line_width;initial_layer_print_height;inner_wall_line_width;only_one_wall_first_layer;prime_tower_rib_wall;prime_tower_width;skeleton_infill_density;skeleton_infill_line_width;skin_infill_density;skin_infill_line_width;sparse_infill_density;sparse_infill_line_width;sparse_infill_pattern;top_shell_layers;top_surface_pattern;wall_generator;wall_loops",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "draft_shield": "disabled",
+    "during_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "elefant_foot_compensation": "0.15",
+    "embedding_wall_into_infill": "0",
+    "enable_arc_fitting": "1",
+    "enable_circle_compensation": "0",
+    "enable_height_slowdown": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_long_retraction_when_cut": "2",
+    "enable_overhang_bridge_fan": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_pre_heating": "1",
+    "enable_pressure_advance": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_prime_tower": "1",
+    "enable_support": "0",
+    "enable_support_ironing": "0",
+    "enable_tower_interface_features": "1",
+    "enable_wrapping_detection": "0",
+    "enforce_support_layers": "0",
+    "eng_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "eng_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "ensure_vertical_shell_thickness": "enabled",
+    "exclude_object": "1",
+    "extruder_ams_count": [
+        "1#0|4#0",
+        "1#0|4#0"
+    ],
+    "extruder_clearance_dist_to_rod": "50",
+    "extruder_clearance_height_to_lid": "201",
+    "extruder_clearance_height_to_rod": "47.4",
+    "extruder_clearance_max_radius": "96",
+    "extruder_colour": [
+        "#018001",
+        "#018001"
+    ],
+    "extruder_max_nozzle_count": [
+        "1",
+        "1"
+    ],
+    "extruder_nozzle_stats": [
+        "Standard#1",
+        "Standard#1"
+    ],
+    "extruder_offset": [
+        "0x0",
+        "0x0"
+    ],
+    "extruder_printable_area": [
+        "0x0,325x0,325x320,0x320",
+        "25x0,350x0,350x320,25x320"
+    ],
+    "extruder_printable_height": [
+        "320",
+        "325"
+    ],
+    "extruder_type": [
+        "Direct Drive",
+        "Direct Drive"
+    ],
+    "extruder_variant_list": [
+        "Direct Drive Standard,Direct Drive High Flow",
+        "Direct Drive Standard,Direct Drive High Flow,Direct Drive TPU High Flow"
+    ],
+    "fan_cooling_layer_time": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "fan_direction": "left",
+    "fan_max_speed": [
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "fan_min_speed": [
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_adaptive_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_adhesiveness_category": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_bridge_speed": [
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25"
+    ],
+    "filament_change_length": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_change_length_nc": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_colour": [
+        "#FFFFFF",
+        "#C12E1F",
+        "#F4EE2A",
+        "#0000FF"
+    ],
+    "filament_colour_type": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_cooling_before_tower": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_cost": [
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99"
+    ],
+    "filament_density": [
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26"
+    ],
+    "filament_deretraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_dev_ams_drying_ams_limitations": [
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0"
+    ],
+    "filament_dev_ams_drying_heat_distortion_temperature": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_chamber_drying_bed_temperature": [
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "filament_dev_chamber_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_drying_cooling_temperature": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_drying_softening_temperature": [
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_diameter": [
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75"
+    ],
+    "filament_enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_end_gcode": [
+        "; filament end gcode \n",
+        "; filament end gcode \n",
+        "; filament end gcode \n",
+        "; filament end gcode \n"
+    ],
+    "filament_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "filament_flow_ratio": [
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98",
+        "0.98"
+    ],
+    "filament_flush_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_flush_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ids": [
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00"
+    ],
+    "filament_is_support": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_long_retractions_when_cut": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_map": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map_mode": "Auto For Flush",
+    "filament_max_volumetric_speed": [
+        "25",
+        "40",
+        "25",
+        "40",
+        "25",
+        "40",
+        "25",
+        "40"
+    ],
+    "filament_minimal_purge_on_wipe_tower": [
+        "15",
+        "15",
+        "15",
+        "15"
+    ],
+    "filament_multi_colour": [
+        "#FFFFFF",
+        "#C12E1F",
+        "#F4EE2A",
+        "#0000FF"
+    ],
+    "filament_notes": "",
+    "filament_nozzle_map": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_1_4_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_2_4_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_overhang_3_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_pre_cooling_temperature": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_pre_cooling_temperature_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_prime_volume": [
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_prime_volume_nc": [
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_printable": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "filament_ramming_travel_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_travel_time_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_volumetric_speed": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_ramming_volumetric_speed_nc": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_retract_before_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_length_nc": [
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14"
+    ],
+    "filament_retract_restart_extra": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_when_changing_layer": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_distances_when_cut": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_length": [
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4"
+    ],
+    "filament_retraction_minimum_travel": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_speed": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_scarf_gap": [
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "filament_scarf_height": [
+        "10%",
+        "10%",
+        "10%",
+        "10%"
+    ],
+    "filament_scarf_length": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_scarf_seam_type": [
+        "none",
+        "none",
+        "none",
+        "none"
+    ],
+    "filament_self_index": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "3",
+        "3",
+        "4",
+        "4"
+    ],
+    "filament_settings_id": [
+        "Bambu PLA Basic @BBL H2S",
+        "Bambu PLA Basic @BBL H2S",
+        "Bambu PLA Basic @BBL H2S",
+        "Bambu PLA Basic @BBL H2S"
+    ],
+    "filament_shrink": [
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "filament_soluble": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_start_gcode": [
+        "; filament start gcode\n",
+        "; filament start gcode\n",
+        "; filament start gcode\n",
+        "; filament start gcode\n"
+    ],
+    "filament_tower_interface_pre_extrusion_dist": [
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_tower_interface_pre_extrusion_length": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_tower_interface_print_temp": [
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_tower_interface_purge_volume": [
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "filament_tower_ironing_area": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_type": [
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA"
+    ],
+    "filament_velocity_adaptation_factor": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_vendor": [
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab"
+    ],
+    "filament_volume_map": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_wipe": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_wipe_distance": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_z_hop": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop_types": [
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift",
+        "Spiral Lift"
+    ],
+    "filename_format": "{input_filename_base}_{filament_type[0]}_{print_time}.gcode",
+    "fill_multiline": "1",
+    "filter_out_gap_fill": "0",
+    "first_layer_print_sequence": [
+        "0"
+    ],
+    "first_x_layer_fan_speed": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "flush_into_infill": "0",
+    "flush_into_objects": "0",
+    "flush_into_support": "1",
+    "flush_multiplier": [
+        "1",
+        "1"
+    ],
+    "flush_volumes_matrix": [
+        "0",
+        "90",
+        "90",
+        "402",
+        "900",
+        "0",
+        "450",
+        "351",
+        "900",
+        "180",
+        "0",
+        "391",
+        "791",
+        "547",
+        "770",
+        "0",
+        "0",
+        "90",
+        "90",
+        "417",
+        "900",
+        "0",
+        "450",
+        "366",
+        "900",
+        "180",
+        "0",
+        "406",
+        "806",
+        "562",
+        "785",
+        "0"
+    ],
+    "flush_volumes_vector": [
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140"
+    ],
+    "from": "project",
+    "full_fan_speed_layer": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "fuzzy_skin": "none",
+    "fuzzy_skin_point_distance": "0.8",
+    "fuzzy_skin_thickness": "0.3",
+    "gap_infill_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "gcode_add_line_number": "0",
+    "gcode_flavor": "marlin",
+    "grab_length": [
+        "0",
+        "0"
+    ],
+    "group_algo_with_time": "0",
+    "has_scarf_joint_seam": "0",
+    "head_wrap_detect_zone": [],
+    "hole_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "hole_coef_2": [
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008"
+    ],
+    "hole_coef_3": [
+        "0.18",
+        "0.18",
+        "0.18",
+        "0.18"
+    ],
+    "hole_limit_max": [
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22"
+    ],
+    "hole_limit_min": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "host_type": "octoprint",
+    "hot_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hot_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hotend_cooling_rate": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "hotend_heating_rate": [
+        "3.6",
+        "3.6",
+        "3.6",
+        "3.6",
+        "3.6"
+    ],
+    "impact_strength_z": [
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8"
+    ],
+    "independent_support_layer_height": "1",
+    "infill_combination": "0",
+    "infill_direction": "0",
+    "infill_instead_top_bottom_surfaces": "0",
+    "infill_jerk": "9",
+    "infill_lock_depth": "1",
+    "infill_rotate_step": "0",
+    "infill_shift_step": "0.4",
+    "infill_wall_overlap": "15%",
+    "inherits_group": [
+        "0.08mm Extra Fine @BBL H2S",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "initial_layer_acceleration": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "initial_layer_flow_ratio": "1",
+    "initial_layer_infill_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "initial_layer_jerk": "9",
+    "initial_layer_line_width": "0.42",
+    "initial_layer_print_height": "0.08",
+    "initial_layer_speed": [
+        "40",
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "initial_layer_travel_acceleration": [
+        "6000",
+        "6000",
+        "6000",
+        "6000",
+        "6000"
+    ],
+    "inner_wall_acceleration": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "inner_wall_jerk": "9",
+    "inner_wall_line_width": "0.42",
+    "inner_wall_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "interface_shells": "0",
+    "interlocking_beam": "0",
+    "interlocking_beam_layer_count": "2",
+    "interlocking_beam_width": "0.8",
+    "interlocking_boundary_avoidance": "2",
+    "interlocking_depth": "2",
+    "interlocking_orientation": "22.5",
+    "internal_bridge_support_thickness": "0.8",
+    "internal_solid_infill_line_width": "0.42",
+    "internal_solid_infill_pattern": "zig-zag",
+    "internal_solid_infill_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "ironing_direction": "45",
+    "ironing_flow": "8%",
+    "ironing_inset": "0.21",
+    "ironing_pattern": "zig-zag",
+    "ironing_spacing": "0.15",
+    "ironing_speed": "30",
+    "ironing_type": "no ironing",
+    "is_infill_first": "0",
+    "layer_change_gcode": ";======== H2D 20250710 layer_change ========\n; layer num/total_layer_count: {layer_num+1}/[total_layer_count]\n; update layer progress\nM73 L{layer_num+1}\nM991 S0 P{layer_num} ;notify layer change\n",
+    "layer_height": "0.08",
+    "line_width": "0.42",
+    "locked_skeleton_infill_pattern": "zigzag",
+    "locked_skin_infill_pattern": "crosszag",
+    "long_retractions_when_cut": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "long_retractions_when_ec": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "machine_end_gcode": ";========== H2D end ==========\n;===== date: 2025/12/26 =====\n\nG392 S0 ;turn off nozzle clog detect\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\nM400 ; wait for buffer to clear\nG92 E0 ; zero the extruder\nG1 E-0.8 F1800 ; retract\nM400\nM211 Z1\nG1 Z{max_layer_z + 0.4} F900 ; lower z a little\n\nM1002 judge_flag timelapse_record_flag\nM622 J1\n    G150.3\n    M400 ; wait all motion done\n    M991 S0 P-1 ;end smooth timelapse at safe pos\n    M400 S5 ;wait for last picture to be taken\nM623  ;end of \"timelapse_record_flag\"\n\nG90\nG1 Z{max_layer_z + 10} F900 ; lower z a little\n\nG90\nM141 S0 ; turn off chamber heating\nM140 S0 ; turn off bed\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off remote part cooling fan\nM106 P3 S0 ; turn off chamber cooling fan\nM106 P9 S0 ; turn off ext toodhead cooling fan\n; pull back filament to AMS\nM620 S65535\nT65535\nG150.2\nM621 S65535\n\nM620 S65279\nT65279\nG150.2\nM621 S65279\n\nG150.3\n\nM104 S0 T0; turn off hotend\nM104 S0 T1; turn off hotend\n\nM400 ; wait all motion done\nM17 S\nM17 Z0.4 ; lower z motor current to reduce impact if there is something in the bottom\n{if (100.0 - max_layer_z/2) > 0}\n    {if (max_layer_z + 100.0 - max_layer_z/2) < 320}\n        G1 Z{max_layer_z + 100.0 - max_layer_z/2} F600\n        G1 Z{max_layer_z + 98.0 - max_layer_z/2}\n    {else}\n        G1 Z320 F600\n        G1 Z320\n    {endif}\n{else}\n    {if (max_layer_z + 4.0) < 320}\n        G1 Z{max_layer_z + 4.0} F600\n        G1 Z{max_layer_z + 2.0}\n    {else}\n        G1 Z320 F600\n        G1 Z320\n    {endif}\n{endif}\nM400 P100\nM17 R ; restore z current\n\nM220 S100  ; Reset feedrate magnitude\nM201.2 K1.0 ; Reset acc magnitude\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 0\n\nM1015.4 S0 K0 ;disable air printing detect\n\n;=====printer finish air purification=========\nM622.1 S0\nM1002 judge_flag print_finish_air_filt_flag\n\nM622 J1\nM1002 gcode_claim_action : 66\nM145 P1\nM106 P6 S255\nM400 S180\nM106 P6 S0\nM623\n\nM622 J2\nM1002 gcode_claim_action : 66\nM145 P0\nM106 P3 S127\nM400 S180\nM106 P3 S0\nM623\n;=====printer finish air purification=========\n\n\n;=====printer finish  sound=========\nM17\nM400 S1\nM1006 S1\nM1006 A53 B10 L99 C53 D10 M99 E53 F10 N99 \nM1006 A57 B10 L99 C57 D10 M99 E57 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A53 B10 L99 C53 D10 M99 E53 F10 N99 \nM1006 A57 B10 L99 C57 D10 M99 E57 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A48 B10 L99 C48 D10 M99 E48 F10 N99 \nM1006 A0 B15 L0 C0 D15 M0 E0 F15 N0 \nM1006 A60 B10 L99 C60 D10 M99 E60 F10 N99 \nM1006 W\n;=====printer finish  sound=========\nM400\nM18\n\n",
+    "machine_hotend_change_time": "0",
+    "machine_load_filament_time": "30",
+    "machine_max_acceleration_e": [
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_extruding": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_retracting": [
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_travel": [
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000",
+        "9000"
+    ],
+    "machine_max_acceleration_x": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_y": [
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_z": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_jerk_e": [
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5"
+    ],
+    "machine_max_jerk_x": [
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_y": [
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_z": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "machine_max_speed_e": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "machine_max_speed_x": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "machine_max_speed_y": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "machine_max_speed_z": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "machine_min_extruding_rate": [
+        "0",
+        "0"
+    ],
+    "machine_min_travel_rate": [
+        "0",
+        "0"
+    ],
+    "machine_pause_gcode": "M400 U1",
+    "machine_prepare_compensation_time": "260",
+    "machine_start_gcode": ";===== machine: H2D =========================\n;===== date: 20260116 =====================\n\n;M1002 set_flag extrude_cali_flag=1\n;M1002 set_flag g29_before_print_flag=1\n;M1002 set_flag auto_cali_toolhead_offset_flag=1\n;M1002 set_flag build_plate_detect_flag=1\n\nM993 A0 B0 C0 ; nozzle cam detection not allowed.\n\nM400\n;M73 P99\n\nM960 S10 P1 ; ext fan led\n\n;=====printer start sound ===================\nM17\nM400 S1\nM1006 S1\nM1006 A53 B9 L99 C53 D9 M99 E53 F9 N99 \nM1006 A56 B9 L99 C56 D9 M99 E56 F9 N99 \nM1006 A61 B9 L99 C61 D9 M99 E61 F9 N99 \nM1006 A53 B9 L99 C53 D9 M99 E53 F9 N99 \nM1006 A56 B9 L99 C56 D9 M99 E56 F9 N99 \nM1006 A61 B18 L99 C61 D18 M99 E61 F18 N99 \nM1006 W\n;=====printer start sound ===================\n\n;===== reset machine status =================\nM204 S10000\nM630 S0 P0\n\nG90\nM17 D ; reset motor current to default\nM960 S5 P1 ; turn on logo lamp\nG90\nM1002 set_gcode_claim_speed_level 5 ;Reset speed level\nM220 S100 ;Reset Feedrate\nM221 S100 ;Reset Flowrate\nM73.2   R1.0 ;Reset left time magnitude\nG29.1 Z{+0.0} ; clear z-trim value first\nM983.1 M1 \nM901 D4\nM481 S0 ; turn off cutter pos comp\nG28.140 D0; reset pre-extrude z pos\n;===== reset machine status =================\n\nM620 M ;enable remap\n\n;===== avoid end stop =================\nG91\nG380 S2 Z42 F1200\nG380 S2 Z-12 F1200\nG90\n;===== avoid end stop =================\n\n;==== set airduct mode ==== \n\n{if (overall_chamber_temperature >= 40)}\n\n    M145 P1 ; set airduct mode to heating mode for heating\n    M106 P2 S0 ; turn off auxiliary fan\n    M106 P3 S0 ; turn off chamber fan\n\n{else}\n    M145 P0 ; set airduct mode to cooling mode for cooling\n    M106 P2 S178 ; turn on auxiliary fan for cooling\n    M106 P3 S127 ; turn on chamber fan for cooling\n    M140 S0 ; stop heatbed from heating\n\n    M1002 gcode_claim_action : 29\n    M191 S0 ; wait for chamber temp\n    M106 P2 S0 ; turn off auxiliary fan\n    {if (min_vitrification_temperature <= 50)}\n        {if (nozzle_diameter == 0.2)}\n            M142 P1 R30 S35 T40 U0.3 V0.5 W0.8 O40 ; set PLA/TPU ND0.2 chamber autocooling\n        {else}\n            M142 P1 R30 S40 T45 U0.3 V0.5 W0.8 O45; set PLA/TPU ND0.4 chamber autocooling\n        {endif}\n    {else}\n        {if (!is_all_bbl_filament)}\n            M142 P1 R35 S40 T45 U0.3 V0.5 W0.8 O45 L1 ; set third-party PETG chamber autocooling\n        {else}\n            {if (nozzle_diameter == 0.2)}\n                M142 P1 R35 S45 T50 U0.3 V0.5 W0.8 O50 L1 ; set PETG ND0.2 chamber autocooling\n            {else}\n                M142 P1 R35 S50 T55 U0.3 V0.5 W0.8 O55 L1 ; set PETG ND0.4 chamber autocooling\n            {endif}\n        {endif}\n    {endif}\n    {if(cooling_filter_enabled)}\n        M145.2 P0 F0\n    {else}\n        M145.2 P0 F1\n    {endif}\n{endif}\n;==== set airduct mode ==== \n\n;===== start to heat heatbed & hotend==========\n\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n\n    M104 S140 A\n    M140 S[bed_temperature_initial_layer_single]\n\n    ;===== set chamber temperature ==========\n    {if (overall_chamber_temperature >= 40)}\n        M145 P1 ; set airduct mode to heating mode\n        M141 S[overall_chamber_temperature] ; Let Chamber begin to heat\n    {endif}\n    ;===== set chamber temperature ==========\n\n;===== start to heat heatbead & hotend==========\n\n;====== cog noise reduction=================\nM982.2 S1 ; turn on cog noise reduction\n\n;===== first homing start =====\nM1002 gcode_claim_action : 13\n\nG28 X T300\n\nG150.1 F18000 ; wipe mouth to avoid filament stick to heatbed\nG150.3 F18000\nM400 P200\nM972 S24 P0 T2000\n\nM1002 gcode_claim_action : 74 ; Heatbed surface foreign object detection\n{if curr_bed_type==\"Textured PEI Plate\"}\nM972 S26 P0 C0\n{else}\nM972 S36 P0 C0 X1\n{endif}\nM972 S35 P0 C0\n\nM972 S41 P0 T5000 ; trash can anti-collision\n\nM1009 Q1 L1\nG91\nG380 S2 Z30 F1200 ; lower heatbed to move toolhead\nG90\nG1 X175 Y160 F30000\nG28 Z P0 T250\nM1009 Q1 L0\n\n;===== first homing end =====\n\nM400\n;M73 P99\n\n;===== detection start =====\n    \nM1002 judge_flag build_plate_detect_flag\nM622 S1\n    ;M1002 gcode_claim_action : 11 ; Indentifying build plate type\n    M972 S19 P0 C0    ; heatbed presence detection\n    M972 S31 P0 T5000 ; toolhead camera dirty detection\n    ;M1002 gcode_claim_action : 73 ; Build plate alignment detection\n    M972 S34 P0 T5000 ; heatbed plate offset detection\nM623\n\nM1002 gcode_claim_action : 72 ; Hotend Type Detection\nT1001\nM972 S14 P0 T5000 ; nozzle type detection\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} T{filament_map[initial_no_support_extruder] % 2} ; rise temp in advance\n\nG151 P{filament_map[initial_no_support_extruder] % 2} M ; plug the heat nozzle\n\n{if max_print_z >= 145}\nM1002 gcode_claim_action : 75 ; Heatbed underside foreign object detection\nG3811 Z{max_print_z}  ; Detect obstacles at the bottom of the heated bed\n{endif}\n\n;===== detection end =====\n\nM400\n;M73 P99\n\n;===== prepare print temperature and material ==========\nM400\nM211 X0 Y0 Z0 ;turn off soft endstop\nM975 S1 ; turn on input shaping\n\nG29.2 S0 ; avoid invalid abl data\n\n{if ((filament_type[initial_no_support_extruder] == \"PLA\") || (filament_type[initial_no_support_extruder] == \"PLA-CF\") || (filament_type[initial_no_support_extruder] == \"PETG\")) && (nozzle_diameter[initial_no_support_extruder] == 0.2)}\nM620.10 A0 F74.8347 H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\nM620.10 A1 F74.8347 H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\n{else}\nM620.10 A0 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60*0.8} H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\nM620.10 A1 F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60*0.8} H{nozzle_diameter[initial_no_support_extruder]} T{flush_temperatures[initial_no_support_extruder]} P{nozzle_temperature_initial_layer[initial_no_support_extruder]} S1\n{endif}\n\nM620.11 P0 I[initial_no_support_extruder] E0\n\n{if long_retraction_when_ec }\nM620.11 K1 I[initial_no_support_extruder] R{retraction_distance_when_ec} F{max((flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60), 200)}\n{else}\nM620.11 K0 I[initial_no_support_extruder] R0\n{endif}\n\nM628 S1\n{if filament_type[initial_no_support_extruder] == \"TPU\"}\n    M620.11 S0 L0 I[initial_no_support_extruder] E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{else}\n{if (filament_type[initial_no_support_extruder] == \"PA\") ||  (filament_type[initial_no_support_extruder] == \"PA-GF\")}\n    M620.11 S1 L0 I[initial_no_support_extruder] R4 D2 E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{else}\n    M620.11 S1 L0 I[initial_no_support_extruder] R10 D8 E-{retraction_distances_when_cut[initial_no_support_extruder]} F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60}\n{endif}\n{endif}\nM629\n\nM620 S[initial_no_support_extruder]A   ; switch material if AMS exist\nM1002 gcode_claim_action : 4\nM1002 set_filament_type:UNKNOWN\nM400\nT[initial_no_support_extruder]\nM400\nM628 S0\nM629\nM400\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM621 S[initial_no_support_extruder]A\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]}\nM400\nM106 P1 S0\n\nG29.2 S1\n;===== prepare print temperature and material ==========\n\nM400\n;M73 P99\n\n;===== auto extrude cali start =========================\nM975 S1\nM1002 judge_flag extrude_cali_flag\n\nM622 J0\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\nM623\n\nM622 J1\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M1002 gcode_claim_action : 8\n\n    M109 S{nozzle_temperature[initial_no_support_extruder]}\n\n    G90\n    M83\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\n\n    M400\n    M106 P1 S255\n    M400 S5\n    M106 P1 S0\n    G150.3\nM623\n\nM622 J2\n    M1002 set_filament_type:{filament_type[initial_no_support_extruder]}\n    M1002 gcode_claim_action : 8\n\n    M109 S{nozzle_temperature[initial_no_support_extruder]}\n\n    G90\n    M83\n    M983.3 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4} A0.4 ; cali dynamic extrusion compensation\n\n    M400\n    M106 P1 S255\n    M400 S5\n    M106 P1 S0\n    G150.3\nM623\n\n;===== auto extrude cali end =========================\n\n{if filament_type[initial_no_support_extruder] == \"TPU\"}\n    G150.2\n    G150.1\n    G150.2\n    G150.1\n    G150.2\n    G150.1\n{else}\n    M106 P1 S0\n    M400 S2\n    M109 S{nozzle_temperature[initial_no_support_extruder]} ; wait tmpr to extrude\n    M83\n    {if(nozzle_diameter == 0.8)}\n        G1 E60 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    {else}\n        G1 E45 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    {endif}\n    G1 E-3 F1800\n    M400 P500\n    G150.2\n    G150.1\n{endif}\n\nG91\nG1 Y-16 F12000 ; move away from the trash bin\nG90\n\nM400\n;M73 P99\n\n;===== wipe right nozzle start =====\n\nM1002 gcode_claim_action : 14\n    G150 T{nozzle_temperature_initial_layer[initial_no_support_extruder]}\n    {if (overall_chamber_temperature >= 40)}\n        G150 T{nozzle_temperature_initial_layer[initial_no_support_extruder] - 80}\n    {endif}\nM106 S255 ; turn on fan to cool the nozzle\n\n;===== wipe left nozzle end =====\n\nM400\n;M73 P99\n\n{if (overall_chamber_temperature >= 40)}\n    M1002 gcode_claim_action : 49\n    M191 S[overall_chamber_temperature] ; wait for chamber temp\n{endif}\n\nM400\n;M73 P99\n\n;===== bed leveling ==================================\n\nM1002 judge_flag g29_before_print_flag\n\nM190 S[bed_temperature_initial_layer_single]; ensure bed temp\nM109 S140 A\nM106 S0 ; turn off fan , too noisy\n\nG91\nG1 Z5 F1200\nG90\nG1 X175 Y160 F30000\n\nM622 J1\n    M1002 gcode_claim_action : 1\n    G29.20 A3\n    G29 A1 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R \n    M400\n    M500 ; save cali data\nM623\n    \nM622 J2\n    M1002 gcode_claim_action : 1\n    {if has_tpu_in_first_layer}\n        G29.20 A3\n        G29 A1 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R\n    {else}\n        G29.20 A4\n        G29 A2 O X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]} R\n    {endif}\n    M400\n    M500 ; save cali data\nM623\n\nM622 J0\n    G28 R\nM623\n\n;===== bed leveling end ================================\n\n;===== z ofst cali start =====\n\n    M190 S[bed_temperature_initial_layer_single]; ensure bed temp\n\n    G383 O0 M2 T140\n    M500\n\n;===== z ofst cali end =====\n\nG39.1 ; cali nozzle wrapped detection pos\nM500\n\nG90\nG1 Z5 F1200\nG1 X270 Y-0.5 F60000\nG28.140 S0 ; cali pre-extrude z pos\n\nM141 S[overall_chamber_temperature]\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} A\n\n;===== mech mode sweep start =====\n    M1002 gcode_claim_action : 3\n\n    G90\n    G1 Z5 F1200\n    G1 X187 Y160 F20000\n    T1000\n    M400 P200\n\n    M970.3 Q1 A5 K0 O1\n    M974 Q1 S2 P0\n\n    M970.3 Q0 A5 K0 O1\n    M974 Q0 S2 P0\n\n    M970.2 Q2 K0 W38 Z0.01\n    M974 Q2 S2 P0\n    M500\n\n    M975 S1\n;===== mech mode sweep end =====\n\nM400\n;M73 P99\n\nG150.3 ; move to garbage can to wait for temp\nM1026\nG29.9\n\n;===== xy ofst cali start =====\n\nM1002 judge_flag auto_cali_toolhead_offset_flag\n\nM622 J0\n    M1012.5 N1 R1\n    M500\nM623\n\nM622 J1\n    M1002 gcode_claim_action : 39\n    M141 S0\n    M620.17 T0 S{nozzle_temperature_initial_layer[(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])]} L{(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])}\n    M620.17 T1 S{nozzle_temperature_initial_layer[(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])]} L{(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])}\n    G383 O1 T{nozzle_temperature_initial_layer[initial_no_support_extruder]} L{initial_no_support_extruder}\n    M500\n    M141 S[overall_chamber_temperature]\nM623\n\nM622 J2\n    M1002 gcode_claim_action : 39\n    M141 S0\n    M620.17 T0 S{nozzle_temperature_initial_layer[(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])]} L{(first_non_support_filaments[0] != -1 ? first_non_support_filaments[0] : first_filaments[0])}\n    M620.17 T1 S{nozzle_temperature_initial_layer[(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])]} L{(first_non_support_filaments[1] != -1 ? first_non_support_filaments[1] : first_filaments[1])}\n    G383.3 T{nozzle_temperature_initial_layer[initial_no_support_extruder]} L{initial_no_support_extruder}\n    M500\n    M141 S[overall_chamber_temperature]\nM623\n;===== xy ofst cali end =====\n\nM400\n;M73 P99\n\nM1002 gcode_claim_action : 0\nM400\n\n;============switch again==================\n\nM211 X0 Y0 Z0 ;turn off soft endstop\nG91\nG1 Z6 F1200\nG90\nM1002 set_filament_type:{filament_type[initial_no_support_extruder]}\nM620 S[initial_no_support_extruder]A\nM400\nT[initial_no_support_extruder]\nM400\nM628 S0\nM629\nM400\nM621 S[initial_no_support_extruder]A\n\n;============switch again==================\n\nM400\n;M73 P99\n\n;===== wait temperature reaching the reference value =======\n\nM104 S{nozzle_temperature_initial_layer[initial_no_support_extruder]} ; rise to print tmpr\n\nM140 S[bed_temperature_initial_layer_single] \nM190 S[bed_temperature_initial_layer_single] \n\n    ;========turn off light and fans =============\n    M960 S1 P0 ; turn off laser\n    M960 S2 P0 ; turn off laser\n    M106 S0 ; turn off fan\n    M106 P2 S0 ; turn off big fan\n    ;==== set ext toodhead cooling fan ==== \n    {if (min_vitrification_temperature <= 50)}\n    M106 P9 S255\n    {endif}\n    ;============set motor current==================\n    M400 S1\n\n;===== wait temperature reaching the reference value =======\n\nM400\n;M73 P99\n\n;===== for Textured PEI Plate , lower the nozzle as the nozzle was touching topmost of the texture when homing ==\n    {if curr_bed_type==\"Textured PEI Plate\"}\n        {if nozzle_diameter[initial_no_support_extruder] == 0.2}\n            G29.1 Z{-0.01} ; for Textured PEI Plate\n        {else}\n            G29.1 Z{-0.02} ; for Textured PEI Plate\n        {endif}\n    {else}\n        {if nozzle_diameter[initial_no_support_extruder] == 0.2}\n            G29.1 Z{0.01} ; for Textured PEI Plate\n        {endif}\n    {endif}\n    \nG150.1\n\nM975 S1 ; turn on mech mode supression\nM983.4 S1 ; turn on deformation compensation \nG29.2 S1 ; turn on pos comp\nG29.7 S1\n\nG90\nG1 Z5 F1200\nG1 Y295 F30000\nG1 Y265 F18000\n\n;===== nozzle load line ===============================\n    G29.2 S1 ; ensure z comp turn on\n    G90\n    M83\n    G1 Z5 F1200\n    G1 X270 Y-0.5 F60000\n    G28.14 R0\n    G29.2 S0\n    G91\n    G1 Z0.8 F1200\n    G90\n    G1 X250 F60000\n    M109 S{nozzle_temperature_initial_layer[initial_no_support_extruder]}\n    M83\n{if (filament_type[initial_no_support_extruder] == \"TPU\")}\n    G1 E5 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n{endif}\n    G1 E5 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    G1 X290 E10 F{filament_max_volumetric_speed[initial_no_support_extruder]/2.4053*60}\n    G91\n    G3 Z0.4 I1.217 J0 P1 F60000\n    G90\n    M83\n    G29.2 S1 ; ensure z comp turn on\n;===== noozle load line end ===========================\n\nM400\n;M73 P99\n\nM993 A1 B1 C1 ; nozzle cam detection allowed.\n\n{if (filament_type[initial_no_support_extruder] == \"TPU\")}\nM1015.3 S1;enable tpu clog detect\n{else}\nM1015.3 S0;disable tpu clog detect\n{endif}\n\n{if (filament_type[initial_no_support_extruder] == \"PLA\") ||  (filament_type[initial_no_support_extruder] == \"PETG\")\n ||  (filament_type[initial_no_support_extruder] == \"PLA-CF\")  ||  (filament_type[initial_no_support_extruder] == \"PETG-CF\")}\nM1015.4 S1 K1 H[nozzle_diameter] ;enable E air printing detect\n{else}\nM1015.4 S0 K0 H[nozzle_diameter] ;disable E air printing detect\n{endif}\n\nM620.6 I[initial_no_support_extruder] W1 ;enable ams air printing detect\n\nM211 Z1\nG29.99\n\n\n",
+    "machine_switch_extruder_time": "5.6",
+    "machine_unload_filament_time": "30",
+    "master_extruder_id": "2",
+    "max_bridge_length": "0",
+    "max_layer_height": [
+        "0.28",
+        "0.28"
+    ],
+    "max_travel_detour_distance": "0",
+    "min_bead_width": "85%",
+    "min_feature_size": "25%",
+    "min_layer_height": [
+        "0.08",
+        "0.08"
+    ],
+    "minimum_sparse_infill_area": "15",
+    "mmu_segmented_region_interlocking_depth": "0",
+    "mmu_segmented_region_max_width": "0",
+    "name": "project_settings",
+    "no_slow_down_for_cooling_on_outwalls": [
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "nozzle_diameter": [
+        "0.4",
+        "0.4"
+    ],
+    "nozzle_flush_dataset": [
+        "1",
+        "2",
+        "1",
+        "2",
+        "2"
+    ],
+    "nozzle_height": "4",
+    "nozzle_temperature": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_initial_layer": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_range_high": [
+        "240",
+        "240",
+        "240",
+        "240"
+    ],
+    "nozzle_temperature_range_low": [
+        "190",
+        "190",
+        "190",
+        "190"
+    ],
+    "nozzle_type": [
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel",
+        "hardened_steel"
+    ],
+    "nozzle_volume": [
+        "130",
+        "133",
+        "145",
+        "148",
+        "148"
+    ],
+    "nozzle_volume_type": [
+        "Standard",
+        "Standard"
+    ],
+    "only_one_wall_first_layer": "1",
+    "ooze_prevention": "0",
+    "other_layers_print_sequence": [
+        "0"
+    ],
+    "other_layers_print_sequence_nums": "0",
+    "outer_wall_acceleration": [
+        "2000",
+        "2000",
+        "2000",
+        "2000",
+        "2000"
+    ],
+    "outer_wall_jerk": "9",
+    "outer_wall_line_width": "0.42",
+    "outer_wall_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "overhang_1_4_speed": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "overhang_2_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "overhang_3_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "overhang_fan_speed": [
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "overhang_fan_threshold": [
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "overhang_threshold_participating_cooling": [
+        "95%",
+        "95%",
+        "95%",
+        "95%"
+    ],
+    "overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "override_filament_scarf_seam_setting": "0",
+    "override_process_overhang_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "physical_extruder_map": [
+        "1",
+        "0"
+    ],
+    "post_process": [],
+    "pre_start_fan_time": [
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "precise_outer_wall": "0",
+    "precise_z_height": "0",
+    "pressure_advance": [
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02"
+    ],
+    "prime_tower_brim_width": "-1",
+    "prime_tower_enable_framework": "0",
+    "prime_tower_extra_rib_length": "0",
+    "prime_tower_fillet_wall": "1",
+    "prime_tower_flat_ironing": "1",
+    "prime_tower_infill_gap": "150%",
+    "prime_tower_lift_height": "-1",
+    "prime_tower_lift_speed": "90",
+    "prime_tower_max_speed": "90",
+    "prime_tower_rib_wall": "0",
+    "prime_tower_rib_width": "8",
+    "prime_tower_skip_points": "1",
+    "prime_tower_width": "230",
+    "prime_volume_mode": "Default",
+    "print_compatible_printers": [
+        "Bambu Lab H2S 0.4 nozzle"
+    ],
+    "print_extruder_id": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "2"
+    ],
+    "print_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive TPU High Flow"
+    ],
+    "print_flow_ratio": "1",
+    "print_sequence": "by layer",
+    "print_settings_id": "Bambu_Lumina",
+    "printable_area": [
+        "0x0",
+        "350x0",
+        "350x320",
+        "0x320"
+    ],
+    "printable_height": "325",
+    "printer_extruder_id": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "2"
+    ],
+    "printer_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive TPU High Flow"
+    ],
+    "printer_model": "Bambu Lab H2S",
+    "printer_notes": "",
+    "printer_settings_id": "Bambu Lab H2S 0.4 nozzle",
+    "printer_structure": "corexy",
+    "printer_technology": "FFF",
+    "printer_variant": "0.4",
+    "printhost_authorization_type": "key",
+    "printhost_ssl_ignore_revoke": "0",
+    "printing_by_object_gcode": "",
+    "process_notes": "",
+    "raft_contact_distance": "0.1",
+    "raft_expansion": "1.5",
+    "raft_first_layer_density": "90%",
+    "raft_first_layer_expansion": "-1",
+    "raft_layers": "0",
+    "reduce_crossing_wall": "0",
+    "reduce_fan_stop_start_freq": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "reduce_infill_retraction": "1",
+    "required_nozzle_HRC": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "resolution": "0.012",
+    "retract_before_wipe": [
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "retract_length_toolchange": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "retract_lift_above": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_lift_below": [
+        "319",
+        "319",
+        "319",
+        "319",
+        "319"
+    ],
+    "retract_restart_extra": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_restart_extra_toolchange": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retract_when_changing_layer": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "retraction_distances_when_cut": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "retraction_distances_when_ec": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "retraction_length": [
+        "0.8",
+        "0.8",
+        "0.8",
+        "0.8",
+        "0.8"
+    ],
+    "retraction_minimum_travel": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "retraction_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "role_base_wipe_speed": "1",
+    "scan_first_layer": "0",
+    "scarf_angle_threshold": "155",
+    "seam_gap": "15%",
+    "seam_placement_away_from_overhangs": "0",
+    "seam_position": "aligned",
+    "seam_slope_conditional": "1",
+    "seam_slope_entire_loop": "0",
+    "seam_slope_gap": "0",
+    "seam_slope_inner_walls": "1",
+    "seam_slope_min_length": "10",
+    "seam_slope_start_height": "10%",
+    "seam_slope_steps": "10",
+    "seam_slope_type": "none",
+    "silent_mode": "0",
+    "single_extruder_multi_material": "1",
+    "skeleton_infill_density": "100%",
+    "skeleton_infill_line_width": "0.42",
+    "skin_infill_density": "100%",
+    "skin_infill_depth": "2",
+    "skin_infill_line_width": "0.42",
+    "skirt_distance": "2",
+    "skirt_height": "1",
+    "skirt_loops": "0",
+    "slice_closing_radius": "0.049",
+    "slicing_mode": "regular",
+    "slow_down_for_layer_cooling": [
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "slow_down_layer_time": [
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "slow_down_min_speed": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "slowdown_end_acc": [
+        "100000",
+        "100000",
+        "100000",
+        "100000",
+        "100000"
+    ],
+    "slowdown_end_height": [
+        "400",
+        "400",
+        "400",
+        "400",
+        "400"
+    ],
+    "slowdown_end_speed": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "slowdown_start_acc": [
+        "100000",
+        "100000",
+        "100000",
+        "100000",
+        "100000"
+    ],
+    "slowdown_start_height": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "slowdown_start_speed": [
+        "1000",
+        "1000",
+        "1000",
+        "1000",
+        "1000"
+    ],
+    "small_perimeter_speed": [
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "small_perimeter_threshold": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "smooth_coefficient": "4",
+    "smooth_speed_discontinuity_area": "1",
+    "solid_infill_filament": "0",
+    "sparse_infill_acceleration": [
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "sparse_infill_anchor": "400%",
+    "sparse_infill_anchor_max": "20",
+    "sparse_infill_density": "100%",
+    "sparse_infill_filament": "0",
+    "sparse_infill_lattice_angle_1": "-45",
+    "sparse_infill_lattice_angle_2": "45",
+    "sparse_infill_line_width": "0.42",
+    "sparse_infill_pattern": "zig-zag",
+    "sparse_infill_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "spiral_mode": "0",
+    "spiral_mode_max_xy_smoothing": "200%",
+    "spiral_mode_smooth": "0",
+    "standby_temperature_delta": "-5",
+    "start_end_points": [
+        "30x-3",
+        "54x245"
+    ],
+    "supertack_plate_temp": [
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "supertack_plate_temp_initial_layer": [
+        "40",
+        "40",
+        "40",
+        "40"
+    ],
+    "support_air_filtration": "0",
+    "support_angle": "0",
+    "support_base_pattern": "default",
+    "support_base_pattern_spacing": "2.5",
+    "support_bottom_interface_spacing": "0.5",
+    "support_bottom_z_distance": "0.08",
+    "support_chamber_temp_control": "1",
+    "support_cooling_filter": "1",
+    "support_critical_regions_only": "0",
+    "support_expansion": "0",
+    "support_filament": "0",
+    "support_interface_bottom_layers": "2",
+    "support_interface_filament": "0",
+    "support_interface_loop_pattern": "0",
+    "support_interface_not_for_body": "1",
+    "support_interface_pattern": "auto",
+    "support_interface_spacing": "0.5",
+    "support_interface_speed": [
+        "80",
+        "80",
+        "80",
+        "80",
+        "80"
+    ],
+    "support_interface_top_layers": "2",
+    "support_ironing_direction": "0",
+    "support_ironing_flow": "10%",
+    "support_ironing_inset": "0",
+    "support_ironing_pattern": "zig-zag",
+    "support_ironing_spacing": "0.15",
+    "support_ironing_speed": "30",
+    "support_line_width": "0.42",
+    "support_object_first_layer_gap": "0.2",
+    "support_object_skip_flush": "0",
+    "support_object_xy_distance": "0.35",
+    "support_on_build_plate_only": "0",
+    "support_remove_small_overhang": "1",
+    "support_speed": [
+        "150",
+        "150",
+        "150",
+        "150",
+        "150"
+    ],
+    "support_style": "default",
+    "support_threshold_angle": "15",
+    "support_top_z_distance": "0.08",
+    "support_type": "tree(auto)",
+    "symmetric_infill_y_axis": "0",
+    "temperature_vitrification": [
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "template_custom_gcode": "",
+    "textured_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "textured_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "thick_bridges": "0",
+    "thumbnail_size": [
+        "50x50"
+    ],
+    "time_lapse_gcode": ";======== H2D 20251104========\n; SKIPPABLE_START\n; SKIPTYPE: timelapse\nM622.1 S1 ; for prev firmware, default turned on\n\nM1002 judge_flag timelapse_record_flag\n\n    M622 J1\n    M993 A2 B2 C2\n    M993 A0 B0 C0\n    \n    M622.1 S0 ; for prev firmware, default turn off\n    M1002 set_flag smooth_safe_pos_suppoprt_flag=1\n    M1002 judge_flag smooth_safe_pos_suppoprt_flag\n    \n    M622 J0\n        {if !spiral_mode && !(has_timelapse_safe_pos && timelapse_type == 0) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                M83\n                G1 Z{max_layer_z + 0.4} F1200\n                M400\n            {endif}\n        {endif}\n\n        {if has_timelapse_safe_pos && timelapse_type == 0 && !spiral_mode}\n            M9711 M{timelapse_type} E{most_used_physical_extruder_id} X{timelapse_pos_x} Y{timelapse_pos_y} Z{layer_z + 0.4} S11 C10 O0 T3000\n        {else}\n            {if spiral_mode}\n                M971 S11 C10 O0\n                M1004 S5 P1  ; external shutter\n            {else}\n                M9711 M{timelapse_type} E{most_used_physical_extruder_id} Z{layer_z + 0.4} S11 C10 O0 T3000\n            {endif}\n        {endif}\n\n        {if !spiral_mode && !(has_timelapse_safe_pos && timelapse_type == 0) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                G90\n                G1 Z{max_layer_z + 3.0} F1200\n                G1 Y295 F30000\n                G1 Y265 F18000\n                M83\n            {endif}\n        {endif}\n    M623\n\n    M622 J1\n        {if !spiral_mode && !(has_timelapse_safe_pos) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                M83\n                G1 Z{max_layer_z + 0.4} F1200\n                M400\n            {endif}\n        {endif}\n\n        {if has_timelapse_safe_pos && !spiral_mode}\n            M9711 M{timelapse_type} E{most_used_physical_extruder_id} U{timelapse_pos_x} V{timelapse_pos_y} Z{layer_z + 0.4} S11 C10 O0 T3000\n        {else}\n            {if spiral_mode}\n                M971 S11 C10 O0\n                M1004 S5 P1  ; external shutter\n            {else}\n                M9711 M{timelapse_type} E{most_used_physical_extruder_id} Z{layer_z + 0.4} S11 C10 O0 T3000\n            {endif}\n        {endif}\n\n        {if !spiral_mode && !(has_timelapse_safe_pos) }\n            {if most_used_physical_extruder_id!= curr_physical_extruder_id || timelapse_type == 1}\n                G90\n                G1 Z{max_layer_z + 3.0} F1200\n                G1 Y295 F30000\n                G1 Y265 F18000\n                M83\n            {endif}\n        {endif}\n    M623\n\n    M993 A3 B3 C3\n\nM623\n; SKIPPABLE_END\n",
+    "timelapse_type": "0",
+    "top_area_threshold": "200%",
+    "top_color_penetration_layers": "9",
+    "top_one_wall_type": "all top",
+    "top_shell_layers": "0",
+    "top_shell_thickness": "1",
+    "top_solid_infill_flow_ratio": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "top_surface_acceleration": [
+        "2000",
+        "2000",
+        "2000",
+        "2000",
+        "2000"
+    ],
+    "top_surface_density": "100%",
+    "top_surface_jerk": "9",
+    "top_surface_line_width": "0.42",
+    "top_surface_pattern": "zig-zag",
+    "top_surface_speed": [
+        "120",
+        "120",
+        "120",
+        "120",
+        "120"
+    ],
+    "top_z_overrides_xy_distance": "0",
+    "travel_acceleration": [
+        "10000",
+        "10000",
+        "10000",
+        "10000",
+        "10000"
+    ],
+    "travel_jerk": "9",
+    "travel_short_distance_acceleration": [
+        "250",
+        "250",
+        "250",
+        "250",
+        "250"
+    ],
+    "travel_speed": [
+        "500",
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "travel_speed_z": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "tree_support_branch_angle": "45",
+    "tree_support_branch_diameter": "2",
+    "tree_support_branch_diameter_angle": "5",
+    "tree_support_branch_distance": "5",
+    "tree_support_wall_count": "-1",
+    "upward_compatible_machine": [
+        "Bambu Lab H2D Pro 0.4 nozzle"
+    ],
+    "use_firmware_retraction": "0",
+    "use_relative_e_distances": "1",
+    "version": "02.05.00.66",
+    "vertical_shell_speed": [
+        "80%",
+        "80%",
+        "80%",
+        "80%",
+        "80%"
+    ],
+    "volumetric_speed_coefficients": [
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0"
+    ],
+    "wall_distribution_count": "1",
+    "wall_filament": "0",
+    "wall_generator": "arachne",
+    "wall_loops": "1",
+    "wall_sequence": "inner wall/outer wall",
+    "wall_transition_angle": "10",
+    "wall_transition_filter_deviation": "25%",
+    "wall_transition_length": "100%",
+    "wipe": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "wipe_distance": [
+        "2",
+        "2",
+        "2",
+        "2",
+        "2"
+    ],
+    "wipe_speed": "80%",
+    "wipe_tower_no_sparse_layers": "0",
+    "wipe_tower_rotation_angle": "0",
+    "wipe_tower_x": [
+        "80"
+    ],
+    "wipe_tower_y": [
+        "250"
+    ],
+    "wrapping_detection_gcode": ";======== H2D 20250729 clumping ========\n{if !spiral_mode}\n    M622.1 S0 ; for previous firmware, default turn off\n    M1002 set_flag g39_forced_detection_flag=1\n    M1002 judge_flag g39_forced_detection_flag\n    M622 J1\n        {if layer_num == 3 || layer_num == 10 || layer_num == 19}\n            M993 A2 B2 C2 ; nozzle cam detection allow status save.\n            M993 A0 B0 C0 ; nozzle cam detection not allowed.\n\n            M400 P100\n\n            G39\n\n            G90\n            G1 Y295 F30000\n            G1 Y265 F18000\n            \n            M993 A3 B3 C3 ; nozzle cam detection allow status restore.\n        {endif}\n    M623\n{endif}\n",
+    "wrapping_detection_layers": "20",
+    "wrapping_exclude_area": [
+        "145x310",
+        "256x310",
+        "256x326",
+        "145x326"
+    ],
+    "xy_contour_compensation": "0",
+    "xy_hole_compensation": "0",
+    "z_direction_outwall_speed_continuous": "1",
+    "z_hop": [
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4",
+        "0.4"
+    ],
+    "z_hop_types": [
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift",
+        "Auto Lift"
+    ]
+}
\ No newline at end of file
diff --git a/printer_profiles/bambu_p1p.json b/printer_profiles/bambu_p1p.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_p1p.json
@@ -0,0 +1,2611 @@
+{
+    "accel_to_decel_enable": "0",
+    "accel_to_decel_factor": "50%",
+    "activate_air_filtration": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "additional_cooling_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "apply_scarf_seam_on_circles": "1",
+    "apply_top_surface_compensation": "0",
+    "auxiliary_fan": "0",
+    "avoid_crossing_wall_includes_support": "0",
+    "bed_custom_model": "",
+    "bed_custom_texture": "",
+    "bed_exclude_area": [],
+    "bed_temperature_formula": "by_first_filament",
+    "before_layer_change_gcode": "",
+    "best_object_pos": "0.5,0.5",
+    "bottom_color_penetration_layers": "3",
+    "bottom_shell_layers": "0",
+    "bottom_shell_thickness": "0",
+    "bottom_surface_density": "100%",
+    "bottom_surface_pattern": "monotonic",
+    "bridge_angle": "0",
+    "bridge_flow": "1",
+    "bridge_no_support": "0",
+    "bridge_speed": [
+        "50",
+        "50"
+    ],
+    "brim_object_gap": "0.1",
+    "brim_type": "auto_brim",
+    "brim_width": "5",
+    "chamber_temperatures": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "change_filament_gcode": ";=P1S 20251031=\nM620 S[next_extruder]A\nM204 S9000\nG1 Z{max_layer_z + 3.0} F1200\n\nG1 X70 F21000\nG1 Y245\nG1 Y265 F3000\nM400\nM106 P1 S0\nM106 P2 S0\n{if old_filament_temp > 142 && next_extruder < 255}\nM104 S[old_filament_temp]\n{endif}\n{if long_retractions_when_cut[previous_extruder]}\nM620.11 S1 I[previous_extruder] E-{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\n{else}\nM620.11 S0\n{endif}\nM400\nG1 X90 F3000\nG1 Y255 F4000\nG1 X100 F5000\nG1 X120 F15000\nG1 X20 Y50 F21000\nG1 Y-3\n{if toolchange_count == 2}\n; get travel path for change filament\nM620.1 X[travel_point_1_x] Y[travel_point_1_y] F21000 P0\nM620.1 X[travel_point_2_x] Y[travel_point_2_y] F21000 P1\nM620.1 X[travel_point_3_x] Y[travel_point_3_y] F21000 P2\n{endif}\nM620.1 E F{flush_volumetric_speeds[previous_extruder]/2.4053*60} T{flush_temperatures[previous_extruder]}\nT[next_extruder]\nM620.1 E F{flush_volumetric_speeds[next_extruder]/2.4053*60} T{flush_temperatures[next_extruder]}\n\n{if next_extruder < 255}\n{if long_retractions_when_cut[previous_extruder]}\nM620.11 S1 I[previous_extruder] E{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nM628 S1\nG92 E0\nG1 E{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nM400\nM629 S1\n{else}\nM620.11 S0\n{endif}\nG92 E0\n{if flush_length_1 > 1}\nM83\n; FLUSH_START\n; always use highest temperature to flush\nM400\n{if filament_type[next_extruder] == \"PETG\"}\nM109 S260\n{elsif filament_type[next_extruder] == \"PVA\"}\nM109 S210\n{else}\nM109 S{flush_temperatures[next_extruder]}\n{endif}\n{if flush_length_1 > 23.7}\nG1 E23.7 F{flush_volumetric_speeds[previous_extruder]/2.4053*60} ; do not need pulsatile flushing for start part\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\n{else}\nG1 E{flush_length_1} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\n{endif}\n; FLUSH_END\nG1 E-[old_retract_length_toolchange] F1800\nG1 E[old_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_2 > 1}\n\nG91\nG1 X3 F12000; move aside to extrude\nG90\nM83\n\n; FLUSH_START\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\n; FLUSH_END\nG1 E-[new_retract_length_toolchange] F1800\nG1 E[new_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_3 > 1}\n\nG91\nG1 X3 F12000; move aside to extrude\nG90\nM83\n\n; FLUSH_START\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\n; FLUSH_END\nG1 E-[new_retract_length_toolchange] F1800\nG1 E[new_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_4 > 1}\n\nG91\nG1 X3 F12000; move aside to extrude\nG90\nM83\n\n; FLUSH_START\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\n; FLUSH_END\n{endif}\n; FLUSH_START\nM400\nM109 S[new_filament_temp]\nG1 E2 F{flush_volumetric_speeds[next_extruder]/2.4053*60} ;Compensate for filament spillage during waiting temperature\n; FLUSH_END\nM400\nG92 E0\nG1 E-[new_retract_length_toolchange] F1800\nM106 P1 S255\nM400 S3\n\nG1 X70 F5000\nG1 X90 F3000\nG1 Y255 F4000\nG1 X105 F5000\nG1 Y265 F5000\nG1 X70 F10000\nG1 X100 F5000\nG1 X70 F10000\nG1 X100 F5000\n\nG1 X70 F10000\nG1 X80 F15000\nG1 X60\nG1 X80\nG1 X60\nG1 X80 ; shake to put down garbage\nG1 X100 F5000\nG1 X165 F15000; wipe and shake\nG1 Y256 ; move Y to aside, prevent collision\nM400\nG1 Z{max_layer_z + 3.0} F3000\n{if layer_z <= (initial_layer_print_height + 0.001)}\nM204 S[initial_layer_acceleration]\n{else}\nM204 S[default_acceleration]\n{endif}\n{else}\nG1 X[x_after_toolchange] Y[y_after_toolchange] Z[z_after_toolchange] F12000\n{endif}\nM621 S[next_extruder]A\n",
+    "circle_compensation_manual_offset": "0",
+    "circle_compensation_speed": [
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200"
+    ],
+    "close_fan_the_first_x_layers": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "complete_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "cool_plate_temp": [
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cool_plate_temp_initial_layer": [
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cooling_filter_enabled": "0",
+    "cooling_perimeter_transition_distance": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "cooling_slowdown_logic": [
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling"
+    ],
+    "counter_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "counter_coef_2": [
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008"
+    ],
+    "counter_coef_3": [
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041"
+    ],
+    "counter_limit_max": [
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033"
+    ],
+    "counter_limit_min": [
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035"
+    ],
+    "curr_bed_type": "Textured PEI Plate",
+    "default_acceleration": [
+        "10000",
+        "10000"
+    ],
+    "default_filament_colour": [
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "default_filament_profile": [
+        "Bambu PLA Basic @BBL P1P 0.4 nozzle"
+    ],
+    "default_jerk": "0",
+    "default_nozzle_volume_type": [
+        "Standard"
+    ],
+    "default_print_profile": "0.20mm Standard @BBL P1P",
+    "deretraction_speed": [
+        "30",
+        "30"
+    ],
+    "detect_floating_vertical_shell": "1",
+    "detect_narrow_internal_solid_infill": "0",
+    "detect_overhang_wall": "1",
+    "detect_thin_wall": "0",
+    "diameter_limit": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "different_settings_to_system": [
+        "bottom_shell_layers;detect_narrow_internal_solid_infill;elefant_foot_compensation;initial_layer_flow_ratio;initial_layer_infill_speed;initial_layer_line_width;initial_layer_print_height;inner_wall_speed;internal_solid_infill_speed;layer_height;only_one_wall_first_layer;outer_wall_speed;prime_tower_rib_wall;prime_tower_width;skeleton_infill_density;skin_infill_density;sparse_infill_density;sparse_infill_pattern;sparse_infill_speed;top_shell_layers;top_surface_speed;wall_loops",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "draft_shield": "disabled",
+    "during_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "elefant_foot_compensation": "0",
+    "embedding_wall_into_infill": "0",
+    "enable_arc_fitting": "1",
+    "enable_circle_compensation": "0",
+    "enable_height_slowdown": [
+        "0",
+        "0"
+    ],
+    "enable_long_retraction_when_cut": "2",
+    "enable_overhang_bridge_fan": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_overhang_speed": [
+        "1",
+        "1"
+    ],
+    "enable_pre_heating": "0",
+    "enable_pressure_advance": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_prime_tower": "1",
+    "enable_support": "0",
+    "enable_support_ironing": "0",
+    "enable_tower_interface_features": "0",
+    "enable_wrapping_detection": "0",
+    "enforce_support_layers": "0",
+    "eng_plate_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "eng_plate_temp_initial_layer": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "ensure_vertical_shell_thickness": "enabled",
+    "exclude_object": "1",
+    "extruder_ams_count": [
+        "1#0|4#0",
+        ""
+    ],
+    "extruder_clearance_dist_to_rod": "33",
+    "extruder_clearance_height_to_lid": "90",
+    "extruder_clearance_height_to_rod": "34",
+    "extruder_clearance_max_radius": "68",
+    "extruder_colour": [
+        "#018001"
+    ],
+    "extruder_max_nozzle_count": [
+        "1"
+    ],
+    "extruder_nozzle_stats": [
+        "Standard#1"
+    ],
+    "extruder_offset": [
+        "0x2"
+    ],
+    "extruder_printable_area": [
+        "0x0,256x0,256x256,0x256"
+    ],
+    "extruder_printable_height": [
+        "256"
+    ],
+    "extruder_type": [
+        "Direct Drive"
+    ],
+    "extruder_variant_list": [
+        "Direct Drive Standard,Direct Drive High Flow"
+    ],
+    "fan_cooling_layer_time": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "fan_direction": "left",
+    "fan_max_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "fan_min_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_adaptive_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_adhesiveness_category": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_bridge_speed": [
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25"
+    ],
+    "filament_change_length": [
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5"
+    ],
+    "filament_change_length_nc": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_colour": [
+        "#FFFFFF",
+        "#0080FF",
+        "#FF00FF",
+        "#FFFF00",
+        "#000000",
+        "#FF0000",
+        "#0000FF",
+        "#00FF00"
+    ],
+    "filament_colour_type": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_cooling_before_tower": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_cost": [
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99"
+    ],
+    "filament_density": [
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26"
+    ],
+    "filament_deretraction_speed": [
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50"
+    ],
+    "filament_dev_ams_drying_ams_limitations": [
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0"
+    ],
+    "filament_dev_ams_drying_heat_distortion_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_chamber_drying_bed_temperature": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "filament_dev_chamber_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_drying_cooling_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_drying_softening_temperature": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_diameter": [
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75"
+    ],
+    "filament_enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_end_gcode": [
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n"
+    ],
+    "filament_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "filament_flow_ratio": [
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985"
+    ],
+    "filament_flush_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_flush_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ids": [
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00"
+    ],
+    "filament_is_support": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_long_retractions_when_cut": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map_mode": "Auto For Flush",
+    "filament_max_volumetric_speed": [
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29"
+    ],
+    "filament_minimal_purge_on_wipe_tower": [
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15"
+    ],
+    "filament_multi_colour": [
+        "#FFFFFF",
+        "#0080FF",
+        "#FF00FF",
+        "#FFFF00",
+        "#000000",
+        "#FF0000",
+        "#0000FF",
+        "#00FF00"
+    ],
+    "filament_notes": "",
+    "filament_nozzle_map": [
+        "1",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_1_4_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_2_4_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_overhang_3_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_pre_cooling_temperature": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_pre_cooling_temperature_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_prime_volume": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_prime_volume_nc": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_printable": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "filament_ramming_travel_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_travel_time_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_volumetric_speed": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_ramming_volumetric_speed_nc": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_retract_before_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_length_nc": [
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14"
+    ],
+    "filament_retract_restart_extra": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_when_changing_layer": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_distances_when_cut": [
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18"
+    ],
+    "filament_retraction_length": [
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4"
+    ],
+    "filament_retraction_minimum_travel": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_speed": [
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50"
+    ],
+    "filament_scarf_gap": [
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "filament_scarf_height": [
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%"
+    ],
+    "filament_scarf_length": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_scarf_seam_type": [
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none"
+    ],
+    "filament_self_index": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "3",
+        "3",
+        "4",
+        "4",
+        "5",
+        "5",
+        "6",
+        "6",
+        "7",
+        "7",
+        "8",
+        "8"
+    ],
+    "filament_settings_id": [
+        "Bambu PLA Basic @BBL P1P 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1P 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1P 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1P 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1P 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1P 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1P 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1P 0.4 nozzle"
+    ],
+    "filament_shrink": [
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "filament_soluble": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_start_gcode": [
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}"
+    ],
+    "filament_tower_interface_pre_extrusion_dist": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_tower_interface_pre_extrusion_length": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_tower_interface_print_temp": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_tower_interface_purge_volume": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "filament_tower_ironing_area": [
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_type": [
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA"
+    ],
+    "filament_velocity_adaptation_factor": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_vendor": [
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab"
+    ],
+    "filament_volume_map": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_wipe_distance": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop": [
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6"
+    ],
+    "filament_z_hop_types": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filename_format": "{input_filename_base}_{filament_type[0]}_{print_time}.gcode",
+    "fill_multiline": "1",
+    "filter_out_gap_fill": "0",
+    "first_layer_print_sequence": [
+        "0"
+    ],
+    "first_x_layer_fan_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "flush_into_infill": "0",
+    "flush_into_objects": "0",
+    "flush_into_support": "1",
+    "flush_multiplier": [
+        "1"
+    ],
+    "flush_volumes_matrix": [
+        "0",
+        "320",
+        "319",
+        "297",
+        "143",
+        "325",
+        "335",
+        "311",
+        "604",
+        "0",
+        "344",
+        "594",
+        "159",
+        "297",
+        "195",
+        "453",
+        "603",
+        "293",
+        "0",
+        "592",
+        "159",
+        "297",
+        "305",
+        "451",
+        "370",
+        "314",
+        "314",
+        "0",
+        "183",
+        "319",
+        "329",
+        "305",
+        "623",
+        "521",
+        "523",
+        "513",
+        "0",
+        "471",
+        "370",
+        "603",
+        "649",
+        "412",
+        "370",
+        "603",
+        "153",
+        "0",
+        "300",
+        "506",
+        "724",
+        "379",
+        "471",
+        "716",
+        "143",
+        "456",
+        "0",
+        "592",
+        "523",
+        "300",
+        "300",
+        "471",
+        "170",
+        "305",
+        "314",
+        "0"
+    ],
+    "flush_volumes_vector": [
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140"
+    ],
+    "from": "project",
+    "full_fan_speed_layer": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "fuzzy_skin": "none",
+    "fuzzy_skin_point_distance": "0.8",
+    "fuzzy_skin_thickness": "0.3",
+    "gap_infill_speed": [
+        "250",
+        "250"
+    ],
+    "gcode_add_line_number": "0",
+    "gcode_flavor": "marlin",
+    "grab_length": [
+        "0"
+    ],
+    "group_algo_with_time": "0",
+    "has_scarf_joint_seam": "0",
+    "head_wrap_detect_zone": [],
+    "hole_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "hole_coef_2": [
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008"
+    ],
+    "hole_coef_3": [
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415"
+    ],
+    "hole_limit_max": [
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22"
+    ],
+    "hole_limit_min": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "host_type": "octoprint",
+    "hot_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hot_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hotend_cooling_rate": [
+        "2",
+        "2"
+    ],
+    "hotend_heating_rate": [
+        "2",
+        "2"
+    ],
+    "impact_strength_z": [
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8"
+    ],
+    "independent_support_layer_height": "1",
+    "infill_combination": "0",
+    "infill_direction": "45",
+    "infill_instead_top_bottom_surfaces": "0",
+    "infill_jerk": "9",
+    "infill_lock_depth": "1",
+    "infill_rotate_step": "0",
+    "infill_shift_step": "0.4",
+    "infill_wall_overlap": "15%",
+    "inherits_group": [
+        "0.20mm Standard @BBL P1P",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "initial_layer_acceleration": [
+        "500",
+        "500"
+    ],
+    "initial_layer_flow_ratio": "1.05",
+    "initial_layer_infill_speed": [
+        "50",
+        "105"
+    ],
+    "initial_layer_jerk": "9",
+    "initial_layer_line_width": "0.42",
+    "initial_layer_print_height": "0.08",
+    "initial_layer_speed": [
+        "50",
+        "50"
+    ],
+    "initial_layer_travel_acceleration": [
+        "6000",
+        "6000"
+    ],
+    "inner_wall_acceleration": [
+        "0",
+        "0"
+    ],
+    "inner_wall_jerk": "9",
+    "inner_wall_line_width": "0.45",
+    "inner_wall_speed": [
+        "100",
+        "400"
+    ],
+    "interface_shells": "0",
+    "interlocking_beam": "0",
+    "interlocking_beam_layer_count": "2",
+    "interlocking_beam_width": "0.8",
+    "interlocking_boundary_avoidance": "2",
+    "interlocking_depth": "2",
+    "interlocking_orientation": "22.5",
+    "internal_bridge_support_thickness": "0.8",
+    "internal_solid_infill_line_width": "0.42",
+    "internal_solid_infill_pattern": "zig-zag",
+    "internal_solid_infill_speed": [
+        "100",
+        "350"
+    ],
+    "ironing_direction": "45",
+    "ironing_flow": "10%",
+    "ironing_inset": "0.21",
+    "ironing_pattern": "zig-zag",
+    "ironing_spacing": "0.15",
+    "ironing_speed": "30",
+    "ironing_type": "no ironing",
+    "is_infill_first": "0",
+    "layer_change_gcode": "; layer num/total_layer_count: {layer_num+1}/[total_layer_count]\n; update layer progress\nM73 L{layer_num+1}\nM991 S0 P{layer_num} ;notify layer change",
+    "layer_height": "0.08",
+    "line_width": "0.42",
+    "locked_skeleton_infill_pattern": "zigzag",
+    "locked_skin_infill_pattern": "crosszag",
+    "long_retractions_when_cut": [
+        "0",
+        "0"
+    ],
+    "long_retractions_when_ec": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "machine_end_gcode": ";===== date: 20230428 =====================\nM400 ; wait for buffer to clear\nG92 E0 ; zero the extruder\nG1 E-0.8 F1800 ; retract\nG1 Z{max_layer_z + 0.5} F900 ; lower z a little\nG1 X65 Y245 F12000 ; move to safe pos \nG1 Y265 F3000\n\nG1 X65 Y245 F12000\nG1 Y265 F3000\nM140 S0 ; turn off bed\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off remote part cooling fan\nM106 P3 S0 ; turn off chamber cooling fan\n\nG1 X100 F12000 ; wipe\n; pull back filament to AMS\nM620 S255\nG1 X20 Y50 F12000\nG1 Y-3\nT255\nG1 X65 F12000\nG1 Y265\nG1 X100 F12000 ; wipe\nM621 S255\nM104 S0 ; turn off hotend\n\nM622.1 S1 ; for prev firware, default turned on\nM1002 judge_flag timelapse_record_flag\nM622 J1\n    M400 ; wait all motion done\n    M991 S0 P-1 ;end smooth timelapse at safe pos\n    M400 S3 ;wait for last picture to be taken\nM623; end of \"timelapse_record_flag\"\n\nM400 ; wait all motion done\nM17 S\nM17 Z0.4 ; lower z motor current to reduce impact if there is something in the bottom\n{if (max_layer_z + 100.0) < 250}\n    G1 Z{max_layer_z + 100.0} F600\n    G1 Z{max_layer_z +98.0}\n{else}\n    G1 Z250 F600\n    G1 Z248\n{endif}\nM400 P100\nM17 R ; restore z current\n\nM220 S100  ; Reset feedrate magnitude\nM201.2 K1.0 ; Reset acc magnitude\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 0\n\nM17 X0.8 Y0.8 Z0.5 ; lower motor current to 45% power\n",
+    "machine_hotend_change_time": "0",
+    "machine_load_filament_time": "29",
+    "machine_max_acceleration_e": [
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_extruding": [
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_retracting": [
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_travel": [
+        "9000",
+        "9000",
+        "9000",
+        "9000"
+    ],
+    "machine_max_acceleration_x": [
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_y": [
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_z": [
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_jerk_e": [
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5"
+    ],
+    "machine_max_jerk_x": [
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_y": [
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_z": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "machine_max_speed_e": [
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "machine_max_speed_x": [
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_speed_y": [
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_speed_z": [
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "machine_min_extruding_rate": [
+        "0"
+    ],
+    "machine_min_travel_rate": [
+        "0"
+    ],
+    "machine_pause_gcode": "M400 U1",
+    "machine_prepare_compensation_time": "260",
+    "machine_start_gcode": ";===== machine: P1S-0.4 ========================\n;===== date: 20251031 =====================\n;===== turn on the HB fan & MC board fan =================\nM104 S75 ;set extruder temp to turn on the HB fan and prevent filament oozing from nozzle\nM710 A1 S255 ;turn on MC fan by default(P1S)\n;===== reset machine status =================\nM290 X40 Y40 Z2.6666666\nG91\nM17 Z0.4 ; lower the z-motor current\nG380 S2 Z30 F300 ; G380 is same as G38; lower the hotbed , to prevent the nozzle is below the hotbed\nG380 S2 Z-25 F300 ;\nG1 Z5 F300;\nG90\nM17 X1.2 Y1.2 Z0.75 ; reset motor current to default\nM960 S5 P1 ; turn on logo lamp\nG90\nM220 S100 ;Reset Feedrate\nM221 S100 ;Reset Flowrate\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 5\nM221 X0 Y0 Z0 ; turn off soft endstop to prevent protential logic problem\nG29.1 Z{+0.0} ; clear z-trim value first\nM204 S10000 ; init ACC set to 10m/s^2\n\n;===== heatbed preheat ====================\nM1002 gcode_claim_action:54\nM140 S[bed_temperature_initial_layer_single] ;set bed temp\nM190 S[bed_temperature_initial_layer_single] ;wait for bed temp\n\n\n\n;=============turn on fans to prevent PLA jamming=================\n{if filament_type[initial_extruder]==\"PLA\"}\n    {if (bed_temperature[initial_extruder] >45)||(bed_temperature_initial_layer[initial_extruder] >45)}\n    M106 P3 S180\n    {endif};Prevent PLA from jamming\n{endif}\nM106 P2 S100 ; turn on big fan ,to cool down toolhead\n\n;===== prepare print temperature and material ==========\nM104 S[nozzle_temperature_initial_layer] ;set extruder temp\nG91\nG0 Z10 F1200\nG90\nG28 X\nM975 S1 ; turn on\nG1 X60 F12000\nG1 Y245\nG1 Y265 F3000\nM620 M\nM620 S[initial_extruder]A   ; switch material if AMS exist\n    M109 S[nozzle_temperature_initial_layer]\n    G1 X120 F12000\n\n    G1 X20 Y50 F12000\n    G1 Y-3\n    T[initial_extruder]\n    G1 X54 F12000\n    G1 Y265\n    M400\nM621 S[initial_extruder]A\nM620.1 E F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60} T{flush_temperatures[initial_no_support_extruder]}\n\n\nM412 S1 ; ===turn on filament runout detection===\n\nM109 S250 ;set nozzle to common flush temp\nM106 P1 S0\nG92 E0\nG1 E50 F200\nM400\nM104 S[nozzle_temperature_initial_layer]\nG92 E0\nG1 E50 F200\nM400\nM106 P1 S255\nG92 E0\nG1 E5 F300\nM109 S{nozzle_temperature_initial_layer[initial_extruder]-20} ; drop nozzle temp, make filament shink a bit\nG92 E0\nG1 E-0.5 F300\n\nG1 X70 F9000\nG1 X76 F15000\nG1 X65 F15000\nG1 X76 F15000\nG1 X65 F15000; shake to put down garbage\nG1 X80 F6000\nG1 X95 F15000\nG1 X80 F15000\nG1 X165 F15000; wipe and shake\nM400\nM106 P1 S0\n;===== prepare print temperature and material end =====\n\n\n;===== wipe nozzle ===============================\nM1002 gcode_claim_action : 14\nM975 S1\nM106 S255\nG1 X65 Y230 F18000\nG1 Y264 F6000\nM109 S{nozzle_temperature_initial_layer[initial_extruder]-20}\nG1 X100 F18000 ; first wipe mouth\n\nG0 X135 Y253 F20000  ; move to exposed steel surface edge\nG28 Z P0 T300; home z with low precision,permit 300deg temperature\nG29.2 S0 ; turn off ABL\nG0 Z5 F20000\n\nG1 X60 Y265\nG92 E0\nG1 E-0.5 F300 ; retrack more\nG1 X100 F5000; second wipe mouth\nG1 X70 F15000\nG1 X100 F5000\nG1 X70 F15000\nG1 X100 F5000\nG1 X70 F15000\nG1 X100 F5000\nG1 X70 F15000\nG1 X90 F5000\nG0 X128 Y261 Z-1.5 F20000  ; move to exposed steel surface and stop the nozzle\nM104 S140 ; set temp down to heatbed acceptable\nM106 S255 ; turn on fan (G28 has turn off fan)\n\nM221 S; push soft endstop status\nM221 Z0 ;turn off Z axis endstop\nG0 Z0.5 F20000\nG0 X125 Y259.5 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y262.5\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y260.0\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y262.0\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y260.5\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y261.5\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y261.0\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 X128\nG2 I0.5 J0 F300\nG2 I0.5 J0 F300\nG2 I0.5 J0 F300\nG2 I0.5 J0 F300\n\nM109 S140 ; wait nozzle temp down to heatbed acceptable\nG2 I0.5 J0 F3000\nG2 I0.5 J0 F3000\nG2 I0.5 J0 F3000\nG2 I0.5 J0 F3000\n\nM221 R; pop softend status\nG1 Z10 F1200\nM400\nG1 Z10\nG1 F30000\nG1 X230 Y15\nG29.2 S1 ; turn on ABL\n;G28 ; home again after hard wipe mouth\nM106 S0 ; turn off fan , too noisy\n;===== wipe nozzle end ================================\n\n\n;===== bed leveling ==================================\nM1002 judge_flag g29_before_print_flag\nM622 J1\n\n    M1002 gcode_claim_action : 1\n    G29 A X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]}\n    M400\n    M500 ; save cali data\n\nM623\n;===== bed leveling end ================================\n\n;===== home after wipe mouth============================\nM1002 judge_flag g29_before_print_flag\nM622 J0\n\n    M1002 gcode_claim_action : 13\n    G28\n\nM623\n;===== home after wipe mouth end =======================\n\nM975 S1 ; turn on vibration supression\n\n\n;=============turn on fans to prevent PLA jamming=================\n{if filament_type[initial_extruder]==\"PLA\"}\n    {if (bed_temperature[initial_extruder] >45)||(bed_temperature_initial_layer[initial_extruder] >45)}\n    M106 P3 S180\n    {endif};Prevent PLA from jamming\n{endif}\nM106 P2 S100 ; turn on big fan ,to cool down toolhead\n\n\nM104 S{nozzle_temperature_initial_layer[initial_extruder]} ; set extrude temp earlier, to reduce wait time\n\n;===== mech mode fast check============================\nG1 X128 Y128 Z10 F20000\nM400 P200\nM970.3 Q1 A7 B30 C80  H15 K0\nM974 Q1 S2 P0\n\nG1 X128 Y128 Z10 F20000\nM400 P200\nM970.3 Q0 A7 B30 C90 Q0 H15 K0\nM974 Q0 S2 P0\n\nM975 S1\nG1 F30000\nG1 X230 Y15\nG28 X ; re-home XY\n;===== fmech mode fast check============================\n\n\n;===== nozzle load line ===============================\nM975 S1\nG90\nM83\nT1000\nG1 X18.0 Y1.0 Z0.8 F18000;Move to start position\nM109 S{nozzle_temperature_initial_layer[initial_extruder]}\nG1 Z0.2\nG0 E2 F300\nG0 X240 E15 F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\nG0 Y11 E0.700 F{outer_wall_volumetric_speed/(0.3*0.5)/ 4 * 60}\nG0 X239.5\nG0 E0.2\nG0 Y1.5 E0.700\nG0 X18 E15 F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\nM400\n\n;===== for Textured PEI Plate , lower the nozzle as the nozzle was touching topmost of the texture when homing ==\n;curr_bed_type={curr_bed_type}\n{if curr_bed_type==\"Textured PEI Plate\"}\nG29.1 Z{-0.04} ; for Textured PEI Plate\n{endif}\n;========turn off light and wait extrude temperature =============\nM1002 gcode_claim_action : 0\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off big fan\nM106 P3 S0 ; turn off chamber fan\n\nM975 S1 ; turn on mech mode supression\n",
+    "machine_switch_extruder_time": "0",
+    "machine_unload_filament_time": "28",
+    "master_extruder_id": "1",
+    "max_bridge_length": "0",
+    "max_layer_height": [
+        "0.28"
+    ],
+    "max_travel_detour_distance": "0",
+    "min_bead_width": "85%",
+    "min_feature_size": "25%",
+    "min_layer_height": [
+        "0.08"
+    ],
+    "minimum_sparse_infill_area": "15",
+    "mmu_segmented_region_interlocking_depth": "0",
+    "mmu_segmented_region_max_width": "0",
+    "name": "project_settings",
+    "no_slow_down_for_cooling_on_outwalls": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "nozzle_diameter": [
+        "0.4"
+    ],
+    "nozzle_flush_dataset": [
+        "0",
+        "0"
+    ],
+    "nozzle_height": "4.2",
+    "nozzle_temperature": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_initial_layer": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_range_high": [
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240"
+    ],
+    "nozzle_temperature_range_low": [
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190"
+    ],
+    "nozzle_type": [
+        "stainless_steel",
+        "stainless_steel"
+    ],
+    "nozzle_volume": [
+        "107",
+        "107"
+    ],
+    "nozzle_volume_type": [
+        "Standard"
+    ],
+    "only_one_wall_first_layer": "1",
+    "ooze_prevention": "0",
+    "other_layers_print_sequence": [
+        "0"
+    ],
+    "other_layers_print_sequence_nums": "0",
+    "outer_wall_acceleration": [
+        "5000",
+        "5000"
+    ],
+    "outer_wall_jerk": "9",
+    "outer_wall_line_width": "0.42",
+    "outer_wall_speed": [
+        "100",
+        "350"
+    ],
+    "overhang_1_4_speed": [
+        "0",
+        "0"
+    ],
+    "overhang_2_4_speed": [
+        "50",
+        "50"
+    ],
+    "overhang_3_4_speed": [
+        "30",
+        "30"
+    ],
+    "overhang_4_4_speed": [
+        "10",
+        "10"
+    ],
+    "overhang_fan_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "overhang_fan_threshold": [
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "overhang_threshold_participating_cooling": [
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%"
+    ],
+    "overhang_totally_speed": [
+        "10",
+        "30"
+    ],
+    "override_filament_scarf_seam_setting": "0",
+    "override_process_overhang_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "physical_extruder_map": [
+        "0"
+    ],
+    "post_process": [],
+    "pre_start_fan_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "precise_outer_wall": "0",
+    "precise_z_height": "0",
+    "pressure_advance": [
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02"
+    ],
+    "prime_tower_brim_width": "3",
+    "prime_tower_enable_framework": "0",
+    "prime_tower_extra_rib_length": "0",
+    "prime_tower_fillet_wall": "1",
+    "prime_tower_flat_ironing": "0",
+    "prime_tower_infill_gap": "150%",
+    "prime_tower_lift_height": "-1",
+    "prime_tower_lift_speed": "90",
+    "prime_tower_max_speed": "90",
+    "prime_tower_rib_wall": "0",
+    "prime_tower_rib_width": "8",
+    "prime_tower_skip_points": "1",
+    "prime_tower_width": "220",
+    "prime_volume_mode": "Default",
+    "print_compatible_printers": [
+        "Bambu Lab P1P 0.4 nozzle"
+    ],
+    "print_extruder_id": [
+        "1",
+        "1"
+    ],
+    "print_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "print_flow_ratio": "1",
+    "print_sequence": "by layer",
+    "print_settings_id": "Bambu_Lumina",
+    "printable_area": [
+        "0x0",
+        "256x0",
+        "256x256",
+        "0x256"
+    ],
+    "printable_height": "256",
+    "printer_extruder_id": [
+        "1",
+        "1"
+    ],
+    "printer_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "printer_model": "Bambu Lab P1P",
+    "printer_notes": "",
+    "printer_settings_id": "Bambu Lab P1P 0.4 nozzle",
+    "printer_structure": "corexy",
+    "printer_technology": "FFF",
+    "printer_variant": "0.4",
+    "printhost_authorization_type": "key",
+    "printhost_ssl_ignore_revoke": "0",
+    "printing_by_object_gcode": "",
+    "process_notes": "",
+    "raft_contact_distance": "0.1",
+    "raft_expansion": "1.5",
+    "raft_first_layer_density": "90%",
+    "raft_first_layer_expansion": "-1",
+    "raft_layers": "0",
+    "reduce_crossing_wall": "0",
+    "reduce_fan_stop_start_freq": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "reduce_infill_retraction": "1",
+    "required_nozzle_HRC": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "resolution": "0.012",
+    "retract_before_wipe": [
+        "0%",
+        "0%"
+    ],
+    "retract_length_toolchange": [
+        "2",
+        "2"
+    ],
+    "retract_lift_above": [
+        "0",
+        "0"
+    ],
+    "retract_lift_below": [
+        "255",
+        "255"
+    ],
+    "retract_restart_extra": [
+        "0",
+        "0"
+    ],
+    "retract_restart_extra_toolchange": [
+        "0",
+        "0"
+    ],
+    "retract_when_changing_layer": [
+        "1",
+        "1"
+    ],
+    "retraction_distances_when_cut": [
+        "18",
+        "18"
+    ],
+    "retraction_distances_when_ec": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retraction_length": [
+        "0.8",
+        "0.8"
+    ],
+    "retraction_minimum_travel": [
+        "1",
+        "1"
+    ],
+    "retraction_speed": [
+        "30",
+        "30"
+    ],
+    "role_base_wipe_speed": "1",
+    "scan_first_layer": "0",
+    "scarf_angle_threshold": "155",
+    "seam_gap": "15%",
+    "seam_placement_away_from_overhangs": "0",
+    "seam_position": "aligned",
+    "seam_slope_conditional": "1",
+    "seam_slope_entire_loop": "0",
+    "seam_slope_gap": "0",
+    "seam_slope_inner_walls": "1",
+    "seam_slope_min_length": "10",
+    "seam_slope_start_height": "10%",
+    "seam_slope_steps": "10",
+    "seam_slope_type": "none",
+    "silent_mode": "0",
+    "single_extruder_multi_material": "1",
+    "skeleton_infill_density": "100%",
+    "skeleton_infill_line_width": "0.45",
+    "skin_infill_density": "100%",
+    "skin_infill_depth": "2",
+    "skin_infill_line_width": "0.45",
+    "skirt_distance": "2",
+    "skirt_height": "1",
+    "skirt_loops": "0",
+    "slice_closing_radius": "0.049",
+    "slicing_mode": "regular",
+    "slow_down_for_layer_cooling": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "slow_down_layer_time": [
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "slow_down_min_speed": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "slowdown_end_acc": [
+        "100000",
+        "100000"
+    ],
+    "slowdown_end_height": [
+        "400",
+        "400"
+    ],
+    "slowdown_end_speed": [
+        "1000",
+        "1000"
+    ],
+    "slowdown_start_acc": [
+        "100000",
+        "100000"
+    ],
+    "slowdown_start_height": [
+        "0",
+        "0"
+    ],
+    "slowdown_start_speed": [
+        "1000",
+        "1000"
+    ],
+    "small_perimeter_speed": [
+        "50%",
+        "50%"
+    ],
+    "small_perimeter_threshold": [
+        "0",
+        "0"
+    ],
+    "smooth_coefficient": "150",
+    "smooth_speed_discontinuity_area": "1",
+    "solid_infill_filament": "0",
+    "sparse_infill_acceleration": [
+        "100%",
+        "100%"
+    ],
+    "sparse_infill_anchor": "400%",
+    "sparse_infill_anchor_max": "20",
+    "sparse_infill_density": "100%",
+    "sparse_infill_filament": "0",
+    "sparse_infill_lattice_angle_1": "-45",
+    "sparse_infill_lattice_angle_2": "45",
+    "sparse_infill_line_width": "0.45",
+    "sparse_infill_pattern": "alignedrectilinear",
+    "sparse_infill_speed": [
+        "100",
+        "370"
+    ],
+    "spiral_mode": "0",
+    "spiral_mode_max_xy_smoothing": "200%",
+    "spiral_mode_smooth": "0",
+    "standby_temperature_delta": "-5",
+    "start_end_points": [
+        "30x-3",
+        "54x245"
+    ],
+    "supertack_plate_temp": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "supertack_plate_temp_initial_layer": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "support_air_filtration": "0",
+    "support_angle": "0",
+    "support_base_pattern": "default",
+    "support_base_pattern_spacing": "2.5",
+    "support_bottom_interface_spacing": "0.5",
+    "support_bottom_z_distance": "0.2",
+    "support_chamber_temp_control": "0",
+    "support_cooling_filter": "0",
+    "support_critical_regions_only": "0",
+    "support_expansion": "0",
+    "support_filament": "0",
+    "support_interface_bottom_layers": "2",
+    "support_interface_filament": "0",
+    "support_interface_loop_pattern": "0",
+    "support_interface_not_for_body": "1",
+    "support_interface_pattern": "auto",
+    "support_interface_spacing": "0.5",
+    "support_interface_speed": [
+        "80",
+        "80"
+    ],
+    "support_interface_top_layers": "2",
+    "support_ironing_direction": "0",
+    "support_ironing_flow": "10%",
+    "support_ironing_inset": "0",
+    "support_ironing_pattern": "zig-zag",
+    "support_ironing_spacing": "0.15",
+    "support_ironing_speed": "30",
+    "support_line_width": "0.42",
+    "support_object_first_layer_gap": "0.2",
+    "support_object_skip_flush": "0",
+    "support_object_xy_distance": "0.35",
+    "support_on_build_plate_only": "0",
+    "support_remove_small_overhang": "1",
+    "support_speed": [
+        "150",
+        "150"
+    ],
+    "support_style": "default",
+    "support_threshold_angle": "30",
+    "support_top_z_distance": "0.2",
+    "support_type": "tree(auto)",
+    "symmetric_infill_y_axis": "0",
+    "temperature_vitrification": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "template_custom_gcode": "",
+    "textured_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "textured_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "thick_bridges": "0",
+    "thumbnail_size": [
+        "50x50"
+    ],
+    "time_lapse_gcode": ";========Date 20250206========\n; SKIPPABLE_START\n; SKIPTYPE: timelapse\nM622.1 S1 ; for prev firmware, default turned on\nM1002 judge_flag timelapse_record_flag\nM622 J1\n{if timelapse_type == 0} ; timelapse without wipe tower\nM971 S11 C10 O0\nM1004 S5 P1  ; external shutter\n{elsif timelapse_type == 1} ; timelapse with wipe tower\nG92 E0\nG1 X65 Y245 F20000 ; move to safe pos\nG17\nG2 Z{layer_z} I0.86 J0.86 P1 F20000\nG1 Y265 F3000\nM400\nM1004 S5 P1  ; external shutter\nM400 P300\nM971 S11 C11 O0\nG92 E0\nG1 X100 F5000\nG1 Y255 F20000\n{endif}\nM623\n; SKIPPABLE_END",
+    "timelapse_type": "0",
+    "top_area_threshold": "200%",
+    "top_color_penetration_layers": "5",
+    "top_one_wall_type": "all top",
+    "top_shell_layers": "0",
+    "top_shell_thickness": "1",
+    "top_solid_infill_flow_ratio": [
+        "1",
+        "1"
+    ],
+    "top_surface_acceleration": [
+        "2000",
+        "2000"
+    ],
+    "top_surface_density": "100%",
+    "top_surface_jerk": "9",
+    "top_surface_line_width": "0.42",
+    "top_surface_pattern": "monotonicline",
+    "top_surface_speed": [
+        "100",
+        "300"
+    ],
+    "top_z_overrides_xy_distance": "0",
+    "travel_acceleration": [
+        "10000",
+        "10000"
+    ],
+    "travel_jerk": "9",
+    "travel_short_distance_acceleration": [
+        "250",
+        "250"
+    ],
+    "travel_speed": [
+        "500",
+        "500"
+    ],
+    "travel_speed_z": [
+        "0",
+        "0"
+    ],
+    "tree_support_branch_angle": "45",
+    "tree_support_branch_diameter": "2",
+    "tree_support_branch_diameter_angle": "5",
+    "tree_support_branch_distance": "5",
+    "tree_support_wall_count": "-1",
+    "upward_compatible_machine": [
+        "Bambu Lab P1P 0.4 nozzle",
+        "Bambu Lab X1 0.4 nozzle",
+        "Bambu Lab X1 Carbon 0.4 nozzle",
+        "Bambu Lab X1E 0.4 nozzle",
+        "Bambu Lab A1 0.4 nozzle",
+        "Bambu Lab H2D 0.4 nozzle",
+        "Bambu Lab H2D Pro 0.4 nozzle",
+        "Bambu Lab H2S 0.4 nozzle",
+        "Bambu Lab P2S 0.4 nozzle",
+        "Bambu Lab H2C 0.4 nozzle"
+    ],
+    "use_firmware_retraction": "0",
+    "use_relative_e_distances": "1",
+    "version": "02.05.00.66",
+    "vertical_shell_speed": [
+        "80%",
+        "80%"
+    ],
+    "volumetric_speed_coefficients": [
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0"
+    ],
+    "wall_distribution_count": "1",
+    "wall_filament": "0",
+    "wall_generator": "classic",
+    "wall_loops": "1",
+    "wall_sequence": "inner wall/outer wall",
+    "wall_transition_angle": "10",
+    "wall_transition_filter_deviation": "25%",
+    "wall_transition_length": "100%",
+    "wipe": [
+        "1",
+        "1"
+    ],
+    "wipe_distance": [
+        "2",
+        "2"
+    ],
+    "wipe_speed": "80%",
+    "wipe_tower_no_sparse_layers": "0",
+    "wipe_tower_rotation_angle": "0",
+    "wipe_tower_x": [
+        "18.5216"
+    ],
+    "wipe_tower_y": [
+        "214.154"
+    ],
+    "wrapping_detection_gcode": "",
+    "wrapping_detection_layers": "20",
+    "wrapping_exclude_area": [],
+    "xy_contour_compensation": "0",
+    "xy_hole_compensation": "0",
+    "z_direction_outwall_speed_continuous": "0",
+    "z_hop": [
+        "0.4",
+        "0.4"
+    ],
+    "z_hop_types": [
+        "Auto Lift",
+        "Auto Lift"
+    ]
+}
\ No newline at end of file
diff --git a/printer_profiles/bambu_p1s.json b/printer_profiles/bambu_p1s.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_p1s.json
@@ -0,0 +1,2615 @@
+{
+    "accel_to_decel_enable": "0",
+    "accel_to_decel_factor": "50%",
+    "activate_air_filtration": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "additional_cooling_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "apply_scarf_seam_on_circles": "1",
+    "apply_top_surface_compensation": "0",
+    "auxiliary_fan": "1",
+    "avoid_crossing_wall_includes_support": "0",
+    "bed_custom_model": "",
+    "bed_custom_texture": "",
+    "bed_exclude_area": [
+        "0x0",
+        "18x0",
+        "18x28",
+        "0x28"
+    ],
+    "bed_temperature_formula": "by_first_filament",
+    "before_layer_change_gcode": "",
+    "best_object_pos": "0.5,0.5",
+    "bottom_color_penetration_layers": "3",
+    "bottom_shell_layers": "0",
+    "bottom_shell_thickness": "0",
+    "bottom_surface_density": "100%",
+    "bottom_surface_pattern": "monotonic",
+    "bridge_angle": "0",
+    "bridge_flow": "1",
+    "bridge_no_support": "0",
+    "bridge_speed": [
+        "50",
+        "50"
+    ],
+    "brim_object_gap": "0.1",
+    "brim_type": "auto_brim",
+    "brim_width": "5",
+    "chamber_temperatures": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "change_filament_gcode": ";=P1S 20251031=\nM620 S[next_extruder]A\nM204 S9000\nG1 Z{max_layer_z + 3.0} F1200\n\nG1 X70 F21000\nG1 Y245\nG1 Y265 F3000\nM400\nM106 P1 S0\nM106 P2 S0\n{if old_filament_temp > 142 && next_extruder < 255}\nM104 S[old_filament_temp]\n{endif}\n{if long_retractions_when_cut[previous_extruder]}\nM620.11 S1 I[previous_extruder] E-{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\n{else}\nM620.11 S0\n{endif}\nM400\nG1 X90 F3000\nG1 Y255 F4000\nG1 X100 F5000\nG1 X120 F15000\nG1 X20 Y50 F21000\nG1 Y-3\n{if toolchange_count == 2}\n; get travel path for change filament\nM620.1 X[travel_point_1_x] Y[travel_point_1_y] F21000 P0\nM620.1 X[travel_point_2_x] Y[travel_point_2_y] F21000 P1\nM620.1 X[travel_point_3_x] Y[travel_point_3_y] F21000 P2\n{endif}\nM620.1 E F{flush_volumetric_speeds[previous_extruder]/2.4053*60} T{flush_temperatures[previous_extruder]}\nT[next_extruder]\nM620.1 E F{flush_volumetric_speeds[next_extruder]/2.4053*60} T{flush_temperatures[next_extruder]}\n\n{if next_extruder < 255}\n{if long_retractions_when_cut[previous_extruder]}\nM620.11 S1 I[previous_extruder] E{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nM628 S1\nG92 E0\nG1 E{retraction_distances_when_cut[previous_extruder]} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nM400\nM629 S1\n{else}\nM620.11 S0\n{endif}\nG92 E0\n{if flush_length_1 > 1}\nM83\n; FLUSH_START\n; always use highest temperature to flush\nM400\n{if filament_type[next_extruder] == \"PETG\"}\nM109 S260\n{elsif filament_type[next_extruder] == \"PVA\"}\nM109 S210\n{else}\nM109 S{flush_temperatures[next_extruder]}\n{endif}\n{if flush_length_1 > 23.7}\nG1 E23.7 F{flush_volumetric_speeds[previous_extruder]/2.4053*60} ; do not need pulsatile flushing for start part\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{(flush_length_1 - 23.7) * 0.02} F50\nG1 E{(flush_length_1 - 23.7) * 0.23} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\n{else}\nG1 E{flush_length_1} F{flush_volumetric_speeds[previous_extruder]/2.4053*60}\n{endif}\n; FLUSH_END\nG1 E-[old_retract_length_toolchange] F1800\nG1 E[old_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_2 > 1}\n\nG91\nG1 X3 F12000; move aside to extrude\nG90\nM83\n\n; FLUSH_START\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\nG1 E{flush_length_2 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_2 * 0.02} F50\n; FLUSH_END\nG1 E-[new_retract_length_toolchange] F1800\nG1 E[new_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_3 > 1}\n\nG91\nG1 X3 F12000; move aside to extrude\nG90\nM83\n\n; FLUSH_START\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\nG1 E{flush_length_3 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_3 * 0.02} F50\n; FLUSH_END\nG1 E-[new_retract_length_toolchange] F1800\nG1 E[new_retract_length_toolchange] F300\n{endif}\n\n{if flush_length_4 > 1}\n\nG91\nG1 X3 F12000; move aside to extrude\nG90\nM83\n\n; FLUSH_START\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\nG1 E{flush_length_4 * 0.18} F{flush_volumetric_speeds[next_extruder]/2.4053*60}\nG1 E{flush_length_4 * 0.02} F50\n; FLUSH_END\n{endif}\n; FLUSH_START\nM400\nM109 S[new_filament_temp]\nG1 E2 F{flush_volumetric_speeds[next_extruder]/2.4053*60} ;Compensate for filament spillage during waiting temperature\n; FLUSH_END\nM400\nG92 E0\nG1 E-[new_retract_length_toolchange] F1800\nM106 P1 S255\nM400 S3\n\nG1 X70 F5000\nG1 X90 F3000\nG1 Y255 F4000\nG1 X105 F5000\nG1 Y265 F5000\nG1 X70 F10000\nG1 X100 F5000\nG1 X70 F10000\nG1 X100 F5000\n\nG1 X70 F10000\nG1 X80 F15000\nG1 X60\nG1 X80\nG1 X60\nG1 X80 ; shake to put down garbage\nG1 X100 F5000\nG1 X165 F15000; wipe and shake\nG1 Y256 ; move Y to aside, prevent collision\nM400\nG1 Z{max_layer_z + 3.0} F3000\n{if layer_z <= (initial_layer_print_height + 0.001)}\nM204 S[initial_layer_acceleration]\n{else}\nM204 S[default_acceleration]\n{endif}\n{else}\nG1 X[x_after_toolchange] Y[y_after_toolchange] Z[z_after_toolchange] F12000\n{endif}\nM621 S[next_extruder]A\n",
+    "circle_compensation_manual_offset": "0",
+    "circle_compensation_speed": [
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200",
+        "200"
+    ],
+    "close_fan_the_first_x_layers": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "complete_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "cool_plate_temp": [
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cool_plate_temp_initial_layer": [
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35",
+        "35"
+    ],
+    "cooling_filter_enabled": "0",
+    "cooling_perimeter_transition_distance": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "cooling_slowdown_logic": [
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling",
+        "uniform_cooling"
+    ],
+    "counter_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "counter_coef_2": [
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008",
+        "0.008"
+    ],
+    "counter_coef_3": [
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041",
+        "-0.041"
+    ],
+    "counter_limit_max": [
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033",
+        "0.033"
+    ],
+    "counter_limit_min": [
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035",
+        "-0.035"
+    ],
+    "curr_bed_type": "Textured PEI Plate",
+    "default_acceleration": [
+        "10000",
+        "10000"
+    ],
+    "default_filament_colour": [
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "default_filament_profile": [
+        "Bambu PLA Basic @BBL P1S 0.4 nozzle"
+    ],
+    "default_jerk": "0",
+    "default_nozzle_volume_type": [
+        "Standard"
+    ],
+    "default_print_profile": "0.20mm Standard @BBL X1C",
+    "deretraction_speed": [
+        "30",
+        "30"
+    ],
+    "detect_floating_vertical_shell": "1",
+    "detect_narrow_internal_solid_infill": "0",
+    "detect_overhang_wall": "1",
+    "detect_thin_wall": "0",
+    "diameter_limit": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "different_settings_to_system": [
+        "bottom_shell_layers;detect_narrow_internal_solid_infill;elefant_foot_compensation;initial_layer_flow_ratio;initial_layer_infill_speed;initial_layer_line_width;initial_layer_print_height;inner_wall_speed;internal_solid_infill_speed;layer_height;only_one_wall_first_layer;outer_wall_speed;prime_tower_rib_wall;prime_tower_width;skeleton_infill_density;skin_infill_density;sparse_infill_density;sparse_infill_pattern;sparse_infill_speed;top_shell_layers;top_surface_speed;wall_loops",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "draft_shield": "disabled",
+    "during_print_exhaust_fan_speed": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "elefant_foot_compensation": "0",
+    "embedding_wall_into_infill": "0",
+    "enable_arc_fitting": "1",
+    "enable_circle_compensation": "0",
+    "enable_height_slowdown": [
+        "0",
+        "0"
+    ],
+    "enable_long_retraction_when_cut": "2",
+    "enable_overhang_bridge_fan": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "enable_overhang_speed": [
+        "1",
+        "1"
+    ],
+    "enable_pre_heating": "0",
+    "enable_pressure_advance": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "enable_prime_tower": "1",
+    "enable_support": "0",
+    "enable_support_ironing": "0",
+    "enable_tower_interface_features": "0",
+    "enable_wrapping_detection": "0",
+    "enforce_support_layers": "0",
+    "eng_plate_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "eng_plate_temp_initial_layer": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "ensure_vertical_shell_thickness": "enabled",
+    "exclude_object": "1",
+    "extruder_ams_count": [
+        "1#0|4#0",
+        ""
+    ],
+    "extruder_clearance_dist_to_rod": "33",
+    "extruder_clearance_height_to_lid": "90",
+    "extruder_clearance_height_to_rod": "34",
+    "extruder_clearance_max_radius": "68",
+    "extruder_colour": [
+        "#018001"
+    ],
+    "extruder_max_nozzle_count": [
+        "1"
+    ],
+    "extruder_nozzle_stats": [
+        "Standard#1"
+    ],
+    "extruder_offset": [
+        "0x2"
+    ],
+    "extruder_printable_area": [],
+    "extruder_printable_height": [],
+    "extruder_type": [
+        "Direct Drive"
+    ],
+    "extruder_variant_list": [
+        "Direct Drive Standard,Direct Drive High Flow"
+    ],
+    "fan_cooling_layer_time": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "fan_direction": "left",
+    "fan_max_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "fan_min_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_adaptive_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_adhesiveness_category": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "filament_bridge_speed": [
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25",
+        "25"
+    ],
+    "filament_change_length": [
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5",
+        "5"
+    ],
+    "filament_change_length_nc": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_colour": [
+        "#FFFFFF",
+        "#0080FF",
+        "#FF00FF",
+        "#FFFF00",
+        "#000000",
+        "#FF0000",
+        "#0000FF",
+        "#00FF00"
+    ],
+    "filament_colour_type": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_cooling_before_tower": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_cost": [
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99",
+        "24.99"
+    ],
+    "filament_density": [
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26",
+        "1.26"
+    ],
+    "filament_deretraction_speed": [
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50"
+    ],
+    "filament_dev_ams_drying_ams_limitations": [
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0",
+        "1",
+        "0"
+    ],
+    "filament_dev_ams_drying_heat_distortion_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_ams_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_chamber_drying_bed_temperature": [
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70",
+        "70"
+    ],
+    "filament_dev_chamber_drying_time": [
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12",
+        "12"
+    ],
+    "filament_dev_drying_cooling_temperature": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "filament_dev_drying_softening_temperature": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_diameter": [
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75",
+        "1.75"
+    ],
+    "filament_enable_overhang_speed": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_end_gcode": [
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n",
+        "; filament end gcode \n\n"
+    ],
+    "filament_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow",
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "filament_flow_ratio": [
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985",
+        "0.98",
+        "0.985"
+    ],
+    "filament_flush_temp": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_flush_volumetric_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ids": [
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00",
+        "GFA00"
+    ],
+    "filament_is_support": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_long_retractions_when_cut": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_map_mode": "Auto For Flush",
+    "filament_max_volumetric_speed": [
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29",
+        "21",
+        "29"
+    ],
+    "filament_minimal_purge_on_wipe_tower": [
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15",
+        "15"
+    ],
+    "filament_multi_colour": [
+        "#FFFFFF",
+        "#0080FF",
+        "#FF00FF",
+        "#FFFF00",
+        "#000000",
+        "#FF0000",
+        "#0000FF",
+        "#00FF00"
+    ],
+    "filament_notes": "",
+    "filament_nozzle_map": [
+        "1",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_1_4_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_overhang_2_4_speed": [
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50",
+        "50"
+    ],
+    "filament_overhang_3_4_speed": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_overhang_4_4_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_overhang_totally_speed": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_pre_cooling_temperature": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_pre_cooling_temperature_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_prime_volume": [
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "filament_prime_volume_nc": [
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60",
+        "60"
+    ],
+    "filament_printable": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "filament_ramming_travel_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_travel_time_nc": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_ramming_volumetric_speed": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_ramming_volumetric_speed_nc": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_retract_before_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_length_nc": [
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14",
+        "14"
+    ],
+    "filament_retract_restart_extra": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retract_when_changing_layer": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_distances_when_cut": [
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18",
+        "18"
+    ],
+    "filament_retraction_length": [
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4",
+        "nil",
+        "0.4"
+    ],
+    "filament_retraction_minimum_travel": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_retraction_speed": [
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50",
+        "nil",
+        "50"
+    ],
+    "filament_scarf_gap": [
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%",
+        "0%"
+    ],
+    "filament_scarf_height": [
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%",
+        "10%"
+    ],
+    "filament_scarf_length": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_scarf_seam_type": [
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none",
+        "none"
+    ],
+    "filament_self_index": [
+        "1",
+        "1",
+        "2",
+        "2",
+        "3",
+        "3",
+        "4",
+        "4",
+        "5",
+        "5",
+        "6",
+        "6",
+        "7",
+        "7",
+        "8",
+        "8"
+    ],
+    "filament_settings_id": [
+        "Bambu PLA Basic @BBL P1S 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1S 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1S 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1S 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1S 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1S 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1S 0.4 nozzle",
+        "Bambu PLA Basic @BBL P1S 0.4 nozzle"
+    ],
+    "filament_shrink": [
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%",
+        "100%"
+    ],
+    "filament_soluble": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_start_gcode": [
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}",
+        "; filament start gcode\n{if  (bed_temperature[current_extruder] >55)||(bed_temperature_initial_layer[current_extruder] >55)}M106 P3 S200\n{elsif(bed_temperature[current_extruder] >50)||(bed_temperature_initial_layer[current_extruder] >50)}M106 P3 S150\n{elsif(bed_temperature[current_extruder] >45)||(bed_temperature_initial_layer[current_extruder] >45)}M106 P3 S50\n{endif}\nM142 P1 R35 S40\n{if activate_air_filtration[current_extruder] && support_air_filtration}\nM106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} \n{endif}"
+    ],
+    "filament_tower_interface_pre_extrusion_dist": [
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10",
+        "10"
+    ],
+    "filament_tower_interface_pre_extrusion_length": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_tower_interface_print_temp": [
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1",
+        "-1"
+    ],
+    "filament_tower_interface_purge_volume": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "filament_tower_ironing_area": [
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "filament_type": [
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA",
+        "PLA"
+    ],
+    "filament_velocity_adaptation_factor": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "filament_vendor": [
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab",
+        "Bambu Lab"
+    ],
+    "filament_volume_map": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "filament_wipe": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_wipe_distance": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filament_z_hop": [
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6",
+        "nil",
+        "0.6"
+    ],
+    "filament_z_hop_types": [
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil",
+        "nil"
+    ],
+    "filename_format": "{input_filename_base}_{filament_type[0]}_{print_time}.gcode",
+    "fill_multiline": "1",
+    "filter_out_gap_fill": "0",
+    "first_layer_print_sequence": [
+        "0"
+    ],
+    "first_x_layer_fan_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "flush_into_infill": "0",
+    "flush_into_objects": "0",
+    "flush_into_support": "1",
+    "flush_multiplier": [
+        "1"
+    ],
+    "flush_volumes_matrix": [
+        "0",
+        "320",
+        "319",
+        "297",
+        "143",
+        "325",
+        "335",
+        "311",
+        "604",
+        "0",
+        "344",
+        "594",
+        "159",
+        "297",
+        "195",
+        "453",
+        "603",
+        "293",
+        "0",
+        "592",
+        "159",
+        "297",
+        "305",
+        "451",
+        "370",
+        "314",
+        "314",
+        "0",
+        "183",
+        "319",
+        "329",
+        "305",
+        "623",
+        "521",
+        "523",
+        "513",
+        "0",
+        "471",
+        "370",
+        "603",
+        "649",
+        "412",
+        "370",
+        "603",
+        "153",
+        "0",
+        "300",
+        "506",
+        "724",
+        "379",
+        "471",
+        "716",
+        "143",
+        "456",
+        "0",
+        "592",
+        "523",
+        "300",
+        "300",
+        "471",
+        "170",
+        "305",
+        "314",
+        "0"
+    ],
+    "flush_volumes_vector": [
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140",
+        "140"
+    ],
+    "from": "project",
+    "full_fan_speed_layer": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "fuzzy_skin": "none",
+    "fuzzy_skin_point_distance": "0.8",
+    "fuzzy_skin_thickness": "0.3",
+    "gap_infill_speed": [
+        "250",
+        "250"
+    ],
+    "gcode_add_line_number": "0",
+    "gcode_flavor": "marlin",
+    "grab_length": [
+        "0"
+    ],
+    "group_algo_with_time": "0",
+    "has_scarf_joint_seam": "0",
+    "head_wrap_detect_zone": [],
+    "hole_coef_1": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "hole_coef_2": [
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008",
+        "-0.008"
+    ],
+    "hole_coef_3": [
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415",
+        "0.23415"
+    ],
+    "hole_limit_max": [
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22",
+        "0.22"
+    ],
+    "hole_limit_min": [
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088",
+        "0.088"
+    ],
+    "host_type": "octoprint",
+    "hot_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hot_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "hotend_cooling_rate": [
+        "2",
+        "2"
+    ],
+    "hotend_heating_rate": [
+        "2",
+        "2"
+    ],
+    "impact_strength_z": [
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8",
+        "13.8"
+    ],
+    "independent_support_layer_height": "1",
+    "infill_combination": "0",
+    "infill_direction": "45",
+    "infill_instead_top_bottom_surfaces": "0",
+    "infill_jerk": "9",
+    "infill_lock_depth": "1",
+    "infill_rotate_step": "0",
+    "infill_shift_step": "0.4",
+    "infill_wall_overlap": "15%",
+    "inherits_group": [
+        "0.20mm Standard @BBL X1C",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        "",
+        ""
+    ],
+    "initial_layer_acceleration": [
+        "500",
+        "500"
+    ],
+    "initial_layer_flow_ratio": "1.05",
+    "initial_layer_infill_speed": [
+        "50",
+        "105"
+    ],
+    "initial_layer_jerk": "9",
+    "initial_layer_line_width": "0.42",
+    "initial_layer_print_height": "0.08",
+    "initial_layer_speed": [
+        "50",
+        "50"
+    ],
+    "initial_layer_travel_acceleration": [
+        "6000",
+        "6000"
+    ],
+    "inner_wall_acceleration": [
+        "0",
+        "0"
+    ],
+    "inner_wall_jerk": "9",
+    "inner_wall_line_width": "0.45",
+    "inner_wall_speed": [
+        "100",
+        "400"
+    ],
+    "interface_shells": "0",
+    "interlocking_beam": "0",
+    "interlocking_beam_layer_count": "2",
+    "interlocking_beam_width": "0.8",
+    "interlocking_boundary_avoidance": "2",
+    "interlocking_depth": "2",
+    "interlocking_orientation": "22.5",
+    "internal_bridge_support_thickness": "0.8",
+    "internal_solid_infill_line_width": "0.42",
+    "internal_solid_infill_pattern": "zig-zag",
+    "internal_solid_infill_speed": [
+        "100",
+        "350"
+    ],
+    "ironing_direction": "45",
+    "ironing_flow": "10%",
+    "ironing_inset": "0.21",
+    "ironing_pattern": "zig-zag",
+    "ironing_spacing": "0.15",
+    "ironing_speed": "30",
+    "ironing_type": "no ironing",
+    "is_infill_first": "0",
+    "layer_change_gcode": "; layer num/total_layer_count: {layer_num+1}/[total_layer_count]\n; update layer progress\nM73 L{layer_num+1}\nM991 S0 P{layer_num} ;notify layer change",
+    "layer_height": "0.08",
+    "line_width": "0.42",
+    "locked_skeleton_infill_pattern": "zigzag",
+    "locked_skin_infill_pattern": "crosszag",
+    "long_retractions_when_cut": [
+        "0",
+        "0"
+    ],
+    "long_retractions_when_ec": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "machine_end_gcode": ";===== date: 20230428 =====================\nM400 ; wait for buffer to clear\nG92 E0 ; zero the extruder\nG1 E-0.8 F1800 ; retract\nG1 Z{max_layer_z + 0.5} F900 ; lower z a little\nG1 X65 Y245 F12000 ; move to safe pos \nG1 Y265 F3000\n\nG1 X65 Y245 F12000\nG1 Y265 F3000\nM140 S0 ; turn off bed\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off remote part cooling fan\nM106 P3 S0 ; turn off chamber cooling fan\n\nG1 X100 F12000 ; wipe\n; pull back filament to AMS\nM620 S255\nG1 X20 Y50 F12000\nG1 Y-3\nT255\nG1 X65 F12000\nG1 Y265\nG1 X100 F12000 ; wipe\nM621 S255\nM104 S0 ; turn off hotend\n\nM622.1 S1 ; for prev firware, default turned on\nM1002 judge_flag timelapse_record_flag\nM622 J1\n    M400 ; wait all motion done\n    M991 S0 P-1 ;end smooth timelapse at safe pos\n    M400 S3 ;wait for last picture to be taken\nM623; end of \"timelapse_record_flag\"\n\nM400 ; wait all motion done\nM17 S\nM17 Z0.4 ; lower z motor current to reduce impact if there is something in the bottom\n{if (max_layer_z + 100.0) < 250}\n    G1 Z{max_layer_z + 100.0} F600\n    G1 Z{max_layer_z +98.0}\n{else}\n    G1 Z250 F600\n    G1 Z248\n{endif}\nM400 P100\nM17 R ; restore z current\n\nM220 S100  ; Reset feedrate magnitude\nM201.2 K1.0 ; Reset acc magnitude\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 0\n\nM17 X0.8 Y0.8 Z0.5 ; lower motor current to 45% power\n",
+    "machine_hotend_change_time": "0",
+    "machine_load_filament_time": "29",
+    "machine_max_acceleration_e": [
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_extruding": [
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_retracting": [
+        "5000",
+        "5000",
+        "5000",
+        "5000"
+    ],
+    "machine_max_acceleration_travel": [
+        "9000",
+        "9000",
+        "9000",
+        "9000"
+    ],
+    "machine_max_acceleration_x": [
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_y": [
+        "20000",
+        "20000",
+        "20000",
+        "20000"
+    ],
+    "machine_max_acceleration_z": [
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_jerk_e": [
+        "2.5",
+        "2.5",
+        "2.5",
+        "2.5"
+    ],
+    "machine_max_jerk_x": [
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_y": [
+        "9",
+        "9",
+        "9",
+        "9"
+    ],
+    "machine_max_jerk_z": [
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "machine_max_speed_e": [
+        "30",
+        "30",
+        "30",
+        "30"
+    ],
+    "machine_max_speed_x": [
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_speed_y": [
+        "500",
+        "500",
+        "500",
+        "500"
+    ],
+    "machine_max_speed_z": [
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "machine_min_extruding_rate": [
+        "0"
+    ],
+    "machine_min_travel_rate": [
+        "0"
+    ],
+    "machine_pause_gcode": "M400 U1",
+    "machine_prepare_compensation_time": "260",
+    "machine_start_gcode": ";===== machine: P1S-0.4 ========================\n;===== date: 20251031 =====================\n;===== turn on the HB fan & MC board fan =================\nM104 S75 ;set extruder temp to turn on the HB fan and prevent filament oozing from nozzle\nM710 A1 S255 ;turn on MC fan by default(P1S)\n;===== reset machine status =================\nM290 X40 Y40 Z2.6666666\nG91\nM17 Z0.4 ; lower the z-motor current\nG380 S2 Z30 F300 ; G380 is same as G38; lower the hotbed , to prevent the nozzle is below the hotbed\nG380 S2 Z-25 F300 ;\nG1 Z5 F300;\nG90\nM17 X1.2 Y1.2 Z0.75 ; reset motor current to default\nM960 S5 P1 ; turn on logo lamp\nG90\nM220 S100 ;Reset Feedrate\nM221 S100 ;Reset Flowrate\nM73.2   R1.0 ;Reset left time magnitude\nM1002 set_gcode_claim_speed_level : 5\nM221 X0 Y0 Z0 ; turn off soft endstop to prevent protential logic problem\nG29.1 Z{+0.0} ; clear z-trim value first\nM204 S10000 ; init ACC set to 10m/s^2\n\n;===== heatbed preheat ====================\nM1002 gcode_claim_action:54\nM140 S[bed_temperature_initial_layer_single] ;set bed temp\nM190 S[bed_temperature_initial_layer_single] ;wait for bed temp\n\n\n\n;=============turn on fans to prevent PLA jamming=================\n{if filament_type[initial_extruder]==\"PLA\"}\n    {if (bed_temperature[initial_extruder] >45)||(bed_temperature_initial_layer[initial_extruder] >45)}\n    M106 P3 S180\n    {endif};Prevent PLA from jamming\n{endif}\nM106 P2 S100 ; turn on big fan ,to cool down toolhead\n\n;===== prepare print temperature and material ==========\nM104 S[nozzle_temperature_initial_layer] ;set extruder temp\nG91\nG0 Z10 F1200\nG90\nG28 X\nM975 S1 ; turn on\nG1 X60 F12000\nG1 Y245\nG1 Y265 F3000\nM620 M\nM620 S[initial_extruder]A   ; switch material if AMS exist\n    M109 S[nozzle_temperature_initial_layer]\n    G1 X120 F12000\n\n    G1 X20 Y50 F12000\n    G1 Y-3\n    T[initial_extruder]\n    G1 X54 F12000\n    G1 Y265\n    M400\nM621 S[initial_extruder]A\nM620.1 E F{flush_volumetric_speeds[initial_no_support_extruder]/2.4053*60} T{flush_temperatures[initial_no_support_extruder]}\n\n\nM412 S1 ; ===turn on filament runout detection===\n\nM109 S250 ;set nozzle to common flush temp\nM106 P1 S0\nG92 E0\nG1 E50 F200\nM400\nM104 S[nozzle_temperature_initial_layer]\nG92 E0\nG1 E50 F200\nM400\nM106 P1 S255\nG92 E0\nG1 E5 F300\nM109 S{nozzle_temperature_initial_layer[initial_extruder]-20} ; drop nozzle temp, make filament shink a bit\nG92 E0\nG1 E-0.5 F300\n\nG1 X70 F9000\nG1 X76 F15000\nG1 X65 F15000\nG1 X76 F15000\nG1 X65 F15000; shake to put down garbage\nG1 X80 F6000\nG1 X95 F15000\nG1 X80 F15000\nG1 X165 F15000; wipe and shake\nM400\nM106 P1 S0\n;===== prepare print temperature and material end =====\n\n\n;===== wipe nozzle ===============================\nM1002 gcode_claim_action : 14\nM975 S1\nM106 S255\nG1 X65 Y230 F18000\nG1 Y264 F6000\nM109 S{nozzle_temperature_initial_layer[initial_extruder]-20}\nG1 X100 F18000 ; first wipe mouth\n\nG0 X135 Y253 F20000  ; move to exposed steel surface edge\nG28 Z P0 T300; home z with low precision,permit 300deg temperature\nG29.2 S0 ; turn off ABL\nG0 Z5 F20000\n\nG1 X60 Y265\nG92 E0\nG1 E-0.5 F300 ; retrack more\nG1 X100 F5000; second wipe mouth\nG1 X70 F15000\nG1 X100 F5000\nG1 X70 F15000\nG1 X100 F5000\nG1 X70 F15000\nG1 X100 F5000\nG1 X70 F15000\nG1 X90 F5000\nG0 X128 Y261 Z-1.5 F20000  ; move to exposed steel surface and stop the nozzle\nM104 S140 ; set temp down to heatbed acceptable\nM106 S255 ; turn on fan (G28 has turn off fan)\n\nM221 S; push soft endstop status\nM221 Z0 ;turn off Z axis endstop\nG0 Z0.5 F20000\nG0 X125 Y259.5 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y262.5\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y260.0\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y262.0\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y260.5\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y261.5\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 Z0.5 F20000\nG0 X125 Y261.0\nG0 Z-1.01\nG0 X131 F211\nG0 X124\nG0 X128\nG2 I0.5 J0 F300\nG2 I0.5 J0 F300\nG2 I0.5 J0 F300\nG2 I0.5 J0 F300\n\nM109 S140 ; wait nozzle temp down to heatbed acceptable\nG2 I0.5 J0 F3000\nG2 I0.5 J0 F3000\nG2 I0.5 J0 F3000\nG2 I0.5 J0 F3000\n\nM221 R; pop softend status\nG1 Z10 F1200\nM400\nG1 Z10\nG1 F30000\nG1 X230 Y15\nG29.2 S1 ; turn on ABL\n;G28 ; home again after hard wipe mouth\nM106 S0 ; turn off fan , too noisy\n;===== wipe nozzle end ================================\n\n\n;===== bed leveling ==================================\nM1002 judge_flag g29_before_print_flag\nM622 J1\n\n    M1002 gcode_claim_action : 1\n    G29 A X{first_layer_print_min[0]} Y{first_layer_print_min[1]} I{first_layer_print_size[0]} J{first_layer_print_size[1]}\n    M400\n    M500 ; save cali data\n\nM623\n;===== bed leveling end ================================\n\n;===== home after wipe mouth============================\nM1002 judge_flag g29_before_print_flag\nM622 J0\n\n    M1002 gcode_claim_action : 13\n    G28\n\nM623\n;===== home after wipe mouth end =======================\n\nM975 S1 ; turn on vibration supression\n\n\n;=============turn on fans to prevent PLA jamming=================\n{if filament_type[initial_extruder]==\"PLA\"}\n    {if (bed_temperature[initial_extruder] >45)||(bed_temperature_initial_layer[initial_extruder] >45)}\n    M106 P3 S180\n    {endif};Prevent PLA from jamming\n{endif}\nM106 P2 S100 ; turn on big fan ,to cool down toolhead\n\n\nM104 S{nozzle_temperature_initial_layer[initial_extruder]} ; set extrude temp earlier, to reduce wait time\n\n;===== mech mode fast check============================\nG1 X128 Y128 Z10 F20000\nM400 P200\nM970.3 Q1 A7 B30 C80  H15 K0\nM974 Q1 S2 P0\n\nG1 X128 Y128 Z10 F20000\nM400 P200\nM970.3 Q0 A7 B30 C90 Q0 H15 K0\nM974 Q0 S2 P0\n\nM975 S1\nG1 F30000\nG1 X230 Y15\nG28 X ; re-home XY\n;===== fmech mode fast check============================\n\n\n;===== nozzle load line ===============================\nM975 S1\nG90\nM83\nT1000\nG1 X18.0 Y1.0 Z0.8 F18000;Move to start position\nM109 S{nozzle_temperature_initial_layer[initial_extruder]}\nG1 Z0.2\nG0 E2 F300\nG0 X240 E15 F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\nG0 Y11 E0.700 F{outer_wall_volumetric_speed/(0.3*0.5)/ 4 * 60}\nG0 X239.5\nG0 E0.2\nG0 Y1.5 E0.700\nG0 X18 E15 F{outer_wall_volumetric_speed/(0.3*0.5)     * 60}\nM400\n\n;===== for Textured PEI Plate , lower the nozzle as the nozzle was touching topmost of the texture when homing ==\n;curr_bed_type={curr_bed_type}\n{if curr_bed_type==\"Textured PEI Plate\"}\nG29.1 Z{-0.04} ; for Textured PEI Plate\n{endif}\n;========turn off light and wait extrude temperature =============\nM1002 gcode_claim_action : 0\nM106 S0 ; turn off fan\nM106 P2 S0 ; turn off big fan\nM106 P3 S0 ; turn off chamber fan\n\nM975 S1 ; turn on mech mode supression\n",
+    "machine_switch_extruder_time": "0",
+    "machine_unload_filament_time": "28",
+    "master_extruder_id": "1",
+    "max_bridge_length": "0",
+    "max_layer_height": [
+        "0.28"
+    ],
+    "max_travel_detour_distance": "0",
+    "min_bead_width": "85%",
+    "min_feature_size": "25%",
+    "min_layer_height": [
+        "0.08"
+    ],
+    "minimum_sparse_infill_area": "15",
+    "mmu_segmented_region_interlocking_depth": "0",
+    "mmu_segmented_region_max_width": "0",
+    "name": "project_settings",
+    "no_slow_down_for_cooling_on_outwalls": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "nozzle_diameter": [
+        "0.4"
+    ],
+    "nozzle_flush_dataset": [
+        "0",
+        "0"
+    ],
+    "nozzle_height": "4.2",
+    "nozzle_temperature": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_initial_layer": [
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220",
+        "220"
+    ],
+    "nozzle_temperature_range_high": [
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240",
+        "240"
+    ],
+    "nozzle_temperature_range_low": [
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190",
+        "190"
+    ],
+    "nozzle_type": [
+        "stainless_steel",
+        "stainless_steel"
+    ],
+    "nozzle_volume": [
+        "107",
+        "107"
+    ],
+    "nozzle_volume_type": [
+        "Standard"
+    ],
+    "only_one_wall_first_layer": "1",
+    "ooze_prevention": "0",
+    "other_layers_print_sequence": [
+        "0"
+    ],
+    "other_layers_print_sequence_nums": "0",
+    "outer_wall_acceleration": [
+        "5000",
+        "5000"
+    ],
+    "outer_wall_jerk": "9",
+    "outer_wall_line_width": "0.42",
+    "outer_wall_speed": [
+        "100",
+        "350"
+    ],
+    "overhang_1_4_speed": [
+        "0",
+        "0"
+    ],
+    "overhang_2_4_speed": [
+        "50",
+        "50"
+    ],
+    "overhang_3_4_speed": [
+        "30",
+        "30"
+    ],
+    "overhang_4_4_speed": [
+        "10",
+        "10"
+    ],
+    "overhang_fan_speed": [
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100",
+        "100"
+    ],
+    "overhang_fan_threshold": [
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%",
+        "50%"
+    ],
+    "overhang_threshold_participating_cooling": [
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%",
+        "95%"
+    ],
+    "overhang_totally_speed": [
+        "10",
+        "30"
+    ],
+    "override_filament_scarf_seam_setting": "0",
+    "override_process_overhang_speed": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "physical_extruder_map": [
+        "0"
+    ],
+    "post_process": [],
+    "pre_start_fan_time": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "precise_outer_wall": "0",
+    "precise_z_height": "0",
+    "pressure_advance": [
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02",
+        "0.02"
+    ],
+    "prime_tower_brim_width": "3",
+    "prime_tower_enable_framework": "0",
+    "prime_tower_extra_rib_length": "0",
+    "prime_tower_fillet_wall": "1",
+    "prime_tower_flat_ironing": "0",
+    "prime_tower_infill_gap": "150%",
+    "prime_tower_lift_height": "-1",
+    "prime_tower_lift_speed": "90",
+    "prime_tower_max_speed": "90",
+    "prime_tower_rib_wall": "0",
+    "prime_tower_rib_width": "8",
+    "prime_tower_skip_points": "1",
+    "prime_tower_width": "220",
+    "prime_volume_mode": "Default",
+    "print_compatible_printers": [
+        "Bambu Lab X1 Carbon 0.4 nozzle",
+        "Bambu Lab X1 0.4 nozzle",
+        "Bambu Lab P1S 0.4 nozzle",
+        "Bambu Lab X1E 0.4 nozzle"
+    ],
+    "print_extruder_id": [
+        "1",
+        "1"
+    ],
+    "print_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "print_flow_ratio": "1",
+    "print_sequence": "by layer",
+    "print_settings_id": "Bambu_Lumina",
+    "printable_area": [
+        "0x0",
+        "256x0",
+        "256x256",
+        "0x256"
+    ],
+    "printable_height": "250",
+    "printer_extruder_id": [
+        "1",
+        "1"
+    ],
+    "printer_extruder_variant": [
+        "Direct Drive Standard",
+        "Direct Drive High Flow"
+    ],
+    "printer_model": "Bambu Lab P1S",
+    "printer_notes": "",
+    "printer_settings_id": "Bambu Lab P1S 0.4 nozzle",
+    "printer_structure": "corexy",
+    "printer_technology": "FFF",
+    "printer_variant": "0.4",
+    "printhost_authorization_type": "key",
+    "printhost_ssl_ignore_revoke": "0",
+    "printing_by_object_gcode": "",
+    "process_notes": "",
+    "raft_contact_distance": "0.1",
+    "raft_expansion": "1.5",
+    "raft_first_layer_density": "90%",
+    "raft_first_layer_expansion": "-1",
+    "raft_layers": "0",
+    "reduce_crossing_wall": "0",
+    "reduce_fan_stop_start_freq": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "reduce_infill_retraction": "1",
+    "required_nozzle_HRC": [
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3",
+        "3"
+    ],
+    "resolution": "0.012",
+    "retract_before_wipe": [
+        "0%",
+        "0%"
+    ],
+    "retract_length_toolchange": [
+        "2",
+        "2"
+    ],
+    "retract_lift_above": [
+        "0",
+        "0"
+    ],
+    "retract_lift_below": [
+        "249",
+        "249"
+    ],
+    "retract_restart_extra": [
+        "0",
+        "0"
+    ],
+    "retract_restart_extra_toolchange": [
+        "0",
+        "0"
+    ],
+    "retract_when_changing_layer": [
+        "1",
+        "1"
+    ],
+    "retraction_distances_when_cut": [
+        "18",
+        "18"
+    ],
+    "retraction_distances_when_ec": [
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0",
+        "0"
+    ],
+    "retraction_length": [
+        "0.8",
+        "0.8"
+    ],
+    "retraction_minimum_travel": [
+        "1",
+        "1"
+    ],
+    "retraction_speed": [
+        "30",
+        "30"
+    ],
+    "role_base_wipe_speed": "1",
+    "scan_first_layer": "0",
+    "scarf_angle_threshold": "155",
+    "seam_gap": "15%",
+    "seam_placement_away_from_overhangs": "0",
+    "seam_position": "aligned",
+    "seam_slope_conditional": "1",
+    "seam_slope_entire_loop": "0",
+    "seam_slope_gap": "0",
+    "seam_slope_inner_walls": "1",
+    "seam_slope_min_length": "10",
+    "seam_slope_start_height": "10%",
+    "seam_slope_steps": "10",
+    "seam_slope_type": "none",
+    "silent_mode": "0",
+    "single_extruder_multi_material": "1",
+    "skeleton_infill_density": "100%",
+    "skeleton_infill_line_width": "0.45",
+    "skin_infill_density": "100%",
+    "skin_infill_depth": "2",
+    "skin_infill_line_width": "0.45",
+    "skirt_distance": "2",
+    "skirt_height": "1",
+    "skirt_loops": "0",
+    "slice_closing_radius": "0.049",
+    "slicing_mode": "regular",
+    "slow_down_for_layer_cooling": [
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1",
+        "1"
+    ],
+    "slow_down_layer_time": [
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4",
+        "4"
+    ],
+    "slow_down_min_speed": [
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20",
+        "20"
+    ],
+    "slowdown_end_acc": [
+        "100000",
+        "100000"
+    ],
+    "slowdown_end_height": [
+        "400",
+        "400"
+    ],
+    "slowdown_end_speed": [
+        "1000",
+        "1000"
+    ],
+    "slowdown_start_acc": [
+        "100000",
+        "100000"
+    ],
+    "slowdown_start_height": [
+        "0",
+        "0"
+    ],
+    "slowdown_start_speed": [
+        "1000",
+        "1000"
+    ],
+    "small_perimeter_speed": [
+        "50%",
+        "50%"
+    ],
+    "small_perimeter_threshold": [
+        "0",
+        "0"
+    ],
+    "smooth_coefficient": "150",
+    "smooth_speed_discontinuity_area": "1",
+    "solid_infill_filament": "0",
+    "sparse_infill_acceleration": [
+        "100%",
+        "100%"
+    ],
+    "sparse_infill_anchor": "400%",
+    "sparse_infill_anchor_max": "20",
+    "sparse_infill_density": "100%",
+    "sparse_infill_filament": "0",
+    "sparse_infill_lattice_angle_1": "-45",
+    "sparse_infill_lattice_angle_2": "45",
+    "sparse_infill_line_width": "0.45",
+    "sparse_infill_pattern": "alignedrectilinear",
+    "sparse_infill_speed": [
+        "100",
+        "370"
+    ],
+    "spiral_mode": "0",
+    "spiral_mode_max_xy_smoothing": "200%",
+    "spiral_mode_smooth": "0",
+    "standby_temperature_delta": "-5",
+    "start_end_points": [
+        "30x-3",
+        "54x245"
+    ],
+    "supertack_plate_temp": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "supertack_plate_temp_initial_layer": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "support_air_filtration": "0",
+    "support_angle": "0",
+    "support_base_pattern": "default",
+    "support_base_pattern_spacing": "2.5",
+    "support_bottom_interface_spacing": "0.5",
+    "support_bottom_z_distance": "0.2",
+    "support_chamber_temp_control": "0",
+    "support_cooling_filter": "0",
+    "support_critical_regions_only": "0",
+    "support_expansion": "0",
+    "support_filament": "0",
+    "support_interface_bottom_layers": "2",
+    "support_interface_filament": "0",
+    "support_interface_loop_pattern": "0",
+    "support_interface_not_for_body": "1",
+    "support_interface_pattern": "auto",
+    "support_interface_spacing": "0.5",
+    "support_interface_speed": [
+        "80",
+        "80"
+    ],
+    "support_interface_top_layers": "2",
+    "support_ironing_direction": "0",
+    "support_ironing_flow": "10%",
+    "support_ironing_inset": "0",
+    "support_ironing_pattern": "zig-zag",
+    "support_ironing_spacing": "0.15",
+    "support_ironing_speed": "30",
+    "support_line_width": "0.42",
+    "support_object_first_layer_gap": "0.2",
+    "support_object_skip_flush": "0",
+    "support_object_xy_distance": "0.35",
+    "support_on_build_plate_only": "0",
+    "support_remove_small_overhang": "1",
+    "support_speed": [
+        "150",
+        "150"
+    ],
+    "support_style": "default",
+    "support_threshold_angle": "30",
+    "support_top_z_distance": "0.2",
+    "support_type": "tree(auto)",
+    "symmetric_infill_y_axis": "0",
+    "temperature_vitrification": [
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45",
+        "45"
+    ],
+    "template_custom_gcode": "",
+    "textured_plate_temp": [
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "textured_plate_temp_initial_layer": [
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55",
+        "55"
+    ],
+    "thick_bridges": "0",
+    "thumbnail_size": [
+        "50x50"
+    ],
+    "time_lapse_gcode": ";========Date 20250206========\n; SKIPPABLE_START\n; SKIPTYPE: timelapse\nM622.1 S1 ; for prev firmware, default turned on\nM1002 judge_flag timelapse_record_flag\nM622 J1\n{if timelapse_type == 0} ; timelapse without wipe tower\nM971 S11 C10 O0\nM1004 S5 P1  ; external shutter\n{elsif timelapse_type == 1} ; timelapse with wipe tower\nG92 E0\nG1 X65 Y245 F20000 ; move to safe pos\nG17\nG2 Z{layer_z} I0.86 J0.86 P1 F20000\nG1 Y265 F3000\nM400\nM1004 S5 P1  ; external shutter\nM400 P300\nM971 S11 C11 O0\nG92 E0\nG1 X100 F5000\nG1 Y255 F20000\n{endif}\nM623\n; SKIPPABLE_END",
+    "timelapse_type": "0",
+    "top_area_threshold": "200%",
+    "top_color_penetration_layers": "5",
+    "top_one_wall_type": "all top",
+    "top_shell_layers": "0",
+    "top_shell_thickness": "1",
+    "top_solid_infill_flow_ratio": [
+        "1",
+        "1"
+    ],
+    "top_surface_acceleration": [
+        "2000",
+        "2000"
+    ],
+    "top_surface_density": "100%",
+    "top_surface_jerk": "9",
+    "top_surface_line_width": "0.42",
+    "top_surface_pattern": "monotonicline",
+    "top_surface_speed": [
+        "100",
+        "300"
+    ],
+    "top_z_overrides_xy_distance": "0",
+    "travel_acceleration": [
+        "10000",
+        "10000"
+    ],
+    "travel_jerk": "9",
+    "travel_short_distance_acceleration": [
+        "250",
+        "250"
+    ],
+    "travel_speed": [
+        "500",
+        "500"
+    ],
+    "travel_speed_z": [
+        "0",
+        "0"
+    ],
+    "tree_support_branch_angle": "45",
+    "tree_support_branch_diameter": "2",
+    "tree_support_branch_diameter_angle": "5",
+    "tree_support_branch_distance": "5",
+    "tree_support_wall_count": "-1",
+    "upward_compatible_machine": [
+        "Bambu Lab P1P 0.4 nozzle",
+        "Bambu Lab X1 0.4 nozzle",
+        "Bambu Lab X1 Carbon 0.4 nozzle",
+        "Bambu Lab X1E 0.4 nozzle",
+        "Bambu Lab A1 0.4 nozzle",
+        "Bambu Lab H2D 0.4 nozzle",
+        "Bambu Lab H2D Pro 0.4 nozzle",
+        "Bambu Lab H2S 0.4 nozzle",
+        "Bambu Lab P2S 0.4 nozzle",
+        "Bambu Lab H2C 0.4 nozzle"
+    ],
+    "use_firmware_retraction": "0",
+    "use_relative_e_distances": "1",
+    "version": "02.05.00.66",
+    "vertical_shell_speed": [
+        "80%",
+        "80%"
+    ],
+    "volumetric_speed_coefficients": [
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0",
+        "0 0 0 0 0 0"
+    ],
+    "wall_distribution_count": "1",
+    "wall_filament": "0",
+    "wall_generator": "classic",
+    "wall_loops": "1",
+    "wall_sequence": "inner wall/outer wall",
+    "wall_transition_angle": "10",
+    "wall_transition_filter_deviation": "25%",
+    "wall_transition_length": "100%",
+    "wipe": [
+        "1",
+        "1"
+    ],
+    "wipe_distance": [
+        "2",
+        "2"
+    ],
+    "wipe_speed": "80%",
+    "wipe_tower_no_sparse_layers": "0",
+    "wipe_tower_rotation_angle": "0",
+    "wipe_tower_x": [
+        "18.5216"
+    ],
+    "wipe_tower_y": [
+        "214.154"
+    ],
+    "wrapping_detection_gcode": "",
+    "wrapping_detection_layers": "20",
+    "wrapping_exclude_area": [],
+    "xy_contour_compensation": "0",
+    "xy_hole_compensation": "0",
+    "z_direction_outwall_speed_continuous": "0",
+    "z_hop": [
+        "0.4",
+        "0.4"
+    ],
+    "z_hop_types": [
+        "Auto Lift",
+        "Auto Lift"
+    ]
+}
\ No newline at end of file
diff --git a/printer_profiles/bambu_p2s.json b/printer_profiles/bambu_p2s.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_p2s.json

diff --git a/printer_profiles/bambu_x1c.json b/printer_profiles/bambu_x1c.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_x1c.json

diff --git a/printer_profiles/bambu_x1e.json b/printer_profiles/bambu_x1e.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/bambu_x1e.json

diff --git a/printer_profiles/elegoo_cc2.json b/printer_profiles/elegoo_cc2.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/elegoo_cc2.json

diff --git a/printer_profiles/orca_a1.json b/printer_profiles/orca_a1.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_a1.json

diff --git a/printer_profiles/orca_a1_mini.json b/printer_profiles/orca_a1_mini.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_a1_mini.json

diff --git a/printer_profiles/orca_h2c.json b/printer_profiles/orca_h2c.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_h2c.json

diff --git a/printer_profiles/orca_h2d.json b/printer_profiles/orca_h2d.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_h2d.json

diff --git a/printer_profiles/orca_h2d_pro.json b/printer_profiles/orca_h2d_pro.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_h2d_pro.json

diff --git a/printer_profiles/orca_h2s.json b/printer_profiles/orca_h2s.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_h2s.json

diff --git a/printer_profiles/orca_p1p.json b/printer_profiles/orca_p1p.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_p1p.json

diff --git a/printer_profiles/orca_p1s.json b/printer_profiles/orca_p1s.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_p1s.json

diff --git a/printer_profiles/orca_p2s.json b/printer_profiles/orca_p2s.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_p2s.json

diff --git a/printer_profiles/orca_x1c.json b/printer_profiles/orca_x1c.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_x1c.json

diff --git a/printer_profiles/orca_x1e.json b/printer_profiles/orca_x1e.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/orca_x1e.json

diff --git a/printer_profiles/snapmaker_u1.json b/printer_profiles/snapmaker_u1.json
new file mode 100644
--- /dev/null
+++ b/printer_profiles/snapmaker_u1.json

diff --git a/utils/bambu_3mf_writer.py b/utils/bambu_3mf_writer.py
--- a/utils/bambu_3mf_writer.py
+++ b/utils/bambu_3mf_writer.py

__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
