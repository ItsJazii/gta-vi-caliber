extends SceneTree
## Close-up capture harness for the playable Mara character.
## Run with a renderer, not --headless:
##   SHOT=/tmp/mara_player.png godot --path game --script res://tests/player_mara_capture.gd
## Optional VIEW=front|rear|inspect captures a fixed front/rear camera or the
## actual player CameraRig character-inspection mode. Optional POSE=run settles
## the animated procedural rig into a moving pose for character-motion review.
## Set PROCEDURAL=1 to force the all-angle playable rig for front face review.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _frames := 0
var _setup_done := false


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 1600))
	change_scene_to_file(PLAYER_SCENE)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _setup_done and _frames >= 3:
		_setup_capture()
	if _frames < 120:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/mara_player.png"
	var image := root.get_texture().get_image()
	if _is_blank(image):
		_fail("capture is blank")
		return true
	image.save_png(path)
	print("player_mara_capture: saved %s" % path)
	quit(0)
	return true


func _setup_capture() -> void:
	var host := current_scene as Node3D
	if host == null:
		_fail("player scene is not active")
		return
	_stabilize_player_for_capture(host)
	if OS.get_environment("PROCEDURAL") == "1":
		_force_procedural_mara(host)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.42, 0.48)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.12
	world.environment = env
	host.add_child(world)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_energy = 2.4
	key.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	host.add_child(key)

	var rim := OmniLight3D.new()
	rim.name = "RimLight"
	rim.light_energy = 1.4
	rim.omni_range = 5.0
	rim.position = Vector3(-1.5, 1.8, 1.8)
	host.add_child(rim)

	var view := OS.get_environment("VIEW")
	if view == "inspect":
		var camera_rig := host.get_node_or_null("CameraRig") as OrbitCamera
		if camera_rig == null:
			_fail("player CameraRig is missing")
			return
		camera_rig.set_character_inspect(true)
		camera_rig.make_current()
	else:
		var camera := Camera3D.new()
		camera.name = "Camera"
		camera.fov = 34.0
		var z := 4.2 if view == "rear" else -4.2
		camera.look_at_from_position(Vector3(0.0, 1.12, z), Vector3(0.0, 0.98, 0.0), Vector3.UP)
		host.add_child(camera)
		camera.make_current()
	_setup_done = true


func _stabilize_player_for_capture(host: Node3D) -> void:
	host.global_position = Vector3.ZERO
	host.set_physics_process(false)
	var body := host as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
	var rig := host.get_node_or_null("Rig")
	if rig != null and rig.has_method("animate"):
		var planar := (
			Vector3(5.0, 0.0, 0.0) if OS.get_environment("POSE") == "run" else Vector3.ZERO
		)
		for i in 40:
			rig.call("animate", planar, true, 0.0, false, 1.0 / 60.0)


func _force_procedural_mara(host: Node3D) -> void:
	var body := host.get_node_or_null("Rig/Body")
	var rig := host.get_node_or_null("Rig")
	if body == null or rig == null:
		return
	body.set("hide_procedural_when_imported", false)
	body.set("switch_imported_mara_by_camera", false)
	body.call("_set_imported_visual_active", false)
	body.call("_set_procedural_visible", rig, true)


func _is_blank(image: Image) -> bool:
	var total := 0.0
	var samples := 0
	for y in range(0, image.get_height(), 80):
		for x in range(0, image.get_width(), 80):
			total += image.get_pixel(x, y).get_luminance()
			samples += 1
	return samples == 0 or total / float(samples) < 0.01


func _fail(message: String) -> void:
	push_error("player_mara_capture: %s" % message)
	quit(1)
