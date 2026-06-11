class_name HumanoidMesh
extends RefCounted
## Premium procedural humanoid body geometry.
##
## Replaces the greybox box body with smoothly-tapered, rounded, anatomically
## proportioned limbs, torso, head, hands and feet. Everything is built from one
## generic lofted-surface helper (a stack of elliptical rings skinned into a
## watertight tube with rounded ends), so the math is pure and scene-free and
## unit-tests headless (tests/unit/test_humanoid_mesh.gd) — same testable-core
## pattern as CityBuilder. A separate HumanoidBody node drops these meshes onto
## the existing rig pivots, so the animator that swings the joints is untouched.
##
## Geometry is returned as {vertices, normals, indices} ready for the ARRAY_*
## slots; smooth per-vertex normals give limbs an organic, un-faceted shade.
## All parts are authored in the local space of the rig MeshInstance3D they
## replace (centred on the instance origin) so no rig transform has to move.

const TAU_F: float = TAU


## Build a lofted surface from a profile of rings. Each ring is a Vector3
## (t, r_a, r_b): t is the position along the spine, r_a/r_b the cross-section
## radii on the two perpendicular axes (elliptical cross-sections let a chest be
## wider than it is deep). With along_z = false the spine is +Y and the section
## lies in XZ; with along_z = true the spine is +Z and the section lies in XY
## (used for the forward-pointing foot). Rings are skinned with quad strips and
## both ends fan-capped; normals are smoothed across shared vertices.
static func lofted(rings: Array, segments: int, along_z: bool = false) -> Dictionary:
	if rings.size() < 2 or segments < 3:
		return {}
	# Normalise to ascending spine order so one winding yields outward normals
	# regardless of whether a part was authored top-down (limbs) or heel-to-toe.
	var ordered: Array = rings
	if float(rings[rings.size() - 1].x) < float(rings[0].x):
		ordered = rings.duplicate()
		ordered.reverse()
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var ring_start := PackedInt32Array()

	for ring in ordered:
		ring_start.append(verts.size())
		var t: float = ring.x
		var r_a: float = ring.y
		var r_b: float = ring.z
		for k in segments:
			var ang: float = float(k) / float(segments) * TAU_F
			var ca: float = cos(ang) * r_a
			var sb: float = sin(ang) * r_b
			verts.append(Vector3(ca, sb, t) if along_z else Vector3(ca, t, sb))

	# Skin consecutive rings with two outward-wound triangles per segment.
	for i in range(ordered.size() - 1):
		var s0: int = ring_start[i]
		var s1: int = ring_start[i + 1]
		for k in segments:
			var k2: int = (k + 1) % segments
			indices.append_array([s0 + k, s1 + k, s0 + k2, s0 + k2, s1 + k, s1 + k2])

	# End caps (fans to a centre point), wound so each faces away from the body.
	_cap(verts, indices, ring_start[0], segments, ordered[0].x, along_z, true)
	var last: int = ordered.size() - 1
	_cap(verts, indices, ring_start[last], segments, ordered[last].x, along_z, false)

	return {"vertices": verts, "normals": _smooth_normals(verts, indices), "indices": indices}


static func _cap(
	verts: PackedVector3Array,
	indices: PackedInt32Array,
	ring_start: int,
	segments: int,
	t: float,
	along_z: bool,
	min_end: bool
) -> void:
	var centre := Vector3(0.0, 0.0, t) if along_z else Vector3(0.0, t, 0.0)
	var c: int = verts.size()
	verts.append(centre)
	for k in segments:
		var k2: int = (k + 1) % segments
		var v0: int = ring_start + k
		var v1: int = ring_start + k2
		# The min-t end faces -spine, the max-t end faces +spine: opposite winding.
		if min_end:
			indices.append_array([c, v1, v0])
		else:
			indices.append_array([c, v0, v1])


## Smooth per-vertex normals: accumulate each triangle's face normal onto its
## three vertices, then normalise. Shared loft vertices end up averaged, which
## is what gives the body its rounded, un-faceted look.
static func _smooth_normals(
	verts: PackedVector3Array, indices: PackedInt32Array
) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var i: int = 0
	while i + 2 < indices.size() + 1 and i + 2 < indices.size():
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


## Quadratic Bezier through three control radii — a smooth taper with a belly:
## start at r0, bulge toward r1 at the midpoint, finish at r2. Used to give limbs
## a bicep/calf swell instead of a dead-straight cone.
static func _bezier3(r0: float, r1: float, r2: float, s: float) -> float:
	var u: float = 1.0 - s
	return u * u * r0 + 2.0 * u * s * r1 + s * s * r2


## A rounded, tapered limb centred on the origin, spine along Y. The radius
## follows _bezier3(top, mid, bottom) along the length, then the last `round_frac`
## of each end is pulled in along a circular arc so the tip domes over like a
## capsule rather than ending in a flat disc.
static func limb(
	length: float,
	r_top: float,
	r_mid: float,
	r_bottom: float,
	segments: int = 16,
	count: int = 18,
	round_frac: float = 0.16
) -> Dictionary:
	var rings: Array = []
	var half: float = length * 0.5
	for i in count + 1:
		var s: float = float(i) / float(count)  # 0 at top, 1 at bottom
		var t: float = half - s * length
		var base: float = _bezier3(r_top, r_mid, r_bottom, s)
		var dome: float = 1.0
		if s < round_frac:
			dome = sqrt(maxf(0.0, 1.0 - pow(1.0 - s / round_frac, 2.0)))
		elif s > 1.0 - round_frac:
			dome = sqrt(maxf(0.0, 1.0 - pow((s - (1.0 - round_frac)) / round_frac, 2.0)))
		var r: float = base * dome
		rings.append(Vector3(t, r, r))
	return lofted(rings, segments)


