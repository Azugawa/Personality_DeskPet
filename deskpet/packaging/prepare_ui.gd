extends SceneTree
func _init() -> void:
	var cursor := Image.load_from_file("res://assets/ui/cursor_source.png")
	cursor = cursor.get_region(cursor.get_used_rect())
	var factor := 48.0 / maxf(cursor.get_width(),cursor.get_height())
	cursor.resize(roundi(cursor.get_width()*factor),roundi(cursor.get_height()*factor),Image.INTERPOLATE_NEAREST)
	cursor.save_png("res://assets/ui/default_cursor.png")
	print("menu size ",Image.load_from_file("res://assets/ui/menu_source.png").get_size())
	quit()
