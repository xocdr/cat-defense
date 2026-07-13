extends Control

## Placeholder shop: every "purchase" just grants gems immediately.
## No real payment backend exists yet -- wire item_purchased into an
## IAP/ad-reward plugin when one is added, keeping this signal contract.

signal item_purchased(gems: int)
signal navigate_to_shop

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
	for path in PRICE_BUTTON_PATHS:
		var button: BaseButton = get_node(path)
		button.pressed.connect(_on_item_pressed.bind(button))
	$GemsHud.add_pressed.connect(_on_gems_add_pressed)

func refresh() -> void:
	$GemsHud.refresh()

func _on_gems_add_pressed() -> void:
	navigate_to_shop.emit()

func _on_item_pressed(button: BaseButton) -> void:
	var gems: int = button.get_meta("gems", 0)
	if gems > 0:
		item_purchased.emit(gems)
