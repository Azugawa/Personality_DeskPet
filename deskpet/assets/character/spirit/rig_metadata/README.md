# Provisional rig metadata — not used at runtime

These are copies of the existing pipeline output:

- `joints.json` ← `E:\DeskPet\character_assets\config\joints.json`
- `layers.json` ← `E:\DeskPet\character_assets\config\layers.json`
- `segmentation.json` ← `E:\DeskPet\character_assets\config\segmentation.json`

They are mirrored byte-for-byte and an integration test asserts they still match
`character_assets` on every run. Do not edit them here; edit the pipeline output
and re-copy if the segmentation is ever corrected.

Important status:

- All 12 proposed parts are marked `NEEDS_REVIEW` in the pipeline report.
- 0 parts are human-confirmed.
- The formal `character_assets/parts/` export directory is empty.
- Only provisional part PNGs exist under `character_assets/parts_provisional/`.

Therefore this framework does **not** load these files and does not animate body parts.
They are copied here only so a future animation phase can start from the existing data
without touching the original pipeline output. Part animation stays disabled until a human
reviews and confirms the segmentation.

`Character.set_part_pose()` and `Character.request_animation()` deliberately return `false`
with a warning; they are reserved interfaces, not working animation.
