class_name Cat
extends Node2D

## A merged defender sitting in the board grid. Appearance and power are
## driven directly by the cat's character identity (1..15, see Rarity for
## the tier each character belongs to).

signal drag_started(cat: Cat)

const BulletScene := preload("res://scenes/Bullet.tscn")
const MAX_CHARACTER := 15
const BASE_DAMAGE := 6.0
const DAMAGE_GROWTH := 1.3     # per character; was mistakenly left at the old 1.38^4
                                 # (4-sub-levels-per-character) rate, which let a single
                                 # merge multiply damage up to ~48x and trivialized waves
const FIRE_COOLDOWN := 1.1
const ATK_RANGE := 950.0
const SPRITE_SCALE := 0.75
const VERTICAL_NUDGE := 26.0  # lifts the sprite (and its foot-level rarity aura) up, purely cosmetic

var character: int = 1
var row: int = 0
var slot: Node2D = null          # the board Slot this cat currently occupies
var dragging: bool = false

var _cooldown: float = 0.0
var _target: Node2D = null

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var tier_aura: Sprite2D = $TierAura

# Character idle-frame canvases aren't a uniform size across the art pack
# (e.g. C1-5 are 150x150 but C9-10 are 198x179), and AnimatedSprite2D
# centers on the raw canvas, not on the character's feet. Left uncorrected,
# taller-canvas characters (which land later, i.e. higher rarity) visibly
# float/sink in the slot square when a merge swaps the displayed character.
# Cache each character's foot-baseline offset (from its idle frame's opaque
# bounding box) once per character so every character's feet line up.
static var _foot_offset_cache: Dictionary = {}
static var _foot_reference: float = NAN

static func display_character(char_index: int) -> int:
	var highest := GameState.highest_owned_character()
	return mini(char_index, highest)

static func damage_for_character(char_index: int) -> int:
	var mult: float = GameState.cat_damage_multiplier(char_index)
	return int(round(BASE_DAMAGE * pow(DAMAGE_GROWTH, char_index - 1) * mult))

func _ready() -> void:
	add_to_group("cats")
	anim.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	anim.animation_finished.connect(_on_anim_finished)
	tier_aura.position.y -= VERTICAL_NUDGE
	_start_aura_pulse()
	set_character(character)

func set_character(new_character: int) -> void:
	character = new_character
	var char_index := display_character(character)
	var base_dir := "res://Png/Characters/C%d" % char_index
	anim.sprite_frames = AnimUtil.cached_frames([
		["idle", base_dir.path_join("Idle"), 12.0, true],
		["shoot", base_dir.path_join("Shoot"), 20.0, false],
	])
	anim.play("idle")
	anim.offset.y = _foot_offset(char_index) - VERTICAL_NUDGE
	update_aura_color(char_index)

## Vertical offset (in unscaled texture pixels) that puts this character's
## idle-frame feet on the same baseline as character 1's, regardless of how
## tall/padded its source canvas is.
func _foot_offset(char_index: int) -> float:
	if _foot_offset_cache.has(char_index):
		return _foot_offset_cache[char_index]
	if is_nan(_foot_reference):
		_foot_reference = _feet_from_center(AnimUtil.cached_frames([
			["idle", "res://Png/Characters/C1/Idle", 12.0, true],
		]))
	var offset := 0.0
	var feet_from_center := _feet_from_center(anim.sprite_frames)
	if not is_nan(feet_from_center):
		offset = _foot_reference - feet_from_center
	_foot_offset_cache[char_index] = offset
	return offset

## Distance from an idle frame texture's vertical center to the bottom of
## its opaque content ("feet"), in unscaled texture pixels. NAN if the
## frame has no opaque pixels (shouldn't happen for real character art).
static func _feet_from_center(sf: SpriteFrames) -> float:
	var tex := sf.get_frame_texture("idle", 0)
	if not tex:
		return NAN
	var used := tex.get_image().get_used_rect()
	if used.size.y <= 0:
		return NAN
	return (used.position.y + used.size.y) - tex.get_height() / 2.0

func _process(delta: float) -> void:
	if dragging:
		return
	_cooldown -= delta
	_target = _find_target()
	if _target and _cooldown <= 0.0:
		_fire()
		_cooldown = FIRE_COOLDOWN

## Enemies walk from high x to low x, so the frontmost (most advanced,
## closest to the wall) enemy in this cat's row has the smallest x. Always
## re-picks the frontmost each frame instead of sticking with a previously
## chosen target, so a faster enemy that overtakes it gets priority.
func _find_target() -> Node2D:
	var best: Node2D = null
	var best_x := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_dead() or e.row != row or e.global_position.x < global_position.x:
			continue
		if global_position.distance_to(e.global_position) > ATK_RANGE:
			continue
		if e.global_position.x < best_x:
			best = e
			best_x = e.global_position.x
	return best

func _fire() -> void:
	anim.play("shoot")
	var muzzle_pos := global_position + Vector2(42, -10)
	Fx.muzzle_flash(get_parent(), muzzle_pos)
	var b = BulletScene.instantiate()
	get_parent().add_child(b)
	b.global_position = muzzle_pos
	b.setup(_target, damage_for_character(character), character)

	if GameState.is_character_purchased(character):
		var b2 := BulletScene.instantiate()
		get_parent().add_child(b2)
		b2.global_position = muzzle_pos
		b2.setup(_target, damage_for_character(character), character)
		b2.scale = Vector2(0.7, 0.7)
		var tw := b2.create_tween()
		tw.tween_property(b2, "scale", Vector2(0.55, 0.55), 0.3)

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

# ---------------------------------------------------------------- rarity aura

func update_aura_color(char_index: int) -> void:
	var tier := Rarity.tier_for_character(char_index)
	tier_aura.texture = Rarity.aura_texture(tier)
	tier_aura.modulate = Color.WHITE

const AURA_PULSE_SCALE := 1.1
const AURA_PULSE_DURATION := 0.9

func _start_aura_pulse() -> void:
	var base_scale := tier_aura.scale
	var tw := create_tween()
	tw.set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(tier_aura, "scale", base_scale * AURA_PULSE_SCALE, AURA_PULSE_DURATION)
	tw.tween_property(tier_aura, "scale", base_scale, AURA_PULSE_DURATION)
