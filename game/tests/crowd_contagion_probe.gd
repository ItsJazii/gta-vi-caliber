extends SceneTree
## Scene-free probe for CrowdPanicDirector panic contagion: one bolting ped spreads
## fear to a calm neighbour within contagion_radius, but not to one across the street.
## Built with mock peds so it needs no scene file. Run headless:
##   godot --headless --path game --script res://tests/crowd_contagion_probe.gd

var _frames: int = 0
var _director: CrowdPanicDirector = null
var _hot: MockPed = null
var _near: MockPed = null
var _far: MockPed = null


class MockPed:
	extends Node3D
	var _fear: float = 0.0

	func _ready() -> void:
		add_to_group("pedestrians")

	func scare(_threat_pos: Vector3, seconds: float) -> void:
		_fear = maxf(_fear, seconds)

	func fear() -> float:
		return _fear


func _initialize() -> void:
	_director = CrowdPanicDirector.new()
	root.add_child(_director)
	_hot = MockPed.new()
	_near = MockPed.new()
	_far = MockPed.new()
	root.add_child(_hot)
	root.add_child(_near)
	root.add_child(_far)
	# Local position; these are root children, so it equals global_position once the
	# tree is up (and avoids the not-yet-in-tree global_position warning in _initialize).
	_hot.position = Vector3(0, 0, 0)
	_near.position = Vector3(5, 0, 0)
	_far.position = Vector3(60, 0, 0)
	_hot.scare(Vector3(-10, 0, 0), 6.0)  # the seed is already bolting


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	for _i in range(4):
		_director._spread_panic()
	if _hot.fear() <= 0.0:
		return _fail("panicking seed lost its fear")
	if _near.fear() <= 0.0:
		return _fail("panic did not spread to the near pedestrian")
	if _far.fear() > 0.0:
		return _fail("panic spread across the street (contagion radius not respected)")
	print("crowd contagion probe: OK (near caught %.1f, far %.1f)" % [_near.fear(), _far.fear()])
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("crowd contagion probe FAIL: " + reason)
	quit(1)
	return true
