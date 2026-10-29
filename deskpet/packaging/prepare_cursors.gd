extends SceneTree
func _init() -> void:
	for id in ["click", "pat"]:
		var image := Image.load_from_file("res://../asset_sources/spirit/ui/cursor_sources/" + id + "_source.png")
		image.resize(48, 48, Image.INTERPOLATE_NEAREST)
		image.save_png("res://assets/ui/" + id + ".png")
	quit()
