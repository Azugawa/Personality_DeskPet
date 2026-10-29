extends SceneTree
func _init() -> void:
	for p in ClassDB.class_get_property_list("Window"):
		if "popup" in str(p.name) or "task" in str(p.name): print(p.name)
	quit()
