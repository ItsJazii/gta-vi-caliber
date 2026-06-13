extends Node3D
## Spawns pedestrian proxies that walk the district's real sidewalk/footpath
## network (RoadNetwork built from walkable OSM ways). Same segment-walking model
## as traffic, just slower agents on a different graph — the city feels inhabited.

@export_file("*.json") var district_path: String = "res://assets/world/downtown_miami.json"
@export var pedestrian_count: int = 90
@export var speed_min: float = 1.1
@export var speed_max: float = 1.8

var _net: RoadNetwork
var _peds: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _mmi: MultiMeshInstance3D
var _mm: MultiMesh


func _ready() -> void:
	var data := _load(district_path)
	if data.is_empty():
		return
	var origin: Dictionary = data["origin"]
	var proj := GeoProjection.new(origin["lat"], origin["lon"])
	_net = RoadNetwork.from_district(data.get("roads", []), proj, 2.0, RoadNetwork.WALKABLE)
	if _net.segment_count() == 0:
		return

	_rng.randomize()
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Pedestrians"
	add_child(_mmi)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.instance_count = pedestrian_count
	_mm.mesh = _make_shared_capsule()
	_mmi.multimesh = _mm
	for _i in pedestrian_count:
		_spawn_ped(_i)


func _physics_process(delta: float) -> void:
	for ped in _peds:
		_advance(ped, delta)


func _spawn_ped(idx: int) -> void:
	var seg := _rng.randi() % _net.segment_count()
	var col := Color.from_hsv(_rng.randf(), 0.35, 0.7)
	_mm.set_instance_color(idx, col)
	(
		_peds
		. append(
			{
				"seg": seg,
				"offset": _rng.randf() * _net.seg_len[seg],
				"speed": _rng.randf_range(speed_min, speed_max),
				"idx": idx,
			}
		)
	)


func _advance(ped: Dictionary, delta: float) -> void:
	ped["offset"] += ped["speed"] * delta
	var guard := 0
	while ped["offset"] > _net.seg_len[ped["seg"]] and guard < 8:
		ped["offset"] -= _net.seg_len[ped["seg"]]
		ped["seg"] = _next_segment(ped["seg"])
		guard += 1
	var s := _net.point_on_segment(ped["seg"], ped["offset"])
	var pos: Vector3 = (s["pos"] as Vector3) + Vector3(0, 0.9, 0)
	var heading: Vector3 = s["heading"]
	var xform := Transform3D(Basis.IDENTITY, pos)
	if heading.length() > 0.01:
		var forward := heading.normalized()
		var up := Vector3.UP
		var right := up.cross(forward).normalized()
		if right.length_squared() > 0.001:
			up = forward.cross(right)
			xform.basis = Basis(right, up, forward)
	_mm.set_instance_transform(ped["idx"], xform)


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


func _make_shared_capsule() -> Mesh:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.7
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	capsule.material = mat
	return capsule


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
