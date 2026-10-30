extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var script = load("res://scripts/ui/temp/assistant_window.gd")
	var layout = script.new()
	var screen := Rect2i(0, 0, 1000, 800)
	assert(layout._panel_position(Rect2(100, 100, 100, 100), screen, Vector2i(300, 500)).x == 214)
	assert(layout._panel_position(Rect2(800, 100, 100, 100), screen, Vector2i(300, 500)).x == 486)
	assert(layout._panel_position(Rect2(0, 100, 1000, 100), screen, Vector2i(300, 500)).x == 700)
	layout.free()
	for kind in ["定时任务", "天气", "C 盘检查", "系统状态", "设置"]:
		var panel = script.new()
		panel.panel_kind = kind
		root.add_child(panel)
		await process_frame
		await process_frame
		assert(panel._tabs.get_tab_count() > 0)
		assert(panel.size.x <= 400)
		assert(panel.size.y <= 600)
		print("PANEL_OK ", kind, " size=", panel.size)
		panel.queue_free()
		await process_frame
	print("PASS: assistant panels")
	quit()
