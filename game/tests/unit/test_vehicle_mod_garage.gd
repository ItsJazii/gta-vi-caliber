extends RefCounted
## Unit tests for VehicleModGarage._best_affordable — the drive-in's category-selection
## policy. It is a static, pure function over a VehicleModShop, so the policy is locked
## here without a scene/node. See tests/run_tests.gd for the runner contract: test_*
## methods return true to pass.
##
## The headline case is test_lowest_level_beats_cheaper_higher_level: it pins the NEW
## least-upgraded-first behavior, which the old cheapest-first logic would have failed
## (it would buy the cheaper, already-upgraded category instead of spreading tuning).


func test_unaffordable_selects_nothing() -> bool:
	# The only category's next tier costs more than the wallet -> "".
	var shop := VehicleModShop.new({"a": [100]})
	return VehicleModGarage._best_affordable(shop, 50) == ""


func test_maxed_selects_nothing() -> bool:
	var shop := VehicleModShop.new({"a": [100]})
	shop.upgrade("a", 1000)  # a -> level 1 (maxed: max_level == 1)
	return VehicleModGarage._best_affordable(shop, 1000) == ""


func test_tie_breaks_on_cheaper_next_tier() -> bool:
	# Both at level 0 -> the cheaper next tier wins the tie.
	var shop := VehicleModShop.new({"dear": [200], "cheap": [50]})
	return VehicleModGarage._best_affordable(shop, 1000) == "cheap"


func test_lowest_level_beats_cheaper_higher_level() -> bool:
	# "fast" has the cheaper next tier but is already a level up; "slow" still sits at
	# level 0. Least-upgraded-first must pick "slow" to spread the tuning — this is
	# exactly what distinguishes the new policy from the old cheapest-first (which would
	# have re-bought the cheaper "fast").
	var shop := VehicleModShop.new({"slow": [200, 200], "fast": [50, 50, 50]})
	shop.upgrade("fast", 1000)  # fast -> level 1 (next tier 50); slow stays level 0 (next 200)
	return VehicleModGarage._best_affordable(shop, 1000) == "slow"


func test_unaffordable_lowest_level_falls_through() -> bool:
	# The least-upgraded category is too dear -> fall through to an affordable one.
	var shop := VehicleModShop.new({"pricey": [9000], "ok": [100, 100]})
	shop.upgrade("ok", 1000)  # ok -> level 1; pricey stays level 0 but costs 9000
	return VehicleModGarage._best_affordable(shop, 500) == "ok"
