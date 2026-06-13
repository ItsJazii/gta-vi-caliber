extends SceneTree
## Runtime wiring probe for AmbientEventDirector.
##
## Proves the timer-driven node self-wires in a real tree: it reads stars from a
## `wanted` group member and, on its tick, rolls AmbientEvents and emits
## encounter_triggered. Built with a mock wanted node + a tiny tick + a fixed seed
## so it's deterministic and needs no scene file. Run headless:
##   godot --headless --path game --script res://tests/ambient_event_probe.gd

var _dir: AmbientEventDirector = null
var _frames: int = 0
var _fired_id: String = ""
var _fired_kind: String = ""


class MockWanted:
	extends Node
	signal stars_changed(stars: int)

	func _ready() -> void:
		add_to_group("wanted")

	func stars() -> int:
		return 0


func _initialize() -> void:
	root.add_child(MockWanted.new())
	_dir = AmbientEventDirector.new()
	root.add_child(_dir)  # _ready randomizes; override with a fixed seed below
	_dir.tick_interval = 0.01
	_dir.set_seed(7)
	_dir.encounter_triggered.connect(_on_encounter)


func _on_encounter(id: String, kind: String) -> void:
	_fired_id = id
	_fired_kind = kind


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if not _fired_id.is_empty():
		if _fired_kind != _dir.events.kind_of(_fired_id):
			return _fail("emitted kind '%s' does not match the model" % _fired_kind)
		return _pass()
	if _frames > 240:
		return _fail("no encounter fired after the tick interval elapsed")
	return false


func _pass() -> bool:
	print("ambient event probe: OK (timer rolled encounter '%s')" % _fired_id)
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("ambient event probe FAIL: %s" % reason)
	quit(1)
	return true
