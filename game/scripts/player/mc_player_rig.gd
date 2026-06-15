class_name McPlayerRig
extends Node3D
## Player rig adapter. Presents the small API the player body already calls
## (animate, set_phone, and the foot_planted signal) but drives the merged Meshy
## MC model directly through MeshyAnimController: no CC0 clip, no retargeting. The
## visual, skeleton and all clips live on the imported GLB child named "Model".
##
## Swapping this scene in for the old character_rig means player.gd only changes
## the rig's type annotation; every call site keeps working.

signal foot_planted(is_left: bool)

## Yaw turn rate (rad/s) when reorienting toward travel/aim direction.
@export var turn_rate: float = 12.0
## Static yaw correction (degrees) for the model's authored forward axis. If the
## MC faces away from its travel direction, set this to 180.
@export var model_yaw_offset_deg: float = 0.0
## Carried-weapon attachment. The owner scene (player.tscn) parents a `GunMount`
## under this node; when true we move it onto the MC's right-hand bone so the gun
## tracks the hand through every clip instead of floating at a fixed body offset
## (which read as "gun behind the player" once the MC model replaced the old rig).
## Offset/rotation are exported because the imported hand bone's local axes are
## only knowable once posed; bullets come from the camera, so an imperfect held
## pose never affects aim.
@export var attach_weapon_to_hand: bool = true
@export var weapon_hand_bone: StringName = &"RightHand"
@export var weapon_hand_offset: Vector3 = Vector3(0.0, 0.0, -0.04)
@export var weapon_hand_rotation_deg: Vector3 = Vector3(-90.0, 0.0, 0.0)

var _ctrl: MeshyAnimController = null
var _facing: float = 0.0
var _aim_facing: bool = false
var _weapon_controller: Node = null
var _was_floor: bool = true
var _step_accum: float = 0.0
var _left_foot: bool = false
var _aiming: bool = false
var _planar_speed: float = 0.0


func _ready() -> void:
	var model := get_node_or_null("Model") as Node3D
	var ap: AnimationPlayer = null
	if model != null:
		_ground_to_feet(model)
		for node in model.find_children("*", "AnimationPlayer", true, false):
			ap = node as AnimationPlayer
			break
	if model != null and absf(model_yaw_offset_deg) > 0.01:
		model.rotation.y = deg_to_rad(model_yaw_offset_deg)
	_facing = rotation.y
	var body := get_parent()
	_aim_facing = body != null and body.is_in_group("player")
	_ctrl = MeshyAnimController.new()
	_ctrl.name = "AnimController"
	_ctrl.animation_player = ap
	add_child(_ctrl)
	_attach_weapon_to_hand(model)


## Move the carried GunMount onto the MC's right-hand bone so the gun follows the
## hand instead of hanging at the authored chest/hip offset. No-op when disabled,
## when no GunMount is parented under this rig, or when the model has no skeleton /
## hand bone — the gun then keeps its scene mount.
func _attach_weapon_to_hand(model: Node3D) -> void:
	if not attach_weapon_to_hand or model == null:
		return
	var gun_mount := get_node_or_null("GunMount") as Node3D
	if gun_mount == null:
		return
	var skel: Skeleton3D = null
	for node in model.find_children("*", "Skeleton3D", true, false):
		skel = node as Skeleton3D
		break
	if skel == null or skel.find_bone(weapon_hand_bone) < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponHand"
	skel.add_child(attachment)
	attachment.bone_name = weapon_hand_bone
	# The imported MC skeleton is authored at 0.01 scale, which a BoneAttachment
	# inherits and would shrink the gun ~100x (invisible) with offsets in the wrong
	# units. Cancel it with an intermediate node so the held gun renders at world
	# scale and the offset/rotation below stay in normal metres/degrees.
	var bone_scale := skel.global_transform.basis.get_scale()
	var unscale := Node3D.new()
	unscale.name = "WeaponScale"
	attachment.add_child(unscale)
	unscale.scale = Vector3(
		1.0 / maxf(bone_scale.x, 0.0001),
		1.0 / maxf(bone_scale.y, 0.0001),
		1.0 / maxf(bone_scale.z, 0.0001)
	)
	var rotation_rad := Vector3(
		deg_to_rad(weapon_hand_rotation_deg.x),
		deg_to_rad(weapon_hand_rotation_deg.y),
		deg_to_rad(weapon_hand_rotation_deg.z)
	)
	gun_mount.get_parent().remove_child(gun_mount)
	unscale.add_child(gun_mount)
	gun_mount.transform = Transform3D(Basis.from_euler(rotation_rad), weapon_hand_offset)


