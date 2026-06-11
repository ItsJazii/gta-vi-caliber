extends RefCounted
## Unit tests for DaylightMath (runner contract: test_* methods return true).


func test_noon_sun_is_high_and_dawn_dusk_sit_on_horizon() -> bool:
	var noon := DaylightMath.sun_elevation_deg(13.0)
	return (
		absf(noon - DaylightMath.NOON_ELEVATION_DEG) < 0.001
		and absf(DaylightMath.sun_elevation_deg(DaylightMath.SUNRISE_HOUR)) < 0.001
		and absf(DaylightMath.sun_elevation_deg(DaylightMath.SUNSET_HOUR)) < 0.001
	)


func test_midnight_sun_is_below_horizon() -> bool:
	return DaylightMath.sun_elevation_deg(0.0) < -35.0


func test_hour_wraps_past_24() -> bool:
	var a := DaylightMath.sun_elevation_deg(25.5)
	var b := DaylightMath.sun_elevation_deg(1.5)
	return absf(a - b) < 0.0001


func test_sun_rises_east_crosses_south_sets_west() -> bool:
	return (
		absf(DaylightMath.sun_azimuth_deg(6.0) - 90.0) < 0.001
		and absf(DaylightMath.sun_azimuth_deg(13.0) - 180.0) < 0.001
		and absf(DaylightMath.sun_azimuth_deg(20.0) - 270.0) < 0.001
	)


func test_sun_direction_is_unit_and_points_up_at_noon() -> bool:
	var dir := DaylightMath.sun_direction(13.0)
	return absf(dir.length() - 1.0) < 0.001 and dir.y > 0.85


func test_sun_direction_points_east_at_sunrise() -> bool:
	var dir := DaylightMath.sun_direction(6.0)
	return dir.x > 0.99 and absf(dir.y) < 0.01


func test_key_light_direction_never_comes_from_below() -> bool:
	for h in [0.0, 3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 23.5]:
		if DaylightMath.key_light_direction(h).y < -0.001:
			return false
	return true


func test_energy_peaks_at_noon_and_floors_at_night() -> bool:
	var noon := DaylightMath.sun_energy(13.0)
	var midnight := DaylightMath.sun_energy(0.0)
	return (
		absf(noon - DaylightMath.MAX_SUN_ENERGY) < 0.001
		and absf(midnight - DaylightMath.NIGHT_ENERGY) < 0.001
		and DaylightMath.sun_energy(7.0) > midnight
	)


func test_golden_hour_is_warmer_than_noon() -> bool:
	var golden := DaylightMath.sun_color(6.7)
	var noon := DaylightMath.sun_color(13.0)
	return (golden.r - golden.b) > (noon.r - noon.b) + 0.2


func test_golden_factor_zero_at_night_and_noon() -> bool:
	return (
		DaylightMath.golden_factor(0.0) < 0.001
		and DaylightMath.golden_factor(13.0) < 0.001
		and DaylightMath.golden_factor(6.5) > 0.5
	)


func test_sky_is_dark_at_night_and_blue_by_day() -> bool:
	var night := DaylightMath.sky_top_color(1.0)
	var day := DaylightMath.sky_top_color(13.0)
	return night.get_luminance() < 0.05 and day.b > 0.5


func test_horizon_glows_warm_at_dusk() -> bool:
	var dusk := DaylightMath.sky_horizon_color(19.8)
	return dusk.r > dusk.b + 0.3


func test_windows_dark_at_noon_lit_at_midnight() -> bool:
	return DaylightMath.window_emission(13.0) < 0.001 and DaylightMath.window_emission(1.0) > 0.999


func test_window_emission_fades_through_dusk() -> bool:
	var dusk := DaylightMath.window_emission(20.1)
	return dusk > 0.0 and dusk < 1.0


func test_streetlight_hysteresis_band() -> bool:
	var on_at_dusk := DaylightMath.lights_on(-2.0, false)
	var stays_off_in_band := DaylightMath.lights_on(3.0, false)
	var stays_on_in_band := DaylightMath.lights_on(3.0, true)
	var off_in_daylight := DaylightMath.lights_on(10.0, true)
	return on_at_dusk and not stays_off_in_band and stays_on_in_band and not off_in_daylight


func test_spaced_along_straight_line_spacing() -> bool:
	var path := PackedVector2Array([Vector2.ZERO, Vector2(100.0, 0.0)])
	var pts := DaylightMath.spaced_along(path, 25.0)
	if pts.size() != 5:
		return false
	return pts[0] == Vector2.ZERO and absf(pts[1].x - 25.0) < 0.001


func test_spaced_along_offsets_to_the_right() -> bool:
	# Heading +X: "right" of travel is +Y in our XZ-plane 2D convention.
	var path := PackedVector2Array([Vector2.ZERO, Vector2(50.0, 0.0)])
	var pts := DaylightMath.spaced_along(path, 20.0, 3.0)
	for p in pts:
		if absf(p.y - 3.0) > 0.001:
			return false
	return pts.size() == 3


func test_spaced_along_degenerate_input_is_empty() -> bool:
	var single := PackedVector2Array([Vector2.ZERO])
	return (
		DaylightMath.spaced_along(single, 10.0).is_empty()
		and DaylightMath.spaced_along(PackedVector2Array(), 10.0).is_empty()
	)
