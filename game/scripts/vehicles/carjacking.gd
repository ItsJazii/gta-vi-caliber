class_name Carjacking
extends RefCounted
## Pure model for the iconic carjack: yanking a driver out of a car. Two halves —
## static geometry helpers (can the player reach the door? which side? is it a
## crime?) and a small STATEFUL struggle timer (the seconds spent wrestling a
## driver out before the player can climb in).
##
## No scene access — a node owns one, feeds it `tick(delta)` each frame, and reads
## `progress()`/`is_complete()`. All math is in the XZ plane (y is up) and
## defensive: zero-length and negative inputs never produce NaN. Unit-tested
## headless (tests/unit/test_carjacking.gd).
##
## Crime distinction: jacking an OCCUPIED car is a crime — you assault the driver
## in public, so it draws heat (see `heat_for_jack`). Hopping into an EMPTY parked
## car is theft-lite: still grand-theft-auto, but no eyewitness victim, so this
## model draws zero heat for it (the wanted system can score the theft elsewhere).

## Default heat a witnessed occupied carjack feeds the wanted system. Deliberately a
## flat one-star event: it clears WantedSystem's 1.0 one-star line but sits under the
## 3.0 two-star line, so a single witnessed jack draws exactly one star — hotter than a
## punch, cooler than a kill. Feed it RAW (no witnessed-crime doubling) to keep that.
const DEFAULT_JACK_HEAT: float = 2.0

var jack_duration: float
var _elapsed: float = 0.0
var _active: bool = false
var _complete: bool = false


## `duration` = seconds to wrestle the driver out; a resisting NPC takes longer
## (scale it up front with `resist_modifier`). Non-positive durations are floored
## to a tiny positive value so progress can't divide by zero and completes at once.
## Default 0.8s: the iconic civilian yank should feel snappy, near-instant — the old
## 1.2s base made the common case (most peds have ~0 toughness) sluggish.
func _init(duration: float = 0.8) -> void:
	jack_duration = maxf(duration, 0.0001)


## Drop the vertical component — door geometry is solved on the ground plane.
static func ground(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## True when the player is close enough to the car to grab a door handle.
## Compared on the flat plane so a height difference (curb, ramp) can't block it.
static func can_reach(player_pos: Vector3, car_pos: Vector3, reach_radius: float) -> bool:
	if reach_radius <= 0.0:
		return false
	return ground(player_pos - car_pos).length() <= reach_radius


## Which side the player approaches from, via lateral projection onto the car's
## right vector: -1 = driver side (left), +1 = passenger side (right), 0 = dead
## centre / undefined facing. `car_forward` need not be normalised.
static func door_side(car_pos: Vector3, car_forward: Vector3, player_pos: Vector3) -> int:
	var fwd := ground(car_forward)
	if fwd.length() < 0.0001:
		return 0
	# Right-hand vector on the XZ plane (forward rotated -90° about up).
	var right := Vector3(fwd.z, 0.0, -fwd.x).normalized()
	var lateral := ground(player_pos - car_pos).dot(right)
	if absf(lateral) < 0.0001:
		return 0
	return 1 if lateral > 0.0 else -1


## Is this jack a crime that draws heat? Occupied = yes (you assault the driver
## in front of witnesses); empty parked car = no (theft-lite, scored elsewhere).
static func is_occupied_crime(car_has_driver: bool) -> bool:
	return car_has_driver


## Heat the wanted system should receive for a jack: `base_heat` only when the
## car is occupied (a witnessed assault); 0 for an empty car. `base_heat` is
## floored at 0 so a stray negative can't bleed heat away.
static func heat_for_jack(car_has_driver: bool, base_heat: float = DEFAULT_JACK_HEAT) -> float:
	if not is_occupied_crime(car_has_driver):
		return 0.0
	return maxf(base_heat, 0.0)


## How much a tougher driver lengthens the struggle. `driver_toughness` is a 0..1
## resistance rating; returns a multiplier in 1.0..2.0 you apply to the base
## duration BEFORE `_init` (e.g. `Carjacking.new(base * resist_modifier(t))`), so a
## limp civilian (0.0) jacks in base time and a brawler (1.0) takes twice as long.
## Eases in quadratically (1 + t^2) rather than linearly, so the bulk of peds (low
## toughness) still jack near base time and only a genuinely tough driver ramps toward
## 2x — a sharper "this one fights back" moment than the old mushy linear ramp.
static func resist_modifier(driver_toughness: float) -> float:
	var t := clampf(driver_toughness, 0.0, 1.0)
	return 1.0 + t * t


## Start (or restart) the struggle from zero. Idempotent re-arm: clears a prior
## completion so the same instance can be reused.
func begin() -> void:
	_elapsed = 0.0
	_active = true
	_complete = false


## Advance the wrestle by `delta` seconds. No-op before `begin()`, once already
## complete, or for a negative delta (clock never runs backwards). Flips to
## complete exactly once the accumulated time reaches `jack_duration`.
func tick(delta: float) -> void:
	if not _active or _complete or delta < 0.0:
		return
	_elapsed += delta
	if _elapsed >= jack_duration:
		_elapsed = jack_duration
		_active = false
		_complete = true


## Struggle fraction, 0.0 at the grab and clamped to 1.0 once the driver is out.
func progress() -> float:
	return clampf(_elapsed / jack_duration, 0.0, 1.0)


## True once the driver has been ejected and the player may climb in.
func is_complete() -> bool:
	return _complete


## Player walked away mid-jack: abort. Stays incomplete (driver kept the car)
## until `begin()` re-arms it; further ticks do nothing.
func cancel() -> void:
	_active = false
	_complete = false
	_elapsed = 0.0


## Full reset to the idle, never-begun state.
func reset() -> void:
	_active = false
	_complete = false
	_elapsed = 0.0
