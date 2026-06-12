extends RefCounted
## Unit tests for HelicopterPursuit (see tests/run_tests.gd for the runner
## contract: test_* methods return true to pass). Pure air-support math — no scene.

const CENTER := Vector3(12, 0, -5)

# --- should_deploy --------------------------------------------------------


func test_no_chopper_below_three_stars() -> bool:
	# PoliceResponse.HELICOPTER_STARS == 3.
	return not HelicopterPursuit.should_deploy(2)


func test_chopper_at_three_plus_stars() -> bool:
	return HelicopterPursuit.should_deploy(3) and HelicopterPursuit.should_deploy(5)


# --- orbit_point ----------------------------------------------------------


func test_orbit_sits_on_radius() -> bool:
	var p := HelicopterPursuit.orbit_point(CENTER, 0.0, 28.0, 32.0, 1.0)
	var planar := Vector2(p.x - CENTER.x, p.z - CENTER.z)
	return is_equal_approx(planar.length(), 28.0)


func test_orbit_holds_altitude() -> bool:
	var p := HelicopterPursuit.orbit_point(CENTER, 1.3, 28.0, 32.0, 0.7)
	return is_equal_approx(p.y, CENTER.y + 32.0)


func test_orbit_advances_with_time() -> bool:
	var a := HelicopterPursuit.orbit_point(CENTER, 0.0, 28.0, 32.0, 1.0)
	var b := HelicopterPursuit.orbit_point(CENTER, 1.0, 28.0, 32.0, 1.0)
	return a.distance_to(b) > 0.1


func test_orbit_periodic() -> bool:
	# A full TAU/angular_speed later returns to the same point.
	var a := HelicopterPursuit.orbit_point(CENTER, 0.0, 28.0, 32.0, 1.0)
	var b := HelicopterPursuit.orbit_point(CENTER, TAU, 28.0, 32.0, 1.0)
	return a.distance_to(b) < 0.001


# --- cone / spotlight radius ---------------------------------------------


func test_cone_half_radians_converts_and_clamps() -> bool:
	if not is_equal_approx(HelicopterPursuit.cone_half_radians(22.0), deg_to_rad(22.0)):
		return false
	# Over-90 is clamped below a right angle.
	return HelicopterPursuit.cone_half_radians(200.0) < deg_to_rad(90.0)


func test_spotlight_radius_grows_with_altitude() -> bool:
	var half := HelicopterPursuit.cone_half_radians(22.0)
	var low := HelicopterPursuit.spotlight_ground_radius(20.0, half)
	var high := HelicopterPursuit.spotlight_ground_radius(40.0, half)
	return high > low and low > 0.0


func test_spotlight_radius_matches_trig() -> bool:
	var half := HelicopterPursuit.cone_half_radians(22.0)
	return is_equal_approx(HelicopterPursuit.spotlight_ground_radius(32.0, half), 32.0 * tan(half))


# --- target_lit -----------------------------------------------------------


func test_target_lit_inside_footprint() -> bool:
	return HelicopterPursuit.target_lit(Vector3(0, 0, 0), Vector3(3, 0, 2), 10.0)


func test_target_dark_outside_footprint() -> bool:
	return not HelicopterPursuit.target_lit(Vector3(0, 0, 0), Vector3(20, 0, 0), 10.0)


func test_target_lit_ignores_height() -> bool:
	# Target 50m below but planar-inside the circle is still lit.
	return HelicopterPursuit.target_lit(Vector3(0, 30, 0), Vector3(2, -20, 1), 10.0)
