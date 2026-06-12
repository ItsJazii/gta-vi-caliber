extends SceneTree
## Dev-only isolation shot of BayBoats over the real Ocean — judges hull/sail
## form and that the fleet sits ON the water before it's wired into the map.
## Run WINDOWED:
##   SHOT=/tmp/boats.png godot --path game --script res://tests/bay_boats_capture.gd
## Env: SHOT, COUNT.

const OCEAN_SCRIPT := preload("res://scripts/world/ocean.gd")

var _frames := 0


func _initialize() -> void:
	var ocean := MeshInstance3D.new()
	ocean.set_script(OCEAN_SCRIPT)
	ocean.set("size_m", 1200.0)
	ocean.set("resolution", 240)
	ocean.set("amplitude_scale", 0.75)
	ocean.set("shallow_color", Color(0.02, 0.68, 0.58))
	ocean.set("deep_color", Color(0.0, 0.08, 0.24))
	ocean.position.y = -0.18
	root.add_child(ocean)

	var boats := BayBoats.new()
	boats.count = int(OS.get_environment("COUNT")) if OS.get_environment("COUNT") != "" else 18
	boats.area_min = Vector2(-120.0, -160.0)
	boats.area_max = Vector2(120.0, 40.0)
	boats.ocean_y = -0.18
	root.add_child(boats)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-22.0, 35.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.9, 0.75)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.66, 0.78, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var cam := Camera3D.new()
		cam.far = 3000.0
		cam.fov = 58.0
		root.add_child(cam)
		cam.global_position = Vector3(0.0, 7.0, 110.0)
		cam.look_at(Vector3(0.0, 1.0, -60.0), Vector3.UP)
		cam.current = true
	if _frames < 150:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/boats.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("bay boats capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
