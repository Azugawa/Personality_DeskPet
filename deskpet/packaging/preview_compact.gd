extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	print("Compact window size: ",root.size)
	root.get_texture().get_image().save_png("E:/DeskPet/build/compact-preview.png")
	quit()
