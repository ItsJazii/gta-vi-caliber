extends RefCounted
## Unit tests for SaveState (runner contract: test_* methods return true).


func test_vec3_round_trips() -> bool:
	var v := Vector3(1.5, -2.25, 38.0)
	return SaveState.array_to_vec3(SaveState.vec3_to_array(v), Vector3.ZERO) == v


func test_vec3_rejects_non_array() -> bool:
	return SaveState.array_to_vec3("nope", Vector3.ONE) == Vector3.ONE


func test_vec3_rejects_wrong_size() -> bool:
	return SaveState.array_to_vec3([1.0, 2.0], Vector3.ONE) == Vector3.ONE


func test_vec3_rejects_non_numeric_items() -> bool:
	return SaveState.array_to_vec3([1.0, "two", 3.0], Vector3.ONE) == Vector3.ONE


func test_transform_round_trips() -> bool:
	var t := Transform3D(Basis().rotated(Vector3.UP, 0.7), Vector3(4.0, 0.6, -5.0))
	var restored := SaveState.dict_to_transform(SaveState.transform_to_dict(t), Transform3D())
	return restored.is_equal_approx(t)


func test_transform_rejects_garbage() -> bool:
	var fallback := Transform3D(Basis(), Vector3(9.0, 0.6, 5.0))
	return SaveState.dict_to_transform(42, fallback) == fallback


func test_number_or_accepts_int_and_float() -> bool:
	return SaveState.number_or(3, 0.0) == 3.0 and SaveState.number_or(2.5, 0.0) == 2.5


func test_number_or_rejects_non_numeric() -> bool:
	return SaveState.number_or(null, 7.0) == 7.0 and SaveState.number_or("90", 7.0) == 7.0


func test_build_is_compatible() -> bool:
	return SaveState.is_compatible(SaveState.build({}, {}))


func test_incompatible_when_not_dictionary() -> bool:
	return not SaveState.is_compatible([1, 2, 3])


func test_incompatible_when_version_differs() -> bool:
	var data := SaveState.build({}, {})
	data["version"] = SaveState.VERSION + 1
	return not SaveState.is_compatible(data)


func test_incompatible_when_sections_missing() -> bool:
	return not SaveState.is_compatible({"version": SaveState.VERSION})


func test_survives_json_round_trip() -> bool:
	var data := SaveState.build({"position": SaveState.vec3_to_array(Vector3(1.0, 2.0, 3.0))}, {})
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if not SaveState.is_compatible(parsed):
		return false
	var position: Variant = parsed["player"]["position"]
	return SaveState.array_to_vec3(position, Vector3.ZERO) == Vector3(1.0, 2.0, 3.0)
