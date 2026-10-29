extends Node
## Temporary reminder presenter.
##
## The final UI will replace this node, but it already implements the contract:
## take queued reminders from ReminderService, show them one at a time, and call
## mark_presented/snooze/dismiss. It stays UI-only; no scheduling logic here.

var _service: Node
var _clock: AssistantClock = AssistantClock.new()
var _queue: Array = []
var _dialog: AcceptDialog
var _current: Dictionary = {}
var _closing := false


func setup(service: Node) -> void:
	_service = service
	if _service == null:
		return
	_service.changed.connect(_on_service_changed)
	_flush.call_deferred()


func _on_service_changed() -> void:
	_flush.call_deferred()


func _flush() -> void:
	if _service == null or DisplayServer.get_name() == "headless":
		return
	if _dialog != null:
		return
	for item in _service.take_pending():
		_queue.append(item)
	_show_next()


func _show_next() -> void:
	if _dialog != null or _queue.is_empty():
		return
	_current = _queue.pop_front()
	var id := str(_current.get("id", ""))
	if not id.is_empty():
		_service.mark_presented(id)
	_dialog = AcceptDialog.new()
	_dialog.title = "定时提醒"
	_dialog.dialog_text = _format_text(_current)
	_dialog.ok_button_text = "知道了"
	var snooze := _dialog.add_button("稍后 10 分钟", true)
	snooze.pressed.connect(_on_snooze_pressed)
	_dialog.confirmed.connect(_close_dialog)
	_dialog.canceled.connect(_close_dialog)
	PixelDialogSkin.apply(_dialog)
	PixelDialogSkin.style_button(snooze)
	add_child(_dialog)
	_dialog.popup_centered(Vector2i(430, 190))


func _format_text(reminder: Dictionary) -> String:
	var due_text := _clock.format_local(int(reminder.get("due_at", 0)))
	var text := str(reminder.get("text", ""))
	if bool(reminder.get("overdue", false)):
		return "%s\n\n补提醒（原定 %s）" % [text, due_text]
	return "%s\n\n提醒时间：%s" % [text, due_text]


func _on_snooze_pressed() -> void:
	if _current.is_empty():
		return
	_service.snooze(str(_current.get("id", "")), 600)
	_close_dialog()


func _close_dialog() -> void:
	if _closing:
		return
	_closing = true
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null
	_current = {}
	await get_tree().create_timer(0.3).timeout
	_closing = false
	_flush()
	_show_next()
