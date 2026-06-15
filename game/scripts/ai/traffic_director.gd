class_name TrafficDirector
extends Node3D
## Streams ambient traffic around the player: spawns kinematic TrafficCars on the
## road just out of view, routes each ALONG THE REAL ROAD GRAPH (RoadNetwork, the
## same OSM streets the traffic signals use), repaths it when it arrives, and
## culls cars that fall far behind.
##
## Cars drive on a flat road plane at the player's height (terrain elevation is a
## later refinement). The map-wide road graph is built once off-thread from the
## district manifest; cars spawn on a street and keep to the right lane, turning
## at junctions like real traffic. If no road data is present (open sandbox) it
## falls back to a baked NavGrid — and, lacking even that, straight cruising to
## random nearby points.

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
## Car-following: a car slows for the nearest vehicle ahead within flow_range and
## flow_lane_half_width, stopping by flow_stop_gap and resuming by flow_safe_gap.
@export var flow_range: float = 28.0
@export var flow_lane_half_width: float = 2.4
@export var flow_stop_gap: float = 5.0
@export var flow_safe_gap: float = 16.0
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
@export var road_surface_y: float = 0.32
## Ambient cars route along the real OSM road graph (RoadNetwork), staying this
## far to the RIGHT of travel so two-way streets don't meet head-on. The graph is
## built once off-thread from the district manifest; routing falls back to the
## NavGrid below only when no road data is present (open sandbox).
@export var lane_half_width: float = 2.0
@export_file("*.json") var road_manifest: String = "res://assets/world/districts.json"
## A car making no progress (gridlocked / boxed in) for longer than this is culled
## and respawned on open road, so a pile-up can never persist.
@export var stuck_timeout: float = 10.0
var nav: NavGrid = null

var _cars: Array[TrafficCar] = []
var _rng := RandomNumberGenerator.new()
var _accum: float = 0.0
var _flow_grid: NeighborGrid = null
var _base_target_count: int = -1
var _roads: RoadNetwork = null
var _roads_thread: Thread = null
var _roads_poll: int = 1
var _origin_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	# Native worldcore SpatialHash when built, GDScript buckets otherwise.
	_flow_grid = NeighborGrid.new(flow_range * 0.5)
	add_to_group("density_aware")
	add_to_group("traffic_director")
	apply_graphics_setting(int(SettingsPanel.load_settings().get("graphics", 1)))
	# Parse the map-wide road graph off the main thread (heavy: thousands of
	# polylines) so it never competes with district streaming during load. Cars
	# spawned before it is ready use the NavGrid/straight fallback for a beat.
	_roads_thread = Thread.new()
	_roads_thread.start(_build_roads)


func _exit_tree() -> void:
	if _roads_thread != null and _roads_thread.is_started():
		_roads_thread.wait_to_finish()
		_roads_thread = null


func apply_graphics_setting(quality: int) -> void:
	if _base_target_count == -1:
		_base_target_count = target_count
	match quality:
		0:
			target_count = maxi(1, int(_base_target_count * 0.25))
		1:
			target_count = maxi(1, int(_base_target_count * 0.6))
		2:
			target_count = _base_target_count


func _physics_process(delta: float) -> void:
	_poll_roads()
	_accum += delta
	if _accum < tick_interval:
		return
	_accum = 0.0
	var player := _player()
	if player == null:
		return
	_origin_offset = _read_origin_offset()
	var center := player.global_position
	# The NavGrid is only the fallback now: bake it solely if the road graph
	# finished building but yielded nothing (no manifest / open sandbox).
	if (
		bake_nav
		and nav == null
		and _roads == null
		and _roads_thread == null
		and _skyline_is_solid()
	):
		_bake_nav(center)
	_cull(center)
	_repath(center)
	_spawn(center)
	_apply_flow()


## Poll the off-thread road-graph build; adopt it the frame after it finishes.
func _poll_roads() -> void:
	if _roads_thread == null:
		return
	if _roads_poll > 0:
		_roads_poll -= 1
	elif not _roads_thread.is_alive():
		_roads = _roads_thread.wait_to_finish()
		_roads_thread = null


## Worker-thread body: merge every district's driveable roads into one map-wide
## RoadNetwork (all share the world origin) and pre-build its spatial index.
## Returns null when there's no manifest/roads, so the NavGrid fallback kicks in.
func _build_roads() -> RoadNetwork:
	var manifest := _load_json(road_manifest)
	var net := RoadNetwork.new(2.0)
	for d in manifest.get("districts", []):
		var data := _load_json(String(d.get("data", "")))
		if data.is_empty() or not data.has("origin"):
			continue
		var origin: Dictionary = data["origin"]
		net.add_district(
			data.get("roads", []),
			GeoProjection.new(origin["lat"], origin["lon"]),
			RoadNetwork.DRIVEABLE
		)
	if net.segment_count() == 0:
		return null
	net.build_spatial_index()
	return net


