extends Node
## LEGACY static-scene tests.
##
## This file documents the previous SceneManager/SceneView phase. It is no
## longer the active runner: tests/test_runner.tscn now starts pet_tests.gd.
## The default runtime is the persistent PetWorld; these checks are kept only
## for historical comparison and should not be used as current acceptance.

## Old headless integration/acceptance tests.
##
## Run:
##   godot --headless --path <project> res://tests/test_runner.tscn
##
## The test scene instantiates the real main scene and drives the real EventBus
## and SceneManager. It does not mock the scene system.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const CHARACTER_SCENE := preload("res://scenes/character/character.tscn")
const PROP_SCENE := preload("res://scenes/props/prop.tscn")
const PSEUDO3D_PROP_SCENE := preload("res://scenes/props/pseudo3d_prop.tscn")

const EXPECTED_SOURCE_SHA256 := "deca4a6b53ebd2f7f60128e14bc29930c616416e932b13ce5cab49a8bb61c8dc"

var failures: PackedStringArray = PackedStringArray()
var checks: int = 0
var main: Node = null

var game_events: Array[String] = []
var system_events: Array[String] = []
var switch_records: Array[String] = []
var failure_records: Array[String] = []
var main_phase_completed: bool = false
var missing_asset_phase_completed: bool = false
var asset_integrity_phase_completed: bool = false


func _ready() -> void:
	await get_tree().process_frame
	print("=== DeskPet integration tests ===")
	_connect_test_listeners()

	_test_runtime_and_registry()
	await _test_main_and_scenes()
	_check("main/scene test phase completed", main_phase_completed)
	_test_missing_asset_diagnostics()
	_check("missing-asset test phase completed", missing_asset_phase_completed)
	_test_asset_integrity()
	_check("asset-integrity test phase completed", asset_integrity_phase_completed)
	_finish()


func _connect_test_listeners() -> void:
	EventBus.game_event.connect(_on_test_game_event)
	EventBus.system_event.connect(_on_test_system_event)
	SceneManager.scene_changed.connect(_on_test_scene_changed)
	SceneManager.scene_change_failed.connect(_on_test_scene_change_failed)


