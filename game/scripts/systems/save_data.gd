class_name SaveData
extends RefCounted
## Pure (de)serialization for a save snapshot.
##
## No file or scene access — SaveManager gathers a plain Dictionary of game
## state, this wraps it with a version and turns it to/from JSON text, and the
## round-trip + malformed-input handling is unit-tested (tests/unit/
## test_save_data.gd). Decode never throws: bad input yields an empty snapshot.

const VERSION: int = 1


## Vector3 -> JSON-safe [x, y, z].
static func vec3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


## [x, y, z] -> Vector3, or `fallback` when the value is malformed.
static func array_to_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Array:
		return fallback
	var values: Array = value
	if values.size() != 3:
		return fallback
	for item in values:
		if not (item is float or item is int):
			return fallback
	return Vector3(values[0], values[1], values[2])


## Transform3D -> JSON-safe dictionary (origin + basis columns).
static func transform_to_dict(value: Transform3D) -> Dictionary:
	return {
		"origin": vec3_to_array(value.origin),
		"basis_x": vec3_to_array(value.basis.x),
		"basis_y": vec3_to_array(value.basis.y),
		"basis_z": vec3_to_array(value.basis.z),
	}


## Dictionary -> Transform3D, or `fallback` when the value is malformed.
static func dict_to_transform(value: Variant, fallback: Transform3D) -> Transform3D:
	if not value is Dictionary:
		return fallback
	var data: Dictionary = value
	var basis := Basis(
		array_to_vec3(data.get("basis_x"), fallback.basis.x),
		array_to_vec3(data.get("basis_y"), fallback.basis.y),
		array_to_vec3(data.get("basis_z"), fallback.basis.z)
	)
	return Transform3D(basis, array_to_vec3(data.get("origin"), fallback.origin))


## Numeric Variant -> float, or `fallback` for anything non-numeric.
static func number_or(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return value
	return fallback


## Wrap a state snapshot with a version header and serialise to JSON text.
static func encode(snapshot: Dictionary) -> String:
	return JSON.stringify({"version": VERSION, "data": snapshot})


## Parse save text back to the inner snapshot. Returns {} for anything that
## isn't a versioned object with a Dictionary payload, so callers can trust the
## shape without try/catch.
static func decode(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Variant = (parsed as Dictionary).get("data")
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


## The format version embedded in save text, or 0 if absent/unparseable. Lets a
## loader migrate or reject old saves.
static func version_of(text: String) -> int:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	return int((parsed as Dictionary).get("version", 0))
