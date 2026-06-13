extends RefCounted
## Functional guards for LifeguardTowers — the pastel beach stands. Pure
## construction, runs headless via populate(). Guards the row is built, spread
## along the shore, each stand is a full structure, and populate is idempotent.


func test_builds_requested_count() -> bool:
	var towers := LifeguardTowers.new()
	towers.count = 6
	var n := towers.populate()
	var made := towers.get_child_count()
	towers.free()
	return n == 6 and made == 6


func test_each_stand_is_a_full_structure() -> bool:
	var towers := LifeguardTowers.new()
	towers.populate()
	var ok := true
	for tower in towers.get_children():
		# 4 legs + deck + back + 2 sides + rail + 2 roof slabs + pole + flag +
		# ladder = 13 parts; guard the stand isn't a stub.
		if (tower as Node3D).get_child_count() < 12:
			ok = false
	towers.free()
	return ok


func test_stands_spread_along_beach() -> bool:
	var towers := LifeguardTowers.new()
	towers.count = 8
	towers.z_start = -1500.0
	towers.z_end = 1500.0
	towers.populate()
	var min_z := INF
	var max_z := -INF
	for tower in towers.get_children():
		var z: float = (tower as Node3D).position.z
		min_z = minf(min_z, z)
		max_z = maxf(max_z, z)
	towers.free()
	return max_z - min_z > 1500.0


func test_populate_is_idempotent() -> bool:
	var towers := LifeguardTowers.new()
	var first := towers.populate()
	var second := towers.populate()
	var made := towers.get_child_count()
	towers.free()
	return first == second and made == first
