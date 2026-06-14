class_name CityBuilder
extends RefCounted
## Pure mesh geometry for the procedural city: building footprints extruded into
## prisms, and road polylines widened into flat ribbons. All functions are static
## and scene-free so they unit-test headless (tests/unit/test_city_builder.gd).
## A separate DistrictLoader turns these arrays into actual scene nodes.
##
## Geometry arrays are returned as a Dictionary {vertices, normals, indices}
## ready for ArrayMesh.add_surface_from_arrays / Mesh.ARRAY_* slots.

const UP: Vector3 = Vector3.UP

## Vice City / South Beach Art-Deco palette: vivid tropical pastels (flamingo,
## turquoise, mint, coral, lavender…) balanced by cream/white so a block reads as
## a real Deco streetscape, not a candy box. building_color() picks per building
## so neighbours differ. This is the post-pivot Miami look (see vice-city-pivot);
## the old sun-bleached LA earth tones were retired here.
const WALL_PALETTE: Array[Color] = [
	Color(0.97, 0.62, 0.70),  # flamingo pink
	Color(0.40, 0.82, 0.80),  # turquoise
	Color(0.66, 0.91, 0.74),  # mint green
	Color(0.99, 0.67, 0.51),  # coral / salmon
	Color(0.74, 0.71, 0.93),  # lavender
	Color(0.56, 0.84, 0.95),  # aqua sky
	Color(0.99, 0.90, 0.60),  # butter yellow
	Color(0.99, 0.81, 0.66),  # peach / apricot
	Color(0.97, 0.94, 0.87),  # deco cream-white
	Color(0.75, 0.93, 0.87),  # sea-foam
]


## Deterministic wall colour from the stable OSM building id: palette pick plus
## a small value jitter so palette twins on the same block still differ.
static func building_color(id: int) -> Color:
	var h := absi(hash(id))
	var base: Color = WALL_PALETTE[h % WALL_PALETTE.size()]
	var jitter := (float((h >> 16) & 0xFF) / 255.0 - 0.5) * 0.14
	return Color(
		clampf(base.r + jitter, 0.0, 1.0),
		clampf(base.g + jitter, 0.0, 1.0),
		clampf(base.b + jitter, 0.0, 1.0)
	)


## Per-building "glassiness" seed in [0,1], packed into facade vertex-colour
## alpha. Tall buildings bias high (reflective glass curtain-wall towers); short
## ones bias low (masonry/concrete). A stable hash jitter keeps same-height
## neighbours from reading as identical so a block has material variety.
static func building_glass_seed(id: int, height_m: float) -> float:
	var hfrac := clampf(height_m / 100.0, 0.0, 1.0)
	var rnd := float(absi(hash(id * 2654435761)) & 0xFFFF) / 65535.0
	return clampf(hfrac * 0.72 + rnd * 0.28, 0.02, 0.98)


