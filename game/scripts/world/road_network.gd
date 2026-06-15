class_name RoadNetwork
extends RefCounted
## A driveable graph built from a district's real OSM roads: shared endpoints
## snap together into junction nodes, and each polyline becomes short directed
## segments (both directions, since lanes are two-way here). Traffic agents walk
## segment→segment, picking a continuation at each junction.
##
## Pure and scene-free so it unit-tests headless (tests/unit/test_road_network.gd).
## Geometry comes in already projected to local metres via GeoProjection.

## Highway classes a car may drive on (sidewalks/steps/cycleways excluded).
const DRIVEABLE := {
	"motorway": true,
	"trunk": true,
	"primary": true,
	"secondary": true,
	"tertiary": true,
	"residential": true,
	"service": true,
	"living_street": true,
	"unclassified": true,
}

## Highway classes a pedestrian may walk on (sidewalks, paths, plus quiet roads).
const WALKABLE := {
	"footway": true,
	"path": true,
	"pedestrian": true,
	"steps": true,
	"living_street": true,
	"residential": true,
	"service": true,
	"tertiary": true,
	"cycleway": true,
}

var nodes := PackedVector3Array()
var seg_a := PackedInt32Array()
var seg_b := PackedInt32Array()
var seg_len := PackedFloat32Array()

var _snap: float
var _index := {}
var _adj := {}

# Coarse XZ bucket grid over segments, for nearest_point(). Built lazily (or
# eagerly off-thread via build_spatial_index) so spawn/route lookups scan only
# nearby segments instead of the whole map-wide graph.
var _seg_cell: float = 24.0
var _seg_index := {}
var _seg_index_built := false


func _init(snap: float = 2.0) -> void:
	_snap = maxf(0.001, snap)


## Build a network from a district's `roads` array (each {kind, path:[[lat,lon]]}).
static func from_district(
	roads: Array, proj: GeoProjection, snap: float = 2.0, classes: Dictionary = DRIVEABLE
) -> RoadNetwork:
	var net := RoadNetwork.new(snap)
	net.add_district(roads, proj, classes)
	return net


## Add one district's driveable (per `classes`) polylines onto this network,
## projecting each path point to local metres. Several districts can be merged
## into one graph this way — they all project against the same shared world
## origin, so their coordinates line up into a single map-wide road network.
func add_district(roads: Array, proj: GeoProjection, classes: Dictionary = DRIVEABLE) -> void:
	for r in roads:
		if not classes.has(r.get("kind", "")):
			continue
		var pts := PackedVector3Array()
		for pair in r.get("path", []):
			pts.append(proj.to_local(pair[0], pair[1]))
		add_polyline(pts)


## Add a polyline of local points, creating junction nodes and two-way segments.
func add_polyline(pts: PackedVector3Array) -> void:
	var prev := -1
	for p in pts:
		var n := _node_for(p)
		if prev != -1 and prev != n:
			_add_segment(prev, n)
			_add_segment(n, prev)
		prev = n


func node_count() -> int:
	return nodes.size()


func segment_count() -> int:
	return seg_a.size()


## Segment indices that start at `node`.
func segments_from(node: int) -> PackedInt32Array:
	return _adj.get(node, PackedInt32Array())


## Sample a segment at a distance `offset` from its start: {pos, heading}.
func point_on_segment(seg: int, offset: float) -> Dictionary:
	var a := nodes[seg_a[seg]]
	var b := nodes[seg_b[seg]]
	var length := seg_len[seg]
	var heading := (b - a).normalized() if length > 0.0 else Vector3.FORWARD
	var t := 0.0 if length <= 0.0 else clampf(offset / length, 0.0, 1.0)
	return {"pos": a.lerp(b, t), "heading": heading}


## Bucket every segment into the XZ grid so nearest_point() scans only nearby
## ones. Pure and self-contained — ideal to call on the worker thread right after
## building a big map-wide graph, before handing it to the main thread.
func build_spatial_index() -> void:
	_seg_index.clear()
	for seg in seg_a.size():
		var a := nodes[seg_a[seg]]
		var b := nodes[seg_b[seg]]
		var steps := maxi(1, ceili(seg_len[seg] / _seg_cell))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / float(steps))
			var key := "%d_%d" % [floori(p.x / _seg_cell), floori(p.z / _seg_cell)]
			var bucket: PackedInt32Array = _seg_index.get(key, PackedInt32Array())
			if bucket.is_empty() or bucket[bucket.size() - 1] != seg:
				bucket.append(seg)
				_seg_index[key] = bucket
	_seg_index_built = true


