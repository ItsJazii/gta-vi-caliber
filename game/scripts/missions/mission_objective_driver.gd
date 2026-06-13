class_name MissionObjectiveDriver
extends Node
## Completes MissionController objectives from world state instead of Area3D
## trigger geometry, so every campaign mission can have its own locations and
## objective kinds without per-mission scene edits. Each physics tick it looks
## at the controller's ACTIVE objective; if the campaign declared a kind for
## that id, the matching MissionObjectiveTypes predicate decides completion:
##   "reach" — the player comes within radius of the objective's waypoint;
##   "hold"  — the player must STAY within radius for duration seconds
##             (leaving resets the clock) — the stake-out / meet beat.
## Objectives with no declared kind keep completing through whatever scene
## triggers exist (the opening mission uses the three hand-placed zones).
## The decision step is static and unit-tested; the node is just the pump.

## Active objective id -> {kind: String, radius: float, duration: float}.
var defs: Dictionary = {}

var _controller: Node = null
var _held: float = 0.0
var _armed_id: String = ""


## Point the driver at the live MissionController. Re-bind on every mission
## change so a leftover hold clock can't leak into the next mission.
func bind(controller: Node) -> void:
	_controller = controller
	_held = 0.0
	_armed_id = ""


func _physics_process(delta: float) -> void:
	if _controller == null or not _controller.is_active():
		return
	var oid := String(_controller.current_objective_id())
	if oid.is_empty() or not defs.get(oid) is Dictionary:
		return
	if oid != _armed_id:
		_armed_id = oid
		_held = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var verdict := evaluate(
		defs[oid], player.global_position, _controller.current_waypoint(), _held, delta
	)
	_held = verdict["held"]
	if verdict["satisfied"]:
		_controller.complete(oid)


## Pure decision step (unit-tested): given an objective def, the player and
## target positions, and the accumulated hold time, returns
## {"satisfied": bool, "held": float} — the new hold clock to carry forward.
## Unknown kinds behave as "reach" so a typo'd def degrades gracefully.
static func evaluate(
	def: Dictionary, player_pos: Vector3, target: Vector3, held: float, delta: float
) -> Dictionary:
	var radius := float(def.get("radius", 6.0))
	var inside := MissionObjectiveTypes.reach_satisfied(player_pos, target, radius)
	if String(def.get("kind", "reach")) == "hold":
		var now := held + delta if inside else 0.0
		var duration := float(def.get("duration", 3.0))
		return {"satisfied": MissionObjectiveTypes.survive_satisfied(now, duration), "held": now}
	return {"satisfied": inside, "held": 0.0}
