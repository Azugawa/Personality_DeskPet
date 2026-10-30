extends Window
## Independent pixel panels backed by the existing assistant services.

const TAB_REMINDERS := "定时任务"
const TAB_WEATHER := "天气"
const TAB_WORK := "工作模式"
const TAB_STATUS := "系统状态"
const TimeWheelScript := preload("res://scripts/ui/time_wheel.gd")

var panel_kind := "定时任务"
var _scan_generation := 0
var _settings_page: VBoxContainer
var _tabs: TabContainer
var _clock := AssistantClock.new()
var _content_edit: LineEdit
var _date_button: Button
var _calendar_popup: PopupPanel
var _calendar_panel: PanelContainer
var _calendar_grid: GridContainer
var _calendar_year_option: OptionButton
var _calendar_month_option: OptionButton
var _calendar_year_base := 2026
var _calendar_year_value := 2026
var _calendar_month_value := 1
var _calendar_day_value := 1
var _calendar_syncing := false
var _calendar_resize_token := 0
var _hour_wheel
var _minute_wheel
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

	input_row.add_child(_label("提醒日期与时间"))
	var date_time_row := HBoxContainer.new()
	date_time_row.add_theme_constant_override("separation", 6)
	input_row.add_child(date_time_row)
	_date_button = Button.new()
	_date_button.text = "选择日期"
	_date_button.tooltip_text = "从日历选择年月日"
	_date_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_date_button.pressed.connect(_toggle_calendar)
	date_time_row.add_child(_date_button)
	_hour_wheel = TimeWheelScript.new()
	_hour_wheel.item_height = 20.0
	_hour_wheel.custom_minimum_size = Vector2(64, 64)
	_hour_wheel.setup(0, 23, 19)
	_hour_wheel.value_changed.connect(func(_value: int): _update_time_preview())
	date_time_row.add_child(_hour_wheel)
	var colon := Label.new()
	colon.text = ":"
	colon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	date_time_row.add_child(colon)
	_minute_wheel = TimeWheelScript.new()
	_minute_wheel.item_height = 20.0
	_minute_wheel.custom_minimum_size = Vector2(64, 64)
	_minute_wheel.setup(0, 59, 56)
	_minute_wheel.value_changed.connect(func(_value: int): _update_time_preview())
	date_time_row.add_child(_minute_wheel)
	_calendar_popup = PopupPanel.new()
	_calendar_popup.transparent = true
	_calendar_popup.transparent_bg = true
	_calendar_popup.borderless = true
	_calendar_popup.wrap_controls = false
	_calendar_popup.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_calendar_popup)
	_calendar_panel = _build_calendar_panel()
	_calendar_popup.add_child(_calendar_panel)

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


func _build_calendar_panel() -> PanelContainer:
	_calendar_year_base = int(_clock.unix_to_local(_clock.now()).get("year", 2026))
	_calendar_year_value = _calendar_year_base
	_calendar_month_value = int(_clock.unix_to_local(_clock.now()).get("month", 1))
	_calendar_day_value = int(_clock.unix_to_local(_clock.now()).get("day", 1))
	var panel := PanelContainer.new()
	panel.visible = true
	panel.theme = PixelDialogSkin.create_theme()
	var calendar_style := StyleBoxFlat.new()
	calendar_style.bg_color = Color("f4fbff")
	calendar_style.border_color = Color("8db8e8")
	calendar_style.set_border_width_all(2)
	calendar_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", calendar_style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	column.add_child(header)
	var previous := Button.new()
	previous.text = "<"
	_style_calendar_button(previous, 26, Color("173763"))
	previous.custom_minimum_size = Vector2(26, 26)
	previous.pressed.connect(_shift_calendar_month.bind(-1))
	header.add_child(previous)
	_calendar_year_option = OptionButton.new()
	_calendar_year_option.custom_minimum_size = Vector2(86, 30)
	for offset in 6:
		_calendar_year_option.add_item(str(_calendar_year_base + offset))
	_calendar_year_option.item_selected.connect(_on_calendar_year_selected)
	_style_calendar_option(_calendar_year_option)
	header.add_child(_calendar_year_option)
	_calendar_month_option = OptionButton.new()
	_calendar_month_option.custom_minimum_size = Vector2(72, 30)
	for month in 12:
		_calendar_month_option.add_item("%d月" % (month + 1))
	_calendar_month_option.item_selected.connect(_on_calendar_month_selected)
	_style_calendar_option(_calendar_month_option)
	header.add_child(_calendar_month_option)
	var next := Button.new()
	next.text = ">"
	_style_calendar_button(next, 26, Color("173763"))
	next.custom_minimum_size = Vector2(26, 26)
	next.pressed.connect(_shift_calendar_month.bind(1))
	header.add_child(next)
	var weekdays := HBoxContainer.new()
	weekdays.add_theme_constant_override("separation", 2)
	column.add_child(weekdays)
	for name in ["一", "二", "三", "四", "五", "六", "日"]:
		var label := Label.new()
		label.text = name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 12)
		label.set_meta("compact_picker_label", true)
		weekdays.add_child(label)
	_calendar_grid = GridContainer.new()
	_calendar_grid.columns = 7
	_calendar_grid.add_theme_constant_override("h_separation", 2)
	_calendar_grid.add_theme_constant_override("v_separation", 2)
	column.add_child(_calendar_grid)
	return panel


