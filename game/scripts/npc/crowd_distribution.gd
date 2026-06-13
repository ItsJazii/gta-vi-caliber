class_name CrowdDistribution
extends RefCounted
## Pure spawn/cull math for a streaming pedestrian crowd.
##
## Static functions only — no scene access, RNG samples injected by the caller —
## so the placement maths is deterministic and unit-tested
## (tests/unit/test_crowd_distribution.gd). CrowdDirector owns the live nodes and
## calls these helpers each tick. Planar means the XZ plane with y left to the
## caller (ground height). Complements NpcBrain.wander_target, which samples a
## full disc for *where a ped walks*; this samples an annulus for *where a ped
## first appears* — never on top of the player, never beyond view.


## An area-uniform planar offset in the annulus [min_radius, max_radius] around
## the origin. Sampling r = sqrt(lerp(min^2, max^2, u)) keeps density even across
## the ring instead of clumping at the inner edge. Peds spawn out here so they
## fade in at the edge of view, not in the player's face.
static func spawn_offset(
	min_radius: float, max_radius: float, u_radius: float, u_angle: float
) -> Vector3:
	var lo: float = maxf(min_radius, 0.0)
	var hi: float = maxf(max_radius, lo)
	var u: float = clampf(u_radius, 0.0, 1.0)
	var r: float = sqrt(lo * lo + (hi * hi - lo * lo) * u)
	var a: float = u_angle * TAU
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


## True once a ped has drifted past the cull radius and should be recycled. A
## hair of hysteresis over the spawn ring is the caller's job (cull_radius >
## spawn_max_radius) so a ped isn't culled the instant it spawns.
static func should_despawn(distance: float, cull_radius: float) -> bool:
	return distance > cull_radius


## How many peds to spawn this tick to reach the target, clamped by a per-tick
## budget so a fresh scene doesn't instantiate the whole crowd in one frame.
static func spawn_count(current: int, target: int, per_tick_budget: int) -> int:
	var deficit: int = target - current
	if deficit <= 0:
		return 0
	return mini(deficit, maxi(per_tick_budget, 0))


## True when the `slot`-th spawn (a monotonically increasing counter) should be
## a Citizen rather than a plain pedestrian, for a target citizen `fraction` of
## the crowd. Bresenham-style spread: floor((slot+1)*f) > floor(slot*f), so
## citizens are interleaved evenly through the spawn order — deterministic for
## tests, no RNG clumping.
static func is_citizen_slot(slot: int, fraction: float) -> bool:
	var f: float = clampf(fraction, 0.0, 1.0)
	return floorf(float(slot + 1) * f) > floorf(float(slot) * f)
