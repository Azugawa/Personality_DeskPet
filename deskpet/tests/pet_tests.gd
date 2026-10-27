extends Node
## Headless acceptance tests for the persistent pet runtime.
##
## These tests instantiate the real Main/PetWorld, real state machine,
## CharacterAnimator and FurnitureManager. Missing sitting/carrying art is
## asserted as a deliberate, safe rejection rather than a fake pass.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var checks: int = 0
var failures: PackedStringArray = PackedStringArray()
var main: Node = null
var world: PetWorld = null
var character: Character = null
var machine: ActionStateMachine = null
var furniture: FurnitureManager = null


func _ready() -> void:
	await get_tree().process_frame
	print("=== DeskPet persistent-pet tests ===")
	await _setup_world()
	_test_project_and_assets()
	_test_character_and_animation()
	_test_furniture()
	await _test_state_machine()
	await _test_activity_menu()
	await _test_input_and_window()
	_finish()


func _setup_world() -> void:
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _wait(0.2)
	world = main.get_node_or_null("PetWorld") as PetWorld
	_check("main creates PetWorld", world != null)
	if world == null:
		return
	_check("PetWorld reports ready", world.is_ready())
	world.set_auto_enabled(false)
	character = world.get_character()
	machine = world.get_state_machine()
	furniture = world.get_furniture_manager()
	_check("character exists", character != null)
	_check("state machine exists", machine != null)
	_check("furniture manager exists", furniture != null)


