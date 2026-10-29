extends Window
## Temporary assistant window (pixel font) used until the final UI is designed.
##
## Tabs are intentionally minimal: they only exercise the backend contracts.
## Replace this whole window later; the services do not depend on it.

const TAB_REMINDERS := "定时任务"
const TAB_WEATHER := "天气"
const TAB_WORK := "工作模式"
const TAB_STATUS := "系统状态"

var _tabs: TabContainer
var _clock := AssistantClock.new()
var _content_edit: LineEdit
var _time_edit: LineEdit
var _status_label: Label
var _list: VBoxContainer
var _sentinel_summary: Label
var _sentinel_processes: VBoxContainer
var _work_summary: Label
var _work_toggle: Button
var _weather_host: LineEdit
var _weather_key: LineEdit
var _weather_city_name: LineEdit
var _weather_city_lat: LineEdit
var _weather_city_lon: LineEdit
var _weather_status: Label
var _weather_summary: Label
var _weather_advice: Label
var _drive_status: Label
var _drive_summary: Label
var _drive_list: VBoxContainer
var _drive_button: Button
var _autostart_check: CheckBox


func _ready() -> void:
	title = "何爪爪助手（临时界面）"
	size = Vector2i(780, 580)
	min_size = Vector2i(700, 520)
	always_on_top = true
	borderless = false
	var usable := DisplayServer.screen_get_usable_rect()
	position = usable.position + (usable.size - size) / 2
	close_requested.connect(_on_close_requested)
	var theme := Theme.new()
	theme.default_font = PixelDialogSkin.load_font()
	theme.default_font_size = 18
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color("dbe8ff")
	style.border_color = Color("5a86c8")
	style.set_border_width_all(4)
	background.add_theme_stylebox_override("panel", style)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	background.add_child(margin)
	_tabs = TabContainer.new()
	_tabs.add_theme_stylebox_override("panel", _content_style())
	margin.add_child(_tabs)
	_build_reminder_tab()
	_build_weather_tab()
	_build_work_tab()
	_build_status_tab()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)


func _on_tick() -> void:
	_refresh_list()
	_refresh_work()
	_refresh_status()


func open_tab(tab_name: String) -> void:
	if not visible:
		show()
	for index in _tabs.get_tab_count():
		if _tabs.get_tab_title(index) == tab_name:
			_tabs.current_tab = index
			break
	_refresh_list()
	_refresh_work()
	_refresh_status()


func _on_close_requested() -> void:
	hide()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()


func _build_reminder_tab() -> void:
	var page := VBoxContainer.new()
	page.name = TAB_REMINDERS
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)

	var title := Label.new()
	title.text = "定时提醒：指定日期时间，或从当前时间开始计时"
	page.add_child(title)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	page.add_child(input_row)
	_content_edit = LineEdit.new()
	_content_edit.placeholder_text = "提醒内容，例如：喝水 / 交作业"
	_content_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(_content_edit)
	_time_edit = LineEdit.new()
	_time_edit.placeholder_text = "YYYY-MM-DD HH:MM"
	_time_edit.custom_minimum_size = Vector2(210, 0)
	_time_edit.text = _clock.format_local(_clock.now() + 600)
	input_row.add_child(_time_edit)
	var add_button := Button.new()
	add_button.text = "添加"
	add_button.pressed.connect(_add_at_time)
	input_row.add_child(add_button)

	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 8)
	page.add_child(quick_row)
	for seconds in [10, 300, 900, 1800, 3600]:
		var button := Button.new()
		button.text = _quick_label(seconds)
		button.pressed.connect(_add_after.bind(seconds))
		quick_row.add_child(button)

	_status_label = Label.new()
	_status_label.text = "待提醒：0 条"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_refresh_list()


