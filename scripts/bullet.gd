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
const DEMON_HIT_SFX := preload("res://sfx/bullets/explosion.mp3")

var target: Node2D
var damage: int = 10
var speed: float = 1200.0
var _poison_dps: float = 0.0
var _poison_duration: float = 0.0
var _rarity_tier: Rarity.Tier = Rarity.Tier.COMMON
var _has_fx: bool = false
var _sprite: Sprite2D
var _halo: Sprite2D
var _base_scale := Vector2.ONE
var _time: float = 0.0

## In-flight "juice" — a stretch/pulse/wobble on the bullet sprite itself
## plus a soft additive halo, both scaled up with rarity so a Demon God
## bullet visibly hums with energy while a Common one barely shimmers.
const MOTION_FX := {
	Rarity.Tier.COMMON: {
		"stretch": 0.06, "pulse_amp": 0.04, "pulse_freq": 5.0,
		"wobble_amp": 0.03, "wobble_freq": 4.0, "glow_alpha": 0.15, "glow_scale": 1.4,
	},
	Rarity.Tier.RARE: {
		"stretch": 0.09, "pulse_amp": 0.06, "pulse_freq": 6.0,
		"wobble_amp": 0.05, "wobble_freq": 5.0, "glow_alpha": 0.3, "glow_scale": 1.7,
	},
	Rarity.Tier.EPIC: {
		"stretch": 0.12, "pulse_amp": 0.08, "pulse_freq": 7.0,
		"wobble_amp": 0.07, "wobble_freq": 6.0, "glow_alpha": 0.45, "glow_scale": 2.0,
	},
	Rarity.Tier.LEGENDARY: {
		"stretch": 0.16, "pulse_amp": 0.1, "pulse_freq": 8.0,
		"wobble_amp": 0.09, "wobble_freq": 7.0, "glow_alpha": 0.6, "glow_scale": 2.4,
	},
	Rarity.Tier.DEMON_GOD: {
		"stretch": 0.22, "pulse_amp": 0.14, "pulse_freq": 9.0,
		"wobble_amp": 0.12, "wobble_freq": 8.0, "glow_alpha": 0.8, "glow_scale": 2.9,
	},
}

## Per-tier particle tuning. Common has no FX (baseline); each rarity above
## it gets a progressively flashier trail + impact burst so a glance at a
## bullet's trail tells you what merge tier fired it.
const TIER_FX := {
	Rarity.Tier.RARE: {
		"trail_amount": 10, "trail_lifetime": 0.25, "trail_spread": 15.0,
		"trail_vel_min": 8.0, "trail_vel_max": 25.0, "trail_scale_min": 0.2, "trail_scale_max": 0.45,
		"burst_amount": 0,
	},
	Rarity.Tier.EPIC: {
		"trail_amount": 16, "trail_lifetime": 0.3, "trail_spread": 18.0,
		"trail_vel_min": 10.0, "trail_vel_max": 30.0, "trail_scale_min": 0.25, "trail_scale_max": 0.55,
		"burst_amount": 12, "burst_lifetime": 0.3, "burst_vel_min": 40.0, "burst_vel_max": 100.0,
		"burst_scale_min": 0.3, "burst_scale_max": 0.6,
	},
	Rarity.Tier.LEGENDARY: {
		"trail_amount": 20, "trail_lifetime": 0.35, "trail_spread": 22.0,
		"trail_vel_min": 10.0, "trail_vel_max": 35.0, "trail_scale_min": 0.3, "trail_scale_max": 0.65,
		"burst_amount": 18, "burst_lifetime": 0.35, "burst_vel_min": 50.0, "burst_vel_max": 130.0,
		"burst_scale_min": 0.35, "burst_scale_max": 0.75,
	},
	Rarity.Tier.DEMON_GOD: {
		"trail_amount": 30, "trail_lifetime": 0.4, "trail_spread": 25.0,
		"trail_vel_min": 15.0, "trail_vel_max": 50.0, "trail_scale_min": 0.4, "trail_scale_max": 0.85,
		"burst_amount": 36, "burst_lifetime": 0.5, "burst_vel_min": 80.0, "burst_vel_max": 220.0,
		"burst_scale_min": 0.5, "burst_scale_max": 1.1,
		"glow": true, "embers": true, "shockwave": true,
		"aoe_radius": 70.0, "aoe_fraction": 0.3,
	},
}

