extends SceneTree
## Dev-only isolation shot of CoastalPalms over a sand ground — no FloatingOrigin
## recentring (which makes the palms impossible to frame by raw coords in the
## live map), so the fringe geometry/distribution can be judged directly. Run
## WINDOWED:
##   SHOT=/tmp/palms.png godot --path game --script res://tests/coastal_palms_capture.gd

var _frames := 0


func _initialize() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(900.0, 900.0)
	var sand := load("res://shaders/florida_sand.gdshader") as Shader
	if sand != null:
		var sm := ShaderMaterial.new()
		sm.shader = sand
		ground.material_override = sm
	ground.mesh = plane
	# Centre the ground under a known palm cluster (~1591, 303).
	ground.position = Vector3(1591.0, 0.0, 303.0)
	root.add_child(ground)

	var palms := CoastalPalms.new()
	root.add_child(palms)
	palms.populate()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26.0, 40.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.92, 0.78)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.66, 0.78, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.85)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 2000.0
		cam.fov = 62.0
		root.add_child(cam)
		cam.global_position = Vector3(1645.0, 10.0, 360.0)
		cam.look_at(Vector3(1585.0, 7.0, 300.0), Vector3.UP)
		cam.current = true
	if _frames < 100:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/palms.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("coastal palms capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
