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

## Combat state-machine node names, layered on top of the locomotion states in
## AnimRouter. Aim is a held pose; the others are one-shots paced by
## _action_time; Death is a terminal hold for downed NPCs.
const STATE_PISTOL_AIM := &"PistolAim"
const STATE_PISTOL_SHOOT := &"PistolShoot"
const STATE_PISTOL_RELOAD := &"PistolReload"
const STATE_PUNCH_JAB := &"PunchJab"
const STATE_PUNCH_CROSS := &"PunchCross"
const STATE_HIT := &"Hit"
const STATE_DEATH := &"Death"

## Loop modes forced onto controlled clips after import — the source library
## leaves them at the glTF default (looping), which makes a held death pose
## re-collapse forever (the "corpse flying" bug). The death and hit reactions
## must settle on their final frame; locomotion stays looping.
const CLIP_LOOP_MODES := {
	&"Death01": Animation.LOOP_NONE,
	&"Hit_Chest": Animation.LOOP_NONE,
	&"Walk": Animation.LOOP_LINEAR,
	&"Jog_Fwd": Animation.LOOP_LINEAR,
	&"Sprint": Animation.LOOP_LINEAR,
	&"Idle": Animation.LOOP_LINEAR,
}

## Press the lowest posed bone this far (m) into the floor when settling a corpse,
## so the skinned surface rests flat instead of leaving a hairline hover gap.
const CORPSE_GROUND_SINK := 0.06

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
## Carried-weapon attachment. When true, a `GunMount` node that the owner scene
## parents under this rig (player.tscn) is moved onto the right-hand bone of the
## retargeted skeleton so the gun tracks the aim/shoot hand instead of floating
## at a fixed chest offset. Offsets are exported because the imported hand bone's
## local axes are only knowable once posed, so the held pose can be dialed in
## from the editor without code changes; bullets always come from the camera, so
## an imperfect gun pose never affects aim.
@export var attach_weapon_to_hand: bool = true
@export var weapon_hand_offset: Vector3 = Vector3.ZERO
@export var weapon_hand_rotation_deg: Vector3 = Vector3(-90.0, 0.0, 0.0)
## Corpse fall (NPC death). The only death clip lays the body down through root
## translation, which the retarget strips (set_position_enabled(false)) — so the
## retargeted pose freezes standing and floating. On death we topple the visual
## about its feet to lie it flat, then clamp it to the floor. Pitch sign chooses
## the direction (negative = backward, as if shot); time is the topple duration.
@export var death_fall_time: float = 0.4
@export var death_fall_pitch_deg: float = -90.0

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
# Combat layer. The WeaponController pushes armed/aim each frame (aim drives the
# held PistolAim pose, blended by _aim_pitch); play_* fire one-shots that hold
# via _action/_action_time so a punch or shot plays out before locomotion
# resumes. _downed latches the terminal death pose for NPCs until revive().
var _armed: bool = false
var _aiming: bool = false
var _aim_pitch: float = 0.0
var _action: StringName = &""
var _action_time: float = 0.0
var _downed: bool = false
var _downed_elapsed: float = 0.0

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


## Corpse fall. The death clip stays upright and floating once the retarget strips
## its root translation, so a downed body has to be laid down here: topple the
## visual about its feet over death_fall_time, then clamp the lowest posed bone to
## the floor so the body rests flat on the ground. Idle while alive.
func _process(delta: float) -> void:
	if not _downed:
		if rotation.x != 0.0:
			rotation.x = 0.0
		if position.y != 0.0:
			position.y = 0.0
		_downed_elapsed = 0.0
		return
	_downed_elapsed += delta
	var fall := clampf(_downed_elapsed / maxf(death_fall_time, 0.01), 0.0, 1.0)
	rotation.x = deg_to_rad(death_fall_pitch_deg) * smoothstep(0.0, 1.0, fall)
	_settle_corpse_on_floor()


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
	_tree.set("parameters/%s/blend_position" % STATE_PISTOL_AIM, _aim_pitch)

	_update_facing(planar_velocity, delta)

	if _action != &"":
		_action_time -= delta
		if _action_time <= 0.0:
			_action = &""

	var current := _playback.get_current_node()
	var loco_target := AnimRouter.travel_target(state, current, planar_speed, land_skip_speed)
	var target := _combat_target(current, loco_target)
	if current != target:
		_playback.travel(target)


## Same contract as CharacterAnimator.set_phone: Player mirrors the raised /
## pocketed phone here. The UAL Standard tier has no phone-hold clip, so the
## flag is state-only for now — the phone's gameplay rules (sprint and vehicle
## gating) live in Player and keep working; a one-handed holding pose can slot
## in when a suitable clip exists.
func set_phone(raised: bool) -> void:
	_phone_raised = raised


