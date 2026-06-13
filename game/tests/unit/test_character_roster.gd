extends RefCounted
## Unit tests for CharacterRoster (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_default_roster_loaded() -> bool:
	var r := CharacterRoster.new()
	return r.character_count() == 2 and r.has_character("mara") and r.has_character("rico")


func test_first_character_is_active() -> bool:
	var r := CharacterRoster.new()
	return r.active() == "mara" and r.active_name() == "Mara"


func test_malformed_characters_dropped() -> bool:
	var r := (
		CharacterRoster
		. new(
			[
				{"id": "ok", "name": "OK"},
				{"id": "", "name": "Empty"},
				{"name": "NoId"},
				{"id": "ok", "name": "Dupe"},  # duplicate id
			]
		)
	)
	return r.character_count() == 1 and r.has_character("ok")


func test_money_defaults() -> bool:
	var r := CharacterRoster.new()
	return r.money_of("mara") == 2500 and r.money_of("rico") == 1500 and r.money_of("nope") == 0


func test_switch_changes_active() -> bool:
	var r := CharacterRoster.new()
	var ok := r.switch_to("rico")
	return ok and r.active() == "rico"


func test_switch_to_unknown_fails() -> bool:
	var r := CharacterRoster.new()
	return not r.switch_to("nope") and r.active() == "mara"


func test_switch_to_active_fails() -> bool:
	var r := CharacterRoster.new()
	return not r.switch_to("mara") and r.active() == "mara"


func test_switch_cooldown() -> bool:
	var r := CharacterRoster.new()
	r.switch_to("rico", 0.0)
	# Immediately switching back is on cooldown; after the window it's allowed.
	var blocked := r.switch_to("mara", 1.0)
	var allowed := r.switch_to("mara", CharacterRoster.SWITCH_COOLDOWN)
	return not blocked and allowed and r.active() == "mara"


func test_repeated_untimed_switches() -> bool:
	# A caller that doesn't pass a timestamp can switch back and forth freely.
	var r := CharacterRoster.new()
	return (
		r.switch_to("rico") and r.switch_to("mara") and r.switch_to("rico") and r.active() == "rico"
	)


func test_independent_money_persists_across_switch() -> bool:
	var r := CharacterRoster.new()
	r.add_money("mara", 1000)  # 3500
	r.switch_to("rico")
	r.add_money("rico", 500)  # 2000
	# Mara's wallet is untouched by Rico's activity.
	return r.money_of("mara") == 3500 and r.money_of("rico") == 2000


func test_add_money_floors_at_zero() -> bool:
	var r := CharacterRoster.new()
	r.add_money("rico", -9999)
	return r.money_of("rico") == 0


func test_wanted_clamps() -> bool:
	var r := CharacterRoster.new()
	r.set_wanted("mara", 9)
	var high := r.wanted_of("mara")
	r.set_wanted("mara", -2)
	return high == CharacterRoster.MAX_STARS and r.wanted_of("mara") == 0


func test_position_persists_per_character() -> bool:
	var r := CharacterRoster.new()
	r.set_position("mara", Vector3(10, 0, 20))
	r.set_position("rico", Vector3(-5, 0, 8))
	return (
		r.position_of("mara") == Vector3(10, 0, 20) and r.position_of("rico") == Vector3(-5, 0, 8)
	)


func test_save_round_trip() -> bool:
	var r := CharacterRoster.new()
	r.add_money("mara", 1000)
	r.set_wanted("rico", 3)
	r.set_position("rico", Vector3(1, 2, 3))
	r.switch_to("rico")
	var saved := r.to_dict()
	var restored := CharacterRoster.new()
	restored.load_dict(saved)
	return (
		restored.active() == "rico"
		and restored.money_of("mara") == 3500
		and restored.wanted_of("rico") == 3
		and restored.position_of("rico") == Vector3(1, 2, 3)
	)
