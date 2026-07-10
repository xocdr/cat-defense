class_name Slot
extends Node2D

## A cell of the merge board. The visual squares (and the trash-can icon on
## the trash cell) are baked into the Area backgrounds; this node only tracks
## occupancy and shows a highlight while a dragged cat hovers over it.

const TINT_MERGE := Color(0.55, 1.0, 0.45, 0.6)   # same-level pair: merging
const TINT_MOVE := Color(1.0, 1.0, 1.0, 0.35)     # empty cell / swap
const TINT_SELL := Color(1.0, 0.75, 0.2, 0.6)     # trash: valid but destructive

@export var row: int = 0
@export var col: int = 0
@export var is_trash: bool = false

var occupant: Cat = null

@onready var highlight: Sprite2D = $Highlight

func _ready() -> void:
	highlight.visible = false

func is_free() -> bool:
	return occupant == null and not is_trash

func set_highlight(on: bool, tint: Color = TINT_MOVE) -> void:
	highlight.visible = on
	highlight.modulate = tint
