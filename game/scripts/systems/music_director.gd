class_name MusicDirector
extends RefCounted
## Pure dynamic-score model — the non-diegetic music intensity that rises and falls
## with the action (distinct from the diegetic RadioScheduler). State drives a
## target tier (calm → tension → combat → chase); the score ESCALATES instantly so
## a gunfight hits immediately, but DE-ESCALATES one tier at a time after a hold so
## it doesn't whiplash back to calm the moment the last cop dies.
##
## No nodes, no scene access: an audio controller owns one, calls update() each
## frame with the game state, and crossfades to stem_for(current_tier()) — so the
## escalation/hysteresis logic stays unit-tested headless
## (tests/unit/test_music_director.gd).

enum Tier { CALM, TENSION, COMBAT, CHASE }

## Seconds the score holds a tier before stepping down once the action eases.
const DEESCALATE_HOLD: float = 5.0

const TIER_NAMES: Array = ["calm", "tension", "combat", "chase"]
## Music stem id per tier (what the audio layer crossfades to).
const TIER_STEMS: Array = ["ambient_calm", "low_pulse", "combat_drums", "chase_synth"]

var _current: int = Tier.CALM
var _hold_left: float = 0.0


## The tier the current game state calls for. context: {stars:int, in_combat:bool,
## in_chase:bool}.
func target_tier(context: Dictionary) -> int:
	if bool(context.get("in_chase", false)):
		return Tier.CHASE
	if bool(context.get("in_combat", false)):
		return Tier.COMBAT
	if int(context.get("stars", 0)) > 0:
		return Tier.TENSION
	return Tier.CALM


## Advance the score one frame. Escalation (target above current) snaps up instantly
## and refreshes the hold; when the action eases, the score waits DEESCALATE_HOLD
## then steps down a single tier, repeating until it reaches the target.
func update(context: Dictionary, delta: float) -> void:
	var target := target_tier(context)
	if target >= _current:
		_current = target
		_hold_left = DEESCALATE_HOLD
		return
	_hold_left -= maxf(delta, 0.0)
	if _hold_left <= 0.0:
		_current -= 1
		_hold_left = DEESCALATE_HOLD


func current_tier() -> int:
	return _current


## Name of the current tier ("calm".."chase").
func tier_name() -> String:
	return TIER_NAMES[_current]


## The stem id the audio layer should be playing now.
func current_stem() -> String:
	return TIER_STEMS[_current]


## Stem id for an explicit tier ("" if out of range).
func stem_for(tier: int) -> String:
	if tier < 0 or tier >= TIER_STEMS.size():
		return ""
	return TIER_STEMS[tier]


## True when the score is at combat intensity or higher.
func is_intense() -> bool:
	return _current >= Tier.COMBAT


## Force the score to a tier (scene load / scripted cue), clamped.
func set_tier(tier: int) -> void:
	_current = clampi(tier, Tier.CALM, Tier.CHASE)
	_hold_left = DEESCALATE_HOLD
