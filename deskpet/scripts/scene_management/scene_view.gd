class_name SceneView
extends Node2D
## Generic, data-driven presenter for one scene.
##
## SceneManager owns lifecycle/switching. SceneView only builds the scene graph
## from a validated scene config: background, one character and a list of props.
## It contains no concrete scene names, furniture logic or character animation.
##
## Ground projection is centralised in Pseudo3D: every scene object with a
## ground_position is placed on the same shared floor plane.

const CHARACTER_SCENE := preload("res://scenes/character/character.tscn")
const PROP_SCENE := preload("res://scenes/props/prop.tscn")
const PSEUDO3D_PROP_SCENE := preload("res://scenes/props/pseudo3d_prop.tscn")

@onready var background: BackgroundView = $Background
@onready var props_root: Node2D = $Props
@onready var characters_root: Node2D = $Characters
@onready var foreground: Node2D = $Foreground

var scene_id: String = ""
var character_node: Character = null
var prop_nodes: Dictionary = {}
var has_missing_assets: bool = false
var last_error: String = ""
var visual_profile: Dictionary = {}


func apply_config(config: Dictionary) -> bool:
	last_error = ""
	has_missing_assets = false
	var errors := ConfigLoader.validate_scene_config(config)
	if not errors.is_empty():
		last_error = "Invalid scene config: %s" % "; ".join(errors)
		push_error("[SceneView] " + last_error)
		return false

	_clear()
	scene_id = str(config.get("scene_id", ""))
	visual_profile = Pseudo3D.get_profile()
	if visual_profile.is_empty():
		push_error("[SceneView] Visual profile is empty; ground projection will use fallbacks.")

	var background_config: Dictionary = config.get("background", {})
	if not background.setup(background_config, _get_design_size()):
		has_missing_assets = true
		last_error = background.last_error

	var character_config: Dictionary = config.get("character", {})
	character_node = CHARACTER_SCENE.instantiate() as Character
	if character_node == null:
		last_error = "Could not instantiate character scene."
		push_error("[SceneView] " + last_error)
		return false
	character_node.name = "Character"
	characters_root.add_child(character_node)
	if _is_vec2(character_config.get("ground_position")):
		var character_ground: Array = character_config.get("ground_position")
		character_node.ground_x = float(character_ground[0])
		character_node.ground_depth = float(character_ground[1])
		character_node.position = Pseudo3D.project_ground(visual_profile, character_node.ground_x, character_node.ground_depth)
	else:
		character_node.position = _read_vec2(character_config.get("position"), Vector2(320.0, 660.0))
		character_node.ground_depth = float(character_config.get("ground_depth", 0.0))
	character_node.z_index = int(character_config.get("z_index", 20))
	if not character_node.setup(character_config):
		has_missing_assets = true
		last_error = character_node.last_error
		push_error("[SceneView] Character setup reported a problem: %s" % character_node.last_error)

	var props_config: Array = config.get("props", [])
	for prop_config_value in props_config:
		var prop_config: Dictionary = prop_config_value
		var prop_id := str(prop_config.get("id", "prop"))
		var prop_node: Node2D
		var prop_ok := false

		if _uses_pseudo3d(prop_config):
			var pseudo_prop := PSEUDO3D_PROP_SCENE.instantiate() as Pseudo3DPropView
			if pseudo_prop == null:
				push_error("[SceneView] Could not instantiate pseudo-3D prop scene for '%s'." % prop_id)
				has_missing_assets = true
				continue
			prop_node = pseudo_prop
			prop_node.name = "Prop_%s" % prop_id
			props_root.add_child(prop_node)
			pseudo_prop.ground_depth = _read_ground_depth(prop_config)
			_apply_prop_transform(prop_node, prop_config, true)
			prop_ok = pseudo_prop.setup(prop_config, visual_profile)
		else:
			var legacy_prop := PROP_SCENE.instantiate() as PropView
			if legacy_prop == null:
				push_error("[SceneView] Could not instantiate prop scene for '%s'." % prop_id)
				has_missing_assets = true
				continue
			prop_node = legacy_prop
			prop_node.name = "Prop_%s" % prop_id
			props_root.add_child(prop_node)
			_apply_prop_transform(prop_node, prop_config, false)
			prop_ok = legacy_prop.setup(prop_config)

		if not prop_ok:
			has_missing_assets = true
			last_error = str(prop_node.get("last_error"))
			push_error("[SceneView] Prop '%s' setup reported a problem: %s" % [prop_id, last_error])
		prop_nodes[prop_id] = prop_node

	print("[SceneView] Built scene '%s': background='%s' character='%s' props=%s visual='%s' missing_assets=%s" % [
		scene_id,
		str(background_config.get("type", "transparent")),
		str(character_config.get("profile", "")),
		str(prop_nodes.keys()),
		str(visual_profile.get("profile_id", "")),
		str(has_missing_assets),
	])
	return true


func teardown() -> void:
	_clear()
	scene_id = ""


func _clear() -> void:
	for prop in prop_nodes.values():
		_dispose(prop)
	prop_nodes.clear()

	_dispose(character_node)
	character_node = null

	for child in foreground.get_children():
		_dispose(child)

	background.setup({"type": "transparent"}, _get_design_size())


func _apply_prop_transform(prop: Node2D, config: Dictionary, use_ground: bool) -> void:
	if use_ground and _is_vec2(config.get("ground_position")):
		var ground: Array = config.get("ground_position")
		prop.position = Pseudo3D.project_ground(visual_profile, float(ground[0]), float(ground[1]))
	else:
		prop.position = _read_vec2(config.get("position"), Vector2.ZERO)
	prop.scale = _read_scale(config.get("scale", 1.0))
	prop.z_index = int(config.get("z_index", 0))
	prop.visible = bool(config.get("visible", true))


func _uses_pseudo3d(prop_config: Dictionary) -> bool:
	return str(prop_config.get("type", "")) == "pseudo3d_debug" or prop_config.has("profile")


func _read_ground_depth(config: Dictionary) -> float:
	var ground: Variant = config.get("ground_position")
	if _is_vec2(ground):
		var arr: Array = ground
		return float(arr[1])
	return float(config.get("ground_depth", 0.0))


func _dispose(node: Node) -> void:
	if not is_instance_valid(node):
		return
	node.visible = false
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


func _get_design_size() -> Vector2:
	var width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 640))
	var height := float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	return Vector2(width, height)


func _is_vec2(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var arr: Array = value
	return arr.size() == 2 and (typeof(arr[0]) == TYPE_INT or typeof(arr[0]) == TYPE_FLOAT) and (typeof(arr[1]) == TYPE_INT or typeof(arr[1]) == TYPE_FLOAT)


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if not _is_vec2(value):
		return fallback
	var arr: Array = value
	return Vector2(float(arr[0]), float(arr[1]))


func _read_scale(value: Variant) -> Vector2:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var scalar := float(value)
		return Vector2(scalar, scalar)
	return _read_vec2(value, Vector2.ONE)
