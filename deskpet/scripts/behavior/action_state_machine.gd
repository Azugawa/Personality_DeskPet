class_name ActionStateMachine
extends Node
## Central authority for character actions and safe manual/auto arbitrations.
##
## Long-lived presentation state (idle/walk/interact) and actions (walk_to,
## head_pat, future sit_down/stand_up) are intentionally separate from the frame
## clips played by CharacterAnimator. Manual commands outrank auto suggestions;
## auto suggestions can never replace a queued or running manual command.

signal state_changed(previous_state: String, current_state: String)
signal action_started(action_name: String, source: String)
signal action_finished(action_name: String, source: String)
signal action_cancelled(action_name: String, source: String)
signal command_rejected(action_name: String, reason: String)
signal auto_pause_changed(paused: bool)
signal rest_stage_changed(stage: String)

const MANUAL := "manual"
const AUTO := "auto"

var current_state: String = "idle"
var current_action: String = ""
var current_source: String = ""
var last_error: String = ""

var _character: Character = null
var _furniture: FurnitureManager = null
var _config: Dictionary = {}
var _busy: bool = false
var _interruptible: bool = true
var _manual_vector: Vector2 = Vector2.ZERO
var _manual_walk: bool = false
var _movement_tween: Tween = null
var _action_tween: Tween = null
var _walk_token: int = 0
var _manual_hold_until: int = 0
var _queue: Array[Dictionary] = []
var _previous_state: String = "idle"
var rest_stage: String = ""
var _rest_active: bool = false
var _rest_layers: Dictionary = {}


func setup(character: Character, furniture: FurnitureManager, behavior_config: Dictionary) -> bool:
	last_error = ""
	_character = character
	_furniture = furniture
	_config = behavior_config.duplicate(true)
	if _character == null:
		return _fail("Character is null.")
	if _furniture == null:
		return _fail("FurnitureManager is null.")
	_set_state("idle")
	return true


func _process(delta: float) -> void:
	if not _manual_walk or not _busy or current_action != "walk":
		return
	if _manual_vector.is_zero_approx():
		return
	var bounds := _walk_bounds()
	var next_position := _character.position + _manual_vector * _walk_speed() * delta
	next_position.x = clampf(next_position.x, bounds.position.x, bounds.end.x)
	next_position.y = clampf(next_position.y, bounds.position.y, bounds.end.y)
	_character.position = next_position
	var direction := Character.direction_from_vector(_manual_vector)
	if direction != _character.get_current_direction():
		_character.play_walk(direction)


func set_manual_direction(direction: Vector2) -> void:
	_set_manual_pause()
	if direction.length_squared() < 0.0001:
		if _manual_walk and current_source == MANUAL and current_action == "walk":
			_finish_action("walk", MANUAL)
		return

	if _busy:
		if current_source == AUTO and _interruptible:
			_cancel_current("manual movement")
		elif current_source == MANUAL and current_action == "walk":
			pass
		elif not _interruptible:
			_queue_command({"action": "walk_manual", "direction": [direction.x, direction.y]}, MANUAL)
			return
		elif _interruptible:
			_cancel_current("manual movement")
		else:
			_reject("walk_manual", "current action cannot be interrupted")
			return

	var normalized := direction.normalized()
	if current_state == "seated":
		_release_rest()
	var facing := Character.direction_from_vector(normalized)
	var already_manual_walking := _busy and current_source == MANUAL and current_action == "walk"
	if not (already_manual_walking and _character.get_current_direction() == facing):
		if not _character.play_walk(facing):
			_reject("walk_manual", "missing walk clip for '%s'" % facing)
			return
	if already_manual_walking:
		_manual_vector = normalized
		return

	_manual_vector = normalized
	_manual_walk = true
	_busy = true
	_interruptible = true
	current_source = MANUAL
	current_action = "walk"
	_set_state("walk")
	action_started.emit("walk", MANUAL)


func request_idle(source: String = MANUAL, direction: String = "") -> bool:
	return request_command({"action": "idle", "direction": direction}, source)


