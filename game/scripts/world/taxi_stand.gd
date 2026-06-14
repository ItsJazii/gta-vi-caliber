class_name TaxiStand
extends Node3D
## A walk-up taxi stand: face it and press the interact key to pay a flat fare and
## fast-travel across the map. Self-contained — joins group `interactables` and
## answers the interact contract (cf. RouletteTable / SlotMachine / FoodVendor),
## charges the live PlayerStats wallet, and teleports the live player.
##
## Each press rides to the NEXT stop in `destinations`, cycling back to the first
## once you've toured them all, so a single stand serves a short loop of districts.
## The fare is debited through the guarded spend_money path, so a broke fare is a
## no-op (you never get a free ride). The player is a CharacterBody3D, so after
## moving its global_position we zero its velocity — otherwise the carried-over
## momentum (a fall, a sprint) would keep applying at the drop-off. `taxi_ride`
## fires with the destination index and fare paid for any HUD/bark to show.
## Wiring exercised by tests/taxi_stand_probe.gd.

## Emitted on a paid ride: the destination index reached and the fare charged.
signal taxi_ride(destination_index: int, fare: int)

## Flat fare charged per ride (debited up-front; only travels if affordable).
@export var fare: int = 100
## Drop-off points, ridden in order on repeat presses then looping back to the
## first. Spread around the map so the stand stitches a few districts together.
@export var destinations: PackedVector3Array = PackedVector3Array(
	[Vector3(0, 1, 0), Vector3(-60, 1, 40), Vector3(40, 1, -40), Vector3(-30, 1, 60)]
)
## Prompt labels, index-aligned with `destinations` (a missing label falls back to
## the stop number, so a length mismatch never breaks the prompt).
@export var destination_names: PackedStringArray = PackedStringArray(
	["Downtown", "West Side", "East Beach", "North Marina"]
)

var _next: int = 0


func _ready() -> void:
	add_to_group("interactables")


## Interact-contract: the on-screen prompt naming the next stop and the fare.
func interact_prompt() -> String:
	if destinations.is_empty():
		return "Taxi (no destinations)"
	return "Taxi to %s ($%d)" % [name_for(_next), fare]


## Interact-contract: pay the fare and fast-travel to the next stop. No-op when
## there's nowhere to go, no live player/wallet, or you can't cover the fare.
func interact(_player: Node) -> void:
	if destinations.is_empty():
		return
	var stats := get_tree().get_first_node_in_group("player_stats") as PlayerStats
	if stats == null or not stats.spend_money(fare):
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	player.global_position = destinations[_next]
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	taxi_ride.emit(_next, fare)
	_next = (_next + 1) % destinations.size()


## Label for stop `i`: its name when one is set, else a plain stop number.
func name_for(i: int) -> String:
	if i >= 0 and i < destination_names.size():
		return destination_names[i]
	return "Stop %d" % (i + 1)
