class_name CrowdPanic
extends RefCounted
## Crowd-wave panic propagation: the iconic GTA moment where a gunshot scares the
## peds nearby and the fear then SPREADS outward as fleeing citizens alarm the
## ones around them, so a single shot empties a whole plaza in a rolling wave.
##
## Pure fear-field math, all in the XZ plane, no nodes — unit-tests headless
## (tests/unit/test_crowd_panic.gd). This is the CROWD layer above NpcReaction:
## NpcReaction.catches_panic() is a single ped's yes/no read of one neighbour;
## CrowdPanic models the continuous 0..1 fear field over a whole local set and
## ticks it so the wave visibly ripples across frames. Flee math composes
## conceptually with NpcSteering (it returns a direction the agent feeds in).
##
## A ped is a Dictionary {pos: Vector3, fear: float}. update_crowd() takes the
## whole set and returns the next-tick fear per ped, O(n^2) over the local
## (streamed) crowd — fine for the few-dozen peds actually loaded near the player.


## Direct fear from a scare event (gunshot, explosion) by proximity. 1.0 at the
## epicentre, falling linearly to 0.0 at scare_radius and 0.0 beyond it. Guards a
## zero/negative radius (returns 0).
static func initial_fear(ped_pos: Vector3, scare_pos: Vector3, scare_radius: float) -> float:
	if scare_radius <= 0.0:
		return 0.0
	var dist := _ground(ped_pos - scare_pos).length()
	if dist >= scare_radius:
		return 0.0
	return clampf(1.0 - dist / scare_radius, 0.0, 1.0)


## Fear CAUGHT this tick from already-panicking neighbours — the contagion term
## that makes panic spread rather than stop at a fixed blast radius. neighbours is
## an Array of {pos: Vector3, fear: float}. Each contributes its own fear scaled
## by proximity (linear falloff to 0 at contagion_radius) and by contagion_strength;
## contributions accumulate and saturate at 1.0. A calm (fear 0) or distant
## neighbour transmits nothing. Guards zero/negative radius.
static func propagated_fear(
	ped_pos: Vector3, neighbors: Array, contagion_radius: float, contagion_strength: float
) -> float:
	if contagion_radius <= 0.0 or contagion_strength <= 0.0:
		return 0.0
	var caught := 0.0
	for other in neighbors:
		var other_fear := _read_fear(other)
		if other_fear <= 0.0:
			continue
		var dist := _ground((other as Dictionary).get("pos", Vector3.ZERO) - ped_pos).length()
		if dist >= contagion_radius:
			continue
		var proximity := 1.0 - dist / contagion_radius
		caught += other_fear * proximity * contagion_strength
	return clampf(caught, 0.0, 1.0)


## Advance one ped's fear by a tick. Newly received fear is taken as a MAX with the
## current level (a scare can only raise fear, never lower it — being already
## scared doesn't add a second jolt), then the whole thing decays linearly by
## decay*delta so a crowd with no fresh scares eventually calms back to 0. Result
## clamped to [0, 1]. delta/decay guarded against negatives.
static func step_fear(
	current_fear: float, external_fear: float, decay: float, delta: float
) -> float:
	var raised := maxf(current_fear, clampf(external_fear, 0.0, 1.0))
	var cooled := raised - maxf(decay, 0.0) * maxf(delta, 0.0)
	return clampf(cooled, 0.0, 1.0)


## Unit flee direction: straight AWAY from the scare, blended with separation from
## panicking neighbours so a bolting crowd fans out instead of collapsing onto one
## escape line. Returns a normalised XZ vector; falls back to separation alone when
## standing on the scare, and to a deterministic +X when everything is degenerate
## (so the agent always has a valid heading — no NaN).
static func flee_direction(
	ped_pos: Vector3, scare_pos: Vector3, neighbors: Array, separation_radius: float
) -> Vector3:
	var away := _ground(ped_pos - scare_pos)
	if away.length() > 0.0001:
		away = away.normalized()
	else:
		away = Vector3.ZERO

	var spread := Vector3.ZERO
	if separation_radius > 0.0:
		for other in neighbors:
			var other_pos := (other as Dictionary).get("pos", Vector3.ZERO) as Vector3
			var off := _ground(ped_pos - other_pos)
			var d := off.length()
			if d > 0.0001 and d < separation_radius:
				spread += off.normalized() * (1.0 - d / separation_radius)
	if spread.length() > 0.0001:
		spread = spread.normalized()

	var blended := away + spread * 0.5
	if blended.length() > 0.0001:
		return blended.normalized()
	if away.length() > 0.0001:
		return away
	if spread.length() > 0.0001:
		return spread
	return Vector3.RIGHT


## Is this ped panicking (fear at/above threshold)?
static func is_panicking(fear: float, threshold: float) -> bool:
	return fear >= threshold


## One whole-crowd tick. For every ped: take the larger of its direct fear from the
## scare and the fear it catches from currently-panicking neighbours, fold that into
## its running fear via step_fear, and return the new fear array (parallel to peds).
## Contagion reads each ped's CURRENT fear, so it takes successive ticks for a wave
## to cross the crowd — a far calm ped only lights up once a nearer ped it can see
## has itself caught fear. peds is an Array of {pos, fear}; returns Array[float].
static func update_crowd(
	peds: Array,
	scare_pos: Vector3,
	scare_radius: float,
	contagion_radius: float,
	contagion_strength: float,
	decay: float,
	delta: float
) -> Array:
	var next_fears: Array = []
	for i in range(peds.size()):
		var ped: Variant = peds[i]
		var ped_dict := ped as Dictionary
		var ped_pos := ped_dict.get("pos", Vector3.ZERO) as Vector3
		var current := _read_fear(ped)

		var direct := initial_fear(ped_pos, scare_pos, scare_radius)
		var neighbors := _others(peds, i)
		var caught := propagated_fear(ped_pos, neighbors, contagion_radius, contagion_strength)
		var incoming := maxf(direct, caught)

		next_fears.append(step_fear(current, incoming, decay, delta))
	return next_fears


## Flatten to the ground plane — panic spreads across the street, not up walls.
static func _ground(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Read a ped's fear defensively (missing/garbage -> 0), so a half-built ped dict
## never poisons the field with a NaN.
static func _read_fear(ped: Variant) -> float:
	var fear := (ped as Dictionary).get("fear", 0.0) as float
	if is_nan(fear):
		return 0.0
	return clampf(fear, 0.0, 1.0)


## Every ped except the one at `self_index` — the local set a ped catches panic
## from. Skips by INDEX, not value: two peds with identical {pos, fear} are
## distinct agents, so a value-compare (`!=`) would wrongly drop a real neighbour
## and stall the wave in a tight clump (everyone at the same spot sees nobody).
static func _others(peds: Array, self_index: int) -> Array:
	var rest: Array = []
	for i in range(peds.size()):
		if i != self_index:
			rest.append(peds[i])
	return rest
