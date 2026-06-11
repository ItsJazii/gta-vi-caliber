class_name FloridaBackdrop
extends Node3D
## Original Florida-scale playable backdrop for the current Miami map.
##
## Builds one low-cost state landmass around the streamed city: water, sand
## edge, causeways, city skyline markers, wetlands, and a swim volume. All
## shapes come from FloridaMapModel, not copied reference map data.

const WATER_VOLUME_SCRIPT := preload("res://scripts/world/water_volume.gd")
const OCEAN_SCRIPT := preload("res://scripts/world/ocean.gd")

@export var map_scale: float = 4.6
@export var water_size_m: float = 12000.0
@export var ocean_y: float = -0.18
@export var land_y: float = 0.0
@export var coastline_width_m: float = 54.0
@export var road_width_m: float = 18.0
@export var wetland_count: int = 150

var _land_mat: Material
var _sand_mat: Material
var _road_mat: Material
var _tower_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _dark_glass_mat: StandardMaterial3D
var _neon_mat: StandardMaterial3D
var _dock_mat: StandardMaterial3D
var _concrete_mat: StandardMaterial3D
var _resort_white_mat: StandardMaterial3D
var _resort_aqua_mat: StandardMaterial3D
var _resort_coral_mat: StandardMaterial3D
var _warning_light_mat: StandardMaterial3D
var _steel_mat: StandardMaterial3D
var _cypress_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_build_water()
	_build_land()
	_build_key_islands()
	_build_coastline()
	_build_routes()
	_build_bridges()
	_build_marinas()
	_build_beach_resorts()
	_build_landmarks()
	_build_city_accents()
	_build_wetlands()
	_build_swim_volume()


func _make_materials() -> void:
	_land_mat = _shader_or_fallback("res://shaders/florida_land.gdshader", Color(0.22, 0.35, 0.18))

	_sand_mat = _shader_or_fallback("res://shaders/florida_sand.gdshader", Color(0.86, 0.77, 0.55))

	_road_mat = _shader_or_fallback("res://shaders/road.gdshader", Color(0.035, 0.04, 0.045))

	_tower_mat = StandardMaterial3D.new()
	_tower_mat.albedo_color = Color(0.86, 0.62, 0.58)
	_tower_mat.roughness = 0.6

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.48, 0.8, 0.92, 0.86)
	_glass_mat.metallic = 0.0
	_glass_mat.roughness = 0.18
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_dark_glass_mat = StandardMaterial3D.new()
	_dark_glass_mat.albedo_color = Color(0.06, 0.11, 0.16)
	_dark_glass_mat.metallic = 0.0
	_dark_glass_mat.roughness = 0.12

	_neon_mat = StandardMaterial3D.new()
	_neon_mat.albedo_color = Color(0.58, 0.86, 0.96)
	_neon_mat.emission_enabled = true
	_neon_mat.emission = Color(0.30, 0.82, 1.0)
	_neon_mat.emission_energy_multiplier = 1.15

	_dock_mat = StandardMaterial3D.new()
	_dock_mat.albedo_color = Color(0.34, 0.24, 0.16)
	_dock_mat.roughness = 0.72

	_concrete_mat = StandardMaterial3D.new()
	_concrete_mat.albedo_color = Color(0.62, 0.60, 0.56)
	_concrete_mat.roughness = 0.82

	_resort_white_mat = StandardMaterial3D.new()
	_resort_white_mat.albedo_color = Color(0.92, 0.89, 0.82)
	_resort_white_mat.roughness = 0.62

	_resort_aqua_mat = StandardMaterial3D.new()
	_resort_aqua_mat.albedo_color = Color(0.18, 0.72, 0.78)
	_resort_aqua_mat.roughness = 0.5

	_resort_coral_mat = StandardMaterial3D.new()
	_resort_coral_mat.albedo_color = Color(0.95, 0.34, 0.36)
	_resort_coral_mat.roughness = 0.56

	_warning_light_mat = StandardMaterial3D.new()
	_warning_light_mat.albedo_color = Color(1.0, 0.18, 0.08)
	_warning_light_mat.emission_enabled = true
	_warning_light_mat.emission = Color(1.0, 0.12, 0.04)
	_warning_light_mat.emission_energy_multiplier = 3.2

	_steel_mat = StandardMaterial3D.new()
	_steel_mat.albedo_color = Color(0.36, 0.39, 0.42)
	_steel_mat.metallic = 0.55
	_steel_mat.roughness = 0.36

	_cypress_mat = StandardMaterial3D.new()
	_cypress_mat.albedo_color = Color(0.22, 0.16, 0.11)
	_cypress_mat.roughness = 0.95

	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_color = Color(0.12, 0.27, 0.12)
	_leaf_mat.roughness = 0.92
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


