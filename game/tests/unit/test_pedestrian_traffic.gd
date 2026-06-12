extends RefCounted
## Unit tests for PedestrianTraffic (see tests/run_tests.gd for the runner
## contract: test_* methods return true to pass). Scenarios are laid out on the
## XZ plane: a pedestrian near the origin, cars driving along +X or +Z.

# --- is_closing --------------------------------------------------------------


func test_closing_when_car_drives_at_pedestrian() -> bool:
	# Car to the pedestrian's -X side driving +X toward them.
	return PedestrianTraffic.is_closing(
		Vector3.ZERO, Vector3.ZERO, Vector3(-10, 0, 0), Vector3(8, 0, 0)
	)


func test_not_closing_when_car_drives_away() -> bool:
	# Car ahead on +X driving further +X.
	var closing := PedestrianTraffic.is_closing(
		Vector3.ZERO, Vector3.ZERO, Vector3(10, 0, 0), Vector3(8, 0, 0)
	)
	return not closing


# --- time_to_closest_approach ------------------------------------------------


func test_ttca_head_on_is_positive() -> bool:
	# Car 16m away closing at 8 m/s straight along X → ~2s to reach the ped line.
	var t := PedestrianTraffic.time_to_closest_approach(
		Vector3.ZERO, Vector3.ZERO, Vector3(-16, 0, 0), Vector3(8, 0, 0)
	)
	return is_equal_approx(t, 2.0)


func test_ttca_zero_when_receding() -> bool:
	var t := PedestrianTraffic.time_to_closest_approach(
		Vector3.ZERO, Vector3.ZERO, Vector3(4, 0, 0), Vector3(8, 0, 0)
	)
	return is_equal_approx(t, 0.0)


func test_ttca_zero_when_parallel_same_velocity() -> bool:
	# No relative motion → degenerate, returns 0 not NaN.
	var t := PedestrianTraffic.time_to_closest_approach(
		Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 5), Vector3(1, 0, 0)
	)
	return is_equal_approx(t, 0.0)


# --- closest_approach_distance -----------------------------------------------


func test_closest_distance_for_passing_car() -> bool:
	# Car passes on a lane 3m in +Z, driving along X → nearest approach ≈ 3m.
	var d := PedestrianTraffic.closest_approach_distance(
		Vector3.ZERO, Vector3.ZERO, Vector3(-20, 0, 3), Vector3(10, 0, 0)
	)
	return is_equal_approx(d, 3.0)


func test_closest_distance_zero_for_direct_hit() -> bool:
	var d := PedestrianTraffic.closest_approach_distance(
		Vector3.ZERO, Vector3.ZERO, Vector3(-20, 0, 0), Vector3(10, 0, 0)
	)
	return d < 0.001


# --- car_threat --------------------------------------------------------------


func test_threat_high_for_imminent_direct_hit() -> bool:
	# 8m out, 8 m/s, dead-on → close in time and distance → strong threat.
	var threat := PedestrianTraffic.car_threat(
		Vector3.ZERO, Vector3.ZERO, Vector3(-8, 0, 0), Vector3(8, 0, 0), 4.0, 3.0
	)
	return threat > 0.6


func test_threat_zero_for_receding_car() -> bool:
	var threat := PedestrianTraffic.car_threat(
		Vector3.ZERO, Vector3.ZERO, Vector3(4, 0, 0), Vector3(8, 0, 0), 4.0, 3.0
	)
	return is_equal_approx(threat, 0.0)


func test_threat_zero_when_miss_exceeds_radius() -> bool:
	# Car passes 6m away but react_radius is only 4m → ignored.
	var threat := PedestrianTraffic.car_threat(
		Vector3.ZERO, Vector3.ZERO, Vector3(-20, 0, 6), Vector3(10, 0, 0), 4.0, 5.0
	)
	return is_equal_approx(threat, 0.0)


func test_threat_zero_beyond_time_horizon() -> bool:
	# Direct hit but 10s away, horizon 3s → not yet a concern.
	var threat := PedestrianTraffic.car_threat(
		Vector3.ZERO, Vector3.ZERO, Vector3(-100, 0, 0), Vector3(10, 0, 0), 4.0, 3.0
	)
	return is_equal_approx(threat, 0.0)


