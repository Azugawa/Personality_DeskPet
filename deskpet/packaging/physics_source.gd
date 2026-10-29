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
	for key in ["held", "prone"]:
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path("res://../asset_sources/spirit/animations/physics/" + key + ".png"))
		textures[key] = ImageTexture.create_from_image(image.get_region(image.get_used_rect()))
	var held_image: Image = textures.held.get_image()
	var found := false
	for y in held_image.get_height():
		var sum_x := 0.0
		var count := 0
		for x in held_image.get_width():
			var pixel := held_image.get_pixel(x,y)
			if pixel.a > 0.8 and pixel.r > 0.65:
				sum_x += x
				count += 1
		if count > 0:
			cloth_grab = Vector2(sum_x/count,y)
			found = true
			break
	if not found: cloth_grab = Vector2(held_image.get_width()*0.75,0)
	var sheet: Image = Image.load_from_file(ProjectSettings.globalize_path("res://../asset_sources/spirit/animations/physics/flight.png"))
	var frames: Array = []
	# Authored sheet has five flight poses above four landing poses.
	for rect in [Rect2i(0,0,335,490),Rect2i(335,0,335,490),Rect2i(670,0,370,490),Rect2i(1040,0,440,490),Rect2i(1480,0,389,490)]:
		var frame := sheet.get_region(rect)
		frames.append(ImageTexture.create_from_image(_extract_character(frame)))
	textures["flight"] = frames
	var landing: Array = []
	for rect in [Rect2i(0,490,440,353),Rect2i(440,490,450,353),Rect2i(890,490,450,353),Rect2i(1340,490,529,353)]:
		landing.append(ImageTexture.create_from_image(_extract_character(sheet.get_region(rect))))
	textures["landing"] = landing
	var rise: Image = Image.load_from_file(ProjectSettings.globalize_path("res://../asset_sources/spirit/animations/physics/getup.png"))
	var recovery: Array = [textures.prone]
	for index in [1,2,3,4]:
		var cell := rise.get_region(Rect2i((index%3)*512,(index/3)*512,512,512))
		recovery.append(ImageTexture.create_from_image(_extract_character(cell)))
	var standing: Image = Image.load_from_file(ProjectSettings.globalize_path("res://../asset_sources/spirit/animations/physics/standing.png"))
	# The source standing portrait has an opaque studio background. Flood only
	# connected outside pixels; white clothing remains enclosed by its outline.
	standing.convert(Image.FORMAT_RGBA8)
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var visited := PackedByteArray()
	visited.resize(standing.get_width()*standing.get_height())
	while not queue.is_empty():
		var point: Vector2i = queue.pop_back()
		if point.x<0 or point.y<0 or point.x>=standing.get_width() or point.y>=standing.get_height(): continue
		var i := point.y*standing.get_width()+point.x
		if visited[i]: continue
		visited[i]=1
		var color := standing.get_pixelv(point)
		if minf(color.r,minf(color.g,color.b))<0.55: continue
		standing.set_pixelv(point,Color.TRANSPARENT)
		for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]: queue.append(point+step)
	# Source watermark lies outside the character crop.
	standing = standing.get_region(Rect2i(350,40,1320,1940))
	recovery.append(ImageTexture.create_from_image(standing.get_region(standing.get_used_rect())))
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

static func _extract_character(cell: Image) -> Image:
	# A generated atlas can extend slightly beyond its nominal grid cells.
	# Extract the main connected sprite, not fragments of its neighbours.
	var width := cell.get_width()
	var height := cell.get_height()
	var seen := PackedByteArray()
	seen.resize(width*height)
	var largest := PackedInt32Array()
	for y in height:
		for x in width:
			var seed := y*width+x
			if seen[seed] or cell.get_pixel(x,y).a < 0.5: continue
			var component := PackedInt32Array([seed])
			seen[seed] = 1
			var cursor := 0
			while cursor < component.size():
				var index := component[cursor]
				cursor += 1
				var point := Vector2i(index%width,index/width)
				for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var next: Vector2i = point+step
					if next.x<0 or next.y<0 or next.x>=width or next.y>=height: continue
					var next_index := next.y*width+next.x
					if seen[next_index]: continue
					seen[next_index] = 1
					if cell.get_pixelv(next).a>=0.5: component.append(next_index)
			if component.size()>largest.size(): largest=component
	var clean := Image.create(width,height,false,Image.FORMAT_RGBA8)
	for index in largest:
		var point := Vector2i(index%width,index/width)
		clean.set_pixelv(point,cell.get_pixelv(point))
	return clean.get_region(clean.get_used_rect())
