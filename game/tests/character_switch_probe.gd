extends SceneTree
## Runtime wiring probe for CharacterSwitcher.
##
## Proves the node syncs per-lead wallets through a live PlayerStats-shaped node in
## group `player_stats`: each character's money persists independently across
## switches. Built with a mock stats node so it needs no scene file. Run headless:
##   godot --headless --path game --script res://tests/character_switch_probe.gd

const SETTLE_FRAMES: int = 3

var _sw: CharacterSwitcher = null
var _stats: MockStats = null
var _frames: int = 0


class MockStats:
	extends Node
	var money: int = 0

	func _ready() -> void:
		add_to_group("player_stats")

	func add_money(amount: int) -> void:
		money += amount


func _initialize() -> void:
	_stats = MockStats.new()
	root.add_child(_stats)
	_sw = CharacterSwitcher.new()
	root.add_child(_sw)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	return _run_scenario()


func _run_scenario() -> bool:
	# After _ready, the active lead (Mara, 2500) is loaded into stats.
	if _stats.money != 2500:
		return _fail("active lead's wallet not loaded into PlayerStats (got %d)" % _stats.money)
	# Mara earns 500 -> 3000, then switch to Rico (1500) at t=0.
	_stats.add_money(500)
	if not _sw.request_switch("rico", 0.0):
		return _fail("switch to rico refused")
	if _stats.money != 1500:
		return _fail("rico's wallet not loaded on switch (got %d)" % _stats.money)
	# Switch back after the cooldown: Mara's 3000 must have persisted.
	if not _sw.request_switch("mara", CharacterRoster.SWITCH_COOLDOWN):
		return _fail("switch back to mara refused")
	if _stats.money != 3000:
		return _fail("mara's earnings did not persist across the switch (got %d)" % _stats.money)
	return _pass()


func _pass() -> bool:
	print("character switch probe: OK (per-lead wallet persists through PlayerStats)")
	quit(0)
	return true


func _fail(reason: String) -> bool:
	push_error("character switch probe FAIL: %s" % reason)
	quit(1)
	return true
