class_name ArrestController
extends Node
## Closes the "Busted" half of the fail loop. While the player is wanted and an
## officer corners them (within catch range), a grapple timer builds; once it
## holds for grapple_time the bust lands — the player is hauled to the nearest
## station (spawn point), forfeits a slice of cash, and the heat clears. Drives
## the pure, tested ArrestModel from live positions, self-wiring by group
## (player, police, wanted, player_stats, spawn_points) — no scene plumbing.

signal busted(fee: int)

## How close an officer must be to start cuffing the player.
@export var catch_distance: float = 2.0
## Seconds cornered before the bust lands.
@export var grapple_time: float = ArrestModel.DEFAULT_GRAPPLE_TIME
## Fraction of the wallet forfeited on a bust.
@export var cash_penalty: float = ArrestModel.DEFAULT_CASH_PENALTY

var _time_held: float = 0.0
var _player: Node3D = null
var _tracker: Node = null
var _police: GroupCache = null


func _ready() -> void:
	_police = GroupCache.for_group(get_tree(), "police")
	add_to_group("arrest")


func _physics_process(delta: float) -> void:
	_bind()
	if _player == null or _tracker == null or not _tracker.has_method("stars"):
		return
	var cornered := ArrestModel.cornered(
		_tracker.stars(), _nearest_cop_distance(delta), catch_distance
	)
	_time_held = ArrestModel.tick_grapple(_time_held, cornered, delta)
	if ArrestModel.is_busted(_time_held, grapple_time):
		_apply_bust()


## 0 → 1 as the cuffs close in, for a HUD prompt.
func grapple_progress() -> float:
	return clampf(_time_held / grapple_time, 0.0, 1.0) if grapple_time > 0.0 else 0.0


func _apply_bust() -> void:
	_time_held = 0.0
	var fee := 0
	var stats := get_tree().get_first_node_in_group("player_stats")
	if stats != null and stats.has_method("spend_money") and "money" in stats:
		fee = ArrestModel.bust_fee(int(stats.money), cash_penalty)
		stats.spend_money(fee)
	if _tracker.has_method("clear"):
		_tracker.clear()
	_haul_to_station()
	busted.emit(fee)


func _haul_to_station() -> void:
	var spawn := get_tree().get_first_node_in_group("spawn_points") as Node3D
	if _player == null or spawn == null:
		return
	_player.global_position = spawn.global_position
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO


## Planar distance to the closest living officer, read from the cached police
## list rather than a fresh group scan every physics frame.
func _nearest_cop_distance(delta: float) -> float:
	if _player == null:
		return INF
	var best := INF
	var here := _player.global_position
	for cop in _police.nodes(delta):
		var officer := cop as Node3D
		if officer == null or (officer.has_method("is_dead") and officer.is_dead()):
			continue
		best = minf(
			best,
			Vector2(officer.global_position.x - here.x, officer.global_position.z - here.z).length()
		)
	return best


func _bind() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _tracker == null or not is_instance_valid(_tracker):
		_tracker = get_tree().get_first_node_in_group("wanted")
