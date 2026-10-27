# 维护与贡献

## 本地开发

1. 克隆仓库，在 Godot 中打开 `deskpet/project.godot` 完成资源导入。
2. 设置 `GODOT_EXE` 指向本机 Godot 可执行文件，运行 `deskpet/tools/run_preview.ps1`。
3. 涉及素材重建时，安装 `requirements.txt` 并运行对应 Python 工具。

配置入口、模块边界见 `deskpet/docs/ARCHITECTURE.md`。素材和行为保持独立；不要把电脑环境路径、令牌、SSH 密钥或构建缓存提交到仓库。

## 提交流程

- 从最新 `main` 建立 `feat/…` 或 `fix/…` 分支，围绕一个明确问题提交。
- 行为、配置或运行素材变化后运行 `deskpet/tools/run_tests.ps1`。
- 视觉变化另做预览检查，检查透明背景、方向、缩放和锚点。
- 使用 `git diff --check` 与 `git diff --cached` 检查提交范围；同步更新相关说明。
- 推送分支后使用 Pull Request 说明变更、验证结果与已知限制。

## 发布约定（待建立发布流水线）

采用 `v主版本.次版本.修订号` 标签，预发布可用 `-alpha.1` 等后缀。
发布前完成安装、卸载、覆盖升级和用户数据保留验证；安装包作为 GitHub Release 附件发布，不提交到源码历史。
版本检查与自动更新尚未实现，不能把源码提交当作已发布安装版本。
