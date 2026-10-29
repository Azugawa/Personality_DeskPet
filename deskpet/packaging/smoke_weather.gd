extends SceneTree
## Weather v1 parsing, advice, cache and failure tests with mocked QWeather JSON.

const SettingsScript := preload("res://scripts/services/settings_service.gd")
const WeatherScript := preload("res://scripts/services/weather_service.gd")
const NOW := 1793282400

class MockWeather:
	extends "res://scripts/services/weather_service.gd"
	var calls := 0
	var fail := false

	func _fetch_json(_url: String, _api_key: String = "") -> Dictionary:
		calls += 1
		if fail:
			return {"ok": false, "error": "mock network failure"}
		if _url.contains("/weather/v1/current/"):
			return {"ok": true, "data": {
				"condition": {"text": "多云", "code": "101"},
				"temperature": {"value": 18.0, "unit": "°C"},
				"feelsLike": {"value": 17.0, "unit": "°C"},
				"humidity": 0.6,
				"wind": {"speed": {"value": 3.3, "unit": "m/s"}, "scale": 2},
				"precipitation": {"amount": {"value": 0.0, "unit": "mm"}, "type": "none"},
			}}
		if _url.contains("/weather/v1/hourly/"):
			return {"ok": true, "data": {"hours": [
				{"forecastTime": "2026-10-29T15:00Z", "temperature": {"value": 16.0},
					"condition": {"text": "小雨"}, "precipitation": {"probability": 0.8},
					"wind": {"speed": {"value": 4.0}}},
				{"forecastTime": "2026-10-29T17:00Z", "temperature": {"value": 13.0},
					"condition": {"text": "小雨"}, "precipitation": {"probability": 0.85},
					"wind": {"speed": {"value": 4.0}}},
			]}}
		if _url.contains("/weather/v1/daily/"):
			return {"ok": true, "data": {"days": [
				{"forecastStartTime": "2026-10-28T22:00Z",
					"temperatureMax": {"value": 24.0}, "temperatureMin": {"value": 16.0},
					"daytime": {"condition": {"text": "多云"},
						"precipitation": {"probability": 0.1, "amount": {"value": 0.0}},
						"wind": {"speed": {"value": 3.0}}}},
				{"forecastStartTime": "2026-10-29T22:00Z",
					"temperatureMax": {"value": 14.0}, "temperatureMin": {"value": 8.0},
					"daytime": {"condition": {"text": "小雨"},
						"precipitation": {"probability": 0.8, "amount": {"value": 5.0}},
						"wind": {"speed": {"value": 5.5}}}},
			]}}
		return {"ok": false, "error": "unexpected url"}


var _root_dir := ""
var _settings: Node
var _clock: AssistantClock


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_root_dir = OS.get_environment("TEMP").path_join("deskpet_weather_%d" % Time.get_ticks_usec())
	_settings = SettingsScript.new()
	_settings.setup(_root_dir.path_join("settings.json"), _root_dir.path_join("secrets.json"))
	_settings.set_value("weather.api_host", "https://example.qweatherapi.com")
	_settings.set_secret("weather.api_key", "test-key")
	_settings.set_value("weather.location_mode", "manual")
	_settings.set_value("weather.manual_city", {"name": "广州", "lat": 23.0, "lon": 113.4})
	_settings.set_value("weather.cache_seconds", 600)
	_clock = AssistantClock.new()
	_clock.set_fixed_now(NOW)
	await _test_refresh()
	await _test_cache()
	await _test_stale_fallback()
	await _test_missing_key()
	JsonStore.remove_tree(_root_dir)
	print("PASS: weather v1 parse/advice/cache/failure")
	quit()


func _new_service(clock_offset: int = 0) -> MockWeather:
	var clock := AssistantClock.new()
	clock.set_fixed_now(NOW + clock_offset)
	var service := MockWeather.new()
	root.add_child(service)
	service.setup(_settings, clock, _root_dir.path_join("cache.json"))
	return service


func _test_refresh() -> void:
	var service := _new_service()
	var result: Dictionary = await service.refresh(true)
	assert(not result.is_empty())
	assert(service.calls == 3, "current + hourly + daily")
	assert(float((result.get("current", {}) as Dictionary).get("temp_c", 0.0)) == 18.0)
	assert(int((result.get("current", {}) as Dictionary).get("humidity", 0)) == 60)
	assert(int(result.get("resolution_km", 0)) == 1)
	var today: Dictionary = result.get("today", {})
	var tomorrow: Dictionary = result.get("tomorrow", {})
	assert(str(today.get("date", "")) == "2026-10-29")
	assert(float(today.get("max_c", 0.0)) == 24.0)
	assert(float(tomorrow.get("max_c", 0.0)) == 14.0)
	var compare: Dictionary = result.get("compare", {})
	assert(float(compare.get("max_delta_c", 0.0)) == -10.0)
	var advice: Array = result.get("advice", [])
	assert(advice.size() >= 2)
	assert(str(advice[0]).contains("降温"))
	assert(_advice_contains(advice, "带伞"))
	var hourly: Array = result.get("hourly", [])
	assert(hourly.size() == 2)
	assert(int((hourly[0] as Dictionary).get("ts", 0)) > 0)
	service.queue_free()
	await process_frame


func _test_cache() -> void:
	var service := _new_service(60)
	var result: Dictionary = await service.refresh(false)
	assert(service.calls == 0, "cache hit must not hit the network")
	assert(not result.is_empty())
	assert(float((result.get("current", {}) as Dictionary).get("temp_c", 0.0)) == 18.0)
	service.queue_free()
	await process_frame


func _test_stale_fallback() -> void:
	var service := _new_service(1200)
	service.fail = true
	var result: Dictionary = await service.refresh(true)
	assert(not result.is_empty())
	assert(bool(result.get("stale", false)))
	assert(str(result.get("error", "")).contains("network"))
	service.queue_free()
	await process_frame


func _test_missing_key() -> void:
	_settings.set_secret("weather.api_key", "")
	var service := _new_service(2400)
	var messages: Array = []
	service.failed.connect(func(message: String): messages.append(message))
	var result: Dictionary = await service.refresh(true)
	assert(result.is_empty())
	assert(messages.size() == 1)
	assert(str(messages[0]).contains("API Key"))
	service.queue_free()
	await process_frame


func _advice_contains(advice: Array, text: String) -> bool:
	for item in advice:
		if str(item).contains(text):
			return true
	return false
