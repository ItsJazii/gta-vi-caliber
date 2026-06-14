class_name SideJob
extends RefCounted
## Pure model for GTA-style SIDE JOBS / CONTRACTS — the quick paid odd-jobs
## (taxi fare, parcel delivery, vigilante hit, towing) that hand the player a
## fast objective and cash without touching the main mission chain.
##
## Two halves, both scene-free: a bank of STATIC reward/eligibility helpers
## (fare, vigilante bounty, par-time bonus, combined payout, streak multiplier)
## that the HUD and tests can call with no instance, and a small STATEFUL
## active-job tracker (pickup -> dropoff -> complete) that a node drives during
## play. Any randomness is the caller's job — pass in a seeded RNG — so the
## model itself is deterministic and unit-tested headless
## (tests/unit/test_side_job.gd).
##
## A job is a Dictionary {kind, pickup: Vector3, dropoff: Vector3, base_reward}.

enum Kind { TAXI, DELIVERY, VIGILANTE, TOWING }

## A job moves pickup -> dropoff; DONE marks a finished/cleared tracker.
enum Stage { PICKUP, DROPOFF, DONE }

## Default cash per metre of trip for fare-style jobs.
const DEFAULT_PER_METER: float = 1.5
## Default cash per eliminated target for vigilante contracts.
const DEFAULT_PER_TARGET: int = 150
## Streak bonus never multiplies a payout past this (×2).
const MAX_CHAIN_MULTIPLIER: float = 2.0
## Extra multiplier earned per back-to-back completion before the cap.
const CHAIN_STEP: float = 0.1

# Stateful active-job tracker state (driven by the instance methods below).
var _active: Dictionary = {}
var _stage: int = Stage.DONE
var _completed: int = 0


## Build a job dictionary (handy for callers/tests; base_reward floored at 0).
static func make_job(kind: int, pickup: Vector3, dropoff: Vector3, base_reward: int) -> Dictionary:
	return {
		"kind": kind,
		"pickup": pickup,
		"dropoff": dropoff,
		"base_reward": maxi(base_reward, 0),
	}


## Stable string id for a kind (HUD/save use), or "" for an unknown value.
static func kind_name(kind: int) -> String:
	match kind:
		Kind.TAXI:
			return "taxi"
		Kind.DELIVERY:
			return "delivery"
		Kind.VIGILANTE:
			return "vigilante"
		Kind.TOWING:
			return "towing"
		_:
			return ""


## Fare for a trip: base plus per-metre distance pay, floored at the base and
## never negative. Negative distance/inputs are clamped to 0.
static func fare(distance: float, base_reward: int, per_meter: float) -> int:
	var base := maxi(base_reward, 0)
	var dist := maxf(distance, 0.0)
	var rate := maxf(per_meter, 0.0)
	return base + int(round(dist * rate))


## Vigilante bounty: base plus a flat sum per eliminated target (both clamped).
static func vigilante_reward(targets: int, base_reward: int, per_target: int) -> int:
	var base := maxi(base_reward, 0)
	var kills := maxi(targets, 0)
	var rate := maxi(per_target, 0)
	return base + kills * rate


## Bonus for beating par time: full `bonus` at/under par, shrinking linearly to 0
## as you approach 2× par, and 0 once over par. Clamped non-negative. A par_time
## <= 0 is degenerate (no clock), so no bonus is awarded.
static func time_bonus(time_taken: float, par_time: float, bonus: int) -> int:
	var reward := maxi(bonus, 0)
	if par_time <= 0.0 or reward == 0:
		return 0
	var taken := maxf(time_taken, 0.0)
	if taken <= par_time:
		return reward  # at or under par -> full bonus
	if taken >= 2.0 * par_time:
		return 0  # at/over 2x par -> nothing
	# Between par and 2x par: shrink linearly to 0 (the documented decay band that
	# was missing — every slightly-over-par finish used to pay 0).
	var frac := 1.0 - (taken - par_time) / par_time
	return maxi(int(round(float(reward) * frac)), 0)


## Total cash for a completed job, combining the per-kind core reward with the
## par-time bonus. Never negative.
static func payout(job: Dictionary, distance: float, time_taken: float, par_time: float) -> int:
	var kind := int(job.get("kind", Kind.TAXI))
	var base := maxi(int(job.get("base_reward", 0)), 0)
	var core := 0
	match kind:
		Kind.VIGILANTE:
			# `distance` carries the kill count for vigilante contracts.
			core = vigilante_reward(int(round(maxf(distance, 0.0))), base, DEFAULT_PER_TARGET)
		_:
			core = fare(distance, base, DEFAULT_PER_METER)
	var bonus := time_bonus(time_taken, par_time, base)
	return maxi(core + bonus, 0)


## Streak multiplier for back-to-back completions: 1.0 for the first job, then
## +CHAIN_STEP each consecutive one, capped at MAX_CHAIN_MULTIPLIER. Always >= 1.
static func chain_multiplier(consecutive_completed: int) -> float:
	var streak := maxi(consecutive_completed, 0)
	return minf(1.0 + float(streak) * CHAIN_STEP, MAX_CHAIN_MULTIPLIER)


# --- Stateful active-job tracker -------------------------------------------


func _init() -> void:
	_active = {}
	_stage = Stage.DONE
	_completed = 0


## Begin a job; it starts at the PICKUP stage. Replaces any current job.
func start(job: Dictionary) -> void:
	_active = job.duplicate(true)
	_stage = Stage.PICKUP


func has_active() -> bool:
	return not _active.is_empty() and _stage != Stage.DONE


## Kind of the active job, or -1 when none is active.
func active_kind() -> int:
	if not has_active():
		return -1
	return int(_active.get("kind", Kind.TAXI))


func stage() -> int:
	return _stage


func is_pickup_done() -> bool:
	return has_active() and _stage == Stage.DROPOFF


## Move PICKUP -> DROPOFF. No-op when there is no active job.
func advance_stage() -> void:
	if not has_active():
		return
	if _stage == Stage.PICKUP:
		_stage = Stage.DROPOFF


## Finish the active job: tally it and clear the tracker. No-op when none active.
func complete() -> void:
	if not has_active():
		return
	_completed += 1
	_active = {}
	_stage = Stage.DONE


## Abort the active job without crediting it. No-op when none active.
func cancel() -> void:
	if not has_active():
		return
	_active = {}
	_stage = Stage.DONE


func completed_count() -> int:
	return _completed
