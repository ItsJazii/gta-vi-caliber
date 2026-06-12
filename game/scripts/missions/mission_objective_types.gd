class_name MissionObjectiveTypes
extends RefCounted
## Pure satisfaction/progress evaluators for the varied GTA-style objective KINDS
## (reach a point, collect N items, eliminate targets, escort an NPC, survive a
## timer, defend a structure) so missions are not all "drive to a zone".
##
## MissionObjectives owns the ordered objective set + done-flags and MissionFlow
## sequences them; this layer answers, per objective, "is it satisfied / failed /
## how far along (0..1)". Static, scene-free, RNG-free, defensively clamped —
## unit-tested headless (tests/unit/test_mission_objective_types.gd). The nested
## Counter is the only stateful piece, a small tally for COLLECT/wave objectives.

enum Kind { REACH, COLLECT, ELIMINATE, ESCORT, SURVIVE, DEFEND }


## Stable string id for a kind (HUD/save use), or "" for an unknown value.
static func kind_name(kind: int) -> String:
	match kind:
		Kind.REACH:
			return "reach"
		Kind.COLLECT:
			return "collect"
		Kind.ELIMINATE:
			return "eliminate"
		Kind.ESCORT:
			return "escort"
		Kind.SURVIVE:
			return "survive"
		Kind.DEFEND:
			return "defend"
		_:
			return ""


## REACH: player is within `radius` of the target point (radius floored at 0).
static func reach_satisfied(player_pos: Vector3, target_pos: Vector3, radius: float) -> bool:
	return player_pos.distance_to(target_pos) <= maxf(radius, 0.0)


## COLLECT: fraction gathered in [0,1]. A required count <= 0 is "nothing to do",
## so it reports fully complete (1.0); over-collecting caps at 1.0.
static func collect_progress(collected: int, required: int) -> float:
	if required <= 0:
		return 1.0
	return clampf(float(maxi(collected, 0)) / float(required), 0.0, 1.0)


## COLLECT done: gathered at least `required` (a required <= 0 is instantly done).
static func collect_satisfied(collected: int, required: int) -> bool:
	if required <= 0:
		return true
	return maxi(collected, 0) >= required


## ELIMINATE done: no targets left to kill (negative treated as 0).
static func eliminate_satisfied(targets_remaining: int) -> bool:
	return maxi(targets_remaining, 0) <= 0


## ESCORT failed: the escortee died (health at or below 0).
static func escort_failed(escortee_health: float) -> bool:
	return escortee_health <= 0.0


## ESCORT done: the escortee reached the drop-off within `radius`.
static func escort_satisfied(escortee_pos: Vector3, dest_pos: Vector3, radius: float) -> bool:
	return escortee_pos.distance_to(dest_pos) <= maxf(radius, 0.0)


## SURVIVE: fraction of the hold-out timer elapsed in [0,1]. A duration <= 0 is a
## degenerate "no wait", reported as complete (1.0).
static func survive_progress(time_survived: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(maxf(time_survived, 0.0) / duration, 0.0, 1.0)


## SURVIVE done: held out for the full duration (a duration <= 0 is instantly done).
static func survive_satisfied(time_survived: float, duration: float) -> bool:
	if duration <= 0.0:
		return true
	return time_survived >= duration


## DEFEND failed: the protected structure was destroyed (health at or below 0).
static func defend_failed(structure_health: float) -> bool:
	return structure_health <= 0.0


## Small mutable tally for COLLECT / wave-clear objectives: count up toward a
## fixed target, ignoring negative deltas and capping reported progress at done.
class Counter:
	extends RefCounted

	var _target: int
	var _count: int = 0

	func _init(target: int = 0) -> void:
		_target = maxi(target, 0)

	## Add `n` to the tally (negative or zero is ignored); returns the new count.
	func add(n: int) -> int:
		if n > 0:
			_count += n
		return _count

	func count() -> int:
		return _count

	func target() -> int:
		return _target

	## Items still needed to finish, never below 0 (0 once the target is met).
	func remaining() -> int:
		return maxi(_target - _count, 0)

	## True once the target is reached (a target of 0 is done immediately).
	func is_done() -> bool:
		return _count >= _target

	## Tally fraction in [0,1]; a target of 0 reports 1.0, over-count caps at 1.0.
	func progress() -> float:
		return MissionObjectiveTypes.collect_progress(_count, _target)

	## Wipe the tally back to empty (keeps the target) for a mission retry.
	func reset() -> void:
		_count = 0
