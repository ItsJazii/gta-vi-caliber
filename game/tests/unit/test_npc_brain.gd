extends RefCounted
## Unit tests for NpcBrain — schedule-vs-need arbitration. The behaviours that
## must hold: a content NPC follows its routine; a desperate drive hijacks it;
## discipline raises the bar for being hijacked.

var _day := [
	{"start": 9.0, "end": 17.0, "activity": "work", "place": "office"},
	{"start": 17.0, "end": 9.0, "activity": "sleep", "place": "home"},
]


func test_content_npc_follows_schedule() -> bool:
	var needs := NpcNeeds.new(1.0)
	var d := NpcBrain.decide(_day, 11.0, needs)
	return d["activity"] == "work" and d["reason"] == "schedule"


func test_desperate_need_overrides_schedule() -> bool:
	var needs := NpcNeeds.new(1.0)
	needs.values["hunger"] = 0.1  # urgency 0.9 > 0.7 threshold
	var d := NpcBrain.decide(_day, 11.0, needs)
	return d["activity"] == "eat" and d["place"] == "diner" and d["reason"] == "need:hunger"


func test_mild_need_does_not_override() -> bool:
	var needs := NpcNeeds.new(1.0)
	needs.values["fun"] = 0.5  # urgency 0.5 < 0.7
	var d := NpcBrain.decide(_day, 11.0, needs)
	return d["activity"] == "work"


func test_discipline_raises_override_bar() -> bool:
	var needs := NpcNeeds.new(1.0)
	needs.values["social"] = 0.25  # urgency 0.75
	# Flake (discipline -1): threshold 0.5 -> overrides.
	var flake := NpcBrain.decide(_day, 11.0, needs, {"discipline": -1.0})
	# Workaholic (discipline +1): threshold 0.9 -> resists, keeps working.
	var workaholic := NpcBrain.decide(_day, 11.0, needs, {"discipline": 1.0})
	return flake["reason"] == "need:social" and workaholic["activity"] == "work"


func test_decision_reports_urgency() -> bool:
	var needs := NpcNeeds.new(1.0)
	needs.values["energy"] = 0.3
	var d := NpcBrain.decide(_day, 11.0, needs)
	return absf(float(d["urgency"]) - 0.7) < 0.001
