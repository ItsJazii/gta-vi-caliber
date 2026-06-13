class_name VehicleHandling
extends RefCounted
## Pure arcade handling-feel math — the grip/drift/handbrake layer that makes
## driving *fun* rather than accurate. GTA cars slide, they don't simulate.
##
## This is a high-level feel layer that sits on top of the engine's
## VehicleBody3D and complements (never replaces) VehicleMotion / Traction: it
## takes a velocity and the car's facing, decides how hard the tyres should
## resist sideways slip, and bleeds the lateral component of velocity off so the
## car "bites" forward — easing it off lets the back end swing wide for a drift.
## The handbrake sharply cuts grip to kick the rear out on demand.
##
## Static math, no scene access — same testable-core pattern as VehicleMotion
## (docs/ARCHITECTURE.md). Vector3 in / Vector3 out, work on the XZ plane (y is
## up). Defensive throughout: zero-velocity is guarded, every output clamped, no
## path produces a NaN. Covered by tests/unit/test_vehicle_handling.gd. The small
## DriftScorer (RefCounted instance) at the bottom is the only stateful piece.


## Drop the vertical component — handling is reasoned about on the ground plane.
static func ground(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Convert a speed in m/s to km/h for the HUD readout (10 m/s -> 36 km/h).
static func speed_kmh(velocity: Vector3) -> float:
	return ground(velocity).length() * 3.6


## Angle (radians, 0..PI) between where the car is travelling and where it
## points. ~0 driving dead straight, grows as the car starts to slide sideways,
## PI when travelling pure backwards. Zero-velocity and zero-forward are guarded
## (a parked car isn't drifting), so this never normalises a zero vector.
static func slip_angle(velocity: Vector3, forward: Vector3) -> float:
	var vel := ground(velocity)
	var fwd := ground(forward)
	if vel.length() < 0.0001 or fwd.length() < 0.0001:
		return 0.0
	var cos_a := clampf(vel.normalized().dot(fwd.normalized()), -1.0, 1.0)
	return acos(cos_a)


## Drift amount in [0, 1] derived from slip angle: 0 while gripping (aligned),
## ramping to 1 as the slip angle opens past `full_slip` (default ~35°). Handy
## for FX intensity, tyre-smoke, and the drift score — not for physics.
static func drift_factor(velocity: Vector3, forward: Vector3, full_slip: float = 0.61) -> float:
	if full_slip <= 0.0:
		return 0.0
	return clampf(slip_angle(velocity, forward) / full_slip, 0.0, 1.0)


## How strongly the tyres resist sideways slip this frame, as a rate in [0, 1].
## `base_grip` is the dry-road bite; pulling the handbrake (bool or 0..1 float)
## scales rear grip sharply down by `handbrake_cut` so the back steps out and
## the car slides. Result is clamped so apply_friction stays stable.
static func lateral_grip(
	velocity: Vector3,
	_forward: Vector3,
	base_grip: float,
	handbrake: float = 0.0,
	handbrake_cut: float = 0.85
) -> float:
	var grip := clampf(base_grip, 0.0, 1.0)
	var brake := clampf(handbrake, 0.0, 1.0)
	var cut := clampf(handbrake_cut, 0.0, 1.0)
	# A standing car can't really slide, so the handbrake's grip-cut only bites
	# once the car is actually moving — ramping in over the first few m/s, which
	# keeps it from snapping grip to zero on a parked car. `_forward` rounds out
	# the (velocity, forward, ...) signature shared with the rest of the layer
	# and is reserved for future load-/heading-sensitive grip.
	var speed := ground(velocity).length()
	var moving := clampf(speed / 3.0, 0.0, 1.0)
	return clampf(grip * (1.0 - brake * cut * moving), 0.0, 1.0)


## Map a 0..1 lateral-grip factor onto a VehicleWheel3D friction slip, between a
## `min_slip` floor (full handbrake slide — the rear barely resists sideways) and
## the wheel's authored `base_slip` (full grip). This is how the abstract grip
## cut from `lateral_grip` becomes a concrete rear-wheel setting on the engine's
## VehicleBody3D, so the pure layer drives the slide without owning the physics.
static func slip_for_grip(grip: float, min_slip: float, base_slip: float) -> float:
	return lerpf(min_slip, base_slip, clampf(grip, 0.0, 1.0))


## The core "tyres bite" step. Split velocity into the component along `forward`
## and the component perpendicular to it (the slide), then bleed the lateral
## component by `grip * delta` — more grip removes more slide per second, so the
## car straightens; low grip lets it keep sliding. The forward component is left
## untouched, so a drifting car keeps its speed down the track. Returns the new
## velocity on the XZ plane. grip*delta is clamped to [0, 1] so a big delta can
## never overshoot and flip the slide to the far side.
static func apply_friction(
	velocity: Vector3, forward: Vector3, grip: float, delta: float
) -> Vector3:
	var vel := ground(velocity)
	var fwd := ground(forward)
	if fwd.length() < 0.0001 or vel.length() < 0.0001:
		return vel
	var fwd_n := fwd.normalized()
	var forward_speed := vel.dot(fwd_n)
	var forward_vel := fwd_n * forward_speed
	var lateral_vel := vel - forward_vel
	var bleed := clampf(maxf(grip, 0.0) * maxf(delta, 0.0), 0.0, 1.0)
	lateral_vel *= 1.0 - bleed
	return forward_vel + lateral_vel


## Steering authority for a speed, falling off as the car goes faster so it
## isn't twitchy at top end: full `max_steer` when parked, shrinking toward zero
## as speed climbs past `speed_falloff`. Same shape as VehicleMotion.steer_limit
## but expressed as a feel knob for the arcade layer.
static func steer_response(speed: float, max_steer: float, speed_falloff: float) -> float:
	var s := maxf(speed, 0.0)
	var falloff := maxf(speed_falloff, 0.001)
	return maxf(max_steer, 0.0) / (1.0 + s / falloff)


## Stateful drift-score accumulator: reward sustained sliding, decay when the
## car grips up again. Feed it drift_factor each frame; read `score`.
class DriftScorer:
	extends RefCounted

	var score: float = 0.0
	var gain: float = 100.0
	var decay: float = 200.0
	var engage: float = 0.2

	func _init(
		gain_per_sec: float = 100.0, decay_per_sec: float = 200.0, engage_threshold: float = 0.2
	) -> void:
		gain = maxf(gain_per_sec, 0.0)
		decay = maxf(decay_per_sec, 0.0)
		engage = clampf(engage_threshold, 0.0, 1.0)

	## Advance one frame. Above the engage threshold the score climbs with the
	## drift intensity; at or below it the score bleeds away. Never negative.
	func tick(drift: float, delta: float) -> float:
		var d := clampf(drift, 0.0, 1.0)
		var dt := maxf(delta, 0.0)
		if d > engage:
			score += gain * d * dt
		else:
			score = maxf(score - decay * dt, 0.0)
		return score

	## Bank the run and start fresh (e.g. when the car comes to rest); returns
	## the score that was banked.
	func cash_out() -> float:
		var banked := score
		score = 0.0
		return banked
