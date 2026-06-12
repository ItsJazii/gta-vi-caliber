extends RefCounted
## Unit tests for CombatCover (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). Concrete coords; planar XZ, y ignored.


func _cover(pos: Vector3, normal: Vector3) -> Dictionary:
	return {"pos": pos, "normal": normal}


# --- provides_cover -------------------------------------------------------------


func test_provides_cover_threat_on_faced_side() -> bool:
	# Cover at origin facing +X; threat out at +X is on the faced side ⇒ protected.
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	return CombatCover.provides_cover(cover, Vector3(5, 0, 0))


func test_provides_cover_false_when_threat_behind_open_side() -> bool:
	# Threat at -X sits on the agent's open side ⇒ wall doesn't block it.
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	return not CombatCover.provides_cover(cover, Vector3(-5, 0, 0))


func test_provides_cover_false_for_zero_normal() -> bool:
	var cover := _cover(Vector3.ZERO, Vector3.ZERO)
	return not CombatCover.provides_cover(cover, Vector3(5, 0, 0))


func test_provides_cover_ignores_vertical() -> bool:
	# Threat directly above counts only by its XZ offset; here also +X ⇒ protected.
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	return CombatCover.provides_cover(cover, Vector3(5, 99, 0))


func test_provides_cover_threat_coincident_no_nan() -> bool:
	var cover := _cover(Vector3(3, 0, 3), Vector3(0, 0, 1))
	return not CombatCover.provides_cover(cover, Vector3(3, 0, 3))


# --- cover_quality --------------------------------------------------------------


func test_quality_in_unit_range() -> bool:
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	var q := CombatCover.cover_quality(cover, Vector3(6, 0, 0), 0.5)
	return q >= 0.0 and q <= 1.0


func test_quality_square_beats_oblique() -> bool:
	# Same distance: a threat dead-ahead of the normal scores above a glancing one.
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	var square := CombatCover.cover_quality(cover, Vector3(6, 0, 0), 0.5)
	var oblique := CombatCover.cover_quality(cover, Vector3(4.24, 0, 4.24), 0.5)
	return square > oblique


func test_quality_close_beats_far_for_square() -> bool:
	# Both squarely faced; the nearer (but still useful) threat scores no less.
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	var near := CombatCover.cover_quality(cover, Vector3(6, 0, 0), 0.5)
	var far := CombatCover.cover_quality(cover, Vector3(11, 0, 0), 0.5)
	return near > 0.0 and far > 0.0 and near >= far


func test_quality_zero_when_not_protecting() -> bool:
	# Threat on the open side ⇒ no protection ⇒ zero quality.
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	return is_equal_approx(CombatCover.cover_quality(cover, Vector3(-6, 0, 0), 0.5), 0.0)


func test_quality_zero_for_degenerate_normal() -> bool:
	var cover := _cover(Vector3.ZERO, Vector3.ZERO)
	return is_equal_approx(CombatCover.cover_quality(cover, Vector3(6, 0, 0), 0.5), 0.0)


func test_quality_zero_when_coincident() -> bool:
	var cover := _cover(Vector3(2, 0, 2), Vector3(1, 0, 0))
	return is_equal_approx(CombatCover.cover_quality(cover, Vector3(2, 0, 2), 0.5), 0.0)


# --- best_cover -----------------------------------------------------------------


func test_best_cover_picks_protecting_and_nearest() -> bool:
	# Agent at origin; threat far +X. Two protecting covers face +X — the nearer wins.
	var near := _cover(Vector3(1, 0, 0), Vector3(1, 0, 0))
	var far := _cover(Vector3(8, 0, 0), Vector3(1, 0, 0))
	var best := CombatCover.best_cover([far, near], Vector3.ZERO, Vector3(20, 0, 0))
	return best.get("pos") == Vector3(1, 0, 0)


func test_best_cover_skips_non_protecting_even_if_nearer() -> bool:
	# Nearest cover faces away from the threat; the protecting (farther) one is chosen.
	var near_wrong := _cover(Vector3(1, 0, 0), Vector3(-1, 0, 0))
	var far_right := _cover(Vector3(5, 0, 0), Vector3(1, 0, 0))
	var best := CombatCover.best_cover([near_wrong, far_right], Vector3.ZERO, Vector3(20, 0, 0))
	return best.get("pos") == Vector3(5, 0, 0)


