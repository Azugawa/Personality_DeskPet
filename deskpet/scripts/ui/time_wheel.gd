class_name TimeWheel
extends Control
## Compact vertical value wheel with animated wheel/drag scrolling.

signal value_changed(value: int)

var min_value := 0
var max_value := 23
var value := 0
var item_height := 24.0
var visible_items := 3
var font_size := 18

var _display := 0.0
var _dragging := false
var _drag_y := 0.0
var _drag_display := 0.0
var _tween: Tween
var _font: FontFile


func _ready() -> void:
	_font = load("res://assets/fonts/pixel.ttf")
	if _font != null:
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	custom_minimum_size = Vector2(64, item_height * visible_items + 8)
	queue_redraw()


func setup(p_min: int, p_max: int, p_value: int) -> void:
	min_value = p_min
	max_value = p_max
	value = clampi(p_value, min_value, max_value)
	_display = float(value)
	queue_redraw()


func set_value(new_value: int, animate: bool = true) -> void:
	var target := clampi(new_value, min_value, max_value)
	value = target
	if _tween != null:
		_tween.kill()
		_tween = null
	if animate and is_inside_tree() and absf(_display - float(target)) > 0.001:
		_tween = create_tween()
		_tween.tween_method(_set_display, _display, float(target), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.finished.connect(func():
			_display = float(target)
			queue_redraw()
			value_changed.emit(target)
		)
	else:
		_display = float(target)
		queue_redraw()
		value_changed.emit(target)


func _set_display(next_display: float) -> void:
	_display = next_display
	queue_redraw()


func _step(delta: int) -> void:
	set_value(roundi(_display) + delta, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_step(1)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_step(-1)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _tween != null:
					_tween.kill()
					_tween = null
				_dragging = true
				_drag_y = event.position.y
				_drag_display = _display
				accept_event()
			elif _dragging:
				_dragging = false
				set_value(roundi(_display), true)
				accept_event()
			return
	if event is InputEventMouseMotion and _dragging:
		_display = clampf(_drag_display - (event.position.y - _drag_y) / item_height, min_value - 0.49, max_value + 0.49)
		queue_redraw()
		accept_event()


func _draw() -> void:
	if _font == null:
		return
	var center := size.y * 0.5
	draw_rect(Rect2(0, center - item_height * 0.55, size.x, item_height * 1.1), Color("d8ecff"))
	var first := int(floor(_display)) - 2
	for number in range(first, first + 5):
		if number < min_value or number > max_value:
			continue
		var y := center + (float(number) - _display) * item_height
		if absf(y - center) > size.y * 0.56:
			continue
		var alpha := 1.0 - minf(1.0, absf(y - center) / (size.y * 0.56))
		var color := Color("173763")
		color.a = alpha
		var text := str(number)
		var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var ascent := _font.get_ascent(font_size)
		var descent := _font.get_descent(font_size)
		var baseline := y + (ascent - descent) * 0.5
		draw_string(_font, Vector2((size.x - text_size.x) * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
