extends RefCounted
## Unit tests for PlayerStats static helpers (see tests/run_tests.gd contract).
## Only the pure maths are tested here; the node mutators need a SceneTree.


func test_absorb_full_soak() -> bool:
	# 100 armor eats 30 damage entirely; nothing reaches health.
	var r := PlayerStats.absorb(100.0, 30.0)
	return absf(r[0] - 70.0) < 0.0001 and absf(r[1]) < 0.0001


func test_absorb_overflow() -> bool:
	# 20 armor eats 20 of 50 damage; 30 spills to health.
	var r := PlayerStats.absorb(20.0, 50.0)
	return absf(r[0]) < 0.0001 and absf(r[1] - 30.0) < 0.0001


func test_absorb_no_armor() -> bool:
	var r := PlayerStats.absorb(0.0, 40.0)
	return absf(r[0]) < 0.0001 and absf(r[1] - 40.0) < 0.0001


func test_absorb_negative_damage_safe() -> bool:
	var r := PlayerStats.absorb(50.0, -10.0)
	return absf(r[0] - 50.0) < 0.0001 and absf(r[1]) < 0.0001


func test_fraction_normal() -> bool:
	return absf(PlayerStats.fraction(25.0, 100.0) - 0.25) < 0.0001


func test_fraction_clamps_high() -> bool:
	return absf(PlayerStats.fraction(150.0, 100.0) - 1.0) < 0.0001


func test_fraction_zero_max_safe() -> bool:
	return absf(PlayerStats.fraction(5.0, 0.0)) < 0.0001
