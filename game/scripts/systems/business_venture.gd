class_name BusinessVenture
extends RefCounted
## Pure operational business-empire model: the active "run the business" loop GTA
## is built on, the layer PropertyOwnership's flat income_per_day does not model.
## Owned ventures (a coke lab, a counterfeit-cash factory, a nightclub, a weed
## farm) convert SUPPLIES into PRODUCT over game time at a rate scaled by hired
## staff and a permanent upgrade tier; the player periodically cashes out the
## accrued stockpile at a per-unit price that moves with market demand and a police
## heat discount.
##
## The loop: acquire() a venture, buy_supplies() raw materials, accrue() converts
## supply to product while the player does other things (throttled when supply runs
## dry), hire()/upgrade() raise throughput, sell() cashes out the stockpile.
##
## No nodes, no PlayerStats coupling: every money op resolves against a wallet
## balance the caller passes in and NEVER mutates it — the caller applies the
## returned new_balance / proceeds (PlayerStats.spend_money / add_money). That keeps
## the supply/staff/tier/demand curves unit-tested headless
## (tests/unit/test_business_venture.gd) while composing with the live economy:
## pass DistrictEconomy.desirability() as `demand` and a WantedSystem/FactionStanding
## heat into sale_price()/sell(). Pairs with PropertyOwnership (passive safehouses).
##
## Catalogue row: {id, name, product_per_day, product_per_supply, max_product,
## sale_value, max_staff, max_tier}. Rows with no/empty id or a non-positive
## product_per_day / sale_value are dropped at construction.

## Demand multiplier is clamped to this band before scaling the sale price.
const DEMAND_MIN: float = 0.5
const DEMAND_MAX: float = 2.0
## Fraction of the sale price lost when the operation is fully hot (heat == 1).
const HEAT_DISCOUNT: float = 0.3
## Production-rate gain per hired worker and per permanent upgrade tier.
const STAFF_GAIN: float = 0.5
const TIER_GAIN: float = 0.35
## Fallbacks for catalogue rows that omit the operational tuning fields.
const DEFAULT_PRODUCT_PER_SUPPLY: float = 1.0
const DEFAULT_MAX_PRODUCT: float = 100.0
const DEFAULT_MAX_STAFF: int = 5
const DEFAULT_MAX_TIER: int = 3
## Catalogue sanity caps so crafted rows / saves can't overflow proceeds (int64).
const MAX_REASONABLE_PRODUCT: float = 1_000_000.0
const MAX_REASONABLE_SALE_VALUE: int = 10_000_000

## id -> catalogue row (immutable tuning). Built once in _init, insertion-ordered.
var _catalogue: Dictionary = {}
## id -> {supply: float, product: float, staff: int, tier: int} for owned ventures.
var _owned: Dictionary = {}
## Lifetime gross revenue from every sell().
var _gross: int = 0


func _init(ventures: Array = []) -> void:
	var source: Array = ventures if not ventures.is_empty() else default_ventures()
	for entry: Variant in source:
		_register(entry)


## Built-in roster used when an empty array is passed: classic operated rackets.
## Sale values are money units; product is an abstract "unit of goods".
static func default_ventures() -> Array:
	return [
		{
			"id": "coke_lab",
			"name": "Cocaine Lockup",
			"product_per_day": 10.0,
			"product_per_supply": 2.0,
			"max_product": 200.0,
			"sale_value": 2000,
			"max_staff": 6,
			"max_tier": 3,
		},
		{
			"id": "cash_factory",
			"name": "Counterfeit Cash Factory",
			"product_per_day": 15.0,
			"product_per_supply": 1.5,
			"max_product": 300.0,
			"sale_value": 1200,
			"max_staff": 8,
			"max_tier": 3,
		},
		{
			"id": "nightclub",
			"name": "Vice Nightclub",
			"product_per_day": 8.0,
			"product_per_supply": 1.0,
			"max_product": 150.0,
			"sale_value": 1500,
			"max_staff": 10,
			"max_tier": 2,
		},
		{
			"id": "weed_farm",
			"name": "Everglades Weed Farm",
			"product_per_day": 12.0,
			"product_per_supply": 2.5,
			"max_product": 250.0,
			"sale_value": 900,
			"max_staff": 5,
			"max_tier": 3,
		},
	]


