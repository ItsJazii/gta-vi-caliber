extends RefCounted
## Unit tests for AmbientEvents (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Selection uses a seeded RNG so it's deterministic.

const CALM := {"stars": 0, "district": "downtown"}


func test_default_events_loaded() -> bool:
	var a := AmbientEvents.new()
	return a.event_count() == 6 and a.has_event("mugging") and a.has_event("gang_shootout")


func test_malformed_events_dropped() -> bool:
	var a := (
		AmbientEvents
		. new(
			[
				{"id": "ok", "weight": 1.0},
				{"id": "", "weight": 1.0},
				{"weight": 1.0},  # no id
				{"id": "zero", "weight": 0.0},  # non-positive weight
				{"id": "ok", "weight": 2.0},  # duplicate id
			]
		)
	)
	return a.event_count() == 1 and a.has_event("ok")


func test_kind_lookup() -> bool:
	var a := AmbientEvents.new()
	return a.kind_of("street_race") == "race" and a.kind_of("nope") == ""


func test_eligibility_by_stars() -> bool:
	var a := AmbientEvents.new()
	# getaway_driver needs 1+ stars; not eligible at 0.
	var calm := a.can_fire("getaway_driver", 0.0, CALM)
	var hot := a.can_fire("getaway_driver", 0.0, {"stars": 2, "district": "downtown"})
	return not calm and hot


func test_eligibility_by_district() -> bool:
	var a := AmbientEvents.new()
	# gang_shootout is docks-only.
	var elsewhere := a.can_fire("gang_shootout", 0.0, {"stars": 3, "district": "downtown"})
	var at_docks := a.can_fire("gang_shootout", 0.0, {"stars": 3, "district": "docks"})
	return not elsewhere and at_docks


func test_eligible_ids_excludes_ineligible() -> bool:
	var a := AmbientEvents.new()
	var elig := a.eligible_ids(0.0, CALM)
	return elig.has("mugging") and not elig.has("getaway_driver") and not elig.has("gang_shootout")


func test_cooldown_blocks_refire() -> bool:
	var a := AmbientEvents.new()
	a.trigger("mugging", 0.0)
	# mugging cooldown is 60s.
	var soon := a.can_fire("mugging", 30.0, CALM)
	var later := a.can_fire("mugging", 60.0, CALM)
	return not soon and later


func test_trigger_next_respects_global_gap() -> bool:
	var a := AmbientEvents.new()
	var first := a.trigger_next(AmbientEvents.make_rng(1), 0.0, CALM)
	# Within GLOBAL_GAP nothing else may fire.
	var blocked := a.trigger_next(AmbientEvents.make_rng(2), 10.0, CALM)
	return first != "" and blocked == ""


func test_trigger_next_null_rng() -> bool:
	var a := AmbientEvents.new()
	return a.trigger_next(null, 100.0, CALM) == ""


func test_trigger_next_picks_eligible_only() -> bool:
	var a := AmbientEvents.new()
	# At 0 stars in downtown, never pick a stars-gated or docks-only event.
	var picked := a.trigger_next(AmbientEvents.make_rng(5), 0.0, CALM)
	return picked != "" and picked != "getaway_driver" and picked != "gang_shootout"


func test_trigger_next_empty_when_nothing_eligible() -> bool:
	# A roster whose only event is docks-only; in another district nothing fires.
	var a := AmbientEvents.new(
		[{"id": "docks_only", "weight": 1.0, "min_stars": 0, "max_stars": 5, "district": "docks"}]
	)
	return a.trigger_next(AmbientEvents.make_rng(3), 100.0, {"stars": 0, "district": "beach"}) == ""


func test_reset_clears_cooldowns() -> bool:
	var a := AmbientEvents.new()
	a.trigger("mugging", 100.0)
	a.reset()
	return a.last_fired_of("mugging") == -INF and a.can_fire("mugging", 0.0, CALM)
