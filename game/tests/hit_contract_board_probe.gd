extends SceneTree
## Runtime wiring + payout probe for the live HitContractBoard in miami.tscn.
##
## Boots the real map, asserts the board is a registered interactable, then drives the
## hit loop against the LIVE player_stats wallet: interact once to ACCEPT the next
## contract (a hit goes active), interact again to COMPLETE it (the wallet rises by the
## contract's reward and the kill is logged). Self-contained — does not touch
## miami_wiring_probe. Run:
##   godot --headless --path game --script res://tests/hit_contract_board_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90

var _scene: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("hit contract board probe: scene failed to load")
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
		quit(0)
	else:
		push_error("hit contract board probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var board := _scene.find_child("HitContractBoard", true, false) as HitContractBoard
	if board == null or board.contracts == null:
		print("HitContractBoard not present in miami.tscn")
		return "HitContractBoard not present in miami.tscn"
	var wiring_err := _verify_wiring(board)
	if not wiring_err.is_empty():
		return wiring_err
	return _verify_loop(board)


## The board is live, owns a model with work to offer, and answers the interactable
## contract as a registered interactable.
func _verify_wiring(board: HitContractBoard) -> String:
	if not board.is_in_group("interactables"):
		return "board not in group 'interactables'"
	if not board.has_method("interact") or not board.has_method("interact_prompt"):
		return "board does not answer the interactable contract"
	if board.has_active():
		return "board starts with an active hit (should accept on first interact)"
	if board.contracts.available().is_empty():
		return "board has no contracts to offer"
	return ""


## accept -> complete round trip against the live wallet must pay out the reward.
func _verify_loop(board: HitContractBoard) -> String:
	var player := get_first_node_in_group("player")
	var stats := get_first_node_in_group("player_stats")
	if player == null or stats == null or not ("money" in stats):
		return "no live player / player_stats node"

	var next_id: String = str(board.contracts.available()[0])
	var reward: int = board.contracts.reward_of(next_id)
	var target: String = board.contracts.target_of(next_id)
	var money0: int = int(stats.money)
	var done0: int = board.contracts.completed_count()

	board.interact(player)
	var accept_err := _verify_accept(board, stats, next_id, target)
	if not accept_err.is_empty():
		return accept_err

	board.interact(player)
	var complete_err := _verify_complete(board, stats, target, money0, reward, done0)
	if not complete_err.is_empty():
		return complete_err
	print(
		(
			"hit contract board probe: OK (hit %s, money %d->%d, +$%d, earned %d)"
			% [next_id, money0, int(stats.money), reward, board.earned()]
		)
	)
	return ""


func _verify_accept(board: HitContractBoard, stats: Node, id: String, target: String) -> String:
	if not board.has_active():
		return "accept did not activate a hit (id %s)" % id
	if (
		not ("objective_title" in stats)
		or String(stats.objective_title) != "Complete hit: %s" % target
	):
		return "accept did not publish hit objective (got '%s')" % String(stats.objective_title)
	return ""


func _verify_complete(
	board: HitContractBoard, stats: Node, target: String, money0: int, reward: int, done0: int
) -> String:
	if board.has_active():
		return "complete left a hit active"
	if "objective_title" in stats and String(stats.objective_title) == "Complete hit: %s" % target:
		return "complete did not clear hit objective"
	if int(stats.money) != money0 + reward:
		return "reward not paid (money %d->%d, reward %d)" % [money0, int(stats.money), reward]
	if board.contracts.completed_count() != done0 + 1 or board.earned() < reward:
		return (
			"completion not recorded (done %d, earned %d)"
			% [board.contracts.completed_count(), board.earned()]
		)
	return ""
