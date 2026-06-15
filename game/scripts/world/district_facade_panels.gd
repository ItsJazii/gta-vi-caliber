class_name DistrictFacadePanels
extends RefCounted
## Batched physical facade/window panels for streamed districts.

const DARK_CAP := 2600
const LIT_CAP := 900
const GeoProjection = preload("res://scripts/world/geo_projection.gd")
const CityBuilder = preload("res://scripts/world/city_builder.gd")


static func build(parent: Node3D, buildings: Array, proj: GeoProjection) -> void:
	var dark_tf: Array[Transform3D] = []
	var lit_tf: Array[Transform3D] = []
	for b in buildings:
		if dark_tf.size() >= DARK_CAP and lit_tf.size() >= LIT_CAP:
			break
		var height := float(b.get("height_m", 0.0))
		if height < 8.0:
			continue
		var ring := _project_ring(b["footprint"], proj)
		collect_transforms(ring, height, int(b.get("id", 0)), dark_tf, lit_tf)
	if dark_tf.is_empty() and lit_tf.is_empty():
		return
	var root := Node3D.new()
	root.name = "FacadePanels"
	parent.add_child(root)
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3.ONE
	_add_layer("DarkGlassPanels", panel_mesh, _glass_material(), dark_tf, root)
	_add_layer("LitWindowPanels", panel_mesh, _lit_material(), lit_tf, root)


static func collect_transforms(
	ring: PackedVector2Array,
	height: float,
	building_id: int,
	dark_out: Array[Transform3D],
	lit_out: Array[Transform3D]
) -> void:
	var pts := CityBuilder.clean_ring(ring)
	if pts.size() < 3:
		return
	if CityBuilder.signed_area(pts) < 0.0:
		pts.reverse()
	var max_storey := mini(int(floor(height / 3.2)), 24)
	if max_storey < 2:
		return
	for i in range(pts.size()):
		if dark_out.size() >= DARK_CAP and lit_out.size() >= LIT_CAP:
			return
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var edge := b - a
		var edge_len := edge.length()
		if edge_len < 5.5:
			continue
		_collect_edge(a, edge, edge_len, i, building_id, max_storey, dark_out, lit_out)


static func _collect_edge(
	a: Vector2,
	edge: Vector2,
	edge_len: float,
	edge_index: int,
	building_id: int,
	max_storey: int,
	dark_out: Array[Transform3D],
	lit_out: Array[Transform3D]
) -> void:
	var dir := edge / edge_len
	var normal := Vector2(dir.y, -dir.x)
	var basis := (
		Basis(Vector3(dir.x, 0.0, dir.y), Vector3.UP, Vector3(normal.x, 0.0, normal.y))
		. scaled(Vector3(1.75, 1.35, 0.12))
	)
	var bay_count := mini(int(floor(edge_len / 3.2)), 12)
	for bay in range(bay_count):
		if dark_out.size() >= DARK_CAP and lit_out.size() >= LIT_CAP:
			return
		var u := (float(bay) + 0.5) * edge_len / float(bay_count)
		for storey in range(1, max_storey):
			if dark_out.size() >= DARK_CAP and lit_out.size() >= LIT_CAP:
				return
			if storey % 3 == 0 and building_id % 5 == 0:
				continue
			var pos2 := a + dir * u + normal * 0.22
			var pos := Vector3(pos2.x, 1.4 + float(storey) * 3.2, pos2.y)
			var h := (building_id * 131 + edge_index * 37 + bay * 17 + storey * 11) % 100
			if h >= 72 and lit_out.size() < LIT_CAP:
				lit_out.append(Transform3D(basis, pos))
			elif dark_out.size() < DARK_CAP:
				dark_out.append(Transform3D(basis, pos))


static func _project_ring(raw: Array, proj: GeoProjection) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for pair in raw:
		ring.append(proj.to_local_2d(pair[0], pair[1]))
	return ring


static func _add_layer(
	layer_name: String, mesh: Mesh, mat: Material, transforms: Array[Transform3D], parent: Node3D
) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	var bounds := AABB(transforms[0].origin, Vector3.ZERO)
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		bounds = bounds.expand(transforms[i].origin)
	mm.custom_aabb = bounds.grow(8.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = layer_name
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)


static func _glass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.015, 0.025, 0.04, 1.0)
	mat.metallic = 0.15
	mat.roughness = 0.12
	return mat


static func _lit_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.56)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.72, 0.36)
	mat.emission_energy_multiplier = 1.2
	mat.roughness = 0.36
	return mat
