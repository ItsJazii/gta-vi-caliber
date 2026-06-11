class_name BarkPool
extends RefCounted
## Pure pool of NPC one-liners ("barks") by situation.
##
## Scene-free so line selection and cooldown gating are unit-tested
## (tests/unit/test_bark_pool.gd). A BarkDirector picks a situation and an index
## (a counter or RNG) and this returns the line; no scene/RNG access here keeps
## it deterministic.

enum Situation { IDLE, ALARMED, FLEE }

const LINES: Dictionary = {
	Situation.IDLE:
	[
		"Lovely day for it.",
		"Where did I park?",
		"Running late again.",
		"I need a coffee.",
		"Nice weather, huh?",
		"...so then I told him no.",
	],
	Situation.ALARMED:
	["What was that?!", "Did you hear that?", "Hey — watch it!", "Everything okay?"],
	Situation.FLEE: ["He's got a gun!", "Run!", "Somebody help!", "Get down!", "Call the cops!"],
}


## The line for a situation at the given index, wrapping so any counter/RNG value
## is valid. Returns "" for an unknown/empty situation.
static func line(situation: Situation, index: int) -> String:
	var pool: Array = LINES.get(situation, [])
	if pool.is_empty():
		return ""
	return pool[posmod(index, pool.size())]


## Number of distinct lines for a situation (for callers that want to vary).
static func count(situation: Situation) -> int:
	return (LINES.get(situation, []) as Array).size()


## Cooldown gate so an NPC doesn't chatter every frame.
static func should_bark(time_since_last: float, cooldown: float) -> bool:
	return time_since_last >= cooldown
