class_name ResponderDispatcher
extends Node
## Self-wiring world-life director: when the player kills someone with gun violence
## (WeaponController.crime_committed with killed=true), an ambulance rolls out — it
## spawns a short drive away, sirens in to the body, treats it, and leaves. The city
## now answers a shooting with *help*, not just pursuit. It finds the weapon by group
## `weapon_controller` (like CrowdPanicDirector / WantedTracker) and reads the live
## heat off the `wanted` group, then runs the pure, unit-tested EmergencyServices
## response timer to drive the siren-run → on-scene → treating → clear sequence.
## Drop the node in a scene; no per-scene plumbing. Exercised by
## tests/responder_dispatcher_probe.gd.
##
## The weapon may arm/appear after this node, so the connection is polled until it
## lands; processing then continues to tick and move every active responder.

## Emitted when an ambulance is dispatched to a shooting at `incident_pos`.
signal responder_dispatched(incident_pos: Vector3)
## Emitted once a responder has finished treating and the scene is cleared.
signal incident_cleared(incident_pos: Vector3)

## Metres per second the ambulance drives in (also the EmergencyServices ETA speed).
@export var response_speed: float = 18.0
## How far from the body the ambulance spawns before driving in.
@export var spawn_offset: float = 60.0
## Hard cap on live responders (frame-budget guard).
@export var max_active: int = 4

var _connected: bool = false
var _active: Array[Dictionary] = []


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _connected:
		_try_connect()
	_advance(delta)


func _try_connect() -> void:
	var weapon := get_tree().get_first_node_in_group("weapon_controller")
	if weapon == null or not weapon.has_signal("crime_committed"):
		return
	if not weapon.crime_committed.is_connected(_on_crime):
		weapon.crime_committed.connect(_on_crime)
	_connected = true


## A crime at `crime_pos`: only a kill warrants a medic. Reads the live wanted stars
## and lets EmergencyServices gate the roll-out (a hot scene the player caused is
## refused — the crew won't drive into an active gunfight).
func _on_crime(killed: bool, crime_pos: Vector3) -> void:
	if not killed:
		return
	dispatch_to(crime_pos, _current_stars())


## Gated dispatch usable without the signal (probes drive it directly). Returns
## whether an ambulance actually rolled out.
func dispatch_to(incident_pos: Vector3, wanted_stars: int) -> bool:
	if _active.size() >= max_active:
		return false
	if not EmergencyServices.should_dispatch(EmergencyServices.Incident.INJURY, true, wanted_stars):
		return false
	_spawn_responder(incident_pos)
	responder_dispatched.emit(incident_pos)
	return true


func active_count() -> int:
	return _active.size()


## Spawn the placeholder ambulance a `spawn_offset` away from the body and start its
## EmergencyServices run (siren-run clock = the ETA over that gap), tracked in _active.
func _spawn_responder(incident_pos: Vector3) -> void:
	var spawn_pos := incident_pos + Vector3(spawn_offset, 0.0, 0.0)
	var unit := _build_ambulance()
	var host: Node = get_tree().get_first_node_in_group("world")
	if host == null:
		host = self
	host.add_child(unit)
	unit.global_position = spawn_pos
	var medic := EmergencyServices.new(
		EmergencyServices.eta(spawn_pos, incident_pos, response_speed)
	)
	medic.begin()
	_active.append({"unit": unit, "medic": medic, "target": incident_pos})


## A code-built placeholder ambulance: a boxy Node3D, no .tscn needed.
func _build_ambulance() -> Node3D:
	var unit := Node3D.new()
	unit.name = "Ambulance"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.6, 4.0)
	mesh.mesh = box
	unit.add_child(mesh)
	return unit


## Per-frame: tick every responder's timer, drive it toward the body while en route,
## and clear it once treatment is done. Iterates a copy so we can erase in place.
func _advance(delta: float) -> void:
	for entry in _active.duplicate():
		var medic: EmergencyServices = entry["medic"]
		var unit: Node3D = entry["unit"]
		var target: Vector3 = entry["target"]
		medic.tick(delta)
		if not medic.has_arrived():
			unit.global_position = unit.global_position.move_toward(target, response_speed * delta)
			continue
		unit.global_position = target
		medic.treating()
		if medic.progress() >= 1.0:
			unit.queue_free()
			_active.erase(entry)
			incident_cleared.emit(target)


func _current_stars() -> int:
	var tracker := get_tree().get_first_node_in_group("wanted")
	if tracker != null and tracker.has_method("stars"):
		return tracker.stars()
	return 0
