class_name PortalMarker
extends Node2D

## Marks where Hunt mode's enemies emerge from off-screen. Position and
## height are authored visually in HuntArea.tscn (drag the node, edit
## `height` in the Inspector) instead of computed from row_y math in main.gd.
@export var height: float = 546.0
