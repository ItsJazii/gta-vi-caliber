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

var _ctrl: MeshyAnimController = null
var _was_floor: bool = true
var _step_accum: float = 0.0
var _left_foot: bool = false


func _ready() -> void:
	var model := get_node_or_null("Model") as Node3D
	var ap: AnimationPlayer = null
	if model != null:
		_ground_to_feet(model)
		for node in model.find_children("*", "AnimationPlayer", true, false):
			ap = node as AnimationPlayer
			break
	_ctrl = MeshyAnimController.new()
	_ctrl.name = "AnimController"
	_ctrl.animation_player = ap
	add_child(_ctrl)


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
	var speed := planar_velocity.length()
	_ctrl.update_locomotion(speed, on_floor)
	_tick_footsteps(speed, on_floor, delta)


## Phone gesture. Raising plays the phone clip; lowering lets locomotion resume on
## its own once the one-shot ends.
func set_phone(raised: bool) -> void:
	if _ctrl != null and raised:
		_ctrl.play_action("phone")


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
