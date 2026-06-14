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
## Free-look while driving: move the mouse to orbit the camera around the car and
## see the sides or what's behind — steering stays on the keyboard, so the view
## moves independently of the car. Mirrors OrbitCamera's mouse feel; after
## `look_return_delay` s without mouse input the view eases back behind the car.
@export var look_sensitivity: float = 0.003
## How far around the car the view can swing (rad); PI reaches straight behind.
@export var look_yaw_limit: float = PI
## Free-look pitch range (rad), layered on the chase cam's authored downward tilt.
@export var look_pitch_min: float = -0.5
@export var look_pitch_max: float = 0.5
## Seconds without mouse-look before the view eases back behind the car.
@export var look_return_delay: float = 0.6
## How fast the view eases back behind the car once idle (rad/s).
@export var look_return_rate: float = 3.5

var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite = null
var _base_distance: float = 0.0
var _roll: float = 0.0
# Free-look (yaw, pitch) offset from the chase pose, the idle timer that triggers
# its return, and the scene-authored SpringArm pitch the free-look pitch rides on.
var _look: Vector2 = Vector2.ZERO
var _look_idle: float = 0.0
var _base_pitch: float = 0.0

@onready var _arm: SpringArm3D = $SpringArm
@onready var _camera: Camera3D = $SpringArm/Camera


func _ready() -> void:
	_camera.fov = base_fov
	_shake_noise = FastNoiseLite.new()
	_base_distance = _arm.spring_length
	# The SpringArm carries an authored downward tilt; free-look pitch rides on it.
	_base_pitch = _arm.rotation.x


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
	_update_free_look(delta)
	# Bank into turns, scaled by speed so it only reads when the car is moving.
	var roll_target := CameraFeel.turn_roll(body.angular_velocity.y, blend, roll_gain, max_roll)
	_roll = CameraFeel.exp_smoothed(_roll, roll_target, roll_smoothing, delta)
	_update_shake(delta)


## Mouse free-look while driving: the accumulated offset orbits the rig so the
## player can check their sides and tail. Holding look_behind still does its
## cinematic swing straight back; otherwise, after a short idle the view eases
## home behind the car. The car is steered by the keyboard, so none of this moves
## it. Gated on `_camera.current`, so a parked car or the on-foot view is left at
## its neutral pose and a fresh entry always starts looking forward.
func _update_free_look(delta: float) -> void:
	if _camera.current and Input.is_action_pressed("look_behind"):
		_look_idle = 0.0
		_look.x = CameraFeel.exp_smoothed(_look.x, look_yaw_limit, look_behind_smoothing, delta)
		_look.y = CameraFeel.exp_smoothed(_look.y, 0.0, look_behind_smoothing, delta)
	elif _camera.current:
		_look_idle += delta
		if _look_idle >= look_return_delay:
			_look = CameraFeel.look_return(_look, look_return_rate, delta)
	else:
		_look = CameraFeel.look_return(_look, look_return_rate, delta)
		_look_idle = 0.0
	rotation.y = _look.x
	_arm.rotation.x = _base_pitch + _look.y


## Accumulate mouse motion into the free-look offset, but only while this is the
## active driving camera and the mouse is captured for gameplay (not a menu).
## Steering is keyboard, so this only swings the view — never the car.
func _unhandled_input(event: InputEvent) -> void:
	if not _camera.current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	_look_idle = 0.0
	_look = CameraFeel.look_offset(
		_look, motion.relative, look_sensitivity, look_yaw_limit, look_pitch_min, look_pitch_max
	)


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
