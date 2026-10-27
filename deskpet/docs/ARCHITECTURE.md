# DeskPet 架构说明（持久化桌面宠物阶段）

本文件描述当前默认运行时。旧的静态 2.5D 场景系统仍保留在仓库中作为历史参考，
但 `Main` 不再启动 `SceneManager`。

---

## 1. 模块边界

| 模块 | 文件 | 负责 | 不负责 |
|---|---|---|---|
| 应用入口 | `scripts/core/main.gd` | 窗口模式、预览背景、调试层、启动 `PetWorld` | 角色行为、家具逻辑 |
| 持久世界 | `scripts/world/pet_world.gd` | 组装 Character/Furniture/StateMachine/Brain/Input，提供公共操作 | 具体动画、具体输入解析 |
| 角色表现 | `scripts/character/character.gd` | 位置、方向、脚底锚点、阴影、当前动画入口 | 选择行为、随机决策 |
| 动画表现 | `scripts/character/character_animator.gd` | 加载 clip、`SpriteFrames`、fps、loop、canvas、scale | 业务状态、自动行为 |
| 行为状态机 | `scripts/behavior/action_state_machine.gd` | 动作切换、手动优先级、暂停、排队、完成/拒绝信号 | 图片帧、家具内部表现 |
| 自动行为 | `scripts/behavior/behavior_brain.gd` | 空闲计时、随机选择、自动暂停检查 | 直接移动/改动画 |
| 输入 | `scripts/input/pet_input.gd` | 键鼠 → 命令；注册 InputMap；窗口拖动 | 决定动作是否合法 |
| 家具管理 | `scripts/props/furniture_manager.gd` | 创建独立家具、显示/隐藏/移动/方向/锚点查询 | 角色动作 |
| 单件家具 | `scripts/props/furniture_view.gd` | 方向贴图、阴影、出现动画、交互锚点 | 全局调度 |
| 动作入口 | `scripts/behavior/pet_activity_controller.gd` | 右键动作 → 家具缓现 → 走到接近点 → 等待坐姿/后续流程 | 图片帧播放 |
| 右键菜单 | `scripts/ui/pet_menu.gd` | 显示动作菜单并发出选择 | 状态机决策 |
| 窗口 | `scripts/core/window_controller.gd` | 透明/无边框/置顶/位置 | 鼠标命中、角色动作 |
| 旧静态场景 | `scene_manager.gd` / `scene_view.gd` / `pseudo3d*` | 历史 2.5D 场景与调试家具 | 默认运行路径 |

---

## 2. 场景树

```text
Main (Node)
├── BackdropLayer (CanvasLayer, -100)
│   ├── Backdrop
│   └── StageGuide（默认隐藏，旧预览网格）
├── PetWorld (Node2D)
│   ├── WorldSort (Node2D, y_sort_enabled=true)
│   │   ├── Character
│   │   │   ├── ShadowRoot/ShadowView
│   │   │   └── BodyRoot
│   │   │       ├── AnimatedBody (AnimatedSprite2D)
│   │   │       ├── FullBodySprite（旧 fallback，隐藏）
│   │   │       └── PartsRoot（换装预留）
│   │   └── Furniture_chair / Furniture_desk / Furniture_computer
│   ├── FurnitureManager (Node)
│   ├── StateMachine (Node)
│   ├── BehaviorBrain (Node)
│   ├── ActivityController (Node)
│   ├── PetInput (Node)
│   └── PetMenu (CanvasLayer, 110)
└── DebugOverlay (CanvasLayer, 100，桌面模式隐藏)
```

`WorldSort` 按 y 排序角色和家具，形成 2D 舞台的前后关系。角色和家具的阴影仍然是独立节点。

---

## 3. 启动数据流

1. `Main._ready()`
   - 读取 `config/app.json`
   - 设置预览背景、可选地面网格
   - 解析 `--desktop-mode` 并应用窗口属性
   - 调用 `PetWorld.setup()`
   - 预览模式创建调试面板
2. `PetWorld.setup()`
   - 读取 `config/world/default.json`
   - 实例化 Character，设置脚底位置
   - 创建 FurnitureManager 和独立家具
   - 读取 `config/behavior.json`
   - 连接 StateMachine + BehaviorBrain + PetInput
3. `Character.setup()`
   - 读取 `config/characters/spirit.json`
   - 读取 `config/animations/spirit.json`
   - 建立 16 个动画（8 idle + 8 walk）
   - 播放默认方向 `front` 的 `idle_front`
4. `FurnitureManager.setup()`
   - 按世界配置创建 `chair`、`desk`、`computer`
   - 每个实例独立设置位置、方向、可见性和阴影
