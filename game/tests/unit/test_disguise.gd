extends RefCounted
## Unit tests for Disguise (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Recognition sums float slot weights, so those assertions use is_equal_approx.
## Includes a cross-system test: a disguised player drains the live WantedEvasion
## "go cold" countdown faster than a recognized one.


func test_fresh_has_no_description() -> bool:
	var d := Disguise.new()
	return not d.has_description() and d.recognition() == 0.0 and d.changed_slots() == 0


func test_default_slots_present() -> bool:
	var d := Disguise.new()
	return d.slots().size() == 4 and d.current("mask") == Disguise.DEFAULT_LOOK


func test_unknown_slot_is_neutral() -> bool:
	var d := Disguise.new()
	d.set_appearance("nope", "x")
	return d.current("nope") == "" and not d.current("nope") == "x"


func test_logged_unchanged_is_fully_recognized() -> bool:
	var d := Disguise.new()
	d.log_sighting()
	return d.has_description() and is_equal_approx(d.recognition(), 1.0)


func test_changing_mask_drops_recognition() -> bool:
	var d := Disguise.new()
	d.log_sighting()
	d.set_appearance("mask", "ski_mask")  # mask weight 0.4 -> recognition 0.6
	return is_equal_approx(d.recognition(), 0.6) and d.changed_slots() == 1


func test_changing_everything_zeroes_recognition() -> bool:
	var d := Disguise.new()
	d.log_sighting()
	d.set_appearance("outfit", "tux")
	d.set_appearance("mask", "ski")
	d.set_appearance("vehicle", "taxi")
	d.set_appearance("hair", "blonde")
	return is_equal_approx(d.recognition(), 0.0) and d.changed_slots() == 4


func test_speedup_scales_with_disguise() -> bool:
	var recognized := Disguise.new()
	recognized.log_sighting()  # recognition 1 -> speedup 1.0
	var disguised := Disguise.new()
	disguised.log_sighting()
	disguised.set_appearance("mask", "ski")  # recognition 0.6 -> speedup 1.8
	return (
		is_equal_approx(recognized.evasion_speedup(), 1.0)
		and is_equal_approx(disguised.evasion_speedup(), 1.8)
	)


func test_speedup_max_when_no_description() -> bool:
	var d := Disguise.new()
	return is_equal_approx(d.evasion_speedup(), Disguise.MAX_EVASION_SPEEDUP)


func test_is_recognized_threshold() -> bool:
	var d := Disguise.new()
	d.log_sighting()
	d.set_appearance("mask", "ski")  # recognition 0.6
	var above := d.is_recognized(0.5)
	d.set_appearance("outfit", "tux")  # recognition 0.3
	var below := d.is_recognized(0.5)
	return above and not below


func test_reset_to_clean_clears_description() -> bool:
	var d := Disguise.new()
	d.log_sighting()
	d.reset_to_clean()
	return not d.has_description() and d.recognition() == 0.0


func test_disguised_evades_faster_than_recognized() -> bool:
	# Cross-system: same real time, the disguised player drains WantedEvasion's
	# search countdown faster and goes cold while the recognized one is still hunted.
	var disguised := Disguise.new()
	disguised.log_sighting()
	disguised.set_appearance("outfit", "tux")
	disguised.set_appearance("mask", "ski")
	disguised.set_appearance("vehicle", "taxi")
	disguised.set_appearance("hair", "blonde")  # recognition 0 -> speedup 3.0
	var recognized := Disguise.new()
	recognized.log_sighting()  # recognition 1 -> speedup 1.0
	var ev_disg := WantedEvasion.new(10.0)
	var ev_recog := WantedEvasion.new(10.0)
	ev_disg.notify_crime()
	ev_recog.notify_crime()
	for _i in range(6):
		ev_disg.update(false, 1.0 * disguised.evasion_speedup())  # 6 * 3 = 18 > 10
		ev_recog.update(false, 1.0 * recognized.evasion_speedup())  # 6 * 1 = 6 < 10
	return ev_disg.is_cold() and ev_recog.is_searching()
