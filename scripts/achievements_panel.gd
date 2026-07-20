extends Control

## Achievement list popup: rows are built at runtime from GameState.ACHIEVEMENTS
## since the catalog can grow without touching this scene.

const CLICK_SFX_PATH := "res://sfx/boink.mp3"
const ICON_PATH := "res://Png/Ui/Uplogo1.png"

const DONE_COLOR := Color(0.55, 1, 0.45, 1)
const READY_COLOR := Color(1, 0.85, 0.4, 1)
const LOCKED_COLOR := Color(0.75, 0.75, 0.75, 1)

@onready var rows_container: VBoxContainer = $Card/Margin/VBox/Scroll/RowsContainer
@onready var close_button: Button = $Card/Margin/VBox/Header/CloseButton

var _click_player: AudioStreamPlayer
var _progress_labels: Dictionary = {}   # id -> Label
var _claim_buttons: Dictionary = {}     # id -> Button

func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = load(CLICK_SFX_PATH)
	add_child(_click_player)
	close_button.pressed.connect(_on_close_pressed)
	$Dim.gui_input.connect(_on_dim_input)
	_build_rows()

func _play_click() -> void:
	if GameState.sound_on:
		_click_player.play()

func refresh() -> void:
	for ach in GameState.ACHIEVEMENTS:
		var id: String = ach["id"]
		var progress: int = GameState.achievement_progress(ach)
		var goal: int = int(ach["goal"])
		var label: Label = _progress_labels[id]
		var button: Button = _claim_buttons[id]
		if GameState.is_achievement_claimed(id):
			label.text = "Claimed"
			label.modulate = DONE_COLOR
			button.visible = false
		elif progress >= goal:
			label.text = "%d / %d" % [progress, goal]
			label.modulate = READY_COLOR
			button.visible = true
			button.disabled = false
		else:
			label.text = "%d / %d" % [progress, goal]
			label.modulate = LOCKED_COLOR
			button.visible = false

func _build_rows() -> void:
	for ach in GameState.ACHIEVEMENTS:
		rows_container.add_child(_make_row(ach))
	refresh()

func _make_row(ach: Dictionary) -> Control:
	var id: String = ach["id"]
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	var icon := TextureRect.new()
	icon.texture = load(ICON_PATH)
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	hbox.add_child(text_box)

	var name_label := Label.new()
	name_label.text = String(ach["name"])
	name_label.add_theme_font_size_override("font_size", 16)
	text_box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = String(ach["desc"])
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.modulate = Color(0.85, 0.85, 0.85)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_box.add_child(desc_label)

	var progress_label := Label.new()
	progress_label.add_theme_font_size_override("font_size", 12)
	text_box.add_child(progress_label)
	_progress_labels[id] = progress_label

	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 4)
	hbox.add_child(right_box)

	var reward_label := Label.new()
	reward_label.text = "+%d gems" % int(ach["reward_gems"])
	reward_label.add_theme_font_size_override("font_size", 12)
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_box.add_child(reward_label)

	var claim_button := Button.new()
	claim_button.text = "Claim"
	claim_button.pressed.connect(_on_claim_pressed.bind(id))
	right_box.add_child(claim_button)
	_claim_buttons[id] = claim_button

	return panel

func _on_claim_pressed(id: String) -> void:
	_play_click()
	if GameState.claim_achievement(id) > 0:
		refresh()

func _on_close_pressed() -> void:
	_play_click()
	visible = false

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_close_pressed()