5. `StateMachine.setup()`
   - 进入 `idle`
   - 手动命令开始后设置自动暂停
6. `BehaviorBrain.setup()`
   - 启动空闲计时
7. `PetInput.setup()`
   - 注册 `pet_move_*` InputMap actions
   - 开始接收键盘和鼠标

---

## 4. 状态机

### 4.1 三层区分

- **长期状态**：`idle`、`walk`、`interact`；未来 `seated`、`carrying`、`resting`。
- **动作流程**：`walk_to`、`walk_manual`、`head_pat`、`furniture_toggle`；未来 `sit_down` / `sit` / `stand_up` / `carry_*`。
- **视觉动画**：由 `CharacterAnimator` 播放的具体 clip，例如 `idle_front`、`walk_back_right`。

状态机不把每个视觉变化都做成顶层状态。

### 4.2 手动优先

`PetInput` 只提交命令。`ActionStateMachine.request_command()` 执行：

- 手动命令会刷新 4 秒自动暂停。
- 自动命令在忙碌、排队或暂停时被拒绝。
- 手动命令可中断自动 walk。
- 不可中断动作（未来的 sit/carry）会把手动命令放入队列，在安全点后执行。
- 自动行为默认关闭；开启后只在 `can_auto_act()` 为真时提出。

### 4.3 走路

- 手动移动：`PetInput` 每帧提供方向，状态机在 `_process()` 中按速度移动并更新八方向 walk clip。
- 自动走路：状态机创建 Tween，到目标后回到 idle；目标被限制在 `walk_bounds` 内。
- 屏幕方向映射：
  - 下 → `front`
  - 上 → `back`
  - 右 → `right`
  - 左 → `left`
  - 右下 → `front_right`
  - 右上 → `back_right`
  - 左下 → `front_left`
  - 左上 → `back_left`

### 4.4 摸头

当前没有专门摸头帧。手动摸头会：

- 进入 `interact` 状态；
- 播放当前方向的 idle；
- 对 `BodyRoot` 做轻微弹跳；
- 0.75 秒后回 idle。

这是一个明确标记的占位表现，不冒充完整摸头动画。

### 4.5 坐下/起身

`sit` / `stand` 已经在状态机中保留，但由于没有坐姿素材：

- 不会伪造坐姿；
- 会发出 `command_rejected`；
- 家具的 `seat` 锚点已经可由 `FurnitureManager` 查询；
- 后续只需补充 sit 帧和 safe-point 流程。

---

## 5. 动画数据

`config/animations/spirit.json`：

```json
{
  "animations": {
    "idle_front": {
      "frames": ["res://.../idle/front_01.png", "..."],
      "fps": 3.5,
      "loop": true,
      "canvas": [352, 512],
      "scale": 0.6061
    },
    "walk_front": {
      "frames": ["res://.../walk/front_01.png", "..."],
      "fps": 8.0,
      "loop": true,
      "canvas": [96, 160],
      "scale": 2.069
    }
  },
  "direction_idle": { "front": "idle_front", "...": "..." },
  "direction_walk": { "front": "walk_front", "...": "..." }
}
```

`CharacterAnimator` 在 setup 时：

- 读取所有帧；
- 构造 `SpriteFrames`；
- 设置 `AnimatedSprite2D.centered = false`；
- 设置 `offset = (-canvas.x/2, -canvas.y)`；
- 设置显示 scale；
- 将脚底固定在 Character 根节点。

不同 clip 可以使用不同的 canvas 和 scale。当前：
- 站立：约 300 px 高；
- 走路：约 300 px 高；
- 待机：约 300 px 高。

---

## 6. 家具

### 6.1 单件家具节点

`scenes/props/furniture.tscn`：

```text
Furniture (Node2D，根节点即地面锚点)
├── ShadowRoot
│   └── ShadowView
└── VisualRoot（显示缩放）
    ├── Sprite
    └── Anchors
        ├── SeatAnchor
        ├── WorkSurfaceAnchor
        └── ScreenAnchor
```

根节点位置始终是**底边中心地面接触点**。方向贴图只改变 `Sprite.texture`，不改变锚点约定。

### 6.2 锚点

- 椅子：`seat_anchor_uv = [0.5, 0.67]`
- 木桌：`work_surface_uv = [0.5, 0.42]`、`lean_anchor_uv = [0.5, 0.36]`
- 电脑桌：`work_surface_uv = [0.5, 0.68]`、`screen_anchor_uv = [0.5, 0.35]`

锚点由 canvas 和 uv 计算，运行时通过 `FurnitureView.get_anchor_position()` 获取全局位置。
未来坐下时让角色骨盆/脚底对齐这些点，而不是直接改家具内部变量。

