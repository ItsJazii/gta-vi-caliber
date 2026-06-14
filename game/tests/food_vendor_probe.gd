extends SceneTree
## Runtime probe for the live FoodVendor in miami.tscn. Boots the map, asserts the
## vendor is a live interactable, hurts the player and asserts a buy charges `price`
## AND heals, then tops the player off and asserts a buy at full health is a no-op
## (no wasted money). Self-contained (no miami_wiring_probe touch).
##   godot --headless --path game --script res://tests/food_vendor_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90

var _scene: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("food vendor probe: scene failed to load")
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
		print("food vendor probe: OK")
		quit(0)
	else:
		push_error("food vendor probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var vendor := _scene.find_child("FoodVendor", true, false) as FoodVendor
	if vendor == null:
		return "FoodVendor not present in miami.tscn"
	if not vendor.is_in_group("interactables") or not vendor.has_method("interact"):
		return "FoodVendor is not a live interactable (group/contract missing)"
	var health := get_first_node_in_group("player_health")
	var stats := get_first_node_in_group("player_stats") as PlayerStats
	if health == null or stats == null:
		return "no live player_health / player_stats"
	var player := get_first_node_in_group("player")

	# Hurt the player, then a buy must charge the price AND raise the health fraction.
	health.take_damage(90.0)
	var frac0: float = health.fraction()
	var money0: int = int(stats.money)
	vendor.interact(player)
	if int(stats.money) != money0 - vendor.price or health.fraction() <= frac0:
		return (
			"buy did not charge + heal (money %d->%d, frac %.2f->%.2f)"
			% [money0, int(stats.money), frac0, health.fraction()]
		)

	# At full health, a buy must be a no-op (no wasted money).
	health.heal(1000.0)
	var money1: int = int(stats.money)
	vendor.interact(player)
	if int(stats.money) != money1:
		return "charged at full health (wasted %d)" % (money1 - int(stats.money))
	return ""
