extends RefCounted
## Unit tests for WeaponLoadout (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Multipliers are float products, so those checks use is_equal_approx. Includes a
## WeaponBallistics composition test: a scope's range multiplier extends effective
## damage at distance.


func test_default_catalogue_loaded() -> bool:
	var l := WeaponLoadout.new()
	return (
		l.attachment_count() == 6 and l.has_attachment("scope") and l.has_attachment("suppressor")
	)


func test_malformed_attachments_dropped() -> bool:
	var l := (
		WeaponLoadout
		. new(
			[
				{"id": "ok", "slot": "optic"},
				{"id": "no_slot"},
				{"slot": "optic"},  # no id
				{"id": "bad_slot", "slot": "frame"},  # unknown slot
				{"id": "ok", "slot": "grip"},  # duplicate id
			]
		)
	)
	return l.attachment_count() == 1 and l.has_attachment("ok")


func test_slot_lookup() -> bool:
	var l := WeaponLoadout.new()
	return l.slot_of("suppressor") == "muzzle" and l.slot_of("nope") == ""


func test_equip_sets_slot() -> bool:
	var l := WeaponLoadout.new()
	return l.equip("scope") and l.equipped_in("optic") == "scope" and l.is_equipped("scope")


func test_equip_unknown_fails() -> bool:
	var l := WeaponLoadout.new()
	return not l.equip("nope") and l.equipped_count() == 0


func test_equip_replaces_same_slot() -> bool:
	var l := WeaponLoadout.new()
	l.equip("scope")
	l.equip("red_dot")  # same slot 'optic'
	return l.equipped_in("optic") == "red_dot" and not l.is_equipped("scope")


func test_unequip_clears_slot() -> bool:
	var l := WeaponLoadout.new()
	l.equip("scope")
	l.unequip("optic")
	return l.equipped_in("optic") == "" and l.equipped_count() == 0


func test_mult_neutral_when_unaffected() -> bool:
	var l := WeaponLoadout.new()
	l.equip("extended_mag")  # only adds mag, no mults
	return is_equal_approx(l.mult_for("spread"), 1.0)


func test_mult_combines_by_product() -> bool:
	var l := WeaponLoadout.new()
	l.equip("scope")  # spread 0.6
	l.equip("foregrip")  # spread 0.9
	# 0.6 * 0.9 = 0.54
	return is_equal_approx(l.mult_for("spread"), 0.54)


func test_apply_mult() -> bool:
	var l := WeaponLoadout.new()
	l.equip("scope")  # range 1.25
	return is_equal_approx(l.apply_mult(60.0, "range"), 75.0)


func test_mag_size_additive() -> bool:
	var l := WeaponLoadout.new()
	l.equip("extended_mag")  # +12
	return l.mag_size(30) == 42 and l.mag_size(0) == 12


func test_suppressed_flag() -> bool:
	var l := WeaponLoadout.new()
	var before := l.is_suppressed()
	l.equip("suppressor")
	return not before and l.is_suppressed()


func test_clear_strips_all() -> bool:
	var l := WeaponLoadout.new()
	l.equip("scope")
	l.equip("suppressor")
	l.clear()
	return l.equipped_count() == 0 and not l.is_suppressed()


func test_scope_extends_effective_range() -> bool:
	# Composition: a scope's range multiplier widens WeaponBallistics' falloff
	# window, so the same shot at distance lands harder.
	var l := WeaponLoadout.new()
	l.equip("scope")  # range 1.25
	var dist := 50.0
	var bare := WeaponBallistics.effective_damage(30.0, dist, "torso", 20.0, 60.0, 0.2)
	var scoped := WeaponBallistics.effective_damage(
		30.0, dist, "torso", l.apply_mult(20.0, "range"), l.apply_mult(60.0, "range"), 0.2
	)
	return scoped > bare
