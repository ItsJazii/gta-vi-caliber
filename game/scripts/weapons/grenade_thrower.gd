class_name GrenadeThrower
extends Node
## Throws a grenade on the "throw_grenade" action (G / gamepad), arcing from the
## player's hand along the camera heading.
##
## Carries a small pouch that slowly refills, so you're never permanently out
## without a pickup economy, but can't spam either. Self-contained: finds the
## player by group and the aim from the active camera, spawns the grenade into the
## current scene with an initial velocity, and a short cooldown stops double-taps.
## The HUD reads grenade_count()/max_count() (group "grenade_thrower").

## Emitted whenever the pouch count changes, so the HUD can update without polling.
signal grenades_changed(count: int, maximum: int)

const GRENADE_SCENE := preload("res://scenes/weapons/grenade.tscn")

@export var throw_force: float = 15.0
@export var up_force: float = 4.5
@export var cooldown: float = 0.8
## Grenades carried, and how long (s) to regenerate one when below the cap; set
## regen_seconds to 0 to disable refilling.
@export var max_grenades: int = 3
@export var regen_seconds: float = 25.0

var _cooldown_left: float = 0.0
var _grenades: int = 0
var _regen_left: float = 0.0


func _ready() -> void:
	add_to_group("grenade_thrower")
	_grenades = max_grenades
	_regen_left = regen_seconds


func _process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if regen_seconds > 0.0 and _grenades < max_grenades:
		_regen_left -= delta
		if _regen_left <= 0.0:
			_grenades += 1
			_regen_left = regen_seconds
			grenades_changed.emit(_grenades, max_grenades)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("throw_grenade") and _can_throw():
		_throw()


## Grenades currently in the pouch, and the pouch capacity — read by the HUD.
func grenade_count() -> int:
	return _grenades


func max_count() -> int:
	return max_grenades


func _can_throw() -> bool:
	return _cooldown_left <= 0.0 and _grenades > 0


func _throw() -> void:
	var player := _player()
	var cam := get_viewport().get_camera_3d()
	var scene := get_tree().current_scene
	if player == null or cam == null or scene == null:
		return
	_cooldown_left = cooldown
	_grenades -= 1
	_regen_left = regen_seconds
	grenades_changed.emit(_grenades, max_grenades)
	var forward := -cam.global_transform.basis.z
	var grenade := GRENADE_SCENE.instantiate()
	scene.add_child(grenade)
	grenade.global_position = player.global_position + Vector3(0.0, 1.4, 0.0) + forward * 0.6
	if grenade is RigidBody3D:
		(grenade as RigidBody3D).linear_velocity = forward * throw_force + Vector3.UP * up_force


func _player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if not players.is_empty() else null
