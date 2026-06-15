class_name GarageStorageTrigger
extends Node3D
## A safehouse garage you drive your car INTO to park it, and walk up to PRESS
## interact to retrieve it. Drive a car into the StoreZone Area3D and the car is
## pulled out of the active world — hidden + reparented under this node and remembered
## by the tested GarageStorage model — so it survives until you want it back. Press
## interact at the garage and the most-recently parked car reappears at the door,
## visible and drivable again, the SAME node that drove in. Mirrors the drive-in /
## RefCounted-model pattern (cf. ContrabandDealer / VehicleModGarage), except it STORES
## the car instead of selling or destroying it. Self-wires by group (interactables /
## player_stats), so it needs no plumbing beyond a child Area3D + CollisionShape3D
## named "StoreZone" over the garage floor.
##
## The Interactable contract (see Interaction): joins group "interactables" and answers
## interact_prompt() + interact(player). Capacity / store / retrieve rules live in the
## unit-tested GarageStorage; this node's wiring is exercised by
## tests/garage_storage_probe.gd. Original system — no affiliation with any commercial
## title.

## Fired when a car is parked in the garage (its stable id).
signal vehicle_stored(vehicle_id: String)
## Fired when a car is pulled back out into the world (its stable id).
signal vehicle_retrieved(vehicle_id: String)

## GarageStorage garage this trigger parks into (any id is valid; created lazily).
@export var garage_id: String = "safehouse_downtown"
## Wallet charge to pull a car out, billed to PlayerStats (group player_stats). Free
## (no charge, never blocks) when 0; a positive fee aborts the retrieve if unaffordable.
@export var retrieve_fee: int = 0

## The live storage model. Public so a HUD / save layer can read what is parked.
var storage: GarageStorage
## vehicle_id -> the actual hidden Car node, so retrieve brings the SAME node back
## instead of respawning a fresh one from a scene. Mirrors storage.contents() order.
var _parked: Dictionary = {}

var _store_zone: Area3D
var _stats: Node = null


func _init() -> void:
	storage = GarageStorage.new()


func _ready() -> void:
	add_to_group("interactables")
	_store_zone = get_node_or_null("StoreZone") as Area3D
	if _store_zone != null:
		# Cars roll into the zone on the car physics layer; watch layer 2 the same way
		# the other drive-in triggers do so the car body trips the zone.
		_store_zone.collision_mask |= 2
		_store_zone.body_entered.connect(_on_body_entered)


## A stable per-car id that round-trips the same node: its name plus instance id, so
## two cars sharing a name still get distinct ids and the same node retrieves cleanly.
func _vehicle_id_of(car: Node) -> String:
	return car.name + "#" + str(car.get_instance_id())


func _on_body_entered(body: Node) -> void:
	if not (body is Car or body.is_in_group("starter_vehicles")):
		return
	# Only store a car the player actually drives in. A starter car merely placed
	# in the zone at world spawn sits at rest; ignore it so the boot-time vehicle
	# placement can't get a starter car silently swallowed by the garage.
	if body is RigidBody3D and (body as RigidBody3D).linear_velocity.length() < 1.0:
		return
	park_vehicle(body)


## Park a car: store its id in the model, then pull the node out of the active world by
## hiding it + reparenting it under this trigger so a hidden car neither renders nor
## simulates. Public + signal-free so a probe can drive it directly. Returns false (node
## untouched) when the model rejects the store — garage full / already stored / impounded.
func park_vehicle(car: Node3D) -> bool:
	var id := _vehicle_id_of(car)
	if not storage.store(garage_id, id):
		return false
	_parked[id] = car
	_remove_from_world(car)
	vehicle_stored.emit(id)
	return true


## Hide a parked car and move it under this node so it stops rendering and simulating.
func _remove_from_world(car: Node3D) -> void:
	var parent := car.get_parent()
	if parent != null:
		parent.remove_child(car)
	add_child(car)
	car.visible = false
	if car.has_method("set_physics_process"):
		car.set_physics_process(false)


## Pull a car back into the world. With no `vehicle_id` it hands back the most-recently
## parked car (LIFO); pass an explicit id to pull a SPECIFIC stored car (so a future
## garage UI can let the player choose, not just take the newest). Public + signal-free
## for the probe + the interact path. Returns the retrieved id, or "" when nothing
## matches or the (positive) fee can't be paid.
##
## The fee is charged only AFTER confirming the car is actually parked in THIS garage,
## so a retrieve that the model would reject can never silently pocket the player's money
## and hand back no car.
func retrieve_vehicle(_player: Node = null, vehicle_id: String = "") -> String:
	var id := vehicle_id if not vehicle_id.is_empty() else _next_to_retrieve()
	if id.is_empty() or storage.garage_of(id) != garage_id:
		return ""
	if not _charge_fee():
		return ""
	if not storage.retrieve(garage_id, id):
		return ""
	_return_to_world(id)
	vehicle_retrieved.emit(id)
	return id


## The id to hand back next: the most-recently parked node we still hold, falling back
## to the most-recently stored id the model lists for this garage (e.g. after a restore,
## once the live _parked node map is gone). Both paths agree on LIFO so the same press
## doesn't flip to handing back the OLDEST car after a save/load.
func _next_to_retrieve() -> String:
	var keys := _parked.keys()
	if not keys.is_empty():
		return str(keys[keys.size() - 1])
	var contents := storage.contents(garage_id)
	if not contents.is_empty():
		return str(contents[contents.size() - 1])
	return ""


## Bill the retrieve fee to the live wallet. True when free (fee <= 0) or paid; false
## when a positive fee can't be charged, so retrieve aborts and the car stays parked.
func _charge_fee() -> bool:
	if retrieve_fee <= 0:
		return true
	var stats := _player_stats()
	if stats == null or not stats.has_method("spend_money"):
		return false
	return stats.spend_money(retrieve_fee)


## Reparent a stored node back out to the world, at the garage door, and re-enable it.
func _return_to_world(id: String) -> void:
	var car := _parked.get(id) as Node3D
	_parked.erase(id)
	if car == null:
		return
	remove_child(car)
	var world := get_parent()
	if world != null:
		world.add_child(car)
	car.global_position = global_position - global_transform.basis.z * 6.0
	car.visible = true
	if car.has_method("set_physics_process"):
		car.set_physics_process(true)


## HUD hint: how full the garage is and that a press pulls a car out.
func interact_prompt() -> String:
	return "Garage (%d/%d) — retrieve" % [stored_count(), storage.capacity()]


## Interact = retrieve the next car (the drive-in store path is the Area3D, not a press).
func interact(player: Node) -> void:
	retrieve_vehicle(player)


## How many cars are parked in this garage (HUD / probe).
func stored_count() -> int:
	return storage.contents(garage_id).size()


func _player_stats() -> Node:
	if _stats == null or not is_instance_valid(_stats):
		_stats = get_tree().get_first_node_in_group("player_stats")
	return _stats
