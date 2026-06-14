class_name AnimatedRig
extends Node3D
## Skeletal character rig driven by an AnimationTree state machine.
##
## The player's replacement for the procedural CharacterAnimator (issue #1):
## same animate() input contract fed by Player after move_and_slide. Imported
## CC0 clips play on a hidden Quaternius source skeleton, then Godot 4.6's
## RetargetModifier3D transfers those poses to the selected production visual.
## This keeps locomotion clips reusable across player and pedestrian models.

## Fired when a locomotion clip plants a foot on the ground. Player listens
## and re-emits its surface-typed `footstep` signal, so step audio is locked
## to the animation's actual foot strikes instead of a parallel stride clock.
signal foot_planted(is_left: bool)

## The shared clip library; its skeleton matches the base character's, so the
## imported animations resolve against our Model without retargeting.
const ANIM_LIBRARY_SCENE := "res://assets/characters/universal_animations/UAL1_Standard.glb"

const DEFAULT_VISUAL_SCENE := preload("res://assets/characters/coastal_residents/player.glb")

## Blend-space positions for the Move state, matching Locomotion.move_blend's
## axis: 0.0 standing, 0.5 at walk_speed, 1.0 at run_speed.
const BLEND_IDLE := 0.0
const BLEND_WALK := 0.5
const BLEND_JOG := 0.8
const BLEND_SPRINT := 1.0

## Trim windows for the jump one-shots (probed from the clips' pelvis
## curves): Jump_Start spends its first 0.30 s in an anticipation crouch the
## physics jump doesn't wait for, then extends into the air pose; Jump_Land's
## absorb is over by 0.60 s, the rest is a slow recovery the Move crossfade
## covers better.
const JUMP_START_OFFSET := 0.30
const JUMP_START_LENGTH := 0.45
const LAND_LENGTH := 0.60

## Foot-strike timestamps (s) per locomotion clip, probed from each clip's
## foot-bone height curves (the moment the foot reaches ground height and
## starts its stance sweep). Injected as method-track keys that call
## _on_foot_plant; the left-foot key at the Walk cycle's exact start is
## nudged to 0.01 s so it can't double-fire on loop wrap.
const FOOT_PLANT_KEYS := {
	&"Walk": {"blend_point": BLEND_WALK, "left": [0.01], "right": [0.667]},
	&"Jog_Fwd": {"blend_point": BLEND_JOG, "left": [0.023], "right": [0.49]},
	&"Sprint": {"blend_point": BLEND_SPRINT, "left": [0.017], "right": [0.35]},
}

## Blend points whose clips can claim a footstep; Idle has no plant keys.
const MOVING_BLEND_POINTS: PackedFloat32Array = [BLEND_WALK, BLEND_JOG, BLEND_SPRINT]

## Below this move blend the character is effectively stationary — plant
## events from residual low-weight clips are ignored.
const MIN_STEP_BLEND := 0.1

## Speeds must mirror the Player export values so blend thresholds agree.
@export var walk_speed: float = 5.0
@export var run_speed: float = 8.5
## Yaw turn rate (rad/s) when reorienting toward travel/aim direction.
@export var turn_rate: float = 12.0
## How fast the move blend eases toward its target (1/s).
@export var response_rate: float = 10.0
## Crossfade (s) between ground locomotion and the airborne state.
@export var air_xfade: float = 0.2
## Landing at or above this planar speed (m/s) skips the landing absorb and
## rolls straight back into locomotion, so moving landings don't foot-slide.
@export var land_skip_speed: float = 2.0
## Visible skinned model. When options are supplied, one is chosen per rig so
## the pedestrian crowd can mix the imported man and woman variants.
@export var visual_scene: PackedScene = DEFAULT_VISUAL_SCENE
@export var visual_scene_options: Array[PackedScene] = []

var _facing: float = 0.0
var _blend: float = 0.0
var _on_floor: bool = true
var _playback: AnimationNodeStateMachinePlayback = null
# When the owner is the player, face where the weapon aims (not where we
# move) so strafing reads as a third-person shooter. Mirrors CharacterAnimator.
var _aim_facing: bool = false
var _weapon_controller: Node = null
var _phone_raised: bool = false
var _retargeted_skeleton: Skeleton3D = null

