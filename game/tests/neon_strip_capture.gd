extends SceneTree
## Dev-only NIGHT shot of NeonStrip — dark env + glow so the rooflines, marquees
## and lit windows bloom into an Ocean Drive strip. Run WINDOWED:
##   SHOT=/tmp/strip.png godot --path game --script res://tests/neon_strip_capture.gd
## Env: DAY=1 for a daytime read instead.

var _frames := 0


func _initialize() -> void:
	var strip := NeonStrip.new()
	strip.line_x = 0.0
	strip.z_start = -40.0
	strip.z_end = 40.0
	strip.count = 5
	root.add_child(strip)

	var night := OS.get_environment("DAY") != "1"
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, 40.0, 0.0)
	sun.light_energy = 0.12 if night else 1.2
	sun.light_color = Color(0.6, 0.7, 0.95) if night else Color(1.0, 0.95, 0.85)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.06) if night else Color(0.5, 0.68, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.06, 0.07, 0.12) if night else Color(0.62, 0.72, 0.86)
	env.ambient_light_energy = 0.3 if night else 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if night:
		env.glow_enabled = true
		env.glow_intensity = 0.9
		env.glow_bloom = 0.35
		env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 800.0
		cam.fov = 60.0
		root.add_child(cam)
		cam.global_position = Vector3(40.0, 8.0, -44.0)
		cam.look_at(Vector3(8.0, 6.0, 6.0), Vector3.UP)
		cam.current = true
	if _frames < 90:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/strip.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("neon strip capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
