extends RefCounted
## Unit tests for NpcNeeds — the drive model that decides when an NPC abandons
## its routine. Decay, satisfy, clamping and the most-urgent scan must be exact.


func test_init_fills_all_needs() -> bool:
	var n := NpcNeeds.new(0.5)
	for need in NpcNeeds.NEEDS:
		if absf(float(n.values[need]) - 0.5) > 0.001:
			return false
	return true


func test_decay_uses_per_need_rate() -> bool:
	var n := NpcNeeds.new(1.0)
	n.decay(2.0, {"hunger": 0.25})
	# hunger drained 0.25/h × 2h = 0.5; energy had no rate so it stays full.
	return absf(float(n.values["hunger"]) - 0.5) < 0.001 and float(n.values["energy"]) == 1.0


func test_decay_clamps_at_zero() -> bool:
	var n := NpcNeeds.new(0.3)
	n.decay(10.0, {"energy": 1.0})
	return float(n.values["energy"]) == 0.0


func test_satisfy_clamps_at_one() -> bool:
	var n := NpcNeeds.new(0.9)
	n.satisfy("fun", 0.5)
	return float(n.values["fun"]) == 1.0


func test_satisfy_ignores_unknown_need() -> bool:
	var n := NpcNeeds.new(1.0)
	n.satisfy("nonsense", 0.5)  # must not crash or add a key
	return not n.values.has("nonsense")


func test_urgency_is_inverse_of_value() -> bool:
	var n := NpcNeeds.new(1.0)
	n.values["hunger"] = 0.2
	return absf(n.urgency("hunger") - 0.8) < 0.001


func test_most_urgent_finds_lowest() -> bool:
	var n := NpcNeeds.new(1.0)
	n.values["social"] = 0.4
	n.values["hygiene"] = 0.1
	return n.most_urgent() == "hygiene"


func test_most_urgent_breaks_ties_by_order() -> bool:
	var n := NpcNeeds.new(0.5)  # everything tied
	return n.most_urgent() == NpcNeeds.NEEDS[0]


func test_peak_urgency_matches_worst() -> bool:
	var n := NpcNeeds.new(1.0)
	n.values["energy"] = 0.15
	return absf(n.peak_urgency() - 0.85) < 0.001
