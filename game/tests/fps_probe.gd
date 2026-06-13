extends SceneTree
## Sustained-FPS probe (M6 perf workflow). Boots a scene, lets streaming/effects
## settle, then averages Engine FPS over a window and prints it. Run WITHOUT
## --headless (needs the GPU):
##   SCENE=res://scenes/world/miami.tscn TOD=16.8 \
##   godot --path game --script res://tests/fps_probe.gd
## Env: SCENE, TOD (optional), WARMUP frames (default 400), SAMPLE frames (240).

var _frame := 0
var _accum := 0.0
var _samples := 0
var _warmup := 400
var _sample := 240


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	# Uncap from the display refresh so the probe measures real headroom.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_warmup = int(OS.get_environment("WARMUP")) if OS.get_environment("WARMUP") != "" else 400
	_sample = int(OS.get_environment("SAMPLE")) if OS.get_environment("SAMPLE") != "" else 240
	var scene := OS.get_environment("SCENE")
	if scene == "":
		scene = "res://scenes/world/miami.tscn"
	change_scene_to_file(scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 30:
		_force_tod()
	if _frame < _warmup:
		return false
	_accum += Engine.get_frames_per_second()
	_samples += 1
	if _samples < _sample:
		return false
	var avg := _accum / float(_samples)
	print("FPS_PROBE avg=%.1f over %d frames (warmup %d)" % [avg, _samples, _warmup])
	quit()
	return true


func _force_tod() -> void:
	var tod := OS.get_environment("TOD")
	if tod == "":
		return
	var cyc := root.find_child("DayNightCycle", true, false)
	if cyc != null and cyc.has_method("set_time_of_day"):
		if "day_length_seconds" in cyc:
			cyc.day_length_seconds = 0.0
		cyc.set_time_of_day(float(tod))
