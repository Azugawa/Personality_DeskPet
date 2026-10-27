class_name FurnitureManager
extends Node
## Owns independent furniture instances for the persistent pet world.
##
## It knows profiles and placements, but not the character state machine. The
## state machine asks this manager for seat/work anchors and toggles visibility.

signal furniture_toggled(furniture_id: String, is_visible: bool)
signal furniture_moved(furniture_id: String, target: Vector2)
signal furniture_ready(furniture_id: String)

const FURNITURE_SCENE := preload("res://scenes/props/furniture.tscn")

var last_error: String = ""

var _views: Dictionary = {}
var _parent: Node = null
var _exclusive_groups: Dictionary = {}


func setup(world_config: Dictionary, parent_node: Node) -> bool:
	last_error = ""
	_clear()
	_parent = parent_node
	if _parent == null:
		return _fail("Furniture parent is null.")
	var entries: Variant = world_config.get("furniture", [])
	if typeof(entries) != TYPE_ARRAY:
		return _fail("World config 'furniture' must be an array.")

	for entry_value in (entries as Array):
		if typeof(entry_value) != TYPE_DICTIONARY:
			return _fail("Furniture entry must be an object.")
		var entry: Dictionary = entry_value
		var furniture_id := str(entry.get("id", ""))
		var profile_path := str(entry.get("profile", ""))
		if furniture_id.is_empty() or profile_path.is_empty():
			return _fail("Furniture entries need id and profile.")
		if _views.has(furniture_id):
			return _fail("Duplicate furniture id '%s'." % furniture_id)
		if not FileAccess.file_exists(profile_path):
			return _fail("Furniture profile is missing for '%s': %s" % [furniture_id, profile_path])
		var profile := ConfigLoader.load_json(profile_path)
		if profile.is_empty():
			return _fail("Could not load furniture profile '%s': %s" % [profile_path, ConfigLoader.last_error])
		profile = profile.duplicate(true)
		profile["id"] = furniture_id
		if entry.has("direction"):
			profile["default_direction"] = str(entry.get("direction"))
		if entry.has("scale"):
			profile["scale"] = float(entry.get("scale"))

		var view := FURNITURE_SCENE.instantiate() as FurnitureView
		if view == null:
			return _fail("Could not instantiate furniture scene for '%s'." % furniture_id)
		_parent.add_child(view)
		view.name = "Furniture_%s" % furniture_id
		view.position = _read_vec2(entry.get("position"), Vector2.ZERO)
		if not view.setup(profile):
			last_error = view.last_error
			return _fail("Furniture '%s' setup failed: %s" % [furniture_id, view.last_error])
		view.set_visible_immediate(bool(entry.get("visible", true)))
		view.move_finished.connect(_on_view_move_finished)
		view.furniture_visibility_changed.connect(_on_view_visibility_changed)
		_views[furniture_id] = view
		var exclusive_group := str(entry.get("exclusive_group", ""))
		if not exclusive_group.is_empty():
			if not _exclusive_groups.has(exclusive_group):
				_exclusive_groups[exclusive_group] = []
			_exclusive_groups[exclusive_group].append(furniture_id)
		furniture_ready.emit(furniture_id)

	print("[FurnitureManager] Ready: %s" % str(_views.keys()))
	return true


func has_furniture(furniture_id: String) -> bool:
	return _views.has(furniture_id)


func get_view(furniture_id: String) -> FurnitureView:
	return _views.get(furniture_id)


func get_ids() -> Array:
	return _views.keys()


func is_visible(furniture_id: String) -> bool:
	var view: FurnitureView = _views.get(furniture_id)
	return view != null and view.visible


func set_visible(furniture_id: String, value: bool, animated: bool = true, duration: float = 0.24) -> bool:
	var view: FurnitureView = _views.get(furniture_id)
	if view == null:
		return false
	if value:
		_hide_exclusive_siblings(furniture_id, animated, duration)
	if animated:
		view.set_visible_animated(value, duration)
	else:
		view.set_visible_immediate(value)
	return true


func _hide_exclusive_siblings(furniture_id: String, animated: bool, duration: float = 0.24) -> void:
	for group_value in _exclusive_groups.keys():
		var ids: Array = _exclusive_groups[group_value]
		if not ids.has(furniture_id):
			continue
		for other_id_value in ids:
			var other_id := str(other_id_value)
			if other_id == furniture_id:
				continue
			var other: FurnitureView = _views.get(other_id)
			if other == null or not other.is_visible_target():
				continue
			if animated:
				other.set_visible_animated(false, duration)
			else:
				other.set_visible_immediate(false)


func toggle(furniture_id: String) -> bool:
	var view: FurnitureView = _views.get(furniture_id)
	if view == null:
		return false
	set_visible(furniture_id, not view.is_visible_target(), true)
	return true


func show_only(furniture_id: String, animated: bool = true) -> void:
	for id in _views.keys():
		set_visible(str(id), str(id) == furniture_id, animated)


func set_direction(furniture_id: String, direction: String) -> bool:
	var view: FurnitureView = _views.get(furniture_id)
	if view == null:
		return false
	return view.set_direction(direction)


func move_to(furniture_id: String, target: Vector2, duration: float = 0.35) -> bool:
	var view: FurnitureView = _views.get(furniture_id)
	if view == null:
		return false
	view.move_to(target, duration)
	return true


func get_approach_position(furniture_id: String) -> Vector2:
	var view: FurnitureView = _views.get(furniture_id)
	if view == null:
		return Vector2.ZERO
	return view.get_approach_position()


func get_anchor(furniture_id: String, anchor_name: String) -> Vector2:
	var view: FurnitureView = _views.get(furniture_id)
	if view == null:
		return Vector2.ZERO
	return view.get_anchor_position(anchor_name)


func find_closest_seat(from_position: Vector2) -> FurnitureView:
	var best: FurnitureView = null
	var best_distance := INF
	for view_value in _views.values():
		var view := view_value as FurnitureView
		if view == null or not view.visible or not view.has_anchor("seat"):
			continue
		var distance := from_position.distance_squared_to(view.get_anchor_position("seat"))
		if distance < best_distance:
			best = view
			best_distance = distance
	return best


func get_furniture_snapshot() -> Array:
	var result := []
	for furniture_id in _views.keys():
		var view: FurnitureView = _views[furniture_id]
		result.append({
			"id": furniture_id,
			"visible": view.visible,
			"direction": view.direction,
			"position": view.position,
			"has_seat": view.has_anchor("seat"),
			"has_work_surface": view.has_anchor("work_surface"),
		})
	return result


func _clear() -> void:
	for view_value in _views.values():
		var view := view_value as Node
		if is_instance_valid(view):
			if view.get_parent() != null:
				view.get_parent().remove_child(view)
			view.queue_free()
	_views.clear()
	_exclusive_groups.clear()


func _on_view_move_finished(furniture_id: String) -> void:
	var view: FurnitureView = _views.get(furniture_id)
	if view != null:
		furniture_moved.emit(furniture_id, view.position)


func _on_view_visibility_changed(furniture_id: String, is_visible: bool) -> void:
	furniture_toggled.emit(furniture_id, is_visible)


func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() != 2:
		return fallback
	return Vector2(float(array[0]), float(array[1]))


func _fail(message: String) -> bool:
	last_error = message
	push_error("[FurnitureManager] " + message)
	return false
