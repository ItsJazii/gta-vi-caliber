extends RefCounted
## Focused tests for WeatherEffects visibility helpers. Split from
## test_weather_effects.gd to keep each legacy suite under the lint method cap.


func test_fog_level_blends_cloud_and_rain() -> bool:
	var cloudy := WeatherEffects.fog_level(0.6, 0.0)
	var rainy := WeatherEffects.fog_level(0.6, 1.0)
	return rainy > cloudy and rainy <= 1.0 and is_equal_approx(cloudy, 0.6)


func test_fog_level_clamps_inputs() -> bool:
	return (
		is_equal_approx(WeatherEffects.fog_level(-2.0, -1.0), 0.0)
		and is_equal_approx(WeatherEffects.fog_level(9.0, 9.0), 1.0)
	)


func test_ai_sight_range_uses_weather_multiplier() -> bool:
	var clear := WeatherEffects.ai_sight_range(45.0, 0.0, 0.0)
	var storm := WeatherEffects.ai_sight_range(45.0, 1.0, 1.0)
	return is_equal_approx(clear, 45.0) and storm < clear and is_equal_approx(storm, 13.5)


func test_ai_sight_range_has_floor() -> bool:
	return is_equal_approx(WeatherEffects.ai_sight_range(-10.0, 1.0, 1.0), 5.0)
