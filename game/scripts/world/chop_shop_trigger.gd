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
## Fired when the rotating most-wanted orders board re-rolls (the new requested ids).
signal orders_rotated(requested: Array)

## Gap between chops so the loop is paced like the other crime earners (robbery is
## a 30s cooldown), not a 5s money fountain — one drive-in still can't fence a
## convoy in a single frame, but back-to-back chopping now costs real time.
@export var cooldown_seconds: float = 30.0
## How many classes sit on the most-wanted orders board at once (each pays the
## REQUEST_BONUS until fenced). The board is seeded on _ready so the demand bonus
## is actually live in-game (it used to be dead — nothing ever populated it).
@export var request_count: int = 2
## Real seconds between most-wanted re-rolls. <= 0 freezes the board after seeding.
@export var request_rotate_seconds: float = 180.0
## Classes never placed on the most-wanted board, so their demand bonus can't fire. Keeps
## the top tier's chop ceiling at its base (a clean super tops out at 30000 / hit-contract
## tier instead of 45000 with the 1.5x bonus). Cars of these classes still fence normally.
@export var non_requestable_classes: Array[String] = ["super"]
## Class fenced when a delivered car matches no keyword. A deliberate mid-tier
## default (not the accidental cheapest class that catalogue[0] happened to be),
## so an unrecognised car isn't silently floored to scrap money.
@export var default_class: String = "sedan"

## The live valuation model. Public so a price-board UI can read class values / orders.
var shop: ChopShop

var _fence_zone: Area3D = null
var _stats: Node = null
var _wanted: Node = null
var _cooldown_left: float = 0.0
var _rng := RandomNumberGenerator.new()
var _rotate_left: float = 0.0


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
	# Seed the rotating most-wanted board so the REQUEST_BONUS is live from the start.
	_rng.randomize()
	_roll_orders()
	_rotate_left = request_rotate_seconds


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if request_rotate_seconds > 0.0:
		_rotate_left -= delta
		if _rotate_left <= 0.0:
			_roll_orders()
			_rotate_left = request_rotate_seconds


## Re-roll the most-wanted orders board (skipping non-requestable classes) and announce it.
func _roll_orders() -> void:
	shop.rotate_requests(_rng, request_count, non_requestable_classes)
	orders_rotated.emit(shop.requested())


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if not (body is Car or body.is_in_group("starter_vehicles")):
		return
	# Only chop a car the player actually drives in. A starter car merely placed
	# in the zone at world spawn sits at rest; ignore it so the boot-time vehicle
	# placement can't get a starter car silently chopped on spawn.
	if body is RigidBody3D and (body as RigidBody3D).linear_velocity.length() < 1.0:
		return
	resolve_chop(body as Node3D)


## Fence the delivered car and apply the payout, returning the cash paid (0 if nothing
## happened). Public + signal-free so a probe can drive it directly. Reads the car's
## condition from health/max_health (defaulting to pristine when those props are missing),
## fences it through the demand-aware ChopShop's deliver() — so the heat discount, the
## most-wanted order fulfilment, and the shop's earnings bookkeeping all actually fire
## (the old value() path left every one of them dead) — pays the wallet (group
## player_stats), starts the cooldown, frees the car, and announces the chop.
func resolve_chop(car: Node3D) -> int:
	if car == null or _cooldown_left > 0.0:
		return 0
	var condition := _condition_of(car)
	var class_id := _class_for(car)
	# A car driven in while the player is wanted is "hot" — it takes the fence's
	# heat discount. Cool off first (lose the stars) to fence for full price.
	var result := shop.deliver(class_id, condition, _is_hot())
	var payout := int(result.get("payout", 0))
	if not result.get("accepted", false) or payout <= 0:
		return 0
	_pay(payout)
	_cooldown_left = maxf(cooldown_seconds, 0.0)
	car.queue_free()
	vehicle_chopped.emit(class_id, payout)
	return payout


## Is the delivered car hot? True while the player carries any wanted level, read
## from the live WantedTracker (group "wanted") the same duck-typed way pay_spray
## and the helicopter read it. Defaults to false (full price) when no tracker exists,
## so the headless probe and any wanted-free scene still fence cleanly.
func _is_hot() -> bool:
	if _wanted == null or not is_instance_valid(_wanted):
		_wanted = get_tree().get_first_node_in_group("wanted")
	if _wanted == null or not _wanted.has_method("stars"):
		return false
	return int(_wanted.stars()) > 0


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
## keywords, matched against the model's real catalogue. Every catalogue class now has a
## keyword branch (the old version had none for suv/compact/super, so those price tiers
## were dead data and unrecognised cars collapsed to the cheapest class). The table is
## ordered most- to least-specific so e.g. "supersport" reads as super, not sports. An
## unmatched car falls back to `default_class` (a deliberate mid-tier), then catalogue[0].
func _class_for(car: Node3D) -> String:
	var hint := (str(car.name) + " " + car.scene_file_path).to_lower()
	var hints := [
		["super", ["super", "hyper"]],
		["sports", ["coupe", "sport"]],
		["muscle", ["muscle"]],
		["suv", ["suv", "truck", "jeep", "van"]],
		["sedan", ["sedan", "classic"]],
		["compact", ["compact", "hatch", "mini"]],
		["bike", ["bike"]],
	]
	for entry in hints:
		var class_id := str(entry[0])
		if not shop.has_class(class_id):
			continue
		for keyword in entry[1]:
			if hint.contains(str(keyword)):
				return class_id
	if shop.has_class(default_class):
		return default_class
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
