extends RefCounted
## Unit tests for VehicleModShop (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_stock_starts_at_level_zero() -> bool:
	var shop := VehicleModShop.new()
	return (
		shop.level_of("engine") == 0
		and shop.level_of("brakes") == 0
		and shop.level_of("armor") == 0
		and shop.level_of("tires") == 0
	)


func test_fresh_shop_is_stock() -> bool:
	var shop := VehicleModShop.new()
	return shop.is_stock()


func test_stock_multipliers_are_one() -> bool:
	var shop := VehicleModShop.new()
	return (
		is_equal_approx(shop.top_speed_multiplier(), 1.0)
		and is_equal_approx(shop.acceleration_multiplier(), 1.0)
		and is_equal_approx(shop.brake_multiplier(), 1.0)
		and is_equal_approx(shop.armor_multiplier(), 1.0)
		and is_equal_approx(shop.grip_multiplier(), 1.0)
	)


func test_max_level_is_three() -> bool:
	var shop := VehicleModShop.new()
	return shop.max_level("engine") == 3 and shop.max_level("tires") == 3


func test_price_for_tiers() -> bool:
	var shop := VehicleModShop.new()
	return (
		shop.price_for("engine", 1) == 2000
		and shop.price_for("engine", 2) == 5000
		and shop.price_for("engine", 3) == 12000
	)


func test_price_for_past_max_is_minus_one() -> bool:
	var shop := VehicleModShop.new()
	return shop.price_for("engine", 4) == -1


func test_price_for_unknown_category_is_minus_one() -> bool:
	var shop := VehicleModShop.new()
	return shop.price_for("nitro", 1) == -1


func test_upgrade_raises_level_and_deducts() -> bool:
	var shop := VehicleModShop.new()
	var result := shop.upgrade("engine", 10000)
	return (
		result["success"]
		and result["cost"] == 2000
		and result["new_balance"] == 8000
		and result["new_level"] == 1
		and shop.level_of("engine") == 1
		and not shop.is_stock()
	)


func test_upgrade_steps_through_tiers() -> bool:
	var shop := VehicleModShop.new()
	shop.upgrade("brakes", 50000)
	var second := shop.upgrade("brakes", 50000)
	return second["cost"] == 3500 and second["new_level"] == 2 and shop.level_of("brakes") == 2


func test_upgrade_fails_at_max() -> bool:
	var shop := VehicleModShop.new()
	shop.upgrade("tires", 100000)
	shop.upgrade("tires", 100000)
	shop.upgrade("tires", 100000)
	var maxed := shop.upgrade("tires", 100000)
	return (
		not maxed["success"]
		and maxed["new_level"] == -1
		and shop.level_of("tires") == 3
		and not shop.can_upgrade("tires")
	)


func test_upgrade_fails_insufficient_funds() -> bool:
	var shop := VehicleModShop.new()
	var result := shop.upgrade("armor", 100)
	return not result["success"] and result["new_balance"] == 100 and shop.level_of("armor") == 0


func test_upgrade_unknown_category_safe() -> bool:
	var shop := VehicleModShop.new()
	var result := shop.upgrade("turbo", 99999)
	return not result["success"] and result["new_balance"] == 99999 and shop.is_stock()


func test_can_upgrade_reflects_state() -> bool:
	var shop := VehicleModShop.new()
	var fresh := shop.can_upgrade("engine")
	shop.upgrade("engine", 100000)
	shop.upgrade("engine", 100000)
	shop.upgrade("engine", 100000)
	return fresh and not shop.can_upgrade("engine") and not shop.can_upgrade("ghost")


func test_engine_raises_speed_and_accel() -> bool:
	var shop := VehicleModShop.new()
	shop.upgrade("engine", 100000)
	shop.upgrade("engine", 100000)
	return (
		is_equal_approx(shop.top_speed_multiplier(), 1.16)
		and is_equal_approx(shop.acceleration_multiplier(), 1.12)
	)


func test_tires_raise_grip_only() -> bool:
	var shop := VehicleModShop.new()
	shop.upgrade("tires", 100000)
	return (
		is_equal_approx(shop.grip_multiplier(), 1.07)
		and is_equal_approx(shop.top_speed_multiplier(), 1.0)
		and is_equal_approx(shop.brake_multiplier(), 1.0)
		and is_equal_approx(shop.armor_multiplier(), 1.0)
	)


func test_brakes_raise_brake_only() -> bool:
	var shop := VehicleModShop.new()
	shop.upgrade("brakes", 100000)
	shop.upgrade("brakes", 100000)
	return (
		is_equal_approx(shop.brake_multiplier(), 1.2)
		and is_equal_approx(shop.grip_multiplier(), 1.0)
	)


func test_armor_raises_armor_only() -> bool:
	var shop := VehicleModShop.new()
	shop.upgrade("armor", 100000)
	shop.upgrade("armor", 100000)
	shop.upgrade("armor", 100000)
	return (
		is_equal_approx(shop.armor_multiplier(), 1.75)
		and is_equal_approx(shop.top_speed_multiplier(), 1.0)
	)


func test_multipliers_rise_monotonically() -> bool:
	var shop := VehicleModShop.new()
	var before := shop.top_speed_multiplier()
	shop.upgrade("engine", 100000)
	var mid := shop.top_speed_multiplier()
	shop.upgrade("engine", 100000)
	var after := shop.top_speed_multiplier()
	return before < mid and mid < after


func test_total_spent_sums_tiers() -> bool:
	var shop := VehicleModShop.new()
	shop.upgrade("engine", 100000)
	shop.upgrade("engine", 100000)
	shop.upgrade("tires", 100000)
	return shop.total_spent() == 2000 + 5000 + 1000


func test_serialize_restore_round_trip() -> bool:
	var shop := VehicleModShop.new()
	shop.upgrade("engine", 100000)
	shop.upgrade("armor", 100000)
	var snapshot := shop.serialize()
	var other := VehicleModShop.new()
	other.restore(snapshot)
	return (
		other.level_of("engine") == 1
		and other.level_of("armor") == 1
		and other.level_of("brakes") == 0
		and is_equal_approx(other.top_speed_multiplier(), 1.08)
	)


func test_restore_clamps_out_of_range() -> bool:
	var shop := VehicleModShop.new()
	shop.restore({"engine": 99, "tires": -3})
	return shop.level_of("engine") == 3 and shop.level_of("tires") == 0


func test_reset_returns_to_stock() -> bool:
	var shop := VehicleModShop.new()
	shop.upgrade("engine", 100000)
	shop.upgrade("brakes", 100000)
	shop.reset()
	return (
		shop.is_stock()
		and shop.level_of("engine") == 0
		and is_equal_approx(shop.brake_multiplier(), 1.0)
		and shop.total_spent() == 0
	)
