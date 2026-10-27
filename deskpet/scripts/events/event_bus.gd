extends Node
## Global, config-agnostic event bus.
##
## Gameplay events are emitted as game_event(name, payload). SceneManager listens
## to game_event and applies each scene's allow-list/transition rules. Lifecycle
## notifications use system_event, so they can never trigger a gameplay transition.
##
## The four reserved demo events also have typed signals for convenience.

signal workspace_requested(payload: Dictionary)
signal furniture_ready(payload: Dictionary)
signal sit_requested(payload: Dictionary)
signal sit_completed(payload: Dictionary)

signal game_event(event_name: String, payload: Dictionary)
signal system_event(event_name: String, payload: Dictionary)
signal scene_change_requested(scene_id: String, reason: String)

const RESERVED_EVENTS := [
	"workspace_requested",
	"furniture_ready",
	"sit_requested",
	"sit_completed",
]

var _event_count: int = 0


func emit_game_event(event_name: String, payload: Dictionary = {}) -> void:
	var clean_name := event_name.strip_edges()
	if clean_name.is_empty():
		push_error("[EventBus] Refusing to emit an event with an empty name.")
		return

	_event_count += 1
	print("[EventBus] game event #%d: %s payload=%s" % [_event_count, clean_name, JSON.stringify(payload)])

	game_event.emit(clean_name, payload)

	match clean_name:
		"workspace_requested":
			workspace_requested.emit(payload)
		"furniture_ready":
			furniture_ready.emit(payload)
		"sit_requested":
			sit_requested.emit(payload)
		"sit_completed":
			sit_completed.emit(payload)
		_:
			print("[EventBus] note: '%s' has no typed convenience signal." % clean_name)


func emit_system_event(event_name: String, payload: Dictionary = {}) -> void:
	var clean_name := event_name.strip_edges()
	if clean_name.is_empty():
		push_error("[EventBus] Refusing to emit a system event with an empty name.")
		return
	print("[EventBus] system event: %s payload=%s" % [clean_name, JSON.stringify(payload)])
	system_event.emit(clean_name, payload)


func request_scene_change(scene_id: String, reason: String = "") -> void:
	print("[EventBus] scene change requested: '%s' reason='%s'" % [scene_id, reason])
	scene_change_requested.emit(scene_id, reason)


func request_workspace(context: Dictionary = {}) -> void:
	emit_game_event("workspace_requested", context)


func notify_furniture_ready(prop_id: String) -> void:
	emit_game_event("furniture_ready", {"prop_id": prop_id})


func request_sit(seat_id: String) -> void:
	emit_game_event("sit_requested", {"seat_id": seat_id})


func notify_sit_completed(seat_id: String) -> void:
	emit_game_event("sit_completed", {"seat_id": seat_id})


func get_event_count() -> int:
	return _event_count
