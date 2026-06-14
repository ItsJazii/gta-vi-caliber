class_name TestPrismRoof
extends GdUnitTestSuite
## Resolves a contested finding: does extrude_prism's roof cap face UP (+Y)?
## The roof builds a ConcavePolygonShape3D (single-sided, winding-keyed) collider,
## so a downward ray / footstep / landing only registers if the roof's geometric
## winding normal points +Y. A -Y roof is walk-through.


func test_roof_cap_faces_up() -> void:
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var geo := CityBuilder.extrude_prism(ring, 0.0, 25.0)
	var verts: PackedVector3Array = geo["vertices"]
	var idx: PackedInt32Array = geo["indices"]
	var top := 25.0
	var roof_tris := 0
	var i := 0
	while i + 2 < idx.size():
		var a: Vector3 = verts[idx[i]]
		var b: Vector3 = verts[idx[i + 1]]
		var c: Vector3 = verts[idx[i + 2]]
		# A roof triangle has all three vertices at the top plane (wall triangles
		# always include a base-height vertex).
		if is_equal_approx(a.y, top) and is_equal_approx(b.y, top) and is_equal_approx(c.y, top):
			roof_tris += 1
			var winding_normal := (b - a).cross(c - a)
			assert_float(winding_normal.y).is_greater(0.0)
		i += 3
	assert_int(roof_tris).is_greater(0)  # ensure we actually checked roof triangles
