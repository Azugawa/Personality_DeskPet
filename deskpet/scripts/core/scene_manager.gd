extends Node
## Owns scene registration, scene lifecycle and event-driven transitions.
##
## Rendering is delegated to the generic SceneView scene. This manager never
## knows a concrete background, character or prop; it only reads scene configs.
## Adding a scene therefore means adding a JSON file + registering its id in
## config/scenes/scene_index.json.

signal scene_changed(previous_scene_id: String, current_scene_id: String)
signal scene_change_failed(reason: String)

const SCENE_INDEX_PATH := "res://config/scenes/scene_index.json"
const SCENE_CONFIG_DIR := "res://config/scenes"
const SCENE_VIEW_SCENE := preload("res://scenes/environments/scene_view.tscn")

var current_scene_id: String = ""
var current_scene_config: Dictionary = {}
var current_view: SceneView = null
var last_error: String = ""

var _configs: Dictionary = {}
var _default_scene_id: String = ""
var _container: Node = null
var _started: bool = false
var _transitioning: bool = false


func _ready() -> void:
	EventBus.game_event.connect(_on_game_event)
	EventBus.scene_change_requested.connect(_on_scene_change_requested)
	_load_registry()


func start(container: Node) -> bool:
	if container == null:
		_fail("Cannot start: scene container is null.")
		return false
	if not is_instance_valid(container):
		_fail("Cannot start: scene container is not valid.")
		return false

	_container = container
	if _started:
		print("[SceneManager] Restarting with scene '%s'." % _default_scene_id)
		_destroy_current_view()
	else:
		_started = true

	if _default_scene_id.is_empty() or not _configs.has(_default_scene_id):
		_fail("Default scene '%s' is not registered." % _default_scene_id)
		return false

	return _switch_scene(_default_scene_id, "startup")


func request_scene_change(scene_id: String, reason: String = "") -> bool:
	if not _started:
		_fail("Scene change to '%s' requested before SceneManager.start()." % scene_id)
		return false
	if _transitioning:
		print("[SceneManager] Ignored scene change to '%s': a transition is already in progress." % scene_id)
		return false
	if not _configs.has(scene_id):
		_fail("Unknown scene id '%s' (reason: %s)." % [scene_id, reason])
		return false
	if scene_id == current_scene_id:
		print("[SceneManager] Ignored scene change to '%s': already current." % scene_id)
		return false
	return _switch_scene(scene_id, reason)


func register_scene(config: Dictionary) -> bool:
	var errors := ConfigLoader.validate_scene_config(config)
	if not errors.is_empty():
		_fail("Refusing to register invalid scene: %s" % "; ".join(errors))
		return false

	var scene_id := str(config.get("scene_id", ""))
	if scene_id.is_empty():
		_fail("Refusing to register a scene without scene_id.")
		return false
	if _configs.has(scene_id):
		print("[SceneManager] Replacing already-registered scene '%s'." % scene_id)
	_configs[scene_id] = config
	print("[SceneManager] Registered scene '%s'." % scene_id)
	return true


func get_registered_scene_ids() -> Array:
	return _configs.keys()


func get_scene_config(scene_id: String) -> Dictionary:
	if not _configs.has(scene_id):
		return {}
	var config: Dictionary = _configs[scene_id]
	return config.duplicate(true)


func get_default_scene_id() -> String:
	return _default_scene_id


func get_registry_error() -> String:
	return ConfigLoader.last_error


func _load_registry() -> void:
	_configs.clear()
	var index := ConfigLoader.load_json(SCENE_INDEX_PATH)
	if index.is_empty():
		_fail("Cannot load scene index: %s" % ConfigLoader.last_error)
		return

	var scene_ids: Variant = index.get("scenes", [])
	if typeof(scene_ids) != TYPE_ARRAY:
		_fail("scene_index.json field 'scenes' must be an array.")
		return

	for scene_id_value in scene_ids:
		var scene_id := str(scene_id_value)
		if scene_id.is_empty():
			push_error("[SceneManager] Ignoring empty scene id in scene_index.json.")
			continue
		var path := "%s/%s.json" % [SCENE_CONFIG_DIR, scene_id]
		var config := ConfigLoader.load_json(path)
		if config.is_empty():
			push_error("[SceneManager] Failed to load scene '%s' from %s: %s" % [scene_id, path, ConfigLoader.last_error])
			continue
		var errors := ConfigLoader.validate_scene_config(config, scene_id)
		if not errors.is_empty():
			push_error("[SceneManager] Scene '%s' failed validation: %s" % [scene_id, "; ".join(errors)])
			continue
		register_scene(config)

	_default_scene_id = str(index.get("default_scene", ""))
	if _default_scene_id.is_empty():
		_fail("scene_index.json field 'default_scene' must be set.")
	elif not _configs.has(_default_scene_id):
		_fail("Default scene '%s' is not in the registered scene list." % _default_scene_id)
	print("[SceneManager] Registry ready: default='%s', scenes=%s" % [_default_scene_id, str(_configs.keys())])


