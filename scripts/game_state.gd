extends Node

## Autoload singleton: persistent player profile + economy shared between
## the Lobby (meta game) and Main (match). Saved as a ConfigFile so the
## format stays human-readable for debugging.

signal gems_changed(gems: int)
signal treats_changed(treats: int)
signal achievement_unlocked(id: String)

const BGM_PATH := "res://sfx/cat-defense-theme.mp3"
const BATTLE_BGM_PATH := "res://bg music/cat-defense-ingame battle.mp3"

var _music_player: AudioStreamPlayer

const SAVE_PATH := "user://savegame.cfg"

const MAX_LEVEL := 8            # level buttons on the lobby map
const CAT_COUNT := 15           # C1..C15 character tiers
const MAX_ITEM_COUNT := 5
const ITEM_GEM_COST := 25
const CHARACTER_UNLOCK_COSTS := [0, 100, 200, 400, 800, 1200, 1600, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500]
const DAILY_BASE_GEMS := 20
const DAILY_MAX_STREAK := 5
const FIRST_CLEAR_GEMS := 150
const REPLAY_CLEAR_GEMS := 30

# --- treats: earned in-match (not purchasable with real money), spent only
# on character unlocks in the Upgrades panel. Kept separate from gems so
# character progression stays free-to-play even if gems are ever sold. ---
const TREATS_PER_WAVE_CLEAR := 5
const FIRST_CLEAR_TREATS := 100
const REPLAY_CLEAR_TREATS := 25
const BOSS_KILL_TREATS := 15         # bonus treats on top of TREATS_PER_WAVE_CLEAR whenever a boss dies

# --- card-collection cat leveling ---
enum Stat { DAMAGE, FIRE_RATE, RANGE }
const STAT_KEYS := {
	Stat.DAMAGE: {"level": "level", "cards": "current_cards"},
	Stat.FIRE_RATE: {"level": "fire_rate_level", "cards": "fire_rate_cards"},
	Stat.RANGE: {"level": "range_level", "cards": "range_cards"},
}
const MAX_CAT_LEVEL := 20
const CARDS_PER_CHEST := 10          # base cards handed out per level-win chest (see cards_per_chest())
const CARDS_PER_UNLOCKED_CAT := 3    # extra chest cards per cat beyond the first, so per-cat card
									   # income doesn't dilute as the roster grows (see cards_per_chest())
const CARD_BASE_COST := 10           # cards needed to go from level 1 -> 2
const CARD_COST_STEP := 10           # extra cards required per subsequent level
const GEM_BASE_COST := 20            # gems needed to go from level 1 -> 2
const GEM_COST_GROWTH := 1.40        # gem cost multiplier per level
const BOSS_KILL_CARDS := 3           # cards dropped whenever a boss enemy dies
const CARD_PACK_GEM_COST := 50       # gem cost of the Upgrades-panel card pack
const CARD_PACK_CARDS := 15          # cards granted by a card pack purchase
const AD_CARD_REWARD := 8            # cards granted by the once-a-day ad-reward chest
const FIRE_RATE_COOLDOWN_FLOOR := 0.4  # upgrades can shrink cooldown to at most 40% of base
const MAX_RANGE_BONUS := 1.0           # range upgrades can at most double base range (100% bonus)
const HUNT_MODE_STAT_DAMPING := 0.5    # fire-rate/range upgrade bonuses apply at half strength in
										 # Hunt mode (rather than not at all) so cards spent on those
										 # tracks are never fully wasted for Hunt-focused players

# --- cosmetic cat skins ---
# {char_index: [{"id": String, "name": String, "cost": int, "dir_suffix": String}, ...]}.
# Every character always has a free "default" entry (dir_suffix "" resolves to the
# existing Png/Characters/C<N> art); new skins are appended here as art is commissioned.
const SKIN_CATALOG := {}
const DEFAULT_SKIN_ID := "default"

