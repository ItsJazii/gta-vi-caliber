class_name TrafficDemo
extends Node3D
## End-to-end demo of the native TrafficModel: a line of cars on a single-lane
## ring road, each following the car ahead via the Intelligent Driver Model
## (cruise to desired speed, keep a safe time-headway gap, brake when it closes).
## No overtaking on one lane, so index order around the ring is preserved and the
## leader of car i is car (i+1). Rendered as one MultiMesh. The per-frame sim is
## step(delta) so a headless probe can drive it. Falls back to static if the
## native module is absent.

@export var car_count: int = 24
@export var track_radius: float = 40.0
@export var car_length: float = 4.0
@export var desired_speed: float = 16.0
@export var seed: int = 7

# Arc-length position along the ring (metres) and speed (m/s), parallel arrays
# kept in ring order (cars never overtake on a single lane).
var arc: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()

var _model: Object = null
var _mm: MultiMesh = null
var _rng := RandomNumberGenerator.new()
var _min_gap_seen: float = INF


func _ready() -> void:
	_rng.seed = seed
	_spawn_cars()
	_setup_native()
	_setup_multimesh()
	_sync_multimesh()


func native_active() -> bool:
	return _model != null


## Smallest bumper-to-bumper gap observed across the whole run (for probes). If
## car-following works this stays positive — cars never overlap.
func min_gap_seen() -> float:
	return _min_gap_seen


func circumference() -> float:
	return TAU * track_radius


func _spawn_cars() -> void:
	arc.resize(car_count)
	speed.resize(car_count)
	var spacing := circumference() / float(car_count)
	for i in car_count:
		arc[i] = spacing * float(i)
		speed[i] = desired_speed * _rng.randf_range(0.4, 1.0)


func _setup_native() -> void:
	if not ClassDB.class_exists("TrafficModel"):
		push_warning("TrafficDemo: native TrafficModel absent — cars will sit still")
		return
	_model = ClassDB.instantiate("TrafficModel")
	_model.set("desired_speed", desired_speed)
	_model.set("max_accel", 1.6)
	_model.set("comfort_decel", 2.2)
	_model.set("min_gap", 2.0)
	_model.set("time_headway", 1.4)


func _setup_multimesh() -> void:
	var mesh := VehicleVisualLibrary.traffic_mesh(VehicleVisualLibrary.Variant.SPORT_COUPE)
	if mesh == null:
		return
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = car_count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Cars"
	mmi.multimesh = _mm
	add_child(mmi)


func _physics_process(delta: float) -> void:
	if native_active():
		step(delta)
		_sync_multimesh()


## One tick: each car follows the car ahead (wrapping around the ring).
func step(delta: float) -> void:
	if not native_active():
		return

	var circ := circumference()
	# Each car's leader = the next car ahead by actual arc position, recomputed
	# every tick so the follow relationship stays correct even if speeds reorder
	# cars (no fragile fixed-index assumption — Codex review).
	var leader_of := _leaders_by_arc_order()

	var new_arc := PackedFloat32Array()
	var new_speed := PackedFloat32Array()
	new_arc.resize(car_count)
	new_speed.resize(car_count)

	for i in car_count:
		var leader: int = leader_of[i]
		# True bumper-to-bumper gap (can be negative on overlap); clamp only the
		# value fed to the model, so the safety metric below stays honest.
		var true_gap := fposmod(arc[leader] - arc[i], circ) - car_length
		var gap: float = maxf(true_gap, 0.01)

		var accel: float = _model.call("acceleration", speed[i], gap, speed[leader])
		var v: float = maxf(speed[i] + accel * delta, 0.0)  # no reversing
		new_speed[i] = v
		new_arc[i] = fposmod(arc[i] + v * delta, circ)

	arc = new_arc
	speed = new_speed

	# Record the smallest TRUE (unclamped) bumper gap after integration — this
	# goes negative if any car overlaps another, so the probe's no-collision
	# assertion is actually meaningful (Codex review).
	var order := _arc_order()
	for p in car_count:
		var i: int = order[p]
		var leader: int = order[(p + 1) % car_count]
		var g := fposmod(arc[leader] - arc[i], circ) - car_length
		_min_gap_seen = minf(_min_gap_seen, g)


## Indices 0..n-1 sorted ascending by arc position.
func _arc_order() -> PackedInt32Array:
	var idx: Array = []
	idx.resize(car_count)
	for i in car_count:
		idx[i] = i
	idx.sort_custom(_compare_arc)
	return PackedInt32Array(idx)


func _compare_arc(a: int, b: int) -> bool:
	return arc[a] < arc[b]


## Map each car index -> the index of the next car ahead of it on the ring.
func _leaders_by_arc_order() -> PackedInt32Array:
	var order := _arc_order()
	var leader_of := PackedInt32Array()
	leader_of.resize(car_count)
	for p in car_count:
		leader_of[order[p]] = order[(p + 1) % car_count]
	return leader_of


func _sync_multimesh() -> void:
	if _mm == null:
		return
	for i in car_count:
		var theta := arc[i] / track_radius
		var pos := Vector3(
			cos(theta) * track_radius,
			VehicleVisualLibrary.MODEL_FLOOR_OFFSET_Y,
			sin(theta) * track_radius
		)
		# Orient along the tangent (direction of travel).
		var tangent := Vector3(-sin(theta), 0.0, cos(theta))
		var basis := Basis.looking_at(tangent, Vector3.UP)
		_mm.set_instance_transform(i, Transform3D(basis, pos))
