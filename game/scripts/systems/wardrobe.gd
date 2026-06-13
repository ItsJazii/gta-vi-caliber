class_name Wardrobe
extends RefCounted
## Pure clothing-wardrobe model — buy outfits, own them, and wear one per slot
## (outfit / hair / mask). What you're wearing feeds Disguise: each worn item has a
## `look` value you push into Disguise.set_appearance(slot, look), so changing
## clothes changes how recognizable you are to the cops. Distinct from the generic
## ShopModel: this tracks ownership + the currently-worn look per slot.
##
## No nodes, no scene access: a wardrobe UI owns one, resolves buy() against the
## wallet (caller applies the spend), and pushes worn_looks() into a Disguise — so
## the catalogue / ownership / wear logic stays unit-tested headless
## (tests/unit/test_wardrobe.gd).
##
## Each item is a Dictionary {id, name, slot, price, look, owned}. Malformed entries
## (missing/empty id, unknown slot, negative price) are dropped.

## Wearable clothing slots (a subset of Disguise's slots — vehicle isn't clothing).
const SLOTS: Array = ["outfit", "hair", "mask"]

## id -> {name, slot, price:int>=0, look}.
var _catalogue: Dictionary = {}
## Set of owned item ids.
var _owned: Dictionary = {}
## slot -> worn item id.
var _worn: Dictionary = {}


func _init(items: Array = []) -> void:
	var source: Array = items if not items.is_empty() else default_items()
	for entry: Variant in source:
		_register(entry)
	# Wear the first owned starter in each slot.
	for id: Variant in _owned:
		var slot: String = _catalogue[id]["slot"]
		if not _worn.has(slot):
			_worn[slot] = id


## Built-in catalogue; the starter casual + buzz cut are owned and worn from new.
static func default_items() -> Array:
	return [
		{
			"id": "street_casual",
			"name": "Street Casual",
			"slot": "outfit",
			"price": 0,
			"look": "casual",
			"owned": true
		},
		{"id": "sharp_suit", "name": "Sharp Suit", "slot": "outfit", "price": 1500, "look": "suit"},
		{
			"id": "track_suit",
			"name": "Track Suit",
			"slot": "outfit",
			"price": 400,
			"look": "tracksuit"
		},
		{
			"id": "buzz_cut",
			"name": "Buzz Cut",
			"slot": "hair",
			"price": 0,
			"look": "buzz",
			"owned": true
		},
		{"id": "blonde_dye", "name": "Blonde Dye", "slot": "hair", "price": 300, "look": "blonde"},
		{"id": "ski_mask", "name": "Ski Mask", "slot": "mask", "price": 250, "look": "ski_mask"},
	]


func item_count() -> int:
	return _catalogue.size()


func has_item(id: String) -> bool:
	return _catalogue.has(id)


func ids() -> Array:
	return _catalogue.keys()


## Catalogue price of an item (-1 if unknown).
func price_of(id: String) -> int:
	if not _catalogue.has(id):
		return -1
	return _catalogue[id]["price"]


## The slot an item occupies ("" if unknown).
func slot_of(id: String) -> String:
	if not _catalogue.has(id):
		return ""
	return _catalogue[id]["slot"]


## The Disguise appearance value an item maps to ("" if unknown).
func look_of(id: String) -> String:
	if not _catalogue.has(id):
		return ""
	return _catalogue[id]["look"]


## Catalogue ids in a slot.
func items_in_slot(slot: String) -> Array:
	var out: Array = []
	for id: Variant in _catalogue:
		if _catalogue[id]["slot"] == slot:
			out.append(id)
	return out


func owns(id: String) -> bool:
	return _owned.has(id)


## Buy an item against a wallet balance. Never mutates the wallet (caller applies
## new_balance). Fails on unknown id, already owned, or insufficient funds. Returns
## {success, cost, new_balance, reason}.
func buy(id: String, balance: int) -> Dictionary:
	if not _catalogue.has(id):
		return _fail(balance, "no such item: %s" % id)
	if _owned.has(id):
		return _fail(balance, "already owned")
	var cost: int = _catalogue[id]["price"]
	if balance < cost:
		return _fail(balance, "insufficient funds: need %d, have %d" % [cost, balance])
	_owned[id] = true
	return {"success": true, "cost": cost, "new_balance": balance - cost, "reason": ""}


## Wear an owned item (replaces whatever was in its slot). Returns false if unknown
## or not owned.
func wear(id: String) -> bool:
	if not _owned.has(id):
		return false
	_worn[_catalogue[id]["slot"]] = id
	return true


## Take off whatever's in a slot.
func take_off(slot: String) -> void:
	_worn.erase(slot)


## The item id worn in a slot ("" if nothing).
func worn_in(slot: String) -> String:
	return _worn.get(slot, "")


## The Disguise look value worn in a slot ("" if nothing).
func worn_look(slot: String) -> String:
	return look_of(worn_in(slot)) if not worn_in(slot).is_empty() else ""


## {slot: look} for every worn slot — push into Disguise.set_appearance per slot.
func worn_looks() -> Dictionary:
	var out: Dictionary = {}
	for slot: Variant in _worn:
		out[slot] = look_of(_worn[slot])
	return out


func _fail(balance: int, reason: String) -> Dictionary:
	return {"success": false, "cost": 0, "new_balance": balance, "reason": reason}


func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not dict.has("id"):
		return
	var id: String = str(dict["id"])
	var slot: String = str(dict.get("slot", ""))
	var price := int(dict.get("price", 0))
	if id.is_empty() or _catalogue.has(id) or not SLOTS.has(slot) or price < 0:
		return
	_catalogue[id] = {
		"name": str(dict.get("name", id)),
		"slot": slot,
		"price": price,
		"look": str(dict.get("look", id)),
	}
	if bool(dict.get("owned", false)):
		_owned[id] = true
