class_name BayIslands
extends RefCounted
## The man-made residential islands of Biscayne Bay — Star / Palm / Hibiscus off
## MacArthur Causeway and the Venetian Islands chain off Venetian Causeway. These
## are the iconic Miami/Vice City landmarks the GTA-VI trailer lingers on, and
## they give the causeways something to thread between instead of bare water.
##
## Pure static data + math (no scene deps), world-space (x = east, z) so it lines
## up with CausewayNetwork and the district offsets. Each island is a rounded
## land pad: a centre, a radius, and a "kind" the builder uses to dress it.

## Island surface height above the bay water (a low seawalled pad).
const LAND_Y: float = 2.6
## How far the seawall foots below the waterline.
const FOOT_Y: float = CausewayNetwork.WATER_Y - 4.0


## Every island: {name, center: Vector2 (world x,z), radius: float, kind: String}.
## Positions hug the MacArthur (z≈-350..-760) and Venetian (z≈-1050) spans.
static func islands() -> Array:
	return [
		{"name": "watson", "center": Vector2(1450, -380), "radius": 220.0, "kind": "civic"},
		{"name": "star", "center": Vector2(2150, -760), "radius": 205.0, "kind": "luxury"},
		{"name": "palm", "center": Vector2(2560, -360), "radius": 180.0, "kind": "luxury"},
		{"name": "hibiscus", "center": Vector2(2960, -430), "radius": 150.0, "kind": "luxury"},
		{
			"name": "biscayne",
			"center": Vector2(1750, -1040),
			"radius": 120.0,
			"kind": "residential"
		},
		{
			"name": "san_marco",
			"center": Vector2(2450, -1045),
			"radius": 110.0,
			"kind": "residential"
		},
		{
			"name": "san_marino",
			"center": Vector2(3150, -1050),
			"radius": 110.0,
			"kind": "residential"
		},
		{"name": "di_lido", "center": Vector2(3850, -1055), "radius": 125.0, "kind": "residential"},
		{
			"name": "rivo_alto",
			"center": Vector2(4450, -1060),
			"radius": 110.0,
			"kind": "residential"
		},
	]


## A closed ring polygon approximating an island outline, with a little
## per-island wobble so the pads do not read as perfect circles.
static func ring(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = maxi(segments, 3)
	var seed := int(absf(center.x) + absf(center.y))
	for i in n:
		var a := TAU * float(i) / float(n)
		# Deterministic 4–6% radial wobble keyed off the centre.
		var wobble := 1.0 + 0.05 * sin(a * 3.0 + float(seed) * 0.7)
		out.append(center + Vector2(cos(a), sin(a)) * radius * wobble)
	return out


## Shoelace area of a polygon (absolute, m²).
static func polygon_area(poly: PackedVector2Array) -> float:
	var n := poly.size()
	if n < 3:
		return 0.0
	var sum := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


## Combined land area of every island (m²).
static func total_land_area() -> float:
	var total := 0.0
	for isle in islands():
		total += PI * isle["radius"] * isle["radius"]
	return total


## Shortest distance from a point to any causeway centreline — used to keep the
## islands hugging the spans (and unit-tested as the coupling guarantee).
static func nearest_causeway_distance(p: Vector2) -> float:
	var best := INF
	for c in CausewayNetwork.causeways():
		var pts: PackedVector2Array = c["points"]
		for i in range(1, pts.size()):
			var d := _point_segment_distance(p, pts[i - 1], pts[i])
			best = minf(best, d)
	return best


static func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
