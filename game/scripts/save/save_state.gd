class_name SaveState
extends RefCounted
## Pure (de)serialization helpers for the save system.
##
## Static functions only, no scene or file access — same testable-core pattern
## as PlayerMotion (docs/ARCHITECTURE.md). Covered by
## tests/unit/test_save_state.gd. All readers take untrusted Variants and fall
## back safely so a corrupt save can never crash the game.

const VERSION: int = 1


## Vector3 -> JSON-safe [x, y, z].
static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## [x, y, z] -> Vector3, or `fallback` when the value is malformed.
static func array_to_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Array:
		return fallback
	var arr: Array = value
	if arr.size() != 3:
		return fallback
	for item in arr:
		if not (item is float or item is int):
			return fallback
	return Vector3(arr[0], arr[1], arr[2])


## Transform3D -> JSON-safe dictionary (origin + basis columns).
static func transform_to_dict(t: Transform3D) -> Dictionary:
	return {
		"origin": vec3_to_array(t.origin),
		"basis_x": vec3_to_array(t.basis.x),
		"basis_y": vec3_to_array(t.basis.y),
		"basis_z": vec3_to_array(t.basis.z),
	}


## Dictionary -> Transform3D, or `fallback` when the value is malformed.
static func dict_to_transform(value: Variant, fallback: Transform3D) -> Transform3D:
	if not value is Dictionary:
		return fallback
	var dict: Dictionary = value
	var basis := Basis(
		array_to_vec3(dict.get("basis_x"), fallback.basis.x),
		array_to_vec3(dict.get("basis_y"), fallback.basis.y),
		array_to_vec3(dict.get("basis_z"), fallback.basis.z)
	)
	return Transform3D(basis, array_to_vec3(dict.get("origin"), fallback.origin))


## Numeric Variant -> float, or `fallback` for anything non-numeric.
static func number_or(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return value
	return fallback


## Assembles a versioned save dictionary from captured sections.
static func build(player: Dictionary, vehicles: Dictionary) -> Dictionary:
	return {"version": VERSION, "player": player, "vehicles": vehicles}


## True iff `data` is a save this code can apply (version + sections present).
static func is_compatible(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var dict: Dictionary = data
	if not (dict.get("player") is Dictionary and dict.get("vehicles") is Dictionary):
		return false
	return number_or(dict.get("version"), -1.0) == float(VERSION)
