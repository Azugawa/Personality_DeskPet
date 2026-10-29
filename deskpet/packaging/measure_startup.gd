extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var start := Time.get_ticks_msec()
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	print("SCENE_READY_MS=",Time.get_ticks_msec()-start)
	quit()
