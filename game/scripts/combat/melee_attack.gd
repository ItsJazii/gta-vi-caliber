class_name MeleeAttack
extends RefCounted
## Pure melee swing/combo timing.
##
## No scene access — a MeleeController owns one, calls start() on the attack
## key and tick() each frame, and asks consume_hit() during the active window to
## land damage exactly once per swing. Chaining a swing during recovery builds a
## combo that scales damage. Timing/combo logic is unit-tested
## (tests/unit/test_melee_attack.gd).

enum Phase { READY, WINDUP, STRIKE, RECOVER }

## Extra damage per combo step beyond the first (0.2 = +20% on the 2nd hit, etc).
const COMBO_SCALING: float = 0.2

var phase: Phase = Phase.READY
var combo: int = 0

var _windup: float
var _strike: float
var _recover: float
var _t: float = 0.0
var _struck: bool = false
# Latched true the moment the strike window OPENS, so a long frame that advances
# WINDUP->STRIKE->RECOVER in one tick() can't strand the hit (the caller queries
# consume_hit() after tick(), by which point the live phase may already be past
# STRIKE). Cleared on the consumed hit and reset each swing.
var _strike_pending: bool = false


func _init(windup: float = 0.10, strike: float = 0.08, recover: float = 0.34) -> void:
	_windup = windup
	_strike = strike
	_recover = recover


## A new swing may begin from rest or by cancelling into the recovery window.
func can_start() -> bool:
	return phase == Phase.READY or phase == Phase.RECOVER


## Begin a swing. Chaining during recovery increments the combo; a fresh swing
## from rest resets it to 1. Returns false if a swing is mid-flight (windup/strike).
func start() -> bool:
	if not can_start():
		return false
	combo = combo + 1 if phase == Phase.RECOVER else 1
	phase = Phase.WINDUP
	_t = 0.0
	_struck = false
	_strike_pending = false
	return true


## Advance the swing. WINDUP → STRIKE → RECOVER → READY; reaching READY drops
## the combo back to zero. Leftover time carries across phase boundaries so a
## long frame can't strand the swing mid-phase.
func tick(delta: float) -> void:
	if phase == Phase.READY:
		return
	_t += delta
	while phase != Phase.READY:
		var duration := _phase_duration()
		if _t < duration:
			break
		_t -= duration
		_advance_phase()


func _phase_duration() -> float:
	match phase:
		Phase.WINDUP:
			return _windup
		Phase.STRIKE:
			return _strike
		Phase.RECOVER:
			return _recover
		_:
			return 0.0


func _advance_phase() -> void:
	match phase:
		Phase.WINDUP:
			phase = Phase.STRIKE
			_strike_pending = true  # latch: the active window opened this tick
		Phase.STRIKE:
			phase = Phase.RECOVER
		Phase.RECOVER:
			phase = Phase.READY
			combo = 0


## True at most once per swing, only during the active strike window — the
## moment the caller should run its hit query.
func consume_hit() -> bool:
	# Use the latch, not the live phase: a long frame can blow WINDUP->STRIKE->
	# RECOVER past the strike window in a single tick(), and the caller queries us
	# afterwards. _strike_pending records that the window opened, so the hit still
	# lands exactly once.
	if _strike_pending and not _struck:
		_struck = true
		return true
	return false


func is_active() -> bool:
	return phase != Phase.READY


## Damage for the current combo step.
func combo_damage(base_damage: float) -> float:
	return base_damage * (1.0 + COMBO_SCALING * float(maxi(combo - 1, 0)))
