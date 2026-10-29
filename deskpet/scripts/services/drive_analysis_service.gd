extends Node
## C: drive analysis coordinator.
##
## The actual enumeration runs in DeskPetSentinel.exe with a time/file cap and
## background I/O priority. This service only builds the config, polls progress
## and exposes results. It never deletes or moves files.

signal scan_started(scan_id: String)
signal scan_progress(progress: Dictionary)
signal scan_finished(result: Dictionary)
signal scan_failed(message: String)

const CACHE_PATH := "user://cache/drive_scan.json"
const SCHEMA := 1

var _settings: Node
var _sentinel: Node
var _clock: AssistantClock
var _cache_path := CACHE_PATH
var _cache: Dictionary = {}
var _busy := false
var _scan_id := ""
var _out_dir := ""
var _helper_pid := -1
var _started_msec := 0
var _timer: Timer
var _max_seconds := 60


func setup(settings: Node, sentinel: Node = null, clock: AssistantClock = null, cache_path: String = CACHE_PATH) -> void:
	_settings = settings
	_sentinel = sentinel
	_clock = clock if clock != null else AssistantClock.new()
	_cache_path = cache_path
	_cache = JsonStore.load_dict(_cache_path, {})
	if int(_cache.get("schema", 0)) != SCHEMA:
		_cache = {}


func is_scanning() -> bool:
	return _busy


func get_cached() -> Dictionary:
	return _cache.duplicate(true)


func start_scan() -> bool:
	if _busy:
		return false
	var helper := _helper_path()
	if helper.is_empty():
		scan_failed.emit("扫描助手不可用")
		return false
	var base := OS.get_environment("LOCALAPPDATA")
	if base.is_empty():
		scan_failed.emit("无法定位本地数据目录")
		return false
	_cleanup_runtime(base)
	_scan_id = "scan-%d" % Time.get_ticks_msec()
	_out_dir = base.path_join("DeskPet").path_join("runtime").path_join(_scan_id)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var config := _build_config()
	var config_path := _out_dir.path_join("config.json")
	if not JsonStore.save_dict(config_path, config):
		scan_failed.emit("无法写入扫描配置")
		return false
	_max_seconds = int(config.get("max_seconds", 60))
	_helper_pid = OS.create_process(helper, PackedStringArray([
		"--scan",
		"--out", _out_dir,
		"--config", config_path,
		"--scan-id", _scan_id,
	]))
	if _helper_pid <= 0:
		scan_failed.emit("无法启动扫描助手")
		return false
	_busy = true
	_started_msec = Time.get_ticks_msec()
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(_poll)
	add_child(_timer)
	scan_started.emit(_scan_id)
	return true


func cancel_scan() -> void:
	if not _busy or _out_dir.is_empty():
		return
	JsonStore.save_dict(_out_dir.path_join("cancel-" + _scan_id), {"cancel": true})


func _poll() -> void:
	if not _busy:
		return
	var progress_path := _out_dir.path_join("scan-" + _scan_id + ".progress.json")
	if FileAccess.file_exists(progress_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(progress_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			scan_progress.emit(parsed)
	var result_path := _out_dir.path_join("scan-" + _scan_id + ".json")
	if FileAccess.file_exists(result_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_finish(parsed)
			return
	if Time.get_ticks_msec() - _started_msec > (_max_seconds + 30) * 1000:
		cancel_scan()
		if _helper_pid > 0:
			OS.kill(_helper_pid)
			_helper_pid = -1
		_fail("扫描超时")


func _finish(result: Dictionary) -> void:
	_busy = false
	if _timer != null:
		_timer.stop()
		_timer.queue_free()
		_timer = null
	if _helper_pid > 0:
		# The helper exits by itself after writing the result.
		_helper_pid = -1
	_cache = result.duplicate(true)
	_cache["schema"] = SCHEMA
	JsonStore.save_dict(_cache_path, _cache)
	if bool(result.get("cancelled", false)):
		scan_failed.emit("扫描已取消")
		return
	if not str(result.get("error", "")).is_empty():
		scan_failed.emit(str(result.get("error", "扫描失败")))
		return
	scan_finished.emit(result.duplicate(true))


func _fail(message: String) -> void:
	_busy = false
	if _timer != null:
		_timer.stop()
		_timer.queue_free()
		_timer = null
	scan_failed.emit(message)


func _build_config() -> Dictionary:
	var roots: Array = []
	var user_profile := OS.get_environment("USERPROFILE")
	for root in _settings.get_array("drive_analysis.roots", []):
		roots.append(str(root).replace("{USER}", user_profile))
	return {
		"roots": roots,
		"exclude_dirs": _settings.get_array("drive_analysis.exclude_dirs", []),
		"exclude_extensions": _settings.get_array("drive_analysis.exclude_extensions", []),
		"categories": _settings.get_dict("drive_analysis.categories", {}),
		"large_file_mb": _settings.get_int("drive_analysis.large_file_mb", 100),
		"document_mb": _settings.get_int("drive_analysis.document_mb", 50),
		"max_seconds": _settings.get_int("drive_analysis.max_scan_seconds", 60),
		"max_files": _settings.get_int("drive_analysis.max_files", 200000),
		"max_candidates": _settings.get_int("drive_analysis.max_candidates", 200),
	}


func _cleanup_runtime(base: String) -> void:
	var runtime := base.path_join("DeskPet").path_join("runtime")
	if not DirAccess.dir_exists_absolute(runtime):
		return
	var dir := DirAccess.open(runtime)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("scan-"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for name in names:
		JsonStore.remove_tree(runtime.path_join(name))


func _helper_path() -> String:
	if _sentinel != null and _sentinel.has_method("helper_executable"):
		var extracted: String = _sentinel.helper_executable()
		if not extracted.is_empty():
			return extracted
	if FileAccess.file_exists("res://bin/DeskPetSentinel.exe"):
		return ProjectSettings.globalize_path("res://bin/DeskPetSentinel.exe")
	var installed := OS.get_executable_path().get_base_dir().path_join("DeskPetSentinel.exe")
	if FileAccess.file_exists(installed):
		return installed
	return ""
