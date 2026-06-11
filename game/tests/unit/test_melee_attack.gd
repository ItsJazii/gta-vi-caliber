extends RefCounted
## Unit tests for MeleeAttack (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_starts_ready() -> bool:
	var m := MeleeAttack.new()
	return m.phase == MeleeAttack.Phase.READY and not m.is_active()


func test_start_enters_windup() -> bool:
	var m := MeleeAttack.new()
	return m.start() and m.phase == MeleeAttack.Phase.WINDUP and m.combo == 1


func test_phases_progress_to_strike_then_recover() -> bool:
	var m := MeleeAttack.new(0.1, 0.08, 0.34)
	m.start()
	m.tick(0.1)
	var at_strike := m.phase == MeleeAttack.Phase.STRIKE
	m.tick(0.08)
	return at_strike and m.phase == MeleeAttack.Phase.RECOVER


func test_returns_to_ready_after_recover() -> bool:
	var m := MeleeAttack.new(0.1, 0.08, 0.3)
	m.start()
	m.tick(0.5)  # past every phase
	return m.phase == MeleeAttack.Phase.READY and m.combo == 0


func test_cannot_start_mid_swing() -> bool:
	var m := MeleeAttack.new()
	m.start()
	m.tick(0.05)  # still in windup
	return not m.can_start() and not m.start()


func test_hit_lands_once_during_strike() -> bool:
	var m := MeleeAttack.new(0.1, 0.08, 0.3)
	m.start()
	m.tick(0.1)  # enter strike
	var first := m.consume_hit()
	var second := m.consume_hit()
	return first and not second


func test_no_hit_outside_strike() -> bool:
	var m := MeleeAttack.new(0.1, 0.08, 0.3)
	m.start()  # windup
	return not m.consume_hit()


func test_combo_chains_during_recover() -> bool:
	var m := MeleeAttack.new(0.1, 0.08, 0.3)
	m.start()
	m.tick(0.19)  # into recovery
	var chained := m.start()
	return chained and m.combo == 2


func test_combo_resets_after_full_recover() -> bool:
	var m := MeleeAttack.new(0.1, 0.08, 0.3)
	m.start()
	m.tick(0.5)  # back to ready, combo cleared
	m.start()
	return m.combo == 1


func test_combo_damage_scales() -> bool:
	var m := MeleeAttack.new(0.1, 0.08, 0.3)
	m.start()  # combo 1 → x1.0
	var base := m.combo_damage(20.0)
	m.tick(0.19)
	m.start()  # combo 2 → x1.2
	var stronger := m.combo_damage(20.0)
	return is_equal_approx(base, 20.0) and is_equal_approx(stronger, 24.0)
