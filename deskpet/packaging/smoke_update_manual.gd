extends SceneTree
## Manual update check regression test.
##
## Covers the startup race: 检查更新 used to only show "正在检查或下载更新"
## and never report the result of the silent check already in flight. It also
## covers the normal "new version" and "already latest" manual outcomes.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path deskpet \
##       --script res://packaging/smoke_update_manual.gd

class ProbeUpdate:
	extends "res://scripts/services/update_service.gd"
	var calls: Array[String] = []
	var responses: Array = []
	var delay := 0.0

	func _ready() -> void:
		# Build the real dialog but keep the startup auto check out of the test.
		update_config = ConfigLoader.load_json("res://config/updates.json")
		dialog = AcceptDialog.new()
		dialog.title = "软件更新"
		add_child(dialog)
		_skin_dialog(dialog)

	func _fetch_once(url: String, _file: String = "") -> Array:
		calls.append(url)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		if responses.is_empty():
			return [HTTPRequest.RESULT_CANT_CONNECT, 0, [], PackedByteArray()]
		return responses.pop_front()


func _initialize() -> void:
	call_deferred("run")


func _make_manifest(service: ProbeUpdate, version: String) -> Array:
	var prefixes: Array = service.update_config.get("allowed_download_prefixes", [])
	assert(not prefixes.is_empty())
	var body := JSON.stringify({
		"version": version,
		"url": str(prefixes[0]) + "v" + version + "/DeskPet-Setup-" + version + ".exe",
		"sha256": "a".repeat(64),
	})
	return [HTTPRequest.RESULT_SUCCESS, 200, [], body.to_utf8_buffer()]


func _new_service() -> ProbeUpdate:
	var service := ProbeUpdate.new()
	root.add_child(service)
	service.update_config = ConfigLoader.load_json("res://config/updates.json")
	assert(not service.update_config.is_empty())
	return service


func _confirmation(service: ProbeUpdate) -> ConfirmationDialog:
	for child in service.get_children():
		if child is ConfirmationDialog and child.visible:
			return child
	return null


func run() -> void:
	await _test_manual_while_startup_check_runs()
	await _test_manual_finds_new_version()
	await _test_manual_reports_latest()
	print("PASS: manual update check reports queued startup result, new version and latest version")
	quit()


func _test_manual_while_startup_check_runs() -> void:
	var service := _new_service()
	service.delay = 0.3
	# Failure for GitHub direct plus every configured gateway.
	service.responses = []
	service.check(false)
	await create_timer(0.05).timeout
	assert(service.busy)
	service.check()
	assert(service.busy)
	assert(service.dialog.visible)
	assert(service.dialog.dialog_text == "正在检查更新，请稍候……")
	await create_timer(3.0).timeout
	assert(not service.busy)
	assert(not service.checking)
	assert(service.dialog.visible)
	assert(service.dialog.dialog_text == "暂时无法检查更新，请稍后重试。",
		"queued manual check must report the finished startup check, got: %s" % service.dialog.dialog_text)
	service.queue_free()
	await process_frame


func _test_manual_finds_new_version() -> void:
	var service := _new_service()
	service.responses = [_make_manifest(service, "9.9.9")]
	service.check()
	await create_timer(0.2).timeout
	assert(not service.busy)
	var prompt := _confirmation(service)
	assert(prompt != null, "manual check must offer the new version")
	assert(prompt.dialog_text.contains("9.9.9"))
	assert(not service.dialog.visible)
	service.queue_free()
	await process_frame


func _test_manual_reports_latest() -> void:
	var service := _new_service()
	var current := str(ProjectSettings.get_setting("application/config/version", ""))
	assert(not current.is_empty())
	service.responses = [_make_manifest(service, current)]
	service.check()
	await create_timer(0.2).timeout
	assert(not service.busy)
	assert(_confirmation(service) == null)
	assert(service.dialog.visible)
	assert(service.dialog.dialog_text == "当前为最新版本 " + current)
	service.queue_free()
	await process_frame
