class_name PoliceSpawner
extends Node3D
## Dynamic police escalation: while the player is wanted, keep the right number of
## officers in the field for the current heat and feed reinforcements in from
## rings that widen with the stars. Drop this node into a world scene and assign
## `police_scene` (res://scenes/npc/police.tscn).
##
## All the escalation math is the pure, tested PoliceDispatch model; this node is
## just the lifecycle shell — it polls heat on an interval, frees recalled units,
## and instances fresh ones ground-snapped onto the response ring. Spawned cops
## run their own PoliceCombat brain, so reinforcements actually shoot back.

## The officer scene to instance (res://scenes/npc/police.tscn).
@export var police_scene: PackedScene
## Hard cap on live officers regardless of heat (frame-budget guard).
@export var max_alive: int = 8
## Officers added per spawn wave, so pressure ramps in instead of popping.
@export var max_per_wave: int = 2
## Seconds between dispatch ticks.
@export var spawn_interval: float = 1.6
## Officers beyond this planar distance from the player are recalled and re-placed.
@export var despawn_radius: float = 160.0
## Metres of random distance wobble applied to ring spawns.
@export var radial_jitter: float = 6.0
## Downward ground probe: start this high above the ring point …
@export var ground_probe_height: float = 60.0
## … and cast this far down looking for a floor to drop the officer onto.
@export var ground_probe_depth: float = 120.0

var _units: Array[Node3D] = []
var _accum: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < spawn_interval:
		return
	_accum = 0.0
	_tick()


func _tick() -> void:
	_prune()
	var player := _first_player()
	var stars := _current_stars()
	_recall(player, stars)

	if player == null or police_scene == null or stars <= 0:
		return
	var count := PoliceDispatch.spawn_count(stars, _units.size(), max_alive, max_per_wave)
	if count <= 0:
		return
	var radius := PoliceResponse.spawn_radius(stars)
	for i in count:
		var angle := PoliceDispatch.ring_angle(i, count, _rng.randf(), 1.0)
		var spot := PoliceDispatch.ring_position(
			player.global_position, radius, angle, _rng.randf(), radial_jitter
		)
		_spawn_one(_ground_snap(spot))


## Free officers PoliceDispatch says to recall (heat cleared, or fallen too far).
## When heat drops mid-chase (e.g. 5→3 stars) the desired count shrinks but the
## extra units linger until they drift past despawn_radius — natural attrition,
## not an instant vanish, which reads better than cops popping out of existence.
func _recall(player: Node3D, stars: int) -> void:
	for unit in _units.duplicate():
		var dist := (
			INF
			if player == null
			else NpcBrain.planar_distance(unit.global_position, player.global_position)
		)
		if PoliceDispatch.should_despawn(stars, dist, despawn_radius):
			unit.queue_free()
			_units.erase(unit)


func _spawn_one(spot: Vector3) -> void:
	var unit := police_scene.instantiate() as Node3D
	if unit == null:
		return
	add_child(unit)
	unit.global_position = spot
	_units.append(unit)


## Drop a planar ring point onto the floor below it; keep its height if nothing
## is found (e.g. spawned over a gap).
func _ground_snap(spot: Vector3) -> Vector3:
	# The 2-arg create() defaults collision_mask to all layers, so this hits any
	# solid floor (the world is on layer 1).
	var query := PhysicsRayQueryParameters3D.create(
		spot + Vector3.UP * ground_probe_height, spot + Vector3.DOWN * ground_probe_depth
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return spot
	var grounded := spot
	grounded.y = (hit["position"] as Vector3).y
	return grounded


func _prune() -> void:
	var alive: Array[Node3D] = []
	for unit in _units:
		if is_instance_valid(unit):
			alive.append(unit)
	_units = alive


func _first_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if not players.is_empty() else null


func _current_stars() -> int:
	for tracker in get_tree().get_nodes_in_group("wanted"):
		if tracker.has_method("stars"):
			return tracker.stars()
	return 0