@onready var _anim_player: AnimationPlayer = $AnimationPlayer
@onready var _tree: AnimationTree = $AnimationTree


func _ready() -> void:
	_facing = rotation.y
	var owner_body := get_parent()
	_aim_facing = owner_body != null and owner_body.is_in_group("player")
	_install_animations()
	_install_retargeted_visual()
	_tree.tree_root = _build_state_machine()
	_tree.active = true
	_playback = _tree.get("parameters/playback")
	_playback.start(AnimRouter.STATE_MOVE)


## Drive the rig for one physics frame from the character's current motion.
## Same contract as CharacterAnimator.animate: planar_velocity is world-space
## with y ignored; vertical_velocity tells a rising jump from a fall.
func animate(
	planar_velocity: Vector3,
	on_floor: bool,
	vertical_velocity: float,
	is_climbing: bool,
	delta: float
) -> void:
	var planar_speed := planar_velocity.length()
	_on_floor = on_floor
	var state := Locomotion.state_for(
		planar_speed, on_floor, vertical_velocity, is_climbing, walk_speed, run_speed
	)

	var total_speed := Vector3(planar_velocity.x, vertical_velocity, planar_velocity.z).length()
	var target_blend := AnimRouter.move_blend_value(
		planar_speed, total_speed, is_climbing, walk_speed, run_speed
	)
	_blend = move_toward(_blend, target_blend, response_rate * delta)
	_tree.set("parameters/Move/blend_position", _blend)

	_update_facing(planar_velocity, delta)

	var current := _playback.get_current_node()
	var target := AnimRouter.travel_target(state, current, planar_speed, land_skip_speed)
	if current != target:
		_playback.travel(target)


## Same contract as CharacterAnimator.set_phone: Player mirrors the raised /
## pocketed phone here. The UAL Standard tier has no phone-hold clip, so the
## flag is state-only for now — the phone's gameplay rules (sprint and vehicle
## gating) live in Player and keep working; a one-handed holding pose can slot
## in when a suitable clip exists.
func set_phone(raised: bool) -> void:
	_phone_raised = raised


func _update_facing(planar_velocity: Vector3, delta: float) -> void:
	var target := AnimRouter.facing_target(planar_velocity, _aim_yaw())
	if is_nan(target):
		return
	_facing = AnimRouter.rotate_toward_angle(_facing, target, turn_rate * delta)
	rotation.y = _facing


# Aim yaw from the player's WeaponController (NAN while holstered or for
# non-player owners, meaning travel-facing). Mirrors CharacterAnimator.
func _aim_yaw() -> float:
	if not _aim_facing:
		return NAN
	if _weapon_controller == null:
		var found := get_tree().get_nodes_in_group("weapon_controller")
		if found.is_empty():
			return NAN
		_weapon_controller = found[0]
	if _weapon_controller.has_method("facing_override"):
		return _weapon_controller.facing_override()
	return NAN


## Copy the clip library out of the imported animation-library scene into our
## AnimationPlayer. Both scenes share the Armature/Skeleton3D structure and
## bone names, so the tracks drive our skeleton without retargeting. The
## locomotion clips get foot-plant method-track keys injected into private
## duplicates, leaving the imported library untouched for other users.
func _install_animations() -> void:
	var packed: PackedScene = load(ANIM_LIBRARY_SCENE)
	if packed == null:
		push_error("AnimatedRig: cannot load animation library " + ANIM_LIBRARY_SCENE)
		return
	var source := packed.instantiate()
	var players := source.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("AnimatedRig: no AnimationPlayer inside " + ANIM_LIBRARY_SCENE)
		source.free()
		return
	var source_player: AnimationPlayer = players[0]
	var library: AnimationLibrary = source_player.get_animation_library(&"").duplicate()
	for clip_name: StringName in FOOT_PLANT_KEYS:
		var spec: Dictionary = FOOT_PLANT_KEYS[clip_name]
		var clip: Animation = library.get_animation(clip_name).duplicate(true)
		_add_plant_keys(clip, spec)
		library.add_animation(clip_name, clip)
	_anim_player.add_animation_library(&"", library)
	source.free()


