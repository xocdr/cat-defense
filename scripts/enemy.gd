class_name Enemy
extends Node2D

## A zombie walking left along its row. It stops to attack the wall (or a
## summoned blocker such as the boxing cat) and, once nothing blocks the way,
## keeps marching toward the left edge — crossing LOSE_X loses the match.

signal reached_end(enemy)
signal died(enemy)

@export var enemy_index: int = 1
@export var row: int = 0
@export var is_boss: bool = false
@export var speed: float = 45.0
@export var max_hp: int = 40
@export var damage: int = 8
@export var gold_reward: int = 10

const ATTACK_INTERVAL := 1.0
const WALL_STOP_X := 452.0
const BLOCKER_STOP_DISTANCE := 62.0
const LOSE_X := 70.0
const REG_SCALE := 0.65
const BOSS_SCALE := 0.85

# Enemy canvases aren't a uniform size across the art pack, and
# AnimatedSprite2D centers on the raw canvas rather than on the enemy's feet,
# so left uncorrected different enemy types visibly float/sink relative to
# their row's Y line (and relative to cats, whose feet ARE baseline-corrected
# in cat.gd — see VERTICAL_NUDGE there). Mirror that correction here so every
# enemy's feet — and the cats they're lined up against — sit on the same
# on-screen row line.
const VERTICAL_NUDGE_PX := 19.5  # matches cat.gd's on-screen nudge (26 * cat SPRITE_SCALE 0.75)

var wall: Wall = null            # assigned by main before add_child
var hp: int
var state: String = "walk"
var _attack_target: Node2D = null
var _attack_timer: float = 0.0
var _stop_jitter: float = 0.0
var _aura_tween: Tween = null

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var boss_aura: Sprite2D = $BossAura

static var _foot_offset_cache: Dictionary = {}
static var _foot_reference: float = NAN
static var _boss_aura_tex: GradientTexture2D = null

## Menacing red pulse, distinct from the cats' rarity auras, marking a wave
## boss out at a glance.
static func _boss_aura_texture() -> GradientTexture2D:
	if _boss_aura_tex:
		return _boss_aura_tex
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1.0, 0.15, 0.1, 0.85),
		Color(1.0, 0.15, 0.1, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 160
	tex.height = 160
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_boss_aura_tex = tex
	return tex

func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	_stop_jitter = randf_range(-8.0, 24.0)
	var base_dir := ("res://Png/Enemies/Enemy Boss %d" if is_boss else "res://Png/Enemies/Enemy Reg %d") % enemy_index
	anim.sprite_frames = AnimUtil.cached_frames([
		["walk", base_dir.path_join("Walk"), 24.0, true],
		["attack", base_dir.path_join("Attack"), 20.0, true],
		["dead", base_dir.path_join("Dead"), 40.0, false],
	])
	var s := BOSS_SCALE if is_boss else REG_SCALE
	anim.scale = Vector2(s, s)
	anim.offset.y = _foot_offset(base_dir) - VERTICAL_NUDGE_PX / s
	anim.play("walk")
	anim.animation_finished.connect(_on_anim_finished)
	if is_boss:
		boss_aura.texture = _boss_aura_texture()
		boss_aura.visible = true
		_start_aura_pulse()

const AURA_PULSE_SCALE := 1.15
const AURA_PULSE_DURATION := 0.7

func _start_aura_pulse() -> void:
	var base_scale := boss_aura.scale
	var peak := base_scale * AURA_PULSE_SCALE
	_aura_tween = create_tween()
	_aura_tween.set_loops()
	_aura_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_aura_tween.tween_property(boss_aura, "scale", peak, AURA_PULSE_DURATION)
	_aura_tween.tween_property(boss_aura, "scale", base_scale, AURA_PULSE_DURATION)

## Vertical offset (in unscaled texture pixels) that puts this enemy type's
## walk-frame feet on the same baseline as "Enemy Reg 1", regardless of how
## tall/padded its source canvas is. Mirrors Cat._foot_offset.
func _foot_offset(base_dir: String) -> float:
	if _foot_offset_cache.has(base_dir):
		return _foot_offset_cache[base_dir]
	if is_nan(_foot_reference):
		_foot_reference = _feet_from_center(AnimUtil.cached_frames([
			["walk", "res://Png/Enemies/Enemy Reg 1/Walk", 24.0, true],
		]))
	var offset := 0.0
	var feet_from_center := _feet_from_center(anim.sprite_frames)
	if not is_nan(feet_from_center):
		offset = _foot_reference - feet_from_center
	_foot_offset_cache[base_dir] = offset
	return offset

## Distance from a walk-frame texture's vertical center to the bottom of its
## opaque content ("feet"), in unscaled texture pixels. NAN if the frame has
## no opaque pixels (shouldn't happen for real enemy art).
static func _feet_from_center(sf: SpriteFrames) -> float:
	var tex := sf.get_frame_texture("walk", 0)
	if not tex:
		return NAN
	var used := tex.get_image().get_used_rect()
	if used.size.y <= 0:
		return NAN
	return (used.position.y + used.size.y) - tex.get_height() / 2.0

func _process(delta: float) -> void:
	match state:
		"walk":
			var blocker := _find_blocker()
			if blocker:
				state = "attack"
				_attack_target = blocker
				_attack_timer = ATTACK_INTERVAL * 0.5
				anim.play("attack")
			else:
				position.x -= speed * delta
				if position.x < LOSE_X:
					reached_end.emit(self)
		"attack":
			if not is_instance_valid(_attack_target) or _attack_target.is_dead():
				_attack_target = null
				state = "walk"
				anim.play("walk")
				return
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_attack_target.take_damage(damage)
				_attack_timer = ATTACK_INTERVAL

func _find_blocker() -> Node2D:
	# Summoned blockers (boxing cat) take priority; then the wall.
	for b in get_tree().get_nodes_in_group("blockers"):
		if b.row != row or b.is_dead():
			continue
		var dx: float = global_position.x - b.global_position.x
		if dx > 0.0 and dx < BLOCKER_STOP_DISTANCE:
			return b
	# Only block at the wall line itself: an enemy that already slipped past
	# a broken wall must not snap back to attack it after a repair.
	if wall and not wall.is_dead() \
			and global_position.x <= WALL_STOP_X + _stop_jitter \
			and global_position.x >= WALL_STOP_X - 40.0:
		return wall
	return null

func take_damage(amount: int) -> void:
	if state == "dead":
		return
	hp -= amount
	FloatText.spawn(get_parent(), global_position + Vector2(randf_range(-14, 14), -46), str(amount), Color(1, 1, 0.85), 15)
	_flash()
	if hp <= 0:
		state = "dead"
		z_index = -1
		anim.play("dead")
		if _aura_tween:
			_aura_tween.kill()
		boss_aura.visible = false
		died.emit(self)

func _flash() -> void:
	Fx.flash_hit(anim)

func is_dead() -> bool:
	return state == "dead"

func _on_anim_finished() -> void:
	if anim.animation == "dead":
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.35)
		tw.tween_callback(queue_free)
