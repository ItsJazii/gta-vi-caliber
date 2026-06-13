class_name TestCorrectnessFixes
extends GdUnitTestSuite
## Regression tests for the loop bug-hunt correctness sweep. Each asserts the
## post-fix behaviour and would FAIL against the pre-fix code:
##   - WeatherEffects._level NaN propagation (poisoned the physics chain)
##   - PlayerHealthModel.heal resurrecting a dead model
##   - ShopModel.items_in_category aliasing the master catalogue
##   - ShopModel.sell_value truncating instead of rounding
##   - NavGrid.block_world_rect blocking cells whose centre is outside the rect
##   - PropertyOwnership.accrue letting a NaN span poison the income bank
## Written as a gdUnit4 suite so the CI runner (run_tests.gd -> res://tests/unit)
## actually executes them.


func test_weather_nan_inputs_stay_dry() -> void:
	# clampf(NaN) is NaN and used to propagate through every multiplier.
	assert_float(WeatherEffects.grip_multiplier(NAN)).is_equal(1.0)
	assert_float(WeatherEffects.brake_distance_multiplier(NAN)).is_equal(1.0)
	assert_float(WeatherEffects.traffic_speed_multiplier(NAN)).is_equal(1.0)


func test_heal_does_not_resurrect_dead_model() -> void:
	var h := PlayerHealthModel.new(100.0)
	h.apply(500.0)  # lethal, past any armor
	h.heal(30.0)
	assert_bool(h.is_dead()).is_true()
	assert_float(h.health).is_equal(0.0)


func test_shop_items_in_category_returns_copies() -> void:
	var shop := ShopModel.new()
	var listing := shop.items_in_category("weapon")
	assert_bool(listing.is_empty()).is_false()
	var id: String = listing[0]["id"]
	var original := shop.price_of(id)
	listing[0]["price"] = 1  # mutating a returned copy must not corrupt the source
	assert_int(shop.price_of(id)).is_equal(original)


func test_shop_sell_value_rounds_not_truncates() -> void:
	# 150 * 0.51 = 76.5 -> round 77 (used to truncate to 76).
	assert_int(ShopModel.new().sell_value("ammo_box", 0.51)).is_equal(77)


func test_navgrid_block_world_rect_uses_cell_centres() -> void:
	# Max-z corner 0.4 sits below every row centre (0.5, 1.5, ...), so no cell
	# centre is inside the rect -> nothing should block. The old corner-span fill
	# wrongly stamped row 0 (and a phantom strip for the off-grid x start).
	var g := NavGrid.new(10, 10, 1.0)
	g.block_world_rect(Vector2(-5.0, -5.0), Vector2(2.4, 0.4))
	for c in range(10):
		assert_bool(g.is_blocked(c, 0)).is_false()


func test_property_accrue_ignores_nan_span() -> void:
	# A NaN span slipped past the `<= 0.0` guard and poisoned the bank to NaN;
	# collect() then returned int(NaN)=0 and wiped all real accrued income.
	var p := PropertyOwnership.new(
		[{"id": "biz", "name": "Biz", "price": 1000, "income_per_day": 100, "is_safehouse": false}]
	)
	p.buy("biz", 5000)
	p.accrue(5.0)
	p.accrue(NAN)
	p.accrue(5.0)
	assert_int(p.collect()).is_equal(1000)  # 100/day * (5 + 5) days; NaN ignored
