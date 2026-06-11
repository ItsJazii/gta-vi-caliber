extends SceneTree
## Beauty-shot harness (M6 capture tooling): runs a cinematic dolly through a
## scene and saves stills for quality review (docs/QUALITY.md workflow).
## Needs a renderer — run WITHOUT --headless:
##   godot --path game --script res://tests/beauty_capture.gd
## Optional env vars: BEAUTY_SCENE (res:// path), BEAUTY_SECONDS (duration).
## Stills land in /tmp/gta6_beauty/ every ~1.5 s of the move.

const OUT_DIR := "/tmp/gta6_beauty"
const DEFAULT_SCENE := "res://scenes/world/districts/downtown_la.tscn"
const WARMUP_FRAMES := 90
const STILL_INTERVAL_FRAMES := 90

var _frame := 0
var _shot_started := false
var _shot_done := false
var _still_index := 0
var _camera: CinematicCamera


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var scene := OS.get_environment("BEAUTY_SCENE")
	change_scene_to_file(scene if scene != "" else DEFAULT_SCENE)


func _process(_delta: float) -> bool:
	_frame += 1
	if not _shot_started:
		if _frame >= WARMUP_FRAMES:
			_start_shot()
		return false
	if _frame % STILL_INTERVAL_FRAMES == 0 and not _shot_done:
		_save_still()
	return _shot_done


func _start_shot() -> void:
	if OS.get_environment("BEAUTY_HIDE_HUD") == "1":
		_hide_hud(current_scene)
	_camera = CinematicCamera.new()
	_camera.far = 4000.0
	current_scene.add_child(_camera)
	var seconds := OS.get_environment("BEAUTY_SECONDS").to_float()
	if seconds <= 0.0:
		seconds = 12.0
	# Spiral descent: wide high establish → low street-level close on the core.
	# BEAUTY_CENTER="x,z" recenters the whole move (default 0,0 = downtown);
	# districts share one projection origin, so e.g. Venice is "-21050,6900".
	var center := Vector3.ZERO
	var center_env := OS.get_environment("BEAUTY_CENTER")
	if center_env.contains(","):
		var parts := center_env.split(",")
		center = Vector3(parts[0].to_float(), 0.0, parts[1].to_float())
	# BEAUTY_POINTS="x,y,z;x,y,z;..." + BEAUTY_LOOK="x,y,z" replace the whole
	# move for custom shots (e.g. a shoreline pan); both are absolute, the
	# center offset is not applied to them.
	var points := _env_points("BEAUTY_POINTS")
	var look := _env_vec3("BEAUTY_LOOK", center + Vector3(0.0, 40.0, 0.0))
	if points.is_empty():
		points = PackedVector3Array(
			[
				center + Vector3(420.0, 180.0, 0.0),
				center + Vector3(180.0, 110.0, 260.0),
				center + Vector3(-160.0, 60.0, 200.0),
				center + Vector3(-180.0, 25.0, -60.0),
				center + Vector3(-40.0, 8.0, -120.0),
			]
		)
	_camera.play_shot(points, seconds, look)
	_camera.shot_finished.connect(_on_shot_finished)
	_shot_started = true
	_frame = 0


func _hide_hud(root_node: Node) -> void:
	for child in root_node.get_children():
		if child is CanvasLayer or child is Control:
			(child as Node).set("visible", false)
		_hide_hud(child)


func _env_points(name: String) -> PackedVector3Array:
	var raw := OS.get_environment(name)
	var points := PackedVector3Array()
	if raw == "":
		return points
	for triple in raw.split(";", false):
		var parts := triple.split(",")
		if parts.size() == 3:
			points.append(Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()))
	return points


func _env_vec3(name: String, fallback: Vector3) -> Vector3:
	var pts := _env_points(name)
	return pts[0] if pts.size() == 1 else fallback


func _on_shot_finished() -> void:
	_save_still()
	print("beauty: done — %d stills in %s" % [_still_index, OUT_DIR])
	_shot_done = true
	quit(0)


func _save_still() -> void:
	var img := root.get_texture().get_image()
	var path := "%s/still_%02d.png" % [OUT_DIR, _still_index]
	img.save_png(path)
	print("beauty: saved %s" % path)
	_still_index += 1