func _build_weather_tab() -> void:
	var page := VBoxContainer.new()
	page.name = TAB_WEATHER
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "和风天气：填写 API Host 与 API Key；坐标只用于天气请求"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	var settings: Node = FeatureServices.settings
	if settings == null:
		var missing := Label.new()
		missing.text = "设置服务未初始化"
		page.add_child(missing)
		return
	var service: Node = FeatureServices.get_provider("weather")
	if service != null:
		service.weather_ready.connect(_on_weather_ready)
		service.failed.connect(_on_weather_failed)
	var api_row := HBoxContainer.new()
	api_row.add_theme_constant_override("separation", 8)
	page.add_child(api_row)
	api_row.add_child(_label("API Host"))
	_weather_host = LineEdit.new()
	_weather_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather_host.placeholder_text = "https://xxxx.re.qweatherapi.com"
	_weather_host.text = settings.get_string("weather.api_host", "")
	api_row.add_child(_weather_host)
	api_row.add_child(_label("API Key"))
	_weather_key = LineEdit.new()
	_weather_key.secret = true
	_weather_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather_key.placeholder_text = "和风天气 API Key"
	_weather_key.text = settings.get_secret("weather.api_key", "")
	api_row.add_child(_weather_key)
	var save_api := Button.new()
	save_api.text = "保存"
	save_api.pressed.connect(_save_weather_settings)
	api_row.add_child(save_api)

	var city_row := HBoxContainer.new()
	city_row.add_theme_constant_override("separation", 8)
	page.add_child(city_row)
	city_row.add_child(_label("手动城市"))
	_weather_city_name = LineEdit.new()
	_weather_city_name.placeholder_text = "名称"
	_weather_city_name.custom_minimum_size = Vector2(110, 0)
	city_row.add_child(_weather_city_name)
	_weather_city_lat = LineEdit.new()
	_weather_city_lat.placeholder_text = "纬度"
	_weather_city_lat.custom_minimum_size = Vector2(90, 0)
	city_row.add_child(_weather_city_lat)
	_weather_city_lon = LineEdit.new()
	_weather_city_lon.placeholder_text = "经度"
	_weather_city_lon.custom_minimum_size = Vector2(90, 0)
	city_row.add_child(_weather_city_lon)
	var save_city := Button.new()
	save_city.text = "使用手动城市"
	save_city.pressed.connect(_save_manual_city)
	city_row.add_child(save_city)
	var use_system := Button.new()
	use_system.text = "使用系统定位"
	use_system.pressed.connect(_use_system_location)
	city_row.add_child(use_system)
	var refresh_button := Button.new()
	refresh_button.text = "刷新天气"
	refresh_button.pressed.connect(_refresh_weather)
	city_row.add_child(refresh_button)
	var city: Dictionary = settings.get_dict("weather.manual_city", {})
	_weather_city_name.text = str(city.get("name", ""))
	_weather_city_lat.text = str(city.get("lat", ""))
	_weather_city_lon.text = str(city.get("lon", ""))

	_weather_status = Label.new()
	_weather_status.text = "尚未查询天气"
	_weather_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_weather_status)
	_weather_summary = Label.new()
	_weather_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_weather_summary)
	_weather_advice = Label.new()
	_weather_advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_weather_advice)
	_refresh_weather_cache()


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _content_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("dbe8ff")
	style.set_corner_radius_all(4)
	return style


func _save_weather_settings() -> void:
	var settings: Node = FeatureServices.settings
	if settings == null:
		return
	settings.set_value("weather.api_host", _weather_host.text.strip_edges())
	settings.set_secret("weather.api_key", _weather_key.text.strip_edges())
	_weather_status.text = "设置已保存，正在刷新……"
	_refresh_weather()


func _save_manual_city() -> void:
	var settings: Node = FeatureServices.settings
	if settings == null:
		return
	var lat := _weather_city_lat.text.strip_edges().to_float()
	var lon := _weather_city_lon.text.strip_edges().to_float()
	if absf(lat) > 90.0 or absf(lon) > 180.0 or (is_zero_approx(lat) and is_zero_approx(lon)):
		_weather_status.text = "纬度/经度无效"
		return
	var name := _weather_city_name.text.strip_edges()
	if name.is_empty():
		name = "手动位置"
	settings.set_value("weather.manual_city", {"name": name, "lat": lat, "lon": lon})
	settings.set_value("weather.location_mode", "manual")
	_weather_status.text = "已切换到手动城市，正在刷新……"
	_refresh_weather()


func _use_system_location() -> void:
	var settings: Node = FeatureServices.settings
	if settings == null:
		return
	settings.set_value("weather.location_mode", "system")
	_weather_status.text = "已切换到系统定位，正在刷新……"
	_refresh_weather()


func _refresh_weather() -> void:
	var service: Node = FeatureServices.get_provider("weather")
	if service == null:
		_weather_status.text = "天气服务未初始化"
		return
	_weather_status.text = "正在查询天气……"
	service.refresh(true)


func _refresh_weather_cache() -> void:
	var service: Node = FeatureServices.get_provider("weather")
	if service == null:
		return
	var cached: Dictionary = service.get_cached()
	if not cached.is_empty():
		_on_weather_ready(cached)
	else:
		_weather_status.text = "尚未查询天气，填写 API 配置后点“刷新天气”"