## Nearest point ON the road graph to a world position (planar XZ):
## {seg, offset, pos, heading, dist}, or {} if the graph is empty. `offset` is
## metres along the segment from its start node. Builds the index on first use.
func nearest_point(pos: Vector3) -> Dictionary:
	if seg_a.is_empty():
		return {}
	if not _seg_index_built:
		build_spatial_index()
	var cx := floori(pos.x / _seg_cell)
	var cz := floori(pos.z / _seg_cell)
	var best := {}
	var best_dist := INF
	# Widen the search ring until a segment is found (a dense city hits at ring 1).
	for ring in [1, 2, 4, 8, 16]:
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				for seg in _seg_index.get("%d_%d" % [cx + dx, cz + dz], PackedInt32Array()):
					var hit := _project_to_segment(seg, pos)
					if hit["dist"] < best_dist:
						best_dist = hit["dist"]
						best = hit
		if not best.is_empty():
			break
	return best


## A* shortest node path from `start` to `goal` over the directed graph (edge cost
## = segment length, heuristic = straight-line distance), inclusive of both ends.
## Empty if unreachable or the search budget is exceeded. Pure — lets ambient cars
## drive to a destination instead of wandering. Covered by test_road_network.
func find_path(start: int, goal: int) -> PackedInt32Array:
	if start < 0 or goal < 0 or start >= nodes.size() or goal >= nodes.size():
		return PackedInt32Array()
	if start == goal:
		return PackedInt32Array([start])
	var goal_pos := nodes[goal]
	var came := {}
	var cost := {start: 0.0}
	var open := {start: nodes[start].distance_to(goal_pos)}
	var guard := 0
	while not open.is_empty() and guard < 1500:
		guard += 1
		var cur := -1
		var best := INF
		for n in open:
			if open[n] < best:
				best = open[n]
				cur = n
		if cur == goal:
			break
		open.erase(cur)
		for seg in segments_from(cur):
			var nb: int = seg_b[seg]
			var tentative: float = cost[cur] + seg_len[seg]
			if not cost.has(nb) or tentative < cost[nb]:
				came[nb] = cur
				cost[nb] = tentative
				open[nb] = tentative + nodes[nb].distance_to(goal_pos)
	if not came.has(goal):
		return PackedInt32Array()
	var path := PackedInt32Array([goal])
	var c := goal
	while c != start:
		c = came[c]
		path.append(c)
	path.reverse()
	return path


## Closest point on one segment to `pos`, projected on the flat (XZ). The y is
## interpolated along the segment so callers get a sensible road height.
func _project_to_segment(seg: int, pos: Vector3) -> Dictionary:
	var a := nodes[seg_a[seg]]
	var b := nodes[seg_b[seg]]
	var ax := Vector2(a.x, a.z)
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var len2 := ab.length_squared()
	var t := 0.0 if len2 <= 0.0 else clampf((Vector2(pos.x, pos.z) - ax).dot(ab) / len2, 0.0, 1.0)
	var closest := ax + ab * t
	var heading := (b - a).normalized() if seg_len[seg] > 0.0 else Vector3.FORWARD
	return {
		"seg": seg,
		"offset": t * seg_len[seg],
		"pos": Vector3(closest.x, a.y + (b.y - a.y) * t, closest.y),
		"heading": heading,
		"dist": Vector2(pos.x, pos.z).distance_to(closest),
	}


func _node_for(p: Vector3) -> int:
	var key := "%d_%d" % [roundi(p.x / _snap), roundi(p.z / _snap)]
	if _index.has(key):
		return _index[key]
	var i := nodes.size()
	nodes.append(p)
	_index[key] = i
	_adj[i] = PackedInt32Array()
	return i


func _add_segment(a: int, b: int) -> void:
	if a == b:
		return
	var i := seg_a.size()
	seg_a.append(a)
	seg_b.append(b)
	seg_len.append(nodes[a].distance_to(nodes[b]))
	var outgoing: PackedInt32Array = _adj[a]
	outgoing.append(i)
	_adj[a] = outgoing
