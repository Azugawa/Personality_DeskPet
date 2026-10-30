extends SceneTree
func _init() -> void:
	var source := Image.load_from_file("res://assets/ui/panels/dialog_sheet.png")
	var cropped := source.get_region(Rect2i(1250, 827, 270, 153))
	cropped.fill_rect(Rect2i(0, 0, 190, 15), Color.TRANSPARENT)
	cropped.save_png("res://assets/ui/panels/assistant_panel.png")
	quit()
