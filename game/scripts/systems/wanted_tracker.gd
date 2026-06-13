class_name WantedTracker
extends Node
## Scene bridge for the wanted system.
##
## Owns a WantedSystem (pure, tested), listens for crimes from the player's
## WeaponController, cools heat each frame, and exposes stars()/is_wanted() for
## police AI and HUDs. Joins group "wanted" so anything can find it without a
## hard reference. One per world scene.
##
## Gameplay crimes are perception-gated through CrimeWitness: heat only lands
## if a pedestrian or cop actually saw the crime. Civilian witnesses take
## report_delay_sec to call it in (and a silenced/dead witness never does);
## a cop witness radios it in instantly.

signal stars_changed(stars: int)

@export var wound_heat: float = 0.7
@export var kill_heat: float = 2.5
@export var decay_rate: float = 0.35
@export var heat_cap: float = 20.0
## Civilian perception: how far and how wide (half-angle) a ped can see a crime.
@export var ped_sight_range: float = 24.0
@export var ped_fov_degrees: float = 70.0
## Police perception: trained spotters get a longer, wider cone.
@export var police_sight_range: float = 40.0
@export var police_fov_degrees: float = 100.0
## Seconds a civilian witness takes to call a crime in.
@export var report_delay_sec: float = 2.5
## Seconds after a crime during which the player still counts as "actively
## committing", so heat HOLDS instead of decaying. WantedSystem has this branch
## (tick's committing flag) but the tracker hardcoded committing=false every
## frame, so heat decayed even mid-rampage and this hold was dead.
@export var crime_active_window: float = 0.6

var _wanted: WantedSystem
var _stars: int = -1
var _pending_reports: Array[Dictionary] = []
var _crime_timer: float = 0.0


func _ready() -> void:
	_wanted = WantedSystem.new(decay_rate, heat_cap)
	add_to_group("wanted")
	call_deferred("_bind")


func _bind() -> void:
	for controller in get_tree().get_nodes_in_group("weapon_controller"):
		if controller.has_signal("crime_committed"):
			controller.crime_committed.connect(_on_crime)


func _on_crime(killed: bool, crime_pos: Vector3) -> void:
	report_witnessed_crime(killed, crime_pos)


## Direct, unconditional heat — the crime is taken as already reported
## (scripted events, probes, anything that bypasses perception).
func report_crime(killed: bool) -> void:
	_wanted.add_crime(kill_heat if killed else wound_heat)
	_crime_timer = crime_active_window
	_refresh()


## A crime at a world position that someone must have SEEN for heat to land.
## A lone kill in an empty alley goes unreported; a busy street saturates
## toward double the direct tuning (one witness lands exactly report_crime's
## heat, a crowd approaches 2x).
func report_witnessed_crime(killed: bool, crime_pos: Vector3) -> void:
	# The player just committed a crime (seen or not) — mark them actively
	# committing so heat holds through a rampage even before/without a witness.
	_crime_timer = crime_active_window
	var seen: Dictionary = CrimeWitness.collect_witnesses(
		crime_pos,
		_gather_observers(),
		ped_sight_range,
		deg_to_rad(ped_fov_degrees),
		police_sight_range,
		deg_to_rad(police_fov_degrees)
	)
	var witnesses: Array = seen["witnesses"]
	if witnesses.is_empty():
		return
	var base := (kill_heat if killed else wound_heat) * 2.0
	var heat := CrimeWitness.heat_for_crime(base, witnesses.size())
	if bool(seen["police_saw"]):
		# A cop saw it — no phone call needed, the report is instant.
		_wanted.add_crime(heat)
		_refresh()
		return
	var nodes: Array[Node3D] = []
	for entry in witnesses:
		var node := (entry as Dictionary).get("node") as Node3D
		if node != null:
			nodes.append(node)
	_pending_reports.append(
		{"report": CrimeWitness.new(report_delay_sec), "heat": heat, "witnesses": nodes}
	)


func _process(delta: float) -> void:
	# Hold heat while the player is still actively committing crimes (the timer is
	# re-armed on each crime); only decay once the rampage has paused.
	_crime_timer = maxf(_crime_timer - delta, 0.0)
	_wanted.tick(delta, _crime_timer > 0.0)
	_tick_reports(delta)
	_refresh()


# Advance in-progress witness calls: a report whose witnesses all died is
# silenced (the call never lands); a completed call converts into heat.
func _tick_reports(delta: float) -> void:
	if _pending_reports.is_empty():
		return
	var finished: Array[Dictionary] = []
	for entry in _pending_reports:
		var report: CrimeWitness = entry["report"]
		if _all_witnesses_down(entry["witnesses"]):
			report.silence()
			finished.append(entry)
			continue
		report.tick(delta)
		if report.is_reported():
			_wanted.add_crime(float(entry["heat"]))
			finished.append(entry)
	for entry in finished:
		_pending_reports.erase(entry)


func _all_witnesses_down(witnesses: Array[Node3D]) -> bool:
	for node in witnesses:
		if not is_instance_valid(node):
			continue
		if node.has_method("is_dead") and node.is_dead():
			continue
		return false
	return true


# Snapshot every live pedestrian and cop as a CrimeWitness observer entry.
# NPC roots never yaw — their Rig child turns to face travel — so facing reads
# the rig's forward (-Z) when present. The scene node rides along so pending
# reports can tell whether their witnesses were silenced.
func _gather_observers() -> Array:
	var observers: Array = []
	for group_info in [
		{"group": "pedestrians", "is_police": false}, {"group": "police", "is_police": true}
	]:
		var info: Dictionary = group_info
		for node in get_tree().get_nodes_in_group(String(info["group"])):
			var spatial := node as Node3D
			if spatial == null:
				continue
			if spatial.has_method("is_dead") and spatial.is_dead():
				continue
			var facing_node := spatial.get_node_or_null("Rig") as Node3D
			if facing_node == null:
				facing_node = spatial
			(
				observers
				. append(
					{
						"pos": spatial.global_position,
						"facing": -facing_node.global_transform.basis.z,
						"is_police": bool(info["is_police"]),
						"node": spatial,
					}
				)
			)
	return observers


func stars() -> int:
	return _wanted.stars()


func is_wanted() -> bool:
	return _wanted.is_wanted()


## Wipe all heat (e.g. on death/arrest). The player escapes the law.
func clear() -> void:
	_wanted.heat = 0.0
	_refresh()


## Snapshot for SaveManager.
func serialize() -> Dictionary:
	return {"heat": _wanted.heat}


func restore(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("heat"):
		return
	_wanted.heat = maxf(float((data as Dictionary)["heat"]), 0.0)
	_refresh()


func _refresh() -> void:
	var current := _wanted.stars()
	if current != _stars:
		_stars = current
		stars_changed.emit(current)
