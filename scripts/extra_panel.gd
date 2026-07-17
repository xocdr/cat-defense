extends Control

signal navigate_to_shop

const CLICK_SFX_PATH := "res://sfx/boink.mp3"

const ITEM_DEFS := [
	{"id": "spikes", "name": "Spikes"},
	{"id": "tnt", "name": "TNT"},
	{"id": "boxer", "name": "Boxing Cat"},
	{"id": "poison", "name": "Poison Cloud"},
]

var _click_player: AudioStreamPlayer

func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = load(CLICK_SFX_PATH)
	add_child(_click_player)
	$GemsHud.add_pressed.connect(_on_gems_add_pressed)
	_setup_extra_items()

func _play_click() -> void:
	if GameState.sound_on:
		_click_player.play()

func refresh() -> void:
	_refresh_extra_items()
	$GemsHud.refresh()

func _on_gems_add_pressed() -> void:
	navigate_to_shop.emit()

func _setup_extra_items() -> void:
	for i in range(ITEM_DEFS.size()):
		var item_box: Control = get_node("Item%d" % (i + 1))
		item_box.get_node("CostButton").pressed.connect(_on_item_buy_pressed.bind(i))
	_refresh_extra_items()

func _refresh_extra_items() -> void:
	for i in range(ITEM_DEFS.size()):
		var id: String = ITEM_DEFS[i]["id"]
		var count: int = GameState.item_count(id)
		var item_box: Control = get_node("Item%d" % (i + 1))
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