# --- achievements ---
# metric keys read by achievement_progress(): "levels_completed", "characters_owned",
# "max_merge_character", "boss_kills", "gems_earned", "treats_earned", "daily_streak",
# "max_stat_level". Rewards are paid once, on claim_achievement().
const ACHIEVEMENTS := [
	{"id": "first_steps", "name": "First Steps", "desc": "Complete Level 1", "metric": "levels_completed", "goal": 1, "reward_gems": 50},
	{"id": "veteran", "name": "Veteran", "desc": "Complete all 8 levels", "metric": "levels_completed", "goal": MAX_LEVEL, "reward_gems": 300},
	{"id": "collector", "name": "Collector", "desc": "Unlock 5 cat characters", "metric": "characters_owned", "goal": 5, "reward_gems": 200},
	{"id": "full_roster", "name": "Full Roster", "desc": "Unlock all 15 cat characters", "metric": "characters_owned", "goal": 15, "reward_gems": 1000},
	{"id": "merge_master", "name": "Merge Master", "desc": "Reach cat character C10 in a match", "metric": "max_merge_character", "goal": 10, "reward_gems": 250},
	{"id": "apex_predator", "name": "Apex Predator", "desc": "Reach cat character C15 in a match", "metric": "max_merge_character", "goal": 15, "reward_gems": 500},
	{"id": "boss_hunter", "name": "Boss Hunter", "desc": "Defeat 10 boss enemies", "metric": "boss_kills", "goal": 10, "reward_gems": 150},
	{"id": "boss_slayer", "name": "Boss Slayer", "desc": "Defeat 50 boss enemies", "metric": "boss_kills", "goal": 50, "reward_gems": 400},
	{"id": "gem_hoarder", "name": "Gem Hoarder", "desc": "Earn 5000 gems in total", "metric": "gems_earned", "goal": 5000, "reward_gems": 100},
	{"id": "treat_lover", "name": "Treat Lover", "desc": "Earn 1000 treats in total", "metric": "treats_earned", "goal": 1000, "reward_gems": 100},
	{"id": "loyal", "name": "Loyal", "desc": "Reach a 5-day daily-gift streak", "metric": "daily_streak", "goal": DAILY_MAX_STREAK, "reward_gems": 100},
	{"id": "upgrade_enthusiast", "name": "Upgrade Enthusiast", "desc": "Level any cat stat to level 10", "metric": "max_stat_level", "goal": 10, "reward_gems": 150},
]

# --- persistent state ---
var gems: int = 50
var treats: int = 0
var unlocked_level: int = 1                 # highest level the player may enter
var completed_levels: Array = []            # level numbers beaten at least once
var items: Dictionary = {"spikes": 2, "tnt": 3, "boxer": 2, "poison": 2}
var cat_data: Array = []                    # per-character {unlocked, level, current_cards, fire_rate_level, fire_rate_cards, range_level, range_cards}, see _default_cat_data()
var owned_characters: Array = [1]           # purchased character indices (1-based), C1 free
var max_merge_character: int = 1            # best cat character ever reached in a match
var best_endless_wave: Dictionary = {}      # {level: best wave reached past that level's final wave}
var music_on: bool = true
var sound_on: bool = true
var vibra_on: bool = true
var daily_streak: int = 0
var daily_last_claim: String = ""           # "YYYY-MM-DD"
var ad_cards_last_claim: String = ""        # "YYYY-MM-DD", last ad-reward card chest claim
var tutorial_seen: bool = false             # first-launch tutorial completed/skipped
var owned_skins: Dictionary = {}            # {char_index: [skin_id, ...]}, "default" always implicitly owned
var equipped_skins: Dictionary = {}         # {char_index: skin_id}, defaults to "default"
var claimed_achievements: Array = []        # ids of achievements whose reward has been claimed
var stat_boss_kills: int = 0                # lifetime boss enemies defeated, across all matches
var stat_gems_earned: int = 0               # lifetime gems earned (not counting spending), for achievements
var stat_treats_earned: int = 0             # lifetime treats earned (not counting spending), for achievements
var best_daily_streak: int = 0              # highest daily_streak ever reached (daily_streak itself can reset)

# --- transient (not saved) ---
var selected_level: int = 1                 # set by the lobby before entering Main
var hunt_mode: bool = false                 # set by the lobby's HUNT button; forces Main onto MainArea.png
var last_cards_awarded: Dictionary = {}     # {char_index: count} from the most recent chest
var tutorial_step: int = 0                  # cursor into TutorialSteps.STEPS, resets on relaunch

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
	if amount > 0:
		stat_gems_earned += amount
	gems_changed.emit(gems)
	save()

func spend_gems(amount: int) -> bool:
	if gems < amount:
		return false
	gems -= amount
	gems_changed.emit(gems)
	save()
	return true

# ---------------------------------------------------------------- treats

func add_treats(amount: int) -> void:
	treats += amount
	if amount > 0:
		stat_treats_earned += amount
	treats_changed.emit(treats)
	save()

