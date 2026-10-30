extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var script = load("res://scripts/ui/temp/assistant_window.gd")
	for kind in ["定时任务", "天气", "C 盘检查", "系统状态", "设置"]:
		var panel = script.new()
		panel.panel_kind = kind
		root.add_child(panel)
		panel.show()
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		panel.get_texture().get_image().save_png("E:/DeskPet/build/panel-" + kind + ".png")
		panel.queue_free()
		await process_frame
	quit()
