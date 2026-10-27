"""通用工具：图像读写、遮罩运算、多边形/笔刷、最近邻缩放、颜色量化等。

像素风格保护：本模块不提供任何会改变像素内容的缩放/模糊操作；
唯一的 resize 工具使用最近邻插值，且默认根本不会被调用。
"""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw

try:  # OpenCV 可选（python310 conda 环境已包含）
    import cv2
    _HAVE_CV2 = True
except Exception:  # pragma: no cover
    _HAVE_CV2 = False


# ---------------------------------------------------------------------------
# 图像读写
# ---------------------------------------------------------------------------
def load_rgba(path: str) -> np.ndarray:
    """读取 PNG，统一为 RGBA uint8 (H, W, 4)。"""
    im = Image.open(path)
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    return np.asarray(im).copy()


def save_png(path: str, rgba: np.ndarray) -> None:
    """保存 RGBA 数组为 PNG。"""
    arr = np.asarray(rgba, dtype=np.uint8)
    if arr.ndim == 2:
        arr = np.dstack([arr, arr, arr, np.full(arr.shape, 255, np.uint8)])
    elif arr.shape[2] == 3:
        arr = np.dstack([arr, np.full(arr.shape[:2], 255, np.uint8)])
    Image.fromarray(arr).save(path)


def save_mask_png(path: str, mask: np.ndarray) -> None:
    """保存布尔遮罩为白色实心 PNG（白=选中）。"""
    m = (np.asarray(mask) > 0).astype(np.uint8) * 255
    Image.fromarray(m, mode="L").save(path)


# ---------------------------------------------------------------------------
# 遮罩 / 像素
# ---------------------------------------------------------------------------
def alpha_mask(rgba: np.ndarray) -> np.ndarray:
    """alpha > 0 的布尔遮罩。"""
    return np.asarray(rgba)[..., 3] > 0


def opaque_mask(rgba: np.ndarray, thresh: int = 128) -> np.ndarray:
    """alpha >= thresh 的布尔遮罩（用于忽略抗锯齿边缘）。"""
    return np.asarray(rgba)[..., 3] >= thresh


