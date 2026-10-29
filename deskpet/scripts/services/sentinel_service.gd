extends Node
## Windows sensor service.
##
## The actual sampling lives in DeskPetSentinel.exe. This service extracts the
## helper from the pck (so incremental pck updates can ship a new helper),
## starts it with the current process id, and polls an atomic JSON snapshot.
## Everything degrades to "unavailable" instead of blocking the pet.

signal snapshot_updated(snapshot: Dictionary)
signal availability_changed(available: bool)

const HELPER_RES := "res://bin/DeskPetSentinel.exe"
const HELPER_NAME := "DeskPetSentinel"
const SCHEMA := 1

var _settings: Node
var _snapshot: Dictionary = {}
var _available := false
var _helper_pid := -1
var _helper_exe := ""
var _state_dir := ""
var _last_ts := 0.0
var _stale_polls := 0
var _restart_attempts := 0
var _restart_at_msec := 0
var _timer: Timer


func setup(settings: Node, force_start: bool = false) -> void:
	_settings = settings
	if not bool(settings.get_bool("sentinel.enabled", true)):
		return
	if DisplayServer.get_name() == "headless" and not force_start:
		return
	call_deferred("_start_after_delay")


func _start_after_delay() -> void:
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return
	_start_helper()


func is_available() -> bool:
	return _available


## Extract (or locate) the helper executable even if sampling was not started.
func helper_executable() -> String:
	if _helper_exe.is_empty():
		_helper_exe = _ensure_helper()
	return _helper_exe


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_foreground() -> Dictionary:
	var value: Variant = _snapshot.get("foreground", {})
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func foreground_process() -> String:
	return str(get_foreground().get("process", ""))


func idle_seconds() -> int:
	return int(_snapshot.get("idle_seconds", 0))


func cpu_percent() -> float:
	return float(_snapshot.get("cpu_percent", 0.0))


func disk_c() -> Dictionary:
	var value: Variant = _snapshot.get("disk_c", {})
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func top_processes() -> Array:
	var processes: Variant = _snapshot.get("processes", {})
	if typeof(processes) != TYPE_DICTIONARY:
		return []
	var list: Variant = (processes as Dictionary).get("list", [])
	return (list as Array).duplicate(true) if typeof(list) == TYPE_ARRAY else []


## Test seam: inject a snapshot without a helper process.
func inject_snapshot(snapshot: Dictionary) -> void:
	_apply_snapshot(snapshot)


func stop() -> void:
	if _timer != null:
		_timer.stop()
	if _helper_pid > 0:
		OS.kill(_helper_pid)
		_helper_pid = -1
	_available = false


func _exit_tree() -> void:
	stop()


func _start_helper() -> void:
	if _helper_pid > 0:
		return
	if _helper_exe.is_empty():
		_helper_exe = _ensure_helper()
	if _helper_exe.is_empty():
		push_warning("[Sentinel] helper executable is unavailable")
		return
	var base := OS.get_environment("LOCALAPPDATA")
	if base.is_empty():
		base = OS.get_environment("APPDATA")
	if base.is_empty():
		push_warning("[Sentinel] no LOCALAPPDATA/APPDATA directory")
		return
	_state_dir = base.path_join("DeskPet").path_join("runtime").path_join(str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(_state_dir)
	var arguments: Array[String] = [
		"--run",
		"--parent", str(OS.get_process_id()),
		"--out", _state_dir,
	]
	if _settings != null and _settings.get_bool("sentinel.capture_titles", false):
		arguments.append("--titles")
	_helper_pid = OS.create_process(_helper_exe, PackedStringArray(arguments))
	if _helper_pid <= 0:
		push_warning("[Sentinel] could not start helper: %s" % _helper_exe)
		return
	_stale_polls = 0
	if _timer == null:
		_timer = Timer.new()
		_timer.name = "SentinelPoll"
		_timer.wait_time = 1.0
		_timer.autostart = true
		_timer.timeout.connect(_poll)
		add_child(_timer)
	else:
		_timer.start()


func _ensure_helper() -> String:
	var base := OS.get_environment("LOCALAPPDATA")
	if base.is_empty():
		return ""
	var target_dir := base.path_join("DeskPet").path_join("bin")
	DirAccess.make_dir_recursive_absolute(target_dir)
	var bytes: PackedByteArray = []
	if FileAccess.file_exists(HELPER_RES):
		bytes = FileAccess.get_file_as_bytes(HELPER_RES)
	if bytes.is_empty():
		var installed := OS.get_executable_path().get_base_dir().path_join(HELPER_NAME + ".exe")
		if FileAccess.file_exists(installed):
			return installed
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	var digest := context.finish().hex_encode().substr(0, 12)
	var target := target_dir.path_join("%s-%s.exe" % [HELPER_NAME, digest])
	if FileAccess.file_exists(target):
		return target
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_warning("[Sentinel] cannot extract helper to %s" % target)
		return ""
	file.store_buffer(bytes)
	file.close()
	return target


func _poll() -> void:
	if _state_dir.is_empty():
		return
	var path := _state_dir.path_join("state.json")
	if not FileAccess.file_exists(path):
		_mark_unavailable()
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_mark_unavailable()
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text.trim_prefix("\ufeff"))
	if typeof(parsed) != TYPE_DICTIONARY:
		_mark_unavailable()
		return
	_apply_snapshot(parsed as Dictionary)


func _apply_snapshot(snapshot: Dictionary) -> void:
	if int(snapshot.get("schema", 0)) != SCHEMA:
		return
	var stamp := float(snapshot.get("ts", 0.0))
	if stamp <= _last_ts:
		return
	_last_ts = stamp
	_snapshot = snapshot.duplicate(true)
	_stale_polls = 0
	_restart_attempts = 0
	if not _available:
		_available = true
		availability_changed.emit(true)
	snapshot_updated.emit(get_snapshot())


func _mark_unavailable() -> void:
	_stale_polls += 1
	var stale_seconds := 6
	if _settings != null:
		stale_seconds = _settings.get_int("sentinel.state_stale_seconds", 6)
	if _stale_polls >= maxi(1, stale_seconds):
		if _available:
			_available = false
			availability_changed.emit(false)
		_try_restart()


func _try_restart() -> void:
	if _helper_pid <= 0:
		return
	var now := Time.get_ticks_msec()
	if now < _restart_at_msec:
		return
	if _restart_attempts >= 3:
		return
	_restart_attempts += 1
	if _helper_pid > 0:
		OS.kill(_helper_pid)
		_helper_pid = -1
	_restart_at_msec = now + 5000 * _restart_attempts
	_start_helper()
