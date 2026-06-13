extends SceneTree
## Exercises the real main-menu Play transition, including threaded scene load.

const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const TIMEOUT_MSEC: int = 60_000

var _menu: MainMenu
var _started_at_msec: int
var _play_pressed: bool = false
var _world_ready_msec: int = -1


func _initialize() -> void:
	_started_at_msec = Time.get_ticks_msec()
	var packed := load(MENU_SCENE) as PackedScene
	if packed == null:
		_fail("main menu failed to load")
		return
	_menu = packed.instantiate() as MainMenu
	if _menu == null:
		_fail("main menu failed to instantiate")
		return
	root.add_child(_menu)
	current_scene = _menu


func _process(_delta: float) -> bool:
	if not _play_pressed:
		_play_pressed = true
		_menu.call("_on_play")
		return false

	var worlds := get_nodes_in_group("world")
	if not worlds.is_empty():
		return _check_world(worlds[0] as Node)

	if Time.get_ticks_msec() - _started_at_msec > TIMEOUT_MSEC:
		return _fail("timed out waiting for playable world and crowd")
	return false


func _check_world(world: Node) -> bool:
	var streamers := get_nodes_in_group("district_streamer")
	if streamers.size() != 1:
		return _fail("expected one district streamer, found %d" % streamers.size())
	var resident: Array = streamers[0].call("resident_names")
	if resident != ["downtown_miami"]:
		return _fail("startup loaded unexpected districts: %s" % str(resident))
	if _world_ready_msec < 0:
		_world_ready_msec = Time.get_ticks_msec()
	var crowd := world.find_child("CrowdDirector", true, false) as CrowdDirector
	if crowd == null:
		return _fail("crowd director is missing")
	if crowd.pedestrian_scene == null or crowd.population() < crowd.target_count:
		return false
	print(
		(
			"menu startup probe: OK (world %d ms, full crowd %d ms, %s)"
			% [
				_world_ready_msec - _started_at_msec,
				Time.get_ticks_msec() - _started_at_msec,
				resident[0],
			]
		)
	)
	quit(0)
	return true


func _fail(message: String) -> bool:
	push_error("menu startup probe: %s" % message)
	quit(1)
	return true
