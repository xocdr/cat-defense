extends PopupPanel
class_name SkinPicker

## Emitted after the player equips or purchases a skin, so the caller can
## refresh whatever portrait/preview is showing that character.
signal skin_changed(char_index: int)

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var list: VBoxContainer = $VBoxContainer/SkinList

var _char_index: int = 1

func open_for(char_index: int) -> void:
	_char_index = char_index
	title_label.text = "Skins — C%d" % char_index
	_rebuild_list()
	popup_centered()

func _rebuild_list() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var entries: Array = [{"id": GameState.DEFAULT_SKIN_ID, "name": "Classic", "cost": 0}]
	for entry in GameState.SKIN_CATALOG.get(_char_index, []):
		entries.append(entry)
	for entry in entries:
		list.add_child(_build_entry_row(entry))

func _build_entry_row(entry: Dictionary) -> Control:
	var skin_id: String = entry["id"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	name_label.text = String(entry["name"])
	name_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_label)

	var action_button := Button.new()
	if GameState.equipped_skin_for(_char_index) == skin_id:
		action_button.text = "Equipped"
		action_button.disabled = true
	elif GameState.is_skin_owned(_char_index, skin_id):
		action_button.text = "Equip"
		action_button.pressed.connect(_on_equip_pressed.bind(skin_id))
	else:
		action_button.text = "Buy (%d)" % int(entry["cost"])
		action_button.disabled = not GameState.can_purchase_skin(_char_index, skin_id)
		action_button.pressed.connect(_on_buy_pressed.bind(skin_id))
	row.add_child(action_button)
	return row

func _on_equip_pressed(skin_id: String) -> void:
	GameState.equip_skin(_char_index, skin_id)
	skin_changed.emit(_char_index)
	_rebuild_list()

func _on_buy_pressed(skin_id: String) -> void:
	if GameState.purchase_skin(_char_index, skin_id):
		GameState.equip_skin(_char_index, skin_id)
		skin_changed.emit(_char_index)
	_rebuild_list()