static var _spark_cache: GradientTexture2D
static var _ring_cache: GradientTexture2D

static func _spark_texture() -> GradientTexture2D:
	if _spark_cache:
		return _spark_cache
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 16
	tex.height = 16
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_spark_cache = tex
	return tex

## Hollow ring gradient used for the Demon God impact shockwave.
static func _ring_texture() -> GradientTexture2D:
	if _ring_cache:
		return _ring_cache
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_ring_cache = tex
	return tex

func setup(t: Node2D, dmg: int, character: int = 1) -> void:
	target = t
	damage = dmg
	var tier := clampi((character - 1) / 5, 0, TIER_TEXTURES.size() - 1)
	_sprite = $Sprite2D
	_sprite.texture = load(TIER_TEXTURES[tier])
	_base_scale = _sprite.scale
	_rarity_tier = Rarity.tier_for_character(character)
	_has_fx = TIER_FX.has(_rarity_tier)
	var weapon := Cat.weapon_for_character(character)
	var poison_mult: float = weapon.get("poison_dps_mult", 0.0)
	_poison_dps = dmg * poison_mult
	_poison_duration = weapon.get("poison_duration", 0.0) if poison_mult > 0.0 else 0.0
	if _has_fx:
		_spawn_trail(Rarity.color_for_tier(_rarity_tier), TIER_FX[_rarity_tier])
	_spawn_halo(Rarity.color_for_tier(_rarity_tier), MOTION_FX[_rarity_tier])

## Soft additive glow sitting behind the sprite, pulsing in place with it —
## makes the bullet itself read as "energy" rather than a flat cutout.
func _spawn_halo(color: Color, motion: Dictionary) -> void:
	_halo = Sprite2D.new()
	_halo.texture = _spark_texture()
	_halo.modulate = Color(color.r, color.g, color.b, motion["glow_alpha"])
	_halo.z_index = -1
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo.material = glow_mat
	add_child(_halo)
	move_child(_halo, 0)

func _spawn_trail(color: Color, fx: Dictionary) -> void:
	var trail := GPUParticles2D.new()
	trail.texture = _spark_texture()
	trail.amount = fx["trail_amount"]
	trail.lifetime = fx["trail_lifetime"]
	trail.z_index = -1
	if fx.get("glow", false):
		var glow_mat := CanvasItemMaterial.new()
		glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		trail.material = glow_mat
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(-1, 0, 0)
	mat.spread = fx["trail_spread"]
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = fx["trail_vel_min"]
	mat.initial_velocity_max = fx["trail_vel_max"]
	mat.scale_min = fx["trail_scale_min"]
	mat.scale_max = fx["trail_scale_max"]
	mat.color = color
	trail.process_material = mat
	add_child(trail)
	if fx.get("embers", false):
		_spawn_ember_trail(color)

## Slow-rising embers drifting up off the Demon God bullet, layered behind
## the main spark trail for a "burning" silhouette instead of a flat streak.
func _spawn_ember_trail(color: Color) -> void:
	var embers := GPUParticles2D.new()
	embers.texture = _spark_texture()
	embers.amount = 14
	embers.lifetime = 0.7
	embers.z_index = -1
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = glow_mat
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(-0.3, -1, 0)
	mat.spread = 35.0
	mat.gravity = Vector3(0, -25.0, 0)
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 22.0
	mat.scale_min = 0.15
	mat.scale_max = 0.35
	mat.color = Color(color.r, min(color.g + 0.15, 1.0), color.b * 0.6, 1.0)
	embers.process_material = mat
	add_child(embers)

