class_name OriginMath
extends RefCounted
## Pure math for floating-origin shifts (M3). At a few kilometres from the
## origin, 32-bit floats stop resolving sub-centimetre detail and physics and
## rendering start to jitter; the fix is to teleport the whole world back so
## the player stays near (0, 0, 0). FloatingOrigin (the node) applies these
## numbers to the scene tree.

## Beyond this distance from the origin a shift is due. 2 km keeps absolute
## coordinates under ~4 km (after the worst-case diagonal), where float32
## still resolves ~0.25 mm.
const DEFAULT_THRESHOLD_M: float = 2048.0

## Shifts snap to this grid so reconstructed absolute positions accumulate
## exact multiples instead of drifting by float error.
const DEFAULT_GRID_M: float = 256.0


## True when the anchor has strayed far enough (horizontally) to need a shift.
## Height is ignored: altitude alone doesn't break precision budgets here and
## shifting Y would fight gravity-driven systems.
static func should_shift(anchor_pos: Vector3, threshold: float = DEFAULT_THRESHOLD_M) -> bool:
	var planar := Vector3(anchor_pos.x, 0.0, anchor_pos.z)
	return planar.length_squared() > threshold * threshold


## The translation to apply to every world root so the anchor lands near the
## origin: minus the anchor position, snapped to the grid, Y untouched.
static func shift_for(anchor_pos: Vector3, grid: float = DEFAULT_GRID_M) -> Vector3:
	var snapped_x := snappedf(anchor_pos.x, grid)
	var snapped_z := snappedf(anchor_pos.z, grid)
	return Vector3(-snapped_x, 0.0, -snapped_z)


## World-space origin offset after applying a shift: tracks where the engine
## origin sits in absolute world coordinates, so absolute = local - offset.
static func accumulate_offset(current_offset: Vector3, shift: Vector3) -> Vector3:
	return current_offset + shift


## Reconstruct an absolute world position from engine-local coordinates.
static func to_absolute(local_pos: Vector3, origin_offset: Vector3) -> Vector3:
	return local_pos - origin_offset
