class_name Ballistics
extends RefCounted
## Pure hitscan math shared by every weapon.
##
## Static functions only — no scene access, no RNG (the caller passes a random
## sample in, so results are deterministic and testable). Covered by
## tests/unit/test_ballistics.gd.


## Perturb a forward aim direction within a cone. `sample` is a point in the
## unit disk (each component in [-1, 1], length <= 1) supplied by the caller's
## RNG; `right`/`up` are the camera basis. spread is the cone half-angle in
## radians: 0 returns forward unchanged. Result is unit length.
static func spread_direction(
	forward: Vector3, right: Vector3, up: Vector3, sample: Vector2, spread: float
) -> Vector3:
	if spread <= 0.0 or sample.is_zero_approx():
		return forward.normalized()
	var offset: Vector3 = (right * sample.x + up * sample.y) * tan(spread)
	return (forward + offset).normalized()


## Damage after distance falloff: full inside falloff_start, lerps down to
## base_damage * min_fraction by falloff_end, flat beyond. Guards a degenerate
## (end <= start) band by returning the near value.
static func damage_at_range(
	base_damage: float,
	distance: float,
	falloff_start: float,
	falloff_end: float,
	min_fraction: float
) -> float:
	# Clamp the floor to [0,1] (the WeaponBallistics twin already does): an
	# out-of-range min_fraction > 1 would otherwise make a far shot deal MORE than
	# point-blank, and a negative one would heal the target.
	var mf := clampf(min_fraction, 0.0, 1.0)
	if distance <= falloff_start:
		return base_damage
	if distance >= falloff_end or falloff_end <= falloff_start:
		return base_damage * mf
	var t: float = (distance - falloff_start) / (falloff_end - falloff_start)
	return base_damage * lerpf(1.0, mf, t)


## Damage multiplier for where a shot landed on a target: a hit at or above
## head_height (measured from the target's origin) gets head_mult, otherwise 1.
## Kept pure so the head/body split is unit-tested without a scene.
static func zone_multiplier(local_height: float, head_height: float, head_mult: float) -> float:
	return head_mult if local_height >= head_height else 1.0


## A point uniformly distributed in the unit disk from two independent [0, 1)
## samples (rejection-free, area-correct). Use to feed spread_direction without
## clumping shots toward the centre. Caller supplies the randoms so tests stay
## deterministic.
static func disk_sample(u_radius: float, u_angle: float) -> Vector2:
	var r: float = sqrt(clampf(u_radius, 0.0, 1.0))
	var a: float = u_angle * TAU
	return Vector2(cos(a), sin(a)) * r
