class_name Disguise
extends RefCounted
## Pure appearance / disguise model — the genre's "change your look to lose the
## heat" mechanic. The player has an appearance across weighted slots (outfit,
## mask, vehicle, hair); when police get a good look they LOG a description, and
## how much your current look still matches that description is your recognition.
## Swap enough slots and recognition drops, so a searching patrol gives up faster.
##
## Composes with the live WantedEvasion (it never imports it): a node feeds
## evasion the search delta scaled by evasion_speedup(), so a well-disguised player
## drains the "go cold" countdown faster. No scene access — the recognition / slot
## math stays unit-tested headless (tests/unit/test_disguise.gd).
##
## Slots and their weight in recognition (a mask hides the most, hair the least);
## the weights sum to 1.0 so recognition lands in [0, 1].

const WEIGHTS: Dictionary = {"outfit": 0.3, "mask": 0.4, "vehicle": 0.2, "hair": 0.1}

## How much faster a fully-disguised player (recognition 0) drains the search
## countdown versus a fully-recognized one (recognition 1 -> 1.0x).
const MAX_EVASION_SPEEDUP: float = 3.0

## Value every slot starts at (and resets to).
const DEFAULT_LOOK: String = "default"

## slot -> current value the player is wearing/driving.
var _current: Dictionary = {}

## slot -> value police last logged (the description they're hunting). Empty until
## the first log_sighting().
var _wanted_look: Dictionary = {}


func _init() -> void:
	for slot: Variant in WEIGHTS:
		_current[slot] = DEFAULT_LOOK


## Every appearance slot, in weight-declaration order.
func slots() -> Array:
	return WEIGHTS.keys()


## The player's current value for a slot, or "" for an unknown slot.
func current(slot: String) -> String:
	return _current.get(slot, "")


## Change one appearance slot (new jacket, mask on, different car). Unknown slots
## are ignored.
func set_appearance(slot: String, value: String) -> void:
	if _current.has(slot):
		_current[slot] = value


## Police memorise the player's current look as the description to hunt. Call this
## when the player is seen committing a crime / clearly spotted.
func log_sighting() -> void:
	_wanted_look = _current.duplicate()


## True once police have a description on file.
func has_description() -> bool:
	return not _wanted_look.is_empty()


## How recognizable the player is versus the logged description, in [0, 1]: the
## summed weight of every slot that still matches. 0.0 when police have no
## description (nobody is hunting a specific look).
func recognition() -> float:
	if _wanted_look.is_empty():
		return 0.0
	var score := 0.0
	for slot: Variant in WEIGHTS:
		if _current.get(slot) == _wanted_look.get(slot):
			score += WEIGHTS[slot]
	return score


## Multiplier a caller applies to the WantedEvasion search delta: 1.0 when fully
## recognized (no help) up to MAX_EVASION_SPEEDUP when fully disguised, so cops
## give up faster the less you look like their description.
func evasion_speedup() -> float:
	return 1.0 + (1.0 - recognition()) * (MAX_EVASION_SPEEDUP - 1.0)


## True if the player still matches the description at or above `threshold`.
func is_recognized(threshold: float) -> bool:
	return recognition() >= threshold


## How many slots differ from the logged description (0 when none is on file) —
## a "you changed N things about your look" count for UI/feedback.
func changed_slots() -> int:
	if _wanted_look.is_empty():
		return 0
	var count := 0
	for slot: Variant in WEIGHTS:
		if _current.get(slot) != _wanted_look.get(slot):
			count += 1
	return count


## Clear the logged description (police lose the trail once you go cold) so the
## next sighting starts fresh.
func reset_to_clean() -> void:
	_wanted_look = {}
