extends SceneTree
## Dev-only isolation shot of AirBanner — frames the plane broadside (radius 0 so
## it holds still) to judge the aircraft form, the trailing banner orientation,
## and that the satirical ad reads. Run WINDOWED:
##   SHOT=/tmp/banner.png godot --path game --script res://tests/air_banner_capture.gd

var _frames := 0
var _banner: AirBanner


func _initialize() -> void:
	_banner = AirBanner.new()
	_banner.centre = Vector3(0.0, 40.0, 0.0)
	_banner.radius = 0.0
	_banner.count = 1
	root.add_child(_banner)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, 25.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.95, 0.85)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.46, 0.63, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.85)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	_banner._apply(0.0)
	# Pin the plane facing +z at the origin so the banner trails straight -z and
	# the side camera reads it (radius 0 still leaves a random heading otherwise).
	var plane := _banner.get_child(0) as Node3D
	plane.position = Vector3(0.0, 40.0, 0.0)
	plane.rotation = Vector3.ZERO
	if _frames == 20:
		var cam := Camera3D.new()
		cam.far = 3000.0
		cam.fov = 58.0
		root.add_child(cam)
		cam.global_position = Vector3(40.0, 40.5, -15.0)
		cam.look_at(Vector3(0.0, 40.0, -15.0), Vector3.UP)
		cam.current = true
	if _frames < 90:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/banner.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("air banner capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
