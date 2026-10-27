# DeskPet — 持久化 2D/2.5D 像素桌面宠物

当前阶段已经把原来的静态 2.5D 展示框架升级为**一次创建、持续存在的 PetWorld**：

- 角色：八方向站立 + 八方向四帧走路 + 正面五帧待机。
- 行为：默认保持待机；右键选择休息/玩电脑。可选自动看/走由 `Tab` 开启，默认关闭。
- 状态机：统一管理 idle / walk / interact 和手动命令优先级。
- 家具：椅子、木桌、电脑桌各自是独立节点，可显示、隐藏、移动、切换方向。
- 窗口：保留透明、无边框、置顶的 `--desktop-mode` 能力。
- 兼容：保留旧 `SceneManager` / 静态伪 3D 场景脚本作为历史参考，但默认运行入口已经不再是它。

验证环境：

- Windows
- Godot **4.7.2.stable.official**（GL Compatibility）
- 2026-10-27：**147 项无头测试通过**
- Windows 透明合成脚本实测通过（洋红背景可见比例 0.8444）
- 桌面模式视口四角 alpha = 0.000

---

## 一、快速启动

```powershell
# 编辑器
E:\Godot.exe\Godot_v4.7.2-stable_win64.exe --editor --path E:\DeskPet\deskpet

# 普通预览（不透明、显示调试面板）
E:\Godot.exe\Godot_v4.7.2-stable_win64.exe --path E:\DeskPet\deskpet

# 桌面透明模式（透明 + 无边框 + 置顶）
E:\Godot.exe\Godot_v4.7.2-stable_win64.exe --path E:\DeskPet\deskpet -- --desktop-mode
```

PowerShell 工具：

```powershell
cd E:\DeskPet\deskpet
.\tools\run_preview.ps1
.\tools\run_preview.ps1 -DesktopMode
.\tools\run_tests.ps1
.\tools\capture_screenshots.ps1
.\tools\verify_desktop_transparency.ps1
```

---

## 二、操作

| 操作 | 行为 |
|---|---|
| `WASD` / 方向键 | 手动移动；手动命令优先于自动行为 |
| 左键点击角色 | 摸头交互（当前为轻量身体弹跳占位） |
| 右键角色 | 打开动作菜单：待机 / 休息 / 玩电脑 |
| 按住左键拖动 | 拖动整个窗口 |
| `Tab` | 开启/关闭可选自动看/走（默认关闭） |
| `I` | 回到待机 |
| `C` | 显示/隐藏椅子 |
| `G` | 显示/隐藏木桌 |
| `V` | 显示/隐藏电脑桌 |
| `H` | 摸头 |
| `Z` | 坐下/起身请求（素材未提供，会安全拒绝） |
| `F1` | 显示/隐藏调试面板 |

默认情况下不会自动走动，只播放待机动画。开启可选自动模式后，手动操作会让它暂停 4 秒。自动行为只在角色空闲、没有排队命令时生效，不会覆盖手动命令。

---

## 三、当前目录

```text
deskpet/
├── project.godot
├── config/
│   ├── app.json
│   ├── behavior.json
│   ├── activities.json
│   ├── animations/spirit.json
│   ├── characters/spirit.json
│   ├── props/{chair,desk,computer}.json
│   ├── scenes/                         # 旧静态场景配置，默认运行时不启动
│   ├── visual/pseudo3d.json            # 旧 2.5D 视觉规范，保留参考
│   └── world/default.json              # 当前持久化世界
├── scenes/
│   ├── main/{main.tscn,debug_overlay.tscn}
│   ├── world/pet_world.tscn
│   ├── character/character.tscn
│   ├── props/furniture.tscn
│   ├── props/{prop.tscn,pseudo3d_prop.tscn}   # 旧调试道具
│   └── environments/scene_view.tscn           # 旧静态场景
├── scripts/
│   ├── core/{main,config_loader,window_controller,scene_manager}.gd
│   ├── world/pet_world.gd
│   ├── character/{character,character_animator}.gd
│   ├── behavior/{action_state_machine,behavior_brain,pet_activity_controller}.gd
│   ├── input/pet_input.gd
│   ├── ui/pet_menu.gd
│   ├── props/{furniture_manager,furniture_view}.gd
│   ├── props/{prop_view,pseudo3d_prop_view}.gd # 旧实现
│   ├── scene_management/{scene_view,background_view}.gd
│   ├── visual/{pseudo3d,shadow_view,stage_guide}.gd
│   ├── events/event_bus.gd
│   └── ui/debug_overlay.gd
├── assets/
│   ├── sprite_manifest.json
│   ├── character/spirit/
│   │   ├── character_full.png          # 旧单图 fallback
│   │   ├── directions/                 # 8 张透明站立图
│   │   ├── idle/                       # 5 张正面待机帧
│   │   └── walk/                       # 8×4 张透明走路帧
│   └── props/
│       ├── chair/                      # 8 个方向
│       ├── desk/                       # 8 个方向
│       └── computer/                   # 8 个方向
├── tests/
│   ├── test_runner.tscn
│   ├── pet_tests.gd                    # 当前 147 项验收测试
│   ├── capture_pet.tscn/.gd            # 预览/桌面截图
│   └── integration_tests.gd            # 旧静态场景测试，保留参考
├── tools/
│   ├── prepare_sprite_sheets.py        # 白底 contact sheet → RGBA 运行素材
│   ├── run_preview.ps1
│   ├── run_tests.ps1
│   ├── capture_screenshots.ps1
│   └── verify_desktop_transparency.ps1
└── docs/
```

