extends Node

## Autoload singleton: persistent player profile + economy shared between
## the Lobby (meta game) and Main (match). Saved as a ConfigFile so the
## format stays human-readable for debugging.

signal gems_changed(gems: int)
signal cards_awarded(rewards: Dictionary)

const BGM_PATH := "res://sfx/cat-defense-theme.mp3"
const BATTLE_BGM_PATH := "res://bg music/cat-defense-ingame battle.mp3"

var _music_player: AudioStreamPlayer

const SAVE_PATH := "user://savegame.cfg"

const MAX_LEVEL := 8            # level buttons on the lobby map
const CAT_COUNT := 15           # C1..C15 character tiers
const MAX_ITEM_COUNT := 5
const ITEM_IDS := ["spikes", "tnt", "boxer"]
const ITEM_GEM_COST := 25
const CHARACTER_UNLOCK_COSTS := [0, 100, 200, 400, 800, 1200, 1600, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500]
const DAILY_BASE_GEMS := 20
const DAILY_MAX_STREAK := 5
const FIRST_CLEAR_GEMS := 150
const REPLAY_CLEAR_GEMS := 30

# --- card-collection cat leveling ---
const MAX_CAT_LEVEL := 20
const CARDS_PER_CHEST := 10          # cards handed out per level-win chest
const CARD_BASE_COST := 10           # cards needed to go from level 1 -> 2
const CARD_COST_STEP := 10           # extra cards required per subsequent level
const GEM_BASE_COST := 20            # gems needed to go from level 1 -> 2
const GEM_COST_GROWTH := 1.5         # gem cost multiplier per level

# --- persistent state ---
var gems: int = 50
var unlocked_level: int = 1                 # highest level the player may enter
var completed_levels: Array = []            # level numbers beaten at least once
var items: Dictionary = {"spikes": 2, "tnt": 3, "boxer": 2}
var cat_data: Array = []                    # per-character {unlocked, level, current_cards}, see _default_cat_data()
var owned_characters: Array = [1]           # purchased character indices (1-based), C1 free
var max_merge_character: int = 1            # best cat character ever reached in a match
var music_on: bool = true
var sound_on: bool = true
var vibra_on: bool = true
var daily_streak: int = 0
var daily_last_claim: String = ""           # "YYYY-MM-DD"

# --- transient (not saved) ---
var selected_level: int = 1                 # set by the lobby before entering Main
var last_cards_awarded: Dictionary = {}     # {char_index: count} from the most recent chest

func _ready() -> void:
	cat_data = _default_cat_data()
	load_save()
	_setup_music()
	_setup_theme_font()

func _setup_theme_font() -> void:
	var font: FontFile = load("res://fonts/LuckiestGuy.ttf")
	if font:
		font.fallbacks = [ThemeDB.fallback_font]
		get_tree().root.theme = Theme.new()
		get_tree().root.theme.default_font = font

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

func is_cat_unlocked(char_index: int) -> bool:
	var unlocked := is_character_purchased(char_index) or max_merge_character >= char_index
	if unlocked:
		_mark_cat_unlocked(char_index)
	return unlocked

func is_character_purchased(char_index: int) -> bool:
	return char_index == 1 or char_index in owned_characters

func character_unlock_cost(char_index: int) -> int:
	return CHARACTER_UNLOCK_COSTS[char_index - 1] if char_index <= CAT_COUNT else 0

func purchase_character(char_index: int) -> bool:
	if is_character_purchased(char_index):
		return false
	if char_index < 1 or char_index > CAT_COUNT:
		return false
	var cost := character_unlock_cost(char_index)
	if not spend_gems(cost):
		return false
	owned_characters.append(char_index)
	_mark_cat_unlocked(char_index)
	save()
	return true

func highest_owned_character() -> int:
	var highest := 1
	for i in owned_characters:
		highest = maxi(highest, i)
	for i in range(2, CAT_COUNT + 1):
		if max_merge_character >= i:
			highest = maxi(highest, i)
	return highest

## Called during a match whenever a higher cat character appears on the board.
func record_merge_character(character: int) -> void:
	if character > max_merge_character:
		max_merge_character = character
		for i in range(2, CAT_COUNT + 1):
			if max_merge_character >= i:
				_mark_cat_unlocked(i)
		save()

# ---------------------------------------------------------------- cat cards / leveling

## Per-character save entry: {"unlocked": bool, "level": int, "current_cards": int}.
func _default_cat_data() -> Array:
	var data: Array = []
	for i in CAT_COUNT:
		data.append({"unlocked": i == 0, "level": 1, "current_cards": 0})
	return data

func _mark_cat_unlocked(char_index: int) -> void:
	if char_index < 1 or char_index > CAT_COUNT:
		return
	cat_data[char_index - 1]["unlocked"] = true

func cat_level(char_index: int) -> int:
	return int(cat_data[char_index - 1]["level"])

func cat_cards(char_index: int) -> int:
	return int(cat_data[char_index - 1]["current_cards"])

## Cards required to advance from the cat's current level to the next.
func cat_cards_required(char_index: int) -> int:
	var level := cat_level(char_index)
	if level >= MAX_CAT_LEVEL:
		return 0
	return CARD_BASE_COST + (level - 1) * CARD_COST_STEP

## Gems required to advance from the cat's current level to the next.
func cat_level_gem_cost(char_index: int) -> int:
	var level := cat_level(char_index)
	if level >= MAX_CAT_LEVEL:
		return 0
	return int(round(GEM_BASE_COST * pow(GEM_COST_GROWTH, level - 1)))

