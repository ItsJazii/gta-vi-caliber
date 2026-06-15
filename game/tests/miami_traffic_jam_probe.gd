extends SceneTree
## Integration probe: ambient traffic keeps FLOWING — moving cars don't bunch up
## and stick to each other. Boots miami, waits for the road graph + a fleet, then
## watches the director's stuck-car counts over a window with the player standing
## on foot at spawn (mid-street, clear of junctions — where the jack-assist used to
## freeze a knot of cars). Asserts the peak number of cars stuck AT THE PLAYER stays
## tiny, and the fleet keeps a population. Run headless:
##   godot --headless --path game --script res://tests/miami_traffic_jam_probe.gd

const SCENE_PATH := "res://scenes/world/miami.tscn"
const WARMUP_FRAMES := 120
const MAX_WAIT_MSEC := 25000
const MIN_CARS := 3
## Watch the fleet for this long (wall-clock) once it's up.
const WATCH_MSEC := 12000
## Near-player jam: cars within this radius of the on-foot player, stuck this long.
const NEAR_RADIUS := 6.0
const NEAR_STUCK := 2.0
## At most this many cars may be stuck right at the player at once. The jack-assist
## should stop only the ONE car you'd grab, not a cluster.
const MAX_NEAR_STUCK := 1

var _scene: Node = null
var _frames := 0
var _started_msec := 0
var _watch_start := -1
var _peak_near := 0
var _peak_total := 0
var _samples := 0
var _stand_spot: Vector3 = Vector3.INF
var _failures: PackedStringArray = []


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami traffic jam probe: scene failed to load")
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
	if (
		td != null
		and (not td.roads_ready() or td.population() < MIN_CARS)
		and Time.get_ticks_msec() - _started_msec < MAX_WAIT_MSEC
	):
		return false
	if td == null:
		_failures.append("no TrafficDirector in the scene")
		return _finish()
	# Stand the player IN the traffic, on a spawned car's road spot, so the
	# jack-assist's effect on nearby cars is actually exercised — a stationary
	# spawn-centre player has no through-traffic beside them to bunch up.
	var player := get_first_node_in_group("player") as Node3D
	var cars: PackedVector3Array = td.car_positions()
	if _watch_start < 0:
		_watch_start = Time.get_ticks_msec()
		if not cars.is_empty():
			_stand_spot = cars[0]
	if _stand_spot == Vector3.INF:
		return false
	if player != null:
		player.global_position = _stand_spot
	_peak_near = maxi(_peak_near, int(td.stuck_count_near(_stand_spot, NEAR_RADIUS, NEAR_STUCK)))
	_peak_total = maxi(_peak_total, int(td.stuck_count(NEAR_STUCK)))
	_samples += 1
	if Time.get_ticks_msec() - _watch_start < WATCH_MSEC:
		return false
	_run_checks(td)
	return _finish()


func _director() -> Node:
	return get_first_node_in_group("traffic_director")


func _run_checks(td: Node) -> void:
	if td.population() < MIN_CARS:
		_failures.append("fleet vanished: %d cars left" % td.population())
		return
	if _peak_near > MAX_NEAR_STUCK:
		_failures.append(
			(
				"traffic bunches at the player: peak %d cars stuck within %.0fm (max %d)"
				% [_peak_near, NEAR_RADIUS, MAX_NEAR_STUCK]
			)
		)


func _finish() -> bool:
	if _failures.is_empty():
		print(
			(
				"miami traffic jam probe: OK (peak %d stuck at player, %d fleet-wide, %d samples)"
				% [_peak_near, _peak_total, _samples]
			)
		)
		quit(0)
	else:
		for f in _failures:
			push_error("miami traffic jam probe FAIL :: %s" % f)
		print("miami traffic jam probe: %d failure(s)" % _failures.size())
		quit(1)
	return true