# --- Catalogue queries ----------------------------------------------------


func venture_count() -> int:
	return _catalogue.size()


func has_venture(id: String) -> bool:
	return _catalogue.has(id)


## Catalogue ids in first-seen order.
func ids() -> Array:
	return _catalogue.keys()


# --- Ownership queries ----------------------------------------------------


func owns(id: String) -> bool:
	return _owned.has(id)


## Owned ids, sorted so callers and tests agree on order.
func owned_ids() -> Array:
	var out: Array = _owned.keys()
	out.sort()
	return out


## Live operational state — all return 0 for an unowned / unknown venture.
func supply_in(id: String) -> float:
	return _owned[id]["supply"] if _owned.has(id) else 0.0


func product_in(id: String) -> float:
	return _owned[id]["product"] if _owned.has(id) else 0.0


func staff_in(id: String) -> int:
	return _owned[id]["staff"] if _owned.has(id) else 0


func tier_in(id: String) -> int:
	return _owned[id]["tier"] if _owned.has(id) else 0


# --- Acquisition & money ops (wallet resolved by caller) -------------------


## Take over a venture against a wallet balance. On success marks it owned with a
## fresh empty operation; reports new_balance for the caller to apply. Fails
## (state unchanged) for unknown / already-owned / insufficient funds.
func acquire(id: String, cost: int, balance: int) -> Dictionary:
	if not _catalogue.has(id):
		return _fail(balance, "unknown venture: %s" % id)
	if _owned.has(id):
		return _fail(balance, "already owned: %s" % id)
	if balance < cost:
		return _fail(balance, "insufficient funds: need %d, have %d" % [cost, balance])
	_owned[id] = {"supply": 0.0, "product": 0.0, "staff": 0, "tier": 0}
	return {"success": true, "cost": cost, "new_balance": balance - cost, "reason": ""}


## Restock raw materials, clamped so supply never exceeds what max_product needs
## (over-ordering is free of charge — you only pay for what actually fits). Fails
## for unowned / non-positive units / non-positive unit_cost (a negative price would
## be a money printer) / already fully stocked / insufficient funds.
func buy_supplies(id: String, units: int, unit_cost: int, balance: int) -> Dictionary:
	if not _owned.has(id):
		return _fail(balance, "not owned: %s" % id)
	if units <= 0:
		return _fail(balance, "non-positive units")
	if unit_cost <= 0:
		return _fail(balance, "non-positive unit_cost")
	var ceiling: float = _supply_ceiling(id)
	var current: float = _owned[id]["supply"]
	var added: float = clampf(ceiling - current, 0.0, float(units))
	if added <= 0.0:
		return _fail(balance, "already fully stocked: %s" % id)
	var cost: int = int(round(added * float(unit_cost)))
	if balance < cost:
		return _fail(balance, "insufficient funds: need %d, have %d" % [cost, balance])
	_owned[id]["supply"] = current + added
	return {"success": true, "cost": cost, "new_balance": balance - cost, "reason": ""}


## Raise tier toward max_tier (a permanent production multiplier) against the
## wallet. Fails for unowned / already at max / insufficient funds.
func upgrade(id: String, cost: int, balance: int) -> Dictionary:
	if not _owned.has(id):
		return _fail(balance, "not owned: %s" % id)
	var max_tier: int = _catalogue[id]["max_tier"]
	if _owned[id]["tier"] >= max_tier:
		return _fail(balance, "already at max tier")
	if balance < cost:
		return _fail(balance, "insufficient funds: need %d, have %d" % [cost, balance])
	_owned[id]["tier"] = int(_owned[id]["tier"]) + 1
	return {"success": true, "cost": cost, "new_balance": balance - cost, "reason": ""}


