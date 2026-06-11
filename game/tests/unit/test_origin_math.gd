extends RefCounted
## Unit tests for OriginMath — the float-precision budget math behind the
## floating-origin shift. Off-by-one here means kilometre-scale jitter.


func test_no_shift_near_origin() -> bool:
	return not OriginMath.should_shift(Vector3(100.0, 0.0, 100.0))


func test_shift_due_past_threshold() -> bool:
	return OriginMath.should_shift(Vector3(3000.0, 0.0, 0.0))


func test_height_alone_never_triggers() -> bool:
	return not OriginMath.should_shift(Vector3(0.0, 99999.0, 0.0))


func test_diagonal_distance_counts() -> bool:
	# 1800² + 1800² > 2048² even though each axis is under the threshold.
	return OriginMath.should_shift(Vector3(1800.0, 0.0, 1800.0))


func test_custom_threshold_respected() -> bool:
	var pos := Vector3(600.0, 0.0, 0.0)
	return OriginMath.should_shift(pos, 500.0) and not OriginMath.should_shift(pos, 700.0)


func test_shift_is_grid_snapped() -> bool:
	var shift := OriginMath.shift_for(Vector3(2500.0, 0.0, -2300.0))
	var on_grid_x := absf(fmod(shift.x, OriginMath.DEFAULT_GRID_M)) < 0.001
	var on_grid_z := absf(fmod(shift.z, OriginMath.DEFAULT_GRID_M)) < 0.001
	return on_grid_x and on_grid_z


func test_shift_never_touches_y() -> bool:
	return OriginMath.shift_for(Vector3(5000.0, 1234.0, 5000.0)).y == 0.0


func test_shift_brings_anchor_near_origin() -> bool:
	var pos := Vector3(2500.0, 0.0, -2300.0)
	var landed := pos + OriginMath.shift_for(pos)
	# After snapping, the anchor lands within half a grid cell of the origin.
	return landed.length() <= OriginMath.DEFAULT_GRID_M


func test_offset_accumulates_exactly() -> bool:
	var offset := Vector3.ZERO
	offset = OriginMath.accumulate_offset(offset, Vector3(-2560.0, 0.0, 0.0))
	offset = OriginMath.accumulate_offset(offset, Vector3(0.0, 0.0, -512.0))
	return offset == Vector3(-2560.0, 0.0, -512.0)


func test_absolute_position_round_trips() -> bool:
	# Walk to absolute (2500, 0, 0), shift, then reconstruct.
	var absolute := Vector3(2500.0, 2.0, 0.0)
	var shift := OriginMath.shift_for(absolute)
	var local := absolute + shift
	var offset := OriginMath.accumulate_offset(Vector3.ZERO, shift)
	return OriginMath.to_absolute(local, offset).is_equal_approx(absolute)
