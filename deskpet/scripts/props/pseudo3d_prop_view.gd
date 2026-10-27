class_name Pseudo3DPropView
extends Node2D
## Profile-driven pseudo-3D furniture presenter.
##
## A furniture profile describes boxes in local coordinates:
##   x = lateral, y = depth (away), z = height (up).
## The node position is the projected front-centre ground anchor. Boxes are
## drawn with only top/front/right faces, flat palette tones and 1 px outlines.
##
## These profiles are explicitly debug placeholders, not final furniture art.
## The label and anchor marker are drawn by the profile's debug block.

@onready var shadow_root: Node2D = $ShadowRoot

var prop_id: String = ""
var prop_type: String = ""
var profile_path: String = ""
var profile: Dictionary = {}
var visual_profile: Dictionary = {}
var parts: Array = []
var ground_depth: float = 0.0
var last_error: String = ""

var _anchor: Vector3 = Vector3.ZERO
var _bounds: Rect2 = Rect2()
var _missing_asset: bool = false


func setup(config: Dictionary, shared_visual_profile: Dictionary) -> bool:
	last_error = ""
	_missing_asset = false
	_clear()
	prop_id = str(config.get("id", ""))
	prop_type = str(config.get("type", ""))
	visual_profile = shared_visual_profile
	profile_path = str(config.get("profile", ""))

	if profile_path.is_empty():
		return _fail("Prop '%s' is pseudo3d_debug but has no profile path." % prop_id)
	if not FileAccess.file_exists(profile_path):
		return _fail("Furniture profile file is missing: %s" % profile_path)
	profile = ConfigLoader.load_json(profile_path)
	if profile.is_empty():
		return _fail("Furniture profile could not be loaded: %s (%s)" % [profile_path, ConfigLoader.last_error])
	if visual_profile.is_empty():
		return _fail("Shared visual profile is empty; cannot project furniture '%s'." % prop_id)

	var dimensions: Variant = profile.get("dimensions", {})
	if typeof(dimensions) != TYPE_DICTIONARY:
		return _fail("Furniture profile '%s' has no dimensions object." % profile_path)
	var width := float((dimensions as Dictionary).get("width", 0.0))
	var depth := float((dimensions as Dictionary).get("depth", 0.0))
	var height := float((dimensions as Dictionary).get("height", 0.0))
	if width <= 0.0 or depth <= 0.0 or height <= 0.0:
		return _fail("Furniture profile '%s' dimensions must be positive." % profile_path)

	_anchor = _read_vec3(profile.get("anchor"), Vector3(width * 0.5, 0.0, 0.0))

	var raw_parts: Variant = profile.get("parts", [])
	if typeof(raw_parts) != TYPE_ARRAY or (raw_parts as Array).is_empty():
		return _fail("Furniture profile '%s' has no parts." % profile_path)
	parts.clear()
	for part_value in (raw_parts as Array):
		if typeof(part_value) != TYPE_DICTIONARY:
			return _fail("Furniture profile '%s' contains a non-object part." % profile_path)
		var part: Dictionary = part_value
		if not _is_valid_box(part):
			return _fail("Furniture part '%s' must have origin/size [x, depth, z] with positive size." % str(part.get("id", "?")))
		parts.append(part)

	parts.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("draw_order", 0)) < int((b as Dictionary).get("draw_order", 0))
	)

	_setup_shadow(profile.get("shadow", {}))
	_compute_bounds()
	queue_redraw()
	print("[Pseudo3DPropView] Ready: id='%s' profile='%s' parts=%d anchor=%s depth=%.2f" % [
		prop_id, profile_path, parts.size(), str(_anchor), ground_depth
	])
	return true


func get_profile_path() -> String:
	return profile_path


func get_profile_id() -> String:
	return str(profile.get("profile_id", ""))


func get_ground_depth() -> float:
	return ground_depth


func get_parts_count() -> int:
	return parts.size()


func get_shadow_root() -> Node2D:
	return shadow_root


func get_visual_bounds() -> Rect2:
	return Rect2(global_position + _bounds.position * scale, _bounds.size * scale)


func is_missing_asset() -> bool:
	return _missing_asset


