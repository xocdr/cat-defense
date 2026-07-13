class_name CoinPickup
extends Node2D

signal collected(pickup: CoinPickup)

@export var value: int = 1

const LIFETIME := 5.0
const BOUNCE_OFFSET := 28.0
const COIN_ICON := preload("res://Png/Ui/CoinIcon.png")

var _lifetime: float = LIFETIME
var _collected: bool = false
var _sprite: Sprite2D
var _base_y: float

func _ready() -> void:
	add_to_group("coin_pickups")
	_sprite = Sprite2D.new()
	_sprite.texture = COIN_ICON
	_sprite.scale = Vector2.ZERO
	add_child(_sprite)
	_base_y = position.y
	_bounce_in()

func _bounce_in() -> void:
	position.y = _base_y + BOUNCE_OFFSET
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sprite, "scale", Vector2(0.45, 0.45), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", _base_y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if _collected:
		return
	_lifetime -= delta
	if _lifetime <= 1.0 and _lifetime > 0.0:
		modulate.a = 0.5 + 0.5 * sin(_lifetime * 20.0)
	if _lifetime <= 0.0:
		_auto_collect()
		return
	_sprite.position.y = sin(Time.get_ticks_msec() * 0.003) * 2.0

func collect() -> void:
	if _collected:
		return
	_collected = true
	collected.emit(self)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:y", position.y - 30.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sprite, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)

func _auto_collect() -> void:
	if _collected:
		return
	_collected = true
	collected.emit(self)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
