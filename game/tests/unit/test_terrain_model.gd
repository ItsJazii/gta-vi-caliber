extends RefCounted
## Unit tests for TerrainModel — the procedural heightfield under the open world.
## The load-bearing property is seamlessness: chunks must share edge heights
## exactly, or the world cracks along tile borders.


func test_height_is_deterministic() -> bool:
	return is_equal_approx(
		TerrainModel.height_at(123.0, -57.0), TerrainModel.height_at(123.0, -57.0)
	)


func test_height_varies_across_the_world() -> bool:
	# Two far-apart points should almost never share a height.
	return not is_equal_approx(
		TerrainModel.height_at(0.0, 0.0), TerrainModel.height_at(800.0, 600.0)
	)


func test_height_within_amplitude_bounds() -> bool:
	for p in [Vector2(0, 0), Vector2(500, 500), Vector2(-1200, 300), Vector2(2000, -2000)]:
		var h := TerrainModel.height_at(p.x, p.y)
		if absf(h) > TerrainModel.AMPLITUDE + TerrainModel.VALLEY_DEPTH + 1.0:
			return false
	return true


func test_seed_changes_terrain() -> bool:
	return not is_equal_approx(
		TerrainModel.height_at(100.0, 100.0, 1), TerrainModel.height_at(100.0, 100.0, 2)
	)


func test_normal_is_unit_length() -> bool:
	for p in [Vector2(0, 0), Vector2(321, -88), Vector2(-940, 1200)]:
		if absf(TerrainModel.normal_at(p.x, p.y).length() - 1.0) > 1e-4:
			return false
	return true


func test_normal_points_upward() -> bool:
	# A height-field surface never overhangs, so the normal's Y is always > 0.
	for p in [Vector2(0, 0), Vector2(321, -88), Vector2(-940, 1200), Vector2(50, 50)]:
		if TerrainModel.normal_at(p.x, p.y).y <= 0.0:
			return false
	return true


func test_chunk_vertex_count() -> bool:
	var res := 8
	var chunk := TerrainModel.chunk_arrays(0.0, 0.0, 64.0, res)
	var verts: PackedVector3Array = chunk["vertices"]
	var idx: PackedInt32Array = chunk["indices"]
	return verts.size() == (res + 1) * (res + 1) and idx.size() == res * res * 6


func test_chunk_local_origin_corner() -> bool:
	# First vertex sits at local (0,0) with the world height of the chunk corner.
	var chunk := TerrainModel.chunk_arrays(128.0, -64.0, 64.0, 4)
	var v: Vector3 = chunk["vertices"][0]
	return (
		is_equal_approx(v.x, 0.0)
		and is_equal_approx(v.z, 0.0)
		and is_equal_approx(v.y, TerrainModel.height_at(128.0, -64.0))
	)


func test_chunks_are_seamless() -> bool:
	# The east edge of chunk A must equal the west edge of its neighbour B, in
	# world-space height, so tiles join with no cracks.
	var span := 64.0
	var res := 8
	var a := TerrainModel.chunk_arrays(0.0, 0.0, span, res)
	var b := TerrainModel.chunk_arrays(span, 0.0, span, res)
	var va: PackedVector3Array = a["vertices"]
	var vb: PackedVector3Array = b["vertices"]
	var stride := res + 1
	for j in range(res + 1):
		var east := va[j * stride + res]  # last column of A
		var west := vb[j * stride + 0]  # first column of B
		# Local x differs (span vs 0); the world height must match exactly.
		if not is_equal_approx(east.y, west.y):
			return false
	return true


func test_uvs_span_unit_square() -> bool:
	var chunk := TerrainModel.chunk_arrays(0.0, 0.0, 32.0, 4)
	var uvs: PackedVector2Array = chunk["uvs"]
	return uvs[0] == Vector2(0, 0) and uvs[uvs.size() - 1] == Vector2(1, 1)


func test_slope_in_unit_range() -> bool:
	for p in [Vector2(0, 0), Vector2(400, 400), Vector2(-700, 250)]:
		var s := TerrainModel.slope_at(p.x, p.y)
		if s < 0.0 or s > 1.0:
			return false
	return true
