class_name TrafficRouting
extends RefCounted
## Pure road-following router for ambient traffic (issue #61). Each car gets a
## DESTINATION and the A* shortest path to it along the road graph, so it drives
## somewhere on purpose instead of wandering turn-by-turn. The node path becomes a
## string of waypoints ~WAYPOINT_STEP apart, each pushed a half-lane to the RIGHT
## of travel so opposing cars keep to opposite sides of a two-way street.
##
## Real-traffic turns: a car stays in its right lane up to a junction, then sweeps
## a smooth arc (a tangent quadratic Bézier whose control point is the offset-lane
## intersection) from the incoming right lane into the OUTGOING right lane. So it
## turns FROM its own lane instead of first cutting toward the centre/oncoming side
## and weaving back — the bug that made cars drift across lanes and circle at
## corners. Right turns hug the inside corner; left turns swing through the
## junction without ever crossing into the oncoming lane.
##
## Returns ABSOLUTE world waypoints (the caller shifts them into the engine frame
## via FloatingOrigin.origin_offset). Scene-free and deterministic, so it
## unit-tests headless (tests/unit/test_traffic_routing.gd).

## Waypoint spacing (m) along straight lane runs. OSM polylines run far between
## vertices, so subdivide them — a long edge still yields followable on-road points.
const WAYPOINT_STEP := 9.0
## How far (m) before a junction the car leaves the straight and begins its turn
## arc (and how far past it the arc rejoins the next lane). Clamped to a fraction
## of each segment so short blocks still leave room.
const CORNER_SETBACK := 5.0
## Two segments whose headings agree closer than this (≈10°) are treated as one
## straight run — no turn arc, the lane just flows through.
const STRAIGHT_DOT := 0.985
## Turn-arc resolution: roughly one extra waypoint per this much heading change.
const ARC_STEP_RAD := PI / 6.0


## Right-hand perpendicular of a planar heading: heading north (-Z) -> east (+X),
## matching GeoProjection's +X = east / -Z = north convention (right-hand drive).
static func right_of(heading: Vector3) -> Vector3:
	var r := Vector3(-heading.z, 0.0, heading.x)
	return r.normalized() if r.length() > 0.0001 else Vector3.ZERO


## Right-lane route from `start_pos` to the road nearest `goal_pos`, via the graph's
## A* shortest path. `heading_hint` sets the initial travel direction so the car
## sets off forward rather than reversing. Returns absolute waypoints (right lane,
## with smooth turn arcs at junctions), or empty if no path connects the two.
static func route_to(
	net: RoadNetwork,
	start_pos: Vector3,
	goal_pos: Vector3,
	heading_hint: Vector3,
	lane_half_width: float
) -> PackedVector3Array:
	var out := PackedVector3Array()
	if net.segment_count() == 0:
		return out
	var np := net.nearest_point(start_pos)
	var gp := net.nearest_point(goal_pos)
	if np.is_empty() or gp.is_empty():
		return out
	# Begin along the directed segment matching the car's facing, so it heads
	# toward that segment's end node rather than reversing onto the road behind it.
	var start_seg: int = np["seg"]
	var start_off: float = np["offset"]
	if heading_hint.length() > 0.001 and heading_hint.dot(np["heading"]) < 0.0:
		var rev := _reverse_segment(net, start_seg)
		if rev >= 0:
			start_off = net.seg_len[start_seg] - start_off
			start_seg = rev
	var start_node: int = net.seg_b[start_seg]
	# Aim at whichever end of the goal's segment sits closer to the destination.
	var ga: int = net.seg_a[gp["seg"]]
	var gb: int = net.seg_b[gp["seg"]]
	var to_a := net.nodes[ga].distance_to(goal_pos)
	var to_b := net.nodes[gb].distance_to(goal_pos)
	var path := net.find_path(start_node, ga if to_a <= to_b else gb)
	if path.is_empty():
		return out
	# Centreline of the trip: the car's foot on its current segment, then every
	# node of the A* path. The foot->start_node leg shares the start segment's
	# direction, so the car sets off straight ahead.
	var centers := PackedVector3Array()
	centers.append(net.point_on_segment(start_seg, start_off)["pos"])
	for n in path:
		centers.append(net.nodes[n])
	# Drop a near-zero opening leg (car sitting on the node) so the first heading
	# is taken from a real segment, not a degenerate one.
	if centers.size() >= 3 and centers[0].distance_to(centers[1]) < 0.5:
		centers.remove_at(0)
	_emit_lane_path(centers, lane_half_width, out)
	return out


