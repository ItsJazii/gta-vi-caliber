extends RefCounted
## Unit tests for GauntletChecks — the pure math behind the asset integration
## gauntlet (tests/asset_gauntlet_capture.gd). Runner contract: test_* methods
## return true to pass.


func test_luma_stats_mean_and_stddev() -> bool:
	var stats := GauntletChecks.luma_stats(PackedFloat32Array([0.0, 0.5, 1.0]))
	return is_equal_approx(stats.mean, 0.5) and absf(stats.stddev - 0.4082) < 0.001


func test_luma_stats_empty_is_blank_and_uniform() -> bool:
	var stats := GauntletChecks.luma_stats(PackedFloat32Array())
	return is_equal_approx(stats.mean, 0.0) and is_equal_approx(stats.stddev, 0.0)


func test_blank_verdict() -> bool:
	return (
		GauntletChecks.is_blank(0.001)
		and not GauntletChecks.is_blank(0.05)
		and GauntletChecks.is_blank(GauntletChecks.BLANK_MEAN_LUMA - 0.0001)
	)


func test_uniform_verdict() -> bool:
	return GauntletChecks.is_uniform(0.002) and not GauntletChecks.is_uniform(0.08)


func test_flicker_fraction_counts_only_big_deltas() -> bool:
	var a := PackedFloat32Array([0.5, 0.5, 0.5, 0.5])
	var b := PackedFloat32Array([0.5, 0.51, 0.9, 0.5])
	# one of four samples exceeds a 0.25 delta
	return is_equal_approx(GauntletChecks.flicker_fraction(a, b, 0.25), 0.25)


func test_flicker_fraction_mismatched_lengths_is_total_failure() -> bool:
	var a := PackedFloat32Array([0.5, 0.5])
	var b := PackedFloat32Array([0.5])
	return is_equal_approx(GauntletChecks.flicker_fraction(a, b, 0.25), 1.0)


func test_arc_poses_count_and_walking_height() -> bool:
	var poses := GauntletChecks.arc_poses(
		8, Vector3(0, 1.7, 60), Vector3(0, 1.7, 12), Vector3.ZERO, 35.0
	)
	if poses.size() != 8:
		return false
	for p in poses:
		if not is_equal_approx(p.pos.y, 1.7):
			return false
	return true


func test_arc_poses_make_forward_progress() -> bool:
	var poses := GauntletChecks.arc_poses(
		6, Vector3(0, 1.7, 60), Vector3(0, 1.7, 12), Vector3.ZERO, 35.0
	)
	for i in range(1, poses.size()):
		if poses[i].pos.z >= poses[i - 1].pos.z:
			return false
	return true


func test_arc_poses_swing_is_bounded_and_actually_swings() -> bool:
	var swing := 35.0
	var poses := GauntletChecks.arc_poses(
		12, Vector3(0, 1.7, 60), Vector3(0, 1.7, 12), Vector3.ZERO, swing
	)
	var max_off := 0.0
	for p in poses:
		var fwd: Vector3 = (Vector3.ZERO - p.pos).normalized()
		var look_dir: Vector3 = (p.look - p.pos).normalized()
		var off := absf(rad_to_deg(fwd.signed_angle_to(look_dir, Vector3.UP)))
		max_off = maxf(max_off, off)
	return max_off > swing * 0.5 and max_off <= swing + 0.01


func test_framing_distance_scales_with_radius_and_fov() -> bool:
	var near := GauntletChecks.framing_distance(5.0, 65.0, 0.8)
	var far := GauntletChecks.framing_distance(50.0, 65.0, 0.8)
	var tele := GauntletChecks.framing_distance(5.0, 30.0, 0.8)
	return far > near and tele > near and near > 0.0


func test_glass_sweep_poses_hit_requested_incidence() -> bool:
	var normal := Vector3(0, 0, 1)
	var center := Vector3(0, 8, 28)
	var poses := GauntletChecks.glass_sweep_poses(
		center, normal, 12.0, 1.7, PackedFloat32Array([0.0, 45.0, 80.0])
	)
	if poses.size() != 3:
		return false
	for i in poses.size():
		var to_cam: Vector3 = poses[i].pos - center
		to_cam.y = 0.0  # incidence measured in the horizontal plane
		var angle := rad_to_deg(to_cam.normalized().angle_to(normal))
		if absf(angle - [0.0, 45.0, 80.0][i]) > 0.5:
			return false
		if not is_equal_approx(poses[i].pos.y, 1.7):
			return false
	return true


func test_glass_sweep_poses_keep_distance() -> bool:
	var center := Vector3(0, 8, 28)
	var poses := GauntletChecks.glass_sweep_poses(
		center, Vector3(0, 0, 1), 12.0, 1.7, PackedFloat32Array([10.0, 70.0])
	)
	for p in poses:
		var flat: Vector3 = p.pos - center
		flat.y = 0.0
		if absf(flat.length() - 12.0) > 0.01:
			return false
	return true
