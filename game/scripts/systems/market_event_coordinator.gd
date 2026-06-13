class_name MarketEventCoordinator
extends Node
## Self-wiring coordinator that turns the StockMarket into a LIVING, reactive
## backdrop. It owns a StockMarket and wires itself to the live `wanted` group: a
## rising wanted level rallies defense/security stocks (a crime spree drives
## security demand). Completed HitContracts are applied through apply_hit_effect(),
## closing the assassinate-to-move-the-market loop. Follows the repo's self-wiring
## pattern (cf. PaySprayShop): drop the node in a scene and it finds its
## collaborators by group — no per-scene plumbing.
##
## Owns the market so a future brokerage UI can read/trade it via market. The pure
## models stay headless-unit-tested; this node's wiring is exercised by a runtime
## probe (tests/market_event_probe.gd).

## Emitted whenever a world event moves the market, with a short reason tag.
signal market_shocked(reason: String)

## Sector that rallies as the player's wanted level climbs.
@export var defense_sector: String = "defense"
## Market move applied per additional wanted star gained.
@export var escalation_strength: float = 0.08

## The live market. Public so a brokerage UI / ticker can read prices.
var market: StockMarket

var _last_stars: int = 0


func _init() -> void:
	market = StockMarket.new()


func _ready() -> void:
	# The `wanted` node may be added after us; wire on the next idle frame.
	call_deferred("_connect_wanted")


## Find the wanted tracker by group and subscribe to its star changes. Defensive:
## a scene without a wanted system simply leaves the market event-free.
func _connect_wanted() -> void:
	var tracker := get_tree().get_first_node_in_group("wanted")
	if tracker == null or not tracker.has_signal("stars_changed"):
		return
	tracker.connect("stars_changed", _on_stars_changed)
	if tracker.has_method("stars"):
		_last_stars = tracker.stars()


func _on_stars_changed(stars: int) -> void:
	if stars > _last_stars:
		var gained := stars - _last_stars
		market.apply_sector_event(defense_sector, escalation_strength * float(gained))
		market_shocked.emit("wanted+%d" % gained)
	_last_stars = stars


## Apply a completed HitContract's market effect (the invest-then-hit loop): feed
## the {company_id, magnitude, spillover} returned by HitContract.complete().
## Returns true if the shock was applied.
func apply_hit_effect(effect: Dictionary) -> bool:
	if not (effect.has("company_id") and effect.has("magnitude") and effect.has("spillover")):
		return false
	var applied: bool = market.apply_rivalry_shock(
		effect["company_id"], effect["magnitude"], effect["spillover"]
	)
	if applied:
		market_shocked.emit("hit:%s" % effect["company_id"])
	return applied
