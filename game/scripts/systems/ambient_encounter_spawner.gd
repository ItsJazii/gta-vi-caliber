class_name AmbientEncounterSpawner
extends Node
## Connects AmbientEventDirector.encounter_triggered to live encounter handlers.
## Self-wiring: finds the director sibling and the race by group, then activates
## gameplay when a freeroam roll fires. PR 1 handles street_race only; other ids
## are ignored until a later pass adds spawn logic. Exercised by
## tests/ambient_street_race_probe.gd.

signal encounter_started(id: String, kind: String)

const STREET_RACE_OBJECTIVE: String = "Street race: hit the checkpoints"

var _director: AmbientEventDirector = null
var _race: RaceController = null
var _race_finished_connected: bool = false


func _ready() -> void:
	call_deferred("_connect_director")


func _connect_director() -> void:
	_director = _find_director()
	if _director == null:
		return
	if not _director.encounter_triggered.is_connected(_on_encounter):
		_director.encounter_triggered.connect(_on_encounter)
	_race = get_tree().get_first_node_in_group("race") as RaceController
	if _race != null and not _race_finished_connected:
		_race.race_finished.connect(_on_race_finished)
		_race_finished_connected = true


func _on_encounter(id: String, kind: String) -> void:
	if id == "street_race":
		_start_street_race()
		return
	encounter_started.emit(id, kind)


func _start_street_race() -> void:
	if _race == null:
		_race = get_tree().get_first_node_in_group("race") as RaceController
	if _race == null:
		return
	_race.start_challenge()
	var waypoint := _race.first_checkpoint()
	var stats := get_tree().get_first_node_in_group("player_stats")
	if stats != null and stats.has_method("set_objective"):
		stats.set_objective(STREET_RACE_OBJECTIVE, waypoint, waypoint != Vector3.ZERO)
	encounter_started.emit("street_race", "race")


func _on_race_finished(_reward: int) -> void:
	var stats := get_tree().get_first_node_in_group("player_stats")
	if stats == null or not stats.has_method("clear_objective"):
		return
	if not ("objective_title" in stats):
		return
	if String(stats.objective_title) == STREET_RACE_OBJECTIVE:
		stats.clear_objective()


func _find_director() -> AmbientEventDirector:
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is AmbientEventDirector:
				return child as AmbientEventDirector
	return get_tree().get_first_node_in_group("ambient_event_director") as AmbientEventDirector
