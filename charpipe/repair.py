"""隐藏区域与接缝修复：缺口检测 + 人工补绘。

- 缺口检测区分"原图真实像素"与"需要补绘的像素"。
- 未分配到任何部件的像素 -> unassigned（分解缺口）。
- 部件内部被透明包围的空洞 -> interior hole（疑似缺失）。
- 人工补绘通过 manual_repair.json 提供（带显式颜色或自动取最近原图颜色），
  补绘像素会被标记为 synthetic（非原图），绝不冒充原始像素。
"""
from __future__ import annotations

import json

import numpy as np

from . import util
from .segmentation import masks_union


def detect_gaps(opaque: np.ndarray, masks: dict[str, np.ndarray]) -> dict:
    """检测分解缺口与部件内部空洞。"""
    h, w = opaque.shape
    union = masks_union(masks)
    unassigned = opaque & ~union

    holes: dict[str, int] = {}
    hole_masks: dict[str, np.ndarray] = {}
    for name, m in masks.items():
        if m.sum() == 0:
            holes[name] = 0
            hole_masks[name] = np.zeros((h, w), bool)
            continue
        # 部件包围盒内的"透明"像素，若被部件完全包围则是内部空洞
        x0, y0, x1, y1 = util.bbox_of(m)
        sub = np.zeros((h, w), bool)
        sub[y0:y1 + 1, x0:x1 + 1] = True
        inside_bbox = sub & ~m
        # 用连通域区分"bbox 内外部背景"与"被包围的空洞"：
        # 空洞 = 与 bbox 边界不连通的透明连通域
        n, labels, _ = util.connected_components(inside_bbox)
        border_labels = set()
        if n > 0:
            # bbox 边界上的标签视为外部
            border = np.zeros_like(inside_bbox)
            border[y0, x0:x1 + 1] = True
            border[y1, x0:x1 + 1] = True
            border[y0:y1 + 1, x0] = True
            border[y0:y1 + 1, x1] = True
            border_labels = set(np.unique(labels[border & inside_bbox])) - {0}
        hole = np.zeros((h, w), bool)
        if n > 0:
            for lab in range(1, n):
                if lab not in border_labels:
                    hole |= (labels == lab)
        hole_masks[name] = hole
        holes[name] = int(hole.sum())

    return {
        "unassigned": unassigned,
        "unassigned_count": int(unassigned.sum()),
        "hole_masks": hole_masks,
        "hole_counts": holes,
    }


# ---------------------------------------------------------------------------
# 人工补绘
# ---------------------------------------------------------------------------
def nearest_opaque_color(rgba: np.ndarray, x: int, y: int, max_r: int = 256):
    """在原图中找离 (x,y) 最近的不透明像素颜色（环状搜索）。"""
    h, w = rgba.shape[:2]
    a = rgba[..., 3]
    for r in range(0, max_r + 1):
        for dy in range(-r, r + 1):
            for dx in (-r, r) if dy not in (-r, r) else range(-r, r + 1):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and a[ny, nx] > 0:
                    return tuple(int(v) for v in rgba[ny, nx])
    return (255, 0, 255, 255)  # 兜底：品红，醒目提示未取到颜色


def load_manual_repair(path) -> dict:
    if not path:
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def apply_repair(part_rgba: np.ndarray, items: list, source_rgba: np.ndarray,
                 part_mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """把人工补绘应用到部件。返回 (新部件RGBA, synthetic遮罩)。

    items: [{"x":..,"y":..,"r":..,"color":[r,g,b,a]?}, ...]
    无 color 时自动取最近原图不透明颜色。
    """
    out = np.asarray(part_rgba).copy()
    synthetic = np.zeros(part_rgba.shape[:2], bool)
    h, w = part_rgba.shape[:2]
    for it in items:
        x, y, r = int(it["x"]), int(it["y"]), int(it["r"])
        color = it.get("color")
        if color is None:
            color = nearest_opaque_color(source_rgba, x, y)
        color = tuple(int(v) for v in color)
        mask = util.circles_to_mask([(x, y, r)], (h, w))
        # 只补到部件遮罩范围内（或允许扩到遮罩边缘？默认严格限制在遮罩内，
        # 避免污染其它部件；如需扩边，用户应同步修改 mask）
        mask &= np.asarray(part_mask) > 0
        out[mask] = color
        synthetic |= mask
    return out, synthetic
