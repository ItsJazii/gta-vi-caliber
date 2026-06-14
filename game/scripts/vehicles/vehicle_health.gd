class_name VehicleHealth
extends RefCounted
## Pure health / damage-state machine for a vehicle: the timeline where a
## beaten-up car smokes, then catches fire, then explodes.
##
## STATEFUL instance, no scene access — a Car node owns one and feeds it damage
## and time, so the burn-down/explosion curve is unit-tested
## (tests/unit/test_vehicle_health.gd). This is the HEALTH state machine; the
## crash-impact math lives in VehicleDamage (static, stateless) and is unrelated.
##
## State boundaries, as a fraction of max health:
##   PRISTINE   >= 0.66
##   DAMAGED    [0.33, 0.66)
##   SMOKING    [fire_threshold, 0.33)   (skipped if fire_threshold >= 0.33)
##   ON_FIRE    (0, fire_threshold)      — starts the explosion fuse
##   WRECKED    health == 0, or the fuse has elapsed (irreversible until reset)

enum State { PRISTINE, DAMAGED, SMOKING, ON_FIRE, WRECKED }

const DAMAGED_FRACTION: float = 0.66
const SMOKING_FRACTION: float = 0.33
## Seconds the car burns once ON_FIRE before it explodes into WRECKED.
const DEFAULT_FUSE: float = 5.0
## Health chipped off per second while burning (cosmetic; the fuse is what
## actually triggers the explosion).
const BURN_RATE: float = 0.0

var max_health: float
var fire_threshold_fraction: float
var fuse_duration: float

var _health: float
var _state: int = State.PRISTINE
var _fuse_remaining: float = INF
var _just_exploded: bool = false


func _init(
	starting_max_health: float = 1000.0,
	fire_threshold: float = 0.2,
	fuse_seconds: float = DEFAULT_FUSE
) -> void:
	max_health = maxf(starting_max_health, 0.0)
	# Cap the fire band below the SMOKING band so a fire_threshold > 0.33 can't
	# route a merely-DAMAGED car (fraction in [0.33, 0.66)) straight to ON_FIRE,
	# arming the explosion fuse at half health and skipping the documented
	# DAMAGED/SMOKING states.
	fire_threshold_fraction = clampf(fire_threshold, 0.0, SMOKING_FRACTION)
	fuse_duration = maxf(fuse_seconds, 0.0)
	_health = max_health
	_refresh_state()


## Apply damage (negative ignored). Health floors at 0; the state is recomputed,
## and crossing into ON_FIRE arms the explosion fuse. Reaching 0 health goes
## straight to WRECKED and fires the one-shot explosion.
func apply_damage(amount: float) -> void:
	if amount <= 0.0 or _state == State.WRECKED:
		return
	_health = maxf(_health - amount, 0.0)
	_refresh_state()


## Advance time (negative delta ignored). Only meaningful while ON_FIRE: burns
## the fuse down and optionally chips health; when the fuse hits 0 the vehicle
## becomes WRECKED and just_exploded() returns true for that one read.
func tick(delta: float) -> void:
	if delta <= 0.0 or _state != State.ON_FIRE:
		return
	if BURN_RATE > 0.0:
		_health = maxf(_health - BURN_RATE * delta, 0.0)
	_fuse_remaining = maxf(_fuse_remaining - delta, 0.0)
	if _fuse_remaining <= 0.0 or _health <= 0.0:
		_explode()
	else:
		_refresh_state()


func health() -> float:
	return _health


func health_fraction() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(_health / max_health, 0.0, 1.0)


func state() -> int:
	return _state


func is_on_fire() -> bool:
	return _state == State.ON_FIRE


func is_wrecked() -> bool:
	return _state == State.WRECKED


## Seconds of fuse left before the explosion. INF when not yet ON_FIRE (no fuse
## armed); 0.0 once WRECKED.
func time_to_explosion() -> float:
	if _state == State.WRECKED:
		return 0.0
	if _state != State.ON_FIRE:
		return INF
	return _fuse_remaining


## One-shot: true exactly once after the explosion, then self-clears.
func just_exploded() -> bool:
	var fired := _just_exploded
	_just_exploded = false
	return fired


## Restore to full health and PRISTINE; disarms the fuse.
func repair() -> void:
	reset()


func reset() -> void:
	_health = max_health
	_fuse_remaining = INF
	_just_exploded = false
	_refresh_state()


func _explode() -> void:
	_health = 0.0
	_fuse_remaining = 0.0
	_state = State.WRECKED
	_just_exploded = true


func _refresh_state() -> void:
	if _health <= 0.0:
		_explode()
		return
	var fraction := health_fraction()
	if fraction < fire_threshold_fraction:
		_enter_fire()
	elif fraction < SMOKING_FRACTION:
		_state = State.SMOKING
	elif fraction < DAMAGED_FRACTION:
		_state = State.DAMAGED
	else:
		_state = State.PRISTINE


## Move into ON_FIRE, arming the fuse on the transition only so re-entry from a
## later tick/damage does not reset an already-burning countdown.
func _enter_fire() -> void:
	if _state != State.ON_FIRE:
		_fuse_remaining = fuse_duration
	_state = State.ON_FIRE
