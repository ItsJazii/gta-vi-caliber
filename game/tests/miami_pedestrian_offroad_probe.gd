extends SceneTree
## Integration probe: the ambient crowd stays OFF the carriageway. Boots
## miami.tscn, waits for CrowdDirector to populate the streets, then samples every
## live pedestrian/citizen over a window and asserts none stand in a driving lane
## — the bug this change fixed (peds used to spawn and wander down the middle of
## the road). The keep-out maths is unit-tested in test_road_keepout; this proves
## the wiring in the playable scene, against an independently-built reference road
## graph (so it can't pass just because the director agrees with itself).
##
## check.sh is owned by another open PR, so this isn't registered there yet —
## run it directly:
##   godot --headless --path game --script res://tests/miami_pedestrian_offroad_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const ROAD_MANIFEST: String = "res://assets/world/districts.json"
const WARMUP_FRAMES: int = 120
## Peds load on a delay and spawn over several ticks, so wait (wall-clock) for the
## crowd instead of a fixed frame count — headless races past one.
const MAX_WAIT_MSEC: int = 35000
const MIN_PEDS: int = 5
## Frames to watch once the crowd is up, so a ped wandering toward a kerb is
## caught, not just the spawn snapshot.
const SAMPLE_FRAMES: int = 150
## A ped must stay this far (m) from any road centreline. The director holds them
## ~7 m clear; a ped genuinely in a lane (the bug) sits within ~3 m, so 4.5 m
## cleanly separates "on the sidewalk" from "in the road".
const MIN_ROAD_DIST: float = 4.5

var _scene: Node = null
var _frames: int = 0
var _started_msec: int = 0
var _roads: RoadNetwork = null
var _sampling: bool = false
var _samples: int = 0
var _peak_on_road: int = 0
var _worst_dist: float = INF
var _peak_pop: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami pedestrian off-road probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	_roads = _build_roads()
	_started_msec = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var peds := _ped_nodes()
	_peak_pop = maxi(_peak_pop, peds.size())
	if not _sampling:
		if peds.size() < MIN_PEDS and Time.get_ticks_msec() - _started_msec < MAX_WAIT_MSEC:
			return false
		_sampling = true
	_sample(peds)
	_samples += 1
	if _samples < SAMPLE_FRAMES and Time.get_ticks_msec() - _started_msec < MAX_WAIT_MSEC:
		return false
	_run_checks()
	return _finish()


## Every live ambient pedestrian and citizen (both add themselves to their group).
func _ped_nodes() -> Array:
	var out: Array = []
	out.append_array(get_nodes_in_group("pedestrians"))
	out.append_array(get_nodes_in_group("citizens"))
	return out


## Count, this frame, how many peds sit inside a driving lane, tracking the worst
## case across the whole window.
func _sample(peds: Array) -> void:
	if _roads == null:
		return
	var offset := _origin_offset()
	var on_road := 0
	for ped in peds:
		var node := ped as Node3D
		if node == null:
			continue
		var np := _roads.nearest_point(node.global_position - offset)
		if not np.has("dist"):
			continue
		var d := float(np["dist"])
		_worst_dist = minf(_worst_dist, d)
		if d < MIN_ROAD_DIST:
			on_road += 1
	_peak_on_road = maxi(_peak_on_road, on_road)


func _run_checks() -> void:
	if _roads == null or _roads.segment_count() == 0:
		_failures.append("reference road graph never built — cannot judge peds")
		return
	if _peak_pop < MIN_PEDS:
		_failures.append("too few pedestrians spawned: peak %d" % _peak_pop)
		return
	# One transient cutter at a corner is tolerable; a lane full of peds is the bug.
	var allowed := maxi(1, _peak_pop / 10)
	if _peak_on_road > allowed:
		_failures.append(
			(
				"%d peds in the carriageway at once (allowed %d); nearest ped %.1f m from a road"
				% [_peak_on_road, allowed, _worst_dist]
			)
		)


func _origin_offset() -> Vector3:
	var fo := get_first_node_in_group("floating_origin")
	return fo.origin_offset if fo != null and "origin_offset" in fo else Vector3.ZERO


## Merge every district's driveable roads into one map-wide graph — the same set
## the crowd's keep-out uses, rebuilt here so the check is independent.
func _build_roads() -> RoadNetwork:
	var manifest := _load_json(ROAD_MANIFEST)
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


func _finish() -> bool:
	if _failures.is_empty():
		print(
			(
				"miami pedestrian off-road probe: OK (peak %d peds, none in lanes, nearest %.1f m)"
				% [_peak_pop, _worst_dist]
			)
		)
		quit(0)
	else:
		for failure in _failures:
			push_error("miami pedestrian off-road probe FAIL :: %s" % failure)
		print("miami pedestrian off-road probe: %d failure(s)" % _failures.size())
		quit(1)
	return true
