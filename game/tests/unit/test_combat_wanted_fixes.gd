class_name TestCombatWantedFixes
extends GdUnitTestSuite
## Regression tests for two more bug-hunt fixes:
##   - MeleeAttack: a long frame that blew the strike window past in one tick()
##     used to drop the hit (consume_hit checked the live phase). It now latches.
##   - WantedTracker: _process hardcoded committing=false, so heat decayed even
##     mid-rampage. It now holds heat during the active-crime window.


func test_melee_hit_lands_during_a_normal_strike() -> void:
	var m := MeleeAttack.new(0.10, 0.08, 0.34)
	m.start()
	m.tick(0.12)  # past windup -> sitting in STRIKE
	assert_bool(m.consume_hit()).is_true()
	assert_bool(m.consume_hit()).is_false()  # only once per swing


func test_melee_hit_lands_even_when_strike_window_tunnels() -> void:
	# One long frame blows WINDUP(0.10)+STRIKE(0.08) straight into RECOVER, so the
	# live phase is past STRIKE — the latch must still let the hit land once.
	var m := MeleeAttack.new(0.10, 0.08, 0.34)
	m.start()
	m.tick(0.25)
	assert_int(m.phase).is_equal(MeleeAttack.Phase.RECOVER)  # window was skipped
	assert_bool(m.consume_hit()).is_true()
	assert_bool(m.consume_hit()).is_false()


func test_wanted_heat_holds_while_committing_then_decays() -> void:
	var w: WantedTracker = auto_free(WantedTracker.new())
	add_child(w)  # _ready builds the WantedSystem
	w.report_crime(true)
	var heat0 := w._wanted.heat
	assert_float(heat0).is_greater(0.0)
	w._process(0.1)  # inside the active-crime window -> heat holds
	assert_float(w._wanted.heat).is_equal(heat0)
	w._process(1.0)  # window elapsed -> heat decays
	assert_float(w._wanted.heat).is_less(heat0)
