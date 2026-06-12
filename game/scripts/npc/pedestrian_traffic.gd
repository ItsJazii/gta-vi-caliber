class_name PedestrianTraffic
extends RefCounted
## Pure traffic-awareness math for pedestrians — the "look before you cross, and
## jump when a car runs the light" instinct that keeps crowds from walking
## blindly into the road. Complements NpcSteering (which handles sidewalk flow)
## by turning nearby car positions+velocities into a threat score, a curb
## go/no-go decision, and a lateral dodge impulse.
##
## All static, Vector3-in / scalar-or-Vector3-out, no nodes — unit-tested
## headless (tests/unit/test_pedestrian_traffic.gd). Work happens in the XZ
## plane (y is up); inputs are flattened with NpcSteering.ground(). A pedestrian
## node blends dodge_velocity() into NpcSteering.combine() when threat is high,
## and gates stepping off a curb on safe_to_cross().
##
## `cars` arguments are an Array of {pos: Vector3, vel: Vector3} dictionaries.

const EPSILON := 0.0001


## True when the gap between pedestrian and car is shrinking (the car is closing
## in), rather than the car already moving away. Uses the sign of d/dt |r|^2.
static func is_closing(p_pos: Vector3, p_vel: Vector3, c_pos: Vector3, c_vel: Vector3) -> bool:
	var r := NpcSteering.ground(p_pos - c_pos)
	var v := NpcSteering.ground(p_vel - c_vel)
	return r.dot(v) < 0.0


## Seconds until pedestrian and car are at their nearest point, assuming both
## hold velocity. 0 when they are not closing (already past, or parallel), so
## callers never react to a car that is leaving.
static func time_to_closest_approach(
	p_pos: Vector3, p_vel: Vector3, c_pos: Vector3, c_vel: Vector3
) -> float:
	var r := NpcSteering.ground(p_pos - c_pos)
	var v := NpcSteering.ground(p_vel - c_vel)
	var vv := v.dot(v)
	if vv < EPSILON:
		return 0.0
	return maxf(-r.dot(v) / vv, 0.0)


## How close the car and pedestrian come (planar) if both hold velocity from now.
static func closest_approach_distance(
	p_pos: Vector3, p_vel: Vector3, c_pos: Vector3, c_vel: Vector3
) -> float:
	var t := time_to_closest_approach(p_pos, p_vel, c_pos, c_vel)
	var p_future := NpcSteering.ground(p_pos) + NpcSteering.ground(p_vel) * t
	var c_future := NpcSteering.ground(c_pos) + NpcSteering.ground(c_vel) * t
	return (p_future - c_future).length()


## Danger of one car, 0 (safe) .. 1 (imminent broadside). Non-zero only when the
## car is closing, will miss by less than `react_radius`, and arrives within
## `horizon_sec`. Blends proximity and urgency so a car that will shave past you
## next instant scores near 1 and a distant slow approach scores near 0.
static func car_threat(
	p_pos: Vector3,
	p_vel: Vector3,
	c_pos: Vector3,
	c_vel: Vector3,
	react_radius: float,
	horizon_sec: float
) -> float:
	if react_radius <= 0.0 or horizon_sec <= 0.0:
		return 0.0
	if not is_closing(p_pos, p_vel, c_pos, c_vel):
		return 0.0
	var t := time_to_closest_approach(p_pos, p_vel, c_pos, c_vel)
	if t > horizon_sec:
		return 0.0
	var miss := closest_approach_distance(p_pos, p_vel, c_pos, c_vel)
	if miss >= react_radius:
		return 0.0
	var proximity := 1.0 - miss / react_radius
	var urgency := 1.0 - t / horizon_sec
	return clampf(proximity * urgency, 0.0, 1.0)


## The most threatening car around the pedestrian. Returns
## {threat, index, pos, vel}; index is -1 and threat 0.0 when nothing qualifies.
static func nearest_threat(
	p_pos: Vector3, p_vel: Vector3, cars: Array, react_radius: float, horizon_sec: float
) -> Dictionary:
	var best := {"threat": 0.0, "index": -1, "pos": Vector3.ZERO, "vel": Vector3.ZERO}
	for i in cars.size():
		var car := cars[i] as Dictionary
		var c_pos := car.get("pos", Vector3.ZERO) as Vector3
		var c_vel := car.get("vel", Vector3.ZERO) as Vector3
		var threat := car_threat(p_pos, p_vel, c_pos, c_vel, react_radius, horizon_sec)
		if threat > best["threat"]:
			best = {"threat": threat, "index": i, "pos": c_pos, "vel": c_vel}
	return best


## A lateral escape velocity to clear the car's path: perpendicular to the car's
## heading, toward whichever side the pedestrian is already on (shortest way out
## of the lane). Falls back to straight-away-from-car when the car is stopped.
static func dodge_velocity(
	p_pos: Vector3, c_pos: Vector3, c_vel: Vector3, max_speed: float
) -> Vector3:
	var heading := NpcSteering.ground(c_vel)
	var offset := NpcSteering.ground(p_pos - c_pos)
	if heading.length() < EPSILON:
		if offset.length() < EPSILON:
			return Vector3.ZERO
		return offset.normalized() * max_speed
	var perp := Vector3(heading.z, 0.0, -heading.x).normalized()
	var side := signf(offset.dot(perp))
	if side == 0.0:
		side = 1.0
	return perp * side * max_speed


## Curb go/no-go: false when any car is closing on the pedestrian's spot, will
## pass within `danger_radius`, and gets there within `safe_gap_sec`. The
## pedestrian is treated as stationary (deciding whether to step off), so this is
## the "is there a gap in traffic" check.
static func safe_to_cross(
	p_pos: Vector3, cars: Array, danger_radius: float, safe_gap_sec: float
) -> bool:
	for car in cars:
		var c := car as Dictionary
		var c_pos := c.get("pos", Vector3.ZERO) as Vector3
		var c_vel := c.get("vel", Vector3.ZERO) as Vector3
		if not is_closing(p_pos, Vector3.ZERO, c_pos, c_vel):
			continue
		var t := time_to_closest_approach(p_pos, Vector3.ZERO, c_pos, c_vel)
		if t > safe_gap_sec:
			continue
		if closest_approach_distance(p_pos, Vector3.ZERO, c_pos, c_vel) <= danger_radius:
			return false
	return true
