class_name WeatherAdvice
extends RefCounted
## Deterministic advice rules. No model, no network, easy to unit test.

const MAX_TIPS := 3


static func build(result: Dictionary) -> Array[String]:
	var tips: Array[String] = []
	var today: Dictionary = result.get("today", {})
	var tomorrow: Dictionary = result.get("tomorrow", {})
	var current: Dictionary = result.get("current", {})
	var hourly: Array = result.get("hourly", [])
	var now_ts := int(result.get("fetched_at", 0))

	if not today.is_empty() and not tomorrow.is_empty():
		var max_delta := float(tomorrow.get("max_c", 0.0)) - float(today.get("max_c", 0.0))
		var min_delta := float(tomorrow.get("min_c", 0.0)) - float(today.get("min_c", 0.0))
		var cold_delta := minf(max_delta, min_delta)
		var warm_delta := maxf(max_delta, min_delta)
		if cold_delta <= -5.0:
			tips.append("明天比今天明显降温（最高温低约 %d°C），早晚记得加衣" % int(absf(cold_delta)))
		elif warm_delta >= 5.0:
			tips.append("明天比今天升温约 %d°C，注意增减衣物" % int(warm_delta))
		var tomorrow_pop := int(tomorrow.get("pop", 0))
		var today_pop := int(today.get("pop", 0))
		var tomorrow_text := str(tomorrow.get("text", ""))
		var today_text := str(today.get("text", ""))
		if tomorrow_pop >= 60 and today_pop < 30:
			tips.append("明天降雨概率 %d%%（今天 %d%%），记得带伞" % [tomorrow_pop, today_pop])
		elif _is_wet(tomorrow_text) and not _is_wet(today_text):
			tips.append("明天有%s，出门记得带伞" % tomorrow_text)
		if float(tomorrow.get("wind_ms", 0.0)) >= 10.8 and float(tomorrow.get("wind_ms", 0.0)) >= float(today.get("wind_ms", 0.0)) + 2.0:
			tips.append("明天风比今天大，注意防风")

	var max_pop := 0
	var min_temp := 999.0
	for item_value in hourly:
		var item: Dictionary = item_value
		var stamp := int(item.get("ts", 0))
		if stamp < now_ts or stamp > now_ts + 6 * 3600:
			continue
		max_pop = maxi(max_pop, int(item.get("pop", 0)))
		min_temp = minf(min_temp, float(item.get("temp_c", 0.0)))
	if max_pop >= 60:
		tips.append("今天未来 6 小时降雨概率 %d%%，带伞更稳妥" % max_pop)
	var current_temp := float(current.get("temp_c", 0.0))
	if min_temp < 999.0 and current_temp - min_temp >= 5.0:
		tips.append("今天稍后可能降温约 %d°C，注意加衣" % int(current_temp - min_temp))
	if current_temp >= 33.0:
		tips.append("高温天气，注意补水和防晒")
	if float(current.get("wind_ms", 0.0)) >= 10.8:
		tips.append("当前风力较大，注意防风")

	if tips.is_empty():
		tips.append("今天天气平稳，适合正常出行")
	var limited: Array[String] = []
	for index in tips.size():
		if index >= MAX_TIPS:
			break
		limited.append(tips[index])
	return limited


static func _is_wet(text: String) -> bool:
	return text.contains("雨") or text.contains("雪") or text.contains("雷")
