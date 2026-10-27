class_name PetWorld
extends Node2D
## Persistent composition root for the pet runtime.
##
## It is created once and survives environment changes. Character, furniture,
## state machine, autonomous brain and input are separate children; none of them
## owns the whole pet. This is the boundary that replaces the old
## one-SceneView-per-scene character lifecycle for runtime behaviour.

const CHARACTER_SCENE := preload("res://scenes/character/character.tscn")
const WORLD_CONFIG_PATH := "res://config/world/default.json"
const ACTIVITIES_CONFIG_PATH := "res://config/activities.json"

@onready var world_sort: Node2D = $WorldSort
@onready var furniture_manager: FurnitureManager = $FurnitureManager
@onready var state_machine: ActionStateMachine = $StateMachine
@onready var behavior_brain: BehaviorBrain = $BehaviorBrain
@onready var pet_input: PetInput = $PetInput
@onready var activity_controller: PetActivityController = $ActivityController
@onready var pet_menu: PetMenu = $PetMenu

var character: Character = null
var world_config: Dictionary = {}
var behavior_config: Dictionary = {}
var last_error: String = ""
var _ready_for_use: bool = false


func setup(config_path: String = WORLD_CONFIG_PATH) -> bool:
	last_error = ""
	world_config = ConfigLoader.load_json(config_path)
	if world_config.is_empty():
		return _fail("Could not load world config '%s': %s" % [config_path, ConfigLoader.last_error])

	var character_config: Dictionary = world_config.get("character", {})
	if character_config.is_empty():
		return _fail("World config has no character object.")
	var spawn := _read_vec2(character_config.get("spawn"), Vector2(320, 620))
	var character_shadow: Dictionary = character_config.get("shadow", {})
	if character_shadow.is_empty():
		character_shadow = {
			"enabled": true,
			"shape": "ellipse",
			"offset": [5, 3],
			"size": [110, 20],
			"color": "#00000066",
			"core_color": "#00000040",
			"core_scale": 0.62,
			"z_index": -5,
		}

	character = CHARACTER_SCENE.instantiate() as Character
	if character == null:
		return _fail("Could not instantiate Character.")
	world_sort.add_child(character)
	character.name = "Character"
	character.position = spawn
	character.ground_x = spawn.x
	character.ground_depth = spawn.y
	character.z_index = int(character_config.get("z_index", 0))
	var scene_character_config := {
		"profile": str(character_config.get("profile", "res://config/characters/spirit.json")),
		"state": "idle",
		"facing": str(character_config.get("facing", "front")),
		"shadow": character_shadow,
	}
	if not character.setup(scene_character_config):
		return _fail("Character setup failed: %s" % character.last_error)

	if not furniture_manager.setup(world_config, world_sort):
		return _fail("Furniture setup failed: %s" % furniture_manager.last_error)

	behavior_config = ConfigLoader.load_json(str(world_config.get("behavior", "res://config/behavior.json")))
	if behavior_config.is_empty():
		return _fail("Could not load behavior config: %s" % ConfigLoader.last_error)
	if not state_machine.setup(character, furniture_manager, behavior_config):
		return _fail("State machine setup failed: %s" % state_machine.last_error)
	if not behavior_brain.setup(state_machine, behavior_config):
		return _fail("Behavior brain setup failed.")
	if not pet_input.setup(state_machine, character, behavior_brain):
		return _fail("Pet input setup failed: %s" % pet_input.last_error)

	var activities_config := ConfigLoader.load_json(ACTIVITIES_CONFIG_PATH)
	if activities_config.is_empty():
		return _fail("Could not load activities config: %s" % ConfigLoader.last_error)
	if not activity_controller.setup(state_machine, furniture_manager, character, activities_config):
		return _fail("Activity controller setup failed.")
	pet_input.context_menu_requested.connect(_on_context_menu_requested)
	pet_menu.action_selected.connect(_on_menu_action_selected)
	activity_controller.activity_started.connect(_on_activity_started)
	activity_controller.activity_waiting.connect(_on_activity_waiting)
	activity_controller.activity_finished.connect(_on_activity_finished)

	state_machine.action_started.connect(_on_action_started)
	state_machine.action_finished.connect(_on_action_finished)
	state_machine.action_cancelled.connect(_on_action_cancelled)
	state_machine.command_rejected.connect(_on_command_rejected)
	state_machine.state_changed.connect(_on_state_changed)
	furniture_manager.furniture_toggled.connect(_on_furniture_toggled)
	_ready_for_use = true
	print("[PetWorld] Ready: character=%s furniture=%s auto=%s" % [
		character.profile_path, str(furniture_manager.get_ids()), str(behavior_brain.is_auto_enabled())
	])
	return true


