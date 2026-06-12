extends RefCounted
## Functional guards for BayBoats — the ambient bay fleet. OceanMath is pure, so
## the build + drift are exercised headless via a real SceneTree (needed so the
## node's _ready/_process fire). Guards the fleet is populated, sits on the wave
## surface, and actually drifts (a regression that froze or emptied it would
## quietly return the bay to a dead plane).


func test_builds_requested_count() -> bool:
	var boats := BayBoats.new()
	boats.count = 12
	boats.populate()
	var made := boats.get_child_count()
	boats.free()
	return made == 12


func test_boats_sit_near_ocean_surface() -> bool:
	var boats := BayBoats.new()
	boats.count = 8
	boats.ocean_y = -0.18
	boats.amplitude_scale = 0.75
	boats.populate()
	# Every boat's y must be within the wave envelope of ocean_y (no boats
	# stranded in the air or sunk far below the surface).
	var envelope := OceanMath.max_height(0.75) + 0.5
	var ok := true
	for child in boats.get_children():
		if absf((child as Node3D).position.y - (-0.18)) > envelope:
			ok = false
	boats.free()
	return ok


func test_boats_drift_over_time() -> bool:
	var boats := BayBoats.new()
	boats.count = 6
	boats.drift_speed_min = 2.0
	boats.drift_speed_max = 4.0
	boats.populate()
	var before: Array[Vector3] = []
	for child in boats.get_children():
		before.append((child as Node3D).position)
	# Two sizable steps; at least one boat must have moved horizontally.
	boats._process(0.5)
	boats._process(0.5)
	var moved := false
	var i := 0
	for child in boats.get_children():
		var p: Vector3 = (child as Node3D).position
		if Vector2(p.x - before[i].x, p.z - before[i].z).length() > 0.1:
			moved = true
		i += 1
	boats.free()
	return moved


func test_boats_stay_in_bounds() -> bool:
	var boats := BayBoats.new()
	boats.count = 10
	boats.area_min = Vector2(100.0, 100.0)
	boats.area_max = Vector2(140.0, 140.0)
	boats.drift_speed_max = 50.0
	boats.drift_speed_min = 50.0
	boats.populate()
	# Drive many steps; wrapf must keep every boat inside the rectangle.
	for _s in 40:
		boats._process(0.2)
	var ok := true
	for child in boats.get_children():
		var p: Vector3 = (child as Node3D).position
		if p.x < 99.0 or p.x > 141.0 or p.z < 99.0 or p.z > 141.0:
			ok = false
	boats.free()
	return ok
