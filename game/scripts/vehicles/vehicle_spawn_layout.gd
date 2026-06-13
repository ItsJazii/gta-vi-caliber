class_name VehicleSpawnLayout
extends RefCounted
## Deterministic placement for the starter vehicles around the player spawn.

const LANE_OFFSET: float = 3.0
const FIRST_DISTANCE: float = 8.0
const SECOND_DISTANCE: float = 15.0


static func starter_transforms(spawn: Vector3, yaw: float) -> Array[Transform3D]:
	var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0))
	var forward := -basis.z
	var right := basis.x
	return [
		Transform3D(basis, spawn + forward * FIRST_DISTANCE + right * LANE_OFFSET),
		Transform3D(basis, spawn + forward * SECOND_DISTANCE - right * LANE_OFFSET),
	]
