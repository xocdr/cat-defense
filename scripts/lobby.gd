extends Control

## Hub scene: level-select map, cat Upgrades page, Extra (consumables) page
## and gem Shop. All economy/progress state lives in the GameState autoload.

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const CLICK_SFX_PATH := "res://sfx/boink.mp3"

const TEX_LEVEL_CURRENT := "res://Png/Ui/GreenLevel.png"
const TEX_LEVEL_DONE := "res://Png/Ui/OrangeLvl.png"
const TEX_LEVEL_LOCKED := "res://Png/Ui/LockedLevel.png"

const NAV_TAB_ACTIVE := preload("res://Png/Ui/BtnTab_on.png")
const NAV_TAB_INACTIVE := preload("res://Png/Ui/BtnTab_Active.png")

const ITEM_DEFS := [
	{"id": "spikes", "name": "Spikes"},
	{"id": "tnt", "name": "TNT"},
	{"id": "boxer", "name": "Boxing Cat"},
]

@onready var daily_gift_button: TextureButton = $DailyGiftButton
@onready var home_button: TextureButton = $Sidebar/HomeButton
@onready var cats_button: TextureButton = $Sidebar/CatsButton
@onready var shop_button: TextureButton = $Sidebar/ShopButton
@onready var extra_button: TextureButton = $Sidebar/ExtraButton
@onready var credits_button: TextureButton = $Sidebar/CreditsButton
@onready var placeholder_popup: PanelContainer = $PlaceholderPopup
@onready var placeholder_label: Label = $PlaceholderPopup/MarginContainer/VBoxContainer/PlaceholderLabel
@onready var shop_panel: Control = $ShopPanel
@onready var map_content: Control = $MapScroll/MapContent
@onready var map_scroll: ScrollContainer = $MapScroll
@onready var level_select_ribbon: TextureRect = $TitleRibbon
@onready var upgrades_page: Control = $UpgradesPage
@onready var upgrade_grid: GridContainer = $UpgradesPage/UpgradeScroll/UpgradeGrid
@onready var extra_page: Control = $ExtraPage
@onready var credits_page: Control = $CreditsPage

@onready var _pages: Array[CanvasItem] = [map_scroll, level_select_ribbon, shop_panel, upgrades_page, extra_page, credits_page]
@onready var _gems_labels: Array[Label] = [
	$ShopPanel/GemsHud/GemsLabel,
	$UpgradesPage/GemsHud/GemsLabel,
	$ExtraPage/GemsHud/GemsLabel,
]

var _upgrade_rows: Array[Control] = []
var _click_player: AudioStreamPlayer

func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = load(CLICK_SFX_PATH)
	add_child(_click_player)
	placeholder_popup.visible = false
	daily_gift_button.pressed.connect(_on_daily_gift_pressed)
	home_button.pressed.connect(_show_level_select)
	cats_button.pressed.connect(_show_upgrades)
	extra_button.pressed.connect(_show_extra)
	shop_button.pressed.connect(_show_shop)
	credits_button.pressed.connect(_show_credits)
	shop_panel.item_purchased.connect(_on_shop_item_purchased)
	$PlaceholderPopup/MarginContainer/VBoxContainer/CloseButton.pressed.connect(_on_placeholder_close_pressed)
	for hud_path in ["ShopPanel/GemsHud/AddButton", "UpgradesPage/GemsHud/AddButton", "ExtraPage/GemsHud/AddButton"]:
		get_node(hud_path).pressed.connect(_show_shop)
	# Connect a real method, not a lambda: method connections auto-disconnect
	# when this Lobby is freed on scene change, lambdas would not.
	GameState.gems_changed.connect(_on_gems_changed)

	_setup_levels()
	_build_upgrade_grid()
	_setup_extra_items()
	_refresh_gems()

func _play_click() -> void:
	if GameState.sound_on:
		_click_player.play()

# ---------------------------------------------------------------- level map

