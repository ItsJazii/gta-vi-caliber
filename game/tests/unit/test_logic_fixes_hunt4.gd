extends RefCounted
## Regression tests for the hunt-4 correctness fixes (see tests/run_legacy_tests.gd
## for the runner contract: zero-arg test_* methods return true to pass).
##
## Covers five confirmed bugs:
##   1. CrowdPanic._others — value-compare dropped identical peds, stalling the wave
##   2. FirePropagation._others — same value-compare bug, stalling fire spread
##   3. VehicleHandling.drift_factor — straight reverse saturated to 1.0 (not drift)
##   4. HelicopterPursuit.spotlight_ground_radius — inner 1.55 clamp shrank the cone
##   5. VehicleModShop._clean_tiers — accepted zero-priced tiers (free upgrade)

# --- 1. CrowdPanic: panic spreads among value-identical peds ------------------


func test_crowd_panic_spreads_through_identical_peds() -> bool:
	# Three peds at the SAME spot with the SAME fear are distinct agents and must
	# catch panic from one another. The old value-compare _others() treated them
	# as equal and dropped them all, so a tight clump never propagated.
	var clump: Array = [
		{"pos": Vector3.ZERO, "fear": 0.3},
		{"pos": Vector3.ZERO, "fear": 0.3},
		{"pos": Vector3.ZERO, "fear": 0.3},
	]
	# Scare is far away (no direct fear) so only contagion can raise ped 0.
	var next_clump := CrowdPanic.update_crowd(
		clump, Vector3(1000.0, 0.0, 0.0), 1.0, 5.0, 1.0, 0.0, 0.0
	)
	var single := CrowdPanic.update_crowd(
		[{"pos": Vector3.ZERO, "fear": 0.3}], Vector3(1000.0, 0.0, 0.0), 1.0, 5.0, 1.0, 0.0, 0.0
	)
	# Clumped ped catches its two neighbours' fear; the lone ped catches nothing.
	return float(next_clump[0]) > 0.5 and float(next_clump[0]) > float(single[0])


# --- 2. FirePropagation: fire spreads among value-identical objects -----------


func test_fire_spreads_through_identical_objects() -> bool:
	# Same _others() bug: a row of identical burning crates must reinforce each
	# other. Compare a trio against a lone crate (dynamics-agnostic).
	# step_intensity takes max(current, caught), so the caught term must clear the
	# object's own heat to be observable: two identical neighbours at dist 0 over a
	# 0.6 tick contribute 0.6, above the 0.5 starting intensity.
	var crate := {"pos": Vector3.ZERO, "intensity": 0.5, "fuel": 1.0}
	var trio: Array = [crate.duplicate(), crate.duplicate(), crate.duplicate()]
	var solo: Array = [crate.duplicate()]
	var next_trio := FirePropagation.update_fires(trio, 5.0, 1.0, 0.1, 0.1, 0.1, 0.6)
	var next_solo := FirePropagation.update_fires(solo, 5.0, 1.0, 0.1, 0.1, 0.1, 0.6)
	# The crate flanked by two identical fires gains extra spread intensity.
	return float(next_trio[0]["intensity"]) > float(next_solo[0]["intensity"]) + 0.0001


# --- 3. VehicleHandling.drift_factor: reverse is not a drift ------------------


func test_drift_factor_zero_for_straight_reverse() -> bool:
	# Backing straight up: velocity opposite forward (180° slip). Folded, that is
	# 0° lateral slip — no drift, so the score/FX stay quiet.
	var d := VehicleHandling.drift_factor(Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, -1.0))
	return d < 0.05


func test_drift_factor_zero_for_straight_forward() -> bool:
	var d := VehicleHandling.drift_factor(Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, 1.0))
	return d < 0.05


func test_drift_factor_max_when_sideways() -> bool:
	# Pure lateral slip (90°) is full drift.
	var d := VehicleHandling.drift_factor(Vector3(3.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0))
	return is_equal_approx(d, 1.0)


func test_drift_factor_forward_slip_still_registers() -> bool:
	# A genuine ~30° forward slip must still read a partial drift (the fold must
	# not flatten ordinary forward drifting).
	var vel := Vector3(sin(deg_to_rad(30.0)), 0.0, cos(deg_to_rad(30.0))) * 3.0
	var d := VehicleHandling.drift_factor(vel, Vector3(0.0, 0.0, 1.0))
	return d > 0.5 and d < 1.0


# --- 4. HelicopterPursuit.spotlight_ground_radius: full cone honoured ---------


func test_spotlight_radius_honours_wide_cone() -> bool:
	# At the max 89° cone the footprint must use the true tan(89°), not the old
	# 1.55-rad (≈88.8°) under-clamp. 100m * tan(89°) ≈ 5729 > the old ≈4807.
	var r := HelicopterPursuit.spotlight_ground_radius(
		100.0, HelicopterPursuit.cone_half_radians(89.0)
	)
	return r > 5000.0


func test_spotlight_radius_default_cone_unchanged() -> bool:
	# A normal 22° cone sits well below the clamp ceiling, so the value is the
	# plain altitude * tan(half-angle) — unaffected by the fix.
	var half := HelicopterPursuit.cone_half_radians(22.0)
	var r := HelicopterPursuit.spotlight_ground_radius(50.0, half)
	return is_equal_approx(r, 50.0 * tan(half))


# --- 5. VehicleModShop._clean_tiers: zero-priced tiers rejected ---------------


func test_mod_shop_rejects_zero_priced_tier() -> bool:
	# A zero (free) tier anywhere poisons the whole row, so the category is
	# dropped — no free permanent upgrade.
	var shop := VehicleModShop.new({"nitro": [1500, 0, 8000]})
	return not shop.has_category("nitro")


func test_mod_shop_accepts_positive_tiers() -> bool:
	var shop := VehicleModShop.new({"nitro": [1500, 4000]})
	return shop.has_category("nitro") and shop.max_level("nitro") == 2


func test_mod_shop_default_catalogue_still_loads() -> bool:
	# Tightening the price guard must not reject the built-in catalogue.
	var shop := VehicleModShop.new()
	return shop.has_category("engine") and shop.max_level("engine") == 3
