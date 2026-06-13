class_name BuildingEntry
extends RefCounted
## Pure placement math for stepping into a building interior: where to recentre
## the footprint so the room builds around the origin (away from the district's
## large local coordinates), and where to drop the player once inside. Scene-free
## so it unit-tests headless (tests/unit/test_building_entry.gd). The room mesh
## itself comes from InteriorBuilder; which buildings and where their door sits
## come from Enterable. This module only does the arithmetic between them.


## Average of the footprint points (its rough centre). Zero for an empty ring.
static func centroid(footprint: PackedVector2Array) -> Vector2:
	var n := footprint.size()
	if n == 0:
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in footprint:
		sum += p
	return sum / float(n)


## The footprint shifted so `centre` lands on the origin. Builds a room around
## (0,0), which keeps interior vertices small and precise no matter how far the
## district sits from its own origin.
static func recenter(footprint: PackedVector2Array, centre: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in footprint:
		out.append(p - centre)
	return out


## Where to place the player inside, given the door point already expressed in
## the recentred (centroid-at-origin) frame. Pulls `inset` metres in from the
## door toward the centre so the body spawns within the walls, never past the
## centre (a tiny building just puts you at its middle).
static func entry_offset(door_recentred: Vector2, inset: float) -> Vector2:
	var length := door_recentred.length()
	if length <= 0.0001:
		return Vector2.ZERO
	var pulled := maxf(length - inset, 0.0)
	return door_recentred * (pulled / length)
