extends RefCounted
## Unit tests for MissionObjectiveDriver.evaluate (see tests/run_tests.gd for
## the runner contract: test_* methods return true to pass) plus the
## MissionController.current_objective_id accessor the driver pumps from. The
## evaluate step is pure; the controller is exercised out of tree (it only
## touches the SceneTree in _process/_local_waypoints, which aren't called).

const REACH := {"kind": "reach", "radius": 6.0}
const HOLD := {"kind": "hold", "radius": 8.0, "duration": 3.0}


func test_reach_satisfied_inside_radius() -> bool:
	var v := MissionObjectiveDriver.evaluate(REACH, Vector3(2, 0, 1), Vector3(0, 0, 0), 0.0, 0.016)
	return v["satisfied"] and is_equal_approx(float(v["held"]), 0.0)


func test_reach_not_satisfied_outside_radius() -> bool:
	var v := MissionObjectiveDriver.evaluate(REACH, Vector3(20, 0, 0), Vector3(0, 0, 0), 0.0, 0.016)
	return not v["satisfied"]


func test_hold_accumulates_while_inside() -> bool:
	var v := MissionObjectiveDriver.evaluate(HOLD, Vector3(1, 0, 0), Vector3.ZERO, 1.0, 0.5)
	return not v["satisfied"] and is_equal_approx(float(v["held"]), 1.5)


func test_hold_completes_at_duration() -> bool:
	var v := MissionObjectiveDriver.evaluate(HOLD, Vector3(1, 0, 0), Vector3.ZERO, 2.9, 0.2)
	return v["satisfied"] and float(v["held"]) >= 3.0


func test_hold_resets_when_player_leaves() -> bool:
	var v := MissionObjectiveDriver.evaluate(HOLD, Vector3(50, 0, 0), Vector3.ZERO, 2.9, 0.2)
	return not v["satisfied"] and is_equal_approx(float(v["held"]), 0.0)


func test_unknown_kind_degrades_to_reach() -> bool:
	var odd := {"kind": "dance_off", "radius": 5.0}
	var v := MissionObjectiveDriver.evaluate(odd, Vector3(1, 0, 1), Vector3.ZERO, 0.0, 0.016)
	return v["satisfied"]


func test_empty_def_uses_defaults() -> bool:
	# Default kind "reach", default radius 6: 4 m away completes, 9 m doesn't.
	var near := MissionObjectiveDriver.evaluate({}, Vector3(4, 0, 0), Vector3.ZERO, 0.0, 0.016)
	var far := MissionObjectiveDriver.evaluate({}, Vector3(9, 0, 0), Vector3.ZERO, 0.0, 0.016)
	return near["satisfied"] and not far["satisfied"]


func test_controller_reports_active_objective_id() -> bool:
	var ctl := MissionController.new()
	ctl.auto_start = false
	ctl.objective_defs = [{"id": "a", "text": "A"}, {"id": "b", "text": "B"}]
	ctl.begin()
	var first := ctl.current_objective_id() == "a"
	ctl.complete("a")
	var second := ctl.current_objective_id() == "b"
	ctl.complete("b")
	var done := ctl.current_objective_id() == "" and ctl.is_complete()
	ctl.free()
	return first and second and done
