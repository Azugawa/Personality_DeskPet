"""预览图生成：分割预览、骨骼预览、重组人物、差异图、缺口图。

仅用于人工检查，全部基于原图叠加；不修改任何部件像素。
"""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import JOINT_PARENT, PART_COLORS, PARTS


def _load_font(size: int):
    for p in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf",
              "C:/Windows/Fonts/arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()


def _blend_overlay(base: np.ndarray, mask: np.ndarray, color, alpha: float = 0.38) -> np.ndarray:
    """在 base 上叠加彩色半透明遮罩。"""
    out = np.asarray(base).copy()
    m = np.asarray(mask) > 0
    col = np.array(color, dtype=np.uint8)
    for c in range(3):
        out[..., c][m] = (out[..., c][m].astype(int) * (1 - alpha)
                          + col[c] * alpha).astype(np.uint8)
    # 遮罩内若原图为透明，也填淡色，便于看到部件轮廓
    transparent = m & (out[..., 3] == 0)
    out[..., 0][transparent] = col[0]
    out[..., 1][transparent] = col[1]
    out[..., 2][transparent] = col[2]
    out[..., 3][transparent] = int(alpha * 255)
    return out


def _draw_text(img: Image.Image, xy, text, fill, font_size=14):
    d = ImageDraw.Draw(img)
    f = _load_font(font_size)
    d.text(xy, text, fill=fill, font=f)


def segmentation_preview(rgba: np.ndarray, masks: dict[str, np.ndarray],
                         seg_cfg: dict, out_path: str) -> None:
    """分割预览：原图 + 各部件彩色遮罩 + 状态标签。"""
    overlay = np.asarray(rgba).copy()
    for p in PARTS:
        m = masks.get(p)
        if m is None or m.sum() == 0:
            continue
        overlay = _blend_overlay(overlay, m, PART_COLORS[p], 0.34)
    img = Image.fromarray(overlay)
    d = ImageDraw.Draw(img)
    f = _load_font(16)
    y = 8
    # 图例
    for p in PARTS:
        cfg = (seg_cfg or {}).get("parts", {}).get(p, {})
        status = "OK" if cfg.get("confirmed") else "NEEDS_REVIEW"
        col = PART_COLORS[p]
        d.rectangle([8, y, 26, y + 14], fill=col, outline=(0, 0, 0))
        d.text((34, y - 2), f"{p}  [{status}]", fill=(255, 255, 255), font=f)
        y += 18
    img.save(out_path)


def rig_preview(rgba: np.ndarray, masks: dict[str, np.ndarray],
                joints: dict, out_path: str) -> None:
    """骨骼预览：原图 + 关节标记 + 骨骼连线 + 部件包围盒。"""
    img = Image.fromarray(np.asarray(rgba)).convert("RGB")
    d = ImageDraw.Draw(img)
    f = _load_font(14)

    # 部件包围盒
    from . import util
    for p in PARTS:
        bbox = util.bbox_of(masks.get(p)) if masks.get(p) is not None else None
        if bbox:
            x0, y0, x1, y1 = bbox
            d.rectangle([x0, y0, x1, y1], outline=PART_COLORS[p], width=1)

    # 骨骼连线
    for name, c in joints.items():
        parent = JOINT_PARENT.get(name)
        if parent and parent in joints:
            d.line([joints[parent]["x"], joints[parent]["y"],
                    c["x"], c["y"]], fill=(255, 220, 40), width=2)

    # 关节标记
    for name, c in joints.items():
        x, y = c["x"], c["y"]
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 60, 60), outline=(255, 255, 255))
        d.text((x + 6, y - 6), name, fill=(0, 255, 255), font=f)
    img.save(out_path)


def reconstructed_preview(reconstructed: np.ndarray, out_path: str) -> None:
    """重组人物预览（直接保存合成结果）。"""
    from . import util
    util.save_png(out_path, reconstructed)


def diff_preview(original: np.ndarray, diff: dict, out_path: str) -> None:
    """差异图：missing 红 / extra 蓝 / value_diff 黄。"""
    img = np.asarray(original).copy()
    m = diff["missing_mask"]
    img[..., 0][m] = 255; img[..., 1][m] = 40; img[..., 2][m] = 40; img[..., 3][m] = 255
    e = diff["extra_mask"]
    img[..., 0][e] = 40; img[..., 1][e] = 120; img[..., 2][e] = 255; img[..., 3][e] = 255
    v = diff["value_diff_mask"]
    img[..., 0][v] = 255; img[..., 1][v] = 255; img[..., 2][v] = 0; img[..., 3][v] = 255
    Image.fromarray(img).save(out_path)


def gap_preview(rgba: np.ndarray, gaps: dict, out_path: str) -> None:
    """缺口图：unassigned 红色，内部空洞黄色。"""
    img = np.asarray(rgba).copy()
    u = gaps.get("unassigned")
    if u is not None and u.sum():
        img[..., 0][u] = 255; img[..., 1][u] = 40; img[..., 2][u] = 40; img[..., 3][u] = 255
    holes = gaps.get("hole_masks") or {}
    for name, hm in holes.items():
        if hm is not None and hm.sum():
            img[..., 0][hm] = 255; img[..., 1][hm] = 230; img[..., 2][hm] = 0; img[..., 3][hm] = 255
    Image.fromarray(img).save(out_path)
