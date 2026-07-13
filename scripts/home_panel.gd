extends Control

signal navigate_to_shop

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const CLICK_SFX_PATH := "res://sfx/boink.mp3"

const TEX_LEVEL_CURRENT := "res://Png/Ui/GreenLevel.png"
const TEX_LEVEL_DONE := "res://Png/Ui/OrangeLvl.png"
const TEX_LEVEL_LOCKED := "res://Png/Ui/LockedLevel.png"

@onready var map_content: Control = $MapScroll/MapContent

var _click_player: AudioStreamPlayer

func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = load(CLICK_SFX_PATH)
	add_child(_click_player)

func _play_click() -> void:
	if GameState.sound_on:
		_click_player.play()

func refresh() -> void:
	_setup_levels()

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
		if not button.pressed.is_connected(_on_level_pressed.bind(i)):
			button.pressed.connect(_on_level_pressed.bind(i))

func _on_level_pressed(level: int) -> void:
	_play_click()
	if not GameState.is_level_unlocked(level):
		return
	GameState.selected_level = level
	SceneTransition.change_scene(MAIN_SCENE_PATH)
