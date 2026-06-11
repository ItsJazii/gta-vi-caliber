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


func test_vec3_round_trips() -> bool:
	var value := Vector3(1.5, -2.25, 38.0)
	return SaveData.array_to_vec3(SaveData.vec3_to_array(value), Vector3.ZERO) == value


func test_vec3_rejects_malformed_values() -> bool:
	return (
		SaveData.array_to_vec3("nope", Vector3.ONE) == Vector3.ONE
		and SaveData.array_to_vec3([1.0, 2.0], Vector3.ONE) == Vector3.ONE
		and SaveData.array_to_vec3([1.0, "two", 3.0], Vector3.ONE) == Vector3.ONE
	)


func test_transform_round_trips() -> bool:
	var value := Transform3D(Basis().rotated(Vector3.UP, 0.7), Vector3(4.0, 0.6, -5.0))
	var restored := SaveData.dict_to_transform(SaveData.transform_to_dict(value), Transform3D())
	return restored.is_equal_approx(value)


func test_transform_rejects_garbage() -> bool:
	var fallback := Transform3D(Basis(), Vector3(9.0, 0.6, 5.0))
	return SaveData.dict_to_transform(42, fallback) == fallback


func test_number_or_accepts_int_and_float() -> bool:
	return SaveData.number_or(3, 0.0) == 3.0 and SaveData.number_or(2.5, 0.0) == 2.5


func test_number_or_rejects_non_numeric() -> bool:
	return SaveData.number_or(null, 7.0) == 7.0 and SaveData.number_or("90", 7.0) == 7.0
