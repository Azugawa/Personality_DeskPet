extends SceneTree
## Work mode state machine tests with a fake sentinel and a fixed clock.

const SettingsScript := preload("res://scripts/services/settings_service.gd")
const WorkScript := preload("res://scripts/services/work_mode_service.gd")

class FakeSentinel:
	extends Node
	var snapshot: Dictionary = {}

	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func set_foreground(process: String, idle_seconds := 0, fullscreen := false) -> void:
		snapshot = {
			"foreground": {"process": process, "fullscreen": fullscreen},
			"idle_seconds": idle_seconds,
		}


var _root_dir := ""
var _settings: Node
var _fake: FakeSentinel
var _clock: AssistantClock


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_root_dir = OS.get_environment("TEMP").path_join("deskpet_work_%d" % Time.get_ticks_usec())
	_settings = SettingsScript.new()
	_settings.setup(_root_dir.path_join("settings.json"), _root_dir.path_join("secrets.json"))
	_settings.set_value("work_mode.work_minutes", 1)
	_settings.set_value("work_mode.break_minutes", 1)
	_settings.set_value("work_mode.auto_enable_seconds", 30)
	_settings.set_value("work_mode.auto_disable_seconds", 120)
	_settings.set_value("work_mode.manual_auto_disable_seconds", 600)
	_settings.set_value("work_mode.manual_off_suppress_seconds", 1800)
	_clock = AssistantClock.new()
	_clock.set_fixed_now(1793311200)
	_fake = FakeSentinel.new()
	root.add_child(_fake)
	await _test_auto_enable_disable()
	await _test_manual_auto_close()
	await _test_break_cycle()
	await _test_fullscreen_defer()
	await _test_manual_off_suppression()
	await _test_restore()
	JsonStore.remove_tree(_root_dir)
	print("PASS: work mode auto/manual/break/fullscreen/suppression/restore")
	quit()


func _new_service(file_name: String) -> Node:
	var service = WorkScript.new()
	root.add_child(service)
	service.setup(_settings, _fake, _clock, _root_dir.path_join(file_name))
	service.set_process(false)
	return service


func _ticks(service: Node, count: int) -> void:
	for _index in count:
		_clock.advance_for_test(1)
		service.tick()


func _free(service: Node) -> void:
	service.queue_free()
	await process_frame


func _test_auto_enable_disable() -> void:
	var service := _new_service("auto.json")
	_fake.set_foreground("WINWORD.EXE")
	_ticks(service, 29)
	assert(str(service.get_state().get("mode", "")) == "off")
	_ticks(service, 2)
	assert(str(service.get_state().get("mode", "")) == "auto")
	_fake.set_foreground("")
	_ticks(service, 119)
	assert(str(service.get_state().get("mode", "")) == "auto")
	_ticks(service, 2)
	assert(str(service.get_state().get("mode", "")) == "off")
	_fake.set_foreground("WINWORD.EXE")
	_ticks(service, 31)
	assert(str(service.get_state().get("mode", "")) == "auto")
	await _free(service)


func _test_manual_auto_close() -> void:
	var service := _new_service("manual_close.json")
	service.enable_manual()
	assert(str(service.get_state().get("mode", "")) == "manual")
	_fake.set_foreground("")
	_ticks(service, 599)
	assert(str(service.get_state().get("mode", "")) == "manual")
	_ticks(service, 2)
	assert(str(service.get_state().get("mode", "")) == "off")
	await _free(service)


func _test_break_cycle() -> void:
	var service := _new_service("break.json")
	_fake.set_foreground("wps.exe")
	service.enable_manual()
	var events: Array = []
	service.break_due.connect(func(info: Dictionary): events.append(info))
	_ticks(service, 60)
	assert(events.size() == 1, "one break prompt after one minute")
	assert(bool(service.get_state().get("break_pending", false)))
	service.start_break(60)
	assert(str(service.get_state().get("phase", "")) == "break")
	_ticks(service, 61)
	assert(str(service.get_state().get("phase", "")) == "work")
	# Snooze: the reminder should come back after the snooze window.
	_ticks(service, 60)
	assert(events.size() == 2)
	service.snooze_break(10)
	_ticks(service, 9)
	assert(events.size() == 2)
	_ticks(service, 2)
	assert(events.size() == 3)
	service.skip_break()
	assert(not bool(service.get_state().get("break_pending", true)))
	await _free(service)


func _test_fullscreen_defer() -> void:
	var service := _new_service("fullscreen.json")
	_fake.set_foreground("POWERPNT.EXE", 0, true)
	service.enable_manual()
	var events: Array = []
	service.break_due.connect(func(info: Dictionary): events.append(info))
	_ticks(service, 60)
	assert(events.is_empty(), "full-screen presentation must defer the break prompt")
	assert(bool(service.get_state().get("break_deferred", false)))
	_fake.set_foreground("POWERPNT.EXE", 0, false)
	_ticks(service, 1)
	assert(events.size() == 1)
	await _free(service)


func _test_manual_off_suppression() -> void:
	var service := _new_service("suppress.json")
	service.enable_manual()
	service.disable_manual()
	_fake.set_foreground("WINWORD.EXE")
	_ticks(service, 31)
	assert(str(service.get_state().get("mode", "")) == "off")
	_clock.advance_for_test(1801)
	_fake.set_foreground("WINWORD.EXE")
	_ticks(service, 31)
	assert(str(service.get_state().get("mode", "")) == "auto")
	await _free(service)


func _test_restore() -> void:
	var service := _new_service("restore.json")
	_fake.set_foreground("WINWORD.EXE")
	service.enable_manual()
	_ticks(service, 3)
	service.save_now()
	var restored := _new_service("restore.json")
	assert(str(restored.get_state().get("mode", "")) == "manual")
	assert(int(restored.get_state().get("active_seconds", 0)) >= 2)
	await _free(service)
	await _free(restored)
