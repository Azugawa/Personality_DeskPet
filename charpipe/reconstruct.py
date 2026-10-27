"""角色重组与像素差异检测。

按图层顺序把全部部件重新合成，并与原图逐像素对比：
- missing：原图有、重组无的像素（分解缺口）。
- extra：重组有、原图无的像素（多为人工补绘 synthetic）。
- value_diff：两者都有但 RGB 不同的像素（本流水线只复制原像素，应恒为 0）。
"""
from __future__ import annotations

import numpy as np

from . import LAYER_Z, PARTS


def composite(parts: dict[str, np.ndarray], canvas_shape) -> np.ndarray:
    """按 z 顺序合成部件（z 大者覆盖其上）。返回 RGBA。"""
    h, w = canvas_shape
    out = np.zeros((h, w, 4), np.uint8)
    ordered = sorted(PARTS, key=lambda p: LAYER_Z[p])
    for name in ordered:
        p = np.asarray(parts[name])
        m = p[..., 3] > 0
        out[m] = p[m]
    return out


def diff(original_rgba: np.ndarray, reconstructed_rgba: np.ndarray,
         opaque: np.ndarray) -> dict:
    o = np.asarray(original_rgba)
    r = np.asarray(reconstructed_rgba)
    o_op = o[..., 3] > 0
    r_op = r[..., 3] > 0

    missing = o_op & ~r_op
    extra = r_op & ~o_op
    both = o_op & r_op
    value_diff = both & (np.abs(o[..., :3].astype(int) - r[..., :3].astype(int)).max(axis=2) > 0)

    total = int(opaque.sum()) if opaque is not None else int(o_op.sum())
    return {
        "missing_pixels": int(missing.sum()),
        "extra_pixels": int(extra.sum()),
        "value_diff_pixels": int(value_diff.sum()),
        "coverage": round(1.0 - (int(missing.sum()) / total), 6) if total else 1.0,
        "missing_mask": missing,
        "extra_mask": extra,
        "value_diff_mask": value_diff,
    }