def extract_part(rgba: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """只保留 mask 内的像素，其余透明。返回新 RGBA 数组。"""
    out = np.zeros_like(rgba, dtype=np.uint8)
    m = np.asarray(mask) > 0
    out[m] = np.asarray(rgba)[m]
    return out


def bbox_of(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    """布尔遮罩的闭区间包围盒 (x0, y0, x1, y1)，空返回 None。"""
    m = np.asarray(mask) > 0
    ys, xs = np.nonzero(m)
    if xs.size == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def crop_with_offset(rgba: np.ndarray, mask: np.ndarray):
    """按 mask 包围盒裁剪 rgba，返回 (cropped, offset=(x0,y0))。"""
    bbox = bbox_of(mask)
    if bbox is None:
        return None, (0, 0)
    x0, y0, x1, y1 = bbox
    return np.asarray(rgba)[y0:y1 + 1, x0:x1 + 1].copy(), (x0, y0)


# ---------------------------------------------------------------------------
# 几何掩膜
# ---------------------------------------------------------------------------
def polygon_to_mask(points, shape) -> np.ndarray:
    """多边形 -> 布尔遮罩。points: 可迭代 [(x,y), ...]，shape: (H, W)。"""
    h, w = int(shape[0]), int(shape[1])
    pts = [(int(round(float(p[0]))), int(round(float(p[1])))) for p in points]
    if len(pts) < 3:
        return np.zeros((h, w), bool)
    if _HAVE_CV2:
        m = np.zeros((h, w), np.uint8)
        cv2.fillPoly(m, [np.array(pts, dtype=np.int32)], 255)
        return m > 0
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).polygon(pts, fill=255)
    return np.asarray(img) > 0


def circles_to_mask(circles, shape, value=True) -> np.ndarray:
    """圆形笔刷 -> 布尔遮罩。circles: [(x, y, r), ...]。"""
    h, w = int(shape[0]), int(shape[1])
    m = np.zeros((h, w), bool)
    if not circles:
        return m
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    for c in circles:
        x, y, r = float(c[0]), float(c[1]), float(c[2])
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    return np.asarray(img) > 0


def connected_components(mask: np.ndarray):
    """连通域分析。返回 (num_labels, labels, stats)。空 mask 返回 (0, 空, 空)。"""
    m = (np.asarray(mask) > 0).astype(np.uint8)
    if m.sum() == 0:
        return 0, np.zeros_like(m, np.int32), None
    if _HAVE_CV2:
        n, labels, stats, _ = cv2.connectedComponentsWithStats(m, 8)
        return n, labels, stats
    # 极简 BFS 回退（仅 label + 面积，stats 用占位）
    h, w = m.shape
    labels = np.zeros((h, w), np.int32)
    n = 1
    from collections import deque
    for y in range(h):
        for x in range(w):
            if m[y, x] and labels[y, x] == 0:
                q = deque([(y, x)])
                labels[y, x] = n
                while q:
                    cy, cx = q.popleft()
                    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0),
                                   (1, 1), (1, -1), (-1, 1), (-1, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and labels[ny, nx] == 0:
                            labels[ny, nx] = n
                            q.append((ny, nx))
                n += 1
    return n, labels, None


def dilate(mask: np.ndarray, iters: int = 1) -> np.ndarray:
    """3x3 膨胀（用于把细缝、断点连接起来做诊断）。"""
    m = (np.asarray(mask) > 0).astype(np.uint8)
    if _HAVE_CV2:
        k = np.ones((3, 3), np.uint8)
        return cv2.dilate(m, k, iterations=iters) > 0
    out = m.copy()
    for _ in range(iters):
        prev = out
        shifted = [np.roll(np.roll(prev, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
        out = prev.copy()
        for s in shifted:
            out |= s
    return out > 0


def erode(mask: np.ndarray, iters: int = 1) -> np.ndarray:
    m = (np.asarray(mask) > 0).astype(np.uint8)
    if _HAVE_CV2:
        k = np.ones((3, 3), np.uint8)
        return cv2.erode(m, k, iterations=iters) > 0
    out = m.copy()
    for _ in range(iters):
        prev = out
        out = prev.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                out &= np.roll(np.roll(prev, dy, 0), dx, 1)
    return out > 0


# ---------------------------------------------------------------------------
# 最近邻缩放（唯一被允许的 resize，仅在显式需要时使用）
# ---------------------------------------------------------------------------
def nearest_resize(rgba: np.ndarray, fx: float, fy: float) -> np.ndarray:
    """最近邻缩放。仅用于预览降采样等非资产场合，绝不用于部件导出。"""
    h, w = np.asarray(rgba).shape[:2]
    nh, nw = max(1, int(round(h * fy))), max(1, int(round(w * fx)))
    if _HAVE_CV2:
        return cv2.resize(np.asarray(rgba), (nw, nh), interpolation=cv2.INTER_NEAREST)
    im = Image.fromarray(np.asarray(rgba, dtype=np.uint8)).resize(
        (nw, nh), resample=Image.NEAREST)
    return np.asarray(im)


# ---------------------------------------------------------------------------
# 颜色分析
# ---------------------------------------------------------------------------
def dominant_colors(rgba: np.ndarray, alpha_thresh: int = 128, k: int = 16,
                    quant: int = 16) -> list[dict]:
    """统计主色。返回 [{"rgb": [r,g,b], "count": n}, ...]，按出现次数降序。"""
    a = np.asarray(rgba)
    op = a[a[..., 3] >= alpha_thresh][:, :3]
    if op.size == 0:
        return []
    q = (op // quant) * quant
    uniq, cnt = np.unique(q.reshape(-1, 3), axis=0, return_counts=True)
    order = np.argsort(-cnt)
    return [{"rgb": [int(v) for v in uniq[i]], "count": int(cnt[i])}
            for i in order[:k]]
