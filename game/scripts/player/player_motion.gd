class_name PlayerMotion
extends RefCounted
## Pure movement math for the player controller.
##
## Static functions only, no scene access — this is the pattern for testable
## logic (docs/ARCHITECTURE.md): Player stays thin, the math lives here and
## is covered by tests/unit/test_player_motion.gd.


## Convert 2D input (from Input.get_vector) into a world-space direction,
## rotated so "forward" follows the camera yaw. Returns a unit vector or ZERO.
static func direction_from_input(input_dir: Vector2, camera_yaw: float) -> Vector3:
	if input_dir.is_zero_approx():
		return Vector3.ZERO
	var local := Vector3(input_dir.x, 0.0, input_dir.y)
	return local.rotated(Vector3.UP, camera_yaw).normalized()


## Yaw for a Node3D whose visual forward is Godot/project forward (-Z).
static func yaw_from_forward(direction: Vector3) -> float:
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.is_zero_approx():
		return NAN
	return atan2(-planar.x, -planar.z)


## Target horizontal velocity for a direction and speed (y is always 0).
static func horizontal_velocity(direction: Vector3, speed: float) -> Vector3:
	return Vector3(direction.x * speed, 0.0, direction.z * speed)


## Move the current horizontal velocity toward the target, leaving y intact.
static func accelerated(
	current: Vector3, target: Vector3, acceleration: float, delta: float
) -> Vector3:
	return Vector3(
		move_toward(current.x, target.x, acceleration * delta),
		current.y,
		move_toward(current.z, target.z, acceleration * delta)
	)


## Pick this frame's acceleration rate: speeding up and braking use separate
## rates (braking is stronger, so stops feel crisp), and both are scaled by
## air_control while airborne so jumps keep their momentum.
static func acceleration_rate(
	has_input: bool, on_floor: bool, accel: float, decel: float, air_control: float
) -> float:
	var rate := accel if has_input else decel
	if not on_floor:
		rate *= air_control
	return rate


## Whether a jump should fire this frame. Combines coyote time (a late press
## shortly after walking off a ledge still counts) with jump buffering (an
## early press shortly before landing still counts). jump_spent guards
## against double-firing until the character touches the floor again.
static func should_jump(
	time_since_grounded: float,
	coyote_time: float,
	time_since_jump_pressed: float,
	buffer_time: float,
	jump_spent: bool
) -> bool:
	if jump_spent:
		return false
	return time_since_grounded <= coyote_time and time_since_jump_pressed <= buffer_time


## Velocity while latched to a ladder: forward input climbs, back input
## descends, and the world-space move direction is kept at half speed so the
## player can steer off the ladder sideways or over the top lip.
static func climb_velocity(input_dir: Vector2, direction: Vector3, climb_speed: float) -> Vector3:
	return Vector3(
		direction.x * climb_speed * 0.5, -input_dir.y * climb_speed, direction.z * climb_speed * 0.5
	)
