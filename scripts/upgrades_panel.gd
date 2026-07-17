extends Control

signal navigate_to_shop

const CLICK_SFX_PATH := "res://sfx/boink.mp3"
const UPGRADE_ROW_SCENE := preload("res://scenes/UpgradeRow.tscn")

@onready var upgrade_grid: GridContainer = $UpgradeScroll/UpgradeGrid
@onready var treats_label: Label = $TreatsLabel

var _upgrade_controls: Dictionary = {}
var _selected_stat: Dictionary = {}      # {char_index: GameState.Stat}, defaults to DAMAGE
var _click_player: AudioStreamPlayer

const STAT_NAMES := {
	GameState.Stat.DAMAGE: "Damage",
	GameState.Stat.FIRE_RATE: "Fire Rate",
	GameState.Stat.RANGE: "Range",
}

func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = load(CLICK_SFX_PATH)
	add_child(_click_player)
	$GemsHud.add_pressed.connect(_on_gems_add_pressed)
	$CardRewardsRow/CardPackButton.pressed.connect(_on_card_pack_pressed)
	$CardRewardsRow/AdCardsButton.pressed.connect(_on_ad_cards_pressed)
	GameState.treats_changed.connect(_on_treats_changed)
	_build_upgrade_grid()
	_refresh_card_reward_buttons()
	_refresh_treats_label()

func _play_click() -> void:
	if GameState.sound_on:
		_click_player.play()

func refresh() -> void:
	for char_index in _upgrade_controls.keys():
		_refresh_upgrade_row(char_index)
	$GemsHud.refresh()
	_refresh_card_reward_buttons()
	_refresh_treats_label()

func _refresh_treats_label() -> void:
	treats_label.text = "Treats: %d" % GameState.treats

func _on_treats_changed(_treats: int) -> void:
	_refresh_treats_label()

func _on_gems_add_pressed() -> void:
	navigate_to_shop.emit()

func _refresh_card_reward_buttons() -> void:
	var card_pack_button: Button = $CardRewardsRow/CardPackButton
	var affordable := GameState.gems >= GameState.CARD_PACK_GEM_COST
	# Left clickable even when unaffordable/claimed so pressing it still
	# reports why, instead of a disabled button silently eating the tap.
	card_pack_button.disabled = false
	card_pack_button.self_modulate = Color.WHITE if affordable else Color(0.5, 0.5, 0.5)

	var ad_cards_button: Button = $CardRewardsRow/AdCardsButton
	var claimed_today := not GameState.can_claim_ad_cards()
	ad_cards_button.disabled = false
	ad_cards_button.self_modulate = Color(0.5, 0.5, 0.5) if claimed_today else Color.WHITE

func _show_card_toast(message: String) -> void:
	var toast: Label = $CardToast
	toast.text = message
	toast.visible = true
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if is_instance_valid(toast):
			toast.visible = false
	)

func _total_cards(reward: Dictionary) -> int:
	var total := 0
	for count in reward.values():
		total += count
	return total

func _on_card_pack_pressed() -> void:
	_play_click()
	if GameState.gems < GameState.CARD_PACK_GEM_COST:
		_show_card_toast("Need %d more Gems" % (GameState.CARD_PACK_GEM_COST - GameState.gems))
		return
	var reward := GameState.buy_card_pack()
	if reward.is_empty():
		return
	_show_card_toast("+%d Cards!" % _total_cards(reward))
	for char_index in reward.keys():
		_refresh_upgrade_row(char_index)
	$GemsHud.refresh()
	_refresh_card_reward_buttons()

func _on_ad_cards_pressed() -> void:
	_play_click()
	if not GameState.can_claim_ad_cards():
		_show_card_toast("Already claimed today.\nCome back tomorrow!")
		return
	var reward := GameState.claim_ad_cards()
	_show_card_toast("+%d Cards!" % _total_cards(reward))
	for char_index in reward.keys():
		_refresh_upgrade_row(char_index)
	_refresh_card_reward_buttons()

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
		row.stat_selected.connect(_on_stat_selected.bind(i))
		_selected_stat[i] = GameState.Stat.DAMAGE
		_refresh_upgrade_row(i)

