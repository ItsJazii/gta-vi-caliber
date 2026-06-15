extends SceneTree
## Scene-free probe for ChopShopTrigger: drive two cars of the same class but different
## condition into the chop shop and assert both pay, the pristine one pays MORE than the
## wrecked one (condition scales the payout), the wallet grows by exactly each payout, and
## each fenced car is freed. Built with mock player_stats / car nodes so it needs no scene
## file (and dodges Area3D physics-tick timing). Run headless:
##   godot --headless --path game --script res://tests/chop_shop_probe.gd

var _frames: int = 0
var _trigger: ChopShopTrigger = null
var _stats: MockStats = null
var _pristine: MockCar = null
var _wrecked: MockCar = null
var _full_pay: int = 0
var _low_pay: int = 0
var _chopped: bool = false


class MockStats:
	extends Node
	var money: int = 0

	func _ready() -> void:
		add_to_group("player_stats")

	func add_money(amount: int) -> void:
		money = maxi(0, money + amount)


## Duck-typed stand-in for a Car: a Node3D with health/max_health and a name that hints a
## class, in group starter_vehicles so _on_body_entered would accept it too.
class MockCar:
	extends Node3D
	var health: float = 100.0
	var max_health: float = 100.0

	func _ready() -> void:
		add_to_group("starter_vehicles")


func _initialize() -> void:
	_stats = MockStats.new()
	root.add_child(_stats)
	_trigger = ChopShopTrigger.new()
	# No cooldown gap so back-to-back drive-ins both fence in this one probe run.
	_trigger.cooldown_seconds = 0.0
	var fence := Area3D.new()
	fence.name = "FenceZone"
	_trigger.add_child(fence)
	root.add_child(_trigger)
	_pristine = _spawn_car("coupe_full", 100.0)
	_wrecked = _spawn_car("coupe_low", 15.0)


func _process(_delta: float) -> bool:
	# Nodes added in _initialize aren't fully in-tree yet; let a few frames pass so
	# _ready/group membership settle. Chop on one frame, then verify the queue_free'd
	# cars are gone a frame later (deletion is deferred to end-of-frame).
	_frames += 1
	if _frames < 3:
		return false
	if not _chopped:
		return _chop()
	return _verify()


## Fence both cars and check both paid, each credited the wallet exactly, and the pristine
## car out-paid the wrecked one. Defers the freed-car check to the next frame.
func _chop() -> bool:
	_chopped = true
	var before := _stats.money
	_full_pay = _trigger.resolve_chop(_pristine)
	if _full_pay <= 0:
		return _fail("full-health car paid nothing (%d)" % _full_pay)
	if _stats.money != before + _full_pay:
		return _fail(
			"wallet mismatch on full chop (%d -> %d, paid %d)" % [before, _stats.money, _full_pay]
		)
	var mid := _stats.money
	_low_pay = _trigger.resolve_chop(_wrecked)
	if _low_pay <= 0:
		return _fail("low-health car paid nothing (%d)" % _low_pay)
	if _stats.money != mid + _low_pay:
		return _fail(
			"wallet mismatch on low chop (%d -> %d, paid %d)" % [mid, _stats.money, _low_pay]
		)
	return false


## Next-frame assertions: condition scaled the payout, and both fenced cars were freed.
func _verify() -> bool:
	if _full_pay <= _low_pay:
		return _fail("condition did not scale payout (full %d <= low %d)" % [_full_pay, _low_pay])
	if is_instance_valid(_pristine) or is_instance_valid(_wrecked):
		return _fail("a fenced car was not freed")
	print("chop shop probe: OK (full $%d > low $%d, wallet credited both)" % [_full_pay, _low_pay])
	quit(0)
	return true


func _spawn_car(node_name: String, health: float) -> MockCar:
	var car := MockCar.new()
	car.name = node_name
	car.health = health
	root.add_child(car)
	return car


func _fail(reason: String) -> bool:
	push_error("chop shop probe FAIL: " + reason)
	quit(1)
	return true
