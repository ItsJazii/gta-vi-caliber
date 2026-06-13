class_name NpcSteering
extends RefCounted
## Pure steering math for pedestrians — the locomotion side of NPC life. Turns a
## goal position and a handful of neighbours into a desired velocity, so crowds
## flow along sidewalks, ease to a stop at destinations, and don't telescope
## into each other. Boids-lite: seek, arrive, separation, path following.
##
## All static, all Vector3-in / Vector3-out, no nodes — unit-tests headless
## (tests/unit/test_npc_steering.gd). The NpcAgent feeds the result to a
## CharacterBody3D; gravity and collision stay the engine's job. Work happens in
## the XZ plane (y is up); callers flatten with `ground()` where it matters.


## Drop the vertical component — pedestrians steer on the ground plane.
static func ground(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Desired velocity heading straight at `target` at full speed. Zero when already
## on top of it (avoids a NaN from normalising a zero vector).
static func seek(pos: Vector3, target: Vector3, max_speed: float) -> Vector3:
	var to := ground(target - pos)
	if to.length() < 0.0001:
		return Vector3.ZERO
	return to.normalized() * max_speed


## Like seek, but ramps speed down inside `slow_radius` so the NPC eases to a
## halt on its mark instead of jittering across it. Stops within `arrive_radius`.
static func arrive(
	pos: Vector3, target: Vector3, max_speed: float, slow_radius: float, arrive_radius: float = 0.25
) -> Vector3:
	var to := ground(target - pos)
	var dist := to.length()
	if dist <= arrive_radius:
		return Vector3.ZERO
	var speed := max_speed
	if dist < slow_radius and slow_radius > 0.0:
		speed = max_speed * (dist / slow_radius)
	return to.normalized() * speed


## Repulsion from nearby NPCs, weighted by closeness (closer = stronger push),
## so personal space is respected without anyone phasing through anyone. Returns
## a velocity-scale vector you blend into the desired velocity (see `combine`).
static func separation(pos: Vector3, neighbors: Array, radius: float, max_speed: float) -> Vector3:
	if radius <= 0.0:
		return Vector3.ZERO
	var push := Vector3.ZERO
	for other in neighbors:
		var away := ground(pos - (other as Vector3))
		var d := away.length()
		if d > 0.0001 and d < radius:
			# Inverse falloff: a crowder at the elbow shoves far harder than one
			# at arm's length.
			push += away.normalized() * (1.0 - d / radius)
	if push.length() < 0.0001:
		return Vector3.ZERO
	# Preserve the inverse-falloff magnitude accumulated above — normalizing it
	# away made a lone distant neighbour shove exactly as hard as one at the
	# elbow, contradicting the "closer shoves harder" doc. Only clamp when a dense
	# crowd's combined push would exceed max_speed.
	return push.limit_length(max_speed)


## Blend weighted steering vectors and clamp the result to `max_speed`, so no
## combination of urges can launch an NPC faster than it can walk.
static func combine(vectors: Array, weights: Array, max_speed: float) -> Vector3:
	var sum := Vector3.ZERO
	var count := mini(vectors.size(), weights.size())
	for i in count:
		sum += (vectors[i] as Vector3) * float(weights[i])
	if sum.length() > max_speed:
		sum = sum.normalized() * max_speed
	return sum


## Which waypoint to head for: advance past any already reached within
## `accept_radius`. Returns the new index (clamped to the last point), so a path
## walker just calls this each tick and seeks `waypoints[index]`.
static func advance_waypoint(
	pos: Vector3, waypoints: Array, index: int, accept_radius: float
) -> int:
	var i := index
	while i < waypoints.size() - 1:
		var wp := waypoints[i] as Vector3
		if ground(wp - pos).length() <= accept_radius:
			i += 1
		else:
			break
	return clampi(i, 0, maxi(waypoints.size() - 1, 0))
