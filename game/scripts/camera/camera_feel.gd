class_name CameraFeel
extends RefCounted
## Pure camera-feel math (FOV kick, smoothing) for OrbitCamera.
##
## Static functions only, no scene access — same testable-core pattern as
## PlayerMotion (docs/ARCHITECTURE.md). Covered by
## tests/unit/test_camera_feel.gd.


## How far into "sprinting" the current speed is, 0..1. Used to blend the
## FOV kick in proportionally instead of snapping on a key press.
static func sprint_blend(speed: float, walk_speed: float, sprint_speed: float) -> float:
	if sprint_speed <= walk_speed:
		return 0.0
	return clampf((speed - walk_speed) / (sprint_speed - walk_speed), 0.0, 1.0)


## Target field of view for a sprint blend amount.
static func fov_for_blend(base_fov: float, kick: float, blend: float) -> float:
	return base_fov + kick * blend


## Frame-rate-independent exponential approach: composing two half-steps
## gives exactly one full step, so feel doesn't change with FPS.
static func exp_smoothed(current: float, target: float, smoothing: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-smoothing * delta))


## Camera yaw that looks along a horizontal travel direction — the angle to
## recenter to so the player runs away from the camera. Matches PlayerMotion's
## convention (forward input at yaw 0 travels -Z): solving -Z·R(yaw) = velocity
## gives atan2(-vx, -vz). A zero vector yields 0.
static func recenter_yaw(velocity_x: float, velocity_z: float) -> float:
	if is_zero_approx(velocity_x) and is_zero_approx(velocity_z):
		return 0.0
	return atan2(-velocity_x, -velocity_z)


## Step an angle toward a target along the shortest arc, capped at max_step, so
## recentering never spins the long way round a ±PI wrap.
static func approach_angle(current: float, target: float, max_step: float) -> float:
	var diff := wrapf(target - current, -PI, PI)
	return current + clampf(diff, -max_step, max_step)


## Camera roll (radians) banking into a turn for the driving chase cam:
## proportional to the car's yaw rate, scaled by the speed blend (so it only
## kicks in at speed), and capped at `max_roll`. Sign is negated so a left turn
## (positive yaw rate) tilts the horizon into the corner.
static func turn_roll(yaw_rate: float, blend: float, roll_gain: float, max_roll: float) -> float:
	return clampf(-yaw_rate * roll_gain, -max_roll, max_roll) * clampf(blend, 0.0, 1.0)