func _load_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _read_origin_offset() -> Vector3:
	var fo := get_tree().get_first_node_in_group("floating_origin")
	return fo.origin_offset if fo != null and "origin_offset" in fo else Vector3.ZERO


## Cap each car's speed for the vehicle ahead in its lane, so the fleet queues
## and brakes instead of driving through itself. Neighbour candidates come from
## a spatial grid rebuilt per tick (NeighborGrid: native SpatialHash or GDScript
## buckets) so the pass scales with local density instead of all pairs; the
## tested TrafficFlow lane math then runs on just the nearby cars. Each car's
## own position is naturally ignored (zero forward distance).
func _apply_flow() -> void:
	var live: Array[TrafficCar] = []
	var positions := PackedVector3Array()
	_flow_grid.clear()
	for car in _cars:
		if not is_instance_valid(car):
			continue
		var pos := car.global_position
		_flow_grid.insert(live.size(), Vector2(pos.x, pos.z))
		live.append(car)
		positions.append(pos)
	for i in live.size():
		var car := live[i]
		var pos := positions[i]
		var near := _flow_grid.query_radius(Vector2(pos.x, pos.z), flow_range)
		var candidates := PackedVector3Array()
		for id in near:
			candidates.append(positions[id])
		var gap := TrafficFlow.gap_ahead(
			pos, car.heading(), candidates, flow_range, flow_lane_half_width
		)
		car.speed_limit = TrafficFlow.follow_speed(car.speed, gap, flow_stop_gap, flow_safe_gap)
		# Hold at a red/yellow signalled junction ahead — stop overrides the
		# follow cap. No TrafficSignalField in the scene -> always false, so
		# ambient traffic behaves exactly as before (issue #61).
		if _hold_for_signal(car, pos):
			car.speed_limit = 0.0


## True if a signalled junction ahead shows red/yellow for this car's approach,
## so the per-tick speed cap should drop to a stop. The batched TrafficSignalField
## owns the junction clocks; no field in the scene means no holds, so ambient
## traffic is unaffected.
func _hold_for_signal(car: TrafficCar, pos: Vector3) -> bool:
	var field := get_tree().get_first_node_in_group("traffic_signal_field") as TrafficSignalField
	return field != null and field.must_hold(pos, car.heading(), car.speed)


## True once at least one district's building colliders exist. The bake reads the
## skyline off physics colliders, and the player is placed before the spawn
## district's buildings are extruded, so baking earlier would miss them and route
## cars straight through not-yet-built footprints.
func _skyline_is_solid() -> bool:
	return not get_tree().get_nodes_in_group("world_buildings").is_empty()


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
		car.note_tick(tick_interval)
		# Drop cars that fell far behind OR have been stuck (gridlocked / boxed in)
		# past the timeout — a fresh one respawns on open road, so no jam persists.
		if (
			TrafficMotion.planar_distance(car.global_position, center) > cull_radius
			or car.stuck_time() > stuck_timeout
		):
			car.queue_free()
		else:
			survivors.append(car)
	_cars = survivors


## Give any car that has finished its route a fresh destination, so traffic keeps
## flowing instead of parking at the end of each trip.
func _repath(center: Vector3) -> void:
	var survivors: Array[TrafficCar] = []
	for car in _cars:
		if not is_instance_valid(car):
			continue
		# A finished car that can't get a fresh road route is stranded at a dead
		# end — cull it so it never sits in the road blocking the fleet behind it
		# (a new car respawns on open road next tick).
		if car.is_done() and not _route_car(car, center, car.heading()):
			car.queue_free()
		else:
			survivors.append(car)
	_cars = survivors


func _spawn(center: Vector3) -> void:
	# Hold ambient spawns until the road graph has finished building, so no car
	# ever starts on the NavGrid/straight fallback while real roads are on the way
	# (those early cars are what wandered off-road). Sandbox builds finish instantly.
	if _roads_thread != null:
		return
	var n: int = mini(maxi(target_count - _cars.size(), 0), maxi(spawn_budget, 0))
	for _i in n:
		var spot := _spawn_spot(center)
		if spot.is_empty():
			continue
		var car := _make_car()
		add_child(car)
		car.global_position = spot["pos"]
		# Only keep it if it can actually set off on the road; otherwise drop it so
		# it doesn't sit at the spawn point as an instant roadblock.
		if _route_car(car, center, spot["heading"]):
			_cars.append(car)
		else:
			car.queue_free()


