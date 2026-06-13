extends RefCounted
## Unit tests for SkyModel — the deterministic day/night core that aims the sun,
## sets key/ambient light and feeds the sky shader. If these drift, the cast
## shadows, the ambient term and the painted sky stop agreeing.


func test_noon_sun_is_high() -> bool:
	return SkyModel.sun_direction(12.0).y > 0.8


func test_midnight_sun_is_below_horizon() -> bool:
	return SkyModel.sun_direction(0.0).y < -0.5


func test_sun_direction_is_unit_length() -> bool:
	for h in [0.0, 4.5, 9.0, 12.0, 17.5, 21.0, 23.99]:
		if absf(SkyModel.sun_direction(h).length() - 1.0) > 1e-4:
			return false
	return true


func test_sunrise_in_the_east() -> bool:
	# Just after 06:00 the sun clears the horizon to the east (+X).
	var d := SkyModel.sun_direction(6.5)
	return d.x > 0.0 and absf(d.y) < 0.25


func test_sunset_in_the_west() -> bool:
	# Just before 18:00 the sun sits low in the west (-X).
	var d := SkyModel.sun_direction(17.5)
	return d.x < 0.0 and absf(d.y) < 0.25


func test_time_wraps_around_the_day() -> bool:
	# 24h later is the same instant; negative hours wrap too.
	var a := SkyModel.sun_direction(8.0)
	var b := SkyModel.sun_direction(32.0)
	var c := SkyModel.sun_direction(-16.0)
	return a.distance_to(b) < 1e-4 and a.distance_to(c) < 1e-4


func test_elevation_matches_direction() -> bool:
	var tod := 10.0
	return absf(SkyModel.sun_elevation(tod) - asin(SkyModel.sun_direction(tod).y)) < 1e-5


func test_moon_opposes_sun() -> bool:
	var tod := 22.0
	return SkyModel.moon_direction(tod).distance_to(-SkyModel.sun_direction(tod)) < 1e-5


func test_daylight_brighter_than_night() -> bool:
	return SkyModel.light_energy(12.0) > SkyModel.light_energy(0.0)


func test_night_keeps_moonlight_floor() -> bool:
	# Energy never collapses to pure black, so night scenes still read.
	return SkyModel.light_energy(0.0) >= SkyModel.MOON_ENERGY - 1e-6


func test_daylight_reaches_full_energy() -> bool:
	return absf(SkyModel.light_energy(12.0) - SkyModel.MAX_SUN_ENERGY) < 0.05


func test_low_sun_is_warmer_than_high_sun() -> bool:
	# Sunset light leans orange: more red, less blue than the midday key.
	var dusk := SkyModel.light_color(18.2)
	var noon := SkyModel.light_color(12.0)
	return dusk.r >= noon.r and dusk.b < noon.b


func test_night_amount_is_zero_at_noon() -> bool:
	return SkyModel.night_amount(12.0) < 0.01


func test_night_amount_is_one_at_midnight() -> bool:
	return SkyModel.night_amount(0.0) > 0.99


func test_night_amount_in_range() -> bool:
	for h in [0.0, 3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0]:
		var n := SkyModel.night_amount(h)
		if n < 0.0 or n > 1.0:
			return false
	return true


func test_ambient_brighter_by_day() -> bool:
	var a := SkyModel.ambient_energy(12.0)
	return a > SkyModel.ambient_energy(0.0) and a <= SkyModel.MAX_AMBIENT + 1e-6


func test_ambient_color_warm_by_day_cool_by_night() -> bool:
	# Noon fill is warm (red >= blue); midnight fill is cool (blue > red), so
	# night shadows pick up moonlight rather than the daytime golden tint.
	var noon := SkyModel.ambient_color(12.0)
	var night := SkyModel.ambient_color(0.0)
	return noon.r >= noon.b and night.b > night.r


func test_ambient_color_matches_authored_day_tint() -> bool:
	# Daytime must stay the colour the scene was authored against.
	var noon := SkyModel.ambient_color(12.0)
	return noon.is_equal_approx(SkyModel.DAY_AMBIENT_COLOR)


func test_moon_light_energy_brighter_than_sun_floor() -> bool:
	# The dedicated moon key is brighter than the sun's residual night floor so a
	# moonlit night actually reads.
	return SkyModel.MOON_LIGHT_ENERGY > SkyModel.MOON_ENERGY


func test_sky_sun_energy_clamped() -> bool:
	for h in [0.0, 6.0, 12.0, 18.0, 23.0]:
		var e := SkyModel.sky_sun_energy(h)
		if e < 0.0 or e > 1.0:
			return false
	return true


func test_sun_up_flag_tracks_horizon() -> bool:
	return SkyModel.is_sun_up(12.0) and not SkyModel.is_sun_up(0.0)