### 6.3 定位与层级

- 家具在 `WorldSort` 下按 y 排序。
- 家具阴影 `z_index=-2`。
- 角色阴影 `z_index=-5`。
- 家具之间的遮挡由 y 和树顺序决定，不再依赖旧 `SceneManager`。

---

### 6.4 右键动作与场景布置

`config/activities.json` 定义动作入口：

```json
{
  "id": "rest",
  "label": "休息",
  "required_furniture": ["chair", "desk"],
  "show_furniture": ["chair", "desk"],
  "hide_furniture": ["computer"],
  "approach_furniture": "chair",
  "required_animation": "sit_front",
  "reveal_seconds": 0.9
}
```

流程：

```text
右键角色
  → PetMenu 显示待机 / 休息 / 玩电脑
  → ActivityController 检查家具和动画
  → 显隐家具（出现动画可配置 duration）
  → 走到 approach_furniture 的接近点
  → 有 sit 帧：进入预留的坐下流程（下一阶段接入）
  → 无 sit 帧：停在椅子前，发出 activity_waiting
```

当前 `rest` / `computer` 会在“停在椅子前”结束，因为 `sit_front` 还没有制作。
菜单标签会标出“坐姿待补”。这是有意的安全降级，不是完整的坐下动作。

`PetMenu` 是一个 `PopupMenu`，右键角色时按鼠标位置弹出；选择后只发出 activity id，
不直接控制角色。

---

## 7. 输入与窗口

- `PetInput` 运行时创建 `pet_move_up/down/left/right`，绑定 W/S/A/D 和方向键。
- 左键按下记录位置；移动超过 5 px 进入窗口拖动；未拖动点击角色则触发摸头。
- 窗口拖动使用 `get_window().position += event.relative`。
- 窗口属性由 `WindowController.apply()` 管理。
- 预览模式默认不透明；`--desktop-mode` 才启用透明、无边框、置顶。
- 尚未实现：
  - 透明区域鼠标穿透；
  - 像素级点击遮罩；
  - 右键菜单；
  - 焦点/任务栏/托盘行为。

---

## 8. 素材准备

见 `tools/prepare_sprite_sheets.py` 与 `assets/sprite_manifest.json`。

约束：

- 原始文件在 `E:\DeskPet\素材`，不覆盖。
- 不缩小/拉伸原图来生成运行帧；只裁切、去背景、放入统一 canvas。
- 显示缩放由运行时配置负责，使用最近邻。
- 八方向图的标签不进入运行素材。
- 浅色纸边只从透明背景连通区域和暴露边缘去除，不修改被角色轮廓包围的白色衬衫。

---

## 9. 旧静态场景的去留

以下文件仍是有效历史代码，但不是默认运行路径：

- `scripts/core/scene_manager.gd`
- `scripts/scene_management/scene_view.gd`
- `scripts/visual/pseudo3d.gd`
- `scripts/props/pseudo3d_prop_view.gd`
- `config/scenes/*.json`
- `tests/integration_tests.gd`（旧 176 项静态场景测试）

当前 `SceneManager` 仍是 Autoload，但它不会启动 `SceneView`；旧测试也不在当前 `test_runner.tscn` 中。
后续确认后可选择：

1. 删除旧场景系统；或
2. 把 SceneManager 改造为“环境预设”层，仅切换背景/投影，不销毁 PetWorld。

---

## 10. 测试结构

- `tests/test_runner.tscn` 启动 `tests/pet_tests.gd`。
- 实例化真实 `Main` 和 `PetWorld`。
- 使用真实 CharacterAnimator / StateMachine / FurnitureManager。
- 覆盖 147 项检查。
- 视觉截图由 `tests/capture_pet.tscn` 生成。
- `tools/verify_desktop_transparency.ps1` 做 Windows 合成器级别透明验证。

---

## 11. 设计取舍

| 取舍 | 原因 |
|---|---|
| 持久 PetWorld | 坐姿/自动行为不能因场景切换被销毁 |
| 2D y-sort 舞台 | 当前素材是方向 sprite，先保证稳定和可读 |
| 保留旧 SceneManager | 不推翻已稳定的静态场景代码，留作参考/回归 |
| 不伪造坐姿 | 没有坐姿素材，只保留锚点和拒绝路径 |
| 用 JSON 配置行为/动画 | 避免把动画帧和状态机硬编码在脚本里 |
| 用 Tween 做家具出现/移动 | 当前没有专门的搬运帧，先用可替换的表现 |
| 不引入第三方插件 | 当前需求用 Godot 原生节点和 JSON 足够 |
