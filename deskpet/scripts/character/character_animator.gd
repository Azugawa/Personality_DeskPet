class_name CharacterAnimator
extends Node
## Frame-based presentation for one character.
##
## This node owns AnimatedSprite2D concern: animation clips, fps, loop flags,
## per-clip canvas/pivot and display scale. It never chooses behaviour and never
## mutates the state machine. CharacterView is the only caller.

signal animation_finished(animation_name: String)

var current_animation: String = ""
var last_error: String = ""

var _sprite: AnimatedSprite2D = null
var _animations: Dictionary = {}
var _frames: SpriteFrames = null


func setup(sprite_node: AnimatedSprite2D, config: Dictionary) -> bool:
	last_error = ""
	_sprite = sprite_node
	_animations = {}
	current_animation = ""

	if _sprite == null:
		return _fail("AnimatedSprite2D is null.")
	if typeof(config.get("animations")) != TYPE_DICTIONARY:
		return _fail("Animation config has no 'animations' object.")

	_frames = SpriteFrames.new()
	var animations: Dictionary = config.get("animations")
	if animations.is_empty():
		return _fail("Animation config contains no clips.")

	for animation_name_value in animations.keys():
		var animation_name := str(animation_name_value)
		var clip_value: Variant = animations[animation_name]
		if typeof(clip_value) != TYPE_DICTIONARY:
			return _fail("Animation '%s' must be an object." % animation_name)
		var clip: Dictionary = clip_value
		var frame_paths: Variant = clip.get("frames", [])
		if typeof(frame_paths) != TYPE_ARRAY or (frame_paths as Array).is_empty():
			return _fail("Animation '%s' has no frames." % animation_name)

		_frames.add_animation(animation_name)
		_frames.set_animation_loop(animation_name, bool(clip.get("loop", true)))
		_frames.set_animation_speed(animation_name, maxf(0.1, float(clip.get("fps", 8.0))))

		for frame_value in (frame_paths as Array):
			var frame_path := str(frame_value)
			var texture := _load_texture(frame_path, animation_name)
			if texture == null:
				return false
			_frames.add_frame(animation_name, texture)

		_animations[animation_name] = {
			"canvas": _read_vec2(clip.get("canvas"), Vector2(256.0, 384.0)),
			"scale": maxf(0.01, float(clip.get("scale", 1.0))),
			"loop": bool(clip.get("loop", true)),
			"fps": maxf(0.1, float(clip.get("fps", 8.0))),
			"frame_count": (frame_paths as Array).size(),
		}

	_sprite.sprite_frames = _frames
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not _sprite.animation_finished.is_connected(_on_sprite_animation_finished):
		_sprite.animation_finished.connect(_on_sprite_animation_finished)
	_sprite.visible = true
	return true


func has_animation(animation_name: String) -> bool:
	return _animations.has(animation_name)


func play(animation_name: String, restart: bool = false) -> bool:
	if _sprite == null:
		return false
	if not _animations.has(animation_name):
		push_warning("[CharacterAnimator] Missing animation '%s'." % animation_name)
		return false
	if not restart and current_animation == animation_name and _sprite.is_playing():
		return true

	var clip: Dictionary = _animations[animation_name]
	var canvas: Vector2 = clip["canvas"]
	var display_scale: float = float(clip["scale"])
	_sprite.offset = Vector2(-canvas.x * 0.5, -canvas.y)
	_sprite.scale = Vector2(display_scale, display_scale)
	_sprite.play(animation_name)
	current_animation = animation_name
	return true


func stop() -> void:
	if _sprite != null:
		_sprite.stop()
	current_animation = ""


func is_playing() -> bool:
	return _sprite != null and _sprite.is_playing()


func get_current_animation() -> String:
	return current_animation


func get_frame_count(animation_name: String) -> int:
	if not _animations.has(animation_name):
		return 0
	return int((_animations[animation_name] as Dictionary).get("frame_count", 0))


func get_display_size(animation_name: String = "") -> Vector2:
	var key := animation_name if not animation_name.is_empty() else current_animation
	if not _animations.has(key):
		return Vector2.ZERO
	var clip: Dictionary = _animations[key]
	return (clip["canvas"] as Vector2) * float(clip["scale"])


func get_animation_names() -> Array:
	return _animations.keys()


func _load_texture(frame_path: String, animation_name: String) -> Texture2D:
	if frame_path.is_empty():
		_fail("Animation '%s' contains an empty frame path." % animation_name)
		return null
	if not FileAccess.file_exists(frame_path):
		_fail("Animation '%s' frame is missing: %s" % [animation_name, frame_path])
		return null
	var texture := load(frame_path) as Texture2D
	if texture == null:
		_fail("Animation '%s' frame could not be loaded: %s" % [animation_name, frame_path])
		return null
	return texture


func _on_sprite_animation_finished() -> void:
	animation_finished.emit(current_animation)


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() != 2:
		return fallback
	return Vector2(float(array[0]), float(array[1]))


func _fail(message: String) -> bool:
	last_error = message
	push_error("[CharacterAnimator] " + message)
	return false
