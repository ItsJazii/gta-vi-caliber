extends SceneTree
## Scene-free probe for ChopShopTrigger's full fence path. Drives cars of the same class
## but different condition / heat / demand state into the trigger and asserts:
##   * condition scales the payout (a pristine car out-pays a wrecked one);
##   * a HOT car (player carries a wanted level) takes the 25% heat discount;
##   * a car of a REQUESTED most-wanted class out-pays a non-requested one, and the
##     delivery fulfils (clears) that order;
##   * every payout credits the wallet exactly, the shop's earnings bookkeeping banks
##     each delivery (the live trigger now fences through deliver(), not the old value()
##     path that left the discount / orders / earnings all dead), and each car is freed.
## Built with mock player_stats / wanted / car nodes so it needs no scene file (and dodges
## Area3D physics-tick timing). Run headless:
##   godot --headless --path game --script res://tests/chop_shop_probe.gd

var _frames: int = 0
var _trigger: ChopShopTrigger = null
var _stats: MockStats = null
var _wanted: MockWanted = null
var _cars: Array = []
var _pays: Array = []
var _full_pay: int = 0
var _low_pay: int = 0
var _hot_pay: int = 0
var _req_pay: int = 0
var _chopped: bool = false


class MockStats:
	extends Node
	var money: int = 0

	func _ready() -> void:
		add_to_group("player_stats")

	func add_money(amount: int) -> void:
		money = maxi(0, money + amount)


## Stand-in for WantedTracker: a node in group "wanted" answering stars() (the duck-typed
## contract ChopShopTrigger._is_hot reads). `stars_value` is driven directly to flip heat.
class MockWanted:
	extends Node
	var stars_value: int = 0

	func _ready() -> void:
		add_to_group("wanted")

	func stars() -> int:
		return stars_value


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
	_wanted = MockWanted.new()
	root.add_child(_wanted)
	_trigger = ChopShopTrigger.new()
	# No cooldown gap so back-to-back drive-ins all fence in one probe run, and freeze the
	# rotating orders board so the probe controls demand deterministically (set_requests).
	_trigger.cooldown_seconds = 0.0
	_trigger.request_rotate_seconds = 0.0
	var fence := Area3D.new()
	fence.name = "FenceZone"
	_trigger.add_child(fence)
	root.add_child(_trigger)


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


## Fence four cars covering condition, heat, and demand. Runs the scenarios, fails on the
## first bad result, else continues to the next-frame freed-car check.
func _chop() -> bool:
	_chopped = true
	var err := _run_chops()
	if not err.is_empty():
		return _fail(err)
	return false


## Run the fence scenarios in order; "" on success, else the first failure reason.
func _run_chops() -> String:
	# _ready must have seeded the rotating most-wanted board so REQUEST_BONUS is live in
	# the shipped game (it used to be dead — nothing populated it). Assert that BEFORE
	# clearing the board for the deterministic scenarios below.
	if _trigger.shop.requested().is_empty():
		return "_ready did not seed the most-wanted orders board"
	# Deterministic baseline: empty the (randomly seeded) orders board, no heat.
	_trigger.shop.set_requests([])
	_wanted.stars_value = 0
	var err := _chop_classes()
	if not err.is_empty():
		return err
	err = _chop_condition()
	if not err.is_empty():
		return err
	err = _chop_hot()
	if not err.is_empty():
		return err
	err = _chop_requested()
	if not err.is_empty():
		return err
	return _check_bookkeeping()