func _process(delta: float) -> void:
	if not is_instance_valid(target) or target.is_dead():
		queue_free()
		return
	_time += delta
	var dir: Vector2 = target.global_position - global_position
	var dist: float = dir.length()
	rotation = dir.angle()
	_update_motion_fx()
	if dist < 20.0:
		target.take_damage(damage)
		if _poison_dps > 0.0:
			target.apply_poison(_poison_dps, _poison_duration)
		_sfx_hit()
		if _has_fx and TIER_FX[_rarity_tier]["burst_amount"] > 0:
			_impact_burst(Rarity.color_for_tier(_rarity_tier), TIER_FX[_rarity_tier])
		if _has_fx and TIER_FX[_rarity_tier].has("aoe_radius"):
			_aoe_damage(TIER_FX[_rarity_tier]["aoe_radius"], TIER_FX[_rarity_tier]["aoe_fraction"])
		queue_free()
		return
	global_position += dir.normalized() * speed * delta

## Demon God bullets splash — everything nearby the direct hit takes a cut
## of the same damage, so its explosion reads as an AoE detonation instead
## of a single-target hit with extra sparkles.
func _aoe_damage(radius: float, fraction: float) -> void:
	var splash_damage := maxi(1, roundi(damage * fraction))
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == target or not is_instance_valid(e) or e.is_dead():
			continue
		if e.global_position.distance_to(global_position) <= radius:
			e.take_damage(splash_damage)

func _update_motion_fx() -> void:
	var motion: Dictionary = MOTION_FX[_rarity_tier]
	var pulse: float = 1.0 + sin(_time * motion["pulse_freq"]) * motion["pulse_amp"]
	_sprite.scale = Vector2(_base_scale.x * (1.0 + motion["stretch"]) * pulse, _base_scale.y * (1.0 - motion["stretch"] * 0.4) * pulse)
	_sprite.rotation = sin(_time * motion["wobble_freq"]) * motion["wobble_amp"]
	if is_instance_valid(_halo):
		var halo_pulse: float = motion["glow_scale"] * (1.0 + sin(_time * motion["pulse_freq"] * 1.3) * 0.15)
		_halo.scale = _base_scale * halo_pulse

func _impact_burst(color: Color, fx: Dictionary) -> void:
	var burst := GPUParticles2D.new()
	burst.texture = _spark_texture()
	burst.amount = fx["burst_amount"]
	burst.lifetime = fx["burst_lifetime"]
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.global_position = global_position
	if fx.get("glow", false):
		var glow_mat := CanvasItemMaterial.new()
		glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		burst.material = glow_mat
	var mat := ParticleProcessMaterial.new()
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = fx["burst_vel_min"]
	mat.initial_velocity_max = fx["burst_vel_max"]
	mat.scale_min = fx["burst_scale_min"]
	mat.scale_max = fx["burst_scale_max"]
	mat.color = color
	burst.process_material = mat
	get_parent().add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)
	if fx.get("shockwave", false):
		_spawn_shockwave(color)
	if fx.get("embers", false):
		_spawn_impact_embers(color)

## Expanding hollow ring, additive-blended so it reads as a hit of light
## rather than a flat circle — the visual signature of a Demon God kill.
func _spawn_shockwave(color: Color) -> void:
	var ring := Sprite2D.new()
	ring.texture = _ring_texture()
	ring.global_position = global_position
	ring.modulate = Color(color.r, color.g, color.b, 0.9)
	ring.scale = Vector2(0.15, 0.15)
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ring.material = glow_mat
	get_parent().add_child(ring)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.6, 1.6), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(ring.queue_free)

## A few embers that linger and drift upward after the main burst dissipates.
func _spawn_impact_embers(color: Color) -> void:
	var embers := GPUParticles2D.new()
	embers.texture = _spark_texture()
	embers.amount = 16
	embers.lifetime = 0.8
	embers.one_shot = true
	embers.explosiveness = 0.9
	embers.global_position = global_position
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = glow_mat
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 60.0
	mat.gravity = Vector3(0, -30.0, 0)
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 60.0
	mat.scale_min = 0.2
	mat.scale_max = 0.45
	mat.color = Color(color.r, min(color.g + 0.15, 1.0), color.b * 0.6, 1.0)
	embers.process_material = mat
	get_parent().add_child(embers)
	embers.emitting = true
	embers.finished.connect(embers.queue_free)

func _sfx_hit() -> void:
	if not GameState.sound_on:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = DEMON_HIT_SFX if _rarity_tier == Rarity.Tier.DEMON_GOD else HIT_SFX
	p.finished.connect(p.queue_free)
	get_parent().add_child(p)
	p.play()
