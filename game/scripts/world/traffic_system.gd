extends Node3D
## Spawns kinematic car proxies that drive the district's real road network. Each
## car advances along a RoadNetwork segment and, at each junction, picks a
## continuation (avoiding an immediate U-turn when it can). No physics — traffic
## follows authored road paths, like most open-world ambient traffic. Heavy graph
## math lives in RoadNetwork (tested); this node only animates proxies.

@export_file("*.json") var district_path: String = "res://assets/world/downtown_la.json"
@export var car_count: int = 40
@export var speed_min: float = 8.0
@export var speed_max: float = 16.0

var _net: RoadNetwork
var _cars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var data := _load(district_path)
	if data.is_empty():
		return
	var origin: Dictionary = data["origin"]
	var proj := GeoProjection.new(origin["lat"], origin["lon"])
	_net = RoadNetwork.from_district(data.get("roads", []), proj)
	if _net.segment_count() == 0:
		return

	_rng.randomize()
	var holder := Node3D.new()
	holder.name = "Cars"
	add_child(holder)
	for _i in car_count:
		_spawn_car(holder)


func _physics_process(delta: float) -> void:
	for car in _cars:
		_advance(car, delta)


func _spawn_car(holder: Node3D) -> void:
	var seg := _rng.randi() % _net.segment_count()
	var mesh := _make_car_mesh()
	holder.add_child(mesh)
	(
		_cars
		. append(
			{
				"seg": seg,
				"offset": _rng.randf() * _net.seg_len[seg],
				"speed": _rng.randf_range(speed_min, speed_max),
				"mesh": mesh,
			}
		)
	)


func _advance(car: Dictionary, delta: float) -> void:
	car["offset"] += car["speed"] * delta
	var guard := 0
	while car["offset"] > _net.seg_len[car["seg"]] and guard < 8:
		car["offset"] -= _net.seg_len[car["seg"]]
		car["seg"] = _next_segment(car["seg"])
		guard += 1
	var s := _net.point_on_segment(car["seg"], car["offset"])
	var mesh: Node3D = car["mesh"]
	mesh.global_position = (s["pos"] as Vector3) + Vector3(0, 0.6, 0)
	var heading: Vector3 = s["heading"]
	if heading.length() > 0.01:
		mesh.look_at(mesh.global_position + heading, Vector3.UP)


## Pick the next segment leaving the current segment's end node, preferring not
## to double straight back the way we came.
func _next_segment(seg: int) -> int:
	var from_node := _net.seg_b[seg]
	var came_from := _net.seg_a[seg]
	var outs := _net.segments_from(from_node)
	if outs.is_empty():
		return seg
	var forward := PackedInt32Array()
	for o in outs:
		if _net.seg_b[o] != came_from:
			forward.append(o)
	var pool := forward if forward.size() > 0 else outs
	return pool[_rng.randi() % pool.size()]


func _make_car_mesh() -> Node3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.4, 4.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(_rng.randf(), 0.45, 0.85)
	mat.roughness = 0.4
	box.material = mat
	mi.mesh = box
	return mi


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
