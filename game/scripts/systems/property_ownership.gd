class_name PropertyOwnership
extends RefCounted
## Pure property-ownership / passive-income model: the player buys safehouses and
## businesses, which then accrue income over time into a pending bank the player
## collects by visiting.
##
## No nodes, no PlayerStats coupling: a purchase resolves against a wallet balance
## the caller passes in, returning the result so the caller applies the spend
## (PlayerStats.spend_money). Income accrues on game days fed in by a node, and
## collect() hands back the banked cash for the caller to credit. That keeps it
## unit-testable headless (tests/unit/test_property_ownership.gd) while
## complementing the live economy (PlayerStats.money + MissionReward payouts).
##
## Each catalogue entry is a Dictionary {id, name, price, income_per_day,
## is_safehouse}. Garbage entries (missing id, non-int/negative price) are dropped
## at construction.

## id -> {id, name, price, income_per_day, is_safehouse}. Built once in _init.
var _catalogue: Dictionary = {}
## Set of owned ids: id -> true.
var _owned: Dictionary = {}
## Income accrued from owned businesses but not yet collected.
var _pending: float = 0.0


func _init(catalogue: Array = []) -> void:
	var source: Array = catalogue if not catalogue.is_empty() else default_catalogue()
	for entry in source:
		_register(entry)


## The built-in stock used when an empty catalogue is passed: a couple of
## safehouses plus income-producing businesses. Prices/income are money units.
static func default_catalogue() -> Array:
	return [
		{
			"id": "beach_condo",
			"name": "Ocean Drive Condo",
			"price": 25000,
			"income_per_day": 0,
			"is_safehouse": true,
		},
		{
			"id": "downtown_loft",
			"name": "Downtown Loft",
			"price": 90000,
			"income_per_day": 0,
			"is_safehouse": true,
		},
		{
			"id": "taxi_firm",
			"name": "Vice Taxi Firm",
			"price": 120000,
			"income_per_day": 4000,
			"is_safehouse": false,
		},
		{
			"id": "nightclub",
			"name": "Neon Nightclub",
			"price": 300000,
			"income_per_day": 12000,
			"is_safehouse": false,
		},
		{
			"id": "auto_shop",
			"name": "Auto Repair Shop",
			"price": 75000,
			"income_per_day": 2500,
			"is_safehouse": false,
		},
	]


# --- Catalogue queries ----------------------------------------------------


func property_count() -> int:
	return _catalogue.size()


## Price of a property, or -1 if the id is unknown.
func price_of(id: String) -> int:
	if not _catalogue.has(id):
		return -1
	return _catalogue[id]["price"]


## Daily income an individual property yields (0 for unknown or safehouse).
func income_of(id: String) -> int:
	if not _catalogue.has(id):
		return 0
	return _catalogue[id]["income_per_day"]


func is_safehouse(id: String) -> bool:
	if not _catalogue.has(id):
		return false
	return _catalogue[id]["is_safehouse"]


# --- Ownership queries ----------------------------------------------------


func owns(id: String) -> bool:
	return _owned.has(id)


## Sorted ids the player owns (sorted so callers and tests agree on order).
func owned_ids() -> Array:
	var out: Array = _owned.keys()
	out.sort()
	return out


func has_safehouse() -> bool:
	for id: String in _owned:
		if _catalogue[id]["is_safehouse"]:
			return true
	return false


## Id of the first owned safehouse (sorted), or "" if none owned. A stand-in for
## a real nearest-by-distance pick the caller can resolve against world position.
func nearest_safehouse_owned() -> String:
	for id: String in owned_ids():
		if _catalogue[id]["is_safehouse"]:
			return id
	return ""


## Total money spent acquiring every owned property.
func total_invested() -> int:
	var sum := 0
	for id: String in _owned:
		sum += _catalogue[id]["price"]
	return sum


## Combined daily income across every owned property.
func daily_income() -> int:
	var sum := 0
	for id: String in _owned:
		sum += _catalogue[id]["income_per_day"]
	return sum


# --- Purchase -------------------------------------------------------------


## Buy a property against a wallet balance. On success marks it owned and reports
## the deducted balance for the caller to apply (PlayerStats.spend_money).
## Fails (state unchanged) for unknown / already-owned / insufficient funds.
## Returns {success, cost, new_balance, reason}.
func buy(id: String, balance: int) -> Dictionary:
	if not _catalogue.has(id):
		return _fail(balance, "unknown property: %s" % id)
	if _owned.has(id):
		return _fail(balance, "already owned: %s" % id)
	var price: int = _catalogue[id]["price"]
	if balance < price:
		return _fail(balance, "insufficient funds: need %d, have %d" % [price, balance])
	_owned[id] = true
	return {
		"success": true,
		"cost": price,
		"new_balance": balance - price,
		"reason": "",
	}


# --- Income accrual -------------------------------------------------------


## Accumulate income from all owned businesses over `delta_days` into the pending
## bank. Negative or zero spans are ignored.
func accrue(delta_days: float) -> void:
	# `<= 0.0` lets NaN through (every NaN comparison is false), and NaN would
	# permanently poison the bank — collect() then returns int(NaN)=0 and wipes
	# all accrued income. Reject any non-finite span.
	if not is_finite(delta_days) or delta_days <= 0.0:
		return
	_pending += float(daily_income()) * delta_days


## Income banked but not yet collected.
func pending_income() -> float:
	return _pending


## Withdraw the pending income (models visiting a property to pick up the cash):
## returns the whole-money amount and zeroes the bank. The caller credits it
## (PlayerStats.add_money).
func collect() -> int:
	var amount := int(_pending) if is_finite(_pending) else 0
	_pending = 0.0
	return amount


# --- Persistence ----------------------------------------------------------


func serialize() -> Dictionary:
	return {
		"owned": owned_ids(),
		"pending": _pending,
	}


## Rebuild from a serialize() snapshot. Unknown ids are dropped; malformed input
## leaves an empty ownership map.
func restore(data: Dictionary) -> void:
	_owned = {}
	_pending = maxf(float(data.get("pending", 0.0)), 0.0)
	var stored: Variant = data.get("owned")
	if typeof(stored) != TYPE_ARRAY:
		return
	for entry: Variant in stored:
		var id := str(entry)
		if _catalogue.has(id):
			_owned[id] = true


## Sell off everything and clear the pending bank.
func reset() -> void:
	_owned = {}
	_pending = 0.0


# --- Internal -------------------------------------------------------------


func _fail(balance: int, reason: String) -> Dictionary:
	return {"success": false, "cost": 0, "new_balance": balance, "reason": reason}


## Validate and store one catalogue entry; silently drops malformed rows so a bad
## row can't crash the catalogue.
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
	var income: Variant = entry.get("income_per_day", 0)
	var income_int: int = income if (income is int) and income >= 0 else 0
	_catalogue[id] = {
		"id": id,
		"name": entry.get("name", id),
		"price": price,
		"income_per_day": income_int,
		"is_safehouse": bool(entry.get("is_safehouse", false)),
	}
