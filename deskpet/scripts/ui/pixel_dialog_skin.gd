class_name PixelDialogSkin
extends RefCounted
## Shared pixel-art skin for the temporary assistant dialogs.
##
## UpdateService keeps its own copy because it predates this helper; new
## assistant windows use this one so all temporary UI shares the same font.

const SHEET_PATH := "res://assets/ui/panels/dialog_sheet.png"
const FONT_PATH := "res://assets/fonts/pixel.ttf"
const PANEL_REGION := Rect2(1250, 827, 270, 153)
const TEXT_COLOR := Color("173763")
const BUTTON_COLOR := Color(0.23, 0.49, 0.8)


static func apply(window: AcceptDialog) -> void:
	window.borderless = true
	window.transparent = true
	window.transparent_bg = true
	var font := load_font()
	window.add_theme_font_override("font", font)
	window.add_theme_font_size_override("font_size", 18)
	window.add_theme_color_override("font_color", TEXT_COLOR)
	var panel := pixel_box(Color("e2f2ff"))
	panel.content_margin_left = 34
	panel.content_margin_right = 34
	panel.content_margin_top = 52
	panel.content_margin_bottom = 35
	window.add_theme_stylebox_override("panel", panel)
	window.get_label().add_theme_font_override("font", font)
	window.get_label().add_theme_font_size_override("font_size", 18)
	window.get_label().add_theme_color_override("font_color", TEXT_COLOR)
	style_button(window.get_ok_button())
	if window is ConfirmationDialog:
		style_button(window.get_cancel_button())


static func style_button(button: Button) -> void:
	if button == null:
		return
	var font := load_font()
	button.custom_minimum_size = Vector2(148, 40)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	button.theme = create_theme()



static func load_font() -> FontFile:
	var font: FontFile = load(FONT_PATH)
	if font != null:
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	return font


static func _button_box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


static func _sheet_style(region: Rect2, margin: int) -> StyleBoxTexture:
	var sheet: Texture2D = load(SHEET_PATH)
	var cropped := sheet.get_image().get_region(Rect2i(region))
	cropped.fill_rect(Rect2i(0, 0, 190, 15), Color.TRANSPARENT)
	var texture := ImageTexture.create_from_image(cropped)
	var style := StyleBoxTexture.new()
	style.texture = texture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, margin)
	return style


static func pixel_box(fill: Color, inset: int = 12) -> StyleBoxTexture:
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var colors := [Color("263e6b"), Color("6798db"), Color("b7ddff"), Color("f8fcff"), fill]
	for layer in range(5):
		var edge: int = layer * 2
		var radius: int = maxi(6, 20 - edge)
		for y in range(edge, 48 - edge):
			var dy: int = mini(y - edge, 47 - edge - y)
			var cut: int = 0
			if dy < radius:
				cut = int(ceil((radius - sqrt(float(radius * radius - (radius - dy - 1) * (radius - dy - 1)))) / 2.0)) * 2
			image.fill_rect(Rect2i(edge + cut, y, 48 - 2 * edge - cut * 2, 1), colors[layer])
	image.fill_rect(Rect2i(16, 8, 16, 2), Color("ffffff"))
	image.fill_rect(Rect2i(16, 38, 16, 2), fill.darkened(0.12))
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(image)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, 20)
		box.set_content_margin(side, inset)
	return box


static func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = load_font()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", TEXT_COLOR)
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var colors := {"normal": "e2f2ff", "hover": "f5fbff", "pressed": "9fc8ef", "disabled": "b8c6d8", "focus": "c4e2ff"}
			theme.set_stylebox(state, type, pixel_box(Color(colors[state]), 10))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(state, type, TEXT_COLOR)
		theme.set_color("font_disabled_color", type, Color("667a96"))
	for type in ["VScrollBar", "HScrollBar"]:
		for state in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("d9eaff") if state.begins_with("scroll") else Color("6198df")
			if state == "grabber_highlight": box.bg_color = Color("8bbcff")
			if state == "grabber_pressed": box.bg_color = Color("3b69ab")
			box.border_color = Color("294b7e")
			box.set_border_width_all(2)
			box.content_margin_left = 7
			box.content_margin_top = 7
			box.content_margin_right = 7
			box.content_margin_bottom = 7
			theme.set_stylebox(state, type, box)
	return theme


static func heading(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


static func add_topper(parent: Control, width: int, height: int = 120) -> void:
	var portrait := Sprite2D.new()
	portrait.texture = load("res://assets/ui/icons/panel_topper.png")
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.centered = false
	var ratio := minf(180.0 / portrait.texture.get_width(), float(height) / portrait.texture.get_height())
	portrait.scale = Vector2(ratio, ratio)
	portrait.position = Vector2((width - portrait.texture.get_width() * ratio) / 2, 0)
	parent.add_child(portrait)
