class_name PaySprayShop
extends Area3D
## A drive-in pay-n-spray: enter while wanted and unseen to pay a heat-scaled fee
## and lose the cops — the iconic GTA wanted-clear. Consumes the tested PaySpray
## model and self-wires by group (player, wanted, player_stats, police), so it
## needs no plumbing beyond an Area3D + CollisionShape3D placed in the world.

signal resprayed(cost: int)

## Fee = base_cost + per_star * stars (PaySpray.cost_for).
@export var base_cost: int = 200
@export var per_star: int = 100
## If any cop is within this range of the shop as you enter, you're traced and it
## won't clear — shake them first.
@export var sight_radius: float = 45.0

# Singleton lookups cached across visits; re-resolved only when freed.
var _tracker: Node = null
var _stats: Node = null


func _ready() -> void:
	# player.gd puts the player body on collision layer 2; watch for it.
	collision_mask |= 2
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_bind()
	var tracker := _tracker
	if tracker == null or not tracker.has_method("is_wanted") or not tracker.is_wanted():
		return
	var stats := _stats
	var balance: int = int(stats.money) if stats != null and ("money" in stats) else 0
	var stars: int = tracker.stars() if tracker.has_method("stars") else 0
	# Traced if a cop watches you duck in — no clean getaway. The police list is
	# read live (not cached): entries are rare events and a stale list here
	# could let the player respray under a watching cop's nose.
	if PaySpray.is_seen_entering(global_position, _police_positions(), sight_radius):
		return
	var cost := PaySpray.cost_for(stars, base_cost, per_star)
	if cost <= 0 or balance < cost:
		return
	if stats != null and stats.has_method("spend_money"):
		stats.spend_money(cost)
	tracker.clear()
	resprayed.emit(cost)


func _bind() -> void:
	if _tracker == null or not is_instance_valid(_tracker):
		_tracker = get_tree().get_first_node_in_group("wanted")
	if _stats == null or not is_instance_valid(_stats):
		_stats = get_tree().get_first_node_in_group("player_stats")


func _police_positions() -> Array:
	var out: Array = []
	for cop in get_tree().get_nodes_in_group("police"):
		var node := cop as Node3D
		if node != null:
			out.append({"pos": node.global_position})
	return out
