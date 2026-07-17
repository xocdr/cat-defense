extends ScrollContainer

const DRAG_THRESHOLD := 10.0

var _pressed := false
var _dragging := false
var _drag_start_pos := Vector2.ZERO
var _scroll_start := 0
var _press_active_button: BaseButton = null


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			_pressed = true
			_dragging = false
			_drag_start_pos = event.position
			_scroll_start = scroll_horizontal
			_press_active_button = _button_at(get_global_mouse_position())
		else:
			_end_drag()
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and _pressed):
		if not _pressed:
			return
		var delta_x: float = event.position.x - _drag_start_pos.x
		if not _dragging and absf(delta_x) > DRAG_THRESHOLD:
			_dragging = true
			if _press_active_button:
				_press_active_button.disabled = true
		if _dragging:
			scroll_horizontal = _scroll_start - int(delta_x)


func _end_drag() -> void:
	if _press_active_button:
		var btn := _press_active_button
		call_deferred("_restore_button", btn)
	_pressed = false
	_dragging = false
	_press_active_button = null


func _restore_button(btn: BaseButton) -> void:
	if is_instance_valid(btn):
		btn.disabled = false


func _button_at(pos: Vector2) -> BaseButton:
	for child in get_children():
		var found := _find_button_at(child, pos)
		if found:
			return found
	return null


func _find_button_at(node: Node, global_pos: Vector2) -> BaseButton:
	if node is Control:
		var ctrl := node as Control
		if ctrl.get_global_rect().has_point(global_pos):
			for child in ctrl.get_children():
				var found := _find_button_at(child, global_pos)
				if found:
					return found
			if ctrl is BaseButton and not (ctrl as BaseButton).disabled:
				return ctrl
	return null
