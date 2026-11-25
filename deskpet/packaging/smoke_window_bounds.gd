extends SceneTree
## Window drag bounds: the pet must stay inside the taskbar-excluded work area.

const WindowBounds := preload("res://scripts/core/window_controller.gd")


func _initialize() -> void:
	var usable := Rect2i(0, 0, 1920, 1040)
	_assert_position(Vector2i(100, 1100), Vector2i(200, 200), usable, Vector2i(100, 840), "bottom edge stops at the taskbar")
	_assert_position(Vector2i(-50, -20), Vector2i(200, 200), usable, Vector2i(0, 0), "top-left corner")
	_assert_position(Vector2i(1900, 500), Vector2i(200, 200), usable, Vector2i(1720, 500), "right edge")
	_assert_position(Vector2i(500, 500), Vector2i(2200, 1200), usable, Vector2i(0, 0), "oversized window pins to top-left")

	var secondary := Rect2i(1920, 0, 1920, 1040)
	_assert_position(Vector2i(1900, 500), Vector2i(200, 200), secondary, Vector2i(1920, 500), "secondary monitor left edge")
	_assert_position(Vector2i(3700, 1100), Vector2i(200, 200), secondary, Vector2i(3640, 840), "secondary monitor taskbar")
	print("PASS window work-area bounds")
	quit()


func _assert_position(position: Vector2i, size: Vector2i, usable: Rect2i, expected: Vector2i, label: String) -> void:
	var actual := WindowBounds.clamp_rect_to_usable(position, size, usable)
	assert(actual == expected, "%s: expected %s, got %s" % [label, str(expected), str(actual)])