## Called whenever a boss enemy dies in a match; feeds the boss-kill achievements.
func record_boss_kill() -> void:
	stat_boss_kills += 1
	save()

func spend_treats(amount: int) -> bool:
	if treats < amount:
		return false
	treats -= amount
	treats_changed.emit(treats)
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
	if not spend_treats(cost):
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

# ---------------------------------------------------------------- cosmetic skins

func _skin_catalog_for(char_index: int) -> Array:
	return SKIN_CATALOG.get(char_index, [])

func _skin_entry(char_index: int, skin_id: String) -> Dictionary:
	for entry in _skin_catalog_for(char_index):
		if entry["id"] == skin_id:
			return entry
	return {}

func is_skin_owned(char_index: int, skin_id: String) -> bool:
	if skin_id == DEFAULT_SKIN_ID:
		return true
	return skin_id in owned_skins.get(char_index, [])

func can_purchase_skin(char_index: int, skin_id: String) -> bool:
	if is_skin_owned(char_index, skin_id):
		return false
	var entry := _skin_entry(char_index, skin_id)
	if entry.is_empty():
		return false
	return gems >= int(entry["cost"])

func purchase_skin(char_index: int, skin_id: String) -> bool:
	if not can_purchase_skin(char_index, skin_id):
		return false
	var entry := _skin_entry(char_index, skin_id)
	if not spend_gems(int(entry["cost"])):
		return false
	var owned: Array = owned_skins.get(char_index, [])
	owned.append(skin_id)
	owned_skins[char_index] = owned
	save()
	return true

func equip_skin(char_index: int, skin_id: String) -> bool:
	if not is_skin_owned(char_index, skin_id):
		return false
	equipped_skins[char_index] = skin_id
	save()
	return true

func equipped_skin_for(char_index: int) -> String:
	return equipped_skins.get(char_index, DEFAULT_SKIN_ID)

## Folder-name suffix for the given character/skin, e.g. "" for the default skin
## (resolves to the existing Png/Characters/C<N> art) or "_Halloween" for a
## commissioned alternate at Png/Characters/C<N>_Halloween.
func skin_dir_suffix(char_index: int, skin_id: String) -> String:
	return String(_skin_entry(char_index, skin_id).get("dir_suffix", ""))

## Idle-portrait path for the character's currently equipped skin. Shared by the
## Upgrades row portrait and any other UI that needs a static preview image, so
## the skin-aware path convention can't drift between call sites.
func skin_portrait_path(char_index: int) -> String:
	var suffix := skin_dir_suffix(char_index, equipped_skin_for(char_index))
	return "res://Png/Characters/C%d%s/Idle/Character%d-Idle_00.png" % [char_index, suffix, char_index]

# ---------------------------------------------------------------- cat cards / leveling

## Per-character save entry: {"unlocked": bool, "level": int, "current_cards": int,
## "fire_rate_level": int, "fire_rate_cards": int, "range_level": int, "range_cards": int}.
func _default_cat_data() -> Array:
	var data: Array = []
	for i in CAT_COUNT:
		data.append({
			"unlocked": i == 0, "level": 1, "current_cards": 0,
			"fire_rate_level": 1, "fire_rate_cards": 0,
			"range_level": 1, "range_cards": 0,
		})
	return data

## Fills in any stat fields missing from an older save (added after that save was written).
func _backfill_cat_data_defaults() -> void:
	for entry in cat_data:
		for key in ["level", "current_cards", "fire_rate_level", "fire_rate_cards", "range_level", "range_cards"]:
			if not entry.has(key):
				entry[key] = 1 if key.ends_with("_level") or key == "level" else 0

func _mark_cat_unlocked(char_index: int) -> void:
	if char_index < 1 or char_index > CAT_COUNT:
		return
	cat_data[char_index - 1]["unlocked"] = true

func cat_stat_level(char_index: int, stat: int) -> int:
	return int(cat_data[char_index - 1][STAT_KEYS[stat]["level"]])

func cat_stat_cards(char_index: int, stat: int) -> int:
	return int(cat_data[char_index - 1][STAT_KEYS[stat]["cards"]])

## Cards required to advance a given stat from the cat's current level to the next.
func cat_stat_cards_required(char_index: int, stat: int) -> int:
	var level := cat_stat_level(char_index, stat)
	if level >= MAX_CAT_LEVEL:
		return 0
	return CARD_BASE_COST + (level - 1) * CARD_COST_STEP

