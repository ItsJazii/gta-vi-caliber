extends SceneTree
## Causal gameplay-loop probe for the main playable map.
##
## miami_wiring_probe proves the systems are *present*; this proves the GTA core
## loop actually *fires* end to end in miami.tscn: a crime raises the wanted
## level, and a raised wanted level makes the police spawner dispatch officers
## around the player. Guards against a swarm edit silently unhooking the chain.
## Run headless:
##   godot --headless --path game --script res://tests/miami_loop_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 40
## PoliceSpawner ticks every spawn_interval (1.6s ≈ 96 physics frames); give it
## comfortably more than one tick to dispatch before we give up.
const RESPONSE_FRAMES: int = 260
const CRIME_COUNT: int = 8

var _scene: Node = null
var _frames: int = 0
var _crime_reported: bool = false
var _spawner: Node = null
var _tracker: Node = null


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami loop probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == WARMUP_FRAMES:
		_commit_crimes()
		return false
	if _frames < WARMUP_FRAMES:
		return false

	# Poll for the police response; succeed the instant officers appear.
	if _crime_reported and _spawner != null and _spawner.get_child_count() > 0:
		return _pass()
	if _frames >= WARMUP_FRAMES + RESPONSE_FRAMES:
		return _timeout()
	return false


func _commit_crimes() -> void:
	_tracker = get_first_node_in_group("wanted")
	_spawner = _scene.find_child("PoliceSpawner", true, false)
	if _tracker == null or not _tracker.has_method("report_crime"):
		_fail("no WantedTracker with report_crime() in group 'wanted'")
		return
	if _spawner == null:
		_fail("no PoliceSpawner node found")
		return
	# Witness gate sanity first: a kill miles from every observer goes
	# unreported — no heat, no stars.
	if _tracker.has_method("report_witnessed_crime"):
		_tracker.report_witnessed_crime(true, Vector3(40000.0, 0.0, 40000.0))
		if bool(_tracker.is_wanted()):
			_fail("unseen crime raised heat — witness gate is not filtering")
			return
	for _i in CRIME_COUNT:
		_tracker.report_crime(true)
	_crime_reported = true


func _pass() -> bool:
	var stars := int(_tracker.stars()) if _tracker.has_method("stars") else -1
	print(
		(
			"miami loop probe: OK (crime -> %d stars -> %d officers dispatched)"
			% [stars, _spawner.get_child_count()]
		)
	)
	quit(0)
	return true


func _timeout() -> bool:
	var stars := int(_tracker.stars()) if _tracker != null and _tracker.has_method("stars") else -1
	_fail("police never dispatched within %d frames (stars=%d)" % [RESPONSE_FRAMES, stars])
	return true


func _fail(message: String) -> bool:
	push_error("miami loop probe FAIL :: %s" % message)
	print("miami loop probe: FAIL")
	quit(1)
	return true
