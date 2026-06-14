class_name FirePropagation
extends RefCounted
## Pure fire-propagation model: the GTA chain-fire where a molotov puddle, a
## burning car, or a torched palm SPREADS to the flammable thing next to it over
## time — distinct from ExplosionModel's instant radial blast. A fire is a single
## 0..1 intensity per flammable object that catches, grows while fuel lasts, then
## burns out as the fuel is consumed.
##
## Full 3D distances (a fire on a balcony can drop to the awning below), scene-free,
## all static, Vector3-in / numbers-out. Deterministic — no RNG. Defensive: every
## read is clamped/floored and NaN-guarded so a half-built object dict never poisons
## the field. Unit-tested headless (tests/unit/test_fire_propagation.gd).
##
## Shape mirrors CrowdPanic (a propagating field over a local set): ignite_intensity
## is the direct catch from a source, spread_intensity is the contagion term from
## burning neighbours, step_intensity ticks one object's running intensity, and
## update_fires runs one whole-set tick, O(n^2) over the few flammables streamed in
## near the player.
##
## A flammable object is a Dictionary {pos: Vector3, intensity: float, fuel: float}.
##
## FUEL / BURNOUT MODEL: `fuel` is abstract burn-seconds-worth of material, floored
## at 0. step_intensity ramps intensity UP toward 1 by `growth*delta` while fuel
## remains, and once fuel hits 0 it can no longer climb and instead DECAYS by
## `burnout*delta` back to 0 — that decay is the dying-flame tail. fuel_step drains
## fuel faster the hotter the object burns (consume_rate * intensity * delta), so a
## fierce fire is short-lived and a smouldering one lingers. A burnt-out object
## (fuel 0) is spent ash: it stops burning and CANNOT reignite from neighbours — only
## a fresh external source (a new molotov) handled outside this fuel state could.

## Falloff curve shared by ignite/spread: LINEAR, 1 at the source falling straight
## to 0 at `radius`, 0 at/beyond it. Linear (not smoothstep) to match ExplosionModel
## and CrowdPanic so designers tuning blast/panic/fire feel reason about one curve.


## Direct catch from a fire SOURCE (the molotov impact, the already-burning car) by
## proximity: 1.0 at the source position, linearly to 0.0 at spread_radius, 0.0 at or
## beyond it. This is the seed intensity a fresh flammable picks up the instant a
## source lands on it. Guards a zero/negative radius (returns 0).
static func ignite_intensity(
	source_pos: Vector3, target_pos: Vector3, spread_radius: float
) -> float:
	if spread_radius <= 0.0:
		return 0.0
	var dist := source_pos.distance_to(target_pos)
	if dist >= spread_radius:
		return 0.0
	return clampf(1.0 - dist / spread_radius, 0.0, 1.0)


## Intensity CAUGHT this tick from already-burning NEIGHBOURS — the contagion term
## that turns a single flame into a spreading chain instead of stopping at the source.
## burning_neighbors is an Array of {pos: Vector3, intensity: float}; each contributes
## its own intensity scaled by proximity (linear falloff to 0 at spread_radius) and by
## spread_rate*delta, so nearer AND hotter neighbours ignite a target faster.
## Contributions accumulate and saturate at 1.0. A cold (intensity 0) or out-of-range
## neighbour transmits nothing. Guards zero/negative radius/rate/delta.
static func spread_intensity(
	target_pos: Vector3,
	burning_neighbors: Array,
	spread_radius: float,
	spread_rate: float,
	delta: float
) -> float:
	if spread_radius <= 0.0 or spread_rate <= 0.0 or delta <= 0.0:
		return 0.0
	var caught := 0.0
	for other in burning_neighbors:
		var other_intensity := _read_intensity(other)
		if other_intensity <= 0.0:
			continue
		var other_pos := (other as Dictionary).get("pos", Vector3.ZERO) as Vector3
		var dist := other_pos.distance_to(target_pos)
		if dist >= spread_radius:
			continue
		var proximity := 1.0 - dist / spread_radius
		caught += other_intensity * proximity * spread_rate * delta
	return clampf(caught, 0.0, 1.0)


## Advance one object's intensity by a tick. `incoming` is the fresh ignition it
## received this tick (max of ignite/spread, computed by the caller). The new floor is
## max(current, incoming) — fire only rises from catching, never falls from it. While
## fuel remains it then RAMPS toward 1 by growth*delta (the flames building); once
## fuel is gone it cannot climb and DECAYS by burnout*delta toward 0 (the dying tail).
## Result clamped to [0, 1]. growth/burnout/delta guarded against negatives. See the
## FUEL / BURNOUT MODEL note at the top of the file.
static func step_intensity(
	current: float,
	incoming: float,
	growth: float,
	burnout: float,
	fuel_remaining: float,
	delta: float
) -> float:
	var base := maxf(_clamp01(current), _clamp01(incoming))
	# A cold object with nothing catching it stays cold — growth needs an existing
	# flame to feed; fuel alone does not make it ignite spontaneously.
	if base <= 0.0:
		return 0.0
	var d := maxf(delta, 0.0)
	if fuel_remaining > 0.0:
		var grown := base + maxf(growth, 0.0) * d
		return clampf(grown, 0.0, 1.0)
	var faded := base - maxf(burnout, 0.0) * d
	return clampf(faded, 0.0, 1.0)