func _make_car() -> TrafficCar:
	var car: TrafficCar
	if car_scene != null:
		car = car_scene.instantiate() as TrafficCar
	if car == null:
		car = TrafficCar.new()
	car.model_variant = _rng.randi() % VehicleVisualLibrary.variant_count()
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
		var path := PathSmoother.simplify_world(nav, nav.find_path(car.global_position, dest))
		if path.size() >= 2:
			# Flatten the route onto the car's drive plane.
			for i in path.size():
				path[i] = Vector3(path[i].x, car.global_position.y, path[i].z)
			car.set_route(path)
			return
	car.set_route(PackedVector3Array([car.global_position, dest]))


## Where to drop a new car: a point on a road in the spawn annulus when the road
## graph is up, else any open NavGrid cell (the sandbox fallback). Returns
## {pos, heading} (world/local), or {} if no spot was found this tick.
func _spawn_spot(center: Vector3) -> Dictionary:
	if _roads != null:
		return _road_spawn_point(center)
	var pos := _walkable_point(center, spawn_min_radius, spawn_max_radius)
	if pos == Vector3.INF:
		return {}
	return {"pos": Vector3(pos.x, road_surface_y, pos.z), "heading": Vector3.ZERO}


## Sample the spawn annulus and snap to the nearest road, keeping to the right
## lane. Retries because a sample can land far from any street. Road coordinates
## are absolute, so convert to/from the engine frame with the floating offset.
func _road_spawn_point(center: Vector3) -> Dictionary:
	var center_abs := center - _origin_offset
	for _a in maxi(walkable_attempts, 1):
		var ang := _rng.randf() * TAU
		var r := sqrt(
			spawn_min_radius ** 2 + (spawn_max_radius ** 2 - spawn_min_radius ** 2) * _rng.randf()
		)
		var np := _roads.nearest_point(center_abs + Vector3(cos(ang) * r, 0.0, sin(ang) * r))
		if np.is_empty():
			continue
		var on_road: Vector3 = np["pos"] + TrafficRouting.right_of(np["heading"]) * lane_half_width
		var local: Vector3 = on_road + _origin_offset
		var d := TrafficMotion.planar_distance(local, center)
		if d < spawn_min_radius or d > spawn_max_radius:
			continue
		return {"pos": Vector3(local.x, road_surface_y, local.z), "heading": np["heading"]}
	return {}


## Route a car along the road graph (right lane) for trip_radius metres, following
## real streets and turning at junctions. Returns false when roads exist but no
## route can be built from where the car sits (a dead-end stub) — the caller culls
## it so a stuck car never sits in the road blocking the cars queued behind it.
## With no road graph it takes the NavGrid/straight sandbox fallback and is kept.
## `heading_hint` keeps a moving car going forward, not reversing behind itself.
func _route_car(car: TrafficCar, center: Vector3, heading_hint: Vector3) -> bool:
	if _roads == null:
		_assign_route(car, center)
		return true
	var car_abs := car.global_position - _origin_offset
	var abs_pts := TrafficRouting.route_to(
		_roads, car_abs, _pick_goal(car_abs, heading_hint), heading_hint, lane_half_width
	)
	if abs_pts.size() < 2:
		return false
	var route := PackedVector3Array()
	for p in abs_pts:
		route.append(Vector3(p.x + _origin_offset.x, car.global_position.y, p.z + _origin_offset.z))
	car.set_route(route)
	return true


## A destination roughly trip_radius..1.8x ahead of the car, in absolute coords. The
## arc is kept to a forward cone (±63°) so the goal is genuinely ahead — a goal off
## to the side or behind would route the car on a U-turn/loop back past itself,
## which read as cars circling. The car A*-routes here and picks a fresh one on
## arrival, so it always drives somewhere on purpose.
func _pick_goal(car_abs: Vector3, heading: Vector3) -> Vector3:
	var fwd := Vector3(heading.x, 0.0, heading.z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var dir := fwd.rotated(Vector3.UP, _rng.randf_range(-PI * 0.35, PI * 0.35))
	return car_abs + dir * _rng.randf_range(trip_radius, trip_radius * 1.8)


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


## True once the off-thread road graph is built and in use.
func roads_ready() -> bool:
	return _roads != null


## Live ambient-car world positions (for probes / telemetry).
func car_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for car in _cars:
		if is_instance_valid(car):
			out.append(car.global_position)
	return out


## Planar distance from a world position to the nearest road, or -1 when there is
## no road graph. Lets a probe assert ambient cars are actually on the streets.
func nearest_road_distance(world_pos: Vector3) -> float:
	if _roads == null:
		return -1.0
	var np := _roads.nearest_point(world_pos - _origin_offset)
	return INF if np.is_empty() else float(np["dist"])


func _player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D
