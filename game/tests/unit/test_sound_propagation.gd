extends RefCounted
## Unit tests for SoundPropagation (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Covers the full acoustic chain: per-kind loudness, distance falloff on the XZ
## plane, ambient masking, audibility/reaction gating, the immutable emit() fan-out,
## loudest_heard() target picking, and the day-night/weather ambient derivation.


func test_base_loudness_explosion_loudest_silenced_quiet() -> bool:
	var e := SoundPropagation.base_loudness(SoundPropagation.Sound.EXPLOSION)
	var g := SoundPropagation.base_loudness(SoundPropagation.Sound.GUNSHOT)
	var s := SoundPropagation.base_loudness(SoundPropagation.Sound.SILENCED_SHOT)
	return e > g and g > s and e <= 1.0 and s >= 0.0


func test_base_loudness_unknown_kind_is_zero() -> bool:
	return SoundPropagation.base_loudness(999) == 0.0


func test_is_alarming_gunshot_true_engine_false() -> bool:
	return (
		SoundPropagation.is_alarming(SoundPropagation.Sound.GUNSHOT)
		and SoundPropagation.is_alarming(SoundPropagation.Sound.ALARM)
		and not SoundPropagation.is_alarming(SoundPropagation.Sound.ENGINE)
		and not SoundPropagation.is_alarming(SoundPropagation.Sound.FOOTSTEP)
	)


func test_silenced_shot_is_not_alarming() -> bool:
	return not SoundPropagation.is_alarming(SoundPropagation.Sound.SILENCED_SHOT)


func test_perceived_intensity_falls_with_distance() -> bool:
	var loud := SoundPropagation.base_loudness(SoundPropagation.Sound.GUNSHOT)
	var src := Vector3.ZERO
	var near := SoundPropagation.perceived_intensity(src, Vector3(5, 0, 0), loud, 0.0)
	var far := SoundPropagation.perceived_intensity(src, Vector3(50, 0, 0), loud, 0.0)
	var at_source := SoundPropagation.perceived_intensity(src, src, loud, 0.0)
	return near > far and near < at_source and far > 0.0


func test_perceived_intensity_uses_xz_plane() -> bool:
	var loud := SoundPropagation.base_loudness(SoundPropagation.Sound.ALARM)
	var src := Vector3.ZERO
	# Two listeners at equal XZ distance (3-4-5) but very different height read equal.
	var ground := SoundPropagation.perceived_intensity(src, Vector3(3, 0, 4), loud, 0.0)
	var elevated := SoundPropagation.perceived_intensity(src, Vector3(3, 100, 4), loud, 0.0)
	return is_equal_approx(ground, elevated)


func test_ambient_masks_quiet_sounds() -> bool:
	var loud := SoundPropagation.base_loudness(SoundPropagation.Sound.FOOTSTEP)
	var src := Vector3.ZERO
	var listener := Vector3(8, 0, 0)
	var quiet := SoundPropagation.perceived_intensity(src, listener, loud, 0.02)
	var noisy := SoundPropagation.perceived_intensity(src, listener, loud, 0.5)
	return quiet > 0.0 and noisy == 0.0


func test_perceived_intensity_clamped_0_1() -> bool:
	var src := Vector3.ZERO
	var at_source := SoundPropagation.perceived_intensity(src, src, 1.0, 0.0)
	var masked := SoundPropagation.perceived_intensity(src, Vector3(5, 0, 0), 0.3, 1.0)
	return at_source == 1.0 and masked == 0.0


func test_is_audible_threshold_gate() -> bool:
	var src := Vector3.ZERO
	var close := SoundPropagation.is_audible(src, Vector3(40, 0, 0), 0.5, 0.0)
	var distant := SoundPropagation.is_audible(src, Vector3(80, 0, 0), 0.5, 0.0)
	return close and not distant


func test_audible_radius_grows_with_loudness_shrinks_with_floor() -> bool:
	var loud_r := SoundPropagation.audible_radius(0.9, 0.05)
	var quiet_r := SoundPropagation.audible_radius(0.3, 0.05)
	var high_floor_r := SoundPropagation.audible_radius(0.9, 0.2)
	var zero_loud := SoundPropagation.audible_radius(0.0, 0.05)
	var zero_floor := SoundPropagation.audible_radius(0.9, 0.0)
	return loud_r > quiet_r and high_floor_r < loud_r and zero_loud == 0.0 and zero_floor == 0.0


func test_reaction_alarming_reaches_alarmed_sooner() -> bool:
	var mid := 0.4
	var alarmed := SoundPropagation.reaction_for(mid, true)
	var noticed := SoundPropagation.reaction_for(mid, false)
	return (
		alarmed == SoundPropagation.Reaction.ALARMED
		and noticed == SoundPropagation.Reaction.NOTICED
	)


func test_reaction_unheard_below_floor() -> bool:
	return SoundPropagation.reaction_for(0.0, true) == SoundPropagation.Reaction.UNHEARD


func test_emit_fans_out_and_is_immutable() -> bool:
	var near := {"pos": Vector3(3, 0, 0)}
	var far := {"pos": Vector3(300, 0, 0)}
	var listeners := [near, far]
	var out := SoundPropagation.emit(Vector3.ZERO, SoundPropagation.Sound.GUNSHOT, listeners, 0.05)
	var near_out: Dictionary = out[0]
	var far_out: Dictionary = out[1]
	# Original input dicts must be untouched (emit returns new dicts).
	var immutable := (
		not near.has("intensity") and not near.has("reaction") and not near.has("heard")
	)
	return (
		near_out["reaction"] == SoundPropagation.Reaction.ALARMED
		and near_out["heard"] == true
		and far_out["heard"] == false
		and immutable
	)


func test_emit_carries_listener_keys_through() -> bool:
	var listeners := [{"pos": Vector3(2, 0, 0), "id": "cop_3"}]
	var out := SoundPropagation.emit(Vector3.ZERO, SoundPropagation.Sound.ALARM, listeners, 0.0)
	var l: Dictionary = out[0]
	return l.get("id", "") == "cop_3" and l.has("intensity")


func test_loudest_heard_picks_highest_intensity() -> bool:
	var listener := Vector3.ZERO
	var events := [
		{"pos": Vector3(60, 0, 0), "kind": SoundPropagation.Sound.EXPLOSION},
		{"pos": Vector3(4, 0, 0), "kind": SoundPropagation.Sound.FOOTSTEP},
	]
	# Near footstep out-shouts a far explosion for this listener.
	var best := SoundPropagation.loudest_heard(listener, events, 0.0)
	var none := SoundPropagation.loudest_heard(Vector3(5000, 0, 0), events, 0.0)
	return best.get("kind", -1) == SoundPropagation.Sound.FOOTSTEP and none.is_empty()


func test_ambient_for_night_quieter_rain_louder_floor() -> bool:
	var base := 0.2
	var night := SoundPropagation.ambient_for(base, true, 0.0)
	var day := SoundPropagation.ambient_for(base, false, 0.0)
	var rainy := SoundPropagation.ambient_for(base, false, 1.0)
	return night < day and rainy > day and night >= 0.0 and rainy <= 1.0
