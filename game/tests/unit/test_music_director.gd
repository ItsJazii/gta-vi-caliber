extends RefCounted
## Unit tests for MusicDirector (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_starts_calm() -> bool:
	var m := MusicDirector.new()
	return m.current_tier() == MusicDirector.Tier.CALM and m.tier_name() == "calm"


func test_target_tier_priority() -> bool:
	var m := MusicDirector.new()
	return (
		m.target_tier({"in_chase": true, "in_combat": true}) == MusicDirector.Tier.CHASE
		and m.target_tier({"in_combat": true}) == MusicDirector.Tier.COMBAT
		and m.target_tier({"stars": 2}) == MusicDirector.Tier.TENSION
		and m.target_tier({}) == MusicDirector.Tier.CALM
	)


func test_escalates_instantly() -> bool:
	var m := MusicDirector.new()
	m.update({"in_combat": true}, 0.016)
	return m.current_tier() == MusicDirector.Tier.COMBAT and m.is_intense()


func test_escalates_straight_to_chase() -> bool:
	var m := MusicDirector.new()
	m.update({"in_chase": true}, 0.016)
	return m.current_tier() == MusicDirector.Tier.CHASE and m.current_stem() == "chase_synth"


func test_deescalation_is_held() -> bool:
	var m := MusicDirector.new()
	m.update({"in_combat": true}, 0.016)  # COMBAT
	# Action eases, but within the hold window the score stays put.
	m.update({}, MusicDirector.DEESCALATE_HOLD - 1.0)
	return m.current_tier() == MusicDirector.Tier.COMBAT


func test_deescalation_steps_one_tier() -> bool:
	var m := MusicDirector.new()
	m.update({"in_combat": true}, 0.016)  # COMBAT (tier 2)
	m.update({}, MusicDirector.DEESCALATE_HOLD)  # -> TENSION (tier 1)
	var step1 := m.current_tier()
	m.update({}, MusicDirector.DEESCALATE_HOLD)  # -> CALM (tier 0)
	return step1 == MusicDirector.Tier.TENSION and m.current_tier() == MusicDirector.Tier.CALM


func test_reescalation_refreshes_hold() -> bool:
	var m := MusicDirector.new()
	m.update({"in_combat": true}, 0.016)  # COMBAT
	m.update({}, MusicDirector.DEESCALATE_HOLD - 0.5)  # nearly stepped down
	m.update({"in_combat": true}, 0.016)  # combat resumes -> refresh
	# A short tick now should NOT step down (hold was refreshed).
	m.update({}, 1.0)
	return m.current_tier() == MusicDirector.Tier.COMBAT


func test_stems_and_names() -> bool:
	var m := MusicDirector.new()
	return (
		m.stem_for(MusicDirector.Tier.CALM) == "ambient_calm"
		and m.stem_for(MusicDirector.Tier.CHASE) == "chase_synth"
		and m.stem_for(99) == ""
	)


func test_set_tier_clamps() -> bool:
	var m := MusicDirector.new()
	m.set_tier(99)
	var hi := m.current_tier()
	m.set_tier(-5)
	return hi == MusicDirector.Tier.CHASE and m.current_tier() == MusicDirector.Tier.CALM


func test_tension_from_stars_only() -> bool:
	var m := MusicDirector.new()
	m.update({"stars": 1}, 0.016)
	return m.current_tier() == MusicDirector.Tier.TENSION and not m.is_intense()
