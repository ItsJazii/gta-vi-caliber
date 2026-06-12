class_name CarMesh
extends RefCounted
## Pure procedural car-body geometry.
##
## A sleek single-volume hull lofted from rounded (superellipse) cross-sections
## whose width and roof height follow a car silhouette along the length: low nose,
## raked windshield up to a flat roof, dropping rear window into a short tail.
## Static and scene-free so it unit-tests headless (tests/unit/test_car_mesh.gd) —
## same testable-core pattern as HumanoidMesh/CityBuilder. A CarBody node swaps
## this (and metallic wheel rims) onto the greybox car at runtime, leaving the
## VehicleBody3D physics, wheels and collision untouched.

## Superellipse exponent for the cross-section: ~3 reads as a rounded rectangle
## (flat-ish roof/sides with soft corners), far more car-like than an ellipse.
const SE_POWER: float = 3.0
## Floor of the body shell (metres, body-local). Sits just above the wheel tops.
const FLOOR_Y: float = 0.30
## Roofline silhouette: (u along length 0=nose..1=tail, height in metres). The
## windshield/rear-window rakes are the big jumps; smoothstep rounds them over.
const ROOFLINE: Array[Vector2] = [
	Vector2(0.0, 0.62),
	Vector2(0.10, 0.80),
	Vector2(0.32, 0.86),
	Vector2(0.44, 1.30),
	Vector2(0.62, 1.34),
	Vector2(0.76, 1.04),
	Vector2(1.0, 0.86),
]
## A taller, longer-cabined SUV silhouette.
const ROOFLINE_SUV: Array[Vector2] = [
	Vector2(0.0, 0.7),
	Vector2(0.12, 0.96),
	Vector2(0.3, 1.02),
	Vector2(0.4, 1.5),
	Vector2(0.74, 1.52),
	Vector2(0.86, 1.32),
	Vector2(1.0, 1.06),
]
## A boxy cab-forward van: tall flat roof across most of the length.
const ROOFLINE_VAN: Array[Vector2] = [
	Vector2(0.0, 0.72),
	Vector2(0.1, 1.02),
	Vector2(0.22, 1.56),
	Vector2(0.3, 1.62),
	Vector2(0.86, 1.62),
	Vector2(0.95, 1.42),
	Vector2(1.0, 1.12),
]
# The greenhouse glass belt is classified on the loft GRID, not in world space:
# by length fraction u (cabin between windshield and rear window) and by the
# cross-section height fraction f (above the beltline, below the painted roof).
# Both seams fall on constant-u / constant-f grid lines, so the paint/glass
# boundary is clean — a world-space centroid box staircases on a round hull.
const GLASS_U_FRONT: float = 0.30
const GLASS_U_REAR: float = 0.78
const GLASS_F_LOW: float = 0.34
const GLASS_F_HIGH: float = 0.88


## Build the car body. length/width are the overall hull bounds (metres); the
## mesh is centred on X and Z with the floor at FLOOR_Y, matching the greybox
## chassis it replaces so no node transform has to move.
static func body(
	length: float = 4.2, width: float = 1.9, slices: int = 28, segments: int = 24, style: int = 0
) -> Dictionary:
	var roofline: Array = ROOFLINE
	if style == 1:
		roofline = ROOFLINE_SUV
	elif style == 2:
		roofline = ROOFLINE_VAN
	var prof: Array = []
	for i in slices + 1:
		var u: float = float(i) / float(slices)
		var z: float = lerpf(-length * 0.5, length * 0.5, u)
		var half_w: float = width * 0.5 * _width_profile(u)
		var top: float = _roofline(u, roofline)
		prof.append([z, half_w, (top + FLOOR_Y) * 0.5, (top - FLOOR_Y) * 0.5])
	return _loft(prof, segments)


## Width taper toward the nose and tail so the ends round off instead of slab-cut.
static func _width_profile(u: float) -> float:
	var ends: float = minf(smoothstep(0.0, 0.12, u), smoothstep(0.0, 0.12, 1.0 - u))
	return lerpf(0.55, 1.0, ends)


## Roof height at u via smoothstep-interpolated control points.
static func _roofline(u: float, points: Array) -> float:
	for i in range(points.size() - 1):
		if u <= points[i + 1].x:
			var span: float = maxf(points[i + 1].x - points[i].x, 1e-5)
			var t: float = smoothstep(0.0, 1.0, (u - points[i].x) / span)
			return lerpf(points[i].y, points[i + 1].y, t)
	return points[points.size() - 1].y


## Superellipse point at the given angle for a half-width/half-height box.
static func _se(angle: float, half_w: float, half_h: float) -> Vector2:
	var c: float = cos(angle)
	var s: float = sin(angle)
	var x: float = half_w * signf(c) * pow(absf(c), 2.0 / SE_POWER)
	var y: float = half_h * signf(s) * pow(absf(s), 2.0 / SE_POWER)
	return Vector2(x, y)


