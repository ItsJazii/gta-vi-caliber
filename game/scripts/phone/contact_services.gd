class_name ContactServices
extends RefCounted
## Pure phone contact-services model — the "call a contact to pull a favour" loop:
## ring the right friend to lower your wanted level, have a car delivered, get a
## weapon drop, a chopper pickup, or armed backup. Each service has a cash cost and
## a cooldown, and only fires if the contact actually picks up (gate it with
## PhoneContacts.will_answer). Distinct from PhoneContacts (presence/roster) and
## SocialFeed (procedural posts): this is the gameplay-ability layer.
##
## No nodes, no scene access: the phone UI owns one, checks reachability via
## PhoneContacts, calls request() against the wallet (caller applies the returned
## spend), and triggers the matching effect — so the cost/cooldown math stays
## unit-tested headless (tests/unit/test_contact_services.gd).
##
## Each service is a Dictionary {id, contact, kind, cost, cooldown}. Malformed
## entries (missing id, non-positive cost) are dropped.

## id -> {contact, kind, cost:int, cooldown:float, last_used:float}.
var _services: Dictionary = {}


func _init(services: Array = []) -> void:
	var source: Array = services if not services.is_empty() else default_services()
	for entry: Variant in source:
		_register(entry)


## Built-in services, each tied to a PhoneContacts roster friend.
static func default_services() -> Array:
	return [
		{"id": "lower_wanted", "contact": "Lena", "kind": "heat", "cost": 5000, "cooldown": 300.0},
		{"id": "mechanic", "contact": "Devin", "kind": "vehicle", "cost": 1000, "cooldown": 120.0},
		{
			"id": "weapon_drop",
			"contact": "Priya",
			"kind": "weapons",
			"cost": 2500,
			"cooldown": 180.0
		},
		{
			"id": "heli_pickup",
			"contact": "Coop",
			"kind": "transport",
			"cost": 3000,
			"cooldown": 240.0
		},
		{"id": "backup", "contact": "Tomas", "kind": "combat", "cost": 4000, "cooldown": 360.0},
	]


func service_count() -> int:
	return _services.size()


func has_service(id: String) -> bool:
	return _services.has(id)


func ids() -> Array:
	return _services.keys()


## The contact who provides a service ("" if unknown).
func contact_of(id: String) -> String:
	if not _services.has(id):
		return ""
	return _services[id]["contact"]


## Cash cost of a service (-1 if unknown).
func cost_of(id: String) -> int:
	if not _services.has(id):
		return -1
	return _services[id]["cost"]


## Effect category of a service ("" if unknown).
func kind_of(id: String) -> String:
	if not _services.has(id):
		return ""
	return _services[id]["kind"]


## Seconds left on a service's cooldown at time `now` (0 when ready / unknown).
func cooldown_remaining(id: String, now: float) -> float:
	if not _services.has(id):
		return 0.0
	return maxf(0.0, _services[id]["cooldown"] - (now - _services[id]["last_used"]))


## Whether a service's cooldown has elapsed.
func is_ready(id: String, now: float) -> bool:
	return _services.has(id) and cooldown_remaining(id, now) <= 0.0


## Whether a service can be requested right now: known, the contact is reachable,
## off cooldown, and affordable.
func can_use(id: String, now: float, balance: int, reachable: bool) -> bool:
	if not _services.has(id) or not reachable:
		return false
	return is_ready(id, now) and balance >= _services[id]["cost"]


## Request a service. `reachable` is whether the contact answered (compute from
## PhoneContacts.will_answer). Never mutates the wallet: the caller applies
## new_balance and triggers the effect on success. Returns
## {success, cost, new_balance, kind, reason}.
func request(id: String, now: float, balance: int, reachable: bool = true) -> Dictionary:
	if not _services.has(id):
		return _fail(balance, "no such service: %s" % id)
	if not reachable:
		return _fail(balance, "%s didn't pick up" % contact_of(id))
	if not is_ready(id, now):
		return _fail(balance, "on cooldown (%ds left)" % int(ceil(cooldown_remaining(id, now))))
	var cost: int = _services[id]["cost"]
	if balance < cost:
		return _fail(balance, "insufficient funds: need %d, have %d" % [cost, balance])
	_services[id]["last_used"] = now
	return {
		"success": true,
		"cost": cost,
		"new_balance": balance - cost,
		"kind": _services[id]["kind"],
		"reason": "",
	}


## Clear all cooldowns (new game / chapter).
func reset_cooldowns() -> void:
	for id: Variant in _services:
		_services[id]["last_used"] = -INF


func _fail(balance: int, reason: String) -> Dictionary:
	return {"success": false, "cost": 0, "new_balance": balance, "kind": "", "reason": reason}


func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not dict.has("id"):
		return
	var id: String = str(dict["id"])
	var cost := int(dict.get("cost", 0))
	if id.is_empty() or _services.has(id) or cost <= 0:
		return
	_services[id] = {
		"contact": str(dict.get("contact", "Unknown")),
		"kind": str(dict.get("kind", "misc")),
		"cost": cost,
		"cooldown": maxf(0.0, float(dict.get("cooldown", 60.0))),
		"last_used": -INF,
	}
