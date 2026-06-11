class_name CrowdNativeDemo
extends Node3D
## End-to-end demo of the native worldcore crowd stack: flocks `agent_count`
## agents on the XZ plane using SpatialHash (O(local-density) neighbour queries)
## + CrowdSteering (boids), drawn as a single MultiMesh (one draw call). Proves
## the native modules compose into a real, moving crowd.
##
## The per-frame simulation is `step(delta)` so it can be driven headlessly by a
## test probe. Falls back to a static field if the native module is absent, so
## the scene still loads in a GDScript-only build.

@export var agent_count: int = 200
@export var half_extent: float = 60.0  # agents wrap within [-he, he] on X/Z
@export var max_speed: float = 7.0
@export var neighbor_radius: float = 5.0
@export var seed: int = 1234

var positions: PackedVector2Array = PackedVector2Array()
var velocities: PackedVector2Array = PackedVector2Array()

var _hash: Object = null
var _steer: Object = null
var _mm: MultiMesh = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = seed
	_spawn_agents()
	_setup_native()
	_setup_multimesh()
	_sync_multimesh()


## True when the native crowd modules are present and wired.
func native_active() -> bool:
	return _hash != null and _steer != null


func _spawn_agents() -> void:
	positions.resize(agent_count)
	velocities.resize(agent_count)
	for i in agent_count:
		positions[i] = Vector2(
			_rng.randf_range(-half_extent, half_extent), _rng.randf_range(-half_extent, half_extent)
		)
		velocities[i] = (
			Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * max_speed
		)


func _setup_native() -> void:
	if not (ClassDB.class_exists("SpatialHash") and ClassDB.class_exists("CrowdSteering")):
		push_warning("CrowdNativeDemo: native worldcore modules absent — agents will sit still")
		return
	_hash = ClassDB.instantiate("SpatialHash")
	_hash.set("cell_size", neighbor_radius)
	_steer = ClassDB.instantiate("CrowdSteering")
	_steer.set("neighbor_radius", neighbor_radius)
	_steer.set("max_force", 10.0)
	_steer.set("separation_weight", 1.6)
	_steer.set("alignment_weight", 1.0)
	_steer.set("cohesion_weight", 0.9)


func _setup_multimesh() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 1.8, 0.6)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = agent_count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Agents"
	mmi.multimesh = _mm
	add_child(mmi)


func _physics_process(delta: float) -> void:
	if native_active():
		step(delta)
		_sync_multimesh()


## One simulation tick. Rebuilds the spatial hash, steers each agent from its
## neighbours, integrates, clamps speed and wraps toroidally inside the field.
## Pure over (positions, velocities) given the native helpers — the probe calls
## this directly.
func step(delta: float) -> void:
	if not native_active():
		return

	_hash.call("clear")
	for i in agent_count:
		_hash.call("insert", i, positions[i])

	for i in agent_count:
		var ids: PackedInt32Array = _hash.call("query_radius", positions[i], neighbor_radius)
		var npos := PackedVector2Array()
		var nvel := PackedVector2Array()
		for id in ids:
			if id == i:
				continue
			npos.append(positions[id])
			nvel.append(velocities[id])

		var force: Vector2 = _steer.call("steer", positions[i], velocities[i], npos, nvel)
		var v: Vector2 = velocities[i] + force * delta
		if v.length() > max_speed:
			v = v.normalized() * max_speed
		velocities[i] = v
		positions[i] = _wrap(positions[i] + v * delta)


func _wrap(p: Vector2) -> Vector2:
	var span := half_extent * 2.0
	if p.x > half_extent:
		p.x -= span
	elif p.x < -half_extent:
		p.x += span
	if p.y > half_extent:
		p.y -= span
	elif p.y < -half_extent:
		p.y += span
	return p


func _sync_multimesh() -> void:
	if _mm == null:
		return
	for i in agent_count:
		var p := positions[i]
		var facing := velocities[i]
		var basis := Basis.IDENTITY
		if facing.length() > 0.01:
			basis = Basis.looking_at(Vector3(facing.x, 0.0, facing.y), Vector3.UP)
		_mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, 0.9, p.y)))
