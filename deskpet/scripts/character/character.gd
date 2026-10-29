class_name Character
extends Node2D
## Reusable character presenter.
##
## The preferred mode is `sprite_frames`, backed by CharacterAnimator,
## AnimatedSprite2D and the configuration in config/animations/spirit.json.
## The old single full-body PNG path remains as a safe fallback for profiles
## that do not provide an animation set.
##
## Behaviour selection, movement and furniture coordination belong to
## ActionStateMachine / BehaviorBrain, not to this node.

signal state_changed(new_state: String)
signal animation_changed(animation_name: String)
signal animation_finished(animation_name: String)
signal asset_load_failed(message: String)

@onready var shadow_root: Node2D = $ShadowRoot
@onready var body_root: Node2D = $BodyRoot
@onready var animated_body: AnimatedSprite2D = $BodyRoot/AnimatedBody
@onready var full_body_sprite: Sprite2D = $BodyRoot/FullBodySprite
@onready var parts_root: Node2D = $BodyRoot/PartsRoot
@onready var animator: CharacterAnimator = $Animator

var profile: Dictionary = {}
var profile_path: String = ""
var current_state: String = "idle"
var current_direction: String = "front"
var current_animation: String = ""
var last_error: String = ""
var missing_indicator: Label = null

var ground_x: float = 0.0
var ground_depth: float = 0.0

var _body_scale: float = 0.25
var _facing_sign: float = 1.0
var _content_bounds: Rect2 = Rect2(406.0, 86.0, 1231.0, 1871.0)
var _canvas_size: Vector2 = Vector2(2048.0, 2048.0)
var _animations_config: Dictionary = {}
var _available_directions: Array = []
var _use_animator: bool = false
var _reaction_tween: Tween = null


func _ready() -> void:
	if animator != null:
		animator.animation_finished.connect(_on_animator_finished)


func setup(scene_character_config: Dictionary) -> bool:
	last_error = ""
	current_state = "idle"
	current_direction = "front"
	_facing_sign = 1.0
	_hide_missing_indicator()
	_clear_shadow()
	body_root.visible = true
	body_root.position = Vector2.ZERO
	body_root.scale = Vector2.ONE

	profile_path = str(scene_character_config.get("profile", "res://config/characters/spirit.json"))
	profile = ConfigLoader.load_json(profile_path)
	if profile.is_empty():
		return _fail_asset("Character profile could not be loaded: %s (%s)" % [profile_path, ConfigLoader.last_error])

	var render_mode := str(profile.get("render_mode", "full_body"))
	if render_mode == "sprite_frames":
		if _setup_animations():
			_setup_shadow(scene_character_config.get("shadow", {}))
			_apply_initial_direction_and_state(scene_character_config)
			print("[Character] Ready: profile='%s' mode='sprite_frames' state='%s' direction='%s' clips=%d" % [
				str(profile.get("character_id", "?")), current_state, current_direction, animator.get_animation_names().size()
			])
			return true
		push_warning("[Character] Animation setup failed; falling back to the legacy full-body texture.")
	elif render_mode != "full_body":
		push_warning("[Character] render_mode '%s' is unknown; trying full_body fallback." % render_mode)

	if not _setup_full_body(scene_character_config):
		return false
	_setup_shadow(scene_character_config.get("shadow", {}))
	var facing := str(scene_character_config.get("facing", profile.get("default_facing", "front")))
	if not set_facing(facing):
		set_facing("front")
	var state := str(scene_character_config.get("state", profile.get("default_state", "idle")))
	if not set_state(state):
		set_state("idle")
	print("[Character] Ready: profile='%s' mode='full_body' state='%s' scale=%s content=%s" % [
		str(profile.get("character_id", "?")), current_state, str(_body_scale), str(_content_bounds.size)
	])
	return true


func _setup_animations() -> bool:
	var animations_path := str(profile.get("animations", ""))
	if animations_path.is_empty():
		return false
	if not FileAccess.file_exists(animations_path):
		last_error = "Animation config is missing: %s" % animations_path
		push_error("[Character] " + last_error)
		return false
	_animations_config = ConfigLoader.load_json(animations_path)
	if _animations_config.is_empty():
		last_error = "Animation config could not be loaded: %s (%s)" % [animations_path, ConfigLoader.last_error]
		push_error("[Character] " + last_error)
		return false
	if not animator.setup(animated_body, _animations_config):
		last_error = animator.last_error
		push_error("[Character] " + last_error)
		return false

	_use_animator = true
	_available_directions = _animations_config.get("directions", []).duplicate()
	full_body_sprite.visible = false
	full_body_sprite.texture = null
	animated_body.visible = true
	body_root.scale = Vector2.ONE
	return true


