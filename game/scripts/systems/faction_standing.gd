class_name FactionStanding
extends RefCounted
## Pure faction-reputation model — how each gang/faction feels about the player on a
## -100 (hostile) .. +100 (allied) scale. Helping a faction raises its standing
## (and, via rivalry, lowers its enemy's); attacking it lowers it. Standing gates
## behaviour: a hostile faction's NPCs attack on sight, an allied faction's assist
## in a fight. Faction ids line up with GangTerritory's gangs, so turf and
## reputation share one set of factions (turf = who holds ground, standing = how
## they treat you).
##
## No nodes, no scene access: an AI/world controller owns one, adjusts standing on
## player actions, and reads will_attack/will_assist to drive NPC behaviour — so the
## standing/tier/rivalry math stays unit-tested headless
## (tests/unit/test_faction_standing.gd).
##
## Each faction is a Dictionary {id, rival}; rival "" means no rivalry. Malformed
## entries (missing/empty id) are dropped.

const MIN_STANDING: int = -100
const MAX_STANDING: int = 100
## Tier thresholds (standing <= / >=).
const HOSTILE_AT: int = -40
const WARY_AT: int = -10
const FRIENDLY_AT: int = 10
const ALLIED_AT: int = 40
## Default fraction of an adjustment that bleeds (inverted) onto a rival.
const DEFAULT_SPILLOVER: float = 0.5

## id -> {rival: String, standing: int}.
var _factions: Dictionary = {}


func _init(factions: Array = []) -> void:
	var source: Array = factions if not factions.is_empty() else default_factions()
	for entry: Variant in source:
		_register(entry)


## Built-in factions, ids aligned with GangTerritory's gangs plus the police.
static func default_factions() -> Array:
	return [
		{"id": "vice_kings", "rival": "marina_cartel"},
		{"id": "marina_cartel", "rival": "vice_kings"},
		{"id": "los_santos_set", "rival": ""},
		{"id": "police", "rival": ""},
	]


func faction_count() -> int:
	return _factions.size()


func has_faction(id: String) -> bool:
	return _factions.has(id)


func ids() -> Array:
	return _factions.keys()


## The faction's rival id ("" if none / unknown).
func rival_of(id: String) -> String:
	if not _factions.has(id):
		return ""
	return _factions[id]["rival"]


## Standing in [-100, 100] (0 / neutral if unknown).
func standing_of(id: String) -> int:
	if not _factions.has(id):
		return 0
	return _factions[id]["standing"]


## Named tier for the current standing ("" if unknown).
func tier_of(id: String) -> String:
	if not _factions.has(id):
		return ""
	var s: int = _factions[id]["standing"]
	if s <= HOSTILE_AT:
		return "hostile"
	if s <= WARY_AT:
		return "wary"
	if s < FRIENDLY_AT:
		return "neutral"
	if s < ALLIED_AT:
		return "friendly"
	return "allied"


func is_hostile(id: String) -> bool:
	return _factions.has(id) and _factions[id]["standing"] <= HOSTILE_AT


func is_allied(id: String) -> bool:
	return _factions.has(id) and _factions[id]["standing"] >= ALLIED_AT


## Whether this faction's NPCs attack the player on sight.
func will_attack(id: String) -> bool:
	return is_hostile(id)


## Whether this faction's NPCs will help the player in a fight.
func will_assist(id: String) -> bool:
	return is_allied(id)


## Set standing directly (loading a save / story beat), clamped. No-op if unknown.
func set_standing(id: String, value: int) -> void:
	if _factions.has(id):
		_factions[id]["standing"] = clampi(value, MIN_STANDING, MAX_STANDING)


## Shift a faction's standing by `delta` (clamped). A non-zero `spillover` applies
## the inverse, scaled, to the faction's rival (helping one gang angers its enemy).
## No-op for an unknown faction.
func adjust(id: String, delta: int, spillover: float = DEFAULT_SPILLOVER) -> void:
	if not _factions.has(id):
		return
	set_standing(id, _factions[id]["standing"] + delta)
	var rival: String = _factions[id]["rival"]
	if not rival.is_empty() and spillover > 0.0 and _factions.has(rival):
		var bleed := int(round(float(delta) * clampf(spillover, 0.0, 1.0)))
		set_standing(rival, _factions[rival]["standing"] - bleed)


## Flatten to {id: standing} for the save system.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for id: Variant in _factions:
		out[id] = _factions[id]["standing"]
	return out


## Restore from {id: standing}. Unknown ids / non-int values ignored; known clamped.
func load_dict(data: Dictionary) -> void:
	for id: Variant in data:
		var key: String = str(id)
		if _factions.has(key) and (data[id] is int or data[id] is float):
			set_standing(key, int(data[id]))


func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not dict.has("id"):
		return
	var id: String = str(dict["id"])
	if id.is_empty() or _factions.has(id):
		return
	_factions[id] = {"rival": str(dict.get("rival", "")), "standing": 0}
