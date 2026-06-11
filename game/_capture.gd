extends SceneTree
## Dev-only screenshot tool. Run windowed (NOT headless) so the GPU renders:
##   SHOT=/tmp/x.png TOD=18.5 PITCH=12 godot --path game --script res://_capture.gd
## Boots the sandbox, optionally forces a time of day and tilts the camera up to
## frame the sky, lets it settle, saves one PNG, quits. With no env vars set it
## behaves as before (boot, settle, shoot /tmp/gta6_shot.png).

var _frames := 0


func _initialize() -> void:
	var scene := OS.get_environment("SCENE")
	if scene == "":
		scene = "res://scenes/world/sandbox.tscn"
	change_scene_to_file(scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		_setup()
	if _frames < 150:
		return false
	var path := OS.get_environment("SHOT")
	if path == "":
		path = "/tmp/gta6_shot.png"
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("captured: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	quit()
	return true


func _setup() -> void:
	var tod := OS.get_environment("TOD")
	if tod != "":
		var cyc := root.find_child("DayNightCycle", true, false)
		if cyc != null:
			cyc.day_length_seconds = 0.0
			cyc.set_time_of_day(float(tod))
			print("capture: set time_of_day=%s on %s" % [tod, cyc.get_path()])
		else:
			print("capture: WARNING DayNightCycle not found")
	# Tilt the active camera upward so the frame is mostly sky.
	var pitch := OS.get_environment("PITCH")
	if pitch != "":
		var cam := root.get_viewport().get_camera_3d()
		if cam != null:
			cam.rotation.x = deg_to_rad(float(pitch))