func _on_weather_ready(result: Dictionary) -> void:
	if _weather_status == null:
		return
	var location: Dictionary = result.get("location", {})
	var current: Dictionary = result.get("current", {})
	var today: Dictionary = result.get("today", {})
	var tomorrow: Dictionary = result.get("tomorrow", {})
	var advice: Array = result.get("advice", [])
	var stamp := _clock.format_local(int(result.get("fetched_at", 0)))
	var suffix := "（缓存，可能不是最新）" if bool(result.get("stale", false)) else ""
	var resolution := int(result.get("resolution_km", 0))
	var resolution_text := (" · %dkm 格点" % resolution) if resolution > 0 else ""
	_weather_status.text = "更新时间：%s%s  %s" % [stamp, suffix, str(result.get("error", ""))]
	_weather_summary.text = "位置：%s（%s）%s\n现在：%.0f°C %s，湿度 %d%%，风 %.1f m/s\n今天：%.0f~%.0f°C %s，降雨概率 %d%%\n明天：%.0f~%.0f°C %s，降雨概率 %d%%" % [
		str(location.get("name", "当前位置")),
		str(location.get("source", "system")),
		resolution_text,
		float(current.get("temp_c", 0.0)),
		str(current.get("text", "")),
		int(current.get("humidity", 0)),
		float(current.get("wind_ms", 0.0)),
		float(today.get("min_c", 0.0)),
		float(today.get("max_c", 0.0)),
		str(today.get("text", "")),
		int(today.get("pop", 0)),
		float(tomorrow.get("min_c", 0.0)),
		float(tomorrow.get("max_c", 0.0)),
		str(tomorrow.get("text", "")),
		int(tomorrow.get("pop", 0)),
	]
	var advice_lines: Array[String] = []
	for item in advice:
		advice_lines.append("• " + str(item))
	_weather_advice.text = "建议：\n" + "\n".join(advice_lines)


func _on_weather_failed(message: String) -> void:
	if _weather_status != null:
		_weather_status.text = "天气查询失败：" + message


func _build_work_tab() -> void:
	var page := VBoxContainer.new()
	page.name = TAB_WORK
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "工作模式：Word / WPS / PPT / Excel / PDF 前台时自动开启；离开 10 分钟自动关闭"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	_work_summary = Label.new()
	_work_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_work_summary)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	page.add_child(row)
	_work_toggle = Button.new()
	_work_toggle.text = "开启工作模式"
	_work_toggle.pressed.connect(_toggle_work_mode)
	row.add_child(_work_toggle)
	var break_button := Button.new()
	break_button.text = "立即休息 5 分钟"
	break_button.pressed.connect(_start_break)
	row.add_child(break_button)
	var skip_button := Button.new()
	skip_button.text = "跳过本轮"
	skip_button.pressed.connect(_skip_break)
	row.add_child(skip_button)
	_refresh_work()


func _toggle_work_mode() -> void:
	var service: Node = FeatureServices.get_provider("work_mode")
	if service == null:
		return
	if str(service.get_state().get("mode", "off")) == "off":
		service.enable_manual()
	else:
		service.disable_manual()
	_refresh_work()


func _start_break() -> void:
	var service: Node = FeatureServices.get_provider("work_mode")
	if service != null:
		service.start_break()
	_refresh_work()


func _skip_break() -> void:
	var service: Node = FeatureServices.get_provider("work_mode")
	if service != null:
		service.skip_break()
	_refresh_work()


func _refresh_work() -> void:
	if _work_summary == null:
		return
	var service: Node = FeatureServices.get_provider("work_mode")
	if service == null:
		_work_summary.text = "工作模式服务未初始化"
		return
	var state: Dictionary = service.get_state()
	var mode := str(state.get("mode", "off"))
	var phase := str(state.get("phase", "work"))
	var busy_text := "休息中" if phase == "break" else "工作中"
	if mode == "off":
		busy_text = "未开启"
	_work_toggle.text = "关闭工作模式" if mode != "off" else "开启工作模式"
	_work_summary.text = "状态：%s（%s）  剩余：%s\n前台：%s  办公软件：%s  空闲：%d 秒\n自动开启：30 秒；无办公软件自动关闭：自动 2 分钟 / 手动 10 分钟" % [
		busy_text,
		mode,
		_clock.format_duration(int(state.get("remaining_seconds", 0))),
		str(state.get("foreground", "无")),
		"是" if bool(state.get("office", false)) else "否",
		int(state.get("idle_seconds", 0)),
	]


