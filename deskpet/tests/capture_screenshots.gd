extends Node
## LEGACY static-scene screenshot harness.
##
## The active harness is tests/capture_pet.gd. This file is kept for the old
## SceneManager screenshots and is not run by tools/capture_screenshots.ps1.

## Renders preview screenshots and a desktop-transparency probe.
##
## Run with a real window (not --headless):
##   godot --path <project> res://tests/capture_screenshots.tscn
##
## Outputs docs/screenshots/standing.png, workspace_setup.png and
## desktop_transparent.png (with alpha). The desktop probe also prints the
## corner alpha and the actual Window flags; it does not claim OS compositor
## success by itself.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var main: Node = null
var captured_paths: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		push_error("[Capture] Screenshots require a real window; do not run with --headless.")
		get_tree().quit(1)
		return

	var output_dir := ProjectSettings.globalize_path("res://docs/screenshots")
	var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_error != OK:
		push_error("[Capture] Could not create screenshot directory '%s' (error %d)." % [output_dir, dir_error])
		get_tree().quit(1)
		return

	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _frames(4)
	_hide_debug_overlay()

	await _capture("standing")
	EventBus.emit_game_event("workspace_requested", {"source": "screenshot_tool"})
	await _frames(4)
	_hide_debug_overlay()
	await _capture("workspace_setup")

	main.set_desktop_mode(true)
	SceneManager.request_scene_change("standing", "screenshot desktop probe")
	await _frames(6)
	var desktop_image := await _grab()
	var corner := desktop_image.get_pixel(0, 0)
	_save(desktop_image, "desktop_transparent")
	var window_flags_ok := get_window().transparent and get_window().borderless and get_window().always_on_top
	var probe_ok := window_flags_ok and corner.a <= 0.01
	print("[Capture] desktop probe: window.transparent=%s borderless=%s always_on_top=%s size=%s corner_alpha=%.3f" % [
		str(get_window().transparent),
		str(get_window().borderless),
		str(get_window().always_on_top),
		str(get_window().size),
		corner.a,
	])
	if not window_flags_ok:
		push_error("[Capture] Desktop probe failed: transparent/borderless/always_on_top were not all enabled.")
	if corner.a > 0.01:
		push_error("[Capture] Desktop probe viewport is not transparent at the corner (alpha %.3f). See docs/TEST_RESULTS.md for diagnostic steps." % corner.a)
	elif window_flags_ok:
		print("[Capture] Desktop probe viewport corner is transparent (alpha 0).")

	print("[Capture] SCREENSHOT_RESULT: %s" % str(captured_paths))
	get_tree().quit(0 if probe_ok else 2)


func _capture(shot_name: String) -> void:
	var image := await _grab()
	_save(image, shot_name)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	return get_viewport().get_texture().get_image()


func _save(image: Image, shot_name: String) -> void:
	var relative_path := "res://docs/screenshots/%s.png" % shot_name
	var absolute_path := ProjectSettings.globalize_path(relative_path)
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		push_error("[Capture] Failed to save %s (error %d)." % [absolute_path, save_error])
		return
	captured_paths.append(relative_path)
	print("[Capture] Saved %s (%dx%d)." % [absolute_path, image.get_width(), image.get_height()])


func _hide_debug_overlay() -> void:
	if main != null and main.debug_overlay != null and is_instance_valid(main.debug_overlay):
		main.debug_overlay.visible = false


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
