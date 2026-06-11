extends RefCounted
## Unit tests for HudFormat pure helpers (see tests/run_tests.gd contract).


func test_clock_formats_morning() -> bool:
	return HudFormat.format_clock(9.5) == "09:30"


func test_clock_formats_midnight() -> bool:
	return HudFormat.format_clock(0.0) == "00:00"


func test_clock_wraps_past_24() -> bool:
	return HudFormat.format_clock(25.0) == "01:00"


func test_clock_quarter_hour() -> bool:
	return HudFormat.format_clock(14.25) == "14:15"


func test_day_phase_buckets() -> bool:
	return (
		HudFormat.day_phase(2.0) == "Night"
		and HudFormat.day_phase(6.0) == "Dawn"
		and HudFormat.day_phase(12.0) == "Day"
		and HudFormat.day_phase(19.0) == "Dusk"
		and HudFormat.day_phase(23.0) == "Night"
	)


func test_money_basic() -> bool:
	return HudFormat.format_money(0) == "$0"


func test_money_thousands() -> bool:
	return HudFormat.format_money(1500) == "$1,500"


func test_money_millions() -> bool:
	return HudFormat.format_money(1234567) == "$1,234,567"


func test_money_negative() -> bool:
	return HudFormat.format_money(-250) == "-$250"


func test_distance_metres() -> bool:
	return HudFormat.format_distance(450.0) == "450m"


func test_distance_kilometres() -> bool:
	return HudFormat.format_distance(2500.0) == "2.5km"


func test_compass_cardinals() -> bool:
	return (
		HudFormat.compass_8(Vector2(0, -1)) == "N"
		and HudFormat.compass_8(Vector2(1, 0)) == "E"
		and HudFormat.compass_8(Vector2(0, 1)) == "S"
		and HudFormat.compass_8(Vector2(-1, 0)) == "W"
	)


func test_world_to_map_forward_is_up() -> bool:
	var p := HudFormat.world_to_map(Vector2(0, 10), Vector2(0, 1), 2.0)
	return absf(p.x) < 0.0001 and absf(p.y - (-20.0)) < 0.0001


func test_world_to_map_right_is_screen_right() -> bool:
	var p := HudFormat.world_to_map(Vector2(10, 0), Vector2(0, 1), 2.0)
	return absf(p.x - 20.0) < 0.0001 and absf(p.y) < 0.0001


func test_world_to_map_zero_forward_safe() -> bool:
	var p := HudFormat.world_to_map(Vector2(5, 5), Vector2.ZERO, 1.0)
	return p.is_finite()


func test_wheel_slot_top_is_zero() -> bool:
	return HudFormat.wheel_slot(Vector2(0, -100), 4, 36.0) == 0


func test_wheel_slot_right_is_quarter() -> bool:
	return HudFormat.wheel_slot(Vector2(100, 0), 4, 36.0) == 1


func test_wheel_slot_dead_zone() -> bool:
	return HudFormat.wheel_slot(Vector2(5, 5), 4, 36.0) == -1


func test_wheel_slot_angle_spacing() -> bool:
	return absf(HudFormat.wheel_slot_angle(1, 4) - (TAU / 4.0)) < 0.0001
