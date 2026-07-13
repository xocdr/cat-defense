extends TextureRect

signal add_pressed

@onready var gems_label: Label = $GemsLabel
@onready var add_button: TextureButton = $AddButton

func _ready() -> void:
	add_button.pressed.connect(_on_add_pressed)
	GameState.gems_changed.connect(_on_gems_changed)
	refresh()

func refresh() -> void:
	gems_label.text = str(GameState.gems)

func _on_add_pressed() -> void:
	add_pressed.emit()

func _on_gems_changed(_gems: int) -> void:
	refresh()
