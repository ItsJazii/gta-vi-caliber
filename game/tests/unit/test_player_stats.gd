extends RefCounted
## Unit tests for PlayerStats static helpers (see tests/run_tests.gd contract).
## Only the pure maths are tested here, plus the tree-free save round trip;
## the other node mutators need a SceneTree.


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


func test_save_round_trip_restores_wallet_and_armor() -> bool:
	var stats := PlayerStats.new()
	stats.money = 4250
	stats.armor = 62.5
	var snapshot := stats.serialize()
	var fresh := PlayerStats.new()
	fresh.money = 0
	fresh.armor = 0.0
	fresh.restore(snapshot)
	var ok := fresh.money == 4250 and absf(fresh.armor - 62.5) < 0.0001
	stats.free()
	fresh.free()
	return ok


func test_restore_clamps_and_survives_garbage() -> bool:
	var stats := PlayerStats.new()
	stats.money = 700
	stats.armor = 10.0
	stats.restore({"money": -50, "armor": 9999.0})
	var clamped := stats.money == 0 and absf(stats.armor - stats.max_armor) < 0.0001
	stats.restore({"money": "junk", "armor": null})
	var kept := stats.money == 0 and absf(stats.armor - stats.max_armor) < 0.0001
	stats.free()
	return clamped and kept
