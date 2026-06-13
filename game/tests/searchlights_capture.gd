extends SceneTree
## Dev-only NIGHT shot of Searchlights — dark sky, beams swept to a crossed
## frame. Run WINDOWED:
##   SHOT=/tmp/searchlights.png godot --path game --script res://tests/searchlights_capture.gd

var _frames := 0
var _lights: Searchlights


func _initialize() -> void:
	_lights = Searchlights.new()
	root.add_child(_lights)

	# A faint ground so the bases sit on something.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.04, 0.04, 0.06)
	ground.mesh = plane
	ground.material_override = gm
	root.add_child(ground)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.04, 0.05, 0.09)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.25
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	_lights._apply(1.6)  # a crossed-beam moment
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 2000.0
		cam.fov = 62.0
		root.add_child(cam)
		cam.global_position = Vector3(0.0, 35.0, 150.0)
		cam.look_at(Vector3(0.0, 90.0, 0.0), Vector3.UP)
		cam.current = true
	if _frames < 80:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/searchlights.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("searchlights capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
