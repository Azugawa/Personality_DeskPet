extends Node
const VERSION := "0.3.3"
# GitHub remains the fallback; config/updates.json puts the Gitee feed first.
const FEED := "https://github.com/Azugawa/Personality_DeskPet/releases/latest/download/update.json"
const PREFIX := "https://github.com/Azugawa/Personality_DeskPet/releases/download/"
const GITEE_FEED := "https://gitee.com/shengge-zichuan/personality_-deskpet/raw/main/update.json"
const GITEE_PREFIX := "https://gitee.com/shengge-zichuan/personality_-deskpet/releases/download/"
var update_config: Dictionary = {}
var busy := false
var offer: Dictionary = {}
var dialog: AcceptDialog
# True while a feed check (not a download) is running; the automatic startup
# check can still be in flight when the user asks for a manual check.
var checking := false
# Set when 检查更新 is clicked during an automatic check. The running check then
# reports its own result instead of leaving a "please wait" dialog on screen.
var _manual_queued := false

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
		if not manual: return
		if checking:
			# The silent check started at launch is still running. Ask for its
			# result to be shown when it finishes instead of a dead-end message.
			_manual_queued = true
			_message("正在检查更新，请稍候……")
		else:
			_message("正在检查或下载更新，请稍候……")
		return
	if manual: _message("正在检查更新，请稍候……")
	busy = true
	checking = true
	var result: Array = []
	for feed in update_config.get("feeds", [FEED]):
		if not str(feed).begins_with("https://"): continue
		result = await _fetch(str(feed))
		if not result.is_empty() and result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200:
			break
	busy = false
	checking = false
	var report := manual or _manual_queued
	_manual_queued = false
	if result.is_empty() or result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		if report:
			_message("暂时无法检查更新，请稍后重试。")
		return
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8().trim_prefix("\ufeff"))
	if not parsed is Dictionary:
		if report: _message("更新信息格式无效。")
		return
	offer = parsed
	var version := str(offer.get("version", ""))
	var regex := RegEx.new()
	regex.compile("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	if regex.search(version) == null or not _allowed_download(str(offer.get("url", ""))):
		if report: _message("更新信息校验失败。")
		return
	var newer := false
	var a := version.split(".")
	var b := VERSION.split(".")
	for i in 3:
		if int(a[i]) != int(b[i]):
			newer = int(a[i]) > int(b[i])
			break
	if not newer:
		if report: _message("当前为最新版本 " + VERSION)
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
	if offer.has("resource_update") and FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("DeskPetUpdater.exe")):
		await _install_chunks()
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
	var bases: Array[String] = [url]
	for rule in update_config.get("asset_mirrors", []):
		if typeof(rule) != TYPE_DICTIONARY: continue
		var from := str(rule.get("from", ""))
		var to := str(rule.get("to", ""))
		if from.is_empty() or to.is_empty() or not url.begins_with(from): continue
		bases.append(to + url.substr(from.length()))
	var candidates: Array[String] = []
	for base in bases:
		if not candidates.has(base):
			candidates.append(base)
		if base.begins_with("https://github.com/"):
			for prefix in update_config.get("github_proxy_prefixes", []):
				var gateway := str(prefix)
				if gateway.begins_with("https://") and gateway.ends_with("/"):
					var proxied := gateway + base
					if not candidates.has(proxied):
						candidates.append(proxied)
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
	PixelDialogSkin.apply(window)
	window.get_ok_button().text = "确定"
	if window is ConfirmationDialog: window.get_cancel_button().text = "取消"
	var drag := preload("res://scripts/ui/dialog_drag.gd").new()
	drag.name = "DialogDrag"
	window.add_child(drag)


func _sheet_style(region: Rect2, margin: int) -> StyleBoxTexture:
	# Give nine-slice its own image so UV stretching cannot sample adjacent atlas art.
	var sheet: Texture2D = load("res://assets/ui/panels/dialog_sheet.png")
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

func _install_chunks() -> void:
	var plan: Dictionary = offer.resource_update
	if plan.get("format") != 1 or plan.get("engine") != "4.7.2":
		_message("此版本需要更新运行引擎，请下载安装包。")
		return
	busy = true
	var old := FileAccess.open(OS.get_executable_path().get_base_dir().path_join("DeskPet.pck"),FileAccess.READ)
	var staged := FileAccess.open("user://resource-update.pck",FileAccess.WRITE)
	if old == null or staged == null:
		busy = false
		_message("无法读取或写入更新文件。")
		return
	var hashes: Dictionary = {}
	while old.get_position()<old.get_length():
		var offset := old.get_position()
		var data := old.get_buffer(1048576)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(data)
		hashes[hash.finish().hex_encode()] = offset
	var index := 0
	var ok := true
	for part in plan.get("chunks",[]):
		index += 1
		_message("正在更新资源：%d / %d" % [index,plan.chunks.size()])
		var size := int(part.get("size",0))
		var digest := str(part.get("sha256",""))
		if size<=0 or size>1048576 or digest.length()!=64 or not _allowed_download(str(part.get("url",""))):
			ok = false
			break
		if hashes.has(digest):
			old.seek(hashes[digest])
			staged.store_buffer(old.get_buffer(size))
		else:
			var result := await _fetch(str(part.url),"user://update-chunk.bin",digest)
			if result.is_empty():
				ok = false
				break
			staged.store_buffer(FileAccess.get_file_as_bytes("user://update-chunk.bin"))
	old.close()
	staged.close()
	busy = false
	if not ok or FileAccess.get_sha256("user://resource-update.pck") != str(plan.get("sha256","")):
		_message("增量更新下载或校验失败，原版本未改变。")
		return
	var pid := OS.create_process(OS.get_executable_path().get_base_dir().path_join("DeskPetUpdater.exe"),PackedStringArray([str(OS.get_process_id()),ProjectSettings.globalize_path("user://resource-update.pck"),str(plan.sha256),str(offer.version)]))
	if pid>0: get_tree().quit()
	else: _message("无法启动更新器，原版本未改变。")
