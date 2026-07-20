extends Control

## Hub shell: sidebar navigation with cached panel scenes.

const CLICK_SFX_PATH := "res://sfx/boink.mp3"

const ACTIVE_COLOR := Color(0.463, 0.502, 0.467)  # #768077
const INACTIVE_COLOR := Color(0.3804, 0.4078, 0.3804)  # #616861

const PANEL_PATHS := {
	"home": "res://scenes/HomePanel.tscn",
	"upgrades": "res://scenes/UpgradesPanel.tscn",
	"extra": "res://scenes/ExtraPanel.tscn",
	"shop": "res://scenes/ShopPanel.tscn",
	"credits": "res://scenes/CreditsPanel.tscn",
}

const BUTTON_TO_SECTION := {
	"HomeButton": "home",
	"CatsButton": "upgrades",
	"ExtraButton": "extra",
	"ShopButton": "shop",
	"CreditsButton": "credits",
}

@onready var content: Control = $Content
@onready var daily_gift_button: TextureButton = $DailyGiftButton
@onready var placeholder_popup: PanelContainer = $PlaceholderPopup
@onready var placeholder_label: Label = $PlaceholderPopup/MarginContainer/VBoxContainer/PlaceholderLabel
@onready var achievements_button: Button = $AchievementsButton
@onready var achievements_badge: ColorRect = $AchievementsButton/Badge
@onready var achievements_panel: Control = $AchievementsPanel

var _nav_buttons: Dictionary = {}
var _panels: Dictionary = {}
var _current_section: String = ""
var _click_player: AudioStreamPlayer

func _ready() -> void:
	GameState.set_bgm(GameState.BGM_PATH)
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = load(CLICK_SFX_PATH)
	add_child(_click_player)
	placeholder_popup.visible = false
	daily_gift_button.pressed.connect(_on_daily_gift_pressed)
	$PlaceholderPopup/MarginContainer/VBoxContainer/CloseButton.pressed.connect(_on_placeholder_close_pressed)
	achievements_button.pressed.connect(_on_achievements_pressed)
	GameState.achievement_unlocked.connect(_on_achievement_unlocked)
	_refresh_achievements_badge()
	for child in $Sidebar.get_children():
		var section_key: String = child.name
		if BUTTON_TO_SECTION.has(section_key):
			_nav_buttons[BUTTON_TO_SECTION[section_key]] = child
			child.pressed.connect(_on_nav_pressed.bind(BUTTON_TO_SECTION[section_key]))
	_show_section("home")

func _play_click() -> void:
	if GameState.sound_on:
		_click_player.play()

func _on_nav_pressed(section: String) -> void:
	_play_click()
	_show_section(section)

func _show_section(section: String) -> void:
	if _current_section == section:
		return
	if _current_section and _panels.has(_current_section):
		_panels[_current_section].visible = false
	if not _panels.has(section):
		var panel: Control = load(PANEL_PATHS[section]).instantiate()
		content.add_child(panel)
		_panels[section] = panel
		_setup_panel_signals(section, panel)
	_panels[section].visible = true
	_current_section = section
	_set_active_nav(section)
	if _panels[section].has_method("refresh"):
		_panels[section].refresh()

func _setup_panel_signals(section: String, panel: Control) -> void:
	if panel.has_signal("navigate_to_shop"):
		panel.navigate_to_shop.connect(_on_nav_pressed.bind("shop"))
	if section == "shop" and panel.has_signal("item_purchased"):
		panel.item_purchased.connect(_on_shop_item_purchased)

func _set_active_nav(active_section: String) -> void:
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = ACTIVE_COLOR
	var inactive_style := StyleBoxFlat.new()
	inactive_style.bg_color = INACTIVE_COLOR
	for section in _nav_buttons:
		var btn = _nav_buttons[section]
		var style = active_style if section == active_section else inactive_style
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		for c in btn.get_children():
			if c is ColorRect:
				c.queue_free()
		if section == active_section:
			var overlay := ColorRect.new()
			overlay.color = Color(0, 0, 0, 0.7)
			overlay.anchors_preset = 15
			btn.add_child(overlay)
			btn.move_child(overlay, 0)

func _on_shop_item_purchased(gems_amount: int) -> void:
	GameState.add_gems(gems_amount)

func _on_daily_gift_pressed() -> void:
	_play_click()
	if GameState.can_claim_daily():
		var reward: int = GameState.claim_daily()
		_show_placeholder("Day %d gift: +%d gems!" % [GameState.daily_streak, reward])
	else:
		_show_placeholder("Already claimed today.\nCome back tomorrow!")

func _show_placeholder(message: String) -> void:
	placeholder_label.text = message
	placeholder_popup.visible = true

func _on_placeholder_close_pressed() -> void:
	_play_click()
	placeholder_popup.visible = false

func _on_achievements_pressed() -> void:
	_play_click()
	achievements_panel.visible = true
	achievements_panel.refresh()
	_refresh_achievements_badge()

func _on_achievement_unlocked(_id: String) -> void:
	_refresh_achievements_badge()

func _refresh_achievements_badge() -> void:
	achievements_badge.visible = GameState.has_unclaimed_achievements()
