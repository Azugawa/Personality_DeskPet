extends Node
const VERSION := "0.2.3"
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
	_skin_dialog(dialog)
	if not OS.has_feature("editor"):
		check(false)

func _message(message: String) -> void:
	dialog.dialog_text = message
	if not dialog.visible:
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
		if manual: _message("正在检查或下载更新，请稍候……")
		return
	if manual: _message("正在检查更新，请稍候……")
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
		if manual: _message("当前为最新版本 " + VERSION)
		return
	dialog.hide()
	var prompt := ConfirmationDialog.new()
	prompt.title = "发现新版本 " + version
	prompt.dialog_text = "有新版本需要下载：" + version + "\n确定下载并安装？安装程序启动后桌宠将退出。"
	add_child(prompt)
	_skin_dialog(prompt)
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
	_message("正在下载更新，请稍候……")
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

func _skin_dialog(window: AcceptDialog) -> void:
	window.borderless = true
	window.transparent = true
	window.transparent_bg = true
	window.get_ok_button().text = "确定"
	if window is ConfirmationDialog:
		window.get_cancel_button().text = "取消"
	var font: FontFile = load("res://assets/fonts/pixel.ttf")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	window.add_theme_font_override("font", font)
	window.add_theme_font_size_override("font_size", 18)
	window.add_theme_color_override("font_color", Color("173763"))
	var panel := _sheet_style(Rect2(1250,827,270,153), 56)
	panel.content_margin_left = 34
	panel.content_margin_right = 34
	panel.content_margin_top = 52
	panel.content_margin_bottom = 35
	window.add_theme_stylebox_override("panel",panel)
	var drag := preload("res://scripts/ui/dialog_drag.gd").new()
	drag.name = "DialogDrag"
	window.add_child(drag)
	window.get_label().add_theme_font_override("font",font)
	window.get_label().add_theme_font_size_override("font_size",18)
	window.get_label().add_theme_color_override("font_color",Color("173763"))
	for button in [window.get_ok_button(), window.get_cancel_button() if window is ConfirmationDialog else null]:
		if button == null: continue
		# Keep the authored lettering at the same horizontal/vertical scale.
		var button_width := 255.0 * 40.0 / 62.0 if button == window.get_ok_button() else 238.0 * 40.0 / 62.0
		button.custom_minimum_size = Vector2(button_width,40)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.mouse_default_cursor_shape = Control.CURSOR_CROSS
		button.add_theme_font_override("font",font)
		button.add_theme_font_size_override("font_size",18)
		button.add_theme_color_override("font_color",Color.WHITE)
		# Full authored buttons, including both end caps and original pixel lettering.
		var region := Rect2(344,672,255,62) if button == window.get_ok_button() else Rect2(631,672,238,62)
		var normal := _sheet_style(region,0)
		normal.content_margin_left = button_width / 2.0
		normal.content_margin_right = button_width / 2.0
		normal.content_margin_top = 20
		normal.content_margin_bottom = 20
		button.text = ""
		button.tooltip_text = "确定" if button == window.get_ok_button() else "取消"
		button.add_theme_stylebox_override("normal",normal)
		var hover := normal.duplicate()
		hover.modulate_color = Color(0.8,0.9,1)
		button.add_theme_stylebox_override("hover",hover)
		button.add_theme_stylebox_override("pressed",hover)

func _sheet_style(region: Rect2, margin: int) -> StyleBoxTexture:
	# Give nine-slice its own image so UV stretching cannot sample adjacent atlas art.
	var sheet: Texture2D = load("res://assets/ui/dialog_sheet.png")
	var cropped := sheet.get_image().get_region(Rect2i(region))
	if region == Rect2(1250,827,270,153):
		# Trim only the unrelated caption above the panel; preserve the entire
		# original star and border together, without overlays or rebuilt corners.
		cropped.fill_rect(Rect2i(0,0,190,15),Color.TRANSPARENT)
	var texture := ImageTexture.create_from_image(cropped)
	var style := StyleBoxTexture.new()
	style.texture = texture
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,margin)
	return style
