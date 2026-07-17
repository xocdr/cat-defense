class_name Wall
extends Node2D

## The crate barricade between the cat grid and the road. The crates and the
## HP-bar frame are baked into every Area background at the same position, so
## this node only draws the *dynamic* parts on top: the draining HP fill and
## a dark overlay over the crates while the wall is broken.
##
## crate_region/bar_rect/bg_scale are @export so a scene that inherits Main.tscn
## with a differently-laid-out barricade (e.g. HuntArea.tscn's castle gate)
## can just set them in the editor Inspector on its own Wall node instead of
## main.gd passing overrides in code. Area1..5's shared Main.tscn still passes
## overrides explicitly from AREA_BOARD_CONFIG (see main.gd), which simply
## reassigns these same fields at runtime.

signal hp_changed(hp: int, max_hp: int)
signal broken
signal repaired

const BAR_BACK_RECT := Rect2(398, 182, 20, 360)
const BAR_INSET := 3.0
const CRATE_REGION := Rect2(521, 219, 122, 606)   # in Area*.png pixels
const BG_SCALE := Vector2(0.598, 0.678)

@export var crate_region: Rect2 = CRATE_REGION
@export var bar_rect: Rect2 = BAR_BACK_RECT
@export var bg_scale: Vector2 = BG_SCALE
## When true, bar_rect is drained left-to-right instead of bottom-to-top —
## for areas like HuntArea whose HP bar sits flat under the HUD instead of
## standing beside a vertical crate barricade.
@export var bar_horizontal: bool = false
## Screen-x where an enemy in this area stops to attack the wall (see
## enemy.gd's WALL_STOP_X usage) — tuned per-Area since each background bakes
## its barricade art at a different position. Default matches Area1-5's
## shared wall; a scene with a differently-placed barricade (e.g. HuntArea's
## castle gate) overrides this in the editor Inspector alongside crate_region.
@export var attack_stop_x: float = 452.0

var max_hp: int = 300
var hp: int = 300

var _bar_back: ColorRect
var _bar_fill: ColorRect
var _broken_overlay: Sprite2D

func _ready() -> void:
	_bar_back = ColorRect.new()
	_bar_back.position = bar_rect.position
	_bar_back.size = bar_rect.size
	_bar_back.color = Color(0.10, 0.10, 0.11)
	_bar_back.z_index = 5
	add_child(_bar_back)

	_bar_fill = ColorRect.new()
	_bar_fill.z_index = 6
	add_child(_bar_fill)
	_update_bar()

## Repositions the HP-bar backing/fill for a background whose barricade art
## sits somewhere other than bar_rect's current value. Safe to call any time
## since it only touches the already-created bar nodes.
func set_bar_rect(rect: Rect2) -> void:
	bar_rect = rect
	_bar_back.position = rect.position
	_bar_back.size = rect.size
	_update_bar()

## Called by main with the level's background texture so the broken overlay
## darkens the exact crates drawn on this level's art. Region/scale override
## params are optional (null = keep whatever crate_region/bg_scale already
## are, i.e. this Wall's exported/inspector values).
func setup_broken_overlay(bg_texture: Texture2D, crate_region_override: Variant = null, bg_scale_override: Variant = null) -> void:
	if crate_region_override != null:
		crate_region = crate_region_override
	if bg_scale_override != null:
		bg_scale = bg_scale_override
	_broken_overlay = Sprite2D.new()
	_broken_overlay.texture = bg_texture
	_broken_overlay.region_enabled = true
	_broken_overlay.region_rect = crate_region
	_broken_overlay.scale = bg_scale
	_broken_overlay.position = (crate_region.position + crate_region.size / 2.0) * bg_scale
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
		Fx.explosion(self, (crate_region.position + crate_region.size / 2.0) * bg_scale, 0.3)
		Fx.smoke_puff(self, (crate_region.position + crate_region.size / 2.0) * bg_scale, 0.35)

func _update_bar() -> void:
	var pct := float(hp) / float(max_hp) if max_hp > 0 else 0.0
	if bar_horizontal:
		var inner_w := (bar_rect.size.x - BAR_INSET * 2.0) * pct
		_bar_fill.size = Vector2(inner_w, bar_rect.size.y - BAR_INSET * 2.0)
		_bar_fill.position = Vector2(bar_rect.position.x + BAR_INSET, bar_rect.position.y + BAR_INSET)
	else:
		var inner_h := (bar_rect.size.y - BAR_INSET * 2.0) * pct
		_bar_fill.size = Vector2(bar_rect.size.x - BAR_INSET * 2.0, inner_h)
		_bar_fill.position = Vector2(
			bar_rect.position.x + BAR_INSET,
			bar_rect.position.y + bar_rect.size.y - BAR_INSET - inner_h)
	if pct > 0.5:
		_bar_fill.color = Color(0.55, 0.85, 0.15)
	elif pct > 0.25:
		_bar_fill.color = Color(0.95, 0.75, 0.15)
	else:
		_bar_fill.color = Color(0.90, 0.25, 0.15)
