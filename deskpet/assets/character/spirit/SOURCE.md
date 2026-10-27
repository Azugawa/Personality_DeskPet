# Character source assets

`character_full.png` is a **verbatim copy** of the confirmed full-body source PNG:

- Original: `E:\DeskPet\Spirit\人物图_透明.png`
- Also present as: `E:\DeskPet\character_assets\source\original.png`
- SHA-256: `deca4a6b53ebd2f7f60128e14bc29930c616416e932b13ce5cab49a8bb61c8dc`
- Size: 2048 × 2048 RGBA
- Transparent content bounds: x 406, y 86, width 1231, height 1871

`character_full.png` is now the **legacy full-body fallback** and the source reference
for the original front pose. The default runtime uses the generated directional
sprites:

- `directions/` — 8 standing directions
- `idle/` — 5 front idle frames
- `walk/` — 8 × 4 walk frames

Those are generated from the authored contact sheets in `E:\DeskPet\素材` by
`tools/prepare_sprite_sheets.py`. The original 2048×2048 file is never
overwritten.

Do not re-cut, repaint, replace or rename the original without updating
`config/characters/spirit.json`, `config/animations/spirit.json` and re-running
the tests.
