# 资产识别、生成与缺失清单

生成依据：实际扫描 `E:\DeskPet`、读取 source PNG 的尺寸/alpha/哈希，并检查
`assets/sprite_manifest.json` 与 Godot 运行结果。**原始素材没有被修改、移动或重命名。**

---

## 1. 角色源文件

| 项目 | 结果 |
|---|---|
| 原始路径 | `E:\DeskPet\Spirit\人物图_透明.png` |
| 格式 | PNG，RGBA，2048×2048 |
| 透明通道 | 有，含部分透明像素 |
| 人物实际包围盒 | x=406, y=86, w=1231, h=1871 |
| SHA-256 | `deca4a6b53ebd2f7f60128e14bc29930c616416e932b13ce5cab49a8bb61c8dc` |
| Godot fallback | `assets/character/spirit/character_full.png`，逐字节相同 |

当前运行时优先使用八方向/走路/待机帧；这张 2048×2048 单图只作为 fallback 和未来参考。

---

## 2. 新运行素材

### 2.1 来源 contact sheets

原始文件仍是白底/浅底的展示板，不直接导入运行：

| 源文件 | 尺寸 | 格式 | 用途 |
|---|---:|---|---|
| `E:\DeskPet\素材\八方向图.png` | 1254×1254 | RGB，无 alpha | 8 方向站立 |
| `E:\DeskPet\素材\人物走路八方向图.png` | 1536×1024 | RGB，无 alpha | 8 方向 × 4 帧走路 |
| `E:\DeskPet\素材\idle_breath.png` | 1763×554 | RGB，无 alpha | 正面 5 帧待机 |
| `E:\DeskPet\素材\桌子和椅子八方向图.png` | 1536×1024 | RGB，无 alpha | 椅子 8 方向 + 木桌 8 方向 |
| `E:\DeskPet\素材\电脑八方向图.png` | 1536×1024 | RGB，无 alpha | 电脑桌 8 方向 |

这些文件包含：
- 中文标题/帧标签；
- 非透明纸底；
- 不是严格等宽帧的排版；
- 角色/家具外缘的浅色纸边。

### 2.2 生成结果

[tools/prepare_sprite_sheets.py](../tools/prepare_sprite_sheets.py) 已生成 **69 张 RGBA PNG**：

| 输出 | 数量 | 单帧 canvas | 说明 |
|---|---:|---|---|
| `assets/character/spirit/directions/` | 8 | 256×384 | 站立，8 方向 |
| `assets/character/spirit/idle/` | 5 | 352×512 | 正面待机 |
| `assets/character/spirit/walk/` | 32 | 96×160 | 8 方向 × 4 帧 |
| `assets/props/chair/` | 8 | 120×160 | 椅子 8 方向 |
| `assets/props/desk/` | 8 | 160×160 | 木桌 8 方向 |
| `assets/props/computer/` | 8 | 224×256 | 电脑桌 8 方向 |

方向顺序：

```text
front, front_right, right, back_right,
back, back_left, left, front_left
```

视觉含义：

- `front`：面向镜头；
- `back`：背向镜头；
- 屏幕向上移动使用 `back`，向下移动使用 `front`；
- 对角方向按屏幕向量映射。

### 2.3 处理规则

脚本只做确定性准备：

1. 找到大前景连通块（排除标题文字）；
2. 裁切每个角色/家具；
3. 从裁切边缘 flood-fill 背景；
4. 只去除暴露在透明背景边缘的浅色纸边；
5. 把透明像素的 RGB 置黑，避免白色纸底在过滤/导入时渗入边缘（alpha despill）；
6. 保留被人物轮廓包围的白色衬衫/高光；
7. 以 alpha 底部中心为脚底/地面锚点；
8. 放入统一透明 canvas；
9. 写 manifest 并进行 RGBA/透明角校验。

没有重绘角色，没有改变像素比例，没有把原图缩放后覆盖源文件。

> 边缘 matte 已经清理了纸底、浅色暴露边和透明 RGB 的白色渗色；部分角色/家具
> 轮廓上仍能看到源图自带的约 1px 浅色像素。这是原画边缘，不是残留背景。
> 若需要完全统一的深色描边，必须人工重绘轮廓，不能仅靠去底自动完成。

### 2.4 显示比例

运行时按约 300 px 角色高度校准：

