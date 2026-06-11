extends RefCounted
## Unit tests for MissionObjectives — the objective/state-machine gameplay rules.

const DEFS := [{"id": "a", "text": "Reach A"}, {"id": "b", "text": "Reach B"}]


func _mission() -> MissionObjectives:
	return MissionObjectives.new("Test", DEFS)


func test_starts_inactive_then_active() -> bool:
	var m := _mission()
	if m.state != MissionObjectives.State.INACTIVE:
		return false
	m.start()
	return m.is_active()


func test_cannot_complete_before_start() -> bool:
	return _mission().complete_objective("a") == false


func test_completing_all_objectives_completes_mission() -> bool:
	var m := _mission()
	m.start()
	m.complete_objective("a")
	if m.is_complete():
		return false  # not yet — one objective left
	m.complete_objective("b")
	return m.is_complete()


func test_progress_counts() -> bool:
	var m := _mission()
	m.start()
	m.complete_objective("a")
	return m.progress() == Vector2i(1, 2)


func test_unknown_objective_is_noop() -> bool:
	var m := _mission()
	m.start()
	return m.complete_objective("zzz") == false


func test_double_complete_is_noop() -> bool:
	var m := _mission()
	m.start()
	m.complete_objective("a")
	return m.complete_objective("a") == false


func test_fail_blocks_further_progress() -> bool:
	var m := _mission()
	m.start()
	m.fail()
	return m.state == MissionObjectives.State.FAILED and m.complete_objective("a") == false
