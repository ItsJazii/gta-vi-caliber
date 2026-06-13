extends RefCounted
## Unit tests for VehicleCondition (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Covers the full fuel/wear ledger: catalogue validation, fresh-vehicle state,
## fuel burn by economy, engine/tire wear accrual (intensity-scaled), empty-tank
## stall, drivability gates (top-speed/grip), crash wear, the condition blend
## feeding ChopShop, refuel capping, mechanic service, and save round-trip.
## sedan: tank 60L, economy 0.0009 L/m.


func test_default_vehicles_loaded() -> bool:
	var vc := VehicleCondition.new()
	return vc.vehicle_count() >= 3 and vc.has_vehicle("sedan")


func test_malformed_vehicles_dropped() -> bool:
	var vc := (
		VehicleCondition
		. new(
			[
				{"id": "ok", "tank": 50.0},
				{"id": "", "tank": 50.0},
				{"tank": 40.0},  # no id
				{"id": "zero", "tank": 0.0},  # non-positive tank
				{"id": "ok", "tank": 99.0},  # duplicate id
			]
		)
	)
	return vc.vehicle_count() == 1 and vc.has_vehicle("ok")


func test_new_vehicle_starts_full_and_unworn() -> bool:
	var vc := VehicleCondition.new()
	return (
		is_equal_approx(vc.fuel_fraction("sedan"), 1.0)
		and vc.engine_wear_of("sedan") == 0.0
		and vc.tire_wear_of("sedan") == 0.0
		and is_equal_approx(vc.condition("sedan"), 1.0)
	)


func test_unknown_vehicle_is_neutral() -> bool:
	var vc := VehicleCondition.new()
	return (
		vc.condition("nope") == 1.0
		and vc.fuel_of("nope") == 0.0
		and vc.top_speed_factor("nope") == 1.0
		and vc.grip_factor("nope") == 1.0
		and vc.refuel("nope") == 0.0
	)


func test_drive_burns_fuel_by_economy() -> bool:
	var vc := VehicleCondition.new()
	var before := vc.fuel_of("sedan")
	var r := vc.drive("sedan", 1000.0)  # default intensity 1.0; 0.0009 * 1000 = 0.9 L
	var burned := before - vc.fuel_of("sedan")
	var fuel_used: float = r["fuel_used"]
	return is_equal_approx(burned, 0.9) and is_equal_approx(fuel_used, 0.9)


func test_drive_accrues_engine_and_tire_wear() -> bool:
	var vc := VehicleCondition.new()
	vc.drive("sedan", 1000.0, 1.0)
	vc.drive("sports", 1000.0, 2.0)  # harder driving over the same distance
	return (
		vc.engine_wear_of("sedan") > 0.0
		and vc.tire_wear_of("sedan") > 0.0
		and vc.engine_wear_of("sports") > vc.engine_wear_of("sedan")
		and vc.tire_wear_of("sports") > vc.tire_wear_of("sedan")
	)


func test_drive_stops_at_empty_and_stalls() -> bool:
	var vc := VehicleCondition.new()
	var r := vc.drive("sedan", 9999999.0)  # far beyond tank range
	var stalled: bool = r["stalled"]
	return (
		is_equal_approx(vc.fuel_of("sedan"), 0.0)
		and vc.is_out_of_fuel("sedan")
		and stalled
		and vc.fuel_of("sedan") >= 0.0
	)


func test_top_speed_factor_drops_with_engine_wear() -> bool:
	var vc := VehicleCondition.new()
	vc.apply_crash("sedan", 1.0)
	vc.apply_crash("sedan", 1.0)  # engine_wear ~0.8
	var worn_factor := vc.top_speed_factor("sedan")
	vc.drive("sedan", 9999999.0)  # drain the tank
	var empty_factor := vc.top_speed_factor("sedan")
	return (
		worn_factor < 1.0 and worn_factor >= VehicleCondition.ENGINE_FLOOR and empty_factor == 0.0
	)


