class_name FloridaMapModel
extends RefCounted
## Original peninsula-scale map model used by FloridaBackdrop.
##
## This deliberately avoids tracing a real or commercial map. The silhouette,
## routes, city anchors, and wetlands are authored as a unique tropical state
## shape that gives the current world a Florida-scale read without copying
## protected layouts.

const DEFAULT_SCALE: float = 1.0

const OUTLINE: Array[Vector2] = [
	Vector2(-470.0, -940.0),
	Vector2(-350.0, -760.0),
	Vector2(-300.0, -540.0),
	Vector2(-380.0, -330.0),
	Vector2(-340.0, -120.0),
	Vector2(-250.0, 130.0),
	Vector2(-180.0, 380.0),
	Vector2(-120.0, 710.0),
	Vector2(10.0, 1010.0),
	Vector2(160.0, 1130.0),
	Vector2(320.0, 1020.0),
	Vector2(280.0, 780.0),
	Vector2(210.0, 530.0),
	Vector2(250.0, 280.0),
	Vector2(360.0, 40.0),
	Vector2(410.0, -190.0),
	Vector2(360.0, -430.0),
	Vector2(250.0, -650.0),
	Vector2(90.0, -790.0),
	Vector2(-120.0, -890.0),
]

const CITY_NODES: Array[Dictionary] = [
	{"name": "Neon Bay", "position": Vector2(260.0, -420.0), "height": 115.0, "radius": 125.0},
	{"name": "Glass Harbor", "position": Vector2(150.0, 120.0), "height": 72.0, "radius": 95.0},
	{"name": "Cypress Gate", "position": Vector2(-150.0, 270.0), "height": 44.0, "radius": 80.0},
	{"name": "Panhandle Port", "position": Vector2(20.0, 900.0), "height": 62.0, "radius": 105.0},
	{"name": "Gulf Keys", "position": Vector2(-255.0, -700.0), "height": 28.0, "radius": 70.0},
]

const ROAD_PATHS: Array[Array] = [
	[Vector2(260.0, -420.0), Vector2(170.0, -150.0), Vector2(150.0, 120.0), Vector2(40.0, 360.0), Vector2(20.0, 900.0)],
	[Vector2(260.0, -420.0), Vector2(40.0, -540.0), Vector2(-255.0, -700.0)],
	[Vector2(150.0, 120.0), Vector2(-60.0, 210.0), Vector2(-150.0, 270.0), Vector2(-210.0, 480.0)],
	[Vector2(170.0, -150.0), Vector2(315.0, 10.0), Vector2(305.0, 275.0)],
]

const KEY_ISLANDS: Array[Dictionary] = [
	{"position": Vector2(-310.0, -780.0), "size": Vector2(95.0, 34.0), "rotation": -0.35},
	{"position": Vector2(-190.0, -850.0), "size": Vector2(82.0, 30.0), "rotation": 0.08},
	{"position": Vector2(-45.0, -900.0), "size": Vector2(115.0, 38.0), "rotation": 0.28},
	{"position": Vector2(120.0, -860.0), "size": Vector2(88.0, 30.0), "rotation": 0.45},
	{"position": Vector2(255.0, -735.0), "size": Vector2(72.0, 24.0), "rotation": 0.78},
]

const MARINAS: Array[Dictionary] = [
	{"position": Vector2(315.0, -370.0), "rotation": 1.1, "slips": 12},
	{"position": Vector2(210.0, 85.0), "rotation": 0.35, "slips": 10},
	{"position": Vector2(-250.0, -700.0), "rotation": -0.6, "slips": 8},
]

const LANDMARKS: Array[Dictionary] = [
	{"kind": "lighthouse", "name": "Torch Key Light", "position": Vector2(250.0, -725.0), "rotation": 0.78},
	{"kind": "wheel", "name": "Sunset Wheel", "position": Vector2(310.0, -350.0), "rotation": 1.1},
	{"kind": "launch", "name": "Atlas Point", "position": Vector2(315.0, 265.0), "rotation": 0.12},
	{"kind": "arch", "name": "Gulf Gate", "position": Vector2(-260.0, -690.0), "rotation": -0.6},
]


static func outline(scale: float = DEFAULT_SCALE) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in OUTLINE:
		points.append(p * scale)
	return points


static func closed_outline(scale: float = DEFAULT_SCALE) -> PackedVector2Array:
	var points := outline(scale)
	if points.size() > 0:
		points.append(points[0])
	return points


static func city_nodes(scale: float = DEFAULT_SCALE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for city in CITY_NODES:
		out.append(
			{
				"name": city["name"],
				"position": (city["position"] as Vector2) * scale,
				"height": float(city["height"]) * scale,
				"radius": float(city["radius"]) * scale,
			}
		)
	return out


static func road_paths(scale: float = DEFAULT_SCALE) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for path in ROAD_PATHS:
		var points := PackedVector2Array()
		for p in path:
			points.append((p as Vector2) * scale)
		out.append(points)
	return out


static func key_islands(scale: float = DEFAULT_SCALE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for island in KEY_ISLANDS:
		out.append(
			{
				"position": (island["position"] as Vector2) * scale,
				"size": (island["size"] as Vector2) * scale,
				"rotation": float(island["rotation"]),
			}
		)
	return out


static func marinas(scale: float = DEFAULT_SCALE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for marina in MARINAS:
		out.append(
			{
				"position": (marina["position"] as Vector2) * scale,
				"rotation": float(marina["rotation"]),
				"slips": int(marina["slips"]),
			}
		)
	return out


static func landmarks(scale: float = DEFAULT_SCALE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for landmark in LANDMARKS:
		out.append(
			{
				"kind": landmark["kind"],
				"name": landmark["name"],
				"position": (landmark["position"] as Vector2) * scale,
				"rotation": float(landmark["rotation"]),
			}
		)
	return out


static func bridge_paths(scale: float = DEFAULT_SCALE) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for path in road_paths(scale):
		if path.size() >= 2:
			out.append(PackedVector2Array([path[0], path[1]]))
	return out


static func wetland_points(count: int, scale: float = DEFAULT_SCALE, seed: int = 60611) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points: Array[Vector2] = []
	var minmax := bounds(scale)
	var attempts := 0
	while points.size() < count and attempts < count * 20:
		attempts += 1
		var p := Vector2(
			rng.randf_range(minmax.position.x, minmax.end.x),
			rng.randf_range(minmax.position.y, minmax.end.y)
		)
		if not contains_point(p, scale):
			continue
		# Keep wetlands mostly interior and westward so the cities/coast stay readable.
		if p.x > 120.0 * scale or p.y < -700.0 * scale:
			continue
		points.append(p)
	return points


static func bounds(scale: float = DEFAULT_SCALE) -> Rect2:
	var points := outline(scale)
	if points.is_empty():
		return Rect2()
	var min_p := points[0]
	var max_p := points[0]
	for p in points:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	return Rect2(min_p, max_p - min_p)


static func contains_point(point: Vector2, scale: float = DEFAULT_SCALE) -> bool:
	return Geometry2D.is_point_in_polygon(point, outline(scale))