func _setup_levels() -> void:
	for i in range(1, GameState.MAX_LEVEL + 1):
		var button: TextureButton = map_content.get_node("Level%d" % i)
		var unlocked := GameState.is_level_unlocked(i)
		var completed := GameState.is_level_completed(i)
		button.disabled = not unlocked
		if completed:
			button.texture_normal = load(TEX_LEVEL_DONE)
		elif unlocked:
			button.texture_normal = load(TEX_LEVEL_CURRENT)
		else:
			button.texture_normal = load(TEX_LEVEL_LOCKED)
		var label: Label = button.get_node_or_null("Label%d" % i)
		if label:
			label.visible = unlocked
		# Bound callables with equal arguments compare equal, so this guard
		# holds across repeated _setup_levels calls.
		if not button.pressed.is_connected(_on_level_pressed.bind(i)):
			button.pressed.connect(_on_level_pressed.bind(i))

func _on_level_pressed(level: int) -> void:
	_play_click()
	if not GameState.is_level_unlocked(level):
		return
	GameState.selected_level = level
	SceneTransition.change_scene(MAIN_SCENE_PATH)

# ---------------------------------------------------------------- upgrades

func _build_upgrade_grid() -> void:
	_upgrade_rows.clear()
	for child in upgrade_grid.get_children():
		# remove_child before queue_free so the container never lays out old
		# and new rows together for a frame (visible flicker otherwise).
		upgrade_grid.remove_child(child)
		child.queue_free()
	for i in range(1, GameState.CAT_COUNT + 1):
		var row := Control.new()
		row.custom_minimum_size = Vector2(268, 78)
		upgrade_grid.add_child(row)
		_upgrade_rows.append(row)
		_refresh_upgrade_row(i)

func _refresh_upgrade_row(char_index: int) -> void:
	var row := _upgrade_rows[char_index - 1]
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var unlocked: bool = GameState.is_cat_unlocked(char_index)

	if not unlocked:
		var locked_box := TextureRect.new()
		locked_box.texture = load("res://Png/Ui/LockedCatBox.png")
		locked_box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		locked_box.size = Vector2(268, 78)
		row.add_child(locked_box)
		var lock_label := Label.new()
		lock_label.text = "Level %d" % GameState.cat_unlock_level(char_index)
		lock_label.position = Vector2(78, 8)
		lock_label.add_theme_font_size_override("font_size", 16)
		lock_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		row.add_child(lock_label)
		return

	var box := TextureRect.new()
	box.texture = load("res://Png/Ui/AddonBoxGrey.png")
	box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.size = Vector2(268, 78)
	row.add_child(box)

	var portrait := TextureRect.new()
	portrait.texture = load("res://Png/Characters/C%d/Idle/Character%d-Idle_00.png" % [char_index, char_index])
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.position = Vector2(10, 15)
	portrait.size = Vector2(48, 48)
	row.add_child(portrait)

	var name_label := Label.new()
	name_label.text = "Level %d" % GameState.cat_unlock_level(char_index)
	name_label.position = Vector2(68, 8)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(name_label)

	var pips: int = GameState.cat_pips(char_index)
	var pip_bar := TextureRect.new()
	pip_bar.texture = load("res://Png/Ui/%dBar.png" % pips)
	pip_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pip_bar.position = Vector2(68, 36)
	pip_bar.size = Vector2(120, 32)
	row.add_child(pip_bar)

	var maxed := pips >= GameState.MAX_UPGRADE_PIPS
	var button := TextureButton.new()
	button.texture_normal = load("res://Png/Ui/AddonBtnyellow.png")
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.position = Vector2(204, 14)
	button.size = Vector2(54, 34)
	button.disabled = maxed
	button.self_modulate = Color(0.5, 0.5, 0.5) if maxed else Color.WHITE
	button.pressed.connect(_on_upgrade_pressed.bind(char_index))
	row.add_child(button)

	var cost_label := Label.new()
	cost_label.position = Vector2(200, 48)
	cost_label.size = Vector2(62, 20)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 13)
	cost_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.45))
	cost_label.text = "MAX" if maxed else "%d gems" % GameState.cat_upgrade_cost(char_index)
	row.add_child(cost_label)

