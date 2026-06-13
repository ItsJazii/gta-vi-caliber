extends SceneTree
## Close-up capture harness for the playable car body.
## Run with a renderer, not --headless:
##   SHOT=/tmp/car.png VIEW=front godot --path game --script res://tests/car_capture.gd
## CAR_SCENE=res://scenes/vehicles/coastal_sport_coupe.tscn selects a variant.
## VIEW=front|rear|threequarter picks the camera. The car is frozen at the origin
## so the lofted body + emissive head/tail lights can be reviewed by pixel.

const CAR_SCENE := "res://scenes/vehicles/coastal_sport_coupe.tscn"

var _frames := 0
var _setup_done := false


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	var scene_path := OS.get_environment("CAR_SCENE")
	if scene_path.is_empty():
		scene_path = CAR_SCENE
	change_scene_to_file(scene_path)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _setup_done and _frames >= 3:
		_setup_capture()
	if _frames < 60:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/car.png"
	var image := root.get_texture().get_image()
	if _is_blank(image):
		push_error("car_capture: capture is blank")
		quit(1)
		return true
	image.save_png(path)
	print("car_capture: saved %s" % path)
	quit(0)
	return true


func _setup_capture() -> void:
	var car := current_scene as Node3D
	if car == null:
		push_error("car_capture: car scene is not active")
		quit(1)
		return
	# Freeze the VehicleBody3D so it does not roll or settle during the capture.
	if car is RigidBody3D:
		(car as RigidBody3D).freeze = true
	car.global_position = Vector3.ZERO

	var world := WorldEnvironment.new()
	var env := Environment.new()
	# A dusk sky doubles as backdrop and as the reflection source so chrome / glass
	# read like they will in-game (metals are black in a void with nothing to mirror).
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.15, 0.26)
	sky_mat.sky_horizon_color = Color(0.5, 0.32, 0.42)
	sky_mat.ground_horizon_color = Color(0.32, 0.22, 0.28)
	sky_mat.ground_bottom_color = Color(0.06, 0.06, 0.08)
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.25
	world.environment = env
	car.add_child(world)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	car.add_child(key)

	var view := OS.get_environment("VIEW")
	var cam := Camera3D.new()
	cam.fov = 42.0
	var pos := Vector3(0.0, 1.3, -6.2)  # front
	if view == "rear":
		pos = Vector3(0.0, 1.3, 6.2)
	elif view == "threequarter":
		pos = Vector3(4.6, 1.9, -4.8)
	cam.look_at_from_position(pos, Vector3(0.0, 0.7, 0.0), Vector3.UP)
	car.add_child(cam)
	cam.make_current()
	_setup_done = true


func _is_blank(image: Image) -> bool:
	var total := 0.0
	var samples := 0
	for y in range(0, image.get_height(), 80):
		for x in range(0, image.get_width(), 80):
			total += image.get_pixel(x, y).get_luminance()
			samples += 1
	return samples == 0 or total / float(samples) < 0.01
