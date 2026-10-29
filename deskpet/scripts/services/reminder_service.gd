extends Node
## Local reminder scheduler.
##
## Reminders are one-shot entries stored as UTC Unix seconds. The service is
## deliberately independent from UI: it queues due reminders and emits signals,
## a presenter decides how to show them. It also catches up after the app or the
## machine was closed, within a configurable grace window.

signal due(reminder: Dictionary)
signal changed

const DATA_PATH := "user://data/reminders.json"
const SCHEMA := 1
const MAX_ITEMS := 200
const MAX_TEXT := 200
const MAX_HORIZON_SECONDS := 5 * 365 * 24 * 3600

const VALID_STATUS := ["pending", "fired", "dismissed", "expired", "canceled"]

var _clock: AssistantClock
var _path := DATA_PATH
var _grace_seconds := 24 * 3600
var _retention_days := 7
var _max_items := MAX_ITEMS
var _max_text := MAX_TEXT
var _state: Dictionary = {"schema": SCHEMA, "next_id": 1, "items": []}
var _pending_presentation: Array = []
var _tick_accumulator := 0.0
var _save_warned := false


func setup(
	path: String = DATA_PATH,
	clock: AssistantClock = null,
	grace_hours: int = 24,
	retention_days: int = 7,
	max_items: int = MAX_ITEMS,
	max_text_length: int = MAX_TEXT
) -> void:
	_path = path
	_clock = clock if clock != null else AssistantClock.new()
	_grace_seconds = maxi(0, grace_hours) * 3600
	_retention_days = maxi(1, retention_days)
	_max_items = clampi(max_items, 1, 1000)
	_max_text = clampi(max_text_length, 1, 1000)
	_load()
	_catch_up()
	_prune()


func _process(delta: float) -> void:
	_tick_accumulator += delta
	if _tick_accumulator < 1.0:
		return
	_tick_accumulator = 0.0
	tick()


func tick() -> void:
	var now := _clock.now()
	var fired_any := false
	for item_value in _state.get("items", []):
		var item: Dictionary = item_value
		if str(item.get("status", "")) != "pending":
			continue
		if int(item.get("due_at", 0)) > now:
			continue
		item["status"] = "fired"
		item["fired_at"] = now
		item["presented"] = false
		_queue_presentation(item)
		due.emit(item.duplicate(true))
		fired_any = true
	if fired_any:
		_save()
		changed.emit()


func add_at_string(text: String, local_datetime: String) -> Dictionary:
	var parsed := _clock.parse_local(local_datetime)
	if parsed.is_empty():
		return _error("时间格式应为 YYYY-MM-DD HH:MM")
	return add_at(text, parsed.get("unix", 0))


func add_at(text: String, local_unix: int) -> Dictionary:
	return add_reminder(text, local_unix, "user")


func add_after(text: String, seconds: int) -> Dictionary:
	if seconds < 1:
		return _error("计时时间必须大于 0 秒")
	return add_reminder(text, _clock.now() + seconds, "user")


func add_reminder(text: String, due_at: int, kind: String = "user") -> Dictionary:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return _error("提醒内容不能为空")
	if clean_text.length() > _max_text:
		return _error("提醒内容太长了（最多 %d 字）" % _max_text)
	var now := _clock.now()
	if due_at <= now:
		return _error("提醒时间必须晚于当前时间")
	if due_at > now + MAX_HORIZON_SECONDS:
		return _error("提醒时间太远了")
	if _pending_count() >= _max_items:
		return _error("待提醒数量已达上限（%d 条）" % _max_items)
	var next_id := int(_state.get("next_id", 1))
	var reminder := {
		"id": "r_%04d" % next_id,
		"text": clean_text,
		"due_at": due_at,
		"created_at": now,
		"kind": kind,
		"status": "pending",
		"presented": false,
		"snooze_count": 0,
	}
	_state["next_id"] = next_id + 1
	(_state["items"] as Array).append(reminder)
	_save()
	changed.emit()
	return {"ok": true, "reminder": reminder.duplicate(true)}


func cancel(id: String) -> bool:
	var item := _find(id)
	if item.is_empty() or str(item.get("status", "")) != "pending":
		return false
	item["status"] = "canceled"
	_remove_from_queue(id)
	_save()
	changed.emit()
	return true


func snooze(id: String, seconds: int) -> bool:
	var item := _find(id)
	if item.is_empty():
		return false
	var status := str(item.get("status", ""))
	if status in ["canceled", "expired", "dismissed"]:
		return false
	item["status"] = "pending"
	item["due_at"] = _clock.now() + maxi(1, seconds)
	item["snooze_count"] = int(item.get("snooze_count", 0)) + 1
	item["presented"] = false
	_remove_from_queue(id)
	_save()
	changed.emit()
	return true


func dismiss(id: String) -> void:
	var item := _find(id)
	if item.is_empty():
		return
	item["status"] = "dismissed"
	item["dismissed_at"] = _clock.now()
	item["presented"] = true
	_remove_from_queue(id)
	_save()
	changed.emit()


func mark_presented(id: String) -> void:
	var item := _find(id)
	if item.is_empty():
		return
	item["presented"] = true
	_save()


