extends Window
## Independent pixel panels backed by the existing assistant services.

const TAB_REMINDERS := "定时任务"
const TAB_WEATHER := "天气"
const TAB_WORK := "工作模式"
const TAB_STATUS := "系统状态"

var panel_kind := "定时任务"
var _scan_generation := 0
var _settings_page: VBoxContainer
var _tabs: TabContainer
var _clock := AssistantClock.new()
var _content_edit: LineEdit
var _time_pickers: Dictionary = {}
var _time_preview: Label
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
var _weather_today: Label
var _weather_tomorrow: Label
var _weather_advice: Label
var _drive_status: Label
var _drive_summary: Label
var _drive_list: VBoxContainer
var _drive_button: Button
var _autostart_check: CheckBox


func _ready() -> void:
	hide()
	title = panel_kind
	size = Vector2i(390, 430)
	if panel_kind == TAB_WORK: size.y = 340
	if panel_kind == TAB_WEATHER: size.y = 500
	min_size = Vector2i(340, 360)
	always_on_top = true
	borderless = true
	transparent = true
	transparent_bg = true
	size.y += 88
	var usable := DisplayServer.screen_get_usable_rect()
	position = usable.position + (usable.size - size) / 2
	close_requested.connect(_on_close_requested)
	var theme := PixelDialogSkin.create_theme()
	var background := PanelContainer.new()
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.theme = theme
	var style := PixelDialogSkin.pixel_box(Color("e2f2ff"))
	background.add_theme_stylebox_override("panel", style)
	add_child(background)
	background.offset_top = 88
	var decoration := Control.new()
	decoration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(decoration)
	PixelDialogSkin.add_topper(decoration, size.x, 104)
	size_changed.connect(func():
		decoration.get_child(0).position.x = (size.x - decoration.get_child(0).texture.get_width() * decoration.get_child(0).scale.x) / 2
	)
	window_input.connect(_on_header_input)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	background.add_child(margin)
	_tabs = TabContainer.new()
	_tabs.add_theme_stylebox_override("panel", _content_style())
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	layout.add_child(PixelDialogSkin.heading(panel_kind))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tabs)
	var close_button := Button.new()
	close_button.text = "收起面板"
	close_button.pressed.connect(hide)
	_style_controls(close_button)
	layout.add_child(close_button)
	_tabs.tabs_visible = false
	match panel_kind:
		TAB_REMINDERS: _build_reminder_tab()
		TAB_WEATHER: _build_weather_tab()
		TAB_STATUS: _build_status_tab()
		"C 盘检查": _build_drive_tab()
		"设置":
			_build_weather_tab()
			_build_status_tab()
			_tabs.current_tab = 0
	if panel_kind == "设置":
		for child in _tabs.get_children():
			if child != _settings_page:
				_tabs.remove_child(child)
				child.hide()
				add_child(child)
	_style_controls(_tabs)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)


func _on_tick() -> void:
	if not visible: return
	_refresh_list()
	_refresh_work()
	_refresh_status()


func _panel_position(pet_rect: Rect2, screen: Rect2i, panel_size: Vector2i) -> Vector2i:
	var gap := 14
	var pet := Rect2i(Vector2i(pet_rect.position.round()), Vector2i(pet_rect.size.round()))
	var right_x := pet.end.x + gap
	var left_x := pet.position.x - panel_size.x - gap
	var right_fits := right_x >= screen.position.x and right_x + panel_size.x <= screen.end.x
	var left_fits := left_x >= screen.position.x and left_x + panel_size.x <= screen.end.x
	var x: int
	if right_fits:
		x = right_x
	elif left_fits:
		x = left_x
	else:
		# Neither side fits: use the side with more room. Overlap is unavoidable.
		var right_space := screen.end.x - pet.end.x - gap
		var left_space := pet.position.x - screen.position.x - gap
		if right_space >= left_space:
			x = maxi(screen.position.x, screen.end.x - panel_size.x)
		else:
			x = screen.position.x
	var y := pet.position.y + int(pet.size.y / 2.0) - int(panel_size.y / 2.0)
	y = clampi(y, screen.position.y + 8, maxi(screen.position.y + 8, screen.end.y - panel_size.y - 8))
	return Vector2i(x, y)


