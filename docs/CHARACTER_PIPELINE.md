# 像素角色资产包制作流水线（charpipe）

> 桌面宠物 Godot 工程位于 `deskpet/`，启动、架构、配置与测试见
> [deskpet/README.md](deskpet/README.md)。本文件描述的是人物资产制作流水线，不是桌宠运行时。

> **2026-10-27 更新：** 当前桌宠运行时已经使用新的八方向/走路/家具/电脑白底
> contact sheets。它们由 `deskpet/tools/prepare_sprite_sheets.py` 裁切、去背景、
> 对齐脚底并输出到 `deskpet/assets/`，运行说明与架构见
> [deskpet/README.md](deskpet/README.md)。
>
> 本文下面的 `charpipe` 是早期的“单张正面角色 → 部件/关节结构”流水线，
> 仍然是未来换装和分层动画的结构参考，但不是当前运行素材的唯一来源。

基于**单张正面 2D 像素角色 PNG**，构建可用于后续帧动画引擎的标准化资产包：
部件图层、遮罩、关节骨骼、图层顺序、预览图与质量检查报告。

- 只做「角色资产制作」，**不生成动画帧**、**不重绘角色**、**不调用 AI 生成模型**。
- 半自动分割 + 人工校正，绝不假设自动分割一次到位。
- 像素风格保护：只复制原图像素，不做缩放/插值/平滑/模糊。
- 坐标统一使用**原图左上角原点**，像素单位（支持浮点）。
- L/R = **角色自身的左/右**（角色左手 = 观察者右侧）。

---

## 一、目录结构

```
E:\DeskPet\
├── build_assets.py            # 命令行入口
├── charpipe/                  # 流水线包
│   ├── __init__.py            # 部件/关节/图层定义
│   ├── util.py                # 图像读写、遮罩、多边形、最近邻
│   ├── analyze.py             # 原图分析与背景检测
│   ├── landmarks.py           # 几何地标估计（对称轴/头肩腰髋膝踝）
│   ├── segmentation.py        # 自动分割 + 人工遮罩合并
│   ├── joints.py              # 骨骼关节估计与配置
│   ├── repair.py              # 缺口检测 + 人工补绘
│   ├── reconstruct.py         # 重组 + 像素差异检测
│   ├── export.py              # 部件导出与配置文件写出
│   ├── previews.py            # 预览图生成
│   ├── report.py              # 质量报告与检查清单
│   └── manual_gui.py          # 可选人工校正 GUI（tkinter）
├── requirements.txt
└── character_assets/          # 输出（运行时生成）
```

## 二、依赖安装

推荐使用 conda 虚拟环境（本机 `python310` 环境已包含全部依赖）：

```bash
conda activate python310
pip install -r requirements.txt     # 若环境已含依赖可跳过
```

依赖仅三项：`numpy`、`Pillow`、`opencv-python`（OpenCV 可选，缺失时自动回退到 Pillow 实现）。

## 三、运行命令

```bash
conda activate python310

# 1) 首次运行：自动分割 + 生成预览图与待校正遮罩
python build_assets.py --input "E:\DeskPet\Spirit\人物图_透明.png"

# 2) 检查 previews/ 与 config/，人工校正后导出正式资产包
python build_assets.py --input "E:\DeskPet\Spirit\人物图_透明.png" --stage export

# （可选）可视化人工校正 GUI
python build_assets.py --input "E:\DeskPet\Spirit\人物图_透明.png" --gui

# （可选）快速确认全部部件
python build_assets.py --input "E:\DeskPet\Spirit\人物图_透明.png" --confirm-all --stage export
```

其他参数：

