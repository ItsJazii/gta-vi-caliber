extends RefCounted
## Unit tests for PoliceDispatch (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). Pure spawn-plan math — no scene, no node.

const CENTER := Vector3(10, 2, -4)

# --- desired_units --------------------------------------------------------


func test_desired_units_follows_heat() -> bool:
	# PoliceResponse.UNITS_PER_STAR == [0, 1, 2, 4, 6, 8].
	return PoliceDispatch.desired_units(0, 99) == 0 and PoliceDispatch.desired_units(5, 99) == 8


func test_desired_units_capped_by_budget() -> bool:
	return PoliceDispatch.desired_units(5, 3) == 3


# --- spawn_count ----------------------------------------------------------


func test_spawn_count_fills_deficit() -> bool:
	# 5 stars wants 8; 2 alive; wave cap 3 → spawn 3 (not the full 6).
	return PoliceDispatch.spawn_count(5, 2, 12, 3) == 3


func test_spawn_count_zero_when_satisfied() -> bool:
	return PoliceDispatch.spawn_count(2, 2, 12, 4) == 0


func test_spawn_count_never_negative() -> bool:
	# More alive than desired (heat just dropped) → spawn nothing, never negative.
	return PoliceDispatch.spawn_count(1, 6, 12, 4) == 0


func test_spawn_count_respects_budget() -> bool:
	# Wants 8 but budget 5, none alive, big wave cap → only 5.
	return PoliceDispatch.spawn_count(5, 0, 5, 99) == 5


# --- ring_angle -----------------------------------------------------------


func test_ring_angle_evenly_slices_without_jitter() -> bool:
	# 4 spawns, no jitter → 0, π/2, π, 3π/2.
	for i in range(0, 4):
		if not is_equal_approx(PoliceDispatch.ring_angle(i, 4, 0.5, 0.0), i * TAU / 4.0):
			return false
	return true


func test_ring_angle_jitter_stays_in_slice() -> bool:
	var slice := TAU / 6.0
	var base := 2 * slice
	# Extreme jitter samples land at ±half a slice from the base angle.
	var lo := PoliceDispatch.ring_angle(2, 6, 0.0, 1.0)
	var hi := PoliceDispatch.ring_angle(2, 6, 1.0, 1.0)
	return is_equal_approx(lo, base - slice * 0.5) and is_equal_approx(hi, base + slice * 0.5)


# --- ring_position --------------------------------------------------------


func test_ring_position_sits_on_radius() -> bool:
	var p := PoliceDispatch.ring_position(CENTER, 40.0, 0.0, 0.5, 0.0)
	var planar := Vector2(p.x - CENTER.x, p.z - CENTER.z)
	return is_equal_approx(planar.length(), 40.0)


func test_ring_position_keeps_center_height() -> bool:
	var p := PoliceDispatch.ring_position(CENTER, 40.0, 1.2, 0.7, 6.0)
	return is_equal_approx(p.y, CENTER.y)


func test_ring_position_radial_jitter_bounded() -> bool:
	# u_radius extremes shift distance by exactly ±radial_jitter.
	var near := PoliceDispatch.ring_position(CENTER, 40.0, 0.0, 0.0, 6.0)
	var far := PoliceDispatch.ring_position(CENTER, 40.0, 0.0, 1.0, 6.0)
	var dn := Vector2(near.x - CENTER.x, near.z - CENTER.z).length()
	var df := Vector2(far.x - CENTER.x, far.z - CENTER.z).length()
	return is_equal_approx(dn, 34.0) and is_equal_approx(df, 46.0)


# --- should_despawn -------------------------------------------------------


func test_despawn_when_no_longer_wanted() -> bool:
	# Heat cleared → recall even a unit standing right next to the player.
	return PoliceDispatch.should_despawn(0, 1.0, 160.0)


func test_keep_nearby_unit_while_wanted() -> bool:
	return not PoliceDispatch.should_despawn(3, 30.0, 160.0)


func test_despawn_unit_that_falls_too_far_behind() -> bool:
	return PoliceDispatch.should_despawn(3, 200.0, 160.0)
