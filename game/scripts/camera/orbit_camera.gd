class_name OrbitCamera
extends Node3D
## Mouse-look camera rig: this node yaws, the SpringArm child pitches.
##
## The SpringArm keeps the camera from clipping through world geometry
## (its collision mask excludes the player's layer).

const PITCH_MIN: float = -1.2
const PITCH_MAX: float = 0.5

@export var sensitivity: float = 0.003
## Gamepad right-stick look. Sensitivity is peak turn rate (rad/s) at full
## deflection; deadzone and exponent shape the stick via StickInput so a flick
## and a fine nudge both feel right (mouse stays on `sensitivity` above).
@export var stick_sensitivity: float = 2.6
@export_range(0.0, 0.9) var stick_deadzone: float = 0.18
@export_range(1.0, 4.0) var stick_exponent: float = 1.8
## Over-the-shoulder framing: the arm pivot sits slightly right of the spine.
@export var shoulder_offset: Vector3 = Vector3(0.55, 0.0, 0.0)
@export var base_fov: float = 75.0
## Extra FOV blended in at full sprint speed for a sense of acceleration.
@export var sprint_fov_kick: float = 9.0
@export var fov_smoothing: float = 8.0
## Speeds (horizontal m/s) mapping to 0% and 100% of the FOV kick — keep in
## sync with Player.walk_speed / Player.sprint_speed.
@export var fov_walk_speed: float = 5.0
@export var fov_sprint_speed: float = 8.5
## Field of view while aiming down sights; the view eases to this and the
## sprint FOV kick is suppressed for the duration.
@export var aim_fov: float = 55.0
@export var aim_smoothing: float = 12.0
## How fast a recoil kick eases back to zero (1/s).
@export var recoil_recovery: float = 9.0
## Trauma-based shake (gunfire/impacts/landings call add_shake). Max per-axis
## angles (rad) at full trauma; trauma decays at shake_decay/s and the offset is
## trauma^shake_exponent so light hits stay subtle. Applied to the leaf camera
## so it never fights look/recoil. shake_frequency sets how buzzy it reads.
@export var shake_max_angles: Vector3 = Vector3(0.05, 0.04, 0.06)
@export var shake_decay: float = 1.4
@export_range(1.0, 4.0) var shake_exponent: float = 2.0
@export var shake_frequency: float = 18.0
## Extra FOV (deg) widened at full trauma so a big shake also punches the view.
@export var shake_fov_punch: float = 5.0
## Cinematic depth of field: geometry past dof_far_distance (easing over
## dof_far_transition) blurs gently so the eye reads depth and the distant city
## hazes off while the foreground stays sharp. Set dof_blur_amount to 0 to off.
@export var dof_blur_amount: float = 0.06
@export var dof_far_distance: float = 55.0
@export var dof_far_transition: float = 45.0
## Auto-recenter: after recenter_delay seconds without look input, the camera
## eases (recenter_rate rad/s) behind the travel direction while moving faster
## than recenter_min_speed — so a gamepad player isn't forced to ride the stick.
@export var recenter_delay: float = 1.0
@export var recenter_rate: float = 2.2
@export var recenter_min_speed: float = 1.5

var _pitch: float = 0.0
var _recoil: float = 0.0
var _aiming: bool = false
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite = null
var _look_idle: float = 0.0

@onready var _arm: SpringArm3D = $SpringArm
@onready var _camera: Camera3D = $SpringArm/Camera


func _ready() -> void:
	_arm.position = shoulder_offset
	_camera.fov = base_fov
	_pitch = _arm.rotation.x
	_shake_noise = FastNoiseLite.new()
	_apply_camera_attributes()


## Attach far-field depth of field to the camera for a cinematic depth cue.
## Code-driven (not the scene) so the camera rig stays self-contained.
func _apply_camera_attributes() -> void:
	if dof_blur_amount <= 0.0:
		return
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = dof_far_distance
	attrs.dof_blur_far_transition = dof_far_transition
	attrs.dof_blur_amount = dof_blur_amount
	_camera.attributes = attrs


