class_name TrafficCar
extends Node3D
## A lightweight kinematic ambient-traffic car: follows a list of world waypoints
## (typically straight from NavGrid.find_path) by turn-rate-limited steering, so
## it arcs through corners and faces where it's going. Visual-only — it carries
## a decimated production coupe or sedan so a street of these matches the
## player's vehicles. It still steers kinematically (far cheaper than a full
## VehicleBody3D per car) but carries a solid collision body on the world layer,
## so the player, NPCs and other vehicles can't walk or drive through it.
##
## Steering maths is the pure, tested TrafficMotion; this node owns the state, the
## mesh and the collider. Hand it a route with set_route(); poll is_done() to know
## when to give it a new one (the TrafficDirector does this).

## World collision layer (matches BuildingCollision.WORLD_LAYER) — the solid layer
## the player, NPCs and vehicles all collide against, so a body placed here blocks
## every one of them.
const SOLID_LAYER := 1
## Fallback collision-box extents (m: width, height, length), used only if the
## decimated visual has no mesh AABB to size the body from.
const DEFAULT_CAR_EXTENTS := Vector3(1.9, 1.4, 4.4)

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
var _tick_pos: Vector3 = Vector3.INF
var _stuck_time: float = 0.0
var _body: AnimatableBody3D = null


func _ready() -> void:
	# Joins "ambient_cars" so the player can walk up and jack any of them — the
	# Player swaps the car it finds here for a real drivable Car of the same model.
	add_to_group("ambient_cars")
	var visual := VehicleVisualLibrary.instantiate_traffic(model_variant)
	if visual != null:
		visual.name = "VehicleVisual"
		add_child(visual)
	_add_solid_body(visual)


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


## Called once per TrafficDirector tick: accumulates how long the car has failed
## to make progress (gridlocked or boxed in by other cars), reset the moment it
## moves. The director culls cars stuck past its timeout so a jam can't persist.
func note_tick(dt: float, progress: float = 0.5) -> void:
	if _tick_pos == Vector3.INF or global_position.distance_to(_tick_pos) > progress:
		_stuck_time = 0.0
	else:
		_stuck_time += dt
	_tick_pos = global_position


func stuck_time() -> float:
	return _stuck_time


## True once the car carries its solid collision body on the world layer.
func is_solid() -> bool:
	return _body != null and (_body.collision_layer & SOLID_LAYER) != 0


## The {size, center} of a collision box wrapping a visual's local mesh `aabb`,
## lifted by `lift` (the visual's own y offset) so the box hugs the bodywork.
## Pure, so the sizing is unit-tested without a scene.
static func solid_box(aabb: AABB, lift: float) -> Dictionary:
	return {
		"size": aabb.size,
		"center": aabb.position + aabb.size * 0.5 + Vector3(0.0, lift, 0.0),
	}


## Give the car a solid body so the player, NPCs and other vehicles can't pass
## through it. The car drives kinematically, so an AnimatableBody3D — repositioned
## by our transform each physics frame — is a moving obstacle on the world layer
## that never gets knocked off its route (its own mask is 0, so nothing pushes
## IT). sync_to_physics stays off: we only need it to BLOCK, and leaving it off
## keeps the spawn teleport from imparting a shove. Sized to the visual mesh.
func _add_solid_body(visual: MeshInstance3D) -> void:
	var box := BoxShape3D.new()
	var center := Vector3(0.0, DEFAULT_CAR_EXTENTS.y * 0.5, 0.0)
	if visual != null and visual.mesh != null:
		var spec := solid_box(visual.mesh.get_aabb(), visual.position.y)
		box.size = spec["size"]
		center = spec["center"]
	else:
		box.size = DEFAULT_CAR_EXTENTS
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = center
	_body = AnimatableBody3D.new()
	_body.name = "SolidBody"
	_body.sync_to_physics = false
	_body.collision_layer = SOLID_LAYER
	_body.collision_mask = 0
	_body.add_child(shape)
	add_child(_body)


func _physics_process(delta: float) -> void:
	_index = TrafficMotion.advance_waypoint(global_position, _waypoints, _index, arrive_tolerance)
	if is_done():
		if loop and _waypoints.size() > 0:
			_index = 0
		else:
			return
	var target := _waypoints[_index]
	var cruise := speed if speed_limit < 0.0 else minf(speed, speed_limit)
	# Ease off through corners so a sharp turn arc is tracked, not overshot.
	var desired := TrafficMotion.planar_dir(global_position, target)
	var drive_speed := cruise * TrafficMotion.corner_speed_scale(_heading, desired)
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
