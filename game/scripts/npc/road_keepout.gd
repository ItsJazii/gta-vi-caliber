class_name RoadKeepout
extends RefCounted
## Keeps pedestrians off the carriageway. Wraps the same map-wide driveable
## RoadNetwork the traffic uses and answers three things about a *scene-space*
## world point: is it clear of every road, how far is the nearest road, and where
## is the nearest clear spot. The road graph lives in absolute (pre-floating-
## origin) coordinates, so the live origin offset is subtracted on every query
## and added back on every result — callers always pass and receive scene-space
## positions. Pure and scene-free (RoadNetwork is itself scene-free), so the math
## unit-tests headless (tests/unit/test_road_keepout.gd).

# A pushed-out point lands this far past the clearance line, so a rounding wobble
# at the boundary can't flip it straight back onto the road.
const _PUSH_MARGIN: float = 0.5

## Metres a pedestrian must stay clear of a road centreline — roughly half a wide
## carriageway plus a kerb buffer, so the crowd settles on the sidewalk/verge.
var clearance: float = 7.0

var _net: RoadNetwork = null
var _origin_offset: Vector3 = Vector3.ZERO


func _init(net: RoadNetwork = null, keep_clear: float = 7.0) -> void:
	_net = net
	clearance = maxf(keep_clear, 0.0)


## Track the world's floating-origin shift so scene-space queries map onto the
## absolute road graph. Call once per tick with the current offset.
func set_origin_offset(offset: Vector3) -> void:
	_origin_offset = offset


## Planar distance from a scene-space point to the nearest road centreline, or
## INF when there is no road graph (then everywhere counts as clear).
func nearest_dist(world_pos: Vector3) -> float:
	if _net == null:
		return INF
	var np := _net.nearest_point(world_pos - _origin_offset)
	return float(np["dist"]) if np.has("dist") else INF


## True when a scene-space point is at least `clearance` from every road.
func is_clear(world_pos: Vector3) -> bool:
	return nearest_dist(world_pos) >= clearance


## Nudge a scene-space point straight out from the nearest road until it clears
## the keep-out band, preserving the side it was already on (so a ped is never
## flung across the road). Points already clear return unchanged; a point sitting
## exactly on the centreline is pushed along the road's perpendicular.
func push_clear(world_pos: Vector3) -> Vector3:
	if _net == null:
		return world_pos
	var np := _net.nearest_point(world_pos - _origin_offset)
	if not np.has("dist") or float(np["dist"]) >= clearance:
		return world_pos
	var road_scene: Vector3 = (np["pos"] as Vector3) + _origin_offset
	var away := _flat(world_pos - road_scene)
	if away.length() < 0.001:
		away = _perp(np.get("heading", Vector3.FORWARD))
	away = away.normalized()
	var out := road_scene + away * (clearance + _PUSH_MARGIN)
	return Vector3(out.x, world_pos.y, out.z)


## Steer a desired move direction so a walking ped slides along the kerb instead
## of stepping into the road: when the ped is inside the keep-out band and the
## move heads roadward, the roadward component is stripped (and the result
## renormalised to the original speed). Outside the band, or when already heading
## away/along, the direction passes through untouched.
func deflect(world_pos: Vector3, dir: Vector3) -> Vector3:
	if _net == null or dir.length() < 0.0001:
		return dir
	var np := _net.nearest_point(world_pos - _origin_offset)
	if not np.has("dist") or float(np["dist"]) >= clearance:
		return dir
	var road_scene: Vector3 = (np["pos"] as Vector3) + _origin_offset
	var normal := _flat(world_pos - road_scene)
	if normal.length() < 0.001:
		normal = _perp(np.get("heading", Vector3.FORWARD))
	normal = normal.normalized()  # points away from the road
	var into := dir.dot(normal)
	if into >= 0.0:
		return dir  # already moving away from or along the road
	var speed := dir.length()
	var tangential := dir - normal * into  # remove the roadward component
	if tangential.length() < 0.0001:
		return Vector3.ZERO
	return tangential.normalized() * speed


## Drop the vertical component — keep-out math is all in the XZ ground plane.
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## A planar unit vector perpendicular to a heading (rotate 90° in XZ).
static func _perp(heading: Vector3) -> Vector3:
	var flat := _flat(heading)
	if flat.length() < 0.001:
		return Vector3.RIGHT
	flat = flat.normalized()
	return Vector3(-flat.z, 0.0, flat.x)
