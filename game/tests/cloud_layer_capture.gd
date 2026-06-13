extends SceneTree
## Dev-only isolation shot of CloudLayer over a warm ProceduralSky, framed from
## ground level looking up toward the horizon — judges whether the cloud sheet
## reads as broken cumulus (not a grey smear) before it's wired into the map.
## Run WINDOWED:
##   SHOT=/tmp/clouds.png COVER=0.42 godot --path game --script res://tests/cloud_layer_capture.gd
## Env: COVER (coverage 0..1), SHOT.

var _frames := 0


func _initialize() -> void:
	var clouds := MeshInstance3D.new()
	clouds.set_script(load("res://scripts/world/cloud_layer.gd"))
	clouds.set("coverage", _envf("COVER", 0.42))
	root.add_child(clouds)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-14.0, 35.0, 0.0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.82, 0.6)
	root.add_child(sun)

	# A warm dusk ProceduralSky like the miami grade, so the clouds are judged in
	# the context they'll actually live in.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.14, 0.24, 0.52)
	sky_mat.sky_horizon_color = Color(0.72, 0.44, 0.34)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var cam := Camera3D.new()
		cam.far = 20000.0
		cam.fov = 64.0
		root.add_child(cam)
		cam.global_position = Vector3(0.0, 3.0, 0.0)
		cam.look_at(Vector3(0.0, 240.0, -1400.0), Vector3.UP)
		cam.current = true
	if _frames < 150:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/clouds.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("cloud layer capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true


func _envf(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback
