extends Node
## Temporary work-break prompt. Replaced together with the final UI.

var _service: Node
var _dialog: AcceptDialog
var _resolved := false


func setup(service: Node) -> void:
	_service = service
	if _service != null:
		_service.break_due.connect(_on_break_due)


func _on_break_due(info: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _dialog != null:
		return
	_resolved = false
	var minutes := int(info.get("work_minutes", 40))
	_dialog = AcceptDialog.new()
	_dialog.title = "该休息一下了"
	_dialog.dialog_text = "你已经连续工作 %d 分钟。\n起来活动一下，喝口水吧。" % minutes
	_dialog.ok_button_text = "休息 5 分钟"
	var snooze := _dialog.add_button("稍后 10 分钟", true)
	var skip := _dialog.add_button("跳过本轮", true)
	_dialog.confirmed.connect(_on_rest)
	snooze.pressed.connect(_on_snooze)
	skip.pressed.connect(_on_skip)
	_dialog.canceled.connect(_on_snooze)
	PixelDialogSkin.apply(_dialog)
	PixelDialogSkin.style_button(snooze)
	PixelDialogSkin.style_button(skip)
	add_child(_dialog)
	_dialog.popup_centered(Vector2i(440, 200))


func _on_rest() -> void:
	if _resolved:
		return
	_resolved = true
	_cleanup()
	if _service != null:
		_service.start_break()


func _on_snooze() -> void:
	if _resolved:
		return
	_resolved = true
	_cleanup()
	if _service != null:
		_service.snooze_break(600)


func _on_skip() -> void:
	if _resolved:
		return
	_resolved = true
	_cleanup()
	if _service != null:
		_service.skip_break()


func _cleanup() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null
