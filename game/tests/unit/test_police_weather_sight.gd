extends RefCounted
## Police sight should consume the live WeatherController levels through the
## WeatherEffects math: storms shorten spotting range, clear weather stays
## neutral, and missing weather keeps old behaviour.


class FakeWeather:
	extends Node

	var wet: float = 0.0
	var fog: float = 0.0

	func wetness() -> float:
		return wet

	func gameplay_fog() -> float:
		return fog


func test_clear_weather_keeps_base_sight() -> bool:
	var weather := FakeWeather.new()
	var result := is_equal_approx(Police.weather_adjusted_sight_range(45.0, weather), 45.0)
	weather.free()
	return result


func test_storm_weather_shortens_sight() -> bool:
	var weather := FakeWeather.new()
	weather.wet = 1.0
	weather.fog = 1.0
	var result := is_equal_approx(Police.weather_adjusted_sight_range(45.0, weather), 13.5)
	weather.free()
	return result


func test_missing_weather_keeps_base_sight() -> bool:
	return is_equal_approx(Police.weather_adjusted_sight_range(45.0, null), 45.0)


func test_bad_base_range_uses_visibility_floor() -> bool:
	var weather := FakeWeather.new()
	weather.wet = 1.0
	weather.fog = 1.0
	var result := is_equal_approx(Police.weather_adjusted_sight_range(-10.0, weather), 5.0)
	weather.free()
	return result
