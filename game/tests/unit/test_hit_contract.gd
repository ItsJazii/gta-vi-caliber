extends RefCounted
## Unit tests for HitContract (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Includes a cross-system test proving the signature loop: a completed hit's
## market_effect, fed to StockMarket.apply_rivalry_shock, tanks the target's stock
## and lifts a sector rival.


func test_default_board_loaded() -> bool:
	var hc := HitContract.new()
	return hc.contract_count() == 3 and hc.has_contract("tech_takedown")


func test_malformed_contracts_dropped() -> bool:
	var hc := (
		HitContract
		. new(
			[
				{"id": "ok", "reward": 1000},
				{"id": "", "reward": 1000},
				{"reward": 1000},  # no id
				{"id": "free", "reward": 0},  # non-positive reward
				{"id": "ok", "reward": 9999},  # duplicate id
			]
		)
	)
	return hc.contract_count() == 1 and hc.has_contract("ok")


func test_reward_lookup() -> bool:
	var hc := HitContract.new()
	return hc.reward_of("airline_war") == 18000 and hc.reward_of("nope") == -1


func test_market_effect_lookup() -> bool:
	var hc := HitContract.new()
	var e := hc.market_effect_of("airline_war")
	return (
		e["company_id"] == "pelican_air"
		and is_equal_approx(e["magnitude"], -0.4)
		and hc.market_effect_of("nope").is_empty()
	)


func test_all_available_initially() -> bool:
	var hc := HitContract.new()
	return hc.available().size() == 3 and not hc.has_active()


func test_accept_sets_active() -> bool:
	var hc := HitContract.new()
	return hc.accept("tech_takedown") and hc.active() == "tech_takedown" and hc.has_active()


func test_accept_unknown_fails() -> bool:
	var hc := HitContract.new()
	return not hc.accept("nope") and not hc.has_active()


func test_accept_while_active_fails() -> bool:
	var hc := HitContract.new()
	hc.accept("tech_takedown")
	return not hc.accept("airline_war") and hc.active() == "tech_takedown"


func test_available_excludes_active() -> bool:
	var hc := HitContract.new()
	hc.accept("tech_takedown")
	return not hc.available().has("tech_takedown") and hc.available().size() == 2


func test_abandon_returns_to_pool() -> bool:
	var hc := HitContract.new()
	hc.accept("tech_takedown")
	var dropped := hc.abandon()
	return (
		dropped == "tech_takedown" and not hc.has_active() and hc.available().has("tech_takedown")
	)


func test_complete_banks_reward_and_marks_done() -> bool:
	var hc := HitContract.new()
	hc.accept("tech_takedown")
	var r := hc.complete()
	return (
		r["success"]
		and r["reward"] == 25000
		and hc.is_completed("tech_takedown")
		and not hc.has_active()
		and hc.total_earned() == 25000
	)


func test_complete_returns_market_effect() -> bool:
	var hc := HitContract.new()
	hc.accept("airline_war")
	var effect: Dictionary = hc.complete()["market_effect"]
	return effect["company_id"] == "pelican_air" and is_equal_approx(effect["magnitude"], -0.4)


func test_complete_no_active_fails() -> bool:
	var hc := HitContract.new()
	var r := hc.complete()
	return not r["success"] and r["reward"] == 0


func test_cannot_reaccept_completed() -> bool:
	var hc := HitContract.new()
	hc.accept("tech_takedown")
	hc.complete()
	return not hc.accept("tech_takedown")


func test_available_excludes_completed() -> bool:
	var hc := HitContract.new()
	hc.accept("tech_takedown")
	hc.complete()
	return not hc.available().has("tech_takedown") and hc.available().size() == 2


func test_total_earned_accumulates() -> bool:
	var hc := HitContract.new()
	hc.accept("tech_takedown")
	hc.complete()  # 25000
	hc.accept("airline_war")
	hc.complete()  # 18000
	return hc.total_earned() == 43000 and hc.completed_count() == 2


func test_hit_moves_stock_market() -> bool:
	# The signature loop: complete a hit, apply its effect to the live market.
	var hc := HitContract.new()
	var sm := StockMarket.new()
	var base_pelican := sm.price("pelican_air")
	var base_augury := sm.price("augury_air")
	hc.accept("airline_war")
	var effect: Dictionary = hc.complete()["market_effect"]
	sm.apply_rivalry_shock(effect["company_id"], effect["magnitude"], effect["spillover"])
	# Target airline drops; its aviation rival rises.
	return sm.price("pelican_air") < base_pelican and sm.price("augury_air") > base_augury
