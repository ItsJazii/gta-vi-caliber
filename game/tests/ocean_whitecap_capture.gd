extends SceneTree
## Dev-only visual QA shot of the Ocean shader's open-water whitecaps (Ocean v2).
## Isolates the water from the full miami scene so the Gerstner-Jacobian foam
## can be judged by eye at a low, golden-hour grazing angle. Run WINDOWED:
##   SHOT=/tmp/ocean.png godot --path game --script res://tests/ocean_whitecap_capture.gd
## Env knobs: WCAP (whitecap_strength), WCOV (whitecap_coverage), AMP, SHOT.

const OCEAN_SCRIPT := preload("res://scripts/world/ocean.gd")

var _frames := 0


func _initialize() -> void:
	var ocean := MeshInstance3D.new()
	ocean.set_script(OCEAN_SCRIPT)
	ocean.set("size_m", 1400.0)
	ocean.set("resolution", 320)
	ocean.set("amplitude_scale", _envf("AMP", 0.75))
	ocean.set("wave_speed", 0.78)
	ocean.set("shallow_color", Color(0.02, 0.68, 0.58))
	ocean.set("deep_color", Color(0.0, 0.08, 0.24))
	ocean.set("horizon_color", Color(0.10, 0.34, 0.55))
	ocean.set("absorption_per_m", 0.2)
	ocean.set("surface_roughness", 0.045)
	ocean.set("foam_strength", 0.18)
	ocean.set("whitecap_strength", _envf("WCAP", 0.6))
	ocean.set("whitecap_coverage", _envf("WCOV", 1.0))
	root.add_child(ocean)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-12.0, 35.0, 0.0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.82, 0.62)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.6, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		_setup_cam()
	if _frames < 180:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/ocean.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("ocean whitecap capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true


func _setup_cam() -> void:
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.global_position = Vector3(0.0, 6.0, 120.0)
	cam.look_at(Vector3(40.0, 0.0, -400.0), Vector3.UP)
	cam.current = true


func _envf(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback
