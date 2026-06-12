class_name GangTerritory
extends RefCounted
## Pure gang turf-control model — districts owned by gangs, with a 0..1 player
## influence level that rises as fights are won there and falls when contested.
##
## No nodes, no scene access: a world controller owns one and feeds it fight
## results, so the influence/takeover curve is unit-tested headless
## (tests/unit/test_gang_territory.gd). Each district is a Dictionary
## {id, owner, influence}; takeover flips owner to "player" once influence is full.

## Owner string for districts the player has captured.
const PLAYER_OWNER: String = "player"

## id -> {owner: String, influence: float}. Built once in _init, insertion-ordered.
var _districts: Dictionary = {}


func _init(districts: Array = []) -> void:
	var source: Array = districts if not districts.is_empty() else default_districts()
	for entry: Variant in source:
		_register(entry)


## The built-in turf map used when an empty list is passed: a few Vice City
## districts each held by a rival gang, player influence starting at zero.
static func default_districts() -> Array:
	return [
		{"id": "downtown", "owner": "vice_kings"},
		{"id": "beach", "owner": "los_santos_set"},
		{"id": "docks", "owner": "marina_cartel"},
		{"id": "little_havana", "owner": "vice_kings"},
	]


func district_count() -> int:
	return _districts.size()


## True if the district id exists in the turf map.
func has_district(district_id: String) -> bool:
	return _districts.has(district_id)


## Owner gang id of a district, or "" if the id is unknown.
func owner_of(district_id: String) -> String:
	if not _districts.has(district_id):
		return ""
	return _districts[district_id]["owner"]


## Current 0..1 player influence in a district, or 0 if the id is unknown.
func influence_in(district_id: String) -> float:
	if not _districts.has(district_id):
		return 0.0
	return _districts[district_id]["influence"]


## Winning a fight / clearing a wave raises player influence (clamped 0..1).
## Negative amounts and unknown districts are no-ops.
func add_influence(district_id: String, amount: float) -> void:
	if not _districts.has(district_id) or amount <= 0.0:
		return
	_set_influence(district_id, influence_in(district_id) + amount)


## Decay / contested loss lowers player influence (floored at 0). Negative
## amounts and unknown districts are no-ops.
func lose_influence(district_id: String, amount: float) -> void:
	if not _districts.has(district_id) or amount <= 0.0:
		return
	_set_influence(district_id, influence_in(district_id) - amount)


## True when player influence is above the fight-back threshold (gangs start
## pushing back). Unknown districts are never contested.
func is_contested(district_id: String, threshold: float) -> bool:
	return influence_in(district_id) > threshold


## Capture a district: succeeds only at full influence (>= 1.0), flipping the
## owner to "player". Returns whether the owner actually flipped.
func take_over(district_id: String) -> bool:
	if not _districts.has(district_id):
		return false
	if influence_in(district_id) < 1.0:
		return false
	if _districts[district_id]["owner"] == PLAYER_OWNER:
		return false
	_districts[district_id]["owner"] = PLAYER_OWNER
	return true


## Every district id the player owns (empty Array if none).
func player_districts() -> Array:
	var out: Array = []
	for id: Variant in _districts:
		if _districts[id]["owner"] == PLAYER_OWNER:
			out.append(id)
	return out


## Fraction (0..1) of all districts the player owns; 0 when there are none.
func controlled_fraction() -> float:
	if _districts.is_empty():
		return 0.0
	return float(player_districts().size()) / float(_districts.size())


## True only when the player owns every district (false with no districts).
func all_owned() -> bool:
	return not _districts.is_empty() and player_districts().size() == _districts.size()


## Snapshot for save_data: a list of {id, owner, influence}, insertion-ordered.
func serialize() -> Dictionary:
	var out: Array = []
	for id: Variant in _districts:
		(
			out
			. append(
				{
					"id": id,
					"owner": _districts[id]["owner"],
					"home_owner": _districts[id]["home_owner"],
					"influence": _districts[id]["influence"],
				}
			)
		)
	return {"districts": out}


## Rebuild from a serialize() snapshot. Malformed input leaves an empty map.
func restore(data: Dictionary) -> void:
	_districts = {}
	var stored: Variant = data.get("districts")
	if typeof(stored) != TYPE_ARRAY:
		return
	for entry: Variant in stored:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_register(entry)
		var id: String = str((entry as Dictionary).get("id", ""))
		if _districts.has(id):
			_set_influence(id, float((entry as Dictionary).get("influence", 0.0)))


## Reset every district back to zero player influence and its original gang owner.
func reset() -> void:
	for id: Variant in _districts:
		_districts[id]["owner"] = _districts[id]["home_owner"]
		_districts[id]["influence"] = 0.0


## Register one {id, owner} (optionally influence) entry, dropping garbage.
func _register(entry: Variant) -> void:
	if typeof(entry) != TYPE_DICTIONARY:
		return
	var dict: Dictionary = entry
	var id: String = str(dict.get("id", ""))
	if id.is_empty() or _districts.has(id):
		return
	var owner: String = str(dict.get("owner", ""))
	_districts[id] = {
		"owner": owner,
		"home_owner": str(dict.get("home_owner", owner)),
		"influence": clampf(float(dict.get("influence", 0.0)), 0.0, 1.0),
	}


## Write a district's influence, clamped to 0..1.
func _set_influence(district_id: String, value: float) -> void:
	_districts[district_id]["influence"] = clampf(value, 0.0, 1.0)