## The segment retracing `seg` (its end node back to its start), or -1 if none.
static func _reverse_segment(net: RoadNetwork, seg: int) -> int:
	var a := net.seg_a[seg]
	var b := net.seg_b[seg]
	for cand in net.segments_from(b):
		if net.seg_b[cand] == a:
			return cand
	return -1


## Turn a centreline node list into right-lane waypoints: straight runs offset a
## half-lane to the right, joined at each interior junction by a smooth turn arc.
static func _emit_lane_path(
	centers: PackedVector3Array, lane_half_width: float, out: PackedVector3Array
) -> void:
	var m := centers.size()
	if m < 2:
		return
	# Per-segment travel direction and its right-lane offset vector.
	var dirs: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var lens := PackedFloat32Array()
	for k in m - 1:
		var v: Vector3 = centers[k + 1] - centers[k]
		var l := v.length()
		var d := v / l if l > 0.0001 else Vector3(0.0, 0.0, 1.0)
		dirs.append(d)
		rights.append(right_of(d) * lane_half_width)
		lens.append(l)
	for k in m - 1:
		# A junction is a "turn" only when the two segments actually change heading;
		# a straight run of collinear OSM segments flows through with no arc.
		var turn_start: bool = k > 0 and not _straight(dirs[k - 1], dirs[k])
		var turn_end: bool = k < m - 2 and not _straight(dirs[k], dirs[k + 1])
		var d_start: float = minf(CORNER_SETBACK, lens[k] * 0.45) if turn_start else 0.0
		var d_end: float = (lens[k] - minf(CORNER_SETBACK, lens[k] * 0.45)) if turn_end else lens[k]
		# Resume the lane exactly where the incoming arc left off (its tangent point).
		if turn_start:
			out.append(_lane_pt(centers[k], dirs[k], rights[k], d_start))
		var off := d_start
		while off < d_end - 0.01:
			off = minf(off + WAYPOINT_STEP, d_end)
			out.append(_lane_pt(centers[k], dirs[k], rights[k], off))
		if turn_end:
			_emit_arc(
				centers[k + 1],
				dirs[k],
				dirs[k + 1],
				rights[k],
				rights[k + 1],
				lens[k],
				lens[k + 1],
				out
			)


## True when two unit headings agree to within STRAIGHT_DOT (no real turn between).
static func _straight(a: Vector3, b: Vector3) -> bool:
	return a.dot(b) >= STRAIGHT_DOT


## Append the interior points of a turn arc at `node`: a quadratic Bézier from the
## incoming right lane's exit point, through the two offset lanes' intersection, to
## the outgoing right lane's entry point. Tangent to both lanes, so the car keeps
## its lane right up to the turn and eases into the new one — no centre-line weave.
static func _emit_arc(
	node: Vector3,
	d_in: Vector3,
	d_out: Vector3,
	right_in: Vector3,
	right_out: Vector3,
	len_in: float,
	len_out: float,
	out: PackedVector3Array
) -> void:
	var exit_sb := minf(CORNER_SETBACK, len_in * 0.45)
	var entry_sb := minf(CORNER_SETBACK, len_out * 0.45)
	var e := node - d_in * exit_sb + right_in
	var s := node + d_out * entry_sb + right_out
	var control := _corner_control(node + right_in, d_in, node + right_out, d_out, (e + s) * 0.5)
	var turn := acos(clampf(d_in.dot(d_out), -1.0, 1.0))
	var n := clampi(ceili(turn / ARC_STEP_RAD), 1, 6)
	for i in range(1, n):
		out.append(_bezier2(e, control, s, float(i) / float(n)))


## Intersection (in XZ) of line `p_in + t*d_in` and line `p_out + s*d_out`, or
## `fallback` when they are near-parallel. This is the natural turn corner: tight
## on the inside for a right turn, swept wide on the outside for a left turn.
static func _corner_control(
	p_in: Vector3, d_in: Vector3, p_out: Vector3, d_out: Vector3, fallback: Vector3
) -> Vector3:
	var det := d_out.x * d_in.z - d_in.x * d_out.z
	if absf(det) < 0.0001:
		return fallback
	var t := (-(p_out.x - p_in.x) * d_out.z + d_out.x * (p_out.z - p_in.z)) / det
	var c := p_in + d_in * t
	c.y = fallback.y
	return c


## Point a half-lane to the right of the centreline, `dist` metres along a segment.
static func _lane_pt(base: Vector3, dir: Vector3, right_off: Vector3, dist: float) -> Vector3:
	return base + dir * dist + right_off


## Quadratic Bézier a→(control)→c at parameter t.
static func _bezier2(a: Vector3, control: Vector3, c: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * (u * u) + control * (2.0 * u * t) + c * (t * t)