func _setup_full_body(scene_character_config: Dictionary) -> bool:
	_use_animator = false
	animator.stop()
	animated_body.visible = false
	var texture_path := str(profile.get("texture", ""))
	if texture_path.is_empty():
		return _fail_asset("Character profile '%s' does not define a texture path." % profile_path)
	if not ResourceLoader.exists(texture_path):
		return _fail_asset("Character texture file is missing: %s" % texture_path)
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return _fail_asset("Character texture exists but could not be loaded as Texture2D: %s" % texture_path)

	_canvas_size = _read_vec2(profile.get("canvas_size"), Vector2(2048.0, 2048.0))
	_content_bounds = _read_rect(profile.get("content_bounds"), Rect2(406.0, 86.0, 1231.0, 1871.0))
	if _content_bounds.size.x <= 0.0 or _content_bounds.size.y <= 0.0:
		return _fail_asset("Character content_bounds must have positive width and height (got %s)." % str(_content_bounds))

	var fallback_scale := float(profile.get("default_scale", 0.25))
	var configured_scale := float(scene_character_config.get("scale", fallback_scale))
	if configured_scale <= 0.0:
		configured_scale = fallback_scale
	_body_scale = configured_scale

	full_body_sprite.centered = false
	full_body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	full_body_sprite.texture = texture
	full_body_sprite.position = -_get_anchor_offset()
	full_body_sprite.visible = true
	_apply_body_transform()
	return true


func _apply_initial_direction_and_state(scene_character_config: Dictionary) -> void:
	var facing := str(scene_character_config.get("facing", profile.get("default_facing", "front")))
	if not set_facing(facing):
		set_facing("front")
	var state := str(scene_character_config.get("state", profile.get("default_state", "idle")))
	if not set_state(state):
		set_state("idle")


func set_state(new_state: String) -> bool:
	var states: Variant = profile.get("states", {})
	if typeof(states) == TYPE_DICTIONARY and (states as Dictionary).has(new_state):
		current_state = new_state
		state_changed.emit(new_state)
		if new_state == "idle" and _use_animator:
			play_idle()
		return true
	push_warning("[Character] State '%s' is not declared in profile '%s'." % [new_state, profile_path])
	return false


func set_facing(direction: String) -> bool:
	if _use_animator:
		if not _available_directions.has(direction):
			push_warning("[Character] Unsupported direction '%s' for this animation set." % direction)
			return false
		current_direction = direction
		play_idle(direction)
		return true
	if direction != "front" and direction != "left" and direction != "right":
		push_warning("[Character] Legacy full-body mode only supports front/left/right; got '%s'." % direction)
		return false
	current_direction = direction
	_facing_sign = -1.0 if direction == "left" else 1.0
	_apply_body_transform()
	return true


func play_idle(direction: String = "") -> bool:
	if not _use_animator:
		return false
	var target_direction := current_direction if direction.is_empty() else direction
	var idle_map: Dictionary = _animations_config.get("direction_idle", {})
	var animation := str(idle_map.get(target_direction, ""))
	if animation.is_empty():
		return false
	current_direction = target_direction
	if not animator.play(animation, true):
		return false
	current_animation = animation
	animation_changed.emit(animation)
	return true


func play_walk(direction: String) -> bool:
	if not _use_animator:
		return false
	var walk_map: Dictionary = _animations_config.get("direction_walk", {})
	var animation := str(walk_map.get(direction, ""))
	if animation.is_empty():
		push_warning("[Character] No walk clip for direction '%s'." % direction)
		return false
	current_direction = direction
	if not animator.play(animation, true):
		return false
	current_animation = animation
	animation_changed.emit(animation)
	return true


func play_animation(animation_name: String, restart: bool = true) -> bool:
	if not _use_animator:
		push_warning("[Character] Animation '%s' requested without an animation set." % animation_name)
		return false
	if not animator.play(animation_name, restart):
		return false
	current_animation = animation_name
	animation_changed.emit(animation_name)
	return true


func has_animation(animation_name: String) -> bool:
	return _use_animator and animator.has_animation(animation_name)


func get_animation_names() -> Array:
	return animator.get_animation_names() if _use_animator else []


func get_available_directions() -> Array:
	return _available_directions.duplicate()


func get_current_direction() -> String:
	return current_direction


func get_current_animation() -> String:
	return current_animation


func get_texture() -> Texture2D:
	if _use_animator and animated_body.sprite_frames != null:
		return animated_body.sprite_frames.get_frame_texture(animated_body.animation, animated_body.frame)
	return full_body_sprite.texture


func get_texture_path() -> String:
	return str(profile.get("texture", ""))


func get_content_size() -> Vector2:
	if _use_animator:
		return animator.get_display_size()
	return Vector2(absf(_content_bounds.size.x * _body_scale), absf(_content_bounds.size.y * _body_scale))


func get_ground_depth() -> float:
	return ground_depth


