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

var nodes := PackedVector3Array()
var seg_a := PackedInt32Array()
var seg_b := PackedInt32Array()
var seg_len := PackedFloat32Array()

var _snap: float
var _index := {}
var _adj := {}


func _init(snap: float = 2.0) -> void:
	_snap = maxf(0.001, snap)


## Build a network from a district's `roads` array (each {kind, path:[[lat,lon]]}).
static func from_district(roads: Array, proj: GeoProjection, snap: float = 2.0) -> RoadNetwork:
	var net := RoadNetwork.new(snap)
	for r in roads:
		if not DRIVEABLE.has(r.get("kind", "")):
			continue
		var pts := PackedVector3Array()
		for pair in r.get("path", []):
			pts.append(proj.to_local(pair[0], pair[1]))
		net.add_polyline(pts)
	return net


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
