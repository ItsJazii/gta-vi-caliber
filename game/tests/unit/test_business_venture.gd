extends RefCounted
## Unit tests for BusinessVenture (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Covers the full operate-a-business loop: catalogue validation, acquisition +
## wallet results, supply restock + clamp, supply->product accrual (with supply and
## max_product caps), staff/tier throughput, demand/heat sale pricing, cash-out,
## empire aggregates, and save round-trip. coke_lab tuning: 10 product/day,
## 2.0 supply per product, 200 max product, $2000 sale, 6 staff, 3 tiers.


func test_default_ventures_loaded() -> bool:
	var b := BusinessVenture.new()
	return b.venture_count() >= 4 and b.has_venture("coke_lab") and b.has_venture("nightclub")


func test_malformed_ventures_dropped() -> bool:
	var b := (
		BusinessVenture
		. new(
			[
				{"id": "ok", "product_per_day": 10.0, "sale_value": 100},
				{"id": "", "product_per_day": 10.0, "sale_value": 100},
				{"product_per_day": 5.0, "sale_value": 100},  # no id
				{"id": "bad", "product_per_day": 0.0, "sale_value": 100},  # non-positive rate
				{"id": "ok", "product_per_day": 7.0, "sale_value": 100},  # duplicate id
			]
		)
	)
	return b.venture_count() == 1 and b.has_venture("ok")


func test_acquire_deducts_and_marks_owned() -> bool:
	var b := BusinessVenture.new()
	var r := b.acquire("coke_lab", 50000, 80000)
	return r["success"] and r["new_balance"] == 30000 and b.owns("coke_lab") and r["cost"] == 50000


func test_acquire_rejects_unowned_unknown_and_insufficient() -> bool:
	var b := BusinessVenture.new()
	var ghost := b.acquire("ghost", 1, 9999)
	var broke := b.acquire("nightclub", 999999, 100)
	b.acquire("coke_lab", 10, 1000)
	var dup := b.acquire("coke_lab", 10, 1000)
	return (
		ghost["success"] == false
		and broke["success"] == false
		and broke["new_balance"] == 100
		and dup["success"] == false
		and "already owned" in dup["reason"]
	)


func test_buy_supplies_requires_ownership_and_clamps() -> bool:
	var b := BusinessVenture.new()
	var unowned := b.buy_supplies("coke_lab", 10, 1, 1000)
	b.acquire("coke_lab", 0, 1000)
	var r := b.buy_supplies("coke_lab", 1000000, 1, 10000000)
	# ceiling = max_product(200) * product_per_supply(2.0) = 400, not 1000000.
	return (
		unowned["success"] == false
		and r["success"]
		and is_equal_approx(b.supply_in("coke_lab"), 400.0)
	)


func test_accrue_converts_supply_to_product() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 1000)
	b.buy_supplies("coke_lab", 400, 1, 1000)
	var rate := b.production_rate("coke_lab")  # 10 * 1.0 * 1.0
	b.accrue(1.0)
	var produced_ok := is_equal_approx(b.product_in("coke_lab"), rate)
	var supply_ok := is_equal_approx(b.supply_in("coke_lab"), 400.0 - rate * 2.0)
	# Non-positive spans are no-ops.
	b.accrue(0.0)
	b.accrue(-3.0)
	var noop_ok := is_equal_approx(b.product_in("coke_lab"), rate)
	return produced_ok and supply_ok and noop_ok


func test_production_zero_without_supply() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 1000)  # acquired but never stocked
	var rate0 := b.production_rate("coke_lab")
	b.accrue(5.0)
	return rate0 == 0.0 and b.product_in("coke_lab") == 0.0


func test_accrue_caps_at_max_product() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 1000)
	b.buy_supplies("coke_lab", 400, 1, 1000)
	b.accrue(9999.0)
	return is_equal_approx(b.product_in("coke_lab"), 200.0)  # max_product, no overflow


