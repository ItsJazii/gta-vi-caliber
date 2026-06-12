extends RefCounted
## Unit tests for CombatAi (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). Related assertions are grouped to stay
## under gdlint's max-public-methods cap.

const ORIGIN := Vector3.ZERO
const FAR := Vector3(50, 0, 0)


func _band() -> Vector2:
	return CombatAi.engagement_band(14.0, 0.25)  # ~[10.5, 17.5]


# --- engagement_band ------------------------------------------------------


func test_engagement_band() -> bool:
	var b := CombatAi.engagement_band(14.0, 0.25)
	if not (b.x < 14.0 and b.y > 14.0):
		return false
	# hysteresis > 0.9 must not invert the band.
	var wide := CombatAi.engagement_band(10.0, 5.0)
	return wide.x >= 0.0 and wide.x < wide.y


# --- in_firing_arc --------------------------------------------------------


func test_firing_arc_front_vs_back() -> bool:
	var ahead := CombatAi.in_firing_arc(
		Vector3(1, 0, 0), Vector3(1, 0, 0), CombatAi.DEFAULT_ARC_HALF
	)
	var behind := CombatAi.in_firing_arc(
		Vector3(1, 0, 0), Vector3(-1, 0, 0), CombatAi.DEFAULT_ARC_HALF
	)
	return ahead and not behind


func test_firing_arc_ignores_height() -> bool:
	# Target straight ahead in XZ but offset in Y is still in the planar arc.
	return CombatAi.in_firing_arc(Vector3(1, 0, 0), Vector3(1, 9, 0), CombatAi.DEFAULT_ARC_HALF)


func test_firing_arc_false_on_zero_vector() -> bool:
	return not CombatAi.in_firing_arc(Vector3.ZERO, Vector3(1, 0, 0), CombatAi.DEFAULT_ARC_HALF)


# --- decide_action --------------------------------------------------------


func test_advance_when_out_of_range() -> bool:
	return (
		CombatAi.decide_action(40.0, _band(), true, true, 1.0, 0.8, 30) == CombatAi.Action.ADVANCE
	)


func test_engage_when_in_band_and_aimed() -> bool:
	return CombatAi.decide_action(14.0, _band(), true, true, 1.0, 0.8, 30) == CombatAi.Action.ENGAGE


func test_reposition_when_in_band_but_not_aimed() -> bool:
	return (
		CombatAi.decide_action(14.0, _band(), true, false, 1.0, 0.8, 30)
		== CombatAi.Action.REPOSITION
	)


func test_reposition_when_too_close() -> bool:
	return (
		CombatAi.decide_action(5.0, _band(), true, true, 1.0, 0.8, 30) == CombatAi.Action.REPOSITION
	)


func test_advance_when_no_line_of_sight() -> bool:
	# In band and aimed, but no LOS → must move rather than fire blind.
	return (
		CombatAi.decide_action(14.0, _band(), false, true, 1.0, 0.8, 30) == CombatAi.Action.ADVANCE
	)


func test_take_cover_when_hurt_but_lethal_presses_on() -> bool:
	var hurt := CombatAi.decide_action(14.0, _band(), true, true, 0.3, 0.6, 30)
	# aggression 1.0 (5-star heat) attacks even while hurt.
	var lethal := CombatAi.decide_action(14.0, _band(), true, true, 0.3, 1.0, 30)
	return hurt == CombatAi.Action.TAKE_COVER and lethal == CombatAi.Action.ENGAGE


func test_retreat_when_badly_hurt_and_timid() -> bool:
	return (
		CombatAi.decide_action(14.0, _band(), true, true, 0.1, 0.3, 30) == CombatAi.Action.RETREAT
	)


func test_out_of_ammo_branches_on_resolve() -> bool:
	var timid := CombatAi.decide_action(14.0, _band(), true, true, 1.0, 0.4, 0)
	# Relentless unit breaks contact to reload rather than fleeing.
	var lethal := CombatAi.decide_action(14.0, _band(), true, true, 1.0, 0.9, 0)
	return timid == CombatAi.Action.RETREAT and lethal == CombatAi.Action.REPOSITION


# --- should_fire ----------------------------------------------------------


func test_fires_only_when_engaging_and_ready() -> bool:
	if not CombatAi.should_fire(CombatAi.Action.ENGAGE, true):
		return false
	if CombatAi.should_fire(CombatAi.Action.ENGAGE, false):
		return false
	return not CombatAi.should_fire(CombatAi.Action.REPOSITION, true)


# --- fire_interval --------------------------------------------------------


func test_fire_interval_scales_and_clamps() -> bool:
	if not (CombatAi.fire_interval(1.0, 1.0) < CombatAi.fire_interval(1.0, 0.0)):
		return false
	# Out-of-range aggression must not push the interval past its bounds.
	var lo := CombatAi.fire_interval(1.0, 5.0)
	var hi := CombatAi.fire_interval(1.0, -5.0)
	return is_equal_approx(lo, 0.6) and is_equal_approx(hi, 1.8)


# --- desired_move ---------------------------------------------------------


func test_advance_and_retreat_are_radial() -> bool:
	var adv := CombatAi.desired_move(CombatAi.Action.ADVANCE, ORIGIN, FAR, 1.0)
	var ret := CombatAi.desired_move(CombatAi.Action.RETREAT, ORIGIN, FAR, 1.0)
	return adv.dot(Vector3(1, 0, 0)) > 0.99 and ret.dot(Vector3(1, 0, 0)) < -0.99


func test_engage_holds_position() -> bool:
	return CombatAi.desired_move(CombatAi.Action.ENGAGE, ORIGIN, FAR, 1.0) == Vector3.ZERO


func test_reposition_is_lateral_and_normalized() -> bool:
	var dir := CombatAi.desired_move(CombatAi.Action.REPOSITION, ORIGIN, FAR, 1.0)
	# Strafing target on +X: lateral (z) component dominates the radial (x) one.
	return absf(dir.z) > absf(dir.x) and dir.is_normalized()


func test_reposition_side_flips_with_sign() -> bool:
	var left := CombatAi.desired_move(CombatAi.Action.REPOSITION, ORIGIN, FAR, 1.0)
	var right := CombatAi.desired_move(CombatAi.Action.REPOSITION, ORIGIN, FAR, -1.0)
	return signf(left.z) != signf(right.z)


# --- move_speed -----------------------------------------------------------


func test_engage_speed_is_zero() -> bool:
	return is_equal_approx(CombatAi.move_speed(CombatAi.Action.ENGAGE, 6.0), 0.0)


func test_advance_runs_and_outpaces_reposition() -> bool:
	var adv := CombatAi.move_speed(CombatAi.Action.ADVANCE, 6.0)
	return is_equal_approx(adv, 6.0) and CombatAi.move_speed(CombatAi.Action.REPOSITION, 6.0) < adv
