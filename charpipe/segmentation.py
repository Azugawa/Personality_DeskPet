"""部件分割：自动分割 + 人工遮罩合并。

自动分割基于地标（几何），生成 12 个部件遮罩，全部默认标记 NEEDS_REVIEW。
人工修正通过 segmentation.json 中的 polygon / strokes / method / confirmed 字段合并。

遮罩语义：部件遮罩是"从原图选取哪些像素"的集合，部件之间允许在关节处重叠。
"""
from __future__ import annotations

import numpy as np

from . import PARTS, util


def default_part_cfg() -> dict:
    return {"method": "auto", "confirmed": False,
            "polygon": [], "strokes": {"add": [], "erase": []}}


def default_segmentation(lm: dict) -> dict:
    """生成默认 segmentation 配置结构（自动 + 全部待确认）。"""
    return {
        "version": 1,
        "symmetry_x": lm.get("symmetry_x"),
        "landmarks": {k: v for k, v in lm.items()},
        "parts": {p: default_part_cfg() for p in PARTS},
    }


def build_auto_masks(opaque: np.ndarray, lm: dict) -> dict[str, np.ndarray]:
    """由地标生成自动分割遮罩（全画布坐标，布尔）。

    头部模式：
      "split"        —— head[顶,分界], torso+arms[分界,腰], legs[腰,底]
      "merge_upper"  —— head[顶,腰]，torso/arms 并入 head，legs[腰,底]
      "big_head"     —— 大头角色：head[顶,腰], torso+arms[腰,膝], legs[膝,底]
    """
    h, w = opaque.shape
    yy, xx = np.mgrid[0:h, 0:w]
    neck = lm["neck_y"]
    waist = lm["waist_y"]
    knee = lm["knee_y"]
    bottom = lm["bottom_y"]
    sym = lm["symmetry_x"]
    armpit = lm["armpit_offset"]
    split = int(round(sym))

    masks: dict[str, np.ndarray] = {}
    head_mode = lm.get("head_mode", "split")

    # ---- 1) head ----
    if head_mode in ("merge_upper", "big_head"):
        head_bottom = waist
    else:
        head_bottom = int(lm.get("head_bottom_y", neck))
    masks["head"] = opaque & (yy <= head_bottom)

    # ---- 2) torso + arms 的纵向区间 ----
    if head_mode == "big_head":
        body_top, body_bot = waist, knee          # 躯干+手臂在腰与膝之间
    elif head_mode == "split":
        body_top, body_bot = head_bottom, waist
    else:  # merge_upper：无独立躯干/手臂
        body_top, body_bot = None, None

    if body_top is None:
        for p in ("torso", "upper_arm_L", "forearm_L", "hand_L",
                  "upper_arm_R", "forearm_R", "hand_R"):
            masks[p] = np.zeros_like(opaque, dtype=bool)
    else:
        band = opaque & (yy >= body_top) & (yy <= body_bot)
        arm_len = max(1, body_bot - body_top)
        elbow_y = body_top + int(round(0.45 * arm_len))
        wrist_y = body_top + int(round(0.78 * arm_len))

        armpit_R = int(round(sym - armpit))
        armpit_L = int(round(sym + armpit))

        if head_mode == "big_head":
            # 大头：torso 只取中央，手臂独立在两侧（互不包含，torso 不含手臂）
            masks["torso"] = band & (xx >= armpit_R) & (xx <= armpit_L)
            arm_L = band & (xx >= armpit_L)
            arm_R = band & (xx <= armpit_R)
        else:
            # split：torso 全宽保留像素，手臂为两侧重叠条带
            masks["torso"] = band
            arm_L = band & (xx >= armpit_L)
            arm_R = band & (xx <= armpit_R)

        masks["upper_arm_L"] = arm_L & (yy <= elbow_y)
        masks["forearm_L"] = arm_L & (yy > elbow_y) & (yy <= wrist_y)
        masks["hand_L"] = arm_L & (yy > wrist_y)
        masks["upper_arm_R"] = arm_R & (yy <= elbow_y)
        masks["forearm_R"] = arm_R & (yy > elbow_y) & (yy <= wrist_y)
        masks["hand_R"] = arm_R & (yy > wrist_y)

    # ---- 3) 腿 ----
    if head_mode == "big_head":
        leg_top = knee
        leg_mid = leg_top + int(round(0.5 * (bottom - leg_top)))
        thigh_band = opaque & (yy >= leg_top) & (yy <= leg_mid)
        shin_band = opaque & (yy > leg_mid) & (yy <= bottom)
    else:
        thigh_band = opaque & (yy >= waist) & (yy <= knee)
        shin_band = opaque & (yy > knee) & (yy <= bottom)

    masks["thigh_L"] = thigh_band & (xx >= split)
    masks["thigh_R"] = thigh_band & (xx < split)
    masks["shin_L"] = shin_band & (xx >= split)
    masks["shin_R"] = shin_band & (xx < split)

    return masks


def apply_manual(mask: np.ndarray, cfg: dict, shape) -> np.ndarray:
    """把人工修正合并进遮罩。

    base = 自动结果(method=auto) / 多边形(method=polygon) / 空(method=manual)。
    add 笔刷并入，erase 笔刷移除。
    """
    h, w = int(shape[0]), int(shape[1])
    method = cfg.get("method", "auto")
    polygon = cfg.get("polygon") or []

    if method == "polygon":
        base = util.polygon_to_mask(polygon, (h, w))
    elif method == "manual":
        base = np.zeros((h, w), bool)
    else:  # auto
        base = np.asarray(mask) > 0

    strokes = cfg.get("strokes") or {}
    base = base | util.circles_to_mask(strokes.get("add", []), (h, w))
    base = base & ~util.circles_to_mask(strokes.get("erase", []), (h, w))
    return base


def build_masks(opaque: np.ndarray, lm: dict, seg_cfg: dict | None) -> dict[str, np.ndarray]:
    """构建全部部件遮罩 = 自动 + 人工合并。seg_cfg 为 None 时用自动。"""
    auto = build_auto_masks(opaque, lm)
    h, w = opaque.shape
    if not seg_cfg:
        return auto
    parts_cfg = seg_cfg.get("parts", {})
    out = {}
    for p in PARTS:
        cfg = parts_cfg.get(p) or default_part_cfg()
        out[p] = apply_manual(auto.get(p), cfg, (h, w))
    return out


def masks_union(masks: dict[str, np.ndarray]) -> np.ndarray:
    u = None
    for m in masks.values():
        u = m.copy() if u is None else (u | m)
    return u if u is not None else np.zeros((1, 1), bool)
