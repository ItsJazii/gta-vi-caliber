extends SceneTree
## Scene-free probe for ResponderDispatcher: a kill dispatches an ambulance that
## drives in, treats the scene, and leaves. Built with mock world/wanted nodes so it
## needs no scene file — independent of miami.tscn. The test runs from _process after
## a few warmup frames: nodes added in _initialize are not fully in-tree yet, so the
## dispatcher's get_tree() lookups (world host, etc.) only resolve once the tree is up.
## Run headless:
##   godot --headless --path game --script res://tests/responder_dispatcher_probe.gd

const DT: float = 0.1
const INCIDENT := Vector3(0, 0, 0)
const MAX_STEPS: int = 600

var _dispatcher: ResponderDispatcher = null
var _cleared: int = 0
var _frames: int = 0
var _done: bool = false


class MockWanted:
	extends Node

	func _ready() -> void:
		add_to_group("wanted")

	func stars() -> int:
		return 2


func _initialize() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	world.add_to_group("world")
	var wanted := MockWanted.new()
	root.add_child(wanted)
	_dispatcher = ResponderDispatcher.new()
	root.add_child(_dispatcher)
	_dispatcher.incident_cleared.connect(_on_cleared)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3 or _done:
		return false
	_done = true
	_run()
	return true


func _on_cleared(_incident_pos: Vector3) -> void:
	_cleared += 1


func _run() -> void:
	if not _dispatcher.dispatch_to(INCIDENT, 2):
		_fail("dispatch_to refused a 2-star injury")
		return
	if _dispatcher.active_count() != 1:
		_fail("responder did not spawn (active_count != 1)")
		return
	var unit := _spawned_unit()
	if unit == null:
		_fail("no ambulance node found under world")
		return
	var start_dist := unit.global_position.distance_to(INCIDENT)
	# A few ticks should move the ambulance closer while it is still en route.
	for _i in range(3):
		_dispatcher._process(DT)
	if unit.global_position.distance_to(INCIDENT) >= start_dist:
		_fail("responder did not move toward the incident")
		return
	_finish(unit, start_dist)


## Keep ticking until the scene clears (treatment done), then report.
func _finish(_unit: Node3D, start_dist: float) -> void:
	var steps := 0
	while _dispatcher.active_count() > 0 and steps < MAX_STEPS:
		_dispatcher._process(DT)
		steps += 1
	if _dispatcher.active_count() != 0:
		_fail("incident never cleared (active_count stuck > 0)")
		return
	if _cleared < 1:
		_fail("incident_cleared signal never fired")
		return
	_pass(start_dist, steps)


func _spawned_unit() -> Node3D:
	var world := root.get_node_or_null("World")
	if world == null:
		return null
	return world.get_node_or_null("Ambulance") as Node3D


func _pass(start_dist: float, steps: int) -> void:
	print(
		(
			"responder dispatcher probe: OK (drove in from %.1fm, cleared in %d ticks)"
			% [start_dist, steps]
		)
	)
	quit(0)


func _fail(reason: String) -> void:
	push_error("responder dispatcher probe FAIL: " + reason)
	quit(1)
