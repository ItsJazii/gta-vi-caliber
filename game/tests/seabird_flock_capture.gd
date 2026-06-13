extends SceneTree
## Dev-only isolation shot of SeabirdFlock against the sky — judges the gull
## silhouette/flap before it's wired into the map. Run WINDOWED:
##   SHOT=/tmp/birds.png godot --path game --script res://tests/seabird_flock_capture.gd

var _frames := 0
var _flock: SeabirdFlock


func _initialize() -> void:
	_flock = SeabirdFlock.new()
	_flock.centre = Vector3(0.0, 0.0, 0.0)
	_flock.spread = 220.0
	_flock.count = 22
	_flock.altitude_min = 55.0
	_flock.altitude_max = 110.0
	root.add_child(_flock)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, 30.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.95, 0.85)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.85)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	# Advance the flock a little so wings are mid-flap and birds have spread.
	_flock._apply(1.4)
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 3000.0
		cam.fov = 60.0
		root.add_child(cam)
		cam.global_position = Vector3(0.0, 85.0, 250.0)
		cam.look_at(Vector3(0.0, 80.0, 0.0), Vector3.UP)
		cam.current = true
	if _frames < 90:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/birds.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("seabird flock capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
