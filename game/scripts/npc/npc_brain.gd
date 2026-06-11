class_name NpcBrain
extends RefCounted
## The decision layer that makes a citizen feel alive: it fuses the scripted
## daily routine (NpcSchedule) with live drives (NpcNeeds) and personality, and
## emits a single concrete intent — "go here and do this, because...".
##
## The routine is the baseline. But a drive that gets desperate enough crosses
## the NPC's personal interrupt threshold and hijacks the plan: the diligent
## accountant who suddenly *has* to find a toilet, the bored intern who ditches
## work for the park the instant fun bottoms out. That tension between schedule
## and need is what reads, from the sidewalk, as a person with an inner life.
##
## Pure decision math (state in, intent out), scene-free, unit-tested headless
## (tests/unit/test_npc_brain.gd).

## Default urgency at which a drive overrides the schedule. Personality shifts it.
const OVERRIDE_THRESHOLD: float = 0.7

## Which activity / place resolves each drive when it boils over.
const NEED_ACTIVITY: Dictionary = {
	"energy": {"activity": "sleep", "place": "home"},
	"hunger": {"activity": "eat", "place": "diner"},
	"social": {"activity": "socialize", "place": "bar"},
	"fun": {"activity": "goof_off", "place": "park"},
	"hygiene": {"activity": "freshen_up", "place": "restroom"},
}


## Decide what this NPC does at `hour` given its routine, drives and personality.
##
## personality keys (all optional, default 0):
##   "discipline" in [-1, 1] — how stubbornly it sticks to the schedule. A
##     disciplined NPC tolerates more discomfort before bailing; a flake bails
##     at the first twinge.
##
## Returns {activity, place, reason, urgency}. `reason` is "schedule" or
## "need:<drive>" so debug HUD / dialogue can explain the choice.
static func decide(
	blocks: Array, hour: float, needs: NpcNeeds, personality: Dictionary = {}
) -> Dictionary:
	var scheduled := NpcSchedule.activity_at(blocks, hour)
	var need := needs.most_urgent()
	var urg := needs.urgency(need)

	var discipline := clampf(float(personality.get("discipline", 0.0)), -1.0, 1.0)
	var threshold := clampf(OVERRIDE_THRESHOLD + discipline * 0.2, 0.4, 0.95)

	if urg >= threshold and NEED_ACTIVITY.has(need):
		var act: Dictionary = (NEED_ACTIVITY[need] as Dictionary).duplicate()
		act["reason"] = "need:%s" % need
		act["urgency"] = urg
		return act

	var out := scheduled.duplicate()
	out["reason"] = "schedule"
	out["urgency"] = urg
	return out
