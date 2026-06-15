extends SceneTree
## Runtime probe: the rig's death/hit reactions are one-shots (LOOP_NONE) so a
## downed NPC settles on its final frame instead of re-collapsing on a loop (the
## "corpse flying" bug), while locomotion clips stay looping. Guards
## AnimatedRig._install_animations' loop-mode pinning.

const CIVILIAN_RIG_PATH: String = "res://scenes/npc/civilian_rig.tscn"
const WARMUP_FRAMES: int = 6

var _rig: AnimatedRig = null
var _frames: int = 0


func _initialize() -> void:
	var packed := load(CIVILIAN_RIG_PATH) as PackedScene
	if packed == null:
		_fail("cannot load %s" % CIVILIAN_RIG_PATH)
		return
	_rig = packed.instantiate() as AnimatedRig
	if _rig == null:
		_fail("%s root is not AnimatedRig" % CIVILIAN_RIG_PATH)
		return
	root.add_child(_rig)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var failures := PackedStringArray()
	var anim_player := _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		failures.append("rig has no AnimationPlayer")
	else:
		_check_loop(anim_player, &"Death01", Animation.LOOP_NONE, failures)
		_check_loop(anim_player, &"Hit_Chest", Animation.LOOP_NONE, failures)
		_check_loop(anim_player, &"Walk", Animation.LOOP_LINEAR, failures)
		_check_loop(anim_player, &"Sprint", Animation.LOOP_LINEAR, failures)
	if not failures.is_empty():
		for failure in failures:
			push_error("anim loop probe FAIL :: %s" % failure)
		quit(1)
		return true
	print("anim loop probe: OK (death/hit hold, locomotion loops)")
	quit(0)
	return true


func _check_loop(
	anim_player: AnimationPlayer, anim_name: StringName, want: int, failures: PackedStringArray
) -> void:
	if not anim_player.has_animation(anim_name):
		failures.append("%s clip missing" % anim_name)
		return
	var got: int = anim_player.get_animation(anim_name).loop_mode
	if got != want:
		failures.append("%s loop_mode=%d want %d" % [anim_name, got, want])


func _fail(message: String) -> void:
	push_error("anim loop probe FAIL :: %s" % message)
	quit(1)