static func _shader_or_fallback(path: String, fallback: Color) -> Material:
	var shader := load(path) as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		return mat
	var std := StandardMaterial3D.new()
	std.albedo_color = fallback
	std.roughness = 0.9
	return std


func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "StateOcean"
	water.set_script(OCEAN_SCRIPT)
	water.set("size_m", water_size_m)
	water.set("resolution", 192)
	water.set("amplitude_scale", 0.75)
	water.set("wave_speed", 0.78)
	water.set("shallow_color", Color(0.02, 0.68, 0.58))
	water.set("deep_color", Color(0.0, 0.08, 0.24))
	water.set("horizon_color", Color(0.10, 0.34, 0.55))
	water.set("absorption_per_m", 0.2)
	water.set("edge_fade_m", 0.9)
	water.set("surface_roughness", 0.045)
	water.set("foam_depth_m", 0.08)
	water.set("foam_strength", 0.18)
	water.set("foam_color", Color(0.92, 0.95, 0.92, 1.0))
	water.position.y = ocean_y
	add_child(water)


func _build_land() -> void:
	var outline := FloridaMapModel.outline(map_scale)
	var triangles := Geometry2D.triangulate_polygon(outline)
	if triangles.is_empty():
		return

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var extents := FloridaMapModel.bounds(map_scale)
	for p in outline:
		vertices.append(Vector3(p.x, land_y, p.y))
		normals.append(Vector3.UP)
		uvs.append(
			Vector2(
				(p.x - extents.position.x) / maxf(extents.size.x, 1.0),
				(p.y - extents.position.y) / maxf(extents.size.y, 1.0)
			)
		)
	for i in triangles:
		indices.append(i)

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _land_mat)

	var body := StaticBody3D.new()
	body.name = "StateLandmass"
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)


func _build_key_islands() -> void:
	for island in FloridaMapModel.key_islands(map_scale):
		var centre: Vector2 = island["position"]
		var size: Vector2 = island["size"]
		var rot := float(island["rotation"])
		var outline := _ellipse_outline(centre, size, rot, 18)
		var triangles := Geometry2D.triangulate_polygon(outline)
		if triangles.is_empty():
			continue
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for p in outline:
			vertices.append(Vector3(p.x, land_y + 0.045, p.y))
			normals.append(Vector3.UP)
		for i in triangles:
			indices.append(i)
		_add_flat_mesh(
			"OriginalKeyIsland",
			{"vertices": vertices, "normals": normals, "indices": indices},
			_sand_mat
		)


