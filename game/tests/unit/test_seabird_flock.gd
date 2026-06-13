extends RefCounted
## Functional guards for SeabirdFlock — the ambient gull flock. Motion is pure
## time math, so populate()/_apply run headless. Guards the flock is populated,
## stays in its altitude band, drifts over time, and flaps its wings (a freeze
## or empty flock would quietly kill the only moving life in the sky).


func test_populates_requested_count() -> bool:
	var flock := SeabirdFlock.new()
	flock.count = 14
	flock.populate()
	var made := flock.get_child_count()
	flock.free()
	return made == 14


func test_birds_stay_in_altitude_band() -> bool:
	var flock := SeabirdFlock.new()
	flock.count = 12
	flock.altitude_min = 45.0
	flock.altitude_max = 130.0
	flock.populate()
	flock._apply(3.0)
	var ok := true
	for bird in flock.get_children():
		var y: float = (bird as Node3D).position.y
		# alt band ± the vertical bob amplitude (4 m).
		if y < 45.0 - 5.0 or y > 130.0 + 5.0:
			ok = false
	flock.free()
	return ok


func test_birds_move_over_time() -> bool:
	var flock := SeabirdFlock.new()
	flock.count = 8
	flock.populate()
	flock._apply(0.0)
	var before: Array[Vector3] = []
	for bird in flock.get_children():
		before.append((bird as Node3D).position)
	flock._apply(5.0)
	var moved := false
	var i := 0
	for bird in flock.get_children():
		if (bird as Node3D).position.distance_to(before[i]) > 1.0:
			moved = true
		i += 1
	flock.free()
	return moved


func test_wings_flap() -> bool:
	var flock := SeabirdFlock.new()
	flock.count = 4
	flock.flap_speed = 6.0
	flock.populate()
	var wing := flock.get_child(0).get_node("L") as Node3D
	flock._apply(0.0)
	var a := wing.rotation.z
	# Quarter flap period later the wing angle must have changed.
	flock._apply(PI / (2.0 * 6.0))
	var b := wing.rotation.z
	flock.free()
	return absf(a - b) > 0.05