func test_grip_factor_drops_with_tire_wear() -> bool:
	var vc := VehicleCondition.new()
	var fresh := vc.grip_factor("sedan")
	vc.drive("sedan", 30000.0, 1.0)  # tire wear ~0.9
	var worn := vc.grip_factor("sedan")
	return is_equal_approx(fresh, 1.0) and worn < 1.0 and worn >= VehicleCondition.TIRE_FLOOR


func test_apply_crash_increases_engine_wear_clamped() -> bool:
	var vc := VehicleCondition.new()
	var before := vc.engine_wear_of("sedan")
	vc.apply_crash("sedan", 0.5)
	var after := vc.engine_wear_of("sedan")
	for _i in 10:
		vc.apply_crash("sedan", 1.0)
	var maxed := vc.engine_wear_of("sedan")
	var cond_floor := vc.condition("sedan")
	vc.apply_crash("sedan", 1.0)  # already maxed: no further change
	var cond_after := vc.condition("sedan")
	return (
		after > before and is_equal_approx(maxed, 1.0) and is_equal_approx(cond_floor, cond_after)
	)


func test_condition_blends_wear_and_feeds_chopshop() -> bool:
	var vc := VehicleCondition.new()
	var pristine := vc.condition("sedan")
	vc.drive("sedan", 50000.0, 2.0)
	vc.apply_crash("sedan", 0.5)
	var worn := vc.condition("sedan")
	var shop := ChopShop.new()
	# A worn car fences for less — the named ChopShop.value() composition.
	return worn < pristine and shop.value("sedan", worn) < shop.value("sedan", pristine)


func test_refuel_caps_at_tank_and_returns_added() -> bool:
	var vc := VehicleCondition.new()
	vc.drive("sedan", 20000.0)  # burn 18 L, leaving 42
	var added := vc.refuel("sedan", -1.0)  # fill to full -> add exactly 18
	var second := vc.refuel("sedan", -1.0)  # already full -> 0
	return (
		is_equal_approx(added, 18.0)
		and is_equal_approx(vc.fuel_fraction("sedan"), 1.0)
		and second == 0.0
	)


func test_service_resets_selected_channels() -> bool:
	var vc := VehicleCondition.new()
	vc.drive("sedan", 30000.0, 2.0)  # both channels wear
	vc.service("sedan", true, false)  # engine only
	var engine_zeroed := vc.engine_wear_of("sedan") == 0.0
	var tire_kept := vc.tire_wear_of("sedan") > 0.0
	vc.service("sedan")  # defaults: both
	return (
		engine_zeroed
		and tire_kept
		and vc.tire_wear_of("sedan") == 0.0
		and vc.engine_wear_of("sedan") == 0.0
	)


func test_save_roundtrip() -> bool:
	var vc := VehicleCondition.new()
	vc.drive("sedan", 15000.0, 1.5)
	vc.apply_crash("sedan", 0.3)
	var snap := vc.to_dict()
	var fresh := VehicleCondition.new()
	fresh.load_dict(snap)
	var match_ok: bool = (
		is_equal_approx(fresh.fuel_of("sedan"), vc.fuel_of("sedan"))
		and is_equal_approx(fresh.engine_wear_of("sedan"), vc.engine_wear_of("sedan"))
		and is_equal_approx(fresh.tire_wear_of("sedan"), vc.tire_wear_of("sedan"))
	)
	# Unknown ids and non-numeric values are ignored (sedan stays pristine).
	var bad := VehicleCondition.new()
	bad.load_dict({"ghost": {"fuel": 10.0}, "sedan": {"fuel": "lots"}})
	var ignored: bool = (
		bad.engine_wear_of("sedan") == 0.0 and is_equal_approx(bad.fuel_fraction("sedan"), 1.0)
	)
	return match_ok and ignored


func test_drive_intensity_zero_still_costs() -> bool:
	# Movement always costs: intensity 0 is floored to MIN_INTENSITY (no free driving).
	var vc := VehicleCondition.new()
	var before := vc.fuel_of("sedan")
	vc.drive("sedan", 5000.0, 0.0)
	return (
		vc.fuel_of("sedan") < before
		and vc.engine_wear_of("sedan") > 0.0
		and vc.tire_wear_of("sedan") > 0.0
	)


