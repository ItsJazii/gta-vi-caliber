extends SceneTree
## Runtime wiring + economy probe for the live TurfClaim point in miami.tscn.
##
## Boots the real map, asserts the claim point is a registered interactable, then drives
## the claim loop against the LIVE player_stats wallet: each interact() spends claim_cost
## and buys influence, and after enough presses the district flips to player ownership
## (district_claimed fires, owner_of -> "player"). A final press once owned must be a
## no-op that charges nothing. Self-contained — does not touch other probes. Run:
##   godot --headless --path game --script res://tests/turf_claim_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90
## Cash fronted so the probe exercises the claim path, not the can't-afford branch.
const FRONT_MONEY: int = 200000
## Presses to drive: 0.34 each clamps to full at 3, so 4 also proves the owned no-op.
const CLAIM_PRESSES: int = 4

var _scene: Node = null
var _frames: int = 0
var _claimed: bool = false


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("turf claim probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var err := _verify()
	if err.is_empty():
		print("turf claim probe: OK (owned %s)" % str(_claimed))
		quit(0)
	else:
		push_error("turf claim probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var point := _scene.find_child("TurfClaim", true, false) as TurfClaim
	if point == null:
		return "TurfClaim not present in miami.tscn"
	var wiring_err := _verify_wiring(point)
	if not wiring_err.is_empty():
		return wiring_err
	return _verify_loop(point)


## The point is live, owns its models, and answers the interactable contract unowned.
func _verify_wiring(point: TurfClaim) -> String:
	if point.territory == null or point.factions == null:
		return "TurfClaim / its models not present in miami.tscn"
	if not point.is_in_group("interactables"):
		return "claim point not in group 'interactables'"
	if not point.has_method("interact") or not point.has_method("interact_prompt"):
		return "claim point does not answer the interactable contract"
	if point.owns_district():
		return "claim point starts already owned (should claim via interact)"
	return ""


## Each press spends claim_cost + raises influence; enough presses flip to ownership,
## and a further press once owned charges nothing.
func _verify_loop(point: TurfClaim) -> String:
	var player := get_first_node_in_group("player")
	var stats := get_first_node_in_group("player_stats")
	if player == null or stats == null or not ("money" in stats):
		return "no live player / player_stats node"
	if stats.has_method("add_money"):
		stats.add_money(FRONT_MONEY)
	point.district_claimed.connect(func(_id: String) -> void: _claimed = true)
	return _drive_presses(point, player, stats)


## Run the press sequence: charge + influence rise each press until owned, then no-op.
func _drive_presses(point: TurfClaim, player: Node, stats: Node) -> String:
	for i in range(CLAIM_PRESSES):
		var owned_before: bool = point.owns_district()
		var money_before: int = int(stats.money)
		var influence_before: float = point.influence()
		point.interact(player)
		var step_err := _check_press(point, stats, owned_before, money_before, influence_before)
		if not step_err.is_empty():
			return step_err
	if not point.owns_district() or point.territory.owner_of(point.district_id) != "player":
		return "never reached ownership after %d presses" % CLAIM_PRESSES
	if not _claimed:
		return "district_claimed never fired"
	print(
		(
			"turf claim probe: %s claimed, influence %.2f, money %d"
			% [point.district_id, point.influence(), int(stats.money)]
		)
	)
	return ""


## One press: pre-ownership must charge + raise influence; post-ownership a free no-op.
func _check_press(
	point: TurfClaim, stats: Node, owned_before: bool, money_before: int, influence_before: float
) -> String:
	if owned_before:
		if int(stats.money) != money_before:
			return (
				"owned press charged the wallet (money %d->%d)" % [money_before, int(stats.money)]
			)
		return ""
	if int(stats.money) != money_before - point.claim_cost:
		return "press did not charge claim_cost (money %d->%d)" % [money_before, int(stats.money)]
	if point.influence() <= influence_before:
		return "influence did not climb (%.2f->%.2f)" % [influence_before, point.influence()]
	return ""