## Hold the camera in the tighter aim FOV. WeaponController sets this each frame
## while the aim button is held.
func set_aiming(value: bool) -> void:
	_aiming = value


## Kick the view up by `amount` radians; it eases back via recoil_recovery so a
## burst climbs and then re-settles on the original aim.
func add_recoil(amount: float) -> void:
	_recoil += amount


## Add camera-shake trauma in [0, 1] from a gameplay event; scale to its
## violence (a pistol shot is a tap, a car crash is a jolt). Trauma accumulates
## and decays in _update_shake.
func add_shake(amount: float) -> void:
	_trauma = CameraShake.add(_trauma, amount)


## Re-activate this rig's camera (e.g. after stepping out of a vehicle).
func make_current() -> void:
	_camera.current = true


func _physics_process(delta: float) -> void:
	var body := get_parent() as CharacterBody3D
	if body == null:
		return
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	var blend := CameraFeel.sprint_blend(speed, fov_walk_speed, fov_sprint_speed)
	var target := CameraFeel.fov_for_blend(base_fov, sprint_fov_kick, blend)
	var smoothing := fov_smoothing
	if _aiming:
		target = aim_fov
		smoothing = aim_smoothing
	target += shake_fov_punch * CameraShake.shake_amount(_trauma, shake_exponent)
	_camera.fov = CameraFeel.exp_smoothed(_camera.fov, target, smoothing, delta)

	_apply_stick_look(delta)
	_update_recenter(body, delta)
	_recoil = move_toward(_recoil, 0.0, recoil_recovery * delta)
	_arm.rotation.x = clampf(_pitch, PITCH_MIN, PITCH_MAX) + _recoil
	_update_shake(delta)


## After a spell with no look input, ease the yaw behind the player's travel
## direction (only while moving and not aiming) so the view follows without the
## player having to steer it — important once a gamepad is driving.
func _update_recenter(body: CharacterBody3D, delta: float) -> void:
	_look_idle += delta
	if _aiming or _look_idle < recenter_delay:
		return
	if Vector2(body.velocity.x, body.velocity.z).length() < recenter_min_speed:
		return
	var target := CameraFeel.recenter_yaw(body.velocity.x, body.velocity.z)
	rotation.y = CameraFeel.approach_angle(rotation.y, target, recenter_rate * delta)


## Decay trauma and apply the resulting shake as a small rotation on the leaf
## camera (isolated from yaw/pitch/recoil). Decorrelated noise per axis comes
## from sampling the noise field at separate offsets along an advancing time.
func _update_shake(delta: float) -> void:
	_trauma = CameraShake.decay(_trauma, shake_decay, delta)
	if _trauma <= 0.0:
		_camera.rotation = Vector3.ZERO
		return
	_shake_time += delta * shake_frequency
	var noise := Vector3(
		_shake_noise.get_noise_2d(_shake_time, 0.0),
		_shake_noise.get_noise_2d(_shake_time, 100.0),
		_shake_noise.get_noise_2d(_shake_time, 200.0)
	)
	_camera.rotation = CameraShake.angular_offset(_trauma, shake_exponent, shake_max_angles, noise)


## Gamepad right-stick look, read as continuous axis state each frame (unlike
## mouse motion, which arrives as discrete events). Shares the yaw/pitch model
## and pitch clamp with mouse-look so both feel identical.
func _apply_stick_look(delta: float) -> void:
	var raw := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	var look := StickInput.look_delta(raw, stick_deadzone, stick_exponent, stick_sensitivity, delta)
	if look == Vector2.ZERO:
		return
	_look_idle = 0.0
	rotation.y -= look.x
	_pitch = clampf(_pitch - look.y, PITCH_MIN, PITCH_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	_look_idle = 0.0
	rotation.y -= motion.relative.x * sensitivity
	_pitch = clampf(_pitch - motion.relative.y * sensitivity, PITCH_MIN, PITCH_MAX)
