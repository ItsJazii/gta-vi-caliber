extends RefCounted
## Unit tests for PlayerSkills (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Gains involve a diminishing-returns float curve, so level/gain assertions use
## is_equal_approx; tier/clamp/count assertions are exact.

const TWO := [{"id": "a", "rate": 1.0}, {"id": "b", "rate": 1.0}]


func test_default_skills_loaded() -> bool:
	var s := PlayerSkills.new()
	return s.skill_count() == 7 and s.has_skill("driving") and s.has_skill("shooting")


func test_skills_list_order() -> bool:
	var s := PlayerSkills.new()
	return s.skills()[0] == "driving" and s.skills().has("flying")


func test_fresh_skill_is_zero() -> bool:
	var s := PlayerSkills.new()
	return s.level("driving") == 0.0 and s.tier("driving") == "novice"


func test_unknown_skill_is_neutral() -> bool:
	var s := PlayerSkills.new()
	return s.level("nope") == 0.0 and s.tier("nope") == "" and s.bonus("nope") == 0.0


func test_malformed_skills_dropped() -> bool:
	var s := (
		PlayerSkills
		. new(
			[
				{"id": "ok", "rate": 1.0},
				{"id": "", "rate": 1.0},
				{"rate": 1.0},
				{"id": "zero_rate", "rate": 0.0},
				{"id": "ok", "rate": 2.0},  # duplicate id dropped
			]
		)
	)
	return s.skill_count() == 1 and s.has_skill("ok")


func test_train_increases_level() -> bool:
	var s := PlayerSkills.new()
	var gain := s.train("driving", 10.0)  # 10 * 1.0 * (1 - 0) = 10
	return is_equal_approx(gain, 10.0) and is_equal_approx(s.level("driving"), 10.0)


func test_train_diminishing_returns() -> bool:
	var s := PlayerSkills.new()
	var first := s.train("driving", 10.0)  # gain 10 -> value 10
	var second := s.train("driving", 10.0)  # gain 10*0.9 = 9 -> value 19
	return first > second and is_equal_approx(s.level("driving"), 19.0)


func test_train_respects_rate() -> bool:
	# Same effort, lower-rate skill gains less.
	var s := PlayerSkills.new()
	var driving := s.train("driving", 10.0)  # rate 1.0
	var flying := s.train("flying", 10.0)  # rate 0.5
	return driving > flying and is_equal_approx(flying, 5.0)


func test_train_caps_at_max() -> bool:
	var s := PlayerSkills.new()
	s.train("driving", 100000.0)
	return s.level("driving") == PlayerSkills.MAX_SKILL


func test_train_at_max_gains_nothing() -> bool:
	var s := PlayerSkills.new()
	s.set_level("driving", PlayerSkills.MAX_SKILL)
	return s.train("driving", 50.0) == 0.0 and s.level("driving") == PlayerSkills.MAX_SKILL


func test_train_rejects_bad_input() -> bool:
	var s := PlayerSkills.new()
	return s.train("nope", 10.0) == 0.0 and s.train("driving", 0.0) == 0.0


func test_tier_bands() -> bool:
	var s := PlayerSkills.new()
	s.set_level("driving", 25.0)
	var competent := s.tier("driving")
	s.set_level("driving", 70.0)
	var expert := s.tier("driving")
	s.set_level("driving", 90.0)
	var master := s.tier("driving")
	return competent == "competent" and expert == "expert" and master == "master"


func test_bonus_is_normalised() -> bool:
	var s := PlayerSkills.new()
	s.set_level("shooting", 50.0)
	return is_equal_approx(s.bonus("shooting"), 0.5)


func test_set_level_clamps() -> bool:
	var s := PlayerSkills.new()
	s.set_level("driving", 150.0)
	var high := s.level("driving")
	s.set_level("driving", -20.0)
	var low := s.level("driving")
	return high == PlayerSkills.MAX_SKILL and low == 0.0


func test_set_level_unknown_is_noop() -> bool:
	var s := PlayerSkills.new()
	s.set_level("nope", 50.0)
	return not s.has_skill("nope")


func test_overall_mastery() -> bool:
	var s := PlayerSkills.new(TWO)
	s.set_level("a", 50.0)
	s.set_level("b", 50.0)
	return is_equal_approx(s.overall_mastery(), 0.5)


func test_overall_mastery_empty() -> bool:
	var s := PlayerSkills.new([{"id": "only", "rate": 1.0}])
	return s.overall_mastery() == 0.0


func test_to_dict_and_load_round_trip() -> bool:
	var s := PlayerSkills.new()
	s.train("driving", 10.0)
	s.set_level("shooting", 33.0)
	var saved := s.to_dict()
	var restored := PlayerSkills.new()
	restored.load_dict(saved)
	return (
		is_equal_approx(restored.level("driving"), s.level("driving"))
		and restored.level("shooting") == 33.0
	)


func test_load_ignores_unknown_and_bad_values() -> bool:
	var s := PlayerSkills.new()
	s.load_dict({"driving": 40.0, "nope": 99.0, "shooting": "bad"})
	return s.level("driving") == 40.0 and s.level("shooting") == 0.0 and not s.has_skill("nope")
