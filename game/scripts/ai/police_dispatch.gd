class_name PoliceDispatch
extends RefCounted
## Pure spawn-plan model for the wanted-level police response: how many officers
## should be in the field at a given heat, where to spawn the reinforcements
## (rings that widen with the stars), and which existing units to recall.
##
## Static functions only — no scene/RNG/node state, RNG samples injected by the
## caller — so the escalation math is deterministic and unit-tested
## (tests/unit/test_police_dispatch.gd). A PoliceSpawner node consumes the plan:
## it instances police.tscn at the returned positions and frees recalled units.
## "Planar" means the XZ plane with y carried from the spawn centre, matching
## CombatAi / NpcBrain / PoliceResponse.


## How many officers should be live at this heat, capped by the scene budget.
static func desired_units(stars: int, max_alive: int) -> int:
	return mini(PoliceResponse.units_for(stars), maxi(max_alive, 0))


## How many to spawn this wave: the deficit toward `desired_units`, never
## negative and never more than `max_per_wave` (so reinforcements trickle in as
## expanding pressure rather than popping in all at once).
static func spawn_count(stars: int, alive: int, max_alive: int, max_per_wave: int) -> int:
	var deficit := desired_units(stars, max_alive) - alive
	return clampi(deficit, 0, maxi(max_per_wave, 0))


## Angle (radians) for the index-th of `total` spawns: an even slice of the ring
## plus jitter inside that slice, so a wave fans out around the player instead of
## stacking on one bearing. `u_jitter` in [0,1); `jitter_frac` scales the wobble.
static func ring_angle(index: int, total: int, u_jitter: float, jitter_frac: float) -> float:
	var slice := TAU / float(maxi(total, 1))
	return (
		index * slice + (clampf(u_jitter, 0.0, 1.0) - 0.5) * slice * clampf(jitter_frac, 0.0, 1.0)
	)


## A spawn point on the response ring around `center`. `radius` is the heat's
## spawn radius; `u_radius` in [0,1) jitters the distance by up to `radial_jitter`
## metres so officers don't appear on a perfect circle.
static func ring_position(
	center: Vector3, radius: float, angle: float, u_radius: float, radial_jitter: float
) -> Vector3:
	var r := maxf(radius + (clampf(u_radius, 0.0, 1.0) - 0.5) * 2.0 * radial_jitter, 0.0)
	return center + Vector3(cos(angle) * r, 0.0, sin(angle) * r)


## Whether a live officer should be recalled (freed): once the player is no longer
## wanted everyone stands down, and anyone who falls beyond `despawn_radius` is
## culled so the spawner can re-place fresh pressure closer in.
static func should_despawn(stars: int, distance_to_player: float, despawn_radius: float) -> bool:
	if stars <= 0:
		return true
	return distance_to_player > despawn_radius
