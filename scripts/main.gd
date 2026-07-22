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
# "cols" is a flat Array shared by every row (a rectangular NxM board, as
# every Area1..5 layout is). Hunt's cross-shaped board isn't described here
# at all - see the AREA_BOARD_CONFIG[0] comment below.
const ROW_Y := [199.8, 276.5, 354.2, 431.6, 508.5]
const LEGACY_BG_SCALE := Vector2(0.598, 0.678)
const HUNT_AREA_INDEX := 0
# Hunt mode doesn't spawn slots/background/wall from this config at all - it
# runs scenes/HuntArea.tscn, an inherited scene of Main.tscn that authors its
# own Background/Wall/Slots/PortalMarker in the editor (see _setup_level()
# and _spawn_slots()). Area 0's row_y is still used for enemy lanes and item
# placement snapping (_row_y()), which aren't authored per-node in the scene.
const AREA_BOARD_CONFIG := {
	0: {
		"row_y": [216.1, 475.8],
		"item_min_x": 230.0,
		"item_max_x": 1050.0,
	},
	1: {"cols": [78.9, 162.7, 245.8], "trash_pos": Vector2(62.2, 644.1), "trash_row": -1, "trash_col": -1},
	2: {"cols": [78.9, 162.7, 245.8], "trash_pos": Vector2(242.2, 603.4), "trash_row": -1, "trash_col": -1},
	3: {"cols": [78.9, 162.7, 245.8], "trash_pos": Vector2(66.4, 73.9), "trash_row": -1, "trash_col": -1},
	4: {"cols": [163.0, 246.0], "trash_pos": Vector2(163.0, 508.5), "trash_row": 4, "trash_col": 0},
	5: {"cols": [163.0, 246.0], "trash_pos": Vector2(163.0, 508.5), "trash_row": 4, "trash_col": 0},
}

