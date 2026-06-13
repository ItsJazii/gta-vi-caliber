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
var _sign_face_mat: StandardMaterial3D
var _sign_back_mat: StandardMaterial3D
var _amber_light_mat: StandardMaterial3D
var _cypress_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _shrub_mat: StandardMaterial3D

var _landmarks: FloridaLandmarks
var _threejs: FloridaThreeJsPlacements


func _ready() -> void:
	_make_materials()
	_landmarks = FloridaLandmarks.new(self)
	_threejs = FloridaThreeJsPlacements.new(self)
	_build_water()
	_build_land()
	_build_key_islands()
	_build_coastline()
	_build_routes()
	_build_bridges()
	_build_route_details()
	_build_marinas()
	_build_beach_resorts()
	_build_landmarks()
	_threejs.build_landmark_models()
	_threejs.build_city_blocks()
	_threejs.build_neon_details()
	_threejs.build_regional_destinations()
	_threejs.build_infrastructure_details()
	_threejs.build_environment_details()
	_threejs.build_traffic_marine_details()
	_threejs.build_vista_details()
	_threejs.build_streetlife_details()
	_build_city_accents()
	_build_map_markers()
	_build_wetlands()
	_build_coastal_palms()
	_build_clouds()
	_build_bay_boats()
	_build_seabirds()
	_build_ad_blimp()
	_build_air_banner()
	_build_billboards()
	_build_pier()
	_build_lifeguard_towers()
	_build_neon_sign()
	_build_neon_strip()
	_build_neon_pylon()
	_build_searchlights()
	_build_causeway_traffic()
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

	_sign_face_mat = StandardMaterial3D.new()
	_sign_face_mat.albedo_color = Color(0.05, 0.34, 0.28)
	_sign_face_mat.roughness = 0.5

	_sign_back_mat = StandardMaterial3D.new()
	_sign_back_mat.albedo_color = Color(0.08, 0.10, 0.11)
	_sign_back_mat.metallic = 0.25
	_sign_back_mat.roughness = 0.44

	_amber_light_mat = StandardMaterial3D.new()
	_amber_light_mat.albedo_color = Color(1.0, 0.68, 0.28)
	_amber_light_mat.emission_enabled = true
	_amber_light_mat.emission = Color(1.0, 0.54, 0.16)
	_amber_light_mat.emission_energy_multiplier = 1.8

	_cypress_mat = StandardMaterial3D.new()
	_cypress_mat.albedo_color = Color(0.22, 0.16, 0.11)
	_cypress_mat.roughness = 0.95

	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_color = Color(0.12, 0.27, 0.12)
	_leaf_mat.roughness = 0.92
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_shrub_mat = StandardMaterial3D.new()
	_shrub_mat.albedo_color = Color(0.20, 0.31, 0.13)
	_shrub_mat.roughness = 0.93
	_shrub_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


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
	# Tiered grid: a fine 3 km square over the playable bay (31 m vertex
	# spacing — finer than the old uniform 62.5 m, so the 42 m swell finally
	# displaces), flat 750 m quads out to the horizon. ~19k triangles versus
	# ~74k for the old uniform 192x192 plane.
	water.set("resolution", 96)
	water.set("fine_extent_m", 1500.0)
	water.set("far_cell_m", 750.0)
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
	# Flat seabed → keep the shoreline band thin (above), but let the open bay
	# froth: Jacobian whitecaps on the swell read as a living sea, not plastic.
	water.set("whitecap_strength", 0.7)
	water.set("whitecap_coverage", 0.96)
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


func _ellipse_outline(
	centre: Vector2, size: Vector2, rotation: float, steps: int
) -> PackedVector2Array:
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
	_add_flat_mesh(
		"StateCauseways",
		{"vertices": verts, "normals": norms, "indices": idx, "uvs": uvs},
		_road_mat
	)


func _build_bridges() -> void:
	var root := Node3D.new()
	root.name = "SignatureBridges"
	add_child(root)
	for path in FloridaMapModel.bridge_paths(map_scale):
		_add_bridge_span(root, path[0], path[1])