## Return queued reminders exactly once and clear the in-memory queue.
func take_pending() -> Array:
	var result := _pending_presentation.duplicate(true)
	_pending_presentation.clear()
	return result


func pending_count() -> int:
	return _pending_count()


func list_pending() -> Array:
	var result: Array = []
	for item_value in _state.get("items", []):
		var item: Dictionary = item_value
		if str(item.get("status", "")) == "pending":
			result.append(item.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("due_at", 0)) < int(b.get("due_at", 0))
	)
	return result


func list_all() -> Array:
	return (_state.get("items", []) as Array).duplicate(true)


func find_reminder(id: String) -> Dictionary:
	var item := _find(id)
	return item.duplicate(true) if not item.is_empty() else {}


func next_due() -> Dictionary:
	var pending := list_pending()
	if pending.is_empty():
		return {}
	return pending[0]


func _load() -> void:
	var loaded := JsonStore.load_dict(_path, {})
	if loaded.is_empty():
		_state = {"schema": SCHEMA, "next_id": 1, "items": []}
		return
	if int(loaded.get("schema", 0)) > SCHEMA:
		push_warning("[Reminder] newer schema %s; starting with an empty list." % str(loaded.get("schema")))
		_state = {"schema": SCHEMA, "next_id": 1, "items": []}
		return
	var items: Array = []
	var seen := {}
	var raw_items: Variant = loaded.get("items", [])
	if typeof(raw_items) != TYPE_ARRAY:
		raw_items = []
	for item_value in raw_items:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value
		var id := str(item.get("id", ""))
		var text := str(item.get("text", "")).strip_edges()
		var status := str(item.get("status", "pending"))
		if id.is_empty() or seen.has(id) or text.is_empty() or status not in VALID_STATUS:
			continue
		seen[id] = true
		item["id"] = id
		item["text"] = text
		item["due_at"] = int(item.get("due_at", 0))
		item["created_at"] = int(item.get("created_at", 0))
		item["status"] = status
		item["presented"] = bool(item.get("presented", false))
		item["snooze_count"] = int(item.get("snooze_count", 0))
		items.append(item)
	_state = {
		"schema": SCHEMA,
		"next_id": maxi(1, int(loaded.get("next_id", 1))),
		"items": items,
	}
	var highest := 0
	for item_value in items:
		var id := str((item_value as Dictionary).get("id", ""))
		var numeric := int(id.trim_prefix("r_"))
		highest = maxi(highest, numeric)
	_state["next_id"] = maxi(int(_state["next_id"]), highest + 1)


func _catch_up() -> void:
	var now := _clock.now()
	var queued := false
	for item_value in _state.get("items", []):
		var item: Dictionary = item_value
		var status := str(item.get("status", ""))
		if status == "fired" and not bool(item.get("presented", true)):
			if now - int(item.get("fired_at", item.get("due_at", now))) <= _grace_seconds:
				_queue_presentation(item)
				queued = true
			else:
				item["status"] = "expired"
			continue
		if status != "pending":
			continue
		var due_at := int(item.get("due_at", 0))
		if due_at > now:
			continue
		if now - due_at > _grace_seconds:
			item["status"] = "expired"
			continue
		item["status"] = "fired"
		item["fired_at"] = now
		item["presented"] = false
		item["overdue"] = true
		_queue_presentation(item)
		queued = true
	if queued:
		_save()
		changed.emit()


func _prune() -> void:
	var now := _clock.now()
	var cutoff := now - _retention_days * 24 * 3600
	var kept: Array = []
	var changed_any := false
	for item_value in _state.get("items", []):
		var item: Dictionary = item_value
		var status := str(item.get("status", ""))
		var stamp := int(item.get("dismissed_at", item.get("fired_at", item.get("created_at", now))))
		if status in ["dismissed", "expired", "canceled"] and stamp < cutoff:
			changed_any = true
			continue
		if status == "fired" and bool(item.get("presented", false)) and stamp < cutoff:
			changed_any = true
			continue
		kept.append(item)
	if changed_any:
		_state["items"] = kept
		_save()


func _queue_presentation(item: Dictionary) -> void:
	var id := str(item.get("id", ""))
	for queued in _pending_presentation:
		if str((queued as Dictionary).get("id", "")) == id:
			return
	_pending_presentation.append(item.duplicate(true))


func _remove_from_queue(id: String) -> void:
	var kept: Array = []
	for queued in _pending_presentation:
		if str((queued as Dictionary).get("id", "")) != id:
			kept.append(queued)
	_pending_presentation = kept


func _find(id: String) -> Dictionary:
	for item_value in _state.get("items", []):
		var item: Dictionary = item_value
		if str(item.get("id", "")) == id:
			return item
	return {}


func _pending_count() -> int:
	var count := 0
	for item_value in _state.get("items", []):
		if str((item_value as Dictionary).get("status", "")) == "pending":
			count += 1
	return count


func _save() -> void:
	if not JsonStore.save_dict(_path, _state) and not _save_warned:
		_save_warned = true
		push_warning("[Reminder] could not write %s" % _path)


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
