class_name Interaction
extends RefCounted
## Pure target-selection for the player's interact key: given the world
## positions of nearby interactables and where the player is, pick the one to
## act on. Scene-free so it unit-tests headless (tests/unit/test_interaction.gd).
##
## The Interactable contract (duck-typed, the same way "vehicles" work): any
## Node3D in group "interactables" that implements
##     interact(player: Node) -> void      # do the thing
##     interact_prompt() -> String         # HUD hint, e.g. "Enter shop"
## Player gathers those nodes, asks nearest() which one is in reach, shows its
## prompt, and calls interact() on the key press. A building door or a prop
## (ATM, bench) becomes interactive just by joining the group and answering
## those two methods, with no change to the player.

## Returned by nearest() when nothing qualifies.
const NONE := -1


## Index of the closest point within `reach` metres of `from`, or NONE.
## The reach boundary is inclusive; ties resolve to the lower index (stable);
## a non-positive reach selects nothing.
static func nearest(points: PackedVector3Array, from: Vector3, reach: float) -> int:
	if reach <= 0.0:
		return NONE
	var best := NONE
	var best_distance := INF
	for i in points.size():
		var distance := from.distance_to(points[i])
		if distance <= reach and distance < best_distance:
			best = i
			best_distance = distance
	return best
