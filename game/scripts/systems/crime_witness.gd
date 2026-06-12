class_name CrimeWitness
extends RefCounted
## Pure crime witness & reporting model — the perception layer under the wanted
## system. A crime only raises heat if someone actually *sees* it, and a witness
## needs time to call it in, so a mugging in an empty alley can go unreported and
## a silenced witness never makes the call.
##
## Two parts:
##   - Static line-of-sight + heat math (no state): can_witness / count_witnesses
##     / heat_for_crime. Cops pass a wider, longer cone than peds.
##   - A small stateful in-progress report (an instance): a witness has started
##     dialling; tick() runs the timer down, silence() cancels it.
##
## All XZ-plane (y is up), defensive against zero-length facings and NaN. Feeds a
## WantedTracker, which turns the returned heat into stars. Unit-tested headless
## (tests/unit/test_crime_witness.gd).

# Stateful in-progress report — only used by an instance (see _init / tick).
var _report_delay: float
var _elapsed: float = 0.0
var _silenced: bool = false


static func _ground(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## True if `observer` can see `crime_pos`: within `sight_range` AND inside the
## forward FOV cone of half-angle `fov_radians`. A zero/degenerate facing can't
## witness anything (no defined forward), and a crime sitting on top of the
## observer counts as seen (no direction to test).
static func can_witness(
	observer_pos: Vector3,
	observer_facing: Vector3,
	crime_pos: Vector3,
	sight_range: float,
	fov_radians: float
) -> bool:
	if sight_range <= 0.0 or fov_radians <= 0.0:
		return false
	var facing := _ground(observer_facing)
	if facing.length() < 0.0001:
		return false
	var to_crime := _ground(crime_pos - observer_pos)
	var dist := to_crime.length()
	if dist > sight_range:
		return false
	if dist < 0.0001:
		# Crime is right on the observer — no meaningful bearing, count it seen.
		return true
	# Compare the bearing to facing against the cone's half-angle. fov_radians is
	# the half-angle, so the dot must clear cos(half-angle).
	var cos_angle := facing.normalized().dot(to_crime.normalized())
	return cos_angle >= cos(clampf(fov_radians, 0.0, PI))


## How many of `observers` can witness the crime. Each entry is a dictionary
## {pos: Vector3, facing: Vector3}; missing keys default to a safe value (origin
## pos, zero facing -> can't see), so malformed entries are skipped not crashed.
static func count_witnesses(
	crime_pos: Vector3, observers: Array, sight_range: float, fov_radians: float
) -> int:
	var count := 0
	for entry in observers:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pos: Vector3 = entry.get("pos", Vector3.ZERO)
		var facing: Vector3 = entry.get("facing", Vector3.ZERO)
		if can_witness(pos, facing, crime_pos, sight_range, fov_radians):
			count += 1
	return count


## Partition `observers` into the ones who actually saw a crime. Each entry is
## a dictionary {pos: Vector3, facing: Vector3, is_police: bool} plus any
## caller payload (e.g. the scene node), carried through untouched so the
## caller can track the witnesses afterwards. Police get their own (wider,
## longer) cone than civilians — trained spotters. Returns
## {"witnesses": Array of seeing entries, "police_saw": bool}.
static func collect_witnesses(
	crime_pos: Vector3,
	observers: Array,
	ped_range: float,
	ped_fov: float,
	police_range: float,
	police_fov: float
) -> Dictionary:
	var witnesses: Array = []
	var police_saw := false
	for entry in observers:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var observer: Dictionary = entry
		var is_police: bool = bool(observer.get("is_police", false))
		var pos: Vector3 = observer.get("pos", Vector3.ZERO)
		var facing: Vector3 = observer.get("facing", Vector3.ZERO)
		var sight := police_range if is_police else ped_range
		var fov := police_fov if is_police else ped_fov
		if can_witness(pos, facing, crime_pos, sight, fov):
			witnesses.append(observer)
			police_saw = police_saw or is_police
	return {"witnesses": witnesses, "police_saw": police_saw}


## Heat a crime generates given how many people saw it. Zero witnesses -> 0 heat
## (it goes unreported, no matter how bad the crime). The first witness carries
## most of the weight; extra witnesses add diminishing returns via a saturating
## curve that approaches but never exceeds `base_heat`.
static func heat_for_crime(base_heat: float, witness_count: int) -> float:
	if witness_count <= 0 or base_heat <= 0.0:
		return 0.0
	# Saturating curve: 1 - 0.5^n. One witness -> 0.5, two -> 0.75, three ->
	# 0.875 ... asymptotes to 1.0 but never reaches base_heat.
	var fraction := 1.0 - pow(0.5, float(witness_count))
	return base_heat * fraction


# --- Stateful in-progress report ------------------------------------------


## A witness has started calling it in; `report_delay` seconds until the report
## lands. A non-positive delay means an instant report (lands on the first tick).
func _init(report_delay: float = 3.0) -> void:
	_report_delay = maxf(report_delay, 0.0)


## Advance the call by `delta` seconds. No effect once silenced or already
## reported; negative deltas are ignored so time never runs backwards.
func tick(delta: float) -> void:
	if _silenced or is_reported():
		return
	_elapsed = minf(_elapsed + maxf(delta, 0.0), _report_delay)


## True once the witness has finished calling it in (and wasn't silenced first).
func is_reported() -> bool:
	if _silenced:
		return false
	return _elapsed >= _report_delay


## How far along the call is, 0..1. Reads 1.0 the instant it completes.
func progress() -> float:
	if _silenced:
		return 0.0
	if _report_delay <= 0.0:
		return 1.0
	return clampf(_elapsed / _report_delay, 0.0, 1.0)


## Cancel the report before it lands — witness eliminated or fled. Permanently
## stuck unreported until reset(); further ticks do nothing.
func silence() -> void:
	_silenced = true


## Re-arm a fresh report: clears progress and the silenced flag.
func reset() -> void:
	_elapsed = 0.0
	_silenced = false
