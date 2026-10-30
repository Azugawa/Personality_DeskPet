extends Node
## Composition root for optional assistant features.
##
## Services live as children of this autoload so project.godot keeps its existing
## autoload list. Feature code is UI-agnostic; the temporary window only calls
## public methods and listens to signals.

signal reminder_due(reminder: Dictionary)
signal dialogue_requested(message: String)
signal outfit_requested(outfit_id: String)
signal game_space_requested(space_id: String)

const SettingsScript := preload("res://scripts/services/settings_service.gd")
const SentinelScript := preload("res://scripts/services/sentinel_service.gd")
const ReminderScript := preload("res://scripts/services/reminder_service.gd")
const WorkModeScript := preload("res://scripts/services/work_mode_service.gd")
const WeatherScript := preload("res://scripts/services/weather_service.gd")
const DriveAnalysisScript := preload("res://scripts/services/drive_analysis_service.gd")
const AutostartScript := preload("res://scripts/services/autostart_service.gd")
const ReminderPresenterScript := preload("res://scripts/ui/reminder_presenter.gd")
const WorkBreakPresenterScript := preload("res://scripts/ui/work_break_presenter.gd")
const AssistantWindowScript := preload("res://scripts/ui/temp/assistant_window.gd")

var providers: Dictionary = {}
var clock: AssistantClock
var settings: Node
var sentinel: Node
var reminder: Node
var work_mode: Node
var weather: Node
var drive_analysis: Node
var autostart: Node
var reminder_presenter: Node
var work_break_presenter: Node

var _assistant_window: Window = null
var _panels: Dictionary = {}


func _ready() -> void:
	clock = AssistantClock.new()
	settings = SettingsScript.new()
	settings.name = "SettingsService"
	add_child(settings)
	settings.setup()
	sentinel = SentinelScript.new()
	sentinel.name = "SentinelService"
	add_child(sentinel)
	sentinel.setup(settings)
	reminder = ReminderScript.new()
	reminder.name = "ReminderService"
	add_child(reminder)
	reminder.setup(
		"user://data/reminders.json",
		clock,
		settings.get_int("reminders.missed_grace_hours", 24),
		settings.get_int("reminders.retention_days", 7),
		settings.get_int("reminders.max_items", 200),
		settings.get_int("reminders.max_text_length", 200)
	)
	reminder_presenter = ReminderPresenterScript.new()
	reminder_presenter.name = "ReminderPresenter"
	add_child(reminder_presenter)
	reminder_presenter.setup(reminder)
	reminder.due.connect(_on_reminder_due)
	work_mode = WorkModeScript.new()
	work_mode.name = "WorkModeService"
	add_child(work_mode)
	work_mode.setup(settings, sentinel, clock, "user://data/work_mode.json")
	weather = WeatherScript.new()
	weather.name = "WeatherService"
	add_child(weather)
	weather.setup(settings, clock, "user://cache/weather.json")
	drive_analysis = DriveAnalysisScript.new()
	drive_analysis.name = "DriveAnalysisService"
	add_child(drive_analysis)
	drive_analysis.setup(settings, sentinel, clock)
	autostart = AutostartScript.new()
	autostart.name = "AutostartService"
	add_child(autostart)
	work_break_presenter = WorkBreakPresenterScript.new()
	work_break_presenter.name = "WorkBreakPresenter"
	add_child(work_break_presenter)
	work_break_presenter.setup(work_mode)
	register_provider("settings", settings)
	register_provider("sentinel", sentinel)
	register_provider("reminder", reminder)
	register_provider("work_mode", work_mode)
	register_provider("weather", weather)
	register_provider("drive_analysis", drive_analysis)
	register_provider("autostart", autostart)


func _on_reminder_due(item: Dictionary) -> void:
	reminder_due.emit(item)


func register_provider(service: String, provider: Node) -> void:
	providers[service] = provider


func get_provider(service: String) -> Node:
	return providers.get(service) as Node


func get_service(service: String) -> Node:
	return get_provider(service)


## Entries appended after the activity menu on the pet's right click.
func get_menu_entries() -> Array:
	var entries: Array = []
	if reminder != null:
		var count: int = reminder.pending_count()
		entries.append({
			"id": "assistant_reminders",
			"label": "定时任务" + ("（%d）" % count if count > 0 else ""),
		})
	if weather != null:
		entries.append({"id": "assistant_weather", "label": "天气"})
	if work_mode != null:
		entries.append({"id": "assistant_work_mode", "label": work_mode.menu_label()})
	if sentinel != null:
		entries.append({"id": "assistant_sentinel", "label": "系统状态"})
	return entries


func handle_menu_action(action_id: String) -> void:
	match action_id:
		"assistant_reminders":
			open_panel("定时任务")
		"assistant_weather":
			open_panel("天气")
		"assistant_work_mode":
			if work_mode != null:
				work_mode.toggle()

		"assistant_sentinel":
			open_panel("系统状态")
		_:
			push_warning("[Assistant] Unknown menu action: %s" % action_id)


func open_panel(tab_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_assistant_window = _panels.get(tab_name)
	if _assistant_window == null or not is_instance_valid(_assistant_window):
		_assistant_window = AssistantWindowScript.new()
		_assistant_window.panel_kind = tab_name
		add_child(_assistant_window)
		_panels[tab_name] = _assistant_window
	_assistant_window.open_tab(tab_name)
