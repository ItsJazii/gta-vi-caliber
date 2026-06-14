class_name HitContractBoard
extends Node3D
## A walk-up assassination-contract board — the genre's signature "take the hit, move
## the market" loop (cf. GTA V's Lester assassinations): face it, press interact to
## ACCEPT the next contract, then press again to COMPLETE it (the hit's done). On
## completion you're paid the contract's reward and the kill sends a SHOCK through the
## live stock market, so a player who invested first cashes in on the swing. Surfaces
## the unit-tested HitContract model and self-wires by group (interactables /
## player_stats) — no plumbing beyond dropping the node.
##
## The Interactable contract (see Interaction): joins group "interactables" and
## answers interact_prompt() + interact(player). Reward cash is resolved against the
## live wallet; the market shock is best-effort fed to whatever live market node is in
## the scene. HitContract itself never touches PlayerStats or StockMarket.

## Fired when the player takes a contract off the board (id, reward it will pay).
signal contract_accepted(id: String, reward: int)
## Fired when the hit is finished: the banked reward and the market shock that was
## produced (a {company_id, magnitude, spillover} descriptor, possibly applied live).
signal contract_completed(reward: int, market_effect: Dictionary)

## The live contract board. Public so a manage/HUD UI can read the offered jobs.
var contracts: HitContract

var _stats: Node = null
var _market: Node = null
var _objective_contract_id: String = ""


func _init() -> void:
	# Default constructor seeds a built-in board of market-moving hits, so there is
	# always work to offer the moment the node drops into a scene.
	contracts = HitContract.new()


func _ready() -> void:
	add_to_group("interactables")


## HUD hint: a complete prompt while a hit is in progress, otherwise an invite to
## take the next available contract. Degrades to a "cleared" line when nothing is left.
func interact_prompt() -> String:
	if contracts.has_active():
		return "Complete hit ($%d)" % contracts.reward_of(contracts.active())
	var next := _next_id()
	if next.is_empty():
		return "No contracts available"
	return "Take contract: %s ($%d)" % [next, contracts.reward_of(next)]


## First press accepts the next available contract; every later press completes the
## active hit, banks the reward, and fires off the market shock.
func interact(_player: Node) -> void:
	if contracts.has_active():
		_complete()
	else:
		_accept()


## Whether a contract is currently in progress, for a HUD readout.
func has_active() -> bool:
	return contracts != null and contracts.has_active()


## Lifetime reward cash from completed hits, for a HUD/probe readout.
func earned() -> int:
	return contracts.total_earned() if contracts != null else 0


## Take the next available contract off the board and announce it. No-op when the
## board is empty.
func _accept() -> void:
	var id := _next_id()
	if id.is_empty() or not contracts.accept(id):
		return
	_set_hit_objective(id)
	contract_accepted.emit(id, contracts.reward_of(id))


## Finish the active hit: bank the reward against PlayerStats, best-effort apply the
## resulting market shock to a live market node, then announce the completion.
func _complete() -> void:
	var id := contracts.active()
	var result: Dictionary = contracts.complete()
	if not result.get("success", false):
		return
	var reward: int = int(result["reward"])
	var effect: Dictionary = result.get("market_effect", {})
	var stats := _player_stats()
	if reward > 0 and stats != null and stats.has_method("add_money"):
		stats.add_money(reward)
	_clear_hit_objective(id)
	_apply_market_effect(effect)
	contract_completed.emit(reward, effect)


func _set_hit_objective(id: String) -> void:
	var stats := _player_stats()
	if stats == null or not stats.has_method("set_objective"):
		return
	stats.set_objective(_objective_text(id), Vector3.ZERO, false)
	_objective_contract_id = id


func _clear_hit_objective(id: String) -> void:
	var stats := _player_stats()
	if stats == null or not stats.has_method("clear_objective") or _objective_contract_id != id:
		return
	if not ("objective_title" in stats) or String(stats.objective_title) == _objective_text(id):
		stats.clear_objective()
	_objective_contract_id = ""


func _objective_text(id: String) -> String:
	var target := contracts.target_of(id) if contracts != null else ""
	return "Complete hit: %s" % (target if not target.is_empty() else id)


## Feed the completed contract's {company_id, magnitude, spillover} shock to a live
## market node if one is in the scene. Best-effort: the reward payout above does not
## depend on this, and a scene without a market simply skips the shock.
func _apply_market_effect(effect: Dictionary) -> void:
	if effect.is_empty():
		return
	var market := _market_node()
	if market == null:
		return
	if market.has_method("apply_hit_effect"):
		market.apply_hit_effect(effect)
		return
	var book: Variant = market.get("market")
	if book != null and book.has_method("apply_rivalry_shock"):
		book.apply_rivalry_shock(effect["company_id"], effect["magnitude"], effect["spillover"])


## First still-available contract id, or "" when the board is exhausted.
func _next_id() -> String:
	var pool := contracts.available()
	return str(pool[0]) if not pool.is_empty() else ""


func _player_stats() -> Node:
	if _stats == null or not is_instance_valid(_stats):
		_stats = get_tree().get_first_node_in_group("player_stats")
	return _stats


## Locate a live market node by capability: one that consumes a hit effect directly,
## or one that owns a StockMarket-like `market` we can shock. Cached once found.
func _market_node() -> Node:
	if _market != null and is_instance_valid(_market):
		return _market
	for node: Node in _market_candidates():
		if _is_market(node):
			_market = node
			break
	return _market


func _market_candidates() -> Array:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return []
	return tree.root.find_children("*", "Node", true, false)


func _is_market(node: Node) -> bool:
	if node.has_method("apply_hit_effect"):
		return true
	var book: Variant = node.get("market")
	return book != null and book.has_method("apply_rivalry_shock")