func _draw() -> void:
	if _missing_asset:
		_draw_missing_asset()
		return
	for part_value in parts:
		_draw_box(part_value as Dictionary)
	_draw_debug_marker()


func _draw_box(part: Dictionary) -> void:
	var box: Dictionary = part.get("box", {})
	var origin := _read_vec3(box.get("origin"), Vector3.ZERO)
	var size := _read_vec3(box.get("size"), Vector3.ONE)
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return

	var x0 := origin.x
	var x1 := origin.x + size.x
	var d0 := origin.y
	var d1 := origin.y + size.y
	var z0 := origin.z
	var z1 := origin.z + size.z

	var p000 := _project(Vector3(x0, d0, z0))
	var p100 := _project(Vector3(x1, d0, z0))
	var p110 := _project(Vector3(x1, d1, z0))
	var p010 := _project(Vector3(x0, d1, z0))
	var p001 := _project(Vector3(x0, d0, z1))
	var p101 := _project(Vector3(x1, d0, z1))
	var p111 := _project(Vector3(x1, d1, z1))
	var p011 := _project(Vector3(x0, d1, z1))

	var material_colors := Pseudo3D.material(visual_profile, str(part.get("material", "")))
	var top_color := Pseudo3D.face_color(material_colors, "top", Color(0.65, 0.65, 0.65))
	var front_color := Pseudo3D.face_color(material_colors, "front", Color(0.5, 0.5, 0.5))
	var side_color := Pseudo3D.face_color(material_colors, "side", Color(0.35, 0.35, 0.35))
	var outline_color := Pseudo3D.face_color(material_colors, "outline", Color(0.1, 0.1, 0.1))

	var axis := Pseudo3D.depth_axis(visual_profile)
	if axis.x >= 0.0:
		_draw_face(PackedVector2Array([p100, p110, p111, p101]), side_color, outline_color)
	else:
		_draw_face(PackedVector2Array([p000, p010, p011, p001]), side_color, outline_color)
	_draw_face(PackedVector2Array([p001, p101, p111, p011]), top_color, outline_color)
	_draw_face(PackedVector2Array([p000, p100, p101, p001]), front_color, outline_color)


func _draw_face(points: PackedVector2Array, fill: Color, outline: Color) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, outline, 1.0, false)


