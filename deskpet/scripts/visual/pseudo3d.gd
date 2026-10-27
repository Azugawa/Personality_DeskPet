class_name Pseudo3D
extends RefCounted
## Shared 2.5D projection rules and palette access.
##
## Ground coordinates: x = lateral screen direction, depth = away from camera.
## World height: z = up. This is an orthographic oblique projection, so objects
## do not shrink with depth; the visual language relies on depth offset, overlap
## and shadows instead of perspective scaling.
##
## The character is intentionally a front-facing billboard. Furniture uses the
## same ground axis, so its top/front/right faces form one consistent space.

const DEFAULT_PROFILE_PATH := "res://config/visual/pseudo3d.json"

static var _profile: Dictionary = {}


static func get_profile() -> Dictionary:
	if _profile.is_empty():
		_profile = ConfigLoader.load_json(DEFAULT_PROFILE_PATH)
		if _profile.is_empty():
			push_error("[Pseudo3D] Could not load visual profile: %s (%s)" % [DEFAULT_PROFILE_PATH, ConfigLoader.last_error])
	return _profile


static func reload_profile() -> void:
	_profile = {}


static func ground_config(profile: Dictionary) -> Dictionary:
	if typeof(profile.get("ground")) == TYPE_DICTIONARY:
		return profile.get("ground")
	return {}


static func floor_guide(profile: Dictionary) -> Dictionary:
	if typeof(profile.get("floor_guide")) == TYPE_DICTIONARY:
		return profile.get("floor_guide")
	return {}


static func front_y(profile: Dictionary) -> float:
	return float(ground_config(profile).get("front_y", 660.0))


static func depth_axis(profile: Dictionary) -> Vector2:
	var ground := ground_config(profile)
	var axis: Variant = ground.get("depth_axis", [0.55, -0.35])
	if typeof(axis) == TYPE_ARRAY and (axis as Array).size() == 2:
		var arr: Array = axis
		return Vector2(float(arr[0]), float(arr[1]))
	return Vector2(0.55, -0.35)


static func project_ground(profile: Dictionary, x: float, depth: float) -> Vector2:
	var ground := ground_config(profile)
	var axis := depth_axis(profile)
	var origin_x := float(ground.get("x_origin", 0.0))
	var base_y := float(ground.get("front_y", 660.0))
	return Vector2(origin_x + x + depth * axis.x, base_y + depth * axis.y)


## Projects a local point (x lateral, y depth, z height) relative to an anchor.
## The result is a screen-space offset from the object's ground anchor.
static func project_local(profile: Dictionary, point: Vector3, anchor: Vector3) -> Vector2:
	var axis := depth_axis(profile)
	var local_x := point.x - anchor.x
	var local_depth := point.y - anchor.y
	var local_z := point.z - anchor.z
	return Vector2(local_x + local_depth * axis.x, local_depth * axis.y - local_z)


static func material(profile: Dictionary, material_name: String) -> Dictionary:
	var palette: Variant = profile.get("palette", {})
	if typeof(palette) != TYPE_DICTIONARY:
		return {}
	var materials: Dictionary = palette
	var value: Variant = materials.get(material_name, {})
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func face_color(material_colors: Dictionary, face: String, fallback: Color) -> Color:
	return Color.from_string(str(material_colors.get(face, "")), fallback)


static func snap(value: Vector2) -> Vector2:
	return Vector2(roundf(value.x), roundf(value.y))


static func depth_screen_angle_degrees(profile: Dictionary) -> float:
	var axis := depth_axis(profile)
	return rad_to_deg(atan2(-axis.y, axis.x))