## Is this object actively on fire (intensity at/above threshold)?
static func is_burning(intensity: float, threshold: float) -> bool:
	return intensity >= threshold


## Is this object spent — all fuel consumed, so it can no longer sustain a fire and
## cannot reignite from neighbours (only a fresh external source could).
static func is_burnt_out(fuel_remaining: float) -> bool:
	return fuel_remaining <= 0.0


## Drain fuel for one tick: the hotter the object burns the faster its material is
## consumed (consume_rate * intensity * delta). A cold object (intensity 0) loses no
## fuel; a roaring one empties fast. Floored at 0 — fuel never goes negative.
## consume_rate/delta guarded against negatives; intensity read clamped to [0,1].
static func fuel_step(fuel: float, intensity: float, consume_rate: float, delta: float) -> float:
	var drained := fuel - maxf(consume_rate, 0.0) * _clamp01(intensity) * maxf(delta, 0.0)
	return maxf(drained, 0.0)


## Damage per second the fire deals to whatever stands in it, scaled linearly by
## intensity: max_dps at full blaze, 0 when not burning. Never negative (max_dps
## floored at 0, intensity clamped).
static func damage_per_second(intensity: float, max_dps: float) -> float:
	return maxf(max_dps, 0.0) * _clamp01(intensity)


## One whole-set tick. For every object: take the larger of its direct catch from an
## (optional) source position and the contagion it catches from currently-burning
## neighbours, ramp/decay its intensity via step_intensity against its REMAINING fuel,
## then drain that fuel by the NEW intensity. Returns a parallel Array of
## {intensity, fuel} so a fire visibly spreads across successive ticks (a far calm
## object only lights once a nearer burning one has itself caught) and burns out when
## fuel runs dry. objects is an Array of {pos, intensity, fuel}; O(n^2) over the local
## set. Pass a source via objects' existing intensities only — this overload spreads
## purely from already-burning members (the chain), which is the common per-frame case.
static func update_fires(
	objects: Array,
	spread_radius: float,
	spread_rate: float,
	growth: float,
	burnout: float,
	consume_rate: float,
	delta: float
) -> Array:
	var result: Array = []
	for i in range(objects.size()):
		var obj: Variant = objects[i]
		var obj_dict := obj as Dictionary
		var pos := obj_dict.get("pos", Vector3.ZERO) as Vector3
		var current := _read_intensity(obj)
		var fuel := _read_fuel(obj)

		var caught := 0.0
		# A spent object is ash — neighbours cannot reignite it (model invariant).
		if not is_burnt_out(fuel):
			var neighbors := _others(objects, i)
			caught = spread_intensity(pos, neighbors, spread_radius, spread_rate, delta)

		var next_intensity := step_intensity(current, caught, growth, burnout, fuel, delta)
		var next_fuel := fuel_step(fuel, next_intensity, consume_rate, delta)
		result.append({"intensity": next_intensity, "fuel": next_fuel})
	return result


## Clamp a raw float to [0,1], treating NaN as 0 — keeps garbage out of the field.
static func _clamp01(value: float) -> float:
	if is_nan(value):
		return 0.0
	return clampf(value, 0.0, 1.0)


## Read an object's intensity defensively (missing/garbage -> 0, clamped [0,1]).
static func _read_intensity(obj: Variant) -> float:
	var intensity := (obj as Dictionary).get("intensity", 0.0) as float
	return _clamp01(intensity)


## Read an object's remaining fuel defensively (missing/garbage/NaN -> 0, floored 0).
static func _read_fuel(obj: Variant) -> float:
	var fuel := (obj as Dictionary).get("fuel", 0.0) as float
	if is_nan(fuel):
		return 0.0
	return maxf(fuel, 0.0)


## Every object except the one at `self_index` — the local set it spreads from.
## Skips by INDEX, not value: two objects with identical {pos, intensity, fuel}
## are distinct, so a value-compare (`!=`) would wrongly drop a real neighbour and
## stall fire spread between matching props (e.g. a row of identical crates).
static func _others(objects: Array, self_index: int) -> Array:
	var rest: Array = []
	for i in range(objects.size()):
		if i != self_index:
			rest.append(objects[i])
	return rest
