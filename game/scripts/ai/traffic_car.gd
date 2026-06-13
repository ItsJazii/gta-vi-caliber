class_name TrafficCar
extends Node3D
## A lightweight kinematic ambient-traffic car: follows a list of world waypoints
## (typically straight from NavGrid.find_path) by turn-rate-limited steering, so
## it arcs through corners and faces where it's going. Visual-only — it carries
## a decimated production coupe or sedan so a street of these matches the
## player's vehicles without the cost of a full VehicleBody3D per car.
##
## Steering maths is the pure, tested TrafficMotion; this node only owns the
## state and the mesh. Hand it a route with set_route(); poll is_done() to know
## when to give it a new one (the TrafficDirector does this).

@export var speed: float = 9.0
@export var max_turn_rate: float = 2.2  # rad/s
@export var arrive_tolerance: float = 2.0
@export var model_variant: int = VehicleVisualLibrary.Variant.SPORT_COUPE
## Loop the route forever (handy for a standalone demo); the director leaves this
## off and repaths on completion instead.
@export var loop: bool = false

## Per-tick speed cap set by the director's car-following (TrafficFlow); negative
## means uncapped. Lets a car slow or stop for the vehicle ahead without changing
## its own cruising `speed`.
var speed_limit: float = -1.0

var _waypoints: PackedVector3Array = PackedVector3Array()
var _index: int = 0
var _heading: Vector3 = Vector3(0, 0, 1)


func _ready() -> void:
	var visual := VehicleVisualLibrary.instantiate_traffic(model_variant)
	if visual != null:
		visual.name = "VehicleVisual"
		add_child(visual)


## Start following a new route. The car snaps its heading toward the first leg so
## it doesn't spin on spawn. Positions are world-space (y is followed as given).
func set_route(waypoints: PackedVector3Array) -> void:
	_waypoints = waypoints
	_index = 0
	if waypoints.size() >= 2:
		_heading = TrafficMotion.planar_dir(waypoints[0], waypoints[1])
		if _heading == Vector3.ZERO:
			_heading = Vector3(0, 0, 1)


func is_done() -> bool:
	return _index >= _waypoints.size()


func heading() -> Vector3:
	return _heading


func _physics_process(delta: float) -> void:
	_index = TrafficMotion.advance_waypoint(global_position, _waypoints, _index, arrive_tolerance)
	if is_done():
		if loop and _waypoints.size() > 0:
			_index = 0
		else:
			return
	var target := _waypoints[_index]
	var drive_speed := speed if speed_limit < 0.0 else minf(speed, speed_limit)
	var r := TrafficMotion.step(
		global_position, _heading, target, drive_speed, max_turn_rate, delta
	)
	global_position = r["position"]
	_heading = r["heading"]
	# Face travel direction (heading is planar unit, so look along it on the flat).
	var look := global_position + _heading
	look.y = global_position.y
	if _heading.length() > 0.0001:
		look_at(look, Vector3.UP)