## Strip a redundant closing vertex (OSM rings repeat the first point at the end)
## and collapse any near-duplicate consecutive points.
static func clean_ring(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ring:
		if out.is_empty() or out[-1].distance_to(p) > 0.01:
			out.append(p)
	if out.size() > 1 and out[0].distance_to(out[-1]) < 0.01:
		out.remove_at(out.size() - 1)
	return out


## Signed area (shoelace). Positive = counter-clockwise in our XZ 2D space.
static func signed_area(ring: PackedVector2Array) -> float:
	var a := 0.0
	var n := ring.size()
	for i in n:
		var p := ring[i]
		var q := ring[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Extrude a 2D footprint (x = east, y = north-local/z) from base_y up to
## base_y + height. Walls get flat per-face normals; a triangulated roof caps it.
## Returns {} if the ring is degenerate (< 3 distinct points).
static func extrude_prism(
	footprint: PackedVector2Array, base_y: float, height: float
) -> Dictionary:
	var ring := clean_ring(footprint)
	if ring.size() < 3:
		return {}
	# Normalise to counter-clockwise so outward wall normals are consistent.
	if signed_area(ring) < 0.0:
		ring.reverse()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var top := base_y + height
	var n := ring.size()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var dir := b - a
		if dir.length() < 0.001:
			continue
		# Outward normal for a CCW ring: rotate edge direction by -90°.
		var nrm := Vector3(dir.y, 0.0, -dir.x).normalized()
		var base_index := vertices.size()
		# Quad a_bottom, b_bottom, b_top, a_top.
		vertices.append(Vector3(a.x, base_y, a.y))
		vertices.append(Vector3(b.x, base_y, b.y))
		vertices.append(Vector3(b.x, top, b.y))
		vertices.append(Vector3(a.x, top, a.y))
		for _k in 4:
			normals.append(nrm)
		# Wound so the triangle's geometric (winding) normal matches the outward
		# shading normal above. Trimesh collision keys off winding, not the normal
		# array — inward-wound walls collide only on their backface, which lets
		# characters and raycasts pass straight through buildings.
		indices.append_array(
			[base_index, base_index + 2, base_index + 1, base_index, base_index + 3, base_index + 2]
		)

	# Roof cap.
	var tri := Geometry2D.triangulate_polygon(ring)
	if not tri.is_empty():
		var roof_base := vertices.size()
		for p in ring:
			vertices.append(Vector3(p.x, top, p.y))
			normals.append(UP)
		# REVERSE triangulate_polygon's winding so the roof's geometric normal
		# points UP (+Y). For a CCW ring (extrude_prism normalises to CCW) the raw
		# triangulation winds the roof cap DOWN (-Y) — verified by test — and the
		# roof's ConcavePolygonShape3D collider is single-sided + winding-keyed, so
		# a downward ray/footstep/landing passed straight through the roof to the
		# ground. Swapping the last two indices flips the cap to face up; vertex and
		# index COUNTS are unchanged so the geometry/count tests stay green.
		var t := 0
		while t + 2 < tri.size() + 1 and t + 2 < tri.size():
			indices.append(roof_base + tri[t])
			indices.append(roof_base + tri[t + 2])
			indices.append(roof_base + tri[t + 1])
			t += 3

	return {"vertices": vertices, "normals": normals, "indices": indices}


## Widen a polyline into a flat ground ribbon of the given width at height y.
## Miterless (each segment is its own quad) — fine for greybox roads.
static func road_ribbon(path: PackedVector2Array, width: float, y: float) -> Dictionary:
	var pts := clean_ring_open(path)
	if pts.size() < 2:
		return {}
	var half := width * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var uvs := PackedVector2Array()
	var along := 0.0

	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var dir := b - a
		var seg := dir.length()
		if seg < 0.001:
			continue
		dir = dir / seg
		var side := Vector2(-dir.y, dir.x) * half
		var base_index := vertices.size()
		vertices.append(Vector3(a.x - side.x, y, a.y - side.y))
		vertices.append(Vector3(a.x + side.x, y, a.y + side.y))
		vertices.append(Vector3(b.x + side.x, y, b.y + side.y))
		vertices.append(Vector3(b.x - side.x, y, b.y - side.y))
		for _k in 4:
			normals.append(UP)
		# UV.x spans the width 0..1, UV.y accumulates metres along the
		# centreline — road shaders draw lane paint/sidewalks from these.
		uvs.append(Vector2(0.0, along))
		uvs.append(Vector2(1.0, along))
		uvs.append(Vector2(1.0, along + seg))
		uvs.append(Vector2(0.0, along + seg))
		along += seg
		# Clockwise-from-above winding: Godot front faces match PlaneMesh, so
		# up-facing ribbons survive back-face culling (they used to be culled).
		indices.append_array(
			[base_index, base_index + 2, base_index + 1, base_index, base_index + 3, base_index + 2]
		)

	return {"vertices": vertices, "normals": normals, "indices": indices, "uvs": uvs}


## Like clean_ring but for open polylines (keeps the last point).
static func clean_ring_open(path: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in path:
		if out.is_empty() or out[-1].distance_to(p) > 0.01:
			out.append(p)
	return out


## Two raised concrete sidewalk strips flanking a road polyline: a vertical curb
## face at the gutter rising to curb_h, then a flat walking top extending
## walk_width outward. The inner edge sits at road_width*0.5 so it meets the road
## ribbon with no gap. Per-segment quads like road_ribbon; the sidewalk shader is
## cull_disabled, so a single winding is fine for both sides. UVs: U across the
## strip (0 at the curb face .. 1 at the outer edge), V metres along the
## centreline — mesh-local, so it stays stable under FloatingOrigin shifts.
static func sidewalk_ribbon(
	path: PackedVector2Array, road_width: float, walk_width: float, curb_h: float, base_y: float
) -> Dictionary:
	var pts := clean_ring_open(path)
	if pts.size() < 2:
		return {}
	var inner := road_width * 0.5
	var outer := inner + walk_width
	var curb_frac := curb_h / (curb_h + walk_width)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var uv := PackedVector2Array()
	var along := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var seg := d.length()
		if seg < 0.001:
			continue
		d /= seg
		var s := Vector2(-d.y, d.x)
		for side_sign in [1.0, -1.0]:
			var sd := s * float(side_sign)
			var toroad := Vector3(-sd.x, 0.0, -sd.y)
			var gi_a := _side_pt(a, sd, inner, base_y)
			var gi_b := _side_pt(b, sd, inner, base_y)
			var li_a := _side_pt(a, sd, inner, base_y + curb_h)
			var li_b := _side_pt(b, sd, inner, base_y + curb_h)
			var lo_a := _side_pt(a, sd, outer, base_y + curb_h)
			var lo_b := _side_pt(b, sd, outer, base_y + curb_h)
			# Curb face (vertical), normal toward the road.
			_sw_quad(
				v,
				n,
				idx,
				uv,
				gi_a,
				gi_b,
				li_b,
				li_a,
				toroad,
				Vector2(0.0, along),
				Vector2(0.0, along + seg),
				Vector2(curb_frac, along + seg),
				Vector2(curb_frac, along)
			)
			# Walking top (horizontal), normal up.
			_sw_quad(
				v,
				n,
				idx,
				uv,
				li_a,
				li_b,
				lo_b,
				lo_a,
				UP,
				Vector2(curb_frac, along),
				Vector2(curb_frac, along + seg),
				Vector2(1.0, along + seg),
				Vector2(1.0, along)
			)
		along += seg
	return {"vertices": v, "normals": n, "indices": idx, "uvs": uv}


## Offset a 2D centreline point sideways by `off` metres and lift to height y.
static func _side_pt(p: Vector2, side: Vector2, off: float, y: float) -> Vector3:
	return Vector3(p.x + side.x * off, y, p.y + side.y * off)


## Append one quad (two tris, shared face normal, 4 UVs) into the sidewalk arrays.
static func _sw_quad(
	v: PackedVector3Array,
	n: PackedVector3Array,
	idx: PackedInt32Array,
	uv: PackedVector2Array,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	nrm: Vector3,
	u0: Vector2,
	u1: Vector2,
	u2: Vector2,
	u3: Vector2
) -> void:
	var bi := v.size()
	v.append(p0)
	v.append(p1)
	v.append(p2)
	v.append(p3)
	for _k in 4:
		n.append(nrm)
	uv.append(u0)
	uv.append(u1)
	uv.append(u2)
	uv.append(u3)
	idx.append_array([bi, bi + 2, bi + 1, bi, bi + 3, bi + 2])


## Pack a geometry Dictionary into an ArrayMesh surface. Empty dict → null.
## Optional "uvs" / "colors" keys ride along into the matching ARRAY_* slots
## (road paint coordinates, per-building facade tints).
static func arrays_to_mesh(geo: Dictionary) -> ArrayMesh:
	if geo.is_empty() or (geo["vertices"] as PackedVector3Array).is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = geo["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = geo["normals"]
	arrays[Mesh.ARRAY_INDEX] = geo["indices"]
	if geo.has("uvs"):
		arrays[Mesh.ARRAY_TEX_UV] = geo["uvs"]
	if geo.has("colors"):
		arrays[Mesh.ARRAY_COLOR] = geo["colors"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
