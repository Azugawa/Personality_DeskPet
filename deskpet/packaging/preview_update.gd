extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var service = root.get_node("UpdateService")
	service._message("正在检查更新，请稍候……")
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	service.dialog.get_texture().get_image().save_png("E:/DeskPet/build/update-panel-preview.png")
	quit()
