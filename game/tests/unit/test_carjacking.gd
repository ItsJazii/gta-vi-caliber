extends RefCounted
## Unit tests for Carjacking (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).

# --- can_reach -------------------------------------------------------------


func test_can_reach_within_radius() -> bool:
	# 1.5 m away, 2.0 m reach → grabbable.
	return Carjacking.can_reach(Vector3(1.5, 0.0, 0.0), Vector3.ZERO, 2.0)


func test_can_reach_ignores_height() -> bool:
	# Same flat distance (1.5), player 5 m above on a ramp — still reachable.
	return Carjacking.can_reach(Vector3(1.5, 5.0, 0.0), Vector3.ZERO, 2.0)


func test_cannot_reach_beyond_radius() -> bool:
	# 3.0 m away, 2.0 m reach → too far.
	return not Carjacking.can_reach(Vector3(3.0, 0.0, 0.0), Vector3.ZERO, 2.0)


func test_zero_radius_never_reaches() -> bool:
	return not Carjacking.can_reach(Vector3.ZERO, Vector3.ZERO, 0.0)


# --- door_side -------------------------------------------------------------


func test_door_side_driver_left() -> bool:
	# Car faces +Z; right = +X, so a player at -X is on the left (driver) side.
	return Carjacking.door_side(Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0)) == -1


func test_door_side_passenger_right() -> bool:
	# Car faces +Z; player at +X is on the right (passenger) side.
	return Carjacking.door_side(Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0)) == 1


func test_door_side_dead_centre_is_zero() -> bool:
	# Player directly ahead — no lateral offset.
	return Carjacking.door_side(Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 4.0)) == 0


func test_door_side_no_forward_is_zero() -> bool:
	return Carjacking.door_side(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.0, 0.0)) == 0


# --- crime / heat ----------------------------------------------------------


func test_occupied_is_crime() -> bool:
	return Carjacking.is_occupied_crime(true) and not Carjacking.is_occupied_crime(false)


func test_heat_occupied_draws_base() -> bool:
	return is_equal_approx(Carjacking.heat_for_jack(true, 2.5), 2.5)


func test_heat_empty_draws_zero() -> bool:
	return is_equal_approx(Carjacking.heat_for_jack(false, 2.5), 0.0)


func test_heat_negative_base_floored() -> bool:
	return is_equal_approx(Carjacking.heat_for_jack(true, -4.0), 0.0)


func test_resist_modifier_range() -> bool:
	return (
		is_equal_approx(Carjacking.resist_modifier(0.0), 1.0)
		and is_equal_approx(Carjacking.resist_modifier(1.0), 2.0)
		and is_equal_approx(Carjacking.resist_modifier(2.0), 2.0)
	)


func test_resist_modifier_eases_in() -> bool:
	# Quadratic ease-in (1 + t^2): a half-toughness driver lengthens the struggle by
	# only 25% (1.25), not the linear 50% — most peds stay near base time, and only a
	# genuinely tough driver ramps toward 2x.
	return (
		is_equal_approx(Carjacking.resist_modifier(0.5), 1.25)
		and is_equal_approx(Carjacking.resist_modifier(0.25), 1.0625)
	)


func test_default_duration_is_snappy() -> bool:
	# The no-arg jack (limp civilian) wrestles out in the snappy 0.8s base.
	var j := Carjacking.new()
	return is_equal_approx(j.jack_duration, 0.8)


# --- struggle timer --------------------------------------------------------


func test_starts_idle() -> bool:
	var j := Carjacking.new(1.0)
	return is_equal_approx(j.progress(), 0.0) and not j.is_complete()


func test_tick_before_begin_does_nothing() -> bool:
	var j := Carjacking.new(1.0)
	j.tick(2.0)
	return is_equal_approx(j.progress(), 0.0) and not j.is_complete()


func test_not_complete_until_duration_elapses() -> bool:
	var j := Carjacking.new(1.0)
	j.begin()
	j.tick(0.4)
	j.tick(0.4)
	# 0.8 s of a 1.0 s struggle → still wrestling.
	return is_equal_approx(j.progress(), 0.8) and not j.is_complete()


func test_completes_when_duration_reached() -> bool:
	var j := Carjacking.new(1.0)
	j.begin()
	j.tick(0.6)
	j.tick(0.6)
	# 1.2 s ≥ 1.0 s → driver out, progress clamps to 1.0.
	return j.is_complete() and is_equal_approx(j.progress(), 1.0)


func test_complete_flips_once() -> bool:
	var j := Carjacking.new(1.0)
	j.begin()
	j.tick(1.0)
	var first := j.is_complete()
	j.tick(5.0)
	# Extra ticks after completion are inert and progress stays clamped.
	return first and j.is_complete() and is_equal_approx(j.progress(), 1.0)


func test_negative_delta_ignored() -> bool:
	var j := Carjacking.new(1.0)
	j.begin()
	j.tick(0.5)
	j.tick(-0.5)
	return is_equal_approx(j.progress(), 0.5) and not j.is_complete()


func test_cancel_aborts_and_stays_incomplete() -> bool:
	var j := Carjacking.new(1.0)
	j.begin()
	j.tick(0.5)
	j.cancel()
	# Walked away: not complete, and further ticks can't revive it.
	j.tick(2.0)
	return not j.is_complete() and is_equal_approx(j.progress(), 0.0)


func test_begin_rearms_after_complete() -> bool:
	var j := Carjacking.new(1.0)
	j.begin()
	j.tick(1.0)
	var done := j.is_complete()
	j.begin()
	# Re-armed: completion cleared, clock back to zero.
	return done and not j.is_complete() and is_equal_approx(j.progress(), 0.0)


func test_reset_clears_state() -> bool:
	var j := Carjacking.new(1.0)
	j.begin()
	j.tick(0.7)
	j.reset()
	j.tick(2.0)
	return not j.is_complete() and is_equal_approx(j.progress(), 0.0)


func test_resist_modifier_lengthens_struggle() -> bool:
	# A max-toughness driver doubles a 1.0 s base to 2.0 s.
	var j := Carjacking.new(1.0 * Carjacking.resist_modifier(1.0))
	j.begin()
	j.tick(1.0)
	# Halfway through the doubled struggle — not out yet.
	return not j.is_complete() and is_equal_approx(j.progress(), 0.5)
