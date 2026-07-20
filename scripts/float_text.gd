class_name FloatText
extends RefCounted

## Small rising, fading text used for damage numbers and coin rewards.

static func spawn(parent: Node, pos: Vector2, text: String, color: Color, font_size: int = 16) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos + Vector2(-40, -20)
	label.size = Vector2(80, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 90
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.05))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 42.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(label.queue_free)

## Bigger, longer-lived variant for rewards worth calling out (e.g. rare drops)
## that would otherwise get lost among the constant damage/coin float text —
## punches in with a scale pop, holds, then rises and fades.
static func spawn_banner(parent: Node, pos: Vector2, text: String, color: Color, font_size: int = 24) -> void:
	var label := Label.new()
	label.text = text
	label.size = Vector2(200, 36)
	label.position = pos + Vector2(-100, -18)
	label.pivot_offset = Vector2(100, 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.05))
	label.add_theme_constant_override("outline_size", 6)
	label.scale = Vector2(0.3, 0.3)
	label.modulate.a = 0.0
	parent.add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(label, "scale", Vector2(1.25, 1.25), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.9)
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 50.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(label.queue_free)
