class_name CrowdPanicDirector
extends Node
## Self-wiring world-life director: when the player commits gun violence
## (WeaponController.crime_committed), the nearby crowd SCATTERS — and then the panic
## SPREADS. It finds the weapon by group `weapon_controller` (like WantedTracker) and
## the crowd by group `pedestrians`, uses CrowdPanic.initial_fear for the blast-ring
## falloff, and runs a throttled contagion pass (CrowdPanic.propagated_fear) so a calm
## ped next to a bolting one catches the fear and runs too — the crowd fans out from
## the shooting instead of a hard circle. Drop the node in a scene; no per-scene
## plumbing. Wiring + contagion exercised by tests/crowd_panic_probe.gd and
## tests/crowd_contagion_probe.gd.
##
## The weapon may arm/appear after this node, so the connection is polled until it
## lands; processing then continues for the contagion tick.

## Emitted when a shooting scatters the crowd, with how many peds were spooked.
signal crowd_scattered(scared: int)

## Peds within this distance of a shooting are spooked (linear fear falloff to 0).
@export var scare_radius: float = 24.0
## Max seconds a spooked ped flees, scaled down by distance via the fear model.
@export var flee_seconds: float = 6.0

@export_group("Panic contagion")
## How often (seconds) the panic-spread pass runs.
@export var contagion_interval: float = 0.3
## A calm ped catches panic from bolting neighbours within this distance.
@export var contagion_radius: float = 11.0
## How strongly nearby panic spreads (into CrowdPanic.propagated_fear).
@export var contagion_strength: float = 0.7
## Caught fear (0..1) above which a calm ped starts bolting too.
@export var contagion_catch: float = 0.25
## Fear seconds at/above which a ped already counts as panicking.
@export var panic_threshold: float = 0.5

var _connected: bool = false
var _contagion_timer: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _connected:
		_try_connect()
		if not _connected:
			return
	_contagion_timer += delta
	if _contagion_timer >= contagion_interval:
		_contagion_timer = 0.0
		_spread_panic()


func _try_connect() -> void:
	var weapon := get_tree().get_first_node_in_group("weapon_controller")
	if weapon == null or not weapon.has_signal("crime_committed"):
		return
	if not weapon.crime_committed.is_connected(_on_crime):
		weapon.crime_committed.connect(_on_crime)
	_connected = true


## A crime (gunshot) at `crime_pos` spooks every pedestrian within scare_radius,
## fleeing longer the closer they were. Returns nothing; emits crowd_scattered.
func _on_crime(_killed: bool, crime_pos: Vector3) -> void:
	var scared: int = 0
	for ped in get_tree().get_nodes_in_group("pedestrians"):
		var node := ped as Node3D
		if node == null or not node.has_method("scare"):
			continue
		var fear := CrowdPanic.initial_fear(node.global_position, crime_pos, scare_radius)
		if fear > 0.0:
			node.scare(crime_pos, flee_seconds * fear)
			scared += 1
	if scared > 0:
		crowd_scattered.emit(scared)


## One contagion pass: each calm ped catches panic from bolting neighbours within
## contagion_radius (CrowdPanic.propagated_fear) and bolts away from the nearest one,
## so panic cascades through the crowd rather than stopping at the blast ring.
func _spread_panic() -> void:
	var peds := get_tree().get_nodes_in_group("pedestrians")
	if peds.size() < 2:
		return
	# Binary panicking flag per ped (sidesteps the fear-seconds vs 0..1 unit clash).
	var states: Array = []
	for p in peds:
		var n := p as Node3D
		var hot := n != null and n.has_method("fear") and float(n.fear()) > panic_threshold
		states.append(
			{"pos": n.global_position if n != null else Vector3.ZERO, "fear": 1.0 if hot else 0.0}
		)
	for i in range(peds.size()):
		var node := peds[i] as Node3D
		if node == null or not node.has_method("scare") or not node.has_method("fear"):
			continue
		if float(node.fear()) > panic_threshold:
			continue
		var here: Vector3 = node.global_position
		var src := Vector3.ZERO
		var best := INF
		for j in range(states.size()):
			if j == i or float(states[j]["fear"]) <= 0.5:
				continue
			var d: float = (states[j]["pos"] as Vector3).distance_to(here)
			if d < best:
				best = d
				src = states[j]["pos"]
		if best == INF:
			continue
		var caught := CrowdPanic.propagated_fear(here, states, contagion_radius, contagion_strength)
		if caught > contagion_catch:
			node.scare(src, flee_seconds * caught)
