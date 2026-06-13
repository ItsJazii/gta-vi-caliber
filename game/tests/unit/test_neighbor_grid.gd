extends RefCounted
## Unit tests for NeighborGrid (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). The GDScript bucket fallback is forced
## (allow_native = false) so these run identically with or without the native
## worldcore module; the last test cross-checks native parity when it's built.


func _fallback(cell: float = 8.0) -> NeighborGrid:
	return NeighborGrid.new(cell, false)


func test_fallback_inserts_and_queries() -> bool:
	var g := _fallback()
	g.insert(1, Vector2(0, 0))
	g.insert(2, Vector2(3, 0))
	g.insert(3, Vector2(100, 100))
	g.insert(4, Vector2(8.5, 0))
	if g.size() != 4:
		return false
	var near := g.query_radius(Vector2(0, 0), 5.0)
	return 1 in near and 2 in near and not 3 in near and not 4 in near


func test_query_crosses_cell_borders() -> bool:
	var g := _fallback(8.0)
	g.insert(7, Vector2(7.9, 0.0))
	g.insert(8, Vector2(8.1, 0.0))
	var near := g.query_radius(Vector2(8.0, 0.0), 0.5)
	return 7 in near and 8 in near


func test_negative_coordinates_bucket_correctly() -> bool:
	var g := _fallback(8.0)
	g.insert(1, Vector2(-0.5, -0.5))
	g.insert(2, Vector2(-7.5, -7.5))
	g.insert(3, Vector2(-20.0, -20.0))
	var near := g.query_radius(Vector2(-4.0, -4.0), 6.0)
	return 1 in near and 2 in near and not 3 in near


func test_radius_boundary_inclusive() -> bool:
	var g := _fallback()
	g.insert(1, Vector2(5.0, 0.0))
	var near := g.query_radius(Vector2(0, 0), 5.0)
	return 1 in near


func test_query_includes_self_position() -> bool:
	var g := _fallback()
	g.insert(42, Vector2(3.0, 4.0))
	var near := g.query_radius(Vector2(3.0, 4.0), 1.0)
	return 42 in near


func test_clear_resets() -> bool:
	var g := _fallback()
	g.insert(1, Vector2.ZERO)
	g.clear()
	return g.size() == 0 and g.query_radius(Vector2.ZERO, 10.0).is_empty()


func test_zero_radius_finds_exact_point_only() -> bool:
	var g := _fallback()
	g.insert(1, Vector2(1.0, 1.0))
	g.insert(2, Vector2(1.5, 1.0))
	var near := g.query_radius(Vector2(1.0, 1.0), 0.0)
	return 1 in near and not 2 in near


func test_fallback_matches_brute_force() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var g := _fallback(6.0)
	var points: Array[Vector2] = []
	for i in 120:
		var p := Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		points.append(p)
		g.insert(i, p)
	for _q in 12:
		var at := Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		var radius := rng.randf_range(2.0, 25.0)
		var got := Array(g.query_radius(at, radius))
		got.sort()
		var want: Array = []
		for i in points.size():
			if points[i].distance_squared_to(at) <= radius * radius:
				want.append(i)
		if got != want:
			return false
	return true


func test_native_parity_when_module_built() -> bool:
	if not ClassDB.class_exists("SpatialHash"):
		print("SpatialHash native module absent — skipping parity")
		return true
	var native := NeighborGrid.new(6.0, true)
	if not native.is_native():
		return false
	var fallback := _fallback(6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 80:
		var p := Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		native.insert(i, p)
		fallback.insert(i, p)
	for _q in 8:
		var at := Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		var a := Array(native.query_radius(at, 12.0))
		var b := Array(fallback.query_radius(at, 12.0))
		a.sort()
		b.sort()
		if a != b:
			return false
	return true
