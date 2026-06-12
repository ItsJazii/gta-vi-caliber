class_name FlowFieldDemo
extends Node3D
## End-to-end demo of the native FlowField: a grid with wall blocks and a single
## goal; the field is built once, then every agent samples direction_at() to
## route around the walls toward the goal — one shared solution for the whole
## crowd, no per-agent pathfinding. step(delta) drives it for a headless probe.
## Falls back to a static field if the native module is absent.

@export var grid_w: int = 24
@export var grid_h: int = 24
@export var cell_size: float = 2.5
@export var agent_count: int = 150
@export var agent_speed: float = 9.0
@export var seed: int = 5

var positions: PackedVector2Array = PackedVector2Array()
var costs: PackedFloat32Array = PackedFloat32Array()

var _flow: Object = null
var _goal_world := Vector2.ZERO
var _origin := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _mm: MultiMesh = null


func _ready() -> void:
	_rng.seed = seed
	_origin = Vector2(-grid_w * cell_size * 0.5, -grid_h * cell_size * 0.5)
	_build_grid()
	_setup_native()
	_spawn_agents()
	_setup_multimesh()
	_render_walls()
	_sync_multimesh()


func native_active() -> bool:
	return _flow != null


func goal() -> Vector2:
	return _goal_world


func is_wall_at(p: Vector2) -> bool:
	var cx := int(floor((p.x - _origin.x) / cell_size))
	var cz := int(floor((p.y - _origin.y) / cell_size))
	if cx < 0 or cx >= grid_w or cz < 0 or cz >= grid_h:
		return true
	return costs[cz * grid_w + cx] < 0.0


func _build_grid() -> void:
	costs.resize(grid_w * grid_h)
	costs.fill(1.0)
	_wall_rect(6, 3, 2, 13)  # two staggered barriers force a routed path
	_wall_rect(15, 8, 2, 13)
	_goal_world = _cell_center(grid_w - 3, grid_h - 3)


func _wall_rect(x: int, y: int, w: int, h: int) -> void:
	for cz in range(y, mini(y + h, grid_h)):
		for cx in range(x, mini(x + w, grid_w)):
			costs[cz * grid_w + cx] = -1.0


func _cell_center(cx: int, cz: int) -> Vector2:
	return _origin + Vector2((cx + 0.5) * cell_size, (cz + 0.5) * cell_size)


func _setup_native() -> void:
	if not ClassDB.class_exists("FlowField"):
		push_warning("FlowFieldDemo: native FlowField absent — agents will sit still")
		return
	_flow = ClassDB.instantiate("FlowField")
	_flow.set("cell_size", cell_size)
	_flow.set("origin", _origin)
	_flow.call("build", grid_w, grid_h, costs, _goal_world)
	if not _flow.call("is_built"):
		_flow = null


func _spawn_agents() -> void:
	positions.resize(agent_count)
	for i in agent_count:
		var p := Vector2.ZERO
		for _try in 60:  # rejection-sample a passable start cell
			p = (
				_origin
				+ Vector2(
					_rng.randf_range(0.0, grid_w * cell_size),
					_rng.randf_range(0.0, grid_h * cell_size)
				)
			)
			if not is_wall_at(p):
				break
		positions[i] = p


func _physics_process(delta: float) -> void:
	if _flow != null:
		step(delta)
		_sync_multimesh()


## One tick: each agent steps along the flow direction toward the goal. The move
## is capped at one cell so a large delta spike can't tunnel an agent across a
## thin wall (Codex review).
func step(delta: float) -> void:
	if _flow == null:
		return
	for i in agent_count:
		var dir: Vector2 = _flow.call("direction_at", positions[i])
		if dir.length() < 0.01:
			continue  # at the goal or on an unreachable cell
		var move := dir * agent_speed * delta
		if move.length() > cell_size:
			move = move.normalized() * cell_size
		positions[i] += move


func _setup_multimesh() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 1.6, 0.8)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = agent_count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Agents"
	mmi.multimesh = _mm
	add_child(mmi)


func _render_walls() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cell_size, 4.0, cell_size)
	var wall_mm := MultiMesh.new()
	wall_mm.transform_format = MultiMesh.TRANSFORM_3D
	wall_mm.mesh = mesh
	var cells: Array = []
	for cz in grid_h:
		for cx in grid_w:
			if costs[cz * grid_w + cx] < 0.0:
				cells.append(_cell_center(cx, cz))
	wall_mm.instance_count = cells.size()
	for i in cells.size():
		wall_mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(cells[i].x, 2.0, cells[i].y))
		)
	var wmi := MultiMeshInstance3D.new()
	wmi.name = "Walls"
	wmi.multimesh = wall_mm
	add_child(wmi)


func _sync_multimesh() -> void:
	if _mm == null:
		return
	for i in agent_count:
		var p := positions[i]
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, 0.8, p.y)))