func request_walk_to(target: Vector2, source: String = MANUAL) -> bool:
	return request_command({"action": "walk_to", "target": [target.x, target.y]}, source)


func request_head_pat(source: String = MANUAL) -> bool:
	return request_command({"action": "head_pat"}, source)


func request_furniture_toggle(furniture_id: String, source: String = MANUAL) -> bool:
	return request_command({"action": "furniture_toggle", "id": furniture_id}, source)


func request_sit(source: String = MANUAL) -> bool:
	return request_command({"action": "sit"}, source)


func request_stand(source: String = MANUAL) -> bool:
	return request_command({"action": "stand"}, source)


func request_auto_walk() -> bool:
	if not can_auto_act():
		return false
	var bounds := _walk_bounds()
	var current := _character.position
	var distance_range := _read_range(_config.get("auto_walk_distance"), Vector2(45.0, 120.0))
	for _attempt in 8:
		var angle := randf_range(0.0, TAU)
		var distance := randf_range(distance_range.x, distance_range.y)
		var target := current + Vector2(cos(angle), sin(angle)) * distance
		target.x = clampf(target.x, bounds.position.x, bounds.end.x)
		target.y = clampf(target.y, bounds.position.y, bounds.end.y)
		if target.distance_to(current) >= 24.0:
			return request_walk_to(target, AUTO)
	return false


func request_auto_look() -> bool:
	if not can_auto_act():
		return false
	var directions := _character.get_available_directions()
	if directions.is_empty():
		return false
	var direction := str(directions[randi() % directions.size()])
	if not _character.set_facing(direction):
		return false
	_set_state("idle")
	return true


func can_auto_act() -> bool:
	if _busy or not _queue.is_empty():
		return false
	if Time.get_ticks_msec() < _manual_hold_until:
		return false
	return current_state == "idle" and current_action.is_empty()


func is_auto_paused() -> bool:
	return Time.get_ticks_msec() < _manual_hold_until


func get_manual_pause_remaining() -> float:
	return maxf(0.0, (_manual_hold_until - Time.get_ticks_msec()) / 1000.0)


func is_busy() -> bool:
	return _busy


func get_queued_count() -> int:
	return _queue.size()


func get_snapshot() -> Dictionary:
	return {
		"state": current_state,
		"action": current_action,
		"source": current_source,
		"busy": _busy,
		"queued": _queue.size(),
		"manual_pause": get_manual_pause_remaining(),
		"direction": _character.get_current_direction() if _character != null else "",
	}


func request_command(command: Dictionary, source: String) -> bool:
	var action_name := str(command.get("action", ""))
	if action_name.is_empty():
		_reject("unknown", "command has no action")
		return false
	if source == MANUAL:
		_set_manual_pause()
	if _busy:
		if source == AUTO:
			_reject(action_name, "character is busy with a manual action")
			return false
		if current_source == AUTO and _interruptible:
			_cancel_current("manual command")
		elif not _interruptible:
			_queue_command(command, MANUAL)
			return true
		elif current_source == MANUAL and _interruptible:
			_cancel_current("replaced by manual command")
		else:
			_reject(action_name, "action cannot be interrupted")
			return false
	return _execute(command, source)


func _execute(command: Dictionary, source: String) -> bool:
	var action_name := str(command.get("action", ""))
	match action_name:
		"idle":
			_release_rest()
			var previous_action := current_action
			var previous_source := current_source
			_walk_token += 1
			_cancel_tweens()
			_manual_walk = false
			_manual_vector = Vector2.ZERO
			_busy = false
			_interruptible = true
			current_action = ""
			current_source = ""
			if not previous_action.is_empty():
				action_finished.emit(previous_action, previous_source)
			var requested_direction := str(command.get("direction", ""))
			if not requested_direction.is_empty():
				if not _character.set_facing(requested_direction):
					_character.play_idle()
			else:
				_character.play_idle()
			_set_state("idle")
			_drain_queue()
			return true
		"walk_to":
			return _start_walk(_read_vec2(command.get("target"), _character.position), source)
		"walk_manual":
			var direction := _read_vec2(command.get("direction"), Vector2.ZERO)
			set_manual_direction(direction)
			return true
		"head_pat":
			return _start_head_pat(source)
		"furniture_toggle":
			return _toggle_furniture(str(command.get("id", "")), source)
		"sit":
			return _start_rest_sequence(source)
		"rest", "computer":
			return _start_seated_activity(action_name, source)
		"stand":
			if current_state == "seated":
				return request_idle(source, "front")
			_reject("stand", "character is not seated")
			return false
		_:
			_reject(action_name, "unknown action")
			return false


