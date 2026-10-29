class_name PetActivityController
extends Node
## Data-driven bridge between right-click activities, furniture presentation and
## the character state machine.
##
## A selected activity can reveal furniture slowly and walk the character to an
## approach anchor. If the authored seated clip is missing, the controller stops
## at the chair and emits activity_waiting instead of faking a sit pose.

signal activity_started(activity_id: String)
signal activity_waiting(activity_id: String, reason: String)
signal activity_finished(activity_id: String)

var _state_machine: ActionStateMachine = null
var _furniture: FurnitureManager = null
var _character: Character = null
var _activities: Array = []
var current_activity: String = "idle"
var transitioning: bool = false

var _pending_id: String = ""
var _pending_activity: Dictionary = {}


func setup(
	state_machine: ActionStateMachine,
	furniture: FurnitureManager,
	character: Character,
	config: Dictionary
) -> bool:
	_state_machine = state_machine
	_furniture = furniture
	_character = character
	var activities_value: Variant = config.get("activities", [])
	if typeof(activities_value) != TYPE_ARRAY:
		push_error("[PetActivityController] activities must be an array.")
		return false
	_activities = (activities_value as Array).duplicate(true)
	if _state_machine == null or _furniture == null or _character == null:
		push_error("[PetActivityController] Missing runtime dependency.")
		return false
	_state_machine.action_finished.connect(_on_action_finished)
	_state_machine.action_cancelled.connect(_on_action_cancelled)
	return true


func get_menu_entries() -> Array:
	var entries: Array = []
	var busy := false # transient reactions can be interrupted by an activity
	for activity_value in _activities:
		var activity: Dictionary = activity_value
		var activity_id := str(activity.get("id", ""))
		if activity_id == current_activity:
			continue
		var label := str(activity.get("label", activity_id))
		var required_furniture: Array = activity.get("required_furniture", [])
		var missing_furniture := false
		for furniture_id_value in required_furniture:
			if not _furniture.has_furniture(str(furniture_id_value)):
				missing_furniture = true
				break
		var required_animation := str(activity.get("required_animation", ""))
		var missing_animation := not required_animation.is_empty() and not _character.has_animation(required_animation)
		if missing_animation:
			label += "（坐姿待补）"
		var enabled := not transitioning and not busy and not missing_furniture
		entries.append({
			"id": activity_id,
			"label": label,
			"enabled": enabled,
			"partial": missing_animation,
			"reason": "missing required furniture" if missing_furniture else ("missing " + required_animation if missing_animation else ""),
		})
	return entries


func request(activity_id: String) -> bool:
	var activity := _find_activity(activity_id)
	if activity.is_empty():
		push_warning("[PetActivityController] Unknown activity '%s'." % activity_id)
		return false
	if transitioning:
		return false
	transitioning = true
	_run_transition(activity_id, activity)
	return true


func _run_transition(activity_id: String, activity: Dictionary) -> void:
	activity_started.emit(activity_id)
	if current_activity != "idle":
		await _reverse_entry()
	_state_machine.request_idle(ActionStateMachine.MANUAL)
	for id in ["desk", "chair", "computer"]:
		_furniture.set_visible(id, false, false)
	_character.play_walk("right")
	await get_tree().create_timer(0.9).timeout
	current_activity = activity_id
	if activity_id == "idle":
		_character.play_idle("front")
		transitioning = false
		activity_finished.emit(activity_id)
		return
	if activity_id == "computer":
		_state_machine._set_state("seated")
		_furniture.get_view("chair").set_visible_immediate(true)
		_pending_id = activity_id
		_pending_activity = activity
		_state_machine.request_command({"action": "computer"}, ActionStateMachine.MANUAL)
		return
	_pending_id = activity_id
	_pending_activity = activity
	if not _state_machine.request_sit(ActionStateMachine.MANUAL):
		current_activity = "idle"
		_pending_id = ""
		transitioning = false


func get_pending_id() -> String:
	return _pending_id


func get_activity_snapshot() -> Array:
	var result := []
	for activity_value in _activities:
		var activity: Dictionary = activity_value
		result.append({
			"id": str(activity.get("id", "")),
			"label": str(activity.get("label", "")),
			"required_animation": str(activity.get("required_animation", "")),
		})
	return result


func _on_action_finished(action_name: String, _source: String) -> void:
	if not _pending_id.is_empty() and action_name == "sit":
		var followup := str(_pending_activity.get("followup", ""))
		if not followup.is_empty() and _state_machine.request_command({"action": followup}, ActionStateMachine.MANUAL):
			return
		var finished_id := _pending_id
		_pending_id = ""
		_pending_activity = {}
		transitioning = false
		activity_finished.emit(finished_id)
		return
	if not _pending_id.is_empty() and action_name in ["rest", "computer"]:
		var finished_id := _pending_id
		_pending_id = ""
		_pending_activity = {}
		transitioning = false
		activity_finished.emit(finished_id)
		return
	if _pending_id.is_empty() or action_name != "walk":
		return
	var activity_id := _pending_id
	var activity := _pending_activity
	_pending_id = ""
	_pending_activity = {}
	var required_animation := str(activity.get("required_animation", ""))
	if required_animation.is_empty() or _character.has_animation(required_animation):
		# Future path: align to the seat anchor and run sit_down here. Until an
		# authored seated clip exists, the controller deliberately stops at the
		# chair instead of using a standing image as a fake sit.
		if not required_animation.is_empty():
			activity_waiting.emit(activity_id, "seated animation is not implemented yet")
	else:
		activity_waiting.emit(activity_id, "missing seated animation '%s'" % required_animation)
	activity_finished.emit(activity_id)


func _on_action_cancelled(action_name: String, _reason: String) -> void:
	if _pending_id.is_empty() or action_name not in ["walk", "sit", "rest", "computer"]:
		return
	transitioning = false
	current_activity = "idle"
	var activity_id := _pending_id
	_pending_id = ""
	_pending_activity = {}
	activity_finished.emit(activity_id)


func _find_activity(activity_id: String) -> Dictionary:
	for activity_value in _activities:
		var activity: Dictionary = activity_value
		if str(activity.get("id", "")) == activity_id:
			return activity
	return {}


func _reverse_clip(clip: String, seconds: float) -> void:
	_character.play_animation(clip)
	_character.animated_body.play(clip, -1.0, true)
	await get_tree().create_timer(seconds).timeout


func _reverse_entry() -> void:
	if current_activity == "rest":
		await _reverse_clip("rest_enter", 0.5)
	else:
		await _reverse_clip("computer_reach", 0.25)
		await _reverse_clip("computer_sit_right", 0.2)
		return
	var chair := _furniture.get_view("chair")
	chair.set_direction("front")
	chair.position = _character.position + Vector2(0, -14)
	await _reverse_clip("sit_lower", 0.22)
	await _reverse_clip("sit_align", 0.18)
	await _reverse_clip("sit_turn", 0.14)
	_character.play_walk("left")
	var seat := _character.position
	var tween := create_tween()
	var distance := float(_state_machine._config.get("rest_sequence", {}).get("chair_reach_distance", 75.0))
	tween.tween_property(chair, "position:x", chair.position.x + distance, 1.05)
	var desk := _furniture.get_view("desk")
	tween.parallel().tween_property(desk, "position:x", desk.position.x + distance, 1.05)
	await tween.finished
	_character.play_animation("chair_pull")
	tween = create_tween()
	tween.tween_property(chair, "position:y", seat.y, 0.42)
	await tween.finished
	await _reverse_clip("chair_grip", 0.28)
	await _reverse_clip("sit_arrive", 0.18)
