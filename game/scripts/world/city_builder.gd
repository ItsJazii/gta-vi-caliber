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

## Sun-bleached wall palette: worn stucco/concrete tones (VISION.md coastal-city
## look). building_color() picks per building so blocks don't read as one grey
## extrusion.
const WALL_PALETTE: Array[Color] = [
	Color(0.93, 0.89, 0.80),  # bleached white plaster
	Color(0.87, 0.78, 0.58),  # cream stucco
	Color(0.80, 0.70, 0.52),  # sandstone
	Color(0.78, 0.58, 0.45),  # faded terracotta
	Color(0.72, 0.70, 0.65),  # weathered concrete
	Color(0.82, 0.66, 0.58),  # dusty rose
	Color(0.62, 0.70, 0.60),  # faded sage
	Color(0.60, 0.66, 0.72),  # hazy blue-grey
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
		indices.append_array(
			[base_index, base_index + 1, base_index + 2, base_index, base_index + 2, base_index + 3]
		)

	# Roof cap.
	var tri := Geometry2D.triangulate_polygon(ring)
	if not tri.is_empty():
		var roof_base := vertices.size()
		for p in ring:
			vertices.append(Vector3(p.x, top, p.y))
			normals.append(UP)
		# triangulate_polygon yields clockwise tris for CCW input → reverse for up-facing.
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
