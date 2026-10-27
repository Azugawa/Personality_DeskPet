extends Node
## Composition root for the desktop pet application.
##
## App-level concerns only: preview backdrop, optional floor guide, window mode,
## debug overlay and lifecycle of the persistent PetWorld. Character behaviour,
## furniture and state transitions live under PetWorld.

const APP_CONFIG_PATH := "res://config/app.json"
const DEBUG_OVERLAY_SCENE := preload("res://scenes/main/debug_overlay.tscn")

var app_config: Dictionary = {}
var desktop_mode: bool = false
var debug_overlay: CanvasLayer = null
var visual_profile: Dictionary = {}

@onready var backdrop_layer: CanvasLayer = $BackdropLayer
@onready var backdrop: ColorRect = $BackdropLayer/Backdrop
@onready var stage_guide: StageGuide = $BackdropLayer/StageGuide
@onready var pet_world: PetWorld = $PetWorld


func _ready() -> void:
	app_config = ConfigLoader.load_json(APP_CONFIG_PATH)
	if app_config.is_empty():
		push_error("[Main] app config could not be loaded; built-in defaults will be used. %s" % ConfigLoader.last_error)

	visual_profile = Pseudo3D.get_profile()
	if stage_guide.setup(visual_profile):
		stage_guide.visible = bool(_dictionary(app_config.get("preview", {})).get("show_floor_guide", false))
	else:
		push_warning("[Main] Preview floor guide failed: %s" % stage_guide.last_error)
	_apply_preview_config()
	desktop_mode = WindowController.is_desktop_mode_requested()
	set_desktop_mode(desktop_mode)

	if not pet_world.setup():
		push_error("[Main] PetWorld failed to start: %s" % pet_world.last_error)

	var overlay_enabled := bool(_dictionary(app_config.get("debug", {})).get("overlay", true))
	if overlay_enabled and not desktop_mode:
		debug_overlay = DEBUG_OVERLAY_SCENE.instantiate()
		if debug_overlay.has_method("bind_pet_world"):
			debug_overlay.bind_pet_world(pet_world)
		add_child(debug_overlay)

	print("[Main] Ready. desktop_mode=%s debug_overlay=%s world=%s" % [
		str(desktop_mode), str(debug_overlay != null), str(pet_world.world_config.get("world_id", ""))
	])


func set_desktop_mode(enabled: bool) -> void:
	desktop_mode = enabled
	backdrop_layer.visible = not enabled
	WindowController.apply(get_window(), app_config, enabled)
	if debug_overlay != null and is_instance_valid(debug_overlay):
		debug_overlay.visible = not enabled


func _apply_preview_config() -> void:
	var preview: Dictionary = _dictionary(app_config.get("preview", {}))
	backdrop.color = Color.from_string(str(preview.get("backdrop_color", "#141821")), Color(0.08, 0.09, 0.13, 1.0))


func _dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
