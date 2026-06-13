extends RefCounted
## Unit tests for SettingsPanel's pure helpers (see tests/run_tests.gd:
## test_* methods return true to pass). Exercises only the static maths — no
## tree, AudioServer or DisplayServer needed.


func test_volume_zero_is_silent() -> bool:
	return SettingsPanel.volume_to_db(0.0) <= -80.0


func test_volume_full_is_zero_db() -> bool:
	return absf(SettingsPanel.volume_to_db(1.0) - 0.0) < 0.0001


func test_volume_half_is_negative_and_above_floor() -> bool:
	var db := SettingsPanel.volume_to_db(0.5)
	return db < 0.0 and db > -80.0


func test_volume_clamps_above_one() -> bool:
	return absf(SettingsPanel.volume_to_db(9.0) - 0.0) < 0.0001


func test_volume_monotonic() -> bool:
	return SettingsPanel.volume_to_db(0.3) < SettingsPanel.volume_to_db(0.7)


func test_sensitivity_midpoint_is_unity() -> bool:
	return absf(SettingsPanel.sensitivity_to_multiplier(0.5) - 1.0) < 0.0001


func test_sensitivity_min_is_quarter() -> bool:
	return absf(SettingsPanel.sensitivity_to_multiplier(0.0) - 0.25) < 0.0001


func test_sensitivity_max_is_double() -> bool:
	return absf(SettingsPanel.sensitivity_to_multiplier(1.0) - 2.0) < 0.0001


func test_sensitivity_monotonic() -> bool:
	var a := SettingsPanel.sensitivity_to_multiplier(0.2)
	var b := SettingsPanel.sensitivity_to_multiplier(0.8)
	return a < 1.0 and b > 1.0 and a < b


func test_defaults_round_trip_shape() -> bool:
	var d := SettingsPanel.defaults()
	return d.has("volume") and d.has("fullscreen") and d.has("sensitivity") and d.has("graphics")
