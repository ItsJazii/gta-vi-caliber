extends RefCounted
## Unit tests for SideJob (see tests/run_tests.gd for the runner contract:
## zero-arg test_* methods return true to pass). Deterministic, no asserts.

# --- fare -------------------------------------------------------------------


func test_fare_scales_with_distance() -> bool:
	# 100 base + 200m * 1.5 = 100 + 300 = 400.
	return SideJob.fare(200.0, 100, 1.5) == 400


func test_fare_floors_at_base_with_zero_distance() -> bool:
	return SideJob.fare(0.0, 50, 1.5) == 50


func test_fare_clamps_negative_distance() -> bool:
	# Negative distance treated as 0 -> just the base.
	return SideJob.fare(-500.0, 75, 2.0) == 75


func test_fare_never_negative() -> bool:
	return SideJob.fare(-10.0, -10, -1.0) == 0


# --- vigilante --------------------------------------------------------------


func test_vigilante_reward_by_targets() -> bool:
	# 200 base + 3 targets * 100 = 500.
	return SideJob.vigilante_reward(3, 200, 100) == 500


func test_vigilante_zero_targets_is_base() -> bool:
	return SideJob.vigilante_reward(0, 200, 100) == 200


func test_vigilante_negative_targets_guarded() -> bool:
	return SideJob.vigilante_reward(-4, 150, 100) == 150


# --- time_bonus -------------------------------------------------------------


func test_time_bonus_positive_under_par() -> bool:
	return SideJob.time_bonus(20.0, 30.0, 500) == 500


func test_time_bonus_full_at_exactly_par() -> bool:
	return SideJob.time_bonus(30.0, 30.0, 500) == 500


func test_time_bonus_linear_decay_over_par() -> bool:
	# 1.5x par -> 50% of the bonus (was wrongly 0 before the decay band was added).
	return SideJob.time_bonus(45.0, 30.0, 500) == 250


func test_time_bonus_clamped_non_negative() -> bool:
	# Negative bonus and a degenerate par both yield 0, never negative.
	return SideJob.time_bonus(10.0, 30.0, -100) == 0 and SideJob.time_bonus(10.0, 0.0, 500) == 0


# --- payout -----------------------------------------------------------------


func test_payout_taxi_combines_fare_and_bonus() -> bool:
	# Taxi: 100 base + 100m*1.5 = 250 fare, + full 100 time bonus (under par) = 350.
	var job := SideJob.make_job(SideJob.Kind.TAXI, Vector3.ZERO, Vector3(100, 0, 0), 100)
	return SideJob.payout(job, 100.0, 10.0, 30.0) == 350


func test_payout_vigilante_uses_target_count() -> bool:
	# Vigilante: distance arg carries kill count (2). 300 base + 2*150 = 600 core,
	# + 300 time bonus (under par) = 900.
	var job := SideJob.make_job(SideJob.Kind.VIGILANTE, Vector3.ZERO, Vector3(5, 0, 0), 300)
	return SideJob.payout(job, 2.0, 5.0, 20.0) == 900


func test_payout_over_par_drops_bonus() -> bool:
	# Same taxi trip but over par -> only the 250 fare, no bonus.
	var job := SideJob.make_job(SideJob.Kind.TAXI, Vector3.ZERO, Vector3(100, 0, 0), 100)
	return SideJob.payout(job, 100.0, 99.0, 30.0) == 250


func test_payout_never_negative() -> bool:
	var job := SideJob.make_job(SideJob.Kind.DELIVERY, Vector3.ZERO, Vector3.ZERO, 0)
	return SideJob.payout(job, -50.0, 100.0, 30.0) == 0


# --- chain_multiplier -------------------------------------------------------


func test_chain_multiplier_base_is_one_and_floored() -> bool:
	# First job (0 streak) is exactly 1.0; a negative streak never drops below 1.0.
	return is_equal_approx(SideJob.chain_multiplier(0), 1.0) and SideJob.chain_multiplier(-5) >= 1.0


func test_chain_multiplier_grows_with_streak() -> bool:
	# 3 in a row -> 1.0 + 3*0.1 = 1.3.
	return is_equal_approx(SideJob.chain_multiplier(3), 1.3)


func test_chain_multiplier_caps() -> bool:
	return is_equal_approx(SideJob.chain_multiplier(50), 2.0)


# --- stateful active-job lifecycle ------------------------------------------


func test_starts_with_no_active_job() -> bool:
	var s := SideJob.new()
	return not s.has_active() and s.completed_count() == 0 and s.active_kind() == -1


func test_lifecycle_start_pickup_dropoff_complete() -> bool:
	var s := SideJob.new()
	var job := SideJob.make_job(SideJob.Kind.TAXI, Vector3.ZERO, Vector3(10, 0, 0), 100)
	s.start(job)
	var at_pickup := s.has_active() and s.stage() == SideJob.Stage.PICKUP and not s.is_pickup_done()
	s.advance_stage()
	var at_dropoff := s.stage() == SideJob.Stage.DROPOFF and s.is_pickup_done()
	s.complete()
	var done := not s.has_active() and s.completed_count() == 1
	return at_pickup and at_dropoff and done


func test_active_kind_reports_current_job() -> bool:
	var s := SideJob.new()
	s.start(SideJob.make_job(SideJob.Kind.TOWING, Vector3.ZERO, Vector3.ONE, 80))
	return s.active_kind() == SideJob.Kind.TOWING


func test_cancel_aborts_without_crediting() -> bool:
	var s := SideJob.new()
	s.start(SideJob.make_job(SideJob.Kind.DELIVERY, Vector3.ZERO, Vector3.ONE, 50))
	s.cancel()
	return not s.has_active() and s.completed_count() == 0


func test_completed_count_increments_across_jobs() -> bool:
	var s := SideJob.new()
	for _i in 3:
		s.start(SideJob.make_job(SideJob.Kind.TAXI, Vector3.ZERO, Vector3.ONE, 100))
		s.advance_stage()
		s.complete()
	return s.completed_count() == 3


func test_no_active_advance_and_complete_are_noops() -> bool:
	var s := SideJob.new()
	s.advance_stage()
	s.complete()
	s.cancel()
	return not s.has_active() and s.completed_count() == 0 and s.stage() == SideJob.Stage.DONE


func test_kind_name_roundtrip() -> bool:
	return (
		SideJob.kind_name(SideJob.Kind.TAXI) == "taxi"
		and SideJob.kind_name(SideJob.Kind.VIGILANTE) == "vigilante"
		and SideJob.kind_name(999) == ""
	)
