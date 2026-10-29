extends SceneTree
## Core tests for the assistant foundation: clock, atomic JSON, settings.

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_test_clock()
	_test_json_store()
	_test_settings()
	print("PASS: assistant clock, json store and settings")
	quit()


func _test_clock() -> void:
	var clock := AssistantClock.new()
	var parts := {"year": 2026, "month": 10, "day": 29, "hour": 22, "minute": 0, "second": 0}
	var unix := clock.local_to_unix(parts)
	var back := clock.unix_to_local(unix)
	assert(int(back.get("year", 0)) == 2026)
	assert(int(back.get("month", 0)) == 10)
	assert(int(back.get("day", 0)) == 29)
	assert(int(back.get("hour", 0)) == 22)
	assert(int(back.get("minute", 0)) == 0)
	assert(clock.format_local(unix) == "2026-10-29 22:00")
	assert(clock.format_clock(unix) == "22:00")
	var parsed := clock.parse_local("2026-10-30 08:00")
	assert(not parsed.is_empty())
	assert(int(parsed.get("unix", 0)) == unix + 10 * 3600)
	assert(clock.parse_local("2026-02-31 08:00").is_empty())
	assert(clock.parse_local("not a date").is_empty())
	assert(clock.format_duration(59) == "00:59")
	assert(clock.format_duration(3661) == "1:01:01")
	assert(clock.format_duration(-1) == "已过期")
	clock.set_fixed_now(1000)
	assert(clock.now() == 1000)
	clock.advance_for_test(5)
	assert(clock.now() == 1005)


func _test_json_store() -> void:
	var root := OS.get_environment("TEMP").path_join("deskpet_core_%d" % Time.get_ticks_usec())
	var path := root.path_join("data.json")
	assert(JsonStore.save_dict(path, {"a": 1, "nested": {"b": "x"}}))
	var loaded := JsonStore.load_dict(path, {})
	assert(int(loaded.get("a", 0)) == 1)
	assert(str((loaded.get("nested", {}) as Dictionary).get("b", "")) == "x")
	# A second save must leave the previous document as .bak.
	assert(JsonStore.save_dict(path, {"a": 2}))
	assert(int(JsonStore.load_dict(path, {}).get("a", 0)) == 2)
	var corrupt := FileAccess.open(JsonStore.absolute_path(path), FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	var recovered := JsonStore.load_dict(path, {"fallback": true})
	assert(int(recovered.get("a", 0)) == 1)
	JsonStore.remove_tree(root)


func _test_settings() -> void:
	var root := OS.get_environment("TEMP").path_join("deskpet_settings_%d" % Time.get_ticks_usec())
	var settings = preload("res://scripts/services/settings_service.gd").new()
	settings.setup(root.path_join("settings.json"), root.path_join("secrets.json"))
	assert(settings.get_string("weather.provider", "") == "qweather")
	assert(settings.get_int("reminders.max_items", 0) == 200)
	assert(settings.get_bool("work_mode.fullscreen_defer", false))
	assert(not settings.has_secret("weather.api_key"))
	settings.set_value("weather.api_host", "https://example.qweatherapi.com")
	settings.set_secret("weather.api_key", "secret-value")
	var reloaded = preload("res://scripts/services/settings_service.gd").new()
	reloaded.setup(root.path_join("settings.json"), root.path_join("secrets.json"))
	assert(reloaded.get_string("weather.api_host", "") == "https://example.qweatherapi.com")
	assert(reloaded.get_secret("weather.api_key", "") == "secret-value")
	var merged: Dictionary = reloaded.snapshot()
	assert((merged.get("weather", {}) as Dictionary).has("api_host"))
	settings.free()
	reloaded.free()
	JsonStore.remove_tree(root)
