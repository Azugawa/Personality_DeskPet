extends Node
## Weather service for QWeather (和风天气), API-key authentication.
##
## Uses the current v1 endpoints:
##   GET /weather/v1/current/{lat}/{lon}
##   GET /weather/v1/hourly/{lat}/{lon}?hours=24
##   GET /weather/v1/daily/{lat}/{lon}?days=3
## Authentication is the X-QW-Api-Key header. Coordinates are only sent to the
## configured weather host; they are never logged or uploaded anywhere else.

signal weather_ready(result: Dictionary)
signal failed(message: String)

const CACHE_PATH := "user://cache/weather.json"
const SCHEMA := 1
const LOCATION_SCRIPT_RES := "res://bin/location.ps1"
const AdviceScript := preload("res://scripts/services/weather_advice.gd")

var _settings: Node
var _clock: AssistantClock
var _cache_path := CACHE_PATH
var _cache: Dictionary = {}
var _busy := false
var _last_fetch_at := 0
var _location_override: Dictionary = {}


func setup(settings: Node, clock: AssistantClock = null, cache_path: String = CACHE_PATH) -> void:
	_settings = settings
	_clock = clock if clock != null else AssistantClock.new()
	_cache_path = cache_path
	_cache = JsonStore.load_dict(_cache_path, {})
	if int(_cache.get("schema", 0)) != SCHEMA:
		_cache = {}


func set_location_override(lat: float, lon: float, name: String = "手动位置") -> void:
	_location_override = {"lat": lat, "lon": lon, "name": name, "source": "manual"}


func clear_location_override() -> void:
	_location_override = {}


func get_cached() -> Dictionary:
	return _cache.duplicate(true)


func is_busy() -> bool:
	return _busy


## Fetch current + 24h + daily. Returns the result dictionary (also emitted).
func refresh(force: bool = false) -> Dictionary:
	if _busy:
		return _cache.duplicate(true)
	_busy = true
	var now := _clock.now()
	var ttl: int = _settings.get_int("weather.cache_seconds", 600)
	if not force and not _cache.is_empty() and now - int(_cache.get("fetched_at", 0)) <= ttl:
		_busy = false
		weather_ready.emit(_cache.duplicate(true))
		return _cache.duplicate(true)
	var min_interval: int = _settings.get_int("weather.min_query_interval_seconds", 60)
	if not force and _last_fetch_at > 0 and now - _last_fetch_at < min_interval and not _cache.is_empty():
		_busy = false
		weather_ready.emit(_cache.duplicate(true))
		return _cache.duplicate(true)
	var location := await _resolve_location()
	if location.is_empty():
		_busy = false
		var location_error := "无法获取位置，请到设置里手动选择城市"
		failed.emit(location_error)
		return {}
	var host: String = _normalized_host()
	var api_key: String = _settings.get_secret("weather.api_key", "")
	if host.is_empty() or api_key.is_empty():
		_busy = false
		var config_error := "请先在设置里填写和风天气 API Host 和 API Key"
		failed.emit(config_error)
		return {}
	var fetched := await _fetch_weather(location, host, api_key, now)
	_busy = false
	if not bool(fetched.get("ok", false)):
		var message := str(fetched.get("error", "天气服务暂不可用"))
		if not _cache.is_empty():
			var stale := _cache.duplicate(true)
			stale["stale"] = true
			stale["error"] = message
			weather_ready.emit(stale)
			return stale
		failed.emit(message)
		return {}
	var result: Dictionary = fetched.get("data", {})
	_cache = result
	JsonStore.save_dict(_cache_path, result)
	_last_fetch_at = now
	weather_ready.emit(result.duplicate(true))
	return result.duplicate(true)


func _resolve_location() -> Dictionary:
	if not _location_override.is_empty():
		return _location_override.duplicate(true)
	var manual := _manual_location()
	if _settings.get_string("weather.location_mode", "system") == "manual":
		return manual
	var system := await _resolve_system_location()
	if not system.is_empty():
		if str(system.get("name", "")).is_empty():
			system["name"] = "当前位置"
		return system
	if not manual.is_empty():
		return manual
	return {}


