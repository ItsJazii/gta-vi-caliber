extends SceneTree
## Runtime wiring probe for CrimeReactionDirector.
##
## Proves the node self-wires in a real tree: subscribing to a `wanted` group
## member's stars_changed signal files a news headline AND heats the active
## district, and the heat then decays via _process. Built with a mock wanted node
## so it needs no scene file — independent of miami.tscn. Run headless:
##   godot --headless --path game --script res://tests/crime_reaction_probe.gd

const SETTLE_FRAMES: int = 3

var _dir: CrimeReactionDirector = null
var _mock: MockWanted = null
var _frames: int = 0
var _heat_after_crime: float = 0.0
var _checked_reaction: bool = false


class MockWanted:
	extends Node
	signal stars_changed(stars: int)
	var _stars: int = 0

	func _ready() -> void:
		add_to_group("wanted")

	func stars() -> int:
		return _stars

	func escalate(to_stars: int) -> void:
		_stars = to_stars
		stars_changed.emit(to_stars)


func _initialize() -> void:
	_mock = MockWanted.new()
	root.add_child(_mock)
	_dir = CrimeReactionDirector.new()
	root.add_child(_dir)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	if not _checked_reaction:
		return _check_reaction()
	return _check_decay()


# A wanted spike should file news AND heat the active district.
func _check_reaction() -> bool:
	_mock.escalate(4)
	if not _dir.news.has_pending():
		return _fail("crime did not file a news headline")
	_heat_after_crime = _dir.districts.heat_in(_dir.active_district)
	if _heat_after_crime <= 0.0:
		return _fail("crime did not heat the active district")
	_checked_reaction = true
	return false


# After a few more frames, _process decay should have cooled the district.
func _check_decay() -> bool:
	if _dir.districts.heat_in(_dir.active_district) < _heat_after_crime:
		return _pass()
	if _frames > SETTLE_FRAMES + 600:
		return _fail("district heat did not decay over time")
	return false


func _pass() -> bool:
	print("crime reaction probe: OK (news + district heat wired, heat decays)")
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("crime reaction probe FAIL: %s" % reason)
	quit(1)
	return true