func test_threat_grows_as_car_nears() -> bool:
	var far := PedestrianTraffic.car_threat(
		Vector3.ZERO, Vector3.ZERO, Vector3(-20, 0, 0), Vector3(8, 0, 0), 5.0, 4.0
	)
	var near := PedestrianTraffic.car_threat(
		Vector3.ZERO, Vector3.ZERO, Vector3(-8, 0, 0), Vector3(8, 0, 0), 5.0, 4.0
	)
	return near > far


# --- nearest_threat ----------------------------------------------------------


func test_nearest_threat_picks_most_dangerous() -> bool:
	var cars := [
		{"pos": Vector3(-40, 0, 0), "vel": Vector3(8, 0, 0)},  # far, low threat
		{"pos": Vector3(-8, 0, 0), "vel": Vector3(10, 0, 0)},  # close, high threat
	]
	var best := PedestrianTraffic.nearest_threat(Vector3.ZERO, Vector3.ZERO, cars, 5.0, 4.0)
	return best["index"] == 1 and best["threat"] > 0.0


func test_nearest_threat_empty_when_no_cars() -> bool:
	var best := PedestrianTraffic.nearest_threat(Vector3.ZERO, Vector3.ZERO, [], 5.0, 4.0)
	return best["index"] == -1 and is_equal_approx(best["threat"], 0.0)


func test_nearest_threat_ignores_receding_traffic() -> bool:
	var cars := [{"pos": Vector3(4, 0, 0), "vel": Vector3(8, 0, 0)}]
	var best := PedestrianTraffic.nearest_threat(Vector3.ZERO, Vector3.ZERO, cars, 5.0, 4.0)
	return best["index"] == -1


# --- dodge_velocity ----------------------------------------------------------


func test_dodge_is_perpendicular_to_car_heading() -> bool:
	# Car heading +X, ped on +Z side → dodge should be along ±Z, zero X.
	var dodge := PedestrianTraffic.dodge_velocity(
		Vector3(0, 0, 2), Vector3(-10, 0, 0), Vector3(10, 0, 0), 3.0
	)
	return absf(dodge.x) < 0.001 and dodge.z > 0.0 and is_equal_approx(dodge.length(), 3.0)


func test_dodge_picks_pedestrians_side() -> bool:
	# Same car, ped on -Z side → dodge flips to -Z.
	var dodge := PedestrianTraffic.dodge_velocity(
		Vector3(0, 0, -2), Vector3(-10, 0, 0), Vector3(10, 0, 0), 3.0
	)
	return dodge.z < 0.0


func test_dodge_pushes_away_from_stopped_car() -> bool:
	# Stopped car at -X, ped at origin → push straight +X away from it.
	var dodge := PedestrianTraffic.dodge_velocity(
		Vector3.ZERO, Vector3(-2, 0, 0), Vector3.ZERO, 3.0
	)
	return dodge.x > 0.0 and is_equal_approx(dodge.length(), 3.0)


# --- safe_to_cross -----------------------------------------------------------


func test_safe_to_cross_clear_road() -> bool:
	return PedestrianTraffic.safe_to_cross(Vector3.ZERO, [], 3.0, 3.0)


func test_unsafe_to_cross_with_incoming_car() -> bool:
	var cars := [{"pos": Vector3(-12, 0, 0), "vel": Vector3(10, 0, 0)}]
	return not PedestrianTraffic.safe_to_cross(Vector3.ZERO, cars, 3.0, 3.0)


func test_safe_to_cross_when_car_far_in_time() -> bool:
	# Car dead-on but 10s out, only need a 3s gap → safe to step.
	var cars := [{"pos": Vector3(-100, 0, 0), "vel": Vector3(10, 0, 0)}]
	return PedestrianTraffic.safe_to_cross(Vector3.ZERO, cars, 3.0, 3.0)


func test_safe_to_cross_when_car_on_far_lane() -> bool:
	# Car arrives soon but passes 8m away; danger radius 3m → safe.
	var cars := [{"pos": Vector3(-12, 0, 8), "vel": Vector3(10, 0, 0)}]
	return PedestrianTraffic.safe_to_cross(Vector3.ZERO, cars, 3.0, 3.0)