func _refresh_upgrade_row(char_index: int) -> void:
	var row: UpgradeRow = _upgrade_controls.get(char_index)
	if row == null:
		return

	var owned := GameState.is_character_purchased(char_index)
	var stat: int = _selected_stat.get(char_index, GameState.Stat.DAMAGE)
	var level: int = GameState.cat_stat_level(char_index, stat) if owned else 1
	var maxed := owned and level >= GameState.MAX_CAT_LEVEL

	row.bg_locked.visible = not owned
	row.bg_unlocked.visible = owned
	row.aura.visible = owned
	row.portrait.visible = owned
	if owned:
		row.portrait.texture = load("res://Png/Characters/C%d/Idle/Character%d-Idle_00.png" % [char_index, char_index])
	else:
		row.portrait.texture = null
	row.name_label.text = "C%d" % char_index if not owned else "Level %d" % level
	row.pip_bar.visible = owned
	row.cards_label.visible = owned
	row.stat_tabs.visible = owned

	if owned:
		var bar_index := clampi(int(floor(float(level - 1) / float(GameState.MAX_CAT_LEVEL - 1) * 5.0)), 0, 5)
		row.pip_bar.texture = load("res://Png/Ui/%dBar.png" % bar_index)
		if maxed:
			row.cards_label.text = "MAX LEVEL"
			row.cost_label.text = ""
			row.buy_button.visible = false
			row.click_overlay.visible = false
		else:
			var cards := GameState.cat_stat_cards(char_index, stat)
			var cards_needed := GameState.cat_stat_cards_required(char_index, stat)
			var gem_cost := GameState.cat_stat_gem_cost(char_index, stat)
			row.cards_label.text = "Cards: %d/%d" % [cards, cards_needed]
			row.cost_label.text = ""
			row.buy_button_label.text = "UPGRADE"
			var can_afford_gems := GameState.gems >= gem_cost
			var can_afford_cards := cards >= cards_needed
			var affordable := can_afford_gems and can_afford_cards
			# Left clickable even when unaffordable so pressing it still
			# reports what's missing instead of silently eating the tap.
			row.buy_button.disabled = false
			row.buy_button.self_modulate = Color.WHITE if affordable else Color(0.5, 0.5, 0.5)
			row.buy_button.visible = true
			row.click_overlay.visible = false
	else:
		row.buy_button_label.text = "BUY"
		var cost := GameState.character_unlock_cost(char_index)
		var affordable := GameState.treats >= cost
		row.buy_button.disabled = false
		row.buy_button.self_modulate = Color.WHITE if affordable else Color(0.5, 0.5, 0.5)
		row.buy_button.visible = true
		row.cost_label.text = "%d treats" % cost
		row.click_overlay.visible = false

func _on_upgrade_row_gui_input(event: InputEvent, char_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_upgrade_row_pressed(char_index)

func _on_stat_selected(stat: int, char_index: int) -> void:
	_play_click()
	_selected_stat[char_index] = stat
	_refresh_upgrade_row(char_index)

func _on_upgrade_row_pressed(char_index: int) -> void:
	_play_click()
	if not GameState.is_character_purchased(char_index):
		if GameState.purchase_character(char_index):
			_refresh_upgrade_row(char_index)
			_refresh_treats_label()
		else:
			var missing := GameState.character_unlock_cost(char_index) - GameState.treats
			_show_card_toast("Need %d more Treats" % missing)
	else:
		var stat: int = _selected_stat.get(char_index, GameState.Stat.DAMAGE)
		if GameState.upgrade_cat_stat(char_index, stat):
			_refresh_upgrade_row(char_index)
		else:
			_show_card_toast(_upgrade_denial_reason(char_index, stat))

## Builds the specific reason an upgrade_cat_stat() call was rejected, so the
## player knows exactly what's missing (cards, gems, or both) rather than
## just seeing the button silently stay disabled.
func _upgrade_denial_reason(char_index: int, stat: int) -> String:
	if GameState.cat_stat_level(char_index, stat) >= GameState.MAX_CAT_LEVEL:
		return "%s already at MAX LEVEL" % STAT_NAMES[stat]
	var cards_missing := GameState.cat_stat_cards_required(char_index, stat) - GameState.cat_stat_cards(char_index, stat)
	var gems_missing := GameState.cat_stat_gem_cost(char_index, stat) - GameState.gems
	if cards_missing > 0 and gems_missing > 0:
		return "Need %d more Cards\nand %d more Gems" % [cards_missing, gems_missing]
	if cards_missing > 0:
		return "Need %d more Cards" % cards_missing
	if gems_missing > 0:
		return "Need %d more Gems" % gems_missing
	return "Cannot upgrade right now"
