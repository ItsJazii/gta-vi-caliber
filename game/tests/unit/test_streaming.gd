class_name TestStreaming
extends GdUnitTestSuite
## Unit tests for Streaming.resolve — the load/unload decision for districts.

const DISTRICTS := [
	{"name": "downtown_la", "offset": Vector2(0, 0)},
	{"name": "hollywood", "offset": Vector2(-7490, -5792)},
]


func test_near_district_loads() -> void:
	var r := Streaming.resolve(Vector2(100, 100), DISTRICTS, 1500.0, 2200.0, {})
	assert_bool(r["to_load"].has("downtown_la")).is_true()
	assert_bool(r["to_load"].has("hollywood")).is_false()


func test_multiple_loads_are_nearest_first() -> void:
	var districts := [
		{"name": "far", "offset": Vector2(1000, 0)},
		{"name": "near", "offset": Vector2(100, 0)},
		{"name": "mid", "offset": Vector2(500, 0)},
	]
	var r := Streaming.resolve(Vector2.ZERO, districts, 1500.0, 2200.0, {})
	assert_bool(r["to_load"] == ["near", "mid", "far"]).is_true()


func test_far_resident_unloads() -> void:
	var r := Streaming.resolve(Vector2(0, 0), DISTRICTS, 1500.0, 2200.0, {"hollywood": true})
	assert_bool(r["to_unload"].has("hollywood")).is_true()


func test_hysteresis_keeps_between_radii() -> void:
	# A resident district between load and unload radius is neither loaded nor
	# unloaded — it just stays as-is.
	var pos := Vector2(1800, 0)  # 1800 m from downtown: > load(1500), < unload(2200)
	var r := Streaming.resolve(pos, DISTRICTS, 1500.0, 2200.0, {"downtown_la": true})
	assert_bool(r["to_load"].is_empty()).is_true()
	assert_bool(r["to_unload"].is_empty()).is_true()


func test_not_resident_in_gap_does_not_load() -> void:
	var pos := Vector2(1800, 0)
	var r := Streaming.resolve(pos, DISTRICTS, 1500.0, 2200.0, {})
	assert_bool(r["to_load"].has("downtown_la")).is_false()


func test_already_resident_near_is_not_reloaded() -> void:
	var r := Streaming.resolve(Vector2(0, 0), DISTRICTS, 1500.0, 2200.0, {"downtown_la": true})
	assert_bool(r["to_load"].has("downtown_la")).is_false()


func test_load_batch_caps_work_and_keeps_order() -> void:
	assert_bool(Streaming.load_batch(["near", "mid", "far"], 1) == ["near"]).is_true()


func test_load_batch_handles_zero_budget() -> void:
	assert_bool(Streaming.load_batch(["near"], 0).is_empty()).is_true()
