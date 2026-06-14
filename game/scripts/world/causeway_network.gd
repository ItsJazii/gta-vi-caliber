class_name CausewayNetwork
extends RefCounted
## Authored layout of the causeways that bridge Biscayne Bay — the connective
## Florida geography that turns the five paged districts (downtown, Brickell,
## Wynwood on the mainland; South Beach, Mid-Beach across the water) into ONE
## continuous, drivable landmass instead of isolated islands.
##
## Pure static data + math (no scene deps) so it is unit-testable and shared by
## the Causeways builder node, traffic stitching, and the minimap. All points
## are WORLD-SPACE (x = east, z) Vector2s that line up with the district
## world_offsets in assets/world/districts.json:
##   downtown  (172,-193)  brickell (-156,1239)  wynwood (-504,-3364)
##   south_beach (5899,-715)            mid_beach (6453,-4702)
## The ~4.5 km bay gap sits between mainland (x≈0) and beaches (x≈6000); each
## causeway crosses it roughly east-west, anchored at the district edges.
##
## Causeways are modelled on the real Miami crossings:
##   MacArthur   — downtown ⇄ South Beach (the iconic A1A/I-395 span)
##   Julia Tuttle — Wynwood/midtown ⇄ Mid-Beach (I-195)
##   Venetian    — a slimmer island-hopping road parallel to MacArthur

## Bay surface height (matches the ocean plane the beaches sit beside).
const WATER_Y: float = -0.4
## Deck height above water at the shore ends, before the mid-span arch.
const DECK_BASE_Y: float = 2.2


## Every causeway as a Dictionary:
##   name   : String        stable id
##   points : PackedVector2Array  world-space centreline (x, z), shore→shore
##   width  : float         drivable deck width in metres
##   rise   : float         extra height added at mid-span for boat clearance
static func causeways() -> Array:
	return [
		{
			"name": "macarthur",
			"points":
			PackedVector2Array(
				[
					Vector2(900, -350),
					Vector2(1800, -420),
					Vector2(3100, -480),
					Vector2(4400, -560),
					Vector2(5350, -650),
				]
			),
			"width": 24.0,
			"rise": 16.0,
		},
		{
			"name": "julia_tuttle",
			"points":
			PackedVector2Array(
				[
					Vector2(400, -3050),
					Vector2(1600, -3300),
					Vector2(3050, -3700),
					Vector2(4500, -4150),
					Vector2(5700, -4550),
				]
			),
			"width": 22.0,
			"rise": 11.0,
		},
		{
			"name": "venetian",
			"points":
			PackedVector2Array(
				[
					Vector2(950, -900),
					Vector2(2000, -950),
					Vector2(3200, -1000),
					Vector2(4500, -1050),
					Vector2(5300, -1060),
				]
			),
			"width": 12.0,
			"rise": 7.0,
		},
	]


## Centreline of one causeway by name (empty if unknown).
static func centerline(causeway_name: String) -> PackedVector2Array:
	for c in causeways():
		if c["name"] == causeway_name:
			return c["points"]
	return PackedVector2Array()


## Planar length of a polyline in metres.
static func length_of(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


## Combined length of every causeway deck — total new drivable bay road.
static func total_length() -> float:
	var total := 0.0
	for c in causeways():
		total += length_of(c["points"])
	return total


## Deck height at normalised span position t∈[0,1]. A single gentle hump
## (sin arch) lifts the centre over the shipping channel and settles back to
## DECK_BASE_Y at both shores so the ramps meet the streets cleanly.
static func deck_height(t: float, rise: float) -> float:
	var s: float = clampf(t, 0.0, 1.0)
	return DECK_BASE_Y + rise * sin(PI * s)


## Point on a polyline at arc-distance `dist` from the start (clamped to ends).
static func sample(points: PackedVector2Array, dist: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO  # guard: the fall-through return indexes points[-1]
	if points.size() == 1:
		return points[0]
	if dist <= 0.0:
		return points[0]
	var travelled := 0.0
	for i in range(1, points.size()):
		var seg := points[i].distance_to(points[i - 1])
		if travelled + seg >= dist:
			var f: float = (dist - travelled) / seg if seg > 0.0 else 0.0
			return points[i - 1].lerp(points[i], f)
		travelled += seg
	return points[points.size() - 1]


## Evenly spaced support-pillar footprints along a centreline, excluding the two
## shore ends (those sit on land). Spacing is honoured to within one step.
static func pillar_points(points: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if spacing <= 0.0 or points.size() < 2:
		return out
	var total := length_of(points)
	var d := spacing
	while d < total - 0.001:
		out.append(sample(points, d))
		d += spacing
	return out
