extends Node
## Drag the message/background, while keeping buttons clickable.
var window: AcceptDialog
var dragging := false
var mouse_origin := Vector2i.ZERO
var window_origin := Vector2i.ZERO

func _ready() -> void:
	window = get_parent() as AcceptDialog
	window.window_input.connect(_on_input)
	window.visibility_changed.connect(func(): dragging = false)
	window.focus_exited.connect(func(): dragging = false)

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			dragging = false
			return
		var buttons := [window.get_ok_button()]
		if window is ConfirmationDialog:
			buttons.append(window.get_cancel_button())
		for button in buttons:
			if button.get_global_rect().has_point(event.position):
				return
		dragging = true
		mouse_origin = DisplayServer.mouse_get_position()
		window_origin = window.position

func _process(_delta: float) -> void:
	if dragging:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			dragging = false
			return
		window.position = window_origin + DisplayServer.mouse_get_position() - mouse_origin
