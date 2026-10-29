extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var physics = main.get_node("PetWorld/PetInput").physics
	var canvas := Image.create(1500,400,false,Image.FORMAT_RGBA8)
	canvas.fill(Color("738493"))
	for i in physics.textures.getup.size():
		var frame: Image = physics.textures.getup[i].get_image()
		frame.save_png("E:/DeskPet/build/getup-frame-%d.png" % i)
		var factor := minf(230.0/frame.get_width(),360.0/frame.get_height())
		frame.resize(int(frame.get_width()*factor),int(frame.get_height()*factor),Image.INTERPOLATE_NEAREST)
		canvas.blend_rect(frame,Rect2i(Vector2i.ZERO,frame.get_size()),Vector2i(i*250,400-frame.get_height()))
	canvas.save_png("E:/DeskPet/build/getup-frames.png")
	quit()
