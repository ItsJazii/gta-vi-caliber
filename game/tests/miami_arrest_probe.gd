extends SceneTree
## "Busted" loop probe for the main playable map.
##
## Proves the arrest half of the fail loop fires end to end in miami.tscn: while
## the player is wanted and an officer is on top of them, the ArrestController's
## grapple timer runs out, the bust lands, the wallet is docked, and the heat
## clears. Plants a stand-in officer right on the player (no damage) so the bust,
## not a Wasted death, is what we measure. Run headless:
##   godot --headless --path game --script res://tests/miami_arrest_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 40
const CRIME_COUNT: int = 8
## Grapple is ~1.5s (~90 physics ticks); allow comfortable margin before failing.
const BUST_FRAMES: int = 400
## Keep the unrelated threaded crowd load outside this short probe. Quitting
## while that request starts can leave a zero-reference loader object at exit.
const CROWD_LOAD_DELAY: float = 30.0

var _scene: Node = null
var _frames: int = 0
var _staged: bool = false
var _busted: bool = false
var _fee: int = 0
var _money_before: int = 0
var _player: Node3D = null
var _tracker: Node = null


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami arrest probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	var crowd := _scene.find_child("CrowdDirector", true, false)
	if crowd != null and "pedestrian_load_delay" in crowd:
		crowd.set("pedestrian_load_delay", CROWD_LOAD_DELAY)
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	if not _staged:
		return _stage()
	if _busted:
		return _check()
	if _frames >= WARMUP_FRAMES + BUST_FRAMES:
		return _fail("never busted within %d frames" % BUST_FRAMES)
	return false


func _stage() -> bool:
	_player = get_first_node_in_group("player") as Node3D
	_tracker = get_first_node_in_group("wanted")
	var arrest := get_first_node_in_group("arrest")
	var stats := get_first_node_in_group("player_stats")
	if _player == null or _tracker == null or arrest == null or stats == null:
		return _fail("missing player / wanted / arrest / player_stats node")
	if not _tracker.has_method("report_crime"):
		return _fail("tracker has no report_crime()")
	for _i in CRIME_COUNT:
		_tracker.report_crime(true)
	_money_before = int(stats.money)
	# Plant a stand-in officer on top of the player so the cuffs close in. A bare
	# Marker3D in group "police" satisfies the ArrestController's proximity check
	# without dealing damage, isolating Busted from a Wasted death.
	var cop := Marker3D.new()
	cop.add_to_group("police")
	_scene.add_child(cop)
	cop.global_position = _player.global_position
	arrest.busted.connect(_on_busted)
	_staged = true
	return false


func _on_busted(fee: int) -> void:
	_busted = true
	_fee = fee


func _check() -> bool:
	var stats := get_first_node_in_group("player_stats")
	var stars := int(_tracker.stars()) if _tracker.has_method("stars") else -1
	var money_after := int(stats.money) if stats != null else -1
	if _fee <= 0:
		return _fail("bust took no cash (fee=%d)" % _fee)
	if money_after != _money_before - _fee:
		return _fail(
			"cash mismatch (before=%d after=%d fee=%d)" % [_money_before, money_after, _fee]
		)
	if stars != 0:
		return _fail("wanted not cleared after bust (stars=%d)" % stars)
	print("miami arrest probe: OK (busted -> -$%d, heat cleared)" % _fee)
	quit(0)
	return true


func _fail(message: String) -> bool:
	push_error("miami arrest probe FAIL :: %s" % message)
	print("miami arrest probe: FAIL")
	quit(1)
	return true