# --- Staffing -------------------------------------------------------------


## Hire one worker (raises production_rate), bounded by max_staff. False if unowned
## or already at the cap.
func hire(id: String) -> bool:
	if not _owned.has(id):
		return false
	var max_staff: int = _catalogue[id]["max_staff"]
	if _owned[id]["staff"] >= max_staff:
		return false
	_owned[id]["staff"] = int(_owned[id]["staff"]) + 1
	return true


## Lay off one worker, bounded at 0. False if unowned or already at zero.
func fire(id: String) -> bool:
	if not _owned.has(id):
		return false
	if _owned[id]["staff"] <= 0:
		return false
	_owned[id]["staff"] = int(_owned[id]["staff"]) - 1
	return true


# --- Production -----------------------------------------------------------


## Effective product/day = product_per_day * staff factor * tier factor. 0.0 if
## unowned or out of supply (an idle, unstocked lab makes nothing).
func production_rate(id: String) -> float:
	if not _owned.has(id):
		return 0.0
	if float(_owned[id]["supply"]) <= 0.0:
		return 0.0
	var base: float = _catalogue[id]["product_per_day"]
	return base * _staff_factor(_owned[id]["staff"]) * _tier_factor(_owned[id]["tier"])


## Advance every owned venture by `delta_days`: convert supplies to product at
## production_rate, capped by the max_product headroom and by the supply actually
## on hand (each product unit costs product_per_supply supply). Non-positive spans
## are ignored.
func accrue(delta_days: float) -> void:
	if delta_days <= 0.0:
		return
	for id: String in _owned:
		var rate: float = production_rate(id)
		if rate <= 0.0:
			continue
		var per_supply: float = _catalogue[id]["product_per_supply"]
		var max_product: float = _catalogue[id]["max_product"]
		var product: float = _owned[id]["product"]
		var supply: float = _owned[id]["supply"]
		var wanted: float = rate * delta_days
		var headroom: float = maxf(max_product - product, 0.0)
		var from_supply: float = supply / per_supply if per_supply > 0.0 else wanted
		var made: float = minf(wanted, minf(headroom, from_supply))
		_owned[id]["product"] = product + made
		_owned[id]["supply"] = maxf(supply - made * per_supply, 0.0)


# --- Selling --------------------------------------------------------------


## Per-unit cash-out price for a venture: sale_value scaled by clamped demand and
## docked by the heat discount. 0 for an unknown venture. `demand` is e.g.
## DistrictEconomy.desirability(); `heat` in [0,1] from stars / faction trouble.
func sale_price(id: String, demand: float, heat: float) -> int:
	if not _catalogue.has(id):
		return 0
	var sale_value: int = _catalogue[id]["sale_value"]
	var d: float = clampf(demand, DEMAND_MIN, DEMAND_MAX)
	var h: float = clampf(heat, 0.0, 1.0)
	# Floor a known venture's unit price at 1 so cheap rackets can't burn product for $0.
	return maxi(1, int(round(float(sale_value) * d * (1.0 - HEAT_DISCOUNT * h))))


## Cash out up to `units` of accrued product at sale_price. Never mutates the
## wallet — the caller credits `proceeds`. Records lifetime gross. Fails for
## unowned / non-positive units / an empty stockpile.
func sell(id: String, units: int, demand: float, heat: float) -> Dictionary:
	if not _owned.has(id):
		return _sell_fail("not owned: %s" % id)
	if units <= 0:
		return _sell_fail("non-positive units")
	var available: int = int(floor(float(_owned[id]["product"])))
	if available <= 0:
		return _sell_fail("empty stockpile")
	var sold: int = mini(units, available)
	var proceeds: int = sold * sale_price(id, demand, heat)
	_owned[id]["product"] = float(_owned[id]["product"]) - float(sold)
	_gross += proceeds
	return {"success": true, "proceeds": proceeds, "sold": sold, "reason": ""}


