# Personality DeskPet

个性化桌面宠物软件，采用 Godot 4 与 GDScript，目前为 Windows 桌面原型。
目标是支持个性化角色和行为、安装包下载与安装、软件更新。

## 当前功能

- 透明、无边框、置顶的桌面宠物窗口。
- 八方向站立和行走、正面待机动画。
- 独立的桌子、椅子与电脑家具。
- 手动移动、摸头交互、右键动作菜单和 JSON 配置。

完整坐下/起身动作、用户设置界面、安装包与软件更新机制尚待实现。

## 运行

克隆仓库，用 Godot 打开 `deskpet/project.godot`，完成资源导入后按 **F5** 运行主场景。
现有工程验证版本为 Godot 4.7.2，使用 GL Compatibility 渲染器，无需 Python。

也可以在仓库根目录使用命令行：

```powershell
$env:GODOT_EXE = '你的Godot目录/Godot可执行文件.exe'
& $env:GODOT_EXE --editor --path ./deskpet
# 普通预览
& $env:GODOT_EXE --path ./deskpet
# 透明桌面模式
& $env:GODOT_EXE --path ./deskpet -- --desktop-mode
```

WASD / 方向键移动；右键角色打开动作菜单；左键点击摸头；拖动移动窗口。

## 仓库内容

仅维护软件运行所需工程及最少的仓库说明：

| 路径 | 内容 |
|---|---|
| `deskpet/project.godot` | Godot 工程入口 |
| `deskpet/scripts/` | 运行代码 |
| `deskpet/scenes/` | 场景与节点结构 |
| `deskpet/config/` | 运行配置 |
| `deskpet/assets/` | 运行素材及资源导入设置 |

原始素材、素材编辑与生成工具、测试代码、开发截图和文档、缓存及备份不纳入版本控制。
这些开发文件可保留在维护者本地；克隆仓库无需这些文件即可运行软件。

维护者：Azugawa。后续安装包计划发布至 [GitHub Releases](https://github.com/Azugawa/Personality_DeskPet/releases)，目前尚无正式安装版本。
