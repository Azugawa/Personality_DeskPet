extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var service = root.get_node("FeatureServices").weather
	var cached: Dictionary = service.get_cached()
	var location: Dictionary = cached.get("location", {})
	if location.is_empty():
		print("GEO_DIAG: no cached coordinates")
	else:
		var host: String = service._normalized_host()
		var key: String = root.get_node("FeatureServices").settings.get_secret("weather.api_key", "")
		var result: Dictionary = await service._fetch_json("%s/geo/v2/city/lookup?location=%.2f%%2C%.2f&lang=zh&number=1" % [host, float(location.get("lon", 0)), float(location.get("lat", 0))], key)
		print("GEO_DIAG ok=", result.get("ok"), " error=", result.get("error", ""), " count=", result.get("data", {}).get("location", []).size())
	quit()