func test_hire_raises_rate_and_respects_bounds() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 1000)
	b.buy_supplies("coke_lab", 400, 1, 1000)  # supply so production_rate > 0
	var rate0 := b.production_rate("coke_lab")
	var hired := b.hire("coke_lab")
	var rate1 := b.production_rate("coke_lab")
	for _i in 5:
		b.hire("coke_lab")  # up to max_staff (6)
	var at_max := b.staff_in("coke_lab")
	var over := b.hire("coke_lab")
	for _j in 6:
		b.fire("coke_lab")  # back to 0
	var under := b.fire("coke_lab")
	return hired and rate1 > rate0 and at_max == 6 and over == false and under == false


func test_upgrade_raises_tier_and_rate() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 100000)
	b.buy_supplies("coke_lab", 400, 1, 1000)  # supply so rate > 0
	var rate0 := b.production_rate("coke_lab")
	var r := b.upgrade("coke_lab", 20000, 100000)
	var tier1 := b.tier_in("coke_lab")
	var rate1 := b.production_rate("coke_lab")
	b.upgrade("coke_lab", 0, 100000)  # tier 2
	b.upgrade("coke_lab", 0, 100000)  # tier 3 (max)
	var past := b.upgrade("coke_lab", 0, 100000)
	return r["success"] and tier1 == 1 and rate1 > rate0 and past["success"] == false


func test_sale_price_scales_with_demand_and_heat() -> bool:
	var b := BusinessVenture.new()  # coke_lab sale_value = 2000
	var base := b.sale_price("coke_lab", 1.0, 0.0)
	var high_demand := b.sale_price("coke_lab", 2.0, 0.0)
	var hot := b.sale_price("coke_lab", 1.0, 1.0)
	return (
		base == 2000
		and high_demand > base
		and hot == int(2000 * (1.0 - BusinessVenture.HEAT_DISCOUNT))
		and hot < base
	)


func test_sell_pays_proceeds_and_clears_stock() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 1000)
	b.buy_supplies("coke_lab", 400, 1, 1000)
	b.accrue(1.0)  # product = 10
	var price := b.sale_price("coke_lab", 1.0, 0.0)
	var before := b.product_in("coke_lab")
	var r := b.sell("coke_lab", 5, 1.0, 0.0)
	var expect_sold := mini(5, int(floor(before)))
	var sell_ok: bool = (
		r["success"]
		and r["sold"] == expect_sold
		and r["proceeds"] == expect_sold * price
		and is_equal_approx(b.product_in("coke_lab"), before - float(expect_sold))
		and b.gross_earned() == r["proceeds"]
	)
	b.sell("coke_lab", 999, 1.0, 0.0)  # drains the rest
	var empty := b.sell("coke_lab", 1, 1.0, 0.0)
	var unowned := b.sell("nightclub", 1, 1.0, 0.0)
	return sell_ok and empty["success"] == false and unowned["success"] == false


func test_total_and_gross_aggregate() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 100000)
	b.acquire("weed_farm", 0, 100000)
	b.buy_supplies("coke_lab", 400, 1, 1000)
	b.buy_supplies("weed_farm", 1000, 1, 1000)
	b.accrue(1.0)  # coke +10, weed +12
	var r1 := b.sell("coke_lab", 4, 1.0, 0.0)  # leaves 6
	var r2 := b.sell("weed_farm", 2, 1.0, 0.0)  # leaves 10
	var total := b.total_product()
	return total == 16 and b.gross_earned() == r1["proceeds"] + r2["proceeds"]


func test_serialize_restore_roundtrip() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 100000)
	b.buy_supplies("coke_lab", 100, 1, 1000)
	b.hire("coke_lab")
	b.hire("coke_lab")
	b.upgrade("coke_lab", 0, 100000)
	b.accrue(0.5)
	var snap := b.serialize()
	var fresh := BusinessVenture.new()
	fresh.restore(snap)
	var match_ok: bool = (
		fresh.owned_ids() == b.owned_ids()
		and is_equal_approx(fresh.supply_in("coke_lab"), b.supply_in("coke_lab"))
		and is_equal_approx(fresh.product_in("coke_lab"), b.product_in("coke_lab"))
		and fresh.staff_in("coke_lab") == b.staff_in("coke_lab")
		and fresh.tier_in("coke_lab") == b.tier_in("coke_lab")
	)
	var bad := BusinessVenture.new()
	bad.restore({"owned": "garbage"})
	return match_ok and bad.owned_ids().is_empty()


