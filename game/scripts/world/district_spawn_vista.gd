class_name DistrictSpawnVista
extends RefCounted
## The hand-dressed hero street built around the player spawn: a clean asphalt
## ribbon with lane dashes, crosswalks, sidewalks, palm rows and traffic cones,
## so the first playable view opens on a composed Vice City corridor instead of
## raw OSM massing. Split out of DistrictLoader (which decides WHERE to spawn);
## this class only dresses the chosen spot.


static func build(parent: Node3D, spawn: Vector3, yaw: float, street_y: float) -> void:
	var root := Node3D.new()
	root.name = "SpawnVistaStreet"
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	# The hero road box (0.12 thick) is centred on the root, so dropping the root
	# 0.06 below street_y puts the road's TOP exactly at street_y + 0.06 = the
	# floor (street_y is -0.02), so the player spawns standing on the asphalt
	# instead of sunk into it. It also rides just above the district road ribbons
	# (at street_y) so the two don't z-fight where they overlap.
	root.position = Vector3(spawn.x, street_y - 0.04, spawn.z) + forward * 4.0
	root.rotation.y = yaw
	parent.add_child(root)

	# Shaded (was unshaded) so the hero corridor breathes with the day/night
	# cycle, the cinematic grade and the night streetlamps instead of rendering
	# as a flat black slab the lighting can't touch. Dark asphalt albedo keeps it
	# reading as fresh tarmac.
	var asphalt_mat := StandardMaterial3D.new()
	asphalt_mat.albedo_color = Color(0.05, 0.052, 0.055)
	asphalt_mat.roughness = 0.92
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(18.0, 0.12, 160.0)
	_add_surface(root, "HeroRoad", road_mesh, asphalt_mat, Vector3.ZERO)

	var sidewalk_mat := StandardMaterial3D.new()
	sidewalk_mat.albedo_color = Color(0.30, 0.30, 0.28)
	sidewalk_mat.roughness = 0.88
	var sidewalk_mesh := BoxMesh.new()
	sidewalk_mesh.size = Vector3(4.0, 0.12, 160.0)
	_add_surface(root, "LeftSidewalk", sidewalk_mesh, sidewalk_mat, Vector3(11.0, 0.04, 0.0))
	_add_surface(root, "RightSidewalk", sidewalk_mesh, sidewalk_mat, Vector3(-11.0, 0.04, 0.0))

	var paint_mat := StandardMaterial3D.new()
	paint_mat.albedo_color = Color(0.86, 0.82, 0.68)
	paint_mat.roughness = 0.82
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(0.22, 0.025, 4.8)
	for z in [-60.0, -48.0, -36.0, -24.0, -12.0, 0.0, 12.0, 24.0, 36.0, 48.0, 60.0]:
		_add_surface(root, "LaneDash", dash_mesh, paint_mat, Vector3(0.0, 0.07, z))

	var crosswalk_mesh := BoxMesh.new()
	crosswalk_mesh.size = Vector3(13.5, 0.025, 0.48)
	for z in [-70.0, -69.1, -68.2, 68.2, 69.1, 70.0]:
		_add_surface(root, "CrosswalkBar", crosswalk_mesh, paint_mat, Vector3(0.0, 0.075, z))

	_build_palms(root)
	_build_cones(root)
	_build_lamps(root)


## Warm streetlamps down the hero corridor with real OmniLight3D pools that fade
## in at night via a StreetlightSwitch — so the player's opening view lights up
## after dusk like the streamed district roads do.
static func _build_lamps(parent: Node3D) -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.1, 0.1, 0.12)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.5
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.92, 0.72)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.85, 0.55)
	lamp_mat.emission_energy_multiplier = 2.5
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.14, 5.0, 0.14)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.5, 0.22, 0.32)

	var switch := StreetlightSwitch.new()
	switch.setup(lamp_mat, lamp_mat.emission_energy_multiplier)
	parent.add_child(switch)

	var lights: Array[OmniLight3D] = []
	for side in [-1.0, 1.0]:
		for z in [-60.0, -36.0, -12.0, 12.0, 36.0, 60.0]:
			var lamp := Node3D.new()
			lamp.name = "SpawnLamp"
			lamp.position = Vector3(side * 9.3, 0.1, z)
			var pole := MeshInstance3D.new()
			pole.mesh = pole_mesh
			pole.material_override = pole_mat
			pole.position = Vector3(0.0, 2.5, 0.0)
			lamp.add_child(pole)
			var head := MeshInstance3D.new()
			head.mesh = head_mesh
			head.material_override = lamp_mat
			head.position = Vector3(0.0, 5.0, 0.0)
			lamp.add_child(head)
			var glow := OmniLight3D.new()
			glow.omni_range = 14.0
			glow.omni_attenuation = 1.4
			glow.light_color = Color(1.0, 0.85, 0.55)
			glow.light_energy = 0.0
			glow.light_volumetric_fog_energy = 0.0
			glow.shadow_enabled = false
			glow.visible = false
			glow.position = Vector3(0.0, 4.7, 0.0)
			lamp.add_child(glow)
			lights.append(glow)
			parent.add_child(lamp)
	switch.bind_lights(lights, 4.0)


static func _add_surface(
	parent: Node, node_name: String, mesh: Mesh, mat: Material, pos: Vector3
) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _build_palms(parent: Node3D) -> void:
	var trunk_mesh := TreeMesh.to_mesh(TreeMesh.palm_trunk(8.0))
	var crown_mesh := TreeMesh.to_mesh(TreeMesh.palm_crown(11, 2.7, 8.0))
	if trunk_mesh == null or crown_mesh == null:
		return
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.52, 0.44, 0.34)
	bark.roughness = 0.92
	var frond := StandardMaterial3D.new()
	frond.albedo_color = Color(0.24, 0.45, 0.18)
	frond.roughness = 0.86
	frond.cull_mode = BaseMaterial3D.CULL_DISABLED

	for side in [-1.0, 1.0]:
		for i in 6:
			var z := -48.0 + float(i) * 19.0
			var palm := Node3D.new()
			palm.name = "SpawnPalm"
			palm.position = Vector3(side * 13.2, 0.0, z)
			palm.rotation.y = side * 0.25 + float(i) * 0.31
			var s := 0.86 + float(i % 3) * 0.08
			palm.scale = Vector3(s, s, s)
			parent.add_child(palm)
			_add_surface(palm, "Trunk", trunk_mesh, bark, Vector3.ZERO)
			_add_surface(palm, "Crown", crown_mesh, frond, Vector3.ZERO)


static func _build_cones(parent: Node3D) -> void:
	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color(1.0, 0.36, 0.08)
	cone_mat.roughness = 0.72
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.08
	cone_mesh.bottom_radius = 0.28
	cone_mesh.height = 0.72
	cone_mesh.radial_segments = 10
	for z in [-34.0, -18.0, 18.0, 34.0]:
		_add_surface(parent, "TrafficCone", cone_mesh, cone_mat, Vector3(7.4, 0.36, z))
