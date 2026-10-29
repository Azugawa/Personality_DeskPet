extends Node
## Screen-space motion, independent of the animation canvas.
const THROW_THRESHOLD := 2300.0
const MAX_THROW_SPEED := 2800.0

var input: PetInput
var sprite: Sprite2D
var mode := "idle"
var velocity := Vector2.ZERO
var position := Vector2.ZERO
var previous_mouse := Vector2.ZERO
var elapsed := 0.0
var textures: Dictionary = {}
var facing_right := false
var pose_image: Image
var cloth_grab := Vector2.ZERO
var pose_scales: Dictionary = {}
const STANDING_WIDTH := 200.284
# Head widths measured in source pixels, excluding cloth, limbs and motion trails.
const HELD_HEAD_WIDTH := 780.0
const PRONE_HEAD_WIDTH := 865.0
const FLIGHT_HEAD_WIDTHS := [245.0,233.0,256.0,244.0,250.0]
const LANDING_HEAD_WIDTHS := [250.0,250.0,270.0,270.0]
const GETUP_HEAD_WIDTHS := [350.0,350.0,352.0,342.0]

func setup(owner_input: PetInput) -> void:
	input = owner_input
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	input._character.add_child(sprite)
	sprite.visible = false
	var base := "res://assets/character/spirit/physics/"
	for key in ["held","prone"]: textures[key] = load(base+key+"/00.png")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base+"metadata.json"))
	cloth_grab = Vector2(meta.cloth_grab[0],meta.cloth_grab[1])
	var frames: Array = []
	var landing: Array = []
	var recovery: Array = []
	for i in 5: frames.append(load(base+"flight/%02d.png" % i))
	for i in 4: landing.append(load(base+"landing/%02d.png" % i))
	for i in 6: recovery.append(load(base+"getup/%02d.png" % i))
	recovery[0] = textures.prone
	textures["flight"] = frames
	textures["landing"] = landing
	textures["getup"] = recovery
	# Preserve the existing standing reference size. Other frames are scaled by
	# the same anatomical landmark, never by the entire pose/canvas width.
	var standing_texture: Texture2D = recovery.back()
	var reference_head_width := float(standing_texture.get_width())
	var idle_sprite := input._character.animated_body
	var idle_texture := idle_sprite.sprite_frames.get_frame_texture("idle_front",0)
	var idle_width := idle_texture.get_image().get_used_rect().size.x * idle_sprite.scale.x * input._character.body_root.scale.x
	var reference_scale := idle_width / standing_texture.get_width()
	var displayed_head_width := reference_head_width * reference_scale
	pose_scales[standing_texture] = reference_scale
	pose_scales[textures.held] = displayed_head_width / HELD_HEAD_WIDTH
	pose_scales[textures.prone] = displayed_head_width / PRONE_HEAD_WIDTH
	for i in frames.size(): pose_scales[frames[i]] = displayed_head_width / FLIGHT_HEAD_WIDTHS[i]
	for i in landing.size(): pose_scales[landing[i]] = displayed_head_width / LANDING_HEAD_WIDTHS[i]
	for i in GETUP_HEAD_WIDTHS.size(): pose_scales[recovery[i+1]] = displayed_head_width / GETUP_HEAD_WIDTHS[i]

func begin() -> void:
	if input.activity_controller.transitioning and mode == "idle": return
	input._state_machine.request_idle(ActionStateMachine.MANUAL)
	for id in ["desk", "chair", "computer"]:
		input.activity_controller._furniture.set_visible(id,false,false)
	input.activity_controller.current_activity = "idle"
	input.activity_controller.transitioning = true
	mode = "held"
	velocity = Vector2.ZERO
	previous_mouse = Vector2(DisplayServer.mouse_get_position())
	input._character.body_root.visible = false
	sprite.visible = true
	show_pose(textures.held)

func show_pose(texture: Texture2D) -> void:
	if sprite.texture != texture:
		sprite.texture = texture
		pose_image = texture.get_image()
	# Uniform X/Y scaling preserves anatomy in horizontal and upright poses.
	sprite.scale = Vector2.ONE * float(pose_scales[texture])
	sprite.position = Vector2(0,-texture.get_height() * sprite.scale.y / 2.0)
	sprite.flip_h = facing_right

