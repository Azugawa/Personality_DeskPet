# Windows 打包与更新

主工程：deskpet。Windows 编译工具在 E:/DeskPet/build/tooling，不提交 Git。

1. 安装与编辑器版本一致的 Godot 导出模板。
2. 在仓库根执行：`./deskpet/packaging/build.ps1`。
3. 输出位于 `build/installer`：安装程序及 `update.json`。
4. 在 Azugawa/Personality_DeskPet 创建正式 GitHub Release，标签为 `v0.1.0`，上传两个文件。更新源读取 latest 正式发布，预发布不推送给普通用户。
5. 新版本同时修改 update_service.gd 的 VERSION、export_presets.cfg 的版本信息，并将新版本传给 build.ps1 的 Version 参数。不要重复使用旧版本号。

无需自行租服务器，公开 GitHub Releases 即可。仓库私有时公开客户端无法匿名下载，需另设公开发行仓库并同步修改更新地址。网络无法访问 GitHub 时会提示失败，不影响当前版本。

更新步骤：检查 → 用户确认 → HTTPS 下载 → SHA-256 验证 → 启动交互式安装器 → 退出桌宠。覆盖安装沿用固定 AppId，用户数据在 Godot user:// 下，不作为卸载文件删除。

SHA-256 用于完整性校验，不能替代代码签名。当前安装包没有发行者代码签名，正式分发时可购置签名证书；勿将证书或 API 密钥提交仓库。

未来提醒、对话、换装、游戏空间入口在 FeatureServices 中预留，尚未实现。模型密钥应保存在用户配置或后端，不能嵌入安装包。

验证：packaging/smoke_transitions.gd 检查六个有向活动切换。原 tests/sequence_review.gd 记录历史四菜单流程，其 lie 命令不再适用于三菜单版本。
