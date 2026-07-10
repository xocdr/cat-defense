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
const REG_SCALE := 0.55
const BOSS_SCALE := 0.75

var wall: Wall = null            # assigned by main before add_child
var hp: int
var state: String = "walk"
var _attack_target: Node2D = null
var _attack_timer: float = 0.0
var _stop_jitter: float = 0.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

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
	anim.play("walk")
	anim.animation_finished.connect(_on_anim_finished)

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