func get_screen_bounds() -> Rect2:
	var content := get_content_size()
	return Rect2(global_position + Vector2(-content.x * 0.5, -content.y), content)


func get_feet_anchor() -> Vector2:
	return global_position


func is_using_animations() -> bool:
	return _use_animator


func is_asset_missing() -> bool:
	return missing_indicator != null and missing_indicator.visible


## Short placeholder reaction for the manual head-pat command. A dedicated
## authored reaction clip can replace this without changing the state machine.
func play_head_pat_reaction() -> void:
	if _reaction_tween != null:
		_reaction_tween.kill()
	body_root.position = Vector2.ZERO
	_reaction_tween = create_tween()
	_reaction_tween.tween_property(body_root, "position", Vector2(0, 4), 0.08)
	_reaction_tween.tween_property(body_root, "position", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func request_animation(animation_id: String) -> bool:
	return play_animation(animation_id)


func set_part_pose(part_name: String, rotation_degrees_value: float) -> bool:
	push_warning("[Character] Part pose '%s' (%.2f deg) refused: part rig status is NEEDS_REVIEW." % [part_name, rotation_degrees_value])
	return false


static func direction_from_vector(vector: Vector2) -> String:
	if vector.length_squared() < 0.0001:
		return "front"
	var angle := rad_to_deg(atan2(vector.y, vector.x))
	if angle >= -22.5 and angle < 22.5:
		return "right"
	if angle >= 22.5 and angle < 67.5:
		return "front_right"
	if angle >= 67.5 and angle < 112.5:
		return "front"
	if angle >= 112.5 and angle < 157.5:
		return "front_left"
	if angle >= 157.5 or angle < -157.5:
		return "left"
	if angle >= -157.5 and angle < -112.5:
		return "back_left"
	if angle >= -112.5 and angle < -67.5:
		return "back"
	return "back_right"


func _apply_body_transform() -> void:
	body_root.scale = Vector2(_body_scale * _facing_sign, _body_scale)


func _on_animator_finished(animation_name: String) -> void:
	animation_finished.emit(animation_name)


func _get_anchor_offset() -> Vector2:
	var anchor_name := str(profile.get("anchor", "content_bottom_center"))
	match anchor_name:
		"canvas_bottom_center":
			return Vector2(_canvas_size.x * 0.5, _canvas_size.y)
		"content_bottom_center":
			return Vector2(_content_bounds.position.x + _content_bounds.size.x * 0.5, _content_bounds.position.y + _content_bounds.size.y)
		_:
			return Vector2(_content_bounds.position.x + _content_bounds.size.x * 0.5, _content_bounds.position.y + _content_bounds.size.y)


func _setup_shadow(shadow_config: Variant) -> void:
	_clear_shadow()
	if typeof(shadow_config) != TYPE_DICTIONARY:
		return
	var cfg: Dictionary = shadow_config
	shadow_root.z_index = int(cfg.get("z_index", -5))
	var shadow := ShadowView.new()
	shadow.name = "ContactShadow"
	shadow_root.add_child(shadow)
	if not shadow.setup(cfg):
		push_warning("[Character] Shadow configuration was not accepted; shadow skipped.")


func _clear_shadow() -> void:
	for child in shadow_root.get_children():
		shadow_root.remove_child(child)
		child.queue_free()


func _fail_asset(message: String) -> bool:
	last_error = message
	body_root.visible = false
	_clear_shadow()
	_show_missing_indicator(message)
	push_error("[Character] " + message)
	asset_load_failed.emit(message)
	return false


func _show_missing_indicator(message: String) -> void:
	if missing_indicator == null or not is_instance_valid(missing_indicator):
		missing_indicator = Label.new()
		missing_indicator.name = "MissingAssetIndicator"
		missing_indicator.position = Vector2(-190.0, -130.0)
		missing_indicator.size = Vector2(380.0, 120.0)
		missing_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		missing_indicator.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		missing_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		missing_indicator.z_index = 100
		missing_indicator.add_theme_font_size_override("font_size", 12)
		missing_indicator.add_theme_color_override("font_color", Color.WHITE)
		missing_indicator.add_theme_color_override("font_outline_color", Color.BLACK)
		missing_indicator.add_theme_constant_override("outline_size", 4)
		add_child(missing_indicator)
	missing_indicator.text = "MISSING CHARACTER ASSET\n" + message
	missing_indicator.visible = true


func _hide_missing_indicator() -> void:
	if missing_indicator != null and is_instance_valid(missing_indicator):
		missing_indicator.visible = false


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() != 2:
		return fallback
	return Vector2(float(array[0]), float(array[1]))


func _read_rect(value: Variant, fallback: Rect2) -> Rect2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() != 4:
		return fallback
	return Rect2(float(array[0]), float(array[1]), float(array[2]), float(array[3]))
