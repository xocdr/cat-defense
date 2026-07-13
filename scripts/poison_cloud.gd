class_name PoisonCloud
extends Node2D

## Consumable: a lingering toxic cloud dropped on the road. Damages every
## enemy standing in the same row on a fixed tick until it wears out.

const TICK_INTERVAL := 0.5
const RADIUS := 70.0

var row: int = 0
var damage_per_tick: int = 10
var lifetime: float = 8.0

var _tick: float = 0.0

func _ready() -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = AnimUtil.cached_frames([["fx", "res://Png/Poisonous Smoke", 12.0, true]])
	sprite.scale = Vector2(0.5, 0.5)
	add_child(sprite)
	sprite.play("fx")
	var tw := create_tween()
	tw.tween_interval(lifetime - 1.0)
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_INTERVAL
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.row == row and not e.is_dead() and absf(e.global_position.x - global_position.x) < RADIUS:
			e.take_damage(damage_per_tick)
