extends RefCounted
## Unit tests for MeleeCombat (see tests/run_tests.gd: test_* methods return true
## to pass). Deterministic, no asserts, is_equal_approx for floats.

# --- static: strike_damage ---


func test_strike_damage_first_hit_is_base() -> bool:
	return is_equal_approx(MeleeCombat.strike_damage(MeleeCombat.Strike.CROSS, 1), 10.0)


func test_strike_damage_rises_with_combo() -> bool:
	# CROSS base 10, +12% on the 2nd chained hit → 11.2.
	return is_equal_approx(MeleeCombat.strike_damage(MeleeCombat.Strike.CROSS, 2), 11.2)


func test_strike_damage_combo_bonus_caps() -> bool:
	# Bonus caps at 5 steps: combo 6 and combo 99 both yield base * 1.6.
	var capped: float = MeleeCombat.strike_damage(MeleeCombat.Strike.JAB, 6)
	var beyond: float = MeleeCombat.strike_damage(MeleeCombat.Strike.JAB, 99)
	return is_equal_approx(capped, 6.0 * 1.6) and is_equal_approx(beyond, capped)


# --- static: strike_for_combo (chain escalation) ---


func test_strike_for_combo_chain() -> bool:
	# 1->jab, 2->cross, 3->kick, then holds on heavy; a fresh/degenerate count
	# (<=0) opens with the lightest strike rather than wrapping.
	return (
		MeleeCombat.strike_for_combo(1) == MeleeCombat.Strike.JAB
		and MeleeCombat.strike_for_combo(2) == MeleeCombat.Strike.CROSS
		and MeleeCombat.strike_for_combo(3) == MeleeCombat.Strike.KICK
		and MeleeCombat.strike_for_combo(4) == MeleeCombat.Strike.HEAVY
		and MeleeCombat.strike_for_combo(5) == MeleeCombat.Strike.HEAVY
		and MeleeCombat.strike_for_combo(20) == MeleeCombat.Strike.HEAVY
		and MeleeCombat.strike_for_combo(0) == MeleeCombat.Strike.JAB
		and MeleeCombat.strike_for_combo(-3) == MeleeCombat.Strike.JAB
	)


# --- static: block_reduction ---


func test_block_soaks_part_of_hit() -> bool:
	# A 0.5 guard on a 10-damage cross leaves 5.
	return is_equal_approx(MeleeCombat.block_reduction(10.0, 0.5, MeleeCombat.Strike.CROSS), 5.0)


func test_block_heavy_breaks_through_floor() -> bool:
	# Perfect guard vs a 20-damage heavy still lets 25% through → 5.
	var through: float = MeleeCombat.block_reduction(20.0, 1.0, MeleeCombat.Strike.HEAVY)
	return is_equal_approx(through, 5.0)


func test_block_light_fully_soaked_by_perfect_guard() -> bool:
	# A jab has no break-through floor, so a perfect block eats it entirely.
	return is_equal_approx(MeleeCombat.block_reduction(8.0, 1.0, MeleeCombat.Strike.JAB), 0.0)


func test_block_never_negative() -> bool:
	# Over-strong guard / negative incoming can't drive damage below zero.
	var a: float = MeleeCombat.block_reduction(-5.0, 1.0, MeleeCombat.Strike.CROSS)
	var b: float = MeleeCombat.block_reduction(10.0, 5.0, MeleeCombat.Strike.CROSS)
	return is_equal_approx(a, 0.0) and is_equal_approx(b, 0.0)


# --- static: counter_damage ---


func test_counter_beats_base_on_good_timing() -> bool:
	return is_equal_approx(MeleeCombat.counter_damage(10.0, true), 17.5)


func test_counter_equals_base_off_timing() -> bool:
	return is_equal_approx(MeleeCombat.counter_damage(10.0, false), 10.0)


# --- static: is_in_range ---


func test_in_range_within_reach() -> bool:
	return MeleeCombat.is_in_range(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 1.5)


func test_out_of_range_beyond_reach() -> bool:
	return not MeleeCombat.is_in_range(Vector3.ZERO, Vector3(3.0, 0.0, 0.0), 1.5)


func test_negative_reach_never_in_range() -> bool:
	return not MeleeCombat.is_in_range(Vector3.ZERO, Vector3.ZERO, -1.0)


# --- static: stagger_threshold ---


func test_stagger_when_damage_meets_poise() -> bool:
	return MeleeCombat.stagger_threshold(20.0, 18.0)


func test_no_stagger_below_poise() -> bool:
	return not MeleeCombat.stagger_threshold(10.0, 18.0)


# --- static: combo_continues ---


func test_combo_continues_within_window() -> bool:
	return MeleeCombat.combo_continues(0.3, 0.6)


func test_combo_breaks_after_window() -> bool:
	return not MeleeCombat.combo_continues(0.9, 0.6)


# --- stateful ---


func test_strike_spends_stamina_and_advances_combo() -> bool:
	var m := MeleeCombat.new(100.0)
	var dmg: float = m.strike(MeleeCombat.Strike.CROSS)
	# First cross: base 10, costs 9 stamina, combo now 1.
	return (
		is_equal_approx(dmg, 10.0) and is_equal_approx(m.stamina(), 91.0) and m.combo_count() == 1
	)


func test_combo_bonus_banked_across_strikes() -> bool:
	var m := MeleeCombat.new(100.0)
	m.strike(MeleeCombat.Strike.JAB)
	var second: float = m.strike(MeleeCombat.Strike.JAB)
	# Second jab: base 6 * 1.12 = 6.72, combo now 2.
	return is_equal_approx(second, 6.72) and m.combo_count() == 2


