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

var health: float = 100.0
var gear: int = 1
var rpm: float = 0.0

var _driver: Node3D = null
var _prev_velocity: Vector3 = Vector3.ZERO

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
	engine_force = force * VehicleDamage.engine_multiplier(health, max_health, limp_floor)

	var target := VehicleMotion.steer_target(steer_input, speed, max_steer, steer_falloff_speed)
	steering = move_toward(steering, target, steer_speed * delta)

	if Input.is_action_pressed("jump"):
		brake = max_brake
	elif throttle < 0.0 and forward_speed >= REVERSE_SPEED_THRESHOLD:
		# "Back" while still rolling forward = service brake, not reverse yet.
		brake = max_brake * 0.7
	else:
		brake = 0.0


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
