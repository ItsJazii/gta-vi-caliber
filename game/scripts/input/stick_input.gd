class_name StickInput
extends RefCounted
## Pure analog-stick conditioning for gamepad input.
##
## Static functions only, no scene access — the pattern for testable logic
## (docs/ARCHITECTURE.md). Godot's per-axis joypad deadzone snaps and lets a
## hard left/up read as a weak diagonal; these helpers treat the stick as a
## vector instead: a radial deadzone with edge rescaling (no snap as you cross
## the threshold) plus an expo response curve for fine control near centre.
## Covered by tests/unit/test_stick_input.gd; consumed by the camera rig and
## (later) the player controller so mouse and gamepad share one feel.

## Smallest deadzone we treat as meaningful; below this the stick is "live"
## everywhere and rescaling would divide by ~zero.
const MIN_DEADZONE: float = 0.001


## Radial deadzone: zero inside `deadzone`, and outside it the magnitude is
## rescaled from [deadzone, 1] back to [0, 1] so output eases up from nothing at
## the threshold instead of snapping to a step. Direction is preserved and the
## magnitude is clamped to 1 so an over-range raw vector can't exceed unit speed.
static func radial_deadzone(raw: Vector2, deadzone: float) -> Vector2:
	var magnitude := raw.length()
	if magnitude <= deadzone:
		return Vector2.ZERO
	var dz := clampf(deadzone, 0.0, 1.0 - MIN_DEADZONE)
	var scaled := (magnitude - dz) / (1.0 - dz)
	return raw / magnitude * clampf(scaled, 0.0, 1.0)


## Expo response: raise the magnitude to `exponent` (>= 1 softens the centre for
## precise aim, 1.0 is linear) while keeping the direction. Operates on the
## vector magnitude, not per-axis, so diagonals curve evenly.
static func apply_response(v: Vector2, exponent: float) -> Vector2:
	var magnitude := v.length()
	if magnitude <= 0.0:
		return Vector2.ZERO
	var shaped := pow(magnitude, maxf(exponent, 1.0))
	return v / magnitude * shaped


## Full conditioning pipeline: radial deadzone then expo curve. Returns a vector
## with magnitude in [0, 1].
static func conditioned(raw: Vector2, deadzone: float, exponent: float) -> Vector2:
	return apply_response(radial_deadzone(raw, deadzone), exponent)


## Per-frame look offset (radians) from a raw right-stick vector: condition it,
## then scale by sensitivity (rad/s at full deflection) and delta so the turn
## rate is frame-rate independent. x drives yaw, y drives pitch.
static func look_delta(
	raw: Vector2, deadzone: float, exponent: float, sensitivity: float, delta: float
) -> Vector2:
	return conditioned(raw, deadzone, exponent) * sensitivity * delta
