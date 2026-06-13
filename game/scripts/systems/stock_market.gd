class_name StockMarket
extends RefCounted
## Pure equities-market model — a roster of tradeable companies whose share prices
## react to in-world EVENTS, so the player can profit by moving the market and then
## trading on it (the genre's signature "assassinate a rival CEO, watch the
## competitor's stock spike" loop). Distinct from ContrabandMarket: that is
## commodity arbitrage across districts; this is event-driven equities with a
## tracked portfolio.
##
## No nodes, no scene access: a world controller owns one, feeds it events (a
## mission kill, a heist on a bank, a district lost to a gang) and the player's
## wallet balance on a trade, then applies the returned spend/proceeds itself — so
## the price / event / portfolio curves stay unit-testable headless
## (tests/unit/test_stock_market.gd).
##
## Each company is a Dictionary {id, sector, base_price, volatility}. Garbage
## entries (missing id, non-int/non-positive price, out-of-range volatility) are
## dropped at construction. Current price is base_price * a per-company multiplier
## that starts at 1.0 and is moved by events (scaled by the company's volatility)
## and by fluctuate() drift, clamped to [MULTIPLIER_MIN, MULTIPLIER_MAX]. Trades
## never mutate the wallet; the caller applies the result.

## Band a company's price multiplier can sit in: base_price * [MIN, MAX]. Equities
## swing harder than contraband, so the band is wide.
const MULTIPLIER_MIN: float = 0.1
const MULTIPLIER_MAX: float = 8.0

## How far a single fluctuate() step may nudge a multiplier at volatility 1.0.
const FLUCTUATE_SWING: float = 0.15

## id -> {sector: String, base_price: int, volatility: float}. Insertion-ordered.
var _companies: Dictionary = {}

## id -> current price multiplier (float). Seeded to 1.0 on registration.
var _multipliers: Dictionary = {}

## id -> {qty: int >= 0, avg_cost: float}. The player's portfolio. Empty positions
## are erased so shares_held() / holdings stay tidy.
var _holdings: Dictionary = {}

## Running total of realized profit/loss from sells (proceeds minus cost basis).
var _realized: int = 0


func _init(companies: Array = []) -> void:
	var source: Array = companies if not companies.is_empty() else default_companies()
	for entry: Variant in source:
		_register(entry)


## The built-in roster used when an empty list is passed: a spread of sectors so
## sector-wide and rivalry shocks have something to ripple through.
static func default_companies() -> Array:
	return [
		{"id": "augury_air", "sector": "aviation", "base_price": 42, "volatility": 0.7},
		{"id": "pelican_air", "sector": "aviation", "base_price": 38, "volatility": 0.7},
		{"id": "bittn_tech", "sector": "tech", "base_price": 120, "volatility": 0.9},
		{"id": "fruit_systems", "sector": "tech", "base_price": 210, "volatility": 0.6},
		{"id": "cluckin_co", "sector": "food", "base_price": 24, "volatility": 0.3},
		{"id": "merryweather", "sector": "defense", "base_price": 88, "volatility": 0.8},
		{"id": "lombank", "sector": "banking", "base_price": 64, "volatility": 0.5},
	]


func company_count() -> int:
	return _companies.size()


## True if the company id exists in the roster.
func has_company(id: String) -> bool:
	return _companies.has(id)


## Every distinct sector in the roster, in first-seen order.
func sectors() -> Array:
	var seen: Array = []
	for id: Variant in _companies:
		var sector: String = _companies[id]["sector"]
		if not seen.has(sector):
			seen.append(sector)
	return seen


## Base (event-neutral) share price of a company, or -1 if the id is unknown.
func base_price(id: String) -> int:
	if not _companies.has(id):
		return -1
	return _companies[id]["base_price"]


## A company's volatility in [0, 1] (how hard it reacts to events / drift), or 0.0
## if the id is unknown.
func volatility(id: String) -> float:
	if not _companies.has(id):
		return 0.0
	return _companies[id]["volatility"]


## Sector a company belongs to, or "" if the id is unknown.
func sector_of(id: String) -> String:
	if not _companies.has(id):
		return ""
	return _companies[id]["sector"]


## Current price multiplier of a company (1.0 == neutral), or 1.0 if unknown.
func multiplier(id: String) -> float:
	return _multipliers.get(id, 1.0)


## Current share price: base_price * the company multiplier, rounded to whole
## currency and floored at 1 (a listed share is never free). -1 for unknown id.
func price(id: String) -> int:
	var base := base_price(id)
	if base < 0:
		return -1
	return maxi(1, int(round(float(base) * multiplier(id))))


## Move one company's price by `magnitude` (a signed fraction, e.g. +0.30 = a 30%
## upward shock intent), scaled by the company's volatility so jumpy stocks react
## harder than stable ones. Multiplier stays clamped to the band. No-op / false for
## an unknown id or a zero net move. Returns true if the company exists.
func apply_company_event(id: String, magnitude: float) -> bool:
	if not _companies.has(id):
		return false
	_move(id, magnitude)
	return true


## Shock an entire sector at once (e.g. an oil spill tanks all energy stocks).
## Returns the number of companies moved.
func apply_sector_event(sector: String, magnitude: float) -> int:
	var moved := 0
	for id: Variant in _companies:
		if _companies[id]["sector"] == sector:
			_move(id, magnitude)
			moved += 1
	return moved


