"""原图分析：尺寸、RGBA 透明通道、角色边界、颜色、背景检测。

背景处理原则：
- 优先保留 RGBA 透明通道。
- 绝不未经确认就把黑色背景视为透明。
- 若图片有不透明背景，先输出诊断结果，只有在显式授权时才执行去背景。
- 无法可靠区分角色与背景时，暂停自动去背景并要求用户确认。
"""
from __future__ import annotations

import numpy as np

from . import util


def analyze(path: str, rgba: np.ndarray) -> dict:
    """分析原图，返回 character 元信息 dict（将写入 character.json）。"""
    h, w, _ = rgba.shape
    alpha = rgba[..., 3]
    opaque = util.alpha_mask(rgba)
    solid = (alpha == 255)

    ys, xs = np.nonzero(opaque)
    bbox = None
    if xs.size:
        bbox = {"x": int(xs.min()), "y": int(ys.min()),
                "width": int(xs.max() - xs.min() + 1),
                "height": int(ys.max() - ys.min() + 1)}

    # 背景检测
    bg = detect_background(rgba)

    return {
        "source": {"path": path, "filename": path.rsplit("\\", 1)[-1].rsplit("/", 1)[-1]},
        "image": {
            "width": w, "height": h, "mode": "RGBA",
            "has_alpha": True,
            "aspect_ratio": round(w / h, 6),
        },
        "character_bbox": bbox,
        "opaque": {
            "pixel_count": int(opaque.sum()),
            "opaque_ratio": round(float(opaque.mean()), 6),
            "fully_opaque_count": int(solid.sum()),
        },
        "alpha": {
            "has_transparent": bool((alpha == 0).any()),
            "has_partial": bool(((alpha > 0) & (alpha < 255)).any()),
            "partial_pixel_count": int(((alpha > 0) & (alpha < 255)).sum()),
        },
        "background": bg,
        "colors": {"dominant": util.dominant_colors(rgba)},
    }


def detect_background(rgba: np.ndarray) -> dict:
    """检测背景特征，返回诊断结果。绝不擅自删除背景。"""
    alpha = rgba[..., 3]
    h, w = alpha.shape

    # 1) 已有透明通道，且透明区域连通到图片边框 -> 已抠图
    transparent = alpha == 0
    border_transparent = bool(
        transparent[0, :].any() or transparent[-1, :].any()
        or transparent[:, 0].any() or transparent[:, -1].any()
    )
    if transparent.any() and border_transparent:
        # 进一步确认透明区域是否“包裹”角色（而非角色内部挖洞）
        return {
            "detected": "transparent",
            "method": "alpha_channel",
            "note": "图片已含透明背景，透明区域连通到边框，按 alpha 通道处理。",
            "needs_removal": False,
            "safe": True,
        }

    # 2) 无透明背景：分析边框颜色特征
    # 取四个边框的像素
    borders = np.concatenate([
        rgba[0, :, :3], rgba[-1, :, :3],
        rgba[:, 0, :3], rgba[:, -1, :3],
    ])
    # 若存在部分透明，先剔除透明像素
    borders_alpha = np.concatenate([
        alpha[0, :], alpha[-1, :], alpha[:, 0], alpha[:, -1],
    ])
    solid_borders = borders[borders_alpha > 0]
    if solid_borders.size == 0:
        return {"detected": "transparent", "method": "alpha_channel",
                "note": "边框全透明。", "needs_removal": False, "safe": True}

    mean_border = solid_borders.mean(axis=0)
    std_border = solid_borders.std(axis=0)
    uniform = float(std_border.max()) < 12.0
    dark = bool(mean_border.max() < 40)

    if uniform:
        kind = "solid"
        decision = {
            "detected": "opaque_background",
            "method": "border_sampling",
            "border_color": [int(v) for v in mean_border.round()],
            "uniform": True,
            "dark": dark,
            "needs_removal": True,
            "safe": not dark,  # 深色背景与头发/眼镜/裤子易混淆，不自动处理
            "note": (
                "检测到不透明纯色背景，且颜色较暗，可能与角色深色轮廓混淆。"
                "为避免误删头发/眼镜/裤子，自动去背景已暂停，请人工确认。"
                if dark else
                "检测到不透明纯色背景，可安全执行背景分割。"
            ),
        }
        return decision

    return {
        "detected": "opaque_background",
        "method": "border_sampling",
        "border_color": [int(v) for v in mean_border.round()],
        "uniform": False,
        "dark": dark,
        "needs_removal": True,
        "safe": False,
        "note": "背景颜色不统一，无法可靠区分角色与背景，已暂停自动去背景。",
    }


def remove_background(rgba: np.ndarray, bg_color=None, tolerance: int = 16) -> np.ndarray:
    """仅在用户显式授权后调用：把接近 bg_color 的像素设为透明。

    返回新的 RGBA 数组；不修改传入数组。
    """
    out = np.asarray(rgba).copy()
    if bg_color is None:
        # 默认取边框主色
        alpha = out[..., 3]
        borders = np.concatenate([
            out[0, :, :3], out[-1, :, :3], out[:, 0, :3], out[:, -1, :3]])
        borders_alpha = np.concatenate([alpha[0, :], alpha[-1, :], alpha[:, 0], alpha[:, -1]])
        bg_color = borders[borders_alpha > 0].mean(axis=0)
    bg = np.asarray(bg_color, dtype=float)
    diff = np.abs(out[..., :3].astype(float) - bg).max(axis=2)
    out[diff <= tolerance, 3] = 0
    return out