func _ellipse_outline(centre: Vector2, size: Vector2, rotation: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var basis := Transform2D(rotation, centre)
	for i in range(steps):
		var t := TAU * float(i) / float(steps)
		points.append(basis * Vector2(cos(t) * size.x * 0.5, sin(t) * size.y * 0.5))
	return points


func _build_coastline() -> void:
	var geo := CityBuilder.road_ribbon(
		FloridaMapModel.closed_outline(map_scale), coastline_width_m, land_y + 0.035
	)
	_add_flat_mesh("SandCoastline", geo, _sand_mat)


func _build_routes() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var uvs := PackedVector2Array()
	for path in FloridaMapModel.road_paths(map_scale):
		var geo := CityBuilder.road_ribbon(path, road_width_m, land_y + 0.07)
		var offset := verts.size()
		verts.append_array(geo["vertices"])
		norms.append_array(geo["normals"])
		uvs.append_array(geo["uvs"])
		for i in geo["indices"] as PackedInt32Array:
			idx.append(offset + i)
	_add_flat_mesh("StateCauseways", {"vertices": verts, "normals": norms, "indices": idx, "uvs": uvs}, _road_mat)


func _build_bridges() -> void:
	var root := Node3D.new()
	root.name = "SignatureBridges"
	add_child(root)
	for path in FloridaMapModel.bridge_paths(map_scale):
		_add_bridge_span(root, path[0], path[1])


func _add_bridge_span(parent: Node, a: Vector2, b: Vector2) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 1.0:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(delta.x, delta.y)

	var deck := MeshInstance3D.new()
	deck.name = "BridgeDeck"
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(24.0, 2.4, length)
	deck.mesh = deck_mesh
	deck.material_override = _concrete_mat
	deck.position = Vector3(mid.x, land_y + 8.0, mid.y)
	deck.rotation.y = yaw
	parent.add_child(deck)

	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.42, 1.1, length)
	for side in [-12.4, 12.4]:
		var rail := MeshInstance3D.new()
		rail.name = "BridgeRail"
		rail.mesh = rail_mesh
		rail.material_override = _neon_mat
		rail.position = Vector3(mid.x, land_y + 11.0, mid.y)
		rail.rotation.y = yaw
		rail.translate_object_local(Vector3(side, 0.0, 0.0))
		parent.add_child(rail)

	var pier_mesh := CylinderMesh.new()
	pier_mesh.top_radius = 2.8
	pier_mesh.bottom_radius = 3.2
	pier_mesh.height = 12.0
	for t in [0.22, 0.5, 0.78]:
		var p := a.lerp(b, t)
		var pier := MeshInstance3D.new()
		pier.name = "BridgePier"
		pier.mesh = pier_mesh
		pier.material_override = _concrete_mat
		pier.position = Vector3(p.x, land_y + 3.0, p.y)
		parent.add_child(pier)


func _build_marinas() -> void:
	var root := Node3D.new()
	root.name = "OriginalMarinas"
	add_child(root)
	for marina in FloridaMapModel.marinas(map_scale):
		_add_marina(root, marina)


func _build_beach_resorts() -> void:
	var root := Node3D.new()
	root.name = "OriginalBeachResorts"
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260611
	for island in FloridaMapModel.key_islands(map_scale):
		var centre: Vector2 = island["position"]
		var size: Vector2 = island["size"]
		var rotation := float(island["rotation"])
		for i in range(5):
			var along := (float(i) - 2.0) * size.x * 0.16
			var side := -1.0 if i % 2 == 0 else 1.0
			var local := Vector2(along, side * size.y * rng.randf_range(0.16, 0.28))
			var world := Transform2D(rotation, centre) * local
			_add_cabana(root, world, rotation + rng.randf_range(-0.18, 0.18), rng)
		for i in range(3):
			var local := Vector2((float(i) - 1.0) * size.x * 0.22, -size.y * 0.08)
			var world := Transform2D(rotation, centre) * local
			_add_key_hotel(root, world, rotation + rng.randf_range(-0.08, 0.08), rng, i)
		for i in range(7):
			var local := Vector2(
				rng.randf_range(-size.x * 0.42, size.x * 0.42),
				rng.randf_range(-size.y * 0.28, size.y * 0.28)
			)
			var world := Transform2D(rotation, centre) * local
			_add_beach_umbrella(root, world, rotation + rng.randf_range(-0.3, 0.3), i)


func _add_key_hotel(
	parent: Node, xz: Vector2, yaw: float, rng: RandomNumberGenerator, index: int
) -> void:
	var hotel := Node3D.new()
	hotel.name = "KeyHotel"
	hotel.position = Vector3(xz.x, land_y + 0.4, xz.y)
	hotel.rotation.y = yaw
	parent.add_child(hotel, true)

	var height := rng.randf_range(14.0, 24.0)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(22.0, height, 11.0)
	body.mesh = body_mesh
	body.material_override = _resort_white_mat
	body.position = Vector3(0.0, height * 0.5, 0.0)
	hotel.add_child(body)

	var glass := MeshInstance3D.new()
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(23.0, 2.8, 0.42)
	glass.mesh = glass_mesh
	glass.material_override = _resort_aqua_mat if index % 2 == 0 else _resort_coral_mat
	glass.position = Vector3(0.0, height + 1.4, -5.7)
	hotel.add_child(glass)


