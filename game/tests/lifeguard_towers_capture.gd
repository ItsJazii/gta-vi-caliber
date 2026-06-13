extends SceneTree
## Dev-only isolation shot of LifeguardTowers on sand — judges the pastel stand
## form (legs, hut, peaked roof, flag, ladder) and the colour cycle. Run WINDOWED:
##   SHOT=/tmp/towers.png godot --path game --script res://tests/lifeguard_towers_capture.gd

var _frames := 0


func _initialize() -> void:
	var towers := LifeguardTowers.new()
	towers.line_x = 0.0
	towers.z_start = -18.0
	towers.z_end = 18.0
	towers.count = 4
	root.add_child(towers)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	var sand := load("res://shaders/florida_sand.gdshader") as Shader
	if sand != null:
		var sm := ShaderMaterial.new()
		sm.shader = sand
		ground.material_override = sm
	ground.mesh = plane
	root.add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, 60.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.85)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.68, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.72, 0.86)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 800.0
		cam.fov = 55.0
		root.add_child(cam)
		cam.global_position = Vector3(26.0, 7.0, -26.0)
		cam.look_at(Vector3(0.0, 3.0, 4.0), Vector3.UP)
		cam.current = true
	if _frames < 90:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/towers.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("lifeguard towers capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
