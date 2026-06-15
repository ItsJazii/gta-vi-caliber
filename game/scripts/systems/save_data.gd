class_name SaveData
extends RefCounted
## Pure (de)serialization for a save snapshot.
##
## No file or scene access — SaveManager gathers a plain Dictionary of game
## state, this wraps it with a version and turns it to/from JSON text, and the
## round-trip + malformed-input handling is unit-tested (tests/unit/
## test_save_data.gd). Decode never throws: bad input yields an empty snapshot.

## v2 added stats (money/armor), progression XP, property ownership and
## boat/bike vehicle entries on top of v1's position/health/wanted/cars.
## v3 added lifetime/100%-completion stats as a separate section from the
## player wallet/armor "stats" payload.
## v4 added activity-based player skills.
const VERSION: int = 4


## Wrap a state snapshot with a version header and serialise to JSON text.
static func encode(snapshot: Dictionary) -> String:
	return JSON.stringify({"version": VERSION, "data": snapshot})


## Bring an older snapshot up to the current shape. v1 saves predate the
## stats/progression/properties keys — they're normalised to empty dictionaries
## (every restore() treats {} as "no saved data"), so a v1 save loads cleanly
## instead of being rejected. Unknown future versions pass through untouched
## (best effort). Pure: returns a new Dictionary.
static func migrate(snapshot: Dictionary, from_version: int) -> Dictionary:
	# A failed/empty decode ({}) must stay empty: otherwise the v1->v2 section-fill
	# below turns it into {stats:{}, progression:{}, properties:{}} — NON-empty —
	# which slips past SaveManager.load_game's `if snapshot.is_empty(): return`
	# guard and runs restore({}) on every tracker, silently wiping stats and
	# progression XP from a corrupt or empty old-version save.
	if snapshot.is_empty():
		return {}
	var out := snapshot.duplicate(true)
	if from_version < 2:
		for key in ["stats", "progression", "properties"]:
			if not out.get(key) is Dictionary:
				out[key] = {}
	if from_version < 3 and not out.get("lifetime_stats") is Dictionary:
		out["lifetime_stats"] = {}
	if from_version < 4 and not out.get("player_skills") is Dictionary:
		out["player_skills"] = {}
	return out


## Parse save text back to the inner snapshot. Returns {} for anything that
## isn't a versioned object with a Dictionary payload, so callers can trust the
## shape without try/catch.
static func decode(text: String) -> Dictionary:
	var parsed: Variant = _parse(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Variant = (parsed as Dictionary).get("data")
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


## The format version embedded in save text, or 0 if absent/unparseable. Lets a
## loader migrate or reject old saves.
static func version_of(text: String) -> int:
	var parsed: Variant = _parse(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	return int((parsed as Dictionary).get("version", 0))


## Parse JSON without the global ERROR log that JSON.parse_string pushes on bad
## input. Empty/missing/old save text is a normal path here (callers fall back
## to {} / 0), so it must stay silent instead of spamming hard errors.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	if text.strip_edges().is_empty() or json.parse(text) != OK:
		return null
	return json.data


## Vector3 -> JSON-safe [x, y, z].
static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## [x, y, z] -> Vector3, or `fallback` when the value is malformed. Takes an
## untrusted Variant so a corrupt save can never crash a loader.
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
