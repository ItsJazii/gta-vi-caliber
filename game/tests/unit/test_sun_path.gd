extends RefCounted
## Unit tests for SunPath — the day/night cycle math. The boundaries that matter:
## noon is highest and brightest, midnight is below the horizon and dark, dawn/
## dusk are warm, and nothing ever goes fully black.


func test_solar_height_peaks_at_noon() -> bool:
	return absf(SunPath.solar_height(12.0) - 1.0) < 0.001


func test_solar_height_zero_at_horizons() -> bool:
	return absf(SunPath.solar_height(6.0)) < 0.001 and absf(SunPath.solar_height(18.0)) < 0.001


func test_solar_height_negative_at_midnight() -> bool:
	return SunPath.solar_height(0.0) < -0.99


func test_is_daytime() -> bool:
	return (
		SunPath.is_daytime(12.0)
		and SunPath.is_daytime(9.0)
		and not SunPath.is_daytime(3.0)
		and not SunPath.is_daytime(22.0)
	)


func test_pitch_above_horizon_by_day_below_by_night() -> bool:
	return SunPath.sun_pitch(12.0) > 0.0 and SunPath.sun_pitch(0.0) < 0.0


func test_energy_peaks_at_noon_floors_at_night() -> bool:
	return (
		absf(SunPath.energy(12.0) - SunPath.PEAK_ENERGY) < 0.001
		and absf(SunPath.energy(0.0) - SunPath.NIGHT_ENERGY) < 0.001
	)


func test_energy_never_below_night_floor() -> bool:
	var h := 0.0
	while h < 24.0:
		if SunPath.energy(h) < SunPath.NIGHT_ENERGY - 0.001:
			return false
		h += 0.5
	return true


func test_night_light_is_cool_blue() -> bool:
	var c := SunPath.light_color(1.0)
	return c.b > c.r  # bluer than it is red


func test_noon_light_is_warm_white() -> bool:
	var c := SunPath.light_color(12.0)
	return c.r > 0.9 and c.g > 0.9 and c.b > 0.85


func test_horizon_light_is_warm() -> bool:
	# Just after sunrise the light skews orange: much more red than blue.
	var c := SunPath.light_color(6.5)
	return c.r > c.b


func test_lights_on_at_night_off_at_noon() -> bool:
	return (
		SunPath.lights_on(0.0)
		and SunPath.lights_on(20.0)
		and not SunPath.lights_on(12.0)
		and not SunPath.lights_on(9.0)
	)


func test_ambient_scale_bounded() -> bool:
	var h := 0.0
	while h < 24.0:
		var a := SunPath.ambient_scale(h)
		if a < 0.0 or a > 1.0:
			return false
		h += 0.5
	return SunPath.ambient_scale(12.0) > SunPath.ambient_scale(0.0)
