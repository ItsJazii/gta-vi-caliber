extends RefCounted
## Unit tests for DistrictEconomy (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Desirability is a float sum, so those checks use is_equal_approx; property_value
## is rounded to int and compared exactly. Includes a GangTerritory composition
## test (turf influence feeds district desirability).


func test_default_districts_loaded() -> bool:
	var e := DistrictEconomy.new()
	return e.district_count() == 4 and e.has_district("downtown") and e.has_district("beach")


func test_malformed_districts_dropped() -> bool:
	var e := (
		DistrictEconomy
		. new(
			[
				{"id": "ok", "base": 1.0},
				{"id": "", "base": 1.0},
				{"base": 1.0},  # no id
				{"id": "free", "base": 0.0},  # non-positive base
				{"id": "ok", "base": 2.0},  # duplicate id
			]
		)
	)
	return e.district_count() == 1 and e.has_district("ok")


func test_base_index_lookup() -> bool:
	var e := DistrictEconomy.new()
	return is_equal_approx(e.base_index("beach"), 1.4) and e.base_index("nope") == -1.0


func test_neutral_desirability_is_base() -> bool:
	var e := DistrictEconomy.new()
	return is_equal_approx(e.desirability("downtown"), 1.2)


func test_unknown_desirability_is_neutral() -> bool:
	var e := DistrictEconomy.new()
	return e.desirability("nope") == 1.0 and e.property_value(1000, "nope") == 1000


func test_control_raises_desirability() -> bool:
	var e := DistrictEconomy.new()
	e.set_control("downtown", 1.0)  # +0.3
	return is_equal_approx(e.desirability("downtown"), 1.5)


func test_control_clamped() -> bool:
	var e := DistrictEconomy.new()
	e.set_control("downtown", 5.0)
	return e.control_in("downtown") == 1.0


func test_heat_lowers_desirability() -> bool:
	var e := DistrictEconomy.new()
	e.add_heat("downtown", 0.5)  # -0.2
	return is_equal_approx(e.desirability("downtown"), 1.0)


func test_investment_raises_and_caps() -> bool:
	var e := DistrictEconomy.new()
	for _i in range(5):
		e.invest("downtown")  # capped at 3 -> +0.3
	return e.investment_in("downtown") == 5 and is_equal_approx(e.desirability("downtown"), 1.5)


func test_divest_floors_at_zero() -> bool:
	var e := DistrictEconomy.new()
	e.invest("docks")
	e.divest("docks")
	e.divest("docks")
	return e.investment_in("docks") == 0


func test_desirability_clamps_high() -> bool:
	var e := DistrictEconomy.new()
	e.set_control("beach", 1.0)  # base 1.4 + 0.3
	for _i in range(3):
		e.invest("beach")  # + 0.3 -> 2.0 (cap)
	return is_equal_approx(e.desirability("beach"), DistrictEconomy.DESIR_MAX)


func test_desirability_clamps_low() -> bool:
	var e := DistrictEconomy.new()
	e.add_heat("docks", 1.0)  # base 0.7 - 0.4 = 0.3 -> clamp 0.4
	return is_equal_approx(e.desirability("docks"), DistrictEconomy.DESIR_MIN)


func test_property_value_scales() -> bool:
	var e := DistrictEconomy.new()
	# downtown desirability 1.2 -> 100000 * 1.2 = 120000
	return e.property_value(100000, "downtown") == 120000


func test_income_multiplier_tracks_desirability() -> bool:
	var e := DistrictEconomy.new()
	e.set_control("beach", 1.0)
	return is_equal_approx(e.income_multiplier("beach"), e.desirability("beach"))


func test_decay_heat_floors() -> bool:
	var e := DistrictEconomy.new()
	e.add_heat("downtown", 0.3)
	e.decay_heat("downtown", 0.5)
	return e.heat_in("downtown") == 0.0


func test_decay_all_heat() -> bool:
	var e := DistrictEconomy.new()
	e.add_heat("downtown", 0.5)
	e.add_heat("beach", 0.5)
	e.decay_all_heat(0.2)
	return is_equal_approx(e.heat_in("downtown"), 0.3) and is_equal_approx(e.heat_in("beach"), 0.3)


func test_gang_influence_drives_desirability() -> bool:
	# Composition: taking turf (GangTerritory influence) gentrifies the district.
	var gt := GangTerritory.new()
	gt.add_influence("downtown", 1.0)
	var e := DistrictEconomy.new()
	var before := e.desirability("downtown")
	e.set_control("downtown", gt.influence_in("downtown"))
	return e.desirability("downtown") > before and e.property_value(100000, "downtown") > 120000
