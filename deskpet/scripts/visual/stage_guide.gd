class_name StageGuide
extends Node2D
## Preview-only pseudo-3D floor guide.
##
## It draws the same ground plane used by SceneView/Pseudo3DPropView so the
## spatial direction is visible while composing scenes. It is hidden in desktop
## mode together with Main's preview backdrop; it is not a background asset.

var last_error: String = ""

var _profile: Dictionary = {}


func setup(profile: Dictionary) -> bool:
	last_error = ""
	_profile = profile
	if profile.is_empty():
		last_error = "Visual profile is empty; floor guide disabled."
		push_error("[StageGuide] " + last_error)
		queue_redraw()
		return false
	queue_redraw()
	return true


func is_configured() -> bool:
	return not _profile.is_empty()


func _draw() -> void:
	if _profile.is_empty():
		return
	var guide := Pseudo3D.floor_guide(_profile)
	if guide.is_empty() or not bool(guide.get("enabled", true)):
		return

	var front_depth := float(guide.get("front_depth", -120.0))
	var back_depth := float(guide.get("back_depth", 200.0))
	var left_x := float(guide.get("left_x", -80.0))
	var right_x := float(guide.get("right_x", 700.0))
	var step_x := maxf(1.0, float(guide.get("step_x", 80.0)))
	var step_depth := maxf(1.0, float(guide.get("step_depth", 25.0)))
	var major_step_x := maxf(1.0, float(guide.get("major_step_x", 160.0)))
	var major_step_depth := maxf(1.0, float(guide.get("major_step_depth", 100.0)))
	var depth_line_width := maxf(1.0, float(guide.get("line_width_depth", 1.0)))
	var lateral_line_width := maxf(1.0, float(guide.get("line_width_lateral", 2.0)))

	var floor_color := _color(guide, "floor_color", Color(0.12, 0.15, 0.2, 1.0))
	var grid_color := _color(guide, "grid_color", Color(0.18, 0.23, 0.3, 1.0))
	var major_grid_color := _color(guide, "major_grid_color", Color(0.24, 0.3, 0.38, 1.0))
	var edge_color := _color(guide, "edge_color", Color(0.34, 0.42, 0.52, 1.0))
	var origin_color := _color(guide, "origin_line_color", Color(0.43, 0.52, 0.62, 1.0))

	var front_left := _ground_point(left_x, front_depth)
	var front_right := _ground_point(right_x, front_depth)
	var back_left := _ground_point(left_x, back_depth)
	var back_right := _ground_point(right_x, back_depth)

	draw_colored_polygon(PackedVector2Array([front_left, front_right, back_right, back_left]), floor_color)

	var depth := front_depth
	while depth <= back_depth + 0.001:
		var line_color := grid_color
		if is_zero_approx(depth):
			line_color = origin_color
		elif int(roundf(depth)) % int(major_step_depth) == 0:
			line_color = major_grid_color
		draw_line(_ground_point(left_x, depth), _ground_point(right_x, depth), line_color, depth_line_width, false)
		depth += step_depth

	# Emphasize the front/back limits of the guide.
	draw_line(front_left, front_right, edge_color, 1.0, false)
	draw_line(back_left, back_right, edge_color, 1.0, false)
	draw_line(front_left, back_left, edge_color, 1.0, false)
	draw_line(front_right, back_right, edge_color, 1.0, false)

	var x := left_x
	while x <= right_x + 0.001:
		var line_color := grid_color
		if is_zero_approx(x) or int(roundf(x)) % int(major_step_x) == 0:
			line_color = major_grid_color
		draw_line(_ground_point(x, front_depth), _ground_point(x, back_depth), line_color, lateral_line_width, false)
		x += step_x


func _ground_point(x: float, depth: float) -> Vector2:
	return Pseudo3D.snap(Pseudo3D.project_ground(_profile, x, depth))


func _color(config: Dictionary, key: String, fallback: Color) -> Color:
	return Color.from_string(str(config.get(key, "")), fallback)
