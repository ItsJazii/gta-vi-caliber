class_name BeachProps
extends Node3D
## Shoreline postcard foreground for the Venice Beach scene: a seeded row of
## procedural palms (PalmMesh) plus benches and warm lamp posts along the
## boardwalk line, so a shore camera frames palms + sand + ocean + lit city.
##
## Sits as a CHILD of the Ground plane (the dry shelf the city stands on; the
## tilted Beach plane dives below sea level toward the city) and works purely
## in parent-local coordinates: FloatingOrigin shifts top-level scene nodes,
## so children ride along and nothing here ever computes a world-absolute
## position (see the re-anchor note in venice_beach.gd). The waterline is the
## Ground's west edge at local x -1200 (scene-local -21249); the city facades
## begin ~30 m further east, so the palm row threads the strip between them.

const PALM_VARIANTS := 3

## Parent-local x of the palm row (scene-local ≈ ground centre -20049 + row_x).
@export var row_x: float = -1178.0
## Palms run z in [-row_half_z, row_half_z] (scene-local z ~5860..7860).
@export var row_half_z: float = 1000.0
@export var spacing: float = 35.0
@export var seed_value: int = 4242


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.45, 0.36, 0.27)
	trunk_mat.roughness = 0.95
	var frond_mat := StandardMaterial3D.new()
	frond_mat.albedo_color = Color(0.2, 0.45, 0.16)
	frond_mat.roughness = 0.85
	frond_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# A few shared trunk/crown variants keep 60+ palms cheap while the seeded
	# per-palm yaw/lean/scale below hides the repetition.
	var trunks: Array[ArrayMesh] = []
	var crowns: Array[ArrayMesh] = []
	var tips: Array[Vector3] = []
	for i in PALM_VARIANTS:
		var height: float = 10.0 + 2.5 * float(i)
		var bend: float = 1.0 + 0.7 * float(i)
		trunks.append(TreeMesh.to_mesh(PalmMesh.trunk(height, bend, 0.34, 0.19)))
		crowns.append(TreeMesh.to_mesh(PalmMesh.crown(8, 4.2, 0.75, seed_value + i)))
		tips.append(PalmMesh.tip(height, bend))

	var z: float = -row_half_z
	while z <= row_half_z:
		var variant: int = rng.randi_range(0, PALM_VARIANTS - 1)
		var pos := Vector3(row_x + rng.randf_range(-5.0, 5.0), 0.0, z + rng.randf_range(-5.0, 5.0))
		_add_palm(trunks[variant], crowns[variant], tips[variant], trunk_mat, frond_mat, pos, rng)
		z += spacing
	_add_boardwalk_props(rng)


func _add_palm(
	trunk_mesh: ArrayMesh,
	crown_mesh: ArrayMesh,
	crown_tip: Vector3,
	trunk_mat: StandardMaterial3D,
	frond_mat: StandardMaterial3D,
	pos: Vector3,
	rng: RandomNumberGenerator
) -> void:
	var palm := Node3D.new()
	palm.position = pos
	var s: float = rng.randf_range(0.85, 1.25)
	palm.scale = Vector3(s, s, s)
	palm.rotation.y = rng.randf() * TAU
	palm.rotation.x = rng.randf_range(-0.05, 0.05)
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.material_override = trunk_mat
	palm.add_child(trunk)
	var crown := MeshInstance3D.new()
	crown.mesh = crown_mesh
	crown.material_override = frond_mat
	crown.position = crown_tip
	crown.rotation.y = rng.randf() * TAU
	palm.add_child(crown)
	add_child(palm)


## Benches and warm emissive lamp posts on the city side of the palm row —
## the same shared-mesh prop pattern as district_loader's street furniture.
func _add_boardwalk_props(rng: RandomNumberGenerator) -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.42, 0.3, 0.2)
	wood_mat.roughness = 0.9
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.12, 0.12, 0.14)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.5
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.9, 0.7)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.82, 0.5)
	lamp_mat.emission_energy_multiplier = 2.5
	# Fade the boardwalk lamps with the same day/night clock as the city
	# streetlights instead of leaving them glowing at noon.
	var switch := StreetlightSwitch.new()
	switch.setup(lamp_mat, lamp_mat.emission_energy_multiplier)
	add_child(switch)
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(0.5, 0.08, 1.8)
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.08, 0.5, 1.8)
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.14, 4.2, 0.14)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44

	var index: int = 0
	var z: float = -row_half_z + spacing * 0.5
	while z <= row_half_z:
		var x: float = row_x + 10.0 + rng.randf_range(-1.5, 1.5)
		if index % 2 == 0:
			var lamp := Node3D.new()
			lamp.position = Vector3(x, 0.0, z)
			var pole := MeshInstance3D.new()
			pole.mesh = pole_mesh
			pole.material_override = pole_mat
			pole.position = Vector3(0.0, 2.1, 0.0)
			lamp.add_child(pole)
			var head := MeshInstance3D.new()
			head.mesh = head_mesh
			head.material_override = lamp_mat
			head.position = Vector3(0.0, 4.3, 0.0)
			lamp.add_child(head)
			add_child(lamp)
		else:
			var bench := Node3D.new()
			bench.position = Vector3(x, 0.0, z)
			bench.rotation.y = rng.randf_range(-0.15, 0.15)
			var seat := MeshInstance3D.new()
			seat.mesh = seat_mesh
			seat.material_override = wood_mat
			seat.position = Vector3(0.0, 0.45, 0.0)
			bench.add_child(seat)
			var back := MeshInstance3D.new()
			back.mesh = back_mesh
			back.material_override = wood_mat
			back.position = Vector3(0.25, 0.74, 0.0)
			bench.add_child(back)
			add_child(bench)
		index += 1
		z += spacing * 2.0
