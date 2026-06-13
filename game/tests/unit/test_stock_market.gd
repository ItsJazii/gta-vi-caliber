extends RefCounted
## Unit tests for StockMarket (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Prices are base_price * a multiplier the model moves; assertions either use a
## known neutral multiplier (1.0) or compare relative direction, so they stay
## deterministic and engine-correct. Kept under the 25-public-method lint cap by
## folding related assertions into single tests.

const STABLE := [{"id": "rock_corp", "sector": "utility", "base_price": 100, "volatility": 0.0}]


func test_default_roster_loaded() -> bool:
	var m := StockMarket.new()
	return m.company_count() == 7 and m.has_company("augury_air")


func test_default_sectors() -> bool:
	var m := StockMarket.new()
	return m.sectors().size() == 5 and m.sectors().has("aviation")


func test_known_lookups() -> bool:
	var m := StockMarket.new()
	return (
		m.base_price("augury_air") == 42
		and m.price("augury_air") == 42  # neutral multiplier -> price == base
		and m.sector_of("augury_air") == "aviation"
		and m.volatility("augury_air") == 0.7
	)


func test_unknown_lookups_are_neutral() -> bool:
	var m := StockMarket.new()
	return (
		m.base_price("nope") == -1
		and m.price("nope") == -1
		and m.sector_of("nope") == ""
		and m.volatility("nope") == 0.0
		and m.multiplier("nope") == 1.0
	)


func test_malformed_companies_dropped() -> bool:
	var m := (
		StockMarket
		. new(
			[
				{"id": "ok", "sector": "x", "base_price": 50, "volatility": 0.5},
				{"id": "no_price", "sector": "x"},
				{"sector": "x", "base_price": 10},
				{"id": "neg", "base_price": -5},
				{"id": "ok", "base_price": 999},  # duplicate id dropped
			]
		)
	)
	return m.company_count() == 1 and m.has_company("ok")


func test_volatility_clamped_on_register() -> bool:
	var m := StockMarket.new([{"id": "wild", "base_price": 10, "volatility": 9.0}])
	return m.volatility("wild") == 1.0


func test_company_event_moves_price_both_ways() -> bool:
	var up := StockMarket.new()
	up.apply_company_event("augury_air", 1.0)
	# 42 * (1 + 1.0*0.7) = 71.4 -> 71
	var down := StockMarket.new()
	down.apply_company_event("augury_air", -0.5)
	# 42 * (1 - 0.5*0.7) = 27.3 -> 27
	return up.price("augury_air") == 71 and down.price("augury_air") == 27


func test_event_unknown_company_is_false() -> bool:
	var m := StockMarket.new()
	return m.apply_company_event("nope", 1.0) == false


func test_volatility_scales_reaction() -> bool:
	# Same magnitude: the higher-volatility stock moves further from base.
	var m := (
		StockMarket
		. new(
			[
				{"id": "jumpy", "base_price": 100, "volatility": 1.0},
				{"id": "calm", "base_price": 100, "volatility": 0.2},
			]
		)
	)
	m.apply_company_event("jumpy", 0.5)
	m.apply_company_event("calm", 0.5)
	return m.price("jumpy") > m.price("calm") and m.price("calm") > 100


func test_zero_volatility_ignores_events() -> bool:
	var m := StockMarket.new(STABLE)
	m.apply_company_event("rock_corp", 5.0)
	return m.price("rock_corp") == 100


func test_sector_event_counts_moved() -> bool:
	var m := StockMarket.new()
	var moved := m.apply_sector_event("aviation", 0.1)
	# augury_air + pelican_air move; an unrelated stock holds.
	return moved == 2 and m.price("bittn_tech") == 120


func test_rivalry_shock_target_down_rivals_up() -> bool:
	var m := StockMarket.new()
	var base_pelican := m.price("pelican_air")
	var ok := m.apply_rivalry_shock("augury_air", -0.5, 1.0)
	# Target augury falls; aviation rival pelican rises; unrelated food stock holds.
	return (
		ok
		and m.price("augury_air") < 42
		and m.price("pelican_air") > base_pelican
		and m.price("cluckin_co") == 24
	)


