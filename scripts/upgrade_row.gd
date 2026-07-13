extends Control
class_name UpgradeRow

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