## Gems required to advance a given stat from the cat's current level to the next.
func cat_stat_gem_cost(char_index: int, stat: int) -> int:
	var level := cat_stat_level(char_index, stat)
	if level >= MAX_CAT_LEVEL:
		return 0
	return int(round(GEM_BASE_COST * pow(GEM_COST_GROWTH, level - 1)))

func can_upgrade_cat_stat(char_index: int, stat: int) -> bool:
	if not is_cat_unlocked(char_index) or cat_stat_level(char_index, stat) >= MAX_CAT_LEVEL:
		return false
	return cat_stat_cards(char_index, stat) >= cat_stat_cards_required(char_index, stat) \
		and gems >= cat_stat_gem_cost(char_index, stat)

## Spends cards + gems and levels up the given stat. Returns false if requirements aren't met.
func upgrade_cat_stat(char_index: int, stat: int) -> bool:
	if not can_upgrade_cat_stat(char_index, stat):
		return false
	var cards_cost := cat_stat_cards_required(char_index, stat)
	var gem_cost := cat_stat_gem_cost(char_index, stat)
	if not spend_gems(gem_cost):
		return false
	var entry: Dictionary = cat_data[char_index - 1]
	var keys: Dictionary = STAT_KEYS[stat]
	entry[keys["cards"]] = int(entry[keys["cards"]]) - cards_cost
	entry[keys["level"]] = int(entry[keys["level"]]) + 1
	save()
	return true

## Picks which stat (damage/fire-rate/range) a card should land on for the given cat,
## pity-weighting toward whichever stat is furthest behind the cat's highest-leveled
## stat so a cat's three stats stay roughly in step instead of drifting on bad luck.
func _pick_pity_stat(char_index: int) -> int:
	var entry: Dictionary = cat_data[char_index - 1]
	var stats: Array = STAT_KEYS.keys()
	var levels: Array = []
	var max_level := 0
	for stat in stats:
		var lvl: int = int(entry[STAT_KEYS[stat]["level"]])
		levels.append(lvl)
		max_level = max(max_level, lvl)
	var weights: Array = []
	var total_weight := 0
	for lvl in levels:
		var w: int = (max_level - lvl) + 1
		weights.append(w)
		total_weight += w
	var roll := randi() % total_weight
	for i in stats.size():
		roll -= weights[i]
		if roll < 0:
			return stats[i]
	return stats[stats.size() - 1]

## Chest size for a level-win card drop: a flat base plus a per-cat bonus so that
## as the roster grows, cards-per-cat from a chest doesn't shrink just because
## more cats are competing for the same fixed pool.
func cards_per_chest() -> int:
	var unlocked_count := 0
	for entry in cat_data:
		if bool(entry["unlocked"]):
			unlocked_count += 1
	return CARDS_PER_CHEST + CARDS_PER_UNLOCKED_CAT * maxi(unlocked_count - 1, 0)

## Randomly distributes `total_cards` one-at-a-time among currently unlocked cats,
## each card landing on a stat (damage/fire-rate/range) for that cat, pity-weighted
## toward whichever stat is furthest behind so a cat's stats stay roughly in step.
## Returns {char_index: cards_awarded} so the UI can show what dropped (stat breakdown
## isn't surfaced here — the toast only needs the total count per character).
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
		var stat: int = _pick_pity_stat(char_index)
		var cards_key: String = STAT_KEYS[stat]["cards"]
		cat_data[char_index - 1][cards_key] = int(cat_data[char_index - 1][cards_key]) + 1
		rewards[char_index] = int(rewards.get(char_index, 0)) + 1
	save()
	return rewards

## Spends CARD_PACK_GEM_COST gems for a CARD_PACK_CARDS card pack. Returns the
## {char_index: count} breakdown, or an empty dict if gems were insufficient.
func buy_card_pack() -> Dictionary:
	if not spend_gems(CARD_PACK_GEM_COST):
		return {}
	return award_cards(CARD_PACK_CARDS)

func can_claim_ad_cards() -> bool:
	return ad_cards_last_claim != _today()

## Placeholder for a rewarded-ad card chest — grants cards immediately with no
## real ad shown yet. Wire this into an ad SDK's reward callback later,
## keeping the once-per-day gate so it isn't a free unlimited-cards loop.
func claim_ad_cards() -> Dictionary:
	if not can_claim_ad_cards():
		return {}
	ad_cards_last_claim = _today()
	save()
	return award_cards(AD_CARD_REWARD)