func _draw_debug_marker() -> void:
	var debug: Variant = profile.get("debug", {})
	if typeof(debug) != TYPE_DICTIONARY:
		return
	var debug_config: Dictionary = debug
	var tag_material := Pseudo3D.material(visual_profile, "debug_tag")
	var tag_bg := Pseudo3D.face_color(tag_material, "background", Color(0.06, 0.08, 0.1, 1.0))
	var tag_border := Pseudo3D.face_color(tag_material, "border", Color(0.85, 0.75, 0.4, 1.0))
	var tag_text := Pseudo3D.face_color(tag_material, "text", Color(0.95, 0.89, 0.65, 1.0))
	var tag_anchor := Pseudo3D.face_color(tag_material, "anchor", Color(1.0, 0.34, 0.84, 1.0))

	if bool(debug_config.get("anchor_marker", true)):
		draw_line(Vector2(-6, 0), Vector2(6, 0), tag_anchor, 1.0, false)
		draw_line(Vector2(0, -6), Vector2(0, 6), tag_anchor, 1.0, false)

	var label := str(debug_config.get("label", "DEBUG PROP"))
	var sublabel := str(debug_config.get("sublabel", "PLACEHOLDER"))
	var text := "%s\n%s" % [label, sublabel]
	var label_offset := _read_vec2(debug_config.get("label_offset"), Vector2(-70, -200))
	var label_width := float(debug_config.get("label_width", 150))
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := 10
	var text_width := maxf(40.0, label_width - 10.0)
	var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, text_width, font_size)
	var panel_height := measured.y + 8.0
	var panel := Rect2(label_offset.x - label_width * 0.5, label_offset.y - panel_height * 0.5, label_width, panel_height)
	draw_rect(panel, tag_bg, true)
	draw_rect(panel, tag_border, false, 1.0)
	var baseline := panel.position.y + 4.0 + font.get_ascent(font_size)
	draw_multiline_string(font, Vector2(panel.position.x + 5.0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, text_width, font_size, -1, tag_text)


func _draw_missing_asset() -> void:
	var tag_material := Pseudo3D.material(visual_profile, "debug_tag")
	var tag_bg := Pseudo3D.face_color(tag_material, "background", Color(0.06, 0.08, 0.1, 1.0))
	var tag_text := Pseudo3D.face_color(tag_material, "text", Color(1.0, 0.9, 0.6, 1.0))
	var rect := Rect2(-105.0, -140.0, 210.0, 140.0)
	draw_rect(rect, Color(1.0, 0.0, 1.0, 0.12), true)
	draw_rect(rect, Color(1.0, 0.0, 1.0, 0.9), false, 1.0)
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text := "MISSING PROP PROFILE\n" + last_error
	var panel := Rect2(-150.0, -205.0, 300.0, 52.0)
	draw_rect(panel, tag_bg, true)
	draw_rect(panel, Color(1.0, 0.0, 1.0, 0.8), false, 1.0)
	draw_multiline_string(font, Vector2(panel.position.x + 5.0, panel.position.y + 4.0 + font.get_ascent(10)), text, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x - 10.0, 10, -1, tag_text)


func _project(point: Vector3) -> Vector2:
	return Pseudo3D.snap(Pseudo3D.project_local(visual_profile, point, _anchor))


func _compute_bounds() -> void:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for part_value in parts:
		var part: Dictionary = part_value
		var box: Dictionary = part.get("box", {})
		var origin := _read_vec3(box.get("origin"), Vector3.ZERO)
		var size := _read_vec3(box.get("size"), Vector3.ONE)
		for x in [origin.x, origin.x + size.x]:
			for d in [origin.y, origin.y + size.y]:
				for z in [origin.z, origin.z + size.z]:
					var point := _project(Vector3(x, d, z))
					min_point.x = minf(min_point.x, point.x)
					min_point.y = minf(min_point.y, point.y)
					max_point.x = maxf(max_point.x, point.x)
					max_point.y = maxf(max_point.y, point.y)
	if min_point.x == INF or min_point.y == INF:
		_bounds = Rect2()
		return
	_bounds = Rect2(min_point, max_point - min_point)


func _setup_shadow(shadow_config: Variant) -> void:
	for child in shadow_root.get_children():
		shadow_root.remove_child(child)
		child.queue_free()
	shadow_root.z_index = -2
	if typeof(shadow_config) != TYPE_DICTIONARY:
		return
	var cfg: Dictionary = shadow_config
	if not bool(cfg.get("enabled", true)):
		return
	shadow_root.z_index = int(cfg.get("z_index", -2))
	var shadow := ShadowView.new()
	shadow.name = "ContactShadow"
	shadow_root.add_child(shadow)
	shadow.setup(cfg, visual_profile)


func _clear() -> void:
	for child in shadow_root.get_children():
		shadow_root.remove_child(child)
		child.queue_free()
	parts.clear()
	_bounds = Rect2()
	profile = {}
	queue_redraw()


func _fail(message: String) -> bool:
	last_error = message
	_missing_asset = true
	push_error("[Pseudo3DPropView] " + message)
	queue_redraw()
	return false


func _is_valid_box(part: Dictionary) -> bool:
	var box: Variant = part.get("box", {})
	if typeof(box) != TYPE_DICTIONARY:
		return false
	var origin: Variant = (box as Dictionary).get("origin")
	var size: Variant = (box as Dictionary).get("size")
	if not _is_vec3(origin) or not _is_vec3(size):
		return false
	var size_vec := _read_vec3(size, Vector3.ZERO)
	return size_vec.x > 0.0 and size_vec.y > 0.0 and size_vec.z > 0.0


func _is_vec3(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var arr: Array = value
	if arr.size() != 3:
		return false
	for item in arr:
		if typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT:
			return false
	return true


func _read_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if not _is_vec3(value):
		return fallback
	var arr: Array = value
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var arr: Array = value
	if arr.size() != 2:
		return fallback
	return Vector2(float(arr[0]), float(arr[1]))
