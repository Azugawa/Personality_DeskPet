extends Node
## Work mode: manual on/off plus automatic detection through the sentinel.
##
## Only active work time accumulates. While a break prompt is pending the timer
## stops, and full-screen presentations defer the prompt until the user leaves
## full screen. All policy values come from SettingsService.

signal state_changed(state: Dictionary)
signal break_due(info: Dictionary)

const DATA_PATH := "user://data/work_mode.json"

var _settings: Node
var _sentinel: Node
var _clock: AssistantClock
var _path := DATA_PATH

var _apps: Array[String] = []
var _auto_enable_seconds := 30
var _auto_disable_seconds := 120
var _manual_auto_disable_seconds := 600
var _manual_off_suppress_seconds := 1800
var _idle_pause_seconds := 120
var _work_seconds := 40 * 60
var _break_seconds := 5 * 60
var _fullscreen_defer := true

var _mode := "off"          # off / manual / auto
var _phase := "work"        # work / break
var _active_seconds := 0
var _break_ends_at := 0
var _break_remaining := 0
var _snooze_until := 0
var _suppressed_until := 0
var _last_office_at := 0
var _office_since := 0
var _break_pending := false
var _break_announced := false
var _break_deferred := false

var _last_tick_at := 0
var _tick_accumulator := 0.0
var _save_accumulator := 0.0
var _last_state: Dictionary = {}


func setup(settings: Node, sentinel: Node, clock: AssistantClock = null, path: String = DATA_PATH) -> void:
	_settings = settings
	_sentinel = sentinel
	_clock = clock if clock != null else AssistantClock.new()
	_path = path
	_apply_settings()
	_restore()
	_last_tick_at = _clock.now()
	_emit_state()


func _apply_settings() -> void:
	if _settings == null:
		return
	_apps.clear()
	for app in _settings.get_array("work_mode.apps", []):
		_apps.append(str(app).to_lower())
	_auto_enable_seconds = maxi(1, _settings.get_int("work_mode.auto_enable_seconds", 30))
	_auto_disable_seconds = maxi(1, _settings.get_int("work_mode.auto_disable_seconds", 120))
	_manual_auto_disable_seconds = maxi(1, _settings.get_int("work_mode.manual_auto_disable_seconds", 600))
	_manual_off_suppress_seconds = maxi(0, _settings.get_int("work_mode.manual_off_suppress_seconds", 1800))
	_idle_pause_seconds = maxi(1, _settings.get_int("work_mode.idle_pause_seconds", 120))
	_work_seconds = maxi(1, _settings.get_int("work_mode.work_minutes", 40)) * 60
	_break_seconds = maxi(1, _settings.get_int("work_mode.break_minutes", 5)) * 60
	_fullscreen_defer = _settings.get_bool("work_mode.fullscreen_defer", true)


func _process(delta: float) -> void:
	_tick_accumulator += delta
	if _tick_accumulator < 1.0:
		return
	_tick_accumulator = 0.0
	tick()


func tick() -> void:
	var now := _clock.now()
	var snapshot := _snapshot()
	var foreground := str((snapshot.get("foreground", {}) as Dictionary).get("process", ""))
	var idle_seconds := int(snapshot.get("idle_seconds", 0))
	var fullscreen := bool((snapshot.get("foreground", {}) as Dictionary).get("fullscreen", false))
	var office := _is_office(foreground)
	if office:
		_last_office_at = now
		if _office_since == 0:
			_office_since = now
	else:
		_office_since = 0
	var delta := _elapsed(now)
	_handle_auto_enable(now, office, idle_seconds, delta)
	_handle_auto_disable(now, office)
	_handle_break_phase(now)
	_handle_work_accumulation(now, office, idle_seconds, fullscreen, delta)
	_handle_break_pending(now, fullscreen)
	_save_accumulator += delta
	if _save_accumulator >= 15.0 and _mode != "off":
		_save_accumulator = 0.0
		_save()
	_emit_state()


