class_name RobberyTarget
extends Node3D
## A walk-up store/bank you can hold up: face it and press the interact key to rob
## it. One press grabs a random wad of cash (credited to the live PlayerStats
## wallet) but spikes your wanted level — the heat lands on WantedTracker, which the
## police + emergency-responder systems already react to — then the target goes on
## cooldown so you can't farm it instantly. This is the FIRST way to EARN money
## through crime; it feeds the existing wanted->police->responder loop.
##
## Mirrors the storefront interactable shape (Shop / FoodVendor / RouletteTable):
## self-wires into the "interactables" group and answers interact_prompt() +
## interact(player), resolving the wallet and the wanted node by group. Loot is
## drawn from a node-owned RandomNumberGenerator so a probe can seed (set_seed) a
## deterministic haul; gameplay leaves it on its random default. Wiring exercised
## by tests/robbery_target_probe.gd.

## Fired on a successful holdup: the cash grabbed this robbery.
signal robbed(loot: int)

## Display name shown in the prompt ("Rob %s").
@export var target_name: String = "Liquor Store"
## Smallest possible haul (inclusive).
@export var loot_min: int = 500
## Largest possible haul (inclusive).
@export var loot_max: int = 2500
## Real seconds the target stays cooling down after a holdup before it can be robbed again.
@export var cooldown_seconds: float = 30.0
## How many report_crime(false) calls one holdup triggers — tuned so the heat
## reliably bumps at least one star (WantedTracker.wound_heat 0.7 x 3 = 2.1 heat,
## clearing the 1.0/3.0 star thresholds for a 2-star spike from a cold start).
@export var heat_hits: int = 3

var _rng := RandomNumberGenerator.new()
var _cooldown_left: float = 0.0


func _ready() -> void:
	add_to_group("interactables")


## Count the cooldown down to zero in real time so the target re-arms on its own.
func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## HUD prompt: the remaining cooldown while hot, the holdup invite otherwise.
func interact_prompt() -> String:
	if _cooldown_left > 0.0:
		return "Robbed (%ds)" % int(ceil(_cooldown_left))
	return "Rob %s" % target_name


## One press: grab the loot, bank it, spike the heat, start the cooldown. No-op
## while still cooling down so the target can't be farmed instantly.
func interact(_player: Node) -> void:
	if _cooldown_left > 0.0:
		return
	var loot := _rng.randi_range(loot_min, loot_max)
	var stats := get_tree().get_first_node_in_group("player_stats")
	if stats != null and stats.has_method("add_money"):
		stats.add_money(loot)
	var wanted := get_tree().get_first_node_in_group("wanted")
	if wanted != null and wanted.has_method("report_crime"):
		for _i in heat_hits:
			wanted.report_crime(false)
	_cooldown_left = cooldown_seconds
	robbed.emit(loot)


## Whether the target is still cooling down (no-ops a holdup) — for a HUD/probe readout.
func is_cooling_down() -> bool:
	return _cooldown_left > 0.0


## Seed the loot RNG so a probe can replay a deterministic haul.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value
