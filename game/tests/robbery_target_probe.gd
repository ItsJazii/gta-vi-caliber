extends SceneTree
## Runtime wiring + economy/heat probe for the live RobberyTarget in miami.tscn.
##
## Boots the real map, asserts the target is present and registered as an
## interactable (so the player can walk up and press to rob it), seeds its loot
## RNG for a deterministic haul, snapshots the LIVE player_stats wallet and the
## live wanted node's star level, then robs it once via interact(). The holdup
## must credit the wallet by a value in [loot_min, loot_max] AND bump the wanted
## stars (the heat spike registered) — proving the FIRST crime-earns-money path
## feeds the wanted->police->responder loop. An immediate second interact() must
## be a no-op (still cooling down: wallet unchanged). Self-contained. Run headless:
##   godot --headless --path game --script res://tests/robbery_target_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90
const SEED_VALUE: int = 20260614

var _scene: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("robbery target probe: scene failed to load")
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
		push_error("robbery target probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var target := _scene.find_child("RobberyTarget", true, false) as RobberyTarget
	if target == null:
		return "RobberyTarget not present in miami.tscn"
	if not target.is_in_group("interactables"):
		return "RobberyTarget not registered as an interactable"
	var stats := get_first_node_in_group("player_stats") as PlayerStats
	var wanted := get_first_node_in_group("wanted")
	var player := get_first_node_in_group("player")
	if stats == null or wanted == null or player == null:
		return "no live player / player_stats / wanted node"
	return _run_holdup(target, stats, wanted, player)


## Seed the loot, rob once (wallet up by a legal haul + stars up), then assert an
## immediate second press is a cooldown no-op (wallet flat, still cooling down).
func _run_holdup(target: RobberyTarget, stats: PlayerStats, wanted: Node, player: Node) -> String:
	target.set_seed(SEED_VALUE)
	var money0: int = int(stats.money)
	var stars0: int = int(wanted.stars())
	target.interact(player)
	var loot: int = int(stats.money) - money0
	if loot < target.loot_min or loot > target.loot_max:
		return "loot %d outside [%d, %d]" % [loot, target.loot_min, target.loot_max]
	if int(wanted.stars()) <= stars0:
		return "stars did not rise (%d -> %d)" % [stars0, int(wanted.stars())]
	if not target.is_cooling_down():
		return "target not cooling down after a holdup"
	var money1: int = int(stats.money)
	target.interact(player)
	if int(stats.money) != money1:
		return "second interact paid out mid-cooldown (%d -> %d)" % [money1, int(stats.money)]
	print(
		(
			"robbery target probe: OK (loot %d, stars %d -> %d, cooldown holds)"
			% [loot, stars0, int(wanted.stars())]
		)
	)
	return ""
