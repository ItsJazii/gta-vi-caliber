extends SceneTree
## Dev-only isolation shot of the Pier over the real Ocean — judges the deck,
## pilings, railings, lamps and sea-end platform before it's wired into the map.
## Run WINDOWED:
##   SHOT=/tmp/pier.png godot --path game --script res://tests/pier_capture.gd

const OCEAN_SCRIPT := preload("res://scripts/world/ocean.gd")

var _frames := 0


func _initialize() -> void:
	var ocean := MeshInstance3D.new()
	ocean.set_script(OCEAN_SCRIPT)
	ocean.set("size_m", 600.0)
	ocean.set("resolution", 160)
	ocean.set("amplitude_scale", 0.6)
	ocean.set("shallow_color", Color(0.02, 0.68, 0.58))
	ocean.set("deep_color", Color(0.0, 0.08, 0.24))
	ocean.position.y = -0.18
	root.add_child(ocean)

	var pier := Pier.new()
	root.add_child(pier)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, 50.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.92, 0.78)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.74, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.85)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var cam := Camera3D.new()
		cam.far = 2000.0
		cam.fov = 60.0
		root.add_child(cam)
		cam.global_position = Vector3(34.0, 12.0, -16.0)
		cam.look_at(Vector3(0.0, 1.0, 55.0), Vector3.UP)
		cam.current = true
	if _frames < 110:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/pier.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("pier capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
