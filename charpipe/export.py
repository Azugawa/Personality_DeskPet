"""资产导出：部件 PNG、裁剪件、遮罩、源图副本、配置文件（character/joints/layers/segmentation）。

所有部件 PNG 使用原始画布尺寸并记录 bbox/offset，同时输出裁剪件供动画引擎
按需加载；坐标全部以原图左上角为原点。
"""
from __future__ import annotations

import json
import os
import shutil

import numpy as np

from . import LAYER_Z, PART_JOINT, PARTS, util


def prepare_parts(rgba: np.ndarray, masks: dict[str, np.ndarray],
                  manual_repair: dict) -> tuple[dict[str, np.ndarray], dict[str, np.ndarray]]:
    """生成部件 RGBA 与 synthetic 标记。manual_repair: {part: [items]}。"""
    parts = {}
    synthetic = {}
    for p in PARTS:
        m = masks[p]
        part = util.extract_part(rgba, m)
        items = (manual_repair or {}).get(p, [])
        if items:
            from .repair import apply_repair
            part, syn = apply_repair(part, items, rgba, m)
            synthetic[p] = syn
        else:
            synthetic[p] = np.zeros(rgba.shape[:2], bool)
        parts[p] = part
    return parts, synthetic


def build_parts_info(masks: dict[str, np.ndarray], parts: dict[str, np.ndarray],
                     seg_cfg: dict, head_mode: str = "split") -> dict[str, dict]:
    """每个部件的基本信息：状态、bbox、offset、像素数、备注。"""
    parts_cfg = (seg_cfg or {}).get("parts", {})
    merged = {"torso", "upper_arm_L", "forearm_L", "hand_L",
              "upper_arm_R", "forearm_R", "hand_R"}
    info = {}
    for p in PARTS:
        m = masks[p]
        bbox = util.bbox_of(m)
        px = int(m.sum())
        cfg = parts_cfg.get(p, {})
        confirmed = bool(cfg.get("confirmed"))
        if px == 0:
            status = "EMPTY"
            if head_mode == "merge_upper" and p in merged:
                notes = ["已按大头角色结构并入 head，不单独输出"]
            else:
                notes = ["自动分割未能分离出该部件，需人工提供遮罩"]
        elif confirmed:
            status = "CONFIRMED"
            notes = ["人工已确认"]
        else:
            status = "NEEDS_REVIEW"
            notes = ["自动估计，未人工确认"]
        info[p] = {
            "status": status,
            "confirmed": confirmed,
            "bbox": list(bbox) if bbox else None,
            "offset": [bbox[0], bbox[1]] if bbox else [0, 0],
            "pixel_count": px,
            "notes": notes,
        }
    return info


def build_layers_cfg(canvas_shape, masks, parts_info, joints_cfg, synthetic) -> dict:
    h, w = canvas_shape
    jj = joints_cfg["joints"]
    pivots = joints_cfg["part_pivots"]
    part_list = []
    for p in PARTS:
        bbox = parts_info[p]["bbox"]
        pivot = pivots[p]
        part_list.append({
            "name": p,
            "z": LAYER_Z[p],
            "bbox": bbox,
            "offset": [bbox[0], bbox[1]] if bbox else [0, 0],
            "pivot": [pivot["x"], pivot["y"]],
            "anchor_joint": PART_JOINT[p],
            "synthetic_pixel_count": int(np.asarray(synthetic[p]).sum()),
            "status": parts_info[p]["status"],
        })
    return {
        "version": 1,
        "canvas": {"width": w, "height": h},
        "coordinate_system": "original_canvas_top_left_pixels",
        "lr_convention": "L=角色自身左侧（观察者右侧）；R=角色自身右侧（观察者左侧）",
        "parts": part_list,
    }


def _json_dump(obj, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def write_package(out_dir: str, *, source_path: str, rgba: np.ndarray,
                  character: dict, segmentation_cfg: dict, joints_cfg: dict,
                  layers_cfg: dict, masks: dict[str, np.ndarray],
                  parts: dict[str, np.ndarray], synthetic: dict[str, np.ndarray],
                  mode: str) -> list[str]:
    """写出资产包。mode: 'auto' 写入 parts_provisional/（全部部件）；
    'export' 写入 parts/ 与 parts_cropped/（仅已确认部件）。返回已导出部件名列表。"""
    src_dir = os.path.join(out_dir, "source")
    mask_dir = os.path.join(out_dir, "masks")
    cfg_dir = os.path.join(out_dir, "config")
    for d in (src_dir, mask_dir, cfg_dir):
        os.makedirs(d, exist_ok=True)

    # 源图副本（绝不覆盖原文件）
    dst = os.path.join(src_dir, "original.png")
    if not os.path.exists(dst):
        shutil.copy2(source_path, dst)

    name2info = {e["name"]: e for e in layers_cfg["parts"]}

    exported = []
    if mode == "auto":
        parts_dir = os.path.join(out_dir, "parts_provisional")
        os.makedirs(parts_dir, exist_ok=True)
        for p in PARTS:
            util.save_png(os.path.join(parts_dir, f"{p}.png"), parts[p])
            exported.append(p)
    else:  # export
        parts_dir = os.path.join(out_dir, "parts")
        crop_dir = os.path.join(out_dir, "parts_cropped")
        os.makedirs(parts_dir, exist_ok=True)
        os.makedirs(crop_dir, exist_ok=True)
        for p in PARTS:
            status = name2info[p]["status"]
            if status != "CONFIRMED":
                continue  # 未确认部件不输出正式素材
            util.save_png(os.path.join(parts_dir, f"{p}.png"), parts[p])
            cropped, _off = util.crop_with_offset(parts[p], masks[p])
            if cropped is not None:
                util.save_png(os.path.join(crop_dir, f"{p}.png"), cropped)
            exported.append(p)

    # 遮罩（始终写出，供人工校正）
    for p in PARTS:
        util.save_mask_png(os.path.join(mask_dir, f"{p}_mask.png"), masks[p])

    # 配置文件
    _json_dump(character, os.path.join(cfg_dir, "character.json"))
    _json_dump(joints_cfg, os.path.join(cfg_dir, "joints.json"))
    _json_dump(layers_cfg, os.path.join(cfg_dir, "layers.json"))
    _json_dump(segmentation_cfg, os.path.join(cfg_dir, "segmentation.json"))
    return exported
