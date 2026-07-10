extends Node2D

## Match scene: merge-board defense. Buy cats onto the 5x2 grid, drag two of
## the same level together to merge them, and defend the crate wall against
## 10 waves of zombies. Losing = an enemy walks past the cat grid.

const CatScene := preload("res://scenes/Cat.tscn")
const SlotScene := preload("res://scenes/Slot.tscn")
const EnemyScene := preload("res://scenes/Enemy.tscn")

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
	3: {"cols": [163.0, 246.0], "trash_pos": Vector2(66.4, 73.9), "trash_row": -1, "trash_col": -1},
	4: {"cols": [163.0, 246.0], "trash_pos": Vector2(163.0, 508.5), "trash_row": 4, "trash_col": 0},
	5: {"cols": [163.0, 246.0], "trash_pos": Vector2(163.0, 508.5), "trash_row": 4, "trash_col": 0},
}

const WAVE_SFX_PATH := "res://sfx/evil-cat-laugh.mp3"
const MERGE_SFX_PATH := "res://sfx/lvlup-cat-meow.mp3"
const PLACE_SFX_PATH := "res://sfx/cat-placed.mp3"
const WAVE_COMPLETE_SFX_PATH := "res://sfx/wave complete.mp3"

const TEX_MUSIC_ON := preload("res://Png/Ui/BtnMusic.png")
const TEX_MUSIC_OFF := preload("res://Png/Ui/BtnMusicOff.png")
const TEX_SOUND_ON := preload("res://Png/Ui/BtnSound.png")
const TEX_SOUND_OFF := preload("res://Png/Ui/BtnSound Off.png")
const TEX_VIBRA_ON := preload("res://Png/Ui/BtnVibra.png")
const TEX_VIBRA_OFF := preload("res://Png/Ui/BtnVibra Off.png")
const WIN_WAVE := 10
const BUY_BASE_COST := 35.0
const BUY_COST_GROWTH := 1.18
const START_COINS := 150
const DRAG_PICK_RADIUS := 55.0
const ITEM_MIN_X := 470.0
const ITEM_MAX_X := 1230.0
const ENEMY_SPAWN_X := 1340.0

const ITEM_DEFS := [
	{"id": "spikes", "icon": "res://Png/Ui/AddonIcon8.png"},
	{"id": "tnt", "icon": "res://Png/Ui/AddonIcon6.png"},
	{"id": "boxer", "icon": "res://Png/Ui/AddonIcon7.png"},
]

var level_num: int = 1
var area_index: int = 1
var coins: int = START_COINS
var wave: int = 0
var buys: int = 0
var best_level: int = 1        # highest cat level reached this match
var enemies_to_spawn: int = 0
var boss_to_spawn: bool = false
var spawn_timer: float = 0.0
var wave_active: bool = false
var break_pending: bool = false
var match_over: bool = false
var _gold_timer: float = 0.0

var slots: Array[Slot] = []
var dragged_cat: Cat = null
var drag_origin: Slot = null
var armed_item: String = ""
var _wave_sfx_player: AudioStreamPlayer
var _merge_sfx_player: AudioStreamPlayer
var _place_sfx_player: AudioStreamPlayer
var _wave_complete_sfx_player: AudioStreamPlayer

@onready var background: Sprite2D = $Background
@onready var wall: Wall = $Wall
@onready var world: Node2D = $World
@onready var slots_container: Node2D = $Slots

@onready var coin_label: Label = $UI/TopBar/CoinBar/CoinLabel
@onready var wave_label: Label = $UI/TopBar/WaveBar/WaveLabel
@onready var settings_button: TextureButton = $UI/TopBar/SettingsButton
@onready var wave_banner: Label = $UI/WaveBanner

