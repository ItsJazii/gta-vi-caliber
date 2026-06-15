extends SceneTree
## Integration probe: ambient traffic follows the road graph (issue #61). Boots
## miami.tscn, waits for TrafficDirector's threaded RoadNetwork + a fleet of cars,
## then asserts every car sits ON a road (within a lane of the nearest street) and
## that the cars are spread out rather than stacked on one spot — the exact bug
## this change fixed. The routing maths is unit-tested in test_traffic_routing /
## test_road_network; this proves the wiring in the playable scene. Run headless:
##   godot --headless --path game --script res://tests/miami_traffic_road_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 120
## The road graph builds on a worker thread and cars spawn over several ticks, so
## wait (wall-clock) for both — headless races past a fixed frame count.
const MAX_WAIT_MSEC: int = 25000
const MIN_CARS: int = 3
## A car on its right lane sits ~lane_half_width off the centreline; allow that
## plus turning/steering slack. Beyond this a car is genuinely off-road.
const ON_ROAD_TOL: float = 6.0
## The fleet must occupy a spread of space (bbox diagonal), not pile onto a point.
const MIN_SPREAD: float = 15.0

var _scene: Node = null
var _frames: int = 0
var _started_msec: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami traffic road probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	_started_msec = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var td := _director()
	# Wait for the threaded road graph and a few cars before asserting.
	if (
		td != null
		and (not td.roads_ready() or td.population() < MIN_CARS)
		and Time.get_ticks_msec() - _started_msec < MAX_WAIT_MSEC
	):
		return false
	_run_checks(td)
	return _finish(td)


func _director() -> Node:
	return get_first_node_in_group("traffic_director")


func _run_checks(td: Node) -> void:
	if td == null:
		_failures.append("no TrafficDirector in the scene")
		return
	if not td.roads_ready():
		_failures.append("road graph never built (RoadNetwork null) — cars cannot be on roads")
		return
	var positions: PackedVector3Array = td.car_positions()
	if positions.size() < MIN_CARS:
		_failures.append("too few ambient cars spawned: %d" % positions.size())
		return

	# Allow a few transient cutters (mid-junction turn) but catch systemic wander.
	var off_road := 0
	for p in positions:
		if td.nearest_road_distance(p) > ON_ROAD_TOL:
			off_road += 1
	if off_road > maxi(1, positions.size() / 5):
		_failures.append(
			(
				"%d/%d cars are off-road (> %.0f m from any street)"
				% [off_road, positions.size(), ON_ROAD_TOL]
			)
		)

	var spread := _spread(positions)
	if spread < MIN_SPREAD:
		_failures.append("cars are clustered, not spread (bbox diagonal %.1f m)" % spread)


## Bounding-box diagonal of the car positions on the flat (XZ).
func _spread(positions: PackedVector3Array) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in positions:
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.z)
	return lo.distance_to(hi)


func _finish(td: Node) -> bool:
	if _failures.is_empty():
		var n: int = td.population() if td != null else 0
		print("miami traffic road probe: OK (%d cars, all on roads, spread out)" % n)
		quit(0)
	else:
		for failure in _failures:
			push_error("miami traffic road probe FAIL :: %s" % failure)
		print("miami traffic road probe: %d failure(s)" % _failures.size())
		quit(1)
	return true