func open_tab(tab_name: String) -> void:
	var pet_rect := Rect2()
	if FeatureServices.has_method("get_character_screen_rect"):
		pet_rect = FeatureServices.get_character_screen_rect()
	var screen: Rect2i
	var pos: Vector2i
	if pet_rect.size.x > 1.0 and pet_rect.size.y > 1.0:
		var pet_recti := Rect2i(Vector2i(pet_rect.position.round()), Vector2i(pet_rect.size.round()))
		screen = DisplayServer.screen_get_usable_rect(DisplayServer.get_screen_from_rect(pet_recti))
		pos = _panel_position(pet_rect, screen, size)
	else:
		pos = DisplayServer.mouse_get_position() + Vector2i(8, 8)
		screen = DisplayServer.screen_get_usable_rect(DisplayServer.get_screen_from_rect(Rect2i(pos, Vector2i.ONE)))
		if pos.x + size.x > screen.end.x: pos.x -= size.x + 16
		pos = Vector2i(clampi(pos.x, screen.position.x, maxi(screen.position.x, screen.end.x - size.x)), clampi(pos.y, screen.position.y, maxi(screen.position.y, screen.end.y - size.y)))
	position = pos
	show()
	if panel_kind == "C 盘检查":
		_restart_drive_scan()
	if panel_kind == TAB_WEATHER:
		_refresh_weather()
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
	title.text = "新建提醒"
	page.add_child(title)

	var input_row := VBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	page.add_child(input_row)
	_content_edit = LineEdit.new()
	_content_edit.placeholder_text = "提醒内容，例如：喝水 / 交作业"
	_content_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(_label("提醒内容"))
	input_row.add_child(_content_edit)

	var now_local := _clock.unix_to_local(_clock.now())
	var year := int(now_local.get("year", 2026))
	input_row.add_child(_label("提醒日期与时间"))
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 4)
	input_row.add_child(time_row)
	time_row.add_child(_make_scroll_picker("year", year, year + 5, "年", 82))
	time_row.add_child(_make_scroll_picker("month", 1, 12, "月", 58))
	time_row.add_child(_make_scroll_picker("day", 1, 31, "日", 58))
	time_row.add_child(_make_scroll_picker("hour", 0, 23, "时", 58))
	time_row.add_child(_make_scroll_picker("minute", 0, 59, "分", 58))

	_time_preview = Label.new()
	_time_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_time_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	input_row.add_child(action_row)
	action_row.add_child(_time_preview)
	var add_button := Button.new()
	add_button.text = "创建提醒"
	add_button.pressed.connect(_add_at_time)
	action_row.add_child(add_button)
	_set_time_from_unix(_clock.now() + 600)

	var quick_row := HFlowContainer.new()
	quick_row.add_theme_constant_override("separation", 8)
	page.add_child(_label("快捷提醒"))
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
	scroll.custom_minimum_size.y = 64
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_refresh_list()


