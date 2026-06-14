class_name HelicopterPursuit
extends RefCounted
## Pure air-support math for the police helicopter that joins the chase at high
## heat (PoliceResponse.uses_helicopter(stars) — 3+ stars). It decides where the
## chopper orbits above the target, how wide its searchlight footprint is, and
## whether the target is currently lit (which keeps the wanted level hot and feeds
## officers the player's position).
##
## Static, scene-free, RNG-free — unit-tested headless
## (tests/unit/test_helicopter_pursuit.gd). A HelicopterPursuit node flies its
## body toward orbit_point() and aims a spotlight; "planar" is the XZ ground
## plane, matching the rest of the AI models.

const DEFAULT_ORBIT_RADIUS := 28.0
const DEFAULT_ALTITUDE := 32.0
const DEFAULT_CONE_DEGREES := 22.0


## True once the wanted level calls in air support (3+ stars).
static func should_deploy(stars: int) -> bool:
	return PoliceResponse.uses_helicopter(stars)


## Where the chopper should be this instant: circling `center` at `radius` and
## `altitude`, the bearing advancing with `time`. Deterministic in `time` so the
## orbit is smooth and reproducible.
static func orbit_point(
	center: Vector3, time: float, radius: float, altitude: float, angular_speed: float
) -> Vector3:
	var a := time * angular_speed
	return center + Vector3(cos(a) * radius, altitude, sin(a) * radius)


## Half-angle (radians) of the searchlight cone from degrees, clamped to a sane
## (0, 90deg) range.
static func cone_half_radians(degrees: float) -> float:
	return deg_to_rad(clampf(degrees, 0.0, 89.0))


## Radius of the lit circle the searchlight casts on the ground, given the
## chopper's height above that ground and the cone half-angle.
static func spotlight_ground_radius(altitude: float, cone_half: float) -> float:
	# Clamp to the SAME ceiling cone_half_radians() produces (89°). A hard 1.55
	# under-clamped a max-angle cone (deg_to_rad(89) ≈ 1.5533 > 1.55), shrinking
	# the lit footprint ~16% below the true cone at wide angles.
	return maxf(altitude, 0.0) * tan(clampf(cone_half, 0.0, deg_to_rad(89.0)))


## Whether the target (a ground position) stands inside the searchlight footprint
## centred on `focus_ground` (where the light is aimed), given the lit radius.
## Planar — height is ignored. The player escapes the light by leaving the circle
## (cover, foliage, tunnels).
static func target_lit(focus_ground: Vector3, target_ground: Vector3, lit_radius: float) -> bool:
	var d := Vector2(target_ground.x - focus_ground.x, target_ground.z - focus_ground.z)
	return d.length() <= maxf(lit_radius, 0.0)
