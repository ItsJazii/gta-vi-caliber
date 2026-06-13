class_name DistrictEconomy
extends RefCounted
## Pure living real-estate model — each district carries a desirability that the
## world moves: taking over turf (player influence) and investing in local
## businesses lift it, while recent crime heat drags it down. Desirability scales
## property values and passive income on top of PropertyOwnership's flat
## catalogue, and the district ids line up with GangTerritory so a caller can feed
## influence_in() straight into set_control() — a neighbourhood you've cleaned up
## and invested in becomes worth more.
##
## No nodes, no scene access: a world controller owns one and feeds it turf/crime
## signals, so the desirability curve stays unit-tested headless
## (tests/unit/test_district_economy.gd).
##
## Each district is a Dictionary {id, base}; base is its baseline desirability
## index (a premium beach district starts higher than the docks). Malformed
## entries (missing/empty id, non-positive base) are dropped at construction.

## Desirability shift per unit of player control (turf cleaned up).
const CONTROL_WEIGHT: float = 0.3
## Desirability shift per owned local business, up to INVEST_CAP businesses.
const INVEST_WEIGHT: float = 0.1
const INVEST_CAP: int = 3
## Desirability drop at full crime heat.
const HEAT_WEIGHT: float = 0.4
## Desirability is clamped to this band.
const DESIR_MIN: float = 0.4
const DESIR_MAX: float = 2.0

## id -> {base: float, control: float[0,1], heat: float[0,1], investment: int>=0}.
var _districts: Dictionary = {}


func _init(districts: Array = []) -> void:
	var source: Array = districts if not districts.is_empty() else default_districts()
	for entry: Variant in source:
		_register(entry)


## Built-in roster, ids aligned with GangTerritory.default_districts() so turf and
## real-estate share one set of neighbourhoods.
static func default_districts() -> Array:
	return [
		{"id": "downtown", "base": 1.2},
		{"id": "beach", "base": 1.4},
		{"id": "docks", "base": 0.7},
		{"id": "little_havana", "base": 0.9},
	]


func district_count() -> int:
	return _districts.size()


## True if the district id exists.
func has_district(id: String) -> bool:
	return _districts.has(id)


## Every district id, in first-seen order.
func ids() -> Array:
	return _districts.keys()


## Baseline desirability index of a district, or -1.0 if unknown.
func base_index(id: String) -> float:
	if not _districts.has(id):
		return -1.0
	return _districts[id]["base"]


## Player control in [0, 1] (0.0 if unknown).
func control_in(id: String) -> float:
	if not _districts.has(id):
		return 0.0
	return _districts[id]["control"]


## Crime heat in [0, 1] (0.0 if unknown).
func heat_in(id: String) -> float:
	if not _districts.has(id):
		return 0.0
	return _districts[id]["heat"]


## Owned local businesses in the district (0 if unknown).
func investment_in(id: String) -> int:
	if not _districts.has(id):
		return 0
	return _districts[id]["investment"]


## Current desirability multiplier: base + control & investment bonuses - heat
## penalty, clamped to the band. 1.0 (neutral) for an unknown district.
func desirability(id: String) -> float:
	if not _districts.has(id):
		return 1.0
	var d: Dictionary = _districts[id]
	var invest_bonus := INVEST_WEIGHT * float(mini(d["investment"], INVEST_CAP))
	var raw: float = (
		d["base"] + CONTROL_WEIGHT * d["control"] + invest_bonus - HEAT_WEIGHT * d["heat"]
	)
	return clampf(raw, DESIR_MIN, DESIR_MAX)


## A base price adjusted for the district's desirability, rounded to whole money.
func property_value(base_price: int, id: String) -> int:
	return int(round(float(base_price) * desirability(id)))


## Multiplier a caller applies to a property's passive income in this district.
func income_multiplier(id: String) -> float:
	return desirability(id)


## Set player control directly (e.g. from GangTerritory.influence_in), clamped to
## [0, 1]. No-op for an unknown district.
func set_control(id: String, value: float) -> void:
	if _districts.has(id):
		_districts[id]["control"] = clampf(value, 0.0, 1.0)


## Add crime heat (a fresh crime in the district), clamped to [0, 1]. No-op for an
## unknown district or non-positive amount.
func add_heat(id: String, amount: float) -> void:
	if _districts.has(id) and amount > 0.0:
		_districts[id]["heat"] = clampf(_districts[id]["heat"] + amount, 0.0, 1.0)


## Bleed crime heat off one district over time, floored at 0. No-op for an unknown
## district or non-positive amount.
func decay_heat(id: String, amount: float) -> void:
	if _districts.has(id) and amount > 0.0:
		_districts[id]["heat"] = maxf(_districts[id]["heat"] - amount, 0.0)


## Bleed heat off every district at once (one world tick).
func decay_all_heat(amount: float) -> void:
	for id: Variant in _districts:
		decay_heat(id, amount)


## Open a local business in the district (raises desirability up to the cap).
## No-op for an unknown district.
func invest(id: String) -> void:
	if _districts.has(id):
		_districts[id]["investment"] += 1


## Close a local business (floored at 0). No-op for an unknown district.
func divest(id: String) -> void:
	if _districts.has(id):
		_districts[id]["investment"] = maxi(_districts[id]["investment"] - 1, 0)


## Validate and register one district entry; malformed entries are silently dropped.
func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not dict.has("id"):
		return
	var id: String = str(dict["id"])
	if id.is_empty() or _districts.has(id):
		return
	var base := float(dict.get("base", 1.0))
	if base <= 0.0:
		return
	_districts[id] = {"base": base, "control": 0.0, "heat": 0.0, "investment": 0}