func _build_status_tab() -> void:
	var page := VBoxContainer.new()
	page.name = TAB_STATUS
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "系统状态（哨兵每 1 秒刷新；C 盘分析只读，不会删除文件）"
	page.add_child(title)
	_sentinel_summary = Label.new()
	_sentinel_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sentinel_summary.text = "哨兵启动中……"
	page.add_child(_sentinel_summary)
	var process_title := Label.new()
	process_title.text = "占用较高的程序："
	page.add_child(process_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	_sentinel_processes = VBoxContainer.new()
	_sentinel_processes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sentinel_processes)
	_refresh_status()
	var drive_title := Label.new()
	drive_title.text = "C 盘非必要文件（定向扫描，最多 60 秒）"
	page.add_child(drive_title)
	_drive_status = Label.new()
	_drive_status.text = "尚未扫描"
	_drive_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_drive_status)
	_drive_button = Button.new()
	_drive_button.text = "检查 C 盘"
	_drive_button.pressed.connect(_on_drive_button)
	page.add_child(_drive_button)
	_drive_summary = Label.new()
	_drive_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_drive_summary)
	var drive_scroll := ScrollContainer.new()
	drive_scroll.custom_minimum_size = Vector2(0, 150)
	page.add_child(drive_scroll)
	_drive_list = VBoxContainer.new()
	_drive_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drive_scroll.add_child(_drive_list)
	var drive: Node = FeatureServices.get_provider("drive_analysis")
	if drive != null:
		drive.scan_started.connect(_on_drive_started)
		drive.scan_progress.connect(_on_drive_progress)
		drive.scan_finished.connect(_on_drive_finished)
		drive.scan_failed.connect(_on_drive_failed)
		var cached: Dictionary = drive.get_cached()
		if not cached.is_empty():
			_render_drive(cached)
	var autostart: Node = FeatureServices.get_provider("autostart")
	_autostart_check = CheckBox.new()
	_autostart_check.text = "开机自动启动（推荐，定时提醒更可靠）"
	if autostart != null:
		_autostart_check.button_pressed = autostart.is_enabled()
		_autostart_check.toggled.connect(_on_autostart_toggled)
	page.add_child(_autostart_check)


func _on_autostart_toggled(pressed: bool) -> void:
	var service: Node = FeatureServices.get_provider("autostart")
	if service == null:
		return
	if not service.set_enabled(pressed):
		_autostart_check.set_pressed_no_signal(not pressed)
		if _drive_status != null:
			_drive_status.text = "自启设置未修改（编辑器环境不支持或注册表写入失败）"


func _on_drive_button() -> void:
	var drive: Node = FeatureServices.get_provider("drive_analysis")
	if drive == null:
		return
	if drive.is_scanning():
		drive.cancel_scan()
		_drive_button.text = "正在取消……"
		return
	if drive.start_scan():
		_drive_button.text = "取消扫描"
		_drive_status.text = "正在扫描……"


func _on_drive_started(_scan_id: String) -> void:
	if _drive_status != null:
		_drive_status.text = "正在扫描……"
	if _drive_button != null:
		_drive_button.text = "取消扫描"


func _on_drive_progress(progress: Dictionary) -> void:
	if _drive_status == null:
		return
	_drive_status.text = "已扫描 %d 个文件，匹配 %d 个，累计 %s" % [
		int(progress.get("files_scanned", 0)),
		int(progress.get("matched", 0)),
		_format_size(int(progress.get("bytes", 0))),
	]


func _on_drive_finished(result: Dictionary) -> void:
	if _drive_button != null:
		_drive_button.text = "检查 C 盘"
	_render_drive(result)


func _on_drive_failed(message: String) -> void:
	if _drive_status != null:
		_drive_status.text = "C 盘分析：%s" % message
	if _drive_button != null:
		_drive_button.text = "检查 C 盘"


func _render_drive(result: Dictionary) -> void:
	if _drive_summary == null:
		return
	if _drive_status != null:
		_drive_status.text = "扫描完成%s" % ("（达到时间/数量上限，结果不完整）" if bool(result.get("truncated", false)) else "")
	var totals: Dictionary = result.get("totals", {})
	var parts: Array[String] = []
	for category in totals.keys():
		parts.append("%s %s" % [_category_label(str(category)), _format_size(int(totals[category]))])
	_drive_summary.text = "共 %d 个可整理文件，合计 %s。%s\n建议手动移动到其他盘；本功能不会删除或移动文件。" % [
		int(result.get("matched", 0)),
		_format_size(int(result.get("bytes", 0))),
		"，".join(parts),
	]
	for child in _drive_list.get_children():
		child.queue_free()
	var candidates: Array = result.get("candidates", [])
	for index in mini(candidates.size(), 20):
		var item: Dictionary = candidates[index]
		var label := Label.new()
		label.text = "%s  %s  %s" % [
			_format_size(int(item.get("size", 0))),
			_category_label(str(item.get("category", ""))),
			str(item.get("path", "")),
		]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_drive_list.add_child(label)


