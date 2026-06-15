class_name MeshyAnimController
extends Node
## Drives a Meshy-rigged character's own AnimationPlayer directly, with no
## retargeting: every Meshy biped shares one 24-bone skeleton, so the merged clip
## library on the MC plays unchanged on the MC and on every NPC built from the
## same rig. This replaces the old CC0 RetargetModifier path.
##
## The same controller serves the player and NPCs. The owner feeds it a planar
## speed and a grounded flag each frame for locomotion, and calls play_action()
## for one-shots (melee, reload, wave, talk, react). Clips the model does not yet
## carry resolve to no-ops, so the controller is safe before the full set exists.
##
## Canonical names (left column of CLIPS) are the stable game-facing API; the
## right column maps to whatever Meshy named the clip, so regenerating the
## library only touches this table.

signal action_finished(canonical: String)

enum Mode { GROUND, AIR, ACTION, AIM }

## Canonical clip used for the held aiming/shooting stance. The Meshy MC set has no
## static aim pose, so the run-and-gun clip doubles as the gun-up stance.
const AIM_CLIP := "run_and_gun"
## Frame (0-1 of the clip) frozen for a standing aim: far enough in that the gun is
## fully raised and two-handed, before the run stride swings the torso.
const AIM_HOLD_FRACTION := 0.2

## Canonical action/state name -> clip name as it imports from the Meshy GLB.
## Add a row here when a new Meshy clip lands; callers only ever use the keys.
const CLIPS := {
	"idle": "Idle_4",
	"walk": "Walking",
	"run": "Running",
	"run_alt": "Run_02",
	"walk_back": "Walk_Backward",
	"turn_left": "Walk_Turn_Left",
	"turn_right": "Walk_Turn_Right",
	"jump": "Regular_Jump",
	"fall": "Fall2",
	"reload": "Standing_Reload",
	"reload_run": "Running_Reload",
	"run_and_gun": "Run_and_Shoot",
	"melee": "Punch_Combo",
	"melee_1": "Punch_Combo_1",
	"melee_3": "Punch_Combo_3",
	"melee_5": "Punch_Combo_5",
	"hit_melee": "Face_Punch_Reaction",
	"hit_gun": "Gunshot_Reaction",
	"get_up": "Stand_Up4",
	"wave": "Big_Wave_Hello",
	"wave_one": "Wave_One_Hand",
	"talk": "Talk_Passionately",
	"talk_open": "Talk_with_Hands_Open",
	"talk_raised": "Talk_with_Left_Hand_Raised",
	"look_around": "Look_Around_Dumbfounded",
	"phone": "Phone_Call_Gesture",
	"phone_talk": "Phone_Conversation",
	"phone_walk": "Walking_with_Phone",
	"texting_walk": "Texting_Walk",
	"idle_var": "Shrug",
}

## Looping states. Everything else plays once and returns to locomotion.
const LOOPING := ["idle", "walk", "run", "run_alt", "fall", "walk_back"]

## Planar speed (m/s) at or below which the character reads as standing.
@export var idle_speed: float = 0.2
## Planar speed (m/s) at which locomotion switches from walk to run.
@export var run_speed: float = 6.5
## Crossfade time (s) between locomotion states.
@export var locomotion_blend: float = 0.18
## Default crossfade time (s) into a one-shot action.
@export var action_blend: float = 0.12
## Optional explicit AnimationPlayer; auto-found from the owner when left empty.
@export var animation_player: AnimationPlayer = null

var _ap: AnimationPlayer = null
var _mode: int = Mode.GROUND
var _loco: String = ""  # canonical locomotion clip currently requested
var _aim_moving: bool = false  # last aim stance: looped (moving) vs frozen (standing)
var _resolved: Dictionary = {}  # canonical -> actual AnimationPlayer clip name


func _ready() -> void:
	_ap = animation_player if animation_player != null else _find_player()
	if _ap == null:
		push_warning("MeshyAnimController: no AnimationPlayer found under owner")
		return
	_resolve_clips()
	_apply_loops()
	_ap.animation_finished.connect(_on_finished)
	_play("idle")
	_mode = Mode.GROUND


## Call every frame from the owner. speed is the planar (XZ) velocity length in
## m/s; grounded is false while airborne. While a one-shot action is playing this
## is ignored until the action finishes, so triggered moves are not cut off.
func update_locomotion(speed: float, grounded: bool) -> void:
	if _ap == null or _mode == Mode.ACTION:
		return
	if not grounded:
		if _mode != Mode.AIR:
			_mode = Mode.AIR
			if not _play("fall"):
				_play("jump")
		return
	# Leaving the air or a (possibly frozen) aim stance: clear the cached
	# locomotion clip so _ground always re-issues play(), which also unpauses the
	# AnimationPlayer if a standing aim had paused it on a held frame.
	if _mode == Mode.AIR or _mode == Mode.AIM:
		_loco = ""
	_mode = Mode.GROUND
	_ground(speed)