func _make_scroll_picker(key: String, min_value: int, max_value: int, suffix: String, width: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 38)
	panel.add_theme_stylebox_override("panel", PixelDialogSkin.pixel_box(Color("f8fcff"), 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	panel.add_child(row)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.set_meta("compact_picker_label", true)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)
	var arrows := VBoxContainer.new()
	arrows.add_theme_constant_override("separation", 0)
	arrows.custom_minimum_size = Vector2(16, 0)
	arrows.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(arrows)
	var up := Button.new()
	up.text = "+"
	up.flat = true
	up.focus_mode = Control.FOCUS_NONE
	up.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	up.add_theme_font_size_override("font_size", 10)
	up.set_meta("compact_picker_button", true)
	up.custom_minimum_size = Vector2(16, 17)
	up.pressed.connect(_change_time_picker.bind(key, 1))
	arrows.add_child(up)
	var down := Button.new()
	down.text = "-"
	down.flat = true
	down.focus_mode = Control.FOCUS_NONE
	down.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	down.add_theme_font_size_override("font_size", 10)
	down.set_meta("compact_picker_button", true)
	down.custom_minimum_size = Vector2(16, 17)
	down.pressed.connect(_change_time_picker.bind(key, -1))
	arrows.add_child(down)
	panel.gui_input.connect(_on_time_picker_wheel.bind(key))
	label.gui_input.connect(_on_time_picker_wheel.bind(key))
	_time_pickers[key] = {
		"label": label,
		"value": min_value,
		"min": min_value,
		"max": max_value,
		"suffix": suffix,
	}
	_refresh_picker_label(key)
	return panel


func _refresh_picker_label(key: String) -> void:
	var info: Dictionary = _time_pickers.get(key, {})
	if info.is_empty():
		return
	var label: Label = info.get("label")
	label.text = "%d%s" % [int(info.get("value", 0)), str(info.get("suffix", ""))]


func _refresh_day_limit() -> void:
	var info: Dictionary = _time_pickers.get("day", {})
	if info.is_empty():
		return
	var max_day := _days_in_month(int(_time_pickers["year"].get("value", 1970)), int(_time_pickers["month"].get("value", 1)))
	info["max"] = max_day
	if int(info.get("value", 1)) > max_day:
		info["value"] = max_day
	_refresh_picker_label("day")


func _set_picker_raw(key: String, value: int) -> void:
	var info: Dictionary = _time_pickers.get(key, {})
	if info.is_empty():
		return
	info["value"] = clampi(value, int(info.get("min", 0)), int(info.get("max", 0)))
	_refresh_picker_label(key)


func _set_time_picker_value(key: String, value: int) -> void:
	_set_picker_raw(key, value)
	if key == "year" or key == "month":
		_refresh_day_limit()
	_update_time_preview()


func _change_time_picker(key: String, delta: int) -> void:
	var info: Dictionary = _time_pickers.get(key, {})
	if info.is_empty():
		return
	_set_time_picker_value(key, int(info.get("value", 0)) + delta)


func _on_time_picker_wheel(event: InputEvent, key: String) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_change_time_picker(key, 1)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_change_time_picker(key, -1)
		get_viewport().set_input_as_handled()


func _days_in_month(year: int, month: int) -> int:
	var days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
		return 29
	return int(days[clampi(month - 1, 0, 11)])


func _set_time_from_unix(unix_seconds: int) -> void:
	if _time_pickers.is_empty():
		return
	var parts := _clock.unix_to_local(unix_seconds)
	_set_picker_raw("year", int(parts.get("year", 1970)))
	_set_picker_raw("month", int(parts.get("month", 1)))
	_refresh_day_limit()
	_set_picker_raw("day", int(parts.get("day", 1)))
	_set_picker_raw("hour", int(parts.get("hour", 0)))
	_set_picker_raw("minute", int(parts.get("minute", 0)))
	_update_time_preview()


func _selected_unix() -> int:
	return _clock.local_to_unix({
		"year": int(_time_pickers.get("year", {}).get("value", 1970)),
		"month": int(_time_pickers.get("month", {}).get("value", 1)),
		"day": int(_time_pickers.get("day", {}).get("value", 1)),
		"hour": int(_time_pickers.get("hour", {}).get("value", 0)),
		"minute": int(_time_pickers.get("minute", {}).get("value", 0)),
		"second": 0,
	})


func _update_time_preview() -> void:
	if _time_preview == null:
		return
	var unix := _selected_unix()
	var text := "将提醒：" + _clock.format_local(unix)
	if unix <= _clock.now():
		text += "（已过去）"
	_time_preview.text = text


func _build_weather_tab() -> void:
	var page := VBoxContainer.new()
	page.name = TAB_WEATHER
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "和风天气：填写 API Host 与 API Key；坐标只用于天气请求"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_page = VBoxContainer.new()
	_settings_page.name = "设置"
	_tabs.add_child(_settings_page)
	_settings_page.add_child(title)
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
	var api_row := VBoxContainer.new()
	api_row.add_theme_constant_override("separation", 8)
	_settings_page.add_child(api_row)
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

	var city_row := VBoxContainer.new()
	city_row.add_theme_constant_override("separation", 8)
	_settings_page.add_child(city_row)
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
	_weather_summary = _weather_card(page, "实时")
	_weather_today = _weather_card(page, "今日")
	_weather_tomorrow = _weather_card(page, "明天")
	_weather_advice = _weather_card(page, "建议")
	_refresh_weather_cache()


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _content_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f3f8ff")
	style.set_corner_radius_all(0)
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
		_weather_status.text = "暂无天气记录，请先在托盘“设置”中配置天气服务。"


func _on_weather_ready(result: Dictionary) -> void:
	if _weather_status == null:
		return
	var location: Dictionary = result.get("location", {})
	var current: Dictionary = result.get("current", {})
	var today: Dictionary = result.get("today", {})
	var tomorrow: Dictionary = result.get("tomorrow", {})
	var advice: Array = result.get("advice", [])
	_weather_status.text = "位置：" + str(location.get("name", "地点暂不可用"))
	if bool(result.get("stale", false)): _weather_status.text += "（缓存，待刷新）"
	var name_error := str(location.get("name_error", ""))
	if not name_error.is_empty():
		_weather_status.text += "\n" + ("地点服务无权限，请检查 GeoAPI 权限或在设置中填写手动城市。" if name_error.contains("403") else name_error)
	_weather_summary.text = "%.0f°C %s · 湿度 %d%% · 风 %.1f m/s" % [float(current.get("temp_c", 0)), str(current.get("text", "")), int(current.get("humidity", 0)), float(current.get("wind_ms", 0))]
	_weather_today.text = _forecast_text(today)
	_weather_tomorrow.text = _forecast_text(tomorrow)
	_weather_advice.text = "\n".join(advice) if not advice.is_empty() else "暂无建议"

func _forecast_text(day: Dictionary) -> String:
	return "%.0f～%.0f°C %s · 降雨概率 %d%%" % [float(day.get("min_c", 0)), float(day.get("max_c", 0)), str(day.get("text", "")), int(day.get("pop", 0))]

func _weather_card(parent: Control, heading: String) -> Label:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelDialogSkin.pixel_box(Color("f3faff")))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_label(heading))
	var body := _label("等待天气数据")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)
	return body


