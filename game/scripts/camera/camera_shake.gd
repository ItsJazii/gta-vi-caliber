class_name CameraShake
extends RefCounted
## Pure trauma-based camera-shake math (Squirrel Eiserloh's model: events add
## "trauma", which decays linearly, and the actual shake is trauma raised to a
## power so small hits stay subtle while big ones snap). Static and scene-free
## so it unit-tests headless; OrbitCamera holds the trauma scalar and feeds in a
## noise sample per axis, applying the offset to the leaf Camera3D so it never
## fights the yaw/pitch/recoil model. Covered by tests/unit/test_camera_shake.gd.


## Add an impulse to the current trauma, clamped to [0, 1]. Callers scale the
## amount to the event (a pistol shot < a car crash < an explosion).
static func add(trauma: float, amount: float) -> float:
	return clampf(trauma + amount, 0.0, 1.0)


## Linear decay toward calm; trauma falls by decay_rate per second.
static func decay(trauma: float, decay_rate: float, delta: float) -> float:
	return clampf(trauma - decay_rate * delta, 0.0, 1.0)


## Shake magnitude for the current trauma. Raising to `exponent` (2–3) makes the
## response non-linear so light trauma barely registers and heavy trauma jolts.
static func shake_amount(trauma: float, exponent: float) -> float:
	return pow(clampf(trauma, 0.0, 1.0), maxf(exponent, 1.0))


## Map an impact speed (m/s) — a landing, a collision — to trauma: silent at or
## below min_speed, ramping linearly to max_trauma at max_speed. A gentle step
## down stays calm while a long fall jolts the view.
static func trauma_from_impact(
	speed: float, min_speed: float, max_speed: float, max_trauma: float
) -> float:
	if speed <= min_speed or max_speed <= min_speed:
		return 0.0
	return clampf((speed - min_speed) / (max_speed - min_speed), 0.0, 1.0) * max_trauma


## Angular shake offset (radians) for the camera. Each axis is its own max angle
## times the shake magnitude times that axis's noise sample in [-1, 1] — pass
## decorrelated noise so pitch/yaw/roll don't move in lockstep.
static func angular_offset(
	trauma: float, exponent: float, max_angles: Vector3, noise: Vector3
) -> Vector3:
	var s := shake_amount(trauma, exponent)
	return Vector3(
		max_angles.x * s * noise.x, max_angles.y * s * noise.y, max_angles.z * s * noise.z
	)
