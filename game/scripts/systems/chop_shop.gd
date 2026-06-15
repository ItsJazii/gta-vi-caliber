class_name ChopShop
extends RefCounted
## Pure chop-shop / import-export valuation model — fence a (stolen) vehicle for
## cash priced by its CLASS, its CONDITION (fed from VehicleHealth.health_fraction),
## a rotating "most-wanted" orders list that pays a demand bonus, and a heat
## discount if the car is hot. Distinct from VehicleModShop (upgrades) and
## GarageStorage (storage): this is the deliver-a-car-for-money loop.
##
## No nodes, no scene access: a chop-shop trigger owns one, reads the delivered
## vehicle's class + condition, and applies the returned payout to the wallet — so
## the valuation/demand math stays unit-tested headless
## (tests/unit/test_chop_shop.gd). The orders list rotation takes an injected RNG so
## it's deterministic.
##
## Each class is a Dictionary {id, base}; base is its pristine fence value.
## Malformed entries (missing/empty id, non-positive base) are dropped.

## Even a totalled car is worth this fraction of base (scrap).
const SCRAP_FLOOR: float = 0.2
## Payout multiplier for a class that's currently on the most-wanted orders list.
const REQUEST_BONUS: float = 1.5
## Fraction shaved off when the delivered car is hot (freshly stolen / wanted).
const HEAT_DISCOUNT: float = 0.25

## id -> base value (int > 0). Insertion-ordered.
var _classes: Dictionary = {}
## Set of class ids currently requested (id -> true).
var _requests: Dictionary = {}
var _earned: int = 0
var _deliveries: int = 0


func _init(classes: Array = []) -> void:
	var source: Array = classes if not classes.is_empty() else default_classes()
	for entry: Variant in source:
		_register(entry)


## The built-in class price list (pristine FENCE values, not showroom prices).
## A fence pays a fraction of street value, so these sit well below the shop's
## retail tags (a Sports Car sells for 60000 in ShopModel) — fencing a stolen one
## pristine pays 14000, scaling down with damage and the hot/heat discount. Tuned
## against the wider economy so a routine chop lands near a robbery/race payout
## (500-2500) for the common classes, while a clean super tops out at its 30000 base
## (hit-contract tier). The top tier is held off the most-wanted demand board (see
## ChopShopTrigger.non_requestable_classes), so the 1.5x REQUEST_BONUS can't push a super
## into heist territory — it stays a rare hit-contract-tier spike rather than the old
## values that dwarfed every other earner. Ordering (compact < bike < sedan < suv <
## muscle < sports < super) is preserved.
static func default_classes() -> Array:
	return [
		{"id": "compact", "base": 2000},
		{"id": "sedan", "base": 3500},
		{"id": "bike", "base": 3000},
		{"id": "suv", "base": 5000},
		{"id": "muscle", "base": 8000},
		{"id": "sports", "base": 14000},
		{"id": "super", "base": 30000},
	]


func class_count() -> int:
	return _classes.size()


func has_class(id: String) -> bool:
	return _classes.has(id)


func ids() -> Array:
	return _classes.keys()


## Pristine fence value of a class, or -1 if unknown.
func base_value_of(id: String) -> int:
	if not _classes.has(id):
		return -1
	return _classes[id]["base"]


## Fence value for a class at `condition` (0..1, e.g. VehicleHealth.health_fraction):
## base, scaled from SCRAP_FLOOR (wrecked) up to full (pristine), times the demand
## bonus if the class is currently requested. 0 for an unknown class.
func value(id: String, condition: float) -> int:
	return int(round(_value_exact(id, condition, 1.0)))


## The unrounded fence value: base * condition_factor * demand * heat_factor.
## Both value() and deliver() round THIS once, so the hot discount no longer
## double-rounds (round(round(x) * 0.75)) and a wrecked/discounted/requested combo
## is computed in a single exact pass. 0.0 for an unknown class.
func _value_exact(id: String, condition: float, heat_factor: float) -> float:
	if not _classes.has(id):
		return 0.0
	var cond := clampf(condition, 0.0, 1.0)
	var condition_factor := SCRAP_FLOOR + (1.0 - SCRAP_FLOOR) * cond
	var demand := REQUEST_BONUS if is_requested(id) else 1.0
	return float(_classes[id]["base"]) * condition_factor * demand * heat_factor


## Whether a class is on the current most-wanted orders list.
func is_requested(id: String) -> bool:
	return _requests.has(id)


## The current most-wanted class ids.
func requested() -> Array:
	return _requests.keys()


## Set the most-wanted orders directly (ignores unknown class ids).
func set_requests(class_ids: Array) -> void:
	_requests.clear()
	for raw: Variant in class_ids:
		var id := str(raw)
		if _classes.has(id):
			_requests[id] = true


## Roll a fresh set of `count` distinct most-wanted classes using rng, skipping any class
## in `exclude` (e.g. a top tier you never want demand-boosted, so its chop value can't be
## pushed past its base). Deterministic for a given seed. No-op without an rng.
func rotate_requests(rng: RandomNumberGenerator, count: int, exclude: Array = []) -> void:
	if rng == null:
		return
	var skip: Dictionary = {}
	for raw: Variant in exclude:
		skip[str(raw)] = true
	var pool: Array = []
	for id: Variant in _classes.keys():
		if not skip.has(str(id)):
			pool.append(id)
	_shuffle(rng, pool)
	_requests.clear()
	for i in range(mini(maxi(count, 0), pool.size())):
		_requests[pool[i]] = true


## Fence a delivered vehicle. Pays value() (heat-discounted if `hot`), banks it,
## and fulfils the order (removing the class from the most-wanted list) so the next
## one of that class pays base. Returns {accepted, payout, was_requested, reason}.
func deliver(id: String, condition: float, hot: bool = false) -> Dictionary:
	if not _classes.has(id):
		return {"accepted": false, "payout": 0, "was_requested": false, "reason": "unknown class"}
	var was_requested := is_requested(id)
	var heat_factor := (1.0 - HEAT_DISCOUNT) if hot else 1.0
	var payout := int(round(_value_exact(id, condition, heat_factor)))
	_requests.erase(id)
	_earned += payout
	_deliveries += 1
	return {"accepted": true, "payout": payout, "was_requested": was_requested, "reason": ""}


func total_earned() -> int:
	return _earned


func deliveries_count() -> int:
	return _deliveries


func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not (dict.has("id") and dict.has("base")):
		return
	var id: String = str(dict["id"])
	var raw_base: Variant = dict["base"]
	if id.is_empty() or _classes.has(id) or not (raw_base is int) or int(raw_base) <= 0:
		return
	_classes[id] = {"base": int(raw_base)}
