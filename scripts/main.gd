extends Node2D

## Match scene: merge-board defense. Buy cats onto the 5x2 grid, drag two of
## the same level together to merge them, and defend the crate wall against
## 10 waves of zombies. Losing = an enemy walks past the cat grid.

const CatScene := preload("res://scenes/Cat.tscn")
const SlotScene := preload("res://scenes/Slot.tscn")
const EnemyScene := preload("res://scenes/Enemy.tscn")
const TutorialOverlayScene := preload("res://scenes/TutorialOverlay.tscn")
const TUTORIAL_SLOT_SIZE := Vector2(70.0, 70.0)

# Board geometry, derived from the slot squares baked into the Area art
# (original pixels * background scale 0.598 / 0.678). Row Y positions are
# shared by every Area background; column layout and trash-cell placement
# differ per Area since each background bakes its own squares/trash icon.
# trash_row/trash_col >= 0 means the trash cell sits inside the occupant
# grid at that cell (that cell is skipped when spawning occupant slots);
# -1 means the trash icon is its own square, independent of the grid.
const ROW_Y := [199.8, 276.5, 354.2, 431.6, 508.5]
const AREA_BOARD_CONFIG := {
	1: {"cols": [78.9, 162.7, 245.8], "trash_pos": Vector2(62.2, 644.1), "trash_row": -1, "trash_col": -1},
	2: {"cols": [78.9, 162.7, 245.8], "trash_pos": Vector2(242.2, 603.4), "trash_row": -1, "trash_col": -1},
	3: {"cols": [78.9, 162.7, 245.8], "trash_pos": Vector2(66.4, 73.9), "trash_row": -1, "trash_col": -1},
	4: {"cols": [163.0, 246.0], "trash_pos": Vector2(163.0, 508.5), "trash_row": 4, "trash_col": 0},
	5: {"cols": [163.0, 246.0], "trash_pos": Vector2(163.0, 508.5), "trash_row": 4, "trash_col": 0},
}

const WAVE_SFX_PATHS := [
	"res://sfx/laughs sfx/evil-cat-laugh.mp3",
	"res://sfx/laughs sfx/cartoonlaugh1.mp3",
]
const MERGE_SFX_PATH := "res://sfx/lvlup-cat-meow.mp3"
const DEMON_GOD_SFX_PATH := "res://sfx/laughs sfx/evil-cat-laugh.mp3"
const PLACE_SFX_PATH := "res://sfx/cat-placed.mp3"
const WAVE_COMPLETE_SFX_PATH := "res://sfx/wave complete.mp3"
const LEVEL_COMPLETE_SFX_PATH := "res://sfx/level-complete.mp3"

const TEX_MUSIC_ON := preload("res://Png/Ui/BtnMusic.png")
const TEX_MUSIC_OFF := preload("res://Png/Ui/BtnMusicOff.png")
const TEX_SOUND_ON := preload("res://Png/Ui/BtnSound.png")
const TEX_SOUND_OFF := preload("res://Png/Ui/BtnSound Off.png")
const TEX_VIBRA_ON := preload("res://Png/Ui/BtnVibra.png")
const TEX_VIBRA_OFF := preload("res://Png/Ui/BtnVibra Off.png")
const WIN_WAVE := 10
const SUMMON_COST := 30
const START_COINS := 30
const DRAG_PICK_RADIUS := 55.0
const ITEM_MIN_X := 470.0
const ITEM_MAX_X := 1230.0
const ENEMY_SPAWN_X := 1340.0
const DROP_COIN_SFX_PATH := "res://sfx/drop-coin.mp3"
const BOSS_COIN_COUNT := 3
const COIN_DROP_CFG := {
	1: {"base": 0.75, "decay": 0.04, "floor": 0.30},
	2: {"base": 0.70, "decay": 0.04, "floor": 0.25},
	3: {"base": 0.65, "decay": 0.04, "floor": 0.22},
	4: {"base": 0.60, "decay": 0.05, "floor": 0.20},
	5: {"base": 0.55, "decay": 0.05, "floor": 0.18},
	6: {"base": 0.50, "decay": 0.05, "floor": 0.15},
	7: {"base": 0.45, "decay": 0.06, "floor": 0.12},
	8: {"base": 0.40, "decay": 0.06, "floor": 0.10},
}

const ITEM_DEFS := [
	{"id": "spikes", "icon": "res://Png/Ui/AddonIcon8.png"},
	{"id": "tnt", "icon": "res://Png/Ui/AddonIcon6.png"},
	{"id": "boxer", "icon": "res://Png/Ui/AddonIcon7.png"},
	{"id": "poison", "icon": "res://Png/Ui/AddonIcon9.png"},
]

var level_num: int = 1
var area_index: int = 1
var coins: int = START_COINS
var wave: int = 0
var best_character: int = 1    # highest cat character reached this match
var enemies_to_spawn: int = 0
var boss_to_spawn: bool = false
var spawn_timer: float = 0.0
var wave_active: bool = false
var break_pending: bool = false
var match_over: bool = false
var _cheat_buffer: String = ""
const CHEAT_CODE := "GREEDISGOOD"

var slots: Array[Slot] = []
var dragged_cat: Cat = null
var drag_origin: Slot = null
var armed_item: String = ""
var _active_swap_cat: Cat = null    # Demon God cat currently showing its Swap button
var swap_source_cat: Cat = null     # set once that button is pressed, awaiting a merge target tap
var _tutorial_overlay: CanvasLayer = null
var _wave_sfx_player: AudioStreamPlayer
var _wave_sfx_streams: Array[AudioStream] = []
var _wave_sfx_index: int = 0
var _merge_sfx_player: AudioStreamPlayer
var _place_sfx_player: AudioStreamPlayer
var _wave_complete_sfx_player: AudioStreamPlayer
var _level_complete_sfx_player: AudioStreamPlayer
var _drop_sfx_player: AudioStreamPlayer
var _demon_god_sfx_player: AudioStreamPlayer

