class_name ShopModel
extends RefCounted
## Pure shop/store economy model — spends the money the player earns on weapons,
## ammo, armor, and vehicles.
##
## No nodes, no PlayerStats coupling: a purchase resolves against a wallet balance
## that the caller passes in, returning the result so the caller applies the spend
## (PlayerStats.spend_money). That keeps it unit-testable headless
## (tests/unit/test_shop_model.gd) while complementing the live economy
## (PlayerStats.money + MissionReward payouts).
##
## Each catalogue entry is a Dictionary {id, name, price, category}. Garbage
## entries (missing id, non-int/negative price) are dropped at construction.

## Fraction of an item's price recovered when selling it back (50%).
const DEFAULT_SELL_FRACTION: float = 0.5

## id -> {id, name, price, category}. Built once in _init.
var _items: Dictionary = {}


func _init(catalogue: Array = []) -> void:
	var source: Array = catalogue if not catalogue.is_empty() else default_catalogue()
	for entry in source:
		_register(entry)


## The built-in stock used when an empty catalogue is passed: a couple of
## weapons, ammo, armor, and vehicles. Prices are in the game's money units.
static func default_catalogue() -> Array:
	return [
		{"id": "pistol", "name": "Pistol", "price": 500, "category": "weapon"},
		{"id": "smg", "name": "SMG", "price": 2500, "category": "weapon"},
		{"id": "rifle", "name": "Assault Rifle", "price": 7500, "category": "weapon"},
		{"id": "ammo_box", "name": "Ammo Box", "price": 150, "category": "ammo"},
		{"id": "body_armor", "name": "Body Armor", "price": 1000, "category": "armor"},
		{"id": "sedan", "name": "Sedan", "price": 12000, "category": "vehicle"},
		{"id": "sportscar", "name": "Sports Car", "price": 60000, "category": "vehicle"},
	]


func item_count() -> int:
	return _items.size()


func has_item(id: String) -> bool:
	return _items.has(id)


## Price of an item, or -1 if the id is unknown.
func price_of(id: String) -> int:
	if not _items.has(id):
		return -1
	return _items[id]["price"]


## Every item in a category (empty Array if none / unknown category).
func items_in_category(category: String) -> Array:
	var out: Array = []
	for id in _items:
		if _items[id]["category"] == category:
			# Hand back COPIES: the entries are the live master catalogue, and a
			# caller mutating a returned dict (e.g. a discounted price) would
			# corrupt the source that price_of/can_afford/purchase read.
			out.append((_items[id] as Dictionary).duplicate())
	return out


## True when the balance covers the item's price. Unknown id is never affordable.
func can_afford(id: String, balance: int) -> bool:
	var price := price_of(id)
	if price < 0:
		return false
	return balance >= price


## What an item sells back for at the given fraction of its price (>= 0).
## Unknown id returns 0. Fraction is clamped to [0, 1].
func sell_value(id: String, fraction: float = DEFAULT_SELL_FRACTION) -> int:
	var price := price_of(id)
	if price < 0:
		return 0
	return int(round(float(price) * clampf(fraction, 0.0, 1.0)))


## Resolve a purchase against a wallet balance. Never mutates state: the caller
## applies new_balance via PlayerStats.spend_money on success.
## Returns {success, cost, new_balance, reason}.
func purchase(id: String, balance: int) -> Dictionary:
	if not _items.has(id):
		return _fail(balance, "unknown item: %s" % id)
	var price: int = _items[id]["price"]
	if balance < price:
		return _fail(balance, "insufficient funds: need %d, have %d" % [price, balance])
	return {
		"success": true,
		"cost": price,
		"new_balance": balance - price,
		"reason": "",
	}


func _fail(balance: int, reason: String) -> Dictionary:
	return {"success": false, "cost": 0, "new_balance": balance, "reason": reason}


## Validate and store one catalogue entry; silently drops malformed ones so a bad
## row can't crash the store.
func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	if not (entry.has("id") and entry.has("price")):
		return
	var id: Variant = entry["id"]
	var price: Variant = entry["price"]
	if not (id is String) or id.is_empty():
		return
	if not (price is int) or price < 0:
		return
	_items[id] = {
		"id": id,
		"name": entry.get("name", id),
		"price": price,
		"category": entry.get("category", "misc"),
	}
