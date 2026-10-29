class_name AssistantClock
extends RefCounted
## Wall-clock helpers shared by reminders, work mode and weather.
##
## Persisted instants are always UTC Unix seconds. Local date/time conversion is
## isolated here so it can be tested with a fixed clock on any machine.

var _offset_seconds: int = 0
var _fixed_now: int = -1


func now() -> int:
	if _fixed_now >= 0:
		return _fixed_now
	return int(Time.get_unix_time_from_system()) + _offset_seconds


func now_float() -> float:
	if _fixed_now >= 0:
		return float(_fixed_now)
	return Time.get_unix_time_from_system() + float(_offset_seconds)


func set_fixed_now(unix_seconds: int) -> void:
	_fixed_now = unix_seconds


func clear_fixed_now() -> void:
	_fixed_now = -1


func advance_for_test(seconds: int) -> void:
	if _fixed_now >= 0:
		_fixed_now += seconds
	else:
		_offset_seconds += seconds


func timezone_bias_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## Convert a local calendar dictionary (year/month/day/hour/minute/second) to UTC.
func local_to_unix(parts: Dictionary) -> int:
	var utc_like := Time.get_unix_time_from_datetime_dict({
		"year": int(parts.get("year", 1970)),
		"month": int(parts.get("month", 1)),
		"day": int(parts.get("day", 1)),
		"hour": int(parts.get("hour", 0)),
		"minute": int(parts.get("minute", 0)),
		"second": int(parts.get("second", 0)),
	})
	return int(utc_like) - timezone_bias_seconds()


func unix_to_local(unix_seconds: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(unix_seconds + timezone_bias_seconds())


## Parse "YYYY-MM-DD HH:MM" or "YYYY-MM-DD HH:MM:SS" as local time.
## Returns {"unix": int, "parts": Dictionary} or {} when invalid.
func parse_local(text: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("^\\s*(\\d{4})-(\\d{1,2})-(\\d{1,2})[ T](\\d{1,2}):(\\d{2})(?::(\\d{2}))?\\s*$")
	var match := regex.search(text)
	if match == null:
		return {}
	var parts := {
		"year": int(match.get_string(1)),
		"month": int(match.get_string(2)),
		"day": int(match.get_string(3)),
		"hour": int(match.get_string(4)),
		"minute": int(match.get_string(5)),
		"second": 0 if match.get_string(6).is_empty() else int(match.get_string(6)),
	}
	if not _valid_parts(parts):
		return {}
	var unix := local_to_unix(parts)
	var round_trip := unix_to_local(unix)
	if _date_key(round_trip) != _date_key(parts):
		return {}
	return {"unix": unix, "parts": parts}


func format_local(unix_seconds: int) -> String:
	var d := unix_to_local(unix_seconds)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(d.get("year", 0)), int(d.get("month", 0)), int(d.get("day", 0)),
		int(d.get("hour", 0)), int(d.get("minute", 0)),
	]


func format_clock(unix_seconds: int) -> String:
	var d := unix_to_local(unix_seconds)
	return "%02d:%02d" % [int(d.get("hour", 0)), int(d.get("minute", 0))]


func format_duration(seconds: int) -> String:
	if seconds < 0:
		return "已过期"
	var total := seconds
	var hours := int(total / 3600.0)
	total -= hours * 3600
	var minutes := int(total / 60.0)
	total -= minutes * 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, total]
	return "%02d:%02d" % [minutes, total]


func _valid_parts(parts: Dictionary) -> bool:
	var year := int(parts.get("year", 0))
	var month := int(parts.get("month", 0))
	var day := int(parts.get("day", 0))
	var hour := int(parts.get("hour", 0))
	var minute := int(parts.get("minute", 0))
	var second := int(parts.get("second", 0))
	if year < 1970 or year > 2100: return false
	if month < 1 or month > 12: return false
	var month_days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var max_day: int = month_days[month - 1]
	if month == 2 and _is_leap_year(year):
		max_day = 29
	if day < 1 or day > max_day: return false
	if hour < 0 or hour > 23: return false
	if minute < 0 or minute > 59: return false
	if second < 0 or second > 59: return false
	return true


func _date_key(parts: Dictionary) -> String:
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(parts.get("year", 0)), int(parts.get("month", 0)), int(parts.get("day", 0)),
		int(parts.get("hour", 0)), int(parts.get("minute", 0)), int(parts.get("second", 0)),
	]


func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
