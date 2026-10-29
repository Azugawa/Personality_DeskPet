extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var start := Time.get_ticks_msec()
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var source = load("res://packaging/physics_source.gd").new()
	main.add_child(source)
	source.setup(main.get_node("PetWorld/PetInput"))
	var base := "res://assets/character/spirit/physics/"
	DirAccess.make_dir_recursive_absolute(base)
	for key in ["held","prone"]:
		DirAccess.make_dir_recursive_absolute(base+key)
		source.textures[key].get_image().save_png(base+key+"/00.png")
	for key in ["flight","landing","getup"]:
		DirAccess.make_dir_recursive_absolute(base+key)
		for i in source.textures[key].size(): source.textures[key][i].get_image().save_png(base+key+"/%02d.png" % i)
	var file := FileAccess.open(base+"metadata.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cloth_grab":[source.cloth_grab.x,source.cloth_grab.y]}))
	print("BAKE completed ms=",Time.get_ticks_msec()-start)
	quit()
