class_name Car
extends VehicleBody3D
## Greybox drivable car. Idle until a driver enters (Player calls enter()), then
## reads move input as throttle/steer. Steering math is delegated to
## VehicleMotion and the engine/gearbox to Powertrain — both pure and
## unit-tested. The drivetrain runs a real torque curve through a multi-speed
## auto-shifting gearbox, so acceleration falls off as each gear tops out and
## recovers on the upshift, instead of one flat pull to top speed.

## Below this forward speed (m/s) a press of "back" engages reverse; above it the
## same press brakes the still-forward-rolling car instead.
const REVERSE_SPEED_THRESHOLD: float = 1.0
const GRAVITY: float = 9.81

## Peak crankshaft torque (N·m). Tuned with the gearing below so first gear
## launches this 300 kg greybox at a sporty ~10 m/s² rather than a rocket.
@export var peak_torque: float = 95.0
@export var idle_rpm: float = 850.0
## RPM where the torque curve peaks; the powerband centres here.
@export var peak_rpm: float = 4000.0
@export var redline_rpm: float = 6500.0
## Forward gear ratios, tallest (1st) to shortest (top). Multiplied by the final
## drive into wheel torque.
@export var gear_ratios: Array[float] = [3.40, 2.10, 1.40, 1.05, 0.85]
@export var final_drive: float = 3.70
@export var reverse_ratio: float = 3.40
@export var wheel_radius: float = 0.35
@export var drivetrain_efficiency: float = 0.9
## Auto-shift points. Keep upshift well above downshift: the gap is the
## hysteresis band that stops the gearbox hunting at a steady cruise.
@export var upshift_rpm: float = 5600.0
@export var downshift_rpm: float = 2600.0

@export var max_brake: float = 55.0
## Gentle braking from engine drag when coasting off-throttle in gear.
@export var max_engine_brake: float = 6.0
@export var max_steer: float = 0.55
## Speed (m/s) at which available steering lock is halved.
@export var steer_falloff_speed: float = 12.0
## How fast the wheels track the steering target (rad/s).
@export var steer_speed: float = 3.5
@export var max_health: float = 100.0
## Velocity change (m/s) in a single physics tick that starts counting as a
## crash — normal driving, braking, and landings stay below this.
@export var impact_threshold: float = 6.0
@export var impact_damage_scale: float = 4.0
## Engine output fraction left when barely alive (limp-home floor).
@export var limp_floor: float = 0.25
## Drag area Cd·A (m²): the squared-speed drag that actually caps top speed once
## the gearbox runs out of pull. ~0.7 m² is a typical small saloon.
@export var drag_area: float = 0.7
## Downforce area Cl·A (m²): presses the car into the road harder with speed.
@export var downforce_area: float = 0.4
## Peak grip coefficient of the tyres. ~1.6 is a sticky sport-street tyre; the
## traction limiter pulls drive force that would exceed grip · load.
@export var tire_friction: float = 1.6
## Fraction of weight (and downforce) statically over the driven axle. Rear-drive
## so rear-biased; weight transfer adds the dynamic squat on top.
@export var drive_axle_load_share: float = 0.55
## Centre-of-gravity height (m) and wheelbase (m): set how much load squats onto
## the rear under acceleration. A low CG over a long wheelbase transfers least.
@export var cg_height: float = 0.5
@export var wheelbase: float = 2.9
## Distance (m) between left and right wheels; with cg_height it sets the
## cornering force that would lift the inside wheels.
@export var track_width: float = 1.7
## Fraction of the theoretical rollover threshold steering may use. Below 1
## leaves lateral grip headroom so hard swerves slide instead of flipping.
@export_range(0.1, 1.0) var rollover_margin: float = 0.8

var health: float = 100.0
var gear: int = 1
var rpm: float = 0.0

var _driver: Node3D = null
var _prev_velocity: Vector3 = Vector3.ZERO
var _long_accel: float = 0.0
var _prev_forward_speed: float = 0.0

@onready var _camera: Camera3D = $CameraPivot/SpringArm/Camera
@onready var _exit_point: Marker3D = $ExitPoint


func has_driver() -> bool:
	return _driver != null


func enter(driver: Node3D) -> void:
	_driver = driver
	_camera.current = true


## Releases the driver and returns a safe world position to step out at.
func exit() -> Vector3:
	_driver = null
	_camera.current = false
	gear = 1
	rpm = idle_rpm
	return _exit_point.global_position


func _ready() -> void:
	health = max_health
	rpm = idle_rpm