func release() -> void:
	if mode != "held": return
	if velocity.length() < THROW_THRESHOLD:
		_finish_placement()
		return
	mode = "flight"
	position = Vector2(get_window().position)
	velocity = velocity.limit_length(MAX_THROW_SPEED)
	elapsed = 0

func _process(delta: float) -> void:
	if input == null: return
	if mode == "held":
		var mouse := Vector2(DisplayServer.mouse_get_position())
		var instantaneous := (mouse-previous_mouse)/maxf(delta,0.001)
		velocity = velocity.lerp(instantaneous,1.0-exp(-delta*24.0))
		previous_mouse = mouse
		if absf(instantaneous.x)>20: facing_right = instantaneous.x>0
		sprite.flip_h = facing_right
		# The top of the pulled cloth is the actual grab point, including mirroring.
		var local_grab := Vector2(sprite.texture.get_width()-1-cloth_grab.x if facing_right else cloth_grab.x,cloth_grab.y)-sprite.texture.get_size()/2
		var grab := get_viewport().get_final_transform() * sprite.get_global_transform_with_canvas() * local_grab
		get_window().position = DisplayServer.mouse_get_position()-Vector2i(grab)
		input._window_anchor = get_window().position
		input._screen_anchor = DisplayServer.mouse_get_position()
		if velocity.length() >= THROW_THRESHOLD:
			input._pressed = false
			release()
	elif mode == "flight":
		elapsed += delta
		velocity.y += 1500 * delta
		position += velocity * delta
		var area := Rect2(DisplayServer.screen_get_usable_rect(get_window().current_screen))
		var transform := get_viewport().get_final_transform() * sprite.get_global_transform_with_canvas()
		var bounds := transform * sprite.get_rect()
		var low := area.position-bounds.position
		var high := area.end-bounds.end
		if position.x < low.x or position.x > high.x:
			position.x = clampf(position.x,low.x,high.x)
			velocity.x *= -0.65
		if position.y < low.y:
			position.y = low.y
			velocity.y = absf(velocity.y)*0.65
		if position.y > high.y:
			position.y = high.y
			if absf(velocity.y)>280 and elapsed<4:
				velocity.y *= -0.4
				velocity.x *= 0.65
			else:
				mode = "landing"
				elapsed = 0
				show_pose(textures.landing[0])
		facing_right = velocity.x>0 if absf(velocity.x)>10 else facing_right
		if mode == "flight": show_pose(textures.flight[mini(int(elapsed*10),4)])
		get_window().position = Vector2i(position)
	elif mode == "landing":
		elapsed += delta
		show_pose(textures.landing[mini(int(elapsed*10),3)])
		if elapsed >= 0.4:
			mode = "prone"
			elapsed = 0
			show_pose(textures.prone)
	elif mode == "prone":
		elapsed += delta
		if elapsed > 2.5:
			mode = "getup"
			elapsed = 0
	elif mode == "getup":
		elapsed += delta
		show_pose(textures.getup[mini(int(elapsed*7),5)])
		if elapsed > 1.0:
			input.activity_controller.transitioning = false
			mode = "idle"
			sprite.visible = false
			input._character.body_root.visible = true
			input._character.play_idle("front")

func hit_test(point: Vector2) -> bool:
	if pose_image == null: return false
	var pixel := sprite.get_global_transform().affine_inverse()*point-sprite.get_rect().position
	if sprite.flip_h: pixel.x = pose_image.get_width()-1-pixel.x
	if not Rect2(Vector2.ZERO,pose_image.get_size()).has_point(pixel): return false
	return pose_image.get_pixelv(Vector2i(pixel)).a>0.2

func _finish_placement() -> void:
	# Keep the character's world anchor where it was placed. No gravity or
	# landing sequence applies to a normal release.
	velocity = Vector2.ZERO
	mode = "idle"
	elapsed = 0
	input.activity_controller.transitioning = false
	sprite.visible = false
	input._character.body_root.visible = true
	input._character.play_idle("front")

