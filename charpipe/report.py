"""质量检查报告与人工检查清单。

绝不因为部件成功导出就判定拆分合格；所有未确认遮罩标记 NEEDS_REVIEW。
"""
from __future__ import annotations

import json
from datetime import datetime

import numpy as np

from . import PARTS


def build_report(*, source: dict, landmarks: dict, parts_info: dict,
                 joints_cfg: dict, diff: dict, gaps: dict,
                 canvas_shape, exported_parts: list[str] | None,
                 warnings: list[str]) -> dict:
    """汇总为 validation_report.json 结构。"""
    h, w = canvas_shape
    jj = joints_cfg["joints"]
    joint_list = []
    for name, c in jj.items():
        in_bounds = 0 <= c["x"] <= w and 0 <= c["y"] <= h
        joint_list.append({
            "name": name, "x": c["x"], "y": c["y"],
            "part": c["part"], "parent": c["parent"],
            "in_bounds": bool(in_bounds),
        })

    parts = {}
    confirmed = needs_review = empty = exported = 0
    for p in PARTS:
        info = parts_info[p]
        st = info["status"]
        if st == "CONFIRMED":
            confirmed += 1
        elif st == "NEEDS_REVIEW":
            needs_review += 1
        elif st == "EMPTY":
            empty += 1
        if exported_parts and p in exported_parts:
            exported += 1
        parts[p] = {
            "status": st,
            "confirmed": bool(info["confirmed"]),
            "bbox": info["bbox"],
            "offset": info["offset"],
            "pixel_count": info["pixel_count"],
            "exported": bool(exported_parts and p in exported_parts),
            "notes": info.get("notes", []),
        }

    summary = {
        "total_parts": len(PARTS),
        "confirmed": confirmed,
        "needs_review": needs_review,
        "empty": empty,
        "exported": exported,
    }

    report = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "source": source.get("source"),
        "image": source.get("image"),
        "background": source.get("background"),
        "landmarks": landmarks,
        "summary": summary,
        "parts": parts,
        "joints": joint_list,
        "reconstruction": {
            "missing_pixels": diff["missing_pixels"],
            "extra_pixels": diff["extra_pixels"],
            "value_diff_pixels": diff["value_diff_pixels"],
            "coverage": diff["coverage"],
        },
        "gaps": {
            "unassigned_pixels": gaps["unassigned_count"],
            "hole_counts": gaps["hole_counts"],
        },
        "warnings": warnings,
    }
    return report


def save_report(report: dict, path: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)


def save_checklist(report: dict, path: str) -> None:
    """输出清晰的人工检查清单（Markdown）。"""
    lines = []
    lines.append("# 角色资产人工检查清单")
    lines.append("")
    lines.append(f"生成时间：{report['generated_at']}")
    lines.append("")
    s = report["summary"]
    lines.append("## 汇总")
    lines.append(f"- 部件总数：{s['total_parts']}")
    lines.append(f"- 已确认：{s['confirmed']}")
    lines.append(f"- 待人工确认（NEEDS_REVIEW）：{s['needs_review']}")
    lines.append(f"- 空部件（EMPTY，无法分离）：{s['empty']}")
    lines.append(f"- 已导出：{s['exported']}")
    lines.append("")
    lines.append(f"- 重组覆盖率：{report['reconstruction']['coverage']*100:.3f}%")
    lines.append(f"- 缺失像素：{report['reconstruction']['missing_pixels']}")
    lines.append(f"- 多余像素（多为人工补绘）：{report['reconstruction']['extra_pixels']}")
    lines.append(f"- 颜色不一致像素：{report['reconstruction']['value_diff_pixels']}")
    lines.append(f"- 未分配像素：{report['gaps']['unassigned_pixels']}")
    lines.append("")

    confirmed_lines = []
    review_lines = []
    empty_lines = []
    for p, info in report["parts"].items():
        row = f"- `{p}`：{info['status']}"
        if info["bbox"]:
            row += f"，bbox={info['bbox']}"
        if info["notes"]:
            row += "（" + "；".join(info["notes"]) + "）"
        if info["status"] == "CONFIRMED":
            confirmed_lines.append(row)
        elif info["status"] == "EMPTY":
            empty_lines.append(row)
        else:
            review_lines.append(row)

    lines.append("## 已确认（可直接用于动画）")
    lines.extend(confirmed_lines or ["- （无）"])
    lines.append("")
    lines.append("## 仍需补绘 / 校正（NEEDS_REVIEW）")
    lines.extend(review_lines or ["- （无）"])
    lines.append("")
    lines.append("## 已并入 head / 无法分离（EMPTY，未单独导出）")
    lines.extend(empty_lines or ["- （无）"])
    lines.append("")

    if report["warnings"]:
        lines.append("## 警告")
        for w in report["warnings"]:
            lines.append(f"- {w}")
        lines.append("")

    lines.append("## 人工校正方法")
    lines.append("1. 编辑 `config/segmentation.json`：为每个部件设置 `method`（auto/polygon/manual）、"
                "`polygon`（多边形顶点，原图坐标）、`strokes.add/erase`（圆形笔刷），`confirmed` 设为 true 表示确认。")
    lines.append("2. 编辑 `config/joints_manual.json`（人工关节修正，仅含 x/y）："
                "调整关节坐标后重新运行即生效；`config/joints.json` 是最终输出，供动画引擎读取。")
    lines.append("3. 需要补绘缺失像素时，编辑 `config/manual_repair.json`：")
    lines.append("   `{\"<部件名>\": [{\"x\":..,\"y\":..,\"r\":..,\"color\":[r,g,b,a]}]}`，"
                "省略 color 时自动取最近原图颜色，补绘像素会标记为 synthetic。")
    lines.append("4. 也可运行 `python build_assets.py --input <原图> --gui` 使用可视化画笔/关节拖动。")
    lines.append("5. 校正完成后运行 `python build_assets.py --input <原图> --stage export` 导出正式资产。")
    lines.append("")
    lines.append("> 注意：L/R 为角色自身左/右（角色左手 = 观察者右侧）。补绘像素非原图，"
                "在 layers.json 中以 `synthetic` 标记。")

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