## Shared diminishing-returns curve (+10%/level to 10, +5%/level after) used by all
## three stat tracks so the grind pacing feels consistent across damage/fire-rate/range.
func _stat_bonus(level: int) -> float:
	var capped_level: int = mini(level, 10)
	var extra_levels: int = maxi(level - 10, 0)
	return 0.1 * (capped_level - 1) + 0.05 * extra_levels

## Permanent damage multiplier a character earns from card-collection leveling.
func cat_damage_multiplier(char_index: int) -> float:
	return 1.0 + _stat_bonus(cat_stat_level(char_index, Stat.DAMAGE))

## Multiplier applied to a cat's shot cooldown (< 1.0 = faster firing), floored so
## upgrades can't shrink it to zero. Halved in Hunt mode — see HUNT_MODE_STAT_DAMPING.
func cat_fire_rate_multiplier(char_index: int) -> float:
	var bonus := _stat_bonus(cat_stat_level(char_index, Stat.FIRE_RATE))
	if hunt_mode:
		bonus *= HUNT_MODE_STAT_DAMPING
	return maxf(1.0 - bonus, FIRE_RATE_COOLDOWN_FLOOR)

## Multiplier applied to a cat's attack range (> 1.0 = longer range), capped at
## MAX_RANGE_BONUS. Halved in Hunt mode — see HUNT_MODE_STAT_DAMPING.
func cat_range_multiplier(char_index: int) -> float:
	var bonus := _stat_bonus(cat_stat_level(char_index, Stat.RANGE))
	if hunt_mode:
		bonus *= HUNT_MODE_STAT_DAMPING
	return 1.0 + minf(bonus, MAX_RANGE_BONUS)

# ---------------------------------------------------------------- levels

func is_level_unlocked(level: int) -> bool:
	return level <= unlocked_level

func is_level_completed(level: int) -> bool:
	return level in completed_levels

## Returns the gem bonus earned for beating `level`. Also rolls a card chest
## (see `last_cards_awarded` for the drop breakdown).
func complete_level(level: int) -> int:
	var first_clear := not is_level_completed(level)
	if first_clear:
		completed_levels.append(level)
	if level >= unlocked_level and level < MAX_LEVEL:
		unlocked_level = level + 1
	var bonus := FIRST_CLEAR_GEMS if first_clear else REPLAY_CLEAR_GEMS
	add_gems(bonus)  # also saves
	add_treats(FIRST_CLEAR_TREATS if first_clear else REPLAY_CLEAR_TREATS)
	last_cards_awarded = award_cards(cards_per_chest())
	return bonus

## Records a new personal-best endless wave for `level`. Returns true if it
## beat the previous best (and was saved).
func record_endless_wave(level: int, wave: int) -> bool:
	var current: int = best_endless_wave.get(level, 0)
	if wave <= current:
		return false
	best_endless_wave[level] = wave
	save()
	return true

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
	best_daily_streak = maxi(best_daily_streak, daily_streak)
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

# ---------------------------------------------------------------- tutorial

func mark_tutorial_seen() -> void:
	tutorial_seen = true
	save()

func advance_tutorial_step() -> void:
	tutorial_step += 1

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

# ---------------------------------------------------------------- achievements

## Current value of the metric an achievement definition tracks.
func achievement_progress(ach: Dictionary) -> int:
	match String(ach["metric"]):
		"levels_completed": return completed_levels.size()
		"characters_owned": return owned_characters.size()
		"max_merge_character": return max_merge_character
		"boss_kills": return stat_boss_kills
		"gems_earned": return stat_gems_earned
		"treats_earned": return stat_treats_earned
		"daily_streak": return best_daily_streak
		"max_stat_level":
			var highest := 0
			for entry in cat_data:
				highest = maxi(highest, int(entry["level"]))
				highest = maxi(highest, int(entry["fire_rate_level"]))
				highest = maxi(highest, int(entry["range_level"]))
			return highest
		_: return 0

func is_achievement_complete(ach: Dictionary) -> bool:
	return achievement_progress(ach) >= int(ach["goal"])

func is_achievement_claimed(id: String) -> bool:
	return id in claimed_achievements

func can_claim_achievement(id: String) -> bool:
	if is_achievement_claimed(id):
		return false
	for ach in ACHIEVEMENTS:
		if ach["id"] == id:
			return is_achievement_complete(ach)
	return false

