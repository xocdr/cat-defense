extends Node

## Autoload singleton: persistent player profile + economy shared between
## the Lobby (meta game) and Main (match). Saved as a ConfigFile so the
## format stays human-readable for debugging.

signal gems_changed(gems: int)

const BGM_PATH := "res://sfx/cat-defense-theme.mp3"

var _music_player: AudioStreamPlayer

const SAVE_PATH := "user://savegame.cfg"

const MAX_LEVEL := 8            # level buttons on the lobby map
const CAT_COUNT := 15           # C1..C15 character tiers
const MAX_UPGRADE_PIPS := 5
const MAX_ITEM_COUNT := 5
const ITEM_IDS := ["spikes", "tnt", "boxer"]
const ITEM_GEM_COST := 25
const UPGRADE_GEM_COSTS := [20, 40, 80, 160, 320]  # cost of pip 1..5
const DAILY_BASE_GEMS := 20
const DAILY_MAX_STREAK := 5
const FIRST_CLEAR_GEMS := 150
const REPLAY_CLEAR_GEMS := 30

# --- persistent state ---
var gems: int = 50
var unlocked_level: int = 1                 # highest level the player may enter
var completed_levels: Array = []            # level numbers beaten at least once
var items: Dictionary = {"spikes": 2, "tnt": 3, "boxer": 2}
var cat_upgrades: Array = []                # pips per character, 0..MAX_UPGRADE_PIPS
var max_merge_level: int = 1                # best cat level ever reached in a match
var music_on: bool = true
var sound_on: bool = true
var vibra_on: bool = true
var daily_streak: int = 0
var daily_last_claim: String = ""           # "YYYY-MM-DD"

# --- transient (not saved) ---
var selected_level: int = 1                 # set by the lobby before entering Main

func _ready() -> void:
	cat_upgrades.resize(CAT_COUNT)
	cat_upgrades.fill(0)
	load_save()
	_setup_music()

# ---------------------------------------------------------------- gems

func add_gems(amount: int) -> void:
	gems += amount
	gems_changed.emit(gems)
	save()

func spend_gems(amount: int) -> bool:
	if gems < amount:
		return false
	gems -= amount
	gems_changed.emit(gems)
	save()
	return true

# ---------------------------------------------------------------- items

func item_count(id: String) -> int:
	return int(items.get(id, 0))

func buy_item(id: String) -> bool:
	if item_count(id) >= MAX_ITEM_COUNT:
		return false
	if not spend_gems(ITEM_GEM_COST):
		return false
	items[id] = item_count(id) + 1
	save()
	return true

func use_item(id: String) -> bool:
	if item_count(id) <= 0:
		return false
	items[id] = item_count(id) - 1
	save()
	return true

# ---------------------------------------------------------------- cat upgrades

## Character index i (1-based) is shown in the lobby once the player has
## reached its first merge level (1, 5, 9, ... = 4*(i-1)+1) in any match.
func cat_unlock_level(char_index: int) -> int:
	return 4 * (char_index - 1) + 1

func is_cat_unlocked(char_index: int) -> bool:
	return max_merge_level >= cat_unlock_level(char_index)

func cat_pips(char_index: int) -> int:
	return int(cat_upgrades[char_index - 1])

func cat_upgrade_cost(char_index: int) -> int:
	var pips := cat_pips(char_index)
	if pips >= MAX_UPGRADE_PIPS:
		return 0
	return UPGRADE_GEM_COSTS[pips]

func upgrade_cat(char_index: int) -> bool:
	if not is_cat_unlocked(char_index) or cat_pips(char_index) >= MAX_UPGRADE_PIPS:
		return false
	if not spend_gems(cat_upgrade_cost(char_index)):
		return false
	cat_upgrades[char_index - 1] += 1
	save()
	return true

## Permanent damage multiplier a character earns from lobby upgrades.
func cat_damage_multiplier(char_index: int) -> float:
	return 1.0 + 0.1 * cat_pips(char_index)

