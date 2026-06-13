extends SceneTree
## Dev-only isolation shot of a Billboards hoarding — frames one panel head-on to
## judge the posted/framed structure and that the parody ad reads. Run WINDOWED:
##   SHOT=/tmp/billboard.png godot --path game --script res://tests/billboards_capture.gd

var _frames := 0


func _initialize() -> void:
	var boards := Billboards.new()
	boards.count = 1
	boards.line_x = 0.0
	boards.z_start = 0.0
	boards.z_end = 0.0
	root.add_child(boards)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.2, 0.18)
	ground.mesh = plane
	ground.material_override = gm
	root.add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, -120.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.93, 0.82)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.66, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		# i=0 faces -x, so view from -x.
		var cam := Camera3D.new()
		cam.far = 800.0
		cam.fov = 50.0
		root.add_child(cam)
		cam.global_position = Vector3(-26.0, 9.5, 1.0)
		cam.look_at(Vector3(0.0, 9.0, 0.0), Vector3.UP)
		cam.current = true
	if _frames < 90:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/billboard.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("billboards capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