func is_ready() -> bool:
	return _ready_for_use


func set_auto_enabled(value: bool) -> void:
	if behavior_brain != null:
		behavior_brain.set_auto_enabled(value)


func toggle_auto() -> void:
	if behavior_brain != null:
		behavior_brain.toggle_auto()


func toggle_furniture(furniture_id: String) -> bool:
	if state_machine == null:
		return false
	return state_machine.request_furniture_toggle(furniture_id, ActionStateMachine.MANUAL)


func head_pat() -> bool:
	if state_machine == null:
		return false
	return state_machine.request_head_pat(ActionStateMachine.MANUAL)


func sit_or_stand() -> bool:
	if state_machine == null:
		return false
	return state_machine.request_sit(ActionStateMachine.MANUAL)


func walk_to(target: Vector2) -> bool:
	if state_machine == null:
		return false
	return state_machine.request_walk_to(target, ActionStateMachine.MANUAL)


func idle() -> bool:
	if state_machine == null:
		return false
	return state_machine.request_idle(ActionStateMachine.MANUAL)


func get_activity_menu_entries() -> Array:
	return activity_controller.get_menu_entries()


func request_activity(activity_id: String) -> bool:
	return activity_controller.request(activity_id)


func get_snapshot() -> Dictionary:
	var result := {
		"world": str(world_config.get("world_id", "")),
		"character_position": character.position if character != null else Vector2.ZERO,
		"character_direction": character.get_current_direction() if character != null else "",
		"character_animation": character.get_current_animation() if character != null else "",
		"furniture": furniture_manager.get_furniture_snapshot() if furniture_manager != null else [],
	}
	if state_machine != null:
		result["state_machine"] = state_machine.get_snapshot()
	if behavior_brain != null:
		result["brain"] = behavior_brain.get_snapshot()
	return result


func get_character() -> Character:
	return character


func get_state_machine() -> ActionStateMachine:
	return state_machine


func get_behavior_brain() -> BehaviorBrain:
	return behavior_brain


func get_furniture_manager() -> FurnitureManager:
	return furniture_manager


func get_activity_controller() -> PetActivityController:
	return activity_controller


func _on_context_menu_requested(screen_position: Vector2) -> void:
	pet_menu.show_actions(activity_controller.get_menu_entries(), screen_position)


func _on_menu_action_selected(activity_id: String) -> void:
	if not activity_controller.request(activity_id):
		push_warning("[PetWorld] Activity request failed: %s" % activity_id)


func _on_activity_started(activity_id: String) -> void:
	print("[PetWorld] activity_started: %s" % activity_id)


func _on_activity_waiting(activity_id: String, reason: String) -> void:
	print("[PetWorld] activity_waiting: %s (%s)" % [activity_id, reason])


func _on_activity_finished(activity_id: String) -> void:
	print("[PetWorld] activity_finished: %s" % activity_id)


func _on_action_started(action_name: String, source: String) -> void:
	print("[PetWorld] action_started: %s (%s)" % [action_name, source])


func _on_action_finished(action_name: String, source: String) -> void:
	print("[PetWorld] action_finished: %s (%s)" % [action_name, source])


func _on_action_cancelled(action_name: String, reason: String) -> void:
	print("[PetWorld] action_cancelled: %s (%s)" % [action_name, reason])


func _on_command_rejected(action_name: String, reason: String) -> void:
	print("[PetWorld] command_rejected: %s (%s)" % [action_name, reason])


func _on_state_changed(previous_state: String, current_state: String) -> void:
	print("[PetWorld] state: %s -> %s" % [previous_state, current_state])


func _on_furniture_toggled(furniture_id: String, is_visible: bool) -> void:
	print("[PetWorld] furniture %s visible=%s" % [furniture_id, str(is_visible)])


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() != 2:
		return fallback
	return Vector2(float(array[0]), float(array[1]))


func _fail(message: String) -> bool:
	last_error = message
	push_error("[PetWorld] " + message)
	return false
