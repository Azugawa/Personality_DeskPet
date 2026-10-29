extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var p = main.get_node("PetWorld/PetInput").physics
	var idle = p.input._character.animated_body
	print("IDLE visible size: ",Vector2(idle.sprite_frames.get_frame_texture(idle.animation,idle.frame).get_image().get_used_rect().size) * idle.scale * p.input._character.body_root.scale)
	var all: Array = [p.textures.held]
	all.append_array(p.textures.flight)
	all.append_array(p.textures.landing)
	all.append(p.textures.prone)
	all.append_array(p.textures.getup.slice(1))
	var canvas := Image.create(1680,2000,false,Image.FORMAT_RGBA8)
	canvas.fill(Color("738493"))
	for i in all.size():
		var img: Image = all[i].get_image()
		print(i, " ",img.get_size())
		img.save_png("E:/DeskPet/build/pose-%d.png" % i)
		var ratio: float = p.pose_scales[all[i]]
		img.resize(int(img.get_width()*ratio),int(img.get_height()*ratio),Image.INTERPOLATE_NEAREST)
		canvas.blend_rect(img,Rect2i(Vector2i.ZERO,img.get_size()),Vector2i((i%4)*420,(i/4)*500+500-img.get_height()))
	canvas.save_png("E:/DeskPet/build/all-poses.png")
	quit()