## Chest-to-waist torso: an elliptical trunk (wider across the shoulders than
## front-to-back), gently rounded at top and bottom. y spans [-h/2, h/2].
static func torso(
	height: float = 0.6,
	shoulder_w: float = 0.25,
	shoulder_d: float = 0.15,
	waist_w: float = 0.17,
	waist_d: float = 0.12
) -> Dictionary:
	var h: float = height * 0.5
	var rings: Array = [
		# Broad, shallow top ring = flat shoulders the neck rises out of, rather
		# than a pinched peak.
		Vector3(h, shoulder_w * 0.98, shoulder_d * 0.72),
		Vector3(h * 0.80, shoulder_w, shoulder_d),
		Vector3(h * 0.30, shoulder_w * 0.9, shoulder_d * 0.95),
		Vector3(-h * 0.20, waist_w * 1.06, waist_d * 1.04),
		Vector3(-h * 0.72, waist_w, waist_d),
		Vector3(-h, waist_w * 0.78, waist_d * 0.82),
	]
	return lofted(rings, 18)


## Pelvis/hip block: a short, rounded elliptical segment.
static func pelvis(height: float = 0.22, width: float = 0.21, depth: float = 0.125) -> Dictionary:
	var h: float = height * 0.5
	var rings: Array = [
		Vector3(h, width * 0.82, depth * 0.86),
		Vector3(h * 0.2, width, depth),
		Vector3(-h * 0.5, width * 1.02, depth),
		Vector3(-h, width * 0.7, depth * 0.78),
	]
	return lofted(rings, 18)


## Head: an egg-shaped ovoid (slightly narrower at the jaw), spine along Y.
static func head(height: float = 0.28, width: float = 0.13, depth: float = 0.13) -> Dictionary:
	var h: float = height * 0.5
	var rings: Array = []
	var count: int = 12
	for i in count + 1:
		var s: float = float(i) / float(count)
		var t: float = h - s * height
		# Sphere-ish profile, lifted to an egg by widening the upper cranium.
		var prof: float = sin(s * PI)
		var jaw: float = lerpf(1.04, 0.82, s)
		rings.append(Vector3(t, width * prof * jaw, depth * prof * jaw))
	return lofted(rings, 18)


## Neck: a short skin column that bridges the shoulders and the head so the
## head no longer reads as floating above the collar.
static func neck(height: float = 0.16, radius: float = 0.052) -> Dictionary:
	var h: float = height * 0.5
	var rings: Array = [
		Vector3(h, radius * 0.9, radius * 0.92),
		Vector3(0.0, radius, radius),
		Vector3(-h, radius * 1.08, radius * 1.0),
	]
	return lofted(rings, 12)


## Hair: a thin shell over the upper cranium, a touch proud of the skull, from
## the crown down to the brow line. Authored in Head-local space (head centred at
## origin) so the builder can parent it straight to the head with no offset.
static func hair(head_height: float = 0.28, head_width: float = 0.13) -> Dictionary:
	var rings: Array = []
	var count: int = 12
	for i in count + 1:
		var s: float = lerpf(0.0, 0.5, float(i) / float(count))  # crown(pole) → brow
		var y: float = head_height * 0.5 - s * head_height
		var jaw: float = lerpf(1.04, 0.86, s)
		# pow(sin, 0.7) fattens the crown so the top domes over like a beanie
		# instead of pinching into a witch-hat point.
		var r: float = head_width * pow(sin(s * PI), 0.7) * jaw * 1.08
		rings.append(Vector3(y, r, r))
	return lofted(rings, 18)


## Forearm/upper-arm as one tapered limb (shoulder → wrist), centred on origin.
static func arm(length: float = 0.6) -> Dictionary:
	return limb(length, 0.062, 0.07, 0.046, 14, 18)


## Thigh/calf as one tapered limb (hip → ankle) with a calf swell. Slimmer than a
## box so the two legs read as a clear pair instead of one solid mass.
static func leg(length: float = 0.82) -> Dictionary:
	return limb(length, 0.086, 0.08, 0.05, 16, 20)


## A rounded fist, spine along Y, sized to sit at the wrist.
static func hand() -> Dictionary:
	var rings: Array = [
		Vector3(0.06, 0.03, 0.035),
		Vector3(0.02, 0.058, 0.066),
		Vector3(-0.03, 0.062, 0.072),
		Vector3(-0.06, 0.04, 0.05),
	]
	return lofted(rings, 12)


## A shoe: a rounded, forward-pointing form (spine along +Z, toe forward) with a
## flat-ish sole implied by the squashed vertical radius.
static func foot(length: float = 0.3, width: float = 0.1, height: float = 0.06) -> Dictionary:
	var h: float = length * 0.5
	var rings: Array = [
		Vector3(-h, width * 0.7, height * 0.7),  # heel
		Vector3(-h * 0.5, width, height),
		Vector3(h * 0.1, width * 1.04, height * 1.05),
		Vector3(h * 0.7, width * 0.86, height * 0.78),
		Vector3(h, width * 0.5, height * 0.5),  # toe
	]
	return lofted(rings, 14, true)


## Pack a geometry dict into an ArrayMesh surface. Empty/degenerate → null.
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
