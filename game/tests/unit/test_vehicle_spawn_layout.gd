extends RefCounted


func test_starter_layout_places_two_vehicles() -> bool:
	return VehicleSpawnLayout.starter_transforms(Vector3.ZERO, 0.0).size() == 2


func test_starter_layout_places_vehicles_ahead_on_opposite_sides() -> bool:
	var transforms := VehicleSpawnLayout.starter_transforms(Vector3(10.0, 0.9, 20.0), 0.0)
	return (
		transforms[0].origin.is_equal_approx(Vector3(13.0, 0.9, 12.0))
		and transforms[1].origin.is_equal_approx(Vector3(7.0, 0.9, 5.0))
	)


func test_starter_layout_rotates_with_street() -> bool:
	var transforms := VehicleSpawnLayout.starter_transforms(Vector3.ZERO, PI * 0.5)
	return (
		transforms[0].origin.is_equal_approx(Vector3(-8.0, 0.0, -3.0))
		and transforms[0].basis.is_equal_approx(Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)))
	)
