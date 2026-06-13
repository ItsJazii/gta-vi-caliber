class_name ProgressionTracker
extends Node
## Makes PlayerProgression live: awards respect/XP as the player completes
## mission objectives and missions, so levels actually climb during play. Thin
## self-wiring coordinator — finds the MissionController in group "mission" and
## drives a PlayerProgression instance; joins group "progression" so the HUD can
## read level()/level_progress(). Mirrors how MissionReward credits money.

@export var objective_xp: int = 120
@export var mission_xp: int = 600

var _progression: PlayerProgression


func _ready() -> void:
	_progression = PlayerProgression.new()
	add_to_group("progression")
	var mission := get_tree().get_first_node_in_group("mission")
	if mission == null:
		return
	if mission.has_signal("objective_completed"):
		mission.connect("objective_completed", _on_objective)
	if mission.has_signal("mission_completed"):
		mission.connect("mission_completed", _on_mission)


func _on_objective(_id: String) -> void:
	_progression.add_xp(objective_xp)


func _on_mission() -> void:
	_progression.add_xp(mission_xp)


## Current respect level, for the HUD.
func level() -> int:
	return _progression.level() if _progression != null else 1


## Progress through the current level, 0..1, for a HUD bar.
func level_progress() -> float:
	return _progression.level_progress() if _progression != null else 0.0


## Total respect earned, for the HUD / save.
func total_xp() -> int:
	return _progression.total_xp() if _progression != null else 0


# --- Persistence (SaveManager) ---------------------------------------------


func serialize() -> Dictionary:
	return {"total_xp": total_xp()}


## Rebuild from a serialize() snapshot: replaying lifetime XP through the
## levelling curve reconstructs level and within-level progress exactly.
func restore(data: Dictionary) -> void:
	if _progression == null:
		_progression = PlayerProgression.new()
	_progression.reset()
	_progression.add_xp(maxi(int(SaveData.number_or(data.get("total_xp"), 0)), 0))
