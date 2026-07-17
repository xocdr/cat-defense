extends Control
class_name UpgradeRow

## Emitted when the player taps a stat tab, with the GameState.Stat value selected.
signal stat_selected(stat: int)

@onready var bg_locked: TextureRect = $BgLocked
@onready var bg_unlocked: TextureRect = $BgUnlocked
@onready var aura: TextureRect = $Aura
@onready var portrait: TextureRect = $Portrait
@onready var name_label: Label = $NameLabel
@onready var tier_label: Label = $TierLabel
@onready var pip_bar: TextureRect = $PipBar
@onready var cards_label: Label = $CardsLabel
@onready var cost_label: Label = $CostLabel
@onready var buy_button: TextureButton = $BuyButton
@onready var buy_button_label: Label = $BuyButton/Label
@onready var click_overlay: ColorRect = $ClickOverlay
@onready var stat_tabs: HBoxContainer = $StatTabs
@onready var dmg_tab: Button = $StatTabs/DmgTab
@onready var rate_tab: Button = $StatTabs/RateTab
@onready var range_tab: Button = $StatTabs/RangeTab

func _ready() -> void:
	dmg_tab.pressed.connect(func(): stat_selected.emit(GameState.Stat.DAMAGE))
	rate_tab.pressed.connect(func(): stat_selected.emit(GameState.Stat.FIRE_RATE))
	range_tab.pressed.connect(func(): stat_selected.emit(GameState.Stat.RANGE))
