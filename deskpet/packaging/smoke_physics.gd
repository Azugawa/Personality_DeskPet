extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var physics = main.get_node("PetWorld/PetInput").physics
	physics.set_process(false)
	physics.begin()
	assert(physics.mode == "held" and physics.sprite.visible)
	var anchor: Vector2 = physics.input._character.global_position
	physics.velocity = Vector2(100,-40)
	physics.release()
	assert(physics.mode == "idle" and physics.velocity == Vector2.ZERO)
	for i in 120: physics._process(1.0/60.0)
	assert(physics.mode == "idle" and physics.input._character.global_position == anchor)
	physics.begin()
	physics.velocity = Vector2(2299,0)
	physics.release()
	assert(physics.mode == "idle")
	physics.begin()
	physics.velocity = Vector2(2400,-400)
	physics.release()
	assert(physics.mode == "flight")
	for i in 1200:
		physics._process(1.0/120.0)
		if physics.mode == "idle": break
	assert(physics.mode == "idle")
	assert(not physics.sprite.visible)
	assert(not physics.input.activity_controller.transitioning)
	print("PASS slow release stays placed; below-threshold release stays placed; fast throw -> collisions -> prone -> getup -> idle")
	quit()
