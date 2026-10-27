"""charpipe — 像素角色资产包制作流水线。

把单张正面像素角色图拆分为可动画的部件图层，并输出标准化资产包：
部件 PNG、遮罩、关节骨骼、图层顺序、预览图与质量检查报告。

设计原则：
- 半自动分割 + 人工校正，绝不假设自动分割一次到位。
- 所有坐标使用原始画布坐标系（左上角为原点，浮点像素单位）。
- 像素风格保护：只复制原始像素，不做缩放/插值/平滑/模糊。
- L/R 统一为角色自身的左/右（角色左手 = 观察者看到的右侧）。
"""

__version__ = "1.0.0"

# 部件定义（12 个），按角色自身的 L/R 命名
PARTS = [
    "head",
    "torso",
    "upper_arm_L", "forearm_L", "hand_L",
    "upper_arm_R", "forearm_R", "hand_R",
    "thigh_L", "shin_L",
    "thigh_R", "shin_R",
]

# 图层顺序（z 越大越靠上绘制）
LAYER_Z = {
    "torso": 10,
    "thigh_R": 20, "thigh_L": 20,
    "shin_R": 22, "shin_L": 22,
    "upper_arm_R": 30, "upper_arm_L": 30,
    "forearm_R": 32, "forearm_L": 32,
    "hand_R": 34, "hand_L": 34,
    "head": 40,
}

# 每个部件归属的关节（旋转锚点）
PART_JOINT = {
    "head": "neck",
    "torso": None,  # torso 作为根，无父关节
    "upper_arm_L": "shoulder_L", "forearm_L": "elbow_L", "hand_L": "wrist_L",
    "upper_arm_R": "shoulder_R", "forearm_R": "elbow_R", "hand_R": "wrist_R",
    "thigh_L": "hip_L", "shin_L": "knee_L",
    "thigh_R": "hip_R", "shin_R": "knee_R",
}

# 部件可视化颜色（BGR-free 的 RGB）
PART_COLORS = {
    "head": (236, 64, 122),
    "torso": (66, 133, 244),
    "upper_arm_L": (255, 152, 0), "forearm_L": (255, 193, 7), "hand_L": (255, 235, 59),
    "upper_arm_R": (0, 188, 212), "forearm_R": (3, 169, 244), "hand_R": (33, 150, 243),
    "thigh_L": (156, 39, 176), "shin_L": (103, 58, 183),
    "thigh_R": (76, 175, 80), "shin_R": (139, 195, 74),
}

# 关节定义
JOINT_PARENT = {
    "neck": None,
    "shoulder_L": "neck", "shoulder_R": "neck",
    "elbow_L": "shoulder_L", "elbow_R": "shoulder_R",
    "wrist_L": "elbow_L", "wrist_R": "elbow_R",
    "hip_L": None, "hip_R": None,
    "knee_L": "hip_L", "knee_R": "hip_R",
    "ankle_L": "knee_L", "ankle_R": "knee_R",
}

JOINT_PART = {
    "neck": "torso",
    "shoulder_L": "torso", "shoulder_R": "torso",
    "elbow_L": "upper_arm_L", "elbow_R": "upper_arm_R",
    "wrist_L": "forearm_L", "wrist_R": "forearm_R",
    "hip_L": "thigh_L", "hip_R": "thigh_R",
    "knee_L": "thigh_L", "knee_R": "thigh_R",
    "ankle_L": "shin_L", "ankle_R": "shin_R",
}

ALL_JOINTS = list(JOINT_PARENT.keys())