func _build_route_details() -> void:
	var root := Node3D.new()
	root.name = "OriginalRouteDetails"
	add_child(root)
	var samples := FloridaMapModel.route_samples(map_scale, 520.0)
	for i in range(samples.size()):
		var sample := samples[i]
		var pos: Vector2 = sample["position"]
		var dir: Vector2 = sample["direction"]
		if i % 4 == 0:
			_add_route_billboard(root, pos, dir, i)
		elif i % 4 == 1:
			_add_route_sign(root, pos, dir, i)
		else:
			_add_light_mast(root, pos, dir, i)


func _route_yaw(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


func _add_route_billboard(parent: Node, xz: Vector2, dir: Vector2, index: int) -> void:
	var board := Node3D.new()
	board.name = "RouteBillboard"
	board.position = Vector3(xz.x, land_y + 0.2, xz.y)
	board.rotation.y = _route_yaw(dir) + PI * 0.5
	board.translate_object_local(Vector3(36.0, 0.0, 0.0))
	parent.add_child(board, true)

	for x in [-5.5, 5.5]:
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.32
		pole_mesh.bottom_radius = 0.42
		pole_mesh.height = 14.0
		pole.mesh = pole_mesh
		pole.material_override = _steel_mat
		pole.position = Vector3(x, 7.0, 0.0)
		board.add_child(pole)

	var face := MeshInstance3D.new()
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(18.0, 7.0, 0.55)
	face.mesh = face_mesh
	face.material_override = _resort_coral_mat if index % 8 == 0 else _resort_aqua_mat
	face.position = Vector3(0.0, 15.5, 0.0)
	board.add_child(face)

	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(15.5, 0.55, 0.62)
	stripe.mesh = stripe_mesh
	stripe.material_override = _neon_mat
	stripe.position = Vector3(0.0, 17.2, -0.35)
	board.add_child(stripe)


func _add_route_sign(parent: Node, xz: Vector2, dir: Vector2, index: int) -> void:
	var sign := Node3D.new()
	sign.name = "RouteSign"
	sign.position = Vector3(xz.x, land_y + 0.2, xz.y)
	sign.rotation.y = _route_yaw(dir) + PI * 0.5
	sign.translate_object_local(Vector3(-24.0, 0.0, 0.0))
	parent.add_child(sign, true)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.15
	pole_mesh.bottom_radius = 0.18
	pole_mesh.height = 5.5
	pole.mesh = pole_mesh
	pole.material_override = _steel_mat
	pole.position = Vector3(0.0, 2.75, 0.0)
	sign.add_child(pole)

	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(5.8, 2.8, 0.3)
	panel.mesh = panel_mesh
	panel.material_override = _sign_face_mat
	panel.position = Vector3(0.0, 6.0, 0.0)
	sign.add_child(panel)

	var route_bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(4.6, 0.28, 0.34)
	route_bar.mesh = bar_mesh
	route_bar.material_override = _resort_white_mat
	route_bar.position = Vector3(0.0, 6.55, -0.2)
	sign.add_child(route_bar)

	if index % 3 == 0:
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(5.8, 0.42, 0.34)
		cap.mesh = cap_mesh
		cap.material_override = _amber_light_mat
		cap.position = Vector3(0.0, 7.6, -0.2)
		sign.add_child(cap)


func _add_light_mast(parent: Node, xz: Vector2, dir: Vector2, index: int) -> void:
	var mast := Node3D.new()
	mast.name = "RouteLightMast"
	mast.position = Vector3(xz.x, land_y + 0.2, xz.y)
	mast.rotation.y = _route_yaw(dir) + PI * 0.5
	mast.translate_object_local(Vector3(20.0 if index % 2 == 0 else -20.0, 0.0, 0.0))
	parent.add_child(mast, true)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.22
	pole_mesh.bottom_radius = 0.32
	pole_mesh.height = 12.0
	pole.mesh = pole_mesh
	pole.material_override = _steel_mat
	pole.position = Vector3(0.0, 6.0, 0.0)
	mast.add_child(pole)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(7.5, 0.34, 0.34)
	arm.mesh = arm_mesh
	arm.material_override = _steel_mat
	arm.position = Vector3(3.8, 12.0, 0.0)
	mast.add_child(arm)

	var lamp := MeshInstance3D.new()
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(1.4, 0.5, 0.7)
	lamp.mesh = lamp_mesh
	lamp.material_override = _amber_light_mat
	lamp.position = Vector3(7.8, 11.75, 0.0)
	mast.add_child(lamp)


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
			_landmarks.add_cabana(root, world, rotation + rng.randf_range(-0.18, 0.18), rng)
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
			_landmarks.add_beach_umbrella(root, world, rotation + rng.randf_range(-0.3, 0.3), i)


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
				_landmarks.add_lighthouse(root, pos, yaw)
			"wheel":
				_landmarks.add_observation_wheel(root, pos, yaw)
			"launch":
				_landmarks.add_launch_tower(root, pos, yaw)
			"arch":
				_landmarks.add_resort_arch(root, pos, yaw)


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
	parent: Node,
	xz: Vector2,
	footprint: float,
	height: float,
	rng: RandomNumberGenerator,
	index: int
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


func _build_coastal_palms() -> void:
	# Iconic palm fringe along the shore — frames the establishing shots that the
	# bare sand left empty. CoastalPalms walks the same coast outline as
	# _build_coastline, so the palms line the waterline the player sees.
	var palms := CoastalPalms.new()
	palms.name = "CoastalPalms"
	palms.map_scale = map_scale
	palms.ground_y = land_y + 0.05
	add_child(palms)


func _build_causeway_traffic() -> void:
	# Ambient cars driving the bay causeways (with night head/tail lights) — the
	# bridges the player drives shouldn't be empty. Density is bounded for perf;
	# these are long spans, so it reads as light traffic, not a jam.
	var traffic := CausewayTraffic.new()
	traffic.name = "CausewayTraffic"
	add_child(traffic)


func _build_searchlights() -> void:
	# Sweeping club searchlight beams over the boardwalk — night-sky drama.
	var lights := Searchlights.new()
	lights.name = "Searchlights"
	lights.position = Vector3(1300.0, land_y + 0.5, 560.0)
	add_child(lights)


func _build_neon_pylon() -> void:
	# An animated vintage motel pylon (chasing border + blinking VACANCY) — the
	# moving neon landmark by the boardwalk.
	var pylon := NeonPylon.new()
	pylon.name = "NeonPylon"
	pylon.position = Vector3(1255.0, land_y, 640.0)
	add_child(pylon)


func _build_neon_strip() -> void:
	# Ocean-Drive Art-Deco strip: pastel hotels by day, glowing neon by night.
	# A back row just inland of the boardwalk so it doesn't fight the billboards.
	var strip := NeonStrip.new()
	strip.name = "NeonStrip"
	strip.ground_y = land_y
	strip.line_x = 1280.0
	add_child(strip)


func _build_neon_sign() -> void:
	# A glowing neon gateway at the pier approach — the Vice City night signature.
	var sign := NeonSign.new()
	sign.name = "NeonSign"
	sign.position = Vector3(1350.0, land_y, 470.0)
	sign.rotation.y = -PI * 0.5
	add_child(sign)


func _build_lifeguard_towers() -> void:
	# The pastel Miami Beach lifeguard stands along the shore — a signature Vice
	# City motif facing the water.
	var towers := LifeguardTowers.new()
	towers.name = "LifeguardTowers"
	towers.ground_y = land_y
	add_child(towers)


func _build_pier() -> void:
	# A fishing pier reaching off the bay-facing shore into the water — the
	# "pier" half of the ledger's palms/pier postcard note. Yawed so the deck
	# extends from the mainland shore out over the bay.
	var pier := Pier.new()
	pier.name = "Pier"
	pier.position = Vector3(1380.0, 0.0, 500.0)
	pier.rotation.y = -PI * 0.5
	add_child(pier)


func _build_billboards() -> void:
	# Satirical roadside hoardings along the bay-facing shore — the humor/tone
	# axis plus set-dressing the player drives past.
	var boards := Billboards.new()
	boards.name = "Billboards"
	boards.ground_y = land_y
	add_child(boards)


func _build_air_banner() -> void:
	# A banner-tow plane circling the beach with a satirical ad — ambient air
	# life plus the humor/tone axis. Default centre is over South Beach.
	var banner := AirBanner.new()
	banner.name = "AirBanner"
	add_child(banner)


func _build_ad_blimp() -> void:
	# A high advertising blimp circling over downtown — visible from the player's
	# actual playspace (unlike the far-coast props) and reads in the dusk grade.
	var blimp := AdBlimp.new()
	blimp.name = "AdBlimp"
	# Lower + a touch slower than default so it reads from the ground rather than
	# being a high speck lost in the dusk haze.
	blimp.centre = Vector3(200.0, 190.0, -250.0)
	blimp.radius = 520.0
	add_child(blimp)


func _build_seabirds() -> void:
	# Ambient gulls wheeling over the bay — the moving life the static scenery
	# doesn't give. Centred over the open bay so they read against sky + water.
	var birds := SeabirdFlock.new()
	birds.name = "SeabirdFlock"
	birds.centre = Vector3(2800.0, 80.0, 0.0)
	add_child(birds)


func _build_bay_boats() -> void:
	# Ambient fleet drifting/bobbing on the open bay so the water reads as a
	# living waterway, not an empty plane. Matches the StateOcean wave clock
	# (same ocean_y/amplitude_scale as _build_water) via OceanMath.
	var boats := BayBoats.new()
	boats.name = "BayBoats"
	boats.ocean_y = ocean_y
	boats.amplitude_scale = 0.75
	boats.count = 30
	boats.area_min = Vector2(1500.0, -2300.0)
	boats.area_max = Vector2(5000.0, 1600.0)
	add_child(boats)


func _build_clouds() -> void:
	# A high broken-cumulus sheet so the playable map's flat ProceduralSky gains
	# depth and drift. CloudLayer owns the look; added here (not in the shared
	# scene env) so the world gets a sky without touching miami.tscn.
	var clouds := CloudLayer.new()
	clouds.name = "CloudLayer"
	add_child(clouds)


func _build_wetlands() -> void:
	# Cluster each wetland seed point into layered cypress + shrub understory.
	# WetlandFlora owns the look (and its own tests); the count of seed points
	# stays FloridaMapModel-driven so the wetlands keep their spatial spread.
	var points := FloridaMapModel.wetland_points(wetland_count, map_scale)
	WetlandFlora.build(self, points, land_y, _cypress_mat, _leaf_mat, _shrub_mat)


func _build_map_markers() -> void:
	var root := Node3D.new()
	root.name = "OriginalMapMarkers"
	add_child(root)
	for marker in FloridaMapModel.poi_markers(map_scale):
		var p: Vector2 = marker["position"]
		var kind := String(marker["kind"])
		var node := Marker3D.new()
		node.name = "%sMarker" % String(marker["name"]).replace(" ", "")
		node.position = Vector3(p.x, land_y + 2.0, p.y)
		node.set_meta("map_label", marker["name"])
		node.add_to_group("poi_%s" % kind)
		root.add_child(node, true)
		if kind == "city" or kind == "landmark":
			_add_map_marker_label(root, String(marker["name"]), p, kind)


func _add_map_marker_label(parent: Node, text: String, xz: Vector2, kind: String) -> void:
	var label := Label3D.new()
	label.name = "%sMapLabel" % text.replace(" ", "")
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30 if kind == "city" else 24
	label.modulate = Color(0.55, 0.92, 1.0) if kind == "city" else Color(1.0, 0.78, 0.34)
	label.outline_size = 6
	label.outline_modulate = Color(0.02, 0.02, 0.025)
	label.position = Vector3(xz.x, land_y + (86.0 if kind == "city" else 58.0), xz.y)
	parent.add_child(label, true)


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