func _start_walk(target: Vector2, source: String) -> bool:
	if current_state == "seated":
		_release_rest()
	var delta := target - _character.position
	if delta.length_squared() < 4.0:
		_reject("walk_to", "target is too close")
		return false
	var direction := Character.direction_from_vector(delta)
	if not _character.play_walk(direction):
		_reject("walk_to", "missing walk clip for '%s'" % direction)
		return false

	_cancel_tweens()
	_busy = true
	_interruptible = true
	current_action = "walk"
	current_source = source
	_set_state("walk")
	action_started.emit("walk", source)

	var distance := delta.length()
	var duration := maxf(0.12, distance / _walk_speed())
	_walk_token += 1
	var token := _walk_token
	_movement_tween = create_tween()
	_movement_tween.tween_property(_character, "position", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_movement_tween.finished.connect(_on_walk_tween_finished.bind(token))
	return true


func _start_head_pat(source: String) -> bool:
	if current_state == "seated":
		_reject("head_pat", "leave the seat before this reaction")
		return false
	if not _character.has_animation("idle_" + _character.get_current_direction()):
		_reject("head_pat", "no idle clip for the current direction")
		return false
	_cancel_tweens()
	_busy = true
	_interruptible = true
	current_action = "head_pat"
	current_source = source
	_set_state("interact")
	_character.play_idle()
	_character.play_head_pat_reaction()
	action_started.emit("head_pat", source)
	_action_tween = create_tween()
	_action_tween.tween_interval(0.75)
	_action_tween.finished.connect(_on_head_pat_finished.bind(source))
	return true


func _toggle_furniture(furniture_id: String, source: String) -> bool:
	if _furniture == null or not _furniture.has_furniture(furniture_id):
		_reject("furniture_toggle", "unknown furniture '%s'" % furniture_id)
		return false
	_furniture.toggle(furniture_id)
	action_started.emit("furniture_toggle:" + furniture_id, source)
	action_finished.emit("furniture_toggle:" + furniture_id, source)
	return true


func _on_walk_tween_finished(token: int) -> void:
	if token != _walk_token:
		return
	if current_action != "walk":
		return
	_finish_action("walk", current_source)


func _on_head_pat_finished(source: String) -> void:
	if current_action != "head_pat" or current_source != source:
		return
	_finish_action("head_pat", source)


func _finish_action(action_name: String, source: String, return_to_idle: bool = true) -> void:
	var finished_action := action_name
	var finished_source := source
	_busy = false
	_manual_walk = false
	_manual_vector = Vector2.ZERO
	current_action = ""
	current_source = ""
	if return_to_idle:
		_set_state("idle")
		_character.play_idle()
	# Complete the old action before observers can begin a follow-up action.
	action_finished.emit(finished_action, finished_source)
	_drain_queue()


func _cancel_current(reason: String) -> void:
	var action_name := current_action
	var source := current_source
	_walk_token += 1
	_cancel_tweens()
	_release_rest()
	_manual_walk = false
	_manual_vector = Vector2.ZERO
	_busy = false
	_interruptible = true
	current_action = ""
	current_source = ""
	if not action_name.is_empty():
		action_cancelled.emit(action_name, source + ":" + reason)


func _cancel_tweens() -> void:
	if _movement_tween != null and _movement_tween.is_valid():
		_movement_tween.kill()
	_movement_tween = null
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	_action_tween = null


func _queue_command(command: Dictionary, source: String) -> void:
	_queue.append({"command": command.duplicate(true), "source": source})
	print("[ActionStateMachine] Queued '%s' (%s), %d pending." % [str(command.get("action", "")), source, _queue.size()])


func _drain_queue() -> void:
	if _queue.is_empty() or _busy:
		return
	var next: Dictionary = _queue.pop_front()
	var command: Dictionary = next.get("command", {})
	var source := str(next.get("source", MANUAL))
	_execute(command, source)


func _set_manual_pause() -> void:
	var was_paused := is_auto_paused()
	var seconds := maxf(0.0, float(_config.get("manual_pause_seconds", 4.0)))
	_manual_hold_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	if not was_paused:
		auto_pause_changed.emit(true)


func _set_state(new_state: String) -> void:
	if new_state == current_state:
		return
	_previous_state = current_state
	current_state = new_state
	state_changed.emit(_previous_state, current_state)


func _walk_bounds() -> Rect2:
	var values: Variant = _config.get("walk_bounds", [110, 530, 580, 660])
	if typeof(values) == TYPE_ARRAY and (values as Array).size() == 4:
		var array: Array = values
		return Rect2(float(array[0]), float(array[2]), float(array[1]) - float(array[0]), float(array[3]) - float(array[2]))
	return Rect2(110, 580, 420, 80)


func _walk_speed() -> float:
	return maxf(1.0, float(_config.get("walk_speed", 76.0)))


func _read_range(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() != 2:
		return fallback
	return Vector2(float(array[0]), float(array[1]))


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() != 2:
		return fallback
	return Vector2(float(array[0]), float(array[1]))


func _start_rest_sequence(source: String) -> bool:
	for clip in ["sit_arrive", "chair_grip", "chair_pull", "sit_align", "sit_lower", "sit_front"]:
		if not _character.has_animation(clip):
			_reject("sit", "missing authored clip: " + clip)
			return false
	var chair := _furniture.get_view("chair")
	var desk := _furniture.get_view("desk")
	if chair == null or desk == null:
		_reject("sit", "chair and desk are required")
		return false
	_release_rest()
	_cancel_tweens()
	var settings: Dictionary = _config.get("rest_sequence", {})
	var seat := _read_vec2(settings.get("seat_position"), Vector2(440, 620))
	var approach := seat + Vector2(-98, 0)
	var chair_start := seat
	var chair_end := chair_start + Vector2(0, -14)
	# Furniture transforms are set before revealing. Desk is never animated in
	# position or scale during this sequence; only its opacity changes.
	chair.position = chair_start
	desk.position = seat + Vector2(0, float(settings.get("desk_forward_offset", 50.0)))
	chair.set_direction("front")
	desk.set_direction("front")
	_furniture.set_visible("computer", false, false)
	chair.set_visible_immediate(false)
	desk.set_visible_immediate(false)
	_rest_layers = {"character": _character.z_index, "chair": chair.z_index, "desk": desk.z_index}
	var computer := _furniture.get_view("computer")
	if computer != null:
		_rest_layers["computer"] = computer.z_index
	chair.z_index = 0
	_character.z_index = 1
	desk.z_index = 2
	_rest_active = true
	_busy = true
	_interruptible = true
	_manual_walk = false
	_manual_vector = Vector2.ZERO
	current_action = "sit"
	current_source = source
	_set_state("walk")
	_set_rest_stage("approach")
	action_started.emit("sit", source)
	var duration := maxf(0.25, _character.position.distance_to(approach) / _walk_speed())
	_character.play_walk(Character.direction_from_vector(approach - _character.position))
	_action_tween = create_tween()
	_action_tween.tween_property(_character, "position", approach, duration)
	_action_tween.parallel().tween_callback(func() -> void:
		chair.set_visible_immediate(true)
		desk.set_visible_immediate(true)
		chair.modulate.a = 0.0
		desk.modulate.a = 0.0
	).set_delay(duration * 0.35)
	_action_tween.parallel().tween_property(chair, "modulate:a", 1.0, duration * 0.45).set_delay(duration * 0.4)
	_action_tween.parallel().tween_property(desk, "modulate:a", 1.0, duration * 0.45).set_delay(duration * 0.4)
	_action_tween.tween_callback(func() -> void:
		_set_state("interact")
		_rest_pose("arrive", "sit_arrive")
	)
	_action_tween.tween_interval(0.18)
	_action_tween.tween_callback(_rest_pose.bind("grip", "chair_grip"))
	_action_tween.tween_interval(0.28)
	_action_tween.tween_callback(_rest_pose.bind("pull", "chair_pull"))
	_action_tween.tween_property(chair, "position", chair_end, 0.42).set_trans(Tween.TRANS_SINE)
	_action_tween.tween_interval(0.12)
	_action_tween.tween_callback(func() -> void:
		_set_rest_stage("enter_gap")
		_character.play_walk("right")
	)
	_action_tween.tween_property(_character, "position", seat, 1.05)
	_action_tween.tween_callback(_rest_pose.bind("turn", "sit_turn"))
	_action_tween.tween_interval(0.14)
	_action_tween.tween_callback(_rest_pose.bind("align", "sit_align"))
	_action_tween.tween_interval(0.18)
	_action_tween.tween_callback(_rest_pose.bind("lower", "sit_lower"))
	_action_tween.tween_interval(0.22)
	_action_tween.tween_callback(func() -> void:
		_rest_pose("seated", "sit_front")
		_character.current_direction = "front"
		_set_state("seated")
		_finish_action("sit", source, false)
	)
	return true


func _rest_pose(stage: String, clip: String) -> void:
	_set_rest_stage(stage)
	_character.play_animation(clip)


func _start_seated_activity(activity: String, source: String) -> bool:
	if current_state != "seated":
		_reject(activity, "sit down before starting a seated activity")
		return false
	var clips := ["rest_enter", "rest_loop"] if activity == "rest" else ["computer_sit_right", "computer_reach", "computer_type"]
	for clip in clips:
		if not _character.has_animation(clip):
			_reject(activity, "missing clip: " + clip)
			return false
	_cancel_tweens()
	_busy = true
	_interruptible = true
	current_action = activity
	current_source = source
	action_started.emit(activity, source)
	_action_tween = create_tween()
	if activity == "rest":
		_furniture.set_visible("computer", false, false)
		_furniture.set_visible("desk", true, false)
		_furniture.get_view("chair").set_direction("front")
		_character.current_direction = "front"
		_rest_pose("lean", "rest_enter")
		_action_tween.tween_interval(0.5)
		_action_tween.tween_callback(_rest_pose.bind("resting", "rest_loop"))
	else:
		var computer := _furniture.get_view("computer")
		if computer == null:
			_finish_action(activity, source, false)
			return false
		_furniture.set_visible("desk", false, false)
		_furniture.get_view("chair").set_direction("right")
		computer.set_direction("right")
		computer.position = _character.position + Vector2(120, 28)
		computer.z_index = 2
		computer.set_visible_immediate(true)
		_character.current_direction = "right"
		_rest_pose("computer_seated", "computer_sit_right")
		_action_tween.tween_interval(0.2)
		_action_tween.tween_callback(_rest_pose.bind("reach_keyboard", "computer_reach"))
		_action_tween.tween_interval(0.25)
		_action_tween.tween_callback(_rest_pose.bind("typing", "computer_type"))
	_action_tween.tween_callback(func() -> void: _finish_action(activity, source, false))
	return true


func _set_rest_stage(stage: String) -> void:
	rest_stage = stage
	rest_stage_changed.emit(stage)


func _release_rest() -> void:
	if not _rest_active:
		return
	_rest_active = false
	_character.z_index = int(_rest_layers.get("character", 0))
	for id in ["chair", "desk", "computer"]:
		var view := _furniture.get_view(id)
		if view != null:
			view.z_index = int(_rest_layers.get(id, 0))
			view.set_visible_immediate(view.visible)
	_rest_layers.clear()
	_set_rest_stage("")


func _reject(action_name: String, reason: String) -> void:
	last_error = reason
	push_warning("[ActionStateMachine] Rejected '%s': %s" % [action_name, reason])
	command_rejected.emit(action_name, reason)


func _fail(message: String) -> bool:
	last_error = message
	push_error("[ActionStateMachine] " + message)
	return false
