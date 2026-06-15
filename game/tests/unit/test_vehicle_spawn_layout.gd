extends RefCounted


func test_starter_layout_places_two_vehicles() -> bool:
	return VehicleSpawnLayout.starter_transforms(Vector3.ZERO, 0.0).size() == 2


func test_starter_layout_parks_at_the_kerb_on_opposite_sides() -> bool:
	# Default 12 m road → kerb 4.6 m off centre (6 − 1.4). The cars sit at the
	# kerbs ahead of the spawn, facing down the street — clear of the travel lanes.
	var transforms := VehicleSpawnLayout.starter_transforms(Vector3(10.0, 0.9, 20.0), 0.0)
	return (
		transforms[0].origin.is_equal_approx(Vector3(14.6, 0.9, 12.0))
		and transforms[1].origin.is_equal_approx(Vector3(5.4, 0.9, 5.0))
	)


func test_starter_layout_rotates_with_street() -> bool:
	var transforms := VehicleSpawnLayout.starter_transforms(Vector3.ZERO, PI * 0.5)
	return (
		transforms[0].origin.is_equal_approx(Vector3(-8.0, 0.0, -4.6))
		and transforms[0].basis.is_equal_approx(Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)))
	)


func test_kerb_offset_widens_with_the_road() -> bool:
	# Wider carriageway → park further out (road_width / 2 − inset).
	return (
		is_equal_approx(VehicleSpawnLayout.kerb_offset(12.0), 4.6)
		and is_equal_approx(VehicleSpawnLayout.kerb_offset(20.0), 8.6)
	)


func test_kerb_offset_has_a_floor_on_narrow_roads() -> bool:
	# Even a sliver of a road parks the car at least MIN_CURB_OFFSET off centre.
	return is_equal_approx(VehicleSpawnLayout.kerb_offset(2.0), 1.6)
