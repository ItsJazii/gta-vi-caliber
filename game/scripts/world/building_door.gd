class_name BuildingDoor
extends Node3D
## A doorway the player can step through. One interactable type serves both
## sides: the district spawns "Enter" doors at street frontages (is_exit = false),
## and the interior manager spawns a single "Exit" door inside the room
## (is_exit = true). Both just answer the interactables contract and hand off to
## BuildingInterior, which owns the fade and the teleport.

## Footprint in district-local metres (only the enter door needs it; the manager
## recentres it to build the room).
var footprint: PackedVector2Array = PackedVector2Array()
## The door point in that same district-local frame.
var door_local: Vector2 = Vector2.ZERO
## False = street door (enter), true = the in-room door (exit).
var is_exit: bool = false


func _ready() -> void:
	add_to_group("interactables")


func interact_prompt() -> String:
	return "Exit" if is_exit else "Enter"


func interact(player: Node) -> void:
	var interior := BuildingInterior.instance(get_tree())
	if interior == null:
		return
	var who := player as Node3D
	if is_exit:
		interior.leave(who)
	else:
		interior.enter(who, self)