func enable_manual() -> void:
	var now := _clock.now()
	_mode = "manual"
	_phase = "work"
	_active_seconds = 0
	_break_ends_at = 0
	_break_remaining = 0
	_snooze_until = 0
	_suppressed_until = 0
	_break_pending = false
	_break_announced = false
	_break_deferred = false
	_last_office_at = now
	_office_since = 0
	_save()
	_emit_state()


func disable_manual() -> void:
	var now := _clock.now()
	_mode = "off"
	_phase = "work"
	_active_seconds = 0
	_break_ends_at = 0
	_break_remaining = 0
	_snooze_until = 0
	_suppressed_until = now + _manual_off_suppress_seconds
	_break_pending = false
	_break_announced = false
	_break_deferred = false
	_save()
	_emit_state()


func toggle() -> void:
	if _mode == "off":
		enable_manual()
	else:
		disable_manual()


func start_break(seconds: int = -1) -> void:
	var duration := seconds if seconds > 0 else _break_seconds
	var now := _clock.now()
	_phase = "break"
	_break_ends_at = now + duration
	_break_remaining = duration
	_active_seconds = 0
	_break_pending = false
	_break_announced = false
	_break_deferred = false
	_snooze_until = 0
	_save()
	_emit_state()


func snooze_break(seconds: int = 600) -> void:
	var now := _clock.now()
	_break_pending = false
	_break_announced = false
	_break_deferred = false
	_snooze_until = now + maxi(1, seconds)
	_phase = "work"
	_save()
	_emit_state()


func skip_break() -> void:
	_phase = "work"
	_active_seconds = 0
	_break_pending = false
	_break_announced = false
	_break_deferred = false
	_snooze_until = 0
	_save()
	_emit_state()


func get_state() -> Dictionary:
	return _state()


func menu_label() -> String:
	match _mode:
		"off":
			return "工作模式：关"
		"manual":
			if _phase == "break":
				return "工作模式：休息中（%s）" % _clock.format_duration(_break_remaining)
			return "工作模式：开（剩 %s）" % _clock.format_duration(maxi(0, _work_seconds - _active_seconds))
		"auto":
			if _phase == "break":
				return "工作模式：休息中（%s）" % _clock.format_duration(_break_remaining)
			return "工作模式：自动（剩 %s）" % _clock.format_duration(maxi(0, _work_seconds - _active_seconds))
	return "工作模式：关"


func save_now() -> void:
	_save()


func _snapshot() -> Dictionary:
	if _sentinel == null:
		return {}
	return _sentinel.get_snapshot()


func _elapsed(now: int) -> float:
	var raw := now - _last_tick_at
	_last_tick_at = now
	if raw <= 0:
		return 0.0
	# A sleep/hibernate gap must not count as hours of work.
	return float(mini(raw, 2))


func _is_office(process: String) -> bool:
	if process.is_empty():
		return false
	var lower := process.to_lower()
	var base := lower.get_file()
	return _apps.has(lower) or _apps.has(base)


func _handle_auto_enable(now: int, office: bool, idle_seconds: int, delta: float) -> void:
	if _mode != "off" or not office or _office_since == 0:
		return
	if idle_seconds > _idle_pause_seconds:
		return
	if now < _suppressed_until:
		return
	if float(now - _office_since) < float(_auto_enable_seconds):
		return
	_mode = "auto"
	_phase = "work"
	_active_seconds = 0
	_snooze_until = 0
	_break_pending = false
	_break_announced = false
	_break_deferred = false
	_last_office_at = now
	_save()
	_emit_state()


func _handle_auto_disable(now: int, office: bool) -> void:
	if _mode == "off" or _phase == "break":
		return
	if _mode == "auto" and _break_pending:
		return
	if office:
		return
	if _mode == "auto":
		if float(now - _last_office_at) >= float(_auto_disable_seconds):
			_mode = "off"
			_active_seconds = 0
			_save()
			_emit_state()
	elif _mode == "manual":
		if float(now - _last_office_at) >= float(_manual_auto_disable_seconds):
			_mode = "off"
			_active_seconds = 0
			_phase = "work"
			_break_pending = false
			_break_announced = false
			_save()
			_emit_state()