## Grants the gem reward for a completed-but-unclaimed achievement. Returns the
## gems awarded, or 0 if the achievement isn't ready to claim.
func claim_achievement(id: String) -> int:
	if not can_claim_achievement(id):
		return 0
	var reward := 0
	for ach in ACHIEVEMENTS:
		if ach["id"] == id:
			reward = int(ach["reward_gems"])
			break
	claimed_achievements.append(id)
	achievement_unlocked.emit(id)
	add_gems(reward)  # also saves
	return reward

## True if any achievement is complete and awaiting its reward — drives a
## notification badge on the Achievements entry point.
func has_unclaimed_achievements() -> bool:
	for ach in ACHIEVEMENTS:
		if not is_achievement_claimed(ach["id"]) and is_achievement_complete(ach):
			return true
	return false

# ---------------------------------------------------------------- persistence

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "gems", gems)
	cfg.set_value("profile", "treats", treats)
	cfg.set_value("profile", "unlocked_level", unlocked_level)
	cfg.set_value("profile", "completed_levels", completed_levels)
	cfg.set_value("profile", "items", items)
	cfg.set_value("profile", "cat_data", cat_data)
	cfg.set_value("profile", "owned_characters", owned_characters)
	cfg.set_value("profile", "max_merge_character", max_merge_character)
	cfg.set_value("profile", "best_endless_wave", best_endless_wave)
	cfg.set_value("profile", "owned_skins", owned_skins)
	cfg.set_value("profile", "equipped_skins", equipped_skins)
	cfg.set_value("profile", "claimed_achievements", claimed_achievements)
	cfg.set_value("profile", "stat_boss_kills", stat_boss_kills)
	cfg.set_value("profile", "stat_gems_earned", stat_gems_earned)
	cfg.set_value("profile", "stat_treats_earned", stat_treats_earned)
	cfg.set_value("profile", "best_daily_streak", best_daily_streak)
	cfg.set_value("settings", "music_on", music_on)
	cfg.set_value("settings", "sound_on", sound_on)
	cfg.set_value("settings", "vibra_on", vibra_on)
	cfg.set_value("settings", "tutorial_seen", tutorial_seen)
	cfg.set_value("daily", "streak", daily_streak)
	cfg.set_value("daily", "last_claim", daily_last_claim)
	cfg.set_value("daily", "ad_cards_last_claim", ad_cards_last_claim)
	cfg.save(SAVE_PATH)

func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	gems = cfg.get_value("profile", "gems", gems)
	treats = cfg.get_value("profile", "treats", treats)
	unlocked_level = cfg.get_value("profile", "unlocked_level", unlocked_level)
	completed_levels = cfg.get_value("profile", "completed_levels", completed_levels)
	items = cfg.get_value("profile", "items", items)
	max_merge_character = cfg.get_value("profile", "max_merge_character", -1)
	if max_merge_character == -1:
		# migration: derive from the old fine-grained level scale (4 levels/character)
		var legacy_level: int = cfg.get_value("profile", "max_merge_level", 1)
		@warning_ignore("integer_division")
		max_merge_character = clampi((legacy_level - 1) / 4 + 1, 1, CAT_COUNT)
	best_endless_wave = cfg.get_value("profile", "best_endless_wave", {})
	owned_skins = cfg.get_value("profile", "owned_skins", {})
	equipped_skins = cfg.get_value("profile", "equipped_skins", {})
	claimed_achievements = cfg.get_value("profile", "claimed_achievements", [])
	stat_boss_kills = cfg.get_value("profile", "stat_boss_kills", 0)
	stat_gems_earned = cfg.get_value("profile", "stat_gems_earned", 0)
	stat_treats_earned = cfg.get_value("profile", "stat_treats_earned", 0)
	best_daily_streak = cfg.get_value("profile", "best_daily_streak", 0)
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
		_backfill_cat_data_defaults()
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
	tutorial_seen = cfg.get_value("settings", "tutorial_seen", tutorial_seen)
	daily_streak = cfg.get_value("daily", "streak", daily_streak)
	best_daily_streak = maxi(best_daily_streak, daily_streak)  # migration: backfill from existing streak saves
	daily_last_claim = cfg.get_value("daily", "last_claim", daily_last_claim)
	ad_cards_last_claim = cfg.get_value("daily", "ad_cards_last_claim", ad_cards_last_claim)
