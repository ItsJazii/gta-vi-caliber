class_name TrafficMotion
extends RefCounted
## Pure kinematic steering for ambient traffic — turn-rate-limited waypoint
## following on the XZ plane.
##
## Static, scene-free and deterministic so it unit-tests headless
## (tests/unit/test_traffic_motion.gd). A TrafficCar holds the mutable state
## (position, heading, which waypoint) and calls these each physics frame; the
## TrafficDirector routes cars with NavGrid.find_path and hands the waypoints in.
## Heading is a planar unit vector (y = 0); a car can only swing it by
## max_turn_rate·delta per frame, which is what makes cars arc through turns
## instead of pivoting on the spot.

const UP: Vector3 = Vector3.UP


## Planar (XZ) distance between two points.
static func planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Planar unit direction a→b, or ZERO if effectively coincident.
static func planar_dir(a: Vector3, b: Vector3) -> Vector3:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


## Rotate `heading` toward `desired` by at most max_step radians, around +Y.
## Both are treated as planar unit vectors; returns a planar unit vector. If
## desired is zero (no target) the heading is held.
static func turn_toward(heading: Vector3, desired: Vector3, max_step: float) -> Vector3:
	if desired.length() < 0.0001:
		return heading
	var h := Vector3(heading.x, 0.0, heading.z)
	h = h.normalized() if h.length() > 0.0001 else desired
	var dot := clampf(h.dot(desired), -1.0, 1.0)
	var angle := acos(dot)
	if angle <= max_step:
		return desired
	var sign_dir := signf(h.cross(desired).y)
	if sign_dir == 0.0:
		sign_dir = 1.0  # exactly opposite: pick a consistent way around
	return h.rotated(UP, sign_dir * max_step).normalized()


## Speed multiplier for how hard the car must turn to face `desired` from its
## current `heading`: full speed when already lined up, easing down to `min_scale`
## for a sharp (>=90°) turn. Real drivers brake into corners — this keeps a car
## from overshooting a tight junction arc and wandering off the far side. Pure.
static func corner_speed_scale(
	heading: Vector3, desired: Vector3, min_scale: float = 0.45
) -> float:
	if desired.length() < 0.0001:
		return 1.0
	var h := Vector3(heading.x, 0.0, heading.z)
	if h.length() < 0.0001:
		return 1.0
	var dot := clampf(h.normalized().dot(desired.normalized()), -1.0, 1.0)
	# dot 1 (aligned) -> full; dot <= 0 (>=90° off) -> min; cos(30°)≈0.87 -> full.
	var t := clampf(dot / 0.87, 0.0, 1.0)
	return lerpf(min_scale, 1.0, t)


## Advance one frame toward `target`: swing the heading (capped by max_turn_rate)
## then step forward along the new heading by speed·delta. Returns the updated
## {position, heading}. Pure — the caller owns the state.
static func step(
	pos: Vector3,
	heading: Vector3,
	target: Vector3,
	speed: float,
	max_turn_rate: float,
	delta: float
) -> Dictionary:
	var desired := planar_dir(pos, target)
	var new_heading := turn_toward(heading, desired, max_turn_rate * delta)
	var new_pos := pos + new_heading * speed * delta
	new_pos.y = pos.y
	return {"position": new_pos, "heading": new_heading}


## Advance the waypoint cursor while the car is within `tolerance` of the
## current waypoint, so a car that overshoots a tight corner still latches onto
## the next one. Returns the new index (clamped to waypoints.size(), meaning
## "route finished").
static func advance_waypoint(
	pos: Vector3, waypoints: PackedVector3Array, index: int, tolerance: float
) -> int:
	var i := index
	while i < waypoints.size() and planar_distance(pos, waypoints[i]) <= tolerance:
		i += 1
	return i
