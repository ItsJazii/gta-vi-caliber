extends SceneTree
## Scene-free probe for GarageStorageTrigger's store -> hide -> retrieve -> restore round
## trip. Drives the trigger directly in a mock tree (a "World" with the trigger and two
## mock cars under it) so it needs no miami.tscn: parking a car must store its id, hide
## it, and pull it out of the world (no longer a child of World); retrieving must hand the
## SAME node back, visible and reparented into the world; a third car must be refused once
## the garage is full; and a retrieve fee must be charged ONLY when a car is actually
## pulled out — never silently pocketed for a retrieve that the model would reject. Run
## headless:
##   godot --headless --path game --script res://tests/garage_storage_probe.gd

## Let the trigger's _ready() (group join, StoreZone wiring) settle before driving it.
const WARMUP_FRAMES: int = 3
## Wallet charge configured for the fee phase, and the wallet the mock starts with.
const RETRIEVE_FEE: int = 250
const START_MONEY: int = 1000

var _world: Node3D = null
var _trigger: GarageStorageTrigger = null
var _stats: MockStats = null
var _car_a: Node3D = null
var _car_b: Node3D = null
var _frames: int = 0


## A mock PlayerStats (group player_stats) with the same guarded spend_money the trigger's
## fee path bills against: false (no debit) on a non-positive or unaffordable charge.
class MockStats:
	extends Node
	var money: int = 0

	func _ready() -> void:
		add_to_group("player_stats")

	func spend_money(amount: int) -> bool:
		if amount <= 0 or money < amount:
			return false
		money -= amount
		return true


func _initialize() -> void:
	_world = Node3D.new()
	_world.name = "World"
	root.add_child(_world)
	_stats = MockStats.new()
	_stats.money = START_MONEY
	root.add_child(_stats)
	_trigger = GarageStorageTrigger.new()
	_world.add_child(_trigger)
	# StoreZone child so _ready() finds + wires it the same way the live scene would.
	var zone := Area3D.new()
	zone.name = "StoreZone"
	_trigger.add_child(zone)
	_car_a = _make_car("CarA")
	_car_b = _make_car("CarB")


## A mock car: a Node3D in group starter_vehicles (the gate park_vehicle accepts),
## parented under World so parking can prove it leaves the active world.
func _make_car(car_name: String) -> Node3D:
	var car := Node3D.new()
	car.name = car_name
	car.add_to_group("starter_vehicles")
	_world.add_child(car)
	return car


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var err := _run()
	if err.is_empty():
		print(
			(
				"garage storage probe: OK (parked 2, retrieved 1, capacity refusal held, fee charged once for $%d)"
				% RETRIEVE_FEE
			)
		)
		quit(0)
	else:
		push_error("garage storage probe FAIL: " + err)
		quit(1)
	return true


## Full round trip: park both cars, retrieve one, prove the capacity cap refuses an
## over-full park, then prove the retrieve fee is charged on success but not lost on a
## reject. Returns "" on success, else a one-line failure reason.
func _run() -> String:
	var park_err := _verify_park()
	if not park_err.is_empty():
		return park_err
	var retrieve_err := _verify_retrieve()
	if not retrieve_err.is_empty():
		return retrieve_err
	var capacity_err := _verify_capacity()
	if not capacity_err.is_empty():
		return capacity_err
	return _verify_fee()


## Park both cars: each store returns true, the count grows, and each car is hidden and
## no longer a child of World (it has been pulled out under the trigger).
func _verify_park() -> String:
	if not _trigger.park_vehicle(_car_a) or _trigger.stored_count() != 1:
		return "parking car A did not store it (count %d)" % _trigger.stored_count()
	if _car_a.visible or _car_a.get_parent() == _world:
		return "car A still visible / still in the world after parking"
	if not _trigger.park_vehicle(_car_b) or _trigger.stored_count() != 2:
		return "parking car B did not store it (count %d)" % _trigger.stored_count()
	if _car_b.visible or _car_b.get_parent() == _world:
		return "car B still visible / still in the world after parking"
	return ""


## Retrieve one car: a non-empty id comes back, that car is visible + reparented into the
## world again, and the stored count drops by one.
func _verify_retrieve() -> String:
	var id := _trigger.retrieve_vehicle()
	if id.is_empty():
		return "retrieve returned no id with two cars parked"
	if _trigger.stored_count() != 1:
		return "stored count did not drop after retrieve (count %d)" % _trigger.stored_count()
	# The most-recently parked car (B) is the one handed back.
	if not _car_b.visible or _car_b.get_parent() != _world:
		return "retrieved car B not visible / not back in the world"
	return ""


## Filling the garage past capacity must refuse the extra park (model rejects it, node
## untouched). Top the garage off to capacity with fresh cars, then prove one more park
## past the cap is turned away (returns false) and the count holds.
func _verify_capacity() -> String:
	var cap := storage_capacity()
	while _trigger.stored_count() < cap:
		var filler := _make_car("Filler%d" % _trigger.stored_count())
		if not _trigger.park_vehicle(filler):
			return "park refused while the garage still had a free slot"
	var overflow := _make_car("Overflow")
	if _trigger.park_vehicle(overflow):
		return "park accepted a car past capacity (count %d)" % _trigger.stored_count()
	if _trigger.stored_count() != cap:
		return (
			"stored count moved on a refused over-capacity park (count %d)"
			% _trigger.stored_count()
		)
	return ""


## Retrieve fee: with a positive fee, a successful retrieve debits the wallet by exactly
## the fee; and retrieving an id NOT parked here is refused WITHOUT charging — money is
## never pocketed for a retrieve the model would reject (the fee is the last fallible step).
func _verify_fee() -> String:
	_trigger.retrieve_fee = RETRIEVE_FEE
	var before := _stats.money
	var count_before := _trigger.stored_count()
	var id := _trigger.retrieve_vehicle()
	if id.is_empty():
		return "fee retrieve returned no id with cars parked"
	if _stats.money != before - RETRIEVE_FEE:
		return (
			"fee not charged on success (%d -> %d, fee %d)" % [before, _stats.money, RETRIEVE_FEE]
		)
	if _trigger.stored_count() != count_before - 1:
		return "stored count did not drop on a paid retrieve (count %d)" % _trigger.stored_count()
	# A car that isn't parked in this garage must be refused with no charge (no money loss).
	var guarded := _stats.money
	var ghost := _trigger.retrieve_vehicle(null, "not-a-parked-car#0")
	if not ghost.is_empty():
		return "retrieve of an unparked id unexpectedly succeeded (%s)" % ghost
	if _stats.money != guarded:
		return (
			"fee charged for a retrieve that returned no car (%d -> %d)" % [guarded, _stats.money]
		)
	return ""


## Per-garage capacity (the model's default), for the over-fill check.
func storage_capacity() -> int:
	return _trigger.storage.capacity()
