extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var service = root.get_node("UpdateService")
	service._message("正在检查更新，请稍候……")
	await create_timer(0.3).timeout
	var window = service.dialog
	var drag = window.get_node("DialogDrag")
	drag.set_process(false)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(50,60)
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	drag._on_input(press)
	assert(drag.dragging)
	var before: Vector2i = window.position
	drag.mouse_origin -= Vector2i(80,40)
	drag._process(0.016)
	assert(window.position == before + Vector2i(80,40))
	service._message("当前为最新版本 0.2.3")
	assert(window.position == before + Vector2i(80,40))
	press = press.duplicate()
	press.pressed = false
	Input.parse_input_event(press)
	drag._on_input(press)
	assert(not drag.dragging)
	press.pressed = true
	press.position = window.get_ok_button().get_global_rect().get_center()
	drag._on_input(press)
	assert(not drag.dragging)
	print("PASS: drag delta, release, button exclusion, position retained")
	quit()
