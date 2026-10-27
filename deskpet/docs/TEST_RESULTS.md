# 测试与验证结果（持久化桌面宠物阶段）

测试时间：2026-10-27（Asia/Shanghai）
测试机器：Windows，NVIDIA GeForce RTX 4060 Laptop GPU，1920×1080
引擎：Godot `4.7.2.stable.official.ed1daf0bf`，GL Compatibility

---

## 1. 结论

| 验收项 | 结果 |
|---|---|
| 项目导入 / 编辑器启动 | ✅ 无脚本解析错误 |
| 主场景与持久 PetWorld | ✅ |
| 八方向站立 | ✅ 8 张透明图 |
| 正面待机 | ✅ 5 帧 |
| 八方向走路 | ✅ 32 帧（8×4） |
| 16 个角色 clip | ✅ |
| 手动移动 / 摸头 / 回 idle | ✅ |
| 可选自动行为（默认关闭）与手动暂停 | ✅ |
| 手动优先级 | ✅ 自动请求在手动暂停/忙碌时被拒绝 |
| 独立家具显示/隐藏/移动/方向 | ✅ 椅子/木桌/电脑桌 |
| 家具锚点 | ✅ seat / work_surface / screen |
| 预览窗口属性 | ✅ 不透明、有边框、不置顶 |
| 桌面透明/无边框/置顶 | ✅ 视口四角 alpha 0.000 |
| Windows 合成器透明 | ✅ 洋红背景可见比例 0.8444 |
| 原图 SHA-256 未变 | ✅ |
| 自动测试 | ✅ **147 / 147 通过，退出码 0** |

**自动测试结果：**

```text
=== PET_TEST_RESULT: PASS (147 checks) ===
```

> 旧的 176 项静态 SceneView 测试仍保留在 `tests/integration_tests.gd` 作为历史参考，
> 但当前 `tests/test_runner.tscn` 已切换到持久化运行时测试。

---

## 2. 命令与结果

### 2.1 导入 / 解析检查

```powershell
E:\Godot.exe\Godot_v4.7.2-stable_win64_console.exe `
  --headless --import --path E:\DeskPet\deskpet

E:\Godot.exe\Godot_v4.7.2-stable_win64_console.exe `
  --headless --editor --path E:\DeskPet\deskpet --quit
```

结果：69 张 RGBA 素材重新导入，无脚本解析错误。

### 2.2 无头集成测试

```powershell
E:\Godot.exe\Godot_v4.7.2-stable_win64_console.exe `
  --headless --path E:\DeskPet\deskpet res://tests/test_runner.tscn
```

最终输出：

```text
=== PET_TEST_RESULT: PASS (147 checks) ===
```

退出码 0。

覆盖范围：

- Main / PetWorld 初始化；
- 8 方向静态图、5 帧待机、32 帧走路；
- 16 个 clip 的加载；
- CharacterAnimator 最近邻、AnimatedSprite2D 可见性；
- 方向向量 → 视觉方向映射；
- 左键点击角色 → 摸头请求；
- 手动摸头、interact → idle；
- 手动走路、走路帧推进、目标到达、回 idle；
- 手动暂停使自动行为不可用；
- 自动 walk 请求在暂停时被拒绝；
- sit/stand 在缺素材时安全拒绝；
- 右键菜单节点、打开/关闭；
- activity 菜单项（待机/休息/玩电脑）与“坐姿待补”标记；
- 休息 activity 的家具缓现、走到椅子接近点、缺坐姿时安全停止；
- 家具独立显示/隐藏/移动/方向；
- 三种家具的交互锚点；
- 椅子/木桌/电脑桌的独立节点关系；
- 家具阴影；
- 运行时 InputMap actions；
- 预览窗口属性。

### 2.3 预期警告

测试会输出以下**预期警告**，不是失败：

```text
WARNING: [ActionStateMachine] Rejected 'sit': missing authored sit pose; structure reserved
WARNING: [ActionStateMachine] Rejected 'stand': character is not seated
```

这是“没有坐姿素材时不伪造坐姿”的验证。

### 2.4 自动行为模式

正常桌面宠物逻辑是**保持待机**，所以 `config/behavior.json` 的
`auto_enabled` 默认是 `false`。

测试验证：

- 默认关闭；
- 可通过 `set_auto_enabled(true)` / `Tab` 开启；
- 再次关闭后不会覆盖右键动作或手动操作。

在显式开启可选的 `auto_enabled` 模式后，固定帧率运行曾观察到：

```text
[PetWorld] state: idle -> walk
[PetWorld] action_started: walk (auto)
[PetWorld] action_finished: walk (auto)
[PetWorld] state: walk -> idle
```

默认配置不会主动走开。

---

## 3. 视觉截图

测试命令：

```powershell
E:\Godot.exe\Godot_v4.7.2-stable_win64_console.exe `
  --path E:\DeskPet\deskpet res://tests/capture_pet.tscn
```

