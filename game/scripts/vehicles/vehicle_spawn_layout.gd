class_name VehicleSpawnLayout
extends RefCounted
## Deterministic placement for the starter vehicles around the player spawn. They
## park at the KERB of the spawn road (one on each side, nose down the street),
## offset to the carriageway edge from the road's width — so they sit on the side
## and never block the travel lanes ambient traffic drives in.

const FIRST_DISTANCE: float = 8.0
const SECOND_DISTANCE: float = 15.0
## How far inside the carriageway edge a parked car's centre sits (≈ half a car
## width plus a little clearance), so the body lines the kerb without poking out.
const CURB_INSET: float = 1.4
## Keep the kerb offset at least this far from the centre even on a narrow road.
const MIN_CURB_OFFSET: float = 1.6
## Carriageway width (m) assumed when the caller doesn't know the spawn road's.
const DEFAULT_ROAD_WIDTH: float = 12.0


## Two starter cars parked along the kerbs of the spawn road: one on each side,
## facing down the street, offset to the carriageway edge from `road_width`.
static func starter_transforms(
	spawn: Vector3, yaw: float, road_width: float = DEFAULT_ROAD_WIDTH
) -> Array[Transform3D]:
	var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0))
	var forward := -basis.z
	var right := basis.x
	var kerb := kerb_offset(road_width)
	return [
		Transform3D(basis, spawn + forward * FIRST_DISTANCE + right * kerb),
		Transform3D(basis, spawn + forward * SECOND_DISTANCE - right * kerb),
	]


## Lateral distance from the road centre to park a car at the kerb of a
## `road_width`-wide carriageway. Pure, so it unit-tests without a scene.
static func kerb_offset(road_width: float) -> float:
	return maxf(road_width * 0.5 - CURB_INSET, MIN_CURB_OFFSET)
