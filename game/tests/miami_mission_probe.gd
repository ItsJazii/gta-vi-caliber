extends SceneTree
## Mission-vertical probe for the main playable map.
##
## Proves the in-world mission actually plays: it walks the player rig through
## each MissionTrigger Area3D in miami.tscn (reach the car, drive the strip,
## return home) and asserts the MissionController completes the mission. Guards
## the orphaned MissionController/MissionTrigger framework against scene rot.
## Run headless:
##   godot --headless --path game --script res://tests/miami_mission_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 30
const DWELL_FRAMES: int = 14
## Trigger world positions, in the order the objectives must be completed.
const WAYPOINTS: Array = [Vector3(7, 1, 5), Vector3(72, 1, -48), Vector3(0, 1, 0)]

var _scene: Node = null
var _player: Node3D = null
var _mission: Node = null
var _stats: Node = null
var _money_at_start: int = 0
var _frames: int = 0
var _stop: int = 0
var _phase: int = 0
var _dwell: int = 0
var _failed: bool = false


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami mission probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	if _frames == WARMUP_FRAMES:
		return _resolve_nodes()

	# Pin the player inside the current trigger for a few frames so Area3D
	# body_entered registers, then advance to the next objective marker.
	if _phase < WAYPOINTS.size():
		if _dwell == 0:
			_player.global_position = WAYPOINTS[_phase]
		_player.global_position = WAYPOINTS[_phase]
		_dwell += 1
		if _dwell >= DWELL_FRAMES:
			_dwell = 0
			_phase += 1
		return false

	return _finish()


func _resolve_nodes() -> bool:
	var players := get_nodes_in_group("player")
	_player = players[0] as Node3D if not players.is_empty() else null
	_mission = get_first_node_in_group("mission")
	if _player == null:
		return _fail("no player rig in group 'player'")
	if _mission == null or not _mission.has_method("is_complete"):
		return _fail("no MissionController in group 'mission'")
	if not _mission.has_method("hud_text"):
		return _fail("mission node missing hud_text()")
	_stats = get_first_node_in_group("player_stats")
	if _stats == null or not ("money" in _stats):
		return _fail("no PlayerStats with money in group 'player_stats'")
	_money_at_start = int(_stats.money)
	return false


func _finish() -> bool:
	if _failed:
		return true
	if _mission.is_complete():
		var earned := int(_stats.money) - _money_at_start
		if earned <= 0:
			push_error("miami mission probe FAIL :: mission complete but economy paid nothing")
			print("miami mission probe: FAIL — money unchanged at %d" % int(_stats.money))
			quit(1)
			return true
		print(
			(
				"miami mission probe: OK (mission complete across %d objectives, earned $%d)"
				% [WAYPOINTS.size(), earned]
			)
		)
		quit(0)
	else:
		push_error("miami mission probe FAIL :: mission not complete after visiting all triggers")
		print("miami mission probe: FAIL — hud now reads '%s'" % _mission.hud_text())
		quit(1)
	return true


func _fail(message: String) -> bool:
	_failed = true
	push_error("miami mission probe FAIL :: %s" % message)
	print("miami mission probe: FAIL")
	quit(1)
	return true
