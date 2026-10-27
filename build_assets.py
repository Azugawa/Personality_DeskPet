#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""基于单张正面像素角色图，构建可用于帧动画的角色资产包。

用法：
    python build_assets.py --input <原图.png>                 # 自动分割 + 预览（首次运行）
    python build_assets.py --input <原图.png> --stage export  # 人工校正后导出正式资产包
    python build_assets.py --input <原图.png> --gui           # 可视化人工校正

说明：
    - 绝不覆盖原始文件；原图副本保存到 <输出>/source/original.png。
    - 坐标统一使用原图左上角原点、像素单位。
    - L/R 为角色自身左/右（角色左手 = 观察者右侧）。
"""
from __future__ import annotations

import argparse
import json
import os
import sys

from charpipe import PARTS, util
from charpipe import analyze, export, joints as joints_mod, landmarks
from charpipe import previews, reconstruct, repair, report, segmentation


def _load_json(path, default=None):
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return default


def run(args) -> int:
    if not os.path.exists(args.input):
        print(f"[error] 输入文件不存在：{args.input}")
        return 2

    rgba = util.load_rgba(args.input)
    h, w, _ = rgba.shape

    # ---- 1. 分析 ----
    character = analyze.analyze(args.input, rgba)

    # ---- 2. 背景处理 ----
    bg = character["background"]
    if bg.get("needs_removal"):
        if args.allow_bg_removal and bg.get("safe"):
            rgba = analyze.remove_background(rgba)
            character["background"]["removed"] = True
            character["background"]["note"] += " 已按用户授权执行去背景。"
            print("[info] 已执行背景去除。")
        elif args.allow_bg_removal and not bg.get("safe"):
            print("[warning] 背景为深色且可能与角色混淆，出于安全拒绝自动去背景。"
                  "请人工确认后再处理。")
        else:
            print(f"[halt] {bg.get('note')}")
            print("       若确认背景可安全去除，请加 --allow-bg-removal 重试；"
                  "否则请先人工处理好背景。")
            return 3

    opaque = util.alpha_mask(rgba)
    if opaque.sum() == 0:
        print("[error] 图片无任何不透明像素。")
        return 2

    # ---- 3. 地标估计 ----
    lm = landmarks.detect(opaque)

    # ---- 4. 载入/初始化分割配置（保留人工校正） ----
    out_dir = args.output
    cfg_dir = os.path.join(out_dir, "config")
    seg_path = os.path.join(cfg_dir, "segmentation.json")
    joints_manual_path = os.path.join(cfg_dir, "joints_manual.json")
    repair_path = os.path.join(cfg_dir, "manual_repair.json")

    seg_cfg = _load_json(seg_path)
    if seg_cfg is None:
        seg_cfg = segmentation.default_segmentation(lm)
    else:
        # 保留人工编辑（method/polygon/strokes/confirmed），刷新自动地标引用
        seg_cfg.setdefault("parts", {})
        for p in PARTS:
            seg_cfg["parts"].setdefault(p, segmentation.default_part_cfg())
        seg_cfg["landmarks"] = {k: v for k, v in lm.items()}
        seg_cfg["symmetry_x"] = lm.get("symmetry_x")

    # 命令行确认
    for p in args.confirm_part:
        if p in PARTS:
            seg_cfg["parts"][p]["confirmed"] = True
    if args.confirm_all:
        for p in PARTS:
            seg_cfg["parts"][p]["confirmed"] = True

    # 头部模式 + 头/躯干分界
    head_mode = args.head_mode
    if head_mode is None:
        head_mode = seg_cfg.get("head_mode", "split")
    lm["head_mode"] = head_mode
    seg_cfg["head_mode"] = head_mode

    if head_mode == "split":
        head_y = args.head_y
        if head_y is None:
            head_y = seg_cfg.get("head_torso_y")
        if head_y is not None:
            head_y = int(head_y)
            lm["head_bottom_y"] = head_y
            seg_cfg["head_torso_y"] = head_y  # 持久化，后续重跑继续生效

    masks = segmentation.build_masks(opaque, lm, seg_cfg)

    # ---- 5. 关节 ----
    joints = joints_mod.estimate(lm)
    # 人工关节修正独立存放在 joints_manual.json，避免与自动估计互相污染
    manual_joints = _load_json(joints_manual_path)
    if manual_joints:
        overrides = manual_joints.get("joints") or manual_joints
        joints = joints_mod.merge_joint_edits(joints, overrides)
    joints_cfg = joints_mod.make_joints_config(lm, joints)

    # ---- 6. 部件 + 补绘 ----
    manual_repair = repair.load_manual_repair(repair_path)
    parts, synthetic = export.prepare_parts(rgba, masks, manual_repair)
    parts_info = export.build_parts_info(masks, parts, seg_cfg, head_mode=head_mode)
    layers_cfg = export.build_layers_cfg((h, w), masks, parts_info, joints_cfg, synthetic)

    # ---- 7. 缺口检测 ----
    gaps = repair.detect_gaps(opaque, masks)

    # ---- 8. 重组 + 差异 ----
    reconstructed = reconstruct.composite(parts, (h, w))
    diff = reconstruct.diff(rgba, reconstructed, opaque)

    # ---- 9. 警告收集 ----
    warnings = []
    for p in PARTS:
        if parts_info[p]["status"] == "EMPTY":
            warnings.append(f"部件 {p} 自动分割为空，需人工提供遮罩。")
        if parts_info[p]["status"] == "NEEDS_REVIEW":
            warnings.append(f"部件 {p} 为自动估计，尚未人工确认（NEEDS_REVIEW）。")
    if diff["missing_pixels"] > 0:
        warnings.append(f"重组结果相对原图缺失 {diff['missing_pixels']} 像素。")
    if diff["value_diff_pixels"] > 0:
        warnings.append(f"重组结果与原图有 {diff['value_diff_pixels']} 个像素颜色不一致（异常）。")
    if gaps["unassigned_count"] > 0:
        warnings.append(f"存在 {gaps['unassigned_count']} 个未分配到任何部件的像素。")
    for p, n in gaps["hole_counts"].items():
        if n > 0:
            warnings.append(f"部件 {p} 内部疑似空洞 {n} 像素，需人工检查补绘。")
    if bg.get("needs_removal") and not bg.get("safe"):
        warnings.append("背景深色且未确认去除，可能影响分割，请人工确认。")

    # ---- 10. 报告 ----
    report_cfg = report.build_report(
        source=character, landmarks=lm, parts_info=parts_info,
        joints_cfg=joints_cfg, diff=diff, gaps=gaps, canvas_shape=(h, w),
        exported_parts=None, warnings=warnings)

    # ---- 11. 写目录 ----
    os.makedirs(out_dir, exist_ok=True)
    previews_dir = os.path.join(out_dir, "previews")
    report_dir = os.path.join(out_dir, "reports")
    repair_dir = os.path.join(out_dir, "repair")
    for d in (previews_dir, report_dir, repair_dir, cfg_dir):
        os.makedirs(d, exist_ok=True)

    previews.segmentation_preview(rgba, masks, seg_cfg,
                                  os.path.join(previews_dir, "segmentation_preview.png"))
    previews.rig_preview(rgba, masks, joints_cfg["joints"],
                         os.path.join(previews_dir, "rig_preview.png"))
    previews.reconstructed_preview(reconstructed,
                                   os.path.join(previews_dir, "reconstructed_character.png"))
    previews.diff_preview(rgba, diff, os.path.join(previews_dir, "diff_preview.png"))
    previews.gap_preview(rgba, gaps, os.path.join(previews_dir, "gap_preview.png"))

    # 缺口/修复遮罩
    if gaps["unassigned_count"] > 0:
        util.save_mask_png(os.path.join(repair_dir, "unassigned.png"), gaps["unassigned"])
    for p in PARTS:
        hm = gaps["hole_masks"].get(p)
        if hm is not None and hm.sum() > 0:
            util.save_mask_png(os.path.join(repair_dir, f"{p}_hole.png"), hm)

    # 阶段
    stage = args.stage
    mode = "export" if stage == "export" else "auto"
    exported = export.write_package(
        out_dir, source_path=args.input, rgba=rgba, character=character,
        segmentation_cfg=seg_cfg, joints_cfg=joints_cfg, layers_cfg=layers_cfg,
        masks=masks, parts=parts, synthetic=synthetic, mode=mode)

    # 更新报告里的导出状态
    report_cfg["summary"]["exported"] = len(exported)
    for p in PARTS:
        report_cfg["parts"][p]["exported"] = p in exported
    report.save_report(report_cfg, os.path.join(report_dir, "validation_report.json"))
    report.save_checklist(report_cfg, os.path.join(report_dir, "checklist.md"))

    # ---- 12. 控制台摘要 ----
    print("=" * 62)
    print(f"输入：{args.input}")
    print(f"尺寸：{w}x{h}  背景：{character['background']['detected']}")
    print(f"对称轴 x≈{lm['symmetry_x']:.1f}  头底 y={lm['neck_y']}  腰 y={lm['waist_y']}"
          f"  髋 y={lm['hip_y']}  膝 y={lm['knee_y']}  踝 y={lm['ankle_y']}")
    print("-" * 62)
    for p in PARTS:
        info = parts_info[p]
        mark = {"CONFIRMED": "[OK]      ", "NEEDS_REVIEW": "[REVIEW]  ",
                "EMPTY": "[EMPTY]   "}[info["status"]]
        print(f"  {mark}{p:14s} px={info['pixel_count']:7d}  "
              f"bbox={info['bbox']}")
    print("-" * 62)
    print(f"重组覆盖率={diff['coverage']*100:.2f}%  缺失={diff['missing_pixels']}"
          f"  多余={diff['extra_pixels']}  颜色不一致={diff['value_diff_pixels']}")
    print(f"未分配像素={gaps['unassigned_count']}")
    print("-" * 62)
    if stage == "export":
        print(f"正式导出 {len(exported)}/{len(PARTS)} 个已确认部件 → {os.path.join(out_dir, 'parts')}")
        if len(exported) < len(PARTS):
            print("以下部件尚未确认，未导出正式素材（遮罩与状态已提供）：")
            for p in PARTS:
                if p not in exported:
                    print(f"  - {p} [{parts_info[p]['status']}]")
    else:
        print(f"首次运行（auto）：已生成预览与待校正遮罩 → {out_dir}")
        print("请检查 previews/ 与 config/segmentation.json，完成人工校正后运行：")
        print(f"  python build_assets.py --input {args.input} --stage export")
    print("=" * 62)
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="像素角色资产包制作流水线")
    ap.add_argument("--input", required=True, help="原始角色 PNG 路径")
    ap.add_argument("--output", default="character_assets", help="输出目录（默认 character_assets）")
    ap.add_argument("--stage", choices=["auto", "export"], default="auto",
                    help="auto=首次运行生成预览与待校正遮罩；export=校正后导出正式资产包")
    ap.add_argument("--allow-bg-removal", action="store_true",
                    help="允许在检测到安全纯色背景时执行去背景（深色背景仍会拒绝）")
    ap.add_argument("--confirm-part", action="append", default=[],
                    help="标记某部件为已确认，可多次使用")
    ap.add_argument("--confirm-all", action="store_true", help="标记全部部件为已确认")
    ap.add_argument("--head-y", type=int, default=None,
                    help="人工指定头/躯干分界 y（覆盖自动检测，仅影响 split 模式）")
    ap.add_argument("--head-mode", choices=["split", "merge_upper", "big_head"],
                    default=None,
                    help="split=头/躯干/手臂分别切分；merge_upper=整个上半身并入 head；"
                         "big_head=大头角色(head到腰, 躯干+手臂在腰~膝, 腿在膝以下)")
    ap.add_argument("--gui", action="store_true", help="打开人工校正 GUI（tkinter）")
    ap.add_argument("--verbose", action="store_true", help="输出更多诊断信息")
    args = ap.parse_args(argv)

    if args.gui:
        from charpipe import manual_gui
        manual_gui.run_gui(args.input, args.output)
        return 0

    return run(args)


if __name__ == "__main__":
    sys.exit(main())
