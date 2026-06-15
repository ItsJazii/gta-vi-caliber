class_name TrafficSignal
extends RefCounted
## A 2-phase (north-south / east-west) intersection signal plus static right-of-way
## helpers, so ambient cars stop and go at junctions instead of phasing through one
## another. Stateful light-cycle instance + scene-free static rules.
##
## Pure and deterministic — unit-tested headless in tests/unit/test_traffic_signal.gd.
## The TrafficDirector ticks one instance per junction, asks light_for(axis) for a
## car's approach axis, and uses should_stop/is_clear_to_go to gate entry. Car-
## following gaps stay in TrafficFlow; converging-car priority stays in TrafficRules.
##
## Cycle order: NS_GREEN -> NS_YELLOW -> NS_ALL_RED -> EW_GREEN -> EW_YELLOW ->
## EW_ALL_RED -> NS_GREEN. While one axis shows GREEN or YELLOW the cross axis is
## RED; in the two all-red clearance intervals BOTH axes are RED, so the box empties
## before the cross street gets its green.

enum Phase { NS_GREEN, NS_YELLOW, NS_ALL_RED, EW_GREEN, EW_YELLOW, EW_ALL_RED }
enum Light { GREEN, YELLOW, RED }
enum Axis { NS, EW }

var _green_time: float
var _yellow_time: float
var _all_red_time: float
var _phase: int = Phase.NS_GREEN
var _elapsed: float = 0.0


## Seconds per interval, each clamped to a small positive minimum so the cycle always
## advances. all_red_time is the all-red clearance interval inserted between the NS
## and EW greens (set it to a small value for effectively no clearance). Defaults
## mirror TrafficSignalField's cull-safe timings; see there for the budget.
func _init(green_time: float = 4.0, yellow_time: float = 1.5, all_red_time: float = 0.75) -> void:
	_green_time = maxf(green_time, 0.001)
	_yellow_time = maxf(yellow_time, 0.001)
	_all_red_time = maxf(all_red_time, 0.001)


## Advance the cycle by delta seconds, rolling over to the next phase (and possibly
## several phases for a large delta). Negative or zero delta is ignored.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_elapsed += delta
	var limit := _duration(_phase)
	while _elapsed >= limit:
		_elapsed -= limit
		_phase = _next_phase(_phase)
		limit = _duration(_phase)


## Current phase (one of Phase.*).
func phase() -> int:
	return _phase


## Seconds spent in the current phase.
func time_in_phase() -> float:
	return _elapsed


## Total seconds for one full NS+EW cycle: both greens, both yellows and both
## all-red clearance intervals.
func cycle_length() -> float:
	return 2.0 * (_green_time + _yellow_time + _all_red_time)


## Light shown to the given axis (Axis.NS or Axis.EW) -> Light.GREEN/YELLOW/RED.
func light_for(axis: int) -> int:
	match _phase:
		Phase.NS_GREEN:
			return Light.GREEN if axis == Axis.NS else Light.RED
		Phase.NS_YELLOW:
			return Light.YELLOW if axis == Axis.NS else Light.RED
		Phase.EW_GREEN:
			return Light.GREEN if axis == Axis.EW else Light.RED
		Phase.EW_YELLOW:
			return Light.YELLOW if axis == Axis.EW else Light.RED
	# NS_ALL_RED / EW_ALL_RED (and any unexpected phase): every approach stops.
	return Light.RED


## Restart the cycle at the start of NS_GREEN.
func reset() -> void:
	_phase = Phase.NS_GREEN
	_elapsed = 0.0


## Should an approaching car stop for this light? RED always stops; GREEN never does;
## YELLOW stops only if the car can brake comfortably before the stop line — if it is
## too close to stop in time (the "dilemma zone") it proceeds to clear the box.
## distance_to_line is metres to the stop line, speed m/s, comfortable_brake m/s².
static func should_stop(
	light: int, distance_to_line: float, speed: float, comfortable_brake: float
) -> bool:
	if light == Light.GREEN:
		return false
	if light == Light.RED:
		return true
	# YELLOW: stop only if there is room to brake comfortably before the line.
	if speed <= 0.0:
		return true
	var brake := maxf(comfortable_brake, 0.001)
	var braking_distance := (speed * speed) / (2.0 * brake)
	return distance_to_line >= braking_distance


## Is it safe to enter the junction? Only on GREEN, and only when no cross traffic is
## still in the box (covers a late-clearing car after a phase change).
static func is_clear_to_go(light: int, cross_traffic_present: bool) -> bool:
	return light == Light.GREEN and not cross_traffic_present


## Right-of-way for an uncontrolled / four-way-stop junction: does the car heading
## my_dir yield to the car heading other_dir? Rule: yield to the vehicle on your
## right, and when the cross car comes head-on (oncoming) also yield, since a turn
## across it must give way. Directions are planar (XZ) heading vectors. A car never
## yields to one going the same way or already behind the right-hand boundary.
static func yields_to(my_dir: Vector3, other_dir: Vector3) -> bool:
	var mine := Vector3(my_dir.x, 0.0, my_dir.z)
	var theirs := Vector3(other_dir.x, 0.0, other_dir.z)
	if mine.length() < 0.0001 or theirs.length() < 0.0001:
		return false
	mine = mine.normalized()
	theirs = theirs.normalized()
	var dot := mine.dot(theirs)
	# Same direction of travel — no conflict, no yield.
	if dot > 0.7:
		return false
	# Oncoming (roughly head-on) — yield (e.g. turning across oncoming traffic).
	if dot < -0.7:
		return true
	# Crossing: the other approaches from our right if their heading points left of
	# ours. right = mine × up; a car coming from our right travels toward -right,
	# i.e. theirs · right < 0.
	var right := mine.cross(Vector3.UP)
	return theirs.dot(right) < 0.0


# --- internals ---


func _duration(phase_id: int) -> float:
	match phase_id:
		Phase.NS_YELLOW, Phase.EW_YELLOW:
			return _yellow_time
		Phase.NS_ALL_RED, Phase.EW_ALL_RED:
			return _all_red_time
	return _green_time


func _next_phase(phase_id: int) -> int:
	match phase_id:
		Phase.NS_GREEN:
			return Phase.NS_YELLOW
		Phase.NS_YELLOW:
			return Phase.NS_ALL_RED
		Phase.NS_ALL_RED:
			return Phase.EW_GREEN
		Phase.EW_GREEN:
			return Phase.EW_YELLOW
		Phase.EW_YELLOW:
			return Phase.EW_ALL_RED
	return Phase.NS_GREEN