## The signature move: a shock to one company that ripples to its sector RIVALS in
## the opposite direction (take out a competitor and the survivors gain share).
## `magnitude` hits the target; rivals get -magnitude * spillover. spillover is
## clamped to [0, 1]. No-op / false for an unknown id.
func apply_rivalry_shock(id: String, magnitude: float, spillover: float) -> bool:
	if not _companies.has(id):
		return false
	var sector: String = _companies[id]["sector"]
	var rival_mag := -magnitude * clampf(spillover, 0.0, 1.0)
	for other: Variant in _companies:
		if other == id:
			_move(id, magnitude)
		elif _companies[other]["sector"] == sector:
			_move(other, rival_mag)
	return true


## Resolve a buy against a wallet balance. Never mutates the wallet: the caller
## applies new_balance on success. On success the shares are added to the portfolio
## at a quantity-weighted average cost. Fails on unknown company, non-positive qty,
## or insufficient funds. Returns {success, cost, new_balance, reason}.
func buy(id: String, qty: int, balance: int) -> Dictionary:
	if not _companies.has(id):
		return _fail(balance, "unknown company: %s" % id)
	if qty <= 0:
		return _fail(balance, "qty must be positive: %d" % qty)
	var unit := price(id)
	var cost := unit * qty
	if balance < cost:
		return _fail(balance, "insufficient funds: need %d, have %d" % [cost, balance])
	var prev_qty := shares_held(id)
	var prev_basis := avg_cost(id) * float(prev_qty)
	var new_qty := prev_qty + qty
	_holdings[id] = {"qty": new_qty, "avg_cost": (prev_basis + float(cost)) / float(new_qty)}
	return {"success": true, "cost": cost, "new_balance": balance - cost, "reason": ""}


## Sell shares the player holds at the current price. Never mutates the wallet: the
## caller adds proceeds. Updates the portfolio and the running realized P/L. Fails
## on unknown company, non-positive qty, or selling more than held. Returns
## {success, proceeds, realized, reason} (realized = profit/loss on this sale).
func sell(id: String, qty: int) -> Dictionary:
	if not _companies.has(id):
		return _fail_sell("unknown company: %s" % id)
	if qty <= 0:
		return _fail_sell("qty must be positive: %d" % qty)
	var held := shares_held(id)
	if qty > held:
		return _fail_sell("not enough shares: have %d, tried to sell %d" % [held, qty])
	var proceeds := price(id) * qty
	var realized := int(round((float(price(id)) - avg_cost(id)) * float(qty)))
	_realized += realized
	var remaining := held - qty
	if remaining <= 0:
		_holdings.erase(id)
	else:
		_holdings[id]["qty"] = remaining
	return {"success": true, "proceeds": proceeds, "realized": realized, "reason": ""}


## Shares of a company the player currently holds (0 if none / unknown).
func shares_held(id: String) -> int:
	if not _holdings.has(id):
		return 0
	return _holdings[id]["qty"]


## Quantity-weighted average price the player paid for their current position in a
## company (0.0 if none / unknown).
func avg_cost(id: String) -> float:
	if not _holdings.has(id):
		return 0.0
	return _holdings[id]["avg_cost"]


## Market value of the whole portfolio at current prices.
func portfolio_value() -> int:
	var total := 0
	for id: Variant in _holdings:
		total += price(id) * shares_held(id)
	return total


## What the player paid for everything they currently hold (their cost basis).
func total_invested() -> int:
	var total := 0.0
	for id: Variant in _holdings:
		total += avg_cost(id) * float(shares_held(id))
	return int(round(total))


## Paper profit/loss on open positions: current value minus cost basis.
func unrealized_gain() -> int:
	return portfolio_value() - total_invested()


## Locked-in profit/loss from everything sold so far.
func realized_gain() -> int:
	return _realized


## Nudge every company's multiplier a little so prices drift between events.
## Deterministic for a given rng seed; each company's swing scales with its
## volatility. Multipliers stay clamped to the band. No-op without an rng.
func fluctuate(rng: RandomNumberGenerator, intensity: float) -> void:
	if rng == null or intensity <= 0.0:
		return
	for id: Variant in _companies:
		var swing := FLUCTUATE_SWING * intensity * volatility(id)
		if swing <= 0.0:
			continue
		var delta := rng.randf_range(-swing, swing)
		_multipliers[id] = clampf(multiplier(id) + delta, MULTIPLIER_MIN, MULTIPLIER_MAX)


## Deterministic-test helper: a fresh rng seeded with `seed_value`.
static func make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Apply a volatility-scaled multiplicative move to one company, clamped to band.
func _move(id: String, magnitude: float) -> void:
	var effective := magnitude * volatility(id)
	if is_zero_approx(effective):
		return
	_multipliers[id] = clampf(multiplier(id) * (1.0 + effective), MULTIPLIER_MIN, MULTIPLIER_MAX)


func _fail(balance: int, reason: String) -> Dictionary:
	return {"success": false, "cost": 0, "new_balance": balance, "reason": reason}


func _fail_sell(reason: String) -> Dictionary:
	return {"success": false, "proceeds": 0, "realized": 0, "reason": reason}


## Validate and register one company entry; malformed entries are silently dropped.
func _register(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var dict: Dictionary = entry
	if not (dict.has("id") and dict.has("base_price")):
		return
	var id: String = str(dict["id"])
	if id.is_empty() or _companies.has(id):
		return
	var raw_price: Variant = dict["base_price"]
	if not (raw_price is int) or int(raw_price) <= 0:
		return
	var vol := clampf(float(dict.get("volatility", 0.5)), 0.0, 1.0)
	_companies[id] = {
		"sector": str(dict.get("sector", "misc")),
		"base_price": int(raw_price),
		"volatility": vol,
	}
	_multipliers[id] = 1.0
