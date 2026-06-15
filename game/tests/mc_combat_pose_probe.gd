extends SceneTree
## Probe: the MC player rig responds to the WeaponController combat API
## (set_armed / set_aiming / play_shoot / play_reload) with the right Meshy clip.
## The MC is a run-and-gun rig with no static aim/fire clip, so the contract is:
##   - aiming while standing  -> Run_and_Shoot held on a frozen frame (gun up, no
##                               leg shuffle / root drift): clip current, not playing
##   - aiming while moving     -> Run_and_Shoot looping (legs carry the stance)
##   - hip-firing (not aiming) -> a Run_and_Shoot one-shot burst (gun snaps up)
##   - reload standing/moving  -> Standing_Reload / Running_Reload
##   - disarming clears aim     -> back to plain Idle locomotion
## Guards WeaponController._rig resolving the MC rig (it used to cast to AnimatedRig
## and silently no-op every pose) and the MeshyAnimController aim stance.

const MC_RIG_PATH := "res://scenes/player/mc_rig.tscn"
const WARMUP_FRAMES: int = 4
const ASSERT_FRAME: int = 12
const MOVING := Vector3(0, 0, 3.0)

# label -> {vel, aiming, shoot, reload, expect_clip, expect_playing}
var _scenarios := {
	"armed_idle": {"vel": Vector3.ZERO, "aim": false, "clip": "Idle_4", "playing": true},
	"standing_aim": {"vel": Vector3.ZERO, "aim": true, "clip": "Run_and_Shoot", "playing": false},
	"moving_aim": {"vel": MOVING, "aim": true, "clip": "Run_and_Shoot", "playing": true},
	"hipfire": {"vel": Vector3.ZERO, "aim": false, "shoot": true, "clip": "Run_and_Shoot"},
	"reload_stand": {"vel": Vector3.ZERO, "aim": false, "reload": true, "clip": "Standing_Reload"},
	"reload_move": {"vel": MOVING, "aim": false, "reload": true, "clip": "Running_Reload"},
	"disarm_clears": {"vel": Vector3.ZERO, "aim": true, "disarm": true, "clip": "Idle_4"},
}
var _rigs: Dictionary = {}
var _frames: int = 0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	for label in _scenarios:
		var rig := (load(MC_RIG_PATH) as PackedScene).instantiate() as Node3D
		var mount := Node3D.new()
		mount.name = "GunMount"
		mount.add_child(MeshInstance3D.new())
		rig.add_child(mount)
		world.add_child(rig)
		_rigs[label] = rig


func _process(_delta: float) -> bool:
	_frames += 1
	for label in _scenarios:
		_drive(_rigs[label], _scenarios[label])
	if _frames < ASSERT_FRAME:
		return false

	var failures := PackedStringArray()
	for label in _scenarios:
		_check(label, _rigs[label], _scenarios[label], failures)

	if not failures.is_empty():
		for failure in failures:
			push_error("mc combat pose probe FAIL :: %s" % failure)
		quit(1)
		return true
	print("mc combat pose probe: OK (aim / hip-fire / reload all drive MC clips)")
	quit(0)
	return true


func _drive(rig: Node, s: Dictionary) -> void:
	rig.call(&"set_armed", true)
	rig.call(&"set_aiming", bool(s.get("aim", false)), 0.0)
	if s.get("disarm", false):
		rig.call(&"set_armed", false)
	if s.get("shoot", false):
		rig.call(&"play_shoot")
	# Reload fires once after a couple of frames so a moving rig has a cached planar
	# speed (set inside animate) by the time play_reload picks standing vs running.
	if s.get("reload", false) and _frames == WARMUP_FRAMES:
		rig.call(&"play_reload")
	rig.call(&"animate", s["vel"] as Vector3, true, 0.0, false, 0.016)


func _check(label: String, rig: Node, s: Dictionary, failures: PackedStringArray) -> void:
	var ap := _ap_of(rig)
	if ap == null:
		failures.append("%s: no AnimationPlayer" % label)
		return
	# A paused player (frozen standing aim) reports an empty current_animation, so
	# fall back to assigned_animation to read which clip is held.
	var cur := ap.current_animation
	if cur == "":
		cur = ap.assigned_animation
	var want: String = s["clip"]
	if not (cur == want or cur.ends_with("/" + want)):
		failures.append("%s: clip is '%s', expected '%s'" % [label, cur, want])
	if s.has("playing") and ap.is_playing() != bool(s["playing"]):
		var verb := "playing" if s["playing"] else "frozen/paused"
		failures.append("%s: expected %s but is_playing=%s" % [label, verb, ap.is_playing()])


func _ap_of(rig: Node) -> AnimationPlayer:
	for node in rig.find_children("*", "AnimationPlayer", true, false):
		return node as AnimationPlayer
	return null
