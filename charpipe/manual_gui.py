"""可选的人工校正 GUI（tkinter）。

运行：python build_assets.py --input <原图> --gui

功能：
- 选择部件，用画笔添加/擦除该部件遮罩（生成 strokes 写入 segmentation.json）。
- 拖动关节锚点（写入 joints.json）。
- 标记部件"已确认"。
- 保存后重新运行 `--stage export` 生效。

无显示环境时自动给出提示并回退到 JSON 编辑方式。
"""
from __future__ import annotations

import json
import os

import numpy as np


def run_gui(input_path: str, output_dir: str) -> None:
    try:
        import tkinter as tk
        from PIL import Image, ImageTk
    except Exception as e:  # pragma: no cover
        print(f"[gui] 无法启动图形界面（{e}）。请改用 config/segmentation.json 与 "
              f"config/joints.json 进行人工校正。")
        return

    from . import PARTS, PART_COLORS, ALL_JOINTS, JOINT_PARENT, util
    from . import analyze, landmarks, segmentation, joints as joints_mod

    rgba = util.load_rgba(input_path)
    h, w, _ = rgba.shape
    opaque = util.alpha_mask(rgba)
    lm = landmarks.detect(opaque)

    # 读取或初始化配置
    seg_path = os.path.join(output_dir, "config", "segmentation.json")
    joints_path = os.path.join(output_dir, "config", "joints_manual.json")
    if os.path.exists(seg_path):
        with open(seg_path, encoding="utf-8") as f:
            seg_cfg = json.load(f)
    else:
        seg_cfg = segmentation.default_segmentation(lm)
    auto = segmentation.build_auto_masks(opaque, lm)
    masks = segmentation.build_masks(opaque, lm, seg_cfg)
    joints = joints_mod.estimate(lm)
    if os.path.exists(joints_path):
        with open(joints_path, encoding="utf-8") as f:
            jc = json.load(f)
        joints = joints_mod.merge_joint_edits(joints, jc.get("joints"))

    # 显示缩放
    DISP = 820
    scale = min(1.0, DISP / max(w, h))
    dw, dh = int(w * scale), int(h * scale)

    root = tk.Tk()
    root.title("角色资产人工校正")

    state = {"part": PARTS[0], "mode": "add", "radius": 6, "joint": None,
             "strokes_add": [], "strokes_erase": [], "joints": joints}

    canvas = tk.Canvas(root, width=dw, height=dh, bg="black")
    canvas.pack(side="left", fill="both", expand=True)

    # 侧栏
    side = tk.Frame(root)
    side.pack(side="right", fill="y", padx=6, pady=6)

    tk.Label(side, text="部件").pack(anchor="w")
    part_var = tk.StringVar(value=PARTS[0])
    for p in PARTS:
        tk.Radiobutton(side, text=p, value=p, variable=part_var,
                       command=lambda p=p: set_part(p)).pack(anchor="w")

    tk.Label(side, text="模式").pack(anchor="w", pady=(10, 0))
    mode_var = tk.StringVar(value="add")
    tk.Radiobutton(side, text="添加(add)", value="add", variable=mode_var,
                   command=lambda: state.update(mode="add")).pack(anchor="w")
    tk.Radiobutton(side, text="擦除(erase)", value="erase", variable=mode_var,
                   command=lambda: state.update(mode="erase")).pack(anchor="w")
    tk.Radiobutton(side, text="拖动关节", value="joint", variable=mode_var,
                   command=lambda: state.update(mode="joint")).pack(anchor="w")

    tk.Label(side, text="画笔半径").pack(anchor="w", pady=(10, 0))
    r_var = tk.IntVar(value=6)
    tk.Scale(side, from_=1, to=60, orient="horizontal", variable=r_var,
             command=lambda v: state.update(radius=int(float(v)))).pack(anchor="w", fill="x")

    status = tk.Label(side, text="", fg="white", bg="#333", wraplength=220, justify="left")
    status.pack(anchor="w", fill="x", pady=10)

    def set_part(p):
        state["part"] = p
        redraw()

    def redraw():
        disp = np.asarray(rgba).copy()
        sel = state["part"]
        # 半透明底
        mask = masks[sel]
        from .previews import _blend_overlay
        disp = _blend_overlay(disp, mask, PART_COLORS[sel], 0.30)
        im = Image.fromarray(disp).resize((dw, dh), Image.NEAREST)
        state["tk"] = ImageTk.PhotoImage(im)
        canvas.delete("all")
        canvas.create_image(0, 0, image=state["tk"], anchor="nw")
        # 关节
        for name, c in state["joints"].items():
            x, y = c["x"] * scale, c["y"] * scale
            canvas.create_oval(x - 3, y - 3, x + 3, y + 3, fill="red", outline="white")
            if name in ("neck", "shoulder_L", "shoulder_R", "elbow_L", "elbow_R",
                        "wrist_L", "wrist_R", "hip_L", "hip_R", "knee_L", "knee_R",
                        "ankle_L", "ankle_R"):
                canvas.create_text(x + 5, y - 5, text=name, fill="cyan", anchor="nw")
        status.config(text=f"部件={sel}  模式={state['mode']}  半径={state['radius']}px")

    def to_orig(ev):
        return ev.x / scale, ev.y / scale

    def nearest_joint(ev):
        ox, oy = to_orig(ev)
        best, bd = None, 30 / scale
        for name, c in state["joints"].items():
            d = ((c["x"] - ox) ** 2 + (c["y"] - oy) ** 2) ** 0.5
            if d < bd:
                best, bd = name, d
        return best

    def on_press(ev):
        if state["mode"] == "joint":
            state["joint"] = nearest_joint(ev)
        else:
            apply_brush(ev)

    def on_drag(ev):
        if state["mode"] == "joint" and state["joint"]:
            ox, oy = to_orig(ev)
            state["joints"][state["joint"]]["x"] = round(ox, 2)
            state["joints"][state["joint"]]["y"] = round(oy, 2)
            redraw()
        elif state["mode"] in ("add", "erase"):
            apply_brush(ev)

    def apply_brush(ev):
        ox, oy = to_orig(ev)
        r = state["radius"] / scale
        if state["mode"] == "add":
            state["strokes_add"].append([round(ox, 1), round(oy, 1), round(r, 1)])
        else:
            state["strokes_erase"].append([round(ox, 1), round(oy, 1), round(r, 1)])
        # 实时更新工作遮罩
        cfg = seg_cfg["parts"][state["part"]]
        cfg["strokes"] = {"add": state["strokes_add"], "erase": state["strokes_erase"]}
        masks[state["part"]] = segmentation.apply_manual(auto[state["part"]], cfg, (h, w))
        redraw()

    def save():
        # 写回 segmentation.json
        for p in PARTS:
            seg_cfg["parts"][p].setdefault("strokes", {"add": [], "erase": []})
        sel = state["part"]
        seg_cfg["parts"][sel]["strokes"] = {"add": state["strokes_add"],
                                            "erase": state["strokes_erase"]}
        os.makedirs(os.path.join(output_dir, "config"), exist_ok=True)
        with open(seg_path, "w", encoding="utf-8") as f:
            json.dump(seg_cfg, f, ensure_ascii=False, indent=2)
        jc = {"version": 1,
              "joints": {n: {"x": state["joints"][n]["x"], "y": state["joints"][n]["y"]}
                          for n in ALL_JOINTS}}
        with open(joints_path, "w", encoding="utf-8") as f:
            json.dump(jc, f, ensure_ascii=False, indent=2)
        status.config(text="已保存 config/segmentation.json 与 config/joints_manual.json")

    def confirm_selected():
        seg_cfg["parts"][state["part"]]["confirmed"] = True
        status.config(text=f"{state['part']} 已标记为 confirmed")

    tk.Button(side, text="保存配置", command=save).pack(fill="x", pady=4)
    tk.Button(side, text="确认当前部件", command=confirm_selected).pack(fill="x", pady=4)

    canvas.bind("<Button-1>", on_press)
    canvas.bind("<B1-Motion>", on_drag)
    redraw()
    root.mainloop()
