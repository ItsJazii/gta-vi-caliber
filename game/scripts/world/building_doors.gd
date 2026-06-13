class_name BuildingDoors
extends RefCounted
## Spawns "Enter" doors on a district's enterable buildings (named, or a public-
## facing OSM type). Static like DistrictFacadePanels so district_loader stays a
## thin orchestrator: Enterable picks the subset and the door point, each door is
## a BuildingDoor that hands off to BuildingInterior for the fade and the room.

## Doors per district (caps interiors so a dense district doesn't carpet the
## street) and the trigger height above the pavement.
const MAX_DOORS: int = 14
const DOOR_Y: float = 1.2


## Add an enter-door under `loader` for each enterable building. `proj` projects
## footprints into the loader's local metre frame (the same frame as the meshes).
static func build(loader: Node3D, buildings: Array, proj: GeoProjection) -> void:
	for b in Enterable.pick(buildings, MAX_DOORS):
		var ring := _project_ring(b.get("footprint", []), proj)
		if ring.size() < 3:
			continue
		var door := BuildingDoor.new()
		door.footprint = ring
		door.door_local = Enterable.door_point(ring)
		door.position = Vector3(door.door_local.x, DOOR_Y, door.door_local.y)
		loader.add_child(door)


static func _project_ring(raw: Array, proj: GeoProjection) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for pair in raw:
		ring.append(proj.to_local_2d(pair[0], pair[1]))
	return ring
