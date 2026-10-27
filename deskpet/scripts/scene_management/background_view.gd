class_name BackgroundView
extends Node2D
## Config-driven scene background layer.
##
## Supported background types:
##   transparent - no draw; desktop mode shows the actual desktop through the window
##   color       - flat color with an optional floor band
##   texture     - single nearest-filtered background texture
## No background artwork exists yet, so both initial scenes use "transparent".

var last_error: String = ""

var _config: Dictionary = {}
var _design_size: Vector2 = Vector2(640.0, 720.0)
var _texture_sprite: Sprite2D = null


func setup(config: Dictionary, design_size: Vector2) -> bool:
	last_error = ""
	_clear()
	_config = config
	_design_size = design_size

	if typeof(config) != TYPE_DICTIONARY or config.is_empty():
		return _fail("Background config is empty.")

	var background_type := str(config.get("type", "transparent"))
	match background_type:
		"transparent":
			queue_redraw()
			return true
		"color":
			queue_redraw()
			return true
		"texture":
			return _setup_texture(config)
		_:
			return _fail("Unsupported background type '%s' (expected transparent, color or texture)." % background_type)


func _draw() -> void:
	var background_type := str(_config.get("type", "transparent"))
	if background_type != "color":
		return

	var color := Color.from_string(str(_config.get("color", "#000000")), Color.BLACK)
	draw_rect(Rect2(Vector2.ZERO, _design_size), color, true)

	var floor_config: Variant = _config.get("floor", {})
	if typeof(floor_config) == TYPE_DICTIONARY and bool((floor_config as Dictionary).get("enabled", false)):
		var floor_y := clampf(float((floor_config as Dictionary).get("y", _design_size.y)), 0.0, _design_size.y)
		var floor_color := Color.from_string(str((floor_config as Dictionary).get("color", "#000000")), Color.BLACK)
		draw_rect(Rect2(0.0, floor_y, _design_size.x, _design_size.y - floor_y), floor_color, true)


func _setup_texture(config: Dictionary) -> bool:
	var texture_path := str(config.get("texture", ""))
	if texture_path.is_empty():
		return _fail("background.type is 'texture' but background.texture is empty.")
	if not FileAccess.file_exists(texture_path):
		return _fail("Background texture file is missing: %s" % texture_path)
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return _fail("Background texture could not be loaded: %s" % texture_path)

	_texture_sprite = Sprite2D.new()
	_texture_sprite.name = "BackgroundTexture"
	_texture_sprite.texture = texture
	_texture_sprite.centered = false
	_texture_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture_sprite.position = _read_vec2(config.get("position"), Vector2.ZERO)
	_texture_sprite.scale = _read_vec2(config.get("scale"), Vector2.ONE)
	add_child(_texture_sprite)
	return true


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_texture_sprite = null
	queue_redraw()


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var arr: Array = value
	if arr.size() != 2:
		return fallback
	return Vector2(float(arr[0]), float(arr[1]))


func _fail(message: String) -> bool:
	last_error = message
	push_error("[BackgroundView] " + message)
	queue_redraw()
	return false