## Called during a match whenever a higher cat level appears on the board.
func record_merge_level(level: int) -> void:
	if level > max_merge_level:
		max_merge_level = level
		save()

# ---------------------------------------------------------------- levels

func is_level_unlocked(level: int) -> bool:
	return level <= unlocked_level

func is_level_completed(level: int) -> bool:
	return level in completed_levels

## Returns the gem bonus earned for beating `level`.
func complete_level(level: int) -> int:
	var first_clear := not is_level_completed(level)
	if first_clear:
		completed_levels.append(level)
	if level >= unlocked_level and level < MAX_LEVEL:
		unlocked_level = level + 1
	var bonus := FIRST_CLEAR_GEMS if first_clear else REPLAY_CLEAR_GEMS
	add_gems(bonus)  # also saves
	return bonus

# ---------------------------------------------------------------- daily gift

func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func can_claim_daily() -> bool:
	return daily_last_claim != _today()

## Claims the daily gift and returns the gems granted (0 if already claimed).
func claim_daily() -> int:
	if not can_claim_daily():
		return 0
	if daily_last_claim != "":
		var gap_days := (Time.get_unix_time_from_datetime_string(_today())
				- Time.get_unix_time_from_datetime_string(daily_last_claim)) / 86400
		if gap_days > 1:
			daily_streak = 0  # missed a day: streak starts over
	daily_streak = clampi(daily_streak + 1, 1, DAILY_MAX_STREAK)
	daily_last_claim = _today()
	var reward := DAILY_BASE_GEMS * daily_streak
	add_gems(reward)  # also saves
	return reward

# ---------------------------------------------------------------- settings

func set_toggle(key: String, value: bool) -> void:
	match key:
		"music":
			music_on = value
			_update_music()
		"sound": sound_on = value
		"vibra": vibra_on = value
	save()

func _setup_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.stream = load(BGM_PATH)
	_music_player.bus = "Master"
	_music_player.finished.connect(_music_player.play)
	add_child(_music_player)
	_update_music()

func _update_music() -> void:
	if not is_instance_valid(_music_player):
		return
	if music_on and not _music_player.playing:
		_music_player.play()
	elif not music_on and _music_player.playing:
		_music_player.stop()

# ---------------------------------------------------------------- persistence

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "gems", gems)
	cfg.set_value("profile", "unlocked_level", unlocked_level)
	cfg.set_value("profile", "completed_levels", completed_levels)
	cfg.set_value("profile", "items", items)
	cfg.set_value("profile", "cat_upgrades", cat_upgrades)
	cfg.set_value("profile", "max_merge_level", max_merge_level)
	cfg.set_value("settings", "music_on", music_on)
	cfg.set_value("settings", "sound_on", sound_on)
	cfg.set_value("settings", "vibra_on", vibra_on)
	cfg.set_value("daily", "streak", daily_streak)
	cfg.set_value("daily", "last_claim", daily_last_claim)
	cfg.save(SAVE_PATH)

func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	gems = cfg.get_value("profile", "gems", gems)
	unlocked_level = cfg.get_value("profile", "unlocked_level", unlocked_level)
	completed_levels = cfg.get_value("profile", "completed_levels", completed_levels)
	items = cfg.get_value("profile", "items", items)
	var saved_upgrades: Array = cfg.get_value("profile", "cat_upgrades", cat_upgrades)
	saved_upgrades.resize(CAT_COUNT)
	for i in CAT_COUNT:
		if saved_upgrades[i] == null:
			saved_upgrades[i] = 0
	cat_upgrades = saved_upgrades
	max_merge_level = cfg.get_value("profile", "max_merge_level", max_merge_level)
	music_on = cfg.get_value("settings", "music_on", music_on)
	sound_on = cfg.get_value("settings", "sound_on", sound_on)
	vibra_on = cfg.get_value("settings", "vibra_on", vibra_on)
	daily_streak = cfg.get_value("daily", "streak", daily_streak)
	daily_last_claim = cfg.get_value("daily", "last_claim", daily_last_claim)
