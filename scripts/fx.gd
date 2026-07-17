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

static func smoke_explosion(parent: Node, pos: Vector2, fx_scale: float = 0.3) -> void:
	_one_shot(parent, pos, [["fx", "res://Png/Smoke Explosion", 24.0, false]], fx_scale)

static func smoke_puff(parent: Node, pos: Vector2, fx_scale: float = 0.25) -> void:
	_one_shot(parent, pos, [["fx", "res://Png/Smoke", 20.0, false]], fx_scale)

static func smoke_spell(parent: Node, pos: Vector2, fx_scale: float = 0.2) -> void:
	_one_shot(parent, pos, [["fx", "res://Png/Smoke Spell", 20.0, false]], fx_scale)

## A persistent looping rift, used to mark where enemies emerge from off-screen
## (e.g. Hunt mode's MainArea, whose road just runs off the edge with nothing
## to visually explain the spawn). Unlike _one_shot(), this loops forever and
## is never auto-freed — the caller owns its lifetime via the returned node.
static func portal_loop(parent: Node, pos: Vector2, height: float, tint: Color = Color(0.55, 0.35, 0.95)) -> Node2D:
	var rift := Node2D.new()
	rift.position = pos
	rift.z_index = 3
	parent.add_child(rift)

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = AnimUtil.cached_frames([["fx", "res://Png/Chemical Smoke", 10.0, true]])
	sprite.scale = Vector2(0.6, height / 260.0)
	sprite.modulate = tint
	sprite.play("fx")
	rift.add_child(sprite)

	var glow := AnimatedSprite2D.new()
	glow.sprite_frames = AnimUtil.cached_frames([["fx", "res://Png/Smoke Spell", 14.0, true]])
	glow.scale = Vector2(0.45, height / 200.0)
	glow.modulate = Color(tint.r, tint.g, tint.b, 0.6)
	glow.play("fx")
	rift.add_child(glow)

	var tw := rift.create_tween().set_loops()
	tw.tween_property(rift, "scale", Vector2(1.08, 1.0), 1.1).from(Vector2(0.92, 1.0)).set_trans(Tween.TRANS_SINE)
	tw.tween_property(rift, "scale", Vector2(0.92, 1.0), 1.1).set_trans(Tween.TRANS_SINE)
	return rift

static func flash_hit(target: CanvasItem, base_color: Color = Color.WHITE) -> void:
	target.modulate = Color(3.0, 2.4, 2.4)
	var tw := target.create_tween()
	tw.tween_property(target, "modulate", base_color, 0.18)
