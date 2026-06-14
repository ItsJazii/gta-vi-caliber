class_name TrafficJunctions
extends RefCounted
## Pure junction-selection + approach helpers for the ambient-traffic signal layer
## (issue #61, LC1/LC4). Reads a built RoadNetwork, finds real intersections
## (nodes where >= JUNCTION_DEGREE driveable segments meet), and spaces a capped
## set of them out so TrafficSignalField can drop one light per junction. Also
## classifies a car's approach axis and decides, purely, whether a car must hold
## for a light. Scene-free and deterministic so it unit-tests headless
## (tests/unit/test_traffic_junctions.gd).

## A node is an intersection when at least this many segments leave it. Two-way
## polylines give an interior vertex degree 2 (next + prev); a real crossing of
## two streets gives 4 and a T-junction gives 3.
const JUNCTION_DEGREE := 3


## Pick up to `max_count` intersection nodes from `net`, busiest first and spaced
## at least `min_spacing` metres apart so lights don't cluster on one block.
## Returns [{ "pos": Vector3 }] in world-projected metres (the same frame the
## DistrictLoader builds its road meshes in).
static func find_signalled(net: RoadNetwork, max_count: int, min_spacing: float) -> Array:
	# Bucket junctions into a grid (cell = min_spacing) and keep the busiest in
	# each cell. That spreads signals EVENLY across the district — coverage
	# everywhere the player drives, instead of a cluster at the few busiest
	# junctions (which left the spawn edge with nothing nearby).
	var cell := maxf(min_spacing, 1.0)
	var buckets: Dictionary = {}
	for node in net.node_count():
		var degree := net.segments_from(node).size()
		if degree < JUNCTION_DEGREE:
			continue
		var p: Vector3 = net.nodes[node]
		var key := "%d_%d" % [floori(p.x / cell), floori(p.z / cell)]
		if not buckets.has(key) or buckets[key]["degree"] < degree:
			buckets[key] = {"node": node, "degree": degree, "pos": p}

	var picks: Array = buckets.values()
	# Busiest cells first, so a tight max_count still keeps the major junctions.
	picks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["degree"] > b["degree"])

	var chosen: Array = []
	for b in picks:
		if chosen.size() >= max_count:
			break
		chosen.append({"node": b["node"], "pos": b["pos"]})
	return chosen


## A junction's geometry for placing a real signal: its centre, and the local
## offset (relative to centre, XZ) to the kerb corner where the mast should stand
## — diagonally off the roadway along the two road axes meeting here, `curb`
## metres along each. Keeps the signal out of the carriageway while the node's
## logic stays centred on the stop line. Pure.
static func junction_frame(net: RoadNetwork, node: int, curb: float) -> Dictionary:
	var center: Vector3 = net.nodes[node]
	var dirs: Array[Vector3] = []
	for seg in net.segments_from(node):
		var h: Vector3 = net.point_on_segment(seg, 0.0)["heading"]
		h.y = 0.0
		if h.length() > 0.01:
			dirs.append(h.normalized())
	if dirs.is_empty():
		return {"center": center, "corner_offset": Vector3(curb, 0.0, curb)}
	# Two road axes: a1 the first arm, a2 the arm most perpendicular to it.
	var a1: Vector3 = dirs[0]
	var a2 := Vector3(-a1.z, 0.0, a1.x)
	var best := 2.0
	for d in dirs:
		var dot := absf(d.dot(a1))
		if dot < best:
			best = dot
			a2 = d
	if absf(a2.dot(a1)) > 0.95:
		a2 = Vector3(-a1.z, 0.0, a1.x)
	return {"center": center, "corner_offset": a1 * curb + a2 * curb}


## Which signal phase a heading travels along: NS (world Z) when it points more
## north/south than east/west, else EW (world X). Matches GeoProjection's
## +X = east / -Z = north convention.
static func axis_for(heading: Vector3) -> int:
	return TrafficSignal.Axis.NS if absf(heading.z) >= absf(heading.x) else TrafficSignal.Axis.EW


## Should a car hold for a junction light? True when the car is approaching the
## junction (heading points at it), sits within the [stop_line, stop_zone] band
## before it, and the light shown to its axis says stop. Cars already in the box
## (nearer than stop_line) are let through so they clear instead of freezing.
## Planar (XZ); the y component is ignored so road height never matters.
static func should_hold(
	junction_pos: Vector3,
	car_pos: Vector3,
	car_heading: Vector3,
	car_speed: float,
	light: int,
	stop_zone: float,
	stop_line: float,
	comfortable_brake: float
) -> bool:
	var to_junction := Vector3(junction_pos.x - car_pos.x, 0.0, junction_pos.z - car_pos.z)
	var dist := to_junction.length()
	if dist > stop_zone or dist < stop_line:
		return false
	var h := Vector3(car_heading.x, 0.0, car_heading.z)
	if h.length() < 0.0001 or to_junction.normalized().dot(h.normalized()) <= 0.3:
		return false  # not heading into this junction
	return TrafficSignal.should_stop(light, dist - stop_line, car_speed, comfortable_brake)