## Hold the run-and-gun aiming stance while the player aims. Standing freezes a
## settled gun-up frame (no leg shuffle or root-motion drift); moving loops the
## run-and-gun cycle so the legs carry the stance. A one-shot action (reload) is
## left to finish — the caller re-aims once it ends. Call every frame the player
## is aiming, in place of update_locomotion; clearing aim simply routes back to
## update_locomotion, which resumes locomotion from the held pose.
func aim(speed: float) -> void:
	if _ap == null or _mode == Mode.ACTION or not has_clip(AIM_CLIP):
		return
	var clip_name: String = _resolved[AIM_CLIP]
	var moving := speed > idle_speed
	if _mode != Mode.AIM:
		_mode = Mode.AIM
		_aim_moving = moving
		if moving:
			_play(AIM_CLIP, action_blend)
		else:
			_freeze_aim(clip_name)
		return
	if moving != _aim_moving:
		_aim_moving = moving
		if moving:
			_ap.play(clip_name, action_blend)
		else:
			_freeze_aim(clip_name)
		return
	# Sustain a moving aim: the clip is LOOP_NONE (so it can serve as a one-shot
	# fire burst too), so replay it once it runs out to keep the gun up.
	if moving and not _ap.is_playing():
		_ap.play(clip_name)


## Snap to a representative gun-up frame and hold it, for a standing aim.
func _freeze_aim(clip_name: String) -> void:
	var clip := _ap.get_animation(clip_name)
	if clip == null:
		return
	_ap.play(clip_name)
	_ap.advance(clip.length * AIM_HOLD_FRACTION)
	_ap.pause()


## True while a one-shot action of `canonical` is the clip currently playing, so a
## caller can avoid restarting it every frame (e.g. sustained auto-fire).
func is_action_playing(canonical: String) -> bool:
	if _ap == null or _mode != Mode.ACTION or not _resolved.has(canonical):
		return false
	return _ap.current_animation == _resolved[canonical] and _ap.is_playing()


## Play a one-shot action by canonical name (melee, reload, wave, talk, react...).
## Returns false if the model does not carry that clip yet, so callers can branch
## without guessing what the current library contains. Locomotion resumes
## automatically when the action ends.
func play_action(canonical: String, blend: float = -1.0) -> bool:
	if _ap == null or not has_clip(canonical):
		return false
	_mode = Mode.ACTION
	_play(canonical, blend if blend >= 0.0 else action_blend)
	return true


## Takeoff helper for a jumping player: plays the jump clip and enters the air
## state. NPCs that never jump simply never call this.
func jump() -> void:
	if _ap == null:
		return
	_mode = Mode.AIR
	if not _play("jump"):
		_play("fall")


## True when the loaded model actually carries the clip behind a canonical name.
func has_clip(canonical: String) -> bool:
	return _resolved.has(canonical)


func _ground(speed: float) -> void:
	var want := "idle"
	if speed > run_speed:
		want = "run"
	elif speed > idle_speed:
		want = "walk"
	if want != _loco:
		_loco = want
		_play(want, locomotion_blend)


func _play(canonical: String, blend: float = -1.0) -> bool:
	if not _resolved.has(canonical):
		return false
	_ap.play(_resolved[canonical], blend)
	return true


func _on_finished(_anim: String) -> void:
	if _mode == Mode.ACTION:
		_mode = Mode.GROUND
		_loco = ""  # re-pick locomotion on the next update_locomotion call
		action_finished.emit(_canonical_of(_anim))


func _apply_loops() -> void:
	for canonical in _resolved:
		var clip := _ap.get_animation(_resolved[canonical])
		if clip == null:
			continue
		clip.loop_mode = Animation.LOOP_LINEAR if canonical in LOOPING else Animation.LOOP_NONE


func _canonical_of(clip_name: String) -> String:
	for canonical in _resolved:
		if _resolved[canonical] == clip_name:
			return canonical
	return clip_name


## Resolve each canonical name to the actual clip on the AnimationPlayer. Godot
## may import glTF clips under a library prefix ("Lib/Idle_4"), so match by exact
## name or by suffix. Warns with the available list if nothing matches, which is
## the signal that the import named them differently than the CLIPS table.
func _resolve_clips() -> void:
	var names := _ap.get_animation_list()
	for canonical in CLIPS:
		var want: String = CLIPS[canonical]
		for actual in names:
			if actual == want or actual.ends_with("/" + want):
				_resolved[canonical] = actual
				break
	if _resolved.is_empty():
		push_warning(
			"MeshyAnimController: no clips matched. AnimationPlayer has: " + ", ".join(names)
		)


func _find_player() -> AnimationPlayer:
	var root := owner if owner != null else get_parent()
	if root == null:
		return null
	for node in root.find_children("*", "AnimationPlayer", true, false):
		return node as AnimationPlayer
	return null
