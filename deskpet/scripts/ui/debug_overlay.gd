extends CanvasLayer
## Development overlay for the persistent pet runtime.
##
## It calls only public PetWorld/StateMachine APIs. It is hidden in desktop mode
## and is never required for normal pet behaviour.

@onready var state_label: Label = $Panel/Margin/VBox/StateLabel
@onready var animation_label: Label = $Panel/Margin/VBox/AnimationLabel
@onready var furniture_label: Label = $Panel/Margin/VBox/FurnitureLabel
@onready var status_label: Label = $Panel/Margin/VBox/StatusLabel
@onready var auto_button: Button = $Panel/Margin/VBox/AutoButton
@onready var idle_button: Button = $Panel/Margin/VBox/IdleButton
@onready var walk_left_button: Button = $Panel/Margin/VBox/WalkLeftButton
@onready var walk_right_button: Button = $Panel/Margin/VBox/WalkRightButton
@onready var chair_button: Button = $Panel/Margin/VBox/ChairButton
@onready var desk_button: Button = $Panel/Margin/VBox/DeskButton
@onready var computer_button: Button = $Panel/Margin/VBox/ComputerButton
@onready var head_pat_button: Button = $Panel/Margin/VBox/HeadPatButton
@onready var sit_button: Button = $Panel/Margin/VBox/SitButton

var pet_world: PetWorld = null


func bind_pet_world(world: PetWorld) -> void:
	pet_world = world


func _ready() -> void:
	auto_button.pressed.connect(_on_auto_pressed)
	idle_button.pressed.connect(_on_idle_pressed)
	walk_left_button.pressed.connect(_on_walk_left_pressed)
	walk_right_button.pressed.connect(_on_walk_right_pressed)
	chair_button.pressed.connect(_on_chair_pressed)
	desk_button.pressed.connect(_on_desk_pressed)
	computer_button.pressed.connect(_on_computer_pressed)
	head_pat_button.pressed.connect(_on_head_pat_pressed)
	sit_button.pressed.connect(_on_sit_pressed)
	status_label.text = "Ready."
	if pet_world != null and pet_world.get_state_machine() != null:
		var machine := pet_world.get_state_machine()
		machine.action_started.connect(_on_action_started)
		machine.command_rejected.connect(_on_command_rejected)
		machine.state_changed.connect(_on_state_changed)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		visible = not visible
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if pet_world == null or not pet_world.is_ready():
		return
	var snapshot := pet_world.get_snapshot()
	var machine: Dictionary = snapshot.get("state_machine", {})
	var brain: Dictionary = snapshot.get("brain", {})
	var character: Character = pet_world.get_character()
	state_label.text = "state=%s  action=%s  source=%s\nqueued=%s  manual_pause=%.1fs" % [
		str(machine.get("state", "?")),
		str(machine.get("action", "-")),
		str(machine.get("source", "-")),
		str(machine.get("queued", 0)),
		float(machine.get("manual_pause", 0.0)),
	]
	animation_label.text = "direction=%s  clip=%s\nauto=%s  brain=%s" % [
		character.get_current_direction() if character != null else "?",
		character.get_current_animation() if character != null else "?",
		"ON" if bool(brain.get("enabled", false)) else "OFF",
		str(brain.get("last_decision", "-")),
	]
	var parts: Array[String] = []
	for entry_value in snapshot.get("furniture", []):
		var entry: Dictionary = entry_value
		parts.append("%s:%s" % [str(entry.get("id", "?")), "on" if bool(entry.get("visible", false)) else "off"])
	furniture_label.text = "furniture: " + ", ".join(parts)
	auto_button.text = "Tab  Auto: %s" % ("ON" if bool(brain.get("enabled", false)) else "OFF")


func _on_auto_pressed() -> void:
	if pet_world != null:
		pet_world.toggle_auto()


func _on_idle_pressed() -> void:
	if pet_world != null and not pet_world.idle():
		status_label.text = "Idle command rejected."


func _on_walk_left_pressed() -> void:
	_walk_by(-120.0)


func _on_walk_right_pressed() -> void:
	_walk_by(120.0)


func _walk_by(offset_x: float) -> void:
	if pet_world == null or pet_world.get_character() == null:
		return
	var target := pet_world.get_character().position + Vector2(offset_x, 0)
	if not pet_world.walk_to(target):
		status_label.text = "Walk command rejected."


func _on_chair_pressed() -> void:
	if pet_world != null:
		pet_world.toggle_furniture("chair")


func _on_desk_pressed() -> void:
	if pet_world != null:
		pet_world.toggle_furniture("desk")


func _on_computer_pressed() -> void:
	if pet_world != null:
		pet_world.toggle_furniture("computer")


func _on_head_pat_pressed() -> void:
	if pet_world != null:
		pet_world.head_pat()


func _on_sit_pressed() -> void:
	if pet_world != null:
		pet_world.sit_or_stand()


func _on_action_started(action_name: String, source: String) -> void:
	status_label.text = "Action: %s (%s)" % [action_name, source]


func _on_command_rejected(action_name: String, reason: String) -> void:
	status_label.text = "Rejected %s: %s" % [action_name, reason]


func _on_state_changed(_previous_state: String, current_state: String) -> void:
	status_label.text = "State: " + current_state
