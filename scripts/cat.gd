class_name Cat
extends Node2D

## A merged defender sitting in the board grid. Appearance and power are
## driven directly by the cat's character identity (1..15, see Rarity for
## the tier each character belongs to).

signal swap_pressed(cat: Cat)

const BulletScene := preload("res://scenes/Bullet.tscn")
const DEMON_FIRE_SFX := preload("res://sfx/bullets/demon-god-bullet-fired.mp3")
const MAX_CHARACTER := 15
const BASE_DAMAGE := 6.0
const DAMAGE_GROWTH := 1.3     # per character; was mistakenly left at the old 1.38^4
                                 # (4-sub-levels-per-character) rate, which let a single
                                 # merge multiply damage up to ~48x and trivialized waves
const FIRE_COOLDOWN := 1.3
const ATK_RANGE := 500.0
const SPRITE_SCALE := 0.75
const VERTICAL_NUDGE := 26.0  # lifts the sprite (and its foot-level rarity aura) up, purely cosmetic

## Post-cap power stacking: once a cat reaches Demon God (the last character
## tier), merging two of them no longer changes its character, so instead it
## "ascends" — a permanent stat + visual escalation reusing the Up0..Up3
## chevron art as a stage badge, one stage per merge, capped at MAX_ASCENSION.
const MAX_ASCENSION := 4
const ASCENSION_DAMAGE_GROWTH := 1.25
const ASCENSION_BADGE_TEX := [
	"res://Png/Ui/Up0.png", "res://Png/Ui/Up1.png", "res://Png/Ui/Up2.png", "res://Png/Ui/Up3.png",
]

## Per-character weapon feel: same rough DPS (damage_mult / cooldown_mult stays
## near 1.0 x FIRE_COOLDOWN), but traded off between a single hard-hitting shot
## and many small rapid ones so different characters read as different guns
## rather than palette-swapped stat sticks. Cycles every 5 characters, so each
## rarity tier's 3 characters land on different archetypes.
## Toxic trades direct-hit damage for a poison DoT applied on impact
## (see Bullet.setup/Enemy.apply_poison): poison_dps_mult is a fraction of the
## bullet's own damage dealt per second over poison_duration seconds.
const WEAPON_ARCHETYPES := [
	{"name": "Pistol", "cooldown_mult": 1.0, "damage_mult": 1.0},
	{"name": "Shotgun", "cooldown_mult": 1.7, "damage_mult": 1.65},
	{"name": "Rifle", "cooldown_mult": 0.32, "damage_mult": 0.34},
	{"name": "Sniper", "cooldown_mult": 2.4, "damage_mult": 2.5},
	{"name": "Toxic", "cooldown_mult": 1.0, "damage_mult": 0.6, "poison_dps_mult": 0.5, "poison_duration": 3.0},
]

static func weapon_for_character(char_index: int) -> Dictionary:
	return WEAPON_ARCHETYPES[(char_index - 1) % WEAPON_ARCHETYPES.size()]

var character: int = 1
var row: int = 0
var slot: Node2D = null          # the board Slot this cat currently occupies
var dragging: bool = false
var ascension: int = 0

var _shot_cooldown: float = FIRE_COOLDOWN
var _cooldown: float = 0.0
var _target: Node2D = null
var _ascension_particles: GPUParticles2D = null
var _aura_tween: Tween = null

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var tier_aura: Sprite2D = $TierAura
@onready var ascension_badge: Sprite2D = $AscensionBadge
@onready var swap_button: TextureButton = $SwapButton

# Character idle-frame canvases aren't a uniform size across the art pack
# (e.g. C1-5 are 150x150 but C9-10 are 198x179), and AnimatedSprite2D
# centers on the raw canvas, not on the character's feet. Left uncorrected,
# taller-canvas characters (which land later, i.e. higher rarity) visibly
# float/sink in the slot square when a merge swaps the displayed character.
# Cache each character's foot-baseline offset (from its idle frame's opaque
# bounding box) once per character so every character's feet line up.
## Keyed only by char_index, not by equipped skin — fine while every skin shares
## its character's canvas size, but a future skin with a different idle-frame
## canvas would need this keyed by (char_index, skin_id) instead.
static var _foot_offset_cache: Dictionary = {}
static var _foot_reference: float = NAN