func _build_landmarks() -> void:
	var root := Node3D.new()
	root.name = "OriginalLandmarks"
	add_child(root)
	for landmark in FloridaMapModel.landmarks(map_scale):
		var kind := String(landmark["kind"])
		var pos: Vector2 = landmark["position"]
		var yaw := float(landmark["rotation"])
		match kind:
			"lighthouse":
				_add_lighthouse(root, pos, yaw)
			"wheel":
				_add_observation_wheel(root, pos, yaw)
			"launch":
				_add_launch_tower(root, pos, yaw)
			"arch":
				_add_resort_arch(root, pos, yaw)


func _add_lighthouse(parent: Node, xz: Vector2, yaw: float) -> void:
	var lighthouse := Node3D.new()
	lighthouse.name = "TorchKeyLight"
	lighthouse.position = Vector3(xz.x, land_y, xz.y)
	lighthouse.rotation.y = yaw
	parent.add_child(lighthouse, true)

	var tower := MeshInstance3D.new()
	var tower_mesh := CylinderMesh.new()
	tower_mesh.top_radius = 4.0
	tower_mesh.bottom_radius = 7.0
	tower_mesh.height = 64.0
	tower_mesh.radial_segments = 18
	tower.mesh = tower_mesh
	tower.material_override = _resort_white_mat
	tower.position = Vector3(0.0, 32.0, 0.0)
	lighthouse.add_child(tower)

	for y in [14.0, 30.0, 48.0]:
		var band := MeshInstance3D.new()
		var band_mesh := CylinderMesh.new()
		band_mesh.top_radius = 4.4
		band_mesh.bottom_radius = 5.4
		band_mesh.height = 1.2
		band_mesh.radial_segments = 18
		band.mesh = band_mesh
		band.material_override = _resort_coral_mat
		band.position = Vector3(0.0, y, 0.0)
		lighthouse.add_child(band)

	var lantern := MeshInstance3D.new()
	var lantern_mesh := CylinderMesh.new()
	lantern_mesh.top_radius = 4.6
	lantern_mesh.bottom_radius = 4.6
	lantern_mesh.height = 5.0
	lantern_mesh.radial_segments = 18
	lantern.mesh = lantern_mesh
	lantern.material_override = _glass_mat
	lantern.position = Vector3(0.0, 69.0, 0.0)
	lighthouse.add_child(lantern)

	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 1.4
	beacon_mesh.height = 2.8
	beacon.mesh = beacon_mesh
	beacon.material_override = _warning_light_mat
	beacon.position = Vector3(0.0, 72.0, 0.0)
	lighthouse.add_child(beacon)


