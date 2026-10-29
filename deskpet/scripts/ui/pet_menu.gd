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

func _piece(region: Rect2, rect: Rect2) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/ui/panels/menu_source.png")
	atlas.region = region
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.texture = atlas
	image.position = rect.position
	image.size = rect.size
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(image)

func show_actions(entries: Array, _position: Vector2) -> void:
	if entries.is_empty(): return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_entries = entries
	_ids.clear()
	var height := HEADER + ROW * entries.size() + FOOTER
	_content.custom_minimum_size = Vector2(WIDTH, height)
	_content.size = Vector2(WIDTH, height)
	_piece(Rect2(0,0,1177,405),Rect2(0,0,WIDTH,HEADER))
	var font: FontFile = load("res://assets/fonts/pixel.ttf")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	for index in entries.size():
		var entry: Dictionary = entries[index]
		_ids.append(str(entry.id))
		_piece(Rect2(0,405,1177,150),Rect2(0,HEADER+index*ROW,WIDTH,ROW))
		var button := Button.new()
		button.mouse_default_cursor_shape = Control.CURSOR_CROSS
		button.text = str(entry.get("label", entry.id))
		button.position = Vector2(53, HEADER+index*ROW+4)
		button.size = Vector2(134, ROW-8)
		button.disabled = not bool(entry.get("enabled",true))
		button.add_theme_font_override("font",font)
		button.add_theme_font_size_override("font_size",18)
		button.add_theme_color_override("font_color",Color("243e70"))
		button.add_theme_color_override("font_hover_color",Color("14294d"))
		button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.23,0.49,0.8,0.42)
		button.add_theme_stylebox_override("hover",hover)
		button.add_theme_stylebox_override("pressed",hover)
		button.pressed.connect(_select.bind(str(entry.id)))
		_content.add_child(button)
	_piece(Rect2(0,1165,1177,172),Rect2(0,HEADER+ROW*entries.size(),WIDTH,FOOTER))
	var pos := DisplayServer.mouse_get_position()+Vector2i(8,8)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.get_screen_from_rect(Rect2i(pos,Vector2i.ONE)))
	pos.x = clampi(pos.x,screen.position.x,screen.end.x-WIDTH)
	pos.y = clampi(pos.y,screen.position.y,screen.end.y-height)
	_popup.popup(Rect2i(pos,Vector2i(WIDTH,height)))

func _select(id: String) -> void:
	hide_menu()
	action_selected.emit(id)
func hide_menu() -> void:
	if _popup != null: _popup.hide()
func is_menu_visible() -> bool:
	return _popup != null and _popup.visible