func _manual_location() -> Dictionary:
	var city: Dictionary = _settings.get_dict("weather.manual_city", {})
	var lat := float(city.get("lat", 0.0))
	var lon := float(city.get("lon", 0.0))
	if absf(lat) > 90.0 or absf(lon) > 180.0 or (is_zero_approx(lat) and is_zero_approx(lon)):
		return {}
	return {
		"lat": lat,
		"lon": lon,
		"name": str(city.get("name", "手动位置")),
		"source": "manual",
	}


func _resolve_system_location() -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {}
	var script := _ensure_location_script()
	if script.is_empty():
		return {}
	var base := OS.get_environment("LOCALAPPDATA")
	if base.is_empty():
		return {}
	var out_dir := base.path_join("DeskPet").path_join("runtime")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var out_path := out_dir.path_join("location-%d.json" % Time.get_ticks_usec())
	var pid := OS.create_process("powershell.exe", PackedStringArray([
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", script, "-Out", out_path,
	]))
	if pid <= 0:
		return {}
	for _attempt in 30:
		await get_tree().create_timer(0.2).timeout
		if FileAccess.file_exists(out_path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_path))
			if typeof(parsed) != TYPE_DICTIONARY:
				continue
			JsonStore.remove_file(out_path)
			var data: Dictionary = parsed
			if bool(data.get("ok", false)):
				var lat := float(data.get("lat", 0.0))
				var lon := float(data.get("lon", 0.0))
				if absf(lat) <= 90.0 and absf(lon) <= 180.0:
					return {"lat": lat, "lon": lon, "name": "当前位置", "source": "system"}
			return {}
	if pid > 0:
		OS.kill(pid)
	return {}


func _ensure_location_script() -> String:
	if not FileAccess.file_exists(LOCATION_SCRIPT_RES):
		return ""
	var base := OS.get_environment("LOCALAPPDATA")
	if base.is_empty():
		return ""
	var bytes := FileAccess.get_file_as_bytes(LOCATION_SCRIPT_RES)
	if bytes.is_empty():
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	var digest := context.finish().hex_encode().substr(0, 12)
	var target_dir := base.path_join("DeskPet").path_join("bin")
	DirAccess.make_dir_recursive_absolute(target_dir)
	var target := target_dir.path_join("location-%s.ps1" % digest)
	if not FileAccess.file_exists(target):
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return ""
		file.store_buffer(bytes)
		file.close()
	return target


func _normalized_host() -> String:
	var host: String = _settings.get_string("weather.api_host", "").strip_edges()
	if host.ends_with("/"):
		host = host.substr(0, host.length() - 1)
	if host.is_empty():
		return ""
	if not host.begins_with("http://") and not host.begins_with("https://"):
		host = "https://" + host
	return host


func _fetch_weather(location: Dictionary, host: String, api_key: String, now: int) -> Dictionary:
	var lat := float(location.get("lat", 0.0))
	var lon := float(location.get("lon", 0.0))
	var lat_text := "%.2f" % lat
	var lon_text := "%.2f" % lon
	var lang: String = _settings.get_string("weather.language", "zh")
	var current_url := "%s/weather/v1/current/%s/%s?lang=%s" % [host, lat_text, lon_text, lang]
	var hourly_url := "%s/weather/v1/hourly/%s/%s?lang=%s&hours=24" % [host, lat_text, lon_text, lang]
	var daily_url := "%s/weather/v1/daily/%s/%s?lang=%s&days=3" % [host, lat_text, lon_text, lang]
	var current_response := await _fetch_json(current_url, api_key)
	if not bool(current_response.get("ok", false)):
		return {"ok": false, "error": str(current_response.get("error", "当前天气获取失败"))}
	var hourly_response := await _fetch_json(hourly_url, api_key)
	var daily_response := await _fetch_json(daily_url, api_key)
	if not bool(daily_response.get("ok", false)):
		return {"ok": false, "error": str(daily_response.get("error", "每日预报获取失败"))}
	var result := _build_result(
		location,
		current_response.get("data", {}),
		hourly_response.get("data", {}) if bool(hourly_response.get("ok", false)) else {},
		daily_response.get("data", {}),
		now
	)
	return {"ok": true, "data": result}


