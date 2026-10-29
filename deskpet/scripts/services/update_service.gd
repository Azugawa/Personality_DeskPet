extends Node
const VERSION := "0.2.1"
const FEED := "https://github.com/Azugawa/Personality_DeskPet/releases/latest/download/update.json"
const PREFIX := "https://github.com/Azugawa/Personality_DeskPet/releases/download/"
var update_config: Dictionary = {}
var busy := false
var offer: Dictionary = {}
var dialog: AcceptDialog

func _ready() -> void:
	update_config = ConfigLoader.load_json("res://config/updates.json")
	dialog = AcceptDialog.new()
	dialog.title = "软件更新"
	add_child(dialog)
	if not OS.has_feature("editor"):
		check(false)

func _message(message: String) -> void:
	dialog.dialog_text = message
	dialog.popup_centered(Vector2i(400, 160))

func _fetch_once(url: String, file: String = "") -> Array:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 180 if not file.is_empty() else 12
	http.download_file = file
	http.body_size_limit = 536870912 if not file.is_empty() else 65536
	if http.request(url) != OK:
		http.queue_free()
		return []
	var result: Array = await http.request_completed
	http.queue_free()
	return result

func check(manual: bool = true) -> void:
	if busy:
		return
	busy = true
	var result: Array = []
	for feed in update_config.get("feeds", [FEED]):
		if not str(feed).begins_with("https://"): continue
		result = await _fetch(str(feed))
		if not result.is_empty() and result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200:
			break
	busy = false
	if result.is_empty() or result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		if manual:
			_message("暂时无法检查更新，请稍后重试。")
		return
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8().trim_prefix("\ufeff"))
	if not parsed is Dictionary:
		if manual: _message("更新信息格式无效。")
		return
	offer = parsed
	var version := str(offer.get("version", ""))
	var regex := RegEx.new()
	regex.compile("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	if regex.search(version) == null or not _allowed_download(str(offer.get("url", ""))):
		if manual: _message("更新信息校验失败。")
		return
	var newer := false
	var a := version.split(".")
	var b := VERSION.split(".")
	for i in 3:
		if int(a[i]) != int(b[i]):
			newer = int(a[i]) > int(b[i])
			break
	if not newer:
		if manual: _message("当前已是最新版本 " + VERSION)
		return
	var prompt := ConfirmationDialog.new()
	prompt.title = "发现新版本 " + version
	prompt.dialog_text = "下载更新并启动安装程序？安装程序启动后桌宠将退出。"
	add_child(prompt)
	prompt.confirmed.connect(func():
		prompt.queue_free()
		install_update()
	)
	prompt.canceled.connect(prompt.queue_free)
	prompt.popup_centered(Vector2i(440, 160))

func install_update() -> void:
	if busy: return
	if OS.get_name() != "Windows":
		_message("当前自动安装仅支持 Windows。")
		return
	busy = true
	var path := "user://DeskPet-update.exe"
	var result := await _fetch(str(offer.url), path, str(offer.get("sha256", "")).to_lower())
	busy = false
	if result.is_empty() or result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		_message("下载失败，当前版本未受影响。")
		return
	var expected := str(offer.get("sha256", "")).to_lower()
	if expected.length() != 64 or FileAccess.get_sha256(path) != expected:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_message("安装包校验失败，请重新检查更新。")
		return
	var pid := OS.create_process(ProjectSettings.globalize_path(path), PackedStringArray())
	if pid > 0:
		get_tree().quit()
	else:
		_message("无法启动安装程序。")

func _allowed_download(url: String) -> bool:
	if not url.begins_with("https://"): return false
	for prefix in update_config.get("allowed_download_prefixes", [PREFIX]):
		if url.begins_with(str(prefix)): return true
	return false

func _download_candidates(url: String) -> Array[String]:
	var candidates: Array[String] = [url]
	if url.begins_with("https://github.com/"):
		for prefix in update_config.get("github_proxy_prefixes", []):
			var gateway := str(prefix)
			if gateway.begins_with("https://") and gateway.ends_with("/"):
				candidates.append(gateway + url)
	return candidates

func _fetch(url: String, file: String = "", expected_hash: String = "") -> Array:
	for candidate in _download_candidates(url):
		if not file.is_empty() and FileAccess.file_exists(file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
		var result := await _fetch_once(candidate, file)
		if result.is_empty() or result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
			continue
		if file.is_empty():
			var data: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8().trim_prefix("\ufeff"))
			if not data is Dictionary: continue
			var pattern := RegEx.new()
			pattern.compile("^[0-9]+\\.[0-9]+\\.[0-9]+$")
			if pattern.search(str(data.get("version", ""))) == null: continue
			if not _allowed_download(str(data.get("url", ""))): continue
			pattern.compile("^[0-9a-fA-F]{64}$")
			if pattern.search(str(data.get("sha256", ""))) == null: continue
		elif expected_hash.length() != 64 or FileAccess.get_sha256(file) != expected_hash:
			continue
		return result
	if not file.is_empty() and FileAccess.file_exists(file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	return []