func _on_weather_failed(message: String) -> void:
	if _weather_status != null:
		_weather_status.text = "天气查询失败：" + message


func _build_work_tab() -> void:
	var page := VBoxContainer.new()
	page.name = TAB_WORK
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "专注与休息"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	_work_summary = Label.new()
	_work_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_work_summary)
	var row := VBoxContainer.new()
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
	_work_summary.text = "%s · %s\n剩余 %s" % [busy_text, {"off": "未开启", "manual": "手动", "auto": "自动"}.get(mode, mode), _clock.format_duration(int(state.get("remaining_seconds", 0)))]



func _build_status_tab() -> void:
	var page := VBoxContainer.new()
	page.name = TAB_STATUS
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "实时概况"
	page.add_child(title)
	_sentinel_summary = Label.new()
	_sentinel_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sentinel_summary.text = "哨兵启动中……"
	page.add_child(_sentinel_summary)
	var process_title := Label.new()
	process_title.text = "程序占用"
	page.add_child(process_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 64
	page.add_child(scroll)
	_sentinel_processes = VBoxContainer.new()
	_sentinel_processes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sentinel_processes)
	_refresh_status()
	var drive_entry := Button.new()
	drive_entry.text = "检查 C 盘"
	drive_entry.pressed.connect(func(): FeatureServices.open_panel("C 盘检查"))
	page.add_child(drive_entry)
	var autostart: Node = FeatureServices.get_provider("autostart")
	_autostart_check = CheckBox.new()
	_autostart_check.text = "开机自动启动（推荐，定时提醒更可靠）"
	if autostart != null:
		_autostart_check.button_pressed = autostart.is_enabled()
		_autostart_check.toggled.connect(_on_autostart_toggled)
	if _settings_page != null:
		_settings_page.add_child(_autostart_check)
	else:
		_autostart_check.queue_free()


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
	if progress.has("message"):
		_drive_status.text = str(progress.get("message", ""))
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
	var source := "Windows 搜索索引" if str(result.get("source", "")) == "windows_search" else "定向扫描"
	_drive_summary.text = "%s · %d 个文件 · %s\n%s\n仅检查，不会自动删除。" % [
		source,
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
	var due_at := _selected_unix()
	if due_at <= _clock.now():
		_set_status("提醒时间必须晚于当前时间")
		return
	var result: Dictionary = FeatureServices.reminder.add_at(_content_edit.text, due_at)
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
	if int(_status_label.get_meta("until", 0)) < Time.get_ticks_msec():
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
		_status_label.set_meta("until", Time.get_ticks_msec() + 5000)


func _style_controls(node: Node) -> void:
	if node is Button and not node is CheckBox:
		if not node.has_meta("compact_picker_button"):
			node.custom_minimum_size = Vector2(0, 40)
		node.theme = PixelDialogSkin.create_theme()
	if node is LineEdit:
		node.custom_minimum_size.y = 38
		node.add_theme_color_override("font_color", Color("254c7a"))
		node.add_theme_color_override("font_placeholder_color", Color("7b8fa8"))
		var field := StyleBoxFlat.new()
		field.bg_color = Color.WHITE
		field.border_color = Color("bdd0e6")
		field.set_border_width_all(1)
		field.set_corner_radius_all(0)
		field.content_margin_left = 10
		field.content_margin_right = 10
		node.add_theme_stylebox_override("normal", field)
		node.add_theme_stylebox_override("focus", field)
	if node is Label:
		if not node.has_meta("compact_picker_label"):
			node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for child in node.get_children():
		_style_controls(child)


func _build_drive_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "C 盘检查"
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)
	var drive_title := Label.new()
	drive_title.text = "C 盘空间整理"
	page.add_child(drive_title)
	_drive_status = Label.new()
	_drive_status.text = "点击检查，查看可整理的文件"
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

func _restart_drive_scan() -> void:
	_scan_generation += 1
	var generation := _scan_generation
	_drive_summary.text = ""
	for child in _drive_list.get_children(): child.queue_free()
	var drive: Node = FeatureServices.get_provider("drive_analysis")
	if drive == null: return
	if drive.is_scanning():
		drive.cancel_scan()
		_drive_status.text = "正在结束上次扫描……"
		while drive.is_scanning():
			await get_tree().create_timer(0.1).timeout
	if not visible or generation != _scan_generation: return
	_drive_summary.text = ""
	for child in _drive_list.get_children(): child.queue_free()
	_drive_status.text = "正在重新检查……"
	drive.start_scan()


var _header_dragging := false
var _header_mouse := Vector2i.ZERO
var _header_origin := Vector2i.ZERO

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_header_dragging = event.pressed and event.position.y < 170
		if _header_dragging:
			_header_mouse = DisplayServer.mouse_get_position()
			_header_origin = position

func _process(_delta: float) -> void:
	if _header_dragging:
		if not visible or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_header_dragging = false
		else:
			position = _header_origin + DisplayServer.mouse_get_position() - _header_mouse
