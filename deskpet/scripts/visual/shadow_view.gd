class_name ShadowView
extends Node2D
## Reusable flat contact-shadow node. No blur, no gradient: pixel-art compatible.
##
## Shapes:
##   ellipse   - character contact shadow; screen-space ellipse
##   footprint - furniture floor footprint projected with the shared depth axis
##
## The parent object controls the node's z_index; this keeps the shadow an
## independently editable node in the scene tree.

var _config: Dictionary = {}
var _visual_profile: Dictionary = {}
var _visible_shape: bool = false


func setup(config: Dictionary, visual_profile: Dictionary = {}) -> bool:
	_config = config
	_visual_profile = visual_profile
	_visible_shape = false
	if typeof(config) != TYPE_DICTIONARY or config.is_empty():
		queue_redraw()
		return false
	if not bool(config.get("enabled", true)):
		queue_redraw()
		return true

	_visible_shape = true
	queue_redraw()
	return true


func _draw() -> void:
	if not _visible_shape:
		return
	var shape := str(_config.get("shape", "ellipse"))
	if shape == "footprint" and not _visual_profile.is_empty():
		_draw_footprint()
	else:
		_draw_ellipse()


func _draw_ellipse() -> void:
	var center := _read_vec2(_config.get("center"), Vector2.ZERO)
	var offset := _read_vec2(_config.get("offset"), Vector2.ZERO)
	var size := _read_vec2(_config.get("size"), Vector2(224.0, 36.0))
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var center_position := center + offset
	var color := _read_color(_config.get("color"), Color(0.0, 0.0, 0.0, 0.4))
	var core_color := _read_color(_config.get("core_color"), Color(0.0, 0.0, 0.0, 0.25))
	var core_scale := clampf(float(_config.get("core_scale", 0.62)), 0.05, 1.0)
	_draw_ellipse_points(center_position, size, color)
	if core_color.a > 0.0:
		_draw_ellipse_points(center_position, size * core_scale, core_color)


func _draw_footprint() -> void:
	var center_ground := _read_vec2(_config.get("center"), Vector2.ZERO)
	var size_ground := _read_vec2(_config.get("size"), Vector2(120.0, 80.0))
	if size_ground.x <= 0.0 or size_ground.y <= 0.0:
		return
	var offset := _read_vec2(_config.get("offset"), Vector2.ZERO)
	var color := _read_color(_config.get("color"), Color(0.0, 0.0, 0.0, 0.35))
	var core_color := _read_color(_config.get("core_color"), Color(0.0, 0.0, 0.0, 0.2))
	var core_scale := clampf(float(_config.get("core_scale", 0.66)), 0.05, 1.0)

	_draw_polygon(_footprint_points(center_ground, size_ground, offset), color)
	if core_color.a > 0.0:
		_draw_polygon(_footprint_points(center_ground, size_ground * core_scale, offset), core_color)


func _footprint_points(center: Vector2, size: Vector2, screen_offset: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var cx := center.x
	var cd := center.y
	var half_w := size.x * 0.5
	var half_d := size.y * 0.5
	var corners := [
		Vector2(cx - half_w, cd - half_d),
		Vector2(cx + half_w, cd - half_d),
		Vector2(cx + half_w, cd + half_d),
		Vector2(cx - half_w, cd + half_d),
	]
	for corner in corners:
		var projected := Pseudo3D.project_local(_visual_profile, Vector3(corner.x, corner.y, 0.0), Vector3.ZERO)
		points.append(Pseudo3D.snap(projected + screen_offset))
	return points


func _draw_ellipse_points(center: Vector2, size: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	var segments := 24
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(Pseudo3D.snap(center + Vector2(cos(angle) * size.x * 0.5, sin(angle) * size.y * 0.5)))
	_draw_polygon(points, color)


func _draw_polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, color)


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var arr: Array = value
	if arr.size() != 2:
		return fallback
	return Vector2(float(arr[0]), float(arr[1]))


func _read_color(value: Variant, fallback: Color) -> Color:
	var text := str(value)
	if text.is_empty():
		return fallback
	var result := Color.from_string(text, fallback)
	if typeof(value) == TYPE_STRING and text.begins_with("#") and text.length() == 7:
		result.a = 1.0
	return result