## Drive locomotion from the player body. Signature matches the old AnimatedRig so
## player.gd is unchanged apart from the rig type.
func animate(
	planar_velocity: Vector3,
	on_floor: bool,
	vertical_velocity: float,
	_is_climbing: bool,
	delta: float
) -> void:
	if _ctrl == null:
		return
	# Jump takeoff: was grounded, now leaving the floor with upward velocity.
	if _was_floor and not on_floor and vertical_velocity > 0.1:
		_ctrl.jump()
	_was_floor = on_floor
	_update_facing(planar_velocity, delta)
	var speed := planar_velocity.length()
	_planar_speed = speed
	# Aiming on the ground holds the run-and-gun stance; everything else (armed but
	# not aiming, airborne) uses normal locomotion with the gun in hand.
	if _aiming and on_floor and _ctrl.has_clip(MeshyAnimController.AIM_CLIP):
		_ctrl.aim(speed)
	else:
		_ctrl.update_locomotion(speed, on_floor)
	_tick_footsteps(speed, on_floor, delta)


## Turn the rig toward the weapon aim when armed, otherwise the travel direction,
## smoothly at turn_rate. The GunMount under this node follows the same yaw so the
## gun keeps pointing where the player aims. Ported from the old AnimatedRig.
func _update_facing(planar_velocity: Vector3, delta: float) -> void:
	var target := AnimRouter.facing_target(planar_velocity, _aim_yaw())
	if is_nan(target):
		return
	_facing = AnimRouter.rotate_toward_angle(_facing, target, turn_rate * delta)
	rotation.y = _facing


## Aim yaw from the player's WeaponController, NAN while holstered or for non-player
## owners (which then face their travel direction).
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


## Phone gesture. Raising plays the phone clip; lowering lets locomotion resume on
## its own once the one-shot ends.
func set_phone(raised: bool) -> void:
	if _ctrl != null and raised:
		_ctrl.play_action("phone")


## Carried-weapon pose, pushed each frame by the player's WeaponController (same
## contract as the old AnimatedRig). Armed-but-not-aiming keeps normal locomotion
## with the gun in hand; disarming also drops any aim so the stance can't stick.
func set_armed(armed: bool) -> void:
	if not armed:
		_aiming = false


## Raise/lower the aim stance. The MC is a run-and-gun rig with no static aim clip,
## so animate() holds the Run_and_Shoot stance while this is set (frozen standing,
## looped moving). pitch is unused: the model has no up/down aim variants, and
## bullets come from the camera regardless of the held pose.
func set_aiming(active: bool, _pitch: float) -> void:
	_aiming = active


## Fire feedback. While aiming, the gun is already raised, so the muzzle flash and
## recoil (driven by the WeaponController) carry the shot and the held stance is
## left untouched. Hip-firing snaps into a brief run-and-gun burst so the gun still
## comes up; it is not restarted mid-burst so sustained auto-fire stays smooth.
func play_shoot() -> void:
	if _ctrl == null or _aiming:
		return
	if not _ctrl.is_action_playing(MeshyAnimController.AIM_CLIP):
		_ctrl.play_action(MeshyAnimController.AIM_CLIP)


## Reload one-shot: the standing clip when settled, the running clip when on the
## move, so reloading mid-sprint doesn't snap the legs to a halt. Locomotion (or
## the aim stance, if still aiming) resumes automatically when the clip ends.
func play_reload() -> void:
	if _ctrl == null:
		return
	if _planar_speed > _ctrl.idle_speed and _ctrl.has_clip("reload_run"):
		_ctrl.play_action("reload_run")
	else:
		_ctrl.play_action("reload")


## Synthesise footstep beats from the gait, since the Meshy clips carry no
## foot-plant tracks. Cadence shortens with speed; the player's step audio listens
## to foot_planted exactly as before, so audio is not lost in the swap.
func _tick_footsteps(speed: float, on_floor: bool, delta: float) -> void:
	if not on_floor or speed < 0.3:
		_step_accum = 0.6  # primed to step on the next stride
		return
	_step_accum += delta
	var interval := clampf(2.2 / maxf(speed, 0.1), 0.22, 0.6)
	if _step_accum >= interval:
		_step_accum = 0.0
		_left_foot = not _left_foot
		foot_planted.emit(_left_foot)


## Shift the model so its lowest mesh vertex rests at the rig origin (the player
## capsule's feet, which sit at this node's origin), whatever the import pivot, so
## the MC does not sink into or float above the ground.
func _ground_to_feet(model: Node3D) -> void:
	var inv := global_transform.affine_inverse()
	var box := AABB()
	var seen := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		if m.mesh == null:
			continue
		var local := inv * m.global_transform * m.get_aabb()
		if seen:
			box = box.merge(local)
		else:
			box = local
			seen = true
	if seen:
		model.position.y -= box.position.y
