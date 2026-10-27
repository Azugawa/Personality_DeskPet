class_name FurnitureView
extends Node2D
## One independently controllable furniture object.
##
## Profiles provide eight directional textures, a canvas, a floor anchor and
## optional interaction anchors. The node position is always the bottom-centre
## floor contact point. Appearance, direction, movement and anchors are separate
## operations so the character state machine can coordinate without touching
## internal drawing state.

signal move_finished(furniture_id: String)
signal furniture_visibility_changed(furniture_id: String, is_visible: bool)

@onready var visual_root: Node2D = $VisualRoot
@onready var sprite: Sprite2D = $VisualRoot/Sprite
@onready var anchor_root: Node2D = $VisualRoot/Anchors
@onready var shadow_root: Node2D = $ShadowRoot
@onready var seat_anchor: Marker2D = $VisualRoot/Anchors/SeatAnchor
@onready var work_surface_anchor: Marker2D = $VisualRoot/Anchors/WorkSurfaceAnchor
@onready var screen_anchor: Marker2D = $VisualRoot/Anchors/ScreenAnchor

var furniture_id: String = ""
var profile: Dictionary = {}
var direction: String = "front"
var last_error: String = ""

var _textures: Dictionary = {}
var _canvas: Vector2 = Vector2(120.0, 160.0)
var _display_scale: float = 1.0
var _visibility_tween: Tween = null
var _movement_tween: Tween = null
var _pending_visible: bool = true


func setup(config: Dictionary) -> bool:
	last_error = ""
	furniture_id = str(config.get("id", config.get("profile_id", "furniture")))
	profile = config
	_display_scale = maxf(0.01, float(config.get("scale", 1.0)))
	_canvas = _read_vec2(config.get("canvas"), Vector2(120.0, 160.0))
	var direction_texts: Variant = config.get("directions", {})
	if typeof(direction_texts) != TYPE_DICTIONARY or (direction_texts as Dictionary).is_empty():
		return _fail("Furniture '%s' has no directional textures." % furniture_id)

	_textures.clear()
	for direction_name in (direction_texts as Dictionary).keys():
		var path := str((direction_texts as Dictionary)[direction_name])
		if path.is_empty() or not FileAccess.file_exists(path):
			return _fail("Furniture '%s' direction '%s' texture is missing: %s" % [furniture_id, str(direction_name), path])
		var texture := load(path) as Texture2D
		if texture == null:
			return _fail("Furniture '%s' direction '%s' could not load: %s" % [furniture_id, str(direction_name), path])
		_textures[str(direction_name)] = texture

	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(-_canvas.x * 0.5, -_canvas.y)
	visual_root.scale = Vector2(_display_scale, _display_scale)

	_apply_anchor(seat_anchor, config.get("seat_anchor_uv"), false)
	_apply_anchor(work_surface_anchor, config.get("work_surface_uv"), false)
	_apply_anchor(screen_anchor, config.get("screen_anchor_uv"), false)

	_clear_shadow()
	var shadow_config: Variant = config.get("shadow", {})
	if typeof(shadow_config) == TYPE_DICTIONARY and bool((shadow_config as Dictionary).get("enabled", false)):
		var shadow := ShadowView.new()
		shadow.name = "ContactShadow"
		shadow_root.add_child(shadow)
		shadow.setup(shadow_config as Dictionary, {})

	var default_direction := str(config.get("default_direction", "front"))
	if not set_direction(default_direction):
		set_direction(str(_textures.keys()[0]))
	return true


func set_direction(direction_name: String) -> bool:
	if not _textures.has(direction_name):
		push_warning("[FurnitureView] Unknown direction '%s' for '%s'." % [direction_name, furniture_id])
		return false
	direction = direction_name
	sprite.texture = _textures[direction_name]
	return true


func set_visible_immediate(value: bool) -> void:
	if _visibility_tween != null:
		_visibility_tween.kill()
		_visibility_tween = null
	_pending_visible = value
	visible = value
	modulate = Color.WHITE
	visual_root.scale = Vector2(_display_scale, _display_scale)
	furniture_visibility_changed.emit(furniture_id, value)


func set_visible_animated(value: bool, duration: float = 0.24) -> void:
	if _visibility_tween != null:
		_visibility_tween.kill()
		_visibility_tween = null
	_pending_visible = value
	if value:
		visible = true
		modulate.a = 0.0
		visual_root.scale = Vector2(_display_scale * 0.88, _display_scale * 0.88)
		_visibility_tween = create_tween().set_parallel(true)
		_visibility_tween.tween_property(self, "modulate:a", 1.0, duration)
		_visibility_tween.tween_property(visual_root, "scale", Vector2(_display_scale, _display_scale), duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_visibility_tween = create_tween().set_parallel(true)
		_visibility_tween.tween_property(self, "modulate:a", 0.0, duration)
		_visibility_tween.tween_property(visual_root, "scale", Vector2(_display_scale * 0.9, _display_scale * 0.9), duration)
	_visibility_tween.finished.connect(_on_visibility_tween_finished, CONNECT_ONE_SHOT)


func _on_visibility_tween_finished() -> void:
	if not _pending_visible:
		visible = false
		modulate = Color.WHITE
		visual_root.scale = Vector2(_display_scale, _display_scale)
	_visibility_tween = null
	furniture_visibility_changed.emit(furniture_id, visible)


func move_to(target_position: Vector2, duration: float = 0.35) -> void:
	if _movement_tween != null:
		_movement_tween.kill()
	if duration <= 0.0:
		position = target_position
		move_finished.emit(furniture_id)
		return
	_movement_tween = create_tween()
	_movement_tween.tween_property(self, "position", target_position, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_movement_tween.finished.connect(func() -> void:
		move_finished.emit(furniture_id)
	, CONNECT_ONE_SHOT)


func get_approach_position() -> Vector2:
	var offset := _read_vec2(profile.get("approach_offset"), Vector2(0.0, 28.0))
	return global_position + offset


func get_anchor_position(anchor_name: String) -> Vector2:
	match anchor_name:
		"seat":
			return seat_anchor.global_position
		"work_surface":
			return work_surface_anchor.global_position
		"screen":
			return screen_anchor.global_position
		_:
			return global_position


func has_anchor(anchor_name: String) -> bool:
	match anchor_name:
		"seat":
			return seat_anchor.visible
		"work_surface":
			return work_surface_anchor.visible
		"screen":
			return screen_anchor.visible
		_:
			return false


func get_direction() -> String:
	return direction


func is_visible_target() -> bool:
	return _pending_visible


func get_screen_bounds() -> Rect2:
	var size := _canvas * Vector2(_display_scale, _display_scale)
	return Rect2(global_position + Vector2(-size.x * 0.5, -size.y), size)


func get_display_scale() -> float:
	return _display_scale


func _apply_anchor(anchor: Marker2D, value: Variant, fallback_visible: bool) -> void:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		anchor.visible = false
		return
	var uv: Array = value
	anchor.visible = true
	anchor.position = Vector2(float(uv[0]) * _canvas.x - _canvas.x * 0.5, float(uv[1]) * _canvas.y - _canvas.y)
	if fallback_visible:
		anchor.visible = true


func _clear_shadow() -> void:
	for child in shadow_root.get_children():
		shadow_root.remove_child(child)
		child.queue_free()


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() != 2:
		return fallback
	return Vector2(float(array[0]), float(array[1]))


func _fail(message: String) -> bool:
	last_error = message
	push_error("[FurnitureView] " + message)
	return false
