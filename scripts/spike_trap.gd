class_name SpikeTrap
extends Node2D

## Consumable: a spike pad dropped on the road. Damages every enemy standing
## on it in the same row on a fixed tick until it wears out.

const TICK_INTERVAL := 0.5
const RADIUS := 62.0

var row: int = 0
var damage_per_tick: int = 12
var lifetime: float = 8.0

var _tick: float = 0.0

func _ready() -> void:
	# Draw at z 0: an explicit negative z_index would sort the trap behind
	# the Background sprite. World's y_sort keeps walkers layered above it.
	var sprite := Sprite2D.new()
	sprite.texture = load("res://Png/Ui/AddonIcon8.png")
	sprite.scale = Vector2(0.62, 0.5)
	add_child(sprite)
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
