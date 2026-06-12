extends SceneTree
## Dev-only NIGHT shot of NeonSign — dark env with glow on, so the neon border +
## text bloom like real tubes. Judges the Vice City night-sign read. Run WINDOWED:
##   SHOT=/tmp/neon.png godot --path game --script res://tests/neon_sign_capture.gd

var _frames := 0


func _initialize() -> void:
	var sign := NeonSign.new()
	root.add_child(sign)

	# Faint moonlight only — the sign should carry itself.
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	moon.light_energy = 0.12
	moon.light_color = Color(0.6, 0.7, 0.95)
	root.add_child(moon)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.1)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.4
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 800.0
		cam.fov = 48.0
		root.add_child(cam)
		cam.global_position = Vector3(0.0, 9.5, 34.0)
		cam.look_at(Vector3(0.0, 9.5, 0.0), Vector3.UP)
		cam.current = true
	if _frames < 90:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/neon.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("neon sign capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