func _category_label(category: String) -> String:
	match category:
		"video": return "视频"
		"audio": return "音频"
		"archive": return "压缩包"
		"installer": return "安装包"
		"document": return "文档"
		"disk_image": return "镜像"
	return category


func _format_size(bytes: int) -> String:
	if bytes >= 1073741824:
		return "%.1f GB" % (float(bytes) / 1073741824.0)
	return "%.1f MB" % (float(bytes) / 1048576.0)


func _refresh_status() -> void:
	if _sentinel_summary == null:
		return
	var service: Node = FeatureServices.get_provider("sentinel")
	if service == null:
		_sentinel_summary.text = "哨兵服务未初始化"
		return
	if not service.is_available():
		_sentinel_summary.text = "哨兵未就绪（助手启动中或不可用）"
		for child in _sentinel_processes.get_children():
			child.queue_free()
		return
	var snapshot: Dictionary = service.get_snapshot()
	var disk: Dictionary = snapshot.get("disk_c", {})
	var foreground: Dictionary = snapshot.get("foreground", {})
	var free_bytes := int(disk.get("free", 0))
	var total_bytes := int(disk.get("total", 0))
	var free_percent := 0.0
	if total_bytes > 0:
		free_percent = float(free_bytes) / float(total_bytes) * 100.0
	_sentinel_summary.text = "CPU：%.1f%%    空闲：%d 秒\nC 盘剩余：%s / %s（%.1f%%）\n前台程序：%s%s" % [
		float(snapshot.get("cpu_percent", 0.0)),
		int(snapshot.get("idle_seconds", 0)),
		_format_gb(free_bytes),
		_format_gb(total_bytes),
		free_percent,
		str(foreground.get("process", "未知")),
		"（全屏）" if bool(foreground.get("fullscreen", false)) else "",
	]
	for child in _sentinel_processes.get_children():
		child.queue_free()
	for item_value in service.top_processes():
		var item: Dictionary = item_value
		var label := Label.new()
		label.text = "%s  %.1f%%" % [str(item.get("process", "?")), float(item.get("cpu_percent", 0.0))]
		_sentinel_processes.add_child(label)


func _format_gb(bytes: int) -> String:
	return "%.1f GB" % (float(bytes) / 1073741824.0)


func _add_at_time() -> void:
	var parsed := _clock.parse_local(_time_edit.text)
	if parsed.is_empty():
		_set_status("时间格式应为 YYYY-MM-DD HH:MM")
		return
	var result: Dictionary = FeatureServices.reminder.add_at(_content_edit.text, int(parsed.get("unix", 0)))
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("error", "添加失败")))
		return
	_content_edit.text = ""
	_set_status("已添加提醒")
	_refresh_list()


func _add_after(seconds: int) -> void:
	var result: Dictionary = FeatureServices.reminder.add_after(_content_edit.text, seconds)
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("error", "添加失败")))
		return
	_content_edit.text = ""
	_set_status("已添加提醒")
	_refresh_list()


func _delete(id: String) -> void:
	FeatureServices.reminder.cancel(id)
	_refresh_list()


func _refresh_list() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var items: Array = FeatureServices.reminder.list_pending() if FeatureServices.reminder != null else []
	_status_label.text = "待提醒：%d 条" % items.size()
	for item_value in items:
		var item: Dictionary = item_value
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = "%s  |  %s  |  剩余 %s" % [
			str(item.get("text", "")),
			_clock.format_local(int(item.get("due_at", 0))),
			_clock.format_duration(int(item.get("due_at", 0)) - _clock.now()),
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var delete_button := Button.new()
		delete_button.text = "删除"
		delete_button.pressed.connect(_delete.bind(str(item.get("id", ""))))
		row.add_child(delete_button)
		_list.add_child(row)


func _quick_label(seconds: int) -> String:
	if seconds < 60:
		return "%d 秒后" % seconds
	var minutes := int(seconds / 60.0)
	if minutes < 60:
		return "%d 分钟后" % minutes
	return "%d 小时后" % int(minutes / 60.0)


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
