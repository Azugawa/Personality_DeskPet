extends Node
var indicator: StatusIndicator
var menu: PetMenu
func _ready() -> void:
	if DisplayServer.get_name() == "headless": return
	indicator = StatusIndicator.new()
	indicator.name = "TrayIcon"
	indicator.icon = load("res://assets/ui/app_icon_256.png")
	indicator.tooltip = "何爪爪"
	menu = PetMenu.new()
	add_child(menu)
	menu.action_selected.connect(func(id: String): _selected(int(id)))
	add_child(indicator)
	indicator.pressed.connect(func(button: int, _position: Vector2i):
		if button == MOUSE_BUTTON_LEFT: _set_shown(true)
		if button == MOUSE_BUTTON_RIGHT:
			menu.show_actions([
				{"id":"0", "label":"隐藏桌宠" if shown else "显示桌宠"},
				{"id":"2", "label":"检查更新"},
				{"id":"3", "label":"退出"}],Vector2.ZERO)
	)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(func(): _set_shown(false))

var shown := true
func _set_shown(value: bool) -> void:
	shown = value
	# Hide the pet scene while keeping the native tray owner alive.
	var main := get_tree().current_scene
	if main != null:
		var world := main.get_node_or_null("PetWorld")
		if world != null: world.visible = value
	get_window().mouse_passthrough = not value

func _selected(id: int) -> void:
	match id:
		0: _set_shown(not shown)
		2:
			_set_shown(true)
			UpdateService.check()
		3: get_tree().quit()
