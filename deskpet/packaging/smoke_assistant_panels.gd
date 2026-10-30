extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var script = load("res://scripts/ui/temp/assistant_window.gd")
	for kind in ["定时任务", "天气", "C 盘检查", "系统状态", "设置"]:
		var panel = script.new()
		panel.panel_kind = kind
		root.add_child(panel)
		await process_frame
		await process_frame
		assert(panel._tabs.get_tab_count() > 0)
		print("PANEL_OK ", kind, " size=", panel.size)
		panel.queue_free()
		await process_frame
	print("PASS: assistant panels")
	quit()