func _style_calendar_button(button: Button, height: int, color: Color) -> void:
	button.flat = true
	button.set_meta("compact_calendar_button", true)
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", 12)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, empty)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, color)


func _calendar_arrow_icon() -> Texture2D:
	var image := Image.create(9, 5, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for row in 3:
		for column in range(row, 9 - row):
			image.set_pixel(column, row + 1, Color("173763"))
	return ImageTexture.create_from_image(image)


func _calendar_option_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color("8db8e8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 6
	style.content_margin_right = 18
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _style_calendar_option(option: OptionButton) -> void:
	option.add_theme_font_override("font", PixelDialogSkin.load_font())
	option.add_theme_font_size_override("font_size", 12)
	option.alignment = HORIZONTAL_ALIGNMENT_CENTER
	option.add_theme_icon_override("arrow", _calendar_arrow_icon())
	option.add_theme_constant_override("arrow_margin", 2)
	option.add_theme_color_override("font_color", Color("173763"))
	option.add_theme_color_override("font_hover_color", Color("173763"))
	option.add_theme_color_override("font_pressed_color", Color("173763"))
	option.add_theme_stylebox_override("normal", _calendar_option_style(Color("f8fcff")))
	option.add_theme_stylebox_override("hover", _calendar_option_style(Color("eef8ff")))
	option.add_theme_stylebox_override("pressed", _calendar_option_style(Color("dcefff")))
	option.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _on_calendar_year_selected(index: int) -> void:
	if _calendar_syncing:
		return
	_calendar_year_value = _calendar_year_base + index
	_refresh_calendar_grid()


func _on_calendar_month_selected(index: int) -> void:
	if _calendar_syncing:
		return
	_calendar_month_value = index + 1
	_refresh_calendar_grid()


func _shift_calendar_month(delta: int) -> void:
	var year := _calendar_year_value
	var month := _calendar_month_value + delta
	if month < 1:
		month = 12
		year -= 1
	elif month > 12:
		month = 1
		year += 1
	year = clampi(year, _calendar_year_base, _calendar_year_base + 5)
	_calendar_year_value = year
	_calendar_month_value = month
	_calendar_day_value = mini(_calendar_day_value, _days_in_month(year, month))
	_sync_calendar_controls()
	_refresh_calendar_grid()


func _sync_calendar_controls() -> void:
	if _calendar_year_option == null or _calendar_month_option == null:
		return
	_calendar_syncing = true
	_calendar_year_option.select(clampi(_calendar_year_value - _calendar_year_base, 0, 5))
	_calendar_month_option.select(clampi(_calendar_month_value - 1, 0, 11))
	_calendar_syncing = false


func _refresh_calendar_grid() -> void:
	if _calendar_grid == null:
		return
	_sync_calendar_controls()
	_calendar_day_value = mini(_calendar_day_value, _days_in_month(_calendar_year_value, _calendar_month_value))
	for child in _calendar_grid.get_children():
		child.free()
	var first_unix := _clock.local_to_unix({
		"year": _calendar_year_value,
		"month": _calendar_month_value,
		"day": 1,
		"hour": 12,
		"minute": 0,
		"second": 0,
	})
	var first_local := _clock.unix_to_local(first_unix)
	var weekday := int(first_local.get("weekday", 0))
	var leading := (weekday + 6) % 7
	for _blank in leading:
		var blank := Control.new()
		blank.custom_minimum_size = Vector2(0, 24)
		blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_calendar_grid.add_child(blank)
	for day in range(1, _days_in_month(_calendar_year_value, _calendar_month_value) + 1):
		var button := Button.new()
		button.text = str(day)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var day_color := Color("c0392b") if day == _calendar_day_value else Color("111111")
		_style_calendar_button(button, 24, day_color)
		button.pressed.connect(_select_calendar_day.bind(day))
		_calendar_grid.add_child(button)
	_refresh_date_button()
	if _calendar_popup != null and _calendar_popup.visible:
		_queue_calendar_resize()


func _queue_calendar_resize() -> void:
	_calendar_resize_token += 1
	var token := _calendar_resize_token
	await get_tree().process_frame
	await get_tree().process_frame
	if token != _calendar_resize_token:
		return
	_resize_calendar_popup()


func _resize_calendar_popup() -> void:
	if _calendar_popup == null or not _calendar_popup.visible:
		return
	var content_size := _calendar_panel.get_combined_minimum_size()
	_calendar_popup.size = Vector2i(maxi(248, int(content_size.x) + 8), int(content_size.y) + 8)
	_clamp_calendar_popup_position()


func _clamp_calendar_popup_position() -> void:
	if _date_button == null or _calendar_popup == null:
		return
	var pos := _date_button.get_screen_position() + Vector2(0, _date_button.size.y + 6)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.get_screen_from_rect(Rect2i(Vector2i(pos), Vector2i.ONE)))
	pos.x = clampf(pos.x, screen.position.x, maxf(screen.position.x, screen.end.x - _calendar_popup.size.x))
	pos.y = clampf(pos.y, screen.position.y, maxf(screen.position.y, screen.end.y - _calendar_popup.size.y))
	_calendar_popup.position = Vector2i(pos)


func _toggle_calendar() -> void:
	if _calendar_popup == null or _calendar_panel == null:
		return
	if _calendar_popup.visible:
		_calendar_popup.hide()
		return
	_refresh_calendar_grid()
	_calendar_popup.size = Vector2i(248, 200)
	_calendar_popup.popup()
	_queue_calendar_resize()


func _select_calendar_day(day: int) -> void:
	_calendar_day_value = day
	_calendar_popup.hide()
	_refresh_date_button()
	_update_time_preview()


func _refresh_date_button() -> void:
	if _date_button == null:
		return
	_date_button.text = "%04d-%02d-%02d" % [_calendar_year_value, _calendar_month_value, _calendar_day_value]


func _days_in_month(year: int, month: int) -> int:
	var days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
		return 29
	return int(days[clampi(month - 1, 0, 11)])


func _set_time_from_unix(unix_seconds: int) -> void:
	var parts := _clock.unix_to_local(unix_seconds)
	var year := int(parts.get("year", _calendar_year_base))
	if _calendar_year_base == 0:
		_calendar_year_base = year
	_calendar_year_value = clampi(year, _calendar_year_base, _calendar_year_base + 5)
	_calendar_month_value = int(parts.get("month", 1))
	_calendar_day_value = int(parts.get("day", 1))
	if _hour_wheel != null:
		_hour_wheel.set_value(int(parts.get("hour", 0)), false)
	if _minute_wheel != null:
		_minute_wheel.set_value(int(parts.get("minute", 0)), false)
	_sync_calendar_controls()
	_refresh_calendar_grid()
	_refresh_date_button()
	_update_time_preview()


func _selected_unix() -> int:
	return _clock.local_to_unix({
		"year": _calendar_year_value,
		"month": _calendar_month_value,
		"day": _calendar_day_value,
		"hour": _hour_wheel.value if _hour_wheel != null else 0,
		"minute": _minute_wheel.value if _minute_wheel != null else 0,
		"second": 0,
	})


func _update_time_preview() -> void:
	if _time_preview == null:
		return
	var unix := _selected_unix()
	var text := "提醒：" + _clock.format_local(unix).substr(5)
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
	style.content_margin_left = 4
	style.content_margin_right = 10
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
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", PixelDialogSkin.pixel_box(Color("f3faff")))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(column)
	column.add_child(_label(heading))
	var body := _label("等待天气数据")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size.x = 0
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
		if not node.has_meta("compact_picker_button") and not node.has_meta("compact_calendar_button"):
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
