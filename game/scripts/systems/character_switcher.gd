class_name CharacterSwitcher
extends Node
## Self-wiring coordinator for dual-protagonist play: owns a CharacterRoster and
## keeps each lead's wallet in sync with the live PlayerStats (group `player_stats`).
## On a switch it writes the current wallet back to the outgoing lead, flips the
## roster, then loads the incoming lead's wallet into PlayerStats — so each
## character's money persists independently across switches (the genre's
## switch-and-resume). Follows the repo self-wiring pattern (cf. PaySprayShop).
##
## The roster math is unit-tested headless; this node's PlayerStats wiring is
## exercised by tests/character_switch_probe.gd. Position/wanted sync follow the
## same shape and are left to the scene controller that owns those nodes.

signal character_switched(id: String)

## The roster. Public so a switch-wheel UI can read leads / money.
var roster: CharacterRoster


func _init() -> void:
	roster = CharacterRoster.new()


func _ready() -> void:
	call_deferred("_load_active_into_stats")


## Switch the active lead, syncing wallets through PlayerStats. Returns false if the
## roster refuses the switch (unknown id, already active, on cooldown).
func request_switch(id: String, now: float = INF) -> bool:
	var stats := _player_stats()
	_write_wallet_back(stats)
	if not roster.switch_to(id, now):
		return false
	_load_wallet(stats, id)
	character_switched.emit(id)
	return true


func _player_stats() -> Node:
	return get_tree().get_first_node_in_group("player_stats")


## Push the active lead's stored wallet into PlayerStats (scene start / after load).
func _load_active_into_stats() -> void:
	_load_wallet(_player_stats(), roster.active())


func _write_wallet_back(stats: Node) -> void:
	if stats != null and "money" in stats:
		roster.set_money(roster.active(), int(stats.money))


func _load_wallet(stats: Node, id: String) -> void:
	if stats == null or not ("money" in stats) or not stats.has_method("add_money"):
		return
	stats.add_money(roster.money_of(id) - int(stats.money))
