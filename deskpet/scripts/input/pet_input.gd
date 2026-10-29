class_name PetInput
extends Node
## User interaction adapter.
##
## Input is translated into state-machine commands. It never changes animation
## state or furniture state directly. Mouse drag moves the OS window; a click on
## the character sends the short manual head-pat command.

signal context_menu_requested(screen_position: Vector2)

const MOVE_ACTIONS := {
	"pet_move_up": [KEY_W, KEY_UP],
	"pet_move_down": [KEY_S, KEY_DOWN],
	"pet_move_left": [KEY_A, KEY_LEFT],
	"pet_move_right": [KEY_D, KEY_RIGHT],
}

var _cursor_images: Dictionary = {}

var activity_controller: PetActivityController

var last_error: String = ""

var _state_machine: ActionStateMachine = null
var _character: Character = null
var _brain: BehaviorBrain = null
var _screen_anchor := Vector2i.ZERO
var _window_anchor := Vector2i.ZERO
var _head_pressed := false

var _press_position: Vector2 = Vector2.ZERO
var _press_on_character: bool = false
var _dragging: bool = false
var _pressed: bool = false
var _manual_direction_active: bool = false


func setup(state_machine: ActionStateMachine, character: Character, brain: BehaviorBrain) -> bool:
	_state_machine = state_machine
	_character = character
	_brain = brain
	if _state_machine == null or _character == null:
		last_error = "State machine or character is null."
		push_error("[PetInput] " + last_error)
		return false
	activity_controller = get_parent().get_node_or_null("ActivityController")
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(load("res://assets/ui/default_cursor.png"), Input.CURSOR_CROSS, Vector2(2, 12))
	Input.set_custom_mouse_cursor(load("res://assets/ui/pat.png"), Input.CURSOR_POINTING_HAND, Vector2(12, 12))
	Input.set_custom_mouse_cursor(load("res://assets/ui/click.png"), Input.CURSOR_HELP, Vector2(12, 12))
	_ensure_movement_actions()
	return true


func _process(_delta: float) -> void:
	if _pressed and not _head_pressed and _press_on_character:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			get_window().position = _window_anchor + DisplayServer.mouse_get_position() - _screen_anchor
		else:
			_pressed = false
	if _character != null:
		var hover := _is_head(_pointer_position()) and activity_controller != null and activity_controller.current_activity == "idle" and not activity_controller.transitioning and _state_machine.current_state == "idle"
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hover and _on_character_pixel() else (Input.CURSOR_CROSS if _on_character_pixel() else Input.CURSOR_ARROW))
	if _state_machine == null:
		return
	if activity_controller != null and (activity_controller.transitioning or activity_controller.current_activity != "idle"):
		return
	var direction := Input.get_vector("pet_move_left", "pet_move_right", "pet_move_up", "pet_move_down")
	if direction.length_squared() > 0.001:
		_manual_direction_active = true
		_state_machine.set_manual_direction(direction)
	elif _manual_direction_active:
		_manual_direction_active = false
		_state_machine.set_manual_direction(Vector2.ZERO)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_button(mouse_button)
			return
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			if _character != null and _character.get_screen_bounds().has_point(mouse_button.position):
				Input.set_default_cursor_shape(Input.CURSOR_HELP)
				context_menu_requested.emit(mouse_button.position)
				get_viewport().set_input_as_handled()


func _handle_key(event: InputEventKey) -> void:
	if _state_machine == null:
		return
	if activity_controller != null and (activity_controller.transitioning or activity_controller.current_activity != "idle"):
		return
	match event.physical_keycode:
		KEY_TAB:
			if _brain != null:
				_brain.toggle_auto()
			get_viewport().set_input_as_handled()
		KEY_I:
			_state_machine.request_idle(ActionStateMachine.MANUAL)
			get_viewport().set_input_as_handled()
		KEY_H:
			_state_machine.request_head_pat(ActionStateMachine.MANUAL)
			get_viewport().set_input_as_handled()
		KEY_C:
			_state_machine.request_furniture_toggle("chair", ActionStateMachine.MANUAL)
			get_viewport().set_input_as_handled()
		KEY_G:
			_state_machine.request_furniture_toggle("desk", ActionStateMachine.MANUAL)
			get_viewport().set_input_as_handled()
		KEY_V:
			_state_machine.request_furniture_toggle("computer", ActionStateMachine.MANUAL)
			get_viewport().set_input_as_handled()
		KEY_Z:
			_state_machine.request_sit(ActionStateMachine.MANUAL)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			_state_machine.request_idle(ActionStateMachine.MANUAL)
			get_viewport().set_input_as_handled()


func _is_head(point: Vector2) -> bool:
	if _character == null: return false
	var bounds := _character.get_screen_bounds()
	# segmentation.json head_torso_y=668, top=86, bottom=1957.
	bounds.size.y *= (668.0 - 86.0) / 1871.0
	return bounds.has_point(point)


func _handle_left_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		_pressed = false
		_head_pressed = false
		return
	_press_on_character = _character != null and _character.get_screen_bounds().has_point(event.position)
	if not _press_on_character: return
	_pressed = true
	_screen_anchor = DisplayServer.mouse_get_position()
	_window_anchor = get_window().position
	_head_pressed = _is_head(event.position)
	if _head_pressed and (activity_controller == null or (not activity_controller.transitioning and activity_controller.current_activity == "idle")):
		_state_machine.request_head_pat(ActionStateMachine.MANUAL)
	get_viewport().set_input_as_handled()


func _ensure_movement_actions() -> void:
	for action_name in MOVE_ACTIONS.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for keycode in MOVE_ACTIONS[action_name]:
			var input_event := InputEventKey.new()
			input_event.physical_keycode = keycode
			InputMap.action_add_event(action_name, input_event)


static func controls_text() -> String:
	return "WASD/方向键移动  ·  左键点角色摸头  ·  右键角色切换动作  ·  按住拖动窗口  ·  Tab 自动/手动  ·  C 椅子  ·  G 桌子  ·  V 电脑  ·  H 摸头  ·  Z 坐下  ·  I 待机  ·  F1 调试面板"

func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_HELP)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_character_pixel() -> bool:
	var sprite := _character.animated_body
	if sprite.sprite_frames == null: return false
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var point := sprite.get_global_transform_with_canvas().affine_inverse() * _pointer_position() - sprite.offset
	if not Rect2(Vector2.ZERO, texture.get_size()).has_point(point): return false
	if not _cursor_images.has(texture):
		_cursor_images[texture] = texture.get_image()
	return _cursor_images[texture].get_pixelv(Vector2i(point)).a > 0.2

func _pointer_position() -> Vector2:
	# Screen coordinates keep updating when transparent pixels receive no motion events.
	var local := Vector2(DisplayServer.mouse_get_position() - get_window().position)
	return get_viewport().get_final_transform().affine_inverse() * local