func _test_project_and_assets() -> void:
	var version := Engine.get_version_info()
	_check("Godot 4.x runtime", int(version.get("major", 0)) == 4, str(version))
	_check("main scene starts opaque", not get_window().transparent)
	_check("per-pixel transparency is allowed", bool(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed", false)))
	_check("default texture filter is nearest", int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", -1)) == 0)

	var animation_config := ConfigLoader.load_json("res://config/animations/spirit.json")
	_check("animation config loads", not animation_config.is_empty())
	var directions: Array = animation_config.get("directions", [])
	_check("eight authored directions", directions.size() == 8, str(directions))
	_check("sixteen character clips", (animation_config.get("animations", {}) as Dictionary).size() == 16)
	_check("all direction idle maps exist", (animation_config.get("direction_idle", {}) as Dictionary).size() == 8)
	_check("all direction walk maps exist", (animation_config.get("direction_walk", {}) as Dictionary).size() == 8)

	for direction in directions:
		var path := "res://assets/character/spirit/directions/%s.png" % str(direction)
		_check("direction texture exists: " + str(direction), FileAccess.file_exists(path))
	for direction in directions:
		for frame in range(1, 5):
			var path := "res://assets/character/spirit/walk/%s_%02d.png" % [str(direction), frame]
			_check("walk frame exists: %s/%d" % [str(direction), frame], FileAccess.file_exists(path), path)
	for index in range(1, 6):
		_check("idle frame exists: %d" % index, FileAccess.file_exists("res://assets/character/spirit/idle/front_%02d.png" % index))

	_check("chair atlas exists", FileAccess.file_exists("res://assets/props/chair/front.png"))
	_check("desk atlas exists", FileAccess.file_exists("res://assets/props/desk/front.png"))
	_check("computer atlas exists", FileAccess.file_exists("res://assets/props/computer/front.png"))
	_check("sprite manifest exists", FileAccess.file_exists("res://assets/sprite_manifest.json"))
	_check("source original untouched", FileAccess.get_sha256(ProjectSettings.globalize_path("res://../Spirit/人物图_透明.png")).to_lower() == "deca4a6b53ebd2f7f60128e14bc29930c616416e932b13ce5cab49a8bb61c8dc")


func _test_character_and_animation() -> void:
	if character == null:
		return
	_check("character uses animation mode", character.is_using_animations())
	_check("character exposes eight directions", character.get_available_directions().size() == 8)
	_check("character has sixteen clips", character.get_animation_names().size() == 16)
	_check("default direction is front", character.get_current_direction() == "front", character.get_current_direction())
	_check("idle front is playing", character.get_current_animation() == "idle_front", character.get_current_animation())
	_check("animated sprite uses nearest filtering", character.animated_body.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	_check("animated body is visible", character.animated_body.visible)
	_check("legacy full-body sprite is hidden", not character.full_body_sprite.visible)

	_check("manual direction right", character.set_facing("right"))
	_check("right idle clip selected", character.get_current_animation() == "idle_right", character.get_current_animation())
	_check("right walk clip starts", character.play_walk("right"))
	_check("right walk clip selected", character.get_current_animation() == "walk_right", character.get_current_animation())
	var walking_size := character.get_content_size()
	_check("walking character display box is sane", walking_size.y >= 300.0 and walking_size.y <= 340.0, str(walking_size))
	_check("front-direction vector maps to front", Character.direction_from_vector(Vector2(0, 1)) == "front")
	_check("up-direction vector maps to back", Character.direction_from_vector(Vector2(0, -1)) == "back")
	_check("down-right vector maps to front_right", Character.direction_from_vector(Vector2(1, 1)) == "front_right")
	_check("up-left vector maps to back_left", Character.direction_from_vector(Vector2(-1, -1)) == "back_left")

	character.set_facing("front")
	character.play_idle("front")
	_check("idle clip has five frames", character.animator.get_frame_count("idle_front") == 5)
	_check("walk clip has four frames", character.animator.get_frame_count("walk_front") == 4)


func _test_furniture() -> void:
	if furniture == null:
		return
	_check("three independent furniture nodes", furniture.get_ids().size() == 3, str(furniture.get_ids()))
	var chair := furniture.get_view("chair")
	var desk := furniture.get_view("desk")
	var computer := furniture.get_view("computer")
	_check("chair view exists", chair != null)
	_check("desk view exists", desk != null)
	_check("computer view exists", computer != null)
	if chair == null or desk == null or computer == null:
		return
	_check("chair has seat anchor", chair.has_anchor("seat"))
	_check("desk has work-surface anchor", desk.has_anchor("work_surface"))
	_check("computer has screen anchor", computer.has_anchor("screen"))
	_check("furniture nodes are independent", chair.get_parent() == desk.get_parent() and chair != desk)

	var original_chair_position := chair.position
	furniture.move_to("chair", original_chair_position + Vector2(24, 0), 0.0)
	_check("chair can move independently", chair.position.is_equal_approx(original_chair_position + Vector2(24, 0)), str(chair.position))
	furniture.move_to("chair", original_chair_position, 0.0)

	furniture.set_visible("chair", false, false)
	_check("chair hides independently", not furniture.is_visible("chair"))
	_check("desk remains visible when chair hides", furniture.is_visible("desk"))
	furniture.set_visible("chair", true, false)
	_check("chair shows independently", furniture.is_visible("chair"))
	_check("chair can switch authored direction", furniture.set_direction("chair", "right"))
	_check("chair direction updated", chair.get_direction() == "right", chair.get_direction())
	furniture.set_direction("chair", "front")

	furniture.set_visible("desk", true, false)
	furniture.set_visible("computer", true, false)
	_check("workstation assets are mutually exclusive", not furniture.is_visible("desk") and furniture.is_visible("computer"))
	furniture.set_visible("desk", true, false)
	_check("switching back shows desk and hides computer", furniture.is_visible("desk") and not furniture.is_visible("computer"))


func _test_state_machine() -> void:
	if machine == null or character == null:
		return
	world.set_auto_enabled(false)
	machine.request_idle(ActionStateMachine.MANUAL)
	await _wait(0.05)
	_check("initial state is idle", machine.current_state == "idle", machine.current_state)

	_check("manual head pat accepted", machine.request_head_pat(ActionStateMachine.MANUAL))
	_check("head-pat action is active", machine.current_action == "head_pat", machine.current_action)
	_check("head-pat enters interact state", machine.current_state == "interact", machine.current_state)
	_check("manual head pat pauses auto", machine.is_auto_paused())
	_check("auto cannot act during manual pause", not machine.can_auto_act())
	_check("auto walk request is rejected", not machine.request_auto_walk())
	await _wait(0.9)
	_check("head pat returns to idle", machine.current_state == "idle", machine.current_state)
	_check("head pat cleared current action", machine.current_action.is_empty(), machine.current_action)

	var target := character.position + Vector2(64, 0)
	_check("manual walk accepted", machine.request_walk_to(target, ActionStateMachine.MANUAL))
	_check("walking state entered", machine.current_state == "walk", machine.current_state)
	await _wait(1.3)
	_check("walk reaches target", character.position.distance_to(target) < 2.0, str(character.position))
	_check("walk returns to idle", machine.current_state == "idle", machine.current_state)
	_check("walk action finished", machine.current_action.is_empty(), machine.current_action)

	machine.set_manual_direction(Vector2.RIGHT)
	await _wait(0.35)
	_check("manual movement enters walk", machine.current_state == "walk", machine.current_state)
	_check("manual walk animation advances", character.animated_body.frame > 0, str(character.animated_body.frame))
	machine.set_manual_direction(Vector2.ZERO)
	await _wait(0.05)
	_check("manual movement release returns to idle", machine.current_state == "idle", machine.current_state)

	_check("sit is rejected safely because poses are absent", not machine.request_sit(ActionStateMachine.MANUAL))
	_check("stand is rejected when not seated", not machine.request_stand(ActionStateMachine.MANUAL))

	_check("manual chair toggle accepted", machine.request_furniture_toggle("chair", ActionStateMachine.MANUAL))
	await _wait(0.35)
	_check("chair hidden after toggle", not furniture.is_visible("chair"))
	_check("manual chair toggle accepted again", machine.request_furniture_toggle("chair", ActionStateMachine.MANUAL))
	await _wait(0.35)
	_check("chair visible after second toggle", furniture.is_visible("chair"))


func _test_activity_menu() -> void:
	_check("normal mode keeps optional auto behaviour off", not world.get_behavior_brain().is_auto_enabled())
	world.set_auto_enabled(true)
	_check("optional auto mode can be enabled", world.get_behavior_brain().is_auto_enabled())
	world.set_auto_enabled(false)
	_check("optional auto mode can be disabled", not world.get_behavior_brain().is_auto_enabled())

	_check("activity menu controller exists", world.get_activity_controller() != null)
	var entries := world.get_activity_menu_entries()
	_check("activity menu has idle/rest/computer", entries.size() == 3, str(entries))
	var labels: Array[String] = []
	for entry_value in entries:
		labels.append(str((entry_value as Dictionary).get("label", "")))
	_check("activity menu includes rest", labels.has("休息（坐姿待补）"), str(labels))
	_check("activity menu includes computer", labels.has("玩电脑（坐姿待补）"), str(labels))
	var chair := furniture.get_view("chair")
	var approach := furniture.get_approach_position("chair")
	_check("chair approach anchor is in front of chair", approach.is_equal_approx(chair.position + Vector2(0, 28)), str(approach))

	_check("partial rest activity accepted", world.request_activity("rest"))
	_check("rest activity starts with a walk", machine.current_state == "walk", machine.current_state)
	await _wait(1.9)
	_check("rest activity returns to idle while seated clip is absent", machine.current_state == "idle", machine.current_state)
	_check("rest activity reveals chair and desk", furniture.is_visible("chair") and furniture.is_visible("desk"))
	_check("rest activity keeps computer hidden", not furniture.is_visible("computer"))
	_check("rest activity stops at the chair approach", character.position.distance_to(approach) < 3.0, str(character.position))

	var menu := world.get_node_or_null("PetMenu") as PetMenu
	_check("right-click menu node exists", menu != null)
	if menu != null:
		var right_click := InputEventMouseButton.new()
		right_click.button_index = MOUSE_BUTTON_RIGHT
		right_click.pressed = true
		right_click.position = character.get_screen_bounds().get_center()
		world.pet_input._unhandled_input(right_click)
		_check("right-click on character opens menu", menu.is_menu_visible())
		menu.hide_menu()
		_check("right-click menu can close", not menu.is_menu_visible())


func _test_input_and_window() -> void:
	_check("movement action registered", InputMap.has_action("pet_move_up"))
	_check("movement action has key events", InputMap.action_get_events("pet_move_up").size() >= 2)
	_check("controls help mentions movement", PetInput.controls_text().contains("WASD"))

	var click_position := character.get_screen_bounds().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click_position
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click_position
	world.pet_input._handle_left_button(press)
	world.pet_input._handle_left_button(release)
	await _wait(0.1)
	_check("left-click on character requests head pat", machine.current_action == "head_pat", machine.current_action)
	await _wait(0.8)
	_check("click interaction returns to idle", machine.current_state == "idle", machine.current_state)

	_check("preview window is not borderless", not get_window().borderless)
	_check("preview window is not always on top", not get_window().always_on_top)
	_check("furniture has contact shadows", world.furniture_manager.get_view("chair").shadow_root.get_child_count() == 1)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures.append(label if detail.is_empty() else "%s (detail: %s)" % [label, detail])
		print("FAIL: " + label + ("" if detail.is_empty() else "  detail=" + detail))


func _finish() -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
	if failures.is_empty():
		print("=== PET_TEST_RESULT: PASS (%d checks) ===" % checks)
		get_tree().quit(0)
	else:
		print("=== PET_TEST_RESULT: FAIL (%d checks, %d failed) ===" % [checks, failures.size()])
		for failure in failures:
			print("FAILED CHECK: " + failure)
		get_tree().quit(1)