---

## 四、架构

```text
Main
├── BackdropLayer（预览背景；桌面模式隐藏）
├── PetWorld（持久化）
│   ├── WorldSort (Node2D, y_sort_enabled)
│   │   ├── Character
│   │   └── Furniture_*（独立节点）
│   ├── FurnitureManager
│   ├── StateMachine
│   ├── BehaviorBrain
│   ├── ActivityController
│   ├── PetInput
│   └── PetMenu（CanvasLayer，右键菜单）
└── DebugOverlay（CanvasLayer，桌面模式隐藏）
```

### 1. 角色表现

- `Character`：位置、脚底锚点、方向、阴影、状态名。
- `CharacterAnimator`：加载 `config/animations/spirit.json`，建立 16 个 `SpriteFrames` 动画。
- `AnimatedSprite2D`：负责图片帧。
- 旧 `FullBodySprite` 保留为 fallback，默认不显示。
- 12 个 provisional 部件仍不参与运行；`PartsRoot` 为未来换装预留。

### 2. 状态机与自动行为

`ActionStateMachine` 是动作切换的唯一权威：

- 行为状态：`idle`、`walk`、`interact`。
- 动作：`walk_to`、`walk_manual`、`head_pat`、`furniture_toggle`，以及保留的 `sit` / `stand`。
- 手动命令优先；自动命令不能覆盖忙碌中的手动动作。
- 手动操作会设置 4 秒自动暂停。
- 不可中断动作具有排队结构；当前可直接执行的 walk/interact 是可中断的。
- `sit` / `stand` 在缺少坐姿素材时会明确拒绝，而不是假装完成。

`BehaviorBrain` 是**默认关闭的可选模块**：

- 默认 `auto_enabled=false`，角色保持待机。
- 按 `Tab` 开启后，空闲 3–6 秒才按权重选择“换个方向”或“短距离走动”。
- 仅在 `can_auto_act()` 为真时提出。
- 不直接修改角色 transform、动画或家具。
- 右键动作和手动操作始终优先。

### 3. 家具

`FurnitureManager` 创建独立 `FurnitureView`：

- 每个家具都有独立的位置、可见性、8 方向贴图和阴影。
- 椅子提供 `seat` 锚点。
- 木桌提供 `work_surface` 锚点。
- 电脑桌提供 `work_surface` 和 `screen` 锚点。
- 家具移动、显示/隐藏由 manager 控制，不修改角色内部状态。
- `FurnitureView.set_visible_animated()` 提供淡入/缩放出现动画。
- 木桌和电脑桌共用 `workstation` 互斥组；显示电脑桌会隐藏木桌，反之亦然。

### 右键动作

右键角色会打开由 `config/activities.json` 驱动的动作菜单：

- **待机**：回到待机。
- **休息**：让木桌和椅子**缓慢出现**，角色走到椅子前的接近点。
- **玩电脑**：让电脑桌和椅子缓慢出现，木桌收起，角色走到椅子前。

`rest` / `computer` 目前会在到达椅子后停下并等待坐姿帧，因为
`sit_front` 还没有制作。菜单会显示“坐姿待补”。这不会伪造坐姿，但已经验证了
“动作入口 → 家具出现 → 走到目标 → 等待坐姿”的流程。动作细节确认后，
只需在 `PetActivityController` 的完成点接入坐下/起身帧和锚点。

### 4. 输入与窗口

- `PetInput` 把按键/鼠标转换为状态机命令。
- 运行时注册 `pet_move_*` InputMap actions。
- 左键点击角色：摸头；右键角色：打开动作菜单；按住拖动：移动窗口。
- 透明、无边框、置顶仍由 `WindowController` 负责。
- 尚未实现鼠标穿透和像素级点击遮罩。

### 5. 旧静态场景

`SceneManager`、`SceneView`、`Pseudo3DPropView` 和 `config/scenes/*` 保留下来作为历史实现和视觉参考，但 `Main` 默认不再启动它们。这样可以避免“切场景销毁角色”的旧生命周期影响持久化桌宠。

---

## 五、素材处理

白底/浅底 contact sheets 不能直接导入运行：

- 带标签；
- 不是严格等宽帧；
- 无 alpha；
- 白色外缘会与桌面/深色背景混在一起。

[tools/prepare_sprite_sheets.py](tools/prepare_sprite_sheets.py) 做确定性处理：

