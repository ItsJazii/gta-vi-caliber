extends RefCounted
## Unit tests for WeatherState — the weather front model. The shape of a front
## (clear → overcast → rain → clearing) and the lagging wetness are what matter.


func test_front_opens_and_closes_clear() -> bool:
	# Start and end of the cycle are rain-free, low cloud.
	var a := WeatherState.front_targets(0.0)
	var b := WeatherState.front_targets(0.99)
	return float(a["rain"]) < 0.01 and float(b["rain"]) < 0.2


func test_front_builds_overcast_before_rain() -> bool:
	# Around the 0.4 mark the sky is heavily clouded but not yet raining.
	var t := WeatherState.front_targets(0.45)
	return float(t["cloud"]) > 0.6 and float(t["rain"]) < 0.2


func test_front_rains_in_the_band() -> bool:
	# Peak of the rain window (~0.625) is a downpour under full cloud.
	var t := WeatherState.front_targets(0.625)
	return float(t["rain"]) > 0.9 and float(t["cloud"]) > 0.9


func test_front_wraps() -> bool:
	var a := WeatherState.front_targets(0.3)
	var b := WeatherState.front_targets(1.3)
	return absf(float(a["cloud"]) - float(b["cloud"])) < 0.001


func test_step_eases_toward_targets() -> bool:
	var w := WeatherState.new()
	for _i in 200:
		w.step(0.1, 1.0, 0.0)  # 20s easing toward full overcast
	return w.cloudiness > 0.95


func test_rain_wets_surfaces() -> bool:
	var w := WeatherState.new()
	w.rain = 1.0
	w.step(1.0, 1.0, 1.0)
	return w.wetness > 0.0


func test_surfaces_dry_after_rain() -> bool:
	var w := WeatherState.new()
	w.wetness = 1.0
	w.rain = 0.0
	w.step(2.0, 0.0, 0.0)  # no rain -> drying
	return w.wetness < 1.0


func test_wetness_clamped() -> bool:
	var w := WeatherState.new()
	w.rain = 1.0
	for _i in 500:
		w.step(0.1, 1.0, 1.0)
	return w.wetness <= 1.0


func test_labels_track_conditions() -> bool:
	var clear := WeatherState.new()
	var storm := WeatherState.new()
	storm.cloudiness = 1.0
	storm.rain = 0.8
	var grey := WeatherState.new()
	grey.cloudiness = 0.8
	return clear.label() == "clear" and storm.label() == "rain" and grey.label() == "overcast"


func test_sky_cloud_coverage_spans_clear_to_storm() -> bool:
	# Clear keeps a few fair-weather clouds; a storm never becomes a solid slab.
	var clear := WeatherState.sky_cloud_coverage(0.0)
	var storm := WeatherState.sky_cloud_coverage(1.0)
	return clear > 0.05 and clear < 0.35 and storm > 0.85 and storm < 1.0


func test_sky_cloud_coverage_is_monotonic_and_clamped() -> bool:
	var low := WeatherState.sky_cloud_coverage(0.2)
	var high := WeatherState.sky_cloud_coverage(0.8)
	var below := WeatherState.sky_cloud_coverage(-5.0)
	var above := WeatherState.sky_cloud_coverage(5.0)
	var monotonic := high > low
	var clamped := (
		absf(below - WeatherState.sky_cloud_coverage(0.0)) < 0.001
		and absf(above - WeatherState.sky_cloud_coverage(1.0)) < 0.001
	)
	return monotonic and clamped


func test_storm_darkness_fair_weather_stays_bright() -> bool:
	# Below the overcast threshold the sky keeps its full brightness.
	return (
		is_equal_approx(WeatherState.sky_storm_darkness(0.0), 0.0)
		and is_equal_approx(WeatherState.sky_storm_darkness(0.3), 0.0)
	)


func test_storm_darkness_builds_to_charcoal_cap() -> bool:
	var mid := WeatherState.sky_storm_darkness(0.7)
	var full := WeatherState.sky_storm_darkness(1.0)
	var beyond := WeatherState.sky_storm_darkness(9.0)
	return (
		mid > 0.1 and mid < full and is_equal_approx(full, 0.85) and is_equal_approx(beyond, full)
	)


func test_sun_dim_clear_is_full_strength() -> bool:
	return (
		is_equal_approx(WeatherState.sun_dim_factor(0.0), 1.0)
		and is_equal_approx(WeatherState.sun_dim_factor(0.3), 1.0)
	)


func test_sun_dim_storm_drops_toward_floor() -> bool:
	var mid := WeatherState.sun_dim_factor(0.7)
	var full := WeatherState.sun_dim_factor(1.0)
	return mid < 1.0 and mid > full and is_equal_approx(full, 0.35)