static func display_character(char_index: int) -> int:
	var highest := GameState.highest_owned_character()
	return mini(char_index, highest)

static func damage_for_character(char_index: int) -> int:
	var mult: float = GameState.cat_damage_multiplier(char_index)
	return int(round(BASE_DAMAGE * pow(DAMAGE_GROWTH, char_index - 1) * mult))

## This cat's actual per-shot damage, including its Demon God ascension
## stacking on top of the character-derived base damage, and its weapon
## archetype's damage trade-off against fire rate.
func current_damage() -> int:
	var weapon := weapon_for_character(character)
	return int(round(damage_for_character(character) * pow(ASCENSION_DAMAGE_GROWTH, ascension) * weapon["damage_mult"]))

func _ready() -> void:
	add_to_group("cats")
	anim.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	anim.animation_finished.connect(_on_anim_finished)
	tier_aura.position.y -= VERTICAL_NUDGE
	ascension_badge.position.y -= VERTICAL_NUDGE
	_start_aura_pulse()
	swap_button.visible = false
	swap_button.pressed.connect(func(): swap_pressed.emit(self))
	set_character(character)
	_refresh_ascension_visuals()

## True only for a Demon God tier cat that hasn't ascended yet (no chevron
## badge) — the condition under which the manual "Swap" merge button may show.
func is_swap_eligible() -> bool:
	return Rarity.tier_for_character(character) == Rarity.Tier.DEMON_GOD and ascension == 0

func show_swap_button() -> void:
	swap_button.visible = true

func hide_swap_button() -> void:
	swap_button.visible = false

func set_character(new_character: int) -> void:
	hide_swap_button()
	character = new_character
	var char_index := display_character(character)
	var skin_suffix := GameState.skin_dir_suffix(char_index, GameState.equipped_skin_for(char_index))
	var base_dir := "res://Png/Characters/C%d%s" % [char_index, skin_suffix]
	anim.sprite_frames = AnimUtil.cached_frames([
		["idle", base_dir.path_join("Idle"), 12.0, true],
		["shoot", base_dir.path_join("Shoot"), 20.0, false],
	])
	anim.play("idle")
	anim.offset.y = _foot_offset(char_index) - VERTICAL_NUDGE
	update_aura_color(char_index)
	_shot_cooldown = FIRE_COOLDOWN * weapon_for_character(character)["cooldown_mult"]
	_shot_cooldown *= GameState.cat_fire_rate_multiplier(character)

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
		_cooldown = _shot_cooldown

## Enemies walk from high x to low x, so the frontmost (most advanced,
## closest to the wall) enemy has the smallest x. Always re-picks the
## frontmost each frame instead of sticking with a previously chosen target,
## so a faster enemy that overtakes it gets priority.
##
## In Hunt mode, cats aren't confined to defending their own row — the board
## is a cross-shaped junction rather than parallel lanes, so any cat can hit
## any enemy within its attack range regardless of lane. Outside Hunt mode
## (the standard 5-row grid), a cat still only engages its own row.
func _find_target() -> Node2D:
	var any_row := GameState.hunt_mode
	var atk_range := ATK_RANGE * GameState.cat_range_multiplier(character)
	var best: Node2D = null
	var best_x := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_dead() or (not any_row and e.row != row) or e.global_position.x < global_position.x:
			continue
		if global_position.distance_to(e.global_position) > atk_range:
			continue
		if e.global_position.x < best_x:
			best = e
			best_x = e.global_position.x
	return best

