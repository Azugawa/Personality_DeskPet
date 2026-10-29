extends Node
## Crop the native window around visible art without changing character scale.
var world: Node2D
var pet_input: PetInput
var cached: Dictionary = {}
var scale_factor := 0.65
func _ready() -> void:
	process_priority = 100
	world = get_parent().get_node("PetWorld")
	pet_input = world.get_node("PetInput")
	get_window().content_scale_size = Vector2i.ZERO
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_viewport().canvas_transform = Transform2D(Vector2(scale_factor,0),Vector2(0,scale_factor),Vector2.ZERO)
func _process(_delta: float) -> void:
	if not world.visible: return
	var bounds := _bounds(world)
	if bounds.size == Vector2.ZERO: return
	bounds = bounds.grow(5)
	var viewport := get_viewport()
	var previous := viewport.canvas_transform.origin
	var next := -bounds.position*scale_factor
	var shift := Vector2i(previous-next)
	get_window().position += shift
	pet_input._window_anchor += shift
	if pet_input.physics != null: pet_input.physics.position += Vector2(shift)
	viewport.canvas_transform = Transform2D(Vector2(scale_factor,0),Vector2(0,scale_factor),next)
	get_window().size = Vector2i((bounds.size*scale_factor).ceil())
func _bounds(node: Node) -> Rect2:
	var result := Rect2()
	if node is CanvasItem and not node.is_visible_in_tree(): return result
	var texture: Texture2D
	var offset := Vector2.ZERO
	if node is AnimatedSprite2D and node.sprite_frames != null:
		texture = node.sprite_frames.get_frame_texture(node.animation,node.frame)
		offset = node.offset - (texture.get_size()/2 if node.centered else Vector2.ZERO)
	elif node is Sprite2D:
		texture = node.texture
		if texture != null: offset = node.offset - (texture.get_size()/2 if node.centered else Vector2.ZERO)
	if texture != null:
		if not cached.has(texture): cached[texture] = Rect2(texture.get_image().get_used_rect())
		var local: Rect2 = cached[texture]
		local.position += offset
		result = node.get_global_transform()*local
	for child in node.get_children():
		var part := _bounds(child)
		if part.size != Vector2.ZERO: result = part if result.size == Vector2.ZERO else result.merge(part)
	return result
