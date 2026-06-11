extends RefCounted
## Unit tests for NpcSchedule — the daily-routine lookup. Midnight wrapping and
## gap-fallback are the tricky parts, so they get the most coverage.

var _day := [
	{"start": 6.0, "end": 9.0, "activity": "commute", "place": "street"},
	{"start": 9.0, "end": 17.0, "activity": "work", "place": "office"},
	{"start": 17.0, "end": 22.0, "activity": "leisure", "place": "bar"},
	{"start": 22.0, "end": 6.0, "activity": "sleep", "place": "home"},
]


func test_wrap_hour_normalises() -> bool:
	return NpcSchedule.wrap_hour(26.0) == 2.0 and NpcSchedule.wrap_hour(-1.0) == 23.0


func test_block_covers_simple_range() -> bool:
	var b := {"start": 9.0, "end": 17.0}
	return (
		NpcSchedule.block_covers(b, 12.0)
		and not NpcSchedule.block_covers(b, 17.0)
		and not NpcSchedule.block_covers(b, 8.0)
	)


func test_block_covers_wrapping_range() -> bool:
	var b := {"start": 22.0, "end": 6.0}
	return (
		NpcSchedule.block_covers(b, 23.0)
		and NpcSchedule.block_covers(b, 2.0)
		and not NpcSchedule.block_covers(b, 12.0)
	)


func test_activity_at_picks_right_block() -> bool:
	return (
		NpcSchedule.activity_at(_day, 10.0)["activity"] == "work"
		and NpcSchedule.activity_at(_day, 3.0)["activity"] == "sleep"
		and NpcSchedule.activity_at(_day, 19.0)["activity"] == "leisure"
	)


func test_activity_at_falls_back_to_idle() -> bool:
	var sparse := [{"start": 9.0, "end": 10.0, "activity": "blink", "place": "void"}]
	return NpcSchedule.activity_at(sparse, 15.0)["activity"] == "loiter"


func test_hours_until_end_simple() -> bool:
	var b := {"start": 9.0, "end": 17.0}
	return absf(NpcSchedule.hours_until_end(b, 16.5) - 0.5) < 0.001


func test_hours_until_end_wraps() -> bool:
	var b := {"start": 22.0, "end": 6.0}
	# At 23:00, sleep ends at 06:00 -> 7 hours away.
	return absf(NpcSchedule.hours_until_end(b, 23.0) - 7.0) < 0.001