func _physics_process(delta: float) -> void:
	_track_impacts()
	_apply_aero()
	_update_long_accel(delta)
	if _driver == null:
		engine_force = 0.0
		brake = max_brake * 0.05
		steering = move_toward(steering, 0.0, steer_speed * delta)
		gear = 1
		rpm = idle_rpm
		return
	_drive(delta)


func _drive(delta: float) -> void:
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer_input := Input.get_axis("move_right", "move_left")
	var speed := linear_velocity.length()
	var forward_speed := linear_velocity.dot(-global_transform.basis.z)

	var ratio: float
	var pedal: float
	if throttle < 0.0 and forward_speed < REVERSE_SPEED_THRESHOLD:
		# Rolled to (near) a stop with "back" held: drive in reverse.
		gear = 1
		ratio = -reverse_ratio
		pedal = -throttle
	else:
		gear = Powertrain.select_gear(gear, rpm, upshift_rpm, downshift_rpm, gear_ratios.size())
		ratio = gear_ratios[gear - 1]
		pedal = maxf(throttle, 0.0)

	rpm = Powertrain.engine_rpm(speed, ratio, final_drive, wheel_radius, idle_rpm, redline_rpm)
	var torque := Powertrain.engine_torque(rpm, peak_torque, idle_rpm, peak_rpm, redline_rpm)
	var force := Powertrain.wheel_force(
		torque, pedal, ratio, final_drive, wheel_radius, drivetrain_efficiency
	)
	force *= _traction_scale(speed, force)
	engine_force = force * VehicleDamage.engine_multiplier(health, max_health, limp_floor)

	var target := VehicleMotion.steer_target(steer_input, speed, max_steer, steer_falloff_speed)
	var safe_steer := VehicleMotion.rollover_steer_limit(
		speed, track_width, cg_height, wheelbase, rollover_margin
	)
	target = clampf(target, -safe_steer, safe_steer)
	steering = move_toward(steering, target, steer_speed * delta)

	if Input.is_action_pressed("jump"):
		brake = max_brake
	elif throttle < 0.0 and forward_speed >= REVERSE_SPEED_THRESHOLD:
		# "Back" while still rolling forward = service brake, not reverse yet.
		brake = max_brake * 0.7
	elif is_zero_approx(pedal):
		# Coasting off-throttle in gear: let engine drag slow the car.
		brake = Powertrain.engine_brake(
			rpm, redline_rpm, gear_ratios[gear - 1], gear_ratios[0], max_engine_brake
		)
	else:
		brake = 0.0


## Lagged longitudinal acceleration (m/s²) from the change in forward speed. Used
## one frame later for weight transfer — a lag that keeps the load↔grip↔force
## chain stable instead of feeding back on itself within a frame.
func _update_long_accel(delta: float) -> void:
	var forward_speed := linear_velocity.dot(-global_transform.basis.z)
	if delta > 0.0:
		_long_accel = (forward_speed - _prev_forward_speed) / delta
	_prev_forward_speed = forward_speed


## Fraction of demanded drive force the driven tyres can actually lay down right
## now. Rear-axle load is its static share plus aero downforce plus the squat
## from accelerating (weight transfer); cornering (lateral accel ≈ speed · yaw
## rate) then spends part of that grip through the friction circle.
func _traction_scale(speed: float, drive_force: float) -> float:
	var static_load := mass * GRAVITY * drive_axle_load_share
	var downforce_share := Aerodynamics.downforce(speed, downforce_area) * drive_axle_load_share
	var transfer := WeightTransfer.longitudinal_shift(mass, _long_accel, cg_height, wheelbase)
	var load := WeightTransfer.axle_load(static_load + downforce_share, transfer)
	var grip := Traction.grip_limit(load, tire_friction)
	var lateral_force := mass * absf(speed * angular_velocity.y)
	var available := Traction.longitudinal_grip(grip, lateral_force)
	return Traction.traction_scale(drive_force, available)


func _apply_aero() -> void:
	var speed := linear_velocity.length()
	if speed > 0.01:
		var drag := Aerodynamics.drag_force(speed, drag_area)
		apply_central_force(-linear_velocity / speed * drag)
	apply_central_force(Vector3.DOWN * Aerodynamics.downforce(speed, downforce_area))


func _track_impacts() -> void:
	var velocity_change := (linear_velocity - _prev_velocity).length()
	_prev_velocity = linear_velocity
	var damage := VehicleDamage.impact_damage(
		velocity_change, impact_threshold, impact_damage_scale
	)
	if damage > 0.0:
		health = VehicleDamage.health_after(health, damage)
