extends RefCounted
## Unit tests for SaveData (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_round_trip_preserves_values() -> bool:
	var snap := {"health": 72.5, "heat": 4.0, "name": "player"}
	var decoded := SaveData.decode(SaveData.encode(snap))
	return (
		is_equal_approx(decoded.get("health"), 72.5)
		and is_equal_approx(decoded.get("heat"), 4.0)
		and decoded.get("name") == "player"
	)


func test_round_trip_nested_array() -> bool:
	var snap := {"pos": [1.0, 2.0, 3.0]}
	var decoded := SaveData.decode(SaveData.encode(snap))
	var pos: Array = decoded.get("pos")
	return pos.size() == 3 and is_equal_approx(pos[2], 3.0)


func test_encode_embeds_version() -> bool:
	return SaveData.version_of(SaveData.encode({})) == SaveData.VERSION


func test_decode_garbage_is_empty() -> bool:
	return SaveData.decode("not json at all {[").is_empty()


func test_decode_non_object_is_empty() -> bool:
	return SaveData.decode("[1, 2, 3]").is_empty()


func test_decode_missing_data_is_empty() -> bool:
	return SaveData.decode('{"version": 1}').is_empty()


func test_decode_non_dict_data_is_empty() -> bool:
	return SaveData.decode('{"version": 1, "data": 42}').is_empty()


func test_version_of_garbage_is_zero() -> bool:
	return SaveData.version_of("???") == 0


func test_empty_snapshot_round_trips() -> bool:
	return SaveData.decode(SaveData.encode({})).is_empty()


func test_vec3_round_trip() -> bool:
	var v := Vector3(1.5, -2.0, 3.25)
	return SaveData.array_to_vec3(SaveData.vec3_to_array(v), Vector3.ZERO).is_equal_approx(v)


func test_array_to_vec3_rejects_malformed() -> bool:
	var fb := Vector3(9, 9, 9)
	return (
		SaveData.array_to_vec3("nope", fb) == fb
		and SaveData.array_to_vec3([1.0, 2.0], fb) == fb
		and SaveData.array_to_vec3([1.0, 2.0, "x"], fb) == fb
	)


func test_transform_round_trip() -> bool:
	var t := Transform3D(Basis.from_euler(Vector3(0.3, 0.7, -0.2)), Vector3(4, 5, 6))
	var back := SaveData.dict_to_transform(SaveData.transform_to_dict(t), Transform3D.IDENTITY)
	return back.origin.is_equal_approx(t.origin) and back.basis.is_equal_approx(t.basis)


func test_dict_to_transform_rejects_malformed() -> bool:
	var fb := Transform3D(Basis.IDENTITY, Vector3(7, 7, 7))
	return SaveData.dict_to_transform("garbage", fb) == fb


func test_number_or_falls_back() -> bool:
	return (
		is_equal_approx(SaveData.number_or(42.0, 0.0), 42.0)
		and is_equal_approx(SaveData.number_or(3, 0.0), 3.0)
		and is_equal_approx(SaveData.number_or("x", -1.0), -1.0)
		and is_equal_approx(SaveData.number_or(null, -1.0), -1.0)
	)


func test_version_is_two() -> bool:
	return SaveData.VERSION == 2


func test_migrate_v1_fills_new_sections() -> bool:
	var v1 := {"player_pos": [1.0, 2.0, 3.0], "health": {"hp": 50.0}}
	var migrated := SaveData.migrate(v1, 1)
	return (
		migrated.get("stats") is Dictionary
		and (migrated["stats"] as Dictionary).is_empty()
		and migrated.get("progression") is Dictionary
		and migrated.get("properties") is Dictionary
		and migrated["player_pos"] == v1["player_pos"]
		and migrated["health"] == v1["health"]
	)


func test_migrate_current_version_is_untouched() -> bool:
	var v2 := {"stats": {"money": 900}, "vehicles": {}}
	var migrated := SaveData.migrate(v2, SaveData.VERSION)
	return migrated == v2


func test_migrate_does_not_mutate_input() -> bool:
	var v1 := {"health": {"hp": 10.0}}
	SaveData.migrate(v1, 1)
	return not v1.has("stats")


func test_migrate_preserves_existing_sections_from_v1() -> bool:
	# A hand-edited or future-mixed save with a stats dict keeps it verbatim.
	var odd := {"stats": {"money": 123}}
	var migrated := SaveData.migrate(odd, 1)
	return int((migrated["stats"] as Dictionary).get("money", 0)) == 123
