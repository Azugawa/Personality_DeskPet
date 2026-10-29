extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(3).timeout
	var tray = root.get_node("TrayService")
	tray._set_shown(false)
	assert(not main.get_node("PetWorld").visible)
	assert(tray.menu.get_item_text(0) == "显示桌宠")
	tray._set_shown(true)
	assert(main.get_node("PetWorld").visible)
	assert(tray.menu.get_item_text(0) == "隐藏桌宠")
	print("PASS tray visibility and single toggle label")
	quit()
