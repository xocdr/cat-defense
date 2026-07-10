class_name BoxingCat
extends Node2D

## Consumable: a boxing cat summoned onto the road. Enemies in its row stop
## and fight it (it joins the "blockers" group) while it punches back. It
## disappears when its health or its summon time runs out.

const PUNCH_INTERVAL := 0.6
const PUNCH_RANGE := 85.0

var row: int = 0
var hp: int = 250
var punch_damage: int = 25
var lifetime: float = 12.0

var _punch_timer: float = 0.0
var _expired: bool = false

var anim: AnimatedSprite2D

func _ready() -> void:
	add_to_group("blockers")
	anim = AnimatedSprite2D.new()
	anim.sprite_frames = AnimUtil.cached_frames([
		["idle", "res://Png/CatBoxing/Idle", 20.0, true],
		["attack", "res://Png/CatBoxing/Attack", 24.0, true],
	])
	anim.scale = Vector2(0.34, 0.34)
	add_child(anim)
	anim.play("idle")

func _process(delta: float) -> void:
	if _expired:
		return
	# Lifetime counts down in _process so it freezes with the pause menu.
	lifetime -= delta
	if lifetime <= 0.0:
		_expire()
		return
	_punch_timer -= delta
	var target := _find_enemy()
	anim.play("attack" if target else "idle")
	if target and _punch_timer <= 0.0:
		target.take_damage(punch_damage)
		_punch_timer = PUNCH_INTERVAL

func _find_enemy() -> Node2D:
	var best: Node2D = null
	var best_dx := PUNCH_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.row != row or e.is_dead():
			continue
		var dx: float = e.global_position.x - global_position.x
		if dx > -20.0 and dx < best_dx:
			best = e
			best_dx = dx
	return best

func take_damage(amount: int) -> void:
	hp -= amount
	Fx.flash_hit(anim)
	if hp <= 0:
		_expire()

func is_dead() -> bool:
	return _expired or hp <= 0

func _expire() -> void:
	if _expired:
		return
	_expired = true
	remove_from_group("blockers")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
