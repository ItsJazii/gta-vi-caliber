class_name MissionController
extends Node
## Drives one multi-step MissionObjectives from world triggers and a timer, with a
## clean retry path — the scene glue M5 missions need beyond the kill-counter
## MissionDirector.
##
## Triggers (MissionTrigger) call complete(id); a per-objective waypoint feeds the
## HUD/minimap; the mission fails on timeout or player death and can reset() to
## replay. All rules are pure and tested: MissionObjectives (state machine) +
## MissionFlow (sequencing/fail). Joins group "mission" so the HUD can poll
## hud_text(), matching MissionDirector's convention (a scene uses one or other).

signal objective_completed(id: String)
signal mission_completed
signal mission_failed

@export var title: String = "MISSION"
## Ordered objective sequence; each entry {id:String, text:String}.
@export var objective_defs: Array = []
## Optional per-objective world waypoint: id (String) → Vector3.
@export var waypoints: Dictionary = {}
## 0 = untimed; otherwise the mission fails when the clock runs out.
@export var time_limit: float = 0.0
## Start automatically on ready (turn off for missions a trigger/NPC starts).
@export var auto_start: bool = true

var _mission: MissionObjectives
var _time_left: float = 0.0
var _ended: bool = false


func _ready() -> void:
	add_to_group("mission")
	_build()
	if auto_start:
		begin()


func begin() -> void:
	if _mission == null:
		_build()
	_mission.start()


## Mark an objective done; emits per-objective and completes the mission when the
## last objective closes.
func complete(id: String) -> void:
	if _mission == null or not _mission.is_active():
		return
	if _mission.complete_objective(id):
		objective_completed.emit(id)
		if _mission.is_complete():
			_finish(true)


func fail() -> void:
	if _mission != null and _mission.is_active():
		_mission.fail()
		_finish(false)


## Rebuild and restart the mission from scratch (the retry button).
func reset() -> void:
	_build()
	begin()


func is_active() -> bool:
	return _mission != null and _mission.is_active()


func is_complete() -> bool:
	return _mission != null and _mission.is_complete()


## HUD line for the current objective and progress.
func hud_text() -> String:
	return MissionFlow.hud_line(title, _mission.objectives) if _mission != null else ""


## id of the active (first not-done) objective, or "" when none remains.
func current_objective_id() -> String:
	if _mission == null:
		return ""
	return String(MissionFlow.current(_mission.objectives).get("id", ""))


## World marker for the active objective (for compass/minimap), or `fallback`.
func current_waypoint(fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if _mission == null:
		return fallback
	return MissionFlow.current_waypoint(_mission.objectives, _local_waypoints(), fallback)


# Authored waypoints are absolute world coordinates; once a FloatingOrigin has
# shifted the world, the live engine-local equivalent moves with it, so convert
# at read time (local = absolute + origin_offset).
func _local_waypoints() -> Dictionary:
	var origin := get_tree().get_first_node_in_group("floating_origin") as FloatingOrigin
	if origin == null or origin.origin_offset == Vector3.ZERO:
		return waypoints
	var local := {}
	for id in waypoints:
		local[id] = (waypoints[id] as Vector3) + origin.origin_offset
	return local


func _process(delta: float) -> void:
	if _mission == null or not _mission.is_active():
		return
	if time_limit > 0.0:
		_time_left = maxf(_time_left - delta, 0.0)
	if MissionFlow.should_fail(_player_dead(), time_limit, _time_left):
		fail()


func _build() -> void:
	_mission = MissionObjectives.new(title, objective_defs)
	_time_left = time_limit
	_ended = false


func _player_dead() -> bool:
	for health in get_tree().get_nodes_in_group("player_health"):
		if health.has_method("is_dead") and health.is_dead():
			return true
	return false


func _finish(completed: bool) -> void:
	if _ended:
		return
	_ended = true
	if completed:
		mission_completed.emit()
	else:
		mission_failed.emit()
