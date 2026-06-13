extends SceneTree
## Dev-only isolation shot of WetlandFlora over the florida_land ground — no HUD,
## no golden grade, so the wetland density/canopy can be judged honestly (the
## flora is invisibly sparse to hunt for in the full miami map). Run WINDOWED:
##   SHOT=/tmp/wetland.png godot --path game --script res://tests/wetland_flora_capture.gd
## Env: SEEDS (grid of seed points per side), SHOT.

var _frames := 0


func _initialize() -> void:
	# Ground: the real florida_land material so vegetation sits on true terrain.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700.0, 700.0)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	ground.mesh = plane
	var land := load("res://shaders/florida_land.gdshader") as Shader
	if land != null:
		var lm := ShaderMaterial.new()
		lm.shader = land
		ground.material_override = lm
	root.add_child(ground)

	# A grid of wetland seed points across the plane → clustered flora.
	var n := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 8
	var pts := PackedVector2Array()
	var span := 280.0
	for ix in n:
		for iz in n:
			var fx := (float(ix) / float(n - 1) - 0.5) * 2.0 * span
			var fz := (float(iz) / float(n - 1) - 0.5) * 2.0 * span
			pts.append(Vector2(fx, fz))

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.22, 0.16, 0.11)
	trunk_mat.roughness = 0.95
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.14, 0.28, 0.13)
	leaf_mat.roughness = 0.92
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shrub_mat := StandardMaterial3D.new()
	shrub_mat.albedo_color = Color(0.20, 0.31, 0.13)
	shrub_mat.roughness = 0.93
	shrub_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var holder := Node3D.new()
	root.add_child(holder)
	var counts := WetlandFlora.build(holder, pts, 0.0, trunk_mat, leaf_mat, shrub_mat, 811)
	print(
		(
			"wetland flora: %d trees, %d crowns, %d shrubs"
			% [counts["trees"], counts["crowns"], counts["shrubs"]]
		)
	)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 40.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.96, 0.88)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.74, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.68, 0.8)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 4000.0
		cam.fov = 60.0
		root.add_child(cam)
		cam.global_position = Vector3(0.0, 45.0, 320.0)
		cam.look_at(Vector3(0.0, 6.0, -120.0), Vector3.UP)
		cam.current = true
	if _frames < 120:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/wetland.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("wetland flora capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