@onready var buy_button: TextureButton = $UI/BottomBar/BuyButton
@onready var buy_level_label: Label = $UI/BottomBar/BuyButton/TitleLabel
@onready var buy_cost_label: Label = $UI/BottomBar/BuyButton/CostLabel
@onready var repair_button: TextureButton = $UI/BottomBar/RepairButton
@onready var repair_cost_label: Label = $UI/BottomBar/RepairButton/CostLabel
@onready var item_buttons: Array[TextureButton] = [
	$UI/BottomBar/Item0, $UI/BottomBar/Item1, $UI/BottomBar/Item2,
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
@onready var continue_button: TextureButton = $UI/WinPanel/Panel/ContinueButton

func _ready() -> void:
	randomize()
	level_num = GameState.selected_level
	_setup_level()
	_setup_panels()
	_spawn_slots()
	_setup_item_buttons()

	buy_button.pressed.connect(_on_buy_pressed)
	repair_button.pressed.connect(_on_repair_pressed)
	settings_button.pressed.connect(_on_pause_pressed)

	_wave_sfx_player = AudioStreamPlayer.new()
	_wave_sfx_player.stream = load(WAVE_SFX_PATH)
	add_child(_wave_sfx_player)

	_merge_sfx_player = AudioStreamPlayer.new()
	_merge_sfx_player.stream = load(MERGE_SFX_PATH)
	add_child(_merge_sfx_player)

	_place_sfx_player = AudioStreamPlayer.new()
	_place_sfx_player.stream = load(PLACE_SFX_PATH)
	add_child(_place_sfx_player)

	_wave_complete_sfx_player = AudioStreamPlayer.new()
	_wave_complete_sfx_player.stream = load(WAVE_COMPLETE_SFX_PATH)
	add_child(_wave_complete_sfx_player)

	_refresh_hud()
	_start_wave()

func _setup_level() -> void:
	area_index = (level_num - 1) % 5 + 1
	background.texture = load("res://Png/Area/Area%d.png" % area_index)
	coins = START_COINS + 90 * (level_num - 1)
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

func buy_cost() -> int:
	return int(round(BUY_BASE_COST * pow(BUY_COST_GROWTH, buys)))

func buy_level() -> int:
	return maxi(1, best_level - 3)

func _on_buy_pressed() -> void:
	if match_over:
		return
	var free := _free_slots()
	if coins < buy_cost() or free.is_empty():
		_flash_deny(buy_button)
		return
	coins -= buy_cost()
	buys += 1
	var slot: Slot = free.pick_random()
	_place_new_cat(slot, buy_level())
	_refresh_hud()

func _place_new_cat(slot: Slot, level: int) -> void:
	var cat: Cat = CatScene.instantiate()
	cat.level = level
	cat.row = slot.row
	cat.slot = slot
	cat.position = slot.position
	world.add_child(cat)
	slot.occupant = cat
	_record_level(level)
	if GameState.sound_on:
		_place_sfx_player.play()
	cat.scale = Vector2(0.2, 0.2)
	var tw := cat.create_tween()
	tw.tween_property(cat, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _record_level(level: int) -> void:
	if level > best_level:
		best_level = level
		GameState.record_merge_level(level)

func sell_value(level: int) -> int:
	return 10 + 5 * level

# ---------------------------------------------------------------- drag & merge

func _unhandled_input(event: InputEvent) -> void:
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
	if dragged_cat == null:
		return
	dragged_cat.set_dragging(false)
	dragged_cat.position = drag_origin.position
	dragged_cat = null
	drag_origin = null
	_clear_highlights()

func _on_press(pos: Vector2) -> void:
	if dragged_cat != null:
		return
	if armed_item != "":
		_try_place_item(pos)
		return
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
	elif slot.is_trash:
		_sell_cat(cat)
	elif slot.occupant == null:
		_move_cat(cat, slot)
	elif slot.occupant.level == cat.level:
		_merge_cats(cat, slot.occupant)
	else:
		_swap_cats(cat, slot.occupant)
	drag_origin = null

func _return_to_origin(cat: Cat) -> void:
	cat.position = drag_origin.position

func _sell_cat(cat: Cat) -> void:
	var refund := sell_value(cat.level)
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

func _merge_cats(dragged: Cat, kept: Cat) -> void:
	drag_origin.occupant = null
	dragged.queue_free()
	if GameState.sound_on:
		_merge_sfx_player.play()
	kept.set_level(kept.level + 1)
	_record_level(kept.level)
	Fx.explosion(world, kept.position, 0.12)
	FloatText.spawn(world, kept.position + Vector2(0, -30), "Lv %d!" % kept.level, Color(0.6, 1, 0.4), 20)
	var tw := kept.create_tween()
	kept.scale = Vector2(1.3, 1.3)
	tw.tween_property(kept, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_hud()

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
	elif slot.occupant and slot.occupant.level == dragged_cat.level:
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
	enemies_to_spawn = 5 + 2 * wave + (level_num - 1)
	if boss_to_spawn:
		enemies_to_spawn = int(enemies_to_spawn * 0.6)
	spawn_timer = 1.2
	if GameState.sound_on:
		_wave_sfx_player.play()
	_refresh_hud()
	_show_banner("Wave %d Incoming!" % wave)

func _process(delta: float) -> void:
	# Main runs in PROCESS_MODE_ALWAYS so pause/drag input keeps working
	# while the tree is paused; gameplay itself must not advance then.
	if not get_tree().paused and not match_over:
		_gold_timer += delta
		var earned := false
		while _gold_timer >= 1.0:
			_gold_timer -= 1.0
			coins += 1
			earned = true
		if earned:
			_refresh_hud()
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
	var hp := int(round(22.0 * pow(1.18, wave - 1) * pow(1.13, level_num - 1)))
	# Rewards scale exponentially like enemy HP does, or buying/merging
	# stalls out mid-match while enemies keep compounding.
	var reward := int(round(12.0 * pow(1.18, wave - 1))) + 5 * (level_num - 1)
	if boss:
		enemy.enemy_index = (level_num - 1) % 7 + 1
		enemy.max_hp = hp * (8 if wave >= WIN_WAVE else 5)
		enemy.speed = randf_range(18.0, 24.0)
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
	_refresh_hud()

# ---------------------------------------------------------------- match end

func _win_match() -> void:
	match_over = true
	_cancel_drag()
	if GameState.sound_on:
		_wave_complete_sfx_player.play()
	var bonus := GameState.complete_level(level_num)
	win_bonus_label.text = "+%d" % bonus
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
	buy_level_label.text = "Level %d" % buy_level()
	buy_cost_label.text = _fmt(buy_cost())
	buy_button.self_modulate = Color.WHITE if coins >= buy_cost() and not _free_slots().is_empty() else Color(0.55, 0.55, 0.55)
	repair_cost_label.text = _fmt(repair_cost())
	var can_repair := wall.missing_hp() > 0 and coins >= repair_cost()
	repair_button.self_modulate = Color.WHITE if can_repair else Color(0.55, 0.55, 0.55)
	_refresh_item_buttons()

func _fmt(n: int) -> String:
	if n >= 100000:
		return "%dk" % (n / 1000)
	return str(n)

func _flash_deny(button: TextureButton) -> void:
	var tw := button.create_tween()
	button.self_modulate = Color(1.5, 0.4, 0.4)
	tw.tween_interval(0.12)
	tw.tween_callback(_refresh_hud)

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