## _class_for must resolve every catalogue class by keyword, and an unrecognised car must
## fall back to the mid-tier default_class. Each car is pristine / cool / not-requested, so
## its payout equals exactly that class's base value — which pins the resolved class.
func _chop_classes() -> String:
	var cases := {
		"super_x": 30000,  # super/hyper branch (was dead data before)
		"suv_x": 5000,  # suv/truck/jeep/van branch (was dead data)
		"muscle_x": 8000,  # muscle branch
		"compact_x": 2000,  # compact/hatch/mini branch (was dead data)
		"bike_x": 3000,  # bike branch
		"blob_x": 3500,  # no keyword -> default_class "sedan" base (was catalogue[0]=compact)
	}
	for node_name: String in cases:
		var expected := int(cases[node_name])
		var pay := _chop_one(node_name, 100.0)
		if pay != expected:
			return "%s fenced for %d, expected %d (class resolution)" % [node_name, pay, expected]
	return ""


## Pristine vs wrecked, both cool / not requested: condition must scale the payout down.
func _chop_condition() -> String:
	_full_pay = _chop_one("coupe_full", 100.0)
	if _full_pay <= 0:
		return "pristine car paid nothing (%d)" % _full_pay
	_low_pay = _chop_one("coupe_low", 15.0)
	if _low_pay <= 0:
		return "wrecked car paid nothing (%d)" % _low_pay
	if _full_pay <= _low_pay:
		return "condition did not scale payout (full %d <= low %d)" % [_full_pay, _low_pay]
	return ""


## A hot car (player wanted) takes the 25% heat discount vs the cool pristine payout.
func _chop_hot() -> String:
	_wanted.stars_value = 3
	_hot_pay = _chop_one("coupe_hot", 100.0)
	_wanted.stars_value = 0
	if _hot_pay >= _full_pay:
		return "hot car not discounted (hot %d >= full %d)" % [_hot_pay, _full_pay]
	if _hot_pay != int(round(float(_full_pay) * 0.75)):
		return "hot discount was not 25%% (hot %d vs full %d)" % [_hot_pay, _full_pay]
	return ""


## A requested most-wanted class out-pays base, and the delivery fulfils (clears) the order.
func _chop_requested() -> String:
	_trigger.shop.set_requests(["sports"])
	_req_pay = _chop_one("coupe_req", 100.0)
	if _req_pay <= _full_pay:
		return "requested class did not out-pay base (req %d <= full %d)" % [_req_pay, _full_pay]
	if _trigger.shop.is_requested("sports"):
		return "delivering a requested car did not fulfil (clear) the order"
	return ""


## The deliver() path banks every chop and credits the wallet exactly — checked across
## ALL chops (class-resolution + scenarios), so the count auto-tracks however many ran.
func _check_bookkeeping() -> String:
	var expected := 0
	for pay: int in _pays:
		expected += pay
	if _trigger.shop.total_earned() != expected:
		return "shop earnings %d != sum of payouts %d" % [_trigger.shop.total_earned(), expected]
	if _trigger.shop.deliveries_count() != _pays.size():
		return (
			"shop logged %d deliveries, expected %d"
			% [_trigger.shop.deliveries_count(), _pays.size()]
		)
	if _stats.money != expected:
		return "wallet %d != sum of payouts %d" % [_stats.money, expected]
	return ""


## Spawn one mock car of the given health, record it (for the freed + bookkeeping checks),
## and fence it. Every payout is banked into _pays so _check_bookkeeping sums all chops.
func _chop_one(node_name: String, health: float) -> int:
	var car := MockCar.new()
	car.name = node_name
	car.health = health
	root.add_child(car)
	_cars.append(car)
	var pay := _trigger.resolve_chop(car)
	_pays.append(pay)
	return pay


## Next-frame assertion: every fenced car was freed (queue_free is deferred a frame).
func _verify() -> bool:
	for car: Variant in _cars:
		if is_instance_valid(car):
			return _fail("a fenced car was not freed (%s)" % str(car.name))
	print(
		(
			"chop shop probe: OK (board seeded, classes resolved, condition/hot/demand applied; earned $%d over %d chops)"
			% [_trigger.shop.total_earned(), _trigger.shop.deliveries_count()]
		)
	)
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("chop shop probe FAIL: " + reason)
	quit(1)
	return true