1. 找到大前景连通块；
2. 裁切每个角色/家具；
3. 从裁切边缘 flood-fill 背景；
4. 去除暴露在外的浅色纸边；
5. 统一放入透明 canvas，锚点为底边中心；
6. 输出 69 张 RGBA PNG 和 [assets/sprite_manifest.json](assets/sprite_manifest.json)。

原始文件在 `E:\DeskPet\素材`，从不覆盖。

当前生成结果：

| 类型 | 数量 | 来源 |
|---|---:|---|
| 八方向站立 | 8 | `八方向图.png` |
| 正面待机帧 | 5 | `idle_breath.png` |
| 八方向走路帧 | 32 | `人物走路八方向图.png` |
| 椅子方向 | 8 | `桌子和椅子八方向图.png` |
| 木桌方向 | 8 | `桌子八方向_坐姿参考/*.png`，根据 `坐姿定格.png` 生成 |
| 电脑桌方向 | 8 | `电脑八方向图.png` |

角色显示目标高度 300 px；家具按配置分别缩放。所有纹理使用最近邻过滤。

木桌的新透明原图由内置 image_gen 生成，保存于 `素材/桌子八方向_坐姿参考/`；
构建脚本以最近邻缩小并对齐到底部中心，输出仍为 160×160。
生成提示词见该目录的 `generation.json`，旧版桌图备份于 `素材/桌子八方向_旧版备份/`。

---

## 六、配置入口

| 文件 | 作用 |
|---|---|
| `config/world/default.json` | 角色出生点、初始家具、行为配置路径 |
| `config/animations/spirit.json` | 16 个动画的方向、帧、fps、canvas、缩放 |
| `config/characters/spirit.json` | 角色 profile、方向限制、缺失状态、rig 参考 |
| `config/props/*.json` | 家具方向贴图、缩放、锚点、阴影、交互标记 |
| `config/behavior.json` | 空闲间隔、权重、移动速度、边界、手动暂停 |
| `config/app.json` | 窗口尺寸、预览背景、桌面位置、调试面板 |

---

## 七、测试与验证

```powershell
E:\Godot.exe\Godot_v4.7.2-stable_win64_console.exe --headless --path E:\DeskPet\deskpet res://tests/test_runner.tscn
```

最近结果：

```text
=== PET_TEST_RESULT: PASS (147 checks) ===
```

覆盖：

- 主场景和 PetWorld 初始化；
- 69 个 RGBA 素材存在、八方向/帧路径；
- 16 个动画、五帧待机、四帧走路；
- 锁定方向与移动方向的映射；
- 手动摸头、手动走路、动作结束回 idle；
- 自动行为暂停、自动请求被拒绝；
- 家具独立显示/隐藏/移动/方向；
- 椅子的 seat、木桌的 work_surface、电脑的 screen 锚点；
- 预览窗口属性；
- 原图 SHA-256 未变。

截图：

- [pet_default.png](docs/screenshots/pet_default.png)
- [pet_walking.png](docs/screenshots/pet_walking.png)
- [pet_computer.png](docs/screenshots/pet_computer.png)
- [pet_direction.png](docs/screenshots/pet_direction.png)
- [pet_desktop.png](docs/screenshots/pet_desktop.png)
- [desktop_os_capture.png](docs/screenshots/desktop_os_capture.png)

桌面透明模式实际验证：

```text
WINDOW_RECT=640,150,640,720
CORNERS=(255,0,255) (255,0,255) (255,0,255) (255,0,255)
MAGENTA_SAMPLES=1520/1800 RATIO=0.8444
RESULT=PASS
```

---

## 八、已知限制

- 没有坐下、起身、趴桌、办公、搬运、摸头的**专门美术帧**；相关命令会安全拒绝。状态机/家具锚点已预留。
- 没有鼠标穿透、像素级命中遮罩、右键菜单、托盘、开机启动。
- 当前为固定 640×720 窗口；窗口位置不持久化。
- 当前默认是 2D y-sort 舞台，旧 2.5D 斜投影规范只作为历史参考保留；尚未实现“按场景切换空间视角”。
- 家具出现/收起目前是透明度和缩放动画，没有搬运动画。
- 未验证多显示器、DPI、Windows 导出包。
- 旧 `SceneManager` 静态场景和旧测试仍保留，但默认运行路径不依赖它们；后续可在确认后清理。
- 测试会输出两条预期警告：`sit` 缺素材、`stand` 未坐下。它们不是测试失败。

---

## 九、下一步建议

1. 补齐坐姿/趴桌/办公/搬运动作，按 `sit_down` / `sit` / `stand_up` 安全点接入。
2. 将当前 y-sort 舞台扩展为每场景可配置的 2D / 2.5D 投影。
3. 增加鼠标点击穿透和像素级命中遮罩。
4. 把 `FurnitureManager` 的动作与角色搬运流程连接，使用手部锚点。
5. 确认 `character_assets` 的 12 个 provisional 部件是否用于换装；如果使用，保持当前状态机不变，只替换表现层。
6. 建立 Windows 导出预设，验证干净机器运行。
