extends RefCounted
## Unit tests for NpcReaction — flee/gawk/ignore arbitration. The behaviours that
## must hold: distant players are ignored; an armed sprinter clears the street;
## the brave stand their ground; the curious lean in.


func test_distant_player_is_ignored() -> bool:
	return NpcReaction.decide(50.0, 1.0, 0.0, 1.0) == "ignore"


func test_armed_sprinter_reads_as_high_threat() -> bool:
	var t := NpcReaction.threat_from(10.0, true)
	return t >= 0.9


func test_unarmed_stroller_reads_as_low_threat() -> bool:
	return NpcReaction.threat_from(1.0, false) < 0.2


func test_scared_npc_flees_high_threat() -> bool:
	# Timid NPC (bravery 0.1), big threat, well within the extended flee range.
	return NpcReaction.decide(8.0, 0.9, 0.1, 0.0) == "flee"


func test_brave_npc_holds_ground() -> bool:
	# Same threat, but bravery exceeds it -> no fear, and low curiosity -> ignore.
	return NpcReaction.decide(8.0, 0.6, 0.9, 0.1) == "ignore"


func test_curious_npc_gawks_at_harmless_player() -> bool:
	# No threat, high curiosity, in notice range -> stop and stare.
	return NpcReaction.decide(10.0, 0.0, 0.5, 0.9) == "gawk"


func test_personal_space_triggers_flee_even_unarmed() -> bool:
	# A jumpy NPC with a tiny threat right in its face still bolts.
	return NpcReaction.decide(2.0, 0.2, 0.0, 0.0) == "flee"


func test_threat_extends_flee_range() -> bool:
	# At 10m a low threat is ignorable, but a maxed threat reaches that far.
	var calm := NpcReaction.decide(10.0, 0.1, 0.0, 0.0)
	var armed := NpcReaction.decide(10.0, 1.0, 0.0, 0.0)
	return calm != "flee" and armed == "flee"


func test_panic_spreads_to_close_timid_neighbours() -> bool:
	return NpcReaction.catches_panic(4.0, 0.3)


func test_panic_does_not_reach_far_neighbours() -> bool:
	return not NpcReaction.catches_panic(20.0, 0.3)


func test_brave_neighbours_resist_panic() -> bool:
	return not NpcReaction.catches_panic(2.0, 0.95)