输出：

- [pet_default.png](screenshots/pet_default.png)
- [pet_walking.png](screenshots/pet_walking.png)
- [pet_computer.png](screenshots/pet_computer.png)
- [pet_direction.png](screenshots/pet_direction.png)
- [pet_desktop.png](screenshots/pet_desktop.png)

桌面探针：

```text
[WindowController] mode=desktop transparent=true borderless=true always_on_top=true
[CapturePet] desktop probe: transparent=true borderless=true always_on_top=true corner_alpha=0.000
```

说明：

- 当前截图使用 300 px 高角色和 2D y-sort 舞台；
- 椅子、木桌、电脑桌为独立透明贴图；
- 桌面预览图背景为透明，查看器白色只是显示效果；
- 洋红背景仅用于合成器验证，不是项目素材。

---

## 4. Windows 合成器透明验证

```powershell
.\tools\verify_desktop_transparency.ps1
```

实际输出：

```text
SCREEN_BOUNDS={X=0,Y=0,Width=1920,Height=1080}
WINDOW_RECT=640,150,640,720
CORNERS=(255,0,255) (255,0,255) (255,0,255) (255,0,255)
MAGENTA_SAMPLES=1520/1800 RATIO=0.8444
RESULT=PASS (magenta desktop backdrop is visible through transparent window areas)
```

说明：

- 四角为洋红，说明透明区域确实透出了后方窗口；
- 84.33% 采样点为洋红，其余为角色/家具/阴影；
- 透明、无边框、置顶在本机实际生效。

验证图：[desktop_os_capture.png](screenshots/desktop_os_capture.png)

---

## 5. 素材完整性

- 原始 `E:\DeskPet\Spirit\人物图_透明.png` 未修改；
- SHA-256：
  `deca4a6b53ebd2f7f60128e14bc29930c616416e932b13ce5cab49a8bb61c8dc`
- 项目内旧 fallback `character_full.png` 仍是同一文件的逐字节副本；
- 新增运行素材由白底 contact sheet 生成，原始 `E:\DeskPet\素材\*.png` 未修改；
- `assets/sprite_manifest.json` 记录来源、源 SHA-256、裁切 bbox、canvas 和锚点；
- 69 张运行素材均为 RGBA，透明角通过校验。

---

## 6. 尚未验证 / 需要手动检查

以下项目不能仅靠无头测试证明：

- 八方向之间的视觉切换是否自然；
- 待机/走路循环是否存在肉眼可见的跳帧或脚底抖动；
- 300 px 角色与当前 640×720 窗口的整体比例是否合适；
- 家具与角色重叠时的遮挡是否符合预期；
- 左键点击角色的命中范围、按住拖动窗口的手感；
- 透明区域鼠标穿透（**尚未实现**）；
- 不同 Windows DPI/多显示器组合；
- 右键菜单、托盘、开机启动；
- Windows `.exe` 导出与干净机器运行；
- 长时间运行的内存/显存占用；
- 其他显卡/驱动的透明窗口兼容性。

---

## 7. 透明窗口异常诊断

1. 确认启动参数包含 `-- --desktop-mode`。
2. 日志应出现：

```text
[WindowController] mode=desktop transparent=true borderless=true always_on_top=true
[Main] Ready. desktop_mode=true
```

3. 确认没有使用 `--headless`。
4. 运行 `.\tools\verify_desktop_transparency.ps1`：
   - `RESULT=PASS`：合成器透明正常；
   - 四角非洋红：窗口没有真正透明或背景窗口被覆盖；
   - 全屏洋红：置顶顺序问题。

5. 环境因素：
   - 远程桌面、虚拟机、关闭 DWM 的系统可能不支持 per-pixel transparency；
   - 更新显卡驱动；
   - 确认没有全屏独占程序覆盖桌面。

---

## 8. 测试工具

| 工具 | 用途 |
|---|---|
| `tools/run_tests.ps1` | 无头持久化宠物测试 |
| `tools/capture_screenshots.ps1` | 生成预览/桌面截图与视口透明探针 |
| `tools/verify_desktop_transparency.ps1` | Windows 合成器透明验证 |
| `tools/run_preview.ps1` | 预览/桌面模式/编辑器 |
| `tools/prepare_sprite_sheets.py` | 白底 sheet → RGBA 运行素材 |
