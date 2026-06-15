extends SceneTree
## Runtime probe for AmbientEncounterSpawner in miami.tscn. Boots the map,
## asserts the spawner wired itself to AmbientEventDirector, simulates a
## street_race roll, and confirms the live race activates with a HUD objective.
##   godot --headless --path game --script res://tests/ambient_street_race_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90
const EXPECTED_OBJECTIVE: String = "Street race: hit the checkpoints"

var _scene: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("ambient street race probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var err := _verify()
	if err.is_empty():
		print("ambient street race probe: OK (race active + objective set)")
		quit(0)
	else:
		push_error("ambient street race probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var spawner := _scene.find_child("AmbientEncounterSpawner", true, false)
	if spawner == null:
		return "AmbientEncounterSpawner not present in miami.tscn"
	var director := _scene.find_child("AmbientEventDirector", true, false)
	if director == null:
		return "AmbientEventDirector not present in miami.tscn"
	if not director.has_signal("encounter_triggered"):
		return "AmbientEventDirector missing encounter_triggered signal"
	if not director.encounter_triggered.is_connected(Callable(spawner, "_on_encounter")):
		return "spawner not wired to AmbientEventDirector.encounter_triggered"
	spawner.call("_on_encounter", "street_race", "race")
	var race := get_first_node_in_group("race")
	var stats := get_first_node_in_group("player_stats")
	return _race_objective_error(race, stats)


func _race_objective_error(race: Node, stats: Node) -> String:
	if race == null:
		return "no RaceController in group 'race'"
	if not race.has_method("is_active") or not race.is_active():
		return "race did not activate after street_race encounter"
	if stats == null:
		return "no player_stats node"
	if not ("objective_title" in stats) or String(stats.objective_title).is_empty():
		return "player_stats objective not set after street_race encounter"
	if String(stats.objective_title) != EXPECTED_OBJECTIVE:
		return "unexpected objective '%s'" % stats.objective_title
	return ""