func _handle_break_phase(now: int) -> void:
	if _phase != "break":
		return
	_break_remaining = maxi(0, _break_ends_at - now)
	if _break_remaining <= 0:
		_phase = "work"
		_active_seconds = 0
		_break_ends_at = 0
		_break_pending = false
		_break_announced = false
		_break_deferred = false
		_save()
		_emit_state()


func _handle_work_accumulation(now: int, office: bool, idle_seconds: int, fullscreen: bool, delta: float) -> void:
	if _mode == "off" or _phase != "work" or _break_pending:
		return
	if idle_seconds > _idle_pause_seconds:
		return
	if _mode == "auto" and not office:
		return
	_active_seconds += int(round(delta))
	if _active_seconds < _work_seconds:
		return
	if _snooze_until > 0 and now < _snooze_until:
		return
	_break_pending = true
	_break_announced = false
	_break_deferred = fullscreen and _fullscreen_defer
	_save()


func _handle_break_pending(now: int, fullscreen: bool) -> void:
	if not _break_pending or _break_announced:
		return
	if fullscreen and _fullscreen_defer:
		_break_deferred = true
		return
	_break_deferred = false
	_break_announced = true
	break_due.emit({
		"active_seconds": _active_seconds,
		"work_minutes": _work_seconds / 60,
		"deferred": false,
	})
	_save()
	_emit_state()


func _state() -> Dictionary:
	var snapshot := _snapshot()
	var foreground := str((snapshot.get("foreground", {}) as Dictionary).get("process", ""))
	var state := {
		"mode": _mode,
		"phase": _phase,
		"active_seconds": _active_seconds,
		"remaining_seconds": maxi(0, _work_seconds - _active_seconds),
		"break_remaining": _break_remaining,
		"break_pending": _break_pending,
		"break_deferred": _break_deferred,
		"suppressed_until": _suppressed_until,
		"foreground": foreground,
		"office": _is_office(foreground),
		"idle_seconds": int(snapshot.get("idle_seconds", 0)),
		"fullscreen": bool((snapshot.get("foreground", {}) as Dictionary).get("fullscreen", false)),
	}
	return state


func _emit_state() -> void:
	var state := _state()
	_last_state = state
	state_changed.emit(state)


func _save() -> void:
	var now := _clock.now()
	var data := {
		"schema": 1,
		"mode": _mode,
		"phase": _phase,
		"active_seconds": _active_seconds,
		"break_ends_at": _break_ends_at,
		"break_remaining": _break_remaining,
		"snooze_until": _snooze_until,
		"suppressed_until": _suppressed_until,
		"last_office_at": _last_office_at,
		"saved_at": now,
	}
	JsonStore.save_dict(_path, data)


func _restore() -> void:
	var data := JsonStore.load_dict(_path, {})
	if data.is_empty():
		return
	var now := _clock.now()
	var saved_at := int(data.get("saved_at", 0))
	var mode := str(data.get("mode", "off"))
	_last_office_at = int(data.get("last_office_at", now))
	_suppressed_until = int(data.get("suppressed_until", 0))
	_snooze_until = int(data.get("snooze_until", 0))
	_break_ends_at = int(data.get("break_ends_at", 0))
	_break_remaining = int(data.get("break_remaining", 0))
	_active_seconds = clampi(int(data.get("active_seconds", 0)), 0, _work_seconds)
	if mode == "manual" and now - saved_at <= 300:
		_mode = "manual"
		_phase = "work"
		if _break_ends_at > now:
			_phase = "break"
			_break_remaining = _break_ends_at - now
		else:
			_break_ends_at = 0
			_break_remaining = 0
	else:
		_mode = "off"
		_phase = "work"
		_active_seconds = 0
