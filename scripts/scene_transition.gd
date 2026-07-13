extends CanvasLayer

signal fade_in_finished

var overlay: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color.BLACK
	overlay.modulate.a = 0.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

func change_scene(path: String) -> void:
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween().set_ease(Tween.EASE_IN)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.3)
	await tween.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	_fade_in()

func reload_scene() -> void:
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween().set_ease(Tween.EASE_IN)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.3)
	await tween.finished
	get_tree().reload_current_scene()
	await get_tree().process_frame
	await get_tree().process_frame
	_fade_in()

func _fade_in() -> void:
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.3)
	await tween.finished
	fade_in_finished.emit()
