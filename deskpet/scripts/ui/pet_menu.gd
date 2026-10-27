class_name PetMenu
extends CanvasLayer
## Right-click activity menu for the persistent pet.
##
## The menu is data-driven: PetWorld supplies labels/enabled flags from
## config/activities.json. It does not mutate the character; selecting an entry
## only emits the activity id.

signal action_selected(activity_id: String)

var _popup: PopupMenu = null
var _ids: Array[String] = []


func _ready() -> void:
	layer = 110
	_popup = PopupMenu.new()
	_popup.name = "ActivityPopup"
	add_child(_popup)
	_popup.id_pressed.connect(_on_id_pressed)


func show_actions(entries: Array, viewport_position: Vector2) -> void:
	if _popup == null:
		return
	_popup.clear()
	_ids.clear()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var label := str(entry.get("label", entry.get("id", "?")))
		_popup.add_item(label, index)
		_ids.append(str(entry.get("id", "")))
		if not bool(entry.get("enabled", true)):
			_popup.set_item_disabled(index, true)
	if _ids.is_empty():
		return
	var window := get_window()
	var viewport_size := window.get_visible_rect().size
	var screen_position := window.position + Vector2i(
		int(clampf(viewport_position.x, 4.0, maxf(4.0, viewport_size.x - 220.0))),
		int(clampf(viewport_position.y, 4.0, maxf(4.0, viewport_size.y - 160.0)))
	)
	_popup.position = screen_position
	_popup.popup(Rect2i(screen_position, Vector2i(1, 1)))


func hide_menu() -> void:
	if _popup != null:
		_popup.hide()


func is_menu_visible() -> bool:
	return _popup != null and _popup.visible


func _on_id_pressed(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	action_selected.emit(_ids[index])