func test_buy_supplies_charges_only_fitted_units() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 10000000)
	# Order a million units; only the 400 that fit the ceiling are charged for.
	var r := b.buy_supplies("coke_lab", 1000000, 1, 10000000)
	return r["cost"] == 400 and r["new_balance"] == 10000000 - 400


func test_buy_supplies_rejects_nonpositive_unit_cost() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 1000)
	# A negative price would otherwise be a money printer; zero would be free supply.
	var neg := b.buy_supplies("coke_lab", 400, -5, 1000)
	var zero := b.buy_supplies("coke_lab", 400, 0, 1000)
	return (
		neg["success"] == false
		and neg["new_balance"] == 1000
		and zero["success"] == false
		and b.supply_in("coke_lab") == 0.0
	)


func test_buy_supplies_already_full_fails() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 100000)
	b.buy_supplies("coke_lab", 400, 1, 100000)  # fill to ceiling
	var again := b.buy_supplies("coke_lab", 50, 1, 100000)
	return again["success"] == false and is_equal_approx(b.supply_in("coke_lab"), 400.0)


func test_buy_supplies_insufficient_after_clamp() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 100000)
	# Fitted units = 400, unit_cost 100 -> cost 40000 > balance 39999: whole buy fails.
	var r := b.buy_supplies("coke_lab", 400, 100, 39999)
	return r["success"] == false and r["new_balance"] == 39999 and b.supply_in("coke_lab") == 0.0


func test_upgrade_charges_wallet() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 100000)
	var r := b.upgrade("coke_lab", 20000, 100000)
	return r["success"] and r["cost"] == 20000 and r["new_balance"] == 80000


func test_sale_price_unknown_venture_is_zero() -> bool:
	var b := BusinessVenture.new()
	return b.sale_price("ghost", 1.0, 0.0) == 0 and b.sale_price("", 2.0, 0.5) == 0


func test_sale_price_floors_cheap_venture_at_one() -> bool:
	# sale_value 1 at min demand + full heat rounds to 0; must floor to 1, not burn for free.
	var b := BusinessVenture.new([{"id": "penny", "product_per_day": 5.0, "sale_value": 1}])
	return b.sale_price("penny", 0.5, 1.0) == 1


func test_sale_price_clamps_demand_band() -> bool:
	var b := BusinessVenture.new()
	var floor_eq := (
		b.sale_price("coke_lab", 0.1, 0.0)
		== b.sale_price("coke_lab", BusinessVenture.DEMAND_MIN, 0.0)
	)
	var ceil_eq := (
		b.sale_price("coke_lab", 99.0, 0.0)
		== b.sale_price("coke_lab", BusinessVenture.DEMAND_MAX, 0.0)
	)
	var floored_below_base := (
		b.sale_price("coke_lab", 0.1, 0.0) < b.sale_price("coke_lab", 1.0, 0.0)
	)
	return floor_eq and ceil_eq and floored_below_base


func test_gross_accumulates_across_sells() -> bool:
	var b := BusinessVenture.new()
	b.acquire("coke_lab", 0, 100000)
	b.buy_supplies("coke_lab", 400, 1, 1000)
	b.accrue(1.0)  # product = 10
	var r1 := b.sell("coke_lab", 3, 1.0, 0.0)
	var r2 := b.sell("coke_lab", 2, 1.0, 0.0)
	return b.gross_earned() == r1["proceeds"] + r2["proceeds"]


func test_restore_clamps_out_of_range_fields() -> bool:
	var b := BusinessVenture.new()
	(
		b
		. restore(
			{
				"owned":
				{"coke_lab": {"supply": -10.0, "product": 999999.0, "staff": 99, "tier": 99}},
				"gross": -500,
			}
		)
	)
	return (
		b.supply_in("coke_lab") == 0.0
		and is_equal_approx(b.product_in("coke_lab"), 200.0)  # clamped to max_product
		and b.staff_in("coke_lab") == 6  # clamped to max_staff
		and b.tier_in("coke_lab") == 3  # clamped to max_tier
		and b.gross_earned() == 0
	)  # negative gross clamped


func test_hire_fire_unowned_returns_false() -> bool:
	var b := BusinessVenture.new()
	return b.hire("nightclub") == false and b.fire("nightclub") == false
