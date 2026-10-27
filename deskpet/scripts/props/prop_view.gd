class_name PropView
extends Node2D
## Config-driven scene prop presenter.
##
## "debug_placeholder" draws an unmistakable hatched placeholder with a text
## label directly in _draw(). It is not final furniture art. "texture" loads a
## real prop PNG when one becomes available. Position, scale, layer and
## visibility are applied by SceneView from scene JSON, never hard-coded here.

var prop_id: String = ""
var prop_type: String = ""
var last_error: String = ""

var _config: Dictionary = {}
var _size: Vector2 = Vector2(120.0, 80.0)
var _color: Color = Color(0.55, 0.45, 0.35, 0.55)
var _texture_sprite: Sprite2D = null


func setup(config: Dictionary) -> bool:
	last_error = ""
	_clear()
	_config = config
	prop_id = str(config.get("id", ""))
	prop_type = str(config.get("type", ""))
	_size = _read_vec2(config.get("size"), Vector2(120.0, 80.0))
	_color = Color.from_string(str(config.get("color", "#8a6f4d")), Color(0.55, 0.45, 0.35, 0.55))
	if _size.x <= 0.0 or _size.y <= 0.0:
		return _fail("Prop '%s' size must be positive (got %s)." % [prop_id, str(_size)])

	match prop_type:
		"debug_placeholder":
			queue_redraw()
			return true
		"texture":
			return _setup_texture(config)
		_:
			return _fail("Unknown prop type '%s' for prop '%s'." % [prop_type, prop_id])


func _draw() -> void:
	if prop_type == "debug_placeholder":
		_draw_placeholder(_color)
		var display_label := str(_config.get("label", _config.get("display_name", prop_id)))
		if _size.x < 85.0:
			_draw_text_block("%s\nDEBUG\nPLACEHOLDER" % display_label, 9, Color(1.0, 1.0, 1.0, 1.0))
		elif _size.x < 140.0:
			_draw_text_block("%s\nDEBUG PLACEHOLDER" % display_label, 10, Color(1.0, 1.0, 1.0, 1.0))
		else:
			_draw_text_block("%s\nDEBUG PLACEHOLDER" % display_label, 14, Color(1.0, 1.0, 1.0, 1.0))
	elif not last_error.is_empty():
		_draw_placeholder(Color(1.0, 0.0, 1.0, 0.7))
		_draw_text_block("MISSING PROP ASSET\n" + last_error, 10, Color(1.0, 1.0, 1.0, 1.0))


func _draw_placeholder(base_color: Color) -> void:
	var fill := Color(base_color.r, base_color.g, base_color.b, 0.38)
	var border := Color(base_color.r, base_color.g, base_color.b, 0.95).lightened(0.25)
	var rect := Rect2(Vector2.ZERO, _size)
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, 2.0)

	# Diagonal hatching makes it impossible to mistake this for final art.
	var diagonal := _size.x + _size.y
	var distance := 0.0
	var hatch_color := Color(border.r, border.g, border.b, 0.28)
	while distance < diagonal:
		var p1 := Vector2(maxf(0.0, distance - _size.y), minf(distance, _size.y))
		var p2 := Vector2(minf(distance, _size.x), maxf(0.0, distance - _size.x))
		draw_line(p1, p2, hatch_color, 1.0)
		distance += 24.0

	# Corner ticks.
	var tick := 10.0
	draw_line(Vector2.ZERO, Vector2(tick, 0.0), border, 2.0)
	draw_line(Vector2.ZERO, Vector2(0.0, tick), border, 2.0)
	draw_line(Vector2(_size.x, 0.0), Vector2(_size.x - tick, 0.0), border, 2.0)
	draw_line(Vector2(_size.x, 0.0), Vector2(_size.x, tick), border, 2.0)


func _draw_text_block(text: String, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text_width := maxf(20.0, _size.x - 12.0)
	var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, text_width, font_size)
	var panel_height := measured.y + 12.0
	var panel := Rect2(6.0, (_size.y - panel_height) * 0.5, _size.x - 12.0, panel_height)
	draw_rect(panel, Color(0.0, 0.0, 0.0, 0.55), true)
	draw_rect(panel, Color(1.0, 1.0, 1.0, 0.18), false, 1.0)
	var baseline := panel.position.y + 6.0 + font.get_ascent(font_size)
	draw_multiline_string(font, Vector2(panel.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, text_width, font_size, -1, color)


func _setup_texture(config: Dictionary) -> bool:
	var texture_path := str(config.get("texture", ""))
	if texture_path.is_empty():
		return _fail("Prop '%s' has type 'texture' but no texture path." % prop_id)
	if not FileAccess.file_exists(texture_path):
		return _fail("Prop '%s' texture file is missing: %s" % [prop_id, texture_path])
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return _fail("Prop '%s' texture could not be loaded: %s" % [prop_id, texture_path])

	_texture_sprite = Sprite2D.new()
	_texture_sprite.name = "PropTexture"
	_texture_sprite.texture = texture
	_texture_sprite.centered = false
	_texture_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_texture_sprite)
	if not config.has("size"):
		_size = texture.get_size()
	return true


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_texture_sprite = null
	queue_redraw()


func _fail(message: String) -> bool:
	last_error = message
	push_error("[PropView] " + message)
	queue_redraw()
	return false


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var arr: Array = value
	if arr.size() != 2:
		return fallback
	return Vector2(float(arr[0]), float(arr[1]))