func test_rivalry_shock_unknown_is_false() -> bool:
	var m := StockMarket.new()
	return m.apply_rivalry_shock("nope", 0.5, 1.0) == false


func test_multiplier_clamps_both_ends() -> bool:
	var high := StockMarket.new()
	high.apply_company_event("augury_air", 100.0)  # clamp at 8.0 -> 42*8 = 336
	var low := StockMarket.new()
	low.apply_company_event("augury_air", -100.0)  # clamp at 0.1 -> round(42*0.1) = 4
	return high.price("augury_air") == 336 and low.price("augury_air") == 4


func test_buy_success_deducts_and_holds() -> bool:
	var m := StockMarket.new()
	var r := m.buy("augury_air", 10, 1000)
	return (
		r["success"]
		and r["cost"] == 420
		and r["new_balance"] == 580
		and m.shares_held("augury_air") == 10
		and m.avg_cost("augury_air") == 42.0
	)


func test_buy_insufficient_funds() -> bool:
	var m := StockMarket.new()
	var r := m.buy("augury_air", 10, 100)
	return not r["success"] and r["new_balance"] == 100 and m.shares_held("augury_air") == 0


func test_buy_rejects_bad_input() -> bool:
	var m := StockMarket.new()
	return not m.buy("nope", 1, 1000)["success"] and not m.buy("augury_air", 0, 1000)["success"]


func test_buy_weighted_average_cost() -> bool:
	var m := StockMarket.new()
	m.buy("augury_air", 10, 5000)  # 10 @ 42
	m.apply_company_event("augury_air", 1.0)  # price -> 71
	m.buy("augury_air", 10, 5000)  # 10 @ 71
	# (420 + 710) / 20 = 56.5
	return m.shares_held("augury_air") == 20 and m.avg_cost("augury_air") == 56.5


func test_sell_realizes_profit() -> bool:
	var m := StockMarket.new()
	m.buy("augury_air", 10, 5000)  # avg 42
	m.apply_company_event("augury_air", 1.0)  # price -> 71
	var r := m.sell("augury_air", 5)
	# proceeds 71*5 = 355; realized (71-42)*5 = 145
	return (
		r["success"]
		and r["proceeds"] == 355
		and r["realized"] == 145
		and m.shares_held("augury_air") == 5
		and m.realized_gain() == 145
	)


func test_sell_more_than_held_fails() -> bool:
	var m := StockMarket.new()
	m.buy("augury_air", 3, 5000)
	var r := m.sell("augury_air", 4)
	return not r["success"] and m.shares_held("augury_air") == 3


func test_sell_all_erases_position() -> bool:
	var m := StockMarket.new()
	m.buy("augury_air", 5, 5000)
	m.sell("augury_air", 5)
	return m.shares_held("augury_air") == 0 and m.avg_cost("augury_air") == 0.0


func test_portfolio_value_and_unrealized() -> bool:
	var m := StockMarket.new()
	m.buy("augury_air", 10, 5000)  # invested 420
	m.apply_company_event("augury_air", 1.0)  # price -> 71
	# value 710, invested 420, unrealized 290
	return m.portfolio_value() == 710 and m.total_invested() == 420 and m.unrealized_gain() == 290


func test_fluctuate_is_deterministic() -> bool:
	var a := StockMarket.new()
	var b := StockMarket.new()
	a.fluctuate(StockMarket.make_rng(7), 1.0)
	b.fluctuate(StockMarket.make_rng(7), 1.0)
	return a.price("augury_air") == b.price("augury_air")


func test_fluctuate_noop_cases() -> bool:
	var no_rng := StockMarket.new()
	no_rng.fluctuate(null, 1.0)
	var stable := StockMarket.new(STABLE)
	stable.fluctuate(StockMarket.make_rng(3), 1.0)  # zero-volatility stock holds
	return no_rng.price("augury_air") == 42 and stable.price("rock_corp") == 100
