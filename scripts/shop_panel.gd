extends Control

## Placeholder shop: every "purchase" just grants gems immediately.
## No real payment backend exists yet -- wire item_purchased into an
## IAP/ad-reward plugin when one is added, keeping this signal contract.

signal item_purchased(gems: int)

const PRICE_BUTTON_PATHS := [
	"Panel/DealsRow/BestDeals/PriceButton",
	"Panel/DealsRow/SuperPackage/PriceButton",
	"Panel/PacksRow/Pack1/PriceButton",
	"Panel/PacksRow/Pack2/PriceButton",
	"Panel/PacksRow/Pack3/PriceButton",
	"Panel/PacksRow/Pack4/PriceButton",
	"Panel/PacksRow/Pack5/PriceButton",
]

func _ready() -> void:
	visible = false
	for path in PRICE_BUTTON_PATHS:
		var button: BaseButton = get_node(path)
		button.pressed.connect(_on_item_pressed.bind(button))

func open() -> void:
	visible = true

func _on_item_pressed(button: BaseButton) -> void:
	var gems: int = button.get_meta("gems", 0)
	if gems > 0:
		item_purchased.emit(gems)