const WAVE_SFX_PATHS := [
	"res://sfx/laughs sfx/evil-cat-laugh.mp3",
	"res://sfx/laughs sfx/cartoonlaugh1.mp3",
	"res://sfx/alarm.mp3",
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
## A level's length now scales with its number (level 1 = 10 waves, level 2 =
## 20, ... level 8 = 80) so later levels are literally longer fights, not just
## higher-stat versions of the same 10 waves. BASE_WAVE_CHUNK is also the size
## of one escalation "chunk" within that run: the exponential HP/reward growth
## resets its wave exponent every chunk (so it can't blow up to absurd/unkillable
## numbers over an 80-wave level) while DECADE_GROWTH adds a modest extra
## multiplier per chunk survived, so the fight still gets harder the longer it runs.
const BASE_WAVE_CHUNK := 10
const DECADE_GROWTH := 1.6
const SUMMON_COST := 30
const START_COINS := 60
const DRAG_PICK_RADIUS := 55.0
const ITEM_MIN_X := 470.0
const ITEM_MAX_X := 1230.0
const ENEMY_SPAWN_X := 1340.0
const DROP_COIN_SFX_PATH := "res://sfx/drop-coin.mp3"
const COIN_COLLECT_SFX_PATH := "res://sfx/coin.ogg"
const BOSS_COIN_COUNT := 2
const COIN_DROP_CFG := {
	1: {"base": 0.53, "decay": 0.04, "floor": 0.21},
	2: {"base": 0.49, "decay": 0.04, "floor": 0.18},
	3: {"base": 0.46, "decay": 0.04, "floor": 0.15},
	4: {"base": 0.42, "decay": 0.05, "floor": 0.14},
	5: {"base": 0.39, "decay": 0.05, "floor": 0.13},
	6: {"base": 0.35, "decay": 0.05, "floor": 0.11},
	7: {"base": 0.32, "decay": 0.06, "floor": 0.08},
	8: {"base": 0.28, "decay": 0.06, "floor": 0.07},
}

const ITEM_DEFS := [
	{"id": "spikes", "icon": "res://Png/Ui/AddonIcon8.png"},
	{"id": "tnt", "icon": "res://Png/Ui/AddonIcon6.png"},
	{"id": "boxer", "icon": "res://Png/Ui/AddonIcon7.png"},
	{"id": "poison", "icon": "res://Png/Ui/AddonIcon9.png"},
]
const ITEM_STAT_DEFS := {
	"spikes": {"base": 12, "per_wave": 5},
	"tnt": {"base": 150, "per_wave": 50},
	"boxer_hp": {"base": 250, "per_wave": 80},
	"boxer_punch": {"base": 25, "per_wave": 10},
	"poison": {"base": 10, "per_wave": 4},
}
const TNT_BLAST_RADIUS := 150.0

# Wall/economy formula constants
const WALL_BASE_HP := 300
const WALL_HP_PER_LEVEL := 200
const SELL_VALUE_BASE := 10
const SELL_VALUE_PER_CHARACTER := 20
const REPAIR_COST_BASE_PCT := 0.35
const REPAIR_COST_PER_WAVE_PCT := 0.05
const FMT_K_THRESHOLD := 100000

# Wave spawn-cadence constants
const WAVE_START_ENEMY_BASE := 6
const WAVE_START_ENEMY_PER_CHUNK_WAVE := 3
const WAVE_START_ENEMY_PER_LEVEL := 2
const WAVE_START_ENEMY_PER_CHUNK := 9
const BOSS_WAVE_ENEMY_COUNT_MULT := 0.7
# TD-style mid-chunk surge: from this wave-in-chunk onward, extra enemies pile
# on top of the normal per-wave growth (and keep piling on each wave after),
# so a chunk's back half plays like an escalating swarm instead of a flat
# trickle - the same "rounds get noticeably heavier midway" shape most TD
# games use. Resets every BASE_WAVE_CHUNK waves along with the rest of the
# chunk's escalation (see BASE_WAVE_CHUNK comment above _start_wave()).
const WAVE_SURGE_START_WAVE := 5
const WAVE_SURGE_ENEMY_PER_WAVE := 3
const WAVE_SURGE_SPAWN_INTERVAL_PER_WAVE := 0.05
const FIRST_SPAWN_DELAY := 1.8
const SPAWN_INTERVAL_BASE := 1.7
const SPAWN_INTERVAL_PER_WAVE := 0.09
const SPAWN_INTERVAL_PER_LEVEL := 0.02
const SPAWN_INTERVAL_MIN := 0.55
const SPAWN_INTERVAL_JITTER := 0.4
const WAVE_BREAK_SECONDS := 2.2

# Enemy HP/reward growth-formula constants (see _compute_enemy_base_hp/_compute_enemy_reward)
const ENEMY_BASE_HP := 22.0
const ENEMY_HP_GROWTH_PER_WAVE := 1.18
const ENEMY_HP_GROWTH_PER_LEVEL := 1.13
const ENEMY_BASE_REWARD := 12.0
const ENEMY_REWARD_GROWTH := 1.18
const ENEMY_REWARD_PER_LEVEL := 5
const ENEMY_REWARD_SCALE := 0.32
const LATE_WAVE_RAMP_THRESHOLD := 8
const LATE_WAVE_RAMP_FACTOR := 1.05
const LATE_LEVEL_RAMP_THRESHOLD := 6
const LATE_LEVEL_RAMP_FACTOR := 1.06
const ENEMY_SPAWN_Y_JITTER := 8.0

# Boss/regular enemy stat-formula constants. Folder counts are tied to actual
# asset folder counts (Png/Enemies/Enemy Boss %d, Enemy Reg %d) - keep literal.
const BOSS_FOLDER_COUNT := 7
const REGULAR_FOLDER_COUNT := 8
const BOSS_HP_MULT_FINAL := 13       # softened from 16 - less of a hard step vs BOSS_HP_MULT_NORMAL
const BOSS_HP_MULT_NORMAL := 10
const BOSS_SPEED_MIN := 9.0
const BOSS_SPEED_MAX := 13.0
const BOSS_DAMAGE_BASE := 6
const BOSS_DAMAGE_PER_WAVE := 2
const BOSS_DAMAGE_SCALE := 5
const BOSS_GOLD_MULT := 6
const BOSS_FINAL_ARMOR_MIN := 0.35
const BOSS_FINAL_ARMOR_MAX := 0.6
const BOSS_FINAL_ARMOR_PER_WAVE := 0.01
const BOSS_HEAL_PULSE_PCT := 0.08
const BOSS_HEAL_PULSE_INTERVAL := 6.0
const REGULAR_SPEED_MIN := 34.0
const REGULAR_SPEED_MAX := 56.0
const REGULAR_DAMAGE_BASE := 6
const REGULAR_DAMAGE_PER_WAVE := 2
const REGULAR_LATE_CHUNK_THRESHOLD := 6
const REGULAR_LATE_ARMOR_CHANCE := 0.35
const REGULAR_ARMOR_MIN := 0.25
const REGULAR_ARMOR_MAX := 0.65
const REGULAR_ARMOR_PER_WAVE := 0.015

# Coin-drop/pickup constants
const COIN_BURST_JITTER_X := 20.0
const COIN_BURST_JITTER_Y := 15.0

# FX/UI tween constants
const CAT_SPAWN_TWEEN_SCALE := 0.2
const CAT_SPAWN_TWEEN_DURATION := 0.22
const MERGE_TWEEN_SCALE := 1.3
const MERGE_TWEEN_DURATION := 0.25
const DEMON_GOD_PITCH_PER_ASCENSION := 0.1
const DEMON_GOD_SHAKE_DURATION_MIN := 0.4
const DEMON_GOD_SHAKE_DURATION_MAX := 0.7
const DEMON_GOD_SHAKE_STRENGTH_MIN := 10.0
const DEMON_GOD_SHAKE_STRENGTH_MAX := 34.0
const DEMON_GOD_FLASH_DURATION_MIN := 0.5
const DEMON_GOD_FLASH_DURATION_MAX := 0.85
const DEMON_GOD_BURST_BASE_COUNT := 3
const DEMON_GOD_BURST_JITTER := 24.0
const DEMON_GOD_BURST_JITTER_SCALE := 0.2
const DEMON_GOD_BURST_FX_SCALE_MIN := 0.16
const DEMON_GOD_BURST_FX_SCALE_BASE := 0.34
const DEMON_GOD_BURST_FX_SCALE_PER_T := 0.14
const DEMON_GOD_BURST_FX_SCALE_STEP := 0.04
const DEMON_GOD_BURST_INTERVAL := 0.13
const SCREEN_SHAKE_STEP_DURATION := 0.04
const SCREEN_FLASH_ALPHA := 0.55
const SCREEN_FLASH_Z_INDEX := 100
const TITLE_CARD_OFFSET_X := 320.0
const TITLE_CARD_OFFSET_Y := 40.0
const TITLE_CARD_FONT_SIZE := 52
const TITLE_CARD_OUTLINE_COLOR := Color(0.35, 0.05, 0.05)
const TITLE_CARD_OUTLINE_SIZE := 12
const TITLE_CARD_Z_INDEX := 101
const TITLE_CARD_START_SCALE := 0.4
const TITLE_CARD_PUNCH_SCALE := 1.15
const TITLE_CARD_FADE_IN := 0.2
const TITLE_CARD_SCALE_IN := 0.3
const TITLE_CARD_SETTLE := 0.15
const TITLE_CARD_HOLD := 1.1
const TITLE_CARD_FADE_OUT := 0.4
const DENY_FLASH_COLOR_BUTTON := Color(1.5, 0.4, 0.4)
const DENY_FLASH_DURATION_BUTTON := 0.12
const DENY_FLASH_COLOR_SLOT := Color(1.0, 0.3, 0.3, 0.6)
const DENY_FLASH_DURATION_SLOT := 0.15
const BANNER_START_SCALE := Vector2(0.6, 0.6)
const BANNER_FADE_IN := 0.25
const BANNER_SCALE_IN := 0.3
const BANNER_HOLD := 1.3
const BANNER_FADE_OUT := 0.4

# Merge burst/glow-ring FX constants
const MERGE_FX_LIFETIME := 0.45
const MERGE_FX_VELOCITY_MIN := 40.0
const MERGE_FX_VELOCITY_MAX_BASE := 90.0
const MERGE_FX_VELOCITY_PER_TIER := 20.0
const MERGE_FX_SCALE_MIN := 0.15
const MERGE_FX_SCALE_BASE := 0.3
const MERGE_FX_SCALE_PER_TIER := 0.06
const MERGE_RING_START_SCALE := 0.2
const MERGE_RING_ALPHA := 0.85
const MERGE_RING_SCALE_PER_TIER := 0.15
const MERGE_RING_TWEEN_DURATION := 0.4

var level_num: int = 1
var area_index: int = 1
var _enemy_spawn_x: float = ENEMY_SPAWN_X
var coins: int = START_COINS
var wave: int = 0
var best_character: int = 1    # highest cat character reached this match
var enemies_to_spawn: int = 0
var boss_to_spawn: bool = false
var spawn_timer: float = 0.0
var wave_active: bool = false
var break_pending: bool = false
var match_over: bool = false
var endless_mode: bool = false    # true once a level already beaten before is re-cleared, past its final wave
const ENDLESS_BONUS_GEMS := 2      # extra gems per wave cleared beyond a level's final wave in endless mode
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
var _coin_collect_sfx_player: AudioStreamPlayer
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
@onready var pause_home_button: TextureButton = $UI/PausePanel/HomeButton

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

	_merge_sfx_player = _create_sfx_player(MERGE_SFX_PATH)
	_place_sfx_player = _create_sfx_player(PLACE_SFX_PATH)
	_demon_god_sfx_player = _create_sfx_player(DEMON_GOD_SFX_PATH)
	_wave_complete_sfx_player = _create_sfx_player(WAVE_COMPLETE_SFX_PATH)
	_level_complete_sfx_player = _create_sfx_player(LEVEL_COMPLETE_SFX_PATH)
	_drop_sfx_player = _create_sfx_player(DROP_COIN_SFX_PATH)
	_coin_collect_sfx_player = _create_sfx_player(COIN_COLLECT_SFX_PATH)

	_refresh_hud()
	_start_wave()

	if not GameState.tutorial_seen and GameState.tutorial_step >= 1:
		call_deferred("_start_main_tutorial")

## Builds and attaches a one-shot SFX player for `stream_path`. Not used for
## _wave_sfx_player, which cycles through multiple streams (see _ready above).
func _create_sfx_player(stream_path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = load(stream_path)
	add_child(player)
	return player

func _setup_level() -> void:
	if GameState.hunt_mode:
		area_index = HUNT_AREA_INDEX
	else:
		area_index = (level_num - 1) % 5 + 1
	coins = START_COINS
	endless_mode = false
	wall.set_max_hp(WALL_BASE_HP + WALL_HP_PER_LEVEL * (level_num - 1))

	if GameState.hunt_mode:
		# HuntArea.tscn already set Background/Wall's texture/scale/region via
		# the editor Inspector - just hook up the broken-overlay texture.
		wall.setup_broken_overlay(background.texture)
	else:
		var cfg: Dictionary = AREA_BOARD_CONFIG[area_index]
		background.texture = load(cfg.get("bg_path", "res://Png/Area/Area%d.png" % area_index))
		background.scale = cfg.get("bg_scale", LEGACY_BG_SCALE)
		wall.setup_broken_overlay(background.texture, cfg.get("wall_crate_region", Wall.CRATE_REGION), cfg.get("bg_scale", Wall.BG_SCALE))
		wall.set_bar_rect(cfg.get("wall_bar_rect", Wall.BAR_BACK_RECT))
	wall.hp_changed.connect(func(_hp, _max): _refresh_hud())

	if GameState.hunt_mode:
		var marker := world.get_node_or_null("PortalMarker") as PortalMarker
		_enemy_spawn_x = marker.position.x if marker else ENEMY_SPAWN_X
	else:
		_enemy_spawn_x = ENEMY_SPAWN_X

func _setup_panels() -> void:
	for panel in [pause_panel, lose_panel, win_panel]:
		panel.visible = false
		panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_restart_button.pressed.connect(_on_restart_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	pause_home_button.pressed.connect(_on_home_pressed)
	lose_restart_button.pressed.connect(_on_restart_pressed)
	lose_home_button.pressed.connect(_on_home_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	music_toggle.pressed.connect(_on_toggle.bind("music"))
	sound_toggle.pressed.connect(_on_toggle.bind("sound"))
	vibra_toggle.pressed.connect(_on_toggle.bind("vibra"))
	_refresh_toggle_textures()

# ---------------------------------------------------------------- board

## Row Y positions for the current area: falls back to the shared ROW_Y
## unless the area config overrides it (see AREA_BOARD_CONFIG comment above).
func _row_y() -> Array:
	return AREA_BOARD_CONFIG[area_index].get("row_y", ROW_Y)

## Item-placement x clamp for the current area: falls back to the shared
## ITEM_MIN_X/ITEM_MAX_X unless the area config overrides it (Hunt's
## cross-shaped board spans a different x-range than Area1-5's rectangular grid).
func _item_bounds() -> Vector2:
	var cfg: Dictionary = AREA_BOARD_CONFIG[area_index]
	return Vector2(cfg.get("item_min_x", ITEM_MIN_X), cfg.get("item_max_x", ITEM_MAX_X))

func _spawn_slots() -> void:
	if GameState.hunt_mode:
		# HuntArea.tscn places its 23 Slot instances directly under Slots in
		# the editor (row/col/is_trash set per-instance) instead of spawning
		# them from a cols array here - just collect what's already there.
		for child in slots_container.get_children():
			if child is Slot:
				slots.append(child)
		return
	var cfg: Dictionary = AREA_BOARD_CONFIG[area_index]
	var row_y: Array = _row_y()
	var cols: Array = cfg["cols"]
	for r in range(row_y.size()):
		for c in range(cols.size()):
			if r == cfg["trash_row"] and c == cfg["trash_col"]:
				continue
			var slot: Slot = SlotScene.instantiate()
			slot.row = r
			slot.col = c
			slot.is_trash = false
			slot.position = Vector2(cols[c], row_y[r])
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

## Hunt's cross board lets every cat target the single frontmost enemy
## regardless of row (see Cat._find_target's any_row branch), so none of its
## DPS is ever wasted on an empty row the way the row-locked standard grid's
## can be. A flat slot-count ratio only prices in the extra cat count, not
## that zero-waste targeting advantage, so Hunt's capacity ratio is raised to
## this exponent instead of scaling linearly.
const HUNT_CAPACITY_EXPONENT := 1.75

## Areas 4/5 hold only 9-10 board slots vs. Area 1/2/3's 15 (see
## AREA_BOARD_CONFIG), purely an artifact of which background art a level
## reuses. Enemy HP scaling is tuned against the 15-slot baseline, so it's
## scaled down proportionally on smaller boards — otherwise those levels get
## far less achievable cat DPS but face the same enemy toughness as a level
## with a full board, producing wild difficulty swings between levels that
## share the same wave-scaling formula. (Hunt's 19-slot cross board scales
## the other way, upward, past the baseline for the same reason.)
func _board_capacity_factor() -> float:
	var total := 0
	for s in slots:
		if not s.is_trash:
			total += 1
	var ratio := float(total) / float(MAX_BOARD_SLOTS)
	if GameState.hunt_mode:
		return pow(ratio, HUNT_CAPACITY_EXPONENT)
	return ratio

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

## Returns the occupied slot whose position is nearest `pos`, within
## DRAG_PICK_RADIUS, or null if none qualify. Shared by drag-pickup and
## swap-target-pick, which both only care about occupied slots (unlike
## `_slot_at`, which also matches empty slots for buy/trash/move resolution).
func _nearest_occupied_slot(pos: Vector2, max_dist: float = DRAG_PICK_RADIUS) -> Slot:
	var best: Slot = null
	var best_d := max_dist
	for s in slots:
		if s.occupant and s.position.distance_to(pos) < best_d:
			best = s
			best_d = s.position.distance_to(pos)
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
	var owned_in_range: Array[int] = []
	for c in range(lo, hi + 1):
		if GameState.is_character_purchased(c):
			owned_in_range.append(c)
	if randf() < SUMMON_PITY_CHANCE:
		var on_board: Array[int] = []
		for s in slots:
			if s.occupant and s.occupant.character in owned_in_range:
				on_board.append(s.occupant.character)
		if not on_board.is_empty():
			return on_board[randi() % on_board.size()]
	return owned_in_range[randi() % owned_in_range.size()]

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
	_play_sfx_if_enabled(_place_sfx_player)
	cat.scale = Vector2(CAT_SPAWN_TWEEN_SCALE, CAT_SPAWN_TWEEN_SCALE)
	var tw := cat.create_tween()
	tw.tween_property(cat, "scale", Vector2.ONE, CAT_SPAWN_TWEEN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Plays `player` only if the sound setting is on. Shared by every SFX call
## site that has no extra setup (pitch/stream selection) beyond play().
func _play_sfx_if_enabled(player: AudioStreamPlayer) -> void:
	if GameState.sound_on:
		player.play()

func _record_character(character: int) -> void:
	if character > best_character:
		best_character = character
		GameState.record_merge_character(character)

func sell_value(character: int) -> int:
	return SELL_VALUE_BASE + SELL_VALUE_PER_CHARACTER * character

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
	_dismiss_active_swap_button()

## Hides the currently-shown Demon God cat Swap button, if any.
func _dismiss_active_swap_button() -> void:
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
	var best_slot := _nearest_occupied_slot(pos)
	var best: Cat = best_slot.occupant if best_slot else null
	if best == null or best == source:
		return
	if Rarity.tier_for_character(best.character) == Rarity.Tier.DEMON_GOD:
		_merge_cats(source, source.slot, best)

## Tap-dispatch, in strict priority order: an in-progress swap pick, then a
## drag-reentry guard, then item placement, coin pickup collection, dismissing
## any shown swap button, starting a new drag, and finally a buy-at-slot
## fallback. This order is gameplay behavior — do not reorder these checks.
func _on_press(pos: Vector2) -> void:
	if swap_source_cat != null:
		_handle_swap_pick(pos)
		return
	if dragged_cat != null:
		return
	if armed_item != "":
		_try_place_item(pos)
		return
	if _try_collect_coin_pickup(pos):
		return
	_dismiss_active_swap_button()
	if _try_begin_cat_drag(pos):
		return
	_try_buy_at_tapped_slot(pos)

func _try_collect_coin_pickup(pos: Vector2) -> bool:
	for c in get_tree().get_nodes_in_group("coin_pickups"):
		if not is_instance_valid(c):
			continue
		if c.global_position.distance_to(pos) < DRAG_PICK_RADIUS:
			c.collect()
			return true
	return false

func _try_begin_cat_drag(pos: Vector2) -> bool:
	var best_slot := _nearest_occupied_slot(pos)
	if best_slot == null:
		return false
	dragged_cat = best_slot.occupant
	drag_origin = best_slot.occupant.slot
	best_slot.occupant.set_dragging(true)
	return true

func _try_buy_at_tapped_slot(pos: Vector2) -> void:
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
	_dismiss_active_swap_button()
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
	_play_sfx_if_enabled(_place_sfx_player)

## Strict merge rule: only two cats of the exact same character AND exact
## same tier may merge. Since a character deterministically maps to one tier
## (Rarity.tier_for_character), matching character already implies matching
## tier, but both are checked explicitly to keep the rule unambiguous.
## Merging into a new character still requires that character to be purchased
## first (Treats, see GameState.purchase_character) — same gate as summoning.
func _can_merge(a: Cat, b: Cat) -> bool:
	if a.character != b.character:
		return false
	if Rarity.tier_for_character(a.character) != Rarity.tier_for_character(b.character):
		return false
	if Rarity.tier_for_character(a.character) == Rarity.Tier.DEMON_GOD:
		return true
	return GameState.is_character_purchased(a.character + 1)

func _merge_cats(dragged: Cat, dragged_slot: Slot, kept: Cat) -> void:
	dragged_slot.occupant = null
	dragged.queue_free()
	_play_sfx_if_enabled(_merge_sfx_player)
	var current_tier := Rarity.tier_for_character(kept.character)
	var new_character := kept.character
	var is_tier_up := false
	if current_tier < Rarity.Tier.DEMON_GOD:
		new_character = kept.character + 1
		is_tier_up = Rarity.tier_for_character(new_character) == Rarity.Tier.DEMON_GOD
	kept.set_character(new_character)
	_record_character(new_character)
	var new_tier := Rarity.tier_for_character(new_character)
	Fx.smoke_spell(world, kept.position, 0.14)
	_spawn_merge_fx(kept.position, new_tier)
	Fx.flash_hit(kept)
	FloatText.spawn(world, kept.position + Vector2(0, -30), "%s!" % Rarity.name_for_tier(new_tier), Color(0.6, 1, 0.4), 20)
	var tw := kept.create_tween()
	kept.scale = Vector2(MERGE_TWEEN_SCALE, MERGE_TWEEN_SCALE)
	tw.tween_property(kept, "scale", Vector2.ONE, MERGE_TWEEN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
		_demon_god_sfx_player.pitch_scale = 1.0 + DEMON_GOD_PITCH_PER_ASCENSION * ascension
		_demon_god_sfx_player.play()
	_shake_screen(lerpf(DEMON_GOD_SHAKE_DURATION_MIN, DEMON_GOD_SHAKE_DURATION_MAX, t),
		lerpf(DEMON_GOD_SHAKE_STRENGTH_MIN, DEMON_GOD_SHAKE_STRENGTH_MAX, t))
	var flash_color := Color(1.0, 0.85, 0.2).lerp(Color(1.0, 0.35, 0.1), t)
	_flash_screen(flash_color, lerpf(DEMON_GOD_FLASH_DURATION_MIN, DEMON_GOD_FLASH_DURATION_MAX, t))
	var pos := cat.position
	var burst_count := DEMON_GOD_BURST_BASE_COUNT + ascension
	var tw := cat.create_tween()
	for i in range(burst_count):
		var jitter := Vector2(randf_range(-DEMON_GOD_BURST_JITTER, DEMON_GOD_BURST_JITTER), randf_range(-DEMON_GOD_BURST_JITTER, DEMON_GOD_BURST_JITTER)) * (1.0 + DEMON_GOD_BURST_JITTER_SCALE * t)
		var fx_scale: float = maxf(DEMON_GOD_BURST_FX_SCALE_MIN, (DEMON_GOD_BURST_FX_SCALE_BASE + DEMON_GOD_BURST_FX_SCALE_PER_T * t) - i * DEMON_GOD_BURST_FX_SCALE_STEP)
		tw.tween_callback(func(): Fx.explosion(world, pos + jitter, fx_scale))
		tw.tween_interval(DEMON_GOD_BURST_INTERVAL)
	var title_color := Color(1.0, 0.82, 0.15).lerp(Color(1.0, 0.3, 0.05), t)
	_spawn_demon_god_title_card(DEMON_GOD_TITLES[ascension], title_color)

## Camera-less screen shake: jitters the whole battlefield (this Node2D and
## its Background/Wall/Slots/World children) while leaving the UI CanvasLayer
## untouched, since CanvasLayer nodes ignore their parent's 2D transform.
func _shake_screen(duration: float, strength: float) -> void:
	var steps := maxi(4, int(duration / SCREEN_SHAKE_STEP_DURATION))
	var tw := create_tween()
	for i in range(steps):
		var decay := 1.0 - float(i) / steps
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * decay
		tw.tween_property(self, "position", offset, SCREEN_SHAKE_STEP_DURATION)
	tw.tween_property(self, "position", Vector2.ZERO, SCREEN_SHAKE_STEP_DURATION)

## Full-screen color pulse used to punctuate big moments (currently just the
## Demon God promotion). Added straight to the UI CanvasLayer so it overlays
## everything without blocking input.
func _flash_screen(color: Color, duration: float) -> void:
	var rect := ColorRect.new()
	rect.color = Color(color.r, color.g, color.b, SCREEN_FLASH_ALPHA)
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = SCREEN_FLASH_Z_INDEX
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
	label.offset_left = -TITLE_CARD_OFFSET_X
	label.offset_right = TITLE_CARD_OFFSET_X
	label.offset_top = -TITLE_CARD_OFFSET_Y
	label.offset_bottom = TITLE_CARD_OFFSET_Y
	label.pivot_offset = Vector2(TITLE_CARD_OFFSET_X, TITLE_CARD_OFFSET_Y)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TITLE_CARD_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", TITLE_CARD_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", TITLE_CARD_OUTLINE_SIZE)
	label.z_index = TITLE_CARD_Z_INDEX
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	label.scale = Vector2(TITLE_CARD_START_SCALE, TITLE_CARD_START_SCALE)
	$UI.add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "modulate:a", 1.0, TITLE_CARD_FADE_IN)
	tw.tween_property(label, "scale", Vector2(TITLE_CARD_PUNCH_SCALE, TITLE_CARD_PUNCH_SCALE), TITLE_CARD_SCALE_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(label, "scale", Vector2.ONE, TITLE_CARD_SETTLE).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_interval(TITLE_CARD_HOLD)
	tw.chain().tween_property(label, "modulate:a", 0.0, TITLE_CARD_FADE_OUT)
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
	burst.lifetime = MERGE_FX_LIFETIME
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.global_position = pos
	burst.material = glow_mat
	var mat := ParticleProcessMaterial.new()
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = MERGE_FX_VELOCITY_MIN
	mat.initial_velocity_max = MERGE_FX_VELOCITY_MAX_BASE + MERGE_FX_VELOCITY_PER_TIER * tier
	mat.scale_min = MERGE_FX_SCALE_MIN
	mat.scale_max = MERGE_FX_SCALE_BASE + MERGE_FX_SCALE_PER_TIER * tier
	mat.color = color
	burst.process_material = mat
	world.add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

	var ring := Sprite2D.new()
	ring.texture = Rarity.aura_texture(tier)
	ring.global_position = pos
	ring.modulate = Color(color.r, color.g, color.b, MERGE_RING_ALPHA)
	ring.scale = Vector2(MERGE_RING_START_SCALE, MERGE_RING_START_SCALE)
	ring.material = glow_mat
	world.add_child(ring)
	var ring_tw := ring.create_tween()
	ring_tw.set_parallel(true)
	ring_tw.tween_property(ring, "scale", Vector2(1.0, 1.0) * (1.0 + MERGE_RING_SCALE_PER_TIER * tier), MERGE_RING_TWEEN_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ring_tw.tween_property(ring, "modulate:a", 0.0, MERGE_RING_TWEEN_DURATION)
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
	_play_sfx_if_enabled(_place_sfx_player)

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

## Reads a per-item wave-scaled stat (BASE + PER_WAVE * wave) from ITEM_STAT_DEFS.
func _item_stat(key: String) -> int:
	var def: Dictionary = ITEM_STAT_DEFS[key]
	return int(def.base + def.per_wave * wave)

const ITEM_PLACEMENT_X_SLACK := 60.0

func _try_place_item(pos: Vector2) -> void:
	var id := armed_item
	armed_item = ""
	var bounds := _item_bounds()
	if pos.x < bounds.x or pos.x > bounds.y + ITEM_PLACEMENT_X_SLACK:
		_refresh_item_buttons()
		return
	if not GameState.use_item(id):
		_refresh_item_buttons()
		return
	var row := _nearest_row(pos.y)
	var place := Vector2(clampf(pos.x, bounds.x, bounds.y), _row_y()[row])
	match id:
		"spikes":
			var trap := SpikeTrap.new()
			trap.row = row
			trap.damage_per_tick = _item_stat("spikes")
			trap.position = place
			world.add_child(trap)
		"tnt":
			Fx.explosion(world, pos, 0.3)
			Fx.smoke_explosion(world, pos, 0.35)
			var dmg := _item_stat("tnt")
			for e in get_tree().get_nodes_in_group("enemies"):
				if not e.is_dead() and e.global_position.distance_to(pos) < TNT_BLAST_RADIUS:
					e.take_damage(dmg)
		"boxer":
			var boxer := BoxingCat.new()
			boxer.row = row
			boxer.hp = _item_stat("boxer_hp")
			boxer.punch_damage = _item_stat("boxer_punch")
			boxer.position = place
			world.add_child(boxer)
		"poison":
			var cloud := PoisonCloud.new()
			cloud.row = row
			cloud.damage_per_tick = _item_stat("poison")
			cloud.position = place
			world.add_child(cloud)
	_refresh_item_buttons()

func _nearest_row(y: float) -> int:
	var row_y: Array = _row_y()
	var best := 0
	for r in range(row_y.size()):
		if absf(row_y[r] - y) < absf(row_y[best] - y):
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
	return int(ceil(wall.missing_hp() * (REPAIR_COST_BASE_PCT + REPAIR_COST_PER_WAVE_PCT * wave)))

## Final wave of the current level — level_num levels' worth of BASE_WAVE_CHUNK.
func _win_wave() -> int:
	return BASE_WAVE_CHUNK * level_num

## Position within the current BASE_WAVE_CHUNK-sized escalation chunk (1..BASE_WAVE_CHUNK).
func _wave_in_chunk() -> int:
	return ((wave - 1) % BASE_WAVE_CHUNK) + 1

## How many full chunks of waves have already been survived this level (0-based).
func _wave_chunk() -> int:
	return (wave - 1) / BASE_WAVE_CHUNK

## How many waves into the mid-chunk surge we are (0 before WAVE_SURGE_START_WAVE,
## then 1, 2, 3... each wave after) - see WAVE_SURGE_* constants above.
func _wave_surge_steps() -> int:
	return maxi(0, _wave_in_chunk() - (WAVE_SURGE_START_WAVE - 1))

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
	enemies_to_spawn = WAVE_START_ENEMY_BASE + WAVE_START_ENEMY_PER_CHUNK_WAVE * _wave_in_chunk() \
		+ WAVE_START_ENEMY_PER_LEVEL * (level_num - 1) + WAVE_START_ENEMY_PER_CHUNK * _wave_chunk() \
		+ WAVE_SURGE_ENEMY_PER_WAVE * _wave_surge_steps()
	if boss_to_spawn:
		enemies_to_spawn = int(enemies_to_spawn * BOSS_WAVE_ENEMY_COUNT_MULT)
	spawn_timer = FIRST_SPAWN_DELAY
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
	if _tick_spawn_timer(delta):
		return    # a spawn happened this frame; wave-clear can't also be true
	if _is_wave_cleared():
		_on_wave_cleared()

## Counts down the enemy-spawn timer and spawns the next enemy/boss when it
## elapses. Returns true if a spawn happened this frame.
func _tick_spawn_timer(delta: float) -> bool:
	spawn_timer -= delta
	if spawn_timer > 0.0 or (enemies_to_spawn <= 0 and not boss_to_spawn):
		return false
	if boss_to_spawn:
		boss_to_spawn = false
		_spawn_enemy(true)
	else:
		enemies_to_spawn -= 1
		_spawn_enemy(false)
	spawn_timer = maxf(SPAWN_INTERVAL_BASE - SPAWN_INTERVAL_PER_WAVE * wave - SPAWN_INTERVAL_PER_LEVEL * level_num \
		- WAVE_SURGE_SPAWN_INTERVAL_PER_WAVE * _wave_surge_steps(), SPAWN_INTERVAL_MIN) + randf() * SPAWN_INTERVAL_JITTER
	return true

func _is_wave_cleared() -> bool:
	return enemies_to_spawn <= 0 and not boss_to_spawn and _alive_enemies() == 0 and not break_pending

func _on_wave_cleared() -> void:
	wave_active = false
	GameState.add_gems(1)
	GameState.add_treats(GameState.TREATS_PER_WAVE_CLEAR)
	if wave >= _win_wave() and not endless_mode:
		var already_completed := GameState.is_level_completed(level_num)
		if already_completed:
			# Replaying an already-beaten level: skip the win screen and keep
			# going instead, so a maxed-out roster has somewhere to spend
			# its power rather than ending the match at a fixed wave count.
			endless_mode = true
			var bonus := GameState.complete_level(level_num)
			_show_banner("Endless Mode! +%d Gems" % bonus)
		else:
			_win_match()
			return
	elif endless_mode and wave > _win_wave():
		GameState.add_gems(ENDLESS_BONUS_GEMS)
		var new_best := GameState.record_endless_wave(level_num, wave)
		# Only surface the milestone banner every 5 waves (same cadence as
		# boss waves) — showing it every single wave would fire back-to-back
		# with the "Wave N Incoming!" banner and fight over the same tween.
		if new_best and wave % 5 == 0:
			_show_banner("New Best: Wave %d!" % wave)
	_schedule_wave_break()

func _schedule_wave_break() -> void:
	break_pending = true
	# SceneTreeTimers outlive scene reloads and lambda connections are
	# not auto-cleaned on free, so guard against a freed Main.
	get_tree().create_timer(WAVE_BREAK_SECONDS, false).timeout.connect(func():
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
	var row := randi() % _row_y().size()
	enemy.row = row
	enemy.is_boss = boss
	enemy.wall = wall
	var hp := _compute_enemy_base_hp()
	var reward := _compute_enemy_reward()
	if boss:
		_apply_boss_stats(enemy, hp, reward)
	else:
		_apply_regular_stats(enemy, hp, reward)
	enemy.position = Vector2(_enemy_spawn_x, _row_y()[row] + randf_range(-ENEMY_SPAWN_Y_JITTER, ENEMY_SPAWN_Y_JITTER))
	enemy.reached_end.connect(_on_enemy_reached_end)
	enemy.died.connect(_on_enemy_died)
	world.add_child(enemy)

# Extra late-game ramp on top of the base per-wave/per-level growth: the
# closing waves of each chunk and levels 6-8 push harder so enemy toughness
# keeps pace with the multiplicative cat-damage stacking that peaks there.
func _compute_enemy_base_hp() -> int:
	var wave_in_chunk := _wave_in_chunk()
	var chunk_growth := pow(DECADE_GROWTH, _wave_chunk())
	var late_wave_factor := 1.0
	if wave_in_chunk >= LATE_WAVE_RAMP_THRESHOLD:
		late_wave_factor *= pow(LATE_WAVE_RAMP_FACTOR, wave_in_chunk - (LATE_WAVE_RAMP_THRESHOLD - 1))
	if level_num >= LATE_LEVEL_RAMP_THRESHOLD:
		late_wave_factor *= pow(LATE_LEVEL_RAMP_FACTOR, level_num - (LATE_LEVEL_RAMP_THRESHOLD - 1))
	return int(round(ENEMY_BASE_HP * pow(ENEMY_HP_GROWTH_PER_WAVE, wave_in_chunk - 1) \
		* pow(ENEMY_HP_GROWTH_PER_LEVEL, level_num - 1) * late_wave_factor * chunk_growth * _board_capacity_factor()))

# Rewards scale exponentially like enemy HP does, or buying/merging stalls
# out mid-match while enemies keep compounding.
func _compute_enemy_reward() -> int:
	var wave_in_chunk := _wave_in_chunk()
	var chunk_growth := pow(DECADE_GROWTH, _wave_chunk())
	return int(round((ENEMY_BASE_REWARD * pow(ENEMY_REWARD_GROWTH, wave_in_chunk - 1) * chunk_growth \
		+ ENEMY_REWARD_PER_LEVEL * (level_num - 1)) * ENEMY_REWARD_SCALE))

func _apply_boss_stats(enemy: Enemy, hp: int, reward: int) -> void:
	enemy.enemy_index = (level_num - 1) % BOSS_FOLDER_COUNT + 1
	enemy.max_hp = hp * (BOSS_HP_MULT_FINAL if wave >= _win_wave() else BOSS_HP_MULT_NORMAL)
	enemy.speed = randf_range(BOSS_SPEED_MIN, BOSS_SPEED_MAX)
	enemy.damage = (BOSS_DAMAGE_BASE + BOSS_DAMAGE_PER_WAVE * wave) * BOSS_DAMAGE_SCALE
	enemy.gold_reward = reward * BOSS_GOLD_MULT
	if wave >= _win_wave():
		# A level's final-wave boss both resists (so it survives long enough
		# to matter against a one-shot-everything Demon God cat) and
		# regenerates, demanding sustained DPS instead of one burst.
		enemy.armor_pct = clampf(BOSS_FINAL_ARMOR_MIN + BOSS_FINAL_ARMOR_PER_WAVE * wave, BOSS_FINAL_ARMOR_MIN, BOSS_FINAL_ARMOR_MAX)
		enemy.heal_pulse_pct = BOSS_HEAL_PULSE_PCT
		enemy.heal_pulse_interval = BOSS_HEAL_PULSE_INTERVAL

func _apply_regular_stats(enemy: Enemy, hp: int, reward: int) -> void:
	enemy.enemy_index = (level_num - 1 + randi() % 4) % REGULAR_FOLDER_COUNT + 1
	enemy.max_hp = hp
	enemy.speed = randf_range(REGULAR_SPEED_MIN, REGULAR_SPEED_MAX)
	enemy.damage = REGULAR_DAMAGE_BASE + REGULAR_DAMAGE_PER_WAVE * wave
	enemy.gold_reward = reward
	var wave_in_chunk := _wave_in_chunk()
	if (wave >= _win_wave() or (level_num >= REGULAR_LATE_CHUNK_THRESHOLD and wave_in_chunk >= REGULAR_LATE_CHUNK_THRESHOLD)) and randf() < REGULAR_LATE_ARMOR_CHANCE:
		# Percentage-based so it still matters against a maxed Demon God
		# cat's four-figure hits, not just early-game damage numbers.
		enemy.armor_pct = clampf(REGULAR_ARMOR_MIN + REGULAR_ARMOR_PER_WAVE * wave, REGULAR_ARMOR_MIN, REGULAR_ARMOR_MAX)

func _on_enemy_reached_end(enemy: Enemy) -> void:
	if match_over:
		return
	# A live wall here means the enemy never engaged it in the attack state
	# (e.g. HuntArea's wall sits past LOSE_X) — treat reaching the danger
	# zone as a hit on the wall instead of an instant loss, so a full HP bar
	# never coexists with sudden game over. In Area1-5, the wall is always
	# already broken by the time an enemy walks this far, so this branch is
	# a no-op there and the existing instant-loss-on-broken-wall path holds.
	if wall and not wall.is_dead():
		wall.take_damage(enemy.damage)
		enemy.queue_free()
		if wall.is_dead():
			_lose_match()
		return
	_lose_match()

func _on_enemy_died(enemy: Enemy) -> void:
	coins += enemy.gold_reward
	FloatText.spawn(world, enemy.global_position + Vector2(0, -20), "+%d" % enemy.gold_reward, Color(1, 0.85, 0.3), 16)
	if enemy.is_boss:
		Fx.smoke_explosion(world, enemy.global_position, 0.5)
		_burst_coins(enemy.global_position, BOSS_COIN_COUNT)
		GameState.add_treats(GameState.BOSS_KILL_TREATS)
		GameState.record_boss_kill()
		var card_reward := GameState.award_cards(GameState.BOSS_KILL_CARDS)
		var cards_dropped := 0
		for count in card_reward.values():
			cards_dropped += count
		if cards_dropped > 0:
			FloatText.spawn_banner(world, enemy.global_position + Vector2(0, -40), "+%d Cards!" % cards_dropped, Color(0.75, 0.55, 1.0))
	elif randf() < _coin_drop_chance():
		_spawn_coin_pickup(enemy.global_position, 1)
		_play_sfx_if_enabled(_drop_sfx_player)
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
		var offset := Vector2(randf_range(-COIN_BURST_JITTER_X, COIN_BURST_JITTER_X), randf_range(-COIN_BURST_JITTER_Y, COIN_BURST_JITTER_Y))
		_spawn_coin_pickup(pos + offset, 1)
	_play_sfx_if_enabled(_drop_sfx_player)

func _on_coin_collected(coin: CoinPickup) -> void:
	if match_over:
		return
	coins += coin.value
	_play_sfx_if_enabled(_coin_collect_sfx_player)
	FloatText.spawn(world, coin.global_position + Vector2(0, -20), "+%d" % coin.value, Color(1, 0.85, 0.3), 16)
	_refresh_hud()

# ---------------------------------------------------------------- match end

func _win_match() -> void:
	match_over = true
	_cancel_drag()
	_play_sfx_if_enabled(_level_complete_sfx_player)
	var first_clear := not GameState.is_level_completed(level_num)
	var bonus := GameState.complete_level(level_num)
	win_bonus_label.text = "+%d" % bonus
	var treats_bonus := GameState.FIRST_CLEAR_TREATS if first_clear else GameState.REPLAY_CLEAR_TREATS
	var total_cards := 0
	for count in GameState.last_cards_awarded.values():
		total_cards += int(count)
	win_cards_label.text = "+%d Cat Cards   +%d Treats" % [total_cards, treats_bonus]
	get_tree().paused = true
	win_panel.visible = true

func _lose_match() -> void:
	match_over = true
	_cancel_drag()
	get_tree().paused = true
	lose_panel.visible = true

func _on_continue_pressed() -> void:
	get_tree().paused = false
	GameState.hunt_mode = false
	SceneTransition.change_scene("res://scenes/Lobby.tscn")

func _on_restart_pressed() -> void:
	get_tree().paused = false
	SceneTransition.reload_scene()

func _on_home_pressed() -> void:
	get_tree().paused = false
	GameState.hunt_mode = false
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
	if endless_mode and wave > _win_wave():
		wave_label.text = "Wave %d (Endless)" % wave
	else:
		wave_label.text = "Wave %d / %d" % [maxi(wave, 1), _win_wave()]
	repair_cost_label.text = _fmt(repair_cost())
	var can_repair := wall.missing_hp() > 0 and coins >= repair_cost()
	repair_button.self_modulate = Color.WHITE if can_repair else Color(0.55, 0.55, 0.55)
	_refresh_item_buttons()

func _fmt(n: int) -> String:
	if n >= FMT_K_THRESHOLD:
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
	button.self_modulate = DENY_FLASH_COLOR_BUTTON
	tw.tween_interval(DENY_FLASH_DURATION_BUTTON)
	tw.tween_callback(_refresh_hud)

func _flash_deny_slot(slot: Slot) -> void:
	slot.set_highlight(true, DENY_FLASH_COLOR_SLOT)
	var tw := create_tween()
	tw.tween_interval(DENY_FLASH_DURATION_SLOT)
	tw.tween_callback(slot.set_highlight.bind(false))

func _show_banner(text: String) -> void:
	wave_banner.text = text
	wave_banner.visible = true
	wave_banner.modulate.a = 0.0
	wave_banner.scale = BANNER_START_SCALE
	var tw := wave_banner.create_tween()
	tw.set_parallel(true)
	tw.tween_property(wave_banner, "modulate:a", 1.0, BANNER_FADE_IN)
	tw.tween_property(wave_banner, "scale", Vector2.ONE, BANNER_SCALE_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(BANNER_HOLD)
	tw.chain().tween_property(wave_banner, "modulate:a", 0.0, BANNER_FADE_OUT)
	tw.chain().tween_callback(func(): wave_banner.visible = false)
