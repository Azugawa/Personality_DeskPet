# Props assets

The runtime now has three authored directional furniture sets:

- `chair/` — 8 views of the wooden chair
- `desk/` — 8 views of the wooden desk
- `computer/` — 8 views of the computer workstation

All 69 runtime sprites are generated from the source contact sheets in
`E:\DeskPet\素材` by `tools/prepare_sprite_sheets.py`. The source files are never
overwritten.

Furniture profiles live in `config/props/`:

- `chair.json`: `seat_anchor_uv`
- `desk.json`: `work_surface_uv`, `lean_anchor_uv`
- `computer.json`: `work_surface_uv`, `screen_anchor_uv`

Each furniture object is an independent `FurnitureView` instance; it can be
shown, hidden, moved and rotated through its eight authored directions without
touching the character state machine.

There are still no authored carrying or sitting poses. Those actions remain
reserved rather than being faked.