@onready var background: Sprite2D = $Background
@onready var wall: Wall = $Wall
@onready var world: Node2D = $World
@onready var slots_container: Node2D = $Slots

@onready var coin_label: Label = $UI/TopBar/CoinBar/CoinLabel
@onready var wave_label: Label = $UI/TopBar/WaveBar/WaveLabel
@onready var settings_button: TextureButton = $UI/TopBar/SettingsButton
@onready var wave_banner: Label = $UI/WaveBanner

@onready var repair_button: TextureButton = $UI/BottomBar/RepairButton
@onready var repair_cost_label: Label = $UI/BottomBar/RepairButton/CostLabel
@onready var item_buttons: Array[TextureButton] = [
	$UI/BottomBar/Item0, $UI/BottomBar/Item1, $UI/BottomBar/Item2, $UI/BottomBar/Item3,
]

@onready var pause_panel: Control = $UI/PausePanel
@onready var music_toggle: TextureButton = $UI/PausePanel/ToggleBar/Toggles/MusicToggle
@onready var sound_toggle: TextureButton = $UI/PausePanel/ToggleBar/Toggles/SoundToggle
@onready var vibra_toggle: TextureButton = $UI/PausePanel/ToggleBar/Toggles/VibraToggle
@onready var pause_restart_button: TextureButton = $UI/PausePanel/RestartButton
@onready var resume_button: TextureButton = $UI/PausePanel/ResumeButton

@onready var lose_panel: Control = $UI/LosePanel
@onready var lose_restart_button: TextureButton = $UI/LosePanel/Panel/RestartButton
@onready var lose_home_button: TextureButton = $UI/LosePanel/Panel/HomeButton

@onready var win_panel: Control = $UI/WinPanel
@onready var win_bonus_label: Label = $UI/WinPanel/Panel/BonusBox/BonusLabel
@onready var win_cards_label: Label = $UI/WinPanel/Panel/CardsLabel
@onready var continue_button: TextureButton = $UI/WinPanel/Panel/ContinueButton

func _apply_ui_theme() -> void:
	# Main's root is a Node2D, so its "UI" CanvasLayer's Control children
	# never pick up get_tree().root.theme (Control only inherits a Window's
	# theme when every ancestor up to the Window is itself a Control) —
	# assign it directly to each top-level Control instead.
	var ui_theme := get_tree().root.theme
	if not ui_theme:
		return
	for child in $UI.get_children():
		if child is Control:
			child.theme = ui_theme

func _ready() -> void:
	randomize()
	_apply_ui_theme()
	GameState.set_bgm(GameState.BATTLE_BGM_PATH)
	level_num = GameState.selected_level
	_setup_level()
	_setup_panels()
	_spawn_slots()
	_setup_item_buttons()

	repair_button.pressed.connect(_on_repair_pressed)
	settings_button.pressed.connect(_on_pause_pressed)

	_wave_sfx_player = AudioStreamPlayer.new()
	for sfx_path in WAVE_SFX_PATHS:
		_wave_sfx_streams.append(load(sfx_path))
	_wave_sfx_player.stream = _wave_sfx_streams[0]
	add_child(_wave_sfx_player)

	_merge_sfx_player = AudioStreamPlayer.new()
	_merge_sfx_player.stream = load(MERGE_SFX_PATH)
	add_child(_merge_sfx_player)

	_place_sfx_player = AudioStreamPlayer.new()
	_place_sfx_player.stream = load(PLACE_SFX_PATH)
	add_child(_place_sfx_player)

	_demon_god_sfx_player = AudioStreamPlayer.new()
	_demon_god_sfx_player.stream = load(DEMON_GOD_SFX_PATH)
	add_child(_demon_god_sfx_player)

	_wave_complete_sfx_player = AudioStreamPlayer.new()
	_wave_complete_sfx_player.stream = load(WAVE_COMPLETE_SFX_PATH)
	add_child(_wave_complete_sfx_player)

	_level_complete_sfx_player = AudioStreamPlayer.new()
	_level_complete_sfx_player.stream = load(LEVEL_COMPLETE_SFX_PATH)
	add_child(_level_complete_sfx_player)

	_drop_sfx_player = AudioStreamPlayer.new()
	_drop_sfx_player.stream = load(DROP_COIN_SFX_PATH)
	add_child(_drop_sfx_player)

	_refresh_hud()
	_start_wave()

	if not GameState.tutorial_seen and GameState.tutorial_step >= 1:
		call_deferred("_start_main_tutorial")

func _setup_level() -> void:
	area_index = (level_num - 1) % 5 + 1
	background.texture = load("res://Png/Area/Area%d.png" % area_index)
	coins = START_COINS
	wall.set_max_hp(300 + 150 * (level_num - 1))
	wall.setup_broken_overlay(background.texture)
	wall.hp_changed.connect(func(_hp, _max): _refresh_hud())