func _add_observation_wheel(parent: Node, xz: Vector2, yaw: float) -> void:
	var wheel := Node3D.new()
	wheel.name = "SunsetWheel"
	wheel.position = Vector3(xz.x, land_y, xz.y)
	wheel.rotation.y = yaw
	parent.add_child(wheel, true)

	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 40.0
	rim_mesh.outer_radius = 42.0
	rim_mesh.ring_segments = 64
	var rim := MeshInstance3D.new()
	rim.mesh = rim_mesh
	rim.material_override = _steel_mat
	rim.position = Vector3(0.0, 48.0, 0.0)
	rim.rotation.x = PI * 0.5
	wheel.add_child(rim)

	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(0.65, 0.65, 82.0)
	for i in range(12):
		var spoke := MeshInstance3D.new()
		spoke.name = "WheelSpoke"
		spoke.mesh = spoke_mesh
		spoke.material_override = _steel_mat
		spoke.position = Vector3(0.0, 48.0, 0.0)
		spoke.rotation.x = PI * 0.5
		spoke.rotation.z = TAU * float(i) / 12.0
		wheel.add_child(spoke)

	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(5.0, 2.8, 3.0)
	for i in range(10):
		var angle := TAU * float(i) / 10.0
		var cabin := MeshInstance3D.new()
		cabin.name = "WheelCabin"
		cabin.mesh = cabin_mesh
		cabin.material_override = _resort_aqua_mat if i % 2 == 0 else _resort_coral_mat
		cabin.position = Vector3(cos(angle) * 42.0, 48.0 + sin(angle) * 42.0, 0.0)
		wheel.add_child(cabin)

	for x in [-16.0, 16.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(1.5, 58.0, 1.5)
		leg.mesh = leg_mesh
		leg.material_override = _steel_mat
		leg.position = Vector3(x, 29.0, 0.0)
		leg.rotation.z = 0.28 * signf(x)
		wheel.add_child(leg)


func _add_launch_tower(parent: Node, xz: Vector2, yaw: float) -> void:
	var launch := Node3D.new()
	launch.name = "AtlasPointLaunch"
	launch.position = Vector3(xz.x, land_y, xz.y)
	launch.rotation.y = yaw
	parent.add_child(launch, true)

	var tower_mesh := BoxMesh.new()
	tower_mesh.size = Vector3(8.0, 86.0, 8.0)
	var tower := MeshInstance3D.new()
	tower.mesh = tower_mesh
	tower.material_override = _steel_mat
	tower.position = Vector3(0.0, 43.0, 0.0)
	launch.add_child(tower)

	for y in [16.0, 32.0, 48.0, 64.0, 80.0]:
		var deck := MeshInstance3D.new()
		var deck_mesh := BoxMesh.new()
		deck_mesh.size = Vector3(28.0, 1.2, 18.0)
		deck.mesh = deck_mesh
		deck.material_override = _concrete_mat
		deck.position = Vector3(8.0, y, 0.0)
		launch.add_child(deck)

	var rocket := MeshInstance3D.new()
	var rocket_mesh := CylinderMesh.new()
	rocket_mesh.top_radius = 2.0
	rocket_mesh.bottom_radius = 2.6
	rocket_mesh.height = 58.0
	rocket_mesh.radial_segments = 20
	rocket.mesh = rocket_mesh
	rocket.material_override = _resort_white_mat
	rocket.position = Vector3(-18.0, 29.0, 0.0)
	launch.add_child(rocket)

	var nose := MeshInstance3D.new()
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = 2.1
	nose_mesh.height = 8.0
	nose_mesh.radial_segments = 20
	nose.mesh = nose_mesh
	nose.material_override = _resort_coral_mat
	nose.position = Vector3(-18.0, 62.0, 0.0)
	launch.add_child(nose)

	var flame := MeshInstance3D.new()
	var flame_mesh := CylinderMesh.new()
	flame_mesh.top_radius = 1.2
	flame_mesh.bottom_radius = 4.5
	flame_mesh.height = 13.0
	flame_mesh.radial_segments = 16
	flame.mesh = flame_mesh
	flame.material_override = _warning_light_mat
	flame.position = Vector3(-18.0, 0.5, 0.0)
	launch.add_child(flame)


func _add_resort_arch(parent: Node, xz: Vector2, yaw: float) -> void:
	var arch := Node3D.new()
	arch.name = "GulfGateArch"
	arch.position = Vector3(xz.x, land_y, xz.y)
	arch.rotation.y = yaw
	parent.add_child(arch, true)

	for x in [-10.0, 10.0]:
		var column := MeshInstance3D.new()
		var column_mesh := CylinderMesh.new()
		column_mesh.top_radius = 2.2
		column_mesh.bottom_radius = 2.8
		column_mesh.height = 22.0
		column_mesh.radial_segments = 16
		column.mesh = column_mesh
		column.material_override = _resort_white_mat
		column.position = Vector3(x, 11.0, 0.0)
		arch.add_child(column)

	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(26.0, 4.0, 5.0)
	beam.mesh = beam_mesh
	beam.material_override = _resort_aqua_mat
	beam.position = Vector3(0.0, 23.0, 0.0)
	arch.add_child(beam)

	var sign := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(18.0, 2.2, 0.5)
	sign.mesh = sign_mesh
	sign.material_override = _neon_mat
	sign.position = Vector3(0.0, 25.0, -2.7)
	arch.add_child(sign)


func _add_cabana(parent: Node, xz: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var cabana := Node3D.new()
	cabana.name = "BeachCabana"
	cabana.position = Vector3(xz.x, land_y + 0.35, xz.y)
	cabana.rotation.y = yaw
	parent.add_child(cabana, true)

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(10.0, 2.6, 7.0)
	base.mesh = base_mesh
	base.material_override = _resort_white_mat
	base.position = Vector3(0.0, 1.3, 0.0)
	cabana.add_child(base)

	var roof := MeshInstance3D.new()
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(11.5, 2.0, 8.2)
	roof.mesh = roof_mesh
	roof.material_override = _resort_coral_mat if rng.randf() < 0.5 else _resort_aqua_mat
	roof.position = Vector3(0.0, 3.55, 0.0)
	roof.rotation.z = PI * 0.5
	cabana.add_child(roof)


func _add_beach_umbrella(parent: Node, xz: Vector2, yaw: float, index: int) -> void:
	var umbrella := Node3D.new()
	umbrella.name = "BeachUmbrella"
	umbrella.position = Vector3(xz.x, land_y + 0.2, xz.y)
	umbrella.rotation.y = yaw
	parent.add_child(umbrella, true)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 2.5
	pole.mesh = pole_mesh
	pole.material_override = _dock_mat
	pole.position = Vector3(0.0, 1.25, 0.0)
	umbrella.add_child(pole)

	var canopy := MeshInstance3D.new()
	var canopy_mesh := CylinderMesh.new()
	canopy_mesh.top_radius = 0.0
	canopy_mesh.bottom_radius = 1.45
	canopy_mesh.height = 0.65
	canopy_mesh.radial_segments = 12
	canopy.mesh = canopy_mesh
	canopy.material_override = _resort_aqua_mat if index % 2 == 0 else _resort_coral_mat
	canopy.position = Vector3(0.0, 2.65, 0.0)
	umbrella.add_child(canopy)


func _add_marina(parent: Node, marina: Dictionary) -> void:
	var centre: Vector2 = marina["position"]
	var rotation := float(marina["rotation"])
	var slips := int(marina["slips"])
	var dock_mesh := BoxMesh.new()
	dock_mesh.size = Vector3(8.0, 0.55, 95.0)
	var finger_mesh := BoxMesh.new()
	finger_mesh.size = Vector3(5.5, 0.42, 36.0)
	var boat_mesh := BoxMesh.new()
	boat_mesh.size = Vector3(5.2, 1.1, 13.0)

	var main := MeshInstance3D.new()
	main.name = "MarinaMainDock"
	main.mesh = dock_mesh
	main.material_override = _dock_mat
	main.position = Vector3(centre.x, land_y + 0.65, centre.y)
	main.rotation.y = rotation
	parent.add_child(main)

	for i in range(slips):
		var side := -1.0 if i % 2 == 0 else 1.0
		var along := -42.0 + float(i / 2) * 16.0
		var finger := MeshInstance3D.new()
		finger.name = "MarinaFinger"
		finger.mesh = finger_mesh
		finger.material_override = _dock_mat
		finger.position = Vector3(centre.x, land_y + 0.72, centre.y)
		finger.rotation.y = rotation + side * PI * 0.5
		finger.translate_object_local(Vector3(0.0, 0.0, 22.0))
		finger.translate_object_local(Vector3(along, 0.0, side * 5.0))
		parent.add_child(finger)

		var boat := MeshInstance3D.new()
		boat.name = "MooredBoat"
		boat.mesh = boat_mesh
		boat.material_override = _glass_mat if i % 3 == 0 else _concrete_mat
		boat.position = Vector3(centre.x, land_y + 0.95, centre.y)
		boat.rotation.y = rotation + side * PI * 0.5
		boat.translate_object_local(Vector3(0.0, 0.0, 42.0))
		boat.translate_object_local(Vector3(along, 0.0, side * 10.5))
		parent.add_child(boat)


func _add_flat_mesh(node_name: String, geo: Dictionary, mat: Material) -> void:
	if geo.is_empty() or (geo["vertices"] as PackedVector3Array).is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = geo["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = geo["normals"]
	if geo.has("uvs"):
		arrays[Mesh.ARRAY_TEX_UV] = geo["uvs"]
	arrays[Mesh.ARRAY_INDEX] = geo["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	add_child(mi)


func _build_city_accents() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3219
	var root := Node3D.new()
	root.name = "OriginalCityAnchors"
	add_child(root)

	for city in FloridaMapModel.city_nodes(map_scale):
		var centre: Vector2 = city["position"]
		var radius := float(city["radius"])
		var peak_height := float(city["height"])
		for i in range(18):
			var angle := rng.randf() * TAU
			var dist := radius * sqrt(rng.randf())
			var xz := centre + Vector2(cos(angle), sin(angle)) * dist
			var height := rng.randf_range(12.0, peak_height)
			var footprint := rng.randf_range(10.0, 24.0)
			_add_premium_tower(root, xz, footprint, height, rng, i)
		_add_city_label(root, city["name"], centre, peak_height)


func _add_premium_tower(
	parent: Node, xz: Vector2, footprint: float, height: float, rng: RandomNumberGenerator, index: int
) -> void:
	var base := MeshInstance3D.new()
	base.name = "OriginalPremiumTower"
	var box := BoxMesh.new()
	box.size = Vector3(footprint, height, footprint * rng.randf_range(0.75, 1.35))
	base.mesh = box
	base.material_override = _glass_mat if index % 3 == 0 else _dark_glass_mat
	base.position = Vector3(xz.x, land_y + height * 0.5, xz.y)
	base.rotation.y = rng.randf() * TAU
	parent.add_child(base)

	if index % 2 == 0:
		var crown := MeshInstance3D.new()
		crown.name = "TowerCrownGlow"
		var crown_mesh := BoxMesh.new()
		crown_mesh.size = Vector3(footprint * 1.12, 2.0, footprint * 1.12)
		crown.mesh = crown_mesh
		crown.material_override = _neon_mat
		crown.position = Vector3(xz.x, land_y + height + 1.2, xz.y)
		crown.rotation.y = base.rotation.y
		parent.add_child(crown)

	if index % 4 == 0:
		var podium := MeshInstance3D.new()
		podium.name = "TowerPodium"
		var podium_mesh := BoxMesh.new()
		podium_mesh.size = Vector3(footprint * 1.8, 8.0, footprint * 1.5)
		podium.mesh = podium_mesh
		podium.material_override = _tower_mat
		podium.position = Vector3(xz.x, land_y + 4.0, xz.y)
		podium.rotation.y = base.rotation.y
		parent.add_child(podium)

	if index % 5 == 0:
		var mast := MeshInstance3D.new()
		mast.name = "TowerMast"
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.22
		mast_mesh.bottom_radius = 0.32
		mast_mesh.height = 18.0
		mast.mesh = mast_mesh
		mast.material_override = _neon_mat
		mast.position = Vector3(xz.x, land_y + height + 9.0, xz.y)
		parent.add_child(mast)


func _add_city_label(parent: Node, text: String, centre: Vector2, height: float) -> void:
	var label := Label3D.new()
	label.name = "%sLabel" % text.replace(" ", "")
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 42
	label.modulate = Color(1.0, 0.88, 0.62)
	label.outline_size = 8
	label.outline_modulate = Color(0.02, 0.02, 0.025)
	label.position = Vector3(centre.x, land_y + height + 18.0, centre.y)
	parent.add_child(label)


func _build_wetlands() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.28
	trunk_mesh.bottom_radius = 0.44
	trunk_mesh.height = 5.2
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 2.2
	crown_mesh.height = 3.2

	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = trunk_mesh
	var crowns := MultiMesh.new()
	crowns.transform_format = MultiMesh.TRANSFORM_3D
	crowns.mesh = crown_mesh

	var points := FloridaMapModel.wetland_points(wetland_count, map_scale)
	trunks.instance_count = points.size()
	crowns.instance_count = points.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 811
	for i in points.size():
		var p := points[i]
		var s := rng.randf_range(0.75, 1.45)
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		var trunk_basis := yaw.scaled(Vector3(s, s, s))
		trunks.set_instance_transform(
			i, Transform3D(trunk_basis, Vector3(p.x, land_y + 2.6 * s, p.y))
		)
		crowns.set_instance_transform(
			i, Transform3D(trunk_basis, Vector3(p.x, land_y + 6.0 * s, p.y))
		)

	var trunk_layer := MultiMeshInstance3D.new()
	trunk_layer.name = "WetlandCypressTrunks"
	trunk_layer.multimesh = trunks
	trunk_layer.material_override = _cypress_mat
	add_child(trunk_layer)

	var crown_layer := MultiMeshInstance3D.new()
	crown_layer.name = "WetlandCypressCrowns"
	crown_layer.multimesh = crowns
	crown_layer.material_override = _leaf_mat
	add_child(crown_layer)


func _build_swim_volume() -> void:
	var volume := Area3D.new()
	volume.name = "StateOceanSwimVolume"
	volume.set_script(WATER_VOLUME_SCRIPT)
	volume.position = Vector3(0.0, ocean_y - 4.0, 0.0)
	volume.set("surface_offset", 4.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(water_size_m, 8.0, water_size_m)
	shape.shape = box
	volume.add_child(shape)
	add_child(volume)
