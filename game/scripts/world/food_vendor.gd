class_name FoodVendor
extends Node3D
## A walk-up food stand: face it and press the interact key to buy a meal — it
## charges `price` and heals the player. Self-contained: joins group `interactables`
## and answers the interact contract (cf. Shop / SlotMachine), reads player_health
## and player_stats by group. No-op when you're already at full health (so it never
## wastes your money), can't afford it, or are dead. Wiring exercised by
## tests/food_vendor_probe.gd.

## Emitted on a successful purchase: the price paid and the heal granted.
signal food_bought(price: int, healed: float)

## Cost of a meal.
@export var price: int = 50
## Health restored per meal (clamped to full by player_health).
@export var heal_amount: float = 35.0


func _ready() -> void:
	add_to_group("interactables")


## Interact-contract: the on-screen prompt.
func interact_prompt() -> String:
	return "Buy Food ($%d)" % price


## Interact-contract: buy a meal and heal. No-op at full health / when broke / dead.
func interact(_player: Node) -> void:
	var health := get_tree().get_first_node_in_group("player_health")
	if health == null or not health.has_method("heal") or not health.has_method("fraction"):
		return
	if health.has_method("is_dead") and health.is_dead():
		return
	if float(health.fraction()) >= 0.999:
		return
	var stats := get_tree().get_first_node_in_group("player_stats") as PlayerStats
	if stats == null or not stats.spend_money(price):
		return
	health.heal(heal_amount)
	food_bought.emit(price, heal_amount)
