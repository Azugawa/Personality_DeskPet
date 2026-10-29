extends SceneTree
## Sentinel helper + service tests. Runs the real helper once and then starts the
## persistent sampler for a few seconds.

const SettingsScript := preload("res://scripts/services/settings_service.gd")
const SentinelScript := preload("res://scripts/services/sentinel_service.gd")

var _root_dir := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_root_dir = OS.get_environment("TEMP").path_join("deskpet_sentinel_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_root_dir)
	var helper := ProjectSettings.globalize_path("res://bin/DeskPetSentinel.exe")
	assert(FileAccess.file_exists(helper))
	_test_helper_once(helper)
	await _test_service(helper)
	JsonStore.remove_tree(_root_dir)
	print("PASS: sentinel helper and service")
	quit()


func _test_helper_once(helper: String) -> void:
	var out_dir := _root_dir.path_join("once")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var output: Array = []
	var code := OS.execute(helper, PackedStringArray(["--once", "--out", out_dir]), output, true)
	assert(code == 0)
	var path := out_dir.path_join("once.json")
	assert(FileAccess.file_exists(path))
	var snapshot: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(typeof(snapshot) == TYPE_DICTIONARY)
	var data: Dictionary = snapshot
	assert(int(data.get("schema", 0)) == 1)
	assert(data.has("cpu_percent"))
	assert(data.has("foreground"))
	assert(int((data.get("disk_c", {}) as Dictionary).get("total", 0)) > 0)


func _test_service(_helper: String) -> void:
	var settings = SettingsScript.new()
	settings.setup(_root_dir.path_join("settings.json"), _root_dir.path_join("secrets.json"))
	var service = SentinelScript.new()
	root.add_child(service)
	service.setup(settings, true)
	await create_timer(8.0).timeout
	assert(service.is_available(), "sentinel service did not receive a helper snapshot")
	var snapshot: Dictionary = service.get_snapshot()
	assert(int(snapshot.get("schema", 0)) == 1)
	assert(float(snapshot.get("cpu_percent", -1.0)) >= 0.0)
	assert(int((snapshot.get("disk_c", {}) as Dictionary).get("total", 0)) > 0)
	assert(snapshot.get("foreground") is Dictionary)
	service.stop()
	await create_timer(0.2).timeout
	service.queue_free()
	settings.free()
	await process_frame
