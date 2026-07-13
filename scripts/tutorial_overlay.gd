extends CanvasLayer

## Reusable first-launch tutorial layer: dims the screen except a spotlight
## cutout around a target rect, shows a callout bubble explaining the step,
## and lets the player either tap the real target through the cutout (when
## tap_to_continue is false) or tap anywhere to advance (when true). Always
## shows a "Skip Tutorial" button.

signal advanced
signal skipped

const MARGIN := 16.0
const RING_PAD := 10.0
const CALLOUT_MAX_WIDTH := 420.0

@onready var dim_top: ColorRect = $Dim/Top
@onready var dim_bottom: ColorRect = $Dim/Bottom
@onready var dim_left: ColorRect = $Dim/Left
@onready var dim_right: ColorRect = $Dim/Right
@onready var ring: Panel = $Ring
@onready var catcher: Button = $Catcher
@onready var callout: PanelContainer = $Callout
@onready var body_label: Label = $Callout/Margin/Box/BodyLabel
@onready var hint_label: Label = $Callout/Margin/Box/HintLabel
@onready var skip_button: Button = $SkipButton

var _ring_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Callers may add this CanvasLayer under a Node2D root (Main), which
	# breaks automatic theme inheritance from the Window — assign it
	# directly to our top-level Controls, same fix main.gd applies to $UI.
	var ui_theme := get_tree().root.theme
	if ui_theme:
		for child in get_children():
			if child is Control:
				child.theme = ui_theme
	catcher.pressed.connect(_on_catcher_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_last_rect = Rect2()

var _last_rect: Rect2

func show_step(text: String, target_rect: Rect2, tap_to_continue: bool) -> void:
	_last_rect = target_rect
	body_label.text = text
	hint_label.visible = tap_to_continue
	catcher.visible = tap_to_continue
	catcher.disabled = not tap_to_continue
	_apply_cutout(target_rect)
	_position_ring(target_rect)
	_position_callout(target_rect)
	_restart_pulse()

func _on_viewport_resized() -> void:
	if _last_rect.size != Vector2.ZERO:
		_apply_cutout(_last_rect)
		_position_ring(_last_rect)
		_position_callout(_last_rect)

func _apply_cutout(rect: Rect2) -> void:
	var vp := get_viewport().get_visible_rect().size
	dim_top.position = Vector2(0, 0)
	dim_top.size = Vector2(vp.x, max(rect.position.y, 0.0))
	dim_bottom.position = Vector2(0, rect.position.y + rect.size.y)
	dim_bottom.size = Vector2(vp.x, max(vp.y - (rect.position.y + rect.size.y), 0.0))
	dim_left.position = Vector2(0, rect.position.y)
	dim_left.size = Vector2(max(rect.position.x, 0.0), rect.size.y)
	dim_right.position = Vector2(rect.position.x + rect.size.x, rect.position.y)
	dim_right.size = Vector2(max(vp.x - (rect.position.x + rect.size.x), 0.0), rect.size.y)

func _position_ring(rect: Rect2) -> void:
	ring.position = rect.position - Vector2(RING_PAD, RING_PAD)
	ring.size = rect.size + Vector2(RING_PAD, RING_PAD) * 2.0

func _position_callout(rect: Rect2) -> void:
	var vp := get_viewport().get_visible_rect().size
	callout.custom_minimum_size = Vector2(min(CALLOUT_MAX_WIDTH, vp.x - MARGIN * 2.0), 0)
	await get_tree().process_frame
	var callout_size := callout.size
	var x: float = clamp(rect.get_center().x - callout_size.x * 0.5, MARGIN, vp.x - callout_size.x - MARGIN)
	var y: float
	if rect.get_center().y < vp.y * 0.5:
		y = rect.position.y + rect.size.y + MARGIN
	else:
		y = rect.position.y - callout_size.y - MARGIN
	callout.position = Vector2(x, clamp(y, MARGIN, vp.y - callout_size.y - MARGIN))

func _restart_pulse() -> void:
	if _ring_tween:
		_ring_tween.kill()
	ring.modulate.a = 1.0
	_ring_tween = create_tween().set_loops()
	_ring_tween.tween_property(ring, "modulate:a", 0.5, 0.5)
	_ring_tween.tween_property(ring, "modulate:a", 1.0, 0.5)

func _on_catcher_pressed() -> void:
	advanced.emit()

func _on_skip_pressed() -> void:
	skipped.emit()
