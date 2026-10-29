extends SceneTree
## Drive analysis integration test on a temporary fixture directory.

const SettingsScript := preload("res://scripts/services/settings_service.gd")
const DriveScript := preload("res://scripts/services/drive_analysis_service.gd")

var _root_dir := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_root_dir = OS.get_environment("TEMP").path_join("deskpet_drive_%d" % Time.get_ticks_usec())
	var fixture := _root_dir.path_join("fixture")
	var nested := fixture.path_join("sub")
	var excluded := fixture.path_join("node_modules")
	DirAccess.make_dir_recursive_absolute(nested)
	DirAccess.make_dir_recursive_absolute(excluded)
	_write_file(fixture.path_join("a.mp4"), 2 * 1024 * 1024)
	_write_file(fixture.path_join("b.txt"), 2 * 1024 * 1024)
	_write_file(nested.path_join("c.pdf"), 1 * 1024 * 1024)
	_write_file(nested.path_join("skip.tmp"), 2 * 1024 * 1024)
	_write_file(excluded.path_join("d.mp4"), 2 * 1024 * 1024)
	var settings = SettingsScript.new()
	settings.setup(_root_dir.path_join("settings.json"), _root_dir.path_join("secrets.json"))
	settings.set_value("drive_analysis.roots", [fixture])
	settings.set_value("drive_analysis.exclude_dirs", ["node_modules"])
	settings.set_value("drive_analysis.exclude_extensions", [".tmp"])
	settings.set_value("drive_analysis.categories", {"video": [".mp4"], "document": [".pdf"]})
	settings.set_value("drive_analysis.large_file_mb", 1)
	settings.set_value("drive_analysis.document_mb", 1)
	settings.set_value("drive_analysis.max_scan_seconds", 20)
	settings.set_value("drive_analysis.max_candidates", 50)
	var service = DriveScript.new()
	root.add_child(service)
	var clock := AssistantClock.new()
	clock.set_fixed_now(1793311200)
	service.setup(settings, null, clock, _root_dir.path_join("cache.json"))
	var finished: Array = []
	var failed: Array = []
	service.scan_finished.connect(func(result: Dictionary): finished.append(result))
	service.scan_failed.connect(func(message: String): failed.append(message))
	assert(service.start_scan())
	for _attempt in 40:
		await create_timer(0.5).timeout
		if not finished.is_empty() or not failed.is_empty():
			break
	assert(failed.is_empty(), "scan failed: %s" % str(failed))
	assert(finished.size() == 1)
	var result: Dictionary = finished[0]
	assert(int(result.get("matched", 0)) == 2)
	assert(int(result.get("files_scanned", 0)) == 4)
	var totals: Dictionary = result.get("totals", {})
	assert(int(totals.get("video", 0)) == 2 * 1024 * 1024)
	assert(int(totals.get("document", 0)) == 1 * 1024 * 1024)
	assert((result.get("candidates", []) as Array).size() == 2)
	assert(not service.get_cached().is_empty())
	service.queue_free()
	settings.free()
	JsonStore.remove_tree(_root_dir)
	print("PASS: drive analysis fixture scan")
	quit()


func _write_file(path: String, size: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.resize(size)
	file.close()
