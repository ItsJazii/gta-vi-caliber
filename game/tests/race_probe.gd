extends SceneTree
## Runtime probe for the live StreetRace (RaceController) in miami.tscn. Boots the
## map, finds the race + its ordered checkpoint markers, teleports the player
## through them in order, and asserts the race finishes and pays the placement
## reward into the live wallet. Self-contained (does not touch miami_wiring_probe).
##   godot --headless --path game --script res://tests/race_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90
const DWELL_FRAMES: int = 3

var _scene: Node = null
var _frames: int = 0
var _started: bool = false
var _race: Node = null
var _markers: Array = []
var _player: Node3D = null
var _stats: Node = null
var _money0: int = 0
var _cp: int = 0
var _dwell: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("race probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	if not _started:
		return _begin()
	return _drive()


func _begin() -> bool:
	_race = get_first_node_in_group("race")
	if _race == null:
		return _fail("no node in group 'race' (StreetRace not wired)")
	for child in _race.get_children():
		if child is Marker3D:
			_markers.append((child as Marker3D).global_position)
	if _markers.size() < 2:
		return _fail("race has %d checkpoint markers, need >= 2" % _markers.size())
	_player = get_first_node_in_group("player") as Node3D
	_stats = get_first_node_in_group("player_stats")
	if _player == null or _stats == null:
		return _fail("no live player / player_stats node")
	_money0 = int(_stats.money)
	_started = true
	return false


func _drive() -> bool:
	if _cp < _markers.size():
		# Park the player on the current checkpoint for a few frames so the
		# controller's _process registers the (in-order) reach.
		_player.global_position = _markers[_cp]
		_dwell += 1
		if _dwell >= DWELL_FRAMES:
			_dwell = 0
			_cp += 1
		return false
	if not _race.is_complete():
		return _fail("race not finished after visiting all %d checkpoints" % _markers.size())
	var money1: int = int(_stats.money)
	if money1 <= _money0:
		return _fail("finishing paid no reward (%d -> %d)" % [_money0, money1])
	print(
		"race probe: OK (finished %d checkpoints, reward +%d)" % [_markers.size(), money1 - _money0]
	)
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("race probe FAIL: " + reason)
	quit(1)
	return true
