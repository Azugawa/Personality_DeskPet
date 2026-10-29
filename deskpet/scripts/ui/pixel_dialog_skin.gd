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
	var panel := _sheet_style(PANEL_REGION, 56)
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
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(0.9, 0.95, 1.0))
	button.add_theme_stylebox_override("normal", _button_box(BUTTON_COLOR))
	button.add_theme_stylebox_override("hover", _button_box(Color(0.32, 0.58, 0.86)))
	button.add_theme_stylebox_override("pressed", _button_box(Color(0.18, 0.4, 0.68)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


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