func test_cannot_strike_when_empty() -> bool:
	var m := MeleeCombat.new(10.0)
	# 10 stamina can't afford an 18-cost heavy: no damage, nothing spent/advanced.
	var dmg: float = m.strike(MeleeCombat.Strike.HEAVY)
	return (
		is_equal_approx(dmg, 0.0)
		and is_equal_approx(m.stamina(), 10.0)
		and m.combo_count() == 0
		and not m.can_strike(MeleeCombat.Strike.HEAVY)
	)


func test_reset_combo_zeroes() -> bool:
	var m := MeleeCombat.new(100.0)
	m.strike(MeleeCombat.Strike.JAB)
	m.strike(MeleeCombat.Strike.JAB)
	m.reset_combo()
	return m.combo_count() == 0


func test_regen_recovers_and_caps() -> bool:
	var m := MeleeCombat.new(100.0)
	m.strike(MeleeCombat.Strike.HEAVY)  # spends 18 → 82
	m.regen_stamina(1.0)  # +14 → 96
	var mid: float = m.stamina()
	m.regen_stamina(100.0)  # would overshoot, caps at 100
	return is_equal_approx(mid, 96.0) and is_equal_approx(m.stamina(), 100.0)


func test_stamina_fraction_tracks_max() -> bool:
	var m := MeleeCombat.new(50.0)
	m.strike(MeleeCombat.Strike.HEAVY)  # 50 - 18 = 32
	return is_equal_approx(m.stamina_fraction(), 32.0 / 50.0)


func test_blocking_flag() -> bool:
	var m := MeleeCombat.new(100.0)
	var down: bool = m.is_blocking()
	m.block(true)
	var up: bool = m.is_blocking()
	m.block(false)
	return not down and up and not m.is_blocking()


# --- static: hitstop_for_strike ---
# Assertions are grouped into one test to stay under gdlint's max-public-methods
# cap (see test_weapon_ballistics.gd for the same convention). _hs is a private
# helper, so it doesn't count toward the cap.


func _hs(strike: int, killed: bool) -> Dictionary:
	return MeleeCombat.hitstop_for_strike(strike, killed)


func test_hitstop_for_strike() -> bool:
	var jab := _hs(MeleeCombat.Strike.JAB, false)
	var cross := _hs(MeleeCombat.Strike.CROSS, false)
	var kick := _hs(MeleeCombat.Strike.KICK, false)
	var heavy := _hs(MeleeCombat.Strike.HEAVY, false)
	var kill := _hs(MeleeCombat.Strike.HEAVY, true)
	var kill_light := _hs(MeleeCombat.Strike.JAB, true)
	var bogus := _hs(999, false)

	# Dwell rises and the time_scale floor drops jab -> cross -> kick -> heavy.
	var dwell_rises := (
		float(jab["seconds"]) < float(cross["seconds"])
		and float(cross["seconds"]) < float(kick["seconds"])
		and float(kick["seconds"]) < float(heavy["seconds"])
	)
	var scale_drops := (
		float(jab["scale"]) > float(cross["scale"])
		and float(cross["scale"]) > float(kick["scale"])
		and float(kick["scale"]) > float(heavy["scale"])
	)

	# Jab floor and heavy ceiling are exactly their table entries.
	var jab_floor := (
		is_equal_approx(
			float(jab["seconds"]), float(MeleeCombat.HITSTOP_SECONDS[MeleeCombat.Strike.JAB])
		)
		and is_equal_approx(
			float(jab["scale"]), float(MeleeCombat.HITSTOP_SCALE[MeleeCombat.Strike.JAB])
		)
	)
	var heavy_ceiling := (
		is_equal_approx(
			float(heavy["seconds"]), float(MeleeCombat.HITSTOP_SECONDS[MeleeCombat.Strike.HEAVY])
		)
		and is_equal_approx(
			float(heavy["scale"]), float(MeleeCombat.HITSTOP_SCALE[MeleeCombat.Strike.HEAVY])
		)
	)

	# A kill overrides any strike (light and heavy) to the kill freeze, which is
	# meatier than a non-kill heavy: longer dwell, lower (harder) scale.
	var kill_overrides := (
		is_equal_approx(float(kill_light["seconds"]), MeleeCombat.HITSTOP_KILL_SECONDS)
		and is_equal_approx(float(kill_light["scale"]), MeleeCombat.HITSTOP_KILL_SCALE)
		and is_equal_approx(float(kill["seconds"]), MeleeCombat.HITSTOP_KILL_SECONDS)
		and is_equal_approx(float(kill["scale"]), MeleeCombat.HITSTOP_KILL_SCALE)
	)
	var kill_meatiest := (
		float(kill["seconds"]) > float(heavy["seconds"])
		and float(kill["scale"]) < float(heavy["scale"])
	)

	# Every dose is sane: positive dwell, scale in [0,1].
	var sane := true
	for s in [
		MeleeCombat.Strike.JAB,
		MeleeCombat.Strike.CROSS,
		MeleeCombat.Strike.KICK,
		MeleeCombat.Strike.HEAVY,
	]:
		for k in [false, true]:
			var d := _hs(s, k)
			if float(d["seconds"]) <= 0.0 or float(d["scale"]) < 0.0 or float(d["scale"]) > 1.0:
				sane = false

	# An unknown strike id falls back to the lightest (jab) crunch.
	var fallback := (
		is_equal_approx(float(bogus["seconds"]), float(jab["seconds"]))
		and is_equal_approx(float(bogus["scale"]), float(jab["scale"]))
	)

	return (
		dwell_rises
		and scale_drops
		and jab_floor
		and heavy_ceiling
		and kill_overrides
		and kill_meatiest
		and sane
		and fallback
	)
