class_name TurfClaim
extends Node3D
## A walk-up turf-war point: face it, press interact, and each press spends cash to
## MUSCLE IN on a district — buying player influence over it (charged to PlayerStats)
## while angering the rival crew that holds nearby ground. Stack enough presses and
## influence hits full, flipping the district's owner to "player": you've taken it
## over. This is the first time the unit-tested GangTerritory + FactionStanding models
## are surfaced to the player; the node self-wires by group (interactables /
## player_stats) — no plumbing beyond dropping it in the scene.
##
## The Interactable contract (see Interaction): joins group "interactables" and answers
## interact_prompt() + interact(player). All money is resolved against the live wallet
## via the guarded spend_money() path; GangTerritory/FactionStanding never touch
## PlayerStats themselves.

## Fired when a claim press buys influence (district id, new 0..1 influence level).
signal influence_gained(district_id: String, influence: float)
## Fired once influence hits full and the district flips to player ownership.
signal district_claimed(district_id: String)

## District in GangTerritory's turf map this point lets you claim.
@export var district_id: String = "downtown"
## Rival crew whose standing drops each press (muscling in angers them).
@export var rival_faction: String = "marina_cartel"
## Cash charged to the wallet per claim press.
@export var claim_cost: int = 5000
## Influence bought per press; ~3 presses (0.34 each, clamped) fully claims a district.
@export var influence_per_claim: float = 0.34

## The live turf model. Public so a manage/HUD UI can read its control state.
var territory: GangTerritory
## The live reputation model. Public so a HUD can read how the rival now feels.
var factions: FactionStanding

var _stats: Node = null


func _init() -> void:
	territory = GangTerritory.new()
	factions = FactionStanding.new()


func _ready() -> void:
	add_to_group("interactables")


## HUD hint: confirms control once owned, else shows the buy-in (influence % + cost).
func interact_prompt() -> String:
	if owns_district():
		return "%s (controlled)" % district_id
	return (
		"Claim %s — %d%% ($%d)"
		% [district_id, int(territory.influence_in(district_id) * 100), claim_cost]
	)


## One press buys a slice of influence (charged to the wallet) and angers the rival;
## when influence hits full the district flips to player ownership. No-op once owned
## or when the press can't be charged.
func interact(_player: Node) -> void:
	if owns_district():
		return
	var stats := _player_stats()
	if stats == null or not stats.has_method("spend_money"):
		return
	if not stats.spend_money(claim_cost):
		return
	territory.add_influence(district_id, influence_per_claim)
	factions.adjust(rival_faction, -10)
	influence_gained.emit(district_id, territory.influence_in(district_id))
	if territory.influence_in(district_id) >= 1.0 and territory.take_over(district_id):
		district_claimed.emit(district_id)


## Whether the player now owns this district, for a HUD readout.
func owns_district() -> bool:
	return territory != null and territory.owner_of(district_id) == "player"


## Current 0..1 player influence in this district, for a HUD readout.
func influence() -> float:
	return territory.influence_in(district_id) if territory != null else 0.0


func _player_stats() -> Node:
	if _stats == null or not is_instance_valid(_stats):
		_stats = get_tree().get_first_node_in_group("player_stats")
	return _stats
