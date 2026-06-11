extends SceneTree
## Headless boot test: every world scene must instantiate and contain a
## working player rig. Run via:
##   godot --headless --path game --script res://tests/smoke_test.gd
##
## This is the "main stays playable" gate — if this fails, a clone won't run.
## Scenes are booted one per frame: group registration needs the node to be
## in the live tree, so each scene is added on one frame and checked on the
## next, then freed before the next scene loads.

const SCENES: PackedStringArray = [
	"res://scenes/world/sandbox.tscn",
	"res://scenes/world/playground.tscn",
	"res://scenes/world/districts/downtown_la.tscn",
	"res://scenes/world/ocean_demo.tscn",
]

var _index: int = -1
var _current: Node = null
var _failures: PackedStringArray = []


func _process(_delta: float) -> bool:
	if _index >= 0 and _current != null:
		_check_scene(SCENES[_index])
		_current.free()
		_current = null

	_index += 1
	if _index >= SCENES.size() or not _failures.is_empty():
		return _finish()

	var packed: PackedScene = load(SCENES[_index])
	if packed == null:
		_failures.append("scene failed to load: %s" % SCENES[_index])
		return _finish()
	_current = packed.instantiate()
	root.add_child(_current)
	return false


func _check_scene(scene_path: String) -> void:
	var players := get_nodes_in_group("player")
	if players.size() != 1:
		_fail(scene_path, "expected exactly 1 node in group 'player', found %d" % players.size())
	elif players[0] is not CharacterBody3D:
		_fail(scene_path, "player root is not a CharacterBody3D")
	elif (players[0] as Node).find_children("*", "Camera3D", true).is_empty():
		_fail(scene_path, "player has no Camera3D")

	if get_nodes_in_group("world").is_empty():
		_fail(scene_path, "no node in group 'world'")
	if get_nodes_in_group("spawn_points").is_empty():
		_fail(scene_path, "no spawn points (Marker3D in group 'spawn_points')")


func _fail(scene_path: String, message: String) -> void:
	_failures.append("%s: %s" % [scene_path, message])


func _finish() -> bool:
	if _failures.is_empty():
		print("smoke test: OK (%d scenes)" % SCENES.size())
		quit(0)
	else:
		for failure in _failures:
			push_error("smoke test: %s" % failure)
		quit(1)
	return true
