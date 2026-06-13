extends SceneTree
## Runtime wiring probe for the main playable map.
##
## The smoke test only advances one frame per scene, so it proves miami.tscn
## boots but not that the gameplay simulation actually connects. This boots
## miami.tscn, lets it run long enough for the streaming directors to tick at
## least once, then asserts the self-wiring system nodes registered with their
## groups (so the live HUD has data) and the dynamic directors are present and
## found the player. Run headless:
##   godot --headless --path game --script res://tests/miami_wiring_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90

var _scene: Node = null
var _frames: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami wiring probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	_run_checks()
	return _finish()


func _run_checks() -> void:
	_expect_one("player")
	_expect_one("player_health")
	_expect_one("player_stats")
	_expect_one("wanted")
	_expect_one("mission")
	_expect_one("bark_director")
	_expect_one("weather")
	_expect_one("floating_origin")

	# The weather front must actually be wired to the scene: fog driven through
	# the WorldEnvironment and a Rain volume to switch on inside rain bands.
	var weather := get_first_node_in_group("weather") as WeatherController
	if weather != null:
		if weather.get_node_or_null(weather.environment_path) == null:
			_failures.append("weather: environment_path is not wired")
		if weather.get_node_or_null(weather.rain_path) as Rain == null:
			_failures.append("weather: rain_path is not a Rain volume")

	for director_name in ["CrowdDirector", "TrafficDirector", "PoliceSpawner"]:
		if _scene.find_child(director_name, true, false) == null:
			_failures.append("missing director node: %s" % director_name)

	# The dynamic directors discover the player through the "player" group on
	# _ready; a missing player would leave them inert. Confirm the group the
	# directors and HUD both rely on resolves to the rig.
	var players := get_nodes_in_group("player")
	if players.size() == 1 and players[0] is not CharacterBody3D:
		_failures.append("player group node is not a CharacterBody3D")
	if players.size() == 1 and (players[0] as Node).get_node_or_null("MeleeController") == null:
		_failures.append("player scene has no MeleeController (unarmed combat dead)")


func _expect_one(group_name: String) -> void:
	var count := get_nodes_in_group(group_name).size()
	if count != 1:
		_failures.append("group '%s': expected 1, found %d" % [group_name, count])


func _finish() -> bool:
	if _failures.is_empty():
		print("miami wiring probe: OK (gameplay stack wired)")
		quit(0)
	else:
		for failure in _failures:
			push_error("miami wiring probe FAIL :: %s" % failure)
		print("miami wiring probe: %d failure(s)" % _failures.size())
		quit(1)
	return true