## Loft a list of [z, half_w, centre_y, half_h] slices (ascending z) into a closed
## hull, split into paint (`indices`) and glass (`glass_indices`) surfaces. Side
## winding is outward; ends are fan-capped; normals are smoothed over both.
static func _loft(prof: Array, segments: int) -> Dictionary:
	var verts := PackedVector3Array()
	var paint := PackedInt32Array()
	var glass := PackedInt32Array()
	var ring_start := PackedInt32Array()

	for slice in prof:
		ring_start.append(verts.size())
		var z: float = slice[0]
		var half_w: float = slice[1]
		var cy: float = slice[2]
		var half_h: float = slice[3]
		for k in segments:
			var p: Vector2 = _se(float(k) / float(segments) * TAU, half_w, half_h)
			verts.append(Vector3(p.x, cy + p.y, z))

	for i in range(prof.size() - 1):
		var s0: int = ring_start[i]
		var s1: int = ring_start[i + 1]
		var u: float = (float(i) + 0.5) / float(prof.size() - 1)
		for k in segments:
			var k2: int = (k + 1) % segments
			var is_glass: bool = _is_glass_quad(u, k, segments)
			_tri(paint, glass, is_glass, s0 + k, s0 + k2, s1 + k)
			_tri(paint, glass, is_glass, s0 + k2, s1 + k2, s1 + k)

	_cap(verts, paint, glass, ring_start[0], segments, prof[0], true)
	var last: int = prof.size() - 1
	_cap(verts, paint, glass, ring_start[last], segments, prof[last], false)

	var combined := PackedInt32Array()
	combined.append_array(paint)
	combined.append_array(glass)
	return {
		"vertices": verts,
		"normals": _smooth_normals(verts, combined),
		"indices": paint,
		"glass_indices": glass,
	}


## Route a triangle to the paint or glass index list (the caller classifies the
## whole quad/cap on the grid, so both of a quad's triangles share one surface).
static func _tri(
	paint: PackedInt32Array, glass: PackedInt32Array, is_glass: bool, a: int, b: int, c: int
) -> void:
	if is_glass:
		glass.append_array([a, b, c])
	else:
		paint.append_array([a, b, c])


## Classify a side quad as greenhouse glass by its grid cell: within the cabin
## length (u) and between the beltline and the painted roof. f is the cross-section
## height fraction (-1 floor .. +1 roof), matching _se's vertical term exactly.
static func _is_glass_quad(u: float, k: int, segments: int) -> bool:
	if u < GLASS_U_FRONT or u > GLASS_U_REAR:
		return false
	var angle: float = (float(k) + 0.5) / float(segments) * TAU
	var s: float = sin(angle)
	var f: float = signf(s) * pow(absf(s), 2.0 / SE_POWER)
	return f > GLASS_F_LOW and f < GLASS_F_HIGH


static func _cap(
	verts: PackedVector3Array,
	paint: PackedInt32Array,
	glass: PackedInt32Array,
	ring_start: int,
	segments: int,
	slice: Array,
	min_end: bool
) -> void:
	var centre := Vector3(0.0, slice[2], slice[0])
	var c: int = verts.size()
	verts.append(centre)
	for k in segments:
		var k2: int = (k + 1) % segments
		if min_end:
			_tri(paint, glass, false, c, ring_start + k, ring_start + k2)
		else:
			_tri(paint, glass, false, c, ring_start + k2, ring_start + k)


static func _smooth_normals(
	verts: PackedVector3Array, indices: PackedInt32Array
) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var i: int = 0
	while i + 2 < indices.size():
		var ia: int = indices[i]
		var ib: int = indices[i + 1]
		var ic: int = indices[i + 2]
		var face: Vector3 = (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		normals[ia] += face
		normals[ib] += face
		normals[ic] += face
		i += 3
	for n in normals.size():
		var v: Vector3 = normals[n]
		normals[n] = v.normalized() if v.length_squared() > 1e-12 else Vector3.UP
	return normals


## Pack a geometry dict into a single ArrayMesh surface (paint faces). Empty → null.
static func to_mesh(geo: Dictionary) -> ArrayMesh:
	if geo.is_empty() or (geo["vertices"] as PackedVector3Array).is_empty():
		return null
	var mesh := ArrayMesh.new()
	_add_surface(mesh, geo["vertices"], geo["normals"], geo["indices"])
	return mesh


## Two-surface mesh: surface 0 = painted body, surface 1 = glass greenhouse.
## The builder assigns a paint and a glass material respectively.
static func to_mesh_glazed(geo: Dictionary) -> ArrayMesh:
	if geo.is_empty() or (geo["vertices"] as PackedVector3Array).is_empty():
		return null
	var mesh := ArrayMesh.new()
	_add_surface(mesh, geo["vertices"], geo["normals"], geo["indices"])
	var glass: PackedInt32Array = geo.get("glass_indices", PackedInt32Array())
	if not glass.is_empty():
		_add_surface(mesh, geo["vertices"], geo["normals"], glass)
	return mesh


static func _add_surface(
	mesh: ArrayMesh,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array
) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
