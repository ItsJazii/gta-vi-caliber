extends SceneTree
## Dev-only shot of CausewayTraffic on the real causeway deck — instances the
## deck builder (causeways.gd) + the traffic so cars ride the arched bridge.
## Defaults to NIGHT so the head/tail lights read. Run WINDOWED:
##   SHOT=/tmp/traffic.png godot --path game --script res://tests/causeway_traffic_capture.gd
## Env: DAY=1 for daylight.

const CAUSEWAYS_SCRIPT := preload("res://scripts/world/causeways.gd")

var _frames := 0
var _traffic: CausewayTraffic


func _initialize() -> void:
	var decks := Node3D.new()
	decks.set_script(CAUSEWAYS_SCRIPT)
	root.add_child(decks)

	_traffic = CausewayTraffic.new()
	root.add_child(_traffic)

	var night := OS.get_environment("DAY") != "1"
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, 40.0, 0.0)
	sun.light_energy = 0.1 if night else 1.2
	sun.light_color = Color(0.55, 0.65, 0.95) if night else Color(1.0, 0.95, 0.85)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.08) if night else Color(0.5, 0.68, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.06, 0.08, 0.14) if night else Color(0.6, 0.7, 0.85)
	env.ambient_light_energy = 0.35 if night else 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if night:
		env.glow_enabled = true
		env.glow_intensity = 0.8
		env.glow_bloom = 0.3
		env.glow_hdr_threshold = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	_traffic._apply(2.0)
	if _frames == 30:
		# Frame the MacArthur span midpoint (~3100, -480) from the side.
		var cam := Camera3D.new()
		cam.far = 4000.0
		cam.fov = 55.0
		root.add_child(cam)
		cam.global_position = Vector3(1150.0, 9.0, -230.0)
		cam.look_at(Vector3(1750.0, 7.0, -410.0), Vector3.UP)
		cam.current = true
	if _frames < 100:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/traffic.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("causeway traffic capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true
