extends RefCounted
## Unit tests for ChopShop (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Includes a VehicleHealth composition test (a damaged car fences for less).


func test_default_classes_loaded() -> bool:
	var c := ChopShop.new()
	return c.class_count() == 7 and c.has_class("sports") and c.has_class("super")


func test_malformed_classes_dropped() -> bool:
	var c := (
		ChopShop
		. new(
			[
				{"id": "ok", "base": 1000},
				{"id": "", "base": 1000},
				{"id": "no_base"},
				{"id": "free", "base": 0},
				{"id": "ok", "base": 2000},  # duplicate id
			]
		)
	)
	return c.class_count() == 1 and c.has_class("ok")


func test_base_value_lookup() -> bool:
	var c := ChopShop.new()
	return c.base_value_of("sports") == 14000 and c.base_value_of("nope") == -1


func test_pristine_value_is_base() -> bool:
	var c := ChopShop.new()
	return c.value("sports", 1.0) == 14000


func test_wrecked_value_is_scrap_floor() -> bool:
	var c := ChopShop.new()
	# 14000 * 0.2 = 2800
	return c.value("sports", 0.0) == 2800


func test_mid_condition_value() -> bool:
	var c := ChopShop.new()
	# 14000 * (0.2 + 0.8*0.5) = 14000 * 0.6 = 8400
	return c.value("sports", 0.5) == 8400


func test_value_unknown_is_zero() -> bool:
	var c := ChopShop.new()
	return c.value("nope", 1.0) == 0


func test_request_applies_demand_bonus() -> bool:
	var c := ChopShop.new()
	c.set_requests(["sports"])
	# 14000 * 1.0 * 1.5 = 21000
	return c.is_requested("sports") and c.value("sports", 1.0) == 21000


func test_set_requests_ignores_unknown() -> bool:
	var c := ChopShop.new()
	c.set_requests(["sports", "spaceship"])
	return (
		c.is_requested("sports") and not c.is_requested("spaceship") and c.requested().size() == 1
	)


func test_deliver_pays_and_banks() -> bool:
	var c := ChopShop.new()
	var r := c.deliver("muscle", 1.0)
	return (
		r["accepted"]
		and r["payout"] == 8000
		and c.total_earned() == 8000
		and c.deliveries_count() == 1
	)


func test_deliver_unknown_rejected() -> bool:
	var c := ChopShop.new()
	var r := c.deliver("nope", 1.0)
	return not r["accepted"] and r["payout"] == 0 and c.total_earned() == 0


func test_hot_vehicle_discounted() -> bool:
	var c := ChopShop.new()
	var r := c.deliver("sports", 1.0, true)
	# 14000 * (1 - 0.25) = 10500
	return r["payout"] == 10500


func test_delivery_fulfils_request() -> bool:
	var c := ChopShop.new()
	c.set_requests(["sports"])
	var first := c.deliver("sports", 1.0)  # 21000, was requested
	var second := c.deliver("sports", 1.0)  # base 14000, request fulfilled
	return (
		first["was_requested"]
		and first["payout"] == 21000
		and not c.is_requested("sports")
		and second["payout"] == 14000
	)


func test_hot_requested_and_damaged_round_once() -> bool:
	# Combined path: demand bonus + condition + heat discount, rounded a single time.
	# 14000 * (0.2 + 0.8*0.5) * 1.5 * 0.75 = 14000 * 0.6 * 1.5 * 0.75 = 9450
	var c := ChopShop.new()
	c.set_requests(["sports"])
	var r := c.deliver("sports", 0.5, true)
	return r["was_requested"] and r["payout"] == 9450


func test_rotate_requests_deterministic() -> bool:
	var a := ChopShop.new()
	var b := ChopShop.new()
	a.rotate_requests(_rng(4), 2)
	b.rotate_requests(_rng(4), 2)
	return a.requested().size() == 2 and a.requested() == b.requested()


func test_rotate_requests_skips_excluded() -> bool:
	# Roll the whole pool but exclude the top tier: super never lands on the board, so its
	# demand bonus can't fire (the 7-class catalogue yields 6 requestable classes).
	var c := ChopShop.new()
	c.rotate_requests(_rng(4), 7, ["super"])
	return not c.is_requested("super") and c.requested().size() == 6


func test_damaged_car_fences_for_less() -> bool:
	# Composition: VehicleHealth.health_fraction feeds the condition.
	var vh := VehicleHealth.new(1000.0)
	var pristine := ChopShop.new().value("muscle", vh.health_fraction())
	vh.apply_damage(500.0)  # half health
	var damaged := ChopShop.new().value("muscle", vh.health_fraction())
	return pristine == 8000 and damaged < pristine


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