# --- Aggregates -----------------------------------------------------------


## Empire-wide stockpile across every owned venture (floored to whole units).
func total_product() -> int:
	var sum: float = 0.0
	for id: String in _owned:
		sum += float(_owned[id]["product"])
	return int(floor(sum))


## Lifetime gross revenue from all sales.
func gross_earned() -> int:
	return _gross


# --- Persistence ----------------------------------------------------------


func serialize() -> Dictionary:
	var owned: Dictionary = {}
	for id: String in _owned:
		owned[id] = {
			"supply": _owned[id]["supply"],
			"product": _owned[id]["product"],
			"staff": _owned[id]["staff"],
			"tier": _owned[id]["tier"],
		}
	return {"owned": owned, "gross": _gross}


## Rebuild from a serialize() snapshot. Unknown ids and malformed rows are dropped;
## bad input leaves zero owned ventures.
func restore(data: Dictionary) -> void:
	_owned = {}
	_gross = int(maxf(float(data.get("gross", 0)), 0.0))
	var stored: Variant = data.get("owned")
	if not (stored is Dictionary):
		return
	var owned: Dictionary = stored
	for key: Variant in owned:
		var id: String = str(key)
		if not _catalogue.has(id) or not (owned[key] is Dictionary):
			continue
		var row: Dictionary = owned[key]
		# Clamp ALL operational fields, not just staff/tier, so a crafted save can't
		# load supply/product past the caps that buy_supplies/accrue enforce.
		_owned[id] = {
			"supply": clampf(float(row.get("supply", 0.0)), 0.0, _supply_ceiling(id)),
			"product": clampf(float(row.get("product", 0.0)), 0.0, _catalogue[id]["max_product"]),
			"staff": clampi(int(row.get("staff", 0)), 0, _catalogue[id]["max_staff"]),
			"tier": clampi(int(row.get("tier", 0)), 0, _catalogue[id]["max_tier"]),
		}


# --- Internal -------------------------------------------------------------


static func _staff_factor(staff: int) -> float:
	return 1.0 + float(maxi(staff, 0)) * STAFF_GAIN


static func _tier_factor(tier: int) -> float:
	return 1.0 + float(maxi(tier, 0)) * TIER_GAIN


## Supply level at which a venture's stockpile could fill to max_product.
func _supply_ceiling(id: String) -> float:
	return float(_catalogue[id]["max_product"]) * float(_catalogue[id]["product_per_supply"])


func _fail(balance: int, reason: String) -> Dictionary:
	return {"success": false, "cost": 0, "new_balance": balance, "reason": reason}


func _sell_fail(reason: String) -> Dictionary:
	return {"success": false, "proceeds": 0, "sold": 0, "reason": reason}


## Validate and store one catalogue row; silently drops malformed rows.
func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var row: Dictionary = entry
	if not row.has("id"):
		return
	var id: String = str(row["id"])
	if id.is_empty() or _catalogue.has(id):
		return
	var per_day: float = float(row.get("product_per_day", 0.0))
	var sale_value: int = int(row.get("sale_value", 0))
	if per_day <= 0.0 or sale_value <= 0:
		return
	var per_supply: float = float(row.get("product_per_supply", DEFAULT_PRODUCT_PER_SUPPLY))
	_catalogue[id] = {
		"id": id,
		"name": str(row.get("name", id)),
		"product_per_day": per_day,
		"product_per_supply": per_supply if per_supply > 0.0 else DEFAULT_PRODUCT_PER_SUPPLY,
		"max_product":
		clampf(float(row.get("max_product", DEFAULT_MAX_PRODUCT)), 1.0, MAX_REASONABLE_PRODUCT),
		"sale_value": mini(sale_value, MAX_REASONABLE_SALE_VALUE),
		"max_staff": maxi(int(row.get("max_staff", DEFAULT_MAX_STAFF)), 0),
		"max_tier": maxi(int(row.get("max_tier", DEFAULT_MAX_TIER)), 0),
	}
