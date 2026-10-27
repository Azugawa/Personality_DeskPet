"""二维骨骼/关节配置：估计 13 个关节，支持 JSON 读写与人工修改。

坐标均为原图左上角原点、像素单位（浮点）。仅凭正面图无法恢复真实 3D 骨骼，
本模块只给出 2D 锚点初值，供动画引擎旋转部件。
"""
from __future__ import annotations

import numpy as np

from . import (ALL_JOINTS, JOINT_PARENT, JOINT_PART, PART_JOINT)


def estimate(lm: dict) -> dict:
    """由地标估计关节坐标。返回 joints dict。"""
    sym = float(lm["symmetry_x"])
    neck_y = float(lm["neck_y"])
    shoulder_y = float(lm["shoulder_y"])
    waist_y = float(lm["waist_y"])
    hip_y = float(lm["hip_y"])
    knee_y = float(lm["knee_y"])
    ankle_y = float(lm["ankle_y"])
    arm_bottom = float(lm["arm_bottom_y"])
    armpit = float(lm["armpit_offset"])
    max_w = float(lm["max_width"])

    sh_x = armpit                      # 肩部横向偏移
    hip_half = 0.42 * max_w            # 髋横向偏移
    leg_half = 0.26 * max_w            # 膝/踝横向偏移

    arm_len = max(1.0, arm_bottom - shoulder_y)
    elbow_y = shoulder_y + 0.45 * arm_len
    wrist_y = shoulder_y + 0.78 * arm_len

    def j(x, y):
        return {"x": round(float(x), 2), "y": round(float(y), 2)}

    joints = {
        "neck":       j(sym, neck_y),
        "shoulder_L": j(sym + sh_x, shoulder_y),
        "shoulder_R": j(sym - sh_x, shoulder_y),
        "elbow_L":    j(sym + sh_x * 0.82, elbow_y),
        "elbow_R":    j(sym - sh_x * 0.82, elbow_y),
        "wrist_L":    j(sym + sh_x * 0.55, wrist_y),
        "wrist_R":    j(sym - sh_x * 0.55, wrist_y),
        "hip_L":      j(sym + hip_half, hip_y),
        "hip_R":      j(sym - hip_half, hip_y),
        "knee_L":     j(sym + leg_half, knee_y),
        "knee_R":     j(sym - leg_half, knee_y),
        "ankle_L":    j(sym + leg_half, ankle_y),
        "ankle_R":    j(sym - leg_half, ankle_y),
    }
    return joints


def make_joints_config(lm: dict, joints: dict | None = None) -> dict:
    """生成 joints.json 结构。"""
    joints = joints if joints is not None else estimate(lm)
    jlist = {}
    for name in ALL_JOINTS:
        c = joints[name]
        jlist[name] = {
            "x": c["x"], "y": c["y"],
            "part": JOINT_PART[name],
            "parent": JOINT_PARENT[name],
        }
    pivots = {}
    for part, jn in PART_JOINT.items():
        if jn is None:
            pivots[part] = {"joint": None,
                            "x": joints["neck"]["x"],
                            "y": lm.get("waist_y", joints["neck"]["y"])}
        else:
            pivots[part] = {"joint": jn, "x": joints[jn]["x"], "y": joints[jn]["y"]}
    return {"version": 1, "root": "torso", "joints": jlist, "part_pivots": pivots}


def merge_joint_edits(base: dict, joints_file_joints: dict | None) -> dict:
    """用 joints.json 中的人工坐标覆盖自动估计（结构不变）。"""
    if not joints_file_joints:
        return base
    out = dict(base)
    for name, c in joints_file_joints.items():
        if name in out:
            out[name] = {"x": float(c["x"]), "y": float(c["y"])}
    return out
