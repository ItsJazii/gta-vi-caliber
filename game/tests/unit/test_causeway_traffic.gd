extends RefCounted
## Functional guards for CausewayTraffic — ambient cars on the bay bridges. Pure
## time-driven motion over CausewayNetwork, runs headless. Guards cars are built,
## ride the arched deck (within its height envelope), drive along over time, and
## that populate is idempotent.


func test_builds_cars_on_every_causeway() -> bool:
	var traffic := CausewayTraffic.new()
	traffic.cars_per_causeway = 5
	var n := traffic.populate()
	var lanes := CausewayNetwork.causeways().size()
	var made := traffic.get_child_count()
	traffic.free()
	# One car node per (causeway × cars_per_causeway); at least one causeway.
	return lanes > 0 and n == lanes * 5 and made == n


func test_cars_sit_on_the_arched_deck() -> bool:
	var traffic := CausewayTraffic.new()
	traffic.populate()
	traffic._apply(0.0)
	var ok := true
	for car in traffic.get_children():
		var y: float = (car as Node3D).position.y
		# DECK_BASE_Y (2.2) .. + max rise (~16) + clearance, with margin.
		if y < 2.0 or y > 22.0:
			ok = false
	traffic.free()
	return ok


func test_cars_drive_over_time() -> bool:
	var traffic := CausewayTraffic.new()
	traffic.populate()
	traffic._apply(0.0)
	var before: Array[Vector3] = []
	for car in traffic.get_children():
		before.append((car as Node3D).position)
	traffic._process(1.0)
	var moved := false
	var i := 0
	for car in traffic.get_children():
		if (car as Node3D).position.distance_to(before[i]) > 1.0:
			moved = true
		i += 1
	traffic.free()
	return moved


func test_populate_is_idempotent() -> bool:
	var traffic := CausewayTraffic.new()
	var first := traffic.populate()
	var second := traffic.populate()
	var made := traffic.get_child_count()
	traffic.free()
	return first == second and made == first
