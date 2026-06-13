extends RefCounted
## Unit tests for OceanMeshBuilder (see tests/run_tests.gd for the runner
## contract: test_* methods return true to pass) plus the Ocean node's CPU
## fade parity, so buoyancy matches the faded far-field surface.

const SIZE := 12000.0
const FINE_HALF := 1500.0
const FINE_CELLS := 96
const FAR_CELL := 750.0


func _build() -> Dictionary:
	return OceanMeshBuilder.build(SIZE, FINE_HALF, FINE_CELLS, FAR_CELL)


func test_fine_only_when_fine_covers_plane() -> bool:
	var geo := OceanMeshBuilder.build(1000.0, 500.0, 10, 100.0)
	var verts: PackedVector3Array = geo["vertices"]
	var idx: PackedInt32Array = geo["indices"]
	return verts.size() == 11 * 11 and idx.size() == 10 * 10 * 6


func test_tiered_mesh_is_far_smaller_than_uniform() -> bool:
	var geo := _build()
	var verts: PackedVector3Array = geo["vertices"]
	# The old uniform backdrop grid was 192x192 (~37k vertices).
	return verts.size() > 0 and verts.size() < 193 * 193 / 2


func test_far_vertices_lie_outside_fine_square() -> bool:
	var geo := _build()
	var fine_half: float = geo["fine_half"]
	var verts: PackedVector3Array = geo["vertices"]
	var fine_count := (FINE_CELLS + 1) * (FINE_CELLS + 1)
	for i in range(fine_count, verts.size()):
		var v := verts[i]
		if maxf(absf(v.x), absf(v.z)) < fine_half - 0.01:
			return false
	return true


func test_fine_half_snaps_to_far_grid() -> bool:
	# 1300 m requested; far step is 750 m, so the square snaps up to 1500 m.
	var geo := OceanMeshBuilder.build(SIZE, 1300.0, FINE_CELLS, FAR_CELL)
	return is_equal_approx(float(geo["fine_half"]), 1500.0)


func test_indices_in_range_and_triangulated() -> bool:
	var geo := _build()
	var verts: PackedVector3Array = geo["vertices"]
	var idx: PackedInt32Array = geo["indices"]
	if idx.size() % 3 != 0:
		return false
	for i in idx:
		if i < 0 or i >= verts.size():
			return false
	return true


func test_mesh_covers_full_plane_extent() -> bool:
	var geo := _build()
	var verts: PackedVector3Array = geo["vertices"]
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for v in verts:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_z = minf(min_z, v.z)
		max_z = maxf(max_z, v.z)
	var half := SIZE * 0.5
	return (
		is_equal_approx(min_x, -half)
		and is_equal_approx(max_x, half)
		and is_equal_approx(min_z, -half)
		and is_equal_approx(max_z, half)
	)


func test_falloff_full_inside_zero_outside() -> bool:
	var inside := OceanMeshBuilder.displacement_falloff(Vector2(100, -200), 1250.0, 1500.0)
	var at_edge := OceanMeshBuilder.displacement_falloff(Vector2(1500, 0), 1250.0, 1500.0)
	var beyond := OceanMeshBuilder.displacement_falloff(Vector2(0, 4000), 1250.0, 1500.0)
	var mid := OceanMeshBuilder.displacement_falloff(Vector2(1375, 0), 1250.0, 1500.0)
	return (
		is_equal_approx(inside, 1.0)
		and is_equal_approx(at_edge, 0.0)
		and is_equal_approx(beyond, 0.0)
		and mid > 0.0
		and mid < 1.0
	)


func test_falloff_uses_chebyshev_distance() -> bool:
	# A diagonal point at (1100, 1100) has Euclidean length ~1556 but
	# Chebyshev 1100 — still fully displaced for a 1250 m fade start.
	var f := OceanMeshBuilder.displacement_falloff(Vector2(1100, 1100), 1250.0, 1500.0)
	return is_equal_approx(f, 1.0)


func test_falloff_degenerate_band_is_step() -> bool:
	var inside := OceanMeshBuilder.displacement_falloff(Vector2(10, 0), 500.0, 500.0)
	var outside := OceanMeshBuilder.displacement_falloff(Vector2(600, 0), 500.0, 500.0)
	return is_equal_approx(inside, 1.0) and is_equal_approx(outside, 0.0)


func test_ocean_node_fades_buoyancy_far_field() -> bool:
	var ocean := Ocean.new()
	ocean.size_m = SIZE
	ocean.resolution = 32
	ocean.fine_extent_m = FINE_HALF
	ocean.far_cell_m = FAR_CELL
	ocean.fade_band_m = 250.0
	ocean.amplitude_scale = 0.75
	ocean.position = Vector3(0.0, -0.18, 0.0)
	ocean._ready()
	# Step the clock so waves are live (matches _process accumulation).
	ocean._time = 3.7
	# Well inside the fade start: full authored amplitude.
	var near := ocean.wave_height_at(Vector3(40.0, 0.0, -25.0))
	var expected_near := -0.18 + OceanMath.wave_height_at(Vector2(40.0, -25.0), 3.7, 0.75)
	# Far beyond the fine square: dead flat at the resting level.
	var far := ocean.wave_height_at(Vector3(5000.0, 0.0, 5000.0))
	var ok := absf(near - expected_near) < 0.0001 and is_equal_approx(far, -0.18)
	ocean.free()
	return ok


func test_ocean_node_uniform_plane_keeps_full_waves() -> bool:
	var ocean := Ocean.new()
	ocean.size_m = 1400.0
	ocean.resolution = 32
	ocean.fine_extent_m = 0.0
	ocean._ready()
	ocean._time = 2.0
	var h := ocean.wave_height_at(Vector3(5000.0, 0.0, 5000.0))
	var expected := OceanMath.wave_height_at(Vector2(5000.0, 5000.0), 2.0, 1.0)
	ocean.free()
	return absf(h - expected) < 0.0001