func _install_retargeted_visual() -> void:
	var source_skeleton := _source_skeleton()
	var packed := _selected_visual_scene()
	if source_skeleton == null or packed == null:
		push_error("AnimatedRig: missing source skeleton or visible character scene")
		return

	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).visible = false

	var visual_root := packed.instantiate() as Node3D
	if visual_root == null:
		push_error("AnimatedRig: visible character scene has no Node3D root")
		return
	var skeletons := visual_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_error("AnimatedRig: visible character scene has no Skeleton3D")
		visual_root.free()
		return

	var target_skeleton := skeletons[0] as Skeleton3D
	var target_transform := _transform_to_ancestor(target_skeleton, visual_root)
	var missing := HumanoidRetarget.rename_target_skeleton(target_skeleton)
	if not missing.is_empty():
		push_warning("AnimatedRig: unmapped target bones: %s" % [missing])

	target_skeleton.get_parent().remove_child(target_skeleton)
	target_skeleton.owner = null
	target_skeleton.name = "RetargetedSkeleton"
	target_skeleton.transform = target_transform

	var modifier := RetargetModifier3D.new()
	modifier.name = "CharacterRetarget"
	modifier.profile = HumanoidRetarget.build_profile()
	modifier.set_position_enabled(false)
	modifier.set_scale_enabled(false)
	source_skeleton.add_child(modifier)
	modifier.add_child(target_skeleton)
	_retargeted_skeleton = target_skeleton
	_ground_visual_feet()
	visual_root.free()


## Lift the retargeted visual so its lowest vertex rests at the skeleton origin
## (the character's floor, which the rig places at the capsule feet), whatever
## the source model's pivot. Measured from the bind-pose mesh bounds in the
## retarget node's own space, so the figure stands on the ground instead of
## sinking through it, while animation foot-lift still reads above the ground.
func _ground_visual_feet() -> void:
	if _retargeted_skeleton == null:
		return
	var parent := _retargeted_skeleton.get_parent() as Node3D
	if parent == null:
		return
	var inv := parent.global_transform.affine_inverse()
	var box := AABB()
	var seen := false
	for node in _retargeted_skeleton.find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		if m.mesh == null:
			continue
		var local := inv * m.global_transform * m.get_aabb()
		if seen:
			box = box.merge(local)
		else:
			box = local
			seen = true
	if not seen:
		return
	# box.position.y is the lowest visible point relative to the skeleton origin;
	# subtracting it snaps that point onto the origin, correcting both a model
	# that sinks (bounds below) and one that floats (bounds above).
	_retargeted_skeleton.position.y -= box.position.y


func _source_skeleton() -> Skeleton3D:
	var skeletons := find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	return skeletons[0] as Skeleton3D


func _selected_visual_scene() -> PackedScene:
	if visual_scene_options.is_empty():
		return visual_scene
	return visual_scene_options[randi() % visual_scene_options.size()]


func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent() as Node3D
	while parent != null and parent != ancestor:
		result = parent.transform * result
		parent = parent.get_parent() as Node3D
	return result


## Append one method track per clip whose keys call _on_foot_plant (this
## script sits on the animation root, so path "." reaches it).
func _add_plant_keys(clip: Animation, spec: Dictionary) -> void:
	var track := clip.add_track(Animation.TYPE_METHOD)
	clip.track_set_path(track, NodePath("."))
	var blend_point: float = spec["blend_point"]
	for time: float in spec["left"]:
		clip.track_insert_key(
			track, time, {"method": &"_on_foot_plant", "args": [true, blend_point]}
		)
	for time: float in spec["right"]:
		clip.track_insert_key(
			track, time, {"method": &"_on_foot_plant", "args": [false, blend_point]}
		)


