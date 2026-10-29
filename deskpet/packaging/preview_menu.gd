extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(0.5).timeout
	var menu = main.get_node("PetWorld/PetMenu")
	menu.show_actions([{"id":"idle","label":"待机"},{"id":"rest","label":"去趴趴"},{"id":"computer","label":"玩电脑"}],Vector2.ZERO)
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	menu._popup.get_texture().get_image().save_png("E:/DeskPet/build/menu-preview.png")
	quit()