func test_drive_on_stalled_vehicle_is_noop() -> bool:
	# Tiny tank so it empties with negligible wear, making the no-op assertion meaningful.
	var vc := VehicleCondition.new([{"id": "test", "tank": 5.0, "economy": 1.0}])
	vc.drive("test", 5.0, 1.0)  # burns all 5 L; now stalled
	var ew := vc.engine_wear_of("test")
	var tw := vc.tire_wear_of("test")
	var r := vc.drive("test", 1000.0, 1.0)  # stalled car does not move -> no wear
	var fuel_used: float = r["fuel_used"]
	var stalled: bool = r["stalled"]
	return (
		vc.is_out_of_fuel("test")
		and is_equal_approx(vc.engine_wear_of("test"), ew)
		and is_equal_approx(vc.tire_wear_of("test"), tw)
		and fuel_used == 0.0
		and stalled
	)


func test_drive_fuel_used_reports_actual_drain() -> bool:
	var vc := VehicleCondition.new()
	vc.drive("sedan", 60000.0)  # burn 54 L, leaving 6
	var r := vc.drive("sedan", 100000.0)  # want_fuel 90 but only 6 remain
	var fuel_used: float = r["fuel_used"]
	return is_equal_approx(fuel_used, 6.0) and is_equal_approx(vc.fuel_of("sedan"), 0.0)


func test_drive_unknown_vehicle_neutral_dict() -> bool:
	var vc := VehicleCondition.new()
	var count := vc.vehicle_count()
	var r := vc.drive("nope", 1000.0)
	var fuel_used: float = r["fuel_used"]
	var stalled: bool = r["stalled"]
	return (
		fuel_used == 0.0
		and stalled == false
		and vc.vehicle_count() == count
		and not vc.has_vehicle("nope")
	)


func test_drive_nonpositive_distance_noop() -> bool:
	var vc := VehicleCondition.new()
	var before := vc.fuel_of("sedan")
	var r := vc.drive("sedan", 0.0)
	vc.drive("sedan", -50.0)
	var fuel_used: float = r["fuel_used"]
	return (
		is_equal_approx(vc.fuel_of("sedan"), before)
		and fuel_used == 0.0
		and vc.engine_wear_of("sedan") == 0.0
		and vc.tire_wear_of("sedan") == 0.0
	)


func test_refuel_partial_amount() -> bool:
	var vc := VehicleCondition.new()
	vc.drive("sedan", 20000.0)  # burn 18 L, leaving 42
	var added := vc.refuel("sedan", 10.0)
	return is_equal_approx(added, 10.0) and is_equal_approx(vc.fuel_of("sedan"), 52.0)


func test_refuel_clamps_too_large() -> bool:
	var vc := VehicleCondition.new()
	vc.drive("sedan", 20000.0)  # 42 L left, 18 L of space
	var added := vc.refuel("sedan", 100.0)
	return is_equal_approx(added, 18.0) and is_equal_approx(vc.fuel_fraction("sedan"), 1.0)


func test_load_dict_clamps_out_of_range() -> bool:
	var vc := VehicleCondition.new()
	vc.load_dict({"sedan": {"fuel": 999.0, "engine_wear": 5.0, "tire_wear": -2.0}})
	return (
		is_equal_approx(vc.fuel_of("sedan"), 60.0)
		and is_equal_approx(vc.engine_wear_of("sedan"), 1.0)
		and is_equal_approx(vc.tire_wear_of("sedan"), 0.0)
	)


func test_apply_crash_unknown_and_nonpositive_noop() -> bool:
	var vc := VehicleCondition.new()
	vc.apply_crash("nope", 1.0)  # must not crash or register a vehicle
	var before := vc.engine_wear_of("sedan")
	vc.apply_crash("sedan", 0.0)
	vc.apply_crash("sedan", -0.5)
	return not vc.has_vehicle("nope") and vc.engine_wear_of("sedan") == before
