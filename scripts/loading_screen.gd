extends Control

## Title/splash screen: preloads the Lobby in the background while showing
## a pulsing "Tap To Play" prompt. Any tap/click/key advances -- if the
## background load isn't done yet, it shows "Loading..." and continues
## as soon as the load finishes, instead of blocking input up front.

const LOBBY_SCENE_PATH := "res://scenes/Lobby.tscn"

@onready var status_label: Label = $StatusLabel

var _tapped: bool = false

func _ready() -> void:
	ResourceLoader.load_threaded_request(LOBBY_SCENE_PATH)
	set_process(false)
	_pulse_label()
	_run_ambient_explosions()

func _pulse_label() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(status_label, "modulate:a", 0.25, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(status_label, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)

func _run_ambient_explosions() -> void:
	while not _tapped:
		await get_tree().create_timer(randf_range(1.2, 2.4)).timeout
		if _tapped or not is_inside_tree():
			return
		_spawn_random_explosion()

func _spawn_random_explosion() -> void:
	var size := get_viewport_rect().size
	# stay clear of the centered logo/status text, favor the open "road" gap
	var pos := Vector2(
		randf_range(size.x * 0.06, size.x * 0.94),
		randf_range(size.y * 0.08, size.y * 0.62),
	)
	Fx.explosion(self, pos, randf_range(0.22, 0.32))

func _input(event: InputEvent) -> void:
	if _tapped:
		return
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventKey and event.pressed):
		_tapped = true
		_on_tap()
		get_viewport().set_input_as_handled()

func _on_tap() -> void:
	status_label.text = "Loading..."
	set_process(true)
	var tap_pos: Vector2 = get_viewport_rect().size / 2.0
	Fx.explosion(self, tap_pos, 0.55)
	_shake()

func _shake() -> void:
	var tween := create_tween()
	var base_pos := position
	for i in range(5):
		tween.tween_property(self, "position", base_pos + Vector2(randf_range(-8, 8), randf_range(-8, 8)), 0.04)
	tween.tween_property(self, "position", base_pos, 0.04)

func _process(_delta: float) -> void:
	var status := ResourceLoader.load_threaded_get_status(LOBBY_SCENE_PATH)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_finish_loading()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("LoadingScreen: failed to preload %s" % LOBBY_SCENE_PATH)
			_finish_loading()

func _finish_loading() -> void:
	set_process(false)
	SceneTransition.change_scene(LOBBY_SCENE_PATH)
