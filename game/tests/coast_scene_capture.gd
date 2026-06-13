extends SceneTree
## Dev-only verification: boots the REAL miami map, forces night, finds the
## FloridaBackdrop coastal cluster's actual (post-FloatingOrigin) world position
## at runtime, and frames it — to confirm the shipped coastal/neon elements
## really land in the live scene (not just in isolation). Run WINDOWED:
##   TARGET=NeonStrip SHOT=/tmp/coast.png godot --path game --script res://tests/coast_scene_capture.gd

var _frames := 0
var _framed := false


func _initialize() -> void:
	change_scene_to_file("res://scenes/world/miami.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 80:
		_force_night()
	# Let districts + backdrop build and FloatingOrigin settle before framing.
	if _frames == 220 and not _framed:
		_frame_target()
		_framed = true
	if _frames < 300:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/coast.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("coast scene capture: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true


func _force_night() -> void:
	RenderingServer.global_shader_parameter_set("world_night_amount", 1.0)
	for clock_name in ["DayNightCycle", "DayNight", "GameClock", "SkyController"]:
		var clock := root.find_child(clock_name, true, false)
		if clock != null and clock.has_method("set_time_of_day"):
			if "day_length_seconds" in clock:
				clock.day_length_seconds = 0.0
			clock.set_time_of_day(22.5)
			print("night: set_time_of_day on %s" % clock_name)
			return
	print("night: no clock with set_time_of_day found")


func _frame_target() -> void:
	var target := OS.get_environment("TARGET")
	if target == "":
		target = "NeonStrip"
	var node := root.find_child(target, true, false) as Node3D
	var look := Vector3(0, 6, 0)
	if node != null:
		look = node.global_position
		print("framed %s at %s" % [target, str(look)])
	else:
		print("target %s not found — framing origin" % target)
	var cam := Camera3D.new()
	cam.far = 6000.0
	cam.fov = 62.0
	root.add_child(cam)
	cam.global_position = look + Vector3(38.0, 9.0, 38.0)
	cam.look_at(look + Vector3(0.0, 2.0, 0.0), Vector3.UP)
	cam.current = true