func _on_upgrade_pressed(char_index: int) -> void:
	_play_click()
	if GameState.upgrade_cat(char_index):
		_refresh_upgrade_row(char_index)
	else:
		_show_placeholder("Not enough gems!")

# ---------------------------------------------------------------- extra items

func _setup_extra_items() -> void:
	for i in range(ITEM_DEFS.size()):
		var item_box: Control = extra_page.get_node("Item%d" % (i + 1))
		item_box.get_node("CostButton").pressed.connect(_on_item_buy_pressed.bind(i))
	_refresh_extra_items()

func _refresh_extra_items() -> void:
	for i in range(ITEM_DEFS.size()):
		var id: String = ITEM_DEFS[i]["id"]
		var count: int = GameState.item_count(id)
		var item_box: Control = extra_page.get_node("Item%d" % (i + 1))
		item_box.get_node("NameLabel").text = ITEM_DEFS[i]["name"]
		item_box.get_node("CountLabel").text = "%d / %d" % [count, GameState.MAX_ITEM_COUNT]
		item_box.get_node("PipBar").texture = load("res://Png/Ui/%dBar.png" % count)
		var maxed := count >= GameState.MAX_ITEM_COUNT
		var button: TextureButton = item_box.get_node("CostButton")
		button.disabled = maxed
		button.self_modulate = Color(0.5, 0.5, 0.5) if maxed else Color.WHITE

func _on_item_buy_pressed(index: int) -> void:
	_play_click()
	var id: String = ITEM_DEFS[index]["id"]
	if GameState.buy_item(id):
		_refresh_extra_items()
	else:
		var maxed: bool = GameState.item_count(id) >= GameState.MAX_ITEM_COUNT
		_show_placeholder("Storage full!" if maxed else "Not enough gems!")

# ---------------------------------------------------------------- daily gift

func _on_daily_gift_pressed() -> void:
	_play_click()
	if GameState.can_claim_daily():
		var reward: int = GameState.claim_daily()
		_show_placeholder("Day %d gift: +%d gems!" % [GameState.daily_streak, reward])
	else:
		_show_placeholder("Already claimed today.\nCome back tomorrow!")

# ---------------------------------------------------------------- pages

func _show_level_select() -> void:
	_play_click()
	_set_active_nav(home_button)
	_show_only([map_scroll, level_select_ribbon])
	_setup_levels()

func _show_shop() -> void:
	_play_click()
	_set_active_nav(shop_button)
	_show_only([shop_panel])
	shop_panel.open()

func _show_upgrades() -> void:
	_play_click()
	_set_active_nav(cats_button)
	_show_only([upgrades_page])
	_build_upgrade_grid()

func _show_extra() -> void:
	_play_click()
	_set_active_nav(extra_button)
	_show_only([extra_page])
	_refresh_extra_items()

func _show_credits() -> void:
	_play_click()
	_set_active_nav(credits_button)
	_show_only([credits_page])

func _show_only(pages_to_show: Array) -> void:
	for page in _pages:
		page.visible = page in pages_to_show

func _set_active_nav(active_button: TextureButton) -> void:
	for button in [home_button, cats_button, extra_button, shop_button, credits_button]:
		button.texture_normal = NAV_TAB_ACTIVE if button == active_button else NAV_TAB_INACTIVE

func _on_shop_item_purchased(gems_amount: int) -> void:
	GameState.add_gems(gems_amount)

func _on_gems_changed(_gems: int) -> void:
	_refresh_gems()

func _refresh_gems() -> void:
	for label in _gems_labels:
		label.text = str(GameState.gems)

func _show_placeholder(message: String) -> void:
	placeholder_label.text = message
	placeholder_popup.visible = true

func _on_placeholder_close_pressed() -> void:
	_play_click()
	placeholder_popup.visible = false
