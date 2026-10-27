# Personality DeskPet

个性化桌面宠物软件。项目目标是让用户通过安装包安装桌宠，自定义角色、动作和家具，并能便捷地获取软件更新。

当前处于 Windows 桌面原型阶段，核心采用 Godot 4 + GDScript，素材工具采用 Python。
维护者：Azugawa（2812656625@qq.com）。

## 当前能力

- 持久化桌宠世界、透明无边框置顶窗口。
- 八方向站立、行走和正面待机动画。
- 独立的椅子、木桌、电脑桌，支持方向切换与显隐。
- 手动移动、摸头交互、右键动作菜单。
- JSON 驱动的角色、动画、行为和家具配置。
- 147 项 Godot 无头验收检查。

当前尚未提供可下载的正式安装包，也未实现自动更新。休息/玩电脑流程目前停在椅子接近点，完整坐下、起身动画仍待制作。

## 获取与运行

```powershell
git clone git@github.com:Azugawa/Personality_DeskPet.git
cd Personality_DeskPet
$env:GODOT_EXE = '你的Godot目录/Godot控制台可执行文件.exe'
& $env:GODOT_EXE --editor --path ./deskpet
```

现有工程记录的验证版本为 Godot 4.7.2，使用 GL Compatibility 渲染器。
无需 Python 即可运行已提交的桌宠素材。

```powershell
# 普通预览
./deskpet/tools/run_preview.ps1
# 透明桌面模式
./deskpet/tools/run_preview.ps1 -DesktopMode
# 验收测试
./deskpet/tools/run_tests.ps1
```

首次运行前用 Godot 编辑器打开工程完成资源导入。详细操作见 [运行说明](deskpet/README.md)。

## 项目结构

| 路径 | 内容 |
|---|---|
| `deskpet/` | Godot 工程：运行代码、场景、配置、素材、测试与工具 |
| `素材/` | 重建运行素材所需原图与生成提示词 |
| `Spirit/` | 原始角色参考图 |
| `charpipe/`、`build_assets.py` | 人物分割、关节、部件导出流水线 |
| `character_assets/config/` | 可编辑的分割与关节元数据 |
| `docs/` | 产品路线、贡献流程和历史素材流水线说明 |

不入库：Godot 缓存、Python 环境与缓存、日志、旧版备份、人物流水线中间产物、安装包和构建输出。
已提交运行素材和必要源图，确保克隆后可运行，也能重新构建。

## 素材开发

```powershell
python -m pip install -r requirements.txt
python deskpet/tools/prepare_sprite_sheets.py
```

人物分层流程见 [素材流水线](docs/CHARACTER_PIPELINE.md)。该文档中的绝对路径是原开发机示例，请替换为自己的克隆目录。

## 后续方向

优先完善桌宠交互与个性化设置，再建立 Windows 导出、安装与卸载、GitHub Releases 发布流程，最后加入版本检查与安全更新机制。
具体阶段与验收标准见 [开发路线](docs/ROADMAP.md)，维护流程见 [贡献说明](CONTRIBUTING.md)，运行架构见 [架构说明](deskpet/docs/ARCHITECTURE.md)。

未来安装包将通过本仓库的 [Releases](https://github.com/Azugawa/Personality_DeskPet/releases) 发布；当前尚无正式版本。