func _switch_scene(scene_id: String, reason: String) -> bool:
	if not _configs.has(scene_id):
		_fail("Cannot switch to unregistered scene '%s'." % scene_id)
		return false

	_transitioning = true
	var previous_id := current_scene_id
	var previous_config := current_scene_config
	var next_config: Dictionary = _configs[scene_id]

	var next_view := SCENE_VIEW_SCENE.instantiate() as SceneView
	if next_view == null:
		_transitioning = false
		_fail("Could not instantiate the generic SceneView for '%s'." % scene_id)
		return false

	next_view.name = "SceneView_%s" % scene_id
	_container.add_child(next_view)
	var view_ready := next_view.apply_config(next_config)
	if not view_ready:
		next_view.visible = false
		_container.remove_child(next_view)
		next_view.queue_free()
		_transitioning = false
		_fail("Scene '%s' could not be presented. See the preceding SceneView/Character errors." % scene_id)
		return false

	if is_instance_valid(current_view):
		_run_lifecycle(previous_config, "on_exit", scene_id)
		current_view.teardown()
		current_view.visible = false
		current_view.queue_free()

	current_view = next_view
	current_scene_config = next_config
	current_scene_id = scene_id
	_run_lifecycle(next_config, "on_enter", previous_id)

	print("[SceneManager] Scene switched: '%s' -> '%s' (reason: %s)" % [previous_id, scene_id, reason])
	scene_changed.emit(previous_id, scene_id)
	_transitioning = false
	return true


func _on_game_event(event_name: String, payload: Dictionary) -> void:
	if not _started or current_scene_config.is_empty():
		print("[SceneManager] Ignored game event '%s': no active scene." % event_name)
		return
	if _transitioning:
		print("[SceneManager] Ignored game event '%s' during a scene transition." % event_name)
		return

	var allowed: Variant = current_scene_config.get("allowed_events", [])
	if typeof(allowed) != TYPE_ARRAY or not (allowed as Array).has(event_name):
		print("[SceneManager] Ignored event '%s': not allowed in scene '%s'. payload=%s" % [event_name, current_scene_id, JSON.stringify(payload)])
		return

	var transitions: Variant = current_scene_config.get("transitions", {})
	if typeof(transitions) == TYPE_DICTIONARY and (transitions as Dictionary).has(event_name):
		var rule: Variant = (transitions as Dictionary)[event_name]
		if typeof(rule) != TYPE_DICTIONARY:
			push_error("[SceneManager] Transition rule for '%s' is not an object." % event_name)
			return
		var target := str((rule as Dictionary).get("target_scene", ""))
		var transition_reason := str((rule as Dictionary).get("reason", "event: %s" % event_name))
		print("[SceneManager] Event '%s' accepted in '%s'; requesting transition to '%s'." % [event_name, current_scene_id, target])
		request_scene_change(target, transition_reason)
	else:
		print("[SceneManager] Event '%s' accepted in '%s' (no transition configured)." % [event_name, current_scene_id])


func _on_scene_change_requested(scene_id: String, reason: String) -> void:
	request_scene_change(scene_id, reason)


func _run_lifecycle(config: Dictionary, phase: String, other_scene_id: String) -> void:
	if config.is_empty():
		return
	var lifecycle: Variant = config.get("lifecycle", {})
	if typeof(lifecycle) != TYPE_DICTIONARY:
		return
	var rule: Variant = (lifecycle as Dictionary).get(phase, {})
	if typeof(rule) != TYPE_DICTIONARY:
		return

	var message := str((rule as Dictionary).get("log", ""))
	if not message.is_empty():
		print("[SceneManager] %s" % message)

	var emitted_events: Variant = (rule as Dictionary).get("emit_events", [])
	if typeof(emitted_events) == TYPE_ARRAY:
		for event_value in emitted_events:
			var event_name := str(event_value)
			if event_name.is_empty():
				continue
			EventBus.emit_system_event(event_name, {
				"scene_id": str(config.get("scene_id", "")),
				"other_scene_id": other_scene_id,
			})


func _destroy_current_view() -> void:
	if is_instance_valid(current_view):
		current_view.teardown()
		current_view.visible = false
		current_view.queue_free()
	current_view = null
	current_scene_id = ""
	current_scene_config = {}


func _fail(message: String) -> void:
	last_error = message
	push_error("[SceneManager] " + message)
	scene_change_failed.emit(message)