func can_upgrade_cat_level(char_index: int) -> bool:
	if not is_cat_unlocked(char_index) or cat_level(char_index) >= MAX_CAT_LEVEL:
		return false
	return cat_cards(char_index) >= cat_cards_required(char_index) and gems >= cat_level_gem_cost(char_index)

## Spends cards + gems and levels the cat up. Returns false if requirements aren't met.
func upgrade_cat(char_index: int) -> bool:
	if not can_upgrade_cat_level(char_index):
		return false
	var cards_cost := cat_cards_required(char_index)
	var gem_cost := cat_level_gem_cost(char_index)
	if not spend_gems(gem_cost):
		return false
	var entry: Dictionary = cat_data[char_index - 1]
	entry["current_cards"] = int(entry["current_cards"]) - cards_cost
	entry["level"] = int(entry["level"]) + 1
	save()
	return true

## Randomly distributes `total_cards` one-at-a-time among currently unlocked cats.
## Returns {char_index: cards_awarded} so the UI can show what dropped.
func award_cards(total_cards: int = CARDS_PER_CHEST) -> Dictionary:
	var pool: Array = []
	for i in range(1, CAT_COUNT + 1):
		if bool(cat_data[i - 1]["unlocked"]):
			pool.append(i)
	var rewards: Dictionary = {}
	if pool.is_empty():
		return rewards
	for i in total_cards:
		var char_index: int = pool[randi() % pool.size()]
		cat_data[char_index - 1]["current_cards"] = int(cat_data[char_index - 1]["current_cards"]) + 1
		rewards[char_index] = int(rewards.get(char_index, 0)) + 1
	save()
	return rewards

## Permanent damage multiplier a character earns from card-collection leveling.
func cat_damage_multiplier(char_index: int) -> float:
	return 1.0 + 0.1 * (cat_level(char_index) - 1)

# ---------------------------------------------------------------- levels

func is_level_unlocked(level: int) -> bool:
	return level <= unlocked_level

func is_level_completed(level: int) -> bool:
	return level in completed_levels

## Returns the gem bonus earned for beating `level`. Also rolls a card chest
## (see `last_cards_awarded` / `cards_awarded` signal for the drop breakdown).
func complete_level(level: int) -> int:
	var first_clear := not is_level_completed(level)
	if first_clear:
		completed_levels.append(level)
	if level >= unlocked_level and level < MAX_LEVEL:
		unlocked_level = level + 1
	var bonus := FIRST_CLEAR_GEMS if first_clear else REPLAY_CLEAR_GEMS
	add_gems(bonus)  # also saves
	last_cards_awarded = award_cards(CARDS_PER_CHEST)
	cards_awarded.emit(last_cards_awarded)
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
				- Time.get_unix_time_from_datetime_string(daily_last_claim)) / 86400.0
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

func set_bgm(path: String, fade_duration: float = 0.5) -> void:
	if not is_instance_valid(_music_player):
		return
	if fade_duration <= 0:
		_music_player.stop()
		_music_player.stream = load(path)
		if music_on:
			_music_player.play()
		return
	var tween := create_tween().set_ease(Tween.EASE_IN)
	tween.tween_property(_music_player, "volume_db", -80.0, fade_duration)
	await tween.finished
	_music_player.stop()
	_music_player.volume_db = 0.0
	_music_player.stream = load(path)
	if music_on:
		_music_player.play()

# ---------------------------------------------------------------- persistence

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "gems", gems)
	cfg.set_value("profile", "unlocked_level", unlocked_level)
	cfg.set_value("profile", "completed_levels", completed_levels)
	cfg.set_value("profile", "items", items)
	cfg.set_value("profile", "cat_data", cat_data)
	cfg.set_value("profile", "owned_characters", owned_characters)
	cfg.set_value("profile", "max_merge_character", max_merge_character)
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
	max_merge_character = cfg.get_value("profile", "max_merge_character", -1)
	if max_merge_character == -1:
		# migration: derive from the old fine-grained level scale (4 levels/character)
		var legacy_level: int = cfg.get_value("profile", "max_merge_level", 1)
		max_merge_character = clampi((legacy_level - 1) / 4 + 1, 1, CAT_COUNT)
	owned_characters = cfg.get_value("profile", "owned_characters", [])
	var legacy_pips: Array = cfg.get_value("profile", "cat_upgrades", [])
	var saved_cat_data: Array = cfg.get_value("profile", "cat_data", [])
	if saved_cat_data.is_empty():
		# migration: rebuild from the legacy pip-upgrade save (or fresh defaults)
		cat_data = _default_cat_data()
		for i in CAT_COUNT:
			if i < legacy_pips.size() and legacy_pips[i] != null:
				cat_data[i]["level"] = int(legacy_pips[i]) + 1
	else:
		saved_cat_data.resize(CAT_COUNT)
		for i in CAT_COUNT:
			if saved_cat_data[i] == null:
				saved_cat_data[i] = {"unlocked": i == 0, "level": 1, "current_cards": 0}
		cat_data = saved_cat_data
	if owned_characters.is_empty():
		# migration: populate from max_merge_character for existing saves
		for i in range(2, CAT_COUNT + 1):
			if max_merge_character >= i:
				owned_characters.append(i)
		if owned_characters.is_empty():
			owned_characters.append(1)
	for i in range(1, CAT_COUNT + 1):
		if is_character_purchased(i) or max_merge_character >= i:
			_mark_cat_unlocked(i)
	music_on = cfg.get_value("settings", "music_on", music_on)
	sound_on = cfg.get_value("settings", "sound_on", sound_on)
	vibra_on = cfg.get_value("settings", "vibra_on", vibra_on)
	daily_streak = cfg.get_value("daily", "streak", daily_streak)
	daily_last_claim = cfg.get_value("daily", "last_claim", daily_last_claim)
