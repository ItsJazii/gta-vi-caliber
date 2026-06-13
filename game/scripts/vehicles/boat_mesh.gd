class_name BoatMesh
extends RefCounted
## Pure procedural speedboat hull geometry.
##
## A sleek shell lofted from rounded (superellipse) cross-sections with a pointed
## bow, a hull bottom that rockers up at bow and stern, and a flared deck line
## raised at the bow. Static and scene-free so it unit-tests headless
## (tests/unit/test_boat_mesh.gd). A BoatBody node swaps
## it onto the greybox boat at runtime, leaving the RigidBody physics untouched.

const SE_POWER: float = 2.6


## Build the hull. length(z)/width(x)/depth(y) are the bounds (metres); centred on
## X/Z with the keel near y=0, matching the greybox hull box it replaces.
static func hull(
	length: float = 3.4,
	width: float = 1.8,
	depth: float = 0.8,
	slices: int = 24,
	segments: int = 20
) -> Dictionary:
	var prof: Array = []
	for i in slices + 1:
		var u: float = float(i) / float(slices)  # 0 bow(-z) .. 1 stern(+z)
		var z: float = lerpf(-length * 0.5, length * 0.5, u)
		var half_w: float = width * 0.5 * _width(u)
		var top: float = _deck(u, depth)
		var bottom: float = _keel(u, depth)
		prof.append([z, half_w, (top + bottom) * 0.5, (top - bottom) * 0.5])
	return _loft(prof, segments)


## Pointed bow, full-width body, slightly tucked stern.
static func _width(u: float) -> float:
	var bow: float = smoothstep(0.0, 0.34, u)
	var stern: float = lerpf(1.0, 0.9, smoothstep(0.8, 1.0, u))
	return lerpf(0.04, 1.0, bow) * stern


## Gunwale/deck line, raised toward the bow for a sheer line.
static func _deck(u: float, depth: float) -> float:
	return depth * lerpf(1.12, 0.92, smoothstep(0.0, 0.5, u))


## Hull bottom: a rockered keel — lowest amidships, lifting at bow and stern.
static func _keel(u: float, depth: float) -> float:
	return depth * (0.06 + 0.18 * pow(2.0 * u - 1.0, 2.0))


static func _se(angle: float, half_w: float, half_h: float) -> Vector2:
	var c: float = cos(angle)
	var s: float = sin(angle)
	var x: float = half_w * signf(c) * pow(absf(c), 2.0 / SE_POWER)
	var y: float = half_h * signf(s) * pow(absf(s), 2.0 / SE_POWER)
	return Vector2(x, y)


static func _loft(prof: Array, segments: int) -> Dictionary:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
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
		for k in segments:
			var k2: int = (k + 1) % segments
			indices.append_array([s0 + k, s0 + k2, s1 + k, s0 + k2, s1 + k2, s1 + k])

	_cap(verts, indices, ring_start[0], segments, prof[0])
	_cap(verts, indices, ring_start[prof.size() - 1], segments, prof[prof.size() - 1])

	return {"vertices": verts, "normals": _smooth_normals(verts, indices), "indices": indices}


static func _cap(
	verts: PackedVector3Array,
	indices: PackedInt32Array,
	ring_start: int,
	segments: int,
	slice: Array
) -> void:
	var c: int = verts.size()
	verts.append(Vector3(0.0, slice[2], slice[0]))
	for k in segments:
		indices.append_array([c, ring_start + k, ring_start + (k + 1) % segments])


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


## Pack a geometry dict into an ArrayMesh surface. Empty → null.
static func to_mesh(geo: Dictionary) -> ArrayMesh:
	if geo.is_empty() or (geo["vertices"] as PackedVector3Array).is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = geo["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = geo["normals"]
	arrays[Mesh.ARRAY_INDEX] = geo["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
