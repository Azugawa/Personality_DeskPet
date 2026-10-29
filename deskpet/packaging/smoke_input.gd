extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world = main.get_node("PetWorld")
	var bounds: Rect2 = world.character.get_screen_bounds()
	var head := bounds.position + Vector2(bounds.size.x * 0.5, bounds.size.y * 0.15)
	var body := bounds.position + Vector2(bounds.size.x * 0.5, bounds.size.y * 0.7)
	assert(world.pet_input._is_head(head))
	assert(not world.pet_input._is_head(body))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = head
	world.pet_input._handle_left_button(click)
	assert(world.character.get_current_animation() == "head_pat")
	for entry in world.activity_controller.get_menu_entries():
		assert(entry.enabled)
	assert(world.request_activity("rest"))
	assert(world.activity_controller.transitioning)
	print("PASS head/body partition, authored headpat, menu enabled during reaction, reaction interrupted by activity")
	quit()
