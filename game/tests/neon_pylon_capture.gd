extends SceneTree
## Dev-only NIGHT shot of NeonPylon — dark env + glow, animation advanced so the
## border chase is mid-sweep and VACANCY is lit. Run WINDOWED:
##   SHOT=/tmp/pylon.png godot --path game --script res://tests/neon_pylon_capture.gd

var _frames := 0
var _pylon: NeonPylon


func _initialize() -> void:
	_pylon = NeonPylon.new()
	root.add_child(_pylon)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	moon.light_energy = 0.1
	moon.light_color = Color(0.5, 0.6, 0.9)
	root.add_child(moon)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.1)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.35
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	# Advance the sign's own animation to a lively mid-chase frame.
	_pylon._process(0.25)
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 800.0
		cam.fov = 50.0
		root.add_child(cam)
		cam.global_position = Vector3(0.0, 13.5, 30.0)
		cam.look_at(Vector3(0.0, 12.5, 0.0), Vector3.UP)
		cam.current = true
	if _frames < 80:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/pylon.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("neon pylon capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