func _fire() -> void:
	anim.play("shoot")
	var muzzle_pos := global_position + Vector2(42, -10)
	Fx.muzzle_flash(get_parent(), muzzle_pos)
	if Rarity.tier_for_character(character) == Rarity.Tier.DEMON_GOD:
		_sfx_fire()
	var b = BulletScene.instantiate()
	get_parent().add_child(b)
	b.global_position = muzzle_pos
	b.setup(_target, current_damage(), character)

	# Every cat fires a matched double-tap regardless of whether its character
	# has been gem-purchased — gating this on ownership made merged-but-unbought
	# characters do half the DPS of an identical bought one, a monetization
	# cliff unrelated to in-match progress.
	var b2 := BulletScene.instantiate()
	get_parent().add_child(b2)
	b2.global_position = muzzle_pos
	b2.setup(_target, current_damage(), character)
	b2.scale = Vector2(0.7, 0.7)
	var tw := b2.create_tween()
	tw.tween_property(b2, "scale", Vector2(0.55, 0.55), 0.3)

func _sfx_fire() -> void:
	if not GameState.sound_on:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = DEMON_FIRE_SFX
	p.global_position = global_position
	p.finished.connect(p.queue_free)
	get_parent().add_child(p)
	p.play()

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

## speed_mult > 1 pulses faster/wider, used to make an ascended Demon God's
## aura visibly more "charged up" the further it has ascended.
func _start_aura_pulse(speed_mult: float = 1.0) -> void:
	if _aura_tween:
		_aura_tween.kill()
	var base_scale := tier_aura.scale
	var peak := base_scale * (AURA_PULSE_SCALE + 0.05 * (speed_mult - 1.0))
	var duration := AURA_PULSE_DURATION / speed_mult
	_aura_tween = create_tween()
	_aura_tween.set_loops()
	_aura_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_aura_tween.tween_property(tier_aura, "scale", peak, duration)
	_aura_tween.tween_property(tier_aura, "scale", base_scale, duration)

## Sets this cat's Demon God ascension stage (0 = plain Demon God, up to
## MAX_ASCENSION), refreshing the chevron badge, aura heat/speed, and ambient
## spark particles to match — a low-key bump at stage 1, escalating toward a
## Super-Saiyan-style full glow at MAX_ASCENSION.
func set_ascension(level: int) -> void:
	ascension = clampi(level, 0, MAX_ASCENSION)
	_refresh_ascension_visuals()

func _refresh_ascension_visuals() -> void:
	hide_swap_button()
	if ascension <= 0:
		ascension_badge.visible = false
		tier_aura.modulate = Color.WHITE
		_start_aura_pulse(1.0)
		_set_ascension_particles(false)
		return
	ascension_badge.visible = true
	ascension_badge.texture = load(ASCENSION_BADGE_TEX[ascension - 1])
	var heat := 1.0 + 0.35 * ascension
	tier_aura.modulate = Color(heat, heat, heat, 1.0)
	_start_aura_pulse(1.0 + 0.25 * ascension)
	_set_ascension_particles(true)

## Continuous rising gold spark trail that grows denser/faster/brighter with
## each ascension stage, layered on top of the (already pulsing) tier aura.
func _set_ascension_particles(on: bool) -> void:
	if not on:
		if _ascension_particles:
			_ascension_particles.emitting = false
		return
	if _ascension_particles == null:
		_ascension_particles = GPUParticles2D.new()
		_ascension_particles.position = Vector2(0, -VERTICAL_NUDGE)
		_ascension_particles.z_index = 1
		var glow_mat := CanvasItemMaterial.new()
		glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_ascension_particles.material = glow_mat
		_ascension_particles.texture = Rarity.aura_texture(Rarity.Tier.DEMON_GOD)
		add_child(_ascension_particles)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 20.0
	mat.gravity = Vector3(0, -50.0 - 20.0 * ascension, 0)
	mat.initial_velocity_min = 18.0 + 8.0 * ascension
	mat.initial_velocity_max = 32.0 + 12.0 * ascension
	mat.scale_min = 0.06
	mat.scale_max = 0.1 + 0.025 * ascension
	mat.color = Color(1.0, 0.85, 0.3, 0.75)
	_ascension_particles.process_material = mat
	_ascension_particles.amount = 5 + 4 * ascension
	_ascension_particles.lifetime = 0.55
	_ascension_particles.emitting = true
