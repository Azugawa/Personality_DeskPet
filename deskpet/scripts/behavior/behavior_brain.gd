class_name BehaviorBrain
extends Node
## Lightweight automatic behaviour selector.
##
## It proposes small idle/look and walk actions only while the state machine is
## idle and no manual command is pending. Manual commands always take priority;
## this node never mutates the character transform directly.

signal auto_enabled_changed(enabled: bool)
signal decision_made(decision: String)

var enabled: bool = true

var _state_machine: ActionStateMachine = null
var _config: Dictionary = {}
var _timer: float = 0.0
var _last_decision: String = ""
var _cooldowns_until: Dictionary = {}


func setup(state_machine: ActionStateMachine, config: Dictionary) -> bool:
	_state_machine = state_machine
	_config = config.duplicate(true)
	if _state_machine == null:
		push_error("[BehaviorBrain] State machine is null.")
		return false
	enabled = bool(_config.get("auto_enabled", true))
	_reset_timer()
	return true


func _process(delta: float) -> void:
	if not enabled or _state_machine == null:
		return
	if not _state_machine.can_auto_act():
		return
	_timer -= delta
	if _timer > 0.0:
		return

	var can_walk := _cooldown_ready("walk")
	var can_look := _cooldown_ready("look")
	if not can_walk and not can_look:
		_timer = 0.5
		return
	var walk_chance := clampf(float(_config.get("walk_chance", 0.35)), 0.0, 1.0)
	if can_walk and (not can_look or randf() < walk_chance):
		if _state_machine.request_auto_walk():
			_set_cooldown("walk")
			_last_decision = "walk"
			decision_made.emit(_last_decision)
		else:
			_timer = 0.8
			return
	else:
		if _state_machine.request_auto_look():
			_set_cooldown("look")
			_last_decision = "look"
			decision_made.emit(_last_decision)
	_reset_timer()


func set_auto_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	auto_enabled_changed.emit(enabled)
	_reset_timer()


func toggle_auto() -> void:
	set_auto_enabled(not enabled)


func is_auto_enabled() -> bool:
	return enabled


func get_last_decision() -> String:
	return _last_decision


func get_snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"timer": _timer,
		"last_decision": _last_decision,
		"walk_ready": _cooldown_ready("walk"),
		"look_ready": _cooldown_ready("look"),
	}


func _cooldown_ready(action_name: String) -> bool:
	return Time.get_ticks_msec() >= int(_cooldowns_until.get(action_name, 0))


func _set_cooldown(action_name: String) -> void:
	var cooldowns: Variant = _config.get("cooldowns_seconds", {})
	if typeof(cooldowns) != TYPE_DICTIONARY:
		return
	var seconds := maxf(0.0, float((cooldowns as Dictionary).get(action_name, 0.0)))
	_cooldowns_until[action_name] = Time.get_ticks_msec() + int(seconds * 1000.0)


func _reset_timer() -> void:
	var delay_value: Variant = _config.get("idle_delay_seconds", [2.0, 4.5])
	var low := 2.0
	var high := 4.5
	if typeof(delay_value) == TYPE_ARRAY and (delay_value as Array).size() == 2:
		var array: Array = delay_value
		low = maxf(0.2, float(array[0]))
		high = maxf(low, float(array[1]))
	_timer = randf_range(low, high)