## Called by the injected method-track keys whenever a locomotion clip plants
## a foot. Every clip near the current blend position fires its own keys, so
## only the dominant clip's events pass, and only while actually moving on
## the ground in the Move state.
func _on_foot_plant(is_left: bool, blend_point: float) -> void:
	if not _on_floor or _blend < MIN_STEP_BLEND:
		return
	if _playback == null or _playback.get_current_node() != AnimRouter.STATE_MOVE:
		return
	var dominant := AnimRouter.dominant_blend_point(_blend, MOVING_BLEND_POINTS)
	if not is_equal_approx(dominant, blend_point):
		return
	foot_planted.emit(is_left)


## Build the locomotion state machine: a Move blend space (idle → walk → jog
## → sprint along Locomotion.move_blend's axis) plus the three-phase jump
## chain — JumpStart one-shot → Air loop → Land one-shot — with the
## one-shots trimmed to their useful windows and auto-advancing when done.
func _build_state_machine() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()

	var move := AnimationNodeBlendSpace1D.new()
	move.add_blend_point(_clip(&"Idle"), BLEND_IDLE)
	move.add_blend_point(_clip(&"Walk"), BLEND_WALK)
	move.add_blend_point(_clip(&"Jog_Fwd"), BLEND_JOG)
	move.add_blend_point(_clip(&"Sprint"), BLEND_SPRINT)
	machine.add_node(AnimRouter.STATE_MOVE, move)

	machine.add_node(
		AnimRouter.STATE_JUMP_START, _one_shot(&"Jump_Start", JUMP_START_OFFSET, JUMP_START_LENGTH)
	)
	machine.add_node(AnimRouter.STATE_AIR, _clip(&"Jump"))
	machine.add_node(AnimRouter.STATE_LAND, _one_shot(&"Jump_Land", 0.0, LAND_LENGTH))

	# Launch: quick cut into the start one-shot, which flows into the loop.
	machine.add_transition(AnimRouter.STATE_MOVE, AnimRouter.STATE_JUMP_START, _transition(0.1))
	machine.add_transition(AnimRouter.STATE_JUMP_START, AnimRouter.STATE_AIR, _auto_at_end(0.25))
	# Walking off a ledge skips the launch pose.
	machine.add_transition(AnimRouter.STATE_MOVE, AnimRouter.STATE_AIR, _transition(air_xfade))

	# Touchdown: absorb when slow (auto-recovers into Move), straight back
	# into locomotion when moving; short hops can land out of the start.
	machine.add_transition(AnimRouter.STATE_AIR, AnimRouter.STATE_LAND, _transition(0.1))
	machine.add_transition(AnimRouter.STATE_AIR, AnimRouter.STATE_MOVE, _transition(air_xfade))
	machine.add_transition(AnimRouter.STATE_JUMP_START, AnimRouter.STATE_LAND, _transition(0.1))
	machine.add_transition(AnimRouter.STATE_JUMP_START, AnimRouter.STATE_MOVE, _transition(0.15))
	machine.add_transition(AnimRouter.STATE_LAND, AnimRouter.STATE_MOVE, _auto_at_end(0.25))
	# Bunny hop: jumping during the absorb restarts the arc.
	machine.add_transition(AnimRouter.STATE_LAND, AnimRouter.STATE_JUMP_START, _transition(0.1))
	# Walking off a ledge mid-absorb: without this edge, a travel to Air has
	# to wait out the absorb and crossfade through Move while already airborne.
	machine.add_transition(AnimRouter.STATE_LAND, AnimRouter.STATE_AIR, _transition(0.15))
	return machine


func _clip(animation_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation_name
	return node


## A clip trimmed to [offset, offset + length] at natural speed, so the
## state machine sees a one-shot exactly as long as its useful window.
func _one_shot(animation_name: StringName, offset: float, length: float) -> AnimationNodeAnimation:
	var node := _clip(animation_name)
	node.use_custom_timeline = true
	node.start_offset = offset
	node.timeline_length = length
	node.stretch_time_scale = false
	return node


func _transition(xfade: float) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	return transition


## Fires by itself when the source one-shot reaches its end, crossfading
## into the destination over xfade seconds.
func _auto_at_end(xfade: float) -> AnimationNodeStateMachineTransition:
	var transition := _transition(xfade)
	transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	return transition