func _build_result(
	location: Dictionary,
	now_data: Dictionary,
	hourly_data: Dictionary,
	daily_data: Dictionary,
	now: int
) -> Dictionary:
	var current := {
		"temp_c": _metric(now_data.get("temperature", {})),
		"feels_like_c": _metric(now_data.get("feelsLike", {})),
		"text": _condition_text(now_data),
		"humidity": int(round(_number(now_data.get("humidity", 0.0)) * 100.0)),
		"wind_ms": _metric(_dictionary(now_data.get("wind", {})).get("speed", {})),
		"precip_mm": _metric(_dictionary(now_data.get("precipitation", {})).get("amount", {})),
	}
	var hourly: Array = []
	for item_value in hourly_data.get("hours", []):
		var item: Dictionary = item_value
		hourly.append({
			"ts": _parse_iso_time(str(item.get("forecastTime", ""))),
			"temp_c": _metric(item.get("temperature", {})),
			"text": _condition_text(item),
			"pop": _probability_percent(item),
			"wind_ms": _metric(_dictionary(item.get("wind", {})).get("speed", {})),
		})
	var daily: Array = []
	for item_value in daily_data.get("days", []):
		var item: Dictionary = item_value
		var daytime: Dictionary = _dictionary(item.get("daytime", {}))
		var nighttime: Dictionary = _dictionary(item.get("nighttime", {}))
		var start_ts := _parse_iso_time(str(item.get("forecastStartTime", "")))
		var daytime_pop := _probability_percent(daytime)
		var nighttime_pop := _probability_percent(nighttime)
		var daytime_wind := _metric(_dictionary(daytime.get("wind", {})).get("speed", {}))
		var nighttime_wind := _metric(_dictionary(nighttime.get("wind", {})).get("speed", {}))
		daily.append({
			"date": _local_date(start_ts),
			"start_ts": start_ts,
			"min_c": _metric(item.get("temperatureMin", {})),
			"max_c": _metric(item.get("temperatureMax", {})),
			"text": _condition_text(daytime, _condition_text(nighttime)),
			"pop": maxi(daytime_pop, nighttime_pop),
			"precip_mm": maxf(
				_metric(_dictionary(daytime.get("precipitation", {})).get("amount", {})),
				_metric(_dictionary(nighttime.get("precipitation", {})).get("amount", {}))
			),
			"wind_ms": maxf(daytime_wind, nighttime_wind),
		})
	var today: Dictionary = {}
	var tomorrow: Dictionary = {}
	var today_date := _local_date(now)
	var today_index := 0
	for index in daily.size():
		if str((daily[index] as Dictionary).get("date", "")) == today_date:
			today_index = index
			break
	if daily.size() > today_index:
		today = daily[today_index]
	if daily.size() > today_index + 1:
		tomorrow = daily[today_index + 1]
	var result := {
		"schema": SCHEMA,
		"provider": "qweather",
		"fetched_at": now,
		"stale": false,
		"resolution_km": 1,
		"location": location.duplicate(true),
		"current": current,
		"hourly": hourly,
		"daily": daily,
		"today": today,
		"tomorrow": tomorrow,
	}
	var max_delta := 0.0
	var min_delta := 0.0
	if not today.is_empty() and not tomorrow.is_empty():
		max_delta = float(tomorrow.get("max_c", 0.0)) - float(today.get("max_c", 0.0))
		min_delta = float(tomorrow.get("min_c", 0.0)) - float(today.get("min_c", 0.0))
	result["compare"] = {
		"max_delta_c": max_delta,
		"min_delta_c": min_delta,
		"today_pop": int(today.get("pop", 0)),
		"tomorrow_pop": int(tomorrow.get("pop", 0)),
	}
	result["advice"] = AdviceScript.build(result)
	return result


