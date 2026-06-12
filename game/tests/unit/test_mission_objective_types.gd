extends RefCounted
## Unit tests for MissionObjectiveTypes (see tests/run_tests.gd: test_* methods
## return true to pass). Deterministic, RNG-free.


func test_reach_inside_radius() -> bool:
	return MissionObjectiveTypes.reach_satisfied(Vector3(1, 0, 0), Vector3(3, 0, 0), 5.0)


func test_reach_outside_radius() -> bool:
	return not MissionObjectiveTypes.reach_satisfied(Vector3.ZERO, Vector3(0, 0, 10), 4.0)


func test_reach_negative_radius_guarded() -> bool:
	# A negative radius collapses to 0: only an exact hit counts.
	return (
		MissionObjectiveTypes.reach_satisfied(Vector3.ONE, Vector3.ONE, -2.0)
		and not MissionObjectiveTypes.reach_satisfied(Vector3.ZERO, Vector3(0, 1, 0), -2.0)
	)


func test_collect_progress_fraction() -> bool:
	return is_equal_approx(MissionObjectiveTypes.collect_progress(2, 8), 0.25)


func test_collect_progress_over_caps_at_one() -> bool:
	return is_equal_approx(MissionObjectiveTypes.collect_progress(12, 5), 1.0)


func test_collect_progress_negative_floored() -> bool:
	return is_equal_approx(MissionObjectiveTypes.collect_progress(-4, 5), 0.0)


func test_collect_zero_required_instant() -> bool:
	return (
		MissionObjectiveTypes.collect_satisfied(0, 0)
		and is_equal_approx(MissionObjectiveTypes.collect_progress(0, 0), 1.0)
	)


func test_collect_satisfied_at_and_over_required() -> bool:
	return (
		not MissionObjectiveTypes.collect_satisfied(2, 3)
		and MissionObjectiveTypes.collect_satisfied(3, 3)
		and MissionObjectiveTypes.collect_satisfied(9, 3)
	)


func test_eliminate_satisfied_only_at_zero() -> bool:
	return (
		not MissionObjectiveTypes.eliminate_satisfied(2)
		and MissionObjectiveTypes.eliminate_satisfied(0)
		and MissionObjectiveTypes.eliminate_satisfied(-3)
	)


func test_escort_failed_at_zero_health() -> bool:
	return (
		MissionObjectiveTypes.escort_failed(0.0)
		and MissionObjectiveTypes.escort_failed(-1.0)
		and not MissionObjectiveTypes.escort_failed(12.0)
	)


func test_escort_satisfied_at_destination() -> bool:
	return MissionObjectiveTypes.escort_satisfied(Vector3(9, 0, 1), Vector3(10, 0, 1), 2.0)


func test_escort_not_satisfied_far_from_destination() -> bool:
	return not MissionObjectiveTypes.escort_satisfied(Vector3.ZERO, Vector3(50, 0, 0), 2.0)


func test_survive_progress_ramps() -> bool:
	return is_equal_approx(MissionObjectiveTypes.survive_progress(15.0, 60.0), 0.25)


func test_survive_progress_caps_and_floors() -> bool:
	return (
		is_equal_approx(MissionObjectiveTypes.survive_progress(90.0, 60.0), 1.0)
		and is_equal_approx(MissionObjectiveTypes.survive_progress(-5.0, 60.0), 0.0)
	)


func test_survive_satisfied_at_duration() -> bool:
	return (
		not MissionObjectiveTypes.survive_satisfied(59.0, 60.0)
		and MissionObjectiveTypes.survive_satisfied(60.0, 60.0)
		and MissionObjectiveTypes.survive_satisfied(75.0, 60.0)
	)


func test_defend_failed_threshold() -> bool:
	return (
		MissionObjectiveTypes.defend_failed(0.0)
		and MissionObjectiveTypes.defend_failed(-10.0)
		and not MissionObjectiveTypes.defend_failed(0.5)
	)


func test_kind_name_round_trip() -> bool:
	return (
		MissionObjectiveTypes.kind_name(MissionObjectiveTypes.Kind.SURVIVE) == "survive"
		and MissionObjectiveTypes.kind_name(MissionObjectiveTypes.Kind.DEFEND) == "defend"
		and MissionObjectiveTypes.kind_name(999) == ""
	)


func test_counter_add_and_remaining() -> bool:
	var c := MissionObjectiveTypes.Counter.new(5)
	c.add(2)
	return c.count() == 2 and c.remaining() == 3 and not c.is_done()


func test_counter_done_and_over_cap() -> bool:
	var c := MissionObjectiveTypes.Counter.new(3)
	c.add(10)
	return (
		c.is_done()
		and c.remaining() == 0
		and c.count() == 10
		and is_equal_approx(c.progress(), 1.0)
	)


func test_counter_negative_delta_ignored() -> bool:
	var c := MissionObjectiveTypes.Counter.new(4)
	c.add(-7)
	c.add(0)
	return c.count() == 0 and is_equal_approx(c.progress(), 0.0)


func test_counter_progress_fraction() -> bool:
	var c := MissionObjectiveTypes.Counter.new(4)
	c.add(1)
	return is_equal_approx(c.progress(), 0.25)


func test_counter_zero_target_done_immediately() -> bool:
	var c := MissionObjectiveTypes.Counter.new(0)
	return c.is_done() and c.remaining() == 0 and is_equal_approx(c.progress(), 1.0)


func test_counter_reset_clears_count() -> bool:
	var c := MissionObjectiveTypes.Counter.new(5)
	c.add(4)
	c.reset()
	return c.count() == 0 and not c.is_done() and c.target() == 5
