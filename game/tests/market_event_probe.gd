extends SceneTree
## Runtime wiring probe for MarketEventCoordinator.
##
## Unit tests cover the pure models; this proves the *node* self-wires in a real
## tree: it subscribes to a `wanted` group member's stars_changed signal (rallying
## defense stocks on escalation) and applies a HitContract market effect. Built
## with a mock wanted node so it needs no scene file — independent of miami.tscn.
## Run headless:
##   godot --headless --path game --script res://tests/market_event_probe.gd

## Frames to let MarketEventCoordinator's deferred _connect_wanted() run.
const SETTLE_FRAMES: int = 3

var _coord: MarketEventCoordinator = null
var _mock: MockWanted = null
var _frames: int = 0


class MockWanted:
	extends Node
	signal stars_changed(stars: int)
	var _stars: int = 0

	func _ready() -> void:
		add_to_group("wanted")

	func stars() -> int:
		return _stars

	func escalate(to_stars: int) -> void:
		_stars = to_stars
		stars_changed.emit(to_stars)


func _initialize() -> void:
	_mock = MockWanted.new()
	root.add_child(_mock)
	_coord = MarketEventCoordinator.new()
	root.add_child(_coord)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false

	# 1. Rising wanted level should rally the defense sector via the live signal.
	var base_defense := _coord.market.price("merryweather")
	_mock.escalate(3)
	if _coord.market.price("merryweather") <= base_defense:
		return _fail("escalation did not rally defense stock (signal not wired)")

	# 2. A completed-hit market effect should ripple to sector rivals.
	var base_augury := _coord.market.price("augury_air")
	var applied: bool = _coord.apply_hit_effect(
		{"company_id": "pelican_air", "magnitude": -0.4, "spillover": 1.0}
	)
	if not applied or _coord.market.price("augury_air") <= base_augury:
		return _fail("apply_hit_effect did not move the rival stock")

	return _pass()


func _pass() -> bool:
	print("market event probe: OK (wanted rally + hit effect wired)")
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("market event probe FAIL: %s" % reason)
	quit(1)
	return true
