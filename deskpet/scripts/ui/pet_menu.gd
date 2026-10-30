class_name PetMenu
extends CanvasLayer
signal action_selected(activity_id: String)
var _popup: PopupPanel
var _content: Control
var _entries: Array = []
var _ids: Array[String] = []
const WIDTH := 240
const HEADER := 84
const ROW := 36
const FOOTER := 34

func _ready() -> void:
	layer = 110
	_popup = PopupPanel.new()
	_popup.transparent = true
	_popup.transparent_bg = true
	_popup.borderless = true
	_popup.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_popup)
	_content = Control.new()
	_content.mouse_default_cursor_shape = Control.CURSOR_CROSS
	_content.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_popup.add_child(_content)

func show_actions(entries: Array, _position: Vector2) -> void:
	if entries.is_empty(): return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_content.theme = PixelDialogSkin.create_theme()
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.get_screen_from_rect(Rect2i(Vector2i(_position), Vector2i.ONE)))
	var height := mini(168 + entries.size() * 46, screen.size.y - 24)
	_content.custom_minimum_size = Vector2(WIDTH, height)
	_content.size = Vector2(WIDTH, height)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", PixelDialogSkin.pixel_box(Color("477aca")))
	_content.add_child(panel)
	panel.offset_top = 100
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	rows.add_child(PixelDialogSkin.heading("选项"))
	for entry in entries:
		var button := Button.new()
		button.text = str(entry.get("label", entry.id))
		button.set_meta("action_id", str(entry.id))
		button.custom_minimum_size.y = 40
		button.disabled = not bool(entry.get("enabled", true))
		button.pressed.connect(_select.bind(str(entry.id)))
		rows.add_child(button)
	PixelDialogSkin.add_topper(_content, WIDTH)
	var pos := Vector2i(_position) + Vector2i(8, 8)
	if pos.x + WIDTH > screen.end.x: pos.x -= WIDTH + 16
	pos.x = clampi(pos.x, screen.position.x, maxi(screen.position.x, screen.end.x-WIDTH))
	pos.y = clampi(pos.y, screen.position.y, maxi(screen.position.y, screen.end.y-height))
	_popup.popup(Rect2i(pos, Vector2i(WIDTH, height)))

func _select(id: String) -> void:
	hide_menu()
	action_selected.emit(id)
func hide_menu() -> void:
	if _popup != null: _popup.hide()
func is_menu_visible() -> bool:
	return _popup != null and _popup.visible



func _process(_delta: float) -> void:
	if is_menu_visible(): _refresh_work_label(_content)

func _refresh_work_label(node: Node) -> void:
	if node is Button and node.get_meta("action_id", "") == "assistant_work_mode":
		var service: Node = FeatureServices.get_provider("work_mode")
		if service != null: node.text = service.menu_label()
	for child in node.get_children(): _refresh_work_label(child)