- 站立：canvas 256×384，scale ≈ 0.871；
- 待机：canvas 352×512，scale ≈ 0.606；
- 走路：canvas 96×160，scale ≈ 2.069；
- 家具：各自 profile 配置。

所有纹理使用最近邻过滤。

manifest：[assets/sprite_manifest.json](../assets/sprite_manifest.json)

---

## 3. 家具运行素材

| 家具 | 方向数 | 交互锚点 | 运行时缩放 | 阴影 |
|---|---:|---|---:|---|
| 木椅 | 8 | seat | 1.17 | ✅ |
| 木桌 | 8 | work_surface | 1.14 | ✅ |
| 电脑桌 | 8 | work_surface, screen | 0.95 | ✅ |

家具是独立 `FurnitureView` 节点，位置、可见性、方向、移动可分别控制。
电脑桌自身包含桌体，因此当前把它作为独立 workstation，与木桌二选一显示。

---

## 4. 旧的 provisional 部件

`character_assets/` 的 12 个部件仍是 `NEEDS_REVIEW`：

- 0 个人工确认；
- `character_assets/parts/` 和 `parts_cropped/` 为空；
- 只有 `parts_provisional/`；
- 当前运行时不加载这些部件。

它们现在作为**身体结构参考**保留，供未来分层换装或坐姿/搬运动作参考。
如果以后使用，应回到分割流水线人工确认，而不是直接接入运行。

---

## 5. 缺失素材

| 缺失项 | 当前替代 | 影响 |
|---|---|---|
| 坐姿帧 | 无 | `sit` 命令安全拒绝 |
| 起身帧 | 无 | `stand` 命令安全拒绝 |
| 趴桌帧 | 无 | 只能保留 work_surface 锚点 |
| 办公/打字帧 | 无 | 电脑桌只能显示，不能表现使用动作 |
| 搬运帧/手部挂载 | 无 | 家具只能 show/hide/tween |
| 专门摸头帧 | 无 | 使用轻微身体弹跳占位 |
| 行走之外的睡眠/伸懒腰等 | 无 | 自动行为暂只做 idle/look/walk |
| 房间背景 | 无 | 默认透明背景 |
| 鼠标穿透遮罩 | 无 | 透明区域不可穿透 |

缺失项不会被伪造。`sit` / `stand` 在自动测试中明确验证为安全拒绝。

---

## 6. 原始文件完整性

- 原始人物 PNG 未被修改；
- 新素材 contact sheets 未被修改；
- 所有运行素材都在 `deskpet/assets/` 下独立生成；
- 生成脚本可重复运行；
- 重构前备份：`E:\DeskPet_backups\DeskPet_backup_20261027_140833.zip`
  - SHA-256：`2CBE7228A4143668DD9D6EFA1650863EE9DE9E3702E66527170F13A84891E624`
- 重构后备份：`E:\DeskPet_backups\DeskPet_post_refactor_20261027_143120.zip`
  - SHA-256：`BF4098CED021F2348A9DD04DAD8200BD5F8A2180458F5D1539407E8A9B92EC25`
- 最终验证备份：`E:\DeskPet_backups\DeskPet_final_20261027_143235.zip`
  - SHA-256：`9ECE65B43D6D094C6BC73223C51E9C25975800EC9BFB1FC523C57D81B4A2EB52`
- 右键菜单/边缘 matte 后备份：`E:\DeskPet_backups\DeskPet_final_v2_20261027_145227.zip`
  - SHA-256：`C2AAB54CFC8918D3DEF6377CEFD0220B3D1D3899626C3F81A453F699B849F536`
- 最终右键菜单位置修正后备份：`E:\DeskPet_backups\DeskPet_final_v3_20261027_145303.zip`
  - SHA-256：`504C325E9C32A887BF34D83FA60F3CA92359AE8F0F7E3ABB48864234FC2F3A65`
- 默认待机/右键动作/边缘 matte 最终备份：`E:\DeskPet_backups\DeskPet_final_v4_20261027_145515.zip`
  - SHA-256：`1A19336EF284E4E2A77F2A7D2442477AACFF1BC350E0941E1F1300A334FEEED1`
- 两份备份都不含 `.godot/` 和 `__pycache__/`。
- `voxel_character/` 已移动到 `E:\DeskPet_archive\voxel_character_20261027_142623`；
  重构前备份中仍保留原始副本。
