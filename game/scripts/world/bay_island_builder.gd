extends Node3D
## Builds the Biscayne Bay residential islands from the authored BayIslands
## layout: each is a low seawalled land pad (walkable/drivable trimesh-free
## cylinder collision) dressed with a cluster of villa blocks, so the causeways
## thread between real Miami landmarks instead of empty water.
##
## One land cylinder + one StaticBody + one villa MultiMesh per island, all built
## once on _ready from static data. Cheap and always present (the islands sit in
## the gap between streamed districts).

var _land_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _villa_mat: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	for isle in BayIslands.islands():
		_build_island(isle)


func _make_materials() -> void:
	_land_mat = StandardMaterial3D.new()
	_land_mat.albedo_color = Color(0.42, 0.52, 0.30)  # manicured lawn / palm green
	_land_mat.roughness = 0.95

	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.78, 0.77, 0.72)  # concrete seawall
	_wall_mat.roughness = 0.9

	_villa_mat = StandardMaterial3D.new()
	_villa_mat.albedo_color = Color(0.92, 0.90, 0.84)  # cream stucco mansions
	_villa_mat.roughness = 0.6


func _build_island(isle: Dictionary) -> void:
	var center: Vector2 = isle["center"]
	var radius: float = isle["radius"]
	var kind: String = isle["kind"]

	var holder := Node3D.new()
	holder.name = "Island_%s" % isle["name"]
	holder.position = Vector3(center.x, 0.0, center.y)
	add_child(holder)

	var height := BayIslands.LAND_Y - BayIslands.FOOT_Y
	var cy := (BayIslands.LAND_Y + BayIslands.FOOT_Y) * 0.5

	# Seawalled land pad: a slightly flared cylinder reads as a concrete rim
	# rising to a flat grassy top.
	var land := CylinderMesh.new()
	land.top_radius = radius
	land.bottom_radius = radius * 1.04
	land.height = height
	land.radial_segments = 28
	land.material = _land_mat
	var mi := MeshInstance3D.new()
	mi.name = "Land"
	mi.mesh = land
	mi.position.y = cy
	holder.add_child(mi)

	# Walkable/drivable collision (solid cylinder; top face is the lawn).
	var body := StaticBody3D.new()
	body.name = "LandBody"
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position.y = cy
	body.add_child(col)
	holder.add_child(body)

	_build_villas(holder, radius, kind)


## A deterministic cluster of villa blocks ringing the island interior.
func _build_villas(holder: Node3D, radius: float, kind: String) -> void:
	var count := 5
	match kind:
		"luxury":
			count = 7
		"civic":
			count = 4
		"residential":
			count = 5

	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	box.material = _villa_mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = count

	var seed := int(radius) + count * 31
	for i in count:
		var a := TAU * float(i) / float(count) + float(seed) * 0.13
		var ring_r := radius * 0.55
		var px := cos(a) * ring_r
		var pz := sin(a) * ring_r
		# Deterministic footprint + height so mansions vary without randomness.
		var w := 12.0 + float((seed + i * 7) % 9)
		var d := 14.0 + float((seed + i * 5) % 11)
		var h := 7.0 + float((seed + i * 3) % 8)
		var basis := Basis.IDENTITY.scaled(Vector3(w, h, d)).rotated(Vector3.UP, a)
		var pos := Vector3(px, BayIslands.LAND_Y + h * 0.5, pz)
		mm.set_instance_transform(i, Transform3D(basis, pos))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Villas"
	mmi.multimesh = mm
	holder.add_child(mmi)
