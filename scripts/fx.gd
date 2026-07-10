class_name Fx
extends RefCounted

## One-shot visual effects built from the PNG sequences in Png/.

static func _one_shot(parent: Node, pos: Vector2, defs: Array, fx_scale: float, z: int = 50) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = AnimUtil.cached_frames(defs)
	sprite.position = pos
	sprite.scale = Vector2(fx_scale, fx_scale)
	sprite.z_index = z
	parent.add_child(sprite)
	sprite.play("fx")
	sprite.animation_finished.connect(sprite.queue_free)
	return sprite

static func explosion(parent: Node, pos: Vector2, fx_scale: float = 0.22) -> void:
	_one_shot(parent, pos, [["fx", "res://Png/Explosion", 30.0, false]], fx_scale)

static func muzzle_flash(parent: Node, pos: Vector2) -> void:
	var sprite := _one_shot(parent, pos, [["fx", "res://Png/ShootFx", 45.0, false]], 0.3)
	sprite.offset = Vector2(100, 0)  # frames point right from the gun tip

static func flash_hit(target: CanvasItem) -> void:
	target.modulate = Color(3.0, 2.4, 2.4)
	var tw := target.create_tween()
	tw.tween_property(target, "modulate", Color.WHITE, 0.18)