func test_best_cover_empty_list() -> bool:
	return CombatCover.best_cover([], Vector3.ZERO, Vector3(5, 0, 0)).is_empty()


func test_best_cover_none_protect() -> bool:
	# Every cover faces away from the threat ⇒ none protect ⇒ {}.
	var a := _cover(Vector3(1, 0, 0), Vector3(-1, 0, 0))
	var b := _cover(Vector3(2, 0, 0), Vector3(-1, 0, 0))
	return CombatCover.best_cover([a, b], Vector3.ZERO, Vector3(20, 0, 0)).is_empty()


# --- peek_position --------------------------------------------------------------


func test_peek_is_offset_sideways() -> bool:
	# Cover at origin, threat down +Z. Peek steps along X (perpendicular), not Z.
	var cover := _cover(Vector3.ZERO, Vector3(0, 0, 1))
	var peek := CombatCover.peek_position(cover, Vector3(0, 0, 10), 1.5)
	return is_equal_approx(absf(peek.x), 1.5) and is_equal_approx(peek.z, 0.0)


func test_peek_not_on_threat_line() -> bool:
	# The peek spot must have lateral offset from the cover→threat axis.
	var cover := _cover(Vector3.ZERO, Vector3(0, 0, 1))
	var peek := CombatCover.peek_position(cover, Vector3(0, 0, 10), 2.0)
	return absf(peek.x) > 0.0001


func test_peek_sign_flips_side() -> bool:
	var cover := _cover(Vector3.ZERO, Vector3(0, 0, 1))
	var right := CombatCover.peek_position(cover, Vector3(0, 0, 10), 2.0)
	var left := CombatCover.peek_position(cover, Vector3(0, 0, 10), -2.0)
	return is_equal_approx(right.x, -left.x) and absf(right.x) > 0.0001


func test_peek_coincident_threat_falls_back_to_pos() -> bool:
	var cover := _cover(Vector3(4, 0, 4), Vector3(0, 0, 1))
	var peek := CombatCover.peek_position(cover, Vector3(4, 0, 4), 2.0)
	return peek == Vector3(4, 0, 4)


# --- is_exposed -----------------------------------------------------------------


func test_is_exposed_false_when_tucked_behind() -> bool:
	# Cover faces +X; agent tucked on -X (open) side is shielded ⇒ not exposed.
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	return not CombatCover.is_exposed(Vector3(-0.5, 0, 0), cover, Vector3(10, 0, 0))


func test_is_exposed_true_when_stepped_wide() -> bool:
	# Agent steps past the wall onto the threat's side ⇒ exposed.
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	return CombatCover.is_exposed(Vector3(1.0, 0, 0), cover, Vector3(10, 0, 0))


func test_is_exposed_true_when_cover_cannot_protect() -> bool:
	# Threat on the open side: the cover can't help, so the agent is exposed anywhere.
	var cover := _cover(Vector3.ZERO, Vector3(1, 0, 0))
	return CombatCover.is_exposed(Vector3(-0.5, 0, 0), cover, Vector3(-10, 0, 0))


# --- threat_direction -----------------------------------------------------------


func test_threat_direction_normalized() -> bool:
	var dir := CombatCover.threat_direction(Vector3.ZERO, Vector3(3, 0, 4))
	return is_equal_approx(dir.length(), 1.0)


func test_threat_direction_horizontal() -> bool:
	# Vertical separation is dropped: direction lies in the XZ plane.
	var dir := CombatCover.threat_direction(Vector3.ZERO, Vector3(0, 50, 10))
	return is_equal_approx(dir.y, 0.0) and is_equal_approx(dir.z, 1.0)


func test_threat_direction_zero_when_coincident() -> bool:
	var dir := CombatCover.threat_direction(Vector3(2, 0, 2), Vector3(2, 0, 2))
	return dir == Vector3.ZERO
