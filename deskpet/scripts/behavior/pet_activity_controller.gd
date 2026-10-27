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
	var busy := _state_machine != null and _state_machine.is_busy()
	for activity_value in _activities:
		var activity: Dictionary = activity_value
		var activity_id := str(activity.get("id", ""))
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
		var enabled := activity_id == "idle" or (not busy and not missing_furniture)
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
	if activity_id == "idle":
		return _state_machine.request_idle(ActionStateMachine.MANUAL)
	if _state_machine == null or _state_machine.is_busy():
		push_warning("[PetActivityController] Activity '%s' rejected while the character is busy." % activity_id)
		return false

	var required_furniture: Array = activity.get("required_furniture", [])
	for furniture_id_value in required_furniture:
		if not _furniture.has_furniture(str(furniture_id_value)):
			push_warning("[PetActivityController] Activity '%s' missing furniture '%s'." % [activity_id, str(furniture_id_value)])
			return false

	var reveal_seconds := maxf(0.0, float(activity.get("reveal_seconds", 0.9)))
	for hide_value in activity.get("hide_furniture", []):
		_furniture.set_visible(str(hide_value), false, true, 0.3)
	for show_value in activity.get("show_furniture", []):
		_furniture.set_visible(str(show_value), true, true, reveal_seconds)

	var approach_furniture := str(activity.get("approach_furniture", ""))
	var approach := _furniture.get_approach_position(approach_furniture)
	if approach == Vector2.ZERO:
		approach = _character.position + Vector2(80, 0)
	_pending_id = activity_id
	_pending_activity = activity
	activity_started.emit(activity_id)
	if not _state_machine.request_walk_to(approach, ActionStateMachine.MANUAL):
		_pending_id = ""
		_pending_activity = {}
		return false
	return true


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
	if _pending_id.is_empty() or action_name != "walk":
		return
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
