extends SceneTree
## Asset-pipeline proof of concept: a FICTIONAL tower generated on a real OSM
## footprint (Buildify-dressed massing, ambientCG facades — see the art policy
## in docs/ASSET_PIPELINE.md) standing in a scratch scene built entirely here.
## The live miami scene is not touched.
## Run with a renderer, not --headless:
##   SHOT_DIR=session_captures/building_poc godot --path game --script res://tests/building_poc_capture.gd
## Saves street-level day/night shots plus a facade close-up for each.

const BUILDING_GLB := "res://assets/buildings/poc_bayfront_tower.glb"
const GROUND_SET := "res://assets/materials/asphalt_street_01"
const SETTLE_FRAMES := 20

var _frames := 0
var _shot_index := 0
var _shot_armed := false
var _failed := false
var _env: Environment
var _sun: DirectionalLight3D
var _camera: Camera3D

## Each entry: [shot name, day?, camera position, look-at target].
var _shots: Array = [
	["01_street_day", true, Vector3(12.0, 1.7, 78.0), Vector3(0.0, 24.0, 0.0)],
	["02_facade_closeup_day", true, Vector3(22.0, 1.7, 40.0), Vector3(4.0, 16.0, 0.0)],
	["03_street_night", false, Vector3(12.0, 1.7, 78.0), Vector3(0.0, 24.0, 0.0)],
	["04_facade_closeup_night", false, Vector3(22.0, 1.7, 40.0), Vector3(4.0, 16.0, 0.0)],
]


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	root.add_child(_build_scene())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % SETTLE_FRAMES != 0:
		return false
	if _shot_index >= _shots.size():
		quit(1 if _failed else 0)
		return true
	var shot: Array = _shots[_shot_index]
	if not _shot_armed:
		# set up the shot, then let it settle for one window before saving
		_apply_lighting(shot[1])
		_camera.look_at_from_position(shot[2], shot[3], Vector3.UP)
		_shot_armed = true
		return false
	_save_shot(shot[0])
	_shot_armed = false
	_shot_index += 1
	return false


func _build_scene() -> Node3D:
	var scene := Node3D.new()
	scene.name = "BuildingPocScratch"

	var building_scene := load(BUILDING_GLB) as PackedScene
	if building_scene == null:
		push_error("building_poc_capture: cannot load %s" % BUILDING_GLB)
		_failed = true
	else:
		scene.add_child(building_scene.instantiate())

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(500.0, 500.0)
	ground.mesh = plane
	ground.material_override = PbrMaterial.from_set(GROUND_SET, true, 1.0 / 6.0)
	scene.add_child(ground)

	_sun = DirectionalLight3D.new()
	scene.add_child(_sun)

	var world := WorldEnvironment.new()
	_env = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.2
	world.environment = _env
	scene.add_child(world)

	_camera = Camera3D.new()
	_camera.fov = 65.0
	scene.add_child(_camera)
	_camera.make_current()
	return scene


func _apply_lighting(day: bool) -> void:
	# In the live game, window emission rides world_night_amount (see
	# building_windows.gdshader); the scratch scene mimics that by gating
	# the imported material's emission energy on the time of day.
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null and mat.emission_enabled:
				mat.emission_energy_multiplier = 0.0 if day else 1.0
	var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
	_env.glow_enabled = not day  # daylight + bloom veils the whole frame white
	if day:
		sky_mat.sky_top_color = Color(0.25, 0.45, 0.78)
		sky_mat.sky_horizon_color = Color(0.74, 0.82, 0.92)
		sky_mat.ground_horizon_color = Color(0.66, 0.68, 0.66)
		sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.2)
		_sun.light_energy = 1.0
		_sun.rotation_degrees = Vector3(-50.0, 38.0, 0.0)
		_env.ambient_light_energy = 0.45
	else:
		sky_mat.sky_top_color = Color(0.01, 0.015, 0.04)
		sky_mat.sky_horizon_color = Color(0.05, 0.04, 0.09)
		sky_mat.ground_horizon_color = Color(0.04, 0.03, 0.06)
		sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
		_sun.light_energy = 0.05
		_sun.rotation_degrees = Vector3(-30.0, -120.0, 0.0)
		_env.ambient_light_energy = 0.25


func _save_shot(name: String) -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "/tmp/building_poc"
	DirAccess.make_dir_recursive_absolute(dir)
	var image := root.get_texture().get_image()
	if _is_blank(image):
		push_error("building_poc_capture: %s is blank" % name)
		_failed = true
	var path := "%s/%s.png" % [dir, name]
	image.save_png(path)
	print("building_poc_capture: saved %s" % path)


func _is_blank(image: Image) -> bool:
	var total := 0.0
	var samples := 0
	for y in range(0, image.get_height(), 80):
		for x in range(0, image.get_width(), 80):
			total += image.get_pixel(x, y).get_luminance()
			samples += 1
	return samples == 0 or total / float(samples) < 0.005
