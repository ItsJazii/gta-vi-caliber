class_name TestSaveGame
extends GdUnitTestSuite
## Unit tests for SaveGame — versioned serialize/load round-trips.

const SAMPLE := {
	"player_pos": [12.5, 1.0, -300.0],
	"time_of_day": 14.25,
	"wanted_heat": 3.0,
	"missions": {"welcome_to_la": {"done": ["a"], "state": "active"}},
}


func test_round_trip_preserves_state() -> void:
	var text := SaveGame.serialize(SAMPLE)
	var back := SaveGame.deserialize(text)
	assert_bool(back["time_of_day"] == 14.25 and back["player_pos"][0] == 12.5).is_true()


func test_nested_data_survives() -> void:
	var back := SaveGame.deserialize(SaveGame.serialize(SAMPLE))
	assert_bool(back["missions"]["welcome_to_la"]["done"] == ["a"]).is_true()


func test_bad_json_returns_empty() -> void:
	assert_bool(SaveGame.deserialize("{not valid").is_empty()).is_true()


func test_wrong_version_rejected() -> void:
	var forged := JSON.stringify({"version": 999, "state": {"x": 1}})
	assert_bool(SaveGame.deserialize(forged).is_empty()).is_true()


func test_missing_state_rejected() -> void:
	assert_bool(SaveGame.deserialize(JSON.stringify({"version": 1})).is_empty()).is_true()


func test_write_then_read_round_trips() -> void:
	var path := "user://test_save_tmp.json"
	var ok := SaveGame.write(SAMPLE, path)
	var back := SaveGame.read(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_bool(ok and back.get("wanted_heat", -1.0) == 3.0).is_true()


func test_read_missing_file_is_empty() -> void:
	assert_bool(SaveGame.read("user://does_not_exist_42.json").is_empty()).is_true()