## Push the carried-weapon state from the WeaponController. `armed` keeps the
## gun out; `aiming` raises the held aim pose, blended toward up/down by `pitch`
## in [-1, 1] (camera look angle). State-only — no clip exists for armed walking,
## so an armed-but-not-aiming character uses normal locomotion with the gun in
## hand.
func set_armed(armed: bool) -> void:
	_armed = armed
	if not armed:
		_aiming = false


func set_aiming(active: bool, pitch: float) -> void:
	_aiming = active
	_aim_pitch = clampf(pitch, -1.0, 1.0)


## Play the pistol fire one-shot (hip-fire; while aiming the held pose plus the
## camera recoil already sell the shot, so it simply restarts the clip).
func play_shoot() -> void:
	if _downed:
		return
	_start_action(STATE_PISTOL_SHOOT, &"Pistol_Shoot")


func play_reload() -> void:
	if _downed:
		return
	_start_action(STATE_PISTOL_RELOAD, &"Pistol_Reload")


## Throw a punch one-shot; alternates jab/cross by the (1-based) combo step.
func play_punch(combo: int) -> void:
	if _downed:
		return
	if combo % 2 == 0:
		_start_action(STATE_PUNCH_CROSS, &"Punch_Cross")
	else:
		_start_action(STATE_PUNCH_JAB, &"Punch_Jab")


## A flinch one-shot for taking a hit (mostly NPCs). Skipped mid-action so a
## burst of fire can't stutter-lock the rig restarting the clip every frame.
func play_hit() -> void:
	if _downed or _action != &"":
		return
	_start_action(STATE_HIT, &"Hit_Chest")


## Drop into the terminal death pose and hold it until revive(). The lone death
## clip lays the body down through root translation the retarget strips, so playing
## it just curls the legs up in the air (read as "floating / upside-down"). Instead
## we freeze the skinned pose where the NPC stood and topple the whole visual flat
## via _process, which lands a stable, clearly-prone corpse.
func play_death() -> void:
	if _downed:
		return
	_downed = true
	_action = &""
	if _tree != null:
		_tree.active = false


## Clear the death pose on respawn and return to locomotion.
func revive() -> void:
	_downed = false
	_action = &""
	_downed_elapsed = 0.0
	rotation.x = 0.0
	position.y = 0.0
	if _tree != null:
		_tree.active = true
	if _playback != null:
		_playback.travel(AnimRouter.STATE_MOVE)


## Lower the visual so the lowest posed bone rests on the floor as the body topples
## over on death. Self-correcting: it converges in a single step and tracks the
## pose each frame, so the body stays grounded through the fall instead of hovering
## or clipping. Floor is the owning body's origin (its capsule rests feet-down).
func _settle_corpse_on_floor() -> void:
	if _retargeted_skeleton == null:
		return
	var body := get_parent() as Node3D
	if body == null:
		return
	var skel_xform := _retargeted_skeleton.global_transform
	var lowest := INF
	for i in _retargeted_skeleton.get_bone_count():
		var bone_y: float = (skel_xform * _retargeted_skeleton.get_bone_global_pose(i).origin).y
		lowest = minf(lowest, bone_y)
	if is_inf(lowest):
		return
	position.y -= lowest - (body.global_position.y - CORPSE_GROUND_SINK)


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
	# Pin loop modes so the imported default can't leave the death/hit reactions
	# looping (deep-duplicate first so the shared cached library is untouched).
	for clip_name: StringName in CLIP_LOOP_MODES:
		if not library.has_animation(clip_name):
			continue
		var looped: Animation = library.get_animation(clip_name).duplicate(true)
		looped.loop_mode = CLIP_LOOP_MODES[clip_name]
		library.add_animation(clip_name, looped)
	_anim_player.add_animation_library(&"", library)
	source.free()


func _install_retargeted_visual() -> void:
	var source_skeleton := _source_skeleton()
	var packed := _selected_visual_scene()
	if source_skeleton == null or packed == null:
		push_error("AnimatedRig: missing source skeleton or visible character scene")
		return

	# Hide the rig's own source/visual meshes so only the retargeted skin shows,
	# but never the carried weapon (GunMount + children) the owner parents under
	# us — the WeaponController owns that show/hide on its own.
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if _is_weapon_mesh(mesh):
			continue
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
	_attach_weapon_to_hand()


## True when `node` belongs to a carried weapon (lives under a `GunMount`), so
## the mesh-hiding pass leaves it visible — the WeaponController shows/hides it.
func _is_weapon_mesh(node: Node) -> bool:
	var current := node
	while current != null and current != self:
		if current.name == &"GunMount":
			return true
		current = current.get_parent()
	return false


