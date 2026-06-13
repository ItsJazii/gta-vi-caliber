class_name PropertyHub
extends Node3D
## Makes PropertyOwnership playable: drive into the BuyZone to purchase the
## property (if you can afford it), it then earns passive income over time, and
## you collect the takings by entering the CollectZone. Consumes the tested
## PropertyOwnership model and self-wires by group (player / player_stats).
##
## Expects two Area3D children named "BuyZone" and "CollectZone", each with a
## CollisionShape3D. Both watch the player's collision layer (2).

signal property_bought(id: String, cost: int)
signal income_collected(amount: int)

## The catalogue id this hub sells (must exist in PropertyOwnership's catalogue).
@export var property_id: String = "taxi_firm"
## Real seconds per in-world "day" of income accrual.
@export var seconds_per_day: float = 30.0

var _props: PropertyOwnership
var _buy_zone: Area3D
var _collect_zone: Area3D


func _ready() -> void:
	_props = PropertyOwnership.new()
	add_to_group("property_hub")
	_buy_zone = get_node_or_null("BuyZone") as Area3D
	_collect_zone = get_node_or_null("CollectZone") as Area3D
	if _buy_zone != null:
		_buy_zone.collision_mask |= 2
		_buy_zone.body_entered.connect(_on_buy_entered)
	if _collect_zone != null:
		_collect_zone.collision_mask |= 2
		_collect_zone.body_entered.connect(_on_collect_entered)


func _process(delta: float) -> void:
	if _props.owns(property_id) and seconds_per_day > 0.0:
		_props.accrue(delta / seconds_per_day)


func _on_buy_entered(body: Node) -> void:
	if not body.is_in_group("player") or _props.owns(property_id):
		return
	var stats := get_tree().get_first_node_in_group("player_stats")
	var balance: int = int(stats.money) if stats != null and ("money" in stats) else 0
	var result := _props.buy(property_id, balance)
	if not result.get("success", false):
		return
	if stats != null and stats.has_method("spend_money"):
		stats.spend_money(int(result["cost"]))
	property_bought.emit(property_id, int(result["cost"]))


func _on_collect_entered(body: Node) -> void:
	if not body.is_in_group("player") or not _props.owns(property_id):
		return
	var takings := _props.collect()
	if takings <= 0:
		return
	var stats := get_tree().get_first_node_in_group("player_stats")
	if stats != null and stats.has_method("add_money"):
		stats.add_money(takings)
	income_collected.emit(takings)


## Whether the property is owned, for a HUD readout.
func owns_property() -> bool:
	return _props != null and _props.owns(property_id)


## Pending uncollected income, for a HUD readout.
func pending_income() -> float:
	return _props.pending_income() if _props != null else 0.0


# --- Persistence (SaveManager) ---------------------------------------------


func serialize() -> Dictionary:
	return _props.serialize() if _props != null else {}


func restore(data: Dictionary) -> void:
	if _props != null:
		_props.restore(data)
