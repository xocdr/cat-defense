class_name Wall
extends Node2D

## The crate barricade between the cat grid and the road. The crates and the
## HP-bar frame are baked into every Area background at the same position, so
## this node only draws the *dynamic* parts on top: the draining HP fill and
## a dark overlay over the crates while the wall is broken.
##
## Screen-space rects below assume the background sprite maps original image
## pixels to screen via scale (0.598, 0.678) with the top-left at (0, 0),
## matching Main.tscn's Background node.

signal hp_changed(hp: int, max_hp: int)
signal broken
signal repaired

const BAR_BACK_RECT := Rect2(398, 182, 20, 360)
const BAR_INSET := 3.0
const CRATE_REGION := Rect2(521, 219, 122, 606)   # in Area*.png pixels
const BG_SCALE := Vector2(0.598, 0.678)

var max_hp: int = 300
var hp: int = 300

var _bar_fill: ColorRect
var _broken_overlay: Sprite2D

func _ready() -> void:
	var bar_back := ColorRect.new()
	bar_back.position = BAR_BACK_RECT.position
	bar_back.size = BAR_BACK_RECT.size
	bar_back.color = Color(0.10, 0.10, 0.11)
	bar_back.z_index = 5
	add_child(bar_back)

	_bar_fill = ColorRect.new()
	_bar_fill.z_index = 6
	add_child(_bar_fill)
	_update_bar()

## Called by main with the level's background texture so the broken overlay
## darkens the exact crates drawn on this level's art.
func setup_broken_overlay(bg_texture: Texture2D) -> void:
	_broken_overlay = Sprite2D.new()
	_broken_overlay.texture = bg_texture
	_broken_overlay.region_enabled = true
	_broken_overlay.region_rect = CRATE_REGION
	_broken_overlay.scale = BG_SCALE
	_broken_overlay.position = (CRATE_REGION.position + CRATE_REGION.size / 2.0) * BG_SCALE
	_broken_overlay.modulate = Color(0.25, 0.22, 0.22)
	_broken_overlay.z_index = 4
	_broken_overlay.visible = false
	add_child(_broken_overlay)

func set_max_hp(value: int) -> void:
	max_hp = value
	hp = value
	_update_bar()

func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	_update_bar()
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		_set_broken(true)
		broken.emit()

func repair_full() -> void:
	var was_broken := hp <= 0
	hp = max_hp
	_update_bar()
	hp_changed.emit(hp, max_hp)
	if was_broken:
		_set_broken(false)
		repaired.emit()

func is_dead() -> bool:
	return hp <= 0

func missing_hp() -> int:
	return max_hp - hp

func _set_broken(value: bool) -> void:
	if _broken_overlay:
		_broken_overlay.visible = value
	if value:
		Fx.explosion(self, (CRATE_REGION.position + CRATE_REGION.size / 2.0) * BG_SCALE, 0.3)

func _update_bar() -> void:
	var pct := float(hp) / float(max_hp) if max_hp > 0 else 0.0
	var inner_h := (BAR_BACK_RECT.size.y - BAR_INSET * 2.0) * pct
	_bar_fill.size = Vector2(BAR_BACK_RECT.size.x - BAR_INSET * 2.0, inner_h)
	_bar_fill.position = Vector2(
		BAR_BACK_RECT.position.x + BAR_INSET,
		BAR_BACK_RECT.position.y + BAR_BACK_RECT.size.y - BAR_INSET - inner_h)
	if pct > 0.5:
		_bar_fill.color = Color(0.55, 0.85, 0.15)
	elif pct > 0.25:
		_bar_fill.color = Color(0.95, 0.75, 0.15)
	else:
		_bar_fill.color = Color(0.90, 0.25, 0.15)
