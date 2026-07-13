extends Control

signal navigate_to_shop

const CLICK_SFX_PATH := "res://sfx/boink.mp3"
const UPGRADE_ROW_SCENE := preload("res://scenes/UpgradeRow.tscn")

@onready var upgrade_grid: GridContainer = $UpgradeScroll/UpgradeGrid

var _upgrade_controls: Dictionary = {}
var _click_player: AudioStreamPlayer

func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = load(CLICK_SFX_PATH)
	add_child(_click_player)
	$GemsHud.add_pressed.connect(_on_gems_add_pressed)
	_build_upgrade_grid()

func _play_click() -> void:
	if GameState.sound_on:
		_click_player.play()

func refresh() -> void:
	for char_index in _upgrade_controls.keys():
		_refresh_upgrade_row(char_index)
	$GemsHud.refresh()

func _on_gems_add_pressed() -> void:
	navigate_to_shop.emit()

func _build_upgrade_grid() -> void:
	_upgrade_controls.clear()
	for child in upgrade_grid.get_children():
		upgrade_grid.remove_child(child)
		child.queue_free()
	for i in range(1, GameState.CAT_COUNT + 1):
		var row: UpgradeRow = UPGRADE_ROW_SCENE.instantiate()
		upgrade_grid.add_child(row)
		_upgrade_controls[i] = row
		var tier: Rarity.Tier = Rarity.tier_for_character(i)
		row.aura.texture = Rarity.aura_texture(tier)
		row.tier_label.text = Rarity.name_for_tier(tier)
		row.tier_label.add_theme_color_override("font_color", Rarity.color_for_tier(tier))
		row.buy_button.pressed.connect(_on_upgrade_row_pressed.bind(i))
		row.click_overlay.gui_input.connect(_on_upgrade_row_gui_input.bind(i))
		_refresh_upgrade_row(i)

func _refresh_upgrade_row(char_index: int) -> void:
	var row: UpgradeRow = _upgrade_controls.get(char_index)
	if row == null:
		return

	var owned := GameState.is_character_purchased(char_index)
	var level: int = GameState.cat_level(char_index) if owned else 1
	var maxed := owned and level >= GameState.MAX_CAT_LEVEL

	row.bg_locked.visible = not owned
	row.bg_unlocked.visible = owned
	row.portrait.visible = owned
	if owned:
		row.portrait.texture = load("res://Png/Characters/C%d/Idle/Character%d-Idle_00.png" % [char_index, char_index])
	else:
		row.portrait.texture = null
	row.name_label.text = "C%d" % char_index if not owned else "Level %d" % level
	row.pip_bar.visible = owned
	row.cards_label.visible = owned

	if owned:
		row.pip_bar.texture = load("res://Png/Ui/%dBar.png" % clampi(level - 1, 0, 5))
		if maxed:
			row.cards_label.text = "MAX LEVEL"
			row.cost_label.text = ""
			row.buy_button.visible = false
			row.click_overlay.visible = false
		else:
			var cards := GameState.cat_cards(char_index)
			var cards_needed := GameState.cat_cards_required(char_index)
			var gem_cost := GameState.cat_level_gem_cost(char_index)
			row.cards_label.text = "Cards: %d/%d" % [cards, cards_needed]
			row.cost_label.text = "%d gems" % gem_cost
			row.buy_button_label.text = "UPGRADE"
			var can_afford_gems := GameState.gems >= gem_cost
			var can_afford_cards := cards >= cards_needed
			var affordable := can_afford_gems and can_afford_cards
			row.buy_button.disabled = not affordable
			row.buy_button.self_modulate = Color.WHITE if affordable else Color(0.5, 0.5, 0.5)
			row.buy_button.visible = true
			row.click_overlay.visible = false
	else:
		row.buy_button_label.text = "BUY"
		var cost := GameState.character_unlock_cost(char_index)
		var affordable := GameState.gems >= cost
		row.buy_button.disabled = not affordable
		row.buy_button.self_modulate = Color.WHITE if affordable else Color(0.5, 0.5, 0.5)
		row.buy_button.visible = true
		row.cost_label.text = "%d gems" % cost
		row.click_overlay.visible = false

func _on_upgrade_row_gui_input(event: InputEvent, char_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_upgrade_row_pressed(char_index)

func _on_upgrade_row_pressed(char_index: int) -> void:
	_play_click()
	if not GameState.is_character_purchased(char_index):
		if GameState.purchase_character(char_index):
			_refresh_upgrade_row(char_index)
			$GemsHud.refresh()
	else:
		if GameState.upgrade_cat(char_index):
			_refresh_upgrade_row(char_index)
