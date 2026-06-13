extends SceneTree
## Dev-only shot of AdBlimp, pinned broadside so the flank ad reads. Run WINDOWED:
##   SHOT=/tmp/blimp.png godot --path game --script res://tests/ad_blimp_capture.gd

var _frames := 0
var _blimp: AdBlimp


func _initialize() -> void:
	_blimp = AdBlimp.new()
	_blimp.centre = Vector3(0.0, 0.0, 0.0)
	_blimp.radius = 0.0
	root.add_child(_blimp)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24.0, 35.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.9, 0.75)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.7, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	_blimp._apply(0.0)
	_blimp.position = Vector3.ZERO
	_blimp.rotation = Vector3.ZERO
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 800.0
		cam.fov = 52.0
		root.add_child(cam)
		cam.global_position = Vector3(62.0, 4.0, -2.0)
		cam.look_at(Vector3(0.0, 0.0, -2.0), Vector3.UP)
		cam.current = true
	if _frames < 80:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/blimp.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("ad blimp capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
