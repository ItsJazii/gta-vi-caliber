class_name VehicleModShop
extends RefCounted
## Pure tuning-garage model — the GTA mod shop where money buys tiered performance
## and armor upgrades that modify a vehicle's stats.
##
## STATEFUL per-vehicle instance: one VehicleModShop holds the upgrade levels for a
## single vehicle. A vehicle starts stock (every category at level 0) and each
## purchase steps one category up by one tier. No nodes, no wallet coupling: an
## upgrade resolves against a balance the caller passes in and returns the result
## so the caller applies the spend (PlayerStats.spend_money) — same headless,
## unit-testable pattern as ShopModel / WantedSystem. Covered by
## tests/unit/test_vehicle_mod_shop.gd.
##
## Catalogue shape: category -> Array of per-tier prices. price_tiers[i] is the
## cost to go from level i to level i+1, so max_level == price_tiers.size().
##
## Stat multipliers are derived purely from current levels and are 1.0 at stock,
## rising monotonically as levels climb. Each tier adds a fixed per-level step:
##   engine  -> +8% top speed AND +6% acceleration per level
##   tires   -> +7% grip per level
##   brakes  -> +10% brake per level
##   armor   -> +25% armor per level
## A category only feeds its own stat(s); untouched categories leave their
## multiplier at exactly 1.0.

## Per-level stat steps (fraction added to the 1.0 base for each level owned).
const ENGINE_SPEED_STEP: float = 0.08
const ENGINE_ACCEL_STEP: float = 0.06
const TIRES_GRIP_STEP: float = 0.07
const BRAKES_STEP: float = 0.10
const ARMOR_STEP: float = 0.25

## category -> Array[int] of per-tier prices. Built once in _init.
var _catalogue: Dictionary = {}
## category -> int current level. Built once in _init (all start at 0).
var _levels: Dictionary = {}


func _init(catalogue: Dictionary = {}) -> void:
	var source: Dictionary = catalogue if not catalogue.is_empty() else default_catalogue()
	for category in source:
		var tiers: Variant = source[category]
		var clean := _clean_tiers(tiers)
		if clean.is_empty():
			continue
		_catalogue[category] = clean
		_levels[category] = 0


## The built-in tuning catalogue: four categories, three tiers each, rising prices.
static func default_catalogue() -> Dictionary:
	return {
		"engine": [2000, 5000, 12000],
		"brakes": [1500, 3500, 8000],
		"armor": [2500, 6000, 14000],
		"tires": [1000, 2500, 6000],
	}


## Categories this shop sells (in no guaranteed order).
func categories() -> Array:
	return _catalogue.keys()


func has_category(category: String) -> bool:
	return _catalogue.has(category)


## Current installed level of a category (0 if stock / unknown).
func level_of(category: String) -> int:
	if not _levels.has(category):
		return 0
	return _levels[category]


## Highest level a category can reach (0 if unknown).
func max_level(category: String) -> int:
	if not _catalogue.has(category):
		return 0
	return _catalogue[category].size()


## Price to install `next_level` of a category, or -1 if maxed / unknown /
## out-of-range. next_level is the level you'd own after the buy (1-based).
func price_for(category: String, next_level: int) -> int:
	if not _catalogue.has(category):
		return -1
	var tiers: Array = _catalogue[category]
	if next_level < 1 or next_level > tiers.size():
		return -1
	return tiers[next_level - 1]


## True when the category exists and isn't already at max level.
func can_upgrade(category: String) -> bool:
	if not _catalogue.has(category):
		return false
	return level_of(category) < max_level(category)


## Buy the next tier of a category against a wallet balance. Mutates this
## instance's level only on success. Returns
## {success, cost, new_balance, new_level, reason}.
func upgrade(category: String, balance: int) -> Dictionary:
	if not _catalogue.has(category):
		return _fail(balance, "unknown category: %s" % category)
	var current := level_of(category)
	if current >= max_level(category):
		return _fail(balance, "already maxed: %s" % category)
	var cost := price_for(category, current + 1)
	if balance < cost:
		return _fail(balance, "insufficient funds: need %d, have %d" % [cost, balance])
	_levels[category] = current + 1
	return {
		"success": true,
		"cost": cost,
		"new_balance": balance - cost,
		"new_level": current + 1,
		"reason": "",
	}


## Top-speed multiplier from engine level (1.0 stock, +8% per engine level).
func top_speed_multiplier() -> float:
	return 1.0 + ENGINE_SPEED_STEP * float(level_of("engine"))


## Acceleration multiplier from engine level (1.0 stock, +6% per engine level).
func acceleration_multiplier() -> float:
	return 1.0 + ENGINE_ACCEL_STEP * float(level_of("engine"))


## Brake multiplier from brakes level (1.0 stock, +10% per brakes level).
func brake_multiplier() -> float:
	return 1.0 + BRAKES_STEP * float(level_of("brakes"))


## Armor multiplier from armor level (1.0 stock, +25% per armor level).
func armor_multiplier() -> float:
	return 1.0 + ARMOR_STEP * float(level_of("armor"))


## Grip multiplier from tires level (1.0 stock, +7% per tires level).
func grip_multiplier() -> float:
	return 1.0 + TIRES_GRIP_STEP * float(level_of("tires"))


## Total money sunk into this vehicle: the sum of every tier price up to the
## current level of each owned category.
func total_spent() -> int:
	var spent := 0
	for category in _catalogue:
		var tiers: Array = _catalogue[category]
		var lvl: int = _levels[category]
		for i in range(lvl):
			spent += tiers[i]
	return spent


## True when no upgrades have been installed (every category still at level 0).
func is_stock() -> bool:
	for category in _levels:
		if _levels[category] > 0:
			return false
	return true


## Snapshot of the installed levels for saving (category -> level). Catalogue is
## fixed by construction, so only the mutable levels are persisted.
func serialize() -> Dictionary:
	return _levels.duplicate(true)


## Restore installed levels from a serialize() snapshot. Unknown categories are
## ignored; out-of-range levels are clamped into [0, max_level].
func restore(state: Dictionary) -> void:
	for category in _catalogue:
		if not state.has(category):
			continue
		var value: Variant = state[category]
		if not (value is int and value >= 0):
			continue
		_levels[category] = mini(value, max_level(category))


## Strip every upgrade back to stock (all categories to level 0).
func reset() -> void:
	for category in _levels:
		_levels[category] = 0


func _fail(balance: int, reason: String) -> Dictionary:
	return {
		"success": false,
		"cost": 0,
		"new_balance": balance,
		"new_level": -1,
		"reason": reason,
	}


## Coerce a catalogue value into a clean Array[int] of positive tier prices.
## Returns an empty Array for malformed rows so a bad entry can't crash the shop.
## A tier price must be strictly positive (per the contract above): a zero-cost
## tier would hand out a free permanent upgrade, so reject the whole row.
func _clean_tiers(tiers: Variant) -> Array:
	if not (tiers is Array):
		return []
	var out: Array = []
	for price in tiers:
		if not (price is int) or price <= 0:
			return []
		out.append(price)
	return out