func _fetch_json(url: String, api_key: String) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = _settings.get_int("weather.timeout_seconds", 8)
	http.accept_gzip = true
	var headers := PackedStringArray(["X-QW-Api-Key: " + api_key])
	if http.request(url, headers, HTTPClient.METHOD_GET) != OK:
		http.queue_free()
		return {"ok": false, "error": "网络请求无法发起"}
	var response: Array = await http.request_completed
	http.queue_free()
	if response.is_empty():
		return {"ok": false, "error": "天气服务无响应"}
	var status := int(response[1])
	var body := (response[3] as PackedByteArray).get_string_from_utf8().trim_prefix("\ufeff")
	if status != 200:
		return {"ok": false, "error": _http_error(status, body)}
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "天气数据格式无效"}
	var data: Dictionary = parsed
	if data.has("error"):
		return {"ok": false, "error": _body_error(data)}
	if data.has("code") and str(data.get("code", "")) != "200":
		return {"ok": false, "error": "和风天气返回错误码 %s" % str(data.get("code", ""))}
	return {"ok": true, "data": data}


func _http_error(status: int, body: String) -> String:
	if status == 401 or status == 403:
		return "和风天气 API Key 或 Host 无权限（HTTP %d）" % status
	if status == 404:
		return "和风天气 API Host 或路径错误（HTTP 404）"
	if status == 429:
		return "和风天气请求过于频繁（HTTP 429）"
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) == TYPE_DICTIONARY:
		var detail := _body_error(parsed)
		if not detail.is_empty():
			return "天气服务 HTTP %d：%s" % [status, detail]
	return "天气服务网络请求失败（HTTP %d）" % status


func _body_error(data: Dictionary) -> String:
	var value: Variant = data.get("error", data.get("message", ""))
	if typeof(value) == TYPE_DICTIONARY:
		var detail: Dictionary = value
		var message := str(detail.get("message", detail.get("detail", "")))
		if not message.is_empty():
			return message
		return str(detail.get("status", "未知错误"))
	return str(value)


func _parse_iso_time(value: String) -> int:
	var regex := RegEx.new()
	regex.compile("^(\\d{4})-(\\d{2})-(\\d{2})[T ](\\d{2}):(\\d{2})(?::(\\d{2}))?(Z|[+-]\\d{2}:?\\d{2})?$")
	var match := regex.search(value)
	if match == null:
		return 0
	var parts := {
		"year": int(match.get_string(1)),
		"month": int(match.get_string(2)),
		"day": int(match.get_string(3)),
		"hour": int(match.get_string(4)),
		"minute": int(match.get_string(5)),
		"second": 0 if match.get_string(6).is_empty() else int(match.get_string(6)),
	}
	var stamp := int(Time.get_unix_time_from_datetime_dict(parts))
	var zone := match.get_string(7)
	if not zone.is_empty() and zone != "Z":
		var sign := 1 if zone.begins_with("+") else -1
		var digits := zone.substr(1).replace(":", "")
		var offset := int(digits.substr(0, 2)) * 3600 + int(digits.substr(2, 2)) * 60
		stamp -= sign * offset
	return stamp


func _local_date(stamp: int) -> String:
	if stamp <= 0:
		return ""
	var local := _clock.unix_to_local(stamp)
	return "%04d-%02d-%02d" % [int(local.get("year", 0)), int(local.get("month", 0)), int(local.get("day", 0))]


func _metric(value: Variant) -> float:
	if typeof(value) == TYPE_DICTIONARY:
		return _number((value as Dictionary).get("value", 0.0))
	return _number(value)


func _number(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	if typeof(value) == TYPE_STRING:
		return float(str(value))
	return 0.0


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func _condition_text(value: Dictionary, fallback: String = "") -> String:
	var condition: Variant = value.get("condition", {})
	if typeof(condition) == TYPE_DICTIONARY:
		var text := str((condition as Dictionary).get("text", ""))
		if not text.is_empty():
			return text
	return fallback


func _probability_percent(value: Dictionary) -> int:
	var precipitation: Variant = value.get("precipitation", {})
	if typeof(precipitation) == TYPE_DICTIONARY:
		var probability: Variant = (precipitation as Dictionary).get("probability", 0.0)
		return int(round(_number(probability) * 100.0))
	return 0
