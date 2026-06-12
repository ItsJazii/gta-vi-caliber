class_name CombatAi
extends RefCounted
## Pure combat decision AI: turns a pursuer's situation into a discrete combat
## action and a movement intent. This is the connective tissue between
## PoliceResponse.aggression(stars) (how hard the law leans on the player) and an
## actual shootout — when to close distance, when to open fire, when to break
## the line of sight, when to take cover.
##
## Static functions only — no scene access, no RNG, no node state — so behaviour
## is deterministic and unit-tested headless (tests/unit/test_combat_ai.gd). The
## owning enemy/officer node holds mutable state (current cover point, fire
## cooldown, strafe side) and feeds these helpers each tick. "Planar" means the
## XZ plane with y ignored, matching NpcBrain's convention.

enum Action {
	ADVANCE,  ## close toward the target (out of range, or no line of sight)
	ENGAGE,  ## in band, aimed, sightline clear → shoot
	REPOSITION,  ## in range but too close / not aimed → strafe to a better angle
	TAKE_COVER,  ## hurt and not fully committed → seek cover
	RETREAT,  ## overwhelmed or out of ammo with low resolve → fall back
}

## Below this health fraction a unit seeks cover unless its aggression is lethal.
const COVER_HEALTH := 0.35
## Below this health fraction a low-aggression unit breaks off entirely.
const RETREAT_HEALTH := 0.15
## Default half-angle (radians) of the firing arc — the target must be roughly
## in front before a unit will shoot rather than turn/strafe to face it.
const DEFAULT_ARC_HALF := PI * 35.0 / 180.0


## The engagement distance band around a weapon's preferred range. Units advance
## when beyond `y`, back off when inside `x`, and hold-and-fire in between. The
## hysteresis gap keeps a unit from flip-flopping between ADVANCE and REPOSITION
## at a single threshold.
static func engagement_band(preferred_range: float, hysteresis: float) -> Vector2:
	var h := clampf(hysteresis, 0.0, 0.9)
	return Vector2(preferred_range * (1.0 - h), preferred_range * (1.0 + h))


## Planar unit direction from a to b, or ZERO if effectively coincident.
static func planar_dir(a: Vector3, b: Vector3) -> Vector3:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


## True if `target_dir` falls within `half_angle` radians of where the unit
## faces. Both vectors are treated as planar unit directions.
static func in_firing_arc(facing: Vector3, target_dir: Vector3, half_angle: float) -> bool:
	var f := Vector3(facing.x, 0.0, facing.z)
	var t := Vector3(target_dir.x, 0.0, target_dir.z)
	if f.length() < 0.0001 or t.length() < 0.0001:
		return false
	return f.normalized().dot(t.normalized()) >= cos(clampf(half_angle, 0.0, PI))


## The core decision. Given the tactical picture, pick one action. Order matters:
## survival (ammo, cover, retreat) is checked before sightline, range, and aim so
## a unit never charges into fire it can't return.
static func decide_action(
	distance: float,
	band: Vector2,
	los_clear: bool,
	in_arc: bool,
	health_frac: float,
	aggression: float,
	ammo: int
) -> Action:
	# No ammo: lethal units strafe to reload under pressure; the rest fall back.
	if ammo <= 0:
		return Action.REPOSITION if aggression >= 0.8 else Action.RETREAT
	# Badly hurt and not committed → break off.
	if health_frac <= RETREAT_HEALTH and aggression < 0.5:
		return Action.RETREAT
	# Hurt but still in the fight → use cover, unless aggression is maxed.
	if health_frac <= COVER_HEALTH and aggression < 1.0:
		return Action.TAKE_COVER
	# Can't see the target → move to flank/regain line of sight.
	if not los_clear:
		return Action.ADVANCE
	if distance > band.y:
		return Action.ADVANCE
	if distance < band.x:
		return Action.REPOSITION
	# In band with a clear shot: fire if aimed, otherwise adjust angle.
	return Action.ENGAGE if in_arc else Action.REPOSITION


## Whether to actually pull the trigger this tick: only while ENGAGE-ing and the
## per-unit fire cooldown has elapsed. Keeps the trigger gate in one place.
static func should_fire(action: Action, cooldown_ready: bool) -> bool:
	return action == Action.ENGAGE and cooldown_ready


## Seconds between shots, scaled by aggression so high-heat responders fire
## faster. aggression 0 → 1.8x the base interval (cautious), 1 → 0.6x (relentless).
static func fire_interval(base_interval: float, aggression: float) -> float:
	return base_interval * lerpf(1.8, 0.6, clampf(aggression, 0.0, 1.0))


## Planar unit movement intent for an action. TAKE_COVER and RETREAT both run
## away from the target as a fallback — the owning node overrides TAKE_COVER with
## a real cover point when it has one. ENGAGE holds position (ZERO).
## `strafe_sign` (+1/-1) is the unit's stable circling side, chosen by the node.
static func desired_move(
	action: Action, self_pos: Vector3, target_pos: Vector3, strafe_sign: float
) -> Vector3:
	var to_target := planar_dir(self_pos, target_pos)
	match action:
		Action.ADVANCE:
			return to_target
		Action.RETREAT, Action.TAKE_COVER:
			return -to_target
		Action.REPOSITION:
			# Perpendicular to the sightline, picked side; bias slightly outward
			# so "too close" repositioning also opens distance.
			var perp := Vector3(to_target.z, 0.0, -to_target.x) * signf(strafe_sign)
			return (perp - to_target * 0.3).normalized()
		_:  # ENGAGE
			return Vector3.ZERO


## Target move speed for an action. ENGAGE plants the feet to fire; strafing is
## a touch slower than an all-out advance/retreat.
static func move_speed(action: Action, run_speed: float) -> float:
	match action:
		Action.ADVANCE, Action.RETREAT, Action.TAKE_COVER:
			return run_speed
		Action.REPOSITION:
			return run_speed * 0.7
		_:  # ENGAGE
			return 0.0
