class_name WeaponLoadout
extends RefCounted
## Pure weapon-attachment / loadout model — one attachment per slot (optic, muzzle,
## magazine, grip) that tunes a weapon's stats: a scope tightens spread and extends
## range, a suppressor quiets the shot and trims range, an extended mag adds rounds,
## a foregrip tames recoil. The aggregated modifiers feed the live WeaponBallistics
## math (apply the spread/range multipliers around its falloff + spread helpers).
##
## No nodes, no scene access: a weapon controller owns one, asks for the combined
## multipliers/bonuses, and applies them to its own ballistics — so the modifier
## algebra stays unit-tested headless (tests/unit/test_weapon_loadout.gd).
##
## Each attachment is a Dictionary {id, slot, mults, adds, suppresses}: `mults` are
## per-stat multipliers (combine by product), `adds` are per-stat integer bonuses
## (combine by sum). Malformed entries (missing id/slot, unknown slot) are dropped.

## The four attachment slots; one attachment may occupy each.
const SLOTS: Array = ["optic", "muzzle", "magazine", "grip"]

## id -> {slot, mults: Dictionary, adds: Dictionary, suppresses: bool}.
var _catalogue: Dictionary = {}

## slot -> equipped attachment id.
var _equipped: Dictionary = {}


func _init(attachments: Array = []) -> void:
	var source: Array = attachments if not attachments.is_empty() else default_attachments()
	for entry: Variant in source:
		_register(entry)


## Built-in attachment catalogue spanning every slot.
static func default_attachments() -> Array:
	return [
		{"id": "red_dot", "slot": "optic", "mults": {"spread": 0.85}},
		{"id": "scope", "slot": "optic", "mults": {"spread": 0.6, "range": 1.25}},
		{"id": "suppressor", "slot": "muzzle", "mults": {"range": 0.9}, "suppresses": true},
		{"id": "compensator", "slot": "muzzle", "mults": {"recoil": 0.7}},
		{"id": "extended_mag", "slot": "magazine", "adds": {"mag": 12}},
		{"id": "foregrip", "slot": "grip", "mults": {"recoil": 0.8, "spread": 0.9}},
	]


func attachment_count() -> int:
	return _catalogue.size()


## True if the attachment id exists in the catalogue.
func has_attachment(id: String) -> bool:
	return _catalogue.has(id)


## Slot an attachment occupies, or "" if the id is unknown.
func slot_of(id: String) -> String:
	if not _catalogue.has(id):
		return ""
	return _catalogue[id]["slot"]


## Equip an attachment, replacing whatever was in its slot. Returns false for an
## unknown id.
func equip(id: String) -> bool:
	if not _catalogue.has(id):
		return false
	_equipped[_catalogue[id]["slot"]] = id
	return true


## Clear a slot. No-op for an unknown/empty slot.
func unequip(slot: String) -> void:
	_equipped.erase(slot)


## The id equipped in a slot, or "" if the slot is empty.
func equipped_in(slot: String) -> String:
	return _equipped.get(slot, "")


## True if a specific attachment is currently equipped.
func is_equipped(id: String) -> bool:
	if not _catalogue.has(id):
		return false
	return _equipped.get(_catalogue[id]["slot"]) == id


func equipped_count() -> int:
	return _equipped.size()


## Combined multiplier for a stat across all equipped attachments (product; 1.0
## when none affect it). Apply to spread/range/recoil/etc.
func mult_for(stat: String) -> float:
	var factor := 1.0
	for slot: Variant in _equipped:
		var mods: Dictionary = _catalogue[_equipped[slot]]["mults"]
		if mods.has(stat):
			factor *= float(mods[stat])
	return factor


## Combined integer bonus for a stat across all equipped attachments (sum; 0 when
## none affect it). Apply to magazine size etc.
func add_for(stat: String) -> int:
	var total := 0
	for slot: Variant in _equipped:
		var mods: Dictionary = _catalogue[_equipped[slot]]["adds"]
		if mods.has(stat):
			total += int(mods[stat])
	return total


## Convenience: a base stat scaled by the combined multiplier.
func apply_mult(base_value: float, stat: String) -> float:
	return base_value * mult_for(stat)


## Magazine size after additive bonuses, floored at 0.
func mag_size(base_size: int) -> int:
	return maxi(0, base_size + add_for("mag"))


## True if any equipped attachment suppresses the shot (quiet kills / fewer
## witnesses).
func is_suppressed() -> bool:
	for slot: Variant in _equipped:
		if _catalogue[_equipped[slot]]["suppresses"]:
			return true
	return false


## Strip every attachment.
func clear() -> void:
	_equipped.clear()


## Validate and register one attachment; malformed entries are silently dropped.
func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not (dict.has("id") and dict.has("slot")):
		return
	var id: String = str(dict["id"])
	var slot: String = str(dict["slot"])
	if id.is_empty() or _catalogue.has(id) or not SLOTS.has(slot):
		return
	_catalogue[id] = {
		"slot": slot,
		"mults": dict.get("mults", {}),
		"adds": dict.get("adds", {}),
		"suppresses": bool(dict.get("suppresses", false)),
	}
