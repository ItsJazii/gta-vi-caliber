extends RefCounted
## Unit tests for MeleeCombat.best_target — the forgiving melee aim-assist that
## picks which body a punch connects with (see tests/run_tests.gd: test_* methods
## return true to pass). Pure geometry, no scene or physics.

## Attacker faces -Z (Godot forward); candidates are world positions.
const FWD := Vector3(0.0, 0.0, -1.0)
const REACH := 2.2
const MIN_FACING := 0.25


func test_hits_body_ahead() -> bool:
	var candidates := PackedVector3Array([Vector3(0.0, 0.0, -1.5)])
	return MeleeCombat.best_target(candidates, Vector3.ZERO, FWD, REACH, MIN_FACING) == 0


func test_ignores_body_behind() -> bool:
	# Directly behind the attacker: dot is -1, well under the facing floor.
	var candidates := PackedVector3Array([Vector3(0.0, 0.0, 1.5)])
	return (
		MeleeCombat.best_target(candidates, Vector3.ZERO, FWD, REACH, MIN_FACING)
		== MeleeCombat.NO_TARGET
	)


func test_ignores_out_of_reach() -> bool:
	var candidates := PackedVector3Array([Vector3(0.0, 0.0, -5.0)])
	return (
		MeleeCombat.best_target(candidates, Vector3.ZERO, FWD, REACH, MIN_FACING)
		== MeleeCombat.NO_TARGET
	)


func test_prefers_head_on_closest() -> bool:
	# Index 0 is off to the side and farther; index 1 is dead ahead and closer.
	var candidates := PackedVector3Array([Vector3(1.4, 0.0, -1.4), Vector3(0.0, 0.0, -1.0)])
	return MeleeCombat.best_target(candidates, Vector3.ZERO, FWD, REACH, MIN_FACING) == 1


func test_none_when_empty() -> bool:
	return (
		MeleeCombat.best_target(PackedVector3Array(), Vector3.ZERO, FWD, REACH, MIN_FACING)
		== MeleeCombat.NO_TARGET
	)


func test_overlap_counts_as_dead_ahead() -> bool:
	# A target sharing the attacker's planar position (only y differs) still
	# connects — a point-blank grapple shouldn't whiff on a zero-length vector.
	var candidates := PackedVector3Array([Vector3(0.0, 1.0, 0.0)])
	return MeleeCombat.best_target(candidates, Vector3.ZERO, FWD, REACH, MIN_FACING) == 0