func _test_runtime_and_registry() -> void:
	var version := Engine.get_version_info()
	_check("engine is Godot 4.x", int(version.get("major", 0)) == 4, str(version))
	_check("default texture filter is nearest", int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", -1)) == 0)
	_check("2D MSAA is disabled", int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d", -1)) == 0)
	_check("screen-space AA is disabled", int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", -1)) == 0)
	_check("2D transforms snap to pixels", bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false)) == true)
	_check("2D vertices snap to pixels", bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_vertices_to_pixel", false)) == true)
	_check("preview startup is opaque", bool(ProjectSettings.get_setting("display/window/size/transparent", true)) == false)
	_check("per-pixel transparency is allowed for desktop mode", bool(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed", false)) == true)
	_check("window is not borderless at startup", bool(ProjectSettings.get_setting("display/window/size/borderless", true)) == false)
	_check("window is not always-on-top at startup", bool(ProjectSettings.get_setting("display/window/size/always_on_top", true)) == false)

	var scene_ids := SceneManager.get_registered_scene_ids()
	_check("two scenes registered", scene_ids.size() == 2, str(scene_ids))
	_check("standing registered", scene_ids.has("standing"), str(scene_ids))
	_check("workspace_setup registered", scene_ids.has("workspace_setup"), str(scene_ids))
	_check("default scene is standing", SceneManager.get_default_scene_id() == "standing")
	_check("scene registry has no error", SceneManager.get_registry_error().is_empty(), SceneManager.get_registry_error())

	var standing_config := SceneManager.get_scene_config("standing")
	var workspace_config := SceneManager.get_scene_config("workspace_setup")
	_check("standing config validates", ConfigLoader.validate_scene_config(standing_config, "standing").is_empty(), str(ConfigLoader.validate_scene_config(standing_config, "standing")))
	_check("workspace config validates", ConfigLoader.validate_scene_config(workspace_config, "workspace_setup").is_empty(), str(ConfigLoader.validate_scene_config(workspace_config, "workspace_setup")))
	_check("standing config has zero props", (standing_config.get("props", []) as Array).is_empty())
	_check("workspace config has two props", (workspace_config.get("props", []) as Array).size() == 2)
	_check("standing transition targets workspace", str((standing_config.get("transitions", {}) as Dictionary).get("workspace_requested", {}).get("target_scene", "")) == "workspace_setup")
	_check("workspace transition targets standing", str((workspace_config.get("transitions", {}) as Dictionary).get("workspace_exit_requested", {}).get("target_scene", "")) == "standing")

	var visual := Pseudo3D.get_profile()
	_check("pseudo-3D visual profile loads", not visual.is_empty(), str(visual.get("profile_id", "")))
	_check("visual profile id is stable", str(visual.get("profile_id", "")) == "deskpet_pseudo3d_v1", str(visual.get("profile_id", "")))
	_check("depth axis is shared", Pseudo3D.depth_axis(visual).is_equal_approx(Vector2(0.55, -0.35)), str(Pseudo3D.depth_axis(visual)))
	_check("ground front is y=660", is_equal_approx(Pseudo3D.front_y(visual), 660.0))
	_check("ground origin projects correctly", Pseudo3D.project_ground(visual, 320, 0).is_equal_approx(Vector2(320, 660)), str(Pseudo3D.project_ground(visual, 320, 0)))
	_check("depth projection is consistent", Pseudo3D.project_ground(visual, 415, 75).is_equal_approx(Vector2(456.25, 633.75)), str(Pseudo3D.project_ground(visual, 415, 75)))
	_check("projection is orthographic (no perspective scaling)", bool((visual.get("camera", {}) as Dictionary).get("perspective_scaling", true)) == false)
	_check("floor guide is configured", not Pseudo3D.floor_guide(visual).is_empty())
	_check("desk material exists", not Pseudo3D.material(visual, "desk_top").is_empty())
	_check("chair material exists", not Pseudo3D.material(visual, "chair_body").is_empty())

	var character_visual: Dictionary = ConfigLoader.load_json("res://config/characters/spirit.json").get("visual", {})
	_check("character is a front billboard", str(character_visual.get("projection", "")) == "front_billboard", str(character_visual.get("projection", "")))
	_check("character only has front view", (character_visual.get("available_views", []) as Array) == ["front"], str(character_visual.get("available_views", [])))
	var missing_views: Array = character_visual.get("missing_views", [])
	var missing_states: Array = character_visual.get("missing_states", [])
	_check("all 7 other directions are declared missing", missing_views.has("back") and missing_views.has("front_right") and missing_views.has("front_left") and missing_views.has("right") and missing_views.has("left") and missing_views.has("back_right") and missing_views.has("back_left"), str(missing_views))
	_check("sit and carry states are declared missing", missing_states.has("sitting") and missing_states.has("carrying"), str(missing_states))
	_check("mirroring is not treated as a turn", bool(character_visual.get("mirroring_is_not_a_turn", false)) == true)

	var workspace_desk_config: Dictionary = (workspace_config.get("props", []) as Array)[0]
	var workspace_chair_config: Dictionary = (workspace_config.get("props", []) as Array)[1]
	_check("desk references reusable profile", str(workspace_desk_config.get("profile", "")) == "res://config/props/debug_desk.json", str(workspace_desk_config.get("profile", "")))
	_check("chair references reusable profile", str(workspace_chair_config.get("profile", "")) == "res://config/props/debug_chair.json", str(workspace_chair_config.get("profile", "")))
	var workspace_desk_ground: Array = workspace_desk_config.get("ground_position", [])
	var workspace_chair_ground: Array = workspace_chair_config.get("ground_position", [])
	_check("desk uses ground position", workspace_desk_ground.size() == 2 and is_equal_approx(float(workspace_desk_ground[0]), 415.0) and is_equal_approx(float(workspace_desk_ground[1]), 75.0), str(workspace_desk_ground))
	_check("chair uses ground position", workspace_chair_ground.size() == 2 and is_equal_approx(float(workspace_chair_ground[0]), 330.0) and is_equal_approx(float(workspace_chair_ground[1]), 25.0), str(workspace_chair_ground))
	_check("character depth is in front of chair", int((workspace_config.get("character", {}) as Dictionary).get("ground_position", [0, 0])[1]) < int(workspace_chair_config.get("ground_position", [0, 0])[1]))
	_check("chair depth is in front of desk", int(workspace_chair_config.get("ground_position", [0, 0])[1]) < int(workspace_desk_config.get("ground_position", [0, 0])[1]))
	_check("closer objects render above farther objects", int((workspace_config.get("character", {}) as Dictionary).get("z_index", 0)) > int(workspace_chair_config.get("z_index", 0)) and int(workspace_chair_config.get("z_index", 0)) > int(workspace_desk_config.get("z_index", 0)))

	var desk_profile := ConfigLoader.load_json("res://config/props/debug_desk.json")
	var chair_profile := ConfigLoader.load_json("res://config/props/debug_chair.json")
	_check("desk profile is debug placeholder", str(desk_profile.get("kind", "")) == "debug_pseudo3d")
	_check("chair profile is debug placeholder", str(chair_profile.get("kind", "")) == "debug_pseudo3d")
	_check("desk profile has configured parts", (desk_profile.get("parts", []) as Array).size() == 6, str((desk_profile.get("parts", []) as Array).size()))
	_check("chair profile has configured parts", (chair_profile.get("parts", []) as Array).size() == 6, str((chair_profile.get("parts", []) as Array).size()))


func _test_main_and_scenes() -> void:
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _frames(3)

	_check("main scene instantiated and runs", is_instance_valid(main))
	_check("startup scene is standing", SceneManager.current_scene_id == "standing", SceneManager.current_scene_id)
	_check("preview window is opaque", not get_window().transparent)
	_check("preview window is not borderless", not get_window().borderless)

	var standing_view: SceneView = SceneManager.current_view
	_check("standing SceneView exists", standing_view != null and is_instance_valid(standing_view))
	if standing_view == null:
		return
	_check("standing has zero prop nodes", standing_view.prop_nodes.is_empty(), str(standing_view.prop_nodes.keys()))
	_check("standing has no PropView instances", standing_view.find_children("", "PropView", true, false).is_empty())
	_check("standing has no pseudo-3D prop instances", standing_view.find_children("", "Pseudo3DPropView", true, false).is_empty())
	_check("background is an independent object", standing_view.background != null and standing_view.background.get_parent() == standing_view)
	_check("scene view uses the shared visual profile", not standing_view.visual_profile.is_empty(), str(standing_view.visual_profile.get("profile_id", "")))
	var stage_guide := main.get_node_or_null("BackdropLayer/StageGuide") as StageGuide
	_check("preview floor guide exists", stage_guide != null and is_instance_valid(stage_guide))
	_check("preview floor guide uses the visual profile", stage_guide != null and stage_guide.is_configured())
	_check("preview floor guide is visible in preview mode", stage_guide != null and stage_guide.is_visible_in_tree())

	var standing_character: Character = standing_view.character_node
	_check("standing character exists", standing_character != null and is_instance_valid(standing_character))
	if standing_character == null:
		return
	_check("character uses the shared Character scene", standing_character.scene_file_path == "res://scenes/character/character.tscn", standing_character.scene_file_path)
	_check("character is in its own Characters container", standing_character.get_parent() == standing_view.characters_root)
	_check("character texture loaded", standing_character.get_texture() != null)
	_check("character uses nearest filtering", standing_character.full_body_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	_check("character has a shadow layer child", standing_character.shadow_root.get_child_count() == 1)
	_check("character shadow uses ShadowView", standing_character.shadow_root.get_child(0) is ShadowView)
	_check("character body is not rotated", is_zero_approx(standing_character.body_root.rotation))
	_check("standing character x comes from ground projection", is_equal_approx(standing_character.position.x, 320.0), str(standing_character.position))
	_check("standing character y comes from ground projection", is_equal_approx(standing_character.position.y, 660.0), str(standing_character.position))
	_check("standing character depth is front row", is_zero_approx(standing_character.get_ground_depth()), str(standing_character.get_ground_depth()))
	_check("standing character z is configured", standing_character.z_index == 50, str(standing_character.z_index))
	_check("standing feet touch the ground line", is_equal_approx(standing_character.get_feet_anchor().y, Pseudo3D.front_y(Pseudo3D.get_profile())), str(standing_character.get_feet_anchor()))
	_check("character content height follows scale", is_equal_approx(standing_character.get_content_size().y, 1871.0 * 0.25), str(standing_character.get_content_size()))
	var shared_texture := standing_character.get_texture()
	var shared_texture_path := standing_character.get_texture_path()
	var shared_scene_path := standing_character.scene_file_path
	var shared_profile_path := standing_character.profile_path

	EventBus.emit_game_event("workspace_requested", {"source": "integration_test"})
	await _frames(3)
	_check("workspace_requested switches scene", SceneManager.current_scene_id == "workspace_setup", SceneManager.current_scene_id)
	_check("switch recorded by SceneManager", switch_records.size() >= 2, str(switch_records))

	var workspace_view: SceneView = SceneManager.current_view
	_check("workspace SceneView exists", workspace_view != null and is_instance_valid(workspace_view))
	if workspace_view == null:
		return
	_check("workspace has two props", workspace_view.prop_nodes.size() == 2, str(workspace_view.prop_nodes.keys()))
	_check("workspace has no legacy flat props", workspace_view.find_children("", "PropView", true, false).is_empty())
	_check("workspace has two pseudo-3D props", workspace_view.find_children("", "Pseudo3DPropView", true, false).size() == 2)
	_check("workspace has desk_debug", workspace_view.prop_nodes.has("desk_debug"))
	_check("workspace has chair_debug", workspace_view.prop_nodes.has("chair_debug"))

	var workspace_character: Character = workspace_view.character_node
	_check("workspace shares Character scene", workspace_character.scene_file_path == shared_scene_path, workspace_character.scene_file_path)
	_check("workspace shares texture resource", workspace_character.get_texture() == shared_texture)
	_check("workspace shares texture path", workspace_character.get_texture_path() == shared_texture_path)
	_check("workspace character inherits profile", workspace_character.profile_path == shared_profile_path, workspace_character.profile_path)
	_check("workspace character x comes from ground projection", is_equal_approx(workspace_character.position.x, 170.0), str(workspace_character.position))
	_check("workspace character y stays on the ground line", is_equal_approx(workspace_character.position.y, 660.0), str(workspace_character.position))
	_check("workspace character depth is front row", is_zero_approx(workspace_character.get_ground_depth()))
	_check("workspace character z is configured", workspace_character.z_index == 50, str(workspace_character.z_index))

	var desk: Pseudo3DPropView = workspace_view.prop_nodes["desk_debug"]
	var chair: Pseudo3DPropView = workspace_view.prop_nodes["chair_debug"]
	_check("desk is an independent object", desk.get_parent() == workspace_view.props_root)
	_check("chair is an independent object", chair.get_parent() == workspace_view.props_root)
	_check("desk is a pseudo-3D debug prop", desk.prop_type == "pseudo3d_debug", desk.prop_type)
	_check("chair is a pseudo-3D debug prop", chair.prop_type == "pseudo3d_debug", chair.prop_type)
	_check("desk uses the reusable desk profile", desk.get_profile_path() == "res://config/props/debug_desk.json", desk.get_profile_path())
	_check("chair uses the reusable chair profile", chair.get_profile_path() == "res://config/props/debug_chair.json", chair.get_profile_path())
	_check("desk profile id is debug_desk", desk.get_profile_id() == "debug_desk", desk.get_profile_id())
	_check("chair profile id is debug_chair", chair.get_profile_id() == "debug_chair", chair.get_profile_id())
	_check("desk has six configurable parts", desk.get_parts_count() == 6, str(desk.get_parts_count()))
	_check("chair has six configurable parts", chair.get_parts_count() == 6, str(chair.get_parts_count()))
	_check("desk screen position follows ground projection", desk.position.is_equal_approx(Pseudo3D.project_ground(workspace_view.visual_profile, 415, 75)), str(desk.position))
	_check("chair screen position follows ground projection", chair.position.is_equal_approx(Pseudo3D.project_ground(workspace_view.visual_profile, 330, 25)), str(chair.position))
	_check("desk depth is configured", is_equal_approx(desk.get_ground_depth(), 75.0), str(desk.get_ground_depth()))
	_check("chair depth is configured", is_equal_approx(chair.get_ground_depth(), 25.0), str(chair.get_ground_depth()))
	_check("desk z_index comes from config", desk.z_index == 30, str(desk.z_index))
	_check("chair z_index comes from config", chair.z_index == 40, str(chair.z_index))
	_check("desk visible comes from config", desk.visible == true)
	_check("desk has independent contact shadow", desk.get_shadow_root() != null and desk.get_shadow_root().get_child_count() == 1)
	_check("chair has independent contact shadow", chair.get_shadow_root() != null and chair.get_shadow_root().get_child_count() == 1)
	_check("desk shadow uses ShadowView", desk.get_shadow_root().get_child(0) is ShadowView)
	_check("chair shadow uses ShadowView", chair.get_shadow_root().get_child(0) is ShadowView)
	_check("background remains independent in workspace", workspace_view.background != null and workspace_view.background.get_parent() == workspace_view)
	_check("character is in front of chair by z", workspace_character.z_index > chair.z_index)
	_check("chair is in front of desk by z", chair.z_index > desk.z_index)
	_check("character and chair overlap on screen for occlusion", workspace_character.get_screen_bounds().intersects(chair.get_visual_bounds()), str(workspace_character.get_screen_bounds()) + " / " + str(chair.get_visual_bounds()))
	_check("chair and desk overlap on screen for occlusion", chair.get_visual_bounds().intersects(desk.get_visual_bounds()), str(chair.get_visual_bounds()) + " / " + str(desk.get_visual_bounds()))

	# Re-apply a mutated config copy to prove that ground positions/layers/
	# visibility/scale are data-driven rather than hard-coded in scripts.
	var mutated := SceneManager.get_scene_config("workspace_setup")
	mutated["character"]["ground_position"] = [123, 10]
	mutated["props"][0]["ground_position"] = [11, 22]
	mutated["props"][0]["z_index"] = 33
	mutated["props"][1]["visible"] = false
	mutated["props"][1]["scale"] = 0.75
	var applied := workspace_view.apply_config(mutated)
	_check("mutated config applies", applied)
	var mutated_visual := workspace_view.visual_profile
	_check("mutated character ground position applied", workspace_view.character_node.position.is_equal_approx(Pseudo3D.project_ground(mutated_visual, 123, 10)), str(workspace_view.character_node.position))
	var mutated_desk: Pseudo3DPropView = workspace_view.prop_nodes["desk_debug"]
	var mutated_chair: Pseudo3DPropView = workspace_view.prop_nodes["chair_debug"]
	_check("mutated prop ground position applied", mutated_desk.position.is_equal_approx(Pseudo3D.project_ground(mutated_visual, 11, 22)), str(mutated_desk.position))
	_check("mutated prop depth applied", is_equal_approx(mutated_desk.get_ground_depth(), 22.0), str(mutated_desk.get_ground_depth()))
	_check("mutated prop z_index applied", mutated_desk.z_index == 33, str(mutated_desk.z_index))
	_check("mutated prop visibility applied", mutated_chair.visible == false)
	_check("mutated prop scale applied", mutated_chair.scale.is_equal_approx(Vector2(0.75, 0.75)), str(mutated_chair.scale))
	_check("config mutation restored", workspace_view.apply_config(SceneManager.get_scene_config("workspace_setup")))
	await _frames(1)

	var stable_desk: Pseudo3DPropView = workspace_view.prop_nodes["desk_debug"]
	var stable_chair: Pseudo3DPropView = workspace_view.prop_nodes["chair_debug"]
	var stable_desk_profile := stable_desk.get_profile_path()
	var stable_desk_position := stable_desk.position
	var stable_desk_z := stable_desk.z_index
	var stable_chair_profile := stable_chair.get_profile_path()
	var stable_chair_position := stable_chair.position
	var stable_chair_z := stable_chair.z_index

	# Allowed events in workspace must be accepted without switching.
	EventBus.emit_game_event("furniture_ready", {"prop_id": "desk_debug"})
	EventBus.emit_game_event("sit_requested", {"seat_id": "chair_debug"})
	EventBus.emit_game_event("sit_completed", {"seat_id": "chair_debug"})
	await _frames(2)
	_check("allowed non-transition events keep workspace", SceneManager.current_scene_id == "workspace_setup", SceneManager.current_scene_id)

	# Disallowed event must be ignored by the current scene.
	EventBus.emit_game_event("workspace_requested", {"source": "should_be_ignored"})
	await _frames(2)
	_check("disallowed event does not switch", SceneManager.current_scene_id == "workspace_setup", SceneManager.current_scene_id)

	_check("duplicate switch is rejected", SceneManager.request_scene_change("workspace_setup", "duplicate test") == false)
	var failures_before := failure_records.size()
	_check("unknown scene switch is rejected", SceneManager.request_scene_change("scene_that_does_not_exist", "invalid test") == false)
	await _frames(1)
	_check("unknown scene keeps current scene", SceneManager.current_scene_id == "workspace_setup", SceneManager.current_scene_id)
	_check("unknown scene emits failure signal", failure_records.size() > failures_before, str(failure_records))

	EventBus.emit_game_event("workspace_exit_requested", {"source": "integration_test"})
	await _frames(3)
	_check("workspace_exit_requested switches back", SceneManager.current_scene_id == "standing", SceneManager.current_scene_id)
	_check("scene_entered lifecycle event emitted", system_events.has("scene_entered"), str(system_events))
	_check("scene_exited lifecycle event emitted", system_events.has("scene_exited"), str(system_events))
	_check("typed event reached EventBus", game_events.has("workspace_requested"), str(game_events))

	# Re-enter workspace and prove the desk/chair profiles, positions and layers
	# do not change merely because the scene was rebuilt.
	EventBus.emit_game_event("workspace_requested", {"source": "re-entry test"})
	await _frames(3)
	_check("workspace can be re-entered", SceneManager.current_scene_id == "workspace_setup", SceneManager.current_scene_id)
	var reentry_view: SceneView = SceneManager.current_view
	var reentry_desk: Pseudo3DPropView = reentry_view.prop_nodes["desk_debug"]
	var reentry_chair: Pseudo3DPropView = reentry_view.prop_nodes["chair_debug"]
	_check("desk profile stable across scene switch", reentry_desk.get_profile_path() == stable_desk_profile, reentry_desk.get_profile_path())
	_check("desk position stable across scene switch", reentry_desk.position.is_equal_approx(stable_desk_position), str(reentry_desk.position))
	_check("desk z stable across scene switch", reentry_desk.z_index == stable_desk_z, str(reentry_desk.z_index))
	_check("chair profile stable across scene switch", reentry_chair.get_profile_path() == stable_chair_profile, reentry_chair.get_profile_path())
	_check("chair position stable across scene switch", reentry_chair.position.is_equal_approx(stable_chair_position), str(reentry_chair.position))
	_check("chair z stable across scene switch", reentry_chair.z_index == stable_chair_z, str(reentry_chair.z_index))
	EventBus.emit_game_event("workspace_exit_requested", {"source": "re-entry cleanup"})
	await _frames(3)
	_check("returns to standing after re-entry cleanup", SceneManager.current_scene_id == "standing", SceneManager.current_scene_id)
	main_phase_completed = true


func _test_missing_asset_diagnostics() -> void:
	var character := CHARACTER_SCENE.instantiate() as Character
	add_child(character)
	var loaded := character.setup({
		"profile": "res://tests/fixtures/missing_texture_profile.json",
		"position": [0, 0],
		"scale": 0.25,
		"state": "standing",
	})
	_check("missing character texture fails loudly", loaded == false)
	_check("missing character error names the file", character.last_error.contains("does_not_exist.png"), character.last_error)
	_check("missing character indicator is visible", character.missing_indicator != null and character.missing_indicator.visible)
	_check("missing character indicator explains the problem", character.missing_indicator != null and character.missing_indicator.text.contains("MISSING CHARACTER ASSET"))
	_check("missing character hides body root", character.body_root.visible == false)
	character.queue_free()

	var prop := PROP_SCENE.instantiate() as PropView
	add_child(prop)
	var prop_loaded := prop.setup({
		"id": "missing_prop",
		"type": "texture",
		"position": [0, 0],
		"visible": true,
		"texture": "res://assets/props/does_not_exist.png",
	})
	_check("missing prop texture fails loudly", prop_loaded == false)
	_check("missing prop error names the file", prop.last_error.contains("does_not_exist.png"), prop.last_error)
	prop.queue_free()

	var pseudo_prop := PSEUDO3D_PROP_SCENE.instantiate() as Pseudo3DPropView
	add_child(pseudo_prop)
	var pseudo_loaded := pseudo_prop.setup({
		"id": "missing_pseudo_prop",
		"type": "pseudo3d_debug",
		"profile": "res://tests/fixtures/does_not_exist_prop.json",
		"ground_position": [0, 0],
		"visible": true,
	}, Pseudo3D.get_profile())
	_check("missing furniture profile fails loudly", pseudo_loaded == false)
	_check("missing furniture profile error names the file", pseudo_prop.last_error.contains("does_not_exist_prop.json"), pseudo_prop.last_error)
	_check("missing furniture profile shows diagnostic state", pseudo_prop.is_missing_asset())
	pseudo_prop.queue_free()

	var background := BackgroundView.new()
	var background_loaded := background.setup({
		"type": "texture",
		"texture": "res://assets/backgrounds/does_not_exist.png",
	}, Vector2(640, 720))
	_check("missing background texture fails loudly", background_loaded == false)
	_check("missing background error names the file", background.last_error.contains("does_not_exist.png"), background.last_error)
	background.free()
	missing_asset_phase_completed = true


func _test_asset_integrity() -> void:
	var project_dir := ProjectSettings.globalize_path("res://")
	var original_path := project_dir.path_join("../Spirit/人物图_透明.png").simplify_path()
	var copied_path := ProjectSettings.globalize_path("res://assets/character/spirit/character_full.png")

	_check("original character PNG still exists", FileAccess.file_exists(original_path), original_path)
	if FileAccess.file_exists(original_path):
		var original_hash := FileAccess.get_sha256(original_path).to_lower()
		_check("original character PNG hash unchanged", original_hash == EXPECTED_SOURCE_SHA256, original_hash)
	var copied_hash := FileAccess.get_sha256(copied_path).to_lower()
	_check("copied character PNG hash matches original", copied_hash == EXPECTED_SOURCE_SHA256, copied_hash)

	var image_texture := load("res://assets/character/spirit/character_full.png") as Texture2D
	_check("character PNG loads as a texture", image_texture != null)
	var image: Image = image_texture.get_image() if image_texture != null else null
	_check("character PNG image is available", image != null)
	if image == null:
		return
	_check("character PNG is 2048x2048", image.get_width() == 2048 and image.get_height() == 2048, "%dx%d" % [image.get_width(), image.get_height()])
	_check("character PNG has an alpha channel", image.detect_alpha() != Image.ALPHA_NONE)
	_check("character PNG corner is transparent", is_equal_approx(image.get_pixel(0, 0).a, 0.0))

	var profile := ConfigLoader.load_json("res://config/characters/spirit.json")
	var rig: Dictionary = profile.get("rig_metadata", {})
	_check("character profile found", not profile.is_empty())
	_check("rig metadata is marked NEEDS_REVIEW", str(rig.get("status", "")) == "NEEDS_REVIEW", str(rig.get("status", "")))
	_check("part animation is disabled", bool(rig.get("usable_for_animation", true)) == false)
	_check("provisional joints metadata copied", FileAccess.file_exists("res://assets/character/spirit/rig_metadata/joints.json"))
	_check("provisional layers metadata copied", FileAccess.file_exists("res://assets/character/spirit/rig_metadata/layers.json"))
	_check("segmentation metadata copied", FileAccess.file_exists("res://assets/character/spirit/rig_metadata/segmentation.json"))

	# The Godot project must mirror the character_assets segmentation exactly.
	# Any edit on the pipeline side must be re-copied here (no ad-hoc re-split).
	var source_config_dir := project_dir.path_join("../character_assets/config").simplify_path()
	var mirror_ok := true
	var mirror_detail := ""
	for mirrored_file: String in ["joints.json", "layers.json", "segmentation.json"]:
		var source_file: String = source_config_dir.path_join(mirrored_file).simplify_path()
		var project_file: String = "res://assets/character/spirit/rig_metadata/" + mirrored_file
		if not FileAccess.file_exists(source_file) or not FileAccess.file_exists(project_file):
			mirror_ok = false
			mirror_detail = "%s: source or project copy missing" % mirrored_file
			break
		if _read_text_file(source_file) != _read_text_file(project_file):
			mirror_ok = false
			mirror_detail = "%s differs from character_assets" % mirrored_file
			break
	_check("rig metadata mirrors character_assets exactly", mirror_ok, mirror_detail)

	_check("no unsupported parts assets are referenced", not FileAccess.file_exists("res://assets/character/spirit/parts/head.png"))
	_check("pseudo-3D visual profile file exists", FileAccess.file_exists("res://config/visual/pseudo3d.json"))
	_check("desk profile file exists", FileAccess.file_exists("res://config/props/debug_desk.json"))
	_check("chair profile file exists", FileAccess.file_exists("res://config/props/debug_chair.json"))
	asset_integrity_phase_completed = true


func _finish() -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
	if failures.is_empty():
		print("=== TEST_RESULT: PASS (%d checks) ===" % checks)
		get_tree().quit(0)
	else:
		print("=== TEST_RESULT: FAIL (%d checks, %d failed) ===" % [checks, failures.size()])
		for failure in failures:
			print("FAILED CHECK: " + failure)
		get_tree().quit(1)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures.append(label if detail.is_empty() else "%s (detail: %s)" % [label, detail])
		print("FAIL: " + label + ("" if detail.is_empty() else "  detail=" + detail))


func _read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _on_test_game_event(event_name: String, _payload: Dictionary) -> void:
	game_events.append(event_name)


func _on_test_system_event(event_name: String, _payload: Dictionary) -> void:
	system_events.append(event_name)


func _on_test_scene_changed(previous_scene_id: String, current_scene_id: String) -> void:
	switch_records.append("%s->%s" % [previous_scene_id, current_scene_id])


func _on_test_scene_change_failed(reason: String) -> void:
	failure_records.append(reason)
