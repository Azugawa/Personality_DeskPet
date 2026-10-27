#!/usr/bin/env python3
"""Convert the authored white-background contact sheets into runtime RGBA PNGs.

The authored sheets in E:\\DeskPet\\素材 are presentation boards: they contain
labels, a paper background, and multiple poses on one canvas. This tool performs
only deterministic preparation:

  1. find the large foreground components (characters/props),
  2. crop each component with a small margin,
  3. remove the background only when it is connected to the crop border,
  4. place the result on a common transparent canvas with a bottom-centre pivot,
  5. write a manifest with source hashes and per-image bounds.

It never overwrites the authored source images. Generated desk masters are
normalized with nearest-neighbour sampling; legacy sheets are never resampled.

Run from any directory:
    python E:\\DeskPet\\deskpet\\tools\\prepare_sprite_sheets.py
"""

from __future__ import annotations

import hashlib
import json
from collections import deque
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image


PROJECT = Path(__file__).resolve().parents[1]
WORKSPACE = PROJECT.parent
SOURCE = WORKSPACE / "素材"

DIRECTIONS = [
    "front",
    "front_right",
    "right",
    "back_right",
    "back",
    "back_left",
    "left",
    "front_left",
]

WHITE_THRESHOLD = 242
IDLE_BACKGROUND = np.array([236, 237, 239], dtype=np.int16)
IDLE_THRESHOLD = 8
COMPONENT_MIN_AREA = 3000
CROP_PADDING = 2


@dataclass
class Component:
    area: int
    x0: int
    y0: int
    x1: int
    y1: int

    @property
    def width(self) -> int:
        return self.x1 - self.x0 + 1

    @property
    def height(self) -> int:
        return self.y1 - self.y0 + 1

    @property
    def cx(self) -> float:
        return (self.x0 + self.x1) * 0.5

    @property
    def cy(self) -> float:
        return (self.y0 + self.y1) * 0.5


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def foreground_mask(image: Image.Image, background: np.ndarray | None) -> np.ndarray:
    rgb = np.asarray(image.convert("RGB")).astype(np.int16)
    if background is None:
        return rgb.min(axis=2) < WHITE_THRESHOLD
    return np.abs(rgb - background).max(axis=2) > IDLE_THRESHOLD


def find_components(mask: np.ndarray) -> list[Component]:
    """Four-connected component scan; suitable for the small authored boards."""
    height, width = mask.shape
    seen = np.zeros((height, width), dtype=bool)
    components: list[Component] = []

    for y in range(height):
        for x in range(width):
            if not mask[y, x] or seen[y, x]:
                continue
            queue: deque[tuple[int, int]] = deque([(y, x)])
            seen[y, x] = True
            area = 0
            x0 = x1 = x
            y0 = y1 = y
            while queue:
                cy, cx = queue.popleft()
                area += 1
                x0 = min(x0, cx)
                x1 = max(x1, cx)
                y0 = min(y0, cy)
                y1 = max(y1, cy)
                for ny, nx in ((cy, cx - 1), (cy, cx + 1), (cy - 1, cx), (cy + 1, cx)):
                    if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        queue.append((ny, nx))
            if area >= COMPONENT_MIN_AREA:
                components.append(Component(area, x0, y0, x1, y1))

    return components


def remove_connected_background(
    rgb: np.ndarray,
    background: np.ndarray | None,
    fringe_threshold: int = 228,
) -> np.ndarray:
    """Return an alpha channel.

    Background pixels are removed only when they are connected to the crop
    border. This preserves enclosed white clothing and highlights (the shirt is
    surrounded by a dark outline) while removing the paper around the figure.
    """
    height, width = rgb.shape[:2]
    if background is None:
        near_background = rgb.min(axis=2) >= WHITE_THRESHOLD
    else:
        near_background = np.abs(rgb.astype(np.int16) - background).max(axis=2) <= IDLE_THRESHOLD

    transparent = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    for x in range(width):
        for y in (0, height - 1):
            if near_background[y, x] and not transparent[y, x]:
                transparent[y, x] = True
                queue.append((y, x))
    for y in range(height):
        for x in (0, width - 1):
            if near_background[y, x] and not transparent[y, x]:
                transparent[y, x] = True
                queue.append((y, x))

    while queue:
        cy, cx = queue.popleft()
        for ny, nx in ((cy, cx - 1), (cy, cx + 1), (cy - 1, cx), (cy + 1, cx)):
            if 0 <= ny < height and 0 <= nx < width and near_background[ny, nx] and not transparent[ny, nx]:
                transparent[ny, nx] = True
                queue.append((ny, nx))

    # The authored white sheet has a soft white fringe around the artwork.
    # Remove near-white pixels that are exposed to the removed background. This
    # is an erosion of the paper fringe only: enclosed white clothing is safe
    # because it never touches transparent background.
    for _pass in range(2):
        to_remove: list[tuple[int, int]] = []
        for y in range(1, height - 1):
            for x in range(1, width - 1):
                if transparent[y, x]:
                    continue
                touches = (
                    transparent[y - 1, x]
                    or transparent[y + 1, x]
                    or transparent[y, x - 1]
                    or transparent[y, x + 1]
                )
                if touches and int(rgb[y, x].min()) >= fringe_threshold:
                    to_remove.append((y, x))
        for y, x in to_remove:
            transparent[y, x] = True

    return np.where(transparent, 0, 255).astype(np.uint8)


