extends RefCounted
## Unit tests for Streaming.resolve — the load/unload decision for districts.

const DISTRICTS := [
	{"name": "downtown_la", "offset": Vector2(0, 0)},
	{"name": "hollywood", "offset": Vector2(-7490, -5792)},
]


func test_near_district_loads() -> bool:
	var r := Streaming.resolve(Vector2(100, 100), DISTRICTS, 1500.0, 2200.0, {})
	return r["to_load"].has("downtown_la") and not r["to_load"].has("hollywood")


func test_far_resident_unloads() -> bool:
	var r := Streaming.resolve(Vector2(0, 0), DISTRICTS, 1500.0, 2200.0, {"hollywood": true})
	return r["to_unload"].has("hollywood")


func test_hysteresis_keeps_between_radii() -> bool:
	# A resident district between load and unload radius is neither loaded nor
	# unloaded — it just stays as-is.
	var pos := Vector2(1800, 0)  # 1800 m from downtown: > load(1500), < unload(2200)
	var r := Streaming.resolve(pos, DISTRICTS, 1500.0, 2200.0, {"downtown_la": true})
	return r["to_load"].is_empty() and r["to_unload"].is_empty()


func test_not_resident_in_gap_does_not_load() -> bool:
	var pos := Vector2(1800, 0)
	var r := Streaming.resolve(pos, DISTRICTS, 1500.0, 2200.0, {})
	return not r["to_load"].has("downtown_la")


func test_already_resident_near_is_not_reloaded() -> bool:
	var r := Streaming.resolve(Vector2(0, 0), DISTRICTS, 1500.0, 2200.0, {"downtown_la": true})
	return not r["to_load"].has("downtown_la")
