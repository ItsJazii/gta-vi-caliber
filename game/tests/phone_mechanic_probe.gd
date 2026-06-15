extends SceneTree
## Scene-free probe for the paid phone mechanic service.
##
## The player owns the phone in live play, so this verifies the actual signal path:
## call Devin -> spend cash -> emit the vehicle service -> repair the driven car.

const DEVIN_INDEX: int = 1
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _player: Player = null
var _phone: Phone = null
var _stats: MockStats = null
var _vehicle: MockRepairableVehicle = null
var _frames: int = 0
var _service: Dictionary = {}


class MockStats:
	extends Node
	var money: int = 1500

	func _ready() -> void:
		add_to_group("player_stats")

	func spend_money(amount: int) -> bool:
		if amount <= 0 or money < amount:
			return false
		money -= amount
		return true


class MockRepairableVehicle:
	extends Node3D
	var health: float = 18.0
	var max_health: float = 100.0


func _initialize() -> void:
	_stats = MockStats.new()
	root.add_child(_stats)
	_player = PLAYER_SCENE.instantiate() as Player
	root.add_child(_player)
	_vehicle = MockRepairableVehicle.new()
	root.add_child(_vehicle)
	_player.set("_vehicle", _vehicle)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	return _run()


func _on_service_requested(id: String, kind: String, contact: String, cost: int) -> void:
	_service = {"id": id, "kind": kind, "contact": contact, "cost": cost}


func _run() -> bool:
	_phone = _phone_child()
	if _phone == null:
		return _fail("player did not spawn a phone")
	if not _phone.service_requested.is_connected(_on_service_requested):
		_phone.service_requested.connect(_on_service_requested)
	_phone._start_call(DEVIN_INDEX)
	_phone._advance_call(PhoneModel.DIAL_SECONDS + 0.1)
	_phone._advance_call(PhoneContacts.ring_seconds(PhoneContacts.by_name("Devin")) + 0.1)
	if _service.get("id", "") != "mechanic":
		return _fail("phone did not emit mechanic service: %s" % str(_service))
	if _service.get("kind", "") != "vehicle" or int(_service.get("cost", 0)) != 1000:
		return _fail("mechanic service payload was wrong: %s" % str(_service))
	if _stats.money != 500:
		return _fail("wallet was not charged down to 500 (money=%d)" % _stats.money)
	if not is_equal_approx(_vehicle.health, _vehicle.max_health):
		return _fail("current vehicle was not repaired")
	print("phone mechanic probe: OK (Devin charged wallet and repaired the current car)")
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("phone mechanic probe FAIL: %s" % reason)
	quit(1)
	return true


func _phone_child() -> Phone:
	for child in _player.get_children():
		var phone := child as Phone
		if phone != null:
			return phone
	return null