func _setup_panels() -> void:
	for panel in [pause_panel, lose_panel, win_panel]:
		panel.visible = false
		panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_restart_button.pressed.connect(_on_restart_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	lose_restart_button.pressed.connect(_on_restart_pressed)
	lose_home_button.pressed.connect(_on_home_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	music_toggle.pressed.connect(_on_toggle.bind("music"))
	sound_toggle.pressed.connect(_on_toggle.bind("sound"))
	vibra_toggle.pressed.connect(_on_toggle.bind("vibra"))
	_refresh_toggle_textures()

# ---------------------------------------------------------------- board

func _spawn_slots() -> void:
	var cfg: Dictionary = AREA_BOARD_CONFIG[area_index]
	var cols: Array = cfg["cols"]
	for r in range(ROW_Y.size()):
		for c in range(cols.size()):
			if r == cfg["trash_row"] and c == cfg["trash_col"]:
				continue
			var slot: Slot = SlotScene.instantiate()
			slot.row = r
			slot.col = c
			slot.is_trash = false
			slot.position = Vector2(cols[c], ROW_Y[r])
			slots_container.add_child(slot)
			slots.append(slot)

	var trash: Slot = SlotScene.instantiate()
	trash.row = -1
	trash.col = -1
	trash.is_trash = true
	trash.position = cfg["trash_pos"]
	slots_container.add_child(trash)
	slots.append(trash)

const MAX_BOARD_SLOTS := 15  # Area 1/2's 3-col layout — the capacity wave difficulty is tuned around

## Areas 4/5 hold only 9-10 board slots vs. Area 1/2/3's 15 (see
## AREA_BOARD_CONFIG), purely an artifact of which background art a level
## reuses. Enemy HP scaling is tuned against the 15-slot baseline, so it's
## scaled down proportionally on smaller boards — otherwise those levels get
## far less achievable cat DPS but face the same enemy toughness as a level
## with a full board, producing wild difficulty swings between levels that
## share the same wave-scaling formula.
func _board_capacity_factor() -> float:
	var cfg: Dictionary = AREA_BOARD_CONFIG[area_index]
	var total: int = cfg["cols"].size() * ROW_Y.size()
	if cfg["trash_row"] >= 0:
		total -= 1
	return float(total) / float(MAX_BOARD_SLOTS)

func _free_slots() -> Array[Slot]:
	var free: Array[Slot] = []
	for s in slots:
		if s.is_free():
			free.append(s)
	return free

func _slot_at(pos: Vector2) -> Slot:
	var best: Slot = null
	var best_d := DRAG_PICK_RADIUS
	for s in slots:
		var d: float = s.position.distance_to(pos)
		if d < best_d:
			best = s
			best_d = d
	return best

# ---------------------------------------------------------------- buying

const SUMMON_PITY_CHANCE := 0.55

func summon_character() -> int:
	return _random_character_in_tier(Rarity.Tier.COMMON)

## Picks a random character within `tier`. Merging (and buying) requires an
## exact character match, not just a tier match, so the roll is weighted
## toward characters already on the board (a "pity" pull) — otherwise
# smaller boards (fewer slots to simultaneously hold candidate duplicates,
# e.g. the 9/10-slot Area 4/5 layouts vs. Area 1/2/3's 15) suffer far worse
# merge odds than bigger boards for purely layout reasons, and tiers past
# COMMON have no other source of duplicates at all once summons stop
# landing there.
func _random_character_in_tier(tier: Rarity.Tier) -> int:
	var lo := Rarity.first_character_for_tier(tier)
	var hi := Rarity.last_character_for_tier(tier)
	if randf() < SUMMON_PITY_CHANCE:
		var on_board: Array[int] = []
		for s in slots:
			if s.occupant and s.occupant.character >= lo and s.occupant.character <= hi:
				on_board.append(s.occupant.character)
		if not on_board.is_empty():
			return on_board[randi() % on_board.size()]
	return randi_range(lo, hi)

func _buy_at_slot(slot: Slot) -> void:
	if match_over:
		return
	if coins < SUMMON_COST:
		_flash_deny_slot(slot)
		return
	coins -= SUMMON_COST
	_place_new_cat(slot, summon_character())
	_refresh_hud()
	if _tutorial_overlay and TutorialSteps.STEPS[GameState.tutorial_step]["target"] == "buy_slot":
		_on_tutorial_advanced()

func _place_new_cat(slot: Slot, character: int) -> void:
	var cat: Cat = CatScene.instantiate()
	cat.character = character
	cat.row = slot.row
	cat.slot = slot
	cat.position = slot.position
	cat.swap_pressed.connect(_on_cat_swap_pressed)
	world.add_child(cat)
	slot.occupant = cat
	_record_character(character)
	if GameState.sound_on:
		_place_sfx_player.play()
	cat.scale = Vector2(0.2, 0.2)
	var tw := cat.create_tween()
	tw.tween_property(cat, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _record_character(character: int) -> void:
	if character > best_character:
		best_character = character
		GameState.record_merge_character(character)

func sell_value(character: int) -> int:
	return 10 + 20 * character

# ---------------------------------------------------------------- drag & merge

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.unicode > 0 and event.pressed and not event.echo:
		_cheat_buffer += char(event.unicode).to_upper()
		var start := maxi(0, _cheat_buffer.length() - CHEAT_CODE.length())
		_cheat_buffer = _cheat_buffer.substr(start)
		if _cheat_buffer == CHEAT_CODE:
			_cheat_buffer = ""
			coins += 99999999
			_refresh_hud()
			FloatText.spawn(world, Vector2(640, 200), "+99,999,999", Color(1, 0.85, 0.3), 28)
		return
	if event.is_action_pressed("ui_cancel"):
		if not match_over and not win_panel.visible and not lose_panel.visible:
			if pause_panel.visible:
				_on_resume_pressed()
			else:
				_on_pause_pressed()
		return
	if match_over or get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_press(event.position)

## While a cat is being dragged, motion and release are handled here (before
## Control nodes) so dropping over a UI button still resolves the drag.
func _input(event: InputEvent) -> void:
	if dragged_cat == null:
		return
	if get_tree().paused:
		_cancel_drag()
		return
	if event is InputEventMouseMotion:
		dragged_cat.position = event.position
		_update_drag_highlight(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_on_release(event.position)
		get_viewport().set_input_as_handled()

## Aborts an in-flight drag, snapping the cat back to its slot. Used when the
## game pauses or ends mid-drag, since the mouse release may never arrive.
func _cancel_drag() -> void:
	_cancel_swap_pick()
	if dragged_cat == null:
		return
	dragged_cat.set_dragging(false)
	dragged_cat.position = drag_origin.position
	dragged_cat = null
	drag_origin = null
	_clear_highlights()

## Dismisses any active/pending Demon God Swap button state without side effects.
func _cancel_swap_pick() -> void:
	swap_source_cat = null
	if _active_swap_cat:
		_active_swap_cat.hide_swap_button()
		_active_swap_cat = null

func _on_cat_swap_pressed(cat: Cat) -> void:
	cat.hide_swap_button()
	_active_swap_cat = null
	swap_source_cat = cat

## Resolves the second tap of a Demon God Swap-merge: finds the nearest
## occupied slot to `pos` and, if it holds another Demon God cat, merges them
## into the next ascension stage regardless of their specific character
## (bypassing the strict same-character `_can_merge` rule used for drags).
## Any other tap (empty space, the source cat itself, a non-Demon-God cat)
## silently cancels the pick.
func _handle_swap_pick(pos: Vector2) -> void:
	var source := swap_source_cat
	swap_source_cat = null
	if source == null or not is_instance_valid(source):
		return
	var best: Cat = null
	var best_d := DRAG_PICK_RADIUS
	for s in slots:
		if s.occupant and s.position.distance_to(pos) < best_d:
			best = s.occupant
			best_d = s.position.distance_to(pos)
	if best == null or best == source:
		return
	if Rarity.tier_for_character(best.character) == Rarity.Tier.DEMON_GOD:
		_merge_cats(source, source.slot, best)

func _on_press(pos: Vector2) -> void:
	if swap_source_cat != null:
		_handle_swap_pick(pos)
		return
	if dragged_cat != null:
		return
	if armed_item != "":
		_try_place_item(pos)
		return
	for c in get_tree().get_nodes_in_group("coin_pickups"):
		if not is_instance_valid(c):
			continue
		if c.global_position.distance_to(pos) < DRAG_PICK_RADIUS:
			c.collect()
			return
	if _active_swap_cat:
		_active_swap_cat.hide_swap_button()
		_active_swap_cat = null
	var best: Cat = null
	var best_d := DRAG_PICK_RADIUS
	for s in slots:
		if s.occupant and s.position.distance_to(pos) < best_d:
			best = s.occupant
			best_d = s.position.distance_to(pos)
	if best:
		dragged_cat = best
		drag_origin = best.slot
		best.set_dragging(true)
		return
	var slot := _slot_at(pos)
	if slot and slot.is_free():
		_buy_at_slot(slot)

func _on_release(pos: Vector2) -> void:
	if not dragged_cat:
		return
	var cat := dragged_cat
	dragged_cat = null
	cat.set_dragging(false)
	_clear_highlights()
	var slot := _slot_at(pos)
	if slot == null or slot == drag_origin:
		_return_to_origin(cat)
		_handle_tap_in_place(cat)
	elif slot.is_trash:
		_sell_cat(cat)
	elif slot.occupant == null:
		_move_cat(cat, slot)
	elif _can_merge(cat, slot.occupant):
		_merge_cats(cat, drag_origin, slot.occupant)
	else:
		_swap_cats(cat, slot.occupant)
	drag_origin = null

## Toggles a Demon God cat's Swap button when it's released back on its own
## slot (a tap-in-place, whether from a genuine tap or a drag that snapped
## back to origin) — only one cat's button is shown at a time.
func _handle_tap_in_place(cat: Cat) -> void:
	if _active_swap_cat == cat:
		cat.hide_swap_button()
		_active_swap_cat = null
		return
	if _active_swap_cat:
		_active_swap_cat.hide_swap_button()
		_active_swap_cat = null
	if cat.is_swap_eligible():
		cat.show_swap_button()
		_active_swap_cat = cat

func _return_to_origin(cat: Cat) -> void:
	cat.position = drag_origin.position

func _sell_cat(cat: Cat) -> void:
	var refund := sell_value(cat.character)
	coins += refund
	FloatText.spawn(world, cat.position, "+%d" % refund, Color(1, 0.85, 0.3), 18)
	drag_origin.occupant = null
	cat.queue_free()
	_refresh_hud()

func _move_cat(cat: Cat, slot: Slot) -> void:
	drag_origin.occupant = null
	slot.occupant = cat
	cat.slot = slot
	cat.row = slot.row
	cat.position = slot.position
	if GameState.sound_on:
		_place_sfx_player.play()

## Strict merge rule: only two cats of the exact same character AND exact
## same tier may merge. Since a character deterministically maps to one tier
## (Rarity.tier_for_character), matching character already implies matching
## tier, but both are checked explicitly to keep the rule unambiguous.
func _can_merge(a: Cat, b: Cat) -> bool:
	if a.character != b.character:
		return false
	return Rarity.tier_for_character(a.character) == Rarity.tier_for_character(b.character)

func _merge_cats(dragged: Cat, dragged_slot: Slot, kept: Cat) -> void:
	dragged_slot.occupant = null
	dragged.queue_free()
	if GameState.sound_on:
		_merge_sfx_player.play()
	var current_tier := Rarity.tier_for_character(kept.character)
	var new_character := kept.character
	var is_tier_up := current_tier < Rarity.Tier.DEMON_GOD
	if is_tier_up:
		var next_tier: Rarity.Tier = current_tier + 1
		new_character = _random_character_in_tier(next_tier)
	kept.set_character(new_character)
	_record_character(new_character)
	var new_tier := Rarity.tier_for_character(new_character)
	Fx.smoke_spell(world, kept.position, 0.14)
	_spawn_merge_fx(kept.position, new_tier)
	Fx.flash_hit(kept)
	FloatText.spawn(world, kept.position + Vector2(0, -30), "%s!" % Rarity.name_for_tier(new_tier), Color(0.6, 1, 0.4), 20)
	var tw := kept.create_tween()
	kept.scale = Vector2(1.3, 1.3)
	tw.tween_property(kept, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if new_tier == Rarity.Tier.DEMON_GOD:
		if is_tier_up:
			kept.set_ascension(0)
		else:
			kept.set_ascension(kept.ascension + 1)
		_spawn_demon_god_promotion_fx(kept, kept.ascension)
	_refresh_hud()

const DEMON_GOD_TITLES := [
	"DEMON GOD AWAKENED!", "DEMON GOD ASCENSION I!", "DEMON GOD ASCENSION II!",
	"DEMON GOD ASCENSION III!", "TRUE DEMON GOD!",
]

## Extra-dramatic one-shot for a Demon God merge: screen shake + golden
## screen flash + layered explosion bursts + an evil-laugh sting + a punchy
## title card, stacked on top of the regular tier merge FX above. Scales up
## with the cat's ascension stage (0..Cat.MAX_ASCENSION) so the very first
## promotion is a modest jolt and each further merge into an already-maxed
## Demon God reads as a bigger, more "powered up" moment than the last.
func _spawn_demon_god_promotion_fx(cat: Cat, ascension: int) -> void:
	var t: float = float(ascension) / float(Cat.MAX_ASCENSION)
	if GameState.sound_on:
		_demon_god_sfx_player.pitch_scale = 1.0 + 0.1 * ascension
		_demon_god_sfx_player.play()
	_shake_screen(lerpf(0.4, 0.7, t), lerpf(10.0, 34.0, t))
	var flash_color := Color(1.0, 0.85, 0.2).lerp(Color(1.0, 0.35, 0.1), t)
	_flash_screen(flash_color, lerpf(0.5, 0.85, t))
	var pos := cat.position
	var burst_count := 3 + ascension
	var tw := cat.create_tween()
	for i in range(burst_count):
		var jitter := Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0)) * (1.0 + 0.2 * t)
		var fx_scale: float = maxf(0.16, (0.34 + 0.14 * t) - i * 0.04)
		tw.tween_callback(func(): Fx.explosion(world, pos + jitter, fx_scale))
		tw.tween_interval(0.13)
	var title_color := Color(1.0, 0.82, 0.15).lerp(Color(1.0, 0.3, 0.05), t)
	_spawn_demon_god_title_card(DEMON_GOD_TITLES[ascension], title_color)

## Camera-less screen shake: jitters the whole battlefield (this Node2D and
## its Background/Wall/Slots/World children) while leaving the UI CanvasLayer
## untouched, since CanvasLayer nodes ignore their parent's 2D transform.
func _shake_screen(duration: float, strength: float) -> void:
	var steps := maxi(4, int(duration / 0.04))
	var tw := create_tween()
	for i in range(steps):
		var decay := 1.0 - float(i) / steps
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * decay
		tw.tween_property(self, "position", offset, 0.04)
	tw.tween_property(self, "position", Vector2.ZERO, 0.04)

## Full-screen color pulse used to punctuate big moments (currently just the
## Demon God promotion). Added straight to the UI CanvasLayer so it overlays
## everything without blocking input.
func _flash_screen(color: Color, duration: float) -> void:
	var rect := ColorRect.new()
	rect.color = Color(color.r, color.g, color.b, 0.55)
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 100
	$UI.add_child(rect)
	var tw := rect.create_tween()
	tw.tween_property(rect, "color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(rect.queue_free)

## Big centered Demon God title card, built and animated entirely in code
## (mirrors _show_banner's punch-in/hold/fade rhythm) so no scene edit is
## needed for this rare, escalating moment.
func _spawn_demon_god_title_card(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -320.0
	label.offset_right = 320.0
	label.offset_top = -40.0
	label.offset_bottom = 40.0
	label.pivot_offset = Vector2(320, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 52)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.35, 0.05, 0.05))
	label.add_theme_constant_override("outline_size", 12)
	label.z_index = 101
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	label.scale = Vector2(0.4, 0.4)
	$UI.add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "modulate:a", 1.0, 0.2)
	tw.tween_property(label, "scale", Vector2(1.15, 1.15), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_interval(1.1)
	tw.chain().tween_property(label, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(label.queue_free)

## Tier-colored burst + expanding glow ring on merge, scaling up with rarity
## so leveling into Epic/Legendary/Demon God feels like a bigger deal than
## a plain Common-to-Rare merge.
const MERGE_FX_AMOUNT := [14, 20, 26, 34, 46]

func _spawn_merge_fx(pos: Vector2, tier: Rarity.Tier) -> void:
	var color := Rarity.color_for_tier(tier)
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var burst := GPUParticles2D.new()
	burst.texture = Rarity.aura_texture(tier)
	burst.amount = MERGE_FX_AMOUNT[tier]
	burst.lifetime = 0.45
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.global_position = pos
	burst.material = glow_mat
	var mat := ParticleProcessMaterial.new()
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 90.0 + 20.0 * tier
	mat.scale_min = 0.15
	mat.scale_max = 0.3 + 0.06 * tier
	mat.color = color
	burst.process_material = mat
	world.add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

	var ring := Sprite2D.new()
	ring.texture = Rarity.aura_texture(tier)
	ring.global_position = pos
	ring.modulate = Color(color.r, color.g, color.b, 0.85)
	ring.scale = Vector2(0.2, 0.2)
	ring.material = glow_mat
	world.add_child(ring)
	var ring_tw := ring.create_tween()
	ring_tw.set_parallel(true)
	ring_tw.tween_property(ring, "scale", Vector2(1.0, 1.0) * (1.0 + 0.15 * tier), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ring_tw.tween_property(ring, "modulate:a", 0.0, 0.4)
	ring_tw.chain().tween_callback(ring.queue_free)

func _swap_cats(dragged: Cat, other: Cat) -> void:
	var target_slot: Slot = other.slot
	other.slot = drag_origin
	other.row = drag_origin.row
	other.position = drag_origin.position
	drag_origin.occupant = other
	target_slot.occupant = dragged
	dragged.slot = target_slot
	dragged.row = target_slot.row
	dragged.position = target_slot.position
	if GameState.sound_on:
		_place_sfx_player.play()

func _update_drag_highlight(pos: Vector2) -> void:
	_clear_highlights()
	var slot := _slot_at(pos)
	if slot == null or slot == drag_origin:
		return
	if slot.is_trash:
		slot.set_highlight(true, Slot.TINT_SELL)
	elif slot.occupant and slot.occupant.character == dragged_cat.character:
		slot.set_highlight(true, Slot.TINT_MERGE)
	else:
		slot.set_highlight(true, Slot.TINT_MOVE)

func _clear_highlights() -> void:
	for s in slots:
		s.set_highlight(false)

# ---------------------------------------------------------------- items

func _setup_item_buttons() -> void:
	for i in range(ITEM_DEFS.size()):
		var id: String = ITEM_DEFS[i]["id"]
		item_buttons[i].pressed.connect(_on_item_pressed.bind(id))
	_refresh_item_buttons()

func _on_item_pressed(id: String) -> void:
	if match_over:
		return
	if armed_item == id:
		armed_item = ""
	elif GameState.item_count(id) > 0:
		armed_item = id
	_refresh_item_buttons()

func _try_place_item(pos: Vector2) -> void:
	var id := armed_item
	armed_item = ""
	if pos.x < ITEM_MIN_X or pos.x > ITEM_MAX_X + 60.0:
		_refresh_item_buttons()
		return
	if not GameState.use_item(id):
		_refresh_item_buttons()
		return
	var row := _nearest_row(pos.y)
	var place := Vector2(clampf(pos.x, ITEM_MIN_X, ITEM_MAX_X), ROW_Y[row])
	match id:
		"spikes":
			var trap := SpikeTrap.new()
			trap.row = row
			trap.damage_per_tick = 12 + 5 * wave
			trap.position = place
			world.add_child(trap)
		"tnt":
			Fx.explosion(world, pos, 0.3)
			Fx.smoke_explosion(world, pos, 0.35)
			var dmg := 150 + 50 * wave
			for e in get_tree().get_nodes_in_group("enemies"):
				if not e.is_dead() and e.global_position.distance_to(pos) < 150.0:
					e.take_damage(dmg)
		"boxer":
			var boxer := BoxingCat.new()
			boxer.row = row
			boxer.hp = 250 + 80 * wave
			boxer.punch_damage = 25 + 10 * wave
			boxer.position = place
			world.add_child(boxer)
		"poison":
			var cloud := PoisonCloud.new()
			cloud.row = row
			cloud.damage_per_tick = 10 + 4 * wave
			cloud.position = place
			world.add_child(cloud)
	_refresh_item_buttons()

func _nearest_row(y: float) -> int:
	var best := 0
	for r in range(ROW_Y.size()):
		if absf(ROW_Y[r] - y) < absf(ROW_Y[best] - y):
			best = r
	return best

func _refresh_item_buttons() -> void:
	for i in range(ITEM_DEFS.size()):
		var id: String = ITEM_DEFS[i]["id"]
		var count: int = GameState.item_count(id)
		var btn := item_buttons[i]
		btn.get_node("Badge/CountLabel").text = "%d/%d" % [count, GameState.MAX_ITEM_COUNT]
		if armed_item == id:
			btn.self_modulate = Color(1.4, 1.4, 0.7)
		elif count <= 0:
			btn.self_modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.self_modulate = Color.WHITE

# ---------------------------------------------------------------- wall repair

func repair_cost() -> int:
	return int(ceil(wall.missing_hp() * (0.35 + 0.05 * wave)))

func _on_repair_pressed() -> void:
	if match_over:
		return
	var cost := repair_cost()
	if wall.missing_hp() <= 0 or coins < cost:
		_flash_deny(repair_button)
		return
	coins -= cost
	wall.repair_full()
	_refresh_hud()

# ---------------------------------------------------------------- waves

func _start_wave() -> void:
	wave += 1
	wave_active = true
	boss_to_spawn = wave % 5 == 0
	enemies_to_spawn = 8 + 3 * wave + 2 * (level_num - 1)
	if boss_to_spawn:
		enemies_to_spawn = int(enemies_to_spawn * 0.7)
	spawn_timer = 1.2
	if GameState.sound_on:
		_wave_sfx_player.stream = _wave_sfx_streams[_wave_sfx_index]
		_wave_sfx_index = (_wave_sfx_index + 1) % _wave_sfx_streams.size()
		_wave_sfx_player.play()
	_refresh_hud()
	_show_banner("Wave %d Incoming!" % wave)

func _process(delta: float) -> void:
	# Main runs in PROCESS_MODE_ALWAYS so pause/drag input keeps working
	# while the tree is paused; gameplay itself must not advance then.
	if get_tree().paused or match_over or not wave_active:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0 and (enemies_to_spawn > 0 or boss_to_spawn):
		if boss_to_spawn:
			boss_to_spawn = false
			_spawn_enemy(true)
		else:
			enemies_to_spawn -= 1
			_spawn_enemy(false)
		spawn_timer = maxf(1.7 - 0.09 * wave - 0.02 * level_num, 0.55) + randf() * 0.4
	elif enemies_to_spawn <= 0 and not boss_to_spawn and _alive_enemies() == 0 and not break_pending:
		wave_active = false
		GameState.add_gems(1)
		if wave >= WIN_WAVE:
			_win_match()
		else:
			break_pending = true
			# SceneTreeTimers outlive scene reloads and lambda connections are
			# not auto-cleaned on free, so guard against a freed Main.
			get_tree().create_timer(2.2, false).timeout.connect(func():
				if not is_instance_valid(self):
					return
				break_pending = false
				if not match_over:
					_start_wave())

func _alive_enemies() -> int:
	var count := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_dead():
			count += 1
	return count

func _spawn_enemy(boss: bool) -> void:
	var enemy: Enemy = EnemyScene.instantiate()
	var row := randi() % ROW_Y.size()
	enemy.row = row
	enemy.is_boss = boss
	enemy.wall = wall
	var hp := int(round(22.0 * pow(1.18, wave - 1) * pow(1.13, level_num - 1) * _board_capacity_factor()))
	# Rewards scale exponentially like enemy HP does, or buying/merging
	# stalls out mid-match while enemies keep compounding.
	var reward := int(round((12.0 * pow(1.18, wave - 1) + 5 * (level_num - 1)) * 0.45))
	if boss:
		enemy.enemy_index = (level_num - 1) % 7 + 1
		enemy.max_hp = hp * (16 if wave >= WIN_WAVE else 10)
		enemy.speed = randf_range(9.0, 13.0)
		enemy.damage = (6 + 2 * wave) * 5
		enemy.gold_reward = reward * 8
	else:
		enemy.enemy_index = (level_num - 1 + randi() % 4) % 8 + 1
		enemy.max_hp = hp
		enemy.speed = randf_range(34.0, 56.0)
		enemy.damage = 6 + 2 * wave
		enemy.gold_reward = reward
	enemy.position = Vector2(ENEMY_SPAWN_X, ROW_Y[row] + randf_range(-8.0, 8.0))
	enemy.reached_end.connect(_on_enemy_reached_end)
	enemy.died.connect(_on_enemy_died)
	world.add_child(enemy)

func _on_enemy_reached_end(_enemy: Enemy) -> void:
	if match_over:
		return
	_lose_match()

func _on_enemy_died(enemy: Enemy) -> void:
	coins += enemy.gold_reward
	FloatText.spawn(world, enemy.global_position + Vector2(0, -20), "+%d" % enemy.gold_reward, Color(1, 0.85, 0.3), 16)
	if enemy.is_boss:
		Fx.smoke_explosion(world, enemy.global_position, 0.5)
		_burst_coins(enemy.global_position, BOSS_COIN_COUNT)
	elif randf() < _coin_drop_chance():
		_spawn_coin_pickup(enemy.global_position, 1)
		if GameState.sound_on:
			_drop_sfx_player.play()
	_refresh_hud()

# ---------------------------------------------------------------- coin drop

func _coin_drop_chance() -> float:
	var cfg: Dictionary = COIN_DROP_CFG.get(level_num, COIN_DROP_CFG[1])
	return maxf(cfg.floor, cfg.base - cfg.decay * (wave - 1))

func _spawn_coin_pickup(pos: Vector2, value: int) -> void:
	var coin := CoinPickup.new()
	coin.value = value
	coin.position = pos
	coin.collected.connect(_on_coin_collected)
	world.add_child(coin)

func _burst_coins(pos: Vector2, count: int) -> void:
	for i in range(count):
		var offset := Vector2(randf_range(-20.0, 20.0), randf_range(-15.0, 15.0))
		_spawn_coin_pickup(pos + offset, 1)
	if GameState.sound_on:
		_drop_sfx_player.play()

func _on_coin_collected(coin: CoinPickup) -> void:
	if match_over:
		return
	coins += coin.value
	FloatText.spawn(world, coin.global_position + Vector2(0, -20), "+%d" % coin.value, Color(1, 0.85, 0.3), 16)
	_refresh_hud()

# ---------------------------------------------------------------- match end

func _win_match() -> void:
	match_over = true
	_cancel_drag()
	if GameState.sound_on:
		_level_complete_sfx_player.play()
	var bonus := GameState.complete_level(level_num)
	win_bonus_label.text = "+%d" % bonus
	var total_cards := 0
	for count in GameState.last_cards_awarded.values():
		total_cards += int(count)
	win_cards_label.text = "+%d Cat Cards" % total_cards
	get_tree().paused = true
	win_panel.visible = true

func _lose_match() -> void:
	match_over = true
	_cancel_drag()
	get_tree().paused = true
	lose_panel.visible = true

func _on_continue_pressed() -> void:
	get_tree().paused = false
	SceneTransition.change_scene("res://scenes/Lobby.tscn")

func _on_restart_pressed() -> void:
	get_tree().paused = false
	SceneTransition.reload_scene()

func _on_home_pressed() -> void:
	get_tree().paused = false
	SceneTransition.change_scene("res://scenes/Lobby.tscn")

# ---------------------------------------------------------------- pause

func _on_pause_pressed() -> void:
	_cancel_drag()
	get_tree().paused = true
	pause_panel.visible = true

func _on_resume_pressed() -> void:
	pause_panel.visible = false
	get_tree().paused = false

func _on_toggle(key: String) -> void:
	match key:
		"music": GameState.set_toggle("music", not GameState.music_on)
		"sound": GameState.set_toggle("sound", not GameState.sound_on)
		"vibra": GameState.set_toggle("vibra", not GameState.vibra_on)
	_refresh_toggle_textures()

func _refresh_toggle_textures() -> void:
	music_toggle.texture_normal = TEX_MUSIC_ON if GameState.music_on else TEX_MUSIC_OFF
	sound_toggle.texture_normal = TEX_SOUND_ON if GameState.sound_on else TEX_SOUND_OFF
	vibra_toggle.texture_normal = TEX_VIBRA_ON if GameState.vibra_on else TEX_VIBRA_OFF

# ---------------------------------------------------------------- hud

func _refresh_hud() -> void:
	coin_label.text = str(coins)
	wave_label.text = "Wave %d / %d" % [maxi(wave, 1), WIN_WAVE]
	repair_cost_label.text = _fmt(repair_cost())
	var can_repair := wall.missing_hp() > 0 and coins >= repair_cost()
	repair_button.self_modulate = Color.WHITE if can_repair else Color(0.55, 0.55, 0.55)
	_refresh_item_buttons()

func _fmt(n: int) -> String:
	if n >= 100000:
		return "%dk" % (n / 1000)
	return str(n)

# ---------------------------------------------------------------- tutorial

func _start_main_tutorial() -> void:
	await SceneTransition.fade_in_finished
	if not is_instance_valid(self) or GameState.tutorial_seen or GameState.tutorial_step < 1:
		return
	_tutorial_overlay = TutorialOverlayScene.instantiate()
	add_child(_tutorial_overlay)
	_tutorial_overlay.advanced.connect(_on_tutorial_advanced)
	_tutorial_overlay.skipped.connect(_on_tutorial_skipped)
	_show_main_tutorial_step()

func _show_main_tutorial_step() -> void:
	var index: int = GameState.tutorial_step
	if index >= TutorialSteps.STEPS.size():
		_end_main_tutorial()
		return
	var step: Dictionary = TutorialSteps.STEPS[index]
	var rect := _tutorial_target_rect(step["target"])
	get_tree().paused = not step["gated"]
	_tutorial_overlay.show_step(step["text"], rect, step["tap_to_continue"])

func _tutorial_target_rect(target: String) -> Rect2:
	match target:
		"buy_slot":
			var free := _free_slots()
			if not free.is_empty():
				return Rect2(free[0].global_position - TUTORIAL_SLOT_SIZE * 0.5, TUTORIAL_SLOT_SIZE)
			return _board_rect()
		"merge_hint":
			var pair_rect := _matching_pair_rect()
			return pair_rect if pair_rect.size != Vector2.ZERO else _board_rect()
		"wall":
			return Rect2(wall.global_position + Wall.CRATE_REGION.position * Wall.BG_SCALE, Wall.CRATE_REGION.size * Wall.BG_SCALE)
		"repair_button":
			return repair_button.get_global_rect()
		"item_buttons":
			var union_rect := item_buttons[0].get_global_rect()
			for btn in item_buttons:
				union_rect = union_rect.merge(btn.get_global_rect())
			return union_rect
		_:
			return _board_rect()

func _board_rect() -> Rect2:
	var top_left := slots[0].global_position - TUTORIAL_SLOT_SIZE * 0.5
	var result := Rect2(top_left, TUTORIAL_SLOT_SIZE)
	for s in slots:
		result = result.merge(Rect2(s.global_position - TUTORIAL_SLOT_SIZE * 0.5, TUTORIAL_SLOT_SIZE))
	return result

func _matching_pair_rect() -> Rect2:
	for a in slots:
		if a.is_free() or a.is_trash:
			continue
		for b in slots:
			if b == a or b.is_free() or b.is_trash:
				continue
			if b.occupant.character == a.occupant.character:
				return Rect2(a.global_position - TUTORIAL_SLOT_SIZE * 0.5, TUTORIAL_SLOT_SIZE).merge(
					Rect2(b.global_position - TUTORIAL_SLOT_SIZE * 0.5, TUTORIAL_SLOT_SIZE))
	return Rect2()

func _on_tutorial_advanced() -> void:
	GameState.advance_tutorial_step()
	_show_main_tutorial_step()

func _on_tutorial_skipped() -> void:
	_end_main_tutorial()

func _end_main_tutorial() -> void:
	GameState.mark_tutorial_seen()
	get_tree().paused = false
	if _tutorial_overlay:
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null

func _flash_deny(button: TextureButton) -> void:
	var tw := button.create_tween()
	button.self_modulate = Color(1.5, 0.4, 0.4)
	tw.tween_interval(0.12)
	tw.tween_callback(_refresh_hud)

func _flash_deny_slot(slot: Slot) -> void:
	slot.set_highlight(true, Color(1.0, 0.3, 0.3, 0.6))
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_callback(slot.set_highlight.bind(false))

func _show_banner(text: String) -> void:
	wave_banner.text = text
	wave_banner.visible = true
	wave_banner.modulate.a = 0.0
	wave_banner.scale = Vector2(0.6, 0.6)
	var tw := wave_banner.create_tween()
	tw.set_parallel(true)
	tw.tween_property(wave_banner, "modulate:a", 1.0, 0.25)
	tw.tween_property(wave_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.3)
	tw.chain().tween_property(wave_banner, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(func(): wave_banner.visible = false)
