class_name TrafficDirector
extends Node3D
## Streams ambient traffic around the player: spawns kinematic TrafficCars at the
## edge of view, routes each along the NavGrid, repaths it when it arrives, and
## culls cars that fall far behind — the vehicle counterpart to CrowdDirector,
## sharing the same A* nav grid so traffic and pedestrians respect the same
## streets and building footprints.
##
## Cars drive on a flat road plane at the player's height (terrain elevation is a
## later refinement). Assign `nav` (a NavGrid, optionally baked from the world) to
## get street-following routes; without one, cars cruise straight to random
## nearby points — fine for an open sandbox.

@export var car_scene: PackedScene  ## Optional; defaults to a bare TrafficCar.
@export var target_count: int = 8
@export var spawn_min_radius: float = 22.0
@export var spawn_max_radius: float = 40.0
@export var cull_radius: float = 56.0
@export var tick_interval: float = 0.5
@export var spawn_budget: int = 2
## How far ahead (m) to pick each car's next destination when routing.
@export var trip_radius: float = 60.0
@export var walkable_attempts: int = 8
## Auto-build the routing grid from the physics world on the first tick (same
## scheme as CrowdDirector): raycast a coarse grid from above the rooflines and
## block cells that hit a building/wall or no ground. Off → assign `nav` yourself
## (e.g. share a CrowdDirector's grid) or leave null for straight-line cruising.
@export var bake_nav: bool = false
@export var nav_cell_size: float = 3.0
@export var nav_radius: float = 110.0
@export var nav_probe_height: float = 400.0
@export var ground_probe_down: float = 60.0
@export var max_walkable_rise: float = 2.5
@export_flags_3d_physics var ground_mask: int = 1
## Palette for body paint variety across the fleet.
@export var car_colors: PackedColorArray = PackedColorArray(
	[
		Color(0.72, 0.20, 0.20),
		Color(0.16, 0.18, 0.22),
		Color(0.85, 0.85, 0.88),
		Color(0.20, 0.34, 0.58),
		Color(0.55, 0.56, 0.60),
		Color(0.80, 0.66, 0.20)
	]
)

var nav: NavGrid = null

var _cars: Array[TrafficCar] = []
var _rng := RandomNumberGenerator.new()
var _accum: float = 0.0


func _ready() -> void:
	_rng.randomize()


func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < tick_interval:
		return
	_accum = 0.0
	var player := _player()
	if player == null:
		return
	var center := player.global_position
	if bake_nav and nav == null:
		_bake_nav(center)
	_cull(center)
	_repath(center)
	_spawn(center)


## Raycast a coarse grid of the area into a NavGrid, blocking cells whose ground
## is missing or above max_walkable_rise (buildings/walls/voids). Mirrors
## CrowdDirector so pedestrians and traffic build identical street maps.
func _bake_nav(center: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var cells := maxi(int(2.0 * nav_radius / nav_cell_size), 1)
	var grid := NavGrid.new(
		cells, cells, nav_cell_size, Vector3(center.x - nav_radius, center.y, center.z - nav_radius)
	)
	var ceiling := center.y + max_walkable_rise
	for r in cells:
		for c in cells:
			var at := grid.cell_to_world(c, r)
			var from := Vector3(at.x, center.y + nav_probe_height, at.z)
			var to := Vector3(at.x, center.y - ground_probe_down, at.z)
			var hit := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(from, to, ground_mask)
			)
			if not hit.has("position") or (hit["position"] as Vector3).y > ceiling:
				grid.set_blocked(c, r, true)
	nav = grid


func _cull(center: Vector3) -> void:
	var survivors: Array[TrafficCar] = []
	for car in _cars:
		if not is_instance_valid(car):
			continue
		if TrafficMotion.planar_distance(car.global_position, center) > cull_radius:
			car.queue_free()
		else:
			survivors.append(car)
	_cars = survivors


## Give any car that has finished its route a fresh destination, so traffic keeps
## flowing instead of parking at the end of each trip.
func _repath(center: Vector3) -> void:
	for car in _cars:
		if is_instance_valid(car) and car.is_done():
			_assign_route(car, center)


func _spawn(center: Vector3) -> void:
	var n: int = mini(maxi(target_count - _cars.size(), 0), maxi(spawn_budget, 0))
	for _i in n:
		var pos := _walkable_point(center, spawn_min_radius, spawn_max_radius)
		if pos == Vector3.INF:
			continue
		var car := _make_car()
		add_child(car)
		car.global_position = Vector3(pos.x, center.y, pos.z)
		_assign_route(car, center)
		_cars.append(car)


func _make_car() -> TrafficCar:
	var car: TrafficCar
	if car_scene != null:
		car = car_scene.instantiate() as TrafficCar
	if car == null:
		car = TrafficCar.new()
	if car_colors.size() > 0:
		car.body_color = car_colors[_rng.randi() % car_colors.size()]
	return car


## Route a car to a fresh reachable destination within trip_radius. With a nav
## grid the path follows streets (NavGrid.find_path); without one the car drives
## straight to the point.
func _assign_route(car: TrafficCar, center: Vector3) -> void:
	var dest := _walkable_point(center, 0.0, trip_radius)
	if dest == Vector3.INF:
		return
	dest.y = car.global_position.y
	if nav != null:
		var path := nav.find_path(car.global_position, dest)
		if path.size() >= 2:
			# Flatten the route onto the car's drive plane.
			for i in path.size():
				path[i] = Vector3(path[i].x, car.global_position.y, path[i].z)
			car.set_route(path)
			return
	car.set_route(PackedVector3Array([car.global_position, dest]))


## A point in the annulus [min_r, max_r] around center that sits on an open nav
## cell, or Vector3.INF if no sample lands clear. Without a nav grid the first
## sample is returned.
func _walkable_point(center: Vector3, min_r: float, max_r: float) -> Vector3:
	var attempts: int = walkable_attempts if nav != null else 1
	for _a in attempts:
		var ang := _rng.randf() * TAU
		var r := sqrt(maxf(min_r, 0.0) ** 2 + (max_r ** 2 - maxf(min_r, 0.0) ** 2) * _rng.randf())
		var p := center + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		if nav == null:
			return p
		var cell := nav.world_to_cell(p)
		if not nav.is_blocked(cell.x, cell.y):
			return p
	return Vector3.INF


func population() -> int:
	var live := 0
	for car in _cars:
		if is_instance_valid(car):
			live += 1
	return live


func _player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D