| 参数 | 说明 |
|------|------|
| `--output` | 输出目录，默认 `character_assets` |
| `--stage auto\|export` | `auto` 首次运行；`export` 导出正式资产 |
| `--allow-bg-removal` | 仅在检测到**安全**纯色背景时允许去背景（深色背景仍拒绝） |
| `--confirm-part <名>` | 标记指定部件为已确认，可多次 |
| `--confirm-all` | 标记全部部件已确认 |
| `--head-y <int>` | 人工指定头/躯干分界 y（覆盖自动检测，持久化到 `segmentation.json` 的 `head_torso_y`） |
| `--gui` | 打开人工校正 GUI |

## 四、人工校正方式（三种，任选）

1. **编辑 `config/segmentation.json`**：为每个部件设置
   - `method`：`auto`（自动）/ `polygon`（多边形）/ `manual`（仅笔刷）
   - `polygon`：多边形顶点列表 `[[x,y], ...]`（原图坐标）
   - `strokes.add` / `strokes.erase`：圆形笔刷 `[[x,y,r], ...]`
   - `confirmed`：设为 `true` 表示人工确认
2. **编辑 `config/joints_manual.json`**：调整关节 `x`/`y`（只含坐标，重新运行即生效）。
   `config/joints.json` 是最终输出（自动 + 人工合并），供动画引擎直接读取修改。
3. **补绘缺失像素**：编辑 `config/manual_repair.json`：
   ```json
   {"head": [{"x": 1021, "y": 500, "r": 6, "color": [54, 52, 53, 255]}]}
   ```
   省略 `color` 时自动取最近原图颜色；补绘像素在 `layers.json` 中标记 `synthetic`。
4. 或运行 `--gui` 用画笔添加/擦除、拖动关节。

> 校正后重新运行 `--stage export` 即可。

## 五、输出资产包

```
character_assets/
├── source/original.png              # 原图副本（原文件不被覆盖）
├── parts/                           # 正式部件（仅已确认部件，全画布坐标）
│   ├── head.png  torso.png
│   ├── upper_arm_L.png  forearm_L.png  hand_L.png
│   ├── upper_arm_R.png  forearm_R.png  hand_R.png
│   ├── thigh_L.png  shin_L.png  thigh_R.png  shin_R.png
├── parts_cropped/                   # 裁剪版（配合 layers.json 的 offset 定位）
├── parts_provisional/               # auto 阶段的临时部件（供检查）
├── masks/<part>_mask.png            # 各部件遮罩（白=选中）
├── previews/
│   ├── segmentation_preview.png     # 分割着色预览
│   ├── rig_preview.png              # 关节/骨骼/包围盒
│   ├── reconstructed_character.png  # 重组人物
│   ├── diff_preview.png             # 差异（missing 红 / extra 蓝 / 颜色 黄）
│   └── gap_preview.png              # 缺口
├── config/
│   ├── character.json               # 原图元数据/边界/颜色/背景
│   ├── joints.json                  # 13 个关节 + 父节点 + 部件锚点
│   ├── layers.json                  # 图层顺序/bbox/offset/pivot
│   └── segmentation.json            # 分割配置（可编辑）
├── repair/                          # 缺口/待补绘遮罩
└── reports/
    ├── validation_report.json       # 自动质量检查
    └── checklist.md                 # 人工检查清单
```

## 六、质量检查内容

- 所有导出部件为合法 PNG、透明通道正确。
- 每个部件的原始坐标（bbox）与偏移（offset）完整。
- 关节坐标在画布范围内（`in_bounds`）。
- 按图层顺序重组得到完整人物，并与原图逐像素对比（缺失/多余/颜色差异）。
- 未分配像素、部件内部空洞、背景污染等输出警告。
- 未人工确认的遮罩输出 `NEEDS_REVIEW`，**不**在 `--stage export` 中导出正式素材。

## 七、设计原则

- 自动分割是「几何启发式初值」，全部默认 `NEEDS_REVIEW`。
- 原图不透明背景时先诊断；深色背景可能误删头发/眼镜/裤子，默认拒绝自动去背景。
- 关节连接处保留适量重叠像素，避免动画旋转出现缝隙。
- 补绘像素标记 `synthetic`，不与原图像素混淆。
