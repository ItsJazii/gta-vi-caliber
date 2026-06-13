class_name CausewayTraffic
extends Node3D
## Ambient cars streaming across the bay causeways — ground-level life on the
## bridges the player actually drives. Each car rides its causeway's arched deck
## (via CausewayNetwork.sample + deck_height), keeps to a lane, faces its travel
## direction, and carries emissive head/tail lights for the night. Pure
## time-driven motion; built in populate() so it's headless-testable. Added by
## FloridaBackdrop.

@export var cars_per_causeway: int = 10
@export var speed_min: float = 14.0
@export var speed_max: float = 24.0
@export var deck_clearance: float = 0.6
@export var rng_seed: int = 1962

var _cars: Array = []
var _time: float = 0.0
var _body_mats: Array[StandardMaterial3D] = []
var _dark_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _body_mesh: BoxMesh
var _cabin_mesh: BoxMesh
var _wheel_mesh: BoxMesh
var _head_mesh: BoxMesh
var _tail_mesh: BoxMesh


func _ready() -> void:
	populate()


func populate() -> int:
	if not _cars.is_empty():
		return _cars.size()
	_build_shared()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for c in CausewayNetwork.causeways():
		var points: PackedVector2Array = c["points"]
		if points.size() < 2:
			continue
		var length := CausewayNetwork.length_of(points)
		var rise: float = c.get("rise", 12.0)
		var half_lane: float = float(c.get("width", 22.0)) * 0.22
		for i in cars_per_causeway:
			var dir := 1.0 if (i % 2 == 0) else -1.0
			var node := _make_car(rng)
			add_child(node)
			_cars.append(
				{
					"node": node,
					"points": points,
					"length": length,
					"rise": rise,
					"lane": -half_lane if dir > 0.0 else half_lane,
					"dir": dir,
					"dist": rng.randf() * length,
					"speed": rng.randf_range(speed_min, speed_max)
				}
			)
	_apply(0.0)
	return _cars.size()


func _process(delta: float) -> void:
	_time += delta
	for car in _cars:
		var d: float = car["dist"] + car["speed"] * delta * car["dir"]
		car["dist"] = fposmod(d, car["length"])
	_apply(_time)


func _apply(_t: float) -> void:
	for car in _cars:
		var points: PackedVector2Array = car["points"]
		var length: float = car["length"]
		var dist: float = car["dist"]
		var here := CausewayNetwork.sample(points, dist)
		var ahead := CausewayNetwork.sample(points, fposmod(dist + 1.5, length))
		var tangent := ahead - here
		if tangent.length() < 0.0001:
			tangent = Vector2(1, 0)
		tangent = tangent.normalized() * float(car["dir"])
		var perp := Vector2(-tangent.y, tangent.x)
		var pos2: Vector2 = here + perp * float(car["lane"])
		var y := CausewayNetwork.deck_height(dist / length, car["rise"]) + deck_clearance
		var node: Node3D = car["node"]
		node.position = Vector3(pos2.x, y, pos2.y)
		node.rotation.y = atan2(tangent.x, tangent.y)


func _build_shared() -> void:
	_body_mesh = BoxMesh.new()
	_body_mesh.size = Vector3(1.9, 0.9, 4.4)
	_cabin_mesh = BoxMesh.new()
	_cabin_mesh.size = Vector3(1.7, 0.8, 2.3)
	_wheel_mesh = BoxMesh.new()
	_wheel_mesh.size = Vector3(0.35, 0.7, 0.7)
	_head_mesh = BoxMesh.new()
	_head_mesh.size = Vector3(0.4, 0.25, 0.12)
	_tail_mesh = BoxMesh.new()
	_tail_mesh.size = Vector3(0.5, 0.22, 0.12)

	for col in [
		Color(0.85, 0.85, 0.88),
		Color(0.1, 0.12, 0.16),
		Color(0.7, 0.13, 0.14),
		Color(0.15, 0.32, 0.6),
		Color(0.85, 0.78, 0.3),
		Color(0.2, 0.5, 0.4),
	]:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = 0.3
		m.roughness = 0.4
		_body_mats.append(m)
	_dark_mat = StandardMaterial3D.new()
	_dark_mat.albedo_color = Color(0.05, 0.05, 0.06)
	_dark_mat.roughness = 0.7
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.1, 0.13, 0.16)
	_glass_mat.metallic = 0.4
	_glass_mat.roughness = 0.15
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(1.0, 0.97, 0.85)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(1.0, 0.95, 0.8)
	_head_mat.emission_energy_multiplier = 2.2
	_tail_mat = StandardMaterial3D.new()
	_tail_mat.albedo_color = Color(0.7, 0.05, 0.05)
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color(1.0, 0.1, 0.05)
	_tail_mat.emission_energy_multiplier = 1.8


## Car points +z forward (so head/tail lights sit at the right ends).
func _make_car(rng: RandomNumberGenerator) -> Node3D:
	var car := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.material_override = _body_mats[rng.randi() % _body_mats.size()]
	body.position.y = 0.75
	car.add_child(body)
	var cabin := MeshInstance3D.new()
	cabin.mesh = _cabin_mesh
	cabin.material_override = _glass_mat
	cabin.position = Vector3(0.0, 1.4, -0.2)
	car.add_child(cabin)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = _wheel_mesh
			wheel.material_override = _dark_mat
			wheel.position = Vector3(sx * 0.95, 0.35, sz * 1.5)
			car.add_child(wheel)
	for sx in [-1.0, 1.0]:
		var head := MeshInstance3D.new()
		head.mesh = _head_mesh
		head.material_override = _head_mat
		head.position = Vector3(sx * 0.6, 0.75, 2.25)
		car.add_child(head)
		var tail := MeshInstance3D.new()
		tail.mesh = _tail_mesh
		tail.material_override = _tail_mat
		tail.position = Vector3(sx * 0.6, 0.78, -2.25)
		car.add_child(tail)
	return car
