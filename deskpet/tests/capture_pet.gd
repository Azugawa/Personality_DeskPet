extends Node
## Visual capture harness for the persistent pet runtime.
##
## Run with a real window:
##   godot --path <project> res://tests/capture_pet.tscn

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var main: Node = null


func _ready() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		push_error("[CapturePet] Requires a real window.")
		get_tree().quit(1)
		return

	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _frames(12)
	_hide_overlay()
	await _capture("pet_default")

	var world: PetWorld = main.get_node("PetWorld")
	world.walk_to(Vector2(440, 610))
	await get_tree().create_timer(0.45).timeout
	await _capture("pet_walking")

	world.toggle_furniture("chair")
	world.toggle_furniture("desk")
	world.toggle_furniture("computer")
	await get_tree().create_timer(0.35).timeout
	await _capture("pet_computer")

	world.set_auto_enabled(false)
	world.idle()
	world.get_character().set_facing("front_right")
	await _frames(4)
	await _capture("pet_direction")

	main.set_desktop_mode(true)
	await _frames(8)
	var desktop_image := await _grab()
	var corner := desktop_image.get_pixel(0, 0)
	_save_image(desktop_image, "pet_desktop")
	var flags_ok := get_window().transparent and get_window().borderless and get_window().always_on_top
	print("[CapturePet] desktop probe: transparent=%s borderless=%s always_on_top=%s corner_alpha=%.3f" % [
		str(get_window().transparent), str(get_window().borderless), str(get_window().always_on_top), corner.a
	])
	if not flags_ok or corner.a > 0.01:
		push_error("[CapturePet] Desktop transparency probe failed.")
		get_tree().quit(2)
		return

	print("[CapturePet] done")
	get_tree().quit(0)


func _capture(shot_name: String) -> void:
	var image := await _grab()
	_save_image(image, shot_name)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	return get_viewport().get_texture().get_image()


func _save_image(image: Image, shot_name: String) -> void:
	var path := ProjectSettings.globalize_path("res://docs/screenshots/%s.png" % shot_name)
	var error := image.save_png(path)
	if error != OK:
		push_error("[CapturePet] Failed to save %s (error %d)." % [path, error])
	else:
		print("[CapturePet] Saved %s (%dx%d)." % [path, image.get_width(), image.get_height()])


func _hide_overlay() -> void:
	if main != null and main.debug_overlay != null and is_instance_valid(main.debug_overlay):
		main.debug_overlay.visible = false


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
