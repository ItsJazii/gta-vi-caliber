class_name HitContract
extends RefCounted
## Pure assassination-contract board — the genre's signature "do the hit, move the
## market" loop (GTA V's Lester assassinations): each contract names a target, pays
## a reward, and on completion emits a STOCK-MARKET SHOCK the caller applies to a
## StockMarket, so the player can invest first and cash in on the swing. Distinct
## from SideJob (quick taxi/delivery/vigilante odd-jobs): these are premeditated,
## single-target, market-moving hits offered from a board.
##
## Deliberately decoupled from StockMarket: complete() returns a {company_id,
## magnitude, spillover} effect descriptor and the caller feeds it to
## StockMarket.apply_rivalry_shock — the contract model never imports the market,
## so both stay independently unit-tested headless
## (tests/unit/test_hit_contract.gd).
##
## A contract is a Dictionary {id, target, company_id, magnitude, spillover,
## reward, difficulty}. Malformed entries (missing/empty id, non-positive reward)
## are dropped at construction. One contract is active at a time; finished ones
## leave the available pool.

## id -> contract Dictionary. Insertion-ordered.
var _contracts: Dictionary = {}

## Currently accepted contract id, or "" when none is active.
var _active: String = ""

## Set of completed contract ids (id -> true).
var _completed: Dictionary = {}

## Lifetime reward cash earned from completed hits.
var _earned: int = 0


func _init(contracts: Array = []) -> void:
	var source: Array = contracts if not contracts.is_empty() else default_contracts()
	for entry: Variant in source:
		_register(entry)


## Built-in board, tied to StockMarket's default roster so the cross-system loop
## works out of the box: each hit tanks the target's company, and the rivalry
## spillover pumps its sector competitors.
static func default_contracts() -> Array:
	return [
		{
			"id": "tech_takedown",
			"target": "Avery Kohl",
			"company_id": "bittn_tech",
			"magnitude": -0.5,
			"spillover": 0.8,
			"reward": 25000,
			"difficulty": 4,
		},
		{
			"id": "airline_war",
			"target": "Don Percival",
			"company_id": "pelican_air",
			"magnitude": -0.4,
			"spillover": 1.0,
			"reward": 18000,
			"difficulty": 3,
		},
		{
			"id": "bank_reckoning",
			"target": "Cliff Lombard",
			"company_id": "lombank",
			"magnitude": -0.3,
			"spillover": 0.5,
			"reward": 30000,
			"difficulty": 5,
		},
	]


func contract_count() -> int:
	return _contracts.size()


## True if the contract id exists on the board.
func has_contract(id: String) -> bool:
	return _contracts.has(id)


## Every contract id, in first-seen order.
func ids() -> Array:
	return _contracts.keys()


## Reward cash a contract pays, or -1 for an unknown id.
func reward_of(id: String) -> int:
	if not _contracts.has(id):
		return -1
	return _contracts[id]["reward"]


## The market shock a contract produces, as {company_id, magnitude, spillover} —
## feed it to StockMarket.apply_rivalry_shock(). Empty {} for an unknown id. Lets a
## caller preview the swing and invest before taking the job.
func market_effect_of(id: String) -> Dictionary:
	if not _contracts.has(id):
		return {}
	var c: Dictionary = _contracts[id]
	return {"company_id": c["company_id"], "magnitude": c["magnitude"], "spillover": c["spillover"]}


## Contract ids the player can still take: not already completed and not the one
## currently active.
func available() -> Array:
	var out: Array = []
	for id: Variant in _contracts:
		if not _completed.has(id) and id != _active:
			out.append(id)
	return out


## Take a contract. Fails on an unknown id, an already-completed contract, or while
## another is active (finish or abandon it first). Returns true on success.
func accept(id: String) -> bool:
	if not _contracts.has(id) or _completed.has(id) or not _active.is_empty():
		return false
	_active = id
	return true


## The active contract id, or "" if none.
func active() -> String:
	return _active


func has_active() -> bool:
	return not _active.is_empty()


## Drop the active contract back into the pool without completing it. Returns the
## abandoned id, or "" if none was active.
func abandon() -> String:
	var prior := _active
	_active = ""
	return prior


## Complete the active contract: bank its reward, mark it done, and return the
## market shock for the caller to apply. Returns
## {success, reward, market_effect, reason}; fails (success=false) when nothing is
## active.
func complete() -> Dictionary:
	if _active.is_empty():
		return {"success": false, "reward": 0, "market_effect": {}, "reason": "no active contract"}
	var id := _active
	var reward: int = _contracts[id]["reward"]
	var effect := market_effect_of(id)
	_completed[id] = true
	_earned += reward
	_active = ""
	return {"success": true, "reward": reward, "market_effect": effect, "reason": ""}


## True if a contract has been completed.
func is_completed(id: String) -> bool:
	return _completed.has(id)


func completed_count() -> int:
	return _completed.size()


## Lifetime reward cash from completed hits.
func total_earned() -> int:
	return _earned


## Validate and register one contract; malformed entries are silently dropped.
func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not dict.has("id"):
		return
	var id: String = str(dict["id"])
	if id.is_empty() or _contracts.has(id):
		return
	var raw_reward: Variant = dict.get("reward", 0)
	if not (raw_reward is int) or int(raw_reward) <= 0:
		return
	_contracts[id] = {
		"target": str(dict.get("target", "Unknown")),
		"company_id": str(dict.get("company_id", "")),
		"magnitude": float(dict.get("magnitude", 0.0)),
		"spillover": clampf(float(dict.get("spillover", 0.0)), 0.0, 1.0),
		"reward": int(raw_reward),
		"difficulty": clampi(int(dict.get("difficulty", 1)), 1, 5),
	}
