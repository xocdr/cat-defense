class_name Bullet
extends Node2D

## Homing projectile fired by cats. The sprite upgrades with the shooter's
## merge level using the three bullet artboards in Png/Bullets.

const TIER_TEXTURES := [
	"res://Png/Bullets/Artboard 1.png",
	"res://Png/Bullets/Artboard 1 copy.png",
	"res://Png/Bullets/Artboard 1 copy 2.png",
]
const HIT_SFX := preload("res://sfx/bullet-hit.mp3")

var target: Node2D
var damage: int = 10
var speed: float = 800.0

func setup(t: Node2D, dmg: int, character: int = 1) -> void:
	target = t
	damage = dmg
	var tier := clampi((character - 1) / 5, 0, TIER_TEXTURES.size() - 1)
	$Sprite2D.texture = load(TIER_TEXTURES[tier])

func _process(delta: float) -> void:
	if not is_instance_valid(target) or target.is_dead():
		queue_free()
		return
	var dir: Vector2 = target.global_position - global_position
	var dist: float = dir.length()
	rotation = dir.angle()
	if dist < 20.0:
		target.take_damage(damage)
		_sfx_hit()
		queue_free()
		return
	global_position += dir.normalized() * speed * delta

func _sfx_hit() -> void:
	var p := AudioStreamPlayer2D.new()
	p.stream = HIT_SFX
	p.finished.connect(p.queue_free)
	get_parent().add_child(p)
	p.play()