## Move the carried GunMount onto the right-hand bone so it follows the aim and
## shoot poses. No-op when disabled, when this rig carries no weapon (the NPC
## crowd), or when the hand bone is absent — the gun then keeps its scene mount.
func _attach_weapon_to_hand() -> void:
	if not attach_weapon_to_hand or _retargeted_skeleton == null:
		return
	var gun_mount := get_node_or_null("GunMount") as Node3D
	if gun_mount == null:
		return
	if _retargeted_skeleton.find_bone(&"hand_r") < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponHand"
	_retargeted_skeleton.add_child(attachment)
	attachment.bone_name = "hand_r"
	var rotation_rad := Vector3(
		deg_to_rad(weapon_hand_rotation_deg.x),
		deg_to_rad(weapon_hand_rotation_deg.y),
		deg_to_rad(weapon_hand_rotation_deg.z)
	)
	gun_mount.get_parent().remove_child(gun_mount)
	attachment.add_child(gun_mount)
	gun_mount.transform = Transform3D(Basis.from_euler(rotation_rad), weapon_hand_offset)


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
	_add_combat_states(machine)
	return machine


## Layer the combat nodes onto the locomotion machine: a pitch-blended pistol
## aim pose plus punch/shoot/reload/hit one-shots and a death pose. Each one-shot
## is wired both ways to Move and to the aim pose so a swing or shot can be
## entered and left (manual travel paced by _action_time) with a crossfade from
## whatever the fighter was doing.
func _add_combat_states(machine: AnimationNodeStateMachine) -> void:
	var aim := AnimationNodeBlendSpace1D.new()
	aim.add_blend_point(_clip(&"Pistol_Aim_Down"), -1.0)
	aim.add_blend_point(_clip(&"Pistol_Aim_Neutral"), 0.0)
	aim.add_blend_point(_clip(&"Pistol_Aim_Up"), 1.0)
	machine.add_node(STATE_PISTOL_AIM, aim)
	machine.add_node(STATE_PISTOL_SHOOT, _clip(&"Pistol_Shoot"))
	machine.add_node(STATE_PISTOL_RELOAD, _clip(&"Pistol_Reload"))
	machine.add_node(STATE_PUNCH_JAB, _clip(&"Punch_Jab"))
	machine.add_node(STATE_PUNCH_CROSS, _clip(&"Punch_Cross"))
	machine.add_node(STATE_HIT, _clip(&"Hit_Chest"))
	machine.add_node(STATE_DEATH, _clip(&"Death01"))

	machine.add_transition(AnimRouter.STATE_MOVE, STATE_PISTOL_AIM, _transition(0.18))
	machine.add_transition(STATE_PISTOL_AIM, AnimRouter.STATE_MOVE, _transition(0.18))
	for state: StringName in [
		STATE_PISTOL_SHOOT, STATE_PISTOL_RELOAD, STATE_PUNCH_JAB, STATE_PUNCH_CROSS, STATE_HIT
	]:
		machine.add_transition(AnimRouter.STATE_MOVE, state, _transition(0.06))
		machine.add_transition(STATE_PISTOL_AIM, state, _transition(0.06))
		machine.add_transition(state, AnimRouter.STATE_MOVE, _transition(0.12))
		machine.add_transition(state, STATE_PISTOL_AIM, _transition(0.12))
	machine.add_transition(AnimRouter.STATE_MOVE, STATE_DEATH, _transition(0.08))
	machine.add_transition(STATE_PISTOL_AIM, STATE_DEATH, _transition(0.08))


## The state-machine node to play this frame, combat taking priority over
## locomotion: the death hold while downed, the current one-shot until its timer
## elapses, then the held aim pose while aiming on the ground, else `loco_target`.
func _combat_target(current: StringName, loco_target: StringName) -> StringName:
	if _downed:
		return STATE_DEATH
	if _action != &"":
		return current
	if _armed and _aiming and _on_floor:
		return STATE_PISTOL_AIM
	return loco_target


## Begin a combat one-shot: travel to its node and lock locomotion travel for the
## clip's length (animate() counts _action_time down, then resumes routing).
func _start_action(state: StringName, clip_name: StringName) -> void:
	_action = state
	_action_time = maxf(_clip_length(clip_name), 0.1)
	if _playback != null:
		_playback.travel(state)


func _clip_length(clip_name: StringName) -> float:
	if _anim_player != null and _anim_player.has_animation(clip_name):
		return _anim_player.get_animation(clip_name).length
	return 0.3


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
