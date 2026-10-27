# 木桌八方向替换（2026-10-27）

参考 `素材/坐姿定格.png` 的暖棕长方桌、厚桌沿、方形直腿和深色像素轮廓。
八个方向由内置 image_gen 分别生成，原图和完整提示词保存于
`素材/桌子八方向_坐姿参考/`。左侧视图另外参考右侧图修正宽度。

运行图片为 `assets/props/desk/*.png`，保持八个文件名、160×160 RGBA 画布、
底部中心锚点及 1.14 显示缩放。正背面宽 144 px，侧面宽 72 px；
最近邻等比缩放，保留生成图 alpha。以 alpha >= 128 的实体轮廓确定裁切范围，
避免极淡的生成残影影响地面锚点。后方斜视图按投影长边方向映射。

桌面交互点随新画面调整为 work_surface_uv=[0.5,0.67]，
lean_anchor_uv=[0.5,0.72]。源图和旧桌椅合图保留不变。

`tools/prepare_sprite_sheets.py` 的 `build_reference_desk()` 可重复构建这些素材，
完整构建不会再恢复旧桌图。旧运行图片、桌子配置和素材清单备份于
`素材/桌子八方向_旧版备份/`。

本次核对的架构：根目录 charpipe 是人物分割、关节、重组与检查流水线；
deskpet 是 Godot 运行时，Main 创建持久 PetWorld；FurnitureManager 管理
独立 FurnitureView；JSON profile 决定方向图片、缩放、阴影和锚点；
行为由 ActionStateMachine 与 ActivityController 调度。此次无需改变行为脚本。
