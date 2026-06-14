class_name TestCorrectnessFixes2
extends GdUnitTestSuite
## Regression tests for the second adversarial bug-hunt sweep. Each asserts the
## post-fix behaviour and would fail against the pre-fix code:
##   - SaveData.migrate reviving an empty decode (would wipe stats/XP)
##   - PropertyOwnership.collect truncating + discarding fractional income
##   - VehicleHealth fire band invading the DAMAGED band
##   - SoundPropagation ALARMED tier unreachable for the loudest ambient sound
##   - Ballistics.damage_at_range not clamping min_fraction
##   - PlayerStats.add_armor accepting negatives


func test_migrate_empty_decode_stays_empty() -> void:
	assert_bool(SaveData.migrate({}, 0).is_empty()).is_true()
	assert_bool(SaveData.migrate({}, 1).is_empty()).is_true()


func test_migrate_real_v1_save_still_fills_sections() -> void:
	var out := SaveData.migrate({"foo": 1}, 1)
	assert_bool(out.has("stats") and out.has("progression") and out.has("properties")).is_true()


func test_property_collect_carries_fractional_remainder() -> void:
	var p := PropertyOwnership.new(
		[{"id": "biz", "name": "Biz", "price": 1000, "income_per_day": 100, "is_safehouse": false}]
	)
	p.buy("biz", 5000)
	var total := 0
	for i in 100:
		p.accrue(0.005)  # 0.5 income per accrual
		total += p.collect()
	assert_int(total).is_equal(50)  # 100 * 0.5; truncation used to lose all of it


func test_damaged_car_does_not_catch_fire() -> void:
	var vh := VehicleHealth.new(1000.0, 0.4)  # fire_threshold would invade DAMAGED
	vh.apply_damage(650.0)  # -> fraction 0.35, inside the DAMAGED band
	assert_bool(vh.is_on_fire()).is_false()


func test_loud_ambient_horn_can_alarm() -> void:
	var horn := SoundPropagation.base_loudness(SoundPropagation.Sound.CAR_HORN)
	assert_int(SoundPropagation.reaction_for(horn, false)).is_equal(
		SoundPropagation.Reaction.ALARMED
	)
	# Boundary preserved: a quieter ambient sound still only gets NOTICED.
	assert_int(SoundPropagation.reaction_for(0.4, false)).is_equal(
		SoundPropagation.Reaction.NOTICED
	)


func test_ballistics_clamps_min_fraction() -> void:
	# min_fraction > 1 must not let a far shot exceed point-blank; < 0 must not heal.
	assert_float(Ballistics.damage_at_range(100.0, 999.0, 10.0, 50.0, 1.5)).is_equal(100.0)
	assert_float(Ballistics.damage_at_range(100.0, 999.0, 10.0, 50.0, -0.5)).is_equal(0.0)


func test_add_armor_ignores_negative() -> void:
	var stats: PlayerStats = auto_free(PlayerStats.new())
	add_child(stats)
	stats.armor = 50.0
	stats.add_armor(-30.0)  # a negative "grant" must not drain armor
	assert_float(stats.armor).is_equal(50.0)
	stats.add_armor(30.0)
	assert_float(stats.armor).is_equal(80.0)
