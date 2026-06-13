extends RefCounted
## Unit tests for FactionStanding (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Includes a GangTerritory composition test (a turf owner is a faction you have
## standing with).


func test_default_factions_loaded() -> bool:
	var f := FactionStanding.new()
	return f.faction_count() == 4 and f.has_faction("vice_kings") and f.has_faction("police")


func test_malformed_factions_dropped() -> bool:
	var f := (
		FactionStanding
		. new(
			[
				{"id": "ok"},
				{"id": ""},
				{"rival": "x"},  # no id
				{"id": "ok", "rival": "y"},  # duplicate id
			]
		)
	)
	return f.faction_count() == 1 and f.has_faction("ok")


func test_default_standing_neutral() -> bool:
	var f := FactionStanding.new()
	return f.standing_of("vice_kings") == 0 and f.tier_of("vice_kings") == "neutral"


func test_unknown_is_neutral() -> bool:
	var f := FactionStanding.new()
	return f.standing_of("nope") == 0 and f.tier_of("nope") == "" and not f.is_hostile("nope")


func test_adjust_raises_and_lowers() -> bool:
	var f := FactionStanding.new()
	f.adjust("los_santos_set", 30, 0.0)
	var up := f.standing_of("los_santos_set")
	f.adjust("los_santos_set", -50, 0.0)
	return up == 30 and f.standing_of("los_santos_set") == -20


func test_standing_clamps() -> bool:
	var f := FactionStanding.new()
	f.adjust("police", 9999, 0.0)
	var hi := f.standing_of("police")
	f.adjust("police", -9999, 0.0)
	return (
		hi == FactionStanding.MAX_STANDING
		and f.standing_of("police") == FactionStanding.MIN_STANDING
	)


func test_rivalry_spillover() -> bool:
	var f := FactionStanding.new()
	# Help vice_kings; its rival marina_cartel sours by half.
	f.adjust("vice_kings", 40, 0.5)
	return f.standing_of("vice_kings") == 40 and f.standing_of("marina_cartel") == -20


func test_tiers() -> bool:
	var f := FactionStanding.new()
	f.set_standing("police", -50)
	var hostile := f.tier_of("police")
	f.set_standing("police", 20)
	var friendly := f.tier_of("police")
	f.set_standing("police", 60)
	var allied := f.tier_of("police")
	return hostile == "hostile" and friendly == "friendly" and allied == "allied"


func test_attack_and_assist_gates() -> bool:
	var f := FactionStanding.new()
	f.set_standing("vice_kings", -60)
	var attacks := f.will_attack("vice_kings") and f.is_hostile("vice_kings")
	f.set_standing("vice_kings", 50)
	var assists := f.will_assist("vice_kings") and f.is_allied("vice_kings")
	return attacks and assists


func test_save_round_trip() -> bool:
	var f := FactionStanding.new()
	f.set_standing("vice_kings", 35)
	f.set_standing("police", -25)
	var restored := FactionStanding.new()
	restored.load_dict(f.to_dict())
	return restored.standing_of("vice_kings") == 35 and restored.standing_of("police") == -25


func test_aligns_with_gang_territory() -> bool:
	# Composition: a district's turf owner is a faction you hold standing with.
	var gt := GangTerritory.new()
	var owner := gt.owner_of("downtown")
	var f := FactionStanding.new()
	return owner == "vice_kings" and f.has_faction(owner)
