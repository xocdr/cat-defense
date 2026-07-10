class_name Cat
extends Node2D

## A merged defender sitting in the board grid. Appearance is driven by the
## merge level: every 4 levels advance to the next character folder
## (C1..C15), and the chevron badge (Up0..Up3) shows the step inside the
## current character band.

signal drag_started(cat: Cat)

const BulletScene := preload("res://scenes/Bullet.tscn")
const LEVELS_PER_CHARACTER := 4
const MAX_CHARACTER := 15
const BASE_DAMAGE := 8.0
const DAMAGE_GROWTH := 1.38     # per merge level
const FIRE_COOLDOWN := 1.1
const ATK_RANGE := 950.0
const SPRITE_SCALE := 0.75

var level: int = 1
var row: int = 0
var slot: Node2D = null          # the board Slot this cat currently occupies
var dragging: bool = false

var _cooldown: float = 0.0
var _target: Node2D = null

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

static func character_for_level(p_level: int) -> int:
	return clampi((p_level - 1) / LEVELS_PER_CHARACTER + 1, 1, MAX_CHARACTER)

static func damage_for_level(p_level: int) -> int:
	var char_index := character_for_level(p_level)
	var mult: float = GameState.cat_damage_multiplier(char_index)
	return int(round(BASE_DAMAGE * pow(DAMAGE_GROWTH, p_level - 1) * mult))

func _ready() -> void:
	add_to_group("cats")
	anim.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	anim.animation_finished.connect(_on_anim_finished)
	_build_badge()
	set_level(level)

func set_level(new_level: int) -> void:
	level = new_level
	var char_index := character_for_level(level)
	var base_dir := "res://Png/Characters/C%d" % char_index
	anim.sprite_frames = AnimUtil.cached_frames([
		["idle", base_dir.path_join("Idle"), 12.0, true],
		["shoot", base_dir.path_join("Shoot"), 20.0, false],
	])
	anim.play("idle")
	_update_badge()

func _process(delta: float) -> void:
	if dragging:
		return
	_cooldown -= delta
	if not is_instance_valid(_target) or _target.is_dead():
		_target = _find_target()
	if _target and _cooldown <= 0.0:
		_fire()
		_cooldown = FIRE_COOLDOWN

func _find_target() -> Node2D:
	var best: Node2D = null
	var best_d := ATK_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_dead() or e.row != row or e.global_position.x < global_position.x:
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best = e
			best_d = d
	return best

func _fire() -> void:
	anim.play("shoot")
	var muzzle_pos := global_position + Vector2(42, -10)
	Fx.muzzle_flash(get_parent(), muzzle_pos)
	var b = BulletScene.instantiate()
	get_parent().add_child(b)
	b.global_position = muzzle_pos
	b.setup(_target, damage_for_level(level), level)

func _on_anim_finished() -> void:
	if anim.animation == "shoot":
		anim.play("idle")

func set_dragging(on: bool) -> void:
	dragging = on
	z_index = 100 if on else 0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15) if on else Vector2.ONE, 0.08)

func is_dead() -> bool:
	return false

# ---------------------------------------------------------------- badge

var _badge_chevron: Sprite2D
var _badge_label: Label

func _build_badge() -> void:
	_badge_chevron = Sprite2D.new()
	_badge_chevron.position = Vector2(-34, -30)
	_badge_chevron.scale = Vector2(0.5, 0.5)
	add_child(_badge_chevron)
	_badge_label = Label.new()
	_badge_label.position = Vector2(-45, -14)
	_badge_label.size = Vector2(24, 18)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.add_theme_font_size_override("font_size", 13)
	_badge_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_badge_label.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.05))
	_badge_label.add_theme_constant_override("outline_size", 4)
	add_child(_badge_label)

func _update_badge() -> void:
	var step := (level - 1) % LEVELS_PER_CHARACTER
	_badge_chevron.texture = load("res://Png/Ui/Up%d.png" % step)
	_badge_label.text = str(level)
