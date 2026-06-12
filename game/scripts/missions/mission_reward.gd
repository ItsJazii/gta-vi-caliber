class_name MissionReward
extends Node
## Makes the economy live: pays the player for mission progress so the money HUD
## actually moves. Each completed objective credits a small reward and finishing
## a mission pays a bonus. Self-wires by group — finds the MissionController in
## group "mission" and PlayerStats in group "player_stats" — so it needs no
## per-scene plumbing beyond being present.

@export var objective_reward: int = 250
@export var mission_bonus: int = 1000

var _stats: Node = null


func _ready() -> void:
	var mission := get_tree().get_first_node_in_group("mission")
	if mission == null:
		return
	if mission.has_signal("objective_completed"):
		mission.connect("objective_completed", _on_objective)
	if mission.has_signal("mission_completed"):
		mission.connect("mission_completed", _on_mission)


func _on_objective(_id: String) -> void:
	_pay(objective_reward)


func _on_mission() -> void:
	_pay(mission_bonus)


func _pay(amount: int) -> void:
	var stats := _player_stats()
	if stats != null and stats.has_method("add_money"):
		stats.add_money(amount)


func _player_stats() -> Node:
	if _stats == null or not is_instance_valid(_stats):
		_stats = get_tree().get_first_node_in_group("player_stats")
	return _stats
