class_name MeleeCombat
extends RefCounted
## The fist-fight math: punch/kick combos, blocking, counters, and stamina.
##
## A MeleeController owns one instance and drives the brawl: it asks can_strike()
## before a punch, calls strike() to spend stamina and bank the combo bonus, and
## regen_stamina() each frame the fighter isn't swinging. The static helpers are
## the pure damage/reach math (block soak, counter timing, stagger, reach) — RNG-
## free and scene-free so they unit-test deterministically (see weapon_ballistics
## for the same split). This is the COMBO/stamina math; MeleeAttack owns the
## per-swing windup/strike/recover timing — the two compose, they don't overlap.

## Punches and kicks, ordered light → heavy, each with a base damage.
enum Strike { JAB, CROSS, KICK, HEAVY }

## Base damage per strike type. A jab is a quick poke; a heavy is a haymaker.
const BASE_DAMAGE: Dictionary = {
	Strike.JAB: 6.0,
	Strike.CROSS: 10.0,
	Strike.KICK: 14.0,
	Strike.HEAVY: 22.0,
}

## Stamina each strike costs, mirroring its weight (heavy hits drain more).
const STAMINA_COST: Dictionary = {
	Strike.JAB: 6.0,
	Strike.CROSS: 9.0,
	Strike.KICK: 12.0,
	Strike.HEAVY: 18.0,
}

## Extra damage per chained hit beyond the first (0.12 = +12% on the 2nd hit…).
const COMBO_SCALING: float = 0.12
## The combo bonus stops growing past this many chained hits.
const MAX_COMBO_BONUS_STEPS: int = 5
## How much extra a well-timed counter multiplies the base hit by.
const COUNTER_MULTIPLIER: float = 1.75
## Stamina recovered per second while not striking.
const STAMINA_REGEN_RATE: float = 14.0
## A block leaves at least this fraction of a hit (heavy attacks bypass more of
## the guard, so they're never fully soaked even by a perfect block).
const BLOCK_FLOOR_FRACTION: Dictionary = {
	Strike.JAB: 0.0,
	Strike.CROSS: 0.0,
	Strike.KICK: 0.05,
	Strike.HEAVY: 0.25,
}

var _max_stamina: float
var _stamina: float
var _combo: int = 0
var _blocking: bool = false


## max_stamina is clamped to at least 1 so a fighter can always throw something;
## a fresh fighter starts fully rested with an empty combo and guard down.
func _init(max_stamina: float = 100.0) -> void:
	_max_stamina = maxf(max_stamina, 1.0)
	_stamina = _max_stamina


## Which strike a fighter throws at a given point in the combo, escalating the
## chain jab → cross → kick → heavy and then holding on heavy for the rest of the
## chain. combo_count is the 1-based hit number (the first landed hit is 1). A
## non-positive count maps to the opening jab, so a fresh swing always reads as
## the lightest strike.
static func strike_for_combo(combo_count: int) -> int:
	match combo_count:
		1:
			return Strike.JAB
		2:
			return Strike.CROSS
		3:
			return Strike.KICK
		_:
			return Strike.JAB if combo_count < 1 else Strike.HEAVY


## Base damage for a strike scaled by where it falls in the combo. The first hit
## is base; each chained hit adds COMBO_SCALING, capping at MAX_COMBO_BONUS_STEPS
## so a long combo can't run away. combo_count is clamped non-negative.
static func strike_damage(strike: int, combo_count: int) -> float:
	var base: float = BASE_DAMAGE.get(strike, 0.0)
	var steps: int = clampi(combo_count - 1, 0, MAX_COMBO_BONUS_STEPS)
	return base * (1.0 + COMBO_SCALING * float(steps))


## Damage left after a block soaks part of the hit. block_strength is the guard
## quality in [0,1]; a stronger block soaks more. The soak is capped by the
## strike's floor fraction, so heavy attacks always punch some damage through a
## guard. Result is never below 0 and never above the incoming hit.
static func block_reduction(incoming: float, block_strength: float, strike: int) -> float:
	var hit: float = maxf(incoming, 0.0)
	var soak: float = clampf(block_strength, 0.0, 1.0)
	var floor_frac: float = BLOCK_FLOOR_FRACTION.get(strike, 0.0)
	var min_through: float = hit * floor_frac
	var remaining: float = hit * (1.0 - soak)
	return clampf(maxf(remaining, min_through), 0.0, hit)


## A well-timed counter hits harder than the same blow thrown cold. Off the
## timing window the base damage passes through unchanged. base is floored at 0.
static func counter_damage(base: float, timing_window_hit: bool) -> float:
	var b: float = maxf(base, 0.0)
	return b * COUNTER_MULTIPLIER if timing_window_hit else b


## True when the target sits within reach of the attacker (planar distance, but
## y is included here so a fist whiffs over a ducked target). reach < 0 → false.
static func is_in_range(attacker_pos: Vector3, target_pos: Vector3, reach: float) -> bool:
	if reach < 0.0:
		return false
	return attacker_pos.distance_to(target_pos) <= reach


## Whether a hit of `damage` overwhelms a target's poise and staggers them. A
## non-positive poise staggers on any real hit; non-positive damage never does.
static func stagger_threshold(damage: float, target_poise: float) -> bool:
	if damage <= 0.0:
		return false
	return damage >= target_poise


## Whether the next strike still chains the combo: it lands inside the window.
## A non-positive window can never chain (the combo always resets).
static func combo_continues(time_since_last: float, window: float) -> bool:
	if window <= 0.0:
		return false
	return time_since_last >= 0.0 and time_since_last <= window


## Enough stamina in the tank to throw this strike.
func can_strike(strike: int) -> bool:
	return _stamina >= float(STAMINA_COST.get(strike, 0.0))


## Throw a strike: spend its stamina, advance the combo, and return the damage
## including the combo bonus. If the tank's too low it fails — no stamina spent,
## no combo advance, returns 0.
func strike(strike: int) -> float:
	if not can_strike(strike):
		return 0.0
	_stamina = maxf(_stamina - float(STAMINA_COST.get(strike, 0.0)), 0.0)
	_combo += 1
	return strike_damage(strike, _combo)


## How many hits the live combo has chained.
func combo_count() -> int:
	return _combo


## Drop the combo back to zero — on a whiff, a block, or letting the window lapse.
func reset_combo() -> void:
	_combo = 0


## Raise or drop the guard.
func block(active: bool) -> void:
	_blocking = active


func is_blocking() -> bool:
	return _blocking


## Recover stamina over `delta` seconds (only meaningful between swings), capped
## at the maximum. Negative delta is ignored.
func regen_stamina(delta: float) -> void:
	if delta <= 0.0:
		return
	_stamina = minf(_stamina + STAMINA_REGEN_RATE * delta, _max_stamina)


func stamina() -> float:
	return _stamina


## Stamina as a fraction of the maximum, in [0,1] — handy for a gauge.
func stamina_fraction() -> float:
	return _stamina / _max_stamina
