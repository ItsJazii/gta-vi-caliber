extends SceneTree
## Dev-only isolation shot of the state-ground materials (florida_land /
## florida_sand) — no HUD, no golden grade, so the material's own colour and
## macro variation can be judged honestly from altitude and ground level.
## Run WINDOWED:
##   MAT=land ALT=1 SHOT=/tmp/land.png godot --path game --script res://tests/land_material_capture.gd
## Env: MAT (land|sand), ALT (1 = aerial 3/4, else ground-level), SHOT.

var _frames := 0


func _initialize() -> void:
	var which := OS.get_environment("MAT")
	if which == "":
		which = "land"
	var path := "res://shaders/florida_%s.gdshader" % ("sand" if which == "sand" else "land")
	var mat := ShaderMaterial.new()
	mat.shader = load(path)

	var plane := PlaneMesh.new()
	plane.size = Vector2(3000.0, 3000.0)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	root.add_child(mi)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 40.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.97, 0.9)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.68, 0.8)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_setup_cam()
	if _frames < 120:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/land.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("land capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true


func _setup_cam() -> void:
	var cam := Camera3D.new()
	cam.far = 6000.0
	cam.fov = 60.0
	root.add_child(cam)
	if OS.get_environment("ALT") == "1":
		cam.global_position = Vector3(0.0, 120.0, 320.0)
		cam.look_at(Vector3(0.0, 0.0, -400.0), Vector3.UP)
	else:
		cam.global_position = Vector3(0.0, 1.7, 0.0)
		cam.look_at(Vector3(0.0, 1.4, -200.0), Vector3.UP)
	cam.current = true
