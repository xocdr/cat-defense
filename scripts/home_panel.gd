extends Control

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const HUNT_SCENE_PATH := "res://scenes/HuntArea.tscn"
const CLICK_SFX_PATH := "res://sfx/boink.mp3"
const TUTORIAL_OVERLAY_SCENE := preload("res://scenes/TutorialOverlay.tscn")

const TEX_LEVEL_CURRENT := "res://Png/Ui/GreenLevel.png"
const TEX_LEVEL_DONE := "res://Png/Ui/OrangeLvl.png"
const TEX_LEVEL_LOCKED := "res://Png/Ui/LockedLevel.png"

@onready var map_content: Control = $MapScroll/MapContent

var _click_player: AudioStreamPlayer
var _tutorial_overlay: CanvasLayer = null

func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = load(CLICK_SFX_PATH)
	add_child(_click_player)
	map_content.get_node("HuntButton").pressed.connect(_on_hunt_pressed)
	if not GameState.tutorial_seen and GameState.tutorial_step == 0:
		call_deferred("_show_tutorial")

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
	if _tutorial_overlay and level == 1:
		GameState.advance_tutorial_step()
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null
	GameState.selected_level = level
	SceneTransition.change_scene(MAIN_SCENE_PATH)

func _on_hunt_pressed() -> void:
	_play_click()
	GameState.hunt_mode = true
	GameState.selected_level = 1
	SceneTransition.change_scene(HUNT_SCENE_PATH)

func _show_tutorial() -> void:
	await SceneTransition.fade_in_finished
	if not is_instance_valid(self) or GameState.tutorial_seen or GameState.tutorial_step != 0:
		return
	var level1: Control = map_content.get_node("Level1")
	var rect := Rect2(level1.get_global_rect())
	_tutorial_overlay = TUTORIAL_OVERLAY_SCENE.instantiate()
	add_child(_tutorial_overlay)
	var step: Dictionary = TutorialSteps.STEPS[0]
	_tutorial_overlay.show_step(step["text"], rect, step["tap_to_continue"])
	_tutorial_overlay.skipped.connect(_on_tutorial_skipped)

func _on_tutorial_skipped() -> void:
	GameState.mark_tutorial_seen()
	if _tutorial_overlay:
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null
