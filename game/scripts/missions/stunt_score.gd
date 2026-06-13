class_name StuntScore
extends RefCounted
## Pure freeform stunt-combo scorer — the GTA "string tricks together for a
## multiplier, then land it clean to bank the points" loop. Airtime jumps, flips,
## spins, near-misses and wheelies chain into a combo whose multiplier climbs with
## each trick; landing safely banks the combo into your total (cash + respect),
## while a crash wipes the pending points. Distinct from StreetRace (checkpoint
## laps) and from VehicleHandling's drift scorer (this is air/near-miss style).
##
## No nodes, no scene access: a vehicle/stunt controller calls add_trick() as
## tricks are detected and bank()/wipe() on land/crash, then applies the returned
## score to the wallet (cash_for) and PlayerProgression (respect_for) — so the
## combo/multiplier math stays unit-tested headless (tests/unit/test_stunt_score.gd).

## Points per unit of each trick (magnitude scales: airtime seconds, full
## rotations, near-miss closeness 0..1, wheelie seconds; flip counts whole flips).
const TRICK_POINTS: Dictionary = {
	"jump": 50.0,
	"flip": 250.0,
	"spin": 150.0,
	"near_miss": 100.0,
	"wheelie": 40.0,
}

## Multiplier rises by this per chained trick after the first...
const MULT_STEP: float = 0.5
## ...capped here.
const MAX_MULT: float = 5.0

## Raw points accumulated in the current (un-banked) combo.
var _combo_points: float = 0.0
## Number of tricks in the current combo (drives the multiplier).
var _combo_count: int = 0
## Lifetime banked score.
var _total: int = 0
## Highest single combo ever banked.
var _best: int = 0


## Every recognised trick kind.
func trick_kinds() -> Array:
	return TRICK_POINTS.keys()


## Add a trick to the running combo. `magnitude` scales the trick's base points
## (e.g. seconds of airtime, number of spins). Returns the raw points added (0 for
## an unknown kind or non-positive magnitude).
func add_trick(kind: String, magnitude: float) -> int:
	if not TRICK_POINTS.has(kind) or magnitude <= 0.0:
		return 0
	var points := int(round(TRICK_POINTS[kind] * magnitude))
	_combo_points += float(points)
	_combo_count += 1
	return points


func combo_count() -> int:
	return _combo_count


func has_combo() -> bool:
	return _combo_count > 0


## Current combo multiplier: 1.0 for a single trick, +MULT_STEP per extra trick,
## capped at MAX_MULT.
func multiplier() -> float:
	if _combo_count <= 0:
		return 1.0
	return minf(1.0 + float(_combo_count - 1) * MULT_STEP, MAX_MULT)


## The score the current combo would bank right now: raw points times multiplier.
func pending_score() -> int:
	return int(round(_combo_points * multiplier()))


## Land it clean: bank the pending combo into the total, reset the combo, and
## return the banked score.
func bank() -> int:
	var banked := pending_score()
	_total += banked
	_best = maxi(_best, banked)
	_reset_combo()
	return banked


## Crash: lose the pending combo without banking. Returns the score forfeited.
func wipe() -> int:
	var lost := pending_score()
	_reset_combo()
	return lost


## Lifetime banked score.
func total_score() -> int:
	return _total


## Highest single combo ever banked.
func best_combo() -> int:
	return _best


## Cash payout for a banked score (1:1 by default).
static func cash_for(score: int) -> int:
	return maxi(0, score)


## Respect payout for a banked score (a fraction of the points).
static func respect_for(score: int) -> int:
	return int(round(maxf(0.0, float(score)) * 0.1))


func _reset_combo() -> void:
	_combo_points = 0.0
	_combo_count = 0
