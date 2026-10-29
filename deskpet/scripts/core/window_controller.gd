class_name WindowController
extends RefCounted
## Applies preview vs desktop window settings at runtime.
##
## Project defaults are deliberately an opaque, normal window. Transparent,
## borderless and always-on-top are applied only when "--desktop-mode" is passed
## (after "--"), so F5 in the editor remains easy to debug.

static func is_desktop_mode_requested() -> bool:
	if not OS.has_feature("editor"):
		return true
	for arg in OS.get_cmdline_args():
		if arg == "--desktop-mode":
			return true
	for arg in OS.get_cmdline_user_args():
		if arg == "--desktop-mode":
			return true
	return false


static func apply(window: Window, app_config: Dictionary, desktop_mode: bool) -> Dictionary:
	var window_config: Dictionary = _as_dictionary(app_config.get("window", {}))
	var width := int(window_config.get("width", 640))
	var height := int(window_config.get("height", 720))
	var resizable := bool(window_config.get("resizable", false))

	var report := {
		"desktop_mode": desktop_mode,
		"transparent": false,
		"borderless": false,
		"always_on_top": false,
		"size": Vector2i(width, height),
		"position": Vector2i.ZERO,
		"warnings": [],
	}

	if desktop_mode:
		var desktop_config: Dictionary = _as_dictionary(app_config.get("desktop", {}))
		var wants_transparent := bool(desktop_config.get("transparent", true))
		var transparency_allowed := bool(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed", false))

		window.borderless = bool(desktop_config.get("borderless", true))
		window.always_on_top = bool(desktop_config.get("always_on_top", true))
		window.unresizable = not resizable

		if wants_transparent:
			if transparency_allowed:
				window.transparent = true
				window.transparent_bg = true
			else:
				var warning := "Transparent window requested but display/window/per_pixel_transparency/allowed is false."
				push_error("[WindowController] " + warning)
				report["warnings"].append(warning)

		window.size = Vector2i(width, height)
		_place_window(window, desktop_config, report)

		if not window.transparent:
			var fallback_warning := "Desktop mode is running with an opaque window (transparency unavailable or disabled)."
			push_warning("[WindowController] " + fallback_warning)
			report["warnings"].append(fallback_warning)
	else:
		window.transparent = false
		window.transparent_bg = false
		window.borderless = false
		window.always_on_top = false
		window.unresizable = not resizable
		window.size = Vector2i(width, height)

	report["transparent"] = window.transparent
	report["borderless"] = window.borderless
	report["always_on_top"] = window.always_on_top
	report["size"] = window.size
	report["position"] = window.position

	print("[WindowController] mode=%s transparent=%s borderless=%s always_on_top=%s size=%s position=%s" % [
		"desktop" if desktop_mode else "preview",
		str(window.transparent),
		str(window.borderless),
		str(window.always_on_top),
		str(window.size),
		str(window.position),
	])
	if not report["warnings"].is_empty():
		print("[WindowController] warnings: %s" % str(report["warnings"]))
	return report


static func _place_window(window: Window, desktop_config: Dictionary, report: Dictionary) -> void:
	var position_mode := str(desktop_config.get("position", "center"))
	var margin := int(desktop_config.get("margin", 48))
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)

	match position_mode:
		"bottom_right":
			window.position = usable.position + usable.size - window.size - Vector2i(margin, margin)
		"center":
			window.position = usable.position + (usable.size - window.size) / 2
		_:
			push_warning("[WindowController] Unknown desktop.position '%s'; using center." % position_mode)
			window.position = usable.position + (usable.size - window.size) / 2
	report["position"] = window.position
	report["screen_usable_rect"] = usable


static func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
