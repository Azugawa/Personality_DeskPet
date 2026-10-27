"""几何地标估计：对称轴与头/肩/腰/髋/膝/踝/手臂下沿等关键行。

这是"自动估计"，结果全部需要人工确认；仅凭单张正面图无法精确恢复
真实骨骼，所有数值都是启发式初值。
"""
from __future__ import annotations

import numpy as np

from . import util


def _smooth(arr: np.ndarray, win: int) -> np.ndarray:
    win = max(1, int(win))
    if win == 1:
        return arr.astype(float)
    k = np.ones(win, float) / win
    return np.convolve(arr.astype(float), k, mode="same")


def detect(opaque: np.ndarray) -> dict:
    """由 alpha 布尔遮罩估计地标。返回 dict（写入 character.json / segmentation.json）。"""
    h, w = opaque.shape
    ys, xs = np.nonzero(opaque)
    if xs.size == 0:
        return {"error": "empty_mask"}

    top, bottom = int(ys.min()), int(ys.max())
    left, right = int(xs.min()), int(xs.max())
    body_h = bottom - top + 1

    # 对称轴：每行质心中位数（对非对称发梢/配饰鲁棒）
    coms = []
    for y in range(top, bottom + 1):
        idx = np.nonzero(opaque[y])[0]
        if idx.size:
            coms.append(float(idx.mean()))
    symmetry = float(np.median(coms)) if coms else float(w) / 2

    # 行宽序列（只含非空行）
    rows, widths = [], []
    for y in range(top, bottom + 1):
        idx = np.nonzero(opaque[y])[0]
        if idx.size:
            rows.append(y)
            widths.append(float(idx[-1] - idx[0] + 1))
    rows = np.array(rows, int)
    widths = np.array(widths, float)
    win = max(3, (len(widths) // 80) | 1)
    sw = _smooth(widths, win)
    Wmax = float(sw.max())

    def first_y_below(y0, cond):
        """从 y0 向下（含）找第一个满足 cond 的行；找不到返回 None。"""
        for i in range(len(rows)):
            if rows[i] >= y0 and cond(sw[i]):
                return int(rows[i])
        return None

    # --- 颈部/肩部：宽度首次达到近最大宽度的行 ---
    neck_y = first_y_below(top, lambda v: v >= 0.97 * Wmax)
    neck_method = "width_plateau"
    if neck_y is None or neck_y - top < 0.10 * body_h:
        neck_y = top + int(0.28 * body_h)
        neck_method = "ratio_fallback"
    shoulder_y = neck_y

    # --- 腰部：躯干段（颈下 15% 至底部上 15%）内最窄行 ---
    lo = neck_y + int(0.15 * body_h)
    hi = bottom - int(0.15 * body_h)
    band = (rows >= lo) & (rows <= hi)
    if band.any():
        waist_y = int(rows[np.flatnonzero(band)[np.argmin(sw[band])]])
    else:
        waist_y = neck_y + int(0.35 * (bottom - neck_y))

    # --- 髋部：腰下方至底部上 10% 内最宽行 ---
    hi2 = bottom - int(0.10 * body_h)
    band2 = (rows >= waist_y) & (rows <= hi2)
    if band2.any():
        hip_y = int(rows[np.flatnonzero(band2)[np.argmax(sw[band2])]])
    else:
        hip_y = waist_y + int(0.25 * (bottom - waist_y))
    hip_width = float(sw[rows == hip_y][0]) if (rows == hip_y).any() else float(Wmax * 0.7)

    # --- 膝部：髋下方宽度首次降到髋宽的 0.62 以下 ---
    knee_y = first_y_below(hip_y, lambda v: v <= 0.62 * hip_width)
    if knee_y is None:
        knee_y = hip_y + int(0.30 * (bottom - hip_y))

    # --- 小腿参考宽度：膝至底部的宽度中位数 ---
    band3 = rows >= knee_y
    leg_width = float(np.median(sw[band3])) if band3.any() else float(sw.min())

    # --- 踝部：膝下方宽度首次降到小腿宽的 0.82 以下（脚部收窄顶端） ---
    ankle_y = first_y_below(knee_y, lambda v: v <= 0.82 * leg_width)
    if ankle_y is None:
        ankle_y = bottom

    # --- 手臂下沿：肩以下宽度首次降到 0.85 * 最大宽（手臂/手结束） ---
    arm_bottom_y = first_y_below(neck_y, lambda v: v < 0.85 * Wmax)
    if arm_bottom_y is None:
        arm_bottom_y = waist_y

    # 肩部横向偏移（腋窝线），与手臂分割共用
    # 0.50 * 半宽：手臂再向内收一点，torso 只保留中央衬衫/领带
    armpit_offset = 0.50 * (Wmax / 2.0)

    return {
        "symmetry_x": round(symmetry, 3),
        "top_y": top, "bottom_y": bottom,
        "left_x": left, "right_x": right,
        "body_width": right - left + 1,
        "body_height": body_h,
        "max_width": round(Wmax, 3),
        "neck_y": neck_y, "shoulder_y": shoulder_y,
        "waist_y": waist_y, "hip_y": hip_y,
        "knee_y": knee_y, "ankle_y": ankle_y,
        "arm_bottom_y": arm_bottom_y,
        "armpit_offset": round(armpit_offset, 3),
        "leg_width": round(leg_width, 3),
        "hip_width": round(hip_width, 3),
        "methods": {"neck": neck_method},
    }
