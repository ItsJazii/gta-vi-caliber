extends RefCounted
## Unit tests for GangTerritory (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). Deterministic, no RNG.


func _sample() -> GangTerritory:
	return (
		GangTerritory
		. new(
			[
				{"id": "north", "owner": "vice_kings"},
				{"id": "south", "owner": "marina_cartel"},
			]
		)
	)


func test_defaults_owned_by_gangs() -> bool:
	var t := GangTerritory.new()
	return (
		t.district_count() == 4
		and t.owner_of("downtown") == "vice_kings"
		and t.owner_of("beach") == "los_santos_set"
		and t.player_districts().is_empty()
	)


func test_default_influence_zero() -> bool:
	var t := GangTerritory.new()
	return is_equal_approx(t.influence_in("downtown"), 0.0)


func test_add_influence_raises() -> bool:
	var t := _sample()
	t.add_influence("north", 0.3)
	return is_equal_approx(t.influence_in("north"), 0.3)


func test_add_influence_clamped_at_one() -> bool:
	var t := _sample()
	t.add_influence("north", 0.8)
	t.add_influence("north", 0.8)
	return is_equal_approx(t.influence_in("north"), 1.0)


func test_negative_influence_ignored() -> bool:
	var t := _sample()
	t.add_influence("north", -0.5)
	return is_equal_approx(t.influence_in("north"), 0.0)


func test_lose_influence_lowers() -> bool:
	var t := _sample()
	t.add_influence("north", 0.6)
	t.lose_influence("north", 0.2)
	return is_equal_approx(t.influence_in("north"), 0.4)


func test_lose_influence_floored_at_zero() -> bool:
	var t := _sample()
	t.add_influence("north", 0.3)
	t.lose_influence("north", 0.9)
	return is_equal_approx(t.influence_in("north"), 0.0)


func test_lose_influence_negative_ignored() -> bool:
	var t := _sample()
	t.add_influence("north", 0.5)
	t.lose_influence("north", -0.2)
	return is_equal_approx(t.influence_in("north"), 0.5)


func test_is_contested_threshold() -> bool:
	var t := _sample()
	t.add_influence("north", 0.4)
	return t.is_contested("north", 0.3) and not t.is_contested("north", 0.5)


func test_take_over_fails_below_full() -> bool:
	var t := _sample()
	t.add_influence("north", 0.9)
	var flipped := t.take_over("north")
	return not flipped and t.owner_of("north") == "vice_kings"


func test_take_over_succeeds_at_full() -> bool:
	var t := _sample()
	t.add_influence("north", 1.0)
	var flipped := t.take_over("north")
	return flipped and t.owner_of("north") == "player"


func test_take_over_twice_returns_false() -> bool:
	var t := _sample()
	t.add_influence("north", 1.0)
	t.take_over("north")
	return not t.take_over("north")


func test_player_districts_update() -> bool:
	var t := _sample()
	t.add_influence("south", 1.0)
	t.take_over("south")
	return t.player_districts() == ["south"]


func test_controlled_fraction() -> bool:
	var t := _sample()
	t.add_influence("north", 1.0)
	t.take_over("north")
	return is_equal_approx(t.controlled_fraction(), 0.5)


func test_all_owned_after_full_takeover() -> bool:
	var t := _sample()
	t.add_influence("north", 1.0)
	t.add_influence("south", 1.0)
	t.take_over("north")
	t.take_over("south")
	return t.all_owned() and is_equal_approx(t.controlled_fraction(), 1.0)


func test_all_owned_false_initially() -> bool:
	var t := _sample()
	return not t.all_owned()


func test_unknown_district_safe() -> bool:
	var t := _sample()
	t.add_influence("ghost", 0.5)
	t.lose_influence("ghost", 0.5)
	return (
		t.owner_of("ghost") == ""
		and is_equal_approx(t.influence_in("ghost"), 0.0)
		and not t.is_contested("ghost", 0.0)
		and not t.take_over("ghost")
	)


func test_controlled_fraction_zero_when_empty() -> bool:
	var t := GangTerritory.new([])
	t.restore({"districts": []})
	return is_equal_approx(t.controlled_fraction(), 0.0) and not t.all_owned()


func test_serialize_restore_round_trip() -> bool:
	var t := _sample()
	t.add_influence("north", 1.0)
	t.take_over("north")
	t.add_influence("south", 0.45)
	var snapshot := t.serialize()
	var other := GangTerritory.new()
	other.restore(snapshot)
	return (
		other.district_count() == 2
		and other.owner_of("north") == "player"
		and is_equal_approx(other.influence_in("south"), 0.45)
		and other.owner_of("south") == "marina_cartel"
	)


func test_restore_malformed_empty() -> bool:
	var t := _sample()
	t.restore({"districts": "junk"})
	return t.district_count() == 0


func test_reset_clears() -> bool:
	var t := GangTerritory.new()
	t.add_influence("downtown", 1.0)
	t.take_over("downtown")
	t.reset()
	return (
		is_equal_approx(t.influence_in("downtown"), 0.0)
		and t.owner_of("downtown") == "vice_kings"
		and t.player_districts().is_empty()
	)
