extends SceneTree
var failed := false
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world = main.get_node("PetWorld")
	var initial_position: Vector2 = world.character.position
	for target in ["rest", "computer", "idle", "computer", "rest", "idle"]:
		if not world.request_activity(target):
			push_error("Rejected transition " + target)
			failed = true
		var elapsed := 0.0
		while world.activity_controller.transitioning and elapsed < 20.0:
			await process_frame
			elapsed += 0.05
			await create_timer(0.05).timeout
		var expected := "idle_front" if target == "idle" else ("rest_loop" if target == "rest" else "computer_type")
		if world.character.get_current_animation() != expected:
			push_error("Wrong animation for " + target + ": " + world.character.get_current_animation())
			failed = true
		if not world.character.position.is_equal_approx(initial_position):
			push_error("Character moved during transition")
			failed = true
		if target == "computer":
			if world.furniture_manager.get_view("computer").direction != "left" or world.furniture_manager.get_view("chair").z_index >= world.character.z_index:
				failed = true
		print("TRANSITION ", target, " -> ", world.character.get_current_animation())
	quit(1 if failed else 0)
