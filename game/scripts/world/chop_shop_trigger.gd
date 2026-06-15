class_name ChopShopTrigger
extends Node3D
## Drive-it-in chop shop: roll a (stolen) car into the FenceZone and it's stripped
## for cash, priced by its CLASS and CONDITION, then the car is removed — the classic
## fence-the-ride loop. Consumes the unit-tested ChopShop valuation model and self-wires
## by group (player_stats / starter_vehicles), so it needs no plumbing beyond one Area3D +
## CollisionShape3D child named "FenceZone" (mirrors ContrabandDealer's zone wiring).
##
## A car's condition is its health fraction (Car.health / Car.max_health); the model
## scales the payout from a scrap floor (wrecked) up to full (pristine) and adds a demand
## bonus for any class currently on the most-wanted orders list. The valuation math lives
## in the headless ChopShop (tests/unit/test_chop_shop.gd); this node's wiring is exercised
## by tests/chop_shop_probe.gd. Original system — no affiliation with any commercial title.

## Fired when a delivered car is chopped (the fenced class id, cash paid out).
signal vehicle_chopped(class_id: String, payout: int)

## Brief gap between chops so one drive-in can't fence a convoy in a single frame.
@export var cooldown_seconds: float = 5.0

## The live valuation model. Public so a price-board UI can read class values / orders.
var shop: ChopShop

var _fence_zone: Area3D = null
var _stats: Node = null
var _cooldown_left: float = 0.0


func _init() -> void:
	# default_classes() seeds the catalogue (compact/sedan/bike/suv/muscle/sports/super),
	# so the empty-array ctor already gives this trigger real class ids to fence against.
	shop = ChopShop.new()


func _ready() -> void:
	add_to_group("chop_shop")
	_fence_zone = get_node_or_null("FenceZone") as Area3D
	if _fence_zone != null:
		# car.gd / player.gd put bodies on collision layer 2; watch for it.
		_fence_zone.collision_mask |= 2
		_fence_zone.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if not (body is Car or body.is_in_group("starter_vehicles")):
		return
	resolve_chop(body as Node3D)


## Fence the delivered car and apply the payout, returning the cash paid (0 if nothing
## happened). Public + signal-free so a probe can drive it directly. Reads the car's
## condition from health/max_health (defaulting to pristine when those props are missing),
## prices it via the demand-aware ChopShop, pays the wallet (group player_stats), starts
## the cooldown, frees the car, and announces the chop.
func resolve_chop(car: Node3D) -> int:
	if car == null or _cooldown_left > 0.0:
		return 0
	var condition := _condition_of(car)
	var class_id := _class_for(car)
	var payout := shop.value(class_id, condition)
	if payout <= 0:
		return 0
	_pay(payout)
	_cooldown_left = maxf(cooldown_seconds, 0.0)
	car.queue_free()
	vehicle_chopped.emit(class_id, payout)
	return payout


## Condition in 0..1 from the car's health fraction, defaulting to pristine (1.0) when the
## health props are absent or max_health is non-positive — so a duck-typed mock still works.
func _condition_of(car: Node3D) -> float:
	if not ("health" in car and "max_health" in car):
		return 1.0
	var max_health := float(car.max_health)
	if max_health <= 0.0:
		return 1.0
	return clampf(float(car.health) / max_health, 0.0, 1.0)


## Map a car to a ChopShop class id by sniffing its node name + source scene path for
## keywords, matched against the model's real catalogue. Falls back to the first class id.
func _class_for(car: Node3D) -> String:
	var hint := (str(car.name) + " " + car.scene_file_path).to_lower()
	if shop.has_class("sports") and (hint.contains("coupe") or hint.contains("sport")):
		return "sports"
	if shop.has_class("muscle") and hint.contains("muscle"):
		return "muscle"
	if shop.has_class("sedan") and (hint.contains("sedan") or hint.contains("classic")):
		return "sedan"
	if shop.has_class("bike") and hint.contains("bike"):
		return "bike"
	var catalogue: Array = shop.ids()
	return str(catalogue[0]) if not catalogue.is_empty() else ""


func _pay(amount: int) -> void:
	var stats := _player_stats()
	if stats != null and stats.has_method("add_money"):
		stats.add_money(amount)


func _player_stats() -> Node:
	if _stats == null or not is_instance_valid(_stats):
		_stats = get_tree().get_first_node_in_group("player_stats")
	return _stats
