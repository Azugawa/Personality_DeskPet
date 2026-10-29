# 素材与构建目录

- `asset_sources/spirit/animations/originals/`：原始待机、行走、趴桌、电脑与用户提供素材。
- `asset_sources/spirit/animations/physics/`：提起、甩飞、趴地、站立和起身原始图，供离线切帧使用。
- `asset_sources/spirit/animations/headpat/`：摸头创作源图。
- `asset_sources/spirit/ui/`：UI 原始素材及光标源图。
- `deskpet/assets/character/spirit/`：实际运行帧；物理动画在 `physics/held、flight、landing、prone、getup` 下细分。
- `deskpet/assets/ui/icons、cursors、panels/`：运行图标、光标、菜单与弹窗。
- `deskpet/assets/fonts/`：字体与许可证，必须随项目保留。
- `deskpet/packaging/`：打包、增量更新、离线素材构建和可重复执行的验证脚本。
- `build/installer/`：当前正式安装包、update.json 及其引用的增量块。
- `build/windows/`：当前导出程序；`build/installed-smoke/` 是本机实际安装，不应作为临时文件删除。
- `build/tooling/`：编译工具和已解压导出模板。

修改物理源图后，运行 Godot `--headless --path deskpet --script res://packaging/bake_physics.gd`，再进行编辑器资源导入和打包。运行时不再做去背景或连通区域切分。

清理记录见 `deskpet/packaging/CLEANUP.md`。历史原始素材目录（素材、Spirit、charpipe 等）保留在本机，未擅自删除无法确认用途的创作文件。测试代码保留，测试输出图片和过期安装包已清理。
