class_name ChaseCamera
extends Node3D
## Vehicle chase camera pivot: rides the car body, eases FOV + pull-back with
## speed (reusing CameraFeel's pure math), banks gently into turns, and smoothly
## swings 180° while the look-behind action is held — cinematic, not a hard cut.

@export var base_fov: float = 75.0
## Extra FOV blended in at high speed for a sense of velocity.
@export var speed_fov_kick: float = 12.0
@export var fov_smoothing: float = 6.0
## Speeds (m/s) mapping to 0% and 100% of the FOV kick.
@export var fov_low_speed: float = 8.0
@export var fov_high_speed: float = 35.0
## How fast the rig swings to/from the 180° look-behind (higher = snappier). The
## sweep is smoothed so it reads cinematic instead of an instant cut.
@export var look_behind_smoothing: float = 12.0
## Speed-scaled bank into turns: radians of roll per rad/s of yaw, capped, eased.
@export var roll_gain: float = 0.05
@export var max_roll: float = 0.08
@export var roll_smoothing: float = 7.0
## Crash shake: peak per-axis angles (rad) at full trauma, decay rate (1/s), a
## non-linear exponent, and noise speed. The car feeds add_shake on impact.
@export var shake_max_angles: Vector3 = Vector3(0.06, 0.05, 0.08)
@export var shake_decay: float = 1.6
@export_range(1.0, 4.0) var shake_exponent: float = 2.0
@export var shake_frequency: float = 20.0
## Speed pull-back: extra SpringArm distance (m) eased in at full speed blend for
## a sense of velocity. The base distance is the scene-authored arm length.
@export var distance_kick: float = 2.2
@export var distance_smoothing: float = 5.0

var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite = null
var _base_distance: float = 0.0
var _roll: float = 0.0

@onready var _arm: SpringArm3D = $SpringArm
@onready var _camera: Camera3D = $SpringArm/Camera


func _ready() -> void:
	_camera.fov = base_fov
	_shake_noise = FastNoiseLite.new()
	_base_distance = _arm.spring_length


## Add crash-shake trauma in [0, 1]; the car scales this to the collision force.
func add_shake(amount: float) -> void:
	_trauma = CameraShake.add(_trauma, amount)


func _physics_process(delta: float) -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	var speed := body.linear_velocity.length()
	var blend := CameraFeel.sprint_blend(speed, fov_low_speed, fov_high_speed)
	var target := CameraFeel.fov_for_blend(base_fov, speed_fov_kick, blend)
	_camera.fov = CameraFeel.exp_smoothed(_camera.fov, target, fov_smoothing, delta)
	_arm.spring_length = CameraFeel.exp_smoothed(
		_arm.spring_length, _base_distance + distance_kick * blend, distance_smoothing, delta
	)
	# Smoothly swing to/from the 180° look-behind instead of cutting instantly.
	var look_target := PI if Input.is_action_pressed("look_behind") else 0.0
	rotation.y = CameraFeel.exp_smoothed(rotation.y, look_target, look_behind_smoothing, delta)
	# Bank into turns, scaled by speed so it only reads when the car is moving.
	var roll_target := CameraFeel.turn_roll(body.angular_velocity.y, blend, roll_gain, max_roll)
	_roll = CameraFeel.exp_smoothed(_roll, roll_target, roll_smoothing, delta)
	_update_shake(delta)


## Apply the current turn-bank roll plus any decaying crash jolt to the leaf
## camera (isolated from the rig's look-behind yaw), sampling decorrelated noise
## per axis. Roll is the steady base; shake adds on top.
func _update_shake(delta: float) -> void:
	var base := Vector3(0.0, 0.0, _roll)
	_trauma = CameraShake.decay(_trauma, shake_decay, delta)
	if _trauma <= 0.0:
		_camera.rotation = base
		return
	_shake_time += delta * shake_frequency
	var noise := Vector3(
		_shake_noise.get_noise_2d(_shake_time, 0.0),
		_shake_noise.get_noise_2d(_shake_time, 100.0),
		_shake_noise.get_noise_2d(_shake_time, 200.0)
	)
	_camera.rotation = (
		base + CameraShake.angular_offset(_trauma, shake_exponent, shake_max_angles, noise)
	)