def extract_component(
    image: Image.Image,
    component: Component,
    canvas_size: tuple[int, int],
    background: np.ndarray | None,
    fringe_threshold: int = 228,
) -> Image.Image:
    rgb_image = image.convert("RGB")
    x0 = max(0, component.x0 - CROP_PADDING)
    y0 = max(0, component.y0 - CROP_PADDING)
    x1 = min(rgb_image.width - 1, component.x1 + CROP_PADDING)
    y1 = min(rgb_image.height - 1, component.y1 + CROP_PADDING)
    crop = rgb_image.crop((x0, y0, x1 + 1, y1 + 1))
    rgb = np.asarray(crop).copy()
    alpha = remove_connected_background(rgb, background, fringe_threshold)
    # Decontaminate the alpha edge: fully transparent pixels must not retain the
    # white paper RGB. Otherwise nearest/linear filtering or importer alpha-border
    # repair can pull white into the visible silhouette (a classic white halo).
    rgb[alpha == 0] = (0, 0, 0)
    rgba = np.dstack([rgb, alpha]).astype(np.uint8)
    sprite = Image.fromarray(rgba, "RGBA")

    # The source crop includes transparent padding. Trim it so every output's
    # alpha bottom is the actual foot/floor contact, not an arbitrary margin.
    content_bbox = sprite.getchannel("A").getbbox()
    if content_bbox is None:
        raise ValueError("component became fully transparent during background removal")
    sprite = sprite.crop(content_bbox)

    canvas_width, canvas_height = canvas_size
    if sprite.width > canvas_width or sprite.height > canvas_height:
        raise ValueError(
            f"sprite {sprite.size} does not fit canvas {canvas_size}; "
            "increase the canvas in this script"
        )
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    canvas.alpha_composite(sprite, ((canvas_width - sprite.width) // 2, canvas_height - sprite.height))
    return canvas


def group_by_row(components: list[Component], split_y: float) -> tuple[list[Component], list[Component]]:
    top = sorted([c for c in components if c.cy < split_y], key=lambda c: c.cx)
    bottom = sorted([c for c in components if c.cy >= split_y], key=lambda c: c.cx)
    return top, bottom


def write_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def save_manifest(manifest: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build_static_character(manifest: dict) -> None:
    source = SOURCE / "八方向图.png"
    image = Image.open(source)
    components = find_components(foreground_mask(image, None))
    if len(components) != 8:
        raise ValueError(f"{source.name}: expected 8 characters, found {len(components)}")
    top, bottom = group_by_row(components, 650.0)
    ordered = top + bottom
    if len(top) != 4 or len(bottom) != 4:
        raise ValueError(f"{source.name}: expected 4+4 characters, found {len(top)}+{len(bottom)}")

    canvas = (256, 384)
    outputs = []
    for name, comp in zip(DIRECTIONS, ordered):
        sprite = extract_component(image, comp, canvas, None, fringe_threshold=80)
        rel = f"assets/character/spirit/directions/{name}.png"
        write_png(sprite, PROJECT / rel)
        outputs.append(
            {
                "direction": name,
                "path": f"res://{rel}",
                "source_bbox": [comp.x0, comp.y0, comp.width, comp.height],
                "canvas": list(canvas),
                "anchor": [canvas[0] // 2, canvas[1]],
            }
        )
    manifest["static_directions"] = {
        "source": str(source),
        "source_sha256": sha256(source),
        "canvas": list(canvas),
        "images": outputs,
    }


def build_walking_character(manifest: dict) -> None:
    source = SOURCE / "人物走路八方向图.png"
    image = Image.open(source)
    components = find_components(foreground_mask(image, None))
    if len(components) != 32:
        raise ValueError(f"{source.name}: expected 32 walk frames, found {len(components)}")
    top, bottom = group_by_row(components, 500.0)
    if len(top) != 16 or len(bottom) != 16:
        raise ValueError(f"{source.name}: expected 16+16 walk frames, found {len(top)}+{len(bottom)}")

    canvas = (96, 160)
    outputs = {}
    for row_index, row in enumerate((top, bottom)):
        for direction_index in range(4):
            name = DIRECTIONS[row_index * 4 + direction_index]
            block = row[direction_index * 4 : direction_index * 4 + 4]
            frames = []
            for frame_index, comp in enumerate(block, start=1):
                sprite = extract_component(image, comp, canvas, None, fringe_threshold=80)
                rel = f"assets/character/spirit/walk/{name}_{frame_index:02d}.png"
                write_png(sprite, PROJECT / rel)
                frames.append(
                    {
                        "path": f"res://{rel}",
                        "source_bbox": [comp.x0, comp.y0, comp.width, comp.height],
                    }
                )
            outputs[name] = {"frames": frames, "canvas": list(canvas), "anchor": [canvas[0] // 2, canvas[1]]}
    manifest["walk_directions"] = {
        "source": str(source),
        "source_sha256": sha256(source),
        "canvas": list(canvas),
        "directions": outputs,
    }


def build_idle_front(manifest: dict) -> None:
    source = SOURCE / "idle_breath.png"
    image = Image.open(source)
    components = find_components(foreground_mask(image, IDLE_BACKGROUND))
    if len(components) != 5:
        raise ValueError(f"{source.name}: expected 5 idle frames, found {len(components)}")
    ordered = sorted(components, key=lambda c: c.cx)
    canvas = (352, 512)
    frames = []
    for index, comp in enumerate(ordered, start=1):
        sprite = extract_component(image, comp, canvas, IDLE_BACKGROUND, fringe_threshold=80)
        rel = f"assets/character/spirit/idle/front_{index:02d}.png"
        write_png(sprite, PROJECT / rel)
        frames.append(
            {
                "path": f"res://{rel}",
                "source_bbox": [comp.x0, comp.y0, comp.width, comp.height],
            }
        )
    manifest["idle_front"] = {
        "source": str(source),
        "source_sha256": sha256(source),
        "canvas": list(canvas),
        "anchor": [canvas[0] // 2, canvas[1]],
        "frames": frames,
    }


def build_furniture(manifest: dict) -> None:
    source = SOURCE / "桌子和椅子八方向图.png"
    image = Image.open(source)
    components = find_components(foreground_mask(image, None))
    if len(components) != 16:
        raise ValueError(f"{source.name}: expected 16 furniture views, found {len(components)}")
    top, bottom = group_by_row(components, 520.0)
    if len(top) != 8 or len(bottom) != 8:
        raise ValueError(f"{source.name}: expected 8 chairs + 8 tables, found {len(top)}+{len(bottom)}")

    result = {}
    for kind, row, canvas in (
        ("chair", top, (120, 160)),
        ("desk", bottom, (160, 160)),
    ):
        if kind == "desk":
            result[kind] = build_reference_desk()
            continue
        views = {}
        for name, comp in zip(DIRECTIONS, row):
            sprite = extract_component(image, comp, canvas, None, fringe_threshold=200)
            rel = f"assets/props/{kind}/{name}.png"
            write_png(sprite, PROJECT / rel)
            views[name] = {
                "path": f"res://{rel}",
                "source_bbox": [comp.x0, comp.y0, comp.width, comp.height],
                "canvas": list(canvas),
                "anchor": [canvas[0] // 2, canvas[1]],
            }
        result[kind] = {
            "source": str(source),
            "source_sha256": sha256(source),
            "canvas": list(canvas),
            "views": views,
        }
    manifest["furniture"] = result


def build_reference_desk() -> dict:
    """Package image_gen masters without re-segmenting their transparent art."""
    source_dir = SOURCE / "桌子八方向_坐姿参考"
    canvas = (160, 160)
    views = {}
    # The symmetric rear three-quarter views are assigned by projected long
    # edge orientation, so a complete turn alternates correctly at side views.
    source_names = {"back_right": "back_left", "back_left": "back_right"}
    for name in DIRECTIONS:
        source = source_dir / f"{source_names.get(name, name)}.png"
        master = Image.open(source).convert("RGBA")
        alpha = master.getchannel("A")
        if alpha.getextrema()[0] != 0:
            raise ValueError(f"{source}: expected a transparent generated master")
        # Very faint generated pixels must not determine the ground pivot.
        bbox = alpha.point(lambda value: 255 if value >= 128 else 0).getbbox()
        if bbox is None:
            raise ValueError(f"{source}: empty desk")
        sprite = master.crop(bbox)
        target_width = 72 if name in ("left", "right") else 144
        target_height = round(sprite.height * target_width / sprite.width)
        sprite = sprite.resize((target_width, target_height), Image.Resampling.NEAREST)
        if target_height > canvas[1]:
            raise ValueError(f"{source}: desk does not fit runtime canvas")
        output = Image.new("RGBA", canvas)
        output.alpha_composite(sprite, ((canvas[0] - target_width) // 2, canvas[1] - target_height))
        rel = f"assets/props/desk/{name}.png"
        write_png(output, PROJECT / rel)
        views[name] = {
            "path": f"res://{rel}", "source": str(source),
            "source_sha256": sha256(source), "source_bbox": list(bbox),
            "canvas": list(canvas), "anchor": [80, 160],
            "content_size": [target_width, target_height],
        }
    return {
        "source": str(source_dir), "reference": str(SOURCE / "坐姿定格.png"),
        "reference_sha256": sha256(SOURCE / "坐姿定格.png"),
        "generator": "built-in image_gen", "resampling": "nearest",
        "canvas": list(canvas), "views": views,
    }


def build_computer(manifest: dict) -> None:
    source = SOURCE / "电脑八方向图.png"
    image = Image.open(source)
    components = find_components(foreground_mask(image, None))
    if len(components) != 8:
        raise ValueError(f"{source.name}: expected 8 computer views, found {len(components)}")
    top, bottom = group_by_row(components, 520.0)
    ordered = top + bottom
    if len(top) != 4 or len(bottom) != 4:
        raise ValueError(f"{source.name}: expected 4+4 computer views, found {len(top)}+{len(bottom)}")

    canvas = (224, 256)
    views = {}
    for name, comp in zip(DIRECTIONS, ordered):
        sprite = extract_component(image, comp, canvas, None, fringe_threshold=200)
        rel = f"assets/props/computer/{name}.png"
        write_png(sprite, PROJECT / rel)
        views[name] = {
            "path": f"res://{rel}",
            "source_bbox": [comp.x0, comp.y0, comp.width, comp.height],
            "canvas": list(canvas),
            "anchor": [canvas[0] // 2, canvas[1]],
        }
    manifest["computer"] = {
        "source": str(source),
        "source_sha256": sha256(source),
        "canvas": list(canvas),
        "views": views,
    }


def validate_outputs(manifest: dict) -> None:
    paths: list[str] = []
    for section in ("static_directions", "idle_front"):
        paths.extend(item["path"] for item in manifest[section].get("images", manifest[section].get("frames", [])))
    for direction, data in manifest.get("walk_directions", {}).get("directions", {}).items():
        paths.extend(item["path"] for item in data["frames"])
    for kind in ("chair", "desk"):
        paths.extend(item["path"] for item in manifest["furniture"][kind]["views"].values())
    paths.extend(item["path"] for item in manifest["computer"]["views"].values())

    for res_path in paths:
        path = PROJECT / res_path.removeprefix("res://")
        image = Image.open(path)
        if image.mode != "RGBA":
            raise ValueError(f"{path}: expected RGBA, got {image.mode}")
        alpha = image.getchannel("A")
        if alpha.getbbox() is None:
            raise ValueError(f"{path}: output is fully transparent")
        if alpha.getpixel((0, 0)) != 0:
            raise ValueError(f"{path}: top-left corner is not transparent")
    manifest["validation"] = {"rgba_images": len(paths), "all_corners_transparent": True}
    print(f"validated {len(paths)} RGBA images")


def main() -> None:
    if not SOURCE.is_dir():
        raise SystemExit(f"source directory not found: {SOURCE}")
    manifest: dict = {
        "generated_by": "deskpet/tools/prepare_sprite_sheets.py",
        "direction_order": DIRECTIONS,
        "notes": "Source presentation sheets are never modified. Outputs keep native pixels and use bottom-centre pivots.",
    }
    build_static_character(manifest)
    build_walking_character(manifest)
    build_idle_front(manifest)
    build_furniture(manifest)
    build_computer(manifest)
    validate_outputs(manifest)
    save_manifest(manifest, PROJECT / "assets" / "sprite_manifest.json")
    print("wrote assets/sprite_manifest.json")


if __name__ == "__main__":
    main()
