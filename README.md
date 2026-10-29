# 何爪爪

Godot 4.7.2 桌面宠物，当前提供 Windows x64 安装包。

- 透明置顶窗口、身体拖动、头部点击摸头。
- 待机、趴桌、玩电脑，以及原地行走和倒放离场。
- 自定义像素菜单、中文像素字体、系统托盘显示/隐藏。
- 安装与卸载、GitHub Releases 更新检查和下载校验。

主工程位于 `deskpet/`，源素材备份位于 `asset_sources/`。
用 Godot 打开 `deskpet/project.godot`；桌面模式启动参数为 `-- --desktop-mode`。

打包：`deskpet/packaging/build.ps1`。需要 Godot 4.7.2 Windows 导出模板和 Inno Setup。
详细步骤见 [打包说明](deskpet/packaging/README.md)。

生成的 `build/installer/DeskPet-Setup-0.2.9.exe` 是完整独立安装包，可重命名后通过网盘、U盘或聊天工具直接分享。接收者不需要 GitHub、Godot 或 Python。
正式更新通过 GitHub Release 分发，直连失败时尝试配置的加速网关。兼容版本支持分块增量资源更新；旧版首次迁移仍使用安装包。

提醒、模型对话、换装和游戏空间目前仅预留接口。
字体及其许可证位于 `deskpet/assets/fonts/`。

素材分类和清理范围见 [素材目录](ASSETS.md)。物理动画预先处理，启动时直接加载成品帧。
