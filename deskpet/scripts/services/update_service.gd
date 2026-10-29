extends Node
const VERSION := "0.1.0"
const FEED := "https://github.com/Azugawa/Personality_DeskPet/releases/latest/download/update.json"
const PREFIX := "https://github.com/Azugawa/Personality_DeskPet/releases/download/"
var busy := false
var offer: Dictionary = {}
var dialog: AcceptDialog

func _ready() -> void:
	dialog = AcceptDialog.new()
	dialog.title = "软件更新"
	add_child(dialog)
	if not OS.has_feature("editor"):
		check(false)

func _message(message: String) -> void:
	dialog.dialog_text = message
	dialog.popup_centered(Vector2i(400, 160))

func _fetch(url: String, file: String = "") -> Array:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 60
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
	var result := await _fetch(FEED)
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
	if regex.search(version) == null or not str(offer.get("url", "")).begins_with(PREFIX):
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
	var result := await _fetch(str(offer.url), path)
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
