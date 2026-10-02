#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/IMG_0892.JPG b/IMG_0892.JPG
new file mode 100644
--- /dev/null
+++ b/IMG_0892.JPG

diff --git a/api/routers/extractor.py b/api/routers/extractor.py
--- a/api/routers/extractor.py
+++ b/api/routers/extractor.py
@@ -271,7 +271,7 @@ def extractor_merge_5color_extended(
             merged_stacks = np.zeros((len(merged_rgb), 0), dtype=np.int32)
 
         # Use metadata from first page, update for merged result
-        metadata = LUTManager.infer_default_metadata("lumina_lut", LUT_FILE_PATH, len(merged_rgb))
+        metadata = LUTManager.infer_default_metadata("lumina_lut", LUT_FILE_PATH, len(merged_rgb), color_mode="5-Color Extended")
         LUTManager.save_keyed_json(LUT_FILE_PATH, merged_rgb, merged_stacks, metadata)
     except Exception as e:
         _handle_core_error(e, "5-Color Extended merge")
@@ -330,7 +330,7 @@ def extractor_merge_8color(
         else:
             merged_stacks = np.zeros((len(merged_rgb), 0), dtype=np.int32)
 
-        metadata = LUTManager.infer_default_metadata("lumina_lut", LUT_FILE_PATH, len(merged_rgb))
+        metadata = LUTManager.infer_default_metadata("lumina_lut", LUT_FILE_PATH, len(merged_rgb), color_mode="8-Color Max")
         LUTManager.save_keyed_json(LUT_FILE_PATH, merged_rgb, merged_stacks, metadata)
     except Exception as e:
         _handle_core_error(e, "8-Color merge")
diff --git a/config.py b/config.py
--- a/config.py
+++ b/config.py
@@ -458,6 +458,7 @@ class LUTMetadata:
 
     Attributes:
         palette (list[PaletteEntry]): Palette entries. (调色板条目列表)
+        color_mode (Optional[str]): Color mode identifier, e.g. "4-Color (RYBW)". (颜色模式标识)
         max_color_layers (int): Max color layers in recipe. (最大颜色层数)
         layer_height_mm (float): Layer height in mm. (层高，毫米)
         line_width_mm (float): Line width in mm. (线宽，毫米)
@@ -466,6 +467,7 @@ class LUTMetadata:
         layer_order (str): Print order, "Top2Bottom" or "Bottom2Top". (打印顺序)
     """
     palette: list[PaletteEntry] = field(default_factory=list)
+    color_mode: Optional[str] = None
     max_color_layers: int = 5
     layer_height_mm: float = 0.08
     line_width_mm: float = 0.42
@@ -487,7 +489,7 @@ def to_dict(self) -> dict:
                 entry["hex_color"] = e.hex_color
             palette_obj[e.color] = entry
 
-        return {
+        d = {
             "palette": palette_obj,
             "max_color_layers": self.max_color_layers,
             "layer_height_mm": self.layer_height_mm,
@@ -496,6 +498,9 @@ def to_dict(self) -> dict:
             "base_channel_idx": self.base_channel_idx,
             "layer_order": self.layer_order,
         }
+        if self.color_mode is not None:
+            d["color_mode"] = self.color_mode
+        return d
 
     @classmethod
     def from_dict(cls, data: dict) -> "LUTMetadata":
@@ -532,6 +537,7 @@ def from_dict(cls, data: dict) -> "LUTMetadata":
 
         return cls(
             palette=palette,
+            color_mode=data.get("color_mode"),
             max_color_layers=int(data.get("max_color_layers", 5)),
             layer_height_mm=float(data.get("layer_height_mm", 0.08)),
             line_width_mm=float(data.get("line_width_mm", 0.42)),
diff --git a/core/converter.py b/core/converter.py
--- a/core/converter.py
+++ b/core/converter.py
@@ -747,3 +747,350 @@ def on_preview_click_select_color(cache, evt: gr.SelectData, bed_label=None):
         return gr.update(), display_text, q_hex, status_msg
 
     return display_img, display_text, q_hex, status_msg
+
+
+def generate_lut_grid_html(lut_path, lang: str = "zh"):
+    """
+    生成 LUT 可用颜色的 HTML 网格 (with hue filter + smart search)
+    """
+    from core.i18n import I18n
+    import colorsys
+    colors = extract_lut_available_colors(lut_path)
+
+    if not colors:
+        return f"<div style='color:orange'>LUT 文件无效或为空</div>"
+
+    count = len(colors)
+
+    def _classify_hue(r, g, b):
+        rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
+        h, s, v = colorsys.rgb_to_hsv(rf, gf, bf)
+        h360 = h * 360
+        if s < 0.15 or v < 0.10:
+            return 'neutral'
+        if h360 < 15 or h360 >= 345:
+            return 'red'
+        elif h360 < 40:
+            return 'orange'
+        elif h360 < 70:
+            return 'yellow'
+        elif h360 < 160:
+            return 'green'
+        elif h360 < 195:
+            return 'cyan'
+        elif h360 < 260:
+            return 'blue'
+        elif h360 < 345:
+            return 'purple'
+        return 'neutral'
+
+    from ui.palette_extension import build_search_bar_html, build_hue_filter_bar_html
+
+    # Derive LUT key for favorites persistence
+    _lut_key = os.path.splitext(os.path.basename(lut_path))[0] if lut_path else ''
+
+    html = f"""
+    <div class="lut-grid-container">
+        <div style="margin-bottom: 8px; font-size: 12px; color: #666;">
+            {I18n.get('lut_grid_count', lang).format(count=count)}: <span id="lut-color-visible-count">{count}</span>
+        </div>
+        {build_search_bar_html(lang)}
+        {build_hue_filter_bar_html(lang)}
+        <div id="lut-color-grid-container" data-lut-key="{_lut_key}" style="
+            display: flex;
+            flex-wrap: wrap;
+            gap: 4px;
+            max-height: 300px;
+            overflow-y: auto;
+            padding: 5px;
+            border: 1px solid #eee;
+            border-radius: 8px;
+            background: #f9f9f9;">
+    """
+
+    for entry in colors:
+        hex_val = entry['hex']
+        r, g, b = entry['color']
+        rgb_val = f"R:{r} G:{g} B:{b}"
+        hue_cat = _classify_hue(r, g, b)
+
+        html += f"""
+        <div class="lut-color-swatch-container" data-hue="{hue_cat}" style="display:flex;">
+        <div class="lut-swatch lut-color-swatch"
+             data-color="{hex_val}"
+             style="background-color: {hex_val}; width:24px; height:24px; cursor:pointer; border:1px solid #ddd; border-radius:3px;"
+             title="{hex_val} ({rgb_val})">
+        </div>
+        </div>
+        """
+
+    html += "</div></div>"
+    return html
+
+
+def generate_lut_card_grid_html(lut_path, lang: str = "zh"):
+    """
+    Generate a calibration-card-style (色卡) HTML grid for the LUT.
+
+    Colors are displayed in their original LUT order arranged in a square grid,
+    matching the physical calibration board layout.  For 8-color LUTs the two
+    halves are shown side-by-side horizontally.
+
+    Includes search bar (highlight-in-place, no hiding) and hue filter
+    (dims non-matching swatches instead of hiding to preserve grid layout).
+
+    Each swatch is clickable (same data-color / class as the swatch grid) so
+    the existing event-delegation click handler picks it up automatically.
+    """
+    if not lut_path:
+        return "<div style='color:orange'>LUT 文件无效或为空</div>"
+
+    try:
+        lut_grid = np.load(lut_path)
+        measured_colors = lut_grid.reshape(-1, 3)
+    except Exception as e:
+        return f"<div style='color:orange'>LUT 加载失败: {e}</div>"
+
+    total = len(measured_colors)
+
+    from core.i18n import I18n
+    import colorsys
+
+    def _classify_hue(r, g, b):
+        rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
+        h, s, v = colorsys.rgb_to_hsv(rf, gf, bf)
+        h360 = h * 360
+        if s < 0.15 or v < 0.10:
+            return 'neutral'
+        if h360 < 15 or h360 >= 345:
+            return 'red'
+        elif h360 < 40:
+            return 'orange'
+        elif h360 < 70:
+            return 'yellow'
+        elif h360 < 160:
+            return 'green'
+        elif h360 < 195:
+            return 'cyan'
+        elif h360 < 260:
+            return 'blue'
+        elif h360 < 345:
+            return 'purple'
+        return 'neutral'
+
+    import math
+    if total == 2738:
+        half = total // 2
+        remainder = total - half
+        dim1 = int(math.ceil(math.sqrt(half)))
+        dim2 = int(math.ceil(math.sqrt(remainder)))
+        grids = [
+            (measured_colors[:half], dim1, "色卡 A" if lang == "zh" else "Card A"),
+            (measured_colors[half:], dim2, "色卡 B" if lang == "zh" else "Card B"),
+        ]
+    else:
+        dim = int(math.ceil(math.sqrt(total)))
+        label = f"{total} 色色卡" if lang == "zh" else f"{total}-color Card"
+        grids = [(measured_colors, dim, label)]
+
+    cell = 18
+    gap = 1
+
+    from ui.palette_extension import build_search_bar_html, build_hue_filter_bar_html
+
+    html_parts = [
+        f'<div style="margin-bottom:8px; font-size:12px; color:#666;">{I18n.get("lut_grid_count", lang).format(count=total)}: <span id="lut-color-visible-count">{total}</span></div>',
+        build_search_bar_html(lang),
+        build_hue_filter_bar_html(lang),
+    ]
+
+    # Derive LUT key for favorites persistence
+    _lut_key = os.path.splitext(os.path.basename(lut_path))[0] if lut_path else ''
+
+    # Grid
+    html_parts.append(
+        f"<div id='lut-color-grid-container' data-lut-key='{_lut_key}' style='display:flex; gap:12px; align-items:flex-start; "
+        "overflow-x:auto; padding:4px;'>"
+    )
+
+    for colors_arr, dim, title in grids:
+        html_parts.append(
+            f"<div style='flex-shrink:0;'>"
+            f"<div style='font-size:11px; color:#666; margin-bottom:4px;'>{title} ({len(colors_arr)})</div>"
+            f"<div style='display:grid; grid-template-columns:repeat({dim}, {cell}px); gap:{gap}px; "
+            f"border:1px solid #eee; border-radius:6px; padding:4px; background:#f9f9f9;'>"
+        )
+        for c in colors_arr:
+            r, g, b = int(c[0]), int(c[1]), int(c[2])
+            hex_val = f"#{r:02x}{g:02x}{b:02x}"
+            hue_cat = _classify_hue(r, g, b)
+            html_parts.append(
+                f"<div class='lut-swatch lut-color-swatch' data-color='{hex_val}' data-hue='{hue_cat}' "
+                f"style='width:{cell}px;height:{cell}px;background:{hex_val};"
+                f"cursor:pointer;border-radius:2px;' "
+                f"title='{hex_val} (R:{r} G:{g} B:{b})'></div>"
+            )
+        html_parts.append("</div></div>")
+
+    html_parts.append("</div>")
+    return "".join(html_parts)
+
+
+# ========== Auto-detection Functions ==========
+
+def detect_lut_color_mode(lut_path):
+    """
+    自动检测LUT文件的颜色模式
+    
+    Args:
+        lut_path: LUT文件路径
+    
+    Returns:
+        str: 颜色模式 ("BW (Black & White)", "Merged", "6-Color (Smart 1296)", "8-Color Max", etc.)
+    """
+    if not lut_path or not os.path.exists(lut_path):
+        return None
+    
+    try:
+        if lut_path.endswith('.npz'):
+            data = np.load(lut_path)
+            if 'rgb' in data:
+                rgb = data['rgb']
+                total_colors = int(rgb.reshape(-1, 3).shape[0])
+                stacks = data['stacks'] if 'stacks' in data else None
+                layer_count = int(stacks.shape[1]) if isinstance(stacks, np.ndarray) and stacks.ndim == 2 else None
+                max_mat = int(np.max(stacks)) if isinstance(stacks, np.ndarray) and stacks.size > 0 else None
+                if total_colors >= 2400 and total_colors < 2600 and layer_count == 6 and (max_mat is None or max_mat <= 4):
+                    print(f"[AUTO_DETECT] Detected 5-Color Extended mode from .npz ({total_colors} colors)")
+                    return "5-Color Extended"
+                if total_colors >= 2600 and total_colors <= 2800:
+                    print(f"[AUTO_DETECT] Detected 8-Color mode from .npz ({total_colors} colors)")
+                    return "8-Color Max"
+                if total_colors >= 1200 and total_colors < 1400:
+                    print(f"[AUTO_DETECT] Detected 6-Color mode from .npz ({total_colors} colors)")
+                    return "6-Color (Smart 1296)"
+                if total_colors >= 900 and total_colors < 1200:
+                    print(f"[AUTO_DETECT] Detected 4-Color mode from .npz ({total_colors} colors)")
+                    return "4-Color"
+                if total_colors >= 30 and total_colors <= 35:
+                    print(f"[AUTO_DETECT] Detected 2-Color BW mode from .npz ({total_colors} colors)")
+                    return "BW (Black & White)"
+            print(f"[AUTO_DETECT] Detected Merged LUT (.npz format)")
+            return "Merged"
+        
+        # .json (Keyed JSON) format
+        if lut_path.endswith('.json'):
+            from utils.lut_manager import LUTManager
+            rgb, stacks, _meta = LUTManager.load_lut_with_metadata(lut_path)
+            # 优先使用存储的 color_mode
+            if _meta and _meta.color_mode:
+                print(f"[AUTO_DETECT] Using stored color_mode from metadata: {_meta.color_mode}")
+                return _meta.color_mode
+            # 回退到基于数量的推断
+            total_colors = len(rgb) if rgb is not None else 0
+            layer_count = int(stacks.shape[1]) if isinstance(stacks, np.ndarray) and stacks.ndim == 2 else None
+            max_mat = int(np.max(stacks)) if isinstance(stacks, np.ndarray) and stacks.size > 0 else None
+            print(f"[AUTO_DETECT] JSON LUT: {total_colors} colors, layer_count={layer_count}, max_mat={max_mat}")
+            if total_colors >= 2400 and total_colors < 2600 and layer_count == 6 and (max_mat is None or max_mat <= 4):
+                print(f"[AUTO_DETECT] Detected 5-Color Extended mode from .json ({total_colors} colors)")
+                return "5-Color Extended"
+            if total_colors >= 2600 and total_colors <= 2800:
+                print(f"[AUTO_DETECT] Detected 8-Color mode from .json ({total_colors} colors)")
+                return "8-Color Max"
+            if total_colors >= 1200 and total_colors < 1400:
+                print(f"[AUTO_DETECT] Detected 6-Color mode from .json ({total_colors} colors)")
+                return "6-Color (Smart 1296)"
+            if total_colors >= 900 and total_colors < 1200:
+                print(f"[AUTO_DETECT] Detected 4-Color mode from .json ({total_colors} colors)")
+                return "4-Color"
+            if total_colors >= 30 and total_colors <= 35:
+                print(f"[AUTO_DETECT] Detected 2-Color BW mode from .json ({total_colors} colors)")
+                return "BW (Black & White)"
+            print(f"[AUTO_DETECT] Non-standard JSON LUT size ({total_colors} colors), detected as Merged")
+            return "Merged"
+        
+        # Standard .npy format
+        lut_data = np.load(lut_path)
+        
+        # 确保是2D数组
+        if lut_data.ndim == 1:
+            # 如果是1D数组，假设是 (N*3,) 格式，重塑为 (N, 3)
+            if len(lut_data) % 3 == 0:
+                lut_data = lut_data.reshape(-1, 3)
+            else:
+                print(f"[AUTO_DETECT] Invalid LUT format: cannot reshape to (N, 3)")
+                return None
+        
+        # 计算颜色数量
+        if lut_data.ndim == 2:
+            total_colors = lut_data.shape[0]
+        else:
+            total_colors = lut_data.shape[0] * lut_data.shape[1]
+        
+        print(f"[AUTO_DETECT] LUT shape: {lut_data.shape}, total colors: {total_colors}")
+        
+        # 2色模式：32色 (2^5 = 32)
+        if total_colors >= 30 and total_colors <= 35:
+            print(f"[AUTO_DETECT] Detected 2-Color BW mode (32 colors)")
+            return "BW (Black & White)"
+        
+        # 5-Color Extended模式：~2468色 (1024 base + 1444 extended)
+        elif total_colors >= 2400 and total_colors < 2600:
+            print(f"[AUTO_DETECT] Detected 5-Color Extended mode ({total_colors} colors)")
+            return "5-Color Extended"
+        
+        # 8色模式：2600-2800色
+        elif total_colors >= 2600 and total_colors <= 2800:
+            print(f"[AUTO_DETECT] Detected 8-Color mode ({total_colors} colors)")
+            return "8-Color Max"
+        
+        # 6色模式：1200-1400色
+        elif total_colors >= 1200 and total_colors < 1400:
+            print(f"[AUTO_DETECT] Detected 6-Color mode ({total_colors} colors)")
+            return "6-Color (Smart 1296)"
+        
+        # 4色模式：900-1200色
+        elif total_colors >= 900 and total_colors < 1200:
+            print(f"[AUTO_DETECT] Detected 4-Color mode ({total_colors} colors)")
+            return "4-Color"
+        
+        else:
+            # 非标准尺寸：识别为合并色卡
+            print(f"[AUTO_DETECT] Non-standard LUT size ({total_colors} colors), detected as Merged")
+            return "Merged"
+            
+    except Exception as e:
+        print(f"[AUTO_DETECT] Error detecting LUT mode: {e}")
+        import traceback
+        traceback.print_exc()
+        return None
+
+
+def detect_image_type(image_path):
+    """
+    Detect image type and return recommended modeling mode.
+    自动检测图像类型并返回推荐的建模模式。
+
+    Args:
+        image_path (str): Image file path. (图像文件路径)
+
+    Returns:
+        gr.update: Gradio update object with new mode, or no-op update. (Gradio 更新对象)
+    """
+    import gradio as gr
+    if not image_path:
+        return gr.update()
+    
+    try:
+        ext = os.path.splitext(image_path)[1].lower()
+        
+        if ext == '.svg':
+            print(f"[AUTO_DETECT] SVG file detected, recommending SVG Mode")
+            return gr.update(value=ModelingMode.VECTOR)
+        else:
+            print(f"[AUTO_DETECT] Raster image detected ({ext}), keeping current mode")
+            return gr.update()  # 不改变当前选择
+            
+    except Exception as e:
+        print(f"[AUTO_DETECT] Error detecting image type: {e}")
+        return None
diff --git a/core/extractor.py b/core/extractor.py
--- a/core/extractor.py
+++ b/core/extractor.py
@@ -372,7 +372,7 @@ def run_extraction(img, points, offset_x, offset_y, zoom, barrel, wb, bright, co
 
     # 保存为 Keyed JSON 格式
     rgb_flat = extracted.reshape(-1, 3)[:total_cells]
-    metadata = LUTManager.infer_default_metadata("lumina_lut", LUT_FILE_PATH, len(rgb_flat))
+    metadata = LUTManager.infer_default_metadata("lumina_lut", LUT_FILE_PATH, len(rgb_flat), color_mode=color_mode)
     # 根据颜色模式生成配方
     stacks = _generate_recipes(color_mode, total_cells, page_choice)
     LUTManager.save_keyed_json(LUT_FILE_PATH, rgb_flat, stacks, metadata)
diff --git a/core/lut_merger.py b/core/lut_merger.py
--- a/core/lut_merger.py
+++ b/core/lut_merger.py
@@ -98,53 +98,83 @@ def _detect_mode_by_size(count):
 }
 
 
-def _detect_4color_subtype(lut_path):
-    """Detect 4-Color subtype (RYBW or CMYW) from filename.
+def _detect_4color_subtype(lut_path, metadata=None):
+    """Detect 4-Color subtype (RYBW or CMYW) from metadata or filename.
+    从 metadata 或文件名检测 4 色子类型（RYBW 或 CMYW）。
 
-    Naming convention: filename containing 'RYBW' → RYBW, 'CMYW' → CMYW.
-    Default: RYBW (most common).
+    Priority: metadata.color_mode > filename keyword.
+    优先级：metadata.color_mode > 文件名关键词。
+
+    Args:
+        lut_path (str): LUT file path. (LUT 文件路径)
+        metadata (LUTMetadata | None): Optional metadata with color_mode. (可选的含 color_mode 的元数据)
+
+    Returns:
+        str: "4-Color-RYBW" or "4-Color-CMYW". (4 色子类型字符串)
     """
+    if metadata and metadata.color_mode:
+        if "RYBW" in metadata.color_mode:
+            return "4-Color-RYBW"
+        if "CMYW" in metadata.color_mode:
+            return "4-Color-CMYW"
+    # 回退到文件名检测
     basename = os.path.basename(lut_path).upper()
     if "CMYW" in basename:
         return "4-Color-CMYW"
     return "4-Color-RYBW"
 
 
-def _detect_6color_subtype(lut_path):
-    """Detect 6-Color subtype (CMYWGK or RYBWGK) from filename.
+def _detect_6color_subtype(lut_path, metadata=None):
+    """Detect 6-Color subtype (CMYWGK or RYBWGK) from metadata or filename.
+    从 metadata 或文件名检测 6 色子类型（CMYWGK 或 RYBWGK）。
+
+    Priority: metadata.color_mode > filename keyword.
+    优先级：metadata.color_mode > 文件名关键词。
 
-    Naming convention: filename containing 'RYBW' → RYBWGK, 'CMYW' → CMYWGK.
-    Default: CMYWGK (most common for 6-color).
+    Args:
+        lut_path (str): LUT file path. (LUT 文件路径)
+        metadata (LUTMetadata | None): Optional metadata with color_mode. (可选的含 color_mode 的元数据)
+
+    Returns:
+        str: "6-Color-RYBWGK" or "6-Color-CMYWGK". (6 色子类型字符串)
     """
+    if metadata and metadata.color_mode:
+        if "RYBW" in metadata.color_mode:
+            return "6-Color-RYBWGK"
+    # 回退到文件名检测
     basename = os.path.basename(lut_path).upper()
     if "RYBW" in basename:
         return "6-Color-RYBWGK"
     return "6-Color-CMYWGK"
 
 
-def _remap_stacks(stacks, color_mode, lut_path=None):
+def _remap_stacks(stacks, color_mode, lut_path=None, metadata=None):
     """Remap material IDs in stacks from source mode to 8-Color space.
+    将堆叠中的材料 ID 从源模式重映射到 8-Color 空间。
 
     When merging LUTs from different color modes, each mode uses its own
     material ID numbering. This function translates them all into the
     unified 8-Color numbering so the merged LUT produces correct meshes.
 
     Args:
-        stacks: numpy array (N, 5) of material IDs
-        color_mode: source color mode string
-        lut_path: optional file path, used to detect 4-Color/6-Color subtype
+        stacks: numpy array (N, 5) of material IDs. (材料 ID 数组)
+        color_mode: source color mode string. (源颜色模式字符串)
+        lut_path: optional file path, used to detect 4-Color/6-Color subtype.
+            (可选文件路径，用于检测子类型)
+        metadata (LUTMetadata | None): optional metadata with color_mode for
+            subtype detection priority. (可选元数据，用于子类型检测优先级)
 
     Returns:
-        numpy array (N, 5) with remapped material IDs
+        numpy array (N, 5) with remapped material IDs. (重映射后的材料 ID 数组)
     """
     if color_mode == "8-Color" or color_mode == "Merged":
         return stacks  # Already in 8-Color space
 
     remap_key = color_mode
     if color_mode == "4-Color" and lut_path:
-        remap_key = _detect_4color_subtype(lut_path)
+        remap_key = _detect_4color_subtype(lut_path, metadata=metadata)
     elif color_mode == "6-Color" and lut_path:
-        remap_key = _detect_6color_subtype(lut_path)
+        remap_key = _detect_6color_subtype(lut_path, metadata=metadata)
 
     remap = _REMAP_TO_8COLOR.get(remap_key)
     if remap is None:
@@ -263,7 +293,7 @@ def load_lut_with_stacks(lut_path: str, color_mode: str):
                 return (rgb, stacks)
             # 回退到索引重建：stacks 为 None 或 shape[1]==0
             count = len(rgb)
-            return LUTMerger._rebuild_stacks_from_index(rgb, count, color_mode, lut_path)
+            return LUTMerger._rebuild_stacks_from_index(rgb, count, color_mode, lut_path, metadata=metadata)
 
         # .npy 格式：加载 RGB，根据模式重建堆叠
         lut_data = np.load(lut_path)
@@ -273,17 +303,20 @@ def load_lut_with_stacks(lut_path: str, color_mode: str):
         return LUTMerger._rebuild_stacks_from_index(rgb, count, color_mode, lut_path)
 
     @staticmethod
-    def _rebuild_stacks_from_index(rgb, count, color_mode, lut_path):
+    def _rebuild_stacks_from_index(rgb, count, color_mode, lut_path, metadata=None):
         """根据索引重建堆叠数组（从 .npy 或 .json 无 stacks 时回退使用）
+        Rebuild stacks array from index when loading .npy or .json without stacks.
 
         Args:
-            rgb: RGB 数组 [N, 3]
-            count: 颜色数量
-            color_mode: 色彩模式字符串
-            lut_path: LUT 文件路径（用于检测子类型）
+            rgb: RGB 数组 [N, 3]. (RGB array)
+            count: 颜色数量. (color count)
+            color_mode: 色彩模式字符串. (color mode string)
+            lut_path: LUT 文件路径（用于检测子类型）. (LUT file path for subtype detection)
+            metadata (LUTMetadata | None): 可选元数据，用于子类型检测优先级.
+                (optional metadata for subtype detection priority)
 
         Returns:
-            (rgb_array[N,3], stacks_array[N,L])
+            (rgb_array[N,3], stacks_array[N,L]). (RGB 和堆叠数组)
         """
         if color_mode == "BW":
             stacks = []
@@ -295,7 +328,7 @@ def _rebuild_stacks_from_index(rgb, count, color_mode, lut_path):
                     temp //= 2
                 stacks.append(tuple(reversed(digits)))
             stacks_arr = np.array(stacks)
-            return (rgb, _remap_stacks(stacks_arr, color_mode, lut_path))
+            return (rgb, _remap_stacks(stacks_arr, color_mode, lut_path, metadata=metadata))
 
         elif color_mode == "4-Color":
             stacks = []
@@ -307,10 +340,10 @@ def _rebuild_stacks_from_index(rgb, count, color_mode, lut_path):
                     temp //= 4
                 stacks.append(tuple(reversed(digits)))
             stacks_arr = np.array(stacks)
-            return (rgb, _remap_stacks(stacks_arr, color_mode, lut_path))
+            return (rgb, _remap_stacks(stacks_arr, color_mode, lut_path, metadata=metadata))
 
         elif color_mode == "6-Color":
-            subtype = _detect_6color_subtype(lut_path) if lut_path else "6-Color"
+            subtype = _detect_6color_subtype(lut_path, metadata=metadata) if lut_path else "6-Color"
             if "RYBW" in subtype:
                 from core.calibration import get_top_1296_colors_rybw
                 raw_stacks = get_top_1296_colors_rybw()
@@ -320,7 +353,7 @@ def _rebuild_stacks_from_index(rgb, count, color_mode, lut_path):
             stacks = [tuple(reversed(s)) for s in raw_stacks]
             min_len = min(len(stacks), count)
             stacks_arr = np.array(stacks[:min_len])
-            return (rgb[:min_len], _remap_stacks(stacks_arr, color_mode, lut_path))
+            return (rgb[:min_len], _remap_stacks(stacks_arr, color_mode, lut_path, metadata=metadata))
 
         elif color_mode == "8-Color":
             from config import get_asset_path
@@ -334,7 +367,7 @@ def _rebuild_stacks_from_index(rgb, count, color_mode, lut_path):
             if lut_path.endswith('.npz'):
                 data = np.load(lut_path)
                 stacks = data['stacks']
-                return (rgb, _remap_stacks(stacks, color_mode, lut_path))
+                return (rgb, _remap_stacks(stacks, color_mode, lut_path, metadata=metadata))
 
             base_stacks = []
             for i in range(1024):
@@ -368,7 +401,7 @@ def _rebuild_stacks_from_index(rgb, count, color_mode, lut_path):
             stacks = padded_base + ext_stacks
 
             stacks_arr = np.array(stacks[:count])
-            return (rgb, _remap_stacks(stacks_arr, color_mode, lut_path))
+            return (rgb, _remap_stacks(stacks_arr, color_mode, lut_path, metadata=metadata))
 
         else:
             layer_count = 5
diff --git a/core/slicer.py b/core/slicer.py
--- a/core/slicer.py
+++ b/core/slicer.py
@@ -20,11 +20,12 @@
 # ---------------------------------------------------------------------------
 
 KNOWN_SLICERS: dict[str, dict] = {
-    "bambu_studio":  {"match": ["bambu studio"],                          "display_name": "Bambu Studio"},
-    "orca_slicer":   {"match": ["orcaslicer"],                            "display_name": "OrcaSlicer"},
-    "elegoo_slicer": {"match": ["elegooslicer", "elegoo slicer", "elegoo satellit"], "display_name": "ElegooSlicer"},
-    "prusa_slicer":  {"match": ["prusaslicer"],                           "display_name": "PrusaSlicer"},
-    "cura":          {"match": ["ultimaker cura", "ultimaker-cura"],      "display_name": "Ultimaker Cura"},
+    "bambu_studio":    {"match": ["bambu studio"],                          "display_name": "Bambu Studio"},
+    "orca_slicer":     {"match": ["orcaslicer"],                            "display_name": "OrcaSlicer"},
+    "snapmaker_orca":  {"match": ["snapmaker_orca", "snapmaker orca"],      "display_name": "Snapmaker Orca"},
+    "elegoo_slicer":   {"match": ["elegooslicer", "elegoo slicer", "elegoo satellit"], "display_name": "ElegooSlicer"},
+    "prusa_slicer":    {"match": ["prusaslicer"],                           "display_name": "PrusaSlicer"},
+    "cura":            {"match": ["ultimaker cura", "ultimaker-cura"],      "display_name": "Ultimaker Cura"},
 }
 
 
@@ -74,16 +75,34 @@ def _extract_exe_from_icon(icon_value: str) -> str | None:
     return None
 
 
-def _find_exe_in_directory(directory: str) -> str | None:
-    """Find the first non-uninstaller .exe in *directory*."""
+def _find_exe_in_directory(directory: str, hint: str = "") -> str | None:
+    """Find the slicer .exe in *directory*.
+    找到目录中的切片器可执行文件。
+
+    Args:
+        directory (str): Directory to search. (搜索目录)
+        hint (str): Lowercase keyword to prefer in filename. (文件名优先匹配关键词)
+
+    Returns:
+        str | None: Path to exe or None. (可执行文件路径或 None)
+    """
     if not os.path.isdir(directory):
         return None
+    candidates: list[str] = []
     for fname in os.listdir(directory):
-        if fname.lower().endswith(".exe") and "unins" not in fname.lower():
-            candidate = os.path.join(directory, fname)
-            if os.path.isfile(candidate):
-                return candidate
-    return None
+        fl = fname.lower()
+        if fl.endswith(".exe") and "unins" not in fl and "crashpad" not in fl:
+            candidates.append(os.path.join(directory, fname))
+    if not candidates:
+        return None
+    # Prefer exe whose name contains the hint keyword
+    if hint:
+        for c in candidates:
+            # Compare with hyphens/underscores stripped for fuzzy match
+            basename = os.path.basename(c).lower().replace("-", "").replace("_", "")
+            if hint in basename:
+                return c
+    return candidates[0]
 
 
 def scan_registry() -> list[DetectedSlicer]:
@@ -148,7 +167,20 @@ def scan_registry() -> list[DetectedSlicer]:
                 if exe_path is None:
                     try:
                         install_loc: str = winreg.QueryValueEx(subkey, "InstallLocation")[0]
-                        exe_path = _find_exe_in_directory(install_loc)
+                        exe_hint = sid.replace("_", "")  # e.g. "snapmakerorca"
+                        exe_path = _find_exe_in_directory(install_loc, hint=exe_hint)
+                    except OSError:
+                        pass
+
+                # 3) Fallback: derive directory from UninstallString
+                if exe_path is None:
+                    try:
+                        uninst: str = winreg.QueryValueEx(subkey, "UninstallString")[0]
+                        uninst_path = uninst.strip().strip('"')
+                        uninst_dir = os.path.dirname(uninst_path)
+                        if uninst_dir:
+                            exe_hint = sid.replace("_", "")
+                            exe_path = _find_exe_in_directory(uninst_dir, hint=exe_hint)
                     except OSError:
                         pass
 
diff --git a/frontend/src/components/CalibrationPanel.tsx b/frontend/src/components/CalibrationPanel.tsx
--- a/frontend/src/components/CalibrationPanel.tsx
+++ b/frontend/src/components/CalibrationPanel.tsx
@@ -1,3 +1,4 @@
+import { motion } from "framer-motion";
 import { useCalibrationStore } from "../stores/calibrationStore";
 import { useI18n } from "../i18n/context";
 import { CalibrationColorMode, BackingColor } from "../api/types";
@@ -42,9 +43,12 @@ export default function CalibrationPanel() {
   const backingDisabled = isEightColor || isFiveColorExt || isSixColor;
 
   return (
-    <aside
+    <motion.aside
+      initial={{ opacity: 0, y: 30 }}
+      animate={{ opacity: 1, y: 0 }}
+      transition={{ type: "spring", damping: 25, stiffness: 300 }}
       data-testid="calibration-panel"
-      className="w-full max-w-2xl mx-auto h-full overflow-y-auto bg-white dark:bg-gray-800 p-6 flex flex-col gap-4"
+      className="w-full max-w-2xl mx-auto h-full overflow-y-auto bg-white/85 dark:bg-gray-900/85 backdrop-blur-2xl border border-white/40 dark:border-gray-700/50 shadow-2xl rounded-2xl p-6 flex flex-col gap-4"
     >
       <Dropdown
         label={t("cal_color_mode_label")}
@@ -122,6 +126,6 @@ export default function CalibrationPanel() {
           className="w-full rounded-md border border-gray-300 dark:border-gray-700"
         />
       )}
-    </aside>
+    </motion.aside>
   );
 }
diff --git a/frontend/src/components/ExtractorPanel.tsx b/frontend/src/components/ExtractorPanel.tsx
--- a/frontend/src/components/ExtractorPanel.tsx
+++ b/frontend/src/components/ExtractorPanel.tsx
@@ -1,3 +1,4 @@
+import { motion } from "framer-motion";
 import { useExtractorStore } from "../stores/extractorStore";
 import { useI18n } from "../i18n/context";
 import { ExtractorColorMode, ExtractorPage } from "../api/types";
@@ -14,23 +15,8 @@ const colorModeOptions = Object.values(ExtractorColorMode).map((v) => ({
 
 /** 常见 Bambu Lab 耗材类型 */
 const MATERIAL_OPTIONS = [
-  "PLA Basic",
-  "PLA Matte",
-  "PLA Silk",
-  "PLA Metal",
-  "PLA Glow",
-  "PLA Marble",
-  "PLA-CF",
-  "PETG Basic",
-  "PETG HF",
-  "PETG-CF",
-  "ABS",
-  "ASA",
-  "TPU 95A",
-  "PVA",
-  "PA",
-  "PA-CF",
-  "PC",
+  "PLA",
+  "PETG",
 ];
 
 const pageOptions = Object.values(ExtractorPage).map((v) => ({
@@ -96,9 +82,12 @@ export default function ExtractorPanel() {
     imageFile === null || corner_points.length < 4 || isLoading;
 
   return (
-    <aside
+    <motion.aside
+      initial={{ opacity: 0, x: -30 }}
+      animate={{ opacity: 1, x: 0 }}
+      transition={{ type: "spring", damping: 25, stiffness: 300 }}
       data-testid="extractor-panel"
-      className="w-[400px] shrink-0 h-full overflow-y-auto bg-white dark:bg-gray-800 p-4 flex flex-col gap-4"
+      className="w-[400px] shrink-0 h-full overflow-y-auto bg-white/85 dark:bg-gray-900/85 backdrop-blur-2xl border-r border-white/40 dark:border-gray-700/50 shadow-[12px_0_30px_rgba(0,0,0,0.12)] p-4 flex flex-col gap-4"
     >
       {/* 颜色模式 */}
       <div data-testid="color-mode-select">
@@ -180,7 +169,7 @@ export default function ExtractorPanel() {
           </span>
           {/* 统一耗材类型选择 */}
           <div className="flex items-center gap-2 text-xs">
-            <span className="text-gray-500 dark:text-gray-400 shrink-0">耗材类型</span>
+            <span className="text-gray-500 dark:text-gray-400 shrink-0">{t("ext_material_type_label")}</span>
             <select
               className="flex-1 px-1 py-0.5 rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-800 dark:text-gray-200 text-xs"
               value={defaultPalette[0]?.material ?? "PLA Basic"}
@@ -251,6 +240,6 @@ export default function ExtractorPanel() {
       {manualFixError && (
         <p data-testid="manual-fix-error" className="text-xs text-red-400">{manualFixError}</p>
       )}
-    </aside>
+    </motion.aside>
   );
 }
diff --git a/frontend/src/components/FiveColorQueryPanel.tsx b/frontend/src/components/FiveColorQueryPanel.tsx
--- a/frontend/src/components/FiveColorQueryPanel.tsx
+++ b/frontend/src/components/FiveColorQueryPanel.tsx
@@ -1,3 +1,4 @@
+import { motion } from "framer-motion";
 import { useEffect, useMemo } from "react";
 import { useFiveColorStore } from "../stores/fiveColorStore";
 import { useConverterStore } from "../stores/converterStore";
@@ -38,7 +39,12 @@ export default function FiveColorQueryPanel() {
   );
 
   return (
-    <div className="flex h-full bg-white dark:bg-gray-950 text-gray-900 dark:text-white">
+    <motion.div
+      initial={{ opacity: 0, y: 30 }}
+      animate={{ opacity: 1, y: 0 }}
+      transition={{ type: "spring", damping: 25, stiffness: 300 }}
+      className="flex h-full w-full max-w-5xl mx-auto rounded-2xl overflow-hidden shadow-2xl border border-white/40 dark:border-gray-800/50 bg-white/85 dark:bg-gray-950/85 backdrop-blur-2xl text-gray-900 dark:text-white"
+    >
       {/* ===== 左侧：颜色选择网格 ===== */}
       <div className="w-72 shrink-0 border-r border-gray-200 dark:border-gray-800 flex flex-col">
         <div className="p-4 border-b border-gray-200 dark:border-gray-800">
@@ -189,6 +195,6 @@ export default function FiveColorQueryPanel() {
           </div>
         )}
       </div>
-    </div>
+    </motion.div>
   );
 }
diff --git a/frontend/src/components/LutManagerPanel.tsx b/frontend/src/components/LutManagerPanel.tsx
--- a/frontend/src/components/LutManagerPanel.tsx
+++ b/frontend/src/components/LutManagerPanel.tsx
@@ -4,6 +4,7 @@ import { useI18n } from "../i18n/context";
 import Dropdown from "./ui/Dropdown";
 import Slider from "./ui/Slider";
 import Button from "./ui/Button";
+import { motion } from "framer-motion";
 
 export default function LutManagerPanel() {
   const { t } = useI18n();
@@ -59,9 +60,12 @@ export default function LutManagerPanel() {
   };
 
   return (
-    <aside
+    <motion.aside
+      initial={{ opacity: 0, y: 30 }}
+      animate={{ opacity: 1, y: 0 }}
+      transition={{ type: "spring", damping: 25, stiffness: 300 }}
       data-testid="lut-manager-panel"
-      className="w-full max-w-2xl mx-auto h-full overflow-y-auto bg-white dark:bg-gray-800 p-6 flex flex-col gap-4"
+      className="w-full max-w-2xl mx-auto h-full overflow-y-auto bg-white/85 dark:bg-gray-900/85 backdrop-blur-2xl border border-white/40 dark:border-gray-700/50 shadow-2xl rounded-2xl p-6 flex flex-col gap-4"
     >
       <div>
         <h2 className="text-lg font-semibold text-gray-800 dark:text-gray-100">{t("lut_manager_title")}</h2>
@@ -186,6 +190,6 @@ export default function LutManagerPanel() {
           </button>
         </div>
       )}
-    </aside>
+    </motion.aside>
   );
 }
diff --git a/frontend/src/components/SettingsPanel.tsx b/frontend/src/components/SettingsPanel.tsx
--- a/frontend/src/components/SettingsPanel.tsx
+++ b/frontend/src/components/SettingsPanel.tsx
@@ -3,6 +3,7 @@
  * 系统设置面板，以全屏弹窗形式展示，包含缓存清理功能。
  */
 
+import { motion } from "framer-motion";
 import { useState } from "react";
 import { useI18n } from "../i18n/context";
 import { clearCache } from "../api/system";
@@ -35,9 +36,12 @@ export default function SettingsPanel() {
   };
 
   return (
-    <aside
+    <motion.aside
+      initial={{ opacity: 0, y: 30 }}
+      animate={{ opacity: 1, y: 0 }}
+      transition={{ type: "spring", damping: 25, stiffness: 300 }}
       data-testid="settings-panel"
-      className="w-full max-w-2xl mx-auto h-full overflow-y-auto bg-white dark:bg-gray-800 p-6 flex flex-col gap-6"
+      className="w-full max-w-2xl mx-auto h-full overflow-y-auto bg-white/85 dark:bg-gray-900/85 backdrop-blur-2xl border border-white/40 dark:border-gray-700/50 shadow-2xl rounded-2xl p-6 flex flex-col gap-6"
     >
       <h3 className="text-base font-semibold text-gray-900 dark:text-gray-100">
         {t("settings.title")}
@@ -65,6 +69,6 @@ export default function SettingsPanel() {
           )}
         </div>
       </section>
-    </aside>
+    </motion.aside>
   );
 }
diff --git a/frontend/src/components/ui/Accordion.tsx b/frontend/src/components/ui/Accordion.tsx
--- a/frontend/src/components/ui/Accordion.tsx
+++ b/frontend/src/components/ui/Accordion.tsx
@@ -1,4 +1,5 @@
 import { useState, type ReactNode } from "react";
+import { motion, AnimatePresence } from "framer-motion";
 
 interface AccordionProps {
   title: string;
@@ -18,11 +19,13 @@ export default function Accordion({
       <button
         type="button"
         onClick={() => setOpen((prev) => !prev)}
-        className="flex w-full items-center justify-between py-2 text-sm text-gray-300 hover:text-gray-100 transition-colors"
+        className="flex w-full items-center justify-between py-3 text-sm font-medium text-gray-300 hover:text-gray-100 transition-colors"
       >
         <span>{title}</span>
-        <svg
-          className={`h-4 w-4 shrink-0 text-gray-400 transition-transform duration-200 ${open ? "rotate-90" : ""}`}
+        <motion.svg
+          animate={{ rotate: open ? 90 : 0 }}
+          transition={{ type: "spring", stiffness: 300, damping: 20 }}
+          className="h-4 w-4 shrink-0 text-gray-400"
           viewBox="0 0 24 24"
           fill="none"
           stroke="currentColor"
@@ -31,9 +34,21 @@ export default function Accordion({
           strokeLinejoin="round"
         >
           <polyline points="9 18 15 12 9 6" />
-        </svg>
+        </motion.svg>
       </button>
-      {open && <div className="pb-3">{children}</div>}
+      <AnimatePresence initial={false}>
+        {open && (
+          <motion.div
+            initial={{ height: 0, opacity: 0 }}
+            animate={{ height: "auto", opacity: 1 }}
+            exit={{ height: 0, opacity: 0 }}
+            transition={{ type: "spring", bounce: 0, duration: 0.4 }}
+            className="overflow-hidden"
+          >
+            <div className="pb-3">{children}</div>
+          </motion.div>
+        )}
+      </AnimatePresence>
     </div>
   );
 }
diff --git a/frontend/src/components/ui/Button.tsx b/frontend/src/components/ui/Button.tsx
--- a/frontend/src/components/ui/Button.tsx
+++ b/frontend/src/components/ui/Button.tsx
@@ -1,3 +1,5 @@
+import { motion } from "framer-motion";
+
 interface ButtonProps {
   label: string;
   onClick: () => void;
@@ -21,11 +23,14 @@ export default function Button({
       : "bg-gray-200 dark:bg-gray-600 hover:bg-gray-300 dark:hover:bg-gray-700 text-gray-700 dark:text-gray-200";
 
   return (
-    <button
+    <motion.button
+      whileHover={isDisabled ? {} : { scale: 1.02 }}
+      whileTap={isDisabled ? {} : { scale: 0.95 }}
+      transition={{ type: "spring", stiffness: 400, damping: 25 }}
       type="button"
       onClick={onClick}
       disabled={isDisabled}
-      className={`flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-medium transition-colors ${variantClasses} disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-none`}
+      className={`relative flex flex-shrink-0 items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-medium transition-colors ${variantClasses} disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-none`}
     >
       {loading && (
         <div className="relative flex h-4 w-4 items-center justify-center">
@@ -35,6 +40,6 @@ export default function Button({
         </div>
       )}
       {label}
-    </button>
+    </motion.button>
   );
 }
diff --git a/frontend/src/components/ui/Checkbox.tsx b/frontend/src/components/ui/Checkbox.tsx
--- a/frontend/src/components/ui/Checkbox.tsx
+++ b/frontend/src/components/ui/Checkbox.tsx
@@ -20,7 +20,7 @@ export default function Checkbox({
         checked={checked}
         disabled={disabled}
         onChange={(e) => onChange(e.target.checked)}
-        className="h-4 w-4 rounded border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-blue-500 accent-blue-500 disabled:cursor-not-allowed"
+        className="h-4 w-4 rounded border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-blue-500 accent-blue-500 transition-all duration-200 hover:scale-110 focus:ring-2 focus:ring-blue-500/40 outline-none disabled:cursor-not-allowed"
       />
       <span className="text-gray-700 dark:text-gray-300">{label}</span>
     </label>
diff --git a/frontend/src/components/ui/Dropdown.tsx b/frontend/src/components/ui/Dropdown.tsx
--- a/frontend/src/components/ui/Dropdown.tsx
+++ b/frontend/src/components/ui/Dropdown.tsx
@@ -22,7 +22,7 @@ export default function Dropdown({
         value={value}
         disabled={disabled}
         onChange={(e) => onChange(e.target.value)}
-        className="w-full rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-1.5 text-sm text-gray-800 dark:text-gray-200 outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500 disabled:opacity-40 disabled:cursor-not-allowed"
+        className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white/90 dark:bg-gray-800/90 px-3 py-1.5 text-sm text-gray-800 dark:text-gray-200 outline-none transition-all duration-200 hover:shadow-sm hover:border-gray-400 dark:hover:border-gray-500 focus:border-blue-500 focus:ring-2 focus:ring-blue-500/40 disabled:opacity-40 disabled:cursor-not-allowed"
       >
         {placeholder && (
           <option value="" disabled>
diff --git a/frontend/src/components/ui/FullScreenModal.tsx b/frontend/src/components/ui/FullScreenModal.tsx
--- a/frontend/src/components/ui/FullScreenModal.tsx
+++ b/frontend/src/components/ui/FullScreenModal.tsx
@@ -5,6 +5,7 @@
 
 import { useEffect, useRef, useCallback } from "react";
 import { createPortal } from "react-dom";
+import { motion, AnimatePresence } from "framer-motion";
 import type { ReactNode } from "react";
 
 interface FullScreenModalProps {
@@ -36,38 +37,51 @@ export default function FullScreenModal({ open, title, onClose, children }: Full
     };
   }, [open, handleKeyDown]);
 
-  if (!open) return null;
-
   return createPortal(
-    <div
-      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/60"
-      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
-    >
-      <div
-        ref={modalRef}
-        tabIndex={-1}
-        role="dialog"
-        aria-modal="true"
-        aria-label={title}
-        className="relative w-[95vw] h-[90vh] bg-white dark:bg-gray-900 rounded-xl shadow-2xl flex flex-col overflow-hidden outline-none"
-      >
-        {/* Header */}
-        <div className="flex items-center justify-between px-6 py-3 border-b border-gray-200 dark:border-gray-700 shrink-0">
-          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">{title}</h2>
-          <button
+    <AnimatePresence>
+      {open && (
+        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 sm:p-0">
+          {/* Backdrop */}
+          <motion.div
+            initial={{ opacity: 0 }}
+            animate={{ opacity: 1 }}
+            exit={{ opacity: 0 }}
+            className="absolute inset-0 bg-black/40 backdrop-blur-sm"
             onClick={onClose}
-            className="w-8 h-8 flex items-center justify-center rounded-md text-gray-500 hover:text-gray-900 hover:bg-gray-100 dark:text-gray-400 dark:hover:text-white dark:hover:bg-gray-700 transition-colors"
-            aria-label="关闭"
+          />
+          
+          {/* Modal Container */}
+          <motion.div
+            ref={modalRef}
+            tabIndex={-1}
+            role="dialog"
+            aria-modal="true"
+            aria-label={title}
+            initial={{ opacity: 0, scale: 0.9, y: 20 }}
+            animate={{ opacity: 1, scale: 1, y: 0 }}
+            exit={{ opacity: 0, scale: 0.9, y: 20 }}
+            transition={{ type: "spring", damping: 25, stiffness: 350 }}
+            className="relative w-full max-w-[95vw] h-[90vh] bg-white/95 dark:bg-gray-950/95 backdrop-blur-2xl rounded-2xl shadow-[0_32px_64px_-16px_rgba(0,0,0,0.3)] flex flex-col overflow-hidden outline-none border border-white/20 dark:border-white/5"
           >
-            ✕
-          </button>
-        </div>
-        {/* Body */}
-        <div className="flex-1 overflow-y-auto">
-          {children}
+            {/* Header */}
+            <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200/50 dark:border-gray-800/50 shrink-0">
+              <h2 className="text-xl font-bold tracking-tight text-gray-900 dark:text-white">{title}</h2>
+              <button
+                onClick={onClose}
+                className="w-10 h-10 flex items-center justify-center rounded-xl text-gray-400 hover:text-gray-900 hover:bg-gray-100 dark:text-gray-500 dark:hover:text-white dark:hover:bg-gray-800/50 transition-all duration-200 active:scale-90"
+                aria-label="关闭"
+              >
+                ✕
+              </button>
+            </div>
+            {/* Body */}
+            <div className="flex-1 overflow-hidden relative">
+              {children}
+            </div>
+          </motion.div>
         </div>
-      </div>
-    </div>,
+      )}
+    </AnimatePresence>,
     document.body
   );
 }
diff --git a/frontend/src/components/ui/Slider.tsx b/frontend/src/components/ui/Slider.tsx
--- a/frontend/src/components/ui/Slider.tsx
+++ b/frontend/src/components/ui/Slider.tsx
@@ -91,7 +91,7 @@ export default function Slider({
           value={value}
           disabled={disabled}
           onChange={(e) => onChange(Number(e.target.value))}
-          className="flex-1 h-1.5 rounded-full appearance-none cursor-pointer bg-gray-300 dark:bg-gray-700 accent-blue-500 disabled:opacity-40 disabled:cursor-not-allowed"
+          className="flex-1 h-1.5 rounded-full appearance-none cursor-pointer bg-gray-300 dark:bg-gray-700 accent-blue-500 transition-all duration-200 hover:accent-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-500/40 disabled:opacity-40 disabled:cursor-not-allowed"
         />
         <div className="flex items-center gap-0.5 shrink-0">
           <input
diff --git a/frontend/src/i18n/translations.ts b/frontend/src/i18n/translations.ts
--- a/frontend/src/i18n/translations.ts
+++ b/frontend/src/i18n/translations.ts
@@ -1471,6 +1471,10 @@ export const translations: Record<string, Record<"zh" | "en", string>> = {
     zh: "点击右侧 LUT 预览图中的色块可手动修正颜色",
     en: "Click a cell in the LUT preview to manually fix its color",
   },
+  ext_material_type_label: {
+    zh: "耗材类型",
+    en: "Material Type",
+  },
   ext_palette_title: {
     zh: "调色板确认",
     en: "Palette Confirmation",
diff --git a/frontend/src/index.css b/frontend/src/index.css
--- a/frontend/src/index.css
+++ b/frontend/src/index.css
@@ -1,5 +1,11 @@
 @import "tailwindcss";
 
+@theme {
+  --shadow-glow-yellow: 0 0 12px rgba(250, 204, 21, 0.6);
+  --shadow-glow-blue: 0 0 6px rgba(59, 130, 246, 0.6);
+  --shadow-glass-panel: 0 -8px 30px rgba(0, 0, 0, 0.12);
+}
+
 @custom-variant dark (&:where(.dark, .dark *));
 
 body {
diff --git a/lut-npy预设/Custom/lumina_lut.json b/lut-npy预设/Custom/lumina_lut.json
new file mode 100644
--- /dev/null
+++ b/lut-npy预设/Custom/lumina_lut.json

diff --git a/utils/lut_manager.py b/utils/lut_manager.py
--- a/utils/lut_manager.py
+++ b/utils/lut_manager.py
@@ -112,14 +112,62 @@ def get_lut_choices(cls):
         return list(lut_files.keys())
 
     # JSON LUT 颜色数量 → 模式映射（与 lut_merger._SIZE_TO_MODE 对齐）
+    # 1024 和 1296 已移除：多个变体共享相同数量（CMYW/RYBW 均为 1024，
+    # 6-Color CMYW/RYBW 均为 1296），通过 _detect_variant_from_palette 处理
     _JSON_SIZE_TO_MODE: dict[int, str] = {
         32: "BW (Black & White)",
-        1024: "4-Color (CMYW)",
-        1296: "6-Color (Smart 1296)",
         2468: "5-Color Extended",
         2738: "8-Color Max",
     }
 
+    @staticmethod
+    def _detect_variant_from_palette(data: dict, base_mode: str) -> str:
+        """Detect RYBW/CMYW variant from palette color names.
+        从 palette 颜色名称推断 RYBW/CMYW 变体。
+
+        For ambiguous entry counts (1024 for 4-Color, 1296 for 6-Color),
+        inspect palette keys/color fields to distinguish RYBW from CMYW.
+        对于有歧义的 entries 数量（4-Color 的 1024、6-Color 的 1296），
+        通过检查 palette 的键名或 color 字段区分 RYBW 和 CMYW 变体。
+
+        Args:
+            data (dict): Parsed JSON data containing a "palette" field.
+                         (包含 "palette" 字段的已解析 JSON 数据)
+            base_mode (str): Base color mode without variant, e.g. "4-Color" or "6-Color".
+                             (不含变体的基础颜色模式，如 "4-Color" 或 "6-Color")
+
+        Returns:
+            str: Full color mode string with variant, e.g. "4-Color (RYBW)".
+                 (含变体的完整颜色模式字符串)
+        """
+        palette_raw = data.get("palette", {})
+        color_names: set[str] = set()
+        if isinstance(palette_raw, dict):
+            color_names = {k.lower() for k in palette_raw.keys()}
+        elif isinstance(palette_raw, list):
+            color_names = {
+                item.get("color", "").lower()
+                for item in palette_raw
+                if isinstance(item, dict)
+            }
+
+        rybw_indicators = {"red", "blue"}
+        cmyw_indicators = {"cyan", "magenta"}
+
+        if base_mode == "4-Color":
+            if rybw_indicators & color_names:
+                return "4-Color (RYBW)"
+            if cmyw_indicators & color_names:
+                return "4-Color (CMYW)"
+            return "4-Color (CMYW)"  # default fallback
+
+        if base_mode == "6-Color":
+            if rybw_indicators & color_names:
+                return "6-Color (RYBW 1296)"
+            return "6-Color (Smart 1296)"  # default fallback
+
+        return f"{base_mode}"
+
     @staticmethod
     def infer_color_mode(display_name: str, file_path: str) -> str:
         """Infer color mode from LUT display name or file path.
@@ -151,7 +199,11 @@ def infer_color_mode(display_name: str, file_path: str) -> str:
 
     @staticmethod
     def _infer_color_mode_from_json(file_path: str) -> str:
-        """从 JSON 文件内容推断颜色模式（轻量读取，不做 numpy 运算）。
+        """Infer color mode from JSON file content (lightweight read, no numpy).
+        从 JSON 文件内容推断颜色模式（轻量读取，不做 numpy 运算）。
+
+        Priority: stored color_mode > palette-based variant detection > size mapping.
+        优先级：存储的 color_mode > 基于 palette 的变体检测 > 数量映射。
 
         支持两种 JSON 格式：
         - flat-list: 顶层为数组，len(data) 即 entries 数量
@@ -168,12 +220,22 @@ def _infer_color_mode_from_json(file_path: str) -> str:
         if isinstance(data, list):
             count = len(data)
         elif isinstance(data, dict):
+            # 优先使用存储的 color_mode
+            stored_mode = data.get("color_mode")
+            if stored_mode and isinstance(stored_mode, str):
+                return stored_mode
             entries = data.get("entries", [])
             count = len(entries)
         else:
             count = 0
 
-        # 精确匹配标准尺寸
+        # 对于有歧义的数量，通过 palette 名称区分变体
+        if count == 1024 and isinstance(data, dict):
+            return LUTManager._detect_variant_from_palette(data, "4-Color")
+        if count == 1296 and isinstance(data, dict):
+            return LUTManager._detect_variant_from_palette(data, "6-Color")
+
+        # 无歧义的数量直接映射
         mode = LUTManager._JSON_SIZE_TO_MODE.get(count)
         if mode:
             return mode
@@ -352,19 +414,22 @@ def delete_lut(cls, display_name):
 
     @classmethod
     def infer_default_metadata(cls, display_name: str, file_path: str,
-                               color_count: int) -> LUTMetadata:
+                               color_count: int,
+                               color_mode: str | None = None) -> LUTMetadata:
         """Infer default LUTMetadata from filename and color count.
         根据文件名和颜色数量推断默认元数据。
 
         Args:
             display_name (str): LUT display name. (LUT 显示名称)
             file_path (str): LUT file path. (LUT 文件路径)
             color_count (int): Number of colors in the LUT. (LUT 中的颜色数量)
+            color_mode (str | None): Optional color mode override; when provided,
+                takes priority over inference. (可选颜色模式覆盖；传入时优先使用)
 
         Returns:
             LUTMetadata: Inferred default metadata. (推断的默认元数据)
         """
-        mode = cls.infer_color_mode(display_name, file_path)
+        mode = color_mode or cls.infer_color_mode(display_name, file_path)
         color_conf = ColorSystem.get(mode)
         slots = color_conf.get("slots", [])
 
@@ -375,6 +440,7 @@ def infer_default_metadata(cls, display_name: str, file_path: str,
 
         return LUTMetadata(
             palette=palette,
+            color_mode=mode,
             max_color_layers=PrinterConfig.COLOR_LAYERS,
             layer_height_mm=PrinterConfig.LAYER_HEIGHT,
             line_width_mm=PrinterConfig.NOZZLE_WIDTH,
@@ -473,6 +539,7 @@ def _load_keyed_json(cls, file_path: str, display_name: str) -> tuple[np.ndarray
         # Build metadata
         metadata = LUTMetadata(
             palette=palette,
+            color_mode=data.get("color_mode"),
             max_color_layers=int(data.get("max_color_layers", PrinterConfig.COLOR_LAYERS)),
             layer_height_mm=float(data.get("layer_height_mm", PrinterConfig.LAYER_HEIGHT)),
             line_width_mm=float(data.get("line_width_mm", PrinterConfig.NOZZLE_WIDTH)),
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
